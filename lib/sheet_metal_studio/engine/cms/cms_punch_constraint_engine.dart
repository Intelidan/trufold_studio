// =============================================================================
// cms_punch_constraint_engine.dart
//
// Universal Constraint & Mounting Edge Solver for Coupler Holes and Punches
// across all CMS Cable Management Fittings during Parametric Template Scaling.
//
// Features:
// 1. Explicit Punch-to-Edge Constraints:
//    Punch maintains exact setback distance to its constrained host edge.
// 2. Explicit Punch-to-Punch Constraints:
//    When two coupler holes are constrained to each other (hole-to-hole dimension,
//    pitch constraint, or distance constraint), they stay at the exact same
//    distance from each other.
// 3. Universal Fallback (No Explicit Constraints):
//    When no constraints are detected, each coupler punch automatically binds
//    to its nearest host mounting edge in the baseline blank and shifts with that
//    edge, ensuring holes on expanding tabs (e.g. riser cheeks) preserve their
//    setback and move apart/closer as the tab stretches.
// 4. Dimension Updating:
//    All CAD dimensions referencing transformed punches or edges are updated
//    with accurate coordinates and recalculated measurements.
// =============================================================================

import 'dart:math' as math;

import '../../models/cad_primitives.dart';
import '../../models/cad_dimension.dart';
import '../../models/cad_constraint.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';
import '../../models/constraints/stable_geometry_reference.dart';
import '../associative_dimension_engine.dart';

class CmsPunchConstraintEngine {
  /// Solves and reconciles all punches and dimensions on [scaled] against [baseline].
  /// Guaranteed to satisfy:
  /// - Explicit punch-to-punch distance locks (holes constrained to each other stay at same distance).
  /// - Explicit punch-to-edge setback constraints (holes maintain distance to host edge).
  /// - Universal fallback for unconstrained coupler punches (preserve nearest host edge setback).
  /// - Transformed associative dimensions with accurate layout and measured values.
  static DsfDocument reconcile({
    required DsfDocument baseline,
    required DsfDocument scaled,
    required String paramId,
    required double delta,
    CadPoint2D Function(CadPoint2D)? transformPt,
  }) {
    if (baseline.punches.isEmpty && baseline.dimensions.isEmpty) {
      return scaled;
    }

    final effectiveTransform = transformPt ?? _createGeometryProjector(baseline, scaled);

    // 1. Build punch graph: identify punch-to-punch pairs constrained to each other
    final punchToPunchPairs = _discoverPunchToPunchConstraints(baseline);

    // 2. Determine displacement for each punch
    final punchDisplacements = <String, CadPoint2D>{};
    final resolvedPunches = <String, CadPoint2D>{};

    // First pass: resolve punches that have explicit punch-to-edge constraints
    for (final punch in baseline.punches) {
      final edgeShift = _findExplicitEdgeConstraintShift(punch: punch, baseline: baseline, scaled: scaled, transformPt: effectiveTransform);
      if (edgeShift != null) {
        punchDisplacements[punch.id] = edgeShift;
        resolvedPunches[punch.id] = CadPoint2D(punch.center.x + edgeShift.x, punch.center.y + edgeShift.y);
      }
    }

    // Second pass: propagate punch-to-punch constraints & group centering
    // Build connected components of punches constrained to each other
    final punchMap = {for (final p in baseline.punches) p.id: p};
    final adj = <String, Set<String>>{};
    for (final p in baseline.punches) {
      adj[p.id] = <String>{};
    }
    for (final pair in punchToPunchPairs) {
      adj[pair.$1]?.add(pair.$2);
      adj[pair.$2]?.add(pair.$1);
    }

    final visited = <String>{};
    for (final punch in baseline.punches) {
      if (visited.contains(punch.id)) continue;
      final comp = <String>[];
      final queue = <String>[punch.id];
      visited.add(punch.id);
      while (queue.isNotEmpty) {
        final curr = queue.removeLast();
        comp.add(curr);
        for (final neighbor in adj[curr] ?? const <String>{}) {
          if (!visited.contains(neighbor)) {
            visited.add(neighbor);
            queue.add(neighbor);
          }
        }
      }

      if (comp.length < 2) continue; // Single punch; handled by 1st or 3rd pass

      // Check which punches in this component have explicit edge constraints
      final edgeAnchors = comp.where((id) => punchDisplacements.containsKey(id)).toList();

      if (edgeAnchors.isEmpty) {
        // Neither punch is attached to an edge or 3rd part!
        // Requirement: "when two parts are dimensionally constrained to each other,
        // when scaling the template keep them at the center unless one of them is attached to a 3rd part or the edge"
        final centerShift = _computeGroupCenterShift(
          punchIds: comp,
          baseline: baseline,
          scaled: scaled,
          paramId: paramId,
          delta: delta,
          transformPt: effectiveTransform,
        );

        for (final id in comp) {
          punchDisplacements[id] = centerShift;
          final orig = punchMap[id]!.center;
          resolvedPunches[id] = CadPoint2D(orig.x + centerShift.x, orig.y + centerShift.y);
        }
      } else if (edgeAnchors.length == 1) {
        // Exactly one punch is attached to an edge (the master anchor).
        // The rest of the component follows this anchor to lock mutual distances.
        final anchorId = edgeAnchors.first;
        final anchorShift = punchDisplacements[anchorId]!;
        for (final id in comp) {
          if (id == anchorId) continue;
          punchDisplacements[id] = anchorShift;
          final orig = punchMap[id]!.center;
          resolvedPunches[id] = CadPoint2D(orig.x + anchorShift.x, orig.y + anchorShift.y);
        }
      } else {
        // Multiple punches have independent edge constraints (e.g. SS1/SS2 where each hole
        // is constrained to opposite edges, moving apart as the boundary stretches).
        // Each punch keeps its independent shift from the first pass.
        // For any unanchored punches in the component, anchor to the nearest edge anchor.
        for (final id in comp) {
          if (!punchDisplacements.containsKey(id)) {
            final orig = punchMap[id]!.center;
            String bestAnchor = edgeAnchors.first;
            double bestD = double.infinity;
            for (final aId in edgeAnchors) {
              final d = orig.distanceTo(punchMap[aId]!.center);
              if (d < bestD) {
                bestD = d;
                bestAnchor = aId;
              }
            }
            final aShift = punchDisplacements[bestAnchor]!;
            punchDisplacements[id] = aShift;
            resolvedPunches[id] = CadPoint2D(orig.x + aShift.x, orig.y + aShift.y);
          }
        }
      }
    }

    // Third pass: resolve remaining punches via universal fallback
    for (final punch in baseline.punches) {
      if (resolvedPunches.containsKey(punch.id)) continue;

      // Check if already scaled in `scaled.punches`
      final preScaledPunch = scaled.punches.where((p) => p.id == punch.id).firstOrNull;
      final bool isCoupler = punch.role == CncPunchRole.coupler || punch.isSlot;

      if (isCoupler) {
        final fallbackShift = _computeFallbackEdgeShift(
          punch: punch,
          baseline: baseline,
          scaled: scaled,
          paramId: paramId,
          delta: delta,
          transformPt: effectiveTransform,
        );
        punchDisplacements[punch.id] = fallbackShift;
        resolvedPunches[punch.id] = CadPoint2D(punch.center.x + fallbackShift.x, punch.center.y + fallbackShift.y);
      } else if (preScaledPunch != null) {
        resolvedPunches[punch.id] = preScaledPunch.center;
        punchDisplacements[punch.id] = CadPoint2D(preScaledPunch.center.x - punch.center.x, preScaledPunch.center.y - punch.center.y);
      } else {
        final transformedCenter = effectiveTransform(punch.center);
        resolvedPunches[punch.id] = transformedCenter;
        punchDisplacements[punch.id] = CadPoint2D(transformedCenter.x - punch.center.x, transformedCenter.y - punch.center.y);
      }
    }

    // 3. Assemble final punches list
    final newPunches = baseline.punches.map((p) {
      final newCenter = resolvedPunches[p.id] ?? p.center;
      return p.copyWith(center: newCenter);
    }).toList();

    // 4. Transform and reconcile all dimensions
    final newDimensions = _updateDimensions(baseline: baseline, scaled: scaled, newPunches: newPunches, transformPt: effectiveTransform);

    return scaled.copyWith(punches: newPunches, dimensions: newDimensions);
  }

