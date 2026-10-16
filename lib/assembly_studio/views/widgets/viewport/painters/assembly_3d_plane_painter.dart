import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Renders 3D Datum Origin Planes (XY, XZ, YZ), User Construction Planes (Offset, Angle, Midplane),
/// and the 3D Coordinate Origin Triad with interactive hover/selection highlights.
class Assembly3DPlanePainter extends CustomPainter {
  final AssemblyStudioViewModel viewModel;
  final Offset Function(CadPoint3D) projectPoint;

  Assembly3DPlanePainter({required this.viewModel, required this.projectPoint});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final vmState = viewModel;
    final isPlaneSelectionMode = vmState.isPlaneSelectionMode;
    final showPlanes = isPlaneSelectionMode || vmState.isSketchMode || vmState.showDatumPlanes || vmState.showConstructionPlanes;

    // 1. Draw Global Coordinate Origin Triad (0,0,0)
    if (vmState.showOriginTriad) {
      _drawOriginTriad(canvas, size);
    }

    // 2. Draw 3D Planes (Datum, Construction Planes, & Active Sketch Plane)
    if (showPlanes) {
      final planes = vmState.allAvailablePlanes;
      bool activePlaneDrawn = false;
      for (final plane in planes) {
        final isActive = plane.id == vmState.activeSketchPlane?.id;
        if (!plane.isVisible && !isActive) continue;
        if (isActive) activePlaneDrawn = true;
        final isHovered = plane.id == vmState.hoveredPlaneId;
        _drawPlane(canvas, plane, isHovered: isHovered, isActive: isActive, isSelectionMode: isPlaneSelectionMode);
      }
      if (!activePlaneDrawn && vmState.activeSketchPlane != null && vmState.isSketchMode) {
        _drawPlane(canvas, vmState.activeSketchPlane!, isHovered: false, isActive: true, isSelectionMode: isPlaneSelectionMode);
      }
    }

    // 3. Draw Hovered Face Highlight (when hovering a 3D solid face in Plane Selection Mode)
    if (isPlaneSelectionMode && vmState.hoveredPlaneId != null && vmState.hoveredPlaneId!.startsWith('face:')) {
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

    // Draw axis lines
    _drawTriadAxis(canvas, originScr, xScr, const Color(0xFFEF4444), 'X');
    _drawTriadAxis(canvas, originScr, yScr, const Color(0xFF10B981), 'Y');
    _drawTriadAxis(canvas, originScr, zScr, const Color(0xFF3B82F6), 'Z');

    // Origin central bead (Onshape style white with blue ring)
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

    // Arrowhead
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

      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);

      // Label text
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

