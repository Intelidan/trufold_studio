// =============================================================================
// dxf_auto_fold_engine.dart
//
// Intersection-Based Geometric Auto Fold & Flange/Bend Snapping Engine.
// Analyzes flat DXF drawings to identify corner relief notches, tab steps,
// and opposite intersection dots to accurately place bend and flange lines.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/fold_bend_line.dart';
import '../models/dsf_document.dart';
import '../models/dxf_fitting_metadata.dart';
import 'planar_face_decomposer.dart';

class AutoFoldCandidate {
  final CadPoint2D p1;
  final CadPoint2D p2;
  final bool isFlange;
  final double offsetMm;
  final CadPoint2D? referenceEdgeP1;
  final CadPoint2D? referenceEdgeP2;
  final String label;

  const AutoFoldCandidate({
    required this.p1,
    required this.p2,
    required this.isFlange,
    required this.offsetMm,
    this.referenceEdgeP1,
    this.referenceEdgeP2,
    required this.label,
  });

  CadLineSegment toLineSegment(String id) => CadLineSegment(id: id, p1: p1, p2: p2);

  double get length => p1.distanceTo(p2);
  CadPoint2D get midpoint => CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
}

class DxfAutoFoldEngine {
  /// Detects all logical bend and flange candidates on a contour by analyzing
  /// tab protrusions, re-entrant notch intersections, and opposite boundary dots.
  static List<AutoFoldCandidate> detectCandidateLines(
    List<CadPoint2D> contour, {
    double minFlangeMm = 7.0,
    double maxFlangeMm = 25.0,
  }) {
    if (contour.length < 4) return [];

    final candidates = <AutoFoldCandidate>[];

    // 1. Detect Tab Base Lines (Flange candidates connecting two base corner dots)
    final tabCandidates = _detectTabBaseLines(contour, minFlangeMm, maxFlangeMm);
    candidates.addAll(tabCandidates);

    // 2. Detect Neck & Junction Bend Lines (connecting opposite notch dots or crotches)
    final bendCandidates = _detectNeckAndJunctionBends(contour);
    candidates.addAll(bendCandidates);

    // 3. Detect Notch-to-Opposite-Boundary Edge-Parallel Lines
    final notchEdgeCandidates = _detectNotchEdgeParallelLines(contour, minFlangeMm, maxFlangeMm);
    for (final cand in notchEdgeCandidates) {
      // Avoid duplicates
      final isDup = candidates.any((existing) =>
          (existing.midpoint.distanceTo(cand.midpoint) < 4.0) ||
          ((existing.p1.distanceTo(cand.p1) < 3.0 && existing.p2.distanceTo(cand.p2) < 3.0) ||
           (existing.p1.distanceTo(cand.p2) < 3.0 && existing.p2.distanceTo(cand.p1) < 3.0)));
      if (!isDup) {
        candidates.add(cand);
      }
    }

    return candidates;
  }

  /// Finds the best interactive candidate when hovering or pointing within 20mm
  /// of an intersecting line, notch, or boundary edge.
  static AutoFoldCandidate? findInteractiveCandidate(
    CadPoint2D cursorPt, {
    required bool isFlange,
    required List<CadPoint2D> contour,
    double maxProximityMm = 20.0,
  }) {
    if (contour.length < 3) return null;

    final allCandidates = detectCandidateLines(contour);
    final filtered = allCandidates.where((c) => c.isFlange == isFlange).toList();

    AutoFoldCandidate? bestCandidate;
    double bestDist = double.infinity;

    for (final cand in filtered) {
      // Check distance from cursor to candidate line segment
      final lineDist = _distToSegment(cursorPt, cand.p1, cand.p2);

      // Check distance to candidate endpoints (the "dots")
      final p1Dist = cursorPt.distanceTo(cand.p1);
      final p2Dist = cursorPt.distanceTo(cand.p2);
      final dotDist = math.min(p1Dist, p2Dist);

      // Check distance to the reference outer boundary edge (e.g. the tab edge)
      double edgeDist = double.infinity;
      if (cand.referenceEdgeP1 != null && cand.referenceEdgeP2 != null) {
        edgeDist = _distToSegment(cursorPt, cand.referenceEdgeP1!, cand.referenceEdgeP2!);
      }

      final minDist = math.min(lineDist, math.min(dotDist, edgeDist));

      if (minDist <= maxProximityMm && minDist < bestDist) {
        bestDist = minDist;
        bestCandidate = cand;
      }
    }

    return bestCandidate;
  }

