import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import 'package:trufold_studio/assembly_studio/engine/assembly_raycaster.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

/// Result of 2-entity vicinity validation and contact seam resolution.
class WeldVicinityResult {
  final AssemblyPart partA;
  final AssemblyPart partB;
  final CadPoint3D weldPoint;
  final CadPoint3D weldAxis;
  final CadPoint3D legDir1;
  final CadPoint3D legDir2;
  final double seamLengthMm;
  final List<CadPoint3D> smoothedPathPoints;

  const WeldVicinityResult({
    required this.partA,
    required this.partB,
    required this.weldPoint,
    required this.weldAxis,
    required this.legDir1,
    required this.legDir2,
    required this.seamLengthMm,
    required this.smoothedPathPoints,
  });
}

/// Helper for smoothing shaky mouse welding strokes and enforcing 2-entity vicinity.
class AssemblyWeldSmoothingHelper {
  /// Smoothens a 2D screen stroke using Chaikin's corner-cutting algorithm.
  static List<Offset> smooth2DPath(List<Offset> rawPath, {int iterations = 2}) {
    if (rawPath.length < 3) return List<Offset>.from(rawPath);

    // 1. Remove micro-jitter points (< 3.0 px distance)
    final filtered = <Offset>[rawPath.first];
    for (int i = 1; i < rawPath.length; i++) {
      if ((rawPath[i] - filtered.last).distance >= 3.0) {
        filtered.add(rawPath[i]);
      }
    }
    if (filtered.length < 3) return filtered;

    // 2. Chaikin's algorithm
    List<Offset> current = filtered;
    for (int it = 0; it < iterations; it++) {
      final smoothed = <Offset>[current.first];
      for (int i = 0; i < current.length - 1; i++) {
        final p0 = current[i];
        final p1 = current[i + 1];
        final q = Offset(0.75 * p0.dx + 0.25 * p1.dx, 0.75 * p0.dy + 0.25 * p1.dy);
        final r = Offset(0.25 * p0.dx + 0.75 * p1.dx, 0.25 * p0.dy + 0.75 * p1.dy);
        smoothed.add(q);
        smoothed.add(r);
      }
      smoothed.add(current.last);
      current = smoothed;
    }
    return current;
  }

  /// Smoothens a 3D surface point list using 3D Chaikin subdivision.
  static List<CadPoint3D> smooth3DPoints(List<CadPoint3D> rawPoints, {int iterations = 2}) {
    if (rawPoints.length < 3) return List<CadPoint3D>.from(rawPoints);

    // 1. Filter out points too close to each other (< 2.0 mm)
    final filtered = <CadPoint3D>[rawPoints.first];
    for (int i = 1; i < rawPoints.length; i++) {
      if (rawPoints[i].distanceTo(filtered.last) >= 2.0) {
        filtered.add(rawPoints[i]);
      }
    }
    if (filtered.length < 3) return filtered;

    // 2. 3D Chaikin's algorithm
    List<CadPoint3D> current = filtered;
    for (int it = 0; it < iterations; it++) {
      final smoothed = <CadPoint3D>[current.first];
      for (int i = 0; i < current.length - 1; i++) {
        final p0 = current[i];
        final p1 = current[i + 1];
        final q = CadPoint3D(0.75 * p0.x + 0.25 * p1.x, 0.75 * p0.y + 0.25 * p1.y, 0.75 * p0.z + 0.25 * p1.z);
        final r = CadPoint3D(0.25 * p0.x + 0.75 * p1.x, 0.25 * p0.y + 0.75 * p1.y, 0.25 * p0.z + 0.75 * p1.z);
        smoothed.add(q);
        smoothed.add(r);
      }
      smoothed.add(current.last);
      current = smoothed;
    }
    return current;
  }

