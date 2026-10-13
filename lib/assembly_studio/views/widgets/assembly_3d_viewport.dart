import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import '../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../sheet_metal_studio/engine/kinematic_fold_engine.dart';
import '../../../sheet_metal_studio/engine/flutter_scene_cad_mesh_builder.dart';
import '../../../sheet_metal_studio/engine/trufold_3d_engine_preloader.dart';
import '../../../sheet_metal_studio/views/widgets/viewport_3d/painters/flutter_paint_3d_engine.dart';
import '../../../sheet_metal_studio/views/widgets/studio/studio_3d_navigation_bar.dart';
import '../../../sheet_metal_studio/views/widgets/studio/studio_view_cube.dart';
import '../../../sheet_metal_studio/views/widgets/studio/studio_graphics_preferences_panel.dart';
import '../../models/assembly_part.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';
import '../../engine/assembly_raycaster.dart';
import '../../models/assembly_docking_zone.dart';
import '../../engine/assembly_docking_engine.dart';
import 'assembly_snap_animator.dart';
import 'assembly_sketchup_toolbar.dart';
import 'assembly_sketchup_views_toolbar.dart';
import 'viewport/handlers/handlers.dart';
import 'viewport/overlays/overlays.dart';
import 'viewport/painters/painters.dart';

/// Primary 3D interactive viewport for the Assembly Studio.
/// Powered by the real flutter_scene Impeller GPU engine (PBR shaders, lighting, depth buffer)
/// with graceful fallback to FlutterPaint3dPainter on headless/non-GPU environments.
/// Features exact CAD Studio 3D navigation (Orbit, Pan, Zoom, Alt-constrained orbit, Double-tap fit),
/// integrated Studio3dNavigationBar & StudioViewCube, SketchUp-style primary movement toolbar,
/// direct 3D model face sketching with 'S' hotkey, and 60FPS fluid transformations.
class Assembly3DViewport extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;

  const Assembly3DViewport({super.key, required this.viewModel});

  @override
  State<Assembly3DViewport> createState() => Assembly3DViewportState();
}

class Assembly3DViewportState extends State<Assembly3DViewport> with TickerProviderStateMixin {
  final FocusNode _viewportFocusNode = FocusNode();

  // Local Viewport Navigation State for 60FPS fluid responsiveness
  late double _azimuthDeg;
  late double _elevationDeg;
  late double _zoom;
  late Offset _pan;
  bool _isTurntable = true;
  bool _isPanToolActive = false;

  // Flutter Scene (Impeller GPU Engine)
  Scene? _scene;
  late Node _cameraNode;
  late CameraComponent _cameraComponent;
  Node? _cadModelNode;
  PreprocessedMaterial? _masterShaderMaterial;
  bool _isGpuAvailable = true;
  bool _isSceneReady = false;
  Size? _lastViewportSize;

  // Fixed Camera Target & Scale (Prevents camera from shifting/zooming when entities move)
  CadPoint3D _cameraPivot = const CadPoint3D(0.0, 0.0, 0.0);
  double _cameraFitDim = 600.0;
  bool _cameraInitialized = false;

  // Direct Whole-Part Dragging State (Move Command)
  AssemblyPart? _draggingPart;
  final List<AssemblyPart> _draggedParts = [];
  final Map<String, CadPoint3D> _draggedPartsStartPos = {};
  Offset? _partDragStartScreen;
  bool _hasMovedPart = false;
  bool _isMovingEntity = false;
  CadPoint3D? _moveBaseWorldPoint;
  CadPoint3D? _moveBaseStartWorldPoint;

  // Subtle in-viewport warning banner (Item 5.1 / SS5)
  String? _subtleWarningText;
  String? _subtleWarningActionLabel;
  VoidCallback? _subtleWarningAction;
  Timer? _subtleWarningTimer;

  // Bounding Box, Hole, and Sketch Snap Point Magnetic Dragging
  CadPoint3D? _hoveredSnapPoint;
  AssemblySnapPoint? _hoveredSnapPointModel;
  AssemblySnapPoint? _snapDragSourceSnap;
  AssemblySnapPoint? _snapDragTargetSnap;
  Offset? _currentSnapDragScreenPos;
  late final AssemblySnapAnimator _snapAnimator;

  // SketchUp-Style 3-Click Rotate Tool State
  RotateToolPhase _rotatePhase = RotateToolPhase.awaitingCenter;
  CadPoint3D? _rotateCenterPoint;
  CadPoint3D? _rotateBaselinePoint;
  CadPoint3D? _rotateCurrentArmPoint;
  CadPoint3D? _rotateHoverWorldPos;
  Offset? _lastHoverScreenPos;
  final ValueNotifier<Offset?> _cursorScreenPosNotifier = ValueNotifier<Offset?>(null);
  int _lastGpuRebuildMs = 0;
  double _rotateCurrentAngleDeg = 0.0;
  GizmoAxis _rotateAxis = GizmoAxis.z;
  bool _isRotateCopyMode = false;
  bool _hasClonedForRotate = false;
  SketchUpToolMode? _lastSeenToolMode;
  AssemblyPart? _rotatingPart;
  final Map<String, CadPoint3D> _draggedPartsStartRot = {};
  Offset? _partRotateStartScreen;
  bool _hasRotatedPart = false;
  Offset? _secondaryDownPos;

  // CAD GPU Mesh Caching & Orbit Performance Optimization
  int _lastMeshPolyCount = -1;
  int _lastDocVersion = -1;
  String? _lastSelectedFaceId;
  OnshapeRenderMode? _lastRenderMode;
  CadMaterialPresetType? _lastPreset;
  bool _lastShowWireframe = true;

  // Interactive Draft-Line Welding Tool State
  Offset? _weldDraftStartScreen;
  final List<Offset> _weldDraftPath = [];
  final List<CadPoint3D> _weld3DPoints = [];
  final List<_WeldSparkParticle> _weldSparks = [];
  bool _isDrawingWeld = false;

  // Draggable Standard Views Toolbar State
  Offset _viewsToolbarOffset = const Offset(60, 54);

  // Magnetic Tool State
  CadPoint3D? _magneticHoverPoint;
  CadPoint3D? _magneticHoverNormal;
  AssemblyPart? _magneticHoverPart;

  // Gizmo Interaction State
  GizmoAxis _draggingGizmoAxis = GizmoAxis.none;
  Offset? _gizmoDragStartScreen;
  CadPoint3D? _gizmoDragStartPartPos;
  CadPoint3D? _gizmoDragStartPartRot;

  // Sketch Entity Dragging State (holes, bend lines, slots)
  AssemblySketchFeature? _draggingFeature;
  Offset? _featureDragStartScreen;
  CadPoint2D? _featureDragStartPos;

  // Two-Way Selection Box State (Window Left-to-Right vs Crossing Right-to-Left)
  Offset? _selectionBoxStart;
  Offset? _selectionBoxCurrent;

  // Multi-Click Selection Hierarchy (1-click face, 2-click edit, 3-click whole body)
  DateTime? _lastClickTime;
  int _clickCount = 0;
  String? _lastClickedPartId;

  // VCB Measurements HUD Controller
  final TextEditingController _vcbController = TextEditingController();
  final FocusNode _vcbFocusNode = FocusNode();
  bool _isOrbitingWithMouse = false;
  bool _isPanningWithMouse = false;

  @override
  void initState() {
    super.initState();
    _snapAnimator = AssemblySnapAnimator(vsync: this);
    _azimuthDeg = widget.viewModel.azimuthDeg;
    _elevationDeg = widget.viewModel.elevationDeg;
    _zoom = widget.viewModel.zoom;
    _pan = widget.viewModel.pan;
    widget.viewModel.addListener(_onViewModelChanged);
    _setupSceneGraph();
  }

  @override
  void dispose() {
    _subtleWarningTimer?.cancel();
    _snapAnimator.dispose();
    _cursorScreenPosNotifier.dispose();
    widget.viewModel.removeListener(_onViewModelChanged);
    _viewportFocusNode.dispose();
    _vcbController.dispose();
    _vcbFocusNode.dispose();
    super.dispose();
  }

