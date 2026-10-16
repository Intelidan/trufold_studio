import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import '../../sheet_metal_studio/models/cad_primitives.dart';
import '../../sheet_metal_studio/engine/kinematic_fold_engine.dart';
import '../models/assembly_part.dart';
import '../models/assembly_document.dart';
import '../models/assembly_compliance.dart';
import '../models/assembly_bom.dart';
import '../models/weld_quality_model.dart';
import '../models/assembly_timeline_item.dart';
import '../models/assembly_cad_settings.dart';
import '../engine/sketch/assembly_surface_sketch_engine.dart' hide WeldJointStyle;
import '../engine/sketch/onshape_sketch_modify_engine.dart';
import '../../sketch_draft_files/widgets/weld_overlay_ui.dart';

/// Active 3D manipulation mode for the selected part.
enum GizmoMode { translate, rotate }

/// Three distinct interaction phases for the authentic SketchUp-style Rotate Tool:
enum RotateToolPhase {
  /// 1. Hovering protractor, waiting for Click 1 to lock Pivot / Center point
  awaitingCenter,

  /// 2. Center locked, moving rubber-band arm, waiting for Click 2 to set 0.0° reference baseline
  awaitingBaseline,

  /// 3. Baseline locked, sweeping angle arc with snapping, waiting for Click 3 to commit
  rotatingAngle,
}

/// SketchUp-style primary tool modes.
enum SketchUpToolMode {
  select, // Click to select parts / entities
  move, // Move / Translate tool (Key: M)
  rotate, // Rotate tool (Key: R / Q)
  sketch, // Direct 3D Face Sketch (Key: S)
  bridge, // Auto-Span Face-to-Face Bridging Tool (Key: B)
  weld, // Interactive Draft-Line Seam Weld Tool (Key: W)
  magnetic, // Magnetic Snap & Coupling Tool (Key: J)
  orbit, // Camera Orbit / Rotation Tool (Key: O)
  pan, // Camera Pan Tool (Key: H)
}

/// Measurement Unit Format (SS2)
enum MeasurementUnitFormat {
  decimal('Decimal'),
  fractional('Fractional'),
  architectural('Architectural'),
  engineering('Engineering');

  final String label;
  const MeasurementUnitFormat(this.label);
}

/// Measurement Length Unit (SS2)
enum MeasurementLengthUnit {
  millimeters('Millimeters', 'mm', 1.0),
  centimeters('Centimeters', 'cm', 10.0),
  meters('Meters', 'm', 1000.0),
  inches('Inches', 'in', 25.4),
  feet('Feet', 'ft', 304.8);

  final String label;
  final String symbol;
  final double toMmFactor;
  const MeasurementLengthUnit(this.label, this.symbol, this.toMmFactor);
}

/// Measurement Area Unit (SS2)
enum MeasurementAreaUnit {
  squareFeet('Feet²', 'ft²'),
  squareMeters('Meters²', 'm²'),
  squareInches('Inches²', 'in²'),
  squareMillimeters('Millimeters²', 'mm²');

  final String label;
  final String symbol;
  const MeasurementAreaUnit(this.label, this.symbol);
}

/// Measurement Volume Unit (SS2)
enum MeasurementVolumeUnit {
  cubicFeet('Feet³', 'ft³'),
  cubicMeters('Meters³', 'm³'),
  cubicInches('Inches³', 'in³'),
  cubicMillimeters('Millimeters³', 'mm³');

  final String label;
  final String symbol;
  const MeasurementVolumeUnit(this.label, this.symbol);
}

/// Angle Unit (SS2)
enum MeasurementAngleUnit {
  degrees('Degrees', '°'),
  radians('Radians', 'rad');

  final String label;
  final String symbol;
  const MeasurementAngleUnit(this.label, this.symbol);
}

/// SketchUp Standard Camera Views (SS3)
enum SketchUpStandardView {
  iso('Iso', 45.0, 35.264),
  top('Top', 0.0, 89.9),
  front('Front', 0.0, 0.0),
  right('Right', 90.0, 0.0),
  back('Back', 180.0, 0.0),
  left('Left', 270.0, 0.0),
  bottom('Bottom', 0.0, -89.9);

  final String label;
  final double azimuth;
  final double elevation;
  const SketchUpStandardView(this.label, this.azimuth, this.elevation);
}

/// Active axis being transformed or nudged.
enum GizmoAxis { none, x, y, z }

/// Model defining a part awaiting placement onto the drawing board via click or drag-and-drop.
class PendingPartPlacement {
  final AssemblyPartType type;
  final String name;
  final double length;
  final double height;
  final double flangeWidth;
  final double thickness;
  final Color? color;
  final Map<String, dynamic>? extraParams;

  const PendingPartPlacement({
    required this.type,
    required this.name,
    this.length = 1000.0,
    this.height = 75.0,
    this.flangeWidth = 35.0,
    this.thickness = 2.0,
    this.color,
    this.extraParams,
  });
}

/// Comprehensive ViewModel managing the 3D Assembly Studio state.
class AssemblyStudioViewModel extends ChangeNotifier implements FinalCADViewModel {
  late AssemblyDocument doc;

  // Undo / Redo history
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  static const int _maxUndoHistory = 40;
  int _nextIdCounter = 0;

  String _generateId(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_nextIdCounter++}';

  // Camera & Viewport Navigation
  double azimuthDeg = 45.0;
  double elevationDeg = 30.0;
  double zoom = 0.75;
  Offset pan = Offset.zero;
  bool isOrthoProjection = false;
  bool isTurntableOrbit = true;
  bool showWireframe = true;
  bool showWelds = true;
  bool showWeldOverlay = true;
  int documentVersion = 0;

  // Active 3D Render Engine (Flutter GPU vs 2D Canvas Fallback)
  Cad3dEngineMode _renderEngine = Cad3dEngineMode.flutterGpu;
  Cad3dEngineMode get renderEngine => _renderEngine;

  void setRenderEngine(Cad3dEngineMode mode) {
    if (_renderEngine == mode) return;
    _renderEngine = mode;
    notifyListeners();
  }

  void toggleRenderEngine() {
    if (_renderEngine == Cad3dEngineMode.flutterGpu) {
      setRenderEngine(Cad3dEngineMode.flutterPaint);
    } else {
      setRenderEngine(Cad3dEngineMode.flutterGpu);
    }
  }

  // ===========================================================================
  // WELDING SIMULATION: JOINT STYLES & QUALITY EVALUATION (welding_simulation_docs.md)
  // ===========================================================================
  WeldJointStyle activeJointStyle = WeldJointStyle.tJoint;
  WeldScoreResult? latestWeldEvaluation;
  List<WeldAnomaly> latestWeldAnomalies = [];

  void setJointStyle(WeldJointStyle style) {
    if (activeJointStyle != style) {
      activeJointStyle = style;
      notifyListeners();
    }
  }

  void clearWeldEvaluation() {
    latestWeldEvaluation = null;
    latestWeldAnomalies.clear();
    notifyListeners();
  }

  WeldScoreResult evaluateWeldQuality({required List<CadPoint3D> pathPoints, required List<double> timestamps}) {
    final anomalies = <WeldAnomaly>[];

    if (pathPoints.length < 2 || timestamps.length < 2) {
      const res = WeldScoreResult(
        speedConsistency: 100.0,
        profileUniformity: 100.0,
        overallScore: 100.0,
        gradeFeedback: 'EXCELLENT: Ideal bead deposition profile.',
      );
      latestWeldEvaluation = res;
      latestWeldAnomalies.clear();
      notifyListeners();
      return res;
    }

    final count = math.min(pathPoints.length, timestamps.length);
    final speeds = <double>[];

    for (int i = 1; i < count; i++) {
      final dist = pathPoints[i].distanceTo(pathPoints[i - 1]);
      final dt = timestamps[i] - timestamps[i - 1];
      if (dt > 0.005) {
        final speed = dist / dt;
        speeds.add(speed);

        // Thresholds matching welding_simulation_docs.md:
        // Excessive speed (> 24.0 mm/s) -> Porosity Risk
        // Too slow (< 2.5 mm/s) -> Burn-through Risk
        if (speed > 24.0) {
          anomalies.add(WeldAnomaly(position: pathPoints[i], description: 'Excessive speed (Porosity Risk)', severity: 0.85));
        } else if (speed < 2.5 && dist > 1.0) {
          anomalies.add(WeldAnomaly(position: pathPoints[i], description: 'Too slow (Burn-through Risk)', severity: 0.90));
        }
      }
    }

    // Hand wobble / erratic weave detection
    if (pathPoints.length >= 4) {
      final start = pathPoints.first;
      final end = pathPoints.last;
      final lineVec = CadPoint3D(end.x - start.x, end.y - start.y, end.z - start.z);
      final lineLen = math.sqrt(lineVec.x * lineVec.x + lineVec.y * lineVec.y + lineVec.z * lineVec.z);
      if (lineLen > 10.0) {
        final dir = CadPoint3D(lineVec.x / lineLen, lineVec.y / lineLen, lineVec.z / lineLen);
        for (int i = 1; i < pathPoints.length - 1; i++) {
          final pt = pathPoints[i];
          final v = CadPoint3D(pt.x - start.x, pt.y - start.y, pt.z - start.z);
          final proj = v.x * dir.x + v.y * dir.y + v.z * dir.z;
          final perpX = v.x - proj * dir.x;
          final perpY = v.y - proj * dir.y;
          final perpZ = v.z - proj * dir.z;
          final dev = math.sqrt(perpX * perpX + perpY * perpY + perpZ * perpZ);
          if (dev > 7.0 && !anomalies.any((a) => a.position.distanceTo(pt) < 12.0)) {
            anomalies.add(WeldAnomaly(position: pt, description: 'Irregular weave (Lack of fusion)', severity: 0.70));
          }
        }
      }
    }

    final double speedScore = (100.0 - (anomalies.length * 6.5)).clamp(15.0, 100.0);
    final double uniformityScore = anomalies.isEmpty ? 96.0 : (88.0 - anomalies.length * 5.0).clamp(25.0, 95.0);
    final double overallScore = ((speedScore * 0.5) + (uniformityScore * 0.5)).clamp(0.0, 100.0);

    final String feedback;
    if (anomalies.isEmpty) {
      feedback = 'EXCELLENT: Highly consistent speed and structural uniform deposition profiles (AWS D1.1 Grade A).';
    } else {
      feedback =
          'CRITICAL: Flagged ${anomalies.length} geometric errors along the path seams (Risk: ${anomalies.map((a) => a.description.split(" ").first).toSet().join(", ")}).';
    }

    final result = WeldScoreResult(
      speedConsistency: speedScore,
      profileUniformity: uniformityScore,
      overallScore: overallScore,
      gradeFeedback: feedback,
      anomalies: anomalies,
    );

    latestWeldEvaluation = result;
    latestWeldAnomalies = anomalies;
    notifyListeners();
    return result;
  }

  void toggleWeldOverlay() {
    showWeldOverlay = !showWeldOverlay;
    invalidateMeshCache();
    notifyListeners();
  }

  bool showDimensions = true;
  bool isLightBackground = true;
  bool get isLightMode => isLightBackground;
  bool showGlobalAxes = false;

  void toggleGlobalAxes() {
    showGlobalAxes = !showGlobalAxes;
    notifyListeners();
  }

  // Graphics, Shaders & Visual Preferences
  OnshapeGraphicsPreferences _graphicsPreferences = const OnshapeGraphicsPreferences(
    ambientOcclusion: 85.0,
    shininess: 75.0,
    keyLightIntensity: 3.2,
    antiAliasingQuality: AntiAliasingQuality.high,
  );
  OnshapeGraphicsPreferences get graphicsPreferences => _graphicsPreferences;
  set graphicsPreferences(OnshapeGraphicsPreferences prefs) {
    _graphicsPreferences = prefs;
    notifyListeners();
  }

  void updateGraphicsPreferences(OnshapeGraphicsPreferences Function(OnshapeGraphicsPreferences) update) {
    graphicsPreferences = update(_graphicsPreferences);
  }

  /// Magnetic attraction snapping pixel distance threshold (Item 1).
  /// Controls how close the mouse must be before magnetically snapping to a point.
  double _magneticSnapDistancePx = 10.0;
  double get magneticSnapDistancePx => _magneticSnapDistancePx;
  set magneticSnapDistancePx(double val) {
    _magneticSnapDistancePx = val.clamp(4.0, 30.0);
    notifyListeners();
  }

  void setMagneticSnapDistance(double val) {
    magneticSnapDistancePx = val;
  }

  OnshapeRenderMode _onshapeRenderMode = OnshapeRenderMode.shadedWithEdges;
  OnshapeRenderMode get onshapeRenderMode => _onshapeRenderMode;
  set onshapeRenderMode(OnshapeRenderMode mode) {
    if (_onshapeRenderMode != mode) {
      _onshapeRenderMode = mode;
      notifyListeners();
    }
  }

  bool isGraphicsPreferencesOpen = false;
  void toggleGraphicsPreferences() {
    isGraphicsPreferencesOpen = !isGraphicsPreferencesOpen;
    notifyListeners();
  }

  CadShadingStyle shadingStyle = CadShadingStyle.realisticPbr;
  void setShadingStyle(CadShadingStyle style) {
    shadingStyle = style;
    notifyListeners();
  }

  void setMaterialPreset(CadMaterialPresetType preset) {
    updateGraphicsPreferences((p) => p.copyWith(materialSettings: CadMaterialSettings.preset(preset)));
  }

  void toggleBackgroundMode() {
    isLightBackground = !isLightBackground;
    notifyListeners();
  }

  void toggleTheme() => toggleBackgroundMode();

  void setLightBackground(bool value) {
    if (isLightBackground != value) {
      isLightBackground = value;
      notifyListeners();
    }
  }

  void setLightMode(bool value) => setLightBackground(value);

  // Gizmo & Transformation
  GizmoMode gizmoMode = GizmoMode.translate;
  SketchUpToolMode activeToolMode = SketchUpToolMode.select;
  GizmoAxis activeGizmoAxis = GizmoAxis.none;
  GizmoAxis lockedAxis = GizmoAxis.none; // SketchUp Arrow-key axis restriction (X=Red, Y=Green, Z=Blue)
  CadPoint3D? lastRotateCenterPoint;
  GizmoAxis lastRotateAxis = GizmoAxis.z;
  double protractorSnapDeg = 15.0; // Standard SketchUp 15° protractor snapping
  double nudgeLinearStep = 1.0; // mm: 0.5, 1.0, 5.0, 10.0, 50.0
  double nudgeAngularStep = 5.0; // deg: 1.0, 5.0, 15.0, 45.0, 90.0
  bool snapToGrid = true;
  double gridStepMm = 10.0;
  bool get snapTo15Degrees => protractorSnapDeg > 0;

  // ===========================================================================
  // SKETCHUP MEASUREMENT UNITS & PRECISION (SS2)
  // ===========================================================================
  MeasurementUnitFormat unitFormat = MeasurementUnitFormat.decimal;
  MeasurementLengthUnit lengthUnit = MeasurementLengthUnit.millimeters;
  int lengthDisplayPrecision = 4; // 0.0000 mm default as in SS2
  MeasurementAreaUnit areaUnit = MeasurementAreaUnit.squareFeet;
  int areaDisplayPrecision = 2; // 0.00 ft² default as in SS2
  MeasurementVolumeUnit volumeUnit = MeasurementVolumeUnit.cubicFeet;
  int volumeDisplayPrecision = 2; // 0.00 ft³ default as in SS2
  bool enableLengthSnapping = false;
  double lengthSnapStep = 0.0001; // in active length unit
  bool displayUnitsFormat = true;
  bool forceDisplayInchesZero = false;

  MeasurementAngleUnit angleUnit = MeasurementAngleUnit.degrees;
  int angleDisplayPrecision = 1; // 0.0 default as in SS2
  bool enableAngleSnapping = true;
  double angleSnapDegrees = 15.0; // 15.0 default as in SS2

  bool showSketchupToolbar = true;
  bool showMovementToolbar = false;
  bool showStatusPill = false;
  bool showBottomQuickBar = false;
  bool showCanvasControls = false;
  bool showBottomTimeline = false;
  bool showLegacySketchHud = false;
  bool showLegacySketchPalette = false;

  bool showViewsToolbar = false;
  bool isViewsToolbarMinimized = false;

  bool showJointStyleToolbar = false;
  bool isJointToolbarMinimized = false;

  bool showQualityHud = false;
  bool isQualityCardMinimized = false;
  bool isAnomalySidebarMinimized = false;

  bool show3dNavigationBar = false;
  bool isCleanCanvasMode = false;

  void toggleViewsToolbar() {
    showViewsToolbar = !showViewsToolbar;
    notifyListeners();
  }

  void toggleViewsToolbarMinimized() {
    isViewsToolbarMinimized = !isViewsToolbarMinimized;
    notifyListeners();
  }

  void toggleJointStyleToolbar() {
    showJointStyleToolbar = !showJointStyleToolbar;
    notifyListeners();
  }

  void toggleJointToolbarMinimized() {
    isJointToolbarMinimized = !isJointToolbarMinimized;
    notifyListeners();
  }

  void toggleQualityHud() {
    showQualityHud = !showQualityHud;
    notifyListeners();
  }

  void toggleQualityCardMinimized() {
    isQualityCardMinimized = !isQualityCardMinimized;
    notifyListeners();
  }

  void toggleAnomalySidebarMinimized() {
    isAnomalySidebarMinimized = !isAnomalySidebarMinimized;
    notifyListeners();
  }

  void toggle3dNavigationBar() {
    show3dNavigationBar = !show3dNavigationBar;
    notifyListeners();
  }

  void toggleCleanCanvasMode() {
    isCleanCanvasMode = !isCleanCanvasMode;
    notifyListeners();
  }

  /// Calculates the live movement step (in mm) dictated by display precision or length snapping.
  /// (Requirement 3: "The display precision type should also control the object movement steps during moving the object or measurements")
  double get precisionMovementStepMm {
    if (enableLengthSnapping && lengthSnapStep > 0) {
      return lengthSnapStep * lengthUnit.toMmFactor;
    }
    final stepInUnit = math.pow(10.0, -lengthDisplayPrecision).toDouble();
    return stepInUnit * lengthUnit.toMmFactor;
  }

  /// Formats length in mm to the configured display precision and unit symbol.
  String formatLength(double lengthMm) {
    final valInUnit = lengthMm / lengthUnit.toMmFactor;
    final numStr = valInUnit.toStringAsFixed(lengthDisplayPrecision);
    if (displayUnitsFormat) {
      return '$numStr ${lengthUnit.symbol}';
    }
    return numStr;
  }

  /// Formats angle in degrees to configured display precision and angle unit.
  String formatAngle(double deg) {
    final val = angleUnit == MeasurementAngleUnit.radians ? (deg * math.pi / 180.0) : deg;
    final numStr = val.toStringAsFixed(angleDisplayPrecision);
    if (displayUnitsFormat) {
      return '$numStr${angleUnit.symbol}';
    }
    return numStr;
  }

  /// Parses user-entered length text (with or without unit suffix) to mm.
  double? parseLengthToMm(String text) {
    var s = text.trim().toLowerCase();
    for (final u in MeasurementLengthUnit.values) {
      s = s.replaceAll(u.symbol.toLowerCase(), '').replaceAll(u.label.toLowerCase(), '');
    }
    s = s.replaceAll('"', '').replaceAll("'", '');
    final val = double.tryParse(s.trim());
    if (val == null) return null;
    return val * lengthUnit.toMmFactor;
  }

  void setMeasurementSettings({
    MeasurementUnitFormat? format,
    MeasurementLengthUnit? length,
    int? lengthPrecision,
    MeasurementAreaUnit? area,
    int? areaPrecision,
    MeasurementVolumeUnit? volume,
    int? volumePrecision,
    bool? lengthSnapping,
    double? snapStep,
    bool? showUnitsFormat,
    bool? forceZeroInches,
    MeasurementAngleUnit? angle,
    int? anglePrecision,
    bool? angleSnapping,
    double? angleSnapStep,
  }) {
    if (format != null) unitFormat = format;
    if (length != null) lengthUnit = length;
    if (lengthPrecision != null) lengthDisplayPrecision = lengthPrecision;
    if (area != null) areaUnit = area;
    if (areaPrecision != null) areaDisplayPrecision = areaPrecision;
    if (volume != null) volumeUnit = volume;
    if (volumePrecision != null) volumeDisplayPrecision = volumePrecision;
    if (lengthSnapping != null) enableLengthSnapping = lengthSnapping;
    if (snapStep != null) lengthSnapStep = snapStep;
    if (showUnitsFormat != null) displayUnitsFormat = showUnitsFormat;
    if (forceZeroInches != null) forceDisplayInchesZero = forceZeroInches;
    if (angle != null) angleUnit = angle;
    if (anglePrecision != null) angleDisplayPrecision = anglePrecision;
    if (angleSnapping != null) {
      enableAngleSnapping = angleSnapping;
      protractorSnapDeg = angleSnapping ? (angleSnapStep ?? angleSnapDegrees) : 0.0;
    }
    if (angleSnapStep != null) {
      angleSnapDegrees = angleSnapStep;
      if (enableAngleSnapping) protractorSnapDeg = angleSnapStep;
    }
    notifyListeners();
  }

  void setLockedAxis(GizmoAxis axis) {
    lockedAxis = axis;
    notifyListeners();
  }

  void toggleLockedAxis(GizmoAxis axis) {
    lockedAxis = (lockedAxis == axis) ? GizmoAxis.none : axis;
    notifyListeners();
  }

  void clearLockedAxis() {
    lockedAxis = GizmoAxis.none;
    notifyListeners();
  }

  double snapRotationAngle(double deg) {
    if (protractorSnapDeg <= 0) return deg;
    return (deg / protractorSnapDeg).round() * protractorSnapDeg;
  }

  String? _lockedToolSelectionPartId;
  String? get lockedToolSelectionPartId => _lockedToolSelectionPartId;

  void unlockToolSelection() {
    _lockedToolSelectionPartId = null;
  }

  void setToolMode(SketchUpToolMode mode) {
    if (activeToolMode == mode && mode != SketchUpToolMode.select) {
      // Toggle off / deactivate: revert back to select mode
      activeToolMode = SketchUpToolMode.select;
      _lockedToolSelectionPartId = null;
      bridgeSourcePartId = null;
      setVcbState(label: 'Select', value: 'Ready', hint: 'Click or drag window to select');
      notifyListeners();
      return;
    }
    activeToolMode = mode;
    if (mode == SketchUpToolMode.select) {
      _lockedToolSelectionPartId = null;
    } else if (mode == SketchUpToolMode.move || mode == SketchUpToolMode.rotate) {
      _lockedToolSelectionPartId = doc.selectedPartId;
    }
    if (mode != SketchUpToolMode.bridge) {
      bridgeSourcePartId = null;
    }
    if (mode == SketchUpToolMode.move) {
      gizmoMode = GizmoMode.translate;
      setVcbState(label: 'Move', value: 'Ready', hint: 'Pick point to move from (Ctrl to copy)');
    } else if (mode == SketchUpToolMode.rotate) {
      gizmoMode = GizmoMode.rotate;
      setVcbState(label: 'Rotate', value: 'Ready', hint: 'Click 1 to place center, or use Arrow keys to lock plane');
    } else if (mode == SketchUpToolMode.select) {
      setVcbState(label: 'Select', value: 'Ready', hint: 'Click or drag window to select');
    } else if (mode == SketchUpToolMode.weld) {
      setVcbState(label: 'Weld Tool', value: 'Ready', hint: 'Drag across entity intersection to create weld joint');
    } else if (mode == SketchUpToolMode.magnetic) {
      setVcbState(label: 'Magnetic Tool', value: 'Ready', hint: 'Click surface to place magnetic spot, or link spots');
    }
    notifyListeners();
  }

  void setNudgeLinearStep(double step) {
    nudgeLinearStep = step;
    notifyListeners();
  }

  void setNudgeAngularStep(double step) {
    nudgeAngularStep = step;
    notifyListeners();
  }

  // 3D Model Movement Lock (locks orbit & pan during direct 3D sketching)
  bool is3DMovementLocked = false;

  void set3DMovementLocked(bool locked) {
    is3DMovementLocked = locked;
    notifyListeners();
  }

  // WYSIWYG Face Sketch Mode (OnShape / Fusion 360 Style)
  bool isSketchMode = false;
  String? sketchPartId;
  String? sketchFaceId;
  String activeSketchTool =
      'rectangle'; // 'rectangle', 'circle', 'line', 'polyline', 'select_entity', 'circle_hole', 'obround_slot', 'rect_cut', 'bend_line', 'rung_slot'
  String? selectedSketchFeatureId;
  double sketchToolParamWidth = 50.0; // mm
  double sketchToolParamHeight = 30.0; // mm
  double sketchToolParamRadius = 15.0; // mm
  bool isSketchConstructionMode = false;

  /// Active 3D Sketch Plane mapped to surface or datum
  CADSketchPlane? activeSketchPlane;

  /// All saved sketch planes across model surfaces
  final List<CADSketchPlane> savedSketchPlanes = [];

  /// Camera pivot override point (e.g. centering directly on the sketch plane origin)
  CadPoint3D? cameraPivotOverride;

  int _sketchCounter = 1;
  String generateNextSketchName() {
    return 'Sketch ${_sketchCounter++}';
  }

  /// Plane selection mode (triggered by "Create Sketch" / 'S' or plane tools)
  bool isPlaneSelectionMode = false;

  /// Identifier of currently hovered plane or part face during plane selection
  String? hoveredPlaneId;

  /// User-defined construction planes (Offset, Angle, Midplane, 3-Point)
  final List<CADSketchPlane> constructionPlanes = [];

  /// Visibility toggles for viewport 3D planes & triad
  bool showDatumPlanes = true;
  bool showConstructionPlanes = true;
  bool showOriginTriad = true;
  double defaultPlaneSizeMm = 450.0;

  /// Cached origin datum planes (XY Top, XZ Front, YZ Right)
  late final CADSketchPlane datumPlaneXY = AssemblySurfaceSketchEngine.createDatumPlane('XY', size: defaultPlaneSizeMm);
  late final CADSketchPlane datumPlaneXZ = AssemblySurfaceSketchEngine.createDatumPlane('XZ', size: defaultPlaneSizeMm);
  late final CADSketchPlane datumPlaneYZ = AssemblySurfaceSketchEngine.createDatumPlane('YZ', size: defaultPlaneSizeMm);

  /// Returns all available planes: Origin Datums + User Construction Planes + Saved Sketches
  List<CADSketchPlane> get allAvailablePlanes {
    final planes = <CADSketchPlane>[datumPlaneXY, datumPlaneXZ, datumPlaneYZ, ...constructionPlanes];
    for (final sp in savedSketchPlanes) {
      if (!planes.any((p) => p.id == sp.id)) {
        planes.add(sp);
      }
    }
    if (activeSketchPlane != null && !planes.any((p) => p.id == activeSketchPlane!.id)) {
      planes.add(activeSketchPlane!);
    }
    return planes;
  }

  // --- Fusion 360 Style Sketch Palette & Display Toggles (Phase 2) ---
  bool showSketchGrid = true;
  bool showSketchSnap = true;
  bool showSketchConstraints = true;
  bool showSketchDimensions = true;
  bool showSketchExpressions = true;
  bool showSketchProfileShading = true;
  bool isSketchSliceBody = false;

  // --- Geometry Projection Mode ('P' key) ---
  bool isProjectGeometryMode = false;
  String? hoveredProjectableEntityId;
  CadPoint3D? hoveredProjectablePoint;
  List<CadPoint3D>? hoveredProjectableEdge;

  void toggleSketchGrid() {
    showSketchGrid = !showSketchGrid;
    notifyListeners();
  }

  void toggleSketchSnap() {
    showSketchSnap = !showSketchSnap;
    notifyListeners();
  }

  void toggleSketchConstraints() {
    showSketchConstraints = !showSketchConstraints;
    notifyListeners();
  }

  void toggleSketchDimensions() {
    showSketchDimensions = !showSketchDimensions;
    notifyListeners();
  }

  void toggleSketchExpressions() {
    showSketchExpressions = !showSketchExpressions;
    notifyListeners();
  }

  void toggleSketchProfileShading() {
    showSketchProfileShading = !showSketchProfileShading;
    notifyListeners();
  }

  void toggleSketchConstructionMode() {
    if (activeSketchPlane != null && selectedSketchEntity != null) {
      _recordUndo();
      selectedSketchEntity!.isConstruction = !selectedSketchEntity!.isConstruction;
      isSketchConstructionMode = selectedSketchEntity!.isConstruction;
      for (final id in selectedSketchEntityIds) {
        final ent = activeSketchPlane!.primitives.where((p) => p.id == id).firstOrNull;
        if (ent != null && ent != selectedSketchEntity) {
          ent.isConstruction = selectedSketchEntity!.isConstruction;
        }
      }
      activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
      notifyListeners();
      return;
    }
    isSketchConstructionMode = !isSketchConstructionMode;
    notifyListeners();
  }

