// =============================================================================
// dds_paper_canvas.dart
//
// Technical Data Sheet (TDS) Paper Canvas & ISO 7200 Presentation Renderer.
// Renders standard ISO 5457 / ISO 7200 compliant A4/A3 engineering submittal sheets.
//
// Features:
// 1. Two distinct sheet formats:
//    - Cover Schedule Sheet: Submittal transmittal, project control grid,
//      complete Product Schedule table (from Excel / DDS instances), and
//      client approval sign-off stamps.
//    - Product Sheet: Split viewports with 2D dimensioned flat pattern and
//      3D isometric preview (base + live exploded/snapped cover), key dimensions,
//      and docked ISO 7200 title block.
// 2. Interactive paper container with zoom/pan and crisp physical borders.
// 3. Interactive Markup & Annotation Overlay:
//    - Linear dimensions with CAD arrows and witness lines.
//    - Leader notes pointing to features with callouts.
//    - Note boxes, revision clouds with Δ1 tags, and approval stamps.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../models/cad_primitives.dart';
import '../../../models/cnc_punch_primitive.dart';
import '../../../models/dsf_document.dart';
import '../../../models/dds/dds_annotation.dart';
import '../../../models/dds/dds_document.dart';
import '../../../models/dds/dds_product_instance.dart';
import '../../../models/dds/dds_sheet.dart';
import '../../../models/fold_bend_line.dart';
import '../../../models/planar_sheet_face.dart';
import '../../../engine/dds/dds_instance_evaluator.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../viewport_3d/flutter_scene_viewport_widget.dart';
import 'dds_drawing_painters.dart';

enum DdsViewportMode { presentation3D, transitionWipe }

class DdsPaperCanvas extends StatefulWidget {
  final DdsDocument document;
  final DdsSheet sheet;
  final EvaluatedDdsInstance? evaluatedInstance;
  final SheetMetalStudioViewModel? viewModel;
  final DdsMarkupTool activeMarkupTool;
  final String? selectedAnnotationId;
  final void Function(List<DdsAnnotation> updatedAnnotations)? onAnnotationsChanged;
  final void Function(String? annotationId)? onAnnotationSelected;
  final VoidCallback? onNextSheet;
  final VoidCallback? onPrevSheet;
  final VoidCallback? onDeleteSheet;
  final bool? showDimWidth;
  final bool? showDimHeight;
  final bool? showDimPorts;
  final bool? showDimSlots;
  final bool? showDimFlange;
  final bool? showDimThickness;
  final void Function(String dim, bool visible)? onDimensionToggled;
  final ValueChanged<DdsViewSettings>? onViewSettingsChanged;
  final ValueChanged<DdsProjectInfo>? onProjectInfoChanged;

  const DdsPaperCanvas({
    super.key,
    required this.document,
    required this.sheet,
    this.evaluatedInstance,
    this.viewModel,
    this.activeMarkupTool = DdsMarkupTool.select,
    this.selectedAnnotationId,
    this.onAnnotationsChanged,
    this.onAnnotationSelected,
    this.onNextSheet,
    this.onPrevSheet,
    this.onDeleteSheet,
    this.showDimWidth,
    this.showDimHeight,
    this.showDimPorts,
    this.showDimSlots,
    this.showDimFlange,
    this.showDimThickness,
    this.onDimensionToggled,
    this.onViewSettingsChanged,
    this.onProjectInfoChanged,
  });

  @override
  State<DdsPaperCanvas> createState() => _DdsPaperCanvasState();
}

enum _AnnotationDragMode {
  none,
  move,
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  targetPoint,
  textPosition,
  dimP1,
  dimP2,

  /// Dragging a pull-out arrow tip on a DdsNoteBoxAnnotation.
  arrowTip,

  /// Dragging a pull-out arrow root (attachment on note-box border).
  arrowRoot,
}

/// Computes the nearest point on the rectangle perimeter of [ann] to [pt].
CadPoint2D _getNearestBorderPoint(CadPoint2D pt, DdsNoteBoxAnnotation ann) {
  final rx = ann.x;
  final ry = ann.y;
  final rw = ann.width;
  final rh = ann.height;

  final cx = pt.x.clamp(rx, rx + rw);
  final cy = pt.y.clamp(ry, ry + rh);

  final distLeft = (pt.x - rx).abs();
  final distRight = (pt.x - (rx + rw)).abs();
  final distTop = (pt.y - ry).abs();
  final distBottom = (pt.y - (ry + rh)).abs();

  final minDist = math.min(math.min(distLeft, distRight), math.min(distTop, distBottom));

  if (minDist == distLeft) return CadPoint2D(rx, cy);
  if (minDist == distRight) return CadPoint2D(rx + rw, cy);
  if (minDist == distTop) return CadPoint2D(cx, ry);
  return CadPoint2D(cx, ry + rh);
}

class _DdsPaperCanvasState extends State<DdsPaperCanvas> with TickerProviderStateMixin {
  // Dedicated fitting ViewModel for this sheet's specific evaluated model (Reducer, Cross, Bend, Tee)
  SheetMetalStudioViewModel? _sheetViewModel;
  String? _activeLoadedInstanceId;
  Timer? _viewSettingsPersistTimer;
  int? _lastObservedMeshHash;
  bool? _lastObservedCoverVisible;

  // Temporary interactive drawing state
  CadPoint2D? _pendingStartPoint;
  CadPoint2D? _currentHoverPoint;
  final List<CadPoint2D> _pendingCloudPoints = [];

  // Dragging & Resizing annotations state
  bool _isDraggingAnnotation = false;
  String? _draggedAnnotationId;
  CadPoint2D? _dragLastPointMm;
  _AnnotationDragMode _activeDragMode = _AnnotationDragMode.none;
  _AnnotationDragMode _activeHoverMode = _AnnotationDragMode.none;

  /// Arrow drag: id of the DdsNoteArrow being dragged (on a note box).
  String? _draggingArrowId;

  /// Currently selected arrow id on the active note box (for deletion and highlight).
  String? _selectedArrowId;

  // Hit test radius in sheet mm
  static const double _hitTestRadiusMm = 8.0;
  static const double _handleRadiusMm = 6.0;

  // Focus node to capture Delete key and shortcuts whenever canvas is clicked
  final FocusNode _canvasFocusNode = FocusNode();

  // 3D Model rotation & movement lock state
  bool _is3DModelLocked = false;

  // Viewport mode and 3D technical presentation parameters
  DdsViewportMode _viewportMode = DdsViewportMode.presentation3D;
  double _transitionProgress = 0.50; // 0.0 to 1.0 (sweep divider line)
  bool _showHatching = true;
  bool _isAutoSweeping = false;
  late AnimationController _sweepController;

  // 3D Presentation Dimension Annotations & Companion Model Toggle State
  bool _showCover3D = true;
  bool _showFasteners3D = false;
  bool _showDimWidth = true;
  bool _showDimHeight = true;
  bool _showDimPorts = true;
  bool _showDimSlots = true;
  bool _showDimFlange = true;
  bool _showDimThickness = true;
  bool _showCadDimensionLines = true;
  bool _showDimensionTags = false;
  bool _combinePortDimensions = true;

  void _onSheetVmChanged() {
    if (!mounted) return;
    final currentMeshHash = _sheetViewModel?.currentMesh.hashCode;
    final currentCover = _sheetViewModel?.isCoverVisible3D;
    final needsCanvasRebuild = currentMeshHash != _lastObservedMeshHash || currentCover != _lastObservedCoverVisible;
    _lastObservedMeshHash = currentMeshHash;
    _lastObservedCoverVisible = currentCover;

    // Debounce view settings persistence to prevent root application rebuild storm on continuous camera drag
    _persistSheetViewSettings(immediate: false);

    if (needsCanvasRebuild) {
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else {
        setState(() {});
      }
    }
  }

  void _restoreFromSheetViewSettings() {
    final vs = widget.sheet.viewSettings;
    _showCover3D = vs.showCover3D;
    _showFasteners3D = vs.showFasteners3D;
    _showDimWidth = widget.showDimWidth ?? vs.showDimWidth;
    _showDimHeight = widget.showDimHeight ?? vs.showDimHeight;
    _showDimPorts = widget.showDimPorts ?? vs.showDimPorts;
    _showDimSlots = widget.showDimSlots ?? vs.showDimSlots;
    _showDimFlange = widget.showDimFlange ?? vs.showDimFlange;
    _showDimThickness = widget.showDimThickness ?? vs.showDimThickness;
    _showCadDimensionLines = vs.showCadDimensionLines;
    _showDimensionTags = vs.showDimensionTags;
    _combinePortDimensions = vs.combinePortDimensions;
    _is3DModelLocked = vs.is3DModelLocked;

    if (_sheetViewModel != null) {
      if (_sheetViewModel!.isCoverVisible3D != vs.showCover3D) {
        _sheetViewModel!.toggleCoverVisibility3D();
      }
      _sheetViewModel!.azimuthDeg = vs.camera3D.azimuthDeg;
      _sheetViewModel!.elevationDeg = vs.camera3D.elevationDeg;
      _sheetViewModel!.cameraZoom = vs.camera3D.zoom;
      _sheetViewModel!.pan3D = Offset(vs.camera3D.panOffset.x, vs.camera3D.panOffset.y);
      _sheetViewModel!.showCmsPortHighlights = _showDimPorts;
    }
  }

