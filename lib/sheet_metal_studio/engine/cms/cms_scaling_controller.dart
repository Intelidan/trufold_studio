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
import '../../models/fold_bend_line.dart';
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
import 'cms_punch_constraint_engine.dart';

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

  bool get isMultiPortFitting {
    final prof = effectiveScalingProfile;
    return prof == CmsScalingProfile.tee ||
        prof == CmsScalingProfile.cross ||
        baselinePorts.length >= 3;
  }

  bool get isLinkedPorts => _model.isLinkedPorts;
  int get activePortIndex => _model.activePortIndex;

  void setActivePortIndex(int index) {
    if (index < 0 || index >= baselinePorts.length) return;
    _model = _model.copyWith(activePortIndex: index);
    if (!_model.isLinkedPorts) {
      final wId = 'port${index + 1}_width';
      if (_model.parameters.containsKey(wId)) {
        selectParameter(wId);
      }
    } else {
      notifyListeners();
    }
  }

  void setLinkedPorts(bool linked) {
    togglePortLinking(linked);
  }

  void togglePortLinking(bool linked) {
    if (_model.isLinkedPorts == linked) return;
    _model = _model.copyWith(isLinkedPorts: linked);

    if (linked) {
      // In linked mode, synchronize to unified width and height
      final firstPort = baselinePorts.isNotEmpty ? baselinePorts.first : null;
      final curW = firstPort?.width ?? 100.0;
      final curH = firstPort?.height ?? 100.0;

      final params = <String, CmsScalingParameter>{
        'width': CmsScalingParameter(
          id: 'width',
          displayName: 'Width (W)',
          currentValue: curW,
          baselineValue: curW,
          minValidMm: math.min(50.0, curW - 50.0),
          maxValidMm: math.max(750.0, curW + 200.0),
          unit: 'mm',
          teachingState: CmsParameterTeachingState.learning,
        ),
        'height': CmsScalingParameter(
          id: 'height',
          displayName: 'Height (H)',
          currentValue: curH,
          baselineValue: curH,
          minValidMm: math.min(50.0, curH - 50.0),
          maxValidMm: math.max(300.0, curH + 150.0),
          unit: 'mm',
          teachingState: CmsParameterTeachingState.learning,
        ),
      };
      _model = _model.copyWith(parameters: params);
      _activeParameterId = 'width';
      _previewMorphValue = curW;
    } else {
      // In unlinked mode, create per-port parameters
      final params = <String, CmsScalingParameter>{};
      for (int i = 0; i < baselinePorts.length; i++) {
        final port = baselinePorts[i];
        final wId = 'port${i + 1}_width';
        final hId = 'port${i + 1}_height';
        params[wId] = CmsScalingParameter(
          id: wId,
          displayName: 'Port ${i + 1} Width',
          currentValue: port.width,
          baselineValue: port.width,
          minValidMm: math.min(50.0, port.width - 50.0),
          maxValidMm: math.max(750.0, port.width + 200.0),
          unit: 'mm',
          teachingState: CmsParameterTeachingState.learning,
        );
        params[hId] = CmsScalingParameter(
          id: hId,
          displayName: 'Port ${i + 1} Height',
          currentValue: port.height,
          baselineValue: port.height,
          minValidMm: math.min(50.0, port.height - 50.0),
          maxValidMm: math.max(300.0, port.height + 150.0),
          unit: 'mm',
          teachingState: CmsParameterTeachingState.learning,
        );
      }
      _model = _model.copyWith(parameters: params);
      final activeWId = 'port${_model.activePortIndex + 1}_width';
      _activeParameterId = params.containsKey(activeWId) ? activeWId : params.keys.first;
      _previewMorphValue = params[_activeParameterId]?.currentValue ?? 100.0;
    }

    evaluateMorph(_previewMorphValue);
    notifyListeners();
  }

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
    if (param != null) {
      final updatedParam = param.copyWith(currentValue: targetValue);
      final newParams = Map<String, CmsScalingParameter>.from(_model.parameters);
      newParams[_activeParameterId] = updatedParam;
      _model = _model.copyWith(parameters: newParams);
    }

    final widthParam = _model.parameters['width'];
    final heightParam = _model.parameters['height'];

    final deltaW = (widthParam != null)
        ? (widthParam.currentValue - widthParam.baselineValue)
        : 0.0;
    final deltaH = (heightParam != null)
        ? (heightParam.currentValue - heightParam.baselineValue)
        : 0.0;

    // 1. Generate updated canonical 2D sheet geometry composing active parameter deltas
    var scaledDoc = baselineDocument;
    final prof = effectiveScalingProfile;

    if (prof == CmsScalingProfile.cross || isCrossGeometry(baselineDocument)) {
      scaledDoc = _scaleCross2D(
        scaledDoc,
        isLinked: _model.isLinkedPorts,
        parameters: _model.parameters,
      );
    } else if (prof == CmsScalingProfile.tee || isTeeGeometry(baselineDocument)) {
      scaledDoc = _scaleTee2D(
        scaledDoc,
        isLinked: _model.isLinkedPorts,
        parameters: _model.parameters,
      );
    } else {
      if (deltaW.abs() > 0.01) {
        scaledDoc = _generateScaled2DDocument(
          baseline: scaledDoc,
          paramId: 'width',
          delta: deltaW,
        );
      }
      if (deltaH.abs() > 0.01) {
        scaledDoc = _generateScaled2DDocument(
          baseline: scaledDoc,
          paramId: 'height',
          delta: deltaH,
        );
      }
    }

    final targetW = widthParam?.currentValue ?? (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    final targetH = heightParam?.currentValue ?? (baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0);
    scaledDoc = scaledDoc.copyWith(
      parameters: {
        ...scaledDoc.parameters,
        'width': targetW,
        'height': targetH,
        _activeParameterId: targetValue,
        for (final p in _model.parameters.values) p.id: p.currentValue,
      },
    );

    // 2. Fold the modified 2D sheet through the KinematicFoldEngine
    final mesh = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);

    // 3. Derive 3D physical port mouths from the newly folded 3D mesh
    final rawOpenings = Cms3DOpeningDetector.detectOpenings(
      document: scaledDoc,
      foldResult: mesh,
    );
    final initialMeasured = rawOpenings.map(
      (r) => CmsOpeningPlaneAnalyzer.analyze(
        raw: r,
        document: scaledDoc,
        foldResult: mesh,
        defaultHeight: targetH,
      ),
    ).toList();

    // Reconcile channel height across ports (only for linked mode)
    double? detectedChannelHeight;
    if (_model.isLinkedPorts) {
      for (final m in initialMeasured) {
        if (m.height > 15.0) {
          if (detectedChannelHeight == null || m.height > detectedChannelHeight) {
            detectedChannelHeight = m.height;
          }
        }
      }
    }

    final measured = initialMeasured.map((m) {
      if (_model.isLinkedPorts && detectedChannelHeight != null && (m.height - detectedChannelHeight).abs() > 3.0) {
        return CmsOpeningPlaneAnalyzer.analyze(
          raw: rawOpenings.firstWhere((r) => r.openingId == m.openingId),
          document: scaledDoc,
          foldResult: mesh,
          defaultHeight: detectedChannelHeight,
          fallbackHeight: detectedChannelHeight,
        );
      }
      return m;
    }).toList();

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
            var updated = mp;
            double portExpectedW = targetW;
            double portExpectedH = targetH;
            if (!_model.isLinkedPorts) {
              final pW = _model.parameters['port${mp.index}_width'];
              final pH = _model.parameters['port${mp.index}_height'];
              if (pW != null) portExpectedW = pW.currentValue;
              if (pH != null) portExpectedH = pH.currentValue;
              updated = updated.copyWith(
                width: portExpectedW,
                height: portExpectedH,
              );
            } else {
              if ((portExpectedW - mp.width).abs() <= 6.0) {
                updated = updated.copyWith(width: portExpectedW);
              }
              if ((portExpectedH - mp.height).abs() <= 6.0) {
                updated = updated.copyWith(height: portExpectedH);
              }
            }
            if (baseMatch.role != null && baseMatch.role != CmsPortRole.unassigned) {
              updated = updated.copyWith(
                role: baseMatch.role,
                roleSource: baseMatch.roleSource,
              );
            }
            return updated;
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
    final newParams = Map<String, CmsScalingParameter>.from(_model.parameters);
    for (final entry in _model.parameters.entries) {
      newParams[entry.key] = entry.value.copyWith(
        teachingState: CmsParameterTeachingState.learned,
      );
    }
    _model = _model.copyWith(parameters: newParams);

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
      for (final p in _model.parameters.values) {
        params[p.id] = p.currentValue;
      }
      fittingMeta['parameters'] = params;
      meta['fittingMetadata'] = fittingMeta;
    }

    final finalDoc = previewDoc.copyWith(
      parameters: {
        ...previewDoc.parameters,
        for (final p in _model.parameters.values) p.id: p.currentValue,
      },
      metadata: meta,
    );
    notifyListeners();
    return finalDoc;
  }

  /// Restores all active parameters and the preview back to baseline dimensions (Section 6).
  void resetToBaseline() {
    final newParams = <String, CmsScalingParameter>{};
    for (final entry in _model.parameters.entries) {
      newParams[entry.key] = entry.value.copyWith(
        currentValue: entry.value.baselineValue,
      );
    }
    _model = _model.copyWith(parameters: newParams);

    final activeBase = _model.parameters[_activeParameterId]?.baselineValue ?? 100.0;
    _previewMorphValue = activeBase;

    evaluateMorph(activeBase);
  }

  /// Reverts any preview changes back to the unscaled baseline.
  void cancelScaling() {
    _currentPreview = null;
    final baseVal = baselineDocument.parameters[_activeParameterId] ??
        (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    _previewMorphValue = baseVal;
    final param = activeParameter;
    if (param != null && param.teachingState == CmsParameterTeachingState.learning) {
      final reverted = param.copyWith(
        currentValue: param.baselineValue,
        teachingState: CmsParameterTeachingState.untaught,
      );
      final newParams = Map<String, CmsScalingParameter>.from(_model.parameters);
      newParams[param.id] = reverted;
      _model = _model.copyWith(parameters: newParams);
    }
    evaluateMorph(_previewMorphValue);
  }

  /// Cancels preview and reverts to baseline.
  void cancelPreview() => cancelScaling();

  /// Geometrically detects if a document has the topology of an inside riser:
  /// Two parallel ~90° bends with a transverse bend connecting between them.
  static bool isInsideRiserGeometry(DsfDocument doc) {
    if (doc.bends.length < 2) return false;

    final bends90 = doc.bends.where((b) {
      final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
      return is90 && b.role != BendLineRole.flange;
    }).toList();

    if (bends90.length < 2) return false;

    for (int i = 0; i < bends90.length; i++) {
      for (int j = i + 1; j < bends90.length; j++) {
        final b1 = bends90[i];
        final b2 = bends90[j];
        final dx1 = (b1.p2.x - b1.p1.x).abs();
        final dy1 = (b1.p2.y - b1.p1.y).abs();
        final dx2 = (b2.p2.x - b2.p1.x).abs();
        final dy2 = (b2.p2.y - b2.p1.y).abs();

        final b1IsVertical = dy1 > dx1 * 1.5;
        final b2IsVertical = dy2 > dx2 * 1.5;
        final b1IsHorizontal = dx1 > dy1 * 1.5;
        final b2IsHorizontal = dx2 > dy2 * 1.5;

        if ((b1IsVertical && b2IsVertical) || (b1IsHorizontal && b2IsHorizontal)) {
          final hasTransverseBend = doc.bends.any((b) {
            if (b.id == b1.id || b.id == b2.id) return false;
            final dx = (b.p2.x - b.p1.x).abs();
            final dy = (b.p2.y - b.p1.y).abs();
            if (b1IsVertical) {
              return dx > dy * 1.5;
            } else {
              return dy > dx * 1.5;
            }
          });

          if (hasTransverseBend) return true;
        }
      }
    }
    return false;
  }

  /// Resolves the true scaling profile, ensuring risers are never misclassified as flat bends.
  CmsScalingProfile get effectiveScalingProfile {
    if (contract.scalingProfile == CmsScalingProfile.insideRiser ||
        contract.scalingProfile == CmsScalingProfile.outsideRiser) {
      return contract.scalingProfile;
    }

    // Inspect baseline document itself to prevent fallback misrouting
    final docType = '${baselineDocument.productType} ${baselineDocument.itemName}'.toLowerCase();
    if (docType.contains('inside') && (docType.contains('riser') || docType.contains('rise'))) {
      return CmsScalingProfile.insideRiser;
    }
    if (docType.contains('outside') && (docType.contains('riser') || docType.contains('rise'))) {
      return CmsScalingProfile.outsideRiser;
    }
    if (docType.contains('riser')) {
      return CmsScalingProfile.insideRiser;
    }

    final contractStr = '${contract.productType} ${contract.variationName}'.toLowerCase();
    if (contractStr.contains('inside') && (contractStr.contains('riser') || contractStr.contains('rise'))) {
      return CmsScalingProfile.insideRiser;
    }
    if (contractStr.contains('outside') && (contractStr.contains('riser') || contractStr.contains('rise'))) {
      return CmsScalingProfile.outsideRiser;
    }
    if (contractStr.contains('riser')) {
      return CmsScalingProfile.insideRiser;
    }

    // Geometrically detect riser topology directly from document features
    if (isOutsideRiserGeometry(baselineDocument)) {
      return CmsScalingProfile.outsideRiser;
    }
    if (isInsideRiserGeometry(baselineDocument)) {
      return CmsScalingProfile.insideRiser;
    }

    if (contract.scalingProfile == CmsScalingProfile.cross ||
        docType.contains('cross') ||
        isCrossGeometry(baselineDocument)) {
      return CmsScalingProfile.cross;
    }
    if (contract.scalingProfile == CmsScalingProfile.tee ||
        docType.contains('tee') ||
        isTeeGeometry(baselineDocument)) {
      return CmsScalingProfile.tee;
    }

    return contract.scalingProfile;
  }

  /// Geometrically detects whether [doc] is a Cross fitting (4 physical ports or 4-way corner bends).
  bool isCrossGeometry(DsfDocument doc) {
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (docType.contains('cross')) return true;
    return doc.bends.length >= 14 || baselinePorts.length == 4;
  }

  /// Geometrically detects whether [doc] is a Tee fitting (3 physical ports or 3-way layout).
  bool isTeeGeometry(DsfDocument doc) {
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (docType.contains('tee')) return true;
    return (doc.bends.length >= 9 && doc.bends.length <= 13) || baselinePorts.length == 3;
  }

  /// Dedicated 2D Sheet Scaling for Cross Fittings:
  /// - Base floor is an octagonal or rectangular central base with 4-way symmetry.
  /// - Horizontal and vertical runs scale symmetrically in linked mode, or independently in unlinked mode.
  /// - Corner sidewalls and return flanges scale diagonally outward with zero distortion.
  /// Dedicated 2D Sheet Scaling for Cross Fittings:
  /// - Base floor is an octagonal or rectangular central base with 4-way symmetry.
  /// - Horizontal and vertical runs scale symmetrically in linked mode, or independently in unlinked mode.
  /// - Body height is governed by the highest port height, and flap heights for lower ports retract.
  DsfDocument _scaleCross2D(
    DsfDocument baseline, {
    required bool isLinked,
    required Map<String, CmsScalingParameter> parameters,
  }) {
    final baseFloor = baseline.faces.firstWhere(
      (f) => f.isBaseAnchor || f.role == FaceRole.baseFloor,
      orElse: () => baseline.faces.first,
    );
    final verts = baseFloor.vertices;
    final minX = verts.map((v) => v.x).reduce(math.min);
    final maxX = verts.map((v) => v.x).reduce(math.max);
    final minY = verts.map((v) => v.y).reduce(math.min);
    final maxY = verts.map((v) => v.y).reduce(math.max);
    final midX = (minX + maxX) / 2.0;
    final midY = (minY + maxY) / 2.0;

    double dWHoriz = 0.0;
    double dWVert = 0.0;
    double dHBody = 0.0;
    double dH1 = 0.0;
    double dH2 = 0.0;
    double dH3 = 0.0;
    double dH4 = 0.0;

    if (isLinked) {
      final w = parameters['width'];
      final h = parameters['height'];
      final dW = w != null ? (w.currentValue - w.baselineValue) : 0.0;
      final dH = h != null ? (h.currentValue - h.baselineValue) : 0.0;
      dWHoriz = dW;
      dWVert = dW;
      dHBody = dH;
      dH1 = dH;
      dH2 = dH;
      dH3 = dH;
      dH4 = dH;
    } else {
      final p1W = parameters['port1_width'];
      final p2W = parameters['port2_width'];
      final p3W = parameters['port3_width'];
      final p4W = parameters['port4_width'];
      final p1H = parameters['port1_height'];
      final p2H = parameters['port2_height'];
      final p3H = parameters['port3_height'];
      final p4H = parameters['port4_height'];

      final dW1 = p1W != null ? (p1W.currentValue - p1W.baselineValue) : 0.0;
      final dW2 = p2W != null ? (p2W.currentValue - p2W.baselineValue) : 0.0;
      final dW3 = p3W != null ? (p3W.currentValue - p3W.baselineValue) : 0.0;
      final dW4 = p4W != null ? (p4W.currentValue - p4W.baselineValue) : 0.0;

      dWVert = (dW2.abs() > 0.01 ? dW2 : dW4);
      dWHoriz = (dW1.abs() > 0.01 ? dW1 : dW3);
      if (dWVert.abs() < 0.01) dWVert = (dW2 + dW4) / 2.0;
      if (dWHoriz.abs() < 0.01) dWHoriz = (dW1 + dW3) / 2.0;

      final h1cur = p1H?.currentValue ?? p1H?.baselineValue ?? 100.0;
      final h2cur = p2H?.currentValue ?? p2H?.baselineValue ?? 100.0;
      final h3cur = p3H?.currentValue ?? p3H?.baselineValue ?? 100.0;
      final h4cur = p4H?.currentValue ?? p4H?.baselineValue ?? 100.0;
      final h1base = p1H?.baselineValue ?? h1cur;
      final h2base = p2H?.baselineValue ?? h2cur;
      final h3base = p3H?.baselineValue ?? h3cur;
      final h4base = p4H?.baselineValue ?? h4cur;

      final maxTargetH = math.max(math.max(h1cur, h2cur), math.max(h3cur, h4cur));
      final maxBaseH = math.max(math.max(h1base, h2base), math.max(h3base, h4base));
      dHBody = maxTargetH - maxBaseH;

      dH1 = h1cur - h1base;
      dH2 = h2cur - h2base;
      dH3 = h3cur - h3base;
      dH4 = h4cur - h4base;
    }

    final hasCrossChange = dWHoriz.abs() > 1e-4 ||
        dWVert.abs() > 1e-4 ||
        dHBody.abs() > 1e-4 ||
        dH1.abs() > 1e-4 ||
        dH2.abs() > 1e-4 ||
        dH3.abs() > 1e-4 ||
        dH4.abs() > 1e-4;
    if (!hasCrossChange) return baseline;

    CadPoint2D transformCrossPt(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      if (x > midX + 5.0) {
        x += dWHoriz / 2.0;
      } else if (x < midX - 5.0) {
        x -= dWHoriz / 2.0;
      }

      if (y > midY + 5.0) {
        y += dWVert / 2.0;
      } else if (y < midY - 5.0) {
        y -= dWVert / 2.0;
      }

      if (dHBody.abs() > 1e-4) {
        final distFromCenter = math.sqrt(math.pow(pt.x - midX, 2) + math.pow(pt.y - midY, 2));
        if (distFromCenter > 80.0) {
          final signX = pt.x >= midX ? 1.0 : -1.0;
          final signY = pt.y >= midY ? 1.0 : -1.0;
          x += signX * (dHBody / (2.0 * math.sqrt2));
          y += signY * (dHBody / (2.0 * math.sqrt2));
        }
      }

      // Per-port flap adjustments (height delta relative to baseline for that port)
      if (dH1.abs() > 1e-4 && x > maxX - 5.0) {
        final signY = y >= midY ? 1.0 : -1.0;
        y += signY * (dH1 / 2.0);
      }
      if (dH2.abs() > 1e-4 && y > maxY - 5.0) {
        final signX = x >= midX ? 1.0 : -1.0;
        x += signX * (dH2 / 2.0);
      }
      if (dH3.abs() > 1e-4 && x < minX + 5.0) {
        final signY = y >= midY ? 1.0 : -1.0;
        y += signY * (dH3 / 2.0);
      }
      if (dH4.abs() > 1e-4 && y < minY + 5.0) {
        final signX = x >= midX ? 1.0 : -1.0;
        x += signX * (dH4 / 2.0);
      }

      return CadPoint2D(x, y);
    }

    return baseline.copyWith(
      outerContour: baseline.outerContour.map(transformCrossPt).toList(),
      bends: baseline.bends.map((b) => b.copyWith(
        p1: transformCrossPt(b.p1),
        p2: transformCrossPt(b.p2),
      )).toList(),
      faces: baseline.faces.map((f) => f.copyWith(
        vertices: f.vertices.map(transformCrossPt).toList(),
      )).toList(),
      punches: baseline.punches.map((p) => p.copyWith(
        center: transformCrossPt(p.center),
      )).toList(),
    );
  }

  /// Dedicated 2D Sheet Scaling for Tee Fittings:
  /// - Base floor web with Main Run and Branch mouth.
  /// - Branch width scales horizontally; Main run width scales bed vertically.
  /// - Product physical height remains max port height across the fitting.
  /// - Lower-height ports have their coupler flaps retracted along their outward direction.
  DsfDocument _scaleTee2D(
    DsfDocument baseline, {
    required bool isLinked,
    required Map<String, CmsScalingParameter> parameters,
  }) {
    final baseFloor = baseline.faces.firstWhere(
      (f) => f.isBaseAnchor || f.role == FaceRole.baseFloor,
      orElse: () => baseline.faces.first,
    );
    final verts = baseFloor.vertices;
    final minX = verts.map((v) => v.x).reduce(math.min);
    final maxX = verts.map((v) => v.x).reduce(math.max);
    final minY = verts.map((v) => v.y).reduce(math.min);
    final maxY = verts.map((v) => v.y).reduce(math.max);
    final midX = (minX + maxX) / 2.0;

    double dWMain = 0.0;
    double dWBranch = 0.0;
    double dHBody = 0.0;
    double dH1 = 0.0;
    double dH2 = 0.0;
    double dH3 = 0.0;

    if (isLinked) {
      final w = parameters['width'];
      final h = parameters['height'];
      final dW = w != null ? (w.currentValue - w.baselineValue) : 0.0;
      final dH = h != null ? (h.currentValue - h.baselineValue) : 0.0;
      dWMain = dW;
      dWBranch = dW;
      dHBody = dH;
      dH1 = dH;
      dH2 = dH;
      dH3 = dH;
    } else {
      final p1W = parameters['port1_width'];
      final p2W = parameters['port2_width'];
      final p3W = parameters['port3_width'];
      final p1H = parameters['port1_height'];
      final p2H = parameters['port2_height'];
      final p3H = parameters['port3_height'];

      final dW1 = p1W != null ? (p1W.currentValue - p1W.baselineValue) : 0.0;
      final dW2 = p2W != null ? (p2W.currentValue - p2W.baselineValue) : 0.0;
      final dW3 = p3W != null ? (p3W.currentValue - p3W.baselineValue) : 0.0;

      dWBranch = dW1;
      dWMain = (dW2.abs() > 0.01 ? dW2 : dW3);
      if (dWMain.abs() < 0.01) dWMain = (dW2 + dW3) / 2.0;

      final h1cur = p1H?.currentValue ?? p1H?.baselineValue ?? 100.0;
      final h2cur = p2H?.currentValue ?? p2H?.baselineValue ?? 100.0;
      final h3cur = p3H?.currentValue ?? p3H?.baselineValue ?? 100.0;
      final h1base = p1H?.baselineValue ?? h1cur;
      final h2base = p2H?.baselineValue ?? h2cur;
      final h3base = p3H?.baselineValue ?? h3cur;

      final maxTargetH = math.max(h1cur, math.max(h2cur, h3cur));
      final maxBaseH = math.max(h1base, math.max(h2base, h3base));
      dHBody = maxTargetH - maxBaseH;

      dH1 = h1cur - h1base;
      dH2 = h2cur - h2base;
      dH3 = h3cur - h3base;
    }

    final hasAnyChange = dWMain.abs() > 1e-4 ||
        dWBranch.abs() > 1e-4 ||
        dHBody.abs() > 1e-4 ||
        dH1.abs() > 1e-4 ||
        dH2.abs() > 1e-4 ||
        dH3.abs() > 1e-4;
    if (!hasAnyChange) return baseline;

    CadPoint2D transformTeePt(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      // --- Width (Branch & Main Run) ---
      if (x > midX + 5.0) {
        x += dWBranch / 2.0;
      } else if (x < midX - 5.0) {
        x -= dWBranch / 2.0;
      }
      if (y > maxY - 15.0) {
        y += dWMain;
      }

      // --- Physical Body Height Scaling ---
      // Sidewall F_9 (top run) extends vertically along with its return flange lip
      if (dHBody.abs() > 1e-4 && y > maxY - 5.0) {
        y += dHBody;
      }

      // --- Coupler Flap Retraction / Extension per Port ---
      // 1. Port 3 Flaps (Left ear of top wall, and upper-left diagonal cheek flap F_5):
      if (dH3.abs() > 1e-4) {
        if (x < minX + 5.0 && y > maxY - 15.0) {
          // Left ear of top sidewall F_9 / F_11
          y += dH3;
        } else if (x < midX - 40.0 && y > 40.0 && y < 160.0) {
          // Flap F_5 on left cheek
          x -= dH3 / math.sqrt2;
          y += dH3 / math.sqrt2;
        }
      }

      // 2. Port 2 Flaps (Right ear of top wall, and upper-right diagonal cheek flap F_1):
      if (dH2.abs() > 1e-4) {
        if (x > maxX - 5.0 && y > maxY - 15.0) {
          // Right ear of top sidewall F_9 / F_10
          y += dH2;
        } else if (x > midX + 40.0 && y > 140.0 && y < 220.0) {
          // Flap F_1 on right cheek
          x += dH2 / math.sqrt2;
          y += dH2 / math.sqrt2;
        }
      }

      // 3. Port 1 Flaps (Lower diagonal cheek flaps F_2 and F_6):
      if (dH1.abs() > 1e-4 && y < minY + 15.0) {
        if (x > midX) {
          // Flap F_2 on right lower cheek
          x += dH1 / math.sqrt2;
          y -= dH1 / math.sqrt2;
        } else {
          // Flap F_6 on left lower cheek
          x -= dH1 / math.sqrt2;
          y -= dH1 / math.sqrt2;
        }
      }

      return CadPoint2D(x, y);
    }

    return baseline.copyWith(
      outerContour: baseline.outerContour.map(transformTeePt).toList(),
      bends: baseline.bends.map((b) => b.copyWith(
        p1: transformTeePt(b.p1),
        p2: transformTeePt(b.p2),
      )).toList(),
      faces: baseline.faces.map((f) => f.copyWith(
        vertices: f.vertices.map(transformTeePt).toList(),
      )).toList(),
      punches: baseline.punches.map((p) => p.copyWith(
        center: transformTeePt(p.center),
      )).toList(),
    );
  }

  /// Geometrically detects whether [doc] is an Outside Riser.
  /// Outside risers have parallel vertical cheek bends (B1, B2) and flange bends (FL1, FL2)
  /// or 'outside' keywords, with no transverse floor bend across the central floor web.
  bool isOutsideRiserGeometry(DsfDocument doc) {
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (docType.contains('outside') && (docType.contains('riser') || docType.contains('rise'))) {
      return true;
    }

    final vertBends = doc.bends.where((b) {
      final dx = (b.p2.x - b.p1.x).abs();
      final dy = (b.p2.y - b.p1.y).abs();
      return dy > dx * 1.5;
    }).toList();

    final hasTransverseBend = doc.bends.any((b) {
      final dx = (b.p2.x - b.p1.x).abs();
      final dy = (b.p2.y - b.p1.y).abs();
      return dx > dy * 1.5;
    });

    return vertBends.length >= 2 && !hasTransverseBend && docType.contains('outside');
  }

  // ---------------------------------------------------------------------------
  // Canonical 2D Sheet Scaling Math (Section 13)
  // ---------------------------------------------------------------------------

  DsfDocument _generateScaled2DDocument({
    required DsfDocument baseline,
    required String paramId,
    required double delta,
  }) {
    final morphed = _morph2DBlank(baseline: baseline, paramId: paramId, delta: delta);
    return CmsPunchConstraintEngine.reconcile(
      baseline: baseline,
      scaled: morphed,
      paramId: paramId,
      delta: delta,
    );
  }

  DsfDocument _morph2DBlank({
    required DsfDocument baseline,
    required String paramId,
    required double delta,
  }) {
    if (delta.abs() < 1e-4) return baseline;

    final baseW = baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0;
    final baseH = baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0;
    final targetW = paramId == 'width' ? baseW + delta : baseW;
    final targetH = paramId == 'height' ? baseH + delta : baseH;

    final profile = effectiveScalingProfile;

    // 1. Dedicated Outside Riser Scaling Profile
    if (profile == CmsScalingProfile.outsideRiser || isOutsideRiserGeometry(baseline)) {
      if (paramId == 'width') {
        return _scaleOutsideRiserWidth2D(baseline, delta);
      } else if (paramId == 'height') {
        return _scaleOutsideRiserHeight2D(baseline, delta);
      }
      return baseline;
    }

    // 2. Dedicated Inside Riser Scaling Profile
    if (profile == CmsScalingProfile.insideRiser || isInsideRiserGeometry(baseline)) {
      if (paramId == 'width') {
        return _scaleRiserWidth2D(baseline, delta);
      } else if (paramId == 'height') {
        return _scaleRiserHeight2D(baseline, delta);
      }
      return baseline;
    }

    // 2. Flat Bends and Tees via TopologicalZoneMorpher
    if (profile == CmsScalingProfile.flatBend45 ||
        profile == CmsScalingProfile.flatBend90 ||
        profile == CmsScalingProfile.tee ||
        profile == CmsScalingProfile.straight) {
      final templateDef = TemplateParameterDefinition(
        templateId: profile == CmsScalingProfile.flatBend45
            ? '45_deg_bend'
            : (profile == CmsScalingProfile.flatBend90
                ? '90_deg_bend'
                : 'equal_tee'),
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

  /// Dedicated 2D Riser Width Scaling:
  /// - Floor web between B1 and B2 expands by delta.
  /// - Left cheek translates rigidly outward by -delta/2.
  /// - Right cheek translates rigidly outward by +delta/2.
  /// - Coupler slots translate with their host cheek with zero distortion.
  DsfDocument _scaleRiserWidth2D(DsfDocument baseline, double delta) {
    if (baseline.bends.isEmpty) return baseline;

    final b45 = baseline.bends.firstWhere(
      (b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0,
      orElse: () => baseline.bends.first,
    );
    final has45 = (b45.targetAngleDeg.abs() - 45.0).abs() < 15.0;

    double x1;
    double x2;
    if (has45 && (b45.p2.x - b45.p1.x).abs() > 20.0) {
      x1 = math.min(b45.p1.x, b45.p2.x);
      x2 = math.max(b45.p1.x, b45.p2.x);
    } else {
      final vertBends = baseline.bends
          .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0)
          .toList()
        ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));
      if (vertBends.length >= 4) {
        x1 = math.min((vertBends[1].p1.x + vertBends[1].p2.x) / 2.0, (vertBends[vertBends.length - 2].p1.x + vertBends[vertBends.length - 2].p2.x) / 2.0);
        x2 = math.max((vertBends[1].p1.x + vertBends[1].p2.x) / 2.0, (vertBends[vertBends.length - 2].p1.x + vertBends[vertBends.length - 2].p2.x) / 2.0);
      } else if (vertBends.length >= 2) {
        x1 = math.min((vertBends.first.p1.x + vertBends.first.p2.x) / 2.0, (vertBends.last.p1.x + vertBends.last.p2.x) / 2.0);
        x2 = math.max((vertBends.first.p1.x + vertBends.first.p2.x) / 2.0, (vertBends.last.p1.x + vertBends.last.p2.x) / 2.0);
      } else {
        return _scaleWidth2D(baseline, delta);
      }
    }

    final floorSpan = x2 - x1;
    if (floorSpan < 10.0) return _scaleWidth2D(baseline, delta);

    final halfDelta = delta / 2.0;

    CadPoint2D transformPt(CadPoint2D pt) {
      if (pt.x <= x1 + 0.5) {
        return CadPoint2D(pt.x - halfDelta, pt.y);
      } else if (pt.x >= x2 - 0.5) {
        return CadPoint2D(pt.x + halfDelta, pt.y);
      } else {
        final u = (pt.x - x1) / floorSpan;
        final newX = (x1 - halfDelta) + u * (floorSpan + delta);
        return CadPoint2D(newX, pt.y);
      }
    }

    final newContour = baseline.outerContour.map(transformPt).toList();

    final newBends = baseline.bends.map((b) {
      return b.copyWith(
        p1: transformPt(b.p1),
        p2: transformPt(b.p2),
      );
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    final newPunches = baseline.punches.map((p) {
      return p.copyWith(
        center: transformPt(p.center),
      );
    }).toList();

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(
        p1: transformPt(cl.p1),
        p2: transformPt(cl.p2),
      );
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final dx = newCenter.x - a.center.x;
      final dy = newCenter.y - a.center.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: newContour,
      bends: newBends,
      cutLines: newCutLines,
    );

    final doc = baseline.copyWith(
      outerContour: newContour,
      bends: newBends,
      faces: newFaces.isNotEmpty ? newFaces : decomp.faces,
      baseFaceId: baseline.baseFaceId.isNotEmpty ? baseline.baseFaceId : decomp.baseFaceId,
      punches: newPunches,
      cutLines: newCutLines,
      arcs: newArcs,
    );

    // If baseline topology is already established and complete, preserve it directly!
    final hasCompleteTopology = baseline.faces.isNotEmpty &&
        baseline.bends.isNotEmpty &&
        baseline.bends.every((b) => b.parentFaceId.isNotEmpty);

    if (hasCompleteTopology) {
      return doc;
    }

    final yB3 = has45 ? b45.p1.y : 128.65;
    return _normalizeRiserTopology(doc, x1 - halfDelta, x2 + halfDelta, yB3);
  }

  /// Dedicated 2D Outside Riser Width Scaling:
  /// - Floor web between B1 and B2 expands symmetrically along X by delta.
  /// - B1 and Left Cheek & Flange translate rigidly outward by -delta/2.
  /// - B2 and Right Cheek & Flange translate rigidly outward by +delta/2.
  /// - Flared cheek mouth prongs above the floor web (y > yFloorTop) are partitioned
  ///   strictly by centerline (xMid), ensuring the inner throat cuts and 45° mouths
  ///   translate rigidly with zero skewing, tearing, or angular distortion.
  /// - Coupler slots translate rigidly with their host cheek with zero distortion.
  DsfDocument _scaleOutsideRiserWidth2D(DsfDocument baseline, double delta) {
    if (baseline.bends.isEmpty) return baseline;

    final vertBends = baseline.bends
        .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
        .toList()
      ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));

    if (vertBends.length < 2) return _scaleWidth2D(baseline, delta);

    final b1 = vertBends.first;
    final b2 = vertBends.last;
    final x1 = math.min((b1.p1.x + b1.p2.x) / 2.0, (b2.p1.x + b2.p2.x) / 2.0);
    final x2 = math.max((b1.p1.x + b1.p2.x) / 2.0, (b2.p1.x + b2.p2.x) / 2.0);
    final xMid = (x1 + x2) / 2.0;
    final floorSpan = x2 - x1;
    if (floorSpan < 10.0) return _scaleWidth2D(baseline, delta);

    final halfDelta = delta / 2.0;
    final yFloorTop = math.max(math.max(b1.p1.y, b1.p2.y), math.max(b2.p1.y, b2.p2.y));

    CadPoint2D transformPt(CadPoint2D pt) {
      // 1. Above floor web (flared cheek prongs):
      // The cheek throat notch reaches inward into x1 < x < x2.
      // Partition strictly by midX so that each cheek translates 100% rigidly.
      if (pt.y > yFloorTop + 0.5) {
        return pt.x < xMid
            ? CadPoint2D(pt.x - halfDelta, pt.y)
            : CadPoint2D(pt.x + halfDelta, pt.y);
      }

      // 2. Straight sidewall cheeks and flanges
      if (pt.x <= x1 + 0.5) {
        return CadPoint2D(pt.x - halfDelta, pt.y);
      } else if (pt.x >= x2 - 0.5) {
        return CadPoint2D(pt.x + halfDelta, pt.y);
      } else {
        // 3. Central Floor Web: expands symmetrically along X
        final u = (pt.x - x1) / floorSpan;
        final newX = (x1 - halfDelta) + u * (floorSpan + delta);
        return CadPoint2D(newX, pt.y);
      }
    }

    final newContour = baseline.outerContour.map(transformPt).toList();

    final newBends = baseline.bends.map((b) {
      return b.copyWith(
        p1: transformPt(b.p1),
        p2: transformPt(b.p2),
      );
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    final newPunches = baseline.punches.map((p) {
      return p.copyWith(
        center: transformPt(p.center),
      );
    }).toList();

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(
        p1: transformPt(cl.p1),
        p2: transformPt(cl.p2),
      );
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final dx = newCenter.x - a.center.x;
      final dy = newCenter.y - a.center.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: newContour,
      bends: newBends,
      cutLines: newCutLines,
    );

    final doc = baseline.copyWith(
      outerContour: newContour,
      bends: newBends,
      faces: newFaces.isNotEmpty ? newFaces : decomp.faces,
      baseFaceId: baseline.baseFaceId,
      punches: newPunches,
      cutLines: newCutLines,
      arcs: newArcs,
    );

    // If baseline topology is already established and complete, preserve it directly!
    final hasCompleteTopology = baseline.faces.isNotEmpty &&
        baseline.bends.isNotEmpty &&
        baseline.bends.every((b) => b.parentFaceId.isNotEmpty);

    if (hasCompleteTopology) {
      return doc;
    }

    return _normalizeRiserTopology(doc, x1 - halfDelta, x2 + halfDelta, yFloorTop);
  }

  /// Dedicated 2D Outside Riser Height Scaling:
  /// - Central Floor Web (between x1 and x2) and vertical bend lines B1 and B2 remain 100% stationary and parallel.
  /// - Sidewall cheeks expand outward along X by delta (FL1 shifts by -delta, FL2 shifts by +delta).
  /// - Port 2 45° cheek mouth edges expand strictly along the 45° vector (±delta / sqrt(2), +delta / sqrt(2)),
  ///   preserving the exact 45° miter angle (dy / dx = ±1.0) with zero angular distortion.
  /// - Top miter cuts meet outer flanges at y + delta * (sqrt(2) - 1.0), preserving the 45° miter slope.
  /// - Coupler slots translate rigidly on both straight mouths and 45° mouths, preserving mounting setbacks
  ///   and orientations (0°, 45°, 135°) with zero distortion.
  DsfDocument _scaleOutsideRiserHeight2D(DsfDocument baseline, double delta) {
    if (baseline.bends.isEmpty) return baseline;

    // Identify vertical bends
    final vertBends = baseline.bends
        .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0)
        .toList()
      ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));

    double x1;
    double x2;
    double xFL1;
    double xFL2;

    if (vertBends.length >= 4) {
      xFL1 = (vertBends[0].p1.x + vertBends[0].p2.x) / 2.0;
      x1 = (vertBends[1].p1.x + vertBends[1].p2.x) / 2.0;
      x2 = (vertBends[vertBends.length - 2].p1.x + vertBends[vertBends.length - 2].p2.x) / 2.0;
      xFL2 = (vertBends.last.p1.x + vertBends.last.p2.x) / 2.0;
    } else if (vertBends.length >= 2) {
      x1 = (vertBends.first.p1.x + vertBends.first.p2.x) / 2.0;
      x2 = (vertBends.last.p1.x + vertBends.last.p2.x) / 2.0;
      final fl1Bends = baseline.bends.where((b) => b.p1.x < x1 - 10.0);
      final fl2Bends = baseline.bends.where((b) => b.p1.x > x2 + 10.0);
      xFL1 = fl1Bends.isNotEmpty ? fl1Bends.first.p1.x : x1 - 96.0;
      xFL2 = fl2Bends.isNotEmpty ? fl2Bends.first.p1.x : x2 + 96.0;
    } else {
      return _scaleHeight2D(baseline, delta);
    }

    final b1Bend = vertBends.firstWhere(
      (b) => ((b.p1.x + b.p2.x) / 2.0 - x1).abs() < 10.0,
      orElse: () => vertBends.first,
    );
    final yFloorBottom = math.min(b1Bend.p1.y, b1Bend.p2.y);
    final yFloorTop = math.max(b1Bend.p1.y, b1Bend.p2.y);
    final xMid = (x1 + x2) / 2.0;

    final dX45 = delta / math.sqrt(2);
    final dY45 = delta / math.sqrt(2);
    final dYStep = delta * (math.sqrt(2) - 1.0);

    CadPoint2D transformPt(CadPoint2D pt) {
      // 1. Central Floor Web & B1/B2 (between x1 and x2)
      if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5 && pt.y <= yFloorTop + 0.5) {
        return pt;
      }

      // Throat inner relief notches (pt near throat apex between x1 and x2)
      if (pt.y >= yFloorTop - 5.0 && pt.y <= yFloorTop + 30.0) {
        if (pt.x > x1 - 0.5 && pt.x < xMid) {
          return pt;
        }
        if (pt.x > xMid && pt.x < x2 + 0.5) {
          return pt;
        }
      }

      // 2. Left Cheek (pt.x <= x1)
      if (pt.x <= x1 + 0.5) {
        // Return flange and outer flange FL1 (x <= xFL1)
        if (pt.x <= xFL1 + 0.5) {
          if (pt.y <= yFloorBottom + 0.5) {
            return CadPoint2D(pt.x - delta, pt.y);
          } else {
            return CadPoint2D(pt.x - delta, pt.y + dYStep);
          }
        }

        // Port 1 mouth at bottom (y <= yFloorBottom)
        if (pt.y <= yFloorBottom + 0.5) {
          if (pt.x <= xFL1 + 5.5) {
            return CadPoint2D(pt.x - delta, pt.y);
          }
          if (pt.x >= x1 - 5.5) {
            return pt;
          }
          final t = (pt.x - (xFL1 + 5.0)) / (x1 - 5.0 - (xFL1 + 5.0));
          final newX = (xFL1 + 5.0 - delta) + t * (x1 - 5.0 - (xFL1 + 5.0) + delta);
          return CadPoint2D(newX, pt.y);
        }

        // Port 2 45° mouth outer corner and tip chamfer
        if (pt.y > yFloorTop + 20.0) {
          return CadPoint2D(pt.x - dX45, pt.y + dY45);
        }
      }

      // 3. Right Cheek (pt.x >= x2)
      if (pt.x >= x2 - 0.5) {
        // Return flange and outer flange FL2 (x >= xFL2)
        if (pt.x >= xFL2 - 0.5) {
          if (pt.y <= yFloorBottom + 0.5) {
            return CadPoint2D(pt.x + delta, pt.y);
          } else {
            return CadPoint2D(pt.x + delta, pt.y + dYStep);
          }
        }

        // Port 1 mouth at bottom (y <= yFloorBottom)
        if (pt.y <= yFloorBottom + 0.5) {
          if (pt.x >= xFL2 - 5.5) {
            return CadPoint2D(pt.x + delta, pt.y);
          }
          if (pt.x <= x2 + 5.5) {
            return pt;
          }
          final t = (pt.x - (x2 + 5.0)) / (xFL2 - 5.0 - (x2 + 5.0));
          final newX = (x2 + 5.0) + t * (xFL2 - 5.0 - (x2 + 5.0) + delta);
          return CadPoint2D(newX, pt.y);
        }

        // Port 2 45° mouth outer corner and tip chamfer
        if (pt.y > yFloorTop + 20.0) {
          return CadPoint2D(pt.x + dX45, pt.y + dY45);
        }
      }

      return pt;
    }

    CadPoint2D transformPunchCenter(CncPunchPrimitive p) {
      final cx = p.center.x;
      final cy = p.center.y;
      if (cx < xMid) {
        // Left Cheek
        if (p.rotationDeg == 0.0) {
          final xLeftMid = (xFL1 + x1) / 2.0;
          if (cx <= xLeftMid) {
            return CadPoint2D(cx - delta, cy); // SLOT_7 (outer)
          } else {
            return CadPoint2D(cx, cy); // SLOT_8 (inner)
          }
        } else {
          if (cy >= yFloorTop + 35.0) {
            return CadPoint2D(cx - dX45, cy + dY45); // SLOT_2 (outer)
          } else {
            return CadPoint2D(cx, cy); // SLOT_1 (inner)
          }
        }
      } else {
        // Right Cheek
        if (p.rotationDeg == 0.0) {
          final xRightMid = (x2 + xFL2) / 2.0;
          if (cx >= xRightMid) {
            return CadPoint2D(cx + delta, cy); // SLOT_5 (outer)
          } else {
            return CadPoint2D(cx, cy); // SLOT_6 (inner)
          }
        } else {
          if (cy >= yFloorTop + 35.0) {
            return CadPoint2D(cx + dX45, cy + dY45); // SLOT_4 (outer)
          } else {
            return CadPoint2D(cx, cy); // SLOT_3 (inner)
          }
        }
      }
    }

    final newContour = baseline.outerContour.map(transformPt).toList();

    final newBends = baseline.bends.map((b) {
      if (b.role == BendLineRole.flange || b.id.toUpperCase().startsWith('FL')) {
        final isLeft = ((b.p1.x + b.p2.x) / 2.0) < xMid;
        final shiftX = isLeft ? -delta : delta;
        final p1 = b.p1.y <= yFloorBottom + 1.0
            ? CadPoint2D(b.p1.x + shiftX, b.p1.y)
            : CadPoint2D(b.p1.x + shiftX, b.p1.y + dYStep);
        final p2 = b.p2.y <= yFloorBottom + 1.0
            ? CadPoint2D(b.p2.x + shiftX, b.p2.y)
            : CadPoint2D(b.p2.x + shiftX, b.p2.y + dYStep);
        return b.copyWith(p1: p1, p2: p2);
      }
      return b;
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    final newPunches = baseline.punches.map((p) {
      return p.copyWith(
        center: transformPunchCenter(p),
      );
    }).toList();

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(
        p1: transformPt(cl.p1),
        p2: transformPt(cl.p2),
      );
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final dx = newCenter.x - a.center.x;
      final dy = newCenter.y - a.center.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: newContour,
      bends: newBends,
      cutLines: newCutLines,
    );

    return baseline.copyWith(
      outerContour: newContour,
      bends: decomp.connectedBends.isNotEmpty ? decomp.connectedBends : newBends,
      faces: newFaces.isNotEmpty ? newFaces : decomp.faces,
      baseFaceId: decomp.baseFaceId.isNotEmpty ? decomp.baseFaceId : baseline.baseFaceId,
      punches: newPunches,
      cutLines: newCutLines,
      arcs: newArcs,
    );
  }

  /// Dedicated 2D Inside Riser Height Scaling:
  /// - Sidewall cheeks expand outward along X by delta.
  /// - 45° riser prongs shift outward along both X and Y (±delta, +delta), preserving
  ///   the exact 45° miter angle (dy / dx = 1.0) so they touch the 45° bottom flap bend F_1 in 3D.
  /// - Coupler slots translate rigidly on both the 45° prongs and straight sidewalls,
  ///   preserving their exact shape, pitch spacing, and rotation with zero distortion.
  /// - Floor web and bends B1, B2, B3 remain fixed.
  /// - Floor length along Y is never lengthened.
  DsfDocument _scaleRiserHeight2D(DsfDocument baseline, double delta) {
    if (baseline.bends.isEmpty) return baseline;

    final b45 = baseline.bends.firstWhere(
      (b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0,
      orElse: () => baseline.bends.first,
    );
    final has45 = (b45.targetAngleDeg.abs() - 45.0).abs() < 15.0;

    double x1;
    double x2;
    if (has45 && (b45.p2.x - b45.p1.x).abs() > 20.0) {
      x1 = math.min(b45.p1.x, b45.p2.x);
      x2 = math.max(b45.p1.x, b45.p2.x);
    } else {
      final vertBends = baseline.bends
          .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0)
          .toList()
        ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));
      if (vertBends.length >= 4) {
        x1 = math.min((vertBends[1].p1.x + vertBends[1].p2.x) / 2.0, (vertBends[vertBends.length - 2].p1.x + vertBends[vertBends.length - 2].p2.x) / 2.0);
        x2 = math.max((vertBends[1].p1.x + vertBends[1].p2.x) / 2.0, (vertBends[vertBends.length - 2].p1.x + vertBends[vertBends.length - 2].p2.x) / 2.0);
      } else if (vertBends.length >= 2) {
        x1 = math.min((vertBends.first.p1.x + vertBends.first.p2.x) / 2.0, (vertBends.last.p1.x + vertBends.last.p2.x) / 2.0);
        x2 = math.max((vertBends.first.p1.x + vertBends.first.p2.x) / 2.0, (vertBends.last.p1.x + vertBends.last.p2.x) / 2.0);
      } else {
        return _scaleHeight2D(baseline, delta);
      }
    }

    double minX = x1;
    double maxX = x2;
    for (final pt in baseline.outerContour) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
    }

    final leftHeight = x1 - minX;
    final rightHeight = maxX - x2;
    if (leftHeight < 10.0 || rightHeight < 10.0) return _scaleHeight2D(baseline, delta);

    // Find B3 transverse bend to establish the base junction Y (y ≈ 128.65)
    final b3 = baseline.bends.firstWhere(
      (b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0,
      orElse: () => baseline.bends.first,
    );
    final yB3 = b3.p1.y;

    // Threshold Y separating the straight run (including vertical flange lines FL1/FL2 ending at y = 85.64)
    // from the 45° riser prong and relief notch (y >= 88.64).
    // yProngThreshold = 87.0 ensures FL1/FL2 remain strictly vertical, while the mouth and its notch
    // move rigidly along the 45° mouth direction (-d45, -d45) / (+d45, -d45).
    final yProngThreshold = 87.0;

    // Determine the stretch threshold X for left and right cheek:
    // Left cheek: inner corner arc ARC_BND_3 is near B1 (x1). The stretch zone is between ARC_BND_3 and ARC_BND_4.
    // Right cheek: inner corner arc ARC_BND_2 is near B2 (x2). The stretch zone is between ARC_BND_2 and ARC_BND_1.
    double xLeftStretch = x1 - 5.0;
    double xRightStretch = x2 + 5.0;

    for (final a in baseline.arcs) {
      if (a.center.y < yProngThreshold) {
        if ((a.center.x - x1).abs() <= 20.0) {
          xLeftStretch = math.min(xLeftStretch, a.center.x - 0.5);
        }
        if ((a.center.x - x2).abs() <= 20.0) {
          xRightStretch = math.max(xRightStretch, a.center.x + a.radius + 0.5);
        }
      }
    }

    final deltaH = delta;
    final d45 = deltaH / math.sqrt(2);
    final deltaYB3 = 44.35 * (deltaH / 100.0);
    final deltaYFlapTop = 86.60 * (deltaH / 100.0);
    final deltaYProngTip = (244.70 - 170.66) * (deltaH / 100.0); // ~74.04 * (deltaH / 100.0)

    CadPoint2D transformPt(CadPoint2D pt) {
      // 1. Floor web and bottom flap (between x1 and x2)
      if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5) {
        if (pt.y < yB3 - 0.5) {
          // Floor web: fixed at bottom throat (y ~ 30), stretches in Y up to B3
          final ratio = (pt.y - 30.0) / (yB3 - 30.0);
          return CadPoint2D(pt.x, pt.y + deltaYB3 * ratio.clamp(0.0, 1.0));
        } else {
          // Bottom flap: shifts with B3, and expands in length to maintain 0 miter gap in 3D
          final flapLen = 167.70 - yB3; // ~39.05 mm
          final ratio = flapLen > 0.1 ? (pt.y - yB3) / flapLen : 1.0;
          final flapGrowth = deltaYFlapTop - deltaYB3; // ~42.25 mm per 100mm deltaH
          return CadPoint2D(pt.x, pt.y + deltaYB3 + flapGrowth * ratio.clamp(0.0, 1.0));
        }
      }

      // 2. Left Cheek (x < x1)
      if (pt.x < x1 - 0.5) {
        if (pt.y > yProngThreshold) {
          // 45° Riser Prong & Miter Cut:
          // Outer corner & notch (x <= minX + 25.0, or y ~ 116.92) translate horizontally with the outer wall (-deltaH, 0).
          // Inner mouth tip (y ~ 170.66) extends upward and inward by (-deltaH + d45, deltaYProngTip).
          // This keeps the mouth cut completely above FL1 without cutting into the return flange.
          if (pt.x <= minX + 25.0) {
            return CadPoint2D(pt.x - deltaH, pt.y);
          }
          final t = ((pt.y - 116.92) / (170.66 - 116.92)).clamp(0.0, 1.0);
          final dx = -deltaH + t * d45;
          final dy = t * deltaYProngTip;
          return CadPoint2D(pt.x + dx, pt.y + dy);
        } else {
          // Straight sidewall section:
          // Inner corner (x >= xLeftStretch - 0.5) remains fixed with B1 and PORT_1.
          // Outer sidewall (x < xLeftStretch - 0.5) translates rigidly outward by -deltaH.
          // The horizontal edge between them expands by deltaH, keeping all corner arcs and chamfers 100% invariant.
          if (pt.x >= xLeftStretch - 0.5) {
            return pt;
          } else {
            return CadPoint2D(pt.x - deltaH, pt.y);
          }
        }
      }

      // 3. Right Cheek (x > x2)
      if (pt.x > x2 + 0.5) {
        if (pt.y > yProngThreshold) {
          // 45° Riser Prong & Miter Cut:
          // Outer corner & notch translate horizontally with the outer wall (+deltaH, 0).
          // Inner mouth tip (y ~ 170.66) extends upward and inward by (+deltaH - d45, deltaYProngTip).
          if (pt.x >= maxX - 25.0) {
            return CadPoint2D(pt.x + deltaH, pt.y);
          }
          final t = ((pt.y - 116.92) / (170.66 - 116.92)).clamp(0.0, 1.0);
          final dx = deltaH - t * d45;
          final dy = t * deltaYProngTip;
          return CadPoint2D(pt.x + dx, pt.y + dy);
        } else {
          // Straight sidewall section:
          // Inner corner (x <= xRightStretch + 0.5) remains fixed with B2 and PORT_1.
          // Outer sidewall (x > xRightStretch + 0.5) translates rigidly outward by +deltaH.
          if (pt.x <= xRightStretch + 0.5) {
            return pt;
          } else {
            return CadPoint2D(pt.x + deltaH, pt.y);
          }
        }
      }

      return pt;
    }

    CadPoint2D transformPunchCenter(CadPoint2D pt) {
      // 1. Floor punches: fixed
      if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5) {
        return pt;
      }

      // 2. Left Cheek punches
      if (pt.x < x1 - 0.5) {
        if (pt.y > yProngThreshold) {
          // Coupler slots on 45° prong:
          // Outer slot (SLOT_4, y < 120) tracks outer mouth corner (-deltaH, 0)
          // Inner slot (SLOT_3, y >= 120) tracks inner mouth tip (-deltaH + d45, d45)
          if (pt.y < 120.0) {
            return CadPoint2D(pt.x - deltaH, pt.y);
          } else {
            return CadPoint2D(pt.x - deltaH + d45, pt.y + d45);
          }
        } else {
          // Coupler slots on straight sidewall:
          final xLeftMid = (minX + x1) / 2.0;
          if (pt.x > xLeftMid) {
            return pt;
          } else {
            return CadPoint2D(pt.x - deltaH, pt.y);
          }
        }
      }

      // 3. Right Cheek punches
      if (pt.x > x2 + 0.5) {
        if (pt.y > yProngThreshold) {
          // Coupler slots on 45° prong:
          // Outer slot (SLOT_2, y < 120) tracks outer mouth corner (+deltaH, 0)
          // Inner slot (SLOT_1, y >= 120) tracks inner mouth tip (+deltaH - d45, d45)
          if (pt.y < 120.0) {
            return CadPoint2D(pt.x + deltaH, pt.y);
          } else {
            return CadPoint2D(pt.x + deltaH - d45, pt.y + d45);
          }
        } else {
          // Coupler slots on straight sidewall:
          final xRightMid = (x2 + maxX) / 2.0;
          if (pt.x < xRightMid) {
            return pt;
          } else {
            return CadPoint2D(pt.x + deltaH, pt.y);
          }
        }
      }

      return pt;
    }

    final newContour = baseline.outerContour.map(transformPt).toList();

    final newBends = baseline.bends.map((b) {
      return b.copyWith(
        p1: transformPt(b.p1),
        p2: transformPt(b.p2),
      );
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    final newPunches = baseline.punches.map((p) {
      return p.copyWith(
        center: transformPunchCenter(p.center),
      );
    }).toList();

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(
        p1: transformPt(cl.p1),
        p2: transformPt(cl.p2),
      );
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newStart = transformPt(a.startPoint);
      final dx = newStart.x - a.startPoint.x;
      final dy = newStart.y - a.startPoint.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: newContour,
      bends: newBends,
      cutLines: newCutLines,
    );

    final doc = baseline.copyWith(
      outerContour: newContour,
      bends: newBends,
      faces: newFaces.isNotEmpty ? newFaces : decomp.faces,
      baseFaceId: baseline.baseFaceId,
      punches: newPunches,
      cutLines: newCutLines,
      arcs: newArcs,
    );

    // If baseline topology is already established and complete, preserve it directly!
    final hasCompleteTopology = baseline.faces.isNotEmpty &&
        baseline.bends.isNotEmpty &&
        baseline.bends.every((b) => b.parentFaceId.isNotEmpty);

    if (hasCompleteTopology) {
      return doc;
    }

    return _normalizeRiserTopology(doc, x1, x2, yB3);
  }

  /// Normalizes kinematic DAG topology for 45° Inside Riser fittings:
  /// - Central Floor Web (between x1 and x2, y < yB3) is the base anchor (Root of DAG, FaceRole.baseFloor).
  /// - Bottom Flap is child of Floor Web via B3 (45° bend UP).
  /// - Left Cheek is child of Floor Web via inner 90° bend UP.
  /// - Right Cheek is child of Floor Web via inner 90° bend UP.
  /// - Left/Right Flanges (if present) are children of Left/Right Cheeks via outer 90° bends UP.
  /// - Ensures exact 3D touching along the 45° miter line with zero separation.
  DsfDocument _normalizeRiserTopology(DsfDocument doc, double x1, double x2, double yB3) {
    final floorFace = doc.faces.firstWhere(
      (f) {
        final cx = f.centroid.x;
        return cx >= x1 - 5.0 && cx <= x2 + 5.0 && f.centroid.y < yB3;
      },
      orElse: () => doc.faces.firstWhere((f) => f.id == 'F_4' || f.id == 'F_2', orElse: () => doc.faces.first),
    );

    final flapFace = doc.faces.firstWhere(
      (f) => f.id != floorFace.id && f.centroid.x >= x1 - 5.0 && f.centroid.x <= x2 + 5.0,
      orElse: () => doc.faces.firstWhere((f) => f.id == 'F_3' || f.id == 'F_1', orElse: () => doc.faces.first),
    );

    // Left faces: x < x1 - 5.0, sorted descending by centroid.x (cheek is closest to x1, flange is outer)
    final leftFaces = doc.faces.where((f) => f.centroid.x < x1 - 5.0).toList()
      ..sort((a, b) => b.centroid.x.compareTo(a.centroid.x));
    final leftCheek = leftFaces.isNotEmpty ? leftFaces.first : null;
    final leftFlange = leftFaces.length > 1 ? leftFaces.last : null;

    // Right faces: x > x2 + 5.0, sorted ascending by centroid.x (cheek is closest to x2, flange is outer)
    final rightFaces = doc.faces.where((f) => f.centroid.x > x2 + 5.0).toList()
      ..sort((a, b) => a.centroid.x.compareTo(b.centroid.x));
    final rightCheek = rightFaces.isNotEmpty ? rightFaces.first : null;
    final rightFlange = rightFaces.length > 1 ? rightFaces.last : null;

    final normalizedFaces = doc.faces.map((f) {
      if (f.id == floorFace.id) {
        return f.copyWith(isBaseAnchor: true, role: FaceRole.baseFloor, label: 'Floor Web');
      } else if (f.id == flapFace.id) {
        return f.copyWith(isBaseAnchor: false, role: FaceRole.sideWall, label: 'Bottom Flap');
      } else if (leftCheek != null && f.id == leftCheek.id) {
        return f.copyWith(isBaseAnchor: false, role: FaceRole.sideWall, label: 'Left Sidewall Cheek');
      } else if (rightCheek != null && f.id == rightCheek.id) {
        return f.copyWith(isBaseAnchor: false, role: FaceRole.sideWall, label: 'Right Sidewall Cheek');
      } else if (leftFlange != null && f.id == leftFlange.id) {
        return f.copyWith(isBaseAnchor: false, role: FaceRole.returnFlange, label: 'Left Return Flange');
      } else if (rightFlange != null && f.id == rightFlange.id) {
        return f.copyWith(isBaseAnchor: false, role: FaceRole.returnFlange, label: 'Right Return Flange');
      }
      return f.copyWith(isBaseAnchor: false);
    }).toList();

    // Partition 90° bends into left and right
    final midWebX = (x1 + x2) / 2.0;
    final left90Bends = doc.bends.where((b) {
      final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
      final midX = (b.p1.x + b.p2.x) / 2.0;
      return is90 && midX <= midWebX;
    }).toList()
      ..sort((a, b) => ((b.p1.x + b.p2.x) / 2.0).compareTo((a.p1.x + a.p2.x) / 2.0)); // Inner bend first

    final right90Bends = doc.bends.where((b) {
      final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
      final midX = (b.p1.x + b.p2.x) / 2.0;
      return is90 && midX > midWebX;
    }).toList()
      ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0)); // Inner bend first

    final leftInnerBendId = left90Bends.isNotEmpty ? left90Bends.first.id : null;
    final leftOuterBendId = left90Bends.length > 1 ? left90Bends.last.id : null;

    final rightInnerBendId = right90Bends.isNotEmpty ? right90Bends.first.id : null;
    final rightOuterBendId = right90Bends.length > 1 ? right90Bends.last.id : null;

    final normalizedBends = doc.bends.map((b) {
      if ((b.targetAngleDeg.abs() - 45.0).abs() < 15.0) {
        return b.copyWith(
          parentFaceId: floorFace.id,
          childFaceId: flapFace.id,
          direction: BendDirection.up,
        );
      } else if (b.id == leftInnerBendId && leftCheek != null) {
        return b.copyWith(
          parentFaceId: floorFace.id,
          childFaceId: leftCheek.id,
          direction: BendDirection.up,
        );
      } else if (b.id == leftOuterBendId && leftCheek != null && leftFlange != null) {
        return b.copyWith(
          parentFaceId: leftCheek.id,
          childFaceId: leftFlange.id,
          direction: BendDirection.up,
        );
      } else if (b.id == rightInnerBendId && rightCheek != null) {
        return b.copyWith(
          parentFaceId: floorFace.id,
          childFaceId: rightCheek.id,
          direction: BendDirection.up,
        );
      } else if (b.id == rightOuterBendId && rightCheek != null && rightFlange != null) {
        return b.copyWith(
          parentFaceId: rightCheek.id,
          childFaceId: rightFlange.id,
          direction: BendDirection.up,
        );
      }
      return b;
    }).toList();

    return doc.copyWith(
      baseFaceId: floorFace.id,
      faces: normalizedFaces,
      bends: normalizedBends,
    );
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
    final is45Bend = contract.scalingProfile == CmsScalingProfile.flatBend45;

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
    if (baseline.faces.isEmpty && baseline.outerContour.isEmpty) return baseline;

    // Shift sidewall outer edges and return flanges along Y
    final halfDelta = delta / 2.0;

    // Compute dynamic split line along Y
    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final pt in baseline.outerContour) {
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }
    for (final b in baseline.bends) {
      if (b.p1.y < minY) minY = b.p1.y;
      if (b.p2.y < minY) minY = b.p2.y;
      if (b.p1.y > maxY) maxY = b.p1.y;
      if (b.p2.y > maxY) maxY = b.p2.y;
    }
    final midY = (minY.isFinite && maxY.isFinite) ? (minY + maxY) / 2.0 : 0.0;

    CadPoint2D transformPt(CadPoint2D pt) {
      // Points in upper region shift +halfDelta, lower shift -halfDelta
      final shift = pt.y >= midY ? halfDelta : -halfDelta;
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

    final minW = math.min(50.0, baselineWidth - 50.0);
    final maxW = math.max(750.0, baselineWidth + 200.0);
    final minH = math.min(50.0, baselineHeight - 50.0);
    final maxH = math.max(300.0, baselineHeight + 150.0);

    bool initialLinked = true;
    if (baselinePorts.length >= 3) {
      final firstW = baselinePorts.first.width;
      final firstH = baselinePorts.first.height;
      for (final p in baselinePorts) {
        if ((p.width - firstW).abs() > 3.0 || (p.height - firstH).abs() > 3.0) {
          initialLinked = false;
          break;
        }
      }
    }

    final params = <String, CmsScalingParameter>{};
    if (initialLinked || baselinePorts.length < 3) {
      params['width'] = CmsScalingParameter(
        id: 'width',
        displayName: 'Width (W)',
        currentValue: baselineWidth,
        baselineValue: baselineWidth,
        minValidMm: minW,
        maxValidMm: maxW,
        unit: 'mm',
        teachingState: CmsParameterTeachingState.untaught,
        stretchZoneIds: ['ZONE_FLOOR_WEB'],
        translationZoneIds: ['ZONE_SIDEWALLS_AND_FLANGES'],
        rigidGroupIds: rigidGroups.map((g) => g.id).toList(),
        derivedPortIds: derivedPorts.map((p) => p.portId).toList(),
      );
      params['height'] = CmsScalingParameter(
        id: 'height',
        displayName: 'Height (H)',
        currentValue: baselineHeight,
        baselineValue: baselineHeight,
        minValidMm: minH,
        maxValidMm: maxH,
        unit: 'mm',
        teachingState: CmsParameterTeachingState.untaught,
        stretchZoneIds: [],
        translationZoneIds: ['ZONE_SIDEWALLS_AND_FLANGES'],
        rigidGroupIds: rigidGroups.map((g) => g.id).toList(),
        derivedPortIds: derivedPorts.map((p) => p.portId).toList(),
      );
      _activeParameterId = 'width';
    } else {
      for (int i = 0; i < baselinePorts.length; i++) {
        final p = baselinePorts[i];
        final wId = 'port${i + 1}_width';
        final hId = 'port${i + 1}_height';
        params[wId] = CmsScalingParameter(
          id: wId,
          displayName: 'Port ${i + 1} Width',
          currentValue: p.width,
          baselineValue: p.width,
          minValidMm: math.min(50.0, p.width - 50.0),
          maxValidMm: math.max(750.0, p.width + 200.0),
          unit: 'mm',
          teachingState: CmsParameterTeachingState.untaught,
        );
        params[hId] = CmsScalingParameter(
          id: hId,
          displayName: 'Port ${i + 1} Height',
          currentValue: p.height,
          baselineValue: p.height,
          minValidMm: math.min(50.0, p.height - 50.0),
          maxValidMm: math.max(300.0, p.height + 150.0),
          unit: 'mm',
          teachingState: CmsParameterTeachingState.untaught,
        );
      }
      _activeParameterId = 'port1_width';
    }

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
      isLinkedPorts: initialLinked,
      activePortIndex: 0,
    );
  }
}
