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
import 'dimension_drive_dialog.dart';
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

class _UnfoldedCanvasWidgetState extends State<UnfoldedCanvasWidget> {
  // Draggable inspector panel offset (null defaults to top-right)
  Offset? _inspectorOffset;
  _DragTarget _activeDrag = _DragTarget.none;
  Offset? _boxSelectStart;
  Offset? _boxSelectCurrent;
  String? _draggedBendId;
  String? _draggedCutId;
  String? _draggedDimId;
  Offset _dragDimensionStartOffset = Offset.zero;
  Offset _dragStartScreen = Offset.zero;
  final Map<String, Rect> _dimensionBadgeRects = {};
  String? _hoveredDimId;
  final Map<String, ({Offset pA, Offset pB, double offsetDist, CadPoint2D ptA, CadPoint2D ptB, CadDimensionType type})> _dimensionLineSegments = {};
  String? _hoveredDimLineId;
  String? _draggedDimLineId;
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  final Map<String, Rect> _portBadgeRects = {};
  String? _draggedPortBadgeId;
  Offset _dragPortBadgeStartOffset = Offset.zero;
  String? _hoveredPortBadgeId;
  bool _hasMovedPortBadge = false;

  // Port-Driven Direct Canvas Editing (Set 4A)
  String? _activeEditingPortId;
  double _portEditWidth = 300.0;
  double _portEditHeightA = 50.0;
  double _portEditHeightB = 50.0;
  bool _portHeightsLinked = true;
  Map<String, double> _portEditBaselineParams = {};
  Offset? _portEditorScreenPos;

  // Interactive Canvas Constraint Glyphs (Component 2)
  final Map<String, Rect> _constraintBadgeRects = {};
  String? _hoveredConstraintId;
  final Set<String> _constraintHoverHighlightedEntityIds = {};

  // Inline Floating Dimension Callout Editor (Component 1)
  String? _activeInlineDimId;
  CadPoint2D? _activeInlineDimPA;
  CadPoint2D? _activeInlineDimPB;
  String? _activeInlineDimRefA;
  String? _activeInlineDimRefB;
  double _activeInlineDimOffset = 25.0;
  Offset? _inlineDimEditorScreenPos;
  final TextEditingController _inlineDimTextController = TextEditingController();
  final FocusNode _inlineDimFocusNode = FocusNode();
  final FocusNode _canvasFocusNode = FocusNode();

  bool _isEditingText() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final ctx = focus.context;
    if (ctx == null || !ctx.mounted) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  void dispose() {
    _inlineDimTextController.dispose();
    _inlineDimFocusNode.dispose();
    _canvasFocusNode.dispose();
    super.dispose();
  }

  void _openInlineDimensionCallout({
    required Offset screenPos,
    String? dimId,
    CadPoint2D? pA,
    CadPoint2D? pB,
    String? referenceAId,
    String? referenceBId,
    required double measuredValue,
    double offset = 25.0,
  }) {
    setState(() {
      _activeInlineDimId = dimId;
      _activeInlineDimPA = pA;
      _activeInlineDimPB = pB;
      _activeInlineDimRefA = referenceAId;
      _activeInlineDimRefB = referenceBId;
      _activeInlineDimOffset = offset;
      _inlineDimEditorScreenPos = screenPos;
      _inlineDimTextController.text = measuredValue.toStringAsFixed(2);
      _inlineDimTextController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inlineDimTextController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inlineDimFocusNode.requestFocus();
    });
  }