  void _persistSheetViewSettings({bool immediate = true}) {
    if (!mounted) return;
    if (immediate) {
      _viewSettingsPersistTimer?.cancel();
      _doPersistSheetViewSettings();
    } else {
      _viewSettingsPersistTimer?.cancel();
      _viewSettingsPersistTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _doPersistSheetViewSettings();
        }
      });
    }
  }

  void _doPersistSheetViewSettings() {
    if (!mounted) return;
    final cam = _sheetViewModel != null
        ? DdsCamera3DSettings(
            elevationDeg: _sheetViewModel!.elevationDeg,
            azimuthDeg: _sheetViewModel!.azimuthDeg,
            zoom: _sheetViewModel!.cameraZoom,
            panOffset: CadPoint2D(_sheetViewModel!.pan3D.dx, _sheetViewModel!.pan3D.dy),
          )
        : widget.sheet.viewSettings.camera3D;

    final updated = widget.sheet.viewSettings.copyWith(
      showCover3D: _sheetViewModel?.isCoverVisible3D ?? _showCover3D,
      showFasteners3D: _showFasteners3D,
      showDimWidth: _showDimWidth,
      showDimHeight: _showDimHeight,
      showDimPorts: _showDimPorts,
      showDimSlots: _showDimSlots,
      showDimFlange: _showDimFlange,
      showDimThickness: _showDimThickness,
      showCadDimensionLines: _showCadDimensionLines,
      showDimensionTags: _showDimensionTags,
      combinePortDimensions: _combinePortDimensions,
      is3DModelLocked: _is3DModelLocked,
      camera3D: cam,
    );

    if (updated != widget.sheet.viewSettings) {
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onViewSettingsChanged?.call(updated);
        });
      } else {
        widget.onViewSettingsChanged?.call(updated);
      }
    }
  }

  void _syncSheetViewModel() {
    final eval = widget.evaluatedInstance;
    if (eval != null) {
      var doc = eval.scaledBaseDocument;
      if (eval.coverData != null) {
        doc = doc.copyWith(cover: eval.coverData);
      }
      final newInstId = eval.instance.instanceId;
      if (_activeLoadedInstanceId == newInstId && _sheetViewModel != null) {
        _sheetViewModel!.loadDocument(doc);
        final vs = widget.sheet.viewSettings;
        if (_sheetViewModel!.isCoverVisible3D != vs.showCover3D) {
          _sheetViewModel!.toggleCoverVisibility3D();
        }
        _sheetViewModel!.showCmsPortHighlights = _showDimPorts;
        return;
      }
      _sheetViewModel?.removeListener(_onSheetVmChanged);
      _sheetViewModel?.dispose();
      _sheetViewModel = SheetMetalStudioViewModel(initialDocument: doc);
      final vs = widget.sheet.viewSettings;
      if (_sheetViewModel!.isCoverVisible3D != vs.showCover3D) {
        _sheetViewModel!.toggleCoverVisibility3D();
      }
      _sheetViewModel!.azimuthDeg = vs.camera3D.azimuthDeg;
      _sheetViewModel!.elevationDeg = vs.camera3D.elevationDeg;
      _sheetViewModel!.cameraZoom = vs.camera3D.zoom;
      _sheetViewModel!.pan3D = Offset(vs.camera3D.panOffset.x, vs.camera3D.panOffset.y);
      _sheetViewModel!.showCmsPortHighlights = _showDimPorts;
      _sheetViewModel!.addListener(_onSheetVmChanged);
      _activeLoadedInstanceId = newInstId;
    } else {
      _sheetViewModel?.removeListener(_onSheetVmChanged);
      _sheetViewModel?.dispose();
      _sheetViewModel = null;
      _activeLoadedInstanceId = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _restoreFromSheetViewSettings();
    _syncSheetViewModel();

    _sweepController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500))
      ..addListener(() {
        if (_isAutoSweeping) {
          setState(() {
            _transitionProgress = _sweepController.value;
          });
        }
      });
  }

  @override
  void didUpdateWidget(covariant DdsPaperCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeMarkupTool != widget.activeMarkupTool) {
      _pendingStartPoint = null;
      _pendingCloudPoints.clear();
      _currentHoverPoint = null;
    }
    if (oldWidget.sheet.sheetId != widget.sheet.sheetId) {
      _restoreFromSheetViewSettings();
    }
    if (widget.showDimWidth != null && widget.showDimWidth != _showDimWidth) {
      _showDimWidth = widget.showDimWidth!;
    }
    if (widget.showDimHeight != null && widget.showDimHeight != _showDimHeight) {
      _showDimHeight = widget.showDimHeight!;
    }
    if (widget.showDimPorts != null && widget.showDimPorts != _showDimPorts) {
      _showDimPorts = widget.showDimPorts!;
    }
    if (widget.showDimSlots != null && widget.showDimSlots != _showDimSlots) {
      _showDimSlots = widget.showDimSlots!;
    }
    if (widget.showDimFlange != null && widget.showDimFlange != _showDimFlange) {
      _showDimFlange = widget.showDimFlange!;
    }
    if (widget.showDimThickness != null && widget.showDimThickness != _showDimThickness) {
      _showDimThickness = widget.showDimThickness!;
    }

    if (oldWidget.evaluatedInstance != widget.evaluatedInstance ||
        oldWidget.sheet.sheetId != widget.sheet.sheetId ||
        oldWidget.evaluatedInstance?.instance.instanceId != widget.evaluatedInstance?.instance.instanceId) {
      _syncSheetViewModel();
    }
    if (_sheetViewModel != null) {
      _sheetViewModel!.showCmsPortHighlights = _showDimPorts;
    }
  }

  @override
  void dispose() {
    _viewSettingsPersistTimer?.cancel();
    _canvasFocusNode.dispose();
    _sheetViewModel?.removeListener(_onSheetVmChanged);
    _sheetViewModel?.dispose();
    _sweepController.dispose();
    super.dispose();
  }

  void _toggleAutoSweep() {
    setState(() {
      _isAutoSweeping = !_isAutoSweeping;
      if (_isAutoSweeping) {
        _sweepController.repeat(reverse: true);
      } else {
        _sweepController.stop();
      }
    });
  }

  // ===========================================================================
  // Interactive Pointer Gestures for Markup Authoring
  // ===========================================================================

  /// Checks if [pt] is within [tolerance] mm of the perimeter of [ann].
  bool _isNearBorder(CadPoint2D pt, DdsNoteBoxAnnotation ann, {double tolerance = 4.5}) {
    final borderPt = _getNearestBorderPoint(pt, ann);
    return (pt - borderPt).length <= tolerance;
  }

  _AnnotationDragMode _hitTestHandles(CadPoint2D ptMm, DdsAnnotation ann) {
    if (ann is DdsNoteBoxAnnotation) {
      final x = ann.x;
      final y = ann.y;
      final w = ann.width;
      final h = ann.height;

      // 1. Pull-out arrow tips (diamond handles)
      for (final arrow in ann.arrows) {
        if ((ptMm - arrow.tip).length <= _handleRadiusMm) return _AnnotationDragMode.arrowTip;
      }

      // 2. Pull-out arrow roots (border attachment handles)
      for (final arrow in ann.arrows) {
        final root = arrow.root ?? _getNearestBorderPoint(arrow.tip, ann);
        if ((ptMm - root).length <= _handleRadiusMm) return _AnnotationDragMode.arrowRoot;
      }

      // 3. Corner resize handles
      if ((ptMm - CadPoint2D(x, y)).length <= _handleRadiusMm) return _AnnotationDragMode.topLeft;
      if ((ptMm - CadPoint2D(x + w, y)).length <= _handleRadiusMm) return _AnnotationDragMode.topRight;
      if ((ptMm - CadPoint2D(x, y + h)).length <= _handleRadiusMm) return _AnnotationDragMode.bottomLeft;
      if ((ptMm - CadPoint2D(x + w, y + h)).length <= _handleRadiusMm) return _AnnotationDragMode.bottomRight;

      // 4. Any point on the border picks an arrow
      if (_isNearBorder(ptMm, ann, tolerance: 4.5)) {
        return _AnnotationDragMode.arrowTip;
      }

      // 5. Interior moves the note box
      if (ptMm.x >= x && ptMm.x <= x + w && ptMm.y >= y && ptMm.y <= y + h) {
        return _AnnotationDragMode.move;
      }
    } else if (ann is DdsApprovalStampAnnotation) {
      final x = ann.x;
      final y = ann.y;
      final w = ann.width;
      final h = ann.height;

      if ((ptMm - CadPoint2D(x, y)).length <= _handleRadiusMm) return _AnnotationDragMode.topLeft;
      if ((ptMm - CadPoint2D(x + w, y)).length <= _handleRadiusMm) return _AnnotationDragMode.topRight;
      if ((ptMm - CadPoint2D(x, y + h)).length <= _handleRadiusMm) return _AnnotationDragMode.bottomLeft;
      if ((ptMm - CadPoint2D(x + w, y + h)).length <= _handleRadiusMm) return _AnnotationDragMode.bottomRight;
      if ((ptMm - CadPoint2D(x + w / 2, y)).length <= _handleRadiusMm) return _AnnotationDragMode.topCenter;
      if ((ptMm - CadPoint2D(x + w / 2, y + h)).length <= _handleRadiusMm) return _AnnotationDragMode.bottomCenter;
      if ((ptMm - CadPoint2D(x, y + h / 2)).length <= _handleRadiusMm) return _AnnotationDragMode.middleLeft;
      if ((ptMm - CadPoint2D(x + w, y + h / 2)).length <= _handleRadiusMm) return _AnnotationDragMode.middleRight;

      if (ptMm.x >= x && ptMm.x <= x + w && ptMm.y >= y && ptMm.y <= y + h) {
        return _AnnotationDragMode.move;
      }
    } else if (ann is DdsLeaderNoteAnnotation) {
      if ((ptMm - ann.targetPoint).length <= _handleRadiusMm) return _AnnotationDragMode.targetPoint;
      if ((ptMm - ann.textPosition).length <= _handleRadiusMm) return _AnnotationDragMode.textPosition;
      final dMid = ((ann.targetPoint + ann.textPosition) * 0.5 - ptMm).length;
      if (dMid <= _hitTestRadiusMm) return _AnnotationDragMode.move;
    } else if (ann is DdsLinearDimensionAnnotation) {
      if ((ptMm - ann.p1).length <= _handleRadiusMm) return _AnnotationDragMode.dimP1;
      if ((ptMm - ann.p2).length <= _handleRadiusMm) return _AnnotationDragMode.dimP2;
      final mid = (ann.p1 + ann.p2) * 0.5;
      if ((ptMm - mid).length <= _hitTestRadiusMm) return _AnnotationDragMode.move;
    }
    return _AnnotationDragMode.none;
  }

  void _handlePointerHover(PointerHoverEvent event, Size paperSize) {
    if (paperSize.width <= 0 || paperSize.height <= 0) return;
    final mmX = (event.localPosition.dx / paperSize.width) * 297.0;
    final mmY = (event.localPosition.dy / paperSize.height) * 210.0;
    final hoverMm = CadPoint2D(mmX, mmY);

    _AnnotationDragMode hoverMode = _AnnotationDragMode.none;
    if (widget.selectedAnnotationId != null) {
      final selAnn = widget.sheet.annotations.cast<DdsAnnotation?>().firstWhere((a) => a?.id == widget.selectedAnnotationId, orElse: () => null);
      if (selAnn != null) {
        hoverMode = _hitTestHandles(hoverMm, selAnn);
      }
    }

    setState(() {
      _currentHoverPoint = hoverMm;
      _activeHoverMode = hoverMode;
    });
  }

  void _handlePointerDown(PointerDownEvent event, Size paperSize) {
    if (paperSize.width <= 0 || paperSize.height <= 0) return;
    _canvasFocusNode.requestFocus();
    final mmX = (event.localPosition.dx / paperSize.width) * 297.0;
    final mmY = (event.localPosition.dy / paperSize.height) * 210.0;
    final clickPoint = CadPoint2D(mmX, mmY);

    switch (widget.activeMarkupTool) {
      case DdsMarkupTool.select:
        _performHitTest(clickPoint);
        break;

      case DdsMarkupTool.linearDimension:
        if (_pendingStartPoint == null) {
          setState(() => _pendingStartPoint = clickPoint);
        } else {
          final p1 = _pendingStartPoint!;
          final p2 = clickPoint;
          _pendingStartPoint = null;
          _createLinearDimension(p1, p2);
        }
        break;

      case DdsMarkupTool.leaderNote:
        if (_pendingStartPoint == null) {
          setState(() => _pendingStartPoint = clickPoint);
        } else {
          final target = _pendingStartPoint!;
          final textPos = clickPoint;
          _pendingStartPoint = null;
          _promptAndCreateLeaderNote(target, textPos);
        }
        break;

      case DdsMarkupTool.noteBox:
        _promptAndCreateNoteBox(clickPoint);
        break;

      case DdsMarkupTool.revisionCloud:
        setState(() {
          _pendingCloudPoints.add(clickPoint);
        });
        break;

      case DdsMarkupTool.approvalStamp:
        _createApprovalStamp(clickPoint);
        break;
    }
  }

  void _performHitTest(CadPoint2D clickMm) {
    // 1. If an annotation is already selected, test if we clicked on any of its resize handles or body
    if (widget.selectedAnnotationId != null) {
      final selAnn = widget.sheet.annotations.cast<DdsAnnotation?>().firstWhere((a) => a?.id == widget.selectedAnnotationId, orElse: () => null);
      if (selAnn != null && selAnn.isVisible) {
        // Check if user clicked the delete button near the selected arrow tip
        if (selAnn is DdsNoteBoxAnnotation && _selectedArrowId != null) {
          final selArrow = selAnn.arrows.where((a) => a.id == _selectedArrowId).firstOrNull;
          if (selArrow != null) {
            final delBtnMm = CadPoint2D(selArrow.tip.x + 4.0, selArrow.tip.y - 4.0);
            if ((clickMm - delBtnMm).length <= 5.0) {
              _deleteArrow(selAnn.id, _selectedArrowId!);
              return;
            }
          }
        }

        final mode = _hitTestHandles(clickMm, selAnn);
        if (mode != _AnnotationDragMode.none) {
          if (mode == _AnnotationDragMode.arrowTip && selAnn is DdsNoteBoxAnnotation) {
            String? hitArrowId;
            for (final arrow in selAnn.arrows) {
              if ((clickMm - arrow.tip).length <= _handleRadiusMm) {
                hitArrowId = arrow.id;
                break;
              }
            }
            if (hitArrowId != null) {
              // Clicked existing arrow tip
              _draggingArrowId = hitArrowId;
              _selectedArrowId = hitArrowId;
            } else {
              // Pick an arrow from ANY point on the border
              final rootPt = _getNearestBorderPoint(clickMm, selAnn);
              final newArrow = DdsNoteArrow(id: 'arrow_${DateTime.now().millisecondsSinceEpoch}', tip: clickMm, root: rootPt);
              final updatedAnns = List<DdsAnnotation>.from(widget.sheet.annotations);
              final idx = updatedAnns.indexWhere((a) => a.id == selAnn.id);
              if (idx != -1) {
                updatedAnns[idx] = selAnn.copyWith(arrows: [...selAnn.arrows, newArrow]);
              }
              widget.onAnnotationsChanged?.call(updatedAnns);
              hitArrowId = newArrow.id;
              _draggingArrowId = hitArrowId;
              _selectedArrowId = hitArrowId;
            }
            _draggedAnnotationId = selAnn.id;
            _activeDragMode = _AnnotationDragMode.arrowTip;
            _isDraggingAnnotation = true;
            _dragLastPointMm = clickMm;
            setState(() {});
            return;
          }
          if (mode == _AnnotationDragMode.arrowRoot && selAnn is DdsNoteBoxAnnotation) {
            String? hitArrowId;
            for (final arrow in selAnn.arrows) {
              final root = arrow.root ?? _getNearestBorderPoint(arrow.tip, selAnn);
              if ((clickMm - root).length <= _handleRadiusMm) {
                hitArrowId = arrow.id;
                break;
              }
            }
            if (hitArrowId != null) {
              _draggingArrowId = hitArrowId;
              _selectedArrowId = hitArrowId;
              _draggedAnnotationId = selAnn.id;
              _activeDragMode = _AnnotationDragMode.arrowRoot;
              _isDraggingAnnotation = true;
              _dragLastPointMm = clickMm;
              setState(() {});
              return;
            }
          }
          _selectedArrowId = null;
          _activeDragMode = mode;
          _isDraggingAnnotation = true;
          _draggedAnnotationId = selAnn.id;
          _dragLastPointMm = clickMm;
          setState(() {});
          return;
        }
      }
    }

    // 2. Otherwise hit-test all visible annotations to select a new one
    for (final ann in widget.sheet.annotations.reversed) {
      if (!ann.isVisible) continue;

      if (ann is DdsLinearDimensionAnnotation) {
        final d1 = (ann.p1 - clickMm).length;
        final d2 = (ann.p2 - clickMm).length;
        final mid = CadPoint2D((ann.p1.x + ann.p2.x) / 2, (ann.p1.y + ann.p2.y) / 2);
        final dMid = (mid - clickMm).length;
        if (d1 < _hitTestRadiusMm || d2 < _hitTestRadiusMm || dMid < _hitTestRadiusMm) {
          _draggedAnnotationId = ann.id;
          _activeDragMode = _AnnotationDragMode.move;
          _isDraggingAnnotation = true;
          _dragLastPointMm = clickMm;
          widget.onAnnotationSelected?.call(ann.id);
          return;
        }
      } else if (ann is DdsLeaderNoteAnnotation) {
        final dT = (ann.targetPoint - clickMm).length;
        final dP = (ann.textPosition - clickMm).length;
        if (dT < _hitTestRadiusMm || dP < _hitTestRadiusMm) {
          _draggedAnnotationId = ann.id;
          _activeDragMode = _AnnotationDragMode.move;
          _isDraggingAnnotation = true;
          _dragLastPointMm = clickMm;
          widget.onAnnotationSelected?.call(ann.id);
          return;
        }
      } else if (ann is DdsNoteBoxAnnotation) {
        if (clickMm.x >= ann.x && clickMm.x <= ann.x + ann.width && clickMm.y >= ann.y && clickMm.y <= ann.y + ann.height) {
          _draggedAnnotationId = ann.id;
          _activeDragMode = _AnnotationDragMode.move;
          _isDraggingAnnotation = true;
          _dragLastPointMm = clickMm;
          widget.onAnnotationSelected?.call(ann.id);
          return;
        }
      } else if (ann is DdsApprovalStampAnnotation) {
        if (clickMm.x >= ann.x && clickMm.x <= ann.x + ann.width && clickMm.y >= ann.y && clickMm.y <= ann.y + ann.height) {
          _draggedAnnotationId = ann.id;
          _activeDragMode = _AnnotationDragMode.move;
          _isDraggingAnnotation = true;
          _dragLastPointMm = clickMm;
          widget.onAnnotationSelected?.call(ann.id);
          return;
        }
      } else if (ann is DdsRevisionCloudAnnotation) {
        for (final pt in ann.points) {
          if ((pt - clickMm).length < _hitTestRadiusMm) {
            _draggedAnnotationId = ann.id;
            _activeDragMode = _AnnotationDragMode.move;
            _isDraggingAnnotation = true;
            _dragLastPointMm = clickMm;
            widget.onAnnotationSelected?.call(ann.id);
            return;
          }
        }
      }
    }

    // Deselect if clicked blank area
    _draggedAnnotationId = null;
    _activeDragMode = _AnnotationDragMode.none;
    _isDraggingAnnotation = false;
    _dragLastPointMm = null;
    widget.onAnnotationSelected?.call(null);
  }

  void _handlePointerMove(PointerMoveEvent event, Size paperSize) {
    if (!_isDraggingAnnotation || _draggedAnnotationId == null || _dragLastPointMm == null) return;
    if (paperSize.width <= 0 || paperSize.height <= 0) return;

    final mmX = (event.localPosition.dx / paperSize.width) * 297.0;
    final mmY = (event.localPosition.dy / paperSize.height) * 210.0;
    final currentMm = CadPoint2D(mmX, mmY);
    final dx = currentMm.x - _dragLastPointMm!.x;
    final dy = currentMm.y - _dragLastPointMm!.y;
    if (dx.abs() < 0.05 && dy.abs() < 0.05) return;
    _dragLastPointMm = currentMm;

    final updatedList = widget.sheet.annotations.map((ann) {
      if (ann.id != _draggedAnnotationId) return ann;
      if (ann is DdsNoteBoxAnnotation) {
        switch (_activeDragMode) {
          case _AnnotationDragMode.move:
            return ann.copyWith(x: ann.x + dx, y: ann.y + dy);
          case _AnnotationDragMode.topLeft:
            final newW = ann.width - dx;
            final newH = ann.height - dy;
            return ann.copyWith(
              x: newW >= 20.0 ? ann.x + dx : ann.x,
              y: newH >= 10.0 ? ann.y + dy : ann.y,
              width: math.max(20.0, newW),
              height: math.max(10.0, newH),
            );
          case _AnnotationDragMode.topCenter:
            final newH = ann.height - dy;
            return ann.copyWith(y: newH >= 10.0 ? ann.y + dy : ann.y, height: math.max(10.0, newH));
          case _AnnotationDragMode.topRight:
            final newW = ann.width + dx;
            final newH = ann.height - dy;
            return ann.copyWith(y: newH >= 10.0 ? ann.y + dy : ann.y, width: math.max(20.0, newW), height: math.max(10.0, newH));
          case _AnnotationDragMode.middleLeft:
            final newW = ann.width - dx;
            return ann.copyWith(x: newW >= 20.0 ? ann.x + dx : ann.x, width: math.max(20.0, newW));
          case _AnnotationDragMode.middleRight:
            return ann.copyWith(width: math.max(20.0, ann.width + dx));
          case _AnnotationDragMode.bottomLeft:
            final newW = ann.width - dx;
            final newH = ann.height + dy;
            return ann.copyWith(x: newW >= 20.0 ? ann.x + dx : ann.x, width: math.max(20.0, newW), height: math.max(10.0, newH));
          case _AnnotationDragMode.bottomCenter:
            return ann.copyWith(height: math.max(10.0, ann.height + dy));
          case _AnnotationDragMode.bottomRight:
            return ann.copyWith(width: math.max(20.0, ann.width + dx), height: math.max(10.0, ann.height + dy));
          case _AnnotationDragMode.arrowTip:
            // Move only the dragged arrow tip
            if (_draggingArrowId != null) {
              final updatedArrows = ann.arrows.map((a) {
                if (a.id != _draggingArrowId) return a;
                return a.copyWith(tip: CadPoint2D(a.tip.x + dx, a.tip.y + dy));
              }).toList();
              return ann.copyWith(arrows: updatedArrows);
            }
            return ann;
          case _AnnotationDragMode.arrowRoot:
            // Slide the dragged arrow's root along the border
            if (_draggingArrowId != null) {
              final updatedArrows = ann.arrows.map((a) {
                if (a.id != _draggingArrowId) return a;
                final curRoot = a.root ?? _getNearestBorderPoint(a.tip, ann);
                final shifted = CadPoint2D(curRoot.x + dx, curRoot.y + dy);
                final clampedRoot = _getNearestBorderPoint(shifted, ann);
                return a.copyWith(root: clampedRoot);
              }).toList();
              return ann.copyWith(arrows: updatedArrows);
            }
            return ann;
          default:
            // Move note box: also move all arrow roots and free tips with it
            final movedArrows = ann.arrows.map((a) {
              final oldRoot = a.root ?? _getNearestBorderPoint(a.tip, ann);
              final newRoot = CadPoint2D(oldRoot.x + dx, oldRoot.y + dy);
              if (a.anchorEntity != null) {
                return a.copyWith(root: newRoot);
              } else {
                final newTip = CadPoint2D(a.tip.x + dx, a.tip.y + dy);
                return a.copyWith(root: newRoot, tip: newTip);
              }
            }).toList();
            return ann.copyWith(x: ann.x + dx, y: ann.y + dy, arrows: movedArrows);
        }
      } else if (ann is DdsApprovalStampAnnotation) {
        switch (_activeDragMode) {
          case _AnnotationDragMode.move:
            return ann.copyWith(x: ann.x + dx, y: ann.y + dy);
          case _AnnotationDragMode.topLeft:
            final newW = ann.width - dx;
            final newH = ann.height - dy;
            return ann.copyWith(
              x: newW >= 40.0 ? ann.x + dx : ann.x,
              y: newH >= 25.0 ? ann.y + dy : ann.y,
              width: math.max(40.0, newW),
              height: math.max(25.0, newH),
            );
          case _AnnotationDragMode.topCenter:
            final newH = ann.height - dy;
            return ann.copyWith(y: newH >= 25.0 ? ann.y + dy : ann.y, height: math.max(25.0, newH));
          case _AnnotationDragMode.topRight:
            final newW = ann.width + dx;
            final newH = ann.height - dy;
            return ann.copyWith(y: newH >= 25.0 ? ann.y + dy : ann.y, width: math.max(40.0, newW), height: math.max(25.0, newH));
          case _AnnotationDragMode.middleLeft:
            final newW = ann.width - dx;
            return ann.copyWith(x: newW >= 40.0 ? ann.x + dx : ann.x, width: math.max(40.0, newW));
          case _AnnotationDragMode.middleRight:
            return ann.copyWith(width: math.max(40.0, ann.width + dx));
          case _AnnotationDragMode.bottomLeft:
            final newW = ann.width - dx;
            final newH = ann.height + dy;
            return ann.copyWith(x: newW >= 40.0 ? ann.x + dx : ann.x, width: math.max(40.0, newW), height: math.max(25.0, newH));
          case _AnnotationDragMode.bottomCenter:
            return ann.copyWith(height: math.max(25.0, ann.height + dy));
          case _AnnotationDragMode.bottomRight:
            return ann.copyWith(width: math.max(40.0, ann.width + dx), height: math.max(25.0, ann.height + dy));
          default:
            return ann.copyWith(x: ann.x + dx, y: ann.y + dy);
        }
      } else if (ann is DdsLeaderNoteAnnotation) {
        if (_activeDragMode == _AnnotationDragMode.targetPoint) {
          return ann.copyWith(targetPoint: CadPoint2D(ann.targetPoint.x + dx, ann.targetPoint.y + dy));
        } else if (_activeDragMode == _AnnotationDragMode.textPosition) {
          return ann.copyWith(textPosition: CadPoint2D(ann.textPosition.x + dx, ann.textPosition.y + dy));
        } else {
          return ann.copyWith(
            targetPoint: CadPoint2D(ann.targetPoint.x + dx, ann.targetPoint.y + dy),
            textPosition: CadPoint2D(ann.textPosition.x + dx, ann.textPosition.y + dy),
          );
        }
      } else if (ann is DdsLinearDimensionAnnotation) {
        if (_activeDragMode == _AnnotationDragMode.dimP1) {
          return ann.copyWith(p1: CadPoint2D(ann.p1.x + dx, ann.p1.y + dy));
        } else if (_activeDragMode == _AnnotationDragMode.dimP2) {
          return ann.copyWith(p2: CadPoint2D(ann.p2.x + dx, ann.p2.y + dy));
        } else {
          return ann.copyWith(p1: CadPoint2D(ann.p1.x + dx, ann.p1.y + dy), p2: CadPoint2D(ann.p2.x + dx, ann.p2.y + dy));
        }
      } else if (ann is DdsRevisionCloudAnnotation) {
        return ann.copyWith(points: ann.points.map((p) => CadPoint2D(p.x + dx, p.y + dy)).toList());
      }
      return ann;
    }).toList();

    widget.onAnnotationsChanged?.call(updatedList);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_activeDragMode == _AnnotationDragMode.arrowTip && _draggingArrowId != null) {
      final selAnn = widget.sheet.annotations.where((a) => a.id == widget.selectedAnnotationId).firstOrNull;
      if (selAnn is DdsNoteBoxAnnotation) {
        final arrow = selAnn.arrows.where((a) => a.id == _draggingArrowId).firstOrNull;
        if (arrow != null) {
          final root = arrow.root ?? _getNearestBorderPoint(arrow.tip, selAnn);
          if ((arrow.tip - root).length < 4.0) {
            final center = CadPoint2D(selAnn.x + selAnn.width / 2, selAnn.y + selAnn.height / 2);
            var dir = root - center;
            if (dir.length < 0.1) dir = const CadPoint2D(1, 0);
            final norm = CadPoint2D(dir.x / dir.length, dir.y / dir.length);
            final extendedTip = CadPoint2D(root.x + norm.x * 16.0, root.y + norm.y * 16.0);
            final updatedArrows = selAnn.arrows.map((a) => a.id == arrow.id ? a.copyWith(tip: extendedTip) : a).toList();
            final updatedAnns = widget.sheet.annotations.map((a) => a.id == selAnn.id ? selAnn.copyWith(arrows: updatedArrows) : a).toList();
            widget.onAnnotationsChanged?.call(updatedAnns);
          }
        }
      }
    }
    _isDraggingAnnotation = false;
    _activeDragMode = _AnnotationDragMode.none;
    _draggedAnnotationId = null;
    _draggingArrowId = null;
    _dragLastPointMm = null;
    setState(() {});
  }

  void _createLinearDimension(CadPoint2D p1, CadPoint2D p2) {
    final length = (p2 - p1).length;
    final annotation = DdsLinearDimensionAnnotation(
      id: 'dim_${DateTime.now().millisecondsSinceEpoch}',
      p1: p1,
      p2: p2,
      prefix: 'L = ',
      suffix: ' mm',
      offsetDistance: 12.0,
      textOverride: '${length.toStringAsFixed(1)} mm',
    );

    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  Future<void> _promptAndCreateLeaderNote(CadPoint2D target, CadPoint2D textPos) async {
    final controller = TextEditingController(text: 'Coupler Flap (4x M6 Slots)');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.call_made, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 8.0),
            Text('Leader Callout Note', style: TextStyle(color: Colors.white, fontSize: 14.0)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13.0),
          decoration: InputDecoration(
            labelText: 'Note Text',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Place Note', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (text == null || text.isEmpty) return;

    final annotation = DdsLeaderNoteAnnotation(id: 'leader_${DateTime.now().millisecondsSinceEpoch}', targetPoint: target, textPosition: textPos, text: text);

    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  Future<void> _promptAndCreateNoteBox(CadPoint2D pos) async {
    final controller = TextEditingController(text: 'NOTE: All dimensions in mm. Confirm site opening before fabrication.');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.note_alt_outlined, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 8.0),
            Text('General Sheet Note', style: TextStyle(color: Colors.white, fontSize: 14.0)),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13.0),
          decoration: InputDecoration(
            labelText: 'Specification / Site Note',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add Note Box', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (text == null || text.isEmpty) return;

    final annotation = DdsNoteBoxAnnotation(id: 'notebox_${DateTime.now().millisecondsSinceEpoch}', x: pos.x, y: pos.y, width: 75.0, height: 25.0, text: text);

    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  void _finishRevisionCloud() {
    if (_pendingCloudPoints.length < 2) {
      setState(() => _pendingCloudPoints.clear());
      return;
    }

    final annotation = DdsRevisionCloudAnnotation(
      id: 'revcloud_${DateTime.now().millisecondsSinceEpoch}',
      points: List<CadPoint2D>.from(_pendingCloudPoints),
      revisionTag: 'Δ${widget.document.projectInfo.revision}',
    );

    _pendingCloudPoints.clear();
    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  void _createApprovalStamp(CadPoint2D pos) {
    final annotation = DdsApprovalStampAnnotation(
      id: 'stamp_${DateTime.now().millisecondsSinceEpoch}',
      x: pos.x,
      y: pos.y,
      width: 70.0,
      height: 28.0,
      status: 'APPROVED AS NOTED',
      reviewedBy: widget.document.projectInfo.consultant.isNotEmpty ? widget.document.projectInfo.consultant : 'Consultant Engineer',
      reviewDate: widget.document.projectInfo.issueDate,
    );

    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  void _deleteSelectedAnnotation() {
    if (widget.selectedAnnotationId == null) return;
    final list = widget.sheet.annotations.where((a) => a.id != widget.selectedAnnotationId).toList();
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(null);
    setState(() {
      _selectedArrowId = null;
      _draggingArrowId = null;
    });
  }

  /// Deletes a specific pull-out arrow from a note box.
  void _deleteArrow(String boxId, String arrowId) {
    final updatedList = widget.sheet.annotations.map((ann) {
      if (ann.id == boxId && ann is DdsNoteBoxAnnotation) {
        return ann.copyWith(arrows: ann.arrows.where((a) => a.id != arrowId).toList());
      }
      return ann;
    }).toList();
    widget.onAnnotationsChanged?.call(updatedList);
    setState(() {
      _selectedArrowId = null;
      _draggingArrowId = null;
    });
  }

  // ===========================================================================
  // Build Method
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const paperAspect = 297.0 / 210.0;
        final maxWidth = constraints.maxWidth - 32.0;
        final maxHeight = constraints.maxHeight - 32.0;

        double paperWidth = maxWidth;
        double paperHeight = paperWidth / paperAspect;

        if (paperHeight > maxHeight) {
          paperHeight = maxHeight;
          paperWidth = paperHeight * paperAspect;
        }

        final paperSize = Size(paperWidth, paperHeight);

        return Center(
          child: MouseRegion(
            onHover: (e) => _handlePointerHover(e, paperSize),
            cursor: _getCursorForMarkupTool(),
            child: Focus(
              focusNode: _canvasFocusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent && widget.selectedAnnotationId != null) {
                  if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
                    if (_selectedArrowId != null) {
                      _deleteArrow(widget.selectedAnnotationId!, _selectedArrowId!);
                      return KeyEventResult.handled;
                    }
                    _deleteSelectedAnnotation();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Listener(
                onPointerDown: (e) => _handlePointerDown(e, paperSize),
                onPointerMove: (e) => _handlePointerMove(e, paperSize),
                onPointerUp: (e) => _handlePointerUp(e),
                child: Container(
                  width: paperWidth,
                  height: paperHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4.0),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16.0, offset: const Offset(0, 6))],
                  ),
                  child: Stack(
                    children: [
                      // Physical Sheet Content (Cover, Blank, or Product Layout)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20.0, 10.0, 10.0, 10.0), // 20mm filing margin
                          child: Container(
                            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF0F172A), width: 1.2)),
                            child: widget.sheet.isCoverPage ? _buildCoverPageSheet() : (widget.sheet.isBlankSheet ? _buildBlankSheet() : _buildProductSheet()),
                          ),
                        ),
                      ),

                      // Interactive Annotation Layer (Linear dimensions, leader notes, clouds, stamps)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _DdsAnnotationOverlayPainter(
                              annotations: widget.sheet.annotations,
                              selectedAnnotationId: widget.selectedAnnotationId,
                              selectedArrowId: _selectedArrowId,
                              paperSize: paperSize,
                              pendingStartPoint: _pendingStartPoint,
                              hoverPoint: _currentHoverPoint,
                              pendingCloudPoints: _pendingCloudPoints,
                              activeTool: widget.activeMarkupTool,
                            ),
                          ),
                        ),
                      ),

                      // Revision Cloud "Finish Cloud" floating button
                      if (_pendingCloudPoints.length >= 2 && widget.activeMarkupTool == DdsMarkupTool.revisionCloud)
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                            icon: const Icon(Icons.check, size: 16, color: Colors.white),
                            label: const Text('Finish Cloud', style: TextStyle(color: Colors.white, fontSize: 12.0)),
                            onPressed: _finishRevisionCloud,
                          ),
                        ),

                      // Quick Delete Floating Button for Selected Annotation or Arrow
                      if (_selectedArrowId != null && widget.selectedAnnotationId != null)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6.0),
                              border: Border.all(color: const Color(0xFFF59E0B)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Arrow Selected',
                                  style: TextStyle(color: Color(0xFFFCD34D), fontSize: 11.0, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8.0),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.delete, color: Color(0xFFEF4444), size: 16),
                                  tooltip: 'Delete Arrow (or press Del)',
                                  onPressed: () {
                                    _deleteArrow(widget.selectedAnnotationId!, _selectedArrowId!);
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (widget.selectedAnnotationId != null)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6.0),
                              border: Border.all(color: const Color(0xFFEF4444)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Markup Selected', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.0)),
                                const SizedBox(width: 8.0),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.delete, color: Color(0xFFEF4444), size: 16),
                                  tooltip: 'Delete Annotation',
                                  onPressed: _deleteSelectedAnnotation,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  MouseCursor _getCursorForMarkupTool() {
    // During active drag, the drag mode overrides hover mode
    final effectiveMode = _activeDragMode != _AnnotationDragMode.none ? _activeDragMode : _activeHoverMode;
    if (effectiveMode != _AnnotationDragMode.none) {
      switch (effectiveMode) {
        case _AnnotationDragMode.topLeft:
        case _AnnotationDragMode.bottomRight:
          return SystemMouseCursors.resizeUpLeftDownRight;
        case _AnnotationDragMode.topRight:
        case _AnnotationDragMode.bottomLeft:
          return SystemMouseCursors.resizeUpRightDownLeft;
        case _AnnotationDragMode.topCenter:
        case _AnnotationDragMode.bottomCenter:
          return SystemMouseCursors.resizeUpDown;
        case _AnnotationDragMode.middleLeft:
        case _AnnotationDragMode.middleRight:
          return SystemMouseCursors.resizeLeftRight;
        case _AnnotationDragMode.targetPoint:
        case _AnnotationDragMode.textPosition:
        case _AnnotationDragMode.dimP1:
        case _AnnotationDragMode.dimP2:
        case _AnnotationDragMode.arrowTip:
        case _AnnotationDragMode.arrowRoot:
          return SystemMouseCursors.grab;
        case _AnnotationDragMode.move:
          return SystemMouseCursors.move;
        case _AnnotationDragMode.none:
          break;
      }
    }
    switch (widget.activeMarkupTool) {
      case DdsMarkupTool.select:
        return SystemMouseCursors.basic;
      case DdsMarkupTool.linearDimension:
      case DdsMarkupTool.leaderNote:
      case DdsMarkupTool.revisionCloud:
        return SystemMouseCursors.precise;
      case DdsMarkupTool.noteBox:
      case DdsMarkupTool.approvalStamp:
        return SystemMouseCursors.copy;
    }
  }

  // ===========================================================================
  // 0. Blank Sheet Layout
  // ===========================================================================

  Widget _buildBlankSheet() {
    final proj = widget.document.projectInfo;

    return Column(
      children: [
        // Sheet Product Top Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    widget.sheet.title.isNotEmpty ? widget.sheet.title : 'Blank Engineering Sheet',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(width: 8.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                    decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(3.0)),
                    child: Text(
                      'SHEET ${widget.sheet.sheetNumber.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white, fontSize: 9.0, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'BLANK DRAFTING CANVAS  •  DOC: ${proj.documentNumber}',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.0, fontWeight: FontWeight.bold),
                  ),
                  if (widget.onDeleteSheet != null && widget.document.sheets.length > 1) ...[
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Delete this Sheet Page',
                      child: InkWell(
                        onTap: widget.onDeleteSheet,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline, size: 12, color: Color(0xFFEF4444)),
                              SizedBox(width: 3),
                              Text(
                                'DELETE PAGE',
                                style: TextStyle(color: Color(0xFFEF4444), fontSize: 8.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Blank Technical Drawing Canvas with subtle drafting grid
        Expanded(
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: CustomPaint(painter: _ViewportGridPainter()),
          ),
        ),

        // Bottom Technical Strip + Docked ISO 7200 Title Block
        _buildProductBottomDock(null, null),
      ],
    );
  }

  // ===========================================================================
  // 1. Cover Schedule Sheet Layout
  // ===========================================================================

  Widget _buildCoverPageSheet() {
    final proj = widget.document.projectInfo;
    final toc = widget.sheet.tableOfContents;

    return Column(
      children: [
        // Submittal Transmittal Header
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proj.documentTitle.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    'SUBMITTAL TRANSMITTAL & PRODUCT SCHEDULE  •  DOC: ${proj.documentNumber}',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                    decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(4.0)),
                    child: Text(
                      'REV ${proj.revision}  (${proj.status.toUpperCase()})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
                    ),
                  ),
                  if (widget.onDeleteSheet != null && widget.document.sheets.length > 1) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Delete Cover Page',
                      child: InkWell(
                        onTap: widget.onDeleteSheet,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline, size: 12, color: Color(0xFFEF4444)),
                              SizedBox(width: 3),
                              Text(
                                'DELETE PAGE',
                                style: TextStyle(color: Color(0xFFEF4444), fontSize: 8.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Document Control Grid (ISO 7200)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          color: const Color(0xFFF1F5F9),
          child: Row(
            children: [
              Expanded(child: _buildMetaField('PROJECT', proj.projectName)),
              Expanded(child: _buildMetaField('CLIENT', proj.client)),
              Expanded(child: _buildMetaField('CONSULTANT', proj.consultant)),
              Expanded(child: _buildMetaField('CONTRACTOR', proj.contractor)),
              Expanded(child: _buildMetaField('DATE', proj.issueDate)),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFCBD5E1)),

        // Table of Contents & BoQ Schedule Table
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.format_list_numbered, size: 14, color: Color(0xFF0284C7)),
                    SizedBox(width: 6.0),
                    Text(
                      'PRODUCT TRANSMITTAL SCHEDULE & BILL OF QUANTITIES',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),

                // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  color: const Color(0xFFE2E8F0),
                  child: const Row(
                    children: [
                      SizedBox(width: 36, child: Text('SHEET', style: _tocHeaderStyle)),
                      SizedBox(width: 50, child: Text('LINE #', style: _tocHeaderStyle)),
                      SizedBox(width: 80, child: Text('CUSTOMER REF', style: _tocHeaderStyle)),
                      Expanded(flex: 4, child: Text('PRODUCT DESCRIPTION', style: _tocHeaderStyle)),
                      Expanded(flex: 3, child: Text('CONFIGURATION & PORTS', style: _tocHeaderStyle)),
                      SizedBox(
                        width: 44,
                        child: Text('QTY', style: _tocHeaderStyle, textAlign: TextAlign.right),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text('STATUS', style: _tocHeaderStyle, textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF94A3B8)),

                // Table Rows
                Expanded(
                  child: ListView.separated(
                    itemCount: toc.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (context, idx) {
                      final item = toc[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 5.0),
                        child: Row(
                          children: [
                            SizedBox(width: 36, child: Text(item.sheetNumber.toString().padLeft(2, '0'), style: _tocRowStyleBold)),
                            SizedBox(width: 50, child: Text(item.orderLine, style: _tocRowStyle)),
                            SizedBox(width: 80, child: Text(item.customerRef, style: _tocRowStyleBold)),
                            Expanded(flex: 4, child: Text(item.productName, style: _tocRowStyleBold)),
                            Expanded(flex: 3, child: Text(item.configuration, style: _tocRowStyle)),
                            SizedBox(
                              width: 44,
                              child: Text('${item.quantity} pcs', style: _tocRowStyle, textAlign: TextAlign.right),
                            ),
                            SizedBox(
                              width: 60,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3.0),
                                    border: Border.all(color: const Color(0xFF10B981), width: 0.6),
                                  ),
                                  child: Text(
                                    item.status.toUpperCase(),
                                    style: const TextStyle(color: Color(0xFF047857), fontSize: 8.0, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Compliance Notes & Client Approval Stamp Block
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // General Specifications & Compliance
              const Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GENERAL NOTES & COMPLIANCE:',
                      style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    SizedBox(height: 3.0),
                    Text(
                      '1. Conforms to BS EN 50085-1: Cable trunking systems and cable ducting systems.',
                      style: TextStyle(fontSize: 8.0, color: Color(0xFF475569)),
                    ),
                    Text(
                      '2. Material: Pre-Galvanized Mild Steel DX51D + Z275 coating (nominal thickness 1.5 mm).',
                      style: TextStyle(fontSize: 8.0, color: Color(0xFF475569)),
                    ),
                    Text(
                      '3. Universal 95 mm coupler flap spacing with integral slotted holes (Ø6 mm).',
                      style: TextStyle(fontSize: 8.0, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),

              // Client Approval Stamp
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFF0284C7), width: 1.0),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'CLIENT / CONSULTANT APPROVAL STAMP',
                            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                          ),
                          Text('ISO 7200', style: TextStyle(fontSize: 8.0, color: Color(0xFF64748B))),
                        ],
                      ),
                      SizedBox(height: 4.0),
                      Row(
                        children: [
                          Text('[  ] APPROVED    [  ] APPROVED AS NOTED    [  ] REVISE & RESUBMIT', style: TextStyle(fontSize: 7.5, color: Color(0xFF334155))),
                        ],
                      ),
                      SizedBox(height: 4.0),
                      Text('Signed: ___________________________    Date: ______________', style: TextStyle(fontSize: 8.0, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. Product Detail Sheet Layout
  // ===========================================================================

  Widget _buildProductSheet() {
    final inst = widget.document.findInstance(widget.sheet.productInstanceId);
    final eval = widget.evaluatedInstance;

    return Column(
      children: [
        // Sheet Product Top Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    (inst?.productName ?? widget.sheet.title).replaceAll('Equal Gusset Cross', 'Equal Cross'),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(width: 8.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                    decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(3.0)),
                    child: Text(
                      inst?.productCode ?? 'PRODUCT',
                      style: const TextStyle(color: Colors.white, fontSize: 9.0, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (inst?.orderLine != null)
                    Text(
                      'ORDER: ${inst!.orderLine!.orderNumber}  |  LINE ${inst.orderLine!.lineNumber}  |  QTY: ${inst.orderLine!.quantity} PCS',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.0, fontWeight: FontWeight.bold),
                    ),
                  if (widget.onDeleteSheet != null) ...[
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Delete this Sheet Page',
                      child: InkWell(
                        onTap: widget.onDeleteSheet,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline, size: 12, color: Color(0xFFEF4444)),
                              SizedBox(width: 3),
                              Text(
                                'DELETE PAGE',
                                style: TextStyle(color: Color(0xFFEF4444), fontSize: 8.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Viewport Mode & Animation Control Bar
        _buildViewportControlBar(eval),

        // Active Viewport (2D ⇄ 3D Transition Wipe, Kinematic Fold, or Dual Split)
        Expanded(child: _buildActiveViewport(eval)),

        // Bottom Technical Strip + Docked ISO 7200 Title Block
        _buildProductBottomDock(inst, eval),
      ],
    );
  }

  // ===========================================================================
  // 2D ⇄ 3D Transition & Viewport Modes
  // ===========================================================================

  Widget _buildViewportControlBar(EvaluatedDdsInstance? eval) {
    final effectiveVm = _sheetViewModel ?? widget.viewModel;
    final inst = eval?.instance;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.5),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1.0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 720),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Viewport Mode Switcher
              Row(
                children: [
                  _buildModeTab(mode: DdsViewportMode.presentation3D, icon: Icons.view_in_ar, label: '3D Presentation Model', badgeText: 'ISO 3D'),
                  const SizedBox(width: 4),
                  _buildModeTab(mode: DdsViewportMode.transitionWipe, icon: Icons.compare_arrows, label: '3D Wipe'),
                ],
              ),

              // Right: Active Mode Controls
              if (_viewportMode == DdsViewportMode.presentation3D)
                Row(
                  children: [
                    // 3D Model Movement / Rotation Lock
                    _buildDisplayModeChip(
                      label: _is3DModelLocked ? 'Model Locked' : 'Model Unlocked',
                      icon: _is3DModelLocked ? Icons.lock : Icons.lock_open_outlined,
                      active: _is3DModelLocked,
                      activeColor: const Color(0xFFEF4444),
                      onTap: () {
                        setState(() => _is3DModelLocked = !_is3DModelLocked);
                        _persistSheetViewSettings();
                      },
                    ),
                    const SizedBox(width: 4),
                    // Option to display actual CAD Dimension Lines (like 2D sketch) and/or Callout Tags
                    _buildDisplayModeChip(
                      label: 'CAD Lines',
                      icon: Icons.straighten,
                      active: _showCadDimensionLines,
                      onTap: () {
                        setState(() => _showCadDimensionLines = !_showCadDimensionLines);
                        _persistSheetViewSettings();
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildDisplayModeChip(
                      label: 'Tags',
                      icon: Icons.label_outline,
                      active: _showDimensionTags,
                      onTap: () {
                        setState(() => _showDimensionTags = !_showDimensionTags);
                        _persistSheetViewSettings();
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildDisplayModeChip(
                      label: _combinePortDimensions ? 'W×H Joint' : 'W/H Split',
                      icon: _combinePortDimensions ? Icons.join_inner : Icons.splitscreen,
                      active: _combinePortDimensions,
                      onTap: () {
                        setState(() => _combinePortDimensions = !_combinePortDimensions);
                        _persistSheetViewSettings();
                      },
                    ),
                    if (effectiveVm?.document.cover != null || effectiveVm?.coverMesh != null || inst?.coverConfiguration.included == true) ...[
                      const SizedBox(width: 4),
                      _buildDisplayModeChip(
                        label: (effectiveVm?.isCoverVisible3D ?? true) ? 'Cover On' : 'Cover Off',
                        icon: (effectiveVm?.isCoverVisible3D ?? true) ? Icons.shield : Icons.shield_outlined,
                        active: effectiveVm?.isCoverVisible3D ?? true,
                        onTap: () {
                          effectiveVm?.toggleCoverVisibility3D();
                          setState(() {
                            _showCover3D = effectiveVm?.isCoverVisible3D ?? true;
                          });
                          _persistSheetViewSettings();
                        },
                      ),
                    ],
                    const SizedBox(width: 4),
                    _buildDisplayModeChip(
                      label: _showFasteners3D ? 'Fasteners On' : 'Fasteners Off',
                      icon: _showFasteners3D ? Icons.hardware : Icons.hardware_outlined,
                      active: _showFasteners3D,
                      onTap: () {
                        setState(() => _showFasteners3D = !_showFasteners3D);
                        _persistSheetViewSettings();
                      },
                    ),
                    const SizedBox(width: 8),
                    Container(width: 1, height: 16, color: const Color(0xFFCBD5E1)),
                    const SizedBox(width: 8),
                    const Text(
                      'Features: ',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    _buildDimToggleChip('W', _showDimWidth, () {
                      setState(() => _showDimWidth = !_showDimWidth);
                      widget.onDimensionToggled?.call('W', _showDimWidth);
                      _persistSheetViewSettings();
                    }),
                    const SizedBox(width: 3),
                    _buildDimToggleChip('H', _showDimHeight, () {
                      setState(() => _showDimHeight = !_showDimHeight);
                      widget.onDimensionToggled?.call('H', _showDimHeight);
                      _persistSheetViewSettings();
                    }),
                    const SizedBox(width: 3),
                    _buildDimToggleChip('Ports', _showDimPorts, () {
                      setState(() => _showDimPorts = !_showDimPorts);
                      widget.onDimensionToggled?.call('Ports', _showDimPorts);
                      _persistSheetViewSettings();
                    }),
                    const SizedBox(width: 3),
                    _buildDimToggleChip('Slots', _showDimSlots, () {
                      setState(() => _showDimSlots = !_showDimSlots);
                      widget.onDimensionToggled?.call('Slots', _showDimSlots);
                      _persistSheetViewSettings();
                    }),
                    const SizedBox(width: 3),
                    _buildDimToggleChip('Flange', _showDimFlange, () {
                      setState(() => _showDimFlange = !_showDimFlange);
                      widget.onDimensionToggled?.call('Flange', _showDimFlange);
                      _persistSheetViewSettings();
                    }),
                    const SizedBox(width: 3),
                    _buildDimToggleChip('Gauge', _showDimThickness, () {
                      setState(() => _showDimThickness = !_showDimThickness);
                      widget.onDimensionToggled?.call('Gauge', _showDimThickness);
                      _persistSheetViewSettings();
                    }),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        final allOn = _showDimWidth && _showDimHeight && _showDimPorts && _showDimSlots && _showDimFlange && _showDimThickness;
                        final target = !allOn;
                        setState(() {
                          _showDimWidth = target;
                          _showDimHeight = target;
                          _showDimPorts = target;
                          _showDimSlots = target;
                          _showDimFlange = target;
                          _showDimThickness = target;
                        });
                        widget.onDimensionToggled?.call('W', target);
                        widget.onDimensionToggled?.call('H', target);
                        widget.onDimensionToggled?.call('Ports', target);
                        widget.onDimensionToggled?.call('Slots', target);
                        widget.onDimensionToggled?.call('Flange', target);
                        widget.onDimensionToggled?.call('Gauge', target);
                        _persistSheetViewSettings();
                      },
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          (_showDimWidth && _showDimHeight) ? 'Hide All' : 'Show All',
                          style: const TextStyle(color: Color(0xFF0284C7), fontSize: 8.0, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                )
              else if (_viewportMode == DdsViewportMode.transitionWipe)
                Row(
                  children: [
                    // 45 deg Mechanical Section Hatching Toggle
                    InkWell(
                      onTap: () => setState(() => _showHatching = !_showHatching),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _showHatching ? const Color(0xFF0284C7).withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _showHatching ? const Color(0xFF38BDF8) : const Color(0xFF475569), width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.texture, size: 11, color: _showHatching ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8)),
                            const SizedBox(width: 4),
                            Text(
                              '45° Hatching',
                              style: TextStyle(
                                color: _showHatching ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                                fontSize: 9.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // 50% Quick Reset
                    InkWell(
                      onTap: () {
                        if (_isAutoSweeping) {
                          setState(() {
                            _isAutoSweeping = false;
                            _sweepController.stop();
                          });
                        }
                        setState(() => _transitionProgress = 0.50);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                        ),
                        child: const Text(
                          '50% Split',
                          style: TextStyle(color: Color(0xFF334155), fontSize: 9.0, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Auto-Sweep Button (60 FPS Cinematic Sweep)
                    InkWell(
                      onTap: _toggleAutoSweep,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isAutoSweeping ? [const Color(0xFFE11D48), const Color(0xFFBE123C)] : [const Color(0xFF0284C7), const Color(0xFF0369A1)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: _isAutoSweeping
                              ? [BoxShadow(color: const Color(0xFFE11D48).withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 1))]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(_isAutoSweeping ? Icons.pause : Icons.play_arrow, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              _isAutoSweeping ? 'Pause Sweep' : 'Auto Sweep',
                              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Transition Percentage Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Text(
                        '${(_transitionProgress * 100).toInt()}% 2D  ⬌  ${(100 - _transitionProgress * 100).toInt()}% 3D',
                        style: const TextStyle(color: Color(0xFF0284C7), fontSize: 9.0, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                )
              else
                const Row(
                  children: [
                    Icon(Icons.sync_alt, size: 12, color: Color(0xFF38BDF8)),
                    SizedBox(width: 4),
                    Text(
                      'Synchronized Dual Viewports',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.0, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisplayModeChip({required String label, required IconData icon, required bool active, required VoidCallback onTap, Color? activeColor}) {
    final effectiveActive = activeColor ?? const Color(0xFF0284C7);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? effectiveActive : Colors.white,
          border: Border.all(color: active ? effectiveActive : const Color(0xFFCBD5E1), width: 1.0),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [if (!active) BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: active ? Colors.white : effectiveActive),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 8.5, fontWeight: active ? FontWeight.bold : FontWeight.w600, color: active ? Colors.white : const Color(0xFF334155)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimToggleChip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0284C7) : Colors.white,
          border: Border.all(color: active ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1), width: 0.8),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 7.5, fontWeight: active ? FontWeight.bold : FontWeight.w500, color: active ? Colors.white : const Color(0xFF64748B)),
        ),
      ),
    );
  }

  Widget _buildModeTab({required DdsViewportMode mode, required IconData icon, required String label, String? badgeText}) {
    final isSelected = _viewportMode == mode;
    return InkWell(
      onTap: () {
        if (_isAutoSweeping) {
          _isAutoSweeping = false;
          _sweepController.stop();
        }
        setState(() => _viewportMode = mode);
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 11, color: isSelected ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF334155),
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF0284C7), fontSize: 7.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveViewport(EvaluatedDdsInstance? eval) {
    switch (_viewportMode) {
      case DdsViewportMode.presentation3D:
        return _build3DPresentationViewport(eval);
      case DdsViewportMode.transitionWipe:
        return _buildTransitionViewport(eval);
    }
  }

  Widget _buildTransitionViewport(EvaluatedDdsInstance? eval) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            if (_isAutoSweeping) {
              setState(() {
                _isAutoSweeping = false;
                _sweepController.stop();
              });
            }
          },
          onHorizontalDragUpdate: (details) {
            if (constraints.maxWidth > 0) {
              setState(() {
                _transitionProgress = (_transitionProgress + details.delta.dx / constraints.maxWidth).clamp(0.0, 1.0);
              });
            }
          },
          onTapDown: (details) {
            if (constraints.maxWidth > 0) {
              setState(() {
                if (_isAutoSweeping) {
                  _isAutoSweeping = false;
                  _sweepController.stop();
                }
                _transitionProgress = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
              });
            }
          },
          child: Stack(
            children: [
              // Combined 2D to 3D Shader/Clipped Painter
              Positioned.fill(
                child: CustomPaint(
                  painter: Dds2Dto3DTransitionPainter(
                    document: eval?.scaledBaseDocument,
                    mesh: eval?.combinedMesh3D,
                    transitionProgress: _transitionProgress,
                    showCrossHatching: _showHatching,
                    showDividerLine: true,
                    dividerColor: const Color(0xFF00E5FF),
                  ),
                ),
              ),

              // Bottom instruction pill overlay
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBAE6FD), width: 1.0),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swipe, size: 12, color: Color(0xFF0284C7)),
                        SizedBox(width: 6),
                        Text(
                          'Drag laser divider left/right or click anywhere to transition between 2D Blueprint & 3D Shaded Solid',
                          style: TextStyle(color: Color(0xFF0F172A), fontSize: 8.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Offset _projectMeshPoint(CadPoint3D p, Size size, SheetMetalStudioViewModel? vm) {
    if (vm == null) return Offset(size.width / 2.0, size.height / 2.0);
    final mesh = vm.currentMesh;
    final cx = size.width / 2.0 + vm.pan3D.dx;
    final cy = size.height / 2.0 + vm.pan3D.dy;
    final azRad = vm.azimuthDeg * math.pi / 180.0;
    final elRad = vm.elevationDeg * math.pi / 180.0;
    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * vm.cameraZoom;

    final rx = p.x - mesh.center.x;
    final ry = p.y - mesh.center.y;
    final rz = p.z - mesh.center.z;

    final x1 = rx * cosAz - ry * sinAz;
    final y1 = rx * sinAz + ry * cosAz;
    final z1 = rz;

    final x2 = x1;
    final y2 = y1 * cosEl - z1 * sinEl;

    return Offset(cx + x2 * scale, cy - y2 * scale);
  }

  Widget _build3DPresentationViewport(EvaluatedDdsInstance? eval) {
    final effectiveVm = _sheetViewModel ?? widget.viewModel;
    return LayoutBuilder(
      builder: (context, viewportConstraints) {
        final viewportSize = Size(viewportConstraints.maxWidth, viewportConstraints.maxHeight);

        return Container(
          color: const Color(0xFFF8FAFC),
          child: Stack(
            children: [
              // Technical Grid Background
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _ViewportGridPainter())),
              ),

              // 3D Rendering Engine: Modern Flutter GPU / Impeller 3D viewport with synchronized overlayBuilder
              Positioned.fill(
                child: effectiveVm != null
                    ? FlutterSceneViewportWidget(
                        viewModel: effectiveVm,
                        isInteractionLocked: _is3DModelLocked,
                        overlayBuilder: (overlayContext, size, project) {
                          return _build3DDimensionsOverlay(
                            eval: eval,
                            effectiveVm: effectiveVm,
                            viewportSize: size,
                            project: project,
                          );
                        },
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(painter: Dds3DIsometricPainter(mesh: eval?.combinedMesh3D)),
                          ),
                          _build3DDimensionsOverlay(
                            eval: eval,
                            effectiveVm: null,
                            viewportSize: viewportSize,
                            project: (p) => _projectMeshPoint(p, viewportSize, null),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _build3DDimensionsOverlay({
    required EvaluatedDdsInstance? eval,
    required SheetMetalStudioViewModel? effectiveVm,
    required Size viewportSize,
    required Offset Function(CadPoint3D p) project,
  }) {
    final inst = eval?.instance ?? widget.document.productInstances.firstOrNull;
    final cmsLive = (effectiveVm?.document.metadata['cmsParameters'] as Map<String, dynamic>?) ?? {};
    final p = Map<String, dynamic>.from(inst?.instanceParameters ?? {})..addAll(cmsLive);
    if (effectiveVm != null) {
      p['thickness'] = effectiveVm.document.material.thicknessMm;
    }

    final tId = (inst?.templateReference.templateId ?? '').toLowerCase();
    final pName = (inst?.productName ?? '').toLowerCase();
    final isCross = tId.contains('cross') || pName.contains('cross') || p.containsKey('port4_width');
    final isTee = !isCross && (tId.contains('tee') || pName.contains('tee') || p.containsKey('port3_width') || p.containsKey('branch_width'));
    final isReducer = !isCross && !isTee && (tId.contains('reducer') || pName.contains('reducer') || p.containsKey('port2_width') || p.containsKey('width2'));
    final hasMultiplePorts = isReducer || isTee || isCross;

    final physicalPorts = (eval?.scaledPorts.isNotEmpty == true) ? eval!.scaledPorts : (effectiveVm?.verifiedCmsPorts ?? []);

    final port1 = physicalPorts.isNotEmpty ? physicalPorts[0] : null;
    final port2 = physicalPorts.length > 1 ? physicalPorts[1] : null;
    final port3 = physicalPorts.length > 2 ? physicalPorts[2] : null;
    final port4 = physicalPorts.length > 3 ? physicalPorts[3] : null;

    final w1 = (p['port1_width'] ?? port1?.nominalWidth ?? p['width'] ?? 100.0).toDouble();
    final h1 = (p['port1_height'] ?? port1?.nominalHeight ?? p['height'] ?? 100.0).toDouble();
    final w2 = (p['port2_width'] ?? p['width2'] ?? port2?.nominalWidth ?? (isReducer ? (port2?.nominalWidth ?? w1 * 0.5) : (port2?.nominalWidth ?? 50.0)))
        .toDouble();
    final h2 = (p['port2_height'] ?? p['height2'] ?? port2?.nominalHeight ?? (isReducer ? (port2?.nominalHeight ?? h1 * 0.5) : (port2?.nominalHeight ?? 50.0)))
        .toDouble();
    final w3 = (p['port3_width'] ?? p['branch_width'] ?? port3?.nominalWidth ?? (isCross ? (port3?.nominalWidth ?? 50.0) : 50.0)).toDouble();
    final h3 = (p['port3_height'] ?? p['branch_height'] ?? port3?.nominalHeight ?? (isCross ? (port3?.nominalHeight ?? 50.0) : 50.0)).toDouble();
    final w4 = (p['port4_width'] ?? port4?.nominalWidth ?? (isCross ? (port4?.nominalWidth ?? w2) : 50.0)).toDouble();
    final h4 = (p['port4_height'] ?? port4?.nominalHeight ?? (isCross ? (port4?.nominalHeight ?? h2) : 50.0)).toDouble();

    final slotW = (p['coupler_slot_width'] ?? 9.0).toDouble();
    final slotL = (p['coupler_slot_length'] ?? 20.0).toDouble();
    final slotP = (p['coupler_slot_pitch'] ?? 25.0).toDouble();
    final baseFlange = (p['base_flange_size'] ?? 20.0).toDouble();
    final flangeDir = (p['flange_direction'] ?? 0.0) == 0.0 ? 'Inside Flange' : 'Outside Return';
    final coverFlange = (inst?.coverConfiguration.flangeDepthMm ?? p['cover_flange_size'] ?? 15.0).toDouble();
    final isCoverActive =
        (effectiveVm?.isCoverVisible3D ?? true) &&
        (inst?.coverConfiguration.included == true || effectiveVm?.document.cover != null || effectiveVm?.coverMesh != null);
    final thickness = (p['thickness'] ?? 1.5).toDouble();

    final m = effectiveVm?.currentMesh;
    final hasMesh = m != null && m.polygons.isNotEmpty && effectiveVm != null;

    final minX = m != null ? m.center.x - m.boundWidth / 2.0 : -100.0;
    final maxX = m != null ? m.center.x + m.boundWidth / 2.0 : 100.0;
    final minY = m != null ? m.center.y - m.boundLength / 2.0 : -100.0;
    final maxY = m != null ? m.center.y + m.boundLength / 2.0 : 100.0;
    final minZ = m != null ? m.center.z - m.boundHeight / 2.0 : -50.0;
    final maxZ = m != null ? m.center.z + m.boundHeight / 2.0 : 50.0;

    // Accurate 3D Coupler Slot Placement on actual coupler flap
    final punchCenters = m?.punchCenters3D ?? {};
    final couplerPunches = (effectiveVm?.document.allPunches ?? [])
        .where((p) => (p.role == CncPunchRole.coupler || p.isSlot || p.id.toUpperCase().contains('SLOT')) && punchCenters.containsKey(p.id))
        .toList();

    CadPoint3D slotP1_3D;
    CadPoint3D slotP2_3D;
    CadPoint3D slotAnchor3D;

    if (couplerPunches.length >= 2) {
      // Find pair of slots sharing the same coupler ear/flap
      CncPunchPrimitive bestA = couplerPunches[0];
      CncPunchPrimitive bestB = couplerPunches[1];
      double bestDist = double.infinity;
      for (int i = 0; i < couplerPunches.length; i++) {
        for (int j = i + 1; j < couplerPunches.length; j++) {
          final ptA = punchCenters[couplerPunches[i].id]!;
          final ptB = punchCenters[couplerPunches[j].id]!;
          final dXY = math.sqrt(math.pow(ptA.x - ptB.x, 2) + math.pow(ptA.y - ptB.y, 2));
          if (dXY < 25.0 && (ptA.z - ptB.z).abs() > 4.0 && dXY < bestDist) {
            bestDist = dXY;
            bestA = couplerPunches[i];
            bestB = couplerPunches[j];
          }
        }
      }
      slotP1_3D = punchCenters[bestA.id]!;
      slotP2_3D = punchCenters[bestB.id]!;
      slotAnchor3D = CadPoint3D((slotP1_3D.x + slotP2_3D.x) / 2, (slotP1_3D.y + slotP2_3D.y) / 2, (slotP1_3D.z + slotP2_3D.z) / 2);
    } else if (couplerPunches.length == 1) {
      final c = punchCenters[couplerPunches.first.id]!;
      slotP1_3D = CadPoint3D(c.x, c.y, c.z - slotL / 2);
      slotP2_3D = CadPoint3D(c.x, c.y, c.z + slotL / 2);
      slotAnchor3D = c;
    } else {
      // Geometric fallback anchored to coupler flap ear at port mouth
      final earY = minY - 8.0;
      slotP1_3D = CadPoint3D(minX, earY, (minZ + maxZ) / 2 - slotL / 2);
      slotP2_3D = CadPoint3D(minX, earY, (minZ + maxZ) / 2 + slotL / 2);
      slotAnchor3D = CadPoint3D(minX, earY, (minZ + maxZ) / 2);
    }

    // Physical 3D Port Mouth Rim Vertices extraction
    List<CadPoint3D>? getPhysicalPortCorners(int portIndex) {
      final ports = (eval?.scaledPorts.isNotEmpty == true) ? eval!.scaledPorts : (effectiveVm?.verifiedCmsPorts ?? []);
      if (portIndex < ports.length) {
        final port = ports[portIndex];
        if (port.derivedMouthCorners.length >= 4) {
          return port.derivedMouthCorners;
        }
        if (port.width > 1.0 && port.height > 1.0) {
          final floorCenter = CadPoint3D(
            port.center.x - (port.height / 2.0) * port.heightDirection.x,
            port.center.y - (port.height / 2.0) * port.heightDirection.y,
            port.center.z - (port.height / 2.0) * port.heightDirection.z,
          );
          final p0 = CadPoint3D(
            floorCenter.x - (port.width / 2.0) * port.widthDirection.x,
            floorCenter.y - (port.width / 2.0) * port.widthDirection.y,
            floorCenter.z - (port.width / 2.0) * port.widthDirection.z,
          );
          final p3 = CadPoint3D(
            floorCenter.x + (port.width / 2.0) * port.widthDirection.x,
            floorCenter.y + (port.width / 2.0) * port.widthDirection.y,
            floorCenter.z + (port.width / 2.0) * port.widthDirection.z,
          );
          final p1 = CadPoint3D(
            p0.x + port.height * port.heightDirection.x,
            p0.y + port.height * port.heightDirection.y,
            p0.z + port.height * port.heightDirection.z,
          );
          final p2 = CadPoint3D(
            p3.x + port.height * port.heightDirection.x,
            p3.y + port.height * port.heightDirection.y,
            p3.z + port.height * port.heightDirection.z,
          );
          return [p0, p1, p2, p3];
        }
      }
      return null;
    }

    final port1Corners = getPhysicalPortCorners(0);
    final port2Corners = getPhysicalPortCorners(1);
    final port3Corners = getPhysicalPortCorners(2);
    final port4Corners = getPhysicalPortCorners(3);

    final topAnchor = port1Corners != null
        ? project(
            CadPoint3D(
              (port1Corners[1].x + port1Corners[2].x) / 2,
              (port1Corners[1].y + port1Corners[2].y) / 2,
              (port1Corners[1].z + port1Corners[2].z) / 2,
            ),
          )
        : (hasMesh
              ? project(CadPoint3D(m.center.x, minY, maxZ))
              : Offset(viewportSize.width / 2.0, viewportSize.height * 0.35));

    final port2Anchor = port2Corners != null
        ? project(
            CadPoint3D(
              (port2Corners[1].x + port2Corners[2].x) / 2,
              (port2Corners[1].y + port2Corners[2].y) / 2,
              (port2Corners[1].z + port2Corners[2].z) / 2,
            ),
          )
        : (hasMesh
              ? project(CadPoint3D(m.center.x, isReducer ? (maxY - 25.0) : maxY, minZ + h2))
              : Offset(viewportSize.width * 0.70, viewportSize.height * 0.40));

    final port3Anchor = port3Corners != null
        ? project(
            CadPoint3D(
              (port3Corners[1].x + port3Corners[2].x) / 2,
              (port3Corners[1].y + port3Corners[2].y) / 2,
              (port3Corners[1].z + port3Corners[2].z) / 2,
            ),
          )
        : (hasMesh
              ? project(CadPoint3D(maxX, m.center.y, minZ + h3))
              : Offset(viewportSize.width * 0.75, viewportSize.height * 0.55));

    final port4Anchor = port4Corners != null
        ? project(
            CadPoint3D(
              (port4Corners[1].x + port4Corners[2].x) / 2,
              (port4Corners[1].y + port4Corners[2].y) / 2,
              (port4Corners[1].z + port4Corners[2].z) / 2,
            ),
          )
        : (hasMesh
              ? project(CadPoint3D(minX, m.center.y, minZ + h4))
              : Offset(viewportSize.width * 0.25, viewportSize.height * 0.45));

    final rightAnchor = hasMesh
        ? project(CadPoint3D(maxX, m.center.y, (minZ + maxZ) / 2))
        : Offset(viewportSize.width * 0.75, viewportSize.height * 0.55);
    final sAnchor = hasMesh ? project(slotAnchor3D) : Offset(viewportSize.width * 0.28, viewportSize.height * 0.55);
    final bottomAnchor = hasMesh
        ? project(CadPoint3D(m.center.x, (minY + maxY) / 2, minZ))
        : Offset(viewportSize.width / 2.0, viewportSize.height * 0.72);

    // Accurate Return Flange Geometry extracted from actual physical mesh face
    CadPoint3D? flangeInner3D;
    CadPoint3D? flangeOuter3D;

    if (hasMesh) {
      final flangeFaceIds = <String>{};

      // 1. Collect child face IDs from bends marked as flange
      for (final b in effectiveVm.document.bends) {
        if (b.role == BendLineRole.flange || b.id.toUpperCase().startsWith('FL') || b.layer.toUpperCase().contains('FLANGE')) {
          if (b.childFaceId.isNotEmpty) {
            flangeFaceIds.add(b.childFaceId);
          }
        }
      }

      // 2. Collect from template metadata verifiedFlangeIds if present
      final cmsMeta = effectiveVm.document.metadata['cmsTemplate'] as Map<String, dynamic>?;
      final verifiedFlangeIds = (cmsMeta?['verifiedFlangeIds'] as List?)?.map((e) => e.toString()).toSet() ?? {};
      for (final b in effectiveVm.document.bends) {
        if (verifiedFlangeIds.contains(b.id) && b.childFaceId.isNotEmpty) {
          flangeFaceIds.add(b.childFaceId);
        }
      }

      // 3. Collect from faces explicitly flagged as returnFlange
      for (final f in effectiveVm.document.faces) {
        if (f.role == FaceRole.returnFlange ||
            f.id.toUpperCase().contains('FLANGE') ||
            f.label.toLowerCase().contains('flange') ||
            f.label.toLowerCase().contains('return')) {
          flangeFaceIds.add(f.id);
        }
      }

      // Filter polygons: return flanges are planar 4-vertex quadrilaterals at the top rim of sidewalls
      List<CadFoldedPolygon3D> flangePolys = m.polygons.where((poly) {
        if (!flangeFaceIds.contains(poly.faceId)) return false;
        if (poly.vertices.length != 4) return false;
        final avgZ = poly.vertices.map((v) => v.z).reduce((a, b) => a + b) / 4.0;
        // Return flanges strictly reside at top sidewall elevation, never at floor or mid-flaps
        if (avgZ < minZ + (maxZ - minZ) * 0.50) return false;
        return true;
      }).toList();

      // Fallback: If no face was tagged with role flange, detect geometric top return lip
      if (flangePolys.isEmpty) {
        for (final poly in m.polygons) {
          if (poly.vertices.length == 4) {
            final avgZ = poly.vertices.map((v) => v.z).reduce((a, b) => a + b) / 4.0;
            if (avgZ >= minZ + (maxZ - minZ) * 0.65) {
              final v = poly.vertices;
              final d01 = (v[0] - v[1]).length;
              final d12 = (v[1] - v[2]).length;
              final minSide = math.min(d01, d12);
              final maxSide = math.max(d01, d12);
              if (minSide >= 5.0 && minSide <= 35.0 && maxSide > minSide * 1.5) {
                flangePolys.add(poly);
              }
            }
          }
        }
      }

      if (flangePolys.isNotEmpty) {
        CadFoldedPolygon3D? bestPoly;
        double bestScore = -double.infinity;
        for (final poly in flangePolys) {
          final c3D = CadPoint3D(
            poly.vertices.map((v) => v.x).reduce((a, b) => a + b) / 4.0,
            poly.vertices.map((v) => v.y).reduce((a, b) => a + b) / 4.0,
            poly.vertices.map((v) => v.z).reduce((a, b) => a + b) / 4.0,
          );
          final c2D = project(c3D);
          // Prioritize foreground left-hand return flange for clean isometric presentation
          double score = c2D.dy;
          if (c3D.x <= m.center.x + 5.0) {
            score += 500.0;
          }
          if (score > bestScore) {
            bestScore = score;
            bestPoly = poly;
          }
        }

        if (bestPoly != null && bestPoly.vertices.length >= 4) {
          final v = bestPoly.vertices;
          final d01 = (v[0] - v[1]).length;
          final d12 = (v[1] - v[2]).length;
          if ((d01 - baseFlange).abs() < (d12 - baseFlange).abs()) {
            final midA = CadPoint3D((v[0].x + v[3].x) / 2, (v[0].y + v[3].y) / 2, (v[0].z + v[3].z) / 2);
            final midB = CadPoint3D((v[1].x + v[2].x) / 2, (v[1].y + v[2].y) / 2, (v[1].z + v[2].z) / 2);
            final distA = (midA - m.center).length;
            final distB = (midB - m.center).length;
            flangeInner3D = distA <= distB ? midA : midB;
            flangeOuter3D = distA <= distB ? midB : midA;
          } else {
            final midA = CadPoint3D((v[0].x + v[1].x) / 2, (v[0].y + v[1].y) / 2, (v[0].z + v[1].z) / 2);
            final midB = CadPoint3D((v[3].x + v[2].x) / 2, (v[3].y + v[2].y) / 2, (v[3].z + v[2].z) / 2);
            final distA = (midA - m.center).length;
            final distB = (midB - m.center).length;
            flangeInner3D = distA <= distB ? midA : midB;
            flangeOuter3D = distA <= distB ? midB : midA;
          }
        }
      }
    }

    if (flangeInner3D == null || flangeOuter3D == null) {
      if (port1Corners != null) {
        // Anchor to the top lip of port 1 (z = port1Corners[1].z which is at max sidewall elevation)
        flangeInner3D = port1Corners[1];
        flangeOuter3D = CadPoint3D(flangeInner3D.x, flangeInner3D.y - baseFlange, flangeInner3D.z);
      } else {
        flangeInner3D = CadPoint3D(m != null ? m.center.x : 0.0, minY, maxZ);
        flangeOuter3D = CadPoint3D(flangeInner3D.x, flangeInner3D.y - baseFlange, maxZ);
      }
    }

    final flangeA2D = project(flangeInner3D);
    final flangeB2D = project(flangeOuter3D);
    final flangeAnchor = flangeB2D;

    final wBadgePos = Offset((topAnchor.dx - 60).clamp(12.0, viewportSize.width - 150.0), (topAnchor.dy - 44).clamp(38.0, viewportSize.height - 40.0));
    final p2BadgePos = Offset((port2Anchor.dx + 20).clamp(12.0, viewportSize.width - 160.0), (port2Anchor.dy - 35).clamp(38.0, viewportSize.height - 40.0));
    final p3BadgePos = Offset((port3Anchor.dx + 20).clamp(12.0, viewportSize.width - 160.0), (port3Anchor.dy - 35).clamp(38.0, viewportSize.height - 40.0));
    final p4BadgePos = Offset(
      (port4Anchor.dx - 160).clamp(12.0, viewportSize.width - 160.0),
      (port4Anchor.dy - 35).clamp(38.0, viewportSize.height - 40.0),
    );
    final hBadgePos = Offset((rightAnchor.dx + 14).clamp(12.0, viewportSize.width - 140.0), (rightAnchor.dy - 16).clamp(38.0, viewportSize.height - 40.0));
    final sBadgePos = Offset((sAnchor.dx - 180).clamp(12.0, viewportSize.width - 190.0), (sAnchor.dy - 14).clamp(38.0, viewportSize.height - 40.0));
    final fBadgePos = Offset(
      (flangeAnchor.dx - 110).clamp(12.0, viewportSize.width - 210.0),
      (flangeAnchor.dy - 35).clamp(38.0, viewportSize.height - 40.0),
    );
    final tBadgePos = Offset(
      (bottomAnchor.dx - 85).clamp(12.0, viewportSize.width - 200.0),
      (bottomAnchor.dy - 15).clamp(38.0, viewportSize.height - 40.0),
    );

    final leaderLines = <({Offset badgePos, Offset anchorPos, Color color})>[];
    if (_showDimWidth) leaderLines.add((badgePos: Offset(wBadgePos.dx + 55, wBadgePos.dy + 30), anchorPos: topAnchor, color: const Color(0xFF0284C7)));
    if (_showDimPorts && hasMultiplePorts) {
      leaderLines.add((badgePos: Offset(p2BadgePos.dx, p2BadgePos.dy + 14), anchorPos: port2Anchor, color: const Color(0xFF059669)));
    }
    if (_showDimPorts && (isTee || isCross)) {
      leaderLines.add((badgePos: Offset(p3BadgePos.dx, p3BadgePos.dy + 14), anchorPos: port3Anchor, color: const Color(0xFFD97706)));
    }
    if (_showDimPorts && isCross) {
      leaderLines.add((badgePos: Offset(p4BadgePos.dx + 140, p4BadgePos.dy + 14), anchorPos: port4Anchor, color: const Color(0xFF7C3AED)));
    }
    if (_showDimHeight && !hasMultiplePorts) {
      leaderLines.add((badgePos: Offset(hBadgePos.dx, hBadgePos.dy + 14), anchorPos: rightAnchor, color: const Color(0xFF0284C7)));
    }
    if (_showDimSlots) leaderLines.add((badgePos: Offset(sBadgePos.dx + 165, sBadgePos.dy + 14), anchorPos: sAnchor, color: const Color(0xFF7C3AED)));
    if (_showDimFlange) leaderLines.add((badgePos: Offset(fBadgePos.dx + 105, fBadgePos.dy), anchorPos: flangeAnchor, color: const Color(0xFFDB2777)));
    // Note: Gauge tag does NOT need a leader line or dimensional line as requested

    // Compute 2D CAD Dimension Line items projected from 3D geometry
    final center2D = hasMesh ? project(m.center) : Offset(viewportSize.width / 2.0, viewportSize.height / 2.0);

    Offset calcPerpNormal(Offset a, Offset b, Offset center) {
      final diff = b - a;
      final dist = diff.distance;
      if (dist < 1e-4) return const Offset(0, -1);
      var perp = Offset(-diff.dy / dist, diff.dx / dist);
      final mid = Offset((a.dx + b.dx) / 2.0, (a.dy + b.dy) / 2.0);
      final away = mid - center;
      if (perp.dx * away.dx + perp.dy * away.dy < 0) {
        perp = -perp;
      }
      return perp;
    }

    final cadDimensionItems = <DdsCadDimensionItem>[];

    if (_combinePortDimensions) {
      // Combined Joint Port Tags: 1 tag per port showing both W and H together (e.g. PORT 1: 100×100 mm)
      // 1. Port 1 Joint
      if (_showDimWidth || _showDimPorts) {
        final pA = port1Corners != null
            ? project(port1Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x - w1 / 2, minY, maxZ))
                  : Offset(viewportSize.width * 0.35, viewportSize.height * 0.35));
        final pB = port1Corners != null
            ? project(port1Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x + w1 / 2, minY, maxZ))
                  : Offset(viewportSize.width * 0.65, viewportSize.height * 0.35));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'port1_joint',
            label: hasMultiplePorts ? 'PORT 1' : 'SIZE',
            valueText: '${w1.toStringAsFixed(0)}×${h1.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF0284C7),
          ),
        );
      }

      // 2. Port 2 Joint (for Reducer, Unequal Tee, Unequal Cross)
      if (hasMultiplePorts && (_showDimWidth || _showDimPorts)) {
        final pA = port2Corners != null
            ? project(port2Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x - w2 / 2, isReducer ? (maxY - 25.0) : maxY, minZ + h2))
                  : Offset(viewportSize.width * 0.65, viewportSize.height * 0.40));
        final pB = port2Corners != null
            ? project(port2Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x + w2 / 2, isReducer ? (maxY - 25.0) : maxY, minZ + h2))
                  : Offset(viewportSize.width * 0.85, viewportSize.height * 0.40));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'port2_joint',
            label: 'PORT 2',
            valueText: '${w2.toStringAsFixed(0)}×${h2.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF059669),
          ),
        );
      }

      // 3. Port 3 Joint (East / Branch 1 for Tee & Cross)
      if ((isTee || isCross) && (_showDimWidth || _showDimPorts)) {
        final pA = port3Corners != null
            ? project(port3Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(maxX, m.center.y - w3 / 2, minZ + h3))
                  : Offset(viewportSize.width * 0.70, viewportSize.height * 0.65));
        final pB = port3Corners != null
            ? project(port3Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(maxX, m.center.y + w3 / 2, minZ + h3))
                  : Offset(viewportSize.width * 0.85, viewportSize.height * 0.65));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'port3_joint',
            label: 'PORT 3',
            valueText: '${w3.toStringAsFixed(0)}×${h3.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFFD97706),
          ),
        );
      }

      // 4. Port 4 Joint (West / Branch 2 for Cross)
      if (isCross && (_showDimWidth || _showDimPorts)) {
        final pA = port4Corners != null
            ? project(port4Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(minX, m.center.y + w4 / 2, minZ + h4))
                  : Offset(viewportSize.width * 0.25, viewportSize.height * 0.45));
        final pB = port4Corners != null
            ? project(port4Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(minX, m.center.y - w4 / 2, minZ + h4))
                  : Offset(viewportSize.width * 0.15, viewportSize.height * 0.45));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'port4_joint',
            label: 'PORT 4',
            valueText: '${w4.toStringAsFixed(0)}×${h4.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF7C3AED),
          ),
        );
      }
    } else {
      // Separate W and H Dimension Lines
      // 1. Port 1 (Inlet) Width & Height
      final w1Label = hasMultiplePorts ? 'W1' : 'W';
      final h1Label = hasMultiplePorts ? 'H1' : 'H';

      if (_showDimWidth) {
        final pA = port1Corners != null
            ? project(port1Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x - w1 / 2, minY, maxZ))
                  : Offset(viewportSize.width * 0.35, viewportSize.height * 0.35));
        final pB = port1Corners != null
            ? project(port1Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x + w1 / 2, minY, maxZ))
                  : Offset(viewportSize.width * 0.65, viewportSize.height * 0.35));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'width1',
            label: w1Label,
            valueText: '${w1.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF0284C7),
          ),
        );
      }

      if (_showDimHeight) {
        final pA = port1Corners != null
            ? project(port1Corners[3])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x + w1 / 2, minY, minZ))
                  : Offset(viewportSize.width * 0.65, viewportSize.height * 0.65));
        final pB = port1Corners != null
            ? project(port1Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x + w1 / 2, minY, maxZ))
                  : Offset(viewportSize.width * 0.65, viewportSize.height * 0.35));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'height1',
            label: h1Label,
            valueText: '${h1.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF0284C7),
          ),
        );
      }

      // 2. Port 2 (Outlet) Width & Height (for Reducer, Unequal Tee, Unequal Cross)
      if (hasMultiplePorts && (_showDimWidth || _showDimPorts)) {
        final pA = port2Corners != null
            ? project(port2Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x - w2 / 2, isReducer ? (maxY - 25.0) : maxY, minZ + h2))
                  : Offset(viewportSize.width * 0.65, viewportSize.height * 0.40));
        final pB = port2Corners != null
            ? project(port2Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x + w2 / 2, isReducer ? (maxY - 25.0) : maxY, minZ + h2))
                  : Offset(viewportSize.width * 0.85, viewportSize.height * 0.40));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'width2',
            label: 'W2',
            valueText: '${w2.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF0284C7),
          ),
        );
      }

      if (hasMultiplePorts && (_showDimHeight || _showDimPorts)) {
        final pA = port2Corners != null
            ? project(port2Corners[0])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x - w2 / 2, isReducer ? (maxY - 25.0) : maxY, minZ))
                  : Offset(viewportSize.width * 0.35, viewportSize.height * 0.60));
        final pB = port2Corners != null
            ? project(port2Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(m.center.x - w2 / 2, isReducer ? (maxY - 25.0) : maxY, minZ + h2))
                  : Offset(viewportSize.width * 0.35, viewportSize.height * 0.40));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'height2',
            label: 'H2',
            valueText: '${h2.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF0284C7),
          ),
        );
      }

      // 3. Port 3 (East / Branch 1) Width & Height (for Tee & Cross)
      if ((isTee || isCross) && (_showDimWidth || _showDimPorts)) {
        final pA = port3Corners != null
            ? project(port3Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(maxX, m.center.y - w3 / 2, minZ + h3))
                  : Offset(viewportSize.width * 0.70, viewportSize.height * 0.65));
        final pB = port3Corners != null
            ? project(port3Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(maxX, m.center.y + w3 / 2, minZ + h3))
                  : Offset(viewportSize.width * 0.85, viewportSize.height * 0.65));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'width3',
            label: 'W3',
            valueText: '${w3.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFFD97706),
          ),
        );
      }

      if ((isTee || isCross) && (_showDimHeight || _showDimPorts)) {
        final pA = port3Corners != null
            ? project(port3Corners[0])
            : (hasMesh
                  ? project(CadPoint3D(maxX, m.center.y - w3 / 2, minZ))
                  : Offset(viewportSize.width * 0.70, viewportSize.height * 0.75));
        final pB = port3Corners != null
            ? project(port3Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(maxX, m.center.y - w3 / 2, minZ + h3))
                  : Offset(viewportSize.width * 0.70, viewportSize.height * 0.65));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'height3',
            label: 'H3',
            valueText: '${h3.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFFD97706),
          ),
        );
      }

      // 4. Port 4 (West / Branch 2) Width & Height (for Cross)
      if (isCross && (_showDimWidth || _showDimPorts)) {
        final pA = port4Corners != null
            ? project(port4Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(minX, m.center.y + w4 / 2, minZ + h4))
                  : Offset(viewportSize.width * 0.25, viewportSize.height * 0.45));
        final pB = port4Corners != null
            ? project(port4Corners[2])
            : (hasMesh
                  ? project(CadPoint3D(minX, m.center.y - w4 / 2, minZ + h4))
                  : Offset(viewportSize.width * 0.15, viewportSize.height * 0.45));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'width4',
            label: 'W4',
            valueText: '${w4.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF7C3AED),
          ),
        );
      }

      if (isCross && (_showDimHeight || _showDimPorts)) {
        final pA = port4Corners != null
            ? project(port4Corners[0])
            : (hasMesh
                  ? project(CadPoint3D(minX, m.center.y + w4 / 2, minZ))
                  : Offset(viewportSize.width * 0.25, viewportSize.height * 0.55));
        final pB = port4Corners != null
            ? project(port4Corners[1])
            : (hasMesh
                  ? project(CadPoint3D(minX, m.center.y + w4 / 2, minZ + h4))
                  : Offset(viewportSize.width * 0.25, viewportSize.height * 0.45));
        final norm = calcPerpNormal(pA, pB, center2D);
        cadDimensionItems.add(
          DdsCadDimensionItem(
            id: 'height4',
            label: 'H4',
            valueText: '${h4.toStringAsFixed(0)} mm',
            p1: pA,
            p2: pB,
            offsetVector: norm * 14.0,
            color: const Color(0xFF7C3AED),
          ),
        );
      }
    }

    // 5. Coupler Slots Dimension Line (Anchored directly on the coupler flap)
    if (_showDimSlots) {
      final pA = hasMesh ? project(slotP1_3D) : Offset(viewportSize.width * 0.26, viewportSize.height * 0.58);
      final pB = hasMesh ? project(slotP2_3D) : Offset(viewportSize.width * 0.26, viewportSize.height * 0.46);
      final norm = calcPerpNormal(pA, pB, center2D);
      cadDimensionItems.add(
        DdsCadDimensionItem(
          id: 'slots',
          label: 'SLOTS',
          valueText: '${slotL.toStringAsFixed(0)}×${slotW.toStringAsFixed(1)} @ ${slotP.toStringAsFixed(0)}P',
          p1: pA,
          p2: pB,
          offsetVector: norm * 14.0,
          color: const Color(0xFF7C3AED),
        ),
      );
    }

    // 6. Flange Dimension Line (Accurately anchored on physical flange)
    if (_showDimFlange) {
      final norm = calcPerpNormal(flangeA2D, flangeB2D, center2D);
      cadDimensionItems.add(
        DdsCadDimensionItem(
          id: 'flange',
          label: 'FLANGE',
          valueText: isCoverActive
              ? '${baseFlange.toStringAsFixed(0)}mm (Cover ${coverFlange.toStringAsFixed(0)}mm)'
              : '${baseFlange.toStringAsFixed(0)}mm ($flangeDir)',
          p1: flangeA2D,
          p2: flangeB2D,
          offsetVector: norm * 12.0,
          color: const Color(0xFFDB2777),
        ),
      );
    }
    // Note: Gauge tag does NOT need a dimensional line as requested

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // CAD Witness & Dimension Lines Anchored to 3D Model (Engineering 2D Sketch Style)
        if (_showCadDimensionLines && cadDimensionItems.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _Dds3DCadDimensionLinesPainter(items: cadDimensionItems)),
            ),
          ),

        // Leader Lines for Callout Badges
        if (_showDimensionTags && leaderLines.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _Dds3DLeaderLinesPainter(lines: leaderLines)),
            ),
          ),

        // 3D Dimension Callout Badges Anchored at the Model (User Option: Tags)
        if (_showDimensionTags) ...[
          // 1. Port 1 Dimension Callout
          if (_showDimWidth)
            Positioned(
              left: wBadgePos.dx,
              top: wBadgePos.dy,
              child: _buildDimCalloutBadge(
                label: hasMultiplePorts ? 'PORT 1 (INLET)' : (_combinePortDimensions ? 'SIZE (W×H)' : 'WIDTH (W)'),
                value: hasMultiplePorts || _combinePortDimensions
                    ? '${w1.toStringAsFixed(0)}×${h1.toStringAsFixed(0)} mm'
                    : '${w1.toStringAsFixed(0)} mm',
                accentColor: const Color(0xFF0284C7),
                icon: Icons.straighten,
                onDismiss: () {
                  setState(() => _showDimWidth = false);
                  widget.onDimensionToggled?.call('W', false);
                },
              ),
            ),

          // 2. Port 2 Dimension Callout (for Reducer, Tee, Cross)
          if (hasMultiplePorts && (_showDimPorts || _showDimWidth))
            Positioned(
              left: p2BadgePos.dx,
              top: p2BadgePos.dy,
              child: _buildDimCalloutBadge(
                label: 'PORT 2 (OUTLET)',
                value: '${w2.toStringAsFixed(0)}×${h2.toStringAsFixed(0)} mm',
                accentColor: const Color(0xFF059669),
                icon: Icons.filter_frames,
                onDismiss: () {
                  setState(() => _showDimPorts = false);
                  widget.onDimensionToggled?.call('Ports', false);
                },
              ),
            ),

          // 2b. Port 3 Dimension Callout (for Tee & Cross)
          if ((isTee || isCross) && (_showDimPorts || _showDimWidth))
            Positioned(
              left: p3BadgePos.dx,
              top: p3BadgePos.dy,
              child: _buildDimCalloutBadge(
                label: 'PORT 3 (BRANCH 1)',
                value: '${w3.toStringAsFixed(0)}×${h3.toStringAsFixed(0)} mm',
                accentColor: const Color(0xFFD97706),
                icon: Icons.alt_route,
                onDismiss: () {
                  setState(() => _showDimPorts = false);
                  widget.onDimensionToggled?.call('Ports', false);
                },
              ),
            ),

          // 2c. Port 4 Dimension Callout (for Cross)
          if (isCross && (_showDimPorts || _showDimWidth))
            Positioned(
              left: p4BadgePos.dx,
              top: p4BadgePos.dy,
              child: _buildDimCalloutBadge(
                label: 'PORT 4 (BRANCH 2)',
                value: '${w4.toStringAsFixed(0)}×${h4.toStringAsFixed(0)} mm',
                accentColor: const Color(0xFF7C3AED),
                icon: Icons.alt_route,
                onDismiss: () {
                  setState(() => _showDimPorts = false);
                  widget.onDimensionToggled?.call('Ports', false);
                },
              ),
            ),

          // 3. Height Dimension Callout (for single port fitting in split mode)
          if (!hasMultiplePorts && _showDimHeight && !_combinePortDimensions)
            Positioned(
              left: hBadgePos.dx,
              top: hBadgePos.dy,
              child: _buildDimCalloutBadge(
                label: 'HEIGHT (H)',
                value: '${h1.toStringAsFixed(0)} mm',
                accentColor: const Color(0xFF0284C7),
                icon: Icons.height,
                onDismiss: () {
                  setState(() => _showDimHeight = false);
                  widget.onDimensionToggled?.call('H', false);
                },
              ),
            ),

          // 4. Coupler Slot Specification Callout (Anchored on the coupler flap)
          if (_showDimSlots)
            Positioned(
              left: sBadgePos.dx,
              top: sBadgePos.dy,
              child: _buildDimCalloutBadge(
                label: 'COUPLER SLOTS',
                value: '${slotL.toStringAsFixed(0)}×${slotW.toStringAsFixed(1)} @ ${slotP.toStringAsFixed(0)}P',
                accentColor: const Color(0xFF7C3AED),
                icon: Icons.drag_indicator,
                onDismiss: () {
                  setState(() => _showDimSlots = false);
                  widget.onDimensionToggled?.call('Slots', false);
                },
              ),
            ),

          // 5. Flange Direction & Size Callout (Linked cover flange omitted when cover is off)
          if (_showDimFlange)
            Positioned(
              left: fBadgePos.dx,
              top: fBadgePos.dy,
              child: _buildDimCalloutBadge(
                label: isCoverActive ? 'BASE & COVER FLANGE' : 'BASE FLANGE',
                value: isCoverActive
                    ? '$flangeDir (${baseFlange.toStringAsFixed(0)}mm)  |  Cover: ${coverFlange.toStringAsFixed(0)}mm'
                    : '$flangeDir (${baseFlange.toStringAsFixed(0)}mm)',
                accentColor: const Color(0xFFDB2777),
                icon: Icons.crop_square,
                onDismiss: () {
                  setState(() => _showDimFlange = false);
                  widget.onDimensionToggled?.call('Flange', false);
                },
              ),
            ),

          // 6. Gauge / Sheet Thickness Callout (Bottom Floor of 3D Model)
          if (_showDimThickness)
            Positioned(
              left: tBadgePos.dx,
              top: tBadgePos.dy,
              child: _buildDimCalloutBadge(
                label: 'SHEET THICKNESS / GAUGE',
                value: '${thickness.toStringAsFixed(1)} mm (Pre-Galv DX51D)',
                accentColor: const Color(0xFF4F46E5),
                icon: Icons.layers,
                onDismiss: () {
                  setState(() => _showDimThickness = false);
                  widget.onDimensionToggled?.call('Gauge', false);
                },
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildDimCalloutBadge({
    required String label,
    required String value,
    required Color accentColor,
    required IconData icon,
    required VoidCallback onDismiss,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: const Color(0xEBFFFFFF), // 92% opaque frosted white glass
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withValues(alpha: 0.40), width: 1.1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2)),
          BoxShadow(color: accentColor.withValues(alpha: 0.12), blurRadius: 5, spreadRadius: 0.5),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3.5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 0.7),
            ),
            child: Icon(icon, size: 12, color: accentColor),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(color: accentColor, fontSize: 7.8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              Text(
                value,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 9.2, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0), width: 0.6),
              ),
              child: const Icon(Icons.close, size: 9.5, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductBottomDock(DdsProductInstance? inst, EvaluatedDdsInstance? eval) {
    final proj = widget.document.projectInfo;
    final takeoff = eval?.calculatedTakeoff ?? inst?.calculatedTakeoff;
    final orderLine = inst?.orderLine;
    final cmsLive = (widget.viewModel?.document.metadata['cmsParameters'] as Map<String, dynamic>?) ?? {};
    final p = Map<String, dynamic>.from(inst?.instanceParameters ?? {})..addAll(cmsLive);
    if (widget.viewModel != null) {
      p['thickness'] = widget.viewModel!.document.material.thicknessMm;
    }

    // Dynamic port specification string
    final physicalPorts = (eval?.scaledPorts.isNotEmpty == true) ? eval!.scaledPorts : (widget.viewModel?.verifiedCmsPorts ?? []);
    final p1 = physicalPorts.isNotEmpty ? physicalPorts[0] : null;
    final p2 = physicalPorts.length > 1 ? physicalPorts[1] : null;
    final p3 = physicalPorts.length > 2 ? physicalPorts[2] : null;
    final p4 = physicalPorts.length > 3 ? physicalPorts[3] : null;

    final tId = (inst?.templateReference.templateId ?? '').toLowerCase();
    String portSpecsStr;
    if (tId.contains('reducer')) {
      final w1 = (p['port1_width'] ?? p1?.nominalWidth ?? 100.0).toStringAsFixed(0);
      final h1 = (p['port1_height'] ?? p1?.nominalHeight ?? 100.0).toStringAsFixed(0);
      final w2 = (p['port2_width'] ?? p2?.nominalWidth ?? 50.0).toStringAsFixed(0);
      final h2 = (p['port2_height'] ?? p2?.nominalHeight ?? 50.0).toStringAsFixed(0);
      portSpecsStr = 'P1 (Inlet): $w1×$h1 mm  |  P2 (Outlet): $w2×$h2 mm';
    } else if (tId.contains('cross')) {
      if (tId.contains('unequal')) {
        final w1 = (p['port1_width'] ?? p1?.nominalWidth ?? 100.0).toStringAsFixed(0);
        final h1 = (p['port1_height'] ?? p1?.nominalHeight ?? 100.0).toStringAsFixed(0);
        final w2 = (p['port2_width'] ?? p2?.nominalWidth ?? 100.0).toStringAsFixed(0);
        final h2 = (p['port2_height'] ?? p2?.nominalHeight ?? 100.0).toStringAsFixed(0);
        final w3 = (p['port3_width'] ?? p3?.nominalWidth ?? 50.0).toStringAsFixed(0);
        final h3 = (p['port3_height'] ?? p3?.nominalHeight ?? 50.0).toStringAsFixed(0);
        final w4 = (p['port4_width'] ?? p4?.nominalWidth ?? 50.0).toStringAsFixed(0);
        final h4 = (p['port4_height'] ?? p4?.nominalHeight ?? 50.0).toStringAsFixed(0);
        portSpecsStr = 'P1: $w1×$h1  |  P2: $w2×$h2  |  P3: $w3×$h3  |  P4: $w4×$h4 mm';
      } else {
        final w = (p['width'] ?? p1?.nominalWidth ?? p['port1_width'] ?? 100.0).toStringAsFixed(0);
        final h = (p['height'] ?? p1?.nominalHeight ?? p['port1_height'] ?? 100.0).toStringAsFixed(0);
        portSpecsStr = '4 Ports (Equal Cross): $w×$h mm';
      }
    } else if (tId.contains('tee')) {
      if (tId.contains('unequal')) {
        final w1 = (p['port1_width'] ?? p1?.nominalWidth ?? 100.0).toStringAsFixed(0);
        final h1 = (p['port1_height'] ?? p1?.nominalHeight ?? 100.0).toStringAsFixed(0);
        final w3 = (p['port3_width'] ?? p['branch_width'] ?? p3?.nominalWidth ?? 50.0).toStringAsFixed(0);
        final h3 = (p['port3_height'] ?? p['branch_height'] ?? p3?.nominalHeight ?? 50.0).toStringAsFixed(0);
        portSpecsStr = 'Main Trunk (P1 & P2): $w1×$h1 mm  |  Branch (P3): $w3×$h3 mm';
      } else {
        final w = (p['width'] ?? p1?.nominalWidth ?? p['port1_width'] ?? 100.0).toStringAsFixed(0);
        final h = (p['height'] ?? p1?.nominalHeight ?? p['port1_height'] ?? 100.0).toStringAsFixed(0);
        portSpecsStr = '3 Ports (Equal Tee): $w×$h mm';
      }
    } else {
      final w = (p['width'] ?? p['port1_width'] ?? 100.0).toStringAsFixed(0);
      final h = (p['height'] ?? p['port1_height'] ?? 100.0).toStringAsFixed(0);
      final angle = tId.contains('45') ? '45°' : '90°';
      portSpecsStr = 'Trunking Mouth: $w×$h mm  |  Angle: $angle';
    }

    final baseFlange = (p['base_flange_size'] ?? 20.0).toStringAsFixed(0);
    final flangeDir = (p['flange_direction'] ?? 0.0) == 0.0 ? 'Inside Flange' : 'Outside Return';
    final coverFlange = (inst?.coverConfiguration.flangeDepthMm ?? p['cover_flange_size'] ?? 15.0).toStringAsFixed(0);
    final slotW = (p['coupler_slot_width'] ?? 9.0).toStringAsFixed(1);
    final slotL = (p['coupler_slot_length'] ?? 20.0).toStringAsFixed(0);
    final slotP = (p['coupler_slot_pitch'] ?? 25.0).toStringAsFixed(0);
    final thickness = (p['thickness'] ?? 1.5).toStringAsFixed(1);
    final qty = orderLine?.quantity ?? 1;

    final effectiveVm = _sheetViewModel ?? widget.viewModel;
    final isCoverActive =
        (effectiveVm?.isCoverVisible3D ?? true) &&
        (inst?.coverConfiguration.included == true || effectiveVm?.document.cover != null || effectiveVm?.coverMesh != null);

    // Compute base and cover takeoff areas & weights dynamically
    final baseDoc = eval?.scaledBaseDocument ?? (effectiveVm?.document);
    double baseAreaM2 = 0.0;
    if (baseDoc != null && baseDoc.faces.isNotEmpty) {
      for (final f in baseDoc.faces) {
        baseAreaM2 += f.areaMm2.abs() / 1e6;
      }
    }
    final coverDoc = eval?.coverData?.document ?? (effectiveVm?.document.cover);
    double coverAreaM2 = 0.0;
    if (coverDoc is DsfDocument && coverDoc.faces.isNotEmpty) {
      for (final f in coverDoc.faces) {
        coverAreaM2 += f.areaMm2.abs() / 1e6;
      }
    }

    final double thkVal = double.tryParse(thickness) ?? 1.5;
    final activeMaterial = inst?.material ?? effectiveVm?.document.material.materialGrade ?? 'Pre-Galv DX51D';
    final activeDensity = DdsInstanceEvaluator.resolveDensity(activeMaterial);
    double baseMassKg = baseAreaM2 > 0 ? (baseAreaM2 * (thkVal / 1000.0) * activeDensity) : (0.64 * (activeDensity / 7850.0));
    double coverMassKg = coverAreaM2 > 0 ? (coverAreaM2 * (thkVal / 1000.0) * activeDensity) : (0.20 * (activeDensity / 7850.0));

    if (baseAreaM2 == 0.0 && takeoff != null) {
      final dynWeight = takeoff.blankSurfaceAreaM2 * (thkVal / 1000.0) * activeDensity;
      if (isCoverActive) {
        baseMassKg = dynWeight * 0.75;
        coverMassKg = dynWeight * 0.25;
        baseAreaM2 = takeoff.blankSurfaceAreaM2 * 0.75;
        coverAreaM2 = takeoff.blankSurfaceAreaM2 * 0.25;
      } else {
        baseMassKg = dynWeight;
        baseAreaM2 = takeoff.blankSurfaceAreaM2;
      }
    }

    final double activeTotalUnitMass = isCoverActive ? (baseMassKg + coverMassKg) : baseMassKg;
    final double activeTotalBlankArea = isCoverActive ? (baseAreaM2 + coverAreaM2) : baseAreaM2;
    final double activeLineTotalMass = activeTotalUnitMass * qty;

    final blankAreaStr = '${activeTotalBlankArea.toStringAsFixed(3)} m²';
    final netMassStr = '${activeTotalUnitMass.toStringAsFixed(2)} kg';
    final lineTotalMassStr = '${activeLineTotalMass.toStringAsFixed(2)} kg';

    final desDate = proj.effectiveDesignedDate;
    final drwDate = proj.effectiveDrawnDate;
    final chkDate = proj.effectiveCheckedDate;
    final appDate = proj.effectiveApprovedDate;

    return Container(
      height: 154,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===================================================================
          // Section 1: Tabular Part Specifications & Displayed Items Schedule
          // ===================================================================
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Header Strip
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.5),
                    decoration: const BoxDecoration(color: Color(0xFF0F172A)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SCHEDULE OF DISPLAYED ITEMS / BILL OF MATERIALS (LINE ${orderLine?.lineNumber ?? "001"})',
                          style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
                        ),
                        Text(
                          'PO: ${orderLine?.orderNumber.isNotEmpty == true ? orderLine!.orderNumber : "PO-88210"}  |  QTY: $qty PCS  |  REF: ${orderLine?.customerItemReference.isNotEmpty == true ? orderLine!.customerItemReference : (inst?.productCode ?? "RED-150-75")}',
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                        ),
                      ],
                    ),
                  ),

                  // Table of Displayed Items
                  Table(
                    border: TableBorder.all(color: const Color(0xFFCBD5E1), width: 0.8),
                    columnWidths: const {
                      0: FixedColumnWidth(28), // ITM
                      1: FlexColumnWidth(2.2), // COMPONENT
                      2: FlexColumnWidth(4.6), // SPECS / PORTS / FLANGE
                      3: FlexColumnWidth(2.4), // MATERIAL & FINISH
                      4: FixedColumnWidth(44), // THK
                      5: FixedColumnWidth(40), // QTY
                      6: FixedColumnWidth(54), // UNIT WT
                    },
                    children: [
                      // Header Row
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                        children: [
                          _buildTableHeaderCell('ITM', align: TextAlign.center),
                          _buildTableHeaderCell('COMPONENT / PART'),
                          _buildTableHeaderCell('SPECIFICATIONS / PORTS / FLANGE'),
                          _buildTableHeaderCell('MATERIAL & FINISH'),
                          _buildTableHeaderCell('THK', align: TextAlign.center),
                          _buildTableHeaderCell('QTY', align: TextAlign.center),
                          _buildTableHeaderCell('UNIT WT', align: TextAlign.right),
                        ],
                      ),
                      // Row 1: Base Fitting
                      TableRow(
                        children: [
                          _buildTableCell('01', isBold: true, align: TextAlign.center),
                          _buildTableCell(inst?.productName ?? 'Base Fitting', isBold: true),
                          _buildTableCell('$portSpecsStr  |  Base Flange: ${baseFlange}mm ($flangeDir)  |  Slots: $slotW×$slotL@${slotP}P'),
                          _buildTableCell('${inst?.material ?? "Pre-Galv DX51D"} ${inst?.finish ?? "Z275"}'),
                          _buildTableCell('$thickness mm', align: TextAlign.center),
                          _buildTableCell('$qty', align: TextAlign.center),
                          _buildTableCell('${baseMassKg.toStringAsFixed(2)} kg', align: TextAlign.right),
                        ],
                      ),
                      // Row 2: Companion Cover (Rendered when cover is active)
                      if (isCoverActive)
                        TableRow(
                          decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                          children: [
                            _buildTableCell('02', isBold: true, align: TextAlign.center),
                            _buildTableCell(
                              'Companion Cover (${inst?.coverConfiguration.placementMode3D == 'exploded' ? 'Exploded' : 'Top Fitted'})',
                              isBold: true,
                            ),
                            _buildTableCell('Cover Flange: ${coverFlange}mm Return  |  Contour Matched Cover Plate'),
                            _buildTableCell('${inst?.material ?? "Pre-Galv DX51D"} ${inst?.finish ?? "Z275"}'),
                            _buildTableCell('$thickness mm', align: TextAlign.center),
                            _buildTableCell('$qty', align: TextAlign.center),
                            _buildTableCell('${coverMassKg.toStringAsFixed(2)} kg', align: TextAlign.right),
                          ],
                        ),
                      // Row 3: Companion Fasteners (Rendered when fasteners are toggled on)
                      if (_showFasteners3D)
                        TableRow(
                          decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                          children: [
                            _buildTableCell('03', isBold: true, align: TextAlign.center),
                            _buildTableCell('Fixing Fasteners (M6 Flange Bolt & Nut)', isBold: true),
                            _buildTableCell('4× M6×16 Hex Serrated Screws + M6 Flange Nuts @ Coupler Ports'),
                            _buildTableCell('A2-70 Stainless Steel / BZP'),
                            _buildTableCell('M6', align: TextAlign.center),
                            _buildTableCell('${qty * 4}', align: TextAlign.center),
                            _buildTableCell('0.04 kg', align: TextAlign.right),
                          ],
                        ),
                    ],
                  ),

                  // Footer Strip: Takeoff Summary
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(top: BorderSide(color: Color(0xFFCBD5E1), width: 0.8)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL BLANK AREA: $blankAreaStr  |  UNIT NET MASS: $netMassStr  |  LINE TOTAL: $lineTotalMassStr',
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const Text(
                          'STD: BS EN 61537:2007',
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const VerticalDivider(width: 1, thickness: 1.0, color: Color(0xFF0F172A)),

          // ===================================================================
          // Section 2: General Tolerances & Engineering Sign-Off Table
          // ===================================================================
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Tolerance Band
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                    color: const Color(0xFFF1F5F9),
                    child: const Text(
                      'GENERAL TOLERANCE (ISO 2768-m):  ≤30: ±0.5  |  30-120: ±0.8  |  >120: ±1.2 mm  |  ANG: ±0.5°',
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                    ),
                  ),

                  // 4-Row Quality Sign-off Grid
                  Table(
                    border: TableBorder.all(color: const Color(0xFFCBD5E1), width: 0.6),
                    columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(4.0), 2: FlexColumnWidth(2.8)},
                    children: [
                      _buildSignOffRow('DESIGNED', proj.designedBy, desDate, () => _pickSignOffDate('DESIGNED', desDate)),
                      _buildSignOffRow('DRAWN', proj.drawnBy, drwDate, () => _pickSignOffDate('DRAWN', drwDate)),
                      _buildSignOffRow('CHECKED', proj.checkedBy, chkDate, () => _pickSignOffDate('CHECKED', chkDate)),
                      _buildSignOffRow('APPROVED', proj.approvedBy, appDate, () => _pickSignOffDate('APPROVED', appDate)),
                    ],
                  ),

                  // Material / Mass row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MATERIAL: ASTM A36 / DX51D',
                        style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                      Text(
                        'MASS: $netMassStr',
                        style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'STATUS: ${proj.status.toUpperCase()}',
                        style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const VerticalDivider(width: 1, thickness: 1.2, color: Color(0xFF0F172A)),

          // ===================================================================
          // Section 3: ISO 7200 Title Block & 3rd Angle Projection
          // ===================================================================
          SizedBox(
            width: 300,
            child: Column(
              children: [
                // Top: Projection Symbol & Doc Title
                Expanded(
                  flex: 3,
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                    child: Row(
                      children: [
                        // 3rd Angle Projection Symbol
                        SizedBox(
                          width: 48,
                          height: 26,
                          child: CustomPaint(painter: _ProjectionSymbolPainter(color: const Color(0xFF0F172A))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                proj.documentNumber,
                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                              ),
                              Text(
                                inst?.productName ?? proj.documentTitle,
                                style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF0F172A)),

                // Middle: Project & Client
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'PROJECT: ${proj.projectName.isNotEmpty ? proj.projectName : "Hospital CMS Fitting"}',
                                style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'CLIENT: ${proj.client.isNotEmpty ? proj.client : "Standard"}',
                                style: const TextStyle(fontSize: 8.5, color: Color(0xFF64748B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFF0284C7).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                          child: Text(
                            'REV ${proj.revision}',
                            style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF0F172A)),

                // Bottom: Engineering Controls & Sheet Number
                Expanded(
                  flex: 3,
                  child: Container(
                    color: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SCALE: NTS  |  SIZE: A4  |  UNIT: MM',
                          style: TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.verified, size: 12, color: Color(0xFF00E5FF)),
                            const SizedBox(width: 4),
                            Text(
                              'SHEET ${widget.sheet.sheetNumber} OF ${widget.document.totalSheets}',
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 3.5),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Color(0xFF334155), letterSpacing: 0.2),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isBold = false, TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 3.0),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(fontSize: 9.0, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: const Color(0xFF0F172A)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _pickSignOffDate(String role, String currentDate) async {
    DateTime initialDate = DateTime.now();
    try {
      if (currentDate.contains('/')) {
        final parts = currentDate.split('/');
        if (parts.length == 3) {
          initialDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        }
      } else if (currentDate.contains('-')) {
        initialDate = DateTime.parse(currentDate);
      }
    } catch (_) {}

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF0F172A), onPrimary: Colors.white, surface: Colors.white, onSurface: Color(0xFF0F172A)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && widget.onProjectInfoChanged != null) {
      final day = picked.day.toString().padLeft(2, '0');
      final month = picked.month.toString().padLeft(2, '0');
      final formatted = '$day/$month/${picked.year}';
      final proj = widget.document.projectInfo;
      switch (role) {
        case 'DESIGNED':
          widget.onProjectInfoChanged!(proj.copyWith(designedDate: formatted));
          break;
        case 'DRAWN':
          widget.onProjectInfoChanged!(proj.copyWith(drawnDate: formatted));
          break;
        case 'CHECKED':
          widget.onProjectInfoChanged!(proj.copyWith(checkedDate: formatted));
          break;
        case 'APPROVED':
          widget.onProjectInfoChanged!(proj.copyWith(approvedDate: formatted));
          break;
      }
    }
  }

  TableRow _buildSignOffRow(String role, String name, String date, [VoidCallback? onDateTap]) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: Text(
            role,
            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: Text(
            name.isNotEmpty ? name : '—',
            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        InkWell(
          onTap: onDateTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    date.isNotEmpty ? date : '—',
                    style: const TextStyle(fontSize: 8.0, color: Color(0xFF0284C7), fontWeight: FontWeight.w500),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.onProjectInfoChanged != null) const Icon(Icons.edit_calendar, size: 9, color: Color(0xFF0284C7)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 7.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 1.0),
        Text(
          value.isNotEmpty ? value : '—',
          style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
        ),
      ],
    );
  }

  static const TextStyle _tocHeaderStyle = TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF475569));

  static const TextStyle _tocRowStyle = TextStyle(fontSize: 8.5, color: Color(0xFF334155));

  static const TextStyle _tocRowStyleBold = TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A));
}

