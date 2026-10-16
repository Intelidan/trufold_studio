import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
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
import '../../engine/sketch/assembly_surface_sketch_engine.dart' hide WeldJointStyle;
import '../../engine/sketch/onshape_sketch_modify_engine.dart';

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
  final ValueNotifier<int> _cameraRepaintNotifier = ValueNotifier<int>(0);

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
  final Map<String, CadPoint3D> _draggedWeldsStartPos = {};
  final Map<String, CadPoint3D?> _draggedWeldsStartSecPos = {};
  final Map<String, List<CadPoint3D>?> _draggedWeldsStartPathPoints = {};
  Offset? _partDragStartScreen;
  bool _hasMovedPart = false;
  bool _isMovingEntity = false;
  CadPoint3D? _moveBaseWorldPoint;
  CadPoint3D? _moveBaseStartWorldPoint;
  final List<AssemblySnapPoint> _cachedMoveOtherSnapPoints = [];

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
  String? _lastSelectedWeldId;
  OnshapeRenderMode? _lastRenderMode;
  CadMaterialPresetType? _lastPreset;
  bool _lastShowWireframe = true;
  OnshapeGraphicsPreferences? _lastGraphicsPreferences;

  // Interactive Draft-Line Welding Tool State
  Offset? _weldDraftStartScreen;
  final List<Offset> _weldDraftPath = [];
  final List<CadPoint3D> _weld3DPoints = [];
  final List<double> _weldTimestamps = [];
  final Stopwatch _weldStopwatch = Stopwatch();
  final Set<String> _weldHitPartIds = {};
  final List<_WeldSparkParticle> _weldSparks = [];
  bool _isDrawingWeld = false;
  double _weldFlickerPhase = 0.0;
  int _lastSparkSpawnMs = 0;
  Timer? _cameraAnimationTimer;
  Timer? _weldPhysicsTimer;

  // Draggable Standard Views Toolbar & Joint Toolbar State
  Offset _viewsToolbarOffset = const Offset(60, 54);
  Offset _jointToolbarOffset = const Offset(60, 98);

  void _resetToolbarPositions() {
    setState(() {
      _viewsToolbarOffset = const Offset(60, 54);
      _jointToolbarOffset = const Offset(60, 98);
    });
  }

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
  bool _isVcbUserTyping = false;
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
    _vcbFocusNode.addListener(() {
      if (_vcbFocusNode.hasFocus) {
        _isVcbUserTyping = true;
        _vcbController.selection = TextSelection(baseOffset: 0, extentOffset: _vcbController.text.length);
      }
    });
    widget.viewModel.addListener(_onViewModelChanged);
    _setupSceneGraph();
  }

  @override
  void dispose() {
    _subtleWarningTimer?.cancel();
    _cameraAnimationTimer?.cancel();
    _weldPhysicsTimer?.cancel();
    _weldStopwatch.stop();
    _snapAnimator.dispose();
    _cursorScreenPosNotifier.dispose();
    _cameraRepaintNotifier.dispose();
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

        // High-Performance CAD graphics profile and lighting (Item 6, SS3)
        _applyEnvironmentSettings();

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

  void _applyEnvironmentSettings() {
    if (_scene == null || !_isGpuAvailable) return;
    final prefs = widget.viewModel.graphicsPreferences;
    final aoRatio = (prefs.ambientOcclusion / 100.0).clamp(0.0, 1.0);

    // Authentic Onshape CAD look: ACES tone mapping, high contrast, clean saturation, ground-truth AO
    _scene!.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.aces,
      exposure: 1.15,
      bloomEnabled: true,
      bloomThreshold: 1.15,
      bloomIntensity: 0.12,
      bloomScatter: 0.6,
      ambientOcclusionEnabled: true,
      ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
      ambientOcclusionBentNormals: true,
      ambientOcclusionSpecularMode: SpecularAmbientOcclusionMode.bentCone,
      ambientOcclusionIntensity: aoRatio > 0.05 ? aoRatio : 0.85,
      ambientOcclusionHalfResolution: true,
      screenSpaceReflectionsEnabled: true,
      screenSpaceReflectionsIntensity: 0.7,
      colorGradingEnabled: true,
      contrast: 1.10,
      saturation: 1.16,
      brightness: 1.02,
      vignetteEnabled: true,
      vignetteIntensity: 0.12,
    );

    final azRad = prefs.lightAzimuthDeg * vm_math.degrees2Radians;
    final elRad = prefs.lightElevationDeg * vm_math.degrees2Radians;
    final lx = -math.cos(elRad) * math.sin(azRad);
    final ly = -math.cos(elRad) * math.cos(azRad);
    final lz = -math.sin(elRad);

    _scene!.directionalLight = DirectionalLight(
      direction: vm_math.Vector3(lx, ly, lz).normalized(),
      intensity: (prefs.keyLightIntensity).clamp(0.5, 4.0),
      castsShadow: false,
    );

    if (!widget.viewModel.isOrthoProjection) {
      _cameraComponent.projection = PerspectiveProjection(
        fovRadiansY: (prefs.fieldOfView * vm_math.degrees2Radians).clamp(15.0 * vm_math.degrees2Radians, 90.0 * vm_math.degrees2Radians),
        near: 0.5,
        far: 50000.0,
      );
    }
  }

  void _rebuildGpuCadModel({bool force = false}) {
    if (_scene == null || !_isGpuAvailable || !_isSceneReady) return;
    final mesh = widget.viewModel.assemblyMesh;
    if (mesh.polygons.isEmpty) return;

    final selectedPartId = widget.viewModel.selectedPart?.id;
    final targetSelectedFaceId = widget.viewModel.doc.selectedFaceId ?? selectedPartId;
    final targetSelectedWeldId = widget.viewModel.selectedWeldId;
    final targetRenderMode = widget.viewModel.onshapeRenderMode;
    final targetPreset = widget.viewModel.graphicsPreferences.materialSettings.preset;
    final targetWireframe = widget.viewModel.showWireframe;
    final currentPrefs = widget.viewModel.graphicsPreferences;

    final docVersion = widget.viewModel.documentVersion;

    if (!force &&
        _cadModelNode != null &&
        docVersion == _lastDocVersion &&
        mesh.polygons.length == _lastMeshPolyCount &&
        targetSelectedFaceId == _lastSelectedFaceId &&
        targetSelectedWeldId == _lastSelectedWeldId &&
        targetRenderMode == _lastRenderMode &&
        targetPreset == _lastPreset &&
        targetWireframe == _lastShowWireframe &&
        currentPrefs == _lastGraphicsPreferences) {
      return;
    }

    _lastDocVersion = docVersion;
    _lastMeshPolyCount = mesh.polygons.length;
    _lastSelectedFaceId = targetSelectedFaceId;
    _lastSelectedWeldId = targetSelectedWeldId;
    _lastRenderMode = targetRenderMode;
    _lastPreset = targetPreset;
    _lastShowWireframe = targetWireframe;
    _lastGraphicsPreferences = currentPrefs;

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
    final orbitDist = isOrtho ? math.max(fitDim * 12.0, 15000.0) : math.max((fitDim * 2.5) / _zoom, 2.0);

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

    // Camera-relative CAD 3-light key direction from top-left: creates natural contrast across top, flange, and end faces
    if (_scene != null) {
      final lightDir = (right * (-0.55) + up * 0.65 + d * 0.45).normalized();
      _scene!.directionalLight = DirectionalLight(direction: lightDir, intensity: 3.2, castsShadow: false);
    }
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
      if (widget.viewModel.cameraPivotOverride != null) {
        _cameraPivot = widget.viewModel.cameraPivotOverride!;
      }
    });
    if (!_isVcbUserTyping && !_vcbFocusNode.hasFocus && widget.viewModel.vcbValue.isNotEmpty && _vcbController.text != widget.viewModel.vcbValue) {
      _vcbController.text = widget.viewModel.vcbValue;
    }
    _rebuildGpuCadModel();
    _updateGpuCamera();
  }

  void _orbitCamera(double dAz, double dEl) {
    _azimuthDeg = (_azimuthDeg + dAz) % 360.0;
    _elevationDeg = (_elevationDeg + dEl).clamp(-89.0, 89.0);
    widget.viewModel.azimuthDeg = _azimuthDeg;
    widget.viewModel.elevationDeg = _elevationDeg;
    _cameraRepaintNotifier.value++;
    _updateGpuCamera();
  }

  void _panCamera(Offset delta) {
    _pan += delta;
    widget.viewModel.pan = _pan;
    _cameraRepaintNotifier.value++;
    _updateGpuCamera();
  }

  void _zoomCamera(double factor) {
    _zoom = (_zoom * factor).clamp(0.02, 120.0);
    widget.viewModel.zoom = _zoom;
    _cameraRepaintNotifier.value++;
    _updateGpuCamera();
  }

  void _zoomToFit() {
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
    _cameraRepaintNotifier.value++;
    setState(() {});
    _updateGpuCamera();
  }

  void _setCameraFromAngles(double az, double el) {
    _azimuthDeg = az % 360.0;
    _elevationDeg = el.clamp(-89.0, 89.0);
    widget.viewModel.azimuthDeg = _azimuthDeg;
    widget.viewModel.elevationDeg = _elevationDeg;
    _cameraRepaintNotifier.value++;
    _updateGpuCamera();
  }

  void _smoothAnimateCameraTo(CadPoint3D targetPos, {double targetZoom = 4.5}) {
    _cameraAnimationTimer?.cancel();

    final mesh = widget.viewModel.assemblyMesh;
    _initCameraTargetIfNeeded(mesh);
    final pivot = _cameraPivot;
    final fitDim = _cameraFitDim > 0 ? _cameraFitDim : 200.0;
    final size = MediaQuery.sizeOf(context);
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final startPan = _pan;
    final startZoom = _zoom;
    final startAz = _azimuthDeg;
    final startEl = _elevationDeg;

    final rx = targetPos.x - pivot.x;
    final ry = targetPos.y - pivot.y;
    final rz = targetPos.z - pivot.z;

    const endAz = 45.0;
    const endEl = 30.0;
    final m = _computeRotationMatrix(endAz, endEl);
    final x2 = rx * m[0] + ry * m[1] + rz * m[2];
    final y2 = rx * m[4] + ry * m[5] + rz * m[6];
    final z2 = rx * m[8] + ry * m[9] + rz * m[10];

    final cameraDist = math.max(fitDim * 2.5, 1000.0);
    final isOrtho = widget.viewModel.isOrthoProjection;
    final persp = isOrtho ? 1.0 : (cameraDist / math.max(cameraDist - z2, cameraDist * 0.15));

    final endScale = baseScale * targetZoom;
    final endPan = Offset(-(x2 * persp) * endScale, (y2 * persp) * endScale);
    final endZoom = targetZoom.clamp(0.02, 120.0);

    int tick = 0;
    const totalTicks = 35;
    _cameraAnimationTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      tick++;
      final t = (tick / totalTicks).clamp(0.0, 1.0);
      final factor = 1.0 - math.pow(1.0 - t, 3.0).toDouble();

      if (mounted) {
        setState(() {
          _pan = Offset.lerp(startPan, endPan, factor) ?? endPan;
          _zoom = startZoom + (endZoom - startZoom) * factor;
          _azimuthDeg = startAz + (endAz - startAz) * factor;
          _elevationDeg = startEl + (endEl - startEl) * factor;

          widget.viewModel.pan = _pan;
          widget.viewModel.zoom = _zoom;
          widget.viewModel.azimuthDeg = _azimuthDeg;
          widget.viewModel.elevationDeg = _elevationDeg;
        });
        _updateGpuCamera();
      }

      if (tick >= totalTicks) {
        timer.cancel();
        _cameraAnimationTimer = null;
      }
    });
  }

  void _resetCamera() {
    _cameraAnimationTimer?.cancel();
    _zoomToFit();
    widget.viewModel.clearWeldEvaluation();
  }

  AssemblySnapPoint? _findNearestSnapPointForPart(AssemblyPart part, Offset cursorScreen, Size size, FoldedMeshResult mesh) {
    if (!part.isVisible) return null;
    final allSnapPts = AssemblyDockingEngine.getAllSnapPointsForPart(part, cachedMesh: mesh);
    return AssemblyDockingEngine.findNearestSnapPoint(
      screenCursor: cursorScreen,
      candidates: allSnapPts,
      projectPoint: (pt) => _projectPoint(pt, size, mesh),
      maxPixelDistance: widget.viewModel.magneticSnapDistancePx,
    );
  }

  AssemblySnapPoint? _findNearestSnapPointAcrossParts(Iterable<AssemblyPart> parts, Offset cursorScreen, Size size, FoldedMeshResult mesh) {
    final candidatePoints = <AssemblySnapPoint>[];
    for (final p in parts) {
      if (!p.isVisible) continue;
      candidatePoints.addAll(AssemblyDockingEngine.getAllSnapPointsForPart(p, cachedMesh: mesh));
    }
    return AssemblyDockingEngine.findNearestSnapPoint(
      screenCursor: cursorScreen,
      candidates: candidatePoints,
      projectPoint: (pt) => _projectPoint(pt, size, mesh),
      maxPixelDistance: widget.viewModel.magneticSnapDistancePx,
    );
  }

  MouseCursor _getCursorForToolMode(AssemblyStudioViewModel vm) {
    if (vm.isSketchMode) return SystemMouseCursors.precise;
    if (_isOrbitingWithMouse || vm.activeToolMode == SketchUpToolMode.orbit) return SystemMouseCursors.allScroll;
    if (_isPanningWithMouse || vm.activeToolMode == SketchUpToolMode.pan || _isPanToolActive) return SystemMouseCursors.grab;
    if (vm.activeToolMode == SketchUpToolMode.select) return SystemMouseCursors.basic;
    if (vm.activeToolMode == SketchUpToolMode.move) {
      if (_isMovingEntity || _draggingPart != null) return SystemMouseCursors.grabbing;
      if (_hoveredSnapPointModel != null) return SystemMouseCursors.precise;
      return SystemMouseCursors.basic;
    }
    if (vm.activeToolMode == SketchUpToolMode.rotate) return SystemMouseCursors.basic;
    if (_snapDragSourceSnap != null) return SystemMouseCursors.grabbing;
    if (_hoveredSnapPoint != null) return SystemMouseCursors.basic;
    if (vm.pendingPlacement != null) return SystemMouseCursors.precise;
    if (_draggingPart != null) return SystemMouseCursors.grabbing;
    if (vm.activeToolMode == SketchUpToolMode.weld) return SystemMouseCursors.precise;
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

        return ClipRect(
          child: Focus(
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
                  if (vm.isSketchMode) {
                    vm.applySketchConstraint(CadConstraintType.horizontal);
                    return KeyEventResult.handled;
                  }
                  // SketchUp Camera Pan Tool (Key: H)
                  vm.setToolMode(SketchUpToolMode.pan);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.keyS && !isCtrl) {
                  // Onshape Shortcut: Shift+S or S -> Focus plane/surface, normal view alignment, activate sketch
                  if (!vm.isSketchMode) {
                    if (vm.isPlaneSelectionMode) {
                      vm.exitPlaneSelectionMode();
                    } else if (vm.doc.selectedFaceId != null) {
                      vm.focusPartAndEnterSketch(vm.selectedPart?.id, faceId: vm.doc.selectedFaceId);
                    } else {
                      vm.enterPlaneSelectionMode();
                    }
                  } else {
                    vm.alignCameraToActivePlaneNormal();
                  }
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.keyN && !isCtrl) {
                  // Onshape Universal Shortcut: N -> View Normal To Sketch Plane / Face
                  vm.alignCameraToActivePlaneNormal();
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.keyP && !isCtrl) {
                  // Onshape Shortcut: P -> Toggle Datum Planes Visibility (or with Shift in sketch mode: Project)
                  if (vm.isSketchMode && isShift) {
                    vm.toggleProjectGeometryMode();
                  } else {
                    vm.toggleDatumPlanesVisibility();
                  }
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.keyU && !isCtrl) {
                  // Onshape Sketch Shortcut: U -> Use / Project 3D Geometry
                  if (vm.isSketchMode) {
                    vm.toggleProjectGeometryMode();
                    return KeyEventResult.handled;
                  }
                } else if ((event.logicalKey == LogicalKeyboardKey.keyQ || event.logicalKey == LogicalKeyboardKey.keyX) && !isCtrl) {
                  // Onshape Sketch Shortcut: Q / X -> Toggle Construction Geometry Mode
                  if (vm.isSketchMode) {
                    vm.toggleSketchConstructionMode();
                    return KeyEventResult.handled;
                  }
                  // Rotate fallback
                  vm.setToolMode(SketchUpToolMode.rotate);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.keyE && !isCtrl) {
                  // Onshape Modeling Shortcut: Shift+E or E -> Extrude Feature Dialog
                  // In Sketch Mode without Shift: Equal Constraint (E)
                  if (isShift || !vm.isSketchMode) {
                    if (vm.isSketchMode || vm.activeSketchPlane != null || vm.doc.selectedFaceId != null) {
                      vm.toggleExtrudeMode();
                      return KeyEventResult.handled;
                    }
                  } else if (vm.isSketchMode) {
                    vm.applySketchConstraint(CadConstraintType.equal);
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.keyC && !isCtrl) {
                  // Onshape Sketch Shortcut: C -> Circle Tool
                  if (vm.isSketchMode) {
                    vm.activeSketchTool = 'circle';
                    vm.clearSketchInteractiveState();
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.keyL && !isCtrl) {
                  // Onshape Sketch Shortcut: L -> Line Tool
                  if (vm.isSketchMode) {
                    vm.activeSketchTool = 'line';
                    vm.clearSketchInteractiveState();
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.keyA && !isCtrl) {
                  // Onshape Sketch Shortcut: A -> 3-Point Arc Tool
                  if (vm.isSketchMode) {
                    vm.activeSketchTool = 'arc_3point';
                    vm.clearSketchInteractiveState();
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.keyG && !isCtrl) {
                  // Onshape Sketch Shortcut: G -> Corner Rectangle Tool
                  if (vm.isSketchMode) {
                    vm.activeSketchTool = 'rectangle';
                    vm.clearSketchInteractiveState();
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.keyD && !isCtrl) {
                  // Onshape Sketch Shortcut: D -> Dimension Tool
                  if (vm.isSketchMode) {
                    vm.activeSketchTool = 'dimension';
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.keyI && !isCtrl) {
                  // Onshape Constraint: I -> Coincident Constraint
                  if (vm.isSketchMode) {
                    vm.applySketchConstraint(CadConstraintType.coincident);
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.keyT && !isCtrl) {
                  // Onshape Constraint: T -> Tangent Constraint
                  if (vm.isSketchMode) {
                    vm.applySketchConstraint(CadConstraintType.tangent);
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
                  // SketchUp Move Tool
                  vm.setToolMode(SketchUpToolMode.move);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
                  if (vm.isSketchMode) {
                    // Onshape Sketch Shortcut: R -> Center Rectangle Tool
                    vm.activeSketchTool = 'center_rect';
                    vm.clearSketchInteractiveState();
                    return KeyEventResult.handled;
                  }
                  // SketchUp Rotate Tool
                  vm.setToolMode(SketchUpToolMode.rotate);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.keyB) {
                  if (vm.isSketchMode) {
                    // Onshape Constraint: B -> Parallel Constraint
                    vm.applySketchConstraint(CadConstraintType.parallel);
                    return KeyEventResult.handled;
                  }
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
                  if (vm.isExtrudeMode) {
                    vm.executeExtrudeFeature();
                    return KeyEventResult.handled;
                  }
                  if (_vcbController.text.isNotEmpty || vm.vcbValue.isNotEmpty) {
                    final input = _vcbController.text.isNotEmpty ? _vcbController.text : vm.vcbValue;
                    _isVcbUserTyping = false;
                    if (_isMovingEntity) {
                      _applyVcbTextToMovingEntity(input, vm);
                      _commitEntityMove(vm);
                      _vcbController.clear();
                      _viewportFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (vm.activeToolMode == SketchUpToolMode.rotate && (_rotatePhase == RotateToolPhase.rotatingAngle || _draggedParts.isNotEmpty)) {
                      _applyVcbTextToRotatingEntity(input, vm);
                      _commitRotation(vm);
                      _vcbController.clear();
                      _viewportFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }
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
                  _isVcbUserTyping = false;
                  bool cancelledActiveAction = false;
                  if (vm.isExtrudeMode) {
                    vm.closeExtrudeDialog();
                    cancelledActiveAction = true;
                  }
                  if (vm.sketchInteractiveStartPoint != null || vm.sketchPolylinePoints.isNotEmpty) {
                    vm.clearSketchInteractiveState();
                    cancelledActiveAction = true;
                  }
                  if (vm.isProjectGeometryMode) {
                    vm.exitProjectGeometryMode();
                    cancelledActiveAction = true;
                  }
                  if (vm.isPlaneSelectionMode) {
                    vm.exitPlaneSelectionMode();
                    cancelledActiveAction = true;
                  }
                  if (vm.latestWeldEvaluation != null) {
                    vm.clearWeldEvaluation();
                    cancelledActiveAction = true;
                  }
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
                  if (vm.isExtrudeMode) {
                    vm.closeExtrudeDialog();
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
                    if (!_isVcbUserTyping) {
                      _isVcbUserTyping = true;
                      _vcbController.text = char;
                    } else {
                      _vcbController.text += char;
                    }
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

                        // Snap point hover & magnetic attraction for selection/move/rotate tools (Requirement 4)
                        final isSnapTool =
                            !vm.isSketchMode &&
                            (vm.activeToolMode == SketchUpToolMode.select ||
                                vm.activeToolMode == SketchUpToolMode.move ||
                                vm.activeToolMode == SketchUpToolMode.rotate);
                        if (isSnapTool && !_isOrbitingWithMouse && !_isPanningWithMouse && !_isMovingEntity) {
                          _handleMagneticSnapHover(event.localPosition, size, mesh, vm);
                        }

                        if (vm.isPlaneSelectionMode && !_isOrbitingWithMouse && !_isPanningWithMouse) {
                          final hitPlane = _findPlaneUnderScreenCursor(event.localPosition, size, mesh, vm);
                          if (hitPlane != null) {
                            vm.setHoveredPlane(hitPlane.id);
                          } else {
                            final hitPoly = _findFrontmostPolygonUnderCursor(event.localPosition, size, mesh);
                            if (hitPoly != null) {
                              final hitPart = vm.findPartForFaceId(hitPoly.faceId);
                              if (hitPart != null) {
                                vm.setHoveredPlane('face:${hitPart.id}:${hitPoly.faceId}');
                              } else {
                                vm.setHoveredPlane(null);
                              }
                            } else {
                              vm.setHoveredPlane(null);
                            }
                          }
                        }

                        if (vm.isSketchMode && vm.activeSketchPlane != null && !_isOrbitingWithMouse && !_isPanningWithMouse) {
                          if (vm.isProjectGeometryMode) {
                            _updateProjectGeometryHover(event.localPosition, size, mesh, vm);
                          } else {
                            _updateSketchHover(event.localPosition, size, mesh, vm);
                          }
                        }

                        if (vm.activeToolMode == SketchUpToolMode.rotate) {
                          _handleRotatePointerHover(event.localPosition, size, mesh, vm);
                        } else if (vm.activeToolMode == SketchUpToolMode.magnetic) {
                          _handleMagneticPointerHover(event.localPosition, size, mesh, vm);
                        } else if (vm.activeToolMode == SketchUpToolMode.move) {
                          if (_isMovingEntity && _draggingPart != null) {
                            _handleMovePointerMove(event.localPosition, size, mesh, vm);
                          } else {
                            _handleMovePreGrabHover(event.localPosition, size, mesh, vm);
                          }
                        }
                      },
                      onPointerDown: (event) {
                        _viewportFocusNode.requestFocus();
                        final selectedPart = vm.selectedPart;

                        // 1a. Immediate Middle Mouse Button Pan / Orbit Activation (Requirement 1 & 2)
                        final isMiddle = (event.buttons & kTertiaryButton) != 0 || (event.buttons & kMiddleMouseButton) != 0;
                        if (isMiddle) {
                          bool isShift = false;
                          try {
                            isShift = HardwareKeyboard.instance.isShiftPressed;
                          } catch (_) {}
                          if (isShift) {
                            _isOrbitingWithMouse = true;
                          } else {
                            _isPanningWithMouse = true;
                          }
                          setState(() {});
                          return;
                        }

                        // 1b. Draft-Line Welding Tool Start
                        if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.weld && (event.buttons & kPrimaryMouseButton) != 0) {
                          _weldDraftStartScreen = event.localPosition;
                          _weldDraftPath.clear();
                          _weldDraftPath.add(event.localPosition);
                          _weld3DPoints.clear();
                          _weldTimestamps.clear();
                          _weldStopwatch.reset();
                          _weldStopwatch.start();
                          _weldTimestamps.add(0.0);
                          _weldHitPartIds.clear();
                          _weldSparks.clear();
                          _weldFlickerPhase = 0.0;
                          _isDrawingWeld = true;
                          _startWeldPhysicsLoop();
                          final (rayOrigin, rayDir) = _getRayFromScreen(event.localPosition, size, mesh);
                          final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
                          if (hit != null) {
                            _weld3DPoints.add(hit.hitPoint);
                            final p = vm.findPartForFaceId(hit.polygon.faceId);
                            if (p != null) _weldHitPartIds.add(p.id);
                          }
                          _spawnWeldSparks(event.localPosition);
                          setState(() {});
                          return;
                        }

                        // 1b-2. Direct Plane Selection Mode (Click datum plane, construction plane, or solid face)
                        if (vm.isPlaneSelectionMode && (event.buttons & kPrimaryMouseButton) != 0) {
                          final hitPlane = _findPlaneUnderScreenCursor(event.localPosition, size, mesh, vm);
                          if (hitPlane != null) {
                            vm.selectPlaneForSketch(hitPlane);
                            setState(() {});
                            return;
                          }
                          final hitPoly = _findFrontmostPolygonUnderCursor(event.localPosition, size, mesh);
                          if (hitPoly != null) {
                            final hitPart = vm.findPartForFaceId(hitPoly.faceId);
                            if (hitPart != null) {
                              vm.activateSketchOnFacePolygon(hitPoly, partId: hitPart.id);
                              vm.exitPlaneSelectionMode();
                              setState(() {});
                              return;
                            }
                          }
                        }

                        // 1b-3. Extrude 3D Arrow Manipulator Drag Start (Phase 5)
                        if (vm.isExtrudeMode && vm.activeSketchPlane != null && (event.buttons & kPrimaryMouseButton) != 0) {
                          final plane = vm.activeSketchPlane!;
                          final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(plane);
                          final val = CADProfileValidator.validateProfile(segments);
                          if (val.isValidClosedLoop && val.orderedPathVertices.length >= 3) {
                            final pts = val.orderedPathVertices;
                            final cx = pts.map((p) => p.dx).reduce((a, b) => a + b) / pts.length;
                            final cy = pts.map((p) => p.dy).reduce((a, b) => a + b) / pts.length;
                            final base3d = CadPoint3D(
                              plane.origin.x + plane.xAxis.normalized().x * cx + plane.yAxis.normalized().x * cy,
                              plane.origin.y + plane.xAxis.normalized().y * cx + plane.yAxis.normalized().y * cy,
                              plane.origin.z + plane.xAxis.normalized().z * cx + plane.yAxis.normalized().z * cy,
                            );
                            final dist = vm.extrudeParams.distanceMm;
                            final tip3d = CadPoint3D(
                              base3d.x + plane.normal.normalized().x * dist,
                              base3d.y + plane.normal.normalized().y * dist,
                              base3d.z + plane.normal.normalized().z * dist,
                            );
                            final scrTip = _projectPoint(tip3d, size, mesh);
                            if ((event.localPosition - scrTip).distance < 28.0) {
                              vm.isExtrudeArrowDragging = true;
                              vm.extrudeDragStartScreen = event.localPosition;
                              vm.extrudeDragStartDistance = dist;
                              setState(() {});
                              return;
                            }
                          }
                        }

                        // 1c. Direct Sketch Entity Interaction & Parametric Drawing
                        if (vm.isSketchMode && (event.buttons & kPrimaryMouseButton) != 0) {
                          if (vm.isProjectGeometryMode) {
                            _handleProjectGeometryClick(event.localPosition, size, mesh, vm);
                            return;
                          }

                          final plane = vm.activeSketchPlane;
                          if (plane != null) {
                            final localPoint = _unprojectScreenToPlane(event.localPosition, plane, size, mesh);
                            if (localPoint != null) {
                              final snapped = vm.activePlaneHoverLocal ?? localPoint;
                              final tool = vm.activeSketchTool;

                              if (tool == 'rectangle' || tool == 'rect') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '📐 Dimensions (W x H)', value: '0.0 x 0.0 mm', hint: 'Click 2nd corner, or type dimensions');
                                  setState(() {});
                                  return;
                                } else {
                                  final pStart = vm.sketchInteractiveStartPoint!;
                                  final w = (snapped.dx - pStart.dx).abs();
                                  final h = (snapped.dy - pStart.dy).abs();
                                  if (w > 0.1 && h > 0.1) {
                                    final topLeft = Offset(math.min(pStart.dx, snapped.dx), math.min(pStart.dy, snapped.dy));
                                    final newRect = CADRectangleEntity(
                                      id: 'rect_${DateTime.now().millisecondsSinceEpoch}',
                                      startPoint: topLeft,
                                      width: w,
                                      height: h,
                                      isPassThrough: true,
                                      depthMm: 5.0,
                                      isConstruction: vm.isSketchConstructionMode,
                                    );
                                    vm.addPrimitiveEntityToActivePlane(newRect);
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              } else if (tool == 'center_rect') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '📐 Center Rect (W x H)', value: '0.0 x 0.0 mm', hint: 'Click corner, or type dimensions');
                                  setState(() {});
                                  return;
                                } else {
                                  final pCenter = vm.sketchInteractiveStartPoint!;
                                  final w = 2.0 * (snapped.dx - pCenter.dx).abs();
                                  final h = 2.0 * (snapped.dy - pCenter.dy).abs();
                                  if (w > 0.1 && h > 0.1) {
                                    final newCenterRect = CADCenterRectangleEntity(
                                      id: 'center_rect_${DateTime.now().millisecondsSinceEpoch}',
                                      center: pCenter,
                                      width: w,
                                      height: h,
                                      isPassThrough: true,
                                      depthMm: 5.0,
                                      isConstruction: vm.isSketchConstructionMode,
                                    );
                                    vm.addPrimitiveEntityToActivePlane(newCenterRect);
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              } else if (tool == 'circle' || tool == 'hole') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '⭕ Diameter (Ø)', value: 'Ø 0.0 mm', hint: 'Click edge to set radius, or type diameter');
                                  setState(() {});
                                  return;
                                } else {
                                  final pCenter = vm.sketchInteractiveStartPoint!;
                                  final radius = (snapped - pCenter).distance;
                                  if (radius > 0.1) {
                                    final newCircle = CADCircleEntity(
                                      id: 'circle_${DateTime.now().millisecondsSinceEpoch}',
                                      center: pCenter,
                                      radius: radius,
                                      isPassThrough: true,
                                      depthMm: 5.0,
                                      isConstruction: vm.isSketchConstructionMode,
                                    );
                                    vm.addPrimitiveEntityToActivePlane(newCircle);
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              } else if (tool == 'arc_3point') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '⌒ 3-Pt Arc', value: 'Chord: 0.0 mm', hint: 'Click to place End Point of Arc');
                                  setState(() {});
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  if ((snapped - vm.sketchInteractiveStartPoint!).distance > 0.1) {
                                    vm.setInteractiveSketchMid(snapped);
                                    vm.setVcbState(label: '⌒ 3-Pt Arc Radius', value: 'Defining curvature...', hint: 'Click to place Apex/Curvature Point');
                                    setState(() {});
                                    return;
                                  }
                                } else {
                                  final pStart = vm.sketchInteractiveStartPoint!;
                                  final pEnd = vm.sketchInteractiveMidPoint!;
                                  final newArc = CADArcEntity(
                                    id: 'arc_${DateTime.now().millisecondsSinceEpoch}',
                                    startPoint: pStart,
                                    endPoint: pEnd,
                                    pointOnArc: snapped,
                                    isConstruction: vm.isSketchConstructionMode,
                                  );
                                  vm.addPrimitiveEntityToActivePlane(newArc);
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  _rebuildGpuCadModel();
                                  return;
                                }
                              } else if (tool == 'line') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '📏 Line Length', value: '0.0 mm', hint: 'Click next point, or Escape to end chaining');
                                  setState(() {});
                                  return;
                                } else {
                                  final pStart = vm.sketchInteractiveStartPoint!;
                                  if ((snapped - pStart).distance > 0.1) {
                                    final newLine = CADLineEntity(
                                      id: 'line_${DateTime.now().millisecondsSinceEpoch}',
                                      start: pStart,
                                      end: snapped,
                                      isConstruction: vm.isSketchConstructionMode,
                                    );
                                    vm.addPrimitiveEntityToActivePlane(newLine);
                                    // Continuous chaining: next segment starts where current finished
                                    vm.setInteractiveSketchStart(snapped);
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              } else if (tool == 'polyline') {
                                if (vm.sketchPolylinePoints.isNotEmpty &&
                                    (snapped - vm.sketchPolylinePoints.first).distance < 6.0 &&
                                    vm.sketchPolylinePoints.length >= 2) {
                                  vm.addSketchPolylinePoint(vm.sketchPolylinePoints.first);
                                  final newPoly = CADPolylineEntity(
                                    id: 'polyline_${DateTime.now().millisecondsSinceEpoch}',
                                    points: List.from(vm.sketchPolylinePoints),
                                    isClosed: true,
                                    isConstruction: vm.isSketchConstructionMode,
                                  );
                                  vm.addPrimitiveEntityToActivePlane(newPoly);
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  _rebuildGpuCadModel();
                                  return;
                                } else {
                                  vm.addSketchPolylinePoint(snapped);
                                  setState(() {});
                                  return;
                                }
                              }
                              // --- MIDPOINT LINE (2 Clicks: Midpoint -> Endpoint) ---
                              else if (tool == 'midpoint_line') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '📏 Midpoint Line', value: '0.0 mm', hint: 'Click endpoint (extends symmetrically from midpoint)');
                                  setState(() {});
                                  return;
                                } else {
                                  final midPt = vm.sketchInteractiveStartPoint!;
                                  if ((snapped - midPt).distance > 0.1) {
                                    final midLine = CADMidpointLineEntity(
                                      id: 'midline_${DateTime.now().millisecondsSinceEpoch}',
                                      midpoint: midPt,
                                      endpoint: snapped,
                                      isConstruction: vm.isSketchConstructionMode,
                                    );
                                    vm.addPrimitiveEntityToActivePlane(midLine);
                                    vm.clearSketchInteractiveState();
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              }
                              // --- ALIGNED RECTANGLE (3 Clicks: Corner 1 -> Corner 2 -> Height) ---
                              else if (tool == 'aligned_rect') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '📐 Aligned Rect', value: 'Step 1/3', hint: 'Click 2nd corner to set primary edge & angle');
                                  setState(() {});
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  if ((snapped - vm.sketchInteractiveStartPoint!).distance > 0.1) {
                                    vm.setInteractiveSketchMid(snapped);
                                    vm.setVcbState(label: '📐 Aligned Rect Height', value: 'Step 2/3', hint: 'Click 3rd point to set perpendicular height');
                                    setState(() {});
                                    return;
                                  }
                                } else {
                                  final p1 = vm.sketchInteractiveStartPoint!;
                                  final p2 = vm.sketchInteractiveMidPoint!;
                                  final edge = p2 - p1;
                                  final len = edge.distance;
                                  final perp = len > 1e-4 ? Offset(-edge.dy / len, edge.dx / len) : const Offset(0, 1);
                                  final hSigned = (snapped.dx - p1.dx) * perp.dx + (snapped.dy - p1.dy) * perp.dy;
                                  if (hSigned.abs() > 0.1) {
                                    vm.addPrimitiveEntityToActivePlane(CADAlignedRectangleEntity(
                                      id: 'arect_${DateTime.now().millisecondsSinceEpoch}',
                                      corner1: p1,
                                      corner2: p2,
                                      height: hSigned,
                                      isConstruction: vm.isSketchConstructionMode,
                                    ));
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              }
                              // --- 3-POINT PERIMETER CIRCLE (3 Clicks on Perimeter) ---
                              else if (tool == 'circle_3point') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  vm.setInteractiveSketchMid(snapped);
                                  return;
                                } else {
                                  vm.addPrimitiveEntityToActivePlane(CADThreePointCircleEntity(
                                    id: 'c3pt_${DateTime.now().millisecondsSinceEpoch}',
                                    p1: vm.sketchInteractiveStartPoint!,
                                    p2: vm.sketchInteractiveMidPoint!,
                                    p3: snapped,
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  _rebuildGpuCadModel();
                                  return;
                                }
                              }
                              // --- ELLIPSE (3 Clicks: Center -> Major Axis Tip -> Minor Axis Radius) ---
                              else if (tool == 'ellipse' || tool == 'arc_ellipse') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  vm.setInteractiveSketchMid(snapped);
                                  return;
                                } else {
                                  final center = vm.sketchInteractiveStartPoint!;
                                  final majorTip = vm.sketchInteractiveMidPoint!;
                                  final majorVec = majorTip - center;
                                  final rx = majorVec.distance.clamp(1.0, 10000.0);
                                  final rot = math.atan2(majorVec.dy, majorVec.dx);
                                  final ry = (snapped - center).distance.clamp(1.0, 10000.0);
                                  vm.addPrimitiveEntityToActivePlane(CADEllipseEntity(
                                    id: 'ellipse_${DateTime.now().millisecondsSinceEpoch}',
                                    center: center,
                                    radiusX: rx,
                                    radiusY: ry,
                                    rotationRad: rot,
                                    sweepAngleRad: tool == 'arc_ellipse' ? math.pi : 2.0 * math.pi,
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  _rebuildGpuCadModel();
                                  return;
                                }
                              }
                              // --- TANGENT ARC & CENTER POINT ARC & CONIC ---
                              else if (tool == 'arc_tangent') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else {
                                  final p0 = vm.sketchInteractiveStartPoint!;
                                  vm.addPrimitiveEntityToActivePlane(CADTangentArcEntity(
                                    id: 'tarc_${DateTime.now().millisecondsSinceEpoch}',
                                    startPoint: p0,
                                    endPoint: snapped,
                                    startTangentDir: const Offset(1.0, 0.0),
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  return;
                                }
                              } else if (tool == 'arc_center') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  vm.setInteractiveSketchMid(snapped);
                                  return;
                                } else {
                                  final c = vm.sketchInteractiveStartPoint!;
                                  final pStart = vm.sketchInteractiveMidPoint!;
                                  final r = (pStart - c).distance.clamp(1.0, 10000.0);
                                  final a0 = math.atan2(pStart.dy - c.dy, pStart.dx - c.dx);
                                  final a1 = math.atan2(snapped.dy - c.dy, snapped.dx - c.dx);
                                  double sweep = a1 - a0;
                                  while (sweep <= 0) {
                                    sweep += 2.0 * math.pi;
                                  }
                                  vm.addPrimitiveEntityToActivePlane(CADCenterPointArcEntity(
                                    id: 'cparc_${DateTime.now().millisecondsSinceEpoch}',
                                    center: c,
                                    radius: r,
                                    startAngleRad: a0,
                                    sweepAngleRad: sweep,
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  return;
                                }
                              } else if (tool == 'conic') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  vm.setInteractiveSketchMid(snapped);
                                  return;
                                } else {
                                  vm.addPrimitiveEntityToActivePlane(CADConicEntity(
                                    id: 'conic_${DateTime.now().millisecondsSinceEpoch}',
                                    startPoint: vm.sketchInteractiveStartPoint!,
                                    endPoint: vm.sketchInteractiveMidPoint!,
                                    apexControlPoint: snapped,
                                    rho: 0.5,
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  return;
                                }
                              }
                              // --- INSCRIBED & CIRCUMSCRIBED POLYGONS (Center -> Radius) ---
                              else if (tool == 'polygon_inscribed' || tool == 'polygon_circumscribed') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '⬡ Polygon (6 Sides)', value: 'R: 0.0 mm', hint: 'Click radius point, or type side count (3..50)');
                                  setState(() {});
                                  return;
                                } else {
                                  final center = vm.sketchInteractiveStartPoint!;
                                  final r = (snapped - center).distance;
                                  if (r > 0.5) {
                                    final rot = math.atan2(snapped.dy - center.dy, snapped.dx - center.dx);
                                    vm.addPrimitiveEntityToActivePlane(CADRegularPolygonEntity(
                                      id: 'poly_${DateTime.now().millisecondsSinceEpoch}',
                                      center: center,
                                      radius: r,
                                      sides: 6,
                                      rotationRad: rot,
                                      isInscribed: tool == 'polygon_inscribed',
                                      isConstruction: vm.isSketchConstructionMode,
                                    ));
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              }
                              // --- FIT SPLINE & BEZIER ---
                              else if (tool == 'spline' || tool == 'bezier') {
                                if (vm.sketchPolylinePoints.length >= 2 &&
                                    (snapped - vm.sketchPolylinePoints.last).distance < 3.0) {
                                  vm.addPrimitiveEntityToActivePlane(CADSplineEntity(
                                    id: 'spline_${DateTime.now().millisecondsSinceEpoch}',
                                    controlPoints: List.from(vm.sketchPolylinePoints),
                                    isBezier: tool == 'bezier',
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  return;
                                } else {
                                  vm.addSketchPolylinePoint(snapped);
                                  setState(() {});
                                  return;
                                }
                              }
                              // --- SKETCH OBROUND SLOT (Start Center -> End Center) ---
                              else if (tool == 'sketch_slot') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else {
                                  final p0 = vm.sketchInteractiveStartPoint!;
                                  if ((snapped - p0).distance > 1.0) {
                                    vm.addPrimitiveEntityToActivePlane(CADSlotEntity(
                                      id: 'slot_${DateTime.now().millisecondsSinceEpoch}',
                                      startCenter: p0,
                                      endCenter: snapped,
                                      diameter: 20.0,
                                      isConstruction: vm.isSketchConstructionMode,
                                    ));
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    return;
                                  }
                                }
                              }
                              // --- STANDALONE POINT & TEXT ---
                              else if (tool == 'point') {
                                vm.addPrimitiveEntityToActivePlane(CADPointEntity(
                                  id: 'pt_${DateTime.now().millisecondsSinceEpoch}',
                                  position: snapped,
                                ));
                                setState(() {});
                                return;
                              } else if (tool == 'text') {
                                vm.addPrimitiveEntityToActivePlane(CADTextEntity(
                                  id: 'txt_${DateTime.now().millisecondsSinceEpoch}',
                                  origin: snapped,
                                  text: 'TRUFOLD',
                                  heightMm: 16.0,
                                ));
                                vm.activeSketchTool = 'select_entity';
                                setState(() {});
                                return;
                              }
                              // --- SKETCH MODIFY: TRIM ('M'), EXTEND, SPLIT ---
                              else if (tool == 'trim') {
                                if (OnshapeSketchModifyEngine.trimAtPoint(plane, localPoint)) {
                                  vm.activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(plane);
                                  vm.notifyDocChanged();
                                  setState(() {});
                                }
                                return;
                              } else if (tool == 'extend') {
                                if (OnshapeSketchModifyEngine.extendAtPoint(plane, localPoint)) {
                                  vm.activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(plane);
                                  vm.notifyDocChanged();
                                  setState(() {});
                                }
                                return;
                              } else if (tool == 'split') {
                                if (OnshapeSketchModifyEngine.splitAtPoint(plane, localPoint)) {
                                  vm.activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(plane);
                                  vm.notifyDocChanged();
                                  setState(() {});
                                }
                                return;
                              } else {
                                // Selection mode: hit test primitive entities on active plane
                                CADPrimitiveEntity? hitPrimitive;
                                for (final p in plane.primitives.reversed) {
                                  if (p is CADRectangleEntity) {
                                    final r = Rect.fromLTWH(p.startPoint.dx, p.startPoint.dy, p.width, p.height);
                                    if (r.inflate(5.0).contains(localPoint)) {
                                      hitPrimitive = p;
                                      break;
                                    }
                                  } else if (p is CADCenterRectangleEntity) {
                                    final r = Rect.fromCenter(center: p.center, width: p.width, height: p.height);
                                    if (r.inflate(5.0).contains(localPoint)) {
                                      hitPrimitive = p;
                                      break;
                                    }
                                  } else if (p is CADCircleEntity) {
                                    if ((localPoint - p.center).distance <= p.radius + 5.0) {
                                      hitPrimitive = p;
                                      break;
                                    }
                                  } else if (p is CADArcEntity) {
                                    final geom = p.computeCircumcircle();
                                    if (geom != null) {
                                      final d = (localPoint - geom.center).distance;
                                      if ((d - geom.radius).abs() <= 6.0) {
                                        hitPrimitive = p;
                                        break;
                                      }
                                    } else {
                                      if (_distanceToSegment(localPoint, p.startPoint, p.endPoint) <= 5.0) {
                                        hitPrimitive = p;
                                        break;
                                      }
                                    }
                                  } else if (p is CADLineEntity) {
                                    if (_distanceToSegment(localPoint, p.start, p.end) <= 5.0) {
                                      hitPrimitive = p;
                                      break;
                                    }
                                  } else if (p is CADPolylineEntity) {
                                    for (int i = 0; i < p.points.length - 1; i++) {
                                      if (_distanceToSegment(localPoint, p.points[i], p.points[i + 1]) <= 5.0) {
                                        hitPrimitive = p;
                                        break;
                                      }
                                    }
                                    if (hitPrimitive != null) break;
                                  } else if (p is CADPointEntity) {
                                    if ((localPoint - p.position).distance <= 6.0) {
                                      hitPrimitive = p;
                                      break;
                                    }
                                  } else {
                                    for (final seg in p.toLineSegments()) {
                                      if (_distanceToSegment(localPoint, seg.start, seg.end) <= 6.0) {
                                        hitPrimitive = p;
                                        break;
                                      }
                                    }
                                    if (hitPrimitive != null) break;
                                  }
                                }

                                if (hitPrimitive != null) {
                                  if (HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isControlPressed) {
                                    vm.toggleSketchEntityMultiSelection(hitPrimitive.id);
                                  } else {
                                    vm.selectSketchPrimitive(hitPrimitive);
                                  }
                                  setState(() {});
                                  return;
                                } else {
                                  vm.selectSketchPrimitive(null);
                                }
                              }
                            }
                          }

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

                        // 2a. SketchUp 2-Click Move Tool - Commit Placement (Click 2)
                        if (!vm.isSketchMode &&
                            vm.activeToolMode == SketchUpToolMode.move &&
                            _isMovingEntity &&
                            _draggingPart != null &&
                            (event.buttons & kPrimaryMouseButton) != 0) {
                          _commitEntityMove(vm);
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

                        // 2b-2. SketchUp Move Tool - Click 1 (Base Grab) on active bounding box snap point
                        if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.move && !_isMovingEntity && (event.buttons & kPrimaryMouseButton) != 0) {
                          final snapToGrab =
                              _hoveredSnapPointModel ??
                              _findNearestSnapPointAcrossParts(
                                vm.selectedPart != null ? [vm.selectedPart!, ...vm.doc.parts.where((p) => p.id != vm.selectedPart!.id)] : vm.doc.parts,
                                event.localPosition,
                                size,
                                mesh,
                              );
                          if (snapToGrab != null) {
                            final part = vm.doc.parts.where((p) => p.id == snapToGrab.partId).firstOrNull;
                            if (part != null) {
                              if (vm.isPartBonded(part.id)) {
                                vm.setVcbState(label: '🔒 Welded Entity', value: 'Locked by Weld', hint: 'Break weld joint first to move.');
                                return;
                              }
                              if (!vm.doc.selectedPartIds.contains(part.id)) {
                                vm.selectPart(part.id);
                              }
                              _startEntityMove(part, snapToGrab.worldPosition, event.localPosition, vm);
                              return;
                            }
                          }
                        }

                        // 2c. Magnetic Snap Tool Point Click
                        if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.magnetic && (event.buttons & kPrimaryMouseButton) != 0) {
                          _handleMagneticPointerDown(event.localPosition, size, mesh, vm);
                          return;
                        }

                        // 3. Direct Whole-Part Group Selection, Weld Picking, Move, and In-Place Rotate
                        if (!vm.isSketchMode && (event.buttons & kPrimaryMouseButton) != 0 && vm.pendingPlacement == null) {
                          // Proximity picking for weld beads (Item 5)
                          final clickedWeld = _findNearestWeldUnderScreenCursor(event.localPosition, size, mesh, vm, maxScreenDist: 14.0);
                          if (clickedWeld != null) {
                            vm.selectWeld(clickedWeld.id);
                            _rebuildGpuCadModel(force: true);
                            setState(() {});
                            return;
                          }

                          final hitPoly = _findFrontmostPolygonUnderCursor(event.localPosition, size, mesh);
                          if (hitPoly != null) {
                            // Check if hit a weld bead directly
                            if (hitPoly.faceId.startsWith('weld_')) {
                              final weldId = hitPoly.faceId.substring('weld_'.length);
                              vm.selectWeld(weldId);
                              _rebuildGpuCadModel(force: true);
                              setState(() {});
                              return;
                            }

                            final hitPart = vm.findPartForFaceId(hitPoly.faceId);
                            if (hitPart != null) {
                              vm.doc.selectedFaceId = hitPoly.faceId;

                              // Direct 3D Face Sketch Mode Activation (Key: S or Sketch tool)
                              if (vm.activeToolMode == SketchUpToolMode.sketch) {
                                vm.activateSketchOnFacePolygon(hitPoly, partId: hitPart.id);
                                setState(() {});
                                return;
                              }

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
                                  vm.focusPartAndEnterSketch(hitPart.id, faceId: hitPoly.faceId);
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

                                if (!vm.doc.selectedPartIds.contains(hitPart.id)) {
                                  vm.selectPart(hitPart.id);
                                }

                                // Pickup from clicked snap point OR clicked surface point
                                final nearestSnap = _findNearestSnapPointForPart(hitPart, event.localPosition, size, mesh);
                                final surfaceHit = _findFrontmostRaycastHit(event.localPosition, size, mesh);
                                final baseAnchor = nearestSnap?.worldPosition ?? surfaceHit?.hitPoint ?? hitPart.position;
                                _startEntityMove(hitPart, baseAnchor, event.localPosition, vm, mesh: mesh);
                                return;
                              }
                            }
                          } else {
                            if (vm.activeToolMode == SketchUpToolMode.move) {
                              if (vm.selectedPart != null) {
                                final partToMove = vm.selectedPart!;
                                if (vm.isPartBonded(partToMove.id)) {
                                  vm.setVcbState(label: '🔒 Welded Entity', value: 'Locked by Weld', hint: 'Break weld joint first to move.');
                                  return;
                                }
                                final nearestSnap = _findNearestSnapPointForPart(partToMove, event.localPosition, size, mesh);
                                final surfaceHit = _findFrontmostRaycastHit(event.localPosition, size, mesh);
                                final baseAnchor = nearestSnap?.worldPosition ?? surfaceHit?.hitPoint ?? partToMove.position;
                                _startEntityMove(partToMove, baseAnchor, event.localPosition, vm, mesh: mesh);
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

                        // Extrude 3D Arrow Manipulator Dragging (Phase 5)
                        if (vm.isExtrudeMode && vm.isExtrudeArrowDragging && vm.extrudeDragStartScreen != null && vm.activeSketchPlane != null) {
                          final delta = event.localPosition - vm.extrudeDragStartScreen!;
                          final plane = vm.activeSketchPlane!;
                          final baseScr = _projectPoint(CadPoint3D(plane.origin.x, plane.origin.y, plane.origin.z), size, mesh);
                          final tipScr = _projectPoint(
                            CadPoint3D(
                              plane.origin.x + plane.normal.normalized().x * 50.0,
                              plane.origin.y + plane.normal.normalized().y * 50.0,
                              plane.origin.z + plane.normal.normalized().z * 50.0,
                            ),
                            size,
                            mesh,
                          );
                          final normScr = tipScr - baseScr;
                          final normLen = normScr.distance;
                          if (normLen > 1.0) {
                            final unit = normScr / normLen;
                            final projDist = (delta.dx * unit.dx + delta.dy * unit.dy);
                            final mmDelta = projDist * (50.0 / normLen);
                            final newDist = (vm.extrudeDragStartDistance + mmDelta);
                            vm.updateExtrudeDistance(double.parse(newDist.toStringAsFixed(1)));
                          }
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
                            (isMiddle && !isShiftPressed) ||
                            (isSecondary && (isShiftPressed || isCtrlPressed)) ||
                            (isPrimary && _isPanToolActive) ||
                            (isPrimary && isShiftPressed && _isPanToolActive);
                        final isOrbit =
                            (isMiddle && isShiftPressed) ||
                            (isSecondary && !isShiftPressed && !isCtrlPressed) ||
                            (isPrimary && vm.activeToolMode == SketchUpToolMode.orbit);

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
                              _orbitCamera(-event.delta.dx * 0.38, 0.0);
                            } else {
                              _orbitCamera(0.0, -event.delta.dy * 0.38);
                            }
                          } else {
                            _orbitCamera(-event.delta.dx * 0.38, -event.delta.dy * 0.38);
                          }
                          return;
                        }

                        if (vm.activeToolMode == SketchUpToolMode.weld && _isDrawingWeld && isPrimary) {
                          if (_weldDraftPath.isEmpty) {
                            _weldDraftPath.add(event.localPosition);
                          } else {
                            final lastPt = _weldDraftPath.last;
                            final dist = (event.localPosition - lastPt).distance;
                            if (dist >= 3.0) {
                              final smoothedPt = Offset.lerp(lastPt, event.localPosition, 0.65)!;
                              _weldDraftPath.add(smoothedPt);
                            }
                          }
                          final (rayOrigin, rayDir) = _getRayFromScreen(event.localPosition, size, mesh);
                          final hit = AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
                          if (hit != null) {
                            if (_weld3DPoints.isEmpty || _weld3DPoints.last.distanceTo(hit.hitPoint) > 2.0) {
                              _weld3DPoints.add(hit.hitPoint);
                              _weldTimestamps.add(_weldStopwatch.elapsedMilliseconds / 1000.0);
                            }
                            final p = vm.findPartForFaceId(hit.polygon.faceId);
                            if (p != null) _weldHitPartIds.add(p.id);
                          }
                          _weldFlickerPhase += 0.08;
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
                        if (vm.isExtrudeArrowDragging) {
                          vm.isExtrudeArrowDragging = false;
                          vm.extrudeDragStartScreen = null;
                          setState(() {});
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
                            if (!isShift && !isCtrl && !_isMovingEntity) {
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
                          _weld3DPoints.clear();
                          _weldHitPartIds.clear();
                          _weldSparks.clear();
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
                        setState(() {});
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
                        _isDrawingWeld = false;
                        _weldDraftPath.clear();
                        _weldDraftStartScreen = null;
                        _weld3DPoints.clear();
                        _weldHitPartIds.clear();
                        _weldSparks.clear();
                        setState(() {});
                      },
                      onPointerSignal: (pointerSignal) {
                        if (pointerSignal is PointerScrollEvent) {
                          final dy = pointerSignal.scrollDelta.dy;
                          final factor = math.exp(-dy * 0.0010).clamp(0.92, 1.08);
                          _zoomCamera(factor);
                        }
                      },
                      child: DragTarget<PendingPartPlacement>(
                        onWillAcceptWithDetails: (details) => true,
                        onAcceptWithDetails: (details) {
                          final renderBox = context.findRenderObject() as RenderBox?;
                          final localPos = _lastHoverScreenPos ?? (renderBox != null ? renderBox.globalToLocal(details.offset) : details.offset);
                          final worldPos = _screenToWorldGround(localPos, size, mesh);
                          vm.setPendingPlacement(details.data);
                          vm.placePendingPartAt(worldPos);
                          _rebuildGpuCadModel(force: true);
                          setState(() {});
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
                                  child: ListenableBuilder(
                                    listenable: _cameraRepaintNotifier,
                                    builder: (context, _) {
                                      final bool useGpu = (vm.renderEngine == Cad3dEngineMode.flutterGpu) &&
                                          _isGpuAvailable && _scene != null && _isSceneReady;
                                      return useGpu
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
                                                  pivotOverride: _cameraPivot,
                                                ),
                                              ),
                                            );
                                    },
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
                  // 1b-0b. 3D DATUM & CONSTRUCTION PLANES LAYER (Phase 1)
                  // =================================================================
                  if (vm.isPlaneSelectionMode || vm.isSketchMode || vm.showDatumPlanes || vm.showConstructionPlanes || vm.showOriginTriad)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: Assembly3DPlanePainter(viewModel: vm, projectPoint: (pt) => _projectPoint(pt, size, mesh)),
                        ),
                      ),
                    ),

                  // =================================================================
                  // 1b. SKETCHUP TRANSLUCENT BOUNDING BOX OVERLAY (Requirement 7 / SS3)
                  // =================================================================
                  if (!vm.isSketchMode && (vm.selectedPart != null || vm.selectedPartIds.isNotEmpty || _hoveredSnapPointModel != null))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _SelectedPartBoundingBoxPainter(
                            selectedParts: vm.doc.parts
                                .where((p) => p.isVisible && (p.id == vm.selectedPart?.id || vm.selectedPartIds.contains(p.id)))
                                .toList(),
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
                            zoom: _zoom,
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
                            customCenter3d: _moveBaseWorldPoint ?? vm.selectedPart!.position,
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

                  if (!vm.isSketchMode && vm.activeToolMode == SketchUpToolMode.select && !_isOrbitingWithMouse && !_isPanningWithMouse)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ValueListenableBuilder<Offset?>(
                          valueListenable: _cursorScreenPosNotifier,
                          builder: (context, cursorPos, _) {
                            final pos = cursorPos ?? _lastHoverScreenPos;
                            if (pos == null) return const SizedBox.shrink();
                            return CustomPaint(
                              size: Size.infinite,
                              painter: _CadSelectionPointerOverlayPainter(cursorScreenPos: pos, isSnapped: _hoveredSnapPointModel != null),
                            );
                          },
                        ),
                      ),
                    ),

                  // =================================================================
                  // 2a-2. 3D PARAMETRIC SURFACE SKETCH OVERLAY (GRIDS, INFERENCES, PRIMITIVES)
                  // =================================================================
                  if (vm.isSketchMode && vm.activeSketchPlane != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: Assembly3DSurfaceSketchPainter(viewModel: vm, projectPoint: (pt) => _projectPoint(pt, size, mesh)),
                        ),
                      ),
                    ),

                  // =================================================================
                  // 2a-3. 3D FEATURE EXTRUSION PREVIEW & ARROW MANIPULATOR (Phase 5)
                  // =================================================================
                  if (vm.isExtrudeMode && vm.activeSketchPlane != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: Assembly3DExtrudePainter(viewModel: vm, projectPoint: (pt) => _projectPoint(pt, size, mesh)),
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
                  // 2b-0. SELECTED WELD HIGHLIGHT OVERLAY (Item 2)
                  // =================================================================
                  if (vm.selectedWeldId != null)
                    Builder(
                      builder: (context) {
                        final selWeld = vm.doc.welds.where((w) => w.id == vm.selectedWeldId).firstOrNull;
                        if (selWeld == null) return const SizedBox.shrink();
                        CadPoint3D u = selWeld.weldAxis;
                        final uLen = math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z);
                        if (uLen > 1e-4) {
                          u = CadPoint3D(u.x / uLen, u.y / uLen, u.z / uLen);
                        } else {
                          u = const CadPoint3D(1.0, 0.0, 0.0);
                        }
                        final halfLen = selWeld.weldLengthMm / 2.0;
                        final p0 = CadPoint3D(selWeld.weldPoint.x - u.x * halfLen, selWeld.weldPoint.y - u.y * halfLen, selWeld.weldPoint.z - u.z * halfLen);
                        final p1 = CadPoint3D(selWeld.weldPoint.x + u.x * halfLen, selWeld.weldPoint.y + u.y * halfLen, selWeld.weldPoint.z + u.z * halfLen);
                        final scr0 = _projectPoint(p0, size, mesh);
                        final scr1 = _projectPoint(p1, size, mesh);
                        return Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: AssemblySelectedWeldHighlightPainter(screenStart: scr0, screenEnd: scr1),
                            ),
                          ),
                        );
                      },
                    ),

                  // =================================================================
                  // 2b. WELD JOINT STYLE SELECTION TOOLBAR (welding_simulation_docs.md)
                  // =================================================================
                  if (vm.activeToolMode == SketchUpToolMode.weld || vm.selectedWeldId != null)
                    AssemblyWeldJointStyleToolbar(
                      viewModel: vm,
                      position: _jointToolbarOffset,
                      onDragUpdate: (details) {
                        setState(() {
                          _jointToolbarOffset += details.delta;
                        });
                      },
                      onToggleMinimize: () => setState(() => vm.toggleJointToolbarMinimized()),
                      onClose: () => setState(() => vm.toggleJointStyleToolbar()),
                    ),

                  // =================================================================
                  // 2b-2. WELD QUALITY EVALUATION CARD & DEFECT SIDEBAR (welding_simulation_docs.md)
                  // =================================================================
                  if (vm.latestWeldEvaluation != null)
                    AssemblyWeldQualityHUD(
                      viewModel: vm,
                      onAnomalyTap: (pos) => _smoothAnimateCameraTo(pos, targetZoom: 5.5),
                      onInspectSeam: () {
                        final selectedWeld = vm.selectedWeld;
                        if (selectedWeld != null) {
                          _smoothAnimateCameraTo(selectedWeld.weldPoint, targetZoom: 5.0);
                        } else if (vm.doc.welds.isNotEmpty) {
                          _smoothAnimateCameraTo(vm.doc.welds.last.weldPoint, targetZoom: 5.0);
                        }
                      },
                      onResetCam: _resetCamera,
                      onDismiss: () => vm.clearWeldEvaluation(),
                      onToggleCardMinimize: () => setState(() => vm.toggleQualityCardMinimized()),
                      onToggleSidebarMinimize: () => setState(() => vm.toggleAnomalySidebarMinimized()),
                    ),

                  // =================================================================
                  // 2c. INTERACTIVE REAL-WORLD WELDING TORCH BRUSH, ARC LAMP & SPARKS
                  // =================================================================
                  if (vm.activeToolMode == SketchUpToolMode.weld && _isDrawingWeld && _weldDraftPath.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: AssemblyWeldLampPainter(torchPosition: _weldDraftPath.last, isWelding: _isDrawingWeld, flickerPhase: _weldFlickerPhase),
                        ),
                      ),
                    ),

                  if (vm.activeToolMode == SketchUpToolMode.weld && _isDrawingWeld && _weldDraftPath.isNotEmpty)
                    Builder(
                      builder: (context) {
                        double dynamicBeadRadius = 11.5;
                        double dynamicSpacing = 9.0;
                        if (_weld3DPoints.isNotEmpty || mesh.allPolygons.isNotEmpty) {
                          final refPt = _weld3DPoints.isNotEmpty ? _weld3DPoints.last : mesh.center;
                          final p0 = _projectPoint(refPt, size, mesh);
                          final p1 = _projectPoint(CadPoint3D(refPt.x + 10.0, refPt.y, refPt.z), size, mesh);
                          final p2 = _projectPoint(CadPoint3D(refPt.x, refPt.y + 10.0, refPt.z), size, mesh);
                          final p3 = _projectPoint(CadPoint3D(refPt.x, refPt.y, refPt.z + 10.0), size, mesh);
                          final d1 = (p1 - p0).distance / 10.0;
                          final d2 = (p2 - p0).distance / 10.0;
                          final d3 = (p3 - p0).distance / 10.0;
                          final pxPerMm = math.max(d1, math.max(d2, d3));
                          if (pxPerMm > 0.02) {
                            dynamicBeadRadius = (pxPerMm * 4.5).clamp(2.5, 45.0);
                            dynamicSpacing = (dynamicBeadRadius * 0.72).clamp(1.8, 32.0);
                          }
                        }
                        return Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _WeldBeadsBrushPainter(
                                path: AssemblyWeldSmoothingHelper.smooth2DPath(_weldDraftPath),
                                isFinished: false,
                                beadRadius: dynamicBeadRadius,
                                scallopSpacing: dynamicSpacing,
                              ),
                            ),
                          ),
                        );
                      },
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
                  // Contextual Banner for Auto-Span Bridging Tool (Key: B)
                  if (vm.activeToolMode == SketchUpToolMode.bridge)
                    Positioned(
                      top: 62,
                      left: 70,
                      right: 120,
                      child: Center(
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                              boxShadow: [BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 2)],
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
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
                                    onTap: () {
                                      vm.cancelBridge();
                                      vm.setToolMode(SketchUpToolMode.select);
                                    },
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
                      ),
                    ),

                  // Contextual Banner for Interactive Weld Tool (Key: W)
                  if (vm.activeToolMode == SketchUpToolMode.weld)
                    Positioned(
                      top: 62,
                      left: 70,
                      right: 120,
                      child: Center(
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
                              boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 2)],
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
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
                      ),
                    ),

                  // Contextual Banner for Magnetic Tool (Key: J)
                  if (vm.activeToolMode == SketchUpToolMode.magnetic)
                    Positioned(
                      top: 62,
                      left: 70,
                      right: 120,
                      child: Center(
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF818CF8), width: 1.2),
                              boxShadow: [BoxShadow(color: const Color(0xFF818CF8).withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 2)],
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
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
                      ),
                    ),

                  // Contextual Banner for Create Sketch / Plane Selection Mode (Phase 1)
                  if (vm.isPlaneSelectionMode) AssemblyPlaneSelectionBanner(viewModel: vm),

                  // Contextual In-Viewport Warning Banner (Item 5.1 / SS5)
                  if (_subtleWarningText != null)
                    Positioned(
                      top: 104,
                      left: 70,
                      right: 120,
                      child: Center(
                        child: Material(
                          color: Colors.transparent,
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
                    ),

                  // =================================================================
                  // 3. SKETCHUP-STYLE VERTICAL TOOL PALETTE (SS2)
                  // =================================================================
                  if (!vm.isCleanCanvasMode && vm.showSketchupToolbar)
                    Positioned(
                      top: 14,
                      left: 12,
                      child: AssemblySketchupToolbar(viewModel: vm, onZoomExtents: _zoomToFit),
                    ),

                  // =================================================================
                  // 3b. FLOATING INDUSTRIAL CAD 3D NAVIGATION BAR
                  // =================================================================
                  if (!vm.isSketchMode && !vm.isCleanCanvasMode && vm.show3dNavigationBar)
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
                  if (!vm.isSketchMode && vm.showViewsToolbar && !vm.isCleanCanvasMode)
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
                        onToggleMinimize: () => setState(() => vm.toggleViewsToolbarMinimized()),
                        onClose: () => setState(() => vm.toggleViewsToolbar()),
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
                  Positioned(
                    top: 14,
                    right: 14,
                    child: ListenableBuilder(
                      listenable: _cameraRepaintNotifier,
                      builder: (context, _) => StudioViewCube(
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
                  ),

                  // =================================================================
                  // 4.5 FLOATING GRAPHICS PREFERENCES PANEL (SS2)
                  // =================================================================
                  if (vm.isGraphicsPreferencesOpen)
                    Positioned(
                      top: 56,
                      bottom: 20,
                      right: 140,
                      child: StudioGraphicsPreferencesPanel(
                        preferences: vm.graphicsPreferences,
                        snapDistancePx: vm.magneticSnapDistancePx,
                        onSnapDistanceChanged: (val) {
                          vm.setMagneticSnapDistance(val);
                          setState(() {});
                        },
                        onChanged: (prefs) {
                          vm.graphicsPreferences = prefs;
                          _applyEnvironmentSettings();
                          _rebuildGpuCadModel(force: true);
                          setState(() {});
                        },
                        onClose: () {
                          setState(() {
                            vm.isGraphicsPreferencesOpen = false;
                          });
                        },
                        onResetToDefault: () {
                          vm.graphicsPreferences = const OnshapeGraphicsPreferences();
                          _applyEnvironmentSettings();
                          _rebuildGpuCadModel(force: true);
                          setState(() {});
                        },
                      ),
                    ),

                  // =================================================================
                  // 5. SKETCHUP-STYLE PRIMARY MOVEMENT & EDIT TOOLBAR (TOP CENTER)
                  // =================================================================
                  if (!vm.isSketchMode && vm.showMovementToolbar)
                    Positioned(top: 14, left: 0, right: 0, child: Center(child: _buildSketchUpMovementToolbar(vm))),

                  // =================================================================
                  // 5.5 LIVE OSHA / ISO COMPLIANCE BADGE & CUT LIST BOM (TOP RIGHT)
                  // =================================================================
                  if (!vm.isSketchMode && !vm.isCleanCanvasMode) Positioned(top: 14, right: 16, child: _buildTopRightStatusPill(context, vm)),

                  // =================================================================
                  // 6. ONSHAPE FLOATING SKETCH FEATURE DIALOG CARD (TOP-LEFT)
                  // =================================================================
                  if (vm.isSketchMode) Positioned(top: 0, left: 0, child: _buildOnshapeSketchHUD(vm)),

                  // =================================================================
                  // 6a. ONSHAPE DIRECT 3D SKETCH TOOLBAR HUD (TOP-RIGHT)
                  // =================================================================
                  if (vm.isSketchMode && vm.showLegacySketchHud) Positioned(top: 14, right: 16, child: AssemblySketchHud(viewModel: vm)),

                  // =================================================================
                  // 6b. ONSHAPE / FUSION 360 PARAMETRIC DIMENSION & FEATURE MODIFIER PANEL
                  // =================================================================
                  if (vm.isSketchMode && vm.selectedSketchEntity != null)
                    Positioned(
                      top: 65,
                      right: 248,
                      child: AssemblySketchParameterPanel(
                        viewModel: vm,
                        onRebuildModel: () {
                          setState(() {});
                          _rebuildGpuCadModel();
                        },
                      ),
                    ),

                  // =================================================================
                  // 6c. FUSION 360 SKETCH PALETTE HUD
                  // =================================================================
                  if (vm.isSketchMode && vm.showLegacySketchPalette && vm.activeSketchPlane != null) AssemblySketchPalette(viewModel: vm),

                  // =================================================================
                  // 6d. FUSION 360 3D EXTRUDE INSPECTOR DIALOG (Phase 5)
                  // =================================================================
                  if (vm.isExtrudeMode && vm.activeSketchPlane != null) Positioned(top: 80, right: 248, child: AssemblyExtrudeDialog(viewModel: vm)),

                  // =================================================================
                  // 7. SELECTED PART / WELD STATUS PILL (BOTTOM CENTER)
                  // =================================================================
                  if (vm.selectedPart != null && !vm.isSketchMode)
                    Positioned(
                      bottom: vm.timelineItems.isNotEmpty ? 58 : 16,
                      left: 16,
                      right: 260,
                      child: Center(child: _buildBottomQuickActionBar(vm)),
                    ),
                  if (vm.selectedWeld != null && !vm.isSketchMode)
                    Positioned(
                      bottom: vm.timelineItems.isNotEmpty ? 58 : 16,
                      left: 16,
                      right: 260,
                      child: Center(child: _buildSelectedWeldStatusBar(context, vm)),
                    ),

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

                  // =================================================================
                  // 10. CANVAS CONTROLS & TOOLBAR VISIBILITY MANAGER (BOTTOM LEFT)
                  // =================================================================
                  if (!vm.isSketchMode && !vm.isCleanCanvasMode) AssemblyCanvasControlsHUD(viewModel: vm, onResetPositions: _resetToolbarPositions),

                  // =================================================================
                  // 11. AUTODESK FUSION 360 PARAMETRIC TIMELINE (BOTTOM)
                  // =================================================================
                  if (!vm.isSketchMode && !vm.isCleanCanvasMode && vm.timelineItems.isNotEmpty)
                    Positioned(bottom: 16, left: 104, right: 264, child: AssemblyParametricTimeline(viewModel: vm)),

                  // =================================================================
                  // 12. PARAMETRIC CAD & VIEWPORT SETTINGS MODAL DIALOG
                  // =================================================================
                  if (vm.isCadSettingsOpen) Positioned.fill(child: AssemblyCadSettingsDialog(viewModel: vm)),
                ],
              ),
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

      bool isShift = false;
      try {
        isShift = HardwareKeyboard.instance.isShiftPressed;
      } catch (_) {}

      if (isShift && widget.viewModel.snapToGrid) {
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

      bool isShift = false;
      try {
        isShift = HardwareKeyboard.instance.isShiftPressed;
      } catch (_) {}

      if (isShift && widget.viewModel.snapToGrid) {
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
      // CRITICAL FIX: When sketching on an active 3D CADSketchPlane, Listener.onPointerDown
      // handles all 2-click primitive creation and selection. Do NOT run legacy 1-click tap hole punching!
      if (vm.activeSketchPlane != null) {
        return;
      }
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

  AssemblyRayHit? _findFrontmostRaycastHit(Offset cursorLocalPos, Size size, FoldedMeshResult mesh) {
    if (mesh.allPolygons.isEmpty || size.width <= 0 || size.height <= 0) return null;
    final (rayOrigin, rayDir) = _getRayFromScreen(cursorLocalPos, size, mesh);
    return AssemblyRaycaster.raycast(rayOrigin: rayOrigin, rayDirection: rayDir, mesh: mesh);
  }

  CadFoldedPolygon3D? _findFrontmostPolygonUnderCursor(Offset cursorLocalPos, Size size, FoldedMeshResult mesh) {
    if (mesh.allPolygons.isEmpty || size.width <= 0 || size.height <= 0) return null;

    // 1. Direct 3D Raycast against all model polygons (true frontmost surface)
    final hit = _findFrontmostRaycastHit(cursorLocalPos, size, mesh);
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

  Offset? _unprojectScreenToPlane(Offset screenPos, CADSketchPlane plane, Size size, FoldedMeshResult mesh) {
    final (rayOrigin, rayDir) = _getRayFromScreen(screenPos, size, mesh);
    final planeNormal = plane.zAxis;
    final denom = rayDir.dot(planeNormal);
    if (denom.abs() < 1e-6) return null;
    final diff = plane.origin - rayOrigin;
    final t = diff.dot(planeNormal) / denom;
    final hitWorld = rayOrigin + (rayDir * t);
    return plane.toLocal(hitWorld);
  }

  CADSketchPlane? _findPlaneUnderScreenCursor(Offset screenPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (!vm.isPlaneSelectionMode && !vm.showDatumPlanes && !vm.showConstructionPlanes) return null;

    final (rayOrigin, rayDir) = _getRayFromScreen(screenPos, size, mesh);
    CADSketchPlane? bestPlane;
    double closestT = double.infinity;

    for (final plane in vm.allAvailablePlanes) {
      if (!plane.isVisible) continue;
      final res = plane.intersectRay(rayOrigin, rayDir);
      if (res.hit && res.t > 0 && res.t < closestT) {
        closestT = res.t;
        bestPlane = plane;
      }
    }
    return bestPlane;
  }

  void _updateSketchHover(Offset screenPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    final plane = vm.activeSketchPlane;
    if (plane == null) return;
    final localPos = _unprojectScreenToPlane(screenPos, plane, size, mesh);
    if (localPos == null) return;
    vm.updateSketchPlaneHover(localPos);
    _updateInteractiveSketchVcb(vm, vm.activePlaneHoverLocal ?? localPos);
  }

  void _updateInteractiveSketchVcb(AssemblyStudioViewModel vm, Offset currentLocal) {
    if (!vm.isSketchMode || vm.activeSketchPlane == null) return;
    final tool = vm.activeSketchTool;
    final pStart = vm.sketchInteractiveStartPoint;

    if (pStart != null) {
      if (tool == 'rectangle' || tool == 'rect') {
        final w = (currentLocal.dx - pStart.dx).abs();
        final h = (currentLocal.dy - pStart.dy).abs();
        vm.setVcbState(
          label: '📐 Dimensions (W x H)',
          value: '${w.toStringAsFixed(1)} x ${h.toStringAsFixed(1)} mm',
          hint: 'Click 2nd corner, or type dimensions (e.g. 50, 30)',
        );
      } else if (tool == 'center_rect') {
        final w = 2.0 * (currentLocal.dx - pStart.dx).abs();
        final h = 2.0 * (currentLocal.dy - pStart.dy).abs();
        vm.setVcbState(
          label: '📐 Center Rect (W x H)',
          value: '${w.toStringAsFixed(1)} x ${h.toStringAsFixed(1)} mm',
          hint: 'Click corner, or type dimensions (e.g. 60, 40)',
        );
      } else if (tool == 'circle' || tool == 'hole') {
        final r = (currentLocal - pStart).distance;
        final dia = r * 2.0;
        vm.setVcbState(
          label: '⭕ Diameter (Ø)',
          value: 'Ø ${dia.toStringAsFixed(1)} mm (R: ${r.toStringAsFixed(1)})',
          hint: 'Click edge, or type radius/diameter',
        );
      } else if (tool == 'arc_3point') {
        if (vm.sketchInteractiveMidPoint == null) {
          final chord = (currentLocal - pStart).distance;
          vm.setVcbState(label: '⌒ 3-Pt Arc Chord', value: 'Chord: ${chord.toStringAsFixed(1)} mm', hint: 'Click to place End Point of Arc');
        } else {
          final pEnd = vm.sketchInteractiveMidPoint!;
          final arcTemp = CADArcEntity(id: 'vcb_arc', startPoint: pStart, endPoint: pEnd, pointOnArc: currentLocal);
          final geom = arcTemp.computeCircumcircle();
          if (geom != null) {
            vm.setVcbState(
              label: '⌒ 3-Pt Arc Radius',
              value: 'R: ${geom.radius.toStringAsFixed(1)} mm (Sweep: ${(geom.sweep * 180 / math.pi).abs().toStringAsFixed(1)}°)',
              hint: 'Click to place Apex/Curvature Point',
            );
          } else {
            vm.setVcbState(label: '⌒ 3-Pt Arc', value: 'Collinear', hint: 'Move cursor away from chord line to define curvature');
          }
        }
      } else if (tool == 'line') {
        final len = (currentLocal - pStart).distance;
        final angleRad = math.atan2(currentLocal.dy - pStart.dy, currentLocal.dx - pStart.dx);
        final angleDeg = (angleRad * 180 / math.pi).toStringAsFixed(1);
        vm.setVcbState(
          label: '📏 Line Length & Angle',
          value: '${len.toStringAsFixed(1)} mm  ∠ $angleDeg°',
          hint: 'Click next vertex, or press Escape to finish chaining',
        );
      }
    } else if (vm.sketchPolylinePoints.isNotEmpty) {
      final lastPt = vm.sketchPolylinePoints.last;
      final len = (currentLocal - lastPt).distance;
      vm.setVcbState(
        label: '📐 Polyline (Segment ${vm.sketchPolylinePoints.length})',
        value: 'L: ${len.toStringAsFixed(1)} mm (${vm.sketchPolylinePoints.length} vertices)',
        hint: 'Click near start point to close, or Escape to cancel',
      );
    }
  }

  void _updateProjectGeometryHover(Offset screenPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (mesh.allPolygons.isEmpty || size.width <= 0 || size.height <= 0) {
      vm.setHoveredProjectable(entityId: null);
      return;
    }

    // 1. Check for closest vertex (within 14px threshold on screen)
    CadPoint3D? bestVertex;
    double bestVertexDist = 14.0;
    for (final poly in mesh.allPolygons) {
      for (final v in poly.vertices) {
        final scr = _projectPoint(v, size, mesh);
        if (scr == Offset.zero) continue;
        final d = (screenPos - scr).distance;
        if (d < bestVertexDist) {
          bestVertexDist = d;
          bestVertex = v;
        }
      }
    }

    if (bestVertex != null) {
      vm.setHoveredProjectable(entityId: 'v_${bestVertex.x.toInt()}_${bestVertex.y.toInt()}_${bestVertex.z.toInt()}', point: bestVertex);
      return;
    }

    // 2. Check for closest edge (within 12px threshold on screen)
    List<CadPoint3D>? bestEdge;
    double bestEdgeDist = 12.0;
    String? bestEdgeId;
    for (final poly in mesh.allPolygons) {
      if (poly.vertices.length < 2) continue;
      for (int i = 0; i < poly.vertices.length; i++) {
        final v1 = poly.vertices[i];
        final v2 = poly.vertices[(i + 1) % poly.vertices.length];
        final scr1 = _projectPoint(v1, size, mesh);
        final scr2 = _projectPoint(v2, size, mesh);
        if (scr1 == Offset.zero && scr2 == Offset.zero) continue;
        final d = _distToSegment(screenPos, scr1, scr2);
        if (d < bestEdgeDist) {
          bestEdgeDist = d;
          bestEdge = [v1, v2];
          bestEdgeId = '${poly.faceId}_edge_$i';
        }
      }
    }

    if (bestEdge != null) {
      vm.setHoveredProjectable(entityId: bestEdgeId, edge: bestEdge);
      return;
    }

    // 3. Check for frontmost polygon face
    final hitPoly = _findFrontmostPolygonUnderCursor(screenPos, size, mesh);
    if (hitPoly != null) {
      vm.setHoveredProjectable(entityId: 'face:${hitPoly.faceId}');
      return;
    }

    vm.setHoveredProjectable(entityId: null);
  }

  void _handleProjectGeometryClick(Offset screenPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (vm.activeSketchPlane == null) return;

    if (vm.hoveredProjectablePoint != null) {
      vm.project3DVertexToActivePlane(vm.hoveredProjectablePoint!, sourceId: vm.hoveredProjectableEntityId);
      setState(() {});
      _rebuildGpuCadModel();
      return;
    }

    if (vm.hoveredProjectableEdge != null && vm.hoveredProjectableEdge!.length >= 2) {
      vm.project3DEdgeToActivePlane(vm.hoveredProjectableEdge![0], vm.hoveredProjectableEdge![1], sourceId: vm.hoveredProjectableEntityId);
      setState(() {});
      _rebuildGpuCadModel();
      return;
    }

    final hitPoly = _findFrontmostPolygonUnderCursor(screenPos, size, mesh);
    if (hitPoly != null) {
      vm.project3DFaceToActivePlane(hitPoly, sourceId: hitPoly.faceId);
      setState(() {});
      _rebuildGpuCadModel();
    }
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    final proj = a + ab * t;
    return (p - proj).distance;
  }

  AssemblyWeldJoint? _findNearestWeldUnderScreenCursor(
    Offset cursorScreen,
    Size size,
    FoldedMeshResult mesh,
    AssemblyStudioViewModel vm, {
    double maxScreenDist = 14.0,
  }) {
    if (vm.doc.welds.isEmpty || size.width <= 0 || size.height <= 0) return null;

    double closestDist = maxScreenDist;
    AssemblyWeldJoint? bestWeld;

    for (final weld in vm.doc.welds) {
      final samplePts = <CadPoint3D>[];
      if (weld.pathPoints != null && weld.pathPoints!.length >= 2) {
        samplePts.addAll(weld.pathPoints!);
      } else {
        CadPoint3D u = weld.weldAxis;
        final uLen = math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z);
        if (uLen > 1e-4) {
          u = CadPoint3D(u.x / uLen, u.y / uLen, u.z / uLen);
        } else {
          u = const CadPoint3D(1.0, 0.0, 0.0);
        }
        final halfL = math.max(12.0, weld.weldLengthMm) / 2.0;
        final start = CadPoint3D(weld.weldPoint.x - u.x * halfL, weld.weldPoint.y - u.y * halfL, weld.weldPoint.z - u.z * halfL);
        final end = CadPoint3D(weld.weldPoint.x + u.x * halfL, weld.weldPoint.y + u.y * halfL, weld.weldPoint.z + u.z * halfL);
        samplePts.add(start);
        samplePts.add(weld.weldPoint);
        samplePts.add(end);
      }

      // Check distance from cursorScreen to each segment between sample points in screen space
      for (int i = 0; i < samplePts.length - 1; i++) {
        final p1 = _projectPoint(samplePts[i], size, mesh);
        final p2 = _projectPoint(samplePts[i + 1], size, mesh);
        if (p1 == Offset.zero && p2 == Offset.zero) continue;

        final dist = _distToSegment(cursorScreen, p1, p2);
        if (dist < closestDist) {
          closestDist = dist;
          bestWeld = weld;
        }
      }
    }

    return bestWeld;
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
      if (screenPt != null) return screenPt;
      return _projectPointPaint(p, size, mesh);
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
  // ONSHAPE FLOATING SKETCH FEATURE DIALOG
  // ---------------------------------------------------------------------------
  Widget _buildOnshapeSketchHUD(AssemblyStudioViewModel vm) {
    return AssemblyOnshapeSketchDialog(
      viewModel: vm,
      onAccept: () {
        vm.finishSketch();
        setState(() {});
      },
      onCancel: () {
        vm.exitSketchMode();
        setState(() {});
      },
    );
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
        _isVcbUserTyping = false;
        if (_isMovingEntity) {
          _cancelEntityMove(vm);
        }
        _vcbController.clear();
        vm.vcbValue = '';
        vm.notifyDocChanged();
      },
      onChanged: (val) {
        _isVcbUserTyping = true;
        if (_isMovingEntity) {
          _applyVcbTextToMovingEntity(val, vm);
        } else if (vm.activeToolMode == SketchUpToolMode.rotate && (_rotatePhase == RotateToolPhase.rotatingAngle || _draggedParts.isNotEmpty)) {
          _applyVcbTextToRotatingEntity(val, vm);
        }
      },
      onSubmitted: (val) {
        _isVcbUserTyping = false;
        if (_isMovingEntity) {
          final clean = val.replaceAll('mm', '').replaceAll('cm', '').replaceAll('m', '').replaceAll('in', '').replaceAll('ft', '').trim();
          final parsed = double.tryParse(clean);
          if (parsed == null || clean.isEmpty) {
            _cancelEntityMove(vm);
            _vcbController.clear();
            _viewportFocusNode.requestFocus();
            return;
          }
          _applyVcbTextToMovingEntity(clean, vm);
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

  /// Intersects the camera-facing billboard view plane passing through planeOrigin
  /// for silky-smooth, continuous 60FPS mouse dragging without oblique distortion or jumping
  CadPoint3D _intersectCameraViewPlane(Offset screenPos, Size size, FoldedMeshResult mesh, CadPoint3D planeOrigin) {
    final (rayOrigin, rayDir) = _getRayFromScreen(screenPos, size, mesh);
    final (_, centerRayDir) = _getRayFromScreen(Offset(size.width / 2.0, size.height / 2.0), size, mesh);
    final rLen = centerRayDir.length;
    final normal = rLen > 1e-6 ? (centerRayDir / rLen) : vm_math.Vector3(0.0, 0.0, 1.0);

    final denom = rayDir.dot(normal);
    if (denom.abs() > 1e-5) {
      final diff = vm_math.Vector3(planeOrigin.x - rayOrigin.x, planeOrigin.y - rayOrigin.y, planeOrigin.z - rayOrigin.z);
      final t = diff.dot(normal) / denom;
      if (t > 0) {
        final hit = rayOrigin + rayDir * t;
        return CadPoint3D(hit.x, hit.y, hit.z);
      }
    }
    return planeOrigin;
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
    _clearDraggedWelds();
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
    _restoreDraggedWelds(vm);
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
    final snapLabel = _hoveredSnapPointModel != null ? ' • Snapped to ${_hoveredSnapPointModel!.label}' : '';
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
    _cachedMoveOtherSnapPoints.clear();
    _clearDraggedWelds();
    vm.invalidateMeshCache();
    _rebuildGpuCadModel(force: true);
    vm.notifyDocChanged();
    vm.setVcbState(label: 'Move', value: 'Placed', hint: 'Click entity point or surface to move again$snapLabel');
    setState(() {});
  }

  void _cancelEntityMove(AssemblyStudioViewModel vm) {
    for (final part in _draggedParts) {
      final startPos = _draggedPartsStartPos[part.id];
      if (startPos != null) {
        part.position = startPos;
      }
    }
    _restoreDraggedWelds(vm);
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
    _cachedMoveOtherSnapPoints.clear();
    vm.invalidateMeshCache();
    _rebuildGpuCadModel(force: true);
    vm.notifyDocChanged();
    vm.setVcbState(label: 'Move', value: 'Cancelled', hint: 'Click entity point or surface to move');
    setState(() {});
  }

  // Synchronized 3D Weld Movement & Rotation (Requirement SS4)
  void _snapshotDraggedWelds(AssemblyStudioViewModel vm) {
    _draggedWeldsStartPos.clear();
    _draggedWeldsStartSecPos.clear();
    _draggedWeldsStartPathPoints.clear();
    final draggedPartIds = _draggedParts.map((p) => p.id).toSet();
    for (final w in vm.doc.welds) {
      if (draggedPartIds.contains(w.partAId) || draggedPartIds.contains(w.partBId)) {
        _draggedWeldsStartPos[w.id] = w.weldPoint;
        _draggedWeldsStartSecPos[w.id] = w.secondWeldPoint;
        _draggedWeldsStartPathPoints[w.id] = w.pathPoints != null ? List<CadPoint3D>.from(w.pathPoints!) : null;
      }
    }
  }

  void _applyTranslationToDraggedWelds(CadPoint3D worldDelta, AssemblyStudioViewModel vm) {
    if (_draggedWeldsStartPos.isEmpty) return;
    for (int i = 0; i < vm.doc.welds.length; i++) {
      final w = vm.doc.welds[i];
      final startPos = _draggedWeldsStartPos[w.id];
      if (startPos != null) {
        final startSec = _draggedWeldsStartSecPos[w.id];
        final startPaths = _draggedWeldsStartPathPoints[w.id];
        vm.doc.welds[i] = w.copyWith(
          weldPoint: CadPoint3D(startPos.x + worldDelta.x, startPos.y + worldDelta.y, startPos.z + worldDelta.z),
          secondWeldPoint: startSec != null ? CadPoint3D(startSec.x + worldDelta.x, startSec.y + worldDelta.y, startSec.z + worldDelta.z) : null,
          pathPoints: startPaths?.map((pt) => CadPoint3D(pt.x + worldDelta.x, pt.y + worldDelta.y, pt.z + worldDelta.z)).toList(),
        );
      }
    }
  }

  void _applyRotationToDraggedWelds({required CadPoint3D centerPoint, required GizmoAxis axis, required double angleDeg, required AssemblyStudioViewModel vm}) {
    if (_draggedWeldsStartPos.isEmpty) return;
    for (int i = 0; i < vm.doc.welds.length; i++) {
      final w = vm.doc.welds[i];
      final startPos = _draggedWeldsStartPos[w.id];
      if (startPos != null) {
        final startSec = _draggedWeldsStartSecPos[w.id];
        final startPaths = _draggedWeldsStartPathPoints[w.id];
        final newPos = AssemblyRotateMathHelper.rotatePoint(point: startPos, centerPoint: centerPoint, axis: axis, angleDeg: angleDeg);
        final newSec = startSec != null
            ? AssemblyRotateMathHelper.rotatePoint(point: startSec, centerPoint: centerPoint, axis: axis, angleDeg: angleDeg)
            : null;
        final newPaths = startPaths
            ?.map((pt) => AssemblyRotateMathHelper.rotatePoint(point: pt, centerPoint: centerPoint, axis: axis, angleDeg: angleDeg))
            .toList();
        vm.doc.welds[i] = w.copyWith(weldPoint: newPos, secondWeldPoint: newSec, pathPoints: newPaths);
      }
    }
  }

  void _restoreDraggedWelds(AssemblyStudioViewModel vm) {
    if (_draggedWeldsStartPos.isEmpty) return;
    for (int i = 0; i < vm.doc.welds.length; i++) {
      final w = vm.doc.welds[i];
      final startPos = _draggedWeldsStartPos[w.id];
      if (startPos != null) {
        final startSec = _draggedWeldsStartSecPos[w.id];
        final startPaths = _draggedWeldsStartPathPoints[w.id];
        vm.doc.welds[i] = w.copyWith(weldPoint: startPos, secondWeldPoint: startSec, pathPoints: startPaths);
      }
    }
    _clearDraggedWelds();
  }

  void _clearDraggedWelds() {
    _draggedWeldsStartPos.clear();
    _draggedWeldsStartSecPos.clear();
    _draggedWeldsStartPathPoints.clear();
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
      _restoreDraggedWelds(vm);
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
    _applyTranslationToDraggedWelds(worldDelta, vm);
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
        _snapshotDraggedWelds(vm);
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
      _restoreDraggedWelds(vm);
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
    _applyRotationToDraggedWelds(centerPoint: center, axis: activeAxis, angleDeg: targetAngle, vm: vm);

    _hasRotatedPart = true;
    vm.invalidateMeshCache();
    _rebuildGpuCadModel(force: true);
    setState(() {});
  }

  void _spawnWeldSparks(Offset origin) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSparkSpawnMs < 45) return;
    _lastSparkSpawnMs = now;

    final rng = math.Random();
    final count = 2 + rng.nextInt(3); // Moderated realistic spark count (Req 5)
    for (int i = 0; i < count; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = 35.0 + rng.nextDouble() * 110.0;
      final vx = math.cos(angle) * speed;
      final vy = math.sin(angle) * speed - 28.0; // slight upward eruption
      final life = 0.18 + rng.nextDouble() * 0.35;
      // Strictly authentic fiery red and orange hues (Req 5)
      final colors = [
        const Color(0xFFEF4444), // Crimson Red
        const Color(0xFFDC2626), // Torch Red
        const Color(0xFFEA580C), // Fiery Red-Orange
        const Color(0xFFF97316), // Molten Orange
        const Color(0xFFFB923C), // Amber Orange
        const Color(0xFFFBBF24), // Golden Orange
      ];
      _weldSparks.add(
        _WeldSparkParticle(
          position: origin + Offset((rng.nextDouble() - 0.5) * 4, (rng.nextDouble() - 0.5) * 4),
          velocity: Offset(vx, vy),
          life: life,
          maxLife: life,
          size: 1.5 + rng.nextDouble() * 2.0,
          color: colors[rng.nextInt(colors.length)],
        ),
      );
    }
  }

  void _startWeldPhysicsLoop() {
    _weldPhysicsTimer?.cancel();
    _weldPhysicsTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_weldSparks.isEmpty && !_isDrawingWeld) {
        timer.cancel();
        _weldPhysicsTimer = null;
        return;
      }
      _updateWeldSparks(0.016);
      setState(() {
        _weldFlickerPhase = (_weldFlickerPhase + 0.25) % (math.pi * 2);
      });
    });
  }

  void _updateWeldSparks(double dt) {
    if (_weldSparks.isEmpty) return;
    for (int i = _weldSparks.length - 1; i >= 0; i--) {
      final s = _weldSparks[i];
      s.life -= dt;
      if (s.life <= 0) {
        _weldSparks.removeAt(i);
      } else {
        // Kinematic equation pos = pos + v*dt + 0.5*g*dt^2 per welding_simulation_docs.md
        const gravity = Offset(0, 320.0);
        s.position += s.velocity * dt + gravity * (0.5 * dt * dt);
        s.velocity += gravity * dt;
        s.size = math.max(0.6, s.size * (s.life / s.maxLife));
      }
    }
  }

  void _startEntityMove(AssemblyPart hitPart, CadPoint3D baseAnchor, Offset screenPos, AssemblyStudioViewModel vm, {FoldedMeshResult? mesh}) {
    _draggingPart = hitPart;
    _partDragStartScreen = screenPos;
    _hasMovedPart = false;
    _isMovingEntity = true;
    _isVcbUserTyping = false;

    final groupParts = hitPart.groupId != null ? vm.doc.parts.where((p) => p.groupId == hitPart.groupId).toList() : <AssemblyPart>[];
    _draggedParts.clear();
    _draggedParts.addAll(groupParts.isNotEmpty ? groupParts : [hitPart]);
    _draggedPartsStartPos.clear();
    for (final p in _draggedParts) {
      _draggedPartsStartPos[p.id] = p.position;
    }
    _snapshotDraggedWelds(vm);

    _moveBaseWorldPoint = baseAnchor;
    _moveBaseStartWorldPoint = _moveBaseWorldPoint;

    // Pre-cache other visible parts snap points for zero-overhead 120 FPS movement
    _cachedMoveOtherSnapPoints.clear();
    for (final p in vm.doc.parts) {
      if (!p.isVisible || _draggedParts.any((dp) => dp.id == p.id)) continue;
      _cachedMoveOtherSnapPoints.addAll(AssemblyDockingEngine.getAllSnapPointsForPart(p, cachedMesh: mesh));
    }

    final axisLockStr = vm.lockedAxis == GizmoAxis.x
        ? ' [X Red]'
        : (vm.lockedAxis == GizmoAxis.y ? ' [Y Green]' : (vm.lockedAxis == GizmoAxis.z ? ' [Z Blue]' : ''));
    vm.setVcbState(
      label: 'Distance$axisLockStr',
      value: vm.formatLength(0.0),
      hint: 'Move mouse freely to translate • Click to place anywhere • Esc to cancel',
    );
    setState(() {});
  }

  void _handleMovePreGrabHover(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    final candidatePoints = <AssemblySnapPoint>[];
    if (vm.selectedPart != null) {
      candidatePoints.addAll(AssemblyDockingEngine.getAllSnapPointsForPart(vm.selectedPart!, cachedMesh: mesh));
    } else {
      for (final p in vm.doc.parts) {
        if (!p.isVisible) continue;
        candidatePoints.addAll(AssemblyDockingEngine.getAllSnapPointsForPart(p, cachedMesh: mesh));
      }
    }

    final targetSnap = AssemblyDockingEngine.findNearestSnapPoint(
      screenCursor: localPos,
      candidates: candidatePoints,
      projectPoint: (pt) => _projectPoint(pt, size, mesh),
      maxPixelDistance: widget.viewModel.magneticSnapDistancePx,
    );

    if (targetSnap != null) {
      if (_hoveredSnapPointModel?.id != targetSnap.id) {
        _hoveredSnapPointModel = targetSnap;
        _hoveredSnapPoint = targetSnap.worldPosition;
        vm.setVcbState(label: 'Move [M]', value: targetSnap.label, hint: 'Click to grab anchor point • Arrow keys lock axis');
        setState(() {});
      }
    } else {
      if (_hoveredSnapPointModel != null) {
        _hoveredSnapPointModel = null;
        _hoveredSnapPoint = null;
        vm.setVcbState(
          label: 'Move [M]',
          value: vm.selectedPart != null ? vm.selectedPart!.name : 'Ready',
          hint: 'Click entity point or surface to grab • Arrow keys lock axis',
        );
        setState(() {});
      }
    }
  }

  void _handleMovePointerMove(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    if (_draggingPart == null || _draggedParts.isEmpty) return;

    final primaryPart = _draggingPart!;
    final refStartPos = _draggedPartsStartPos[primaryPart.id] ?? primaryPart.position;
    final baseAnchor = _moveBaseStartWorldPoint ?? _moveBaseWorldPoint ?? refStartPos;

    CadPoint3D worldDelta;

    // Detect candidate snap points on other visible parts (using pre-cached snap points for 120 FPS)
    final otherSnapPoints = _cachedMoveOtherSnapPoints.isNotEmpty
        ? _cachedMoveOtherSnapPoints
        : () {
            final pts = <AssemblySnapPoint>[];
            for (final p in vm.doc.parts) {
              if (!p.isVisible || _draggedParts.any((dp) => dp.id == p.id)) continue;
              pts.addAll(AssemblyDockingEngine.getAllSnapPointsForPart(p, cachedMesh: mesh));
            }
            return pts;
          }();

    final double snapMaxPx = 14.0;
    final targetSnap = AssemblyDockingEngine.findNearestSnapPoint(
      screenCursor: localPos,
      candidates: otherSnapPoints,
      projectPoint: (pt) => _projectPoint(pt, size, mesh),
      maxPixelDistance: snapMaxPx,
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

      // Silky-smooth, continuous 120 FPS movement along locked axis (no stepped jumping)
      worldDelta = CadPoint3D(axisWorldDir.x * s, axisWorldDir.y * s, axisWorldDir.z * s);
    } else {
      // 2. Free movement: check snap candidates across other parts first, else intersect camera billboard plane
      if (targetSnap != null) {
        worldDelta = CadPoint3D(
          targetSnap.worldPosition.x - baseAnchor.x,
          targetSnap.worldPosition.y - baseAnchor.y,
          targetSnap.worldPosition.z - baseAnchor.z,
        );
      } else {
        final hitPlanePos = _intersectCameraViewPlane(localPos, size, mesh, baseAnchor);
        final dx = hitPlanePos.x - baseAnchor.x;
        final dy = hitPlanePos.y - baseAnchor.y;
        final dz = hitPlanePos.z - baseAnchor.z;

        // Silky-smooth, continuous 120 FPS free camera-plane movement (no stepped jumping)
        worldDelta = CadPoint3D(dx, dy, dz);
      }
    }

    _hasMovedPart = true;

    // Apply synchronized translation to all parts in the rigid cluster
    for (final part in _draggedParts) {
      final startPos = _draggedPartsStartPos[part.id] ?? part.position;
      part.position = CadPoint3D(startPos.x + worldDelta.x, startPos.y + worldDelta.y, startPos.z + worldDelta.z);
    }
    _applyTranslationToDraggedWelds(worldDelta, vm);

    // Keep base anchor point moving synchronously
    _moveBaseWorldPoint = CadPoint3D(baseAnchor.x + worldDelta.x, baseAnchor.y + worldDelta.y, baseAnchor.z + worldDelta.z);

    // Synchronous lightweight repaint without blocking GPU reallocation
    vm.invalidateMeshCache();
    setState(() {});

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
      bool isShift = false;
      try {
        isShift = HardwareKeyboard.instance.isShiftPressed;
      } catch (_) {}
      final snappedAngle = isShift
          ? AssemblyRotateMathHelper.snapRotateAngle(
              rawAngleDeg: rawAngle,
              cursorScreen: localPos,
              centerScreen: centerScreen,
              screenRadius: screenRadius,
              snapToGrid: true,
            )
          : (rawAngle * 10.0).round() / 10.0;
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
      _applyRotationToDraggedWelds(centerPoint: _rotateCenterPoint!, axis: activeAxis, angleDeg: snappedAngle, vm: vm);
      vm.setVcbState(
        label: 'Angle',
        value: '${snappedAngle.toStringAsFixed(1)}°',
        hint: _isRotateCopyMode ? 'Click to commit copy, or type angle' : 'Click to commit rotation, or type angle',
      );
      vm.invalidateMeshCache();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastGpuRebuildMs >= 32) {
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
      _snapshotDraggedWelds(vm);
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
      vm.setVcbState(label: 'Weld Tool', value: 'Drag across seam', hint: 'Click and drag torch across seam of 2 entities to paint beads');
      return;
    }

    final vicinity = AssemblyWeldSmoothingHelper.resolveTwoEntityWeldVicinity(
      raw3DPoints: _weld3DPoints,
      startScreen: startScreen,
      endScreen: endScreen,
      viewportSize: size,
      mesh: mesh,
      allParts: vm.doc.parts,
      findPartForFaceId: vm.findPartForFaceId,
      getRayFromScreen: (pt) => _getRayFromScreen(pt, size, mesh),
      hitPartIds: _weldHitPartIds,
      maxVicinityDistanceMm: 25.0,
    );

    if (vicinity == null) {
      // Clear draft stroke so wrong weld stroke does not persist on screen (SS5)
      _weldDraftPath.clear();
      _weldDraftStartScreen = null;
      _weld3DPoints.clear();
      _weldHitPartIds.clear();
      _weldSparks.clear();
      setState(() {});

      // Restriction: Single-surface welding is strictly restricted (Req 3, SS2 & SS3)
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Welding restricted: 2 entities must be present in direct contact seam (<= 25mm) to create a weld joint.'),
          duration: Duration(seconds: 3),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    _weldStopwatch.stop();
    vm.evaluateWeldQuality(pathPoints: vicinity.smoothedPathPoints, timestamps: _weldTimestamps);

    // Solid 3D fillet weld bead matching auto demo weld geometry and fullness (SS1 Req 1)
    vm.weldParts(
      vicinity.partA.id,
      vicinity.partB.id,
      weldPoint: vicinity.weldPoint,
      weldAxis: vicinity.weldAxis,
      legDir1: vicinity.legDir1,
      legDir2: vicinity.legDir2,
      weldLengthMm: vicinity.seamLengthMm,
      bothSides: false,
      pathPoints: null,
      weldSizeMm: 6.0,
    );

    // Guarantee immediate 3D CAD mesh & GPU node invalidation and update (Req 1)
    vm.invalidateMeshCache();
    vm.notifyDocChanged();
    _rebuildGpuCadModel(force: true);
    setState(() {});

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Fillet Weld Bead created between ${vicinity.partA.name} and ${vicinity.partB.name} (${vicinity.seamLengthMm.toInt()}mm)'),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF0F766E),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAGNETIC SNAP POINT HOVER & ATTRACTION LOGIC (Requirement 4)
  // ---------------------------------------------------------------------------
  void _handleMagneticSnapHover(Offset localPos, Size size, FoldedMeshResult mesh, AssemblyStudioViewModel vm) {
    final candidateSnapPoints = <AssemblySnapPoint>[];
    for (final part in vm.doc.parts) {
      if (!part.isVisible) continue;
      candidateSnapPoints.addAll(AssemblyDockingEngine.getAllSnapPointsForPart(part, cachedMesh: mesh));
    }
    // Weld string snap points: start edge, center, end edge (Item 2)
    for (final weld in vm.doc.welds) {
      candidateSnapPoints.addAll(AssemblyDockingEngine.getAllSnapPointsForWeld(weld));
    }

    final targetSnap = AssemblyDockingEngine.findNearestSnapPoint(
      screenCursor: localPos,
      candidates: candidateSnapPoints,
      projectPoint: (pt) => _projectPoint(pt, size, mesh),
      maxPixelDistance: vm.magneticSnapDistancePx,
    );

    final prevSnap = _hoveredSnapPointModel;
    if (targetSnap != null) {
      _hoveredSnapPointModel = targetSnap;
      _hoveredSnapPoint = targetSnap.worldPosition;
      final scr = _projectPoint(targetSnap.worldPosition, size, mesh);
      if (scr != Offset.zero) {
        _cursorScreenPosNotifier.value = scr;
      }
      if (prevSnap?.id != targetSnap.id) {
        setState(() {});
      }
    } else {
      if (_hoveredSnapPointModel != null) {
        _hoveredSnapPointModel = null;
        _hoveredSnapPoint = null;
        setState(() {});
      }
      _cursorScreenPosNotifier.value = localPos;
    }
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
typedef _CadSelectionPointerOverlayPainter = AssemblyCadSelectionCursorPainter;
typedef _WeldSparkParticle = AssemblyWeldSparkParticle;
typedef _WeldSparksPainter = AssemblyWeldSparksPainter;
typedef _WeldBeadsBrushPainter = AssemblyWeldBeadsBrushPainter;
typedef _SketchUpWeldingTorchCursorPainter = AssemblyWeldingTorchCursorPainter;
typedef _MagneticSpotsOverlayPainter = AssemblyMagneticSpotsOverlayPainter;
