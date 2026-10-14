import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import '../../sheet_metal_studio/models/cad_primitives.dart';
import '../../sheet_metal_studio/engine/kinematic_fold_engine.dart';

/// Represents a validated 3D ray hit against a folded CAD polygon.
class AssemblyRayHit {
  final CadFoldedPolygon3D polygon;
  final double distance;
  final CadPoint3D hitPoint;
  final bool isFrontFacing;

  const AssemblyRayHit({
    required this.polygon,
    required this.distance,
    required this.hitPoint,
    required this.isFrontFacing,
  });
}

/// Robust, mathematically sound 3D raycaster and hit-testing engine for Assembly Studio.
///
/// Features:
/// 1. True 3D ray-to-polygon planar intersection with exact point-in-polygon & hole bypass.
/// 2. Frontmost surface determination sorted by ray distance `t` (closest to camera).
/// 3. Back-face vs front-face prioritization for solid surfaces.
/// 4. Boundary edge snapping within pixel tolerance (only when no solid surface is directly hit).
class AssemblyRaycaster {
  /// Casts a 3D ray in CAD model coordinates through the assembly mesh.
  ///
  /// Returns the nearest frontmost polygon intersected by the ray, or `null` if the ray misses all geometry.
  static AssemblyRayHit? raycast({
    required vm_math.Vector3 rayOrigin,
    required vm_math.Vector3 rayDirection,
    required FoldedMeshResult mesh,
  }) {
    if (mesh.allPolygons.isEmpty) return null;

    final hits = <AssemblyRayHit>[];

    for (final poly in mesh.allPolygons) {
      if (poly.vertices.length < 3) continue;

      double nx = poly.normal.x;
      double ny = poly.normal.y;
      double nz = poly.normal.z;
      final nLenSq = nx * nx + ny * ny + nz * nz;
      if (nLenSq < 1e-6) {
        final v0 = poly.vertices[0];
        final v1 = poly.vertices[1];
        final v2 = poly.vertices[2];
        final e1x = v1.x - v0.x, e1y = v1.y - v0.y, e1z = v1.z - v0.z;
        final e2x = v2.x - v0.x, e2y = v2.y - v0.y, e2z = v2.z - v0.z;
        nx = e1y * e2z - e1z * e2y;
        ny = e1z * e2x - e1x * e2z;
        nz = e1x * e2y - e1y * e2x;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len < 1e-6) continue;
        nx /= len;
        ny /= len;
        nz /= len;
      }

      final denom = nx * rayDirection.x + ny * rayDirection.y + nz * rayDirection.z;
      if (denom.abs() < 1e-7) continue; // Ray is parallel to polygon plane

      final v0 = poly.vertices[0];
      final t = ((v0.x - rayOrigin.x) * nx + (v0.y - rayOrigin.y) * ny + (v0.z - rayOrigin.z) * nz) / denom;
      if (t < 0.01) continue; // Behind ray origin

      final hitX = rayOrigin.x + rayDirection.x * t;
      final hitY = rayOrigin.y + rayDirection.y * t;
      final hitZ = rayOrigin.z + rayDirection.z * t;

      // Project 3D polygon and hit point onto 2D plane by dropping the dominant normal axis
      final absNx = nx.abs();
      final absNy = ny.abs();
      final absNz = nz.abs();

      final int axis; // 0 = drop X, 1 = drop Y, 2 = drop Z
      if (absNz >= absNx && absNz >= absNy) {
        axis = 2;
      } else if (absNy >= absNx) {
        axis = 1;
      } else {
        axis = 0;
      }

      Offset to2d(CadPoint3D pt) {
        switch (axis) {
          case 0:
            return Offset(pt.y, pt.z);
          case 1:
            return Offset(pt.x, pt.z);
          default:
            return Offset(pt.x, pt.y);
        }
      }

      final hit2d = axis == 0
          ? Offset(hitY, hitZ)
          : (axis == 1 ? Offset(hitX, hitZ) : Offset(hitX, hitY));

      final outer2d = [for (final v in poly.vertices) to2d(v)];
      if (!isPointInPolygon2D(hit2d, outer2d)) continue;

      // Ensure ray did not pass through a cutout hole (punch hole, slot, notch)
      bool insideHole = false;
      for (final hole in poly.holes) {
        if (hole.length < 3) continue;
        final hole2d = [for (final v in hole) to2d(v)];
        if (isPointInPolygon2D(hit2d, hole2d)) {
          insideHole = true;
          break;
        }
      }
      if (insideHole) continue;

      hits.add(AssemblyRayHit(
        polygon: poly,
        distance: t,
        hitPoint: CadPoint3D(hitX, hitY, hitZ),
        isFrontFacing: denom < 0.0,
      ));
    }

