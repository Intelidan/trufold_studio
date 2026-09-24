// =============================================================================
// CanvasGestureHandlerMixin
//
// Provides all gesture handling (pan, tap, double-tap, box-select, drawing)
// and geometric hit-testing helpers for _UnfoldedCanvasWidgetState.
// Extracted from unfolded_canvas_widget.dart.
// =============================================================================

part of '../unfolded_canvas_widget.dart';

mixin CanvasGestureHandlerMixin on State<UnfoldedCanvasWidget>, CanvasDimensionEditorMixin, CanvasPortDimensionEditorMixin, CanvasContextMenuMixin, CanvasOverlayStackMixin {
  // ---------------------------------------------------------------------------
  // Gesture & Selection State
  // ---------------------------------------------------------------------------
  _DragTarget _activeDrag = _DragTarget.none;
  Offset? _boxSelectStart;
  Offset? _boxSelectCurrent;
  String? _draggedBendId;
  String? _draggedCutId;
  Offset _dragStartScreen = Offset.zero;
  CadPoint2D _dragPunchOffsetCad = const CadPoint2D(0, 0);
  CadPoint2D _coverDragStartOffset = const CadPoint2D(0, 0);

  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  // Interactive Canvas Constraint Glyphs (Component 2)
  final Map<String, Rect> _constraintBadgeRects = {};
  String? _hoveredConstraintId;
  final Set<String> _constraintHoverHighlightedEntityIds = {};

  CadPoint2D? _hoveredEndpoint;
  String? _lastSelectedEntity;
  ({CadPoint2D point, String label})? _dragAngleInfo;
  Offset? _drawDragStartScreen;
  Offset? _drawDragCurrentScreen;
  CadPoint2D? _drawDragStartCad;
  bool _drawDragCommitted = false;
  bool _shiftSelectionHandledInPan = false;
  bool _drawStartAltPressed = false;
  Offset? _hoverCursorScreen;
  CadPoint2D? _hoverCursorCad;

  // ---------------------------------------------------------------------------
  // Geometry & Keyboard Helpers
  // ---------------------------------------------------------------------------
  bool _isAltPressed() {
    try {
      if (HardwareKeyboard.instance.isAltPressed) return true;
    } catch (_) {}
    try {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(
            LogicalKeyboardKey.altLeft,
          ) ||
          HardwareKeyboard.instance.isLogicalKeyPressed(
            LogicalKeyboardKey.altRight,
          )) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  bool _isShiftPressed() {
    try {
      if (HardwareKeyboard.instance.isShiftPressed) return true;
    } catch (_) {}
    try {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(
            LogicalKeyboardKey.shiftLeft,
          ) ||
          HardwareKeyboard.instance.isLogicalKeyPressed(
            LogicalKeyboardKey.shiftRight,
          )) {
        return true;
      }
    } catch (_) {}
    return false;
  }


  double _distToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y);
    if (l2 < 1e-4) return p.distanceTo(a);
    final t = math.max(
      0.0,
      math.min(
        1.0,
        ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2,
      ),
    );
    final proj = CadPoint2D(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
    return p.distanceTo(proj);
  }

  double _distToScreenSegment(Offset p, Offset a, Offset b) {
    final l2 = (b.dx - a.dx) * (b.dx - a.dx) + (b.dy - a.dy) * (b.dy - a.dy);
    if (l2 < 1e-4) return (p - a).distance;
    final t = math.max(
      0.0,
      math.min(
        1.0,
        ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2,
      ),
    );
    final proj = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - proj).distance;
  }

  bool _isPointInPoly(CadPoint2D pt, List<CadPoint2D> poly) {
    if (poly.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].x, yi = poly[i].y;
      final xj = poly[j].x, yj = poly[j].y;
      final intersect =
          ((yi > pt.y) != (yj > pt.y)) &&
          (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  void _handleCanvasDoubleTap(
    Offset touchScreen,
    CadPoint2D Function(Offset) screenToCad,
    Offset Function(CadPoint2D) cadToScreen,
  ) {
    final viewModel = widget.viewModel;
    final scale = viewModel.zoom2D;

    // 0. Finish active polyline on double tap
    if (viewModel.toolMode == StudioToolMode.drawPolyline &&
        viewModel.pendingMultiPoints.length >= 2) {
      viewModel.finishPolyline();
      return;
    }

    // Check double tap on ANY port badge
    for (final entry in _portBadgeRects.entries) {
      if (entry.value.inflate(6.0).contains(touchScreen)) {
        _openPortDimensionEditor(entry.key);
        return;
      }
    }

    // 1. If double-tapping a dimension badge, convert number tag in-place to entry point!
    for (final entry in _dimensionBadgeRects.entries) {
      if (entry.value.inflate(6.0).contains(touchScreen)) {
        final dimId = entry.key;
        double currentValue = _dimensionBadgeValues[dimId] ?? 0.0;
        final cadDim = viewModel.document.dimensions
            .where((d) => d.id == dimId)
            .firstOrNull;
        if (cadDim != null) {
          currentValue = cadDim.measuredValue;
        } else if (dimId == 'dim_blank_w') {
          currentValue = viewModel.document.blankWidthMm;
        } else if (dimId == 'dim_blank_l') {
          currentValue = viewModel.document.blankLengthMm;
        }

        _startInPlaceDimensionEdit(
          dimId: dimId,
          badgeRect: entry.value,
          initialValue: currentValue,
          pA: cadDim?.pointA,
          pB: cadDim?.pointB,
          referenceAId: cadDim?.referenceAId,
          referenceBId: cadDim?.referenceBId,
          offset: cadDim?.dimensionLineOffset ?? 25.0,
        );
        return;
      }
    }

    final cadPt = screenToCad(touchScreen);
    // 2. If double tapping on an applied perforation pattern, select it and open inspector
    for (final pat in viewModel.document.perforationPatterns) {
      if (!pat.isVisible) continue;
      final holeIdx = pat.findHoleAt(cadPt, maxDistMm: 16.0 / scale);
      if (holeIdx != null || pat.containsPoint(cadPt)) {
        viewModel.selectPattern(pat.id, holeIdx);
        viewModel.setPropertyInspectorOpen(true);
        setState(() {
          _isInspectorCollapsed = false;
        });
        return;
      }
    }

    // 3. If double tapping on a punch
    for (final p in viewModel.document.punches) {
      if (!p.isVisible) continue;
      final sp = cadToScreen(p.center);
      final r = math.max(16.0, (p.widthMm / 2.0) * scale);
      if ((touchScreen - sp).distance <= r) {
        viewModel.selectPunch(p.id);
        viewModel.setPropertyInspectorOpen(true);
        setState(() {
          _isInspectorCollapsed = false;
        });
        return;
      }
    }

    // 4. If double tapping on a bend
    for (final b in viewModel.document.bends) {
      if (!b.isVisible) continue;
      if (_distToSegment(cadPt, b.p1, b.p2) * scale <= 14.0) {
        viewModel.selectBend(b.id);
        viewModel.setPropertyInspectorOpen(true);
        setState(() {
          _isInspectorCollapsed = false;
        });
        return;
      }
    }

    // 5. If double tapping on a cut
    for (final c in viewModel.document.cutLines) {
      if (!c.isVisible) continue;
      if (_distToSegment(cadPt, c.p1, c.p2) * scale <= 14.0) {
        viewModel.selectCut(c.id);
        viewModel.setPropertyInspectorOpen(true);
        setState(() {
          _isInspectorCollapsed = false;
        });
        return;
      }
    }

    // 5b. If double tapping on an arc
    for (final a in viewModel.document.arcs) {
      if (a.distanceTo(cadPt) * scale <= 14.0) {
        viewModel.setSelectedArc(a.id);
        viewModel.setPropertyInspectorOpen(true);
        setState(() {
          _isInspectorCollapsed = false;
        });
        return;
      }
    }

    // 6. If double tapping on a face
    for (final f in viewModel.document.faces) {
      if (!f.isVisible) continue;
      if (_isPointInPoly(cadPt, f.vertices)) {
        viewModel.selectFace(f.id);
        viewModel.setPropertyInspectorOpen(true);
        setState(() {
          _isInspectorCollapsed = false;
        });
        return;
      }
    }

    viewModel.cycleSelectionAt(cadPt);
  }


  // ---------------------------------------------------------------------------
  // Pan & Tap Handlers for Canvas GestureDetector
  // ---------------------------------------------------------------------------

  void _handleCanvasPanStart(
    DragStartDetails details, {
    required SheetMetalStudioViewModel viewModel,
    required CadPoint2D Function(Offset) screenToCad,
    required Offset Function(CadPoint2D) cadToScreen,
    required double scale,
    required Size size,
    FoldBendLine? selectedBend,
    CadLineSegment? selectedCut,
    CncPunchPrimitive? selectedPunch,
  }) {
                                _shiftSelectionHandledInPan = false;
                                final isShiftHeld = _isShiftPressed();
                                bool isSpaceHeld = false;
                                try {
                                  isSpaceHeld = HardwareKeyboard.instance
                                      .isLogicalKeyPressed(
                                        LogicalKeyboardKey.space,
                                      );
                                } catch (_) {}

                                if (isSpaceHeld ||
                                    viewModel.toolMode == StudioToolMode.pan) {
                                  _activeDrag = _DragTarget.canvasPan;
                                  return;
                                }

                                final touchScreen = details.localPosition;
                                if (_editingDimId != null) {
                                  final curRect =
                                      _dimensionBadgeRects[_editingDimId] ??
                                      _editingDimRect;
                                  if (curRect == null ||
                                      !curRect
                                          .inflate(8.0)
                                          .contains(touchScreen)) {
                                    _commitInPlaceDimensionEdit(viewModel);
                                  }
                                }
                                final cadPt = screenToCad(touchScreen);
                                _draggedBendId = null;
                                _draggedCutId = null;
                                _draggedDimId = null;
                                _draggedDimLineId = null;

                                bool found = false;

                                // 0a. Direct hit-test on ANY movable port badge
                                for (final entry in _portBadgeRects.entries) {
                                  if (entry.value
                                      .inflate(4.0)
                                      .contains(touchScreen)) {
                                    _activeDrag = _DragTarget.portBadge;
                                    _draggedPortBadgeId = entry.key;
                                    _hasMovedPortBadge = false;
                                    _dragStartScreen = touchScreen;
                                    _dragPortBadgeStartOffset =
                                        viewModel.portBadgeOffsets[entry.key] ??
                                        Offset.zero;
                                    found = true;
                                    break;
                                  }
                                }

                                // 0b. Direct hit-test on ANY movable dimension badge
                                if (!found) {
                                  for (final entry
                                      in _dimensionBadgeRects.entries) {
                                    if (entry.value
                                        .inflate(4.0)
                                        .contains(touchScreen)) {
                                      final badge = entry.value;
                                      final isDeleteRegion =
                                          touchScreen.dx > (badge.right - 18);
                                      if (isDeleteRegion) {
                                        viewModel.removeDimension(entry.key);
                                        setState(() {
                                          _hoveredDimId = null;
                                        });
                                        found = true;
                                        break;
                                      }
                                      _activeDrag = _DragTarget.dimensionBadge;
                                      _draggedDimId = entry.key;
                                      _dragStartScreen = touchScreen;
                                      _dragDimensionStartOffset =
                                          viewModel.dimensionOffsets[entry
                                              .key] ??
                                          Offset.zero;
                                      if (viewModel.document.dimensions.any(
                                        (d) => d.id == entry.key,
                                      )) {
                                        viewModel.selectDimension(entry.key);
                                        _isInspectorCollapsed = false;
                                      }
                                      found = true;
                                      break;
                                    }
                                  }
                                }

                                // 0b2. Direct hit-test on ANY movable dimension line segment
                                if (!found) {
                                  for (final entry
                                      in _dimensionLineSegments.entries) {
                                    if (_distToScreenSegment(
                                          touchScreen,
                                          entry.value.pA,
                                          entry.value.pB,
                                        ) <=
                                        8.0) {
                                      _activeDrag = _DragTarget.dimensionLine;
                                      _draggedDimLineId = entry.key;
                                      viewModel.selectDimension(entry.key);
                                      _isInspectorCollapsed = false;
                                      found = true;
                                      break;
                                    }
                                  }
                                }

                                // 0c. Direct hit-test on ANY interactive constraint badge
                                if (!found) {
                                  for (final entry
                                      in _constraintBadgeRects.entries) {
                                    if (entry.value
                                        .inflate(4.0)
                                        .contains(touchScreen)) {
                                      final badge = entry.value;
                                      final isDeleteRegion =
                                          touchScreen.dx > (badge.right - 18);
                                      if (isDeleteRegion) {
                                        viewModel.removeConstraint(entry.key);
                                        setState(() {
                                          _hoveredConstraintId = null;
                                          _constraintHoverHighlightedEntityIds
                                              .clear();
                                        });
                                      } else {
                                        viewModel.selectConstraint(entry.key);
                                      }
                                      found = true;
                                      break;
                                    }
                                  }
                                }

                                final isDrawingTool =
                                    viewModel.toolMode ==
                                        StudioToolMode.addBend ||
                                    viewModel.toolMode ==
                                        StudioToolMode.addFlange ||
                                    viewModel.toolMode ==
                                        StudioToolMode.addCut ||
                                    viewModel.toolMode ==
                                        StudioToolMode.drawRectangle ||
                                    viewModel.toolMode ==
                                        StudioToolMode.drawCircle ||
                                    viewModel.toolMode ==
                                        StudioToolMode.drawArc ||
                                    viewModel.toolMode ==
                                        StudioToolMode.drawPolyline ||
                                    viewModel.toolMode ==
                                        StudioToolMode.addPunchRound ||
                                    viewModel.toolMode ==
                                        StudioToolMode.addPunchObround ||
                                    viewModel.toolMode ==
                                        StudioToolMode.addPunchSquare ||
                                    viewModel.toolMode ==
                                        StudioToolMode.dragDimension ||
                                    viewModel.toolMode ==
                                        StudioToolMode.addDimension;

                                // 1. Direct hit-test on ANY bend line endpoint (P1 or P2)
                                if (!found && !isDrawingTool) {
                                  for (final b in viewModel.document.bends) {
                                    if (!b.isVisible) continue;
                                    final s1 = cadToScreen(b.p1);
                                    final s2 = cadToScreen(b.p2);
                                    if ((touchScreen - s1).distance <= 20.0) {
                                      if (isShiftHeld) {
                                        viewModel.toggleEntitySelection(b.id);
                                        _shiftSelectionHandledInPan = true;
                                        found = true;
                                        _activeDrag = _DragTarget.none;
                                        break;
                                      }
                                      viewModel.selectBend(b.id);
                                      _activeDrag = _DragTarget.bendP1;
                                      _draggedBendId = b.id;
                                      found = true;
                                      break;
                                    } else if ((touchScreen - s2).distance <=
                                        20.0) {
                                      if (isShiftHeld) {
                                        viewModel.toggleEntitySelection(b.id);
                                        _shiftSelectionHandledInPan = true;
                                        found = true;
                                        _activeDrag = _DragTarget.none;
                                        break;
                                      }
                                      viewModel.selectBend(b.id);
                                      _activeDrag = _DragTarget.bendP2;
                                      _draggedBendId = b.id;
                                      found = true;
                                      break;
                                    }
                                  }

                                  // 2. Direct hit-test on ANY cut line endpoint (P1 or P2)
                                  if (!found) {
                                    for (final c
                                        in viewModel.document.cutLines) {
                                      if (!c.isVisible) continue;
                                      final s1 = cadToScreen(c.p1);
                                      final s2 = cadToScreen(c.p2);
                                      if ((touchScreen - s1).distance <= 20.0) {
                                        if (isShiftHeld) {
                                          viewModel.toggleEntitySelection(c.id);
                                          _shiftSelectionHandledInPan = true;
                                          found = true;
                                          _activeDrag = _DragTarget.none;
                                          break;
                                        }
                                        viewModel.selectCut(c.id);
                                        _activeDrag = _DragTarget.cutP1;
                                        _draggedCutId = c.id;
                                        found = true;
                                        break;
                                      } else if ((touchScreen - s2).distance <=
                                          20.0) {
                                        if (isShiftHeld) {
                                          viewModel.toggleEntitySelection(c.id);
                                          _shiftSelectionHandledInPan = true;
                                          found = true;
                                          _activeDrag = _DragTarget.none;
                                          break;
                                        }
                                        viewModel.selectCut(c.id);
                                        _activeDrag = _DragTarget.cutP2;
                                        _draggedCutId = c.id;
                                        found = true;
                                        break;
                                      }
                                    }
                                  }

                                  // 3. Direct hit-test along ANY bend line body
                                  if (!found) {
                                    for (final b in viewModel.document.bends) {
                                      if (!b.isVisible) continue;
                                      final d =
                                          _distToSegment(cadPt, b.p1, b.p2) *
                                          scale;
                                      if (d <= 14.0) {
                                        if (isShiftHeld) {
                                          viewModel.toggleEntitySelection(b.id);
                                          _shiftSelectionHandledInPan = true;
                                          found = true;
                                          _activeDrag = _DragTarget.none;
                                          break;
                                        }
                                        if (viewModel.selectedEntityIds.length >
                                                1 &&
                                            viewModel.selectedEntityIds
                                                .contains(b.id)) {
                                          _activeDrag = _DragTarget.multiEntity;
                                          found = true;
                                          break;
                                        }
                                        viewModel.selectBend(b.id);
                                        _activeDrag = _DragTarget.bendBody;
                                        _draggedBendId = b.id;
                                        found = true;
                                        break;
                                      }
                                    }
                                  }

                                  // 4. Direct hit-test along ANY cut line body
                                  if (!found) {
                                    for (final c
                                        in viewModel.document.cutLines) {
                                      if (!c.isVisible) continue;
                                      final d =
                                          _distToSegment(cadPt, c.p1, c.p2) *
                                          scale;
                                      if (d <= 14.0) {
                                        if (isShiftHeld) {
                                          viewModel.toggleEntitySelection(c.id);
                                          _shiftSelectionHandledInPan = true;
                                          found = true;
                                          _activeDrag = _DragTarget.none;
                                          break;
                                        }
                                        if (viewModel.selectedEntityIds.length >
                                                1 &&
                                            viewModel.selectedEntityIds
                                                .contains(c.id)) {
                                          _activeDrag = _DragTarget.multiEntity;
                                          found = true;
                                          break;
                                        }
                                        viewModel.selectCut(c.id);
                                        _activeDrag = _DragTarget.cutBody;
                                        _draggedCutId = c.id;
                                        found = true;
                                        break;
                                      }
                                    }
                                  }

                                  // 4b. Direct hit-test along ANY arc entity
                                  if (!found) {
                                    for (final a in viewModel.document.arcs) {
                                      final d = a.distanceTo(cadPt) * scale;
                                      if (d <= 14.0) {
                                        if (isShiftHeld) {
                                          viewModel.toggleEntitySelection(a.id);
                                          _shiftSelectionHandledInPan = true;
                                          found = true;
                                          _activeDrag = _DragTarget.none;
                                          break;
                                        }
                                        viewModel.setSelectedArc(a.id);
                                        viewModel.setPropertyInspectorOpen(
                                          true,
                                        );
                                        _isInspectorCollapsed = false;
                                        found = true;
                                        _activeDrag = _DragTarget.none;
                                        break;
                                      }
                                    }
                                  }

                                  // 5. Direct hit-test on ANY punch (with Selection Cycling for overlapping punches)
                                  if (!found) {
                                    final hitPunches = <CncPunchPrimitive>[];
                                    for (final p
                                        in viewModel.document.punches) {
                                      if (!p.isVisible) continue;
                                      final dist = cadPt.distanceTo(p.center);
                                      final effRadius = p.isRound
                                          ? p.diameterMm / 2.0
                                          : math.max(p.widthMm, p.lengthMm) /
                                                2.0;
                                      final hitR = math.max(
                                        14.0 / scale,
                                        effRadius + 3.0,
                                      );
                                      if (dist <= hitR) {
                                        hitPunches.add(p);
                                      }
                                    }

                                    if (hitPunches.isNotEmpty) {
                                      if (isShiftHeld) {
                                        hitPunches.sort(
                                          (a, b) => cadPt
                                              .distanceTo(a.center)
                                              .compareTo(
                                                cadPt.distanceTo(b.center),
                                              ),
                                        );
                                        final targetPunch = hitPunches.first;
                                        viewModel.toggleEntitySelection(
                                          targetPunch.id,
                                        );
                                        _shiftSelectionHandledInPan = true;
                                        _activeDrag = _DragTarget.none;
                                        found = true;
                                      } else {
                                        final clickedPunch = hitPunches
                                            .firstWhere(
                                              (p) => viewModel.selectedEntityIds
                                                  .contains(p.id),
                                              orElse: () => hitPunches.first,
                                            );
                                        if (viewModel.selectedEntityIds.length >
                                                1 &&
                                            viewModel.selectedEntityIds
                                                .contains(clickedPunch.id)) {
                                          _activeDrag = _DragTarget.multiEntity;
                                          found = true;
                                        } else {
                                          final targetPunch =
                                              hitPunches.any(
                                                (p) =>
                                                    p.id ==
                                                    viewModel.selectedPunchId,
                                              )
                                              ? hitPunches.firstWhere(
                                                  (p) =>
                                                      p.id ==
                                                      viewModel.selectedPunchId,
                                                )
                                              : hitPunches.first;
                                          viewModel.selectPunch(targetPunch.id);
                                          _dragPunchOffsetCad =
                                              targetPunch.center - cadPt;
                                          _activeDrag = _DragTarget.punch;
                                          found = true;
                                        }
                                      }
                                    }
                                  }

                                  // 5b. Direct hit-test on ANY perforation pattern
                                  if (!found) {
                                    for (final pat
                                        in viewModel
                                            .document
                                            .perforationPatterns) {
                                      if (!pat.isVisible) continue;
                                      final holeIdx = pat.findHoleAt(
                                        cadPt,
                                        maxDistMm: 16.0 / scale,
                                      );
                                      if (holeIdx != null ||
                                          pat.containsPoint(cadPt)) {
                                        if (isShiftHeld) {
                                          viewModel.toggleEntitySelection(
                                            pat.id,
                                          );
                                          _shiftSelectionHandledInPan = true;
                                          found = true;
                                          _activeDrag = _DragTarget.none;
                                          break;
                                        }
                                        viewModel.selectPattern(
                                          pat.id,
                                          holeIdx,
                                        );
                                        // Per user requirement: applied perforations must NOT be movable by mouse dragging!
                                        found = true;
                                        _activeDrag = _DragTarget.none;
                                        break;
                                      }
                                    }
                                  }
                                }

                                if (!found &&
                                    viewModel.document.cover != null &&
                                    viewModel.document.cover!.isVisible2D) {
                                  final cover = viewModel.document.cover!;
                                  final coverDoc = cover.document;
                                  final ox = cover.offset2D.x;
                                  final oy = cover.offset2D.y;
                                  final relCadPt = CadPoint2D(
                                    cadPt.x - ox,
                                    cadPt.y - oy,
                                  );
                                  final coverBbox = TrunkingCoverGenerator
                                      .calculateDocumentBbox(coverDoc);
                                  if (relCadPt.x >= coverBbox.minX - 10.0 &&
                                      relCadPt.x <= coverBbox.maxX + 10.0 &&
                                      relCadPt.y >= coverBbox.minY - 35.0 &&
                                      relCadPt.y <= coverBbox.maxY + 10.0) {
                                    _activeDrag = _DragTarget.cover;
                                    _dragStartScreen = touchScreen;
                                    _coverDragStartOffset = cover.offset2D;
                                    found = true;
                                  }
                                }

                                if (found) {
                                  if (!isShiftHeld &&
                                      _activeDrag != _DragTarget.none &&
                                      _activeDrag !=
                                          _DragTarget.dimensionBadge) {
                                    viewModel.beginObjectDrag();
                                  }
                                } else {
                                  if (isDrawingTool) {
                                    final screenSnapMm = (8.0 / scale).clamp(
                                      1.5,
                                      8.0,
                                    );
                                    _drawStartAltPressed = _isAltPressed();

                                    CadPoint2D effectiveStart;
                                    if (_drawStartAltPressed) {
                                      // Free mode for start point when Alt is held
                                      effectiveStart = cadPt;
                                    } else {
                                      // Magnetic snap to nearest geometry/spanning point
                                      viewModel.updateCursorMm(
                                        cadPt,
                                        snapRadiusMm: screenSnapMm,
                                      );
                                      effectiveStart =
                                          viewModel.activeSnap?.point ??
                                          viewModel.resolveEffectivePoint(
                                            cadPt,
                                            snapRadiusMm: screenSnapMm,
                                          );
                                    }

                                    _activeDrag = _DragTarget.drawEntity;
                                    _drawDragStartScreen = touchScreen;
                                    _drawDragCurrentScreen = touchScreen;
                                    _drawDragStartCad = effectiveStart;
                                    _drawDragCommitted = false;

                                    if (viewModel.pendingBendStart == null &&
                                        viewModel.toolMode !=
                                            StudioToolMode.drawArc &&
                                        viewModel.toolMode !=
                                            StudioToolMode.drawPolyline &&
                                        viewModel.toolMode !=
                                            StudioToolMode.addDimension) {
                                      viewModel.setPendingBendStart(
                                        effectiveStart,
                                      );
                                    }
                                    setState(() {});
                                  } else if (viewModel.toolMode ==
                                      StudioToolMode.select) {
                                    // In Select mode, dragging on blank canvas starts box selection
                                    _activeDrag = _DragTarget.boxSelect;
                                    _boxSelectStart = touchScreen;
                                    _boxSelectCurrent = touchScreen;
                                    setState(() {});
                                  } else {
                                    // Dragging on blank canvas/surface in other modes pans the 2D flat view
                                    _activeDrag = _DragTarget.canvasPan;
                                  }
                                }
  }

  void _handleCanvasPanUpdate(
    DragUpdateDetails details, {
    required SheetMetalStudioViewModel viewModel,
    required CadPoint2D Function(Offset) screenToCad,
    required Offset Function(CadPoint2D) cadToScreen,
    required double scale,
    required Size size,
    FoldBendLine? selectedBend,
    CadLineSegment? selectedCut,
    CncPunchPrimitive? selectedPunch,
  }) {
                                if (_activeDrag == _DragTarget.boxSelect) {
                                  setState(() {
                                    _boxSelectCurrent = details.localPosition;
                                  });
                                  return;
                                }

                                final cadPt = screenToCad(
                                  details.localPosition,
                                );

                                if (_activeDrag == _DragTarget.drawEntity) {
                                  _drawDragCurrentScreen =
                                      details.localPosition;
                                  final screenSnapMm = (8.0 / scale).clamp(
                                    1.5,
                                    8.0,
                                  );
                                  final isEndAlt = _isAltPressed();

                                  final isLineTool =
                                      viewModel.toolMode ==
                                          StudioToolMode.addBend ||
                                      viewModel.toolMode ==
                                          StudioToolMode.addFlange ||
                                      viewModel.toolMode ==
                                          StudioToolMode.addCut ||
                                      viewModel.toolMode ==
                                          StudioToolMode.dragDimension ||
                                      viewModel.toolMode ==
                                          StudioToolMode.addDimension ||
                                      viewModel.toolMode ==
                                          StudioToolMode.drawPolyline;

                                  CadPoint2D effectivePt = cadPt;

                                  if (isEndAlt) {
                                    // Alt is pressed during drag: end point moves freely without snapping
                                    effectivePt = cadPt;
                                    viewModel.clearSnap();
                                    if (isLineTool &&
                                        _drawDragStartCad != null) {
                                      final dx =
                                          effectivePt.x - _drawDragStartCad!.x;
                                      final dy =
                                          effectivePt.y - _drawDragStartCad!.y;
                                      double angle =
                                          math.atan2(dy, dx) * 180.0 / math.pi;
                                      if (angle < 0) angle += 360.0;
                                      final toolLabel =
                                          viewModel.toolMode ==
                                              StudioToolMode.addCut
                                          ? "CUT"
                                          : (viewModel.toolMode ==
                                                        StudioToolMode
                                                            .dragDimension ||
                                                    viewModel.toolMode ==
                                                        StudioToolMode
                                                            .addDimension
                                                ? "DIM"
                                                : (viewModel.toolMode ==
                                                          StudioToolMode
                                                              .drawPolyline
                                                      ? "LINE"
                                                      : "BEND"));
                                      _dragAngleInfo = (
                                        point: effectivePt,
                                        label:
                                            '$toolLabel ${angle.round() % 360}° (Alt Free)',
                                      );
                                    } else {
                                      _dragAngleInfo = null;
                                    }
                                  } else {
                                    // Alt is not pressed: end point snaps on 5 degrees and nearest geometry
                                    if (isLineTool &&
                                        _drawDragStartCad != null) {
                                      effectivePt =
                                          SheetMetalStudioViewModel.snapEndpointAngle(
                                            anchor: _drawDragStartCad!,
                                            target: effectivePt,
                                            isAlt: false,
                                          );
                                      final dx =
                                          effectivePt.x - _drawDragStartCad!.x;
                                      final dy =
                                          effectivePt.y - _drawDragStartCad!.y;
                                      double angle =
                                          math.atan2(dy, dx) * 180.0 / math.pi;
                                      if (angle < 0) angle += 360.0;
                                      final toolLabel =
                                          viewModel.toolMode ==
                                              StudioToolMode.addCut
                                          ? "CUT"
                                          : (viewModel.toolMode ==
                                                        StudioToolMode
                                                            .dragDimension ||
                                                    viewModel.toolMode ==
                                                        StudioToolMode
                                                            .addDimension
                                                ? "DIM"
                                                : (viewModel.toolMode ==
                                                          StudioToolMode
                                                              .drawPolyline
                                                      ? "LINE"
                                                      : "BEND"));
                                      _dragAngleInfo = (
                                        point: effectivePt,
                                        label:
                                            '$toolLabel ${angle.round() % 360}°',
                                      );
                                    } else {
                                      _dragAngleInfo = null;
                                    }

                                    // Magnetic snapping to nearest entity
                                    viewModel.updateCursorMm(
                                      effectivePt,
                                      snapRadiusMm: screenSnapMm,
                                    );
                                    effectivePt =
                                        viewModel.activeSnap?.point ??
                                        effectivePt;
                                  }

                                  viewModel.updateRubberBand(effectivePt);
                                  setState(() {});
                                  return;
                                }

                                // Determine fixed anchor for line endpoint dragging to anchor angle snapping
                                CadPoint2D? anchor;
                                bool isCutLineDrag = false;

                                if (_activeDrag == _DragTarget.bendP1) {
                                  final targetBendId =
                                      _draggedBendId ?? selectedBend?.id;
                                  final b = viewModel.document.bends
                                      .cast<FoldBendLine?>()
                                      .firstWhere(
                                        (x) => x?.id == targetBendId,
                                        orElse: () => null,
                                      );
                                  if (b != null) anchor = b.p2;
                                } else if (_activeDrag == _DragTarget.bendP2) {
                                  final targetBendId =
                                      _draggedBendId ?? selectedBend?.id;
                                  final b = viewModel.document.bends
                                      .cast<FoldBendLine?>()
                                      .firstWhere(
                                        (x) => x?.id == targetBendId,
                                        orElse: () => null,
                                      );
                                  if (b != null) anchor = b.p1;
                                } else if (_activeDrag == _DragTarget.cutP1) {
                                  isCutLineDrag = true;
                                  final targetCutId =
                                      _draggedCutId ?? selectedCut?.id;
                                  final c = viewModel.document.cutLines
                                      .cast<CadLineSegment?>()
                                      .firstWhere(
                                        (x) => x?.id == targetCutId,
                                        orElse: () => null,
                                      );
                                  if (c != null) anchor = c.p2;
                                } else if (_activeDrag == _DragTarget.cutP2) {
                                  isCutLineDrag = true;
                                  final targetCutId =
                                      _draggedCutId ?? selectedCut?.id;
                                  final c = viewModel.document.cutLines
                                      .cast<CadLineSegment?>()
                                      .firstWhere(
                                        (x) => x?.id == targetCutId,
                                        orElse: () => null,
                                      );
                                  if (c != null) anchor = c.p1;
                                }

                                CadPoint2D candidate = cadPt;
                                int currentAngleDeg = 0;
                                bool isAlt = false;
                                try {
                                  isAlt =
                                      HardwareKeyboard.instance.isAltPressed;
                                } catch (_) {}

                                if (anchor != null) {
                                  candidate =
                                      SheetMetalStudioViewModel.snapEndpointAngle(
                                        anchor: anchor,
                                        target: cadPt,
                                        isAlt: isAlt,
                                      );
                                  final dx = candidate.x - anchor.x;
                                  final dy = candidate.y - anchor.y;
                                  double angle =
                                      math.atan2(dy, dx) * 180.0 / math.pi;
                                  if (angle < 0) angle += 360.0;
                                  currentAngleDeg = angle.round() % 360;
                                }

                                // Live magnetic snap update during dragging (lines snap, punches move smoothly)
                                if (_activeDrag == _DragTarget.bendP1 ||
                                    _activeDrag == _DragTarget.bendP2 ||
                                    _activeDrag == _DragTarget.cutP1 ||
                                    _activeDrag == _DragTarget.cutP2) {
                                  final screenSnapMm = (8.0 / scale).clamp(
                                    1.5,
                                    8.0,
                                  );
                                  viewModel.updateCursorMm(
                                    candidate,
                                    snapRadiusMm: screenSnapMm,
                                  );
                                }
                                final effectivePt =
                                    viewModel.activeSnap?.point ?? candidate;

                                if (anchor != null) {
                                  _dragAngleInfo = (
                                    point: effectivePt,
                                    label:
                                        '${isCutLineDrag ? "CUT" : "BEND"} $currentAngleDeg° ${isAlt ? "(Alt Free)" : ""}',
                                  );
                                } else {
                                  _dragAngleInfo = null;
                                }

                                switch (_activeDrag) {
                                  case _DragTarget.boxSelect:
                                    break;

                                  case _DragTarget.canvasPan:
                                    viewModel.pan2DCanvas(details.delta);
                                    break;

                                  case _DragTarget.cover:
                                    if (viewModel.document.cover != null) {
                                      final screenDelta =
                                          details.localPosition -
                                          _dragStartScreen;
                                      final cadDeltaX = screenDelta.dx / scale;
                                      final cadDeltaY = screenDelta.dy / scale;
                                      final newOffset = CadPoint2D(
                                        _coverDragStartOffset.x + cadDeltaX,
                                        _coverDragStartOffset.y + cadDeltaY,
                                      );
                                      final updatedCover = viewModel
                                          .document
                                          .cover!
                                          .copyWith(
                                            placementMode2D:
                                                CoverPlacementMode2D.custom,
                                            offset2D: newOffset,
                                          );
                                      viewModel.setDocumentFromSolver(
                                        viewModel.document.copyWith(
                                          cover: updatedCover,
                                        ),
                                      );
                                    }
                                    break;

                                  case _DragTarget.portBadge:
                                    if (_draggedPortBadgeId != null) {
                                      if ((details.localPosition -
                                                  _dragStartScreen)
                                              .distance >
                                          4.0) {
                                        _hasMovedPortBadge = true;
                                      }
                                      final currentOffset =
                                          _dragPortBadgeStartOffset +
                                          (details.localPosition -
                                              _dragStartScreen);
                                      viewModel.setPortBadgeOffset(
                                        _draggedPortBadgeId!,
                                        currentOffset,
                                      );
                                    }
                                    break;

                                  case _DragTarget.dimensionBadge:
                                    if (_draggedDimId != null) {
                                      final currentOffset =
                                          _dragDimensionStartOffset +
                                          (details.localPosition -
                                              _dragStartScreen);
                                      viewModel.setDimensionOffset(
                                        _draggedDimId!,
                                        currentOffset,
                                      );
                                    }
                                    break;

                                  case _DragTarget.dimensionLine:
                                    if (_draggedDimLineId != null) {
                                      final dim = viewModel.document.dimensions
                                          .where(
                                            (d) => d.id == _draggedDimLineId,
                                          )
                                          .firstOrNull;
                                      if (dim != null) {
                                        final assoc =
                                            AssociativeDimensionEngine.resolveAssociation(
                                              dim,
                                              viewModel.document,
                                            );
                                        final pA = assoc.pA;
                                        final pB = assoc.pB;
                                        double newOffset =
                                            dim.dimensionLineOffset;

                                        if (dim.type ==
                                            CadDimensionType.horizontal) {
                                          final minY = math.min(pA.y, pB.y);
                                          newOffset = minY - cadPt.y;
                                        } else if (dim.type ==
                                            CadDimensionType.vertical) {
                                          final minX = math.min(pA.x, pB.x);
                                          newOffset = minX - cadPt.x;
                                        } else {
                                          final dx = pB.x - pA.x;
                                          final dy = pB.y - pA.y;
                                          final len = math.sqrt(
                                            dx * dx + dy * dy,
                                          );
                                          if (len > 1e-4) {
                                            final nx = -dy / len;
                                            final ny = dx / len;
                                            newOffset =
                                                (cadPt.x - pA.x) * nx +
                                                (cadPt.y - pA.y) * ny;
                                          }
                                        }
                                        viewModel.setDimensionLineOffset(
                                          _draggedDimLineId!,
                                          newOffset,
                                        );
                                      } else {
                                        final seg =
                                            _dimensionLineSegments[_draggedDimLineId!];
                                        if (seg != null) {
                                          double newOffset = seg.offsetDist;
                                          if (seg.type ==
                                              CadDimensionType.horizontal) {
                                            final refY = math.min(
                                              seg.ptA.y,
                                              seg.ptB.y,
                                            );
                                            newOffset = math.max(
                                              6.0,
                                              (refY - cadPt.y).abs(),
                                            );
                                          } else if (seg.type ==
                                              CadDimensionType.vertical) {
                                            final refX = math.min(
                                              seg.ptA.x,
                                              seg.ptB.x,
                                            );
                                            newOffset = math.max(
                                              6.0,
                                              (refX - cadPt.x).abs(),
                                            );
                                          }
                                          viewModel.setDimensionLineOffset(
                                            _draggedDimLineId!,
                                            newOffset,
                                          );
                                        }
                                      }
                                    }
                                    break;

                                  case _DragTarget.punch:
                                    final targetCenter = CadPoint2D(
                                      candidate.x + _dragPunchOffsetCad.x,
                                      candidate.y + _dragPunchOffsetCad.y,
                                    );
                                    viewModel.moveSelectedPunch(targetCenter);
                                    break;

                                  case _DragTarget.multiEntity:
                                    final cadDelta = CadPoint2D(
                                      details.delta.dx / scale,
                                      details.delta.dy / scale,
                                    );
                                    if (cadDelta.x.abs() > 0.0 ||
                                        cadDelta.y.abs() > 0.0) {
                                      viewModel.moveSelectedEntities(
                                        cadDelta.x,
                                        cadDelta.y,
                                      );
                                    }
                                    break;

                                  case _DragTarget.pattern:
                                    if (viewModel.selectedPatternId != null &&
                                        details.delta.distance > 0.05) {
                                      viewModel.movePattern(
                                        viewModel.selectedPatternId!,
                                        candidate,
                                      );
                                    }
                                    break;

                                  case _DragTarget.bendP1:
                                    final targetBendId =
                                        _draggedBendId ?? selectedBend?.id;
                                    if (targetBendId != null) {
                                      viewModel.updateBendEndpoint(
                                        bendId: targetBendId,
                                        isP1: true,
                                        newPoint: effectivePt,
                                      );
                                    }
                                    break;

                                  case _DragTarget.bendP2:
                                    final targetBendId =
                                        _draggedBendId ?? selectedBend?.id;
                                    if (targetBendId != null) {
                                      viewModel.updateBendEndpoint(
                                        bendId: targetBendId,
                                        isP1: false,
                                        newPoint: effectivePt,
                                      );
                                    }
                                    break;

                                  case _DragTarget.bendBody:
                                    final cadDelta = CadPoint2D(
                                      details.delta.dx / scale,
                                      details.delta.dy / scale,
                                    );
                                    if (cadDelta.x.abs() > 0.0 ||
                                        cadDelta.y.abs() > 0.0) {
                                      viewModel.moveSelectedBend(cadDelta);
                                    }
                                    break;

                                  case _DragTarget.cutP1:
                                    final targetCutId =
                                        _draggedCutId ?? selectedCut?.id;
                                    if (targetCutId != null) {
                                      viewModel.updateCutEndpoint(
                                        cutId: targetCutId,
                                        isP1: true,
                                        newPoint: effectivePt,
                                      );
                                    }
                                    break;

                                  case _DragTarget.cutP2:
                                    final targetCutId =
                                        _draggedCutId ?? selectedCut?.id;
                                    if (targetCutId != null) {
                                      viewModel.updateCutEndpoint(
                                        cutId: targetCutId,
                                        isP1: false,
                                        newPoint: effectivePt,
                                      );
                                    }
                                    break;

                                  case _DragTarget.cutBody:
                                    final cadDeltaCut = CadPoint2D(
                                      details.delta.dx / scale,
                                      details.delta.dy / scale,
                                    );
                                    if (cadDeltaCut.x.abs() > 0.0 ||
                                        cadDeltaCut.y.abs() > 0.0) {
                                      viewModel.moveSelectedCut(cadDeltaCut);
                                    }
                                    break;

                                  case _DragTarget.drawEntity:
                                    break;

                                  case _DragTarget.none:
                                    break;
                                }
  }

  void _handleCanvasPanEnd(
    DragEndDetails details, {
    required SheetMetalStudioViewModel viewModel,
    required CadPoint2D Function(Offset) screenToCad,
    required Offset Function(CadPoint2D) cadToScreen,
    required double scale,
  }) {
                                if (_activeDrag == _DragTarget.drawEntity) {
                                  final dragDist =
                                      (_drawDragStartScreen != null &&
                                          _drawDragCurrentScreen != null)
                                      ? (_drawDragCurrentScreen! -
                                                _drawDragStartScreen!)
                                            .distance
                                      : 0.0;
                                  final screenSnapMm = (8.0 / scale).clamp(
                                    1.5,
                                    8.0,
                                  );

                                  if (dragDist > 6.0) {
                                    // Onshape-style: Drag & Release committed the entity!
                                    final endScreen =
                                        _drawDragCurrentScreen ??
                                        _drawDragStartScreen!;
                                    final endCad = screenToCad(endScreen);
                                    final isEndAlt = _isAltPressed();

                                    final isLineTool =
                                        viewModel.toolMode ==
                                            StudioToolMode.addBend ||
                                        viewModel.toolMode ==
                                            StudioToolMode.addFlange ||
                                        viewModel.toolMode ==
                                            StudioToolMode.addCut ||
                                        viewModel.toolMode ==
                                            StudioToolMode.dragDimension ||
                                        viewModel.toolMode ==
                                            StudioToolMode.addDimension ||
                                        viewModel.toolMode ==
                                            StudioToolMode.drawPolyline;

                                    CadPoint2D effectiveEnd = endCad;
                                    if (isEndAlt) {
                                      // Free mode for end point (Alt held at release)
                                      effectiveEnd = endCad;
                                    } else {
                                      // Snapped mode for end point (Alt NOT held at release)
                                      if (_drawDragStartCad != null &&
                                          isLineTool) {
                                        effectiveEnd =
                                            SheetMetalStudioViewModel.snapEndpointAngle(
                                              anchor: _drawDragStartCad!,
                                              target: effectiveEnd,
                                              isAlt: false,
                                            );
                                      }
                                      viewModel.updateCursorMm(
                                        effectiveEnd,
                                        snapRadiusMm: screenSnapMm,
                                      );
                                      effectiveEnd =
                                          viewModel.activeSnap?.point ??
                                          effectiveEnd;
                                    }

                                    if (viewModel.toolMode ==
                                            StudioToolMode.drawCircle ||
                                        viewModel.toolMode ==
                                            StudioToolMode.addPunchRound) {
                                      final center =
                                          _drawDragStartCad ??
                                          viewModel.pendingBendStart ??
                                          effectiveEnd;
                                      final radius = center.distanceTo(
                                        effectiveEnd,
                                      );
                                      final diam = radius > 0.5
                                          ? radius * 2.0
                                          : (viewModel
                                                        .toolConfig
                                                        .roundHoleDiameter >
                                                    0
                                                ? viewModel
                                                      .toolConfig
                                                      .roundHoleDiameter
                                                : 10.0);
                                      final newId =
                                          'P${viewModel.document.punches.length + 1}';
                                      final p = CncTurretEngine.createRoundHole(
                                        id: newId,
                                        center: center,
                                        diameterMm: diam,
                                      );
                                      viewModel.addPunch(p);
                                      viewModel.selectPunch(p.id);
                                      viewModel.setPendingBendStart(null);
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                    } else if (viewModel.toolMode ==
                                            StudioToolMode.drawRectangle ||
                                        viewModel.toolMode ==
                                            StudioToolMode.addPunchSquare) {
                                      final startPt =
                                          _drawDragStartCad ??
                                          viewModel.pendingBendStart ??
                                          effectiveEnd;
                                      final rawW = (effectiveEnd.x - startPt.x)
                                          .abs();
                                      final rawH = (effectiveEnd.y - startPt.y)
                                          .abs();
                                      final double effW;
                                      final double effH;
                                      if (viewModel
                                          .toolConfig
                                          .squareAspectLocked) {
                                        final side = math.max(rawW, rawH);
                                        effW = side > 1.0
                                            ? side
                                            : (viewModel.toolConfig.squareSize >
                                                      0
                                                  ? viewModel
                                                        .toolConfig
                                                        .squareSize
                                                  : 20.0);
                                        effH = effW;
                                      } else {
                                        effW = rawW > 1.0
                                            ? rawW
                                            : (viewModel.toolConfig.rectWidth >
                                                      0
                                                  ? viewModel
                                                        .toolConfig
                                                        .rectWidth
                                                  : 20.0);
                                        effH = rawH > 1.0
                                            ? rawH
                                            : (viewModel.toolConfig.rectHeight >
                                                      0
                                                  ? viewModel
                                                        .toolConfig
                                                        .rectHeight
                                                  : 20.0);
                                      }
                                      final center = CadPoint2D(
                                        (startPt.x + effectiveEnd.x) / 2.0,
                                        (startPt.y + effectiveEnd.y) / 2.0,
                                      );
                                      final newId =
                                          'P${viewModel.document.punches.length + 1}';
                                      final p =
                                          CncTurretEngine.createRectangularPunch(
                                            id: newId,
                                            center: center,
                                            widthMm: effW,
                                            heightMm: effH,
                                          );
                                      viewModel.addPunch(p);
                                      viewModel.selectPunch(p.id);
                                      viewModel.setPendingBendStart(null);
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                    } else if (viewModel.toolMode ==
                                        StudioToolMode.addPunchObround) {
                                      final center =
                                          _drawDragStartCad ?? effectiveEnd;
                                      final w =
                                          (effectiveEnd.x - center.x).abs() *
                                          2.0;
                                      final l =
                                          (effectiveEnd.y - center.y).abs() *
                                          2.0;
                                      final effW = w > 2.0
                                          ? w
                                          : viewModel.toolConfig.obroundLength;
                                      final effL = l > 2.0
                                          ? l
                                          : viewModel.toolConfig.obroundWidth;
                                      final newId =
                                          'P${viewModel.document.punches.length + 1}';
                                      final p =
                                          CncTurretEngine.createObroundSlot(
                                            id: newId,
                                            center: center,
                                            widthMm: effW,
                                            lengthMm: effL,
                                          );
                                      viewModel.addPunch(p);
                                      viewModel.selectPunch(p.id);
                                      viewModel.setPendingBendStart(null);
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                    } else if (viewModel.toolMode ==
                                            StudioToolMode.dragDimension ||
                                        viewModel.toolMode ==
                                            StudioToolMode.addDimension) {
                                      final start =
                                          _drawDragStartCad ??
                                          viewModel.pendingBendStart ??
                                          effectiveEnd;
                                      final end = effectiveEnd;
                                      final dist = start.distanceTo(end);
                                      if (dist > 0.5) {
                                        viewModel.commitDragDimension(
                                          pA: start,
                                          pB: end,
                                        );
                                      }
                                      viewModel.setPendingBendStart(null);
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                    } else if (viewModel.toolMode ==
                                            StudioToolMode.addBend ||
                                        viewModel.toolMode ==
                                            StudioToolMode.addFlange) {
                                      final p1 =
                                          _drawDragStartCad ??
                                          viewModel.pendingBendStart ??
                                          effectiveEnd;
                                      final p2 = effectiveEnd;
                                      viewModel.setPendingBendStart(null);
                                      if (p1.distanceTo(p2) > 1.0) {
                                        if (viewModel.toolMode ==
                                            StudioToolMode.addFlange) {
                                          viewModel.addFlangeLine(p1, p2);
                                        } else {
                                          viewModel.addBendLine(p1, p2);
                                        }
                                      }
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                    } else if (viewModel.toolMode ==
                                        StudioToolMode.addCut) {
                                      final p1 =
                                          _drawDragStartCad ??
                                          viewModel.pendingBendStart ??
                                          effectiveEnd;
                                      final p2 = effectiveEnd;
                                      viewModel.setPendingBendStart(null);
                                      if (p1.distanceTo(p2) > 1.0) {
                                        viewModel.addCutLine(p1, p2);
                                      }
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                    } else {
                                      viewModel.handleCanvasClick(
                                        effectiveEnd,
                                        snapRadiusMm: screenSnapMm,
                                        autoPlace: false,
                                      );
                                      if (viewModel.selectedDimensionId !=
                                          null) {
                                        final newlyCreated = viewModel
                                            .document
                                            .dimensions
                                            .where(
                                              (d) =>
                                                  d.id ==
                                                  viewModel.selectedDimensionId,
                                            )
                                            .firstOrNull;
                                        if (newlyCreated != null) {
                                          final badgePos =
                                              _drawDragCurrentScreen ??
                                              _drawDragStartScreen ??
                                              Offset.zero;
                                          _startInPlaceDimensionEdit(
                                            dimId: newlyCreated.id,
                                            badgeRect: Rect.fromCenter(
                                              center: badgePos,
                                              width: 60,
                                              height: 22,
                                            ),
                                            initialValue:
                                                newlyCreated.measuredValue,
                                            pA: newlyCreated.pointA,
                                            pB: newlyCreated.pointB,
                                            referenceAId:
                                                newlyCreated.referenceAId,
                                            referenceBId:
                                                newlyCreated.referenceBId,
                                            offset: newlyCreated
                                                .dimensionLineOffset,
                                          );
                                        }
                                      }
                                    }
                                    _drawDragCommitted = true;
                                  } else {
                                    // Single click without drag (<= 6px)
                                    final clickCad =
                                        _drawDragStartCad ??
                                        viewModel.pendingBendStart;

                                    if (clickCad != null &&
                                        (viewModel.toolMode ==
                                                StudioToolMode.drawRectangle ||
                                            viewModel.toolMode ==
                                                StudioToolMode
                                                    .addPunchSquare)) {
                                      final center = clickCad;
                                      final w =
                                          viewModel
                                              .toolConfig
                                              .squareAspectLocked
                                          ? viewModel.toolConfig.squareSize
                                          : viewModel.toolConfig.rectWidth;
                                      final h =
                                          viewModel
                                              .toolConfig
                                              .squareAspectLocked
                                          ? viewModel.toolConfig.squareSize
                                          : viewModel.toolConfig.rectHeight;
                                      final effW = w > 0 ? w : 20.0;
                                      final effH = h > 0 ? h : 20.0;
                                      final newId =
                                          'P${viewModel.document.punches.length + 1}';
                                      final p =
                                          CncTurretEngine.createRectangularPunch(
                                            id: newId,
                                            center: center,
                                            widthMm: effW,
                                            heightMm: effH,
                                          );
                                      viewModel.addPunch(p);
                                      viewModel.selectPunch(p.id);
                                      viewModel.setPendingBendStart(null);
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                      _drawDragCommitted = true;
                                    } else if (clickCad != null &&
                                        (viewModel.toolMode ==
                                                StudioToolMode.drawCircle ||
                                            viewModel.toolMode ==
                                                StudioToolMode.addPunchRound)) {
                                      final center = clickCad;
                                      final diam =
                                          viewModel
                                                  .toolConfig
                                                  .roundHoleDiameter >
                                              0
                                          ? viewModel
                                                .toolConfig
                                                .roundHoleDiameter
                                          : 10.0;
                                      final newId =
                                          'P${viewModel.document.punches.length + 1}';
                                      final p = CncTurretEngine.createRoundHole(
                                        id: newId,
                                        center: center,
                                        diameterMm: diam,
                                      );
                                      viewModel.addPunch(p);
                                      viewModel.selectPunch(p.id);
                                      viewModel.setPendingBendStart(null);
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                      _drawDragCommitted = true;
                                    } else if (clickCad != null &&
                                        viewModel.toolMode ==
                                            StudioToolMode.addPunchObround) {
                                      final center = clickCad;
                                      final effW =
                                          viewModel.toolConfig.obroundLength > 0
                                          ? viewModel.toolConfig.obroundLength
                                          : 25.0;
                                      final effL =
                                          viewModel.toolConfig.obroundWidth > 0
                                          ? viewModel.toolConfig.obroundWidth
                                          : 10.0;
                                      final newId =
                                          'P${viewModel.document.punches.length + 1}';
                                      final p =
                                          CncTurretEngine.createObroundSlot(
                                            id: newId,
                                            center: center,
                                            widthMm: effW,
                                            lengthMm: effL,
                                          );
                                      viewModel.addPunch(p);
                                      viewModel.selectPunch(p.id);
                                      viewModel.setPendingBendStart(null);
                                      viewModel.setToolMode(
                                        StudioToolMode.select,
                                      );
                                      _drawDragCommitted = true;
                                    } else if (clickCad != null &&
                                        viewModel.toolMode ==
                                            StudioToolMode.dragDimension) {
                                      if (viewModel.pendingBendStart == null) {
                                        viewModel.setPendingBendStart(clickCad);
                                      } else {
                                        final pA = viewModel.pendingBendStart!;
                                        final pB = clickCad;
                                        if (pA.distanceTo(pB) > 0.5) {
                                          viewModel.commitDragDimension(
                                            pA: pA,
                                            pB: pB,
                                          );
                                        }
                                        viewModel.setPendingBendStart(null);
                                        viewModel.setToolMode(
                                          StudioToolMode.select,
                                        );
                                      }
                                      _drawDragCommitted = true;
                                    } else {
                                      // Standard multi-click line/polyline/arc drawing:
                                      if (viewModel.pendingBendStart != null &&
                                          _drawDragStartCad != null &&
                                          viewModel.pendingBendStart !=
                                              _drawDragStartCad) {
                                        viewModel.handleCanvasClick(
                                          _drawDragStartCad!,
                                          snapRadiusMm: screenSnapMm,
                                          autoPlace: false,
                                        );
                                        if (viewModel.selectedDimensionId !=
                                            null) {
                                          final newlyCreated = viewModel
                                              .document
                                              .dimensions
                                              .where(
                                                (d) =>
                                                    d.id ==
                                                    viewModel
                                                        .selectedDimensionId,
                                              )
                                              .firstOrNull;
                                          if (newlyCreated != null) {
                                            final badgePos =
                                                _drawDragCurrentScreen ??
                                                _drawDragStartScreen ??
                                                Offset.zero;
                                            _startInPlaceDimensionEdit(
                                              dimId: newlyCreated.id,
                                              badgeRect: Rect.fromCenter(
                                                center: badgePos,
                                                width: 60,
                                                height: 22,
                                              ),
                                              initialValue:
                                                  newlyCreated.measuredValue,
                                              pA: newlyCreated.pointA,
                                              pB: newlyCreated.pointB,
                                              referenceAId:
                                                  newlyCreated.referenceAId,
                                              referenceBId:
                                                  newlyCreated.referenceBId,
                                              offset: newlyCreated
                                                  .dimensionLineOffset,
                                            );
                                          }
                                        }
                                        _drawDragCommitted = true;
                                      } else {
                                        if (viewModel.pendingBendStart ==
                                                null &&
                                            _drawDragStartCad != null) {
                                          if (viewModel.toolMode ==
                                              StudioToolMode.addDimension) {
                                            viewModel.handleCanvasClick(
                                              _drawDragStartCad!,
                                              snapRadiusMm: screenSnapMm,
                                              autoPlace: false,
                                            );
                                          } else {
                                            viewModel.setPendingBendStart(
                                              _drawDragStartCad,
                                            );
                                          }
                                        }
                                        _drawDragCommitted = true;
                                      }
                                    }
                                  }

                                  _activeDrag = _DragTarget.none;
                                  _drawDragStartScreen = null;
                                  _drawDragCurrentScreen = null;
                                  _drawDragStartCad = null;
                                  _dragAngleInfo = null;
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) _drawDragCommitted = false;
                                  });
                                  setState(() {});
                                  return;
                                }

                                if (_activeDrag == _DragTarget.boxSelect) {
                                  if (_boxSelectStart != null &&
                                      _boxSelectCurrent != null) {
                                    final dist =
                                        (_boxSelectCurrent! - _boxSelectStart!)
                                            .distance;
                                    if (dist > 6.0) {
                                      final p1 = screenToCad(_boxSelectStart!);
                                      final p2 = screenToCad(
                                        _boxSelectCurrent!,
                                      );
                                      final cadBox = Rect.fromPoints(
                                        Offset(p1.x, p1.y),
                                        Offset(p2.x, p2.y),
                                      );
                                      final Set<String> selectedIds;
                                      if (_boxSelectCurrent!.dx >=
                                          _boxSelectStart!.dx) {
                                        // Window selection (Left-to-Right): strictly contained
                                        selectedIds =
                                            MagneticSnapEngine.evaluateWindowSelection(
                                              doc: viewModel.document,
                                              cadBox: cadBox,
                                            );
                                      } else {
                                        // Crossing selection (Right-to-Left): touches or intersects
                                        selectedIds =
                                            MagneticSnapEngine.evaluateCrossingSelection(
                                              doc: viewModel.document,
                                              cadBox: cadBox,
                                            );
                                      }
                                      final isShiftHeld = _isShiftPressed();

                                      if (isShiftHeld) {
                                        viewModel.selectEntities({
                                          ...viewModel.selectedEntityIds,
                                          ...selectedIds,
                                        });
                                      } else {
                                        viewModel.selectEntities(selectedIds);
                                      }
                                    } else {
                                      final isShiftHeld = _isShiftPressed();
                                      if (!isShiftHeld) {
                                        viewModel.clearSelection();
                                      }
                                    }
                                  }
                                  _boxSelectStart = null;
                                  _boxSelectCurrent = null;
                                  _activeDrag = _DragTarget.none;
                                  _shiftSelectionHandledInPan = false;
                                  setState(() {});
                                  return;
                                }

                                if (_draggedPortBadgeId != null &&
                                    !_hasMovedPortBadge) {
                                  final pId = _draggedPortBadgeId!;
                                  _draggedPortBadgeId = null;
                                  _activeDrag = _DragTarget.none;
                                  _shiftSelectionHandledInPan = false;
                                  _openPortDimensionEditor(pId);
                                  return;
                                }

                                if (_activeDrag == _DragTarget.dimensionLine) {
                                  if (_draggedDimLineId != null) {
                                    viewModel.commitDimensionLineOffset(
                                      _draggedDimLineId!,
                                    );
                                  }
                                  _draggedDimLineId = null;
                                  _activeDrag = _DragTarget.none;
                                  _shiftSelectionHandledInPan = false;
                                  setState(() {});
                                  return;
                                }

                                final wasObjectDrag =
                                    _activeDrag != _DragTarget.none &&
                                    _activeDrag != _DragTarget.canvasPan;
                                _draggedBendId = null;
                                _draggedCutId = null;
                                _draggedPortBadgeId = null;
                                _draggedDimLineId = null;
                                _dragPunchOffsetCad = const CadPoint2D(0, 0);
                                _activeDrag = _DragTarget.none;
                                _dragAngleInfo = null;
                                _shiftSelectionHandledInPan = false;
                                if (wasObjectDrag) {
                                  viewModel.endObjectDrag();
                                }
  }

  void _handleCanvasPanCancel({
    required SheetMetalStudioViewModel viewModel,
  }) {
                                _shiftSelectionHandledInPan = false;
                                _boxSelectStart = null;
                                _boxSelectCurrent = null;
                                if (_activeDrag == _DragTarget.drawEntity) {
                                  _drawDragStartScreen = null;
                                  _drawDragCurrentScreen = null;
                                  _drawDragStartCad = null;
                                  _dragAngleInfo = null;
                                  viewModel.setPendingBendStart(null);
                                }
                                final wasObjectDrag =
                                    _activeDrag != _DragTarget.none &&
                                    _activeDrag != _DragTarget.canvasPan;
                                _draggedBendId = null;
                                _draggedCutId = null;
                                _draggedPortBadgeId = null;
                                _draggedDimLineId = null;
                                _dragPunchOffsetCad = const CadPoint2D(0, 0);
                                _activeDrag = _DragTarget.none;
                                _dragAngleInfo = null;
                                if (wasObjectDrag) {
                                  viewModel.endObjectDrag();
                                }
                                setState(() {});
  }

  void _handleCanvasSecondaryTapUp(
    TapUpDetails details, {
    required SheetMetalStudioViewModel viewModel,
    required CadPoint2D Function(Offset) screenToCad,
    required double scale,
  }) {
                                if (viewModel.toolMode ==
                                        StudioToolMode.drawPolyline &&
                                    viewModel.pendingMultiPoints.isNotEmpty) {
                                  viewModel.finishPolyline(close: false);
                                  return;
                                }
                                if (viewModel.pendingBendStart != null) {
                                  viewModel.clearSnap();
                                  viewModel.setToolMode(viewModel.toolMode);
                                  return;
                                }
                                if (viewModel.toolMode !=
                                    StudioToolMode.select) {
                                  viewModel.setToolMode(StudioToolMode.select);
                                  return;
                                }

                                // Check if right-clicking on or near an outer contour edge for port assignment
                                final cadPt = screenToCad(
                                  details.localPosition,
                                );
                                final contour = viewModel.document.outerContour;
                                CadPoint2D? bestP1;
                                CadPoint2D? bestP2;
                                double minD = double.infinity;
                                for (int i = 0; i < contour.length; i++) {
                                  final p1 = contour[i];
                                  final p2 = contour[(i + 1) % contour.length];
                                  final d =
                                      _distToSegment(cadPt, p1, p2) * scale;
                                  if (d < minD && d <= 28.0) {
                                    minD = d;
                                    bestP1 = p1;
                                    bestP2 = p2;
                                  }
                                }

                                if (bestP1 != null && bestP2 != null) {
                                  setState(() {
                                    _contextMenuP1 = bestP1;
                                    _contextMenuP2 = bestP2;
                                    _contextMenuLenMm = bestP1!.distanceTo(
                                      bestP2!,
                                    );
                                  });
                                  _contextMenuController.open(
                                    position: details.localPosition,
                                  );
                                } else {
                                  viewModel.clearSelection();
                                }
  }

  void _handleCanvasTapUp(
    TapUpDetails details, {
    required BuildContext context,
    required SheetMetalStudioViewModel viewModel,
    required CadPoint2D Function(Offset) screenToCad,
    required Offset Function(CadPoint2D) cadToScreen,
    required double scale,
    required Size size,
  }) {
                                if (_shiftSelectionHandledInPan) {
                                  _shiftSelectionHandledInPan = false;
                                  return;
                                }

                                if (_drawDragCommitted) {
                                  _drawDragCommitted = false;
                                  return;
                                }

                                if (viewModel.toolMode == StudioToolMode.pan) {
                                  return;
                                }

                                // Instant click with software double-tap detection (0ms tap delay!)
                                final now = DateTime.now();
                                final touchScreen = details.localPosition;
                                if (_lastTapTime != null &&
                                    now.difference(_lastTapTime!) <
                                        const Duration(milliseconds: 280) &&
                                    _lastTapPosition != null &&
                                    (touchScreen - _lastTapPosition!)
                                            .distance <=
                                        20.0) {
                                  _lastTapTime = null;
                                  _lastTapPosition = null;
                                  _handleCanvasDoubleTap(
                                    touchScreen,
                                    screenToCad,
                                    cadToScreen,
                                  );
                                  return;
                                }
                                _lastTapTime = now;
                                _lastTapPosition = touchScreen;

                                // Check direct tap on dimension badge (select or delete)
                                for (final entry
                                    in _dimensionBadgeRects.entries) {
                                  if (entry.value
                                      .inflate(4.0)
                                      .contains(touchScreen)) {
                                    final badge = entry.value;
                                    final isDeleteRegion =
                                        touchScreen.dx > (badge.right - 18);
                                    if (isDeleteRegion) {
                                      viewModel.removeDimension(entry.key);
                                      setState(() {
                                        _hoveredDimId = null;
                                      });
                                    } else {
                                      viewModel.selectDimension(entry.key);
                                      _isInspectorCollapsed = false;
                                    }
                                    return;
                                  }
                                }

                                // Check direct tap on constraint badge (select or delete)
                                for (final entry
                                    in _constraintBadgeRects.entries) {
                                  if (entry.value
                                      .inflate(4.0)
                                      .contains(touchScreen)) {
                                    final badge = entry.value;
                                    final isDeleteRegion =
                                        touchScreen.dx > (badge.right - 18);
                                    if (isDeleteRegion) {
                                      viewModel.removeConstraint(entry.key);
                                      setState(() {
                                        _hoveredConstraintId = null;
                                        _constraintHoverHighlightedEntityIds
                                            .clear();
                                      });
                                    } else {
                                      viewModel.selectConstraint(entry.key);
                                    }
                                    return;
                                  }
                                }

                                // Handling interactive geometric constraint picking
                                if (viewModel.activeConstraintPickType !=
                                    null) {
                                  if (viewModel.hoveredPunchId != null) {
                                    viewModel.registerEntityPickForConstraint(
                                      EntityRef.punchCenter(
                                        viewModel.hoveredPunchId!,
                                      ),
                                    );
                                    return;
                                  }
                                  if (viewModel.hoveredBendId != null) {
                                    viewModel.registerEntityPickForConstraint(
                                      EntityRef(
                                        entityId: viewModel.hoveredBendId!,
                                      ),
                                    );
                                    return;
                                  }
                                  if (viewModel.hoveredCutId != null) {
                                    viewModel.registerEntityPickForConstraint(
                                      EntityRef(
                                        entityId: viewModel.hoveredCutId!,
                                      ),
                                    );
                                    return;
                                  }
                                  if (viewModel.hoveredContourEdgeP1 != null &&
                                      viewModel.hoveredContourEdgeP2 != null) {
                                    final p1 = viewModel.hoveredContourEdgeP1!;
                                    final p2 = viewModel.hoveredContourEdgeP2!;
                                    final isVertical =
                                        (p1.x - p2.x).abs() < 1.0;
                                    final bw =
                                        viewModel.document.blankWidthMm > 0
                                        ? viewModel.document.blankWidthMm
                                        : 200.0;
                                    final bl =
                                        viewModel.document.blankLengthMm > 0
                                        ? viewModel.document.blankLengthMm
                                        : 300.0;
                                    final EntityRef edgeRef;
                                    if (isVertical) {
                                      final midX = (p1.x + p2.x) / 2.0;
                                      edgeRef = midX < bw / 2.0
                                          ? EntityRef.edgeLeft
                                          : EntityRef.edgeRight;
                                    } else {
                                      final midY = (p1.y + p2.y) / 2.0;
                                      edgeRef = midY < bl / 2.0
                                          ? EntityRef.edgeBottom
                                          : EntityRef.edgeTop;
                                    }
                                    viewModel.registerEntityPickForConstraint(
                                      edgeRef,
                                    );
                                    return;
                                  }
                                }

                                // Handling 1-Click Semantic Port Inference
                                if (viewModel.toolMode ==
                                        StudioToolMode.assignPortSemantic ||
                                    viewModel.activeSemanticPortId != null) {
                                  final cadPt = screenToCad(
                                    details.localPosition,
                                  );
                                  viewModel.handleCanvasSemanticPortClick(
                                    cadPt,
                                  );
                                  return;
                                }

                                // Handling interactive edge picking for fitting openings (W and H)
                                if (viewModel.toolMode ==
                                        StudioToolMode.pickPortEdge ||
                                    viewModel.activePortPickTarget != null) {
                                  if (viewModel.hoveredContourEdgeP1 != null &&
                                      viewModel.hoveredContourEdgeP2 != null) {
                                    final p1 = viewModel.hoveredContourEdgeP1!;
                                    final p2 = viewModel.hoveredContourEdgeP2!;
                                    final lenMm =
                                        viewModel.hoveredContourEdgeLengthMm ??
                                        p1.distanceTo(p2);
                                    final target =
                                        viewModel.activePortPickTarget!;
                                    final targetName = target.displayName;
                                    final collisionError = viewModel
                                        .completePortEdgePick(
                                          p1: p1,
                                          p2: p2,
                                          measuredLengthMm: lenMm,
                                        );
                                    if (collisionError != null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(
                                                Icons.warning_amber_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  collisionError,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          backgroundColor: const Color(
                                            0xFFDC2626,
                                          ),
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );
                                      return;
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Assigned $targetName: ${lenMm.toStringAsFixed(1)} mm',
                                        ),
                                        backgroundColor: const Color(
                                          0xFF0D9488,
                                        ),
                                        duration: const Duration(seconds: 4),
                                        action: SnackBarAction(
                                          label: 'Open Inspector',
                                          textColor: Colors.amberAccent,
                                          onPressed: () => viewModel
                                              .setFittingInspectorOpen(true),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                }

                                final cadPt = screenToCad(
                                  details.localPosition,
                                );
                                // When in Fillet mode, clicking on a bend line pops up the bend radius editor
                                if (viewModel.toolMode ==
                                    StudioToolMode.cornerFillet) {
                                  FoldBendLine? hitBend;
                                  for (final b in viewModel.document.bends) {
                                    if (_distToSegment(cadPt, b.p1, b.p2) *
                                            scale <=
                                        16.0) {
                                      hitBend = b;
                                      break;
                                    }
                                  }
                                  if (hitBend != null) {
                                    BendRadiusDialog.show(
                                      context,
                                      viewModel,
                                      hitBend,
                                    );
                                    return;
                                  }
                                }
                                final isShiftHeld = _isShiftPressed();
                                final screenSnapMm = (8.0 / scale).clamp(
                                  1.5,
                                  8.0,
                                );
                                viewModel.handleCanvasClick(
                                  cadPt,
                                  snapRadiusMm: screenSnapMm,
                                  autoPlace: true,
                                  multiSelect: isShiftHeld,
                                );
  }
}