  void _showSubtleWarning(String message, {String? actionLabel, VoidCallback? onAction}) {
    _subtleWarningTimer?.cancel();
    setState(() {
      _subtleWarningText = message;
      _subtleWarningActionLabel = actionLabel;
      _subtleWarningAction = onAction;
    });
    _subtleWarningTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) {
        setState(() {
          _subtleWarningText = null;
          _subtleWarningActionLabel = null;
          _subtleWarningAction = null;
        });
      }
    });
  }

  void _dismissSubtleWarning() {
    _subtleWarningTimer?.cancel();
    if (_subtleWarningText != null && mounted) {
      setState(() {
        _subtleWarningText = null;
        _subtleWarningActionLabel = null;
        _subtleWarningAction = null;
      });
    }
  }

  void _setupSceneGraph() {
    try {
      if (TruFold3dEnginePreloader.instance.isGpuAvailable) {
        _scene = Scene();
        // Crucial for millimeter-scale CAD: disable game-scale dynamic near plane fitting
        // which snaps the near plane to 512-1024mm and slices through CAD assemblies.
        _scene!.fitNearPlane = false;
        _cameraNode = Node(name: 'AssemblyCamera');
        _cameraComponent = CameraComponent(
          projection: widget.viewModel.isOrthoProjection
              ? OrthographicProjection(zoom: 1.0, near: 0.5, far: 50000.0)
              : PerspectiveProjection(fovRadiansY: 45.0 * vm_math.degrees2Radians, near: 0.5, far: 50000.0),
          activateOnMount: true,
        );
        _cameraNode.addComponent(_cameraComponent);
        _scene!.add(_cameraNode);

        // Preload procedural master shader material
        if (TruFold3dEnginePreloader.instance.isReady) {
          _masterShaderMaterial = TruFold3dEnginePreloader.instance.cachedMasterMaterial;
        }
        if (_masterShaderMaterial == null) {
          try {
            loadFmatMaterial('assets/materials/master_materials.fmat')
                .then((mat) {
                  if (mounted) {
                    _masterShaderMaterial = mat;
                    _masterShaderMaterial?.doubleSided = true;
                    _rebuildGpuCadModel();
                  }
                })
                .catchError((e) {
                  debugPrint('Assembly3DViewport: master_materials.fmat notice: $e');
                });
          } catch (_) {}
        }

        // High-Performance CAD graphics profile (60-120fps buttery-smooth navigation, zero jank)
        _scene!.environmentSettings = EnvironmentSettings(
          toneMapping: ToneMappingMode.aces,
          exposure: 1.10,
          bloomEnabled: false,
          ambientOcclusionEnabled: true,
          ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
          ambientOcclusionBentNormals: false,
          ambientOcclusionSpecularMode: SpecularAmbientOcclusionMode.none,
          ambientOcclusionIntensity: 0.65,
          ambientOcclusionHalfResolution: true,
          screenSpaceReflectionsEnabled: false,
          colorGradingEnabled: false,
          vignetteEnabled: false,
        );

        _scene!.directionalLight = DirectionalLight(direction: vm_math.Vector3(-0.45, -0.85, -0.35).normalized(), intensity: 3.2, castsShadow: false);

        _isSceneReady = true;
        _rebuildGpuCadModel(force: true);
        _updateGpuCamera();
      } else {
        _isGpuAvailable = false;
      }
    } catch (e) {
      debugPrint('Assembly3DViewport GPU init fallback to FlutterPaint: $e');
      _isGpuAvailable = false;
      _scene = null;
    }
  }

  void _rebuildGpuCadModel({bool force = false}) {
    if (_scene == null || !_isGpuAvailable || !_isSceneReady) return;
    final mesh = widget.viewModel.assemblyMesh;
    if (mesh.polygons.isEmpty) return;

    final selectedPartId = widget.viewModel.selectedPart?.id;
    final targetSelectedFaceId = widget.viewModel.doc.selectedFaceId ?? selectedPartId;
    final targetRenderMode = widget.viewModel.onshapeRenderMode;
    final targetPreset = widget.viewModel.graphicsPreferences.materialSettings.preset;
    final targetWireframe = widget.viewModel.showWireframe;

    final docVersion = widget.viewModel.documentVersion;

    if (!force &&
        _cadModelNode != null &&
        docVersion == _lastDocVersion &&
        mesh.polygons.length == _lastMeshPolyCount &&
        targetSelectedFaceId == _lastSelectedFaceId &&
        targetRenderMode == _lastRenderMode &&
        targetPreset == _lastPreset &&
        targetWireframe == _lastShowWireframe) {
      return;
    }

    _lastDocVersion = docVersion;
    _lastMeshPolyCount = mesh.polygons.length;
    _lastSelectedFaceId = targetSelectedFaceId;
    _lastRenderMode = targetRenderMode;
    _lastPreset = targetPreset;
    _lastShowWireframe = targetWireframe;

    if (_cadModelNode != null) {
      _scene!.remove(_cadModelNode!);
      _cadModelNode = null;
    }

    final overrides = <String, Color>{};
    for (final part in widget.viewModel.doc.parts) {
      overrides[part.id] = part.color;
    }

    PreprocessedMaterial? activeShaderMaterial;
    final matSettings = widget.viewModel.graphicsPreferences.materialSettings;
    if (matSettings.useSpangles && _masterShaderMaterial != null) {
      _masterShaderMaterial!.parameters.setVec4('baseColorFactor', matSettings.toLinearRgbVector4());
      _masterShaderMaterial!.parameters.setFloat('roughnessFactor', matSettings.roughness);
      _masterShaderMaterial!.parameters.setFloat('isPlastic', matSettings.isPlastic ? 1.0 : 0.0);
      _masterShaderMaterial!.parameters.setFloat('materialMode', 1.0);
      _masterShaderMaterial!.parameters.setFloat('spangleScale', matSettings.spangleScale);
      _masterShaderMaterial!.doubleSided = true;
      activeShaderMaterial = _masterShaderMaterial;
    }

    _initCameraTargetIfNeeded(mesh);
    _cadModelNode = FlutterSceneCadMeshBuilder.buildCadModel(
      mesh,
      selectedFaceId: targetSelectedFaceId,
      showWireframe: targetWireframe,
      customMaterial: activeShaderMaterial,
      preferences: widget.viewModel.graphicsPreferences,
      renderMode: targetRenderMode,
      partColorOverrides: overrides,
      pivotOverride: _cameraPivot,
    );
    _scene!.add(_cadModelNode!);
  }

  void _initCameraTargetIfNeeded(FoldedMeshResult mesh) {
    if (!_cameraInitialized && mesh.polygons.isNotEmpty) {
      _cameraPivot = mesh.center;
      final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
      _cameraFitDim = maxDim > 0 ? maxDim : 600.0;
      _cameraInitialized = true;
    }
  }

  void _updateGpuCamera([Size? viewportSize]) {
    if (!_isSceneReady || _scene == null || !_isGpuAvailable) return;
    final size = viewportSize ?? _lastViewportSize ?? const Size(1280, 800);
    final mesh = widget.viewModel.assemblyMesh;
    _initCameraTargetIfNeeded(mesh);
    final fitDim = _cameraFitDim > 0 ? _cameraFitDim : 400.0;
    final isOrtho = widget.viewModel.isOrthoProjection;
    // In orthographic projection, keep camera eye safely outside model bounds
    // so near clipping plane (0.5) never slices through 3D parts when rotating / zooming (Item 4 / SS3/SS4)
    final orbitDist = isOrtho ? math.max(fitDim * 12.0, 15000.0) : math.max((fitDim * 2.5) / _zoom, 25.0);

    final m = _computeRotationMatrix(_azimuthDeg, _elevationDeg);
    final d = vm_math.Vector3(-m[8], m[10], m[9]);
    final up = vm_math.Vector3(-m[4], m[6], m[5]);
    final right = up.cross(d).normalized();

    if (isOrtho) {
      if (_cameraComponent.projection is! OrthographicProjection) {
        _cameraComponent.projection = OrthographicProjection(near: 0.5, far: 50000.0);
      }
      (_cameraComponent.projection as OrthographicProjection).zoom = _zoom / fitDim;
    } else {
      if (_cameraComponent.projection is! PerspectiveProjection) {
        _cameraComponent.projection = PerspectiveProjection(fovRadiansY: 45.0 * vm_math.degrees2Radians, near: 0.5, far: 50000.0);
      }
    }

    final vH = 2.0 * orbitDist * math.tan(45.0 * vm_math.degrees2Radians / 2.0);
    final unitsPerPixel = size.height > 0 ? vH / size.height : 1.0;
    // Panning: moving mouse right (dx > 0) moves model right, so camera shifts left (+right vector).
    // Moving mouse down (dy > 0) moves model down, so camera shifts up (+up vector).
    final target = right * (_pan.dx * unitsPerPixel) + up * (_pan.dy * unitsPerPixel);
    final eye = target + d * orbitDist;
    _cameraNode.lookAtFrom(eye, target, up: up);
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    if (widget.viewModel.activeToolMode != _lastSeenToolMode) {
      _lastSeenToolMode = widget.viewModel.activeToolMode;
      _rotatePhase = RotateToolPhase.awaitingCenter;
      _rotateCenterPoint = null;
      _rotateBaselinePoint = null;
      _rotateCurrentArmPoint = null;
      _rotateCurrentAngleDeg = 0.0;
      _partRotateStartScreen = null;
      _draggedParts.clear();
      _draggedPartsStartRot.clear();
      _draggedPartsStartPos.clear();
      _rotatingPart = null;
      _hasRotatedPart = false;
      _hasClonedForRotate = false;
      _isMovingEntity = false;
      _isDrawingWeld = false;
      _weldDraftPath.clear();
      _weld3DPoints.clear();
      _weldSparks.clear();
      _weldDraftStartScreen = null;
    }
    setState(() {
      _azimuthDeg = widget.viewModel.azimuthDeg;
      _elevationDeg = widget.viewModel.elevationDeg;
      _zoom = widget.viewModel.zoom;
      _pan = widget.viewModel.pan;
    });
    if (!_vcbFocusNode.hasFocus && widget.viewModel.vcbValue.isNotEmpty && _vcbController.text != widget.viewModel.vcbValue) {
      _vcbController.text = widget.viewModel.vcbValue;
    }
    _rebuildGpuCadModel();
    _updateGpuCamera();
  }

  void _orbitCamera(double dAz, double dEl) {
    if (_scene != null && _scene!.renderScale > 0.86) {
      _scene!.renderScale = 0.85;
    }
    setState(() {
      _azimuthDeg = (_azimuthDeg + dAz) % 360.0;
      _elevationDeg = (_elevationDeg + dEl).clamp(-89.0, 89.0);
      widget.viewModel.azimuthDeg = _azimuthDeg;
      widget.viewModel.elevationDeg = _elevationDeg;
    });
    _updateGpuCamera();
  }

  void _panCamera(Offset delta) {
    if (_scene != null && _scene!.renderScale > 0.86) {
      _scene!.renderScale = 0.85;
    }
    setState(() {
      _pan += delta;
      widget.viewModel.pan = _pan;
    });
    _updateGpuCamera();
  }

  void _zoomCamera(double factor) {
    setState(() {
      _zoom = (_zoom * factor).clamp(0.15, 10.0);
      widget.viewModel.zoom = _zoom;
    });
    _updateGpuCamera();
  }

  void _zoomToFit() {
    setState(() {
      _pan = Offset.zero;
      _azimuthDeg = 45.0;
      _elevationDeg = 30.0;
      final mesh = widget.viewModel.assemblyMesh;
      final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
      _cameraFitDim = maxDim > 0 ? maxDim : 600.0;
      _cameraPivot = mesh.center;
      _cameraInitialized = true;
      _zoom = (850.0 / _cameraFitDim).clamp(0.4, 2.5);
      widget.viewModel.azimuthDeg = _azimuthDeg;
      widget.viewModel.elevationDeg = _elevationDeg;
      widget.viewModel.pan = _pan;
      widget.viewModel.zoom = _zoom;
    });
    _updateGpuCamera();
  }

  void _setCameraFromAngles(double az, double el) {
    setState(() {
      _azimuthDeg = az % 360.0;
      _elevationDeg = el.clamp(-89.0, 89.0);
      widget.viewModel.azimuthDeg = _azimuthDeg;
      widget.viewModel.elevationDeg = _elevationDeg;
    });
    _updateGpuCamera();
  }

  AssemblySnapPoint? _findNearestSnapPointOnSelectedPart(Offset cursorScreen, Size size, FoldedMeshResult mesh) {
    final part = widget.viewModel.selectedPart;
    if (part == null || !part.isVisible) return null;
    final allSnapPts = AssemblyDockingEngine.getAllSnapPointsForPart(part, cachedMesh: mesh);
    return AssemblyDockingEngine.findNearestSnapPoint(
      screenCursor: cursorScreen,
      candidates: allSnapPts,
      projectPoint: (pt) => _projectPoint(pt, size, mesh),
      maxPixelDistance: 12.0,
    );
  }

  MouseCursor _getCursorForToolMode(AssemblyStudioViewModel vm) {
    if (_isOrbitingWithMouse || vm.activeToolMode == SketchUpToolMode.orbit) return SystemMouseCursors.none;
    if (_isPanningWithMouse || vm.activeToolMode == SketchUpToolMode.pan || _isPanToolActive) return SystemMouseCursors.none;
    if (vm.activeToolMode == SketchUpToolMode.move) return SystemMouseCursors.none;
    if (vm.activeToolMode == SketchUpToolMode.rotate) return SystemMouseCursors.none;
    if (_snapDragSourceSnap != null) return SystemMouseCursors.grabbing;
    if (_hoveredSnapPoint != null) return SystemMouseCursors.grab;
    if (vm.pendingPlacement != null) return SystemMouseCursors.precise;
    if (_draggingPart != null) return SystemMouseCursors.none;
    if (vm.activeToolMode == SketchUpToolMode.weld) return SystemMouseCursors.none;
    if (vm.activeToolMode == SketchUpToolMode.magnetic) return SystemMouseCursors.precise;
    return SystemMouseCursors.basic;
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final mesh = vm.assemblyMesh;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _lastViewportSize = size;

        return Focus(
          focusNode: _viewportFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              bool isCtrl = false;
              bool isShift = false;
              bool isAlt = false;
              try {
                isCtrl = HardwareKeyboard.instance.isControlPressed;
                isShift = HardwareKeyboard.instance.isShiftPressed;
                isAlt = HardwareKeyboard.instance.isAltPressed;
              } catch (_) {}

              if (isAlt && event.logicalKey == LogicalKeyboardKey.keyT) {
                vm.toggleBackgroundMode();
                return KeyEventResult.handled;
              }

              if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
                if (isShift) {
                  vm.redo();
                } else {
                  vm.undo();
                }
                return KeyEventResult.handled;
              } else if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyY) {
                vm.redo();
                return KeyEventResult.handled;
              } else if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyG) {
                if (isShift) {
                  vm.ungroupSelectedParts();
                } else {
                  vm.groupSelectedParts();
                }
                return KeyEventResult.handled;
              } else if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyD) {
                vm.duplicateSelectedPart();
                return KeyEventResult.handled;
              } else if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
                vm.selectAllParts();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyO && !isCtrl) {
                // SketchUp Camera Orbit Tool (Key: O)
                vm.setToolMode(SketchUpToolMode.orbit);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyH && !isCtrl) {
                // SketchUp Camera Pan Tool (Key: H)
                vm.setToolMode(SketchUpToolMode.pan);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyS && !isCtrl) {
                // Focus part, lock 3D movement, activate real-time direct sketch
                if (!vm.isSketchMode) {
                  vm.focusPartAndEnterSketch(vm.selectedPart?.id);
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
                // SketchUp Move Tool
                vm.setToolMode(SketchUpToolMode.move);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyR || event.logicalKey == LogicalKeyboardKey.keyQ) {
                // SketchUp Rotate Tool
                vm.setToolMode(SketchUpToolMode.rotate);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyB) {
                // SketchUp Auto-Span Face-to-Face Bridging Tool
                vm.setToolMode(SketchUpToolMode.bridge);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyW) {
                // Interactive Draft-Line Welding Tool
                vm.setToolMode(SketchUpToolMode.weld);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyJ) {
                // Magnetic Snap & Coupling Tool
                vm.setToolMode(SketchUpToolMode.magnetic);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.space || event.logicalKey == LogicalKeyboardKey.keyV) {
                // SketchUp Select Tool (Requirement 5)
                _cancelRotation(vm);
                if (_draggingPart != null || _draggedParts.isNotEmpty) {
                  for (final part in _draggedParts) {
                    final startPos = _draggedPartsStartPos[part.id];
                    if (startPos != null) part.position = startPos;
                  }
                  _draggingPart = null;
                  _draggedParts.clear();
                  _draggedPartsStartPos.clear();
                  _partDragStartScreen = null;
                }
                if (vm.bridgeSourcePartId != null) vm.cancelBridge();
                vm.setToolMode(SketchUpToolMode.select);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
                _zoomToFit();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                // SketchUp Red Axis constraint (X) - strictly locks movement direction
                vm.toggleLockedAxis(GizmoAxis.x);
                final isLocked = vm.lockedAxis == GizmoAxis.x;
                vm.setVcbState(
                  label: 'Axis Lock',
                  value: isLocked ? 'Red Axis [X] Locked' : 'Axis Unlocked',
                  hint: isLocked ? 'Movement locked to X axis • Press → again or ↓ to unlock' : 'Free movement',
                );
                if (vm.activeToolMode == SketchUpToolMode.rotate) {
                  _rotateAxis = isLocked ? GizmoAxis.x : GizmoAxis.z;
                  if (_lastHoverScreenPos != null) {
                    _handleRotatePointerHover(_lastHoverScreenPos!, size, mesh, vm);
                  }
                } else if (vm.activeToolMode == SketchUpToolMode.move && _isMovingEntity && _draggingPart != null) {
                  if (_lastHoverScreenPos != null) {
                    _handleMovePointerMove(_lastHoverScreenPos!, size, mesh, vm);
                  }
                }
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                // SketchUp Green Axis constraint (Y) - strictly locks movement direction
                vm.toggleLockedAxis(GizmoAxis.y);
                final isLocked = vm.lockedAxis == GizmoAxis.y;
                vm.setVcbState(
                  label: 'Axis Lock',
                  value: isLocked ? 'Green Axis [Y] Locked' : 'Axis Unlocked',
                  hint: isLocked ? 'Movement locked to Y axis • Press ← again or ↓ to unlock' : 'Free movement',
                );
                if (vm.activeToolMode == SketchUpToolMode.rotate) {
                  _rotateAxis = isLocked ? GizmoAxis.y : GizmoAxis.z;
                  if (_lastHoverScreenPos != null) {
                    _handleRotatePointerHover(_lastHoverScreenPos!, size, mesh, vm);
                  }
                } else if (vm.activeToolMode == SketchUpToolMode.move && _isMovingEntity && _draggingPart != null) {
                  if (_lastHoverScreenPos != null) {
                    _handleMovePointerMove(_lastHoverScreenPos!, size, mesh, vm);
                  }
                }
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                // SketchUp Blue Axis constraint (Z) - strictly locks movement direction
                vm.toggleLockedAxis(GizmoAxis.z);
                final isLocked = vm.lockedAxis == GizmoAxis.z;
                vm.setVcbState(
                  label: 'Axis Lock',
                  value: isLocked ? 'Blue Axis [Z] Locked' : 'Axis Unlocked',
                  hint: isLocked ? 'Movement locked to Z axis • Press ↑ again or ↓ to unlock' : 'Free movement',
                );
                if (vm.activeToolMode == SketchUpToolMode.rotate) {
                  _rotateAxis = isLocked ? GizmoAxis.z : GizmoAxis.z;
                  if (_lastHoverScreenPos != null) {
                    _handleRotatePointerHover(_lastHoverScreenPos!, size, mesh, vm);
                  }
                } else if (vm.activeToolMode == SketchUpToolMode.move && _isMovingEntity && _draggingPart != null) {
                  if (_lastHoverScreenPos != null) {
                    _handleMovePointerMove(_lastHoverScreenPos!, size, mesh, vm);
                  }
                }
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                // SketchUp Unlock / Clear Axis constraint
                vm.clearLockedAxis();
                vm.setVcbState(label: 'Axis Lock', value: 'Unlocked (Free)', hint: 'Free movement across all 3 axes');
                if (vm.activeToolMode == SketchUpToolMode.rotate) {
                  _rotateAxis = GizmoAxis.z;
                  if (_lastHoverScreenPos != null) {
                    _handleRotatePointerHover(_lastHoverScreenPos!, size, mesh, vm);
                  }
                } else if (vm.activeToolMode == SketchUpToolMode.move && _isMovingEntity && _draggingPart != null) {
                  if (_lastHoverScreenPos != null) {
                    _handleMovePointerMove(_lastHoverScreenPos!, size, mesh, vm);
                  }
                }
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.controlLeft || event.logicalKey == LogicalKeyboardKey.controlRight) {
                if (vm.activeToolMode == SketchUpToolMode.rotate) {
                  _isRotateCopyMode = !_isRotateCopyMode;
                  vm.setVcbState(label: vm.vcbLabel, value: vm.vcbValue, hint: _isRotateCopyMode ? 'Rotational Copy Mode ON (+)' : 'Rotate Mode');
                  setState(() {});
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
                if (_vcbFocusNode.hasFocus) {
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey == LogicalKeyboardKey.backspace && _vcbController.text.isNotEmpty) {
                  _vcbController.text = _vcbController.text.substring(0, _vcbController.text.length - 1);
                  vm.vcbValue = _vcbController.text;
                  vm.notifyDocChanged();
                  return KeyEventResult.handled;
                }
                if (vm.selectedWeldId != null) {
                  vm.deleteSelectedWeld();
                  return KeyEventResult.handled;
                }
                if (vm.selectedPart != null) {
                  vm.deleteSelectedPart();
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                if (_vcbController.text.isNotEmpty || vm.vcbValue.isNotEmpty) {
                  final input = _vcbController.text.isNotEmpty ? _vcbController.text : vm.vcbValue;
                  vm.submitVcbInput(input);
                  _vcbController.clear();
                  _viewportFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (vm.isSketchMode) {
                  vm.finishSketch();
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                bool cancelledActiveAction = false;
                if (vm.activeToolMode == SketchUpToolMode.rotate && (_rotatePhase != RotateToolPhase.awaitingCenter || _draggedParts.isNotEmpty)) {
                  _cancelRotation(vm);
                  cancelledActiveAction = true;
                }
                if (_isMovingEntity || _draggingPart != null || _draggedParts.isNotEmpty) {
                  _cancelEntityMove(vm);
                  cancelledActiveAction = true;
                }
                if (_draggingGizmoAxis != GizmoAxis.none) {
                  if (vm.selectedPart != null && _gizmoDragStartPartPos != null) {
                    vm.selectedPart!.position = _gizmoDragStartPartPos!;
                    if (_gizmoDragStartPartRot != null) {
                      vm.selectedPart!.rotationDeg = _gizmoDragStartPartRot!;
                    }
                    vm.notifyDocChanged();
                  }
                  _draggingGizmoAxis = GizmoAxis.none;
                  setState(() {});
                  cancelledActiveAction = true;
                }
                if (vm.pendingPlacement != null) {
                  vm.cancelPendingPlacement();
                  cancelledActiveAction = true;
                }
                if (vm.activeToolMode == SketchUpToolMode.bridge && vm.bridgeSourcePartId != null) {
                  vm.cancelBridge();
                  cancelledActiveAction = true;
                }
                if (cancelledActiveAction) {
                  return KeyEventResult.handled;
                }
                if (vm.activeToolMode != SketchUpToolMode.select) {
                  vm.setToolMode(SketchUpToolMode.select);
                  _rotatePhase = RotateToolPhase.awaitingCenter;
                  _rotateCenterPoint = null;
                  _rotateBaselinePoint = null;
                  _rotateCurrentArmPoint = null;
                  _moveBaseWorldPoint = null;
                  _moveBaseStartWorldPoint = null;
                  vm.clearLockedAxis();
                  setState(() {});
                  return KeyEventResult.handled;
                }
                if (_vcbController.text.isNotEmpty) {
                  _vcbController.clear();
                  vm.vcbValue = '';
                  vm.notifyDocChanged();
                  return KeyEventResult.handled;
                }
                if (vm.doc.selectedPartIds.isNotEmpty) {
                  vm.clearSelection(force: true);
                  return KeyEventResult.handled;
                }
                if (vm.selectedWeldId != null) {
                  vm.selectWeld(null);
                  return KeyEventResult.handled;
                }
                if (vm.lockedAxis != GizmoAxis.none) {
                  vm.clearLockedAxis();
                  return KeyEventResult.handled;
                }
                if (vm.isSketchMode) {
                  vm.finishSketch();
                  return KeyEventResult.handled;
                }
              }

              if (!isCtrl && event.character != null && event.character!.isNotEmpty && !_vcbFocusNode.hasFocus) {
                final char = event.character!;
                if (RegExp(r'^[0-9\.\,\*\x\X\/\-\+]$').hasMatch(char)) {
                  _vcbController.text += char;
                  vm.setVcbState(label: vm.vcbLabel, value: _vcbController.text);
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: vm.isLightBackground
                  ? const RadialGradient(center: Alignment(0.0, -0.20), radius: 1.35, colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)])
                  : const RadialGradient(center: Alignment(0.0, -0.15), radius: 1.25, colors: [Color(0xFF262630), Color(0xFF14141A)]),
            ),
            child: Stack(
              children: [
                // =================================================================
                // 1. PRIMARY 3D CANVAS & RAW MOUSE NAVIGATION LISTENER
                // =================================================================
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerHover: (event) {
                      _lastHoverScreenPos = event.localPosition;
                      _cursorScreenPosNotifier.value = event.localPosition;
                      if (vm.activeToolMode == SketchUpToolMode.rotate) {
                        _handleRotatePointerHover(event.localPosition, size, mesh, vm);
                      } else if (vm.activeToolMode == SketchUpToolMode.magnetic) {
                        _handleMagneticPointerHover(event.localPosition, size, mesh, vm);
                      } else if (vm.activeToolMode == SketchUpToolMode.move) {
                        if (_isMovingEntity && _draggingPart != null) {
                          _handleMovePointerMove(event.localPosition, size, mesh, vm);
                        }
                      }
                    },
                    onPointerDown: (event) {
                      _viewportFocusNode.requestFocus();
                      final selectedPart = vm.selectedPart;

                      // 1b. Draft-Line Welding Tool Start
                      if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.weld && (event.buttons & kPrimaryMouseButton) != 0) {
                        _weldDraftStartScreen = event.localPosition;
                        _weldDraftPath.clear();
                        _weldDraftPath.add(event.localPosition);
                        _weld3DPoints.clear();
                        _isDrawingWeld = true;
                        final (rayOrigin, rayDir) = _getRayFromScreen(event.localPosition, size, mesh);
                        final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
                        if (hit != null) {
                          _weld3DPoints.add(hit.hitPoint);
                        }
                        _spawnWeldSparks(event.localPosition);
                        setState(() {});
                        return;
                      }

                      // 1c. Direct Sketch Entity Interaction
                      if (vm.isSketchMode && (event.buttons & kPrimaryMouseButton) != 0) {
                        final targetPart = vm.doc.parts.where((p) => p.id == vm.sketchPartId).firstOrNull ?? vm.selectedPart;
                        if (targetPart != null) {
                          final hitFeature = _hitTestSketchFeature(event.localPosition, size, mesh, targetPart);
                          if (hitFeature != null) {
                            if (hitFeature.matedRungPartId != null || vm.isPartBonded(targetPart.id)) {
                              vm.selectSketchFeature(hitFeature.id);
                              vm.setVcbState(label: '🔒 Welded / Mated Entity', value: 'Locked by Weld', hint: 'Break weld joint first to move or drag.');
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                SnackBar(
                                  duration: const Duration(seconds: 4),
                                  content: Text('Entity "${hitFeature.featureType}" is welded/bonded. Break weld first to move.'),
                                  action: SnackBarAction(
                                    label: 'Break Weld',
                                    textColor: const Color(0xFFEF4444),
                                    onPressed: () {
                                      vm.breakAllBondsForPart(targetPart.id);
                                    },
                                  ),
                                ),
                              );
                              return;
                            }
                            _draggingFeature = hitFeature;
                            _featureDragStartScreen = event.localPosition;
                            _featureDragStartPos = hitFeature.localCenter;
                            vm.selectSketchFeature(hitFeature.id);
                            return;
                          }
                        }
                      }

                      if ((event.buttons & kSecondaryMouseButton) != 0) {
                        _secondaryDownPos = event.localPosition;
                      }

                      // 2. SketchUp 3-Click Rotate Tool: Center, Baseline, Angle Sweep
                      if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.rotate && (event.buttons & kPrimaryMouseButton) != 0) {
                        _handleRotatePointerDown(event.localPosition, size, mesh, vm);
                        return;
                      }

                      // 2b. Check if pointer hits a Gizmo handle (Move)
                      if (selectedPart != null && !vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.move) {
                        final hitAxis = _hitTestGizmo(event.localPosition, size, mesh, selectedPart, vm.gizmoMode);
                        if (hitAxis != GizmoAxis.none) {
                          if (vm.isPartBonded(selectedPart.id)) {
                            vm.setVcbState(label: '🔒 Welded Entity', value: 'Locked by Weld', hint: 'Break weld joint first to move/rotate with Gizmo.');
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 4),
                                content: Text('Part "${selectedPart.name}" is welded. Break weld joint first to move with Gizmo.'),
                                action: SnackBarAction(
                                  label: 'Break Weld',
                                  textColor: const Color(0xFFEF4444),
                                  onPressed: () {
                                    vm.breakAllBondsForPart(selectedPart.id);
                                  },
                                ),
                              ),
                            );
                            return;
                          }
                          _draggingGizmoAxis = hitAxis;
                          _gizmoDragStartScreen = event.localPosition;
                          _gizmoDragStartPartPos = selectedPart.position;
                          _gizmoDragStartPartRot = selectedPart.rotationDeg;
                          return;
                        }
                      }

                      _draggingGizmoAxis = GizmoAxis.none;

                      // 2c. Magnetic Snap Tool Point Click
                      if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.magnetic && (event.buttons & kPrimaryMouseButton) != 0) {
                        _handleMagneticPointerDown(event.localPosition, size, mesh, vm);
                        return;
                      }

                      // 3. Direct Whole-Part Group Selection, Weld Picking, Move, and In-Place Rotate
                      if (!vm.isSketchMode && (event.buttons & kPrimaryMouseButton) != 0 && vm.pendingPlacement == null) {
                        final hitPoly = _findFrontmostPolygonUnderCursor(event.localPosition, size, mesh);
                        if (hitPoly != null) {
                          // Check if hit a weld bead directly
                          if (hitPoly.faceId.startsWith('weld_')) {
                            final weldId = hitPoly.faceId.substring('weld_'.length);
                            vm.selectWeld(weldId);
                            return;
                          }

                          final hitPart = vm.findPartForFaceId(hitPoly.faceId);
                          if (hitPart != null) {
                            bool isShift = false;
                            bool isCtrl = false;
                            try {
                              isShift = HardwareKeyboard.instance.isShiftPressed;
                              isCtrl = HardwareKeyboard.instance.isControlPressed;
                            } catch (_) {}

                            // Auto-Span Face-to-Face Bridging Tool (Key: B)
                            if (vm.activeToolMode == SketchUpToolMode.bridge) {
                              if (vm.bridgeSourcePartId == null) {
                                vm.startBridge(hitPart.id);
                              } else if (vm.bridgeSourcePartId != hitPart.id) {
                                vm.bridgeParts(vm.bridgeSourcePartId!, hitPart.id);
                              } else {
                                vm.cancelBridge();
                              }
                              return;
                            }

                            if (vm.activeToolMode == SketchUpToolMode.select) {
                              final now = DateTime.now();
                              if (_lastClickTime != null && _lastClickedPartId == hitPart.id && now.difference(_lastClickTime!).inMilliseconds < 450) {
                                _clickCount++;
                              } else {
                                _clickCount = 1;
                                _lastClickedPartId = hitPart.id;
                              }
                              _lastClickTime = now;

                              if (_clickCount == 2) {
                                vm.focusPartAndEnterSketch(hitPart.id);
                                return;
                              }

                              if (isCtrl) {
                                vm.togglePartSelection(hitPart.id);
                              } else if (isShift) {
                                vm.addToSelection(hitPart.id);
                              } else {
                                vm.selectPart(hitPart.id);
                              }
                              return;
                            }

                            if (vm.activeToolMode == SketchUpToolMode.move) {
                              if (vm.isPartBonded(hitPart.id)) {
                                vm.setVcbState(label: '🔒 Welded Entity', value: 'Locked by Weld', hint: 'Break weld joint first to move.');
                                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 4),
                                    content: Text('Part "${hitPart.name}" is welded. Break weld joint first to move.'),
                                    action: SnackBarAction(
                                      label: 'Break Weld',
                                      textColor: const Color(0xFFEF4444),
                                      onPressed: () {
                                        vm.breakAllBondsForPart(hitPart.id);
                                      },
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (_isMovingEntity && _draggingPart != null) {
                                _commitEntityMove(vm);
                                return;
                              }

                              if (!vm.doc.selectedPartIds.contains(hitPart.id)) {
                                vm.selectPart(hitPart.id);
                              }

                              _draggingPart = hitPart;
                              _partDragStartScreen = event.localPosition;
                              _hasMovedPart = false;
                              _isMovingEntity = true;

                              final groupParts = hitPart.groupId != null ? vm.doc.parts.where((p) => p.groupId == hitPart.groupId).toList() : <AssemblyPart>[];
                              _draggedParts.clear();
                              _draggedParts.addAll(groupParts.isNotEmpty ? groupParts : [hitPart]);
                              _draggedPartsStartPos.clear();
                              for (final p in _draggedParts) {
                                _draggedPartsStartPos[p.id] = p.position;
                              }

                              final nearestSnap = _findNearestSnapPointOnSelectedPart(event.localPosition, size, mesh);
                              _moveBaseWorldPoint = nearestSnap?.worldPosition ?? hitPart.position;
                              _moveBaseStartWorldPoint = _moveBaseWorldPoint;

                              vm.setVcbState(
                                label: 'Distance',
                                value: vm.formatLength(0.0),
                                hint: 'Click destination point or type distance in VCB (e.g. 150)',
                              );
                              setState(() {});
                              return;
                            }
                          }
                        } else {
                          if (vm.activeToolMode == SketchUpToolMode.move) {
                            if (_isMovingEntity && _draggingPart != null) {
                              _commitEntityMove(vm);
                              return;
                            } else if (vm.selectedPart != null) {
                              final partToMove = vm.selectedPart!;
                              if (vm.isPartBonded(partToMove.id)) {
                                vm.setVcbState(label: '🔒 Welded Entity', value: 'Locked by Weld', hint: 'Break weld joint first to move.');
                                return;
                              }
                              _draggingPart = partToMove;
                              _partDragStartScreen = event.localPosition;
                              _hasMovedPart = false;
                              _isMovingEntity = true;

                              final groupParts = partToMove.groupId != null
                                  ? vm.doc.parts.where((p) => p.groupId == partToMove.groupId).toList()
                                  : <AssemblyPart>[];
                              _draggedParts.clear();
                              _draggedParts.addAll(groupParts.isNotEmpty ? groupParts : [partToMove]);
                              _draggedPartsStartPos.clear();
                              for (final p in _draggedParts) {
                                _draggedPartsStartPos[p.id] = p.position;
                              }

                              final nearestSnap = _findNearestSnapPointOnSelectedPart(event.localPosition, size, mesh);
                              _moveBaseWorldPoint = nearestSnap?.worldPosition ?? partToMove.position;
                              _moveBaseStartWorldPoint = _moveBaseWorldPoint;

                              vm.setVcbState(label: 'Distance', value: vm.formatLength(0.0), hint: 'Move mouse or type distance in VCB (e.g. 150)');
                              setState(() {});
                              return;
                            }
                          }
                          if (vm.activeToolMode == SketchUpToolMode.select) {
                            _selectionBoxStart = event.localPosition;
                            _selectionBoxCurrent = event.localPosition;
                            setState(() {});
                          }
                        }
                      }
                    },
                    onPointerMove: (event) {
                      if (_snapAnimator.isSnapping) return;
                      _lastHoverScreenPos = event.localPosition;
                      _cursorScreenPosNotifier.value = event.localPosition;

                      if (_selectionBoxStart != null) {
                        setState(() {
                          _selectionBoxCurrent = event.localPosition;
                        });
                        return;
                      }

                      if (_draggingFeature != null) {
                        _handleFeatureDragUpdate(event.localPosition, size, mesh);
                        return;
                      }

                      if (_draggingGizmoAxis != GizmoAxis.none) {
                        _handleGizmoDragUpdate(event.localPosition, size, mesh);
                        return;
                      }

                      final isSecondary = (event.buttons & kSecondaryMouseButton) != 0;
                      final isMiddle = (event.buttons & kTertiaryButton) != 0 || (event.buttons & kMiddleMouseButton) != 0;
                      final isPrimary = (event.buttons & kPrimaryMouseButton) != 0;

                      bool isShiftPressed = false;
                      bool isCtrlPressed = false;
                      bool isAltPressed = false;
                      try {
                        isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                        isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
                        isAltPressed = HardwareKeyboard.instance.isAltPressed;
                      } catch (_) {}

                      final isPan =
                          (isMiddle && isShiftPressed) ||
                          (isSecondary && (isShiftPressed || isCtrlPressed)) ||
                          (isPrimary && _isPanToolActive) ||
                          (isPrimary && isShiftPressed && _isPanToolActive);
                      final isOrbit = (isMiddle && !isShiftPressed) || (isSecondary && !isShiftPressed && !isCtrlPressed);

                      if (isPan) {
                        _isPanningWithMouse = true;
                        final panDelta = isAltPressed
                            ? (event.delta.dx.abs() > event.delta.dy.abs() ? Offset(event.delta.dx, 0.0) : Offset(0.0, event.delta.dy))
                            : event.delta;
                        _panCamera(panDelta);
                        return;
                      } else if (isOrbit) {
                        _isOrbitingWithMouse = true;
                        if (isAltPressed) {
                          if (event.delta.dx.abs() > event.delta.dy.abs()) {
                            _orbitCamera(-event.delta.dx * 0.5, 0.0);
                          } else {
                            _orbitCamera(0.0, -event.delta.dy * 0.5);
                          }
                        } else {
                          _orbitCamera(-event.delta.dx * 0.5, -event.delta.dy * 0.5);
                        }
                        return;
                      }

                      if (vm.activeToolMode == SketchUpToolMode.weld && _isDrawingWeld && isPrimary) {
                        _weldDraftPath.add(event.localPosition);
                        final (rayOrigin, rayDir) = _getRayFromScreen(event.localPosition, size, mesh);
                        final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
                        if (hit != null) {
                          if (_weld3DPoints.isEmpty || _weld3DPoints.last.distanceTo(hit.hitPoint) > 2.0) {
                            _weld3DPoints.add(hit.hitPoint);
                          }
                        }
                        _spawnWeldSparks(event.localPosition);
                        _updateWeldSparks(0.016);
                        setState(() {});
                        return;
                      }

                      if (vm.activeToolMode == SketchUpToolMode.rotate) {
                        _handleRotatePointerMove(event.localPosition, size, mesh, vm);
                        return;
                      }

                      if (vm.activeToolMode == SketchUpToolMode.move && _isMovingEntity && _draggingPart != null) {
                        _handleMovePointerMove(event.localPosition, size, mesh, vm);
                        return;
                      }
                    },
                    onPointerUp: (event) {
                      _isOrbitingWithMouse = false;
                      _isPanningWithMouse = false;
                      if (_scene != null && _scene!.renderScale != 1.0) {
                        _scene!.renderScale = 1.0;
                      }
                      if (_selectionBoxStart != null && _selectionBoxCurrent != null) {
                        final start = _selectionBoxStart!;
                        final current = _selectionBoxCurrent!;
                        final rect = Rect.fromPoints(start, current);
                        bool isShift = false;
                        bool isCtrl = false;
                        try {
                          isShift = HardwareKeyboard.instance.isShiftPressed;
                          isCtrl = HardwareKeyboard.instance.isControlPressed;
                        } catch (_) {}
                        if (rect.width > 4 || rect.height > 4) {
                          final isCrossing = current.dx < start.dx;
                          final matchingPartIds = <String>{};
                          for (final part in vm.doc.parts) {
                            if (!part.isVisible) continue;
                            final corners2d = _getPartScreenCorners(part, size, mesh);
                            if (corners2d.isEmpty) continue;
                            if (isCrossing) {
                              final anyInside = corners2d.any((pt) => rect.contains(pt));
                              final partRect = Rect.fromPoints(
                                Offset(corners2d.map((p) => p.dx).reduce(math.min), corners2d.map((p) => p.dy).reduce(math.min)),
                                Offset(corners2d.map((p) => p.dx).reduce(math.max), corners2d.map((p) => p.dy).reduce(math.max)),
                              );
                              if (anyInside || rect.overlaps(partRect)) {
                                matchingPartIds.add(part.id);
                              }
                            } else {
                              final allInside = corners2d.every((pt) => rect.contains(pt));
                              if (allInside) {
                                matchingPartIds.add(part.id);
                              }
                            }
                          }
                          if (isCtrl) {
                            vm.doc.selectedPartIds.addAll(matchingPartIds);
                          } else if (isShift) {
                            vm.doc.selectedPartIds.removeAll(matchingPartIds);
                          } else {
                            vm.doc.selectedPartIds = matchingPartIds;
                            vm.doc.selectedPartId = matchingPartIds.isNotEmpty ? matchingPartIds.first : null;
                          }
                          vm.notifyDocChanged();
                        } else {
                          // Single click on empty canvas deselects
                          if (vm.activeToolMode == SketchUpToolMode.select && !isShift && !isCtrl) {
                            vm.clearSelection();
                          }
                        }
                        setState(() {
                          _selectionBoxStart = null;
                          _selectionBoxCurrent = null;
                        });
                      }

                      if (vm.activeToolMode == SketchUpToolMode.move && _draggingPart != null && _partDragStartScreen != null) {
                        if (_hasMovedPart && (event.localPosition - _partDragStartScreen!).distance > 10.0) {
                          _commitEntityMove(vm);
                        }
                      }

                      if (vm.activeToolMode == SketchUpToolMode.weld && _isDrawingWeld) {
                        _isDrawingWeld = false;
                        _processWeldDraft(event.localPosition, size, mesh, vm);
                        _weldDraftPath.clear();
                        _weldDraftStartScreen = null;
                        setState(() {});
                        return;
                      }

                      if (vm.activeToolMode == SketchUpToolMode.rotate && _hasRotatedPart) {
                        _commitRotation(vm);
                      }

                      _draggingGizmoAxis = GizmoAxis.none;
                      _gizmoDragStartScreen = null;
                      _gizmoDragStartPartPos = null;
                      _gizmoDragStartPartRot = null;
                      _draggingFeature = null;
                      _featureDragStartScreen = null;
                      _featureDragStartPos = null;

                      if (_secondaryDownPos != null) {
                        final dist = (event.localPosition - _secondaryDownPos!).distance;
                        if (dist < 6.0) {
                          final hitPoly = _findFrontmostPolygonUnderCursor(event.localPosition, size, mesh);
                          if (hitPoly != null) {
                            final hitPart = vm.findPartForFaceId(hitPoly.faceId);
                            if (hitPart != null && !vm.doc.selectedPartIds.contains(hitPart.id)) {
                              vm.selectPart(hitPart.id);
                            }
                          }
                          _showContextMenu(event.position);
                        }
                        _secondaryDownPos = null;
                      }
                    },
                    onPointerCancel: (_) {
                      _isOrbitingWithMouse = false;
                      _isPanningWithMouse = false;
                      _cursorScreenPosNotifier.value = null;
                      _draggingPart = null;
                      _partDragStartScreen = null;
                      _hasMovedPart = false;
                      _rotatingPart = null;
                      _partRotateStartScreen = null;
                      _hasRotatedPart = false;
                      _draggedParts.clear();
                      _draggedPartsStartPos.clear();
                      _draggedPartsStartRot.clear();
                      _secondaryDownPos = null;
                      _draggingGizmoAxis = GizmoAxis.none;
                      _gizmoDragStartScreen = null;
                      _gizmoDragStartPartPos = null;
                      _gizmoDragStartPartRot = null;
                      _draggingFeature = null;
                      _featureDragStartScreen = null;
                      _featureDragStartPos = null;
                    },
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        final factor = pointerSignal.scrollDelta.dy < 0 ? 1.15 : 0.85;
                        _zoomCamera(factor);
                      }
                    },
                    child: DragTarget<PendingPartPlacement>(
                      onWillAcceptWithDetails: (details) => true,
                      onAcceptWithDetails: (details) {
                        final renderBox = context.findRenderObject() as RenderBox?;
                        final localPos = renderBox != null ? renderBox.globalToLocal(details.offset) : details.offset;
                        final worldPos = _screenToWorldGround(localPos, size, mesh);
                        vm.setPendingPlacement(details.data);
                        vm.placePendingPartAt(worldPos);
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isDraggingOver = candidateData.isNotEmpty;

                        return Stack(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onDoubleTap: _zoomToFit,
                              onTapUp: (details) {
                                if (vm.isSketchMode || vm.pendingPlacement != null) {
                                  _handleTapUp(details.localPosition, size, mesh);
                                }
                              },
                              child: MouseRegion(
                                cursor: _getCursorForToolMode(vm),
                                child: (_isGpuAvailable && _scene != null && _isSceneReady)
                                    ? RepaintBoundary(child: SceneView(_scene!))
                                    : RepaintBoundary(
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter: FlutterPaint3dPainter(
                                            mesh: mesh,
                                            azimuthDeg: _azimuthDeg,
                                            elevationDeg: _elevationDeg,
                                            zoom: _zoom,
                                            pan: _pan,
                                            showWireframe: vm.onshapeRenderMode != OnshapeRenderMode.shadedWithoutEdges,
                                            isGlassMode: vm.onshapeRenderMode == OnshapeRenderMode.translucent,
                                            isOrthoProjection: vm.isOrthoProjection,
                                            selectedFaceId: vm.doc.selectedPartId ?? vm.doc.selectedFaceId,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            if (isDraggingOver)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFF0284C7), width: 2.5),
                                      color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                                    ),
                                    alignment: Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
                                      ),
                                      child: const Text(
                                        'Release mouse to place part here',
                                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                if (vm.selectedWeldId != null) Positioned(top: 56, left: 0, right: 0, child: AssemblySelectedWeldBanner(viewModel: vm)),

                // =================================================================
                // 1e. MULTI-PART SELECTION & BATCH WELD BANNER
                // =================================================================
                if (vm.selectedPartIds.length >= 2)
                  Positioned(
                    bottom: 80,
                    left: 0,
                    right: 0,
                    child: AssemblySelectionToolbar(viewModel: vm, onPromptGroupNameAndGroup: () => _promptGroupNameAndGroup(vm)),
                  ),

                // =================================================================
                // 1b-0. GLOBAL 3D SCENE AXES (Red X, Green Y, Blue Z - SS1)
                // =================================================================
                if (vm.showGlobalAxes)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _GlobalSceneAxesPainter(size: size, mesh: mesh, projectPoint: (pt) => _projectPoint(pt, size, mesh)),
                      ),
                    ),
                  ),

                // =================================================================
                // 1b. SKETCHUP TRANSLUCENT BOUNDING BOX OVERLAY (Requirement 7 / SS3)
                // =================================================================
                if (!vm.isSketchMode && (vm.selectedPart != null || vm.selectedPartIds.isNotEmpty))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _SelectedPartBoundingBoxPainter(
                          selectedParts: vm.doc.parts.where((p) => p.isVisible && (p.id == vm.selectedPart?.id || vm.selectedPartIds.contains(p.id))).toList(),
                          allParts: vm.doc.parts.where((p) => p.isVisible).toList(),
                          size: size,
                          mesh: mesh,
                          projectPoint: (pt) => _projectPoint(pt, size, mesh),
                          hoveredSnapPoint: _hoveredSnapPointModel,
                          moveBasePoint: _moveBaseWorldPoint,
                          snapDragSourceSnap: _snapDragSourceSnap,
                          snapDragTargetSnap: _snapDragTargetSnap,
                          highlightedTargetPartId: _snapAnimator.highlightedPartId,
                          targetScaleFactor: _snapAnimator.targetScaleFactor,
                          currentSnapDragScreenPos: _currentSnapDragScreenPos,
                          showSnapLabel: vm.activeToolMode != SketchUpToolMode.move,
                        ),
                      ),
                    ),
                  ),

                // =================================================================
                // 2. 3D INTERACTIVE GIZMO LAYER (NON-BLOCKING OVERLAY - MOVE)
                // =================================================================
                if (vm.selectedPart != null && !vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.move)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _AssemblyGizmoPainter(
                          selectedPart: vm.selectedPart!,
                          size: size,
                          mesh: mesh,
                          azimuthDeg: _azimuthDeg,
                          elevationDeg: _elevationDeg,
                          zoom: _zoom,
                          pan: _pan,
                          isOrthoProjection: vm.isOrthoProjection,
                          gizmoMode: vm.gizmoMode,
                          activeAxis: _draggingGizmoAxis,
                          lockedAxis: vm.lockedAxis,
                          projectPoint: (pt) => _projectPoint(pt, size, mesh),
                        ),
                      ),
                    ),
                  ),

                // =================================================================
                // 2a. SKETCHUP 3D PROTRACTOR ROTATE TOOL OVERLAY
                // =================================================================
                if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.rotate)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _SketchUpProtractorOverlayPainter(
                          phase: _rotatePhase,
                          centerPoint: _rotateCenterPoint,
                          baselinePoint: _rotateBaselinePoint,
                          currentArmPoint: _rotateCurrentArmPoint,
                          hoverPoint: _rotateHoverWorldPos,
                          activeAxis: vm.lockedAxis != GizmoAxis.none ? vm.lockedAxis : _rotateAxis,
                          currentAngleDeg: _rotateCurrentAngleDeg,
                          isCopyMode: _isRotateCopyMode,
                          cursorScreenPos: _lastHoverScreenPos,
                          size: size,
                          mesh: mesh,
                          projectPoint: (pt) => _projectPoint(pt, size, mesh),
                        ),
                      ),
                    ),
                  ),

                // =================================================================
                // 2a-2. SKETCHUP MOVE / ORBIT / PAN VECTOR CURSOR OVERLAYS (SS1)
                // =================================================================
                if (_isOrbitingWithMouse || (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.orbit))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<Offset?>(
                        valueListenable: _cursorScreenPosNotifier,
                        builder: (context, cursorPos, _) {
                          return CustomPaint(
                            size: Size.infinite,
                            painter: _SketchUpOrbitCursorPainter(cursorScreenPos: cursorPos ?? _lastHoverScreenPos),
                          );
                        },
                      ),
                    ),
                  ),

                if (_isPanningWithMouse || (!vm.isSketchMode && (vm.activeToolMode == SketchUpToolMode.pan || _isPanToolActive)))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<Offset?>(
                        valueListenable: _cursorScreenPosNotifier,
                        builder: (context, cursorPos, _) {
                          return CustomPaint(
                            size: Size.infinite,
                            painter: _SketchUpPanCursorPainter(cursorScreenPos: cursorPos ?? _lastHoverScreenPos),
                          );
                        },
                      ),
                    ),
                  ),

                if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.move && !_isOrbitingWithMouse && !_isPanningWithMouse)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<Offset?>(
                        valueListenable: _cursorScreenPosNotifier,
                        builder: (context, cursorPos, _) {
                          return CustomPaint(
                            size: Size.infinite,
                            painter: _SketchUpMoveBadgeOverlayPainter(
                              cursorScreenPos: cursorPos ?? _lastHoverScreenPos,
                              isCopyMode: HardwareKeyboard.instance.isControlPressed,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // =================================================================
                // 2b. 3D INTERACTIVE SKETCH ENTITY OVERLAY (HIGHLIGHTS, BENDS, LABELS)
                // =================================================================
                if (vm.isSketchMode && (vm.sketchPartId != null || vm.selectedPart != null))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _AssemblyEntityOverlayPainter(
                          part: vm.doc.parts.where((p) => p.id == vm.sketchPartId).firstOrNull ?? vm.selectedPart!,
                          size: size,
                          mesh: mesh,
                          selectedFeatureId: vm.selectedSketchFeatureId,
                          draggingFeatureId: _draggingFeature?.id,
                          projectPoint: (pt) => _projectPoint(pt, size, mesh),
                        ),
                      ),
                    ),
                  ),

                // =================================================================
                // 2c. INTERACTIVE REAL-WORLD WELDING TORCH BRUSH, BEADS & SPARKS
                // =================================================================
                if (vm.activeToolMode == SketchUpToolMode.weld && _weldDraftPath.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _WeldBeadsBrushPainter(path: _weldDraftPath),
                      ),
                    ),
                  ),

                if (vm.activeToolMode == SketchUpToolMode.weld && _weldSparks.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _WeldSparksPainter(sparks: _weldSparks),
                      ),
                    ),
                  ),

                if (vm.activeToolMode == SketchUpToolMode.weld && !_isOrbitingWithMouse && !_isPanningWithMouse)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<Offset?>(
                        valueListenable: _cursorScreenPosNotifier,
                        builder: (context, cursorPos, _) {
                          return CustomPaint(
                            size: Size.infinite,
                            painter: _SketchUpWeldingTorchCursorPainter(cursorScreenPos: cursorPos ?? _lastHoverScreenPos, isWelding: _isDrawingWeld),
                          );
                        },
                      ),
                    ),
                  ),

                // =================================================================
                // 2d. 3D MAGNETIC SNAP SPOTS & COUPLING OVERLAY
                // =================================================================
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _MagneticSpotsOverlayPainter(
                        parts: vm.doc.parts.where((p) => p.isVisible).toList(),
                        magneticJoints: vm.doc.magneticJoints,
                        isMagneticToolActive: vm.activeToolMode == SketchUpToolMode.magnetic,
                        hoverPoint: _magneticHoverPoint,
                        projectPoint: (pt) => _projectPoint(pt, size, mesh),
                      ),
                    ),
                  ),
                ),

                // Contextual Banner for Auto-Span Bridging Tool (Key: B)
                if (vm.activeToolMode == SketchUpToolMode.bridge)
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                          boxShadow: [BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 2)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.horizontal_distribute_rounded, color: Color(0xFF38BDF8), size: 16),
                            const SizedBox(width: 8),
                            Text(
                              vm.bridgeSourcePartId == null
                                  ? 'Auto-Span Bridge: Click first stile / part'
                                  : 'Bridging: Click destination stile to bridge with auto rungs & welds',
                              style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: vm.cancelBridge,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Contextual Banner for Interactive Weld Tool (Key: W)
                if (vm.activeToolMode == SketchUpToolMode.weld)
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
                          boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 2)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.blur_linear_rounded, color: Color(0xFFF59E0B), size: 16),
                            const SizedBox(width: 8),
                            const Text(
                              'Weld Tool: Click and drag draft line across entity seam to weld',
                              style: TextStyle(color: Color(0xFFF1F5F9), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: () => vm.setToolMode(SketchUpToolMode.select),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Contextual Banner for Magnetic Tool (Key: J)
                if (vm.activeToolMode == SketchUpToolMode.magnetic)
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF818CF8), width: 1.2),
                          boxShadow: [BoxShadow(color: const Color(0xFF818CF8).withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 2)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.hub_rounded, color: Color(0xFF818CF8), size: 16),
                            const SizedBox(width: 8),
                            const Text(
                              'Magnetic Tool: Click surface to place spot',
                              style: TextStyle(color: Color(0xFFF1F5F9), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: () => _showMagneticCouplingDialog(context, vm),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(12)),
                                child: const Text(
                                  'Link Spots Dialog',
                                  style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => vm.setToolMode(SketchUpToolMode.select),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Contextual In-Viewport Warning Banner (Item 5.1 / SS5)
                if (_subtleWarningText != null)
                  Positioned(
                    top: 60,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(maxWidth: math.max(200.0, size.width - 60.0)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                          boxShadow: [BoxShadow(color: const Color(0xFFEF4444).withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 2)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 16),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _subtleWarningText!,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (_subtleWarningActionLabel != null && _subtleWarningAction != null) ...[
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () {
                                  final action = _subtleWarningAction;
                                  _dismissSubtleWarning();
                                  action?.call();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(12)),
                                  child: Text(
                                    _subtleWarningActionLabel!,
                                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _dismissSubtleWarning,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // =================================================================
                // 3. SKETCHUP-STYLE VERTICAL TOOL PALETTE (SS2)
                // =================================================================
                Positioned(
                  top: 14,
                  left: 12,
                  child: AssemblySketchupToolbar(viewModel: vm, onZoomExtents: _zoomToFit),
                ),

                // =================================================================
                // 3b. FLOATING INDUSTRIAL CAD 3D NAVIGATION BAR
                // =================================================================
                if (!vm.isSketchMode)
                  Positioned(
                    top: 14,
                    left: 60,
                    child: Studio3dNavigationBar(
                      onFitAll: _zoomToFit,
                      onSelectView: (az, el) => _setCameraFromAngles(az, el),
                      isTurntable: _isTurntable,
                      onToggleOrbitMode: () {
                        setState(() => _isTurntable = !_isTurntable);
                      },
                      isPanToolActive: _isPanToolActive,
                      onTogglePanTool: () {
                        setState(() => _isPanToolActive = !_isPanToolActive);
                      },
                      isOrtho: vm.isOrthoProjection,
                      onToggleProjection: () {
                        setState(() {
                          vm.isOrthoProjection = !vm.isOrthoProjection;
                        });
                        _updateGpuCamera();
                      },
                      showBorderLines: vm.showWireframe,
                      onToggleBorderLines: () {
                        setState(() {
                          vm.showWireframe = !vm.showWireframe;
                        });
                      },
                      currentShadingStyle: vm.shadingStyle,
                      onShadingStyleChanged: (style) {
                        setState(() {
                          vm.setShadingStyle(style);
                        });
                        _rebuildGpuCadModel();
                      },
                      currentAntiAliasing: vm.graphicsPreferences.antiAliasingQuality,
                      onAntiAliasingChanged: (aa) {
                        setState(() {
                          vm.updateGraphicsPreferences((p) => p.copyWith(antiAliasingQuality: aa));
                        });
                      },
                    ),
                  ),

                // =================================================================
                // 3c. SKETCHUP-STYLE STANDARD VIEWS TOOLBAR (SS3)
                // =================================================================
                if (!vm.isSketchMode && vm.showViewsToolbar)
                  Positioned(
                    top: _viewsToolbarOffset.dy,
                    left: _viewsToolbarOffset.dx,
                    child: AssemblySketchupViewsToolbar(
                      viewModel: vm,
                      onDragUpdate: (details) {
                        setState(() {
                          _viewsToolbarOffset += details.delta;
                        });
                      },
                      onCenterAxes: () {
                        setState(() {
                          _pan = Offset.zero;
                          widget.viewModel.pan = Offset.zero;
                        });
                        _updateGpuCamera();
                      },
                      onResetView: _zoomToFit,
                    ),
                  ),

                // =================================================================
                // 4. STUDIO VIEW CUBE 3D ORIENTATION (TOP RIGHT)
                // =================================================================
                if (!vm.isSketchMode)
                  Positioned(
                    top: 14,
                    right: 14,
                    child: StudioViewCube(
                      azimuthDeg: _azimuthDeg,
                      elevationDeg: _elevationDeg,
                      onOrbit: (dAz, dEl) => _orbitCamera(dAz, dEl),
                      onZoomToFit: _zoomToFit,
                      onSetView: (az, el) => _setCameraFromAngles(az, el),
                      isPerspective: !vm.isOrthoProjection,
                      onTogglePerspective: () {
                        setState(() {
                          vm.isOrthoProjection = !vm.isOrthoProjection;
                        });
                      },
                      renderMode: vm.onshapeRenderMode,
                      onRenderModeChanged: (mode) {
                        vm.onshapeRenderMode = mode;
                        _rebuildGpuCadModel();
                        setState(() {});
                      },
                      onOpenGraphicsPreferences: () {
                        setState(() {
                          vm.isGraphicsPreferencesOpen = true;
                        });
                      },
                      hiddenEdgesVisible: vm.graphicsPreferences.hiddenEdgesVisible,
                      onToggleHiddenEdges: (val) {
                        vm.updateGraphicsPreferences((p) => p.copyWith(hiddenEdgesVisible: val));
                        _rebuildGpuCadModel();
                        setState(() {});
                      },
                      tangentEdgeMode: vm.graphicsPreferences.tangentEdgeMode,
                      onTangentEdgeModeChanged: (mode) {
                        vm.updateGraphicsPreferences((p) => p.copyWith(tangentEdgeMode: mode));
                        _rebuildGpuCadModel();
                        setState(() {});
                      },
                      highlightBoundaryEdges: vm.graphicsPreferences.highlightBoundaryEdges,
                      onToggleHighlightBoundaryEdges: () {
                        vm.updateGraphicsPreferences((p) => p.copyWith(highlightBoundaryEdges: !p.highlightBoundaryEdges));
                        _rebuildGpuCadModel();
                        setState(() {});
                      },
                      isHighQuality: vm.graphicsPreferences.antiAliasingQuality == AntiAliasingQuality.high,
                      onToggleHighQuality: () {
                        final isHigh = vm.graphicsPreferences.antiAliasingQuality == AntiAliasingQuality.high;
                        vm.updateGraphicsPreferences((p) => p.copyWith(antiAliasingQuality: isHigh ? AntiAliasingQuality.off : AntiAliasingQuality.high));
                        _rebuildGpuCadModel();
                        setState(() {});
                      },
                      onZoomToSelection: () {
                        if (vm.selectedPart != null) {
                          _pan = Offset.zero;
                          _zoom = 1.2;
                          _updateGpuCamera();
                          setState(() {});
                        }
                      },
                      onOrientNormal: () {
                        _setCameraFromAngles(0, 0);
                      },
                    ),
                  ),

                // =================================================================
                // 4.5 FLOATING GRAPHICS PREFERENCES PANEL (SS2)
                // =================================================================
                if (vm.isGraphicsPreferencesOpen)
                  Positioned(
                    top: 56,
                    right: 140,
                    child: StudioGraphicsPreferencesPanel(
                      preferences: vm.graphicsPreferences,
                      onChanged: (prefs) {
                        vm.graphicsPreferences = prefs;
                        _rebuildGpuCadModel();
                        setState(() {});
                      },
                      onClose: () {
                        setState(() {
                          vm.isGraphicsPreferencesOpen = false;
                        });
                      },
                      onResetToDefault: () {
                        vm.graphicsPreferences = const OnshapeGraphicsPreferences();
                        _rebuildGpuCadModel();
                        setState(() {});
                      },
                    ),
                  ),

                // =================================================================
                // 5. SKETCHUP-STYLE PRIMARY MOVEMENT & EDIT TOOLBAR (TOP CENTER)
                // =================================================================
                if (!vm.isSketchMode) Positioned(top: 14, left: 0, right: 0, child: Center(child: _buildSketchUpMovementToolbar(vm))),

                // =================================================================
                // 5.5 LIVE OSHA / ISO COMPLIANCE BADGE & CUT LIST BOM (TOP RIGHT)
                // =================================================================
                if (!vm.isSketchMode) Positioned(top: 14, right: 16, child: _buildTopRightStatusPill(context, vm)),

                // =================================================================
                // 6. ONSHAPE-STYLE DIRECT 3D FACE SKETCH HUD (WHEN SKETCHING)
                // =================================================================
                if (vm.isSketchMode && vm.sketchPartId != null) Positioned(top: 14, left: 14, right: 14, child: _buildOnshapeSketchHUD(vm)),

                // =================================================================
                // 7. SELECTED PART / WELD STATUS PILL (BOTTOM CENTER)
                // =================================================================
                if (vm.selectedPart != null && !vm.isSketchMode)
                  Positioned(bottom: 16, left: 16, right: 260, child: Center(child: _buildBottomQuickActionBar(vm))),
                if (vm.selectedWeld != null && !vm.isSketchMode)
                  Positioned(bottom: 16, left: 16, right: 260, child: Center(child: _buildSelectedWeldStatusBar(context, vm))),

                // =================================================================
                // 8. TWO-WAY SELECTION BOX OVERLAY (WINDOW / CROSSING)
                // =================================================================
                if (_selectionBoxStart != null && _selectionBoxCurrent != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _TwoWaySelectionBoxPainter(start: _selectionBoxStart!, current: _selectionBoxCurrent!),
                      ),
                    ),
                  ),

                // =================================================================
                // 9. SKETCHUP MEASUREMENTS VCB HUD (BOTTOM RIGHT)
                // =================================================================
                Positioned(bottom: 16, right: 16, child: _buildMeasurementsVcbHud(vm)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // GIZMO HIT-TESTING & 60FPS DRAG COMPUTATION
  // ---------------------------------------------------------------------------
  GizmoAxis _hitTestGizmo(Offset clickPos, Size size, FoldedMeshResult mesh, AssemblyPart part, GizmoMode mode) {
    final center3d = part.position;
    final centerScreen = _projectPoint(center3d, size, mesh);
    if (centerScreen == Offset.zero) return GizmoAxis.none;

    const double axisLen = 65.0;
    final ptX = _projectPoint(CadPoint3D(center3d.x + axisLen, center3d.y, center3d.z), size, mesh);
    final ptY = _projectPoint(CadPoint3D(center3d.x, center3d.y + axisLen, center3d.z), size, mesh);
    final ptZ = _projectPoint(CadPoint3D(center3d.x, center3d.y, center3d.z + axisLen), size, mesh);

    if (mode == GizmoMode.translate) {
      if (_distToSegment(clickPos, centerScreen, ptX) < 18.0) return GizmoAxis.x;
      if (_distToSegment(clickPos, centerScreen, ptY) < 18.0) return GizmoAxis.y;
      if (_distToSegment(clickPos, centerScreen, ptZ) < 18.0) return GizmoAxis.z;
    } else {
      final d = (clickPos - centerScreen).distance;
      if ((d - 45.0).abs() < 12.0) return GizmoAxis.x;
      if ((d - 55.0).abs() < 12.0) return GizmoAxis.y;
      if ((d - 65.0).abs() < 12.0) return GizmoAxis.z;
    }

    return GizmoAxis.none;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final l2 = (b - a).distanceSquared;
    if (l2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - proj).distance;
  }

  void _handleGizmoDragUpdate(Offset currentPos, Size size, FoldedMeshResult mesh) {
    final part = widget.viewModel.selectedPart;
    if (part == null || _gizmoDragStartScreen == null) return;
    if (widget.viewModel.isPartBonded(part.id)) {
      widget.viewModel.setVcbState(label: '🔒 Welded Entity', value: 'Locked by Weld', hint: 'Break weld joint first to move with Gizmo.');
      return;
    }

    final screenDelta = currentPos - _gizmoDragStartScreen!;
    final center3d = part.position;
    final centerScreen = _projectPoint(center3d, size, mesh);
    const double axisLen = 65.0;

    if (widget.viewModel.gizmoMode == GizmoMode.translate && _gizmoDragStartPartPos != null) {
      CadPoint3D axisWorldDir;
      Offset axisScreenPoint;
      switch (_draggingGizmoAxis) {
        case GizmoAxis.x:
          axisWorldDir = const CadPoint3D(1.0, 0.0, 0.0);
          axisScreenPoint = _projectPoint(CadPoint3D(center3d.x + axisLen, center3d.y, center3d.z), size, mesh);
          break;
        case GizmoAxis.y:
          axisWorldDir = const CadPoint3D(0.0, 1.0, 0.0);
          axisScreenPoint = _projectPoint(CadPoint3D(center3d.x, center3d.y + axisLen, center3d.z), size, mesh);
          break;
        case GizmoAxis.z:
          axisWorldDir = const CadPoint3D(0.0, 0.0, 1.0);
          axisScreenPoint = _projectPoint(CadPoint3D(center3d.x, center3d.y, center3d.z + axisLen), size, mesh);
          break;
        case GizmoAxis.none:
          return;
      }

      final axisScreenVec = axisScreenPoint - centerScreen;
      final screenLen = axisScreenVec.distance;
      double mmDelta = 0.0;
      if (screenLen > 1.0) {
        final dot = (screenDelta.dx * axisScreenVec.dx + screenDelta.dy * axisScreenVec.dy) / screenLen;
        mmDelta = dot * (axisLen / screenLen);
      } else {
        mmDelta = screenDelta.dx;
      }

      var newX = _gizmoDragStartPartPos!.x + axisWorldDir.x * mmDelta;
      var newY = _gizmoDragStartPartPos!.y + axisWorldDir.y * mmDelta;
      var newZ = _gizmoDragStartPartPos!.z + axisWorldDir.z * mmDelta;

      if (widget.viewModel.snapToGrid) {
        final step = widget.viewModel.gridStepMm;
        newX = (newX / step).round() * step;
        newY = (newY / step).round() * step;
        newZ = (newZ / step).round() * step;
      }

      widget.viewModel.updatePartPosition(part.id, CadPoint3D(newX, newY, newZ));
    } else if (widget.viewModel.gizmoMode == GizmoMode.rotate && _gizmoDragStartPartRot != null) {
      final rotDelta = screenDelta.dx * 0.8;
      var rx = _gizmoDragStartPartRot!.x;
      var ry = _gizmoDragStartPartRot!.y;
      var rz = _gizmoDragStartPartRot!.z;

      switch (_draggingGizmoAxis) {
        case GizmoAxis.x:
          rx = (rx + rotDelta) % 360.0;
          break;
        case GizmoAxis.y:
          ry = (ry + rotDelta) % 360.0;
          break;
        case GizmoAxis.z:
          rz = (rz + rotDelta) % 360.0;
          break;
        case GizmoAxis.none:
          break;
      }

      if (widget.viewModel.snapToGrid) {
        rx = widget.viewModel.snapRotationAngle(rx);
        ry = widget.viewModel.snapRotationAngle(ry);
        rz = widget.viewModel.snapRotationAngle(rz);
      }

      widget.viewModel.updatePartRotation(part.id, CadPoint3D(rx, ry, rz));
    }
  }

  // ---------------------------------------------------------------------------
  // SKETCH ENTITY HIT-TESTING & FREE 3D DRAGGING
  // ---------------------------------------------------------------------------
  AssemblySketchFeature? _hitTestSketchFeature(Offset clickPos, Size size, FoldedMeshResult mesh, AssemblyPart part) {
    for (final sk in part.sketches.reversed) {
      final center3d = part.toWorld(CadPoint3D(sk.localCenter.x, 0.0, sk.localCenter.y));
      final screenPos = _projectPoint(center3d, size, mesh);
      if (screenPos == Offset.zero) continue;

      if (sk.featureType == 'bend_line') {
        final top3d = part.toWorld(CadPoint3D(sk.localCenter.x, 0.0, part.height));
        final topScreen = _projectPoint(top3d, size, mesh);
        final bot3d = part.toWorld(CadPoint3D(sk.localCenter.x, 0.0, 0.0));
        final botScreen = _projectPoint(bot3d, size, mesh);
        if (_distToSegment(clickPos, botScreen, topScreen) < 16.0) {
          return sk;
        }
      } else {
        if ((clickPos - screenPos).distance < 20.0) {
          return sk;
        }
      }
    }
    return null;
  }

  void _handleFeatureDragUpdate(Offset currentPos, Size size, FoldedMeshResult mesh) {
    final part = widget.viewModel.selectedPart ?? widget.viewModel.doc.parts.where((p) => p.id == widget.viewModel.sketchPartId).firstOrNull;
    if (part == null || _featureDragStartScreen == null || _featureDragStartPos == null || _draggingFeature == null) {
      return;
    }
    if (_draggingFeature!.matedRungPartId != null || widget.viewModel.isPartBonded(part.id)) {
      return;
    }

    final screenDelta = currentPos - _featureDragStartScreen!;

    final originScreen = _projectPoint(part.position, size, mesh);
    final xScreen = _projectPoint(CadPoint3D(part.position.x + 100.0, part.position.y, part.position.z), size, mesh);
    final zScreen = _projectPoint(CadPoint3D(part.position.x, part.position.y, part.position.z + 100.0), size, mesh);

    final xVec = xScreen - originScreen;
    final zVec = zScreen - originScreen;

    double deltaMmX = 0.0;
    double deltaMmY = 0.0;

    if (xVec.distance > 1.0) {
      final dotX = (screenDelta.dx * xVec.dx + screenDelta.dy * xVec.dy) / xVec.distance;
      deltaMmX = dotX * (100.0 / xVec.distance);
    }
    if (zVec.distance > 1.0) {
      final dotZ = (screenDelta.dx * zVec.dx + screenDelta.dy * zVec.dy) / zVec.distance;
      deltaMmY = dotZ * (100.0 / zVec.distance);
    }

    var newX = _featureDragStartPos!.x + deltaMmX;
    var newY = _featureDragStartPos!.y + deltaMmY;

    if (widget.viewModel.snapToGrid) {
      final step = widget.viewModel.gridStepMm;
      newX = (newX / step).round() * step;
      newY = (newY / step).round() * step;
    }

    newX = newX.clamp(10.0, math.max(10.0, part.length - 10.0)).toDouble();
    newY = newY.clamp(5.0, math.max(5.0, part.height - 5.0)).toDouble();

    widget.viewModel.setSketchFeaturePosition(part.id, _draggingFeature!.id, newX, newY);
  }

  // ---------------------------------------------------------------------------
  // DIRECT 3D TAP HANDLING & FACE CLICKING
  // ---------------------------------------------------------------------------
  void _handleTapUp(Offset localPos, Size size, FoldedMeshResult mesh) {
    final vm = widget.viewModel;

    if (vm.activeToolMode == SketchUpToolMode.move || vm.activeToolMode == SketchUpToolMode.rotate) {
      return;
    }

    if (_hasMovedPart) {
      _hasMovedPart = false;
      return;
    }

    // 1. Pending Part Placement (Click-to-Place Mode) (Requirement 2, Way 1)
    if (vm.pendingPlacement != null) {
      final worldPos = _screenToWorldGround(localPos, size, mesh);
      vm.placePendingPartAt(worldPos);
      return;
    }

    // 2. DIRECT 3D SKETCHING ON THE MODEL (REAL-TIME 3D):
    if (vm.isSketchMode) {
      final part = vm.doc.parts.where((p) => p.id == vm.sketchPartId).firstOrNull ?? vm.selectedPart;
      if (part == null) return;

      // Check if clicked directly on an existing entity to select it
      final hitFeat = _hitTestSketchFeature(localPos, size, mesh, part);
      if (hitFeat != null) {
        vm.selectSketchFeature(hitFeat.id);
        return;
      }

      if (vm.activeSketchTool == 'select_entity') {
        vm.selectSketchFeature(null);
        return;
      }

      final cx = size.width / 2.0 + _pan.dx;
      final cy = size.height / 2.0 + _pan.dy;

      final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
      final fitDim = maxDim > 0 ? maxDim : 400.0;
      final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
      final scale = baseScale * _zoom;

      final relScreenX = localPos.dx - cx;
      final relScreenY = localPos.dy - cy;

      final worldX = relScreenX / scale + (mesh.boundWidth / 2.0);
      final worldZ = -relScreenY / scale + (mesh.boundHeight / 2.0);

      final localX = worldX - part.position.x;
      final localZ = worldZ - part.position.z;

      if (localX >= -25.0 && localX <= part.length + 25.0 && localZ >= -25.0 && localZ <= part.height + 25.0) {
        final clampedX = localX.clamp(10.0, math.max(10.0, part.length - 10.0)).toDouble();
        final clampedZ = localZ.clamp(5.0, math.max(5.0, part.height - 5.0)).toDouble();

        if (vm.activeSketchTool == 'rung_slot') {
          vm.punchRungSlot(railId: part.id, distanceX: clampedX);
        } else if (vm.activeSketchTool == 'bend_line') {
          vm.addSketchFeature(featureType: 'bend_line', localCenter: CadPoint2D(clampedX, clampedZ), widthMm: 2.0, heightMm: part.height);
        } else {
          vm.addSketchFeature(
            featureType: vm.activeSketchTool,
            localCenter: CadPoint2D(clampedX, clampedZ),
            widthMm: vm.sketchToolParamWidth,
            heightMm: vm.sketchToolParamHeight,
          );
        }
      }
      return;
    }

    // 3. Normal Selection Mode: Raycast frontmost polygon under cursor (Requirement 3: Whole Part Selection)
    final hitPoly = _findFrontmostPolygonUnderCursor(localPos, size, mesh);
    bool isMulti = false;
    try {
      isMulti = HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isControlPressed;
    } catch (_) {}

    if (hitPoly != null) {
      vm.selectFace(hitPoly.faceId, multiSelect: isMulti);
    } else {
      if (!isMulti) {
        vm.clearSelection();
      }
    }
  }

  /// Projects a 2D screen coordinate into 3D CAD world space onto the ground plane (Y = 0)
  CadPoint3D _screenToWorldGround(Offset screenPos, Size size, FoldedMeshResult mesh) {
    if (size.width <= 0 || size.height <= 0) return const CadPoint3D(0.0, 0.0, 0.0);
    final cx = size.width / 2.0 + _pan.dx;
    final cy = size.height / 2.0 + _pan.dy;

    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 400.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * _zoom;
    final pivot = mesh.center;
    final cameraDist = math.max(fitDim * 2.5, 1000.0);

    final relScreenX = (screenPos.dx - cx) / (scale > 0 ? scale : 1.0);
    final relScreenY = -(screenPos.dy - cy) / (scale > 0 ? scale : 1.0);

    final m = _computeRotationMatrix(_azimuthDeg, _elevationDeg);

    // Ray direction in camera space:
    final dirCamX = widget.viewModel.isOrthoProjection ? 0.0 : relScreenX / cameraDist;
    final dirCamY = widget.viewModel.isOrthoProjection ? 0.0 : relScreenY / cameraDist;
    final dirCamZ = -1.0;

    // Transform direction to world space via inverse rotation (m^T):
    final dirWx = dirCamX * m[0] + dirCamY * m[4] + dirCamZ * m[8];
    final dirWy = dirCamX * m[1] + dirCamY * m[5] + dirCamZ * m[9];
    final dirWz = dirCamX * m[2] + dirCamY * m[6] + dirCamZ * m[10];

    // Eye origin in world space:
    final eyeWx = pivot.x + (relScreenX * m[0] + relScreenY * m[4]) + (m[8] * cameraDist);
    final eyeWy = pivot.y + (relScreenX * m[1] + relScreenY * m[5]) + (m[9] * cameraDist);
    final eyeWz = pivot.z + (relScreenX * m[2] + relScreenY * m[6]) + (m[10] * cameraDist);

    // Intersect ray with ground plane Y = 0:
    double hitX = pivot.x + (relScreenX * m[0] + relScreenY * m[4]);
    double hitZ = pivot.z + (relScreenX * m[2] + relScreenY * m[6]);

    if (dirWy.abs() > 1e-4) {
      final t = (0.0 - eyeWy) / dirWy;
      if (t > 0) {
        hitX = eyeWx + t * dirWx;
        hitZ = eyeWz + t * dirWz;
      }
    }

    // Snap to 10mm increments for clean CAD layout:
    final snappedX = (hitX / 10.0).round() * 10.0;
    final snappedZ = (hitZ / 10.0).round() * 10.0;

    return CadPoint3D(snappedX, 0.0, snappedZ);
  }

  (vm_math.Vector3, vm_math.Vector3) _getRayFromScreen(Offset cursorLocalPos, Size size, FoldedMeshResult mesh) {
    _initCameraTargetIfNeeded(mesh);
    final pivot = _cameraPivot;
    if (_isGpuAvailable && _scene != null && _isSceneReady) {
      final camera = _cameraComponent.toCamera();
      final ray = camera.screenPointToRay(cursorLocalPos, size);
      final rayDir = ray.direction.normalized();
      final rayOrigin = ray.origin + vm_math.Vector3(pivot.x, pivot.y, pivot.z);
      return (rayOrigin, rayDir);
    } else {
      final cx = size.width / 2.0 + _pan.dx;
      final cy = size.height / 2.0 + _pan.dy;

      final fitDim = _cameraFitDim > 0 ? _cameraFitDim : 200.0;
      final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
      final scale = baseScale * _zoom;
      final cameraDist = math.max(fitDim * 2.5, 1000.0);

      final relScreenX = (cursorLocalPos.dx - cx) / (scale > 0 ? scale : 1.0);
      final relScreenY = -(cursorLocalPos.dy - cy) / (scale > 0 ? scale : 1.0);

      final m = _computeRotationMatrix(_azimuthDeg, _elevationDeg);
      final isOrtho = widget.viewModel.isOrthoProjection;

      if (isOrtho) {
        final eyeWx = pivot.x + (relScreenX * m[0] + relScreenY * m[4]) + (m[8] * cameraDist);
        final eyeWy = pivot.y + (relScreenX * m[1] + relScreenY * m[5]) + (m[9] * cameraDist);
        final eyeWz = pivot.z + (relScreenX * m[2] + relScreenY * m[6]) + (m[10] * cameraDist);
        final rayOrigin = vm_math.Vector3(eyeWx, eyeWy, eyeWz);
        final rayDir = vm_math.Vector3(-m[8], -m[9], -m[10]).normalized();
        return (rayOrigin, rayDir);
      } else {
        final eyeWx = pivot.x + (m[8] * cameraDist);
        final eyeWy = pivot.y + (m[9] * cameraDist);
        final eyeWz = pivot.z + (m[10] * cameraDist);
        final rayOrigin = vm_math.Vector3(eyeWx, eyeWy, eyeWz);

        final dirWx = relScreenX * m[0] + relScreenY * m[4] - (m[8] * cameraDist);
        final dirWy = relScreenX * m[1] + relScreenY * m[5] - (m[9] * cameraDist);
        final dirWz = relScreenX * m[2] + relScreenY * m[6] - (m[10] * cameraDist);
        final rayDir = vm_math.Vector3(dirWx, dirWy, dirWz).normalized();
        return (rayOrigin, rayDir);
      }
    }
  }

  CadFoldedPolygon3D? _findFrontmostPolygonUnderCursor(Offset cursorLocalPos, Size size, FoldedMeshResult mesh) {
    if (mesh.allPolygons.isEmpty || size.width <= 0 || size.height <= 0) return null;

    final (rayOrigin, rayDir) = _getRayFromScreen(cursorLocalPos, size, mesh);

    // 1. Direct 3D Raycast against all model polygons (true frontmost surface)
    final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
    if (hit != null) {
      return hit.polygon;
    }

    // 2. Proximity boundary edge snapping (within 8.0px tolerance only)
    return AssemblyRaycaster.findClosestEdgePolygon(
      cursorLocalPos: cursorLocalPos,
      size: size,
      mesh: mesh,
      projectPoint: (pt) => _projectPoint(pt, size, mesh),
      maxScreenDistance: 8.0,
    );
  }

  Future<void> _promptGroupNameAndGroup(AssemblyStudioViewModel vm) async {
    final name = await AssemblyViewportDialogs.promptGroupName(context, vm);
    if (!mounted || name == null) return;
    final gid = vm.groupSelectedParts(name: name);
    if (gid != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Created virtual group "$name" (${vm.doc.parts.where((p) => p.groupId == gid).length} parts)'),
          backgroundColor: const Color(0xFF0369A1),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showContextMenu(Offset globalPos) async {
    await AssemblyViewportDialogs.showContextMenu(
      context,
      globalPos,
      widget.viewModel,
      onZoomToFit: _zoomToFit,
      onPromptGroupNameAndGroup: () => _promptGroupNameAndGroup(widget.viewModel),
    );
  }

  Offset _projectPointPaint(CadPoint3D p, Size size, FoldedMeshResult mesh) {
    if (size.width <= 0 || size.height <= 0) return Offset.zero;
    final cx = size.width / 2.0 + _pan.dx;
    final cy = size.height / 2.0 + _pan.dy;

    _initCameraTargetIfNeeded(mesh);
    final fitDim = _cameraFitDim > 0 ? _cameraFitDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * _zoom;

    final pivot = _cameraPivot;
    final cameraDist = math.max(fitDim * 2.5, 1000.0);

    final rx = p.x - pivot.x;
    final ry = p.y - pivot.y;
    final rz = p.z - pivot.z;

    final m = _computeRotationMatrix(_azimuthDeg, _elevationDeg);
    final x2 = rx * m[0] + ry * m[1] + rz * m[2];
    final y2 = rx * m[4] + ry * m[5] + rz * m[6];
    final z2 = rx * m[8] + ry * m[9] + rz * m[10];

    final isOrtho = widget.viewModel.isOrthoProjection;
    final persp = isOrtho ? 1.0 : (cameraDist / math.max(cameraDist - z2, cameraDist * 0.15));

    final sx = cx + (x2 * persp) * scale;
    final sy = cy - (y2 * persp) * scale;

    return Offset(sx, sy);
  }

  Offset _projectPoint(CadPoint3D p, Size size, FoldedMeshResult mesh) {
    if (size.width <= 0 || size.height <= 0) return Offset.zero;
    if (_isGpuAvailable && _scene != null && _isSceneReady) {
      final camera = _cameraComponent.toCamera();
      _initCameraTargetIfNeeded(mesh);
      final pivot = _cameraPivot;
      final worldPt = vm_math.Vector3(p.x - pivot.x, p.y - pivot.y, p.z - pivot.z);
      final screenPt = camera.worldToScreen(worldPt, size);
      return screenPt ?? Offset.zero;
    }
    return _projectPointPaint(p, size, mesh);
  }

  @visibleForTesting
  Offset projectPointForTest(CadPoint3D p, Size size) {
    return _projectPoint(p, size, widget.viewModel.assemblyMesh);
  }

  List<double> _computeRotationMatrix(double azimuthDeg, double elevationDeg) {
    final azRad = azimuthDeg * math.pi / 180.0;
    final elRad = elevationDeg * math.pi / 180.0;
    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    return [cosAz, sinAz, 0.0, 0.0, -sinEl * sinAz, sinEl * cosAz, cosEl, 0.0, cosEl * sinAz, -cosEl * cosAz, sinEl, 0.0, 0.0, 0.0, 0.0, 1.0];
  }

  // ---------------------------------------------------------------------------
  // SKETCHUP-STYLE PRIMARY MOVEMENT TOOLBAR (TOP CENTER)
  // ---------------------------------------------------------------------------
  Widget _buildSketchUpMovementToolbar(AssemblyStudioViewModel vm) {
    return AssemblyMovementToolbar(
      viewModel: vm,
      onRebuildGpu: () {
        setState(() {});
        _rebuildGpuCadModel();
      },
      onShowMagneticCouplingDialog: () => _showMagneticCouplingDialog(context, vm),
    );
  }

  // ---------------------------------------------------------------------------
  // ONSHAPE DIRECT 3D SKETCH HUD
  // ---------------------------------------------------------------------------
  Widget _buildOnshapeSketchHUD(AssemblyStudioViewModel vm) {
    return AssemblySketchHud(viewModel: vm);
  }

  // ---------------------------------------------------------------------------
  // BOTTOM QUICK ACTION BAR
  // ---------------------------------------------------------------------------
  Widget _buildBottomQuickActionBar(AssemblyStudioViewModel vm) {
    return AssemblyQuickActionBar(viewModel: vm);
  }

  // ---------------------------------------------------------------------------
  // SELECTED WELD STATUS BAR (BOTTOM CENTER)
  // ---------------------------------------------------------------------------
  Widget _buildSelectedWeldStatusBar(BuildContext context, AssemblyStudioViewModel vm) {
    return AssemblySelectedWeldStatusBar(viewModel: vm);
  }

  // ---------------------------------------------------------------------------
  // TOP RIGHT STATUS PILL (OSHA / ISO COMPLIANCE BADGE & BOM BUTTON)
  // ---------------------------------------------------------------------------
  Widget _buildTopRightStatusPill(BuildContext context, AssemblyStudioViewModel vm) {
    return AssemblyViewportStatusPill(
      viewModel: vm,
      onShowComplianceAuditDialog: () => _showComplianceAuditDialog(context, vm),
      onShowBomDialog: () => _showBomDialog(context, vm),
    );
  }

  void _showComplianceAuditDialog(BuildContext context, AssemblyStudioViewModel vm) {
    AssemblyViewportDialogs.showComplianceAuditDialog(context, vm);
  }

  void _showBomDialog(BuildContext context, AssemblyStudioViewModel vm) {
    AssemblyViewportDialogs.showBomDialog(context, vm);
  }

  Widget _buildMeasurementsVcbHud(AssemblyStudioViewModel vm) {
    return AssemblyVcbHud(
      viewModel: vm,
      controller: _vcbController,
      focusNode: _vcbFocusNode,
      onClear: () {
        if (_isMovingEntity) {
          _cancelEntityMove(vm);
        }
        _vcbController.clear();
        vm.vcbValue = '';
        vm.notifyDocChanged();
      },
      onChanged: (val) {
        if (_isMovingEntity) {
          _applyVcbTextToMovingEntity(val, vm);
        } else if (vm.activeToolMode == SketchUpToolMode.rotate && (_rotatePhase == RotateToolPhase.rotatingAngle || _draggedParts.isNotEmpty)) {
          _applyVcbTextToRotatingEntity(val, vm);
        }
      },
      onSubmitted: (val) {
        if (_isMovingEntity) {
          final clean = val.replaceAll('mm', '').replaceAll('cm', '').replaceAll('m', '').replaceAll('in', '').replaceAll('ft', '').trim();
          final parsed = double.tryParse(clean);
          if (parsed == null || clean.isEmpty) {
            _cancelEntityMove(vm);
            _vcbController.clear();
            _viewportFocusNode.requestFocus();
            return;
          }
          _commitEntityMove(vm);
          _vcbController.clear();
          _viewportFocusNode.requestFocus();
          return;
        }
        if (vm.activeToolMode == SketchUpToolMode.rotate && (_rotatePhase == RotateToolPhase.rotatingAngle || _draggedParts.isNotEmpty)) {
          final clean = val.replaceAll('°', '').replaceAll('deg', '').trim();
          final parsed = double.tryParse(clean);
          if (parsed == null || clean.isEmpty) {
            _cancelRotation(vm);
            _vcbController.clear();
            _viewportFocusNode.requestFocus();
            return;
          }
          _applyVcbTextToRotatingEntity(clean, vm);
          _commitRotation(vm);
          _vcbController.clear();
          _viewportFocusNode.requestFocus();
          return;
        }
        if (val.trim().isNotEmpty) {
          vm.submitVcbInput(val.trim());
          _vcbController.clear();
          _viewportFocusNode.requestFocus();
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TWO-WAY SELECTION BOX HELPER: PROJECTED SCREEN CORNERS OF PART
  // ---------------------------------------------------------------------------
  List<Offset> _getPartScreenCorners(AssemblyPart part, Size size, FoldedMeshResult mesh) {
    // First, if mesh has polygons corresponding to this part, extract all projected screen vertices
    final matchingPolys = mesh.allPolygons.where((poly) => poly.faceId == part.id || poly.faceId.startsWith('${part.id}_'));
    if (matchingPolys.isNotEmpty) {
      final pts = <Offset>[];
      for (final poly in matchingPolys) {
        for (final v in poly.vertices) {
          pts.add(_projectPoint(v, size, mesh));
        }
      }
      if (pts.isNotEmpty) return pts;
    }

    // Fallback: 8 bounding box corners around part position and dimensions
    final l = part.length > 0 ? part.length : 100.0;
    final h = part.height > 0 ? part.height : 40.0;
    final w = part.flangeWidth > 0 ? part.flangeWidth * 2 : 40.0;

    final corners = <CadPoint3D>[
      part.toWorld(const CadPoint3D(0, 0, 0)),
      part.toWorld(CadPoint3D(l, 0, 0)),
      part.toWorld(CadPoint3D(0, w, 0)),
      part.toWorld(CadPoint3D(l, w, 0)),
      part.toWorld(CadPoint3D(0, 0, h)),
      part.toWorld(CadPoint3D(l, 0, h)),
      part.toWorld(CadPoint3D(0, w, h)),
      part.toWorld(CadPoint3D(l, w, h)),
    ];

    return corners.map((p) => _projectPoint(p, size, mesh)).toList();
  }

  // ---------------------------------------------------------------------------
  // SKETCHUP 3-CLICK ROTATE TOOL HELPERS
  // ---------------------------------------------------------------------------
  CadPoint3D _intersectPlane(Offset screenPos, Size size, FoldedMeshResult mesh, GizmoAxis axis, CadPoint3D planeOrigin) {
    return AssemblyRotateMathHelper.intersectPlane(
      screenPos: screenPos,
      size: size,
      mesh: mesh,
      axis: axis,
      planeOrigin: planeOrigin,
      getRay: _getRayFromScreen,
    );
  }

  double _calculateSignedAngleDeg({required CadPoint3D center, required CadPoint3D baselinePt, required CadPoint3D currentPt, required GizmoAxis axis}) {
    return AssemblyRotateMathHelper.calculateSignedAngleDeg(center: center, baselinePt: baselinePt, currentPt: currentPt, axis: axis);
  }

  (CadPoint3D, CadPoint3D) _computeRotatedTransform({
    required CadPoint3D startPos,
    required CadPoint3D startRot,
    required CadPoint3D centerPoint,
    required GizmoAxis axis,
    required double angleDeg,
  }) {
    return AssemblyRotateMathHelper.computeRotatedTransform(startPos: startPos, startRot: startRot, centerPoint: centerPoint, axis: axis, angleDeg: angleDeg);
  }

  void _commitRotation(AssemblyStudioViewModel vm) {
    if (_rotateCurrentAngleDeg.abs() > 0.001 && _draggedParts.isNotEmpty) {
      if (!_hasRotatedPart) {
        _hasRotatedPart = true;
        vm.recordHistory();
      }
      final targetPart = _rotatingPart ?? _draggedParts.first;
      vm.recordLastRotate(
        partId: targetPart.id,
        deltaDeg: _rotateCurrentAngleDeg,
        centerPoint: _rotateCenterPoint,
        axis: vm.lockedAxis != GizmoAxis.none ? vm.lockedAxis : _rotateAxis,
      );
      vm.notifyDocChanged();
      vm.invalidateMeshCache();
      _rebuildGpuCadModel(force: true);
    }
    _rotatePhase = RotateToolPhase.awaitingCenter;
    _rotateCenterPoint = null;
    _rotateBaselinePoint = null;
    _rotateCurrentArmPoint = null;
    _rotateCurrentAngleDeg = 0.0;
    _partRotateStartScreen = null;
    _draggedParts.clear();
    _draggedPartsStartRot.clear();
    _draggedPartsStartPos.clear();
    _rotatingPart = null;
    _hasClonedForRotate = false;
    setState(() {});
  }

  void _cancelRotation(AssemblyStudioViewModel vm) {
    for (final part in _draggedParts) {
      final startRot = _draggedPartsStartRot[part.id];
      final startPos = _draggedPartsStartPos[part.id];
      if (startRot != null) part.rotationDeg = startRot;
      if (startPos != null) part.position = startPos;
    }
    _rotatePhase = RotateToolPhase.awaitingCenter;
    _rotateCenterPoint = null;
    _rotateBaselinePoint = null;
    _rotateCurrentArmPoint = null;
    _rotateCurrentAngleDeg = 0.0;
    _partRotateStartScreen = null;
    _draggedParts.clear();
    _draggedPartsStartRot.clear();
    _draggedPartsStartPos.clear();
    _rotatingPart = null;
    _hasClonedForRotate = false;
    vm.setVcbState(label: 'Rotate', value: 'Cancelled', hint: 'Click 1 to place center');
    vm.invalidateMeshCache();
    _rebuildGpuCadModel(force: true);
    vm.notifyDocChanged();
    setState(() {});
  }

  void _commitEntityMove(AssemblyStudioViewModel vm) {
    if (_hasMovedPart) {
      vm.recordHistory();
    }
    _isMovingEntity = false;
    _moveBaseWorldPoint = null;
    _moveBaseStartWorldPoint = null;
    _hoveredSnapPointModel = null;
    _hoveredSnapPoint = null;
    _draggingPart = null;
    _partDragStartScreen = null;
    _hasMovedPart = false;
    _draggedParts.clear();
    _draggedPartsStartPos.clear();
    vm.invalidateMeshCache();
    _rebuildGpuCadModel(force: true);
    vm.notifyDocChanged();
    vm.setVcbState(label: 'Move', value: 'Placed', hint: 'Click entity point or surface to move again');
    setState(() {});
  }

  void _cancelEntityMove(AssemblyStudioViewModel vm) {
    for (final part in _draggedParts) {
      final startPos = _draggedPartsStartPos[part.id];
      if (startPos != null) {
        part.position = startPos;
      }
    }
    _isMovingEntity = false;
    _moveBaseWorldPoint = null;
    _moveBaseStartWorldPoint = null;
    _hoveredSnapPointModel = null;
    _hoveredSnapPoint = null;
    _draggingPart = null;
    _partDragStartScreen = null;
    _hasMovedPart = false;
    _draggedParts.clear();
    _draggedPartsStartPos.clear();
    vm.invalidateMeshCache();
    _rebuildGpuCadModel(force: true);
    vm.notifyDocChanged();
    vm.setVcbState(label: 'Move', value: 'Cancelled', hint: 'Click entity point or surface to move');
    setState(() {});
  }

  void _applyVcbTextToMovingEntity(String rawText, AssemblyStudioViewModel vm) {
    if (!_isMovingEntity || _draggedParts.isEmpty || _draggingPart == null) return;
    final cleanText = rawText
        .replaceAll('mm', '')
        .replaceAll('cm', '')
        .replaceAll('m', '')
        .replaceAll('in', '')
        .replaceAll('ft', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();
    final targetDist = double.tryParse(cleanText);

    if (targetDist == null || cleanText.isEmpty) {
      // Requirement 2: If the value is invalid or blank then the object should assume the original position!
      for (final part in _draggedParts) {
        final startPos = _draggedPartsStartPos[part.id];
        if (startPos != null) {
          part.position = startPos;
        }
      }
      _moveBaseWorldPoint = _moveBaseStartWorldPoint;
      vm.invalidateMeshCache();
      _rebuildGpuCadModel(force: true);
      setState(() {});
      return;
    }

    // Valid distance: translate along locked axis or current move vector
    final distMm = targetDist * vm.lengthUnit.toMmFactor;
    final refStartPos = _draggedPartsStartPos[_draggingPart!.id] ?? _draggingPart!.position;
    final baseAnchor = _moveBaseStartWorldPoint ?? refStartPos;

    CadPoint3D axisWorldDir;
    if (vm.lockedAxis == GizmoAxis.x) {
      axisWorldDir = const CadPoint3D(1.0, 0.0, 0.0);
    } else if (vm.lockedAxis == GizmoAxis.y) {
      axisWorldDir = const CadPoint3D(0.0, 1.0, 0.0);
    } else if (vm.lockedAxis == GizmoAxis.z) {
      axisWorldDir = const CadPoint3D(0.0, 0.0, 1.0);
    } else {
      final curPos = _draggingPart!.position;
      final curDelta = CadPoint3D(curPos.x - refStartPos.x, curPos.y - refStartPos.y, curPos.z - refStartPos.z);
      final curLen = math.sqrt(curDelta.x * curDelta.x + curDelta.y * curDelta.y + curDelta.z * curDelta.z);
      if (curLen > 1e-4) {
        axisWorldDir = CadPoint3D(curDelta.x / curLen, curDelta.y / curLen, curDelta.z / curLen);
      } else {
        axisWorldDir = const CadPoint3D(1.0, 0.0, 0.0);
      }
    }

    final worldDelta = CadPoint3D(axisWorldDir.x * distMm, axisWorldDir.y * distMm, axisWorldDir.z * distMm);

    for (final part in _draggedParts) {
      final startPos = _draggedPartsStartPos[part.id] ?? part.position;
      part.position = CadPoint3D(startPos.x + worldDelta.x, startPos.y + worldDelta.y, startPos.z + worldDelta.z);
    }
    _moveBaseWorldPoint = CadPoint3D(baseAnchor.x + worldDelta.x, baseAnchor.y + worldDelta.y, baseAnchor.z + worldDelta.z);

    _hasMovedPart = true;
    vm.invalidateMeshCache();
    _rebuildGpuCadModel(force: true);
    setState(() {});
  }

  void _applyVcbTextToRotatingEntity(String rawText, AssemblyStudioViewModel vm) {
    if (_draggedParts.isEmpty && vm.selectedPartIds.isNotEmpty) {
      final selected = vm.doc.parts.where((p) => vm.selectedPartIds.contains(p.id)).toList();
      if (selected.isNotEmpty) {
        _draggedParts.addAll(selected);
        for (final p in selected) {
          _draggedPartsStartRot[p.id] = p.rotationDeg;
          _draggedPartsStartPos[p.id] = p.position;
        }
      }
    }
    if (_draggedParts.isEmpty) return;

    final cleanText = rawText.replaceAll('°', '').replaceAll('deg', '').trim();
    final targetAngle = double.tryParse(cleanText);

    if (targetAngle == null || cleanText.isEmpty) {
      // Restore the object to its original position/rotation when invalid or empty
      for (final part in _draggedParts) {
        final startRot = _draggedPartsStartRot[part.id];
        final startPos = _draggedPartsStartPos[part.id];
        if (startRot != null) part.rotationDeg = startRot;
        if (startPos != null) part.position = startPos;
      }
      _rotateCurrentAngleDeg = 0.0;
      vm.invalidateMeshCache();
      _rebuildGpuCadModel(force: true);
      setState(() {});
      return;
    }

    _rotateCurrentAngleDeg = targetAngle;
    final activeAxis = vm.lockedAxis != GizmoAxis.none ? vm.lockedAxis : _rotateAxis;
    final center = _rotateCenterPoint ?? _draggedParts.first.position;

    for (final part in _draggedParts) {
      final startRot = _draggedPartsStartRot[part.id] ?? part.rotationDeg;
      final startPos = _draggedPartsStartPos[part.id] ?? part.position;
      final (newPos, newRot) = _computeRotatedTransform(startPos: startPos, startRot: startRot, centerPoint: center, axis: activeAxis, angleDeg: targetAngle);
      part.position = newPos;
      part.rotationDeg = newRot;
    }

    _hasRotatedPart = true;
    vm.invalidateMeshCache();
    _rebuildGpuCadModel(force: true);
    setState(() {});
  }

  void _spawnWeldSparks(Offset origin) {
    final rng = math.Random();
    final count = 7 + rng.nextInt(7);
    for (int i = 0; i < count; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = 40.0 + rng.nextDouble() * 150.0;
      final vx = math.cos(angle) * speed;
      final vy = math.sin(angle) * speed - 35.0; // slight upward eruption
      final life = 0.25 + rng.nextDouble() * 0.45;
      final colors = [
        const Color(0xFFFFFFFF),
        const Color(0xFFFEF08A),
        const Color(0xFFFBBF24),
        const Color(0xFFF97316),
        const Color(0xFF38BDF8),
        const Color(0xFF00E5FF),
      ];
      _weldSparks.add(
        _WeldSparkParticle(
          position: origin + Offset((rng.nextDouble() - 0.5) * 6, (rng.nextDouble() - 0.5) * 6),
          velocity: Offset(vx, vy),
          life: life,
          maxLife: life,
          size: 1.5 + rng.nextDouble() * 2.5,
          color: colors[rng.nextInt(colors.length)],
        ),
      );
    }
  }

  void _updateWeldSparks(double dt) {
    if (_weldSparks.isEmpty) return;
    for (int i = _weldSparks.length - 1; i >= 0; i--) {
      final s = _weldSparks[i];
      s.life -= dt;
      if (s.life <= 0) {
        _weldSparks.removeAt(i);
      } else {
        s.position += s.velocity * dt;
        s.velocity += const Offset(0, 180.0) * dt; // gravity
      }
    }
  }

  void _handleMovePointerMove(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (_draggingPart == null || _draggedParts.isEmpty) return;

    final primaryPart = _draggingPart!;
    final refStartPos = _draggedPartsStartPos[primaryPart.id] ?? primaryPart.position;
    final baseAnchor = _moveBaseStartWorldPoint ?? _moveBaseWorldPoint ?? refStartPos;

    CadPoint3D worldDelta;

    // Detect candidate snap points on other visible parts (excluding currently moving parts)
    final otherSnapPoints = <AssemblySnapPoint>[];
    for (final p in vm.doc.parts) {
      if (!p.isVisible || _draggedParts.any((dp) => dp.id == p.id)) continue;
      otherSnapPoints.addAll(AssemblyDockingEngine.getAllSnapPointsForPart(p, cachedMesh: mesh));
    }

    final targetSnap = AssemblyDockingEngine.findNearestSnapPoint(
      screenCursor: localPos,
      candidates: otherSnapPoints,
      projectPoint: (pt) => _projectPoint(pt, size, mesh),
      maxPixelDistance: 18.0,
    );

    if (targetSnap != null) {
      _hoveredSnapPointModel = targetSnap;
      _hoveredSnapPoint = targetSnap.worldPosition;
    } else {
      _hoveredSnapPointModel = null;
      _hoveredSnapPoint = null;
    }

    if (vm.lockedAxis != GizmoAxis.none) {
      // 1. Constrained move along locked Axis (Right Arrow = X Red, Left Arrow = Y Green, Up Arrow = Z Blue)
      final CadPoint3D axisWorldDir;
      switch (vm.lockedAxis) {
        case GizmoAxis.x:
          axisWorldDir = const CadPoint3D(1.0, 0.0, 0.0);
          break;
        case GizmoAxis.y:
          axisWorldDir = const CadPoint3D(0.0, 1.0, 0.0);
          break;
        case GizmoAxis.z:
          axisWorldDir = const CadPoint3D(0.0, 0.0, 1.0);
          break;
        case GizmoAxis.none:
          axisWorldDir = const CadPoint3D(1.0, 0.0, 0.0);
          break;
      }

      double s = 0.0;
      if (targetSnap != null) {
        // Snap inferencing along locked axis: project target snap coordinate onto axis line passing through baseAnchor
        final diff = CadPoint3D(
          targetSnap.worldPosition.x - baseAnchor.x,
          targetSnap.worldPosition.y - baseAnchor.y,
          targetSnap.worldPosition.z - baseAnchor.z,
        );
        s = diff.x * axisWorldDir.x + diff.y * axisWorldDir.y + diff.z * axisWorldDir.z;
      } else {
        // 3D Ray-to-Line closest point calculation
        final (vm_math.Vector3 rayOrigin, vm_math.Vector3 rayDir) = _getRayFromScreen(localPos, size, mesh);
        final rLen = math.sqrt(rayDir.x * rayDir.x + rayDir.y * rayDir.y + rayDir.z * rayDir.z);
        final CadPoint3D v = rLen > 1e-6 ? CadPoint3D(rayDir.x / rLen, rayDir.y / rLen, rayDir.z / rLen) : CadPoint3D(rayDir.x, rayDir.y, rayDir.z);

        final w0 = CadPoint3D(baseAnchor.x - rayOrigin.x, baseAnchor.y - rayOrigin.y, baseAnchor.z - rayOrigin.z);
        final b = axisWorldDir.x * v.x + axisWorldDir.y * v.y + axisWorldDir.z * v.z;
        final d = axisWorldDir.x * w0.x + axisWorldDir.y * w0.y + axisWorldDir.z * w0.z;
        final e = v.x * w0.x + v.y * w0.y + v.z * w0.z;
        final denom = 1.0 - b * b;

        if (denom > 1e-4) {
          s = (b * e - d) / denom;
        } else {
          // Ray nearly parallel to axis line: fallback to screen displacement projected onto axis screen vector
          final axisScr = _projectPoint(
            CadPoint3D(baseAnchor.x + axisWorldDir.x * 100, baseAnchor.y + axisWorldDir.y * 100, baseAnchor.z + axisWorldDir.z * 100),
            size,
            mesh,
          );
          final centerScr = _projectPoint(baseAnchor, size, mesh);
          final scrVec = axisScr - centerScr;
          final scrLen = scrVec.distance;
          final scrDelta = _partDragStartScreen != null ? (localPos - _partDragStartScreen!) : Offset.zero;
          if (scrLen > 1.0) {
            s = ((scrDelta.dx * scrVec.dx + scrDelta.dy * scrVec.dy) / scrLen) * (100.0 / scrLen);
          }
        }
      }

      final precisionStep = vm.precisionMovementStepMm;
      if (precisionStep > 0) {
        s = (s / precisionStep).round() * precisionStep;
      } else if (vm.snapToGrid) {
        final step = vm.gridStepMm;
        s = (s / step).round() * step;
      }

      worldDelta = CadPoint3D(axisWorldDir.x * s, axisWorldDir.y * s, axisWorldDir.z * s);
    } else {
      // 2. Free movement: check snap candidates across other parts first, else intersect plane
      if (targetSnap != null) {
        worldDelta = CadPoint3D(
          targetSnap.worldPosition.x - baseAnchor.x,
          targetSnap.worldPosition.y - baseAnchor.y,
          targetSnap.worldPosition.z - baseAnchor.z,
        );
      } else {
        final hitPlanePos = _intersectPlane(localPos, size, mesh, GizmoAxis.z, baseAnchor);
        var dx = hitPlanePos.x - baseAnchor.x;
        var dy = hitPlanePos.y - baseAnchor.y;
        var dz = hitPlanePos.z - baseAnchor.z;

        final precisionStep = vm.precisionMovementStepMm;
        if (precisionStep > 0) {
          dx = (dx / precisionStep).round() * precisionStep;
          dy = (dy / precisionStep).round() * precisionStep;
          dz = (dz / precisionStep).round() * precisionStep;
        } else if (vm.snapToGrid) {
          final step = vm.gridStepMm;
          dx = (dx / step).round() * step;
          dy = (dy / step).round() * step;
          dz = (dz / step).round() * step;
        }

        worldDelta = CadPoint3D(dx, dy, dz);
      }
    }

    _hasMovedPart = true;

    // Apply synchronized translation to all parts in the rigid cluster
    for (final part in _draggedParts) {
      final startPos = _draggedPartsStartPos[part.id] ?? part.position;
      part.position = CadPoint3D(startPos.x + worldDelta.x, startPos.y + worldDelta.y, startPos.z + worldDelta.z);
    }

    // Keep base anchor point moving synchronously
    _moveBaseWorldPoint = CadPoint3D(baseAnchor.x + worldDelta.x, baseAnchor.y + worldDelta.y, baseAnchor.z + worldDelta.z);

    // Synchronous GPU and mesh update
    vm.invalidateMeshCache();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastGpuRebuildMs >= 16) {
      _lastGpuRebuildMs = now;
      _rebuildGpuCadModel(force: true);
    }

    final dist = math.sqrt(worldDelta.x * worldDelta.x + worldDelta.y * worldDelta.y + worldDelta.z * worldDelta.z);
    final axisLockStr = vm.lockedAxis == GizmoAxis.x
        ? ' [X Red]'
        : (vm.lockedAxis == GizmoAxis.y ? ' [Y Green]' : (vm.lockedAxis == GizmoAxis.z ? ' [Z Blue]' : ''));
    final snapStr = targetSnap != null ? ' • Snapped to ${targetSnap.label}' : '';
    final formattedDist = vm.formatLength(dist);
    vm.setVcbState(label: 'Distance$axisLockStr', value: formattedDist, hint: 'Click anywhere to place • Esc to cancel$snapStr');

    setState(() {});
  }

  void _handleRotatePointerHover(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    final activeAxis = vm.lockedAxis != GizmoAxis.none ? vm.lockedAxis : _rotateAxis;

    if (_rotatePhase == RotateToolPhase.awaitingCenter) {
      // 1. Check snapping to candidate points (corners, edge centers, hole centers, sketch endpoints)
      final candidatePoints = <CadPoint3D>[];
      for (final p in vm.doc.parts) {
        if (!p.isVisible) continue;
        candidatePoints.addAll(p.getAllSnapCandidatePoints());
      }
      final snappedPt = AssemblyRaycaster.snapToCandidatePoints(
        cursorPos: localPos,
        candidatePoints: candidatePoints,
        projectPoint: (pt) => _projectPoint(pt, size, mesh),
        pixelTolerance: 16.0,
      );

      if (snappedPt != null) {
        _rotateHoverWorldPos = snappedPt;
      } else {
        final (rayOrigin, rayDir) = _getRayFromScreen(localPos, size, mesh);
        final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
        if (hit != null) {
          _rotateHoverWorldPos = hit.hitPoint;
          if (vm.lockedAxis == GizmoAxis.none) {
            final n = hit.polygon.normal;
            if (n.z.abs() >= n.x.abs() && n.z.abs() >= n.y.abs()) {
              _rotateAxis = GizmoAxis.z;
            } else if (n.x.abs() >= n.y.abs()) {
              _rotateAxis = GizmoAxis.x;
            } else {
              _rotateAxis = GizmoAxis.y;
            }
          }
        } else {
          final refOrigin = vm.selectedPart?.position ?? const CadPoint3D(0, 0, 0);
          _rotateHoverWorldPos = AssemblyRotateMathHelper.intersectPlane(
            screenPos: localPos,
            size: size,
            mesh: mesh,
            axis: activeAxis,
            planeOrigin: refOrigin,
            getRay: _getRayFromScreen,
          );
        }
      }
      setState(() {});
    } else if (_rotatePhase == RotateToolPhase.awaitingBaseline && _rotateCenterPoint != null) {
      _rotateCurrentArmPoint = AssemblyRotateMathHelper.intersectPlane(
        screenPos: localPos,
        size: size,
        mesh: mesh,
        axis: activeAxis,
        planeOrigin: _rotateCenterPoint!,
        getRay: _getRayFromScreen,
      );
      setState(() {});
    } else if (_rotatePhase == RotateToolPhase.rotatingAngle && _rotateCenterPoint != null && _rotateBaselinePoint != null) {
      _rotateCurrentArmPoint = AssemblyRotateMathHelper.intersectPlane(
        screenPos: localPos,
        size: size,
        mesh: mesh,
        axis: activeAxis,
        planeOrigin: _rotateCenterPoint!,
        getRay: _getRayFromScreen,
      );
      final rawAngle = _calculateSignedAngleDeg(
        center: _rotateCenterPoint!,
        baselinePt: _rotateBaselinePoint!,
        currentPt: _rotateCurrentArmPoint!,
        axis: activeAxis,
      );
      final centerScreen = _projectPoint(_rotateCenterPoint!, size, mesh);
      final screenRadius = AssemblyRotateMathHelper.computeProtractorScreenRadius(
        center: _rotateCenterPoint!,
        axis: activeAxis,
        size: size,
        mesh: mesh,
        projectPoint: (pt) => _projectPoint(pt, size, mesh),
      );
      final snappedAngle = AssemblyRotateMathHelper.snapRotateAngle(
        rawAngleDeg: rawAngle,
        cursorScreen: localPos,
        centerScreen: centerScreen,
        screenRadius: screenRadius,
        snapToGrid: vm.snapToGrid,
      );
      _rotateCurrentAngleDeg = snappedAngle;

      if (_isRotateCopyMode && !_hasClonedForRotate && _draggedParts.isNotEmpty) {
        _hasClonedForRotate = true;
        final template = _draggedParts.first;
        final clone = vm.clonePartForMove(template);
        _rotatingPart = clone;
        _draggedParts.clear();
        _draggedParts.add(clone);
        _draggedPartsStartRot[clone.id] = clone.rotationDeg;
        _draggedPartsStartPos[clone.id] = clone.position;
      }

      for (final part in _draggedParts) {
        final startRot = _draggedPartsStartRot[part.id];
        final startPos = _draggedPartsStartPos[part.id];
        if (startRot != null && startPos != null) {
          final (newPos, newRot) = _computeRotatedTransform(
            startPos: startPos,
            startRot: startRot,
            centerPoint: _rotateCenterPoint!,
            axis: activeAxis,
            angleDeg: snappedAngle,
          );
          part.position = newPos;
          part.rotationDeg = newRot;
        }
      }
      vm.setVcbState(
        label: 'Angle',
        value: '${snappedAngle.toStringAsFixed(1)}°',
        hint: _isRotateCopyMode ? 'Click to commit copy, or type angle' : 'Click to commit rotation, or type angle',
      );
      vm.invalidateMeshCache();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastGpuRebuildMs >= 16) {
        _lastGpuRebuildMs = now;
        _rebuildGpuCadModel(force: true);
      }
      setState(() {});
    }
  }

  void _handleRotatePointerMove(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (_partRotateStartScreen != null) {
      final dragDist = (localPos - _partRotateStartScreen!).distance;
      if (dragDist > 5.0) {
        if (!_hasRotatedPart) {
          _hasRotatedPart = true;
          vm.recordHistory();
        }
        if (_rotatePhase == RotateToolPhase.awaitingBaseline && _rotateCenterPoint != null) {
          final activeAxis = vm.lockedAxis != GizmoAxis.none ? vm.lockedAxis : _rotateAxis;
          var basePt = AssemblyRotateMathHelper.intersectPlane(
            screenPos: _partRotateStartScreen!,
            size: size,
            mesh: mesh,
            axis: activeAxis,
            planeOrigin: _rotateCenterPoint!,
            getRay: _getRayFromScreen,
          );
          final diff = CadPoint3D(basePt.x - _rotateCenterPoint!.x, basePt.y - _rotateCenterPoint!.y, basePt.z - _rotateCenterPoint!.z);
          if (diff.distanceTo(const CadPoint3D(0, 0, 0)) < 1.0) {
            // Drag started at center: default to canonical axis on the rotation plane
            if (activeAxis == GizmoAxis.z) {
              basePt = CadPoint3D(_rotateCenterPoint!.x + 100.0, _rotateCenterPoint!.y, _rotateCenterPoint!.z);
            } else if (activeAxis == GizmoAxis.x) {
              basePt = CadPoint3D(_rotateCenterPoint!.x, _rotateCenterPoint!.y + 100.0, _rotateCenterPoint!.z);
            } else {
              basePt = CadPoint3D(_rotateCenterPoint!.x + 100.0, _rotateCenterPoint!.y, _rotateCenterPoint!.z);
            }
          }
          _rotateBaselinePoint = basePt;
          _rotatePhase = RotateToolPhase.rotatingAngle;
        }
      }
    }
    _handleRotatePointerHover(localPos, size, mesh, vm);
  }

  void _handleRotatePointerDown(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    _lastHoverScreenPos = localPos;
    final activeAxis = vm.lockedAxis != GizmoAxis.none ? vm.lockedAxis : _rotateAxis;
    final hitPoly = _findFrontmostPolygonUnderCursor(localPos, size, mesh);
    final hitPart = hitPoly != null ? vm.findPartForFaceId(hitPoly.faceId) : null;

    // If user clicked on an entity that is not selected, select it ONLY if no part is currently selected
    if (hitPart != null && !vm.doc.selectedPartIds.contains(hitPart.id)) {
      if (vm.selectedPart == null) {
        vm.selectPart(hitPart.id);
      }
    }

    final targetPart =
        hitPart ?? (vm.doc.selectedPartIds.isNotEmpty ? vm.doc.parts.where((p) => vm.doc.selectedPartIds.contains(p.id)).firstOrNull : vm.selectedPart);

    if (_rotatePhase == RotateToolPhase.awaitingCenter) {
      // Check if target entity to rotate is welded
      if (hitPart != null && vm.isPartBonded(hitPart.id)) {
        vm.setVcbState(label: '🔒 Welded Entity', value: 'Locked by Weld', hint: 'Break weld joint first to rotate.');
        _showSubtleWarning(
          'Part "${hitPart.name}" is welded. Break weld joint first to rotate.',
          actionLabel: 'Break Weld',
          onAction: () => vm.breakAllBondsForPart(hitPart.id),
        );
        return;
      }

      // Phase 1: Set Pivot Center Point (Snap point on entity, entity body, or empty area plane)
      CadPoint3D? centerPt;

      // 1. Check candidate snap points across all visible parts first
      final candidatePoints = <CadPoint3D>[];
      for (final p in vm.doc.parts) {
        if (!p.isVisible) continue;
        candidatePoints.addAll(p.getAllSnapCandidatePoints());
      }
      final snappedPt = AssemblyRaycaster.snapToCandidatePoints(
        cursorPos: localPos,
        candidatePoints: candidatePoints,
        projectPoint: (pt) => _projectPoint(pt, size, mesh),
        pixelTolerance: 20.0,
      );

      if (hitPart != null) {
        // Direct click on entity body: pivot at entity position for in-place rotation
        centerPt = hitPart.position;
      } else if (snappedPt != null) {
        // User clicked a corner/snap point: pivot exactly around that point!
        centerPt = snappedPt;
      } else {
        // 2. Work Plane Intersection in Empty Area
        centerPt = _rotateHoverWorldPos ?? _intersectPlane(localPos, size, mesh, activeAxis, targetPart?.position ?? const CadPoint3D(0, 0, 0));
      }

      if (hitPoly != null && vm.lockedAxis == GizmoAxis.none) {
        final (rayOrigin, rayDir) = _getRayFromScreen(localPos, size, mesh);
        final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
        if (hit != null) {
          final n = hit.polygon.normal;
          if (n.z.abs() >= n.x.abs() && n.z.abs() >= n.y.abs()) {
            _rotateAxis = GizmoAxis.z;
          } else if (n.x.abs() >= n.y.abs()) {
            _rotateAxis = GizmoAxis.x;
          } else {
            _rotateAxis = GizmoAxis.y;
          }
        }
      }

      _rotateCenterPoint = centerPt;
      _rotateHoverWorldPos = centerPt;
      _rotatePhase = RotateToolPhase.awaitingBaseline;
      _rotateBaselinePoint = null;
      _rotateCurrentArmPoint = null;
      _rotateCurrentAngleDeg = 0.0;
      _partRotateStartScreen = localPos;
      _hasRotatedPart = false;
      _hasClonedForRotate = false;

      // Populate parts to rotate
      _draggedParts.clear();
      _draggedPartsStartRot.clear();
      _draggedPartsStartPos.clear();
      if (vm.doc.selectedPartIds.isNotEmpty) {
        _draggedParts.addAll(vm.doc.parts.where((p) => vm.doc.selectedPartIds.contains(p.id)));
      } else if (targetPart != null) {
        _draggedParts.add(targetPart);
      }
      for (final p in _draggedParts) {
        _draggedPartsStartRot[p.id] = p.rotationDeg;
        _draggedPartsStartPos[p.id] = p.position;
      }
      if (_draggedParts.isNotEmpty) {
        _rotatingPart = _draggedParts.first;
      }
      vm.recordHistory();

      vm.setVcbState(label: 'Rotate', value: 'Pivot set', hint: 'Click 2 to set reference baseline (0.0°)');
      setState(() {});
      return;
    } else if (_rotatePhase == RotateToolPhase.awaitingBaseline && _rotateCenterPoint != null) {
      // Phase 2: Set Reference Baseline (0.0°)
      final basePt = AssemblyRotateMathHelper.intersectPlane(
        screenPos: localPos,
        size: size,
        mesh: mesh,
        axis: activeAxis,
        planeOrigin: _rotateCenterPoint!,
        getRay: _getRayFromScreen,
      );
      _rotateBaselinePoint = basePt;
      _rotatePhase = RotateToolPhase.rotatingAngle;
      _rotateCurrentArmPoint = basePt;
      _rotateCurrentAngleDeg = 0.0;

      vm.setVcbState(label: 'Angle', value: '0.0°', hint: 'Click 3 to commit, or type angle in VCB');
      setState(() {});
      return;
    } else if (_rotatePhase == RotateToolPhase.rotatingAngle) {
      // Phase 3: Commit Rotation!
      _commitRotation(vm);
      return;
    }
  }

  // ---------------------------------------------------------------------------
  // INTERACTIVE DRAFT-LINE WELDING TOOL LOGIC (Requirement 4)
  // ---------------------------------------------------------------------------
  void _processWeldDraft(Offset endScreen, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (_weldDraftStartScreen == null && _weldDraftPath.isEmpty) return;
    final startScreen = _weldDraftStartScreen ?? _weldDraftPath.first;
    final screenDist = (endScreen - startScreen).distance;
    if (screenDist < 4.0 && _weld3DPoints.length < 2) {
      vm.setVcbState(label: 'Weld Tool', value: 'Drag across seam', hint: 'Click and drag torch across seam of entities to paint beads');
      return;
    }

    final (rayStartOrigin, rayStartDir) = _getRayFromScreen(startScreen, size, mesh);
    final (rayEndOrigin, rayEndDir) = _getRayFromScreen(endScreen, size, mesh);

    final hitStart = AssemblyRaycaster.raycast(rayOrigin: rayStartOrigin, rayDirection: rayStartDir, mesh: mesh);
    final hitEnd = AssemblyRaycaster.raycast(rayOrigin: rayEndOrigin, rayDirection: rayEndDir, mesh: mesh);

    AssemblyPart? partA = hitStart != null ? vm.findPartForFaceId(hitStart.polygon.faceId) : null;
    AssemblyPart? partB = hitEnd != null ? vm.findPartForFaceId(hitEnd.polygon.faceId) : null;

    if (partA == null || partB == null || partA.id == partB.id) {
      for (double t = 0.2; t <= 0.8; t += 0.2) {
        final sampleScreen = Offset.lerp(startScreen, endScreen, t)!;
        final (sampleRayOrigin, sampleRayDir) = _getRayFromScreen(sampleScreen, size, mesh);
        final sampleHit = AssemblyRaycaster.raycast(rayOrigin: sampleRayOrigin, rayDirection: sampleRayDir, mesh: mesh);
        if (sampleHit != null) {
          final p = vm.findPartForFaceId(sampleHit.polygon.faceId);
          if (p != null) {
            if (partA == null) {
              partA = p;
            } else if (partB == null && p.id != partA.id) {
              partB = p;
            }
          }
        }
      }
    }

    // Inspect entities along 3D sampled surface points
    if (partA == null || partB == null || partA.id == partB.id) {
      for (final pt in _weld3DPoints) {
        for (final p in vm.doc.parts) {
          if (!p.isVisible) continue;
          final dist = (p.position.x - pt.x).abs() + (p.position.y - pt.y).abs() + (p.position.z - pt.z).abs();
          if (dist < 400.0) {
            if (partA == null) {
              partA = p;
            } else if (partB == null && p.id != partA.id) {
              partB = p;
            }
          }
        }
      }
    }

    if (partA != null && (partB == null || partB.id == partA.id)) {
      partB = vm.doc.parts.where((p) => p.isVisible && p.id != partA!.id).fold<AssemblyPart?>(null, (closest, p) {
        final dist = (p.position.x - partA!.position.x).abs() + (p.position.y - partA.position.y).abs() + (p.position.z - partA.position.z).abs();
        if (dist < 500.0) return p;
        return closest;
      });
    }

    if (partA == null || partB == null || partA.id == partB.id) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Could not detect 2 entities along weld stroke. Drag torch across seam.'), duration: Duration(seconds: 2)));
      return;
    }

    CadPoint3D weldPt;
    CadPoint3D axisVector;
    CadPoint3D? leg1 = hitStart?.polygon.normal;
    CadPoint3D? leg2 = hitEnd?.polygon.normal;
    double seamLength;

    if (_weld3DPoints.length >= 2) {
      final pFirst = _weld3DPoints.first;
      final pLast = _weld3DPoints.last;
      weldPt = CadPoint3D((pFirst.x + pLast.x) / 2.0, (pFirst.y + pLast.y) / 2.0, (pFirst.z + pLast.z) / 2.0);
      axisVector = CadPoint3D(pLast.x - pFirst.x, pLast.y - pFirst.y, pLast.z - pFirst.z);
      double totalDist = 0.0;
      for (int i = 1; i < _weld3DPoints.length; i++) {
        totalDist += _weld3DPoints[i].distanceTo(_weld3DPoints[i - 1]);
      }
      seamLength = totalDist > 5.0 ? totalDist : axisVector.length;
    } else if (hitStart != null && hitEnd != null) {
      weldPt = CadPoint3D(
        (hitStart.hitPoint.x + hitEnd.hitPoint.x) / 2.0,
        (hitStart.hitPoint.y + hitEnd.hitPoint.y) / 2.0,
        (hitStart.hitPoint.z + hitEnd.hitPoint.z) / 2.0,
      );
      axisVector = CadPoint3D(hitEnd.hitPoint.x - hitStart.hitPoint.x, hitEnd.hitPoint.y - hitStart.hitPoint.y, hitEnd.hitPoint.z - hitStart.hitPoint.z);
      seamLength = axisVector.length;
    } else {
      weldPt = CadPoint3D(
        (partA.position.x + partB.position.x) / 2.0,
        (partA.position.y + partB.position.y) / 2.0,
        (partA.position.z + partB.position.z) / 2.0,
      );
      axisVector = const CadPoint3D(1.0, 0.0, 0.0);
      seamLength = 60.0;
    }

    if (axisVector.length < 1e-4) {
      axisVector = const CadPoint3D(1.0, 0.0, 0.0);
    }
    seamLength = seamLength.clamp(15.0, 600.0);

    // Pass the sampled 3D points directly to ensure the bead follows the dragged surface path
    final pathPts = _weld3DPoints.length >= 2 ? List<CadPoint3D>.from(_weld3DPoints) : null;

    vm.weldParts(
      partA.id,
      partB.id,
      weldPoint: weldPt,
      weldAxis: axisVector,
      legDir1: leg1,
      legDir2: leg2,
      weldLengthMm: seamLength,
      bothSides: false,
      pathPoints: pathPts,
    );

    if (vm.doc.welds.isNotEmpty) {
      vm.selectWeld(vm.doc.welds.last.id);
    }

    _rebuildGpuCadModel(force: true);

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Fillet Weld Bead created between ${partA.name} and ${partB.name} (${seamLength.toInt()}mm)'),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF0F766E),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAGNETIC SNAP TOOL LOGIC (Requirement 7)
  // ---------------------------------------------------------------------------
  void _handleMagneticPointerHover(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (mesh.allPolygons.isEmpty) return;
    final (rayOrigin, rayDir) = _getRayFromScreen(localPos, size, mesh);
    final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
    if (hit != null) {
      final part = vm.findPartForFaceId(hit.polygon.faceId);
      if (part != null) {
        setState(() {
          _magneticHoverPoint = hit.hitPoint;
          _magneticHoverNormal = hit.polygon.normal;
          _magneticHoverPart = part;
        });
        vm.setVcbState(label: 'Magnetic Spot', value: part.name, hint: 'Click to place magnetic snap spot on surface');
        return;
      }
    }
    if (_magneticHoverPoint != null) {
      setState(() {
        _magneticHoverPoint = null;
        _magneticHoverNormal = null;
        _magneticHoverPart = null;
      });
    }
  }

  void _handleMagneticPointerDown(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (_magneticHoverPart != null && _magneticHoverPoint != null) {
      final part = _magneticHoverPart!;
      final localPt = part.toLocal(_magneticHoverPoint!);
      final spot = vm.addMagneticSpot(part.id, localPt, _magneticHoverNormal ?? const CadPoint3D(0.0, 0.0, 1.0));

      if (spot != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Magnetic spot placed on "${part.name}"'), duration: const Duration(seconds: 2), backgroundColor: const Color(0xFF6366F1)),
        );

        final partsWithSpots = vm.doc.parts.where((p) => p.magneticSpots.isNotEmpty).toList();
        if (partsWithSpots.length >= 2) {
          _showMagneticCouplingDialog(context, vm);
        }
      }
    }
  }

  void _showMagneticCouplingDialog(BuildContext context, AssemblyStudioViewModel vm) {
    AssemblyViewportDialogs.showMagneticCouplingDialog(context, vm, onRebuildGpu: () => _rebuildGpuCadModel(force: true));
  }
}

// =============================================================================
// MODULAR VIEWPORT PAINTER ALIASES (Backward Compatibility)
// =============================================================================
typedef _GlobalSceneAxesPainter = AssemblyGlobalSceneAxesPainter;
typedef _AssemblyGizmoPainter = AssemblyGizmoPainter;
typedef _AssemblyEntityOverlayPainter = AssemblyEntityOverlayPainter;
typedef _TwoWaySelectionBoxPainter = AssemblyTwoWaySelectionBoxPainter;
typedef _SketchUpProtractorOverlayPainter = AssemblyProtractorOverlayPainter;
typedef _SelectedPartBoundingBoxPainter = AssemblySelectedPartBoundingBoxPainter;
typedef _SketchUpMoveBadgeOverlayPainter = AssemblyMoveBadgeOverlayPainter;
typedef _SketchUpOrbitCursorPainter = AssemblyOrbitCursorPainter;
typedef _SketchUpPanCursorPainter = AssemblyPanCursorPainter;
typedef _WeldSparkParticle = AssemblyWeldSparkParticle;
typedef _WeldSparksPainter = AssemblyWeldSparksPainter;
typedef _WeldBeadsBrushPainter = AssemblyWeldBeadsBrushPainter;
typedef _SketchUpWeldingTorchCursorPainter = AssemblyWeldingTorchCursorPainter;
typedef _MagneticSpotsOverlayPainter = AssemblyMagneticSpotsOverlayPainter;
