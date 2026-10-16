// Performs topological analysis over wire networks to confirm a closed loop exists prior to execution.

import 'package:flutter/material.dart';

import '../cad_parameter_engine/cad_models.dart';

class ValidationResult {
  final bool isValidClosedLoop;
  final String reportFeedback;
  final List<Offset> orderedPathVertices;
  final List<List<Offset>> allClosedLoops;

  ValidationResult({
    required this.isValidClosedLoop,
    required this.reportFeedback,
    this.orderedPathVertices = const [],
    this.allClosedLoops = const [],
  });
}

class CADProfileValidator {
  static const double vertexTolerance = 0.25; // 0.25 mm tolerance (fixed from 0.005m!)

  static ValidationResult validateProfile(List<CADLineSegment> segments) {
    // Ignore deleted, construction, and projected reference segments when extracting closed profiles
    final activeSegments = segments
        .where((s) => !s.isDeleted && !s.isConstruction && !s.isProjected)
        .toList();
    if (activeSegments.isEmpty) {
      return ValidationResult(isValidClosedLoop: false, reportFeedback: "Empty sketch profile.");
    }

    final List<CADLineSegment> unvisited = List.from(activeSegments);
    final List<List<Offset>> closedLoops = [];

    while (unvisited.isNotEmpty) {
      final first = unvisited.removeAt(0);
      final List<Offset> path = [first.start];
      Offset currentTip = first.end;
      bool moving = true;

      while (moving && unvisited.isNotEmpty) {
        moving = false;
        for (int i = 0; i < unvisited.length; i++) {
          final cand = unvisited[i];
          if ((cand.start - currentTip).distance <= vertexTolerance) {
            path.add(currentTip);
            currentTip = cand.end;
            unvisited.removeAt(i);
            moving = true;
            break;
          } else if ((cand.end - currentTip).distance <= vertexTolerance) {
            path.add(currentTip);
            currentTip = cand.start;
            unvisited.removeAt(i);
            moving = true;
            break;
          }
        }
        if ((currentTip - path.first).distance <= vertexTolerance && path.length >= 3) {
          break;
        }
      }

      if ((currentTip - path.first).distance <= vertexTolerance && path.length >= 3) {
        path.add(path.first);
        closedLoops.add(path);
      }
    }

    if (closedLoops.isEmpty) {
      return ValidationResult(
        isValidClosedLoop: false,
        reportFeedback: "OPEN LOOP ERROR: Loop is not watertight.",
      );
    }

    return ValidationResult(
      isValidClosedLoop: true,
      reportFeedback: "${closedLoops.length} Closed Profile(s) Ready",
      orderedPathVertices: closedLoops.last, // Most recently drawn or selected closed profile
      allClosedLoops: closedLoops,
    );
  }
}
