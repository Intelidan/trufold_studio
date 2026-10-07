// =============================================================================
// flutter_scene_viewport_widget.dart
//
// Dual-Engine High-Performance 3D CAD Viewport for TruFold Studio:
// 1. Next-Generation Flutter GPU / Impeller (120 FPS PBR Hardware Engine)
// 2. 1st-Generation Pure Flutter Canvas 2.5D (Zero-GPU Software Backup View)
//
// Replicates the complete industrial UI/UX suite:
// - Interactive 3D ViewCube with orientation tracking and context menu
// - Floating CAD 3D Navigation Bar (view presets, orbit/pan, ortho/perspective)
// - Floating Graphics Preferences Panel (PBR, lighting, bloom, anti-aliasing)
// - Seamless Mouse Navigation (middle-drag pan, right/left-drag orbit, wheel zoom)
// - Live zero-drift 3D witness lines, bend callouts, and bounding badges
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../../engine/flutter_scene_cad_mesh_builder.dart';
import '../../../engine/kinematic_fold_engine.dart';
import '../../../models/cad_primitives.dart';
import '../../../models/cms/cms_physical_port.dart';
import '../../../models/cnc_punch_primitive.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../studio/studio_3d_navigation_bar.dart';
import '../studio/studio_graphics_preferences_panel.dart';
import '../studio/studio_view_cube.dart';
import 'painters/flutter_paint_3d_engine.dart';

/// Next-Generation 3D CAD Viewport with Dual-Engine (Flutter GPU / Flutter Paint) switching.
class FlutterSceneViewportWidget extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final bool isInteractionLocked;
  final Widget Function(BuildContext context, Size size, Offset Function(CadPoint3D p) projectPoint)? overlayBuilder;

  const FlutterSceneViewportWidget({super.key, required this.viewModel, this.isInteractionLocked = false, this.overlayBuilder});

  @override
  State<FlutterSceneViewportWidget> createState() => _FlutterSceneViewportWidgetState();
}

class _FlutterSceneViewportWidgetState extends State<FlutterSceneViewportWidget> with SingleTickerProviderStateMixin {
  // --- Flutter Scene (GPU Engine) ---
  Scene? _scene;
  late final Node _cameraNode;
  late final CameraComponent _cameraComponent;
  Node? _cadModelNode;
  PreprocessedMaterial? _masterShaderMaterial;

  // --- Smooth Camera Transition Animation ---
  late final AnimationController _cameraAnimationController;
  Cad3dCameraState? _animStartState;
  Cad3dCameraState? _animTargetState;
  double _animShortestAzimuthDiff = 0.0;
  double _animShortestElevationDiff = 0.0;

  // --- Engine & Viewport States ---
  bool _isCameraReady = false;
  bool _isEngineReady = false;
  bool _isGpuAvailable = true;
  Cad3dEngineMode _engineMode = Cad3dEngineMode.flutterGpu;
  bool _showWireframe = true;
  bool _showDimensions = true;
  bool _isFirstLoad = true;
  bool _showModelDetails = false;

  // --- Mouse & Navigation States ---
  bool _isTurntableOrbit = true;
  bool _isPanToolActive = false;
  bool _isUserInteracting = false;
  late final ValueNotifier<(double, double)> _viewCubeNotifier;

  // --- Flutter Paint (1st Engine Software Fallback) Camera State ---
  double _paintAzimuthDeg = 45.0;
  double _paintElevationDeg = 35.264;
  double _paintZoom = 1.0;
  Offset _paintPan = Offset.zero;
  double _orbitDistance = 350.0;
  CadPoint3D _orbitTarget = const CadPoint3D(0, 0, 0);

  @override
  void initState() {
    super.initState();
    _cameraAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..addListener(_onCameraAnimationTick);

    final savedState = widget.viewModel.camera3dState;
    final initialAzDeg = (savedState != null && savedState.isInitialized) ? savedState.azimuthDeg : 45.0;
    final initialElDeg = (savedState != null && savedState.isInitialized) ? savedState.elevationDeg : 35.264;
    _paintAzimuthDeg = initialAzDeg;
    _paintElevationDeg = initialElDeg;
    if (savedState != null && savedState.isInitialized) {
      _paintZoom = savedState.zoom;
      _paintPan = savedState.pan;
      _orbitDistance = savedState.orbitDistance;
      _orbitTarget = savedState.orbitTarget;
    }
    _viewCubeNotifier = ValueNotifier<(double, double)>((initialAzDeg, initialElDeg));
    widget.viewModel.addListener(_onViewModelChanged);
    _setupSceneGraph();
    _saveCameraStateToViewModel(widget.viewModel);
  }

  @override
  void dispose() {
    _saveCameraStateToViewModel(widget.viewModel);
    _cameraAnimationController.dispose();
    widget.viewModel.removeListener(_onViewModelChanged);
    _viewCubeNotifier.dispose();
    super.dispose();
  }

  static double _normalizeAngle(double deg) {
    var a = deg % 360.0;
    if (a < 0) a += 360.0;
    return a;
  }

  Cad3dCameraState _getCurrentCameraState() {
    return Cad3dCameraState(
      azimuthDeg: _paintAzimuthDeg,
      elevationDeg: _paintElevationDeg,
      zoom: _paintZoom,
      pan: _paintPan,
      orbitDistance: _orbitDistance,
      orbitTarget: _orbitTarget,
      isInitialized: true,
    );
  }

  Cad3dCameraState _computeFitCameraState(SheetMetalStudioViewModel vm) {
    final mesh = vm.currentMesh;
    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDist = (maxDim > 0 ? maxDim * 2.2 : 350.0).clamp(50.0, 5000.0);
    return Cad3dCameraState(
      azimuthDeg: 45.0,
      elevationDeg: 35.264,
      zoom: 1.0,
      pan: Offset.zero,
      orbitDistance: fitDist,
      orbitTarget: mesh.center,
      isInitialized: true,
    );
  }

