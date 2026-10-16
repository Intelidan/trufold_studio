// Assembly Gizmo & Bounding Box Painters
// Modularized for TruFold MVVM Architecture

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:trufold_studio/assembly_studio/engine/assembly_docking_engine.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_docking_zone.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

// =============================================================================
// GLOBAL SCENE AXES PAINTER
// =============================================================================
class AssemblyGlobalSceneAxesPainter extends CustomPainter {
  final Size size;
  final FoldedMeshResult mesh;
  final Offset Function(CadPoint3D) projectPoint;

  AssemblyGlobalSceneAxesPainter({required this.size, required this.mesh, required this.projectPoint});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (size.width <= 0 || size.height <= 0) return;

    final originScreen = projectPoint(const CadPoint3D(0, 0, 0));
    if (originScreen == Offset.zero) return;

    final maxDim = math.max(size.width, size.height) * 2.5;

    // Helper to draw an axis given its 100mm reference point
    void drawAxis(CadPoint3D refPoint3D, Color color) {
      final refScreen = projectPoint(refPoint3D);
      if (refScreen == Offset.zero) return;
      final vec = refScreen - originScreen;
      final dist = vec.distance;
      if (dist < 0.5) return;
      final unit = Offset(vec.dx / dist, vec.dy / dist);

      final positiveEnd = originScreen + unit * maxDim;
      final negativeEnd = originScreen - unit * maxDim;

      // Positive axis: solid colored line
      final solidPaint = Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawLine(originScreen, positiveEnd, solidPaint);

      // Negative axis: dotted colored line
      final dottedPaint = Paint()
        ..color = color.withValues(alpha: 0.75)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      _drawDottedLine(canvas, originScreen, negativeEnd, dottedPaint, dashLen: 3.5, spaceLen: 3.5);
    }

    // Red Axis (X)
    drawAxis(const CadPoint3D(100.0, 0, 0), const Color(0xFFDC2626));
    // Green Axis (Y)
    drawAxis(const CadPoint3D(0, 100.0, 0), const Color(0xFF16A34A));
    // Blue Axis (Z)
    drawAxis(const CadPoint3D(0, 0, 100.0), const Color(0xFF0284C7));
  }

  void _drawDottedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {double dashLen = 3.5, double spaceLen = 3.5}) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalDist = math.sqrt(dx * dx + dy * dy);
    if (totalDist == 0) return;
    final unitX = dx / totalDist;
    final unitY = dy / totalDist;

    double currentDist = 0.0;
    while (currentDist < totalDist) {
      final segStart = Offset(p1.dx + unitX * currentDist, p1.dy + unitY * currentDist);
      final segmentEndDist = math.min(currentDist + dashLen, totalDist);
      final segEnd = Offset(p1.dx + unitX * segmentEndDist, p1.dy + unitY * segmentEndDist);
      canvas.drawLine(segStart, segEnd, paint);
      currentDist += dashLen + spaceLen;
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyGlobalSceneAxesPainter old) => true;
}

// =============================================================================
// GIZMO CUSTOM PAINTER
// =============================================================================
class AssemblyGizmoPainter extends CustomPainter {
  final AssemblyPart selectedPart;
  final Size size;
  final FoldedMeshResult mesh;
  final double azimuthDeg;
  final double elevationDeg;
  final double zoom;
  final Offset pan;
  final bool isOrthoProjection;
  final GizmoMode gizmoMode;
  final GizmoAxis activeAxis;
  final GizmoAxis lockedAxis;
  final Offset Function(CadPoint3D)? projectPoint;
  final CadPoint3D? customCenter3d;

