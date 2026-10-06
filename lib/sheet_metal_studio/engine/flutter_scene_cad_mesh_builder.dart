import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'kinematic_fold_engine.dart';

/// Hardware-accelerated Flutter GPU / Impeller CAD Mesh Builder for TruFold Studio.
/// Translates [FoldedMeshResult] into native [Node]s, [MeshGeometry] via [GeometryBuilder],
/// and crisp silhouette borders via [LineSegmentsGeometry].
class FlutterSceneCadMeshBuilder {
  /// Builds a complete 3D CAD scene node from a folded sheet metal mesh.
  static Node buildCadModel(
    FoldedMeshResult meshResult, {
    String? selectedFaceId,
    String? hoveredFaceId,
    bool showWireframe = true,
    Color? baseColorOverride,
  }) {
    final rootNode = Node(name: 'CadModelRoot');
    final pivot = meshResult.center;

    final builder = GeometryBuilder(deduplicate: true);

    // Collect all boundary line segments for crisp silhouette overlay
    final List<double> edgePositions = [];

    for (final poly in meshResult.allPolygons) {
      if (poly.vertices.length < 3) continue;

      final isSelected = (poly.faceId == selectedFaceId);
      final isHovered = (poly.faceId == hoveredFaceId);

      // Resolve color for this face
      vm.Vector4 faceColor;
      if (isSelected) {
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
      } else {
        // Authentic Onshape Slate Steel-Blue #477AA6
        faceColor = vm.Vector4(0.278, 0.478, 0.651, 1.0);
      }

      builder.color(faceColor);

      // Normal
      final n = poly.normal;
      final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
      final normVec = lenN > 1e-6
          ? vm.Vector3(n.x / lenN, n.y / lenN, n.z / lenN)
          : vm.Vector3(0, 0, 1);
      builder.normal(normVec);

      // Triangulate planar polygon (fan triangulation around v0)
      final v0 = poly.vertices[0];
      final p0 = vm.Vector3(v0.x - pivot.x, v0.y - pivot.y, v0.z - pivot.z);

      for (int i = 1; i < poly.vertices.length - 1; i++) {
        final v1 = poly.vertices[i];
        final v2 = poly.vertices[i + 1];

        final p1 = vm.Vector3(v1.x - pivot.x, v1.y - pivot.y, v1.z - pivot.z);
        final p2 = vm.Vector3(v2.x - pivot.x, v2.y - pivot.y, v2.z - pivot.z);

        final idx0 = builder.addVertex(p0);
        final idx1 = builder.addVertex(p1);
        final idx2 = builder.addVertex(p2);

        builder.addTriangle(idx0, idx1, idx2);
      }

      // Collect outer boundary lines
      if (showWireframe) {
        for (final seg in poly.boundaryLines) {
          if (seg.length >= 2) {
            for (int i = 0; i < seg.length - 1; i++) {
              final a = seg[i];
              final b = seg[i + 1];
              edgePositions.addAll([
                a.x - pivot.x, a.y - pivot.y, a.z - pivot.z,
                b.x - pivot.x, b.y - pivot.y, b.z - pivot.z,
              ]);
            }
          }
        }
      }
    }

    if (builder.triangleCount > 0) {
      final geometry = builder.build(storage: GeometryStorage.fixed);
      final material = PhysicallyBasedMaterial()
        ..metallicFactor = 0.70
        ..roughnessFactor = 0.35;

      final bodyMesh = Mesh(geometry, material);
      final bodyNode = Node(name: 'SolidCadBody', mesh: bodyMesh);
      rootNode.add(bodyNode);
    }

    // Add crisp silhouette wireframe if boundary lines exist
    if (showWireframe && edgePositions.length >= 6) {
      final lineData = LineSegmentData(
        positions: Float32List.fromList(edgePositions),
      );
      final lineGeometry = LineSegmentsGeometry(lineData, width: 0.75);
      final lineMat = UnlitMaterial()
        ..baseColorFactor = vm.Vector4(0.08, 0.12, 0.18, 1.0); // Slate 900
      final lineMesh = Mesh(lineGeometry, lineMat);
      final edgeNode = Node(name: 'CadBoundaryEdges', mesh: lineMesh);
      rootNode.add(edgeNode);
    }

    return rootNode;
  }
}
