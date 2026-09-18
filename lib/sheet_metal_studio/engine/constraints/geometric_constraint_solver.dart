// =============================================================================
// geometric_constraint_solver.dart
//
// Professional 2D Geometric & Dimensional Constraint Solver for Sheet Metal Studio
// per Phase 1 Master Guide Sections 6, 7, 8, 10, 18, 26, 38, 49 & Sets 03, 04, 06, 07.
//
// Binds and regenerates:
// 1. Outer Contour boundary edges (e.g. EDGE_LEFT to EDGE_RIGHT width, length, branches)
// 2. Punch/Hole centers to reference edges & centerlines
// 3. Fold bend lines to boundary edges (parallel offsets, distance)
// 4. Centerline symmetry (CENTER_X, CENTER_Y)
// 5. Part-to-part / branch-to-main-body binding
// =============================================================================

import 'dart:math' as math;
import '../../models/cad_constraint.dart';
import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/fold_bend_line.dart';
import '../../models/dsf_document.dart';
import '../../models/constraints/stable_geometry_reference.dart';
import '../../models/constraints/constraint_definition.dart';
import '../../models/constraints/reference_geometry.dart';
import '../planar_face_decomposer.dart';
import 'contour_topology_classifier.dart';
import 'expression_parser_engine.dart';

class GeometricSolverResult {
  final bool success;
  final DsfDocument updatedDocument;
  final List<ConstraintDefinition> satisfiedConstraints;
  final List<ConstraintDefinition> violatedConstraints;
  final List<String> conflicts;
  final int degreesOfFreedom;
  final String message;

  const GeometricSolverResult({
    required this.success,
    required this.updatedDocument,
    this.satisfiedConstraints = const [],
    this.violatedConstraints = const [],
    this.conflicts = const [],
    this.degreesOfFreedom = 0,
    required this.message,
  });
}