  AssemblyGizmoPainter({
    required this.selectedPart,
    required this.size,
    required this.mesh,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.zoom,
    required this.pan,
    required this.isOrthoProjection,
    required this.gizmoMode,
    required this.activeAxis,
    this.lockedAxis = GizmoAxis.none,
    this.projectPoint,
    this.customCenter3d,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center3d = customCenter3d ?? selectedPart.position;
    final centerScreen = _project(center3d);
    if (centerScreen == Offset.zero) return;

    const double axisLen = 65.0;

    final ptX = _project(CadPoint3D(center3d.x + axisLen, center3d.y, center3d.z));
    final ptY = _project(CadPoint3D(center3d.x, center3d.y + axisLen, center3d.z));
    final ptZ = _project(CadPoint3D(center3d.x, center3d.y, center3d.z + axisLen));

    // 1. Draw extended SketchUp Axis Guideline across viewport when locked
    if (lockedAxis != GizmoAxis.none) {
      if (lockedAxis == GizmoAxis.x && ptX != Offset.zero) {
        _drawGuideline(canvas, centerScreen, ptX, const Color(0xFFEF4444), 'RED AXIS [X]');
      } else if (lockedAxis == GizmoAxis.y && ptY != Offset.zero) {
        _drawGuideline(canvas, centerScreen, ptY, const Color(0xFF10B981), 'GREEN AXIS [Y]');
      } else if (lockedAxis == GizmoAxis.z && ptZ != Offset.zero) {
        _drawGuideline(canvas, centerScreen, ptZ, const Color(0xFF38BDF8), 'BLUE AXIS [Z]');
      }
    }

    if (gizmoMode == GizmoMode.translate) {
      // X Axis (Red)
      _drawAxisArrow(canvas, centerScreen, ptX, const Color(0xFFEF4444), 'X', activeAxis == GizmoAxis.x || lockedAxis == GizmoAxis.x);
      // Y Axis (Green)
      _drawAxisArrow(canvas, centerScreen, ptY, const Color(0xFF10B981), 'Y', activeAxis == GizmoAxis.y || lockedAxis == GizmoAxis.y);
      // Z Axis (Blue)
      _drawAxisArrow(canvas, centerScreen, ptZ, const Color(0xFF38BDF8), 'Z', activeAxis == GizmoAxis.z || lockedAxis == GizmoAxis.z);
    } else {
      // SketchUp Protractor Tool (15° Snapping Graduations)
      final activeOrLocked = lockedAxis != GizmoAxis.none ? lockedAxis : activeAxis;

      if (activeOrLocked == GizmoAxis.x) {
        _drawProtractor(canvas, centerScreen, 68.0, const Color(0xFFEF4444), 'RED (X)', true);
      } else if (activeOrLocked == GizmoAxis.y) {
        _drawProtractor(canvas, centerScreen, 68.0, const Color(0xFF10B981), 'GREEN (Y)', true);
      } else if (activeOrLocked == GizmoAxis.z) {
        _drawProtractor(canvas, centerScreen, 68.0, const Color(0xFF38BDF8), 'BLUE (Z)', true);
      } else {
        // Multi-axis rotation rings with graduations
        _drawProtractor(canvas, centerScreen, 52.0, const Color(0xFFEF4444), 'X', false);
        _drawProtractor(canvas, centerScreen, 62.0, const Color(0xFF10B981), 'Y', false);
        _drawProtractor(canvas, centerScreen, 72.0, const Color(0xFF38BDF8), 'Z', false);
      }
    }

    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(centerScreen, 4.0, centerPaint);
    final centerBorder = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(centerScreen, 4.0, centerBorder);
  }

  void _drawGuideline(Canvas canvas, Offset center, Offset dirPoint, Color color, String axisName) {
    final d = dirPoint - center;
    if (d.distance < 1.0) return;
    final unit = d / d.distance;
    const double lineExt = 900.0;
    final p1 = center - unit * lineExt;

    final guidePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 1.8;

    const double dashLen = 8.0;
    const double spaceLen = 6.0;
    double dist = 0.0;
    while (dist < lineExt * 2) {
      final start = p1 + unit * dist;
      final end = p1 + unit * math.min(dist + dashLen, lineExt * 2);
      canvas.drawLine(start, end, guidePaint);
      dist += dashLen + spaceLen;
    }
  }

  void _drawProtractor(Canvas canvas, Offset center, double radius, Color color, String axisLabel, bool isActive) {
    // Semi-transparent protractor disc
    final discPaint = Paint()
      ..color = (isActive ? Colors.yellowAccent : color).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, discPaint);

    // Outer circular boundary
    final ringPaint = Paint()
      ..color = isActive ? Colors.yellowAccent : color
      ..strokeWidth = isActive ? 2.5 : 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, ringPaint);

