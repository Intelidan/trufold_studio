// =============================================================================
// studio_3d_tool_icons.dart
//
// Interactive 3D Animated Action Icons for Sheet Metal Studio Toolbar.
// Uses isometric 3D projection, depth shading, and physics-driven animations
// to dynamically demonstrate each tool's mechanical and CAD action on hover.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Supported CAD & Sheet Metal Tool Types for 3D animated visualization.
enum Tool3DType {
  select,
  drawPolyline,
  drawRectangle,
  drawCircle,
  drawArc,
  addBend,
  addFlange,
  addCut,
  perforationPattern,
  setBaseAnchor,
  constructionToggle,
  cornerFillet,
  cornerChamfer,
  modifyMirror,
  addPunchObround,
  addDimension,
  dragDimension,
  pressBrake,
  punchTooling,
}

/// A self-contained widget that displays an isometric 3D tool action icon.
/// Automatically plays the 3D action animation when hovered, or displays
/// a live active state when [isActive] is true.
class Tool3DActionIcon extends StatefulWidget {
  final Tool3DType toolType;
  final bool isHovered;
  final bool isActive;
  final double size;
  final Color? primaryColor;
  final Color? accentColor;

  const Tool3DActionIcon({
    super.key,
    required this.toolType,
    this.isHovered = false,
    this.isActive = false,
    this.size = 28.0,
    this.primaryColor,
    this.accentColor,
  });

  @override
  State<Tool3DActionIcon> createState() => _Tool3DActionIconState();
}

class _Tool3DActionIconState extends State<Tool3DActionIcon> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;
  Timer? _dwellTimer;

  @override
  void initState() {
    super.initState();
    // Faster action stroke (520ms) and slower return retraction stroke (1050ms)
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 520), reverseDuration: const Duration(milliseconds: 1050));

    // Asymmetric organic curves:
    // - Forward: fast decisive stroke (Curves.fastOutSlowIn)
    // - Reverse: smooth, gradual mechanical recovery (Curves.easeInOutCubic)
    _animation = CurvedAnimation(parent: _animController, curve: Curves.fastOutSlowIn, reverseCurve: Curves.easeInOutCubic);

    _animController.addStatusListener(_onAnimationStatusChanged);
    _updateAnimationState();
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (!mounted || !widget.isHovered) return;
    if (status == AnimationStatus.completed) {
      // Natural mechanical dwell at apex/stroke limit (80ms), then return slowly
      _dwellTimer?.cancel();
      _dwellTimer = Timer(const Duration(milliseconds: 80), () {
        if (mounted && widget.isHovered) {
          _animController.reverse();
        }
      });
    } else if (status == AnimationStatus.dismissed) {
      // Natural resting pause before next cycle begins (140ms), then execute stroke decisively
      _dwellTimer?.cancel();
      _dwellTimer = Timer(const Duration(milliseconds: 140), () {
        if (mounted && widget.isHovered) {
          _animController.forward();
        }
      });
    }
  }

  @override
  void didUpdateWidget(Tool3DActionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isHovered != widget.isHovered || oldWidget.isActive != widget.isActive) {
      _updateAnimationState();
    }
  }

  void _updateAnimationState() {
    _dwellTimer?.cancel();
    if (widget.isHovered) {
      // Begin natural asymmetric cycle
      if (_animController.status == AnimationStatus.dismissed || _animController.value == 0.0) {
        _animController.forward();
      } else if (_animController.status == AnimationStatus.completed || _animController.value == 1.0) {
        _animController.reverse();
      } else {
        _animController.forward();
      }
    } else if (widget.isActive) {
      _animController.stop();
      // Hold at a subtle 35% action preview state when tool is currently active
      _animController.animateTo(0.35, duration: const Duration(milliseconds: 300));
    } else {
      _animController.stop();
      // Smoothly return to resting position
      _animController.animateTo(0.0, duration: const Duration(milliseconds: 300));
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _animController.removeStatusListener(_onAnimationStatusChanged);
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _Tool3DIsoPainter(
            toolType: widget.toolType,
            progress: _animation.value,
            isActive: widget.isActive,
            isHovered: widget.isHovered,
            primaryColor: widget.primaryColor ?? const Color(0xFF0284C7),
            accentColor: widget.accentColor ?? const Color(0xFFF59E0B),
          ),
        );
      },
    );
  }
}

/// Custom isometric painter rendering 3D sheet metal geometry and mechanical actions.
class _Tool3DIsoPainter extends CustomPainter {
  final Tool3DType toolType;
  final double progress;
  final bool isActive;
  final bool isHovered;
  final Color primaryColor;
  final Color accentColor;

  _Tool3DIsoPainter({
    required this.toolType,
    required this.progress,
    required this.isActive,
    required this.isHovered,
    required this.primaryColor,
    required this.accentColor,
  });

  // Isometric 30-degree projection constants
  static const double _cos30 = 0.8660254;
  static const double _sin30 = 0.5;

