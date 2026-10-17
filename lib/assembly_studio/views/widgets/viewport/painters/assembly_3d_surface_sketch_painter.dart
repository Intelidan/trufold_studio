import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Renders real-time 3D parametric sketch geometry and Onshape CAD Engineering Dimensions
/// (witness/extension lines, filled arrowheads, radial/diametric leaders, angular arcs,
/// and clickable inline dimension tags matching image_31d02d.png and image_31d0a3.png).
class Assembly3DSurfaceSketchPainter extends CustomPainter {
  final AssemblyStudioViewModel viewModel;
  final Offset Function(CadPoint3D) projectPoint;

  Assembly3DSurfaceSketchPainter({required this.viewModel, required this.projectPoint});

  @override
  void paint(Canvas canvas, Size size) {
    final plane = viewModel.activeSketchPlane;
    if (plane == null) return;

    viewModel.sketchDimensionHitRects.clear();

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
        ..color = const Color(0x260284C7)
        ..strokeWidth = 0.8;

      const double extent = 200.0;
      const double step = 20.0;
      final int lineCount = (extent / step).round();

      for (int i = -lineCount; i <= lineCount; i++) {
        final val = i * step;
        final s1 = toScreen(Offset(val, -extent));
        final e1 = toScreen(Offset(val, extent));
        if (s1 != Offset.zero && e1 != Offset.zero) {
          canvas.drawLine(s1, e1, gridPaint);
        }
        final s2 = toScreen(Offset(-extent, val));
        final e2 = toScreen(Offset(extent, val));
        if (s2 != Offset.zero && e2 != Offset.zero) {
          canvas.drawLine(s2, e2, gridPaint);
        }
      }
    }

    // Sketch Origin Crosshair & Axes (Onshape dark crosshair + subtle R/G axes)
    final scrOrigin = toScreen(Offset.zero);
    final scrXAxis = toScreen(const Offset(30.0, 0.0));
    final scrYAxis = toScreen(const Offset(0.0, 30.0));
    if (scrOrigin != Offset.zero) {
      if (scrXAxis != Offset.zero) {
        canvas.drawLine(scrOrigin, scrXAxis, Paint()..color = const Color(0x99EF4444)..strokeWidth = 1.6);
      }
      if (scrYAxis != Offset.zero) {
        canvas.drawLine(scrOrigin, scrYAxis, Paint()..color = const Color(0x9910B981)..strokeWidth = 1.6);
      }
      canvas.drawCircle(
        scrOrigin,
        4.0,
        Paint()
          ..color = const Color(0xFF334155)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // 2. Interior Shaded Closed Profiles (Onshape translucent steel-blue region fill + orange highlight when Extrude is active)
    final validation = viewModel.activeSketchValidation;
    if (viewModel.showSketchProfileShading && validation != null && validation.isValidClosedLoop) {
      final loopsToFill = validation.allClosedLoops.isNotEmpty
          ? validation.allClosedLoops
          : (validation.orderedPathVertices.length >= 3 ? [validation.orderedPathVertices] : <List<Offset>>[]);

      final isExtrudeHighlight = viewModel.isExtrudeMode;
      final fillPaint = Paint()
        ..color = isExtrudeHighlight ? const Color(0x45F59E0B) : const Color(0x320284C7)
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
          if (isExtrudeHighlight) {
            canvas.drawPath(
              fillPath,
              Paint()
                ..color = const Color(0xFFF59E0B)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4,
            );
          }
        }
      }
    }

    // Track which entities already have an explicit driving dimensional constraint
    final entitiesWithDrivingDim = <String>{};
    for (final c in plane.constraints) {
      if (c.isActive && c.isDimensional) {
        for (final eid in c.entityIds) {
          entitiesWithDrivingDim.add(eid);
        }
      }
    }

