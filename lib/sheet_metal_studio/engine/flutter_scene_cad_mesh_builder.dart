import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../models/cad_primitives.dart';
import '../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'cad_polygon_triangulator.dart';
import 'kinematic_fold_engine.dart';

/// Hardware-accelerated Flutter GPU / Impeller Multi-Pass CAD Mesh Builder for TruFold Studio.
/// Implements:
/// - Pass 1A: Smooth-Normal Inverted-Hull Outer Silhouette Mesh (`depthLayer = 0`, back-face hull)
/// - Pass 1B: Hardware Z-Buffer Depth-Tested 3D Topological Crease & Hole-Rim Mesh (`depthLayer = 0`, +0.18mm normal bias)
/// - Pass 2:  Onshape Studio 3-Light Hemisphere + Step-Quantized Toon/Cel-Shading Hybrid + Crevice AO
class FlutterSceneCadMeshBuilder {
  /// Converts an sRGB channel [0..1] to Linear RGB for physically based rendering.
  static double _srgbToLinear(double s) {
    final c = s.clamp(0.0, 1.0);
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Smooth Hermite interpolation (GLSL `smoothstep` equivalent) for anti-aliased Toon/Cel step bands.
  static double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  /// Quantizes continuous diffuse lighting [0..1] into 3 crisp, anti-aliased Toon / Cel-Shaded CAD bands:
  /// Band 0 (Core Shadow: 0.50) -> Band 1 (Midtone: 0.80) -> Band 2 (Key-Lit Face: 1.06)
  static double _quantizeToonLightingStep(double wrapKey) {
    final band1 = _smoothstep(0.24, 0.30, wrapKey);
    final band2 = _smoothstep(0.64, 0.70, wrapKey);
    return (0.50 + band1 * 0.30 + band2 * 0.26);
  }

  /// Computes Onshape Studio 3-Light + Toon Step-Shading Hybrid + Crevice AO Linear RGB color for a face.
  /// Works for BOTH default Onshape CAD colors AND custom per-part colors (`partColorOverrides`)!
  static vm.Vector4 computeOnshapeStudioFaceColor({
    required CadFoldedPolygon3D poly,
    required Color baseSrgbColor,
    required OnshapeGraphicsPreferences preferences,
    required bool isHovered,
  }) {
    if (isHovered) {
      return vm.Vector4(_srgbToLinear(0.73), _srgbToLinear(0.90), _srgbToLinear(0.99), 1.0);
    }

    // 1. Normalize face normal
    final n = poly.normal;
    final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
    final nx = lenN > 1e-6 ? n.x / lenN : 0.0;
    final ny = lenN > 1e-6 ? n.y / lenN : 0.0;
    final nz = lenN > 1e-6 ? n.z / lenN : 1.0;

    // 2. Studio 3-Light Rig + Cool Sky / Warm Ground Hemisphere
    const lKeyX = -0.42, lKeyY = -0.58, lKeyZ = 0.70;
    const lFillX = 0.60, lFillY = 0.45, lFillZ = -0.66;
    const lRimX = 0.25, lRimY = 0.78, lRimZ = 0.57;

    final dotKey = (nx * lKeyX + ny * lKeyY + nz * lKeyZ).clamp(0.0, 1.0);
    final wrapKey = ((nx * lKeyX + ny * lKeyY + nz * lKeyZ + 0.35) / 1.35).clamp(0.0, 1.0);
    final dotFill = (nx * lFillX + ny * lFillY + nz * lFillZ).clamp(0.0, 1.0);
    final dotRim = (nx * lRimX + ny * lRimY + nz * lRimZ).clamp(0.0, 1.0);

    // Sky-to-ground hemisphere gradient along Z-up
    final hemi = (nz * 0.5 + 0.5); // 1.0 facing sky, 0.0 facing ground
    final hemiTone = 0.52 + 0.22 * hemi;

    // Smooth Onshape Studio directional tone
    final smoothTone =
        hemiTone + wrapKey * 0.34 + dotKey * 0.14 + dotFill * (preferences.hasSecondaryLight ? 0.14 : 0.04) + dotRim * (preferences.hasBackLight ? 0.10 : 0.03);

    // Step-Quantized Toon / Cel-Shaded tone + stepped specular highlight band
    final steppedTone = _quantizeToonLightingStep(wrapKey) + (_smoothstep(0.76, 0.82, dotKey) * 0.10);

    // Blend between Smooth Studio and Step-Shaded Toon based on active lighting preset:
    // - engineeringCrisp ("Toon / Blueprint"): 85% step-quantized cel-shading
    // - onshapeStudio ("Onshape SS3"): 22% subtle step definition + 78% smooth studio gradient
    final double toonStepMix = switch (preferences.lightingPreset) {
      CadLightingPreset.engineeringCrisp => 0.85,
      CadLightingPreset.onshapeStudio => 0.22,
      CadLightingPreset.clayPresentation => 0.10,
      CadLightingPreset.metallicShowroom => 0.30,
    };

    final double directionalTone = smoothTone * (1.0 - toonStepMix) + steppedTone * toonStepMix;

    // 3. Topological Crevice & Feature Ambient Occlusion Multiplier
    final aoStrength = (preferences.ambientOcclusion / 100.0).clamp(0.0, 1.0);
    final cavityRatio = (preferences.cavityStrength / 100.0).clamp(0.0, 1.0);
    final combinedAo = ((aoStrength * 0.65) + (cavityRatio * 0.35)).clamp(0.0, 1.0);

    final fid = poly.faceId;
    double featureAo = 1.0;

    if (fid.startsWith('BORE_') || fid.contains('_bore_')) {
      featureAo = 1.0 - (0.40 * combinedAo);
    } else if (fid.contains('_inner_web')) {
      featureAo = 1.0 - (0.30 * combinedAo);
    } else if (fid.contains('_inner_flange')) {
      featureAo = 1.0 - (0.24 * combinedAo);
    } else if (fid.startsWith('RIM_') || fid.contains('_rim_') || fid.contains('_end_cap_')) {
      featureAo = 1.0 - (0.18 * combinedAo);
    } else if (fid.endsWith('_BOT') || fid.contains('flange_bottom')) {
      featureAo = 1.0 - (0.15 * combinedAo);
    }

    final finalSrgbScale = (directionalTone * featureAo).clamp(0.28, 1.10);

    // Subtle cool sky tint on upward faces, warm slate on downward crevices
    final rSrgb = (baseSrgbColor.r * finalSrgbScale * (0.98 + 0.02 * (1.0 - hemi))).clamp(0.0, 1.0);
    final gSrgb = (baseSrgbColor.g * finalSrgbScale).clamp(0.0, 1.0);
    final bSrgb = (baseSrgbColor.b * finalSrgbScale * (0.97 + 0.05 * hemi)).clamp(0.0, 1.0);

    // Convert sRGB -> Linear RGB so ACES tone mapping doesn't wash out colors to white!
    return vm.Vector4(_srgbToLinear(rSrgb), _srgbToLinear(gSrgb), _srgbToLinear(bSrgb), 1.0);
  }

  /// Pass 1A: Builds an In-Engine 3D Inverted-Hull Outer Silhouette Node on `depthLayer = 0`.
  /// - Averages vertex normals across shared 90° corners so corners expand uniformly without splitting open.
  /// - Extrudes vertices outward along their smooth normal by [hullThicknessMm].
  /// - Emits reversed triangle winding (`0, 2, 1`) with `doubleSided = false` (front-face culled)
  ///   so only the outer silhouette contour pokes out around the 3D part, 100% depth-tested by the GPU Z-buffer!
  static Node? buildInvertedHullOutlineNode(
    FoldedMeshResult meshResult, {
    required CadPoint3D pivot,
    required double hullThicknessMm,
    required Color outlineSrgbColor,
    required SectionViewConfig sectionViewConfig,
    Set<String> hiddenPartIds = const {},
    Set<String> isolatedPartIds = const {},
  }) {
    final smoothNormals = <String, vm.Vector3>{};
    String vKey(CadPoint3D p) => '${(p.x * 100).round()}_${(p.y * 100).round()}_${(p.z * 100).round()}';

    for (final poly in meshResult.allPolygons) {
      if (poly.vertices.length < 3) continue;
      if (poly.faceId.startsWith('WELD_')) continue;
      if (poly.faceId.contains('_inner') || poly.faceId.contains('_bore') || poly.faceId.startsWith('BORE_')) {
        continue;
      }
      final partId = SheetMetalStudioViewModel.extractPartIdFromFaceId(poly.faceId);
      if (hiddenPartIds.contains(partId)) continue;
      if (isolatedPartIds.isNotEmpty && !isolatedPartIds.contains(partId)) continue;

      final n = poly.normal;
      final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
      if (lenN <= 1e-6) continue;
      final fn = vm.Vector3(n.x / lenN, n.y / lenN, n.z / lenN);

      for (final v in poly.vertices) {
        final k = vKey(v);
        final prev = smoothNormals[k];
        smoothNormals[k] = prev == null ? fn.clone() : (prev + fn);
      }
    }

    if (smoothNormals.isEmpty) return null;
    for (final v in smoothNormals.values) {
      if (v.length2 > 1e-6) v.normalize();
    }

    final hullBuilder = GeometryBuilder(deduplicate: false);
    final linearOutline = vm.Vector4(_srgbToLinear(outlineSrgbColor.r), _srgbToLinear(outlineSrgbColor.g), _srgbToLinear(outlineSrgbColor.b), 1.0);
    hullBuilder.color(linearOutline);

    for (final poly in meshResult.allPolygons) {
      if (poly.vertices.length != 4 || poly.holes.isNotEmpty) continue;
      if (poly.faceId.startsWith('WELD_')) continue;
      if (poly.faceId.contains('_inner') || poly.faceId.contains('_bore') || poly.faceId.startsWith('BORE_')) {
        continue;
      }
      final partId = SheetMetalStudioViewModel.extractPartIdFromFaceId(poly.faceId);
      if (hiddenPartIds.contains(partId)) continue;
      if (isolatedPartIds.isNotEmpty && !isolatedPartIds.contains(partId)) continue;

      if (sectionViewConfig.isEnabled) {
        double cx = 0, cy = 0, cz = 0;
        for (final v in poly.vertices) {
          cx += v.x - pivot.x;
          cy += v.y - pivot.y;
          cz += v.z - pivot.z;
        }
        cx /= poly.vertices.length;
        cy /= poly.vertices.length;
        cz /= poly.vertices.length;
        final double planeVal = switch (sectionViewConfig.axis) {
          SectionPlaneAxis.yz => cx,
          SectionPlaneAxis.zx => cy,
          SectionPlaneAxis.xy => cz,
        };
        final double dist = planeVal - sectionViewConfig.distanceOffsetMm;
        final bool isClipped = sectionViewConfig.flipNormal ? (dist < 0.0) : (dist > 0.0);
        if (isClipped) continue;
      }

      hullBuilder.normal(vm.Vector3(0, 0, -1));
      final v0 = poly.vertices[0];
      final v1 = poly.vertices[1];
      final v2 = poly.vertices[2];
      final v3 = poly.vertices[3];
      final sn0 = smoothNormals[vKey(v0)] ?? vm.Vector3(0, 0, 1);
      final sn1 = smoothNormals[vKey(v1)] ?? vm.Vector3(0, 0, 1);
      final sn2 = smoothNormals[vKey(v2)] ?? vm.Vector3(0, 0, 1);
      final sn3 = smoothNormals[vKey(v3)] ?? vm.Vector3(0, 0, 1);

      final i0 = hullBuilder.addVertex(
        vm.Vector3((v0.x + sn0.x * hullThicknessMm) - pivot.x, (v0.y + sn0.y * hullThicknessMm) - pivot.y, (v0.z + sn0.z * hullThicknessMm) - pivot.z),
      );
      final i1 = hullBuilder.addVertex(
        vm.Vector3((v1.x + sn1.x * hullThicknessMm) - pivot.x, (v1.y + sn1.y * hullThicknessMm) - pivot.y, (v1.z + sn1.z * hullThicknessMm) - pivot.z),
      );
      final i2 = hullBuilder.addVertex(
        vm.Vector3((v2.x + sn2.x * hullThicknessMm) - pivot.x, (v2.y + sn2.y * hullThicknessMm) - pivot.y, (v2.z + sn2.z * hullThicknessMm) - pivot.z),
      );
      final i3 = hullBuilder.addVertex(
        vm.Vector3((v3.x + sn3.x * hullThicknessMm) - pivot.x, (v3.y + sn3.y * hullThicknessMm) - pivot.y, (v3.z + sn3.z * hullThicknessMm) - pivot.z),
      );

      // Emit REVERSED winding (0, 2, 1) and (0, 3, 2) so front faces are culled
      // and only the back-face silhouette rim is visible around the solid part!
      hullBuilder.addTriangle(i0, i2, i1);
      hullBuilder.addTriangle(i0, i3, i2);
    }

    if (hullBuilder.triangleCount == 0) return null;

    final hullMat = UnlitMaterial()
      ..doubleSided =
          false // Front-face culling active!
      ..depthLayer =
          0 // Shares hardware Z-buffer with SolidCadBody!
      ..baseColorFactor = linearOutline;

    return Node(
      name: 'CadInvertedHullOutline',
      mesh: Mesh(hullBuilder.build(storage: GeometryStorage.fixed), hullMat),
    );
  }

  /// Builds a complete 3D CAD scene node from a folded sheet metal mesh.
  static Node buildCadModel(
    FoldedMeshResult meshResult, {
    String? selectedFaceId,
    String? hoveredFaceId,
    bool showWireframe = true,
    Color? baseColorOverride,
    Material? customMaterial,
    OnshapeGraphicsPreferences preferences = const OnshapeGraphicsPreferences(),
    OnshapeRenderMode renderMode = OnshapeRenderMode.shadedWithEdges,
    Set<String> hiddenPartIds = const {},
    Set<String> isolatedPartIds = const {},
    Set<String> transparentPartIds = const {},
    SectionViewConfig sectionViewConfig = const SectionViewConfig(),
    Map<String, Color> partColorOverrides = const {},
    CadPoint3D? pivotOverride,
  }) {
    final rootNode = Node(name: 'CadModelRoot');
    final pivot = pivotOverride ?? meshResult.center;

    final opaqueBuilder = GeometryBuilder(deduplicate: false);
    final translucentBuilder = GeometryBuilder(deduplicate: false);

    // Collect outer boundary & hole rim segments WITH their parent face normal so we can apply
    // a +0.18mm outward corner-bisector normal bias for hardware Z-buffer depth testing on depthLayer = 0!
    final List<(CadPoint3D, CadPoint3D, CadPoint3D)> rawBoundarySegs = [];
    final List<double> edgePositions = [];

    final bool shouldDrawWireframe = showWireframe && renderMode != OnshapeRenderMode.shadedWithoutEdges && preferences.lineWidth > 0.05;

    // Collect tangent seam edges (fillet transitions) with face normal offset
    final List<double> tangentPositions = [];
    final bool shouldDrawTangents = preferences.tangentEdgeMode != OnshapeTangentEdgeMode.removed;

    final bool isWireframeOnly = renderMode == OnshapeRenderMode.unshaded;
    final bool isGlobalTranslucent = renderMode == OnshapeRenderMode.translucent;

    for (final poly in meshResult.allPolygons) {
      if (poly.vertices.length < 3) continue;

      final partId = SheetMetalStudioViewModel.extractPartIdFromFaceId(poly.faceId);
      if (hiddenPartIds.contains(partId)) continue;
      if (isolatedPartIds.isNotEmpty && !isolatedPartIds.contains(partId)) continue;

      if (sectionViewConfig.isEnabled) {
        double cx = 0, cy = 0, cz = 0;
        for (final v in poly.vertices) {
          cx += v.x - pivot.x;
          cy += v.y - pivot.y;
          cz += v.z - pivot.z;
        }
        cx /= poly.vertices.length;
        cy /= poly.vertices.length;
        cz /= poly.vertices.length;

        final double planeVal = switch (sectionViewConfig.axis) {
          SectionPlaneAxis.yz => cx,
          SectionPlaneAxis.zx => cy,
          SectionPlaneAxis.xy => cz,
        };
        final double dist = planeVal - sectionViewConfig.distanceOffsetMm;
        final bool isClipped = sectionViewConfig.flipNormal ? (dist < 0.0) : (dist > 0.0);
        if (isClipped) continue;
      }

      final isHovered = poly.faceId == hoveredFaceId;
      final isWeld = poly.faceId.startsWith('WELD_');
      final isPartTranslucent = isGlobalTranslucent || transparentPartIds.contains(partId);
      final currentBuilder = isPartTranslucent ? translucentBuilder : opaqueBuilder;

      // Resolve base sRGB color for this part/face, then apply Onshape Studio + Toon Step-Shading + Crevice AO!
      vm.Vector4 faceColor;
      if (isWeld) {
        faceColor = vm.Vector4(_srgbToLinear(poly.color.r), _srgbToLinear(poly.color.g), _srgbToLinear(poly.color.b), poly.color.a);
      } else {
        Color baseSrgb = const Color(0xFF6C9DC6); // Authentic Onshape SS3 Cerulean Steel-Blue
        if (baseColorOverride != null) {
          baseSrgb = baseColorOverride;
        } else if (partColorOverrides.containsKey(partId)) {
          baseSrgb = partColorOverrides[partId]!;
        } else if (!preferences.useOnshapeCadColor) {
          baseSrgb = preferences.materialSettings.baseColor;
        }
        faceColor = computeOnshapeStudioFaceColor(poly: poly, baseSrgbColor: baseSrgb, preferences: preferences, isHovered: isHovered);
      }

      currentBuilder.color(faceColor);

      // Normal
      final n = poly.normal;
      final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
      final normVec = lenN > 1e-6 ? vm.Vector3(n.x / lenN, n.y / lenN, n.z / lenN) : vm.Vector3(0, 0, 1);
      currentBuilder.normal(normVec);

      // Triangulate outer polygon with interior cutout holes & vertex crevice AO
      CadPolygonTriangulator.triangulateToBuilder(
        outerVertices: poly.vertices,
        holes: poly.holes,
        normal: poly.normal,
        pivot: pivot,
        builder: currentBuilder,
        baseLinearColor: faceColor,
        creviceAoStrength: (preferences.ambientOcclusion / 100.0).clamp(0.0, 1.0),
        isInnerOrWebFace: poly.faceId.contains('_inner') || poly.faceId.contains('_web') || poly.faceId.contains('flange'),
      );

      // Collect wireframe / boundary / hole rim segments with parent face normal
      final isInternalFace =
          poly.faceId.startsWith('BORE_') ||
          poly.faceId.startsWith('RIM_') ||
          poly.faceId.startsWith('CHAMFER_') ||
          poly.faceId.contains('_rim_') ||
          poly.faceId.contains('_end_cap_') ||
          poly.faceId.contains('_bore_');

      final faceNorm = CadPoint3D(normVec.x, normVec.y, normVec.z);

      if (shouldDrawTangents && poly.faceId.startsWith('FILLET_') && poly.vertices.length >= 4) {
        const double tBias = 0.18;
        final v0 = poly.vertices[0];
        final v1 = poly.vertices[1];
        tangentPositions.addAll([
          (v0.x + faceNorm.x * tBias) - pivot.x,
          (v0.y + faceNorm.y * tBias) - pivot.y,
          (v0.z + faceNorm.z * tBias) - pivot.z,
          (v1.x + faceNorm.x * tBias) - pivot.x,
          (v1.y + faceNorm.y * tBias) - pivot.y,
          (v1.z + faceNorm.z * tBias) - pivot.z,
        ]);
        if (poly.vertices.length >= 4) {
          final v2 = poly.vertices[2];
          final v3 = poly.vertices[3];
          tangentPositions.addAll([
            (v2.x + faceNorm.x * tBias) - pivot.x,
            (v2.y + faceNorm.y * tBias) - pivot.y,
            (v2.z + faceNorm.z * tBias) - pivot.z,
            (v3.x + faceNorm.x * tBias) - pivot.x,
            (v3.y + faceNorm.y * tBias) - pivot.y,
            (v3.z + faceNorm.z * tBias) - pivot.z,
          ]);
        }
      }

      if (shouldDrawWireframe && poly.drawWireframe && !isInternalFace) {
        // 1. Outer boundary lines
        if (poly.boundaryLines.isNotEmpty) {
          for (final seg in poly.boundaryLines) {
            if (seg.length >= 2) {
              for (int i = 0; i < seg.length - 1; i++) {
                rawBoundarySegs.add((seg[i], seg[i + 1], faceNorm));
              }
            }
          }
        } else if (poly.vertices.length >= 3) {
          for (int i = 0; i < poly.vertices.length; i++) {
            final v1 = poly.vertices[i];
            final v2 = poly.vertices[(i + 1) % poly.vertices.length];
            rawBoundarySegs.add((v1, v2, faceNorm));
          }
        }

        // 2. Cutout holes and voids outline loops (punch holes, slots, coupler cuts)
        for (final hole in poly.holes) {
          if (hole.length >= 3) {
            final sanitizedHole = <CadPoint3D>[];
            for (final pt in hole) {
              if (sanitizedHole.isEmpty ||
                  (pt.x - sanitizedHole.last.x).abs() > 1e-4 ||
                  (pt.y - sanitizedHole.last.y).abs() > 1e-4 ||
                  (pt.z - sanitizedHole.last.z).abs() > 1e-4) {
                sanitizedHole.add(pt);
              }
            }
            if (sanitizedHole.length > 2 &&
                (sanitizedHole.first.x - sanitizedHole.last.x).abs() <= 1e-4 &&
                (sanitizedHole.first.y - sanitizedHole.last.y).abs() <= 1e-4 &&
                (sanitizedHole.first.z - sanitizedHole.last.z).abs() <= 1e-4) {
              sanitizedHole.removeLast();
            }

            for (int i = 0; i < sanitizedHole.length; i++) {
              final h1 = sanitizedHole[i];
              final h2 = sanitizedHole[(i + 1) % sanitizedHole.length];
              rawBoundarySegs.add((h1, h2, faceNorm));
            }
          }
        }
      }
    }

    // Canonical 3D Crease & Hole-Rim Deduplication with Averaged Corner-Bisector Normal Offset:
    // For shared 90° corner edges, averaging the two adjacent face normals pushes the 3D border line
    // diagonally outward along the 45° corner bisector by +0.18mm so it NEVER Z-fights with either face,
    // and is 100% occluded by the hardware Z-buffer on depthLayer = 0 when behind another 3D part!
    if (shouldDrawWireframe && rawBoundarySegs.isNotEmpty) {
      final edgeMap = <String, (CadPoint3D, CadPoint3D, CadPoint3D)>{};

      for (final seg in rawBoundarySegs) {
        final a = seg.$1;
        final b = seg.$2;
        final n = seg.$3;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dz = b.z - a.z;
        if (dx * dx + dy * dy + dz * dz <= 1e-6) continue;

        final kA = '${(a.x * 100).round()}_${(a.y * 100).round()}_${(a.z * 100).round()}';
        final kB = '${(b.x * 100).round()}_${(b.y * 100).round()}_${(b.z * 100).round()}';
        if (kA == kB) continue;

        final isForward = kA.compareTo(kB) <= 0;
        final edgeKey = isForward ? '$kA|$kB' : '$kB|$kA';
        final pStart = isForward ? a : b;
        final pEnd = isForward ? b : a;

        final existing = edgeMap[edgeKey];
        if (existing == null) {
          edgeMap[edgeKey] = (pStart, pEnd, n);
        } else {
          // Average the outward normals of the two faces sharing this 90° crease edge!
          final prevN = existing.$3;
          final sumNx = prevN.x + n.x;
          final sumNy = prevN.y + n.y;
          final sumNz = prevN.z + n.z;
          final len = math.sqrt(sumNx * sumNx + sumNy * sumNy + sumNz * sumNz);
          final avgN = len > 1e-4 ? CadPoint3D(sumNx / len, sumNy / len, sumNz / len) : prevN;
          edgeMap[edgeKey] = (existing.$1, existing.$2, avgN);
        }
      }

      const double depthBiasMm = 0.18;
      for (final entry in edgeMap.values) {
        final a = entry.$1;
        final b = entry.$2;
        final n = entry.$3;
        edgePositions.addAll([
          (a.x + n.x * depthBiasMm) - pivot.x,
          (a.y + n.y * depthBiasMm) - pivot.y,
          (a.z + n.z * depthBiasMm) - pivot.z,
          (b.x + n.x * depthBiasMm) - pivot.x,
          (b.y + n.y * depthBiasMm) - pivot.y,
          (b.z + n.z * depthBiasMm) - pivot.z,
        ]);
      }
    }

    final maxModelDim = math.max(meshResult.boundWidth, math.max(meshResult.boundLength, meshResult.boundHeight)).clamp(100.0, 5000.0);

    final boundaryColor = preferences.highlightBoundaryEdges ? preferences.boundaryEdgeColor : const Color(0xFF1B242D); // Onshape dark charcoal-slate

    // 1. Pass 1A: Optional In-Engine Inverted-Hull Outer Silhouette Pass (depthLayer = 0)
    if (shouldDrawWireframe && !isGlobalTranslucent && (preferences.silhouetteEdgeBoost || preferences.lightingPreset == CadLightingPreset.engineeringCrisp)) {
      final hullThickness = (preferences.lineWidth * maxModelDim * 0.00028).clamp(0.18, 1.4);
      final hullNode = buildInvertedHullOutlineNode(
        meshResult,
        pivot: pivot,
        hullThicknessMm: hullThickness,
        outlineSrgbColor: boundaryColor,
        sectionViewConfig: sectionViewConfig,
        hiddenPartIds: hiddenPartIds,
        isolatedPartIds: isolatedPartIds,
      );
      if (hullNode != null) {
        rootNode.add(hullNode);
      }
    }

    // 2. Pass 2: Build Opaque Solid Body Node (depthLayer = 0)
    if (opaqueBuilder.triangleCount > 0) {
      final solidGeometry = opaqueBuilder.build(storage: GeometryStorage.fixed);
      final Material material;
      if (customMaterial != null) {
        material = customMaterial;
      } else if (isWireframeOnly) {
        material = UnlitMaterial()
          ..doubleSided = true
          ..depthLayer = 0
          ..baseColorFactor = vm.Vector4(0.96, 0.97, 0.98, 1.0);
      } else {
        final matSettings = preferences.materialSettings;
        final shininessRatio = (preferences.shininess / 100.0).clamp(0.0, 1.0);
        final roughness = (0.68 - shininessRatio * 0.52).clamp(0.12, 0.75);
        material = PhysicallyBasedMaterial()
          ..doubleSided = true
          ..depthLayer = 0
          ..metallicFactor = matSettings.isPlastic ? 0.02 : 0.08
          ..roughnessFactor = roughness
          ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0);
      }
      final solidMesh = Mesh(solidGeometry, material);
      final solidNode = Node(name: 'SolidCadBody', mesh: solidMesh);
      rootNode.add(solidNode);
    }

    // 3. Build Translucent Solid Body Node (for Translucent mode or transparent parts)
    if (translucentBuilder.triangleCount > 0) {
      final transGeometry = translucentBuilder.build(storage: GeometryStorage.fixed);
      final transMaterial = UnlitMaterial()
        ..doubleSided = true
        ..depthLayer = 1
        ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 0.38);
      final transMesh = Mesh(transGeometry, transMaterial);
      final transNode = Node(name: 'TranslucentCadBody', mesh: transMesh);
      rootNode.add(transNode);
    }