  void toggleSketchSliceBody() {
    isSketchSliceBody = !isSketchSliceBody;
    notifyListeners();
  }

  void enterProjectGeometryMode() {
    if (!isSketchMode) return;
    isProjectGeometryMode = true;
    hoveredProjectableEntityId = null;
    notifyListeners();
  }

  void exitProjectGeometryMode() {
    isProjectGeometryMode = false;
    hoveredProjectableEntityId = null;
    hoveredProjectablePoint = null;
    hoveredProjectableEdge = null;
    notifyListeners();
  }

  void toggleProjectGeometryMode() {
    if (isProjectGeometryMode) {
      exitProjectGeometryMode();
    } else {
      enterProjectGeometryMode();
    }
  }

  void setHoveredProjectable({String? entityId, CadPoint3D? point, List<CadPoint3D>? edge}) {
    hoveredProjectableEntityId = entityId;
    hoveredProjectablePoint = point;
    hoveredProjectableEdge = edge;
    notifyListeners();
  }

  /// Projects a 3D line/edge (2 CadPoint3D points in world space) onto the active sketch plane
  CADLineEntity? project3DEdgeToActivePlane(CadPoint3D p1, CadPoint3D p2, {String? sourceId}) {
    if (activeSketchPlane == null) return null;
    final loc1 = activeSketchPlane!.toLocal(vm_math.Vector3(p1.x, p1.y, p1.z));
    final loc2 = activeSketchPlane!.toLocal(vm_math.Vector3(p2.x, p2.y, p2.z));

    final line = CADLineEntity(id: 'proj_edge_${DateTime.now().millisecondsSinceEpoch}', start: loc1, end: loc2, isProjected: true, sourceEntityId: sourceId);
    addPrimitiveEntityToActivePlane(line);
    return line;
  }

  /// Projects a 3D vertex/point onto the active sketch plane
  CADCircleEntity? project3DVertexToActivePlane(CadPoint3D p, {String? sourceId}) {
    if (activeSketchPlane == null) return null;
    final loc = activeSketchPlane!.toLocal(vm_math.Vector3(p.x, p.y, p.z));

    final circle = CADCircleEntity(
      id: 'proj_pt_${DateTime.now().millisecondsSinceEpoch}',
      center: loc,
      radius: 2.0,
      isProjected: true,
      isConstruction: true,
      sourceEntityId: sourceId,
    );
    addPrimitiveEntityToActivePlane(circle);
    return circle;
  }

  /// Projects all boundary edges of a 3D polygon face onto the active sketch plane
  List<CADLineEntity> project3DFaceToActivePlane(CadFoldedPolygon3D polygon, {String? sourceId}) {
    if (activeSketchPlane == null || polygon.vertices.length < 2) return [];
    final results = <CADLineEntity>[];
    for (int i = 0; i < polygon.vertices.length; i++) {
      final p1 = polygon.vertices[i];
      final p2 = polygon.vertices[(i + 1) % polygon.vertices.length];
      final line = project3DEdgeToActivePlane(p1, p2, sourceId: '${sourceId ?? polygon.faceId}_edge_$i');
      if (line != null) results.add(line);
    }
    return results;
  }

  /// Currently selected parametric 2D primitive entity on active plane
  CADPrimitiveEntity? selectedSketchEntity;

  /// Parametric feature history tree
  final List<CADHistoryItem> sketchFeatureHistory = [];

  /// Real-time inferencing guides for cursor
  List<CADInferenceMatch> currentInferenceGuides = [];

  /// Hovered/snapped local position on active sketch plane
  Offset? activePlaneHoverLocal;
  vm_math.Vector3? activePlaneHoverWorld;

  /// Profile loop validation status for active sketch
  ValidationResult? activeSketchValidation;

  /// Interactive multi-step sketch drawing state (Phase 3)
  Offset? sketchInteractiveStartPoint;
  Offset? sketchInteractiveMidPoint;
  final List<Offset> sketchPolylinePoints = [];

  void setSketchInteractiveStartPoint(Offset? pt) {
    sketchInteractiveStartPoint = pt;
    notifyListeners();
  }

  void setInteractiveSketchStart(Offset? pt) => setSketchInteractiveStartPoint(pt);

  void setSketchInteractiveMidPoint(Offset? pt) {
    sketchInteractiveMidPoint = pt;
    notifyListeners();
  }

  void setInteractiveSketchMid(Offset? pt) => setSketchInteractiveMidPoint(pt);

  void addSketchPolylinePoint(Offset pt) {
    sketchPolylinePoints.add(pt);
    notifyListeners();
  }

  void clearSketchInteractiveState() {
    sketchInteractiveStartPoint = null;
    sketchInteractiveMidPoint = null;
    sketchPolylinePoints.clear();
    notifyListeners();
  }

  @override
  bool isExportingFile = false;

  void selectSketchFeature(String? featureId) {
    selectedSketchFeatureId = featureId;
    if (featureId != null && activeSketchPlane != null) {
      selectedSketchEntity = activeSketchPlane!.primitives.where((p) => p.id == featureId).firstOrNull;
    } else if (featureId == null) {
      selectedSketchEntity = null;
    }
    notifyListeners();
  }

  final Set<String> selectedSketchEntityIds = {};
  CadConstraint? selectedSketchConstraint;
  SketchConstraintSolverResult? lastConstraintSolverResult;

  int get sketchDegreesOfFreedom => lastConstraintSolverResult?.totalDegreesOfFreedom ?? 0;
  bool get isSketchFullyConstrained => (activeSketchPlane?.primitives.isNotEmpty ?? false) && sketchDegreesOfFreedom == 0;

  void toggleSketchEntityMultiSelection(String entityId) {
    if (selectedSketchEntityIds.contains(entityId)) {
      selectedSketchEntityIds.remove(entityId);
    } else {
      selectedSketchEntityIds.add(entityId);
    }
    for (final p in activeSketchPlane?.primitives ?? <CADPrimitiveEntity>[]) {
      p.isSelected = selectedSketchEntityIds.contains(p.id);
    }
    if (selectedSketchEntityIds.isNotEmpty) {
      selectedSketchEntity = activeSketchPlane?.primitives.where((p) => p.id == selectedSketchEntityIds.last).firstOrNull;
      selectedSketchFeatureId = selectedSketchEntity?.id;
    } else {
      selectedSketchEntity = null;
      selectedSketchFeatureId = null;
    }
    notifyListeners();
  }

  void solveSketchConstraints() {
    if (activeSketchPlane == null) return;
    lastConstraintSolverResult = AssemblySketchConstraintSolver.solve(activeSketchPlane!);
    notifyListeners();
  }

  void applySketchConstraint(CadConstraintType type, {List<String>? targetEntityIds}) {
    if (activeSketchPlane == null) return;
    final ids =
        targetEntityIds ??
        (selectedSketchEntityIds.isNotEmpty ? selectedSketchEntityIds.toList() : (selectedSketchEntity != null ? [selectedSketchEntity!.id] : <String>[]));

    if (ids.isEmpty) return;
    _recordUndo();

    final constraint = CadConstraint(id: 'c_${type.name}_${DateTime.now().millisecondsSinceEpoch}', type: type, entityIds: ids);
    activeSketchPlane!.constraints.add(constraint);
    solveSketchConstraints();

    final dofs = sketchDegreesOfFreedom;
    setVcbState(
      label: 'Constraint: ${type.label} (${type.symbol})',
      value: dofs == 0 ? 'Fully Constrained (0 DOFs) 🔒' : '$dofs DOFs Remaining',
      hint: dofs == 0 ? 'Profile turns black - locked' : 'Add more constraints or dimensions to fully constrain',
    );
    notifyListeners();
  }

