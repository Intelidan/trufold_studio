import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:trufold_studio/sketch_draft_files/cad_parameter_engine/cad_models.dart';
import 'package:trufold_studio/sketch_draft_files/math_and_processing/cad_intersection_solver.dart';

class OnshapeSketchModifyEngine {
  /// Converts any composite primitive (Rectangle, Polygon, Slot) on [plane] into individual
  /// CADLineEntity / CADArcEntity primitives so Trim, Extend, Split, and Offset operate cleanly per segment.
  static void decomposeCompositePrimitives(CADSketchPlane plane) {
    final toReplace = <CADPrimitiveEntity>[];
    final replacementLines = <CADLineEntity>[];

    for (final prim in plane.primitives) {
      if (prim is CADRectangleEntity ||
          prim is CADCenterRectangleEntity ||
          prim is CADAlignedRectangleEntity ||
          prim is CADRegularPolygonEntity) {
        toReplace.add(prim);
        for (final seg in prim.toLineSegments()) {
          replacementLines.add(CADLineEntity(
            id: seg.id,
            start: seg.start,
            end: seg.end,
            isConstruction: seg.isConstruction,
          ));
        }
      }
    }
    for (final r in toReplace) {
      plane.primitives.remove(r);
    }
    plane.primitives.addAll(replacementLines);
  }

  /// 1. TRIM TOOL ('M' Key — onshape.pdf p. 20):
  /// Splits the clicked line at all intersections with other sketch entities and deletes ONLY the clicked sub-span!
  static bool trimAtPoint(CADSketchPlane plane, Offset clickLocal, {double hitTolerance = 6.0}) {
    decomposeCompositePrimitives(plane);

    CADLineEntity? targetLine;
    double bestDist = hitTolerance;
    for (final p in plane.primitives.whereType<CADLineEntity>()) {
      final d = _distancePointToSegment(clickLocal, p.start, p.end);
      if (d < bestDist) {
        bestDist = d;
        targetLine = p;
      }
    }
    if (targetLine == null) return false;

    // Collect all intersection parameters t in (0, 1) along targetLine against all other segments
    final allSegments = <CADLineSegment>[];
    for (final p in plane.primitives) {
      if (p.id == targetLine.id) continue;
      allSegments.addAll(p.toLineSegments());
    }

    final targetSeg = CADLineSegment(id: targetLine.id, start: targetLine.start, end: targetLine.end);
    final lineVec = targetLine.end - targetLine.start;
    final lineLen = lineVec.distance;
    if (lineLen < 1e-4) {
      plane.primitives.remove(targetLine);
      return true;
    }

    final splitParams = <double>[0.0, 1.0];
    for (final other in allSegments) {
      final pt = CADIntersectionSolver.findIntersection(targetSeg, other);
      if (pt != null) {
        final t = ((pt - targetLine.start).distance / lineLen).clamp(0.0, 1.0);
        if (splitParams.every((existing) => (existing - t).abs() > 1e-3)) {
          splitParams.add(t);
        }
      }
    }
    splitParams.sort();

    // If no interior intersections exist, delete the entire line
    if (splitParams.length <= 2) {
      plane.primitives.remove(targetLine);
      return true;
    }

    // Find which sub-span [t_i, t_{i+1}] contains clickLocal and keep all OTHER sub-spans
    final clickT = (((clickLocal.dx - targetLine.start.dx) * lineVec.dx +
                (clickLocal.dy - targetLine.start.dy) * lineVec.dy) /
            (lineLen * lineLen))
        .clamp(0.0, 1.0);

    plane.primitives.remove(targetLine);
    for (int i = 0; i < splitParams.length - 1; i++) {
      final t0 = splitParams[i];
      final t1 = splitParams[i + 1];
      if (clickT >= t0 - 1e-4 && clickT <= t1 + 1e-4) {
        // This is the trimmed sub-segment — omit it!
        continue;
      }
      final p0 = Offset.lerp(targetLine.start, targetLine.end, t0)!;
      final p1 = Offset.lerp(targetLine.start, targetLine.end, t1)!;
      if ((p1 - p0).distance > 0.2) {
        plane.primitives.add(CADLineEntity(
          id: '${targetLine.id}_trim_$i',
          start: p0,
          end: p1,
          isConstruction: targetLine.isConstruction,
        ));
      }
    }
    return true;
  }

