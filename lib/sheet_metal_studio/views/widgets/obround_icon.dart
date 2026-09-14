// =============================================================================
// obround_icon.dart
//
// Custom Vector CAD Icon for Obround Slot Punches.
// Draws an authentic stadium/pill shape with semi-circular rounded ends,
// clearly distinguishing obround tooling from sharp rectangular tools.
// =============================================================================

import 'package:flutter/material.dart';

class ObroundSlotIcon extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final double strokeWidth;

  const ObroundSlotIcon({
    super.key,
    this.width = 16.0,
    this.height = 9.0,
    this.color = const Color(0xFF475569),
    this.strokeWidth = 1.4,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _ObroundPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _ObroundPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _ObroundPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final r = size.height / 2.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2.0,
        strokeWidth / 2.0,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(r),
    );

    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _ObroundPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
