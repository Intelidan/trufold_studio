// =============================================================================
// associative_dimension_engine.dart
//
// Associative Dimensioning Engine per Master Guide Step 6 (#19).
// Computes witness / extension lines, dimension lines, architectural ticks /
// arrowheads, text formatting, and geometry association for 2D CAD dimensions.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/cad_dimension.dart';
import '../models/cad_primitives.dart';
import '../models/canvas_display_settings.dart';
import '../models/dsf_document.dart';

/// Computed geometric layout for rendering a CadDimension
class ResolvedDimensionLayout {
  final CadDimension dimension;
  final Offset witnessAStart;
  final Offset witnessAEnd;
  final Offset witnessBStart;
  final Offset witnessBEnd;
  final Offset dimLineStart;
  final Offset dimLineEnd;
  final List<Offset> arrowA; // 3 points forming arrow triangle or 2 points for tick
  final List<Offset> arrowB;
  final Offset textCenter;
  final double textAngle;
  final String displayText;
  final Rect hitBox;

  const ResolvedDimensionLayout({
    required this.dimension,
    required this.witnessAStart,
    required this.witnessAEnd,
    required this.witnessBStart,
    required this.witnessBEnd,
    required this.dimLineStart,
    required this.dimLineEnd,
    required this.arrowA,
    required this.arrowB,
    required this.textCenter,
    required this.textAngle,
    required this.displayText,
    required this.hitBox,
  });
}

class AssociativeDimensionEngine {
  /// Format the dimension measurement text including prefixes, tolerances, and units
  static String formatDimensionText(CadDimension dim, [CanvasDisplaySettings? settings]) {
    if (dim.overrideText != null && dim.overrideText!.isNotEmpty) {
      return dim.overrideText!;
    }

    final buffer = StringBuffer();
    if (dim.prefix != null && dim.prefix!.isNotEmpty) {
      buffer.write('${dim.prefix} ');
    } else {
      if (dim.type == CadDimensionType.radius) {
        buffer.write('R');
      } else if (dim.type == CadDimensionType.diameter) {
        buffer.write('Ø');
      } else if (dim.type == CadDimensionType.arcLength) {
        buffer.write('⌒');
      }
    }

    // Format number
    final val = dim.measuredValue;
    if (dim.type == CadDimensionType.angular) {
      buffer.write('${val.toStringAsFixed(1)}°');
    } else if (settings != null) {
      buffer.write(formatMeasure(val, settings));
    } else {
      buffer.write(val.toStringAsFixed(1));
    }

    // Tolerances
    if (dim.toleranceUpper != null || dim.toleranceLower != null) {
      final u = dim.toleranceUpper ?? 0.0;
      final l = dim.toleranceLower ?? 0.0;
      if ((u.abs() - l.abs()).abs() < 1e-4 && (u != 0.0 || l != 0.0)) {
        buffer.write(' ±${u.abs().toStringAsFixed(2)}');
      } else {
        buffer.write(' +${u.toStringAsFixed(2)} / -${l.abs().toStringAsFixed(2)}');
      }
    }

    if (dim.suffix != null && dim.suffix!.isNotEmpty) {
      buffer.write(' ${dim.suffix}');
    }

    return buffer.toString();
  }

  /// Projects point [p] perpendicularly onto the line segment passing through [e1] and [e2].
  static CadPoint2D projectPointToSegmentLine(CadPoint2D p, CadPoint2D e1, CadPoint2D e2) {
    final dx = e2.x - e1.x;
    final dy = e2.y - e1.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return e1;
    final t = ((p.x - e1.x) * dx + (p.y - e1.y) * dy) / lenSq;
    return CadPoint2D(e1.x + t * dx, e1.y + t * dy);
  }

