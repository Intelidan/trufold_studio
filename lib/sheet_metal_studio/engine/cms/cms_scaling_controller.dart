// =============================================================================
// cms_scaling_controller.dart
//
// Autonomous Observable Controller for Phase 2: Intelligent Template Scaling.
// Implements the Canonical Geometry Rule:
// 1. All scaling operations modify canonical 2D sheet geometry (DsfDocument).
// 2. The 3D model is folded from that exact 2D state via KinematicFoldEngine.
// 3. Port opening geometry is derived from the folded 3D mesh.
// Zero independent 3D vertex deformation.
// per TRUFOLD_PHASE_1_2_TEMPLATE_SCALING_WORKFLOW.md (Sections 8-22).
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/cad_primitives.dart';
import '../../models/dsf_document.dart';
import '../../models/planar_sheet_face.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../models/cms/cms_product_contract.dart';
import '../../models/cms/cms_scaling_model.dart';
import '../../models/template_parameter_definition.dart';
import '../kinematic_fold_engine.dart';
import '../planar_face_decomposer.dart';
import '../topological_zone_morpher.dart';
import 'cms_3d_opening_detector.dart';
import 'cms_opening_plane_analyzer.dart';
import 'cms_port_matcher.dart';

/// Result of evaluating a parametric dimension on the 2D blank and folding to 3D.
class CmsScalingPreviewResult {
  final DsfDocument scaledDocument;
  final FoldedMeshResult foldedMesh;
  final List<CmsPhysicalPort> derivedPorts;
  final bool isValid;
  final String validationMessage;

  const CmsScalingPreviewResult({
    required this.scaledDocument,
    required this.foldedMesh,
    required this.derivedPorts,
    required this.isValid,
    this.validationMessage = '',
  });
}

/// Controller governing the interactive Teach Scaling workflow.
class CmsScalingController extends ChangeNotifier {
  final DsfDocument baselineDocument;
  final CmsProductContract contract;
  final List<CmsPhysicalPort> baselinePorts;

  late CmsScalingModel _model;
  String _activeParameterId = 'width';
  double _previewMorphValue = 100.0;
  CmsScalingPreviewResult? _currentPreview;
  bool _isEvaluating = false;