  /// Validates that TWO distinct entities are present within the welding fillet vicinity (<= 25mm),
  /// and resolves the contact seam line and leg directions to glue both entities together.
  ///
  /// Returns [null] if only 1 entity is present (single-surface welding restricted).
  static WeldVicinityResult? resolveTwoEntityWeldVicinity({
    required List<CadPoint3D> raw3DPoints,
    required Offset startScreen,
    required Offset endScreen,
    required Size viewportSize,
    required FoldedMeshResult mesh,
    required List<AssemblyPart> allParts,
    required AssemblyPart? Function(String faceId) findPartForFaceId,
    required (vm_math.Vector3, vm_math.Vector3) Function(Offset screenPoint) getRayFromScreen,
    Set<String>? hitPartIds,
    double maxVicinityDistanceMm = 25.0,
  }) {
    if (raw3DPoints.isEmpty && (endScreen - startScreen).distance < 4.0) {
      return null;
    }

    // 1. Identify candidate parts along stroke via raycast and hit tracking
    AssemblyPart? partA;
    AssemblyPart? partB;
    CadPoint3D? normalA;
    CadPoint3D? normalB;

    if (hitPartIds != null && hitPartIds.length >= 2) {
      final ids = hitPartIds.toList();
      partA = allParts.where((p) => p.id == ids[0]).firstOrNull;
      partB = allParts.where((p) => p.id == ids[1]).firstOrNull;
    }

    final (rayStartOrigin, rayStartDir) = getRayFromScreen(startScreen);
    final (rayEndOrigin, rayEndDir) = getRayFromScreen(endScreen);

    final hitStart = AssemblyRaycaster.raycast(rayOrigin: rayStartOrigin, rayDirection: rayStartDir, mesh: mesh);
    final hitEnd = AssemblyRaycaster.raycast(rayOrigin: rayEndOrigin, rayDirection: rayEndDir, mesh: mesh);

    if (hitStart != null) {
      final p = findPartForFaceId(hitStart.polygon.faceId);
      if (partA == null) {
        partA = p;
        normalA = hitStart.polygon.normal;
      } else if (p != null && p.id != partA.id && partB == null) {
        partB = p;
        normalB = hitStart.polygon.normal;
      }
    }
    if (hitEnd != null) {
      final p = findPartForFaceId(hitEnd.polygon.faceId);
      if (p != null) {
        if (partA == null) {
          partA = p;
          normalA = hitEnd.polygon.normal;
        } else if (p.id != partA.id && partB == null) {
          partB = p;
          normalB = hitEnd.polygon.normal;
        }
      }
    }

    // Intermediate samples along screen line
    if (partB == null) {
      for (double t = 0.15; t <= 0.85; t += 0.15) {
        final sampleScreen = Offset.lerp(startScreen, endScreen, t)!;
        final (rayOrg, rayDir) = getRayFromScreen(sampleScreen);
        final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrg, rayDirection: rayDir, mesh: mesh);
        if (hit != null) {
          final p = findPartForFaceId(hit.polygon.faceId);
          if (p != null) {
            if (partA == null) {
              partA = p;
              normalA = hit.polygon.normal;
            } else if (p.id != partA.id) {
              partB = p;
              normalB = hit.polygon.normal;
              break;
            }
          }
        }
      }
    }

    // 2. If partB is still not found by direct raycast, search candidate parts within physical contact vicinity
    final strokePoints = raw3DPoints.isNotEmpty
        ? raw3DPoints
        : [hitStart?.hitPoint ?? const CadPoint3D(0, 0, 0), hitEnd?.hitPoint ?? const CadPoint3D(0, 0, 0)];

    final double contactToleranceMm = maxVicinityDistanceMm;

    if (partA != null && partB == null) {
      AssemblyPart? closestPart;
      double closestDist = double.infinity;

      for (final p in allParts) {
        if (!p.isVisible || p.id == partA.id) continue;

        for (final pt in strokePoints) {
          final d = _pointToPartDistance(pt, p, mesh);
          if (d <= contactToleranceMm && d < closestDist) {
            closestDist = d;
            closestPart = p;
          }
        }
      }

      if (closestPart != null) {
        partB = closestPart;
      }
    }

    // 3. Strict 2-Entity Requirement: Restrict welding on simply one surface! (SS2 & SS3)
    if (partA == null || partB == null || partA.id == partB.id) {
      return null; // Rejected: 2 distinct entities must be present in vicinity!
    }

    // 4. Verify that the stroke touches/bridges both entity surfaces
    bool hasContactA = (hitPartIds != null && hitPartIds.contains(partA.id));
    bool hasContactB = (hitPartIds != null && hitPartIds.contains(partB.id));
    if (!hasContactA || !hasContactB) {
      for (final pt in strokePoints) {
        if (!hasContactA && _pointToPartDistance(pt, partA, mesh) <= contactToleranceMm) {
          hasContactA = true;
        }
        if (!hasContactB && _pointToPartDistance(pt, partB, mesh) <= contactToleranceMm) {
          hasContactB = true;
        }
        if (hasContactA && hasContactB) break;
      }
    }
    if (!hasContactA || !hasContactB) {
      return null;
    }

    // 5. Smooth the 3D path points
    final smoothedPts = smooth3DPoints(strokePoints, iterations: 2);

    // 6. Calculate Seam Axis and Root Point
    CadPoint3D weldPt;
    CadPoint3D axisVector;
    double seamLength;

    if (smoothedPts.length >= 2) {
      final pFirst = smoothedPts.first;
      final pLast = smoothedPts.last;
      weldPt = CadPoint3D((pFirst.x + pLast.x) / 2.0, (pFirst.y + pLast.y) / 2.0, (pFirst.z + pLast.z) / 2.0);
      axisVector = CadPoint3D(pLast.x - pFirst.x, pLast.y - pFirst.y, pLast.z - pFirst.z);
      double totalDist = 0.0;
      for (int i = 1; i < smoothedPts.length; i++) {
        totalDist += smoothedPts[i].distanceTo(smoothedPts[i - 1]);
      }
      seamLength = totalDist > 5.0 ? totalDist : axisVector.length;
    } else {
      weldPt = CadPoint3D(
        (partA.position.x + partB.position.x) / 2.0,
        (partA.position.y + partB.position.y) / 2.0,
        (partA.position.z + partB.position.z) / 2.0,
      );
      axisVector = const CadPoint3D(1.0, 0.0, 0.0);
      seamLength = 50.0;
    }

