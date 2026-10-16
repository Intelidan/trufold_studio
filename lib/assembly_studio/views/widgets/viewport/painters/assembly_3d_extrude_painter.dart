// 3D Feature Extrusion Preview & Interactive Manipulator Painter
// TruFold Assembly Studio - Phase 5 Feature Extrusion
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';

import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

class Assembly3DExtrudePainter extends CustomPainter {
  final AssemblyStudioViewModel viewModel;
  final Offset Function(CadPoint3D) projectPoint;

  Assembly3DExtrudePainter({
    required this.viewModel,
    required this.projectPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!viewModel.isExtrudeMode) return;
    final plane = viewModel.activeSketchPlane;
    if (plane == null) return;

    // 1. Compile 2D segments and extract closed profile loop
    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(plane);
    final validation = CADProfileValidator.validateProfile(segments);
    if (!validation.isValidClosedLoop || validation.orderedPathVertices.length < 3) return;

    final profileLoop = validation.orderedPathVertices;
    final params = viewModel.extrudeParams;

    // 2. Generate 3D Extrusion Mesh Preview
    final opColor = params.operation.color;
    final solidMesh = AssemblyExtrudeEngine.generateExtrudedSolid(
      plane: plane,
      profilePoints: profileLoop,
      params: params,
      color: opColor,
    );
    if (solidMesh.isEmpty) return;

    // 3. Render Translucent Glassmorphic 3D Solid Preview
    final fillPaint = Paint()
      ..color = opColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    final wirePaint = Paint()
      ..color = opColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final poly in solidMesh.polygons) {
      if (poly.vertices.length < 3) continue;
      final path = Path();
      bool first = true;
      bool allValid = true;

      for (final v in poly.vertices) {
        final scr = projectPoint(v);
        if (scr == Offset.zero) {
          allValid = false;
          break;
        }
        if (first) {
          path.moveTo(scr.dx, scr.dy);
          first = false;
        } else {
          path.lineTo(scr.dx, scr.dy);
        }
      }

      if (allValid) {
        path.close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, wirePaint);
      }
    }

    // 4. Render Interactive 3D Extrude Arrow Manipulator
    _drawExtrudeArrowManipulator(canvas, plane, profileLoop, params);
  }

  void _drawExtrudeArrowManipulator(
    Canvas canvas,
    CADSketchPlane plane,
    List<Offset> profileLoop,
    AssemblyExtrudeParams params,
  ) {
    // 2D Centroid on plane
    final cx = profileLoop.map((p) => p.dx).reduce((a, b) => a + b) / profileLoop.length;
    final cy = profileLoop.map((p) => p.dy).reduce((a, b) => a + b) / profileLoop.length;

    final origin = plane.origin;
    final xAxis = plane.xAxis.normalized();
    final yAxis = plane.yAxis.normalized();
    final normal = plane.normal.normalized();

    // Base point in 3D
    final base3d = CadPoint3D(
      origin.x + xAxis.x * cx + yAxis.x * cy,
      origin.y + xAxis.y * cx + yAxis.y * cy,
      origin.z + xAxis.z * cx + yAxis.z * cy,
    );

    // Tip point in 3D along normal
    final dist = params.distanceMm;
    final tip3d = CadPoint3D(
      base3d.x + normal.x * dist,
      base3d.y + normal.y * dist,
      base3d.z + normal.z * dist,
    );

    final scrBase = projectPoint(base3d);
    final scrTip = projectPoint(tip3d);

    if (scrBase == Offset.zero || scrTip == Offset.zero) return;

    final isDragging = viewModel.isExtrudeArrowDragging;
    final arrowColor = isDragging ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8);

    // Draw dashed axis guide line
    final guidePaint = Paint()
      ..color = arrowColor.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(scrBase, scrTip, guidePaint);

    // Draw arrow shaft
    final shaftPaint = Paint()
      ..color = arrowColor
      ..strokeWidth = isDragging ? 4.0 : 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(scrBase, scrTip, shaftPaint);

    // Draw arrowhead cone
    final dir = scrTip - scrBase;
    final len = dir.distance;
    if (len > 8.0) {
      final unit = dir / len;
      final perp = Offset(-unit.dy, unit.dx);
      const headSize = 14.0;
      const headWidth = 8.0;

      final arrowHeadPath = Path()
        ..moveTo(scrTip.dx, scrTip.dy)
        ..lineTo(scrTip.dx - unit.dx * headSize + perp.dx * headWidth, scrTip.dy - unit.dy * headSize + perp.dy * headWidth)
        ..lineTo(scrTip.dx - unit.dx * headSize - perp.dx * headWidth, scrTip.dy - unit.dy * headSize - perp.dy * headWidth)
        ..close();

      final headPaint = Paint()
        ..color = arrowColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowHeadPath, headPaint);

      // White outline for crisp contrast
      final headStroke = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawPath(arrowHeadPath, headStroke);
    }

    // Draw floating distance badge near arrow tip
    final badgeOffset = scrTip + const Offset(16, -12);
    final badgeText = params.direction == AssemblyExtrudeDirection.symmetric
        ? '±${params.distanceMm.abs().toStringAsFixed(1)} mm'
        : '${params.distanceMm.toStringAsFixed(1)} mm';

    final textSpan = TextSpan(
      text: badgeText,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeOffset.dx - 6, badgeOffset.dy - 3, textPainter.width + 12, textPainter.height + 6),
      const Radius.circular(5),
    );

    canvas.drawRRect(
      badgeRect,
      Paint()..color = const Color(0xDD0F172A),
    );
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = arrowColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    textPainter.paint(canvas, badgeOffset);
  }

  @override
  bool shouldRepaint(covariant Assembly3DExtrudePainter oldDelegate) => true;
}
