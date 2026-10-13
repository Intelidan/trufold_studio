import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';

/// Sketch Entity Overlay Painter (3D Highlights, Bends, Holes, and Slots)
class AssemblyEntityOverlayPainter extends CustomPainter {
  final AssemblyPart part;
  final Size size;
  final FoldedMeshResult mesh;
  final String? selectedFeatureId;
  final String? draggingFeatureId;
  final Offset Function(CadPoint3D) projectPoint;

  AssemblyEntityOverlayPainter({
    required this.part,
    required this.size,
    required this.mesh,
    required this.selectedFeatureId,
    required this.draggingFeatureId,
    required this.projectPoint,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    for (final sk in part.sketches) {
      final isSel = sk.id == selectedFeatureId || sk.id == draggingFeatureId;
      final center3d = part.toWorld(CadPoint3D(sk.localCenter.x, 0.0, sk.localCenter.y));
      final centerScreen = projectPoint(center3d);
      if (centerScreen == Offset.zero) continue;

      if (sk.featureType == 'bend_line') {
        final bot3d = part.toWorld(CadPoint3D(sk.localCenter.x, 0.0, 0.0));
        final top3d = part.toWorld(CadPoint3D(sk.localCenter.x, 0.0, part.height));
        final botScreen = projectPoint(bot3d);
        final topScreen = projectPoint(top3d);

        final bendPaint = Paint()
          ..color = isSel ? const Color(0xFF0284C7) : const Color(0xFFF59E0B)
          ..strokeWidth = isSel ? 3.5 : 2.0
          ..style = PaintingStyle.stroke;

        // Draw dashed bend line
        final dist = (topScreen - botScreen).distance;
        if (dist > 2.0) {
          final dir = (topScreen - botScreen) / dist;
          double cur = 0.0;
          while (cur < dist) {
            final p1 = botScreen + dir * cur;
            final p2 = botScreen + dir * math.min(cur + 6.0, dist);
            canvas.drawLine(p1, p2, bendPaint);
            cur += 10.0;
          }
        }

        // Bend label
        final tp = TextPainter(
          text: TextSpan(
            text: isSel ? 'BEND 90° (SELECTED)' : 'BEND 90°',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isSel ? const Color(0xFF0284C7) : const Color(0xFFD97706),
              backgroundColor: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, botScreen + const Offset(4, -14));
      } else {
        // Holes, slots, cutouts
        if (isSel) {
          // Luminous selection halo
          final glowPaint = Paint()
            ..color = const Color(0xFF38BDF8).withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6.0;
          canvas.drawCircle(centerScreen, 18.0, glowPaint);

          final selPaint = Paint()
            ..color = const Color(0xFF0284C7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
          canvas.drawCircle(centerScreen, 18.0, selPaint);

          // 4-way move handle arrows
          final arrowPaint = Paint()
            ..color = const Color(0xFF0284C7)
            ..strokeWidth = 1.5;
          canvas.drawLine(centerScreen - const Offset(12, 0), centerScreen + const Offset(12, 0), arrowPaint);
          canvas.drawLine(centerScreen - const Offset(0, 12), centerScreen + const Offset(0, 12), arrowPaint);

          // Dimension text
          final tp = TextPainter(
            text: TextSpan(
              text: 'X: ${sk.localCenter.x.toInt()}mm',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF0369A1), backgroundColor: Colors.white),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, centerScreen + const Offset(10, -18));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyEntityOverlayPainter old) {
    return old.part != part || old.selectedFeatureId != selectedFeatureId || old.draggingFeatureId != draggingFeatureId;
  }
}
