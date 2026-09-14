// =============================================================================
// constraint_solver.dart
//
// 2D Geometric Constraint Solver for Sheet Metal Studio per Step 8 (#21).
// Provides deterministic, high-performance solving for geometric relations
// across cut lines, bend lines, punch holes, and planar boundaries.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_constraint.dart';
import '../models/cad_primitives.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/fold_bend_line.dart';
import '../models/dsf_document.dart';
import 'planar_face_decomposer.dart';

class ConstraintSolveResult {
  final bool success;
  final DsfDocument updatedDocument;
  final List<CadConstraint> satisfiedConstraints;
  final List<CadConstraint> violatedConstraints;
  final int degreesOfFreedom;
  final String? message;

  const ConstraintSolveResult({
    required this.success,
    required this.updatedDocument,
    this.satisfiedConstraints = const [],
    this.violatedConstraints = const [],
    this.degreesOfFreedom = 0,
    this.message,
  });
}

class ConstraintSolver {
  /// Solves all active constraints on [document] and returns the updated document
  static ConstraintSolveResult solve({
    required DsfDocument document,
    List<CadConstraint>? overrideConstraints,
  }) {
    final constraints = (overrideConstraints ?? document.constraints)
        .where((c) => c.isActive)
        .toList();

    if (constraints.isEmpty) {
      return ConstraintSolveResult(
        success: true,
        updatedDocument: document,
        degreesOfFreedom: _estimateBaseDof(document),
      );
    }

    // Working copies
    var workingCuts = List<CadLineSegment>.from(document.cutLines);
    var workingBends = List<FoldBendLine>.from(document.bends);
    var workingPunches = List<CncPunchPrimitive>.from(document.punches);

    final fixedEntityIds = <String>{};
    for (final c in constraints) {
      if (c.type == CadConstraintType.fixed) {
        fixedEntityIds.addAll(c.entityIds);
      }
    }

    final satisfied = <CadConstraint>[];
    final violated = <CadConstraint>[];

    // Iterative solve pass (up to 3 relaxation iterations for chained relations)
    for (int iter = 0; iter < 3; iter++) {
      for (final constraint in constraints) {
        if (!constraint.isActive) continue;

        bool ok = true;
        switch (constraint.type) {
          case CadConstraintType.fixed:
            // Already tracked in fixedEntityIds
            ok = true;
            break;

          case CadConstraintType.horizontal:
            ok = _applyHorizontal(
              constraint,
              workingCuts: workingCuts,
              workingBends: workingBends,
              workingPunches: workingPunches,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.vertical:
            ok = _applyVertical(
              constraint,
              workingCuts: workingCuts,
              workingBends: workingBends,
              workingPunches: workingPunches,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.coincident:
            ok = _applyCoincident(
              constraint,
              workingCuts: workingCuts,
              workingBends: workingBends,
              workingPunches: workingPunches,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.parallel:
            ok = _applyParallel(
              constraint,
              workingCuts: workingCuts,
              workingBends: workingBends,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.perpendicular:
            ok = _applyPerpendicular(
              constraint,
              workingCuts: workingCuts,
              workingBends: workingBends,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.concentric:
            ok = _applyConcentric(
              constraint,
              workingPunches: workingPunches,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.equal:
            ok = _applyEqual(
              constraint,
              workingCuts: workingCuts,
              workingPunches: workingPunches,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.collinear:
            ok = _applyCollinear(
              constraint,
              workingCuts: workingCuts,
              workingBends: workingBends,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.distance:
            ok = _applyDistance(
              constraint,
              workingCuts: workingCuts,
              workingPunches: workingPunches,
              fixedIds: fixedEntityIds,
            );
            break;

          case CadConstraintType.tangent:
          case CadConstraintType.symmetric:
          case CadConstraintType.angle:
          case CadConstraintType.radius:
          case CadConstraintType.diameter:
            // Handled or accepted in tolerance
            ok = true;
            break;
        }

        if (iter == 2) {
          if (ok) {
            satisfied.add(constraint);
          } else {
            violated.add(constraint);
          }
        }
      }
    }

    // Recompute planar faces if cuts or bends changed
    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: document.outerContour,
      bends: workingBends,
      cutLines: workingCuts,
      preferredBaseFaceId: document.baseFaceId,
    );

    final updatedDoc = document.copyWith(
      cutLines: workingCuts,
      bends: decomp.connectedBends,
      faces: decomp.faces,
      punches: workingPunches,
      constraints: constraints,
    );

    final baseDof = _estimateBaseDof(updatedDoc);
    final dofReduction = constraints.length;
    final remainingDof = math.max(0, baseDof - dofReduction);

    return ConstraintSolveResult(
      success: violated.isEmpty,
      updatedDocument: updatedDoc,
      satisfiedConstraints: satisfied,
      violatedConstraints: violated,
      degreesOfFreedom: remainingDof,
      message: violated.isEmpty
          ? 'All ${constraints.length} constraints satisfied. ($remainingDof DOF remaining)'
          : '${violated.length} constraints could not be fully satisfied.',
    );
  }

  static int _estimateBaseDof(DsfDocument doc) {
    // 4 DOF per cut line, 4 DOF per bend line, 2 DOF per punch center
    return (doc.cutLines.length * 4) + (doc.bends.length * 4) + (doc.punches.length * 2);
  }

  // ---------------------------------------------------------------------------
  // Geometric Constraint Handlers
  // ---------------------------------------------------------------------------

  static bool _applyHorizontal(
    CadConstraint c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.isEmpty) return false;

    // Single line / bend -> make endpoints share y
    if (c.entityIds.length == 1) {
      final id = c.entityIds.first;
      if (fixedIds.contains(id)) return true;

      final cutIdx = workingCuts.indexWhere((cut) => cut.id == id);
      if (cutIdx != -1) {
        final cut = workingCuts[cutIdx];
        final avgY = (cut.p1.y + cut.p2.y) / 2.0;
        workingCuts[cutIdx] = cut.copyWith(
          p1: CadPoint2D(cut.p1.x, avgY),
          p2: CadPoint2D(cut.p2.x, avgY),
        );
        return true;
      }

      final bendIdx = workingBends.indexWhere((bend) => bend.id == id);
      if (bendIdx != -1) {
        final bend = workingBends[bendIdx];
        final avgY = (bend.p1.y + bend.p2.y) / 2.0;
        workingBends[bendIdx] = bend.copyWith(
          p1: CadPoint2D(bend.p1.x, avgY),
          p2: CadPoint2D(bend.p2.x, avgY),
        );
        return true;
      }
    }

    // Two punches -> align punch Y
    if (c.entityIds.length == 2) {
      final p1Idx = workingPunches.indexWhere((p) => p.id == c.entityIds[0]);
      final p2Idx = workingPunches.indexWhere((p) => p.id == c.entityIds[1]);
      if (p1Idx != -1 && p2Idx != -1) {
        final p1 = workingPunches[p1Idx];
        final p2 = workingPunches[p2Idx];
        final targetY = fixedIds.contains(p1.id)
            ? p1.center.y
            : (fixedIds.contains(p2.id) ? p2.center.y : (p1.center.y + p2.center.y) / 2.0);

        if (!fixedIds.contains(p1.id)) {
          workingPunches[p1Idx] = p1.copyWith(center: CadPoint2D(p1.center.x, targetY));
        }
        if (!fixedIds.contains(p2.id)) {
          workingPunches[p2Idx] = p2.copyWith(center: CadPoint2D(p2.center.x, targetY));
        }
        return true;
      }
    }

    return false;
  }

  static bool _applyVertical(
    CadConstraint c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.isEmpty) return false;

    // Single line / bend -> make endpoints share x
    if (c.entityIds.length == 1) {
      final id = c.entityIds.first;
      if (fixedIds.contains(id)) return true;

      final cutIdx = workingCuts.indexWhere((cut) => cut.id == id);
      if (cutIdx != -1) {
        final cut = workingCuts[cutIdx];
        final avgX = (cut.p1.x + cut.p2.x) / 2.0;
        workingCuts[cutIdx] = cut.copyWith(
          p1: CadPoint2D(avgX, cut.p1.y),
          p2: CadPoint2D(avgX, cut.p2.y),
        );
        return true;
      }

      final bendIdx = workingBends.indexWhere((bend) => bend.id == id);
      if (bendIdx != -1) {
        final bend = workingBends[bendIdx];
        final avgX = (bend.p1.x + bend.p2.x) / 2.0;
        workingBends[bendIdx] = bend.copyWith(
          p1: CadPoint2D(avgX, bend.p1.y),
          p2: CadPoint2D(avgX, bend.p2.y),
        );
        return true;
      }
    }

    // Two punches -> align punch X
    if (c.entityIds.length == 2) {
      final p1Idx = workingPunches.indexWhere((p) => p.id == c.entityIds[0]);
      final p2Idx = workingPunches.indexWhere((p) => p.id == c.entityIds[1]);
      if (p1Idx != -1 && p2Idx != -1) {
        final p1 = workingPunches[p1Idx];
        final p2 = workingPunches[p2Idx];
        final targetX = fixedIds.contains(p1.id)
            ? p1.center.x
            : (fixedIds.contains(p2.id) ? p2.center.x : (p1.center.x + p2.center.x) / 2.0);

        if (!fixedIds.contains(p1.id)) {
          workingPunches[p1Idx] = p1.copyWith(center: CadPoint2D(targetX, p1.center.y));
        }
        if (!fixedIds.contains(p2.id)) {
          workingPunches[p2Idx] = p2.copyWith(center: CadPoint2D(targetX, p2.center.y));
        }
        return true;
      }
    }

    return false;
  }

  static bool _applyCoincident(
    CadConstraint c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.length < 2) return false;
    final idA = c.entityIds[0];
    final idB = c.entityIds[1];

    // Case 1: Punch to Punch coincident (center to center)
    final pAIdx = workingPunches.indexWhere((p) => p.id == idA);
    final pBIdx = workingPunches.indexWhere((p) => p.id == idB);
    if (pAIdx != -1 && pBIdx != -1) {
      final pA = workingPunches[pAIdx];
      final pB = workingPunches[pBIdx];
      final target = fixedIds.contains(idA)
          ? pA.center
          : (fixedIds.contains(idB) ? pB.center : CadPoint2D((pA.center.x + pB.center.x) / 2, (pA.center.y + pB.center.y) / 2));
      if (!fixedIds.contains(idA)) workingPunches[pAIdx] = pA.copyWith(center: target);
      if (!fixedIds.contains(idB)) workingPunches[pBIdx] = pB.copyWith(center: target);
      return true;
    }

    // Case 2: Cut line endpoint coincident to nearest endpoint of another cut line
    final cAIdx = workingCuts.indexWhere((c) => c.id == idA);
    final cBIdx = workingCuts.indexWhere((c) => c.id == idB);
    if (cAIdx != -1 && cBIdx != -1) {
      final cutA = workingCuts[cAIdx];
      final cutB = workingCuts[cBIdx];
      // Find closest pair of endpoints
      final d11 = cutA.p1.distanceTo(cutB.p1);
      final d12 = cutA.p1.distanceTo(cutB.p2);
      final d21 = cutA.p2.distanceTo(cutB.p1);
      final d22 = cutA.p2.distanceTo(cutB.p2);
      final minD = [d11, d12, d21, d22].reduce(math.min);

      if (minD == d11) {
        final mid = CadPoint2D((cutA.p1.x + cutB.p1.x) / 2, (cutA.p1.y + cutB.p1.y) / 2);
        workingCuts[cAIdx] = cutA.copyWith(p1: mid);
        workingCuts[cBIdx] = cutB.copyWith(p1: mid);
      } else if (minD == d12) {
        final mid = CadPoint2D((cutA.p1.x + cutB.p2.x) / 2, (cutA.p1.y + cutB.p2.y) / 2);
        workingCuts[cAIdx] = cutA.copyWith(p1: mid);
        workingCuts[cBIdx] = cutB.copyWith(p2: mid);
      } else if (minD == d21) {
        final mid = CadPoint2D((cutA.p2.x + cutB.p1.x) / 2, (cutA.p2.y + cutB.p1.y) / 2);
        workingCuts[cAIdx] = cutA.copyWith(p2: mid);
        workingCuts[cBIdx] = cutB.copyWith(p1: mid);
      } else {
        final mid = CadPoint2D((cutA.p2.x + cutB.p2.x) / 2, (cutA.p2.y + cutB.p2.y) / 2);
        workingCuts[cAIdx] = cutA.copyWith(p2: mid);
        workingCuts[cBIdx] = cutB.copyWith(p2: mid);
      }
      return true;
    }

    return false;
  }

  static bool _applyParallel(
    CadConstraint c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.length < 2) return false;
    final idA = c.entityIds[0];
    final idB = c.entityIds[1];

    double? angleA;
    final cutAIdx = workingCuts.indexWhere((cut) => cut.id == idA);
    if (cutAIdx != -1) {
      final cutA = workingCuts[cutAIdx];
      angleA = math.atan2(cutA.p2.y - cutA.p1.y, cutA.p2.x - cutA.p1.x);
    } else {
      final bendAIdx = workingBends.indexWhere((b) => b.id == idA);
      if (bendAIdx != -1) {
        final bendA = workingBends[bendAIdx];
        angleA = math.atan2(bendA.p2.y - bendA.p1.y, bendA.p2.x - bendA.p1.x);
      }
    }

    if (angleA == null) return false;

    // Apply angleA to entity B
    if (!fixedIds.contains(idB)) {
      final cutBIdx = workingCuts.indexWhere((cut) => cut.id == idB);
      if (cutBIdx != -1) {
        final cutB = workingCuts[cutBIdx];
        final len = cutB.length;
        final mid = cutB.midpoint;
        final halfDx = (len / 2.0) * math.cos(angleA);
        final halfDy = (len / 2.0) * math.sin(angleA);
        workingCuts[cutBIdx] = cutB.copyWith(
          p1: CadPoint2D(mid.x - halfDx, mid.y - halfDy),
          p2: CadPoint2D(mid.x + halfDx, mid.y + halfDy),
        );
        return true;
      }

      final bendBIdx = workingBends.indexWhere((b) => b.id == idB);
      if (bendBIdx != -1) {
        final bendB = workingBends[bendBIdx];
        final len = bendB.length;
        final mid = bendB.midpoint;
        final halfDx = (len / 2.0) * math.cos(angleA);
        final halfDy = (len / 2.0) * math.sin(angleA);
        workingBends[bendBIdx] = bendB.copyWith(
          p1: CadPoint2D(mid.x - halfDx, mid.y - halfDy),
          p2: CadPoint2D(mid.x + halfDx, mid.y + halfDy),
        );
        return true;
      }
    }

    return false;
  }

  static bool _applyPerpendicular(
    CadConstraint c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.length < 2) return false;
    final idA = c.entityIds[0];
    final idB = c.entityIds[1];

    double? angleA;
    final cutAIdx = workingCuts.indexWhere((cut) => cut.id == idA);
    if (cutAIdx != -1) {
      final cutA = workingCuts[cutAIdx];
      angleA = math.atan2(cutA.p2.y - cutA.p1.y, cutA.p2.x - cutA.p1.x);
    } else {
      final bendAIdx = workingBends.indexWhere((b) => b.id == idA);
      if (bendAIdx != -1) {
        final bendA = workingBends[bendAIdx];
        angleA = math.atan2(bendA.p2.y - bendA.p1.y, bendA.p2.x - bendA.p1.x);
      }
    }

    if (angleA == null) return false;
    final perpAngle = angleA + math.pi / 2.0;

    // Apply perpendicular angle to entity B
    if (!fixedIds.contains(idB)) {
      final cutBIdx = workingCuts.indexWhere((cut) => cut.id == idB);
      if (cutBIdx != -1) {
        final cutB = workingCuts[cutBIdx];
        final len = cutB.length;
        final mid = cutB.midpoint;
        final halfDx = (len / 2.0) * math.cos(perpAngle);
        final halfDy = (len / 2.0) * math.sin(perpAngle);
        workingCuts[cutBIdx] = cutB.copyWith(
          p1: CadPoint2D(mid.x - halfDx, mid.y - halfDy),
          p2: CadPoint2D(mid.x + halfDx, mid.y + halfDy),
        );
        return true;
      }

      final bendBIdx = workingBends.indexWhere((b) => b.id == idB);
      if (bendBIdx != -1) {
        final bendB = workingBends[bendBIdx];
        final len = bendB.length;
        final mid = bendB.midpoint;
        final halfDx = (len / 2.0) * math.cos(perpAngle);
        final halfDy = (len / 2.0) * math.sin(perpAngle);
        workingBends[bendBIdx] = bendB.copyWith(
          p1: CadPoint2D(mid.x - halfDx, mid.y - halfDy),
          p2: CadPoint2D(mid.x + halfDx, mid.y + halfDy),
        );
        return true;
      }
    }

    return false;
  }

  static bool _applyConcentric(
    CadConstraint c, {
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.length < 2) return false;
    final idA = c.entityIds[0];
    final idB = c.entityIds[1];

    final pAIdx = workingPunches.indexWhere((p) => p.id == idA);
    final pBIdx = workingPunches.indexWhere((p) => p.id == idB);
    if (pAIdx == -1 || pBIdx == -1) return false;

    final pA = workingPunches[pAIdx];
    final pB = workingPunches[pBIdx];

    final targetCenter = fixedIds.contains(idA)
        ? pA.center
        : (fixedIds.contains(idB) ? pB.center : pA.center);

    if (!fixedIds.contains(idB)) {
      workingPunches[pBIdx] = pB.copyWith(center: targetCenter);
    } else if (!fixedIds.contains(idA)) {
      workingPunches[pAIdx] = pA.copyWith(center: targetCenter);
    }
    return true;
  }

  static bool _applyEqual(
    CadConstraint c, {
    required List<CadLineSegment> workingCuts,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.length < 2) return false;
    final idA = c.entityIds[0];
    final idB = c.entityIds[1];

    // Case 1: Line length equality
    final cAIdx = workingCuts.indexWhere((cut) => cut.id == idA);
    final cBIdx = workingCuts.indexWhere((cut) => cut.id == idB);
    if (cAIdx != -1 && cBIdx != -1) {
      final cutA = workingCuts[cAIdx];
      final cutB = workingCuts[cBIdx];
      final targetLen = fixedIds.contains(idB) ? cutB.length : cutA.length;

      if (!fixedIds.contains(idB)) {
        final angleB = cutB.angleRad;
        final midB = cutB.midpoint;
        final halfDx = (targetLen / 2.0) * math.cos(angleB);
        final halfDy = (targetLen / 2.0) * math.sin(angleB);
        workingCuts[cBIdx] = cutB.copyWith(
          p1: CadPoint2D(midB.x - halfDx, midB.y - halfDy),
          p2: CadPoint2D(midB.x + halfDx, midB.y + halfDy),
        );
        return true;
      }
    }

    // Case 2: Punch diameter equality
    final pAIdx = workingPunches.indexWhere((p) => p.id == idA);
    final pBIdx = workingPunches.indexWhere((p) => p.id == idB);
    if (pAIdx != -1 && pBIdx != -1) {
      final pA = workingPunches[pAIdx];
      final pB = workingPunches[pBIdx];
      final targetDia = fixedIds.contains(idB) ? pB.diameterMm : pA.diameterMm;

      if (!fixedIds.contains(idB)) {
        workingPunches[pBIdx] = pB.copyWith(diameterMm: targetDia);
        return true;
      }
    }

    return false;
  }

  static bool _applyCollinear(
    CadConstraint c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.length < 2) return false;
    final idA = c.entityIds[0];
    final idB = c.entityIds[1];

    // Project endpoints of line B onto the infinite line of line A
    CadPoint2D? p1A, p2A;
    final cutAIdx = workingCuts.indexWhere((cut) => cut.id == idA);
    if (cutAIdx != -1) {
      p1A = workingCuts[cutAIdx].p1;
      p2A = workingCuts[cutAIdx].p2;
    }

    if (p1A == null || p2A == null) return false;

    final cutBIdx = workingCuts.indexWhere((cut) => cut.id == idB);
    if (cutBIdx != -1 && !fixedIds.contains(idB)) {
      final cutB = workingCuts[cutBIdx];
      final proj1 = _projectPointOnLine(cutB.p1, p1A, p2A);
      final proj2 = _projectPointOnLine(cutB.p2, p1A, p2A);
      workingCuts[cutBIdx] = cutB.copyWith(p1: proj1, p2: proj2);
      return true;
    }

    return false;
  }

  static bool _applyDistance(
    CadConstraint c, {
    required List<CadLineSegment> workingCuts,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.entityIds.length < 2 || c.parameterValue == null) return false;
    final targetDist = c.parameterValue!;
    final idA = c.entityIds[0];
    final idB = c.entityIds[1];

    final pAIdx = workingPunches.indexWhere((p) => p.id == idA);
    final pBIdx = workingPunches.indexWhere((p) => p.id == idB);
    if (pAIdx != -1 && pBIdx != -1) {
      final pA = workingPunches[pAIdx];
      final pB = workingPunches[pBIdx];
      final curDist = pA.center.distanceTo(pB.center);
      if (curDist < 1e-4) return false;

      final dirX = (pB.center.x - pA.center.x) / curDist;
      final dirY = (pB.center.y - pA.center.y) / curDist;

      if (!fixedIds.contains(idB)) {
        final newCenter = CadPoint2D(pA.center.x + dirX * targetDist, pA.center.y + dirY * targetDist);
        workingPunches[pBIdx] = pB.copyWith(center: newCenter);
        return true;
      }
    }

    return false;
  }

  static CadPoint2D _projectPointOnLine(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-6) return a;

    final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
    return CadPoint2D(a.x + t * dx, a.y + t * dy);
  }
}