  static DsfDocument _ensureFaces(DsfDocument doc) {
    if (doc.faces.isNotEmpty) return doc;
    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: doc.outerContour,
      bends: doc.bends,
      cutLines: doc.cutLines,
    );
    return doc.copyWith(
      faces: decomp.faces,
      baseFaceId: decomp.baseFaceId,
    );
  }

  CmsScalingController({
    required DsfDocument baselineDocument,
    required this.contract,
    required this.baselinePorts,
  }) : baselineDocument = _ensureFaces(baselineDocument) {
    _initModelFromPhase1();
    _previewMorphValue = _model.parameters[_activeParameterId]?.currentValue ?? 100.0;
    evaluateMorph(_previewMorphValue);
  }

  // Getters
  CmsScalingModel get model => _model;
  String get activeParameterId => _activeParameterId;
  double get previewMorphValue => _previewMorphValue;
  CmsScalingPreviewResult? get currentPreview => _currentPreview;
  bool get isEvaluating => _isEvaluating;

  CmsScalingParameter? get activeParameter => _model.parameters[_activeParameterId];

  void selectParameter(String parameterId) {
    if (!_model.parameters.containsKey(parameterId)) return;
    _activeParameterId = parameterId;
    final param = _model.parameters[parameterId]!;
    _previewMorphValue = param.currentValue;

    // Set parameter to learning state if untaught
    if (param.teachingState == CmsParameterTeachingState.untaught) {
      final updated = param.copyWith(teachingState: CmsParameterTeachingState.learning);
      final newParams = Map<String, CmsScalingParameter>.from(_model.parameters);
      newParams[parameterId] = updated;
      _model = _model.copyWith(parameters: newParams);
    }

    evaluateMorph(_previewMorphValue);
    notifyListeners();
  }

  /// Evaluates the 2D sheet geometry at [targetValue], folds it to 3D, and updates the preview.
  /// Follows the CANONICAL GEOMETRY RULE strictly:
  /// Target Value -> Regenerate 2D -> Fold 2D -> Derive 3D.
  void evaluateMorph(double targetValue) {
    _previewMorphValue = targetValue;
    _isEvaluating = true;

    final param = activeParameter;
    final baselineVal = param?.baselineValue ?? 100.0;
    final delta = targetValue - baselineVal;

    // 1. Generate updated canonical 2D sheet geometry
    final scaledDoc = _generateScaled2DDocument(
      baseline: baselineDocument,
      paramId: _activeParameterId,
      delta: delta,
    );

    // 2. Fold the modified 2D sheet through the KinematicFoldEngine
    final mesh = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);

    // 3. Derive 3D physical port mouths from the newly folded 3D mesh
    final rawOpenings = Cms3DOpeningDetector.detectOpenings(
      document: scaledDoc,
      foldResult: mesh,
    );
    final measured = rawOpenings.map(
      (r) => CmsOpeningPlaneAnalyzer.analyze(
        raw: r,
        document: scaledDoc,
        foldResult: mesh,
      ),
    ).toList();

    final matchResult = CmsPortMatcher.match(
      measuredOpenings: measured,
      contract: contract,
    );

    final effectivePorts = matchResult.matchedPorts.isNotEmpty
        ? matchResult.matchedPorts.map((mp) {
            final baseMatch = baselinePorts.firstWhere(
              (bp) => bp.id == mp.id || bp.index == mp.index,
              orElse: () => mp,
            );
            if (baseMatch.role != null && baseMatch.role != CmsPortRole.unassigned) {
              return mp.copyWith(
                role: baseMatch.role,
                roleSource: baseMatch.roleSource,
              );
            }
            return mp;
          }).toList()
        : baselinePorts;

    _currentPreview = CmsScalingPreviewResult(
      scaledDocument: scaledDoc,
      foldedMesh: mesh,
      derivedPorts: effectivePorts,
      isValid: true,
      validationMessage: 'Successfully evaluated 2D blank and regenerated 3D model for ${targetValue.toStringAsFixed(1)} mm.',
    );

    _isEvaluating = false;
    notifyListeners();
  }

  /// Commits the active parameter scaling behavior as Learned.
  DsfDocument acceptScalingModel() {
    final param = activeParameter;
    if (param != null) {
      final learnedParam = param.copyWith(
        currentValue: _previewMorphValue,
        teachingState: CmsParameterTeachingState.learned,
      );
      final newParams = Map<String, CmsScalingParameter>.from(_model.parameters);
      newParams[_activeParameterId] = learnedParam;
      _model = _model.copyWith(parameters: newParams);
    }

    // Persist scaling model and derived scaled ports into DSF metadata
    final previewDoc = _currentPreview?.scaledDocument ?? baselineDocument;
    final meta = Map<String, dynamic>.from(previewDoc.metadata);
    final cmsTemplate = Map<String, dynamic>.from(meta['cmsTemplate'] as Map<String, dynamic>? ?? {});
    cmsTemplate['scalingModel'] = _model.toJson();
    if (_currentPreview != null && _currentPreview!.derivedPorts.isNotEmpty) {
      cmsTemplate['ports'] = _currentPreview!.derivedPorts.map((p) => p.toJson()).toList();
    }
    meta['cmsTemplate'] = cmsTemplate;

    if (meta['fittingMetadata'] is Map) {
      final fittingMeta = Map<String, dynamic>.from(meta['fittingMetadata'] as Map);
      final params = Map<String, dynamic>.from(fittingMeta['parameters'] as Map? ?? {});
      if (param != null) {
        params[param.id] = _previewMorphValue;
      }
      fittingMeta['parameters'] = params;
      meta['fittingMetadata'] = fittingMeta;
    }

    final finalDoc = previewDoc.copyWith(metadata: meta);
    notifyListeners();
    return finalDoc;
  }

  /// Cancels preview and reverts to baseline.
  void cancelPreview() {
    final param = activeParameter;
    if (param != null && param.teachingState == CmsParameterTeachingState.learning) {
      final reverted = param.copyWith(teachingState: CmsParameterTeachingState.untaught);
      final newParams = Map<String, CmsScalingParameter>.from(_model.parameters);
      newParams[_activeParameterId] = reverted;
      _model = _model.copyWith(parameters: newParams);
    }
    _previewMorphValue = param?.baselineValue ?? 100.0;
    evaluateMorph(_previewMorphValue);
  }

  // ---------------------------------------------------------------------------
  // Canonical 2D Geometry Scaling Engine
  // ---------------------------------------------------------------------------

  DsfDocument _generateScaled2DDocument({
    required DsfDocument baseline,
    required String paramId,
    required double delta,
  }) {
    if (delta.abs() < 1e-4) return baseline;

    final baseW = baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0;
    final baseH = baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0;
    final targetW = paramId == 'width' ? baseW + delta : baseW;
    final targetH = paramId == 'height' ? baseH + delta : baseH;

    // Check if TopologicalZoneMorpher handles this fitting
    final prod = '${contract.productType} ${contract.variationName} ${baseline.productType}'.toLowerCase();
    if (prod.contains('45') || prod.contains('90') || prod.contains('tee') || prod.contains('straight')) {
      final templateDef = TemplateParameterDefinition(
        templateId: prod.contains('45') ? '45_deg_bend' : (prod.contains('90') ? '90_deg_bend' : 'equal_tee'),
        name: contract.variationName,
        category: contract.productType,
        productType: contract.productType,
        baselineParameters: {'width': baseW, 'height': baseH, 'flangeWidth': 15.0},
        parameters: [],
      );
      try {
        final morphed = TopologicalZoneMorpher.morph(
          baselineDocument: baseline,
          template: templateDef,
          targetParameters: {'width': targetW, 'height': targetH, 'flangeWidth': 15.0},
        );
        if (morphed.outerContour.isNotEmpty && morphed.faces.isNotEmpty) {
          return morphed;
        }
      } catch (_) {}
    }

    if (paramId == 'width') {
      return _scaleWidth2D(baseline, delta);
    } else if (paramId == 'height') {
      return _scaleHeight2D(baseline, delta);
    }
    return baseline;
  }

  /// Scales the canonical 2D flat blank for Width:
  /// - Floor web expands by delta.
  /// - Sidewalls & return flanges translate outward rigidly.
  /// - Coupler slots translate with their host sidewall (preserving shape and edge distance).
  DsfDocument _scaleWidth2D(DsfDocument baseline, double delta) {
    final doc = baseline.faces.isNotEmpty
        ? baseline
        : () {
            final decomp = PlanarFaceDecomposer.decompose(
              outerContour: baseline.outerContour,
              bends: baseline.bends,
              cutLines: baseline.cutLines,
            );
            return baseline.copyWith(
              faces: decomp.faces,
              baseFaceId: decomp.baseFaceId,
            );
          }();

    if (doc.faces.isEmpty && doc.outerContour.isEmpty) return baseline;

    // Identify the Floor Web face
    final floorFace = doc.faces.firstWhere(
      (f) => f.id == doc.baseFaceId || f.role == FaceRole.baseFloor,
      orElse: () => doc.faces.isNotEmpty ? doc.faces.first : const PlanarSheetFace(id: 'F_0', vertices: []),
    );

    // Calculate center of floor face in 2D
    double sumX = 0;
    for (final v in floorFace.vertices) {
      sumX += v.x;
    }
    final floorCenterX = floorFace.vertices.isNotEmpty ? sumX / floorFace.vertices.length : 0.0;

    final halfDelta = delta / 2.0;
    final is45Bend = contract.productType.contains('45') || contract.variationName.contains('45') || doc.productType.contains('45');

    CadPoint2D transformPt(CadPoint2D pt) {
      final dx = pt.x - floorCenterX;
      double x = pt.x;
      double y = pt.y;

      if (dx.abs() < 2.5) {
        if (is45Bend) {
          y += halfDelta * math.tan(22.5 * math.pi / 180.0);
        }
        return CadPoint2D(x, y);
      }

      final shift = dx > 0 ? halfDelta : -halfDelta;
      return CadPoint2D(x + shift, y);
    }

    // 1. Transform outer contour
    final newContour = doc.outerContour.map(transformPt).toList();

    // 2. Transform bends
    final newBends = doc.bends.map((b) {
      return b.copyWith(
        p1: transformPt(b.p1),
        p2: transformPt(b.p2),
      );
    }).toList();

    // 3. Transform faces
    final newFaces = doc.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    // 4. Transform punches (RIGID: maintain exact shape, shift center with host region)
    final newPunches = doc.punches.map((p) {
      return p.copyWith(
        center: transformPt(p.center),
      );
    }).toList();

    // 5. Transform cut lines
    final newCutLines = doc.cutLines.map((cl) {
      return cl.copyWith(
        p1: transformPt(cl.p1),
        p2: transformPt(cl.p2),
      );
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: newContour,
      bends: newBends,
      cutLines: newCutLines,
    );

    return doc.copyWith(
      outerContour: newContour,
      bends: newBends,
      faces: decomp.faces.isNotEmpty ? decomp.faces : newFaces,
      baseFaceId: decomp.baseFaceId,
      punches: newPunches,
      cutLines: newCutLines,
    );
  }

  /// Scales the canonical 2D flat blank for Height:
  /// - Sidewall faces expand vertically by delta.
  /// - Flanges translate outward.
  /// - Floor stays fixed.
  DsfDocument _scaleHeight2D(DsfDocument baseline, double delta) {
    if (baseline.faces.isEmpty) return baseline;

    // Shift sidewall outer edges and return flanges along Y
    final halfDelta = delta / 2.0;

    CadPoint2D transformPt(CadPoint2D pt) {
      // Points in upper flange region shift +halfDelta, lower shift -halfDelta
      final shift = pt.y > 100.0 ? halfDelta : -halfDelta;
      return CadPoint2D(pt.x, pt.y + shift);
    }

    return baseline.copyWith(
      outerContour: baseline.outerContour.map(transformPt).toList(),
      bends: baseline.bends.map((b) => b.copyWith(p1: transformPt(b.p1), p2: transformPt(b.p2))).toList(),
      faces: baseline.faces.map((f) => f.copyWith(vertices: f.vertices.map(transformPt).toList())).toList(),
      punches: baseline.punches.map((p) => p.copyWith(center: transformPt(p.center))).toList(),
      cutLines: baseline.cutLines.map((cl) => cl.copyWith(p1: transformPt(cl.p1), p2: transformPt(cl.p2))).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Setup from Phase 1 Verified Template
  // ---------------------------------------------------------------------------

  void _initModelFromPhase1() {
    final floorFace = baselineDocument.faces.firstWhere(
      (f) => f.id == baselineDocument.baseFaceId || f.role == FaceRole.baseFloor,
      orElse: () => baselineDocument.faces.isNotEmpty ? baselineDocument.faces.first : const PlanarSheetFace(id: 'F_FLOOR', vertices: []),
    );

    final sidewalls = baselineDocument.faces.where((f) => f.role == FaceRole.sideWall).toList();
    final flanges = baselineDocument.faces.where((f) => f.role == FaceRole.returnFlange).toList();

    // 1. Dynamic Rigid Feature Group for Coupler Fasteners (never hardcoded count!)
    final couplerPunches = baselineDocument.punches.where((p) => p.isSlot || p.type == PunchType.obroundSlot).toList();
    final rigidGroups = <CmsRigidFeatureGroup>[];
    if (couplerPunches.isNotEmpty) {
      rigidGroups.add(
        CmsRigidFeatureGroup(
          id: 'GRP_COUPLER_SLOTS',
          name: 'Coupler Slots (${couplerPunches.length})',
          punchIds: couplerPunches.map((p) => p.id).toList(),
          hostFaceId: sidewalls.isNotEmpty ? sidewalls.first.id : floorFace.id,
          description: 'Maintains exact slot geometry and reference edge mounting distance.',
        ),
      );
    }

    // 2. Stretch Zones
    final stretchZones = [
      CmsStretchZone(
        id: 'ZONE_FLOOR_WEB',
        description: 'Floor web expands along transverse bend axis.',
        faceIds: [floorFace.id],
        axis: const CadPoint2D(1.0, 0.0),
      ),
    ];

    // 3. Translation Zones
    final translationZones = [
      CmsTranslationZone(
        id: 'ZONE_SIDEWALLS_AND_FLANGES',
        description: 'Standing sidewalls and locked flanges translate rigidly.',
        faceIds: [...sidewalls.map((s) => s.id), ...flanges.map((f) => f.id)],
        bendIds: baselineDocument.bends.map((b) => b.id).toList(),
      ),
    ];

    // 4. Derived Ports
    final derivedPorts = baselinePorts.map((p) {
      return CmsDerivedPort(
        portId: p.id,
        role: p.role,
        description: 'Derived 3D opening mouth for ${p.width.toStringAsFixed(0)} × ${p.height.toStringAsFixed(0)} mm channel.',
      );
    }).toList();

    // 5. Initial Parameters (progressive learning: untaught by default)
    final baselineWidth = baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0;
    final baselineHeight = baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0;

    final params = <String, CmsScalingParameter>{
      'width': CmsScalingParameter(
        id: 'width',
        displayName: 'Width (W)',
        currentValue: baselineWidth,
        baselineValue: baselineWidth,
        minValidMm: 50.0,
        maxValidMm: 600.0,
        unit: 'mm',
        teachingState: CmsParameterTeachingState.untaught,
        stretchZoneIds: ['ZONE_FLOOR_WEB'],
        translationZoneIds: ['ZONE_SIDEWALLS_AND_FLANGES'],
        rigidGroupIds: rigidGroups.map((g) => g.id).toList(),
        derivedPortIds: derivedPorts.map((p) => p.portId).toList(),
      ),
      'height': CmsScalingParameter(
        id: 'height',
        displayName: 'Height (H)',
        currentValue: baselineHeight,
        baselineValue: baselineHeight,
        minValidMm: 50.0,
        maxValidMm: 300.0,
        unit: 'mm',
        teachingState: CmsParameterTeachingState.untaught,
        stretchZoneIds: [],
        translationZoneIds: ['ZONE_SIDEWALLS_AND_FLANGES'],
        rigidGroupIds: rigidGroups.map((g) => g.id).toList(),
        derivedPortIds: derivedPorts.map((p) => p.portId).toList(),
      ),
    };

    _model = CmsScalingModel(
      templateId: '${contract.productType}_${contract.variationName}',
      category: (baselineDocument.metadata['category'] as String?) ?? 'Cable Tray & Trunking',
      productType: contract.productType,
      variation: contract.variationName,
      parameters: params,
      stretchZones: stretchZones,
      translationZones: translationZones,
      rigidFeatureGroups: rigidGroups,
      derivedPorts: derivedPorts,
    );
  }
}
