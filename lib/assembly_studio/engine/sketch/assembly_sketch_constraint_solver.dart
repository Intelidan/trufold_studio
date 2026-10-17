// =============================================================================
// assembly_sketch_constraint_solver.dart
//
// 2D Geometric Constraint & Degree of Freedom (DOF) Solver for 3D Surface &
// Datum Plane Sketches per Autodesk Fusion 360 mechanics.
//
// Solves:
// - Horizontal / Vertical (snaps lines or points to orthogonal axes)
// - Parallel & Perpendicular (aligns or squares line segments)
// - Concentric (locks centers of circles and arcs)
// - Coincident (merges vertex/endpoint coordinates)
// - Equal (synchronizes lengths or radii)
// - Tangent (aligns lines and arc perimeters smoothly)
// - Fixed / Lock (immobilizes entities, reducing remaining DOFs to 0)
// - Live Degree of Freedom (DOF) tracking: Under-constrained (Blue) vs Fully Constrained (Black)
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:trufold_studio/sketch_draft_files/cad_parameter_engine/cad_models.dart';

class SketchConstraintSolverResult {
  final bool isSuccess;
  final int totalDegreesOfFreedom;
  final Map<String, int> entityDegreesOfFreedom;
  final List<CadConstraint> satisfiedConstraints;
  final List<CadConstraint> conflictingConstraints;
  final String statusMessage;

  const SketchConstraintSolverResult({
    required this.isSuccess,
    required this.totalDegreesOfFreedom,
    required this.entityDegreesOfFreedom,
    this.satisfiedConstraints = const [],
    this.conflictingConstraints = const [],
    required this.statusMessage,
  });

  bool get isFullyConstrained => totalDegreesOfFreedom == 0;
}

class AssemblySketchConstraintSolver {
  static const double epsilon = 1e-5;

  /// Calculates the intrinsic degrees of freedom for an unconstrained primitive.
  static int computeInitialDof(CADPrimitiveEntity prim) {
    if (prim.isProjected) {
      return 0;
    } else if (prim is CADLineEntity) {
      return 4; // Start X, Start Y, End X, End Y
    } else if (prim is CADCircleEntity || prim is CADThreePointCircleEntity) {
      return 3; // Center X, Center Y, Radius
    } else if (prim is CADEllipseEntity) {
      return 5; // Center X, Center Y, RadiusX, RadiusY, Rotation
    } else if (prim is CADArcEntity || prim is CADCenterPointArcEntity) {
      return 5; // Center X, Center Y, Radius, Angles
    } else if (prim is CADRegularPolygonEntity) {
      return 4; // Center X, Center Y, Radius, Angle
    } else if (prim is CADSlotEntity) {
      return 5; // StartCenter X, Y, EndCenter X, Y, Diameter
    } else if (prim is CADAlignedRectangleEntity) {
      return 5; // Corner1 X, Y, Corner2 X, Y, Offset
    } else if (prim is CADConicEntity) {
      return 6; // Start X, Y, End X, Y, Apex X, Y
    } else if (prim is CADSplineEntity) {
      return prim.controlPoints.length * 2;
    } else if (prim is CADRectangleEntity || prim is CADCenterRectangleEntity) {
      return 4; // Center/Corner X, Y, Width, Height
    } else if (prim is CADPolylineEntity) {
      return prim.points.length * 2;
    } else if (prim is CADTextEntity) {
      return 3;
    } else {
      return 2;
    }
  }