  /// Resolves the two endpoints of an edge entity (bend, cut line, contour segment, or face edge).
  static (CadPoint2D, CadPoint2D)? resolveEdgeSegment(String? edgeId, DsfDocument doc) {
    if (edgeId == null) return null;

    // Check bends
    for (final b in doc.bends) {
      if (b.id == edgeId) return (b.p1, b.p2);
    }
    // Check cut lines
    for (final c in doc.cutLines) {
      if (c.id == edgeId) return (c.p1, c.p2);
    }
    // Check outer contour edges (format CONTOUR_EDGE_i)
    if (edgeId.startsWith('CONTOUR_EDGE_')) {
      final index = int.tryParse(edgeId.replaceFirst('CONTOUR_EDGE_', ''));
      if (index != null && index >= 0 && index < doc.outerContour.length) {
        final p1 = doc.outerContour[index];
        final p2 = doc.outerContour[(index + 1) % doc.outerContour.length];
        return (p1, p2);
      }
    }
    // Fallback: check faces
    if (edgeId.startsWith('FACE_') && edgeId.contains('_EDGE_')) {
      final parts = edgeId.split('_EDGE_');
      final faceId = parts[0].replaceFirst('FACE_', '');
      final edgeIdx = int.tryParse(parts[1]);
      final f = doc.faces.where((face) => face.id == faceId).firstOrNull;
      if (f != null && edgeIdx != null && edgeIdx >= 0 && edgeIdx < f.vertices.length) {
        final p1 = f.vertices[edgeIdx];
        final p2 = f.vertices[(edgeIdx + 1) % f.vertices.length];
        return (p1, p2);
      }
    }
    for (final f in doc.faces) {
      if (f.id == edgeId && f.vertices.length >= 2) {
        return (f.vertices[0], f.vertices[1]);
      }
    }
    return null;
  }

  /// Resolves the actual 2D attachment point of an anchor from the live DsfDocument.
  static CadPoint2D? resolveAnchorPoint({
    required DsfDocument doc,
    required String? entityId,
    required CadAnchorType? anchorType,
    CadPoint2D? fallbackPoint,
  }) {
    return CadDimension.resolveAnchorPoint(
      doc: doc,
      entityId: entityId,
      anchorType: anchorType,
      fallbackPoint: fallbackPoint,
    );
  }