  /// 2. EXTEND TOOL (08_sketch_modify/04_extend.svg):
  /// Extends the clicked endpoint of a line outward until it hits the nearest boundary segment on [plane].
  static bool extendAtPoint(CADSketchPlane plane, Offset clickLocal, {double hitTolerance = 8.0}) {
    decomposeCompositePrimitives(plane);

    CADLineEntity? targetLine;
    double bestDist = hitTolerance;
    for (final p in plane.primitives.whereType<CADLineEntity>()) {
      final d = _distancePointToSegment(clickLocal, p.start, p.end);
      if (d < bestDist) {
        bestDist = d;
        targetLine = p;
      }
    }
    if (targetLine == null) return false;

    final extendEnd = (clickLocal - targetLine.end).distance <= (clickLocal - targetLine.start).distance;
    final fixedPt = extendEnd ? targetLine.start : targetLine.end;
    final movingPt = extendEnd ? targetLine.end : targetLine.start;
    final dir = movingPt - fixedPt;
    final len = dir.distance;
    if (len < 1e-4) return false;
    final unit = dir / len;

    // Cast a long ray segment from movingPt along +unit and find the closest intersection
    final raySeg = CADLineSegment(
      id: 'extend_ray',
      start: movingPt + unit * 0.05,
      end: movingPt + unit * 2000.0,
    );

    Offset? closestHit;
    double closestDist = double.infinity;

    for (final p in plane.primitives) {
      if (p.id == targetLine.id) continue;
      for (final seg in p.toLineSegments()) {
        final hit = CADIntersectionSolver.findIntersection(raySeg, seg);
        if (hit != null) {
          final d = (hit - movingPt).distance;
          if (d > 0.1 && d < closestDist) {
            closestDist = d;
            closestHit = hit;
          }
        }
      }
    }

    if (closestHit == null) return false;
    if (extendEnd) {
      targetLine.end = closestHit;
    } else {
      targetLine.start = closestHit;
    }
    return true;
  }

  /// 3. SPLIT TOOL (08_sketch_modify/05_split.svg):
  /// Splits a line at [clickLocal] into two independent collinear lines meeting at a shared vertex.
  static bool splitAtPoint(CADSketchPlane plane, Offset clickLocal, {double hitTolerance = 6.0}) {
    decomposeCompositePrimitives(plane);

    for (final p in plane.primitives.whereType<CADLineEntity>().toList()) {
      final proj = _projectPointOnSegment(clickLocal, p.start, p.end);
      if ((proj - clickLocal).distance <= hitTolerance &&
          (proj - p.start).distance > 1.0 &&
          (proj - p.end).distance > 1.0) {
        plane.primitives.remove(p);
        plane.primitives.add(CADLineEntity(id: '${p.id}_s1', start: p.start, end: proj, isConstruction: p.isConstruction));
        plane.primitives.add(CADLineEntity(id: '${p.id}_s2', start: proj, end: p.end, isConstruction: p.isConstruction));
        return true;
      }
    }
    return false;
  }

  /// 4. OFFSET TOOL ('O' Key — 08_sketch_modify/06_offset.svg):
  /// Creates a parallel offset copy of [entity] at signed distance [offsetMm].
  static CADPrimitiveEntity? offsetEntity(CADSketchPlane plane, CADPrimitiveEntity entity, double offsetMm) {
    final String nextId = '${entity.id}_offset_${DateTime.now().millisecondsSinceEpoch}';
    CADPrimitiveEntity? created;

    if (entity is CADCircleEntity) {
      final newR = (entity.radius + offsetMm).clamp(0.5, 10000.0);
      created = CADCircleEntity(id: nextId, center: entity.center, radius: newR, isConstruction: entity.isConstruction);
    } else if (entity is CADLineEntity) {
      final d = entity.end - entity.start;
      final len = d.distance;
      if (len > 1e-4) {
        final n = Offset(-d.dy / len, d.dx / len) * offsetMm;
        created = CADLineEntity(id: nextId, start: entity.start + n, end: entity.end + n, isConstruction: entity.isConstruction);
      }
    } else if (entity is CADRectangleEntity) {
      created = CADRectangleEntity(
        id: nextId,
        startPoint: entity.startPoint - Offset(offsetMm, offsetMm),
        width: (entity.width + 2.0 * offsetMm).clamp(1.0, 10000.0),
        height: (entity.height + 2.0 * offsetMm).clamp(1.0, 10000.0),
        isConstruction: entity.isConstruction,
      );
    } else if (entity is CADCenterRectangleEntity) {
      created = CADCenterRectangleEntity(
        id: nextId,
        center: entity.center,
        width: (entity.width + 2.0 * offsetMm).clamp(1.0, 10000.0),
        height: (entity.height + 2.0 * offsetMm).clamp(1.0, 10000.0),
        isConstruction: entity.isConstruction,
      );
    }

    if (created != null) {
      plane.primitives.add(created);
    }
    return created;
  }

