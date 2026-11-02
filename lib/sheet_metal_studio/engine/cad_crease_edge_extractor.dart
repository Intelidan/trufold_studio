// =============================================================================
// cad_crease_edge_extractor.dart
//
// TruFold Studio - Professional CAD Feature Edge & Dihedral Crease Extractor
// Eliminates raw triangle diagonals on flat faces and facet strip lines on bends,
// producing clean, single outline borders matching SketchUp and PaliCAD standards.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';

/// Clean topological CAD feature edge extractor using dihedral crease angle detection.
class CadCreaseEdgeExtractor {
  CadCreaseEdgeExtractor._();

  /// Canonical edge key independent of vertex winding order, quantized to 0.02 mm (50 units/mm).
  static String edgeKey(CadPoint3D a, CadPoint3D b) {
    final kA = '${(a.x * 50).round()}_${(a.y * 50).round()}_${(a.z * 50).round()}';
    final kB = '${(b.x * 50).round()}_${(b.y * 50).round()}_${(b.z * 50).round()}';
    return kA.compareTo(kB) <= 0 ? '$kA|$kB' : '$kB|$kA';
  }

  /// Computes the set of unique edge keys that represent true CAD feature edges.
  /// 
  /// - **Naked Boundary Edges** (incident to only 1 face, e.g. sheet borders or open cuts) -> KEPT.
  /// - **Coplanar Edges** (angle < 1°, e.g. quad triangulation diagonals) -> DISCARDED.
  /// - **Smooth Curve Edges** (angle < [creaseAngleThresholdDeg], e.g. bend facet strips) -> DISCARDED.
  /// - **Sharp Crease Edges** (angle >= [creaseAngleThresholdDeg], e.g. 90° or 45° bends/rims) -> KEPT.
  static Set<String> computeSurvivingCreaseKeys(
    Iterable<CadFoldedPolygon3D> polygons, {
    double creaseAngleThresholdDeg = 24.0,
    CadPoint3D? pivot,
  }) {
    final cosThreshold = math.cos(creaseAngleThresholdDeg * math.pi / 180.0);
    final edgeNormals = <String, List<CadPoint3D>>{};

    final pX = pivot?.x ?? 0.0;
    final pY = pivot?.y ?? 0.0;
    final pZ = pivot?.z ?? 0.0;

    for (final poly in polygons) {
      if (poly.vertices.length < 3) continue;

      // Normalize polygon unit normal
      final n = poly.normal;
      final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
      final unitN = lenN > 1e-6
          ? CadPoint3D(n.x / lenN, n.y / lenN, n.z / lenN)
          : const CadPoint3D(0.0, 0.0, 1.0);

      // Outer polygon loop
      final verts = poly.vertices;
      for (int i = 0; i < verts.length; i++) {
        final v0 = verts[i];
        final v1 = verts[(i + 1) % verts.length];
        final p0 = CadPoint3D(v0.x - pX, v0.y - pY, v0.z - pZ);
        final p1 = CadPoint3D(v1.x - pX, v1.y - pY, v1.z - pZ);

        final dx = p1.x - p0.x;
        final dy = p1.y - p0.y;
        final dz = p1.z - p0.z;
        if (dx * dx + dy * dy + dz * dz < 1e-6) continue;

        final key = edgeKey(p0, p1);
        edgeNormals.putIfAbsent(key, () => []).add(unitN);
      }

      // Inner hole cutout loops (punch holes, slots, coupler cutouts)
      for (final hole in poly.holes) {
        if (hole.length < 3) continue;
        for (int i = 0; i < hole.length; i++) {
          final h0 = hole[i];
          final h1 = hole[(i + 1) % hole.length];
          final p0 = CadPoint3D(h0.x - pX, h0.y - pY, h0.z - pZ);
          final p1 = CadPoint3D(h1.x - pX, h1.y - pY, h1.z - pZ);

          final dx = p1.x - p0.x;
          final dy = p1.y - p0.y;
          final dz = p1.z - p0.z;
          if (dx * dx + dy * dy + dz * dz < 1e-6) continue;

          final key = edgeKey(p0, p1);
          edgeNormals.putIfAbsent(key, () => []).add(unitN);
        }
      }
    }

    final survivingKeys = <String>{};

    edgeNormals.forEach((key, normals) {
      if (normals.length == 1) {
        // Naked boundary edge -> KEEP
        survivingKeys.add(key);
      } else if (normals.length >= 2) {
        // Find maximum dihedral divergence among adjacent face normals
        double minDot = 1.0;
        for (int i = 0; i < normals.length - 1; i++) {
          for (int j = i + 1; j < normals.length; j++) {
            final dot = (normals[i].x * normals[j].x +
                         normals[i].y * normals[j].y +
                         normals[i].z * normals[j].z).clamp(-1.0, 1.0);
            if (dot < minDot) minDot = dot;
          }
        }

        // If minDot <= cosThreshold (angle >= threshold), it's a sharp crease -> KEEP
        if (minDot <= cosThreshold) {
          survivingKeys.add(key);
        }
      }
    });

    return survivingKeys;
  }

