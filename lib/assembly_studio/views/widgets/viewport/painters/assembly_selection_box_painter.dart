import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Two-Way Selection Box Painter
/// Left-to-Right = Window (Translucent Blue Solid Border, selects fully enclosed parts)
/// Right-to-Left = Crossing (Translucent Green Dashed Border, selects any intersecting parts)
class AssemblyTwoWaySelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset current;

  AssemblyTwoWaySelectionBoxPainter({required this.start, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, current);
    final isCrossing = current.dx < start.dx; // Right-to-Left = Crossing, Left-to-Right = Window

    if (isCrossing) {
      // Crossing: Translucent Green Fill + Dashed Green Border
      final fillPaint = Paint()
        ..color = const Color(0x2216A34A)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = const Color(0xFF22C55E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      _drawDashedRect(canvas, rect, borderPaint, dashWidth: 6.0, dashSpace: 4.0);
    } else {
      // Window: Translucent Blue Fill + Solid Blue Border
      final fillPaint = Paint()
        ..color = const Color(0x220284C7)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRect(rect, borderPaint);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint, {double dashWidth = 6.0, double dashSpace = 4.0}) {
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint, dashWidth, dashSpace);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, double dashWidth, double dashSpace) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalDist = math.sqrt(dx * dx + dy * dy);
    if (totalDist == 0) return;
    final unitX = dx / totalDist;
    final unitY = dy / totalDist;

    double currentDist = 0.0;
    while (currentDist < totalDist) {
      final segStart = Offset(p1.dx + unitX * currentDist, p1.dy + unitY * currentDist);
      final segmentEndDist = math.min(currentDist + dashWidth, totalDist);
      final segEnd = Offset(p1.dx + unitX * segmentEndDist, p1.dy + unitY * segmentEndDist);
      canvas.drawLine(segStart, segEnd, paint);
      currentDist += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyTwoWaySelectionBoxPainter old) {
    return old.start != start || old.current != current;
  }
}
