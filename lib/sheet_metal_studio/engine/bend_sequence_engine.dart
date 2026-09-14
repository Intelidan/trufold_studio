// =============================================================================
// bend_sequence_engine.dart
//
// Bend Sequence Validation & Collision Detection Engine for Sheet Metal Studio.
// Simulates progressive press-brake bending step-by-step.
// Detects physical interference between pre-folded flanges and the descending
// upper punch tool (Straight vs Gooseneck profiles).
// Suggests collision-free bend re-ordering and tooling adjustments.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/fold_bend_line.dart';
import '../models/planar_sheet_face.dart';
import '../models/press_brake_machine.dart';
import '../models/dsf_document.dart';

class BendSequenceStep {
  final int stepIndex; // 1-based index (1 .. N)
  final String bendId;
  final bool hasCollision;
  final String? collidingBendId;
  final String? reason;
  final PunchToolType recommendedTool;
  final double flangeHeightMm;

  const BendSequenceStep({
    required this.stepIndex,
    required this.bendId,
    required this.hasCollision,
    this.collidingBendId,
    this.reason,
    this.recommendedTool = PunchToolType.straight,
    this.flangeHeightMm = 0.0,
  });
}

class BendSequenceReport {
  final List<BendSequenceStep> steps;
  final bool isCollisionFree;
  final List<String> recommendedSequence;

  const BendSequenceReport({
    required this.steps,
    required this.isCollisionFree,
    required this.recommendedSequence,
  });

  BendSequenceStep? stepForBend(String bendId) {
    for (final s in steps) {
      if (s.bendId == bendId) return s;
    }
    return null;
  }
}

class BendSequenceEngine {
  /// Analyzes a proposed bend sequence order against punch tooling
  static BendSequenceReport validateSequence({
    required DsfDocument doc,
    required PressBrakeMachine machine,
    List<String>? sequenceOrder, // Optional custom bend IDs order
    bool computeOptimal = true,
  }) {
    if (doc.bends.isEmpty) {
      return const BendSequenceReport(
        steps: [],
        isCollisionFree: true,
        recommendedSequence: [],
      );
    }

    // Default sequence is document bend order
    final orderedBendIds = sequenceOrder ?? doc.bends.map((b) => b.id).toList();
    final bendMap = {for (final b in doc.bends) b.id: b};

    final steps = <BendSequenceStep>[];
    final foldedBends = <FoldBendLine>[];

    for (int i = 0; i < orderedBendIds.length; i++) {
      final bendId = orderedBendIds[i];
      final currentBend = bendMap[bendId];
      if (currentBend == null) continue;

      // Check if any previously folded bend interferes with the punch entering currentBend
      BendSequenceStep step = _checkStepInterference(
        stepIndex: i + 1,
        currentBend: currentBend,
        previouslyFolded: foldedBends,
        doc: doc,
        machine: machine,
      );

      steps.add(step);
      foldedBends.add(currentBend);
    }

    final hasAnyCollision = steps.any((s) => s.hasCollision);
    final optimalSequence = computeOptimal
        ? autoSequence(doc: doc, machine: machine)
        : orderedBendIds;

    return BendSequenceReport(
      steps: steps,
      isCollisionFree: !hasAnyCollision,
      recommendedSequence: optimalSequence,
    );
  }

  /// Automatically computes a collision-free or collision-minimized sequence
  static List<String> autoSequence({
    required DsfDocument doc,
    required PressBrakeMachine machine,
  }) {
    if (doc.bends.length <= 1) {
      return doc.bends.map((b) => b.id).toList();
    }

    // Heuristic 1: Flanges with return lips or smaller outer flanges bent first
    // or inner walls bent first so punch access isn't blocked.
    // For small number of bends (<= 6), test permutations or sort by flange depth:
    final bends = List<FoldBendLine>.from(doc.bends);

    // Measure flange depths
    final flangeDepths = <String, double>{};
    for (final b in bends) {
      flangeDepths[b.id] = _computeFlangeDepth(b, doc);
    }

    // Candidate 1: Outer return flanges first (ascending depth from edge inwards)
    final candidate1 = List<FoldBendLine>.from(bends)
      ..sort((a, b) => flangeDepths[a.id]!.compareTo(flangeDepths[b.id]!));

    // Candidate 2: Inside out (descending)
    final candidate2 = List<FoldBendLine>.from(bends)
      ..sort((a, b) => flangeDepths[b.id]!.compareTo(flangeDepths[a.id]!));

    // Evaluate Candidate 1
    final report1 = _evaluateCandidate(candidate1.map((b) => b.id).toList(), doc, machine);
    if (report1.isCollisionFree) {
      return candidate1.map((b) => b.id).toList();
    }

    // Evaluate Candidate 2
    final report2 = _evaluateCandidate(candidate2.map((b) => b.id).toList(), doc, machine);
    if (report2.isCollisionFree) {
      return candidate2.map((b) => b.id).toList();
    }

    // Return the candidate with fewer collisions
    final col1 = report1.steps.where((s) => s.hasCollision).length;
    final col2 = report2.steps.where((s) => s.hasCollision).length;
    return col1 <= col2
        ? candidate1.map((b) => b.id).toList()
        : candidate2.map((b) => b.id).toList();
  }

