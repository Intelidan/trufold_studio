import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Renders 3D Datum & Surface Sketch Planes matching Onshape's sleek visual standard (`image_41a6fb.png`):
/// - Thin sky-blue outer frame (`#7DD3FC` / `#38BDF8`, `1.1px`) that auto-expands to enclose all sketch entities & dimensions
/// - Top-left `"Sketch 1"` / `"Sketch 2"` label rotated parallel to the top edge of the 3D sketch plane!
/// - Crystal-clear interior (no heavy blue tint obscuring the 3D model underneath)
class Assembly3DPlanePainter extends CustomPainter {
  final AssemblyStudioViewModel viewModel;
  final Offset Function(CadPoint3D) projectPoint;

  Assembly3DPlanePainter({required this.viewModel, required this.projectPoint});

  @override
  void paint(Canvas canvas, Size size) {
    final planes = <CADSketchPlane>[
      if (viewModel.showAllDatumPlanes && !viewModel.isSketchMode) ...viewModel.datumPlanes,
      ...viewModel.customPlanes,
      if (viewModel.activeSketchPlane != null &&
          !viewModel.datumPlanes.any((p) => p.id == viewModel.activeSketchPlane!.id) &&
          !viewModel.customPlanes.any((p) => p.id == viewModel.activeSketchPlane!.id))
        viewModel.activeSketchPlane!,
    ];

    for (final plane in planes) {
      if (!plane.isVisible) continue;
      final isSelected = viewModel.selectedPlane?.id == plane.id;
      final isHovered = viewModel.hoveredPlane?.id == plane.id;
      final isActiveSketch = viewModel.activeSketchPlane?.id == plane.id && viewModel.isSketchMode;

      double minU = -plane.size / 2.0;
      double maxU = plane.size / 2.0;
      double minV = -plane.size / 2.0;
      double maxV = plane.size / 2.0;

      if (isActiveSketch && plane.primitives.isNotEmpty) {
        double pMinX = -40.0, pMaxX = 40.0, pMinY = -40.0, pMaxY = 40.0;
        for (final prim in plane.primitives) {
          for (final seg in prim.toLineSegments(curveResolution: 16)) {
            pMinX = math.min(pMinX, math.min(seg.start.dx, seg.end.dx));
            pMaxX = math.max(pMaxX, math.max(seg.start.dx, seg.end.dx));
            pMinY = math.min(pMinY, math.min(seg.start.dy, seg.end.dy));
            pMaxY = math.max(pMaxY, math.max(seg.start.dy, seg.end.dy));
          }
        }
        const double marginMm = 48.0;
        minU = math.min(minU, pMinX - marginMm);
        maxU = math.max(maxU, pMaxX + marginMm);
        minV = math.min(minV, pMinY - marginMm);
        maxV = math.max(maxV, pMaxY + marginMm);
      }

      final xAx = plane.xAxis;
      final yAx = plane.yAxis;
      final orig = plane.origin;

      CadPoint3D toWorldPt(double u, double v) {
        final w = orig + (xAx * u) + (yAx * v);
        return CadPoint3D(w.x, w.y, w.z);
      }

      final cBL = projectPoint(toWorldPt(minU, minV));
      final cBR = projectPoint(toWorldPt(maxU, minV));
      final cTR = projectPoint(toWorldPt(maxU, maxV));
      final cTL = projectPoint(toWorldPt(minU, maxV));
      if (cBL == Offset.zero || cBR == Offset.zero || cTR == Offset.zero || cTL == Offset.zero) continue;

      final path = Path()
        ..moveTo(cBL.dx, cBL.dy)
        ..lineTo(cBR.dx, cBR.dy)
        ..lineTo(cTR.dx, cTR.dy)
        ..lineTo(cTL.dx, cTL.dy)
        ..close();

      final Color baseColor = isActiveSketch
          ? const Color(0xFF7DD3FC)
          : (plane.customColor ?? const Color(0xFF38BDF8));

      final double fillAlpha = isActiveSketch
          ? 0.0
          : isSelected
              ? 0.14
              : isHovered
                  ? 0.10
                  : 0.04;

      if (fillAlpha > 0.0) {
        canvas.drawPath(
          path,
          Paint()
            ..color = baseColor.withValues(alpha: fillAlpha)
            ..style = PaintingStyle.fill,
        );
      }

      final borderPaint = Paint()
        ..color = isActiveSketch
            ? const Color(0xFF7DD3FC)
            : isSelected
                ? const Color(0xFFF59E0B)
                : isHovered
                    ? baseColor.withValues(alpha: 0.90)
                    : baseColor.withValues(alpha: 0.45)
        ..strokeWidth = isActiveSketch ? 1.15 : (isSelected ? 1.8 : 1.0)
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, borderPaint);

      if (isActiveSketch || isSelected || isHovered) {
        final corners = [cTL, cTR, cBR, cBL];
        int topIdx = 0;
        for (int i = 1; i < 4; i++) {
          if (corners[i].dy < corners[topIdx].dy) {
            topIdx = i;
          }
        }
        final pCorner = corners[topIdx];
        final pNextCW = corners[(topIdx + 1) % 4];
        final pPrevCCW = corners[(topIdx + 3) % 4];
        final Offset edgeRight = (pNextCW.dx >= pPrevCCW.dx) ? (pNextCW - pCorner) : (pPrevCCW - pCorner);
        final Offset edgeDown = (pNextCW.dx >= pPrevCCW.dx) ? (pPrevCCW - pCorner) : (pNextCW - pCorner);

        final double edgeLen = edgeRight.distance;
        final double downLen = edgeDown.distance;
        if (edgeLen > 20.0 && downLen > 20.0) {
          final String displayLabel = isActiveSketch
              ? (plane.name.startsWith('Sketch') ? plane.name : 'Sketch 1')
              : plane.name;

          final tp = TextPainter(
            text: TextSpan(
              text: displayLabel,
              style: TextStyle(
                color: isActiveSketch
                    ? const Color(0xFF7DD3FC)
                    : isSelected
                        ? const Color(0xFFF59E0B)
                        : baseColor,
                fontSize: isActiveSketch ? 12.5 : 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          final unitRight = edgeRight / edgeLen;
          final unitDown = edgeDown / downLen;
          final labelPos = pCorner + unitRight * 8.0 + unitDown * 4.0;
          double angle = math.atan2(unitRight.dy, unitRight.dx);
          if (angle > math.pi / 2.0) angle -= math.pi;
          if (angle < -math.pi / 2.0) angle += math.pi;

          canvas.save();
          canvas.translate(labelPos.dx, labelPos.dy);
          canvas.rotate(angle);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant Assembly3DPlanePainter oldDelegate) => true;
}