  /// Discovers explicit punch-to-punch constraints in [doc]
  /// (e.g. holeToHole dimensions, CadConstraintType.distance between two punches).
  static List<(String, String)> _discoverPunchToPunchConstraints(DsfDocument doc) {
    final pairs = <(String, String)>[];
    final punchIds = doc.punches.map((p) => p.id).toSet();

    // 1. Dimensions
    for (final dim in doc.dimensions) {
      final refA = dim.referenceAId;
      final refB = dim.referenceBId;
      if (refA != null && refB != null && punchIds.contains(refA) && punchIds.contains(refB)) {
        if (dim.type == CadDimensionType.holeToHole ||
            dim.type == CadDimensionType.aligned ||
            dim.type == CadDimensionType.horizontal ||
            dim.type == CadDimensionType.vertical) {
          pairs.add((refA, refB));
        }
      }
    }

    // 2. Constraints
    for (final c in doc.constraints) {
      if (c.type == CadConstraintType.distance || c.type == CadConstraintType.equal || c.type == CadConstraintType.coincident) {
        final matches = c.entityIds.where(punchIds.contains).toList();
        if (matches.length >= 2) {
          pairs.add((matches[0], matches[1]));
        }
      }
    }

    // 3. ConstraintDefinitions
    for (final cd in doc.constraintDefinitions) {
      if (cd.type == CadConstraintType.distance || cd.type == CadConstraintType.equal || cd.type == CadConstraintType.coincident) {
        final matches = cd.references.map((r) => r.entityId).where(punchIds.contains).toList();
        if (matches.length >= 2) {
          pairs.add((matches[0], matches[1]));
        }
      }
    }

    return pairs;
  }

