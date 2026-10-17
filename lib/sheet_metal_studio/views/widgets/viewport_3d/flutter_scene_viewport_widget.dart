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
import '../../../engine/trufold_3d_engine_preloader.dart';
import '../../../engine/matrix4_math_helper.dart';
import '../../../models/cad_primitives.dart';
import '../../../models/cms/cms_physical_port.dart';
import '../../../models/cnc_punch_primitive.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../studio/studio_3d_navigation_bar.dart';
import '../studio/studio_graphics_preferences_panel.dart';
import '../studio/studio_view_cube.dart';

/// Next-Generation 3D CAD Viewport powered by Flutter GPU (flutter_scene Impeller).
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
  bool _showWireframe = true;
  bool _showDimensions = true;
  bool _isFirstLoad = true;
  bool _showModelDetails = false;

  // --- Mouse & Navigation States ---
  bool _isTurntableOrbit = false; // Default: 360° Free Virtual Globe Trackball
  bool _isPanToolActive = false;
  late final ValueNotifier<(double, double)> _viewCubeNotifier;

  // --- 360° Virtual Globe / Arcball & Model Transform State ---
  late TransformMatrix4 _modelTransform;
  CadPoint3D? _lastSphereVector;
  Offset? _dragStartPos;
  Offset? _currentDragPos;
  bool _isRotatingModel = false;

  // --- Pinned Pivot Model Rotation State ---
  bool _isPinnedPivotMode = true; // Rotates model with opposite side pinned/anchored
  CadPoint3D? _pinnedPivotPoint;
  Offset? _pinnedScreenAnchor;
  Size? _lastKnownViewportSize;

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
    _cameraAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))..addListener(_onCameraAnimationTick);

    final savedState = widget.viewModel.camera3dState;
    final initialAzDeg = (savedState != null && savedState.isInitialized) ? savedState.azimuthDeg : 45.0;
    final initialElDeg = (savedState != null && savedState.isInitialized) ? savedState.elevationDeg : 35.264;
    _paintAzimuthDeg = initialAzDeg;
    _paintElevationDeg = initialElDeg;
    _modelTransform = _matrixFromAngles(initialAzDeg, initialElDeg);
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
    _modelTransform = _matrixFromAngles(_paintAzimuthDeg, _paintElevationDeg);
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
    _modelTransform = _matrixFromAngles(currentAzimuth, currentElevation);
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
    if (_isEngineReady && _isGpuAvailable) {
      _rebuildCadMesh(preserveCamera: true);
    } else {
      setState(() {});
    }
  }

  void _setupSceneGraph() {
    try {
      _scene = Scene();
      _isGpuAvailable = true;
    } catch (_) {
      _isGpuAvailable = false;
      setState(() => _isEngineReady = true);
      return;
    }

    final scene = _scene!;
    scene.fitNearPlane = false;
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
          ? OrthographicProjection(zoom: 1.0, near: 0.5, far: 50000.0)
          : PerspectiveProjection(
              fovRadiansY: (prefs.fieldOfView * vm.degrees2Radians).clamp(15.0 * vm.degrees2Radians, 90.0 * vm.degrees2Radians),
              near: 0.5,
              far: 50000.0,
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

    // 3. Initialize Engine Static Resources (Shaders & Materials) via Preloader
    if (TruFold3dEnginePreloader.instance.isReady) {
      _masterShaderMaterial = TruFold3dEnginePreloader.instance.cachedMasterMaterial;
      _isGpuAvailable = TruFold3dEnginePreloader.instance.isGpuAvailable;
      final hasSavedCamera = widget.viewModel.camera3dState?.isInitialized == true;
      _rebuildCadMesh(preserveCamera: hasSavedCamera);
      _isEngineReady = true;
    } else {
      TruFold3dEnginePreloader.instance.preload().then((_) async {
        if (!mounted) return;
        _masterShaderMaterial = TruFold3dEnginePreloader.instance.cachedMasterMaterial;
        _isGpuAvailable = TruFold3dEnginePreloader.instance.isGpuAvailable;
        if (_masterShaderMaterial == null && _isGpuAvailable) {
          try {
            _masterShaderMaterial = await loadFmatMaterial('assets/materials/master_materials.fmat');
            _masterShaderMaterial?.doubleSided = true;
          } catch (e) {
            debugPrint('FlutterSceneViewport: master_materials.fmat fallback: $e');
          }
        }
        final hasSavedCamera = widget.viewModel.camera3dState?.isInitialized == true;
        _rebuildCadMesh(preserveCamera: hasSavedCamera);
        if (mounted) setState(() => _isEngineReady = true);
      });
    }
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
        near: 0.5,
        far: 50000.0,
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
      if (_isGpuAvailable) {
        _rebuildCadMesh(preserveCamera: true);
      } else {
        setState(() {});
      }

      // Smoothly glide camera from outgoing tab position to restored destination position
      _restoreCameraStateFromViewModel(widget.viewModel, animate: true);
    } else if (widget.viewModel.currentMesh != oldWidget.viewModel.currentMesh) {
      if (_isGpuAvailable) {
        _rebuildCadMesh(preserveCamera: true);
      }
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    widget.viewModel.recomputeMesh();
    if (_isEngineReady && _isGpuAvailable) {
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
    PreprocessedMaterial? activeShaderMaterial;

    // Use procedural Voronoi shader specifically for HDG spangles, while using
    // double-sided PhysicallyBasedMaterial with vertex color sheet thickness for all other materials (Paint, GI, SS, etc.)
    if (matSettings.useSpangles && _masterShaderMaterial != null) {
      _masterShaderMaterial!.parameters.setVec4('baseColorFactor', matSettings.toLinearRgbVector4());
      _masterShaderMaterial!.parameters.setFloat('roughnessFactor', matSettings.roughness);
      _masterShaderMaterial!.parameters.setFloat('isPlastic', matSettings.isPlastic ? 1.0 : 0.0);
      _masterShaderMaterial!.parameters.setFloat('materialMode', 1.0);
      _masterShaderMaterial!.parameters.setFloat('spangleScale', matSettings.spangleScale);
      _masterShaderMaterial!.doubleSided = true;
      activeShaderMaterial = _masterShaderMaterial;
    }

    _cadModelNode = FlutterSceneCadMeshBuilder.buildCadModel(
      mesh,
      selectedFaceId: widget.viewModel.selectedFaceId,
      hoveredFaceId: widget.viewModel.hoveredFaceId,
      showWireframe: _showWireframe && widget.viewModel.showBorderLines,
      customMaterial: activeShaderMaterial,
      preferences: widget.viewModel.graphicsPreferences,
      renderMode: widget.viewModel.onshapeRenderMode,
      hiddenPartIds: widget.viewModel.hiddenPartIds,
      isolatedPartIds: widget.viewModel.isolatedPartIds,
      transparentPartIds: widget.viewModel.transparentPartIds,
      sectionViewConfig: widget.viewModel.sectionViewConfig,
      partColorOverrides: widget.viewModel.partColorOverrides,
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

    final m = _modelTransform.m;
    // Map CAD world coordinates to FlutterScene coordinate frame:
    // Row 2 is camera view direction in CAD (towards eye): (m[8], m[9], m[10])
    // Row 1 is camera up direction in CAD: (m[4], m[5], m[6])
    final d = vm.Vector3(-m[8], m[10], m[9]);
    final up = vm.Vector3(-m[4], m[6], m[5]);

    final pivot = widget.viewModel.currentMesh.center;
    final target = vm.Vector3(_orbitTarget.x - pivot.x, _orbitTarget.y - pivot.y, _orbitTarget.z - pivot.z);
    final eye = target + d * _orbitDistance;

    _cameraNode.lookAtFrom(eye, target, up: up);
  }

  static TransformMatrix4 _matrixFromAngles(double azDeg, double elDeg) {
    final azRad = azDeg * math.pi / 180.0;
    final elRad = elDeg * math.pi / 180.0;
    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    return TransformMatrix4.fromList([
      cosAz,
      sinAz,
      0.0,
      0.0,
      -sinEl * sinAz,
      sinEl * cosAz,
      cosEl,
      0.0,
      cosEl * sinAz,
      -cosEl * cosAz,
      sinEl,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
    ]);
  }

  void _syncCameraAnglesFromTransform() {
    final m = _modelTransform.m;
    final sinEl = m[10].clamp(-1.0, 1.0);
    final elRad = math.asin(sinEl);
    final azRad = math.atan2(m[8], -m[9]);

    _paintElevationDeg = _normalizeAngle(elRad * 180.0 / math.pi);
    _paintAzimuthDeg = _normalizeAngle(azRad * 180.0 / math.pi);
    _viewCubeNotifier.value = (_paintAzimuthDeg, _paintElevationDeg);
  }

  void _orthonormalizeModelTransform() {
    final m = _modelTransform.m;
    var r0 = CadPoint3D(m[0], m[1], m[2]).normalized();
    var r1 = CadPoint3D(m[4], m[5], m[6]);
    final dot01 = r1.x * r0.x + r1.y * r0.y + r1.z * r0.z;
    r1 = CadPoint3D(r1.x - dot01 * r0.x, r1.y - dot01 * r0.y, r1.z - dot01 * r0.z).normalized();
    final r2 = CadPoint3D(r0.y * r1.z - r0.z * r1.y, r0.z * r1.x - r0.x * r1.z, r0.x * r1.y - r0.y * r1.x).normalized();

    _modelTransform = TransformMatrix4.fromList([r0.x, r0.y, r0.z, 0.0, r1.x, r1.y, r1.z, 0.0, r2.x, r2.y, r2.z, 0.0, 0.0, 0.0, 0.0, 1.0]);
  }

  Offset _projectOffsetFromCenter(CadPoint3D p, Size size) {
    if (size.width <= 0 || size.height <= 0) return Offset.zero;
    final mesh = widget.viewModel.currentMesh;
    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * _paintZoom;

    final pivot = mesh.center;
    final cameraDist = math.max(fitDim * 2.5, 1000.0);

    final rx = p.x - pivot.x;
    final ry = p.y - pivot.y;
    final rz = p.z - pivot.z;

    final m = _modelTransform.m;
    final x2 = rx * m[0] + ry * m[1] + rz * m[2];
    final y2 = rx * m[4] + ry * m[5] + rz * m[6];
    final z2 = rx * m[8] + ry * m[9] + rz * m[10];

    final isOrtho = widget.viewModel.isOrthoProjection;
    final persp = isOrtho ? 1.0 : (cameraDist / math.max(cameraDist - z2, cameraDist * 0.15));

    final ux = (x2 * persp) * scale;
    final uy = -(y2 * persp) * scale;

    return Offset(ux, uy);
  }

  CadPoint3D? _computeOppositePinnedPivot(Offset cursorLocalPos, Size size, FoldedMeshResult mesh) {
    if (mesh.polygons.isEmpty) return null;

    final poly = _findFrontmostPolygonUnderCursor(cursorLocalPos, size, mesh);
    CadPoint3D hitPt;

    if (poly != null && poly.vertices.isNotEmpty) {
      double sx = 0.0, sy = 0.0, sz = 0.0;
      for (final v in poly.vertices) {
        sx += v.x;
        sy += v.y;
        sz += v.z;
      }
      hitPt = CadPoint3D(sx / poly.vertices.length, sy / poly.vertices.length, sz / poly.vertices.length);
    } else {
      CadPoint3D? closestVertex;
      double minScreenDist = 60.0;
      for (final p in mesh.allPolygons) {
        for (final v in p.vertices) {
          final sPos = projectPointToScreenPaint(v, size);
          final d = (sPos - cursorLocalPos).distance;
          if (d < minScreenDist) {
            minScreenDist = d;
            closestVertex = v;
          }
        }
      }
      if (closestVertex == null) return null;
      hitPt = closestVertex;
    }

    final center = mesh.center;
    final dir = CadPoint3D(center.x - hitPt.x, center.y - hitPt.y, center.z - hitPt.z);
    if (dir.length < 1.0) {
      return center;
    }

    final normDir = dir.normalized();
    CadPoint3D bestOpposite = center;
    double maxProj = double.negativeInfinity;

    for (final p in mesh.allPolygons) {
      for (final v in p.vertices) {
        final rel = CadPoint3D(v.x - center.x, v.y - center.y, v.z - center.z);
        final proj = rel.x * normDir.x + rel.y * normDir.y + rel.z * normDir.z;
        if (proj > maxProj) {
          maxProj = proj;
          bestOpposite = v;
        }
      }
    }

    return bestOpposite;
  }

  void _maintainPinnedAnchor(Size size) {
    if (_pinnedPivotPoint != null && _pinnedScreenAnchor != null && size.width > 0 && size.height > 0) {
      final u = _projectOffsetFromCenter(_pinnedPivotPoint!, size);
      _paintPan = Offset(_pinnedScreenAnchor!.dx - size.width / 2.0 - u.dx, _pinnedScreenAnchor!.dy - size.height / 2.0 - u.dy);
    }
  }

  CadPoint3D _projectToSphere(Offset localPos, Size size) {
    final cx = size.width / 2.0 + _paintPan.dx;
    final cy = size.height / 2.0 + _paintPan.dy;
    final r = math.min(size.width, size.height) * 0.45;
    if (r <= 0) return const CadPoint3D(0.0, 0.0, 1.0);

    // Negative u aligns horizontal model drag with mouse drag direction (vertical v is already confirmed correct)
    final double u = -(localPos.dx - cx) / r;
    final double v = -(localPos.dy - cy) / r;
    final double dSq = u * u + v * v;

    double w;
    if (dSq <= 0.5) {
      w = math.sqrt(math.max(0.0, 1.0 - dSq));
    } else {
      w = 0.5 / math.sqrt(dSq);
    }

    final len = math.sqrt(u * u + v * v + w * w);
    if (len < 1e-6) return const CadPoint3D(0.0, 0.0, 1.0);
    return CadPoint3D(u / len, v / len, w / len);
  }

  void _rotateModelTrackball(Offset currentPos, Size size, {bool isAltPressed = false, Offset? delta}) {
    if (_cameraAnimationController.isAnimating) {
      _cameraAnimationController.stop();
    }

    final currVec = _projectToSphere(currentPos, size);
    if (_lastSphereVector == null) {
      _lastSphereVector = currVec;
      return;
    }

    final prevVec = _lastSphereVector!;
    _lastSphereVector = currVec;

    if (isAltPressed && delta != null) {
      final double dX = delta.dx;
      final double dY = delta.dy;
      TransformMatrix4 dRot;
      if (dX.abs() > dY.abs()) {
        final double angle = (-dX / (size.width * 0.45)) * 1.8;
        dRot = TransformMatrix4.rotationAxis(const CadPoint3D(0.0, 1.0, 0.0), angle);
      } else {
        final double angle = (-dY / (size.height * 0.45)) * 1.8;
        dRot = TransformMatrix4.rotationAxis(const CadPoint3D(-1.0, 0.0, 0.0), angle);
      }
      _modelTransform = dRot.multiply(_modelTransform);
    } else {
      // 360° Virtual Globe Arcball rotation (direction of the dragging pointer)
      final axisX = prevVec.y * currVec.z - prevVec.z * currVec.y;
      final axisY = prevVec.z * currVec.x - prevVec.x * currVec.z;
      final axisZ = prevVec.x * currVec.y - prevVec.y * currVec.x;
      final axisLen = math.sqrt(axisX * axisX + axisY * axisY + axisZ * axisZ);

      if (axisLen > 1e-6) {
        final dot = (prevVec.x * currVec.x + prevVec.y * currVec.y + prevVec.z * currVec.z).clamp(-1.0, 1.0);
        final angleRad = math.atan2(axisLen, dot) * 1.8;

        final normAxis = CadPoint3D(axisX / axisLen, axisY / axisLen, axisZ / axisLen);
        final dRot = TransformMatrix4.rotationAxis(normAxis, angleRad);
        _modelTransform = dRot.multiply(_modelTransform);
      }
    }

    _orthonormalizeModelTransform();
    _syncCameraAnglesFromTransform();
    _maintainPinnedAnchor(size);

    if (_isGpuAvailable && _isCameraReady && _scene != null) {
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    if (mounted) setState(() {});
  }

  void _rollCamera(double degrees) {
    if (_cameraAnimationController.isAnimating) {
      _cameraAnimationController.stop();
    }
    final dRot = TransformMatrix4.rotationAxis(const CadPoint3D(0.0, 0.0, 1.0), degrees * math.pi / 180.0);
    _modelTransform = dRot.multiply(_modelTransform);
    _orthonormalizeModelTransform();
    _syncCameraAnglesFromTransform();
    if (_lastKnownViewportSize != null) _maintainPinnedAnchor(_lastKnownViewportSize!);
    if (_isGpuAvailable && _isCameraReady && _scene != null) {
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    if (mounted) setState(() {});
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
    _modelTransform = _matrixFromAngles(_paintAzimuthDeg, _paintElevationDeg);
    _viewCubeNotifier.value = (_paintAzimuthDeg, _paintElevationDeg);
    if (_lastKnownViewportSize != null) _maintainPinnedAnchor(_lastKnownViewportSize!);

    if (_isGpuAvailable && _isCameraReady && _scene != null) {
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
    final up = vm.Vector3(math.sin(azRad) * math.sin(elRad), math.cos(elRad), math.cos(azRad) * math.sin(elRad));

    final vpHeight = size.height > 0 ? size.height : 600.0;
    final k = (_orbitDistance * 0.85) / vpHeight;

    // Moving mouse right (dx > 0) moves model right, so camera target shifts left (-right)
    // Moving mouse down (dy > 0) moves model down, so camera target shifts up (+up)
    final shift = (right * (-delta.dx * k)) + (up * (delta.dy * k));

    _orbitTarget = CadPoint3D(_orbitTarget.x + shift.x, _orbitTarget.y + shift.y, _orbitTarget.z + shift.z);

    if (_isGpuAvailable && _isCameraReady && _scene != null) {
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

    if (_isGpuAvailable && _isCameraReady && _scene != null) {
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
          ? OrthographicProjection(zoom: 1.0, near: 0.5, far: 50000.0)
          : PerspectiveProjection(
              fovRadiansY: (prefs.fieldOfView * vm.degrees2Radians).clamp(15.0 * vm.degrees2Radians, 90.0 * vm.degrees2Radians),
              near: 0.5,
              far: 50000.0,
            );
      _updateGpuCamera();
    }
    _saveCameraStateToViewModel(widget.viewModel);
    if (mounted) setState(() {});
  }

  void _orientNormalToSelectedFace() {
    final selFace = widget.viewModel.selectedFaceId;
    if (selFace == null) return;
    for (final poly in widget.viewModel.currentMesh.allPolygons) {
      if (poly.faceId == selFace) {
        final n = poly.normal;
        final len = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
        if (len > 1e-4) {
          final nx = n.x / len;
          final ny = n.y / len;
          final nz = n.z / len;
          final elDeg = math.asin(ny.clamp(-1.0, 1.0)) * vm.radians2Degrees;
          final azDeg = math.atan2(-nx, -nz) * vm.radians2Degrees;
          _setCameraFromAngles(azDeg, elDeg);
        }
        break;
      }
    }
  }

  void _handlePreviousView() {
    final prev = widget.viewModel.popPreviousCameraState();
    if (prev != null) {
      _animateCameraTo(prev);
    }
  }

  void _zoomToSelection() {
    final selFace = widget.viewModel.selectedFaceId;
    if (selFace == null) {
      _zoomToFit();
      return;
    }
    for (final poly in widget.viewModel.currentMesh.allPolygons) {
      if (poly.faceId == selFace && poly.vertices.isNotEmpty) {
        final center = poly.vertices.reduce((a, b) => CadPoint3D(a.x + b.x, a.y + b.y, a.z + b.z));
        final cx = center.x / poly.vertices.length;
        final cy = center.y / poly.vertices.length;
        final cz = center.z / poly.vertices.length;
        final targetState = Cad3dCameraState(
          azimuthDeg: _paintAzimuthDeg,
          elevationDeg: _paintElevationDeg,
          zoom: _paintZoom * 1.5,
          pan: _paintPan,
          orbitDistance: _orbitDistance * 0.65,
          orbitTarget: CadPoint3D(cx, cy, cz),
          isInitialized: true,
        );
        _animateCameraTo(targetState);
        break;
      }
    }
  }

  void _showNamedViewsDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final views = widget.viewModel.namedViews;
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.bookmark_border, size: 18, color: Color(0xFF0284C7)),
                  SizedBox(width: 8),
                  Text('Named Views', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textController,
                            decoration: const InputDecoration(
                              hintText: 'New view name...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final name = textController.text.trim();
                            if (name.isNotEmpty) {
                              widget.viewModel.saveNamedView(name, _getCurrentCameraState());
                              textController.clear();
                              setDlgState(() {});
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (views.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No named views saved yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      )
                    else
                      SizedBox(
                        height: 180,
                        child: ListView(
                          children: views.entries.map((entry) {
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              title: Text(entry.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                                onPressed: () {
                                  widget.viewModel.deleteNamedView(entry.key);
                                  setDlgState(() {});
                                },
                              ),
                              onTap: () {
                                _animateCameraTo(entry.value);
                                Navigator.of(ctx).pop();
                              },
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
            );
          },
        );
      },
    );
  }

  CadFoldedPolygon3D? _findFrontmostPolygonUnderCursor(Offset cursorLocalPos, Size size, FoldedMeshResult mesh) {
    if (mesh.polygons.isEmpty) return null;

    CadFoldedPolygon3D? bestPoly;
    double closestDist = double.infinity;
    final m = _modelTransform.m;
    final mCenter = mesh.center;

    for (final poly in mesh.allPolygons) {
      if (poly.vertices.length < 3) continue;

      final screenPts = <Offset>[];
      for (final v in poly.vertices) {
        screenPts.add(projectPointToScreen(v, size));
      }

      final path = Path()..moveTo(screenPts[0].dx, screenPts[0].dy);
      for (int i = 1; i < screenPts.length; i++) {
        path.lineTo(screenPts[i].dx, screenPts[i].dy);
      }
      path.close();

      if (path.contains(cursorLocalPos)) {
        double polyDepth = 0.0;
        for (final v in poly.vertices) {
          final dx = v.x - mCenter.x;
          final dy = v.y - mCenter.y;
          final dz = v.z - mCenter.z;
          final depth = dx * m[8] + dy * m[9] + dz * m[10];
          polyDepth += depth;
        }
        polyDepth /= poly.vertices.length;

        final dist = -polyDepth;
        if (dist < closestDist) {
          closestDist = dist;
          bestPoly = poly;
        }
      }
    }

    return bestPoly;
  }

  void _handleSecondaryTapUp(TapUpDetails details, Size size, FoldedMeshResult mesh) {
    if (widget.isInteractionLocked) return;

    final poly = _findFrontmostPolygonUnderCursor(details.localPosition, size, mesh);
    if (poly != null && poly.faceId.isNotEmpty) {
      widget.viewModel.selectFace(poly.faceId);
    }

    _showOnshapeContextMenu(globalPosition: details.globalPosition, polygon: poly, size: size);
  }

  void _handlePrimaryTapUp(TapUpDetails details, Size size, FoldedMeshResult mesh) {
    if (widget.isInteractionLocked) return;

    final poly = _findFrontmostPolygonUnderCursor(details.localPosition, size, mesh);
    if (poly != null && poly.faceId.isNotEmpty) {
      widget.viewModel.selectFace(poly.faceId);
    } else {
      widget.viewModel.clearSelection();
    }
  }

  Future<void> _showOnshapeContextMenu({required Offset globalPosition, required CadFoldedPolygon3D? polygon, required Size size}) async {
    final faceId = polygon?.faceId;
    final partId = faceId != null ? SheetMetalStudioViewModel.extractPartIdFromFaceId(faceId) : null;
    final isPartHidden = partId != null && widget.viewModel.isPartHidden(partId);
    final isPartIsolated = partId != null && widget.viewModel.isPartIsolated(partId);
    final isPartTransparent = partId != null && widget.viewModel.isPartTransparent(partId);

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0), Offset.zero & overlay.size),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
      ),
      color: Colors.white,
      elevation: 8,
      items: [
        // Header Chip
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(polygon != null ? Icons.layers_rounded : Icons.view_in_ar_rounded, size: 13, color: const Color(0xFF0284C7)),
                const SizedBox(width: 6),
                Text(
                  polygon != null ? 'Face: $faceId' : '3D Viewport Controls',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                if (partId != null && partId != faceId) ...[
                  const SizedBox(width: 4),
                  Text('($partId)', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                ],
              ],
            ),
          ),
        ),
        const PopupMenuDivider(height: 6),

        if (polygon != null) ...[
          _buildContextItem('orient_normal', 'Orient normal to face (N)', Icons.filter_center_focus),
          _buildContextItem('zoom_selection', 'Zoom to selection', Icons.crop_free),
          const PopupMenuDivider(height: 6),
          _buildContextItem('hide_part', isPartHidden ? 'Show part (Y)' : 'Hide part (Y)', Icons.visibility_off_outlined),
          _buildContextItem('hide_other', 'Hide other parts', Icons.hide_source),
          _buildContextItem('show_all', 'Show all parts (Shift+Y)', Icons.visibility_outlined),
          const PopupMenuDivider(height: 6),
          _buildContextItem('isolate_part', isPartIsolated ? 'Exit isolation (Shift+I)' : 'Isolate part (Shift+I)', Icons.filter_frames),
          _buildContextItem('make_transparent', isPartTransparent ? 'Clear transparency (Shift+T)' : 'Make transparent (Shift+T)', Icons.opacity),
          const PopupMenuDivider(height: 6),
          _buildContextItem('section_on_plane', 'Create section on this face', Icons.splitscreen),
          _buildContextItem('edit_appearance', 'Edit part appearance...', Icons.palette_outlined),
        ] else ...[
          _buildContextItem('zoom_fit', 'Zoom to fit (F)', Icons.fit_screen),
          _buildContextItem('previous_view', 'Previous view', Icons.history, enabled: widget.viewModel.hasPreviousCameraView),
          _buildContextItem('named_views', 'Named views...', Icons.bookmark_border),
          const PopupMenuDivider(height: 6),
          _buildContextItem('show_all', 'Show all parts (Shift+Y)', Icons.visibility_outlined),
          _buildContextItem('clear_isolation', 'Clear all isolation', Icons.filter_none),
          _buildContextItem('clear_transparency', 'Clear all transparency', Icons.invert_colors_off),
          const PopupMenuDivider(height: 6),
          _buildContextItem(
            'toggle_lock',
            widget.viewModel.is3dRotateLocked ? 'Unlock 3D Rotate' : 'Lock 3D Rotate',
            widget.viewModel.is3dRotateLocked ? Icons.lock_open : Icons.lock_outline,
          ),
          _buildContextItem('section_view', 'Section view...', Icons.splitscreen),
          _buildContextItem('graphics_prefs', 'Graphics preferences...', Icons.settings_outlined),
        ],
      ],
    );

    if (result == null) return;
    _executeContextMenuAction(result, polygon, partId);
  }

  PopupMenuItem<String> _buildContextItem(String value, String text, IconData icon, {bool enabled = true, Color? iconColor}) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 15, color: enabled ? (iconColor ?? const Color(0xFF475569)) : const Color(0xFFCBD5E1)),
          const SizedBox(width: 9),
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: enabled ? const Color(0xFF1E293B) : const Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  void _executeContextMenuAction(String action, CadFoldedPolygon3D? poly, String? partId) {
    switch (action) {
      case 'orient_normal':
        _orientNormalToSelectedFace();
        break;
      case 'zoom_selection':
        _zoomToSelection();
        break;
      case 'zoom_fit':
        _zoomToFit();
        break;
      case 'previous_view':
        _handlePreviousView();
        break;
      case 'named_views':
        _showNamedViewsDialog();
        break;
      case 'hide_part':
        if (partId != null) {
          if (widget.viewModel.isPartHidden(partId)) {
            widget.viewModel.showPart(partId);
          } else {
            widget.viewModel.hidePart(partId);
          }
        }
        break;
      case 'hide_other':
        if (partId != null) {
          widget.viewModel.hideOtherParts(partId);
        }
        break;
      case 'show_all':
        widget.viewModel.showAllParts();
        break;
      case 'isolate_part':
        if (partId != null) {
          if (widget.viewModel.isPartIsolated(partId)) {
            widget.viewModel.clearIsolation();
          } else {
            widget.viewModel.isolatePart(partId);
          }
        }
        break;
      case 'clear_isolation':
        widget.viewModel.clearIsolation();
        break;
      case 'make_transparent':
        if (partId != null) {
          widget.viewModel.makePartTransparent(partId);
        }
        break;
      case 'clear_transparency':
        widget.viewModel.clearTransparency();
        break;
      case 'section_on_plane':
        if (poly != null && poly.vertices.isNotEmpty) {
          final nx = poly.normal.x.abs();
          final ny = poly.normal.y.abs();
          final nz = poly.normal.z.abs();
          SectionPlaneAxis axis;
          double offset;
          if (nx >= ny && nx >= nz) {
            axis = SectionPlaneAxis.yz;
            offset = poly.vertices.first.x;
          } else if (ny >= nx && ny >= nz) {
            axis = SectionPlaneAxis.zx;
            offset = poly.vertices.first.y;
          } else {
            axis = SectionPlaneAxis.xy;
            offset = poly.vertices.first.z;
          }
          widget.viewModel.setSectionViewAxis(axis);
          widget.viewModel.setSectionViewOffset(offset);
          if (!widget.viewModel.sectionViewConfig.isEnabled) {
            widget.viewModel.toggleSectionView();
          }
        }
        break;
      case 'section_view':
        widget.viewModel.toggleSectionView();
        break;
      case 'toggle_lock':
        widget.viewModel.toggle3dRotateLock();
        break;
      case 'graphics_prefs':
        setState(() {
          widget.viewModel.isGraphicsPreferencesOpen = true;
        });
        break;
      case 'edit_appearance':
        if (partId != null) {
          _showPartAppearanceDialog(partId);
        }
        break;
    }
  }

  void _showPartAppearanceDialog(String partId) {
    final currentColor = widget.viewModel.partColorOverrides[partId] ?? widget.viewModel.graphicsPreferences.materialSettings.baseColor;

    final colorPresets = <(String, Color)>[
      ('Galvanized Steel DX51D', const Color(0xFFA6AABC)),
      ('Carbon Steel ASTM A36', const Color(0xFF475569)),
      ('Stainless Steel 304', const Color(0xFFCBD5E1)),
      ('Signal White Powdercoat', const Color(0xFFF8FAFC)),
      ('RAL 7016 Anthracite', const Color(0xFF334155)),
      ('Industrial Orange', const Color(0xFFEA580C)),
      ('Signal Blue', const Color(0xFF0284C7)),
      ('Safety Yellow', const Color(0xFFF59E0B)),
      ('Forest Green', const Color(0xFF15803D)),
      ('Anodized Gold', const Color(0xFFD97706)),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.palette_outlined, size: 20, color: Color(0xFF0284C7)),
            const SizedBox(width: 8),
            Text('Part Appearance: $partId', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Sheet Metal Finish / Color Preset:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colorPresets.map((preset) {
                  final isSelected = currentColor.toARGB32() == preset.$2.toARGB32();
                  return Tooltip(
                    message: preset.$1,
                    child: InkWell(
                      onTap: () {
                        widget.viewModel.setPartColor(partId, preset.$2);
                        if (_isGpuAvailable) {
                          _rebuildCadMesh(preserveCamera: true);
                        }
                        Navigator.of(ctx).pop();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 48,
                        height: 36,
                        decoration: BoxDecoration(
                          color: preset.$2,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF94A3B8), width: isSelected ? 2.5 : 1.0),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2, offset: const Offset(0, 1))],
                        ),
                        child: isSelected ? const Icon(Icons.check, size: 16, color: Color(0xFF0284C7)) : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.viewModel.clearPartColor(partId);
              if (_isGpuAvailable) {
                _rebuildCadMesh(preserveCamera: true);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Reset to Default', style: TextStyle(color: Color(0xFFEF4444))),
          ),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  Widget _buildSectionViewControlBar() {
    final cfg = widget.viewModel.sectionViewConfig;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cut_outlined, size: 16, color: Color(0xFF0284C7)),
          const SizedBox(width: 8),
          const Text(
            'Section:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(width: 8),
          // Axis selector
          DropdownButton<SectionPlaneAxis>(
            value: cfg.axis,
            isDense: true,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: SectionPlaneAxis.yz,
                child: Text('YZ (Front)', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: SectionPlaneAxis.zx,
                child: Text('ZX (Top)', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: SectionPlaneAxis.xy,
                child: Text('XY (Right)', style: TextStyle(fontSize: 12)),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                widget.viewModel.setSectionViewAxis(val);
                if (_isGpuAvailable) {
                  _rebuildCadMesh(preserveCamera: true);
                }
                setState(() {});
              }
            },
          ),
          const SizedBox(width: 12),
          // Distance slider
          SizedBox(
            width: 140,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), trackHeight: 3),
              child: Slider(
                value: cfg.distanceOffsetMm.clamp(-250.0, 250.0),
                min: -250.0,
                max: 250.0,
                activeColor: const Color(0xFF0284C7),
                onChanged: (val) {
                  widget.viewModel.setSectionViewOffset(val);
                  if (_isGpuAvailable) {
                    _rebuildCadMesh(preserveCamera: true);
                  }
                  setState(() {});
                },
              ),
            ),
          ),
          Text('${cfg.distanceOffsetMm.round()} mm', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
          const SizedBox(width: 8),
          // Flip normal button
          IconButton(
            tooltip: 'Flip cut direction',
            icon: Icon(Icons.swap_horiz, size: 16, color: cfg.flipNormal ? const Color(0xFF0284C7) : const Color(0xFF64748B)),
            onPressed: () {
              widget.viewModel.sectionViewConfig = cfg.copyWith(flipNormal: !cfg.flipNormal);
              if (_isGpuAvailable) {
                _rebuildCadMesh(preserveCamera: true);
              }
              setState(() {});
            },
          ),
          // Close section view button
          IconButton(
            tooltip: 'Exit Section View',
            icon: const Icon(Icons.close, size: 16, color: Color(0xFFEF4444)),
            onPressed: () {
              widget.viewModel.toggleSectionView();
              if (_isGpuAvailable) {
                _rebuildCadMesh(preserveCamera: true);
              }
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // --- Screen-Space Projection Math (Dual-Engine Unified) ---

  Offset projectPointToScreenPaint(CadPoint3D p, Size size) {
    if (size.width <= 0 || size.height <= 0) return Offset.zero;
    final mesh = widget.viewModel.currentMesh;
    final cx = size.width / 2.0 + _paintPan.dx;
    final cy = size.height / 2.0 + _paintPan.dy;

    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * _paintZoom;

    final pivot = mesh.center;
    final cameraDist = math.max(fitDim * 2.5, 1000.0);

    final rx = p.x - pivot.x;
    final ry = p.y - pivot.y;
    final rz = p.z - pivot.z;

    final m = _modelTransform.m;
    final x2 = rx * m[0] + ry * m[1] + rz * m[2];
    final y2 = rx * m[4] + ry * m[5] + rz * m[6];
    final z2 = rx * m[8] + ry * m[9] + rz * m[10];

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
    if (!_isGpuAvailable || _scene == null) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _lastKnownViewportSize = size;

        return Stack(
          children: [
            // =================================================================
            // 1. PRIMARY VIEWPORT LAYER (Flutter GPU vs Flutter Paint)
            // =================================================================
            Positioned.fill(
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.keyF) {
                    _zoomToFit();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.keyN) {
                    _orientNormalToSelectedFace();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.keyP && !HardwareKeyboard.instance.isShiftPressed) {
                    setState(() {
                      _isPinnedPivotMode = !_isPinnedPivotMode;
                    });
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.keyY) {
                    final selFace = widget.viewModel.selectedFaceId;
                    if (selFace != null) {
                      final pId = SheetMetalStudioViewModel.extractPartIdFromFaceId(selFace);
                      if (HardwareKeyboard.instance.isShiftPressed) {
                        widget.viewModel.showPart(pId);
                      } else {
                        widget.viewModel.hidePart(pId);
                      }
                      if (_isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                      return KeyEventResult.handled;
                    }
                  }
                  if (key == LogicalKeyboardKey.keyI && HardwareKeyboard.instance.isShiftPressed) {
                    final selFace = widget.viewModel.selectedFaceId;
                    if (selFace != null) {
                      final pId = SheetMetalStudioViewModel.extractPartIdFromFaceId(selFace);
                      widget.viewModel.isolatePart(pId);
                      if (_isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                      return KeyEventResult.handled;
                    }
                  }
                  if (key == LogicalKeyboardKey.keyT && HardwareKeyboard.instance.isShiftPressed) {
                    final selFace = widget.viewModel.selectedFaceId;
                    if (selFace != null) {
                      final pId = SheetMetalStudioViewModel.extractPartIdFromFaceId(selFace);
                      widget.viewModel.makePartTransparent(pId);
                      if (_isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    widget.viewModel.pushCameraHistory(_getCurrentCameraState());
                    final isPrimary = (event.buttons & kPrimaryMouseButton) != 0;
                    final isSecondary = (event.buttons & kSecondaryMouseButton) != 0;
                    final isMiddle = (event.buttons & kTertiaryButton) != 0 || (event.buttons & kMiddleMouseButton) != 0;
                    bool isCtrlPressed = false;
                    try {
                      isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
                    } catch (_) {}

                    setState(() {
                      if (!isMiddle && (isPrimary || isSecondary) && !_isPanToolActive) {
                        _isRotatingModel = true;
                        _dragStartPos = event.localPosition;
                        _currentDragPos = event.localPosition;
                        _lastSphereVector = _projectToSphere(event.localPosition, size);

                        // If Pinned Pivot mode is active (or Ctrl pressed), pin the opposite side
                        if (_isPinnedPivotMode || isCtrlPressed) {
                          final pinPt = _computeOppositePinnedPivot(event.localPosition, size, mesh);
                          if (pinPt != null) {
                            _pinnedPivotPoint = pinPt;
                            _pinnedScreenAnchor = projectPointToScreenPaint(pinPt, size);
                          } else {
                            _pinnedPivotPoint = null;
                            _pinnedScreenAnchor = null;
                          }
                        } else {
                          _pinnedPivotPoint = null;
                          _pinnedScreenAnchor = null;
                        }
                      }
                    });
                  },
                  onPointerUp: (_) => setState(() {
                    _isRotatingModel = false;
                    _dragStartPos = null;
                    _currentDragPos = null;
                    _lastSphereVector = null;
                    _pinnedPivotPoint = null;
                    _pinnedScreenAnchor = null;
                  }),
                  onPointerCancel: (_) => setState(() {
                    _isRotatingModel = false;
                    _dragStartPos = null;
                    _currentDragPos = null;
                    _lastSphereVector = null;
                    _pinnedPivotPoint = null;
                    _pinnedScreenAnchor = null;
                  }),
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
                    bool isCtrlPressed = false;
                    bool isAltPressed = false;
                    try {
                      isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                      isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
                      isAltPressed = HardwareKeyboard.instance.isAltPressed;
                    } catch (_) {}

                    if (isMiddle || (isSecondary && isCtrlPressed) || (isPrimary && (_isPanToolActive || isShiftPressed))) {
                      // Panning (Middle Drag / Ctrl+Right Drag / Shift+Left / Pan Tool)
                      _panCamera(event.delta, size);
                      _lastSphereVector = _projectToSphere(event.localPosition, size);
                    } else if (isSecondary || isPrimary) {
                      if (widget.viewModel.is3dRotateLocked) {
                        return; // 3D Rotate is locked!
                      }
                      _currentDragPos = event.localPosition;
                      if (_isTurntableOrbit) {
                        // Turntable constrained orbit
                        if (isAltPressed) {
                          if (event.delta.dx.abs() > event.delta.dy.abs()) {
                            _orbitCamera(-event.delta.dx * 0.5, 0.0);
                          } else {
                            _orbitCamera(0.0, -event.delta.dy * 0.5);
                          }
                        } else {
                          _orbitCamera(-event.delta.dx * 0.5, -event.delta.dy * 0.5);
                        }
                      } else {
                        // 360° Virtual Globe Arcball rotation
                        _rotateModelTrackball(event.localPosition, size, isAltPressed: isAltPressed, delta: event.delta);
                      }
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: widget.isInteractionLocked ? null : (details) => _handlePrimaryTapUp(details, size, mesh),
                    onSecondaryTapUp: widget.isInteractionLocked ? null : (details) => _handleSecondaryTapUp(details, size, mesh),
                    // Fix #1: Removed onDoubleTap: _zoomToFit so double-clicking never resets the camera!
                    child: _scene != null ? SceneView(_scene!) : const SizedBox.shrink(),
                  ),
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
            // 2b. 360° VIRTUAL GLOBE DRAG OVERLAY
            // =================================================================
            if (_isRotatingModel && _dragStartPos != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _VirtualGlobeOverlayPainter(
                      center: Offset(size.width / 2.0 + _paintPan.dx, size.height / 2.0 + _paintPan.dy),
                      radius: math.min(size.width, size.height) * 0.45,
                      startPoint: _dragStartPos,
                      currentPoint: _currentDragPos,
                      pinnedAnchor: _pinnedScreenAnchor,
                    ),
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

                            // Engine Mode Indicator (Flutter GPU Impeller 120 FPS)
                            Tooltip(
                              message: '3D CAD Engine: Flutter GPU (Impeller)\nHardware-accelerated 120 FPS PBR rendering active.',
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF10B981)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.speed, size: 12, color: Color(0xFF10B981)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Engine: GPU (120 FPS)',
                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                                    ),
                                  ],
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
                isPinnedPivot: _isPinnedPivotMode,
                onTogglePinnedPivot: () {
                  setState(() => _isPinnedPivotMode = !_isPinnedPivotMode);
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
                    if (_isGpuAvailable) {
                      _rebuildCadMesh(preserveCamera: true);
                    }
                  });
                },
                isObstructedXRay: widget.viewModel.isObstructedXRayMode,
                onToggleObstructedXRay: () {
                  widget.viewModel.toggleObstructedXRayMode();
                  if (_isGpuAvailable) {
                    _rebuildCadMesh(preserveCamera: true);
                  }
                  setState(() {});
                },
                currentShadingStyle: widget.viewModel.cadShadingStyle,
                onShadingStyleChanged: (style) {
                  widget.viewModel.cadShadingStyle = style;
                  if (_isGpuAvailable) {
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
                  viewModel: widget.viewModel,
                  preferences: widget.viewModel.graphicsPreferences,
                  onChanged: (prefs) {
                    widget.viewModel.graphicsPreferences = prefs;
                    _applyEnvironmentSettings();
                    if (_isGpuAvailable) {
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
                    if (_isGpuAvailable) {
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
                    is3dRotateLocked: widget.viewModel.is3dRotateLocked,
                    onToggle3dRotateLock: () {
                      widget.viewModel.toggle3dRotateLock();
                      setState(() {});
                    },
                    renderMode: widget.viewModel.onshapeRenderMode,
                    onRenderModeChanged: (mode) {
                      widget.viewModel.onshapeRenderMode = mode;
                      if (_isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                    },
                    hiddenEdgesVisible: widget.viewModel.showBorderLines,
                    onToggleHiddenEdges: (val) {
                      widget.viewModel.toggleBorderLines();
                      if (_isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                    },
                    tangentEdgeMode: widget.viewModel.graphicsPreferences.tangentEdgeMode,
                    onTangentEdgeModeChanged: (mode) {
                      widget.viewModel.updateGraphicsPreferences((p) => p.copyWith(tangentEdgeMode: mode));
                      if (_isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                    },
                    highlightBoundaryEdges: widget.viewModel.graphicsPreferences.highlightBoundaryEdges,
                    onToggleHighlightBoundaryEdges: () {
                      widget.viewModel.updateGraphicsPreferences((p) => p.copyWith(highlightBoundaryEdges: !p.highlightBoundaryEdges));
                      if (_isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                    },
                    isSectionViewActive: widget.viewModel.sectionViewConfig.isEnabled,
                    onToggleSectionView: () {
                      widget.viewModel.toggleSectionView();
                      if (_isGpuAvailable) {
                        _rebuildCadMesh(preserveCamera: true);
                      }
                      setState(() {});
                    },
                    hasPreviousView: widget.viewModel.hasPreviousCameraView,
                    onPreviousView: _handlePreviousView,
                    onOrientNormal: _orientNormalToSelectedFace,
                    onZoomToSelection: _zoomToSelection,
                    onNamedViews: _showNamedViewsDialog,
                    isPerspective: !widget.viewModel.isOrthoProjection,
                    onTogglePerspective: _toggleProjection,
                    onOpenGraphicsPreferences: () {
                      setState(() {
                        widget.viewModel.isGraphicsPreferencesOpen = true;
                      });
                    },
                    onRollCw: () => _rollCamera(15.0),
                    onRollCcw: () => _rollCamera(-15.0),
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

            // Floating Section View Control Bar (when active)
            if (widget.viewModel.sectionViewConfig.isEnabled) Positioned(bottom: 48, left: 0, right: 0, child: Center(child: _buildSectionViewControlBar())),

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

/// Sleek 360° Virtual Globe overlay displayed during interactive model rotation
class _VirtualGlobeOverlayPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final Offset? startPoint;
  final Offset? currentPoint;
  final Offset? pinnedAnchor;

  _VirtualGlobeOverlayPainter({required this.center, required this.radius, this.startPoint, this.currentPoint, this.pinnedAnchor});

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;

    // 1. Globe Equator / Silhouette Circle
    final rimPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(center, radius, rimPaint);

    // Subtle outer halo glow
    final glowPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawCircle(center, radius, glowPaint);

    // 2. Subtle internal curved meridian & parallel arcs
    final arcPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Horizontal equator arc (slight perspective curve)
    final equatorRect = Rect.fromCenter(center: center, width: radius * 2.0, height: radius * 0.4);
    canvas.drawOval(equatorRect, arcPaint);

    // Vertical meridian arc
    final meridianRect = Rect.fromCenter(center: center, width: radius * 0.4, height: radius * 2.0);
    canvas.drawOval(meridianRect, arcPaint);

    // 3. Pointer Drag Track
    if (startPoint != null && currentPoint != null) {
      final trackPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(startPoint!, currentPoint!, trackPaint);

      // Start anchor dot
      final startPaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(startPoint!, 4.5, startPaint);

      final startRing = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(startPoint!, 4.5, startRing);

      // Current position pointer ring
      final currRing = Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(currentPoint!, 6.0, currRing);
    }

    // 4. Pinned Pivot Reticle Indicator (opposite side pinned in place)
    if (pinnedAnchor != null) {
      final pinP = pinnedAnchor!;

      // Outer glowing target ring
      final anchorGlow = Paint()
        ..color = const Color(0xFFFFB300).withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0;
      canvas.drawCircle(pinP, 13.0, anchorGlow);

      final anchorRing = Paint()
        ..color = const Color(0xFFFFB300)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(pinP, 11.0, anchorRing);

      // Center solid anchor dot
      final dotPaint = Paint()
        ..color = const Color(0xFFFFB300)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pinP, 3.5, dotPaint);

      // Target reticle crosshairs
      final crossPaint = Paint()
        ..color = const Color(0xFFFFB300)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(pinP.dx - 18, pinP.dy), Offset(pinP.dx - 13, pinP.dy), crossPaint);
      canvas.drawLine(Offset(pinP.dx + 13, pinP.dy), Offset(pinP.dx + 18, pinP.dy), crossPaint);
      canvas.drawLine(Offset(pinP.dx, pinP.dy - 18), Offset(pinP.dx, pinP.dy - 13), crossPaint);
      canvas.drawLine(Offset(pinP.dx, pinP.dy + 13), Offset(pinP.dx, pinP.dy + 18), crossPaint);

      // Radial lever arm line to drag start
      if (startPoint != null) {
        final leverPaint = Paint()
          ..color = const Color(0xFFFFB300).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawLine(pinP, startPoint!, leverPaint);
      }

      // High-contrast CAD pill badge: "📌 PINNED PIVOT"
      final textSpan = TextSpan(
        text: '📌 PINNED PIVOT',
        style: const TextStyle(color: Color(0xFFFFB300), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      final badgeOffset = Offset(pinP.dx - textPainter.width / 2.0, pinP.dy + 16.0);
      textPainter.paint(canvas, badgeOffset);
    }
  }

  @override
  bool shouldRepaint(covariant _VirtualGlobeOverlayPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.radius != radius ||
        oldDelegate.startPoint != startPoint ||
        oldDelegate.currentPoint != currentPoint ||
        oldDelegate.pinnedAnchor != pinnedAnchor;
  }
}
