import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import '../models/cad_primitives.dart';
import '../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'cad_polygon_triangulator.dart';
import 'kinematic_fold_engine.dart';

/// Hardware-accelerated Flutter GPU / Impeller CAD Mesh Builder for TruFold Studio.
/// Translates [FoldedMeshResult] into native [Node]s, [MeshGeometry] via [GeometryBuilder]
/// with true hole punch-through via [CadPolygonTriangulator], and crisp silhouette borders
/// via [LineSegmentsGeometry].
class FlutterSceneCadMeshBuilder {
  /// Converts an sRGB channel [0..1] to Linear RGB for physically based rendering.
  static double _srgbToLinear(double s) {
    final c = s.clamp(0.0, 1.0);
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Computes Onshape Studio 3-Light + Hemisphere + Crevice AO Linear RGB color for a face.
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

    // Directional studio contrast factor
    double directionalTone = hemiTone +
        wrapKey * 0.34 +
        dotKey * 0.14 +
        dotFill * (preferences.hasSecondaryLight ? 0.14 : 0.04) +
        dotRim * (preferences.hasBackLight ? 0.10 : 0.03);

    // 3. Topological Crevice & Feature Ambient Occlusion Multiplier
    final aoStrength = (preferences.ambientOcclusion / 100.0).clamp(0.0, 1.0);
    final fid = poly.faceId;
    double featureAo = 1.0;

    if (fid.startsWith('BORE_') || fid.contains('_bore_')) {
      featureAo = 1.0 - (0.38 * aoStrength);
    } else if (fid.contains('_inner_web')) {
      featureAo = 1.0 - (0.28 * aoStrength);
    } else if (fid.contains('_inner_flange')) {
      featureAo = 1.0 - (0.22 * aoStrength);
    } else if (fid.startsWith('RIM_') || fid.contains('_rim_') || fid.contains('_end_cap_')) {
      featureAo = 1.0 - (0.18 * aoStrength);
    } else if (fid.endsWith('_BOT') || fid.contains('flange_bottom')) {
      featureAo = 1.0 - (0.15 * aoStrength);
    }

    final finalSrgbScale = (directionalTone * featureAo).clamp(0.28, 1.08);

    // Subtle cool sky tint on upward faces, warm slate on downward crevices
    final rSrgb = (baseSrgbColor.r * finalSrgbScale * (0.98 + 0.02 * (1.0 - hemi))).clamp(0.0, 1.0);
    final gSrgb = (baseSrgbColor.g * finalSrgbScale).clamp(0.0, 1.0);
    final bSrgb = (baseSrgbColor.b * finalSrgbScale * (0.97 + 0.05 * hemi)).clamp(0.0, 1.0);

    // Convert sRGB -> Linear RGB so ACES tone mapping doesn't wash out colors to white!
    return vm.Vector4(
      _srgbToLinear(rSrgb),
      _srgbToLinear(gSrgb),
      _srgbToLinear(bSrgb),
      1.0,
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

    // Collect outer boundary lines for wireframe (single border line per segment)
    final List<(CadPoint3D, CadPoint3D)> rawBoundarySegs = [];
    final List<double> edgePositions = [];

    final bool shouldDrawWireframe = showWireframe &&
        renderMode != OnshapeRenderMode.shadedWithoutEdges &&
        preferences.lineWidth > 0.05;

    // Collect tangent seam edges (fillet transitions)
    final List<double> tangentPositions = [];
    final bool shouldDrawTangents = preferences.tangentEdgeMode != OnshapeTangentEdgeMode.removed;

    for (final poly in meshResult.allPolygons) {
      if (poly.vertices.length < 3) continue;

      // Onshape Part Visibility Filter: Hide / Show
      final partId = SheetMetalStudioViewModel.extractPartIdFromFaceId(poly.faceId);
      if (hiddenPartIds.contains(partId)) continue;

      // Onshape Dynamic Section View Clipping
      if (sectionViewConfig.isEnabled) {
        double avgX = 0, avgY = 0, avgZ = 0;
        for (final v in poly.vertices) {
          avgX += v.x;
          avgY += v.y;
          avgZ += v.z;
        }
        avgX /= poly.vertices.length;
        avgY /= poly.vertices.length;
        avgZ /= poly.vertices.length;

        double dist;
        switch (sectionViewConfig.axis) {
          case SectionPlaneAxis.yz:
            dist = (avgX - pivot.x) - sectionViewConfig.distanceOffsetMm;
            break;
          case SectionPlaneAxis.zx:
            dist = (avgY - pivot.y) - sectionViewConfig.distanceOffsetMm;
            break;
          case SectionPlaneAxis.xy:
            dist = (avgZ - pivot.z) - sectionViewConfig.distanceOffsetMm;
            break;
        }
        if (sectionViewConfig.flipNormal) dist = -dist;
        if (dist > 0.0) continue;
      }

      final isPartIsolated = isolatedPartIds.isNotEmpty;
      final isWeld = poly.faceId.startsWith('weld_');
      final isTranslucent = (renderMode == OnshapeRenderMode.translucent) ||
          transparentPartIds.contains(partId) ||
          (isPartIsolated && !isolatedPartIds.contains(partId)) ||
          (isWeld && poly.color.a < 0.99);
      final currentBuilder = isTranslucent ? translucentBuilder : opaqueBuilder;

      final isHovered = (poly.faceId == hoveredFaceId);

      // Resolve color for this face, then apply Onshape Studio 3-Light + Crevice AO
      vm.Vector4 faceColor;
      if (isWeld) {
        // Fillet weld bead: preserve poly.color (selection cyan / translucent amber gold / solid steel)
        faceColor = vm.Vector4(
          _srgbToLinear(poly.color.r),
          _srgbToLinear(poly.color.g),
          _srgbToLinear(poly.color.b),
          poly.color.a,
        );
      } else {
        Color baseSrgb = const Color(0xFF6C9DC6); // Authentic Onshape SS3 Cerulean Steel-Blue
        if (baseColorOverride != null) {
          baseSrgb = baseColorOverride;
        } else if (partColorOverrides.containsKey(partId)) {
          baseSrgb = partColorOverrides[partId]!;
        } else if (!preferences.useOnshapeCadColor) {
          baseSrgb = preferences.materialSettings.baseColor;
        }
        faceColor = computeOnshapeStudioFaceColor(
          poly: poly,
          baseSrgbColor: baseSrgb,
          preferences: preferences,
          isHovered: isHovered,
        );
      }

      currentBuilder.color(faceColor);

      // Normal
      final n = poly.normal;
      final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
      final normVec = lenN > 1e-6
          ? vm.Vector3(n.x / lenN, n.y / lenN, n.z / lenN)
          : vm.Vector3(0, 0, 1);
      currentBuilder.normal(normVec);

      // Triangulate planar polygon with inner cutout holes and bake crevice AO
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

      // Filter only strictly internal tessellation/bore/inner faces; external end caps, rims, and slots emit boundary edges
      final isInternalFace = poly.faceId.contains('_inner') ||
          poly.faceId.contains('_bore') ||
          poly.faceId.startsWith('BORE_') ||
          poly.faceId.startsWith('CHAMFER_') ||
          poly.faceId.startsWith('FILLET_CAP') ||
          poly.faceId.startsWith('weld_');

      if (shouldDrawWireframe && poly.drawWireframe && !isInternalFace) {
        // 1. Boundary lines from SheetMetal unfold if available, otherwise from polygon vertices
        if (poly.boundaryLines.isNotEmpty) {
          for (final seg in poly.boundaryLines) {
            if (seg.length >= 2) {
              for (int i = 0; i < seg.length - 1; i++) {
                rawBoundarySegs.add((seg[i], seg[i + 1]));
              }
            }
          }
        } else if (poly.vertices.length >= 3) {
          for (int i = 0; i < poly.vertices.length; i++) {
            final v1 = poly.vertices[i];
            final v2 = poly.vertices[(i + 1) % poly.vertices.length];
            rawBoundarySegs.add((v1, v2));
          }
        }

        // 2. Cutout holes and voids outline loops (punch holes, slots, coupler cuts)
        for (final hole in poly.holes) {
          if (hole.length >= 3) {
            // Sanitize hole loop: strip consecutive duplicate points
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
              rawBoundarySegs.add((h1, h2));
            }
          }
        }
      }

      // Requirement 3: Collect tangent edges (phantom or visible fillet transitions)
      if (shouldDrawTangents && poly.tangentLines.isNotEmpty) {
        for (final seg in poly.tangentLines) {
          if (seg.length >= 2) {
            for (int i = 0; i < seg.length - 1; i++) {
              final p1 = seg[i];
              final p2 = seg[i + 1];
              if (preferences.tangentEdgeMode == OnshapeTangentEdgeMode.phantom) {
                _appendPhantomDashes(p1, p2, pivot, poly.normal, tangentPositions);
              } else {
                // Visible solid tangent line (with subtle normal nudge to prevent z-fighting)
                final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
                final nx = lenN > 1e-4 ? (n.x / lenN) * 0.04 : 0.0;
                final ny = lenN > 1e-4 ? (n.y / lenN) * 0.04 : 0.0;
                final nz = lenN > 1e-4 ? (n.z / lenN) * 0.04 : 0.0;
                tangentPositions.addAll([
                  p1.x + nx - pivot.x, p1.y + ny - pivot.y, p1.z + nz - pivot.z,
                  p2.x + nx - pivot.x, p2.y + ny - pivot.y, p2.z + nz - pivot.z,
                ]);
              }
            }
          }
        }
      }
    }

    // Canonical segment deduplication (_dedupedSegments): each 3D crease edge emitted exactly once!
    if (shouldDrawWireframe && rawBoundarySegs.isNotEmpty) {
      final addedEdgeKeys = <String>{};

      for (final seg in rawBoundarySegs) {
        final a = seg.$1;
        final b = seg.$2;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dz = b.z - a.z;
        if (dx * dx + dy * dy + dz * dz > 1e-6) {
          final kA = '${(a.x * 1000).round()}_${(a.y * 1000).round()}_${(a.z * 1000).round()}';
          final kB = '${(b.x * 1000).round()}_${(b.y * 1000).round()}_${(b.z * 1000).round()}';
          if (kA == kB) continue;

          final edgeKey = kA.compareTo(kB) <= 0 ? '$kA|$kB' : '$kB|$kA';
          if (!addedEdgeKeys.add(edgeKey)) continue;

          edgePositions.addAll([
            a.x - pivot.x, a.y - pivot.y, a.z - pivot.z,
            b.x - pivot.x, b.y - pivot.y, b.z - pivot.z,
          ]);
        }
      }
    }

    // 1. Build Opaque CAD Body
    if (opaqueBuilder.triangleCount > 0) {
      final geometry = opaqueBuilder.build(storage: GeometryStorage.fixed);

      Material material;
      if (renderMode == OnshapeRenderMode.unshaded) {
        material = UnlitMaterial()
          ..doubleSided = true
          ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0);
      } else if (customMaterial != null) {
        material = customMaterial..doubleSided = true;
      } else {
        // Shaded mode: Wire Graphics Preferences 'Shininess' (0..100%) to GGX Roughness!
        final matSettings = preferences.materialSettings;
        final shininessRatio = (preferences.shininess / 100.0).clamp(0.0, 1.0);
        // 68% shininess -> roughness 0.22 (Onshape SS3 satin-plastic/anodized sheen)
        final roughness = (0.68 - shininessRatio * 0.52).clamp(0.12, 0.75);
        material = PhysicallyBasedMaterial()
          ..doubleSided = true
          ..depthLayer = 0
          ..metallicFactor = matSettings.isPlastic ? 0.02 : 0.08
          ..roughnessFactor = roughness
          ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, 1.0);
      }