    if (axisVector.length < 1e-4) {
      axisVector = const CadPoint3D(1.0, 0.0, 0.0);
    }
    seamLength = seamLength.clamp(20.0, 800.0);

    // 7. Calculate gluing leg directions between Entity A and Entity B
    CadPoint3D leg1 = normalA ?? const CadPoint3D(0.0, 0.0, 1.0);
    CadPoint3D leg2 = normalB ?? const CadPoint3D(0.0, 1.0, 0.0);

    // Guarantee normals strictly point outward away from solid faces (never inverted underneath)
    if (leg1.z < -0.01 && (partA.position.z >= partB.position.z)) {
      leg1 = CadPoint3D(leg1.x, leg1.y, leg1.z.abs());
    }
    if (leg2.z < -0.01 && (partB.position.z >= partA.position.z)) {
      leg2 = CadPoint3D(leg2.x, leg2.y, leg2.z.abs());
    }

    return WeldVicinityResult(
      partA: partA,
      partB: partB,
      weldPoint: weldPt,
      weldAxis: axisVector,
      legDir1: leg1,
      legDir2: leg2,
      seamLengthMm: seamLength,
      smoothedPathPoints: smoothedPts,
    );
  }

  /// Calculates accurate geometric distance from a 3D point to part polygon surfaces.
  static double _pointToPartDistance(CadPoint3D pt, AssemblyPart part, [FoldedMeshResult? mesh]) {
    if (mesh != null) {
      double minPolyDist = double.infinity;
      bool found = false;
      for (final poly in mesh.allPolygons) {
        if (poly.faceId.startsWith(part.id) && poly.vertices.length >= 3) {
          found = true;
          final d = _pointToPolygonSurfaceDist(pt, poly);
          if (d < minPolyDist) minPolyDist = d;
          if (minPolyDist < 1.0) return minPolyDist;
        }
      }
      if (found && !minPolyDist.isInfinite) return minPolyDist;
    }

    // Fallback: check against part oriented local bounding box
    final localPt = part.toLocal(pt);
    final double minX = -10.0;
    final double maxX = part.length + 10.0;
    final double halfW = (part.flangeWidth > 0 ? part.flangeWidth : 40.0) / 2.0;
    final double minY = (part.type == AssemblyPartType.rung) ? -halfW - 10.0 : -20.0;
    final double maxY = (part.type == AssemblyPartType.rung) ? halfW + 10.0 : (part.flangeWidth > 0 ? part.flangeWidth + 20.0 : 50.0);
    final double minZ = -10.0;
    final double maxZ = math.max(part.height, 20.0) + 10.0;

    final dx = math.max(0.0, math.max(minX - localPt.x, localPt.x - maxX));
    final dy = math.max(0.0, math.max(minY - localPt.y, localPt.y - maxY));
    final dz = math.max(0.0, math.max(minZ - localPt.z, localPt.z - maxZ));

    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  static double _pointToPolygonSurfaceDist(CadPoint3D pt, CadFoldedPolygon3D poly) {
    final n = poly.normal;
    final v0 = poly.vertices.first;
    final dot = (pt.x - v0.x) * n.x + (pt.y - v0.y) * n.y + (pt.z - v0.z) * n.z;
    final planeDist = dot.abs();

    // Projected point on polygon plane
    final projX = pt.x - n.x * dot;
    final projY = pt.y - n.y * dot;
    final projZ = pt.z - n.z * dot;

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;
    for (final v in poly.vertices) {
      if (v.x < minX) minX = v.x; if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y; if (v.y > maxY) maxY = v.y;
      if (v.z < minZ) minZ = v.z; if (v.z > maxZ) maxZ = v.z;
    }
    const pad = 15.0; // 15mm tolerance around face boundary
    if (projX >= minX - pad && projX <= maxX + pad &&
        projY >= minY - pad && projY <= maxY + pad &&
        projZ >= minZ - pad && projZ <= maxZ + pad) {
      return planeDist;
    }

    // Nearest segment distance
    double minEdgeDist = double.infinity;
    for (int i = 0; i < poly.vertices.length; i++) {
      final vA = poly.vertices[i];
      final vB = poly.vertices[(i + 1) % poly.vertices.length];
      final d = _pointToSegmentDist(pt, vA, vB);
      if (d < minEdgeDist) minEdgeDist = d;
    }
    return minEdgeDist;
  }

  static double _pointToSegmentDist(CadPoint3D p, CadPoint3D a, CadPoint3D b) {
    final abX = b.x - a.x;
    final abY = b.y - a.y;
    final abZ = b.z - a.z;
    final abLenSq = abX * abX + abY * abY + abZ * abZ;
    if (abLenSq < 1e-6) return p.distanceTo(a);

    final apX = p.x - a.x;
    final apY = p.y - a.y;
    final apZ = p.z - a.z;
    final t = ((apX * abX + apY * abY + apZ * abZ) / abLenSq).clamp(0.0, 1.0);

    final q = CadPoint3D(a.x + abX * t, a.y + abY * t, a.z + abZ * t);
    return p.distanceTo(q);
  }
}