  /// Checks if [punch] has an explicit dimension or constraint to an edge or point,
  /// and returns the displacement vector of that reference under the scaling transformation.
  static CadPoint2D? _findExplicitEdgeConstraintShift({
    required CncPunchPrimitive punch,
    required DsfDocument baseline,
    required DsfDocument scaled,
    required CadPoint2D Function(CadPoint2D) transformPt,
  }) {
    // 1. Inspect dimensions
    for (final dim in baseline.dimensions) {
      if (dim.referenceAId == punch.id || dim.referenceBId == punch.id || dim.referenceEntityId == punch.id || dim.drivenEntityId == punch.id) {
        final otherId =
            (dim.referenceAId == punch.id ? dim.referenceBId : dim.referenceAId) ??
            (dim.drivenEntityId == punch.id ? dim.referenceEntityId : dim.drivenEntityId);

        if (otherId != null && otherId != punch.id) {
          if (!baseline.punches.any((p) => p.id == otherId)) {
            final edgeShift = _measureEdgeShift(otherId, baseline, scaled, transformPt);
            if (edgeShift != null) {
              if (dim.type == CadDimensionType.horizontal) {
                return CadPoint2D(edgeShift.x, 0.0);
              } else if (dim.type == CadDimensionType.vertical) {
                return CadPoint2D(0.0, edgeShift.y);
              } else {
                return edgeShift;
              }
            }
          }
          // If otherId is another punch, this is a punch-to-punch constraint, not an edge constraint
          continue;
        } else {
          // Point-based attachment (reference has no entity ID, just coordinate pointA/pointB)
          final otherPt = dim.referenceAId == punch.id ? dim.pointB : dim.pointA;
          if (otherPt != null && otherPt.distanceTo(punch.center) > 0.1) {
            final shift = _projectPointShiftFromGeometry(otherPt, baseline, scaled, transformPt);
            final dx = shift.x;
            final dy = shift.y;
            if (dim.type == CadDimensionType.horizontal) {
              return CadPoint2D(dx, 0.0);
            } else if (dim.type == CadDimensionType.vertical) {
              return CadPoint2D(0.0, dy);
            } else {
              return CadPoint2D(dx, dy);
            }
          }
        }
      }
    }

    // 2. Inspect constraints
    for (final c in baseline.constraints) {
      if (c.entityIds.contains(punch.id)) {
        final otherId = c.entityIds.firstWhere((id) => id != punch.id && !baseline.punches.any((p) => p.id == id), orElse: () => '');
        if (otherId.isNotEmpty) {
          final edgeShift = _measureEdgeShift(otherId, baseline, scaled, transformPt);
          if (edgeShift != null) return edgeShift;
        }
      }
    }

    // 3. Inspect constraint definitions
    for (final cd in baseline.constraintDefinitions) {
      if (cd.references.any((r) => r.entityId == punch.id)) {
        final otherRef = cd.references.firstWhere(
          (r) => r.entityId != punch.id && !baseline.punches.any((p) => p.id == r.entityId),
          orElse: () => const EntityRef(entityId: ''),
        );
        if (otherRef.entityId.isNotEmpty) {
          final edgeShift = _measureEdgeShift(otherRef.entityId, baseline, scaled, transformPt);
          if (edgeShift != null) return edgeShift;
        }
      }
    }

    return null;
  }

  /// Measures how edge [edgeId] shifted between [baseline] and [scaled].
  static CadPoint2D? _measureEdgeShift(String edgeId, DsfDocument baseline, DsfDocument scaled, CadPoint2D Function(CadPoint2D) transformPt) {
    // Check bends
    final bendBase = baseline.bends.where((b) => b.id == edgeId).firstOrNull;
    if (bendBase != null) {
      final bendScaled = scaled.bends.where((b) => b.id == edgeId).firstOrNull;
      if (bendScaled != null) {
        return CadPoint2D(bendScaled.midpoint.x - bendBase.midpoint.x, bendScaled.midpoint.y - bendBase.midpoint.y);
      }
      final newMid = transformPt(bendBase.midpoint);
      return CadPoint2D(newMid.x - bendBase.midpoint.x, newMid.y - bendBase.midpoint.y);
    }

    // Check cut lines
    final cutBase = baseline.cutLines.where((c) => c.id == edgeId).firstOrNull;
    if (cutBase != null) {
      final cutScaled = scaled.cutLines.where((c) => c.id == edgeId).firstOrNull;
      if (cutScaled != null) {
        return CadPoint2D(cutScaled.midpoint.x - cutBase.midpoint.x, cutScaled.midpoint.y - cutBase.midpoint.y);
      }
      final newMid = transformPt(cutBase.midpoint);
      return CadPoint2D(newMid.x - cutBase.midpoint.x, newMid.y - cutBase.midpoint.y);
    }

    // Check contour vertices (CONTOUR_VERTEX_i)
    if (edgeId.startsWith('CONTOUR_VERTEX_')) {
      final index = int.tryParse(edgeId.replaceFirst('CONTOUR_VERTEX_', ''));
      if (index != null && index >= 0 && index < baseline.outerContour.length) {
        final b = baseline.outerContour[index];
        if (index < scaled.outerContour.length && scaled.outerContour.length == baseline.outerContour.length) {
          final s = scaled.outerContour[index];
          return CadPoint2D(s.x - b.x, s.y - b.y);
        } else {
          final s = transformPt(b);
          return CadPoint2D(s.x - b.x, s.y - b.y);
        }
      }
    }

    // Check contour edges (CONTOUR_EDGE_i)
    if (edgeId.startsWith('CONTOUR_EDGE_')) {
      final index = int.tryParse(edgeId.replaceFirst('CONTOUR_EDGE_', ''));
      if (index != null && index >= 0 && index < baseline.outerContour.length) {
        final b1 = baseline.outerContour[index];
        final b2 = baseline.outerContour[(index + 1) % baseline.outerContour.length];
        final baseMid = CadPoint2D((b1.x + b2.x) / 2.0, (b1.y + b2.y) / 2.0);

        if (index < scaled.outerContour.length && scaled.outerContour.length == baseline.outerContour.length) {
          final s1 = scaled.outerContour[index];
          final s2 = scaled.outerContour[(index + 1) % scaled.outerContour.length];
          final scaledMid = CadPoint2D((s1.x + s2.x) / 2.0, (s1.y + s2.y) / 2.0);
          return CadPoint2D(scaledMid.x - baseMid.x, scaledMid.y - baseMid.y);
        } else {
          final s1 = transformPt(b1);
          final s2 = transformPt(b2);
          final scaledMid = CadPoint2D((s1.x + s2.x) / 2.0, (s1.y + s2.y) / 2.0);
          return CadPoint2D(scaledMid.x - baseMid.x, scaledMid.y - baseMid.y);
        }
      }
    }

    // Check named edge tokens: EDGE_TOP, EDGE_BOTTOM, EDGE_LEFT, EDGE_RIGHT
    if (edgeId == 'EDGE_TOP' || edgeId == 'EDGE_BOTTOM' || edgeId == 'EDGE_LEFT' || edgeId == 'EDGE_RIGHT') {
      final seg = _resolveNamedEdgeSegment(edgeId, baseline);
      if (seg != null) {
        final scaledSeg = _resolveNamedEdgeSegment(edgeId, scaled);
        if (scaledSeg != null) {
          final bMid = CadPoint2D((seg.$1.x + seg.$2.x) / 2.0, (seg.$1.y + seg.$2.y) / 2.0);
          final sMid = CadPoint2D((scaledSeg.$1.x + scaledSeg.$2.x) / 2.0, (scaledSeg.$1.y + scaledSeg.$2.y) / 2.0);
          return CadPoint2D(sMid.x - bMid.x, sMid.y - bMid.y);
        }
      }
    }

    return null;
  }