  /// Solves all active constraints on [plane], adjusts entity positions and dimensions,
  /// and calculates exact Degree of Freedom (DOF) status for every sketch entity.
  static SketchConstraintSolverResult solve(CADSketchPlane plane) {
    final primitives = plane.primitives;
    final constraints = plane.constraints.where((c) => c.isActive).toList();

    final satisfied = <CadConstraint>[];
    final conflicting = <CadConstraint>[];
    final Map<String, int> dofMap = {};

    // 1. Initialize base Degrees of Freedom per entity
    for (final prim in primitives) {
      final baseDof = computeInitialDof(prim);
      dofMap[prim.id] = baseDof;
      prim.isFullyConstrained = (baseDof <= 0);
    }

    // 2. Map entities by ID for fast lookup
    final entityMap = <String, CADPrimitiveEntity>{};
    for (final prim in primitives) {
      entityMap[prim.id] = prim;
    }

    // 3. Process constraints: Fixed constraints first (anchors)
    final fixedConstraints = constraints.where((c) => c.type == CadConstraintType.fixed).toList();
    for (final c in fixedConstraints) {
      for (final id in c.entityIds) {
        final ent = entityMap[id];
        if (ent != null) {
          dofMap[id] = 0;
          ent.isFullyConstrained = true;
        }
      }
      satisfied.add(c);
    }

    // Pre-check for inherently conflicting constraints
    final conflictingSet = <CadConstraint>{};
    for (int i = 0; i < constraints.length; i++) {
      final c1 = constraints[i];
      for (int j = i + 1; j < constraints.length; j++) {
        final c2 = constraints[j];
        final commonEntities = c1.entityIds.toSet().intersection(c2.entityIds.toSet());
        if (commonEntities.isNotEmpty) {
          if ((c1.type == CadConstraintType.horizontal && c2.type == CadConstraintType.vertical) ||
              (c1.type == CadConstraintType.vertical && c2.type == CadConstraintType.horizontal)) {
            conflictingSet.add(c1);
            conflictingSet.add(c2);
          }
          final isDim1 = c1.type == CadConstraintType.distance || c1.type == CadConstraintType.radius || c1.type == CadConstraintType.diameter;
          final isDim2 = c2.type == CadConstraintType.distance || c2.type == CadConstraintType.radius || c2.type == CadConstraintType.diameter;
          if (isDim1 && isDim2 && c1.type == c2.type && c1.parameterValue != null && c2.parameterValue != null) {
            if ((c1.parameterValue! - c2.parameterValue!).abs() > 1e-3) {
              conflictingSet.add(c1);
              conflictingSet.add(c2);
            }
          }
        }
      }
    }

    // 4. Process geometric & dimensional constraints iteratively (relaxation)
    final geometricConstraints = constraints.where((c) => c.type != CadConstraintType.fixed).toList();
    const int maxIterations = 5;
    for (int iter = 0; iter < maxIterations; iter++) {
      for (final c in geometricConstraints) {
        if (conflictingSet.contains(c)) {
          if (iter == 0) conflicting.add(c);
          continue;
        }
        final success = _applySingleConstraint(c, entityMap);
        if (iter == 0) {
          if (success) {
            satisfied.add(c);
            _deductDegreesOfFreedom(c, dofMap);
          } else {
            conflicting.add(c);
          }
        }
      }
    }

    // 5. Finalize Degree of Freedom and constraint status
    int totalRemainingDof = 0;
    for (final prim in primitives) {
      int remaining = dofMap[prim.id] ?? 0;
      if (remaining < 0) remaining = 0;
      dofMap[prim.id] = remaining;
      totalRemainingDof += remaining;

      prim.isFullyConstrained = (remaining == 0);
    }

    final isAllConstrained = primitives.isNotEmpty && totalRemainingDof == 0;
    final statusMsg = primitives.isEmpty
        ? 'Empty sketch plane'
        : isAllConstrained
        ? 'Fully Constrained (0 DOFs) 🔒'
        : 'Under-constrained ($totalRemainingDof DOFs remaining)';

    return SketchConstraintSolverResult(
      isSuccess: conflicting.isEmpty,
      totalDegreesOfFreedom: totalRemainingDof,
      entityDegreesOfFreedom: dofMap,
      satisfiedConstraints: satisfied,
      conflictingConstraints: conflicting,
      statusMessage: statusMsg,
    );
  }

  static bool _applySingleConstraint(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.isEmpty) return false;

