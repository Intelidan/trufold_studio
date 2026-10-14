// Handles angular rotation transforms, symmetric length scaling, and enforces coincident vertex locking dependencies across the vector network.

import 'package:flutter/material.dart';

import '../cad_parameter_engine/cad_models.dart';
import 'cad_intersection_solver.dart';

class CADConstraintSolver {
  static void resolveCoincidentConstraints({required CADLineSegment sourceSegment, required bool modStart, required List<CADLineSegment> pool}) {
    final Offset target = modStart ? sourceSegment.start : sourceSegment.end;
    for (var s in pool) {
      if (s.id == sourceSegment.id || s.isDeleted) continue;
      if ((s.start - target).distance < 0.005) s.start = target;
      if ((s.end - target).distance < 0.005) s.end = target;
    }
  }
}

class CADDimensionScaler {
  static void applyLengthTransformation({required CADLineSegment segment, required double lengthMm}) {
    double targetLen = lengthMm / 100.0;
    Offset delta = segment.end - segment.start;
    double currLen = delta.distance;
    if (currLen < 0.0001) return;
    Offset mid = Offset((segment.start.dx + segment.end.dx) / 2, (segment.start.dy + segment.end.dy) / 2);
    Offset dir = Offset(delta.dx / currLen, delta.dy / currLen);
    segment.start = mid - (dir * (targetLen / 2.0));
    segment.end = mid + (dir * (targetLen / 2.0));
  }
}

class CADPerpendicularSolver {
  static void resolvePerpendicular({required CADLineSegment anchorSegment, required CADLineSegment targetSegment}) {
    final Offset? intersect = CADIntersectionSolver.findIntersection(anchorSegment, targetSegment);
    if (intersect == null) return;
    Offset aDelta = anchorSegment.end - anchorSegment.start;
    double aLen = aDelta.distance;
    if (aLen < 0.001) return;
    Offset aHeading = Offset(aDelta.dx / aLen, aDelta.dy / aLen);
    Offset perpHeading = Offset(-aHeading.dy, aHeading.dx);
    bool startIsPivot = (targetSegment.start - intersect).distance < (targetSegment.end - intersect).distance;
    double tLen = ((startIsPivot ? targetSegment.end : targetSegment.start) - intersect).distance;
    Offset newTip = intersect + (perpHeading * tLen);
    if (startIsPivot) {
      targetSegment.start = intersect;
      targetSegment.end = newTip;
    } else {
      targetSegment.end = intersect;
      targetSegment.start = newTip;
    }
  }
}