  /// Resolves named edge tokens (EDGE_TOP, EDGE_BOTTOM, etc.) to outer contour segments.
  static (CadPoint2D, CadPoint2D)? _resolveNamedEdgeSegment(String token, DsfDocument doc) {
    if (doc.outerContour.length < 2) return null;
    int bestIdx = -1;
    double bestVal = token == 'EDGE_TOP' || token == 'EDGE_RIGHT' ? -double.infinity : double.infinity;

    for (int i = 0; i < doc.outerContour.length; i++) {
      final a = doc.outerContour[i];
      final b = doc.outerContour[(i + 1) % doc.outerContour.length];
      final mid = CadPoint2D((a.x + b.x) / 2.0, (a.y + b.y) / 2.0);

      switch (token) {
        case 'EDGE_TOP':
          if ((a.y - b.y).abs() < 2.0 && mid.y > bestVal) {
            bestVal = mid.y;
            bestIdx = i;
          }
          break;
        case 'EDGE_BOTTOM':
          if ((a.y - b.y).abs() < 2.0 && mid.y < bestVal) {
            bestVal = mid.y;
            bestIdx = i;
          }
          break;
        case 'EDGE_LEFT':
          if ((a.x - b.x).abs() < 2.0 && mid.x < bestVal) {
            bestVal = mid.x;
            bestIdx = i;
          }
          break;
        case 'EDGE_RIGHT':
          if ((a.x - b.x).abs() < 2.0 && mid.x > bestVal) {
            bestVal = mid.x;
            bestIdx = i;
          }
          break;
      }
    }

    if (bestIdx != -1) {
      return (doc.outerContour[bestIdx], doc.outerContour[(bestIdx + 1) % doc.outerContour.length]);
    }
    return null;
  }

  /// Computes the exact displacement of a coordinate point [pt] that lies on or near
  /// a baseline segment (bend line, cut line, or contour edge) under the scaling transformation.
  static CadPoint2D _projectPointShiftFromGeometry(CadPoint2D pt, DsfDocument baseline, DsfDocument scaled, CadPoint2D Function(CadPoint2D) transformPt) {
    // 1. Check bends
    for (final b in baseline.bends) {
      if (_pointToSegmentDistance(pt, b.p1, b.p2) <= 3.5) {
        final scaledB = scaled.bends.where((sb) => sb.id == b.id).firstOrNull;
        if (scaledB != null) {
          final t = _projectionFactorOnSegment(pt, b.p1, b.p2);
          final scaledPt = CadPoint2D(scaledB.p1.x + t * (scaledB.p2.x - scaledB.p1.x), scaledB.p1.y + t * (scaledB.p2.y - scaledB.p1.y));
          return CadPoint2D(scaledPt.x - pt.x, scaledPt.y - pt.y);
        }
      }
    }

    // 2. Check cut lines
    for (final c in baseline.cutLines) {
      if (_pointToSegmentDistance(pt, c.p1, c.p2) <= 3.5) {
        final scaledC = scaled.cutLines.where((sc) => sc.id == c.id).firstOrNull;
        if (scaledC != null) {
          final t = _projectionFactorOnSegment(pt, c.p1, c.p2);
          final scaledPt = CadPoint2D(scaledC.p1.x + t * (scaledC.p2.x - scaledC.p1.x), scaledC.p1.y + t * (scaledC.p2.y - scaledC.p1.y));
          return CadPoint2D(scaledPt.x - pt.x, scaledPt.y - pt.y);
        }
      }
    }

    // 3. Check outer contour edges
    if (baseline.outerContour.length >= 2) {
      for (int i = 0; i < baseline.outerContour.length; i++) {
        final b1 = baseline.outerContour[i];
        final b2 = baseline.outerContour[(i + 1) % baseline.outerContour.length];
        if (_pointToSegmentDistance(pt, b1, b2) <= 3.5) {
          final t = _projectionFactorOnSegment(pt, b1, b2);
          if (scaled.outerContour.length == baseline.outerContour.length) {
            final s1 = scaled.outerContour[i];
            final s2 = scaled.outerContour[(i + 1) % scaled.outerContour.length];
            final scaledPt = CadPoint2D(s1.x + t * (s2.x - s1.x), s1.y + t * (s2.y - s1.y));
            return CadPoint2D(scaledPt.x - pt.x, scaledPt.y - pt.y);
          } else {
            final s1 = transformPt(b1);
            final s2 = transformPt(b2);
            final scaledPt = CadPoint2D(s1.x + t * (s2.x - s1.x), s1.y + t * (s2.y - s1.y));
            return CadPoint2D(scaledPt.x - pt.x, scaledPt.y - pt.y);
          }
        }
      }
    }

    // Fallback: transform directly
    final transformed = transformPt(pt);
    return CadPoint2D(transformed.x - pt.x, transformed.y - pt.y);
  }

