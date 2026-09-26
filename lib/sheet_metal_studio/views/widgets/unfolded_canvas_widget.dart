// =============================================================================
// unfolded_canvas_widget.dart
//
// Interactive 2D Drawing Board for truFold Studio by Danish.
// Features:
// - Light CAD Engineering Theme (Crisp white/slate canvas with drafting grid)
// - Enforced ClipRect preventing any drawing spillover onto headers or menus
// - Mouse wheel zoom (PointerScrollEvent)
// - Draggable Parameter Inspector Sheet (freely repositionable anywhere on canvas)
// - Single-step interactive drag undo for punches, bend lines, and cut lines
// - Interactive rubber-band drawing (0°, 45°, 90° snapping with Alt-override)
// - Incomplete/open bend line visual warning badge and endpoint handles
// - Drag-to-snap individual endpoints P1 / P2 of bend and cut lines to edges
// - Laser Cut Lines (+ Cut tool) for surface slits and edge truncations
// - Interactive CAD bend line dragging and edge constraint leader lines
// - Magnetic snap toggle (ON/OFF) with localized proximity snapping
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cad_primitives.dart';
import '../../models/fold_bend_line.dart';
import '../../models/sheet_metal_definition.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../engine/magnetic_snap_engine.dart';
import '../../engine/cnc_turret_engine.dart';
import '../../models/perforation_pattern.dart';
import '../../engine/press_brake_cam_engine.dart';
import '../../models/planar_sheet_face.dart';
import 'active_tool_property_sheet.dart';
import 'obround_icon.dart';
import 'bend_radius_dialog.dart';
import '../../models/cad_dimension.dart';
import '../../engine/associative_dimension_engine.dart';
import 'cad_property_inspector.dart';
import '../../models/dxf_fitting_metadata.dart';
import '../../services/product_catalog_service.dart';
import '../../models/cad_constraint.dart';
import '../../models/constraints/stable_geometry_reference.dart';
import '../../models/constraints/reference_geometry.dart';
import '../../models/constraints/constraint_definition.dart';
import 'canvas/canvas_reference_painter.dart';
import 'canvas/canvas_constraint_painter.dart';
import 'canvas/constraint_binding_hud.dart';
import 'canvas/constraint_manager_sheet.dart';
import 'canvas/floating_sketch_constraint_bar.dart';
import '../../models/constraints/entity_constraint_state.dart';
import 'studio/studio_sketch_palette.dart';
import 'studio/studio_bottom_bar.dart';
import '../../engine/port_inference_engine.dart';
import '../../engine/fitting_port_annotation_engine.dart';
import 'guided_cms/cms_2d_overlay_painter.dart';
import '../../models/cms/cms_ux_state.dart';
import '../../models/canvas_display_settings.dart';
import '../../models/trunking_cover_data.dart';
import '../../engine/covers/trunking_cover_generator.dart';
import 'cover_flange_dialog.dart';
part 'canvas/canvas_painter.dart';
part 'canvas/canvas_dimension_editor.dart';
part 'canvas/canvas_legend.dart';
part 'canvas/canvas_context_menu_builder.dart';
part 'canvas/canvas_port_dimension_editor.dart';
part 'canvas/canvas_gesture_handler.dart';
part 'canvas/canvas_overlay_stack.dart';

enum _DragTarget {
  none,
  canvasPan,
  boxSelect,
  punch,
  pattern,
  bendBody,
  bendP1,
  bendP2,
  cutBody,
  cutP1,
  cutP2,
  dimensionBadge,
  dimensionLine,
  portBadge,
  drawEntity,
  multiEntity,
  cover,
}

class UnfoldedCanvasWidget extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final bool renderFloatingInspectors;
  final bool showInCanvasToolRibbon;

  const UnfoldedCanvasWidget({
    super.key,
    required this.viewModel,
    this.renderFloatingInspectors = true,
    this.showInCanvasToolRibbon = true,
  });

  @override
  State<UnfoldedCanvasWidget> createState() => _UnfoldedCanvasWidgetState();
}

