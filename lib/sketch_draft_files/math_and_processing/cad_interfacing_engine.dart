//Performs trajectory analysis over workspace boundaries to establish live inference and snap metrics.

import 'package:flutter/material.dart';

import '../cad_parameter_engine/cad_models.dart';

class CADInferenceMatch {
  final double value;
  final bool isHorizontal;
  final Offset refVertex;
  CADInferenceMatch({required this.value, required this.isHorizontal, required this.refVertex});
}

class CADInferencingEngine {
  static List<CADInferenceMatch> evaluateInferenceGuides({required Offset cursor, required List<CADLineSegment> segments}) {
    List<CADInferenceMatch> matches = [];
    final Set<Offset> uniqueV = {};
    for (var s in segments) {
      if (!s.isDeleted) {
        uniqueV.add(s.start);
        uniqueV.add(s.end);
      }
    }
    for (var v in uniqueV) {
      if ((cursor.dy - v.dy).abs() < 0.04) matches.add(CADInferenceMatch(value: v.dy, isHorizontal: true, refVertex: v));
      if ((cursor.dx - v.dx).abs() < 0.04) matches.add(CADInferenceMatch(value: v.dx, isHorizontal: false, refVertex: v));
    }
    return matches;
  }
}
