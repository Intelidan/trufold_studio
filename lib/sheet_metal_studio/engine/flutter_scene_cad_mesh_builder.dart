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

    final opaqueBuilder = GeometryBuilder(deduplicate: true);
    final translucentBuilder = GeometryBuilder(deduplicate: true);

    // Collect outer boundary lines for wireframe (single border line per segment)
    final List<(CadPoint3D, CadPoint3D)> rawBoundarySegs = [];
    final List<double> edgePositions = [];

    final bool shouldDrawWireframe = showWireframe &&
        renderMode != OnshapeRenderMode.shadedWithoutEdges;

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

      final isSelected = (poly.faceId == selectedFaceId) ||
          (selectedFaceId != null && poly.faceId.startsWith(selectedFaceId));
      final isHovered = (poly.faceId == hoveredFaceId);

      // Resolve color for this face
      vm.Vector4 faceColor;
      if (isWeld) {
        // Fillet weld bead: preserve poly.color (selection cyan / translucent amber gold / solid steel)
        faceColor = vm.Vector4(
          poly.color.r,
          poly.color.g,
          poly.color.b,
          poly.color.a,
        );
      } else if (isSelected) {
        faceColor = vm.Vector4(0.22, 0.74, 0.97, 1.0); // Sky blue #38BDF8
      } else if (isHovered) {
        faceColor = vm.Vector4(0.73, 0.90, 0.99, 1.0); // Cyan hover #BAE6FD
      } else if (baseColorOverride != null) {
        faceColor = vm.Vector4(
          baseColorOverride.r,
          baseColorOverride.g,
          baseColorOverride.b,
          1.0,
        );
      } else if (partColorOverrides.containsKey(partId)) {
        final pc = partColorOverrides[partId]!;
        faceColor = vm.Vector4(pc.r, pc.g, pc.b, 1.0);
      } else if (!preferences.useOnshapeCadColor) {
        final mc = preferences.materialSettings.baseColor;
        if (poly.faceId.startsWith('BORE_') || poly.faceId.startsWith('RIM_')) {
          faceColor = vm.Vector4(mc.r * 0.75, mc.g * 0.75, mc.b * 0.75, 1.0);
        } else if (poly.faceId.endsWith('_BOT')) {
          faceColor = vm.Vector4(mc.r * 0.88, mc.g * 0.88, mc.b * 0.88, 1.0);
        } else {
          faceColor = vm.Vector4(mc.r, mc.g, mc.b, 1.0);
        }
      } else if (poly.faceId.startsWith('BORE_') || poly.faceId.startsWith('RIM_')) {
        // Deep bore wall / sheet thickness rim steel #28445C
        faceColor = vm.Vector4(0.157, 0.267, 0.361, 1.0);
      } else if (poly.faceId.endsWith('_BOT')) {
        // Back / bottom surface slightly darker tone #375F82
        faceColor = vm.Vector4(0.216, 0.373, 0.510, 1.0);
      } else {
        // Authentic Onshape Slate Steel-Blue #477AA6
        faceColor = vm.Vector4(0.278, 0.478, 0.651, 1.0);
      }

      currentBuilder.color(faceColor);

      // Normal
      final n = poly.normal;
      final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
      final normVec = lenN > 1e-6
          ? vm.Vector3(n.x / lenN, n.y / lenN, n.z / lenN)
          : vm.Vector3(0, 0, 1);
      currentBuilder.normal(normVec);

      // Triangulate planar polygon with inner cutout holes (round holes, obround slots, coupler slots)
      CadPolygonTriangulator.triangulateToBuilder(
        outerVertices: poly.vertices,
        holes: poly.holes,
        normal: poly.normal,
        pivot: pivot,
        builder: currentBuilder,
      );

      // Requirement 1: Only 1 border line per segment (skip bottom/inner/wall/rim duplicates and welds)
      final isInternalFace = poly.faceId.endsWith('_BOT') ||
          poly.faceId.endsWith('_inner') ||
          poly.faceId.contains('_slot_') ||
          poly.faceId.contains('_wall_') ||
          poly.faceId.startsWith('BORE_') ||
          poly.faceId.startsWith('RIM_') ||
          poly.faceId.startsWith('CHAMFER_') ||
          poly.faceId.startsWith('weld_');

      if (shouldDrawWireframe && poly.drawWireframe && !isInternalFace) {
        final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
        final nx = lenN > 1e-4 ? (n.x / lenN) * 0.05 : 0.0;
        final ny = lenN > 1e-4 ? (n.y / lenN) * 0.05 : 0.0;
        final nz = lenN > 1e-4 ? (n.z / lenN) * 0.05 : 0.0;

        // 1. Boundary lines from SheetMetal unfold if available, otherwise from polygon vertices
        if (poly.boundaryLines.isNotEmpty) {
          for (final seg in poly.boundaryLines) {
            if (seg.length >= 2) {
              for (int i = 0; i < seg.length - 1; i++) {
                final p1 = CadPoint3D(seg[i].x + nx, seg[i].y + ny, seg[i].z + nz);
                final p2 = CadPoint3D(seg[i + 1].x + nx, seg[i + 1].y + ny, seg[i + 1].z + nz);
                rawBoundarySegs.add((p1, p2));
              }
            }
          }
        } else if (poly.vertices.length >= 3) {
          for (int i = 0; i < poly.vertices.length; i++) {
            final v1 = poly.vertices[i];
            final v2 = poly.vertices[(i + 1) % poly.vertices.length];
            final p1 = CadPoint3D(v1.x + nx, v1.y + ny, v1.z + nz);
            final p2 = CadPoint3D(v2.x + nx, v2.y + ny, v2.z + nz);
            rawBoundarySegs.add((p1, p2));
          }
        }

        // 2. Cutout holes and voids outline loops (punch holes, slots, coupler cuts)
        for (final hole in poly.holes) {
          if (hole.length >= 3) {
            for (int i = 0; i < hole.length; i++) {
              final h1 = hole[i];
              final h2 = hole[(i + 1) % hole.length];
              final p1 = CadPoint3D(h1.x + nx, h1.y + ny, h1.z + nz);
              final p2 = CadPoint3D(h2.x + nx, h2.y + ny, h2.z + nz);
              rawBoundarySegs.add((p1, p2));
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

    // Requirement 2: Weld/snap intersecting boundary endpoints within floating-point tolerance (0.15 mm)
    // Preserves smooth curved bend fillet arc facets without collapsing them into sharp straight chords.
    if (shouldDrawWireframe && rawBoundarySegs.isNotEmpty) {
      final weldedVertices = <CadPoint3D>[];
      const double snapTolerance = 0.15;
      const double snapTolSq = snapTolerance * snapTolerance;

      CadPoint3D snapVertex(CadPoint3D pt) {
        for (final v in weldedVertices) {
          final dx = v.x - pt.x;
          final dy = v.y - pt.y;
          final dz = v.z - pt.z;
          if (dx.abs() <= snapTolerance && dy.abs() <= snapTolerance && dz.abs() <= snapTolerance) {
            if ((dx * dx + dy * dy + dz * dz) <= snapTolSq) {
              return v;
            }
          }
        }
        weldedVertices.add(pt);
        return pt;
      }

      final addedEdgeKeys = <String>{};

      for (final seg in rawBoundarySegs) {
        final a = snapVertex(seg.$1);
        final b = snapVertex(seg.$2);
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dz = b.z - a.z;
        if (dx * dx + dy * dy + dz * dz > 0.01) {
          final kA = '${a.x.toStringAsFixed(2)}_${a.y.toStringAsFixed(2)}_${a.z.toStringAsFixed(2)}';
          final kB = '${b.x.toStringAsFixed(2)}_${b.y.toStringAsFixed(2)}_${b.z.toStringAsFixed(2)}';
          if (kA == kB) continue;

          final edgeKey = kA.compareTo(kB) <= 0 ? '$kA--$kB' : '$kB--$kA';
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
        // Shaded mode: apply active materialSettings (PGI, HDG, Plastic, Metals)
        final matSettings = preferences.materialSettings;
        material = PhysicallyBasedMaterial()
          ..doubleSided = true
          ..metallicFactor = matSettings.isPlastic ? 0.0 : 0.85
          ..roughnessFactor = (1.0 - (preferences.shininess / 100.0) * 0.95).clamp(0.08, 0.95)
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
        ..alphaMode = AlphaMode.blend
        ..baseColorFactor = vm.Vector4(1.0, 1.0, 1.0, transOpacity)
        ..metallicFactor = 0.08
        ..roughnessFactor = 0.50;
      final transMesh = Mesh(transGeometry, transMat);
      final transNode = Node(name: 'TranslucentCadBody', mesh: transMesh);
      rootNode.add(transNode);
    }

    // 3. Add crisp silhouette wireframe if boundary lines exist (with Highlight Boundary Edges support)
    if (shouldDrawWireframe && edgePositions.length >= 6) {
      final lineData = LineSegmentData(
        positions: Float32List.fromList(edgePositions),
      );
      final computedLineWidth = (preferences.lineWidth * 2.0).clamp(1.0, 3.5);
      final lineGeometry = LineSegmentsGeometry(lineData, width: computedLineWidth, normalOffset: 0.05);
      final boundaryColor = preferences.highlightBoundaryEdges
          ? preferences.boundaryEdgeColor
          : const Color(0xFF0F172A); // Slate 900
      final lineMat = UnlitMaterial()
        ..doubleSided = true
        ..baseColorFactor = vm.Vector4(
          boundaryColor.r,
          boundaryColor.g,
          boundaryColor.b,
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
      final computedPhantomWidth = (preferences.phantomTangentEdgeWidth * 0.7).clamp(0.3, 3.5);
      final tangentGeometry = LineSegmentsGeometry(tangentLineData, width: computedPhantomWidth);
      final tColor = preferences.phantomTangentEdgeColor;
      final tangentMat = UnlitMaterial()
        ..doubleSided = true
        ..baseColorFactor = vm.Vector4(
          tColor.r,
          tColor.g,
          tColor.b,
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
