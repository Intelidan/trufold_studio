import '../engine/constraints/dependency_graph_engine.dart';

// =============================================================================

// sheet_metal_studio_viewmodel.dart

//

// Core MVVM ViewModel for truFold Studio by Danish.

// Orchestrates:

// - Document state & 50-step Undo/Redo history

// - Kinematic 3D folding mesh generation

// - Turret punches, press-brake bends, laser cut lines / slits

// - Mouse wheel zooming, 2D/3D panning (middle-click & shift-drag)

// - Interactive rubber-band drawing (0Â°, 45Â°, 90Â° snapping with Alt-override)

// - Incomplete/open bend line detection and endpoint dragging

// - Interactive CAD bend line dragging and edge constraints

// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:flutter/scheduler.dart';

import '../models/cad_primitives.dart';

import '../models/fold_bend_line.dart';

import '../models/dsf_document.dart';

import '../models/cnc_punch_primitive.dart';

import '../models/planar_sheet_face.dart';

import '../models/perforation_pattern.dart';

import '../models/press_brake_machine.dart';

import '../models/sheet_metal_material.dart';

import '../engine/kinematic_fold_engine.dart';
import '../engine/structural_topology_analyzer.dart';
import '../engine/cms/cms_guided_ux_controller.dart';
import '../models/cms/cms_product_contract.dart';
import '../models/cms/cms_physical_port.dart';
import '../engine/cms/cms_scaling_controller.dart';
import '../models/cms/cms_ux_state.dart';
import '../engine/cms/cms_3d_opening_detector.dart';
import '../engine/cms/cms_opening_plane_analyzer.dart';
import '../engine/cms/cms_port_matcher.dart';
import '../engine/cms/cms_coupler_classifier.dart';

import '../engine/planar_face_decomposer.dart';

import '../engine/dxf_dsf_importer.dart';

import '../engine/magnetic_snap_engine.dart';

import '../engine/cnc_turret_engine.dart';

import '../engine/press_brake_cam_engine.dart';

import '../engine/bend_sequence_engine.dart';

import '../engine/geometry_modify_engine.dart';

import '../models/cad_geometry.dart';

import '../models/cad_dimension.dart';

import '../engine/direct_dimension_driver.dart';

import '../models/cad_constraint.dart';

import '../engine/constraint_solver.dart';

import '../engine/dxf_mini_parser.dart';

import '../engine/dxf_import_diagnostics_engine.dart';

import '../engine/dxf_geometry_recognition_engine.dart';

import '../models/cad_feature.dart';

import '../engine/flat_pattern_engine.dart';

import '../models/studio_command_delta.dart';

import '../models/template_parameter_definition.dart';

import '../engine/topological_zone_morpher.dart';

import '../engine/dxf_auto_fold_engine.dart';

import '../models/dxf_fitting_metadata.dart';

import '../models/constraints/stable_geometry_reference.dart';

import '../models/constraints/reference_geometry.dart';

import '../models/constraints/constraint_definition.dart';

import 'mixins/reference_geometry_mixin.dart';

import 'mixins/parameter_viewmodel_mixin.dart';

import 'mixins/constraint_viewmodel_mixin.dart';

import '../engine/constraints/geometric_constraint_solver.dart';
import '../engine/port_inference_engine.dart';
import '../engine/constraints/expression_parser_engine.dart';
import '../models/constraints/entity_constraint_state.dart';

enum StudioToolMode {
  select, // Click on bend line, face, cut, or punch to inspect/drag

  pan, // Dedicated 2D flat canvas pan / hand tool

  addBend, // 2-click interactive bend line tool with 45° and magnetic snap

  addFlange, // 2-click interactive return flange tool with edge snap and guidance

  addCut, // 2-click laser cut line / slit tool with 45° and magnetic snap

  setBaseAnchor, // Click on a face to make it the stationary base floor anchor

  addPunchRound, // Click to stamp a round bolt clearance hole

  addPunchObround, // Click to stamp an obround slot

  addPunchSquare, // Click to stamp a rectangular/square punch

  perforationPattern, // Specialized cable tray perforation repeat pattern

  cornerFillet, // Click on corner vertex to apply rounded fillet

  cornerChamfer, // Click on corner vertex to apply 45° chamfer

  drawRectangle, // 2-click interactive corner-to-corner rectangle

  drawCircle, // Center + radius interactive circle

  drawArc, // 3-point interactive arc

  drawPolyline, // Continuous multi-point polyline

  modifyMove, // Interactive base point to destination move

  modifyRotate, // Interactive center to angle rotation

  modifyMirror, // Interactive mirror axis line

  modifyOffset, // Interactive offset tool

  addDimension, // Dimensional Constraints parametric tool

  dragDimension, // Click-and-drag interactive dimension measurement tool

  pickPortEdge, // Interactive pick of opening Width or Height edge from drawing

  assignPortSemantic, // 1-Click Semantic Port Assignment from opening edge (W + H-A + H-B + normal)
}

enum PortEdgePickTarget { port1Width, port1Height, port2Width, port2Height, port3Width, port3Height, port4Width, port4Height }

extension PortEdgePickTargetExtension on PortEdgePickTarget {
  String get displayName {
    switch (this) {
      case PortEdgePickTarget.port1Width:
        return 'Port 1 Width (W)';

      case PortEdgePickTarget.port1Height:
        return 'Port 1 Height (H)';

      case PortEdgePickTarget.port2Width:
        return 'Port 2 Width (W)';

      case PortEdgePickTarget.port2Height:
        return 'Port 2 Height (H)';

      case PortEdgePickTarget.port3Width:
        return 'Port 3 Width (W)';

      case PortEdgePickTarget.port3Height:
        return 'Port 3 Height (H)';

      case PortEdgePickTarget.port4Width:
        return 'Port 4 Width (W)';

      case PortEdgePickTarget.port4Height:
        return 'Port 4 Height (H)';
    }
  }
}

/// Dynamic Configuration for Active Creation Tools

class ActiveToolConfig {
  double roundHoleDiameter = 8.0;

  double obroundWidth = 30.0;

  double obroundLength = 7.0;

  double squareSize = 15.0;

  double rectWidth = 20.0;

  double rectHeight = 15.0;

  bool squareAspectLocked = true;

  String selectedPunchPreset = 'M8';

  double chamferDist = 10.0;

  // Bend & Flange tool guidance configuration

  double bendOffsetMm = 50.0;

  double flangeOffsetMm = 13.0;

  // Dimension tool configuration

  CadDimensionType activeDimensionType = CadDimensionType.aligned;

  double dimensionOffsetMm = 25.0;

  // Cable tray perforation pattern repeat & hole selection

  PunchType patternHoleType = PunchType.obroundSlot;

  double patternRotationDeg = 0.0;

  int patternColsX = 3;

  int patternRowsY = 8;

  double patternPitchX = 35.0;

  double patternPitchY = 50.0;

  bool patternStaggered = true;

  double patternSlotWidth = 30.0;

  double patternSlotHeight = 7.0;

  double patternDiameter = 8.0;

  double patternSquareSize = 12.0;

  double patternRectWidth = 30.0;

  double patternRectHeight = 10.0;

  double get roundHoleDiameterMm => roundHoleDiameter;

  set roundHoleDiameterMm(double v) => roundHoleDiameter = v;

  double get obroundWidthMm => obroundWidth;

  set obroundWidthMm(double v) => obroundWidth = v;

  double get obroundLengthMm => obroundLength;

  set obroundLengthMm(double v) => obroundLength = v;

  double get squareSizeMm => squareSize;

  set squareSizeMm(double v) => squareSize = v;

  double get rectWidthMm => rectWidth;

  set rectWidthMm(double v) => rectWidth = v;

  double get rectHeightMm => rectHeight;

  set rectHeightMm(double v) => rectHeight = v;

  double get chamferDistanceMm => chamferDist;

  set chamferDistanceMm(double v) => chamferDist = v;

  int get patternCountX => patternColsX;

  set patternCountX(int v) => patternColsX = v;

  int get patternCountY => patternRowsY;

  set patternCountY(int v) => patternRowsY = v;

  double get patternPitchXMm => patternPitchX;

  set patternPitchXMm(double v) => patternPitchX = v;

  double get patternPitchYMm => patternPitchY;

  set patternPitchYMm(double v) => patternPitchY = v;

  // Modify & Draw Tools Configuration

  double offsetDistance = 10.0;

  double filletRadius = 5.0;

  double rotateAngleDeg = 45.0;

  int linearPatternCols = 3;

  int linearPatternRows = 3;

  double linearPitchX = 25.0;

  double linearPitchY = 25.0;

  int circularPatternCount = 6;

  double circularTotalAngleDeg = 360.0;

  bool isConstructionDraw = false;
}

class SheetMetalStudioViewModel extends ChangeNotifier with ReferenceGeometryMixin, ParameterViewModelMixin, ConstraintViewModelMixin {
  DsfDocument _document;

  double _foldProgress = 1.0; // 0.0 (Flat) to 1.0 (Folded)

  double _splitRatio = 0.50; // 50% 2D canvas, 50% 3D viewport

  StudioToolMode _toolMode = StudioToolMode.select;

  @override
  void recordHistory() => _recordHistory();

  @override
  void onGeometryRecalculated() {
    if (_document.constraints.isNotEmpty) {
      final res = GeometricConstraintSolver.solve(document: _document, customReferences: allReferenceGeometries);

      _document = res.updatedDocument;
    }

    _recomputeMesh();
  }

  @override
  void setDocumentParameters(Map<String, double> newParams) {
    _document = _document.copyWith(parameters: newParams);
  }

  @override
  void setDocumentFromSolver(DsfDocument newDoc) {
    _document = newDoc;

    _recomputeMesh();
  }

  // Undo / Redo Command History Stack

  final List<StudioCommandDelta> _undoStack = [];

  final List<StudioCommandDelta> _redoStack = [];

  static const int _maxUndoSteps = 250; // Generous 200â€“300 steps for in-memory session undo

  DsfDocument? _historyCheckpointDoc;

  String? _pendingHistoryDescription;

  bool _isApplyingUndoRedo = false;

  // Single-Step Drag Session Flag

  bool _isDraggingObject = false;

  // 2D Canvas Viewport State

  Offset _pan2D = Offset.zero;

  double _zoom2D = 1.0;

  SnapTarget? _activeSnap;

  CadPoint2D? _pendingBendStart;

  CadPoint2D? _rubberBandEndpoint;

  String? _pendingDimensionEntityAId;

  CadAnchorType? _pendingDimensionAnchorTypeA;

  String? _pendingInPlaceEditDimId;

  String? get pendingDimensionEntityAId => _pendingDimensionEntityAId;

  CadAnchorType? get pendingDimensionAnchorTypeA => _pendingDimensionAnchorTypeA;

  String? get pendingInPlaceEditDimId => _pendingInPlaceEditDimId;

  void clearPendingInPlaceEdit() {
    _pendingInPlaceEditDimId = null;
  }

  final List<CadPoint2D> _pendingMultiPoints = [];

  List<CadPoint2D> get pendingMultiPoints => List.unmodifiable(_pendingMultiPoints);

  bool _magneticSnapEnabled = true;

  bool _autoBendPlacementEnabled = true;

  bool get autoBendPlacementEnabled => _autoBendPlacementEnabled;

  void toggleAutoBendPlacement({bool? enabled}) {
    _autoBendPlacementEnabled = enabled ?? !_autoBendPlacementEnabled;
    notifyListeners();
  }

  // 3D Viewport State

  double _azimuthDeg = 45.0;

  double _elevationDeg = 30.0;

  double _cameraZoom = 1.0;

  Offset _pan3D = Offset.zero;

  bool _showWireframe = true;

  bool _isGlassMode = false;

  bool _showDimensions = true;

  bool _isPlayingAnimation = false;

  bool _isPropertyInspectorOpen = true;

  bool _isFittingInspectorOpen = false;

  bool _isSketchPaletteOpen = false;

  String? _selectedBendId;

  String? _selectedCutId;

  String? _selectedFaceId;

  String? _selectedPunchId;

  String? _selectedPatternId;

  int? _selectedPatternHoleIndex;

  String? _selectedDimensionId;

  String? _selectedArcId;

  final Set<String> _selectedEntityIds = {};

  CadPoint2D? _currentCursorMm;

  SnapEngineSettings _snapSettings = const SnapEngineSettings();

  // Press Brake Machine & CAM Engine

  PressBrakeMachine _selectedMachine = PressBrakeMachine.standardPresets().first;

  List<String> _bendSequence = [];

  bool _isStepMode = false;

  int _currentBendStep = 1;

  // Cross-Viewport Hover Highlighting (2D <-> 3D)

  String? _hoveredPunchId;

  String? _hoveredBendId;

  String? _hoveredCutId;

  String? _hoveredFaceId;

  String? _hoveredArcId;

  // Movable Dimension Label Offsets (User interactive dragging)

  final Map<String, Offset> _dimensionOffsets = {};

  Map<String, Offset> get dimensionOffsets => Map.unmodifiable(_dimensionOffsets);

  void setDimensionOffset(String dimKey, Offset offset) {
    _dimensionOffsets[dimKey] = offset;

    notifyListeners();
  }

  void resetDimensionOffset(String dimKey) {
    if (_dimensionOffsets.containsKey(dimKey)) {
      _dimensionOffsets.remove(dimKey);

      notifyListeners();
    }
  }

  void clearAllDimensionOffsets() {
    _dimensionOffsets.clear();
    _dimensionLineOffsets.clear();
    notifyListeners();
  }

  // Movable Dimension Line Offsets (Perpendicular dragging for associative & system dimensions)
  final Map<String, double> _dimensionLineOffsets = {};
  Map<String, double> get dimensionLineOffsets => Map.unmodifiable(_dimensionLineOffsets);

  // Tool Configuration Settings

  final ActiveToolConfig toolConfig = ActiveToolConfig();

  ActiveToolConfig get activeToolConfig => toolConfig;

  // In-process Perforation Pattern Preview on Selected Surface

  PerforationPattern? _previewPerforationPattern;

  List<CncPunchPrimitive>? _previewCouplerPunches;

  // Cached 3D Folded Mesh Result

  FoldedMeshResult? _cachedMesh;

  // Cached Manufacturing Flat Pattern Developed Blank

  FlatPatternResult? _cachedFlatPattern;

  // Topological Zone Morphing Template State

  TemplateParameterDefinition? _activeTemplate;

  DsfDocument? _templateBaselineDoc;

  Map<String, double> _currentTemplateParams = {};

  // Detected Fitting Metadata (Cable Tray / Trunking / Accessories)

  DxfFittingMetadata? _detectedFittingMetadata;

  // Interactive Port Edge Picking State (Width & Height)

  PortEdgePickTarget? _activePortPickTarget;

  // 1-Click Semantic Port Assignment State
  PortInferenceResult? _activePortInferenceResult;
  String? _activeSemanticPortId;

  CadPoint2D? _hoveredContourEdgeP1;

  CadPoint2D? _hoveredContourEdgeP2;

  double? _hoveredContourEdgeLengthMm;

  // Movable Port Opening Badge Offsets (User interactive dragging)

  final Map<String, Offset> _portBadgeOffsets = {};

  bool _showPortOpeningBadges = true;

  // Autonomous Observable CMS Guided UX Controller (Clean Architecture)
  final CmsGuidedUxController cmsGuidedController = CmsGuidedUxController();

  /// Runs clean autonomous 3D discovery workflow on the active document
  Future<void> startCleanCmsDiscovery({CmsProductContract? contract}) async {
    final selectedContract = contract ??
        CmsProductContract.lookup(_document.productType, _document.itemName) ??
        CmsProductContract.lookup(null, _document.itemName) ??
        CmsProductContract.lookup(null, _document.productType);
    if (selectedContract == null && !_document.isCmsDrawing) {
      return;
    }
    final activeContract = selectedContract ?? CmsProductContract.bend45;
    cmsGuidedController.startSession(contract: activeContract);
    await cmsGuidedController.runAutomaticDiscovery(document: _document, stepDelay: const Duration(milliseconds: 650));
    notifyListeners();
  }

  /// Applies user-authorized bends to the active document and continues the 3D pipeline.
  Future<void> applyUserBends({List<FoldBendLine>? customBends}) async {
    final bendsToApply =
        customBends ??
        cmsGuidedController.state.suggestedBends.map((s) {
          return FoldBendLine(
            id: s.id,
            p1: s.p1,
            p2: s.p2,
            direction: BendDirection.up,
            targetAngleDeg: s.targetAngleDeg,
            radiusMm: s.radiusMm,
            role: s.isFlange ? BendLineRole.flange : BendLineRole.bend,
            layer: s.isFlange ? 'FLANGE' : 'BEND_UP',
          );
        }).toList();

    final updatedDoc = await cmsGuidedController.applyUserBends(userBends: bendsToApply, document: _document, stepDelay: const Duration(milliseconds: 650));

    _document = updatedDoc;
    _recomputeMesh();
    notifyListeners();
  }

  /// Continues the 3-Stage workflow by auto-mapping ports from existing/user-defined bends.
  Future<void> continueCmsPortMapping() async {
    if (!isCmsDrawing) return;
    if (_document.bends.isNotEmpty && _document.faces.isEmpty) {
      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: _document.outerContour,
        bends: _document.bends,
        cutLines: _document.cutLines,
        preferredBaseFaceId: _document.baseFaceId,
      );
      _document = _document.copyWith(
        bends: decomp.connectedBends,
        faces: decomp.faces,
        baseFaceId: decomp.baseFaceId,
      );
    }

