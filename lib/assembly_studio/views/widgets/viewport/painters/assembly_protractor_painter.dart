import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

/// 3D SketchUp Protractor Overlay Painter
/// Renders 3-phase interactive rotational protractor dial, ticks, angle sweep fan,
/// bullseye, reference baseline, and degree badges.
class AssemblyProtractorOverlayPainter extends CustomPainter {
  final RotateToolPhase phase;
  final CadPoint3D? centerPoint;
  final CadPoint3D? baselinePoint;
  final CadPoint3D? currentArmPoint;
  final CadPoint3D? hoverPoint;
  final GizmoAxis activeAxis;
  final double currentAngleDeg;
  final bool isCopyMode;
  final Offset? cursorScreenPos;
  final Size size;
  final FoldedMeshResult mesh;
  final Offset Function(CadPoint3D) projectPoint;

  AssemblyProtractorOverlayPainter({
    required this.phase,
    required this.centerPoint,
    required this.baselinePoint,
    required this.currentArmPoint,
    required this.hoverPoint,
    required this.activeAxis,
    required this.currentAngleDeg,
    required this.isCopyMode,
    required this.cursorScreenPos,
    required this.size,
    required this.mesh,
    required this.projectPoint,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = centerPoint ?? hoverPoint;
    if (center == null || size.width <= 0 || size.height <= 0) return;

    final centerScreen = projectPoint(center);
    if (centerScreen == Offset.zero) return;

    final Color color;
    final CadPoint3D uAxis;
    final CadPoint3D vAxis;
    final String axisLabel;

    if (activeAxis == GizmoAxis.x) {
      color = const Color(0xFFEF4444); // Red
      uAxis = const CadPoint3D(0.0, 1.0, 0.0);
      vAxis = const CadPoint3D(0.0, 0.0, 1.0);
      axisLabel = 'RED AXIS (X)';
    } else if (activeAxis == GizmoAxis.y) {
      color = const Color(0xFF10B981); // Green
      uAxis = const CadPoint3D(0.0, 0.0, 1.0);
      vAxis = const CadPoint3D(1.0, 0.0, 0.0);
      axisLabel = 'GREEN AXIS (Y)';
    } else {
      color = const Color(0xFF0284C7); // Blue
      uAxis = const CadPoint3D(1.0, 0.0, 0.0);
      vAxis = const CadPoint3D(0.0, 1.0, 0.0);
      axisLabel = 'BLUE AXIS (Z)';
    }

    // Measure screen radius for a nominal 100mm offset
    final testPt = CadPoint3D(center.x + uAxis.x * 100.0, center.y + uAxis.y * 100.0, center.z + uAxis.z * 100.0);
    final testScreen = projectPoint(testPt);
    final dScreen = (testScreen - centerScreen).distance;
    const double kProtractorScreenRadius = 48.0;
    final double worldRadius = dScreen > 0.05 ? (100.0 * kProtractorScreenRadius / dScreen) : 100.0;

    // 1. Draw 3D Circular Disc
    final circlePath = Path();
    const numSteps = 48;
    for (int i = 0; i < numSteps; i++) {
      final angle = (i * 2 * math.pi) / numSteps;
      final pt3d = CadPoint3D(
        center.x + (uAxis.x * math.cos(angle) + vAxis.x * math.sin(angle)) * worldRadius,
        center.y + (uAxis.y * math.cos(angle) + vAxis.y * math.sin(angle)) * worldRadius,
        center.z + (uAxis.z * math.cos(angle) + vAxis.z * math.sin(angle)) * worldRadius,
      );
      final scrPt = projectPoint(pt3d);
      if (i == 0) {
        circlePath.moveTo(scrPt.dx, scrPt.dy);
      } else {
        circlePath.lineTo(scrPt.dx, scrPt.dy);
      }
    }
    circlePath.close();

    final discRim = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(circlePath, discRim);

    // 2. Inner concentric ring at 0.45x radius
    final innerCirclePath = Path();
    for (int i = 0; i < numSteps; i++) {
      final angle = (i * 2 * math.pi) / numSteps;
      final pt3d = CadPoint3D(
        center.x + (uAxis.x * math.cos(angle) + vAxis.x * math.sin(angle)) * (worldRadius * 0.45),
        center.y + (uAxis.y * math.cos(angle) + vAxis.y * math.sin(angle)) * (worldRadius * 0.45),
        center.z + (uAxis.z * math.cos(angle) + vAxis.z * math.sin(angle)) * (worldRadius * 0.45),
      );
      final scrPt = projectPoint(pt3d);
      if (i == 0) {
        innerCirclePath.moveTo(scrPt.dx, scrPt.dy);
      } else {
        innerCirclePath.lineTo(scrPt.dx, scrPt.dy);
      }
    }
    innerCirclePath.close();
    final innerRim = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(innerCirclePath, innerRim);

    // 3. Center Crosshair, Center Bullseye & Circular Rotation Arrows
    final centerCrossPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;
    canvas.drawLine(centerScreen - const Offset(8, 0), centerScreen + const Offset(8, 0), centerCrossPaint);
    canvas.drawLine(centerScreen - const Offset(0, 8), centerScreen + const Offset(0, 8), centerCrossPaint);

    final rotArrowPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    const arrowRadius = 10.0;
    final arrowRect = Rect.fromCircle(center: centerScreen, radius: arrowRadius);
    canvas.drawArc(arrowRect, -0.3, 2.2, false, rotArrowPaint);
    canvas.drawArc(arrowRect, math.pi - 0.3, 2.2, false, rotArrowPaint);
    _drawArrowHead(canvas, centerScreen + Offset(math.cos(1.9) * arrowRadius, math.sin(1.9) * arrowRadius), 2.9, const Color(0xFFDC2626));
    _drawArrowHead(
      canvas,
      centerScreen + Offset(math.cos(math.pi + 1.9) * arrowRadius, math.sin(math.pi + 1.9) * arrowRadius),
      math.pi + 2.9,
      const Color(0xFFDC2626),
    );

    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(centerScreen, 3.5, centerPaint);
    canvas.drawCircle(
      centerScreen,
      1.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // 4. 24 Tick Marks (15° increments)
    for (int i = 0; i < 24; i++) {
      final rad = (i * 15.0) * math.pi / 180.0;
      final isMajor = (i % 3 == 0); // 0, 45, 90, 135, 180, 225, 270, 315
      final tickLen = isMajor ? (worldRadius * 0.22) : (worldRadius * 0.12);

      final outer3d = CadPoint3D(
        center.x + (uAxis.x * math.cos(rad) + vAxis.x * math.sin(rad)) * worldRadius,
        center.y + (uAxis.y * math.cos(rad) + vAxis.y * math.sin(rad)) * worldRadius,
        center.z + (uAxis.z * math.cos(rad) + vAxis.z * math.sin(rad)) * worldRadius,
      );
      final inner3d = CadPoint3D(
        center.x + (uAxis.x * math.cos(rad) + vAxis.x * math.sin(rad)) * (worldRadius - tickLen),
        center.y + (uAxis.y * math.cos(rad) + vAxis.y * math.sin(rad)) * (worldRadius - tickLen),
        center.z + (uAxis.z * math.cos(rad) + vAxis.z * math.sin(rad)) * (worldRadius - tickLen),
      );

      final outerScr = projectPoint(outer3d);
      final innerScr = projectPoint(inner3d);
      final tickPaint = Paint()
        ..color = isMajor ? color : color.withValues(alpha: 0.6)
        ..strokeWidth = isMajor ? 2.0 : 1.0;
      canvas.drawLine(innerScr, outerScr, tickPaint);
    }

    // 5. Baseline and Arm Graphics
    if (phase == RotateToolPhase.awaitingBaseline && currentArmPoint != null) {
      final armScreen = projectPoint(currentArmPoint!);
      _drawDashedLine(
        canvas,
        centerScreen,
        armScreen,
        Paint()
          ..color = Colors.amberAccent
          ..strokeWidth = 2.0,
        dashWidth: 6.0,
        dashSpace: 4.0,
      );
      canvas.drawCircle(
        armScreen,
        5.0,
        Paint()
          ..color = Colors.amberAccent
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        armScreen,
        2.5,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.fill,
      );

      final tp = TextPainter(
        text: const TextSpan(
          text: '0.0° (Baseline)',
          style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Color(0xCC0F172A)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, armScreen + const Offset(8, -14));
    } else if (phase == RotateToolPhase.rotatingAngle) {
      // Baseline dashed arm
      final base3d = baselinePoint ?? CadPoint3D(center.x + uAxis.x * worldRadius, center.y + uAxis.y * worldRadius, center.z + uAxis.z * worldRadius);
      final baseScreen = projectPoint(base3d);
      _drawDashedLine(
        canvas,
        centerScreen,
        baseScreen,
        Paint()
          ..color = const Color(0xFF94A3B8)
          ..strokeWidth = 2.0,
        dashWidth: 6.0,
        dashSpace: 4.0,
      );

      // Swept Arc Wedge
      if (currentAngleDeg.abs() > 0.05) {
        final arcPath = Path();
        arcPath.moveTo(centerScreen.dx, centerScreen.dy);

        // Compute baseline angle on plane
        double bU, bV;
        if (activeAxis == GizmoAxis.x) {
          bU = base3d.y - center.y;
          bV = base3d.z - center.z;
        } else if (activeAxis == GizmoAxis.y) {
          bU = base3d.z - center.z;
          bV = base3d.x - center.x;
        } else {
          bU = base3d.x - center.x;
          bV = base3d.y - center.y;
        }
        final baseAngle = math.atan2(bV, bU);
        final sweepRad = currentAngleDeg * math.pi / 180.0;
        final arcSteps = math.max((currentAngleDeg.abs() / 5.0).round(), 8);

        for (int s = 0; s <= arcSteps; s++) {
          final frac = s / arcSteps;
          final ang = baseAngle + frac * sweepRad;
          final pt3d = CadPoint3D(
            center.x + (uAxis.x * math.cos(ang) + vAxis.x * math.sin(ang)) * worldRadius,
            center.y + (uAxis.y * math.cos(ang) + vAxis.y * math.sin(ang)) * worldRadius,
            center.z + (uAxis.z * math.cos(ang) + vAxis.z * math.sin(ang)) * worldRadius,
          );
          final scrPt = projectPoint(pt3d);
          arcPath.lineTo(scrPt.dx, scrPt.dy);
        }
        arcPath.close();

        final wedgeFill = Paint()
          ..color = color.withValues(alpha: 0.32)
          ..style = PaintingStyle.fill;
        canvas.drawPath(arcPath, wedgeFill);

        final wedgeRim = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawPath(arcPath, wedgeRim);
      }

      // Active Arm line
      if (currentArmPoint != null) {
        final armScreen = projectPoint(currentArmPoint!);
        final armPaint = Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(centerScreen, armScreen, armPaint);
        canvas.drawCircle(
          armScreen,
          5.0,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );

        // Floating Angle Badge
        final badgeText = '${currentAngleDeg.abs().toStringAsFixed(1)}°';
        final tp = TextPainter(
          text: TextSpan(
            text: badgeText,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final badgeRect = RRect.fromRectAndRadius(Rect.fromLTWH(armScreen.dx + 10, armScreen.dy - 20, tp.width + 12, tp.height + 6), const Radius.circular(5));
        canvas.drawRRect(badgeRect, Paint()..color = const Color(0xEE0F172A));
        canvas.drawRRect(
          badgeRect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        tp.paint(canvas, Offset(armScreen.dx + 16, armScreen.dy - 17));
      }
    }

    // 6. Rotational Copy Badge [ + COPY ]
    if (isCopyMode) {
      final copyTp = TextPainter(
        text: const TextSpan(
          text: '+ COPY',
          style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final copyRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(centerScreen.dx + 14, centerScreen.dy + 10, copyTp.width + 10, copyTp.height + 4),
        const Radius.circular(4),
      );
      canvas.drawRRect(copyRect, Paint()..color = const Color(0xEE064E3B));
      canvas.drawRRect(
        copyRect,
        Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      copyTp.paint(canvas, Offset(centerScreen.dx + 19, centerScreen.dy + 12));
    }

    // 7. Axis Lock Badge
    final axisTp = TextPainter(
      text: TextSpan(
        text: 'Protractor: $axisLabel (15° Snap)',
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final badgeBox = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerScreen.dx - axisTp.width / 2 - 6, centerScreen.dy - 46, axisTp.width + 12, axisTp.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(badgeBox, Paint()..color = const Color(0xDD0F172A));
    canvas.drawRRect(
      badgeBox,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    axisTp.paint(canvas, Offset(centerScreen.dx - axisTp.width / 2, centerScreen.dy - 44));

    // 8. In-App Rotate Cursor pointer when sweeping angle away from center
    if (phase != RotateToolPhase.awaitingCenter && cursorScreenPos != null) {
      final curPos = cursorScreenPos!;
      const curRadius = 7.5;
      final curBgPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;
      final curArrowPaint = Paint()
        ..color = const Color(0xFFDC2626)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      final curRect = Rect.fromCircle(center: curPos, radius: curRadius);
      canvas.drawArc(curRect, -0.3, 2.2, false, curBgPaint);
      canvas.drawArc(curRect, math.pi - 0.3, 2.2, false, curBgPaint);
      canvas.drawArc(curRect, -0.3, 2.2, false, curArrowPaint);
      canvas.drawArc(curRect, math.pi - 0.3, 2.2, false, curArrowPaint);
      _drawArrowHead(canvas, curPos + Offset(math.cos(1.9) * curRadius, math.sin(1.9) * curRadius), 2.9, const Color(0xFFDC2626));
      _drawArrowHead(canvas, curPos + Offset(math.cos(math.pi + 1.9) * curRadius, math.sin(math.pi + 1.9) * curRadius), math.pi + 2.9, const Color(0xFFDC2626));
    }
  }

  void _drawArrowHead(Canvas canvas, Offset tip, double angleRad, Color arrowColor) {
    const headLen = 4.5;
    final path = Path();
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(tip.dx - headLen * math.cos(angleRad - 0.5), tip.dy - headLen * math.sin(angleRad - 0.5));
    path.lineTo(tip.dx - headLen * math.cos(angleRad + 0.5), tip.dy - headLen * math.sin(angleRad + 0.5));
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = arrowColor
        ..style = PaintingStyle.fill,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {double dashWidth = 6.0, double dashSpace = 4.0}) {
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
  bool shouldRepaint(covariant AssemblyProtractorOverlayPainter old) {
    return old.phase != phase ||
        old.centerPoint != centerPoint ||
        old.baselinePoint != baselinePoint ||
        old.currentArmPoint != currentArmPoint ||
        old.hoverPoint != hoverPoint ||
        old.activeAxis != activeAxis ||
        old.currentAngleDeg != currentAngleDeg ||
        old.isCopyMode != isCopyMode ||
        old.cursorScreenPos != cursorScreenPos;
  }
}