  /// 5. SKETCH MIRROR TOOL (09_pattern_and_insert/01_mirror.svg — onshape.pdf p. 41):
  /// Mirrors [entitiesToMirror] across [mirrorAxisLine] and attaches Symmetric constraints!
  static List<CADPrimitiveEntity> mirrorEntitiesAcrossLine({
    required CADSketchPlane plane,
    required CADLineEntity mirrorAxisLine,
    required List<CADPrimitiveEntity> entitiesToMirror,
  }) {
    final created = <CADPrimitiveEntity>[];
    final a = mirrorAxisLine.start;
    final b = mirrorAxisLine.end;
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return created;

    Offset reflectPt(Offset p) {
      final ap = p - a;
      final t = (ap.dx * ab.dx + ap.dy * ab.dy) / lenSq;
      final foot = a + ab * t;
      return foot * 2.0 - p;
    }

    int idx = 1;
    for (final src in entitiesToMirror) {
      if (src.id == mirrorAxisLine.id) continue;
      final newId = '${src.id}_mir_${DateTime.now().millisecondsSinceEpoch}_${idx++}';
      CADPrimitiveEntity? mirrored;

      if (src is CADCircleEntity) {
        mirrored = CADCircleEntity(id: newId, center: reflectPt(src.center), radius: src.radius, isConstruction: src.isConstruction);
      } else if (src is CADLineEntity) {
        mirrored = CADLineEntity(id: newId, start: reflectPt(src.start), end: reflectPt(src.end), isConstruction: src.isConstruction);
      } else if (src is CADCenterRectangleEntity) {
        mirrored = CADCenterRectangleEntity(id: newId, center: reflectPt(src.center), width: src.width, height: src.height, isConstruction: src.isConstruction);
      } else if (src is CADPointEntity) {
        mirrored = CADPointEntity(id: newId, position: reflectPt(src.position));
      }

      if (mirrored != null) {
        plane.primitives.add(mirrored);
        created.add(mirrored);
        plane.constraints.add(CadConstraint(
          id: 'sym_$newId',
          type: CadConstraintType.symmetric,
          entityIds: [src.id, mirrored.id, mirrorAxisLine.id],
        ));
      }
    }
    return created;
  }

  /// 6. 2D SKETCH LINEAR PATTERN (09_pattern_and_insert/02_linear_pattern.svg):
  static List<CADPrimitiveEntity> createSketchLinearPattern({
    required CADSketchPlane plane,
    required List<CADPrimitiveEntity> sourceEntities,
    required int countX,
    required int countY,
    required double spacingXMm,
    required double spacingYMm,
  }) {
    final created = <CADPrimitiveEntity>[];
    for (int ix = 0; ix < countX; ix++) {
      for (int iy = 0; iy < countY; iy++) {
        if (ix == 0 && iy == 0) continue;
        final delta = Offset(ix * spacingXMm, iy * spacingYMm);
        for (final src in sourceEntities) {
          final clone = _cloneTranslated(src, delta, '${src.id}_lpat_${ix}_$iy');
          if (clone != null) {
            plane.primitives.add(clone);
            created.add(clone);
          }
        }
      }
    }
    return created;
  }

  /// 7. 2D SKETCH CIRCULAR PATTERN (09_pattern_and_insert/03_circular_pattern.svg):
  static List<CADPrimitiveEntity> createSketchCircularPattern({
    required CADSketchPlane plane,
    required List<CADPrimitiveEntity> sourceEntities,
    required Offset center,
    required int instanceCount,
    double totalAngleDeg = 360.0,
  }) {
    final created = <CADPrimitiveEntity>[];
    if (instanceCount < 2) return created;
    final stepRad = (totalAngleDeg * math.pi / 180.0) / instanceCount;

    Offset rotatePt(Offset p, double rad) {
      final d = p - center;
      final c = math.cos(rad);
      final s = math.sin(rad);
      return Offset(center.dx + d.dx * c - d.dy * s, center.dy + d.dx * s + d.dy * c);
    }

    for (int k = 1; k < instanceCount; k++) {
      final ang = stepRad * k;
      for (final src in sourceEntities) {
        final newId = '${src.id}_cpat_$k';
        if (src is CADCircleEntity) {
          final c = CADCircleEntity(id: newId, center: rotatePt(src.center, ang), radius: src.radius, isConstruction: src.isConstruction);
          plane.primitives.add(c);
          created.add(c);
        } else if (src is CADLineEntity) {
          final l = CADLineEntity(id: newId, start: rotatePt(src.start, ang), end: rotatePt(src.end, ang), isConstruction: src.isConstruction);
          plane.primitives.add(l);
          created.add(l);
        }
      }
    }
    return created;
  }

  static CADPrimitiveEntity? _cloneTranslated(CADPrimitiveEntity src, Offset delta, String newId) {
    if (src is CADCircleEntity) {
      return CADCircleEntity(id: newId, center: src.center + delta, radius: src.radius, isConstruction: src.isConstruction);
    } else if (src is CADLineEntity) {
      return CADLineEntity(id: newId, start: src.start + delta, end: src.end + delta, isConstruction: src.isConstruction);
    } else if (src is CADRectangleEntity) {
      return CADRectangleEntity(id: newId, startPoint: src.startPoint + delta, width: src.width, height: src.height, isConstruction: src.isConstruction);
    } else if (src is CADCenterRectangleEntity) {
      return CADCenterRectangleEntity(id: newId, center: src.center + delta, width: src.width, height: src.height, isConstruction: src.isConstruction);
    }
    return null;
  }

  static Offset _projectPointOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return a;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq).clamp(0.0, 1.0);
    return a + ab * t;
  }

  static double _distancePointToSegment(Offset p, Offset a, Offset b) =>
      (p - _projectPointOnSegment(p, a, b)).distance;
}
