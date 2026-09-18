// =============================================================================
// canvas_reference_painter.dart
//
// Modular Canvas Painter for Reference & Construction Geometry
// per Phase 1 Master Guide Sections 12, 13, 14, 16 & Set 01, Set 05.
//
// Renders:
// - Centerlines (CENTER_X, CENTER_Y) with dashed pattern & "CL" badge
// - Reference Edges (EDGE_LEFT, EDGE_RIGHT, EDGE_BOTTOM, EDGE_TOP)
// - Custom user construction lines & points
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/cad_primitives.dart';
import '../../../models/constraints/reference_geometry.dart';

class CanvasReferencePainter {
  /// Renders all active reference and construction geometries onto the 2D CAD canvas
  static void paint({
    required Canvas canvas,
    required Size size,
    required List<ReferenceGeometry> references,
    required Offset Function(CadPoint2D) cadToScreen,
    bool isDarkTheme = false,
  }) {
    if (references.isEmpty) return;

    final centerlinePaint = Paint()
      ..color = isDarkTheme ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    final refEdgePaint = Paint()
      ..color = isDarkTheme
          ? const Color(0xFFF59E0B).withValues(alpha: 0.7)
          : const Color(0xFFD97706).withValues(alpha: 0.7)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    // OnShape-standard cyan for construction lines
    final constructionPaint = Paint()
      ..color = const Color(0xFF00BCD4) // Cyan — construction line standard
      ..strokeWidth = 0.85
      ..style = PaintingStyle.stroke;

    for (final ref in references) {
      if (!ref.isVisible) continue;

      final s1 = cadToScreen(ref.p1);
      final s2 = cadToScreen(ref.p2);

      // Extend infinite reference lines to the visible canvas bounds
      Offset ep1 = s1;
      Offset ep2 = s2;
      if (ref.isInfinite) {
        final dx = s2.dx - s1.dx;
        final dy = s2.dy - s1.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 0.01) {
          final nx = dx / len;
          final ny = dy / len;
          const extend = 5000.0;
          ep1 = Offset(s1.dx - nx * extend, s1.dy - ny * extend);
          ep2 = Offset(s2.dx + nx * extend, s2.dy + ny * extend);
        }
      }

      switch (ref.type) {
        case ReferenceGeometryType.centerline:
          // Dot-dash pattern: long dash + short gap + dot + short gap (ISO centerline)
          _drawDotDashLine(canvas, ep1, ep2, centerlinePaint);
          _drawBadge(
            canvas,
            ref.id == 'CENTER_X' ? 'CL X' : 'CL Y',
            s1,
            const Color(0xFF0284C7),
          );
          break;

        case ReferenceGeometryType.referenceEdge:
          _drawDashedLine(canvas, ep1, ep2, refEdgePaint, dashLen: 6.0, gapLen: 3.0);
          break;

        case ReferenceGeometryType.constructionLine:
        case ReferenceGeometryType.referenceAxis:
          // Cyan dashed construction line (OnShape standard)
          _drawDashedLine(canvas, ep1, ep2, constructionPaint, dashLen: 6.0, gapLen: 4.0);
          break;

        case ReferenceGeometryType.constructionPoint:
          canvas.drawCircle(s1, 3.5, constructionPaint..style = PaintingStyle.fill);
          canvas.drawCircle(s1, 5.0, constructionPaint..style = PaintingStyle.stroke);
          break;
      }
    }
  }

  static void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dashLen = 6.0,
    double gapLen = 4.0,
  }) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalLen = (p2 - p1).distance;
    if (totalLen < 1e-4) return;

    final ux = dx / totalLen;
    final uy = dy / totalLen;

    double current = 0.0;
    while (current < totalLen) {
      final start = Offset(p1.dx + ux * current, p1.dy + uy * current);
      final endDist = (current + dashLen).clamp(0.0, totalLen);
      final end = Offset(p1.dx + ux * endDist, p1.dy + uy * endDist);
      canvas.drawLine(start, end, paint);
      current += dashLen + gapLen;
    }
  }

  /// ISO 128 centerline: long-dash (12) short-gap (3) dot (2) short-gap (3) repeat
  static void _drawDotDashLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const longDash = 12.0;
    const dot = 2.0;
    const gap = 3.0;
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalLen = math.sqrt(dx * dx + dy * dy);
    if (totalLen < 1e-4) return;
    final ux = dx / totalLen;
    final uy = dy / totalLen;
    double cur = 0.0;
    while (cur < totalLen) {
      // Long dash
      final d1 = cur;
      final d2 = (cur + longDash).clamp(0.0, totalLen);
      canvas.drawLine(
        Offset(p1.dx + ux * d1, p1.dy + uy * d1),
        Offset(p1.dx + ux * d2, p1.dy + uy * d2),
        paint,
      );
      cur += longDash + gap;
      if (cur >= totalLen) break;
      // Dot
      final d3 = cur;
      final d4 = (cur + dot).clamp(0.0, totalLen);
      canvas.drawLine(
        Offset(p1.dx + ux * d3, p1.dy + uy * d3),
        Offset(p1.dx + ux * d4, p1.dy + uy * d4),
        paint,
      );
      cur += dot + gap;
    }
  }

  static void _drawBadge(Canvas canvas, String text, Offset pos, Color color) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 8.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(pos.dx + 16, pos.dy),
        width: textPainter.width + 6,
        height: textPainter.height + 4,
      ),
      const Radius.circular(3),
    );

    canvas.drawRRect(
      bgRect,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    textPainter.paint(
      canvas,
      Offset(bgRect.left + 3, bgRect.top + 2),
    );
  }
}