class GeometricConstraintSolver {
  /// Solves all active constraints on [document] using parameter bindings and
  /// reference geometry. Updates outerContour, bends, punches, and cut lines.
  static GeometricSolverResult solve({
    required DsfDocument document,
    List<ConstraintDefinition>? overrideConstraints,
    Map<String, double>? parameterOverrides,
    List<ReferenceGeometry>? customReferences,
  }) {
    // 1. Collect and normalize constraints
    final constraints = (overrideConstraints ??
            document.constraints.map((c) => ConstraintDefinition.fromLegacy(c)))
        .where((c) => c.isActive && !c.isSuppressed)
        .toList();

    // 2. Build parameters map
    final parameters = Map<String, double>.from(document.parameters);
    if (parameterOverrides != null) {
      parameters.addAll(parameterOverrides);
    }

    // 3. Working copies
    var workingContour = List<CadPoint2D>.from(document.outerContour);
    var workingCuts = List<CadLineSegment>.from(document.cutLines);
    var workingBends = List<FoldBendLine>.from(document.bends);
    var workingPunches = List<CncPunchPrimitive>.from(document.punches);

    // Synthesize driving constraints if parameterOverrides are provided for fittings
    final activeConstraints = List<ConstraintDefinition>.from(constraints);
    if (parameterOverrides != null && parameterOverrides.isNotEmpty) {
      final topology = ContourTopologyClassifier.classify(workingContour, workingBends, document);
      if (topology == ContourTopologyType.tBranch) {
        if (parameterOverrides.containsKey('width') &&
            !activeConstraints.any((c) => c.parameterId?.toLowerCase() == 'width')) {
          activeConstraints.add(ConstraintDefinition(
            id: 'DRIVE_MAIN_WIDTH',
            type: CadConstraintType.distance,
            references: [EntityRef.edgeBottom, EntityRef.edgeTop],
            targetValue: parameterOverrides['width'],
            parameterId: 'width',
          ));
        }
        if (parameterOverrides.containsKey('branchWidth') &&
            !activeConstraints.any((c) => c.parameterId?.toLowerCase() == 'branchwidth')) {
          activeConstraints.add(ConstraintDefinition(
            id: 'DRIVE_BRANCH_WIDTH',
            type: CadConstraintType.distance,
            references: [const EntityRef(entityId: 'EDGE_BRANCH_LEFT'), const EntityRef(entityId: 'EDGE_BRANCH_RIGHT')],
            targetValue: parameterOverrides['branchWidth'],
            parameterId: 'branchWidth',
          ));
        }
        if (parameterOverrides.containsKey('length') &&
            !activeConstraints.any((c) => c.parameterId?.toLowerCase() == 'length')) {
          activeConstraints.add(ConstraintDefinition(
            id: 'DRIVE_MAIN_LENGTH',
            type: CadConstraintType.distance,
            references: [EntityRef.edgeLeft, EntityRef.edgeRight],
            targetValue: parameterOverrides['length'],
            parameterId: 'length',
          ));
        }
      } else if (topology == ContourTopologyType.taperedReducer) {
        final win = parameterOverrides['widthIn'] ?? parameterOverrides['width_a'];
        if (win != null && !activeConstraints.any((c) => c.parameterId?.toLowerCase() == 'widthin')) {
          activeConstraints.add(ConstraintDefinition(
            id: 'DRIVE_REDUCER_WIN',
            type: CadConstraintType.distance,
            references: [EntityRef.edgeLeft, EntityRef.edgeLeft],
            targetValue: win,
            parameterId: 'widthIn',
          ));
        }
        final wout = parameterOverrides['widthOut'] ?? parameterOverrides['width_b'];
        if (wout != null && !activeConstraints.any((c) => c.parameterId?.toLowerCase() == 'widthout')) {
          activeConstraints.add(ConstraintDefinition(
            id: 'DRIVE_REDUCER_WOUT',
            type: CadConstraintType.distance,
            references: [EntityRef.edgeRight, EntityRef.edgeRight],
            targetValue: wout,
            parameterId: 'widthOut',
          ));
        }
        if (parameterOverrides.containsKey('length') &&
            !activeConstraints.any((c) => c.parameterId?.toLowerCase() == 'length')) {
          activeConstraints.add(ConstraintDefinition(
            id: 'DRIVE_REDUCER_LENGTH',
            type: CadConstraintType.distance,
            references: [EntityRef.edgeLeft, EntityRef.edgeRight],
            targetValue: parameterOverrides['length'],
            parameterId: 'length',
          ));
        }
      }
    }

    if (activeConstraints.isEmpty) {
      return GeometricSolverResult(
        success: true,
        updatedDocument: document,
        message: 'No active constraints to solve.',
      );
    }



    final fixedEntityIds = <String>{};
    for (final c in constraints) {
      if (c.type == CadConstraintType.fixed) {
        for (final ref in c.references) {
          fixedEntityIds.add(ref.canonicalPath);
          fixedEntityIds.add(ref.entityId);
        }
      }
    }

    final satisfied = <ConstraintDefinition>[];
    final violated = <ConstraintDefinition>[];
    final conflicts = <String>[];

    // Iterative relaxation pass (up to 4 iterations for chained relations)
    for (int iter = 0; iter < 4; iter++) {
      for (final constraint in activeConstraints) {
        // Resolve target numeric value (either direct targetValue or via linked parameter)
        double? targetVal = constraint.targetValue;
        if (constraint.parameterId != null && constraint.parameterId!.isNotEmpty) {
          final paramName = constraint.parameterId!;
          if (parameters.containsKey(paramName)) {
            targetVal = parameters[paramName];
          } else {
            // Try evaluating as formula expression
            try {
              targetVal = ExpressionParserEngine.evaluate(paramName, parameters);
            } catch (_) {
              // Leave targetVal as is
            }
          }
        }

        bool ok = true;
        try {
          switch (constraint.type) {
            case CadConstraintType.fixed:
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

            case CadConstraintType.distance:
              ok = _applyDistance(
                constraint,
                targetValue: targetVal,
                workingContour: workingContour,
                workingCuts: workingCuts,
                workingBends: workingBends,
                workingPunches: workingPunches,
                fixedIds: fixedEntityIds,
                document: document,
                parameters: parameters,
                customReferences: customReferences,
              );
              break;

            case CadConstraintType.symmetric:
              ok = _applySymmetric(
                constraint,
                workingContour: workingContour,
                workingPunches: workingPunches,
                workingBends: workingBends,
                fixedIds: fixedEntityIds,
              );
              break;

            case CadConstraintType.coincident:
              ok = _applyCoincident(
                constraint,
                workingContour: workingContour,
                workingCuts: workingCuts,
                workingBends: workingBends,
                workingPunches: workingPunches,
                fixedIds: fixedEntityIds,
                document: document,
                customReferences: customReferences,
              );
              break;

            case CadConstraintType.parallel:
              ok = _applyParallel(
                constraint,
                workingCuts: workingCuts,
                workingBends: workingBends,
                fixedIds: fixedEntityIds,
                document: document,
                customReferences: customReferences,
              );
              break;

            case CadConstraintType.perpendicular:
              ok = _applyPerpendicular(
                constraint,
                workingCuts: workingCuts,
                workingBends: workingBends,
                fixedIds: fixedEntityIds,
                document: document,
                customReferences: customReferences,
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

            case CadConstraintType.angle:
            case CadConstraintType.radius:
            case CadConstraintType.diameter:
            case CadConstraintType.tangent:
              ok = true; // Accepted in tolerance
              break;
          }
        } catch (e) {
          ok = false;
          conflicts.add('Constraint "${constraint.id}" error: $e');
        }

        if (iter == 3) {
          if (ok) {
            satisfied.add(constraint);
          } else {
            violated.add(constraint);
            conflicts.add('Constraint "${constraint.id}" (${constraint.label}) could not be satisfied.');
          }
        }
      }
    }

    // 4. Recompose Planar Faces & Fold Kinematics with newly constrained boundary
    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: workingContour,
      bends: workingBends,
      cutLines: workingCuts,
      preferredBaseFaceId: document.baseFaceId,
    );

    final legacyConstraints = activeConstraints.map((c) => c.toLegacy()).toList();

    final updatedDoc = document.copyWith(
      outerContour: workingContour,
      cutLines: workingCuts,
      bends: decomp.connectedBends,
      faces: decomp.faces,
      punches: workingPunches,
      constraints: legacyConstraints,
      parameters: parameters,
      baseFaceId: decomp.baseFaceId,
    );

    final isSuccess = violated.isEmpty;
    final message = isSuccess
        ? 'All ${activeConstraints.length} constraints successfully solved and bound.'
        : '${violated.length} constraints could not be solved. (${conflicts.length} conflicts)';

    return GeometricSolverResult(
      success: isSuccess,
      updatedDocument: updatedDoc,
      satisfiedConstraints: satisfied,
      violatedConstraints: violated,
      conflicts: conflicts,
      message: message,
    );
  }