  Offset _project(double cx, double cy, double x, double y, double z, double s) {
    final px = cx + (x - y) * _cos30 * s;
    final py = cy + (x + y) * _sin30 * s - (z * s);
    return Offset(px, py);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width / 32.0;

    switch (toolType) {
      case Tool3DType.addBend:
        _paintBendLine(canvas, cx, cy, scale);
        break;
      case Tool3DType.addFlange:
        _paintReturnFlange(canvas, cx, cy, scale);
        break;
      case Tool3DType.addCut:
        _paintLaserCut(canvas, cx, cy, scale);
        break;
      case Tool3DType.drawRectangle:
        _paintRectanglePunch(canvas, cx, cy, scale);
        break;
      case Tool3DType.drawCircle:
        _paintCirclePunch(canvas, cx, cy, scale);
        break;
      case Tool3DType.addPunchObround:
        _paintSlotPunch(canvas, cx, cy, scale);
        break;
      case Tool3DType.drawArc:
        _paintArc(canvas, cx, cy, scale);
        break;
      case Tool3DType.drawPolyline:
        _paintPolyline(canvas, cx, cy, scale);
        break;
      case Tool3DType.select:
        _paintSelect(canvas, cx, cy, scale);
        break;
      case Tool3DType.setBaseAnchor:
        _paintBaseAnchor(canvas, cx, cy, scale);
        break;
      case Tool3DType.cornerFillet:
        _paintCornerFillet(canvas, cx, cy, scale);
        break;
      case Tool3DType.cornerChamfer:
        _paintCornerChamfer(canvas, cx, cy, scale);
        break;
      case Tool3DType.perforationPattern:
        _paintPerforationPattern(canvas, cx, cy, scale);
        break;
      case Tool3DType.addDimension:
        _paintDimensionalConstraint(canvas, cx, cy, scale);
        break;
      case Tool3DType.dragDimension:
        _paintDimensionMeasurement(canvas, cx, cy, scale);
        break;
      case Tool3DType.modifyMirror:
        _paintMirror(canvas, cx, cy, scale);
        break;
      case Tool3DType.constructionToggle:
        _paintConstruction(canvas, cx, cy, scale);
        break;
      case Tool3DType.pressBrake:
        _paintPressBrake(canvas, cx, cy, scale);
        break;
      case Tool3DType.punchTooling:
        _paintPunchTooling(canvas, cx, cy, scale);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Bend Line Tool: Sheet metal folds upward 0° -> 90°
  // ---------------------------------------------------------------------------
  void _paintBendLine(Canvas canvas, double cx, double cy, double s) {
    const tMm = 1.8;
    const lHalf = 8.0;
    const w = 11.0;

    // Fixed left sheet half: (-lHalf to 0) in X, (-w/2 to w/2) in Y
    final p0 = _project(cx, cy, -lHalf, -w / 2, 0, s);
    final p1 = _project(cx, cy, 0, -w / 2, 0, s);
    final p2 = _project(cx, cy, 0, w / 2, 0, s);
    final p3 = _project(cx, cy, -lHalf, w / 2, 0, s);

    // Thickness bottom
    final p0b = _project(cx, cy, -lHalf, -w / 2, -tMm, s);
    final p3b = _project(cx, cy, -lHalf, w / 2, -tMm, s);

    // Draw Left Fixed Sheet
    final leftTop = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    final leftEdge = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p3b.dx, p3b.dy)
      ..lineTo(p0b.dx, p0b.dy)
      ..close();

    final metalTopPaint = Paint()..color = const Color(0xFF94A3B8);
    final metalEdgePaint = Paint()..color = const Color(0xFF475569);
    final strokePaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(leftEdge, metalEdgePaint);
    canvas.drawPath(leftTop, metalTopPaint);
    canvas.drawPath(leftTop, strokePaint);

    // Dynamic Folding Right Flange
    // Angle bends from 0 (flat) to pi/2 (90 deg vertical)
    final bendAngle = progress * (math.pi / 2);
    final cosA = math.cos(bendAngle);
    final sinA = math.sin(bendAngle);

    final fX = lHalf * cosA;
    final fZ = lHalf * sinA;

    final r0 = _project(cx, cy, 0, -w / 2, 0, s);
    final r1 = _project(cx, cy, fX, -w / 2, fZ, s);
    final r2 = _project(cx, cy, fX, w / 2, fZ, s);
    final r3 = _project(cx, cy, 0, w / 2, 0, s);

    // Thickness for folding flange
    final r1b = _project(cx, cy, fX - tMm * sinA, -w / 2, fZ - tMm * cosA, s);
    final r2b = _project(cx, cy, fX - tMm * sinA, w / 2, fZ - tMm * cosA, s);

    final rightTop = Path()
      ..moveTo(r0.dx, r0.dy)
      ..lineTo(r1.dx, r1.dy)
      ..lineTo(r2.dx, r2.dy)
      ..lineTo(r3.dx, r3.dy)
      ..close();
    final rightEdge = Path()
      ..moveTo(r1.dx, r1.dy)
      ..lineTo(r2.dx, r2.dy)
      ..lineTo(r2b.dx, r2b.dy)
      ..lineTo(r1b.dx, r1b.dy)
      ..close();

    final foldColor = Color.lerp(const Color(0xFF38BDF8), const Color(0xFF0284C7), progress)!;
    canvas.drawPath(rightEdge, Paint()..color = const Color(0xFF0369A1));
    canvas.drawPath(rightTop, Paint()..color = foldColor);
    canvas.drawPath(rightTop, strokePaint);

    // Glowing Bend Line at fold hinge
    final bendLinePaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(r0, r3, bendLinePaint);

    // Animated Bend Arc indicator arrow
    if (progress > 0.05) {
      final arcPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final arcP = _project(cx, cy, lHalf * 0.7 * cosA, w / 2 + 1.5, lHalf * 0.7 * sinA, s);
      final flatP = _project(cx, cy, lHalf * 0.7, w / 2 + 1.5, 0, s);
      canvas.drawLine(flatP, arcP, arcPaint);
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Return Flange: Sprouting edge flange bending upward
  // ---------------------------------------------------------------------------
  void _paintReturnFlange(Canvas canvas, double cx, double cy, double s) {
    const baseW = 14.0;
    const baseL = 10.0;
    const tMm = 1.6;

    // Base plate
    final b0 = _project(cx, cy, -baseL / 2, -baseW / 2, 0, s);
    final b1 = _project(cx, cy, baseL / 2, -baseW / 2, 0, s);
    final b2 = _project(cx, cy, baseL / 2, baseW / 2, 0, s);
    final b3 = _project(cx, cy, -baseL / 2, baseW / 2, 0, s);

    final basePath = Path()
      ..moveTo(b0.dx, b0.dy)
      ..lineTo(b1.dx, b1.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(b3.dx, b3.dy)
      ..close();
    canvas.drawPath(basePath, Paint()..color = const Color(0xFF94A3B8));
    canvas.drawPath(
      basePath,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Upright Flange growing from top edge (b1 to b2)
    final flangeHeight = (3.0 + progress * 6.5);
    final f1 = _project(cx, cy, baseL / 2, -baseW / 2, flangeHeight, s);
    final f2 = _project(cx, cy, baseL / 2, baseW / 2, flangeHeight, s);

    final flangePath = Path()
      ..moveTo(b1.dx, b1.dy)
      ..lineTo(f1.dx, f1.dy)
      ..lineTo(f2.dx, f2.dy)
      ..lineTo(b2.dx, b2.dy)
      ..close();
    canvas.drawPath(flangePath, Paint()..color = const Color(0xFF0284C7));
    canvas.drawPath(
      flangePath,
      Paint()
        ..color = const Color(0xFF0C4A6E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Thickness side edge
    final f1t = _project(cx, cy, baseL / 2 - tMm, -baseW / 2, flangeHeight, s);
    final b1t = _project(cx, cy, baseL / 2 - tMm, -baseW / 2, 0, s);
    final sidePath = Path()
      ..moveTo(b1.dx, b1.dy)
      ..lineTo(b1t.dx, b1t.dy)
      ..lineTo(f1t.dx, f1t.dy)
      ..lineTo(f1.dx, f1.dy)
      ..close();
    canvas.drawPath(sidePath, Paint()..color = const Color(0xFF0369A1));

    // Glowing return arrow
    final arrowPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(b2, f2, arrowPaint);
  }

  // ---------------------------------------------------------------------------
  // 3. Laser Cut / Slit: Laser nozzle traveling & emitting cutting beam + sparks
  // ---------------------------------------------------------------------------
  void _paintLaserCut(Canvas canvas, double cx, double cy, double s) {
    // Metal sheet
    final p0 = _project(cx, cy, -8, -8, 0, s);
    final p1 = _project(cx, cy, 8, -8, 0, s);
    final p2 = _project(cx, cy, 8, 8, 0, s);
    final p3 = _project(cx, cy, -8, 8, 0, s);

    final sheet = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(sheet, Paint()..color = const Color(0xFF94A3B8));
    canvas.drawPath(
      sheet,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Cut path start & end
    const startX = -6.0, startY = -4.0;
    const endX = 6.0, endY = 4.0;

    final currX = startX + (endX - startX) * progress;
    final currY = startY + (endY - startY) * progress;

    final cutStart = _project(cx, cy, startX, startY, 0, s);
    final cutCurr = _project(cx, cy, currX, currY, 0, s);

    // Cut slit line (glows orange/cyan)
    canvas.drawLine(
      cutStart,
      cutCurr,
      Paint()
        ..color = const Color(0xFFDC2626)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // Laser nozzle hovering above
    final nozzlePos = _project(cx, cy, currX, currY, 6.0, s);

    // Laser beam firing down
    canvas.drawLine(
      nozzlePos,
      cutCurr,
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Nozzle tip
    canvas.drawCircle(nozzlePos, 2.2 * s, Paint()..color = const Color(0xFF334155));
    canvas.drawCircle(nozzlePos, 1.2 * s, Paint()..color = const Color(0xFF38BDF8));

    // Sparks at cut point
    if (progress > 0.05) {
      final sparkPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 1.0;
      canvas.drawLine(cutCurr, cutCurr + Offset(2 * s, -3 * s), sparkPaint);
      canvas.drawLine(cutCurr, cutCurr + Offset(-2.5 * s, -1.5 * s), sparkPaint);
      canvas.drawLine(cutCurr, cutCurr + Offset(1.5 * s, 2 * s), sparkPaint);
    }
  }

  // ---------------------------------------------------------------------------
  // 4. Rectangle / Square Punch: Die descends & stamps rectangular cutout
  // ---------------------------------------------------------------------------
  void _paintRectanglePunch(Canvas canvas, double cx, double cy, double s) {
    // Metal sheet
    final p0 = _project(cx, cy, -9, -9, 0, s);
    final p1 = _project(cx, cy, 9, -9, 0, s);
    final p2 = _project(cx, cy, 9, 9, 0, s);
    final p3 = _project(cx, cy, -9, 9, 0, s);

    final sheet = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(sheet, Paint()..color = const Color(0xFF94A3B8));
    canvas.drawPath(
      sheet,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Punch hole in sheet
    final h0 = _project(cx, cy, -4, -4, 0, s);
    final h1 = _project(cx, cy, 4, -4, 0, s);
    final h2 = _project(cx, cy, 4, 4, 0, s);
    final h3 = _project(cx, cy, -4, 4, 0, s);

    final hole = Path()
      ..moveTo(h0.dx, h0.dy)
      ..lineTo(h1.dx, h1.dy)
      ..lineTo(h2.dx, h2.dy)
      ..lineTo(h3.dx, h3.dy)
      ..close();
    canvas.drawPath(hole, Paint()..color = const Color(0xFF0F172A)); // Void cutout

    // Punch die block descending from above
    // Height drops from 8mm to 0mm
    final dieZ = (1.0 - progress) * 8.0;
    const dieH = 4.5;
    final d1 = _project(cx, cy, 4, -4, dieZ, s);
    final d2 = _project(cx, cy, 4, 4, dieZ, s);
    final d3 = _project(cx, cy, -4, 4, dieZ, s);

    final dt0 = _project(cx, cy, -4, -4, dieZ + dieH, s);
    final dt1 = _project(cx, cy, 4, -4, dieZ + dieH, s);
    final dt2 = _project(cx, cy, 4, 4, dieZ + dieH, s);
    final dt3 = _project(cx, cy, -4, 4, dieZ + dieH, s);

    // Front-Left face (shaded side)
    final leftFace = Path()
      ..moveTo(d3.dx, d3.dy)
      ..lineTo(d2.dx, d2.dy)
      ..lineTo(dt2.dx, dt2.dy)
      ..lineTo(dt3.dx, dt3.dy)
      ..close();

    // Front-Right face (direct light)
    final rightFace = Path()
      ..moveTo(d1.dx, d1.dy)
      ..lineTo(d2.dx, d2.dy)
      ..lineTo(dt2.dx, dt2.dy)
      ..lineTo(dt1.dx, dt1.dy)
      ..close();

    // Top face (highlight)
    final topFace = Path()
      ..moveTo(dt0.dx, dt0.dy)
      ..lineTo(dt1.dx, dt1.dy)
      ..lineTo(dt2.dx, dt2.dy)
      ..lineTo(dt3.dx, dt3.dy)
      ..close();

    final outlinePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    canvas.drawPath(leftFace, Paint()..color = const Color(0xFF0369A1));
    canvas.drawPath(leftFace, outlinePaint);

    canvas.drawPath(rightFace, Paint()..color = const Color(0xFF0284C7));
    canvas.drawPath(rightFace, outlinePaint);

    canvas.drawPath(topFace, Paint()..color = const Color(0xFF38BDF8));
    canvas.drawPath(topFace, outlinePaint);
  }

  // ---------------------------------------------------------------------------
  // 5. Circle Punch: Cylindrical die descending & punching circular hole
  // ---------------------------------------------------------------------------
  void _paintCirclePunch(Canvas canvas, double cx, double cy, double s) {
    // Metal sheet
    final p0 = _project(cx, cy, -9, -9, 0, s);
    final p1 = _project(cx, cy, 9, -9, 0, s);
    final p2 = _project(cx, cy, 9, 9, 0, s);
    final p3 = _project(cx, cy, -9, 9, 0, s);

    final sheet = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(sheet, Paint()..color = const Color(0xFF94A3B8));
    canvas.drawPath(
      sheet,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Hole ellipse
    final center = _project(cx, cy, 0, 0, 0, s);
    final holeRect = Rect.fromCenter(center: center, width: 9 * s, height: 5.5 * s);
    canvas.drawOval(holeRect, Paint()..color = const Color(0xFF0F172A));

    // Punch cylinder descending
    final dieZ = (1.0 - progress) * 7.5;
    final dieCenter = _project(cx, cy, 0, 0, dieZ, s);
    final dieTopCenter = _project(cx, cy, 0, 0, dieZ + 4.5, s);

    // Cylinder body
    final dieRectBottom = Rect.fromCenter(center: dieCenter, width: 8.5 * s, height: 5 * s);
    final dieRectTop = Rect.fromCenter(center: dieTopCenter, width: 8.5 * s, height: 5 * s);

    final bodyPath = Path()
      ..moveTo(dieRectBottom.left, dieCenter.dy)
      ..lineTo(dieRectTop.left, dieTopCenter.dy)
      ..arcTo(dieRectTop, math.pi, -math.pi, false)
      ..lineTo(dieRectBottom.right, dieCenter.dy)
      ..arcTo(dieRectBottom, 0, math.pi, false)
      ..close();

    canvas.drawPath(bodyPath, Paint()..color = const Color(0xFF0284C7));
    canvas.drawOval(dieRectTop, Paint()..color = const Color(0xFF38BDF8));
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Slot / Obround Punch: Racetrack slot punch die stamping
  // ---------------------------------------------------------------------------
  void _paintSlotPunch(Canvas canvas, double cx, double cy, double s) {
    // Metal sheet
    final p0 = _project(cx, cy, -9, -7, 0, s);
    final p1 = _project(cx, cy, 9, -7, 0, s);
    final p2 = _project(cx, cy, 9, 7, 0, s);
    final p3 = _project(cx, cy, -9, 7, 0, s);

    final sheet = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(sheet, Paint()..color = const Color(0xFF94A3B8));
    canvas.drawPath(
      sheet,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Slot cutout on sheet
    final sLeft = _project(cx, cy, -4, 0, 0, s);
    final sRight = _project(cx, cy, 4, 0, 0, s);
    canvas.drawLine(
      sLeft,
      sRight,
      Paint()
        ..color = const Color(0xFF0F172A)
        ..strokeWidth = 4.5 * s
        ..strokeCap = StrokeCap.round,
    );

    // Descending Slot Die
    final dieZ = (1.0 - progress) * 7.0;
    final dLeft = _project(cx, cy, -4, 0, dieZ, s);
    final dRight = _project(cx, cy, 4, 0, dieZ, s);

    canvas.drawLine(
      dLeft,
      dRight,
      Paint()
        ..color = const Color(0xFF0284C7)
        ..strokeWidth = 4.0 * s
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      _project(cx, cy, -4, 0, dieZ + 3.5, s),
      _project(cx, cy, 4, 0, dieZ + 3.5, s),
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 3.2 * s
        ..strokeCap = StrokeCap.round,
    );
  }

  // ---------------------------------------------------------------------------
  // 7. 3-Point Arc: Animated curving arc sweep
  // ---------------------------------------------------------------------------
  void _paintArc(Canvas canvas, double cx, double cy, double s) {
    final p1 = _project(cx, cy, -8, 5, 0, s);
    final p2 = _project(cx, cy, 0, -6, 0, s);
    final p3 = _project(cx, cy, 8, 4, 0, s);

    // Draw control anchor nodes
    final nodePaint = Paint()..color = const Color(0xFF0284C7);
    canvas.drawCircle(p1, 1.8 * s, nodePaint);
    canvas.drawCircle(p2, 1.8 * s, nodePaint);
    canvas.drawCircle(p3, 1.8 * s, nodePaint);

    // Sweeping arc path
    final arcPath = Path()..moveTo(p1.dx, p1.dy);
    // Quadratic bezier curve interpolating progress
    final sweepT = 0.2 + progress * 0.8;
    final qCtrl = Offset.lerp(p1, p2, sweepT)!;
    final qEnd = Offset.lerp(p2, p3, sweepT)!;
    arcPath.quadraticBezierTo(qCtrl.dx, qCtrl.dy, qEnd.dx, qEnd.dy);

    final strokePaint = Paint()
      ..color = const Color(0xFF00BCD4)
      ..strokeWidth = 2.0 * s
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(arcPath, strokePaint);

    // Glowing tip
    canvas.drawCircle(qEnd, 2.2 * s, Paint()..color = const Color(0xFFF59E0B));
  }

  // ---------------------------------------------------------------------------
  // 8. Line / Polyline: 3D CAD stylus drawing vector lines
  // ---------------------------------------------------------------------------
  void _paintPolyline(Canvas canvas, double cx, double cy, double s) {
    final startP = _project(cx, cy, -8, -6, 0, s);
    final endP = _project(cx, cy, 8, 6, 0, s);
    final currP = Offset.lerp(startP, endP, 0.15 + progress * 0.85)!;

    // Drawn line segment
    canvas.drawLine(
      startP,
      currP,
      Paint()
        ..color = const Color(0xFF0284C7)
        ..strokeWidth = 2.0 * s
        ..strokeCap = StrokeCap.round,
    );

    // End node vertices
    canvas.drawCircle(startP, 2.0 * s, Paint()..color = const Color(0xFF0369A1));
    canvas.drawCircle(currP, 2.2 * s, Paint()..color = const Color(0xFF38BDF8));

    // Stylus / laser pen head hovering over currP
    final penTop = currP + Offset(2 * s, -7 * s);
    final penPath = Path()
      ..moveTo(currP.dx, currP.dy)
      ..lineTo(penTop.dx - 1.5 * s, penTop.dy)
      ..lineTo(penTop.dx + 1.5 * s, penTop.dy)
      ..close();
    canvas.drawPath(penPath, Paint()..color = const Color(0xFF334155));
  }

  // ---------------------------------------------------------------------------
  // 9. Select: 3D cursor hovering down, clicking, triggering face selection ripple
  // ---------------------------------------------------------------------------
  void _paintSelect(Canvas canvas, double cx, double cy, double s) {
    // Metal sheet plate
    final p0 = _project(cx, cy, -8, -8, 0, s);
    final p1 = _project(cx, cy, 8, -8, 0, s);
    final p2 = _project(cx, cy, 8, 8, 0, s);
    final p3 = _project(cx, cy, -8, 8, 0, s);

    final sheet = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    final isSelected = progress > 0.4;
    final plateColor = isSelected ? const Color(0xFFBAE6FD) : const Color(0xFF94A3B8);
    canvas.drawPath(sheet, Paint()..color = plateColor);
    canvas.drawPath(
      sheet,
      Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 1.4 : 0.8,
    );

    // Ripple effect on face
    if (progress > 0.3) {
      final rRadius = (progress - 0.3) * 12.0 * s;
      final center = _project(cx, cy, 0, 0, 0, s);
      final rippleRect = Rect.fromCenter(center: center, width: rRadius * 1.5, height: rRadius * 0.9);
      final alpha = (1.0 - (progress - 0.3) / 0.7).clamp(0.0, 1.0);
      canvas.drawOval(
        rippleRect,
        Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // 3D Pointer Arrow
    final arrowOffset = Offset(-2 * s, (-4 + progress * 3) * s);
    final aTip = _project(cx, cy, 0, 0, 4, s) + arrowOffset;
    final aPath = Path()
      ..moveTo(aTip.dx, aTip.dy)
      ..lineTo(aTip.dx, aTip.dy + 8 * s)
      ..lineTo(aTip.dx + 2.5 * s, aTip.dy + 5.5 * s)
      ..lineTo(aTip.dx + 5.5 * s, aTip.dy + 8 * s)
      ..lineTo(aTip.dx + 7 * s, aTip.dy + 6.5 * s)
      ..lineTo(aTip.dx + 4 * s, aTip.dy + 4 * s)
      ..lineTo(aTip.dx + 7 * s, aTip.dy + 4 * s)
      ..close();

    canvas.drawPath(aPath, Paint()..color = const Color(0xFF0F172A));
    canvas.drawPath(
      aPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  // ---------------------------------------------------------------------------
  // 10. Base Floor Anchor: Clamping fixture anchoring plate
  // ---------------------------------------------------------------------------
  void _paintBaseAnchor(Canvas canvas, double cx, double cy, double s) {
    // Metal plate
    final p0 = _project(cx, cy, -8, -8, 0, s);
    final p1 = _project(cx, cy, 8, -8, 0, s);
    final p2 = _project(cx, cy, 8, 8, 0, s);
    final p3 = _project(cx, cy, -8, 8, 0, s);

    final sheet = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(sheet, Paint()..color = const Color(0xFFFEF3C7));
    canvas.drawPath(
      sheet,
      Paint()
        ..color = const Color(0xFFD97706)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Anchor clamp lowering onto plate
    final clampZ = (1.0 - progress) * 6.0;
    final cPos = _project(cx, cy, 0, 0, clampZ, s);

    // Anchor symbol in 3D
    final anchorPaint = Paint()
      ..color = const Color(0xFFD97706)
      ..strokeWidth = 1.8 * s
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(cPos + Offset(0, -5 * s), cPos + Offset(0, 3 * s), anchorPaint);
    canvas.drawArc(Rect.fromCenter(center: cPos + Offset(0, 1 * s), width: 7 * s, height: 6 * s), 0.2, math.pi - 0.4, false, anchorPaint);
    canvas.drawCircle(cPos + Offset(0, -5 * s), 1.5 * s, Paint()..color = const Color(0xFFB45309));
  }

  // ---------------------------------------------------------------------------
  // 11. Corner Fillet: Sharp corner rounding into tangent radius
  // ---------------------------------------------------------------------------
  void _paintCornerFillet(Canvas canvas, double cx, double cy, double s) {
    final corner = _project(cx, cy, 0, 0, 0, s);
    final top = _project(cx, cy, 0, -8, 0, s);
    final right = _project(cx, cy, 8, 0, 0, s);

    // Sharp corner outline
    final sharpPath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(corner.dx, corner.dy)
      ..lineTo(right.dx, right.dy);
    canvas.drawPath(
      sharpPath,
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Fillet curve smoothly interpolating
    final fRadius = progress * 6.0;
    final fTop = _project(cx, cy, 0, -fRadius, 0, s);
    final fRight = _project(cx, cy, fRadius, 0, 0, s);

    final filletPath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(fTop.dx, fTop.dy)
      ..quadraticBezierTo(corner.dx, corner.dy, fRight.dx, fRight.dy)
      ..lineTo(right.dx, right.dy);

    canvas.drawPath(
      filletPath,
      Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Dimension radius R tag
    if (progress > 0.3) {
      canvas.drawCircle(corner, 1.2 * s, Paint()..color = const Color(0xFFF59E0B));
    }
  }

  // ---------------------------------------------------------------------------
  // 12. Corner Chamfer: 45° corner cutting blade
  // ---------------------------------------------------------------------------
  void _paintCornerChamfer(Canvas canvas, double cx, double cy, double s) {
    final top = _project(cx, cy, 0, -8, 0, s);
    final right = _project(cx, cy, 8, 0, 0, s);

    // Chamfer points
    final cCut = progress * 5.5;
    final cTop = _project(cx, cy, 0, -cCut, 0, s);
    final cRight = _project(cx, cy, cCut, 0, 0, s);

    final chamferPath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(cTop.dx, cTop.dy)
      ..lineTo(cRight.dx, cRight.dy)
      ..lineTo(right.dx, right.dy);

    canvas.drawPath(
      chamferPath,
      Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Bevel blade slicing
    if (progress > 0.1) {
      canvas.drawLine(
        cTop,
        cRight,
        Paint()
          ..color = const Color(0xFFEF4444)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 13. Perforation Pattern: 2x2 grid of punch pins stamping in rhythm
  // ---------------------------------------------------------------------------
  void _paintPerforationPattern(Canvas canvas, double cx, double cy, double s) {
    // Metal sheet
    final p0 = _project(cx, cy, -9, -9, 0, s);
    final p1 = _project(cx, cy, 9, -9, 0, s);
    final p2 = _project(cx, cy, 9, 9, 0, s);
    final p3 = _project(cx, cy, -9, 9, 0, s);

    final sheet = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(sheet, Paint()..color = const Color(0xFF94A3B8));

    // 4 Pin holes
    final coords = [
      [-4.0, -4.0],
      [4.0, -4.0],
      [-4.0, 4.0],
      [4.0, 4.0],
    ];

    for (final c in coords) {
      final center = _project(cx, cy, c[0], c[1], 0, s);
      canvas.drawOval(Rect.fromCenter(center: center, width: 4.5 * s, height: 2.8 * s), Paint()..color = const Color(0xFF0F172A));

      // Descending pin
      final pinZ = (1.0 - progress) * 6.0;
      final pinCenter = _project(cx, cy, c[0], c[1], pinZ, s);
      canvas.drawCircle(pinCenter, 1.8 * s, Paint()..color = const Color(0xFF38BDF8));
    }
  }

  // ---------------------------------------------------------------------------
  // 14. Dimensional Constraints: Parametric lock badge with dual constraint rails
  // ---------------------------------------------------------------------------
  void _paintDimensionalConstraint(Canvas canvas, double cx, double cy, double s) {
    // 1. Two parallel reference geometry guide rails (left & right bars)
    final lTop = _project(cx, cy, -7.5, -6, 0, s);
    final lBot = _project(cx, cy, -7.5, 6, 0, s);
    final rTop = _project(cx, cy, 7.5, -6, 0, s);
    final rBot = _project(cx, cy, 7.5, 6, 0, s);

    final railPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2.0 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(lTop, lBot, railPaint);
    canvas.drawLine(rTop, rBot, railPaint);

    // Rail anchor end caps
    final capPaint = Paint()..color = const Color(0xFF38BDF8);
    canvas.drawCircle(lTop, 1.3 * s, capPaint);
    canvas.drawCircle(lBot, 1.3 * s, capPaint);
    canvas.drawCircle(rTop, 1.3 * s, capPaint);
    canvas.drawCircle(rBot, 1.3 * s, capPaint);

    // 2. Central constraint tie line
    final cLeft = _project(cx, cy, -7.5, 0, 2.5, s);
    final cRight = _project(cx, cy, 7.5, 0, 2.5, s);

    final tiePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.4 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(cLeft, cRight, tiePaint);

    // Opposing constraint limit ticks
    final tickH = 2.2 * s;
    canvas.drawLine(cLeft + Offset(0, -tickH), cLeft + Offset(0, tickH), tiePaint);
    canvas.drawLine(cRight + Offset(0, -tickH), cRight + Offset(0, tickH), tiePaint);

    // Constraint inward arrows
    final arrowL = Path()
      ..moveTo(cLeft.dx + 3.0 * s, cLeft.dy - 2.0 * s)
      ..lineTo(cLeft.dx, cLeft.dy)
      ..lineTo(cLeft.dx + 3.0 * s, cLeft.dy + 2.0 * s);
    final arrowR = Path()
      ..moveTo(cRight.dx - 3.0 * s, cRight.dy - 2.0 * s)
      ..lineTo(cRight.dx, cRight.dy)
      ..lineTo(cRight.dx - 3.0 * s, cRight.dy + 2.0 * s);
    final arrowPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(arrowL, arrowPaint);
    canvas.drawPath(arrowR, arrowPaint);

    // 3. Central 3D Parametric Lock Glyph
    final centerPos = (cLeft + cRight) / 2;
    // Dynamic lock animation: shackle clicks down when progress -> 1.0
    final shackleDrop = (1.0 - progress) * 2.2 * s;

    // Lock Shackle (U-shape)
    final shacklePath = Path()
      ..moveTo(centerPos.dx - 2.4 * s, centerPos.dy - (3.5 * s - shackleDrop))
      ..lineTo(centerPos.dx - 2.4 * s, centerPos.dy - (6.0 * s - shackleDrop))
      ..arcToPoint(Offset(centerPos.dx + 2.4 * s, centerPos.dy - (6.0 * s - shackleDrop)), radius: Radius.circular(2.4 * s))
      ..lineTo(centerPos.dx + 2.4 * s, centerPos.dy - (3.5 * s - shackleDrop));

    canvas.drawPath(
      shacklePath,
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s
        ..strokeCap = StrokeCap.round,
    );

    // Lock Body (Solid golden-amber parametric lock)
    final bodyRect = Rect.fromCenter(center: centerPos + Offset(0, 0.5 * s), width: 7.5 * s, height: 6.5 * s);
    final bodyRRect = RRect.fromRectAndRadius(bodyRect, Radius.circular(1.5 * s));

    // Shadow
    canvas.drawRRect(bodyRRect.shift(Offset(0, 1.0 * s)), Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.4));

    // Lock body fill
    canvas.drawRRect(bodyRRect, Paint()..color = const Color(0xFFF59E0B));
    // Lock body border
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = const Color(0xFFD97706)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * s,
    );

    // Keyhole / constraint slot
    canvas.drawCircle(centerPos + Offset(0, -0.3 * s), 0.9 * s, Paint()..color = const Color(0xFF0F172A));
    canvas.drawRect(Rect.fromCenter(center: centerPos + Offset(0, 1.0 * s), width: 0.8 * s, height: 1.4 * s), Paint()..color = const Color(0xFF0F172A));
  }

  // ---------------------------------------------------------------------------
  // 14b. Dimension Measurement: Interactive 2-point ruler with expanding witness lines
  // ---------------------------------------------------------------------------
  void _paintDimensionMeasurement(Canvas canvas, double cx, double cy, double s) {
    // Dynamic Point A (fixed origin) and Point B (dragged out dynamically)
    final pA = _project(cx, cy, -7.5, 0, 0, s);
    // Point B extends outward dynamically with animation progress
    final dynamicX = -7.5 + (15.0 * (0.35 + progress * 0.65));
    final pB = _project(cx, cy, dynamicX, 0, 0, s);

    // 1. Anchor feature bullseye crosshairs on sheet surface
    // Point A Anchor
    canvas.drawCircle(pA, 2.8 * s, Paint()..color = const Color(0xFF0EA5E9).withValues(alpha: 0.25));
    canvas.drawCircle(pA, 1.4 * s, Paint()..color = const Color(0xFF0284C7));
    canvas.drawCircle(pA, 0.6 * s, Paint()..color = Colors.white);

    // Point B Anchor (dynamic)
    canvas.drawCircle(pB, 2.8 * s, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.25));
    canvas.drawCircle(pB, 1.4 * s, Paint()..color = const Color(0xFFD97706));
    canvas.drawCircle(pB, 0.6 * s, Paint()..color = Colors.white);

    // 2. Extending Witness Lines rising in Z
    final extH = 4.0 + progress * 4.0;
    final wA = _project(cx, cy, -7.5, 0, extH, s);
    final wB = _project(cx, cy, dynamicX, 0, extH, s);

    final witnessPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.0 * s;
    canvas.drawLine(pA, wA + Offset(0, -1.5 * s), witnessPaint);
    canvas.drawLine(pB, wB + Offset(0, -1.5 * s), witnessPaint);

    // 3. Dimension span line between witness lines
    final spanPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.5 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(wA, wB, spanPaint);

    // Dimension Arrowheads pointing outwards
    final arrowA = Path()
      ..moveTo(wA.dx + 3.0 * s, wA.dy - 2.0 * s)
      ..lineTo(wA.dx, wA.dy)
      ..lineTo(wA.dx + 3.0 * s, wA.dy + 2.0 * s);
    final arrowB = Path()
      ..moveTo(wB.dx - 3.0 * s, wB.dy - 2.0 * s)
      ..lineTo(wB.dx, wB.dy)
      ..lineTo(wB.dx - 3.0 * s, wB.dy + 2.0 * s);
    final arrowStroke = Paint()
      ..color = const Color(0xFFD97706)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(arrowA, arrowStroke);
    canvas.drawPath(arrowB, arrowStroke);

    // 4. Floating Dimension Measurement Chip with ruler scale ticks
    final centerDim = (wA + wB) / 2 + Offset(0, -4.0 * s);
    final chipWidth = 12.0 * s;
    final chipHeight = 5.5 * s;
    final chipRRect = RRect.fromRectAndRadius(Rect.fromCenter(center: centerDim, width: chipWidth, height: chipHeight), Radius.circular(1.8 * s));

    // Chip shadow & body
    canvas.drawRRect(chipRRect.shift(Offset(0, 1.0 * s)), Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.35));
    canvas.drawRRect(chipRRect, Paint()..color = const Color(0xFF0F172A));
    canvas.drawRRect(
      chipRRect,
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 * s,
    );

    // Ruler measurement scale ticks inside chip
    final tickPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 0.8 * s;
    final startTickX = centerDim.dx - 4.0 * s;
    for (int i = 0; i < 5; i++) {
      final tx = startTickX + i * 2.0 * s;
      final th = (i % 2 == 0) ? 2.5 * s : 1.5 * s;
      canvas.drawLine(Offset(tx, centerDim.dy - th / 2), Offset(tx, centerDim.dy + th / 2), tickPaint);
    }
  }

  // ---------------------------------------------------------------------------
  // 15. Mirror: Central mirror plane reflecting geometry
  // ---------------------------------------------------------------------------
  void _paintMirror(Canvas canvas, double cx, double cy, double s) {
    // Mirror plane at X=0
    final m0 = _project(cx, cy, 0, -8, 0, s);
    final m1 = _project(cx, cy, 0, 8, 0, s);
    final m2 = _project(cx, cy, 0, 8, 8, s);
    final m3 = _project(cx, cy, 0, -8, 8, s);

    final mPath = Path()
      ..moveTo(m0.dx, m0.dy)
      ..lineTo(m1.dx, m1.dy)
      ..lineTo(m2.dx, m2.dy)
      ..lineTo(m3.dx, m3.dy)
      ..close();
    canvas.drawPath(mPath, Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.35));
    canvas.drawPath(
      mPath,
      Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Left shape
    final lP = _project(cx, cy, -5, 0, 3, s);
    canvas.drawCircle(lP, 2.5 * s, Paint()..color = const Color(0xFF0284C7));

    // Reflected right shape (fades in with progress)
    final rP = _project(cx, cy, 5, 0, 3, s);
    final rAlpha = (0.2 + progress * 0.8).clamp(0.0, 1.0);
    canvas.drawCircle(rP, 2.5 * s, Paint()..color = const Color(0xFF10B981).withValues(alpha: rAlpha));
  }

  // ---------------------------------------------------------------------------
  // 16. Construction Toggle: Solid lines morphing to dashed lines
  // ---------------------------------------------------------------------------
  void _paintConstruction(Canvas canvas, double cx, double cy, double s) {
    final startP = _project(cx, cy, -8, 0, 0, s);
    final endP = _project(cx, cy, 8, 0, 0, s);

    // Dashed line segments
    const segments = 5;
    for (int i = 0; i < segments; i++) {
      if (i % 2 == 0 || progress < 0.5) {
        final t0 = i / segments;
        final t1 = (i + 0.8) / segments;
        final pA = Offset.lerp(startP, endP, t0)!;
        final pB = Offset.lerp(startP, endP, t1)!;
        canvas.drawLine(
          pA,
          pB,
          Paint()
            ..color = const Color(0xFF00BCD4)
            ..strokeWidth = 1.8 * s
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Glowing Q emblem
    final qPos = _project(cx, cy, 0, 0, 4, s);
    canvas.drawCircle(qPos, 3.0 * s, Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(qPos, 2.2 * s, Paint()..color = const Color(0xFF00BCD4).withValues(alpha: 0.3));
  }

  // ---------------------------------------------------------------------------
  // 17. Press Brake Settings: Mini ram & V-die
  // ---------------------------------------------------------------------------
  void _paintPressBrake(Canvas canvas, double cx, double cy, double s) {
    // Lower V-Die
    final v0 = _project(cx, cy, -7, 0, 0, s);
    final vMid = _project(cx, cy, 0, 0, -3, s);
    final v1 = _project(cx, cy, 7, 0, 0, s);

    final vPath = Path()
      ..moveTo(v0.dx, v0.dy)
      ..lineTo(vMid.dx, vMid.dy)
      ..lineTo(v1.dx, v1.dy);
    canvas.drawPath(
      vPath,
      Paint()
        ..color = const Color(0xFF475569)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * s,
    );

    // Upper Punch Ram descending
    final ramZ = 7.0 - (progress * 5.5);
    final rTip = _project(cx, cy, 0, 0, ramZ, s);
    final rTop0 = _project(cx, cy, -4, 0, ramZ + 5, s);
    final rTop1 = _project(cx, cy, 4, 0, ramZ + 5, s);

    final ramPath = Path()
      ..moveTo(rTip.dx, rTip.dy)
      ..lineTo(rTop0.dx, rTop0.dy)
      ..lineTo(rTop1.dx, rTop1.dy)
      ..close();
    canvas.drawPath(ramPath, Paint()..color = const Color(0xFF0284C7));
    canvas.drawPath(
      ramPath,
      Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  // ---------------------------------------------------------------------------
  // 18. Punch Tooling: Gooseneck profile
  // ---------------------------------------------------------------------------
  void _paintPunchTooling(Canvas canvas, double cx, double cy, double s) {
    final tip = _project(cx, cy, 0, 0, 0, s);
    final throat = _project(cx, cy, -4, 0, 4, s);
    final back = _project(cx, cy, 3, 0, 8, s);

    final toolProfile = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(throat.dx, throat.dy)
      ..lineTo(back.dx, back.dy)
      ..lineTo(tip.dx + 4 * s, tip.dy + 7 * s)
      ..close();

    canvas.drawPath(toolProfile, Paint()..color = const Color(0xFF38BDF8));
    canvas.drawPath(
      toolProfile,
      Paint()
        ..color = const Color(0xFF0369A1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawCircle(tip, 1.5 * s, Paint()..color = const Color(0xFFF59E0B));
  }

  @override
  bool shouldRepaint(covariant _Tool3DIsoPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.toolType != toolType || oldDelegate.isActive != isActive || oldDelegate.isHovered != isHovered;
  }
}