  /// Searches for the closest entity anchor point (punch center/quadrant, bend endpoint/midpoint,
  /// cut line endpoint/midpoint, arc center/start/end/midpoint, contour corner vertex, contour edge)
  /// within [toleranceMm] of [pt].
  static ({String? entityId, CadAnchorType? anchorType, CadPoint2D point})? findAnchorAt(
    CadPoint2D pt,
    DsfDocument doc, {
    double toleranceMm = 8.0,
  }) {
    String? bestEntityId;
    CadAnchorType? bestAnchorType;
    CadPoint2D? bestPoint;
    double bestDist = toleranceMm;

    // 1. Punches: center and quadrants
    for (final p in doc.allPunchesRaw) {
      final dCenter = pt.distanceTo(p.center);
      final effRad = p.isRound ? p.widthMm / 2.0 : math.max(p.widthMm, p.lengthMm) / 2.0;
      if (dCenter <= math.max(toleranceMm, effRad + 2.0) && dCenter < bestDist) {
        bestDist = dCenter;
        bestEntityId = p.id;
        bestAnchorType = CadAnchorType.center;
        bestPoint = p.center;
      }
    }

    // 2. Contour corner vertices
    for (int i = 0; i < doc.outerContour.length; i++) {
      final v = doc.outerContour[i];
      final d = pt.distanceTo(v);
      if (d <= toleranceMm && d < bestDist) {
        bestDist = d;
        bestEntityId = 'CONTOUR_VERTEX_$i';
        bestAnchorType = CadAnchorType.endpoint;
        bestPoint = v;
      }
    }

    // 3. Bends: endpoints and midpoints
    for (final b in doc.bends) {
      final d1 = pt.distanceTo(b.p1);
      if (d1 <= toleranceMm && d1 < bestDist) {
        bestDist = d1;
        bestEntityId = b.id;
        bestAnchorType = CadAnchorType.startPoint;
        bestPoint = b.p1;
      }
      final d2 = pt.distanceTo(b.p2);
      if (d2 <= toleranceMm && d2 < bestDist) {
        bestDist = d2;
        bestEntityId = b.id;
        bestAnchorType = CadAnchorType.endPoint;
        bestPoint = b.p2;
      }
      final dMid = pt.distanceTo(b.midpoint);
      if (dMid <= toleranceMm && dMid < bestDist) {
        bestDist = dMid;
        bestEntityId = b.id;
        bestAnchorType = CadAnchorType.midpoint;
        bestPoint = b.midpoint;
      }
    }

    // 4. Cut lines: endpoints and midpoints
    for (final c in doc.cutLines) {
      final d1 = pt.distanceTo(c.p1);
      if (d1 <= toleranceMm && d1 < bestDist) {
        bestDist = d1;
        bestEntityId = c.id;
        bestAnchorType = CadAnchorType.startPoint;
        bestPoint = c.p1;
      }
      final d2 = pt.distanceTo(c.p2);
      if (d2 <= toleranceMm && d2 < bestDist) {
        bestDist = d2;
        bestEntityId = c.id;
        bestAnchorType = CadAnchorType.endPoint;
        bestPoint = c.p2;
      }
      final dMid = pt.distanceTo(c.midpoint);
      if (dMid <= toleranceMm && dMid < bestDist) {
        bestDist = dMid;
        bestEntityId = c.id;
        bestAnchorType = CadAnchorType.midpoint;
        bestPoint = c.midpoint;
      }
    }

    // 5. Arcs: center, endpoints, midpoint
    for (final a in doc.arcs) {
      final dCenter = pt.distanceTo(a.center);
      if (dCenter <= toleranceMm && dCenter < bestDist) {
        bestDist = dCenter;
        bestEntityId = a.id;
        bestAnchorType = CadAnchorType.center;
        bestPoint = a.center;
      }
      final dStart = pt.distanceTo(a.startPoint);
      if (dStart <= toleranceMm && dStart < bestDist) {
        bestDist = dStart;
        bestEntityId = a.id;
        bestAnchorType = CadAnchorType.startPoint;
        bestPoint = a.startPoint;
      }
      final dEnd = pt.distanceTo(a.endPoint);
      if (dEnd <= toleranceMm && dEnd < bestDist) {
        bestDist = dEnd;
        bestEntityId = a.id;
        bestAnchorType = CadAnchorType.endPoint;
        bestPoint = a.endPoint;
      }
    }

    // If a discrete point was found, return it
    if (bestEntityId != null && bestPoint != null) {
      return (entityId: bestEntityId, anchorType: bestAnchorType, point: bestPoint);
    }

    // 6. Linear segments (edges): check outer contour edges
    if (doc.outerContour.length >= 2) {
      for (int i = 0; i < doc.outerContour.length; i++) {
        final c1 = doc.outerContour[i];
        final c2 = doc.outerContour[(i + 1) % doc.outerContour.length];
        final d = _distToSegment(pt, c1, c2);
        if (d <= toleranceMm && d < bestDist) {
          bestDist = d;
          bestEntityId = 'CONTOUR_EDGE_$i';
          bestAnchorType = CadAnchorType.perpendicular;
          bestPoint = projectPointToSegmentLine(pt, c1, c2);
        }
      }
    }

    // 7. Linear segments: bends
    for (final b in doc.bends) {
      final d = _distToSegment(pt, b.p1, b.p2);
      if (d <= toleranceMm && d < bestDist) {
        bestDist = d;
        bestEntityId = b.id;
        bestAnchorType = CadAnchorType.perpendicular;
        bestPoint = projectPointToSegmentLine(pt, b.p1, b.p2);
      }
    }

    // 8. Linear segments: cut lines
    for (final c in doc.cutLines) {
      final d = _distToSegment(pt, c.p1, c.p2);
      if (d <= toleranceMm && d < bestDist) {
        bestDist = d;
        bestEntityId = c.id;
        bestAnchorType = CadAnchorType.perpendicular;
        bestPoint = projectPointToSegmentLine(pt, c.p1, c.p2);
      }
    }

    if (bestEntityId != null && bestPoint != null) {
      return (entityId: bestEntityId, anchorType: bestAnchorType, point: bestPoint);
    }

    return null;
  }

