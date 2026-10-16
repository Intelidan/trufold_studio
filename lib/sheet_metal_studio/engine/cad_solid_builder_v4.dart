import 'dart:math';
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';
import 'cad_topological_edge_builder.dart';

class CadSurfaceMeshData {
  /// Interleaved 7 floats per vertex:
  /// [posX, posY, posZ, normX, normY, normZ, ambientOcclusion]
  /// ambientOcclusion in [0.0..1.0] darkens interior hole bores & concave fillet roots!
  final Float32List vertices;
  final Uint16List indices;
  CadSurfaceMeshData(this.vertices, this.indices);
}

class CadSolidBuilderV4 {
  final List<double> _verts = [];
  final List<int> _indices = [];
  int _vertexCount = 0;

  int _addVertex(Vector3 pos, Vector3 normal, {double ao = 1.0}) {
    _verts.addAll([
      pos.x,
      pos.y,
      pos.z,
      normal.x,
      normal.y,
      normal.z,
      ao,
    ]);
    return _vertexCount++;
  }

  /// Builds a crisp, flat-shaded 3D box/wall with 24 split vertices (4 per face, zero normal averaging!)
  /// and 12 deduplicated topological border edges (zero corner overhangs!).
  void addSharpBox({
    required Vector3 minCorner,
    required Vector3 maxCorner,
    required CadEdgeBuilder edgeBuilder,
  }) {
    final c000 = Vector3(minCorner.x, minCorner.y, minCorner.z);
    final c100 = Vector3(maxCorner.x, minCorner.y, minCorner.z);
    final c110 = Vector3(maxCorner.x, maxCorner.y, minCorner.z);
    final c010 = Vector3(minCorner.x, maxCorner.y, minCorner.z);
    final c001 = Vector3(minCorner.x, minCorner.y, maxCorner.z);
    final c101 = Vector3(maxCorner.x, minCorner.y, maxCorner.z);
    final c111 = Vector3(maxCorner.x, maxCorner.y, maxCorner.z);
    final c011 = Vector3(minCorner.x, maxCorner.y, maxCorner.z);

    void addFlatQuad(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, Vector3 n) {
      final int b = _vertexCount;
      _addVertex(p0, n);
      _addVertex(p1, n);
      _addVertex(p2, n);
      _addVertex(p3, n);
      _indices.addAll([b, b + 1, b + 2, b, b + 2, b + 3]);

      // Emit topological border loop (CadEdgeBuilder automatically deduplicates shared edges!)
      edgeBuilder.addPolyline([p0, p1, p2, p3], closed: true);
    }

    addFlatQuad(c001, c101, c111, c011, Vector3(0, 0, 1));  // Front (+Z)
    addFlatQuad(c100, c000, c010, c110, Vector3(0, 0, -1)); // Back (-Z)
    addFlatQuad(c011, c111, c110, c010, Vector3(0, 1, 0));  // Top (+Y)
    addFlatQuad(c000, c100, c101, c001, Vector3(0, -1, 0)); // Bottom (-Y)
    addFlatQuad(c101, c100, c110, c111, Vector3(1, 0, 0));  // Right (+X)
    addFlatQuad(c000, c001, c011, c010, Vector3(-1, 0, 0)); // Left (-X)
  }

  /// Builds a high-resolution cylindrical hole bore with:
  /// - Smooth radial inward normals (for Onshape interior bore shading)
  /// - Subtle interior Ambient Occlusion (`ao: 0.78` top, `0.68` bottom)
  /// - ONLY 2 clean circular rim loops (zero vertical spike lines!)
  void addCylindricalHole({
    required Vector3 centerTop,
    required Vector3 plateNormal,
    required double radius,
    required double depth,
    required CadEdgeBuilder edgeBuilder,
  }) {
    final int segments = _getSegmentsForCircle(radius);

    final Vector3 n = plateNormal.normalized();
    final Vector3 helper =
        n.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
    final Vector3 tangent = n.cross(helper).normalized();
    final Vector3 bitangent = n.cross(tangent).normalized();

    final int baseIdx = _vertexCount;
    final List<Vector3> topRimPoints = [];
    final List<Vector3> bottomRimPoints = [];

    for (int i = 0; i <= segments; i++) {
      final double angle = (2.0 * pi * i) / segments;
      final Vector3 radialOut =
          (tangent * cos(angle) + bitangent * sin(angle)).normalized();

      final Vector3 topPos = centerTop + radialOut * radius;
      final Vector3 botPos = topPos - n * depth;

      final Vector3 inwardNormal = -radialOut;
      _addVertex(topPos, inwardNormal, ao: 0.86);
      _addVertex(botPos, inwardNormal, ao: 0.72);

      // Strictly collect < segments unique points so start & end never duplicate!
      if (i < segments) {
        topRimPoints.add(topPos);
        bottomRimPoints.add(botPos);
      }
    }

    for (int i = 0; i < segments; i++) {
      final int b = baseIdx + i * 2;
      _indices.addAll([b, b + 1, b + 2, b + 1, b + 3, b + 2]);
    }

    // Emit ONLY the 2 circular rim loops (top and bottom)
    edgeBuilder.addPolyline(topRimPoints, closed: true);
    edgeBuilder.addPolyline(bottomRimPoints, closed: true);
  }

  static int _getSegmentsForCircle(double radius, {double maxChordError = 0.02}) {
    final double ratio = (maxChordError / radius).clamp(0.0001, 0.5);
    final double angle = 2.0 * acos(1.0 - ratio);
    final int segments = (2.0 * pi / angle).ceil();
    return segments.clamp(48, 96);
  }

  CadSurfaceMeshData build() => CadSurfaceMeshData(
        Float32List.fromList(_verts),
        Uint16List.fromList(_indices),
      );
}