  void removeSketchConstraint(String constraintId) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    activeSketchPlane!.constraints.removeWhere((c) => c.id == constraintId);
    if (selectedSketchConstraint?.id == constraintId) {
      selectedSketchConstraint = null;
    }
    solveSketchConstraints();
    notifyListeners();
  }

  void selectSketchPrimitive(CADPrimitiveEntity? entity) {
    selectedSketchEntity = entity;
    selectedSketchFeatureId = entity?.id;
    selectedSketchEntityIds.clear();
    if (entity != null) selectedSketchEntityIds.add(entity.id);
    for (final p in activeSketchPlane?.primitives ?? <CADPrimitiveEntity>[]) {
      p.isSelected = (p.id == entity?.id);
    }
    notifyListeners();
  }

  // --- 3D Feature Extrusion & Boolean Operations (Phase 5) ---
  bool isExtrudeMode = false;
  AssemblyExtrudeParams extrudeParams = const AssemblyExtrudeParams();
  bool isExtrudeArrowDragging = false;
  Offset? extrudeDragStartScreen;
  double extrudeDragStartDistance = 25.0;

  void openExtrudeDialog() {
    if (activeSketchPlane == null && allAvailablePlanes.isNotEmpty) {
      activeSketchPlane = allAvailablePlanes.first;
    }
    if (activeSketchPlane != null && extrudeParams.profileEntityIds.isEmpty) {
      final selectedIds = activeSketchPlane!.primitives.where((p) => p.isSelected).map((p) => p.id).toList();
      if (selectedIds.isNotEmpty) {
        extrudeParams = extrudeParams.copyWith(profileEntityIds: selectedIds);
      } else if (activeSketchPlane!.primitives.isNotEmpty) {
        extrudeParams = extrudeParams.copyWith(profileEntityIds: [activeSketchPlane!.primitives.first.id]);
      }
    }
    isExtrudeMode = true;
    final dist = extrudeParams.distanceMm;
    setVcbState(label: 'Extrude Feature (E)', value: '${dist.toStringAsFixed(1)} mm', hint: 'Adjust distance, taper angle, or drag 3D arrow manipulator');
    notifyListeners();
  }

  void closeExtrudeDialog() {
    isExtrudeMode = false;
    isExtrudeArrowDragging = false;
    extrudeDragStartScreen = null;
    setVcbState(label: 'Measurements', value: '', hint: 'Ready');
    notifyListeners();
  }

  void toggleExtrudeMode() {
    if (isExtrudeMode) {
      closeExtrudeDialog();
    } else {
      openExtrudeDialog();
    }
  }

  void updateExtrudeParams(AssemblyExtrudeParams newParams) {
    extrudeParams = newParams;
    setVcbState(
      label: 'Extrude (${newParams.operation.label})',
      value: newParams.direction == AssemblyExtrudeDirection.symmetric
          ? '±${newParams.distanceMm.abs().toStringAsFixed(1)} mm'
          : '${newParams.distanceMm.toStringAsFixed(1)} mm',
      hint: 'Taper: ${newParams.taperAngleDeg.toStringAsFixed(1)}° | Direction: ${newParams.direction.label}',
    );
    notifyListeners();
  }

  void updateExtrudeDistance(double distanceMm) {
    extrudeParams = extrudeParams.copyWith(distanceMm: distanceMm);
    setVcbState(
      label: 'Extrude Distance',
      value: extrudeParams.direction == AssemblyExtrudeDirection.symmetric
          ? '±${distanceMm.abs().toStringAsFixed(1)} mm'
          : '${distanceMm.toStringAsFixed(1)} mm',
      hint: 'Type distance or drag arrow manipulator',
    );
    notifyListeners();
  }

  void executeExtrudeFeature() {
    if (activeSketchPlane == null) return;
    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(activeSketchPlane!);
    final validation = CADProfileValidator.validateProfile(segments);
    if (!validation.isValidClosedLoop || validation.orderedPathVertices.length < 3) {
      setVcbState(label: 'Extrude Failed', value: 'Unclosed Profile', hint: 'Ensure sketch forms a closed watertight loop before extruding');
      notifyListeners();
      return;
    }

    _recordUndo();

    final targetPart = doc.parts.where((p) => p.id == (activeSketchPlane!.targetPartId ?? sketchPartId)).firstOrNull ?? selectedPart;

    final result = AssemblyExtrudeEngine.executeExtrusion(
      doc: doc,
      plane: activeSketchPlane!,
      profilePoints: validation.orderedPathVertices,
      params: extrudeParams,
      targetPart: targetPart,
    );

    if (result.isSuccess) {
      sketchFeatureHistory.add(
        CADHistoryItem(
          id: 'extrude_${DateTime.now().millisecondsSinceEpoch}',
          name: '${extrudeParams.operation.label} Extrusion (${extrudeParams.distanceMm.toStringAsFixed(1)}mm)',
          timestamp: DateTime.now(),
          referencePlane: activeSketchPlane,
          featureType: extrudeParams.operation == AssemblyExtrudeOperation.cut ? FeatureType.cut : FeatureType.extrude,
          modificationDepth: extrudeParams.distanceMm,
        ),
      );

      recordTimelineFeature(
        name: '${extrudeParams.operation.label} (${extrudeParams.distanceMm.toStringAsFixed(1)}mm)',
        type: extrudeParams.operation == AssemblyExtrudeOperation.cut ? AssemblyTimelineFeatureType.cut : AssemblyTimelineFeatureType.extrude,
        entityId: result.createdPart?.id ?? targetPart?.id,
        parameters: {'distance': extrudeParams.distanceMm, 'operation': extrudeParams.operation.name},
      );

      invalidateMeshCache();
      if (result.createdPart != null) {
        syncComponentInstances(result.createdPart!.id);
      }
      closeExtrudeDialog();
      setVcbState(label: 'Feature Created', value: result.message, hint: 'Solid geometry updated in assembly document');
    } else {
      setVcbState(label: 'Extrude Error', value: result.message, hint: 'Check profile geometry and try again');
    }

    notifyListeners();
  }

  // --- Parametric Design History Timeline & CAD Settings (Phase 6) ---
  final List<AssemblyTimelineItem> timelineItems = [];
  int timelineRollbackIndex = 0;
  AssemblyCadSettings cadSettings = const AssemblyCadSettings();
  bool isCadSettingsOpen = false;

  void recordTimelineFeature({required String name, required AssemblyTimelineFeatureType type, String? entityId, Map<String, dynamic> parameters = const {}}) {
    final item = AssemblyTimelineItem(
      id: 'timeline_${DateTime.now().millisecondsSinceEpoch}_${timelineItems.length}',
      name: name,
      type: type,
      entityId: entityId,
      parameters: parameters,
      isSuppressed: false,
    );
    timelineItems.add(item);
    timelineRollbackIndex = timelineItems.length;
    notifyDocChanged();
  }

  void setTimelineRollbackIndex(int index) {
    timelineRollbackIndex = index.clamp(0, timelineItems.length);
    for (int i = 0; i < timelineItems.length; i++) {
      timelineItems[i].isSuppressed = (i >= timelineRollbackIndex);
    }
    // Update part/plane visibility according to rollback suppression
    for (int i = 0; i < timelineItems.length; i++) {
      final item = timelineItems[i];
      final isSuppressed = item.isSuppressed;
      if (item.entityId != null) {
        final part = doc.parts.where((p) => p.id == item.entityId).firstOrNull;
        if (part != null) {
          part.isVisible = !isSuppressed;
        }
        final plane = constructionPlanes.where((p) => p.id == item.entityId).firstOrNull;
        if (plane != null) {
          plane.isVisible = !isSuppressed;
        }
      }
    }
    setVcbState(
      label: 'Timeline Rollback',
      value: '$timelineRollbackIndex / ${timelineItems.length} active',
      hint: 'Step or drag marker to navigate design history',
    );
    notifyListeners();
  }

  void rollbackToStart() => setTimelineRollbackIndex(0);

  void rollbackStepBack() {
    if (timelineRollbackIndex > 0) setTimelineRollbackIndex(timelineRollbackIndex - 1);
  }

  void rollbackStepForward() {
    if (timelineRollbackIndex < timelineItems.length) setTimelineRollbackIndex(timelineRollbackIndex + 1);
  }

  void rollbackToEnd() => setTimelineRollbackIndex(timelineItems.length);

  void editTimelineFeature(AssemblyTimelineItem item) {
    switch (item.type) {
      case AssemblyTimelineFeatureType.sketch:
        if (item.entityId != null) {
          final targetPlane = allAvailablePlanes.where((p) => p.id == item.entityId).firstOrNull;
          if (targetPlane != null) {
            selectPlaneForSketch(targetPlane);
            setVcbState(label: 'Edit Sketch', value: targetPlane.name, hint: 'Parametric sketch activated for editing');
          }
        }
        break;
      case AssemblyTimelineFeatureType.extrude:
      case AssemblyTimelineFeatureType.cut:
        final dist = (item.parameters['distance'] as num?)?.toDouble() ?? 25.0;
        final opName = item.parameters['operation'] as String?;
        final op = opName == 'cut' ? AssemblyExtrudeOperation.cut : AssemblyExtrudeOperation.newBody;
        extrudeParams = extrudeParams.copyWith(distanceMm: dist, operation: op);
        openExtrudeDialog();
        break;
      case AssemblyTimelineFeatureType.constructionPlane:
        if (item.entityId != null) {
          final targetPlane = constructionPlanes.where((pl) => pl.id == item.entityId).firstOrNull;
          if (targetPlane != null) {
            activeSketchPlane = targetPlane;
            alignCameraToActivePlaneNormal();
            setVcbState(label: 'Construction Plane', value: targetPlane.name, hint: 'Plane selected from timeline');
            notifyListeners();
          }
        }
        break;
      case AssemblyTimelineFeatureType.originPlane:
      case AssemblyTimelineFeatureType.weld:
        break;
    }
  }

  void updateCadSettings(AssemblyCadSettings newSettings) {
    cadSettings = newSettings;
    notifyListeners();
  }

  void toggleCadSettingsDialog() {
    isCadSettingsOpen = !isCadSettingsOpen;
    notifyListeners();
  }

  void openCadSettingsDialog() {
    isCadSettingsOpen = true;
    notifyListeners();
  }

  void closeCadSettingsDialog() {
    isCadSettingsOpen = false;
    notifyListeners();
  }

  AssemblyStudioViewModel() {
    doc = AssemblyDocument(id: _generateId('doc'), title: 'TruFold Cable Ladder Assembly');
    loadStandardLadderDemo();
  }

  // -------------------------------------------------------------
  // Undo / Redo
  // -------------------------------------------------------------
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _recordUndo() {
    documentVersion++;
    final stateJson = jsonEncode(_serializeDocument());
    _undoStack.add(stateJson);
    if (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Records an undo checkpoint for interactive actions like part dragging.
  void recordHistory() {
    _recordUndo();
  }

  /// Triggers a document change notification to all listeners.
  void notifyDocChanged() {
    documentVersion++;
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    documentVersion++;
    final currentState = jsonEncode(_serializeDocument());
    _redoStack.add(currentState);

    final prevState = _undoStack.removeLast();
    _deserializeDocument(jsonDecode(prevState) as Map<String, dynamic>);
    setVcbState(label: 'Undo', value: 'Action Undone', hint: 'Ctrl+Y to redo');
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    documentVersion++;
    final currentState = jsonEncode(_serializeDocument());
    _undoStack.add(currentState);

    final nextState = _redoStack.removeLast();
    _deserializeDocument(jsonDecode(nextState) as Map<String, dynamic>);
    setVcbState(label: 'Redo', value: 'Action Redone', hint: 'Ctrl+Z to undo');
    notifyListeners();
  }

  Map<String, dynamic> _serializeDocument() {
    return {
      'id': doc.id,
      'title': doc.title,
      'selectedPartId': doc.selectedPartId,
      'selectedFaceId': doc.selectedFaceId,
      'selectedPartIds': doc.selectedPartIds.toList(),
      'selectedWeldId': doc.selectedWeldId,
      'parts': doc.parts
          .map(
            (p) => {
              'id': p.id,
              'name': p.name,
              'type': p.type.name,
              'posX': p.position.x,
              'posY': p.position.y,
              'posZ': p.position.z,
              'rotX': p.rotationDeg.x,
              'rotY': p.rotationDeg.y,
              'rotZ': p.rotationDeg.z,
              'length': p.length,
              'height': p.height,
              'flangeWidth': p.flangeWidth,
              'thickness': p.thickness,
              'isFlangeOutward': p.isFlangeOutward,
              'color': p.color.toARGB32(),
              'segments': p.segments.map((s) => s.toJson()).toList(),
              'sketches': p.sketches.map((sk) => sk.toJson()).toList(),
              'weldedToPartIds': p.weldedToPartIds,
              'magneticSpots': p.magneticSpots.map((ms) => ms.toJson()).toList(),
              'magneticallyLinkedPartIds': p.magneticallyLinkedPartIds,
              'parentPartId': p.parentPartId,
              'matedSlotEntityId': p.matedSlotEntityId,
              'mateStyle': p.mateStyle,
              'isRungUpsideDown': p.isRungUpsideDown,
              'hingeAngleDeg': p.hingeAngleDeg,
              'jointType': p.jointType?.name,
              'groupId': p.groupId,
              'groupName': p.groupName,
              'componentDefinitionId': p.componentDefinitionId,
            },
          )
          .toList(),
      'welds': doc.welds.map((w) => w.toJson()).toList(),
      'magneticJoints': doc.magneticJoints.map((mj) => mj.toJson()).toList(),
    };
  }

  void _deserializeDocument(Map<String, dynamic> json) {
    doc.id = json['id'] as String;
    doc.title = json['title'] as String;
    doc.selectedPartId = json['selectedPartId'] as String?;
    doc.selectedFaceId = json['selectedFaceId'] as String?;
    doc.selectedPartIds = (json['selectedPartIds'] as List<dynamic>?)?.map((e) => e as String).toSet() ?? {};
    doc.selectedWeldId = json['selectedWeldId'] as String?;

    final partsList = <AssemblyPart>[];
    for (final pj in (json['parts'] as List<dynamic>)) {
      final pmap = pj as Map<String, dynamic>;
      partsList.add(
        AssemblyPart(
          id: pmap['id'] as String,
          name: pmap['name'] as String,
          type: AssemblyPartType.values.byName(pmap['type'] as String),
          position: CadPoint3D((pmap['posX'] as num).toDouble(), (pmap['posY'] as num).toDouble(), (pmap['posZ'] as num).toDouble()),
          rotationDeg: CadPoint3D((pmap['rotX'] as num).toDouble(), (pmap['rotY'] as num).toDouble(), (pmap['rotZ'] as num).toDouble()),
          length: (pmap['length'] as num).toDouble(),
          height: (pmap['height'] as num).toDouble(),
          flangeWidth: (pmap['flangeWidth'] as num).toDouble(),
          thickness: (pmap['thickness'] as num).toDouble(),
          isFlangeOutward: pmap['isFlangeOutward'] as bool? ?? false,
          color: Color(pmap['color'] as int),
          segments: (pmap['segments'] as List<dynamic>?)?.map((s) => RailSegmentDefinition.fromJson(s as Map<String, dynamic>)).toList(),
          sketches: (pmap['sketches'] as List<dynamic>?)?.map((sk) => AssemblySketchFeature.fromJson(sk as Map<String, dynamic>)).toList(),
          weldedToPartIds: (pmap['weldedToPartIds'] as List<dynamic>?)?.map((id) => id as String).toList(),
          magneticSpots: (pmap['magneticSpots'] as List<dynamic>?)?.map((ms) => AssemblyMagneticSpot.fromJson(ms as Map<String, dynamic>)).toList(),
          magneticallyLinkedPartIds: (pmap['magneticallyLinkedPartIds'] as List<dynamic>?)?.map((id) => id as String).toList(),
          parentPartId: pmap['parentPartId'] as String?,
          matedSlotEntityId: pmap['matedSlotEntityId'] as String?,
          mateStyle: pmap['mateStyle'] as String? ?? 'passThrough',
          isRungUpsideDown: pmap['isRungUpsideDown'] as bool? ?? false,
          hingeAngleDeg: (pmap['hingeAngleDeg'] as num?)?.toDouble() ?? 0.0,
          jointType: pmap['jointType'] != null ? AssemblyJointType.values.byName(pmap['jointType'] as String) : null,
          groupId: pmap['groupId'] as String?,
          groupName: pmap['groupName'] as String?,
          componentDefinitionId: pmap['componentDefinitionId'] as String?,
        ),
      );
    }
    doc.parts = partsList;

    final weldsList = <AssemblyWeldJoint>[];
    for (final wj in (json['welds'] as List<dynamic>)) {
      weldsList.add(AssemblyWeldJoint.fromJson(wj as Map<String, dynamic>));
    }
    doc.welds = weldsList;

    final magneticJointsList = <AssemblyMagneticJoint>[];
    if (json['magneticJoints'] != null) {
      for (final mj in (json['magneticJoints'] as List<dynamic>)) {
        magneticJointsList.add(AssemblyMagneticJoint.fromJson(mj as Map<String, dynamic>));
      }
    }
    doc.magneticJoints = magneticJointsList;
  }

  // -------------------------------------------------------------
  // Selection (Whole Part Group & Multi-Part Selection)
  // -------------------------------------------------------------
  AssemblyPart? get selectedPart => doc.selectedPart;
  Set<String> get selectedPartIds => doc.selectedPartIds;
  List<AssemblyPart> get selectedParts => doc.selectedParts;
  String? get selectedWeldId => doc.selectedWeldId;
  AssemblyWeldJoint? get selectedWeld => doc.selectedWeld;

  int _groupCounter = 1;
  int get nextGroupNumber => _groupCounter;

  void togglePartSelection(String partId) {
    if (_lockedToolSelectionPartId != null) {
      return;
    }
    if (doc.selectedPartIds.contains(partId)) {
      doc.selectedPartIds.remove(partId);
      if (doc.selectedPartId == partId) {
        doc.selectedPartId = doc.selectedPartIds.isNotEmpty ? doc.selectedPartIds.first : null;
      }
    } else {
      doc.selectedPartIds.add(partId);
      doc.selectedPartId = partId;
    }
    doc.selectedWeldId = null;
    doc.selectedFaceId = null;
    notifyListeners();
  }

  /// Adds a single part (or its group) to multi-selection (Ctrl+Click).
  void addToSelection(String partId) {
    if (_lockedToolSelectionPartId != null) {
      return;
    }
    final target = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (target != null && target.groupId != null) {
      final grpIds = doc.parts.where((p) => p.groupId == target.groupId).map((p) => p.id);
      doc.selectedPartIds.addAll(grpIds);
    } else {
      doc.selectedPartIds.add(partId);
    }
    doc.selectedPartId = partId;
    doc.selectedWeldId = null;
    doc.selectedFaceId = null;
    notifyListeners();
  }

  /// Removes a single part (or its group) from multi-selection (Shift+Click).
  void removeFromSelection(String partId) {
    if (_lockedToolSelectionPartId != null) {
      return;
    }
    final target = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (target != null && target.groupId != null) {
      final grpIds = doc.parts.where((p) => p.groupId == target.groupId).map((p) => p.id);
      doc.selectedPartIds.removeAll(grpIds);
    } else {
      doc.selectedPartIds.remove(partId);
    }
    if (doc.selectedPartId == partId) {
      doc.selectedPartId = doc.selectedPartIds.isNotEmpty ? doc.selectedPartIds.first : null;
    }
    notifyListeners();
  }

  void selectPart(String? id, {bool multiSelect = false}) {
    if (multiSelect && id != null) {
      togglePartSelection(id);
      return;
    }
    if (id == null) {
      doc.selectedPartId = null;
      doc.selectedPartIds = {};
    } else {
      final target = doc.parts.where((p) => p.id == id).firstOrNull;
      if (target != null && target.groupId != null) {
        // Grouped parts act virtually as a single part!
        final grpIds = doc.parts.where((p) => p.groupId == target.groupId).map((p) => p.id).toSet();
        doc.selectedPartIds = grpIds;
        doc.selectedPartId = id;
      } else {
        doc.selectedPartId = id;
        doc.selectedPartIds = {id};
      }
    }
    doc.selectedWeldId = null;
    doc.selectedFaceId = null;
    notifyListeners();
  }

  /// When a polygon in 3D is clicked:
  /// - If it's a weld bead (faceId starts with 'weld_'), select the weld joint directly.
  /// - If it's a part face, select the whole part as a group, supporting Shift/Ctrl multi-selection!
  /// Maps a 3D polygon face identifier to its owning AssemblyPart.
  /// Handles prefixes (e.g. RIM_), aliases (e.g. left_rail vs rail_left), and suffixes.
  AssemblyPart? findPartForFaceId(String faceId) {
    // 1. Direct match or startsWith part id
    for (final p in doc.parts) {
      if (faceId == p.id || faceId.startsWith('${p.id}_')) {
        return p;
      }
    }
    // 2. Contains part id (e.g. RIM_rung_2_front_lip, RIM_rung_1_cap_left)
    for (final p in doc.parts) {
      if (faceId.contains(p.id)) {
        return p;
      }
    }
    // 3. Rail aliases (left_rail_... -> rail_left, right_rail_... -> rail_right)
    if (faceId.contains('left_rail')) {
      return doc.parts.where((p) => p.id == 'rail_left').firstOrNull;
    }
    if (faceId.contains('right_rail')) {
      return doc.parts.where((p) => p.id == 'rail_right').firstOrNull;
    }
    return null;
  }

  /// When a polygon in 3D is clicked:
  /// - If it's a weld bead (faceId starts with 'weld_'), select the weld joint directly.
  /// - If it's a part face, select the whole part as a group, supporting Shift/Ctrl multi-selection!
  void selectFace(String? faceId, {bool multiSelect = false}) {
    if (_lockedToolSelectionPartId != null) {
      return;
    }
    if (faceId != null) {
      // 1. Check if clicked directly on a weld bead/joint in 3D
      if (faceId.startsWith('weld_')) {
        final weldId = faceId.substring('weld_'.length);
        selectWeld(weldId);
        return;
      }

      // 2. Clicked on a part
      final hitPart = findPartForFaceId(faceId);
      if (hitPart != null) {
        if (multiSelect) {
          togglePartSelection(hitPart.id);
        } else {
          selectPart(hitPart.id);
        }
        return;
      }
    }
    if (!multiSelect) {
      clearSelection();
    }
  }

  /// Groups currently selected parts into a virtual group that moves as a single unit.
  /// Grouping preserves each part's current position and state (no physical welding/sticking).
  String? groupSelectedParts({String? name}) {
    if (doc.selectedPartIds.length < 2) return null;
    _recordUndo();

    final newGroupId = 'grp_${DateTime.now().millisecondsSinceEpoch}';
    final groupLabel = name ?? 'Group $_groupCounter';
    _groupCounter++;

    for (final part in doc.parts) {
      if (doc.selectedPartIds.contains(part.id)) {
        part.groupId = newGroupId;
        part.groupName = groupLabel;
      }
    }
    notifyListeners();
    return newGroupId;
  }

  /// Ungroups the selected parts, removing their virtual group binding.
  void ungroupSelectedParts() {
    if (doc.selectedPartIds.isEmpty) return;
    _recordUndo();

    final targetGroupIds = <String>{};
    for (final part in doc.parts) {
      if (doc.selectedPartIds.contains(part.id) && part.groupId != null) {
        targetGroupIds.add(part.groupId!);
      }
    }

    for (final part in doc.parts) {
      if (targetGroupIds.contains(part.groupId) || doc.selectedPartIds.contains(part.id)) {
        part.groupId = null;
        part.groupName = null;
      }
    }
    notifyListeners();
  }

  bool get canGroupSelectedParts => doc.selectedPartIds.length >= 2;

  bool get canUngroupSelectedParts => doc.parts.any((p) => doc.selectedPartIds.contains(p.id) && p.groupId != null);

  void selectWeld(String? weldId) {
    if (doc.selectedWeldId == weldId) return;
    doc.selectedWeldId = weldId;
    doc.selectedPartId = null;
    doc.selectedPartIds.clear();
    doc.selectedFaceId = null;
    invalidateMeshCache();
    notifyListeners();
  }

  void deleteSelectedWeld() {
    if (doc.selectedWeldId != null) {
      breakWeld(doc.selectedWeldId!);
      doc.selectedWeldId = null;
    }
  }

  void selectAllParts() {
    doc.selectedPartIds = doc.parts.map((p) => p.id).toSet();
    doc.selectedPartId = doc.parts.isNotEmpty ? doc.parts.first.id : null;
    doc.selectedWeldId = null;
    doc.selectedFaceId = null;
    notifyListeners();
  }

  void clearSelection({bool force = false}) {
    if (!force && _lockedToolSelectionPartId != null) {
      return;
    }
    doc.selectedPartId = null;
    doc.selectedPartIds.clear();
    doc.selectedWeldId = null;
    doc.selectedFaceId = null;
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Advanced Multi-Part Touching-Point Weld / Link Engine
  // -------------------------------------------------------------
  /// Evaluates 3D extents of multi-selected parts, calculates touching / contact points,
  /// and automatically welds/joins them at their contact locations.
  int weldSelectedPartsAtContactPoints({double contactToleranceMm = 80.0}) {
    final targets = doc.selectedParts;
    if (targets.length < 2) return 0;

    _recordUndo();
    int weldsCreated = 0;

    for (int i = 0; i < targets.length; i++) {
      for (int j = i + 1; j < targets.length; j++) {
        final pA = targets[i];
        final pB = targets[j];

        final contact = _calculateContactPoint(pA, pB, toleranceMm: contactToleranceMm);
        if (contact != null) {
          weldParts(pA.id, pB.id, weldPoint: contact);
          weldsCreated++;
        }
      }
    }

    notifyListeners();
    return weldsCreated;
  }

  /// Calculates the 3D contact point between two parts by analyzing their spatial bounding extents.
  CadPoint3D? _calculateContactPoint(AssemblyPart pA, AssemblyPart pB, {double toleranceMm = 80.0}) {
    final minXA = pA.position.x;
    final maxXA = pA.position.x + pA.length;
    final minYA = pA.position.y;
    final maxYA = pA.position.y + pA.flangeWidth;
    final minZA = pA.position.z;
    final maxZA = pA.position.z + pA.height;

    final minXB = pB.position.x;
    final maxXB = pB.position.x + pB.length;
    final minYB = pB.position.y;
    final maxYB = pB.position.y + pB.flangeWidth;
    final minZB = pB.position.z;
    final maxZB = pB.position.z + pB.height;

    // Check if parts are in proximity along all 3 axes within tolerance
    final overlapX = (math.min(maxXA, maxXB) + toleranceMm >= math.max(minXA, minXB));
    final overlapY = (math.min(maxYA, maxYB) + toleranceMm >= math.max(minYA, minYB));
    final overlapZ = (math.min(maxZA, maxZB) + toleranceMm >= math.max(minZA, minZB));

    if (!overlapX || !overlapY || !overlapZ) return null;

    final contactX = (math.max(minXA, minXB) + math.min(maxXA, maxXB)) / 2.0;
    final contactY = (math.max(minYA, minYB) + math.min(maxYA, maxYB)) / 2.0;
    final contactZ = (math.max(minZA, minZB) + math.min(maxZA, maxZB)) / 2.0;

    return CadPoint3D(contactX, contactY, contactZ);
  }

  /// Welds two parts at a specific 3D mouse click location or designated port.
  void weldAtPoint(CadPoint3D worldPoint, String partAId, String partBId, {String description = 'MIG Fillet Weld', double weldSizeMm = 6.0}) {
    weldParts(partAId, partBId, weldPoint: worldPoint, description: description, weldSizeMm: weldSizeMm);
  }

  // -------------------------------------------------------------
  // Pending Part Placement (Click to Place & Drag-and-Drop)
  // -------------------------------------------------------------
  PendingPartPlacement? pendingPlacement;

  void setPendingPlacement(PendingPartPlacement? placement) {
    pendingPlacement = placement;
    notifyListeners();
  }

  void cancelPendingPlacement() {
    pendingPlacement = null;
    notifyListeners();
  }

  /// Places the currently pending part at the specified 3D world position on the drawing board.
  AssemblyPart? placePendingPartAt(CadPoint3D position) {
    if (pendingPlacement == null) return null;
    final p = pendingPlacement!;
    _recordUndo();

    AssemblyPart newPart;
    switch (p.type) {
      case AssemblyPartType.straightRail:
        newPart = AssemblyPart(
          id: _generateId('rail'),
          name: p.name,
          type: AssemblyPartType.straightRail,
          length: p.length,
          height: p.height,
          flangeWidth: p.flangeWidth,
          thickness: p.thickness,
          position: position,
          color: p.color ?? const Color(0xFF64748B),
        );
        break;
      case AssemblyPartType.bentRail:
        newPart = AssemblyPart(
          id: _generateId('bent_rail'),
          name: p.name,
          type: AssemblyPartType.bentRail,
          length: p.length,
          height: p.height,
          flangeWidth: p.flangeWidth,
          thickness: p.thickness,
          position: position,
          segments: [
            RailSegmentDefinition(id: _generateId('seg_0'), length: p.length * 0.4, bendAngleDeg: 0),
            RailSegmentDefinition(id: _generateId('seg_1'), length: p.length * 0.3, bendAngleDeg: 45),
            RailSegmentDefinition(id: _generateId('seg_2'), length: p.length * 0.3, bendAngleDeg: 45),
          ],
          color: p.color ?? const Color(0xFF64748B),
        );
        break;
      case AssemblyPartType.rung:
        newPart = AssemblyPart(
          id: _generateId('rung'),
          name: p.name,
          type: AssemblyPartType.rung,
          length: p.length,
          height: p.height,
          flangeWidth: p.flangeWidth,
          thickness: p.thickness,
          position: position,
          color: p.color ?? const Color(0xFF38BDF8),
        );
        break;
      case AssemblyPartType.channel:
        newPart = AssemblyPart(
          id: _generateId('channel'),
          name: p.name,
          type: AssemblyPartType.channel,
          length: p.length,
          height: p.height,
          flangeWidth: p.flangeWidth,
          thickness: p.thickness,
          position: position,
          color: p.color ?? const Color(0xFF546E7A),
        );
        break;
      case AssemblyPartType.angle:
        newPart = AssemblyPart(
          id: _generateId('angle'),
          name: p.name,
          type: AssemblyPartType.angle,
          length: p.length,
          height: p.height,
          flangeWidth: p.flangeWidth,
          thickness: p.thickness,
          position: position,
          color: p.color ?? const Color(0xFF455A64),
        );
        break;
      case AssemblyPartType.rod:
        newPart = AssemblyPart(
          id: _generateId('rod'),
          name: p.name,
          type: AssemblyPartType.rod,
          length: p.length,
          height: p.height,
          flangeWidth: p.height,
          thickness: p.height,
          position: position,
          color: p.color ?? const Color(0xFF78909C),
        );
        break;
      case AssemblyPartType.bar:
        newPart = AssemblyPart(
          id: _generateId('bar'),
          name: p.name,
          type: AssemblyPartType.bar,
          length: p.length,
          height: p.height,
          flangeWidth: p.flangeWidth,
          thickness: p.thickness,
          position: position,
          color: p.color ?? const Color(0xFF607D8B),
        );
        break;
      case AssemblyPartType.iBeam:
        newPart = AssemblyPart(
          id: _generateId('ibeam'),
          name: p.name,
          type: AssemblyPartType.iBeam,
          length: p.length,
          height: p.height,
          flangeWidth: p.flangeWidth,
          thickness: p.thickness,
          position: position,
          color: p.color ?? const Color(0xFF37474F),
        );
        break;
      case AssemblyPartType.walkThroughStile:
      case AssemblyPartType.boxTubeStile:
      case AssemblyPartType.diamondGripRung:
      case AssemblyPartType.wideStepTread:
      case AssemblyPartType.safetyCageHoop:
      case AssemblyPartType.safetyCageBellHoop:
      case AssemblyPartType.cageStrap:
      case AssemblyPartType.standoffBracket:
      case AssemblyPartType.baseFootPlate:
      case AssemblyPartType.splicePlate:
      case AssemblyPartType.swingGate:
      case AssemblyPartType.customExtrusion:
        newPart = AssemblyPart(
          id: _generateId(p.type.name.toLowerCase()),
          name: p.name,
          type: p.type,
          length: p.length,
          height: p.height,
          flangeWidth: p.flangeWidth,
          thickness: p.thickness,
          position: position,
          color: p.color ?? const Color(0xFF64748B),
        );
        break;
    }

    doc.parts.add(newPart);
    doc.selectedPartId = newPart.id;
    doc.selectedPartIds = {newPart.id};
    pendingPlacement = null;
    invalidateMeshCache();
    notifyDocChanged();
    return newPart;
  }

  /// Adds a new part to the assembly scene.
  void addPart(AssemblyPart part) {
    _recordUndo();
    doc.parts.add(part);
    doc.selectedPartId = part.id;
    doc.selectedPartIds = {part.id};
    invalidateMeshCache();
    notifyDocChanged();
  }

  /// Adds a new part to the assembly scene positioned at the center of the screen/model.
  void addPartAtScreenCenter(AssemblyPart part) {
    if (doc.parts.isNotEmpty) {
      final pivot = assemblyMesh.center;
      part.position = CadPoint3D(pivot.x, pivot.y, 0.0);
    } else {
      part.position = const CadPoint3D(0.0, 0.0, 0.0);
    }
    addPart(part);
  }

  // -------------------------------------------------------------
  // Camera & View Presets
  // -------------------------------------------------------------
  void setIsometricView() {
    azimuthDeg = 45.0;
    elevationDeg = 35.26;
    isOrthoProjection = false;
    notifyListeners();
  }

  void setTopView() {
    azimuthDeg = 0.0;
    elevationDeg = 90.0;
    isOrthoProjection = true;
    notifyListeners();
  }

  void setFrontView() {
    azimuthDeg = 0.0;
    elevationDeg = 0.0;
    isOrthoProjection = true;
    notifyListeners();
  }

  void setRightView() {
    azimuthDeg = 90.0;
    elevationDeg = 0.0;
    isOrthoProjection = true;
    notifyListeners();
  }

  void setBackView() {
    azimuthDeg = 180.0;
    elevationDeg = 0.0;
    isOrthoProjection = true;
    notifyListeners();
  }

  void setLeftView() {
    azimuthDeg = 270.0;
    elevationDeg = 0.0;
    isOrthoProjection = true;
    notifyListeners();
  }

  void setBottomView() {
    azimuthDeg = 0.0;
    elevationDeg = -89.9;
    isOrthoProjection = true;
    notifyListeners();
  }

  void setStandardView(SketchUpStandardView view) {
    azimuthDeg = view.azimuth;
    elevationDeg = view.elevation;
    isOrthoProjection = view != SketchUpStandardView.iso;
    notifyListeners();
  }

  void zoomToFit() {
    pan = Offset.zero;
    zoom = 0.75;
    notifyListeners();
  }

  void updateOrbit(double deltaAzimuth, double deltaElevation) {
    azimuthDeg = (azimuthDeg + deltaAzimuth) % 360.0;
    elevationDeg = (elevationDeg + deltaElevation).clamp(-89.9, 89.9);
    notifyListeners();
  }

  void updatePan(Offset delta) {
    pan += delta;
    notifyListeners();
  }

  void updateZoom(double factor) {
    zoom = (zoom * factor).clamp(0.02, 120.0);
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Part Operations & Spawning
  // -------------------------------------------------------------
  void addRung({double length = 600.0, CadPoint3D? position}) {
    _recordUndo();
    final newId = _generateId('rung');
    final p = AssemblyPart(
      id: newId,
      name: 'Slotted Rung (${length.toInt()}mm)',
      type: AssemblyPartType.rung,
      length: length,
      height: 20.0,
      flangeWidth: 20.0,
      thickness: 1.5,
      position: position ?? CadPoint3D(0.0, 0.0, 50.0),
      color: const Color(0xFF78909C),
    );
    doc.parts.add(p);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  void addChannel({double length = 1000.0, double webHeight = 75.0, double flangeWidth = 35.0, double thickness = 3.0, CadPoint3D? position}) {
    _recordUndo();
    final newId = _generateId('channel');
    final p = AssemblyPart(
      id: newId,
      name: 'C-Channel (${length.toInt()}x${webHeight.toInt()}mm)',
      type: AssemblyPartType.channel,
      length: length,
      height: webHeight,
      flangeWidth: flangeWidth,
      thickness: thickness,
      position: position ?? CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF546E7A),
    );
    doc.parts.add(p);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  void addAngle({double length = 1000.0, double legA = 50.0, double legB = 50.0, double thickness = 4.0, CadPoint3D? position}) {
    _recordUndo();
    final newId = _generateId('angle');
    final p = AssemblyPart(
      id: newId,
      name: 'L-Angle (${legA.toInt()}x${legB.toInt()}mm)',
      type: AssemblyPartType.angle,
      length: length,
      height: legA,
      flangeWidth: legB,
      thickness: thickness,
      position: position ?? CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF455A64),
    );
    doc.parts.add(p);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  void addRod({double length = 1000.0, double diameter = 20.0, CadPoint3D? position}) {
    _recordUndo();
    final newId = _generateId('rod');
    final p = AssemblyPart(
      id: newId,
      name: 'Round Rod (⌀${diameter.toInt()}mm)',
      type: AssemblyPartType.rod,
      length: length,
      height: diameter,
      flangeWidth: diameter,
      thickness: diameter,
      position: position ?? CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF78909C),
    );
    doc.parts.add(p);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  void addFlatBar({double length = 1000.0, double width = 40.0, double thickness = 6.0, CadPoint3D? position}) {
    _recordUndo();
    final newId = _generateId('bar');
    final p = AssemblyPart(
      id: newId,
      name: 'Flat Bar (${width.toInt()}x${thickness.toInt()}mm)',
      type: AssemblyPartType.bar,
      length: length,
      height: width,
      flangeWidth: width,
      thickness: thickness,
      position: position ?? CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF607D8B),
    );
    doc.parts.add(p);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  void addIBeam({double length = 1000.0, double height = 100.0, double flangeWidth = 60.0, double thickness = 4.5, CadPoint3D? position}) {
    _recordUndo();
    final newId = _generateId('ibeam');
    final p = AssemblyPart(
      id: newId,
      name: 'I-Beam (${height.toInt()}x${flangeWidth.toInt()}mm)',
      type: AssemblyPartType.iBeam,
      length: length,
      height: height,
      flangeWidth: flangeWidth,
      thickness: thickness,
      position: position ?? CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF37474F),
    );
    doc.parts.add(p);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  void addStraightRail({
    double length = 1000.0,
    double height = 100.0,
    double flangeWidth = 20.0, // Default 20mm flange
    bool isFlangeOutward = false,
    CadPoint3D? position,
  }) {
    _recordUndo();
    final newId = _generateId('rail');
    final p = AssemblyPart(
      id: newId,
      name: 'Straight Rail (${length.toInt()}mm)',
      type: AssemblyPartType.straightRail,
      length: length,
      height: height,
      flangeWidth: flangeWidth,
      thickness: 2.0,
      isFlangeOutward: isFlangeOutward,
      position: position ?? CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF607D8B),
    );
    doc.parts.add(p);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  void addBentRail({double height = 100.0, double flangeWidth = 20.0, List<RailSegmentDefinition>? segments, CadPoint3D? position}) {
    _recordUndo();
    final newId = _generateId('bent_rail');
    final segs =
        segments ??
        [
          RailSegmentDefinition(id: 'seg_1', length: 300.0, bendAngleDeg: 0.0),
          RailSegmentDefinition(id: 'seg_2', length: 250.0, bendAngleDeg: 45.0, hasFlangeVNotch: true),
          RailSegmentDefinition(id: 'seg_3', length: 300.0, bendAngleDeg: 0.0, hasFlangeVNotch: true),
        ];
    final p = AssemblyPart(
      id: newId,
      name: 'Bent Rail (${segs.length} Segments)',
      type: AssemblyPartType.bentRail,
      height: height,
      flangeWidth: flangeWidth,
      thickness: 2.0,
      segments: segs,
      position: position ?? CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF546E7A),
    );
    doc.parts.add(p);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  void duplicateSelectedPart() {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    final newId = _generateId(part.type.name);
    final defId = part.componentDefinitionId ?? _generateId('comp_def');
    part.componentDefinitionId = defId;

    final copy = part.copyWith(
      id: newId,
      name: '${part.name} (Copy)',
      componentDefinitionId: defId,
      position: CadPoint3D(part.position.x + 30.0, part.position.y + 30.0, part.position.z),
      weldedToPartIds: [], // New copy is not yet welded
    );
    doc.parts.add(copy);
    doc.selectedPartId = newId;
    notifyListeners();
  }

  /// Creates a duplicate of `part` right where it is, leaving the original in place,
  /// and returning the new clone so it can be dragged (SketchUp Ctrl+Move).
  /// Automatically links parent and clone as component instances.
  AssemblyPart clonePartForMove(AssemblyPart part) {
    _recordUndo();
    final newId = _generateId(part.type.name);
    final defId = part.componentDefinitionId ?? _generateId('comp_def');
    part.componentDefinitionId = defId;

    final clone = part.copyWith(id: newId, name: '${part.name} (Copy)', componentDefinitionId: defId, weldedToPartIds: []);
    doc.parts.add(clone);
    doc.selectedPartId = newId;
    doc.selectedPartIds = {newId};
    notifyListeners();
    return clone;
  }

  // -------------------------------------------------------------
  // SketchUp Measurements VCB (Value Control Box) & Array Engine
  // -------------------------------------------------------------
  String vcbLabel = 'Measurements';
  String vcbValue = '';
  String vcbHint = 'Type distance, *N, or /N';
  bool isVcbActive = false;

  CadPoint3D? lastMoveDelta;
  String? lastMovedPartId;
  List<String> lastClonedPartIds = [];
  double? lastRotateDeltaDeg;

  void setVcbState({required String label, required String value, String? hint}) {
    vcbLabel = label;
    vcbValue = value;
    if (hint != null) vcbHint = hint;
    isVcbActive = true;
    notifyListeners();
  }

  void recordLastMove({required String partId, required CadPoint3D delta, List<String>? clonedIds}) {
    lastMovedPartId = partId;
    lastMoveDelta = delta;
    lastClonedPartIds = clonedIds ?? [partId];
    final dist = math.sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z);
    setVcbState(label: 'Distance', value: '${dist.toStringAsFixed(1)}mm', hint: 'Type *N to multiply, /N to divide, or mm');
  }

  void recordLastRotate({required String partId, required double deltaDeg, CadPoint3D? centerPoint, GizmoAxis axis = GizmoAxis.z}) {
    lastMovedPartId = partId;
    lastRotateDeltaDeg = deltaDeg;
    lastRotateCenterPoint = centerPoint;
    lastRotateAxis = axis;
    setVcbState(label: 'Angle', value: '${deltaDeg.toStringAsFixed(1)}°', hint: 'Type *N for radial array, /N to divide, or angle');
  }

  /// Evaluates and applies user input from the Measurements VCB box.
  bool submitVcbInput(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) return false;

    // 1. Array Multiplier: e.g. "*10" or "x10" or "X10"
    if (input.startsWith('*') || input.toLowerCase().startsWith('x')) {
      final numStr = input.substring(1).trim();
      final count = int.tryParse(numStr);
      if (count != null && count > 1) {
        if (activeToolMode == SketchUpToolMode.rotate || vcbLabel == 'Angle' || vcbLabel == 'Rotate' || (lastRotateDeltaDeg != null && lastMoveDelta == null)) {
          createRadialArray(count);
        } else {
          createLinearArray(count);
        }
        return true;
      }
    }

    // 2. Linear / Radial Divide: e.g. "/10" or "/12"
    if (input.startsWith('/')) {
      final numStr = input.substring(1).trim();
      final count = int.tryParse(numStr);
      if (count != null && count > 1) {
        if (activeToolMode == SketchUpToolMode.rotate || vcbLabel == 'Angle' || vcbLabel == 'Rotate' || (lastRotateDeltaDeg != null && lastMoveDelta == null)) {
          divideRadialArray(count);
        } else {
          divideLinearArray(count);
        }
        return true;
      }
    }

    // 3. Explicit Single Number (Distance or Angle): e.g. "250", "250mm", "45", "45°"
    final cleanNum = input
        .replaceAll('mm', '')
        .replaceAll('cm', '')
        .replaceAll('m', '')
        .replaceAll('in', '')
        .replaceAll('ft', '')
        .replaceAll('°', '')
        .replaceAll('deg', '')
        .trim();
    final singleVal = double.tryParse(cleanNum);
    if (singleVal != null) {
      if (activeToolMode == SketchUpToolMode.rotate || vcbLabel == 'Angle' || input.contains('°') || input.contains('deg')) {
        applyExplicitRotation(singleVal);
        return true;
      } else {
        final distMm = parseLengthToMm(input) ?? (singleVal * lengthUnit.toMmFactor);
        applyExplicitMoveDistance(distMm);
        return true;
      }
    }

    // 4. Dimensions pair: e.g. "600, 40"
    if (input.contains(',')) {
      final parts = input.split(',');
      if (parts.length == 2) {
        final l = double.tryParse(parts[0].trim());
        final h = double.tryParse(parts[1].trim());
        if (l != null && h != null && selectedPart != null) {
          _recordUndo();
          selectedPart!.length = l;
          selectedPart!.height = h;
          syncComponentInstances(selectedPart!.id);
          setVcbState(label: 'Dimensions', value: '${l.toStringAsFixed(0)} × ${h.toStringAsFixed(0)}mm', hint: 'Dimensions updated');
          notifyListeners();
          return true;
        }
      }
    }

    return false;
  }

  /// Clones the last moved part `count - 1` times along the `lastMoveDelta` vector.
  void createLinearArray(int totalCount) {
    if (lastMoveDelta == null || lastMovedPartId == null || totalCount < 2) return;
    final templatePart = doc.parts.where((p) => p.id == lastMovedPartId).firstOrNull;
    if (templatePart == null) return;

    _recordUndo();
    final defId = templatePart.componentDefinitionId ?? _generateId('comp_def');
    templatePart.componentDefinitionId = defId;
    final delta = lastMoveDelta!;
    final newSelectedIds = <String>[templatePart.id];

    AssemblyPart? parentRail;
    if (templatePart.parentPartId != null) {
      parentRail = doc.parts.where((p) => p.id == templatePart.parentPartId).firstOrNull;
    }

    for (int i = 1; i < totalCount; i++) {
      final newId = _generateId(templatePart.type.name);
      final newPos = CadPoint3D(templatePart.position.x + delta.x * i, templatePart.position.y + delta.y * i, templatePart.position.z + delta.z * i);

      final clone = templatePart.copyWith(id: newId, name: '${templatePart.name} #$i', componentDefinitionId: defId, position: newPos, weldedToPartIds: []);

      if (parentRail != null && templatePart.type == AssemblyPartType.rung) {
        final slotEntity = punchRungSlot(railId: parentRail.id, distanceX: newPos.x);
        clone.matedSlotEntityId = slotEntity.id;
        slotEntity.matedRungPartId = newId;

        final weldId = 'weld_${parentRail.id}_$newId';
        doc.welds.add(
          AssemblyWeldJoint(id: weldId, partAId: parentRail.id, partBId: newId, weldPoint: newPos, jointDescription: 'Fillet Weld (3mm)', weldSizeMm: 3.0),
        );
        parentRail.weldedToPartIds.add(newId);
        clone.weldedToPartIds.add(parentRail.id);
      }

      doc.parts.add(clone);
      newSelectedIds.add(newId);
    }

    doc.selectedPartIds = newSelectedIds.toSet();
    doc.selectedPartId = newSelectedIds.last;
    setVcbState(label: 'Array', value: '*$totalCount copies created', hint: 'Array complete');
    notifyListeners();
  }

  /// Divides the span of the last move into `divideCount` segments.
  void divideLinearArray(int divideCount) {
    if (lastMoveDelta == null || lastMovedPartId == null || divideCount < 2) return;
    final templatePart = doc.parts.where((p) => p.id == lastMovedPartId).firstOrNull;
    if (templatePart == null) return;

    _recordUndo();
    final defId = templatePart.componentDefinitionId ?? _generateId('comp_def');
    templatePart.componentDefinitionId = defId;
    final delta = lastMoveDelta!;
    final startPos = CadPoint3D(templatePart.position.x - delta.x, templatePart.position.y - delta.y, templatePart.position.z - delta.z);
    final step = CadPoint3D(delta.x / divideCount, delta.y / divideCount, delta.z / divideCount);

    final newSelectedIds = <String>[templatePart.id];
    AssemblyPart? parentRail;
    if (templatePart.parentPartId != null) {
      parentRail = doc.parts.where((p) => p.id == templatePart.parentPartId).firstOrNull;
    }

    for (int i = 1; i < divideCount; i++) {
      final newId = _generateId(templatePart.type.name);
      final newPos = CadPoint3D(startPos.x + step.x * i, startPos.y + step.y * i, startPos.z + step.z * i);

      final clone = templatePart.copyWith(id: newId, name: '${templatePart.name} div#$i', componentDefinitionId: defId, position: newPos, weldedToPartIds: []);

      if (parentRail != null && templatePart.type == AssemblyPartType.rung) {
        final slotEntity = punchRungSlot(railId: parentRail.id, distanceX: newPos.x);
        clone.matedSlotEntityId = slotEntity.id;
        slotEntity.matedRungPartId = newId;

        final weldId = 'weld_${parentRail.id}_$newId';
        doc.welds.add(
          AssemblyWeldJoint(id: weldId, partAId: parentRail.id, partBId: newId, weldPoint: newPos, jointDescription: 'Fillet Weld (3mm)', weldSizeMm: 3.0),
        );
        parentRail.weldedToPartIds.add(newId);
        clone.weldedToPartIds.add(parentRail.id);
      }

      doc.parts.add(clone);
      newSelectedIds.add(newId);
    }

    doc.selectedPartIds = newSelectedIds.toSet();
    setVcbState(label: 'Divide', value: '/$divideCount ($divideCount segments)', hint: 'Divided evenly');
    notifyListeners();
  }

  void applyExplicitMoveDistance(double targetDistance) {
    final part = (lastMovedPartId != null ? doc.parts.where((p) => p.id == lastMovedPartId).firstOrNull : null) ?? selectedPart;
    if (part == null || lastMoveDelta == null) return;
    final currentDist = math.sqrt(lastMoveDelta!.x * lastMoveDelta!.x + lastMoveDelta!.y * lastMoveDelta!.y + lastMoveDelta!.z * lastMoveDelta!.z);
    if (currentDist <= 0.001) return;

    _recordUndo();
    final scale = targetDistance / currentDist;
    final originalStart = CadPoint3D(part.position.x - lastMoveDelta!.x, part.position.y - lastMoveDelta!.y, part.position.z - lastMoveDelta!.z);
    part.position = CadPoint3D(
      originalStart.x + lastMoveDelta!.x * scale,
      originalStart.y + lastMoveDelta!.y * scale,
      originalStart.z + lastMoveDelta!.z * scale,
    );
    lastMoveDelta = CadPoint3D(lastMoveDelta!.x * scale, lastMoveDelta!.y * scale, lastMoveDelta!.z * scale);
    setVcbState(label: 'Distance', value: formatLength(targetDistance), hint: 'Distance updated');
    notifyListeners();
  }

  void applyExplicitRotation(double targetAngleDeg) {
    final part = (lastMovedPartId != null ? doc.parts.where((p) => p.id == lastMovedPartId).firstOrNull : null) ?? selectedPart;
    if (part == null) return;
    _recordUndo();
    final center = lastRotateCenterPoint;
    final axis = lastRotateAxis;
    if (center != null && lastRotateDeltaDeg != null) {
      final angleDiff = targetAngleDeg - lastRotateDeltaDeg!;
      final rad = angleDiff * math.pi / 180.0;
      if (axis == GizmoAxis.x) {
        final dy = part.position.y - center.y;
        final dz = part.position.z - center.z;
        final ry = center.y + (dy * math.cos(rad) - dz * math.sin(rad));
        final rz = center.z + (dy * math.sin(rad) + dz * math.cos(rad));
        part.position = CadPoint3D(part.position.x, ry, rz);
        part.rotationDeg = CadPoint3D((part.rotationDeg.x + angleDiff) % 360.0, part.rotationDeg.y, part.rotationDeg.z);
      } else if (axis == GizmoAxis.y) {
        final dz = part.position.z - center.z;
        final dx = part.position.x - center.x;
        final rz = center.z + (dz * math.cos(rad) - dx * math.sin(rad));
        final rx = center.x + (dz * math.sin(rad) + dx * math.cos(rad));
        part.position = CadPoint3D(rx, part.position.y, rz);
        part.rotationDeg = CadPoint3D(part.rotationDeg.x, (part.rotationDeg.y + angleDiff) % 360.0, part.rotationDeg.z);
      } else {
        final dx = part.position.x - center.x;
        final dy = part.position.y - center.y;
        final rx = center.x + (dx * math.cos(rad) - dy * math.sin(rad));
        final ry = center.y + (dx * math.sin(rad) + dy * math.cos(rad));
        part.position = CadPoint3D(rx, ry, part.position.z);
        part.rotationDeg = CadPoint3D(part.rotationDeg.x, part.rotationDeg.y, (part.rotationDeg.z + angleDiff) % 360.0);
      }
      lastRotateDeltaDeg = targetAngleDeg;
    } else {
      if (axis == GizmoAxis.x) {
        part.rotationDeg = CadPoint3D(targetAngleDeg % 360.0, part.rotationDeg.y, part.rotationDeg.z);
      } else if (axis == GizmoAxis.y) {
        part.rotationDeg = CadPoint3D(part.rotationDeg.x, targetAngleDeg % 360.0, part.rotationDeg.z);
      } else {
        part.rotationDeg = CadPoint3D(part.rotationDeg.x, part.rotationDeg.y, targetAngleDeg % 360.0);
      }
    }
    setVcbState(label: 'Angle', value: '${targetAngleDeg.toStringAsFixed(1)}°', hint: 'Rotation updated');
    notifyListeners();
  }

  /// Duplicates a part, assigns/inherits component definition, and rotates the clone.
  AssemblyPart rotateAndCopyPart(String partId, double angleDeg, {CadPoint3D? centerPoint, GizmoAxis axis = GizmoAxis.z}) {
    final original = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (original == null) throw ArgumentError('Part not found: $partId');

    _recordUndo();
    final defId = original.componentDefinitionId ?? _generateId('comp_def');
    original.componentDefinitionId = defId;

    final newId = _generateId(original.type.name);
    final rad = angleDeg * math.pi / 180.0;

    CadPoint3D newPos = original.position;
    CadPoint3D newRot = original.rotationDeg;

    if (axis == GizmoAxis.x) {
      if (centerPoint != null) {
        final dy = original.position.y - centerPoint.y;
        final dz = original.position.z - centerPoint.z;
        final ry = centerPoint.y + (dy * math.cos(rad) - dz * math.sin(rad));
        final rz = centerPoint.z + (dy * math.sin(rad) + dz * math.cos(rad));
        newPos = CadPoint3D(original.position.x, ry, rz);
      }
      newRot = CadPoint3D((original.rotationDeg.x + angleDeg) % 360.0, original.rotationDeg.y, original.rotationDeg.z);
    } else if (axis == GizmoAxis.y) {
      if (centerPoint != null) {
        final dz = original.position.z - centerPoint.z;
        final dx = original.position.x - centerPoint.x;
        final rz = centerPoint.z + (dz * math.cos(rad) - dx * math.sin(rad));
        final rx = centerPoint.x + (dz * math.sin(rad) + dx * math.cos(rad));
        newPos = CadPoint3D(rx, original.position.y, rz);
      }
      newRot = CadPoint3D(original.rotationDeg.x, (original.rotationDeg.y + angleDeg) % 360.0, original.rotationDeg.z);
    } else {
      if (centerPoint != null) {
        final dx = original.position.x - centerPoint.x;
        final dy = original.position.y - centerPoint.y;
        final rx = centerPoint.x + (dx * math.cos(rad) - dy * math.sin(rad));
        final ry = centerPoint.y + (dx * math.sin(rad) + dy * math.cos(rad));
        newPos = CadPoint3D(rx, ry, original.position.z);
      }
      newRot = CadPoint3D(original.rotationDeg.x, original.rotationDeg.y, (original.rotationDeg.z + angleDeg) % 360.0);
    }

    final clone = original.copyWith(
      id: newId,
      name: '${original.name} (Rotated)',
      componentDefinitionId: defId,
      position: newPos,
      rotationDeg: newRot,
      weldedToPartIds: [],
    );

    doc.parts.add(clone);
    doc.selectedPartId = newId;
    doc.selectedPartIds = {newId};
    recordLastRotate(partId: newId, deltaDeg: angleDeg, centerPoint: centerPoint, axis: axis);
    notifyListeners();
    return clone;
  }

  /// Creates a radial circular array of [totalCount] parts spaced by [stepAngleDeg].
  List<AssemblyPart> radialArrayPart(String partId, int totalCount, double stepAngleDeg, {CadPoint3D? centerPoint, GizmoAxis axis = GizmoAxis.z}) {
    if (totalCount < 2) return [];
    final template = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (template == null) return [];

    _recordUndo();
    final defId = template.componentDefinitionId ?? _generateId('comp_def');
    template.componentDefinitionId = defId;

    final createdParts = <AssemblyPart>[];
    final selectedIds = <String>{template.id};

    for (int i = 1; i < totalCount; i++) {
      final currentAngleDeg = stepAngleDeg * i;
      final rad = currentAngleDeg * math.pi / 180.0;
      final newId = _generateId(template.type.name);

      CadPoint3D newPos = template.position;
      CadPoint3D newRot = template.rotationDeg;

      if (axis == GizmoAxis.x) {
        if (centerPoint != null) {
          final dy = template.position.y - centerPoint.y;
          final dz = template.position.z - centerPoint.z;
          final ry = centerPoint.y + (dy * math.cos(rad) - dz * math.sin(rad));
          final rz = centerPoint.z + (dy * math.sin(rad) + dz * math.cos(rad));
          newPos = CadPoint3D(template.position.x, ry, rz);
        }
        newRot = CadPoint3D((template.rotationDeg.x + currentAngleDeg) % 360.0, template.rotationDeg.y, template.rotationDeg.z);
      } else if (axis == GizmoAxis.y) {
        if (centerPoint != null) {
          final dz = template.position.z - centerPoint.z;
          final dx = template.position.x - centerPoint.x;
          final rz = centerPoint.z + (dz * math.cos(rad) - dx * math.sin(rad));
          final rx = centerPoint.x + (dz * math.sin(rad) + dx * math.cos(rad));
          newPos = CadPoint3D(rx, template.position.y, rz);
        }
        newRot = CadPoint3D(template.rotationDeg.x, (template.rotationDeg.y + currentAngleDeg) % 360.0, template.rotationDeg.z);
      } else {
        if (centerPoint != null) {
          final dx = template.position.x - centerPoint.x;
          final dy = template.position.y - centerPoint.y;
          final rx = centerPoint.x + (dx * math.cos(rad) - dy * math.sin(rad));
          final ry = centerPoint.y + (dx * math.sin(rad) + dy * math.cos(rad));
          newPos = CadPoint3D(rx, ry, template.position.z);
        }
        newRot = CadPoint3D(template.rotationDeg.x, template.rotationDeg.y, (template.rotationDeg.z + currentAngleDeg) % 360.0);
      }

      final clone = template.copyWith(
        id: newId,
        name: '${template.name} rad#$i',
        componentDefinitionId: defId,
        position: newPos,
        rotationDeg: newRot,
        weldedToPartIds: [],
      );

      doc.parts.add(clone);
      createdParts.add(clone);
      selectedIds.add(newId);
    }

    doc.selectedPartIds = selectedIds;
    doc.selectedPartId = selectedIds.last;
    setVcbState(label: 'Radial Array', value: '*$totalCount copies (${stepAngleDeg.toStringAsFixed(1)}° pitch)', hint: 'Radial array complete');
    notifyListeners();
    return createdParts;
  }

  void createRadialArray(int totalCount) {
    if (lastRotateDeltaDeg == null || lastMovedPartId == null || totalCount < 2) return;
    radialArrayPart(lastMovedPartId!, totalCount, lastRotateDeltaDeg!, centerPoint: lastRotateCenterPoint, axis: lastRotateAxis);
  }

  void divideRadialArray(int divideCount) {
    if (lastRotateDeltaDeg == null || lastMovedPartId == null || divideCount < 2) return;
    final stepAngle = lastRotateDeltaDeg! / divideCount;
    radialArrayPart(lastMovedPartId!, divideCount, stepAngle, centerPoint: lastRotateCenterPoint, axis: lastRotateAxis);
  }

  // -------------------------------------------------------------
  // SketchUp Component Definitions & Parametric Synchronization
  // -------------------------------------------------------------

  /// Returns how many parts in the scene share this [definitionId].
  int getComponentInstanceCount(String? definitionId) {
    if (definitionId == null) return 0;
    return doc.parts.where((p) => p.componentDefinitionId == definitionId).length;
  }

  /// Propagates geometry and sketch changes from [sourcePartId] to all sibling component instances.
  void syncComponentInstances(String sourcePartId) {
    final source = doc.parts.where((p) => p.id == sourcePartId).firstOrNull;
    if (source == null || source.componentDefinitionId == null) return;

    final defId = source.componentDefinitionId!;
    final siblings = doc.parts.where((p) => p.id != sourcePartId && p.componentDefinitionId == defId).toList();
    if (siblings.isEmpty) return;

    for (final sib in siblings) {
      sib.length = source.length;
      sib.height = source.height;
      sib.flangeWidth = source.flangeWidth;
      sib.thickness = source.thickness;
      sib.isFlangeOutward = source.isFlangeOutward;
      sib.color = source.color;
      // Deep-copy sketches
      sib.sketches = source.sketches.map((s) => s.copyWith(id: _generateId(s.featureType))).toList();
      // Deep-copy segments if any
      sib.segments = source.segments
          .map((seg) => RailSegmentDefinition(id: _generateId('seg'), length: seg.length, bendAngleDeg: seg.bendAngleDeg, hasFlangeVNotch: seg.hasFlangeVNotch))
          .toList();
    }
  }

  /// Detaches [partId] from its component definition so it can be edited independently.
  void makePartUnique(String partId) {
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null || part.componentDefinitionId == null) return;
    _recordUndo();
    part.componentDefinitionId = null;
    notifyListeners();
  }

  void makeSelectedPartUnique() {
    if (selectedPart != null) {
      makePartUnique(selectedPart!.id);
    }
  }

  /// Converts [partId] into a component definition template.
  void makePartComponent(String partId) {
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null) return;
    _recordUndo();
    part.componentDefinitionId = _generateId('comp_def');
    notifyListeners();
  }

  void makeSelectedPartComponent() {
    if (selectedPart != null) {
      makePartComponent(selectedPart!.id);
    }
  }

  // -------------------------------------------------------------
  // Auto-Span Face-to-Face Bridging Tool
  // -------------------------------------------------------------
  String? bridgeSourcePartId;

  void startBridge(String partId) {
    bridgeSourcePartId = partId;
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    final name = part?.name ?? partId;
    setVcbState(label: 'Bridge', value: 'From: $name', hint: 'Click destination stile / part to span');
    notifyListeners();
  }

  void cancelBridge() {
    bridgeSourcePartId = null;
    setVcbState(label: 'Measurements', value: '', hint: 'Bridge cancelled');
    notifyListeners();
  }

  AssemblyPart? bridgeParts(
    String partAId,
    String partBId, {
    double? distanceX,
    AssemblyPartType rungType = AssemblyPartType.diamondGripRung,
    double? customSpanLength,
  }) {
    if (partAId == partBId) return null;
    final partA = doc.parts.where((p) => p.id == partAId).firstOrNull;
    final partB = doc.parts.where((p) => p.id == partBId).firstOrNull;
    if (partA == null || partB == null) return null;

    _recordUndo();

    // Determine span distance and placement orientation
    final dy = (partB.position.y - partA.position.y).abs();
    final dx = (partB.position.x - partA.position.x).abs();
    final isAlongY = dy >= dx;

    final spanLength = customSpanLength ?? (isAlongY ? (dy > 0 ? dy : 450.0) : (dx > 0 ? dx : 450.0));
    final clampedSpan = spanLength.clamp(100.0, 3000.0);

    final posX = distanceX ?? (partA.position.x + (partA.length / 2.0));
    final posY = isAlongY ? math.min(partA.position.y, partB.position.y) : partA.position.y;
    final posZ = partA.position.z + (partA.height / 2.0) - 10.0;

    final newRungId = _generateId(rungType.name);
    final bridgePart = AssemblyPart(
      id: newRungId,
      name: '${rungType == AssemblyPartType.diamondGripRung ? "Diamond Grip Rung" : "Bridge Member"} (${clampedSpan.toStringAsFixed(0)}mm)',
      type: rungType,
      length: clampedSpan,
      height: 25.0,
      flangeWidth: 20.0,
      thickness: 2.0,
      position: CadPoint3D(posX, posY, posZ),
      rotationDeg: isAlongY ? const CadPoint3D(0.0, 0.0, 90.0) : const CadPoint3D(0.0, 0.0, 0.0),
      parentPartId: partA.id,
      color: const Color(0xFF38BDF8),
    );

    // Punch slots if stiles support it
    if (partA.type == AssemblyPartType.straightRail || partA.type == AssemblyPartType.boxTubeStile || partA.type == AssemblyPartType.walkThroughStile) {
      final slotA = punchRungSlot(railId: partA.id, distanceX: posX);
      slotA.matedRungPartId = newRungId;
      bridgePart.matedSlotEntityId = slotA.id;
    }
    if (partB.type == AssemblyPartType.straightRail || partB.type == AssemblyPartType.boxTubeStile || partB.type == AssemblyPartType.walkThroughStile) {
      final slotB = punchRungSlot(railId: partB.id, distanceX: posX);
      slotB.matedRungPartId = newRungId;
    }

    // Add persistent fillet welds at both ends (AWS D1.1 / ISO 2553 per SS4 & SS5)
    final inwardDirA = (partA.position.y <= partB.position.y) ? 1.0 : -1.0;
    final weldA = AssemblyWeldJoint(
      id: 'weld_${partA.id}_$newRungId',
      partAId: partA.id,
      partBId: newRungId,
      weldPoint: CadPoint3D(posX, partA.position.y, posZ + 10.0),
      weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
      weldLengthMm: 40.0,
      weldSizeMm: 10.0,
      legDir1: const CadPoint3D(0.0, 0.0, 1.0),
      legDir2: CadPoint3D(0.0, inwardDirA, 0.0),
      bothSides: false,
      jointDescription: 'Bridge Stile-to-Rung Fillet Weld (10mm)',
      jointType: AssemblyJointType.welded,
    );

    final inwardDirB = (partB.position.y <= partA.position.y) ? 1.0 : -1.0;
    final weldB = AssemblyWeldJoint(
      id: 'weld_${partB.id}_$newRungId',
      partAId: partB.id,
      partBId: newRungId,
      weldPoint: CadPoint3D(posX, partB.position.y, posZ + 10.0),
      weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
      weldLengthMm: 40.0,
      weldSizeMm: 10.0,
      legDir1: const CadPoint3D(0.0, 0.0, 1.0),
      legDir2: CadPoint3D(0.0, inwardDirB, 0.0),
      bothSides: false,
      jointDescription: 'Bridge Stile-to-Rung Fillet Weld (10mm)',
      jointType: AssemblyJointType.welded,
    );

    doc.welds.addAll([weldA, weldB]);
    partA.weldedToPartIds.add(newRungId);
    partB.weldedToPartIds.add(newRungId);
    bridgePart.weldedToPartIds.addAll([partA.id, partB.id]);

    doc.parts.add(bridgePart);
    doc.selectedPartId = newRungId;
    doc.selectedPartIds = {newRungId};
    bridgeSourcePartId = null;

    setVcbState(label: 'Bridge Span', value: '${clampedSpan.toStringAsFixed(1)}mm', hint: 'Dual fillet welds applied');
    notifyListeners();
    return bridgePart;
  }

  void deleteSelectedPart() {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    // Remove welds referencing this part
    doc.welds.removeWhere((w) => w.partAId == part.id || w.partBId == part.id);
    for (final p in doc.parts) {
      p.weldedToPartIds.remove(part.id);
    }
    doc.parts.removeWhere((p) => p.id == part.id);
    doc.selectedPartId = null;
    doc.selectedFaceId = null;
    notifyListeners();
  }

  // -------------------------------------------------------------
  // -------------------------------------------------------------
  // Direct 3D Transformations & Micro-adjustments
  // -------------------------------------------------------------
  void nudgeSelectedPosition(double dx, double dy, double dz) {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    final delta = CadPoint3D(dx, dy, dz);
    final affectedPartIds = <String>{part.id};
    if (part.groupId != null) {
      affectedPartIds.addAll(doc.parts.where((p) => p.groupId == part.groupId).map((p) => p.id));
    } else if (doc.selectedPartIds.contains(part.id)) {
      affectedPartIds.addAll(doc.selectedPartIds);
    }
    // Propagate to all bonded cluster members so welded parts never separate
    affectedPartIds.addAll(getBondedClusterPartIds(part.id));
    // Propagate to all magnetically linked cluster members
    affectedPartIds.addAll(getMagneticallyLinkedClusterPartIds(part.id));
    final movedPartIds = Set<String>.from(affectedPartIds);
    for (final pid in affectedPartIds) {
      final p = doc.parts.where((x) => x.id == pid).firstOrNull;
      if (p != null) {
        p.position = CadPoint3D(p.position.x + dx, p.position.y + dy, p.position.z + dz);
        _propagateTranslationToAssemblySet(p.id, delta, excludePartIds: movedPartIds);
      }
    }
    _translateWeldsForParts(movedPartIds, delta);
    notifyListeners();
  }

  void nudgeSelectedRotation(double rx, double ry, double rz) {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    part.rotationDeg = CadPoint3D((part.rotationDeg.x + rx) % 360.0, (part.rotationDeg.y + ry) % 360.0, (part.rotationDeg.z + rz) % 360.0);
    notifyListeners();
  }

  void updatePartPosition(String id, CadPoint3D pos) {
    final p = doc.parts.where((x) => x.id == id).firstOrNull;
    if (p == null) return;
    final delta = CadPoint3D(pos.x - p.position.x, pos.y - p.position.y, pos.z - p.position.z);
    p.position = pos;

    final movedPartIds = <String>{p.id};

    // Propagate translation to virtual group members so they move as a single rigid unit
    if (p.groupId != null) {
      for (final sibling in doc.parts) {
        if (sibling.id != p.id && sibling.groupId == p.groupId) {
          sibling.position = CadPoint3D(sibling.position.x + delta.x, sibling.position.y + delta.y, sibling.position.z + delta.z);
          movedPartIds.add(sibling.id);
        }
      }
    }

    // Propagate translation to magnetically linked cluster members
    final magneticCluster = getMagneticallyLinkedClusterPartIds(p.id);
    for (final linkedId in magneticCluster) {
      if (linkedId != p.id && !movedPartIds.contains(linkedId)) {
        final linkedPart = doc.parts.where((x) => x.id == linkedId).firstOrNull;
        if (linkedPart != null) {
          linkedPart.position = CadPoint3D(linkedPart.position.x + delta.x, linkedPart.position.y + delta.y, linkedPart.position.z + delta.z);
          movedPartIds.add(linkedId);
        }
      }
    }

    _propagateTranslationToAssemblySet(id, delta, excludePartIds: movedPartIds);
    _translateWeldsForParts(movedPartIds, delta);
    notifyListeners();
  }

  /// Propagates translation of a parent part to all mated child parts in the Assembly Set.
  void _propagateTranslationToAssemblySet(String parentId, CadPoint3D delta, {Set<String>? excludePartIds}) {
    for (final child in doc.parts) {
      if (child.parentPartId == parentId && (excludePartIds == null || !excludePartIds.contains(child.id))) {
        child.position = CadPoint3D(child.position.x + delta.x, child.position.y + delta.y, child.position.z + delta.z);
        excludePartIds?.add(child.id);
        _propagateTranslationToAssemblySet(child.id, delta, excludePartIds: excludePartIds);
      }
    }
  }

  /// Translates all attached weld geometry when welded parts move (keeps welds sticking/glued to parts, SS4).
  void _translateWeldsForParts(Set<String> movedPartIds, CadPoint3D delta) {
    if (movedPartIds.isEmpty || (delta.x == 0.0 && delta.y == 0.0 && delta.z == 0.0)) return;
    for (int i = 0; i < doc.welds.length; i++) {
      final w = doc.welds[i];
      if (movedPartIds.contains(w.partAId) || movedPartIds.contains(w.partBId)) {
        final newPt = CadPoint3D(w.weldPoint.x + delta.x, w.weldPoint.y + delta.y, w.weldPoint.z + delta.z);
        final newSec = w.secondWeldPoint != null
            ? CadPoint3D(w.secondWeldPoint!.x + delta.x, w.secondWeldPoint!.y + delta.y, w.secondWeldPoint!.z + delta.z)
            : null;
        final newPaths = w.pathPoints?.map((p) => CadPoint3D(p.x + delta.x, p.y + delta.y, p.z + delta.z)).toList();
        doc.welds[i] = w.copyWith(weldPoint: newPt, secondWeldPoint: newSec, pathPoints: newPaths);
      }
    }
  }

  void updatePartRotation(String id, CadPoint3D rot) {
    final p = doc.parts.where((x) => x.id == id).firstOrNull;
    if (p == null) return;
    p.rotationDeg = rot;
    notifyListeners();
  }

  void setActiveSketchTool(String tool) {
    if (activeSketchTool != tool) {
      clearSketchInteractiveState();
    }
    activeSketchTool = tool;
    notifyListeners();
  }

  void updatePartDimensions(String id, {double? length, double? height, double? flangeWidth, double? thickness}) {
    final p = doc.parts.where((x) => x.id == id).firstOrNull;
    if (p == null) return;
    _recordUndo();
    if (length != null) p.length = length.clamp(50.0, 10000.0);
    if (height != null) p.height = height.clamp(20.0, 500.0);
    if (flangeWidth != null) p.flangeWidth = flangeWidth.clamp(5.0, 150.0);
    if (thickness != null) p.thickness = thickness.clamp(0.5, 10.0);
    syncComponentInstances(p.id);
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Direct Dimensions & Flange Editing
  // -------------------------------------------------------------
  void updateSelectedLength(double length) {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    part.length = length.clamp(50.0, 10000.0);
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void updateSelectedHeight(double height) {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    part.height = height.clamp(20.0, 500.0);
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void updateSelectedFlangeWidth(double flange) {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    part.flangeWidth = flange.clamp(5.0, 150.0);
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void updateSelectedThickness(double t) {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    part.thickness = t.clamp(0.5, 10.0);
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void toggleSelectedFlangeOrientation() {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    part.isFlangeOutward = !part.isFlangeOutward;
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void setSelectedColor(Color col) {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    part.color = col;
    syncComponentInstances(part.id);
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Multi-Segment Editing & Auto Flange V-Notches
  // -------------------------------------------------------------
  void addSegmentToSelectedRail({double length = 300.0, double bendAngleDeg = 45.0, bool hasFlangeVNotch = true}) {
    final part = selectedPart;
    if (part == null || part.type != AssemblyPartType.bentRail) return;
    _recordUndo();
    final newId = _generateId('seg');
    part.segments.add(RailSegmentDefinition(id: newId, length: length, bendAngleDeg: bendAngleDeg, hasFlangeVNotch: hasFlangeVNotch));
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void removeSegmentFromSelectedRail(int index) {
    final part = selectedPart;
    if (part == null || part.type != AssemblyPartType.bentRail) return;
    if (index < 0 || index >= part.segments.length) return;
    _recordUndo();
    part.segments.removeAt(index);
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void updateSegment(int index, {double? length, double? bendAngleDeg, bool? hasFlangeVNotch}) {
    final part = selectedPart;
    if (part == null || part.type != AssemblyPartType.bentRail) return;
    if (index < 0 || index >= part.segments.length) return;
    _recordUndo();
    final seg = part.segments[index];
    if (length != null) seg.length = length.clamp(20.0, 5000.0);
    if (bendAngleDeg != null) seg.bendAngleDeg = bendAngleDeg.clamp(-170.0, 170.0);
    if (hasFlangeVNotch != null) seg.hasFlangeVNotch = hasFlangeVNotch;
    syncComponentInstances(part.id);
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Welding & Bonding Joints
  // -------------------------------------------------------------
  void weldParts(
    String partAId,
    String partBId, {
    CadPoint3D? weldPoint,
    String description = 'MIG Fillet Weld',
    double weldSizeMm = 6.0,
    CadPoint3D? weldAxis,
    CadPoint3D? legDir1,
    CadPoint3D? legDir2,
    bool bothSides = false,
    CadPoint3D? secondWeldPoint,
    CadPoint3D? secondLegDir1,
    CadPoint3D? secondLegDir2,
    List<CadPoint3D>? pathPoints,
    double weldLengthMm = 40.0,
  }) {
    final pA = doc.parts.where((p) => p.id == partAId).firstOrNull;
    final pB = doc.parts.where((p) => p.id == partBId).firstOrNull;
    if (pA == null || pB == null || partAId == partBId) return;

    _recordUndo();

    final bool isRailRung =
        (pA.type == AssemblyPartType.straightRail || pA.type == AssemblyPartType.bentRail || pA.type == AssemblyPartType.boxTubeStile) &&
        (pB.type == AssemblyPartType.rung);
    final bool isRungRail =
        (pB.type == AssemblyPartType.straightRail || pB.type == AssemblyPartType.bentRail || pB.type == AssemblyPartType.boxTubeStile) &&
        (pA.type == AssemblyPartType.rung);

    CadPoint3D pt;
    CadPoint3D axis = weldAxis ?? const CadPoint3D(1.0, 0.0, 0.0);
    CadPoint3D? l1 = legDir1;
    CadPoint3D? l2 = legDir2;
    bool both = bothSides;
    CadPoint3D? sPt = secondWeldPoint;
    CadPoint3D? sL1 = secondLegDir1;
    CadPoint3D? sL2 = secondLegDir2;
    double seamLen = weldLengthMm;

    if (weldPoint != null) {
      pt = weldPoint;
      if (pathPoints != null) {
        both = false;
        sPt = null;
        sL1 = null;
        sL2 = null;
      } else if ((isRailRung || isRungRail) && bothSides) {
        final rail = isRailRung ? pA : pB;
        final rung = isRailRung ? pB : pA;
        final double inwardY = (rail.position.y <= rung.position.y) ? 1.0 : -1.0;
        l1 ??= const CadPoint3D(0.0, 0.0, 1.0);
        l2 ??= CadPoint3D(0.0, inwardY, 0.0);
        both = true;
        sPt ??= CadPoint3D(pt.x, pt.y, pt.z - 20.0);
        sL1 ??= const CadPoint3D(0.0, 0.0, -1.0);
        sL2 ??= CadPoint3D(0.0, inwardY, 0.0);
      }
    } else if (isRailRung || isRungRail) {
      final rail = isRailRung ? pA : pB;
      final rung = isRailRung ? pB : pA;
      final double rx = rung.position.x;
      final double ry = rail.position.y;
      final double rz = rung.position.z + 10.0;
      final double topZ = rz + 10.0;
      final double botZ = rz - 10.0;
      final double inwardY = (rail.position.y <= rung.position.y) ? 1.0 : -1.0;

      pt = CadPoint3D(rx, ry, topZ);
      axis = const CadPoint3D(1.0, 0.0, 0.0);
      l1 = const CadPoint3D(0.0, 0.0, 1.0);
      l2 = CadPoint3D(0.0, inwardY, 0.0);
      both = true;
      sPt = CadPoint3D(rx, ry, botZ);
      sL1 = const CadPoint3D(0.0, 0.0, -1.0);
      sL2 = CadPoint3D(0.0, inwardY, 0.0);
      seamLen = 40.0;
    } else {
      pt = CadPoint3D((pA.position.x + pB.position.x) / 2.0, (pA.position.y + pB.position.y) / 2.0, (pA.position.z + pB.position.z) / 2.0);
      final dx = (pA.position.x - pB.position.x).abs();
      final dy = (pA.position.y - pB.position.y).abs();
      final dz = (pA.position.z - pB.position.z).abs();
      if (dx >= dy && dx >= dz) {
        axis = const CadPoint3D(0.0, 1.0, 0.0);
        l1 = const CadPoint3D(1.0, 0.0, 0.0);
        l2 = const CadPoint3D(0.0, 0.0, 1.0);
      } else if (dy >= dx && dy >= dz) {
        axis = const CadPoint3D(1.0, 0.0, 0.0);
        l1 = const CadPoint3D(0.0, 1.0, 0.0);
        l2 = const CadPoint3D(0.0, 0.0, 1.0);
      } else {
        axis = const CadPoint3D(1.0, 0.0, 0.0);
        l1 = const CadPoint3D(0.0, 0.0, 1.0);
        l2 = const CadPoint3D(0.0, 1.0, 0.0);
      }
      seamLen = math.min(math.max(pA.height, pB.height), 60.0);
    }

    final joint = AssemblyWeldJoint(
      id: _generateId('weld'),
      partAId: partAId,
      partBId: partBId,
      weldPoint: pt,
      jointDescription: description,
      weldSizeMm: weldSizeMm,
      weldAxis: axis,
      legDir1: l1,
      legDir2: l2,
      bothSides: both,
      secondWeldPoint: sPt,
      secondLegDir1: sL1,
      secondLegDir2: sL2,
      pathPoints: pathPoints,
      weldLengthMm: seamLen,
      jointStyle: activeJointStyle,
      scoreResult: latestWeldEvaluation,
    );

    doc.welds.add(joint);
    if (!pA.weldedToPartIds.contains(pB.id)) pA.weldedToPartIds.add(pB.id);
    if (!pB.weldedToPartIds.contains(pA.id)) pB.weldedToPartIds.add(pA.id);

    notifyListeners();
  }

  void weldSelectedTo(String targetPartId) {
    final part = selectedPart;
    if (part == null || part.id == targetPartId) return;
    weldParts(part.id, targetPartId);
  }

  void breakWeld(String weldId) {
    _recordUndo();
    final w = doc.welds.where((j) => j.id == weldId).firstOrNull;
    if (w == null) return;

    doc.welds.removeWhere((j) => j.id == weldId);

    // Check if other welds still bond these parts
    final hasOtherBondAB = doc.welds.any((j) => (j.partAId == w.partAId && j.partBId == w.partBId) || (j.partAId == w.partBId && j.partBId == w.partAId));
    if (!hasOtherBondAB) {
      final pA = doc.parts.where((p) => p.id == w.partAId).firstOrNull;
      final pB = doc.parts.where((p) => p.id == w.partBId).firstOrNull;
      pA?.weldedToPartIds.remove(w.partBId);
      pB?.weldedToPartIds.remove(w.partAId);
    }
    notifyListeners();
  }

  void breakAllWeldsForSelectedPart() {
    final part = selectedPart;
    if (part == null) return;
    _recordUndo();
    doc.welds.removeWhere((w) => w.partAId == part.id || w.partBId == part.id);
    for (final p in doc.parts) {
      p.weldedToPartIds.remove(part.id);
    }
    part.weldedToPartIds.clear();
    notifyListeners();
  }

  List<AssemblyWeldJoint> getWeldsForSelectedPart() {
    final part = selectedPart;
    if (part == null) return [];
    return doc.welds.where((w) => w.partAId == part.id || w.partBId == part.id).toList();
  }

  // -------------------------------------------------------------
  // Magnetic Snap & Coupling System
  // -------------------------------------------------------------
  AssemblyMagneticSpot? addMagneticSpot(String partId, CadPoint3D localPoint, CadPoint3D normal, {String? name}) {
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null) return null;
    _recordUndo();

    final spotNumber = doc.parts.fold<int>(0, (sum, p) => sum + p.magneticSpots.length) + 1;
    final spot = AssemblyMagneticSpot(
      id: _generateId('mag'),
      partId: partId,
      localPoint: localPoint,
      normal: normal,
      name: name ?? 'Mag Point $spotNumber (${part.name})',
    );
    part.magneticSpots.add(spot);
    notifyDocChanged();
    return spot;
  }

  void removeMagneticSpot(String spotId) {
    _recordUndo();
    for (final p in doc.parts) {
      p.magneticSpots.removeWhere((s) => s.id == spotId);
    }
    final jointsToRemove = doc.magneticJoints.where((j) => j.spotAId == spotId || j.spotBId == spotId).toList();
    for (final j in jointsToRemove) {
      breakMagneticJoint(j.id);
    }
    notifyDocChanged();
  }

  bool createMagneticJoint({required String partAId, required String spotAId, required String partBId, required String spotBId}) {
    if (partAId == partBId) return false; // STRICT RULE: same entity coupling forbidden
    final pA = doc.parts.where((p) => p.id == partAId).firstOrNull;
    final pB = doc.parts.where((p) => p.id == partBId).firstOrNull;
    if (pA == null || pB == null) return false;

    final spotA = pA.magneticSpots.where((s) => s.id == spotAId).firstOrNull;
    final spotB = pB.magneticSpots.where((s) => s.id == spotBId).firstOrNull;
    if (spotA == null || spotB == null) return false;

    _recordUndo();

    // 1. Calculate world positions of both magnetic spots
    final worldSpotA = spotA.toWorldPoint(pA);
    final worldSpotB = spotB.toWorldPoint(pB);

    // 2. Attract Entity B to Entity A:
    // Translate Part B by the delta so spot B aligns with spot A
    final delta = CadPoint3D(worldSpotA.x - worldSpotB.x, worldSpotA.y - worldSpotB.y, worldSpotA.z - worldSpotB.z);

    pB.position = CadPoint3D(pB.position.x + delta.x, pB.position.y + delta.y, pB.position.z + delta.z);

    // 3. Register the magnetic link
    final jointId = _generateId('mag_joint');
    final joint = AssemblyMagneticJoint(id: jointId, partAId: partAId, spotAId: spotAId, partBId: partBId, spotBId: spotBId);
    doc.magneticJoints.add(joint);

    if (!pA.magneticallyLinkedPartIds.contains(pB.id)) {
      pA.magneticallyLinkedPartIds.add(pB.id);
    }
    if (!pB.magneticallyLinkedPartIds.contains(pA.id)) {
      pB.magneticallyLinkedPartIds.add(pA.id);
    }

    notifyDocChanged();
    return true;
  }

  void breakMagneticJoint(String jointId) {
    _recordUndo();
    final joint = doc.magneticJoints.where((j) => j.id == jointId).firstOrNull;
    if (joint == null) return;

    doc.magneticJoints.removeWhere((j) => j.id == jointId);

    final stillLinked = doc.magneticJoints.any(
      (j) => (j.partAId == joint.partAId && j.partBId == joint.partBId) || (j.partAId == joint.partBId && j.partBId == joint.partAId),
    );
    if (!stillLinked) {
      final pA = doc.parts.where((p) => p.id == joint.partAId).firstOrNull;
      final pB = doc.parts.where((p) => p.id == joint.partBId).firstOrNull;
      pA?.magneticallyLinkedPartIds.remove(joint.partBId);
      pB?.magneticallyLinkedPartIds.remove(joint.partAId);
    }

    notifyDocChanged();
  }

  void breakAllMagneticJointsForPart(String partId) {
    _recordUndo();
    final joints = doc.magneticJoints.where((j) => j.partAId == partId || j.partBId == partId).toList();
    for (final j in joints) {
      breakMagneticJoint(j.id);
    }
    final target = doc.parts.where((p) => p.id == partId).firstOrNull;
    target?.magneticallyLinkedPartIds.clear();
    for (final p in doc.parts) {
      p.magneticallyLinkedPartIds.remove(partId);
    }
    notifyDocChanged();
  }

  bool isPartMagneticallyLinked(String partId) {
    return doc.magneticJoints.any((j) => j.partAId == partId || j.partBId == partId);
  }

  Set<String> getMagneticallyLinkedClusterPartIds(String partId) {
    final cluster = <String>{partId};
    final queue = <String>[partId];
    while (queue.isNotEmpty) {
      final curr = queue.removeLast();
      for (final j in doc.magneticJoints) {
        if (j.partAId == curr && cluster.add(j.partBId)) queue.add(j.partBId);
        if (j.partBId == curr && cluster.add(j.partAId)) queue.add(j.partAId);
      }
    }
    return cluster;
  }

  // -------------------------------------------------------------
  // WYSIWYG Face Sketch Mode (Draw Sketch on Face)
  // -------------------------------------------------------------
  // -------------------------------------------------------------
  // WYSIWYG Face Sketch Mode & 'S' Key Focus
  // -------------------------------------------------------------
  void enterSketchMode({String? faceId}) {
    if (faceId == null && selectedPart == null && activeSketchPlane == null) {
      enterPlaneSelectionMode();
      return;
    }
    focusPartAndEnterSketch(selectedPart?.id, faceId: faceId);
  }

  void enterPlaneSelectionMode() {
    isPlaneSelectionMode = true;
    hoveredPlaneId = null;
    notifyListeners();
  }

  void exitPlaneSelectionMode() {
    isPlaneSelectionMode = false;
    hoveredPlaneId = null;
    notifyListeners();
  }

  void togglePlaneSelectionMode() {
    if (isPlaneSelectionMode) {
      exitPlaneSelectionMode();
    } else {
      enterPlaneSelectionMode();
    }
  }

  void setHoveredPlane(String? planeId) {
    if (hoveredPlaneId == planeId) return;
    hoveredPlaneId = planeId;
    notifyListeners();
  }

  /// Selects a specific plane for sketch, locks 3D movement and aligns the camera normal.
  void selectPlaneForSketch(CADSketchPlane plane) {
    activeSketchPlane = plane;
    if (!savedSketchPlanes.any((p) => p.id == plane.id)) {
      savedSketchPlanes.add(plane);
    }
    sketchPartId = plane.targetPartId ?? selectedPart?.id;
    sketchFaceId = plane.targetFaceId ?? plane.id;
    doc.selectedFaceId = sketchFaceId;
    isSketchMode = true;
    isPlaneSelectionMode = false;
    hoveredPlaneId = null;
    is3DMovementLocked = true;

    alignCameraToActivePlaneNormal();
    notifyListeners();
  }

  /// Adds an Offset Construction Plane parallel to a reference plane.
  CADSketchPlane addOffsetConstructionPlane({required String parentPlaneId, required double offsetMm, String? name, double size = 140.0}) {
    final parent = allAvailablePlanes.where((p) => p.id == parentPlaneId).firstOrNull ?? datumPlaneXY;
    final newPlane = AssemblySurfaceSketchEngine.createOffsetPlane(parentPlane: parent, offsetMm: offsetMm, name: name, size: size);
    constructionPlanes.add(newPlane);
    recordTimelineFeature(
      name: newPlane.name,
      type: AssemblyTimelineFeatureType.constructionPlane,
      entityId: newPlane.id,
      parameters: {'offsetMm': offsetMm, 'parentPlaneId': parentPlaneId},
    );
    notifyListeners();
    return newPlane;
  }

  /// Adds an Angle Construction Plane rotated around an axis.
  CADSketchPlane addAngleConstructionPlane({
    required String referencePlaneId,
    required vm_math.Vector3 axisOrigin,
    required vm_math.Vector3 axisDir,
    required double angleDeg,
    String? name,
    double size = 140.0,
  }) {
    final parent = allAvailablePlanes.where((p) => p.id == referencePlaneId).firstOrNull ?? datumPlaneXY;
    final newPlane = AssemblySurfaceSketchEngine.createAnglePlane(
      referencePlane: parent,
      axisOrigin: axisOrigin,
      axisDir: axisDir,
      angleDeg: angleDeg,
      name: name,
      size: size,
    );
    constructionPlanes.add(newPlane);
    recordTimelineFeature(
      name: newPlane.name,
      type: AssemblyTimelineFeatureType.constructionPlane,
      entityId: newPlane.id,
      parameters: {'angleDeg': angleDeg, 'referencePlaneId': referencePlaneId},
    );
    notifyListeners();
    return newPlane;
  }

  /// Removes a user construction plane.
  void removeConstructionPlane(String planeId) {
    constructionPlanes.removeWhere((p) => p.id == planeId);
    if (activeSketchPlane?.id == planeId) {
      exitSketchMode();
    }
    notifyListeners();
  }

  void toggleDatumPlanesVisibility() {
    showDatumPlanes = !showDatumPlanes;
    notifyListeners();
  }

  void toggleConstructionPlanesVisibility() {
    showConstructionPlanes = !showConstructionPlanes;
    notifyListeners();
  }

  void toggleOriginTriadVisibility() {
    showOriginTriad = !showOriginTriad;
    notifyListeners();
  }

  bool _previousOrthoBeforeSketch = false;

  /// Activates sketch mode on a specific face polygon extracted from the 3D mesh.
  void activateSketchOnFacePolygon(CadFoldedPolygon3D polygon, {String? partId}) {
    final targetPart = doc.parts.where((p) => p.id == partId).firstOrNull ?? selectedPart;
    if (targetPart == null && doc.parts.isNotEmpty) {
      doc.selectedPartId = doc.parts.first.id;
    }
    final part = doc.parts.where((p) => p.id == partId).firstOrNull ?? selectedPart;

    // Check if this surface already has a saved sketch plane
    CADSketchPlane? plane = savedSketchPlanes.where((p) => p.targetFaceId == polygon.faceId).firstOrNull;

    if (plane == null) {
      plane = AssemblySurfaceSketchEngine.createPlaneFromFacePolygon(polygon: polygon, partId: part?.id);
      plane.name = generateNextSketchName();
      savedSketchPlanes.add(plane);
    }

    activeSketchPlane = plane;
    sketchPartId = part?.id;
    sketchFaceId = polygon.faceId;
    doc.selectedFaceId = polygon.faceId;
    isSketchMode = true;
    is3DMovementLocked = true;

    // Orient camera perpendicular to the plane
    alignCameraToActivePlaneNormal();
    notifyListeners();
  }

  /// Activates sketch mode on a global datum plane (XY, XZ, YZ).
  void activateSketchOnDatum(String datumType) {
    CADSketchPlane? plane = savedSketchPlanes.where((p) => p.id == 'datum_${datumType.toUpperCase()}').firstOrNull;

    if (plane == null) {
      plane = AssemblySurfaceSketchEngine.createDatumPlane(datumType);
      savedSketchPlanes.add(plane);
    }

    activeSketchPlane = plane;
    sketchPartId = selectedPart?.id;
    sketchFaceId = plane.id;
    isSketchMode = true;
    is3DMovementLocked = true;

    alignCameraToActivePlaneNormal();
    solveSketchConstraints();
    notifyListeners();
  }

  /// Aligns camera view directly perpendicular (normal view) facing the active plane and centers on plane origin.
  void alignCameraToActivePlaneNormal() {
    if (activeSketchPlane == null) return;
    pan = Offset.zero;
    cameraPivotOverride = CadPoint3D(activeSketchPlane!.origin.x, activeSketchPlane!.origin.y, activeSketchPlane!.origin.z);
    final angles = AssemblySurfaceSketchEngine.computeNormalViewCameraAngles(activeSketchPlane!.normal);
    azimuthDeg = angles.azimuthDeg;
    elevationDeg = angles.elevationDeg;
    _previousOrthoBeforeSketch = isOrthoProjection;
    isOrthoProjection = true;
    final maxDim = selectedPart != null ? math.max(selectedPart!.length, selectedPart!.height) : 400.0;
    zoom = (850.0 / (maxDim > 0 ? maxDim : 800.0)).clamp(0.65, 2.5);
    notifyListeners();
  }

  /// Focuses the camera directly on the selected part, locks 3D model movement,
  /// and activates real-time 3D sketch mode on the part (triggered by 'S' key).
  void focusPartAndEnterSketch(String? partId, {String? faceId}) {
    final targetId = partId ?? doc.selectedPartId ?? (doc.parts.isNotEmpty ? doc.parts.first.id : null);
    if (targetId == null) return;
    final part = doc.parts.where((p) => p.id == targetId).firstOrNull;
    if (part == null) return;

    doc.selectedPartId = part.id;
    final targetFace = faceId ?? doc.selectedFaceId ?? '${part.id}_web';
    doc.selectedFaceId = targetFace;

    String cleanFaceId = targetFace;
    if (cleanFaceId.startsWith('plane_')) {
      cleanFaceId = cleanFaceId.substring('plane_'.length);
    }

    // Search for polygon matching cleanFaceId in assemblyMesh
    CadFoldedPolygon3D? matchingPoly;
    for (final poly in assemblyMesh.allPolygons) {
      if (poly.faceId == cleanFaceId || poly.faceId.startsWith(cleanFaceId) || cleanFaceId.startsWith(poly.faceId)) {
        matchingPoly = poly;
        break;
      }
    }

    if (matchingPoly == null) {
      for (final poly in assemblyMesh.allPolygons) {
        if (poly.faceId.startsWith(part.id)) {
          if (cleanFaceId.contains('flange') && poly.faceId.contains('flange')) {
            matchingPoly = poly;
            break;
          } else if (cleanFaceId.contains('web') && poly.faceId.contains('web')) {
            matchingPoly = poly;
            break;
          }
        }
      }
    }

    if (matchingPoly != null) {
      activateSketchOnFacePolygon(matchingPoly, partId: part.id);
      return;
    }

    // Default to part face plane with correct world normal & position
    CadPoint3D localNorm = const CadPoint3D(0.0, -1.0, 0.0);
    if (cleanFaceId.contains('top') || cleanFaceId.contains('flange_top')) {
      localNorm = const CadPoint3D(0.0, 0.0, 1.0);
    } else if (cleanFaceId.contains('bot') || cleanFaceId.contains('flange_bot')) {
      localNorm = const CadPoint3D(0.0, 0.0, -1.0);
    }
    final worldNorm = part.normalToWorld(localNorm);
    final normal = vm_math.Vector3(worldNorm.x, worldNorm.y, worldNorm.z);
    final faceCenter = part.toWorld(CadPoint3D(part.length / 2.0, 0.0, part.height / 2.0));
    final origin = vm_math.Vector3(faceCenter.x, faceCenter.y, faceCenter.z);
    final up = vm_math.Vector3(0.0, 0.0, 1.0);
    CADSketchPlane? plane = savedSketchPlanes
        .where((p) => p.targetPartId == part.id && (p.targetFaceId == targetFace || p.targetFaceId == cleanFaceId))
        .firstOrNull;

    if (plane == null) {
      plane = CADSketchPlane(
        id: 'plane_${part.id}_$cleanFaceId',
        name: generateNextSketchName(),
        origin: origin,
        normal: normal,
        up: up,
        targetPartId: part.id,
        targetFaceId: cleanFaceId,
      );
      savedSketchPlanes.add(plane);
    }

    activeSketchPlane = plane;
    isSketchMode = true;
    is3DMovementLocked = true;
    sketchPartId = part.id;
    sketchFaceId = cleanFaceId;

    alignCameraToActivePlaneNormal();
    notifyListeners();
  }

  /// Finishes sketching, unlocks 3D model movement, and returns to full 3D interactive mode.
  void finishSketch() {
    if (activeSketchPlane != null) {
      if (!savedSketchPlanes.any((p) => p.id == activeSketchPlane!.id)) {
        savedSketchPlanes.add(activeSketchPlane!);
      }
      recordTimelineFeature(
        name: activeSketchPlane!.name.startsWith('Sketch') ? activeSketchPlane!.name : 'Sketch on ${activeSketchPlane!.name}',
        type: AssemblyTimelineFeatureType.sketch,
        entityId: activeSketchPlane!.id,
      );
    }
    isSketchMode = false;
    is3DMovementLocked = false;
    isProjectGeometryMode = false;
    clearSketchInteractiveState();
    selectedSketchEntity = null;
    selectedSketchFeatureId = null;
    isOrthoProjection = _previousOrthoBeforeSketch;
    notifyListeners();
  }

  /// Re-enters sketch mode to edit a previously saved sketch.
  void editSketch(CADSketchPlane plane) {
    activeSketchPlane = plane;
    isSketchMode = true;
    is3DMovementLocked = true;
    sketchPartId = plane.targetPartId ?? selectedPart?.id;
    sketchFaceId = plane.targetFaceId ?? plane.id;
    doc.selectedFaceId = sketchFaceId;
    alignCameraToActivePlaneNormal();
    notifyListeners();
  }

  /// Toggles visibility of a specific plane or sketch in the 3D viewport.
  void togglePlaneVisibility(String planeId) {
    for (final p in allAvailablePlanes) {
      if (p.id == planeId) {
        p.isVisible = !p.isVisible;
        notifyListeners();
        return;
      }
    }
  }

  void exitSketchMode() {
    finishSketch();
  }

  /// Converts a 2D point on [plane] into the host [part]'s local 2D face coordinates (0..length, 0..height).
  CadPoint2D _plane2DToPartFaceLocal(CADSketchPlane plane, AssemblyPart part, Offset planePt) {
    final worldVec = plane.toWorld(planePt);
    final local3D = part.worldToLocal(CadPoint3D(worldVec.x, worldVec.y, worldVec.z));
    final faceId = plane.targetFaceId ?? 'web';
    if (faceId.contains('flange_top') || faceId.contains('flange_bot') || faceId.contains('bar_top')) {
      return CadPoint2D(local3D.x, local3D.y.abs());
    }
    return CadPoint2D(local3D.x, local3D.z);
  }

  /// Adds a 2D parametric primitive entity directly to the active sketch plane.
  /// Pure Onshape behavior: drawing a 2D sketch curve NEVER mutates 3D part.sketches until Extrude/Cut is executed!
  void addPrimitiveEntityToActivePlane(CADPrimitiveEntity entity) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    activeSketchPlane!.primitives.add(entity);
    selectedSketchEntity = entity;
    selectedSketchFeatureId = entity.id;

    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(activeSketchPlane!);
    activeSketchValidation = CADProfileValidator.validateProfile(segments);

    solveSketchConstraints();
    notifyListeners();
  }

  /// Updates parameters of the currently selected primitive shape.
  void updateSelectedPrimitiveDimensions({
    double? width,
    double? height,
    double? radius,
    Offset? position,
    FeatureType? featureType,
    bool? isPassThrough,
    double? depthMm,
    bool? isConstruction,
  }) {
    if (selectedSketchEntity == null || activeSketchPlane == null) return;
    _recordUndo();

    final entity = selectedSketchEntity!;
    if (featureType != null) entity.featureType = featureType;
    if (isPassThrough != null) entity.isPassThrough = isPassThrough;
    if (depthMm != null) entity.depthMm = depthMm;
    if (isConstruction != null) entity.isConstruction = isConstruction;

    if (entity is CADRectangleEntity) {
      if (width != null) entity.width = width;
      if (height != null) entity.height = height;
      if (position != null) entity.startPoint = position;
    } else if (entity is CADCenterRectangleEntity) {
      if (width != null) entity.width = width;
      if (height != null) entity.height = height;
      if (position != null) entity.center = position;
    } else if (entity is CADCircleEntity) {
      if (radius != null) entity.radius = radius;
      if (position != null) entity.center = position;
    } else if (entity is CADArcEntity) {
      if (position != null) {
        final d = position - entity.startPoint;
        entity.startPoint = position;
        entity.endPoint = entity.endPoint + d;
        entity.pointOnArc = entity.pointOnArc + d;
      }
      if (radius != null && radius > 0) {
        final chordVec = entity.endPoint - entity.startPoint;
        final chordLen = chordVec.distance;
        if (chordLen > 1e-4) {
          final clampedR = math.max(radius, chordLen / 2.0);
          final mid = Offset((entity.startPoint.dx + entity.endPoint.dx) / 2.0, (entity.startPoint.dy + entity.endPoint.dy) / 2.0);
          final perp = Offset(-chordVec.dy / chordLen, chordVec.dx / chordLen);
          final currentSide = (entity.pointOnArc.dx - mid.dx) * perp.dx + (entity.pointOnArc.dy - mid.dy) * perp.dy;
          final sign = currentSide >= 0 ? 1.0 : -1.0;
          final hDist = math.sqrt(math.max(0.0, clampedR * clampedR - (chordLen / 2.0) * (chordLen / 2.0)));
          final sagitta = clampedR - hDist;
          entity.pointOnArc = mid + perp * (sign * (sagitta > 1e-4 ? sagitta : clampedR));
        }
      }
    } else if (entity is CADLineEntity) {
      if (position != null) {
        final d = entity.end - entity.start;
        entity.start = position;
        entity.end = position + d;
      }
    }

    // Revalidate loop
    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(activeSketchPlane!);
    activeSketchValidation = CADProfileValidator.validateProfile(segments);

    // Sync to part if an extruded/committed feature already exists
    final part = doc.parts.where((p) => p.id == (activeSketchPlane!.targetPartId ?? sketchPartId)).firstOrNull ?? selectedPart;
    if (part != null) {
      final feat = part.sketches.where((s) => s.id == entity.id || s.id == 'cut_${entity.id}').firstOrNull;
      if (feat != null) {
        if (entity is CADRectangleEntity) {
          feat.widthMm = entity.width;
          feat.heightMm = entity.height;
          final c = Offset(entity.startPoint.dx + entity.width / 2.0, entity.startPoint.dy + entity.height / 2.0);
          feat.localCenter = _plane2DToPartFaceLocal(activeSketchPlane!, part, c);
        } else if (entity is CADCenterRectangleEntity) {
          feat.widthMm = entity.width;
          feat.heightMm = entity.height;
          feat.localCenter = _plane2DToPartFaceLocal(activeSketchPlane!, part, entity.center);
        } else if (entity is CADCircleEntity) {
          feat.widthMm = entity.radius * 2.0;
          feat.heightMm = entity.radius * 2.0;
          feat.localCenter = _plane2DToPartFaceLocal(activeSketchPlane!, part, entity.center);
        }
        feat.isPassThrough = entity.isPassThrough;
        feat.isSurfaceImpress = (entity.featureType == FeatureType.extrude && !entity.isPassThrough);
        feat.cutDepthMm = entity.depthMm;
        part.invalidateMeshCache();
        syncComponentInstances(part.id);
      }
    }
    solveSketchConstraints();
    notifyListeners();
  }

  /// Executes boolean void cut on the active surface using the validated sketch profile.
  void executeFeatureCutOnActiveSurface({bool isPassThrough = true, double depthMm = 5.0}) {
    if (activeSketchPlane == null) return;
    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(activeSketchPlane!);
    final validation = CADProfileValidator.validateProfile(segments);
    activeSketchValidation = validation;

    if (!validation.isValidClosedLoop || validation.orderedPathVertices.isEmpty) {
      notifyListeners();
      return;
    }

    _recordUndo();
    final part = doc.parts.where((p) => p.id == (activeSketchPlane!.targetPartId ?? sketchPartId)).firstOrNull ?? selectedPart;
    if (part == null) return;

    final path = validation.orderedPathVertices;
    double sumX = 0, sumY = 0;
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final pt in path) {
      sumX += pt.dx;
      sumY += pt.dy;
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dy > maxY) maxY = pt.dy;
    }
    final count = path.length;
    final cxPlane = sumX / count;
    final cyPlane = sumY / count;
    final w = maxX - minX;
    final h = maxY - minY;

    // CRITICAL FIX: Convert from Sketch Plane (centroid origin) to Part Local (corner origin)!
    final partLocalCenter = _plane2DToPartFaceLocal(activeSketchPlane!, part, Offset(cxPlane, cyPlane));
    final featureId = selectedSketchEntity?.id != null ? 'cut_${selectedSketchEntity!.id}' : _generateId('feature_cut');

    final feat = AssemblySketchFeature(
      id: featureId,
      featureType: 'custom_cut',
      localCenter: partLocalCenter,
      widthMm: w > 0 ? w : 10.0,
      heightMm: h > 0 ? h : 10.0,
      targetFace: activeSketchPlane!.targetFaceId ?? 'web',
      isPassThrough: isPassThrough,
      isSurfaceImpress: !isPassThrough && depthMm == 0.0,
      cutDepthMm: depthMm,
      customPolygonPoints: path.map((p) => Offset(p.dx - cxPlane, p.dy - cyPlane)).toList(),
      planeId: activeSketchPlane!.id,
    );

    // Replace existing cut from the same sketch entity so editing Pos X / Pos Y moves the hole instead of leaving a ghost hole!
    part.sketches.removeWhere((s) => s.id == featureId);
    part.sketches.add(feat);
    sketchFeatureHistory.add(
      CADHistoryItem(
        id: feat.id,
        name: isPassThrough ? 'Pass-Through Void Cut' : 'Surface Cut (${depthMm.toStringAsFixed(1)}mm)',
        timestamp: DateTime.now(),
        referencePlane: activeSketchPlane,
        featureType: FeatureType.cut,
        modificationDepth: isPassThrough ? 1.0 : depthMm,
      ),
    );
    part.invalidateMeshCache();
    syncComponentInstances(part.id);
    notifyListeners();
  }

  /// Deletes currently selected sketch entity from plane and part.
  void deleteSelectedSketchEntity() {
    if (selectedSketchEntity == null || activeSketchPlane == null) return;
    _recordUndo();
    final id = selectedSketchEntity!.id;
    activeSketchPlane!.primitives.removeWhere((p) => p.id == id);
    activeSketchPlane!.entities.removeWhere((s) => s.id == id);

    final part = doc.parts.where((p) => p.id == (activeSketchPlane!.targetPartId ?? sketchPartId)).firstOrNull ?? selectedPart;
    if (part != null) {
      part.sketches.removeWhere((s) => s.id == id);
      syncComponentInstances(part.id);
    }

    selectedSketchEntity = null;
    selectedSketchFeatureId = null;

    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(activeSketchPlane!);
    activeSketchValidation = CADProfileValidator.validateProfile(segments);
    notifyListeners();
  }

  void _convertSelectedRectangleToSegmentsIfNeeded() {
    if (activeSketchPlane == null) return;
    final sel = selectedSketchEntity;
    if (sel is CADRectangleEntity || sel is CADCenterRectangleEntity || sel is CADAlignedRectangleEntity) {
      activeSketchPlane!.primitives.remove(sel);
      final segs = sel!.toLineSegments().where((s) => !s.isConstruction).toList();
      activeSketchPlane!.entities.addAll(segs);
      selectedSketchEntity = null;
    }
  }

  /// Applies chamfer to corners of the active sketch using CADCornerModifier.
  void applyChamferToSelectedCorner(double offsetMm) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    _convertSelectedRectangleToSegmentsIfNeeded();
    final segs = activeSketchPlane!.entities.where((s) => !s.isDeleted && !s.isConstruction).toList();
    if (segs.length < 2) return;
    final newSegs = CADCornerModifier.applyChamfer(segA: segs[0], segB: segs[1], offsetMm: offsetMm);
    activeSketchPlane!.entities.addAll(newSegs);
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }

  /// Applies fillet arc to corners of the active sketch using CADCornerModifier.
  void applyFilletToSelectedCorner(double radiusMm) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    _convertSelectedRectangleToSegmentsIfNeeded();
    final segs = activeSketchPlane!.entities.where((s) => !s.isDeleted && !s.isConstruction).toList();
    if (segs.length < 2) return;
    final newSegs = CADCornerModifier.applyFillet(segA: segs[0], segB: segs[1], radiusMm: radiusMm);
    activeSketchPlane!.entities.addAll(newSegs);
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }

  /// Applies a driving dimension constraint ('D' tool) to the selected sketch entity or pair of entities
  /// and immediately solves the sketch!
  void applyDrivingSketchDimension({
    required String entityId,
    String? secondEntityId,
    required double valueMmOrDeg,
  }) {
    if (activeSketchPlane == null) return;
    final ent = activeSketchPlane!.primitives.where((p) => p.id == entityId).firstOrNull;
    if (ent == null) return;

    _recordUndo();
    CadConstraintType dimType = CadConstraintType.distance;
    if (ent is CADCircleEntity) {
      dimType = CadConstraintType.diameter;
    } else if (ent is CADArcEntity || ent is CADCenterPointArcEntity) {
      dimType = CadConstraintType.radius;
    }

    // Update existing dimension constraint on this entity if one exists, otherwise add a new one
    final existing = activeSketchPlane!.constraints
        .where((c) => c.type == dimType && c.entityIds.contains(entityId))
        .firstOrNull;
    if (existing != null) {
      final idx = activeSketchPlane!.constraints.indexOf(existing);
      activeSketchPlane!.constraints[idx] = existing.copyWith(parameterValue: valueMmOrDeg);
    } else {
      activeSketchPlane!.constraints.add(CadConstraint(
        id: 'dim_${DateTime.now().millisecondsSinceEpoch}',
        type: dimType,
        entityIds: [entityId, ?secondEntityId],
        parameterValue: valueMmOrDeg,
      ));
    }

    solveSketchConstraints();
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }

  void offsetSelectedSketchEntity(double offsetMm) {
    if (activeSketchPlane == null || selectedSketchEntity == null) return;
    _recordUndo();
    final newEnt = OnshapeSketchModifyEngine.offsetEntity(activeSketchPlane!, selectedSketchEntity!, offsetMm);
    if (newEnt != null) {
      selectedSketchEntity = newEnt;
      selectedSketchFeatureId = newEnt.id;
      activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
      notifyListeners();
    }
  }

  void mirrorSelectedSketchEntities() {
    if (activeSketchPlane == null) return;
    final axisLine = activeSketchPlane!.primitives.whereType<CADLineEntity>().where((l) => l.isConstruction).firstOrNull;
    if (axisLine == null) return;
    _recordUndo();
    final targets = selectedSketchEntity != null
        ? [selectedSketchEntity!]
        : activeSketchPlane!.primitives.where((p) => p.id != axisLine.id).toList();
    OnshapeSketchModifyEngine.mirrorEntitiesAcrossLine(
      plane: activeSketchPlane!,
      mirrorAxisLine: axisLine,
      entitiesToMirror: targets,
    );
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }

  void patternSelectedSketchEntitiesLinear({int countX = 3, int countY = 1, double spacingXMm = 40.0, double spacingYMm = 0.0}) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    final targets = selectedSketchEntity != null ? [selectedSketchEntity!] : List<CADPrimitiveEntity>.from(activeSketchPlane!.primitives);
    OnshapeSketchModifyEngine.createSketchLinearPattern(
      plane: activeSketchPlane!,
      sourceEntities: targets,
      countX: countX,
      countY: countY,
      spacingXMm: spacingXMm,
      spacingYMm: spacingYMm,
    );
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }

  void patternSelectedSketchEntitiesCircular({int instanceCount = 4, double totalAngleDeg = 360.0}) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    final targets = selectedSketchEntity != null ? [selectedSketchEntity!] : List<CADPrimitiveEntity>.from(activeSketchPlane!.primitives);
    OnshapeSketchModifyEngine.createSketchCircularPattern(
      plane: activeSketchPlane!,
      sourceEntities: targets,
      center: Offset.zero,
      instanceCount: instanceCount,
      totalAngleDeg: totalAngleDeg,
    );
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }

  void project3DIntersectionToActivePlane() {
    if (hoveredProjectableEdge != null && hoveredProjectableEdge!.length >= 2) {
      project3DEdgeToActivePlane(hoveredProjectableEdge![0], hoveredProjectableEdge![1]);
    } else if (hoveredProjectablePoint != null) {
      project3DVertexToActivePlane(hoveredProjectablePoint!);
    } else {
      enterProjectGeometryMode();
    }
  }

  /// Updates hovered and snapped position on the active sketch plane, evaluating
  /// real-time grid snap and inferencing alignment guides.
  void updateSketchPlaneHover(Offset rawLocalPos) {
    if (activeSketchPlane == null) return;
    final gridSolver = CADGridSolver(gridSpacing: 5.0);
    final snapped = gridSolver.snapToGrid(rawLocalPos);

    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(activeSketchPlane!);
    final guides = <CADInferenceMatch>[];
    final Set<Offset> uniqueV = {};
    for (final s in segments) {
      if (!s.isDeleted) {
        uniqueV.add(s.start);
        uniqueV.add(s.end);
      }
    }
    double finalX = snapped.dx;
    double finalY = snapped.dy;
    for (final v in uniqueV) {
      if ((rawLocalPos.dy - v.dy).abs() < 6.0) {
        guides.add(CADInferenceMatch(value: v.dy, isHorizontal: true, refVertex: v));
        finalY = v.dy;
      }
      if ((rawLocalPos.dx - v.dx).abs() < 6.0) {
        guides.add(CADInferenceMatch(value: v.dx, isHorizontal: false, refVertex: v));
        finalX = v.dx;
      }
    }

    activePlaneHoverLocal = Offset(finalX, finalY);
    activePlaneHoverWorld = activeSketchPlane!.toWorld(activePlaneHoverLocal!);
    currentInferenceGuides = guides;
    notifyListeners();
  }

  @override
  Future<String?> generateIndustrialSTLFilePayload() async {
    isExportingFile = true;
    notifyListeners();
    try {
      final mesh = assemblyMesh;
      if (mesh.allPolygons.isEmpty) return null;
      final List<double> vertices = [];
      final List<int> indices = [];
      int idx = 0;
      for (final poly in mesh.allPolygons) {
        if (poly.vertices.length < 3) continue;
        for (int i = 1; i < poly.vertices.length - 1; i++) {
          final v0 = poly.vertices[0];
          final v1 = poly.vertices[i];
          final v2 = poly.vertices[i + 1];
          vertices.addAll([v0.x, v0.y, v0.z, poly.normal.x, poly.normal.y, poly.normal.z]);
          vertices.addAll([v1.x, v1.y, v1.z, poly.normal.x, poly.normal.y, poly.normal.z]);
          vertices.addAll([v2.x, v2.y, v2.z, poly.normal.x, poly.normal.y, poly.normal.z]);
          indices.addAll([idx, idx + 1, idx + 2]);
          idx += 3;
        }
      }
      final stl = AssemblySurfaceSketchEngine.exportToAsciiStl(
        vertices: Float32List.fromList(vertices),
        indices: Uint16List.fromList(indices),
        modelName: doc.title.isNotEmpty ? doc.title : 'TruFold_Assembly',
      );
      return stl;
    } finally {
      isExportingFile = false;
      notifyListeners();
    }
  }

  /// Serializes the parametric feature history tree to JSON string.
  String serializeSketchHistory() {
    return AssemblySurfaceSketchEngine.serializeHistory(sketchFeatureHistory);
  }

  /// Loads and restores parametric feature history tree from JSON string.
  void loadSketchHistory(String jsonStr) {
    if (jsonStr.isEmpty) return;
    sketchFeatureHistory.clear();
    sketchFeatureHistory.addAll(AssemblySurfaceSketchEngine.deserializeHistory(jsonStr));
    notifyListeners();
  }

  void addSketchFeature({required String featureType, required CadPoint2D localCenter, double widthMm = 10.0, double heightMm = 10.0, double angleDeg = 0.0}) {
    final part = doc.parts.where((p) => p.id == sketchPartId).firstOrNull ?? selectedPart;
    if (part == null) return;

    _recordUndo();
    final isRungSlot = featureType == 'rung_slot';
    final feature = AssemblySketchFeature(
      id: isRungSlot ? _generateId('rung_slot') : _generateId('sketch'),
      featureType: featureType,
      localCenter: localCenter,
      widthMm: isRungSlot ? 40.5 : widthMm,
      heightMm: isRungSlot ? 20.5 : heightMm,
      angleDeg: angleDeg,
      isRungSlotEntity: isRungSlot,
      distanceAlongRailMm: localCenter.x,
      mateStyle: 'passThrough',
    );
    part.sketches.add(feature);
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void removeSketchFeature(String partId, String featureId) {
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null) return;
    _recordUndo();
    part.sketches.removeWhere((s) => s.id == featureId);
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void moveSketchFeature(String partId, String featureId, double deltaX, double deltaY) {
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null) return;
    final feat = part.sketches.where((s) => s.id == featureId).firstOrNull;
    if (feat == null) return;
    _recordUndo();
    feat.localCenter = CadPoint2D(feat.localCenter.x + deltaX, feat.localCenter.y + deltaY);
    feat.distanceAlongRailMm = feat.localCenter.x;

    // If this feature is a mated slot entity linked to a rung, move the rung together with it!
    if (feat.isRungSlotEntity && feat.matedRungPartId != null) {
      final rung = doc.parts.where((p) => p.id == feat.matedRungPartId).firstOrNull;
      if (rung != null) {
        rung.position = CadPoint3D(part.position.x + feat.localCenter.x, rung.position.y, part.position.z + feat.localCenter.y - (rung.height / 2.0));
      }
    }
    syncComponentInstances(part.id);
    notifyListeners();
  }

  void setSketchFeaturePosition(String partId, String featureId, double newX, double newY, {bool recordUndo = false}) {
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null) return;
    final feat = part.sketches.where((s) => s.id == featureId).firstOrNull;
    if (feat == null) return;
    if (recordUndo) {
      _recordUndo();
    }
    feat.localCenter = CadPoint2D(newX, newY);
    feat.distanceAlongRailMm = newX;

    // If this feature is a mated slot entity linked to a rung, move the rung together with it!
    if (feat.isRungSlotEntity && feat.matedRungPartId != null) {
      final rung = doc.parts.where((p) => p.id == feat.matedRungPartId).firstOrNull;
      if (rung != null) {
        rung.position = CadPoint3D(part.position.x + feat.localCenter.x, rung.position.y, part.position.z + feat.localCenter.y - (rung.height / 2.0));
      }
    }
    syncComponentInstances(part.id);
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Punched Rung Hole Entity & C-Channel Snapping/Mating
  // -------------------------------------------------------------

  /// Punches a rung hole on a rail web at a calculated distance X.
  /// This punched hole becomes an interactive assembly entity.
  AssemblySketchFeature punchRungSlot({
    required String railId,
    required double distanceX,
    double slotWidth = 40.5, // Engineered clearance for 40mm rung width
    double slotHeight = 20.5, // Engineered clearance for 20mm rung height
  }) {
    final rail = doc.parts.where((p) => p.id == railId).firstOrNull;
    if (rail == null) {
      throw ArgumentError('Rail with id $railId not found');
    }
    _recordUndo();
    final slotEntity = AssemblySketchFeature(
      id: 'rung_slot_${DateTime.now().microsecondsSinceEpoch}_${distanceX.toInt()}',
      featureType: 'rung_slot',
      localCenter: CadPoint2D(distanceX, rail.height / 2.0),
      widthMm: slotWidth,
      heightMm: slotHeight,
      isRungSlotEntity: true,
      distanceAlongRailMm: distanceX,
      mateStyle: 'passThrough',
      isUpsideDown: false,
    );
    rail.sketches.add(slotEntity);
    notifyListeners();
    return slotEntity;
  }

  /// Automatically punches multiple evenly spaced rung hole entities along the rail.
  void punchEvenRungSlots(String railId, {int count = 4}) {
    final rail = doc.parts.where((p) => p.id == railId).firstOrNull;
    if (rail == null || count <= 0) return;
    _recordUndo();
    final pitch = rail.length / (count + 1);
    for (int i = 1; i <= count; i++) {
      final dx = pitch * i;
      punchRungSlot(railId: railId, distanceX: dx);
    }
  }

  /// Links a C-channel to a punched rung slot entity.
  /// The C-channel acts as a rung and reorients itself to fit exactly within the hole.
  void linkRungToSlot({required String slotEntityId, required String rungPartId, String mateStyle = 'passThrough', bool isUpsideDown = false}) {
    AssemblyPart? parentRail;
    AssemblySketchFeature? slotEntity;
    for (final p in doc.parts) {
      for (final sk in p.sketches) {
        if (sk.id == slotEntityId) {
          parentRail = p;
          slotEntity = sk;
          break;
        }
      }
      if (slotEntity != null) break;
    }

    final rung = doc.parts.where((p) => p.id == rungPartId).firstOrNull;
    if (parentRail == null || slotEntity == null || rung == null) return;
    final rail = parentRail;

    _recordUndo();

    slotEntity.matedRungPartId = rung.id;
    slotEntity.mateStyle = mateStyle;
    slotEntity.isUpsideDown = isUpsideDown;

    rung.parentPartId = rail.id;
    rung.matedSlotEntityId = slotEntity.id;
    rung.mateStyle = mateStyle;
    rung.isRungUpsideDown = isUpsideDown;
    rung.jointType = AssemblyJointType.slotMate;

    // Snap and reorient rung to fit precisely within the punched hole:
    // X aligns with slot's X position along rail
    // Z centers the 20mm rung within the 20.5mm slot
    // Y aligns with rail web: passThrough protrudes -10mm for outer welding, directInside is flush at 0.0mm
    final snapX = rail.position.x + slotEntity.localCenter.x;
    final snapZ = rail.position.z + slotEntity.localCenter.y - (rung.height / 2.0);
    final snapY = rail.position.y + (mateStyle == 'passThrough' ? -10.0 : 0.0);

    rung.position = CadPoint3D(snapX, snapY, snapZ);
    // Transverse along Y (Yaw = 90°), Roll = 180° if upside down
    rung.rotationDeg = CadPoint3D(isUpsideDown ? 180.0 : 0.0, 0.0, 90.0);

    doc.welds.removeWhere((w) => (w.partAId == rail.id && w.partBId == rung.id) || (w.partAId == rung.id && w.partBId == rail.id));

    final joint = AssemblyWeldJoint(
      id: _generateId('joint_mate'),
      partAId: rail.id,
      partBId: rung.id,
      weldPoint: rung.position,
      jointDescription: 'Rung-Slot Mate ($mateStyle)',
      jointType: AssemblyJointType.slotMate,
      mateStyle: mateStyle,
    );
    doc.welds.add(joint);

    if (!parentRail.weldedToPartIds.contains(rung.id)) {
      parentRail.weldedToPartIds.add(rung.id);
    }
    if (!rung.weldedToPartIds.contains(parentRail.id)) {
      rung.weldedToPartIds.add(parentRail.id);
    }

    notifyListeners();
  }

  /// Toggles rung upside down (180° flip along longitudinal axis) while maintaining slot fit.
  void toggleRungUpsideDown(String rungId) {
    final rung = doc.parts.where((p) => p.id == rungId).firstOrNull;
    if (rung == null) return;

    _recordUndo();
    rung.isRungUpsideDown = !rung.isRungUpsideDown;

    if (rung.matedSlotEntityId != null) {
      for (final p in doc.parts) {
        for (final sk in p.sketches) {
          if (sk.id == rung.matedSlotEntityId) {
            sk.isUpsideDown = rung.isRungUpsideDown;
            break;
          }
        }
      }
    }

    // Keep Yaw at 90° (transverse) and flip Roll by 180°
    final curYaw = rung.rotationDeg.z;
    rung.rotationDeg = CadPoint3D(rung.isRungUpsideDown ? 180.0 : 0.0, rung.rotationDeg.y, curYaw);

    notifyListeners();
  }

  /// Sets rung joint style: 'passThrough' (protrudes -10mm for exterior welding) vs 'directInside' (flush).
  void setRungJointStyle(String rungId, String mateStyle) {
    final rung = doc.parts.where((p) => p.id == rungId).firstOrNull;
    if (rung == null) return;

    _recordUndo();
    rung.mateStyle = mateStyle;

    if (rung.parentPartId != null) {
      final parentRail = doc.parts.where((p) => p.id == rung.parentPartId).firstOrNull;
      if (parentRail != null) {
        final newY = parentRail.position.y + (mateStyle == 'passThrough' ? -10.0 : 0.0);
        rung.position = CadPoint3D(rung.position.x, newY, rung.position.z);
      }
    }

    if (rung.matedSlotEntityId != null) {
      for (final p in doc.parts) {
        for (final sk in p.sketches) {
          if (sk.id == rung.matedSlotEntityId) {
            sk.mateStyle = mateStyle;
            break;
          }
        }
      }
    }

    for (final w in doc.welds) {
      if ((w.partAId == rung.id || w.partBId == rung.id) && w.jointType == AssemblyJointType.slotMate) {
        // Updated joint style
      }
    }

    notifyListeners();
  }

  /// General joining mode between any 2 parts (fused, welded, hinged, slotMate).
  void joinParts(
    String partAId,
    String partBId,
    AssemblyJointType jointType, {
    double hingeAngleDeg = 0.0,
    String mateStyle = 'passThrough',
    String description = 'Joint Bond',
  }) {
    final pA = doc.parts.where((p) => p.id == partAId).firstOrNull;
    final pB = doc.parts.where((p) => p.id == partBId).firstOrNull;
    if (pA == null || pB == null || partAId == partBId) return;

    _recordUndo();
    pB.parentPartId = pA.id;
    pB.jointType = jointType;
    pB.hingeAngleDeg = hingeAngleDeg;

    final joint = AssemblyWeldJoint(
      id: _generateId('joint'),
      partAId: partAId,
      partBId: partBId,
      weldPoint: CadPoint3D((pA.position.x + pB.position.x) / 2.0, (pA.position.y + pB.position.y) / 2.0, (pA.position.z + pB.position.z) / 2.0),
      jointDescription: description,
      jointType: jointType,
      hingeAngleDeg: hingeAngleDeg,
      mateStyle: mateStyle,
    );

    doc.welds.add(joint);
    if (!pA.weldedToPartIds.contains(pB.id)) pA.weldedToPartIds.add(pB.id);
    if (!pB.weldedToPartIds.contains(pA.id)) pB.weldedToPartIds.add(pA.id);

    notifyListeners();
  }

  /// Separates two parts at any time, breaking their weld/joint/mate and returning them to independent entities.
  void separateParts(String partAId, String partBId) {
    _recordUndo();
    doc.welds.removeWhere((w) => (w.partAId == partAId && w.partBId == partBId) || (w.partAId == partBId && w.partBId == partAId));

    final pA = doc.parts.where((p) => p.id == partAId).firstOrNull;
    final pB = doc.parts.where((p) => p.id == partBId).firstOrNull;

    if (pB != null && pB.parentPartId == partAId) {
      pB.parentPartId = null;
      pB.jointType = null;
      pB.matedSlotEntityId = null;
    }
    if (pA != null && pA.parentPartId == partBId) {
      pA.parentPartId = null;
      pA.jointType = null;
      pA.matedSlotEntityId = null;
    }

    pA?.weldedToPartIds.remove(partBId);
    pB?.weldedToPartIds.remove(partAId);

    for (final p in doc.parts) {
      for (final sk in p.sketches) {
        if (sk.matedRungPartId == partAId || sk.matedRungPartId == partBId) {
          sk.matedRungPartId = null;
        }
      }
    }

    notifyListeners();
  }

  /// Checks whether a part has any active bonds, weld joints, or parent attachments.
  bool isPartBonded(String partId) {
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null) return false;
    if (part.weldedToPartIds.isNotEmpty) return true;
    if (part.parentPartId != null) return true;
    if (doc.welds.any((w) => w.partAId == partId || w.partBId == partId)) return true;
    if (doc.parts.any((p) => p.parentPartId == partId)) return true;
    if (doc.magneticJoints.any((j) => j.partAId == partId || j.partBId == partId)) return true;
    return false;
  }

  /// Finds all part IDs transitively welded or bonded to [partId].
  Set<String> getBondedClusterPartIds(String partId) {
    final cluster = <String>{partId};
    final queue = <String>[partId];
    while (queue.isNotEmpty) {
      final currId = queue.removeLast();
      final currPart = doc.parts.where((p) => p.id == currId).firstOrNull;
      if (currPart != null) {
        for (final wId in currPart.weldedToPartIds) {
          if (cluster.add(wId)) queue.add(wId);
        }
        for (final mId in currPart.magneticallyLinkedPartIds) {
          if (cluster.add(mId)) queue.add(mId);
        }
        if (currPart.parentPartId != null && cluster.add(currPart.parentPartId!)) {
          queue.add(currPart.parentPartId!);
        }
      }
      for (final w in doc.welds) {
        if (w.partAId == currId && cluster.add(w.partBId)) queue.add(w.partBId);
        if (w.partBId == currId && cluster.add(w.partAId)) queue.add(w.partAId);
      }
      for (final j in doc.magneticJoints) {
        if (j.partAId == currId && cluster.add(j.partBId)) queue.add(j.partBId);
        if (j.partBId == currId && cluster.add(j.partAId)) queue.add(j.partAId);
      }
      for (final p in doc.parts) {
        if (p.parentPartId == currId && cluster.add(p.id)) queue.add(p.id);
      }
    }
    return cluster;
  }

  /// Breaks all welds and bonds for the specified part, releasing it to be freely moved or dragged.
  void breakAllBondsForPart(String partId) {
    _recordUndo();
    doc.welds.removeWhere((w) => w.partAId == partId || w.partBId == partId);
    breakAllMagneticJointsForPart(partId);
    final target = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (target != null) {
      target.weldedToPartIds.clear();
      target.parentPartId = null;
      target.jointType = null;
      target.matedSlotEntityId = null;
    }
    for (final p in doc.parts) {
      p.weldedToPartIds.remove(partId);
      if (p.parentPartId == partId) {
        p.parentPartId = null;
        p.jointType = null;
        p.matedSlotEntityId = null;
      }
      for (final sk in p.sketches) {
        if (sk.matedRungPartId == partId) {
          sk.matedRungPartId = null;
        }
      }
    }
    notifyListeners();
  }

  /// Separates the currently selected part from all parent sets and bonded parts by breaking all its welds.
  void separateSelectedPart() {
    final part = selectedPart;
    if (part == null) return;
    breakAllBondsForPart(part.id);
  }

  // -------------------------------------------------------------
  // Prebuilt Demos & Presets
  // -------------------------------------------------------------
  void clearAll() {
    _recordUndo();
    doc.parts.clear();
    doc.welds.clear();
    doc.selectedPartId = null;
    doc.selectedFaceId = null;
    timelineItems.clear();
    constructionPlanes.clear();
    timelineRollbackIndex = 0;
    notifyListeners();
  }

  /// Spawns a realistic standard ladder segment: 2 side rails + 4 slotted rungs fitted into punched slot entities.
  void loadStandardLadderDemo() {
    _recordUndo();
    doc.parts.clear();
    doc.welds.clear();
    doc.selectedPartId = null;
    doc.selectedPartIds.clear();

    const double ladderLength = 1000.0;
    const double ladderWidth = 600.0;
    const double railHeight = 100.0;
    const double flangeW = 20.0; // 20mm default flange

    // Left Rail (Straight C-channel, flange facing inward)
    final leftRail = AssemblyPart(
      id: 'rail_left',
      name: 'Left Side Rail',
      type: AssemblyPartType.straightRail,
      length: ladderLength,
      height: railHeight,
      flangeWidth: flangeW,
      isFlangeOutward: false,
      position: const CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF6C9DC6), // Onshape Cerulean Steel-Blue
    );

    // Right Rail (Flange facing inward toward left rail)
    final rightRail = AssemblyPart(
      id: 'rail_right',
      name: 'Right Side Rail',
      type: AssemblyPartType.straightRail,
      length: ladderLength,
      height: railHeight,
      flangeWidth: flangeW,
      isFlangeOutward: true,
      position: CadPoint3D(0.0, ladderWidth, 0.0),
      color: const Color(0xFF6C9DC6), // Onshape Cerulean Steel-Blue
    );

    doc.parts.addAll([leftRail, rightRail]);

    // 4 C-channel slotted rungs along X axis mated to punched rung slot entities
    final rungPositions = [125.0, 375.0, 625.0, 875.0];
    for (int i = 0; i < rungPositions.length; i++) {
      final rx = rungPositions[i];
      final rungId = 'rung_${i + 1}';

      // Punch slot entity on left rail web and right rail web
      final slotEntityLeft = punchRungSlot(railId: leftRail.id, distanceX: rx);
      final slotEntityRight = punchRungSlot(railId: rightRail.id, distanceX: rx);

      // Create C-channel rung
      // Pass-through rung extends symmetrically with 10mm protrusion through both rail webs
      final rung = AssemblyPart(
        id: rungId,
        name: 'Rung #${i + 1}',
        type: AssemblyPartType.rung,
        length: ladderWidth + 20.0,
        height: 20.0,
        flangeWidth: 20.0,
        thickness: 1.5,
        parentPartId: leftRail.id,
        matedSlotEntityId: slotEntityLeft.id,
        mateStyle: 'passThrough',
        position: CadPoint3D(rx, -10.0, (railHeight / 2.0) - 10.0), // Pass through protrudes -10mm
        rotationDeg: const CadPoint3D(0.0, 0.0, 90.0), // Transverse along Y
        color: const Color(0xFF5B8DB8), // Onshape Medium Cerulean
        jointType: AssemblyJointType.slotMate,
      );
      slotEntityLeft.matedRungPartId = rungId;
      slotEntityRight.matedRungPartId = rungId;
      doc.parts.add(rung);

      final double topZ = (railHeight / 2.0) + 10.0;
      final double botZ = (railHeight / 2.0) - 10.0;

      // Both-sides fillet weld to left rail (AWS D1.1 / ISO 2553 per SS4 & SS5)
      doc.welds.add(
        AssemblyWeldJoint(
          id: 'weld_left_${i + 1}',
          partAId: leftRail.id,
          partBId: rungId,
          weldPoint: CadPoint3D(rx, 0.0, topZ),
          weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
          weldLengthMm: 40.0,
          weldSizeMm: 6.0,
          legDir1: const CadPoint3D(0.0, 0.0, 1.0),
          legDir2: const CadPoint3D(0.0, 1.0, 0.0),
          bothSides: true,
          secondWeldPoint: CadPoint3D(rx, 0.0, botZ),
          secondLegDir1: const CadPoint3D(0.0, 0.0, -1.0),
          secondLegDir2: const CadPoint3D(0.0, 1.0, 0.0),
          jointDescription: 'Rung-to-Rail Both-Sides Fillet Weld (6mm)',
          jointType: AssemblyJointType.welded,
          mateStyle: 'passThrough',
        ),
      );
      leftRail.weldedToPartIds.add(rungId);
      rung.weldedToPartIds.add(leftRail.id);

      // Both-sides fillet weld to right rail (AWS D1.1 / ISO 2553 per SS4 & SS5)
      doc.welds.add(
        AssemblyWeldJoint(
          id: 'weld_right_${i + 1}',
          partAId: rightRail.id,
          partBId: rungId,
          weldPoint: CadPoint3D(rx, ladderWidth, topZ),
          weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
          weldLengthMm: 40.0,
          weldSizeMm: 6.0,
          legDir1: const CadPoint3D(0.0, 0.0, 1.0),
          legDir2: const CadPoint3D(0.0, -1.0, 0.0),
          bothSides: true,
          secondWeldPoint: CadPoint3D(rx, ladderWidth, botZ),
          secondLegDir1: const CadPoint3D(0.0, 0.0, -1.0),
          secondLegDir2: const CadPoint3D(0.0, -1.0, 0.0),
          jointDescription: 'Rung-to-Rail Both-Sides Fillet Weld (6mm)',
          jointType: AssemblyJointType.welded,
          mateStyle: 'passThrough',
        ),
      );
      rightRail.weldedToPartIds.add(rungId);
      rung.weldedToPartIds.add(rightRail.id);
    }

    timelineItems.clear();
    recordTimelineFeature(name: 'Origin Datum (XY)', type: AssemblyTimelineFeatureType.originPlane, entityId: 'datum_XY');
    recordTimelineFeature(name: 'Left Side Rail', type: AssemblyTimelineFeatureType.extrude, entityId: leftRail.id);
    recordTimelineFeature(name: 'Right Side Rail', type: AssemblyTimelineFeatureType.extrude, entityId: rightRail.id);
    for (int i = 0; i < 4; i++) {
      recordTimelineFeature(name: 'Rung ${i + 1}', type: AssemblyTimelineFeatureType.extrude, entityId: 'rung_${i + 1}');
      recordTimelineFeature(name: 'Fillet Weld ${i + 1}', type: AssemblyTimelineFeatureType.weld, entityId: 'weld_left_${i + 1}');
    }

    doc.selectedPartId = 'rail_left';
    notifyListeners();
  }

  /// Spawns a Tee junction ladder assembly using straight rail, 2 bent rails (with flange V-notches), and welded rungs.
  void loadTeeAssemblyDemo() {
    _recordUndo();
    doc.parts.clear();
    doc.welds.clear();

    const double flangeW = 20.0;
    const double railH = 100.0;

    // Main run straight rail
    final mainRail = AssemblyPart(
      id: 'main_rail_1',
      name: 'Main Run Rail',
      type: AssemblyPartType.straightRail,
      length: 1200.0,
      height: railH,
      flangeWidth: flangeW,
      position: const CadPoint3D(0.0, 0.0, 0.0),
      color: const Color(0xFF64748B),
    );

    // Left curved branch rail (3 segments: run, 45° bend with auto V-notch, branch run)
    final branchLeft = AssemblyPart(
      id: 'branch_left',
      name: 'Branch Left Rail (3 Segments)',
      type: AssemblyPartType.bentRail,
      height: railH,
      flangeWidth: flangeW,
      segments: [
        RailSegmentDefinition(id: 's1', length: 300.0, bendAngleDeg: 0.0),
        RailSegmentDefinition(id: 's2', length: 250.0, bendAngleDeg: 45.0, hasFlangeVNotch: true),
        RailSegmentDefinition(id: 's3', length: 400.0, bendAngleDeg: 0.0, hasFlangeVNotch: true),
      ],
      position: const CadPoint3D(300.0, 600.0, 0.0),
      color: const Color(0xFF475569),
    );

    // Right curved branch rail
    final branchRight = AssemblyPart(
      id: 'branch_right',
      name: 'Branch Right Rail (3 Segments)',
      type: AssemblyPartType.bentRail,
      height: railH,
      flangeWidth: flangeW,
      segments: [
        RailSegmentDefinition(id: 's1', length: 300.0, bendAngleDeg: 0.0),
        RailSegmentDefinition(id: 's2', length: 250.0, bendAngleDeg: -45.0, hasFlangeVNotch: true),
        RailSegmentDefinition(id: 's3', length: 400.0, bendAngleDeg: 0.0, hasFlangeVNotch: true),
      ],
      position: const CadPoint3D(900.0, 600.0, 0.0),
      color: const Color(0xFF475569),
    );

    doc.parts.addAll([mainRail, branchLeft, branchRight]);

    // Add rungs
    for (int i = 0; i < 3; i++) {
      final rungId = 'tee_rung_${i + 1}';
      final rung = AssemblyPart(
        id: rungId,
        name: 'Main Rung #${i + 1}',
        type: AssemblyPartType.rung,
        length: 600.0,
        height: 20.0,
        flangeWidth: 20.0,
        position: CadPoint3D(200.0 + (i * 300.0), 0.0, railH / 2.0),
        rotationDeg: const CadPoint3D(0.0, 0.0, 90.0),
        color: const Color(0xFF94A3B8),
      );
      doc.parts.add(rung);
      weldParts(rungId, 'main_rail_1');
    }

    doc.selectedPartId = 'branch_left';
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Phase 2: Industrial Ladder Accessories & Safety Cage Generators
  // -------------------------------------------------------------

  /// Generates a compliant OSHA / EN-ISO Safety Cage Assembly onto the current ladder rails.
  /// Spawns a bottom flared bell entry hoop, standard Ø700mm circular hoops spaced at <= 750mm pitch,
  /// and vertical flat bar straps running along the hoops, creating persistent weld connections.
  void generateSafetyCageAssembly({double? startHeight, double? totalHeight, double hoopDiameter = 700.0, int strapCount = 7, double hoopSpacing = 750.0}) {
    _recordUndo();

    // 1. Identify ladder rails and span
    AssemblyPart? leftRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y <= 100.0).firstOrNull;
    AssemblyPart? rightRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y > 100.0).firstOrNull;

    if (leftRail == null || rightRail == null) {
      final rails = doc.parts.where((p) => p.type == AssemblyPartType.straightRail || p.type == AssemblyPartType.boxTubeStile).toList();
      if (rails.length >= 2) {
        rails.sort((a, b) => a.position.y.compareTo(b.position.y));
        leftRail = rails.first;
        rightRail = rails.last;
      }
    }

    final double ladderLen = leftRail?.length ?? 3000.0;
    final double ladderWidth = (rightRail != null && leftRail != null) ? (rightRail.position.y - leftRail.position.y).abs() : 600.0;
    final double leftRailY = leftRail?.position.y ?? 0.0;
    final double rightRailY = rightRail?.position.y ?? ladderWidth;

    // Default start height: 2200mm for tall ladders, or 40% of ladder length for shorter ladders
    final double actualStart = startHeight ?? (ladderLen > 2500.0 ? 2200.0 : ladderLen * 0.4);
    final double actualEnd = totalHeight ?? ladderLen;
    final double cageSpan = math.max(300.0, actualEnd - actualStart);

    final groupId = 'cage_group_${DateTime.now().millisecondsSinceEpoch}';
    final groupName = 'Safety Cage Assembly (Ø${hoopDiameter.toInt()}mm)';

    // 2. Determine hoop positions along X (height axis)
    final hoopPositions = <double>[actualStart]; // First hoop is flared bell entry hoop
    final int intermediateCount = ((cageSpan - 50.0) / hoopSpacing).floor();
    for (int i = 1; i <= intermediateCount; i++) {
      hoopPositions.add(actualStart + (i * hoopSpacing));
    }
    if (actualEnd > hoopPositions.last + 150.0) {
      hoopPositions.add(actualEnd);
    }

    final hoopParts = <AssemblyPart>[];

    // 3. Spawn Hoops
    for (int i = 0; i < hoopPositions.length; i++) {
      final hx = hoopPositions[i];
      final isBell = i == 0;
      final hoopId = 'hoop_${isBell ? "bell_" : ""}${i + 1}_${DateTime.now().millisecondsSinceEpoch}';

      final hoop = AssemblyPart(
        id: hoopId,
        name: isBell ? 'Bell Entry Hoop (Flared Ø800mm)' : 'Standard Cage Hoop #${i + 1}',
        type: isBell ? AssemblyPartType.safetyCageBellHoop : AssemblyPartType.safetyCageHoop,
        length: 50.0,
        height: hoopDiameter,
        flangeWidth: hoopDiameter,
        thickness: 4.0,
        position: CadPoint3D(hx, leftRailY, leftRail?.height != null ? leftRail!.height / 2.0 : 50.0),
        color: isBell ? const Color(0xFFF59E0B) : const Color(0xFF64748B),
        groupId: groupId,
        groupName: groupName,
      );

      doc.parts.add(hoop);
      hoopParts.add(hoop);

      // Connect welds to rails if rails exist
      if (leftRail != null) {
        doc.welds.add(
          AssemblyWeldJoint(
            id: 'weld_${hoopId}_left',
            partAId: leftRail.id,
            partBId: hoopId,
            weldPoint: CadPoint3D(hx, leftRailY, 50.0),
            jointDescription: 'Hoop Mounting Fillet Weld (5mm)',
          ),
        );
        leftRail.weldedToPartIds.add(hoopId);
        hoop.weldedToPartIds.add(leftRail.id);
      }
      if (rightRail != null) {
        doc.welds.add(
          AssemblyWeldJoint(
            id: 'weld_${hoopId}_right',
            partAId: rightRail.id,
            partBId: hoopId,
            weldPoint: CadPoint3D(hx, rightRailY, 50.0),
            jointDescription: 'Hoop Mounting Fillet Weld (5mm)',
          ),
        );
        rightRail.weldedToPartIds.add(hoopId);
        hoop.weldedToPartIds.add(rightRail.id);
      }
    }

    // 4. Spawn Vertical Straps
    // Arrayed around the hoop perimeter from angle 20° to 160°
    final double radius = hoopDiameter / 2.0;
    final double centerZ = radius;
    final double centerY = leftRailY + (ladderWidth / 2.0);

    for (int s = 0; s < strapCount; s++) {
      final double angleDeg = 20.0 + (s * (140.0 / (strapCount - 1)));
      final double rad = angleDeg * math.pi / 180.0;
      final double sy = centerY + radius * math.cos(rad);
      final double sz = (leftRail?.height ?? 50.0) / 2.0 + centerZ + radius * math.sin(rad);

      final strapId = 'cage_strap_${s + 1}_${DateTime.now().millisecondsSinceEpoch}';
      final strap = AssemblyPart(
        id: strapId,
        name: 'Vertical Cage Strap #${s + 1}',
        type: AssemblyPartType.cageStrap,
        length: cageSpan,
        height: 30.0,
        flangeWidth: 30.0,
        thickness: 3.0,
        position: CadPoint3D(actualStart, sy, sz),
        color: const Color(0xFF94A3B8),
        groupId: groupId,
        groupName: groupName,
      );

      doc.parts.add(strap);

      // Connect weld to each hoop
      for (final hoop in hoopParts) {
        doc.welds.add(
          AssemblyWeldJoint(
            id: 'weld_${strapId}_${hoop.id}',
            partAId: hoop.id,
            partBId: strapId,
            weldPoint: CadPoint3D(hoop.position.x, sy, sz),
            jointDescription: 'Strap-to-Hoop Fillet Weld (3mm)',
          ),
        );
        hoop.weldedToPartIds.add(strapId);
        strap.weldedToPartIds.add(hoop.id);
      }
    }

    doc.selectedPartId = hoopParts.first.id;
    notifyListeners();
  }

  /// Adds OSHA 1060mm flared parapet walk-through top extensions to the current ladder rails.
  void addWalkThroughParapetStiles({double extensionHeight = 1060.0}) {
    _recordUndo();

    AssemblyPart? leftRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y <= 100.0).firstOrNull;
    AssemblyPart? rightRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y > 100.0).firstOrNull;

    final double railLen = leftRail?.length ?? 1000.0;
    final double leftY = leftRail?.position.y ?? 0.0;
    final double rightY = rightRail?.position.y ?? 600.0;
    final double railH = leftRail?.height ?? 100.0;

    // Splice starts 250mm before top of rail
    final double spliceStartX = math.max(0.0, railLen - 250.0);

    // Left walk-through stile
    final leftStile = AssemblyPart(
      id: 'walkthrough_left_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Left Parapet Walk-Through Stile (1060mm)',
      type: AssemblyPartType.walkThroughStile,
      length: extensionHeight,
      height: railH,
      flangeWidth: 30.0,
      isFlangeOutward: false,
      position: CadPoint3D(spliceStartX, leftY, 0.0),
      color: const Color(0xFF38BDF8),
    );

    // Right walk-through stile
    final rightStile = AssemblyPart(
      id: 'walkthrough_right_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Right Parapet Walk-Through Stile (1060mm)',
      type: AssemblyPartType.walkThroughStile,
      length: extensionHeight,
      height: railH,
      flangeWidth: 30.0,
      isFlangeOutward: true,
      position: CadPoint3D(spliceStartX, rightY, 0.0),
      color: const Color(0xFF38BDF8),
    );

    doc.parts.addAll([leftStile, rightStile]);

    // Welds / splices to rails
    if (leftRail != null) {
      doc.welds.add(
        AssemblyWeldJoint(
          id: 'weld_splice_left',
          partAId: leftRail.id,
          partBId: leftStile.id,
          weldPoint: CadPoint3D(railLen, leftY, railH / 2.0),
          jointDescription: 'Stile Splice Fishplate Weld (6mm)',
        ),
      );
      leftRail.weldedToPartIds.add(leftStile.id);
      leftStile.weldedToPartIds.add(leftRail.id);
    }
    if (rightRail != null) {
      doc.welds.add(
        AssemblyWeldJoint(
          id: 'weld_splice_right',
          partAId: rightRail.id,
          partBId: rightStile.id,
          weldPoint: CadPoint3D(railLen, rightY, railH / 2.0),
          jointDescription: 'Stile Splice Fishplate Weld (6mm)',
        ),
      );
      rightRail.weldedToPartIds.add(rightStile.id);
      rightStile.weldedToPartIds.add(rightRail.id);
    }

    doc.selectedPartId = leftStile.id;
    notifyListeners();
  }

  /// Adds wall standoff brackets along the ladder rails at regular spacing (OSHA 175mm clearance).
  void addWallStandoffBrackets({double standoffDepth = 175.0, double spacing = 1500.0}) {
    _recordUndo();

    AssemblyPart? leftRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y <= 100.0).firstOrNull;
    AssemblyPart? rightRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y > 100.0).firstOrNull;

    final double railLen = leftRail?.length ?? 1000.0;
    final double leftY = leftRail?.position.y ?? 0.0;
    final double rightY = rightRail?.position.y ?? 600.0;

    final bracketXPositions = <double>[];
    if (railLen <= 1200.0) {
      bracketXPositions.addAll([200.0, railLen - 200.0]);
    } else {
      final count = (railLen / spacing).ceil() + 1;
      final step = (railLen - 400.0) / (count - 1);
      for (int i = 0; i < count; i++) {
        bracketXPositions.add(200.0 + (i * step));
      }
    }

    for (int i = 0; i < bracketXPositions.length; i++) {
      final bx = bracketXPositions[i];

      // Left bracket
      final bLeft = AssemblyPart(
        id: 'standoff_left_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Wall Standoff Bracket L#${i + 1} (${standoffDepth.toInt()}mm)',
        type: AssemblyPartType.standoffBracket,
        length: standoffDepth,
        height: 80.0,
        flangeWidth: 50.0,
        position: CadPoint3D(bx, leftY, 0.0),
        color: const Color(0xFF64748B),
      );

      // Right bracket
      final bRight = AssemblyPart(
        id: 'standoff_right_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Wall Standoff Bracket R#${i + 1} (${standoffDepth.toInt()}mm)',
        type: AssemblyPartType.standoffBracket,
        length: standoffDepth,
        height: 80.0,
        flangeWidth: 50.0,
        position: CadPoint3D(bx, rightY, 0.0),
        color: const Color(0xFF64748B),
      );

      doc.parts.addAll([bLeft, bRight]);

      if (leftRail != null) {
        doc.welds.add(
          AssemblyWeldJoint(
            id: 'weld_standoff_l_$i',
            partAId: leftRail.id,
            partBId: bLeft.id,
            weldPoint: CadPoint3D(bx, leftY, 0.0),
            jointDescription: 'Bracket Mounting Fillet Weld (4mm)',
          ),
        );
        leftRail.weldedToPartIds.add(bLeft.id);
        bLeft.weldedToPartIds.add(leftRail.id);
      }
      if (rightRail != null) {
        doc.welds.add(
          AssemblyWeldJoint(
            id: 'weld_standoff_r_$i',
            partAId: rightRail.id,
            partBId: bRight.id,
            weldPoint: CadPoint3D(bx, rightY, 0.0),
            jointDescription: 'Bracket Mounting Fillet Weld (4mm)',
          ),
        );
        rightRail.weldedToPartIds.add(bRight.id);
        bRight.weldedToPartIds.add(rightRail.id);
      }
    }

    notifyListeners();
  }

  /// Adds heavy-duty floor base anchor shoe plates at the bottom of the ladder rails.
  void addBaseFootPlates() {
    _recordUndo();

    AssemblyPart? leftRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y <= 100.0).firstOrNull;
    AssemblyPart? rightRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y > 100.0).firstOrNull;

    final double leftY = leftRail?.position.y ?? 0.0;
    final double rightY = rightRail?.position.y ?? 600.0;

    final footLeft = AssemblyPart(
      id: 'foot_plate_left_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Base Anchor Shoe (Left)',
      type: AssemblyPartType.baseFootPlate,
      length: 120.0,
      height: 100.0,
      thickness: 6.0,
      position: CadPoint3D(0.0, leftY, 0.0),
      color: const Color(0xFF475569),
    );

    final footRight = AssemblyPart(
      id: 'foot_plate_right_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Base Anchor Shoe (Right)',
      type: AssemblyPartType.baseFootPlate,
      length: 120.0,
      height: 100.0,
      thickness: 6.0,
      position: CadPoint3D(0.0, rightY, 0.0),
      color: const Color(0xFF475569),
    );

    doc.parts.addAll([footLeft, footRight]);

    if (leftRail != null) {
      doc.welds.add(
        AssemblyWeldJoint(
          id: 'weld_foot_left',
          partAId: leftRail.id,
          partBId: footLeft.id,
          weldPoint: CadPoint3D(0.0, leftY, 0.0),
          jointDescription: 'Base Shoe Heavy Fillet Weld (6mm)',
        ),
      );
      leftRail.weldedToPartIds.add(footLeft.id);
      footLeft.weldedToPartIds.add(leftRail.id);
    }
    if (rightRail != null) {
      doc.welds.add(
        AssemblyWeldJoint(
          id: 'weld_foot_right',
          partAId: rightRail.id,
          partBId: footRight.id,
          weldPoint: CadPoint3D(0.0, rightY, 0.0),
          jointDescription: 'Base Shoe Heavy Fillet Weld (6mm)',
        ),
      );
      rightRail.weldedToPartIds.add(footRight.id);
      footRight.weldedToPartIds.add(rightRail.id);
    }

    doc.selectedPartId = footLeft.id;
    notifyListeners();
  }

  /// Adds a self-closing safety swing gate mounted between the walk-through stiles at the roof exit.
  void addSafetySwingGate() {
    _recordUndo();

    AssemblyPart? leftRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y <= 100.0).firstOrNull;
    AssemblyPart? rightRail = doc.parts.where((p) => p.type == AssemblyPartType.straightRail && p.position.y > 100.0).firstOrNull;

    final double railLen = leftRail?.length ?? 1000.0;
    final double leftY = leftRail?.position.y ?? 0.0;
    final double rightY = rightRail?.position.y ?? 600.0;
    final double span = (rightY - leftY).abs();

    final gate = AssemblyPart(
      id: 'swing_gate_${DateTime.now().millisecondsSinceEpoch}',
      name: 'OSHA Self-Closing Safety Swing Gate',
      type: AssemblyPartType.swingGate,
      length: span,
      height: 420.0,
      position: CadPoint3D(railLen + 200.0, leftY, 50.0),
      rotationDeg: const CadPoint3D(0.0, 0.0, 90.0),
      color: const Color(0xFFFBBF24),
      jointType: AssemblyJointType.hinged,
    );

    doc.parts.add(gate);
    doc.selectedPartId = gate.id;
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Part Visibility in 3D Scene
  // -------------------------------------------------------------
  void togglePartVisibility(String partId) {
    final p = doc.parts.where((x) => x.id == partId).firstOrNull;
    if (p == null) return;
    p.isVisible = !p.isVisible;
    notifyListeners();
  }

  void setPartVisibility(String partId, bool visible) {
    final p = doc.parts.where((x) => x.id == partId).firstOrNull;
    if (p == null) return;
    p.isVisible = visible;
    notifyListeners();
  }

  /// Groups connected, welded, or virtually grouped parts into unified hierarchy tree nodes.
  List<AssemblyGroupNode> getAssemblyHierarchyGroups() {
    final visited = <String>{};
    final groups = <AssemblyGroupNode>[];

    // 1. Collect explicit virtual groups (parts with groupId != null)
    final Map<String, List<AssemblyPart>> virtualGroups = {};
    for (final part in doc.parts) {
      if (part.groupId != null) {
        virtualGroups.putIfAbsent(part.groupId!, () => []).add(part);
      }
    }

    for (final entry in virtualGroups.entries) {
      final grpParts = entry.value;
      for (final p in grpParts) {
        visited.add(p.id);
      }
      final name = grpParts.first.groupName ?? 'Group (${grpParts.length} Parts)';
      final grpWelds = doc.welds.where((w) => grpParts.any((p) => p.id == w.partAId) && grpParts.any((p) => p.id == w.partBId)).toList();
      groups.add(AssemblyGroupNode(id: entry.key, name: name, isConnectedAssembly: true, parts: grpParts, welds: grpWelds));
    }

    // 2. Find all connected components for remaining parts
    for (final part in doc.parts) {
      if (visited.contains(part.id)) continue;

      // Collect all connected parts using BFS
      final connectedPartIds = <String>{};
      final queue = <String>[part.id];
      connectedPartIds.add(part.id);

      while (queue.isNotEmpty) {
        final currentId = queue.removeAt(0);
        final current = doc.parts.where((p) => p.id == currentId).firstOrNull;
        if (current == null) continue;

        // Welded neighbors
        for (final wId in current.weldedToPartIds) {
          if (!connectedPartIds.contains(wId) && doc.parts.any((p) => p.id == wId)) {
            connectedPartIds.add(wId);
            queue.add(wId);
          }
        }

        // Parent part
        if (current.parentPartId != null && !connectedPartIds.contains(current.parentPartId!) && doc.parts.any((p) => p.id == current.parentPartId!)) {
          connectedPartIds.add(current.parentPartId!);
          queue.add(current.parentPartId!);
        }

        // Child parts with parentPartId == current.id
        for (final ch in doc.parts) {
          if (ch.parentPartId == current.id && !connectedPartIds.contains(ch.id)) {
            connectedPartIds.add(ch.id);
            queue.add(ch.id);
          }
        }

        // Welds in doc
        for (final w in doc.welds) {
          if (w.partAId == currentId && !connectedPartIds.contains(w.partBId) && doc.parts.any((p) => p.id == w.partBId)) {
            connectedPartIds.add(w.partBId);
            queue.add(w.partBId);
          } else if (w.partBId == currentId && !connectedPartIds.contains(w.partAId) && doc.parts.any((p) => p.id == w.partAId)) {
            connectedPartIds.add(w.partAId);
            queue.add(w.partAId);
          }
        }
      }

      visited.addAll(connectedPartIds);
      final groupParts = doc.parts.where((p) => connectedPartIds.contains(p.id)).toList();
      final groupWelds = doc.welds.where((w) => connectedPartIds.contains(w.partAId) || connectedPartIds.contains(w.partBId)).toList();

      if (groupParts.length > 1) {
        // Find leader part (prefer rail or first part)
        final leader = groupParts.firstWhere(
          (p) => p.type == AssemblyPartType.straightRail || p.type == AssemblyPartType.bentRail,
          orElse: () => groupParts.first,
        );
        groups.add(
          AssemblyGroupNode(
            id: 'group_${leader.id}',
            name: '${leader.name} Assembly Set (${groupParts.length} Parts)',
            isConnectedAssembly: true,
            parts: groupParts,
            welds: groupWelds,
          ),
        );
      }
    }

    // Collect all independent / loose parts (not in any multi-part assembly)
    final multiGroupPartIds = groups.expand((g) => g.parts.map((p) => p.id)).toSet();
    final looseParts = doc.parts.where((p) => !multiGroupPartIds.contains(p.id)).toList();
    if (looseParts.isNotEmpty) {
      groups.add(
        AssemblyGroupNode(
          id: 'loose_components',
          name: 'Independent Components (${looseParts.length})',
          isConnectedAssembly: false,
          parts: looseParts,
          welds: const [],
        ),
      );
    }

    return groups;
  }

  /// Automatically welds all touching parts at their contact points.
  int autoWeldTouchingParts({double contactToleranceMm = 80.0}) {
    return weldSelectedPartsAtContactPoints(contactToleranceMm: contactToleranceMm);
  }

  /// Breaks the bond between two connected parts.
  void breakBond(String partAId, String partBId) {
    separateParts(partAId, partBId);
  }

  /// Selects an entire group of parts.
  void selectPartGroup(List<String> partIds) {
    _recordUndo();
    doc.selectedPartIds = partIds.toSet();
    doc.selectedPartId = partIds.isNotEmpty ? partIds.first : null;
    notifyListeners();
  }

  /// Selects the entire physical body / virtual group / welded network for a part (SketchUp triple-click).
  void selectPartBodyOrGroup(String partId) {
    if (_lockedToolSelectionPartId != null) {
      return;
    }
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null) return;
    if (part.groupId != null) {
      final groupPartIds = doc.parts.where((p) => p.groupId == part.groupId).map((p) => p.id).toList();
      selectPartGroup(groupPartIds);
    } else {
      // Find all parts welded to this part recursively
      final connected = <String>{part.id};
      final queue = <String>[part.id];
      while (queue.isNotEmpty) {
        final currentId = queue.removeLast();
        final currentPart = doc.parts.where((p) => p.id == currentId).firstOrNull;
        if (currentPart != null) {
          for (final wId in currentPart.weldedToPartIds) {
            if (connected.add(wId)) {
              queue.add(wId);
            }
          }
        }
      }
      selectPartGroup(connected.toList());
    }
  }

  /// Updates the bead size of the currently selected weld.
  void updateSelectedWeldSize(double sizeMm) {
    if (selectedWeldId == null) return;
    final w = doc.welds.where((j) => j.id == selectedWeldId).firstOrNull;
    if (w == null) return;
    _recordUndo();
    final idx = doc.welds.indexOf(w);
    doc.welds[idx] = w.copyWith(weldSizeMm: sizeMm);
    notifyListeners();
  }

  /// Updates the seam length of the currently selected weld bead.
  void updateSelectedWeldLength(double lengthMm) {
    if (selectedWeldId == null) return;
    final w = doc.welds.where((j) => j.id == selectedWeldId).firstOrNull;
    if (w == null) return;
    _recordUndo();
    final idx = doc.welds.indexOf(w);
    doc.welds[idx] = w.copyWith(weldLengthMm: math.max(10.0, lengthMm));
    notifyListeners();
  }

  /// Updates the welding standard or specification of the currently selected weld bead.
  void updateSelectedWeldStandard(String standard) {
    if (selectedWeldId == null) return;
    final w = doc.welds.where((j) => j.id == selectedWeldId).firstOrNull;
    if (w == null) return;
    _recordUndo();
    final idx = doc.welds.indexOf(w);
    doc.welds[idx] = w.copyWith(standard: standard);
    notifyListeners();
  }

  // -------------------------------------------------------------
  // Phase 4: Push/Pull Void Hole Punching
  // -------------------------------------------------------------

  /// Cuts void shapes (circle_hole, obround_slot, rect_cut) through sheet thickness
  /// on web, top flange, bottom flange, or specified target face for true CNC holes.
  void punchVoidHole({
    required String partId,
    String targetFace = 'web',
    required CadPoint2D localCenter,
    required String shape,
    double widthMm = 14.0,
    double heightMm = 14.0,
  }) {
    final part = doc.parts.where((p) => p.id == partId).firstOrNull;
    if (part == null) return;
    _recordUndo();

    final featureId = 'void_${DateTime.now().microsecondsSinceEpoch}';
    final feature = AssemblySketchFeature(
      id: featureId,
      featureType: shape,
      localCenter: localCenter,
      widthMm: widthMm,
      heightMm: heightMm,
      isRungSlotEntity: false,
      targetFace: targetFace,
    );

    part.sketches.add(feature);

    // Propagate to all linked component instances if componentDefinitionId is active
    if (part.componentDefinitionId != null) {
      for (final other in doc.parts) {
        if (other.id != part.id && other.componentDefinitionId == part.componentDefinitionId) {
          other.sketches.add(feature.copyWith(id: 'void_${DateTime.now().microsecondsSinceEpoch}_${other.id.substring(0, math.min(4, other.id.length))}'));
        }
      }
    }

    notifyListeners();
  }

  // -------------------------------------------------------------
  // Phase 4: Live OSHA 1910 & EN ISO 14122-4 Compliance Engine
  // -------------------------------------------------------------

  /// Evaluates full ladder compliance against OSHA 1910.23 / 1910.28 and EN ISO 14122-4.
  AssemblyComplianceReport evaluateLadderCompliance() {
    final items = <ComplianceItemResult>[];

    // 1. Rung Pitch Spacing: 250mm <= P <= 300mm (uniform pitch)
    final rungs = doc.parts
        .where(
          (p) =>
              p.type == AssemblyPartType.rung ||
              p.type == AssemblyPartType.diamondGripRung ||
              p.type == AssemblyPartType.wideStepTread ||
              p.name.toLowerCase().contains('rung') ||
              p.name.toLowerCase().contains('tread'),
        )
        .toList();

    double ladderHeightMm = 0.0;
    for (final p in doc.parts) {
      if (p.position.z + p.height > ladderHeightMm) {
        ladderHeightMm = p.position.z + p.height;
      }
    }

    if (rungs.length < 2) {
      items.add(
        ComplianceItemResult(
          id: 'rung_pitch',
          title: 'Rung Pitch Spacing',
          standardCode: 'OSHA 1910.23(b)(2) / EN ISO 14122-4',
          status: ComplianceStatus.warning,
          measuredValueMm: null,
          minAllowedMm: 250.0,
          maxAllowedMm: 300.0,
          description: 'Only ${rungs.length} rung in assembly. Minimum 2 rungs required to evaluate pitch.',
          recommendation: 'Add rungs along the side rails using linear array (*N) or auto-bridge.',
          fixActionId: 'fix_rung_pitch',
        ),
      );
    } else {
      final double spanX = rungs.map((r) => r.position.x).reduce(math.max) - rungs.map((r) => r.position.x).reduce(math.min);
      final double spanZ = rungs.map((r) => r.position.z).reduce(math.max) - rungs.map((r) => r.position.z).reduce(math.min);
      final bool rungsAlongX = spanX >= spanZ;

      if (rungsAlongX) {
        rungs.sort((a, b) => a.position.x.compareTo(b.position.x));
      } else {
        rungs.sort((a, b) => a.position.z.compareTo(b.position.z));
      }
      final pitches = <double>[];
      for (int i = 0; i < rungs.length - 1; i++) {
        final p = rungsAlongX ? (rungs[i + 1].position.x - rungs[i].position.x).abs() : (rungs[i + 1].position.z - rungs[i].position.z).abs();
        pitches.add(p);
      }
      final double avgPitch = pitches.reduce((a, b) => a + b) / pitches.length;
      final double minPitch = pitches.reduce(math.min);
      final double maxPitch = pitches.reduce(math.max);
      final double pitchDelta = maxPitch - minPitch;

      ComplianceStatus pitchStatus;
      if (minPitch >= 250.0 && maxPitch <= 300.0 && pitchDelta <= 10.0) {
        pitchStatus = ComplianceStatus.pass;
      } else if (minPitch >= 235.0 && maxPitch <= 325.0) {
        pitchStatus = ComplianceStatus.warning;
      } else {
        pitchStatus = ComplianceStatus.fail;
      }

      items.add(
        ComplianceItemResult(
          id: 'rung_pitch',
          title: 'Rung Pitch Spacing',
          standardCode: 'OSHA 1910.23(b)(2) / EN ISO 14122-4',
          status: pitchStatus,
          measuredValueMm: avgPitch,
          minAllowedMm: 250.0,
          maxAllowedMm: 300.0,
          description:
              'Rung pitch averages ${avgPitch.toStringAsFixed(1)} mm (range: ${minPitch.toInt()}–${maxPitch.toInt()} mm across ${pitches.length} spans).',
          recommendation: pitchStatus == ComplianceStatus.pass
              ? 'Meets uniform 250–300 mm rung spacing requirement.'
              : 'Auto-fix rung spacing to a uniform 280 mm pitch along stiles.',
          fixActionId: 'fix_rung_pitch',
        ),
      );
    }

    // 2. Clear Width between Stiles: W >= 400mm (OSHA 16 in / 406mm, EN ISO 400mm)
    double clearWidthMm = 450.0;
    if (rungs.isNotEmpty) {
      clearWidthMm = rungs.first.length;
    } else {
      final rails = doc.parts.where((p) => p.type == AssemblyPartType.straightRail || p.type == AssemblyPartType.bentRail).toList();
      if (rails.length >= 2) {
        clearWidthMm = (rails[1].position.y - rails[0].position.y).abs();
      }
    }

    ComplianceStatus widthStatus;
    if (clearWidthMm >= 400.0 && clearWidthMm <= 600.0) {
      widthStatus = ComplianceStatus.pass;
    } else if (clearWidthMm >= 350.0 && clearWidthMm < 400.0) {
      widthStatus = ComplianceStatus.warning;
    } else {
      widthStatus = ComplianceStatus.fail;
    }

    items.add(
      ComplianceItemResult(
        id: 'clear_width',
        title: 'Clear Width Between Stiles',
        standardCode: 'OSHA 1910.23(b)(4) / EN ISO 14122-4',
        status: widthStatus,
        measuredValueMm: clearWidthMm,
        minAllowedMm: 400.0,
        maxAllowedMm: 600.0,
        description: 'Internal clear width is ${clearWidthMm.toStringAsFixed(1)} mm between side rails.',
        recommendation: widthStatus == ComplianceStatus.pass ? 'Exceeds minimum clear width requirement (>= 400 mm).' : 'Widen stiles to 450 mm clear width.',
        fixActionId: 'fix_clear_width',
      ),
    );

    // 3. Wall Standoff Clearance: >= 175mm from back of rungs to wall
    final brackets = doc.parts
        .where((p) => p.type == AssemblyPartType.standoffBracket || p.name.toLowerCase().contains('standoff') || p.name.toLowerCase().contains('bracket'))
        .toList();

    if (brackets.isEmpty) {
      items.add(
        const ComplianceItemResult(
          id: 'wall_clearance',
          title: 'Wall Standoff Clearance',
          standardCode: 'OSHA 1910.23(d)(2) / EN ISO 14122-4',
          status: ComplianceStatus.warning,
          measuredValueMm: null,
          minAllowedMm: 175.0,
          maxAllowedMm: 350.0,
          description: 'No wall standoff brackets detected in current assembly.',
          recommendation: 'Add wall standoff brackets with minimum 175 mm (7 in) clearance.',
          fixActionId: 'fix_wall_clearance',
        ),
      );
    } else {
      final double bracketLength = brackets.first.length;
      final ComplianceStatus standoffStatus = bracketLength >= 175.0 ? ComplianceStatus.pass : ComplianceStatus.fail;
      items.add(
        ComplianceItemResult(
          id: 'wall_clearance',
          title: 'Wall Standoff Clearance',
          standardCode: 'OSHA 1910.23(d)(2) / EN ISO 14122-4',
          status: standoffStatus,
          measuredValueMm: bracketLength,
          minAllowedMm: 175.0,
          maxAllowedMm: 350.0,
          description: 'Wall standoff bracket provides ${bracketLength.toStringAsFixed(1)} mm rear clearance.',
          recommendation: standoffStatus == ComplianceStatus.pass
              ? 'Complies with >= 175 mm toe clearance standard.'
              : 'Extend bracket depth to at least 175–200 mm.',
          fixActionId: 'fix_wall_clearance',
        ),
      );
    }

    // 4. Safety Cage Start Height: Required when H >= 6.0m (starts 2200–2500mm above ground)
    final cageHoops = doc.parts.where((p) => p.type == AssemblyPartType.safetyCageHoop || p.type == AssemblyPartType.safetyCageBellHoop).toList();

    if (cageHoops.isNotEmpty) {
      final double entryElevation = cageHoops.map((h) => math.max(h.position.x, h.position.z)).reduce(math.min);
      final ComplianceStatus cageStatus = (entryElevation >= 2100.0 && entryElevation <= 2550.0) ? ComplianceStatus.pass : ComplianceStatus.warning;

      items.add(
        ComplianceItemResult(
          id: 'cage_height',
          title: 'Safety Cage Entry Height',
          standardCode: 'OSHA 1910.28(b)(9) / EN ISO 14122-4',
          status: cageStatus,
          measuredValueMm: entryElevation,
          minAllowedMm: 2200.0,
          maxAllowedMm: 2500.0,
          description: 'Bottom entry hoop begins at ${entryElevation.toStringAsFixed(0)} mm above floor.',
          recommendation: cageStatus == ComplianceStatus.pass
              ? 'Meets entry height window (2.2 m to 2.5 m above ground).'
              : 'Adjust cage entry hoop to 2200 mm above base.',
          fixActionId: 'fix_cage_height',
        ),
      );
    } else {
      final bool requiresCage = ladderHeightMm >= 6000.0;
      items.add(
        ComplianceItemResult(
          id: 'cage_height',
          title: 'Safety Cage Requirement',
          standardCode: 'OSHA 1910.28(b)(9) / EN ISO 14122-4',
          status: requiresCage ? ComplianceStatus.warning : ComplianceStatus.pass,
          measuredValueMm: ladderHeightMm,
          minAllowedMm: 2200.0,
          maxAllowedMm: 2500.0,
          description: requiresCage
              ? 'Ladder height (${(ladderHeightMm / 1000.0).toStringAsFixed(1)} m) exceeds 6.0 m; cage or fall arrest required.'
              : 'Ladder height (${(ladderHeightMm / 1000.0).toStringAsFixed(1)} m) is below 6.0 m; cage is optional.',
          recommendation: requiresCage ? 'Attach safety cage assembly starting at 2200 mm.' : 'No cage required for short access ladders.',
          fixActionId: requiresCage ? 'fix_cage_height' : '',
        ),
      );
    }

    // 5. Parapet Walk-Through Extension: Extension >= 1060mm (42 in) above landing
    final parapets = doc.parts.where((p) => p.type == AssemblyPartType.walkThroughStile || p.name.toLowerCase().contains('parapet')).toList();

    if (parapets.isNotEmpty) {
      final double extHeight = math.max(parapets.first.height, parapets.first.length);
      final ComplianceStatus parapetStatus = extHeight >= 1060.0 ? ComplianceStatus.pass : ComplianceStatus.warning;
      items.add(
        ComplianceItemResult(
          id: 'parapet_extension',
          title: 'Walk-Through Parapet Extension',
          standardCode: 'OSHA 1910.23(d)(4) / EN ISO 14122-4',
          status: parapetStatus,
          measuredValueMm: extHeight,
          minAllowedMm: 1060.0,
          maxAllowedMm: 1400.0,
          description: 'Side rail handgrip extension is ${extHeight.toStringAsFixed(0)} mm above roof landing.',
          recommendation: parapetStatus == ComplianceStatus.pass
              ? 'Meets standard >= 1060 mm (42 in) landing handrail extension.'
              : 'Extend parapet stiles to at least 1060–1100 mm.',
          fixActionId: 'fix_parapet_extension',
        ),
      );
    } else {
      final bool needsParapet = rungs.length >= 6 || ladderHeightMm >= 2000.0;
      items.add(
        ComplianceItemResult(
          id: 'parapet_extension',
          title: 'Walk-Through Parapet Extension',
          standardCode: 'OSHA 1910.23(d)(4) / EN ISO 14122-4',
          status: needsParapet ? ComplianceStatus.warning : ComplianceStatus.pass,
          measuredValueMm: null,
          minAllowedMm: 1060.0,
          maxAllowedMm: 1400.0,
          description: needsParapet
              ? 'Elevated ladder has no flared walk-through parapet extension for roof access.'
              : 'Single-stage ladder without elevated landing.',
          recommendation: needsParapet ? 'Add 1100 mm walk-through parapet top stiles.' : 'Parapet not required.',
          fixActionId: needsParapet ? 'fix_parapet_extension' : '',
        ),
      );
    }

    return AssemblyComplianceReport(items: items, ladderTotalHeightMm: ladderHeightMm, totalRungCount: rungs.length);
  }

  /// 1-Click Auto-Fix for Rung Pitch (uniform spacing to targetPitch, default 280 mm).
  void autoFixRungSpacing({double targetPitch = 280.0}) {
    final rungs = doc.parts
        .where(
          (p) =>
              p.type == AssemblyPartType.rung ||
              p.type == AssemblyPartType.diamondGripRung ||
              p.type == AssemblyPartType.wideStepTread ||
              p.name.toLowerCase().contains('rung') ||
              p.name.toLowerCase().contains('tread'),
        )
        .toList();
    if (rungs.length < 2) return;
    _recordUndo();

    final double spanX = rungs.map((r) => r.position.x).reduce(math.max) - rungs.map((r) => r.position.x).reduce(math.min);
    final double spanZ = rungs.map((r) => r.position.z).reduce(math.max) - rungs.map((r) => r.position.z).reduce(math.min);
    final bool rungsAlongX = spanX >= spanZ;

    if (rungsAlongX) {
      rungs.sort((a, b) => a.position.x.compareTo(b.position.x));
      final double startX = rungs.first.position.x;
      for (int i = 0; i < rungs.length; i++) {
        final rung = rungs[i];
        final newX = startX + i * targetPitch;
        final dx = newX - rung.position.x;
        rung.position = CadPoint3D(newX, rung.position.y, rung.position.z);

        // Update associated weld points
        for (int w = 0; w < doc.welds.length; w++) {
          final j = doc.welds[w];
          if (j.partAId == rung.id || j.partBId == rung.id) {
            doc.welds[w] = j.copyWith(weldPoint: CadPoint3D(j.weldPoint.x + dx, j.weldPoint.y, j.weldPoint.z));
          }
        }
      }
    } else {
      rungs.sort((a, b) => a.position.z.compareTo(b.position.z));
      final double startZ = rungs.first.position.z;
      for (int i = 0; i < rungs.length; i++) {
        final rung = rungs[i];
        final newZ = startZ + i * targetPitch;
        final dz = newZ - rung.position.z;
        rung.position = CadPoint3D(rung.position.x, rung.position.y, newZ);

        // Update associated weld points
        for (int w = 0; w < doc.welds.length; w++) {
          final j = doc.welds[w];
          if (j.partAId == rung.id || j.partBId == rung.id) {
            doc.welds[w] = j.copyWith(weldPoint: CadPoint3D(j.weldPoint.x, j.weldPoint.y, j.weldPoint.z + dz));
          }
        }
      }
    }
    notifyListeners();
  }

  /// 1-Click Auto-Fix for Clear Width (widens rungs and repositions right rail to targetWidth, default 450 mm).
  void autoFixClearWidth({double targetWidth = 450.0}) {
    _recordUndo();
    final rungs = doc.parts
        .where(
          (p) =>
              p.type == AssemblyPartType.rung ||
              p.type == AssemblyPartType.diamondGripRung ||
              p.type == AssemblyPartType.wideStepTread ||
              p.name.toLowerCase().contains('rung') ||
              p.name.toLowerCase().contains('tread'),
        )
        .toList();
    for (final rung in rungs) {
      rung.length = targetWidth;
    }

    final rightRails = doc.parts.where((p) => p.id == 'rail_right' || p.name.toLowerCase().contains('right')).toList();
    for (final rail in rightRails) {
      rail.position = CadPoint3D(rail.position.x, targetWidth, rail.position.z);
    }
    notifyListeners();
  }

  /// 1-Click Auto-Fix for Wall Clearance (sets brackets to targetClearance, default 200 mm).
  void autoFixWallClearance({double targetClearance = 200.0}) {
    _recordUndo();
    final brackets = doc.parts
        .where((p) => p.type == AssemblyPartType.standoffBracket || p.name.toLowerCase().contains('standoff') || p.name.toLowerCase().contains('bracket'))
        .toList();
    if (brackets.isEmpty) {
      addWallStandoffBrackets(standoffDepth: targetClearance);
    } else {
      for (final b in brackets) {
        b.length = targetClearance;
      }
    }
    notifyListeners();
  }

  /// 1-Click Auto-Fix for Safety Cage (starts cage at targetHeight, default 2200 mm).
  void autoFixCageHeight({double targetHeight = 2200.0}) {
    _recordUndo();
    final cageParts = doc.parts
        .where((p) => p.type == AssemblyPartType.safetyCageHoop || p.type == AssemblyPartType.safetyCageBellHoop || p.type == AssemblyPartType.cageStrap)
        .toList();
    if (cageParts.isEmpty) {
      generateSafetyCageAssembly(startHeight: targetHeight);
    } else {
      final hoops = cageParts.where((p) => p.type == AssemblyPartType.safetyCageHoop || p.type == AssemblyPartType.safetyCageBellHoop).toList();
      if (hoops.isNotEmpty) {
        final double minX = hoops.map((h) => h.position.x).reduce(math.min);
        final double minZ = hoops.map((h) => h.position.z).reduce(math.min);
        if (minX >= 200.0 || minX > minZ) {
          final dx = targetHeight - minX;
          for (final p in cageParts) {
            p.position = CadPoint3D(p.position.x + dx, p.position.y, p.position.z);
          }
        } else {
          final dz = targetHeight - minZ;
          for (final p in cageParts) {
            p.position = CadPoint3D(p.position.x, p.position.y, p.position.z + dz);
          }
        }
      }
    }
    notifyListeners();
  }

  /// 1-Click Auto-Fix for Parapet Extension (attaches or updates parapet to targetExtension, default 1100 mm).
  void autoFixParapetExtension({double targetExtension = 1100.0}) {
    _recordUndo();
    final parapets = doc.parts.where((p) => p.type == AssemblyPartType.walkThroughStile || p.name.toLowerCase().contains('parapet')).toList();
    if (parapets.isEmpty) {
      addWalkThroughParapetStiles(extensionHeight: targetExtension);
    } else {
      for (final p in parapets) {
        p.height = math.max(p.height, targetExtension);
        p.length = math.max(p.length, targetExtension);
      }
    }
    notifyListeners();
  }

  /// 1-Click Auto-Fix for ALL compliance issues across the assembly.
  void autoFixAllComplianceIssues() {
    autoFixRungSpacing();
    autoFixClearWidth();
    autoFixWallClearance();
    autoFixCageHeight();
    autoFixParapetExtension();
  }

  // -------------------------------------------------------------
  // Phase 4: Bill of Materials (BOM) & Fabrication Cut List
  // -------------------------------------------------------------

  /// Calculates the complete Bill of Materials, profile cut lengths, and material weights.
  AssemblyBomReport generateBillOfMaterials({String materialGrade = 'Stainless Steel 304'}) {
    final Map<String, List<AssemblyPart>> groups = {};
    for (final p in doc.parts) {
      final key = '${p.type.name}_${p.length.round()}_${p.height.round()}_${p.flangeWidth.round()}_${p.thickness.toStringAsFixed(1)}';
      groups.putIfAbsent(key, () => []).add(p);
    }

    final bomItems = <AssemblyBomItem>[];
    int itemIdx = 1;
    double totalAssemblyWeight = 0.0;
    const double steelDensity = 7.93e-6; // kg / mm^3

    for (final entry in groups.entries) {
      final sample = entry.value.first;
      final count = entry.value.length;

      String mark = 'P-${itemIdx.toString().padLeft(2, '0')}';
      String desc = sample.name;
      String prof = '${sample.height.toInt()}×${sample.flangeWidth.toInt()}×${sample.thickness}mm';
      double developedWidth = sample.height + 2 * sample.flangeWidth;

      switch (sample.type) {
        case AssemblyPartType.straightRail:
        case AssemblyPartType.bentRail:
          mark = 'SR-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'C-Channel Stile Side Rail';
          prof = '${sample.height.toInt()}×${sample.flangeWidth.toInt()}×${sample.thickness}mm C-Channel';
          developedWidth = sample.height + 2 * sample.flangeWidth;
          break;
        case AssemblyPartType.rung:
          mark = 'CR-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Slotted C-Channel Ladder Rung';
          prof = '${sample.height.toInt()}×${sample.flangeWidth.toInt()}×${sample.thickness}mm C-Channel';
          developedWidth = sample.height + 2 * sample.flangeWidth;
          break;
        case AssemblyPartType.diamondGripRung:
          mark = 'DR-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Anti-Slip Diamond Grip Rung';
          prof = '40×30×${sample.thickness}mm Diamond Profile';
          developedWidth = 100.0;
          break;
        case AssemblyPartType.wideStepTread:
          mark = 'TR-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Perforated Wide Step Tread';
          prof = '150×${sample.thickness}mm Formed Tread';
          developedWidth = 180.0;
          break;
        case AssemblyPartType.walkThroughStile:
          mark = 'WT-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Flared Walk-Through Parapet Handrail';
          prof = '${sample.height.toInt()}×${sample.flangeWidth.toInt()}×${sample.thickness}mm Arc Stile';
          developedWidth = sample.height + 2 * sample.flangeWidth;
          break;
        case AssemblyPartType.boxTubeStile:
          mark = 'BT-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Heavy-Duty RHS Box Tube Stile';
          prof = '${sample.height.toInt()}×${sample.flangeWidth.toInt()}×${sample.thickness}mm RHS';
          developedWidth = (sample.height + sample.flangeWidth) * 2;
          break;
        case AssemblyPartType.safetyCageHoop:
        case AssemblyPartType.safetyCageBellHoop:
          mark = 'CH-${itemIdx.toString().padLeft(2, '0')}';
          desc = sample.type == AssemblyPartType.safetyCageBellHoop ? 'Flared Entry Bell Hoop' : 'Circular Safety Cage Hoop';
          prof = '50×4.0mm Roll-Formed Flat Bar';
          developedWidth = 50.0;
          break;
        case AssemblyPartType.cageStrap:
          mark = 'CS-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Safety Cage Vertical Strap';
          prof = '30×3.0mm Flat Bar';
          developedWidth = 30.0;
          break;
        case AssemblyPartType.standoffBracket:
          mark = 'WB-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Heavy-Duty Wall Standoff Bracket';
          prof = '50×50×5.0mm Formed Angle Bracket';
          developedWidth = 120.0;
          break;
        case AssemblyPartType.baseFootPlate:
          mark = 'FP-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Chemical Anchor Base Foot Shoe';
          prof = '150×80×8.0mm Heavy Foot Plate';
          developedWidth = 80.0;
          break;
        case AssemblyPartType.splicePlate:
          mark = 'SP-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Internal Stile Splice Joint Fishplate';
          prof = '250×70×4.0mm Flat Splice Plate';
          developedWidth = 70.0;
          break;
        case AssemblyPartType.swingGate:
          mark = 'SG-${itemIdx.toString().padLeft(2, '0')}';
          desc = 'Self-Closing Safety Swing Gate';
          prof = 'Tubular Frame with Kickplate';
          developedWidth = 100.0;
          break;
        default:
          break;
      }

      final double volumeMm3 = developedWidth * sample.length * sample.thickness;
      final double unitWeight = volumeMm3 * steelDensity;
      final double totalWeight = unitWeight * count;
      totalAssemblyWeight += totalWeight;

      final int holes = sample.sketches.where((s) => s.featureType != 'bend_line').length;
      final int bends = sample.sketches.where((s) => s.featureType == 'bend_line').length + 2;

      bomItems.add(
        AssemblyBomItem(
          itemNumber: itemIdx.toString().padLeft(2, '0'),
          partMark: mark,
          description: desc,
          materialGrade: materialGrade,
          profile: prof,
          lengthMm: sample.length,
          widthMm: sample.height,
          thicknessMm: sample.thickness,
          quantity: count,
          unitWeightKg: unitWeight,
          totalWeightKg: totalWeight,
          cutLengthMm: sample.length,
          holeCount: holes,
          bendCount: bends,
        ),
      );
      itemIdx++;
    }

    double totalWeldLen = 0.0;
    for (final w in doc.welds) {
      totalWeldLen += w.weldLengthMm;
    }

    return AssemblyBomReport(
      items: bomItems,
      totalWeightKg: totalAssemblyWeight,
      totalPartCount: doc.parts.length,
      totalWeldLengthMm: totalWeldLen,
      totalWeldCount: doc.welds.length,
      assemblyTitle: doc.title,
    );
  }

  /// Exports the BOM in CSV format.
  String exportBOMAsCsv() => generateBillOfMaterials().toCsv();

  /// Exports the BOM in formatted Markdown table.
  String exportBOMAsMarkdown() => generateBillOfMaterials().toMarkdown();

  // -------------------------------------------------------------
  // Mesh computation with high-performance caching (0ms during orbit/pan)
  // -------------------------------------------------------------
  FoldedMeshResult? _cachedAssemblyMesh;

  FoldedMeshResult get assemblyMesh {
    _cachedAssemblyMesh ??= doc.buildAssemblyMesh(showWeldOverlay: showWeldOverlay);
    return _cachedAssemblyMesh!;
  }

  void invalidateMeshCache() {
    _cachedAssemblyMesh = null;
    documentVersion++;
  }

  @override
  void notifyListeners() {
    _cachedAssemblyMesh = null;
    super.notifyListeners();
  }
}

/// Represents a grouped tree node in the 3D Scene / Assembly Hierarchy.
/// Connected or welded parts appear together under one unified parent assembly set.
class AssemblyGroupNode {
  final String id;
  final String name;
  final bool isConnectedAssembly;
  final List<AssemblyPart> parts;
  final List<AssemblyWeldJoint> welds;

  const AssemblyGroupNode({required this.id, required this.name, required this.isConnectedAssembly, required this.parts, this.welds = const []});
}
