// =============================================================================
// UnfoldedBoardPainter — Custom painter for the 2D sheet metal canvas.
//
// Extracted from unfolded_canvas_widget.dart.
// Contains _UnfoldedBoardPainter and all _draw* / _paint* helper methods.
// =============================================================================

part of '../unfolded_canvas_widget.dart';

class _UnfoldedBoardPainter extends CustomPainter {
  final DsfDocument doc;
  final double foldProgress;
  final dynamic foldedMesh;
  final Offset pan;
  final double zoom;
  final StudioToolMode toolMode;
  final SnapTarget? activeSnap;
  final CadPoint2D? pendingBendStart;
  final CadPoint2D? rubberBandEndpoint;
  final List<CadPoint2D> pendingMultiPoints;
  final String? selectedBendId;
  final String? selectedCutId;
  final String? selectedFaceId;
  final String? selectedPunchId;
  final String? selectedPatternId;
  final int? selectedPatternHoleIndex;
  final bool showDimensions;
  final Map<String, BendValidationResult>? bendViolations;
  final String? hoveredPunchId;
  final String? hoveredBendId;
  final ActiveToolConfig? toolConfig;
  final bool Function(FoldBendLine) isBendIncompleteFn;
  final CadPoint2D? hoveredEndpoint;
  final ({CadPoint2D point, String label})? dragAngleInfo;
  final PerforationPattern? previewPerforationPattern;
  final List<CncPunchPrimitive>? previewCouplerPunches;
  final Map<String, Offset> dimensionOffsets;
  final Map<String, double> dimensionLineOffsets;
  final Map<String, Rect>? renderedDimensionBadges;
  final Map<String, ({Offset pA, Offset pB, double offsetDist, CadPoint2D ptA, CadPoint2D ptB, CadDimensionType type})>? renderedDimensionLines;
  final String? editingDimId;
  final String? selectedDimensionId;
  final String? hoveredDimensionId;
  final Map<String, double>? renderedDimensionValues;
  final String? hoveredDimLineId;
  final Map<String, Offset>? portBadgeOffsets;
  final Map<String, Rect>? renderedPortBadges;
  final CadPoint2D? hoveredContourEdgeP1;
  final CadPoint2D? hoveredContourEdgeP2;
  final double? hoveredContourEdgeLengthMm;
  final Set<String> selectedEntityIds;
  final Offset? boxSelectStart;
  final Offset? boxSelectCurrent;
  final CadLineSegment? autoCandidateLine;
  final bool showOpeningTags;
  final DxfFittingMetadata? fittingMetadata;
  final List<ReferenceGeometry> referenceGeometries;
  final List<ConstraintDefinition> constraintDefinitions;
  final String? selectedConstraintId;
  final String? hoveredConstraintId;
  final Map<String, Rect>? renderedConstraintBadges;
  final Set<String> constraintHoverHighlightedEntityIds;
  final bool showDofDiagnostics;
  final EntityConstraintState Function(String)? dofStateProvider;
  final bool showConstructionGeometry;
  final bool showConstraints;
  final bool showProfileFill;
  final bool showPoints;
  final bool showGrid;
  final PortInferenceResult? activePortInferenceResult;
  final CadPoint2D? hoverCursorCad;
  final bool isAltPressed;
  final CanvasDisplaySettings canvasSettings;

  _UnfoldedBoardPainter({
    required this.doc,
    required this.foldProgress,
    required this.foldedMesh,
    required this.pan,
    required this.zoom,
    required this.toolMode,
    this.activeSnap,
    this.pendingBendStart,
    this.rubberBandEndpoint,
    this.pendingMultiPoints = const [],
    this.selectedBendId,
    this.selectedCutId,
    this.selectedFaceId,
    this.selectedPunchId,
    this.selectedPatternId,
    this.selectedPatternHoleIndex,
    this.showDimensions = true,
    this.bendViolations,
    this.hoveredPunchId,
    this.hoveredBendId,
    this.toolConfig,
    required this.isBendIncompleteFn,
    this.hoveredEndpoint,
    this.dragAngleInfo,
    this.previewPerforationPattern,
    this.previewCouplerPunches,
    this.dimensionOffsets = const {},
    this.dimensionLineOffsets = const {},
    this.renderedDimensionBadges,
    this.renderedDimensionLines,
    this.editingDimId,
    this.selectedDimensionId,
    this.hoveredDimensionId,
    this.renderedDimensionValues,
    this.hoveredDimLineId,
    this.portBadgeOffsets,
    this.renderedPortBadges,
    this.hoveredContourEdgeP1,
    this.hoveredContourEdgeP2,
    this.hoveredContourEdgeLengthMm,
    this.selectedEntityIds = const {},
    this.boxSelectStart,
    this.boxSelectCurrent,
    this.autoCandidateLine,
    this.showOpeningTags = true,
    this.fittingMetadata,
    this.referenceGeometries = const [],
    this.constraintDefinitions = const [],
    this.selectedConstraintId,
    this.hoveredConstraintId,
    this.renderedConstraintBadges,
    this.constraintHoverHighlightedEntityIds = const {},
    this.showDofDiagnostics = false,
    this.dofStateProvider,
    this.showConstructionGeometry = true,
    this.showConstraints = true,
    this.showProfileFill = true,
    this.showPoints = true,
    this.showGrid = true,
    this.selectedArcId,
    this.hoveredArcId,
    this.activePortInferenceResult,
    this.hoverCursorCad,
    this.isAltPressed = false,
    this.canvasSettings = const CanvasDisplaySettings(),
  });

  final String? selectedArcId;
  final String? hoveredArcId;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    renderedDimensionBadges?.clear();
    renderedDimensionValues?.clear();
    renderedDimensionLines?.clear();
    renderedPortBadges?.clear();
    renderedConstraintBadges?.clear();

    if (showGrid) {
      _drawGrid(canvas, size, pan);
    }

    final bw = doc.blankWidthMm > 0 ? doc.blankWidthMm : 200.0;
    final bl = doc.blankLengthMm > 0 ? doc.blankLengthMm : 300.0;

    final fitScale = math.min((size.width * 0.75) / bw, (size.height * 0.75) / bl);
    final scale = fitScale * zoom;

    final cx = size.width / 2.0 + pan.dx;
    final cy = size.height / 2.0 + pan.dy;

    final originX = cx - (bw / 2.0) * scale;
    final originY = cy - (bl / 2.0) * scale;

    Offset toScreen(double x, double y) => Offset(originX + x * scale, originY + y * scale);

    // 2. Render Unfolded Planar Faces (Strictly Flat 2D Blank)
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color =
          const Color(0xFF0F172A) // Crisp dark laser cut contour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    Path buildSmoothPolygonPath(List<CadPoint2D> vertices) {
      final path = Path();
      if (vertices.length < 3) return path;

      final n = vertices.length;
      final firstPt = toScreen(vertices.first.x, vertices.first.y);
      path.moveTo(firstPt.dx, firstPt.dy);

