import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Renders real-time 3D parametric sketch geometry directly glued to surface planes:
/// 1. Procedural 2D design grid aligned to the active 3D plane's local coordinate frame.
/// 2. Glowing neon-green snapping indicator dot.
/// 3. Glowing yellow dashed inferencing alignment tracks.
/// 4. 2D CAD entities (Rectangles, Circles, Lines, Polylines) with construction dashing.
/// 5. Validated closed-loop tessellated fill shading.
/// 6. Floating 3D parametric dimension labels with interactive text blocks.
class Assembly3DSurfaceSketchPainter extends CustomPainter {
  final AssemblyStudioViewModel viewModel;
  final Offset Function(CadPoint3D) projectPoint;

  Assembly3DSurfaceSketchPainter({required this.viewModel, required this.projectPoint});

  @override
  void paint(Canvas canvas, Size size) {
    final plane = viewModel.activeSketchPlane;
    if (plane == null) return;

    final xAx = plane.xAxis;
    final yAx = plane.yAxis;
    final origin = plane.origin;

    Offset toScreen(Offset local) {
      final w = origin + (xAx * local.dx) + (yAx * local.dy);
      return projectPoint(CadPoint3D(w.x, w.y, w.z));
    }

    // 1. Procedural Plane Design Grid Overlay
    final gridPaint = Paint()
      ..color = const Color(0x330284C7)
      ..strokeWidth = 1.0;

    const double extent = 200.0;
    const double step = 20.0;
    final int lineCount = (extent / step).round();

    for (int i = -lineCount; i <= lineCount; i++) {
      final val = i * step;
      // Parallel to Y
      final s1 = toScreen(Offset(val, -extent));
      final e1 = toScreen(Offset(val, extent));
      if (s1 != Offset.zero && e1 != Offset.zero) {
        canvas.drawLine(s1, e1, gridPaint);
      }
      // Parallel to X
      final s2 = toScreen(Offset(-extent, val));
      final e2 = toScreen(Offset(extent, val));
      if (s2 != Offset.zero && e2 != Offset.zero) {
        canvas.drawLine(s2, e2, gridPaint);
      }
    }

    // Origin Axes (Red for X, Green for Y)
    final scrOrigin = toScreen(Offset.zero);
    final scrXAxis = toScreen(const Offset(35.0, 0.0));
    final scrYAxis = toScreen(const Offset(0.0, 35.0));
    if (scrOrigin != Offset.zero) {
      if (scrXAxis != Offset.zero) {
        canvas.drawLine(
          scrOrigin,
          scrXAxis,
          Paint()
            ..color = const Color(0xFFEF4444)
            ..strokeWidth = 2.5,
        );
      }
      if (scrYAxis != Offset.zero) {
        canvas.drawLine(
          scrOrigin,
          scrYAxis,
          Paint()
            ..color = const Color(0xFF10B981)
            ..strokeWidth = 2.5,
        );
      }
    }

    // 2. Interior Shaded Tessellated Profile (if loop is valid)
    final validation = viewModel.activeSketchValidation;
    if (validation != null && validation.isValidClosedLoop && validation.orderedPathVertices.length >= 3) {
      final fillPath = Path();
      bool first = true;
      for (final pt in validation.orderedPathVertices) {
        final scr = toScreen(pt);
        if (scr == Offset.zero) continue;
        if (first) {
          fillPath.moveTo(scr.dx, scr.dy);
          first = false;
        } else {
          fillPath.lineTo(scr.dx, scr.dy);
        }
      }
      fillPath.close();

      final fillPaint = Paint()
        ..color = const Color(0x380284C7)
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);
    }

