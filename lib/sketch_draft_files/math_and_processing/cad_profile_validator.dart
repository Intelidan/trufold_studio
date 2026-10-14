// Performs topological analysis over wire networks to confirm a closed loop exists prior to execution.

import 'package:flutter/material.dart';

import '../cad_parameter_engine/cad_models.dart';

class ValidationResult {
  final bool isValidClosedLoop;
  final String reportFeedback;
  final List<Offset> orderedPathVertices;
  ValidationResult({required this.isValidClosedLoop, required this.reportFeedback, this.orderedPathVertices = const []});
}

class CADProfileValidator {
  static const double vertexTolerance = 0.005;

  static ValidationResult validateProfile(List<CADLineSegment> segments) {
    final activeSegments = segments.where((s) => !s.isDeleted && !s.isConstruction).toList();
    if (activeSegments.isEmpty) return ValidationResult(isValidClosedLoop: false, reportFeedback: "Empty sketch profile.");

    final List<Offset> path = [];
    final List<CADLineSegment> unvisited = List.from(activeSegments);
    final first = unvisited.removeAt(0);
    path.add(first.start);
    Offset currentTip = first.end;
    bool moving = true;

    while (moving && unvisited.isNotEmpty) {
      moving = false;
      for (int i = 0; i < unvisited.length; i++) {
        final cand = unvisited[i];
        if ((cand.start - currentTip).distance < vertexTolerance) {
          path.add(currentTip);
          currentTip = cand.end;
          unvisited.removeAt(i);
          moving = true;
          break;
        } else if ((cand.end - currentTip).distance < vertexTolerance) {
          path.add(currentTip);
          currentTip = cand.start;
          unvisited.removeAt(i);
          moving = true;
          break;
        }
      }
    }
    bool isClosed = (currentTip - path.first).distance < vertexTolerance;
    if (!isClosed) return ValidationResult(isValidClosedLoop: false, reportFeedback: "OPEN LOOP ERROR: Loop is not watertight.");
    if (unvisited.isNotEmpty) return ValidationResult(isValidClosedLoop: false, reportFeedback: "DANGLING GEOMETRY DETECTED.");

    path.add(path.first);
    return ValidationResult(isValidClosedLoop: true, reportFeedback: "PROFILE VALID.", orderedPathVertices: path);
  }
}
