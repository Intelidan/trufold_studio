import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Renders 3D Datum Origin Planes (XY, XZ, YZ), User Construction Planes (Offset, Angle, Midplane),
/// Active Onshape Sketch Planes ("Sketch 1" in SS4), and the 3D Coordinate Origin Triad.
class Assembly3DPlanePainter extends CustomPainter {
  final AssemblyStudioViewModel viewModel;
  final Offset Function(CadPoint3D) projectPoint;

  Assembly3DPlanePainter({required this.viewModel, required this.projectPoint});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final vmState = viewModel;
    final isPlaneSelectionMode = vmState.isPlaneSelectionMode;
    final showPlanes = isPlaneSelectionMode ||
        vmState.isSketchMode ||
        vmState.showDatumPlanes ||
        vmState.showConstructionPlanes;

    // 1. Draw Global Coordinate Origin Triad (0,0,0) when not inside 2D sketch mode
    if (vmState.showOriginTriad && !vmState.isSketchMode) {
      _drawOriginTriad(canvas, size);
    }

    // 2. Draw 3D Planes (Datum, Construction Planes, & Active Sketch Plane)
    if (showPlanes) {
      final planes = vmState.allAvailablePlanes;
      bool activePlaneDrawn = false;
      for (final plane in planes) {
        final isActive = plane.id == vmState.activeSketchPlane?.id;
        // When actively sketching on a plane, hide unselected datum planes so the view matches Onshape SS4!
        if (vmState.isSketchMode && !isActive && !vmState.showDatumPlanes) continue;
        if (!plane.isVisible && !isActive) continue;
        if (isActive) activePlaneDrawn = true;
        final isHovered = plane.id == vmState.hoveredPlaneId;
        _drawPlane(
          canvas,
          plane,
          isHovered: isHovered,
          isActive: isActive,
          isSelectionMode: isPlaneSelectionMode,
        );
      }
      if (!activePlaneDrawn && vmState.activeSketchPlane != null && vmState.isSketchMode) {
        _drawPlane(
          canvas,
          vmState.activeSketchPlane!,
          isHovered: false,
          isActive: true,
          isSelectionMode: isPlaneSelectionMode,
        );
      }
    }