    // Radial tick marks every 15 degrees
    for (int deg = 0; deg < 360; deg += 15) {
      final rad = deg * math.pi / 180.0;
      final isRightAngle = (deg % 90 == 0);
      final isMajor = (deg % 45 == 0);
      final tickLen = isRightAngle ? 10.0 : (isMajor ? 7.0 : 4.0);

      final pOuter = Offset(center.dx + radius * math.cos(rad), center.dy + radius * math.sin(rad));
      final pInner = Offset(center.dx + (radius - tickLen) * math.cos(rad), center.dy + (radius - tickLen) * math.sin(rad));

      final tickPaint = Paint()
        ..color = isRightAngle ? (isActive ? Colors.yellowAccent : color) : color.withValues(alpha: 0.75)
        ..strokeWidth = isMajor ? 2.0 : 1.0;
      canvas.drawLine(pInner, pOuter, tickPaint);
    }

    // Crosshairs
    final crossPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - radius * 0.3, center.dy), Offset(center.dx + radius * 0.3, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius * 0.3), Offset(center.dx, center.dy + radius * 0.3), crossPaint);

    // Protractor label badge
    final tp = TextPainter(
      text: TextSpan(
        text: '$axisLabel (15° Snap)',
        style: TextStyle(color: isActive ? Colors.yellowAccent : color, fontSize: 9, fontWeight: FontWeight.bold, backgroundColor: const Color(0xDD0F172A)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center + Offset(-tp.width / 2, radius + 4));
  }

  void _drawAxisArrow(Canvas canvas, Offset from, Offset to, Color color, String label, bool isActive) {
    final linePaint = Paint()
      ..color = isActive ? Colors.yellowAccent : color
      ..strokeWidth = isActive ? 4.0 : 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, linePaint);

    final headPaint = Paint()..color = isActive ? Colors.yellowAccent : color;
    canvas.drawCircle(to, isActive ? 6.5 : 5.0, headPaint);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: isActive ? Colors.yellowAccent : color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, to + const Offset(4, -6));
  }

  Offset _project(CadPoint3D p) {
    if (projectPoint != null) {
      return projectPoint!(p);
    }
    if (size.width <= 0 || size.height <= 0) return Offset.zero;
    final cx = size.width / 2.0 + pan.dx;
    final cy = size.height / 2.0 + pan.dy;

    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 400.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * zoom;

    final pivot = mesh.center;
    final cameraDist = math.max(fitDim * 2.5, 1000.0);

    final rx = p.x - pivot.x;
    final ry = p.y - pivot.y;
    final rz = p.z - pivot.z;

    final azRad = azimuthDeg * math.pi / 180.0;
    final elRad = elevationDeg * math.pi / 180.0;
    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final x2 = rx * cosAz + ry * sinAz;
    final y2 = rx * (-sinEl * sinAz) + ry * (sinEl * cosAz) + rz * cosEl;
    final z2 = rx * (cosEl * sinAz) - ry * (cosEl * cosAz) + rz * sinEl;

    final persp = isOrthoProjection ? 1.0 : (cameraDist / math.max(cameraDist - z2, cameraDist * 0.15));

    final sx = cx + (x2 * persp) * scale;
    final sy = cy - (y2 * persp) * scale;
    return Offset(sx, sy);
  }

  @override
  bool shouldRepaint(covariant AssemblyGizmoPainter old) {
    return old.selectedPart != selectedPart ||
        old.azimuthDeg != azimuthDeg ||
        old.elevationDeg != elevationDeg ||
        old.zoom != zoom ||
        old.pan != pan ||
        old.gizmoMode != gizmoMode ||
        old.activeAxis != activeAxis ||
        old.lockedAxis != lockedAxis ||
        old.customCenter3d != customCenter3d;
  }
}

// =============================================================================
// SELECTED PART BOUNDING BOX & SNAP POINT PAINTER
// =============================================================================
/// Renders bounding box edges, hole centers/rims, sketch centers/endpoints,
/// and rich visual highlights for activating snap points with glowing halos and badges.
class AssemblySelectedPartBoundingBoxPainter extends CustomPainter {
  final List<AssemblyPart> selectedParts;
  final List<AssemblyPart> allParts;
  final Size size;
  final FoldedMeshResult mesh;
  final Offset Function(CadPoint3D) projectPoint;
  final AssemblySnapPoint? hoveredSnapPoint;
  final CadPoint3D? moveBasePoint;
  final AssemblySnapPoint? snapDragSourceSnap;
  final AssemblySnapPoint? snapDragTargetSnap;
  final String? highlightedTargetPartId;
  final double targetScaleFactor;
  final Offset? currentSnapDragScreenPos;
  final bool showSnapLabel;
  final double zoom;