    final contract = cmsGuidedController.state.contract ??
        CmsProductContract.lookup(_document.productType, _document.itemName) ??
        CmsProductContract.lookup(null, _document.itemName) ??
        CmsProductContract.lookup(null, _document.productType) ??
        CmsProductContract.bend45;
    cmsGuidedController.startSession(contract: contract);
    await cmsGuidedController.startStage2PortMapping(document: _document, stepDelay: const Duration(milliseconds: 100));
    if (cmsGuidedController.state.discoveredPorts.isNotEmpty) {
      _persistentCmsPorts = List<CmsPhysicalPort>.from(cmsGuidedController.state.discoveredPorts);
      final meta = Map<String, dynamic>.from(_document.metadata);
      final existingCms = meta['cmsTemplate'] is Map ? Map<String, dynamic>.from(meta['cmsTemplate'] as Map) : <String, dynamic>{};
      existingCms['category'] = (meta['category'] as String?) ?? 'Cable Tray & Trunking';
      existingCms['productType'] = contract.productType;
      existingCms['variation'] = contract.variationName;
      existingCms['templateId'] = '${contract.productType}_${contract.variationName}';
      existingCms['version'] = 1;
      existingCms['ports'] = _persistentCmsPorts.map((p) => p.toJson()).toList();
      existingCms['verifiedBendIds'] = cmsGuidedController.state.verifiedBendIds;
      existingCms['verifiedFlangeIds'] = cmsGuidedController.state.verifiedFlangeIds;
      existingCms['couplerSlotPunchIds'] = cmsGuidedController.state.classifiedCouplerPunchIds;
      existingCms['scalingModel'] = existingCms['scalingModel'] ?? {};
      meta['cmsTemplate'] = existingCms;
      meta['cmsWorkflow'] = {
        'stage': 'ports_mapped',
        'stageIndex': 2,
      };
      _document = _document.copyWith(metadata: meta);
      _recordHistory('✓ Auto-Mapped CMS Ports (${contract.displayName})');
    }
    _recomputeMesh();
    notifyListeners();
  }

  void _initCmsStateFromDocument() {
    // Ensure faces are decomposed if bends exist
    if (_document.bends.isNotEmpty && _document.faces.isEmpty) {
      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: _document.outerContour,
        bends: _document.bends,
        cutLines: _document.cutLines,
        preferredBaseFaceId: _document.baseFaceId,
      );
      _document = _document.copyWith(
        bends: decomp.connectedBends,
        faces: decomp.faces,
        baseFaceId: decomp.baseFaceId,
      );
    }

    _persistentCmsPorts.clear();

    // Guard: Only initialize CMS workflow and port process if this document is a CMS drawing!
    if (!_document.isCmsDrawing) {
      cmsGuidedController.reset();
      return;
    }

    final cmsRaw = _document.metadata['cmsTemplate'];
    if (cmsRaw is Map && cmsRaw['ports'] is List) {
      _persistentCmsPorts = (cmsRaw['ports'] as List)
          .whereType<Map>()
          .map((p) => CmsPhysicalPort.fromJson(Map<String, dynamic>.from(p)))
          .toList();
    }

    // 3-Stage CMS Workflow detection & stage resumption:
    final workflowMeta = _document.metadata['cmsWorkflow'] as Map?;
    final stageIndex = (workflowMeta?['stageIndex'] as num?)?.toInt();
    final contract = CmsProductContract.lookup(
      cmsRaw is Map ? (cmsRaw['productType'] as String?) : _document.productType,
      _document.itemName,
    ) ??
    CmsProductContract.lookup(null, _document.itemName) ??
    CmsProductContract.lookup(null, _document.productType) ??
    CmsProductContract.bend45;

    final hasScalingModel = cmsRaw is Map && cmsRaw['scalingModel'] is Map && (cmsRaw['scalingModel'] as Map).isNotEmpty;

    if (stageIndex == 1 || (_document.bends.isNotEmpty && _persistentCmsPorts.isEmpty)) {
      // Stage 1: Manufacturing defined (bends present, but ports not yet mapped)
      cmsGuidedController.resumeAtStage1(document: _document, contract: contract);
    } else if (stageIndex == 2 || (_persistentCmsPorts.isNotEmpty && !hasScalingModel)) {
      // Stage 2: Ports mapped, but scaling not yet taught
      cmsGuidedController.resumeAtStage2(document: _document, contract: contract, ports: _persistentCmsPorts);
    }
  }

  List<CmsPhysicalPort> _persistentCmsPorts = [];
  bool _showCmsPortHighlights = true;
  bool _isTeachScalingActive = false;
  CmsScalingController? _scalingController;

  /// Whether the current document is a recognized CMS drawing.
  bool get isCmsDrawing => _document.isCmsDrawing;

  List<CmsPhysicalPort> get verifiedCmsPorts {
    if (_isTeachScalingActive && _scalingController?.currentPreview != null) {
      return _scalingController!.currentPreview!.derivedPorts;
    }
    if (cmsGuidedController.state.discoveredPorts.isNotEmpty) {
      return cmsGuidedController.state.discoveredPorts;
    }
    if (_persistentCmsPorts.isNotEmpty) {
      return _persistentCmsPorts;
    }
    final cmsRaw = _document.metadata['cmsTemplate'];
    if (cmsRaw is Map && cmsRaw['ports'] is List) {
      _persistentCmsPorts = (cmsRaw['ports'] as List)
          .whereType<Map>()
          .map((p) => CmsPhysicalPort.fromJson(Map<String, dynamic>.from(p)))
          .toList();
      return _persistentCmsPorts;
    }
    return const [];
  }

  bool get hasVerifiedCmsTemplate => verifiedCmsPorts.isNotEmpty;

  List<CmsPhysicalPort> get activeCmsPorts {
    if (!_showCmsPortHighlights) return const [];
    return verifiedCmsPorts;
  }

  List<CmsPhysicalPort> get persistentCmsPorts => _persistentCmsPorts;

  bool get showCmsPortHighlights => _showCmsPortHighlights;
  bool get isTeachScalingActive => _isTeachScalingActive;
  CmsScalingController? get scalingController => _scalingController;

  void toggleCmsPortHighlights() {
    _showCmsPortHighlights = !_showCmsPortHighlights;
    notifyListeners();
  }

  /// Finalizes and persists the baseline CMS template into the DSF document metadata.
  void finalizeCmsTemplate({bool openInspector = true}) {
    final state = cmsGuidedController.state;
    final contract = state.contract ?? CmsProductContract.bend45;
    final ports = state.discoveredPorts.isNotEmpty ? state.discoveredPorts : _persistentCmsPorts;
    _persistentCmsPorts = List<CmsPhysicalPort>.from(ports);

    final cmsTemplateData = <String, dynamic>{
      'category': (_document.metadata['category'] as String?) ?? 'Cable Tray & Trunking',
      'productType': contract.productType,
      'variation': contract.variationName,
      'templateId': '${contract.productType}_${contract.variationName}',
      'version': 1,
      'ports': _persistentCmsPorts.map((p) => p.toJson()).toList(),
      'verifiedBendIds': state.verifiedBendIds,
      'verifiedFlangeIds': state.verifiedFlangeIds,
      'couplerSlotPunchIds': state.classifiedCouplerPunchIds,
      'scalingModel': {}, // Empty at baseline; populated as user teaches scaling in Phase 2
    };

    final newMetadata = Map<String, dynamic>.from(_document.metadata);
    newMetadata['cmsTemplate'] = cmsTemplateData;
    _document = _document.copyWith(metadata: newMetadata);
    _recordHistory('✓ Finalized CMS Baseline Template (${contract.displayName})');
    cmsGuidedController.completeSession();
    if (openInspector) {
      setFittingInspectorOpen(true);
    }
    notifyListeners();
  }

  /// Launches Phase 2: Teach Scaling. Automatically finalizes Phase 1 baseline if needed.
  void startTeachScaling() {
    final contract = cmsGuidedController.state.contract ??
        CmsProductContract.lookup(_document.productType, _document.itemName) ??
        CmsProductContract.lookup(_detectedFittingMetadata?.product, _detectedFittingMetadata?.variantName) ??
        CmsProductContract.lookup(_document.metadata['fittingProduct'] as String?, _document.metadata['fittingVariant'] as String?) ??
        CmsProductContract.lookup(null, _document.itemName) ??
        CmsProductContract.lookup(null, _document.productType) ??
        (CmsScalingController.isInsideRiserGeometry(_document)
            ? CmsProductContract.insideRiser45
            : CmsProductContract.bend45);

    if (cmsGuidedController.state.phase == CmsUxPhase.complete || cmsGuidedController.state.discoveredPorts.isNotEmpty) {
      finalizeCmsTemplate(openInspector: false);
    }
    setFittingInspectorOpen(false);

    _scalingController?.removeListener(_onScalingControllerChanged);
    _scalingController = CmsScalingController(
      baselineDocument: _document,
      contract: contract,
      baselinePorts: _persistentCmsPorts.isNotEmpty ? _persistentCmsPorts : cmsGuidedController.state.discoveredPorts,
    );
    _scalingController!.addListener(_onScalingControllerChanged);
    _isTeachScalingActive = true;
    _scalingController!.evaluateMorph(_scalingController!.previewMorphValue);
    notifyListeners();
  }

  void _onScalingControllerChanged() {
    notifyListeners();
  }

  /// Commits learned scaling model from Phase 2 into the canonical DSF document.
  void acceptTeachScaling() {
    if (_scalingController == null) return;
    _scalingController!.removeListener(_onScalingControllerChanged);
    final updatedDoc = _scalingController!.acceptScalingModel();
    _document = updatedDoc;
    _persistentCmsPorts = _scalingController!.currentPreview?.derivedPorts ?? _persistentCmsPorts;
    _isTeachScalingActive = false;
    _scalingController = null;
    _detectedFittingMetadata = DxfFittingMetadata.fromDocument(_document);
    _recomputeMesh();
    _recordHistory('✓ Learned and Accepted CMS Scaling Model');
    notifyListeners();
  }

  /// Cancels Phase 2 Teach Scaling mode and reverts to baseline model.
  void exitTeachScaling() {
    _scalingController?.removeListener(_onScalingControllerChanged);
    _scalingController?.cancelPreview();
    _isTeachScalingActive = false;
    _scalingController = null;
    _recomputeMesh();
    notifyListeners();
  }

  SheetMetalStudioViewModel({DsfDocument? initialDocument}) : _document = initialDocument ?? DsfDocument.sampleCableTray() {
    _detectedFittingMetadata = DxfFittingMetadata.fromDocument(_document);

    if (_detectedFittingMetadata?.portBadgeOffsets != null) {
      _detectedFittingMetadata!.portBadgeOffsets!.forEach((k, v) {
        if (v.length >= 2) _portBadgeOffsets[k] = Offset(v[0], v[1]);
      });
    }

    _initCmsStateFromDocument();

    _hydrateUndoStackFromDocument();

    _recomputeMesh();
  }

  // Getters

  @override
  DsfDocument get document =>
      (_isTeachScalingActive && _scalingController?.currentPreview != null) ? _scalingController!.currentPreview!.scaledDocument : _document;

  DxfFittingMetadata? get detectedFittingMetadata => _detectedFittingMetadata;

  PortEdgePickTarget? get activePortPickTarget => _activePortPickTarget;

  PortInferenceResult? get activePortInferenceResult => _activePortInferenceResult;

  String? get activeSemanticPortId => _activeSemanticPortId;

  CadPoint2D? get hoveredContourEdgeP1 => _hoveredContourEdgeP1;

  CadPoint2D? get hoveredContourEdgeP2 => _hoveredContourEdgeP2;

  double? get hoveredContourEdgeLengthMm => _hoveredContourEdgeLengthMm;

  Map<String, Offset> get portBadgeOffsets => Map.unmodifiable(_portBadgeOffsets);

  bool get showPortOpeningBadges => _showPortOpeningBadges;

  FoldedMeshResult? get cachedMesh =>
      (_isTeachScalingActive && _scalingController?.currentPreview != null) ? _scalingController!.currentPreview!.foldedMesh : _cachedMesh;

  FlatPatternResult? get flatPattern => _cachedFlatPattern;

  bool get isTemplateActive => _activeTemplate != null;

  TemplateParameterDefinition? get activeTemplate => _activeTemplate;

  Map<String, double> get currentTemplateParams => Map.unmodifiable(_currentTemplateParams);

  DsfDocument? get templateBaselineDoc => _templateBaselineDoc;

  List<CadFeature> get featureTree => CadFeatureTreeBuilder.buildFeatures(_document);

  double get foldProgress => _foldProgress;

  double get splitRatio => _splitRatio;

  StudioToolMode get toolMode => _toolMode;

  PerforationPattern? get previewPerforationPattern => _previewPerforationPattern;

  List<CncPunchPrimitive>? get previewCouplerPunches => _previewCouplerPunches;

  SnapTarget? get activeSnap => _activeSnap;

  CadPoint2D? get pendingBendStart => _pendingBendStart;

  void setPendingBendStart(CadPoint2D? pt) {
    _pendingBendStart = pt;
    _rubberBandEndpoint = pt;
    notifyListeners();
  }

  CadPoint2D? get rubberBandEndpoint => _rubberBandEndpoint;

  void updateRubberBand(CadPoint2D? pt) {
    _rubberBandEndpoint = pt;
    notifyListeners();
  }

  bool get magneticSnapEnabled => _magneticSnapEnabled;

  double get azimuthDeg => _azimuthDeg;

  double get elevationDeg => _elevationDeg;

  double get cameraZoom => _cameraZoom;

  Offset get pan3D => _pan3D;

  Offset get pan2D => _pan2D;

  double get zoom2D => _zoom2D;

  bool get showWireframe => _showWireframe;

  bool get isGlassMode => _isGlassMode;

  bool get showDimensions => _showDimensions;

  bool get isPlayingAnimation => _isPlayingAnimation;

  bool get isPropertyInspectorOpen => _isPropertyInspectorOpen;

  bool get isFittingInspectorOpen => _isFittingInspectorOpen;

  bool get isSketchPaletteOpen => _isSketchPaletteOpen;

  String? get selectedBendId => _selectedBendId;

  String? get selectedCutId => _selectedCutId;

  String? get selectedFaceId => _selectedFaceId;

  String? get selectedPunchId => _selectedPunchId;

  String? get selectedPatternId => _selectedPatternId;

  int? get selectedPatternHoleIndex => _selectedPatternHoleIndex;

  String? get selectedDimensionId => _selectedDimensionId;

  String? get selectedArcId => _selectedArcId;

  String? get hoveredArcId => _hoveredArcId;

  CadArc2D? get selectedArc {
    if (_selectedArcId == null) return null;
    for (final a in _document.arcs) {
      if (a.id == _selectedArcId) return a;
    }
    return null;
  }

  void selectArc(String? id) => setSelectedArc(id);

  void setDocument(DsfDocument doc) {
    _document = doc;
    _recomputeMesh();
    notifyListeners();
  }

  void setSelectedArc(String? id, {bool multiSelect = false}) {
    if (multiSelect && id != null) {
      toggleEntitySelection(id);
      return;
    }
    if (_selectedArcId == id && _selectedEntityIds.length <= 1) return;
    _selectedArcId = id;
    _selectedEntityIds.clear();
    if (id != null) {
      _selectedBendId = null;
      _selectedCutId = null;
      _selectedPunchId = null;
      _selectedFaceId = null;
      _selectedPatternId = null;
      _selectedPatternHoleIndex = null;
      _selectedDimensionId = null;
      selectConstraintId(null);
      _selectedEntityIds.add(id);
    }
    notifyListeners();
  }

  void setHoveredArc(String? id) {
    if (_hoveredArcId == id) return;
    _hoveredArcId = id;
    notifyListeners();
  }

  void deleteArc(String arcId) {
    recordHistory();
    final updatedArcs = _document.arcs.where((a) => a.id != arcId).toList();
    _document = _document.copyWith(arcs: updatedArcs);
    if (_selectedArcId == arcId) _selectedArcId = null;
    if (_hoveredArcId == arcId) _hoveredArcId = null;
    _selectedEntityIds.remove(arcId);
    _recomputeMesh();
    notifyListeners();
  }

  void updateArc(CadArc2D updated) {
    recordHistory();
    final index = _document.arcs.indexWhere((a) => a.id == updated.id);
    if (index != -1) {
      final oldArc = _document.arcs[index];
      final newArcs = List<CadArc2D>.from(_document.arcs);
      newArcs[index] = updated;

      List<CadPoint2D> newOuterContour = _document.outerContour;
      if ((updated.isBoundary || oldArc.isBoundary) && _document.outerContour.isNotEmpty) {
        newOuterContour = _syncContourWithArc(_document.outerContour, oldArc, updated);
      }

      _document = _document.copyWith(arcs: newArcs, outerContour: newOuterContour);
      _recomputeMesh();
      notifyListeners();
    }
  }

  static List<CadPoint2D> _syncContourWithArc(List<CadPoint2D> contour, CadArc2D oldArc, CadArc2D newArc) {
    if (contour.isEmpty) return contour;
    final n = contour.length;
    int startIdx = -1;
    int endIdx = -1;
    double minStartDist = 12.0;
    double minEndDist = 12.0;

    for (int i = 0; i < n; i++) {
      final dStart = contour[i].distanceTo(oldArc.startPoint);
      if (dStart < minStartDist) {
        minStartDist = dStart;
        startIdx = i;
      }
      final dEnd = contour[i].distanceTo(oldArc.endPoint);
      if (dEnd < minEndDist) {
        minEndDist = dEnd;
        endIdx = i;
      }
    }

    if (startIdx == -1 || endIdx == -1) return contour;

    final updated = List<CadPoint2D>.from(contour);
    updated[startIdx] = newArc.startPoint;
    updated[endIdx] = newArc.endPoint;
    return updated;
  }

  int _curveResolution2D = 64;
  int get curveResolution2D => _curveResolution2D;
  int get curveResolution => _curveResolution2D;
  void setCurveResolution2D(int val) {
    _curveResolution2D = val.clamp(12, 128);
    notifyListeners();
  }

  void setCurveResolution(int val) => setCurveResolution2D(val);

  int _curveResolution3D = 32;
  int get curveResolution3D => _curveResolution3D;
  void setCurveResolution3D(int val) {
    _curveResolution3D = val.clamp(12, 64);
    _recomputeMesh();
    notifyListeners();
  }

  List<CadDimension> get dimensions => _document.dimensions;

  Set<String> get selectedEntityIds => Set.unmodifiable(_selectedEntityIds);

  List<ReferenceGeometry> get activeReferenceGeometries => allReferenceGeometries;

  bool get showConstraints => showConstraintsOnCanvas;

  void toggleConstraints() => toggleShowConstraintsOnCanvas();

  void toggleConstructionGeometry() => toggleShowConstructionGeometry();

  bool _showDofDiagnostics = false;
  bool get showDofDiagnostics => _showDofDiagnostics;
  void toggleDofDiagnostics() {
    _showDofDiagnostics = !_showDofDiagnostics;
    notifyListeners();
  }

  void setShowDofDiagnostics(bool val) {
    if (_showDofDiagnostics == val) return;
    _showDofDiagnostics = val;
    notifyListeners();
  }

  /// Classifies Degrees of Freedom (DOF) constraint state for an entity (line, cut, bend, punch).
  EntityConstraintState getEntityConstraintState(String entityId) {
    // 1. Check if entity participates in an over-constrained solver conflict
    for (final conflict in currentSolverConflicts) {
      if (conflict.contains(entityId)) {
        return EntityConstraintState.overConstrained;
      }
    }

    final entityConstraints = constraints.where((c) => c.isActive && c.entityIds.any((id) => id.contains(entityId))).toList();

    final defs = activeConstraintDefinitions.where((c) => c.isActive && !c.isSuppressed && c.references.any((r) => r.entityId.contains(entityId))).toList();

    for (final def in defs) {
      if (def.conflictReason != null && def.conflictReason!.isNotEmpty) {
        return EntityConstraintState.overConstrained;
      }
    }

    // Direct geometric contradictions (e.g. both Horizontal AND Vertical on same line)
    final hasHoriz = entityConstraints.any((c) => c.type == CadConstraintType.horizontal) || defs.any((c) => c.type == CadConstraintType.horizontal);
    final hasVert = entityConstraints.any((c) => c.type == CadConstraintType.vertical) || defs.any((c) => c.type == CadConstraintType.vertical);
    if (hasHoriz && hasVert) {
      return EntityConstraintState.overConstrained;
    }

    // 2. Check if entity has a fixed constraint
    final isFixed = entityConstraints.any((c) => c.type == CadConstraintType.fixed) || defs.any((c) => c.type == CadConstraintType.fixed);
    if (isFixed) {
      return EntityConstraintState.fullyConstrained;
    }

    // 3. Check for geometric constraints and dimensions
    final entityDimensions = _document.dimensions.where((d) => d.isVisible && (d.referenceAId == entityId || d.referenceBId == entityId)).toList();

    // If an entity has both orientation and position/size, it is fully constrained.
    final hasOrientation =
        hasHoriz ||
        hasVert ||
        entityConstraints.any(
          (c) => c.type == CadConstraintType.parallel || c.type == CadConstraintType.perpendicular || c.type == CadConstraintType.collinear,
        ) ||
        defs.any((c) => c.type == CadConstraintType.parallel || c.type == CadConstraintType.perpendicular || c.type == CadConstraintType.collinear);

    final hasPositionOrSize =
        entityConstraints.any(
          (c) =>
              c.type == CadConstraintType.distance ||
              c.type == CadConstraintType.equal ||
              c.type == CadConstraintType.coincident ||
              c.type == CadConstraintType.concentric,
        ) ||
        defs.any(
          (c) =>
              c.type == CadConstraintType.distance ||
              c.type == CadConstraintType.equal ||
              c.type == CadConstraintType.coincident ||
              c.type == CadConstraintType.concentric,
        ) ||
        entityDimensions.isNotEmpty;

    if (hasOrientation && hasPositionOrSize) {
      return EntityConstraintState.fullyConstrained;
    }

    return EntityConstraintState.underConstrained;
  }

  void startInteractiveConstraint(CadConstraintType type) => startInteractiveConstraintPick(type);

  CadPoint2D? get currentCursorMm => _currentCursorMm;

  SnapEngineSettings get snapSettings => _snapSettings;

  PressBrakeMachine get selectedMachine => _selectedMachine;

  List<String> get bendSequence => _bendSequence.isNotEmpty ? _bendSequence : _document.bends.map((b) => b.id).toList();

  bool get isStepMode => _isStepMode;

  int get currentBendStep => _currentBendStep;

  Map<String, BendValidationResult> get bendViolations => PressBrakeCamEngine.validateAllBends(doc: _document, machine: _selectedMachine);

  BendSequenceReport get bendSequenceReport =>
      BendSequenceEngine.validateSequence(doc: _document, machine: _selectedMachine, sequenceOrder: _bendSequence.isNotEmpty ? _bendSequence : null);

  double get partNetWeightKg => _document.netWeightKg;

  double get partGrossWeightKg => _document.grossWeightKg;

  String? get hoveredPunchId => _hoveredPunchId;

  String? get hoveredBendId => _hoveredBendId;

  String? get hoveredCutId => _hoveredCutId;

  String? get hoveredFaceId => _hoveredFaceId;

  FoldedMeshResult get currentMesh => (_isTeachScalingActive && _scalingController?.currentPreview != null)
      ? _scalingController!.currentPreview!.foldedMesh
      : (_cachedMesh ?? const FoldedMeshResult(polygons: [], boundWidth: 200, boundLength: 200, boundHeight: 100, center: CadPoint3D(0, 0, 0)));

  void setHoveredPunch(String? id) {
    if (_hoveredPunchId == id) return;

    _hoveredPunchId = id;

    notifyListeners();
  }

  void setHoveredBend(String? id) {
    if (_hoveredBendId == id) return;

    _hoveredBendId = id;

    notifyListeners();
  }

  void setHoveredCut(String? id) {
    if (_hoveredCutId == id) return;

    _hoveredCutId = id;

    notifyListeners();
  }

  void setHoveredFace(String? id) {
    if (_hoveredFaceId == id) return;

    _hoveredFaceId = id;

    notifyListeners();
  }

  void updateToolConfig() {
    notifyListeners();
  }

  // Undo / Redo Status

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  int get undoStackLength => _undoStack.length;

  int get redoStackLength => _redoStack.length;

  List<StudioCommandDelta> get undoStack => List.unmodifiable(_undoStack);

  List<StudioCommandDelta> get redoStack => List.unmodifiable(_redoStack);

  List<String> get undoHistoryDescriptions => _undoStack.map((d) => d.description).toList();

  List<Map<String, dynamic>> get featureHistory => _document.featureHistory;

  void clearFeatureHistory() {
    _undoStack.clear();

    _redoStack.clear();

    _document = _document.withClearedFeatureHistory();

    notifyListeners();
  }

  void _hydrateUndoStackFromDocument() {
    _undoStack.clear();

    _redoStack.clear();

    // 1. Check dedicated metadata['undoDeltas']

    final savedDeltas = _document.undoDeltas;

    if (savedDeltas.isNotEmpty) {
      for (final item in savedDeltas) {
        try {
          _undoStack.add(StudioCommandDelta.fromJson(item));
        } catch (e) {
          debugPrint('Failed to hydrate undo delta: $e');
        }
      }
    }

    // 2. Fallback: check metadata['featureHistory'] if undoStack is empty

    if (_undoStack.isEmpty) {
      final history = _document.featureHistory;

      if (history.isNotEmpty) {
        for (final entry in history) {
          try {
            if (entry['delta'] is Map) {
              _undoStack.add(StudioCommandDelta.fromJson(Map<String, dynamic>.from(entry['delta'] as Map)));
            } else {
              _undoStack.add(StudioCommandDelta.fromLegacyHistoryEntry(entry));
            }
          } catch (e) {
            debugPrint('Failed to hydrate history entry: $e');
          }
        }
      }
    }

    while (_undoStack.length > _maxUndoSteps) {
      _undoStack.removeAt(0);
    }
  }

  void _syncUndoDeltasToMetadata() {
    final undoJson = _undoStack.map((d) => d.toJson()).toList();

    _document = _document.withUndoDeltas(undoJson);
  }

  /// Ensures pending deltas are committed and metadata is synchronized before saving.

  bool _isModified = false;
  bool get isModified => _isModified;
  void markClean() {
    _isModified = false;
    notifyListeners();
  }

  void markModified() {
    _isModified = true;
    notifyListeners();
  }

  DsfDocument prepareDocumentForSave() {
    _commitPendingHistoryDelta();

    _syncUndoDeltasToMetadata();

    if (_isTeachScalingActive && _scalingController != null) {
      final committed = _scalingController!.acceptScalingModel();
      _document = committed;
      _persistentCmsPorts = _scalingController!.currentPreview?.derivedPorts ?? _persistentCmsPorts;
      _isTeachScalingActive = false;
      _scalingController = null;
    }

    final meta = Map<String, dynamic>.from(_document.metadata);

    if (_persistentCmsPorts.isNotEmpty && _document.metadata['cmsTemplate'] is Map) {
      final cms = Map<String, dynamic>.from(meta['cmsTemplate'] as Map);
      cms['ports'] = _persistentCmsPorts.map((p) => p.toJson()).toList();
      meta['cmsTemplate'] = cms;
    }

    // Persist 3-Stage workflow stage (only for CMS drawings)
    if (isCmsDrawing) {
      final cmsRaw = meta['cmsTemplate'];
      final hasScalingModel = cmsRaw is Map && cmsRaw['scalingModel'] is Map && (cmsRaw['scalingModel'] as Map).isNotEmpty;

      if (_document.bends.isNotEmpty && _persistentCmsPorts.isEmpty) {
        meta['cmsWorkflow'] = {
          'stage': 'manufacturing_defined',
          'stageIndex': 1,
        };
      } else if (_persistentCmsPorts.isNotEmpty && !hasScalingModel) {
        meta['cmsWorkflow'] = {
          'stage': 'ports_mapped',
          'stageIndex': 2,
        };
      } else if (hasScalingModel) {
        meta['cmsWorkflow'] = {
          'stage': 'template_complete',
          'stageIndex': 3,
        };
      }
    }

    _document = _document.copyWith(metadata: meta);

    return _document;
  }

  void _recordHistory([String? description]) {
    _isModified = true;
    _historyCheckpointDoc ??= _document;

    if (description != null) {
      _pendingHistoryDescription = description;
    }
  }

  void _commitPendingHistoryDelta() {
    if (_isApplyingUndoRedo || _isDraggingObject) return;

    if (_historyCheckpointDoc != null) {
      final oldDoc = _historyCheckpointDoc!;

      _historyCheckpointDoc = null;

      final desc = _pendingHistoryDescription;

      _pendingHistoryDescription = null;

      if (!identical(oldDoc, _document) && oldDoc != _document) {
        final delta = StudioCommandDelta.between(oldDoc, _document, description: desc);

        _undoStack.add(delta);

        if (_undoStack.length > _maxUndoSteps) {
          _undoStack.removeAt(0);
        }

        _redoStack.clear();

        // Append to persistent feature history audit log in DsfDocument metadata

        final entry = delta.toFeatureHistoryEntry(step: _document.featureHistory.length + 1);

        _document = _document.withAppendedFeatureHistory(entry);

        _syncUndoDeltasToMetadata();
      }
    }
  }

  /// Manually records an explicit Command/Delta action

  void recordCommand(StudioCommandDelta delta) {
    _undoStack.add(delta);

    if (_undoStack.length > _maxUndoSteps) {
      _undoStack.removeAt(0);
    }

    _redoStack.clear();

    final entry = delta.toFeatureHistoryEntry(step: _document.featureHistory.length + 1);

    _document = _document.withAppendedFeatureHistory(entry);

    _syncUndoDeltasToMetadata();
  }

  @override
  void notifyListeners() {
    _commitPendingHistoryDelta();

    super.notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;

    _isApplyingUndoRedo = true;

    try {
      final delta = _undoStack.removeLast();

      _redoStack.add(delta);

      _document = delta.undo(_document);

      _clearSelections();

      _recomputeMesh();

      _syncUndoDeltasToMetadata();
    } finally {
      _isApplyingUndoRedo = false;
    }

    super.notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;

    _isApplyingUndoRedo = true;

    try {
      final delta = _redoStack.removeLast();

      _undoStack.add(delta);

      _document = delta.redo(_document);

      _clearSelections();

      _recomputeMesh();

      _syncUndoDeltasToMetadata();
    } finally {
      _isApplyingUndoRedo = false;
    }

    super.notifyListeners();
  }

  void _clearSelections() {
    _selectedBendId = null;

    _selectedCutId = null;

    _selectedPunchId = null;

    _selectedFaceId = null;

    _selectedPatternId = null;

    _selectedPatternHoleIndex = null;

    _selectedDimensionId = null;

    _selectedArcId = null;

    _selectedEntityIds.clear();

    _pendingBendStart = null;

    _rubberBandEndpoint = null;

    _pendingDimensionEntityAId = null;

    _pendingDimensionAnchorTypeA = null;

    _pendingMultiPoints.clear();
  }

  /// Begins an interactive drag session (saves 1 history state for the entire gesture).

  void beginObjectDrag([String? description]) {
    if (!_isDraggingObject) {
      _recordHistory(description ?? 'Drag CAD Object');

      _isDraggingObject = true;
    }
  }

  /// Finalizes the interactive drag gesture.

  void endObjectDrag() {
    if (_isDraggingObject) {
      _isDraggingObject = false;

      _commitPendingHistoryDelta();

      _recomputeMesh();

      notifyListeners();
    }
  }

  void clearSelection() {
    _selectedBendId = null;

    _selectedCutId = null;

    _selectedPunchId = null;

    _selectedFaceId = null;

    _selectedPatternId = null;

    _selectedPatternHoleIndex = null;

    _selectedDimensionId = null;

    _selectedArcId = null;

    selectConstraintId(null);

    _selectedEntityIds.clear();

    notifyListeners();
  }

  // Actions

  void setFoldProgress(double progress) {
    _foldProgress = progress.clamp(0.0, 1.0);

    _recomputeMesh();

    notifyListeners();
  }

  void setSplitRatio(double ratio) {
    _splitRatio = ratio.clamp(0.15, 0.85);

    notifyListeners();
  }

  void orbit3D(double deltaAzimuth, double deltaElevation) {
    _azimuthDeg = (_azimuthDeg + deltaAzimuth) % 360.0;

    if (_azimuthDeg < 0) _azimuthDeg += 360.0;

    _elevationDeg = (_elevationDeg + deltaElevation) % 360.0;

    if (_elevationDeg < 0) _elevationDeg += 360.0;

    notifyListeners();
  }

  void zoom3D(double factor) {
    _cameraZoom = (_cameraZoom * factor).clamp(0.1, 10.0);

    notifyListeners();
  }

  void pan3DCanvas(Offset delta) {
    _pan3D += delta;

    notifyListeners();
  }

  void resetCamera() {
    _azimuthDeg = 45.0;

    _elevationDeg = 30.0;

    _cameraZoom = 1.0;

    _pan3D = Offset.zero;

    notifyListeners();
  }

  void setPresetView({required double azimuth, required double elevation}) {
    _azimuthDeg = azimuth;

    _elevationDeg = elevation;

    notifyListeners();
  }

  void pan2DCanvas(Offset delta) {
    _pan2D += delta;

    notifyListeners();
  }

  void zoom2DCanvas(double factor, {Offset? focalPoint, Size? viewportSize}) {
    final oldZoom = _zoom2D;
    final newZoom = (_zoom2D * factor).clamp(0.05, 20.0);
    final actualFactor = newZoom / oldZoom;

    if (focalPoint != null && viewportSize != null && actualFactor != 1.0) {
      final focusRel = focalPoint - Offset(viewportSize.width / 2.0, viewportSize.height / 2.0);
      _pan2D = focusRel * (1.0 - actualFactor) + _pan2D * actualFactor;
    }
    _zoom2D = newZoom;

    notifyListeners();
  }

  void reset2DCanvas() {
    _pan2D = Offset.zero;

    _zoom2D = 1.0;

    notifyListeners();
  }

  void setPreviewPerforation(PerforationPattern? pattern, {List<CncPunchPrimitive>? couplers}) {
    _previewPerforationPattern = pattern;

    _previewCouplerPunches = couplers;

    _safeNotifyListeners();
  }

  void clearPreviewPerforation() {
    if (_previewPerforationPattern != null || _previewCouplerPunches != null) {
      _previewPerforationPattern = null;

      _previewCouplerPunches = null;

      _safeNotifyListeners();
    }
  }

  void _safeNotifyListeners() {
    try {
      final binding = WidgetsBinding.instance;

      if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        binding.addPostFrameCallback((_) {
          notifyListeners();
        });

        return;
      }
    } catch (_) {}

    notifyListeners();
  }

  void setToolMode(StudioToolMode mode) {
    _toolMode = mode;

    _pendingBendStart = null;

    _rubberBandEndpoint = null;

    _pendingDimensionEntityAId = null;

    _pendingDimensionAnchorTypeA = null;

    _pendingMultiPoints.clear();

    _activeSnap = null;

    if (mode != StudioToolMode.perforationPattern) {
      _previewPerforationPattern = null;

      _previewCouplerPunches = null;
    }

    notifyListeners();
  }

  void toggleMagneticSnap() {
    _magneticSnapEnabled = !_magneticSnapEnabled;

    if (!_magneticSnapEnabled) {
      clearSnap();
    }

    notifyListeners();
  }

  void toggleWireframe() {
    _showWireframe = !_showWireframe;

    notifyListeners();
  }

  void toggleGlassMode() {
    _isGlassMode = !_isGlassMode;

    notifyListeners();
  }

  void toggleDimensions() {
    _showDimensions = !_showDimensions;

    notifyListeners();
  }

  void setPropertyInspectorOpen(bool open) {
    if (_isPropertyInspectorOpen != open) {
      _isPropertyInspectorOpen = open;

      notifyListeners();
    }
  }

  void togglePropertyInspector() {
    _isPropertyInspectorOpen = !_isPropertyInspectorOpen;

    notifyListeners();
  }

  void setFittingInspectorOpen(bool open) {
    if (_isFittingInspectorOpen != open) {
      _isFittingInspectorOpen = open;

      notifyListeners();
    }
  }

  void toggleFittingInspector() {
    _isFittingInspectorOpen = !_isFittingInspectorOpen;

    notifyListeners();
  }

  void setSketchPaletteOpen(bool open) {
    if (_isSketchPaletteOpen != open) {
      _isSketchPaletteOpen = open;
      notifyListeners();
    }
  }

  void toggleSketchPalette() {
    _isSketchPaletteOpen = !_isSketchPaletteOpen;
    notifyListeners();
  }

  Future<void> playFoldingAnimation() async {
    if (_isPlayingAnimation) return;

    _isPlayingAnimation = true;

    notifyListeners();

    if (_foldProgress >= 0.99) {
      setFoldProgress(0.0);

      await Future.delayed(const Duration(milliseconds: 200));
    }

    const steps = 40;

    const duration = Duration(milliseconds: 1400);

    final interval = duration.inMilliseconds ~/ steps;

    final start = _foldProgress;

    for (int i = 1; i <= steps; i++) {
      if (!_isPlayingAnimation) break;

      final t = i / steps;

      final curvedT = Curves.easeInOutCubic.transform(t);

      setFoldProgress(start + (1.0 - start) * curvedT);

      await Future.delayed(Duration(milliseconds: interval));
    }

    _isPlayingAnimation = false;

    notifyListeners();
  }

  void stopAnimation() {
    _isPlayingAnimation = false;

    notifyListeners();
  }

  /// Checks whether a bend line is incomplete/open (does not partition between two faces).

  bool isBendIncomplete(FoldBendLine bend) {
    return bend.parentFaceId.isEmpty || bend.childFaceId.isEmpty || bend.parentFaceId == bend.childFaceId;
  }

  bool? _altPressedOverride;

  bool get isAltPressed {
    if (_altPressedOverride != null) return _altPressedOverride!;
    try {
      if (HardwareKeyboard.instance.isAltPressed) return true;
      if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.altLeft) ||
          HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.altRight)) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  set isAltPressed(bool? val) {
    _altPressedOverride = val;
  }

  /// Snaps an endpoint around [anchor] in 5Â° steps with magnetic priority for major axes (0Â°, 45Â°, 90Â°, 180Â°, etc.).

  /// If [isAlt] is true, moves freely without angle quantization.

  static CadPoint2D snapEndpointAngle({required CadPoint2D anchor, required CadPoint2D target, bool isAlt = false}) {
    if (isAlt) return target;

    final dx = target.x - anchor.x;

    final dy = target.y - anchor.y;

    final len = math.sqrt(dx * dx + dy * dy);

    if (len < 0.5) return target;

    double angle = math.atan2(dy, dx) * 180.0 / math.pi;

    if (angle < 0) angle += 360.0;

    // Snap to 5-degree increments with 45Â°/90Â°/180Â° priority

    double snapped = (angle / 5.0).round() * 5.0;

    const majorAxes = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0, 360.0];

    for (final ax in majorAxes) {
      if ((angle - ax).abs() <= 2.5 || (angle - (ax - 360)).abs() <= 2.5) {
        snapped = ax % 360.0;

        break;
      }
    }

    final rad = snapped * math.pi / 180.0;

    return CadPoint2D(anchor.x + len * math.cos(rad), anchor.y + len * math.sin(rad));
  }

  /// Resolves a 2D coordinate with 45Â° angle snapping (if line is in progress and Alt not held)

  /// and magnetic snapping (if enabled).

  CadPoint2D resolveEffectivePoint(CadPoint2D point, {double snapRadiusMm = 8.0}) {
    if (isAltPressed) {
      return point;
    }

    CadPoint2D candidate = point;

    final anchor = _pendingBendStart ?? (_pendingMultiPoints.isNotEmpty ? _pendingMultiPoints.last : null);

    if (anchor != null) {
      candidate = snapEndpointAngle(anchor: anchor, target: point, isAlt: isAltPressed);
    }

    if (_magneticSnapEnabled) {
      final targets = MagneticSnapEngine.extractTargets(_document, settings: _snapSettings, anchorPoint: anchor);

      if (_toolMode == StudioToolMode.drawPolyline && _pendingMultiPoints.length >= 2) {
        targets.insert(0, SnapTarget(point: _pendingMultiPoints.first, type: SnapType.endpoint, label: 'Close Polyline (Cutout Void)'));
      }

      final snap = MagneticSnapEngine.findClosestSnap(
        cursorMm: candidate,

        targets: targets,

        doc: _document,

        settings: _snapSettings,

        anchorPoint: anchor,

        snapRadiusMm: snapRadiusMm,
      );

      if (snap != null) {
        return snap.point;
      }
    }

    return candidate;
  }

  /// Updates cursor position with automatic angle snapping (unless Alt is held)

  /// and localized magnetic snapping.

  void updateCursorMm(CadPoint2D cursorMm, {double snapRadiusMm = 8.0, bool? isAlt}) {
    if (isAlt != null) {
      isAltPressed = isAlt;
    }
    _currentCursorMm = cursorMm;

    if (isAltPressed) {
      _activeSnap = null;
      _rubberBandEndpoint = cursorMm;
      notifyListeners();
      return;
    }

    CadPoint2D candidate = cursorMm;

    final anchor = _pendingBendStart ?? (_pendingMultiPoints.isNotEmpty ? _pendingMultiPoints.last : null);

    // 1. Angle snapping if currently drawing a linear entity (polyline, bend, flange, cut, dimension)
    final isLinearTool =
        _toolMode == StudioToolMode.drawPolyline ||
        _toolMode == StudioToolMode.addBend ||
        _toolMode == StudioToolMode.addFlange ||
        _toolMode == StudioToolMode.addCut ||
        _toolMode == StudioToolMode.addDimension ||
        _toolMode == StudioToolMode.dragDimension;

    if (anchor != null && isLinearTool) {
      if (!isAltPressed && _snapSettings.enableOrthoTracking) {
        candidate = snapEndpointAngle(anchor: anchor, target: cursorMm, isAlt: isAltPressed);
      }
    }

    // 2. Magnetic snapping if enabled
    if (_magneticSnapEnabled) {
      // Do not ortho-track rectangle/circle against its own anchor point so the opposite corner
      // does not snap onto the start point axes / origin line.
      final effectiveSnapAnchor =
          (_toolMode == StudioToolMode.drawRectangle ||
              _toolMode == StudioToolMode.drawCircle ||
              _toolMode == StudioToolMode.addPunchRound ||
              _toolMode == StudioToolMode.addPunchSquare ||
              _toolMode == StudioToolMode.addPunchObround)
          ? null
          : anchor;

      final targets = MagneticSnapEngine.extractTargets(_document, settings: _snapSettings, anchorPoint: effectiveSnapAnchor);

      if (_toolMode == StudioToolMode.drawPolyline && _pendingMultiPoints.length >= 2) {
        targets.insert(0, SnapTarget(point: _pendingMultiPoints.first, type: SnapType.endpoint, label: 'Close Polyline (Cutout Void)'));
      }

      var snap = MagneticSnapEngine.findClosestSnap(
        cursorMm: candidate,
        targets: targets,
        doc: _document,
        settings: _snapSettings,
        anchorPoint: effectiveSnapAnchor,
        snapRadiusMm: snapRadiusMm,
      );

      // When drawing a rectangle, avoid collapsing onto the starting point itself if dragged
      if (_toolMode == StudioToolMode.drawRectangle && anchor != null && snap != null) {
        if (snap.point.distanceTo(anchor) < 1e-3) {
          snap = null;
        }
      }

      _activeSnap = snap;
    } else {
      _activeSnap = null;
    }

    _rubberBandEndpoint = _activeSnap?.point ?? candidate;

    notifyListeners();
  }

  void clearSnap() {
    if (_activeSnap != null) {
      _activeSnap = null;

      notifyListeners();
    }
  }

  void handleCanvasClick(CadPoint2D clickedPoint, {double snapRadiusMm = 8.0, bool autoPlace = false, bool multiSelect = false}) {
    var effectivePoint = _activeSnap?.point ?? resolveEffectivePoint(clickedPoint, snapRadiusMm: snapRadiusMm);

    if (_toolMode == StudioToolMode.addPunchRound || _toolMode == StudioToolMode.drawCircle) {
      final newId = 'P${_document.punches.length + 1}';
      final diam = toolConfig.roundHoleDiameter > 0 ? toolConfig.roundHoleDiameter : 10.0;
      final p = CncTurretEngine.createRoundHole(id: newId, center: effectivePoint, diameterMm: diam);
      addPunch(p);
      selectPunch(p.id);
      _toolMode = StudioToolMode.select;
    } else if (_toolMode == StudioToolMode.addPunchObround) {
      final newId = 'P${_document.punches.length + 1}';
      final effW = toolConfig.obroundLength > 0 ? toolConfig.obroundLength : 25.0;
      final effL = toolConfig.obroundWidth > 0 ? toolConfig.obroundWidth : 10.0;
      final p = CncTurretEngine.createObroundSlot(id: newId, center: effectivePoint, widthMm: effW, lengthMm: effL);
      addPunch(p);
      selectPunch(p.id);
      _toolMode = StudioToolMode.select;
    } else if (_toolMode == StudioToolMode.addPunchSquare || _toolMode == StudioToolMode.drawRectangle) {
      final newId = 'P${_document.punches.length + 1}';
      final w = toolConfig.squareAspectLocked ? toolConfig.squareSize : toolConfig.rectWidth;
      final h = toolConfig.squareAspectLocked ? toolConfig.squareSize : toolConfig.rectHeight;
      final effW = w > 0 ? w : 20.0;
      final effH = h > 0 ? h : 20.0;
      final p = CncTurretEngine.createRectangularPunch(id: newId, center: effectivePoint, widthMm: effW, heightMm: effH);
      addPunch(p);
      selectPunch(p.id);
      _toolMode = StudioToolMode.select;
    } else if (_toolMode == StudioToolMode.perforationPattern) {
      final double effW;

      final double effH;

      if (toolConfig.patternHoleType == PunchType.roundHole) {
        effW = toolConfig.patternDiameter;

        effH = toolConfig.patternDiameter;
      } else if (toolConfig.patternHoleType == PunchType.square) {
        effW = toolConfig.patternSquareSize;

        effH = toolConfig.patternSquareSize;
      } else if (toolConfig.patternHoleType == PunchType.rectangle) {
        effW = toolConfig.patternRectWidth;

        effH = toolConfig.patternRectHeight;
      } else {
        effW = toolConfig.patternSlotWidth;

        effH = toolConfig.patternSlotHeight;
      }

      applyPerforationPattern(
        center: effectivePoint,

        countX: toolConfig.patternColsX,

        countY: toolConfig.patternRowsY,

        pitchX: toolConfig.patternPitchX,

        pitchY: toolConfig.patternPitchY,

        slotWidth: effW,

        slotHeight: effH,

        staggered: toolConfig.patternStaggered,

        rotationDeg: toolConfig.patternRotationDeg,

        holeType: toolConfig.patternHoleType,

        diameterMm: toolConfig.patternDiameter,
      );

      _toolMode = StudioToolMode.select;
    } else if (_toolMode == StudioToolMode.cornerFillet || _toolMode == StudioToolMode.cornerChamfer) {
      int bestIdx = -1;

      double bestDist = 20.0;

      for (int i = 0; i < _document.outerContour.length; i++) {
        final d = _document.outerContour[i].distanceTo(effectivePoint);

        if (d < bestDist) {
          bestDist = d;

          bestIdx = i;
        }
      }

      if (bestIdx != -1) {
        if (_toolMode == StudioToolMode.cornerFillet) {
          applyCornerFillet(bestIdx, 5.0);
        } else {
          applyCornerChamfer(bestIdx, toolConfig.chamferDist);
        }

        _toolMode = StudioToolMode.select;
      }
    } else if (_toolMode == StudioToolMode.addBend || _toolMode == StudioToolMode.addFlange) {
      if (_pendingBendStart == null && autoPlace && _autoBendPlacementEnabled) {
        final isFlange = _toolMode == StudioToolMode.addFlange;

        final placed = tryAutoPlaceBendOrFlange(effectivePoint, isFlange: isFlange);

        if (placed) {
          _pendingBendStart = null;

          _rubberBandEndpoint = null;

          return;
        }
      }

      if (_pendingBendStart == null) {
        _pendingBendStart = effectivePoint;

        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      } else {
        final p1 = _pendingBendStart!;

        final p2 = effectivePoint;

        _pendingBendStart = null;

        _rubberBandEndpoint = null;

        if (p1.distanceTo(p2) > 1.0) {
          if (_toolMode == StudioToolMode.addFlange) {
            addFlangeLine(p1, p2);
          } else {
            addBendLine(p1, p2);
          }
        }
      }
    } else if (_toolMode == StudioToolMode.addCut) {
      if (_pendingBendStart == null) {
        _pendingBendStart = effectivePoint;

        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      } else {
        final p1 = _pendingBendStart!;

        final p2 = effectivePoint;

        _pendingBendStart = null;

        _rubberBandEndpoint = null;

        if (p1.distanceTo(p2) > 1.0) {
          addCutLine(p1, p2);
        }
      }
    } else if (_toolMode == StudioToolMode.drawRectangle) {
      if (_pendingBendStart == null) {
        _pendingBendStart = effectivePoint;

        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      } else {
        final c1 = _pendingBendStart!;

        final c2 = effectivePoint;

        _pendingBendStart = null;

        _rubberBandEndpoint = null;

        if (c1.distanceTo(c2) > 1.0) {
          addCutRectangle(c1, c2);
        } else {
          // Single-click stamps with configured punch size
          final newId = 'P${_document.punches.length + 1}';
          final w = toolConfig.squareAspectLocked ? toolConfig.squareSize : toolConfig.rectWidth;
          final h = toolConfig.squareAspectLocked ? toolConfig.squareSize : toolConfig.rectHeight;
          final p = CncTurretEngine.createRectangularPunch(id: newId, center: c1, widthMm: w, heightMm: h);
          addPunch(p);
          _toolMode = StudioToolMode.select;
        }
      }
    } else if (_toolMode == StudioToolMode.drawCircle) {
      if (_pendingBendStart == null) {
        _pendingBendStart = effectivePoint;

        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      } else {
        final center = _pendingBendStart!;

        final r = center.distanceTo(effectivePoint);

        _pendingBendStart = null;

        _rubberBandEndpoint = null;

        if (r > 0.5) {
          final newId = 'P${_document.punches.length + 1}';

          final p = CncTurretEngine.createRoundHole(id: newId, center: center, diameterMm: r * 2.0);

          addPunch(p);

          _toolMode = StudioToolMode.select;
        } else {
          // Single-click stamps with configured punch diameter
          final newId = 'P${_document.punches.length + 1}';
          final p = CncTurretEngine.createRoundHole(id: newId, center: center, diameterMm: toolConfig.roundHoleDiameter);
          addPunch(p);
          _toolMode = StudioToolMode.select;
        }
      }
    } else if (_toolMode == StudioToolMode.drawArc) {
      _pendingMultiPoints.add(effectivePoint);

      if (_pendingMultiPoints.length < 3) {
        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      } else {
        final p1 = _pendingMultiPoints[0];

        final p2 = _pendingMultiPoints[1];

        final p3 = _pendingMultiPoints[2];

        _pendingMultiPoints.clear();

        _rubberBandEndpoint = null;

        addArcEntity(p1, p2, p3);
      }
    } else if (_toolMode == StudioToolMode.drawPolyline) {
      final isCloseClick =
          _pendingMultiPoints.isNotEmpty &&
          (effectivePoint.distanceTo(_pendingMultiPoints.first) < 8.0 || effectivePoint == _pendingMultiPoints.first) &&
          _pendingMultiPoints.length >= 2;

      if (isCloseClick) {
        final pts = List<CadPoint2D>.from(_pendingMultiPoints);

        pts.add(_pendingMultiPoints.first);

        _pendingMultiPoints.clear();

        _rubberBandEndpoint = null;

        addClosedCutoutVoid(pts);
      } else {
        _pendingMultiPoints.add(effectivePoint);

        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      }
    } else if (_toolMode == StudioToolMode.modifyMove) {
      if (_pendingBendStart == null) {
        _pendingBendStart = effectivePoint;

        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      } else {
        final base = _pendingBendStart!;

        final target = effectivePoint;

        _pendingBendStart = null;

        _rubberBandEndpoint = null;

        final dx = target.x - base.x;

        final dy = target.y - base.y;

        moveSelectedEntities(dx, dy);

        _toolMode = StudioToolMode.select;
      }
    } else if (_toolMode == StudioToolMode.modifyRotate) {
      if (_pendingBendStart == null) {
        _pendingBendStart = effectivePoint;

        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      } else {
        final center = _pendingBendStart!;

        final angleDeg = toolConfig.rotateAngleDeg;

        _pendingBendStart = null;

        _rubberBandEndpoint = null;

        rotateSelectedEntities(center, angleDeg);

        _toolMode = StudioToolMode.select;
      }
    } else if (_toolMode == StudioToolMode.modifyMirror) {
      if (_pendingBendStart == null) {
        _pendingBendStart = effectivePoint;

        _rubberBandEndpoint = effectivePoint;

        notifyListeners();
      } else {
        final axisP1 = _pendingBendStart!;

        final axisP2 = effectivePoint;

        _pendingBendStart = null;

        _rubberBandEndpoint = null;

        if (axisP1.distanceTo(axisP2) > 1.0) {
          mirrorSelectedEntities(axisP1, axisP2, copy: true);

          _toolMode = StudioToolMode.select;
        }
      }
    } else if (_toolMode == StudioToolMode.modifyOffset) {
      offsetContour(toolConfig.offsetDistance);

      _toolMode = StudioToolMode.select;
    } else if (_toolMode == StudioToolMode.addDimension || _toolMode == StudioToolMode.dragDimension) {
      // Find if clicked on or snapped to an entity
      String? clickedEntityId = _activeSnap?.entityId;
      CadAnchorType clickedAnchorType = _mapSnapTypeToAnchorType(_activeSnap?.type);

      // If not snapped to a punch/arc/bend/cut/contour, test if close to a punch or edge
      if (clickedEntityId == null) {
        for (final punch in _document.punches) {
          if (!punch.isVisible) continue;
          final dist = effectivePoint.distanceTo(punch.center);
          final effRadius = punch.isRound
              ? punch.diameterMm / 2.0
              : math.max(punch.widthMm, punch.lengthMm) / 2.0;
          if (dist <= math.max(10.0, effRadius + 4.0)) {
            clickedEntityId = punch.id;
            clickedAnchorType = CadAnchorType.center;
            effectivePoint = punch.center;
            break;
          }
        }
      }

      if (clickedEntityId == null) {
        for (final arc in _document.arcs) {
          if (arc.distanceTo(effectivePoint) <= 8.0) {
            clickedEntityId = arc.id;
            clickedAnchorType = CadAnchorType.center;
            break;
          }
        }
      }

      CadPoint2D? edgeP1;
      CadPoint2D? edgeP2;
      String? edgeRefId;

      if (clickedEntityId == null) {
        for (final cut in _document.cutLines) {
          if (_distToSegment(effectivePoint, cut.p1, cut.p2) <= 8.0) {
            edgeP1 = cut.p1;
            edgeP2 = cut.p2;
            edgeRefId = cut.id;
            break;
          }
        }
      }

      if (clickedEntityId == null && edgeP1 == null) {
        for (final bend in _document.bends) {
          if (_distToSegment(effectivePoint, bend.p1, bend.p2) <= 8.0) {
            edgeP1 = bend.p1;
            edgeP2 = bend.p2;
            edgeRefId = bend.id;
            break;
          }
        }
      }

      if (clickedEntityId == null && edgeP1 == null && _document.outerContour.length >= 2) {
        for (int i = 0; i < _document.outerContour.length; i++) {
          final c1 = _document.outerContour[i];
          final c2 = _document.outerContour[(i + 1) % _document.outerContour.length];
          if (_distToSegment(effectivePoint, c1, c2) <= 8.0) {
            edgeP1 = c1;
            edgeP2 = c2;
            edgeRefId = 'CONTOUR_EDGE_$i';
            break;
          }
        }
      }

      if (clickedEntityId == null && edgeRefId != null) {
        clickedEntityId = edgeRefId;
        clickedAnchorType = CadAnchorType.midpoint;
      }

      if (_pendingBendStart == null) {
        if (edgeRefId != null && edgeP1 != null && edgeP2 != null) {
          // 1-click edge measurement
          final measuredVal = edgeP1.distanceTo(edgeP2);
          final dimId = 'dim_${_document.dimensions.length + 1}';
          final dim = CadDimension(
            id: dimId,
            type: CadDimensionType.aligned,
            referenceAId: edgeRefId,
            referenceBId: edgeRefId,
            anchorTypeA: CadAnchorType.endpoint,
            anchorTypeB: CadAnchorType.endpoint,
            pointA: edgeP1,
            pointB: edgeP2,
            measuredValue: measuredVal,
            dimensionLineOffset: toolConfig.dimensionOffsetMm,
            isDriven: false,
            isDriving: true,
            allowedMotion: CadAllowedMotion.structuralParameter,
            referenceEntityId: edgeRefId,
            drivenEntityId: edgeRefId,
          );
          addDimension(dim);
          _pendingInPlaceEditDimId = dimId;
          _toolMode = StudioToolMode.select;
          notifyListeners();
          return;
        }

        // CLICK 1: Select Entity A
        _pendingBendStart = effectivePoint;
        _rubberBandEndpoint = effectivePoint;
        _pendingDimensionEntityAId = clickedEntityId;
        _pendingDimensionAnchorTypeA = clickedAnchorType;
        notifyListeners();
      } else {
        // CLICK 2: Select Entity B & Place Dimension
        var pA = _pendingBendStart!;
        var pB = effectivePoint;
        final entityAId = _pendingDimensionEntityAId;
        final entityBId = clickedEntityId;
        final anchorTypeA = _pendingDimensionAnchorTypeA ?? CadAnchorType.endpoint;
        final anchorTypeB = clickedAnchorType;

        _pendingBendStart = null;
        _rubberBandEndpoint = null;
        _pendingDimensionEntityAId = null;
        _pendingDimensionAnchorTypeA = null;

        // Auto-detect edge if point is on or near an edge/bend
        var resolvedEntityAId = entityAId ?? _findNearestEdgeOrBendId(pA);
        var resolvedEntityBId = entityBId ?? _findNearestEdgeOrBendId(pB);

        // Categorize dimension
        CadDimensionType categorizedType = toolConfig.activeDimensionType;
        CadAllowedMotion allowedMotion = CadAllowedMotion.free;
        String? refEntityId = resolvedEntityAId;
        String? drivenEntityId = resolvedEntityBId;

        final isPunchA = resolvedEntityAId != null && _document.punches.any((p) => p.id == resolvedEntityAId);
        final isPunchB = resolvedEntityBId != null && _document.punches.any((p) => p.id == resolvedEntityBId);
        final isEdgeA = resolvedEntityAId != null && (resolvedEntityAId.startsWith('CONTOUR_EDGE_') || _document.bends.any((b) => b.id == resolvedEntityAId) || _document.cutLines.any((c) => c.id == resolvedEntityAId));
        final isEdgeB = resolvedEntityBId != null && (resolvedEntityBId.startsWith('CONTOUR_EDGE_') || _document.bends.any((b) => b.id == resolvedEntityBId) || _document.cutLines.any((c) => c.id == resolvedEntityBId));

        if (isPunchA && isPunchB) {
          // Hole to Hole
          categorizedType = CadDimensionType.holeToHole;
          allowedMotion = CadAllowedMotion.constraintVector;
          refEntityId = resolvedEntityAId;
          drivenEntityId = resolvedEntityBId;
        } else if ((isPunchA && isEdgeB) || (isEdgeA && isPunchB)) {
          // Hole to Edge Setback
          categorizedType = CadDimensionType.holeToEdge;
          allowedMotion = CadAllowedMotion.edgeNormal;
          refEntityId = isPunchA ? resolvedEntityBId : resolvedEntityAId; // Edge is reference
          drivenEntityId = isPunchA ? resolvedEntityAId : resolvedEntityBId; // Punch is driven

          final punchCenter = isPunchA ? pA : pB;
          final edgeId = isPunchA ? resolvedEntityBId : resolvedEntityAId;
          final edgeSeg = _resolveEdgeSegment(edgeId);
          if (edgeSeg != null) {
            final proj = _projectPointToSegmentLine(punchCenter, edgeSeg.$1, edgeSeg.$2);
            if (isPunchA) {
              pB = proj;
            } else {
              pA = proj;
            }
          }
        } else if (isEdgeA && isEdgeB) {
          // Edge to Edge
          categorizedType = CadDimensionType.edgeToEdge;
          allowedMotion = CadAllowedMotion.structuralParameter;
          refEntityId = resolvedEntityAId;
          drivenEntityId = resolvedEntityBId;
        } else if (isEdgeA && resolvedEntityAId == resolvedEntityBId && edgeP1 != null && edgeP2 != null) {
          // Clicked same edge twice -> measure edge length
          categorizedType = CadDimensionType.aligned;
          allowedMotion = CadAllowedMotion.structuralParameter;
          pA = edgeP1;
          pB = edgeP2;
        }

        final dist = pA.distanceTo(pB);
        if (dist > 0.5) {
          final dimId = 'dim_${_document.dimensions.length + 1}';
          final dim = CadDimension(
            id: dimId,
            type: categorizedType,
            referenceAId: resolvedEntityAId,
            referenceBId: resolvedEntityBId,
            anchorTypeA: anchorTypeA,
            anchorTypeB: anchorTypeB,
            pointA: pA,
            pointB: pB,
            measuredValue: dist,
            dimensionLineOffset: toolConfig.dimensionOffsetMm,
            isDriven: false,
            isDriving: true,
            allowedMotion: allowedMotion,
            referenceEntityId: refEntityId,
            drivenEntityId: drivenEntityId,
          );
          addDimension(dim);
          _pendingInPlaceEditDimId = dimId;
          _toolMode = StudioToolMode.select;
        }
      }
    } else if (_toolMode == StudioToolMode.setBaseAnchor) {
      for (final face in _document.faces) {
        if (_isPointInPoly(effectivePoint, face.vertices)) {
          setBaseAnchorFace(face.id);

          break;
        }
      }
    } else if (_toolMode == StudioToolMode.select) {
      CncPunchPrimitive? bestPunch;
      double bestPunchDist = double.infinity;
      for (final p in _document.punches) {
        final r = p.isRound ? (p.diameterMm / 2.0 + 3.0).clamp(10.0, 30.0) : (math.max(p.widthMm, p.lengthMm) / 2.0 + 3.0).clamp(10.0, 30.0);
        final d1 = p.center.distanceTo(clickedPoint);
        final d2 = p.center.distanceTo(effectivePoint);
        final d = math.min(d1, d2);
        if (d <= r && d < bestPunchDist) {
          bestPunchDist = d;
          bestPunch = p;
        }
      }

      if (bestPunch != null) {
        if (multiSelect) {
          toggleEntitySelection(bestPunch.id);
        } else {
          selectPunch(bestPunch.id);
        }
      } else {
        FoldBendLine? bestBend;
        double bestBendDist = 15.0;
        for (final bend in _document.bends) {
          final d1 = _distToSegment(clickedPoint, bend.p1, bend.p2);
          final d2 = _distToSegment(effectivePoint, bend.p1, bend.p2);
          final dist = math.min(d1, d2);
          if (dist <= bestBendDist) {
            bestBendDist = dist;
            bestBend = bend;
          }
        }

        if (bestBend != null) {
          if (multiSelect) {
            toggleEntitySelection(bestBend.id);
          } else {
            selectBend(bestBend.id);
          }
        } else {
          CadLineSegment? bestCut;
          double bestCutDist = 15.0;
          for (final cut in _document.cutLines) {
            final d1 = _distToSegment(clickedPoint, cut.p1, cut.p2);
            final d2 = _distToSegment(effectivePoint, cut.p1, cut.p2);
            final dist = math.min(d1, d2);
            if (dist <= bestCutDist) {
              bestCutDist = dist;
              bestCut = cut;
            }
          }

          if (bestCut != null) {
            if (multiSelect) {
              toggleEntitySelection(bestCut.id);
            } else {
              selectCut(bestCut.id);
            }
          } else {
            CadArc2D? bestArc;
            double bestArcDist = 15.0;
            for (final arc in _document.arcs) {
              final d1 = arc.distanceTo(clickedPoint);
              final d2 = arc.distanceTo(effectivePoint);
              final dist = math.min(d1, d2);
              if (dist <= bestArcDist) {
                bestArcDist = dist;
                bestArc = arc;
              }
            }

            if (bestArc != null) {
              if (multiSelect) {
                toggleEntitySelection(bestArc.id);
              } else {
                setSelectedArc(bestArc.id);
              }
            } else {
              PerforationPattern? bestPattern;
              int? bestHoleIndex;
              for (final pat in _document.perforationPatterns) {
                final hIdx1 = pat.findHoleAt(clickedPoint, maxDistMm: 15.0);
                final hIdx2 = pat.findHoleAt(effectivePoint, maxDistMm: 15.0);
                final hIdx = hIdx1 ?? hIdx2;
                if (hIdx != null || pat.containsPoint(clickedPoint) || pat.containsPoint(effectivePoint)) {
                  bestPattern = pat;
                  bestHoleIndex = hIdx;
                  break;
                }
              }

              if (bestPattern != null) {
                if (multiSelect) {
                  toggleEntitySelection(bestPattern.id);
                } else {
                  selectPattern(bestPattern.id, bestHoleIndex);
                }
              } else {
                // Check if clicked point hits a dimension line or reference
                CadDimension? bestDim;
                for (final d in _document.dimensions) {
                  if (d.pointA != null && d.pointB != null) {
                    if (_distToSegment(clickedPoint, d.pointA!, d.pointB!) <= 6.0 ||
                        _distToSegment(effectivePoint, d.pointA!, d.pointB!) <= 6.0) {
                      bestDim = d;
                      break;
                    }
                  }
                }
                if (bestDim != null) {
                  selectDimension(bestDim.id);
                } else {
                  if (!multiSelect) {
                    clearSelection();
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  CadAnchorType _mapSnapTypeToAnchorType(SnapType? snapType) {
    if (snapType == null) return CadAnchorType.endpoint;
    switch (snapType) {
      case SnapType.center:
      case SnapType.punchCenter:
        return CadAnchorType.center;
      case SnapType.midpoint:
      case SnapType.edgeMidpoint:
        return CadAnchorType.midpoint;
      case SnapType.quadrant:
        return CadAnchorType.quadrant;
      case SnapType.perpendicular:
        return CadAnchorType.perpendicular;
      case SnapType.tangent:
      case SnapType.endpoint:
      case SnapType.cornerVertex:
      case SnapType.bendEndpoint:
      case SnapType.junctionDot:
      case SnapType.intersection:
      case SnapType.edgeIntersection:
      case SnapType.nearest:
      case SnapType.edgePoint:
      case SnapType.grid:
        return CadAnchorType.endpoint;
    }
  }

  String? _findNearestEdgeOrBendId(CadPoint2D pt, {double maxDistMm = 6.0}) {
    for (final bend in _document.bends) {
      if (_distToSegment(pt, bend.p1, bend.p2) <= maxDistMm) return bend.id;
    }
    for (final cut in _document.cutLines) {
      if (_distToSegment(pt, cut.p1, cut.p2) <= maxDistMm) return cut.id;
    }
    if (_document.outerContour.length >= 2) {
      for (int i = 0; i < _document.outerContour.length; i++) {
        final c1 = _document.outerContour[i];
        final c2 = _document.outerContour[(i + 1) % _document.outerContour.length];
        if (_distToSegment(pt, c1, c2) <= maxDistMm) return 'CONTOUR_EDGE_$i';
      }
    }
    return null;
  }

  (CadPoint2D, CadPoint2D)? _resolveEdgeSegment(String? edgeId) {
    if (edgeId == null) return null;
    for (final cut in _document.cutLines) {
      if (cut.id == edgeId) return (cut.p1, cut.p2);
    }
    for (final bend in _document.bends) {
      if (bend.id == edgeId) return (bend.p1, bend.p2);
    }
    if (edgeId.startsWith('CONTOUR_EDGE_')) {
      final idxStr = edgeId.replaceFirst('CONTOUR_EDGE_', '');
      final idx = int.tryParse(idxStr);
      if (idx != null && _document.outerContour.length >= 2 && idx < _document.outerContour.length) {
        final c1 = _document.outerContour[idx];
        final c2 = _document.outerContour[(idx + 1) % _document.outerContour.length];
        return (c1, c2);
      }
    }
    return null;
  }

  CadPoint2D _projectPointToSegmentLine(CadPoint2D p, CadPoint2D e1, CadPoint2D e2) {
    final dx = e2.x - e1.x;
    final dy = e2.y - e1.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return e1;
    final t = ((p.x - e1.x) * dx + (p.y - e1.y) * dy) / lenSq;
    return CadPoint2D(e1.x + t * dx, e1.y + t * dy);
  }

  void selectPunch(String? punchId, {bool multiSelect = false}) {
    if (multiSelect && punchId != null) {
      toggleEntitySelection(punchId);
      return;
    }
    _selectedPunchId = punchId;
    _selectedEntityIds.clear();
    if (punchId != null) {
      _selectedEntityIds.add(punchId);
      _selectedBendId = null;
      _selectedCutId = null;
      _selectedPatternId = null;
      _selectedPatternHoleIndex = null;
      _selectedArcId = null;
      _selectedFaceId = null;
      _selectedDimensionId = null;
      selectConstraintId(null);
    }
    notifyListeners();
  }

  void selectPattern(String? patternId, [int? holeIndex, bool multiSelect = false]) {
    if (multiSelect && patternId != null) {
      toggleEntitySelection(patternId);
      return;
    }
    _selectedPatternId = patternId;
    _selectedPatternHoleIndex = holeIndex;
    _selectedEntityIds.clear();
    if (patternId != null) {
      _selectedEntityIds.add(patternId);
      _selectedPunchId = null;
      _selectedBendId = null;
      _selectedCutId = null;
      _selectedFaceId = null;
      _selectedArcId = null;
      _selectedDimensionId = null;
      selectConstraintId(null);
    }
    notifyListeners();
  }

  void selectBend(String? bendId, {bool multiSelect = false}) {
    if (multiSelect && bendId != null) {
      toggleEntitySelection(bendId);
      return;
    }
    _selectedBendId = bendId;
    _selectedEntityIds.clear();
    if (bendId != null) {
      _selectedEntityIds.add(bendId);
      _selectedPunchId = null;
      _selectedCutId = null;
      _selectedPatternId = null;
      _selectedPatternHoleIndex = null;
      _selectedArcId = null;
      _selectedFaceId = null;
      _selectedDimensionId = null;
      selectConstraintId(null);
    }
    notifyListeners();
  }

  void selectCut(String? cutId, {bool multiSelect = false}) {
    if (multiSelect && cutId != null) {
      toggleEntitySelection(cutId);
      return;
    }
    _selectedCutId = cutId;
    _selectedEntityIds.clear();
    if (cutId != null) {
      _selectedEntityIds.add(cutId);
      _selectedBendId = null;
      _selectedPunchId = null;
      _selectedPatternId = null;
      _selectedPatternHoleIndex = null;
      _selectedArcId = null;
      _selectedFaceId = null;
      _selectedDimensionId = null;
      selectConstraintId(null);
    }
    notifyListeners();
  }

  void selectFace(String? faceId, {bool multiSelect = false}) {
    if (multiSelect && faceId != null) {
      toggleEntitySelection(faceId);
      return;
    }
    _selectedFaceId = faceId;
    _selectedEntityIds.clear();
    if (faceId != null) {
      _selectedEntityIds.add(faceId);
      _selectedBendId = null;
      _selectedCutId = null;
      _selectedPunchId = null;
      _selectedPatternId = null;
      _selectedPatternHoleIndex = null;
      _selectedArcId = null;
      _selectedDimensionId = null;
      selectConstraintId(null);
    }
    notifyListeners();
  }

  /// Toggles an individual entity in the current selection (used for Shift+Click multi-selection).
  void toggleEntitySelection(String id) {
    final current = Set<String>.from(_selectedEntityIds);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    selectEntities(current);
  }

  /// Sets multi-selection from a collection of entity IDs (from Window/Crossing selection).
  void selectEntities(Iterable<String> ids) {
    _selectedEntityIds.clear();

    _selectedEntityIds.addAll(ids);

    if (_selectedEntityIds.isEmpty) {
      _selectedBendId = null;
      _selectedCutId = null;
      _selectedPunchId = null;
      _selectedPatternId = null;
      _selectedPatternHoleIndex = null;
      _selectedFaceId = null;
      _selectedArcId = null;
    } else if (_selectedEntityIds.length == 1) {
      final singleId = _selectedEntityIds.first;

      if (_document.bends.any((b) => b.id == singleId)) {
        _selectedBendId = singleId;
        _selectedCutId = null;
        _selectedPunchId = null;
        _selectedPatternId = null;
        _selectedArcId = null;
        _selectedFaceId = null;
      } else if (_document.cutLines.any((c) => c.id == singleId)) {
        _selectedCutId = singleId;
        _selectedBendId = null;
        _selectedPunchId = null;
        _selectedPatternId = null;
        _selectedArcId = null;
        _selectedFaceId = null;
      } else if (_document.punches.any((p) => p.id == singleId)) {
        _selectedPunchId = singleId;
        _selectedBendId = null;
        _selectedCutId = null;
        _selectedPatternId = null;
        _selectedArcId = null;
        _selectedFaceId = null;
      } else if (_document.perforationPatterns.any((p) => p.id == singleId)) {
        _selectedPatternId = singleId;
        _selectedBendId = null;
        _selectedCutId = null;
        _selectedPunchId = null;
        _selectedArcId = null;
        _selectedFaceId = null;
      } else if (_document.arcs.any((a) => a.id == singleId)) {
        _selectedArcId = singleId;
        _selectedBendId = null;
        _selectedCutId = null;
        _selectedPunchId = null;
        _selectedPatternId = null;
        _selectedFaceId = null;
      } else if (_document.faces.any((f) => f.id == singleId)) {
        _selectedFaceId = singleId;
        _selectedBendId = null;
        _selectedCutId = null;
        _selectedPunchId = null;
        _selectedPatternId = null;
        _selectedArcId = null;
      }
    } else {
      // Multiple entities selected
      _selectedBendId = null;
      _selectedCutId = null;
      _selectedPunchId = null;
      _selectedPatternId = null;
      _selectedPatternHoleIndex = null;
      _selectedFaceId = null;
      _selectedArcId = null;
    }

    notifyListeners();
  }

  /// Updates snapping engine configuration options.

  void updateSnapSettings(SnapEngineSettings settings) {
    _snapSettings = settings;

    notifyListeners();
  }

  /// Toggles an individual snap mode.

  void toggleSnapSetting(SnapType type) {
    switch (type) {
      case SnapType.endpoint:
      case SnapType.cornerVertex:
      case SnapType.bendEndpoint:
        _snapSettings = _snapSettings.copyWith(enableEndpoint: !_snapSettings.enableEndpoint);

        break;

      case SnapType.midpoint:
      case SnapType.edgeMidpoint:
        _snapSettings = _snapSettings.copyWith(enableMidpoint: !_snapSettings.enableMidpoint);

        break;

      case SnapType.center:
      case SnapType.punchCenter:
        _snapSettings = _snapSettings.copyWith(enableCenter: !_snapSettings.enableCenter);

        break;

      case SnapType.intersection:
      case SnapType.junctionDot:
      case SnapType.edgeIntersection:
        _snapSettings = _snapSettings.copyWith(enableIntersection: !_snapSettings.enableIntersection);

        break;

      case SnapType.perpendicular:
        _snapSettings = _snapSettings.copyWith(enablePerpendicular: !_snapSettings.enablePerpendicular);

        break;

      case SnapType.tangent:
        _snapSettings = _snapSettings.copyWith(enableTangent: !_snapSettings.enableTangent);

        break;

      case SnapType.nearest:
      case SnapType.edgePoint:
        _snapSettings = _snapSettings.copyWith(enableNearest: !_snapSettings.enableNearest);

        break;

      case SnapType.quadrant:
        _snapSettings = _snapSettings.copyWith(enableQuadrant: !_snapSettings.enableQuadrant);

        break;

      case SnapType.grid:
        _snapSettings = _snapSettings.copyWith(enableGrid: !_snapSettings.enableGrid);

        break;
    }

    notifyListeners();
  }

  void toggleGridSnap() {
    _snapSettings = _snapSettings.copyWith(enableGrid: !_snapSettings.enableGrid);

    notifyListeners();
  }

  void toggleOrthoTracking() {
    _snapSettings = _snapSettings.copyWith(enableOrthoTracking: !_snapSettings.enableOrthoTracking);

    notifyListeners();
  }

  /// Clears selection of all entities and cancels pending rubber-band operations.

  void deselectAll() {
    _selectedBendId = null;

    _selectedCutId = null;

    _selectedPunchId = null;

    _selectedFaceId = null;

    _selectedPatternId = null;

    _selectedPatternHoleIndex = null;

    _selectedDimensionId = null;

    _selectedArcId = null;

    selectConstraintId(null);

    _selectedEntityIds.clear();

    _pendingBendStart = null;

    _rubberBandEndpoint = null;

    _pendingDimensionEntityAId = null;

    _pendingDimensionAnchorTypeA = null;

    _pendingMultiPoints.clear();

    _previewPerforationPattern = null;

    _previewCouplerPunches = null;

    notifyListeners();
  }

  /// Selects all drawing entities (punches, cuts, bends, arcs, patterns, dimensions).
  void selectAll() {
    _selectedEntityIds.clear();
    for (final p in _document.punches) {
      _selectedEntityIds.add(p.id);
    }
    for (final c in _document.cutLines) {
      _selectedEntityIds.add(c.id);
    }
    for (final b in _document.bends) {
      _selectedEntityIds.add(b.id);
    }
    for (final a in _document.arcs) {
      _selectedEntityIds.add(a.id);
    }
    for (final pat in _document.perforationPatterns) {
      _selectedEntityIds.add(pat.id);
    }
    for (final d in _document.dimensions) {
      _selectedEntityIds.add(d.id);
    }
    notifyListeners();
  }

  /// Clears all drawing entities (cuts, bends, punches, arcs, patterns, dimensions)
  /// and resets the document to a clean blank sheet so the user can start fresh.
  void clearAllDrawingEntities({bool resetToBlank = true}) {
    deselectAll();
    _selectedEntityIds.clear();
    _recordHistory('Clear All Drawing Entities');

    List<CadPoint2D> newContour = [];
    List<PlanarSheetFace> newFaces = [];
    if (resetToBlank) {
      final w = _document.blankWidthMm > 0 ? _document.blankWidthMm : 500.0;
      final l = _document.blankLengthMm > 0 ? _document.blankLengthMm : 500.0;
      newContour = [const CadPoint2D(0, 0), CadPoint2D(w, 0), CadPoint2D(w, l), CadPoint2D(0, l)];
      newFaces = [PlanarSheetFace(id: 'FACE_ROOT', vertices: List.from(newContour), isBaseAnchor: true, role: FaceRole.baseFloor)];
    } else {
      newContour = List.from(_document.outerContour);
      newFaces = List.from(_document.faces);
    }

    _document = _document.copyWith(
      cutLines: const [],
      bends: const [],
      arcs: const [],
      punches: const [],
      perforationPatterns: const [],
      dimensions: const [],
      constraints: const [],
      outerContour: newContour,
      faces: newFaces,
      baseFaceId: resetToBlank ? 'FACE_ROOT' : _document.baseFaceId,
    );

    _recomputeMesh();
    _isModified = true;
    notifyListeners();
  }

  /// Updates the size dimensions of an existing punch primitive.
  void updatePunchSize(String punchId, {double? widthMm, double? lengthMm, double? diameterMm}) {
    final idx = _document.allPunchesRaw.indexWhere((p) => p.id == punchId);
    if (idx < 0) return;
    final p = _document.allPunchesRaw[idx];
    final updated = p.copyWith(widthMm: widthMm ?? p.widthMm, lengthMm: lengthMm ?? p.lengthMm, diameterMm: diameterMm ?? p.diameterMm);
    updatePunch(updated);
  }

  /// Cycles selection through overlapping items (punches, bends, cuts) near clicked position on double-click.

  void cycleSelectionAt(CadPoint2D pt, {double hitDistMm = 12.0}) {
    final candidatePunchIds = <String>[];

    for (final p in _document.punches) {
      final rad = math.max(p.diameterMm, math.max(p.widthMm, p.lengthMm)) / 2.0;

      if (p.center.distanceTo(pt) <= (rad + hitDistMm)) {
        candidatePunchIds.add(p.id);
      }
    }

    final candidateBendIds = <String>[];

    for (final b in _document.bends) {
      if (_distToSegment(pt, b.p1, b.p2) <= hitDistMm) {
        candidateBendIds.add(b.id);
      }
    }

    final candidateCutIds = <String>[];

    for (final c in _document.cutLines) {
      if (_distToSegment(pt, c.p1, c.p2) <= hitDistMm) {
        candidateCutIds.add(c.id);
      }
    }

    final allCandidates = <({String id, String type})>[
      ...candidatePunchIds.map((id) => (id: id, type: 'PUNCH')),

      ...candidateBendIds.map((id) => (id: id, type: 'BEND')),

      ...candidateCutIds.map((id) => (id: id, type: 'CUT')),
    ];

    if (allCandidates.isEmpty) return;

    int currentIndex = -1;

    for (int i = 0; i < allCandidates.length; i++) {
      final cand = allCandidates[i];

      if (cand.type == 'PUNCH' && cand.id == _selectedPunchId) currentIndex = i;

      if (cand.type == 'BEND' && cand.id == _selectedBendId) currentIndex = i;

      if (cand.type == 'CUT' && cand.id == _selectedCutId) currentIndex = i;
    }

    final nextIndex = (currentIndex + 1) % allCandidates.length;

    final nextCand = allCandidates[nextIndex];

    if (nextCand.type == 'PUNCH') {
      selectPunch(nextCand.id);
    } else if (nextCand.type == 'BEND') {
      selectBend(nextCand.id);
    } else if (nextCand.type == 'CUT') {
      selectCut(nextCand.id);
    }
  }

  /// Stamps a repeating cable tray perforation pattern (staggered or straight) across the sheet metal.

  void applyPerforationPattern({
    required CadPoint2D center,

    required int countX,

    required int countY,

    required double pitchX,

    required double pitchY,

    required double slotWidth,

    required double slotHeight,

    required bool staggered,

    double rotationDeg = 0.0,

    PunchType holeType = PunchType.obroundSlot,

    double diameterMm = 8.0,

    String? targetFaceId,
  }) {
    if (countX <= 0 || countY <= 0) return;

    _recordHistory();

    final patternId = 'PAT_${_document.perforationPatterns.length + 1}';

    final pattern = PerforationPattern(
      id: patternId,

      anchor: center,

      holeType: holeType,

      slotWidthMm: slotHeight,

      slotLengthMm: slotWidth,

      diameterMm: diameterMm,

      countX: countX,

      countY: countY,

      pitchX: pitchX,

      pitchY: pitchY,

      staggered: staggered,

      rotationDeg: rotationDeg,

      targetFaceId: targetFaceId,
    );

    _document = _document.copyWith(perforationPatterns: [..._document.perforationPatterns, pattern]);

    if (_templateBaselineDoc != null) {
      _templateBaselineDoc = _templateBaselineDoc!.copyWith(perforationPatterns: [..._templateBaselineDoc!.perforationPatterns, pattern]);
    }

    if (_templateBaselineDoc != null) {
      _templateBaselineDoc = _templateBaselineDoc!.copyWith(perforationPatterns: [..._templateBaselineDoc!.perforationPatterns, pattern]);
    }

    _selectedPatternId = patternId;

    _selectedPatternHoleIndex = null;

    _recomputeMesh();

    notifyListeners();
  }

  /// Staggered perforation pattern automatically centered on the base floor of the cable tray.

  void applyPerforationToActiveFloor() {
    PlanarSheetFace? baseFloor;

    for (final face in _document.faces) {
      if (face.role == FaceRole.baseFloor) {
        baseFloor = face;

        break;
      }
    }

    baseFloor ??= _document.faces.isNotEmpty ? _document.faces.first : null;

    if (baseFloor == null || baseFloor.vertices.isEmpty) return;

    double sx = 0, sy = 0;

    for (final v in baseFloor.vertices) {
      sx += v.x;

      sy += v.y;
    }

    final center = CadPoint2D(sx / baseFloor.vertices.length, sy / baseFloor.vertices.length);

    applyPerforationPattern(
      center: center,

      countX: toolConfig.patternColsX,

      countY: toolConfig.patternRowsY,

      pitchX: toolConfig.patternPitchX,

      pitchY: toolConfig.patternPitchY,

      slotWidth: toolConfig.patternSlotWidth,

      slotHeight: toolConfig.patternSlotHeight,

      staggered: toolConfig.patternStaggered,
    );
  }

  /// Auto-nests a unified perforation pattern onto any specified or selected planar surface.

  /// Applies CMS standard modular rules (30x7 obround, 80mm pitch, 25mm stagger, auto width pitch).

  void autoNestPerforationOnFace({
    String? faceId,

    PunchType holeType = PunchType.obroundSlot,

    double slotWidth = 7.0,

    double slotLength = 30.0,

    double diameterMm = 8.0,

    double pitchY = 80.0,

    double staggerDistance = 25.0,

    double endMargin = 50.0,

    double? rotationDeg,

    bool staggered = true,

    int? overrideCols,

    double? overridePitchX,
  }) {
    // 1. Locate target face

    PlanarSheetFace? targetFace;

    final fid = faceId ?? _selectedFaceId;

    if (fid != null) {
      targetFace = _document.faces.cast<PlanarSheetFace?>().firstWhere((f) => f?.id == fid, orElse: () => null);
    }

    targetFace ??= _document.faces.cast<PlanarSheetFace?>().firstWhere((f) => f?.role == FaceRole.baseFloor, orElse: () => null);

    targetFace ??= _document.faces.isNotEmpty ? _document.faces.first : null;

    if (targetFace == null || targetFace.vertices.isEmpty) return;

    _recordHistory();

    final pattern = CncTurretEngine.autoNestPerforationOnFace(
      face: targetFace,

      doc: _document,

      holeType: holeType,

      slotWidth: slotWidth,

      slotLength: slotLength,

      diameterMm: diameterMm,

      pitchY: pitchY,

      staggerDistance: staggerDistance,

      endMargin: endMargin,

      rotationDeg: rotationDeg,

      staggered: staggered,

      overrideCols: overrideCols,

      overridePitchX: overridePitchX,

      patternId: 'PAT_${targetFace.id}_${_document.perforationPatterns.length + 1}',
    );

    _document = _document.copyWith(perforationPatterns: [..._document.perforationPatterns, pattern]);

    _selectedPatternId = pattern.id;

    _selectedPatternHoleIndex = null;

    _recomputeMesh();

    notifyListeners();
  }

  /// Nudges currently selected CAD entity (punch, pattern, bend, cut) by (dx, dy) mm.

  void nudgeSelected(double dx, double dy) {
    if (_selectedPunchId != null) {
      final punch = _document.punches.cast<CncPunchPrimitive?>().firstWhere((p) => p?.id == _selectedPunchId, orElse: () => null);

      if (punch != null) {
        // Fixed constraint guard for keyboard nudge
        final isFixed = _document.constraints.any((c) => c.type == CadConstraintType.fixed && c.entityIds.contains(punch.id));
        if (isFixed) return;

        _recordHistory();
        final newCenter = CadPoint2D(punch.center.x + dx, punch.center.y + dy);
        var newPunches = _document.punches.map((p) => p.id == _selectedPunchId ? p.moveTo(newCenter) : p).toList();
        _document = _document.copyWith(punches: newPunches);
        if (_document.constraints.isNotEmpty) {
          final res = GeometricConstraintSolver.solve(document: _document, customReferences: allReferenceGeometries);
          if (res.success) _document = res.updatedDocument;
        }
        _recomputeMesh();
        notifyListeners();
      }
    } else if (_selectedPatternId != null) {
      final pattern = _document.perforationPatterns.cast<PerforationPattern?>().firstWhere((p) => p?.id == _selectedPatternId, orElse: () => null);

      if (pattern != null) {
        _recordHistory();

        final newAnchor = CadPoint2D(pattern.anchor.x + dx, pattern.anchor.y + dy);

        final newPatterns = _document.perforationPatterns.map((p) => p.id == _selectedPatternId ? p.copyWith(anchor: newAnchor) : p).toList();

        _document = _document.copyWith(perforationPatterns: newPatterns);

        _recomputeMesh();

        notifyListeners();
      }
    } else if (_selectedBendId != null) {
      final bend = _document.bends.cast<FoldBendLine?>().firstWhere((b) => b?.id == _selectedBendId, orElse: () => null);

      if (bend != null) {
        _recordHistory();

        final newBends = _document.bends.map((b) {
          if (b.id != _selectedBendId) return b;

          return b.copyWith(p1: CadPoint2D(b.p1.x + dx, b.p1.y + dy), p2: CadPoint2D(b.p2.x + dx, b.p2.y + dy));
        }).toList();

        final decomp = PlanarFaceDecomposer.decompose(
          outerContour: _document.outerContour,

          bends: newBends,

          cutLines: _document.cutLines,

          preferredBaseFaceId: _document.baseFaceId,
        );

        _document = _document.copyWith(bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

        _recomputeMesh();

        notifyListeners();
      }
    } else if (_selectedCutId != null) {
      final cut = _document.cutLines.cast<CadLineSegment?>().firstWhere((c) => c?.id == _selectedCutId, orElse: () => null);

      if (cut != null) {
        _recordHistory();

        final newCuts = _document.cutLines.map((c) {
          if (c.id != _selectedCutId) return c;

          return c.copyWith(p1: CadPoint2D(c.p1.x + dx, c.p1.y + dy), p2: CadPoint2D(c.p2.x + dx, c.p2.y + dy));
        }).toList();

        final decomp = PlanarFaceDecomposer.decompose(
          outerContour: _document.outerContour,

          bends: _document.bends,

          cutLines: newCuts,

          preferredBaseFaceId: _document.baseFaceId,
        );

        _document = _document.copyWith(cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

        _recomputeMesh();

        notifyListeners();
      }
    } else if (_selectedArcId != null) {
      final arc = _document.arcs.cast<CadArc2D?>().firstWhere((a) => a?.id == _selectedArcId, orElse: () => null);
      if (arc != null) {
        _recordHistory();
        final newCenter = CadPoint2D(arc.center.x + dx, arc.center.y + dy);
        final newStart = CadPoint2D(arc.startPoint.x + dx, arc.startPoint.y + dy);
        final newEnd = CadPoint2D(arc.endPoint.x + dx, arc.endPoint.y + dy);
        final newArcs = _document.arcs.map((a) => a.id == _selectedArcId ? a.copyWith(center: newCenter, startPoint: newStart, endPoint: newEnd) : a).toList();
        _document = _document.copyWith(arcs: newArcs);
        _recomputeMesh();
        notifyListeners();
      }
    }
  }

  // --- Material & Physical Properties ---

  void setMaterialType(SheetMaterialType type) {
    _recordHistory();

    String gradeName = 'Mild Steel (CR4)';

    double defaultK = 0.38;

    switch (type) {
      case SheetMaterialType.mildSteel:
        gradeName = 'Mild Steel (CR4)';

        defaultK = 0.38;

        break;

      case SheetMaterialType.stainlessSteel:
        gradeName = 'Stainless Steel (SS 304)';

        defaultK = 0.44;

        break;

      case SheetMaterialType.aluminium:
        gradeName = 'Aluminium (AL 5052)';

        defaultK = 0.41;

        break;
    }

    _document = _document.copyWith(
      material: _document.material.copyWith(materialType: type, materialGrade: gradeName, kFactor: defaultK),
    );

    _recomputeMesh();

    notifyListeners();
  }

  void setMaterialGrade(String grade) {
    _recordHistory();

    _document = _document.copyWith(material: _document.material.copyWith(materialGrade: grade));

    notifyListeners();
  }

  void setMaterialDefinition({required SheetMetalMaterialGrade grade, required CoatingFinish finish}) {
    _recordHistory();

    SheetMaterialType type = SheetMaterialType.mildSteel;

    if (grade == SheetMetalMaterialGrade.ss304 || grade == SheetMetalMaterialGrade.ss316) {
      type = SheetMaterialType.stainlessSteel;
    } else if (grade == SheetMetalMaterialGrade.aluminium) {
      type = SheetMaterialType.aluminium;
    }

    SurfaceFinish surfaceFinish = SurfaceFinish.bare;

    switch (finish) {
      case CoatingFinish.eg:
        surfaceFinish = SurfaceFinish.electroGalvanized;

        break;

      case CoatingFinish.hdg:
      case CoatingFinish.twoHdg:
      case CoatingFinish.threeHdg:
        surfaceFinish = SurfaceFinish.hotDipGalvanized;

        break;

      case CoatingFinish.pc:
      case CoatingFinish.twoPc:
      case CoatingFinish.threePc:
        surfaceFinish = SurfaceFinish.powderCoated;

        break;

      case CoatingFinish.ex:
      case CoatingFinish.twoEx:
      case CoatingFinish.threeEx:
        surfaceFinish = SurfaceFinish.epoxyCoated;

        break;

      case CoatingFinish.none:
        surfaceFinish = SurfaceFinish.bare;

        break;
    }

    _document = _document.copyWith(
      material: _document.material.copyWith(materialType: type, materialGrade: grade.code, kFactor: grade.defaultKFactor, finish: surfaceFinish),
    );

    _recomputeMesh();

    notifyListeners();
  }

  void setCoatingFinish(CoatingFinish finish) {
    _recordHistory();

    SurfaceFinish surfaceFinish = SurfaceFinish.bare;

    switch (finish) {
      case CoatingFinish.eg:
        surfaceFinish = SurfaceFinish.electroGalvanized;

        break;

      case CoatingFinish.hdg:
      case CoatingFinish.twoHdg:
      case CoatingFinish.threeHdg:
        surfaceFinish = SurfaceFinish.hotDipGalvanized;

        break;

      case CoatingFinish.pc:
      case CoatingFinish.twoPc:
      case CoatingFinish.threePc:
        surfaceFinish = SurfaceFinish.powderCoated;

        break;

      case CoatingFinish.ex:
      case CoatingFinish.twoEx:
      case CoatingFinish.threeEx:
        surfaceFinish = SurfaceFinish.epoxyCoated;

        break;

      case CoatingFinish.none:
        surfaceFinish = SurfaceFinish.bare;

        break;
    }

    _document = _document.copyWith(material: _document.material.copyWith(finish: surfaceFinish));

    notifyListeners();
  }

  // --- Perforation Pattern Management ---

  void addPerforationPattern(PerforationPattern pattern) {
    _recordHistory();

    _document = _document.copyWith(perforationPatterns: [..._document.perforationPatterns, pattern]);

    _selectedPatternId = pattern.id;

    _selectedPatternHoleIndex = null;

    _recomputeMesh();

    notifyListeners();
  }

  void deletePattern(String patternId) {
    _recordHistory();

    final patToRemove = _document.perforationPatterns.cast<PerforationPattern?>().firstWhere((p) => p?.id == patternId, orElse: () => null);

    final remaining = _document.perforationPatterns.where((p) => p.id != patternId).toList();

    // If any legacy holes were baked into face.holes from this pattern, purge them

    var updatedFaces = _document.faces;

    if (patToRemove != null) {
      final patPunches = patToRemove.expandToPunches();

      final patHoleCenters = patPunches.map((p) => p.center).toList();

      if (patHoleCenters.isNotEmpty) {
        updatedFaces = _document.faces.map((f) {
          if (patToRemove.targetFaceId == null || f.id == patToRemove.targetFaceId) {
            final cleanHoles = f.holes.where((loop) {
              if (loop.isEmpty) return false;

              double sx = 0, sy = 0;

              for (final pt in loop) {
                sx += pt.x;

                sy += pt.y;
              }

              final center = CadPoint2D(sx / loop.length, sy / loop.length);

              return !patHoleCenters.any((pc) => pc.distanceTo(center) < 2.0);
            }).toList();

            return f.copyWith(holes: cleanHoles);
          }

          return f;
        }).toList();
      }
    }

    _document = _document.copyWith(perforationPatterns: remaining, faces: updatedFaces);

    if (_selectedPatternId == patternId) {
      _selectedPatternId = null;

      _selectedPatternHoleIndex = null;
    }

    _recomputeMesh();

    notifyListeners();
  }

  void deleteSelectedPattern() {
    if (_selectedPatternId == null) return;

    deletePattern(_selectedPatternId!);
  }

  void deletePatternHole(String patternId, int holeIndex) {
    final pattern = _document.perforationPatterns.cast<PerforationPattern?>().firstWhere((p) => p?.id == patternId, orElse: () => null);

    if (pattern == null) return;

    _recordHistory();

    final updatedSet = Set<int>.from(pattern.deletedHoleIndices)..add(holeIndex);

    final updatedPattern = pattern.copyWith(deletedHoleIndices: updatedSet);

    final newPatterns = _document.perforationPatterns.map((p) => p.id == patternId ? updatedPattern : p).toList();

    _document = _document.copyWith(perforationPatterns: newPatterns);

    _recomputeMesh();

    notifyListeners();
  }

  void movePattern(String patternId, CadPoint2D newAnchor) {
    final newPatterns = _document.perforationPatterns.map((p) => p.id == patternId ? p.copyWith(anchor: newAnchor) : p).toList();

    _document = _document.copyWith(perforationPatterns: newPatterns);

    _recomputeMesh();

    notifyListeners();
  }

  void rotatePattern(String patternId, double angleDeg) {
    _recordHistory();

    final newPatterns = _document.perforationPatterns.map((p) => p.id == patternId ? p.copyWith(rotationDeg: angleDeg) : p).toList();

    _document = _document.copyWith(perforationPatterns: newPatterns);

    _recomputeMesh();

    notifyListeners();
  }

  // --- Press Brake Machine & CAM Rules ---

  void setSelectedMachine(PressBrakeMachine machine) {
    _selectedMachine = machine;

    notifyListeners();
  }

  void setBendSequence(List<String> sequence) {
    _bendSequence = sequence;

    notifyListeners();
  }

  void autoSequenceBends() {
    _recordHistory();

    _bendSequence = BendSequenceEngine.autoSequence(doc: _document, machine: _selectedMachine);

    notifyListeners();
  }

  void autoGenerateBendSequence() => autoSequenceBends();

  void toggleStepMode() {
    _isStepMode = !_isStepMode;

    if (_isStepMode) {
      _currentBendStep = 1;

      if (_document.bends.isNotEmpty) {
        setFoldProgress(1.0 / _document.bends.length);
      }
    }

    notifyListeners();
  }

  void setBendStep(int step) {
    if (_document.bends.isEmpty) return;

    _currentBendStep = step.clamp(1, _document.bends.length);

    setFoldProgress(_currentBendStep / _document.bends.length);

    notifyListeners();
  }

  // --- Dimensional Label Toggles ---

  void toggleFaceLabel(String faceId) {
    _recordHistory();

    final updated = _document.faces.map((f) {
      if (f.id != faceId) return f;

      return f.copyWith(showLabel: !f.showLabel);
    }).toList();

    _document = _document.copyWith(faces: updated);

    notifyListeners();
  }

  void toggleBendLabel(String bendId) {
    _recordHistory();

    final updated = _document.bends.map((b) {
      if (b.id != bendId) return b;

      return b.copyWith(showLabel: !b.showLabel);
    }).toList();

    _document = _document.copyWith(bends: updated);

    notifyListeners();
  }

  void togglePunchLabel(String punchId) {
    _recordHistory();

    final updated = _document.punches.map((p) {
      if (p.id != punchId) return p;

      return p.copyWith(showLabel: !p.showLabel);
    }).toList();

    _document = _document.copyWith(punches: updated);

    notifyListeners();
  }

  void togglePatternLabel(String patternId) {
    _recordHistory();

    final updated = _document.perforationPatterns.map((p) {
      if (p.id != patternId) return p;

      return p.copyWith(showLabel: !p.showLabel);
    }).toList();

    _document = _document.copyWith(perforationPatterns: updated);

    notifyListeners();
  }

  void toggleCutLabel(String cutId) {
    _recordHistory();
    final updated = _document.cutLines.map((c) {
      if (c.id != cutId) return c;
      return c.copyWith(showLabel: !c.showLabel);
    }).toList();
    _document = _document.copyWith(cutLines: updated);
    notifyListeners();
  }

  void toggleArcLabel(String arcId) {
    _recordHistory();
    final updated = _document.arcs.map((a) {
      if (a.id != arcId) return a;
      return a.copyWith(showLabel: !a.showLabel);
    }).toList();
    _document = _document.copyWith(arcs: updated);
    notifyListeners();
  }

  // --- Visibility / Suppression Toggles (Temporary Delete) ---

  void toggleFaceVisibility(String faceId) {
    _recordHistory();

    final updated = _document.faces.map((f) {
      if (f.id != faceId) return f;

      return f.copyWith(isVisible: !f.isVisible);
    }).toList();

    _document = _document.copyWith(faces: updated);

    _recomputeMesh();

    notifyListeners();
  }

  void toggleBendVisibility(String bendId) {
    _recordHistory();

    final updated = _document.bends.map((b) {
      if (b.id != bendId) return b;

      return b.copyWith(isVisible: !b.isVisible);
    }).toList();

    _document = _document.copyWith(bends: updated);

    _recomputeMesh();

    notifyListeners();
  }

  void togglePunchVisibility(String punchId) {
    _recordHistory();

    final updated = _document.punches.map((p) {
      if (p.id != punchId) return p;

      return p.copyWith(isVisible: !p.isVisible);
    }).toList();

    _document = _document.copyWith(punches: updated);

    _recomputeMesh();

    notifyListeners();
  }

  void togglePatternVisibility(String patternId) {
    _recordHistory();

    final updated = _document.perforationPatterns.map((p) {
      if (p.id != patternId) return p;

      return p.copyWith(isVisible: !p.isVisible);
    }).toList();

    _document = _document.copyWith(perforationPatterns: updated);

    if (_templateBaselineDoc != null) {
      _templateBaselineDoc = _templateBaselineDoc!.copyWith(perforationPatterns: updated);
    }

    _recomputeMesh();

    notifyListeners();
  }

  /// Updates an existing perforation pattern parametrically live.

  void updatePatternParameters(
    String patternId, {

    PunchType? holeType,

    double? slotWidthMm,

    double? slotLengthMm,

    double? diameterMm,

    int? countX,

    int? countY,

    double? pitchX,

    double? pitchY,

    bool? staggered,

    double? staggerDistanceMm,

    bool? staggerAlongY,

    double? rotationDeg,

    double? gridRotationDeg,

    bool? isVisible,

    bool? showLabel,
  }) {
    _recordHistory();

    final updated = _document.perforationPatterns.map((p) {
      if (p.id != patternId) return p;

      return p.copyWith(
        holeType: holeType,

        slotWidthMm: slotWidthMm,

        slotLengthMm: slotLengthMm,

        diameterMm: diameterMm,

        countX: countX,

        countY: countY,

        pitchX: pitchX,

        pitchY: pitchY,

        staggered: staggered,

        staggerDistanceMm: staggerDistanceMm,

        staggerAlongY: staggerAlongY,

        rotationDeg: rotationDeg,

        gridRotationDeg: gridRotationDeg,

        isVisible: isVisible,

        showLabel: showLabel,
      );
    }).toList();

    _document = _document.copyWith(perforationPatterns: updated);

    if (_templateBaselineDoc != null) {
      _templateBaselineDoc = _templateBaselineDoc!.copyWith(perforationPatterns: updated);
    }

    _recomputeMesh();

    notifyListeners();
  }

  /// Replaces an existing pattern with an updated/draft pattern, recomputes mesh, and notifies listeners.

  void replacePattern(PerforationPattern pattern) {
    _recordHistory();

    final updated = _document.perforationPatterns.map((p) {
      if (p.id != pattern.id) return p;

      return pattern;
    }).toList();

    _document = _document.copyWith(perforationPatterns: updated);

    if (_templateBaselineDoc != null) {
      _templateBaselineDoc = _templateBaselineDoc!.copyWith(perforationPatterns: updated);
    }

    if (_templateBaselineDoc != null) {
      _templateBaselineDoc = _templateBaselineDoc!.copyWith(perforationPatterns: updated);
    }

    _recomputeMesh();

    notifyListeners();
  }

  /// Automatically re-nests an existing perforation pattern onto a newly selected planar face.

  void reNestPatternOnFace({required String patternId, required String newFaceId}) {
    final oldPattern = _document.perforationPatterns.cast<PerforationPattern?>().firstWhere((p) => p?.id == patternId, orElse: () => null);

    if (oldPattern == null) return;

    final targetFace = _document.faces.cast<PlanarSheetFace?>().firstWhere((f) => f?.id == newFaceId, orElse: () => null);

    if (targetFace == null || targetFace.vertices.length < 3) return;

    _recordHistory();

    final reNested = CncTurretEngine.autoNestPerforationOnFace(
      face: targetFace,

      doc: _document,

      holeType: oldPattern.holeType,

      slotWidth: oldPattern.slotWidthMm,

      slotLength: oldPattern.slotLengthMm,

      diameterMm: oldPattern.diameterMm,

      pitchY: oldPattern.pitchY,

      overridePitchX: oldPattern.pitchX,

      staggerDistance: oldPattern.staggerDistanceMm,

      endMargin: 50.0,

      rotationDeg: oldPattern.rotationDeg,

      staggered: oldPattern.staggered,

      patternId: oldPattern.id,
    );

    final updated = _document.perforationPatterns.map((p) {
      if (p.id != patternId) return p;

      return reNested.copyWith(isVisible: oldPattern.isVisible, showLabel: oldPattern.showLabel);
    }).toList();

    _document = _document.copyWith(perforationPatterns: updated);

    if (_templateBaselineDoc != null) {
      _templateBaselineDoc = _templateBaselineDoc!.copyWith(perforationPatterns: updated);
    }

    _recomputeMesh();

    notifyListeners();
  }

  /// Automatically re-nests all active perforation patterns to fit their target faces

  /// when the size of a surface (blank or face) is increased or decreased.

  void _renestPatternsForUpdatedFaces() {
    if (_document.perforationPatterns.isEmpty) return;

    final updatedPatterns = <PerforationPattern>[];

    bool changed = false;

    for (final pat in _document.perforationPatterns) {
      PlanarSheetFace? targetFace;

      if (pat.targetFaceId != null) {
        targetFace = _document.faces.cast<PlanarSheetFace?>().firstWhere((f) => f?.id == pat.targetFaceId, orElse: () => null);
      }

      targetFace ??= _document.faces.cast<PlanarSheetFace?>().firstWhere((f) => f?.role == FaceRole.baseFloor, orElse: () => null);

      targetFace ??= _document.faces.isNotEmpty ? _document.faces.first : null;

      if (targetFace != null && targetFace.vertices.length >= 3) {
        final reNested = CncTurretEngine.autoNestPerforationOnFace(
          face: targetFace,

          doc: _document,

          holeType: pat.holeType,

          slotWidth: pat.slotWidthMm,

          slotLength: pat.slotLengthMm,

          diameterMm: pat.diameterMm,

          pitchY: pat.pitchY,

          overridePitchX: pat.pitchX,

          staggerDistance: pat.staggerDistanceMm,

          endMargin: 50.0,

          rotationDeg: pat.rotationDeg,

          staggered: pat.staggered,

          patternId: pat.id,
        );

        updatedPatterns.add(reNested.copyWith(isVisible: pat.isVisible, showLabel: pat.showLabel));

        changed = true;
      } else {
        updatedPatterns.add(pat);
      }
    }

    if (changed) {
      _document = _document.copyWith(perforationPatterns: updatedPatterns);
    }
  }

  /// Public method to re-nest all perforation patterns when surface sizes change.

  void renestAllPatterns() {
    _recordHistory();

    _renestPatternsForUpdatedFaces();

    _recomputeMesh();

    notifyListeners();
  }

  void addPunch(CncPunchPrimitive punch) {
    _recordHistory();

    _document = _document.copyWith(punches: [..._document.punches, punch]);

    _selectedPunchId = punch.id;

    _selectedBendId = null;

    _selectedCutId = null;

    _recomputeMesh();

    notifyListeners();
  }

  void updatePunch(CncPunchPrimitive updated) {
    _recordHistory();

    final newPunches = _document.punches.map((p) => p.id == updated.id ? updated : p).toList();

    _document = _document.copyWith(punches: newPunches);

    _recomputeMesh();

    notifyListeners();
  }

  void deletePunch(String punchId) {
    _recordHistory();

    final remaining = _document.punches.where((p) => p.id != punchId).toList();

    _document = _document.copyWith(punches: remaining);

    if (_selectedPunchId == punchId) _selectedPunchId = null;

    _recomputeMesh();

    notifyListeners();
  }

  /// Live dragging of punch across sheet blank without flooding undo stack on every frame.

  void moveSelectedPunch(CadPoint2D newCenter) {
    if (_selectedPunchId == null) return;

    // Constraint guard: block movement if a 'fixed' constraint targets this punch.
    final hasFixedConstraint = _document.constraints.any((c) => c.type == CadConstraintType.fixed && c.entityIds.contains(_selectedPunchId));
    if (hasFixedConstraint) return;

    final newPunches = _document.punches.map((p) => p.id == _selectedPunchId ? p.moveTo(newCenter) : p).toList();

    _document = _document.copyWith(punches: newPunches);

    // Enforce geometric constraints after every drag step.
    if (_document.constraints.isNotEmpty) {
      final res = GeometricConstraintSolver.solve(document: _document, customReferences: allReferenceGeometries);
      if (res.success) _document = res.updatedDocument;
    }

    _recomputeMesh();
    notifyListeners();
  }

  /// Finds all punches that geometrically overlap with the specified punch.

  List<CncPunchPrimitive> findOverlappingPunches(String punchId) {
    final target = _document.punches.cast<CncPunchPrimitive?>().firstWhere((p) => p?.id == punchId, orElse: () => null);

    if (target == null) return [];

    final overlaps = <CncPunchPrimitive>[];

    final pathA = _polygonToPath(target.toPolygon());

    for (final other in _document.punches) {
      if (other.id == punchId) continue;

      final maxRadA = math.max(target.diameterMm, math.max(target.widthMm, target.lengthMm));

      final maxRadB = math.max(other.diameterMm, math.max(other.widthMm, other.lengthMm));

      if (target.center.distanceTo(other.center) > (maxRadA + maxRadB)) {
        continue;
      }

      final pathB = _polygonToPath(other.toPolygon());

      final intersect = Path.combine(PathOperation.intersect, pathA, pathB);

      if (intersect.computeMetrics().any((m) => m.length > 0.05)) {
        overlaps.add(other);
      }
    }

    return overlaps;
  }

  /// Merges the specified punch and all its overlapping punches into a single compound punch.

  bool mergeOverlappingPunches(String punchId) {
    final target = _document.punches.cast<CncPunchPrimitive?>().firstWhere((p) => p?.id == punchId, orElse: () => null);

    if (target == null) return false;

    final overlapping = findOverlappingPunches(punchId);

    if (overlapping.isEmpty) return false;

    _recordHistory();

    var unionPath = _polygonToPath(target.toPolygon());

    final idsToRemove = <String>{target.id};

    for (final other in overlapping) {
      idsToRemove.add(other.id);

      unionPath = Path.combine(PathOperation.union, unionPath, _polygonToPath(other.toPolygon()));
    }

    final mergedBoundary = _pathToPolygon(unionPath);

    if (mergedBoundary.length < 3) return false;

    // Calculate centroid

    double sx = 0, sy = 0;

    for (final pt in mergedBoundary) {
      sx += pt.x;

      sy += pt.y;
    }

    final centroid = CadPoint2D(sx / mergedBoundary.length, sy / mergedBoundary.length);

    final mergedPunch = CncPunchPrimitive(
      id: '${target.id}_MERGED',

      type: PunchType.compound,

      center: centroid,

      customBoundary: mergedBoundary,

      layer: target.layer,
    );

    final remainingPunches = _document.punches.where((p) => !idsToRemove.contains(p.id)).toList();

    _document = _document.copyWith(punches: [...remainingPunches, mergedPunch]);

    _selectedPunchId = mergedPunch.id;

    _recomputeMesh();

    notifyListeners();

    return true;
  }

  static Path _polygonToPath(List<CadPoint2D> poly) {
    final path = Path();

    if (poly.isEmpty) return path;

    path.moveTo(poly.first.x, poly.first.y);

    for (int i = 1; i < poly.length; i++) {
      path.lineTo(poly[i].x, poly[i].y);
    }

    path.close();

    return path;
  }

  static List<CadPoint2D> _pathToPolygon(Path path, {double sampleStepMm = 1.0}) {
    final pts = <CadPoint2D>[];

    for (final metric in path.computeMetrics()) {
      final len = metric.length;

      if (len < 0.2) continue;

      final count = (len / sampleStepMm).clamp(32.0, 120.0).toInt();

      for (int i = 0; i < count; i++) {
        final dist = (i / count) * len;

        final t = metric.getTangentForOffset(dist);

        if (t != null) {
          pts.add(CadPoint2D(t.position.dx, t.position.dy));
        }
      }

      break; // Outer boundary contour
    }

    return pts;
  }

  /// Live dragging of bend line across sheet blank.

  void moveSelectedBend(CadPoint2D deltaMm) {
    if (_selectedBendId == null) return;

    // Constraint guard: if the selected bend has a 'fixed' constraint, block all movement.
    final hasFixedConstraint = _document.constraints.any((c) => c.type == CadConstraintType.fixed && c.entityIds.contains(_selectedBendId));
    if (hasFixedConstraint) return;

    final newBends = _document.bends.map((b) {
      if (b.id != _selectedBendId) return b;
      return b.copyWith(p1: CadPoint2D(b.p1.x + deltaMm.x, b.p1.y + deltaMm.y), p2: CadPoint2D(b.p2.x + deltaMm.x, b.p2.y + deltaMm.y));
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,
      bends: newBends,
      cutLines: _document.cutLines,
      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    // Enforce geometric constraints after every drag step.
    if (_document.constraints.isNotEmpty) {
      final res = GeometricConstraintSolver.solve(document: _document, customReferences: allReferenceGeometries);
      if (res.success) _document = res.updatedDocument;
    }

    _recomputeMesh();
    notifyListeners();
  }

  /// Live dragging of laser cut line across sheet blank.
  void moveSelectedCut(CadPoint2D deltaMm) {
    if (_selectedCutId == null) return;

    // Constraint guard: block movement if a 'fixed' constraint targets this cut line.
    final hasFixedConstraint = _document.constraints.any((c) => c.type == CadConstraintType.fixed && c.entityIds.contains(_selectedCutId));
    if (hasFixedConstraint) return;

    final newCuts = _document.cutLines.map((c) {
      if (c.id != _selectedCutId) return c;
      return c.copyWith(p1: CadPoint2D(c.p1.x + deltaMm.x, c.p1.y + deltaMm.y), p2: CadPoint2D(c.p2.x + deltaMm.x, c.p2.y + deltaMm.y));
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,
      bends: _document.bends,
      cutLines: newCuts,
      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    // Enforce geometric constraints after every drag step.
    if (_document.constraints.isNotEmpty) {
      final res = GeometricConstraintSolver.solve(document: _document, customReferences: allReferenceGeometries);
      if (res.success) _document = res.updatedDocument;
    }

    _recomputeMesh();
    notifyListeners();
  }

  /// Drags an individual endpoint of a bend line (e.g. to snap it onto an edge or another bend).

  void updateBendEndpoint({required String bendId, required bool isP1, required CadPoint2D newPoint}) {
    final newBends = _document.bends.map((b) {
      if (b.id != bendId) return b;

      return b.copyWith(p1: isP1 ? newPoint : b.p1, p2: !isP1 ? newPoint : b.p2);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: newBends,

      cutLines: _document.cutLines,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Adds a laser cut line / slit to the workpiece.

  void addCutLine(CadPoint2D p1, CadPoint2D p2) {
    _recordHistory();

    final newId = 'C${_document.cutLines.length + 1}';

    final newCut = CadLineSegment(id: newId, p1: p1, p2: p2, layer: 'CUT');

    final updatedCuts = [..._document.cutLines, newCut];

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: updatedCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(cutLines: updatedCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _selectedCutId = newId;

    _selectedBendId = null;

    _selectedPunchId = null;

    _recomputeMesh();

    notifyListeners();
  }

  void deleteCutLine(String cutId) {
    _recordHistory();

    final remaining = _document.cutLines.where((c) => c.id != cutId).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: remaining,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(cutLines: remaining, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    if (_selectedCutId == cutId) _selectedCutId = null;

    _recomputeMesh();

    notifyListeners();
  }

  void deleteCut(String cutId) => deleteCutLine(cutId);

  void toggleSelectedConstruction() {
    if (_selectedCutId != null) {
      final cutIdx = _document.cutLines.indexWhere((c) => c.id == _selectedCutId);
      if (cutIdx != -1) {
        final cut = _document.cutLines[cutIdx];
        addConstructionLine(cut.p1, cut.p2);
        deleteCutLine(_selectedCutId!);
        _selectedCutId = null;
        notifyListeners();
        return;
      }
    }
    toggleConstructionMode();
  }

  void toggleCutVisibility(String cutId) {
    // Laser cut lines are currently active cutting paths; notify listeners on toggle

    notifyListeners();
  }

  /// Drags an individual endpoint of a cut line.

  void updateCutEndpoint({required String cutId, required bool isP1, required CadPoint2D newPoint}) {
    final newCuts = _document.cutLines.map((c) {
      if (c.id != cutId) return c;

      return c.copyWith(p1: isP1 ? newPoint : c.p1, p2: !isP1 ? newPoint : c.p2);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: newCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Updates an existing cut line / segment with full 50-step undo

  void updateCutLine(CadLineSegment updated) {
    _recordHistory();

    final newCuts = _document.cutLines.any((c) => c.id == updated.id)
        ? _document.cutLines.map((c) => c.id == updated.id ? updated : c).toList()
        : [..._document.cutLines, updated];

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: newCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Updates an existing planar face with full 50-step undo

  void updateFace(PlanarSheetFace updated) {
    _recordHistory();

    final newFaces = _document.faces.any((f) => f.id == updated.id)
        ? _document.faces.map((f) => f.id == updated.id ? updated : f).toList()
        : [..._document.faces, updated];

    _document = _document.copyWith(faces: newFaces);

    _recomputeMesh();

    notifyListeners();
  }

  // ===========================================================================

  // Step 6 (#19) & Step 7 (#20) Dimensioning & Direct Driving Engine

  // ===========================================================================

  void selectDimension(String? id) {
    if (_selectedDimensionId == id) return;

    _selectedDimensionId = id;

    if (id != null) {
      _selectedBendId = null;

      _selectedCutId = null;

      _selectedPunchId = null;

      _selectedFaceId = null;

      _selectedPatternId = null;

      _selectedPatternHoleIndex = null;

      _selectedArcId = null;

      selectConstraintId(null);

      _selectedEntityIds.clear();

      _selectedEntityIds.add(id);
    }

    notifyListeners();
  }

  void addDimension(CadDimension dimension) {
    _recordHistory();

    _document = _document.copyWith(dimensions: [..._document.dimensions, dimension]);

    _selectedDimensionId = dimension.id;

    notifyListeners();
  }

  /// Commits a dimension placed interactively with custom leader line offset and optional driven value.
  CadDimension? commitInteractiveDimension({
    required CadPoint2D pA,
    required CadPoint2D pB,
    String? referenceAId,
    String? referenceBId,
    double offset = 25.0,
    double? customValue,
  }) {
    final dist = pA.distanceTo(pB);
    if (dist <= 0.001) return null;

    final dimId = 'dim_${_document.dimensions.length + 1}';
    final dim = CadDimension(
      id: dimId,
      type: toolConfig.activeDimensionType,
      referenceAId: referenceAId,
      referenceBId: referenceBId,
      pointA: pA,
      pointB: pB,
      measuredValue: dist,
      dimensionLineOffset: offset,
      isDriven: false,
    );
    addDimension(dim);

    if (customValue != null && (customValue - dist).abs() > 1e-4) {
      driveDimension(dimId, customValue);
    }
    return dim;
  }

  /// Commits a persistent dimension placed via click-and-drag from point A to point B.
  CadDimension? commitDragDimension({
    required CadPoint2D pA,
    required CadPoint2D pB,
    double offset = 8.0,
  }) {
    final dist = pA.distanceTo(pB);
    if (dist < 0.5) return null;

    final dimId = 'dim_${_document.dimensions.length + 1}';
    final dim = CadDimension(
      id: dimId,
      type: CadDimensionType.aligned,
      pointA: pA,
      pointB: pB,
      measuredValue: dist,
      dimensionLineOffset: offset,
      isDriven: false,
    );
    addDimension(dim);
    _selectedDimensionId = dimId;
    notifyListeners();
    return dim;
  }

  /// Sets the dimension line offset without polluting undo stack during continuous drag
  /// Works for both user-created CadDimension and system exterior dimensions.
  void setDimensionLineOffset(String id, double newOffset) {
    _dimensionLineOffsets[id] = newOffset;
    final idx = _document.dimensions.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      final dim = _document.dimensions[idx];
      final updated = dim.copyWith(dimensionLineOffset: newOffset);
      final newDims = List<CadDimension>.from(_document.dimensions);
      newDims[idx] = updated;
      _document = _document.copyWith(dimensions: newDims);
    }
    notifyListeners();
  }

  /// Commits the dimension line offset after drag release for undo/redo history
  void commitDimensionLineOffset(String id) {
    _recordHistory();
  }

  /// Resets dimension line offset to its default computed position
  void resetDimensionLineOffset(String id) {
    if (_dimensionLineOffsets.containsKey(id)) {
      _dimensionLineOffsets.remove(id);
      final idx = _document.dimensions.indexWhere((d) => d.id == id);
      if (idx >= 0) {
        final dim = _document.dimensions[idx];
        final updated = dim.copyWith(dimensionLineOffset: 8.0);
        final newDims = List<CadDimension>.from(_document.dimensions);
        newDims[idx] = updated;
        _document = _document.copyWith(dimensions: newDims);
      }
      notifyListeners();
    }
  }

  void updateDimension(CadDimension updated) {
    _recordHistory();

    final newDims = _document.dimensions.map((d) => d.id == updated.id ? updated : d).toList();

    _document = _document.copyWith(dimensions: newDims);

    notifyListeners();
  }

  void removeDimension(String id) {
    _recordHistory();

    final newDims = _document.dimensions.where((d) => d.id != id).toList();

    _document = _document.copyWith(dimensions: newDims);

    if (_selectedDimensionId == id) _selectedDimensionId = null;

    notifyListeners();
  }

  void driveDimension(String id, double newValue) {
    final dim = _document.dimensions.where((d) => d.id == id).firstOrNull;

    if (dim == null) {
      // Check if it's implicit blank width / length

      if (id == 'dim_blank_w' || id == 'dim_blank_l') {
        _recordHistory();

        final dummyDim = CadDimension(
          id: id,

          type: id == 'dim_blank_w' ? CadDimensionType.horizontal : CadDimensionType.vertical,

          measuredValue: id == 'dim_blank_w' ? _document.blankWidthMm : _document.blankLengthMm,
        );

        final res = DirectDimensionDriver.drive(document: _document, dimension: dummyDim, newValue: newValue);

        if (res.success) {
          _document = res.updatedDocument;

          _renestPatternsForUpdatedFaces();

          _recomputeMesh();

          notifyListeners();
        }
      }

      return;
    }

    _recordHistory();

    final result = DirectDimensionDriver.drive(document: _document, dimension: dim, newValue: newValue);

    if (result.success) {
      _document = result.updatedDocument;

      _renestPatternsForUpdatedFaces();

      _recomputeMesh();

      notifyListeners();
    }
  }

  // ===========================================================================

  // Step 8 (#21) Geometric Constraints Engine

  // ===========================================================================

  List<CadConstraint> get constraints => _document.constraints;

  void selectConstraint(String? id) {
    if (id != null) {
      _selectedDimensionId = null;
      _selectedPunchId = null;
      _selectedBendId = null;
      _selectedCutId = null;
      _selectedPatternId = null;
      _selectedPatternHoleIndex = null;
      _selectedFaceId = null;
      _selectedArcId = null;
      _selectedEntityIds.clear();
      _selectedEntityIds.add(id);
    }
    selectConstraintId(id);
  }

  void addConstraint(CadConstraint constraint) {
    addConstraintDefinition(ConstraintDefinition.fromLegacy(constraint));
  }

  void removeConstraint(String id) {
    removeConstraintDefinition(id);
  }

  void toggleConstraint(String id) {
    toggleConstraintDefinition(id);
  }

  bool applyConstraint(CadConstraintType type, {List<String>? targetEntityIds}) {
    List<String> ids = targetEntityIds != null ? List<String>.from(targetEntityIds) : [];

    if (ids.isEmpty) {
      if (_selectedCutId != null) {
        ids.add(_selectedCutId!);
      }

      if (_selectedBendId != null && !ids.contains(_selectedBendId)) {
        ids.add(_selectedBendId!);
      }

      if (_selectedPunchId != null && !ids.contains(_selectedPunchId)) {
        ids.add(_selectedPunchId!);
      }

      for (final id in _selectedEntityIds) {
        if (!ids.contains(id)) ids.add(id);
      }
    }

    if (ids.isEmpty) return false;

    if (type.requiresTwoEntities && ids.length < 2) return false;

    final constraint = ConstraintDefinition(
      id: 'CONST_${DateTime.now().millisecondsSinceEpoch}',

      type: type,

      references: ids.take(type.requiresTwoEntities ? 2 : 1).map((id) => EntityRef.parse(id)).toList(),
    );

    addConstraintDefinition(constraint);

    return true;
  }

  ConstraintSolveResult solveConstraints() {
    final res = solveAllConstraints();

    return ConstraintSolveResult(success: res.success, updatedDocument: res.updatedDocument, message: res.message);
  }

  // ===========================================================================

  // Step 9 (#22) & Step 10 (#23) DXF Diagnostics & Geometry Recognition

  // ===========================================================================

  DxfDiagnosticsReport analyzeDxf(String dxfContent) {
    final parsed = DxfMiniParser.parse(dxfContent);

    return DxfImportDiagnosticsEngine.analyze(parsed);
  }

  void importDxfWithDiagnostics(
    String dxfContent, {

    bool heal = true,

    bool recognize = true,

    String productType = 'Sheet Metal Part',

    String itemName = 'Imported Component',
  }) {
    _recordHistory();

    var parsed = DxfMiniParser.parse(dxfContent);

    if (heal) {
      final healRes = DxfImportDiagnosticsEngine.heal(parsed);

      parsed = healRes.healedData;
    }

    if (recognize) {
      final recRes = DxfGeometryRecognitionEngine.recognize(parsed, productType: productType, itemName: itemName, material: _document.material);

      _document = recRes.generatedDocument;
    } else {
      _document = DxfDsfImporter.importDxf(dxfContent, productType: productType, itemName: itemName, material: _document.material);
    }

    _detectedFittingMetadata = DxfFittingMetadata.detectFromDocument(_document, fileName: itemName);

    _recomputeMesh();

    notifyListeners();
  }

  void recognizeFeatures() {
    _recordHistory();

    final entities = <DxfRawEntity>[];

    for (final c in _document.cutLines) {
      entities.add(DxfRawLine(p1: c.p1, p2: c.p2, layer: c.layer));
    }

    for (final p in _document.punches) {
      if (p.isRound) {
        entities.add(DxfRawCircle(center: p.center, radius: p.diameterMm / 2.0));
      }
    }

    for (final b in _document.bends) {
      entities.add(DxfRawLine(p1: b.p1, p2: b.p2, layer: b.layer));
    }

    final parsed = DxfParsedData(entities: entities, layers: {'0', 'CUT', 'BEND_UP', 'BEND_DOWN'});

    final res = DxfGeometryRecognitionEngine.recognize(parsed, productType: _document.productType, itemName: _document.itemName, material: _document.material);

    _document = res.generatedDocument.copyWith(outerContour: _document.outerContour.isNotEmpty ? _document.outerContour : res.outerContour);

    _recomputeMesh();

    notifyListeners();
  }

  // ===========================================================================

  // Core CAD Draw & Modify Methods (Step 3 #16 & Step 4 #17)

  // ===========================================================================

  /// Moves all currently selected entities by (dx, dy) with full Undo/Redo.

  void moveSelectedEntities(double dx, double dy) {
    if (_selectedEntityIds.isEmpty && _selectedPunchId == null && _selectedCutId == null && _selectedBendId == null) {
      return;
    }

    _recordHistory();

    final targetIds = Set<String>.from(_selectedEntityIds);

    if (_selectedPunchId != null) targetIds.add(_selectedPunchId!);

    if (_selectedCutId != null) targetIds.add(_selectedCutId!);

    if (_selectedBendId != null) targetIds.add(_selectedBendId!);

    final updatedPunches = _document.punches.map((p) {
      if (targetIds.contains(p.id)) {
        return p.moveTo(CadPoint2D(p.center.x + dx, p.center.y + dy));
      }

      return p;
    }).toList();

    final updatedCuts = _document.cutLines.map((c) {
      if (targetIds.contains(c.id)) {
        return c.copyWith(p1: CadPoint2D(c.p1.x + dx, c.p1.y + dy), p2: CadPoint2D(c.p2.x + dx, c.p2.y + dy));
      }

      return c;
    }).toList();

    final updatedBends = _document.bends.map((b) {
      if (targetIds.contains(b.id)) {
        return b.copyWith(p1: CadPoint2D(b.p1.x + dx, b.p1.y + dy), p2: CadPoint2D(b.p2.x + dx, b.p2.y + dy));
      }

      return b;
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: updatedBends,

      cutLines: updatedCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(
      punches: updatedPunches,

      cutLines: updatedCuts,

      bends: decomp.connectedBends,

      faces: decomp.faces,

      baseFaceId: decomp.baseFaceId,
    );

    _recomputeMesh();

    notifyListeners();
  }

  /// Rotates all selected entities around [center] by [angleDeg] with full Undo/Redo.

  void rotateSelectedEntities(CadPoint2D center, double angleDeg) {
    if (_selectedEntityIds.isEmpty && _selectedPunchId == null && _selectedCutId == null && _selectedBendId == null) {
      return;
    }

    _recordHistory();

    final targetIds = Set<String>.from(_selectedEntityIds);

    if (_selectedPunchId != null) targetIds.add(_selectedPunchId!);

    if (_selectedCutId != null) targetIds.add(_selectedCutId!);

    if (_selectedBendId != null) targetIds.add(_selectedBendId!);

    final rad = angleDeg * math.pi / 180.0;

    final updatedPunches = _document.punches.map((p) {
      if (targetIds.contains(p.id)) {
        final newCenter = CadTransformMath.rotatePoint(p.center, center, rad);

        final newRot = (p.rotationDeg + angleDeg) % 360.0;

        return p.copyWith(center: newCenter, rotationDeg: newRot);
      }

      return p;
    }).toList();

    final updatedCuts = _document.cutLines.map((c) {
      if (targetIds.contains(c.id)) {
        return c.copyWith(p1: CadTransformMath.rotatePoint(c.p1, center, rad), p2: CadTransformMath.rotatePoint(c.p2, center, rad));
      }

      return c;
    }).toList();

    final updatedBends = _document.bends.map((b) {
      if (targetIds.contains(b.id)) {
        return b.copyWith(p1: CadTransformMath.rotatePoint(b.p1, center, rad), p2: CadTransformMath.rotatePoint(b.p2, center, rad));
      }

      return b;
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: updatedBends,

      cutLines: updatedCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(
      punches: updatedPunches,

      cutLines: updatedCuts,

      bends: decomp.connectedBends,

      faces: decomp.faces,

      baseFaceId: decomp.baseFaceId,
    );

    _recomputeMesh();

    notifyListeners();
  }

  /// Mirrors all selected entities across axis (axisP1 -> axisP2).

  void mirrorSelectedEntities(CadPoint2D axisP1, CadPoint2D axisP2, {bool copy = false}) {
    if (_selectedEntityIds.isEmpty && _selectedPunchId == null && _selectedCutId == null && _selectedBendId == null) {
      return;
    }

    _recordHistory();

    final targetIds = Set<String>.from(_selectedEntityIds);

    if (_selectedPunchId != null) targetIds.add(_selectedPunchId!);

    if (_selectedCutId != null) targetIds.add(_selectedCutId!);

    if (_selectedBendId != null) targetIds.add(_selectedBendId!);

    final axisAngleDeg = math.atan2(axisP2.y - axisP1.y, axisP2.x - axisP1.x) * 180.0 / math.pi;

    final newPunches = List<CncPunchPrimitive>.from(_document.punches);

    final newCuts = List<CadLineSegment>.from(_document.cutLines);

    final newBends = List<FoldBendLine>.from(_document.bends);

    final newSelectedIds = <String>{};

    for (final p in _document.punches.where((p) => targetIds.contains(p.id))) {
      final mirroredCenter = CadTransformMath.mirrorPoint(p.center, axisP1, axisP2);

      final mirroredRot = (2.0 * axisAngleDeg - p.rotationDeg) % 360.0;

      final mirroredId = copy ? 'P${newPunches.length + 1}' : p.id;

      final mirrored = p.copyWith(id: mirroredId, center: mirroredCenter, rotationDeg: mirroredRot);

      if (copy) {
        newPunches.add(mirrored);

        newSelectedIds.add(mirroredId);
      } else {
        final idx = newPunches.indexWhere((x) => x.id == p.id);

        if (idx != -1) newPunches[idx] = mirrored;
      }
    }

    for (final c in _document.cutLines.where((c) => targetIds.contains(c.id))) {
      final mp1 = CadTransformMath.mirrorPoint(c.p1, axisP1, axisP2);

      final mp2 = CadTransformMath.mirrorPoint(c.p2, axisP1, axisP2);

      final mirroredId = copy ? 'C${newCuts.length + 1}' : c.id;

      final mirrored = c.copyWith(id: mirroredId, p1: mp1, p2: mp2);

      if (copy) {
        newCuts.add(mirrored);

        newSelectedIds.add(mirroredId);
      } else {
        final idx = newCuts.indexWhere((x) => x.id == c.id);

        if (idx != -1) newCuts[idx] = mirrored;
      }
    }

    for (final b in _document.bends.where((b) => targetIds.contains(b.id))) {
      final mp1 = CadTransformMath.mirrorPoint(b.p1, axisP1, axisP2);

      final mp2 = CadTransformMath.mirrorPoint(b.p2, axisP1, axisP2);

      final mirroredId = copy ? 'B${newBends.length + 1}' : b.id;

      final mirrored = b.copyWith(id: mirroredId, p1: mp1, p2: mp2);

      if (copy) {
        newBends.add(mirrored);

        newSelectedIds.add(mirroredId);
      } else {
        final idx = newBends.indexWhere((x) => x.id == b.id);

        if (idx != -1) newBends[idx] = mirrored;
      }
    }

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: newBends,

      cutLines: newCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(punches: newPunches, cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    if (copy && newSelectedIds.isNotEmpty) {
      _selectedEntityIds.clear();

      _selectedEntityIds.addAll(newSelectedIds);

      _selectedPunchId = null;

      _selectedCutId = null;

      _selectedBendId = null;

      if (newSelectedIds.length == 1) {
        final sId = newSelectedIds.first;

        if (sId.startsWith('P')) _selectedPunchId = sId;

        if (sId.startsWith('C')) _selectedCutId = sId;

        if (sId.startsWith('B')) _selectedBendId = sId;
      }
    }

    _recomputeMesh();

    notifyListeners();
  }

  /// Deletes all currently selected entities with Undo/Redo.

  void deleteSelectedEntities() {
    if (_selectedEntityIds.isEmpty &&
        _selectedPunchId == null &&
        _selectedCutId == null &&
        _selectedBendId == null &&
        _selectedArcId == null &&
        _selectedPatternId == null &&
        _selectedDimensionId == null &&
        selectedConstraintId == null) {
      return;
    }

    _recordHistory();

    final targetIds = Set<String>.from(_selectedEntityIds);

    if (_selectedPunchId != null) targetIds.add(_selectedPunchId!);
    if (_selectedCutId != null) targetIds.add(_selectedCutId!);
    if (_selectedBendId != null) targetIds.add(_selectedBendId!);
    if (_selectedArcId != null) targetIds.add(_selectedArcId!);
    if (_selectedPatternId != null) targetIds.add(_selectedPatternId!);
    if (_selectedDimensionId != null) targetIds.add(_selectedDimensionId!);
    if (selectedConstraintId != null) targetIds.add(selectedConstraintId!);

    final remainingPunches = _document.punches.where((p) => !targetIds.contains(p.id)).toList();
    final remainingCuts = _document.cutLines.where((c) => !targetIds.contains(c.id)).toList();
    final remainingBends = _document.bends.where((b) => !targetIds.contains(b.id)).toList();
    final remainingArcs = _document.arcs.where((a) => !targetIds.contains(a.id)).toList();
    final remainingPatterns = _document.perforationPatterns.where((p) => !targetIds.contains(p.id)).toList();
    final remainingDims = _document.dimensions.where((d) => !targetIds.contains(d.id)).toList();
    final remainingConstraints = _document.constraints.where((c) => !targetIds.contains(c.id)).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,
      bends: remainingBends,
      cutLines: remainingCuts,
      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(
      punches: remainingPunches,
      cutLines: remainingCuts,
      bends: decomp.connectedBends,
      faces: decomp.faces,
      baseFaceId: decomp.baseFaceId,
      arcs: remainingArcs,
      perforationPatterns: remainingPatterns,
      dimensions: remainingDims,
      constraints: remainingConstraints,
    );

    deselectAll();
    _recomputeMesh();
    notifyListeners();
  }

  /// Duplicates all selected entities shifted by (dx, dy) with Undo/Redo.

  void duplicateSelectedEntities(double dx, double dy) {
    if (_selectedEntityIds.isEmpty && _selectedPunchId == null && _selectedCutId == null && _selectedBendId == null) {
      return;
    }

    _recordHistory();

    final targetIds = Set<String>.from(_selectedEntityIds);

    if (_selectedPunchId != null) targetIds.add(_selectedPunchId!);

    if (_selectedCutId != null) targetIds.add(_selectedCutId!);

    if (_selectedBendId != null) targetIds.add(_selectedBendId!);

    final newPunches = List<CncPunchPrimitive>.from(_document.punches);

    final newCuts = List<CadLineSegment>.from(_document.cutLines);

    final newBends = List<FoldBendLine>.from(_document.bends);

    final newSelectedIds = <String>{};

    for (final p in _document.punches.where((p) => targetIds.contains(p.id))) {
      final newId = 'P${newPunches.length + 1}';

      final dup = p.copyWith(id: newId, center: CadPoint2D(p.center.x + dx, p.center.y + dy));

      newPunches.add(dup);

      newSelectedIds.add(newId);
    }

    for (final c in _document.cutLines.where((c) => targetIds.contains(c.id))) {
      final newId = 'C${newCuts.length + 1}';

      final dup = c.copyWith(id: newId, p1: CadPoint2D(c.p1.x + dx, c.p1.y + dy), p2: CadPoint2D(c.p2.x + dx, c.p2.y + dy));

      newCuts.add(dup);

      newSelectedIds.add(newId);
    }

    for (final b in _document.bends.where((b) => targetIds.contains(b.id))) {
      final newId = 'B${newBends.length + 1}';

      final dup = b.copyWith(id: newId, p1: CadPoint2D(b.p1.x + dx, b.p1.y + dy), p2: CadPoint2D(b.p2.x + dx, b.p2.y + dy));

      newBends.add(dup);

      newSelectedIds.add(newId);
    }

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: newBends,

      cutLines: newCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(punches: newPunches, cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _selectedEntityIds.clear();

    _selectedEntityIds.addAll(newSelectedIds);

    _selectedPunchId = null;

    _selectedCutId = null;

    _selectedBendId = null;

    if (newSelectedIds.length == 1) {
      final sId = newSelectedIds.first;

      if (sId.startsWith('P')) _selectedPunchId = sId;

      if (sId.startsWith('C')) _selectedCutId = sId;

      if (sId.startsWith('B')) _selectedBendId = sId;
    }

    _recomputeMesh();

    notifyListeners();
  }

  /// Patterns selected entities in a 2D rectangular / linear array.

  void applyLinearPatternToSelected({required int countX, required int countY, required double pitchX, required double pitchY, double angleDeg = 0.0}) {
    if (_selectedEntityIds.isEmpty && _selectedPunchId == null && _selectedCutId == null) {
      return;
    }

    _recordHistory();

    final targetIds = Set<String>.from(_selectedEntityIds);

    if (_selectedPunchId != null) targetIds.add(_selectedPunchId!);

    if (_selectedCutId != null) targetIds.add(_selectedCutId!);

    final newPunches = List<CncPunchPrimitive>.from(_document.punches);

    final newCuts = List<CadLineSegment>.from(_document.cutLines);

    final rad = angleDeg * math.pi / 180.0;

    final cosA = math.cos(rad);

    final sinA = math.sin(rad);

    for (int r = 0; r < countY; r++) {
      for (int c = 0; c < countX; c++) {
        if (r == 0 && c == 0) continue; // Skip original

        final gx = c * pitchX;

        final gy = r * pitchY;

        final dx = gx * cosA - gy * sinA;

        final dy = gx * sinA + gy * cosA;

        for (final p in _document.punches.where((p) => targetIds.contains(p.id))) {
          final newId = 'P${newPunches.length + 1}';

          newPunches.add(p.copyWith(id: newId, center: CadPoint2D(p.center.x + dx, p.center.y + dy)));
        }

        for (final cut in _document.cutLines.where((c) => targetIds.contains(c.id))) {
          final newId = 'C${newCuts.length + 1}';

          newCuts.add(cut.copyWith(id: newId, p1: CadPoint2D(cut.p1.x + dx, cut.p1.y + dy), p2: CadPoint2D(cut.p2.x + dx, cut.p2.y + dy)));
        }
      }
    }

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: newCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(punches: newPunches, cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Patterns selected entities in a polar circular array around [center].

  void applyCircularPatternToSelected({required CadPoint2D center, required int count, required double totalAngleDeg}) {
    if (count <= 1) return;

    _recordHistory();

    final targetIds = Set<String>.from(_selectedEntityIds);

    if (_selectedPunchId != null) targetIds.add(_selectedPunchId!);

    if (_selectedCutId != null) targetIds.add(_selectedCutId!);

    final newPunches = List<CncPunchPrimitive>.from(_document.punches);

    final newCuts = List<CadLineSegment>.from(_document.cutLines);

    final stepAngleRad = (totalAngleDeg / count) * math.pi / 180.0;

    for (int i = 1; i < count; i++) {
      final angle = i * stepAngleRad;

      for (final p in _document.punches.where((p) => targetIds.contains(p.id))) {
        final newCenter = CadTransformMath.rotatePoint(p.center, center, angle);

        final newRot = (p.rotationDeg + angle * 180.0 / math.pi) % 360.0;

        final newId = 'P${newPunches.length + 1}';

        newPunches.add(p.copyWith(id: newId, center: newCenter, rotationDeg: newRot));
      }

      for (final cut in _document.cutLines.where((c) => targetIds.contains(c.id))) {
        final newP1 = CadTransformMath.rotatePoint(cut.p1, center, angle);

        final newP2 = CadTransformMath.rotatePoint(cut.p2, center, angle);

        final newId = 'C${newCuts.length + 1}';

        newCuts.add(cut.copyWith(id: newId, p1: newP1, p2: newP2));
      }
    }

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: newCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(punches: newPunches, cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Offsets the flat blank workpiece outer contour.

  void offsetContour(double distance) {
    if (_document.outerContour.length < 3) return;

    _recordHistory();

    final newContour = GeometryModifyEngine.offsetPolygon(polygon: _document.outerContour, distance: distance);

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: newContour,

      bends: _document.bends,

      cutLines: _document.cutLines,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(outerContour: newContour, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Adds a laser cut rectangle specified by opposite corners as an immediate surface void cutout.

  void addCutRectangle(CadPoint2D c1, CadPoint2D c2) {
    final minX = math.min(c1.x, c2.x);

    final maxX = math.max(c1.x, c2.x);

    final minY = math.min(c1.y, c2.y);

    final maxY = math.max(c1.y, c2.y);

    if ((maxX - minX) < 0.5 || (maxY - minY) < 0.5) return;

    final rectLoop = [CadPoint2D(minX, minY), CadPoint2D(maxX, minY), CadPoint2D(maxX, maxY), CadPoint2D(minX, maxY), CadPoint2D(minX, minY)];

    addClosedCutoutVoid(rectLoop);
  }

  /// Completes active polyline drawing. If [close] is true or first and last vertices match,

  /// generates a closed hole/void cutout on the intersecting surface face.

  void finishPolyline({bool? close}) {
    if (_pendingMultiPoints.length < 2) {
      _pendingMultiPoints.clear();

      _rubberBandEndpoint = null;

      notifyListeners();

      return;
    }

    final pts = List<CadPoint2D>.from(_pendingMultiPoints);

    _pendingMultiPoints.clear();

    _rubberBandEndpoint = null;

    final shouldClose = close ?? (pts.first.distanceTo(pts.last) < 8.0 || (pts.length >= 3 && pts.first.distanceTo(pts.last) < 12.0));

    if (shouldClose) {
      if (pts.first.distanceTo(pts.last) > 1e-4) {
        pts.add(pts.first);
      }

      addClosedCutoutVoid(pts);
    } else {
      addPolylineCuts(pts);
    }
  }

  /// Adds a closed polygon loop as a real cutout void/hole through the sheet surface.

  /// Generates top hole, bottom hole, and solid bore walls in 3D.

  void addClosedCutoutVoid(List<CadPoint2D> polygon) {
    if (polygon.length < 3) return;

    _recordHistory();

    // Strip duplicate closing point for polygon boundary calculation

    final cleanLoop = <CadPoint2D>[];

    for (int i = 0; i < polygon.length; i++) {
      if (i == polygon.length - 1 && polygon[i].distanceTo(polygon.first) < 1e-4) {
        continue;
      }

      cleanLoop.add(polygon[i]);
    }

    if (cleanLoop.length < 3) {
      addPolylineCuts(polygon);

      return;
    }

    // Compute centroid & bounding extents

    double cx = 0.0, cy = 0.0;

    double minX = cleanLoop.first.x, maxX = cleanLoop.first.x;

    double minY = cleanLoop.first.y, maxY = cleanLoop.first.y;

    for (final pt in cleanLoop) {
      cx += pt.x;

      cy += pt.y;

      if (pt.x < minX) minX = pt.x;

      if (pt.x > maxX) maxX = pt.x;

      if (pt.y < minY) minY = pt.y;

      if (pt.y > maxY) maxY = pt.y;
    }

    final center = CadPoint2D(cx / cleanLoop.length, cy / cleanLoop.length);

    final widthMm = maxX - minX;

    final lengthMm = maxY - minY;

    // Create persistent void punch primitive with customBoundary

    final voidPunch = CncPunchPrimitive(
      id: 'VOID_${_document.punches.length + 1}',

      type: PunchType.compound,

      center: center,

      widthMm: widthMm,

      lengthMm: lengthMm,

      customBoundary: cleanLoop,

      layer: 'CUT',

      showLabel: true,
    );

    // Locate enclosing face and associate hole loop

    final updatedFaces = _document.faces.map((f) {
      if (PlanarFaceDecomposer.isPointInsidePolygon(center, f.vertices)) {
        return f.copyWith(holes: [...f.holes, cleanLoop]);
      }

      return f;
    }).toList();

    _document = _document.copyWith(punches: [..._document.punches, voidPunch], faces: updatedFaces);

    _recomputeMesh();

    notifyListeners();
  }

  /// Adds continuous laser cut line segments forming a polyline.

  void addPolylineCuts(List<CadPoint2D> points) {
    if (points.length < 2) return;

    _recordHistory();

    final newCuts = List<CadLineSegment>.from(_document.cutLines);

    for (int i = 0; i < points.length - 1; i++) {
      newCuts.add(CadLineSegment(id: 'C${newCuts.length + 1}', p1: points[i], p2: points[i + 1], layer: 'CUT'));
    }

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: newCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(cutLines: newCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Adds a first-class CAD Arc entity into the document with editable properties.
  void addArcEntity(CadPoint2D p1, CadPoint2D p2, CadPoint2D p3) {
    _recordHistory();
    final arcId = 'ARC_${_document.arcs.length + 1}';
    final arc = CadArc2D.from3Points(id: arcId, p1: p1, p2: p2, p3: p3, layer: 'CUT', isBoundary: false);
    _document = _document.copyWith(arcs: [..._document.arcs, arc]);
    _selectedArcId = arcId;
    _isPropertyInspectorOpen = true;
    _recomputeMesh();
    notifyListeners();
  }

  /// Adds an arc laser cut approximated by discrete line segments.

  void addArcCut(CadPoint2D p1, CadPoint2D p2, CadPoint2D p3, [int segments = 8]) {
    final arc = CadArc2D.from3Points(id: 'arc', p1: p1, p2: p2, p3: p3);

    final pts = arc.samplePoints(segments);

    addPolylineCuts(pts);
  }

  /// Trims a cut line segment against intersecting boundaries with Undo/Redo.

  void trimCutLine(String cutId, CadPoint2D pickPoint) {
    final cut = _document.cutLines.cast<CadLineSegment?>().firstWhere((c) => c?.id == cutId, orElse: () => null);

    if (cut == null) return;

    _recordHistory();

    final subject = CadLine2D(id: cut.id, p1: cut.p1, p2: cut.p2, layer: cut.layer);

    final boundaries = <CadGeometry>[];

    for (final c in _document.cutLines) {
      if (c.id != cutId) {
        boundaries.add(CadLine2D(id: c.id, p1: c.p1, p2: c.p2, layer: c.layer));
      }
    }

    for (int i = 0; i < _document.outerContour.length; i++) {
      final pA = _document.outerContour[i];

      final pB = _document.outerContour[(i + 1) % _document.outerContour.length];

      boundaries.add(CadLine2D(id: 'border_$i', p1: pA, p2: pB));
    }

    final trimmed = GeometryModifyEngine.trimLine(
      subject: subject,

      boundaries: boundaries,

      pickPoint: pickPoint,

      idGenerator: (idx) => 'C${_document.cutLines.length + idx + 1}',
    );

    final remainingCuts = _document.cutLines.where((c) => c.id != cutId).toList();

    for (final seg in trimmed) {
      remainingCuts.add(CadLineSegment(id: seg.id, p1: seg.p1, p2: seg.p2, layer: seg.layer));
    }

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: remainingCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(cutLines: remainingCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Extends a cut line segment towards the nearest boundary with Undo/Redo.

  void extendCutLine(String cutId, {required bool extendStart}) {
    final cut = _document.cutLines.cast<CadLineSegment?>().firstWhere((c) => c?.id == cutId, orElse: () => null);

    if (cut == null) return;

    _recordHistory();

    final subject = CadLine2D(id: cut.id, p1: cut.p1, p2: cut.p2, layer: cut.layer);

    final boundaries = <CadGeometry>[];

    for (final c in _document.cutLines) {
      if (c.id != cutId) {
        boundaries.add(CadLine2D(id: c.id, p1: c.p1, p2: c.p2, layer: c.layer));
      }
    }

    for (int i = 0; i < _document.outerContour.length; i++) {
      final pA = _document.outerContour[i];

      final pB = _document.outerContour[(i + 1) % _document.outerContour.length];

      boundaries.add(CadLine2D(id: 'border_$i', p1: pA, p2: pB));
    }

    final extended = GeometryModifyEngine.extendLine(subject: subject, boundaries: boundaries, extendStart: extendStart);

    if (extended == null) return;

    final updatedCuts = _document.cutLines.map((c) {
      if (c.id == cutId) {
        return c.copyWith(p1: extended.p1, p2: extended.p2);
      }

      return c;
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: updatedCuts,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(cutLines: updatedCuts, bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  /// Computes constraints for the selected bend line to workpiece outer edges.

  ({double distFromLeftMm, double distFromBottomMm, double distFromRightMm, double distFromTopMm})? getSelectedBendConstraints() {
    if (_selectedBendId == null) return null;

    FoldBendLine? bend;

    try {
      bend = _document.bends.firstWhere((b) => b.id == _selectedBendId);
    } catch (_) {
      return null;
    }

    final bw = _document.blankWidthMm > 0 ? _document.blankWidthMm : 200.0;

    final bl = _document.blankLengthMm > 0 ? _document.blankLengthMm : 300.0;

    final minX = math.min(bend.p1.x, bend.p2.x);

    final maxX = math.max(bend.p1.x, bend.p2.x);

    final minY = math.min(bend.p1.y, bend.p2.y);

    final maxY = math.max(bend.p1.y, bend.p2.y);

    return (distFromLeftMm: minX, distFromBottomMm: minY, distFromRightMm: math.max(0.0, bw - maxX), distFromTopMm: math.max(0.0, bl - maxY));
  }

  /// Industrial CAD constraint: sets exact mm distance from an outer edge.

  void setBendConstraint({required String referenceEdge, required double targetDistanceMm}) {
    if (_selectedBendId == null) return;

    recordHistory();

    final edgeRef = referenceEdge.toUpperCase() == 'LEFT'
        ? EntityRef.edgeLeft
        : (referenceEdge.toUpperCase() == 'RIGHT' ? EntityRef.edgeRight : (referenceEdge.toUpperCase() == 'BOTTOM' ? EntityRef.edgeBottom : EntityRef.edgeTop));

    final constraint = ConstraintDefinition(
      id: 'BEND_EDGE_${_selectedBendId}_${referenceEdge.toUpperCase()}',

      type: CadConstraintType.distance,

      references: [
        EntityRef(entityId: _selectedBendId!),
        edgeRef,
      ],

      targetValue: targetDistanceMm,

      mode: ConstraintMode.driving,
    );

    addConstraintDefinition(constraint);
  }

  /// Sets exact mm distance from an outer edge for a punch and binds it persistently

  void setPunchEdgeConstraint({required String punchId, required String referenceEdge, required double targetDistanceMm}) {
    recordHistory();

    final edgeRef = referenceEdge.toUpperCase() == 'LEFT'
        ? EntityRef.edgeLeft
        : (referenceEdge.toUpperCase() == 'RIGHT'
              ? EntityRef.edgeRight
              : (referenceEdge.toUpperCase() == 'BOTTOM'
                    ? EntityRef.edgeBottom
                    : (referenceEdge.toUpperCase() == 'CENTER_X' ? EntityRef.centerX : EntityRef.edgeTop)));

    final constraint = ConstraintDefinition(
      id: 'PUNCH_EDGE_${punchId}_${referenceEdge.toUpperCase()}',

      type: CadConstraintType.distance,

      references: [EntityRef.punchCenter(punchId), edgeRef],

      targetValue: targetDistanceMm,

      mode: ConstraintMode.driving,
    );

    addConstraintDefinition(constraint);
  }

  void deleteSelectedPunch() {
    if (_selectedPunchId == null) return;

    _recordHistory();

    final newPunches = _document.punches.where((p) => p.id != _selectedPunchId).toList();

    _document = _document.copyWith(punches: newPunches);

    _selectedPunchId = null;

    _recomputeMesh();

    notifyListeners();
  }

  // void deletePunch(String punchId) {

  //   _recordHistory();

  //   final remaining = _document.punches.where((p) => p.id != punchId).toList();

  //   _document = _document.copyWith(punches: remaining);

  //   if (_selectedPunchId == punchId) _selectedPunchId = null;

  //   _recomputeMesh();

  //   notifyListeners();

  // }

  void applyCornerChamfer(int vertexIdx, double chamferMm) {
    _recordHistory();

    final updated = CncTurretEngine.applyCornerChamfer(contour: _document.outerContour, vertexIndex: vertexIdx, chamferMm: chamferMm);

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: updated,

      bends: _document.bends,

      cutLines: _document.cutLines,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(outerContour: updated, faces: decomp.faces, bends: decomp.connectedBends, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  void applyCornerFillet(int vertexIdx, double radiusMm) {
    _recordHistory();

    final updated = CncTurretEngine.applyCornerFillet(contour: _document.outerContour, vertexIndex: vertexIdx, radiusMm: radiusMm);

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: updated,

      bends: _document.bends,

      cutLines: _document.cutLines,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(outerContour: updated, faces: decomp.faces, bends: decomp.connectedBends, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  void addBendLine(
    CadPoint2D p1,

    CadPoint2D p2, {

    double angleDeg = 90.0,

    BendDirection direction = BendDirection.up,

    BendLineRole role = BendLineRole.bend,

    double? radiusMm,
  }) {
    _recordHistory();

    final newId = role == BendLineRole.flange
        ? 'FL${_document.bends.where((b) => b.isFlange).length + 1}'
        : 'B${_document.bends.where((b) => !b.isFlange).length + 1}';

    final effectiveRadius = radiusMm ?? (role == BendLineRole.flange ? 0.5 : _document.material.defaultBendRadius);

    final newBend = FoldBendLine(
      id: newId,

      p1: p1,

      p2: p2,

      targetAngleDeg: angleDeg,

      direction: direction,

      radiusMm: effectiveRadius,

      role: role,

      layer: direction == BendDirection.up ? 'BEND_UP' : 'BEND_DOWN',
    );

    final updatedBends = [..._document.bends, newBend];

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: updatedBends,

      cutLines: _document.cutLines,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _selectedBendId = newId;

    if (cmsGuidedController.state.isActive && cmsGuidedController.state.workflowStageIndex == 1) {
      final contract = cmsGuidedController.state.contract ?? CmsProductContract.bend45;
      cmsGuidedController.resumeAtStage1(document: _document, contract: contract);
    }

    _recomputeMesh();

    notifyListeners();
  }

  void addFlangeLine(CadPoint2D p1, CadPoint2D p2, {double angleDeg = 90.0, BendDirection direction = BendDirection.up, double radiusMm = 0.5}) {
    addBendLine(p1, p2, angleDeg: angleDeg, direction: direction, role: BendLineRole.flange, radiusMm: radiusMm);
  }

  void setBendRole(String bendId, BendLineRole newRole) {
    _recordHistory();

    _document = _document.copyWith(
      bends: _document.bends.map((b) {
        if (b.id != bendId) return b;

        final newRadius = newRole == BendLineRole.flange && b.radiusMm >= 1.5 ? 0.5 : (newRole == BendLineRole.bend && b.radiusMm <= 0.5 ? 1.5 : b.radiusMm);

        return b.copyWith(role: newRole, radiusMm: newRadius);
      }).toList(),
    );

    _recomputeMesh();

    notifyListeners();
  }

  void nudgeSelectedBend(double dx, double dy) {
    if (_selectedBendId == null) return;

    // Fixed constraint guard
    final isFixed = _document.constraints.any((c) => c.type == CadConstraintType.fixed && c.entityIds.contains(_selectedBendId));
    if (isFixed) return;

    _recordHistory();

    final updatedBends = _document.bends.map((b) {
      if (b.id != _selectedBendId) return b;
      return b.copyWith(p1: CadPoint2D(b.p1.x + dx, b.p1.y + dy), p2: CadPoint2D(b.p2.x + dx, b.p2.y + dy));
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,
      bends: updatedBends,
      cutLines: _document.cutLines,
      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    if (_document.constraints.isNotEmpty) {
      final res = GeometricConstraintSolver.solve(document: _document, customReferences: allReferenceGeometries);
      if (res.success) _document = res.updatedDocument;
    }

    _recomputeMesh();
    notifyListeners();
  }

  /// Calculates the perpendicular distance to the nearest parallel outer contour edge.

  double? getNearestEdgeDistance(FoldBendLine bend) {
    final contour = _document.outerContour;

    if (contour.length < 3) return null;

    final bendLen = bend.length;

    if (bendLen < 1e-4) return null;

    final bx = (bend.p2.x - bend.p1.x) / bendLen;

    final by = (bend.p2.y - bend.p1.y) / bendLen;

    final mid = bend.midpoint;

    double? minDist;

    for (int i = 0; i < contour.length; i++) {
      final e1 = contour[i];

      final e2 = contour[(i + 1) % contour.length];

      final elen = e1.distanceTo(e2);

      if (elen < 1e-4) continue;

      final ex = (e2.x - e1.x) / elen;

      final ey = (e2.y - e1.y) / elen;

      // Check parallelism (|cross product| < 0.08, ~4.5 degrees)

      final cross = (bx * ey - by * ex).abs();

      if (cross < 0.08) {
        // Normal to edge

        final nx = -ey;

        final ny = ex;

        // Perpendicular distance

        final dist = ((mid.x - e1.x) * nx + (mid.y - e1.y) * ny).abs();

        if (minDist == null || dist < minDist) {
          minDist = dist;
        }
      }
    }

    return minDist;
  }

  /// Shifts the bend or flange line so its distance to the nearest parallel outer edge becomes [targetDistanceMm].

  void setBendDistanceToEdge(String bendId, double targetDistanceMm) {
    final bend = _document.bends.cast<FoldBendLine?>().firstWhere((b) => b?.id == bendId, orElse: () => null);

    if (bend == null) return;

    final contour = _document.outerContour;

    if (contour.length < 3) return;

    final bendLen = bend.length;

    if (bendLen < 1e-4) return;

    final bx = (bend.p2.x - bend.p1.x) / bendLen;

    final by = (bend.p2.y - bend.p1.y) / bendLen;

    final mid = bend.midpoint;

    double? bestDist;

    double bestNx = 0;

    double bestNy = 0;

    for (int i = 0; i < contour.length; i++) {
      final e1 = contour[i];

      final e2 = contour[(i + 1) % contour.length];

      final elen = e1.distanceTo(e2);

      if (elen < 1e-4) continue;

      final ex = (e2.x - e1.x) / elen;

      final ey = (e2.y - e1.y) / elen;

      final cross = (bx * ey - by * ex).abs();

      if (cross < 0.08) {
        // Normal to edge

        var nx = -ey;

        var ny = ex;

        // Signed distance along normal from e1

        var signedDist = (mid.x - e1.x) * nx + (mid.y - e1.y) * ny;

        if (signedDist < 0) {
          nx = -nx;

          ny = -ny;

          signedDist = -signedDist;
        }

        if (bestDist == null || signedDist < bestDist) {
          bestDist = signedDist;

          bestNx = nx;

          bestNy = ny;
        }
      }
    }

    if (bestDist != null && (bestNx != 0 || bestNy != 0)) {
      final delta = targetDistanceMm - bestDist;

      if (delta.abs() > 0.01) {
        nudgeSelectedBend(bestNx * delta, bestNy * delta);
      }
    }
  }

  /// Computes a logical bend or flange line based on a single click or hover

  /// near an outer edge or surface.

  ///

  /// First checks for feature-based intersection / opposite-dot candidates (notches and tabs).

  /// Falls back to nearest edge inward projection if no discrete feature is nearby.

  CadLineSegment? computeAutoBendOrFlangeLine(CadPoint2D pt, {required bool isFlange, double? customOffset}) {
    final contour = _document.outerContour;

    if (contour.length < 3) return null;

    // 1. Feature-based snapping to tab base dots and opposite notch intersections (Requirement 2 & SS4)

    final featureCand = DxfAutoFoldEngine.findInteractiveCandidate(pt, isFlange: isFlange, contour: contour, maxProximityMm: 20.0);

    if (featureCand != null) {
      // Duplicate check against existing bends

      final candidateMid = featureCand.midpoint;

      bool isDup = false;

      for (final existing in _document.bends) {
        if (existing.midpoint.distanceTo(candidateMid) < 3.0) {
          final eLen = existing.length;

          final cLen = featureCand.length;

          if (eLen > 1e-4 && cLen > 1e-4) {
            final exUx = (existing.p2.x - existing.p1.x) / eLen;

            final exUy = (existing.p2.y - existing.p1.y) / eLen;

            final cUx = (featureCand.p2.x - featureCand.p1.x) / cLen;

            final cUy = (featureCand.p2.y - featureCand.p1.y) / cLen;

            final dot = (cUx * exUx + cUy * exUy).abs();

            if (dot > 0.95) {
              isDup = true;

              break;
            }
          }
        }
      }

      if (!isDup) {
        return featureCand.toLineSegment(isFlange ? 'auto_flange' : 'auto_bend');
      }
    }

    // 2. Fallback: Edge offset projection for arbitrary points / custom offsets

    final targetOffset =
        customOffset ??
        (isFlange
            ? ((_detectedFittingMetadata != null && _detectedFittingMetadata!.category != FittingCategory.none)
                  ? _detectedFittingMetadata!.flangeMm
                  : toolConfig.flangeOffsetMm)
            : toolConfig.bendOffsetMm);

    // 1. Find closest edge segment on the outer contour

    int bestEdgeIdx = -1;

    double? minEdgeDist;

    CadPoint2D? closestPtOnEdge;

    for (int i = 0; i < contour.length; i++) {
      final e1 = contour[i];

      final e2 = contour[(i + 1) % contour.length];

      final edgeLen = e1.distanceTo(e2);

      if (edgeLen < 1e-3) continue;

      final ex = (e2.x - e1.x) / edgeLen;

      final ey = (e2.y - e1.y) / edgeLen;

      final t = ((pt.x - e1.x) * ex + (pt.y - e1.y) * ey).clamp(0.0, edgeLen);

      final cand = CadPoint2D(e1.x + ex * t, e1.y + ey * t);

      final dist = pt.distanceTo(cand);

      if (minEdgeDist == null || dist < minEdgeDist) {
        minEdgeDist = dist;

        bestEdgeIdx = i;

        closestPtOnEdge = cand;
      }
    }

    if (bestEdgeIdx == -1 || minEdgeDist == null || closestPtOnEdge == null) {
      return null;
    }

    // Proximity threshold: Click/hover should be on edge or near candidate line

    if (isFlange) {
      if (minEdgeDist > targetOffset + 18.0) return null;
    } else {
      final isNearEdge = minEdgeDist <= 20.0;

      final isNearLine = (minEdgeDist - targetOffset).abs() <= 24.0;

      if (!isNearEdge && !isNearLine) return null;
    }

    final e1 = contour[bestEdgeIdx];

    final e2 = contour[(bestEdgeIdx + 1) % contour.length];

    final edgeLen = e1.distanceTo(e2);

    if (edgeLen < 1e-3) return null;

    final ux = (e2.x - e1.x) / edgeLen;

    final uy = (e2.y - e1.y) / edgeLen;

    final n1x = -uy;

    final n1y = ux;

    final n2x = uy;

    final n2y = -ux;

    final mid = CadPoint2D((e1.x + e2.x) / 2.0, (e1.y + e2.y) / 2.0);

    // Test inward orientation using point-in-polygon

    final test1 = CadPoint2D(mid.x + n1x * 1.0, mid.y + n1y * 1.0);

    final test2 = CadPoint2D(mid.x + n2x * 1.0, mid.y + n2y * 1.0);

    final in1 = _isPointInPoly(test1, contour);

    final in2 = _isPointInPoly(test2, contour);

    double nx = n1x;

    double ny = n1y;

    if (in2 && !in1) {
      nx = n2x;

      ny = n2y;
    } else if (!in1 && !in2) {
      final testD1 = CadPoint2D(mid.x + n1x * targetOffset * 0.5, mid.y + n1y * targetOffset * 0.5);

      if (!_isPointInPoly(testD1, contour)) {
        nx = n2x;

        ny = n2y;
      }
    }

    final p0x = mid.x + nx * targetOffset;

    final p0y = mid.y + ny * targetOffset;

    // 2. Intersect the infinite line with all contour segments

    final List<double> sIntersections = [];

    for (int i = 0; i < contour.length; i++) {
      final a = contour[i];

      final b = contour[(i + 1) % contour.length];

      final vx = b.x - a.x;

      final vy = b.y - a.y;

      final denom = ux * vy - uy * vx;

      if (denom.abs() < 1e-6) continue;

      final s = ((a.x - p0x) * vy - (a.y - p0y) * vx) / denom;

      final w = ((a.x - p0x) * uy - (a.y - p0y) * ux) / denom;

      if (w >= -1e-4 && w <= 1.0 + 1e-4) {
        sIntersections.add(s);
      }
    }

    if (sIntersections.length < 2) return null;

    sIntersections.sort();

    final List<double> uniqueS = [];

    for (final s in sIntersections) {
      if (uniqueS.isEmpty || (s - uniqueS.last).abs() > 0.5) {
        uniqueS.add(s);
      }
    }

    if (uniqueS.length < 2) return null;

    double? bestS1;

    double? bestS2;

    double minMidDist = double.infinity;

    for (int i = 0; i < uniqueS.length - 1; i++) {
      final sA = uniqueS[i];

      final sB = uniqueS[i + 1];

      if ((sB - sA).abs() < 3.0) continue;

      final testMidS = (sA + sB) / 2.0;

      final testMidPt = CadPoint2D(p0x + testMidS * ux, p0y + testMidS * uy);

      if (_isPointInPoly(testMidPt, contour)) {
        final distFromCenter = testMidS.abs();

        if (distFromCenter < minMidDist) {
          minMidDist = distFromCenter;

          bestS1 = sA;

          bestS2 = sB;
        }
      }
    }

    if (bestS1 == null || bestS2 == null) return null;

    final p1 = CadPoint2D(p0x + bestS1 * ux, p0y + bestS1 * uy);

    final p2 = CadPoint2D(p0x + bestS2 * ux, p0y + bestS2 * uy);

    if (p1.distanceTo(p2) < 3.0) return null;

    // Duplicate check against existing bends

    final candidateMid = CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);

    for (final existing in _document.bends) {
      if (existing.midpoint.distanceTo(candidateMid) < 3.0) {
        final eLen = existing.length;

        if (eLen > 1e-4) {
          final exUx = (existing.p2.x - existing.p1.x) / eLen;

          final exUy = (existing.p2.y - existing.p1.y) / eLen;

          final dot = (ux * exUx + uy * exUy).abs();

          if (dot > 0.95) {
            return null; // Already exists
          }
        }
      }
    }

    return CadLineSegment(id: isFlange ? 'auto_flange' : 'auto_bend', p1: p1, p2: p2);
  }

  /// Updates fitting metadata, attaching category, product, and variant parameters to DSF document.

  void updateFittingMetadata(DxfFittingMetadata meta) {
    _recordHistory('Update Fitting Metadata');

    _detectedFittingMetadata = meta;

    final updatedMetadata = Map<String, dynamic>.from(_document.metadata);

    updatedMetadata['fittingMetadata'] = meta.toJson();

    updatedMetadata['fittingCategory'] = meta.category;

    updatedMetadata['fittingProduct'] = meta.product;

    updatedMetadata['fittingVariant'] = meta.variantName;

    updatedMetadata['fittingFlangeMm'] = meta.flangeMm;

    // Attach serialized ports array with their dimensions to DSF metadata

    final ports = meta.getPortOpenings(_document);

    updatedMetadata['ports'] = ports
        .map(
          (p) => {
            'id': p.id,

            'label': p.label,

            'side': p.side.name,

            'width': p.widthMm,

            'height': p.heightMm,

            'measuredLength': p.measuredLengthMm,

            'edgeP1': [p.edgeP1.x, p.edgeP1.y],

            'edgeP2': [p.edgeP2.x, p.edgeP2.y],

            'center': [p.center.x, p.center.y],

            'normal': [p.normal.x, p.normal.y],
          },
        )
        .toList();

    final updatedParams = Map<String, double>.from(_document.parameters);

    updatedParams.addAll(meta.parameters);

    updatedParams['flange'] = meta.flangeMm;

    _document = _document.copyWith(metadata: updatedMetadata, parameters: updatedParams);

    notifyListeners();
  }

  void setPortBadgeOffset(String portId, Offset offset) {
    _portBadgeOffsets[portId] = offset;

    if (_detectedFittingMetadata != null) {
      final map = Map<String, List<double>>.from(_detectedFittingMetadata!.portBadgeOffsets ?? {});

      map[portId] = [offset.dx, offset.dy];

      _detectedFittingMetadata = _detectedFittingMetadata!.copyWith(portBadgeOffsets: map);

      final metaMap = Map<String, dynamic>.from(_document.metadata);

      metaMap['fittingMetadata'] = _detectedFittingMetadata!.toJson();

      _document = _document.copyWith(metadata: metaMap);
    }

    notifyListeners();
  }

  void togglePortOpeningBadges([bool? visible]) {
    _showPortOpeningBadges = visible ?? !_showPortOpeningBadges;

    notifyListeners();
  }

  void startPortEdgePick(PortEdgePickTarget target) {
    _activePortPickTarget = target;

    _toolMode = StudioToolMode.pickPortEdge;

    notifyListeners();
  }

  void cancelPortEdgePick() {
    _activePortPickTarget = null;

    _hoveredContourEdgeP1 = null;

    _hoveredContourEdgeP2 = null;

    _hoveredContourEdgeLengthMm = null;

    _toolMode = StudioToolMode.select;

    notifyListeners();
  }

  void startSemanticPortAssignment(String portId) {
    _activeSemanticPortId = portId;
    _activePortInferenceResult = null;
    _activePortPickTarget = null;
    _toolMode = StudioToolMode.assignPortSemantic;
    notifyListeners();
  }

  void cancelSemanticPortAssignment() {
    _activeSemanticPortId = null;
    _activePortInferenceResult = null;
    _hoveredContourEdgeP1 = null;
    _hoveredContourEdgeP2 = null;
    _hoveredContourEdgeLengthMm = null;
    _toolMode = StudioToolMode.select;
    notifyListeners();
  }

  void handleCanvasSemanticPortClick(CadPoint2D clickPos) {
    final portId = _activeSemanticPortId ?? 'port1';
    PortInferenceResult? result;

    // Fast-path: Consult 3D Structural Topology if bends and faces exist
    if (_document.bends.isNotEmpty && _document.faces.isNotEmpty) {
      try {
        final topo = StructuralTopologyAnalyzer.analyze(
          _document,
          productType: _detectedFittingMetadata?.product,
          variantName: _detectedFittingMetadata?.variantName,
        );
        for (final p in topo.detectedPorts) {
          if (p.portId.toLowerCase() == portId.toLowerCase() || clickPos.distanceTo(p.openingEdge.midpoint) < 40.0) {
            result = p;
            break;
          }
        }
      } catch (_) {}
    }

    result ??= PortInferenceEngine.inferFromOpeningEdge(document: _document, clickedPoint: clickPos, portId: portId);

    if (result != null) {
      _activePortInferenceResult = result;
      _hoveredContourEdgeP1 = result.openingEdge.p1;
      _hoveredContourEdgeP2 = result.openingEdge.p2;
      _hoveredContourEdgeLengthMm = result.inferredWidth;
      notifyListeners();
    }
  }

  void confirmSemanticPortAssignment() {
    final result = _activePortInferenceResult;
    final portId = _activeSemanticPortId;
    if (result == null || portId == null) return;

    final currentMeta = _detectedFittingMetadata ?? DxfFittingMetadata.fromDocument(_document) ?? DxfFittingMetadata.detectFromDocument(_document);

    final semantic = Map<String, Map<String, dynamic>>.from(currentMeta.semanticPorts ?? {});
    semantic[portId] = {
      'width': result.inferredWidth,
      'heightA': result.inferredHeightA,
      'heightB': result.inferredHeightB,
      'side': result.inferredSide.name,
      'outwardNormalAngleRad': result.outwardNormalAngleRad,
      'widthEdge': {
        'p1': [result.openingEdge.p1.x, result.openingEdge.p1.y],
        'p2': [result.openingEdge.p2.x, result.openingEdge.p2.y],
        'length': result.inferredWidth,
      },
      'featureIds': result.associatedFeatureIds,
      'notes': result.inferenceNotes,
    };

    final manual = Map<String, Map<String, dynamic>>.from(currentMeta.manualPortEdges ?? {});
    manual[portId] = {
      'side': result.inferredSide.name,
      'widthEdge': {
        'p1': [result.openingEdge.p1.x, result.openingEdge.p1.y],
        'p2': [result.openingEdge.p2.x, result.openingEdge.p2.y],
        'length': result.inferredWidth,
      },
    };

    final portAssignments = Map<String, String>.from(currentMeta.portAssignments ?? {});
    portAssignments[portId] = result.inferredSide.name;

    final newParams = Map<String, double>.from(currentMeta.parameters);
    newParams['${portId}Width'] = result.inferredWidth;
    newParams['${portId}Height'] = result.inferredHeightA;
    newParams['${portId}HeightA'] = result.inferredHeightA;
    newParams['${portId}HeightB'] = result.inferredHeightB;

    if (portId == 'port1') {
      newParams['width'] = result.inferredWidth;
      newParams['height'] = result.inferredHeightA;
      newParams['heightA'] = result.inferredHeightA;
      newParams['heightB'] = result.inferredHeightB;
    }

    final updatedMeta = currentMeta.copyWith(semanticPorts: semantic, manualPortEdges: manual, portAssignments: portAssignments, parameters: newParams);

    updateFittingMetadata(updatedMeta);
    _activeSemanticPortId = null;
    _activePortInferenceResult = null;
    _hoveredContourEdgeP1 = null;
    _hoveredContourEdgeP2 = null;
    _hoveredContourEdgeLengthMm = null;
    _toolMode = StudioToolMode.select;

    _recordHistory(
      'Assign ${result.inferredSide.displayName} Port ($portId): W=${result.inferredWidth.toStringAsFixed(1)}, H-A=${result.inferredHeightA.toStringAsFixed(1)}, H-B=${result.inferredHeightB.toStringAsFixed(1)}',
    );
    notifyListeners();
  }

  /// 1-Click Automated Batch Port & Topology Discovery using 3D Folded Geometry
  void autoDetectAndAssignAllPorts() {
    if (!isCmsDrawing) return;
    if (_document.bends.isNotEmpty && _document.faces.isNotEmpty) {
      try {
        final topo = StructuralTopologyAnalyzer.analyze(
          _document,
          productType: _detectedFittingMetadata?.product,
          variantName: _detectedFittingMetadata?.variantName,
        );

        // Update punches with classified roles (Coupler vs Perforation)
        _document = _document.copyWith(punches: topo.classifiedPunches);

        final currentMeta = _detectedFittingMetadata ?? DxfFittingMetadata.fromDocument(_document) ?? DxfFittingMetadata.detectFromDocument(_document);

        final semantic = Map<String, Map<String, dynamic>>.from(currentMeta.semanticPorts ?? {});
        final portAssignments = Map<String, String>.from(currentMeta.portAssignments ?? {});

        for (final p in topo.detectedPorts) {
          semantic[p.portId] = {
            'width': p.inferredWidth,
            'heightA': p.inferredHeightA,
            'heightB': p.inferredHeightB,
            'side': p.inferredSide.name,
            'outwardNormalAngleRad': p.outwardNormalAngleRad,
            'widthEdge': {
              'p1': [p.openingEdge.p1.x, p.openingEdge.p1.y],
              'p2': [p.openingEdge.p2.x, p.openingEdge.p2.y],
              'length': p.inferredWidth,
            },
            'featureIds': p.associatedFeatureIds,
            'notes': p.inferenceNotes,
          };
          portAssignments[p.portId] = p.inferredSide.name;
        }

        final updatedMeta = currentMeta.copyWith(semanticPorts: semantic, portAssignments: portAssignments);
        _detectedFittingMetadata = updatedMeta;
        updateFittingMetadata(updatedMeta);
        _recordHistory('⚡ 3D Topology Auto-Detected Ports & Classified Holes');
        notifyListeners();
        return;
      } catch (_) {}
    }

    final updatedMeta = PortInferenceEngine.updateMetadataWithAutoDetectedPorts(_document, _detectedFittingMetadata);
    _detectedFittingMetadata = updatedMeta;
    updateFittingMetadata(updatedMeta);
    _recordHistory('⚡ Auto-Detected All Fitting Ports (1-Click)');
    notifyListeners();
  }

  /// Tag selected holes with a semantic role (coupler, perforation, manufacturing, reference)
  void markSelectedPunchesRole(CncPunchRole role) {
    final ids = Set<String>.from(selectedEntityIds);
    if (selectedPunchId != null) {
      ids.add(selectedPunchId!);
    }
    if (ids.isEmpty) return;

    final updated = _document.punches.map((p) {
      if (ids.contains(p.id)) {
        return p.copyWith(role: role);
      }
      return p;
    }).toList();

    _document = _document.copyWith(punches: updated);
    _recordHistory('Marked ${ids.length} holes as ${role.name}');
    notifyListeners();
  }

  void markSelectedAsCouplerHoles() => markSelectedPunchesRole(CncPunchRole.coupler);
  void markSelectedAsPerforations() => markSelectedPunchesRole(CncPunchRole.perforation);

  /// Explicitly marks or unmarks a punch as a coupler mounting slot (Section 9).
  void markPunchAsCoupler(String punchId, {bool isCoupler = true}) {
    final updated = _document.punches.map((p) {
      if (p.id == punchId) {
        return p.copyWith(
          role: isCoupler ? CncPunchRole.coupler : CncPunchRole.perforation,
        );
      }
      return p;
    }).toList();

    _document = _document.copyWith(punches: updated);
    _recordHistory(isCoupler ? 'Marked punch $punchId as coupler' : 'Marked punch $punchId as regular');
    notifyListeners();
  }

  /// Toggles coupler role for currently selected punch(es).
  void toggleSelectedPunchCouplerRole({bool? isCoupler}) {
    final ids = Set<String>.from(selectedEntityIds);
    if (selectedPunchId != null) ids.add(selectedPunchId!);
    if (ids.isEmpty) return;

    final targetPunch = _document.punches.firstWhere(
      (p) => ids.contains(p.id),
      orElse: () => _document.punches.first,
    );
    final nextState = isCoupler ?? (targetPunch.role != CncPunchRole.coupler);

    final updated = _document.punches.map((p) {
      if (ids.contains(p.id)) {
        return p.copyWith(
          role: nextState ? CncPunchRole.coupler : CncPunchRole.perforation,
        );
      }
      return p;
    }).toList();

    _document = _document.copyWith(punches: updated);
    _recordHistory(nextState ? 'Marked ${ids.length} punch(es) as coupler' : 'Marked ${ids.length} punch(es) as regular');
    notifyListeners();
  }

  /// Automatically identifies candidate coupler slots from geometry and marks them (Section 8 & 9).
  int autoIdentifyCouplerSlots() {
    final contract = cmsGuidedController.state.contract ?? CmsProductContract.bend45;
    final res = CmsCouplerClassifier.classify(
      document: _document,
      contract: contract,
      ports: persistentCmsPorts,
    );

    if (res.couplerSlots.isEmpty) return 0;

    final couplerIds = res.couplerSlots.map((c) => c.id).toSet();
    final updated = _document.punches.map((p) {
      if (couplerIds.contains(p.id)) {
        return p.copyWith(role: CncPunchRole.coupler);
      }
      return p;
    }).toList();

    _document = _document.copyWith(punches: updated);
    _recordHistory('Auto-identified ${couplerIds.length} coupler slot(s)');
    notifyListeners();
    return couplerIds.length;
  }

  void updateHoveredContourEdge(CadPoint2D? p1, CadPoint2D? p2, double? len) {
    if (_hoveredContourEdgeP1 != p1 || _hoveredContourEdgeP2 != p2 || _hoveredContourEdgeLengthMm != len) {
      _hoveredContourEdgeP1 = p1;

      _hoveredContourEdgeP2 = p2;

      _hoveredContourEdgeLengthMm = len;

      notifyListeners();
    }
  }

  /// Checks if edge (a1, a2) is the same edge as (b1, b2) within tolerance

  static bool isSameCadEdge(CadPoint2D a1, CadPoint2D a2, CadPoint2D b1, CadPoint2D b2, {double toleranceMm = 1.0}) {
    final direct = a1.distanceTo(b1) <= toleranceMm && a2.distanceTo(b2) <= toleranceMm;

    final reverse = a1.distanceTo(b2) <= toleranceMm && a2.distanceTo(b1) <= toleranceMm;

    return direct || reverse;
  }

  /// Checks if an edge (p1, p2) is already assigned to any port opening or height flap.

  /// Returns a human-readable description of the existing assignment if found, or null if free.

  String? findAssignedPortForEdge(CadPoint2D p1, CadPoint2D p2, {String? excludePortId, bool? excludeIsWidth}) {
    final currentMeta = _detectedFittingMetadata ?? DxfFittingMetadata.fromDocument(_document);

    if (currentMeta == null) return null;

    final manualEdges = currentMeta.manualPortEdges ?? {};

    for (final entry in manualEdges.entries) {
      final portId = entry.key;

      final portData = entry.value;

      final portNum = portId.replaceAll('port', '');

      final portLabel = portId == 'port1' ? 'Port 1 (Inlet)' : (portId == 'port2' ? 'Port 2 (Outlet)' : 'Port $portNum');

      // Check widthEdge

      final wEdge = portData['widthEdge'] as Map?;

      if (wEdge != null && wEdge['p1'] is List && wEdge['p2'] is List) {
        if (!(portId == excludePortId && excludeIsWidth == true)) {
          final p1List = (wEdge['p1'] as List).map((n) => (n as num).toDouble()).toList();

          final p2List = (wEdge['p2'] as List).map((n) => (n as num).toDouble()).toList();

          if (p1List.length >= 2 && p2List.length >= 2) {
            final ep1 = CadPoint2D(p1List[0], p1List[1]);

            final ep2 = CadPoint2D(p2List[0], p2List[1]);

            if (isSameCadEdge(p1, p2, ep1, ep2)) {
              return '$portLabel Width';
            }
          }
        }
      }

      // Check heightEdges

      final hEdges = portData['heightEdges'] as List?;

      if (hEdges != null) {
        for (final hEdge in hEdges) {
          if (hEdge is Map && hEdge['p1'] is List && hEdge['p2'] is List) {
            if (!(portId == excludePortId && excludeIsWidth == false)) {
              final p1List = (hEdge['p1'] as List).map((n) => (n as num).toDouble()).toList();

              final p2List = (hEdge['p2'] as List).map((n) => (n as num).toDouble()).toList();

              if (p1List.length >= 2 && p2List.length >= 2) {
                final ep1 = CadPoint2D(p1List[0], p1List[1]);

                final ep2 = CadPoint2D(p2List[0], p2List[1]);

                if (isSameCadEdge(p1, p2, ep1, ep2)) {
                  return '$portLabel Height Flap';
                }
              }
            }
          }
        }
      }
    }

    // Also check auto-detected openings if no manual edge overrides them

    final openings = currentMeta.getPortOpenings(_document);

    for (final op in openings) {
      if (op.id == excludePortId && excludeIsWidth == true) continue;

      if (isSameCadEdge(p1, p2, op.edgeP1, op.edgeP2)) {
        return '${op.label} (Port ${op.id.replaceAll('port', '')}) Width';
      }
    }

    return null;
  }

  /// Completes port edge picking. Returns an error message if the edge is already assigned,

  /// or null upon successful assignment.

  String? completePortEdgePick({required CadPoint2D p1, required CadPoint2D p2, required double measuredLengthMm}) {
    if (_activePortPickTarget == null) return null;

    final target = _activePortPickTarget!;

    final isWidth = target.name.endsWith('Width');

    final portNumber = target.name.substring(4, 5);

    final portId = 'port$portNumber';

    // Edge Collision Check: Cannot assign the same edge to two different ports or targets!

    final existingAssignment = findAssignedPortForEdge(p1, p2, excludePortId: portId, excludeIsWidth: isWidth);

    if (existingAssignment != null) {
      return 'Edge already assigned to $existingAssignment. Cannot assign multiple ports to a single edge.';
    }

    _recordHistory('Assign ${target.name} Edge');

    var currentMeta = _detectedFittingMetadata ?? DxfFittingMetadata.fromDocument(_document) ?? const DxfFittingMetadata();

    final manualEdges = Map<String, Map<String, dynamic>>.from(currentMeta.manualPortEdges ?? {});

    final portEntry = Map<String, dynamic>.from(manualEdges[portId] ?? {});

    final params = Map<String, double>.from(currentMeta.parameters);

    if (isWidth) {
      portEntry['widthEdge'] = {
        'p1': [p1.x, p1.y],

        'p2': [p2.x, p2.y],

        'length': measuredLengthMm,
      };

      params['${portId}Width'] = measuredLengthMm;

      if (portId == 'port1') {
        params['width'] = measuredLengthMm;

        params['widthIn'] = measuredLengthMm;
      } else if (portId == 'port2') {
        params['widthOut'] = measuredLengthMm;
      } else if (portId == 'port3') {
        params['branchWidth'] = measuredLengthMm;
      }
    } else {
      final existingHeights = List<Map<String, dynamic>>.from(portEntry['heightEdges'] ?? []);

      existingHeights.add({
        'p1': [p1.x, p1.y],

        'p2': [p2.x, p2.y],

        'length': measuredLengthMm,
      });

      portEntry['heightEdges'] = existingHeights;

      params['${portId}Height'] = measuredLengthMm;

      params['height'] = measuredLengthMm;
    }

    manualEdges[portId] = portEntry;

    final updatedMeta = currentMeta.copyWith(parameters: params, manualPortEdges: manualEdges);

    updateFittingMetadata(updatedMeta);

    cancelPortEdgePick();

    return null;
  }

  /// Directly assigns an edge to a port without requiring interactive pick mode (e.g. from context menu).

  /// Returns an error message if the edge is already assigned to a different port/target, or null on success.

  String? assignPortEdgeDirect({
    required String portId,

    required bool isWidth,

    required CadPoint2D p1,

    required CadPoint2D p2,

    required double measuredLengthMm,
  }) {
    // Edge Collision Check: Cannot assign the same edge to two different ports or targets!

    final existingAssignment = findAssignedPortForEdge(p1, p2, excludePortId: portId, excludeIsWidth: isWidth);

    if (existingAssignment != null) {
      return 'Edge already assigned to $existingAssignment. Cannot assign multiple ports to a single edge.';
    }

    final portNum = portId.replaceAll('port', '');

    final portLabel = portId == 'port1' ? 'Port 1 (Inlet)' : (portId == 'port2' ? 'Port 2 (Outlet)' : 'Port $portNum');

    _recordHistory('Assign $portLabel ${isWidth ? 'Width' : 'Height'} Edge');

    var currentMeta = _detectedFittingMetadata ?? DxfFittingMetadata.fromDocument(_document) ?? const DxfFittingMetadata();

    final manualEdges = Map<String, Map<String, dynamic>>.from(currentMeta.manualPortEdges ?? {});

    final portEntry = Map<String, dynamic>.from(manualEdges[portId] ?? {});

    final params = Map<String, double>.from(currentMeta.parameters);

    if (isWidth) {
      portEntry['widthEdge'] = {
        'p1': [p1.x, p1.y],

        'p2': [p2.x, p2.y],

        'length': measuredLengthMm,
      };

      params['${portId}Width'] = measuredLengthMm;

      if (portId == 'port1') {
        params['width'] = measuredLengthMm;

        params['widthIn'] = measuredLengthMm;
      } else if (portId == 'port2') {
        params['widthOut'] = measuredLengthMm;
      } else if (portId == 'port3') {
        params['branchWidth'] = measuredLengthMm;
      }
    } else {
      final existingHeights = List<Map<String, dynamic>>.from(portEntry['heightEdges'] ?? []);

      existingHeights.add({
        'p1': [p1.x, p1.y],

        'p2': [p2.x, p2.y],

        'length': measuredLengthMm,
      });

      portEntry['heightEdges'] = existingHeights;

      params['${portId}Height'] = measuredLengthMm;

      params['height'] = measuredLengthMm;
    }

    manualEdges[portId] = portEntry;

    final updatedMeta = currentMeta.copyWith(parameters: params, manualPortEdges: manualEdges);

    updateFittingMetadata(updatedMeta);

    return null;
  }

  /// Clears any port assignment (width or height) associated with edge (p1, p2).

  void clearAssignedPortEdge(CadPoint2D p1, CadPoint2D p2) {
    var currentMeta = _detectedFittingMetadata ?? DxfFittingMetadata.fromDocument(_document);

    if (currentMeta == null || currentMeta.manualPortEdges == null) return;

    _recordHistory('Clear Port Assignment');

    final manualEdges = Map<String, Map<String, dynamic>>.from(currentMeta.manualPortEdges!);

    bool modified = false;

    for (final portId in manualEdges.keys.toList()) {
      final portData = Map<String, dynamic>.from(manualEdges[portId]!);

      // Check widthEdge

      final wEdge = portData['widthEdge'] as Map?;

      if (wEdge != null && wEdge['p1'] is List && wEdge['p2'] is List) {
        final p1List = (wEdge['p1'] as List).map((n) => (n as num).toDouble()).toList();

        final p2List = (wEdge['p2'] as List).map((n) => (n as num).toDouble()).toList();

        if (p1List.length >= 2 && p2List.length >= 2) {
          final ep1 = CadPoint2D(p1List[0], p1List[1]);

          final ep2 = CadPoint2D(p2List[0], p2List[1]);

          if (isSameCadEdge(p1, p2, ep1, ep2)) {
            portData.remove('widthEdge');

            modified = true;
          }
        }
      }

      // Check heightEdges

      final hEdges = portData['heightEdges'] as List?;

      if (hEdges != null) {
        final newHeights = <Map<String, dynamic>>[];

        for (final hEdge in hEdges) {
          if (hEdge is Map && hEdge['p1'] is List && hEdge['p2'] is List) {
            final p1List = (hEdge['p1'] as List).map((n) => (n as num).toDouble()).toList();

            final p2List = (hEdge['p2'] as List).map((n) => (n as num).toDouble()).toList();

            if (p1List.length >= 2 && p2List.length >= 2) {
              final ep1 = CadPoint2D(p1List[0], p1List[1]);

              final ep2 = CadPoint2D(p2List[0], p2List[1]);

              if (!isSameCadEdge(p1, p2, ep1, ep2)) {
                newHeights.add(Map<String, dynamic>.from(hEdge));
              } else {
                modified = true;
              }
            }
          }
        }

        portData['heightEdges'] = newHeights;
      }

      if (portData.isEmpty || (portData['widthEdge'] == null && (portData['heightEdges'] as List?)?.isEmpty == true)) {
        manualEdges.remove(portId);
      } else {
        manualEdges[portId] = portData;
      }
    }

    if (modified) {
      final updatedMeta = currentMeta.copyWith(manualPortEdges: manualEdges);

      updateFittingMetadata(updatedMeta);
    }
  }

  /// Automatically applies all logical bend and flange lines to the workpiece using

  /// geometric intersection dots, decomposes planar faces, and folds the 3D model.

  void executeAutoFold({DxfFittingMetadata? metadata, double? customFlangeMm}) {
    _recordHistory('Auto Fold Fitting');

    final effectiveMeta = metadata ?? _detectedFittingMetadata;

    var updatedDoc = DxfAutoFoldEngine.autoFoldFitting(document: _document, metadata: effectiveMeta, customFlangeMm: customFlangeMm);

    if (effectiveMeta != null) {
      _detectedFittingMetadata = effectiveMeta;

      final updatedMetadata = Map<String, dynamic>.from(updatedDoc.metadata);

      updatedMetadata['fittingMetadata'] = effectiveMeta.toJson();

      updatedMetadata['fittingCategory'] = effectiveMeta.category;

      updatedMetadata['fittingProduct'] = effectiveMeta.product;

      updatedMetadata['fittingVariant'] = effectiveMeta.variantName;

      updatedMetadata['fittingFlangeMm'] = effectiveMeta.flangeMm;

      // Attach serialized ports array with their dimensions to DSF metadata

      final ports = effectiveMeta.getPortOpenings(updatedDoc);

      updatedMetadata['ports'] = ports
          .map(
            (p) => {
              'id': p.id,

              'label': p.label,

              'side': p.side.name,

              'width': p.widthMm,

              'height': p.heightMm,

              'measuredLength': p.measuredLengthMm,

              'edgeP1': [p.edgeP1.x, p.edgeP1.y],

              'edgeP2': [p.edgeP2.x, p.edgeP2.y],

              'center': [p.center.x, p.center.y],

              'normal': [p.normal.x, p.normal.y],
            },
          )
          .toList();

      final updatedParams = Map<String, double>.from(updatedDoc.parameters);

      updatedParams.addAll(effectiveMeta.parameters);

      updatedParams['flange'] = effectiveMeta.flangeMm;

      updatedDoc = updatedDoc.copyWith(metadata: updatedMetadata, parameters: updatedParams);
    }

    _document = updatedDoc;

    _recomputeMesh();

    notifyListeners();
  }

  /// Automatically places a bend or flange line with a single click if clicking near an edge or on a surface.

  bool tryAutoPlaceBendOrFlange(CadPoint2D pt, {required bool isFlange, double? customOffset}) {
    final cand = computeAutoBendOrFlangeLine(pt, isFlange: isFlange, customOffset: customOffset);

    if (cand == null) return false;

    if (isFlange) {
      addFlangeLine(cand.p1, cand.p2, radiusMm: 0.5);
    } else {
      addBendLine(cand.p1, cand.p2, radiusMm: 1.5);
    }

    return true;
  }

  void deleteBendLine(String bendId) {
    _recordHistory();

    final remainingBends = _document.bends.where((b) => b.id != bendId).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: remainingBends,

      cutLines: _document.cutLines,

      preferredBaseFaceId: _document.baseFaceId,
    );

    _document = _document.copyWith(bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _selectedBendId = null;

    if (cmsGuidedController.state.isActive && cmsGuidedController.state.workflowStageIndex == 1) {
      final contract = cmsGuidedController.state.contract ?? CmsProductContract.bend45;
      cmsGuidedController.resumeAtStage1(document: _document, contract: contract);
    }

    _recomputeMesh();

    notifyListeners();
  }

  void setBaseAnchorFace(String faceId) {
    _recordHistory();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: _document.outerContour,

      bends: _document.bends,

      cutLines: _document.cutLines,

      preferredBaseFaceId: faceId,
    );

    _document = _document.copyWith(bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    _recomputeMesh();

    notifyListeners();
  }

  void updateBend(FoldBendLine updated) {
    _recordHistory();

    final newBends = _document.bends.map((b) => b.id == updated.id ? updated : b).toList();

    _document = _document.copyWith(bends: newBends);

    _recomputeMesh();

    notifyListeners();
  }

  /// Sets or updates bend relief type and optional dimensions

  void updateBendRelief(String bendId, BendReliefType reliefType, {double? widthMm, double? depthMm}) {
    final bend = _document.bends.cast<FoldBendLine?>().firstWhere((b) => b?.id == bendId, orElse: () => null);

    if (bend == null) return;

    updateBend(bend.copyWith(reliefType: reliefType, reliefWidthMm: widthMm, reliefDepthMm: depthMm));
  }

  /// Sets or updates bend K-Factor override

  void setBendKFactor(String bendId, double? kFactor) {
    final bend = _document.bends.cast<FoldBendLine?>().firstWhere((b) => b?.id == bendId, orElse: () => null);

    if (bend == null) return;

    updateBend(bend.copyWith(kFactor: kFactor));
  }

  /// Sets or updates bend allowance override

  void setBendAllowanceOverride(String bendId, double? allowanceMm) {
    final bend = _document.bends.cast<FoldBendLine?>().firstWhere((b) => b?.id == bendId, orElse: () => null);

    if (bend == null) return;

    updateBend(bend.copyWith(allowanceOverride: allowanceMm));
  }

  /// Sets or updates bend deduction override

  void setBendDeductionOverride(String bendId, double? deductionMm) {
    final bend = _document.bends.cast<FoldBendLine?>().firstWhere((b) => b?.id == bendId, orElse: () => null);

    if (bend == null) return;

    updateBend(bend.copyWith(deductionOverride: deductionMm));
  }

  /// Selects a feature from the CAD feature tree and syncs 2D/3D selection

  void selectFeature(CadFeature feature) {
    if (feature is SheetBendFeature) {
      selectBend(feature.bendLineId);
    } else if (feature is SheetBaseFeature) {
      selectFace(feature.faceId);
    } else if (feature is SheetPatternFeature) {
      selectPattern(feature.patternId);
    } else if (feature is SheetHoleFeature) {
      selectPunch(feature.punchId);
    } else if (feature is SheetCutoutFeature) {
      selectCut(feature.cutId);
    }
  }

  /// Toggles suppression / visibility of a feature from the CAD feature tree

  void toggleFeatureSuppression(CadFeature feature) {
    if (feature is SheetBendFeature) {
      toggleBendVisibility(feature.bendLineId);
    } else if (feature is SheetBaseFeature) {
      toggleFaceVisibility(feature.faceId);
    } else if (feature is SheetPatternFeature) {
      togglePatternVisibility(feature.patternId);
    } else if (feature is SheetHoleFeature) {
      togglePunchVisibility(feature.punchId);
    }
  }

  /// Sets global sheet metal blank thickness in mm.

  void setSheetThickness(double thicknessMm) {
    if (thicknessMm <= 0) return;

    _recordHistory();

    final updatedMat = _document.material.copyWith(thicknessMm: thicknessMm);

    _document = _document.copyWith(material: updatedMat);

    _recomputeMesh();

    notifyListeners();
  }

  /// Global edge chamfer setting in mm (0.0 means sharp edges)

  double get currentEdgeChamfer => _document.material.edgeChamferMm;

  /// Map of individual edge chamfers by edge key (e.g. 'F_0_1' or 'ALL')

  Map<String, double> get edgeChamfers => _document.edgeChamfers;

  /// Sets global outer edge chamfer (bevel / weld prep) across all exposed edges in mm.

  void setGlobalEdgeChamfer(double chamferMm) {
    if (chamferMm < 0) return;

    _recordHistory();

    final updatedMat = _document.material.copyWith(edgeChamferMm: chamferMm);

    _document = _document.copyWith(material: updatedMat);

    _recomputeMesh();

    notifyListeners();
  }

  /// Sets edge chamfer for a specific edge key (or 'ALL') in mm.

  void setEdgeChamfer(String edgeKey, double chamferMm) {
    _recordHistory();

    final newMap = Map<String, double>.from(_document.edgeChamfers);

    if (chamferMm <= 0.05) {
      newMap.remove(edgeKey);
    } else {
      newMap[edgeKey] = chamferMm;
    }

    _document = _document.copyWith(edgeChamfers: newMap);

    _recomputeMesh();

    notifyListeners();
  }

  /// Toggles edge chamfer on a specific edge key.

  void toggleEdgeChamfer(String edgeKey, {double? chamferMm}) {
    _recordHistory();

    final newMap = Map<String, double>.from(_document.edgeChamfers);

    if (newMap.containsKey(edgeKey)) {
      newMap.remove(edgeKey);
    } else {
      newMap[edgeKey] = chamferMm ?? (_document.material.edgeChamferMm > 0 ? _document.material.edgeChamferMm : 1.0);
    }

    _document = _document.copyWith(edgeChamfers: newMap);

    _recomputeMesh();

    notifyListeners();
  }

  /// Sets the inner bending radius (fillet) for a specific bend line.

  void setBendRadius(String bendId, double radiusMm) {
    if (radiusMm <= 0) return;

    _recordHistory();

    final newBends = _document.bends.map((b) {
      if (b.id != bendId) return b;

      return b.copyWith(radiusMm: radiusMm);
    }).toList();

    _document = _document.copyWith(bends: newBends);

    _recomputeMesh();

    notifyListeners();
  }

  /// Sets the inner bending radius (fillet) across ALL bend lines in the document and updates material default.

  void setAllBendsRadius(double radiusMm) {
    if (radiusMm <= 0) return;

    _recordHistory();

    final newBends = _document.bends.map((b) => b.copyWith(radiusMm: radiusMm)).toList();

    final updatedMat = _document.material.copyWith(defaultBendRadius: radiusMm);

    _document = _document.copyWith(bends: newBends, material: updatedMat);

    _recomputeMesh();

    notifyListeners();
  }

  void updateDocument(DsfDocument doc) {
    _recordHistory();

    _document = doc;

    _recomputeMesh();

    notifyListeners();
  }

  void loadDocument(DsfDocument doc) {
    _document = doc;

    _historyCheckpointDoc = null;

    _pendingHistoryDescription = null;

    _foldProgress = 1.0;

    _selectedBendId = null;

    _selectedCutId = null;

    _selectedPunchId = null;

    _selectedFaceId = null;

    _pendingBendStart = null;

    _rubberBandEndpoint = null;

    _pendingDimensionEntityAId = null;

    _pendingDimensionAnchorTypeA = null;

    _activeSnap = null;

    final appliedTemplateId = doc.metadata['appliedTemplate'] as String?;

    if (appliedTemplateId != null) {
      final preset = TemplateParameterDefinition.findPreset(appliedTemplateId);

      if (preset != null) {
        _activeTemplate = preset;

        final rawParams = doc.metadata['templateParameters'];

        _currentTemplateParams = {};

        if (rawParams is Map) {
          rawParams.forEach((k, v) {
            if (v is num) _currentTemplateParams[k.toString()] = v.toDouble();
          });
        }

        _templateBaselineDoc ??= TopologicalZoneMorpher.createBaselineForTemplate(preset);
      }
    } else {
      _activeTemplate = null;

      _templateBaselineDoc = null;

      _currentTemplateParams = {};
    }

    _detectedFittingMetadata = DxfFittingMetadata.fromDocument(doc);

    _portBadgeOffsets.clear();

    if (_detectedFittingMetadata?.portBadgeOffsets != null) {
      _detectedFittingMetadata!.portBadgeOffsets!.forEach((k, v) {
        if (v.length >= 2) _portBadgeOffsets[k] = Offset(v[0], v[1]);
      });
    }

    _initCmsStateFromDocument();

    _hydrateUndoStackFromDocument();

    _recomputeMesh();

    notifyListeners();
  }

  /// Activates template morphing mode for a given template definition.

  /// If [baselineDoc] is omitted, automatically instantiates a clean baseline.

  void loadTemplate(TemplateParameterDefinition template, [DsfDocument? baselineDoc]) {
    _activeTemplate = template;

    _currentTemplateParams = Map<String, double>.from(template.currentValues);

    _templateBaselineDoc = baselineDoc ?? TopologicalZoneMorpher.createBaselineForTemplate(template);

    final morphed = TopologicalZoneMorpher.morph(baselineDocument: _templateBaselineDoc!, template: _activeTemplate!, targetParameters: _currentTemplateParams);

    loadDocument(morphed);
  }

  /// Evaluates dynamic DAG formula expressions on all perforation patterns against

  /// current document parameters and regenerates patterns if parameters changed.

  void recalculatePatternsFromParameters() {
    if (_document.perforationPatterns.isEmpty) return;

    bool anyChanged = false;

    final updatedPatterns = <PerforationPattern>[];

    for (final pattern in _document.perforationPatterns) {
      if (pattern.countXExpression != null || pattern.countYExpression != null || pattern.pitchXParameter != null || pattern.pitchYParameter != null) {
        final evaluated = DependencyGraphEngine.evaluatePattern(pattern, _document.parameters);

        if (evaluated.countX != pattern.countX ||
            evaluated.countY != pattern.countY ||
            evaluated.pitchX != pattern.pitchX ||
            evaluated.pitchY != pattern.pitchY) {
          anyChanged = true;

          updatedPatterns.add(evaluated);
        } else {
          updatedPatterns.add(pattern);
        }
      } else {
        updatedPatterns.add(pattern);
      }
    }

    if (anyChanged) {
      _document = _document.copyWith(perforationPatterns: updatedPatterns);

      _recomputeMesh();

      notifyListeners();
    }
  }

  /// Updates a single parameter in the active template and re-morphs the baseline model.

  void updateTemplateParameter(String paramKey, double newValue) {
    if (_activeTemplate == null || _templateBaselineDoc == null) return;

    _recordHistory('Morph $paramKey to ${newValue.toStringAsFixed(1)} mm');

    _currentTemplateParams[paramKey] = newValue;

    // 1. DAG dependency tracking
    dependencyGraph.markDirty(paramKey);

    // 2. Evaluate dynamic parameter formulas if any exist in the active template
    for (final param in _activeTemplate!.parameters) {
      if (param.id != paramKey && param.formula != null && param.formula!.trim().isNotEmpty) {
        try {
          final evaluated = ExpressionParserEngine.evaluate(param.formula!, _currentTemplateParams);
          if (!evaluated.isNaN && !evaluated.isInfinite) {
            _currentTemplateParams[param.id] = evaluated;
            dependencyGraph.markDirty(param.id);
          }
        } catch (_) {}
      }
    }

    // 3. Morph baseline geometry via TopologicalZoneMorpher
    final morphed = TopologicalZoneMorpher.morph(baselineDocument: _templateBaselineDoc!, template: _activeTemplate!, targetParameters: _currentTemplateParams);

    final updatedParameters = Map<String, double>.from(morphed.parameters);
    updatedParameters.addAll(_currentTemplateParams);

    // 4. Dynamic perforation patterns evaluation via DependencyGraphEngine
    final rawPatterns = morphed.perforationPatterns.isNotEmpty ? morphed.perforationPatterns : _document.perforationPatterns;
    final activePatterns = rawPatterns.map((pat) {
      return DependencyGraphEngine.evaluatePattern(pat, _currentTemplateParams);
    }).toList();

    // 5. Synthesize driving geometric constraints and execute solver
    final candidateDoc = morphed.copyWith(parameters: updatedParameters, perforationPatterns: activePatterns);

    final res = GeometricConstraintSolver.solve(document: candidateDoc, parameterOverrides: _currentTemplateParams, customReferences: allReferenceGeometries);

    _document = res.success ? res.updatedDocument : candidateDoc;

    _recomputeMesh();

    notifyListeners();
  }

  /// Closes the active template morphing mode without discarding geometry changes.

  void closeTemplateMode() {
    _activeTemplate = null;

    _templateBaselineDoc = null;

    _currentTemplateParams = {};

    notifyListeners();
  }

  /// Preset loaders for standard catalog fittings

  void loadTemplateTee() => loadTemplate(TemplateParameterDefinition.cableTrayTee());

  void loadTemplateBend90() => loadTemplate(TemplateParameterDefinition.cableTrayBend90());

  void loadTemplateBend45() => loadTemplate(TemplateParameterDefinition.cableTrayBend45());

  void loadTemplateReducer() => loadTemplate(TemplateParameterDefinition.cableTrayReducer());

  void loadTemplateCross() => loadTemplate(TemplateParameterDefinition.cableTrayCross());

  void loadTemplateStraight() => loadTemplate(TemplateParameterDefinition.cableTrayStraight());

  void loadDxf(String dxfString, {String productType = 'Imported DXF'}) {
    final imported = DxfDsfImporter.importDxf(dxfString, productType: productType);

    loadDocument(imported);
  }

  Future<void> loadDsf(String dsfJsonString) async {
    final doc = DsfDocument.parseJsonString(dsfJsonString);
    loadDocument(doc);
    if (doc.isCmsDrawing &&
        doc.bends.isNotEmpty &&
        (_persistentCmsPorts.isEmpty || doc.metadata['cmsWorkflow']?['stageIndex'] == 1)) {
      await continueCmsPortMapping();
    }
  }

  void loadSampleCableTray({double width = 100, double height = 50, double length = 1000}) {
    final doc = DsfDocument.sampleCableTray(width: width, height: height, length: length, flange: 15.0, thickness: 1.5);

    loadDocument(doc);
  }

  /// Stamps an industrial CMS cable tray perforation array (obround slots) across the bed floor or target face.

  void stampCableTrayPerforations({
    double slotWidth = 7.0,

    double slotLength = 30.0,

    int rows = 2,

    double pitchY = 80.0,

    double sideMargin = 25.0,

    double endMargin = 50.0,

    double rotationDeg = 0.0,

    String? faceId,

    bool staggered = true,

    String layer = 'HOLES',
  }) {
    autoNestPerforationOnFace(
      faceId: faceId,

      slotWidth: slotWidth,

      slotLength: slotLength,

      pitchY: pitchY,

      endMargin: endMargin,

      rotationDeg: rotationDeg,

      staggered: staggered,

      overrideCols: rows > 0 ? rows : null,
    );
  }

  /// Stamps standard CMS side-rail coupler slot pairs at the ends of the side walls.

  void stampSideRailCouplers({
    double slotWidth = 7.0,

    double slotLength = 20.0,

    double endOffset = 25.0,

    double verticalSpacing = 25.0,

    String layer = 'HOLES',
  }) {
    _recordHistory();

    final newCouplers = CncTurretEngine.generateSideRailCouplerSlots(
      doc: _document,

      slotWidth: slotWidth,

      slotLength: slotLength,

      endOffset: endOffset,

      verticalSpacing: verticalSpacing,

      layer: layer,
    );

    if (newCouplers.isNotEmpty) {
      _document = _document.copyWith(punches: [..._document.punches, ...newCouplers]);

      _recomputeMesh();

      notifyListeners();
    }
  }

  /// Toggles visibility of an individual drawing component layer.

  void toggleLayerVisibility(String layerName) {
    _recordHistory();

    final updated = _document.effectiveLayers.map((l) {
      if (l.name != layerName) return l;

      return l.copyWith(isVisible: !l.isVisible);
    }).toList();

    _document = _document.copyWith(layers: updated);

    _recomputeMesh();

    notifyListeners();
  }

  /// Sets the display/export color of a layer.

  void setLayerColor(String layerName, int colorHex) {
    _recordHistory();

    final updated = _document.effectiveLayers.map((l) {
      if (l.name != layerName) return l;

      return l.copyWith(colorHex: colorHex);
    }).toList();

    _document = _document.copyWith(layers: updated);

    _recomputeMesh();

    notifyListeners();
  }

  /// Sets the line style of a layer (CONTINUOUS, DASHED, etc.).

  void setLayerLineType(String layerName, String lineType) {
    _recordHistory();

    final updated = _document.effectiveLayers.map((l) {
      if (l.name != layerName) return l;

      return l.copyWith(lineType: lineType);
    }).toList();

    _document = _document.copyWith(layers: updated);

    _recomputeMesh();

    notifyListeners();
  }

  /// Toggles lock state of an individual drawing component layer.

  void toggleLayerLock(String layerName) {
    _recordHistory();

    final updated = _document.effectiveLayers.map((l) {
      if (l.name != layerName) return l;

      return l.copyWith(isLocked: !l.isLocked);
    }).toList();

    _document = _document.copyWith(layers: updated);

    notifyListeners();
  }

  /// Returns total number of drawing entities currently assigned to a layer.
  int getEntityCountForLayer(String layerName) {
    int count = 0;
    final outlineLayer = _document.outerContourLayer.isNotEmpty ? _document.outerContourLayer : 'OUTLINE';
    if (layerName == outlineLayer) {
      count += _document.outerContour.length;
    }
    for (final b in _document.bends) {
      final bLayer = b.layer.isNotEmpty ? b.layer : (b.direction == BendDirection.up ? 'BEND_UP' : 'BEND_DOWN');

      if (bLayer == layerName) count++;
    }
    for (final c in _document.cutLines) {
      final cLayer = c.layer.isNotEmpty ? c.layer : 'CUT';
      if (cLayer == layerName) count++;
    }
    for (final p in _document.punches) {
      final pLayer = p.layer.isNotEmpty ? p.layer : 'HOLES';

      if (pLayer == layerName) count++;
    }
    for (final f in _document.faces) {
      final fLayer = f.layer.isNotEmpty ? f.layer : 'FACES';
      if (fLayer == layerName) count++;
    }
    return count;
  }

  void _recomputeMesh() {
    _cachedMesh = KinematicFoldEngine.foldDocument(_document, foldProgress: _foldProgress, curveResolution3D: _curveResolution3D);
    _cachedFlatPattern = FlatPatternEngine.computeFlatPattern(_document);
    _syncPersistentCmsPortsWithCurrentMesh();
  }

  void _syncPersistentCmsPortsWithCurrentMesh() {
    if (_isTeachScalingActive || _foldProgress < 0.99) return;
    final cmsRaw = _document.metadata['cmsTemplate'];
    if (cmsRaw is! Map || _persistentCmsPorts.isEmpty) return;
    if (_cachedMesh == null || _cachedMesh!.polygons.isEmpty) return;

    try {
      final contract = CmsProductContract.lookup(
        cmsRaw['productType'] as String?,
        cmsRaw['variation'] as String?,
      ) ?? cmsGuidedController.state.contract ?? CmsProductContract.bend45;

      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: _document,
        foldResult: _cachedMesh!,
      );
      if (rawOpenings.length == _persistentCmsPorts.length) {
        final measured = rawOpenings.map(
          (r) => CmsOpeningPlaneAnalyzer.analyze(
            raw: r,
            document: _document,
            foldResult: _cachedMesh!,
          ),
        ).toList();
        final match = CmsPortMatcher.match(
          measuredOpenings: measured,
          contract: contract,
        );
        if (match.matchedPorts.length == _persistentCmsPorts.length) {
          bool needsUpdate = false;
          for (int i = 0; i < match.matchedPorts.length; i++) {
            final current = _persistentCmsPorts[i];
            final fresh = match.matchedPorts[i];
            if ((current.width - fresh.width).abs() > 0.5 ||
                (current.height - fresh.height).abs() > 0.5 ||
                (current.center.x - fresh.center.x).abs() > 0.5 ||
                (current.center.y - fresh.center.y).abs() > 0.5 ||
                (current.center.z - fresh.center.z).abs() > 0.5) {
              needsUpdate = true;
              break;
            }
          }
          if (needsUpdate) {
            final updated = <CmsPhysicalPort>[];
            for (int i = 0; i < match.matchedPorts.length; i++) {
              final fresh = match.matchedPorts[i];
              final old = _persistentCmsPorts[i];
              updated.add(fresh.copyWith(
                id: old.id,
                index: old.index,
                role: old.role,
                suggestedRole: old.suggestedRole,
                roleSource: old.roleSource,
                suggestionReason: old.suggestionReason,
              ));
            }
            _persistentCmsPorts = updated;
            final meta = Map<String, dynamic>.from(_document.metadata);
            final cms = Map<String, dynamic>.from(meta['cmsTemplate'] as Map);
            cms['ports'] = updated.map((p) => p.toJson()).toList();
            meta['cmsTemplate'] = cms;
            _document = _document.copyWith(metadata: meta);
          }
        }
      }
    } catch (_) {
      // Silently ignore if mesh opening detection cannot resolve
    }
  }

  bool _isPointInPoly(CadPoint2D pt, List<CadPoint2D> poly) {
    if (poly.length < 3) return false;

    bool inside = false;

    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].x, yi = poly[i].y;
      final xj = poly[j].x, yj = poly[j].y;
      final intersect = ((yi > pt.y) != (yj > pt.y)) && (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  double _distToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y);
    if (l2 < 1e-4) return p.distanceTo(a);
    final t = math.max(0.0, math.min(1.0, ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2));
    final proj = CadPoint2D(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
    return p.distanceTo(proj);
  }
}