    // 3. Render Primitive Entities & Onshape CAD Dimensions
    for (final prim in plane.primitives) {
      final isSel = (prim.id == viewModel.selectedSketchEntity?.id) ||
          viewModel.selectedSketchEntityIds.contains(prim.id);
      final isConstrained = prim.isFullyConstrained;
      final isOverConstrained = viewModel.lastConstraintSolverResult?.conflictingConstraints
              .any((c) => c.entityIds.contains(prim.id)) ??
          false;

      final strokePaint = Paint()
        ..color = isOverConstrained
            ? const Color(0xFFEF4444) // Onshape Red for conflicting geometry
            : isSel
                ? const Color(0xFFF59E0B) // Onshape Amber/Orange for selected geometry
                : prim.isProjected
                    ? const Color(0xFFC084FC) // Purple for projected 3D geometry
                    : prim.isConstruction
                        ? const Color(0xFF475569) // Slate dashed for construction geometry
                        : isConstrained
                            ? const Color(0xFF0F172A) // Onshape Black for fully defined geometry
                            : const Color(0xFF0284C7) // Onshape Blue for under-defined geometry
        ..strokeWidth = isSel ? 2.6 : (prim.isConstruction ? 1.4 : 2.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final haloPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = strokePaint.strokeWidth + 2.0
        ..style = PaintingStyle.stroke;

      if (prim is CADRectangleEntity) {
        final p1Local = prim.startPoint;
        final p2Local = Offset(prim.startPoint.dx + prim.width, prim.startPoint.dy);
        final p3Local = Offset(prim.startPoint.dx + prim.width, prim.startPoint.dy + prim.height);
        final p4Local = Offset(prim.startPoint.dx, prim.startPoint.dy + prim.height);

        final p1 = toScreen(p1Local);
        final p2 = toScreen(p2Local);
        final p3 = toScreen(p3Local);
        final p4 = toScreen(p4Local);

        if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
          final rectPath = Path()
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..lineTo(p4.dx, p4.dy)
            ..close();

          canvas.drawPath(rectPath, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, rectPath, strokePaint);
          } else {
            canvas.drawPath(rectPath, strokePaint);
          }

          _drawVertexDot(canvas, p1, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p2, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p3, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p4, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p1,
              pB: p2,
              offsetPx: -26.0,
              label: _formatDimValue(prim.width),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: '${prim.id}:w',
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: prim.width,
                subKey: 'w',
              ),
            );
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p2,
              pB: p3,
              offsetPx: 28.0,
              label: _formatDimValue(prim.height),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: '${prim.id}:h',
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: prim.height,
                subKey: 'h',
              ),
            );
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
            _drawCenterlineDashedPath(canvas, rectPath, strokePaint);
          } else {
            canvas.drawPath(rectPath, strokePaint);
          }

          if (prim.hasDiagonalConstruction || isSel) {
            final diagPaint = Paint()
              ..color = const Color(0xFF64748B).withValues(alpha: 0.65)
              ..strokeWidth = 1.1;
            _drawDashedLine(canvas, p1, p3, diagPaint);
            _drawDashedLine(canvas, p4, p2, diagPaint);
          }

          _drawVertexDot(canvas, cScr, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p1, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p2, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p3, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p4, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p1,
              pB: p2,
              offsetPx: -26.0,
              label: _formatDimValue(prim.width),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: '${prim.id}:w',
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: prim.width,
                subKey: 'w',
              ),
            );
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p2,
              pB: p3,
              offsetPx: 28.0,
              label: _formatDimValue(prim.height),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: '${prim.id}:h',
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: prim.height,
                subKey: 'h',
              ),
            );
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
          const int numSegs = 36;
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
            _drawCenterlineDashedPath(canvas, arcPath, strokePaint);
          } else {
            canvas.drawPath(arcPath, strokePaint);
          }

          _drawVertexDot(canvas, sScr, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, eScr, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, cScr, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
            _drawRadialOrDiameterLeaderDimension(
              canvas: canvas,
              centerScr: cScr,
              rimScr: mScr,
              label: 'R${_formatDimValue(geom.radius)}',
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: prim.id,
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.radius,
                currentValue: geom.radius,
              ),
            );
          }
        }
      } else if (prim is CADCircleEntity) {
        final cScr = toScreen(prim.center);
        // 35° leader point on the circle rim (matches Onshape Ø17 / Ø33 in image_31d02d.png!)
        const double leaderAngle = -math.pi / 4.0;
        final rimLocal = Offset(
          prim.center.dx + prim.radius * math.cos(leaderAngle),
          prim.center.dy + prim.radius * math.sin(leaderAngle),
        );
        final rEdge = toScreen(rimLocal);

        if (cScr != Offset.zero) {
          final circlePath = Path();
          const int segs = 56;
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
            _drawCenterlineDashedPath(canvas, circlePath, strokePaint);
          } else {
            canvas.drawPath(circlePath, strokePaint);
          }

          _drawVertexDot(canvas, cScr, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) &&
              !entitiesWithDrivingDim.contains(prim.id) &&
              rEdge != Offset.zero) {
            _drawRadialOrDiameterLeaderDimension(
              canvas: canvas,
              centerScr: cScr,
              rimScr: rEdge,
              label: 'Ø${_formatDimValue(prim.radius * 2.0)}',
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: prim.id,
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.diameter,
                currentValue: prim.radius * 2.0,
              ),
            );
          }
        }
      } else if (prim is CADLineEntity) {
        final sScr = toScreen(prim.start);
        final eScr = toScreen(prim.end);
        if (sScr != Offset.zero && eScr != Offset.zero) {
          canvas.drawLine(sScr, eScr, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedLine(canvas, sScr, eScr, strokePaint);
          } else {
            canvas.drawLine(sScr, eScr, strokePaint);
          }
          _drawVertexDot(canvas, sScr, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, eScr, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) &&
              !prim.isConstruction &&
              !entitiesWithDrivingDim.contains(prim.id)) {
            final len = (prim.end - prim.start).distance;
            _drawLinearCadDimension(
              canvas: canvas,
              pA: sScr,
              pB: eScr,
              offsetPx: -26.0,
              label: _formatDimValue(len),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: prim.id,
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: len,
              ),
            );
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
            _drawCenterlineDashedPath(canvas, polyPath, strokePaint);
          } else {
            canvas.drawPath(polyPath, strokePaint);
          }
          for (final pt in prim.points) {
            _drawVertexDot(canvas, toScreen(pt), strokePaint.color, isSel: isSel);
          }
        }
      } else if (prim is CADPointEntity) {
        final ptScr = toScreen(prim.position);
        if (ptScr != Offset.zero) {
          _drawVertexDot(canvas, ptScr, strokePaint.color, isSel: isSel);
        }
      } else {
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
            _drawCenterlineDashedPath(canvas, path, strokePaint);
          } else {
            canvas.drawPath(path, strokePaint);
          }
        }
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
          _drawCenterlineDashedPath(
            canvas,
            cPath,
            Paint()
              ..color = const Color(0xFF64748B)
              ..strokeWidth = 1.1
              ..style = PaintingStyle.stroke,
          );
          _drawVertexDot(canvas, toScreen(prim.center), strokePaint.color, isSel: isSel);
        }
      }
    }

    // 4. Render All Explicit Driving Dimensional Constraints (image_31d02d.png & image_31d0a3.png)
    for (final c in plane.constraints) {
      if (!c.isActive || !c.isDimensional) continue;
      _drawDrivingDimensionConstraint(canvas, plane, c, toScreen);
    }

    // 5. Render Geometric Constraint Glyphs (H, V, ⊥, //, ◎, ⌒, =, ⇋)
    if (viewModel.showSketchConstraints && plane.constraints.isNotEmpty) {
      for (final constraint in plane.constraints) {
        if (!constraint.isActive || constraint.isDimensional) continue;
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

    // 6. Glowing Yellow Dashed Inferencing Alignment Lines + Live H/V Inference Badge
    final inferPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.1
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

    // 7. Live Interactive Sketch Rubber-Band Preview
    final hoverLocal = viewModel.activePlaneHoverLocal;
    if (viewModel.sketchInteractiveStartPoint != null && hoverLocal != null) {
      final pStart = viewModel.sketchInteractiveStartPoint!;
      final sScr = toScreen(pStart);
      final hScr = toScreen(hoverLocal);
      final previewPaint = Paint()
        ..color = const Color(0xFF0284C7)
        ..strokeWidth = 1.8
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
            final rPath = Path()
              ..moveTo(p1.dx, p1.dy)
              ..lineTo(p2.dx, p2.dy)
              ..lineTo(p3.dx, p3.dy)
              ..lineTo(p4.dx, p4.dy)
              ..close();
            _drawDashedPath(canvas, rPath, previewPaint);
            _drawLinearCadDimension(canvas: canvas, pA: p1, pB: p2, offsetPx: -24.0, label: _formatDimValue(w), isDriving: false);
            _drawLinearCadDimension(canvas: canvas, pA: p2, pB: p3, offsetPx: 24.0, label: _formatDimValue(h), isDriving: false);
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
            final rPath = Path()
              ..moveTo(p1.dx, p1.dy)
              ..lineTo(p2.dx, p2.dy)
              ..lineTo(p3.dx, p3.dy)
              ..lineTo(p4.dx, p4.dy)
              ..close();
            _drawDashedPath(canvas, rPath, previewPaint);
            _drawLinearCadDimension(canvas: canvas, pA: p1, pB: p2, offsetPx: -24.0, label: _formatDimValue(w), isDriving: false);
            _drawLinearCadDimension(canvas: canvas, pA: p2, pB: p3, offsetPx: 24.0, label: _formatDimValue(h), isDriving: false);
          }
        } else if (tool == 'circle' || tool == 'hole') {
          final rLocal = (hoverLocal - pStart).distance;
          final circlePath = Path();
          const int segs = 48;
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
          _drawRadialOrDiameterLeaderDimension(
            canvas: canvas,
            centerScr: sScr,
            rimScr: hScr,
            label: 'Ø${_formatDimValue(rLocal * 2.0)}',
            isDriving: false,
          );
        } else if (tool == 'line' || tool == 'midpoint_line') {
          _drawDashedLine(canvas, sScr, hScr, previewPaint);
          _drawVertexDot(canvas, sScr, const Color(0xFF0284C7), isSel: true);
          final len = (hoverLocal - pStart).distance;
          _drawLinearCadDimension(canvas: canvas, pA: sScr, pB: hScr, offsetPx: -24.0, label: _formatDimValue(len), isDriving: false);

          // Show live Onshape H / V automatic constraint inference badge while drawing a line!
          final dx = (hoverLocal.dx - pStart.dx).abs();
          final dy = (hoverLocal.dy - pStart.dy).abs();
          if (len > 3.0) {
            if (dy < dx * 0.06) {
              _drawConstraintBadge(canvas, Offset((sScr.dx + hScr.dx) / 2, (sScr.dy + hScr.dy) / 2 + 18), 'H', isHighlighted: true);
            } else if (dx < dy * 0.06) {
              _drawConstraintBadge(canvas, Offset((sScr.dx + hScr.dx) / 2 + 18, (sScr.dy + hScr.dy) / 2), 'V', isHighlighted: true);
            }
          }
        }
      }
    }
  }

  /// Renders an explicit driving `CadConstraint` dimension (`distance`, `diameter`, `radius`, `angle`)
  /// using authentic Onshape CAD extension lines, arrowheads, leader lines, or angular arcs.
  void _drawDrivingDimensionConstraint(
    Canvas canvas,
    CADSketchPlane plane,
    CadConstraint c,
    Offset Function(Offset) toScreen,
  ) {
    if (c.entityIds.isEmpty) return;
    final val = c.parameterValue ?? 0.0;
    final rawId0 = c.entityIds[0];
    final baseId0 = rawId0.split(':').first;
    final subKey0 = rawId0.contains(':') ? rawId0.split(':').last : null;
    final e1 = plane.primitives.where((p) => p.id == baseId0).firstOrNull;
    if (e1 == null) return;

    final String formattedVal = _formatConstraintText(c, val);

    // 1. TWO-ENTITY DIMENSIONS (Angle 27° or Distance 60 / 65 / 10)
    if (c.entityIds.length >= 2) {
      final baseId1 = c.entityIds[1].split(':').first;
      final e2 = plane.primitives.where((p) => p.id == baseId1).firstOrNull;
      if (e2 == null) return;

      if (c.type == CadConstraintType.angle && e1 is CADLineEntity && e2 is CADLineEntity) {
        _drawAngularCadDimension(
          canvas: canvas,
          l1: e1,
          l2: e2,
          toScreen: toScreen,
          label: '$formattedVal°',
          hitInfo: SketchDimensionTagHit(
            tagKey: c.id,
            screenRect: Rect.zero,
            primaryEntityId: e1.id,
            secondaryEntityId: e2.id,
            constraintType: CadConstraintType.angle,
            existingConstraintId: c.id,
            currentValue: val,
            unitSuffix: 'deg',
          ),
        );
        return;
      }

      // Linear distance between two entities
      Offset pA;
      Offset pB;
      if (e1 is CADLineEntity && e2 is! CADLineEntity) {
        final anchor2 = _getEntityCenter(e2);
        pA = toScreen(_projectPointToInfiniteLine(anchor2, e1.start, e1.end));
        pB = toScreen(anchor2);
      } else if (e2 is CADLineEntity && e1 is! CADLineEntity) {
        final anchor1 = _getEntityCenter(e1);
        pA = toScreen(anchor1);
        pB = toScreen(_projectPointToInfiniteLine(anchor1, e2.start, e2.end));
      } else if (e1 is CADLineEntity && e2 is CADLineEntity) {
        final mid1 = (e1.start + e1.end) * 0.5;
        pA = toScreen(mid1);
        pB = toScreen(_projectPointToInfiniteLine(mid1, e2.start, e2.end));
      } else {
        pA = toScreen(_getEntityCenter(e1));
        pB = toScreen(_getEntityCenter(e2));
      }

      if (pA != Offset.zero && pB != Offset.zero) {
        _drawLinearCadDimension(
          canvas: canvas,
          pA: pA,
          pB: pB,
          offsetPx: c.labelOffset * 1.4,
          label: formattedVal,
          isDriving: true,
          hitInfo: SketchDimensionTagHit(
            tagKey: c.id,
            screenRect: Rect.zero,
            primaryEntityId: e1.id,
            secondaryEntityId: e2.id,
            constraintType: CadConstraintType.distance,
            existingConstraintId: c.id,
            currentValue: val,
          ),
        );
      }
      return;
    }

    // 2. SINGLE-ENTITY DRIVING DIMENSIONS
    if (c.type == CadConstraintType.diameter && e1 is CADCircleEntity) {
      final cScr = toScreen(e1.center);
      const double leaderAng = -math.pi / 4.0;
      final rScr = toScreen(Offset(
        e1.center.dx + e1.radius * math.cos(leaderAng),
        e1.center.dy + e1.radius * math.sin(leaderAng),
      ));
      if (cScr != Offset.zero && rScr != Offset.zero) {
        _drawRadialOrDiameterLeaderDimension(
          canvas: canvas,
          centerScr: cScr,
          rimScr: rScr,
          label: 'Ø$formattedVal',
          isDriving: true,
          hitInfo: SketchDimensionTagHit(
            tagKey: c.id,
            screenRect: Rect.zero,
            primaryEntityId: e1.id,
            constraintType: CadConstraintType.diameter,
            existingConstraintId: c.id,
            currentValue: val,
          ),
        );
      }
    } else if (c.type == CadConstraintType.radius) {
      Offset cScr = Offset.zero;
      Offset rScr = Offset.zero;
      if (e1 is CADCircleEntity) {
        cScr = toScreen(e1.center);
        rScr = toScreen(Offset(e1.center.dx + e1.radius * 0.707, e1.center.dy - e1.radius * 0.707));
      } else if (e1 is CADArcEntity) {
        final g = e1.computeCircumcircle();
        if (g != null) {
          cScr = toScreen(g.center);
          rScr = toScreen(e1.pointOnArc);
        }
      } else if (e1 is CADCenterPointArcEntity) {
        cScr = toScreen(e1.center);
        rScr = toScreen(e1.startPoint);
      }
      if (cScr != Offset.zero && rScr != Offset.zero) {
        _drawRadialOrDiameterLeaderDimension(
          canvas: canvas,
          centerScr: cScr,
          rimScr: rScr,
          label: 'R$formattedVal',
          isDriving: true,
          hitInfo: SketchDimensionTagHit(
            tagKey: c.id,
            screenRect: Rect.zero,
            primaryEntityId: e1.id,
            constraintType: CadConstraintType.radius,
            existingConstraintId: c.id,
            currentValue: val,
          ),
        );
      }
    } else if (c.type == CadConstraintType.distance) {
      if (e1 is CADLineEntity) {
        final pA = toScreen(e1.start);
        final pB = toScreen(e1.end);
        if (pA != Offset.zero && pB != Offset.zero) {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: pA,
            pB: pB,
            offsetPx: -c.labelOffset.abs() * 1.5,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
            ),
          );
        }
      } else if (e1 is CADRectangleEntity) {
        final p1 = toScreen(e1.startPoint);
        final p2 = toScreen(Offset(e1.startPoint.dx + e1.width, e1.startPoint.dy));
        final p3 = toScreen(Offset(e1.startPoint.dx + e1.width, e1.startPoint.dy + e1.height));
        if (subKey0 == 'h') {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p2,
            pB: p3,
            offsetPx: 28.0,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
              subKey: 'h',
            ),
          );
        } else {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p1,
            pB: p2,
            offsetPx: -26.0,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
              subKey: 'w',
            ),
          );
        }
      } else if (e1 is CADCenterRectangleEntity) {
        final p1 = toScreen(e1.topLeft);
        final p2 = toScreen(e1.topRight);
        final p3 = toScreen(e1.bottomRight);
        if (subKey0 == 'h') {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p2,
            pB: p3,
            offsetPx: 28.0,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
              subKey: 'h',
            ),
          );
        } else {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p1,
            pB: p2,
            offsetPx: -26.0,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
              subKey: 'w',
            ),
          );
        }
      }
    }
  }

  /// Draws an authentic Onshape Linear Dimension with witness/extension lines,
  /// filled CAD arrowheads, and a clickable central dimension tag (matching image_31d02d.png).
  void _drawLinearCadDimension({
    required Canvas canvas,
    required Offset pA,
    required Offset pB,
    required double offsetPx,
    required String label,
    required bool isDriving,
    SketchDimensionTagHit? hitInfo,
  }) {
    final seg = pB - pA;
    final len = seg.distance;
    if (len < 6.0) return;

    final dir = seg / len;
    final sign = offsetPx >= 0 ? 1.0 : -1.0;
    final n = Offset(-dir.dy, dir.dx) * sign;
    final absOff = offsetPx.abs().clamp(16.0, 120.0);

    final dimA = pA + n * absOff;
    final dimB = pB + n * absOff;

    final dimColor = isDriving ? const Color(0xFF0F172A) : const Color(0xFF334155);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;

    // 1. Extension / witness lines (3px gap from entity vertex, 5px overshoot past dimension line)
    canvas.drawLine(pA + n * 3.0, dimA + n * 5.0, linePaint);
    canvas.drawLine(pB + n * 3.0, dimB + n * 5.0, linePaint);

    // 2. Dimension line + filled arrowheads at both ends
    canvas.drawLine(dimA, dimB, linePaint);
    _drawCadArrowhead(canvas, dimA, dir, dimColor);
    _drawCadArrowhead(canvas, dimB, -dir, dimColor);

    // 3. Clickable Dimension Value Tag centered on the dimension line
    final mid = (dimA + dimB) * 0.5;
    _drawClickableDimensionTag(canvas, mid, label, isDriving: isDriving, hitInfo: hitInfo);
  }

  /// Draws an Onshape Diameter (`Ø17`, `Ø33`) or Radius (`R3`, `R10`) leader dimension
  /// with an arrowhead on the perimeter and a horizontal shoulder leading to the tag.
  void _drawRadialOrDiameterLeaderDimension({
    required Canvas canvas,
    required Offset centerScr,
    required Offset rimScr,
    required String label,
    required bool isDriving,
    SketchDimensionTagHit? hitInfo,
  }) {
    final radial = rimScr - centerScr;
    final rLen = radial.distance;
    final unit = rLen > 1.0 ? radial / rLen : const Offset(0.707, -0.707);

    final elbow = rimScr + unit * 22.0;
    final shoulderDir = unit.dx >= 0 ? const Offset(14.0, 0.0) : const Offset(-14.0, 0.0);
    final tagAnchor = elbow + shoulderDir;

    final dimColor = isDriving ? const Color(0xFF0F172A) : const Color(0xFF334155);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;

    canvas.drawLine(rimScr, elbow, linePaint);
    canvas.drawLine(elbow, tagAnchor, linePaint);
    // Arrowhead pointing inward toward rimScr
    _drawCadArrowhead(canvas, rimScr, unit, dimColor);

    final tagCenter = tagAnchor + Offset(unit.dx >= 0 ? 22.0 : -22.0, 0.0);
    _drawClickableDimensionTag(canvas, tagCenter, label, isDriving: isDriving, hitInfo: hitInfo);
  }

  /// Draws an Onshape Angular Dimension (`27°` in image_31d02d.png) with a curved arc and arrowheads.
  void _drawAngularCadDimension({
    required Canvas canvas,
    required CADLineEntity l1,
    required CADLineEntity l2,
    required Offset Function(Offset) toScreen,
    required String label,
    SketchDimensionTagHit? hitInfo,
  }) {
    final s1 = toScreen(l1.start);
    final e1 = toScreen(l1.end);
    final s2 = toScreen(l2.start);
    final e2 = toScreen(l2.end);
    if (s1 == Offset.zero || e1 == Offset.zero || s2 == Offset.zero || e2 == Offset.zero) return;

    final vertex = _lineLineIntersectionScreen(s1, e1, s2, e2) ?? s1;
    final v1 = (e1 - vertex).distance > (s1 - vertex).distance ? (e1 - vertex) : (s1 - vertex);
    final v2 = (e2 - vertex).distance > (s2 - vertex).distance ? (e2 - vertex) : (s2 - vertex);
    if (v1.distance < 4.0 || v2.distance < 4.0) return;

    final a1 = math.atan2(v1.dy, v1.dx);
    final a2 = math.atan2(v2.dy, v2.dx);
    double sweep = a2 - a1;
    while (sweep <= -math.pi) sweep += 2.0 * math.pi;
    while (sweep > math.pi) sweep -= 2.0 * math.pi;

    const double arcR = 38.0;
    final arcRect = Rect.fromCircle(center: vertex, radius: arcR);
    final dimColor = const Color(0xFF0F172A);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;

    canvas.drawArc(arcRect, a1, sweep, false, linePaint);

    final pArcStart = vertex + Offset(math.cos(a1), math.sin(a1)) * arcR;
    final pArcEnd = vertex + Offset(math.cos(a1 + sweep), math.sin(a1 + sweep)) * arcR;
    final tStart = Offset(-math.sin(a1), math.cos(a1)) * (sweep >= 0 ? 1.0 : -1.0);
    final tEnd = Offset(-math.sin(a1 + sweep), math.cos(a1 + sweep)) * (sweep >= 0 ? -1.0 : 1.0);
    _drawCadArrowhead(canvas, pArcStart, tStart, dimColor);
    _drawCadArrowhead(canvas, pArcEnd, tEnd, dimColor);

    final midAngle = a1 + sweep * 0.5;
    final tagCenter = vertex + Offset(math.cos(midAngle), math.sin(midAngle)) * arcR;
    _drawClickableDimensionTag(canvas, tagCenter, label, isDriving: true, hitInfo: hitInfo);
  }

  void _drawCadArrowhead(Canvas canvas, Offset tip, Offset inwardDir, Color color) {
    final len = inwardDir.distance;
    if (len < 1e-4) return;
    final u = inwardDir / len;
    final n = Offset(-u.dy, u.dx);
    const double arrowLen = 7.5;
    const double arrowHalfW = 2.6;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + u.dx * arrowLen + n.dx * arrowHalfW, tip.dy + u.dy * arrowLen + n.dy * arrowHalfW)
      ..lineTo(tip.dx + u.dx * arrowLen - n.dx * arrowHalfW, tip.dy + u.dy * arrowLen - n.dy * arrowHalfW)
      ..close();

    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  void _drawClickableDimensionTag(
    Canvas canvas,
    Offset center,
    String text, {
    required bool isDriving,
    SketchDimensionTagHit? hitInfo,
  }) {
    if (center == Offset.zero) return;
    final isBeingEdited = hitInfo != null &&
        viewModel.activeEditingDimensionTagKey == hitInfo.tagKey;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isDriving ? const Color(0xFF0F172A) : const Color(0xFF475569),
          fontSize: 11.5,
          fontWeight: isDriving ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 12.0,
      height: tp.height + 6.0,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3.5));

    // White background pill breaks the dimension line cleanly around the text (image_31d02d.png)
    canvas.drawRRect(
      rrect,
      Paint()..color = isBeingEdited ? const Color(0xFFE0F2FE) : const Color(0xF5FFFFFF),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = isBeingEdited
            ? const Color(0xFF0284C7)
            : isDriving
                ? const Color(0xFF94A3B8)
                : const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isBeingEdited ? 1.5 : 0.9,
    );

    tp.paint(canvas, Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0));

    if (hitInfo != null) {
      viewModel.sketchDimensionHitRects.add(SketchDimensionTagHit(
        tagKey: hitInfo.tagKey,
        screenRect: rect.inflate(5.0),
        primaryEntityId: hitInfo.primaryEntityId,
        secondaryEntityId: hitInfo.secondaryEntityId,
        constraintType: hitInfo.constraintType,
        existingConstraintId: hitInfo.existingConstraintId,
        currentValue: hitInfo.currentValue,
        unitSuffix: hitInfo.unitSuffix,
        subKey: hitInfo.subKey,
      ));
    }
  }

  void _drawVertexDot(Canvas canvas, Offset pt, Color color, {required bool isSel}) {
    if (pt == Offset.zero) return;
    canvas.drawCircle(pt, isSel ? 4.2 : 3.2, Paint()..color = Colors.white);
    canvas.drawCircle(
      pt,
      isSel ? 4.2 : 3.2,
      Paint()
        ..color = isSel ? const Color(0xFFF59E0B) : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  String _formatDimValue(double v) {
    return (v - v.roundToDouble()).abs() < 0.05
        ? v.round().toString()
        : v.toStringAsFixed(1);
  }

  String _formatConstraintText(CadConstraint c, double val) {
    final base = _formatDimValue(val);
    final tol = (c.tolerancePlus != null && c.tolerancePlus! > 0)
        ? ' ±${_formatDimValue(c.tolerancePlus!)}'
        : '';
    if (viewModel.showSketchExpressions && c.expression != null && c.expression!.isNotEmpty) {
      return '${c.expression} = $base$tol';
    }
    return '$base$tol';
  }

  Offset _getEntityCenter(CADPrimitiveEntity e) {
    if (e is CADCircleEntity) return e.center;
    if (e is CADPointEntity) return e.position;
    if (e is CADCenterRectangleEntity) return e.center;
    if (e is CADRectangleEntity) {
      return Offset(e.startPoint.dx + e.width * 0.5, e.startPoint.dy + e.height * 0.5);
    }
    if (e is CADLineEntity) return (e.start + e.end) * 0.5;
    if (e is CADArcEntity) return e.computeCircumcircle()?.center ?? e.pointOnArc;
    return Offset.zero;
  }

  static Offset _projectPointToInfiniteLine(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return a;
    final t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    return a + ab * t;
  }

  static Offset? _lineLineIntersectionScreen(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d = (p1.dx - p2.dx) * (p3.dy - p4.dy) - (p1.dy - p2.dy) * (p3.dx - p4.dx);
    if (d.abs() < 1e-5) return null;
    final pre = p1.dx * p2.dy - p1.dy * p2.dx;
    final post = p3.dx * p4.dy - p3.dy * p4.dx;
    final x = (pre * (p3.dx - p4.dx) - (p1.dx - p2.dx) * post) / d;
    final y = (pre * (p3.dy - p4.dy) - (p1.dy - p2.dy) * post) / d;
    return Offset(x, y);
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
          color: isHighlighted ? const Color(0xFFB45309) : const Color(0xFF0F172A),
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

    canvas.drawRRect(badgeRect, Paint()..color = isHighlighted ? const Color(0xFFFEF3C7) : const Color(0xFFE2E8F0));
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = isHighlighted ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
    tp.paint(canvas, pos + Offset(-tp.width / 2, -10 - tp.height / 2));
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

  /// Draws Onshape long-short-long centerline construction dashing (`─── ╌ ───`)
  void _drawCenterlineDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dist = (p2 - p1).distance;
    if (dist < 1.0) return;
    final dir = (p2 - p1) / dist;
    double walked = 0.0;
    bool longDash = true;
    while (walked < dist) {
      final segLen = longDash ? 10.0 : 3.5;
      final start = p1 + dir * walked;
      final end = p1 + dir * math.min(walked + segLen, dist);
      canvas.drawLine(start, end, paint);
      walked += segLen + 3.5;
      longDash = !longDash;
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      double dist = 0.0;
      while (dist < metric.length) {
        final extract = metric.extractPath(dist, math.min(dist + 6.0, metric.length));
        canvas.drawPath(extract, paint);
        dist += 10.0;
      }
    }
  }

  void _drawCenterlineDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      double dist = 0.0;
      bool longDash = true;
      while (dist < metric.length) {
        final segLen = longDash ? 10.0 : 3.5;
        final extract = metric.extractPath(dist, math.min(dist + segLen, metric.length));
        canvas.drawPath(extract, paint);
        dist += segLen + 3.5;
        longDash = !longDash;
      }
    }
  }

  @override
  bool shouldRepaint(covariant Assembly3DSurfaceSketchPainter oldDelegate) => true;
}