  void _drawPlane(Canvas canvas, CADSketchPlane plane, {required bool isHovered, required bool isActive, required bool isSelectionMode}) {
    // Fixed CAD reference plane standard size (Item 2: never expands when objects distance increases)
    const planeScale = 140.0;

    final corners3d = plane.getQuadCorners(customHalfSize: planeScale);
    final cornersScreen = corners3d.map((v) => projectPoint(CadPoint3D(v.x, v.y, v.z))).toList();

    // Quad Path
    final quadPath = Path()
      ..moveTo(cornersScreen[0].dx, cornersScreen[0].dy)
      ..lineTo(cornersScreen[1].dx, cornersScreen[1].dy)
      ..lineTo(cornersScreen[2].dx, cornersScreen[2].dy)
      ..lineTo(cornersScreen[3].dx, cornersScreen[3].dy)
      ..close();

    const onshapeBlue = Color(0xFF0076CE);
    // Ultra-translucent plane styling (Item 5a: crystal clear visibility for models behind planes)
    final fillAlpha = isHovered ? 0.035 : (isActive ? 0.020 : (isSelectionMode ? 0.012 : 0.005));

    // 1. Sleek Ultra-Translucent Fill (Item 5a)
    final fillPaint = Paint()
      ..color = onshapeBlue.withValues(alpha: fillAlpha)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(quadPath, fillPaint);

    // 2. Crisp Onshape Border
    final borderPaint = Paint()
      ..color = isHovered
          ? onshapeBlue
          : (isActive ? onshapeBlue.withValues(alpha: 0.50) : onshapeBlue.withValues(alpha: isSelectionMode ? 0.30 : 0.18))
      ..strokeWidth = isHovered ? 1.2 : (isActive ? 1.0 : 0.75)
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;


    final isConstruction =
        plane.planeType == CADPlaneType.offsetPlane ||
        plane.planeType == CADPlaneType.anglePlane ||
        plane.planeType == CADPlaneType.midplane ||
        plane.planeType == CADPlaneType.threePointPlane;

    if (isConstruction && !isHovered && !isActive) {
      _drawDashedPolygon(canvas, cornersScreen, borderPaint);
    } else {
      canvas.drawPath(quadPath, borderPaint);
    }

    // 3. Clean Onshape Corner Text Label (Direct, sleek text without clunky box)
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

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {double dashLen = 6.0, double gapLen = 4.0}) {
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

  void _drawOnshapePlaneLabel(Canvas canvas, CADSketchPlane plane, List<Offset> corners, {required bool isHovered, required bool isActive}) {
    // Extract clean name e.g. "XZ Front Plane" -> "Front", "XY Top Plane" -> "Top"
    String labelText = plane.name;
    if (labelText.contains('Front')) {
      labelText = 'Front';
    } else if (labelText.contains('Top')) {
      labelText = 'Top';
    } else if (labelText.contains('Right')) {
      labelText = 'Right';
    }

    // Pick top-left or prominent corner
    final labelCorner = corners[3]; // top-left
    final towardsCenter = (corners[1] - corners[3]);
    final textOffset = labelCorner + (towardsCenter.distance > 20 ? (towardsCenter / towardsCenter.distance) * 8.0 : const Offset(6, 6));

    const onshapeBlue = Color(0xFF0076CE);
    final textSpan = TextSpan(
      text: labelText,
      style: TextStyle(
        color: isHovered || isActive ? onshapeBlue : onshapeBlue.withValues(alpha: 0.85),
        fontSize: isHovered ? 11.5 : 10.5,
        fontWeight: isHovered || isActive ? FontWeight.w700 : FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, textOffset);
  }

  void _drawHoveredFace(Canvas canvas, String faceIdentifier) {
    // faceIdentifier format: "face:<partId>:<faceId>"
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

        // Glowing face fill
        final fillPaint = Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);

        // Glowing border
        final borderPaint = Paint()
          ..color = const Color(0xFF38BDF8)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke;
        canvas.drawPath(path, borderPaint);

        // Center badge
        double cx = 0, cy = 0;
        for (final p in screenCorners) {
          cx += p.dx;
          cy += p.dy;
        }
        final center = Offset(cx / screenCorners.length, cy / screenCorners.length);

        final textSpan = const TextSpan(
          text: 'FACE SKETCH PLANE • CLICK TO SELECT',
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        );
        final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
        final rect = Rect.fromCenter(center: center, width: tp.width + 12, height: tp.height + 6);
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

        canvas.drawRRect(rrect, Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.92));
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = const Color(0xFF38BDF8)
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke,
        );
        tp.paint(canvas, Offset(rect.left + 6, rect.top + 3));
        break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant Assembly3DPlanePainter oldDelegate) {
    return oldDelegate.viewModel.hoveredPlaneId != viewModel.hoveredPlaneId ||
        oldDelegate.viewModel.isPlaneSelectionMode != viewModel.isPlaneSelectionMode ||
        oldDelegate.viewModel.activeSketchPlane != viewModel.activeSketchPlane ||
        oldDelegate.viewModel.constructionPlanes.length != viewModel.constructionPlanes.length ||
        oldDelegate.viewModel.showDatumPlanes != viewModel.showDatumPlanes ||
        oldDelegate.viewModel.showConstructionPlanes != viewModel.showConstructionPlanes ||
        oldDelegate.viewModel.showOriginTriad != viewModel.showOriginTriad;
  }
}
