// =============================================================================
// cms_2d_overlay_painter.dart
//
// CustomPainter for 2D drafting canvas rendering synchronized glows, pulses,
// suggested bend lines, and port badges per
// TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 15, 16, 25).
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/cms/cms_physical_port.dart';
import '../../../models/cms/cms_ux_state.dart';

class Cms2DOverlayPainter extends CustomPainter {
  final List<CmsPhysicalPort> ports;
  final List<CmsSuggestedBend> suggestedBends;
  final CmsVisualFocus focus;
  final Offset Function(double x, double y) worldToScreen;

  Cms2DOverlayPainter({this.ports = const [], this.suggestedBends = const [], required this.focus, required this.worldToScreen});

  @override
  void paint(Canvas canvas, Size size) {
    _paintSuggestedBends(canvas);
    _paintPorts(canvas);
  }

  void _paintSuggestedBends(Canvas canvas) {
    if (suggestedBends.isEmpty) return;

    final bendPaint = Paint()
      ..color =
          const Color(0xFF0284C7) // Sky blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final flangePaint = Paint()
      ..color =
          const Color(0xFF0D9488) // Teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final dotFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (final bend in suggestedBends) {
      final s1 = worldToScreen(bend.p1.x, bend.p1.y);
      final s2 = worldToScreen(bend.p2.x, bend.p2.y);
      final isFlange = bend.isFlange;
      final activePaint = isFlange ? flangePaint : bendPaint;

      // Subtle glow behind candidate line
      final glowPaint = Paint()
        ..color = (isFlange ? const Color(0xFF0D9488) : const Color(0xFF0284C7)).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      _drawDashedLine(canvas, s1, s2, glowPaint, dash: 8.0, gap: 4.0);

      // Primary dashed bend line
      _drawDashedLine(canvas, s1, s2, activePaint, dash: 8.0, gap: 4.0);

      // Terminal anchor dots
      canvas.drawCircle(s1, 4.0, dotFill);
      canvas.drawCircle(s1, 4.0, activePaint);
      canvas.drawCircle(s2, 4.0, dotFill);
      canvas.drawCircle(s2, 4.0, activePaint);

      // Midpoint badge
      final mid = Offset((s1.dx + s2.dx) / 2, (s1.dy + s2.dy) / 2);
      final labelText = '${bend.label} (${bend.displayAngleDeg.toInt()}°)';
      final textSpan = TextSpan(
        text: labelText,
        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();

      const padX = 6.0;
      const padY = 3.0;
      final badgeRect = Rect.fromCenter(center: mid, width: textPainter.width + padX * 2, height: textPainter.height + padY * 2);

      final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(5.0));
      final badgeBgPaint = Paint()
        ..color = isFlange ? const Color(0xFF134E4A) : const Color(0xFF0C4A6E)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, badgeBgPaint);

      final badgeBorderPaint = Paint()
        ..color = isFlange ? const Color(0xFF2DD4BF) : const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(rrect, badgeBorderPaint);

      textPainter.paint(canvas, Offset(badgeRect.left + padX, badgeRect.top + padY));
    }
  }

  void _paintPorts(Canvas canvas) {
    if (ports.isEmpty) return;

    final badgePaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..style = PaintingStyle.fill;

    const textStyle = TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.w700, letterSpacing: 0.2);

    for (final port in ports) {
      final isFocused = port.id == focus.activePortId;
      final screenPos = worldToScreen(port.flatCenter.x, port.flatCenter.y);

      // Draw port aperture line passing through coupler hole centers
      if (port.flatP1 != null && port.flatP2 != null) {
        final sP1 = worldToScreen(port.flatP1!.x, port.flatP1!.y);
        final sP2 = worldToScreen(port.flatP2!.x, port.flatP2!.y);

        final linePaint = Paint()
          ..color = isFocused ? const Color(0xFF00E5FF) : const Color(0xFF0284C7).withValues(alpha: 0.75)
          ..strokeWidth = isFocused ? 2.0 : 1.5
          ..style = PaintingStyle.stroke;

        _drawDashedLine(canvas, sP1, sP2, linePaint, dash: 6.0, gap: 4.0);

        final dotPaint = Paint()
          ..color = isFocused ? const Color(0xFF00E5FF) : const Color(0xFF0284C7)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(sP1, 3.5, dotPaint);
        canvas.drawCircle(sP2, 3.5, dotPaint);
      }

      // Draw subtle glowing halo if active
      if (isFocused) {
        final glowPaint = Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
        canvas.drawCircle(screenPos, 22.0, glowPaint);
      }

      // Draw port pill badge
      final label = '${port.id} (${port.nominalWidth.toInt()}×${port.nominalHeight.toInt()})';
      final textSpan = TextSpan(text: label, style: textStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();

      const padX = 8.0;
      const padY = 4.0;
      final badgeRect = Rect.fromCenter(center: screenPos, width: textPainter.width + padX * 2, height: textPainter.height + padY * 2);

      final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(6.0));
      badgePaint.color = isFocused ? const Color(0xFF0284C7) : const Color(0xFF0F172A);
      canvas.drawRRect(rrect, badgePaint);

      // Draw border
      final borderPaint = Paint()
        ..color = isFocused ? Colors.white : const Color(0xFF94A3B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(rrect, borderPaint);

      textPainter.paint(canvas, Offset(badgeRect.left + padX, badgeRect.top + padY));
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {double dash = 6.0, double gap = 4.0}) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalLen = math.sqrt(dx * dx + dy * dy);
    if (totalLen <= 0.001) return;

    final ux = dx / totalLen;
    final uy = dy / totalLen;
    double d = 0.0;

    while (d < totalLen) {
      final segLen = math.min(dash, totalLen - d);
      canvas.drawLine(Offset(p1.dx + ux * d, p1.dy + uy * d), Offset(p1.dx + ux * (d + segLen), p1.dy + uy * (d + segLen)), paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant Cms2DOverlayPainter oldDelegate) {
    return oldDelegate.ports != ports || oldDelegate.suggestedBends != suggestedBends || oldDelegate.focus != focus;
  }
}
