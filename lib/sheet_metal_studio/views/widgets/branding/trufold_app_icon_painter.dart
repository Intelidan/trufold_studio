// =============================================================================
// trufold_app_icon_painter.dart
//
// Standalone App Icon Painter & Asset Generator for truFold Studio.
// Renders the "Concept 3: Hinged Planar 't-F'" icon with squircle / rounded
// corners, subtle blueprint grid lines, and crisp 3D sheet metal depth.
// =============================================================================

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'trufold_3d_icon.dart';

/// App Icon Tile Widget for About dialogs, settings, and window headers.
class TruFoldAppIconTile extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool isDark;
  final bool isAnimated;

  const TruFoldAppIconTile({
    super.key,
    this.size = 80.0,
    this.borderRadius = 18.0,
    this.isDark = true,
    this.isAnimated = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(borderRadius * (size / 80.0)),
        border: Border.all(
          color: isDark
              ? const Color(0xFF38BDF8).withValues(alpha: 0.3)
              : const Color(0xFFCBD5E1),
          width: 1.5 * (size / 80.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 12 * (size / 80.0),
            offset: Offset(0, 4 * (size / 80.0)),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background subtle CAD grid
          CustomPaint(
            size: Size(size, size),
            painter: _IconGridPainter(isDark: isDark),
          ),

          // Central 3D 't-F' Icon
          TruFold3DIcon(
            size: size * 0.72,
            isAnimated: isAnimated,
            fixedFoldAngleDeg: isAnimated ? null : 42.0, // Fixed dynamic 3D angle for app icon
            showGrid: false,
            showAnnotations: false,
            sheetThickness: 2.5,
            tColor: const Color(0xFF38BDF8),
            fColor: isDark ? const Color(0xFF64748B) : const Color(0xFF334155),
          ),
        ],
      ),
    );
  }

  /// Utility to render and export an app icon to a PNG byte image in memory.
  static Future<ui.Image> renderAppIconImage({
    double size = 512.0,
    bool isDark = true,
    double foldAngleDeg = 42.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Draw background
    final bgPaint = Paint()..color = isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size, size),
      Radius.circular(size * 0.22), // Apple / modern squircle ratio
    );
    canvas.drawRRect(rrect, bgPaint);

    // Draw grid
    final gridPainter = _IconGridPainter(isDark: isDark);
    gridPainter.paint(canvas, Size(size, size));

    // Draw border
    final borderPaint = Paint()
      ..color = isDark
          ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
          : const Color(0xFFCBD5E1)
      ..strokeWidth = size * 0.015
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, borderPaint);

    final picture = recorder.endRecording();
    return picture.toImage(size.toInt(), size.toInt());
  }
}

class _IconGridPainter extends CustomPainter {
  final bool isDark;

  _IconGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = isDark
          ? const Color(0xFF1E293B).withValues(alpha: 0.6)
          : const Color(0xFFE2E8F0)
      ..strokeWidth = 0.8;

    final step = size.width / 8.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _IconGridPainter old) => old.isDark != isDark;
}
