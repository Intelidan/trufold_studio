import 'dart:math' as math;
import 'package:flutter/material.dart';

/// SketchUp 4-way crossed red arrows move badge overlay (SS1)
class AssemblyMoveBadgeOverlayPainter extends CustomPainter {
  final Offset? cursorScreenPos;
  final bool isCopyMode;

  AssemblyMoveBadgeOverlayPainter({
    required this.cursorScreenPos,
    required this.isCopyMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cursorScreenPos == null) return;
    final pos = cursorScreenPos!;

    // 1. High-contrast white silhouette background for in-app mouse pointer (Item 8)
    final bgPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pos - const Offset(7.5, 0), pos + const Offset(7.5, 0), bgPaint);
    canvas.drawLine(pos - const Offset(0, 7.5), pos + const Offset(0, 7.5), bgPaint);

    final bgHeadPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    void bgHead(Offset tip, double angle) {
      final p = Path()
        ..moveTo(tip.dx + 1.0 * math.cos(angle), tip.dy + 1.0 * math.sin(angle))
        ..lineTo(tip.dx - 4.2 * math.cos(angle - 0.55), tip.dy - 4.2 * math.sin(angle - 0.55))
        ..lineTo(tip.dx - 4.2 * math.cos(angle + 0.55), tip.dy - 4.2 * math.sin(angle + 0.55))
        ..close();
      canvas.drawPath(p, bgHeadPaint);
    }

    bgHead(pos + const Offset(8, 0), 0);
    bgHead(pos - const Offset(8, 0), math.pi);
    bgHead(pos - const Offset(0, 8), -math.pi / 2);
    bgHead(pos + const Offset(0, 8), math.pi / 2);

    // 2. Crisp SketchUp Red 4-Way Arrow cursor
    final arrowPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(pos - const Offset(7, 0), pos + const Offset(7, 0), arrowPaint);
    canvas.drawLine(pos - const Offset(0, 7), pos + const Offset(0, 7), arrowPaint);

    final headPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;
    void head(Offset tip, double angle) {
      final p = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 3.5 * math.cos(angle - 0.5), tip.dy - 3.5 * math.sin(angle - 0.5))
        ..lineTo(tip.dx - 3.5 * math.cos(angle + 0.5), tip.dy - 3.5 * math.sin(angle + 0.5))
        ..close();
      canvas.drawPath(p, headPaint);
    }

    head(pos + const Offset(8, 0), 0);
    head(pos - const Offset(8, 0), math.pi);
    head(pos - const Offset(0, 8), -math.pi / 2);
    head(pos + const Offset(0, 8), math.pi / 2);

    if (isCopyMode) {
      final plusPaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..strokeWidth = 2.0;
      final plusPos = pos + const Offset(9, 9);
      canvas.drawCircle(plusPos, 5.0, Paint()..color = Colors.white);
      canvas.drawCircle(
        plusPos,
        5.0,
        Paint()
          ..color = const Color(0xFF1E293B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      canvas.drawLine(plusPos - const Offset(3, 0), plusPos + const Offset(3, 0), plusPaint);
      canvas.drawLine(plusPos - const Offset(0, 3), plusPos + const Offset(0, 3), plusPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyMoveBadgeOverlayPainter old) {
    return old.cursorScreenPos != cursorScreenPos || old.isCopyMode != isCopyMode;
  }
}

/// Interactive SketchUp-Style Camera Rotation (Orbit) Vector Cursor Overlay (SS1)
class AssemblyOrbitCursorPainter extends CustomPainter {
  final Offset? cursorScreenPos;

  AssemblyOrbitCursorPainter({required this.cursorScreenPos});

  @override
  void paint(Canvas canvas, Size size) {
    if (cursorScreenPos == null) return;
    final pos = cursorScreenPos!;

    // 1. High-contrast white silhouette background for crisp visibility over any 3D model geometry
    final bgAxisPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pos - const Offset(0, 11), pos + const Offset(0, 11), bgAxisPaint);

    final bgRingPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.2
      ..style = PaintingStyle.stroke;
    canvas.drawOval(Rect.fromCenter(center: pos, width: 22, height: 11), bgRingPaint);

    // 2. Central vertical axis line (dark slate)
    final axisPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pos - const Offset(0, 10), pos + const Offset(0, 10), axisPaint);

    // 3. Bright Red Orbit Elliptical Loop (matching SS1)
    final redLoopPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawOval(Rect.fromCenter(center: pos, width: 20, height: 9.5), redLoopPaint);

    // 4. Arrowheads on the loop
    final headPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;

    // Bottom front arrowhead pointing right
    final p1 = Path()
      ..moveTo(pos.dx + 6.5, pos.dy + 4.8)
      ..lineTo(pos.dx + 2.0, pos.dy + 1.8)
      ..lineTo(pos.dx + 2.0, pos.dy + 7.8)
      ..close();
    canvas.drawPath(p1, headPaint);

    // Top back arrowhead pointing left
    final p2 = Path()
      ..moveTo(pos.dx - 6.5, pos.dy - 4.8)
      ..lineTo(pos.dx - 2.0, pos.dy - 7.8)
      ..lineTo(pos.dx - 2.0, pos.dy - 1.8)
      ..close();
    canvas.drawPath(p2, headPaint);
  }

  @override
  bool shouldRepaint(covariant AssemblyOrbitCursorPainter old) => old.cursorScreenPos != cursorScreenPos;
}

