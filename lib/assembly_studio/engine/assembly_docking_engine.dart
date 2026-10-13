import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../sheet_metal_studio/models/cad_primitives.dart';
import '../../sheet_metal_studio/engine/kinematic_fold_engine.dart';
import '../models/assembly_part.dart';
import '../models/assembly_docking_zone.dart';

/// Pure CAD mathematical engine for extracting snap points, detecting drop zones,
/// and computing magnetic docking relationships across assembly entities.
class AssemblyDockingEngine {
  /// Extracts all active snapping points on an [AssemblyPart]:
  /// 1. Bounding box corners & end centers
  /// 2. Bounding box 12 edge midpoints & 3D centroid
  /// 3. Hole center points & perimeter endpoints (punched slots, bore holes, cutouts)
  /// 4. Sketched feature centers & endpoints (holes, slots, cuts, bend lines)
  static List<AssemblySnapPoint> getAllSnapPointsForPart(
    AssemblyPart part, {
    FoldedMeshResult? cachedMesh,
  }) {
    final points = <AssemblySnapPoint>[];
    final bounds = part.getLocalBounds();
    final minPt = bounds.$1;
    final maxPt = bounds.$2;
    final midX = (minPt.x + maxPt.x) / 2.0;
    final midY = (minPt.y + maxPt.y) / 2.0;
    final midZ = (minPt.z + maxPt.z) / 2.0;

    // 1. Bounding Box 8 Corners / Ends
    final cornerLocals = [
      CadPoint3D(minPt.x, minPt.y, minPt.z),
      CadPoint3D(maxPt.x, minPt.y, minPt.z),
      CadPoint3D(maxPt.x, maxPt.y, minPt.z),
      CadPoint3D(minPt.x, maxPt.y, minPt.z),
      CadPoint3D(minPt.x, minPt.y, maxPt.z),
      CadPoint3D(maxPt.x, minPt.y, maxPt.z),
      CadPoint3D(maxPt.x, maxPt.y, maxPt.z),
      CadPoint3D(minPt.x, maxPt.y, maxPt.z),
    ];
    for (int i = 0; i < cornerLocals.length; i++) {
      final loc = cornerLocals[i];
      points.add(AssemblySnapPoint(
        id: '${part.id}_corner_$i',
        partId: part.id,
        worldPosition: part.toWorld(loc),
        localPosition: loc,
        type: AssemblySnapPointType.boundingBoxCorner,
        label: '■ Corner (${part.name})',
      ));
    }

    // 2. Axial End Cap Centers (Start & Finish of profile along X)
    points.add(AssemblySnapPoint(
      id: '${part.id}_end_start',
      partId: part.id,
      worldPosition: part.toWorld(CadPoint3D(minPt.x, midY, midZ)),
      localPosition: CadPoint3D(minPt.x, midY, midZ),
      normal: const CadPoint3D(-1.0, 0.0, 0.0),
      type: AssemblySnapPointType.boundingBoxFaceCenter,
      label: '● End Cap Start (${part.name})',
    ));
    points.add(AssemblySnapPoint(
      id: '${part.id}_end_finish',
      partId: part.id,
      worldPosition: part.toWorld(CadPoint3D(maxPt.x, midY, midZ)),
      localPosition: CadPoint3D(maxPt.x, midY, midZ),
      normal: const CadPoint3D(1.0, 0.0, 0.0),
      type: AssemblySnapPointType.boundingBoxFaceCenter,
      label: '● End Cap Finish (${part.name})',
    ));

    // 3. Side / Web Face Centers
    final faceCenters = [
      CadPoint3D(midX, minPt.y, midZ),
      CadPoint3D(midX, maxPt.y, midZ),
      CadPoint3D(midX, midY, minPt.z),
      CadPoint3D(midX, midY, maxPt.z),
    ];
    for (int i = 0; i < faceCenters.length; i++) {
      final loc = faceCenters[i];
      points.add(AssemblySnapPoint(
        id: '${part.id}_face_$i',
        partId: part.id,
        worldPosition: part.toWorld(loc),
        localPosition: loc,
        type: AssemblySnapPointType.boundingBoxFaceCenter,
        label: '● Face Center (${part.name})',
      ));
    }

    // 4. Overall 3D Centroid
    points.add(AssemblySnapPoint(
      id: '${part.id}_centroid',
      partId: part.id,
      worldPosition: part.toWorld(CadPoint3D(midX, midY, midZ)),
      localPosition: CadPoint3D(midX, midY, midZ),
      type: AssemblySnapPointType.boundingBoxCentroid,
      label: '✦ Centroid (${part.name})',
    ));

    // 5. 12 Bounding Box Edge Midpoints
    final edgeLocals = [
      // 4 along X
      CadPoint3D(midX, minPt.y, minPt.z),
      CadPoint3D(midX, maxPt.y, minPt.z),
      CadPoint3D(midX, minPt.y, maxPt.z),
      CadPoint3D(midX, maxPt.y, maxPt.z),
      // 4 along Y
      CadPoint3D(minPt.x, midY, minPt.z),
      CadPoint3D(maxPt.x, midY, minPt.z),
      CadPoint3D(minPt.x, midY, maxPt.z),
      CadPoint3D(maxPt.x, midY, maxPt.z),
      // 4 along Z
      CadPoint3D(minPt.x, minPt.y, midZ),
      CadPoint3D(maxPt.x, minPt.y, midZ),
      CadPoint3D(maxPt.x, maxPt.y, midZ),
      CadPoint3D(minPt.x, maxPt.y, midZ),
    ];
    for (int i = 0; i < edgeLocals.length; i++) {
      final loc = edgeLocals[i];
      points.add(AssemblySnapPoint(
        id: '${part.id}_edge_$i',
        partId: part.id,
        worldPosition: part.toWorld(loc),
        localPosition: loc,
        type: AssemblySnapPointType.boundingBoxEdgeCenter,
        label: '▲ Edge Midpoint (${part.name})',
      ));
    }

    // 6. Hole Center Points & Hole Perimeter Endpoints from Mesh Geometry
    final mesh = cachedMesh ?? part.build3DMesh();
    int holeCounter = 0;
    for (final poly in mesh.polygons) {
      if (poly.holes.isEmpty) continue;
      for (final holeLoop in poly.holes) {
        if (holeLoop.length < 3) continue;
        holeCounter++;

        // Compute Hole Centroid / Center Point
        double sumX = 0.0;
        double sumY = 0.0;
        double sumZ = 0.0;
        for (final v in holeLoop) {
          sumX += v.x;
          sumY += v.y;
          sumZ += v.z;
        }
        final holeCenterWorld = CadPoint3D(
          sumX / holeLoop.length,
          sumY / holeLoop.length,
          sumZ / holeLoop.length,
        );
        final holeCenterLocal = part.toLocal(holeCenterWorld);

        points.add(AssemblySnapPoint(
          id: '${part.id}_hole_center_$holeCounter',
          partId: part.id,
          worldPosition: holeCenterWorld,
          localPosition: holeCenterLocal,
          normal: poly.normal,
          type: AssemblySnapPointType.holeCenter,
          label: '⌖ Hole Center #$holeCounter (${part.name})',
          featureId: 'hole_$holeCounter',
        ));

        // Add 4 cardinal perimeter endpoints around the hole outline (e.g. circle / slot extremes)
        final step = math.max(1, holeLoop.length ~/ 4);
        for (int pIdx = 0; pIdx < holeLoop.length; pIdx += step) {
          final pWorld = holeLoop[pIdx];
          final pLocal = part.toLocal(pWorld);
          points.add(AssemblySnapPoint(
            id: '${part.id}_hole_${holeCounter}_pt_$pIdx',
            partId: part.id,
            worldPosition: pWorld,
            localPosition: pLocal,
            normal: poly.normal,
            type: AssemblySnapPointType.holePerimeter,
            label: '○ Hole Rim (${part.name})',
            featureId: 'hole_$holeCounter',
          ));
        }
      }
    }

    // 7. Sketched Features: Centers and Endpoints (Circle holes, slots, cuts, bend lines)
    for (int sIdx = 0; sIdx < part.sketches.length; sIdx++) {
      final sk = part.sketches[sIdx];
      CadPoint3D sketchLocalCenter;
      CadPoint3D sketchNormal;

      if (sk.targetFace == 'web' || sk.targetFace.endsWith('_web') || sk.targetFace.isEmpty) {
        sketchLocalCenter = CadPoint3D(sk.localCenter.x, 0.0, sk.localCenter.y);
        sketchNormal = const CadPoint3D(0.0, 1.0, 0.0);
      } else if (sk.targetFace.contains('top')) {
        sketchLocalCenter = CadPoint3D(sk.localCenter.x, sk.localCenter.y, maxPt.z);
        sketchNormal = const CadPoint3D(0.0, 0.0, 1.0);
      } else {
        sketchLocalCenter = CadPoint3D(sk.localCenter.x, sk.localCenter.y, minPt.z);
        sketchNormal = const CadPoint3D(0.0, 0.0, -1.0);
      }

      final sketchWorldCenter = part.toWorld(sketchLocalCenter);

      // Sketch Center Point
      points.add(AssemblySnapPoint(
        id: '${part.id}_sk_center_${sk.id}',
        partId: part.id,
        worldPosition: sketchWorldCenter,
        localPosition: sketchLocalCenter,
        normal: part.normalToWorld(sketchNormal),
        type: AssemblySnapPointType.sketchCenter,
        label: '⌖ Sketch Center: ${sk.featureType} (${part.name})',
        featureId: sk.id,
      ));

      // Sketch Endpoints / Corner Vertices
      final hw = sk.widthMm / 2.0;
      final hh = sk.heightMm / 2.0;
      final rad = sk.angleDeg * (math.pi / 180.0);
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      final cornerOffsets = [
        Offset(-hw * cosA - -hh * sinA, -hw * sinA + -hh * cosA),
        Offset(hw * cosA - -hh * sinA, hw * sinA + -hh * cosA),
        Offset(hw * cosA - hh * sinA, hw * sinA + hh * cosA),
        Offset(-hw * cosA - hh * sinA, -hw * sinA + hh * cosA),
      ];

      for (int cIdx = 0; cIdx < cornerOffsets.length; cIdx++) {
        final off = cornerOffsets[cIdx];
        CadPoint3D cornerLocal;
        if (sk.targetFace == 'web' || sk.targetFace.endsWith('_web') || sk.targetFace.isEmpty) {
          cornerLocal = CadPoint3D(sk.localCenter.x + off.dx, 0.0, sk.localCenter.y + off.dy);
        } else {
          cornerLocal = CadPoint3D(sk.localCenter.x + off.dx, sk.localCenter.y + off.dy, sketchLocalCenter.z);
        }

        points.add(AssemblySnapPoint(
          id: '${part.id}_sk_end_${sk.id}_$cIdx',
          partId: part.id,
          worldPosition: part.toWorld(cornerLocal),
          localPosition: cornerLocal,
          normal: part.normalToWorld(sketchNormal),
          type: AssemblySnapPointType.sketchEndpoint,
          label: '◇ Sketch Endpoint #${cIdx + 1} (${part.name})',
          featureId: sk.id,
        ));
      }
    }

    return points;
  }