    // 3. Render Primitive Entities & Segments
    for (final prim in plane.primitives) {
      final isSel = (prim.id == viewModel.selectedSketchEntity?.id);
      final strokePaint = Paint()
        ..color = isSel
            ? const Color(0xFFF59E0B) // Amber for selected
            : prim.isConstruction
            ? const Color(0xFF38BDF8) // Light blue for construction
            : const Color(0xFF0284C7) // Blue
        ..strokeWidth = isSel ? 2.8 : 1.8
        ..style = PaintingStyle.stroke;

      if (prim is CADRectangleEntity) {
        final p1 = toScreen(prim.startPoint);
        final p2 = toScreen(Offset(prim.startPoint.dx + prim.width, prim.startPoint.dy));
        final p3 = toScreen(Offset(prim.startPoint.dx + prim.width, prim.startPoint.dy + prim.height));
        final p4 = toScreen(Offset(prim.startPoint.dx, prim.startPoint.dy + prim.height));

        if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
          final rectPath = Path()
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..lineTo(p4.dx, p4.dy)
            ..close();

          if (prim.isConstruction) {
            _drawDashedPath(canvas, rectPath, strokePaint);
          } else {
            canvas.drawPath(rectPath, strokePaint);
          }

          if (isSel) {
            _drawHandle(canvas, p1);
            _drawHandle(canvas, p2);
            _drawHandle(canvas, p3);
            _drawHandle(canvas, p4);

            // Floating dimension labels
            final topMid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
            final rightMid = Offset((p2.dx + p3.dx) / 2, (p2.dy + p3.dy) / 2);
            _drawDimensionBadge(canvas, topMid, 'W: ${prim.width.toStringAsFixed(1)} mm');
            _drawDimensionBadge(canvas, rightMid, 'H: ${prim.height.toStringAsFixed(1)} mm');
          }
        }
      } else if (prim is CADCircleEntity) {
        final cScr = toScreen(prim.center);
        final rEdge = toScreen(Offset(prim.center.dx + prim.radius, prim.center.dy));
        if (cScr != Offset.zero && rEdge != Offset.zero) {
          final rPix = (rEdge - cScr).distance;
          if (prim.isConstruction) {
            _drawDashedCircle(canvas, cScr, rPix, strokePaint);
          } else {
            canvas.drawCircle(cScr, rPix, strokePaint);
          }

          if (isSel) {
            _drawHandle(canvas, cScr);
            _drawHandle(canvas, rEdge);
            canvas.drawLine(
              cScr,
              rEdge,
              Paint()
                ..color = const Color(0xFFF59E0B)
                ..strokeWidth = 1.0,
            );
            _drawDimensionBadge(canvas, Offset((cScr.dx + rEdge.dx) / 2, (cScr.dy + rEdge.dy) / 2), 'Ø ${(prim.radius * 2).toStringAsFixed(1)} mm');
          }
        }
      } else if (prim is CADLineEntity) {
        final sScr = toScreen(prim.start);
        final eScr = toScreen(prim.end);
        if (sScr != Offset.zero && eScr != Offset.zero) {
          if (prim.isConstruction) {
            _drawDashedLine(canvas, sScr, eScr, strokePaint);
          } else {
            canvas.drawLine(sScr, eScr, strokePaint);
          }
          if (isSel) {
            _drawHandle(canvas, sScr);
            _drawHandle(canvas, eScr);
            final mid = Offset((sScr.dx + eScr.dx) / 2, (sScr.dy + eScr.dy) / 2);
            final len = (prim.end - prim.start).distance;
            _drawDimensionBadge(canvas, mid, 'L: ${len.toStringAsFixed(1)} mm');
          }
        }
      } else if (prim is CADPolylineEntity) {
        if (prim.points.isNotEmpty) {
          final polyPath = Path();
          bool firstPt = true;
          for (final pt in prim.points) {
            final scr = toScreen(pt);
            if (scr == Offset.zero) continue;
            if (firstPt) {
              polyPath.moveTo(scr.dx, scr.dy);
              firstPt = false;
            } else {
              polyPath.lineTo(scr.dx, scr.dy);
            }
          }
          if (prim.isClosed) polyPath.close();
          if (prim.isConstruction) {
            _drawDashedPath(canvas, polyPath, strokePaint);
          } else {
            canvas.drawPath(polyPath, strokePaint);
          }
          if (isSel) {
            for (final pt in prim.points) {
              _drawHandle(canvas, toScreen(pt));
            }
          }
        }
      }
    }

    // 4. Glowing Yellow Dashed Inferencing Alignment Lines
    final inferPaint = Paint()
      ..color = const Color(0xFFFFD600)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final match in viewModel.currentInferenceGuides) {
      if (match.isHorizontal) {
        final p1 = toScreen(Offset(-extent * 1.5, match.value));
        final p2 = toScreen(Offset(extent * 1.5, match.value));
        if (p1 != Offset.zero && p2 != Offset.zero) {
          _drawDashedLine(canvas, p1, p2, inferPaint);
        }
      } else {
        final p1 = toScreen(Offset(match.value, -extent * 1.5));
        final p2 = toScreen(Offset(match.value, extent * 1.5));
        if (p1 != Offset.zero && p2 != Offset.zero) {
          _drawDashedLine(canvas, p1, p2, inferPaint);
        }
      }
    }

    // 5. Glowing Neon-Green Snapping Indicator Dot
    final hoverLocal = viewModel.activePlaneHoverLocal;
    if (hoverLocal != null) {
      final snapScr = toScreen(hoverLocal);
      if (snapScr != Offset.zero) {
        // Outer glow
        canvas.drawCircle(snapScr, 7.0, Paint()..color = const Color(0x6600FF66));
        // Solid center
        canvas.drawCircle(snapScr, 3.5, Paint()..color = const Color(0xFF00FF66));
      }
    }
  }

  void _drawHandle(Canvas canvas, Offset pt) {
    if (pt == Offset.zero) return;
    canvas.drawRect(Rect.fromCenter(center: pt, width: 7.0, height: 7.0), Paint()..color = Colors.white);
    canvas.drawRect(
      Rect.fromCenter(center: pt, width: 7.0, height: 7.0),
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawDimensionBadge(Canvas canvas, Offset pos, String text) {
    if (pos == Offset.zero) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 9.5, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos + const Offset(0, -12), width: tp.width + 10, height: tp.height + 4),
      const Radius.circular(4),
    );

    canvas.drawRRect(badgeRect, Paint()..color = Colors.white.withAlpha(230));
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, pos + Offset(-tp.width / 2, -12 - tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dist = (p2 - p1).distance;
    if (dist < 1.0) return;
    final dir = (p2 - p1) / dist;
    double walked = 0.0;
    while (walked < dist) {
      final start = p1 + dir * walked;
      final end = p1 + dir * math.min(walked + 5.0, dist);
      canvas.drawLine(start, end, paint);
      walked += 9.0;
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    const int dashCount = 36;
    final double stepAngle = (2 * math.pi) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      final double a1 = i * stepAngle;
      final double a2 = (i + 1) * stepAngle;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), a1, a2 - a1, false, paint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double dist = 0.0;
      while (dist < metric.length) {
        final extract = metric.extractPath(dist, math.min(dist + 6.0, metric.length));
        canvas.drawPath(extract, paint);
        dist += 10.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant Assembly3DSurfaceSketchPainter oldDelegate) {
    return true;
  }
}