    // 4. Pass 1B: Hardware Depth-Tested 3D Topological Crease & Hole-Rim Mesh (depthLayer = 0!)
    //    Shares the exact same hardware Z-buffer as SolidCadBody:
    //    - ZERO camera lag (transformed on the GPU in the exact same frame as the 3D part)
    //    - ZERO X-ray bleeding (occluded by SolidCadBody whenever behind another 3D part!)
    if (shouldDrawWireframe && edgePositions.length >= 6) {
      final lineData = LineSegmentData(positions: Float32List.fromList(edgePositions));
      final computedLineWidth = (preferences.lineWidth * maxModelDim * 0.00038).clamp(0.20, 2.5);
      final lineGeometry = LineSegmentsGeometry(
        lineData,
        width: computedLineWidth,
        normalOffset: 0.0, // Already offset +0.18mm along true 3D corner-bisector normal!
      );
      final lineMat = UnlitMaterial()
        ..doubleSided = true
        ..depthLayer =
            0 // CRITICAL FIX: depthLayer = 0 enables hardware Z-buffer occlusion against SolidCadBody!
        ..baseColorFactor = vm.Vector4(_srgbToLinear(boundaryColor.r), _srgbToLinear(boundaryColor.g), _srgbToLinear(boundaryColor.b), 1.0);
      final lineMesh = Mesh(lineGeometry, lineMat);
      final edgeNode = Node(name: 'CadBoundaryEdges', mesh: lineMesh);
      rootNode.add(edgeNode);
    }