    if (hits.isEmpty) return null;

    // Sort by ray distance (closest to eye first)
    // If one hit is a weld bead and distance difference is within 2.0mm, prefer the weld bead attached on top
    hits.sort((a, b) {
      final aIsWeld = a.polygon.faceId.startsWith('weld_');
      final bIsWeld = b.polygon.faceId.startsWith('weld_');
      final dDiff = a.distance - b.distance;
      if (aIsWeld != bIsWeld && dDiff.abs() <= 2.0) {
        return aIsWeld ? -1 : 1;
      }
      if (dDiff.abs() > 0.25) {
        return dDiff.compareTo(0.0);
      }
      if (a.isFrontFacing != b.isFrontFacing) {
        return a.isFrontFacing ? -1 : 1;
      }
      return dDiff.compareTo(0.0);
    });

    return hits.first;
  }

  /// Proximity edge hit-test: finds the polygon whose boundary edge is closest to the 2D cursor,
  /// strictly within [maxScreenDistance] pixels.
  static CadFoldedPolygon3D? findClosestEdgePolygon({
    required Offset cursorLocalPos,
    required Size size,
    required FoldedMeshResult mesh,
    Camera? camera,
    Offset? Function(CadPoint3D pt)? projectPoint,
    double maxScreenDistance = 8.0,
  }) {
    if (mesh.allPolygons.isEmpty) return null;

    final pivot = mesh.center;
    CadFoldedPolygon3D? bestPoly;
    double bestDist = maxScreenDistance;

    for (final poly in mesh.allPolygons) {
      if (poly.vertices.length < 2) continue;

      // Check all boundary segments of the polygon
      for (int i = 0; i < poly.vertices.length; i++) {
        final vA = poly.vertices[i];
        final vB = poly.vertices[(i + 1) % poly.vertices.length];

        final Offset? sA;
        final Offset? sB;
        if (projectPoint != null) {
          sA = projectPoint(vA);
          sB = projectPoint(vB);
        } else if (camera != null) {
          final wA = vm_math.Vector3(vA.x - pivot.x, vA.y - pivot.y, vA.z - pivot.z);
          final wB = vm_math.Vector3(vB.x - pivot.x, vB.y - pivot.y, vB.z - pivot.z);
          sA = camera.worldToScreen(wA, size);
          sB = camera.worldToScreen(wB, size);
        } else {
          continue;
        }
        if (sA == null || sB == null) continue;

        final d = distToSegment2D(cursorLocalPos, sA, sB);
        if (d < bestDist) {
          bestDist = d;
          bestPoly = poly;
        }
      }
    }

    return bestPoly;
  }

  /// 2D point-in-polygon test with boundary-inclusive tolerance.
  static bool isPointInPolygon2D(Offset pt, List<Offset> polygon) {
    if (polygon.length < 3) return false;

    bool inside = false;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].dx, yi = polygon[i].dy;
      final xj = polygon[j].dx, yj = polygon[j].dy;

      // Check if point lies directly on or close to segment (boundary hit)
      if (distToSegment2D(pt, polygon[i], polygon[j]) < 1e-2) {
        return true;
      }

      final intersect = ((yi > pt.dy) != (yj > pt.dy)) &&
          (pt.dx < (xj - xi) * (pt.dy - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Calculates minimum perpendicular distance from 2D point [p] to segment [a]-[b].
  static double distToSegment2D(Offset p, Offset a, Offset b) {
    final l2 = (b.dx - a.dx) * (b.dx - a.dx) + (b.dy - a.dy) * (b.dy - a.dy);
    if (l2 < 1e-6) return (p - a).distance;

    var t = ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - proj).distance;
  }

  /// Snaps screen point [cursorPos] to the nearest 3D candidate point within [pixelTolerance].
  static CadPoint3D? snapToCandidatePoints({
    required Offset cursorPos,
    required List<CadPoint3D> candidatePoints,
    required Offset? Function(CadPoint3D) projectPoint,
    double pixelTolerance = 14.0,
  }) {
    CadPoint3D? bestPoint;
    double bestDist = pixelTolerance;

    for (final pt in candidatePoints) {
      final screenPt = projectPoint(pt);
      if (screenPt == null || screenPt == Offset.zero) continue;
      final d = (cursorPos - screenPt).distance;
      if (d < bestDist) {
        bestDist = d;
        bestPoint = pt;
      }
    }
    return bestPoint;
  }
}
