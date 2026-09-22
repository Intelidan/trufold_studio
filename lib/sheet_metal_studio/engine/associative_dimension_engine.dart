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
    for (final f in doc.faces) {
      if (f.id == edgeId && f.vertices.length >= 2) {
        return (f.vertices[0], f.vertices[1]);
      }
    }
    return null;
  }

  /// Extracts geometric points A and B associated with the dimension references,
  /// or falls back to explicit pointA / pointB
  static ({CadPoint2D pA, CadPoint2D pB, double value}) resolveAssociation(CadDimension dim, DsfDocument doc) {
    CadPoint2D? ptA = dim.pointA;
    CadPoint2D? ptB = dim.pointB;
    double measured = dim.measuredValue;

    // Special handling for punch-to-edge dimensions:
    // Project the punch center perpendicularly onto the edge segment so the setback
    // is strictly perpendicular to the edge rather than snapping to the edge midpoint.
    final punchId = dim.referenceAId != null && doc.punches.any((p) => p.id == dim.referenceAId)
        ? dim.referenceAId
        : (dim.referenceBId != null && doc.punches.any((p) => p.id == dim.referenceBId) ? dim.referenceBId : null);
    final edgeId = punchId == dim.referenceAId ? dim.referenceBId : dim.referenceAId;

    if (punchId != null && edgeId != null) {
      final punch = doc.punches.where((p) => p.id == punchId).firstOrNull;
      final edgeSeg = resolveEdgeSegment(edgeId, doc);
      if (punch != null && edgeSeg != null) {
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

    // Resolve reference A
    if (dim.referenceAId != null) {
      final refA = _findEntityCenterOrPoint(dim.referenceAId!, doc);
      if (refA != null) ptA = refA;
    }

    // Resolve reference B
    if (dim.referenceBId != null) {
      final refB = _findEntityCenterOrPoint(dim.referenceBId!, doc);
      if (refB != null) ptB = refB;
    }

    // Handle overall blank width / length dimensions
    if (dim.type == CadDimensionType.overall) {
      ptA = CadPoint2D(0, 0);
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

  static CadPoint2D? _findEntityCenterOrPoint(String id, DsfDocument doc) {
    // Check punches
    for (final p in doc.allPunchesRaw) {
      if (p.id == id) {
        return p.center;
      }
    }
    // Check bends
    for (final b in doc.bends) {
      if (b.id == id) {
        return b.midpoint;
      }
    }
    // Check cut lines
    for (final c in doc.cutLines) {
      if (c.id == id) {
        return c.midpoint;
      }
    }
    // Check contour points (format contour_i)
    if (id.startsWith('contour_')) {
      final index = int.tryParse(id.replaceFirst('contour_', ''));
      if (index != null && index >= 0 && index < doc.outerContour.length) {
        return doc.outerContour[index];
      }
    }
    // Check outer contour edges (format CONTOUR_EDGE_i)
    if (id.startsWith('CONTOUR_EDGE_')) {
      final edgeSeg = resolveEdgeSegment(id, doc);
      if (edgeSeg != null) {
        return CadPoint2D(
          (edgeSeg.$1.x + edgeSeg.$2.x) / 2.0,
          (edgeSeg.$1.y + edgeSeg.$2.y) / 2.0,
        );
      }
    }
    return null;
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

      final offX = nx * offsetDist;
      final offY = ny * offsetDist;
      final overX = nx * overshoot;
      final overY = ny * overshoot;
      final gapX = nx * witnessGap;
      final gapY = ny * witnessGap;

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