// =============================================================================
// 3. Technical Sheet Annotation Overlay Painter
// =============================================================================

class _DdsAnnotationOverlayPainter extends CustomPainter {
  final List<DdsAnnotation> annotations;
  final String? selectedAnnotationId;
  final String? selectedArrowId;
  final Size paperSize;
  final CadPoint2D? pendingStartPoint;
  final CadPoint2D? hoverPoint;
  final List<CadPoint2D> pendingCloudPoints;
  final DdsMarkupTool activeTool;

  _DdsAnnotationOverlayPainter({
    required this.annotations,
    this.selectedAnnotationId,
    this.selectedArrowId,
    required this.paperSize,
    this.pendingStartPoint,
    this.hoverPoint,
    required this.pendingCloudPoints,
    required this.activeTool,
  });

  Offset _toPixel(CadPoint2D mm) {
    return Offset((mm.x / 297.0) * paperSize.width, (mm.y / 210.0) * paperSize.height);
  }

  static Color _parseColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final lower = hex.trim().toLowerCase();
    if (lower == 'transparent' || lower == 'none') return Colors.transparent;
    try {
      String clean = lower.replaceAll('#', '');
      if (clean.length == 6) clean = 'ff$clean';
      if (clean.length == 8) return Color(int.parse(clean, radix: 16));
    } catch (_) {}
    return fallback;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Committed Annotations
    for (final ann in annotations) {
      if (!ann.isVisible) continue;
      final isSelected = ann.id == selectedAnnotationId;

      if (ann is DdsLinearDimensionAnnotation) {
        _paintLinearDimension(canvas, ann, isSelected);
      } else if (ann is DdsLeaderNoteAnnotation) {
        _paintLeaderNote(canvas, ann, isSelected);
      } else if (ann is DdsNoteBoxAnnotation) {
        _paintNoteBox(canvas, ann, isSelected);
      } else if (ann is DdsRevisionCloudAnnotation) {
        _paintRevisionCloud(canvas, ann, isSelected);
      } else if (ann is DdsApprovalStampAnnotation) {
        _paintApprovalStamp(canvas, ann, isSelected);
      }
    }