    // 3. Draw Hovered Face Highlight (when hovering a 3D solid face in Plane Selection Mode)
    if (isPlaneSelectionMode &&
        vmState.hoveredPlaneId != null &&
        vmState.hoveredPlaneId!.startsWith('face:')) {
      _drawHoveredFace(canvas, vmState.hoveredPlaneId!);
    }
  }

  void _drawOriginTriad(Canvas canvas, Size size) {
    const origin3d = CadPoint3D(0.0, 0.0, 0.0);
    final originScr = projectPoint(origin3d);

    const axisLengthMm = 35.0;
    const xEnd3d = CadPoint3D(axisLengthMm, 0.0, 0.0);
    const yEnd3d = CadPoint3D(0.0, axisLengthMm, 0.0);
    const zEnd3d = CadPoint3D(0.0, 0.0, axisLengthMm);

    final xScr = projectPoint(xEnd3d);
    final yScr = projectPoint(yEnd3d);
    final zScr = projectPoint(zEnd3d);

    _drawTriadAxis(canvas, originScr, xScr, const Color(0xFFEF4444), 'X');
    _drawTriadAxis(canvas, originScr, yScr, const Color(0xFF10B981), 'Y');
    _drawTriadAxis(canvas, originScr, zScr, const Color(0xFF3B82F6), 'Z');

    final beadBgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final beadBorderPaint = Paint()
      ..color = const Color(0xFF0076CE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(originScr, 3.5, beadBgPaint);
    canvas.drawCircle(originScr, 3.5, beadBorderPaint);
  }

  void _drawTriadAxis(Canvas canvas, Offset start, Offset end, Color color, String label) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawLine(start, end, linePaint);

    final dir = end - start;
    final len = dir.distance;
    if (len > 4.0) {
      final unit = dir / len;
      final normal = Offset(-unit.dy, unit.dx);
      const headLen = 6.0;
      const headWidth = 3.5;
      final p1 = end;
      final p2 = end - unit * headLen + normal * headWidth;
      final p3 = end - unit * headLen - normal * headWidth;

      final arrowPath = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();

      canvas.drawPath(arrowPath, Paint()..color = color..style = PaintingStyle.fill);

      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      final labelOffset = end + unit * 5.0 - Offset(tp.width / 2.0, tp.height / 2.0);
      tp.paint(canvas, labelOffset);
    }
  }

  void _drawPlane(
    Canvas canvas,
    CADSketchPlane plane, {
    required bool isHovered,
    required bool isActive,
    required bool isSelectionMode,
  }) {
    const planeScale = 145.0;

    final corners3d = plane.getQuadCorners(customHalfSize: planeScale);
    final cornersScreen = corners3d.map((v) => projectPoint(CadPoint3D(v.x, v.y, v.z))).toList();
    if (cornersScreen.any((c) => c == Offset.zero)) return;

    final quadPath = Path()
      ..moveTo(cornersScreen[0].dx, cornersScreen[0].dy)
      ..lineTo(cornersScreen[1].dx, cornersScreen[1].dy)
      ..lineTo(cornersScreen[2].dx, cornersScreen[2].dy)
      ..lineTo(cornersScreen[3].dx, cornersScreen[3].dy)
      ..close();

    // Onshape SS4 sky-blue frame color (#60A5FA / #38BDF8)
    const onshapeSkyBlue = Color(0xFF38BDF8);
    const onshapeHoverAmber = Color(0xFFF59E0B);

    // 1. Crystal-clear interior (zero murky tint when active, subtle glow on hover)
    if (isHovered) {
      canvas.drawPath(
        quadPath,
        Paint()
          ..color = onshapeHoverAmber.withValues(alpha: 0.06)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
    }

    // 2. Crisp Onshape SS4 Thin Sky-Blue Border Frame
    final borderPaint = Paint()
      ..color = isHovered
          ? onshapeHoverAmber
          : (isActive
              ? onshapeSkyBlue.withValues(alpha: 0.78)
              : onshapeSkyBlue.withValues(alpha: isSelectionMode ? 0.42 : 0.25))
      ..strokeWidth = isHovered ? 1.8 : (isActive ? 1.15 : 0.85)
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final isConstruction = plane.planeType == CADPlaneType.offsetPlane ||
        plane.planeType == CADPlaneType.anglePlane ||
        plane.planeType == CADPlaneType.midplane ||
        plane.planeType == CADPlaneType.threePointPlane;

    if (isConstruction && !isHovered && !isActive) {
      _drawDashedPolygon(canvas, cornersScreen, borderPaint);
    } else {
      canvas.drawPath(quadPath, borderPaint);
    }

    // 3. Authentic Onshape SS4 Top-Left Corner Label ("Sketch 1", "Top", "Front", "Right")
    _drawOnshapePlaneLabel(canvas, plane, cornersScreen, isHovered: isHovered, isActive: isActive);
  }

  void _drawDashedPolygon(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      _drawDashedLine(canvas, p1, p2, paint, dashLen: 6.0, gapLen: 4.0);
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dashLen = 6.0,
    double gapLen = 4.0,
  }) {
    final dist = (p2 - p1).distance;
    if (dist < 1e-4) return;
    final unit = (p2 - p1) / dist;
    double current = 0.0;
    while (current < dist) {
      final end = math.min(current + dashLen, dist);
      canvas.drawLine(p1 + unit * current, p1 + unit * end, paint);
      current += dashLen + gapLen;
    }
  }

  void _drawOnshapePlaneLabel(
    Canvas canvas,
    CADSketchPlane plane,
    List<Offset> corners, {
    required bool isHovered,
    required bool isActive,
  }) {
    String labelText = plane.name;
    if (!labelText.startsWith('Sketch')) {
      if (labelText.contains('Front')) {
        labelText = 'Front';
      } else if (labelText.contains('Top')) {
        labelText = 'Top';
      } else if (labelText.contains('Right')) {
        labelText = 'Right';
      }
    }

    // Find the visual top-left corner on screen (minimum dy + 0.35 * dx) so the label
    // always sits inside the top-left corner of the plane frame just like "Sketch 2" in SS4!
    int topIdx = 0;
    double bestScore = double.infinity;
    double cx = 0, cy = 0;
    for (int i = 0; i < corners.length; i++) {
      cx += corners[i].dx;
      cy += corners[i].dy;
      final score = corners[i].dy + corners[i].dx * 0.35;
      if (score < bestScore) {
        bestScore = score;
        topIdx = i;
      }
    }
    final center = Offset(cx / corners.length, cy / corners.length);
    final labelCorner = corners[topIdx];
    final toCenter = center - labelCorner;
    final inwardOffset = toCenter.distance > 20.0
        ? (toCenter / toCenter.distance) * 14.0
        : const Offset(8, 8);

    const onshapeSkyBlue = Color(0xFF38BDF8);
    final textColor = isHovered
        ? const Color(0xFFF59E0B)
        : (isActive ? onshapeSkyBlue : onshapeSkyBlue.withValues(alpha: 0.78));

    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: textColor,
          fontSize: isActive ? 13.0 : 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, labelCorner + inwardOffset - Offset(0, tp.height * 0.3));
  }

  void _drawHoveredFace(Canvas canvas, String faceIdentifier) {
    final parts = faceIdentifier.split(':');
    if (parts.length < 3) return;
    final faceId = parts[2];

    for (final poly in viewModel.assemblyMesh.allPolygons) {
      if (poly.faceId == faceId) {
        final screenCorners = poly.vertices.map((v) => projectPoint(v)).toList();
        if (screenCorners.length < 3) return;

        final path = Path()..moveTo(screenCorners[0].dx, screenCorners[0].dy);
        for (int i = 1; i < screenCorners.length; i++) {
          path.lineTo(screenCorners[i].dx, screenCorners[i].dy);
        }
        path.close();

        // Onshape warm yellow/amber hover highlight on 3D face selection
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFF59E0B).withValues(alpha: 0.18)
            ..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFF59E0B)
            ..strokeWidth = 2.2
            ..style = PaintingStyle.stroke,
        );
        break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant Assembly3DPlanePainter oldDelegate) => true;
}