class _UnfoldedCanvasWidgetState extends State<UnfoldedCanvasWidget>
    with
        CanvasDimensionEditorMixin,
        CanvasPortDimensionEditorMixin,
        CanvasLegendMixin,
        CanvasContextMenuMixin,
        CanvasOverlayStackMixin,
        CanvasGestureHandlerMixin {
  final FocusNode _canvasFocusNode = FocusNode();
  DsfDocument? _lastDoc;
  @override
  void initState() {
    super.initState();
    _lastDoc = widget.viewModel.document;
    _initDimensionEditorMixin();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void didUpdateWidget(covariant UnfoldedCanvasWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
      _boxSelectStart = null;
      _boxSelectCurrent = null;
      _activeDrag = _DragTarget.none;
      _draggedBendId = null;
      _draggedCutId = null;
      _draggedDimId = null;
      _draggedDimLineId = null;
      _draggedPortBadgeId = null;
      _hoveredDimId = null;
      _hoveredConstraintId = null;
      _lastDoc = widget.viewModel.document;
      setState(() {});
    }
  }

  void _onViewModelChanged() {
    if (_lastDoc != null && !identical(_lastDoc, widget.viewModel.document)) {
      if (_activeDrag == _DragTarget.none &&
          !widget.viewModel.isDraggingObject) {
        _boxSelectStart = null;
        _boxSelectCurrent = null;
      }
      _lastDoc = widget.viewModel.document;
    }
    final pendingDimId = widget.viewModel.pendingInPlaceEditDimId;
    if (pendingDimId != null && _editingDimId != pendingDimId) {
      widget.viewModel.clearPendingInPlaceEdit();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final rect =
            _dimensionBadgeRects[pendingDimId] ??
            const Rect.fromLTWH(100, 100, 60, 22);
        final currentValue =
            _dimensionBadgeValues[pendingDimId] ??
            widget.viewModel.document.dimensions
                .where((d) => d.id == pendingDimId)
                .firstOrNull
                ?.measuredValue ??
            0.0;
        _startInPlaceDimensionEdit(
          dimId: pendingDimId,
          badgeRect: rect,
          initialValue: currentValue,
        );
      });
    }
  }

  bool _isEditingText() {
    if (_editingDimId != null) return true;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final ctx = focus.context;
    if (ctx == null || !ctx.mounted) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _disposeDimensionEditorMixin();
    _canvasFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;

    final currentEntity =
        viewModel.selectedBendId ??
        viewModel.selectedPunchId ??
        viewModel.selectedArcId ??
        viewModel.selectedCutId;
    if (currentEntity != null && currentEntity != _lastSelectedEntity) {
      _lastSelectedEntity = currentEntity;
    } else if (currentEntity == null) {
      _lastSelectedEntity = null;
    }

    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);

            // Calculate coordinate transform parameters
            final bw = viewModel.document.blankWidthMm > 0
                ? viewModel.document.blankWidthMm
                : 200.0;
            final bl = viewModel.document.blankLengthMm > 0
                ? viewModel.document.blankLengthMm
                : 300.0;

            var effectiveW = bw;
            var effectiveL = bl;
            if (viewModel.document.cover != null &&
                viewModel.document.cover!.isVisible2D) {
              final coverBbox = TrunkingCoverGenerator.calculateDocumentBbox(
                viewModel.document.cover!.document,
              );
              final coverMaxX =
                  viewModel.document.cover!.offset2D.x + coverBbox.maxX;
              final coverMaxY =
                  viewModel.document.cover!.offset2D.y + coverBbox.maxY;
              if (coverMaxX > effectiveW) effectiveW = coverMaxX + 40.0;
              if (coverMaxY > effectiveL) effectiveL = coverMaxY + 40.0;
            }

            final fitScale = math.min(
              (size.width * 0.75) / effectiveW,
              (size.height * 0.75) / effectiveL,
            );
            final scale = fitScale * viewModel.zoom2D;

            final cx = size.width / 2.0 + viewModel.pan2D.dx;
            final cy = size.height / 2.0 + viewModel.pan2D.dy;

            final originX = cx - (effectiveW / 2.0) * scale;
            final originY = cy - (effectiveL / 2.0) * scale;

            CadPoint2D screenToCad(Offset screenPos) {
              final x = (screenPos.dx - originX) / scale;
              final y = (screenPos.dy - originY) / scale;
              return CadPoint2D(x, y);
            }

            Offset cadToScreen(CadPoint2D pt) {
              return Offset(originX + pt.x * scale, originY + pt.y * scale);
            }

            // Check if a bend, cut, or punch is currently selected
            FoldBendLine? selectedBend;
            if (viewModel.selectedBendId != null) {
              try {
                selectedBend = viewModel.document.bends.firstWhere(
                  (b) => b.id == viewModel.selectedBendId,
                );
              } catch (_) {}
            }

            CadLineSegment? selectedCut;
            if (viewModel.selectedCutId != null) {
              try {
                selectedCut = viewModel.document.cutLines.firstWhere(
                  (c) => c.id == viewModel.selectedCutId,
                );
              } catch (_) {}
            }

            CncPunchPrimitive? selectedPunch;
            if (viewModel.selectedPunchId != null) {
              try {
                selectedPunch = viewModel.document.punches.firstWhere(
                  (p) => p.id == viewModel.selectedPunchId,
                );
              } catch (_) {}
            }

            PerforationPattern? selectedPattern;
            if (viewModel.selectedPatternId != null) {
              try {
                selectedPattern = viewModel.document.perforationPatterns
                    .firstWhere((p) => p.id == viewModel.selectedPatternId);
              } catch (_) {}
            }

            PlanarSheetFace? selectedFace;
            if (viewModel.selectedFaceId != null) {
              try {
                selectedFace = viewModel.document.faces.firstWhere(
                  (f) => f.id == viewModel.selectedFaceId,
                );
              } catch (_) {}
            }

            // Default position for inspector panel (top left corner, below 2D toolbar)
            const defaultInspectorOffset = Offset(16.0, 95.0);
            final effectiveInspectorPos =
                _inspectorOffset ?? defaultInspectorOffset;

            return ClipRect(
              child: Container(
                color: const Color(0xFFF8FAFC), // Light CAD Engineering Canvas
                child: Stack(
                  children: [
                    // 1. Interactive 2D Canvas with Pan, Mouse Wheel Zoom, Hover Snap, Click/Drag, and Arrow Key Nudging
                    Focus(
                      focusNode: _canvasFocusNode,
                      autofocus: true,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          if (_activeEditingPortId != null) {
                            if (event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey ==
                                    LogicalKeyboardKey.numpadEnter) {
                              _applyPortDimensionEditor();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey == LogicalKeyboardKey.escape) {
                              _cancelPortDimensionEditor();
                              return KeyEventResult.handled;
                            }
                          }
                          if (event.logicalKey == LogicalKeyboardKey.escape) {
                            if (_boxSelectStart != null) {
                              _boxSelectStart = null;
                              _boxSelectCurrent = null;
                              _activeDrag = _DragTarget.none;
                              setState(() {});
                              return KeyEventResult.handled;
                            }
                            if (_editingDimId != null) {
                              _cancelInPlaceDimensionEdit();
                              return KeyEventResult.handled;
                            }
                            if (viewModel.selectedConstraintId != null) {
                              viewModel.selectConstraint(null);
                              return KeyEventResult.handled;
                            }
                            if (viewModel.selectedDimensionId != null) {
                              viewModel.selectDimension(null);
                              return KeyEventResult.handled;
                            }
                            if (viewModel.selectedPunchId != null) {
                              viewModel.selectPunch(null);
                              return KeyEventResult.handled;
                            }
                          }
                          final isShift =
                              HardwareKeyboard.instance.isShiftPressed;
                          final isCtrl =
                              HardwareKeyboard.instance.isControlPressed ||
                              HardwareKeyboard.instance.isMetaPressed;
                          final step = isShift ? 0.1 : 1.0;
                          if (event.logicalKey == LogicalKeyboardKey.delete ||
                              event.logicalKey ==
                                  LogicalKeyboardKey.backspace) {
                            if (viewModel.selectedConstraintId != null) {
                              viewModel.removeConstraint(
                                viewModel.selectedConstraintId!,
                              );
                              return KeyEventResult.handled;
                            }
                            if (viewModel.selectedDimensionId != null) {
                              viewModel.removeDimension(
                                viewModel.selectedDimensionId!,
                              );
                              return KeyEventResult.handled;
                            }
                            viewModel.deleteSelectedEntities();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            viewModel.nudgeSelectedBend(0, step);
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.arrowDown) {
                            viewModel.nudgeSelectedBend(0, -step);
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.arrowLeft) {
                            viewModel.nudgeSelectedBend(-step, 0);
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.arrowRight) {
                            viewModel.nudgeSelectedBend(step, 0);
                            return KeyEventResult.handled;
                          }

                          // Toggle CAD Properties Inspector (Ctrl+1 / Ctrl+I / F4)
                          if ((isCtrl &&
                                  (event.logicalKey ==
                                          LogicalKeyboardKey.digit1 ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.keyI)) ||
                              event.logicalKey == LogicalKeyboardKey.f4) {
                            viewModel.togglePropertyInspector();
                            return KeyEventResult.handled;
                          }

                          // Direct CAD tool shortcuts when canvas is focused (KeyDown only, no Ctrl/Meta)
                          if (!isCtrl &&
                              _activeEditingPortId == null &&
                              !_isEditingText()) {
                            if (event.logicalKey == LogicalKeyboardKey.keyB) {
                              viewModel.setToolMode(StudioToolMode.addBend);
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyF) {
                              viewModel.setToolMode(
                                isShift
                                    ? StudioToolMode.cornerFillet
                                    : StudioToolMode.addFlange,
                              );
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyM) {
                              viewModel.setToolMode(StudioToolMode.addCut);
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyL) {
                              viewModel.setToolMode(
                                StudioToolMode.drawPolyline,
                              );
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyG) {
                              viewModel.setToolMode(
                                StudioToolMode.drawRectangle,
                              );
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyC) {
                              viewModel.setToolMode(
                                isShift
                                    ? StudioToolMode.cornerChamfer
                                    : StudioToolMode.drawCircle,
                              );
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                    LogicalKeyboardKey.keyA &&
                                !isShift) {
                              viewModel.setToolMode(StudioToolMode.drawArc);
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyQ) {
                              viewModel.toggleSelectedConstruction();
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyD) {
                              viewModel.setToolMode(
                                StudioToolMode.addDimension,
                              );
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyP) {
                              viewModel.setToolMode(
                                StudioToolMode.perforationPattern,
                              );
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                    LogicalKeyboardKey.keyV ||
                                event.logicalKey == LogicalKeyboardKey.space) {
                              viewModel.setToolMode(StudioToolMode.select);
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.keyH) {
                              viewModel.setToolMode(StudioToolMode.pan);
                              return KeyEventResult.handled;
                            }
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Listener(
                        onPointerDown: (event) {
                          if (!_canvasFocusNode.hasFocus &&
                              !_inPlaceDimFocusNode.hasFocus) {
                            _canvasFocusNode.requestFocus();
                          }
                        },
                        onPointerSignal: (pointerSignal) {
                          if (pointerSignal is PointerScrollEvent) {
                            final zoomFactor = pointerSignal.scrollDelta.dy < 0
                                ? 1.12
                                : 0.89;
                            viewModel.zoom2DCanvas(
                              zoomFactor,
                              focalPoint: pointerSignal.localPosition,
                              viewportSize: size,
                            );
                          }
                        },
                        onPointerPanZoomUpdate: (event) {
                          if (event.pan != Offset.zero) {
                            viewModel.pan2DCanvas(event.pan);
                          }
                          if (event.scale != 1.0) {
                            viewModel.zoom2DCanvas(
                              event.scale,
                              focalPoint: event.localPosition,
                              viewportSize: size,
                            );
                          }
                        },
                        onPointerMove: (event) {
                          if ((event.buttons & kPrimaryMouseButton) == 0 &&
                              _boxSelectStart != null) {
                            _boxSelectStart = null;
                            _boxSelectCurrent = null;
                            _activeDrag = _DragTarget.none;
                            setState(() {});
                          }
                          final isMiddleMouse =
                              (event.buttons & kTertiaryButton) != 0;
                          final isSecondaryMouse =
                              (event.buttons & kSecondaryMouseButton) != 0;
                          bool isSpaceHeld = false;
                          try {
                            isSpaceHeld = HardwareKeyboard.instance
                                .isLogicalKeyPressed(LogicalKeyboardKey.space);
                          } catch (_) {}

                          if (isMiddleMouse ||
                              isSecondaryMouse ||
                              (isSpaceHeld &&
                                  (event.buttons & kPrimaryMouseButton) != 0)) {
                            viewModel.pan2DCanvas(event.delta);
                          }
                        },
                        onPointerUp: (event) {
                          if (_boxSelectStart != null) {
                            _boxSelectStart = null;
                            _boxSelectCurrent = null;
                            _activeDrag = _DragTarget.none;
                            setState(() {});
                          }
                        },
                        onPointerCancel: (event) {
                          if (_boxSelectStart != null) {
                            _boxSelectStart = null;
                            _boxSelectCurrent = null;
                            _activeDrag = _DragTarget.none;
                            setState(() {});
                          }
                        },
                        child: MouseRegion(
                          cursor: _activeDrag == _DragTarget.canvasPan
                              ? SystemMouseCursors.grabbing
                              : (_activeDrag == _DragTarget.boxSelect ||
                                        _activeDrag == _DragTarget.drawEntity
                                    ? SystemMouseCursors.precise
                                    : (_activeDrag ==
                                              _DragTarget.dimensionBadge ||
                                          _hoveredDimId != null ||
                                          _activeDrag ==
                                              _DragTarget.dimensionLine ||
                                          _hoveredDimLineId != null ||
                                          _activeDrag ==
                                              _DragTarget.portBadge ||
                                          _hoveredPortBadgeId != null ||
                                          _activeDrag == _DragTarget.cover)
                                    ? SystemMouseCursors.move
                                    : ((viewModel.toolMode ==
                                                  StudioToolMode.pickPortEdge ||
                                              viewModel.activePortPickTarget !=
                                                  null)
                                          ? SystemMouseCursors.precise
                                          : (viewModel.toolMode ==
                                                    StudioToolMode.pan
                                                ? SystemMouseCursors.grab
                                                : ((viewModel.toolMode !=
                                                              StudioToolMode
                                                                  .select &&
                                                          viewModel.toolMode !=
                                                              StudioToolMode
                                                                  .pan &&
                                                          viewModel.toolMode !=
                                                              StudioToolMode
                                                                  .setBaseAnchor)
                                                      ? SystemMouseCursors
                                                            .precise
                                                      : (_hoveredEndpoint !=
                                                                null
                                                            ? SystemMouseCursors
                                                                  .precise
                                                            : SystemMouseCursors
                                                                  .basic))))),
                          onHover: (event) {
                            if (_activeDrag != _DragTarget.none) return;
                            final cadPt = screenToCad(event.localPosition);
                            _hoverCursorScreen = event.localPosition;
                            _hoverCursorCad = cadPt;
                            final screenSnapMm = (8.0 / scale).clamp(1.5, 8.0);
                            final isAlt = _isAltPressed();
                            viewModel.updateCursorMm(
                              cadPt,
                              snapRadiusMm: screenSnapMm,
                              isAlt: isAlt,
                            );

                            // Check hover on movable dimension line segments
                            String? hoveredDimLine;
                            for (final entry
                                in _dimensionLineSegments.entries) {
                              if (_distToScreenSegment(
                                    event.localPosition,
                                    entry.value.pA,
                                    entry.value.pB,
                                  ) <=
                                  8.0) {
                                hoveredDimLine = entry.key;
                                break;
                              }
                            }
                            if (hoveredDimLine != _hoveredDimLineId) {
                              setState(() {
                                _hoveredDimLineId = hoveredDimLine;
                              });
                            }

                            // Check hover on movable dimension badges
                            String? hoveredDim;
                            for (final entry in _dimensionBadgeRects.entries) {
                              if (entry.value
                                  .inflate(4.0)
                                  .contains(event.localPosition)) {
                                hoveredDim = entry.key;
                                break;
                              }
                            }
                            if (hoveredDim != _hoveredDimId) {
                              setState(() {
                                _hoveredDimId = hoveredDim;
                              });
                            }

                            // Check hover on interactive constraint badges
                            String? hoveredConstraint;
                            for (final entry in _constraintBadgeRects.entries) {
                              if (entry.value
                                  .inflate(4.0)
                                  .contains(event.localPosition)) {
                                hoveredConstraint = entry.key;
                                break;
                              }
                            }
                            if (hoveredConstraint != _hoveredConstraintId) {
                              final highlightedRefs = <String>{};
                              if (hoveredConstraint != null) {
                                final c = viewModel.activeConstraintDefinitions
                                    .where((def) => def.id == hoveredConstraint)
                                    .firstOrNull;
                                if (c != null) {
                                  for (final ref in c.references) {
                                    highlightedRefs.add(ref.canonicalPath);
                                    highlightedRefs.add(ref.entityId);
                                  }
                                }
                              }
                              setState(() {
                                _hoveredConstraintId = hoveredConstraint;
                                _constraintHoverHighlightedEntityIds.clear();
                                _constraintHoverHighlightedEntityIds.addAll(
                                  highlightedRefs,
                                );
                              });
                            }

                            // Check hover on movable port badges
                            String? hoveredPort;
                            for (final entry in _portBadgeRects.entries) {
                              if (entry.value
                                  .inflate(4.0)
                                  .contains(event.localPosition)) {
                                hoveredPort = entry.key;
                                break;
                              }
                            }
                            if (hoveredPort != _hoveredPortBadgeId) {
                              setState(() {
                                _hoveredPortBadgeId = hoveredPort;
                              });
                            }

                            // Dynamic contour edge hover for selection, dimensioning, and port edge picking
                            if (viewModel.toolMode == StudioToolMode.select ||
                                viewModel.toolMode ==
                                    StudioToolMode.addDimension ||
                                viewModel.toolMode ==
                                    StudioToolMode.pickPortEdge ||
                                viewModel.activePortPickTarget != null) {
                              final contour = viewModel.document.outerContour;
                              final candidateEdges =
                                  <(CadPoint2D, CadPoint2D)>[];
                              if (contour.length >= 2) {
                                for (int i = 0; i < contour.length; i++) {
                                  candidateEdges.add((
                                    contour[i],
                                    contour[(i + 1) % contour.length],
                                  ));
                                }
                              } else {
                                for (final f in viewModel.document.faces) {
                                  if (!f.isVisible) continue;
                                  for (int i = 0; i < f.vertices.length; i++) {
                                    candidateEdges.add((
                                      f.vertices[i],
                                      f.vertices[(i + 1) % f.vertices.length],
                                    ));
                                  }
                                }
                              }

                              CadPoint2D? bestP1;
                              CadPoint2D? bestP2;
                              double minD = double.infinity;
                              for (final edge in candidateEdges) {
                                // Check if edge is part of a CAD arc chord
                                bool isPartOfArc = false;
                                for (final a in viewModel.document.arcs) {
                                  if (a.distanceTo(edge.$1) <= 1.2 &&
                                      a.distanceTo(edge.$2) <= 1.2) {
                                    isPartOfArc = true;
                                    break;
                                  }
                                }
                                if (isPartOfArc) continue;

                                final d =
                                    _distToSegment(cadPt, edge.$1, edge.$2) *
                                    scale;
                                if (d < minD && d <= 28.0) {
                                  minD = d;
                                  bestP1 = edge.$1;
                                  bestP2 = edge.$2;
                                }
                              }
                              if (bestP1 != null && bestP2 != null) {
                                final len = bestP1.distanceTo(bestP2);
                                viewModel.updateHoveredContourEdge(
                                  bestP1,
                                  bestP2,
                                  len,
                                );
                              } else {
                                viewModel.updateHoveredContourEdge(
                                  null,
                                  null,
                                  null,
                                );
                              }
                            } else {
                              viewModel.updateHoveredContourEdge(
                                null,
                                null,
                                null,
                              );
                            }

                            // Check hover on punches
                            String? hoveredPunch;
                            for (final p in viewModel.document.punches) {
                              final rad =
                                  math.max(
                                    p.diameterMm,
                                    math.max(p.widthMm, p.lengthMm),
                                  ) /
                                  2.0;
                              if (p.center.distanceTo(cadPt) <=
                                  rad + 6.0 / scale) {
                                hoveredPunch = p.id;
                                break;
                              }
                            }
                            viewModel.setHoveredPunch(hoveredPunch);

                            // Check hover on bends
                            String? hoveredBend;
                            for (final b in viewModel.document.bends) {
                              if (_distToSegment(cadPt, b.p1, b.p2) * scale <=
                                  14.0) {
                                hoveredBend = b.id;
                                break;
                              }
                            }
                            viewModel.setHoveredBend(hoveredBend);

                            // Check hover on cuts
                            String? hoveredCut;
                            for (final c in viewModel.document.cutLines) {
                              if (_distToSegment(cadPt, c.p1, c.p2) * scale <=
                                  14.0) {
                                hoveredCut = c.id;
                                break;
                              }
                            }
                            viewModel.setHoveredCut(hoveredCut);

                            // Check hover on arcs
                            String? hoveredArc;
                            for (final a in viewModel.document.arcs) {
                              if (a.distanceTo(cadPt) * scale <= 14.0) {
                                hoveredArc = a.id;
                                break;
                              }
                            }
                            viewModel.setHoveredArc(hoveredArc);
                            if (hoveredArc != null) {
                              viewModel.updateHoveredContourEdge(
                                null,
                                null,
                                null,
                              );
                            }

                            // Check proximity to any bend or cut line endpoint
                            CadPoint2D? nearPt;
                            for (final b in viewModel.document.bends) {
                              if (cadPt.distanceTo(b.p1) * scale <= 18.0) {
                                nearPt = b.p1;
                                break;
                              }
                              if (cadPt.distanceTo(b.p2) * scale <= 18.0) {
                                nearPt = b.p2;
                                break;
                              }
                            }
                            if (nearPt == null) {
                              for (final c in viewModel.document.cutLines) {
                                if (cadPt.distanceTo(c.p1) * scale <= 18.0) {
                                  nearPt = c.p1;
                                  break;
                                }
                                if (cadPt.distanceTo(c.p2) * scale <= 18.0) {
                                  nearPt = c.p2;
                                  break;
                                }
                              }
                            }
                            if (nearPt != _hoveredEndpoint) {
                              setState(() {
                                _hoveredEndpoint = nearPt;
                              });
                            }
                          },
                          onExit: (_) {
                            viewModel.clearSnap();
                            viewModel.setHoveredPunch(null);
                            viewModel.setHoveredBend(null);
                            viewModel.setHoveredCut(null);
                            viewModel.setHoveredArc(null);
                            viewModel.setHoveredFace(null);
                            viewModel.updateHoveredContourEdge(
                              null,
                              null,
                              null,
                            );
                            if (_hoveredDimId != null ||
                                _hoveredDimLineId != null ||
                                _hoveredEndpoint != null ||
                                _hoveredPortBadgeId != null ||
                                _hoverCursorScreen != null ||
                                _hoverCursorCad != null) {
                              setState(() {
                                _hoveredDimId = null;
                                _hoveredDimLineId = null;
                                _hoveredPortBadgeId = null;
                                _hoveredEndpoint = null;
                                _hoverCursorScreen = null;
                                _hoverCursorCad = null;
                              });
                            }
                          },
                          child: MenuAnchor(
                            controller: _contextMenuController,
                            menuChildren: _buildEdgeContextMenuChildren(
                              viewModel,
                            ),
                            builder: (context, controller, child) => GestureDetector(
                              key: const ValueKey(
                                'unfolded_canvas_gesture_detector',
                              ),
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) => _handleCanvasPanStart(
                                details,
                                viewModel: viewModel,
                                screenToCad: screenToCad,
                                cadToScreen: cadToScreen,
                                scale: scale,
                                size: size,
                                selectedBend: selectedBend,
                                selectedCut: selectedCut,
                                selectedPunch: selectedPunch,
                              ),
                              onPanUpdate: (details) => _handleCanvasPanUpdate(
                                details,
                                viewModel: viewModel,
                                screenToCad: screenToCad,
                                cadToScreen: cadToScreen,
                                scale: scale,
                                size: size,
                                selectedBend: selectedBend,
                                selectedCut: selectedCut,
                                selectedPunch: selectedPunch,
                              ),
                              onPanEnd: (details) => _handleCanvasPanEnd(
                                details,
                                viewModel: viewModel,
                                screenToCad: screenToCad,
                                cadToScreen: cadToScreen,
                                scale: scale,
                              ),
                              onPanCancel: () => _handleCanvasPanCancel(
                                viewModel: viewModel,
                              ),
                              onSecondaryTapUp: (details) =>
                                  _handleCanvasSecondaryTapUp(
                                details,
                                viewModel: viewModel,
                                screenToCad: screenToCad,
                                scale: scale,
                              ),
                              onTapUp: (details) => _handleCanvasTapUp(
                                details,
                                context: context,
                                viewModel: viewModel,
                                screenToCad: screenToCad,
                                cadToScreen: cadToScreen,
                                scale: scale,
                                size: size,
                              ),
                              child: Builder(
                                builder: (context) {
                                  CadLineSegment? autoCandidateLine;
                                  if (viewModel.pendingBendStart == null &&
                                      (viewModel.toolMode ==
                                              StudioToolMode.addBend ||
                                          viewModel.toolMode ==
                                              StudioToolMode.addFlange) &&
                                      viewModel.rubberBandEndpoint != null) {
                                    autoCandidateLine = viewModel
                                        .computeAutoBendOrFlangeLine(
                                          viewModel.rubberBandEndpoint!,
                                          isFlange:
                                              viewModel.toolMode ==
                                              StudioToolMode.addFlange,
                                        );
                                  }

                                  return ExcludeSemantics(
                                    child: Stack(
                                      children: [
                                        CustomPaint(
                                          size: Size.infinite,
                                          painter: _UnfoldedBoardPainter(
                                            doc: viewModel.document,
                                            foldProgress:
                                                viewModel.foldProgress,
                                            foldedMesh: viewModel.currentMesh,
                                            pan: viewModel.pan2D,
                                            zoom: viewModel.zoom2D,
                                            toolMode: viewModel.toolMode,
                                            activeSnap: viewModel.activeSnap,
                                            pendingBendStart:
                                                viewModel.pendingBendStart,
                                            rubberBandEndpoint:
                                                viewModel.rubberBandEndpoint,
                                            pendingMultiPoints:
                                                viewModel.pendingMultiPoints,
                                            selectedBendId:
                                                viewModel.selectedBendId,
                                            selectedCutId:
                                                viewModel.selectedCutId,
                                            selectedFaceId:
                                                viewModel.selectedFaceId,
                                            selectedPunchId:
                                                viewModel.selectedPunchId,
                                            selectedPatternId:
                                                viewModel.selectedPatternId,
                                            selectedPatternHoleIndex: viewModel
                                                .selectedPatternHoleIndex,
                                            showDimensions:
                                                viewModel.canvasDisplaySettings.showDimensions,
                                            bendViolations:
                                                viewModel.bendViolations,
                                            hoveredPunchId:
                                                viewModel.hoveredPunchId,
                                            hoveredBendId:
                                                viewModel.hoveredBendId,
                                            toolConfig: viewModel.toolConfig,
                                            isBendIncompleteFn:
                                                viewModel.isBendIncomplete,
                                            hoveredEndpoint: _hoveredEndpoint,
                                            dragAngleInfo: _dragAngleInfo,
                                            previewPerforationPattern: viewModel
                                                .previewPerforationPattern,
                                            previewCouplerPunches:
                                                viewModel.previewCouplerPunches,
                                            dimensionOffsets:
                                                viewModel.dimensionOffsets,
                                            dimensionLineOffsets:
                                                viewModel.dimensionLineOffsets,
                                            renderedDimensionBadges:
                                                _dimensionBadgeRects,
                                            renderedDimensionLines:
                                                _dimensionLineSegments,
                                            editingDimId: _editingDimId,
                                            selectedDimensionId:
                                                viewModel.selectedDimensionId,
                                            hoveredDimensionId: _hoveredDimId,
                                            renderedDimensionValues:
                                                _dimensionBadgeValues,
                                            hoveredDimLineId: _hoveredDimLineId,
                                            portBadgeOffsets:
                                                viewModel.portBadgeOffsets,
                                            renderedPortBadges: _portBadgeRects,
                                            hoveredContourEdgeP1:
                                                viewModel.hoveredContourEdgeP1,
                                            hoveredContourEdgeP2:
                                                viewModel.hoveredContourEdgeP2,
                                            hoveredContourEdgeLengthMm:
                                                viewModel
                                                    .hoveredContourEdgeLengthMm,
                                            selectedEntityIds:
                                                viewModel.selectedEntityIds,
                                            boxSelectStart: _boxSelectStart,
                                            boxSelectCurrent: _boxSelectCurrent,
                                            autoCandidateLine:
                                                autoCandidateLine,
                                            showOpeningTags:
                                                viewModel.canvasDisplaySettings.showOpeningTags,
                                            fittingMetadata:
                                                viewModel
                                                    .detectedFittingMetadata ??
                                                DxfFittingMetadata.fromDocument(
                                                  viewModel.document,
                                                ),
                                            referenceGeometries: viewModel
                                                .activeReferenceGeometries,
                                            constraintDefinitions: viewModel
                                                .activeConstraintDefinitions,
                                            selectedConstraintId:
                                                viewModel.selectedConstraintId,
                                            hoveredConstraintId:
                                                _hoveredConstraintId,
                                            renderedConstraintBadges:
                                                _constraintBadgeRects,
                                            constraintHoverHighlightedEntityIds:
                                                _constraintHoverHighlightedEntityIds,
                                            showDofDiagnostics:
                                                viewModel.canvasDisplaySettings.showDofDiagnostics,
                                            dofStateProvider: viewModel
                                                .getEntityConstraintState,
                                            showConstructionGeometry:
                                                viewModel.canvasDisplaySettings.showConstructionGeometry,
                                            showConstraints:
                                                viewModel.canvasDisplaySettings.showConstraints,
                                            showProfileFill:
                                                viewModel.canvasDisplaySettings.showProfileFill,
                                            showPoints:
                                                viewModel.canvasDisplaySettings.showSnapPoints,
                                            showGrid:
                                                viewModel.canvasDisplaySettings.showGrid,
                                            selectedArcId:
                                                viewModel.selectedArcId,
                                            hoveredArcId:
                                                viewModel.hoveredArcId,
                                            activePortInferenceResult: viewModel
                                                .activePortInferenceResult,
                                            hoverCursorCad: _hoverCursorCad,
                                            isAltPressed: _isAltPressed(),
                                            canvasSettings:
                                                viewModel.canvasDisplaySettings,
                                          ),
                                        ),
                                        AnimatedBuilder(
                                          animation: Listenable.merge([
                                            viewModel,
                                            viewModel.cmsGuidedController,
                                          ]),
                                          builder: (context, _) {
                                            final ctrl =
                                                viewModel.cmsGuidedController;
                                            final ports =
                                                viewModel.activeCmsPorts;
                                            final suggestedBends =
                                                ctrl.state.suggestedBends;
                                            final showBends =
                                                ctrl.phase ==
                                                    CmsUxPhase
                                                        .suggestingBends ||
                                                ctrl.phase ==
                                                    CmsUxPhase.confirmingBends;
                                            if (ports.isEmpty &&
                                                (!showBends ||
                                                    suggestedBends.isEmpty)) {
                                              return const SizedBox.shrink();
                                            }
                                            return CustomPaint(
                                              size: Size.infinite,
                                              painter: Cms2DOverlayPainter(
                                                ports: ports,
                                                suggestedBends: showBends
                                                    ? suggestedBends
                                                    : const [],
                                                focus: ctrl.state.focus,
                                                worldToScreen: (x, y) =>
                                                    cadToScreen(
                                                      CadPoint2D(x, y),
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Floating Contextual Quick Constraints Bar (Component 3)
                    if (viewModel.toolMode == StudioToolMode.select &&
                        (viewModel.selectedEntityIds.isNotEmpty ||
                            viewModel.selectedCutId != null ||
                            viewModel.selectedBendId != null ||
                            viewModel.selectedPunchId != null))
                      Positioned(
                        top: 14,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FloatingSketchConstraintBar(
                            viewModel: viewModel,
                            onApplyConstraint: (type) {
                              viewModel.applyConstraint(type);
                            },
                            onStartDimension: () {
                              viewModel.setToolMode(
                                StudioToolMode.addDimension,
                              );
                            },
                            onDismiss: () {
                              viewModel.clearSelection();
                            },
                          ),
                        ),
                      ),

                    ..._buildOverlayStack(
                      context: context,
                      viewModel: viewModel,
                      constraints: constraints,
                      size: size,
                      scale: scale,
                      screenToCad: screenToCad,
                      cadToScreen: cadToScreen,
                      effectiveInspectorPos: effectiveInspectorPos,
                      selectedBend: selectedBend,
                      selectedCut: selectedCut,
                      selectedPunch: selectedPunch,
                      selectedPattern: selectedPattern,
                      selectedFace: selectedFace,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
