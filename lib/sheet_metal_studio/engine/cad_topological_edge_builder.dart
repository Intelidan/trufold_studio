import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';

class CadScreenSpaceLineMeshData {
  /// Interleaved 7 floats per vertex:
  /// [posAx, posAy, posAz, posBx, posBy, posBz, sideAndEndSelect]
  /// where sideAndEndSelect encodes endpoint (A vs B) and perpendicular side (-1 vs +1).
  final Float32List vertexData;
  final Uint16List indices;

  /// Raw deduplicated 3D polylines for the 2D Canvas Fallback Painter
  final List<({List<Vector3> points, bool closed})> polylines;

  CadScreenSpaceLineMeshData({
    required this.vertexData,
    required this.indices,
    required this.polylines,
  });
}

class CadEdgeBuilder {
  final List<double> _verts = [];
  final List<int> _indices = [];
  final List<({List<Vector3> points, bool closed})> _polylines = [];
  final Set<String> _dedupedSegments = {};
  int _vertexCount = 0;

  /// Adds a topological feature loop or polyline.
  /// Automatically strips near-duplicate consecutive vertices (fixing hole spikes)
  /// and deduplicates shared 3D crease segments (fixing 3D box corner overhangs).
  void addPolyline(
    List<Vector3> rawPoints, {
    Vector3? surfaceNormal, // Kept optional for API compatibility; not used for world extrusion
    double worldHalfWidth = 0.02,
    bool closed = true,
  }) {
    // 1. Sanitize points: remove consecutive duplicates that cause NaN miter spikes on holes!
    final List<Vector3> pts = [];
    for (final p in rawPoints) {
      if (pts.isEmpty || pts.last.distanceToSquared(p) > 1e-8) {
        pts.add(p.clone());
      }
    }
    if (closed && pts.length > 1 && pts.first.distanceToSquared(pts.last) <= 1e-8) {
      pts.removeLast();
    }
    if (pts.length < 2) return;

    _polylines.add((points: pts, closed: closed));

    // 2. Emit deduplicated 3D segments for screen-space quad expansion
    final int segCount = closed ? pts.length : pts.length - 1;
    for (int i = 0; i < segCount; i++) {
      final Vector3 a = pts[i];
      final Vector3 b = pts[(i + 1) % pts.length];
      if (a.distanceToSquared(b) <= 1e-8) continue;

      final String key = _segmentKey(a, b);
      if (!_dedupedSegments.add(key)) {
        // Shared crease edge between two adjacent faces was already emitted!
        continue;
      }

      _emitScreenSpaceSegmentQuad(a, b);
    }
  }

  void _emitScreenSpaceSegmentQuad(Vector3 a, Vector3 b) {
    final int base = _vertexCount;

    // 4 vertices per segment:
    // sideAndEndSelect:
    //  -1.0 = Endpoint A, Left  (-1)
    //  +1.0 = Endpoint A, Right (+1)
    //  -2.0 = Endpoint B, Left  (-1)
    //  +2.0 = Endpoint B, Right (+1)
    for (final double code in [-1.0, 1.0, -2.0, 2.0]) {
      _verts.addAll([a.x, a.y, a.z, b.x, b.y, b.z, code]);
      _vertexCount++;
    }

    _indices.addAll([
      base,
      base + 1,
      base + 2,
      base + 1,
      base + 3,
      base + 2,
    ]);
  }

  static String _segmentKey(Vector3 p1, Vector3 p2) {
    String fmt(Vector3 v) =>
        '${(v.x * 1000).round()}_${(v.y * 1000).round()}_${(v.z * 1000).round()}';
    final String k1 = fmt(p1);
    final String k2 = fmt(p2);
    return (k1.compareTo(k2) <= 0) ? '$k1|$k2' : '$k2|$k1';
  }

  CadScreenSpaceLineMeshData build() => CadScreenSpaceLineMeshData(
        vertexData: Float32List.fromList(_verts),
        indices: Uint16List.fromList(_indices),
        polylines: List.unmodifiable(_polylines),
      );
}