  static BendSequenceReport _evaluateCandidate(
    List<String> order,
    DsfDocument doc,
    PressBrakeMachine machine,
  ) {
    return validateSequence(
      doc: doc,
      machine: machine,
      sequenceOrder: order,
      computeOptimal: false,
    );
  }

  static BendSequenceStep _checkStepInterference({
    required int stepIndex,
    required FoldBendLine currentBend,
    required List<FoldBendLine> previouslyFolded,
    required DsfDocument doc,
    required PressBrakeMachine machine,
  }) {
    final currentFlangeDepth = _computeFlangeDepth(currentBend, doc);

    // Check collision against previously folded flanges
    for (final prev in previouslyFolded) {
      final prevFlangeDepth = _computeFlangeDepth(prev, doc);

      // If previous bend is parallel or adjacent to current bend:
      final isParallel = _areParallel(currentBend, prev);
      if (isParallel) {
        final distBetweenBends = _distBetweenParallelSegments(currentBend, prev);

        // Scenario: A channel or tray where returning flange was folded first:
        // When folding the deep wall, if previous fold returns back over the die:
        // Straight punch clearance is typically 20mm horizontal.
        // Gooseneck punch has 55mm relief.
        final punchReliefMm = (machine.punchType == PunchToolType.gooseneck) ? 55.0 : 20.0;

        if (distBetweenBends > 0.1 && distBetweenBends < prevFlangeDepth) {
          final overhang = prevFlangeDepth - distBetweenBends;
          if (overhang > punchReliefMm) {
            return BendSequenceStep(
              stepIndex: stepIndex,
              bendId: currentBend.id,
              hasCollision: true,
              collidingBendId: prev.id,
              reason: 'Flange from ${prev.id} overhangs by ${overhang.toStringAsFixed(1)}mm, colliding with ${machine.punchType.name} punch shank (relief: ${punchReliefMm.toStringAsFixed(0)}mm).',
              recommendedTool: PunchToolType.gooseneck,
              flangeHeightMm: currentFlangeDepth,
            );
          } else if (machine.punchType == PunchToolType.straight && overhang > 15.0) {
            return BendSequenceStep(
              stepIndex: stepIndex,
              bendId: currentBend.id,
              hasCollision: true,
              collidingBendId: prev.id,
              reason: 'Flange from ${prev.id} interferes with straight punch body. Re-orient sequence or switch to Gooseneck tooling.',
              recommendedTool: PunchToolType.gooseneck,
              flangeHeightMm: currentFlangeDepth,
            );
          }
        }
      }
    }

    return BendSequenceStep(
      stepIndex: stepIndex,
      bendId: currentBend.id,
      hasCollision: false,
      flangeHeightMm: currentFlangeDepth,
    );
  }

  static double _computeFlangeDepth(FoldBendLine bend, DsfDocument doc) {
    PlanarSheetFace? childFace;
    for (final f in doc.faces) {
      if (f.id == bend.childFaceId) {
        childFace = f;
        break;
      }
    }
    if (childFace == null || childFace.vertices.isEmpty) return 20.0;

    double maxDist = 0.0;
    for (final v in childFace.vertices) {
      final d = _distToInfiniteLine(v, bend.p1, bend.p2);
      if (d > maxDist) maxDist = d;
    }
    return maxDist > 0.0 ? maxDist : 20.0;
  }

  static bool _areParallel(FoldBendLine b1, FoldBendLine b2) {
    final d1 = b1.unitDirection;
    final d2 = b2.unitDirection;
    final dot = (d1.x * d2.x + d1.y * d2.y).abs();
    return dot > 0.96; // Within ~15 degrees of parallel
  }

  static double _distBetweenParallelSegments(FoldBendLine b1, FoldBendLine b2) {
    return _distToInfiniteLine(b1.midpoint, b2.p1, b2.p2);
  }

  static double _distToInfiniteLine(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 < 1e-9) return p.distanceTo(a);
    final cross = ((p.x - a.x) * dy - (p.y - a.y) * dx).abs();
    return cross / math.sqrt(l2);
  }
}