  /// Finds the closest snap point on [candidates] within screen-space [maxPixelDistance].
  static AssemblySnapPoint? findNearestSnapPoint({
    required Offset screenCursor,
    required List<AssemblySnapPoint> candidates,
    required Offset Function(CadPoint3D worldPt) projectPoint,
    double maxPixelDistance = 14.0,
  }) {
    AssemblySnapPoint? bestPoint;
    double bestDistance = maxPixelDistance;

    for (final pt in candidates) {
      final scr = projectPoint(pt.worldPosition);
      if (scr == Offset.zero) continue;
      final dist = (scr - screenCursor).distance;
      if (dist < bestDistance) {
        bestDistance = dist;
        bestPoint = pt;
      }
    }

    return bestPoint;
  }

  /// Generates predefined drop / docking zones for an [AssemblyPart]
  /// (e.g. punched rung slot zones, stile mounting cleat zones).
  static List<AssemblyDropZone> getDropZonesForPart(AssemblyPart part) {
    final zones = <AssemblyDropZone>[];

    // 1. Sketched rung slot entities act as drop zones for rungs
    for (final sk in part.sketches) {
      if (sk.isRungSlotEntity || sk.featureType == 'rung_slot') {
        final centerLocal = CadPoint3D(sk.localCenter.x, 0.0, sk.localCenter.y);
        zones.add(AssemblyDropZone(
          id: '${part.id}_dz_${sk.id}',
          partId: part.id,
          center: part.toWorld(centerLocal),
          size: CadPoint3D(sk.widthMm + 10.0, 30.0, sk.heightMm + 10.0),
          normal: part.normalToWorld(const CadPoint3D(0.0, 1.0, 0.0)),
          label: 'Rung Docking Slot (${part.name})',
          targetFace: 'web',
        ));
      }
    }

    // 2. Axial profile end docking zones
    final bounds = part.getLocalBounds();
    final minPt = bounds.$1;
    final maxPt = bounds.$2;
    final midY = (minPt.y + maxPt.y) / 2.0;
    final midZ = (minPt.z + maxPt.z) / 2.0;

    zones.add(AssemblyDropZone(
      id: '${part.id}_dz_start',
      partId: part.id,
      center: part.toWorld(CadPoint3D(minPt.x, midY, midZ)),
      size: const CadPoint3D(40.0, 60.0, 60.0),
      normal: part.normalToWorld(const CadPoint3D(-1.0, 0.0, 0.0)),
      label: 'End Mount A (${part.name})',
    ));

    zones.add(AssemblyDropZone(
      id: '${part.id}_dz_finish',
      partId: part.id,
      center: part.toWorld(CadPoint3D(maxPt.x, midY, midZ)),
      size: const CadPoint3D(40.0, 60.0, 60.0),
      normal: part.normalToWorld(const CadPoint3D(1.0, 0.0, 0.0)),
      label: 'End Mount B (${part.name})',
    ));

    return zones;
  }

  /// Detects if [draggedPart] is currently hovering inside any drop zone of [otherParts].
  static AssemblyDropZone? detectActiveDropZone({
    required AssemblyPart draggedPart,
    required List<AssemblyPart> otherParts,
    double toleranceMm = 25.0,
  }) {
    final draggedCenter = draggedPart.position;
    for (final other in otherParts) {
      if (other.id == draggedPart.id || !other.isVisible) continue;
      final zones = getDropZonesForPart(other);
      for (final zone in zones) {
        if (zone.containsPoint(draggedCenter, toleranceMm: toleranceMm)) {
          return zone;
        }
      }
    }
    return null;
  }
}
