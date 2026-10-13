import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive Welding Spark Particle Model
class AssemblyWeldSparkParticle {
  Offset position;
  Offset velocity;
  double life;
  double maxLife;
  double size;
  Color color;

  AssemblyWeldSparkParticle({
    required this.position,
    required this.velocity,
    required this.life,
    required this.maxLife,
    required this.size,
    required this.color,
  });
}

/// 3D Animated Flying Sparks Overlay Painter
class AssemblyWeldSparksPainter extends CustomPainter {
  final List<AssemblyWeldSparkParticle> sparks;

  AssemblyWeldSparksPainter({required this.sparks});

  @override
  void paint(Canvas canvas, Size size) {
    if (sparks.isEmpty) return;

    for (final s in sparks) {
      final alpha = (s.life / s.maxLife).clamp(0.0, 1.0);
      if (alpha <= 0.0) continue;

      final sparkColor = s.color.withValues(alpha: alpha);
      final glowPaint = Paint()
        ..color = sparkColor.withValues(alpha: alpha * 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
      canvas.drawCircle(s.position, s.size * 2.2, glowPaint);

      // Streak tail along inverted velocity
      final speed = s.velocity.distance;
      if (speed > 10.0) {
        final dir = s.velocity / speed;
        final tailLen = (speed * 0.04).clamp(3.0, 14.0);
        final tailPaint = Paint()
          ..color = sparkColor
          ..strokeWidth = s.size * 0.9
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(s.position, s.position - dir * tailLen, tailPaint);
      }

      final corePaint = Paint()..color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(s.position, s.size * 0.65, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyWeldSparksPainter old) => true;
}

/// Interactive Real-World Welding Bead Brush Overlay Painter
/// Renders authentic fish-scale scalloped weld beads with molten heat tint & sparks
class AssemblyWeldBeadsBrushPainter extends CustomPainter {
  final List<Offset> path;
  final bool isFinished;
  final double beadRadius;
  final double scallopSpacing;

  AssemblyWeldBeadsBrushPainter({
    required this.path,
    this.isFinished = false,
    this.beadRadius = 11.5,
    this.scallopSpacing = 9.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty) return;

    final r = math.max(3.0, beadRadius);
    final sp = math.max(2.5, scallopSpacing);

    if (path.length == 1) {
      // Single puddle point
      final pt = path.first;
      if (!isFinished) {
        final glowPaint = Paint()
          ..color = const Color(0xFFF97316).withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
        canvas.drawCircle(pt, r * 1.1, glowPaint);
        canvas.drawCircle(pt, r * 0.65, Paint()..color = const Color(0xFFFBBF24));
        canvas.drawCircle(pt, r * 0.32, Paint()..color = const Color(0xFFFFFFFF));
      } else {
        // Cooled solid bead point (clean dark steel, no concentric silver balls, SS5)
        canvas.drawCircle(pt, r * 0.8, Paint()..color = const Color(0xFF18181B));
        canvas.drawCircle(pt, r * 0.65, Paint()..color = const Color(0xFF3F3F46));
      }
      return;
    }

    // 1. Heat Affected Zone (HAZ) outer soft warm glow (no blue tint, SS5)
    final hazGlow = Paint()
      ..color = isFinished
          ? const Color(0xFF27272A).withValues(alpha: 0.20)
          : const Color(0xFF78350F).withValues(alpha: 0.25)
      ..strokeWidth = r * 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

    final hazPath = Path()..moveTo(path[0].dx, path[0].dy);
    for (int i = 1; i < path.length; i++) {
      hazPath.lineTo(path[i].dx, path[i].dy);
    }
    canvas.drawPath(hazPath, hazGlow);

    // 2. Base molten bead root trail (dark gunmetal slag boundary, no blue tint)
    final rootPaint = Paint()
      ..color = const Color(0xFF18181B) // deep charcoal slag boundary
      ..strokeWidth = r * 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(hazPath, rootPaint);

    final midBeadPaint = Paint()
      ..color = const Color(0xFF27272A) // solid dark steel core
      ..strokeWidth = r * 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(hazPath, midBeadPaint);

    // 3. Overlapping scalloped fish-scale ripples (spaced wider so no excessive wrinkles, SS5)
    double accumulatedDist = 0.0;
    final scallopRimPaint = Paint()
      ..color = const Color(0xFF71717A) // neutral graphite / gunmetal highlight rim (NO blue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.16)
      ..strokeCap = StrokeCap.round;

    final scallopFill = Paint()
      ..color = const Color(0xFF3F3F46) // dark gray steel body
      ..style = PaintingStyle.fill;

    final goldTemperPaint = Paint()
      ..color = const Color(0xFF78350F).withValues(alpha: 0.60) // subtle bronze heat discoloration
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.12)
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < path.length - 1; i++) {
      final p0 = path[i];
      final p1 = path[i + 1];
      final segVector = p1 - p0;
      final segLen = segVector.distance;
      if (segLen < 1e-3) continue;

      final dir = segVector / segLen;
      final normal = Offset(-dir.dy, dir.dx); // Perpendicular across seam

      double t = 0.0;
      while (t < segLen) {
        final center = p0 + dir * t;
        // Subtle natural weave oscillation across seam
        final weave = math.sin(accumulatedDist * 0.28) * (r * 0.20);
        final curBeadRadius = r + (math.cos(accumulatedDist * 0.40) * (r * 0.10));

        final beadCenter = center + normal * weave;

        // Shadow under scallop
        canvas.drawCircle(beadCenter + dir * (r * 0.10), curBeadRadius * 0.95, Paint()..color = const Color(0xFF18181B));

        // Solid dark gray metallic scallop body (no bright silver balls inside, SS5)
        canvas.drawCircle(beadCenter, curBeadRadius * 0.85, scallopFill);

        // Crescent arc facing opposite to travel direction (stacked dimes)
        final arcRect = Rect.fromCircle(center: beadCenter, radius: curBeadRadius);
        final startAngle = math.atan2(dir.dy, dir.dx) + math.pi * 0.52;
        canvas.drawArc(arcRect, startAngle, math.pi * 0.96, false, scallopRimPaint);
        canvas.drawArc(Rect.fromCircle(center: beadCenter, radius: curBeadRadius * 0.75), startAngle, math.pi * 0.88, false, goldTemperPaint);

        t += sp;
        accumulatedDist += sp;
      }
    }

    // 4. Molten glowing puddle at the active lead tip (only during active drawing, never left behind)
    if (!isFinished) {
      final leadPt = path.last;
      final puddleGlow = Paint()
        ..color = const Color(0xFFF97316).withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14.0);
      canvas.drawCircle(leadPt, r * 1.5, puddleGlow);

      final moltenHotCore = Paint()..color = const Color(0xFFFBBF24);
      canvas.drawCircle(leadPt, r * 0.7, moltenHotCore);

      final arcCore = Paint()..color = Colors.white;
      canvas.drawCircle(leadPt, r * 0.35, arcCore);
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyWeldBeadsBrushPainter old) => true;
}

/// Real-World Welding Torch & Electric Arc Flame Cursor Painter
class AssemblyWeldingTorchCursorPainter extends CustomPainter {
  final Offset? cursorScreenPos;
  final bool isWelding;