  static double _distToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return p.distanceTo(a);
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq).clamp(0.0, 1.0);
    final proj = CadPoint2D(a.x + t * dx, a.y + t * dy);
    return p.distanceTo(proj);
  }

  /// Ensures that unreferenced or legacy dimensions have their entity and anchor
  /// references bound to the actual geometry beneath [dim.pointA] and [dim.pointB].
  static CadDimension ensureDimensionBound(CadDimension dim, DsfDocument doc) {
    String? refA = dim.referenceAId;
    String? refB = dim.referenceBId;
    CadAnchorType? anchorA = dim.anchorTypeA;
    CadAnchorType? anchorB = dim.anchorTypeB;

    if (refA == null && dim.pointA != null) {
      final foundA = findAnchorAt(dim.pointA!, doc, toleranceMm: 6.0);
      if (foundA != null) {
        refA = foundA.entityId;
        anchorA = foundA.anchorType;
      }
    }

    if (refB == null && dim.pointB != null) {
      final foundB = findAnchorAt(dim.pointB!, doc, toleranceMm: 6.0);
      if (foundB != null) {
        refB = foundB.entityId;
        anchorB = foundB.anchorType;
      }
    }

    if (refA != dim.referenceAId || refB != dim.referenceBId || anchorA != dim.anchorTypeA || anchorB != dim.anchorTypeB) {
      return dim.copyWith(
        referenceAId: refA,
        referenceBId: refB,
        anchorTypeA: anchorA,
        anchorTypeB: anchorB,
      );
    }
    return dim;
  }

  /// Extracts geometric points A and B associated with the dimension references,
  /// or falls back to explicit pointA / pointB
  static ({CadPoint2D pA, CadPoint2D pB, double value}) resolveAssociation(CadDimension dim, DsfDocument doc) {
    CadPoint2D? ptA = dim.pointA;
    CadPoint2D? ptB = dim.pointB;
    double measured = dim.measuredValue;

    // 1. Single edge / segment (e.g. 1-click segment dimension where referenceAId == referenceBId)
    final singleRefId = (dim.referenceAId != null && dim.referenceAId == dim.referenceBId)
        ? dim.referenceAId
        : dim.referenceEntityId;
    if (singleRefId != null && (dim.referenceAId == null || dim.referenceBId == null || dim.referenceAId == dim.referenceBId)) {
      final edgeSeg = resolveEdgeSegment(singleRefId, doc);
      if (edgeSeg != null) {
        ptA = edgeSeg.$1;
        ptB = edgeSeg.$2;
        measured = ptA.distanceTo(ptB);
        return (pA: ptA, pB: ptB, value: measured);
      } else if (dim.pointA != null && dim.pointB != null) {
        ptA = dim.pointA;
        ptB = dim.pointB;
        measured = ptA!.distanceTo(ptB!);
        return (pA: ptA, pB: ptB, value: measured);
      }
    }

    // 2. Point-to-Edge dimension:
    // If dim.type == CadDimensionType.holeToEdge OR one reference is a punch and the other is an edge:
    final punchId = dim.referenceAId != null && doc.punches.any((p) => p.id == dim.referenceAId)
        ? dim.referenceAId
        : (dim.referenceBId != null && doc.punches.any((p) => p.id == dim.referenceBId) ? dim.referenceBId : null);
    final edgeCandidateId = punchId == dim.referenceAId ? dim.referenceBId : dim.referenceAId;

    if (punchId != null && edgeCandidateId != null) {
      final punch = doc.punches.where((p) => p.id == punchId).firstOrNull;
      final edgeSeg = resolveEdgeSegment(edgeCandidateId, doc);
      final edgeAnchor = punchId == dim.referenceAId ? dim.anchorTypeB : dim.anchorTypeA;
      final isPointAnchorOnEdge = edgeAnchor == CadAnchorType.startPoint ||
          edgeAnchor == CadAnchorType.endPoint ||
          edgeAnchor == CadAnchorType.midpoint;
      if (punch != null && edgeSeg != null && (dim.type == CadDimensionType.holeToEdge || !isPointAnchorOnEdge)) {
        final punchCenter = punch.center;
        final proj = projectPointToSegmentLine(punchCenter, edgeSeg.$1, edgeSeg.$2);
        if (dim.referenceAId == punchId) {
          ptA = punchCenter;
          ptB = proj;
        } else {
          ptA = proj;
          ptB = punchCenter;
        }
        if (dim.type == CadDimensionType.horizontal) {
          measured = (ptB.x - ptA.x).abs();
        } else if (dim.type == CadDimensionType.vertical) {
          measured = (ptB.y - ptA.y).abs();
        } else {
          measured = punchCenter.distanceTo(proj);
        }
        return (pA: ptA, pB: ptB, value: measured);
      }
    }

    // Also support general point-to-edge where reference is CONTOUR_EDGE_ or anchor is perpendicular:
    final isEdgeA = dim.referenceAId != null &&
        (dim.referenceAId!.toUpperCase().startsWith('CONTOUR_EDGE_') ||
            dim.referenceAId!.startsWith('FACE_') ||
            dim.anchorTypeA == CadAnchorType.perpendicular);
    final isEdgeB = dim.referenceBId != null &&
        (dim.referenceBId!.toUpperCase().startsWith('CONTOUR_EDGE_') ||
            dim.referenceBId!.startsWith('FACE_') ||
            dim.anchorTypeB == CadAnchorType.perpendicular);

    if (isEdgeA != isEdgeB) {
      final edgeRefId = isEdgeA ? dim.referenceAId : dim.referenceBId;
      final pointRefId = isEdgeA ? dim.referenceBId : dim.referenceAId;
      final pointAnchor = isEdgeA ? dim.anchorTypeB : dim.anchorTypeA;
      final pointFallback = isEdgeA ? dim.pointB : dim.pointA;

      final pointPt = resolveAnchorPoint(
        doc: doc,
        entityId: pointRefId,
        anchorType: pointAnchor,
        fallbackPoint: pointFallback,
      );
      final edgeSeg = resolveEdgeSegment(edgeRefId, doc);

      if (pointPt != null && edgeSeg != null) {
        final proj = projectPointToSegmentLine(pointPt, edgeSeg.$1, edgeSeg.$2);
        if (isEdgeA) {
          ptA = proj;
          ptB = pointPt;
        } else {
          ptA = pointPt;
          ptB = proj;
        }
        if (dim.type == CadDimensionType.horizontal) {
          measured = (ptB.x - ptA.x).abs();
        } else if (dim.type == CadDimensionType.vertical) {
          measured = (ptB.y - ptA.y).abs();
        } else {
          measured = pointPt.distanceTo(proj);
        }
        return (pA: ptA, pB: ptB, value: measured);
      }
    }

    // 3. General two-anchor resolution:
    if (dim.referenceAId != null) {
      final refA = resolveAnchorPoint(
        doc: doc,
        entityId: dim.referenceAId,
        anchorType: dim.anchorTypeA,
        fallbackPoint: dim.pointA,
      );
      if (refA != null) ptA = refA;
    }
    if (dim.referenceBId != null) {
      final refB = resolveAnchorPoint(
        doc: doc,
        entityId: dim.referenceBId,
        anchorType: dim.anchorTypeB,
        fallbackPoint: dim.pointB,
      );
      if (refB != null) ptB = refB;
    }

    // Handle overall blank width / length dimensions
    if (dim.type == CadDimensionType.overall) {
      ptA = const CadPoint2D(0, 0);
      ptB = CadPoint2D(doc.blankWidthMm, 0);
      measured = doc.blankWidthMm;
    }

    ptA ??= const CadPoint2D(0, 0);
    ptB ??= CadPoint2D(ptA.x + 50.0, ptA.y);

    // Compute updated measured value based on resolved points & type
    switch (dim.type) {
      case CadDimensionType.horizontal:
        measured = (ptB.x - ptA.x).abs();
        break;
      case CadDimensionType.vertical:
        measured = (ptB.y - ptA.y).abs();
        break;
      case CadDimensionType.holeToHole:
        final dx = (ptB.x - ptA.x).abs();
        final dy = (ptB.y - ptA.y).abs();
        if (dx > 1.4 * dy) {
          measured = dx;
        } else if (dy > 1.4 * dx) {
          measured = dy;
        } else {
          measured = math.sqrt(dx * dx + dy * dy);
        }
        break;
      case CadDimensionType.aligned:
      case CadDimensionType.centerToCenter:
      case CadDimensionType.holeToEdge:
      case CadDimensionType.bendToEdge:
      case CadDimensionType.bendToBend:
      case CadDimensionType.edgeToEdge:
        measured = math.sqrt(math.pow(ptB.x - ptA.x, 2) + math.pow(ptB.y - ptA.y, 2));
        break;
      case CadDimensionType.radius:
      case CadDimensionType.diameter:
      case CadDimensionType.angular:
      case CadDimensionType.arcLength:
      case CadDimensionType.overall:
        measured = dim.measuredValue > 0 ? dim.measuredValue : (ptB.x - ptA.x).abs();
        break;
    }

    return (pA: ptA, pB: ptB, value: measured);
  }

  /// Solves complete 2D layout geometry for rendering and hit-testing
  static ResolvedDimensionLayout resolveLayout(
    CadDimension dim,
    DsfDocument doc, {
    double scale = 1.0,
    CanvasDisplaySettings? settings,
  }) {
    final assoc = resolveAssociation(dim, doc);
    final pA = assoc.pA;
    final pB = assoc.pB;
    final measured = assoc.value;

    final displayText = formatDimensionText(
      dim.copyWith(measuredValue: measured),
      settings,
    );

    final offsetDist = dim.dimensionLineOffset;
    final overshoot = dim.extensionLineOvershoot;
    const witnessGap = 2.0;

    Offset wAStart, wAEnd, wBStart, wBEnd, dStart, dEnd;
    double textAngle = 0.0;

    // Determine effective dimension orientation
    bool isHorizontal = dim.type == CadDimensionType.horizontal;
    bool isVertical = dim.type == CadDimensionType.vertical;

    if (!isHorizontal && !isVertical) {
      if (dim.type == CadDimensionType.holeToEdge) {
        final dy = (pB.y - pA.y).abs();
        final dx = (pB.x - pA.x).abs();
        if (dy < 0.05 || (dx > 0 && dy / dx < 0.1)) {
          isHorizontal = true;
        } else if (dx < 0.05 || (dy > 0 && dx / dy < 0.1)) {
          isVertical = true;
        }
      } else if (dim.type == CadDimensionType.holeToHole) {
        final dx = (pB.x - pA.x).abs();
        final dy = (pB.y - pA.y).abs();
        if (dx > 1.4 * dy) {
          isHorizontal = true;
        } else if (dy > 1.4 * dx) {
          isVertical = true;
        }
      }
    }

    if (isHorizontal) {
      final yDim = (math.min(pA.y, pB.y)) - offsetDist;
      wAStart = Offset(pA.x, pA.y - (offsetDist > 0 ? witnessGap : -witnessGap));
      wAEnd = Offset(pA.x, yDim - (offsetDist > 0 ? overshoot : -overshoot));
      wBStart = Offset(pB.x, pB.y - (offsetDist > 0 ? witnessGap : -witnessGap));
      wBEnd = Offset(pB.x, yDim - (offsetDist > 0 ? overshoot : -overshoot));
      dStart = Offset(pA.x, yDim);
      dEnd = Offset(pB.x, yDim);
      textAngle = 0.0;
    } else if (isVertical) {
      final xDim = (math.min(pA.x, pB.x)) - offsetDist;
      wAStart = Offset(pA.x - (offsetDist > 0 ? witnessGap : -witnessGap), pA.y);
      wAEnd = Offset(xDim - (offsetDist > 0 ? overshoot : -overshoot), pA.y);
      wBStart = Offset(pB.x - (offsetDist > 0 ? witnessGap : -witnessGap), pB.y);
      wBEnd = Offset(xDim - (offsetDist > 0 ? overshoot : -overshoot), pB.y);
      dStart = Offset(xDim, pA.y);
      dEnd = Offset(xDim, pB.y);
      textAngle = -math.pi / 2.0;
    } else {
      // Aligned / center-to-center / oblique
      final dx = pB.x - pA.x;
      final dy = pB.y - pA.y;
      final len = math.sqrt(dx * dx + dy * dy);
      double nx = 0.0, ny = -1.0;
      if (len > 1e-4) {
        nx = -dy / len;
        ny = dx / len;
      }

      final s = offsetDist >= 0 ? 1.0 : -1.0;
      final offX = nx * offsetDist;
      final offY = ny * offsetDist;
      final overX = nx * overshoot * s;
      final overY = ny * overshoot * s;
      final gapX = nx * witnessGap * s;
      final gapY = ny * witnessGap * s;

      wAStart = Offset(pA.x + gapX, pA.y + gapY);
      wAEnd = Offset(pA.x + offX + overX, pA.y + offY + overY);
      wBStart = Offset(pB.x + gapX, pB.y + gapY);
      wBEnd = Offset(pB.x + offX + overX, pB.y + offY + overY);

      dStart = Offset(pA.x + offX, pA.y + offY);
      dEnd = Offset(pB.x + offX, pB.y + offY);

      textAngle = math.atan2(dEnd.dy - dStart.dy, dEnd.dx - dStart.dx);
      // Keep text upright
      if (textAngle > math.pi / 2.0 || textAngle < -math.pi / 2.0) {
        textAngle += math.pi;
      }
    }

    // Arrows at dStart and dEnd
    final arrowA = _buildArrowHead(dStart, dEnd, 6.0);
    final arrowB = _buildArrowHead(dEnd, dStart, 6.0);

    // Text position centered with userOffset
    final midPoint = Offset((dStart.dx + dEnd.dx) / 2.0 + dim.userOffset.dx, (dStart.dy + dEnd.dy) / 2.0 + dim.userOffset.dy);

    // Hitbox for double-click driving & selection
    final hitBox = Rect.fromCenter(center: midPoint, width: math.max(60.0, displayText.length * 9.0), height: 28.0);

    return ResolvedDimensionLayout(
      dimension: dim,
      witnessAStart: wAStart,
      witnessAEnd: wAEnd,
      witnessBStart: wBStart,
      witnessBEnd: wBEnd,
      dimLineStart: dStart,
      dimLineEnd: dEnd,
      arrowA: arrowA,
      arrowB: arrowB,
      textCenter: midPoint,
      textAngle: textAngle,
      displayText: displayText,
      hitBox: hitBox,
    );
  }

  static List<Offset> _buildArrowHead(Offset tip, Offset from, double arrowLength) {
    final dx = from.dx - tip.dx;
    final dy = from.dy - tip.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-4) return [tip, tip, tip];

    final ux = dx / len;
    final uy = dy / len;
    // Perpendicular vector
    final px = -uy;
    final py = ux;

    const arrowHalfWidth = 2.0;
    final base = Offset(tip.dx + ux * arrowLength, tip.dy + uy * arrowLength);
    final p1 = Offset(base.dx + px * arrowHalfWidth, base.dy + py * arrowHalfWidth);
    final p2 = Offset(base.dx - px * arrowHalfWidth, base.dy - py * arrowHalfWidth);

    return [tip, p1, p2];
  }
}