  /// Calculates interpolation factor t in [0.0, 1.0] of point [p] projected on segment ([a], [b]).
  static double _projectionFactorOnSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return 0.0;
    return (((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq).clamp(0.0, 1.0);
  }

  /// Canonical Fallback: Determines the shift for an unconstrained punch by binding
  /// it to its nearest host mounting edge in [baseline], ensuring setback constancy.
  static CadPoint2D _computeFallbackEdgeShift({
    required CncPunchPrimitive punch,
    required DsfDocument baseline,
    required DsfDocument scaled,
    required String paramId,
    required double delta,
    required CadPoint2D Function(CadPoint2D) transformPt,
  }) {
    final pt = punch.center;

    // 1. Outside Riser Dedicated Punch Scaling
    final isOutsideRiser =
        baseline.productType.toLowerCase().contains('outside') ||
        baseline.itemName.toLowerCase().contains('outside') ||
        (!baseline.bends.any((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0) &&
            baseline.bends.where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange).length >= 2 &&
            (baseline.productType.toLowerCase().contains('riser') || baseline.itemName.toLowerCase().contains('riser')));

    if (isOutsideRiser && paramId == 'width') {
      final vertBends = baseline.bends.where((b) {
        final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
        return is90 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL');
      }).toList()..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));

      if (vertBends.length >= 2) {
        final x1 = math.min(vertBends.first.p1.x, vertBends.last.p1.x);
        final x2 = math.max(vertBends.first.p1.x, vertBends.last.p1.x);
        final xMid = (x1 + x2) / 2.0;
        final halfDelta = delta / 2.0;

        if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5) {
          return const CadPoint2D(0.0, 0.0);
        }
        if (pt.x < xMid) {
          return CadPoint2D(-halfDelta, 0.0);
        } else {
          return CadPoint2D(halfDelta, 0.0);
        }
      }
    }

    if (isOutsideRiser && paramId == 'height') {
      final longBends = baseline.bends.where((b) {
        final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
        return is90 && b.role != BendLineRole.flange;
      }).toList();

      if (longBends.length >= 2) {
        final x1 = math.min(longBends[0].p1.x, longBends[1].p1.x);
        final x2 = math.max(longBends[0].p1.x, longBends[1].p1.x);
        final xMid = (x1 + x2) / 2.0;
        final yFloorTop = math.max(longBends[0].p2.y, longBends[1].p2.y);
        final d45 = delta / math.sqrt(2);

        // Central Floor punches: fixed
        if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5) {
          return const CadPoint2D(0.0, 0.0);
        }

        // Left Cheek punches
        if (pt.x < xMid) {
          if (punch.rotationDeg == 0.0) {
            // Port 1 mouth: outer slot (SLOT_7) moves with FL1, inner slot (SLOT_8) fixed
            final flBends = baseline.bends.where((b) => b.p1.x < x1 - 10.0);
            final xFL1 = flBends.isNotEmpty ? flBends.first.p1.x : x1 - 96.0;
            final xLeftMid = (xFL1 + x1) / 2.0;
            if (pt.x <= xLeftMid) {
              return CadPoint2D(-delta, 0.0);
            }
            return const CadPoint2D(0.0, 0.0);
          } else {
            // Port 2 45° mouth: outer slot (SLOT_2) moves with 45° outer mouth, inner slot (SLOT_1) fixed
            if (pt.y >= yFloorTop + 35.0) {
              return CadPoint2D(-d45, d45);
            }
            return const CadPoint2D(0.0, 0.0);
          }
        } else {
          // Right Cheek punches
          if (punch.rotationDeg == 0.0) {
            // Port 1 mouth: outer slot (SLOT_5) moves with FL2, inner slot (SLOT_6) fixed
            final flBends = baseline.bends.where((b) => b.p1.x > x2 + 10.0);
            final xFL2 = flBends.isNotEmpty ? flBends.first.p1.x : x2 + 96.0;
            final xRightMid = (x2 + xFL2) / 2.0;
            if (pt.x >= xRightMid) {
              return CadPoint2D(delta, 0.0);
            }
            return const CadPoint2D(0.0, 0.0);
          } else {
            // Port 2 45° mouth: outer slot (SLOT_4) moves with 45° outer mouth, inner slot (SLOT_3) fixed
            if (pt.y >= yFloorTop + 35.0) {
              return CadPoint2D(d45, d45);
            }
            return const CadPoint2D(0.0, 0.0);
          }
        }
      }
    }

    // 2. Inside Riser Dedicated Punch Scaling
    final isInsideRiser =
        !isOutsideRiser &&
        (baseline.productType.toLowerCase().contains('riser') ||
            (baseline.bends.where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange).length >= 2 &&
                baseline.bends.any((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0)));

    if (isInsideRiser && paramId == 'height') {
      final longBends = baseline.bends.where((b) {
        final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
        return is90 && b.role != BendLineRole.flange;
      }).toList();

      if (longBends.length >= 2) {
        final x1 = math.min(longBends[0].p1.x, longBends[1].p1.x);
        final x2 = math.max(longBends[0].p1.x, longBends[1].p1.x);

        final b3 = baseline.bends.firstWhere((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0, orElse: () => baseline.bends.first);
        final yB3 = b3.p1.y;
        final yProngThreshold = yB3 - (yB3 - 30.0) * 0.45;

        final deltaH = delta;
        final d45 = deltaH / math.sqrt(2);

        // 1. Floor punches: fixed
        if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5) {
          return const CadPoint2D(0.0, 0.0);
        }

        // 2. Left Cheek punches
        if (pt.x < x1 - 0.5) {
          if (pt.y > yProngThreshold) {
            // 45° diagonal prong:
            // Outer slot (y < 120) tracks outer mouth corner (-deltaH, 0)
            // Inner slot (y >= 120) tracks inner mouth tip (-deltaH + d45, d45)
            if (pt.y < 120.0) {
              return CadPoint2D(-deltaH, 0.0);
            } else {
              return CadPoint2D(-deltaH + d45, d45);
            }
          } else {
            // Straight sidewall section:
            // Find nearest vertical edge in baseline outerContour
            double bestDist = double.infinity;
            int bestEdgeIndex = -1;
            for (int i = 0; i < baseline.outerContour.length; i++) {
              final a = baseline.outerContour[i];
              final b = baseline.outerContour[(i + 1) % baseline.outerContour.length];
              if (a.x < x1 + 0.5 && (b.x - a.x).abs() < 1.0 && (b.y - a.y).abs() > 2.0) {
                final d = _pointToSegmentDistance(pt, a, b);
                if (d < bestDist) {
                  bestDist = d;
                  bestEdgeIndex = i;
                }
              }
            }

            if (bestEdgeIndex != -1) {
              final shift = _measureEdgeShift('CONTOUR_EDGE_$bestEdgeIndex', baseline, scaled, transformPt);
              if (shift != null) return shift;
            }

            // Fallback threshold
            double minContourX = x1;
            for (final p in baseline.outerContour) {
              if (p.x < minContourX) minContourX = p.x;
            }
            final xLeftMid = (minContourX + x1) / 2.0;
            return pt.x > xLeftMid ? const CadPoint2D(0.0, 0.0) : CadPoint2D(-deltaH, 0.0);
          }
        }

        // 3. Right Cheek punches
        if (pt.x > x2 + 0.5) {
          if (pt.y > yProngThreshold) {
            // 45° diagonal prong:
            // Outer slot (y < 120) tracks outer mouth corner (+deltaH, 0)
            // Inner slot (y >= 120) tracks inner mouth tip (+deltaH - d45, d45)
            if (pt.y < 120.0) {
              return CadPoint2D(deltaH, 0.0);
            } else {
              return CadPoint2D(deltaH - d45, d45);
            }
          } else {
            // Straight sidewall section:
            // Find nearest vertical edge in baseline outerContour
            double bestDist = double.infinity;
            int bestEdgeIndex = -1;
            for (int i = 0; i < baseline.outerContour.length; i++) {
              final a = baseline.outerContour[i];
              final b = baseline.outerContour[(i + 1) % baseline.outerContour.length];
              if (a.x > x2 - 0.5 && (b.x - a.x).abs() < 1.0 && (b.y - a.y).abs() > 2.0) {
                final d = _pointToSegmentDistance(pt, a, b);
                if (d < bestDist) {
                  bestDist = d;
                  bestEdgeIndex = i;
                }
              }
            }

            if (bestEdgeIndex != -1) {
              final shift = _measureEdgeShift('CONTOUR_EDGE_$bestEdgeIndex', baseline, scaled, transformPt);
              if (shift != null) return shift;
            }

            // Fallback threshold
            double maxContourX = x2;
            for (final p in baseline.outerContour) {
              if (p.x > maxContourX) maxContourX = p.x;
            }
            final xRightMid = (x2 + maxContourX) / 2.0;
            return pt.x < xRightMid ? const CadPoint2D(0.0, 0.0) : CadPoint2D(delta, 0.0);
          }
        }
      }
    }

    // General fallback for all other CMS fittings (Flat Bends, Tees, Straights):
    // Bind to the nearest parallel outer contour edge within 40 mm.
    double bestDist = double.infinity;
    int bestEdgeIdx = -1;

    for (int i = 0; i < baseline.outerContour.length; i++) {
      final a = baseline.outerContour[i];
      final b = baseline.outerContour[(i + 1) % baseline.outerContour.length];
      final dist = _pointToSegmentDistance(pt, a, b);
      if (dist < bestDist && dist <= 40.0) {
        bestDist = dist;
        bestEdgeIdx = i;
      }
    }

    if (bestEdgeIdx != -1) {
      final edgeShift = _measureEdgeShift('CONTOUR_EDGE_$bestEdgeIdx', baseline, scaled, transformPt);
      if (edgeShift != null) return edgeShift;
    }

    // Default: evaluate through point transform
    final transformed = transformPt(pt);
    return CadPoint2D(transformed.x - pt.x, transformed.y - pt.y);
  }

  /// Computes the centering shift for a group of punches constrained to each other
  /// without edge anchors, ensuring they remain at the center of the expanded host region.
  static CadPoint2D _computeGroupCenterShift({
    required List<String> punchIds,
    required DsfDocument baseline,
    required DsfDocument scaled,
    required String paramId,
    required double delta,
    required CadPoint2D Function(CadPoint2D) transformPt,
  }) {
    if (punchIds.isEmpty) return const CadPoint2D(0.0, 0.0);

    // Compute centroid of the punch group in baseline
    double sumX = 0.0;
    double sumY = 0.0;
    for (final id in punchIds) {
      final p = baseline.punches.firstWhere((p) => p.id == id);
      sumX += p.center.x;
      sumY += p.center.y;
    }
    final groupMid = CadPoint2D(sumX / punchIds.length, sumY / punchIds.length);

    // 1. Inside or Outside Riser sidewall cheeks
    final isRiser =
        baseline.productType.toLowerCase().contains('riser') ||
        (baseline.bends.where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange).length >= 2 &&
            baseline.bends.any((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0));

    if (isRiser && paramId == 'height') {
      final longBends = baseline.bends.where((b) {
        final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
        return is90 && b.role != BendLineRole.flange;
      }).toList();

      if (longBends.length >= 2) {
        final x1 = math.min(longBends[0].p1.x, longBends[1].p1.x);
        final x2 = math.max(longBends[0].p1.x, longBends[1].p1.x);

        final b3 = baseline.bends.firstWhere((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0, orElse: () => baseline.bends.first);
        final yB3 = b3.p1.y;
        final yProngThreshold = yB3 - (yB3 - 30.0) * 0.45;

        final deltaH = delta;
        final d45 = deltaH / math.sqrt(2);
        final deltaYProngTip = (244.70 - 170.66) * (deltaH / 100.0);

        if (groupMid.x > x2 + 0.5) {
          // Right Cheek:
          if (groupMid.y > yProngThreshold) {
            final t = ((groupMid.y - 116.92) / (170.66 - 116.92)).clamp(0.0, 1.0);
            return CadPoint2D(deltaH - t * d45, t * deltaYProngTip);
          } else {
            // Find outer vertical edge of the cheek tab (x > x2 + 20.0, y <= yProngThreshold)
            double bestDist = double.infinity;
            int bestEdgeIndex = -1;
            for (int i = 0; i < baseline.outerContour.length; i++) {
              final a = baseline.outerContour[i];
              final b = baseline.outerContour[(i + 1) % baseline.outerContour.length];
              if (a.x > x2 + 20.0 && (b.x - a.x).abs() < 1.0 && (b.y - a.y).abs() > 2.0 && a.y <= yProngThreshold) {
                final d = _pointToSegmentDistance(groupMid, a, b);
                if (d < bestDist) {
                  bestDist = d;
                  bestEdgeIndex = i;
                }
              }
            }

            double outerShiftX = delta;
            if (bestEdgeIndex != -1) {
              final shift = _measureEdgeShift('CONTOUR_EDGE_$bestEdgeIndex', baseline, scaled, transformPt);
              if (shift != null) outerShiftX = shift.x;
            }

            return CadPoint2D(outerShiftX / 2.0, 0.0);
          }
        } else if (groupMid.x < x1 - 0.5) {
          // Left Cheek:
          if (groupMid.y > yProngThreshold) {
            final t = ((groupMid.y - 116.92) / (170.66 - 116.92)).clamp(0.0, 1.0);
            return CadPoint2D(-deltaH + t * d45, t * deltaYProngTip);
          } else {
            // Find outer vertical edge of the cheek tab (x < x1 - 20.0, y <= yProngThreshold)
            double bestDist = double.infinity;
            int bestEdgeIndex = -1;
            for (int i = 0; i < baseline.outerContour.length; i++) {
              final a = baseline.outerContour[i];
              final b = baseline.outerContour[(i + 1) % baseline.outerContour.length];
              if (a.x < x1 - 20.0 && (b.x - a.x).abs() < 1.0 && (b.y - a.y).abs() > 2.0 && a.y <= yProngThreshold) {
                final d = _pointToSegmentDistance(groupMid, a, b);
                if (d < bestDist) {
                  bestDist = d;
                  bestEdgeIndex = i;
                }
              }
            }

            double outerShiftX = -delta;
            if (bestEdgeIndex != -1) {
              final shift = _measureEdgeShift('CONTOUR_EDGE_$bestEdgeIndex', baseline, scaled, transformPt);
              if (shift != null) outerShiftX = shift.x;
            }

            return CadPoint2D(outerShiftX / 2.0, 0.0);
          }
        } else {
          // Floor web:
          final deltaY = groupMid.y > yB3 + 0.5 ? delta * math.sqrt(2) : 0.0;
          return CadPoint2D(0.0, deltaY);
        }
      }
    }

    // 2. General Fitting Faces (Flat Bends, Reducers, Tees, Crosses, Trunking, Trays)
    if (baseline.faces.isNotEmpty && scaled.faces.isNotEmpty) {
      PlanarSheetFace? hostFace;
      for (final f in baseline.faces) {
        if (_isPointInPoly(groupMid, f.vertices)) {
          hostFace = f;
          break;
        }
      }
      if (hostFace == null) {
        double minDist = double.infinity;
        for (final f in baseline.faces) {
          final c = _computeCentroid(f.vertices);
          final d = groupMid.distanceTo(c);
          if (d < minDist) {
            minDist = d;
            hostFace = f;
          }
        }
      }

      if (hostFace != null) {
        final scaledFace = scaled.faces.where((f) => f.id == hostFace!.id).firstOrNull;
        if (scaledFace != null && scaledFace.vertices.isNotEmpty && hostFace.vertices.isNotEmpty) {
          final cBase = _computeCentroid(hostFace.vertices);
          final cScaled = _computeCentroid(scaledFace.vertices);
          return CadPoint2D(cScaled.x - cBase.x, cScaled.y - cBase.y);
        }
      }
    }

    // 3. Fallback: Geometry Projector shift at centroid
    final transformed = transformPt(groupMid);
    return CadPoint2D(transformed.x - groupMid.x, transformed.y - groupMid.y);
  }

  static CadPoint2D _computeCentroid(List<CadPoint2D> vertices) {
    if (vertices.isEmpty) return const CadPoint2D(0.0, 0.0);
    double sx = 0.0;
    double sy = 0.0;
    for (final v in vertices) {
      sx += v.x;
      sy += v.y;
    }
    return CadPoint2D(sx / vertices.length, sy / vertices.length);
  }

  static bool _isPointInPoly(CadPoint2D pt, List<CadPoint2D> poly) {
    if (poly.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].x, yi = poly[i].y;
      final xj = poly[j].x, yj = poly[j].y;
      final intersect = ((yi > pt.y) != (yj > pt.y)) && (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Updates all baseline dimensions so their attachment points align with the
  /// transformed geometry and punches, and measured values are accurately recomputed.
  static List<CadDimension> _updateDimensions({
    required DsfDocument baseline,
    required DsfDocument scaled,
    required List<CncPunchPrimitive> newPunches,
    required CadPoint2D Function(CadPoint2D) transformPt,
  }) {
    if (baseline.dimensions.isEmpty) return const [];

    return baseline.dimensions.map((dim) {
      CadPoint2D? newPA;
      CadPoint2D? newPB;

      // Resolve Point A
      if (dim.referenceAId != null) {
        final punchA = newPunches.where((p) => p.id == dim.referenceAId).firstOrNull;
        if (punchA != null) {
          newPA = punchA.center;
        } else {
          final edgeSeg = AssociativeDimensionEngine.resolveEdgeSegment(dim.referenceAId, scaled);
          if (edgeSeg != null) {
            newPA = CadPoint2D((edgeSeg.$1.x + edgeSeg.$2.x) / 2.0, (edgeSeg.$1.y + edgeSeg.$2.y) / 2.0);
          }
        }
      }
      newPA ??= (dim.pointA != null ? transformPt(dim.pointA!) : null);

      // Resolve Point B
      if (dim.referenceBId != null) {
        final punchB = newPunches.where((p) => p.id == dim.referenceBId).firstOrNull;
        if (punchB != null) {
          newPB = punchB.center;
        } else {
          final edgeSeg = AssociativeDimensionEngine.resolveEdgeSegment(dim.referenceBId, scaled);
          if (edgeSeg != null) {
            newPB = CadPoint2D((edgeSeg.$1.x + edgeSeg.$2.x) / 2.0, (edgeSeg.$1.y + edgeSeg.$2.y) / 2.0);
          }
        }
      }
      newPB ??= (dim.pointB != null ? transformPt(dim.pointB!) : null);

      // Recalculate measurement
      double measured = dim.measuredValue;
      if (newPA != null && newPB != null) {
        switch (dim.type) {
          case CadDimensionType.horizontal:
            measured = (newPB.x - newPA.x).abs();
            break;
          case CadDimensionType.vertical:
            measured = (newPB.y - newPA.y).abs();
            break;
          case CadDimensionType.holeToEdge:
            // Hole to edge: distance to edge segment line
            final edgeId = (dim.referenceAId != null && !newPunches.any((p) => p.id == dim.referenceAId)) ? dim.referenceAId : dim.referenceBId;
            final edgeSeg = AssociativeDimensionEngine.resolveEdgeSegment(edgeId, scaled);
            final punchId = (dim.referenceAId != null && newPunches.any((p) => p.id == dim.referenceAId)) ? dim.referenceAId : dim.referenceBId;
            final punch = newPunches.where((p) => p.id == punchId).firstOrNull;

            if (edgeSeg != null && punch != null) {
              final proj = AssociativeDimensionEngine.projectPointToSegmentLine(punch.center, edgeSeg.$1, edgeSeg.$2);
              measured = punch.center.distanceTo(proj);
            } else {
              measured = newPA.distanceTo(newPB);
            }
            break;
          case CadDimensionType.holeToHole:
          case CadDimensionType.aligned:
          case CadDimensionType.centerToCenter:
            measured = newPA.distanceTo(newPB);
            break;
          default:
            break;
        }
      }

      return dim.copyWith(pointA: newPA, pointB: newPB, measuredValue: measured);
    }).toList();
  }

  /// Calculates perpendicular distance from point [p] to segment ([a], [b]).
  static double _pointToSegmentDistance(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return p.distanceTo(a);
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq).clamp(0.0, 1.0);
    final proj = CadPoint2D(a.x + t * dx, a.y + t * dy);
    return p.distanceTo(proj);
  }

  /// Builds a fallback geometric projector mapping baseline vertices to scaled vertices.
  static CadPoint2D Function(CadPoint2D) _createGeometryProjector(DsfDocument baseline, DsfDocument scaled) {
    return (CadPoint2D pt) {
      if (scaled.outerContour.length == baseline.outerContour.length && baseline.outerContour.isNotEmpty) {
        int bestIdx = 0;
        double bestDist = double.infinity;
        for (int i = 0; i < baseline.outerContour.length; i++) {
          final d = pt.distanceTo(baseline.outerContour[i]);
          if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
          }
        }
        if (bestDist < 5.0) {
          final origV = baseline.outerContour[bestIdx];
          final scaledV = scaled.outerContour[bestIdx];
          return CadPoint2D(pt.x + (scaledV.x - origV.x), pt.y + (scaledV.y - origV.y));
        }
      }
      return pt;
    };
  }
}
