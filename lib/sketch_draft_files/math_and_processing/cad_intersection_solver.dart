//
// cad_intersection_solver.dart

// Applies Cramer's Rule to resolve segment intersections and dynamically breaks lines into unique topological edges.

import 'package:flutter/material.dart';

import '../cad_parameter_engine/cad_models.dart';

class CADIntersectionSolver {
  static Offset? findIntersection(CADLineSegment s1, CADLineSegment s2) {
    final double p0x = s1.start.dx;
    final double p0y = s1.start.dy;
    final double p1x = s1.end.dx;
    final double p1y = s1.end.dy;
    final double p2x = s2.start.dx;
    final double p2y = s2.start.dy;
    final double p3x = s2.end.dx;
    final double p3y = s2.end.dy;

    final double s1x = p1x - p0x;
    final double s1y = p1y - p0y;
    final double s2x = p3x - p2x;
    final double s2y = p3y - p2y;
    final double denominator = (-s2x * s1y + s1x * s2y);
    if (denominator.abs() < 0.00001) return null;

    double s = (-s1y * (p0x - p2x) + s1x * (p0y - p2y)) / denominator;
    double t = (s2x * (p0y - p2y) - s2y * (p0x - p2x)) / denominator;

    return (s >= 0.0 && s <= 1.0 && t >= 0.0 && t <= 1.0) ? Offset(p0x + (t * s1x), p0y + (t * s1y)) : null;
  }

  static List<CADLineSegment> computeSplits(List<CADLineSegment> activeSegments) {
    List<CADLineSegment> outputPool = List.from(activeSegments.where((s) => !s.isDeleted));
    bool splitsOccurred = true;

    while (splitsOccurred) {
      splitsOccurred = false;
      Offset? intersectPoint;
      int? idxA;
      int? idxB;
      for (int i = 0; i < outputPool.length; i++) {
        for (int j = i + 1; j < outputPool.length; j++) {
          final intersect = findIntersection(outputPool[i], outputPool[j]);
          if (intersect != null && !_isEndpoint(intersect, outputPool[i]) && !_isEndpoint(intersect, outputPool[j])) {
            intersectPoint = intersect;
            idxA = i;
            idxB = j;
            splitsOccurred = true;
            break;
          }
        }
        if (splitsOccurred) break;
      }
      if (splitsOccurred && intersectPoint != null) {
        final segA = outputPool[idxA!];
        final segB = outputPool[idxB!];
        outputPool.removeAt(idxB);
        outputPool.removeAt(idxA);
        outputPool.addAll([
          CADLineSegment(id: "${segA.id}_a", start: segA.start, end: intersectPoint, isConstruction: segA.isConstruction),
          CADLineSegment(id: "${segA.id}_b", start: intersectPoint, end: segA.end, isConstruction: segA.isConstruction),
          CADLineSegment(id: "${segB.id}_a", start: segB.start, end: intersectPoint, isConstruction: segB.isConstruction),
          CADLineSegment(id: "${segB.id}_b", start: intersectPoint, end: segB.end, isConstruction: segB.isConstruction),
        ]);
      }
    }
    return outputPool;
  }

  static bool _isEndpoint(Offset pt, CADLineSegment s) => (pt - s.start).distance < 0.001 || (pt - s.end).distance < 0.001;
}