    switch (c.type) {
      case CadConstraintType.horizontal:
        return _solveHorizontal(c, entityMap);
      case CadConstraintType.vertical:
        return _solveVertical(c, entityMap);
      case CadConstraintType.parallel:
        return _solveParallel(c, entityMap);
      case CadConstraintType.perpendicular:
        return _solvePerpendicular(c, entityMap);
      case CadConstraintType.concentric:
        return _solveConcentric(c, entityMap);
      case CadConstraintType.coincident:
        return _solveCoincident(c, entityMap);
      case CadConstraintType.equal:
        return _solveEqual(c, entityMap);
      case CadConstraintType.tangent:
        return _solveTangent(c, entityMap);
      case CadConstraintType.fixed:
        return true;
      case CadConstraintType.distance:
      case CadConstraintType.radius:
      case CadConstraintType.diameter:
      case CadConstraintType.angle:
        return _solveDimensional(c, entityMap);
      case CadConstraintType.symmetric:
        return _solveSymmetric(c, entityMap);
      case CadConstraintType.midpoint:
        return _solveMidpoint(c, entityMap);
      case CadConstraintType.normal:
        return _solveNormal(c, entityMap);
      case CadConstraintType.pierce:
        return _solvePierce(c, entityMap);
      case CadConstraintType.curvature:
        return _solveCurvature(c, entityMap);
      default:
        return false;
    }
  }

  static bool _solveHorizontal(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length == 1) {
      final ent = entityMap[c.entityIds[0]];
      if (ent is CADLineEntity) {
        final midY = (ent.start.dy + ent.end.dy) / 2.0;
        ent.start = Offset(ent.start.dx, midY);
        ent.end = Offset(ent.end.dx, midY);
        return true;
      }
    } else if (c.entityIds.length >= 2) {
      final e1 = entityMap[c.entityIds[0]];
      final e2 = entityMap[c.entityIds[1]];
      if (e1 != null && e2 != null) {
        final p1 = _getEntityCenterOrAnchor(e1);
        final p2 = _getEntityCenterOrAnchor(e2);
        final targetY = e1.isFullyConstrained ? p1.dy : (p1.dy + p2.dy) / 2.0;
        _shiftEntityTo(e2, Offset(p2.dx, targetY));
        if (!e1.isFullyConstrained) _shiftEntityTo(e1, Offset(p1.dx, targetY));
        return true;
      }
    }
    return false;
  }

  static bool _solveVertical(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length == 1) {
      final ent = entityMap[c.entityIds[0]];
      if (ent is CADLineEntity) {
        final midX = (ent.start.dx + ent.end.dx) / 2.0;
        ent.start = Offset(midX, ent.start.dy);
        ent.end = Offset(midX, ent.end.dy);
        return true;
      }
    } else if (c.entityIds.length >= 2) {
      final e1 = entityMap[c.entityIds[0]];
      final e2 = entityMap[c.entityIds[1]];
      if (e1 != null && e2 != null) {
        final p1 = _getEntityCenterOrAnchor(e1);
        final p2 = _getEntityCenterOrAnchor(e2);
        final targetX = e1.isFullyConstrained ? p1.dx : (p1.dx + p2.dx) / 2.0;
        _shiftEntityTo(e2, Offset(targetX, p2.dy));
        if (!e1.isFullyConstrained) _shiftEntityTo(e1, Offset(targetX, p1.dy));
        return true;
      }
    }
    return false;
  }

  static bool _solveParallel(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 is CADLineEntity && e2 is CADLineEntity) {
      final d1 = e1.end - e1.start;
      final ang1 = math.atan2(d1.dy, d1.dx);

      final d2 = e2.end - e2.start;
      final len2 = d2.distance;
      final ang2 = math.atan2(d2.dy, d2.dx);

      // Choose parallel direction closest to current orientation
      final diff = (ang2 - ang1).abs();
      final targetAng = (diff > math.pi / 2.0 && diff < 3.0 * math.pi / 2.0) ? ang1 + math.pi : ang1;

      final mid2 = Offset((e2.start.dx + e2.end.dx) / 2.0, (e2.start.dy + e2.end.dy) / 2.0);
      final hVec = Offset(math.cos(targetAng), math.sin(targetAng)) * (len2 / 2.0);
      e2.start = mid2 - hVec;
      e2.end = mid2 + hVec;
      return true;
    }
    return false;
  }

  static bool _solvePerpendicular(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 is CADLineEntity && e2 is CADLineEntity) {
      final d1 = e1.end - e1.start;
      final ang1 = math.atan2(d1.dy, d1.dx);

      final d2 = e2.end - e2.start;
      final len2 = d2.distance;
      final ang2 = math.atan2(d2.dy, d2.dx);

      // Desired angles are ang1 + pi/2 or ang1 - pi/2
      final opt1 = ang1 + math.pi / 2.0;
      final opt2 = ang1 - math.pi / 2.0;
      final diff1 = (math.atan2(math.sin(ang2 - opt1), math.cos(ang2 - opt1))).abs();
      final diff2 = (math.atan2(math.sin(ang2 - opt2), math.cos(ang2 - opt2))).abs();
      final targetAng = diff1 < diff2 ? opt1 : opt2;

      final mid2 = Offset((e2.start.dx + e2.end.dx) / 2.0, (e2.start.dy + e2.end.dy) / 2.0);
      final hVec = Offset(math.cos(targetAng), math.sin(targetAng)) * (len2 / 2.0);
      e2.start = mid2 - hVec;
      e2.end = mid2 + hVec;
      return true;
    }
    return false;
  }

  static bool _solveConcentric(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    Offset? c1;
    if (e1 is CADCircleEntity) c1 = e1.center;
    if (e1 is CADArcEntity) c1 = e1.computeCircumcircle()?.center;
    if (e1 is CADCenterRectangleEntity) c1 = e1.center;

    if (c1 != null) {
      if (e2 is CADCircleEntity) {
        e2.center = c1;
        return true;
      } else if (e2 is CADArcEntity) {
        final geom2 = e2.computeCircumcircle();
        if (geom2 != null) {
          final delta = c1 - geom2.center;
          e2.startPoint = e2.startPoint + delta;
          e2.endPoint = e2.endPoint + delta;
          e2.pointOnArc = e2.pointOnArc + delta;
          return true;
        }
      } else if (e2 is CADCenterRectangleEntity) {
        e2.center = c1;
        return true;
      }
    }
    return false;
  }

  static bool _solveCoincident(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    if (e1 is CADLineEntity && e2 is CADLineEntity) {
      // Find closest endpoints
      final pairs = [
        (e1.start, e2.start, true, true),
        (e1.start, e2.end, true, false),
        (e1.end, e2.start, false, true),
        (e1.end, e2.end, false, false),
      ];
      pairs.sort((a, b) => (a.$1 - a.$2).distance.compareTo((b.$1 - b.$2).distance));
      final best = pairs.first;

      final targetPoint = (e1.isFullyConstrained || !e2.isFullyConstrained)
          ? best.$1
          : Offset((best.$1.dx + best.$2.dx) / 2.0, (best.$1.dy + best.$2.dy) / 2.0);

      if (best.$4) {
        e2.start = targetPoint;
      } else {
        e2.end = targetPoint;
      }
      if (!e1.isFullyConstrained && targetPoint != best.$1) {
        if (best.$3) {
          e1.start = targetPoint;
        } else {
          e1.end = targetPoint;
        }
      }
      return true;
    } else if (e2 is CADLineEntity) {
      final p1 = _getEntityCenterOrAnchor(e1);
      final dStart = (e2.start - p1).distance;
      final dEnd = (e2.end - p1).distance;
      if (dStart < dEnd) {
        e2.start = p1;
      } else {
        e2.end = p1;
      }
      return true;
    }
    return false;
  }

  static bool _solveEqual(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    if (e1 is CADLineEntity && e2 is CADLineEntity) {
      final len1 = (e1.end - e1.start).distance;
      final d2 = e2.end - e2.start;
      final len2 = d2.distance;
      if (len2 > 1e-4) {
        final mid2 = Offset((e2.start.dx + e2.end.dx) / 2.0, (e2.start.dy + e2.end.dy) / 2.0);
        final unit = d2 / len2;
        e2.start = mid2 - unit * (len1 / 2.0);
        e2.end = mid2 + unit * (len1 / 2.0);
        return true;
      }
    } else if (e1 is CADCircleEntity && e2 is CADCircleEntity) {
      e2.radius = e1.radius;
      return true;
    } else if (e1 is CADRectangleEntity && e2 is CADRectangleEntity) {
      e2.width = e1.width;
      e2.height = e1.height;
      return true;
    } else if (e1 is CADCenterRectangleEntity && e2 is CADCenterRectangleEntity) {
      e2.width = e1.width;
      e2.height = e1.height;
      return true;
    }
    return false;
  }

  static bool _solveTangent(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    CADLineEntity? line;
    CADCircleEntity? circle;
    if (e1 is CADLineEntity && e2 is CADCircleEntity) {
      line = e1;
      circle = e2;
    } else if (e1 is CADCircleEntity && e2 is CADLineEntity) {
      circle = e1;
      line = e2;
    }

    if (line != null && circle != null) {
      final lVec = line.end - line.start;
      final lLen = lVec.distance;
      if (lLen < 1e-4) return false;
      final normal = Offset(-lVec.dy / lLen, lVec.dx / lLen);

      // Distance from center to line
      final dCenter = circle.center - line.start;
      final dist = (dCenter.dx * normal.dx + dCenter.dy * normal.dy).abs();
      final sign = (dCenter.dx * normal.dx + dCenter.dy * normal.dy) >= 0 ? 1.0 : -1.0;
      final diff = circle.radius - dist;

      if (!line.isFullyConstrained) {
        // Shift line towards circle perimeter
        final shift = normal * (-sign * diff);
        line.start = line.start + shift;
        line.end = line.end + shift;
      } else if (!circle.isFullyConstrained) {
        // Shift circle center to contact line
        circle.center = circle.center + (normal * (sign * diff));
      }
      return true;
    }
    return false;
  }

  static bool _solveDimensional(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    final val = c.parameterValue;
    if (val == null || val <= 0) return false;
    if (c.entityIds.isEmpty) return false;

    final rawId0 = c.entityIds[0];
    final baseId0 = rawId0.split(':').first;
    final subKey0 = rawId0.contains(':') ? rawId0.split(':').last : '';
    final ent = entityMap[baseId0];
    if (ent == null) return false;

    // 1. ANGULAR DIMENSION BETWEEN 2 LINES (e.g. 27° in image_31d02d.png)
    if (c.type == CadConstraintType.angle && c.entityIds.length >= 2) {
      final ent2 = entityMap[c.entityIds[1].split(':').first];
      if (ent is CADLineEntity && ent2 is CADLineEntity) {
        final d1 = ent.end - ent.start;
        final d2 = ent2.end - ent2.start;
        final len1 = d1.distance;
        final len2 = d2.distance;
        if (len1 < 1e-4 || len2 < 1e-4) return false;

        final a1 = math.atan2(d1.dy, d1.dx);
        final a2 = math.atan2(d2.dy, d2.dx);
        double diff = a2 - a1;
        while (diff <= -math.pi) diff += 2.0 * math.pi;
        while (diff > math.pi) diff -= 2.0 * math.pi;
        final sign = diff >= 0 ? 1.0 : -1.0;
        final targetA2 = a1 + sign * (val * math.pi / 180.0);

        Offset pivot = ent2.start;
        bool pivotIsStart = true;
        if ((ent2.end - ent.start).distance < 1.0 || (ent2.end - ent.end).distance < 1.0) {
          pivot = ent2.end;
          pivotIsStart = false;
        }
        final dir2 = Offset(math.cos(targetA2), math.sin(targetA2));
        if (pivotIsStart) {
          ent2.end = pivot + dir2 * len2;
        } else {
          ent2.start = pivot - dir2 * len2;
        }
        return true;
      }
      return false;
    }

    // 2. TWO-ENTITY LINEAR DISTANCE (Point/Circle-to-Line, Line-to-Line, Center-to-Center)
    if (c.type == CadConstraintType.distance && c.entityIds.length >= 2) {
      final ent2 = entityMap[c.entityIds[1].split(':').first];
      if (ent2 == null) return false;

      if (ent is CADLineEntity && ent2 is! CADLineEntity) {
        final lVec = ent.end - ent.start;
        final lLen = lVec.distance;
        if (lLen < 1e-4) return false;
        final unitN = Offset(-lVec.dy / lLen, lVec.dx / lLen);
        final p2 = _getEntityCenterOrAnchor(ent2);
        final signedDist = (p2.dx - ent.start.dx) * unitN.dx + (p2.dy - ent.start.dy) * unitN.dy;
        final sign = signedDist >= 0 ? 1.0 : -1.0;
        final delta = unitN * (sign * val - signedDist);
        _shiftEntityTo(ent2, p2 + delta);
        return true;
      } else if (ent2 is CADLineEntity && ent is! CADLineEntity) {
        final lVec = ent2.end - ent2.start;
        final lLen = lVec.distance;
        if (lLen < 1e-4) return false;
        final unitN = Offset(-lVec.dy / lLen, lVec.dx / lLen);
        final p1 = _getEntityCenterOrAnchor(ent);
        final signedDist = (p1.dx - ent2.start.dx) * unitN.dx + (p1.dy - ent2.start.dy) * unitN.dy;
        final sign = signedDist >= 0 ? 1.0 : -1.0;
        final delta = unitN * (sign * val - signedDist);
        _shiftEntityTo(ent, p1 + delta);
        return true;
      } else if (ent is CADLineEntity && ent2 is CADLineEntity) {
        final lVec = ent.end - ent.start;
        final lLen = lVec.distance;
        if (lLen < 1e-4) return false;
        final unitN = Offset(-lVec.dy / lLen, lVec.dx / lLen);
        final mid2 = (ent2.start + ent2.end) * 0.5;
        final signedDist = (mid2.dx - ent.start.dx) * unitN.dx + (mid2.dy - ent.start.dy) * unitN.dy;
        final sign = signedDist >= 0 ? 1.0 : -1.0;
        final shift = unitN * (sign * val - signedDist);
        ent2.start = ent2.start + shift;
        ent2.end = ent2.end + shift;
        return true;
      } else {
        final p1 = _getEntityCenterOrAnchor(ent);
        final p2 = _getEntityCenterOrAnchor(ent2);
        final d = p2 - p1;
        final len = d.distance;
        final dir = len > 1e-4 ? d / len : const Offset(1.0, 0.0);
        _shiftEntityTo(ent2, p1 + dir * val);
        return true;
      }
    }

    // 3. SINGLE-ENTITY DIMENSIONS (Radius, Diameter, Length, Width/Height)
    if (c.type == CadConstraintType.radius) {
      if (ent is CADCircleEntity) {
        ent.radius = val;
        return true;
      } else if (ent is CADCenterPointArcEntity) {
        ent.radius = val;
        return true;
      } else if (ent is CADRegularPolygonEntity) {
        ent.radius = val;
        return true;
      } else if (ent is CADArcEntity) {
        final chordVec = ent.endPoint - ent.startPoint;
        final chordLen = chordVec.distance;
        if (chordLen > 1e-4) {
          final clampedR = math.max(val, chordLen / 2.0);
          final mid = (ent.startPoint + ent.endPoint) * 0.5;
          final perp = Offset(-chordVec.dy / chordLen, chordVec.dx / chordLen);
          final currentSide = (ent.pointOnArc.dx - mid.dx) * perp.dx + (ent.pointOnArc.dy - mid.dy) * perp.dy;
          final sign = currentSide >= 0 ? 1.0 : -1.0;
          final hDist = math.sqrt(math.max(0.0, clampedR * clampedR - (chordLen / 2.0) * (chordLen / 2.0)));
          final sagitta = clampedR - hDist;
          ent.pointOnArc = mid + perp * (sign * (sagitta > 1e-4 ? sagitta : clampedR));
        }
        return true;
      }
    } else if (c.type == CadConstraintType.diameter) {
      if (ent is CADCircleEntity) {
        ent.radius = val / 2.0;
        return true;
      } else if (ent is CADSlotEntity) {
        ent.diameter = val;
        return true;
      }
    } else if (c.type == CadConstraintType.distance) {
      if (ent is CADLineEntity) {
        final d = ent.end - ent.start;
        final currLen = d.distance;
        if (currLen > 1e-4) {
          final unit = d / currLen;
          final mid = (ent.start + ent.end) * 0.5;
          ent.start = mid - unit * (val / 2.0);
          ent.end = mid + unit * (val / 2.0);
          return true;
        }
      } else if (ent is CADRectangleEntity) {
        if (subKey0 == 'h') {
          ent.height = val;
        } else {
          ent.width = val;
        }
        return true;
      } else if (ent is CADCenterRectangleEntity) {
        if (subKey0 == 'h') {
          ent.height = val;
        } else {
          ent.width = val;
        }
        return true;
      } else if (ent is CADSlotEntity) {
        final d = ent.endCenter - ent.startCenter;
        final len = d.distance;
        final unit = len > 1e-4 ? d / len : const Offset(1.0, 0.0);
        final mid = (ent.startCenter + ent.endCenter) * 0.5;
        ent.startCenter = mid - unit * (val / 2.0);
        ent.endCenter = mid + unit * (val / 2.0);
        return true;
      }
    }
    return false;
  }

  static void _deductDegreesOfFreedom(CadConstraint c, Map<String, int> dofMap) {
    switch (c.type) {
      case CadConstraintType.horizontal:
      case CadConstraintType.vertical:
      case CadConstraintType.parallel:
      case CadConstraintType.perpendicular:
      case CadConstraintType.equal:
      case CadConstraintType.tangent:
      case CadConstraintType.distance:
      case CadConstraintType.radius:
      case CadConstraintType.diameter:
        for (final id in c.entityIds) {
          if (dofMap.containsKey(id)) {
            dofMap[id] = math.max(0, dofMap[id]! - 1);
          }
        }
        break;
      case CadConstraintType.concentric:
      case CadConstraintType.coincident:
      case CadConstraintType.symmetric:
      case CadConstraintType.midpoint:
      case CadConstraintType.pierce:
        for (final id in c.entityIds) {
          if (dofMap.containsKey(id)) {
            dofMap[id] = math.max(0, dofMap[id]! - 2);
          }
        }
        break;
      case CadConstraintType.fixed:
        for (final id in c.entityIds) {
          dofMap[id] = 0;
        }
        break;
      case CadConstraintType.normal:
      case CadConstraintType.curvature:
        for (final id in c.entityIds) {
          if (dofMap.containsKey(id)) {
            dofMap[id] = math.max(0, dofMap[id]! - 1);
          }
        }
        break;
      default:
        break;
    }
  }

  static Offset _getEntityCenterOrAnchor(CADPrimitiveEntity e) {
    if (e is CADLineEntity) {
      return Offset((e.start.dx + e.end.dx) / 2.0, (e.start.dy + e.end.dy) / 2.0);
    } else if (e is CADCircleEntity) {
      return e.center;
    } else if (e is CADEllipseEntity) {
      return e.center;
    } else if (e is CADCenterPointArcEntity) {
      return e.center;
    } else if (e is CADRegularPolygonEntity) {
      return e.center;
    } else if (e is CADSlotEntity) {
      return (e.startCenter + e.endCenter) * 0.5;
    } else if (e is CADAlignedRectangleEntity) {
      final c = e.corners;
      return (c[0] + c[2]) * 0.5;
    } else if (e is CADConicEntity) {
      return e.apexControlPoint;
    } else if (e is CADSplineEntity) {
      return e.controlPoints.isNotEmpty ? e.controlPoints.first : Offset.zero;
    } else if (e is CADTextEntity) {
      return e.origin;
    } else if (e is CADRectangleEntity) {
      return Offset(e.startPoint.dx + e.width / 2.0, e.startPoint.dy + e.height / 2.0);
    } else if (e is CADCenterRectangleEntity) {
      return e.center;
    } else if (e is CADArcEntity) {
      return e.computeCircumcircle()?.center ?? e.startPoint;
    } else if (e is CADPointEntity) {
      return e.position;
    }
    return Offset.zero;
  }

  static void _shiftEntityTo(CADPrimitiveEntity e, Offset newAnchor) {
    final curr = _getEntityCenterOrAnchor(e);
    final delta = newAnchor - curr;
    if (e is CADLineEntity) {
      e.start = e.start + delta;
      e.end = e.end + delta;
    } else if (e is CADThreePointCircleEntity) {
      e.p1 = e.p1 + delta;
      e.p2 = e.p2 + delta;
      e.p3 = e.p3 + delta;
      e.recomputeFromThreePoints();
    } else if (e is CADCircleEntity) {
      e.center = newAnchor;
    } else if (e is CADEllipseEntity) {
      e.center = newAnchor;
    } else if (e is CADCenterPointArcEntity) {
      e.center = newAnchor;
    } else if (e is CADRegularPolygonEntity) {
      e.center = newAnchor;
    } else if (e is CADSlotEntity) {
      e.startCenter = e.startCenter + delta;
      e.endCenter = e.endCenter + delta;
    } else if (e is CADAlignedRectangleEntity) {
      e.corner1 = e.corner1 + delta;
      e.corner2 = e.corner2 + delta;
    } else if (e is CADConicEntity) {
      e.startPoint = e.startPoint + delta;
      e.endPoint = e.endPoint + delta;
      e.apexControlPoint = e.apexControlPoint + delta;
    } else if (e is CADSplineEntity) {
      for (int i = 0; i < e.controlPoints.length; i++) {
        e.controlPoints[i] = e.controlPoints[i] + delta;
      }
    } else if (e is CADTextEntity) {
      e.origin = newAnchor;
    } else if (e is CADRectangleEntity) {
      e.startPoint = e.startPoint + delta;
    } else if (e is CADCenterRectangleEntity) {
      e.center = newAnchor;
    } else if (e is CADArcEntity) {
      e.startPoint = e.startPoint + delta;
      e.endPoint = e.endPoint + delta;
      e.pointOnArc = e.pointOnArc + delta;
    } else if (e is CADPointEntity) {
      e.position = newAnchor;
    }
  }

  /// Solves Onshape Symmetric Constraint (Shift+Q — onshape.pdf p. 41):
  /// Enforces that entityIds[0] and entityIds[1] are mirrored across axis line entityIds[2] (or Y-axis if 2 entities).
  static bool _solveSymmetric(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    // Axis line: either 3rd entity if it is a CADLineEntity, or the sketch Y-axis (x = 0)
    Offset axisA = const Offset(0.0, -100.0);
    Offset axisB = const Offset(0.0, 100.0);
    if (c.entityIds.length >= 3 && entityMap[c.entityIds[2]] is CADLineEntity) {
      final axisLine = entityMap[c.entityIds[2]] as CADLineEntity;
      axisA = axisLine.start;
      axisB = axisLine.end;
    }

    final ab = axisB - axisA;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return false;

    Offset reflect(Offset p) {
      final ap = p - axisA;
      final t = (ap.dx * ab.dx + ap.dy * ab.dy) / lenSq;
      final foot = axisA + ab * t;
      return foot * 2.0 - p;
    }

    final p1 = _getEntityCenterOrAnchor(e1);
    _shiftEntityTo(e2, reflect(p1));
    if (e1 is CADCircleEntity && e2 is CADCircleEntity) {
      e2.radius = e1.radius;
    }
    return true;
  }

  /// Solves Onshape Midpoint Constraint (Shift+M):
  /// Locks a point/circle center to the exact midpoint of a line segment.
  static bool _solveMidpoint(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    final CADLineEntity? line = e1 is CADLineEntity ? e1 : (e2 is CADLineEntity ? e2 : null);
    final CADPrimitiveEntity other = (line == e1) ? e2 : e1;
    if (line == null) return false;

    final mid = Offset((line.start.dx + line.end.dx) * 0.5, (line.start.dy + line.end.dy) * 0.5);
    _shiftEntityTo(other, mid);
    return true;
  }

  /// Solves Onshape Normal Constraint (Shift+K):
  /// Forces a line and a circle/arc perimeter to intersect at 90° (so the line passes directly through the circle/arc center).
  static bool _solveNormal(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    final CADLineEntity? line = e1 is CADLineEntity ? e1 : (e2 is CADLineEntity ? e2 : null);
    final CADPrimitiveEntity curve = (line == e1) ? e2 : e1;
    if (line == null) return false;

    final center = _getEntityCenterOrAnchor(curve);
    final len = (line.end - line.start).distance;
    if (len < 1e-4) return false;
    final dir = (line.end - center);
    final dirLen = dir.distance;
    final unit = dirLen > 1e-4 ? dir / dirLen : const Offset(1.0, 0.0);
    line.start = center;
    line.end = center + unit * len;
    return true;
  }

  /// Solves Onshape Pierce Constraint (Shift+G):
  /// Locks a 2D sketch entity to a projected 3D pierce point (or origin if 1 entity selected).
  static bool _solvePierce(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.isEmpty) return false;
    final e1 = entityMap[c.entityIds[0]];
    if (e1 == null) return false;
    final targetPt = c.entityIds.length >= 2 && entityMap[c.entityIds[1]] != null
        ? _getEntityCenterOrAnchor(entityMap[c.entityIds[1]]!)
        : Offset.zero;
    _shiftEntityTo(e1, targetPt);
    return true;
  }

  /// Solves Onshape Curvature Continuity Constraint (Shift+U):
  /// Aligns endpoints and matches tangent/curvature vectors at the junction.
  static bool _solveCurvature(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    if (e1 is CADSplineEntity && e2 is CADSplineEntity && e1.controlPoints.length >= 2 && e2.controlPoints.length >= 2) {
      // Snap start of e2 to end of e1 and align C1/G2 tangent control vector
      final junction = e1.controlPoints.last;
      final tangentVec = e1.controlPoints.last - e1.controlPoints[e1.controlPoints.length - 2];
      e2.controlPoints[0] = junction;
      e2.controlPoints[1] = junction + tangentVec;
      return true;
    }
    if (_solveCoincident(c, entityMap)) return true;
    // Fallback for arcs/conics: align anchors
    final p1 = _getEntityCenterOrAnchor(e1);
    _shiftEntityTo(e2, p1);
    return true;
  }
}