  AssemblyWeldingTorchCursorPainter({
    required this.cursorScreenPos,
    required this.isWelding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cursorScreenPos == null) return;
    final pos = cursorScreenPos!;

    // Torch angle: held naturally from the front right hand (135° rotation)
    // Handle extends down-and-right (+X, +Y toward user), nozzle tip at (0, 0) points up-left (-X, -Y) into the joint seam
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(135.0 * math.pi / 180.0);

    // 1. Ceramic/Copper Gas Nozzle (at tip origin)
    final nozzlePath = Path()
      ..moveTo(-3.0, 0.0)
      ..lineTo(3.0, 0.0)
      ..lineTo(4.5, -16.0)
      ..lineTo(-4.5, -16.0)
      ..close();
    final nozzlePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFD97706), Color(0xFFF59E0B), Color(0xFFB45309)],
      ).createShader(const Rect.fromLTWH(-5, -16, 10, 16));
    canvas.drawPath(nozzlePath, nozzlePaint);

    final nozzleBorder = Paint()
      ..color = const Color(0xFF78350F)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawPath(nozzlePath, nozzleBorder);

    // Brass insulator retaining ring
    final brassRing = Rect.fromLTWH(-4.0, -20.0, 8.0, 4.0);
    canvas.drawRRect(RRect.fromRectAndRadius(brassRing, const Radius.circular(1.0)), Paint()..color = const Color(0xFFEAB308));

    // Swan Neck metal tube
    final neckPath = Path()
      ..moveTo(-3.0, -20.0)
      ..lineTo(3.0, -20.0)
      ..lineTo(3.0, -38.0)
      ..lineTo(-3.0, -38.0)
      ..close();
    canvas.drawPath(
      neckPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF64748B), Color(0xFF94A3B8), Color(0xFF475569)],
        ).createShader(const Rect.fromLTWH(-3, -38, 6, 18)),
    );
    canvas.drawPath(neckPath, Paint()..color = const Color(0xFF334155)..strokeWidth = 0.8..style = PaintingStyle.stroke);

    // Ergonomic Rubber Handle Grip (held in front)
    final handleRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-5.5, -82.0, 11.0, 44.0),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(
      handleRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF334155), Color(0xFF1E293B)],
        ).createShader(const Rect.fromLTWH(-5.5, -82, 11, 44)),
    );

    // Handle grip ribs
    final ribPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 1.2;
    for (double y = -74.0; y <= -46.0; y += 7.0) {
      canvas.drawLine(Offset(-4.5, y), Offset(4.5, y), ribPaint);
    }

    // Trigger switch
    final triggerPath = Path()
      ..moveTo(5.5, -60.0)
      ..lineTo(8.5, -57.0)
      ..lineTo(8.5, -51.0)
      ..lineTo(5.5, -48.0)
      ..close();
    canvas.drawPath(triggerPath, Paint()..color = const Color(0xFFEF4444));

    // Tungsten Electrode Needle protruding from nozzle into seam
    final needlePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(0.0, -4.0), const Offset(0.0, 4.0), needlePaint);

    canvas.restore(); // Back to screen space at pos

    // 2. Electric Arc Flame & Hot Puddle Plasma at Tip
    if (isWelding) {
      // Violent electric arc flame eruption (fiery incandescent orange & white)
      final arcCorona = Paint()
        ..color = const Color(0xFFF97316).withValues(alpha: 0.65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14.0);
      canvas.drawCircle(pos, 16.0, arcCorona);

      final fieryGlow = Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.5);
      canvas.drawCircle(pos, 9.0, fieryGlow);

      final plasmaCore = Paint()..color = const Color(0xFFFEF3C7);
      canvas.drawCircle(pos, 5.0, plasmaCore);

      final blindingCenter = Paint()..color = Colors.white;
      canvas.drawCircle(pos, 2.5, blindingCenter);

      // Arc rays (fiery amber/orange)
      final rayPaint = Paint()
        ..color = const Color(0xFFFB923C).withValues(alpha: 0.85)
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 6; i++) {
        final a = (i * 60.0 + 15.0) * math.pi / 180.0;
        final r1 = 5.0;
        final r2 = 13.0;
        canvas.drawLine(
          pos + Offset(math.cos(a) * r1, math.sin(a) * r1),
          pos + Offset(math.cos(a) * r2, math.sin(a) * r2),
          rayPaint,
        );
      }
    } else {
      // Idle crosshair & subtle warm pilot indicator
      final pilotGlow = Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(pos, 4.0, pilotGlow);

      final crosshairPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 1.0;
      canvas.drawLine(pos - const Offset(6, 0), pos + const Offset(6, 0), crosshairPaint);
      canvas.drawLine(pos - const Offset(0, 6), pos + const Offset(0, 6), crosshairPaint);
      canvas.drawCircle(pos, 2.0, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyWeldingTorchCursorPainter old) =>
      old.cursorScreenPos != cursorScreenPos || old.isWelding != isWelding;
}
