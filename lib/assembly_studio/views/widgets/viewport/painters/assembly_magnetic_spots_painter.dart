import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/engine/sketch/cad_brep_topology_bridge.dart';

/// 3D Magnetic Snap Spots and Coupling Flux Overlay Painter
class AssemblyMagneticSpotsOverlayPainter extends CustomPainter {
  final List<AssemblyPart> parts;
  final List<AssemblyMagneticJoint> magneticJoints;
  final bool isMagneticToolActive;
  final CadPoint3D? hoverPoint;
  final Offset Function(CadPoint3D) projectPoint;
  final AssemblyStudioViewModel? viewModel;

  static const double kSnapProximityRadiusPx = 18.0;

  AssemblyMagneticSpotsOverlayPainter({
    required this.parts,
    required this.magneticJoints,
    required this.isMagneticToolActive,
    this.hoverPoint,
    required this.projectPoint,
    this.viewModel,
  });

  void paintHoleCenterSnaps(Canvas canvas, Size size) {
    if (viewModel == null) return;
    final vm = viewModel!;
    final Offset? cursorPos = vm.lastMouseScreenOffset;

    for (final HoleSnapSpot spot in vm.allHoleCenterSpots) {
      final bool isExplicitlySelected =
          vm.selectedHoleCenterIds.contains(spot.id);

      // Project 3D hole center to 2D screen without Z-buffer occlusion
      // so hidden hole centers remain hover-snappable!
      final Offset? screenPt = vm.projectWorldToScreen(spot.worldCenter, size);
      if (screenPt == null) continue;

      final double distToCursor = cursorPos != null
          ? (screenPt - cursorPos).distance
          : double.infinity;
      final bool isHoveredForSnap = distToCursor <= kSnapProximityRadiusPx;

      // CRITICAL: Never draw unselected hole center dots unless the mouse is within 18px!
      if (!isExplicitlySelected && !isHoveredForSnap) {
        continue;
      }

      final Paint dotPaint = Paint()
        ..color = isExplicitlySelected
            ? const Color(0xFFFFAB00) // Amber for explicitly selected hole center
            : const Color(0xFF00E5FF) // Cyan ring/dot for proximity snap target
        ..style = PaintingStyle.fill;

      canvas.drawCircle(screenPt, isExplicitlySelected ? 4.5 : 4.0, dotPaint);

      if (isHoveredForSnap) {
        final Paint ringPaint = Paint()
          ..color = const Color(0xFF111111)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(screenPt, 6.0, ringPaint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 0. Draw Proximity-Filtered / X-Ray Hover-Snappable Hole Center Points
    paintHoleCenterSnaps(canvas, size);
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