  /// Automatically applies all logical bend and flange lines to a DSF document,
  /// decomposes the workpiece into planar faces, and recomputes the 3D kinematics.
  static DsfDocument autoFoldFitting({
    required DsfDocument document,
    DxfFittingMetadata? metadata,
    double? customFlangeMm,
  }) {
    final contour = document.outerContour;
    if (contour.length < 3) return document;

    final targetFlange = customFlangeMm ?? metadata?.flangeMm ?? 13.0;
    final candidates = detectCandidateLines(contour);

    final newBends = <FoldBendLine>[];
    int bendIdx = 1;
    int flangeIdx = 1;

    // Filter and add flange candidates near the target flange dimension
    for (final cand in candidates.where((c) => c.isFlange)) {
      // Snap to dot-to-dot line even if entered flange is slightly different
      final isMatch = (cand.offsetMm - targetFlange).abs() <= 8.0 ||
                      (cand.offsetMm >= 7.0 && cand.offsetMm <= 25.0);
      if (isMatch) {
        // Prevent overlapping lines
        final isOverlap = newBends.any((b) =>
            b.midpoint.distanceTo(cand.midpoint) < 4.0 ||
            (b.p1.distanceTo(cand.p1) < 3.0 && b.p2.distanceTo(cand.p2) < 3.0) ||
            (b.p1.distanceTo(cand.p2) < 3.0 && b.p2.distanceTo(cand.p1) < 3.0));

        if (!isOverlap) {
          newBends.add(
            FoldBendLine(
              id: 'FL$flangeIdx',
              p1: cand.p1,
              p2: cand.p2,
              direction: BendDirection.up,
              targetAngleDeg: 90.0,
              radiusMm: 0.5,
              role: BendLineRole.flange,
              layer: 'BEND_UP',
            ),
          );
          flangeIdx++;
        }
      }
    }

    // Collect and sort bend candidates: prioritize shorter/neck spans and those matching fitting widths
    final bendCandidates = candidates.where((c) => !c.isFlange).toList();
    final targetWidths = <double>{};
    if (metadata != null) {
      for (final val in metadata.parameters.values) {
        if (val >= 20.0) targetWidths.add(val);
      }
    }

    bendCandidates.sort((a, b) {
      // Prioritize matches to fitting port widths
      final aMatches = targetWidths.any((w) => (a.offsetMm - w).abs() <= 5.0);
      final bMatches = targetWidths.any((w) => (b.offsetMm - w).abs() <= 5.0);
      if (aMatches && !bMatches) return -1;
      if (!aMatches && bMatches) return 1;
      // Otherwise sort by shorter span first (avoid long internal diagonals)
      return a.length.compareTo(b.length);
    });

    for (final cand in bendCandidates) {
      // Check for overlap or duplicate
      final isOverlap = newBends.any((b) =>
          b.midpoint.distanceTo(cand.midpoint) < 4.0 ||
          (b.p1.distanceTo(cand.p1) < 3.0 && b.p2.distanceTo(cand.p2) < 3.0) ||
          (b.p1.distanceTo(cand.p2) < 3.0 && b.p2.distanceTo(cand.p1) < 3.0));
      if (isOverlap) continue;

      // Check for strict crossing with already accepted bends (sharing endpoints is allowed, crossing is not)
      bool crossesAny = false;
      for (final existing in newBends) {
        // If they share an endpoint, they don't cross
        final sharesEndpoint =
            existing.p1.distanceTo(cand.p1) < 2.0 ||
            existing.p1.distanceTo(cand.p2) < 2.0 ||
            existing.p2.distanceTo(cand.p1) < 2.0 ||
            existing.p2.distanceTo(cand.p2) < 2.0;
        if (!sharesEndpoint && _linesIntersect(cand.p1, cand.p2, existing.p1, existing.p2)) {
          crossesAny = true;
          break;
        }
      }

      if (!crossesAny) {
        newBends.add(
          FoldBendLine(
            id: 'B$bendIdx',
            p1: cand.p1,
            p2: cand.p2,
            direction: BendDirection.up,
            targetAngleDeg: 90.0,
            radiusMm: 1.5,
            role: BendLineRole.bend,
            layer: 'BEND_UP',
          ),
        );
        bendIdx++;
      }
    }

    // Planar Face Decomposition
    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: contour,
      bends: newBends,
      cutLines: document.cutLines,
    );

    // Attach metadata to the document
    final updatedMetadata = Map<String, dynamic>.from(document.metadata);
    if (metadata != null) {
      updatedMetadata['fittingMetadata'] = metadata.toJson();
      updatedMetadata['fittingCategory'] = metadata.category;
      updatedMetadata['fittingProduct'] = metadata.product;
      updatedMetadata['fittingVariant'] = metadata.variantName;
      updatedMetadata['fittingFlangeMm'] = targetFlange;
    }