    // 5. Hardware Depth-Tested Tangent Edges (depthLayer = 0!)
    if (shouldDrawTangents && tangentPositions.length >= 6) {
      final tangentLineData = LineSegmentData(positions: Float32List.fromList(tangentPositions));
      final computedPhantomWidth = (preferences.phantomTangentEdgeWidth * maxModelDim * 0.00022).clamp(0.15, 1.6);
      final tangentGeometry = LineSegmentsGeometry(tangentLineData, width: computedPhantomWidth, normalOffset: 0.0);
      final tColor = preferences.phantomTangentEdgeColor;
      final tangentMat = UnlitMaterial()
        ..doubleSided = true
        ..depthLayer =
            0 // CRITICAL FIX: depthLayer = 0 so hidden tangent lines don't X-ray through front parts!
        ..baseColorFactor = vm.Vector4(_srgbToLinear(tColor.r), _srgbToLinear(tColor.g), _srgbToLinear(tColor.b), tColor.a);
      final tangentMesh = Mesh(tangentGeometry, tangentMat);
      final tangentNode = Node(name: 'CadPhantomTangentEdges', mesh: tangentMesh);
      rootNode.add(tangentNode);
    }

    return rootNode;
  }

  /// Builds a subtle studio ground reference grid on Z = 0
  static Node buildGroundGrid({double size = 400.0, int divisions = 10, double zOffset = -2.0}) {
    final List<double> gridLines = [];
    final half = size / 2.0;
    final step = size / divisions;

    for (int i = 0; i <= divisions; i++) {
      final pos = -half + i * step;
      gridLines.addAll([-half, pos, zOffset, half, pos, zOffset]);
      gridLines.addAll([pos, -half, zOffset, pos, half, zOffset]);
    }

    final lineData = LineSegmentData(positions: Float32List.fromList(gridLines));
    final geometry = LineSegmentsGeometry(lineData, width: 0.35);
    final mat = UnlitMaterial()
      ..doubleSided = true
      ..baseColorFactor = vm.Vector4(0.84, 0.87, 0.91, 1.0);

    return Node(name: 'StudioGrid', mesh: Mesh(geometry, mat));
  }
}