      int i = 0;
      while (i < n) {
        final current = vertices[i];

        CadArc2D? matchedArc;
        int targetIdx = -1;
        bool isReversed = false;

        // Check if current vertex is the start or end of an arc in doc.arcs
        for (final arc in doc.arcs) {
          final isAtStart = current.distanceTo(arc.startPoint) < 2.0;
          final isAtEnd = current.distanceTo(arc.endPoint) < 2.0;

          if (isAtStart || isAtEnd) {
            final targetPoint = isAtStart ? arc.endPoint : arc.startPoint;
            // 1. Check immediate next vertex (standard case)
            final nextIdx = (i + 1) % n;
            if (vertices[nextIdx].distanceTo(targetPoint) < 2.0) {
              matchedArc = arc;
              targetIdx = nextIdx;
              isReversed = isAtEnd;
              break;
            }

            // 2. Fallback for legacy discretized polygons: check if an arc spans up to 16 chord vertices,
            // but ONLY if every intermediate vertex actually lies on the arc curve
            for (int k = 2; k <= math.min(16, n - 1); k++) {
              final checkIdx = (i + k) % n;
              if (vertices[checkIdx].distanceTo(targetPoint) < 2.0) {
                bool allOnArc = true;
                for (int m = 1; m < k; m++) {
                  final midPt = vertices[(i + m) % n];
                  if (arc.distanceTo(midPt) > 2.5) {
                    allOnArc = false;
                    break;
                  }
                }
                if (allOnArc) {
                  matchedArc = arc;
                  targetIdx = checkIdx;
                  isReversed = isAtEnd;
                  break;
                }
              }
            }
            if (matchedArc != null) break;
          }
        }

        if (matchedArc != null && targetIdx != -1) {
          final samples = matchedArc.toPolygon(maxStepDeg: 3.0);
          final orderedSamples = isReversed ? samples.reversed.toList() : samples;
          for (final s in orderedSamples.skip(1)) {
            final pt = toScreen(s.x, s.y);
            path.lineTo(pt.dx, pt.dy);
          }
          if (targetIdx == 0 || targetIdx <= i) {
            break;
          }
          i = targetIdx;
        } else {
          final nextIdx = (i + 1) % n;
          final pt = toScreen(vertices[nextIdx].x, vertices[nextIdx].y);
          path.lineTo(pt.dx, pt.dy);
          i++;
          if (nextIdx == 0) break;
        }
      }
      path.close();
      return path;
    }

    final facesToDraw = doc.faces;
    if (facesToDraw.isNotEmpty) {
      for (final face in facesToDraw) {
        if (face.vertices.length < 3) continue;

        final facePath = buildSmoothPolygonPath(face.vertices)..fillType = PathFillType.evenOdd;

        for (final loop in face.holes) {
          if (loop.length >= 3) {
            facePath.addPath(buildSmoothPolygonPath(loop), Offset.zero);
          }
        }

        if (showProfileFill) {
          fillPaint.color = face.id == selectedFaceId
              ? const Color(0xFFFDE68A).withValues(alpha: 0.70)
              : (face.id == doc.baseFaceId ? const Color(0xFFD6E8F6).withValues(alpha: 0.75) : const Color(0xFFE2EFF9).withValues(alpha: 0.70));
          canvas.drawPath(facePath, fillPaint);
        }
        canvas.drawPath(facePath, borderPaint);

        if (face.showLabel && face.isVisible && face.vertices.isNotEmpty) {
          // --- Zoom-adaptive face label declutter ---
          if (!canvasSettings.faceLabel.visible) continue;
          double fMinX = face.vertices.first.x, fMaxX = face.vertices.first.x;
          double fMinY = face.vertices.first.y, fMaxY = face.vertices.first.y;
          for (final v in face.vertices) {
            if (v.x < fMinX) fMinX = v.x;
            if (v.x > fMaxX) fMaxX = v.x;
            if (v.y < fMinY) fMinY = v.y;
            if (v.y > fMaxY) fMaxY = v.y;
          }
          final fWidth = fMaxX - fMinX;
          final fHeight = fMaxY - fMinY;
          if (fWidth > 5.0 && fHeight > 5.0) {
            // Suppress label if the face is too small on-screen.
            final screenW = fWidth * zoom;
            final screenH = fHeight * zoom;
            if (screenW >= canvasSettings.faceLabelMinScreenSize || screenH >= canvasSettings.faceLabelMinScreenSize) {
              final sCenter = toScreen(face.centroid.x, face.centroid.y);
              _drawFaceSizeBadge(canvas, sCenter, face.label.isNotEmpty ? face.label : face.id, fWidth, fHeight, face.id == selectedFaceId);
            }
          }
        }
      }
    } else if (doc.outerContour.length >= 3) {
      final facePath = buildSmoothPolygonPath(doc.outerContour);

      if (showProfileFill) {
        fillPaint.color = const Color(0xFFE2EFF9).withValues(alpha: 0.75);
        canvas.drawPath(facePath, fillPaint);
      }
      canvas.drawPath(facePath, borderPaint);
    }

    // 2.1 Draw CAD Origin Marker at (0,0)
    final sOrigin = toScreen(0.0, 0.0);
    final originAxisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    originAxisPaint.color = const Color(0xFFEF4444);
    canvas.drawLine(sOrigin, sOrigin + const Offset(18, 0), originAxisPaint);
    originAxisPaint.color = const Color(0xFF22C55E);
    canvas.drawLine(sOrigin, sOrigin + const Offset(0, 18), originAxisPaint);
    canvas.drawCircle(
      sOrigin,
      3.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      sOrigin,
      3.5,
      Paint()
        ..color = const Color(0xFF64748B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawCircle(
      sOrigin,
      1.5,
      Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.fill,
    );

    // 2.2 Draw Point Vertices (Arcs display only 2 dots at the ends)
    if (showPoints) {
      final pointFillPaint = Paint()..style = PaintingStyle.fill;
      final pointStrokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white;

      final drawnPts = <Offset>{};
      void drawVertex(CadPoint2D cadPt, {bool isConstrained = false}) {
        final sPt = toScreen(cadPt.x, cadPt.y);
        if (drawnPts.contains(sPt)) return;
        drawnPts.add(sPt);

        pointFillPaint.color = isConstrained ? const Color(0xFF0F172A) : const Color(0xFF2563EB);
        canvas.drawCircle(sPt, 3.2, pointFillPaint);
        canvas.drawCircle(sPt, 3.2, pointStrokePaint);
      }

      final isPartConstrained = constraintDefinitions.isNotEmpty;

      // Draw exactly 2 dots for each arc (SS1 & SS2)
      for (final arc in doc.arcs) {
        drawVertex(arc.startPoint, isConstrained: isPartConstrained);
        drawVertex(arc.endPoint, isConstrained: isPartConstrained);
      }

      bool isInsideAnyArc(CadPoint2D pt) {
        for (final arc in doc.arcs) {
          if (pt.distanceTo(arc.startPoint) <= 1.2 || pt.distanceTo(arc.endPoint) <= 1.2) {
            return false;
          }
          if (arc.distanceTo(pt) <= 1.0) {
            return true;
          }
        }
        return false;
      }

      if (doc.outerContour.isNotEmpty) {
        final intermediate = _findIntermediateArcIndices(doc.outerContour);
        for (int i = 0; i < doc.outerContour.length; i++) {
          final pt = doc.outerContour[i];
          if (!intermediate.contains(i) && !isInsideAnyArc(pt)) {
            drawVertex(pt, isConstrained: isPartConstrained);
          }
        }
      }
      for (final f in doc.faces) {
        if (f.vertices.isNotEmpty) {
          final intermediate = _findIntermediateArcIndices(f.vertices);
          for (int i = 0; i < f.vertices.length; i++) {
            final pt = f.vertices[i];
            if (!intermediate.contains(i) && !isInsideAnyArc(pt)) {
              drawVertex(pt, isConstrained: isPartConstrained);
            }
          }
        }
      }
      for (final b in doc.bends) {
        drawVertex(b.p1, isConstrained: true);
        drawVertex(b.p2, isConstrained: true);
      }
      for (final p in doc.punches) {
        drawVertex(p.center, isConstrained: isPartConstrained);
      }
    }

    // 3. Render Laser Cut Lines & Slits
    final cutPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final selectedCutPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    for (final cut in doc.cutLines) {
      final isSelected = cut.id == selectedCutId || selectedEntityIds.contains(cut.id);
      final isHoverLinked = constraintHoverHighlightedEntityIds.contains(cut.id);
      final sp1 = toScreen(cut.p1.x, cut.p1.y);
      final sp2 = toScreen(cut.p2.x, cut.p2.y);

      if (isHoverLinked) {
        final haloPaint = Paint()
          ..color = const Color(0xFF06B6D4).withValues(alpha: 0.85)
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke;
        canvas.drawLine(sp1, sp2, haloPaint);
      }

      Paint effectiveCutPaint = isSelected ? selectedCutPaint : cutPaint;
      if (showDofDiagnostics && dofStateProvider != null) {
        final dofState = dofStateProvider!(cut.id);
        effectiveCutPaint = Paint()
          ..color = dofState.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.2 : 1.5;
      }

      canvas.drawLine(sp1, sp2, effectiveCutPaint);

      final mid = Offset((sp1.dx + sp2.dx) / 2.0, (sp1.dy + sp2.dy) / 2.0);
      if (cut.showLabel) {
        _drawCutBadge(canvas, mid, cut.id, isSelected, lengthMm: cut.length, showLabel: cut.showLabel);
      }

      if (isSelected) {
        _drawHandle(canvas, sp1);
        _drawHandle(canvas, sp2);
      }
    }

    // 3b. Render First-Class Arcs (SS3: Hover, Selection, Dimension Badge)
    for (final arc in doc.arcs) {
      final isSelected = arc.id == selectedArcId || selectedEntityIds.contains(arc.id);
      final isHovered = arc.id == hoveredArcId && !isSelected;

      if (isSelected || isHovered || !arc.isBoundary) {
        final arcColor = isSelected ? const Color(0xFF2563EB) : (isHovered ? const Color(0xFF0EA5E9) : const Color(0xFF0F172A));

        final arcPaint = Paint()
          ..color = arcColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.4 : (isHovered ? 1.8 : 1.2);

        final poly = arc.toPolygon(maxStepDeg: 3.0);
        if (poly.length >= 2) {
          final arcPath = Path();
          final s0 = toScreen(poly.first.x, poly.first.y);
          arcPath.moveTo(s0.dx, s0.dy);
          for (int i = 1; i < poly.length; i++) {
            final s = toScreen(poly[i].x, poly[i].y);
            arcPath.lineTo(s.dx, s.dy);
          }
          canvas.drawPath(arcPath, arcPaint);
        }
      }
      // Draw arc badge if arcLabel is visible and arc.showLabel, OR if hovered/selected
      final showArcBadge = arc.showLabel && (canvasSettings.arcLabel.visible || isHovered || isSelected);
      if (showArcBadge) {
        final midCad = arc.midpoint;
        final sMid = toScreen(midCad.x, midCad.y);
        _drawArcBadge(canvas, sMid, arc, isSelected);
      }
    }

    // 4. Render Fold Bends & Flanges with Bend Deductions, Role Colors, and Hover Glow
    for (final bend in doc.bends) {
      if (!bend.isVisible) continue;
      final isSelected = bend.id == selectedBendId || selectedEntityIds.contains(bend.id);
      final isHovered = bend.id == hoveredBendId && !isSelected;
      final isUp = bend.direction == FoldDirection.up;
      final isFlange = bend.isFlange;
      final isIncomplete = isBendIncompleteFn(bend);

      Color color;
      if (showDofDiagnostics && dofStateProvider != null) {
        color = dofStateProvider!(bend.id).color;
      } else if (isSelected) {
        color = isFlange ? const Color(0xFF7C3AED) : const Color(0xFF2563EB); // Vibrant Purple / Royal Blue
      } else if (isHovered) {
        color = isFlange ? const Color(0xFFA78BFA) : const Color(0xFF0EA5E9); // Light Purple / Sky-500 hover
      } else if (isIncomplete) {
        color = const Color(0xFFD97706); // Amber warning
      } else {
        color = isFlange
            ? const Color(0xFF8B5CF6) // Vibrant Violet/Purple for Flange
            : (isUp ? const Color(0xFF0284C7) : const Color(0xFFD97706));
      }

      final isHoverLinked = constraintHoverHighlightedEntityIds.contains(bend.id);
      final sp1 = toScreen(bend.p1.x, bend.p1.y);
      final sp2 = toScreen(bend.p2.x, bend.p2.y);

      if (isHoverLinked) {
        final haloPaint = Paint()
          ..color = const Color(0xFF06B6D4).withValues(alpha: 0.85)
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(sp1, sp2, haloPaint);
      }

      // Render Outer Bend Zone Margins (Curving Bend Allowance / Fillet Lines)
      final baMm = bend.calculateBendAllowance(sheetThicknessMm: doc.material.thicknessMm, kFactor: bend.kFactor ?? doc.material.kFactor);
      final halfBaMm = baMm / 2.0;

      final bendLen = bend.p1.distanceTo(bend.p2);
      if (bendLen > 1e-4) {
        final nx = -(bend.p2.y - bend.p1.y) / bendLen;
        final ny = (bend.p2.x - bend.p1.x) / bendLen;

        final m1a = toScreen(bend.p1.x + nx * halfBaMm, bend.p1.y + ny * halfBaMm);
        final m1b = toScreen(bend.p2.x + nx * halfBaMm, bend.p2.y + ny * halfBaMm);
        final m2a = toScreen(bend.p1.x - nx * halfBaMm, bend.p1.y - ny * halfBaMm);
        final m2b = toScreen(bend.p2.x - nx * halfBaMm, bend.p2.y - ny * halfBaMm);

        // 1. Shaded Bend Allowance Zone (Clear visual indicator distinguishing bends from cuts)
        final zonePath = Path()
          ..moveTo(m1a.dx, m1a.dy)
          ..lineTo(m1b.dx, m1b.dy)
          ..lineTo(m2b.dx, m2b.dy)
          ..lineTo(m2a.dx, m2a.dy)
          ..close();
        final zonePaint = Paint()
          ..color = color.withValues(alpha: isSelected ? 0.18 : (isHovered ? 0.14 : 0.08))
          ..style = PaintingStyle.fill;
        canvas.drawPath(zonePath, zonePaint);

        // 2. Bend Zone Margin Lines
        final marginPaint = Paint()
          ..color = color.withValues(alpha: isSelected ? 0.45 : 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;

        _drawDashedLine(canvas, m1a, m1b, marginPaint, dash: 4.0, gap: 3.0);
        _drawDashedLine(canvas, m2a, m2b, marginPaint, dash: 4.0, gap: 3.0);

        // Render Relief Notch Indicators at bend endpoints if configured
        if (bend.reliefType != BendReliefType.none) {
          final reliefPaint = Paint()
            ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.70)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8;
          const notchRadius = 2.8;
          canvas.drawRect(Rect.fromCenter(center: sp1, width: notchRadius * 2, height: notchRadius * 2), reliefPaint);
          canvas.drawRect(Rect.fromCenter(center: sp2, width: notchRadius * 2, height: notchRadius * 2), reliefPaint);
        }
      }

      // 3. Central Bend/Flange Line (Thicker and distinctly styled)
      final bendPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.0 : (isHovered ? 1.6 : 1.3);

      _drawDashedLine(canvas, sp1, sp2, bendPaint, dash: 6.0, gap: 3.5);

      if (isHovered || isSelected) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: isSelected ? 0.25 : 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3.0 : 2.4;
        canvas.drawLine(sp1, sp2, glowPaint);
      }

      // 4. Angle indicator label with high-contrast pill badge and occluding background
      final mid = Offset((sp1.dx + sp2.dx) / 2.0, (sp1.dy + sp2.dy) / 2.0);

      if (bend.showLabel) {
        // --- Zoom-adaptive bend label declutter ---
        final effectivelyVisible = canvasSettings.bendLabel.visible && zoom >= canvasSettings.bendLabelHideZoomThreshold;
        if (!effectivelyVisible) {
          // Skip label entirely when very zoomed out
        } else {
          final bool compactMode = zoom < canvasSettings.bendLabelCompactZoomThreshold;

          final arrowStr = isUp ? '↑' : '↓';
          final lenStr = compactMode ? '' : ' · ${formatMeasure(bend.length, canvasSettings)}';
          final String labelText;
          if (isIncomplete) {
            labelText = '⚠️ ${bend.id} OPEN$lenStr';
          } else {
            labelText = '${bend.id} ${bend.targetAngleDeg.toStringAsFixed(0)}° $arrowStr$lenStr';
          }

          final bendLabelStyle = canvasSettings.bendLabel;
          final textColor = isIncomplete
              ? const Color(0xFFB45309)
              : (isFlange ? const Color(0xFF6D28D9) : (isUp ? const Color(0xFF0369A1) : const Color(0xFFB45309)));

          final textSpan = TextSpan(
            text: labelText,
            style: TextStyle(color: textColor, fontSize: bendLabelStyle.fontSize, fontWeight: bendLabelStyle.fontWeight, letterSpacing: 0.2),
          );
          final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();

          const iconSize = 11.0;
          const badgePaddingH = 7.0;
          final badgeWidth = iconSize + 4.0 + tp.width + (badgePaddingH * 2.0);
          const badgeHeight = 20.0;

          final badgeRect = RRect.fromRectAndRadius(Rect.fromCenter(center: mid, width: badgeWidth, height: badgeHeight), const Radius.circular(4.5));

          // 4a. Drop shadow
          canvas.drawRRect(
            badgeRect.shift(const Offset(0, 1.2)),
            Paint()
              ..color = Colors.black.withValues(alpha: 0.14)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
          );

          // 4b. High-contrast pill background (Occludes the dashed line completely)
          final badgeBg = Paint()
            ..color = isIncomplete ? const Color(0xFFFEF3C7) : (isSelected ? const Color(0xFFF0F9FF) : Colors.white.withValues(alpha: 0.96))
            ..style = PaintingStyle.fill;
          canvas.drawRRect(badgeRect, badgeBg);

          // 4c. Crisp colored border
          final badgeBorder = Paint()
            ..color = color.withValues(alpha: isSelected ? 0.95 : 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 1.6 : 1.0;
          canvas.drawRRect(badgeRect, badgeBorder);

          // 4d. Micro vector icon (Hook for Flange, Chevron for Bend)
          final iconLeft = mid.dx - (badgeWidth / 2.0) + badgePaddingH;
          final iconTop = mid.dy - (iconSize / 2.0);
          final iconPaint = Paint()
            ..color = textColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

          if (isFlange) {
            final hook = Path()
              ..moveTo(iconLeft + 1.0, iconTop + 9.5)
              ..lineTo(iconLeft + 1.0, iconTop + 2.0)
              ..lineTo(iconLeft + 9.0, iconTop + 2.0);
            canvas.drawPath(hook, iconPaint);
          } else {
            final chev = Path();
            if (isUp) {
              chev.moveTo(iconLeft + 1.5, iconTop + 8.0);
              chev.lineTo(iconLeft + 5.5, iconTop + 2.5);
              chev.lineTo(iconLeft + 9.5, iconTop + 8.0);
            } else {
              chev.moveTo(iconLeft + 1.5, iconTop + 3.0);
              chev.lineTo(iconLeft + 5.5, iconTop + 8.5);
              chev.lineTo(iconLeft + 9.5, iconTop + 3.0);
            }
            canvas.drawPath(chev, iconPaint);
          }

          // 4e. Paint label text
          tp.paint(canvas, Offset(iconLeft + iconSize + 4.0, mid.dy - tp.height / 2.0));

          // 4f. Render CAM violation icon if detected
          final vResult = bendViolations?[bend.id];
          if (vResult != null && !vResult.isClean) {
            const camSpan = TextSpan(text: '⚠️', style: TextStyle(fontSize: 9.5));
            final camTp = TextPainter(text: camSpan, textDirection: TextDirection.ltr)..layout();
            camTp.paint(canvas, Offset(mid.dx + badgeWidth / 2.0 + 3, mid.dy - camTp.height / 2.0));
          }
        }
      }

      // Warning rings around open endpoints
      if (isIncomplete) {
        final warnRingPaint = Paint()
          ..color = const Color(0xFFD97706)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(sp1, 6.0, warnRingPaint);
        canvas.drawCircle(sp2, 6.0, warnRingPaint);
      }

      // If this bend is selected, render handles and dimension leader lines
      if (isSelected) {
        _drawHandle(canvas, sp1);
        _drawHandle(canvas, sp2);

        if (bend.showLabel) {
          final midBend = toScreen(bend.midpoint.x, bend.midpoint.y);
          final leftEdgeScreen = toScreen(0.0, bend.midpoint.y);
          final bottomEdgeScreen = toScreen(bend.midpoint.x, 0.0);

          final dimLinePaint = Paint()
            ..color = const Color(0xFFD97706)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;

          _drawDashedLine(canvas, midBend, leftEdgeScreen, dimLinePaint, dash: 4, gap: 3);
          _drawDimText(canvas, Offset((midBend.dx + leftEdgeScreen.dx) / 2, midBend.dy - 12), 'X: ${bend.midpoint.x.toStringAsFixed(1)} mm');

          _drawDashedLine(canvas, midBend, bottomEdgeScreen, dimLinePaint, dash: 4, gap: 3);
          _drawDimText(canvas, Offset(midBend.dx + 6, (midBend.dy + bottomEdgeScreen.dy) / 2), 'Y: ${bend.midpoint.y.toStringAsFixed(1)} mm');
        }
      }
    }

    // 5. Render Turret Punches & Holes
    final holePaint = Paint()
      ..color =
          const Color(0xFF059669) // Emerald-600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final holeFillPaint = Paint()
      ..color =
          const Color(0xFFECFDF5) // Light mint background
      ..style = PaintingStyle.fill;

    final selectedHolePaint = Paint()
      ..color =
          const Color(0xFF2563EB) // Blue-600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final selectedFillPaint = Paint()
      ..color =
          const Color(0xFFDBEAFE) // Light blue
      ..style = PaintingStyle.fill;

    final hoveredHolePaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final hoveredFillPaint = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.fill;

    // Distinct styling for Coupler Mounting Slots (Electric Violet & Lavender Theme)
    final couplerHolePaint = Paint()
      ..color =
          const Color(0xFF7C3AED) // Electric Violet-600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final couplerHoleFillPaint = Paint()
      ..color =
          const Color(0xFFF5F3FF) // Soft lavender fill
      ..style = PaintingStyle.fill;

    final selectedCouplerHolePaint = Paint()
      ..color =
          const Color(0xFF6D28D9) // Deep Violet-700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final selectedCouplerFillPaint = Paint()
      ..color =
          const Color(0xFFEDE9FE) // Lavender-100 fill
      ..style = PaintingStyle.fill;

    final hoveredCouplerHolePaint = Paint()
      ..color =
          const Color(0xFF8B5CF6) // Violet-500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    // 5. Render Turret Punches & Holes (Both Standalone and Perforation Pattern Holes)
    final unselectedPath = Path();
    final unselectedCouplerPath = Path();
    bool hasUnselected = false;
    bool hasUnselectedCoupler = false;
    final activePunches = <CncPunchPrimitive>[];
    final allPunchesList = doc.allPunches;

    // For dense punch grids (> 25 holes), batch into single path for 60 FPS rendering
    final useBatching = allPunchesList.length > 25;
    Path? unselectedPunchesUnion;
    Path? unselectedCouplerUnion;

    for (final punch in allPunchesList) {
      final isSelected = punch.id == selectedPunchId || selectedEntityIds.contains(punch.id) || selectedEntityIds.any((id) => punch.id.startsWith('${id}_'));
      final isHovered = punch.id == hoveredPunchId && !isSelected;
      if (isSelected || isHovered) {
        activePunches.add(punch);
      } else {
        final isCoupler = punch.role == CncPunchRole.coupler;
        final poly = punch.toPolygon();
        if (poly.isNotEmpty) {
          final pPath = Path();
          final hp0 = toScreen(poly.first.x, poly.first.y);
          pPath.moveTo(hp0.dx, hp0.dy);
          for (int i = 1; i < poly.length; i++) {
            final hpi = toScreen(poly[i].x, poly[i].y);
            pPath.lineTo(hpi.dx, hpi.dy);
          }
          pPath.close();

          if (isCoupler) {
            if (useBatching) {
              unselectedCouplerPath.addPath(pPath, Offset.zero);
              hasUnselectedCoupler = true;
            } else {
              unselectedCouplerUnion = (unselectedCouplerUnion == null) ? pPath : Path.combine(PathOperation.union, unselectedCouplerUnion, pPath);
            }
          } else {
            if (useBatching) {
              unselectedPath.addPath(pPath, Offset.zero);
              hasUnselected = true;
            } else {
              unselectedPunchesUnion = (unselectedPunchesUnion == null) ? pPath : Path.combine(PathOperation.union, unselectedPunchesUnion, pPath);
            }
          }
        }
      }
    }

    if (useBatching) {
      if (hasUnselected) {
        canvas.drawPath(unselectedPath, holeFillPaint);
        canvas.drawPath(unselectedPath, holePaint);
      }
      if (hasUnselectedCoupler) {
        canvas.drawPath(unselectedCouplerPath, couplerHoleFillPaint);
        canvas.drawPath(unselectedCouplerPath, couplerHolePaint);
      }
    } else {
      if (unselectedPunchesUnion != null) {
        canvas.drawPath(unselectedPunchesUnion, holeFillPaint);
        canvas.drawPath(unselectedPunchesUnion, holePaint);
      }
      if (unselectedCouplerUnion != null) {
        canvas.drawPath(unselectedCouplerUnion, couplerHoleFillPaint);
        canvas.drawPath(unselectedCouplerUnion, couplerHolePaint);
      }
    }

    // Distinct visual badge & in-hole logo for coupler slots on the 2D sketch
    if (scale > 0.35) {
      for (final punch in allPunchesList) {
        if (punch.role == CncPunchRole.coupler) {
          final isSelected =
              punch.id == selectedPunchId || selectedEntityIds.contains(punch.id) || selectedEntityIds.any((id) => punch.id.startsWith('${id}_'));
          final isHovered = punch.id == hoveredPunchId && !isSelected;
          final centerScreen = toScreen(punch.center.x, punch.center.y);
          final halfSpan = (punch.type == PunchType.obroundSlot || punch.type == PunchType.rectangle)
              ? (punch.widthMm * 0.5 * scale)
              : (punch.diameterMm * 0.5 * scale);

          // Internal hole coupler watermark logo
          if (halfSpan >= 4.0) {
            final glyphSize = math.min(18.0, math.max(6.0, halfSpan * 0.85));
            _drawCouplerGlyph(
              canvas,
              centerScreen,
              glyphSize,
              const Color(0xFF7C3AED).withValues(alpha: isSelected ? 0.9 : (isHovered ? 0.85 : 0.75)),
              strokeWidth: 1.0,
            );
          }
        }
      }
    }

    // Fallback: If no punch primitives are present, draw any direct face hole loops (e.g. from imported .dsf)
    if (allPunchesList.isEmpty) {
      for (final face in doc.faces) {
        for (final loop in face.holes) {
          if (loop.length >= 3) {
            final fPath = Path();
            final hp0 = toScreen(loop.first.x, loop.first.y);
            fPath.moveTo(hp0.dx, hp0.dy);
            for (int i = 1; i < loop.length; i++) {
              final hpi = toScreen(loop[i].x, loop[i].y);
              fPath.lineTo(hpi.dx, hpi.dy);
            }
            fPath.close();
            canvas.drawPath(fPath, holeFillPaint);
            canvas.drawPath(fPath, holePaint);
          }
        }
      }
    }

    for (final punch in activePunches) {
      final isSelected = punch.id == selectedPunchId || selectedEntityIds.contains(punch.id) || selectedEntityIds.any((id) => punch.id.startsWith('${id}_'));
      final isHovered = punch.id == hoveredPunchId && !isSelected;
      final isHoverLinked = constraintHoverHighlightedEntityIds.contains(punch.id);
      final poly = punch.toPolygon();
      if (poly.isNotEmpty) {
        final holePath = Path();
        final hp0 = toScreen(poly.first.x, poly.first.y);
        holePath.moveTo(hp0.dx, hp0.dy);
        for (int i = 1; i < poly.length; i++) {
          final hpi = toScreen(poly[i].x, poly[i].y);
          holePath.lineTo(hpi.dx, hpi.dy);
        }
        holePath.close();

        if (isHoverLinked) {
          final haloPaint = Paint()
            ..color = const Color(0xFF06B6D4).withValues(alpha: 0.85)
            ..strokeWidth = 4.0
            ..style = PaintingStyle.stroke;
          canvas.drawPath(holePath, haloPaint);
        }

        if (showDofDiagnostics && dofStateProvider != null) {
          final dof = dofStateProvider!(punch.id);
          final dofBorder = Paint()
            ..color = dof.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.4 : 1.6;
          canvas.drawPath(holePath, isSelected ? selectedFillPaint : hoveredFillPaint);
          canvas.drawPath(holePath, dofBorder);
        } else if (isSelected) {
          final isCoupler = punch.role == CncPunchRole.coupler;
          canvas.drawPath(holePath, isCoupler ? selectedCouplerFillPaint : selectedFillPaint);
          canvas.drawPath(holePath, isCoupler ? selectedCouplerHolePaint : selectedHolePaint);

          // Draw CAD Constraint Leader Lines to Left and Bottom Edges
          if (punch.showLabel) {
            final centerScreen = toScreen(punch.center.x, punch.center.y);
            final leftEdgeScreen = toScreen(0.0, punch.center.y);
            final bottomEdgeScreen = toScreen(punch.center.x, 0.0);

            final dimLinePaint = Paint()
              ..color =
                  const Color(0xFFD97706) // Amber dimension leader
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;

            // Dimension X to Left Edge
            _drawDashedLine(canvas, centerScreen, leftEdgeScreen, dimLinePaint, dash: 4, gap: 3);
            _drawDimText(canvas, Offset((centerScreen.dx + leftEdgeScreen.dx) / 2, centerScreen.dy - 12), 'X: ${punch.center.x.toStringAsFixed(1)} mm');

            // Dimension Y to Bottom Edge
            _drawDashedLine(canvas, centerScreen, bottomEdgeScreen, dimLinePaint, dash: 4, gap: 3);
            _drawDimText(canvas, Offset(centerScreen.dx + 6, (centerScreen.dy + bottomEdgeScreen.dy) / 2), 'Y: ${punch.center.y.toStringAsFixed(1)} mm');
          }
        } else {
          final isCoupler = punch.role == CncPunchRole.coupler;
          canvas.drawPath(holePath, isCoupler ? selectedCouplerFillPaint : hoveredFillPaint);
          canvas.drawPath(holePath, isCoupler ? hoveredCouplerHolePaint : hoveredHolePaint);
          final haloPaint = Paint()
            ..color = (isCoupler ? const Color(0xFF8B5CF6) : const Color(0xFF0284C7)).withValues(alpha: 0.20)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawPath(holePath, haloPaint);
        }

        if (punch.showLabel && (isSelected || isHovered)) {
          final centerScreen = toScreen(punch.center.x, punch.center.y);
          final isCoupler = punch.role == CncPunchRole.coupler;
          final prefix = '';
          final String sizeStr;
          if (punch.type == PunchType.roundHole) {
            sizeStr = '$prefixØ ${punch.diameterMm.toStringAsFixed(1)} mm';
          } else if (punch.type == PunchType.square) {
            sizeStr = '$prefix${punch.widthMm.toStringAsFixed(1)} × ${punch.widthMm.toStringAsFixed(1)} mm';
          } else {
            sizeStr = '$prefix${punch.widthMm.toStringAsFixed(1)} × ${punch.lengthMm.toStringAsFixed(1)} mm';
          }

          final pSpan = TextSpan(
            text: sizeStr,
            style: TextStyle(
              color: isSelected
                  ? (isCoupler ? const Color(0xFF6D28D9) : const Color(0xFF1D4ED8))
                  : (isCoupler ? const Color(0xFF7C3AED) : const Color(0xFF047857)),
              fontSize: 9.0,
              fontWeight: FontWeight.bold,
            ),
          );
          final pTp = TextPainter(text: pSpan, textDirection: TextDirection.ltr)..layout();
          final pBadgeRect = Rect.fromCenter(center: Offset(centerScreen.dx, centerScreen.dy - 16.0), width: pTp.width + 8.0, height: pTp.height + 4.0);
          final pRRect = RRect.fromRectAndRadius(pBadgeRect, const Radius.circular(3.0));
          canvas.drawRRect(
            pRRect,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.94)
              ..style = PaintingStyle.fill,
          );
          canvas.drawRRect(
            pRRect,
            Paint()
              ..color = isSelected ? const Color(0xFF2563EB) : const Color(0xFF10B981)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8,
          );
          pTp.paint(canvas, Offset(pBadgeRect.left + 4.0, pBadgeRect.top + 2.0));
        }
      }
    }

    // Ghost Phantom Preview for pending tool stamp (Round Hole, Obround, Square, Perforation, Chamfer)
    if (pendingBendStart == null && rubberBandEndpoint != null) {
      final ghostCenter = toScreen(rubberBandEndpoint!.x, rubberBandEndpoint!.y);
      final cfg = toolConfig ?? ActiveToolConfig();

      final ghostFill = Paint()
        ..color = const Color(0xFF0284C7).withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      final ghostStroke = Paint()
        ..color = const Color(0xFF0284C7).withValues(alpha: 0.80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      if (toolMode == StudioToolMode.addPunchRound || toolMode == StudioToolMode.drawCircle) {
        final r = (cfg.roundHoleDiameterMm / 2.0) * scale;
        canvas.drawCircle(ghostCenter, r, ghostFill);
        canvas.drawCircle(ghostCenter, r, ghostStroke);
        _drawDimText(canvas, Offset(ghostCenter.dx, ghostCenter.dy - r - 10), 'Ø ${cfg.roundHoleDiameterMm.toStringAsFixed(1)} mm');
      } else if (toolMode == StudioToolMode.addPunchObround) {
        final halfW = (cfg.obroundWidthMm / 2.0) * scale;
        final halfL = (cfg.obroundLengthMm / 2.0) * scale;
        final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: ghostCenter, width: halfW * 2.0, height: halfL * 2.0), Radius.circular(halfW));
        canvas.drawRRect(rect, ghostFill);
        canvas.drawRRect(rect, ghostStroke);
        _drawDimText(
          canvas,
          Offset(ghostCenter.dx, ghostCenter.dy - halfL - 10),
          '${cfg.obroundLengthMm.toStringAsFixed(0)}x${cfg.obroundWidthMm.toStringAsFixed(0)} mm',
        );
      } else if (toolMode == StudioToolMode.addPunchSquare || toolMode == StudioToolMode.drawRectangle) {
        final w = cfg.squareAspectLocked ? cfg.squareSizeMm : cfg.rectWidthMm;
        final h = cfg.squareAspectLocked ? cfg.squareSizeMm : cfg.rectHeightMm;
        final halfW = (w / 2.0) * scale;
        final halfH = (h / 2.0) * scale;
        final rect = Rect.fromCenter(center: ghostCenter, width: halfW * 2.0, height: halfH * 2.0);
        canvas.drawRect(rect, ghostFill);
        canvas.drawRect(rect, ghostStroke);
        _drawDimText(canvas, Offset(ghostCenter.dx, ghostCenter.dy - halfH - 10), '□ ${w.toStringAsFixed(1)} × ${h.toStringAsFixed(1)} mm');
      } else if (toolMode == StudioToolMode.perforationPattern && previewPerforationPattern == null) {
        final countX = cfg.patternCountX;
        final countY = cfg.patternCountY;
        final pitchX = cfg.patternPitchXMm * scale;
        final pitchY = cfg.patternPitchYMm * scale;
        final rotRad = cfg.patternRotationDeg * math.pi / 180.0;

        final totalSpanX = (countX - 1) * pitchX;
        final totalSpanY = (countY - 1) * pitchY;
        final startX = ghostCenter.dx - totalSpanX / 2.0;
        final startY = ghostCenter.dy - totalSpanY / 2.0;

        for (int row = 0; row < countY; row++) {
          final rowOffset = (cfg.patternStaggered && row % 2 == 1) ? pitchX / 2.0 : 0.0;
          for (int col = 0; col < countX; col++) {
            final slotX = startX + col * pitchX + rowOffset;
            final slotY = startY + row * pitchY;

            canvas.save();
            canvas.translate(slotX, slotY);
            if (rotRad.abs() > 1e-4) {
              canvas.rotate(rotRad);
            }

            if (cfg.patternHoleType == PunchType.roundHole) {
              final r = (cfg.patternDiameter / 2.0) * scale;
              canvas.drawCircle(Offset.zero, r, ghostFill);
              canvas.drawCircle(Offset.zero, r, ghostStroke);
            } else if (cfg.patternHoleType == PunchType.square) {
              final halfS = (cfg.patternSquareSize / 2.0) * scale;
              final rect = Rect.fromCenter(center: Offset.zero, width: halfS * 2.0, height: halfS * 2.0);
              canvas.drawRect(rect, ghostFill);
              canvas.drawRect(rect, ghostStroke);
            } else if (cfg.patternHoleType == PunchType.rectangle) {
              final halfW = (cfg.patternRectWidth / 2.0) * scale;
              final halfH = (cfg.patternRectHeight / 2.0) * scale;
              final rect = Rect.fromCenter(center: Offset.zero, width: halfW * 2.0, height: halfH * 2.0);
              canvas.drawRect(rect, ghostFill);
              canvas.drawRect(rect, ghostStroke);
            } else {
              // Default: Obround slot
              final halfW = (cfg.patternSlotWidth / 2.0) * scale;
              final halfH = (cfg.patternSlotHeight / 2.0) * scale;
              final r = math.min(halfW, halfH);
              final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: halfW * 2.0, height: halfH * 2.0), Radius.circular(r));
              canvas.drawRRect(rect, ghostFill);
              canvas.drawRRect(rect, ghostStroke);
            }

            canvas.restore();
          }
        }
        _drawDimText(
          canvas,
          Offset(ghostCenter.dx, ghostCenter.dy - totalSpanY / 2.0 - 12),
          'Manual $countX×$countY ${cfg.patternStaggered ? "(Staggered)" : "(Straight)"} @ ${cfg.patternRotationDeg.round()}°',
        );
      } else if (toolMode == StudioToolMode.cornerChamfer) {
        canvas.drawCircle(ghostCenter, 4.0, ghostStroke);
        _drawDimText(canvas, Offset(ghostCenter.dx, ghostCenter.dy - 12), 'Chamfer ${cfg.chamferDistanceMm.toStringAsFixed(1)} mm');
      } else if (toolMode == StudioToolMode.addBend || toolMode == StudioToolMode.addFlange) {
        final isFlange = toolMode == StudioToolMode.addFlange;
        final guideColor = isFlange ? const Color(0xFF8B5CF6) : const Color(0xFF0284C7);

        // 1. If an auto candidate line has been calculated, draw it cutting across the sheet
        if (autoCandidateLine != null) {
          final g1 = toScreen(autoCandidateLine!.p1.x, autoCandidateLine!.p1.y);
          final g2 = toScreen(autoCandidateLine!.p2.x, autoCandidateLine!.p2.y);
          final autoPaint = Paint()
            ..color = guideColor.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;

          _drawDashedLine(canvas, g1, g2, autoPaint, dash: 5.0, gap: 3.5);

          // Subtle dot glyphs at both endpoints (snapped between opposite dots)
          final dotPaint = Paint()
            ..color = guideColor
            ..style = PaintingStyle.fill;
          canvas.drawCircle(g1, 2.2, dotPaint);
          canvas.drawCircle(g2, 2.2, dotPaint);

          final prefix = isFlange ? 'FLANGE' : 'BEND';
          final lineMid = Offset((g1.dx + g2.dx) / 2.0, (g1.dy + g2.dy) / 2.0);

          // Calculate actual candidate feature dimension
          final candLen = autoCandidateLine!.p1.distanceTo(autoCandidateLine!.p2);
          double effDist = isFlange ? 10.0 : candLen;
          if (doc.outerContour.isNotEmpty) {
            double? minD;
            final cMid = CadPoint2D((autoCandidateLine!.p1.x + autoCandidateLine!.p2.x) / 2.0, (autoCandidateLine!.p1.y + autoCandidateLine!.p2.y) / 2.0);
            for (int i = 0; i < doc.outerContour.length; i++) {
              final a = doc.outerContour[i];
              final b = doc.outerContour[(i + 1) % doc.outerContour.length];
              final l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y);
              if (l2 < 1e-4) continue;
              final t = math.max(0.0, math.min(1.0, ((cMid.x - a.x) * (b.x - a.x) + (cMid.y - a.y) * (b.y - a.y)) / l2));
              final proj = CadPoint2D(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
              final d = cMid.distanceTo(proj);
              if (minD == null || d < minD) minD = d;
            }
            if (minD != null && minD > 0.5) {
              effDist = isFlange ? minD : (candLen >= 20.0 ? candLen : minD);
            }
          }

          _drawDimText(canvas, Offset(lineMid.dx, lineMid.dy - 12), '⚡ AUTO $prefix ${effDist.toStringAsFixed(0)}mm (Click to place)');
        } else {
          final contour = doc.outerContour;
          if (contour.length >= 3 && rubberBandEndpoint != null) {
            final pt = rubberBandEndpoint!;
            double? minDist;
            CadPoint2D? edgeP1;
            CadPoint2D? edgeP2;
            double bestNx = 0;
            double bestNy = 0;

            for (int i = 0; i < contour.length; i++) {
              final e1 = contour[i];
              final e2 = contour[(i + 1) % contour.length];
              final elen = e1.distanceTo(e2);
              if (elen < 1e-4) continue;
              final ex = (e2.x - e1.x) / elen;
              final ey = (e2.y - e1.y) / elen;
              final nx = -ey;
              final ny = ex;
              final dist = ((pt.x - e1.x) * nx + (pt.y - e1.y) * ny).abs();
              if (minDist == null || dist < minDist) {
                minDist = dist;
                edgeP1 = e1;
                edgeP2 = e2;
                bestNx = nx;
                bestNy = ny;
              }
            }

            if (minDist != null && edgeP1 != null && edgeP2 != null) {
              final snapOffsets = isFlange ? [10.0, 12.0, 13.0, 14.0, 15.0, 20.0, 25.0] : [25.0, 50.0, 75.0, 100.0, 125.0, 150.0, 200.0];
              double effectiveDist = minDist;
              for (final snapVal in snapOffsets) {
                if ((minDist - snapVal).abs() <= 3.5) {
                  effectiveDist = snapVal;
                  break;
                }
              }

              final shiftX = bestNx * effectiveDist;
              final shiftY = bestNy * effectiveDist;
              final g1 = toScreen(edgeP1.x + shiftX, edgeP1.y + shiftY);
              final g2 = toScreen(edgeP2.x + shiftX, edgeP2.y + shiftY);
              final guidePaint = Paint()
                ..color = guideColor.withValues(alpha: 0.65)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0;

              _drawDashedLine(canvas, g1, g2, guidePaint, dash: 5.0, gap: 3.5);

              final prefix = isFlange ? 'FLANGE' : 'BEND';
              _drawDimText(canvas, Offset(ghostCenter.dx, ghostCenter.dy - 14), '$prefix GUIDE: ${effectiveDist.toStringAsFixed(1)} mm from Edge');
            }
          }
        }
      }
    }

    // 5b. Live In-Process Perforation Pattern Preview on Selected Surface (CMS Tooling)
    if (previewPerforationPattern != null) {
      final pat = previewPerforationPattern!;
      final previewPunches = pat.expandToPunches();
      final previewFill = Paint()
        ..color = const Color(0xFF0284C7).withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;
      final previewStroke = Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      for (final punch in previewPunches) {
        final poly = punch.toPolygon();
        if (poly.isNotEmpty) {
          final path = Path();
          final p0 = toScreen(poly.first.x, poly.first.y);
          path.moveTo(p0.dx, p0.dy);
          for (int i = 1; i < poly.length; i++) {
            final pi = toScreen(poly[i].x, poly[i].y);
            path.lineTo(pi.dx, pi.dy);
          }
          path.close();
          canvas.drawPath(path, previewFill);
          canvas.drawPath(path, previewStroke);
        }
      }

      // Also render preview coupler punches if present
      if (previewCouplerPunches != null) {
        final couplerFill = Paint()
          ..color = const Color(0xFF7C3AED).withValues(alpha: 0.20)
          ..style = PaintingStyle.fill;
        final couplerStroke = Paint()
          ..color = const Color(0xFF7C3AED)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;

        for (final punch in previewCouplerPunches!) {
          final poly = punch.toPolygon();
          if (poly.isNotEmpty) {
            final path = Path();
            final p0 = toScreen(poly.first.x, poly.first.y);
            path.moveTo(p0.dx, p0.dy);
            for (int i = 1; i < poly.length; i++) {
              final pi = toScreen(poly[i].x, poly[i].y);
              path.lineTo(pi.dx, pi.dy);
            }
            path.close();
            canvas.drawPath(path, couplerFill);
            canvas.drawPath(path, couplerStroke);
          }
        }
      }

      // Draw dimension text badge above pattern anchor
      final anchorScreen = toScreen(pat.anchor.x, pat.anchor.y);
      _drawDimText(
        canvas,
        Offset(anchorScreen.dx, anchorScreen.dy - 16),
        'CMS Preview: ${pat.countX}×${pat.countY} slots (${pat.slotLengthMm.toStringAsFixed(0)}×${pat.slotWidthMm.toStringAsFixed(0)}mm, pitch ${pat.pitchY.toStringAsFixed(0)}mm)',
      );
    }

    // 6. Interactive Rubber-Band Preview Line (when authoring Bend, Cut, or Draw/Modify tools)
    if (pendingBendStart != null && rubberBandEndpoint != null) {
      final p1 = toScreen(pendingBendStart!.x, pendingBendStart!.y);
      final p2 = toScreen(rubberBandEndpoint!.x, rubberBandEndpoint!.y);

      if (toolMode == StudioToolMode.drawRectangle) {
        final rectPaint = Paint()
          ..color = const Color(0xFF0F172A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        final left = math.min(p1.dx, p2.dx);
        final top = math.min(p1.dy, p2.dy);
        final w = (p2.dx - p1.dx).abs();
        final h = (p2.dy - p1.dy).abs();
        _drawDashedRect(canvas, Rect.fromLTWH(left, top, w, h), rectPaint);

        final mmW = (rubberBandEndpoint!.x - pendingBendStart!.x).abs();
        final mmH = (rubberBandEndpoint!.y - pendingBendStart!.y).abs();
        final rectSpan = TextSpan(
          text: ' ${mmW.toStringAsFixed(1)} × ${mmH.toStringAsFixed(1)} mm ',
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 10, fontWeight: FontWeight.bold),
        );
        final tpRect = TextPainter(text: rectSpan, textDirection: TextDirection.ltr)..layout();
        tpRect.paint(canvas, Offset(p2.dx + 10, p2.dy - 16));
      } else if (toolMode == StudioToolMode.drawCircle) {
        final radiusPx = (p2 - p1).distance;
        final circlePaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(p1, radiusPx, circlePaint);
        final rMm = pendingBendStart!.distanceTo(rubberBandEndpoint!);
        final circleSpan = TextSpan(
          text: ' Ø ${(rMm * 2.0).toStringAsFixed(1)} mm (R ${rMm.toStringAsFixed(1)}) ',
          style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold),
        );
        final tpCircle = TextPainter(text: circleSpan, textDirection: TextDirection.ltr)..layout();
        tpCircle.paint(canvas, Offset(p2.dx + 10, p2.dy - 16));
      } else if (toolMode == StudioToolMode.modifyMove) {
        final movePaint = Paint()
          ..color = const Color(0xFFE11D48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        _drawDashedLine(canvas, p1, p2, movePaint, dash: 5.0, gap: 4.0);
        final dx = rubberBandEndpoint!.x - pendingBendStart!.x;
        final dy = rubberBandEndpoint!.y - pendingBendStart!.y;
        final moveSpan = TextSpan(
          text: ' MOVE: ΔX=${dx.toStringAsFixed(1)} ΔY=${dy.toStringAsFixed(1)} mm ',
          style: const TextStyle(color: Color(0xFFE11D48), fontSize: 10, fontWeight: FontWeight.bold),
        );
        final tpMove = TextPainter(text: moveSpan, textDirection: TextDirection.ltr)..layout();
        tpMove.paint(canvas, Offset(p2.dx + 10, p2.dy - 16));
      } else if (toolMode == StudioToolMode.modifyMirror) {
        final mirrorPaint = Paint()
          ..color = const Color(0xFF8B5CF6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        _drawDashedLine(canvas, p1, p2, mirrorPaint, dash: 6.0, gap: 4.0);
        final mirrorSpan = const TextSpan(
          text: ' MIRROR AXIS ',
          style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold),
        );
        final tpMirror = TextPainter(text: mirrorSpan, textDirection: TextDirection.ltr)..layout();
        tpMirror.paint(canvas, Offset(p2.dx + 10, p2.dy - 16));
      } else if (toolMode == StudioToolMode.addDimension || toolMode == StudioToolMode.dragDimension) {
        final dimPaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;
        _drawDashedLine(canvas, p1, p2, dimPaint, dash: 4.0, gap: 3.0);

        // Extension witness ticks at both endpoints
        final dx = p2.dx - p1.dx;
        final dy = p2.dy - p1.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 1.0) {
          final nx = -dy / len * 8.0;
          final ny = dx / len * 8.0;
          final tickPaint = Paint()
            ..color = const Color(0xFF0284C7)
            ..strokeWidth = 1.5;
          canvas.drawLine(Offset(p1.dx - nx, p1.dy - ny), Offset(p1.dx + nx, p1.dy + ny), tickPaint);
          canvas.drawLine(Offset(p2.dx - nx, p2.dy - ny), Offset(p2.dx + nx, p2.dy + ny), tickPaint);
        }

        // Precision end dots on dimension line endpoints
        final endDotPaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..style = PaintingStyle.fill;
        final endDotCore = Paint()..color = Colors.white;

        // Locked Entity A halo ring
        final lockedAHalo = Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(p1, 7.0, lockedAHalo);

        canvas.drawCircle(p1, 3.5, endDotPaint);
        canvas.drawCircle(p1, 1.3, endDotCore);
        canvas.drawCircle(p2, 3.5, endDotPaint);
        canvas.drawCircle(p2, 1.3, endDotCore);

        final distMm = pendingBendStart!.distanceTo(rubberBandEndpoint!);
        bool isAlt = false;
        try {
          isAlt = HardwareKeyboard.instance.isAltPressed;
        } catch (_) {}
        final dimSpan = TextSpan(
          text: ' DIM: ${distMm.toStringAsFixed(1)} mm ${isAlt ? "(Alt Free)" : ""}',
          style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold),
        );
        final tpDim = TextPainter(text: dimSpan, textDirection: TextDirection.ltr)..layout();

        // Place dimension text closer to the invisible drawn line, centered at midpoint
        final mid = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);
        final textBgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(mid.dx, mid.dy - tpDim.height / 2.0 - 4.0), width: tpDim.width + 8.0, height: tpDim.height + 3.0),
          const Radius.circular(3.0),
        );
        canvas.drawRRect(textBgRect, Paint()..color = Colors.white.withValues(alpha: 0.9));
        canvas.drawRRect(
          textBgRect,
          Paint()
            ..color = const Color(0xFF0284C7).withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        tpDim.paint(canvas, Offset(mid.dx - tpDim.width / 2.0, mid.dy - tpDim.height - 4.0));
      } else {
        final isCut = toolMode == StudioToolMode.addCut;
        final isFlange = toolMode == StudioToolMode.addFlange;
        final rubberColor = isCut ? const Color(0xFF0F172A) : (isFlange ? const Color(0xFF8B5CF6) : const Color(0xFF0284C7));
        final rubberPaint = Paint()
          ..color = rubberColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        _drawDashedLine(canvas, p1, p2, rubberPaint, dash: 5.0, gap: 4.0);

        // Angle indicator calculation
        final dx = rubberBandEndpoint!.x - pendingBendStart!.x;
        final dy = rubberBandEndpoint!.y - pendingBendStart!.y;
        bool isAlt = false;
        try {
          isAlt = HardwareKeyboard.instance.isAltPressed;
        } catch (_) {}
        final angleDeg = (math.atan2(dy, dx) * 180.0 / math.pi).round();
        final prefix = isCut ? "CUT" : (isFlange ? "FLANGE" : "BEND");
        final angleText = '$prefix ${angleDeg.abs()}° ${isAlt ? "(Alt Free)" : ""}';

        final angleSpan = TextSpan(
          text: ' $angleText ',
          style: TextStyle(color: rubberColor, fontSize: 10, fontWeight: FontWeight.bold),
        );
        final tpAngle = TextPainter(text: angleSpan, textDirection: TextDirection.ltr)..layout();
        tpAngle.paint(canvas, Offset(p2.dx + 10, p2.dy - 16));
      }
    }

    // 6b. Interactive Multi-Point Rubber-Band Preview (for Polyline and Arc drafting)
    if (pendingMultiPoints.isNotEmpty) {
      if (toolMode == StudioToolMode.drawPolyline) {
        final polyStrokePaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4;
        final polyFillNodePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        final polyBorderNodePaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        // 1. Draw already-placed segments
        for (int i = 0; i < pendingMultiPoints.length - 1; i++) {
          final sA = toScreen(pendingMultiPoints[i].x, pendingMultiPoints[i].y);
          final sB = toScreen(pendingMultiPoints[i + 1].x, pendingMultiPoints[i + 1].y);
          canvas.drawLine(sA, sB, polyStrokePaint);
        }

        // 2. Draw placed vertex nodes
        for (int i = 0; i < pendingMultiPoints.length; i++) {
          final sPt = toScreen(pendingMultiPoints[i].x, pendingMultiPoints[i].y);
          canvas.drawCircle(sPt, 4.5, polyFillNodePaint);
          canvas.drawCircle(sPt, 4.5, polyBorderNodePaint);
          canvas.drawCircle(sPt, 2.0, polyStrokePaint);
        }

        // 3. Dynamic rubber-band line to cursor
        if (rubberBandEndpoint != null) {
          final lastPt = pendingMultiPoints.last;
          final sLast = toScreen(lastPt.x, lastPt.y);
          final sCursor = toScreen(rubberBandEndpoint!.x, rubberBandEndpoint!.y);
          final rubberDashPaint = Paint()
            ..color = const Color(0xFF0284C7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
          _drawDashedLine(canvas, sLast, sCursor, rubberDashPaint, dash: 5.0, gap: 4.0);

          final segLen = lastPt.distanceTo(rubberBandEndpoint!);
          final dx = rubberBandEndpoint!.x - lastPt.x;
          final dy = rubberBandEndpoint!.y - lastPt.y;
          final angleDeg = (math.atan2(dy, dx) * 180.0 / math.pi).round();

          final isCloseSnap =
              pendingMultiPoints.length >= 2 &&
              (rubberBandEndpoint!.distanceTo(pendingMultiPoints.first) < 10.0 ||
                  (activeSnap != null && activeSnap!.point.distanceTo(pendingMultiPoints.first) < 1.0));

          if (isCloseSnap) {
            // Draw close loop preview ring and badge
            final sFirst = toScreen(pendingMultiPoints.first.x, pendingMultiPoints.first.y);
            final closeRingPaint = Paint()
              ..color = const Color(0xFF10B981)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5;
            canvas.drawCircle(sFirst, 8.0, closeRingPaint);

            const closeSpan = TextSpan(
              text: ' ⮌ Close Polyline ➔ Cutout Void ',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, backgroundColor: Color(0xFF059669)),
            );
            final tpClose = TextPainter(text: closeSpan, textDirection: TextDirection.ltr)..layout();
            tpClose.paint(canvas, Offset(sCursor.dx + 12, sCursor.dy - 18));
          } else {
            final polySpan = TextSpan(
              text: ' Polyline Pt ${pendingMultiPoints.length + 1}: ${segLen.toStringAsFixed(1)} mm | ∠ ${angleDeg.abs()}° ',
              style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold),
            );
            final tpPoly = TextPainter(text: polySpan, textDirection: TextDirection.ltr)..layout();
            tpPoly.paint(canvas, Offset(sCursor.dx + 12, sCursor.dy - 18));
          }
        }
      } else if (toolMode == StudioToolMode.drawArc) {
        final arcPaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4;
        final guidePaint = Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

        for (int i = 0; i < pendingMultiPoints.length; i++) {
          final sPt = toScreen(pendingMultiPoints[i].x, pendingMultiPoints[i].y);
          canvas.drawCircle(
            sPt,
            4.5,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(sPt, 4.5, arcPaint);
        }

        if (pendingMultiPoints.length == 1 && rubberBandEndpoint != null) {
          final p1 = pendingMultiPoints[0];
          final s1 = toScreen(p1.x, p1.y);
          final s2 = toScreen(rubberBandEndpoint!.x, rubberBandEndpoint!.y);
          _drawDashedLine(canvas, s1, s2, guidePaint, dash: 5.0, gap: 4.0);

          final chord = p1.distanceTo(rubberBandEndpoint!);
          final arcSpan = TextSpan(
            text: ' ARC Pt 2 (Through Point) | Chord: ${chord.toStringAsFixed(1)} mm ',
            style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold),
          );
          final tpArc = TextPainter(text: arcSpan, textDirection: TextDirection.ltr)..layout();
          tpArc.paint(canvas, Offset(s2.dx + 12, s2.dy - 18));
        } else if (pendingMultiPoints.length == 2 && rubberBandEndpoint != null) {
          final p1 = pendingMultiPoints[0];
          final p2 = pendingMultiPoints[1];
          final p3 = rubberBandEndpoint!;
          final s1 = toScreen(p1.x, p1.y);
          final s2 = toScreen(p2.x, p2.y);
          final s3 = toScreen(p3.x, p3.y);

          _drawDashedLine(canvas, s1, s2, guidePaint, dash: 4.0, gap: 4.0);
          _drawDashedLine(canvas, s2, s3, guidePaint, dash: 4.0, gap: 4.0);

          try {
            final previewArc = CadArc2D.from3Points(id: 'preview_arc', p1: p1, p2: p2, p3: p3);
            final samples = previewArc.samplePoints(24);
            if (samples.length >= 2) {
              final arcPath = Path();
              final s0 = toScreen(samples.first.x, samples.first.y);
              arcPath.moveTo(s0.dx, s0.dy);
              for (int i = 1; i < samples.length; i++) {
                final si = toScreen(samples[i].x, samples[i].y);
                arcPath.lineTo(si.dx, si.dy);
              }
              canvas.drawPath(arcPath, arcPaint);
            }

            final arcSpan = TextSpan(
              text:
                  ' ARC Pt 3 (End) | R: ${previewArc.radius.toStringAsFixed(1)} mm | Sweep: ${(previewArc.sweepAngleRad * 180.0 / math.pi).abs().toStringAsFixed(1)}° ',
              style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold),
            );
            final tpArc = TextPainter(text: arcSpan, textDirection: TextDirection.ltr)..layout();
            tpArc.paint(canvas, Offset(s3.dx + 12, s3.dy - 18));
          } catch (_) {
            _drawDashedLine(canvas, s1, s3, guidePaint, dash: 4.0, gap: 4.0);
          }
        }
      }
    }

    // 7. Hovered Endpoint Halo Glow (SS4 - Subtle minor indicator)
    if (hoveredEndpoint != null) {
      final hp = toScreen(hoveredEndpoint!.x, hoveredEndpoint!.y);
      final hoverGlow = Paint()
        ..color = const Color(0xFF0284C7).withValues(alpha: 0.14)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(hp, 5.0, hoverGlow);

      final hoverRing = Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      canvas.drawCircle(hp, 3.5, hoverRing);

      final hoverDot = Paint()..color = const Color(0xFF0284C7);
      canvas.drawCircle(hp, 1.5, hoverDot);
    }

    // 8. Magnetic Snap Target Crosshair & Edge Snapping Highlight (SS4 - Subtle minor indicator)
    if (activeSnap != null) {
      // If snapping to an edge/cut line, highlight the snapped edge
      if (activeSnap!.segmentStart != null && activeSnap!.segmentEnd != null) {
        final e1 = toScreen(activeSnap!.segmentStart!.x, activeSnap!.segmentStart!.y);
        final e2 = toScreen(activeSnap!.segmentEnd!.x, activeSnap!.segmentEnd!.y);
        final edgeGlow = Paint()
          ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(e1, e2, edgeGlow);

        final edgeLine = Paint()
          ..color = const Color(0xFF0284C7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(e1, e2, edgeLine);
      }

      final snapPt = toScreen(activeSnap!.point.x, activeSnap!.point.y);

      // Polar / Ortho tracking line from anchor through cursor
      if (activeSnap!.trackingAnchor != null) {
        final anchorPt = toScreen(activeSnap!.trackingAnchor!.x, activeSnap!.trackingAnchor!.y);
        final trackingPaint = Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85;
        _drawDashedLine(canvas, anchorPt, snapPt, trackingPaint, dash: 4.0, gap: 3.0);

        // Tracking anchor small dot
        canvas.drawCircle(anchorPt, 1.8, Paint()..color = const Color(0xFF0284C7));
      }

      // Draw specialized CAD snap glyph
      _drawSnapGlyph(canvas, snapPt, activeSnap!.type, activeSnap!.label);
    }

    // 8c. Pre-Click Cursor Snap Indicator Dot for all drawing tools
    final isDrawingTool =
        toolMode == StudioToolMode.addBend ||
        toolMode == StudioToolMode.addFlange ||
        toolMode == StudioToolMode.addCut ||
        toolMode == StudioToolMode.drawPolyline ||
        toolMode == StudioToolMode.drawRectangle ||
        toolMode == StudioToolMode.drawCircle ||
        toolMode == StudioToolMode.drawArc ||
        toolMode == StudioToolMode.addPunchRound ||
        toolMode == StudioToolMode.addPunchSquare ||
        toolMode == StudioToolMode.addPunchObround ||
        toolMode == StudioToolMode.dragDimension ||
        toolMode == StudioToolMode.addDimension;

    if (isDrawingTool && hoverCursorCad != null) {
      final rawScreen = toScreen(hoverCursorCad!.x, hoverCursorCad!.y);
      final bool hasSnap = !isAltPressed && activeSnap != null;
      final effectiveScreen = hasSnap ? toScreen(activeSnap!.point.x, activeSnap!.point.y) : rawScreen;

      if (hasSnap) {
        // Snapped state: draw a dynamic magnetic tether line if cursor is offset
        if ((rawScreen - effectiveScreen).distance > 2.0) {
          final tetherPaint = Paint()
            ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;
          _drawDashedLine(canvas, rawScreen, effectiveScreen, tetherPaint, dash: 3.0, gap: 2.0);
        }

        // Concentric target halo ring
        final snapRingPaint = Paint()
          ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(effectiveScreen, 6.0, snapRingPaint);

        // Core dot
        final snapCorePaint = Paint()..color = const Color(0xFF0284C7);
        canvas.drawCircle(effectiveScreen, 3.2, snapCorePaint);

        // Center white precision pip
        canvas.drawCircle(effectiveScreen, 1.2, Paint()..color = Colors.white);
      } else {
        // Free state (either Alt is held or no snap point nearby)
        if (isAltPressed) {
          // Alt Free indicator dot
          final altRingPaint = Paint()
            ..color = const Color(0xFFF97316).withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6;
          canvas.drawCircle(rawScreen, 5.5, altRingPaint);

          final altCorePaint = Paint()..color = const Color(0xFFF97316);
          canvas.drawCircle(rawScreen, 2.8, altCorePaint);
          canvas.drawCircle(rawScreen, 1.0, Paint()..color = Colors.white);

          // "Alt Free" mini tag
          final tagSpan = TextSpan(
            text: ' Alt Free ',
            style: const TextStyle(color: Color(0xFFF97316), fontSize: 9.0, fontWeight: FontWeight.bold),
          );
          final tpTag = TextPainter(text: tagSpan, textDirection: TextDirection.ltr)..layout();
          tpTag.paint(canvas, Offset(rawScreen.dx + 8, rawScreen.dy - 14));
        } else {
          // Normal hovering dot on mouse pointer
          final normRingPaint = Paint()
            ..color = const Color(0xFF0284C7).withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2;
          canvas.drawCircle(rawScreen, 4.5, normRingPaint);

          final normCorePaint = Paint()..color = const Color(0xFF0284C7);
          canvas.drawCircle(rawScreen, 2.5, normCorePaint);
          canvas.drawCircle(rawScreen, 0.9, Paint()..color = Colors.white);
        }
      }
    }

    // 8b. Window & Crossing Selection Box Rendering
    if (boxSelectStart != null && boxSelectCurrent != null) {
      final rect = Rect.fromPoints(boxSelectStart!, boxSelectCurrent!);
      final isWindow = boxSelectCurrent!.dx >= boxSelectStart!.dx;

      if (isWindow) {
        // Window Selection (Left-to-Right): Translucent Blue with Solid Border
        final fillPaint = Paint()
          ..color = const Color(0x282563EB)
          ..style = PaintingStyle.fill;
        final borderPaint = Paint()
          ..color = const Color(0xFF2563EB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);

        _drawSelectionTag(canvas, rect.topLeft, 'WINDOW (INSIDE)', const Color(0xFF2563EB));
      } else {
        // Crossing Selection (Right-to-Left): Translucent Green with Dashed Border
        final fillPaint = Paint()
          ..color = const Color(0x2810B981)
          ..style = PaintingStyle.fill;
        final borderPaint = Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRect(rect, fillPaint);
        _drawDashedRect(canvas, rect, borderPaint);

        _drawSelectionTag(canvas, rect.topRight, 'CROSSING (TOUCHES)', const Color(0xFF10B981));
      }
    }

    // 10. Engineering CAD Outside Dimensions & Hole Leaders (Matching SS1)
    if (showDimensions) {
      _drawOutsideDimensions(canvas, doc, toScreen, scale);
    }

    // 10b. Product Port Opening Badges (W x H dimensions at openings for Tees, Reducers, Bends, Crosses)
    if (showOpeningTags && fittingMetadata != null) {
      _drawPortOpeningBadges(canvas, doc, toScreen, scale);
    }

    // 10c. Interactive Contour Edge Hover & Pick Highlight
    if (hoveredContourEdgeP1 != null && hoveredContourEdgeP2 != null) {
      final hp1 = toScreen(hoveredContourEdgeP1!.x, hoveredContourEdgeP1!.y);
      final hp2 = toScreen(hoveredContourEdgeP2!.x, hoveredContourEdgeP2!.y);

      // Check if this edge is already assigned to any port (width or height flap)
      String? assignedLabel;
      if (fittingMetadata != null) {
        final manual = fittingMetadata!.manualPortEdges ?? {};
        for (final entry in manual.entries) {
          final pId = entry.key;
          final pData = entry.value;
          final pNum = pId.replaceAll('port', '');
          final pName = pId == 'port1' ? 'Port 1' : (pId == 'port2' ? 'Port 2' : 'Port $pNum');

          final wEdge = pData['widthEdge'] as Map?;
          if (wEdge != null && wEdge['p1'] is List && wEdge['p2'] is List) {
            final p1List = (wEdge['p1'] as List).map((n) => (n as num).toDouble()).toList();
            final p2List = (wEdge['p2'] as List).map((n) => (n as num).toDouble()).toList();
            if (p1List.length >= 2 && p2List.length >= 2) {
              if (SheetMetalStudioViewModel.isSameCadEdge(
                hoveredContourEdgeP1!,
                hoveredContourEdgeP2!,
                CadPoint2D(p1List[0], p1List[1]),
                CadPoint2D(p2List[0], p2List[1]),
              )) {
                assignedLabel = '$pName Width';
                break;
              }
            }
          }

          final hEdges = pData['heightEdges'] as List?;
          if (hEdges != null) {
            for (final hEdge in hEdges) {
              if (hEdge is Map && hEdge['p1'] is List && hEdge['p2'] is List) {
                final p1List = (hEdge['p1'] as List).map((n) => (n as num).toDouble()).toList();
                final p2List = (hEdge['p2'] as List).map((n) => (n as num).toDouble()).toList();
                if (p1List.length >= 2 && p2List.length >= 2) {
                  if (SheetMetalStudioViewModel.isSameCadEdge(
                    hoveredContourEdgeP1!,
                    hoveredContourEdgeP2!,
                    CadPoint2D(p1List[0], p1List[1]),
                    CadPoint2D(p2List[0], p2List[1]),
                  )) {
                    assignedLabel = '$pName Height Flap';
                    break;
                  }
                }
              }
            }
          }
          if (assignedLabel != null) break;
        }
      }

      final isAssigned = assignedLabel != null;
      final isPickMode = toolMode == StudioToolMode.pickPortEdge;

      final Color accentColor;
      if (isPickMode) {
        accentColor = isAssigned ? const Color(0xFFEF4444) : const Color(0xFF0284C7);
      } else {
        accentColor = isAssigned ? const Color(0xFF0D9488) : const Color(0xFF0284C7);
      }

      // 1. Radiant Outer Glow
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.35)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(hp1, hp2, glowPaint);

      // 2. High-Precision Core Line
      final corePaint = Paint()
        ..color = accentColor
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(hp1, hp2, corePaint);

      // 3. CAD Vertex Handles at Edge Endpoints (Clear segment boundaries)
      final vertexOuterPaint = Paint()..color = accentColor;
      final vertexInnerPaint = Paint()..color = Colors.white;
      canvas.drawCircle(hp1, 4.5, vertexOuterPaint);
      canvas.drawCircle(hp1, 2.5, vertexInnerPaint);
      canvas.drawCircle(hp2, 4.5, vertexOuterPaint);
      canvas.drawCircle(hp2, 2.5, vertexInnerPaint);

      // 4. Floating Callout Dimension Badge
      final hCenter = Offset((hp1.dx + hp2.dx) / 2.0, (hp1.dy + hp2.dy) / 2.0);
      final lenText = '${hoveredContourEdgeLengthMm?.toStringAsFixed(1) ?? '--'} mm';

      final String badgeText;
      if (isPickMode) {
        badgeText = isAssigned ? ' ⚠️ Already Assigned ($assignedLabel) ' : ' 🎯 Click to Assign: $lenText ';
      } else {
        badgeText = isAssigned ? ' ✓ $assignedLabel: $lenText ' : ' Edge: $lenText ';
      }

      final span = TextSpan(
        text: badgeText,
        style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(hCenter.dx, hCenter.dy - 16.0), width: tp.width + 12, height: tp.height + 6),
        const Radius.circular(4),
      );
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawRRect(badgeRect.shift(const Offset(0, 1)), shadowPaint);
      final badgeBgPaint = Paint()..color = accentColor;
      canvas.drawRRect(badgeRect, badgeBgPaint);
      tp.paint(canvas, Offset(hCenter.dx - tp.width / 2.0, hCenter.dy - 16.0 - tp.height / 2.0));
    }

    // 11. Live Angle HUD when dragging line endpoints
    if (dragAngleInfo != null) {
      final p = toScreen(dragAngleInfo!.point.x, dragAngleInfo!.point.y);
      final angleSpan = TextSpan(
        text: ' ${dragAngleInfo!.label} ',
        style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold),
      );
      final tpAngle = TextPainter(text: angleSpan, textDirection: TextDirection.ltr)..layout();
      tpAngle.paint(canvas, Offset(p.dx + 12, p.dy - 18));
    }

    // 12. Parametric Reference / Construction Geometry (Centerlines, Offsets, Symmetries)
    if (showConstructionGeometry && referenceGeometries.isNotEmpty) {
      CanvasReferencePainter.paint(canvas: canvas, size: size, references: referenceGeometries, cadToScreen: (pt) => toScreen(pt.x, pt.y));
    }

    if (showConstraints && constraintDefinitions.isNotEmpty) {
      CanvasConstraintPainter.paint(
        canvas: canvas,
        size: size,
        document: doc,
        constraints: constraintDefinitions,
        cadToScreen: (pt) => toScreen(pt.x, pt.y),
        selectedConstraintId: selectedConstraintId,
        hoveredConstraintId: hoveredConstraintId,
        renderedConstraintBadges: renderedConstraintBadges,
        customReferences: referenceGeometries,
      );
    }

    // 14. Semantic Port Inference Live Preview HUD & Canvas Highlighting
    if (activePortInferenceResult != null) {
      _paintSemanticPortPreview(canvas, size, toScreen, scale);
    }
  }

  void _drawHandle(Canvas canvas, Offset pos) {
    final fill = Paint()..color = Colors.white;
    final border = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85;
    final inner = Paint()..color = const Color(0xFF2563EB);

    canvas.drawCircle(pos, 2.8, fill);
    canvas.drawCircle(pos, 2.8, border);
    canvas.drawCircle(pos, 1.2, inner);
  }

  void _drawCutBadge(Canvas canvas, Offset pos, String id, bool isSelected, {double? lengthMm, bool showLabel = true}) {
    if (!showLabel) return;
    final label = lengthMm != null ? ' CUT $id ${lengthMm.toStringAsFixed(1)}mm ' : ' CUT $id ';
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF0F172A), fontSize: 9, fontWeight: FontWeight.bold),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    final badgeWidth = tp.width + 6.0;
    final badgeHeight = tp.height + 4.0;
    final badgeRect = Rect.fromCenter(center: pos, width: badgeWidth, height: badgeHeight);
    final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(3.0));

    final bgPaint = Paint()
      ..color = isSelected ? const Color(0xFFEFF6FF) : Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    final borderPaint = Paint()
      ..color = isSelected ? const Color(0xFF3B82F6) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(rrect, borderPaint);

    tp.paint(canvas, Offset(pos.dx - tp.width / 2.0, pos.dy - tp.height / 2.0));
  }

  void _drawFaceSizeBadge(Canvas canvas, Offset center, String label, double widthMm, double heightMm, bool isSelected) {
    final style = canvasSettings.faceLabel;
    final dimStr = formatDimPair(widthMm, heightMm, canvasSettings);
    final text = '$label: $dimStr';
    final span = TextSpan(
      text: text,
      style: TextStyle(color: isSelected ? const Color(0xFF1E3A8A) : style.color, fontSize: style.fontSize, fontWeight: style.fontWeight, letterSpacing: 0.2),
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    final badgeWidth = tp.width + 12.0;
    final badgeHeight = tp.height + 6.0;
    final badgeRect = Rect.fromCenter(center: center, width: badgeWidth, height: badgeHeight);
    final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(4.0));

    // Drop shadow
    canvas.drawRRect(
      rrect.shift(const Offset(0, 1.0)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    // Background
    final bgPaint = Paint()
      ..color = isSelected ? const Color(0xFFFEF3C7).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = isSelected ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 1.4 : 0.8;
    canvas.drawRRect(rrect, borderPaint);

    tp.paint(canvas, Offset(badgeRect.left + 6.0, badgeRect.top + 3.0));
  }

  static Set<int> _findIntermediateArcIndices(List<CadPoint2D> pts) {
    final n = pts.length;
    if (n < 4) return const {};

    final intermediate = <int>{};
    for (int i = 0; i < n; i++) {
      final p0 = pts[i];
      final p1 = pts[(i + 1) % n];
      final p2 = pts[(i + 2) % n];
      final p3 = pts[(i + 3) % n];

      final c1 = _circumcircle(p0, p1, p2);
      final c2 = _circumcircle(p1, p2, p3);

      if (c1 != null && c2 != null) {
        final dx = c1.x - c2.x;
        final dy = c1.y - c2.y;
        final distC = math.sqrt(dx * dx + dy * dy);
        final diffR = (c1.radius - c2.radius).abs();
        if (distC < 0.8 && diffR < 0.8 && c1.radius >= 1.0 && c1.radius <= 5000.0) {
          intermediate.add((i + 1) % n);
          intermediate.add((i + 2) % n);
        }
      }
    }
    return intermediate;
  }

  static ({double x, double y, double radius})? _circumcircle(CadPoint2D p1, CadPoint2D p2, CadPoint2D p3) {
    final d = 2 * (p1.x * (p2.y - p3.y) + p2.x * (p3.y - p1.y) + p3.x * (p1.y - p2.y));
    if (d.abs() < 1e-4) return null;
    final p1Sq = p1.x * p1.x + p1.y * p1.y;
    final p2Sq = p2.x * p2.x + p2.y * p2.y;
    final p3Sq = p3.x * p3.x + p3.y * p3.y;
    final ux = (p1Sq * (p2.y - p3.y) + p2Sq * (p3.y - p1.y) + p3Sq * (p1.y - p2.y)) / d;
    final uy = (p1Sq * (p3.x - p2.x) + p2Sq * (p1.x - p3.x) + p3Sq * (p2.x - p1.x)) / d;
    final rx = ux - p1.x;
    final ry = uy - p1.y;
    final r = math.sqrt(rx * rx + ry * ry);
    return (x: ux, y: uy, radius: r);
  }

  void _drawGrid(Canvas canvas, Size size, Offset pan) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.8;

    final majorGridPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.0;

    const step = 40.0;
    const majorStep = step * 5.0; // 200.0

    final offsetX = (pan.dx % step);
    final offsetY = (pan.dy % step);

    for (double x = offsetX - step; x <= size.width + step; x += step) {
      final globalX = x - pan.dx;
      final isMajor = (globalX.round() % majorStep.round()).abs() < 1.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), isMajor ? majorGridPaint : gridPaint);
    }
    for (double y = offsetY - step; y <= size.height + step; y += step) {
      final globalY = y - pan.dy;
      final isMajor = (globalY.round() % majorStep.round()).abs() < 1.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), isMajor ? majorGridPaint : gridPaint);
    }
  }

  void _drawSnapGlyph(Canvas canvas, Offset snapPt, SnapType type, String label) {
    final strokePaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85;
    final fillPaint = Paint()
      ..color = const Color(0xFF0284C7).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    if (type.isEndpoint) {
      // Subtle Square 🔲 (Endpoint snap - minor 6x6)
      final rect = Rect.fromCenter(center: snapPt, width: 6, height: 6);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, strokePaint);
    } else if (type.isMidpoint) {
      // Subtle Triangle 🔺 (Midpoint snap - minor)
      final path = Path()
        ..moveTo(snapPt.dx, snapPt.dy - 3.5)
        ..lineTo(snapPt.dx + 3.5, snapPt.dy + 3.0)
        ..lineTo(snapPt.dx - 3.5, snapPt.dy + 3.0)
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    } else if (type.isCenter) {
      // Circle with center dot ⭕ (Center snap - minor)
      canvas.drawCircle(snapPt, 3.5, fillPaint);
      canvas.drawCircle(snapPt, 3.5, strokePaint);
      canvas.drawCircle(snapPt, 1.0, Paint()..color = const Color(0xFF0284C7));
    } else if (type.isIntersection) {
      // 'X' Cross ✖ (Intersection snap - minor 6x6)
      canvas.drawLine(Offset(snapPt.dx - 3.0, snapPt.dy - 3.0), Offset(snapPt.dx + 3.0, snapPt.dy + 3.0), strokePaint);
      canvas.drawLine(Offset(snapPt.dx - 3.0, snapPt.dy + 3.0), Offset(snapPt.dx + 3.0, snapPt.dy - 3.0), strokePaint);
    } else if (type == SnapType.perpendicular) {
      // Right angle ⟂ (minor)
      final path = Path()
        ..moveTo(snapPt.dx - 3.5, snapPt.dy + 3.5)
        ..lineTo(snapPt.dx + 3.5, snapPt.dy + 3.5)
        ..moveTo(snapPt.dx, snapPt.dy + 3.5)
        ..lineTo(snapPt.dx, snapPt.dy - 3.5)
        ..moveTo(snapPt.dx, snapPt.dy + 1.2)
        ..lineTo(snapPt.dx + 2.3, snapPt.dy + 1.2)
        ..lineTo(snapPt.dx + 2.3, snapPt.dy + 3.5);
      canvas.drawPath(path, strokePaint);
    } else if (type == SnapType.tangent) {
      // Circle with tangent bar (minor)
      canvas.drawCircle(Offset(snapPt.dx, snapPt.dy + 1.0), 3.0, strokePaint);
      canvas.drawLine(Offset(snapPt.dx - 3.5, snapPt.dy - 2.5), Offset(snapPt.dx + 3.5, snapPt.dy - 2.5), strokePaint);
    } else if (type == SnapType.quadrant) {
      // Diamond 🔷 (minor)
      final path = Path()
        ..moveTo(snapPt.dx, snapPt.dy - 3.5)
        ..lineTo(snapPt.dx + 3.5, snapPt.dy)
        ..lineTo(snapPt.dx, snapPt.dy + 3.5)
        ..lineTo(snapPt.dx - 3.5, snapPt.dy)
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    } else if (type == SnapType.grid) {
      // Grid plus '+' (minor)
      canvas.drawLine(Offset(snapPt.dx - 3.0, snapPt.dy), Offset(snapPt.dx + 3.0, snapPt.dy), strokePaint);
      canvas.drawLine(Offset(snapPt.dx, snapPt.dy - 3.0), Offset(snapPt.dx, snapPt.dy + 3.0), strokePaint);
    } else {
      // Nearest / Bowtie ⧗ (minor)
      final path = Path()
        ..moveTo(snapPt.dx - 3.0, snapPt.dy - 3.0)
        ..lineTo(snapPt.dx + 3.0, snapPt.dy - 3.0)
        ..lineTo(snapPt.dx - 3.0, snapPt.dy + 3.0)
        ..lineTo(snapPt.dx + 3.0, snapPt.dy + 3.0)
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }

    // Subtle snap label with Onshape anchor symbol prefix
    String symbolPrefix = '';
    if (type.isCenter) {
      symbolPrefix = '⊙ ';
    } else if (type.isMidpoint) {
      symbolPrefix = '⌖ ';
    } else if (type.isEndpoint) {
      symbolPrefix = '• ';
    } else if (type == SnapType.quadrant) {
      symbolPrefix = '◇ ';
    } else if (type == SnapType.perpendicular) {
      symbolPrefix = '⊥ ';
    }
    final displayLabel = symbolPrefix.isNotEmpty && !label.startsWith(symbolPrefix) ? '$symbolPrefix$label' : label;

    final textSpan = TextSpan(
      text: displayLabel,
      style: TextStyle(color: const Color(0xFF0284C7), fontSize: 7.5, fontWeight: FontWeight.w600),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(snapPt.dx + 6, snapPt.dy - 11));
  }

  void _drawSelectionTag(Canvas canvas, Offset pos, String label, Color color) {
    final textSpan = TextSpan(
      text: ' $label ',
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(pos.dx + 4, pos.dy - 14));
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint, {double dash = 6.0, double gap = 4.0}) {
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dash: dash, gap: gap);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dash: dash, gap: gap);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint, dash: dash, gap: gap);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint, dash: dash, gap: gap);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {double dash = 6.0, double gap = 4.0}) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalLen = math.sqrt(dx * dx + dy * dy);
    if (totalLen < 1e-4) return;

    final ux = dx / totalLen;
    final uy = dy / totalLen;

    double d = 0.0;
    while (d < totalLen) {
      final segLen = math.min(dash, totalLen - d);
      final start = Offset(p1.dx + ux * d, p1.dy + uy * d);
      final end = Offset(start.dx + ux * segLen, start.dy + uy * segLen);
      canvas.drawLine(start, end, paint);
      d += dash + gap;
    }
  }

  void _drawDimText(Canvas canvas, Offset pos, String text) {
    if (!canvasSettings.dimTextLabel.visible) return;
    final style = canvasSettings.dimTextLabel;
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: style.color, fontSize: style.fontSize, fontWeight: style.fontWeight),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2.0, pos.dy - tp.height / 2.0));
  }

  // --- Engineering CAD Outside Dimensions & Hole Leaders (Matching SS1) ---

  void _drawOutsideDimensions(Canvas canvas, DsfDocument doc, Offset Function(double x, double y) toScreen, double scale) {
    final allPoints = <CadPoint2D>[];
    final visibleFaces = doc.faces.where((f) => f.isVisible).toList();
    if (doc.outerContour.isNotEmpty) {
      allPoints.addAll(doc.outerContour);
    } else if (visibleFaces.isNotEmpty) {
      for (final f in visibleFaces) {
        allPoints.addAll(f.vertices);
      }
    }
    if (allPoints.isEmpty) return;

    double minX = allPoints.first.x, maxX = allPoints.first.x;
    double minY = allPoints.first.y, maxY = allPoints.first.y;
    for (final p in allPoints) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final blankW = maxX - minX;
    final blankL = maxY - minY;
    if (blankW < 1.0 && blankL < 1.0) return;

    // Draw Crosshairs on all circular punches
    _drawHoleCrosshairs(canvas, doc, toScreen, scale);

    if (canvasSettings.outsideDimLabel.visible && canvasSettings.showDimensions) {
      // Dimension lines styling
      const dimChain1 = 26.0; // Inner step dimension chain offset
      const dimChain2 = 54.0; // Outer overall dimension chain offset

      // --- BOTTOM DIMENSION CHAIN (X Axis Widths) ---
      final bScreenY1 = toScreen(0, minY).dy + dimChain1;
      final bScreenY2 = toScreen(0, minY).dy + dimChain2;

      // Overall Blank Width (Bottom outer line)
      _drawLinearDimension(
        canvas,
        p1Screen: toScreen(minX, minY),
        p2Screen: toScreen(maxX, minY),
        dimScreenCoord: bScreenY2 + 8.0,
        isVertical: false,
        valueText: formatMeasure(blankW, canvasSettings),
        dimId: 'dim_blank_w',
        ptA: CadPoint2D(minX, minY),
        ptB: CadPoint2D(maxX, minY),
        scale: scale,
      );

      // Key intermediate X coordinates from vertical bends or notches
      final xBends =
          doc.bends
              .where((b) => b.isVisible && (b.p1.x - b.p2.x).abs() < 1e-2)
              .map((b) => b.p1.x)
              .where((x) => x > minX + 3.0 && x < maxX - 3.0)
              .toSet()
              .toList()
            ..sort();

      if (xBends.isNotEmpty) {
        double curX = minX;
        int stepIdx = 0;
        for (final bx in xBends) {
          final stepW = bx - curX;
          if (stepW > 3.0) {
            // Automatic smart vertical staggering for narrow steps so adjacent badges never collide!
            final stagger = (stepIdx % 2 == 1) ? 18.0 : 0.0;
            _drawLinearDimension(
              canvas,
              p1Screen: toScreen(curX, minY),
              p2Screen: toScreen(bx, minY),
              dimScreenCoord: bScreenY1 + stagger,
              isVertical: false,
              valueText: formatMeasure(stepW, canvasSettings),
              dimId: 'dim_step_x_$stepIdx',
              ptA: CadPoint2D(curX, minY),
              ptB: CadPoint2D(bx, minY),
              scale: scale,
            );
            curX = bx;
            stepIdx++;
          }
        }
        final remW = maxX - curX;
        if (remW > 3.0) {
          final stagger = (stepIdx % 2 == 1) ? 18.0 : 0.0;
          _drawLinearDimension(
            canvas,
            p1Screen: toScreen(curX, minY),
            p2Screen: toScreen(maxX, minY),
            dimScreenCoord: bScreenY1 + stagger,
            isVertical: false,
            valueText: formatMeasure(remW, canvasSettings),
            dimId: 'dim_step_x_$stepIdx',
            ptA: CadPoint2D(curX, minY),
            ptB: CadPoint2D(maxX, minY),
            scale: scale,
          );
        }
      }

      // --- LEFT DIMENSION CHAIN (Y Axis Lengths/Heights) ---
      final lScreenX1 = toScreen(minX, 0).dx - dimChain1;
      final lScreenX2 = toScreen(minX, 0).dx - dimChain2;

      // Overall Blank Length (Left outer line)
      _drawLinearDimension(
        canvas,
        p1Screen: toScreen(minX, minY),
        p2Screen: toScreen(minX, maxY),
        dimScreenCoord: lScreenX2 - 8.0,
        isVertical: true,
        valueText: formatMeasure(blankL, canvasSettings),
        dimId: 'dim_blank_l',
        ptA: CadPoint2D(minX, minY),
        ptB: CadPoint2D(minX, maxY),
        scale: scale,
      );

      // Key intermediate Y coordinates from horizontal bends or notches
      final yBends =
          doc.bends
              .where((b) => b.isVisible && (b.p1.y - b.p2.y).abs() < 1e-2)
              .map((b) => b.p1.y)
              .where((y) => y > minY + 3.0 && y < maxY - 3.0)
              .toSet()
              .toList()
            ..sort();

      if (yBends.isNotEmpty) {
        double curY = minY;
        int stepIdx = 0;
        for (final by in yBends) {
          final stepH = by - curY;
          if (stepH > 3.0) {
            final stagger = (stepIdx % 2 == 1) ? -18.0 : 0.0;
            _drawLinearDimension(
              canvas,
              p1Screen: toScreen(minX, curY),
              p2Screen: toScreen(minX, by),
              dimScreenCoord: lScreenX1 + stagger,
              isVertical: true,
              valueText: formatMeasure(stepH, canvasSettings),
              dimId: 'dim_step_y_$stepIdx',
              ptA: CadPoint2D(minX, curY),
              ptB: CadPoint2D(minX, by),
              scale: scale,
            );
            curY = by;
            stepIdx++;
          }
        }
        final remH = maxY - curY;
        if (remH > 3.0) {
          final stagger = (stepIdx % 2 == 1) ? -18.0 : 0.0;
          _drawLinearDimension(
            canvas,
            p1Screen: toScreen(minX, curY),
            p2Screen: toScreen(minX, maxY),
            dimScreenCoord: lScreenX1 + stagger,
            isVertical: true,
            valueText: formatMeasure(remH, canvasSettings),
            dimId: 'dim_step_y_$stepIdx',
            ptA: CadPoint2D(minX, curY),
            ptB: CadPoint2D(minX, maxY),
            scale: scale,
          );
        }
      }

      // --- RIGHT DIMENSION CHAIN (Hole centers & feature spacing) ---
      // Parametric patterns: dimensions shown for ONLY 1 SET (first pitch interval) + margins
      final punchesWithUniqueY = doc.allPunches.map((p) => p.center.y).toSet().toList()..sort();
      if (punchesWithUniqueY.isNotEmpty) {
        final rScreenX = toScreen(maxX, 0).dx + dimChain1;

        // 1. Margin from bottom edge to first punch
        final firstY = punchesWithUniqueY.first;
        final bottomMargin = firstY - minY;
        if (bottomMargin > 3.0) {
          _drawLinearDimension(
            canvas,
            p1Screen: toScreen(maxX, minY),
            p2Screen: toScreen(maxX, firstY),
            dimScreenCoord: rScreenX,
            isVertical: true,
            valueText: formatMeasure(bottomMargin, canvasSettings),
            dimId: 'dim_punch_margin_bottom',
            ptA: CadPoint2D(maxX, minY),
            ptB: CadPoint2D(maxX, firstY),
            scale: scale,
          );
        }

        // 2. Punch step dimensions: ONLY 1 set for repeating pattern pitches!
        double? lastDrawnDy;
        int pitchSetCount = 0;
        for (int i = 0; i < punchesWithUniqueY.length - 1; i++) {
          final y1 = punchesWithUniqueY[i];
          final y2 = punchesWithUniqueY[i + 1];
          final dy = y2 - y1;
          if (dy <= 3.0) continue;

          // If this dy is identical to the previous step (e.g. repeating pattern pitch 25mm),
          // skip it so we only show 1 set for the pattern!
          if (lastDrawnDy != null && (dy - lastDrawnDy).abs() < 0.5) {
            continue;
          }

          _drawLinearDimension(
            canvas,
            p1Screen: toScreen(maxX, y1),
            p2Screen: toScreen(maxX, y2),
            dimScreenCoord: rScreenX,
            isVertical: true,
            valueText: formatMeasure(dy, canvasSettings),
            dimId: 'dim_punch_pitch_$pitchSetCount',
            ptA: CadPoint2D(maxX, y1),
            ptB: CadPoint2D(maxX, y2),
            scale: scale,
          );
          lastDrawnDy = dy;
          pitchSetCount++;
        }

        // 3. Margin from last punch to top edge
        final lastY = punchesWithUniqueY.last;
        final topMargin = maxY - lastY;
        if (topMargin > 3.0) {
          _drawLinearDimension(
            canvas,
            p1Screen: toScreen(maxX, lastY),
            p2Screen: toScreen(maxX, maxY),
            dimScreenCoord: rScreenX,
            isVertical: true,
            valueText: formatMeasure(topMargin, canvasSettings),
            dimId: 'dim_punch_margin_top',
            ptA: CadPoint2D(maxX, lastY),
            ptB: CadPoint2D(maxX, maxY),
            scale: scale,
          );
        }
      }
    }

    // --- HOLE LEADER CALLOUTS (e.g. "8 * Ø5.00", "6 * Ø20.00" as in SS1) ---
    _drawHoleLeaderCallouts(canvas, doc, toScreen, scale);

    // --- ASSOCIATIVE CAD DIMENSIONS (Step 6 #19 & Step 7 #20) ---
    _drawAssociativeDimensions(canvas, doc, toScreen, scale);

    // --- GEOMETRIC CONSTRAINTS GLYPHS (Step 8 #21) ---
    _drawGeometricConstraints(canvas, doc, toScreen, scale);
  }

  void _drawAssociativeDimensions(Canvas canvas, DsfDocument doc, Offset Function(double x, double y) toScreen, double scale) {
    if (doc.dimensions.isEmpty) return;
    if (!canvasSettings.dimTextLabel.visible) return;

    for (final dim in doc.dimensions) {
      if (!dim.isVisible) continue;

      final layout = AssociativeDimensionEngine.resolveLayout(dim, doc, scale: scale, settings: canvasSettings);
      final pA = toScreen(layout.dimLineStart.dx, layout.dimLineStart.dy);
      final pB = toScreen(layout.dimLineEnd.dx, layout.dimLineEnd.dy);
      final wA1 = toScreen(layout.witnessAStart.dx, layout.witnessAStart.dy);
      final wA2 = toScreen(layout.witnessAEnd.dx, layout.witnessAEnd.dy);
      final wB1 = toScreen(layout.witnessBStart.dx, layout.witnessBStart.dy);
      final wB2 = toScreen(layout.witnessBEnd.dx, layout.witnessBEnd.dy);
      final textPos = toScreen(layout.textCenter.dx, layout.textCenter.dy);

      final assoc = AssociativeDimensionEngine.resolveAssociation(dim, doc);
      if (renderedDimensionLines != null) {
        renderedDimensionLines![dim.id] = (pA: pA, pB: pB, offsetDist: dim.dimensionLineOffset, ptA: assoc.pA, ptB: assoc.pB, type: dim.type);
      }

      final isLineHovered = hoveredDimLineId == dim.id;

      final dimColor = dim.isDriven ? const Color(0xFF0284C7) : const Color(0xFF2563EB);

      final witnessPaint = Paint()
        ..color = const Color(0xFF64748B)
        ..strokeWidth = 0.8;

      // Witness lines
      canvas.drawLine(wA1, wA2, witnessPaint);
      canvas.drawLine(wB1, wB2, witnessPaint);

      // Origin dots on witness lines where they touch geometry
      final originDotPaint = Paint()
        ..color = const Color(0xFF64748B)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(wA1, 2.0, originDotPaint);
      canvas.drawCircle(wB1, 2.0, originDotPaint);

      // Line hover glow
      if (isLineHovered) {
        final glowPaint = Paint()
          ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.35)
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(pA, pB, glowPaint);
      }

      // Dimension line
      final dimLinePaint = Paint()
        ..color = isLineHovered ? const Color(0xFF0284C7) : dimColor
        ..strokeWidth = isLineHovered ? 2.2 : 1.1;
      canvas.drawLine(pA, pB, dimLinePaint);

      // Arrowheads
      final angleA = math.atan2(pB.dy - pA.dy, pB.dx - pA.dx);
      final angleB = math.atan2(pA.dy - pB.dy, pA.dx - pB.dx);
      _drawArrow(canvas, pA, angleA);
      _drawArrow(canvas, pB, angleB);

      // End dots on the dimension line endpoints pA and pB
      final endDotPaint = Paint()
        ..color = isLineHovered ? const Color(0xFF0284C7) : dimColor
        ..style = PaintingStyle.fill;
      final endDotCore = Paint()..color = Colors.white;
      canvas.drawCircle(pA, 3.2, endDotPaint);
      canvas.drawCircle(pA, 1.2, endDotCore);
      canvas.drawCircle(pB, 3.2, endDotPaint);
      canvas.drawCircle(pB, 1.2, endDotCore);

      // User offset if moved
      final userOffset = (dimensionOffsets.containsKey(dim.id)) ? dimensionOffsets[dim.id]! : Offset.zero;
      final effectiveCenter = textPos + userOffset;

      if (userOffset.distance > 4.0) {
        final leaderPaint = Paint()
          ..color = const Color(0xFF64748B)
          ..strokeWidth = 0.9
          ..style = PaintingStyle.stroke;
        canvas.drawLine(textPos, effectiveCenter, leaderPaint);
        final dotPaint = Paint()
          ..color = dimColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(textPos, 2.5, dotPaint);
      }

      renderedDimensionValues?[dim.id] = dim.measuredValue;
      final isDimSelected = selectedDimensionId == dim.id;
      final isDimHovered = hoveredDimensionId == dim.id;
      final badgeRect = _drawDimBadge(
        canvas,
        effectiveCenter,
        layout.displayText,
        isEditing: editingDimId == dim.id,
        isSelected: isDimSelected,
        isHovered: isDimHovered,
        style: canvasSettings.dimTextLabel,
      );
      if (renderedDimensionBadges != null) {
        renderedDimensionBadges![dim.id] = badgeRect;
      }
    }
  }

  void _drawGeometricConstraints(Canvas canvas, DsfDocument doc, Offset Function(double x, double y) toScreen, double scale) {
    if (doc.constraints.isEmpty) return;

    for (final c in doc.constraints) {
      if (!c.isActive || c.entityIds.isEmpty) continue;

      Offset? anchorPos;
      final firstId = c.entityIds.first;

      final cut = doc.cutLines.where((l) => l.id == firstId).firstOrNull;
      if (cut != null) {
        anchorPos = toScreen(cut.midpoint.x, cut.midpoint.y);
      } else {
        final bend = doc.bends.where((b) => b.id == firstId).firstOrNull;
        if (bend != null) {
          anchorPos = toScreen(bend.midpoint.x, bend.midpoint.y);
        } else {
          final punch = doc.punches.where((p) => p.id == firstId).firstOrNull;
          if (punch != null) {
            anchorPos = toScreen(punch.center.x, punch.center.y);
          }
        }
      }

      if (anchorPos == null) continue;

      final isSelected = selectedEntityIds.contains(c.id);
      final badgePaint = Paint()
        ..color = isSelected ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = isSelected ? const Color(0xFF0369A1) : const Color(0xFF94A3B8)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      final badgeCenter = anchorPos + const Offset(12, -12);
      final rrect = RRect.fromRectAndRadius(Rect.fromCenter(center: badgeCenter, width: 18, height: 16), const Radius.circular(3));

      canvas.drawRRect(rrect, badgePaint);
      canvas.drawRRect(rrect, borderPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: c.symbol,
          style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF0F172A), fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, badgeCenter - Offset(textPainter.width / 2, textPainter.height / 2));
    }
  }

  void _drawLinearDimension(
    Canvas canvas, {
    required Offset p1Screen,
    required Offset p2Screen,
    required double dimScreenCoord,
    required bool isVertical,
    required String valueText,
    String? dimId,
    CadPoint2D? ptA,
    CadPoint2D? ptB,
    double? scale,
  }) {
    final sign = isVertical ? ((dimScreenCoord >= p1Screen.dx) ? 1.0 : -1.0) : ((dimScreenCoord >= p1Screen.dy) ? 1.0 : -1.0);

    final geomCoord = isVertical ? p1Screen.dx : p1Screen.dy;
    final initialOffsetMm = (dimScreenCoord - geomCoord).abs() / (scale ?? 1.0);
    final userLineOffsetMm = (dimId != null && dimensionLineOffsets.containsKey(dimId)) ? dimensionLineOffsets[dimId]! : initialOffsetMm;

    final effectiveDimCoord = (scale != null) ? geomCoord + sign * (userLineOffsetMm * scale) : dimScreenCoord;

    final Offset pA;
    final Offset pB;
    if (!isVertical) {
      pA = Offset(p1Screen.dx, effectiveDimCoord);
      pB = Offset(p2Screen.dx, effectiveDimCoord);
    } else {
      pA = Offset(effectiveDimCoord, p1Screen.dy);
      pB = Offset(effectiveDimCoord, p2Screen.dy);
    }

    if (dimId != null && renderedDimensionLines != null) {
      renderedDimensionLines![dimId] = (
        pA: pA,
        pB: pB,
        offsetDist: userLineOffsetMm,
        ptA: ptA ?? (isVertical ? CadPoint2D(p1Screen.dx, p1Screen.dy) : CadPoint2D(p1Screen.dx, p1Screen.dy)),
        ptB: ptB ?? (isVertical ? CadPoint2D(p2Screen.dx, p2Screen.dy) : CadPoint2D(p2Screen.dx, p2Screen.dy)),
        type: isVertical ? CadDimensionType.vertical : CadDimensionType.horizontal,
      );
    }

    final isLineHovered = (dimId != null && hoveredDimLineId == dimId);

    if (isLineHovered) {
      final glowPaint = Paint()
        ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.35)
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(pA, pB, glowPaint);
    }

    final witnessPaint = Paint()
      ..color =
          const Color(0xFF64748B) // Slate witness line
      ..strokeWidth = 0.8;

    final dimLinePaint = Paint()
      ..color = isLineHovered
          ? const Color(0xFF0284C7)
          : const Color(0xFF475569) // Dimension line
      ..strokeWidth = isLineHovered ? 2.0 : 1.0;

    const extPast = 5.0; // Extension past dimension line
    const gapFromPart = 3.0; // Small gap from part geometry

    final Offset defaultMid;

    final style = canvasSettings.outsideDimLabel;
    final textSpanVal = TextSpan(
      text: valueText,
      style: TextStyle(color: style.color, fontSize: style.fontSize, fontWeight: style.fontWeight, fontFamily: 'monospace'),
    );
    final tpVal = TextPainter(text: textSpanVal, textDirection: TextDirection.ltr)..layout();
    final halfTextW = tpVal.width / 2.0 + 3.0;
    final halfTextH = tpVal.height / 2.0 + 2.0;

    final userOffset = (dimId != null && dimensionOffsets.containsKey(dimId)) ? dimensionOffsets[dimId]! : Offset.zero;

    if (!isVertical) {
      // Horizontal dimension line at Y = effectiveDimCoord
      final startY = p1Screen.dy + sign * gapFromPart;
      final endY = effectiveDimCoord + sign * extPast;

      // Witness lines
      canvas.drawLine(Offset(p1Screen.dx, startY), Offset(p1Screen.dx, endY), witnessPaint);
      canvas.drawLine(Offset(p2Screen.dx, startY), Offset(p2Screen.dx, endY), witnessPaint);

      // Witness origin dots
      final originDotPaint = Paint()
        ..color = const Color(0xFF64748B)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p1Screen.dx, startY), 1.8, originDotPaint);
      canvas.drawCircle(Offset(p2Screen.dx, startY), 1.8, originDotPaint);

      final midX = (p1Screen.dx + p2Screen.dx) / 2.0;
      defaultMid = Offset(midX, effectiveDimCoord);

      // Break dimension line with gap for centered text if not manually offset
      if (userOffset.distance <= 4.0 && (p2Screen.dx - p1Screen.dx).abs() > halfTextW * 2.5) {
        final leftX = math.min(p1Screen.dx, p2Screen.dx);
        final rightX = math.max(p1Screen.dx, p2Screen.dx);
        canvas.drawLine(Offset(leftX, effectiveDimCoord), Offset(midX - halfTextW, effectiveDimCoord), dimLinePaint);
        canvas.drawLine(Offset(midX + halfTextW, effectiveDimCoord), Offset(rightX, effectiveDimCoord), dimLinePaint);
      } else {
        canvas.drawLine(pA, pB, dimLinePaint);
      }

      // Arrowheads pointing towards witness lines
      _drawArrow(canvas, Offset(p1Screen.dx, effectiveDimCoord), 0.0);
      _drawArrow(canvas, Offset(p2Screen.dx, effectiveDimCoord), math.pi);
    } else {
      // Vertical dimension line at X = effectiveDimCoord
      final startX = p1Screen.dx + sign * gapFromPart;
      final endX = effectiveDimCoord + sign * extPast;

      // Witness lines
      canvas.drawLine(Offset(startX, p1Screen.dy), Offset(endX, p1Screen.dy), witnessPaint);
      canvas.drawLine(Offset(startX, p2Screen.dy), Offset(endX, p2Screen.dy), witnessPaint);

      // Witness origin dots
      final originDotPaint = Paint()
        ..color = const Color(0xFF64748B)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(startX, p1Screen.dy), 1.8, originDotPaint);
      canvas.drawCircle(Offset(startX, p2Screen.dy), 1.8, originDotPaint);

      final midY = (p1Screen.dy + p2Screen.dy) / 2.0;
      defaultMid = Offset(effectiveDimCoord, midY);

      // Break dimension line with gap for centered text if not manually offset
      if (userOffset.distance <= 4.0 && (p2Screen.dy - p1Screen.dy).abs() > halfTextH * 2.5) {
        final topY = math.min(p1Screen.dy, p2Screen.dy);
        final botY = math.max(p1Screen.dy, p2Screen.dy);
        canvas.drawLine(Offset(effectiveDimCoord, topY), Offset(effectiveDimCoord, midY - halfTextH), dimLinePaint);
        canvas.drawLine(Offset(effectiveDimCoord, midY + halfTextH), Offset(effectiveDimCoord, botY), dimLinePaint);
      } else {
        canvas.drawLine(pA, pB, dimLinePaint);
      }

      // Arrowheads pointing towards witness lines
      _drawArrow(canvas, Offset(effectiveDimCoord, p1Screen.dy), math.pi / 2.0);
      _drawArrow(canvas, Offset(effectiveDimCoord, p2Screen.dy), -math.pi / 2.0);
    }

    // End dots on the dimension line endpoints pA and pB
    final endDotPaint = Paint()
      ..color = isLineHovered ? const Color(0xFF0284C7) : const Color(0xFF475569)
      ..style = PaintingStyle.fill;
    final endDotCore = Paint()..color = Colors.white;
    canvas.drawCircle(pA, 2.6, endDotPaint);
    canvas.drawCircle(pA, 1.0, endDotCore);
    canvas.drawCircle(pB, 2.6, endDotPaint);
    canvas.drawCircle(pB, 1.0, endDotCore);

    final effectiveCenter = defaultMid + userOffset;

    // If moved by user, draw an anchor line and dot
    if (userOffset.distance > 4.0) {
      final leaderPaint = Paint()
        ..color = const Color(0xFF64748B)
        ..strokeWidth = 0.9
        ..style = PaintingStyle.stroke;
      canvas.drawLine(defaultMid, effectiveCenter, leaderPaint);

      final dotPaint = Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(defaultMid, 2.5, dotPaint);
    }

    if (dimId != null) {
      final parsedVal = double.tryParse(valueText.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (parsedVal != null) {
        renderedDimensionValues?[dimId] = parsedVal;
      }
    }

    final isDimSelected = dimId != null && selectedDimensionId == dimId;
    final isDimHovered = dimId != null && hoveredDimensionId == dimId;
    final badgeRect = _drawDimBadge(
      canvas,
      effectiveCenter,
      valueText,
      isEditing: dimId != null && dimId == editingDimId,
      isSelected: isDimSelected,
      isHovered: isDimHovered,
      style: canvasSettings.outsideDimLabel,
    );
    if (dimId != null && renderedDimensionBadges != null) {
      renderedDimensionBadges![dimId] = badgeRect;
    }
  }

  void _drawArrow(Canvas canvas, Offset tip, double angleRad) {
    final arrowPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.fill;

    const arrowLength = 7.0;
    const arrowHalfWidth = 2.5;

    final path = Path();
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(
      tip.dx - arrowLength * math.cos(angleRad) - arrowHalfWidth * math.sin(angleRad),
      tip.dy - arrowLength * math.sin(angleRad) + arrowHalfWidth * math.cos(angleRad),
    );
    path.lineTo(
      tip.dx - arrowLength * math.cos(angleRad) + arrowHalfWidth * math.sin(angleRad),
      tip.dy - arrowLength * math.sin(angleRad) - arrowHalfWidth * math.cos(angleRad),
    );
    path.close();
    canvas.drawPath(path, arrowPaint);
  }

  Rect _drawDimBadge(Canvas canvas, Offset center, String text, {bool isEditing = false, bool isSelected = false, bool isHovered = false, LabelStyle? style}) {
    final effectiveStyle = style ?? canvasSettings.dimTextLabel;
    final hasDeleteIcon = isSelected || isHovered;
    final fullText = hasDeleteIcon ? '$text  ✕' : text;

    final span = TextSpan(
      text: fullText,
      style: TextStyle(
        color: (isSelected || isHovered) ? const Color(0xFF0284C7) : effectiveStyle.color,
        fontSize: effectiveStyle.fontSize,
        fontWeight: (isSelected || isHovered) ? FontWeight.bold : effectiveStyle.fontWeight,
        fontFamily: 'monospace',
      ),
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();

    final bgRect = Rect.fromCenter(center: center, width: tp.width + (hasDeleteIcon ? 8.0 : 4.0), height: tp.height + 3.0);

    final rrect = RRect.fromRectAndRadius(bgRect, const Radius.circular(3.5));

    if (isSelected || isHovered) {
      // Drop shadow
      canvas.drawRRect(
        rrect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );

      // Selected / hovered badge background
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFFF0F9FF));

      // Blue border
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isSelected ? const Color(0xFF0284C7) : const Color(0xFF06B6D4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    } else {
      // Subtle backing to avoid geometry line collision
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFFF8FAFC).withValues(alpha: 0.85));
    }

    if (!isEditing) {
      tp.paint(canvas, Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0));
    }
    return bgRect;
  }

  void _drawHoleCrosshairs(Canvas canvas, DsfDocument doc, Offset Function(double x, double y) toScreen, double scale) {
    final crossPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final punch in doc.allPunches) {
      if (punch.type == PunchType.roundHole) {
        final sc = toScreen(punch.center.x, punch.center.y);
        final rScreen = (punch.diameterMm / 2.0) * scale;
        final armLen = rScreen + 4.0;

        // Horizontal crosshair arm
        canvas.drawLine(Offset(sc.dx - armLen, sc.dy), Offset(sc.dx + armLen, sc.dy), crossPaint);
        // Vertical crosshair arm
        canvas.drawLine(Offset(sc.dx, sc.dy - armLen), Offset(sc.dx, sc.dy + armLen), crossPaint);
      } else if (punch.type == PunchType.ellipse) {
        final sc = toScreen(punch.center.x, punch.center.y);
        final maxR = math.max(punch.lengthMm, punch.widthMm) / 2.0;
        final armLen = maxR * scale + 4.0;

        canvas.drawLine(Offset(sc.dx - armLen, sc.dy), Offset(sc.dx + armLen, sc.dy), crossPaint);
        canvas.drawLine(Offset(sc.dx, sc.dy - armLen), Offset(sc.dx, sc.dy + armLen), crossPaint);
      }
    }
  }

  void _drawHoleLeaderCallouts(Canvas canvas, DsfDocument doc, Offset Function(double x, double y) toScreen, double scale) {
    if (!canvasSettings.dimTextLabel.visible) return;
    final roundPunches = doc.allPunches.where((p) => p.type == PunchType.roundHole && p.diameterMm > 0).toList();
    if (roundPunches.isEmpty) return;

    // Group by rounded diameter
    final Map<int, List<CncPunchPrimitive>> groups = {};
    for (final p in roundPunches) {
      final key = (p.diameterMm * 10).round();
      groups.putIfAbsent(key, () => []).add(p);
    }

    final leaderPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    int calloutIdx = 0;
    for (final entry in groups.entries) {
      final list = entry.value;
      final diam = list.first.diameterMm;
      final count = list.length;
      final dStr = formatMeasure(diam, canvasSettings);
      final label = (count > 1) ? '$count × Ø$dStr' : 'Ø$dStr';

      // Pick top-right-most punch in this group
      list.sort((a, b) => (b.center.x + b.center.y).compareTo(a.center.x + a.center.y));
      final repPunch = list.first;
      final sc = toScreen(repPunch.center.x, repPunch.center.y);
      final rScreen = (diam / 2.0) * scale;

      // Leader angles: 45° angled line pointing outwards to the right
      const leaderAngle = -math.pi / 4.0;
      final rimX = sc.dx + rScreen * math.cos(leaderAngle);
      final rimY = sc.dy + rScreen * math.sin(leaderAngle);

      final elbowX = rimX + 24.0 + (calloutIdx * 14.0);
      final elbowY = rimY - 18.0 - (calloutIdx * 12.0);
      final shoulderEndX = elbowX + 26.0;

      // Draw angled leader line
      canvas.drawLine(Offset(rimX, rimY), Offset(elbowX, elbowY), leaderPaint);
      // Draw horizontal shoulder
      canvas.drawLine(Offset(elbowX, elbowY), Offset(shoulderEndX, elbowY), leaderPaint);

      // Arrow pointing at hole rim
      _drawArrow(canvas, Offset(rimX, rimY), leaderAngle + math.pi);

      // Text callout badge
      final style = canvasSettings.dimTextLabel;
      final span = TextSpan(
        text: ' $label ',
        style: TextStyle(color: style.color, fontSize: style.fontSize, fontWeight: style.fontWeight),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(shoulderEndX + 2, elbowY - tp.height / 2.0));

      calloutIdx++;
    }
  }

  void _drawPortOpeningBadges(Canvas canvas, DsfDocument doc, Offset Function(double x, double y) toScreen, double scale) {
    final meta = fittingMetadata;
    if (meta == null) return;

    final openings = meta.getPortOpenings(doc, onlyAssigned: true);
    if (openings.isEmpty) return;
    if (!canvasSettings.portBadgeLabel.visible) return;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final leaderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final port in openings) {
      final sp1 = toScreen(port.edgeP1.x, port.edgeP1.y);
      final sp2 = toScreen(port.edgeP2.x, port.edgeP2.y);
      final sCenter = toScreen(port.center.x, port.center.y);

      // Color accent by port
      final Color portColor;
      if (port.id == 'port1' || port.id == 'entry') {
        portColor = const Color(0xFF0284C7); // Sky Blue
      } else if (port.id == 'port2' || port.id == 'exit') {
        portColor = const Color(0xFF0D9488); // Teal
      } else if (port.id == 'port3') {
        portColor = const Color(0xFF8B5CF6); // Violet
      } else {
        portColor = const Color(0xFFF59E0B); // Amber
      }

      // 1. Draw refined accent line along opening edge
      glowPaint
        ..color = portColor.withValues(alpha: 0.22)
        ..strokeWidth = 3.0;
      canvas.drawLine(sp1, sp2, glowPaint);

      glowPaint
        ..color = portColor
        ..strokeWidth = 1.4;
      canvas.drawLine(sp1, sp2, glowPaint);

      // 2. Outward normal vector in screen coordinates
      final sNormPt = toScreen(port.center.x + port.normal.x, port.center.y + port.normal.y);
      final rawDir = sNormPt - sCenter;
      final dirLen = rawDir.distance;
      final Offset normalDir = dirLen > 1e-4 ? Offset(rawDir.dx / dirLen, rawDir.dy / dirLen) : const Offset(0, -1);

      // Leader offset length: 30 pixels out from opening edge
      const leaderLen = 30.0;
      final badgeAnchor = sCenter + normalDir * leaderLen;

      // Draw inward-pointing arrow at opening edge pointing into channel
      _drawArrow(canvas, sCenter, math.atan2(-normalDir.dy, -normalDir.dx));

      // 3. Render translucent CAD badge pill for opening Width (W)
      final sideLabel = port.side.displayName;
      final labelText = '${port.label}  [$sideLabel]';
      final dimText = 'W: ${formatMeasure(port.widthMm, canvasSettings)}';

      final titleSpan = TextSpan(
        children: [
          TextSpan(
            text: '$labelText  ',
            style: TextStyle(color: portColor.withValues(alpha: 0.95), fontSize: 9.0, fontWeight: FontWeight.w600, letterSpacing: 0.3),
          ),
          const TextSpan(
            text: '[Edit ✎]',
            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 8.5, fontWeight: FontWeight.bold),
          ),
        ],
      );
      final tpTitle = TextPainter(text: titleSpan, textDirection: TextDirection.ltr)..layout();

      final portStyle = canvasSettings.portBadgeLabel;
      final dimSpan = TextSpan(
        text: dimText,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: portStyle.fontSize, fontWeight: portStyle.fontWeight, letterSpacing: 0.2),
      );
      final tpDim = TextPainter(text: dimSpan, textDirection: TextDirection.ltr)..layout();

      final badgeW = math.max(tpTitle.width, tpDim.width) + 20.0;
      const badgeH = 38.0;

      // Position badge centered at badgeAnchor offset in normal direction + user drag offset
      final customOffset = portBadgeOffsets?[port.id] ?? Offset.zero;
      final defaultCenter = badgeAnchor + normalDir * (badgeH / 2.0 + 2.0);
      final badgeCenter = defaultCenter + customOffset;
      final badgeRect = Rect.fromCenter(center: badgeCenter, width: badgeW, height: badgeH);

      // Register rendered badge rect for draggable interactions
      renderedPortBadges?[port.id] = badgeRect;

      leaderPaint.color = portColor.withValues(alpha: 0.55);
      leaderPaint.strokeWidth = 1.0;
      if (customOffset != Offset.zero) {
        canvas.drawLine(sCenter, badgeCenter, leaderPaint);
      } else {
        canvas.drawLine(sCenter, badgeAnchor, leaderPaint);
      }

      final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(6));

      // Badge drop shadow
      canvas.drawRRect(
        rrect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );

      // Translucent dark slate background (frosted pill, not loud)
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.62));

      // Softer colored accent border
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = portColor.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      // Text inside pill
      tpTitle.paint(canvas, Offset(badgeRect.left + 10.0, badgeRect.top + 4.0));
      tpDim.paint(canvas, Offset(badgeRect.left + 10.0, badgeRect.top + 18.0));

      // 4. Render Height (H) edge callout badges for assigned height flaps (Translucent & Draggable)
      final manual = meta.manualPortEdges?[port.id];
      final heightEdges = manual?['heightEdges'] as List?;
      if (heightEdges != null && heightEdges.isNotEmpty) {
        final hValStr = (port.heightMm % 1 == 0) ? port.heightMm.toInt().toString() : port.heightMm.toStringAsFixed(1);
        final hDimText = 'H: $hValStr mm';

        for (int hIdx = 0; hIdx < heightEdges.length; hIdx++) {
          final hMap = heightEdges[hIdx];
          if (hMap is Map && hMap['p1'] is List && hMap['p2'] is List) {
            final hp1List = (hMap['p1'] as List).map((n) => (n as num).toDouble()).toList();
            final hp2List = (hMap['p2'] as List).map((n) => (n as num).toDouble()).toList();
            if (hp1List.length >= 2 && hp2List.length >= 2) {
              final shp1 = toScreen(hp1List[0], hp1List[1]);
              final shp2 = toScreen(hp2List[0], hp2List[1]);
              final shCenter = Offset((shp1.dx + shp2.dx) / 2.0, (shp1.dy + shp2.dy) / 2.0);

              // Unique ID for dragging this specific H badge
              final hBadgeId = '${port.id}_h_$hIdx';
              final hCustomOffset = portBadgeOffsets?[hBadgeId] ?? Offset.zero;

              // Draw height flap glow line (refined)
              glowPaint
                ..color = portColor.withValues(alpha: 0.22)
                ..strokeWidth = 2.5;
              canvas.drawLine(shp1, shp2, glowPaint);

              // Draw compact badge for H
              final hTitleSpan = TextSpan(
                children: [
                  TextSpan(
                    text: '${port.label} [Flange]  ',
                    style: TextStyle(color: portColor.withValues(alpha: 0.95), fontSize: 8.5, fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(
                    text: '[Edit ✎]',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 8.0, fontWeight: FontWeight.bold),
                  ),
                ],
              );
              final tpHTitle = TextPainter(text: hTitleSpan, textDirection: TextDirection.ltr)..layout();

              final hDimSpan = TextSpan(
                text: hDimText,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 11.0, fontWeight: FontWeight.bold),
              );
              final tpHdim = TextPainter(text: hDimSpan, textDirection: TextDirection.ltr)..layout();

              final hBadgeW = math.max(tpHTitle.width, tpHdim.width) + 16.0;
              const hBadgeH = 32.0;
              final defaultHCenter = shCenter + const Offset(0, -26.0);
              final hBadgeCenter = defaultHCenter + hCustomOffset;
              final hBadgeRect = Rect.fromCenter(center: hBadgeCenter, width: hBadgeW, height: hBadgeH);
              final hRRect = RRect.fromRectAndRadius(hBadgeRect, const Radius.circular(5));

              // Register badge rect for hit-testing and dragging
              renderedPortBadges?[hBadgeId] = hBadgeRect;

              // Leader line to badge
              leaderPaint.color = portColor.withValues(alpha: 0.55);
              leaderPaint.strokeWidth = 1.0;
              canvas.drawLine(shCenter, hBadgeCenter, leaderPaint);

              // Translucent background & soft border
              canvas.drawRRect(
                hRRect.shift(const Offset(0, 1.5)),
                Paint()
                  ..color = Colors.black.withValues(alpha: 0.15)
                  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
              );
              canvas.drawRRect(hRRect, Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.62));
              canvas.drawRRect(
                hRRect,
                Paint()
                  ..color = portColor.withValues(alpha: 0.65)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.0,
              );

              tpHTitle.paint(canvas, Offset(hBadgeRect.left + 8.0, hBadgeRect.top + 3.0));
              tpHdim.paint(canvas, Offset(hBadgeRect.left + 8.0, hBadgeRect.top + 15.0));
            }
          }
        }
      }
    }
  }

  void _drawArcBadge(Canvas canvas, Offset screenPos, CadArc2D arc, bool isSelected) {
    if (!arc.showLabel) return;
    if (!canvasSettings.arcLabel.visible) return;
    final arcStyle = canvasSettings.arcLabel;
    final rStr = formatMeasure(arc.radius, canvasSettings);
    final lStr = formatMeasure(arc.arcLength, canvasSettings);
    final label = 'Arc: R=$rStr • L=$lStr';
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(color: isSelected ? Colors.white : arcStyle.color, fontSize: arcStyle.fontSize, fontWeight: arcStyle.fontWeight, letterSpacing: 0.2),
    );
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();

    final badgeRect = Rect.fromCenter(center: screenPos + const Offset(0, -18), width: textPainter.width + 12.0, height: textPainter.height + 6.0);

    final bgPaint = Paint()
      ..color = isSelected ? const Color(0xFF2563EB) : Colors.white.withValues(alpha: 0.94)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final rrect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(4.0));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);
    textPainter.paint(canvas, Offset(badgeRect.left + 6.0, badgeRect.top + 3.0));
  }

  void _paintSemanticPortPreview(Canvas canvas, Size size, Offset Function(double x, double y) toScreen, double scale) {
    final res = activePortInferenceResult;
    if (res == null) return;

    // 1. Opening Edge (Width W) - Glowing Cyan
    final p1 = toScreen(res.openingEdge.p1.x, res.openingEdge.p1.y);
    final p2 = toScreen(res.openingEdge.p2.x, res.openingEdge.p2.y);
    final edgeMid = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);

    final glowPaint = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.4)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p1, p2, glowPaint);

    final corePaint = Paint()
      ..color = const Color(0xFF06B6D4)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p1, p2, corePaint);

    // Endpoint handles
    final endpointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final endpointBorder = Paint()
      ..color = const Color(0xFF0891B2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(p1, 4.0, endpointPaint);
    canvas.drawCircle(p1, 4.0, endpointBorder);
    canvas.drawCircle(p2, 4.0, endpointPaint);
    canvas.drawCircle(p2, 4.0, endpointBorder);

    // Dimension badge for W
    _paintDimensionBadge(canvas, edgeMid, 'W: ${res.inferredWidth.toStringAsFixed(1)} mm', const Color(0xFF0891B2), const Offset(0, -20));

    // 2. Sidewall A (Height HA) - Amber Wings
    if (res.sidewallAEdges.isNotEmpty) {
      final wallAPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final wallAGlow = Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.3)
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;

      for (final seg in res.sidewallAEdges) {
        final sp1 = toScreen(seg.p1.x, seg.p1.y);
        final sp2 = toScreen(seg.p2.x, seg.p2.y);
        canvas.drawLine(sp1, sp2, wallAGlow);
        canvas.drawLine(sp1, sp2, wallAPaint);
      }

      final firstSeg = res.sidewallAEdges.first;
      final aMid = toScreen((firstSeg.p1.x + firstSeg.p2.x) / 2.0, (firstSeg.p1.y + firstSeg.p2.y) / 2.0);
      _paintDimensionBadge(canvas, aMid, 'HA: ${res.inferredHeightA.toStringAsFixed(1)} mm', const Color(0xFFD97706), const Offset(0, -18));
    }

    // 3. Sidewall B (Height HB) - Purple Wings
    if (res.sidewallBEdges.isNotEmpty) {
      final wallBPaint = Paint()
        ..color = const Color(0xFF8B5CF6)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final wallBGlow = Paint()
        ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.3)
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;

      for (final seg in res.sidewallBEdges) {
        final sp1 = toScreen(seg.p1.x, seg.p1.y);
        final sp2 = toScreen(seg.p2.x, seg.p2.y);
        canvas.drawLine(sp1, sp2, wallBGlow);
        canvas.drawLine(sp1, sp2, wallBPaint);
      }

      final firstSeg = res.sidewallBEdges.first;
      final bMid = toScreen((firstSeg.p1.x + firstSeg.p2.x) / 2.0, (firstSeg.p1.y + firstSeg.p2.y) / 2.0);
      _paintDimensionBadge(canvas, bMid, 'HB: ${res.inferredHeightB.toStringAsFixed(1)} mm', const Color(0xFF7C3AED), const Offset(0, -18));
    }

    // 4. Outward Connection Normal Arrow (Green)
    final normalScreenVec = Offset(res.normal.x, res.normal.y);
    const arrowLength = 46.0;
    final arrowEnd = edgeMid + normalScreenVec * arrowLength;

    final arrowPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(edgeMid, arrowEnd, arrowPaint);

    // Arrowhead
    final normalAngle = math.atan2(normalScreenVec.dy, normalScreenVec.dx);
    final headAngle1 = normalAngle + math.pi * 0.85;
    final headAngle2 = normalAngle - math.pi * 0.85;
    const headLength = 10.0;
    final headP1 = arrowEnd + Offset(math.cos(headAngle1) * headLength, math.sin(headAngle1) * headLength);
    final headP2 = arrowEnd + Offset(math.cos(headAngle2) * headLength, math.sin(headAngle2) * headLength);

    final headPath = Path()
      ..moveTo(arrowEnd.dx, arrowEnd.dy)
      ..lineTo(headP1.dx, headP1.dy)
      ..lineTo(headP2.dx, headP2.dy)
      ..close();
    final arrowHeadPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;
    canvas.drawPath(headPath, arrowHeadPaint);

    // Base circle for arrow
    canvas.drawCircle(edgeMid, 3.5, arrowHeadPaint);

    // Direction label near arrow
    _paintDimensionBadge(
      canvas,
      arrowEnd,
      'OUT (${res.inferredSide.name.toUpperCase()})',
      const Color(0xFF059669),
      Offset(normalScreenVec.dx * 16.0, normalScreenVec.dy * 16.0),
    );

    // 5. Associated Coupler Punches (Teal Pulsing Rings)
    if (res.associatedFeatureIds.isNotEmpty) {
      final punchHighlightPaint = Paint()
        ..color = const Color(0xFF14B8A6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      for (final punch in doc.punches) {
        if (res.associatedFeatureIds.contains(punch.id)) {
          final poly = punch.toPolygon();
          if (poly.isNotEmpty) {
            final path = Path();
            final firstP = toScreen(poly.first.x, poly.first.y);
            path.moveTo(firstP.dx, firstP.dy);
            for (int i = 1; i < poly.length; i++) {
              final pi = toScreen(poly[i].x, poly[i].y);
              path.lineTo(pi.dx, pi.dy);
            }
            path.close();
            canvas.drawPath(path, punchHighlightPaint);
          }
        }
      }
    }
  }

  void _paintDimensionBadge(Canvas canvas, Offset pos, String text, Color color, Offset offset) {
    final textSpan = TextSpan(
      text: ' $text ',
      style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold, letterSpacing: 0.2),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    final center = pos + offset;
    final rrect = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: tp.width + 8.0, height: tp.height + 4.0), const Radius.circular(4.0));
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(rrect.shift(const Offset(0, 1)), shadowPaint);
    canvas.drawRRect(rrect, Paint()..color = color);
    tp.paint(canvas, Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0));
  }

  /// Draws a clean, high-precision vector coupler logo (dual interlocking chain links)
  void _drawCouplerGlyph(Canvas canvas, Offset center, double size, Color color, {double strokeWidth = 1.2}) {
    final linkPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rw = size * 0.60;
    final rh = size * 0.38;
    final spacing = size * 0.16;

    // Left link capsule
    final leftRect = Rect.fromCenter(center: Offset(center.dx - spacing, center.dy), width: rw, height: rh);
    canvas.drawRRect(RRect.fromRectAndRadius(leftRect, Radius.circular(rh * 0.5)), linkPaint);

    // Right link capsule (overlapping)
    final rightRect = Rect.fromCenter(center: Offset(center.dx + spacing, center.dy), width: rw, height: rh);
    canvas.drawRRect(RRect.fromRectAndRadius(rightRect, Radius.circular(rh * 0.5)), linkPaint);

    // Central connection interlock pin dot
    canvas.drawCircle(
      center,
      strokeWidth * 0.6,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _UnfoldedBoardPainter oldDelegate) {
    return oldDelegate.foldProgress != foldProgress ||
        oldDelegate.doc != doc ||
        oldDelegate.pan != pan ||
        oldDelegate.zoom != zoom ||
        oldDelegate.toolMode != toolMode ||
        oldDelegate.activeSnap != activeSnap ||
        oldDelegate.pendingBendStart != pendingBendStart ||
        oldDelegate.rubberBandEndpoint != rubberBandEndpoint ||
        oldDelegate.pendingMultiPoints != pendingMultiPoints ||
        oldDelegate.selectedBendId != selectedBendId ||
        oldDelegate.selectedCutId != selectedCutId ||
        oldDelegate.selectedPunchId != selectedPunchId ||
        oldDelegate.hoveredPunchId != hoveredPunchId ||
        oldDelegate.hoveredBendId != hoveredBendId ||
        oldDelegate.toolConfig != toolConfig ||
        oldDelegate.selectedEntityIds != selectedEntityIds ||
        oldDelegate.boxSelectStart != boxSelectStart ||
        oldDelegate.boxSelectCurrent != boxSelectCurrent ||
        oldDelegate.autoCandidateLine != autoCandidateLine ||
        oldDelegate.showOpeningTags != showOpeningTags ||
        oldDelegate.portBadgeOffsets != portBadgeOffsets ||
        oldDelegate.hoveredContourEdgeP1 != hoveredContourEdgeP1 ||
        oldDelegate.hoveredContourEdgeLengthMm != hoveredContourEdgeLengthMm ||
        oldDelegate.fittingMetadata != fittingMetadata ||
        oldDelegate.activePortInferenceResult != activePortInferenceResult ||
        oldDelegate.hoverCursorCad != hoverCursorCad ||
        oldDelegate.hoveredDimLineId != hoveredDimLineId ||
        oldDelegate.editingDimId != editingDimId ||
        oldDelegate.isAltPressed != isAltPressed ||
        oldDelegate.canvasSettings != canvasSettings;
  }
}
