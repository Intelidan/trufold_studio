import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';

/// 3D Magnetic Snap Spots and Coupling Flux Overlay Painter
class AssemblyMagneticSpotsOverlayPainter extends CustomPainter {
  final List<AssemblyPart> parts;
  final List<AssemblyMagneticJoint> magneticJoints;
  final bool isMagneticToolActive;
  final CadPoint3D? hoverPoint;
  final Offset Function(CadPoint3D) projectPoint;

  AssemblyMagneticSpotsOverlayPainter({
    required this.parts,
    required this.magneticJoints,
    required this.isMagneticToolActive,
    this.hoverPoint,
    required this.projectPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Magnetic Spots on Parts
    for (final part in parts) {
      for (final spot in part.magneticSpots) {
        final worldPt = spot.toWorldPoint(part);
        final scr = projectPoint(worldPt);
        if (scr == Offset.zero) continue;

        // Outer magnetic flux glow
        canvas.drawCircle(scr, 10.0, Paint()..color = const Color(0xFF6366F1).withValues(alpha: 0.25));
        canvas.drawCircle(
          scr,
          6.0,
          Paint()
            ..color = const Color(0xFF818CF8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );

        // Core North / South magnetic pole dots
        canvas.drawCircle(scr - const Offset(2.0, 0), 2.5, Paint()..color = const Color(0xFFEF4444)); // North (Red)
        canvas.drawCircle(scr + const Offset(2.0, 0), 2.5, Paint()..color = const Color(0xFF3B82F6)); // South (Blue)

        // Text label badge
        final tp = TextPainter(
          text: TextSpan(
            text: spot.name,
            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white, backgroundColor: Color(0xCC0F172A)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, scr + Offset(-tp.width / 2, -18));
      }
    }

    // 2. Draw Magnetic Coupling Flux Lines between Linked Spots
    for (final joint in magneticJoints) {
      final partA = parts.where((p) => p.id == joint.partAId).firstOrNull;
      final partB = parts.where((p) => p.id == joint.partBId).firstOrNull;
      if (partA == null || partB == null) continue;

      final spotA = partA.magneticSpots.where((s) => s.id == joint.spotAId).firstOrNull;
      final spotB = partB.magneticSpots.where((s) => s.id == joint.spotBId).firstOrNull;
      if (spotA == null || spotB == null) continue;

      final scrA = projectPoint(spotA.toWorldPoint(partA));
      final scrB = projectPoint(spotB.toWorldPoint(partB));
      if (scrA == Offset.zero || scrB == Offset.zero) continue;

      // Draw subtle dashed magnetic flux line
      final fluxPaint = Paint()
        ..color = const Color(0xFF818CF8).withValues(alpha: 0.8)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;

      canvas.drawLine(scrA, scrB, fluxPaint);
      canvas.drawCircle(Offset((scrA.dx + scrB.dx) / 2, (scrA.dy + scrB.dy) / 2), 3.5, Paint()..color = const Color(0xFF6366F1));
    }

    // 3. Draw Hover Preview if Magnetic Tool is active
    if (isMagneticToolActive && hoverPoint != null) {
      final scr = projectPoint(hoverPoint!);
      if (scr != Offset.zero) {
        canvas.drawCircle(
          scr,
          12.0,
          Paint()
            ..color = const Color(0xFF6366F1).withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        canvas.drawCircle(scr, 4.0, Paint()..color = const Color(0xFF818CF8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyMagneticSpotsOverlayPainter old) => true;
}