  Widget _buildInlineDimensionCallout(SheetMetalStudioViewModel viewModel) {
    if (_inlineDimEditorScreenPos == null) return const SizedBox.shrink();

    return Positioned(
      left: (_inlineDimEditorScreenPos!.dx - 85).clamp(10.0, 4000.0),
      top: (_inlineDimEditorScreenPos!.dy - 70).clamp(10.0, 4000.0),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(6),
        color: Colors.transparent,
        child: Container(
          width: 175,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.straighten, size: 12, color: Color(0xFF0284C7)),
                  const SizedBox(width: 4),
                  const Text(
                    'DIMENSION (mm)',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _inlineDimEditorScreenPos = null;
                      });
                    },
                    child: const Icon(Icons.close, size: 13, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: TextField(
                        controller: _inlineDimTextController,
                        focusNode: _inlineDimFocusNode,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                          ),
                        ),
                        onSubmitted: (val) {
                          final parsed = double.tryParse(val.trim());
                          if (parsed != null && parsed > 0) {
                            if (_activeInlineDimId != null) {
                              viewModel.driveDimension(_activeInlineDimId!, parsed);
                            } else if (_activeInlineDimPA != null && _activeInlineDimPB != null) {
                              viewModel.commitInteractiveDimension(
                                pA: _activeInlineDimPA!,
                                pB: _activeInlineDimPB!,
                                referenceAId: _activeInlineDimRefA,
                                referenceBId: _activeInlineDimRefB,
                                offset: _activeInlineDimOffset,
                                customValue: parsed,
                              );
                            }
                          }
                          setState(() {
                            _inlineDimEditorScreenPos = null;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      final val = _inlineDimTextController.text.trim();
                      final parsed = double.tryParse(val);
                      if (parsed != null && parsed > 0) {
                        if (_activeInlineDimId != null) {
                          viewModel.driveDimension(_activeInlineDimId!, parsed);
                        } else if (_activeInlineDimPA != null && _activeInlineDimPB != null) {
                          viewModel.commitInteractiveDimension(
                            pA: _activeInlineDimPA!,
                            pB: _activeInlineDimPB!,
                            referenceAId: _activeInlineDimRefA,
                            referenceBId: _activeInlineDimRefB,
                            offset: _activeInlineDimOffset,
                            customValue: parsed,
                          );
                        }
                      }
                      setState(() {
                        _inlineDimEditorScreenPos = null;
                      });
                    },
                    child: Container(
                      height: 28,
                      width: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.check, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'Enter ↵ to drive geometry',
                style: TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isInspectorCollapsed = false;
  Offset? _dragStartGlobal;
  Offset? _dragStartPanel;
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

  bool _isAltPressed() {
    try {
      if (HardwareKeyboard.instance.isAltPressed) return true;
    } catch (_) {}
    try {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.altLeft) ||
          HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.altRight)) {
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
      if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
          HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight)) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  // Multilevel Context Menu for Right-Click Edge Port Assignment
  final MenuController _contextMenuController = MenuController();
  CadPoint2D? _contextMenuP1;
  CadPoint2D? _contextMenuP2;
  double? _contextMenuLenMm;
  bool _isLegendCollapsed = false;
  bool _showProfileFill = true;
  bool _showPoints = true;
  bool _showGrid = true;

  static double _distToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
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

  static double _distToScreenSegment(Offset p, Offset a, Offset b) {
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

  static bool _isPointInPoly(CadPoint2D pt, List<CadPoint2D> poly) {
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

    // 1. If double-tapping a dimension badge, open Direct Dimension Driving Dialog!
    for (final entry in _dimensionBadgeRects.entries) {
      if (entry.value.inflate(6.0).contains(touchScreen)) {
        // Find explicit CadDimension
        final cadDim = viewModel.document.dimensions
            .where((d) => d.id == entry.key)
            .firstOrNull;
        if (cadDim != null) {
          _openInlineDimensionCallout(
            screenPos: entry.value.center,
            dimId: cadDim.id,
            pA: cadDim.pointA,
            pB: cadDim.pointB,
            referenceAId: cadDim.referenceAId,
            referenceBId: cadDim.referenceBId,
            measuredValue: cadDim.measuredValue,
            offset: cadDim.dimensionLineOffset,
          );
          return;
        }
        // Check implicit blank dimensions
        if (entry.key == 'dim_blank_w') {
          final dim = CadDimension(
            id: 'dim_blank_w',
            type: CadDimensionType.horizontal,
            measuredValue: viewModel.document.blankWidthMm,
            prefix: 'BLANK W',
          );
          DimensionDriveDialog.show(context, viewModel: viewModel, dimension: dim);
          return;
        }
        if (entry.key == 'dim_blank_l') {
          final dim = CadDimension(
            id: 'dim_blank_l',
            type: CadDimensionType.vertical,
            measuredValue: viewModel.document.blankLengthMm,
            prefix: 'BLANK L',
          );
          DimensionDriveDialog.show(context, viewModel: viewModel, dimension: dim);
          return;
        }
        // Fallback: reset offset
        viewModel.resetDimensionOffset(entry.key);
        return;
      }
    }

    final cadPt = screenToCad(touchScreen);
    // 2. If double tapping on an applied perforation pattern, select it and open inspector
    for (final pat in viewModel.document.perforationPatterns) {
      if (!pat.isVisible) continue;
      final holeIdx = pat.findHoleAt(
        cadPt,
        maxDistMm: 16.0 / scale,
      );
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

  Widget _buildFloatingInspector({
    required SheetMetalStudioViewModel viewModel,
    required Offset effectiveInspectorPos,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        _dragStartGlobal = details.globalPosition;
        _dragStartPanel = effectiveInspectorPos;
      },
      onPanUpdate: (details) {
        if (_dragStartGlobal != null && _dragStartPanel != null) {
          setState(() {
            _inspectorOffset = _dragStartPanel! +
                (details.globalPosition - _dragStartGlobal!);
          });
        }
      },
      child: CadPropertyInspector(
        viewModel: viewModel,
        isCollapsed: _isInspectorCollapsed,
        onToggleCollapse: () {
          setState(() {
            _isInspectorCollapsed = !_isInspectorCollapsed;
          });
        },
        onClose: () {
          widget.viewModel.setPropertyInspectorOpen(false);
        },
        onDragStartHeader: (details) {
          _dragStartGlobal = details.globalPosition;
          _dragStartPanel = effectiveInspectorPos;
        },
        onDragHeader: (details) {
          if (_dragStartGlobal != null && _dragStartPanel != null) {
            setState(() {
              _inspectorOffset = _dragStartPanel! +
                  (details.globalPosition - _dragStartGlobal!);
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;

    final currentEntity = viewModel.selectedBendId ??
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

        final fitScale = math.min(
          (size.width * 0.75) / bw,
          (size.height * 0.75) / bl,
        );
        final scale = fitScale * viewModel.zoom2D;

        final cx = size.width / 2.0 + viewModel.pan2D.dx;
        final cy = size.height / 2.0 + viewModel.pan2D.dy;

        final originX = cx - (bw / 2.0) * scale;
        final originY = cy - (bl / 2.0) * scale;

        CadPoint2D screenToCad(Offset screenPos) {
          final x = (screenPos.dx - originX) / scale;
          final y = (screenPos.dy - originY) / scale;
          return CadPoint2D(x, y);
        }

        Offset cadToScreen(CadPoint2D pt) {
          return Offset(
            originX + pt.x * scale,
            originY + pt.y * scale,
          );
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
            selectedPattern = viewModel.document.perforationPatterns.firstWhere(
              (p) => p.id == viewModel.selectedPatternId,
            );
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

        CadDimension? selectedDimension;
        if (viewModel.selectedDimensionId != null) {
          try {
            selectedDimension = viewModel.document.dimensions.firstWhere(
              (d) => d.id == viewModel.selectedDimensionId,
            );
          } catch (_) {}
        }

        CadArc2D? selectedArc;
        if (viewModel.selectedArcId != null) {
          try {
            selectedArc = viewModel.document.arcs.firstWhere(
              (a) => a.id == viewModel.selectedArcId,
            );
          } catch (_) {}
        }

        final isToolActive =
            viewModel.toolMode != StudioToolMode.select &&
            viewModel.toolMode != StudioToolMode.pan;

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
                        if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                          _applyPortDimensionEditor();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.escape) {
                          _cancelPortDimensionEditor();
                          return KeyEventResult.handled;
                        }
                      }
                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        if (viewModel.selectedPunchId != null) {
                          viewModel.selectPunch(null);
                          return KeyEventResult.handled;
                        }
                      }
                      final isShift = HardwareKeyboard.instance.isShiftPressed;
                      final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
                      final step = isShift ? 0.1 : 1.0;
                      if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
                        viewModel.deleteSelectedEntities();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        viewModel.nudgeSelectedBend(0, step);
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        viewModel.nudgeSelectedBend(0, -step);
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        viewModel.nudgeSelectedBend(-step, 0);
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        viewModel.nudgeSelectedBend(step, 0);
                        return KeyEventResult.handled;
                      }

                      // Direct CAD tool shortcuts when canvas is focused (KeyDown only, no Ctrl/Meta)
                      if (!isCtrl && _activeEditingPortId == null && !_isEditingText()) {
                        if (event.logicalKey == LogicalKeyboardKey.keyB) {
                          viewModel.setToolMode(StudioToolMode.addBend);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
                          viewModel.setToolMode(isShift ? StudioToolMode.cornerFillet : StudioToolMode.addFlange);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
                          viewModel.setToolMode(StudioToolMode.addCut);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyL) {
                          viewModel.setToolMode(StudioToolMode.drawPolyline);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyG) {
                          viewModel.setToolMode(StudioToolMode.drawRectangle);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
                          viewModel.setToolMode(isShift ? StudioToolMode.cornerChamfer : StudioToolMode.drawCircle);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyA && !isShift) {
                          viewModel.setToolMode(StudioToolMode.drawArc);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyQ) {
                          viewModel.toggleSelectedConstruction();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
                          viewModel.setToolMode(StudioToolMode.addDimension);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
                          viewModel.setToolMode(StudioToolMode.perforationPattern);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyV || event.logicalKey == LogicalKeyboardKey.space) {
                          viewModel.setToolMode(StudioToolMode.select);
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.keyH) {
                          viewModel.setToolMode(StudioToolMode.pan);
                          return KeyEventResult.handled;
                        }
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Listener(
                  onPointerDown: (event) {
                    if (!_canvasFocusNode.hasFocus && !_inlineDimFocusNode.hasFocus) {
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
                  child: MouseRegion(
                    cursor: _activeDrag == _DragTarget.canvasPan
                        ? SystemMouseCursors.grabbing
                        : (_activeDrag == _DragTarget.boxSelect || _activeDrag == _DragTarget.drawEntity
                            ? SystemMouseCursors.precise
                            : (_activeDrag == _DragTarget.dimensionBadge ||
                                    _hoveredDimId != null ||
                                    _activeDrag == _DragTarget.dimensionLine ||
                                    _hoveredDimLineId != null ||
                                    _activeDrag == _DragTarget.portBadge ||
                                    _hoveredPortBadgeId != null)
                                ? SystemMouseCursors.move
                                : ((viewModel.toolMode == StudioToolMode.pickPortEdge ||
                                          viewModel.activePortPickTarget != null)
                                      ? SystemMouseCursors.precise
                                      : (viewModel.toolMode == StudioToolMode.pan
                                          ? SystemMouseCursors.grab
                                          : ((viewModel.toolMode != StudioToolMode.select &&
                                                    viewModel.toolMode !=
                                                        StudioToolMode.pan &&
                                                    viewModel.toolMode !=
                                                        StudioToolMode.setBaseAnchor)
                                                ? SystemMouseCursors.precise
                                                : (_hoveredEndpoint != null
                                                    ? SystemMouseCursors.precise
                                                    : SystemMouseCursors.basic))))),
                    onHover: (event) {
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
                      for (final entry in _dimensionLineSegments.entries) {
                        if (_distToScreenSegment(event.localPosition, entry.value.pA, entry.value.pB) <= 8.0) {
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
                        if (entry.value.inflate(4.0).contains(event.localPosition)) {
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
                        if (entry.value.inflate(4.0).contains(event.localPosition)) {
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
                          _constraintHoverHighlightedEntityIds.addAll(highlightedRefs);
                        });
                      }

                      // Check hover on movable port badges
                      String? hoveredPort;
                      for (final entry in _portBadgeRects.entries) {
                        if (entry.value.inflate(4.0).contains(event.localPosition)) {
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
                          viewModel.toolMode == StudioToolMode.addDimension ||
                          viewModel.toolMode == StudioToolMode.pickPortEdge ||
                          viewModel.activePortPickTarget != null) {
                        final contour = viewModel.document.outerContour;
                        final candidateEdges = <(CadPoint2D, CadPoint2D)>[];
                        if (contour.length >= 2) {
                          for (int i = 0; i < contour.length; i++) {
                            candidateEdges.add((contour[i], contour[(i + 1) % contour.length]));
                          }
                        } else {
                          for (final f in viewModel.document.faces) {
                            if (!f.isVisible) continue;
                            for (int i = 0; i < f.vertices.length; i++) {
                              candidateEdges.add((f.vertices[i], f.vertices[(i + 1) % f.vertices.length]));
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
                            if (a.distanceTo(edge.$1) <= 1.2 && a.distanceTo(edge.$2) <= 1.2) {
                              isPartOfArc = true;
                              break;
                            }
                          }
                          if (isPartOfArc) continue;

                          final d = _distToSegment(cadPt, edge.$1, edge.$2) * scale;
                          if (d < minD && d <= 28.0) {
                            minD = d;
                            bestP1 = edge.$1;
                            bestP2 = edge.$2;
                          }
                        }
                        if (bestP1 != null && bestP2 != null) {
                          final len = bestP1.distanceTo(bestP2);
                          viewModel.updateHoveredContourEdge(bestP1, bestP2, len);
                        } else {
                          viewModel.updateHoveredContourEdge(null, null, null);
                        }
                      } else {
                        viewModel.updateHoveredContourEdge(null, null, null);
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
                        if (p.center.distanceTo(cadPt) <= rad + 6.0 / scale) {
                          hoveredPunch = p.id;
                          break;
                        }
                      }
                      viewModel.setHoveredPunch(hoveredPunch);

                      // Check hover on bends
                      String? hoveredBend;
                      for (final b in viewModel.document.bends) {
                        if (_distToSegment(cadPt, b.p1, b.p2) * scale <= 14.0) {
                          hoveredBend = b.id;
                          break;
                        }
                      }
                      viewModel.setHoveredBend(hoveredBend);

                      // Check hover on cuts
                      String? hoveredCut;
                      for (final c in viewModel.document.cutLines) {
                        if (_distToSegment(cadPt, c.p1, c.p2) * scale <= 14.0) {
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
                        viewModel.updateHoveredContourEdge(null, null, null);
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
                      viewModel.updateHoveredContourEdge(null, null, null);
                      if (_hoveredDimId != null || _hoveredDimLineId != null || _hoveredEndpoint != null || _hoveredPortBadgeId != null || _hoverCursorScreen != null || _hoverCursorCad != null) {
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
                      menuChildren: _buildEdgeContextMenuChildren(viewModel),
                      builder: (context, controller, child) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        _shiftSelectionHandledInPan = false;
                        final isShiftHeld = _isShiftPressed();
                        bool isSpaceHeld = false;
                        try {
                          isSpaceHeld = HardwareKeyboard.instance
                              .isLogicalKeyPressed(LogicalKeyboardKey.space);
                        } catch (_) {}

                        if (isSpaceHeld ||
                            viewModel.toolMode == StudioToolMode.pan) {
                          _activeDrag = _DragTarget.canvasPan;
                          return;
                        }

                        final touchScreen = details.localPosition;
                        final cadPt = screenToCad(touchScreen);
                        _draggedBendId = null;
                        _draggedCutId = null;
                        _draggedDimId = null;
                        _draggedDimLineId = null;

                        bool found = false;

                        // 0a. Direct hit-test on ANY movable port badge
                        for (final entry in _portBadgeRects.entries) {
                          if (entry.value.inflate(4.0).contains(touchScreen)) {
                            _activeDrag = _DragTarget.portBadge;
                            _draggedPortBadgeId = entry.key;
                            _hasMovedPortBadge = false;
                            _dragStartScreen = touchScreen;
                            _dragPortBadgeStartOffset =
                                viewModel.portBadgeOffsets[entry.key] ?? Offset.zero;
                            found = true;
                            break;
                          }
                        }

                        // 0b. Direct hit-test on ANY movable dimension badge
                        if (!found) {
                          for (final entry in _dimensionBadgeRects.entries) {
                            if (entry.value.inflate(4.0).contains(touchScreen)) {
                              _activeDrag = _DragTarget.dimensionBadge;
                              _draggedDimId = entry.key;
                              _dragStartScreen = touchScreen;
                              _dragDimensionStartOffset =
                                  viewModel.dimensionOffsets[entry.key] ?? Offset.zero;
                              if (viewModel.document.dimensions.any((d) => d.id == entry.key)) {
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
                          for (final entry in _dimensionLineSegments.entries) {
                            if (_distToScreenSegment(touchScreen, entry.value.pA, entry.value.pB) <= 8.0) {
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
                          for (final entry in _constraintBadgeRects.entries) {
                            if (entry.value.inflate(4.0).contains(touchScreen)) {
                              final badge = entry.value;
                              final isDeleteRegion = touchScreen.dx > (badge.right - 18);
                              if (isDeleteRegion && (viewModel.selectedConstraintId == entry.key || _hoveredConstraintId == entry.key)) {
                                viewModel.removeConstraint(entry.key);
                                setState(() {
                                  _hoveredConstraintId = null;
                                  _constraintHoverHighlightedEntityIds.clear();
                                });
                              } else {
                                viewModel.selectConstraint(entry.key);
                              }
                              found = true;
                              break;
                            }
                          }
                        }

                        final isDrawingTool = viewModel.toolMode == StudioToolMode.addBend ||
                            viewModel.toolMode == StudioToolMode.addFlange ||
                            viewModel.toolMode == StudioToolMode.addCut ||
                            viewModel.toolMode == StudioToolMode.drawRectangle ||
                            viewModel.toolMode == StudioToolMode.drawCircle ||
                            viewModel.toolMode == StudioToolMode.drawArc ||
                            viewModel.toolMode == StudioToolMode.drawPolyline ||
                            viewModel.toolMode == StudioToolMode.addPunchRound ||
                            viewModel.toolMode == StudioToolMode.addPunchObround ||
                            viewModel.toolMode == StudioToolMode.addPunchSquare ||
                            viewModel.toolMode == StudioToolMode.dragDimension;

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
                            } else if ((touchScreen - s2).distance <= 20.0) {
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
                          for (final c in viewModel.document.cutLines) {
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
                            } else if ((touchScreen - s2).distance <= 20.0) {
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
                            final d = _distToSegment(cadPt, b.p1, b.p2) * scale;
                            if (d <= 14.0) {
                              if (isShiftHeld) {
                                viewModel.toggleEntitySelection(b.id);
                                _shiftSelectionHandledInPan = true;
                                found = true;
                                _activeDrag = _DragTarget.none;
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
                          for (final c in viewModel.document.cutLines) {
                            if (!c.isVisible) continue;
                            final d = _distToSegment(cadPt, c.p1, c.p2) * scale;
                            if (d <= 14.0) {
                              if (isShiftHeld) {
                                viewModel.toggleEntitySelection(c.id);
                                _shiftSelectionHandledInPan = true;
                                found = true;
                                _activeDrag = _DragTarget.none;
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
                              viewModel.setPropertyInspectorOpen(true);
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
                          for (final p in viewModel.document.punches) {
                            if (!p.isVisible) continue;
                            final dist = cadPt.distanceTo(p.center);
                            final effRadius = p.isRound
                                ? p.diameterMm / 2.0
                                : math.max(p.widthMm, p.lengthMm) / 2.0;
                            final hitR = math.max(14.0 / scale, effRadius + 3.0);
                            if (dist <= hitR) {
                              hitPunches.add(p);
                            }
                          }

                          if (hitPunches.isNotEmpty) {
                            if (isShiftHeld) {
                              hitPunches.sort((a, b) => cadPt.distanceTo(a.center).compareTo(cadPt.distanceTo(b.center)));
                              final targetPunch = hitPunches.first;
                              viewModel.toggleEntitySelection(targetPunch.id);
                              _shiftSelectionHandledInPan = true;
                              _activeDrag = _DragTarget.none;
                              found = true;
                            } else {
                              final currIdx = hitPunches.indexWhere(
                                (p) => p.id == viewModel.selectedPunchId,
                              );
                              final nextPunch =
                                  hitPunches[(currIdx + 1) % hitPunches.length];
                              viewModel.selectPunch(nextPunch.id);
                              _activeDrag = _DragTarget.punch;
                              found = true;
                            }
                          }
                        }

                        // 5b. Direct hit-test on ANY perforation pattern
                        if (!found) {
                          for (final pat
                              in viewModel.document.perforationPatterns) {
                            if (!pat.isVisible) continue;
                            final holeIdx = pat.findHoleAt(
                              cadPt,
                              maxDistMm: 16.0 / scale,
                            );
                            if (holeIdx != null || pat.containsPoint(cadPt)) {
                              if (isShiftHeld) {
                                viewModel.toggleEntitySelection(pat.id);
                                _shiftSelectionHandledInPan = true;
                                found = true;
                                _activeDrag = _DragTarget.none;
                                break;
                              }
                              viewModel.selectPattern(pat.id, holeIdx);
                              // Per user requirement: applied perforations must NOT be movable by mouse dragging!
                              found = true;
                              _activeDrag = _DragTarget.none;
                              break;
                            }
                          }
                        }
                        }

                        if (found) {
                          if (!isShiftHeld &&
                              _activeDrag != _DragTarget.none &&
                              _activeDrag != _DragTarget.dimensionBadge) {
                            viewModel.beginObjectDrag();
                          }
                        } else {
                          if (isDrawingTool) {
                            final screenSnapMm = (8.0 / scale).clamp(1.5, 8.0);
                            _drawStartAltPressed = _isAltPressed();

                            CadPoint2D effectiveStart;
                            if (_drawStartAltPressed) {
                              // Free mode for start point when Alt is held
                              effectiveStart = cadPt;
                            } else {
                              // Magnetic snap to nearest geometry/spanning point
                              viewModel.updateCursorMm(cadPt, snapRadiusMm: screenSnapMm);
                              effectiveStart = viewModel.activeSnap?.point ??
                                  viewModel.resolveEffectivePoint(cadPt, snapRadiusMm: screenSnapMm);
                            }

                            _activeDrag = _DragTarget.drawEntity;
                            _drawDragStartScreen = touchScreen;
                            _drawDragCurrentScreen = touchScreen;
                            _drawDragStartCad = effectiveStart;
                            _drawDragCommitted = false;

                            if (viewModel.pendingBendStart == null &&
                                viewModel.toolMode != StudioToolMode.drawArc &&
                                viewModel.toolMode != StudioToolMode.drawPolyline) {
                              viewModel.setPendingBendStart(effectiveStart);
                            }
                            setState(() {});
                          } else if (viewModel.toolMode == StudioToolMode.select) {
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
                      },
                      onPanUpdate: (details) {
                        if (_activeDrag == _DragTarget.boxSelect) {
                          setState(() {
                            _boxSelectCurrent = details.localPosition;
                          });
                          return;
                        }

                        final cadPt = screenToCad(details.localPosition);

                        if (_activeDrag == _DragTarget.drawEntity) {
                          _drawDragCurrentScreen = details.localPosition;
                          final screenSnapMm = (8.0 / scale).clamp(1.5, 8.0);
                          final isEndAlt = _isAltPressed();

                          final isLineTool = viewModel.toolMode == StudioToolMode.addBend ||
                              viewModel.toolMode == StudioToolMode.addFlange ||
                              viewModel.toolMode == StudioToolMode.addCut ||
                              viewModel.toolMode == StudioToolMode.dragDimension ||
                              viewModel.toolMode == StudioToolMode.drawPolyline;

                          CadPoint2D effectivePt = cadPt;

                          if (isEndAlt) {
                            // Alt is pressed during drag: end point moves freely without snapping
                            effectivePt = cadPt;
                            viewModel.clearSnap();
                            if (isLineTool && _drawDragStartCad != null) {
                              final dx = effectivePt.x - _drawDragStartCad!.x;
                              final dy = effectivePt.y - _drawDragStartCad!.y;
                              double angle = math.atan2(dy, dx) * 180.0 / math.pi;
                              if (angle < 0) angle += 360.0;
                              final toolLabel = viewModel.toolMode == StudioToolMode.addCut
                                  ? "CUT"
                                  : (viewModel.toolMode == StudioToolMode.dragDimension
                                      ? "DIM"
                                      : (viewModel.toolMode == StudioToolMode.drawPolyline ? "LINE" : "BEND"));
                              _dragAngleInfo = (
                                point: effectivePt,
                                label: '$toolLabel ${angle.round() % 360}° (Alt Free)',
                              );
                            } else {
                              _dragAngleInfo = null;
                            }
                          } else {
                            // Alt is not pressed: end point snaps on 5 degrees and nearest geometry
                            if (isLineTool && _drawDragStartCad != null) {
                              effectivePt = SheetMetalStudioViewModel.snapEndpointAngle(
                                anchor: _drawDragStartCad!,
                                target: effectivePt,
                                isAlt: false,
                              );
                              final dx = effectivePt.x - _drawDragStartCad!.x;
                              final dy = effectivePt.y - _drawDragStartCad!.y;
                              double angle = math.atan2(dy, dx) * 180.0 / math.pi;
                              if (angle < 0) angle += 360.0;
                              final toolLabel = viewModel.toolMode == StudioToolMode.addCut
                                  ? "CUT"
                                  : (viewModel.toolMode == StudioToolMode.dragDimension
                                      ? "DIM"
                                      : (viewModel.toolMode == StudioToolMode.drawPolyline ? "LINE" : "BEND"));
                              _dragAngleInfo = (
                                point: effectivePt,
                                label: '$toolLabel ${angle.round() % 360}°',
                              );
                            } else {
                              _dragAngleInfo = null;
                            }

                            // Magnetic snapping to nearest entity
                            viewModel.updateCursorMm(effectivePt, snapRadiusMm: screenSnapMm);
                            effectivePt = viewModel.activeSnap?.point ?? effectivePt;
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
                          final targetCutId = _draggedCutId ?? selectedCut?.id;
                          final c = viewModel.document.cutLines
                              .cast<CadLineSegment?>()
                              .firstWhere(
                                (x) => x?.id == targetCutId,
                                orElse: () => null,
                              );
                          if (c != null) anchor = c.p2;
                        } else if (_activeDrag == _DragTarget.cutP2) {
                          isCutLineDrag = true;
                          final targetCutId = _draggedCutId ?? selectedCut?.id;
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
                          isAlt = HardwareKeyboard.instance.isAltPressed;
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
                          double angle = math.atan2(dy, dx) * 180.0 / math.pi;
                          if (angle < 0) angle += 360.0;
                          currentAngleDeg = angle.round() % 360;
                        }

                        // Live magnetic snap update during dragging (lines snap, punches move smoothly)
                        if (_activeDrag == _DragTarget.bendP1 ||
                            _activeDrag == _DragTarget.bendP2 ||
                            _activeDrag == _DragTarget.cutP1 ||
                            _activeDrag == _DragTarget.cutP2) {
                          final screenSnapMm = (8.0 / scale).clamp(1.5, 8.0);
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

                          case _DragTarget.portBadge:
                            if (_draggedPortBadgeId != null) {
                              if ((details.localPosition - _dragStartScreen).distance > 4.0) {
                                _hasMovedPortBadge = true;
                              }
                              final currentOffset =
                                  _dragPortBadgeStartOffset +
                                  (details.localPosition - _dragStartScreen);
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
                                  (details.localPosition - _dragStartScreen);
                              viewModel.setDimensionOffset(
                                _draggedDimId!,
                                currentOffset,
                              );
                            }
                            break;

                          case _DragTarget.dimensionLine:
                            if (_draggedDimLineId != null) {
                              final dim = viewModel.document.dimensions
                                  .where((d) => d.id == _draggedDimLineId)
                                  .firstOrNull;
                              if (dim != null) {
                                final assoc = AssociativeDimensionEngine.resolveAssociation(dim, viewModel.document);
                                final pA = assoc.pA;
                                final pB = assoc.pB;
                                double newOffset = dim.dimensionLineOffset;

                                if (dim.type == CadDimensionType.horizontal) {
                                  final minY = math.min(pA.y, pB.y);
                                  newOffset = minY - cadPt.y;
                                } else if (dim.type == CadDimensionType.vertical) {
                                  final minX = math.min(pA.x, pB.x);
                                  newOffset = minX - cadPt.x;
                                } else {
                                  final dx = pB.x - pA.x;
                                  final dy = pB.y - pA.y;
                                  final len = math.sqrt(dx * dx + dy * dy);
                                  if (len > 1e-4) {
                                    final nx = -dy / len;
                                    final ny = dx / len;
                                    newOffset = (cadPt.x - pA.x) * nx + (cadPt.y - pA.y) * ny;
                                  }
                                }
                                viewModel.setDimensionLineOffset(_draggedDimLineId!, newOffset);
                              } else {
                                final seg = _dimensionLineSegments[_draggedDimLineId!];
                                if (seg != null) {
                                  double newOffset = seg.offsetDist;
                                  if (seg.type == CadDimensionType.horizontal) {
                                    final refY = math.min(seg.ptA.y, seg.ptB.y);
                                    newOffset = math.max(6.0, (refY - cadPt.y).abs());
                                  } else if (seg.type == CadDimensionType.vertical) {
                                    final refX = math.min(seg.ptA.x, seg.ptB.x);
                                    newOffset = math.max(6.0, (refX - cadPt.x).abs());
                                  }
                                  viewModel.setDimensionLineOffset(_draggedDimLineId!, newOffset);
                                }
                              }
                            }
                            break;

                          case _DragTarget.punch:
                            viewModel.moveSelectedPunch(candidate);
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
                            if (cadDelta.x.abs() > 0.0 || cadDelta.y.abs() > 0.0) {
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
                            if (cadDeltaCut.x.abs() > 0.0 || cadDeltaCut.y.abs() > 0.0) {
                              viewModel.moveSelectedCut(cadDeltaCut);
                            }
                            break;

                          case _DragTarget.drawEntity:
                            break;

                          case _DragTarget.none:
                            break;
                        }
                      },
                      onPanEnd: (_) {
                        if (_activeDrag == _DragTarget.drawEntity) {
                          final dragDist = (_drawDragStartScreen != null && _drawDragCurrentScreen != null)
                              ? (_drawDragCurrentScreen! - _drawDragStartScreen!).distance
                              : 0.0;
                          final screenSnapMm = (8.0 / scale).clamp(1.5, 8.0);

                          if (dragDist > 6.0) {
                            // Onshape-style: Drag & Release committed the entity!
                            final endScreen = _drawDragCurrentScreen ?? _drawDragStartScreen!;
                            final endCad = screenToCad(endScreen);
                            final isEndAlt = _isAltPressed();

                            final isLineTool = viewModel.toolMode == StudioToolMode.addBend ||
                                viewModel.toolMode == StudioToolMode.addFlange ||
                                viewModel.toolMode == StudioToolMode.addCut ||
                                viewModel.toolMode == StudioToolMode.dragDimension ||
                                viewModel.toolMode == StudioToolMode.drawPolyline;

                            CadPoint2D effectiveEnd = endCad;
                            if (isEndAlt) {
                              // Free mode for end point (Alt held at release)
                              effectiveEnd = endCad;
                            } else {
                              // Snapped mode for end point (Alt NOT held at release)
                              if (_drawDragStartCad != null && isLineTool) {
                                effectiveEnd = SheetMetalStudioViewModel.snapEndpointAngle(
                                  anchor: _drawDragStartCad!,
                                  target: effectiveEnd,
                                  isAlt: false,
                                );
                              }
                              viewModel.updateCursorMm(effectiveEnd, snapRadiusMm: screenSnapMm);
                              effectiveEnd = viewModel.activeSnap?.point ?? effectiveEnd;
                            }

                            if (viewModel.toolMode == StudioToolMode.drawCircle ||
                                viewModel.toolMode == StudioToolMode.addPunchRound) {
                              final center = _drawDragStartCad ?? viewModel.pendingBendStart ?? effectiveEnd;
                              final radius = center.distanceTo(effectiveEnd);
                              final diam = radius > 0.5
                                  ? radius * 2.0
                                  : (viewModel.toolConfig.roundHoleDiameter > 0
                                      ? viewModel.toolConfig.roundHoleDiameter
                                      : 10.0);
                              final newId = 'P${viewModel.document.punches.length + 1}';
                              final p = CncTurretEngine.createRoundHole(
                                id: newId,
                                center: center,
                                diameterMm: diam,
                              );
                              viewModel.addPunch(p);
                              viewModel.selectPunch(p.id);
                              viewModel.setPendingBendStart(null);
                              viewModel.setToolMode(StudioToolMode.select);
                            } else if (viewModel.toolMode == StudioToolMode.drawRectangle ||
                                viewModel.toolMode == StudioToolMode.addPunchSquare) {
                              final startPt = _drawDragStartCad ?? viewModel.pendingBendStart ?? effectiveEnd;
                              final rawW = (effectiveEnd.x - startPt.x).abs();
                              final rawH = (effectiveEnd.y - startPt.y).abs();
                              final double effW;
                              final double effH;
                              if (viewModel.toolConfig.squareAspectLocked) {
                                final side = math.max(rawW, rawH);
                                effW = side > 1.0
                                    ? side
                                    : (viewModel.toolConfig.squareSize > 0
                                        ? viewModel.toolConfig.squareSize
                                        : 20.0);
                                effH = effW;
                              } else {
                                effW = rawW > 1.0
                                    ? rawW
                                    : (viewModel.toolConfig.rectWidth > 0
                                        ? viewModel.toolConfig.rectWidth
                                        : 20.0);
                                effH = rawH > 1.0
                                    ? rawH
                                    : (viewModel.toolConfig.rectHeight > 0
                                        ? viewModel.toolConfig.rectHeight
                                        : 20.0);
                              }
                              final center = CadPoint2D(
                                (startPt.x + effectiveEnd.x) / 2.0,
                                (startPt.y + effectiveEnd.y) / 2.0,
                              );
                              final newId = 'P${viewModel.document.punches.length + 1}';
                              final p = CncTurretEngine.createRectangularPunch(
                                id: newId,
                                center: center,
                                widthMm: effW,
                                heightMm: effH,
                              );
                              viewModel.addPunch(p);
                              viewModel.selectPunch(p.id);
                              viewModel.setPendingBendStart(null);
                              viewModel.setToolMode(StudioToolMode.select);
                            } else if (viewModel.toolMode == StudioToolMode.addPunchObround) {
                              final center = _drawDragStartCad ?? effectiveEnd;
                              final w = (effectiveEnd.x - center.x).abs() * 2.0;
                              final l = (effectiveEnd.y - center.y).abs() * 2.0;
                              final effW = w > 2.0 ? w : viewModel.toolConfig.obroundLength;
                              final effL = l > 2.0 ? l : viewModel.toolConfig.obroundWidth;
                              final newId = 'P${viewModel.document.punches.length + 1}';
                              final p = CncTurretEngine.createObroundSlot(id: newId, center: center, widthMm: effW, lengthMm: effL);
                              viewModel.addPunch(p);
                              viewModel.selectPunch(p.id);
                              viewModel.setPendingBendStart(null);
                              viewModel.setToolMode(StudioToolMode.select);
                            } else if (viewModel.toolMode == StudioToolMode.dragDimension) {
                              final start = _drawDragStartCad ?? viewModel.pendingBendStart ?? effectiveEnd;
                              final end = effectiveEnd;
                              final dist = start.distanceTo(end);
                              if (dist > 0.5) {
                                viewModel.commitDragDimension(pA: start, pB: end);
                              }
                              viewModel.setPendingBendStart(null);
                              viewModel.setToolMode(StudioToolMode.select);
                            } else if (viewModel.toolMode == StudioToolMode.addBend ||
                                viewModel.toolMode == StudioToolMode.addFlange) {
                              final p1 = _drawDragStartCad ?? viewModel.pendingBendStart ?? effectiveEnd;
                              final p2 = effectiveEnd;
                              viewModel.setPendingBendStart(null);
                              if (p1.distanceTo(p2) > 1.0) {
                                if (viewModel.toolMode == StudioToolMode.addFlange) {
                                  viewModel.addFlangeLine(p1, p2);
                                } else {
                                  viewModel.addBendLine(p1, p2);
                                }
                              }
                              viewModel.setToolMode(StudioToolMode.select);
                            } else if (viewModel.toolMode == StudioToolMode.addCut) {
                              final p1 = _drawDragStartCad ?? viewModel.pendingBendStart ?? effectiveEnd;
                              final p2 = effectiveEnd;
                              viewModel.setPendingBendStart(null);
                              if (p1.distanceTo(p2) > 1.0) {
                                viewModel.addCutLine(p1, p2);
                              }
                              viewModel.setToolMode(StudioToolMode.select);
                            } else {
                              viewModel.handleCanvasClick(
                                effectiveEnd,
                                snapRadiusMm: screenSnapMm,
                                autoPlace: false,
                              );
                              if (viewModel.selectedDimensionId != null) {
                                final newlyCreated = viewModel.document.dimensions
                                    .where((d) => d.id == viewModel.selectedDimensionId)
                                    .firstOrNull;
                                if (newlyCreated != null) {
                                  _openInlineDimensionCallout(
                                    screenPos: _drawDragCurrentScreen ?? _drawDragStartScreen ?? Offset.zero,
                                    dimId: newlyCreated.id,
                                    pA: newlyCreated.pointA,
                                    pB: newlyCreated.pointB,
                                    referenceAId: newlyCreated.referenceAId,
                                    referenceBId: newlyCreated.referenceBId,
                                    measuredValue: newlyCreated.measuredValue,
                                    offset: newlyCreated.dimensionLineOffset,
                                  );
                                }
                              }
                            }
                            _drawDragCommitted = true;
                          } else {
                            // Single click without drag (<= 6px)
                            final clickCad = _drawDragStartCad ?? viewModel.pendingBendStart;

                            if (clickCad != null &&
                                (viewModel.toolMode == StudioToolMode.drawRectangle ||
                                 viewModel.toolMode == StudioToolMode.addPunchSquare)) {
                              final center = clickCad;
                              final w = viewModel.toolConfig.squareAspectLocked
                                  ? viewModel.toolConfig.squareSize
                                  : viewModel.toolConfig.rectWidth;
                              final h = viewModel.toolConfig.squareAspectLocked
                                  ? viewModel.toolConfig.squareSize
                                  : viewModel.toolConfig.rectHeight;
                              final effW = w > 0 ? w : 20.0;
                              final effH = h > 0 ? h : 20.0;
                              final newId = 'P${viewModel.document.punches.length + 1}';
                              final p = CncTurretEngine.createRectangularPunch(
                                id: newId,
                                center: center,
                                widthMm: effW,
                                heightMm: effH,
                              );
                              viewModel.addPunch(p);
                              viewModel.selectPunch(p.id);
                              viewModel.setPendingBendStart(null);
                              viewModel.setToolMode(StudioToolMode.select);
                              _drawDragCommitted = true;
                            } else if (clickCad != null &&
                                (viewModel.toolMode == StudioToolMode.drawCircle ||
                                 viewModel.toolMode == StudioToolMode.addPunchRound)) {
                              final center = clickCad;
                              final diam = viewModel.toolConfig.roundHoleDiameter > 0
                                  ? viewModel.toolConfig.roundHoleDiameter
                                  : 10.0;
                              final newId = 'P${viewModel.document.punches.length + 1}';
                              final p = CncTurretEngine.createRoundHole(
                                id: newId,
                                center: center,
                                diameterMm: diam,
                              );
                              viewModel.addPunch(p);
                              viewModel.selectPunch(p.id);
                              viewModel.setPendingBendStart(null);
                              viewModel.setToolMode(StudioToolMode.select);
                              _drawDragCommitted = true;
                            } else if (clickCad != null && viewModel.toolMode == StudioToolMode.addPunchObround) {
                              final center = clickCad;
                              final effW = viewModel.toolConfig.obroundLength > 0 ? viewModel.toolConfig.obroundLength : 25.0;
                              final effL = viewModel.toolConfig.obroundWidth > 0 ? viewModel.toolConfig.obroundWidth : 10.0;
                              final newId = 'P${viewModel.document.punches.length + 1}';
                              final p = CncTurretEngine.createObroundSlot(
                                id: newId,
                                center: center,
                                widthMm: effW,
                                lengthMm: effL,
                              );
                              viewModel.addPunch(p);
                              viewModel.selectPunch(p.id);
                              viewModel.setPendingBendStart(null);
                              viewModel.setToolMode(StudioToolMode.select);
                              _drawDragCommitted = true;
                            } else if (clickCad != null && viewModel.toolMode == StudioToolMode.dragDimension) {
                              if (viewModel.pendingBendStart == null) {
                                viewModel.setPendingBendStart(clickCad);
                              } else {
                                final pA = viewModel.pendingBendStart!;
                                final pB = clickCad;
                                if (pA.distanceTo(pB) > 0.5) {
                                  viewModel.commitDragDimension(pA: pA, pB: pB);
                                }
                                viewModel.setPendingBendStart(null);
                                viewModel.setToolMode(StudioToolMode.select);
                              }
                              _drawDragCommitted = true;
                            } else {
                              // Standard multi-click line/polyline/arc drawing:
                              if (viewModel.pendingBendStart != null && _drawDragStartCad != null &&
                                  viewModel.pendingBendStart != _drawDragStartCad) {
                                viewModel.handleCanvasClick(
                                  _drawDragStartCad!,
                                  snapRadiusMm: screenSnapMm,
                                  autoPlace: false,
                                );
                                if (viewModel.selectedDimensionId != null) {
                                  final newlyCreated = viewModel.document.dimensions
                                      .where((d) => d.id == viewModel.selectedDimensionId)
                                      .firstOrNull;
                                  if (newlyCreated != null) {
                                    _openInlineDimensionCallout(
                                      screenPos: _drawDragStartScreen ?? _drawDragCurrentScreen ?? Offset.zero,
                                      dimId: newlyCreated.id,
                                      pA: newlyCreated.pointA,
                                      pB: newlyCreated.pointB,
                                      referenceAId: newlyCreated.referenceAId,
                                      referenceBId: newlyCreated.referenceBId,
                                      measuredValue: newlyCreated.measuredValue,
                                      offset: newlyCreated.dimensionLineOffset,
                                    );
                                  }
                                }
                                _drawDragCommitted = true;
                              } else {
                                if (viewModel.pendingBendStart == null && _drawDragStartCad != null) {
                                  viewModel.setPendingBendStart(_drawDragStartCad);
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
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _drawDragCommitted = false;
                          });
                          setState(() {});
                          return;
                        }

                        if (_activeDrag == _DragTarget.boxSelect) {
                          if (_boxSelectStart != null &&
                              _boxSelectCurrent != null) {
                            final dist =
                                (_boxSelectCurrent! - _boxSelectStart!).distance;
                            if (dist > 6.0) {
                              final p1 = screenToCad(_boxSelectStart!);
                              final p2 = screenToCad(_boxSelectCurrent!);
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
                                viewModel.selectEntities({...viewModel.selectedEntityIds, ...selectedIds});
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

                        if (_draggedPortBadgeId != null && !_hasMovedPortBadge) {
                          final pId = _draggedPortBadgeId!;
                          _draggedPortBadgeId = null;
                          _activeDrag = _DragTarget.none;
                          _shiftSelectionHandledInPan = false;
                          _openPortDimensionEditor(pId);
                          return;
                        }

                        if (_activeDrag == _DragTarget.dimensionLine) {
                          if (_draggedDimLineId != null) {
                            viewModel.commitDimensionLineOffset(_draggedDimLineId!);
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
                        _activeDrag = _DragTarget.none;
                        _dragAngleInfo = null;
                        _shiftSelectionHandledInPan = false;
                        if (wasObjectDrag) {
                          viewModel.endObjectDrag();
                        }
                      },
                      onPanCancel: () {
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
                        _activeDrag = _DragTarget.none;
                        _dragAngleInfo = null;
                        if (wasObjectDrag) {
                          viewModel.endObjectDrag();
                        }
                        setState(() {});
                      },
                      onSecondaryTapUp: (details) {
                        if (viewModel.toolMode == StudioToolMode.drawPolyline &&
                            viewModel.pendingMultiPoints.isNotEmpty) {
                          viewModel.finishPolyline(close: false);
                          return;
                        }
                        if (viewModel.pendingBendStart != null) {
                          viewModel.clearSnap();
                          viewModel.setToolMode(viewModel.toolMode);
                          return;
                        }
                        if (viewModel.toolMode != StudioToolMode.select) {
                          viewModel.setToolMode(StudioToolMode.select);
                          return;
                        }

                        // Check if right-clicking on or near an outer contour edge for port assignment
                        final cadPt = screenToCad(details.localPosition);
                        final contour = viewModel.document.outerContour;
                        CadPoint2D? bestP1;
                        CadPoint2D? bestP2;
                        double minD = double.infinity;
                        for (int i = 0; i < contour.length; i++) {
                          final p1 = contour[i];
                          final p2 = contour[(i + 1) % contour.length];
                          final d = _distToSegment(cadPt, p1, p2) * scale;
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
                            _contextMenuLenMm = bestP1!.distanceTo(bestP2!);
                          });
                          _contextMenuController.open(position: details.localPosition);
                        } else {
                          viewModel.clearSelection();
                        }
                      },
                      onTapUp: (details) {
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
                            now.difference(_lastTapTime!) < const Duration(milliseconds: 280) &&
                            _lastTapPosition != null &&
                            (touchScreen - _lastTapPosition!).distance <= 20.0) {
                          _lastTapTime = null;
                          _lastTapPosition = null;
                          _handleCanvasDoubleTap(touchScreen, screenToCad, cadToScreen);
                          return;
                        }
                        _lastTapTime = now;
                        _lastTapPosition = touchScreen;

                        // Handling interactive geometric constraint picking
                        if (viewModel.activeConstraintPickType != null) {
                          if (viewModel.hoveredPunchId != null) {
                            viewModel.registerEntityPickForConstraint(
                              EntityRef.punchCenter(viewModel.hoveredPunchId!),
                            );
                            return;
                          }
                          if (viewModel.hoveredBendId != null) {
                            viewModel.registerEntityPickForConstraint(
                              EntityRef(entityId: viewModel.hoveredBendId!),
                            );
                            return;
                          }
                          if (viewModel.hoveredCutId != null) {
                            viewModel.registerEntityPickForConstraint(
                              EntityRef(entityId: viewModel.hoveredCutId!),
                            );
                            return;
                          }
                          if (viewModel.hoveredContourEdgeP1 != null &&
                              viewModel.hoveredContourEdgeP2 != null) {
                            final p1 = viewModel.hoveredContourEdgeP1!;
                            final p2 = viewModel.hoveredContourEdgeP2!;
                            final isVertical = (p1.x - p2.x).abs() < 1.0;
                            final bw = viewModel.document.blankWidthMm > 0 ? viewModel.document.blankWidthMm : 200.0;
                            final bl = viewModel.document.blankLengthMm > 0 ? viewModel.document.blankLengthMm : 300.0;
                            final EntityRef edgeRef;
                            if (isVertical) {
                              final midX = (p1.x + p2.x) / 2.0;
                              edgeRef = midX < bw / 2.0 ? EntityRef.edgeLeft : EntityRef.edgeRight;
                            } else {
                              final midY = (p1.y + p2.y) / 2.0;
                              edgeRef = midY < bl / 2.0 ? EntityRef.edgeBottom : EntityRef.edgeTop;
                            }
                            viewModel.registerEntityPickForConstraint(edgeRef);
                            return;
                          }
                        }

                        // Handling 1-Click Semantic Port Inference
                        if (viewModel.toolMode == StudioToolMode.assignPortSemantic ||
                            viewModel.activeSemanticPortId != null) {
                          final cadPt = screenToCad(details.localPosition);
                          viewModel.handleCanvasSemanticPortClick(cadPt);
                          return;
                        }

                        // Handling interactive edge picking for fitting openings (W and H)
                        if (viewModel.toolMode == StudioToolMode.pickPortEdge ||
                            viewModel.activePortPickTarget != null) {
                          if (viewModel.hoveredContourEdgeP1 != null &&
                              viewModel.hoveredContourEdgeP2 != null) {
                            final p1 = viewModel.hoveredContourEdgeP1!;
                            final p2 = viewModel.hoveredContourEdgeP2!;
                            final lenMm = viewModel.hoveredContourEdgeLengthMm ?? p1.distanceTo(p2);
                            final target = viewModel.activePortPickTarget!;
                            final targetName = target.displayName;
                            final collisionError = viewModel.completePortEdgePick(
                              p1: p1,
                              p2: p2,
                              measuredLengthMm: lenMm,
                            );
                            if (collisionError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          collisionError,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFFDC2626),
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Assigned $targetName: ${lenMm.toStringAsFixed(1)} mm'),
                                backgroundColor: const Color(0xFF0D9488),
                                duration: const Duration(seconds: 4),
                                action: SnackBarAction(
                                  label: 'Open Inspector',
                                  textColor: Colors.amberAccent,
                                  onPressed: () => viewModel.setFittingInspectorOpen(true),
                                ),
                              ),
                            );
                            return;
                          }
                        }

                        final cadPt = screenToCad(details.localPosition);
                        // When in Fillet mode, clicking on a bend line pops up the bend radius editor
                        if (viewModel.toolMode == StudioToolMode.cornerFillet) {
                          FoldBendLine? hitBend;
                          for (final b in viewModel.document.bends) {
                            if (_distToSegment(cadPt, b.p1, b.p2) * scale <=
                                16.0) {
                              hitBend = b;
                              break;
                            }
                          }
                          if (hitBend != null) {
                            BendRadiusDialog.show(context, viewModel, hitBend);
                            return;
                          }
                        }
                        final isShiftHeld = _isShiftPressed();
                        final screenSnapMm = (8.0 / scale).clamp(1.5, 8.0);
                        viewModel.handleCanvasClick(
                          cadPt,
                          snapRadiusMm: screenSnapMm,
                          autoPlace: true,
                          multiSelect: isShiftHeld,
                        );
                      },
                      child: Builder(
                        builder: (context) {
                          CadLineSegment? autoCandidateLine;
                          if (viewModel.pendingBendStart == null &&
                              (viewModel.toolMode == StudioToolMode.addBend ||
                               viewModel.toolMode == StudioToolMode.addFlange) &&
                              viewModel.rubberBandEndpoint != null) {
                            autoCandidateLine = viewModel.computeAutoBendOrFlangeLine(
                              viewModel.rubberBandEndpoint!,
                              isFlange: viewModel.toolMode == StudioToolMode.addFlange,
                            );
                          }

                          return ExcludeSemantics(
                            child: Stack(
                              children: [
                                CustomPaint(
                                  size: Size.infinite,
                                  painter: _UnfoldedBoardPainter(
                              doc: viewModel.document,
                              foldProgress: viewModel.foldProgress,
                              foldedMesh: viewModel.currentMesh,
                              pan: viewModel.pan2D,
                              zoom: viewModel.zoom2D,
                              toolMode: viewModel.toolMode,
                              activeSnap: viewModel.activeSnap,
                              pendingBendStart: viewModel.pendingBendStart,
                              rubberBandEndpoint: viewModel.rubberBandEndpoint,
                              pendingMultiPoints: viewModel.pendingMultiPoints,
                              selectedBendId: viewModel.selectedBendId,
                              selectedCutId: viewModel.selectedCutId,
                              selectedFaceId: viewModel.selectedFaceId,
                              selectedPunchId: viewModel.selectedPunchId,
                              selectedPatternId: viewModel.selectedPatternId,
                              selectedPatternHoleIndex:
                                  viewModel.selectedPatternHoleIndex,
                              showDimensions: viewModel.showDimensions,
                              bendViolations: viewModel.bendViolations,
                              hoveredPunchId: viewModel.hoveredPunchId,
                              hoveredBendId: viewModel.hoveredBendId,
                              toolConfig: viewModel.toolConfig,
                              isBendIncompleteFn: viewModel.isBendIncomplete,
                              hoveredEndpoint: _hoveredEndpoint,
                              dragAngleInfo: _dragAngleInfo,
                              previewPerforationPattern:
                                  viewModel.previewPerforationPattern,
                              previewCouplerPunches:
                                  viewModel.previewCouplerPunches,
                              dimensionOffsets: viewModel.dimensionOffsets,
                              dimensionLineOffsets: viewModel.dimensionLineOffsets,
                              renderedDimensionBadges: _dimensionBadgeRects,
                              renderedDimensionLines: _dimensionLineSegments,
                              hoveredDimLineId: _hoveredDimLineId,
                              portBadgeOffsets: viewModel.portBadgeOffsets,
                              renderedPortBadges: _portBadgeRects,
                              hoveredContourEdgeP1: viewModel.hoveredContourEdgeP1,
                              hoveredContourEdgeP2: viewModel.hoveredContourEdgeP2,
                              hoveredContourEdgeLengthMm: viewModel.hoveredContourEdgeLengthMm,
                              selectedEntityIds: viewModel.selectedEntityIds,
                              boxSelectStart: _boxSelectStart,
                              boxSelectCurrent: _boxSelectCurrent,
                              autoCandidateLine: autoCandidateLine,
                              showOpeningTags: viewModel.showPortOpeningBadges,
                              fittingMetadata: viewModel.detectedFittingMetadata ??
                                  DxfFittingMetadata.fromDocument(viewModel.document),
                              referenceGeometries: viewModel.activeReferenceGeometries,
                              constraintDefinitions: viewModel.activeConstraintDefinitions,
                              selectedConstraintId: viewModel.selectedConstraintId,
                              hoveredConstraintId: _hoveredConstraintId,
                              renderedConstraintBadges: _constraintBadgeRects,
                              constraintHoverHighlightedEntityIds: _constraintHoverHighlightedEntityIds,
                              showDofDiagnostics: viewModel.showDofDiagnostics,
                              dofStateProvider: viewModel.getEntityConstraintState,
                              showConstructionGeometry: viewModel.showConstructionGeometry,
                              showConstraints: viewModel.showConstraints,
                              showProfileFill: _showProfileFill,
                              showPoints: _showPoints,
                              showGrid: _showGrid,
                              selectedArcId: viewModel.selectedArcId,
                              hoveredArcId: viewModel.hoveredArcId,
                              activePortInferenceResult: viewModel.activePortInferenceResult,
                              hoverCursorCad: _hoverCursorCad,
                              isAltPressed: _isAltPressed(),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: Listenable.merge([viewModel, viewModel.cmsGuidedController]),
                            builder: (context, _) {
                              final ctrl = viewModel.cmsGuidedController;
                              final ports = viewModel.activeCmsPorts;
                              final suggestedBends = ctrl.state.suggestedBends;
                              final showBends = ctrl.phase == CmsUxPhase.suggestingBends ||
                                                ctrl.phase == CmsUxPhase.confirmingBends;
                              if (ports.isEmpty && (!showBends || suggestedBends.isEmpty)) {
                                return const SizedBox.shrink();
                              }
                              return CustomPaint(
                                size: Size.infinite,
                                painter: Cms2DOverlayPainter(
                                  ports: ports,
                                  suggestedBends: showBends ? suggestedBends : const [],
                                  focus: ctrl.state.focus,
                                  worldToScreen: (x, y) => cadToScreen(CadPoint2D(x, y)),
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
                          viewModel.setToolMode(StudioToolMode.addDimension);
                        },
                        onDismiss: () {
                          viewModel.clearSelection();
                        },
                      ),
                    ),
                  ),

                // Inline Floating Dimension Callout Card (Component 1)
                _buildInlineDimensionCallout(viewModel),

                // 2. Fitting Metadata / DSF Inspector Badge (Always accessible)
                Positioned(
                  top: 12,
                  left: 12,
                  child: InkWell(
                    onTap: () => viewModel.setFittingInspectorOpen(true),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.65),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune, size: 14, color: Color(0xFFA78BFA)),
                          const SizedBox(width: 6),
                          Text(
                            (viewModel.detectedFittingMetadata != null &&
                                    viewModel.detectedFittingMetadata!.isAssigned &&
                                    viewModel.detectedFittingMetadata!.product.isNotEmpty)
                                ? '${viewModel.detectedFittingMetadata!.product} (${viewModel.detectedFittingMetadata!.variantName})'
                                : 'DSF Inspector',
                            style: const TextStyle(
                              color: Color(0xFFF1F5F9),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Floating Sketch Palette (Top Right Corner - non-persistent, toggled via toolbar button)
                if (viewModel.isSketchPaletteOpen)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: StudioSketchPalette(
                      viewModel: viewModel,
                      showGrid: _showGrid,
                      showProfileFill: _showProfileFill,
                      showPoints: _showPoints,
                      onToggleGrid: (val) {
                        setState(() {
                          _showGrid = val;
                        });
                      },
                      onToggleProfileFill: (val) {
                        setState(() {
                          _showProfileFill = val;
                        });
                      },
                      onTogglePoints: (val) {
                        setState(() {
                          _showPoints = val;
                        });
                      },
                      onClose: () {
                        viewModel.setSketchPaletteOpen(false);
                      },
                      onFinishSketch: () {
                        viewModel.setToolMode(StudioToolMode.select);
                        viewModel.setSketchPaletteOpen(false);
                      },
                    ),
                  ),

                // Floating Constraints Manager Sheet
                if (viewModel.isConstraintManagerOpen)
                  Positioned(
                    top: 48,
                    left: 12,
                    child: ConstraintManagerSheet(
                      viewModel: viewModel,
                      onClose: () => viewModel.setConstraintManagerOpen(false),
                    ),
                  ),

                // Constraint Binding HUD (Interactive prompt banner during constraint creation)
                if (viewModel.activeConstraintPickType != null)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ConstraintBindingHud(viewModel: viewModel),
                    ),
                  ),

                // 2b. Floating HUD for Interactive Port Edge Picking (W and H)
                if (viewModel.activePortPickTarget != null)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.touch_app, color: Color(0xFF38BDF8), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Select Edge for ${viewModel.activePortPickTarget!.displayName}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            if (viewModel.hoveredContourEdgeLengthMm != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D9488),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${viewModel.hoveredContourEdgeLengthMm!.toStringAsFixed(1)} mm',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () => viewModel.cancelPortEdgePick(),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 11)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 2c. Floating HUD for 1-Click Semantic Port Inference
                if (viewModel.activeSemanticPortId != null)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: viewModel.activePortInferenceResult != null
                                ? const Color(0xFF10B981)
                                : const Color(0xFF0EA5E9),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              viewModel.activePortInferenceResult != null
                                  ? Icons.check_circle_outline
                                  : Icons.ads_click,
                              color: viewModel.activePortInferenceResult != null
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF38BDF8),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            if (viewModel.activePortInferenceResult == null) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Click Opening Edge for ${viewModel.activeSemanticPortId!.toUpperCase()}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    'Auto-infers Width (W), Sidewalls (H-A/H-B), and Connection Normal',
                                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              InkWell(
                                onTap: () => viewModel.cancelSemanticPortAssignment(),
                                borderRadius: BorderRadius.circular(5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                ),
                              ),
                            ] else ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Inferred ${viewModel.activePortInferenceResult!.inferredSide.displayName} Port (${viewModel.activeSemanticPortId!.toUpperCase()}):',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    viewModel.activePortInferenceResult!.summaryText,
                                    style: const TextStyle(
                                      color: Color(0xFF34D399),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              ElevatedButton.icon(
                                onPressed: () => viewModel.confirmSemanticPortAssignment(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  elevation: 2,
                                ),
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text(
                                  'Confirm (1-Click)',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => viewModel.cancelSemanticPortAssignment(),
                                borderRadius: BorderRadius.circular(5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                // 2d. Port-Driven Dimension Editor Floating Card (Set 4A)
                if (_activeEditingPortId != null)
                  Positioned(
                    left: (_portEditorScreenPos?.dx ?? 40.0).clamp(16.0, math.max(16.0, constraints.maxWidth - 300.0)),
                    top: (_portEditorScreenPos?.dy ?? 80.0).clamp(16.0, math.max(16.0, constraints.maxHeight - 340.0)),
                    child: _buildPortDimensionEditorCard(viewModel),
                  ),

                // 2e. "Why Did This Move?" Semantic Feature Inspector Card (Set 4A)
                if (viewModel.selectedPunchId != null)
                  _buildWhyDidThisMoveCard(viewModel, constraints),

                // 3. Tool Mode Selector (+ Bend, + Cut, Punches, Snapping Toggle)
                if (widget.showInCanvasToolRibbon)
                  Positioned(
                    top: 50,
                    left: 12,
                    right: 12,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: math.max(100.0, constraints.maxWidth - 24.0),
                      ),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                            PointerDeviceKind.stylus,
                          },
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _toolButton(
                                icon: Icons.near_me,
                                label: 'Select',
                                active:
                                    viewModel.toolMode == StudioToolMode.select,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.select,
                                ),
                              ),
                              const SizedBox(width: 3),
                              _toolButton(
                                icon: Icons.pan_tool_outlined,
                                label: 'Pan',
                                active:
                                    viewModel.toolMode == StudioToolMode.pan,
                                onTap: () =>
                                    viewModel.setToolMode(StudioToolMode.pan),
                              ),
                              if (viewModel.document.productType.toLowerCase().contains('tee') ||
                                  viewModel.document.productType.toLowerCase().contains('fitting')) ...[
                                const SizedBox(width: 3),
                                _toolButton(
                                  icon: viewModel.showPortOpeningBadges
                                      ? Icons.label
                                      : Icons.label_off_outlined,
                                  label: viewModel.showPortOpeningBadges
                                      ? 'W×H Tags: ON'
                                      : 'W×H Tags: OFF',
                                  active: viewModel.showPortOpeningBadges,
                                  onTap: viewModel.togglePortOpeningBadges,
                                ),
                              ],
                              const SizedBox(width: 3),
                              _toolButton(
                                icon: Icons.polyline,
                                label: '+ Bend',
                                active:
                                    viewModel.toolMode ==
                                    StudioToolMode.addBend,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.addBend,
                                ),
                              ),
                              const SizedBox(width: 3),
                              _toolButton(
                                icon: Icons.border_top,
                                label: '+ Flange',
                                active:
                                    viewModel.toolMode ==
                                    StudioToolMode.addFlange,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.addFlange,
                                ),
                              ),
                              const SizedBox(width: 3),
                              _toolButton(
                                icon: Icons.content_cut,
                                label: '+ Cut',
                                active:
                                    viewModel.toolMode == StudioToolMode.addCut,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.addCut,
                                ),
                              ),
                              const SizedBox(width: 3),
                              _toolButton(
                                icon: Icons.radio_button_unchecked,
                                label: 'Round Hole',
                                active:
                                    viewModel.toolMode ==
                                    StudioToolMode.addPunchRound,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.addPunchRound,
                                ),
                              ),
                              const SizedBox(width: 3),
                              _toolButton(
                                customIcon: ObroundSlotIcon(
                                  width: 15,
                                  height: 10,
                                  color:
                                      viewModel.toolMode ==
                                          StudioToolMode.addPunchObround
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFF475569),
                                ),
                                label: 'Obround Slot',
                                active:
                                    viewModel.toolMode ==
                                    StudioToolMode.addPunchObround,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.addPunchObround,
                                ),
                              ),
                              const SizedBox(width: 3),
                              _toolButton(
                                icon: Icons.crop_square,
                                label: 'Square',
                                active:
                                    viewModel.toolMode ==
                                    StudioToolMode.addPunchSquare,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.addPunchSquare,
                                ),
                              ),
                              const SizedBox(width: 3),
                              _toolButton(
                                icon: Icons.grid_view,
                                label: 'Perforation',
                                active:
                                    viewModel.toolMode ==
                                    StudioToolMode.perforationPattern,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.perforationPattern,
                                ),
                              ),
                              const SizedBox(width: 3),
                              _toolButton(
                                icon: Icons.anchor,
                                label: 'Anchor',
                                active:
                                    viewModel.toolMode ==
                                    StudioToolMode.setBaseAnchor,
                                onTap: () => viewModel.setToolMode(
                                  StudioToolMode.setBaseAnchor,
                                ),
                              ),
                              const SizedBox(width: 3),
                              // 2D Draw Tools Dropdown Menu (Step 3 #16)
                              PopupMenuButton<StudioToolMode>(
                                tooltip: '2D Draw Tools',
                                icon: Icon(
                                  Icons.draw_outlined,
                                  size: 15,
                                  color: (viewModel.toolMode == StudioToolMode.drawRectangle ||
                                          viewModel.toolMode == StudioToolMode.drawCircle ||
                                          viewModel.toolMode == StudioToolMode.drawArc ||
                                          viewModel.toolMode == StudioToolMode.drawPolyline)
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFF475569),
                                ),
                                onSelected: (mode) => viewModel.setToolMode(mode),
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: StudioToolMode.drawRectangle,
                                    child: Row(
                                      children: [
                                        Icon(Icons.crop_3_2, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Rectangle (2-Point)'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: StudioToolMode.drawCircle,
                                    child: Row(
                                      children: [
                                        Icon(Icons.circle_outlined, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Circle (Center-Radius)'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: StudioToolMode.drawArc,
                                    child: Row(
                                      children: [
                                        Icon(Icons.architecture, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Arc (3-Point)'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: StudioToolMode.drawPolyline,
                                    child: Row(
                                      children: [
                                        Icon(Icons.timeline, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Polyline (Continuous)'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 3),
                              // 2D Modify Tools Dropdown Menu (Step 4 #17)
                              PopupMenuButton<String>(
                                tooltip: '2D Modify Tools',
                                icon: Icon(
                                  Icons.handyman_outlined,
                                  size: 15,
                                  color: (viewModel.toolMode == StudioToolMode.modifyMove ||
                                          viewModel.toolMode == StudioToolMode.modifyRotate ||
                                          viewModel.toolMode == StudioToolMode.modifyMirror ||
                                          viewModel.toolMode == StudioToolMode.modifyOffset)
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFF475569),
                                ),
                                onSelected: (action) {
                                  switch (action) {
                                    case 'move':
                                      viewModel.setToolMode(StudioToolMode.modifyMove);
                                      break;
                                    case 'rotate':
                                      viewModel.setToolMode(StudioToolMode.modifyRotate);
                                      break;
                                    case 'mirror':
                                      viewModel.setToolMode(StudioToolMode.modifyMirror);
                                      break;
                                    case 'offset':
                                      viewModel.setToolMode(StudioToolMode.modifyOffset);
                                      break;
                                    case 'duplicate':
                                      viewModel.duplicateSelectedEntities(10.0, 10.0);
                                      break;
                                    case 'delete':
                                      viewModel.deleteSelectedEntities();
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'move',
                                    child: Row(
                                      children: [
                                        Icon(Icons.open_with, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Move Selected'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'rotate',
                                    child: Row(
                                      children: [
                                        Icon(Icons.rotate_right, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Rotate Selected'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'mirror',
                                    child: Row(
                                      children: [
                                        Icon(Icons.flip, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Mirror Selected (Copy)'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'offset',
                                    child: Row(
                                      children: [
                                        Icon(Icons.copy_all, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Offset Contour'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'duplicate',
                                    child: Row(
                                      children: [
                                        Icon(Icons.content_copy, size: 16, color: Color(0xFF0F172A)),
                                        SizedBox(width: 8),
                                        Text('Duplicate (+10, +10 mm)'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                                        SizedBox(width: 8),
                                        Text('Delete Selected',
                                            style: TextStyle(color: Color(0xFFEF4444))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 3),
                              // Associative Dimension Tool (Step 6 #19)
                              _toolButton(
                                icon: Icons.straighten,
                                label: 'Dim',
                                active: viewModel.toolMode == StudioToolMode.addDimension,
                                onTap: () => viewModel.setToolMode(
                                  viewModel.toolMode == StudioToolMode.addDimension
                                      ? StudioToolMode.select
                                      : StudioToolMode.addDimension,
                                ),
                              ),
                              const SizedBox(width: 3),
                              // Geometric Constraints Tool Menu
                              PopupMenuButton<CadConstraintType>(
                                tooltip: 'Apply Geometric Constraint',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: viewModel.activeConstraintPickType != null
                                        ? const Color(0xFFE0F2FE)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: viewModel.activeConstraintPickType != null
                                          ? const Color(0xFF0284C7)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.link,
                                        size: 13,
                                        color: viewModel.activeConstraintPickType != null
                                            ? const Color(0xFF0284C7)
                                            : const Color(0xFF475569),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Constraint',
                                        style: TextStyle(
                                          color: viewModel.activeConstraintPickType != null
                                              ? const Color(0xFF0284C7)
                                              : const Color(0xFF475569),
                                          fontSize: 11,
                                          fontWeight: viewModel.activeConstraintPickType != null
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF64748B)),
                                    ],
                                  ),
                                ),
                                onSelected: (type) {
                                  viewModel.startInteractiveConstraint(type);
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: CadConstraintType.coincident,
                                    child: Row(
                                      children: [
                                        Icon(Icons.adjust, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 8),
                                        Text('Coincident (Snap points together)'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: CadConstraintType.distance,
                                    child: Row(
                                      children: [
                                        Icon(Icons.straighten, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 8),
                                        Text('Distance / Clearance (Bind to Edge)'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: CadConstraintType.horizontal,
                                    child: Row(
                                      children: [
                                        Icon(Icons.horizontal_rule, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 8),
                                        Text('Horizontal Alignment'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: CadConstraintType.vertical,
                                    child: Row(
                                      children: [
                                        Icon(Icons.vertical_distribute, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 8),
                                        Text('Vertical Alignment'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: CadConstraintType.parallel,
                                    child: Row(
                                      children: [
                                        Icon(Icons.reorder, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 8),
                                        Text('Parallel'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: CadConstraintType.perpendicular,
                                    child: Row(
                                      children: [
                                        Icon(Icons.square_foot, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 8),
                                        Text('Perpendicular'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: CadConstraintType.symmetric,
                                    child: Row(
                                      children: [
                                        Icon(Icons.splitscreen, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 8),
                                        Text('Symmetric about Centerline'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: CadConstraintType.concentric,
                                    child: Row(
                                      children: [
                                        Icon(Icons.album_outlined, size: 16, color: Color(0xFF2563EB)),
                                        SizedBox(width: 8),
                                        Text('Concentric'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 1,
                                height: 18,
                                color: const Color(0xFFCBD5E1),
                              ),
                              const SizedBox(width: 6),
                              // Magnetic Snapping Toggle
                              _toolButton(
                                icon: viewModel.magneticSnapEnabled
                                    ? Icons.gps_fixed
                                    : Icons.gps_not_fixed,
                                label: viewModel.magneticSnapEnabled
                                    ? 'Snap: ON'
                                    : 'Snap: OFF',
                                active: viewModel.magneticSnapEnabled,
                                onTap: viewModel.toggleMagneticSnap,
                              ),
                              const SizedBox(width: 3),
                              // Snap Mode Dropdown / Settings Menu
                              PopupMenuButton<SnapType>(
                                tooltip: 'Snap Modes',
                                icon: const Icon(
                                  Icons.tune,
                                  size: 15,
                                  color: Color(0xFF475569),
                                ),
                                onSelected: (type) =>
                                    viewModel.toggleSnapSetting(type),
                                itemBuilder: (context) {
                                  final s = viewModel.snapSettings;
                                  return [
                                    _snapMenuItem(
                                      SnapType.endpoint,
                                      'Endpoint 🔲',
                                      s.enableEndpoint,
                                    ),
                                    _snapMenuItem(
                                      SnapType.midpoint,
                                      'Midpoint 🔺',
                                      s.enableMidpoint,
                                    ),
                                    _snapMenuItem(
                                      SnapType.center,
                                      'Center ⭕',
                                      s.enableCenter,
                                    ),
                                    _snapMenuItem(
                                      SnapType.intersection,
                                      'Intersection ✖',
                                      s.enableIntersection,
                                    ),
                                    _snapMenuItem(
                                      SnapType.perpendicular,
                                      'Perpendicular ⟂',
                                      s.enablePerpendicular,
                                    ),
                                    _snapMenuItem(
                                      SnapType.tangent,
                                      'Tangent ⊚',
                                      s.enableTangent,
                                    ),
                                    _snapMenuItem(
                                      SnapType.quadrant,
                                      'Quadrant 🔷',
                                      s.enableQuadrant,
                                    ),
                                    _snapMenuItem(
                                      SnapType.nearest,
                                      'Nearest ⧗',
                                      s.enableNearest,
                                    ),
                                    _snapMenuItem(
                                      SnapType.grid,
                                      'Grid Snap ⊞',
                                      s.enableGrid,
                                    ),
                                  ];
                                },
                              ),
                              const SizedBox(width: 3),
                              // Ortho Tracking Toggle
                              _toolButton(
                                icon: Icons.near_me_disabled,
                                label: viewModel.snapSettings.enableOrthoTracking
                                    ? 'Ortho: ON'
                                    : 'Ortho: OFF',
                                active:
                                    viewModel.snapSettings.enableOrthoTracking,
                                onTap: viewModel.toggleOrthoTracking,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. Draggable Floating Property Inspector (Line, Punch, Bend, Pattern, Face, Dimension)
                if (widget.renderFloatingInspectors &&
                    (selectedBend != null ||
                        selectedCut != null ||
                        selectedPunch != null ||
                        selectedPattern != null ||
                        selectedDimension != null ||
                        selectedArc != null ||
                        (selectedFace != null && !isToolActive)) &&
                    viewModel.isPropertyInspectorOpen)
                  Positioned(
                    left: effectiveInspectorPos.dx.clamp(
                      8.0,
                      math.max(8.0, constraints.maxWidth - 280.0),
                    ),
                    top: effectiveInspectorPos.dy.clamp(
                      8.0,
                      math.max(8.0, constraints.maxHeight - 120.0),
                    ),
                    child: _buildFloatingInspector(
                      viewModel: viewModel,
                      effectiveInspectorPos: effectiveInspectorPos,
                    ),
                  ),

                // 4b. Draggable Active Tool Property Inspector (Configured BEFORE stamping)
                if (widget.renderFloatingInspectors &&
                    viewModel.toolMode != StudioToolMode.select &&
                    viewModel.toolMode != StudioToolMode.pan &&
                    viewModel.toolMode != StudioToolMode.addBend &&
                    viewModel.toolMode != StudioToolMode.addFlange &&
                    viewModel.toolMode != StudioToolMode.addCut &&
                    viewModel.toolMode != StudioToolMode.setBaseAnchor)
                  Positioned(
                    left: effectiveInspectorPos.dx.clamp(
                      8.0,
                      math.max(8.0, constraints.maxWidth - 290.0),
                    ),
                    top: effectiveInspectorPos.dy.clamp(
                      8.0,
                      math.max(8.0, constraints.maxHeight - 120.0),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        _dragStartGlobal = details.globalPosition;
                        _dragStartPanel = effectiveInspectorPos;
                      },
                      onPanUpdate: (details) {
                        if (_dragStartGlobal != null &&
                            _dragStartPanel != null) {
                          setState(() {
                            _inspectorOffset =
                                _dragStartPanel! +
                                (details.globalPosition - _dragStartGlobal!);
                          });
                        }
                      },
                      child: ActiveToolPropertySheet(
                        viewModel: viewModel,
                        onClose: () =>
                            viewModel.setToolMode(StudioToolMode.select),
                        onDragStartHeader: (details) {
                          _dragStartGlobal = details.globalPosition;
                          _dragStartPanel = effectiveInspectorPos;
                        },
                        onDragHeader: (details) {
                          if (_dragStartGlobal != null &&
                              _dragStartPanel != null) {
                            setState(() {
                              _inspectorOffset =
                                  _dragStartPanel! +
                                  (details.globalPosition - _dragStartGlobal!);
                            });
                          }
                        },
                      ),
                    ),
                  ),

                // Floating Reopen Button if Inspector is closed but an item is selected
                if (widget.renderFloatingInspectors &&
                    (selectedBend != null ||
                        selectedPunch != null ||
                        selectedPattern != null ||
                        selectedFace != null) &&
                    !viewModel.isPropertyInspectorOpen)
                  Positioned(
                    top: 12,
                    right: 180,
                    child: InkWell(
                      onTap: () {
                        viewModel.setPropertyInspectorOpen(true);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF0284C7)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.tune,
                              size: 14,
                              color: Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              selectedBend != null
                                  ? 'Open ${selectedBend.id} Properties'
                                  : (selectedPunch != null
                                      ? 'Open ${selectedPunch.id} Properties'
                                      : (selectedPattern != null
                                          ? 'Open ${selectedPattern.id} Properties'
                                          : 'Open ${selectedFace!.id} Properties')),
                              style: const TextStyle(
                                color: Color(0xFF0284C7),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 5. Studio Bottom Bar (Floating Navigation Toolstrip & TEXT COMMANDS Prompt)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: StudioBottomBar(viewModel: viewModel),
                ),

                // 6. Ultra-Small Micro Layer Legend (Hovers neatly above bottom bar)
                Positioned(
                  bottom: 36,
                  right: 12,
                  child: _buildCompactLegend(),
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

  List<Widget> _buildEdgeContextMenuChildren(SheetMetalStudioViewModel viewModel) {
    if (_contextMenuP1 == null || _contextMenuP2 == null) return const [];
    final p1 = _contextMenuP1!;
    final p2 = _contextMenuP2!;
    final lenMm = _contextMenuLenMm ?? p1.distanceTo(p2);
    final assigned = viewModel.findAssignedPortForEdge(p1, p2);
    final meta = viewModel.detectedFittingMetadata ?? DxfFittingMetadata.fromDocument(viewModel.document);
    final portCount = meta != null ? ProductCatalogService.getPortCount(meta.product, meta.variantName) : 2;

    return [
      MenuItemButton(
        onPressed: null,
        child: Text(
          'Edge: ${lenMm.toStringAsFixed(1)} mm${assigned != null ? ' ($assigned)' : ''}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0F172A)),
        ),
      ),
      const Divider(height: 1),
      SubmenuButton(
        menuChildren: [
          for (int i = 1; i <= portCount; i++) ...[
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  onPressed: () {
                    final err = viewModel.assignPortEdgeDirect(
                      portId: 'port$i',
                      isWidth: true,
                      p1: p1,
                      p2: p2,
                      measuredLengthMm: lenMm,
                    );
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('⚠️ $err'), backgroundColor: const Color(0xFFDC2626)),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Assigned Port $i Width (${lenMm.toStringAsFixed(1)} mm)'),
                          backgroundColor: const Color(0xFF0D9488),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  leadingIcon: const Icon(Icons.straighten, size: 16, color: Color(0xFF0284C7)),
                  child: const Text('Assign as Width (W) Edge'),
                ),
                MenuItemButton(
                  onPressed: () {
                    final err = viewModel.assignPortEdgeDirect(
                      portId: 'port$i',
                      isWidth: false,
                      p1: p1,
                      p2: p2,
                      measuredLengthMm: lenMm,
                    );
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('⚠️ $err'), backgroundColor: const Color(0xFFDC2626)),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Assigned Port $i Height Flap (${lenMm.toStringAsFixed(1)} mm)'),
                          backgroundColor: const Color(0xFF0D9488),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  leadingIcon: const Icon(Icons.border_top, size: 16, color: Color(0xFF0D9488)),
                  child: const Text('Assign as Height (H) Flap Edge'),
                ),
              ],
              child: Text(
                i == 1
                    ? 'Port 1 (Inlet)'
                    : (i == 2 ? 'Port 2 (Outlet)' : (i == 3 ? 'Port 3 (Branch)' : 'Port $i')),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
        leadingIcon: const Icon(Icons.input, size: 16, color: Color(0xFF0284C7)),
        child: const Text('Assign Port', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      if (assigned != null) ...[
        const Divider(height: 1),
        MenuItemButton(
          onPressed: () {
            viewModel.clearAssignedPortEdge(p1, p2);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Removed assignment from edge ($assigned)'), duration: const Duration(seconds: 2)),
            );
          },
          leadingIcon: const Icon(Icons.clear, size: 16, color: Color(0xFFEF4444)),
          child: Text('Clear Assignment ($assigned)', style: const TextStyle(color: Color(0xFFEF4444))),
        ),
      ],
      const Divider(height: 1),
      MenuItemButton(
        onPressed: () => viewModel.setFittingInspectorOpen(true),
        leadingIcon: const Icon(Icons.tune, size: 16, color: Color(0xFF64748B)),
        child: const Text('Fitting Inspector...'),
      ),
    ];
  }

  Widget _buildCompactLegend() {
    if (_isLegendCollapsed) {
      return InkWell(
        onTap: () => setState(() => _isLegendCollapsed = false),
        borderRadius: BorderRadius.circular(4),
        child: Tooltip(
          message: 'Layer Legend (Click to expand)',
          child: Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 3.5, height: 3.5, decoration: const BoxDecoration(color: Color(0xFF0F172A), shape: BoxShape.circle)),
                const SizedBox(width: 2.5),
                Container(width: 3.5, height: 3.5, decoration: const BoxDecoration(color: Color(0xFF0284C7), shape: BoxShape.circle)),
                const SizedBox(width: 2.5),
                Container(width: 3.5, height: 3.5, decoration: const BoxDecoration(color: Color(0xFFD97706), shape: BoxShape.circle)),
                const SizedBox(width: 2.5),
                Container(width: 3.5, height: 3.5, decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _microLegendItem('Cut', const Color(0xFF0F172A)),
          const SizedBox(width: 4),
          _microLegendItem('Up', const Color(0xFF0284C7)),
          const SizedBox(width: 4),
          _microLegendItem('Dn', const Color(0xFFD97706)),
          const SizedBox(width: 4),
          _microLegendItem('Hole', const Color(0xFF059669)),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => _isLegendCollapsed = true),
            borderRadius: BorderRadius.circular(2),
            child: const Tooltip(
              message: 'Collapse legend',
              child: Icon(Icons.close, size: 9.5, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _microLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3.5,
          height: 3.5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 7.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  Widget _toolButton({
    IconData? icon,
    Widget? customIcon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            customIcon ??
                Icon(
                  icon,
                  size: 13,
                  color: active
                      ? const Color(0xFF0284C7)
                      : const Color(0xFF475569),
                ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? const Color(0xFF0284C7)
                    : const Color(0xFF475569),
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<SnapType> _snapMenuItem(
    SnapType type,
    String title,
    bool enabled,
  ) {
    return PopupMenuItem<SnapType>(
      value: type,
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: enabled ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ===========================================================================
  // Set 4A: Parametric Template Editing & Scaling UX
  // ===========================================================================

  void _openPortDimensionEditor(String portBadgeId) {
    // Extract base port id (e.g. 'port1' from 'port1' or 'port1_h_0')
    final portId = portBadgeId.split('_').first;
    final meta = widget.viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(widget.viewModel.document) ??
        const DxfFittingMetadata();
    final ports = FittingPortAnnotationEngine.detectPortOpenings(
      document: widget.viewModel.document,
      metadata: meta,
    );
    final port = ports.where((p) => p.id == portId).firstOrNull;
    final semantic = meta.semanticPorts?[portId];

    final currentW = (semantic?['width'] as num?)?.toDouble() ??
        port?.widthMm ??
        widget.viewModel.document.parameters['width'] ??
        300.0;
    final currentHA = (semantic?['heightA'] as num?)?.toDouble() ??
        port?.heightAMm ??
        port?.heightMm ??
        widget.viewModel.document.parameters['heightA'] ??
        widget.viewModel.document.parameters['height'] ??
        50.0;
    final currentHB = (semantic?['heightB'] as num?)?.toDouble() ??
        port?.heightBMm ??
        port?.heightMm ??
        widget.viewModel.document.parameters['heightB'] ??
        widget.viewModel.document.parameters['height'] ??
        50.0;

    final badgeRect = _portBadgeRects[portBadgeId];
    Offset pos = const Offset(60, 100);
    if (badgeRect != null) {
      pos = Offset(badgeRect.center.dx - 140, badgeRect.bottom + 12);
    }

    setState(() {
      _activeEditingPortId = portId;
      _portEditWidth = currentW;
      _portEditHeightA = currentHA;
      _portEditHeightB = currentHB;
      _portHeightsLinked = (_portEditHeightA - _portEditHeightB).abs() < 1e-3;
      _portEditorScreenPos = pos;
      _portEditBaselineParams = Map<String, double>.from(widget.viewModel.document.parameters);
    });
  }

  ({String widthKey, String heightAKey, String heightBKey}) _resolveParamKeysForPort(
    String portId,
    DxfFittingMetadata? meta,
    Map<String, double> params,
  ) {
    final portNum = int.tryParse(portId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;

    String? wKey;
    String? haKey;
    String? hbKey;

    if (params.containsKey('port${portNum}Width')) {
      wKey = 'port${portNum}Width';
    }
    if (params.containsKey('port${portNum}HeightA')) {
      haKey = 'port${portNum}HeightA';
    }
    if (params.containsKey('port${portNum}HeightB')) {
      hbKey = 'port${portNum}HeightB';
    }

    if (wKey == null) {
      if (portNum == 1) {
        if (params.containsKey('widthIn')) {
          wKey = 'widthIn';
        } else if (params.containsKey('widthMain')) {
          wKey = 'widthMain';
        } else if (params.containsKey('width')) {
          wKey = 'width';
        }
      } else if (portNum == 2) {
        if (params.containsKey('widthOut')) {
          wKey = 'widthOut';
        } else if (params.containsKey('widthMain')) {
          wKey = 'widthMain';
        } else if (params.containsKey('width')) {
          wKey = 'width';
        }
      } else if (portNum == 3) {
        if (params.containsKey('branchWidth')) {
          wKey = 'branchWidth';
        } else if (params.containsKey('widthBranch')) {
          wKey = 'widthBranch';
        }
      } else if (portNum == 4) {
        if (params.containsKey('widthBranch')) {
          wKey = 'widthBranch';
        }
      }
      wKey ??= 'width';
    }

    if (haKey == null) {
      if (params.containsKey('heightA')) {
        haKey = 'heightA';
      } else if (params.containsKey('height')) {
        haKey = 'height';
      } else if (params.containsKey('port${portNum}Height')) {
        haKey = 'port${portNum}Height';
      } else {
        haKey = 'height';
      }
    }

    if (hbKey == null) {
      if (params.containsKey('heightB')) {
        hbKey = 'heightB';
      } else if (params.containsKey('height')) {
        hbKey = 'height';
      } else if (params.containsKey('port${portNum}Height')) {
        hbKey = 'port${portNum}Height';
      } else {
        hbKey = 'height';
      }
    }

    return (widthKey: wKey, heightAKey: haKey, heightBKey: hbKey);
  }

  void _updateLivePortDimension({double? newW, double? newHA, double? newHB}) {
    if (_activeEditingPortId == null) return;
    final meta = widget.viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(widget.viewModel.document);
    final keys = _resolveParamKeysForPort(
      _activeEditingPortId!,
      meta,
      widget.viewModel.document.parameters,
    );

    if (newW != null) {
      _portEditWidth = newW;
      widget.viewModel.updateTemplateParameter(keys.widthKey, newW);
    }
    if (newHA != null) {
      _portEditHeightA = newHA;
      widget.viewModel.updateTemplateParameter(keys.heightAKey, newHA);
      if (keys.heightAKey != 'height' && widget.viewModel.document.parameters.containsKey('height')) {
        widget.viewModel.updateTemplateParameter('height', newHA);
      }
      if (_portHeightsLinked) {
        _portEditHeightB = newHA;
        widget.viewModel.updateTemplateParameter(keys.heightBKey, newHA);
      }
    }
    if (newHB != null && !_portHeightsLinked) {
      _portEditHeightB = newHB;
      widget.viewModel.updateTemplateParameter(keys.heightBKey, newHB);
    }
    setState(() {});
  }

  void _applyPortDimensionEditor() {
    if (_activeEditingPortId == null) return;
    final meta = widget.viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(widget.viewModel.document) ??
        const DxfFittingMetadata();

    final existingSemantic = meta.semanticPorts?[_activeEditingPortId!] ?? {};
    final updatedSemantic = Map<String, dynamic>.from(existingSemantic)
      ..['width'] = _portEditWidth
      ..['heightA'] = _portEditHeightA
      ..['heightB'] = _portEditHeightB;

    final updatedMeta = meta.copyWith(
      semanticPorts: {
        ...?meta.semanticPorts,
        _activeEditingPortId!: updatedSemantic,
      },
    );
    widget.viewModel.updateFittingMetadata(updatedMeta);
    setState(() {
      _activeEditingPortId = null;
    });
  }

  void _cancelPortDimensionEditor() {
    if (_activeEditingPortId == null) return;
    for (final entry in _portEditBaselineParams.entries) {
      widget.viewModel.updateTemplateParameter(entry.key, entry.value);
    }
    setState(() {
      _activeEditingPortId = null;
    });
  }

  Widget _buildPortDimensionEditorCard(SheetMetalStudioViewModel viewModel) {
    if (_activeEditingPortId == null) return const SizedBox.shrink();
    final meta = viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(viewModel.document);
    final ports = FittingPortAnnotationEngine.detectPortOpenings(
      document: viewModel.document,
      metadata: meta,
    );
    final port = ports.where((p) => p.id == _activeEditingPortId).firstOrNull;
    final portTitle = port?.label ?? _activeEditingPortId!.toUpperCase();
    final sideName = port?.side.displayName ?? 'Port';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 280,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF0EA5E9), width: 1.6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title, Link/Unlock toggle, and Close
            Row(
              children: [
                const Icon(Icons.adjust, size: 16, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$portTitle ($sideName)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _portHeightsLinked = !_portHeightsLinked;
                      if (_portHeightsLinked) {
                        _updateLivePortDimension(newHB: _portEditHeightA);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: _portHeightsLinked
                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _portHeightsLinked
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        width: 0.9,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _portHeightsLinked ? Icons.link : Icons.link_off,
                          size: 13,
                          color: _portHeightsLinked
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _portHeightsLinked ? 'Linked' : 'Async',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _portHeightsLinked
                                ? const Color(0xFF34D399)
                                : const Color(0xFFFBBF24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _cancelPortDimensionEditor,
                  child: const Icon(Icons.close, size: 16, color: Colors.white54),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 14),

            // Dimension 1: Width
            _buildDimensionRow(
              label: 'Width (W)',
              value: _portEditWidth,
              step: 25.0,
              min: 50.0,
              max: 1200.0,
              accentColor: const Color(0xFF38BDF8),
              onChanged: (newVal) => _updateLivePortDimension(newW: newVal),
            ),
            const SizedBox(height: 8),

            // Dimension 2: Height A
            _buildDimensionRow(
              label: 'Height A (HA)',
              value: _portEditHeightA,
              step: 25.0,
              min: 25.0,
              max: 200.0,
              accentColor: const Color(0xFFF59E0B),
              onChanged: (newVal) => _updateLivePortDimension(newHA: newVal),
            ),
            const SizedBox(height: 8),

            // Dimension 3: Height B
            _buildDimensionRow(
              label: _portHeightsLinked ? 'Height B (HA 🔗)' : 'Height B (HB)',
              value: _portEditHeightB,
              step: 25.0,
              min: 25.0,
              max: 200.0,
              accentColor: const Color(0xFF8B5CF6),
              enabled: !_portHeightsLinked,
              onChanged: (newVal) => _updateLivePortDimension(newHB: newVal),
            ),
            const SizedBox(height: 12),

            // Action row: Apply (Enter) & Cancel (Esc)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _cancelPortDimensionEditor,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Cancel (Esc)', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _applyPortDimensionEditor,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Apply (Enter)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionRow({
    required String label,
    required double value,
    required double step,
    required double min,
    required double max,
    required Color accentColor,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: enabled ? 0.07 : 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: enabled ? Colors.white12 : Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? const Color(0xFFE2E8F0) : Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: enabled ? () {
              final next = (value - step).clamp(min, max);
              onChanged(next);
            } : null,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.remove, size: 13, color: enabled ? Colors.white70 : Colors.white24),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            constraints: const BoxConstraints(minWidth: 46),
            alignment: Alignment.center,
            child: Text(
              '${value.toStringAsFixed(0)} mm',
              style: TextStyle(
                color: enabled ? accentColor : Colors.white38,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: enabled ? () {
              final next = (value + step).clamp(min, max);
              onChanged(next);
            } : null,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.add, size: 13, color: enabled ? Colors.white70 : Colors.white24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhyDidThisMoveCard(SheetMetalStudioViewModel viewModel, BoxConstraints constraints) {
    final punchId = viewModel.selectedPunchId;
    if (punchId == null) return const SizedBox.shrink();
    final punch = viewModel.document.punches.where((p) => p.id == punchId).firstOrNull;
    if (punch == null) return const SizedBox.shrink();

    final meta = viewModel.detectedFittingMetadata ?? DxfFittingMetadata.fromDocument(viewModel.document);
    String associatedPortName = 'Fitting Zone';
    if (meta?.semanticPorts != null) {
      for (final entry in meta!.semanticPorts!.entries) {
        final featIds = (entry.value['associatedFeatureIds'] as List?)?.cast<String>() ?? [];
        if (featIds.contains(punchId)) {
          associatedPortName = entry.key.toUpperCase();
          break;
        }
      }
    }

    final sizeDesc = punch.widthMm > 0 && punch.lengthMm > 0
        ? '${punch.lengthMm.toStringAsFixed(0)} × ${punch.widthMm.toStringAsFixed(0)} mm slot'
        : (punch.diameterMm > 0 ? 'Ø${punch.diameterMm.toStringAsFixed(0)} mm hole' : punch.type.name);

    return Positioned(
      bottom: 50,
      left: 14,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 270,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.help_outline, size: 16, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Why did this move?',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('RIGID', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => viewModel.selectPunch(null),
                    child: const Icon(Icons.close, size: 14, color: Colors.white54),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 14),
              Text(
                'Selected: ${punch.id} ($associatedPortName)',
                style: const TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const SizedBox(height: 4),
              const Text(
                'Driven by:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600),
              ),
              Text(
                '• $associatedPortName Centerline Alignment\n• Flange Root Longitudinal Reference',
                style: const TextStyle(color: Colors.white70, fontSize: 10.5, height: 1.3),
              ),
              const SizedBox(height: 6),
              const Text(
                'Behavior:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600),
              ),
              Text(
                '✓ Tool size preserved ($sizeDesc)\n✓ Shape invariant (Zero ovalization)\n✓ Spatial position recalculated',
                style: const TextStyle(color: Color(0xFF34D399), fontSize: 10.5, height: 1.3, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
  });

  final String? selectedArcId;
  final String? hoveredArcId;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    renderedDimensionBadges?.clear();
    renderedDimensionLines?.clear();
    renderedPortBadges?.clear();
    renderedConstraintBadges?.clear();

    if (showGrid) {
      _drawGrid(canvas, size, pan);
    }

    final bw = doc.blankWidthMm > 0 ? doc.blankWidthMm : 200.0;
    final bl = doc.blankLengthMm > 0 ? doc.blankLengthMm : 300.0;

    final fitScale = math.min(
      (size.width * 0.75) / bw,
      (size.height * 0.75) / bl,
    );
    final scale = fitScale * zoom;

    final cx = size.width / 2.0 + pan.dx;
    final cy = size.height / 2.0 + pan.dy;

    final originX = cx - (bw / 2.0) * scale;
    final originY = cy - (bl / 2.0) * scale;

    Offset toScreen(double x, double y) =>
        Offset(originX + x * scale, originY + y * scale);

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
              : (face.id == doc.baseFaceId
                    ? const Color(0xFFD6E8F6).withValues(alpha: 0.75)
                    : const Color(0xFFE2EFF9).withValues(alpha: 0.70));
          canvas.drawPath(facePath, fillPaint);
        }
        canvas.drawPath(facePath, borderPaint);

        if (face.showLabel && face.isVisible && face.vertices.isNotEmpty) {
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
            final sCenter = toScreen(face.centroid.x, face.centroid.y);
            _drawFaceSizeBadge(
              canvas,
              sCenter,
              face.label.isNotEmpty ? face.label : face.id,
              fWidth,
              fHeight,
              face.id == selectedFaceId,
            );
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
    canvas.drawCircle(sOrigin, 3.5, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawCircle(sOrigin, 3.5, Paint()..color = const Color(0xFF64748B)..style = PaintingStyle.stroke..strokeWidth = 1.0);
    canvas.drawCircle(sOrigin, 1.5, Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.fill);

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

        pointFillPaint.color = isConstrained
            ? const Color(0xFF0F172A)
            : const Color(0xFF2563EB);
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
        final arcColor = isSelected
            ? const Color(0xFF2563EB)
            : (isHovered ? const Color(0xFF0EA5E9) : const Color(0xFF0F172A));

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

        if ((isHovered || isSelected) && arc.showLabel) {
          final midCad = arc.midpoint;
          final sMid = toScreen(midCad.x, midCad.y);
          _drawArcBadge(canvas, sMid, arc, isSelected);
        }
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
      final baMm = bend.calculateBendAllowance(
        sheetThicknessMm: doc.material.thicknessMm,
        kFactor: bend.kFactor ?? doc.material.kFactor,
      );
      final halfBaMm = baMm / 2.0;

      final bendLen = bend.p1.distanceTo(bend.p2);
      if (bendLen > 1e-4) {
        final nx = -(bend.p2.y - bend.p1.y) / bendLen;
        final ny = (bend.p2.x - bend.p1.x) / bendLen;

        final m1a = toScreen(
          bend.p1.x + nx * halfBaMm,
          bend.p1.y + ny * halfBaMm,
        );
        final m1b = toScreen(
          bend.p2.x + nx * halfBaMm,
          bend.p2.y + ny * halfBaMm,
        );
        final m2a = toScreen(
          bend.p1.x - nx * halfBaMm,
          bend.p1.y - ny * halfBaMm,
        );
        final m2b = toScreen(
          bend.p2.x - nx * halfBaMm,
          bend.p2.y - ny * halfBaMm,
        );

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
          canvas.drawRect(
            Rect.fromCenter(center: sp1, width: notchRadius * 2, height: notchRadius * 2),
            reliefPaint,
          );
          canvas.drawRect(
            Rect.fromCenter(center: sp2, width: notchRadius * 2, height: notchRadius * 2),
            reliefPaint,
          );
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
        final arrowStr = isUp ? '↑' : '↓';
        final lenStr = '${bend.length.toStringAsFixed(1)}mm';
        final String labelText;
        if (isIncomplete) {
          labelText = '⚠️ ${bend.id} OPEN · $lenStr';
        } else if (isFlange) {
          labelText = '${bend.id} [FLANGE] ${bend.targetAngleDeg.toStringAsFixed(0)}° $arrowStr · $lenStr';
        } else {
          labelText = '${bend.id} ${bend.targetAngleDeg.toStringAsFixed(0)}° $arrowStr · $lenStr';
        }

        final textColor = isIncomplete
            ? const Color(0xFFB45309)
            : (isFlange
                ? const Color(0xFF6D28D9)
                : (isUp ? const Color(0xFF0369A1) : const Color(0xFFB45309)));

        final textSpan = TextSpan(
          text: labelText,
          style: TextStyle(
            color: textColor,
            fontSize: 10.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        );
        final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
          ..layout();

        const iconSize = 11.0;
        const badgePaddingH = 7.0;
        final badgeWidth = iconSize + 4.0 + tp.width + (badgePaddingH * 2.0);
        const badgeHeight = 20.0;

        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: mid, width: badgeWidth, height: badgeHeight),
          const Radius.circular(4.5),
        );

        // 4a. Drop shadow
        canvas.drawRRect(
          badgeRect.shift(const Offset(0, 1.2)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.14)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
        );

        // 4b. High-contrast pill background (Occludes the dashed line completely)
        final badgeBg = Paint()
          ..color = isIncomplete
              ? const Color(0xFFFEF3C7)
              : (isSelected ? const Color(0xFFF0F9FF) : Colors.white.withValues(alpha: 0.96))
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
        tp.paint(
          canvas,
          Offset(iconLeft + iconSize + 4.0, mid.dy - tp.height / 2.0),
        );

        // 4f. Render CAM violation icon if detected
        final vResult = bendViolations?[bend.id];
        if (vResult != null && !vResult.isClean) {
          const camSpan = TextSpan(
            text: '⚠️',
            style: TextStyle(fontSize: 9.5),
          );
          final camTp = TextPainter(
            text: camSpan,
            textDirection: TextDirection.ltr,
          )..layout();
          camTp.paint(
            canvas,
            Offset(mid.dx + badgeWidth / 2.0 + 3, mid.dy - camTp.height / 2.0),
          );
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

          _drawDashedLine(
            canvas,
            midBend,
            leftEdgeScreen,
            dimLinePaint,
            dash: 4,
            gap: 3,
          );
          _drawDimText(
            canvas,
            Offset((midBend.dx + leftEdgeScreen.dx) / 2, midBend.dy - 12),
            'X: ${bend.midpoint.x.toStringAsFixed(1)} mm',
          );

          _drawDashedLine(
            canvas,
            midBend,
            bottomEdgeScreen,
            dimLinePaint,
            dash: 4,
            gap: 3,
          );
          _drawDimText(
            canvas,
            Offset(midBend.dx + 6, (midBend.dy + bottomEdgeScreen.dy) / 2),
            'Y: ${bend.midpoint.y.toStringAsFixed(1)} mm',
          );
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

    // 5. Render Turret Punches & Holes (Both Standalone and Perforation Pattern Holes)
    final unselectedPath = Path();
    bool hasUnselected = false;
    final activePunches = <CncPunchPrimitive>[];
    final allPunchesList = doc.allPunches;

    // For dense punch grids (> 25 holes), batch into single path for 60 FPS rendering
    final useBatching = allPunchesList.length > 25;
    Path? unselectedPunchesUnion;

    for (final punch in allPunchesList) {
      final isSelected = punch.id == selectedPunchId ||
          selectedEntityIds.contains(punch.id) ||
          selectedEntityIds.any((id) => punch.id.startsWith('${id}_'));
      final isHovered = punch.id == hoveredPunchId && !isSelected;
      if (isSelected || isHovered) {
        activePunches.add(punch);
      } else {
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

          if (useBatching) {
            unselectedPath.addPath(pPath, Offset.zero);
            hasUnselected = true;
          } else {
            unselectedPunchesUnion = (unselectedPunchesUnion == null)
                ? pPath
                : Path.combine(
                    PathOperation.union,
                    unselectedPunchesUnion,
                    pPath,
                  );
          }
        }
      }
    }

    if (useBatching) {
      if (hasUnselected) {
        canvas.drawPath(unselectedPath, holeFillPaint);
        canvas.drawPath(unselectedPath, holePaint);
      }
    } else {
      if (unselectedPunchesUnion != null) {
        canvas.drawPath(unselectedPunchesUnion, holeFillPaint);
        canvas.drawPath(unselectedPunchesUnion, holePaint);
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
      final isSelected = punch.id == selectedPunchId ||
          selectedEntityIds.contains(punch.id) ||
          selectedEntityIds.any((id) => punch.id.startsWith('${id}_'));
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
          canvas.drawPath(holePath, selectedFillPaint);
          canvas.drawPath(holePath, selectedHolePaint);

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
            _drawDashedLine(
              canvas,
              centerScreen,
              leftEdgeScreen,
              dimLinePaint,
              dash: 4,
              gap: 3,
            );
            _drawDimText(
              canvas,
              Offset(
                (centerScreen.dx + leftEdgeScreen.dx) / 2,
                centerScreen.dy - 12,
              ),
              'X: ${punch.center.x.toStringAsFixed(1)} mm',
            );

            // Dimension Y to Bottom Edge
            _drawDashedLine(
              canvas,
              centerScreen,
              bottomEdgeScreen,
              dimLinePaint,
              dash: 4,
              gap: 3,
            );
            _drawDimText(
              canvas,
              Offset(
                centerScreen.dx + 6,
                (centerScreen.dy + bottomEdgeScreen.dy) / 2,
              ),
              'Y: ${punch.center.y.toStringAsFixed(1)} mm',
            );
          }
        } else {
          canvas.drawPath(holePath, hoveredFillPaint);
          canvas.drawPath(holePath, hoveredHolePaint);
          final haloPaint = Paint()
            ..color = const Color(0xFF0284C7).withValues(alpha: 0.20)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawPath(holePath, haloPaint);
        }

        if (punch.showLabel && (isSelected || isHovered)) {
          final centerScreen = toScreen(punch.center.x, punch.center.y);
          final String sizeStr;
          if (punch.type == PunchType.roundHole) {
            sizeStr = 'Ø ${punch.diameterMm.toStringAsFixed(1)} mm';
          } else if (punch.type == PunchType.square) {
            sizeStr = '${punch.widthMm.toStringAsFixed(1)} × ${punch.widthMm.toStringAsFixed(1)} mm';
          } else {
            sizeStr = '${punch.widthMm.toStringAsFixed(1)} × ${punch.lengthMm.toStringAsFixed(1)} mm';
          }

          final pSpan = TextSpan(
            text: sizeStr,
            style: TextStyle(
              color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
              fontSize: 9.0,
              fontWeight: FontWeight.bold,
            ),
          );
          final pTp = TextPainter(text: pSpan, textDirection: TextDirection.ltr)..layout();
          final pBadgeRect = Rect.fromCenter(
            center: Offset(centerScreen.dx, centerScreen.dy - 16.0),
            width: pTp.width + 8.0,
            height: pTp.height + 4.0,
          );
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
      final ghostCenter = toScreen(
        rubberBandEndpoint!.x,
        rubberBandEndpoint!.y,
      );
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
        _drawDimText(
          canvas,
          Offset(ghostCenter.dx, ghostCenter.dy - r - 10),
          'Ø ${cfg.roundHoleDiameterMm.toStringAsFixed(1)} mm',
        );
      } else if (toolMode == StudioToolMode.addPunchObround) {
        final halfW = (cfg.obroundWidthMm / 2.0) * scale;
        final halfL = (cfg.obroundLengthMm / 2.0) * scale;
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: ghostCenter,
            width: halfW * 2.0,
            height: halfL * 2.0,
          ),
          Radius.circular(halfW),
        );
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
        final rect = Rect.fromCenter(
          center: ghostCenter,
          width: halfW * 2.0,
          height: halfH * 2.0,
        );
        canvas.drawRect(rect, ghostFill);
        canvas.drawRect(rect, ghostStroke);
        _drawDimText(
          canvas,
          Offset(ghostCenter.dx, ghostCenter.dy - halfH - 10),
          '□ ${w.toStringAsFixed(1)} × ${h.toStringAsFixed(1)} mm',
        );
      } else if (toolMode == StudioToolMode.perforationPattern &&
          previewPerforationPattern == null) {
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
          final rowOffset = (cfg.patternStaggered && row % 2 == 1)
              ? pitchX / 2.0
              : 0.0;
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
              final rect = Rect.fromCenter(
                center: Offset.zero,
                width: halfS * 2.0,
                height: halfS * 2.0,
              );
              canvas.drawRect(rect, ghostFill);
              canvas.drawRect(rect, ghostStroke);
            } else if (cfg.patternHoleType == PunchType.rectangle) {
              final halfW = (cfg.patternRectWidth / 2.0) * scale;
              final halfH = (cfg.patternRectHeight / 2.0) * scale;
              final rect = Rect.fromCenter(
                center: Offset.zero,
                width: halfW * 2.0,
                height: halfH * 2.0,
              );
              canvas.drawRect(rect, ghostFill);
              canvas.drawRect(rect, ghostStroke);
            } else {
              // Default: Obround slot
              final halfW = (cfg.patternSlotWidth / 2.0) * scale;
              final halfH = (cfg.patternSlotHeight / 2.0) * scale;
              final r = math.min(halfW, halfH);
              final rect = RRect.fromRectAndRadius(
                Rect.fromCenter(
                  center: Offset.zero,
                  width: halfW * 2.0,
                  height: halfH * 2.0,
                ),
                Radius.circular(r),
              );
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
        _drawDimText(
          canvas,
          Offset(ghostCenter.dx, ghostCenter.dy - 12),
          'Chamfer ${cfg.chamferDistanceMm.toStringAsFixed(1)} mm',
        );
      } else if (toolMode == StudioToolMode.addBend ||
          toolMode == StudioToolMode.addFlange) {
        final isFlange = toolMode == StudioToolMode.addFlange;
        final guideColor =
            isFlange ? const Color(0xFF8B5CF6) : const Color(0xFF0284C7);

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
          final dotPaint = Paint()..color = guideColor..style = PaintingStyle.fill;
          canvas.drawCircle(g1, 2.2, dotPaint);
          canvas.drawCircle(g2, 2.2, dotPaint);

          final prefix = isFlange ? 'FLANGE' : 'BEND';
          final lineMid = Offset((g1.dx + g2.dx) / 2.0, (g1.dy + g2.dy) / 2.0);

          // Calculate actual candidate feature dimension
          final candLen = autoCandidateLine!.p1.distanceTo(autoCandidateLine!.p2);
          double effDist = isFlange ? 10.0 : candLen;
          if (doc.outerContour.isNotEmpty) {
            double? minD;
            final cMid = CadPoint2D(
              (autoCandidateLine!.p1.x + autoCandidateLine!.p2.x) / 2.0,
              (autoCandidateLine!.p1.y + autoCandidateLine!.p2.y) / 2.0,
            );
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

          _drawDimText(
            canvas,
            Offset(lineMid.dx, lineMid.dy - 12),
            '⚡ AUTO $prefix ${effDist.toStringAsFixed(0)}mm (Click to place)',
          );
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
              final snapOffsets = isFlange
                  ? [10.0, 12.0, 13.0, 14.0, 15.0, 20.0, 25.0]
                  : [25.0, 50.0, 75.0, 100.0, 125.0, 150.0, 200.0];
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
              _drawDimText(
                canvas,
                Offset(ghostCenter.dx, ghostCenter.dy - 14),
                '$prefix GUIDE: ${effectiveDist.toStringAsFixed(1)} mm from Edge',
              );
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
          ..color = const Color(0xFF0D9488).withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        final couplerStroke = Paint()
          ..color = const Color(0xFF0D9488)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;

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
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        final tpRect =
            TextPainter(text: rectSpan, textDirection: TextDirection.ltr)
              ..layout();
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
          text:
              ' Ø ${(rMm * 2.0).toStringAsFixed(1)} mm (R ${rMm.toStringAsFixed(1)}) ',
          style: const TextStyle(
            color: Color(0xFF0284C7),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        final tpCircle =
            TextPainter(text: circleSpan, textDirection: TextDirection.ltr)
              ..layout();
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
          text:
              ' MOVE: ΔX=${dx.toStringAsFixed(1)} ΔY=${dy.toStringAsFixed(1)} mm ',
          style: const TextStyle(
            color: Color(0xFFE11D48),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        final tpMove =
            TextPainter(text: moveSpan, textDirection: TextDirection.ltr)
              ..layout();
        tpMove.paint(canvas, Offset(p2.dx + 10, p2.dy - 16));
      } else if (toolMode == StudioToolMode.modifyMirror) {
        final mirrorPaint = Paint()
          ..color = const Color(0xFF8B5CF6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        _drawDashedLine(canvas, p1, p2, mirrorPaint, dash: 6.0, gap: 4.0);
        final mirrorSpan = const TextSpan(
          text: ' MIRROR AXIS ',
          style: TextStyle(
            color: Color(0xFF8B5CF6),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        final tpMirror =
            TextPainter(text: mirrorSpan, textDirection: TextDirection.ltr)
              ..layout();
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
          style: const TextStyle(
            color: Color(0xFF0284C7),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        final tpDim = TextPainter(text: dimSpan, textDirection: TextDirection.ltr)..layout();

        // Place dimension text closer to the invisible drawn line, centered at midpoint
        final mid = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);
        final textBgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(mid.dx, mid.dy - tpDim.height / 2.0 - 4.0),
            width: tpDim.width + 8.0,
            height: tpDim.height + 3.0,
          ),
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
        final rubberColor = isCut
            ? const Color(0xFF0F172A)
            : (isFlange ? const Color(0xFF8B5CF6) : const Color(0xFF0284C7));
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
        final angleText =
            '$prefix ${angleDeg.abs()}° ${isAlt ? "(Alt Free)" : ""}';

        final angleSpan = TextSpan(
          text: ' $angleText ',
          style: TextStyle(
            color: rubberColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        final tpAngle = TextPainter(
          text: angleSpan,
          textDirection: TextDirection.ltr,
        )..layout();
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
          final sB =
              toScreen(pendingMultiPoints[i + 1].x, pendingMultiPoints[i + 1].y);
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
          final sCursor =
              toScreen(rubberBandEndpoint!.x, rubberBandEndpoint!.y);
          final rubberDashPaint = Paint()
            ..color = const Color(0xFF0284C7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
          _drawDashedLine(
              canvas, sLast, sCursor, rubberDashPaint, dash: 5.0, gap: 4.0);

          final segLen = lastPt.distanceTo(rubberBandEndpoint!);
          final dx = rubberBandEndpoint!.x - lastPt.x;
          final dy = rubberBandEndpoint!.y - lastPt.y;
          final angleDeg = (math.atan2(dy, dx) * 180.0 / math.pi).round();

          final isCloseSnap = pendingMultiPoints.length >= 2 &&
              (rubberBandEndpoint!.distanceTo(pendingMultiPoints.first) < 10.0 ||
                  (activeSnap != null &&
                      activeSnap!.point
                              .distanceTo(pendingMultiPoints.first) <
                          1.0));

          if (isCloseSnap) {
            // Draw close loop preview ring and badge
            final sFirst = toScreen(
                pendingMultiPoints.first.x, pendingMultiPoints.first.y);
            final closeRingPaint = Paint()
              ..color = const Color(0xFF10B981)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5;
            canvas.drawCircle(sFirst, 8.0, closeRingPaint);

            const closeSpan = TextSpan(
              text: ' ⮌ Close Polyline ➔ Cutout Void ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                backgroundColor: Color(0xFF059669),
              ),
            );
            final tpClose =
                TextPainter(text: closeSpan, textDirection: TextDirection.ltr)
                  ..layout();
            tpClose.paint(canvas, Offset(sCursor.dx + 12, sCursor.dy - 18));
          } else {
            final polySpan = TextSpan(
              text:
                  ' Polyline Pt ${pendingMultiPoints.length + 1}: ${segLen.toStringAsFixed(1)} mm | ∠ ${angleDeg.abs()}° ',
              style: const TextStyle(
                color: Color(0xFF0284C7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            );
            final tpPoly =
                TextPainter(text: polySpan, textDirection: TextDirection.ltr)
                  ..layout();
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
              sPt, 4.5, Paint()..color = Colors.white..style = PaintingStyle.fill);
          canvas.drawCircle(sPt, 4.5, arcPaint);
        }

        if (pendingMultiPoints.length == 1 && rubberBandEndpoint != null) {
          final p1 = pendingMultiPoints[0];
          final s1 = toScreen(p1.x, p1.y);
          final s2 = toScreen(rubberBandEndpoint!.x, rubberBandEndpoint!.y);
          _drawDashedLine(canvas, s1, s2, guidePaint, dash: 5.0, gap: 4.0);

          final chord = p1.distanceTo(rubberBandEndpoint!);
          final arcSpan = TextSpan(
            text:
                ' ARC Pt 2 (Through Point) | Chord: ${chord.toStringAsFixed(1)} mm ',
            style: const TextStyle(
              color: Color(0xFF0284C7),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          );
          final tpArc =
              TextPainter(text: arcSpan, textDirection: TextDirection.ltr)
                ..layout();
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
            final previewArc =
                CadArc2D.from3Points(id: 'preview_arc', p1: p1, p2: p2, p3: p3);
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
              style: const TextStyle(
                color: Color(0xFF0284C7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            );
            final tpArc =
                TextPainter(text: arcSpan, textDirection: TextDirection.ltr)
                  ..layout();
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
        final e1 = toScreen(
          activeSnap!.segmentStart!.x,
          activeSnap!.segmentStart!.y,
        );
        final e2 = toScreen(
          activeSnap!.segmentEnd!.x,
          activeSnap!.segmentEnd!.y,
        );
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
        final anchorPt = toScreen(
          activeSnap!.trackingAnchor!.x,
          activeSnap!.trackingAnchor!.y,
        );
        final trackingPaint = Paint()
          ..color = const Color(0xFF0284C7).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85;
        _drawDashedLine(
          canvas,
          anchorPt,
          snapPt,
          trackingPaint,
          dash: 4.0,
          gap: 3.0,
        );

        // Tracking anchor small dot
        canvas.drawCircle(
          anchorPt,
          1.8,
          Paint()..color = const Color(0xFF0284C7),
        );
      }

      // Draw specialized CAD snap glyph
      _drawSnapGlyph(canvas, snapPt, activeSnap!.type, activeSnap!.label);
    }

    // 8c. Pre-Click Cursor Snap Indicator Dot for all drawing tools
    final isDrawingTool = toolMode == StudioToolMode.addBend ||
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
      final effectiveScreen = hasSnap
          ? toScreen(activeSnap!.point.x, activeSnap!.point.y)
          : rawScreen;

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
            style: const TextStyle(
              color: Color(0xFFF97316),
              fontSize: 9.0,
              fontWeight: FontWeight.bold,
            ),
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

        _drawSelectionTag(
          canvas,
          rect.topLeft,
          'WINDOW (INSIDE)',
          const Color(0xFF2563EB),
        );
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

        _drawSelectionTag(
          canvas,
          rect.topRight,
          'CROSSING (TOUCHES)',
          const Color(0xFF10B981),
        );
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
              if (SheetMetalStudioViewModel.isSameCadEdge(hoveredContourEdgeP1!, hoveredContourEdgeP2!, CadPoint2D(p1List[0], p1List[1]), CadPoint2D(p2List[0], p2List[1]))) {
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
                  if (SheetMetalStudioViewModel.isSameCadEdge(hoveredContourEdgeP1!, hoveredContourEdgeP2!, CadPoint2D(p1List[0], p1List[1]), CadPoint2D(p2List[0], p2List[1]))) {
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.0,
          fontWeight: FontWeight.bold,
        ),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(hCenter.dx, hCenter.dy - 16.0),
          width: tp.width + 12,
          height: tp.height + 6,
        ),
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
        style: const TextStyle(
          color: Color(0xFF0284C7),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final tpAngle = TextPainter(
        text: angleSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tpAngle.paint(canvas, Offset(p.dx + 12, p.dy - 18));
    }

    // 12. Parametric Reference / Construction Geometry (Centerlines, Offsets, Symmetries)
    if (showConstructionGeometry && referenceGeometries.isNotEmpty) {
      CanvasReferencePainter.paint(
        canvas: canvas,
        size: size,
        references: referenceGeometries,
        cadToScreen: (pt) => toScreen(pt.x, pt.y),
      );
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

  void _drawCutBadge(
    Canvas canvas,
    Offset pos,
    String id,
    bool isSelected, {
    double? lengthMm,
    bool showLabel = true,
  }) {
    if (!showLabel) return;
    final label = lengthMm != null
        ? ' CUT $id ${lengthMm.toStringAsFixed(1)}mm '
        : ' CUT $id ';
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
      ..layout();
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

  void _drawFaceSizeBadge(
    Canvas canvas,
    Offset center,
    String label,
    double widthMm,
    double heightMm,
    bool isSelected,
  ) {
    final text = '$label: ${widthMm.toStringAsFixed(1)} × ${heightMm.toStringAsFixed(1)} mm';
    final span = TextSpan(
      text: text,
      style: TextStyle(
        color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF334155),
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    final badgeWidth = tp.width + 12.0;
    final badgeHeight = tp.height + 6.0;
    final badgeRect = Rect.fromCenter(
      center: center,
      width: badgeWidth,
      height: badgeHeight,
    );
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
      ..color = isSelected
          ? const Color(0xFFFEF3C7).withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = isSelected
          ? const Color(0xFFF59E0B)
          : const Color(0xFF94A3B8).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 1.4 : 0.8;
    canvas.drawRRect(rrect, borderPaint);

    tp.paint(
      canvas,
      Offset(badgeRect.left + 6.0, badgeRect.top + 3.0),
    );
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

  static ({double x, double y, double radius})? _circumcircle(
    CadPoint2D p1,
    CadPoint2D p2,
    CadPoint2D p3,
  ) {
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
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? majorGridPaint : gridPaint,
      );
    }
    for (double y = offsetY - step; y <= size.height + step; y += step) {
      final globalY = y - pan.dy;
      final isMajor = (globalY.round() % majorStep.round()).abs() < 1.0;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? majorGridPaint : gridPaint,
      );
    }
  }

  void _drawSnapGlyph(
    Canvas canvas,
    Offset snapPt,
    SnapType type,
    String label,
  ) {
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
      canvas.drawLine(
        Offset(snapPt.dx - 3.0, snapPt.dy - 3.0),
        Offset(snapPt.dx + 3.0, snapPt.dy + 3.0),
        strokePaint,
      );
      canvas.drawLine(
        Offset(snapPt.dx - 3.0, snapPt.dy + 3.0),
        Offset(snapPt.dx + 3.0, snapPt.dy - 3.0),
        strokePaint,
      );
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
      canvas.drawLine(
        Offset(snapPt.dx - 3.5, snapPt.dy - 2.5),
        Offset(snapPt.dx + 3.5, snapPt.dy - 2.5),
        strokePaint,
      );
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
      canvas.drawLine(
        Offset(snapPt.dx - 3.0, snapPt.dy),
        Offset(snapPt.dx + 3.0, snapPt.dy),
        strokePaint,
      );
      canvas.drawLine(
        Offset(snapPt.dx, snapPt.dy - 3.0),
        Offset(snapPt.dx, snapPt.dy + 3.0),
        strokePaint,
      );
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

    // Subtle snap label (minor typography)
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: const Color(0xFF0284C7),
        fontSize: 7.5,
        fontWeight: FontWeight.w600,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(snapPt.dx + 6, snapPt.dy - 11));
  }

  void _drawSelectionTag(
    Canvas canvas,
    Offset pos,
    String label,
    Color color,
  ) {
    final textSpan = TextSpan(
      text: ' $label ',
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(pos.dx + 4, pos.dy - 14));
  }

  void _drawDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    double dash = 6.0,
    double gap = 4.0,
  }) {
    _drawDashedLine(
      canvas,
      rect.topLeft,
      rect.topRight,
      paint,
      dash: dash,
      gap: gap,
    );
    _drawDashedLine(
      canvas,
      rect.topRight,
      rect.bottomRight,
      paint,
      dash: dash,
      gap: gap,
    );
    _drawDashedLine(
      canvas,
      rect.bottomRight,
      rect.bottomLeft,
      paint,
      dash: dash,
      gap: gap,
    );
    _drawDashedLine(
      canvas,
      rect.bottomLeft,
      rect.topLeft,
      paint,
      dash: dash,
      gap: gap,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dash = 6.0,
    double gap = 4.0,
  }) {
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
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0xFFD97706),
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2.0, pos.dy - tp.height / 2.0));
  }

  // --- Engineering CAD Outside Dimensions & Hole Leaders (Matching SS1) ---

  void _drawOutsideDimensions(
    Canvas canvas,
    DsfDocument doc,
    Offset Function(double x, double y) toScreen,
    double scale,
  ) {
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
      valueText: blankW.toStringAsFixed(2),
      dimId: 'dim_blank_w',
      ptA: CadPoint2D(minX, minY),
      ptB: CadPoint2D(maxX, minY),
      scale: scale,
    );

    // Key intermediate X coordinates from vertical bends or notches
    final xBends = doc.bends
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
            valueText: stepW.toStringAsFixed(2),
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
          valueText: remW.toStringAsFixed(2),
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
      valueText: blankL.toStringAsFixed(2),
      dimId: 'dim_blank_l',
      ptA: CadPoint2D(minX, minY),
      ptB: CadPoint2D(minX, maxY),
      scale: scale,
    );

    // Key intermediate Y coordinates from horizontal bends or notches
    final yBends = doc.bends
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
            valueText: stepH.toStringAsFixed(2),
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
          valueText: remH.toStringAsFixed(2),
          dimId: 'dim_step_y_$stepIdx',
          ptA: CadPoint2D(minX, curY),
          ptB: CadPoint2D(minX, maxY),
          scale: scale,
        );
      }
    }

    // --- RIGHT DIMENSION CHAIN (Hole centers & feature spacing) ---
    // Parametric patterns: dimensions shown for ONLY 1 SET (first pitch interval) + margins
    final punchesWithUniqueY =
        doc.allPunches.map((p) => p.center.y).toSet().toList()..sort();
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
          valueText: bottomMargin.toStringAsFixed(2),
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
          valueText: dy.toStringAsFixed(2),
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
          valueText: topMargin.toStringAsFixed(2),
          dimId: 'dim_punch_margin_top',
          ptA: CadPoint2D(maxX, lastY),
          ptB: CadPoint2D(maxX, maxY),
          scale: scale,
        );
      }
    }

    // --- HOLE LEADER CALLOUTS (e.g. "8 * Ø5.00", "6 * Ø20.00" as in SS1) ---
    _drawHoleLeaderCallouts(canvas, doc, toScreen, scale);

    // --- ASSOCIATIVE CAD DIMENSIONS (Step 6 #19 & Step 7 #20) ---
    _drawAssociativeDimensions(canvas, doc, toScreen, scale);

    // --- GEOMETRIC CONSTRAINTS GLYPHS (Step 8 #21) ---
    _drawGeometricConstraints(canvas, doc, toScreen, scale);
  }

  void _drawAssociativeDimensions(
    Canvas canvas,
    DsfDocument doc,
    Offset Function(double x, double y) toScreen,
    double scale,
  ) {
    if (doc.dimensions.isEmpty) return;

    for (final dim in doc.dimensions) {
      if (!dim.isVisible) continue;

      final layout = AssociativeDimensionEngine.resolveLayout(dim, doc, scale: scale);
      final pA = toScreen(layout.dimLineStart.dx, layout.dimLineStart.dy);
      final pB = toScreen(layout.dimLineEnd.dx, layout.dimLineEnd.dy);
      final wA1 = toScreen(layout.witnessAStart.dx, layout.witnessAStart.dy);
      final wA2 = toScreen(layout.witnessAEnd.dx, layout.witnessAEnd.dy);
      final wB1 = toScreen(layout.witnessBStart.dx, layout.witnessBStart.dy);
      final wB2 = toScreen(layout.witnessBEnd.dx, layout.witnessBEnd.dy);
      final textPos = toScreen(layout.textCenter.dx, layout.textCenter.dy);

      final assoc = AssociativeDimensionEngine.resolveAssociation(dim, doc);
      if (renderedDimensionLines != null) {
        renderedDimensionLines![dim.id] = (
          pA: pA,
          pB: pB,
          offsetDist: dim.dimensionLineOffset,
          ptA: assoc.pA,
          ptB: assoc.pB,
          type: dim.type,
        );
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
      final userOffset = (dimensionOffsets.containsKey(dim.id))
          ? dimensionOffsets[dim.id]!
          : Offset.zero;
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

      final badgeRect = _drawDimBadge(canvas, effectiveCenter, layout.displayText);
      if (renderedDimensionBadges != null) {
        renderedDimensionBadges![dim.id] = badgeRect;
      }
    }
  }

  void _drawGeometricConstraints(
    Canvas canvas,
    DsfDocument doc,
    Offset Function(double x, double y) toScreen,
    double scale,
  ) {
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
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: badgeCenter, width: 18, height: 16),
        const Radius.circular(3),
      );

      canvas.drawRRect(rrect, badgePaint);
      canvas.drawRRect(rrect, borderPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: c.symbol,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF0F172A),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        badgeCenter - Offset(textPainter.width / 2, textPainter.height / 2),
      );
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
    final sign = isVertical
        ? ((dimScreenCoord >= p1Screen.dx) ? 1.0 : -1.0)
        : ((dimScreenCoord >= p1Screen.dy) ? 1.0 : -1.0);

    final geomCoord = isVertical ? p1Screen.dx : p1Screen.dy;
    final initialOffsetMm = (dimScreenCoord - geomCoord).abs() / (scale ?? 1.0);
    final userLineOffsetMm = (dimId != null && dimensionLineOffsets.containsKey(dimId))
        ? dimensionLineOffsets[dimId]!
        : initialOffsetMm;

    final effectiveDimCoord = (scale != null)
        ? geomCoord + sign * (userLineOffsetMm * scale)
        : dimScreenCoord;

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
      ..color = const Color(0xFF64748B) // Slate witness line
      ..strokeWidth = 0.8;

    final dimLinePaint = Paint()
      ..color = isLineHovered ? const Color(0xFF0284C7) : const Color(0xFF475569) // Dimension line
      ..strokeWidth = isLineHovered ? 2.0 : 1.0;

    const extPast = 5.0; // Extension past dimension line
    const gapFromPart = 3.0; // Small gap from part geometry

    final Offset defaultMid;

    final textSpanVal = TextSpan(
      text: valueText,
      style: const TextStyle(
        color: Color(0xFF1E293B),
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
      ),
    );
    final tpVal = TextPainter(text: textSpanVal, textDirection: TextDirection.ltr)..layout();
    final halfTextW = tpVal.width / 2.0 + 3.0;
    final halfTextH = tpVal.height / 2.0 + 2.0;

    final userOffset = (dimId != null && dimensionOffsets.containsKey(dimId))
        ? dimensionOffsets[dimId]!
        : Offset.zero;

    if (!isVertical) {
      // Horizontal dimension line at Y = effectiveDimCoord
      final startY = p1Screen.dy + sign * gapFromPart;
      final endY = effectiveDimCoord + sign * extPast;

      // Witness lines
      canvas.drawLine(
        Offset(p1Screen.dx, startY),
        Offset(p1Screen.dx, endY),
        witnessPaint,
      );
      canvas.drawLine(
        Offset(p2Screen.dx, startY),
        Offset(p2Screen.dx, endY),
        witnessPaint,
      );

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
        canvas.drawLine(
          Offset(leftX, effectiveDimCoord),
          Offset(midX - halfTextW, effectiveDimCoord),
          dimLinePaint,
        );
        canvas.drawLine(
          Offset(midX + halfTextW, effectiveDimCoord),
          Offset(rightX, effectiveDimCoord),
          dimLinePaint,
        );
      } else {
        canvas.drawLine(
          pA,
          pB,
          dimLinePaint,
        );
      }

      // Arrowheads pointing towards witness lines
      _drawArrow(canvas, Offset(p1Screen.dx, effectiveDimCoord), 0.0);
      _drawArrow(canvas, Offset(p2Screen.dx, effectiveDimCoord), math.pi);
    } else {
      // Vertical dimension line at X = effectiveDimCoord
      final startX = p1Screen.dx + sign * gapFromPart;
      final endX = effectiveDimCoord + sign * extPast;

      // Witness lines
      canvas.drawLine(
        Offset(startX, p1Screen.dy),
        Offset(endX, p1Screen.dy),
        witnessPaint,
      );
      canvas.drawLine(
        Offset(startX, p2Screen.dy),
        Offset(endX, p2Screen.dy),
        witnessPaint,
      );

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
        canvas.drawLine(
          Offset(effectiveDimCoord, topY),
          Offset(effectiveDimCoord, midY - halfTextH),
          dimLinePaint,
        );
        canvas.drawLine(
          Offset(effectiveDimCoord, midY + halfTextH),
          Offset(effectiveDimCoord, botY),
          dimLinePaint,
        );
      } else {
        canvas.drawLine(
          pA,
          pB,
          dimLinePaint,
        );
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

    final badgeRect = _drawDimBadge(canvas, effectiveCenter, valueText);
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
      tip.dx -
          arrowLength * math.cos(angleRad) -
          arrowHalfWidth * math.sin(angleRad),
      tip.dy -
          arrowLength * math.sin(angleRad) +
          arrowHalfWidth * math.cos(angleRad),
    );
    path.lineTo(
      tip.dx -
          arrowLength * math.cos(angleRad) +
          arrowHalfWidth * math.sin(angleRad),
      tip.dy -
          arrowLength * math.sin(angleRad) -
          arrowHalfWidth * math.cos(angleRad),
    );
    path.close();
    canvas.drawPath(path, arrowPaint);
  }

  Rect _drawDimBadge(Canvas canvas, Offset center, String text) {
    final span = TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0xFF1E293B),
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
      ),
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();

    final bgRect = Rect.fromCenter(
      center: center,
      width: tp.width + 4,
      height: tp.height + 2,
    );

    // Transparent background per CAD sketch drafting style
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0),
    );
    return bgRect;
  }

  void _drawHoleCrosshairs(
    Canvas canvas,
    DsfDocument doc,
    Offset Function(double x, double y) toScreen,
    double scale,
  ) {
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
        canvas.drawLine(
          Offset(sc.dx - armLen, sc.dy),
          Offset(sc.dx + armLen, sc.dy),
          crossPaint,
        );
        // Vertical crosshair arm
        canvas.drawLine(
          Offset(sc.dx, sc.dy - armLen),
          Offset(sc.dx, sc.dy + armLen),
          crossPaint,
        );
      } else if (punch.type == PunchType.ellipse) {
        final sc = toScreen(punch.center.x, punch.center.y);
        final maxR = math.max(punch.lengthMm, punch.widthMm) / 2.0;
        final armLen = maxR * scale + 4.0;

        canvas.drawLine(
          Offset(sc.dx - armLen, sc.dy),
          Offset(sc.dx + armLen, sc.dy),
          crossPaint,
        );
        canvas.drawLine(
          Offset(sc.dx, sc.dy - armLen),
          Offset(sc.dx, sc.dy + armLen),
          crossPaint,
        );
      }
    }
  }

  void _drawHoleLeaderCallouts(
    Canvas canvas,
    DsfDocument doc,
    Offset Function(double x, double y) toScreen,
    double scale,
  ) {
    final roundPunches = doc.allPunches
        .where((p) => p.type == PunchType.roundHole && p.diameterMm > 0)
        .toList();
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
      final label = (count > 1)
          ? '$count * Ø${diam.toStringAsFixed(2)}'
          : 'Ø${diam.toStringAsFixed(2)}';

      // Pick top-right-most punch in this group
      list.sort(
        (a, b) => (b.center.x + b.center.y).compareTo(a.center.x + a.center.y),
      );
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
      canvas.drawLine(
        Offset(elbowX, elbowY),
        Offset(shoulderEndX, elbowY),
        leaderPaint,
      );

      // Arrow pointing at hole rim
      _drawArrow(canvas, Offset(rimX, rimY), leaderAngle + math.pi);

      // Text callout badge
      final span = TextSpan(
        text: ' $label ',
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
        ),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(shoulderEndX + 2, elbowY - tp.height / 2.0));

      calloutIdx++;
    }
  }

  void _drawPortOpeningBadges(
    Canvas canvas,
    DsfDocument doc,
    Offset Function(double x, double y) toScreen,
    double scale,
  ) {
    final meta = fittingMetadata;
    if (meta == null) return;

    final openings = meta.getPortOpenings(doc, onlyAssigned: true);
    if (openings.isEmpty) return;

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
      final Offset normalDir = dirLen > 1e-4
          ? Offset(rawDir.dx / dirLen, rawDir.dy / dirLen)
          : const Offset(0, -1);

      // Leader offset length: 30 pixels out from opening edge
      const leaderLen = 30.0;
      final badgeAnchor = sCenter + normalDir * leaderLen;

      // Draw inward-pointing arrow at opening edge pointing into channel
      _drawArrow(canvas, sCenter, math.atan2(-normalDir.dy, -normalDir.dx));

      // 3. Render translucent CAD badge pill for opening Width (W)
      final sideLabel = port.side.displayName;
      final labelText = '${port.label}  [$sideLabel]';
      final wValStr = (port.widthMm % 1 == 0) ? port.widthMm.toInt().toString() : port.widthMm.toStringAsFixed(1);
      final dimText = 'W: $wValStr mm';

      final titleSpan = TextSpan(
        children: [
          TextSpan(
            text: '$labelText  ',
            style: TextStyle(
              color: portColor.withValues(alpha: 0.95),
              fontSize: 9.0,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const TextSpan(
            text: '[Edit ✎]',
            style: TextStyle(
              color: Color(0xFF38BDF8),
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
      final tpTitle = TextPainter(text: titleSpan, textDirection: TextDirection.ltr)..layout();

      final dimSpan = TextSpan(
        text: dimText,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
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
      canvas.drawRRect(
        rrect,
        Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.62),
      );

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
                    style: TextStyle(
                      color: portColor.withValues(alpha: 0.95),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(
                    text: '[Edit ✎]',
                    style: TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 8.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
              final tpHTitle = TextPainter(text: hTitleSpan, textDirection: TextDirection.ltr)..layout();

              final hDimSpan = TextSpan(
                text: hDimText,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                ),
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
              canvas.drawRRect(
                hRRect,
                Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.62),
              );
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
    final label = 'Arc: R=${arc.radius.toStringAsFixed(1)} mm • L=${arc.arcLength.toStringAsFixed(1)} mm';
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF0F172A),
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = Rect.fromCenter(
      center: screenPos + const Offset(0, -18),
      width: textPainter.width + 12.0,
      height: textPainter.height + 6.0,
    );

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
    textPainter.paint(
      canvas,
      Offset(badgeRect.left + 6.0, badgeRect.top + 3.0),
    );
  }

  void _paintSemanticPortPreview(
    Canvas canvas,
    Size size,
    Offset Function(double x, double y) toScreen,
    double scale,
  ) {
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
    _paintDimensionBadge(
      canvas,
      edgeMid,
      'W: ${res.inferredWidth.toStringAsFixed(1)} mm',
      const Color(0xFF0891B2),
      const Offset(0, -20),
    );

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
      final aMid = toScreen(
        (firstSeg.p1.x + firstSeg.p2.x) / 2.0,
        (firstSeg.p1.y + firstSeg.p2.y) / 2.0,
      );
      _paintDimensionBadge(
        canvas,
        aMid,
        'HA: ${res.inferredHeightA.toStringAsFixed(1)} mm',
        const Color(0xFFD97706),
        const Offset(0, -18),
      );
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
      final bMid = toScreen(
        (firstSeg.p1.x + firstSeg.p2.x) / 2.0,
        (firstSeg.p1.y + firstSeg.p2.y) / 2.0,
      );
      _paintDimensionBadge(
        canvas,
        bMid,
        'HB: ${res.inferredHeightB.toStringAsFixed(1)} mm',
        const Color(0xFF7C3AED),
        const Offset(0, -18),
      );
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

  void _paintDimensionBadge(
    Canvas canvas,
    Offset pos,
    String text,
    Color color,
    Offset offset,
  ) {
    final textSpan = TextSpan(
      text: ' $text ',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10.0,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.2,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
    final center = pos + offset;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: tp.width + 8.0, height: tp.height + 4.0),
      const Radius.circular(4.0),
    );
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(rrect.shift(const Offset(0, 1)), shadowPaint);
    canvas.drawRRect(rrect, Paint()..color = color);
    tp.paint(canvas, Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0));
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
        oldDelegate.isAltPressed != isAltPressed;
  }
}