  /// Extracts unique, clean 3D line segments for direct GPU line buffer emission.
  static List<(CadPoint3D, CadPoint3D)> extractCreaseSegments(
    Iterable<CadFoldedPolygon3D> polygons, {
    double creaseAngleThresholdDeg = 24.0,
    CadPoint3D? pivot,
  }) {
    final survivingKeys = computeSurvivingCreaseKeys(
      polygons,
      creaseAngleThresholdDeg: creaseAngleThresholdDeg,
      pivot: pivot,
    );

    final pX = pivot?.x ?? 0.0;
    final pY = pivot?.y ?? 0.0;
    final pZ = pivot?.z ?? 0.0;

    final emittedKeys = <String>{};
    final segments = <(CadPoint3D, CadPoint3D)>[];

    for (final poly in polygons) {
      if (poly.vertices.length < 3) continue;

      // Check outer loop
      final verts = poly.vertices;
      for (int i = 0; i < verts.length; i++) {
        final v0 = verts[i];
        final v1 = verts[(i + 1) % verts.length];
        final p0 = CadPoint3D(v0.x - pX, v0.y - pY, v0.z - pZ);
        final p1 = CadPoint3D(v1.x - pX, v1.y - pY, v1.z - pZ);

        final key = edgeKey(p0, p1);
        if (survivingKeys.contains(key) && emittedKeys.add(key)) {
          segments.add((p0, p1));
        }
      }

      // Check holes
      for (final hole in poly.holes) {
        if (hole.length < 3) continue;
        for (int i = 0; i < hole.length; i++) {
          final h0 = hole[i];
          final h1 = hole[(i + 1) % hole.length];
          final p0 = CadPoint3D(h0.x - pX, h0.y - pY, h0.z - pZ);
          final p1 = CadPoint3D(h1.x - pX, h1.y - pY, h1.z - pZ);

          final key = edgeKey(p0, p1);
          if (survivingKeys.contains(key) && emittedKeys.add(key)) {
            segments.add((p0, p1));
          }
        }
      }
    }

    return segments;
  }

  /// Extracts tangent edges (smooth fillet transitions where dihedral angle is between 1.5° and [creaseAngleThresholdDeg]).
  /// Returns a list of segments along with the averaged face normal at the tangent seam.
  static List<(CadPoint3D, CadPoint3D, CadPoint3D)> extractTangentSegments(
    Iterable<CadFoldedPolygon3D> polygons, {
    double minAngleDeg = 1.5,
    double creaseAngleThresholdDeg = 24.0,
    CadPoint3D? pivot,
  }) {
    final cosMinAngle = math.cos(minAngleDeg * math.pi / 180.0);
    final cosCreaseAngle = math.cos(creaseAngleThresholdDeg * math.pi / 180.0);

    final pX = pivot?.x ?? 0.0;
    final pY = pivot?.y ?? 0.0;
    final pZ = pivot?.z ?? 0.0;

    final edgeNormals = <String, List<CadPoint3D>>{};
    final edgeSegs = <String, (CadPoint3D, CadPoint3D)>{};

    for (final poly in polygons) {
      if (poly.vertices.length < 3) continue;

      final n = poly.normal;
      final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
      final unitN = lenN > 1e-6
          ? CadPoint3D(n.x / lenN, n.y / lenN, n.z / lenN)
          : const CadPoint3D(0.0, 0.0, 1.0);

      final verts = poly.vertices;
      for (int i = 0; i < verts.length; i++) {
        final v0 = verts[i];
        final v1 = verts[(i + 1) % verts.length];
        final p0 = CadPoint3D(v0.x - pX, v0.y - pY, v0.z - pZ);
        final p1 = CadPoint3D(v1.x - pX, v1.y - pY, v1.z - pZ);

        final dx = p1.x - p0.x;
        final dy = p1.y - p0.y;
        final dz = p1.z - p0.z;
        if (dx * dx + dy * dy + dz * dz < 1e-6) continue;

        final key = edgeKey(p0, p1);
        edgeNormals.putIfAbsent(key, () => []).add(unitN);
        edgeSegs.putIfAbsent(key, () => (p0, p1));
      }
    }

    final tangentSegments = <(CadPoint3D, CadPoint3D, CadPoint3D)>[];

    edgeNormals.forEach((key, normals) {
      if (normals.length == 2) {
        final dot = (normals[0].x * normals[1].x +
                     normals[0].y * normals[1].y +
                     normals[0].z * normals[1].z).clamp(-1.0, 1.0);
        // Tangent edge: dihedral angle is between minAngleDeg (e.g. 1.5°) and creaseAngleThresholdDeg (e.g. 24°)
        if (dot < cosMinAngle && dot >= cosCreaseAngle) {
          final seg = edgeSegs[key]!;
          final avgNx = (normals[0].x + normals[1].x) * 0.5;
          final avgNy = (normals[0].y + normals[1].y) * 0.5;
          final avgNz = (normals[0].z + normals[1].z) * 0.5;
          tangentSegments.add((seg.$1, seg.$2, CadPoint3D(avgNx, avgNy, avgNz)));
        }
      }
    });

    return tangentSegments;
  }
}