    final updatedParams = Map<String, double>.from(document.parameters);
    if (metadata != null) {
      updatedParams.addAll(metadata.parameters);
      updatedParams['flange'] = targetFlange;
    }

    return document.copyWith(
      bends: decomp.connectedBends,
      faces: decomp.faces,
      baseFaceId: decomp.baseFaceId,
      metadata: updatedMetadata,
      parameters: updatedParams,
    );
  }

  // ===========================================================================
  // Feature Recognition Helpers
  // ===========================================================================

  /// Detects tab protrusions by finding step shoulders of depth 7mm - 25mm.
  /// Connects the two base dots on opposite sides of the tab.
  static List<AutoFoldCandidate> _detectTabBaseLines(
    List<CadPoint2D> contour,
    double minFlangeMm,
    double maxFlangeMm,
  ) {
    final results = <AutoFoldCandidate>[];
    final n = contour.length;

    for (int i = 0; i < n; i++) {
      // Check sequence of 3 edges: Shoulder 1, Outer Tab Edge, Shoulder 2
      final pA = contour[i];
      final pB = contour[(i + 1) % n];
      final pC = contour[(i + 2) % n];
      final pD = contour[(i + 3) % n];

      final lenAB = pA.distanceTo(pB);
      final lenBC = pB.distanceTo(pC);
      final lenCD = pC.distanceTo(pD);

      // Shoulder lengths should be in flange range
      if (lenAB >= minFlangeMm && lenAB <= maxFlangeMm &&
          lenCD >= minFlangeMm && lenCD <= maxFlangeMm &&
          lenBC >= 10.0) {

        // Check that AB and CD are roughly parallel and opposite in direction
        final uABx = (pB.x - pA.x) / lenAB;
        final uABy = (pB.y - pA.y) / lenAB;
        final uCDx = (pD.x - pC.x) / lenCD;
        final uCDy = (pD.y - pC.y) / lenCD;

        final dotShoulders = uABx * uCDx + uABy * uCDy;
        if (dotShoulders < -0.7) {
          // Tab protrusion verified! Connect base dots pA and pD.
          final avgOffset = (lenAB + lenCD) / 2.0;
          results.add(
            AutoFoldCandidate(
              p1: pA,
              p2: pD,
              isFlange: true,
              offsetMm: double.parse(avgOffset.toStringAsFixed(1)),
              referenceEdgeP1: pB,
              referenceEdgeP2: pC,
              label: 'FLANGE ${avgOffset.toStringAsFixed(0)}mm',
            ),
          );
        }
      }
    }

    return results;
  }

  /// Detects neck bend lines across ports and miter bends across junctions.
  static List<AutoFoldCandidate> _detectNeckAndJunctionBends(
    List<CadPoint2D> contour,
  ) {
    final results = <AutoFoldCandidate>[];
    final n = contour.length;

    // Find all re-entrant corner vertices (notches and crotches)
    final notchIndices = <int>[];
    for (int i = 0; i < n; i++) {
      final prev = contour[(i - 1 + n) % n];
      final next = contour[(i + 1) % n];

      // Check if interior angle indicates a notch
      final mid = CadPoint2D((prev.x + next.x) / 2.0, (prev.y + next.y) / 2.0);
      if (!_isPointInPoly(mid, contour)) {
        notchIndices.add(i);
      }
    }

    // Connect pairs of notch vertices that form valid internal spans
    for (int a = 0; a < notchIndices.length; a++) {
      for (int b = a + 1; b < notchIndices.length; b++) {
        final idxA = notchIndices[a];
        final idxB = notchIndices[b];

        final p1 = contour[idxA];
        final p2 = contour[idxB];
        final dist = p1.distanceTo(p2);

        if (dist >= 20.0) {
          final mid = CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
          if (_isPointInPoly(mid, contour)) {
            // Check that segment does not cross outer boundary
            if (!_segmentCrossesContour(p1, p2, contour, idxA, idxB)) {
              results.add(
                AutoFoldCandidate(
                  p1: p1,
                  p2: p2,
                  isFlange: false,
                  offsetMm: double.parse(dist.toStringAsFixed(1)),
                  label: 'BEND ${dist.toStringAsFixed(0)}mm',
                ),
              );
            }
          }
        }
      }
    }

    return results;
  }

  /// Projects edge-parallel lines from notch vertices across to opposite boundaries.
  static List<AutoFoldCandidate> _detectNotchEdgeParallelLines(
    List<CadPoint2D> contour,
    double minFlangeMm,
    double maxFlangeMm,
  ) {
    final results = <AutoFoldCandidate>[];
    final n = contour.length;

    for (int i = 0; i < n; i++) {
      final pCurr = contour[i];
      final pNext = contour[(i + 1) % n];
      final pPrev = contour[(i - 1 + n) % n];

      final dNext = pCurr.distanceTo(pNext);
      final dPrev = pCurr.distanceTo(pPrev);

      // If an edge is a shoulder (7mm - 25mm), project perpendicular to it
      if (dPrev >= minFlangeMm && dPrev <= maxFlangeMm) {
        final ux = (pNext.x - pCurr.x) / (dNext > 1e-3 ? dNext : 1.0);
        final uy = (pNext.y - pCurr.y) / (dNext > 1e-3 ? dNext : 1.0);

        final opp = _projectRayToContour(pCurr, ux, uy, contour, excludeEdgeIdx: (i - 1 + n) % n);
        if (opp != null && pCurr.distanceTo(opp) >= 10.0) {
          // Snap to an existing opposite vertex if close (< 3mm)
          final snapped = _snapToNearestVertex(opp, contour, toleranceMm: 3.0);
          results.add(
            AutoFoldCandidate(
              p1: pCurr,
              p2: snapped,
              isFlange: true,
              offsetMm: double.parse(dPrev.toStringAsFixed(1)),
              referenceEdgeP1: pCurr,
              referenceEdgeP2: pPrev,
              label: 'FLANGE ${dPrev.toStringAsFixed(0)}mm',
            ),
          );
        }
      }
    }

    return results;
  }

  static CadPoint2D _snapToNearestVertex(CadPoint2D pt, List<CadPoint2D> contour, {double toleranceMm = 3.0}) {
    for (final v in contour) {
      if (v.distanceTo(pt) <= toleranceMm) {
        return v;
      }
    }
    return pt;
  }

  static CadPoint2D? _projectRayToContour(
    CadPoint2D start,
    double ux,
    double uy,
    List<CadPoint2D> contour, {
    int? excludeEdgeIdx,
  }) {
    double minT = double.infinity;
    CadPoint2D? bestHit;
    final n = contour.length;

    for (int i = 0; i < n; i++) {
      if (excludeEdgeIdx != null && (i == excludeEdgeIdx || i == (excludeEdgeIdx - 1 + n) % n)) {
        continue;
      }
      final e1 = contour[i];
      final e2 = contour[(i + 1) % n];
      final vx = e2.x - e1.x;
      final vy = e2.y - e1.y;

      final denom = ux * vy - uy * vx;
      if (denom.abs() < 1e-6) continue;

      final t = ((e1.x - start.x) * vy - (e1.y - start.y) * vx) / denom;
      final u = ((e1.x - start.x) * uy - (e1.y - start.y) * ux) / denom;

      if (t > 1.0 && u >= 0.0 && u <= 1.0 && t < minT) {
        minT = t;
        bestHit = CadPoint2D(start.x + t * ux, start.y + t * uy);
      }
    }

    return bestHit;
  }

  static bool _segmentCrossesContour(
    CadPoint2D p1,
    CadPoint2D p2,
    List<CadPoint2D> contour,
    int idxA,
    int idxB,
  ) {
    final n = contour.length;
    for (int i = 0; i < n; i++) {
      if (i == idxA || i == (idxA - 1 + n) % n || i == idxB || i == (idxB - 1 + n) % n) {
        continue;
      }
      final e1 = contour[i];
      final e2 = contour[(i + 1) % n];
      if (_linesIntersect(p1, p2, e1, e2)) {
        return true;
      }
    }
    return false;
  }

  static bool _linesIntersect(CadPoint2D a1, CadPoint2D a2, CadPoint2D b1, CadPoint2D b2) {
    final d1 = _crossProduct(b2.x - b1.x, b2.y - b1.y, a1.x - b1.x, a1.y - b1.y);
    final d2 = _crossProduct(b2.x - b1.x, b2.y - b1.y, a2.x - b1.x, a2.y - b1.y);
    final d3 = _crossProduct(a2.x - a1.x, a2.y - a1.y, b1.x - a1.x, b1.y - a1.y);
    final d4 = _crossProduct(a2.x - a1.x, a2.y - a1.y, b2.x - a1.x, b2.y - a1.y);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    return false;
  }

  static double _crossProduct(double x1, double y1, double x2, double y2) => x1 * y2 - y1 * x2;

  static bool _isPointInPoly(CadPoint2D pt, List<CadPoint2D> poly) {
    if (poly.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].x, yi = poly[i].y;
      final xj = poly[j].x, yj = poly[j].y;
      final intersect =
          ((yi > pt.y) != (yj > pt.y)) &&
          (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static double _distToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y);
    if (l2 < 1e-4) return p.distanceTo(a);
    final t = math.max(
      0.0,
      math.min(
        1.0,
        ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2,
      ),
    );
    final proj = CadPoint2D(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
    return p.distanceTo(proj);
  }
}