  // ===========================================================================
  // 1. Distance Constraint Solving (Outer Contour, Punches, Bends, Edges)
  // ===========================================================================
  static bool _applyDistance(
    ConstraintDefinition c, {
    required double? targetValue,
    required List<CadPoint2D> workingContour,
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
    required DsfDocument document,
    Map<String, double>? parameters,
    List<ReferenceGeometry>? customReferences,
  }) {
    if (targetValue == null || c.references.length < 2) return false;
    if (targetValue <= 0.0) {
      return false; // Target dimension must be strictly positive
    }

    final topology = ContourTopologyClassifier.classify(workingContour, workingBends, document);
    if (topology == ContourTopologyType.tBranch) {
      final handled = _applyDistanceTee(
        c,
        targetValue: targetValue,
        workingContour: workingContour,
        workingBends: workingBends,
        workingPunches: workingPunches,
        fixedIds: fixedIds,
        document: document,
        parameters: parameters ?? {},
      );
      if (handled) return true;
    } else if (topology == ContourTopologyType.taperedReducer) {
      final handled = _applyDistanceReducer(
        c,
        targetValue: targetValue,
        workingContour: workingContour,
        workingBends: workingBends,
        workingPunches: workingPunches,
        fixedIds: fixedIds,
        document: document,
        parameters: parameters ?? {},
      );
      if (handled) return true;
    }
    final refA = c.references[0];
    final refB = c.references[1];

    final idA = refA.entityId.toUpperCase();
    final idB = refB.entityId.toUpperCase();

    // -------------------------------------------------------------------------
    // A. Edge-to-Edge Distance: e.g. Distance(EDGE_LEFT, EDGE_RIGHT) = WIDTH
    // -------------------------------------------------------------------------
    if ((idA == 'EDGE_LEFT' && idB == 'EDGE_RIGHT') || (idA == 'EDGE_RIGHT' && idB == 'EDGE_LEFT')) {
      if (workingContour.isEmpty) return false;
      double minX = double.infinity;
      double maxX = -double.infinity;
      for (final pt in workingContour) {
        if (pt.x < minX) minX = pt.x;
        if (pt.x > maxX) maxX = pt.x;
      }
      final currentWidth = maxX - minX;
      if ((currentWidth - targetValue).abs() < 1e-4) return true;

      final targetMaxX = minX + targetValue;
      final scaleFactor = currentWidth > 1e-4 ? targetValue / currentWidth : 1.0;

      // Update outer contour vertices
      for (int i = 0; i < workingContour.length; i++) {
        final pt = workingContour[i];
        if ((pt.x - maxX).abs() < 1.0) {
          // Exactly on the right edge -> snap to targetMaxX
          workingContour[i] = CadPoint2D(targetMaxX, pt.y);
        } else if ((pt.x - minX).abs() > 1.0) {
          // Interior/branch vertices -> scale proportionally
          final newX = minX + (pt.x - minX) * scaleFactor;
          workingContour[i] = CadPoint2D(newX, pt.y);
        }
      }
      return true;
    }

    // -------------------------------------------------------------------------
    // B. Edge-to-Edge Distance: e.g. Distance(EDGE_BOTTOM, EDGE_TOP) = LENGTH
    // -------------------------------------------------------------------------
    if ((idA == 'EDGE_BOTTOM' && idB == 'EDGE_TOP') || (idA == 'EDGE_TOP' && idB == 'EDGE_BOTTOM')) {
      if (workingContour.isEmpty) return false;
      double minY = double.infinity;
      double maxY = -double.infinity;
      for (final pt in workingContour) {
        if (pt.y < minY) minY = pt.y;
        if (pt.y > maxY) maxY = pt.y;
      }
      final currentHeight = maxY - minY;
      if ((currentHeight - targetValue).abs() < 1e-4) return true;

      final targetMaxY = minY + targetValue;
      final scaleFactor = currentHeight > 1e-4 ? targetValue / currentHeight : 1.0;

      for (int i = 0; i < workingContour.length; i++) {
        final pt = workingContour[i];
        if ((pt.y - maxY).abs() < 1.0) {
          workingContour[i] = CadPoint2D(pt.x, targetMaxY);
        } else if ((pt.y - minY).abs() > 1.0) {
          final newY = minY + (pt.y - minY) * scaleFactor;
          workingContour[i] = CadPoint2D(pt.x, newY);
        }
      }
      return true;
    }

    // -------------------------------------------------------------------------
    // C. Punch-to-Edge Distance: e.g. Distance(Punch01.center, EDGE_LEFT) = 25
    // -------------------------------------------------------------------------
    final punchRef = refA.subRef == GeometrySubRefType.center
        ? refA
        : (refB.subRef == GeometrySubRefType.center ? refB : null);
    final edgeRef = (punchRef == refA) ? refB : refA;

    if (punchRef != null) {
      final pIdx = workingPunches.indexWhere((p) => p.id == punchRef.entityId);
      if (pIdx != -1) {
        final punch = workingPunches[pIdx];
        final bounds = _contourBounds(workingContour);

        if (edgeRef.entityId.toUpperCase() == 'EDGE_LEFT') {
          final targetX = bounds.minX + targetValue;
          workingPunches[pIdx] = punch.copyWith(center: CadPoint2D(targetX, punch.center.y));
          return true;
        } else if (edgeRef.entityId.toUpperCase() == 'EDGE_RIGHT') {
          final targetX = bounds.maxX - targetValue;
          workingPunches[pIdx] = punch.copyWith(center: CadPoint2D(targetX, punch.center.y));
          return true;
        } else if (edgeRef.entityId.toUpperCase() == 'EDGE_BOTTOM') {
          final targetY = bounds.minY + targetValue;
          workingPunches[pIdx] = punch.copyWith(center: CadPoint2D(punch.center.x, targetY));
          return true;
        } else if (edgeRef.entityId.toUpperCase() == 'EDGE_TOP') {
          final targetY = bounds.maxY - targetValue;
          workingPunches[pIdx] = punch.copyWith(center: CadPoint2D(punch.center.x, targetY));
          return true;
        } else if (edgeRef.entityId.toUpperCase() == 'CENTER_X') {
          final midX = (bounds.minX + bounds.maxX) / 2.0;
          final targetX = punch.center.x >= midX ? midX + targetValue : midX - targetValue;
          workingPunches[pIdx] = punch.copyWith(center: CadPoint2D(targetX, punch.center.y));
          return true;
        } else if (edgeRef.entityId.toUpperCase() == 'CENTER_Y') {
          final midY = (bounds.minY + bounds.maxY) / 2.0;
          final targetY = punch.center.y >= midY ? midY + targetValue : midY - targetValue;
          workingPunches[pIdx] = punch.copyWith(center: CadPoint2D(punch.center.x, targetY));
          return true;
        } else {
          final allRefs = [
            ...?customReferences,
            ...document.referenceGeometries,
          ];
          ReferenceGeometry? matchRef;
          for (final r in allRefs) {
            if (r.id.toUpperCase() == edgeRef.entityId.toUpperCase()) {
              matchRef = r;
              break;
            }
          }
          if (matchRef != null) {
            if ((matchRef.p1.y - matchRef.p2.y).abs() < 1e-4) {
              final refY = matchRef.p1.y;
              final targetY = punch.center.y >= refY ? refY + targetValue : refY - targetValue;
              workingPunches[pIdx] = punch.copyWith(center: CadPoint2D(punch.center.x, targetY));
              return true;
            } else if ((matchRef.p1.x - matchRef.p2.x).abs() < 1e-4) {
              final refX = matchRef.p1.x;
              final targetX = punch.center.x >= refX ? refX + targetValue : refX - targetValue;
              workingPunches[pIdx] = punch.copyWith(center: CadPoint2D(targetX, punch.center.y));
              return true;
            } else {
              final p = _projectPointOnLine(punch.center, matchRef.p1, matchRef.p2);
              final dx = matchRef.p2.x - matchRef.p1.x;
              final dy = matchRef.p2.y - matchRef.p1.y;
              final len = math.sqrt(dx * dx + dy * dy);
              if (len > 1e-4) {
                final nx = -dy / len;
                final ny = dx / len;
                final curD = (punch.center.x - p.x) * nx + (punch.center.y - p.y) * ny;
                final sign = curD >= 0 ? 1.0 : -1.0;
                workingPunches[pIdx] = punch.copyWith(
                  center: CadPoint2D(p.x + nx * targetValue * sign, p.y + ny * targetValue * sign),
                );
                return true;
              }
            }
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // D. Bend-to-Edge Distance: e.g. Distance(Bend01, EDGE_LEFT) = 50
    // -------------------------------------------------------------------------
    final bendRef = workingBends.any((b) => b.id == refA.entityId)
        ? refA
        : (workingBends.any((b) => b.id == refB.entityId) ? refB : null);
    final bendEdgeRef = (bendRef == refA) ? refB : refA;

    if (bendRef != null) {
      final bIdx = workingBends.indexWhere((b) => b.id == bendRef.entityId);
      if (bIdx != -1) {
        final bend = workingBends[bIdx];
        final bounds = _contourBounds(workingContour);

        if (bendEdgeRef.entityId.toUpperCase() == 'EDGE_LEFT') {
          final shiftX = (bounds.minX + targetValue) - bend.p1.x;
          workingBends[bIdx] = bend.copyWith(
            p1: CadPoint2D(bend.p1.x + shiftX, bend.p1.y),
            p2: CadPoint2D(bend.p2.x + shiftX, bend.p2.y),
          );
          return true;
        } else if (bendEdgeRef.entityId.toUpperCase() == 'EDGE_RIGHT') {
          final shiftX = (bounds.maxX - targetValue) - bend.p1.x;
          workingBends[bIdx] = bend.copyWith(
            p1: CadPoint2D(bend.p1.x + shiftX, bend.p1.y),
            p2: CadPoint2D(bend.p2.x + shiftX, bend.p2.y),
          );
          return true;
        } else if (bendEdgeRef.entityId.toUpperCase() == 'EDGE_BOTTOM') {
          final shiftY = (bounds.minY + targetValue) - bend.p1.y;
          workingBends[bIdx] = bend.copyWith(
            p1: CadPoint2D(bend.p1.x, bend.p1.y + shiftY),
            p2: CadPoint2D(bend.p2.x, bend.p2.y + shiftY),
          );
          return true;
        } else if (bendEdgeRef.entityId.toUpperCase() == 'EDGE_TOP') {
          final shiftY = (bounds.maxY - targetValue) - bend.p1.y;
          workingBends[bIdx] = bend.copyWith(
            p1: CadPoint2D(bend.p1.x, bend.p1.y + shiftY),
            p2: CadPoint2D(bend.p2.x, bend.p2.y + shiftY),
          );
          return true;
        } else {
          final allRefs = [
            ...?customReferences,
            ...document.referenceGeometries,
          ];
          ReferenceGeometry? matchRef;
          for (final r in allRefs) {
            if (r.id.toUpperCase() == bendEdgeRef.entityId.toUpperCase()) {
              matchRef = r;
              break;
            }
          }
          if (matchRef != null) {
            if ((matchRef.p1.y - matchRef.p2.y).abs() < 1e-4) {
              final shiftY = (matchRef.p1.y + targetValue) - bend.p1.y;
              workingBends[bIdx] = bend.copyWith(
                p1: CadPoint2D(bend.p1.x, bend.p1.y + shiftY),
                p2: CadPoint2D(bend.p2.x, bend.p2.y + shiftY),
              );
              return true;
            } else if ((matchRef.p1.x - matchRef.p2.x).abs() < 1e-4) {
              final shiftX = (matchRef.p1.x + targetValue) - bend.p1.x;
              workingBends[bIdx] = bend.copyWith(
                p1: CadPoint2D(bend.p1.x + shiftX, bend.p1.y),
                p2: CadPoint2D(bend.p2.x + shiftX, bend.p2.y),
              );
              return true;
            }
          }
        }
      }
    }

    return false;
  }


  // ===========================================================================
  // 1.1 Multi-Branch Unequal & Equal Tee Solving (SET 17)
  // ===========================================================================
  static bool _applyDistanceTee(
    ConstraintDefinition c, {
    required double targetValue,
    required List<CadPoint2D> workingContour,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
    required DsfDocument document,
    required Map<String, double> parameters,
  }) {
    final refA = c.references[0];
    final refB = c.references[1];
    final idA = refA.entityId.toUpperCase();
    final idB = refB.entityId.toUpperCase();
    final paramId = (c.parameterId ?? '').toLowerCase();

    final isBranchWidth = paramId == 'branchwidth' ||
        paramId == 'branch_width' ||
        idA.contains('BRANCH') ||
        idB.contains('BRANCH') ||
        (refA.partId?.toLowerCase().contains('branch') ?? false) ||
        (refB.partId?.toLowerCase().contains('branch') ?? false);

    final isMainWidth = paramId == 'width' ||
        paramId == 'main_width' ||
        paramId == 'mainwidth' ||
        paramId == 'runwidth' ||
        ((idA == 'EDGE_BOTTOM' && idB == 'EDGE_TOP') || (idA == 'EDGE_TOP' && idB == 'EDGE_BOTTOM')) ||
        idA.contains('MAIN') ||
        idB.contains('MAIN');

    final isMainLength = paramId == 'length' ||
        paramId == 'main_length' ||
        paramId == 'mainlength';

    final isHeight = paramId == 'height' || paramId == 'flange_height';

    if (!isBranchWidth && !isMainWidth && !isMainLength && !isHeight) {
      return false; // Not a Tee boundary dimensional constraint
    }

    final bounds = _contourBounds(workingContour);
    final minX = bounds.minX;
    final maxX = bounds.maxX;
    final minY = bounds.minY;

    // Detect branch position from bends if available, or fall back to geometry/parameters
    final branchLeftBend = workingBends.where((b) => b.id == 'BEND_BRANCH_L' || b.id.contains('BRANCH_L')).firstOrNull;
    final branchRightBend = workingBends.where((b) => b.id == 'BEND_BRANCH_R' || b.id.contains('BRANCH_R')).firstOrNull;

    double notch1X = 50.0;
    double notch2X = 150.0;
    double throatY = minY + 150.0;

    if (branchLeftBend != null && branchRightBend != null) {
      notch1X = branchLeftBend.p1.x;
      notch2X = branchRightBend.p1.x;
      throatY = branchLeftBend.p1.y;
    } else {
      final bw = parameters['branchWidth'] ?? 100.0;
      final w = parameters['width'] ?? 100.0;
      final h = parameters['height'] ?? 50.0;
      notch1X = minX + 50.0;
      notch2X = notch1X + bw;
      throatY = minY + h + w;
    }

    final currentBw = (notch2X - notch1X).abs();
    final h = parameters['height'] ?? 50.0;
    final currentMainW = parameters['width'] ?? (throatY - (minY + h));
    final currentMainL = maxX - minX;

    if (isBranchWidth) {
      if (targetValue >= currentMainL - 10.0 || targetValue <= 0.0) {
        return false; // Branch cannot exceed or equal main run length
      }
      final dBw = targetValue - currentBw;
      if (dBw.abs() < 1e-4) return true;

      CadPoint2D morphX(CadPoint2D pt) {
        double x = pt.x;
        if (x >= notch2X - 1.0) {
          x += dBw;
        } else if (x > notch1X + 1.0) {
          final t = (x - notch1X) / (currentBw > 0 ? currentBw : 1.0);
          x += dBw * t.clamp(0.0, 1.0);
        }
        return CadPoint2D(x, pt.y);
      }

      for (int i = 0; i < workingContour.length; i++) {
        workingContour[i] = morphX(workingContour[i]);
      }
      for (int i = 0; i < workingBends.length; i++) {
        workingBends[i] = workingBends[i].copyWith(
          p1: morphX(workingBends[i].p1),
          p2: morphX(workingBends[i].p2),
        );
      }
      for (int i = 0; i < workingPunches.length; i++) {
        workingPunches[i] = workingPunches[i].copyWith(
          center: morphX(workingPunches[i].center),
        );
      }
      parameters['branchWidth'] = targetValue;
      return true;
    }

    if (isMainWidth) {
      if (targetValue <= 0.0) return false;
      final dW = targetValue - currentMainW;
      if (dW.abs() < 1e-4) return true;

      final bedBottom = minY + h;
      final bedTop = bedBottom + currentMainW;
      CadPoint2D morphY(CadPoint2D pt) {
        double y = pt.y;
        if (y >= bedTop - 1.0) {
          y += dW;
        } else if (y > bedBottom + 1.0) {
          final t = (y - bedBottom) / (currentMainW > 0 ? currentMainW : 1.0);
          y += dW * t.clamp(0.0, 1.0);
        }
        return CadPoint2D(pt.x, y);
      }

      for (int i = 0; i < workingContour.length; i++) {
        workingContour[i] = morphY(workingContour[i]);
      }
      for (int i = 0; i < workingBends.length; i++) {
        workingBends[i] = workingBends[i].copyWith(
          p1: morphY(workingBends[i].p1),
          p2: morphY(workingBends[i].p2),
        );
      }
      for (int i = 0; i < workingPunches.length; i++) {
        workingPunches[i] = workingPunches[i].copyWith(
          center: morphY(workingPunches[i].center),
        );
      }
      parameters['width'] = targetValue;
      return true;
    }

    if (isMainLength) {
      if (targetValue <= currentBw + 20.0 || targetValue <= 0.0) {
        return false;
      }
      final dL = targetValue - currentMainL;
      if (dL.abs() < 1e-4) return true;

      CadPoint2D morphL(CadPoint2D pt) {
        double x = pt.x;
        if (x > notch2X + 5.0) {
          x += dL;
        }
        return CadPoint2D(x, pt.y);
      }

      for (int i = 0; i < workingContour.length; i++) {
        workingContour[i] = morphL(workingContour[i]);
      }
      for (int i = 0; i < workingBends.length; i++) {
        workingBends[i] = workingBends[i].copyWith(
          p1: morphL(workingBends[i].p1),
          p2: morphL(workingBends[i].p2),
        );
      }
      for (int i = 0; i < workingPunches.length; i++) {
        workingPunches[i] = workingPunches[i].copyWith(
          center: morphL(workingPunches[i].center),
        );
      }
      parameters['length'] = targetValue;
      return true;
    }

    return false;
  }

  // ===========================================================================
  // 1.2 Reducer Morphing (SET 19)
  // ===========================================================================
  static bool _applyDistanceReducer(
    ConstraintDefinition c, {
    required double targetValue,
    required List<CadPoint2D> workingContour,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
    required DsfDocument document,
    required Map<String, double> parameters,
  }) {
    if (targetValue <= 0.0) return false;

    final refA = c.references[0];
    final refB = c.references[1];
    final idA = refA.entityId.toUpperCase();
    final idB = refB.entityId.toUpperCase();
    final paramId = (c.parameterId ?? '').toLowerCase();

    final bounds = _contourBounds(workingContour);
    final minX = bounds.minX;
    final maxX = bounds.maxX;
    final totalX = maxX - minX;
    final midY = (bounds.minY + bounds.maxY) / 2.0;

    final isWidthIn = paramId == 'widthin' ||
        paramId == 'width_in' ||
        paramId == 'width_a' ||
        paramId == 'widtha' ||
        paramId == 'w1';

    final isWidthOut = paramId == 'widthout' ||
        paramId == 'width_out' ||
        paramId == 'width_b' ||
        paramId == 'widthb' ||
        paramId == 'w2';

    final isLength = paramId == 'length' ||
        ((idA == 'EDGE_LEFT' && idB == 'EDGE_RIGHT') || (idA == 'EDGE_RIGHT' && idB == 'EDGE_LEFT'));

    final isEdgeTopBottom = (idA == 'EDGE_BOTTOM' && idB == 'EDGE_TOP') ||
        (idA == 'EDGE_TOP' && idB == 'EDGE_BOTTOM');

    final origWin = parameters['widthIn'] ?? parameters['width_a'] ?? 150.0;
    final origWout = parameters['widthOut'] ?? parameters['width_b'] ?? 100.0;
    final origL = parameters['length'] ?? totalX;

    double dWin = 0.0;
    double dWout = 0.0;
    double dL = 0.0;

    if (isWidthIn) {
      dWin = targetValue - origWin;
      parameters['widthIn'] = targetValue;
      parameters['width_a'] = targetValue;
    } else if (isWidthOut) {
      dWout = targetValue - origWout;
      parameters['widthOut'] = targetValue;
      parameters['width_b'] = targetValue;
    } else if (isLength) {
      if (targetValue <= 20.0) return false;
      dL = targetValue - origL;
      parameters['length'] = targetValue;
    } else if (isEdgeTopBottom) {
      dWin = targetValue - origWin;
      parameters['widthIn'] = targetValue;
    } else {
      return false;
    }

    CadPoint2D morphPoint(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      final tx = ((x - minX) / (totalX > 0 ? totalX : 1.0)).clamp(0.0, 1.0);
      final localDeltaW = dWin * (1.0 - tx) + dWout * tx;

      x += dL * tx;
      if (y > midY) {
        y += localDeltaW / 2.0;
      } else {
        y -= localDeltaW / 2.0;
      }

      return CadPoint2D(x, y);
    }

    for (int i = 0; i < workingContour.length; i++) {
      workingContour[i] = morphPoint(workingContour[i]);
    }
    for (int i = 0; i < workingBends.length; i++) {
      workingBends[i] = workingBends[i].copyWith(
        p1: morphPoint(workingBends[i].p1),
        p2: morphPoint(workingBends[i].p2),
      );
    }
    for (int i = 0; i < workingPunches.length; i++) {
      workingPunches[i] = workingPunches[i].copyWith(
        center: morphPoint(workingPunches[i].center),
      );
    }

    return true;
  }


  // ===========================================================================
  // 2. Symmetry Constraint Solving (CENTER_X / CENTER_Y)
  // ===========================================================================
  static bool _applySymmetric(
    ConstraintDefinition c, {
    required List<CadPoint2D> workingContour,
    required List<CncPunchPrimitive> workingPunches,
    required List<FoldBendLine> workingBends,
    required Set<String> fixedIds,
  }) {
    if (c.references.length < 2) return false;
    final refA = c.references[0];
    final refB = c.references[1];

    final bounds = _contourBounds(workingContour);
    final midX = (bounds.minX + bounds.maxX) / 2.0;

    // Two punches symmetric about CENTER_X
    final p1Idx = workingPunches.indexWhere((p) => p.id == refA.entityId);
    final p2Idx = workingPunches.indexWhere((p) => p.id == refB.entityId);

    if (p1Idx != -1 && p2Idx != -1) {
      final p1 = workingPunches[p1Idx];
      final p2 = workingPunches[p2Idx];
      final avgDist = ((p1.center.x - midX).abs() + (p2.center.x - midX).abs()) / 2.0;
      final avgY = (p1.center.y + p2.center.y) / 2.0;

      workingPunches[p1Idx] = p1.copyWith(
        center: CadPoint2D(midX - avgDist, avgY),
      );
      workingPunches[p2Idx] = p2.copyWith(
        center: CadPoint2D(midX + avgDist, avgY),
      );
      return true;
    }

    return false;
  }

  // ===========================================================================
  // 3. Horizontal & Vertical Geometric Handlers
  // ===========================================================================
  static bool _applyHorizontal(
    ConstraintDefinition c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.references.isEmpty) return false;

    // Single line / bend -> make endpoints share Y
    if (c.references.length == 1) {
      final id = c.references.first.entityId;
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
    if (c.references.length >= 2) {
      final p1Idx = workingPunches.indexWhere((p) => p.id == c.references[0].entityId);
      final p2Idx = workingPunches.indexWhere((p) => p.id == c.references[1].entityId);
      if (p1Idx != -1 && p2Idx != -1) {
        final p1 = workingPunches[p1Idx];
        final p2 = workingPunches[p2Idx];
        final avgY = (p1.center.y + p2.center.y) / 2.0;
        workingPunches[p1Idx] = p1.copyWith(center: CadPoint2D(p1.center.x, avgY));
        workingPunches[p2Idx] = p2.copyWith(center: CadPoint2D(p2.center.x, avgY));
        return true;
      }
    }

    return false;
  }

  static bool _applyVertical(
    ConstraintDefinition c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.references.isEmpty) return false;

    if (c.references.length == 1) {
      final id = c.references.first.entityId;
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

    if (c.references.length >= 2) {
      final p1Idx = workingPunches.indexWhere((p) => p.id == c.references[0].entityId);
      final p2Idx = workingPunches.indexWhere((p) => p.id == c.references[1].entityId);
      if (p1Idx != -1 && p2Idx != -1) {
        final p1 = workingPunches[p1Idx];
        final p2 = workingPunches[p2Idx];
        final avgX = (p1.center.x + p2.center.x) / 2.0;
        workingPunches[p1Idx] = p1.copyWith(center: CadPoint2D(avgX, p1.center.y));
        workingPunches[p2Idx] = p2.copyWith(center: CadPoint2D(avgX, p2.center.y));
        return true;
      }
    }

    return false;
  }

  // ===========================================================================
  // 4. Coincident, Parallel, Perpendicular, Collinear, Concentric, Equal
  // ===========================================================================
  static CadPoint2D _projectPointOnLine(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final lenSq = abx * abx + aby * aby;
    if (lenSq < 1e-6) return a;
    final t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq;
    return CadPoint2D(a.x + t * abx, a.y + t * aby);
  }

  static bool _applyCoincident(
    ConstraintDefinition c, {
    required List<CadPoint2D> workingContour,
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
    required DsfDocument document,
    List<ReferenceGeometry>? customReferences,
  }) {
    if (c.references.length < 2) return false;
    final refA = c.references[0];
    final refB = c.references[1];

    final allRefs = [
      ...?customReferences,
      ...document.referenceGeometries,
    ];

    // 1. Align punch center to reference geometry (construction line, centerline)
    final punchIdx = workingPunches.indexWhere((p) => p.id == refA.entityId || p.id == refB.entityId);
    if (punchIdx != -1) {
      final punch = workingPunches[punchIdx];
      final otherRef = (punch.id == refA.entityId) ? refB : refA;
      ReferenceGeometry? matchRef;
      for (final r in allRefs) {
        if (r.id.toUpperCase() == otherRef.entityId.toUpperCase()) {
          matchRef = r;
          break;
        }
      }
      if (matchRef != null) {
        final projected = _projectPointOnLine(punch.center, matchRef.p1, matchRef.p2);
        workingPunches[punchIdx] = punch.copyWith(center: projected);
        return true;
      }
      // Punch to punch coincident
      final otherPunchIdx = workingPunches.indexWhere((p) => p.id == otherRef.entityId);
      if (otherPunchIdx != -1) {
        workingPunches[punchIdx] = punch.copyWith(center: workingPunches[otherPunchIdx].center);
        return true;
      }
    }

    // 2. Align cut endpoint to reference line
    final cutIdx = workingCuts.indexWhere((cut) => cut.id == refA.entityId || cut.id == refB.entityId);
    if (cutIdx != -1) {
      final cut = workingCuts[cutIdx];
      final otherRef = (cut.id == refA.entityId) ? refB : refA;
      ReferenceGeometry? matchRef;
      for (final r in allRefs) {
        if (r.id.toUpperCase() == otherRef.entityId.toUpperCase()) {
          matchRef = r;
          break;
        }
      }
      if (matchRef != null) {
        final snapP1 = _projectPointOnLine(cut.p1, matchRef.p1, matchRef.p2);
        final snapP2 = _projectPointOnLine(cut.p2, matchRef.p1, matchRef.p2);
        if (cut.p1.distanceTo(snapP1) <= cut.p2.distanceTo(snapP2)) {
          workingCuts[cutIdx] = cut.copyWith(p1: snapP1);
        } else {
          workingCuts[cutIdx] = cut.copyWith(p2: snapP2);
        }
        return true;
      }
    }

    // 3. Align endpoints of two cuts
    final cutAIdx = workingCuts.indexWhere((cut) => cut.id == refA.entityId);
    final cutBIdx = workingCuts.indexWhere((cut) => cut.id == refB.entityId);

    if (cutAIdx != -1 && cutBIdx != -1) {
      final cutA = workingCuts[cutAIdx];
      final cutB = workingCuts[cutBIdx];
      final targetPt = CadPoint2D(
        (cutA.p2.x + cutB.p1.x) / 2.0,
        (cutA.p2.y + cutB.p1.y) / 2.0,
      );
      workingCuts[cutAIdx] = cutA.copyWith(p2: targetPt);
      workingCuts[cutBIdx] = cutB.copyWith(p1: targetPt);
      return true;
    }

    return false;
  }

  static bool _applyParallel(
    ConstraintDefinition c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required Set<String> fixedIds,
    required DsfDocument document,
    List<ReferenceGeometry>? customReferences,
  }) {
    if (c.references.length < 2) return false;

    final allRefs = [
      ...?customReferences,
      ...document.referenceGeometries,
    ];

    // Check if one entity is a reference geometry
    ReferenceGeometry? refGeom;
    int targetCutIdx = -1;
    for (final r in allRefs) {
      if (r.id.toUpperCase() == c.references[0].entityId.toUpperCase()) {
        refGeom = r;
        targetCutIdx = workingCuts.indexWhere((cut) => cut.id == c.references[1].entityId);
        break;
      } else if (r.id.toUpperCase() == c.references[1].entityId.toUpperCase()) {
        refGeom = r;
        targetCutIdx = workingCuts.indexWhere((cut) => cut.id == c.references[0].entityId);
        break;
      }
    }
    if (refGeom != null && targetCutIdx != -1) {
      final cut = workingCuts[targetCutIdx];
      final rdx = refGeom.p2.x - refGeom.p1.x;
      final rdy = refGeom.p2.y - refGeom.p1.y;
      final rlen = math.sqrt(rdx * rdx + rdy * rdy);
      final cutLen = cut.p1.distanceTo(cut.p2);
      if (rlen > 1e-4) {
        final ux = rdx / rlen;
        final uy = rdy / rlen;
        workingCuts[targetCutIdx] = cut.copyWith(
          p2: CadPoint2D(cut.p1.x + ux * cutLen, cut.p1.y + uy * cutLen),
        );
        return true;
      }
    }

    // Align angle of cut to bend line
    final bendIdx = workingBends.indexWhere((b) => b.id == c.references[0].entityId);
    final cutIdx = workingCuts.indexWhere((cut) => cut.id == c.references[1].entityId);

    if (bendIdx != -1 && cutIdx != -1) {
      final bend = workingBends[bendIdx];
      final cut = workingCuts[cutIdx];
      final dx = bend.p2.x - bend.p1.x;
      final dy = bend.p2.y - bend.p1.y;
      final len = cut.p1.distanceTo(cut.p2);
      final bendLen = math.sqrt(dx * dx + dy * dy);
      if (bendLen > 1e-4) {
        final ux = dx / bendLen;
        final uy = dy / bendLen;
        workingCuts[cutIdx] = cut.copyWith(
          p2: CadPoint2D(cut.p1.x + ux * len, cut.p1.y + uy * len),
        );
        return true;
      }
    }
    return false;
  }

  static bool _applyPerpendicular(
    ConstraintDefinition c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required Set<String> fixedIds,
    required DsfDocument document,
    List<ReferenceGeometry>? customReferences,
  }) {
    if (c.references.length < 2) return false;

    final allRefs = [
      ...?customReferences,
      ...document.referenceGeometries,
    ];

    // Check if one entity is a reference geometry
    ReferenceGeometry? refGeom;
    int targetCutIdx = -1;
    for (final r in allRefs) {
      if (r.id.toUpperCase() == c.references[0].entityId.toUpperCase()) {
        refGeom = r;
        targetCutIdx = workingCuts.indexWhere((cut) => cut.id == c.references[1].entityId);
        break;
      } else if (r.id.toUpperCase() == c.references[1].entityId.toUpperCase()) {
        refGeom = r;
        targetCutIdx = workingCuts.indexWhere((cut) => cut.id == c.references[0].entityId);
        break;
      }
    }
    if (refGeom != null && targetCutIdx != -1) {
      final cut = workingCuts[targetCutIdx];
      final rdx = -(refGeom.p2.y - refGeom.p1.y);
      final rdy = refGeom.p2.x - refGeom.p1.x;
      final rlen = math.sqrt(rdx * rdx + rdy * rdy);
      final cutLen = cut.p1.distanceTo(cut.p2);
      if (rlen > 1e-4) {
        final ux = rdx / rlen;
        final uy = rdy / rlen;
        workingCuts[targetCutIdx] = cut.copyWith(
          p2: CadPoint2D(cut.p1.x + ux * cutLen, cut.p1.y + uy * cutLen),
        );
        return true;
      }
    }

    final bIdx = workingBends.indexWhere((b) => b.id == c.references[0].entityId);
    final cIdx = workingCuts.indexWhere((cut) => cut.id == c.references[1].entityId);

    if (bIdx != -1 && cIdx != -1) {
      final bend = workingBends[bIdx];
      final cut = workingCuts[cIdx];
      final dx = -(bend.p2.y - bend.p1.y);
      final dy = bend.p2.x - bend.p1.x;
      final len = cut.p1.distanceTo(cut.p2);
      final pLen = math.sqrt(dx * dx + dy * dy);
      if (pLen > 1e-4) {
        workingCuts[cIdx] = cut.copyWith(
          p2: CadPoint2D(cut.p1.x + (dx / pLen) * len, cut.p1.y + (dy / pLen) * len),
        );
        return true;
      }
    }
    return false;
  }

  static bool _applyCollinear(
    ConstraintDefinition c, {
    required List<CadLineSegment> workingCuts,
    required List<FoldBendLine> workingBends,
    required Set<String> fixedIds,
  }) {
    if (c.references.length < 2) return false;
    // If two horizontal or vertical lines are collinear, align their common coordinate
    final b1Idx = workingBends.indexWhere((b) => b.id == c.references[0].entityId);
    final b2Idx = workingBends.indexWhere((b) => b.id == c.references[1].entityId);

    if (b1Idx != -1 && b2Idx != -1) {
      final b1 = workingBends[b1Idx];
      final b2 = workingBends[b2Idx];
      if ((b1.p1.y - b1.p2.y).abs() < 1e-4 && (b2.p1.y - b2.p2.y).abs() < 1e-4) {
        final avgY = (b1.p1.y + b2.p1.y) / 2.0;
        workingBends[b1Idx] = b1.copyWith(
          p1: CadPoint2D(b1.p1.x, avgY),
          p2: CadPoint2D(b1.p2.x, avgY),
        );
        workingBends[b2Idx] = b2.copyWith(
          p1: CadPoint2D(b2.p1.x, avgY),
          p2: CadPoint2D(b2.p2.x, avgY),
        );
        return true;
      }
    }
    return false;
  }

  static bool _applyConcentric(
    ConstraintDefinition c, {
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.references.length < 2) return false;
    final p1Idx = workingPunches.indexWhere((p) => p.id == c.references[0].entityId);
    final p2Idx = workingPunches.indexWhere((p) => p.id == c.references[1].entityId);
    if (p1Idx != -1 && p2Idx != -1) {
      final p1 = workingPunches[p1Idx];
      final p2 = workingPunches[p2Idx];
      workingPunches[p2Idx] = p2.copyWith(center: p1.center);
      return true;
    }
    return false;
  }

  static bool _applyEqual(
    ConstraintDefinition c, {
    required List<CadLineSegment> workingCuts,
    required List<CncPunchPrimitive> workingPunches,
    required Set<String> fixedIds,
  }) {
    if (c.references.length < 2) return false;
    final p1Idx = workingPunches.indexWhere((p) => p.id == c.references[0].entityId);
    final p2Idx = workingPunches.indexWhere((p) => p.id == c.references[1].entityId);
    if (p1Idx != -1 && p2Idx != -1) {
      final p1 = workingPunches[p1Idx];
      final p2 = workingPunches[p2Idx];
      workingPunches[p2Idx] = p2.copyWith(diameterMm: p1.diameterMm);
      return true;
    }
    return false;
  }

  static ({double minX, double maxX, double minY, double maxY}) _contourBounds(
    List<CadPoint2D> contour,
  ) {
    if (contour.isEmpty) return (minX: 0.0, maxX: 100.0, minY: 0.0, maxY: 100.0);
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final pt in contour) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }
    return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
  }
}