/// Interactive SketchUp-Style Camera Panning Vector Cursor Overlay (SS1)
class AssemblyPanCursorPainter extends CustomPainter {
  final Offset? cursorScreenPos;

  AssemblyPanCursorPainter({required this.cursorScreenPos});

  @override
  void paint(Canvas canvas, Size size) {
    if (cursorScreenPos == null) return;
    final pos = cursorScreenPos!;

    // 1. High-contrast white silhouette background for the red double arrow and hand
    final bgArrowPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pos + const Offset(-10, -7), pos + const Offset(10, -7), bgArrowPaint);

    final bgHeadPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final bgLeft = Path()
      ..moveTo(pos.dx - 12.5, pos.dy - 7)
      ..lineTo(pos.dx - 7, pos.dy - 11.5)
      ..lineTo(pos.dx - 7, pos.dy - 2.5)
      ..close();
    final bgRight = Path()
      ..moveTo(pos.dx + 12.5, pos.dy - 7)
      ..lineTo(pos.dx + 7, pos.dy - 11.5)
      ..lineTo(pos.dx + 7, pos.dy - 2.5)
      ..close();
    canvas.drawPath(bgLeft, bgHeadPaint);
    canvas.drawPath(bgRight, bgHeadPaint);

    // 2. Red Horizontal Double-Arrow (⟷) (matching SS1)
    final arrowPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pos + const Offset(-9, -7), pos + const Offset(9, -7), arrowPaint);

    final arrowHeadPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;
    final leftHead = Path()
      ..moveTo(pos.dx - 11, pos.dy - 7)
      ..lineTo(pos.dx - 7.5, pos.dy - 10.2)
      ..lineTo(pos.dx - 7.5, pos.dy - 3.8)
      ..close();
    final rightHead = Path()
      ..moveTo(pos.dx + 11, pos.dy - 7)
      ..lineTo(pos.dx + 7.5, pos.dy - 10.2)
      ..lineTo(pos.dx + 7.5, pos.dy - 3.8)
      ..close();
    canvas.drawPath(leftHead, arrowHeadPaint);
    canvas.drawPath(rightHead, arrowHeadPaint);

    // 3. Hand Silhouette White Border
    final handBorderBgPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final handPath = Path()
      ..moveTo(pos.dx - 5.5, pos.dy + 12)
      ..lineTo(pos.dx + 5.5, pos.dy + 12)
      ..lineTo(pos.dx + 6.8, pos.dy + 6.0)
      ..lineTo(pos.dx + 7.5, pos.dy + 1.0)
      ..lineTo(pos.dx + 5.2, pos.dy + 1.0)
      ..lineTo(pos.dx + 4.8, pos.dy - 1.5)
      ..lineTo(pos.dx + 2.5, pos.dy - 1.5)
      ..lineTo(pos.dx + 2.0, pos.dy - 3.5)
      ..lineTo(pos.dx - 0.5, pos.dy - 3.5)
      ..lineTo(pos.dx - 1.0, pos.dy - 1.5)
      ..lineTo(pos.dx - 3.2, pos.dy - 1.5)
      ..lineTo(pos.dx - 4.5, pos.dy + 3.0)
      ..lineTo(pos.dx - 8.0, pos.dy + 3.0)
      ..lineTo(pos.dx - 7.2, pos.dy + 6.5)
      ..lineTo(pos.dx - 5.8, pos.dy + 8.0)
      ..close();

    canvas.drawPath(handPath, handBorderBgPaint);

    // 4. Hand Fill & Crisp CAD Blue Border (matching SS1)
    final handFill = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.fill;
    final handBorder = Paint()
      ..color = const Color(0xFF0369A1)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(handPath, handFill);
    canvas.drawPath(handPath, handBorder);
  }

  @override
  bool shouldRepaint(covariant AssemblyPanCursorPainter old) => old.cursorScreenPos != cursorScreenPos;
}
