import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../../engine/sketch/assembly_surface_sketch_engine.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Renders real-time 3D parametric sketch geometry and Onshape SS4 CAD Engineering Dimensions
/// (witness/extension lines, sharp filled arrowheads, radial/diametric leaders, angular arcs,
/// yellow-orange hover highlighting, hit-testable constraint badges, and borderless inline dimension tags).
class Assembly3DSurfaceSketchPainter extends CustomPainter {
  final AssemblyStudioViewModel viewModel;
  final Offset Function(CadPoint3D) projectPoint;

  Assembly3DSurfaceSketchPainter({required this.viewModel, required this.projectPoint});

  @override
  void paint(Canvas canvas, Size size) {
    final plane = viewModel.activeSketchPlane;
    if (plane == null) return;

    viewModel.sketchDimensionHitRects.clear();
    viewModel.sketchConstraintHitRects.clear();

    final xAx = plane.xAxis;
    final yAx = plane.yAxis;
    final origin = plane.origin;

    Offset toScreen(Offset local) {
      final w = origin + (xAx * local.dx) + (yAx * local.dy);
      return projectPoint(CadPoint3D(w.x, w.y, w.z));
    }

    // 1. Optional Plane Grid Overlay (off by default in Onshape SS4; toggleable in Sketch Palette)
    if (viewModel.showSketchGrid) {
      final gridPaint = Paint()
        ..color = const Color(0x1C0284C7)
        ..strokeWidth = 0.7;

      const double extent = 140.0;
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

    // Sketch Origin Point (Sleek Onshape dark origin crosshair + point)
    final scrOrigin = toScreen(Offset.zero);
    if (scrOrigin != Offset.zero) {
      final originPaint = Paint()
        ..color = const Color(0xFF334155).withValues(alpha: 0.75)
        ..strokeWidth = 1.2;
      canvas.drawLine(scrOrigin - const Offset(6, 0), scrOrigin + const Offset(6, 0), originPaint);
      canvas.drawLine(scrOrigin - const Offset(0, 6), scrOrigin + const Offset(0, 6), originPaint);
      canvas.drawCircle(
        scrOrigin,
        3.2,
        Paint()
          ..color = const Color(0xFF0F172A)
          ..style = PaintingStyle.fill,
      );
    }

    // 2. Interior Shaded Closed Profiles (Onshape SS4 cool translucent slate-gray region fill)
    final validation = viewModel.activeSketchValidation;
    if (viewModel.showSketchProfileShading && validation != null && validation.isValidClosedLoop) {
      final loopsToFill = validation.allClosedLoops.isNotEmpty
          ? validation.allClosedLoops
          : (validation.orderedPathVertices.length >= 3 ? [validation.orderedPathVertices] : <List<Offset>>[]);

      final isTreeHighlighted = viewModel.highlightedFeatureId == plane.id;
      final isExtrudeHighlight = viewModel.isExtrudeMode;
      final fillPaint = Paint()
        ..color = isTreeHighlighted
            ? const Color(0x38FFB74D) // Onshape amber fill when highlighted from feature tree
            : isExtrudeHighlight
            ? const Color(0x40F59E0B)
            : const Color(0x3890A4AE) // Authentic Onshape cool slate translucent fill (SS4)
        ..style = PaintingStyle.fill;

      final combinedRegionPath = Path()..fillType = PathFillType.evenOdd;
      bool hasAnyLoop = false;
      for (final loop in loopsToFill) {
        if (loop.length < 3) continue;
        final subPath = Path();
        bool first = true;
        for (final pt in loop) {
          final scr = toScreen(pt);
          if (scr == Offset.zero) continue;
          if (first) {
            subPath.moveTo(scr.dx, scr.dy);
            first = false;
          } else {
            subPath.lineTo(scr.dx, scr.dy);
          }
        }
        if (!first) {
          subPath.close();
          combinedRegionPath.addPath(subPath, Offset.zero);
          hasAnyLoop = true;
        }
      }
      if (hasAnyLoop) {
        canvas.drawPath(combinedRegionPath, fillPaint);
        if (isTreeHighlighted || isExtrudeHighlight) {
          canvas.drawPath(
            combinedRegionPath,
            Paint()
              ..color = const Color(0xFFFF9800)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4,
          );
        }
      }
    }

    // Track which entities already have an explicit driving dimensional constraint
    final entitiesWithDrivingDim = <String>{};
    for (final c in plane.constraints) {
      if (c.isActive && c.isDimensional) {
        for (final eid in c.entityIds) {
          entitiesWithDrivingDim.add(eid.split(':').first);
        }
      }
    }

    // 3. Render Primitive Entities & Onshape SS4 CAD Dimensions
    for (final prim in plane.primitives) {
      final isSel =
          (prim.id == viewModel.selectedSketchEntity?.id) ||
          viewModel.selectedSketchEntityIds.contains(prim.id) ||
          (prim.id == viewModel.constraintFirstEntityId) ||
          (prim.id == viewModel.dimensionFirstEntityId);
      final isHovered = prim.id == viewModel.hoveredSketchEntityId;
      final isConstrained = prim.isFullyConstrained;
      final isOverConstrained = viewModel.lastConstraintSolverResult?.conflictingConstraints.any((c) => c.entityIds.contains(prim.id)) ?? false;

      // Onshape SS4 Color System:
      // - Hovered or Selected (especially in Constraint/Dimension mode): Warm Yellow/Orange (#F59E0B)
      // - Conflicting / Over-Constrained: Red (#EF4444)
      // - Fully Defined: Crisp Black (#0F172A)
      // - Under-Defined: Onshape Blue (#0284C7)
      final isTreeHighlighted = viewModel.highlightedFeatureId == plane.id;

      // Onshape Master Color System:
      // - Constrained / Defined: const Color(0xFF111111) (1.65px crisp black)
      // - Under-Constrained: const Color(0xFF1565C0) (1.65px deep Onshape blue)
      // - Construction Geometry: const Color(0xFF546E7A) (1.3px dashed)
      // - Imprinted Host Part Borders: const Color(0xFF263238) (1.2px solid)
      // - Hovered / Selected or Tree-Highlighted: const Color(0xFFFF9800) (2.4px amber/orange)
      final Color entityColor = isOverConstrained
          ? const Color(0xFFEF4444)
          : (isHovered || isSel || isTreeHighlighted)
          ? const Color(0xFFFF9800)
          : prim.isImprintedReference
          ? const Color(0xFF263238)
          : prim.isConstruction
          ? const Color(0xFF546E7A)
          : prim.isProjected
          ? const Color(0xFF7C3AED)
          : isConstrained
          ? const Color(0xFF111111)
          : const Color(0xFF1565C0);

      final strokePaint = Paint()
        ..color = entityColor
        ..strokeWidth = (isHovered || isSel || isTreeHighlighted)
            ? 2.4
            : prim.isImprintedReference
            ? 1.2
            : (prim.isConstruction ? 1.3 : 1.65)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      // Soft yellow glow behind hovered or constraint-picked entities (matches SS4 yellow line!)
      final Paint? glowPaint = (isHovered || isSel)
          ? (Paint()
              ..color = const Color(0x48F59E0B)
              ..strokeWidth = 6.0
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round)
          : null;

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

          if (glowPaint != null) canvas.drawPath(rectPath, glowPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, rectPath, strokePaint);
          } else {
            canvas.drawPath(rectPath, strokePaint);
          }

          if (isSel || isHovered) {
            _drawVertexDot(canvas, p1, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, p2, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, p3, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, p4, entityColor, isHighlighted: true);
          }

          if ((viewModel.showSketchDimensions || isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p1,
              pB: p2,
              offsetPx: -28.0,
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
              offsetPx: 30.0,
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

          if (glowPaint != null) canvas.drawPath(rectPath, glowPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, rectPath, strokePaint);
          } else {
            canvas.drawPath(rectPath, strokePaint);
          }

          if (prim.hasDiagonalConstruction || isSel) {
            final diagPaint = Paint()
              ..color = const Color(0xFF64748B).withValues(alpha: 0.65)
              ..strokeWidth = 1.0;
            _drawDashedLine(canvas, p1, p3, diagPaint);
            _drawDashedLine(canvas, p4, p2, diagPaint);
          }

          if (isSel || isHovered) {
            _drawVertexDot(canvas, cScr, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, p1, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, p2, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, p3, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, p4, entityColor, isHighlighted: true);
          }

          if ((viewModel.showSketchDimensions || isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p1,
              pB: p2,
              offsetPx: -28.0,
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
              offsetPx: 30.0,
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
            if (glowPaint != null) canvas.drawLine(sScr, eScr, glowPaint);
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

          if (glowPaint != null) canvas.drawPath(arcPath, glowPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, arcPath, strokePaint);
          } else {
            canvas.drawPath(arcPath, strokePaint);
          }

          if (isSel || isHovered) {
            _drawVertexDot(canvas, sScr, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, eScr, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, cScr, entityColor, isHighlighted: true);
          }

          if ((viewModel.showSketchDimensions || isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
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
        const double leaderAngle = -math.pi * 0.72;
        final rimLocal = Offset(prim.center.dx + prim.radius * math.cos(leaderAngle), prim.center.dy + prim.radius * math.sin(leaderAngle));
        final rEdge = toScreen(rimLocal);

        if (cScr != Offset.zero) {
          final circlePath = Path();
          const int segs = 64;
          for (int i = 0; i <= segs; i++) {
            final theta = i * 2.0 * math.pi / segs;
            final ptLocal = Offset(prim.center.dx + prim.radius * math.cos(theta), prim.center.dy + prim.radius * math.sin(theta));
            final ptScr = toScreen(ptLocal);
            if (i == 0) {
              circlePath.moveTo(ptScr.dx, ptScr.dy);
            } else {
              circlePath.lineTo(ptScr.dx, ptScr.dy);
            }
          }
          circlePath.close();

          if (glowPaint != null) canvas.drawPath(circlePath, glowPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, circlePath, strokePaint);
          } else {
            canvas.drawPath(circlePath, strokePaint);
          }

          if (isSel || isHovered) {
            _drawVertexDot(canvas, cScr, entityColor, isHighlighted: true);
          }

          if ((viewModel.showSketchDimensions || isSel || viewModel.showSketchExpressions) &&
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
          if (glowPaint != null) canvas.drawLine(sScr, eScr, glowPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedLine(canvas, sScr, eScr, strokePaint);
          } else {
            canvas.drawLine(sScr, eScr, strokePaint);
          }
          if (isSel || isHovered) {
            _drawVertexDot(canvas, sScr, entityColor, isHighlighted: true);
            _drawVertexDot(canvas, eScr, entityColor, isHighlighted: true);
          }

          if ((viewModel.showSketchDimensions || isSel || viewModel.showSketchExpressions) &&
              !prim.isConstruction &&
              !entitiesWithDrivingDim.contains(prim.id)) {
            final len = (prim.end - prim.start).distance;
            _drawLinearCadDimension(
              canvas: canvas,
              pA: sScr,
              pB: eScr,
              offsetPx: -28.0,
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
          if (glowPaint != null) canvas.drawPath(polyPath, glowPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, polyPath, strokePaint);
          } else {
            canvas.drawPath(polyPath, strokePaint);
          }
          if (isSel || isHovered) {
            for (final pt in prim.points) {
              _drawVertexDot(canvas, toScreen(pt), entityColor, isHighlighted: true);
            }
          }
        }
      } else if (prim is CADPointEntity) {
        final ptScr = toScreen(prim.position);
        if (ptScr != Offset.zero) {
          _drawVertexDot(canvas, ptScr, entityColor, isHighlighted: isSel || isHovered);
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
          if (glowPaint != null) canvas.drawPath(path, glowPaint);
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
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke,
          );
          if (isSel || isHovered) {
            _drawVertexDot(canvas, toScreen(prim.center), entityColor, isHighlighted: true);
          }
        }
      }
    }

    // 4. Render All Explicit Driving Dimensional Constraints (Onshape SS4 style)
    for (final c in plane.constraints) {
      if (!c.isActive || !c.isDimensional) continue;
      _drawDrivingDimensionConstraint(canvas, plane, c, toScreen);
    }

    // 5. Render Clickable Geometric Constraint Glyphs (H, V, ⊥, //, ◎, ⌒, =, ⇋)
    if (viewModel.showSketchConstraints && plane.constraints.isNotEmpty) {
      final Map<String, int> entityBadgeSlot = {};
      for (final constraint in plane.constraints) {
        if (!constraint.isActive || constraint.isDimensional) continue;
        final isConstraintSelected = (viewModel.selectedSketchConstraint?.id == constraint.id);
        final isConstraintHovered = (viewModel.hoveredSketchConstraintId == constraint.id);
        final isOwnerSelectedOrHovered = constraint.entityIds.any(
          (id) => viewModel.selectedSketchEntityIds.contains(id) || viewModel.selectedSketchEntity?.id == id || viewModel.hoveredSketchEntityId == id,
        );

        Offset? badgePos;
        if (constraint.entityIds.isNotEmpty) {
          final firstId = constraint.entityIds[0].split(':').first;
          final firstEnt = plane.primitives.where((p) => p.id == firstId).firstOrNull;
          if (firstEnt != null) {
            final slot = entityBadgeSlot[firstId] ?? 0;
            entityBadgeSlot[firstId] = slot + 1;
            badgePos = toScreen(_getEntityBadgeAnchor(firstEnt)) + Offset(slot * 20.0, 0.0);
          }
        }

        if (badgePos != null && badgePos != Offset.zero) {
          final rect = _drawConstraintBadge(
            canvas,
            badgePos,
            constraint.symbol,
            isSelected: isConstraintSelected,
            isHovered: isConstraintHovered || isOwnerSelectedOrHovered,
          );
          viewModel.sketchConstraintHitRects.add(SketchConstraintBadgeHit(constraintId: constraint.id, screenRect: rect.inflate(4.0)));
        }
      }
    }

    // 6. Sleek Point-to-Point Onshape Inference Guides (Only between reference key point & cursor!)
    final hoverLocal = viewModel.activePlaneHoverLocal;
    if (hoverLocal != null && viewModel.currentInferenceGuides.isNotEmpty) {
      final inferPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 1.15
        ..style = PaintingStyle.stroke;

      final hScr = toScreen(hoverLocal);
      for (final match in viewModel.currentInferenceGuides) {
        final refScr = toScreen(match.refVertex);
        if (refScr != Offset.zero && hScr != Offset.zero && (refScr - hScr).distance > 4.0) {
          _drawDashedLine(canvas, refScr, hScr, inferPaint);
          canvas.drawCircle(
            refScr,
            3.5,
            Paint()
              ..color = const Color(0xFFF59E0B)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }

    // 7. Live Interactive Sketch Rubber-Band Preview
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
          const int segs = 56;
          for (int i = 0; i <= segs; i++) {
            final theta = i * 2.0 * math.pi / segs;
            final ptLocal = Offset(pStart.dx + rLocal * math.cos(theta), pStart.dy + rLocal * math.sin(theta));
            final ptScr = toScreen(ptLocal);
            if (i == 0) {
              circlePath.moveTo(ptScr.dx, ptScr.dy);
            } else {
              circlePath.lineTo(ptScr.dx, ptScr.dy);
            }
          }
          circlePath.close();
          _drawDashedPath(canvas, circlePath, previewPaint);
          _drawRadialOrDiameterLeaderDimension(canvas: canvas, centerScr: sScr, rimScr: hScr, label: 'Ø${_formatDimValue(rLocal * 2.0)}', isDriving: false);
        } else if (tool == 'line' || tool == 'midpoint_line') {
          _drawDashedLine(canvas, sScr, hScr, previewPaint);
          _drawVertexDot(canvas, sScr, const Color(0xFF0284C7), isHighlighted: true);
          final len = (hoverLocal - pStart).distance;
          _drawLinearCadDimension(canvas: canvas, pA: sScr, pB: hScr, offsetPx: -24.0, label: _formatDimValue(len), isDriving: false);

          final dx = (hoverLocal.dx - pStart.dx).abs();
          final dy = (hoverLocal.dy - pStart.dy).abs();
          if (len > 3.0) {
            if (dy < dx * 0.06) {
              _drawConstraintBadge(canvas, Offset((sScr.dx + hScr.dx) / 2, (sScr.dy + hScr.dy) / 2 + 18), 'H', isSelected: false, isHovered: true);
            } else if (dx < dy * 0.06) {
              _drawConstraintBadge(canvas, Offset((sScr.dx + hScr.dx) / 2 + 18, (sScr.dy + hScr.dy) / 2), 'V', isSelected: false, isHovered: true);
            }
          }
        }
      }
    }
  }

  /// Renders an explicit driving `CadConstraint` dimension (`distance`, `diameter`, `radius`, `angle`)
  /// using authentic Onshape SS4 extension lines, sharp arrowheads, leader lines, or angular arcs.
  void _drawDrivingDimensionConstraint(Canvas canvas, CADSketchPlane plane, CadConstraint c, Offset Function(Offset) toScreen) {
    if (c.entityIds.isEmpty) return;
    final val = c.parameterValue ?? 0.0;
    final rawId0 = c.entityIds[0];
    final baseId0 = rawId0.split(':').first;
    final subKey0 = rawId0.contains(':') ? rawId0.split(':').last : null;
    final e1 = plane.primitives.where((p) => p.id == baseId0).firstOrNull;
    if (e1 == null) return;

    final String formattedVal = _formatConstraintText(c, val);

    // 1. TWO-ENTITY DIMENSIONS (Angle 27° or Distance 60 / 65 / 99)
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
          isDriving: c.isDriving,
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

      Offset pALocal;
      Offset pBLocal;
      if (e1 is CADLineEntity && e2 is! CADLineEntity) {
        final anchor2 = _getEntityCenter(e2);
        pALocal = _projectPointToInfiniteLine(anchor2, e1.start, e1.end);
        pBLocal = anchor2;
      } else if (e2 is CADLineEntity && e1 is! CADLineEntity) {
        final anchor1 = _getEntityCenter(e1);
        pALocal = anchor1;
        pBLocal = _projectPointToInfiniteLine(anchor1, e2.start, e2.end);
      } else if (e1 is CADLineEntity && e2 is CADLineEntity) {
        final mid1 = (e1.start + e1.end) * 0.5;
        pALocal = mid1;
        pBLocal = _projectPointToInfiniteLine(mid1, e2.start, e2.end);
      } else {
        pALocal = _getEntityCenter(e1);
        pBLocal = _getEntityCenter(e2);
      }

      final pA = toScreen(pALocal);
      final pB = toScreen(pBLocal);

      if (pA != Offset.zero && pB != Offset.zero) {
        _drawLinearCadDimension(
          canvas: canvas,
          pA: pA,
          pB: pB,
          localA: pALocal,
          localB: pBLocal,
          toScreen: toScreen,
          offsetPx: c.labelOffset * 1.5,
          label: formattedVal,
          isDriving: c.isDriving,
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
      const double leaderAng = -math.pi * 0.72;
      final rScr = toScreen(Offset(e1.center.dx + e1.radius * math.cos(leaderAng), e1.center.dy + e1.radius * math.sin(leaderAng)));
      if (cScr != Offset.zero && rScr != Offset.zero) {
        _drawRadialOrDiameterLeaderDimension(
          canvas: canvas,
          centerScr: cScr,
          rimScr: rScr,
          label: 'Ø$formattedVal',
          isDriving: c.isDriving,
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
            localA: e1.start,
            localB: e1.end,
            toScreen: toScreen,
            offsetPx: -c.labelOffset.abs() * 1.5,
            label: formattedVal,
            isDriving: c.isDriving,
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
        final p2Local = Offset(e1.startPoint.dx + e1.width, e1.startPoint.dy);
        final p3Local = Offset(e1.startPoint.dx + e1.width, e1.startPoint.dy + e1.height);
        final p2 = toScreen(p2Local);
        final p3 = toScreen(p3Local);
        if (subKey0 == 'h') {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p2,
            pB: p3,
            localA: p2Local,
            localB: p3Local,
            toScreen: toScreen,
            offsetPx: 30.0,
            label: formattedVal,
            isDriving: c.isDriving,
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
            localA: e1.startPoint,
            localB: p2Local,
            toScreen: toScreen,
            offsetPx: -28.0,
            label: formattedVal,
            isDriving: c.isDriving,
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
            localA: e1.topRight,
            localB: e1.bottomRight,
            toScreen: toScreen,
            offsetPx: 30.0,
            label: formattedVal,
            isDriving: c.isDriving,
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
            localA: e1.topLeft,
            localB: e1.topRight,
            toScreen: toScreen,
            offsetPx: -28.0,
            label: formattedVal,
            isDriving: c.isDriving,
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

  /// Draws an authentic Onshape SS4 Linear Dimension (`60`, `99`, `65`, `90`):
  /// - Crisp 1.0px dark witness/extension lines
  /// - Split dimension line with a clean center break for the text (no clunky box border!)
  /// - Sharp filled CAD arrowheads
  /// Draws an authentic Onshape SS4 Linear Dimension (`60`, `99`, `65`, `90`):
  /// - Strictly orthogonal witness/extension lines in 2D sketch plane coordinates
  /// - Split dimension line with a clean center break for the text
  /// - Sharp filled CAD arrowheads
  void _drawLinearCadDimension({
    required Canvas canvas,
    required Offset pA,
    required Offset pB,
    Offset? localA,
    Offset? localB,
    Offset Function(Offset)? toScreen,
    required double offsetPx,
    required String label,
    required bool isDriving,
    SketchDimensionTagHit? hitInfo,
  }) {
    final dimColor = !isDriving ? const Color(0xFF8C96A0) : const Color(0xFF1E293B);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    Offset dimA;
    Offset dimB;
    Offset w1End;
    Offset w2End;
    Offset a1Scr = pA;
    Offset a2Scr = pB;
    Offset dir;
    Offset mid;
    double len;

    if (localA != null && localB != null && toScreen != null) {
      final v1 = vm.Vector2(localA.dx, localA.dy);
      final v2 = vm.Vector2(localB.dx, localB.dy);
      SketchDimensionOrientation orient = SketchDimensionOrientation.aligned;
      if ((v1.y - v2.y).abs() < 1e-4) {
        orient = SketchDimensionOrientation.horizontal;
      } else if ((v1.x - v2.x).abs() < 1e-4) {
        orient = SketchDimensionOrientation.vertical;
      }
      final midLocal = (v1 + v2) * 0.5;
      final offsetMm = offsetPx / 3.0;
      final delta = v2 - v1;
      final vlen = delta.length;
      final vdir = vlen > 1e-5 ? delta / vlen : vm.Vector2(1.0, 0.0);
      final perp = vm.Vector2(-vdir.y, vdir.x);
      final labelPos2D = midLocal + perp * offsetMm;

      final res = computeOrthogonalDimension2D(
        p1: v1,
        p2: v2,
        labelPosition2D: labelPos2D,
        orientation: orient,
        witnessOvershootMm: 3.5,
      );

      dimA = toScreen(Offset(res.dimLineStart.x, res.dimLineStart.y));
      dimB = toScreen(Offset(res.dimLineEnd.x, res.dimLineEnd.y));
      a1Scr = toScreen(Offset(res.anchor1.x, res.anchor1.y));
      a2Scr = toScreen(Offset(res.anchor2.x, res.anchor2.y));
      w1End = toScreen(Offset(res.witness1End.x, res.witness1End.y));
      w2End = toScreen(Offset(res.witness2End.x, res.witness2End.y));

      final seg = dimB - dimA;
      len = seg.distance;
      dir = len > 1e-4 ? seg / len : const Offset(1, 0);
      mid = (dimA + dimB) * 0.5;
    } else {
      final seg = pB - pA;
      len = seg.distance;
      if (len < 6.0) return;

      dir = seg / len;
      final sign = offsetPx >= 0 ? 1.0 : -1.0;
      final n = Offset(-dir.dy, dir.dx) * sign;
      final absOff = offsetPx.abs().clamp(18.0, 130.0);

      dimA = pA + n * absOff;
      dimB = pB + n * absOff;
      mid = (dimA + dimB) * 0.5;
      w1End = dimA + n * 6.0;
      w2End = dimB + n * 6.0;
      a1Scr = pA + n * 3.0;
      a2Scr = pB + n * 3.0;
    }

    if (len < 6.0) return;

    // 1. Extension / witness lines (strictly orthogonal in 2D sketch plane coordinates)
    canvas.drawLine(a1Scr, w1End, linePaint);
    canvas.drawLine(a2Scr, w2End, linePaint);

    // 2. Measure text width so the dimension line breaks cleanly around the number
    final tp = _layoutDimensionText(label, isDriving: isDriving, hitInfo: hitInfo);
    final halfGap = (tp.width * 0.5) + 5.5;
    double textAngle = math.atan2(dir.dy, dir.dx);
    if (textAngle > math.pi / 2.0) textAngle -= math.pi;
    if (textAngle <= -math.pi / 2.0) textAngle += math.pi;

    if (len > halfGap * 2.35) {
      canvas.drawLine(dimA, mid - dir * halfGap, linePaint);
      canvas.drawLine(mid + dir * halfGap, dimB, linePaint);
      // Standard inward-pointing arrowheads at both ends
      _drawCadArrowhead(canvas, dimA, dir, dimColor);
      _drawCadArrowhead(canvas, dimB, -dir, dimColor);
    } else {
      // Narrow dimension: outside extension tails + inward-pointing arrowheads
      canvas.drawLine(dimA - dir * 13.0, dimA, linePaint);
      canvas.drawLine(dimB, dimB + dir * 13.0, linePaint);
      _drawCadArrowhead(canvas, dimA, -dir, dimColor);
      _drawCadArrowhead(canvas, dimB, dir, dimColor);
    }

    // 4. Clickable Dimension Value Tag centered and rotated parallel to the dimension line
    _drawClickableDimensionTag(canvas, mid, tp, isDriving: isDriving, hitInfo: hitInfo, rotationRad: textAngle);
  }

  /// Draws an Onshape SS4 Diameter (`Ø17`, `Ø33`) or Radius (`R3`, `R10`) leader dimension.
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
    final unit = rLen > 1.0 ? radial / rLen : const Offset(-0.707, -0.707);

    final elbow = rimScr + unit * 24.0;
    final shoulderDir = unit.dx >= 0 ? const Offset(14.0, 0.0) : const Offset(-14.0, 0.0);
    final tagAnchor = elbow + shoulderDir;

    final dimColor = !isDriving ? const Color(0xFF8C96A0) : const Color(0xFF1E293B);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    canvas.drawLine(rimScr, elbow, linePaint);
    canvas.drawLine(elbow, tagAnchor, linePaint);
    // Sharp arrowhead pointing inward toward rimScr
    _drawCadArrowhead(canvas, rimScr, -unit, dimColor);

    final tp = _layoutDimensionText(label, isDriving: isDriving, hitInfo: hitInfo);
    final tagCenter = tagAnchor + Offset(unit.dx >= 0 ? (tp.width * 0.5 + 5.0) : -(tp.width * 0.5 + 5.0), 0.0);
    _drawClickableDimensionTag(canvas, tagCenter, tp, isDriving: isDriving, hitInfo: hitInfo);
  }

  /// Draws an Onshape SS4 Angular Dimension (`27°`) with a curved arc and sharp arrowheads.
  void _drawAngularCadDimension({
    required Canvas canvas,
    required CADLineEntity l1,
    required CADLineEntity l2,
    required Offset Function(Offset) toScreen,
    required String label,
    bool isDriving = true,
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
    while (sweep <= -math.pi) {
      sweep += 2.0 * math.pi;
    }
    while (sweep > math.pi) {
      sweep -= 2.0 * math.pi;
    }

    const double arcR = 42.0;
    final arcRect = Rect.fromCircle(center: vertex, radius: arcR);
    final dimColor = !isDriving ? const Color(0xFF8C96A0) : const Color(0xFF1E293B);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    canvas.drawArc(arcRect, a1, sweep, false, linePaint);

    final pArcStart = vertex + Offset(math.cos(a1), math.sin(a1)) * arcR;
    final pArcEnd = vertex + Offset(math.cos(a1 + sweep), math.sin(a1 + sweep)) * arcR;
    final tStart = Offset(-math.sin(a1), math.cos(a1)) * (sweep >= 0 ? 1.0 : -1.0);
    final tEnd = Offset(-math.sin(a1 + sweep), math.cos(a1 + sweep)) * (sweep >= 0 ? -1.0 : 1.0);
    _drawCadArrowhead(canvas, pArcStart, tStart, dimColor);
    _drawCadArrowhead(canvas, pArcEnd, tEnd, dimColor);

    final midAngle = a1 + sweep * 0.5;
    final tagCenter = vertex + Offset(math.cos(midAngle), math.sin(midAngle)) * arcR;
    final tp = _layoutDimensionText(label, isDriving: isDriving, hitInfo: hitInfo);
    _drawClickableDimensionTag(canvas, tagCenter, tp, isDriving: isDriving, hitInfo: hitInfo);
  }

  void _drawCadArrowhead(Canvas canvas, Offset tip, Offset inwardDir, Color color) {
    final len = inwardDir.distance;
    if (len < 1e-4) return;
    final u = inwardDir / len;
    final n = Offset(-u.dy, u.dx);
    const double arrowLen = 8.5;
    const double arrowHalfW = 2.3;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + u.dx * arrowLen + n.dx * arrowHalfW, tip.dy + u.dy * arrowLen + n.dy * arrowHalfW)
      ..lineTo(tip.dx + u.dx * arrowLen - n.dx * arrowHalfW, tip.dy + u.dy * arrowLen - n.dy * arrowHalfW)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  TextPainter _layoutDimensionText(String text, {required bool isDriving, SketchDimensionTagHit? hitInfo}) {
    final isBeingEdited = hitInfo != null && viewModel.activeEditingDimensionTagKey == hitInfo.tagKey;
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isBeingEdited
              ? const Color(0xFF0284C7)
              : !isDriving
              ? const Color(0xFF8C96A0) // Onshape Driven Grey (SS5)
              : const Color(0xFF0F172A),
          fontSize: 12.0,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          shadows: const [
            Shadow(color: Color(0xE6FFFFFF), blurRadius: 4.0),
            Shadow(color: Color(0xE6FFFFFF), blurRadius: 2.0),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Renders the Onshape SS4 borderless dimension text directly in the line break,
  /// only drawing a subtle highlight pill when actively edited or selected!
  void _drawClickableDimensionTag(
    Canvas canvas,
    Offset center,
    TextPainter tp, {
    required bool isDriving,
    SketchDimensionTagHit? hitInfo,
    double rotationRad = 0.0,
  }) {
    if (center == Offset.zero) return;
    final isBeingEdited = hitInfo != null && viewModel.activeEditingDimensionTagKey == hitInfo.tagKey;
    final isConstraintSelected = hitInfo?.existingConstraintId != null && viewModel.selectedSketchConstraint?.id == hitInfo!.existingConstraintId;

    final rect = Rect.fromCenter(center: center, width: tp.width + 10.0, height: tp.height + 6.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (rotationRad.abs() > 1e-3) {
      canvas.rotate(rotationRad);
    }
    final localRect = Rect.fromCenter(center: Offset.zero, width: tp.width + 8.0, height: tp.height + 4.0);
    if (isBeingEdited || isConstraintSelected) {
      final rrect = RRect.fromRectAndRadius(localRect, const Radius.circular(3.5));
      canvas.drawRRect(rrect, Paint()..color = isConstraintSelected ? const Color(0xFFFEF3C7) : const Color(0xFFE0F2FE));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isConstraintSelected ? const Color(0xFFF59E0B) : const Color(0xFF0284C7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }
    tp.paint(canvas, Offset(-tp.width / 2.0, -tp.height / 2.0));
    canvas.restore();

    if (hitInfo != null) {
      viewModel.sketchDimensionHitRects.add(
        SketchDimensionTagHit(
          tagKey: hitInfo.tagKey,
          screenRect: rect.inflate(6.0),
          primaryEntityId: hitInfo.primaryEntityId,
          secondaryEntityId: hitInfo.secondaryEntityId,
          constraintType: hitInfo.constraintType,
          existingConstraintId: hitInfo.existingConstraintId,
          currentValue: hitInfo.currentValue,
          unitSuffix: hitInfo.unitSuffix,
          subKey: hitInfo.subKey,
        ),
      );
    }
  }

  /// Draws authentic Onshape SS4 filled dark vertex dots (or glowing yellow/orange when hovered/selected).
  void _drawVertexDot(Canvas canvas, Offset pt, Color color, {required bool isHighlighted}) {
    if (pt == Offset.zero) return;
    if (isHighlighted) {
      canvas.drawCircle(pt, 5.2, Paint()..color = const Color(0x55F59E0B));
      canvas.drawCircle(pt, 3.6, Paint()..color = const Color(0xFFF59E0B));
      canvas.drawCircle(
        pt,
        3.6,
        Paint()
          ..color = const Color(0xFF0F172A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    } else {
      canvas.drawCircle(
        pt,
        2.9,
        Paint()
          ..color = const Color(0xFF0F172A)
          ..style = PaintingStyle.fill,
      );
    }
  }

  String _formatDimValue(double v) {
    return (v - v.roundToDouble()).abs() < 0.05 ? v.round().toString() : v.toStringAsFixed(1);
  }

  String _formatConstraintText(CadConstraint c, double val) {
    final base = _formatDimValue(val);
    final tol = (c.tolerancePlus != null && c.tolerancePlus! > 0) ? ' ±${_formatDimValue(c.tolerancePlus!)}' : '';
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

  Rect _drawConstraintBadge(Canvas canvas, Offset pos, String symbol, {required bool isSelected, required bool isHovered}) {
    final tp = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(color: (isSelected || isHovered) ? const Color(0xFF92400E) : const Color(0xFF0F172A), fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromCenter(center: pos + const Offset(0, -12), width: math.max(18.0, tp.width + 8.0), height: math.max(18.0, tp.height + 5.0));
    final badgeRect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = isSelected
            ? const Color(0xFFFDE68A)
            : isHovered
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFF8FAFC),
    );
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = (isSelected || isHovered) ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)
        ..strokeWidth = isSelected ? 1.6 : 1.1
        ..style = PaintingStyle.stroke,
    );
    tp.paint(canvas, Offset(rect.center.dx - tp.width / 2.0, rect.center.dy - tp.height / 2.0));
    return rect;
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dist = (p2 - p1).distance;
    if (dist < 1.0) return;
    final dir = (p2 - p1) / dist;
    double walked = 0.0;
    while (walked < dist) {
      final start = p1 + dir * walked;
      final end = p1 + dir * math.min(walked + 4.5, dist);
      canvas.drawLine(start, end, paint);
      walked += 8.0;
    }
  }

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