  void _saveCameraStateToViewModel(SheetMetalStudioViewModel vm) {
    vm.camera3dState = _getCurrentCameraState();
  }

  void _applyCameraStateImmediately(Cad3dCameraState state) {
    _paintAzimuthDeg = state.azimuthDeg;
    _paintElevationDeg = state.elevationDeg;
    _paintZoom = state.zoom;
    _paintPan = state.pan;
    _orbitDistance = state.orbitDistance;
    _orbitTarget = state.orbitTarget;
    _viewCubeNotifier.value = (_paintAzimuthDeg, _paintElevationDeg);

    if (_isCameraReady && _scene != null && _isGpuAvailable) {
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    if (mounted) setState(() {});
  }

  void _animateCameraTo(Cad3dCameraState targetState, {Duration duration = const Duration(milliseconds: 380)}) {
    if (!mounted) return;
    if (_cameraAnimationController.isAnimating) {
      _cameraAnimationController.stop();
    }

    final startState = _getCurrentCameraState();
    final startAz = _normalizeAngle(startState.azimuthDeg);
    final targetAz = _normalizeAngle(targetState.azimuthDeg);
    final startEl = _normalizeAngle(startState.elevationDeg);
    final targetEl = _normalizeAngle(targetState.elevationDeg);

    var diffAz = (targetAz - startAz) % 360.0;
    if (diffAz > 180.0) diffAz -= 360.0;
    if (diffAz < -180.0) diffAz += 360.0;

    var diffEl = (targetEl - startEl) % 360.0;
    if (diffEl > 180.0) diffEl -= 360.0;
    if (diffEl < -180.0) diffEl += 360.0;

    // Check if start and target are practically identical
    if (diffAz.abs() < 0.05 &&
        diffEl.abs() < 0.05 &&
        (startState.zoom - targetState.zoom).abs() < 0.01 &&
        (startState.orbitDistance - targetState.orbitDistance).abs() < 0.5 &&
        (startState.pan - targetState.pan).distance < 0.5 &&
        (startState.orbitTarget.x - targetState.orbitTarget.x).abs() < 0.5 &&
        (startState.orbitTarget.y - targetState.orbitTarget.y).abs() < 0.5 &&
        (startState.orbitTarget.z - targetState.orbitTarget.z).abs() < 0.5) {
      _applyCameraStateImmediately(targetState);
      return;
    }

    _animStartState = startState;
    _animTargetState = targetState;
    _animShortestAzimuthDiff = diffAz;
    _animShortestElevationDiff = diffEl;

    _cameraAnimationController.duration = duration;
    _cameraAnimationController.forward(from: 0.0).then((_) {
      if (mounted) {
        _applyCameraStateImmediately(targetState);
      }
    });
  }

  void _onCameraAnimationTick() {
    if (!mounted || _animStartState == null || _animTargetState == null) return;
    final t = Curves.easeInOutCubic.transform(_cameraAnimationController.value);

    final start = _animStartState!;
    final target = _animTargetState!;

    final currentAzimuth = _normalizeAngle(start.azimuthDeg + _animShortestAzimuthDiff * t);
    final currentElevation = _normalizeAngle(start.elevationDeg + _animShortestElevationDiff * t);
    final currentZoom = ui.lerpDouble(start.zoom, target.zoom, t) ?? target.zoom;
    final currentPan = Offset.lerp(start.pan, target.pan, t) ?? target.pan;
    final currentDist = ui.lerpDouble(start.orbitDistance, target.orbitDistance, t) ?? target.orbitDistance;
    final currentTargetX = ui.lerpDouble(start.orbitTarget.x, target.orbitTarget.x, t) ?? target.orbitTarget.x;
    final currentTargetY = ui.lerpDouble(start.orbitTarget.y, target.orbitTarget.y, t) ?? target.orbitTarget.y;
    final currentTargetZ = ui.lerpDouble(start.orbitTarget.z, target.orbitTarget.z, t) ?? target.orbitTarget.z;

    _paintAzimuthDeg = currentAzimuth;
    _paintElevationDeg = currentElevation;
    _paintZoom = currentZoom;
    _paintPan = currentPan;
    _orbitDistance = currentDist;
    _orbitTarget = CadPoint3D(currentTargetX, currentTargetY, currentTargetZ);
    _viewCubeNotifier.value = (currentAzimuth, currentElevation);

    if (_isCameraReady && _scene != null && _isGpuAvailable) {
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    setState(() {});
  }

  void _restoreCameraStateFromViewModel(SheetMetalStudioViewModel targetVm, {bool animate = false}) {
    final saved = targetVm.camera3dState ?? _computeFitCameraState(targetVm);
    if (animate && mounted) {
      _animateCameraTo(saved);
    } else {
      _applyCameraStateImmediately(saved);
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    if (_isEngineReady && _engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
      _rebuildCadMesh(preserveCamera: true);
    } else {
      setState(() {});
    }
  }

  void _setupSceneGraph() {
    try {
      _scene = Scene();
    } catch (_) {
      // Graceful fallback to pure software Flutter Paint engine on headless tests or non-Impeller hosts
      _isGpuAvailable = false;
      _engineMode = Cad3dEngineMode.flutterPaint;
      setState(() => _isEngineReady = true);
      return;
    }

    final scene = _scene!;
    final prefs = widget.viewModel.graphicsPreferences;
    final savedState = widget.viewModel.camera3dState;
    if (savedState != null && savedState.isInitialized) {
      _orbitDistance = savedState.orbitDistance;
      _orbitTarget = savedState.orbitTarget;
      _paintAzimuthDeg = savedState.azimuthDeg;
      _paintElevationDeg = savedState.elevationDeg;
      _paintZoom = savedState.zoom;
      _paintPan = savedState.pan;
    }

    // 1. Camera & Orbit Controller Setup
    _cameraNode = Node(name: 'MainCamera');
    _cameraComponent = CameraComponent(
      projection: widget.viewModel.isOrthoProjection
          ? OrthographicProjection(zoom: 1.0, near: 1.0, far: 10000.0)
          : PerspectiveProjection(
              fovRadiansY: (prefs.fieldOfView * vm.degrees2Radians).clamp(15.0 * vm.degrees2Radians, 90.0 * vm.degrees2Radians),
              near: 1.0,
              far: 10000.0,
            ),
      activateOnMount: true,
    );

    _cameraNode.addComponent(_cameraComponent);
    scene.add(_cameraNode);
    _isCameraReady = true;
    _updateGpuCamera();
    _saveCameraStateToViewModel(widget.viewModel);

    // 2. Studio Lighting & High-End Post-Processing Pipeline
    _applyEnvironmentSettings();

    // 3. Initialize Engine Static Resources (Shaders & Materials)
    Scene.initializeStaticResources().then((_) async {
      if (!mounted) return;
      try {
        _masterShaderMaterial = await loadFmatMaterial('assets/materials/master_materials.fmat');
      } catch (e) {
        debugPrint('FlutterSceneViewport: master_materials.fmat fallback: $e');
      }
      final hasSavedCamera = widget.viewModel.camera3dState?.isInitialized == true;
      _rebuildCadMesh(preserveCamera: hasSavedCamera);
      if (mounted) setState(() => _isEngineReady = true);
    });
  }

  void _applyEnvironmentSettings() {
    if (_scene == null || !_isGpuAvailable) return;
    final prefs = widget.viewModel.graphicsPreferences;
    final aoRatio = (prefs.ambientOcclusion / 100.0).clamp(0.0, 1.0);

    _scene!.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.aces,
      exposure: 1.0,
      bloomEnabled: false,
      ambientOcclusionEnabled: aoRatio > 0.05,
      ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
      ambientOcclusionIntensity: aoRatio,
      screenSpaceReflectionsEnabled: true,
      screenSpaceReflectionsIntensity: 0.40,
    );

    final azRad = prefs.lightAzimuthDeg * vm.degrees2Radians;
    final elRad = prefs.lightElevationDeg * vm.degrees2Radians;
    final lx = -math.cos(elRad) * math.sin(azRad);
    final ly = -math.cos(elRad) * math.cos(azRad);
    final lz = -math.sin(elRad);

    _scene!.directionalLight = DirectionalLight(
      direction: vm.Vector3(lx, ly, lz).normalized(),
      intensity: (prefs.keyLightIntensity).clamp(0.5, 3.5),
      castsShadow: false,
    );

    if (_isCameraReady && !widget.viewModel.isOrthoProjection) {
      _cameraComponent.projection = PerspectiveProjection(
        fovRadiansY: (prefs.fieldOfView * vm.degrees2Radians).clamp(15.0 * vm.degrees2Radians, 90.0 * vm.degrees2Radians),
        near: 1.0,
        far: 10000.0,
      );
    }
  }

  @override
  void didUpdateWidget(covariant FlutterSceneViewportWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel != oldWidget.viewModel) {
      if (_cameraAnimationController.isAnimating) {
        _cameraAnimationController.stop();
      }
      _saveCameraStateToViewModel(oldWidget.viewModel);
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);

      // Rebuild 3D mesh for the new tab's drawing while holding current camera view
      if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
        _rebuildCadMesh(preserveCamera: true);
      } else {
        setState(() {});
      }

      // Smoothly glide camera from outgoing tab position to restored destination position
      _restoreCameraStateFromViewModel(widget.viewModel, animate: true);
    } else if (widget.viewModel.currentMesh != oldWidget.viewModel.currentMesh) {
      if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
        _rebuildCadMesh(preserveCamera: true);
      }
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    widget.viewModel.recomputeMesh();
    if (_isEngineReady && _engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
      _rebuildCadMesh(preserveCamera: true);
    }
  }

  void _rebuildCadMesh({bool preserveCamera = true}) {
    if (_scene == null || !_isGpuAvailable) {
      if (mounted) setState(() {});
      return;
    }

    if (_cadModelNode != null) {
      _scene!.remove(_cadModelNode!);
      _cadModelNode = null;
    }

    final mesh = widget.viewModel.currentMesh;
    if (mesh.polygons.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    // Bind active PBR & Voronoi uniforms to procedural shader
    final matSettings = widget.viewModel.graphicsPreferences.materialSettings;
    if (_masterShaderMaterial != null) {
      _masterShaderMaterial!.parameters.setVec4(
        'baseColorFactor',
        matSettings.toLinearRgbVector4(),
      );
      _masterShaderMaterial!.parameters.setFloat('roughnessFactor', matSettings.roughness);
      _masterShaderMaterial!.parameters.setFloat('isPlastic', matSettings.isPlastic ? 1.0 : 0.0);
      _masterShaderMaterial!.parameters.setFloat('materialMode', matSettings.useSpangles ? 1.0 : 0.0);
      _masterShaderMaterial!.parameters.setFloat('spangleScale', matSettings.spangleScale);
    }

    _cadModelNode = FlutterSceneCadMeshBuilder.buildCadModel(
      mesh,
      selectedFaceId: widget.viewModel.selectedFaceId,
      hoveredFaceId: widget.viewModel.hoveredFaceId,
      showWireframe: _showWireframe && widget.viewModel.showBorderLines,
      customMaterial: _masterShaderMaterial,
      preferences: widget.viewModel.graphicsPreferences,
      renderMode: widget.viewModel.onshapeRenderMode,
    );
    _scene!.add(_cadModelNode!);

    // Frame camera on initial mesh load or bounds reset
    if (!preserveCamera || _isFirstLoad) {
      _zoomToFit();
      _isFirstLoad = false;
    } else if (mounted) {
      setState(() {});
    }
  }

  // --- Camera Operations (Synchronized between both engines) ---

  void _zoomToFit({bool animate = true}) {
    final targetState = _computeFitCameraState(widget.viewModel);
    if (animate && mounted) {
      _animateCameraTo(targetState, duration: const Duration(milliseconds: 350));
    } else {
      _applyCameraStateImmediately(targetState);
    }
  }

  void _updateGpuCamera() {
    if (!_isCameraReady || _scene == null || !_isGpuAvailable) return;

    final azRad = _paintAzimuthDeg * vm.degrees2Radians;
    final elRad = _paintElevationDeg * vm.degrees2Radians;

    final d = vm.Vector3(
      -math.sin(azRad) * math.cos(elRad),
      math.sin(elRad),
      -math.cos(azRad) * math.cos(elRad),
    );

    final pivot = widget.viewModel.currentMesh.center;
    final target = vm.Vector3(
      _orbitTarget.x - pivot.x,
      _orbitTarget.y - pivot.y,
      _orbitTarget.z - pivot.z,
    );
    final eye = target + d * _orbitDistance;
    final up = vm.Vector3(
      math.sin(azRad) * math.sin(elRad),
      math.cos(elRad),
      math.cos(azRad) * math.sin(elRad),
    );

    _cameraNode.lookAtFrom(eye, target, up: up);
  }

  void _setCameraFromAngles(double azimuthDeg, double elevationDeg, {bool animate = true}) {
    final targetState = Cad3dCameraState(
      azimuthDeg: _normalizeAngle(azimuthDeg),
      elevationDeg: _normalizeAngle(elevationDeg),
      zoom: _paintZoom,
      pan: _paintPan,
      orbitDistance: _orbitDistance,
      orbitTarget: _orbitTarget,
      isInitialized: true,
    );

    if (animate && mounted) {
      _animateCameraTo(targetState, duration: const Duration(milliseconds: 320));
    } else {
      _applyCameraStateImmediately(targetState);
    }
  }

  void _orbitCamera(double dAzimuth, double dElevation) {
    if (_cameraAnimationController.isAnimating) {
      _cameraAnimationController.stop();
    }
    _paintAzimuthDeg = _normalizeAngle(_paintAzimuthDeg + dAzimuth);
    _paintElevationDeg = _normalizeAngle(_paintElevationDeg + dElevation);
    _viewCubeNotifier.value = (_paintAzimuthDeg, _paintElevationDeg);

    if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable && _isCameraReady && _scene != null) {
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    if (mounted) setState(() {});
  }

  void _panCamera(Offset delta, Size size) {
    if (_cameraAnimationController.isAnimating) {
      _cameraAnimationController.stop();
    }
    _paintPan += delta;

    final azRad = _paintAzimuthDeg * vm.degrees2Radians;
    final elRad = _paintElevationDeg * vm.degrees2Radians;

    final right = vm.Vector3(math.cos(azRad), 0.0, -math.sin(azRad));
    final up = vm.Vector3(
      math.sin(azRad) * math.sin(elRad),
      math.cos(elRad),
      math.cos(azRad) * math.sin(elRad),
    );

    final vpHeight = size.height > 0 ? size.height : 600.0;
    final k = (_orbitDistance * 0.85) / vpHeight;

    // Moving mouse right (dx > 0) moves model right, so camera target shifts left (-right)
    // Moving mouse down (dy > 0) moves model down, so camera target shifts up (+up)
    final shift = (right * (-delta.dx * k)) + (up * (delta.dy * k));

    _orbitTarget = CadPoint3D(
      _orbitTarget.x + shift.x,
      _orbitTarget.y + shift.y,
      _orbitTarget.z + shift.z,
    );

    if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable && _isCameraReady && _scene != null) {
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    if (mounted) setState(() {});
  }

  void _zoomCamera(double factor) {
    if (_cameraAnimationController.isAnimating) {
      _cameraAnimationController.stop();
    }
    _paintZoom = (_paintZoom * factor).clamp(0.1, 25.0);
    _orbitDistance = (_orbitDistance / factor).clamp(10.0, 5000.0);

    if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable && _isCameraReady && _scene != null) {
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    if (mounted) setState(() {});
  }

  void _toggleProjection() {
    widget.viewModel.toggleOrthoProjection();
    if (_scene != null && _isGpuAvailable && _isCameraReady) {
      final isOrtho = widget.viewModel.isOrthoProjection;
      final prefs = widget.viewModel.graphicsPreferences;
      _cameraComponent.projection = isOrtho
          ? OrthographicProjection(zoom: 1.0, near: 1.0, far: 10000.0)
          : PerspectiveProjection(
              fovRadiansY: (prefs.fieldOfView * vm.degrees2Radians).clamp(15.0 * vm.degrees2Radians, 90.0 * vm.degrees2Radians),
              near: 1.0,
              far: 10000.0,
            );
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    if (mounted) setState(() {});
  }

  // --- Screen-Space Projection Math (Dual-Engine Unified) ---

  Offset projectPointToScreenPaint(CadPoint3D p, Size size) {
    if (size.width <= 0 || size.height <= 0) return Offset.zero;
    final mesh = widget.viewModel.currentMesh;
    final cx = size.width / 2.0 + _paintPan.dx;
    final cy = size.height / 2.0 + _paintPan.dy;

    final azRad = _paintAzimuthDeg * vm.degrees2Radians;
    final elRad = _paintElevationDeg * vm.degrees2Radians;

    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * _paintZoom;

    final pivot = mesh.center;
    final cameraDist = math.max(fitDim * 2.5, 1000.0);

    final rx = p.x - pivot.x;
    final ry = p.y - pivot.y;
    final rz = p.z - pivot.z;

    final x2 = rx * cosAz + ry * sinAz;
    final y2 = -rx * sinEl * sinAz + ry * sinEl * cosAz + rz * cosEl;
    final z2 = rx * cosEl * sinAz - ry * cosEl * cosAz + rz * sinEl;

    final isOrtho = widget.viewModel.isOrthoProjection;
    final persp = isOrtho ? 1.0 : (cameraDist / math.max(cameraDist - z2, cameraDist * 0.15));

    final sx = cx + (x2 * persp) * scale;
    final sy = cy - (y2 * persp) * scale;

    return Offset(sx, sy);
  }

  Offset projectPointToScreenGpu(CadPoint3D p, Size viewportSize) {
    if (!_isCameraReady || viewportSize.width <= 0 || viewportSize.height <= 0) {
      return projectPointToScreenPaint(p, viewportSize);
    }

    final pivot = widget.viewModel.currentMesh.center;
    final localPt = vm.Vector4(p.x - pivot.x, p.y - pivot.y, p.z - pivot.z, 1.0);

    final camera = _cameraComponent.toCamera();
    final viewMatrix = camera.getViewMatrix();
    final aspect = viewportSize.width / viewportSize.height;
    final projMatrix = _cameraComponent.projection.getProjectionMatrix(aspect);

    final vpMatrix = projMatrix * viewMatrix;
    final clip = vpMatrix.transform(localPt);

    if (clip.w.abs() < 1e-6) return Offset.zero;

    final ndcX = clip.x / clip.w;
    final ndcY = clip.y / clip.w;

    final sx = (ndcX + 1.0) * 0.5 * viewportSize.width;
    final sy = (1.0 - ndcY) * 0.5 * viewportSize.height;

    return Offset(sx, sy);
  }

  /// Projects a 3D CAD vertex into logical 2D viewport coordinates for dimensions, tags, & annotations.
  Offset projectPointToScreen(CadPoint3D p, Size size) {
    if (_engineMode == Cad3dEngineMode.flutterPaint || !_isGpuAvailable || _scene == null) {
      return projectPointToScreenPaint(p, size);
    }
    return projectPointToScreenGpu(p, size);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEngineReady) {
      return Container(
        color: const Color(0xFF0F172A),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF38BDF8))),
              SizedBox(height: 12),
              Text('Starting TruFold 3D CAD Viewport...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ],
          ),
        ),
      );
    }

    final mesh = widget.viewModel.currentMesh;
    final isPaintMode = (_engineMode == Cad3dEngineMode.flutterPaint || !_isGpuAvailable || _scene == null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            // =================================================================
            // 1. PRIMARY VIEWPORT LAYER (Flutter GPU vs Flutter Paint)
            // =================================================================
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => setState(() => _isUserInteracting = true),
                onPointerUp: (_) => setState(() => _isUserInteracting = false),
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _zoomCamera(event.scrollDelta.dy < 0 ? 1.15 : 0.85);
                  }
                },
                onPointerMove: (event) {
                  if (widget.isInteractionLocked) return;

                  final isPrimary = (event.buttons & kPrimaryMouseButton) != 0;
                  final isMiddle = (event.buttons & kTertiaryButton) != 0 || (event.buttons & kMiddleMouseButton) != 0;
                  final isSecondary = (event.buttons & kSecondaryMouseButton) != 0;
                  bool isShiftPressed = false;
                  try {
                    isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                  } catch (_) {}

                  if (isMiddle || (isPrimary && (_isPanToolActive || isShiftPressed))) {
                    // Panning (Middle Drag / Shift+Left / Pan Tool)
                    _panCamera(event.delta, size);
                  } else if (isSecondary || isPrimary) {
                    // Orbiting (Right Mouse Button or Primary Left Mouse Button Drag)
                    _orbitCamera(event.delta.dx * 0.5, -event.delta.dy * 0.5);
                  }
                },
                child: isPaintMode
                    // --- 1st Generation: Pure Flutter Paint Canvas ---
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.isInteractionLocked ? null : () => widget.viewModel.clearSelection(),
                        onDoubleTap: _zoomToFit,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: FlutterPaint3dPainter(
                              mesh: mesh,
                              azimuthDeg: _paintAzimuthDeg,
                              elevationDeg: _paintElevationDeg,
                              zoom: _paintZoom,
                              pan: _paintPan,
                              showWireframe: _showWireframe && widget.viewModel.showBorderLines,
                              isGlassMode: widget.viewModel.isGlassMode,
                              isOrthoProjection: widget.viewModel.isOrthoProjection,
                              isInteracting: _isUserInteracting,
                              selectedBendId: widget.viewModel.selectedBendId,
                              selectedPunchId: widget.viewModel.selectedPunchId,
                              selectedFaceId: widget.viewModel.selectedFaceId,
                              hoveredPunchId: widget.viewModel.hoveredPunchId,
                              hoveredBendId: widget.viewModel.hoveredBendId,
                              hoveredFaceId: widget.viewModel.hoveredFaceId,
                              activePorts: widget.viewModel.activeCmsPorts,
                              focusedPortId: widget.viewModel.cmsGuidedController.state.focus.activePortId,
                            ),
                          ),
                        ),
                      )
                    // --- Next Generation: Flutter GPU SceneView ---
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: _zoomToFit,
                        child: SceneView(_scene!),
                      ),
              ),
            ),

            // =================================================================
            // 2. DIMENSION WITNESS LINES & ANNOTATIONS OVERLAY
            // =================================================================
            if (_showDimensions && mesh.polygons.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _Cad3dDimensionsPainter(mesh: mesh, viewModel: widget.viewModel, project: (p) => projectPointToScreen(p, size)),
                  ),
                ),
              ),

            // =================================================================
            // 3. SYNCHRONIZED EXTERNAL OVERLAY (TDS / DDS Paper Canvas)
            // =================================================================
            if (widget.overlayBuilder != null)
              Positioned.fill(child: IgnorePointer(child: widget.overlayBuilder!(context, size, (p) => projectPointToScreen(p, size)))),

            // =================================================================
            // 4. TOP HEADER BAR: Status, Cover, Engine Switcher & Details
            // =================================================================
            Positioned(
              top: 12,
              left: 12,
              right: 155, // Clears the 3D ViewCube
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.view_in_ar, size: 15, color: Color(0xFF0284C7)),
                            const SizedBox(width: 6),
                            const Text(
                              '3D FOLDED MESH',
                              style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),

                            // Cover Visibility Toggle (if applicable)
                            if (widget.viewModel.hasCover) ...[
                              const SizedBox(width: 8),
                              Container(width: 1, height: 14, color: const Color(0xFFCBD5E1)),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: widget.viewModel.isCoverVisible3D ? 'Hide Cover (3D)' : 'Show Cover (3D)',
                                child: InkWell(
                                  onTap: widget.viewModel.toggleCoverVisibility3D,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          widget.viewModel.isCoverVisible3D ? Icons.layers : Icons.layers_clear,
                                          size: 13,
                                          color: widget.viewModel.isCoverVisible3D ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Cover: ${widget.viewModel.isCoverVisible3D ? "ON" : "OFF"}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: widget.viewModel.isCoverVisible3D ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(width: 8),
                            Container(width: 1, height: 14, color: const Color(0xFFCBD5E1)),
                            const SizedBox(width: 8),

                            // Engine Mode Switcher (Flutter GPU vs Flutter Paint)
                            Tooltip(
                              message: 'Switch 3D Engine: Flutter GPU (120 FPS PBR) vs Flutter Paint (Canvas 2.5D Backup View)',
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                                      _engineMode = Cad3dEngineMode.flutterPaint;
                                    } else if (_isGpuAvailable) {
                                      _engineMode = Cad3dEngineMode.flutterGpu;
                                      _rebuildCadMesh(preserveCamera: true);
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: _engineMode == Cad3dEngineMode.flutterGpu
                                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                        : const Color(0xFF0284C7).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: _engineMode == Cad3dEngineMode.flutterGpu ? const Color(0xFF10B981) : const Color(0xFF0284C7)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _engineMode == Cad3dEngineMode.flutterGpu ? Icons.speed : Icons.brush,
                                        size: 12,
                                        color: _engineMode == Cad3dEngineMode.flutterGpu ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _engineMode == Cad3dEngineMode.flutterGpu ? 'Engine: GPU (120 FPS)' : 'Engine: Paint (2D Canvas)',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: _engineMode == Cad3dEngineMode.flutterGpu ? const Color(0xFF059669) : const Color(0xFF0284C7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),
                            Container(width: 1, height: 14, color: const Color(0xFFCBD5E1)),
                            const SizedBox(width: 8),

                            // Model Details Toggle Chip
                            Tooltip(
                              message: 'Inspect 3D Model Parameters & Diagnostics',
                              child: InkWell(
                                onTap: () => setState(() => _showModelDetails = !_showModelDetails),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _showModelDetails ? Icons.info : Icons.info_outline,
                                        size: 13,
                                        color: _showModelDetails ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Details',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _showModelDetails ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),
                            Container(width: 1, height: 14, color: const Color(0xFFCBD5E1)),
                            const SizedBox(width: 8),

                            // 3D Dimensions Toggle Chip
                            Tooltip(
                              message: _showDimensions ? 'Hide 3D Dimension Witness Lines' : 'Show 3D Dimension Witness Lines',
                              child: InkWell(
                                onTap: () => setState(() => _showDimensions = !_showDimensions),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _showDimensions ? Icons.straighten : Icons.square_foot,
                                        size: 13,
                                        color: _showDimensions ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Dims: ${_showDimensions ? "ON" : "OFF"}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _showDimensions ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // =================================================================
            // 5. FLOATING INDUSTRIAL CAD 3D NAVIGATION BAR
            // =================================================================
            Positioned(
              top: 56,
              left: 12,
              child: Studio3dNavigationBar(
                onFitAll: _zoomToFit,
                onSelectView: (az, el) => _setCameraFromAngles(az, el),
                isTurntable: _isTurntableOrbit,
                onToggleOrbitMode: () {
                  setState(() => _isTurntableOrbit = !_isTurntableOrbit);
                },
                isPanToolActive: _isPanToolActive,
                onTogglePanTool: () {
                  setState(() => _isPanToolActive = !_isPanToolActive);
                },
                isOrtho: widget.viewModel.isOrthoProjection,
                onToggleProjection: _toggleProjection,
                showBorderLines: _showWireframe && widget.viewModel.showBorderLines,
                onToggleBorderLines: () {
                  setState(() {
                    _showWireframe = !_showWireframe;
                    widget.viewModel.toggleBorderLines();
                    if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                      _rebuildCadMesh(preserveCamera: true);
                    }
                  });
                },
                isObstructedXRay: widget.viewModel.isObstructedXRayMode,
                onToggleObstructedXRay: () {
                  widget.viewModel.toggleObstructedXRayMode();
                  if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                    _rebuildCadMesh(preserveCamera: true);
                  }
                  setState(() {});
                },
                currentShadingStyle: widget.viewModel.cadShadingStyle,
                onShadingStyleChanged: (style) {
                  widget.viewModel.cadShadingStyle = style;
                  if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                    _rebuildCadMesh(preserveCamera: true);
                  }
                  setState(() {});
                },
                currentAntiAliasing: widget.viewModel.antiAliasingQuality,
                onAntiAliasingChanged: (aa) {
                  widget.viewModel.antiAliasingQuality = aa;
                  _applyEnvironmentSettings();
                  setState(() {});
                },
              ),
            ),

            // =================================================================
            // 6. FLOATING MODEL DETAILS & DIAGNOSTICS CARD
            // =================================================================
            if (_showModelDetails)
              Positioned(
                top: 56,
                left: 58,
                child: Container(
                  width: 260,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'CAD MODEL DETAILS',
                            style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                          ),
                          InkWell(
                            onTap: () => setState(() => _showModelDetails = false),
                            child: const Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow('Item Name', widget.viewModel.document.itemName),
                      _buildDetailRow('Product Type', widget.viewModel.document.productType),
                      _buildDetailRow('Material Thickness', '${widget.viewModel.document.material.thicknessMm.toStringAsFixed(2)} mm'),
                      _buildDetailRow('Fold State', '${(widget.viewModel.foldProgress * 100).round()}% Folded'),
                      _buildDetailRow('3D Polygons', '${mesh.polygons.length} faces'),
                      _buildDetailRow('Bend Lines', '${widget.viewModel.document.bends.length} bends'),
                      _buildDetailRow(
                        'Bounding Envelope',
                        '${toNominalSize(mesh.boundWidth).toStringAsFixed(0)} × ${toNominalSize(mesh.boundLength).toStringAsFixed(0)} × ${toNominalSize(mesh.boundHeight).toStringAsFixed(0)} mm',
                      ),
                    ],
                  ),
                ),
              ),

            // =================================================================
            // 7. FLOATING GRAPHICS PREFERENCES PANEL
            // =================================================================
            if (widget.viewModel.isGraphicsPreferencesOpen)
              Positioned(
                top: 56,
                right: 146,
                child: StudioGraphicsPreferencesPanel(
                  preferences: widget.viewModel.graphicsPreferences,
                  onChanged: (prefs) {
                    widget.viewModel.graphicsPreferences = prefs;
                    _applyEnvironmentSettings();
                    if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                      _rebuildCadMesh(preserveCamera: true);
                    }
                    setState(() {});
                  },
                  onClose: () {
                    setState(() {
                      widget.viewModel.isGraphicsPreferencesOpen = false;
                    });
                  },
                  onResetToDefault: () {
                    widget.viewModel.graphicsPreferences = const OnshapeGraphicsPreferences();
                    _applyEnvironmentSettings();
                    if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                      _rebuildCadMesh(preserveCamera: true);
                    }
                    setState(() {});
                  },
                ),
              ),

            // =================================================================
            // 8. INTERACTIVE 3D VIEWCUBE (Top-Right Orientation Navigator)
            // =================================================================
            Positioned(
              top: 12,
              right: 12,
              child: ValueListenableBuilder<(double, double)>(
                valueListenable: _viewCubeNotifier,
                builder: (context, angles, _) {
                  return StudioViewCube(
                    azimuthDeg: angles.$1,
                    elevationDeg: angles.$2,
                    renderMode: widget.viewModel.onshapeRenderMode,
                    onRenderModeChanged: (mode) {
                      widget.viewModel.onshapeRenderMode = mode;
                      if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                    },
                    hiddenEdgesVisible: widget.viewModel.showBorderLines,
                    onToggleHiddenEdges: (val) {
                      widget.viewModel.toggleBorderLines();
                      if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                    },
                    tangentEdgeMode: widget.viewModel.graphicsPreferences.tangentEdgeMode,
                    onTangentEdgeModeChanged: (mode) {
                      widget.viewModel.updateGraphicsPreferences((p) => p.copyWith(tangentEdgeMode: mode));
                      if (_engineMode == Cad3dEngineMode.flutterGpu && _isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                    },
                    isPerspective: !widget.viewModel.isOrthoProjection,
                    onTogglePerspective: _toggleProjection,
                    onOpenGraphicsPreferences: () {
                      setState(() {
                        widget.viewModel.isGraphicsPreferencesOpen = true;
                      });
                    },
                    onRollCw: () => _orbitCamera(15.0, 0.0),
                    onRollCcw: () => _orbitCamera(-15.0, 0.0),
                    onResetView: () {
                      _setCameraFromAngles(45.0, 35.264);
                      _zoomToFit();
                    },
                    onOrbit: (dAz, dEl) => _orbitCamera(dAz, dEl),
                    onSetView: (azimuth, elevation) => _setCameraFromAngles(azimuth, elevation),
                    onZoomToFit: _zoomToFit,
                  );
                },
              ),
            ),

            // =================================================================
            // 9. BOTTOM-RIGHT LIVE BOUNDING DIMENSIONS BADGE
            // =================================================================
            if (mesh.polygons.isNotEmpty)
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF334155)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Text(
                    '3D Bounding: ${toNominalSize(mesh.boundWidth).toStringAsFixed(0)} × ${toNominalSize(mesh.boundLength).toStringAsFixed(0)} × ${toNominalSize(mesh.boundHeight).toStringAsFixed(0)} mm',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 0.3),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
          Text(
            value,
            style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

/// Zero-drift 3D dimension witness lines and feature annotations overlay painter.
class _Cad3dDimensionsPainter extends CustomPainter {
  final FoldedMeshResult mesh;
  final SheetMetalStudioViewModel viewModel;
  final Offset Function(CadPoint3D p) project;

  _Cad3dDimensionsPainter({required this.mesh, required this.viewModel, required this.project});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || mesh.polygons.isEmpty) return;

    // Calculate tight 3D bounding box from actual vertices of all polygons
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    for (final poly in mesh.allPolygons) {
      for (final v in poly.vertices) {
        if (v.x < minX) minX = v.x;
        if (v.x > maxX) maxX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.y > maxY) maxY = v.y;
        if (v.z < minZ) minZ = v.z;
        if (v.z > maxZ) maxZ = v.z;
      }
    }

    if (!minX.isFinite || !maxX.isFinite) return;

    final actualW = maxX - minX;
    final actualL = maxY - minY;
    final actualH = maxZ - minZ;

    final nominalW = toNominalSize(actualW);
    final nominalL = toNominalSize(actualL);
    final nominalH = toNominalSize(actualH);

    // 1. Width Dimension Witness Line (along X axis at bottom front of the actual part)
    final pWidth1 = project(CadPoint3D(minX, minY, minZ));
    final pWidth2 = project(CadPoint3D(maxX, minY, minZ));
    _drawDimensionLine(canvas, pWidth1, pWidth2, label: 'W: ${nominalW.round()} mm', badgeColor: const Color(0xFF0284C7));

    // 2. Length Dimension Witness Line (along Y axis at bottom right of the actual part)
    final pLength1 = project(CadPoint3D(maxX, minY, minZ));
    final pLength2 = project(CadPoint3D(maxX, maxY, minZ));
    _drawDimensionLine(canvas, pLength1, pLength2, label: 'L: ${nominalL.round()} mm', badgeColor: const Color(0xFF0D9488));

    // 3. Height Dimension Witness Line (along Z axis vertically at front corner)
    if (actualH > 3.0) {
      final pHeight1 = project(CadPoint3D(maxX, minY, minZ));
      final pHeight2 = project(CadPoint3D(maxX, minY, maxZ));
      _drawDimensionLine(canvas, pHeight1, pHeight2, label: 'H: ${nominalH.round()} mm', badgeColor: const Color(0xFF6366F1));
    }

    // 4. Coupler Holes Callout
    final couplerPunches = viewModel.document.punches.where((p) => p.role == CncPunchRole.coupler || p.id.toLowerCase().contains('coupler')).toList();
    if (couplerPunches.isNotEmpty) {
      final cCenters = <CadPoint3D>[];
      for (final p in couplerPunches) {
        final p3d = mesh.punchCenters3D[p.id];
        if (p3d != null) {
          cCenters.add(p3d);
        }
      }
      if (cCenters.isNotEmpty) {
        double avgX = 0, avgY = 0, avgZ = 0;
        for (final c in cCenters) {
          avgX += c.x;
          avgY += c.y;
          avgZ += c.z;
        }
        final center3D = CadPoint3D(avgX / cCenters.length, avgY / cCenters.length, avgZ / cCenters.length);
        final screenPos = project(center3D);
        if (screenPos.dx >= 0 && screenPos.dx <= size.width && screenPos.dy >= 0 && screenPos.dy <= size.height) {
          _drawPillBadge(canvas, screenPos, 'COUPLER HOLES: ${cCenters.length}× SLOTS', const Color(0xFFD97706));
        }
      }
    }

    // 5. Cable Ladder Rungs Callout (if ladder)
    final rungFaces = mesh.allPolygons.where((p) => p.faceId.toLowerCase().contains('rung')).toList();
    if (rungFaces.isNotEmpty) {
      final midFace = rungFaces[rungFaces.length ~/ 2];
      if (midFace.vertices.isNotEmpty) {
        double rx = 0, ry = 0, rz = 0;
        for (final v in midFace.vertices) {
          rx += v.x;
          ry += v.y;
          rz += v.z;
        }
        final rungCentroid = CadPoint3D(rx / midFace.vertices.length, ry / midFace.vertices.length, rz / midFace.vertices.length);
        final screenPos = project(rungCentroid);
        if (screenPos.dx >= 0 && screenPos.dx <= size.width && screenPos.dy >= 0 && screenPos.dy <= size.height) {
          _drawPillBadge(canvas, screenPos, 'RUNGS: ${rungFaces.length} RUNGS', const Color(0xFF9333EA));
        }
      }
    }

    // 6. Flange Side Callout
    if (actualH > 8.0) {
      final flangeFaces = mesh.allPolygons
          .where((p) => p.faceId.toLowerCase().contains('side') || p.faceId.toLowerCase().contains('flange') || p.faceId.toLowerCase().contains('wing'))
          .toList();
      if (flangeFaces.isNotEmpty) {
        final f = flangeFaces.first;
        if (f.vertices.isNotEmpty) {
          double fx = 0, fy = 0, fz = 0;
          for (final v in f.vertices) {
            fx += v.x;
            fy += v.y;
            fz += v.z;
          }
          final flangeCentroid = CadPoint3D(fx / f.vertices.length, fy / f.vertices.length, fz / f.vertices.length);
          final screenPos = project(flangeCentroid);
          if (screenPos.dx >= 0 && screenPos.dx <= size.width && screenPos.dy >= 0 && screenPos.dy <= size.height) {
            _drawPillBadge(canvas, screenPos, 'FLANGE SIDE: ${nominalH.round()} mm', const Color(0xFF2563EB));
          }
        }
      }
    }
  }

  void _drawDimensionLine(Canvas canvas, Offset p1, Offset p2, {required String label, required Color badgeColor}) {
    if ((p1 - p2).distance < 12.0) return;

    final linePaint = Paint()
      ..color = badgeColor.withValues(alpha: 0.65)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(p1, p2, linePaint);

    final mid = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);
    _drawPillBadge(canvas, mid, label, badgeColor);
  }

  void _drawPillBadge(Canvas canvas, Offset center, String text, Color color) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
    );
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();

    final pillW = textPainter.width + 12.0;
    final pillH = textPainter.height + 6.0;
    final rect = Rect.fromCenter(center: center, width: pillW, height: pillH);

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2.0, center.dy - textPainter.height / 2.0));
  }

  @override
  bool shouldRepaint(covariant _Cad3dDimensionsPainter oldDelegate) => true;
}