      final bodyMesh = Mesh(geometry, material);
      final bodyNode = Node(name: 'SolidCadBody', mesh: bodyMesh);
      rootNode.add(bodyNode);
    }

    // 2. Build Translucent / Isolated CAD Body
    if (translucentBuilder.triangleCount > 0) {
      final transGeometry = translucentBuilder.build(storage: GeometryStorage.fixed);
      final transOpacity = preferences.transparencyLevel.clamp(0.05, 0.95);
      final transMat = PhysicallyBasedMaterial()
        ..doubleSided = true
        ..depthLayer = 0
        ..alphaMode = AlphaMode.blend
        ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, transOpacity)
        ..metallicFactor = 0.04
        ..roughnessFactor = 0.40;
      final transMesh = Mesh(transGeometry, transMat);
      final transNode = Node(name: 'TranslucentCadBody', mesh: transMesh);
      rootNode.add(transNode);
    }

    // 3. Add crisp silhouette wireframe scaled to the model's millimeter dimensions!
    if (shouldDrawWireframe && edgePositions.length >= 6) {
      final lineData = LineSegmentData(
        positions: Float32List.fromList(edgePositions),
      );
      final maxModelDim = math.max(
        meshResult.boundWidth,
        math.max(meshResult.boundLength, meshResult.boundHeight),
      ).clamp(100.0, 5000.0);
      // Scale world-space ribbon width proportionally to model size so 1.3px..4.0px is crisp!
      final computedLineWidth = (preferences.lineWidth * maxModelDim * 0.00048).clamp(0.25, 4.5);
      final lineGeometry = LineSegmentsGeometry(
        lineData,
        width: computedLineWidth,
        normalOffset: maxModelDim * 0.00025,
      );
      final boundaryColor = preferences.highlightBoundaryEdges
          ? preferences.boundaryEdgeColor
          : const Color(0xFF1B242D); // Onshape dark charcoal-slate (not harsh #000000)
      final lineMat = UnlitMaterial()
        ..doubleSided = true
        ..depthLayer = 2 // Hardware-ordered depth layer
        ..baseColorFactor = vm.Vector4(
          _srgbToLinear(boundaryColor.r),
          _srgbToLinear(boundaryColor.g),
          _srgbToLinear(boundaryColor.b),
          1.0,
        );
      final lineMesh = Mesh(lineGeometry, lineMat);
      final edgeNode = Node(name: 'CadBoundaryEdges', mesh: lineMesh);
      rootNode.add(edgeNode);
    }

    // Requirement 3: Add Phantom Tangent Edges (or visible tangent edges)
    if (shouldDrawTangents && tangentPositions.length >= 6) {
      final tangentLineData = LineSegmentData(
        positions: Float32List.fromList(tangentPositions),
      );
      final maxModelDim = math.max(
        meshResult.boundWidth,
        math.max(meshResult.boundLength, meshResult.boundHeight),
      ).clamp(100.0, 5000.0);
      final computedPhantomWidth = (preferences.phantomTangentEdgeWidth * maxModelDim * 0.00025).clamp(0.15, 2.5);
      final tangentGeometry = LineSegmentsGeometry(
        tangentLineData,
        width: computedPhantomWidth,
        normalOffset: maxModelDim * 0.00015,
      );
      final tColor = preferences.phantomTangentEdgeColor;
      final tangentMat = UnlitMaterial()
        ..doubleSided = true
        ..depthLayer = 2
        ..baseColorFactor = vm.Vector4(
          _srgbToLinear(tColor.r),
          _srgbToLinear(tColor.g),
          _srgbToLinear(tColor.b),
          tColor.a,
        );
      final tangentMesh = Mesh(tangentGeometry, tangentMat);
      final tangentNode = Node(name: 'CadPhantomTangentEdges', mesh: tangentMesh);
      rootNode.add(tangentNode);
    }

    return rootNode;
  }

  /// Decomposes segment [p1, p2] into ISO/ANSI CAD phantom line dashes (long dash, dot, long dash).
  static void _appendPhantomDashes(
    CadPoint3D p1,
    CadPoint3D p2,
    CadPoint3D pivot,
    CadPoint3D normal,
    List<double> out,
  ) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final dz = p2.z - p1.z;
    final len = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (len < 0.5) return;

    final ux = dx / len;
    final uy = dy / len;
    final uz = dz / len;

    // Subtle normal offset (0.04mm) eliminates depth-buffer z-fighting with CAD body facets
    final lenN = math.sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
    final nx = lenN > 1e-4 ? (normal.x / lenN) * 0.04 : 0.0;
    final ny = lenN > 1e-4 ? (normal.y / lenN) * 0.04 : 0.0;
    final nz = lenN > 1e-4 ? (normal.z / lenN) * 0.04 : 0.0;

    // ISO/ANSI CAD Phantom line pattern: Long dash 4.0mm, space 1.8mm, dot 1.2mm, space 1.8mm
    const d1 = 4.0;
    const s1 = 1.8;
    const d2 = 1.2;
    const s2 = 1.8;

    double s = 0.0;
    while (s < len) {
      final e1 = math.min(s + d1, len);
      out.addAll([
        p1.x + ux * s + nx - pivot.x,
        p1.y + uy * s + ny - pivot.y,
        p1.z + uz * s + nz - pivot.z,
        p1.x + ux * e1 + nx - pivot.x,
        p1.y + uy * e1 + ny - pivot.y,
        p1.z + uz * e1 + nz - pivot.z,
      ]);
      s += d1 + s1;
      if (s >= len) break;

      final e2 = math.min(s + d2, len);
      out.addAll([
        p1.x + ux * s + nx - pivot.x,
        p1.y + uy * s + ny - pivot.y,
        p1.z + uz * s + nz - pivot.z,
        p1.x + ux * e2 + nx - pivot.x,
        p1.y + uy * e2 + ny - pivot.y,
        p1.z + uz * e2 + nz - pivot.z,
      ]);
      s += d2 + s2;
    }
  }
}
