// Performs Fillet (smooth circular arcs) and Chamfer (linear bevels) geometric modifications over shared vertex junctions.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../cad_parameter_engine/cad_models.dart';

extension on Offset {
  Offset normalized() => distance > 0 ? this / distance : Offset.zero;
}

class CADCornerModifier {
  static List<CADLineSegment> applyChamfer({required CADLineSegment segA, required CADLineSegment segB, required double offsetMm}) {
    final double offset = offsetMm; // Fixed: 1 unit = 1.0 mm (do not divide by 100!)
    final res = _vertex(segA, segB);
    if (res == null) return [];
    final Offset v = res['v']!;
    Offset dA = ((res['sA']! ? segA.end : segA.start) - v).normalized();
    Offset dB = ((res['sB']! ? segB.end : segB.start) - v).normalized();
    Offset sA = v + (dA * offset);
    Offset sB = v + (dB * offset);
    if (res['sA']!) {
      segA.start = sA;
    } else {
      segA.end = sA;
    }
    if (res['sB']!) {
      segB.start = sB;
    } else {
      segB.end = sB;
    }
    return [CADLineSegment(id: "CHAMF_${DateTime.now().millisecondsSinceEpoch}", start: sA, end: sB)];
  }

  static List<CADLineSegment> applyFillet({required CADLineSegment segA, required CADLineSegment segB, required double radiusMm, int resCount = 8}) {
    final double rad = radiusMm; // Fixed: 1 unit = 1.0 mm
    final res = _vertex(segA, segB);
    if (res == null) return [];
    final Offset v = res['v']!;
    Offset dA = ((res['sA']! ? segA.end : segA.start) - v).normalized();
    Offset dB = ((res['sB']! ? segB.end : segB.start) - v).normalized();
    double theta = math.acos((dA.dx * dB.dx + dA.dy * dB.dy).clamp(-1.0, 1.0));
    double setback = rad / math.tan(theta / 2.0);
    Offset sA = v + (dA * setback);
    Offset sB = v + (dB * setback);
    if (res['sA']!) {
      segA.start = sA;
    } else {
      segA.end = sA;
    }
    if (res['sB']!) {
      segB.start = sB;
    } else {
      segB.end = sB;
    }
    Offset c = sA + (Offset(-dA.dy, dA.dx) * rad);
    List<CADLineSegment> arcs = [];
    double sAng = math.atan2(sA.dy - c.dy, sA.dx - c.dx);
    double eAng = math.atan2(sB.dy - c.dy, sB.dx - c.dx);
    double dAng = eAng - sAng;
    if (dAng.abs() > math.pi) dAng = dAng > 0 ? dAng - 2 * math.pi : dAng + 2 * math.pi;
    Offset prev = sA;
    for (int i = 1; i <= resCount; i++) {
      double curAng = sAng + (dAng * (i / resCount));
      Offset curr = Offset(c.dx + rad * math.cos(curAng), c.dy + rad * math.sin(curAng));
      arcs.add(CADLineSegment(id: "FIL_${DateTime.now().millisecondsSinceEpoch}_$i", start: prev, end: curr));
      prev = curr;
    }
    return arcs;
  }

  static Map<String, dynamic>? _vertex(CADLineSegment a, CADLineSegment b) {
    const double tol = 0.25; // 0.25 mm tolerance
    if ((a.start - b.start).distance < tol) return {'v': a.start, 'sA': true, 'sB': true};
    if ((a.start - b.end).distance < tol) return {'v': a.start, 'sA': true, 'sB': false};
    if ((a.end - b.start).distance < tol) return {'v': a.end, 'sA': false, 'sB': true};
    if ((a.end - b.end).distance < tol) return {'v': a.end, 'sA': false, 'sB': false};
    return null;
  }
}