    // 1b. Draw Selection & Resize Handles for Active Annotation
    if (selectedAnnotationId != null) {
      final selAnn = annotations.cast<DdsAnnotation?>().firstWhere((a) => a?.id == selectedAnnotationId, orElse: () => null);
      if (selAnn != null && selAnn.isVisible) {
        _paintSelectionAndHandles(canvas, selAnn);
      }
    }

    // 2. Draw Interactive Rubber-Band Previews
    if (pendingStartPoint != null && hoverPoint != null) {
      final p1 = _toPixel(pendingStartPoint!);
      final p2 = _toPixel(hoverPoint!);

      if (activeTool == DdsMarkupTool.linearDimension) {
        final previewPaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, previewPaint);
        _drawArrowhead(canvas, p2, p1, const Color(0xFF0284C7));
        _drawArrowhead(canvas, p1, p2, const Color(0xFF0284C7));

        final distMm = (pendingStartPoint! - hoverPoint!).length;
        _drawTextBadge(canvas, (p1 + p2) / 2, '${distMm.toStringAsFixed(1)} mm', isSelected: true);
      } else if (activeTool == DdsMarkupTool.leaderNote) {
        final previewPaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, previewPaint);
        _drawArrowhead(canvas, p1, p2, const Color(0xFF0284C7)); // Arrow at target
      }
    }

    // Revision Cloud in-progress points
    if (pendingCloudPoints.isNotEmpty) {
      final cloudPaint = Paint()
        ..color = const Color(0xFFEF4444)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;

      final path = Path();
      final pFirst = _toPixel(pendingCloudPoints.first);
      path.moveTo(pFirst.dx, pFirst.dy);
      for (int i = 1; i < pendingCloudPoints.length; i++) {
        final p = _toPixel(pendingCloudPoints[i]);
        path.lineTo(p.dx, p.dy);
      }
      if (hoverPoint != null) {
        final pHover = _toPixel(hoverPoint!);
        path.lineTo(pHover.dx, pHover.dy);
      }
      canvas.drawPath(path, cloudPaint);
    }
  }

  void _paintSelectionAndHandles(Canvas canvas, DdsAnnotation ann) {
    const handleBorder = Color(0xFF0284C7);
    const handleFill = Colors.white;
    const handleRadius = 4.0;
    final handlePaint = Paint()
      ..color = handleFill
      ..style = PaintingStyle.fill;
    final handleStroke = Paint()
      ..color = handleBorder
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    void drawHandle(Offset pt) {
      canvas.drawCircle(pt, handleRadius, handlePaint);
      canvas.drawCircle(pt, handleRadius, handleStroke);
    }

    if (ann is DdsNoteBoxAnnotation) {
      final rect = Rect.fromLTWH(
        (ann.x / 297.0) * paperSize.width,
        (ann.y / 210.0) * paperSize.height,
        (ann.width / 297.0) * paperSize.width,
        (ann.height / 210.0) * paperSize.height,
      );
      final boxOutline = Paint()
        ..color = const Color(0xFF0284C7).withValues(alpha: 0.7)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect.inflate(2.0), boxOutline);

      // 4 corner resize handles
      drawHandle(rect.topLeft);
      drawHandle(rect.topRight);
      drawHandle(rect.bottomLeft);
      drawHandle(rect.bottomRight);

      // Arrow spawn handles on the 4 border midpoints
      final spawnMidpoints = [
        Offset(rect.center.dx, rect.top),
        Offset(rect.center.dx, rect.bottom),
        Offset(rect.left, rect.center.dy),
        Offset(rect.right, rect.center.dy),
      ];
      for (final sp in spawnMidpoints) {
        const spawnR = 4.5;
        canvas.drawCircle(
          sp,
          spawnR,
          Paint()
            ..color = const Color(0xFFEA580C)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          sp,
          spawnR,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke,
        );
        final plusPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(sp - const Offset(2.5, 0), sp + const Offset(2.5, 0), plusPaint);
        canvas.drawLine(sp - const Offset(0, 2.5), sp + const Offset(0, 2.5), plusPaint);
      }

      // Existing arrows: root handle on border, tip diamond handle, and delete button if selected
      for (final arrow in ann.arrows) {
        final isSelectedArrow = arrow.id == selectedArrowId;
        final rootMm = arrow.root ?? _getNearestBorderPoint(arrow.tip, ann);
        final rootPx = _toPixel(rootMm);
        final tipPx = _toPixel(arrow.tip);

        // Root handle on border (small orange circle)
        canvas.drawCircle(
          rootPx,
          3.5,
          Paint()
            ..color = const Color(0xFFEA580C)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          rootPx,
          3.5,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke,
        );

        // Tip handle: diamond shape
        final r = isSelectedArrow ? 6.5 : 5.0;
        final diamondPath = Path()
          ..moveTo(tipPx.dx, tipPx.dy - r)
          ..lineTo(tipPx.dx + r, tipPx.dy)
          ..lineTo(tipPx.dx, tipPx.dy + r)
          ..lineTo(tipPx.dx - r, tipPx.dy)
          ..close();
        canvas.drawPath(
          diamondPath,
          Paint()
            ..color = isSelectedArrow ? const Color(0xFFF59E0B) : const Color(0xFFEA580C)
            ..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          diamondPath,
          Paint()
            ..color = Colors.white
            ..strokeWidth = isSelectedArrow ? 1.6 : 1.2
            ..style = PaintingStyle.stroke,
        );

        // Delete button near tip if selected
        if (isSelectedArrow) {
          final delPx = tipPx + const Offset(14, -14);
          canvas.drawCircle(
            delPx,
            8.0,
            Paint()
              ..color = const Color(0xFFEF4444)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(
            delPx,
            8.0,
            Paint()
              ..color = Colors.white
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke,
          );
          final xPaint = Paint()
            ..color = Colors.white
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawLine(delPx + const Offset(-3.5, -3.5), delPx + const Offset(3.5, 3.5), xPaint);
          canvas.drawLine(delPx + const Offset(-3.5, 3.5), delPx + const Offset(3.5, -3.5), xPaint);
        }
      }
    } else if (ann is DdsApprovalStampAnnotation) {
      final rect = Rect.fromLTWH(
        (ann.x / 297.0) * paperSize.width,
        (ann.y / 210.0) * paperSize.height,
        (ann.width / 297.0) * paperSize.width,
        (ann.height / 210.0) * paperSize.height,
      );
      final boxOutline = Paint()
        ..color = const Color(0xFF0284C7).withValues(alpha: 0.7)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect.inflate(2.0), boxOutline);

      drawHandle(rect.topLeft);
      drawHandle(Offset(rect.center.dx, rect.top));
      drawHandle(rect.topRight);
      drawHandle(Offset(rect.left, rect.center.dy));
      drawHandle(Offset(rect.right, rect.center.dy));
      drawHandle(rect.bottomLeft);
      drawHandle(Offset(rect.center.dx, rect.bottom));
      drawHandle(rect.bottomRight);
    } else if (ann is DdsLeaderNoteAnnotation) {
      drawHandle(_toPixel(ann.targetPoint));
      drawHandle(_toPixel(ann.textPosition));
    } else if (ann is DdsLinearDimensionAnnotation) {
      drawHandle(_toPixel(ann.p1));
      drawHandle(_toPixel(ann.p2));
    } else if (ann is DdsRevisionCloudAnnotation) {
      for (final pt in ann.points) {
        drawHandle(_toPixel(pt));
      }
    }
  }

  // --- Dimension Line Drawing ---
  void _paintLinearDimension(Canvas canvas, DdsLinearDimensionAnnotation ann, bool isSelected) {
    final p1 = _toPixel(ann.p1);
    final p2 = _toPixel(ann.p2);
    final d = p2 - p1;
    final len = d.distance;
    if (len < 1.0) return;

    final unit = d / len;
    final normal = Offset(-unit.dy, unit.dx);
    final offsetPx = (ann.offsetDistance / 210.0) * paperSize.height;

    final dimP1 = p1 + normal * offsetPx;
    final dimP2 = p2 + normal * offsetPx;

    final strokeColor = ann.lineColor != null
        ? _parseColor(ann.lineColor, isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A))
        : (isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A));
    final stroke = Paint()
      ..color = strokeColor
      ..strokeWidth = isSelected ? 1.6 : 1.1
      ..style = PaintingStyle.stroke;

    // Witness lines
    canvas.drawLine(p1, dimP1 + normal * 3, stroke);
    canvas.drawLine(p2, dimP2 + normal * 3, stroke);

    // Dimension line
    canvas.drawLine(dimP1, dimP2, stroke);

    // Arrowheads
    _drawArrowhead(canvas, dimP1, dimP2, strokeColor);
    _drawArrowhead(canvas, dimP2, dimP1, strokeColor);

    // Centered Text
    final mid = (dimP1 + dimP2) / 2;
    _drawTextBadge(
      canvas,
      mid,
      ann.displayText,
      isSelected: isSelected,
      textColor: ann.textColor != null ? _parseColor(ann.textColor, Colors.black) : null,
      bgColor: ann.backgroundColor != null ? _parseColor(ann.backgroundColor, Colors.white) : null,
    );
  }

  // --- Leader Note Drawing ---
  void _paintLeaderNote(Canvas canvas, DdsLeaderNoteAnnotation ann, bool isSelected) {
    final target = _toPixel(ann.targetPoint);
    final textPos = _toPixel(ann.textPosition);

    final strokeColor = ann.lineColor != null
        ? _parseColor(ann.lineColor, isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A))
        : (isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A));
    final txtColor = ann.textColor != null ? _parseColor(ann.textColor, strokeColor) : strokeColor;
    final leaderPaint = Paint()
      ..color = strokeColor
      ..strokeWidth = isSelected ? 1.6 : 1.1
      ..style = PaintingStyle.stroke;

    // Arrowhead at target pointing towards target
    _drawArrowhead(canvas, target, textPos, strokeColor);

    // Angled line
    canvas.drawLine(target, textPos, leaderPaint);

    // Horizontal shoulder line
    final shoulderDx = textPos.dx >= target.dx ? 24.0 : -24.0;
    final shoulderEnd = textPos + Offset(shoulderDx, 0);
    canvas.drawLine(textPos, shoulderEnd, leaderPaint);

    // Note Text above shoulder
    final tp = TextPainter(
      text: TextSpan(
        text: ann.text,
        style: TextStyle(color: txtColor, fontSize: 9.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(textPos.dx >= target.dx ? textPos.dx + 2 : textPos.dx - tp.width - 2, textPos.dy - tp.height - 2);

    if (ann.backgroundColor != null) {
      final bg = _parseColor(ann.backgroundColor, Colors.white);
      final bgRect = Rect.fromLTWH(textOffset.dx - 2, textOffset.dy - 1, tp.width + 4, tp.height + 2);
      canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(2.0)), Paint()..color = bg);
    }
    tp.paint(canvas, textOffset);
  }

  // --- Note Box Drawing ---
  void _paintNoteBox(Canvas canvas, DdsNoteBoxAnnotation ann, bool isSelected) {
    final rect = Rect.fromLTWH(
      (ann.x / 297.0) * paperSize.width,
      (ann.y / 210.0) * paperSize.height,
      (ann.width / 297.0) * paperSize.width,
      (ann.height / 210.0) * paperSize.height,
    );

    // Use entity colors directly; fallback to defaults when none set.
    final bgCol = _parseColor(ann.backgroundColor, const Color(0xFFFFFBEB));
    final borderCol = _parseColor(ann.lineColor, const Color(0xFFD97706));
    final textCol = _parseColor(ann.textColor, const Color(0xFF78350F));

    // Draw background only when not transparent
    if (bgCol != Colors.transparent) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4.0)), Paint()..color = bgCol.withValues(alpha: 0.95));
    }

    // Draw border when hasBorder is true
    if (ann.hasBorder) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4.0)),
        Paint()
          ..color = borderCol
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }

    // Draw pull-out arrows
    for (final arrow in ann.arrows) {
      final isSelectedArrow = arrow.id == selectedArrowId;
      final rootMm = arrow.root ?? _getNearestBorderPoint(arrow.tip, ann);
      final rootPx = _toPixel(rootMm);
      final tipPx = _toPixel(arrow.tip);
      final drawCol = isSelectedArrow ? const Color(0xFFF59E0B) : borderCol;
      final arrowPaint = Paint()
        ..color = drawCol
        ..strokeWidth = isSelectedArrow ? 2.0 : 1.4
        ..style = PaintingStyle.stroke;
      canvas.drawLine(rootPx, tipPx, arrowPaint);
      _drawArrowhead(canvas, tipPx, rootPx, drawCol);
    }

    // Text inside box
    final tp = TextPainter(
      text: TextSpan(
        text: ann.text,
        style: TextStyle(color: textCol, fontSize: 8.5, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: math.max(10.0, rect.width - 8.0));

    tp.paint(canvas, rect.topLeft + const Offset(4.0, 4.0));
  }

  // --- Revision Cloud Drawing ---
  void _paintRevisionCloud(Canvas canvas, DdsRevisionCloudAnnotation ann, bool isSelected) {
    if (ann.points.length < 2) return;

    final borderCol = _parseColor(ann.lineColor, const Color(0xFFDC2626));
    final textCol = _parseColor(ann.textColor, borderCol);

    final cloudPaint = Paint()
      ..color = borderCol
      ..strokeWidth = isSelected ? 1.8 : 1.2
      ..style = PaintingStyle.stroke;

    final pts = ann.points.map(_toPixel).toList();
    pts.add(pts.first); // Close loop

    final path = Path();
    path.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final pA = pts[i];
      final pB = pts[i + 1];
      final dist = (pB - pA).distance;
      const arcStep = 14.0;
      final steps = math.max(1, (dist / arcStep).round());

      for (int s = 0; s < steps; s++) {
        final start = pA + (pB - pA) * (s / steps);
        final end = pA + (pB - pA) * ((s + 1) / steps);
        final segMid = (start + end) / 2;
        final segVec = end - start;
        final segNormal = Offset(-segVec.dy, segVec.dx) / (segVec.distance > 0 ? segVec.distance : 1.0);
        final control = segMid + segNormal * 4.5;
        path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      }
    }

    if (ann.backgroundColor != null) {
      final bgCol = _parseColor(ann.backgroundColor, Colors.transparent);
      canvas.drawPath(
        path,
        Paint()
          ..color = bgCol.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(path, cloudPaint);

    // Draw Δ tag triangle badge
    final tagPos = pts.first + const Offset(-14, -14);
    _drawRevisionDeltaTag(canvas, tagPos, ann.revisionTag, borderCol, textColor: textCol);
  }

  void _drawRevisionDeltaTag(Canvas canvas, Offset pos, String tag, Color color, {Color? textColor}) {
    final path = Path()
      ..moveTo(pos.dx, pos.dy - 8)
      ..lineTo(pos.dx + 8, pos.dy + 6)
      ..lineTo(pos.dx - 8, pos.dy + 6)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: tag,
        style: TextStyle(color: textColor ?? color, fontSize: 7.0, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2 + 1));
  }

  // --- Approval Stamp Drawing ---
  void _paintApprovalStamp(Canvas canvas, DdsApprovalStampAnnotation ann, bool isSelected) {
    final rect = Rect.fromLTWH(
      (ann.x / 297.0) * paperSize.width,
      (ann.y / 210.0) * paperSize.height,
      (ann.width / 297.0) * paperSize.width,
      (ann.height / 210.0) * paperSize.height,
    );

    final bgCol = _parseColor(ann.backgroundColor, const Color(0xFFECFDF5));
    final borderCol = _parseColor(ann.lineColor, const Color(0xFF059669));
    final textCol = _parseColor(ann.textColor, const Color(0xFF065F46));

    final borderPaint = Paint()
      ..color = borderCol
      ..strokeWidth = isSelected ? 1.8 : 1.6
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3.0));
    canvas.drawRRect(rrect, Paint()..color = bgCol.withValues(alpha: 0.95));
    canvas.drawRRect(rrect, borderPaint);

    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'CLIENT REVIEW STATUS\n',
            style: TextStyle(color: textCol, fontSize: 7.5, fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: '${ann.status.toUpperCase()}\n',
            style: TextStyle(color: borderCol, fontSize: 9.5, fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: 'By: ${ann.reviewedBy}  •  ${ann.reviewDate}',
            style: TextStyle(color: textCol, fontSize: 7.0),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: math.max(10.0, rect.width - 4.0));

    tp.paint(canvas, rect.topLeft + Offset((rect.width - tp.width) / 2, (rect.height - tp.height) / 2));
  }

  // --- Shared Arrowhead Helper ---
  void _drawArrowhead(Canvas canvas, Offset tip, Offset from, Color color) {
    final dir = from - tip;
    final len = dir.distance;
    if (len < 0.1) return;
    final unit = dir / len;
    final normal = Offset(-unit.dy, unit.dx);

    const arrowLen = 7.0;
    const arrowWidth = 3.5;

    final p1 = tip + unit * arrowLen + normal * arrowWidth;
    final p2 = tip + unit * arrowLen - normal * arrowWidth;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  // --- Text Badge Helper ---
  void _drawTextBadge(Canvas canvas, Offset center, String text, {required bool isSelected, Color? textColor, Color? bgColor}) {
    final effectiveTextColor = textColor ?? (isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A));
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: effectiveTextColor, fontSize: 8.5, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromCenter(center: center, width: tp.width + 6.0, height: tp.height + 4.0);

    canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(2.0)), Paint()..color = bgColor ?? Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(2.0)),
      Paint()
        ..color = isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DdsAnnotationOverlayPainter oldDelegate) => true;
}