  AssemblySelectedPartBoundingBoxPainter({
    required this.selectedParts,
    this.allParts = const [],
    required this.size,
    required this.mesh,
    required this.projectPoint,
    this.hoveredSnapPoint,
    this.moveBasePoint,
    this.snapDragSourceSnap,
    this.snapDragTargetSnap,
    this.highlightedTargetPartId,
    this.targetScaleFactor = 1.0,
    this.currentSnapDragScreenPos,
    this.showSnapLabel = true,
    this.zoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Highlight Target Part if hovered / receiving a drop (3D Scale & Boundary Glow)
    if (highlightedTargetPartId != null) {
      _drawHighlightedTargetPartBoundary(canvas);
    }

    if (selectedParts.isNotEmpty) {
      final wirePaint = Paint()
        ..color =
            const Color(0xEE0284C7) // Crisp SketchUp selection blue wireframe
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      for (final part in selectedParts) {
        final corners = part.getOrientedBoundingBoxCorners();
        // 1. Draw wireframe edges only (cyan face fill disabled per user request)
        _drawBoxEdgesFromWorldCorners(canvas, corners, wirePaint);

        // Extract all snapping points (corners, edge centers, hole centers, sketch endpoints)
        final snapPoints = AssemblyDockingEngine.getAllSnapPointsForPart(part, cachedMesh: mesh);
        _drawPartSnapPoints(canvas, part, snapPoints);
      }
    }

    // 3. Draw Magnetic Snap Drag visuals (tether line, halo, target indicator, badge)
    if (snapDragSourceSnap != null) {
      _drawMagneticSnapDragVisuals(canvas);
    }

    // 4. Highlight the Activating Snap Point (subtle glow halo, target crosshair, and compact badge)
    final activatingPoint = snapDragTargetSnap ?? hoveredSnapPoint;
    if (activatingPoint != null) {
      _drawActivatingSnapPointHighlight(canvas, activatingPoint);
    }

    // 5. Highlight Move Base / Anchor Point on Selected Part
    if (moveBasePoint != null) {
      final scr = projectPoint(moveBasePoint!);
      if (scr != Offset.zero) {
        _drawMoveBasePointHighlight(canvas, scr);
      }
    }
  }

  void _drawHighlightedTargetPartBoundary(Canvas canvas) {
    final targetPart = allParts.where((p) => p.id == highlightedTargetPartId).firstOrNull;
    if (targetPart == null) return;

    final corners = targetPart.getOrientedBoundingBoxCorners();
    final haloPaint = Paint()
      ..color =
          const Color(0xFF10B981) // Vibrant emerald green docking highlight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    _drawBoxEdgesFromWorldCorners(canvas, corners, haloPaint);
  }

  // Bounding box faces disabled per user request (border lines only)

  void _drawBoxEdgesFromWorldCorners(Canvas canvas, List<CadPoint3D> corners3d, Paint wirePaint) {
    if (corners3d.length < 8) return;
    final pts = corners3d.map((c) => projectPoint(c)).toList();
    if (pts.any((p) => p == Offset.zero)) return;

    final p0 = pts[0], p1 = pts[1], p2 = pts[2], p3 = pts[3];
    final p4 = pts[4], p5 = pts[5], p6 = pts[6], p7 = pts[7];

    void edge(Offset a, Offset b) => canvas.drawLine(a, b, wirePaint);
    edge(p0, p1);
    edge(p1, p2);
    edge(p2, p3);
    edge(p3, p0);
    edge(p4, p5);
    edge(p5, p6);
    edge(p6, p7);
    edge(p7, p4);
    edge(p0, p4);
    edge(p1, p5);
    edge(p2, p6);
    edge(p3, p7);
  }

  void _drawPartSnapPoints(Canvas canvas, AssemblyPart part, List<AssemblySnapPoint> snapPoints) {
    final activePt = snapDragTargetSnap ?? hoveredSnapPoint;

    // Zoom-adaptive sizing: scales down smoothly when zoomed out so hole dots don't clutter the view
    final zoomFactor = (zoom / 1.0).clamp(0.12, 1.5);
    final holeRadius = (1.3 * zoomFactor).clamp(0.35, 1.8);
    final cornerRadius = (1.8 * zoomFactor).clamp(0.55, 2.2);
    final midRadius = (1.3 * zoomFactor).clamp(0.45, 1.8);
    final centroidRadius = (1.5 * zoomFactor).clamp(0.5, 2.0);
    final borderStroke = (holeRadius * 0.25).clamp(0.2, 0.5);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderStroke;

    for (final pt in snapPoints) {
      if (activePt != null && pt.id == activePt.id) continue;

      final scr = projectPoint(pt.worldPosition);
      if (scr == Offset.zero) continue;

      switch (pt.type) {
        case AssemblySnapPointType.boundingBoxCorner:
          // SketchUp Green Corner Endpoint
          canvas.drawCircle(
            scr,
            cornerRadius,
            Paint()
              ..color = const Color(0xFF10B981)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(scr, cornerRadius, borderPaint);
          break;
        case AssemblySnapPointType.boundingBoxEdgeCenter:
          // SketchUp Cyan Edge Midpoint
          canvas.drawCircle(
            scr,
            midRadius,
            Paint()
              ..color = const Color(0xFF00E5FF)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(scr, midRadius, borderPaint);
          break;
        case AssemblySnapPointType.boundingBoxFaceCenter:
          // SketchUp Blue Face Center
          canvas.drawCircle(
            scr,
            midRadius,
            Paint()
              ..color = const Color(0xFF0284C7)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(scr, midRadius, borderPaint);
          break;
        case AssemblySnapPointType.boundingBoxCentroid:
          // SketchUp Purple 3D Centroid
          canvas.drawCircle(
            scr,
            centroidRadius,
            Paint()
              ..color = const Color(0xFFA855F7)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(scr, centroidRadius, borderPaint);
          break;
        case AssemblySnapPointType.holeCenter:
          // Parametric Cylindrical Hole Center (scales down dynamically on zoom out)
          canvas.drawCircle(
            scr,
            holeRadius,
            Paint()
              ..color = const Color(0xFFF59E0B)
              ..style = PaintingStyle.fill,
          );
          if (holeRadius >= 0.75) {
            canvas.drawCircle(scr, holeRadius, borderPaint);
          }
          break;
        case AssemblySnapPointType.holePerimeter:
          canvas.drawCircle(
            scr,
            (1.0 * zoomFactor).clamp(0.5, 1.2),
            Paint()
              ..color = const Color(0x6094A3B8)
              ..style = PaintingStyle.fill,
          );
          break;
        case AssemblySnapPointType.sketchCenter:
        case AssemblySnapPointType.sketchEndpoint:
          canvas.drawCircle(
            scr,
            midRadius,
            Paint()
              ..color = const Color(0xFF00E5FF)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(scr, midRadius, borderPaint);
          break;
      }
    }
  }

  void _drawActivatingSnapPointHighlight(Canvas canvas, AssemblySnapPoint pt) {
    final scr = projectPoint(pt.worldPosition);
    if (scr == Offset.zero) return;

    final isHole = pt.type == AssemblySnapPointType.holeCenter;
    final isSketch = pt.type == AssemblySnapPointType.sketchCenter || pt.type == AssemblySnapPointType.sketchEndpoint;
    final themeColor = isHole ? const Color(0xFFF59E0B) : (isSketch ? const Color(0xFF00E5FF) : const Color(0xFF10B981));

    // 1. Subtle, clean activating halo ring
    canvas.drawCircle(
      scr,
      8.0,
      Paint()
        ..color = themeColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      scr,
      5.5,
      Paint()
        ..color = themeColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    canvas.drawCircle(
      scr,
      1.8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // 2. Subtle Reticle Crosshair for Hole Centers
    if (isHole) {
      final crossPaint = Paint()
        ..color = themeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(scr.dx - 4.5, scr.dy), Offset(scr.dx + 4.5, scr.dy), crossPaint);
      canvas.drawLine(Offset(scr.dx, scr.dy - 4.5), Offset(scr.dx, scr.dy + 4.5), crossPaint);
    }

    // 3. Compact Floating Pill Badge
    if (showSnapLabel) {
      final textSpan = TextSpan(
        text: pt.label,
        style: const TextStyle(color: Colors.white, fontSize: 9.0, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();

      final pillOffset = Offset(scr.dx + 10.0, scr.dy - 10.0);
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pillOffset.dx - 4.0, pillOffset.dy - 2.0, textPainter.width + 8.0, textPainter.height + 4.0),
        const Radius.circular(3.5),
      );

      canvas.drawRRect(
        pillRect,
        Paint()
          ..color = const Color(0xDD0F172A)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        pillRect,
        Paint()
          ..color = themeColor.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      textPainter.paint(canvas, pillOffset);
    }
  }

  void _drawMagneticSnapDragVisuals(Canvas canvas) {
    final srcScreen = projectPoint(snapDragSourceSnap!.worldPosition);
    if (srcScreen == Offset.zero) return;

    final targetScreen = snapDragTargetSnap != null ? projectPoint(snapDragTargetSnap!.worldPosition) : null;
    final endScreen = targetScreen != null && targetScreen != Offset.zero ? targetScreen : (currentSnapDragScreenPos ?? srcScreen);

    // Source Snap Point Amber Glow
    canvas.drawCircle(
      srcScreen,
      8.0,
      Paint()
        ..color = const Color(0x55F59E0B)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      srcScreen,
      4.0,
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.fill,
    );

    // Magnetic Tether / Flux Line
    final isSnapped = targetScreen != null && targetScreen != Offset.zero;
    final tetherPaint = Paint()
      ..color = isSnapped ? const Color(0xFF10B981) : const Color(0xFFA855F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSnapped ? 2.2 : 1.5;

    // Draw tether line
    canvas.drawLine(srcScreen, endScreen, tetherPaint);

    if (isSnapped) {
      // Magnetic Contact Ripple Aura
      canvas.drawCircle(
        endScreen,
        12.0,
        Paint()
          ..color = const Color(0x3310B981)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        endScreen,
        7.0,
        Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      canvas.drawCircle(
        endScreen,
        3.5,
        Paint()
          ..color = const Color(0xFF34D399)
          ..style = PaintingStyle.fill,
      );

      // 🧲 SNAP Badge Pill
      const badgeText = '🧲 SNAP';
      final textSpan = const TextSpan(
        text: badgeText,
        style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 10.0, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();

      final pillOffset = Offset(endScreen.dx + 12.0, endScreen.dy - 12.0);
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pillOffset.dx - 4.0, pillOffset.dy - 3.0, textPainter.width + 8.0, textPainter.height + 6.0),
        const Radius.circular(4.0),
      );
      canvas.drawRRect(
        pillRect,
        Paint()
          ..color = const Color(0xEE0F172A)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        pillRect,
        Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      textPainter.paint(canvas, pillOffset);
    }
  }

  void _drawMoveBasePointHighlight(Canvas canvas, Offset scr) {
    // 1. Radiant pulsing amber aura halo
    canvas.drawCircle(
      scr,
      11.0,
      Paint()
        ..color = const Color(0x35F59E0B)
        ..style = PaintingStyle.fill,
    );
    // 2. Crisp outer boundary ring
    canvas.drawCircle(
      scr,
      6.5,
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    // 3. Solid center dot
    canvas.drawCircle(
      scr,
      2.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // 4. Anchor Reticle Diamond / Cross
    final reticlePaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(scr.dx - 8.0, scr.dy), Offset(scr.dx + 8.0, scr.dy), reticlePaint);
    canvas.drawLine(Offset(scr.dx, scr.dy - 8.0), Offset(scr.dx, scr.dy + 8.0), reticlePaint);

    // 5. Subtle "Base Point" badge
    final textSpan = const TextSpan(
      text: 'Base Point',
      style: TextStyle(color: Colors.white, fontSize: 9.0, fontWeight: FontWeight.bold, letterSpacing: 0.3),
    );
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    final pillOffset = Offset(scr.dx + 12.0, scr.dy - 11.0);
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pillOffset.dx - 4.0, pillOffset.dy - 2.0, textPainter.width + 8.0, textPainter.height + 4.0),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = const Color(0xEE0F172A)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    textPainter.paint(canvas, pillOffset);
  }

  @override
  bool shouldRepaint(covariant AssemblySelectedPartBoundingBoxPainter old) {
    return true;
  }
}
