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
    if (viewModel.showSketchGrid) {
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

    // 2. Interior Shaded Tessellated Profiles (shade ALL valid closed loops on the plane!)
    final validation = viewModel.activeSketchValidation;
    if (viewModel.showSketchProfileShading && validation != null && validation.isValidClosedLoop) {
      final loopsToFill = validation.allClosedLoops.isNotEmpty
          ? validation.allClosedLoops
          : (validation.orderedPathVertices.length >= 3 ? [validation.orderedPathVertices] : <List<Offset>>[]);
      final fillPaint = Paint()
        ..color = const Color(0x380284C7)
        ..style = PaintingStyle.fill;

      for (final loop in loopsToFill) {
        if (loop.length < 3) continue;
        final fillPath = Path();
        bool first = true;
        for (final pt in loop) {
          final scr = toScreen(pt);
          if (scr == Offset.zero) continue;
          if (first) {
            fillPath.moveTo(scr.dx, scr.dy);
            first = false;
          } else {
            fillPath.lineTo(scr.dx, scr.dy);
          }
        }
        if (!first) {
          fillPath.close();
          canvas.drawPath(fillPath, fillPaint);
        }
      }
    }

    // 3. Render Primitive Entities & Segments
    for (final prim in plane.primitives) {
      final isSel = (prim.id == viewModel.selectedSketchEntity?.id);
      final isConstrained = prim.isFullyConstrained;
      final isOverConstrained = viewModel.lastConstraintSolverResult?.conflictingConstraints
              .any((c) => c.entityIds.contains(prim.id)) ??
          false;
      final strokePaint = Paint()
        ..color = isOverConstrained
            ? const Color(0xFFEF4444) // Onshape Red for over-constrained / conflicting geometry!
            : isSel
            ? const Color(0xFFF59E0B) // Amber for selected
            : prim.isProjected
            ? const Color(0xFFC084FC) // Purple/Magenta for projected geometry
            : prim.isConstruction
            ? const Color(0xFF38BDF8) // Light blue for construction
            : isConstrained
            ? const Color(0xFF0F172A) // Black / Slate 900 for fully constrained geometry
            : const Color(0xFF0284C7) // Blue for under-constrained geometry
        ..strokeWidth = isSel ? 2.8 : (prim.isProjected ? 2.2 : (isConstrained ? 2.2 : 1.8))
        ..style = PaintingStyle.stroke;

      // High-contrast halo underlay for CAD visibility when rotated/behind parts (Bug 3 / SS4)
      final haloPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.90)
        ..strokeWidth = strokePaint.strokeWidth + 2.2
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

          canvas.drawPath(rectPath, haloPaint);
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
      } else if (prim is CADCenterRectangleEntity) {
        final p1 = toScreen(prim.topLeft);
        final p2 = toScreen(prim.topRight);
        final p3 = toScreen(prim.bottomRight);
        final p4 = toScreen(prim.bottomLeft);
        final cScr = toScreen(prim.center);

        if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
          final rectPath = Path()
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..lineTo(p4.dx, p4.dy)
            ..close();

          canvas.drawPath(rectPath, haloPaint);
          if (prim.isConstruction) {
            _drawDashedPath(canvas, rectPath, strokePaint);
          } else {
            canvas.drawPath(rectPath, strokePaint);
          }

          if (prim.hasDiagonalConstruction || isSel) {
            final diagPaint = Paint()
              ..color = const Color(0xFF38BDF8).withValues(alpha: 0.6)
              ..strokeWidth = 1.0;
            _drawDashedLine(canvas, p1, p3, diagPaint);
            _drawDashedLine(canvas, p4, p2, diagPaint);
          }

          if (isSel) {
            _drawHandle(canvas, cScr);
            _drawHandle(canvas, p1);
            _drawHandle(canvas, p2);
            _drawHandle(canvas, p3);
            _drawHandle(canvas, p4);

            final topMid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
            final rightMid = Offset((p2.dx + p3.dx) / 2, (p2.dy + p3.dy) / 2);
            _drawDimensionBadge(canvas, topMid, 'W: ${prim.width.toStringAsFixed(1)} mm');
            _drawDimensionBadge(canvas, rightMid, 'H: ${prim.height.toStringAsFixed(1)} mm');
          }
        }
      } else if (prim is CADArcEntity) {
        final geom = prim.computeCircumcircle();
        final sScr = toScreen(prim.startPoint);
        final eScr = toScreen(prim.endPoint);
        final mScr = toScreen(prim.pointOnArc);

        if (geom == null) {
          if (sScr != Offset.zero && eScr != Offset.zero) {
            canvas.drawLine(sScr, eScr, haloPaint);
            canvas.drawLine(sScr, eScr, strokePaint);
          }
        } else {
          final cScr = toScreen(geom.center);
          final arcPath = Path();
          const int numSegs = 32;
          for (int i = 0; i <= numSegs; i++) {
            final t = i / numSegs;
            final ang = geom.startAngle + t * geom.sweep;
            final ptLocal = Offset(geom.center.dx + geom.radius * math.cos(ang), geom.center.dy + geom.radius * math.sin(ang));
            final ptScr = toScreen(ptLocal);
            if (i == 0) {
              arcPath.moveTo(ptScr.dx, ptScr.dy);
            } else {
              arcPath.lineTo(ptScr.dx, ptScr.dy);
            }
          }

          canvas.drawPath(arcPath, haloPaint);
          if (prim.isConstruction) {
            _drawDashedPath(canvas, arcPath, strokePaint);
          } else {
            canvas.drawPath(arcPath, strokePaint);
          }

          if (isSel) {
            _drawHandle(canvas, sScr);
            _drawHandle(canvas, eScr);
            _drawHandle(canvas, mScr);
            _drawHandle(canvas, cScr);
            _drawDimensionBadge(canvas, mScr, 'R: ${geom.radius.toStringAsFixed(1)} mm');
          }
        }
      } else if (prim is CADCircleEntity) {
        final cScr = toScreen(prim.center);
        final rEdge = toScreen(Offset(prim.center.dx + prim.radius, prim.center.dy));
        if (cScr != Offset.zero) {
          final circlePath = Path();
          const int segs = 48;
          for (int i = 0; i <= segs; i++) {
            final theta = i * 2.0 * math.pi / segs;
            final ptLocal = Offset(
              prim.center.dx + prim.radius * math.cos(theta),
              prim.center.dy + prim.radius * math.sin(theta),
            );
            final ptScr = toScreen(ptLocal);
            if (i == 0) {
              circlePath.moveTo(ptScr.dx, ptScr.dy);
            } else {
              circlePath.lineTo(ptScr.dx, ptScr.dy);
            }
          }
          circlePath.close();

          canvas.drawPath(circlePath, haloPaint);
          if (prim.isConstruction) {
            _drawDashedPath(canvas, circlePath, strokePaint);
          } else {
            canvas.drawPath(circlePath, strokePaint);
          }

          // Center crosshair mark
          final crossPaint = Paint()
            ..color = strokePaint.color
            ..strokeWidth = 1.2;
          canvas.drawLine(cScr - const Offset(4.0, 0), cScr + const Offset(4.0, 0), crossPaint);
          canvas.drawLine(cScr - const Offset(0, 4.0), cScr + const Offset(0, 4.0), crossPaint);

          if (isSel) {
            _drawHandle(canvas, cScr);
            if (rEdge != Offset.zero) {
              _drawHandle(canvas, rEdge);
              canvas.drawLine(
                cScr,
                rEdge,
                Paint()
                  ..color = const Color(0xFFF59E0B)
                  ..strokeWidth = 1.2,
              );
              _drawDimensionBadge(
                canvas,
                Offset((cScr.dx + rEdge.dx) / 2, (cScr.dy + rEdge.dy) / 2),
                'Ø ${(prim.radius * 2).toStringAsFixed(1)} mm',
              );
            }
          } else if (viewModel.showSketchExpressions) {
            _drawDimensionBadge(
              canvas,
              cScr + const Offset(12.0, -12.0),
              'Ø ${(prim.radius * 2).toStringAsFixed(1)}',
            );
          }
        }
      } else if (prim is CADLineEntity) {
        final sScr = toScreen(prim.start);
        final eScr = toScreen(prim.end);
        if (sScr != Offset.zero && eScr != Offset.zero) {
          canvas.drawLine(sScr, eScr, haloPaint);
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
          canvas.drawPath(polyPath, haloPaint);
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
      } else if (prim is CADPointEntity) {
        final ptScr = toScreen(prim.position);
        if (ptScr != Offset.zero) {
          canvas.drawCircle(ptScr, 3.5, Paint()..color = strokePaint.color);
          canvas.drawLine(ptScr - const Offset(5, 0), ptScr + const Offset(5, 0), Paint()..color = strokePaint.color..strokeWidth = 1.2);
          canvas.drawLine(ptScr - const Offset(0, 5), ptScr + const Offset(0, 5), Paint()..color = strokePaint.color..strokeWidth = 1.2);
          if (isSel) {
            _drawHandle(canvas, ptScr);
          }
        }
      } else {
        // Universal renderer for AlignedRect, Ellipse, CenterPointArc, Conic, RegularPolygon, Spline/Bezier, Slot, and Text
        final segs = prim.toLineSegments();
        if (segs.isNotEmpty) {
          final path = Path();
          for (final s in segs) {
            final pA = toScreen(s.start);
            final pB = toScreen(s.end);
            if (pA != Offset.zero && pB != Offset.zero) {
              path.moveTo(pA.dx, pA.dy);
              path.lineTo(pB.dx, pB.dy);
            }
          }
          canvas.drawPath(path, haloPaint);
          if (prim.isConstruction) {
            _drawDashedPath(canvas, path, strokePaint);
          } else {
            canvas.drawPath(path, strokePaint);
          }
        }
        // Draw construction inscribed/circumscribed circle for RegularPolygon
        if (prim is CADRegularPolygonEntity) {
          final cPath = Path();
          for (int i = 0; i <= 36; i++) {
            final a = (2.0 * math.pi * i) / 36;
            final pt = toScreen(prim.center + Offset(math.cos(a), math.sin(a)) * prim.radius);
            if (i == 0) {
              cPath.moveTo(pt.dx, pt.dy);
            } else {
              cPath.lineTo(pt.dx, pt.dy);
            }
          }
          _drawDashedPath(canvas, cPath, Paint()..color = const Color(0xFF38BDF8)..strokeWidth = 1.0..style = PaintingStyle.stroke);
          _drawDimensionBadge(canvas, toScreen(prim.center), '${prim.sides}x');
        }
      }
    }

    // 4. Glowing Yellow Dashed Inferencing Alignment Lines
    final inferPaint = Paint()
      ..color = const Color(0xFFFFD600)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const double inferExtent = 300.0;
    for (final match in viewModel.currentInferenceGuides) {
      if (match.isHorizontal) {
        final p1 = toScreen(Offset(-inferExtent, match.value));
        final p2 = toScreen(Offset(inferExtent, match.value));
        if (p1 != Offset.zero && p2 != Offset.zero) {
          _drawDashedLine(canvas, p1, p2, inferPaint);
        }
      } else {
        final p1 = toScreen(Offset(match.value, -inferExtent));
        final p2 = toScreen(Offset(match.value, inferExtent));
        if (p1 != Offset.zero && p2 != Offset.zero) {
          _drawDashedLine(canvas, p1, p2, inferPaint);
        }
      }
    }

    // 5. Snapping point indicator (Item 5b: pointed mouse, no giant green dot)
    final hoverLocal = viewModel.activePlaneHoverLocal;


    // 5b. Live Interactive Sketch Rubber-Band Preview (Phase 3)
    if (viewModel.sketchInteractiveStartPoint != null && hoverLocal != null) {
      final pStart = viewModel.sketchInteractiveStartPoint!;
      final sScr = toScreen(pStart);
      final hScr = toScreen(hoverLocal);
      final previewPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;

      if (sScr != Offset.zero && hScr != Offset.zero) {
        final tool = viewModel.activeSketchTool;

        if (tool == 'rectangle' || tool == 'rect') {
          final x = math.min(pStart.dx, hoverLocal.dx);
          final y = math.min(pStart.dy, hoverLocal.dy);
          final w = (hoverLocal.dx - pStart.dx).abs();
          final h = (hoverLocal.dy - pStart.dy).abs();
          final p1 = toScreen(Offset(x, y));
          final p2 = toScreen(Offset(x + w, y));
          final p3 = toScreen(Offset(x + w, y + h));
          final p4 = toScreen(Offset(x, y + h));

          if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
            final rPath = Path()..moveTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..lineTo(p3.dx, p3.dy)..lineTo(p4.dx, p4.dy)..close();
            _drawDashedPath(canvas, rPath, previewPaint);
            _drawDimensionBadge(canvas, Offset((p1.dx + p3.dx) / 2, (p1.dy + p3.dy) / 2), '${w.toStringAsFixed(1)} x ${h.toStringAsFixed(1)} mm');
          }
        } else if (tool == 'center_rect') {
          final w = 2.0 * (hoverLocal.dx - pStart.dx).abs();
          final h = 2.0 * (hoverLocal.dy - pStart.dy).abs();
          final x = pStart.dx - w / 2.0;
          final y = pStart.dy - h / 2.0;
          final p1 = toScreen(Offset(x, y));
          final p2 = toScreen(Offset(x + w, y));
          final p3 = toScreen(Offset(x + w, y + h));
          final p4 = toScreen(Offset(x, y + h));

          if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
            final rPath = Path()..moveTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..lineTo(p3.dx, p3.dy)..lineTo(p4.dx, p4.dy)..close();
            _drawDashedPath(canvas, rPath, previewPaint);
            _drawDashedLine(canvas, p1, p3, Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.5)..strokeWidth = 1.0);
            _drawDashedLine(canvas, p4, p2, Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.5)..strokeWidth = 1.0);
            _drawHandle(canvas, sScr);
            _drawDimensionBadge(canvas, sScr, '${w.toStringAsFixed(1)} x ${h.toStringAsFixed(1)} mm');
          }
        } else if (tool == 'circle' || tool == 'hole') {
          final rLocal = (hoverLocal - pStart).distance;
          final circlePath = Path();
          const int segs = 36;
          for (int i = 0; i <= segs; i++) {
            final theta = i * 2.0 * math.pi / segs;
            final ptLocal = Offset(
              pStart.dx + rLocal * math.cos(theta),
              pStart.dy + rLocal * math.sin(theta),
            );
            final ptScr = toScreen(ptLocal);
            if (i == 0) {
              circlePath.moveTo(ptScr.dx, ptScr.dy);
            } else {
              circlePath.lineTo(ptScr.dx, ptScr.dy);
            }
          }
          circlePath.close();
          _drawDashedPath(canvas, circlePath, previewPaint);
          canvas.drawLine(sScr, hScr, Paint()..color = const Color(0xFFF59E0B)..strokeWidth = 1.0);
          _drawHandle(canvas, sScr);
          _drawDimensionBadge(canvas, Offset((sScr.dx + hScr.dx) / 2, (sScr.dy + hScr.dy) / 2), 'Ø ${(rLocal * 2).toStringAsFixed(1)} mm');
        } else if (tool == 'arc_3point') {
          if (viewModel.sketchInteractiveMidPoint == null) {
            _drawDashedLine(canvas, sScr, hScr, previewPaint);
            _drawHandle(canvas, sScr);
            _drawDimensionBadge(canvas, hScr, 'End Point (Click)');
          } else {
            final pEnd = viewModel.sketchInteractiveMidPoint!;
            final arcTemp = CADArcEntity(id: 'temp_arc', startPoint: pStart, endPoint: pEnd, pointOnArc: hoverLocal);
            final geom = arcTemp.computeCircumcircle();
            if (geom != null) {
              final arcPath = Path();
              const int numSegs = 24;
              for (int i = 0; i <= numSegs; i++) {
                final t = i / numSegs;
                final ang = geom.startAngle + t * geom.sweep;
                final pt = toScreen(Offset(geom.center.dx + geom.radius * math.cos(ang), geom.center.dy + geom.radius * math.sin(ang)));
                if (i == 0) {
                  arcPath.moveTo(pt.dx, pt.dy);
                } else {
                  arcPath.lineTo(pt.dx, pt.dy);
                }
              }
              _drawDashedPath(canvas, arcPath, previewPaint);
              _drawDimensionBadge(canvas, hScr, 'R: ${geom.radius.toStringAsFixed(1)} mm');
            } else {
              _drawDashedLine(canvas, sScr, hScr, previewPaint);
            }
          }
        } else if (tool == 'line') {
          _drawDashedLine(canvas, sScr, hScr, previewPaint);
          _drawHandle(canvas, sScr);
          final len = (hoverLocal - pStart).distance;
          _drawDimensionBadge(canvas, Offset((sScr.dx + hScr.dx) / 2, (sScr.dy + hScr.dy) / 2), 'L: ${len.toStringAsFixed(1)} mm');
        }
      }
    }

    if (viewModel.sketchPolylinePoints.isNotEmpty && hoverLocal != null) {
      final pts = viewModel.sketchPolylinePoints;
      final polyPaint = Paint()..color = const Color(0xFF0284C7)..strokeWidth = 1.8..style = PaintingStyle.stroke;
      for (int i = 0; i < pts.length - 1; i++) {
        final p1 = toScreen(pts[i]);
        final p2 = toScreen(pts[i + 1]);
        if (p1 != Offset.zero && p2 != Offset.zero) canvas.drawLine(p1, p2, polyPaint);
      }
      final lastScr = toScreen(pts.last);
      final hScr = toScreen(hoverLocal);
      if (lastScr != Offset.zero && hScr != Offset.zero) {
        _drawDashedLine(canvas, lastScr, hScr, Paint()..color = const Color(0xFF38BDF8)..strokeWidth = 1.5);
      }
    }

    // 6. Project Geometry Mode 3D Entity Hover Visualizer (Phase 2)
    if (viewModel.isProjectGeometryMode) {
      if (viewModel.hoveredProjectableEdge != null && viewModel.hoveredProjectableEdge!.length >= 2) {
        final p1 = projectPoint(viewModel.hoveredProjectableEdge![0]);
        final p2 = projectPoint(viewModel.hoveredProjectableEdge![1]);
        if (p1 != Offset.zero && p2 != Offset.zero) {
          final glowPaint = Paint()
            ..color = const Color(0xFFC084FC).withValues(alpha: 0.35)
            ..strokeWidth = 6.0
            ..strokeCap = StrokeCap.round;
          final edgePaint = Paint()
            ..color = const Color(0xFFC084FC)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(p1, p2, glowPaint);
          canvas.drawLine(p1, p2, edgePaint);

          final mid = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);
          _drawProjectBadge(canvas, mid, 'PROJECT EDGE (P)');
        }
      } else if (viewModel.hoveredProjectablePoint != null) {
        final ptScr = projectPoint(viewModel.hoveredProjectablePoint!);
        if (ptScr != Offset.zero) {
          canvas.drawCircle(ptScr, 8.0, Paint()..color = const Color(0xFFC084FC).withValues(alpha: 0.35));
          canvas.drawCircle(ptScr, 4.0, Paint()..color = const Color(0xFFC084FC));
          _drawProjectBadge(canvas, ptScr, 'PROJECT VERTEX (P)');
        }
      }
    }

    // 6. Geometric Constraint Glyphs & Badges (Phase 4 - Autodesk Fusion 360)
    if (viewModel.showSketchConstraints && plane.constraints.isNotEmpty) {
      for (final constraint in plane.constraints) {
        if (!constraint.isActive) continue;
        final isConstraintSelected = (viewModel.selectedSketchConstraint?.id == constraint.id) ||
            constraint.entityIds.any((id) => viewModel.selectedSketchEntityIds.contains(id));

        Offset? badgePos;
        if (constraint.entityIds.isNotEmpty) {
          final firstEnt = plane.primitives.where((p) => p.id == constraint.entityIds[0]).firstOrNull;
          if (firstEnt != null) {
            badgePos = toScreen(_getEntityBadgeAnchor(firstEnt));
          }
        }

        if (badgePos != null && badgePos != Offset.zero) {
          _drawConstraintBadge(canvas, badgePos, constraint.symbol, isHighlighted: isConstraintSelected);
        }
      }
    }
  }

  void _drawProjectBadge(Canvas canvas, Offset pos, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos + const Offset(0, -16), width: tp.width + 12, height: tp.height + 6),
      const Radius.circular(4),
    );

    canvas.drawRRect(badgeRect, Paint()..color = const Color(0xFF581C87).withValues(alpha: 0.94));
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = const Color(0xFFC084FC)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
    tp.paint(canvas, pos + Offset(-tp.width / 2, -16 - tp.height / 2));
  }

  Offset _getEntityBadgeAnchor(CADPrimitiveEntity e) {
    if (e is CADLineEntity) {
      return Offset((e.start.dx + e.end.dx) / 2.0, (e.start.dy + e.end.dy) / 2.0);
    } else if (e is CADCircleEntity) {
      return Offset(e.center.dx, e.center.dy - e.radius);
    } else if (e is CADArcEntity) {
      return e.pointOnArc;
    } else if (e is CADRectangleEntity) {
      return Offset(e.startPoint.dx + e.width / 2.0, e.startPoint.dy);
    } else if (e is CADCenterRectangleEntity) {
      return Offset(e.center.dx, e.center.dy - e.height / 2.0);
    }
    return Offset.zero;
  }

  void _drawConstraintBadge(Canvas canvas, Offset pos, String symbol, {bool isHighlighted = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(
          color: isHighlighted ? const Color(0xFFB45309) : const Color(0xFF0369A1),
          fontSize: 10.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos + const Offset(0, -10), width: math.max(16.0, tp.width + 6), height: math.max(16.0, tp.height + 4)),
      const Radius.circular(3),
    );

    canvas.drawRRect(
      badgeRect,
      Paint()..color = isHighlighted ? const Color(0xFFFEF3C7) : Colors.white,
    );
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = isHighlighted ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
    tp.paint(canvas, pos + Offset(-tp.width / 2, -10 - tp.height / 2));
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