class _ProjectionSymbolPainter extends CustomPainter {
  final Color color;

  const _ProjectionSymbolPainter({this.color = const Color(0xFF0F172A)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerLinePaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final cy = size.height / 2;
    // Centerline across entire width
    canvas.drawLine(Offset(2, cy), Offset(size.width - 2, cy), centerLinePaint);

    // Trapezoid (Frustum) on left
    final leftX = 4.0;
    final rightX = size.width * 0.44;
    final rBig = size.height * 0.38;
    final rSmall = size.height * 0.20;

    final path = Path()
      ..moveTo(leftX, cy - rBig)
      ..lineTo(rightX, cy - rSmall)
      ..lineTo(rightX, cy + rSmall)
      ..lineTo(leftX, cy + rBig)
      ..close();
    canvas.drawPath(path, paint);

    // Concentric circles on right
    final circleCenter = Offset(size.width * 0.74, cy);
    canvas.drawCircle(circleCenter, rSmall, paint);
    canvas.drawCircle(circleCenter, rBig, paint);

    // Vertical center line for circles
    canvas.drawLine(Offset(circleCenter.dx, cy - rBig - 3), Offset(circleCenter.dx, cy + rBig + 3), centerLinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ViewportGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    const step = 20.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Dds3DLeaderLinesPainter extends CustomPainter {
  final List<({Offset badgePos, Offset anchorPos, Color color})> lines;

  _Dds3DLeaderLinesPainter({required this.lines});

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in lines) {
      final p1 = l.badgePos;
      final p2 = l.anchorPos;
      if ((p1 - p2).distance < 2.0) continue;

      final linePaint = Paint()
        ..color = l.color.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      // Draw thin leader line from badge to 3D anchor
      canvas.drawLine(p1, p2, linePaint);

      // Draw target anchor dot directly on the 3D model geometry
      final dotPaint = Paint()
        ..color = l.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p2, 2.5, dotPaint);

      final ringPaint = Paint()
        ..color = const Color(0xFF334155).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawCircle(p2, 4.0, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Dds3DLeaderLinesPainter oldDelegate) => true;
}

class DdsCadDimensionItem {
  final String id;
  final String label;
  final String valueText;
  final Offset p1;
  final Offset p2;
  final Offset offsetVector;
  final Color color;

  const DdsCadDimensionItem({
    required this.id,
    required this.label,
    required this.valueText,
    required this.p1,
    required this.p2,
    required this.offsetVector,
    this.color = const Color(0xFF0284C7),
  });
}

class _Dds3DCadDimensionLinesPainter extends CustomPainter {
  final List<DdsCadDimensionItem> items;

  _Dds3DCadDimensionLinesPainter({required this.items});

  @override
  void paint(Canvas canvas, Size size) {
    final witnessPaint = Paint()
      ..color = const Color(0xFF64748B)
          .withValues(alpha: 0.85) // Slate technical drafting line
      ..strokeWidth = 0.9;

    const extPast = 4.0; // Extension past dimension line

    for (final item in items) {
      final p1 = item.p1;
      final p2 = item.p2;
      if ((p2 - p1).distance < 3.0) continue;

      final offset = item.offsetVector;
      final q1 = p1 + offset;
      final q2 = p2 + offset;

      final offsetDist = offset.distance;
      final offsetDir = offsetDist > 1e-4 ? offset / offsetDist : const Offset(0, -1);

      // 1. Witness lines extending from physical geometry points to 4px past dimension line
      final w1End = q1 + offsetDir * extPast;
      final w2End = q2 + offsetDir * extPast;
      canvas.drawLine(p1, w1End, witnessPaint);
      canvas.drawLine(p2, w2End, witnessPaint);

      // 2. High-precision Anchor Points firmly attached to the 3D model geometry
      for (final pt in [p1, p2]) {
        // Translucent aura halo ring
        canvas.drawCircle(
          pt,
          5.0,
          Paint()
            ..color = item.color.withValues(alpha: 0.20)
            ..style = PaintingStyle.fill,
        );
        // Precision dark boundary ring
        canvas.drawCircle(
          pt,
          2.8,
          Paint()
            ..color = const Color(0xFF334155)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
        // Accent core dot
        canvas.drawCircle(
          pt,
          2.0,
          Paint()
            ..color = item.color
            ..style = PaintingStyle.fill,
        );
        // Micro white reflection dot
        canvas.drawCircle(
          pt,
          0.8,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );
      }

      // 3. Prepare Multi-Layered Dimension Typography
      final labelSpan = TextSpan(
        text: item.label,
        style: TextStyle(color: item.color, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      );
      final labelTp = TextPainter(text: labelSpan, textDirection: TextDirection.ltr)..layout();

      final valSpan = TextSpan(
        text: item.valueText,
        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 9.0, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      );
      final valTp = TextPainter(text: valSpan, textDirection: TextDirection.ltr)..layout();

      final badgeWidth = labelTp.width + 8.0;
      final pillWidth = badgeWidth + valTp.width + 16.0;
      const pillHeight = 21.0;
      final mid = Offset((q1.dx + q2.dx) / 2.0, (q1.dy + q2.dy) / 2.0);

      final lineLen = (q2 - q1).distance;
      final lineDir = lineLen > 1e-4 ? (q2 - q1) / lineLen : const Offset(1, 0);

      // 4. Clean dimension drafting line with text clearance
      final dimLinePaint = Paint()
        ..color = const Color(0xFF334155)
        ..strokeWidth = 1.1;

      if (lineLen > pillWidth + 8.0) {
        final gapStart = mid - lineDir * (pillWidth / 2.0 + 3.0);
        final gapEnd = mid + lineDir * (pillWidth / 2.0 + 3.0);
        canvas.drawLine(q1, gapStart, dimLinePaint);
        canvas.drawLine(gapEnd, q2, dimLinePaint);
      } else {
        canvas.drawLine(q1, q2, dimLinePaint);
      }

      // 5. Arrowheads at q1 and q2 pointing towards each other (or outward if tight span)
      final angleQ1ToQ2 = math.atan2(q2.dy - q1.dy, q2.dx - q1.dx);
      if (lineLen > 24.0) {
        _drawArrow(canvas, q1, angleQ1ToQ2, const Color(0xFF334155));
        _drawArrow(canvas, q2, angleQ1ToQ2 + math.pi, const Color(0xFF334155));
      } else {
        _drawArrow(canvas, q1, angleQ1ToQ2 + math.pi, const Color(0xFF334155));
        _drawArrow(canvas, q2, angleQ1ToQ2, const Color(0xFF334155));
      }

      // 6. Multi-Layer Smart Frosted Glassmorphism Dimension Text Pill
      final pillRect = Rect.fromCenter(center: mid, width: pillWidth, height: pillHeight);
      final rrect = RRect.fromRectAndRadius(pillRect, const Radius.circular(5.0));

      // Layer 1: Ambient diffuse drop shadow
      canvas.drawRRect(
        rrect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );

      // Layer 2: Category soft glow diffusion
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = item.color.withValues(alpha: 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );

      // Layer 3: Semi-transparent frosted glass body (92% opaque white)
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xEBFFFFFF)
          ..style = PaintingStyle.fill,
      );

      // Layer 4: Accent-tinted precision glass rim
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = item.color.withValues(alpha: 0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      // Layer 5: Top edge glass reflection shimmer
      canvas.drawLine(
        Offset(pillRect.left + 5.0, pillRect.top + 0.8),
        Offset(pillRect.right - 5.0, pillRect.top + 0.8),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..strokeWidth = 0.8,
      );

      // Layer 6: Inner Category Badge Capsule for Label (W1, H1, SLOTS, etc.)
      final badgeRect = Rect.fromLTWH(pillRect.left + 4.5, mid.dy - 7.5, badgeWidth, 15.0);
      final badgeRRect = RRect.fromRectAndRadius(badgeRect, const Radius.circular(3.0));
      canvas.drawRRect(
        badgeRRect,
        Paint()
          ..color = item.color.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        badgeRRect,
        Paint()
          ..color = item.color.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7,
      );
      labelTp.paint(canvas, Offset(badgeRect.left + 4.0, badgeRect.top + (15.0 - labelTp.height) / 2.0));

      // Layer 7: High-contrast Monospace Measurement Value
      valTp.paint(canvas, Offset(badgeRect.right + 5.0, mid.dy - valTp.height / 2.0));
    }
  }

  void _drawArrow(Canvas canvas, Offset tip, double angleRad, Color color) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const arrowLength = 6.5;
    const arrowHalfWidth = 2.2;

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

  @override
  bool shouldRepaint(covariant _Dds3DCadDimensionLinesPainter oldDelegate) => true;
}
