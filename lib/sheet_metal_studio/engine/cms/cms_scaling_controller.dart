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
import 'cms_port_reconciler.dart';
import 'cms_punch_constraint_engine.dart';
import 'unequal_tee_scaler.dart';
import 'unequal_cross_scaler.dart';
import 'reducer_scaler.dart';

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
    final decomp = PlanarFaceDecomposer.decompose(outerContour: doc.outerContour, bends: doc.bends, cutLines: doc.cutLines);
    return doc.copyWith(faces: decomp.faces, baseFaceId: decomp.baseFaceId);
  }

  CmsScalingController({
    required DsfDocument baselineDocument,
    required this.contract,
    required this.baselinePorts,
    Map<String, double>? currentParameterValues,
  }) : baselineDocument = _ensureFaces(baselineDocument) {
    _initModelFromPhase1(currentParameterValues: currentParameterValues);
    _previewMorphValue = _model.parameters[_activeParameterId]?.currentValue ?? 100.0;
    evaluateMorph(_previewMorphValue);
  }

  // Getters
  CmsScalingModel get model => _model;
  String get activeParameterId => _activeParameterId;
  double get previewMorphValue => _previewMorphValue;
  CmsScalingPreviewResult? get currentPreview => _currentPreview;
  DsfDocument get previewDocument => _currentPreview?.scaledDocument ?? baselineDocument;
  bool get isEvaluating => _isEvaluating;

  bool get isMultiPortFitting {
    final prof = effectiveScalingProfile;
    return prof == CmsScalingProfile.equalTee ||
        prof == CmsScalingProfile.unequalTee ||
        prof == CmsScalingProfile.equalCross ||
        prof == CmsScalingProfile.unequalCross ||
        prof == CmsScalingProfile.tee ||
        prof == CmsScalingProfile.cross ||
        baselinePorts.length >= 3;
  }

  bool get isLinkedPorts => _model.isLinkedPorts;
  int get activePortIndex => _model.activePortIndex;

  void setActivePortIndex(int index) {
    if (index < 0 || index >= baselinePorts.length) return;
    _model = _model.copyWith(activePortIndex: index);
    if (!_model.isLinkedPorts) {
      final isHeightActive = _activeParameterId.endsWith('_height');
      final targetId = isHeightActive ? 'port${index + 1}_height' : 'port${index + 1}_width';
      if (_model.parameters.containsKey(targetId)) {
        selectParameter(targetId);
      } else {
        final wId = 'port${index + 1}_width';
        if (_model.parameters.containsKey(wId)) {
          selectParameter(wId);
        }
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

    final deltaW = (widthParam != null) ? (widthParam.currentValue - widthParam.baselineValue) : 0.0;
    final deltaH = (heightParam != null) ? (heightParam.currentValue - heightParam.baselineValue) : 0.0;

    // 1. Generate updated canonical 2D sheet geometry composing active parameter deltas
    var scaledDoc = baselineDocument;
    final prof = effectiveScalingProfile;

    if (prof == CmsScalingProfile.equalCross) {
      scaledDoc = _scaleEqualCross2D(scaledDoc, parameters: _model.parameters);
    } else if (prof == CmsScalingProfile.unequalCross) {
      scaledDoc = _scaleUnequalCross2D(scaledDoc, isLinked: _model.isLinkedPorts, parameters: _model.parameters);
    } else if (prof == CmsScalingProfile.equalTee) {
      scaledDoc = _scaleEqualTee2D(scaledDoc, parameters: _model.parameters);
    } else if (prof == CmsScalingProfile.unequalTee) {
      scaledDoc = _scaleUnequalTee2D(scaledDoc, isLinked: _model.isLinkedPorts, parameters: _model.parameters);
    } else if (prof == CmsScalingProfile.cross || isCrossGeometry(baselineDocument)) {
      scaledDoc = _scaleCross2D(scaledDoc, isLinked: _model.isLinkedPorts, parameters: _model.parameters);
    } else if (prof == CmsScalingProfile.tee || isTeeGeometry(baselineDocument)) {
      scaledDoc = _scaleTee2D(scaledDoc, isLinked: _model.isLinkedPorts, parameters: _model.parameters);
    } else if (prof == CmsScalingProfile.reducer || isReducerGeometry(baselineDocument)) {
      scaledDoc = _scaleReducer2D(scaledDoc, parameters: _model.parameters);
    } else if (prof == CmsScalingProfile.flatBend45 ||
        (isBend45Geometry(baselineDocument) && prof != CmsScalingProfile.insideRiser && prof != CmsScalingProfile.outsideRiser)) {
      scaledDoc = _scaleFlatBend45_2D(scaledDoc, parameters: _model.parameters);
    } else if (prof == CmsScalingProfile.flatBend90 ||
        (isBend90Geometry(baselineDocument) && prof != CmsScalingProfile.insideRiser && prof != CmsScalingProfile.outsideRiser)) {
      scaledDoc = _scaleFlatBend90_2D(scaledDoc, parameters: _model.parameters);
    } else {
      if (deltaW.abs() > 0.01) {
        scaledDoc = _generateScaled2DDocument(baseline: scaledDoc, paramId: 'width', delta: deltaW);
      }
      if (deltaH.abs() > 0.01) {
        scaledDoc = _generateScaled2DDocument(baseline: scaledDoc, paramId: 'height', delta: deltaH);
      }
    }

    final targetW = (prof == CmsScalingProfile.reducer || isReducerGeometry(baselineDocument))
        ? (_model.parameters['port1_width']?.currentValue ?? 100.0)
        : (widthParam?.currentValue ?? (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0));
    final targetH = (prof == CmsScalingProfile.reducer || isReducerGeometry(baselineDocument))
        ? (_model.parameters['port1_height']?.currentValue ?? 100.0)
        : (heightParam?.currentValue ?? (baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0));
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
    final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: mesh);
    final initialMeasured = rawOpenings
        .map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledDoc, foldResult: mesh, defaultHeight: targetH))
        .toList();

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

    final List<CmsPhysicalPort> matchedPorts;
    if (baselinePorts.isNotEmpty) {
      matchedPorts = CmsPortReconciler.reconcile(previousPorts: baselinePorts, newlyMeasured: measured);
    } else {
      final matchResult = CmsPortMatcher.match(measuredOpenings: measured, contract: contract);
      matchedPorts = matchResult.matchedPorts;
    }

    final effectivePorts = matchedPorts.isNotEmpty
        ? matchedPorts.map((mp) {
            final baseMatch = baselinePorts.firstWhere((bp) => bp.id == mp.id || bp.index == mp.index, orElse: () => mp);
            var updated = mp;
            double portExpectedW = targetW;
            double portExpectedH = targetH;
            if (!_model.isLinkedPorts) {
              final pW = _model.parameters['port${mp.index}_width'];
              final pH = _model.parameters['port${mp.index}_height'];
              if (pW != null) portExpectedW = pW.currentValue;
              if (pH != null) portExpectedH = pH.currentValue;
              updated = updated.copyWith(width: portExpectedW, height: portExpectedH);
            } else {
              if ((portExpectedW - mp.width).abs() <= 6.0) {
                updated = updated.copyWith(width: portExpectedW);
              }
              if ((portExpectedH - mp.height).abs() <= 6.0) {
                updated = updated.copyWith(height: portExpectedH);
              }
            }
            if (baseMatch.role != null && baseMatch.role != CmsPortRole.unassigned) {
              updated = updated.copyWith(role: baseMatch.role, roleSource: baseMatch.roleSource);
            }
            if (updated.derivedMouthCorners.length == 4 && updated.height > 1.0) {
              final p1 = updated.derivedMouthCorners[0];
              final p2 = updated.derivedMouthCorners[3];
              final hDir = updated.heightDirection;
              final p3 = CadPoint3D(p1.x + updated.height * hDir.x, p1.y + updated.height * hDir.y, p1.z + updated.height * hDir.z);
              final p4 = CadPoint3D(p2.x + updated.height * hDir.x, p2.y + updated.height * hDir.y, p2.z + updated.height * hDir.z);
              final newCenter = CadPoint3D(
                (p1.x + p2.x) / 2.0 + (updated.height / 2.0) * hDir.x,
                (p1.y + p2.y) / 2.0 + (updated.height / 2.0) * hDir.y,
                (p1.z + p2.z) / 2.0 + (updated.height / 2.0) * hDir.z,
              );
              final newCalloutAnchor = CadPoint3D(
                (p1.x + p2.x) / 2.0 + updated.height * hDir.x,
                (p1.y + p2.y) / 2.0 + updated.height * hDir.y,
                (p1.z + p2.z) / 2.0 + updated.height * hDir.z,
              );
              updated = updated.copyWith(derivedMouthCorners: [p1, p3, p4, p2], center: newCenter, calloutAnchor: newCalloutAnchor);
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
      newParams[entry.key] = entry.value.copyWith(teachingState: CmsParameterTeachingState.learned);
    }
    _model = _model.copyWith(parameters: newParams);

    // Persist scaling model, canonical baseline, and derived scaled ports into DSF metadata
    final previewDoc = _currentPreview?.scaledDocument ?? baselineDocument;
    final meta = Map<String, dynamic>.from(previewDoc.metadata);
    final cmsTemplate = Map<String, dynamic>.from(meta['cmsTemplate'] as Map<String, dynamic>? ?? {});
    final existingCanonical = (baselineDocument.metadata['cmsTemplate'] as Map?)?['canonicalDocument'];
    cmsTemplate['canonicalDocument'] = existingCanonical ?? baselineDocument.toJson();
    final existingBasePorts = (baselineDocument.metadata['cmsTemplate'] as Map?)?['baselinePorts'];
    cmsTemplate['baselinePorts'] = existingBasePorts ?? baselinePorts.map((p) => p.toJson()).toList();
    cmsTemplate['productType'] = contract.productType;
    cmsTemplate['variation'] = contract.variationName;
    cmsTemplate['templateId'] = '${contract.productType}_${contract.variationName}';
    cmsTemplate['scalingModel'] = _model.toJson();
    if (_currentPreview != null && _currentPreview!.derivedPorts.isNotEmpty) {
      cmsTemplate['ports'] = _currentPreview!.derivedPorts.map((p) => p.toJson()).toList();
    }
    meta['cmsTemplate'] = cmsTemplate;
    meta['cms_product_contract'] = {'productType': contract.productType, 'variationName': contract.variationName};
    meta['appliedTemplate'] = contract.productType;

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
      parameters: {...previewDoc.parameters, for (final p in _model.parameters.values) p.id: p.currentValue},
      metadata: meta,
    );
    notifyListeners();
    return finalDoc;
  }

  /// Restores all active parameters and the preview back to baseline dimensions (Section 6).
  void resetToBaseline() {
    final newParams = <String, CmsScalingParameter>{};
    for (final entry in _model.parameters.entries) {
      newParams[entry.key] = entry.value.copyWith(currentValue: entry.value.baselineValue);
    }
    _model = _model.copyWith(parameters: newParams);

    final activeBase = _model.parameters[_activeParameterId]?.baselineValue ?? 100.0;
    _previewMorphValue = activeBase;

    evaluateMorph(activeBase);
  }

  /// Reverts any preview changes back to the unscaled baseline.
  void cancelScaling() {
    _currentPreview = null;
    final baseVal = baselineDocument.parameters[_activeParameterId] ?? (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    _previewMorphValue = baseVal;
    final param = activeParameter;
    if (param != null && param.teachingState == CmsParameterTeachingState.learning) {
      final reverted = param.copyWith(currentValue: param.baselineValue, teachingState: CmsParameterTeachingState.untaught);
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
    // A cross (4 ports, 14 bends, 17 faces) or tee (3 ports, >=9 bends, >=10 faces) is never an inside riser
    if (doc.bends.length >= 8 || doc.faces.length >= 10) return false;
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (docType.contains('cross') || docType.contains('tee') || docType.contains('reducer') || isReducerGeometry(doc)) return false;
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
            final isBend45 = (b.targetAngleDeg.abs() - 45.0).abs() < 15.0;
            if (!isBend45) return false;
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

  /// Geometrically detects whether [doc] is a Reducer fitting (tapered floor web between two bends).
  static bool isReducerGeometry(DsfDocument doc) {
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (docType.contains('reducer')) return true;

    final bends90 = doc.bends.where((b) {
      final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
      return is90 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL');
    }).toList();

    if (bends90.length == 2) {
      final b1 = bends90[0];
      final b2 = bends90[1];
      final d1 = (b1.p1.x - b2.p1.x).abs();
      final d2 = (b1.p2.x - b2.p2.x).abs();
      if ((d1 - d2).abs() > 15.0) return true;
    }
    return false;
  }

  /// Resolves the true scaling profile, ensuring multi-port fittings and risers are never misclassified.
  CmsScalingProfile get effectiveScalingProfile {
    if (contract.scalingProfile == CmsScalingProfile.unequalCross ||
        contract.scalingProfile == CmsScalingProfile.equalCross ||
        contract.scalingProfile == CmsScalingProfile.unequalTee ||
        contract.scalingProfile == CmsScalingProfile.equalTee ||
        contract.scalingProfile == CmsScalingProfile.insideRiser ||
        contract.scalingProfile == CmsScalingProfile.outsideRiser ||
        contract.scalingProfile == CmsScalingProfile.straight ||
        contract.scalingProfile == CmsScalingProfile.reducer) {
      return contract.scalingProfile;
    }

    // Inspect baseline document itself to prevent fallback misrouting
    final docType = '${baselineDocument.productType} ${baselineDocument.itemName}'.toLowerCase();
    if (docType.contains('reducer') || isReducerGeometry(baselineDocument)) {
      return CmsScalingProfile.reducer;
    }
    final isCross = contract.scalingProfile == CmsScalingProfile.cross || docType.contains('cross') || isCrossGeometry(baselineDocument);

    if (isCross) {
      if (contract.scalingProfile == CmsScalingProfile.unequalCross || isUnequalCross(baselineDocument)) {
        return CmsScalingProfile.unequalCross;
      }
      return CmsScalingProfile.equalCross;
    }

    final isTee = contract.scalingProfile == CmsScalingProfile.tee || docType.contains('tee') || isTeeGeometry(baselineDocument);

    if (isTee) {
      if (contract.scalingProfile == CmsScalingProfile.unequalTee || isUnequalTee(baselineDocument)) {
        return CmsScalingProfile.unequalTee;
      }
      return CmsScalingProfile.equalTee;
    }

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

    return contract.scalingProfile;
  }

  /// Geometrically detects whether [doc] is a Cross fitting (4 physical ports or 4-way corner bends).
  static bool isCrossFitting(DsfDocument doc, {int portCount = 0}) {
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (docType.contains('cross')) return true;
    return doc.bends.length >= 14 || portCount == 4;
  }

  /// Geometrically detects whether [doc] is a Tee fitting (3 physical ports or 3-way layout).
  static bool isTeeFitting(DsfDocument doc, {int portCount = 0}) {
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (docType.contains('tee')) return true;
    return (doc.bends.length >= 9 && doc.bends.length <= 13) || portCount == 3;
  }

  /// Geometrically detects whether [doc] is a 45° Flat Bend fitting.
  static bool isBend45Geometry(DsfDocument doc) {
    final docType = '${doc.productType} ${doc.itemName} ${doc.metadata['appliedTemplate']}'.toLowerCase();
    if (docType.contains('riser') || docType.contains('rise')) return false;
    if (docType.contains('45') && docType.contains('bend')) return true;
    return doc.bends.length >= 3 && doc.bends.length <= 7 && !docType.contains('90');
  }

  /// Geometrically detects whether [doc] is a 90° Flat Bend fitting.
  static bool isBend90Geometry(DsfDocument doc) {
    final docType = '${doc.productType} ${doc.itemName} ${doc.metadata['appliedTemplate']}'.toLowerCase();
    if (docType.contains('riser') || docType.contains('rise')) return false;
    if (docType.contains('90') && docType.contains('bend')) return true;
    return doc.bends.length >= 2 && doc.bends.length <= 6 && !docType.contains('45');
  }

  /// Geometrically detects whether [doc] is a Cross fitting (4 physical ports or 4-way corner bends).
  bool isCrossGeometry(DsfDocument doc) => isCrossFitting(doc, portCount: baselinePorts.length);

  /// Checks whether [doc] is an Unequal Cross fitting based on contract, metadata, or port dimensions.
  bool isUnequalCross(DsfDocument doc) {
    if (contract == CmsProductContract.unequalCross) return true;
    if (contract == CmsProductContract.equalCross) return false;
    final docType = '${doc.productType} ${doc.itemName} ${doc.metadata['appliedTemplate']} ${doc.metadata['cmsTemplate']?['variation']}'.toLowerCase();
    if (docType.contains('unequal')) return true;
    if (docType.contains('equal')) return false;

    if (baselinePorts.length >= 2) {
      final w0 = baselinePorts.first.width;
      final h0 = baselinePorts.first.height;
      for (final p in baselinePorts) {
        if ((p.width - w0).abs() > 1.0 || (p.height - h0).abs() > 1.0) {
          return true;
        }
      }
    }
    return false;
  }

  /// Geometrically detects whether [doc] is a Tee fitting (3 physical ports or 3-way layout).
  bool isTeeGeometry(DsfDocument doc) {
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (docType.contains('tee')) return true;
    return (doc.bends.length >= 9 && doc.bends.length <= 13) || baselinePorts.length == 3;
  }

  /// Checks whether [doc] is an Unequal Tee fitting based on contract, metadata, or port dimensions.
  bool isUnequalTee(DsfDocument doc) {
    if (contract == CmsProductContract.unequalTee) return true;
    if (contract == CmsProductContract.equalTee) return false;
    final docType = '${doc.productType} ${doc.itemName} ${doc.metadata['appliedTemplate']} ${doc.metadata['cmsTemplate']?['variation']}'.toLowerCase();
    if (docType.contains('unequal')) return true;
    if (docType.contains('equal')) return false;

    if (baselinePorts.length >= 2) {
      final w0 = baselinePorts.first.width;
      final h0 = baselinePorts.first.height;
      for (final p in baselinePorts) {
        if ((p.width - w0).abs() > 1.0 || (p.height - h0).abs() > 1.0) {
          return true;
        }
      }
    }
    return false;
  }

  /// Helper struct defining the 8 symmetric coupler flaps of Equal Cross fittings.
  static const List<_EqualCrossFlapConfig> _equalCrossFlapConfigs = [
    // SE quadrant: wx = dW/2, wy = dW/2, vx = 1/sqrt2, vy = 1/sqrt2
    _EqualCrossFlapConfig(
      innerId: 'SLOT_1',
      outerId: 'SLOT_2',
      wxSign: 1,
      wySign: 1,
      vx: 0.7071067811865475,
      vy: 0.7071067811865475,
      rotDeg: 45.0,
      portId: 'PORT_3',
    ),
    _EqualCrossFlapConfig(
      innerId: 'SLOT_3',
      outerId: 'SLOT_4',
      wxSign: 1,
      wySign: 1,
      vx: 0.7071067811865475,
      vy: 0.7071067811865475,
      rotDeg: 45.0,
      portId: 'PORT_4',
    ),
    // SW quadrant: wx = -dW/2, wy = dW/2, vx = -1/sqrt2, vy = 1/sqrt2
    _EqualCrossFlapConfig(
      innerId: 'SLOT_5',
      outerId: 'SLOT_6',
      wxSign: -1,
      wySign: 1,
      vx: -0.7071067811865475,
      vy: 0.7071067811865475,
      rotDeg: 135.0,
      portId: 'PORT_4',
    ),
    _EqualCrossFlapConfig(
      innerId: 'SLOT_7',
      outerId: 'SLOT_8',
      wxSign: -1,
      wySign: 1,
      vx: -0.7071067811865475,
      vy: 0.7071067811865475,
      rotDeg: 135.0,
      portId: 'PORT_1',
    ),
    // NE quadrant: wx = dW/2, wy = -dW/2, vx = 1/sqrt2, vy = -1/sqrt2
    _EqualCrossFlapConfig(
      innerId: 'SLOT_9',
      outerId: 'SLOT_10',
      wxSign: 1,
      wySign: -1,
      vx: 0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 135.0,
      portId: 'PORT_2',
    ),
    _EqualCrossFlapConfig(
      innerId: 'SLOT_11',
      outerId: 'SLOT_12',
      wxSign: 1,
      wySign: -1,
      vx: 0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 135.0,
      portId: 'PORT_3',
    ),
    // NW quadrant: wx = -dW/2, wy = -dW/2, vx = -1/sqrt2, vy = -1/sqrt2
    _EqualCrossFlapConfig(
      innerId: 'SLOT_13',
      outerId: 'SLOT_14',
      wxSign: -1,
      wySign: -1,
      vx: -0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 45.0,
      portId: 'PORT_1',
    ),
    _EqualCrossFlapConfig(
      innerId: 'SLOT_15',
      outerId: 'SLOT_16',
      wxSign: -1,
      wySign: -1,
      vx: -0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 45.0,
      portId: 'PORT_2',
    ),
  ];

  /// Analytical 4-Quadrant Parametric 2D Sheet Scaling for Equal Cross Fittings:
  /// - Base floor is an octagonal central base with 4-way 90° symmetry.
  /// - All 4 ports have identical width and height.
  /// - Width expands symmetrically in all 4 directions (+/- dW / 2).
  /// - Cheeks and flaps expand along their respective 45° normal vector (+/- dH / sqrt(2)).
  /// - All 16 corner fillet arcs (r=10mm) are 100% preserved without disconnection or deletion.
  /// - Coupler punches follow the Universal 95mm Rule:
  ///     * Height < 95mm: exactly 1 slot centered on each flap with respect to height.
  ///     * Height >= 95mm: exactly 2 slots per flap at 50mm pitch, centered with respect to height.
  DsfDocument _scaleEqualCross2D(DsfDocument baseline, {required Map<String, CmsScalingParameter> parameters}) {
    final baseFloor = baseline.faces.firstWhere((f) => f.isBaseAnchor || f.role == FaceRole.baseFloor, orElse: () => baseline.faces.first);
    final verts = baseFloor.vertices;
    final minX = verts.map((v) => v.x).reduce(math.min);
    final maxX = verts.map((v) => v.x).reduce(math.max);
    final minY = verts.map((v) => v.y).reduce(math.min);
    final maxY = verts.map((v) => v.y).reduce(math.max);
    final midX = (minX + maxX) / 2.0;
    final midY = (minY + maxY) / 2.0;

    final w = parameters['width'];
    final h = parameters['height'];
    final targetW = w?.currentValue ?? (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    final targetH = h?.currentValue ?? (baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0);
    final baselineW = w?.baselineValue ?? (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    final baselineH = h?.baselineValue ?? (baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0);

    final dW = targetW - baselineW;
    final dH = targetH - baselineH;

    final hasCrossChange = dW.abs() > 1e-4 || dH.abs() > 1e-4;
    if (!hasCrossChange) return baseline;

    // Dynamically calculate threshold distinguishing base bends from outer flange regions
    final b1 = baseline.bends.where((b) => b.id == 'B1').firstOrNull;
    final fl2 = baseline.bends.where((b) => b.id == 'FL2').firstOrNull;
    final double sThresh;
    if (b1 != null && fl2 != null) {
      final sInner = ((b1.p1.x - midX) + (b1.p1.y - midY)).abs();
      final sOuter = ((fl2.p1.x - midX) + (fl2.p1.y - midY)).abs();
      sThresh = (sInner + sOuter) / 2.0;
    } else {
      sThresh = 195.58;
    }

    CadPoint2D transformPt(CadPoint2D pt) {
      final X = pt.x - midX;
      final Y = pt.y - midY;

      final double wx;
      final double wy;
      final double vx;
      final double vy;
      final bool isOuter;

      if (X <= 0.0 && Y <= 0.0) {
        // NW Quadrant
        wx = -dW / 2.0;
        wy = -dW / 2.0;
        vx = -1.0 / math.sqrt2;
        vy = -1.0 / math.sqrt2;
        isOuter = (X + Y) < -sThresh;
      } else if (X > 0.0 && Y <= 0.0) {
        // NE Quadrant
        wx = dW / 2.0;
        wy = -dW / 2.0;
        vx = 1.0 / math.sqrt2;
        vy = -1.0 / math.sqrt2;
        isOuter = (X - Y) > sThresh;
      } else if (X > 0.0 && Y > 0.0) {
        // SE Quadrant
        wx = dW / 2.0;
        wy = dW / 2.0;
        vx = 1.0 / math.sqrt2;
        vy = 1.0 / math.sqrt2;
        isOuter = (X + Y) > sThresh;
      } else {
        // SW Quadrant (X <= 0.0 && Y > 0.0)
        wx = -dW / 2.0;
        wy = dW / 2.0;
        vx = -1.0 / math.sqrt2;
        vy = 1.0 / math.sqrt2;
        isOuter = (X - Y) < -sThresh;
      }

      double x = pt.x + wx;
      double y = pt.y + wy;
      if (isOuter && dH.abs() > 1e-4) {
        x += dH * vx;
        y += dH * vy;
      }
      return CadPoint2D(x, y);
    }

    final newContour = baseline.outerContour.map(transformPt).toList();

    final newBends = baseline.bends.map((b) => b.copyWith(p1: transformPt(b.p1), p2: transformPt(b.p2))).toList();

    final newFaces = baseline.faces.map((f) => f.copyWith(vertices: f.vertices.map(transformPt).toList())).toList();

    final newArcs = baseline.arcs.map((a) {
      return a.copyWith(center: transformPt(a.center));
    }).toList();

    // Universal 95mm Coupler Rule:
    // Centered with respect to height on all 8 flaps across the 4 quadrants.
    final handledPunchIds = <String>{};
    final newPunches = <CncPunchPrimitive>[];

    for (final flap in _equalCrossFlapConfigs) {
      final wx = flap.wxSign * (dW / 2.0);
      final wy = flap.wySign * (dW / 2.0);

      CncPunchPrimitive? pInner = baseline.punches.where((p) => p.id == flap.innerId).firstOrNull;
      CncPunchPrimitive? pOuter = baseline.punches.where((p) => p.id == flap.outerId).firstOrNull;

      // Geometric fallback if punch IDs differ
      if (pInner == null) {
        final candidates = baseline.punches.where((p) {
          final px = p.center.x - midX;
          final py = p.center.y - midY;
          final inQuad = (flap.vx < 0 ? px <= 0 : px > 0) && (flap.vy < 0 ? py <= 0 : py > 0);
          if (!inQuad) return false;
          final isVert = flap.innerId == 'SLOT_1' || flap.innerId == 'SLOT_5' || flap.innerId == 'SLOT_9' || flap.innerId == 'SLOT_13';
          return isVert ? (px.abs() < py.abs()) : (px.abs() > py.abs());
        }).toList();

        candidates.sort((a, b) {
          final da = (a.center.x - midX) * (a.center.x - midX) + (a.center.y - midY) * (a.center.y - midY);
          final db = (b.center.x - midX) * (b.center.x - midX) + (b.center.y - midY) * (b.center.y - midY);
          return da.compareTo(db);
        });

        if (candidates.isNotEmpty) pInner = candidates[0];
        if (candidates.length > 1) pOuter = candidates[1];
      }

      if (pInner != null) handledPunchIds.add(pInner.id);
      if (pOuter != null) handledPunchIds.add(pOuter.id);

      if (pInner == null) continue;

      final CadPoint2D mBase;
      if (pOuter != null) {
        mBase = CadPoint2D((pInner.center.x + pOuter.center.x) / 2.0, (pInner.center.y + pOuter.center.y) / 2.0);
      } else {
        mBase = pInner.center;
      }

      // Scaled flap center
      final mTarget = CadPoint2D(mBase.x + wx + (dH / 2.0) * flap.vx, mBase.y + wy + (dH / 2.0) * flap.vy);

      if (targetH < 95.0) {
        // Single slot centered on flap with respect to height
        newPunches.add(pInner.copyWith(center: mTarget, rotationDeg: flap.rotDeg));
      } else {
        // Two slots at 50mm pitch, centered on flap with respect to height
        final innerCenter = CadPoint2D(mTarget.x - 25.0 * flap.vx, mTarget.y - 25.0 * flap.vy);
        final outerCenter = CadPoint2D(mTarget.x + 25.0 * flap.vx, mTarget.y + 25.0 * flap.vy);

        newPunches.add(pInner.copyWith(center: innerCenter, rotationDeg: flap.rotDeg));

        final outerPunch =
            pOuter?.copyWith(center: outerCenter, rotationDeg: flap.rotDeg) ??
            CncPunchPrimitive(
              id: flap.outerId,
              type: PunchType.obroundSlot,
              center: outerCenter,
              widthMm: pInner.widthMm,
              lengthMm: pInner.lengthMm,
              diameterMm: pInner.diameterMm,
              rotationDeg: flap.rotDeg,
              role: CncPunchRole.coupler,
              parentFaceId: pInner.parentFaceId,
              associatedPortId: flap.portId,
              layer: pInner.layer,
              showLabel: true,
              isVisible: true,
            );
        newPunches.add(outerPunch);
      }
    }

    // Preserve and transform any other non-coupler punches (e.g. floor stampings)
    for (final p in baseline.punches) {
      if (!handledPunchIds.contains(p.id)) {
        newPunches.add(p.copyWith(center: transformPt(p.center)));
      }
    }

    final updatedParams = Map<String, double>.from(baseline.parameters);
    updatedParams['width'] = targetW;
    updatedParams['height'] = targetH;
    for (int i = 1; i <= 4; i++) {
      updatedParams['port${i}_width'] = targetW;
      updatedParams['port${i}_height'] = targetH;
    }

    return baseline.copyWith(outerContour: newContour, bends: newBends, faces: newFaces, arcs: newArcs, punches: newPunches, parameters: updatedParams);
  }

  /// Dedicated 2D Sheet Scaling for Unequal Cross Fittings:
  /// Routes to the analytical [UnequalCrossScaler] which preserves:
  /// - All 16 corner fillet arcs (r=10mm)
  /// - Universal 95mm coupler rule for punches
  /// - Hbody = max(H1, H2, H3, H4) with orthogonal non-slanted steps
  /// - Closed-form base floor F_16 without bend line shear
  DsfDocument _scaleUnequalCross2D(DsfDocument baseline, {required bool isLinked, required Map<String, CmsScalingParameter> parameters}) {
    final scaleParams = UnequalCrossScaleParameters.fromCmsParameters(parameters);
    final result = UnequalCrossScaler.scale(baseline: baseline, parameters: scaleParams);
    return result.document;
  }

  /// Cross scaling dispatcher: routes to equal or unequal subroutine based on [isLinked].
  DsfDocument _scaleCross2D(DsfDocument baseline, {required bool isLinked, required Map<String, CmsScalingParameter> parameters}) {
    if (isLinked) {
      return _scaleEqualCross2D(baseline, parameters: parameters);
    } else {
      return _scaleUnequalCross2D(baseline, isLinked: isLinked, parameters: parameters);
    }
  }

  /// Helper struct defining the 6 coupler flap & sidewall regions of Equal Tee fittings.
  static const List<_EqualTeeFlapConfig> _equalTeeFlapConfigs = [
    // Left Cheek: Port 1 left flange
    _EqualTeeFlapConfig(
      innerId: 'SLOT_9',
      outerId: 'SLOT_10',
      wxSign: -1,
      hasWyShift: false,
      vx: -0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 45.0,
      portId: 'port1',
    ),
    // Left Cheek: Port 3 top flange
    _EqualTeeFlapConfig(
      innerId: 'SLOT_11',
      outerId: 'SLOT_12',
      wxSign: -1,
      hasWyShift: false,
      vx: -0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 45.0,
      portId: 'port3',
    ),
    // Right Cheek: Port 1 right flange
    _EqualTeeFlapConfig(
      innerId: 'SLOT_1',
      outerId: 'SLOT_2',
      wxSign: 1,
      hasWyShift: false,
      vx: 0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 135.0,
      portId: 'port1',
    ),
    // Right Cheek: Port 2 top flange
    _EqualTeeFlapConfig(
      innerId: 'SLOT_3',
      outerId: 'SLOT_4',
      wxSign: 1,
      hasWyShift: false,
      vx: 0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 135.0,
      portId: 'port2',
    ),
    // Bottom Sidewall: Left side (Port 3 run)
    _EqualTeeFlapConfig(innerId: 'SLOT_8', outerId: 'SLOT_7', wxSign: -1, hasWyShift: true, vx: 0.0, vy: 1.0, rotDeg: 90.0, portId: 'port3'),
    // Bottom Sidewall: Right side (Port 2 run)
    _EqualTeeFlapConfig(innerId: 'SLOT_6', outerId: 'SLOT_5', wxSign: 1, hasWyShift: true, vx: 0.0, vy: 1.0, rotDeg: 90.0, portId: 'port2'),
  ];

  /// Analytical Parametric 2D Sheet Scaling for Equal Tee Fittings:
  /// - Base floor web with Main Run and Branch mouth.
  /// - All 3 ports are identical in width and height.
  /// - Branch width scales horizontally (+/- dW / 2); Main run channel depth scales vertically (+dW).
  /// - Cheeks expand outward along their 45° normal vector (+/- dH / sqrt(2)).
  /// - Bottom sidewall F_10 and return flange F_9 expand vertically (+dH).
  /// - All 12 corner fillet arcs (r=10mm) are 100% preserved and synchronized without disconnection or orphan anchoring dots.
  /// - Coupler punches follow the Universal 95mm Rule:
  ///     * Height < 95mm: exactly 1 slot centered on each flap/sidewall region with respect to height.
  ///     * Height >= 95mm: exactly 2 slots per region at 50mm pitch, centered with respect to height.
  DsfDocument _scaleEqualTee2D(DsfDocument baseline, {required Map<String, CmsScalingParameter> parameters}) {
    final baseFloor = baseline.faces.firstWhere((f) => f.isBaseAnchor || f.role == FaceRole.baseFloor, orElse: () => baseline.faces.first);
    final verts = baseFloor.vertices;
    final minX = verts.map((v) => v.x).reduce(math.min);
    final maxX = verts.map((v) => v.x).reduce(math.max);
    final maxY = verts.map((v) => v.y).reduce(math.max);
    final midX = (minX + maxX) / 2.0;

    final w = parameters['width'];
    final h = parameters['height'];
    final metaPort1 = (baseline.metadata['ports'] is List && (baseline.metadata['ports'] as List).isNotEmpty)
        ? (baseline.metadata['ports'] as List).first as Map<String, dynamic>
        : null;
    final fallbackW = metaPort1?['width'] is num ? (metaPort1!['width'] as num).toDouble() : (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    final fallbackH = metaPort1?['height'] is num ? (metaPort1!['height'] as num).toDouble() : (baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0);

    final targetW = w?.currentValue ?? fallbackW;
    final targetH = h?.currentValue ?? fallbackH;
    final baselineW = w?.baselineValue ?? fallbackW;
    final baselineH = h?.baselineValue ?? fallbackH;

    final dW = targetW - baselineW;
    final dH = targetH - baselineH;

    final hasTeeChange = dW.abs() > 1e-4 || dH.abs() > 1e-4;
    if (!hasTeeChange) return baseline;

    // Left cheek threshold: between B1 (inner) and FL2 (outer)
    final b1 = baseline.bends.where((b) => b.id == 'B1').firstOrNull;
    final fl2 = baseline.bends.where((b) => b.id == 'FL2').firstOrNull;
    final double sLeft;
    if (b1 != null && fl2 != null) {
      final sInner = (b1.p1.x + b1.p2.x + b1.p1.y + b1.p2.y) / 2.0;
      final sOuter = (fl2.p1.x + fl2.p2.x + fl2.p1.y + fl2.p2.y) / 2.0;
      sLeft = (sInner + sOuter) / 2.0;
    } else {
      sLeft = 125.16;
    }

    // Right cheek threshold: between B2 (inner) and FL3 (outer)
    final b2 = baseline.bends.where((b) => b.id == 'B2').firstOrNull;
    final fl3 = baseline.bends.where((b) => b.id == 'FL3').firstOrNull;
    final double sRight;
    if (b2 != null && fl3 != null) {
      final sInner = ((b2.p1.x + b2.p2.x) - (b2.p1.y + b2.p2.y)) / 2.0;
      final sOuter = ((fl3.p1.x + fl3.p2.x) - (fl3.p1.y + fl3.p2.y)) / 2.0;
      sRight = (sInner + sOuter) / 2.0;
    } else {
      sRight = 194.88;
    }

    // Bottom sidewall threshold: between B3 (inner) and FL1 (outer)
    final b3 = baseline.bends.where((b) => b.id == 'B3').firstOrNull;
    final fl1 = baseline.bends.where((b) => b.id == 'FL1').firstOrNull;
    final double sBottom;
    if (b3 != null && fl1 != null) {
      final sInner = (b3.p1.y + b3.p2.y) / 2.0;
      final sOuter = (fl1.p1.y + fl1.p2.y) / 2.0;
      sBottom = (sInner + sOuter) / 2.0;
    } else {
      sBottom = 257.52;
    }

    CadPoint2D transformEqualTeePt(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      // --- Width (Branch & Main Run) ---
      if (pt.x > midX + 5.0) {
        x += dW / 2.0;
      } else if (pt.x < midX - 5.0) {
        x -= dW / 2.0;
      }
      if (pt.y > maxY - 15.0) {
        y += dW;
      }

      // --- Physical Body Height Scaling ---
      if (dH.abs() > 1e-4) {
        // Bottom sidewall outer region (FL1 and F_9)
        if (pt.y > sBottom) {
          y += dH;
        }

        // Left cheek outer region
        if (pt.x < midX && (pt.x + pt.y) < sLeft) {
          x -= dH / math.sqrt2;
          y -= dH / math.sqrt2;
        }

        // Right cheek outer region
        if (pt.x > midX && (pt.x - pt.y) > sRight) {
          x += dH / math.sqrt2;
          y -= dH / math.sqrt2;
        }
      }

      return CadPoint2D(x, y);
    }

    final newContour = baseline.outerContour.map(transformEqualTeePt).toList();

    final newBends = baseline.bends.map((b) => b.copyWith(p1: transformEqualTeePt(b.p1), p2: transformEqualTeePt(b.p2))).toList();

    final newFaces = baseline.faces.map((f) => f.copyWith(vertices: f.vertices.map(transformEqualTeePt).toList())).toList();

    final newArcs = baseline.arcs.map((a) {
      return a.copyWith(center: transformEqualTeePt(a.center));
    }).toList();

    // Universal 95mm Coupler Rule:
    // Centered with respect to height on all 6 flaps/sidewall regions.
    final handledPunchIds = <String>{};
    final newPunches = <CncPunchPrimitive>[];

    for (final flap in _equalTeeFlapConfigs) {
      final wx = flap.wxSign * (dW / 2.0);
      final wy = flap.hasWyShift ? dW : 0.0;

      CncPunchPrimitive? pInner = baseline.punches.where((p) => p.id == flap.innerId).firstOrNull;
      CncPunchPrimitive? pOuter = baseline.punches.where((p) => p.id == flap.outerId).firstOrNull;

      // Geometric fallback if punch IDs differ
      if (pInner == null) {
        final candidates = baseline.punches.where((p) {
          if (flap.hasWyShift) {
            final isBottom = p.center.y > maxY - 15.0;
            if (!isBottom) return false;
            return flap.wxSign < 0 ? (p.center.x < midX) : (p.center.x > midX);
          } else {
            final isCheek = p.center.y <= maxY - 15.0;
            if (!isCheek) return false;
            final isLeft = p.center.x < midX;
            if (flap.wxSign < 0 != isLeft) return false;
            if (isLeft) {
              final isBranch = flap.portId == 'port1';
              return isBranch ? (p.center.x > p.center.y) : (p.center.x <= p.center.y);
            } else {
              final isBranch = flap.portId == 'port1';
              return isBranch ? (p.center.y < 60.0) : (p.center.y >= 60.0);
            }
          }
        }).toList();

        candidates.sort((a, b) {
          if (flap.hasWyShift) {
            return a.center.y.compareTo(b.center.y);
          } else if (flap.wxSign < 0) {
            final da = a.center.x + a.center.y;
            final db = b.center.x + b.center.y;
            return db.compareTo(da);
          } else {
            final da = a.center.x - a.center.y;
            final db = b.center.x - b.center.y;
            return da.compareTo(db);
          }
        });

        if (candidates.isNotEmpty) pInner = candidates[0];
        if (candidates.length > 1) pOuter = candidates[1];
      }

      if (pInner != null) handledPunchIds.add(pInner.id);
      if (pOuter != null) handledPunchIds.add(pOuter.id);

      if (pInner == null) continue;

      final CadPoint2D mBase;
      if (pOuter != null) {
        mBase = CadPoint2D((pInner.center.x + pOuter.center.x) / 2.0, (pInner.center.y + pOuter.center.y) / 2.0);
      } else {
        mBase = pInner.center;
      }

      // Scaled flap center
      final mTarget = CadPoint2D(mBase.x + wx + (dH / 2.0) * flap.vx, mBase.y + wy + (dH / 2.0) * flap.vy);

      if (targetH < 95.0) {
        // Single slot centered on flap with respect to height
        newPunches.add(pInner.copyWith(center: mTarget, rotationDeg: flap.rotDeg));
      } else {
        // Two slots at 50mm pitch, centered on flap with respect to height
        final innerCenter = CadPoint2D(mTarget.x - 25.0 * flap.vx, mTarget.y - 25.0 * flap.vy);
        final outerCenter = CadPoint2D(mTarget.x + 25.0 * flap.vx, mTarget.y + 25.0 * flap.vy);

        newPunches.add(pInner.copyWith(center: innerCenter, rotationDeg: flap.rotDeg));

        final outerPunch =
            pOuter?.copyWith(center: outerCenter, rotationDeg: flap.rotDeg) ??
            CncPunchPrimitive(
              id: flap.outerId,
              type: PunchType.obroundSlot,
              center: outerCenter,
              widthMm: pInner.widthMm,
              lengthMm: pInner.lengthMm,
              diameterMm: pInner.diameterMm,
              rotationDeg: flap.rotDeg,
              role: CncPunchRole.coupler,
              parentFaceId: pInner.parentFaceId,
              associatedPortId: flap.portId,
              layer: pInner.layer,
              showLabel: true,
              isVisible: true,
            );
        newPunches.add(outerPunch);
      }
    }

    // Preserve and transform any other non-coupler punches (e.g. floor stampings)
    for (final p in baseline.punches) {
      if (!handledPunchIds.contains(p.id)) {
        newPunches.add(p.copyWith(center: transformEqualTeePt(p.center)));
      }
    }

    final updatedParams = Map<String, double>.from(baseline.parameters);
    updatedParams['width'] = targetW;
    updatedParams['height'] = targetH;
    for (int i = 1; i <= 3; i++) {
      updatedParams['port${i}_width'] = targetW;
      updatedParams['port${i}_height'] = targetH;
    }

    return baseline.copyWith(outerContour: newContour, bends: newBends, faces: newFaces, arcs: newArcs, punches: newPunches, parameters: updatedParams);
  }

  /// Dedicated 2D Sheet Scaling for Unequal Tee Fittings:
  /// Dispatches to the standalone analytical [UnequalTeeScaler].
  DsfDocument _scaleUnequalTee2D(DsfDocument baseline, {required bool isLinked, required Map<String, CmsScalingParameter> parameters}) {
    final scaleParams = isLinked
        ? UnequalTeeScaleParameters(
            port1Width: parameters['width']?.currentValue ?? 100.0,
            port1Height: parameters['height']?.currentValue ?? 100.0,
            port2Width: parameters['width']?.currentValue ?? 50.0,
            port2Height: parameters['height']?.currentValue ?? 50.0,
            port3Width: parameters['width']?.currentValue ?? 100.0,
            port3Height: parameters['height']?.currentValue ?? 100.0,
            sheetThickness: parameters['thickness']?.currentValue ?? 1.5,
            flangeWidth: parameters['flange']?.currentValue ?? 10.0,
          )
        : UnequalTeeScaleParameters.fromCmsParameters(parameters);

    final res = UnequalTeeScaler.scale(baseline: baseline, parameters: scaleParams);
    return res.isValid ? res.document : baseline;
  }

  /// Tee scaling dispatcher: routes to equal or unequal subroutine based on [isLinked].
  DsfDocument _scaleTee2D(DsfDocument baseline, {required bool isLinked, required Map<String, CmsScalingParameter> parameters}) {
    if (isLinked) {
      return _scaleEqualTee2D(baseline, parameters: parameters);
    } else {
      return _scaleUnequalTee2D(baseline, isLinked: isLinked, parameters: parameters);
    }
  }

  /// Dedicated 2D Sheet Scaling for 45° Flat Bend Fittings:
  /// - Scales Width and Height simultaneously from baseline in a single analytical pass.
  /// - Preserves all 8 corner fillet arcs (r=10mm) 100% attached to outer contour vertices.
  /// - Universal 95mm Coupler Rule:
  ///     * Height < 95mm: exactly 1 slot centered on each flap/mouth region with respect to height.
  ///     * Height >= 95mm: exactly 2 slots per region at 50mm pitch, centered with respect to height.
  /// - Updates physical ports (Port 1 and Port 2) with synchronized width and height.
  DsfDocument _scaleFlatBend45_2D(DsfDocument baseline, {required Map<String, CmsScalingParameter> parameters}) {
    final w = parameters['width'];
    final h = parameters['height'];
    final metaPort1 = (baseline.metadata['ports'] is List && (baseline.metadata['ports'] as List).isNotEmpty)
        ? (baseline.metadata['ports'] as List).first as Map<String, dynamic>
        : null;
    final fallbackW = metaPort1?['width'] is num ? (metaPort1!['width'] as num).toDouble() : (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    final fallbackH = metaPort1?['height'] is num ? (metaPort1!['height'] as num).toDouble() : (baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0);

    final targetW = w?.currentValue ?? fallbackW;
    final targetH = h?.currentValue ?? fallbackH;
    final baselineW = w?.baselineValue ?? fallbackW;
    final baselineH = h?.baselineValue ?? fallbackH;

    final hasChange = (targetW - baselineW).abs() > 1e-4 || (targetH - baselineH).abs() > 1e-4;
    if (!hasChange) return baseline;

    final templateDef = TemplateParameterDefinition(
      templateId: '45_deg_bend',
      name: contract.variationName,
      category: contract.productType,
      productType: contract.productType,
      baselineParameters: {'width': baselineW, 'height': baselineH, 'flangeWidth': 15.0},
      parameters: [],
    );

    var morphed = TopologicalZoneMorpher.morph(
      baselineDocument: baseline,
      template: templateDef,
      targetParameters: {'width': targetW, 'height': targetH, 'flangeWidth': 15.0},
    );

    if (baseline.dimensions.isNotEmpty || baseline.constraints.isNotEmpty) {
      if ((targetH - baselineH).abs() > 1e-4) {
        morphed = CmsPunchConstraintEngine.reconcile(baseline: baseline, scaled: morphed, paramId: 'height', delta: targetH - baselineH);
      }
      if ((targetW - baselineW).abs() > 1e-4) {
        morphed = CmsPunchConstraintEngine.reconcile(baseline: baseline, scaled: morphed, paramId: 'width', delta: targetW - baselineW);
      }
    }

    final updatedParams = Map<String, double>.from(morphed.parameters);
    updatedParams['width'] = targetW;
    updatedParams['height'] = targetH;
    updatedParams['port1_width'] = targetW;
    updatedParams['port1_height'] = targetH;
    updatedParams['port2_width'] = targetW;
    updatedParams['port2_height'] = targetH;

    return morphed.copyWith(parameters: updatedParams);
  }

  /// Dedicated 2D Sheet Scaling for 90° Flat Bend Fittings:
  /// - Scales Width and Height simultaneously from baseline in a single analytical pass.
  /// - Preserves all corner fillet arcs (r=10mm) attached to outer contour vertices.
  /// - Universal 95mm Coupler Rule applied to coupler punches.
  /// - Updates physical ports (Port 1 and Port 2) with synchronized width and height.
  DsfDocument _scaleFlatBend90_2D(DsfDocument baseline, {required Map<String, CmsScalingParameter> parameters}) {
    final w = parameters['width'];
    final h = parameters['height'];
    final metaPort1 = (baseline.metadata['ports'] is List && (baseline.metadata['ports'] as List).isNotEmpty)
        ? (baseline.metadata['ports'] as List).first as Map<String, dynamic>
        : null;
    final fallbackW = metaPort1?['width'] is num ? (metaPort1!['width'] as num).toDouble() : (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    final fallbackH = metaPort1?['height'] is num ? (metaPort1!['height'] as num).toDouble() : (baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0);

    final targetW = w?.currentValue ?? fallbackW;
    final targetH = h?.currentValue ?? fallbackH;
    final baselineW = w?.baselineValue ?? fallbackW;
    final baselineH = h?.baselineValue ?? fallbackH;

    final hasChange = (targetW - baselineW).abs() > 1e-4 || (targetH - baselineH).abs() > 1e-4;
    if (!hasChange) return baseline;

    final templateDef = TemplateParameterDefinition(
      templateId: '90_deg_bend',
      name: contract.variationName,
      category: contract.productType,
      productType: contract.productType,
      baselineParameters: {'width': baselineW, 'height': baselineH, 'flangeWidth': 15.0},
      parameters: [],
    );

    var morphed = TopologicalZoneMorpher.morph(
      baselineDocument: baseline,
      template: templateDef,
      targetParameters: {'width': targetW, 'height': targetH, 'flangeWidth': 15.0},
    );

    if (baseline.dimensions.isNotEmpty || baseline.constraints.isNotEmpty) {
      if ((targetH - baselineH).abs() > 1e-4) {
        morphed = CmsPunchConstraintEngine.reconcile(baseline: baseline, scaled: morphed, paramId: 'height', delta: targetH - baselineH);
      }
      if ((targetW - baselineW).abs() > 1e-4) {
        morphed = CmsPunchConstraintEngine.reconcile(baseline: baseline, scaled: morphed, paramId: 'width', delta: targetW - baselineW);
      }
    }

    final updatedParams = Map<String, double>.from(morphed.parameters);
    updatedParams['width'] = targetW;
    updatedParams['height'] = targetH;
    updatedParams['port1_width'] = targetW;
    updatedParams['port1_height'] = targetH;
    updatedParams['port2_width'] = targetW;
    updatedParams['port2_height'] = targetH;

    return morphed.copyWith(parameters: updatedParams);
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

  DsfDocument _generateScaled2DDocument({required DsfDocument baseline, required String paramId, required double delta}) {
    final morphed = _morph2DBlank(baseline: baseline, paramId: paramId, delta: delta);
    if (effectiveScalingProfile == CmsScalingProfile.outsideRiser ||
        isOutsideRiserGeometry(baseline) ||
        effectiveScalingProfile == CmsScalingProfile.insideRiser ||
        isInsideRiserGeometry(baseline) ||
        effectiveScalingProfile == CmsScalingProfile.reducer ||
        isReducerGeometry(baseline)) {
      return morphed;
    }
    return CmsPunchConstraintEngine.reconcile(baseline: baseline, scaled: morphed, paramId: paramId, delta: delta);
  }

  DsfDocument _morph2DBlank({required DsfDocument baseline, required String paramId, required double delta}) {
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
        templateId: profile == CmsScalingProfile.flatBend45 ? '45_deg_bend' : (profile == CmsScalingProfile.flatBend90 ? '90_deg_bend' : 'equal_tee'),
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

    final b45 = baseline.bends.firstWhere((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0, orElse: () => baseline.bends.first);
    final has45 = (b45.targetAngleDeg.abs() - 45.0).abs() < 15.0;

    double x1;
    double x2;
    if (has45 && (b45.p2.x - b45.p1.x).abs() > 20.0) {
      x1 = math.min(b45.p1.x, b45.p2.x);
      x2 = math.max(b45.p1.x, b45.p2.x);
    } else {
      final vertBends = baseline.bends.where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0).toList()
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
      return b.copyWith(p1: transformPt(b.p1), p2: transformPt(b.p2));
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    final newPunches = baseline.punches.map((p) {
      return p.copyWith(center: transformPt(p.center));
    }).toList();

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(p1: transformPt(cl.p1), p2: transformPt(cl.p2));
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final dx = newCenter.x - a.center.x;
      final dy = newCenter.y - a.center.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(outerContour: newContour, bends: newBends, cutLines: newCutLines);

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
    final hasCompleteTopology = baseline.faces.isNotEmpty && baseline.bends.isNotEmpty && baseline.bends.every((b) => b.parentFaceId.isNotEmpty);

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

    final cheekBends = baseline.bends
        .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
        .toList();

    if (cheekBends.length < 2) return _scaleWidth2D(baseline, delta);

    final isHorizontal = (cheekBends.first.p2.x - cheekBends.first.p1.x).abs() > (cheekBends.first.p2.y - cheekBends.first.p1.y).abs();

    late final CadPoint2D Function(CadPoint2D) transformPt;
    double? normX1;
    double? normX2;
    double? normYTop;

    if (isHorizontal) {
      // 90° Outside Riser: cheek bends run horizontally along X.
      // Width is along Y (distance between B1 and B2).
      cheekBends.sort((a, b) => ((a.p1.y + a.p2.y) / 2.0).compareTo((b.p1.y + b.p2.y) / 2.0));
      final b1 = cheekBends.first;
      final b2 = cheekBends.last;
      final y1 = math.min((b1.p1.y + b1.p2.y) / 2.0, (b2.p1.y + b2.p2.y) / 2.0);
      final y2 = math.max((b1.p1.y + b1.p2.y) / 2.0, (b2.p1.y + b2.p2.y) / 2.0);
      final yMid = (y1 + y2) / 2.0;
      final floorSpan = y2 - y1;
      if (floorSpan < 10.0) return _scaleWidth2D(baseline, delta);

      final halfDelta = delta / 2.0;

      transformPt = (CadPoint2D pt) {
        if (pt.y < yMid) {
          return CadPoint2D(pt.x, pt.y - halfDelta);
        } else {
          return CadPoint2D(pt.x, pt.y + halfDelta);
        }
      };
    } else {
      // 45° Outside Riser: cheek bends run vertically along Y.
      // Width is along X (distance between B1 and B2).
      cheekBends.sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));
      final b1 = cheekBends.first;
      final b2 = cheekBends.last;
      final x1 = math.min((b1.p1.x + b1.p2.x) / 2.0, (b2.p1.x + b2.p2.x) / 2.0);
      final x2 = math.max((b1.p1.x + b1.p2.x) / 2.0, (b2.p1.x + b2.p2.x) / 2.0);
      final xMid = (x1 + x2) / 2.0;
      final floorSpan = x2 - x1;
      if (floorSpan < 10.0) return _scaleWidth2D(baseline, delta);

      final halfDelta = delta / 2.0;
      final yFloorTop = math.max(math.max(b1.p1.y, b1.p2.y), math.max(b2.p1.y, b2.p2.y));
      normX1 = x1 - halfDelta;
      normX2 = x2 + halfDelta;
      normYTop = yFloorTop;

      transformPt = (CadPoint2D pt) {
        // 1. Above floor web (flared cheek prongs):
        if (pt.y > yFloorTop + 0.5) {
          return pt.x < xMid ? CadPoint2D(pt.x - halfDelta, pt.y) : CadPoint2D(pt.x + halfDelta, pt.y);
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
      };
    }

    final newContour = baseline.outerContour.map(transformPt).toList();

    final newBends = baseline.bends.map((b) {
      return b.copyWith(p1: transformPt(b.p1), p2: transformPt(b.p2));
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    final newPunches = baseline.punches.map((p) {
      return p.copyWith(center: transformPt(p.center));
    }).toList();

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(p1: transformPt(cl.p1), p2: transformPt(cl.p2));
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final dx = newCenter.x - a.center.x;
      final dy = newCenter.y - a.center.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(outerContour: newContour, bends: newBends, cutLines: newCutLines);

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
    final hasCompleteTopology = baseline.faces.isNotEmpty && baseline.bends.isNotEmpty && baseline.bends.every((b) => b.parentFaceId.isNotEmpty);

    if (hasCompleteTopology || isHorizontal) {
      return doc;
    }

    return _normalizeRiserTopology(doc, normX1!, normX2!, normYTop!);
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

    final cheekBends = baseline.bends
        .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
        .toList();
    final isHorizontal = cheekBends.isNotEmpty && (cheekBends.first.p2.x - cheekBends.first.p1.x).abs() > (cheekBends.first.p2.y - cheekBends.first.p1.y).abs();

    if (isHorizontal) {
      return _scaleOutsideRiserHeight2DHorizontal(baseline, delta);
    }

    // Identify vertical bends
    final vertBends = baseline.bends.where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0).toList()
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

    final b1Bend = vertBends.firstWhere((b) => ((b.p1.x + b.p2.x) / 2.0 - x1).abs() < 10.0, orElse: () => vertBends.first);
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

        // Intermediate straight sidewall region (between Port 1 bottom and 45° throat):
        // shift rigidly outward with the left cheek.
        return CadPoint2D(pt.x - delta, pt.y);
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

        // Intermediate straight sidewall region (between Port 1 bottom and 45° throat):
        // shift rigidly outward with the right cheek.
        return CadPoint2D(pt.x + delta, pt.y);
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
        final p1 = b.p1.y <= yFloorBottom + 1.0 ? CadPoint2D(b.p1.x + shiftX, b.p1.y) : CadPoint2D(b.p1.x + shiftX, b.p1.y + dYStep);
        final p2 = b.p2.y <= yFloorBottom + 1.0 ? CadPoint2D(b.p2.x + shiftX, b.p2.y) : CadPoint2D(b.p2.x + shiftX, b.p2.y + dYStep);
        return b.copyWith(p1: p1, p2: p2);
      }
      return b;
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    List<CncPunchPrimitive> newPunches = baseline.punches.map((p) {
      return p.copyWith(center: transformPunchCenter(p));
    }).toList();

    // SS4: Coupler slot count rule — for target height < 95 mm keep only the
    // single inner slot per port mouth; remove the outer (further-from-floor) slot.
    final baseH = baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0;
    final targetH = baseH + delta;
    if (targetH < 95.0) {
      final xLeftMid = (xFL1 + x1) / 2.0;
      final xRightMid = (x2 + xFL2) / 2.0;
      newPunches = newPunches.where((p) {
        if (!p.isCoupler) return true;
        final cx = p.center.x;
        final cy = p.center.y;
        if (cx < xMid) {
          // Left cheek: keep SLOT_8 (inner, cx > xLeftMid) & SLOT_1 (inner, cy < yFloorTop+35)
          if (p.rotationDeg == 0.0) return cx > xLeftMid; // remove SLOT_7 (outer)
          return cy < yFloorTop + 35.0; // remove SLOT_2 (outer)
        } else {
          // Right cheek: keep SLOT_6 (inner, cx < xRightMid) & SLOT_3 (inner, cy < yFloorTop+35)
          if (p.rotationDeg == 0.0) return cx < xRightMid; // remove SLOT_5 (outer)
          return cy < yFloorTop + 35.0; // remove SLOT_4 (outer)
        }
      }).toList();
    }

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(p1: transformPt(cl.p1), p2: transformPt(cl.p2));
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final dx = newCenter.x - a.center.x;
      final dy = newCenter.y - a.center.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(outerContour: newContour, bends: newBends, cutLines: newCutLines);

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

  static const List<_OutsideRiser90FlapConfig> _outsideRiser90FlapConfigs = [
    // Flap 1: Cheek 1 Left (Port 1)
    _OutsideRiser90FlapConfig(
      innerId: 'SLOT_1',
      outerId: 'SLOT_2',
      wxSign: -1.0,
      wySign: -1.0,
      vx: -0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 45.0,
      portId: 'port1',
    ),
    // Flap 2: Cheek 1 Right (Port 2)
    _OutsideRiser90FlapConfig(
      innerId: 'SLOT_3',
      outerId: 'SLOT_4',
      wxSign: 1.0,
      wySign: -1.0,
      vx: 0.7071067811865475,
      vy: -0.7071067811865475,
      rotDeg: 135.0,
      portId: 'port2',
    ),
    // Flap 3: Cheek 2 Left (Port 1)
    _OutsideRiser90FlapConfig(
      innerId: 'SLOT_5',
      outerId: 'SLOT_6',
      wxSign: -1.0,
      wySign: 1.0,
      vx: -0.7071067811865475,
      vy: 0.7071067811865475,
      rotDeg: 135.0,
      portId: 'port1',
    ),
    // Flap 4: Cheek 2 Right (Port 2)
    _OutsideRiser90FlapConfig(
      innerId: 'SLOT_7',
      outerId: 'SLOT_8',
      wxSign: 1.0,
      wySign: 1.0,
      vx: 0.7071067811865475,
      vy: 0.7071067811865475,
      rotDeg: 45.0,
      portId: 'port2',
    ),
  ];

  /// Dedicated 2D 90° Outside Riser Height Scaling (Horizontal Bends):
  /// - Central Floor Web (between y1 and y2) and horizontal bend lines B1 and B2 remain stationary.
  /// - Sidewall cheeks expand outward along Y by delta (FL1 shifts by -delta, FL2 shifts by +delta).
  /// - 45° cheek mouth edges expand strictly along 45° vectors (±delta, ±delta),
  ///   preserving the exact 45° miter angle (slope = ±1.0) with zero distortion.
  /// - Coupler slots translate centered on cheek mouths (8 slots for height >= 95mm; 4 slots for < 95mm).
  DsfDocument _scaleOutsideRiserHeight2DHorizontal(DsfDocument baseline, double delta) {
    final cheekBends =
        baseline.bends
            .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
            .toList()
          ..sort((a, b) => ((a.p1.y + a.p2.y) / 2.0).compareTo((b.p1.y + b.p2.y) / 2.0));

    if (cheekBends.length < 2) return _scaleHeight2D(baseline, delta);

    final b1 = cheekBends.first;
    final b2 = cheekBends.last;
    final y1 = math.min((b1.p1.y + b1.p2.y) / 2.0, (b2.p1.y + b2.p2.y) / 2.0); // 106.0
    final y2 = math.max((b1.p1.y + b1.p2.y) / 2.0, (b2.p1.y + b2.p2.y) / 2.0); // 204.0
    final yMid = (y1 + y2) / 2.0; // 155.0

    final fl1Bends = baseline.bends.where((b) => (b.p1.y + b.p2.y) / 2.0 < y1 - 10.0);
    final fl2Bends = baseline.bends.where((b) => (b.p1.y + b.p2.y) / 2.0 > y2 + 10.0);
    final yFL1 = fl1Bends.isNotEmpty ? (fl1Bends.first.p1.y + fl1Bends.first.p2.y) / 2.0 : y1 - 96.0; // 10.0
    final yFL2 = fl2Bends.isNotEmpty ? (fl2Bends.first.p1.y + fl2Bends.first.p2.y) / 2.0 : y2 + 96.0; // 300.0

    final xFloorLeft = math.min(math.min(b1.p1.x, b1.p2.x), math.min(b2.p1.x, b2.p2.x)); // 82.08
    final xFloorRight = math.max(math.max(b1.p1.x, b1.p2.x), math.max(b2.p1.x, b2.p2.x)); // 145.72
    final xMid = (xFloorLeft + xFloorRight) / 2.0; // 113.90
    final xThroatLeft = 53.80;
    final xThroatRight = 174.01;

    CadPoint2D transformPt(CadPoint2D pt) {
      // 1. Central Floor Web & B1/B2
      if (pt.y >= y1 - 0.5 && pt.y <= y2 + 0.5 && pt.x >= xFloorLeft - 0.5 && pt.x <= xFloorRight + 0.5) {
        return pt;
      }

      // Throat inner relief areas near B1/B2
      if (pt.y >= y1 - 5.0 && pt.y <= y2 + 5.0 && pt.x >= xThroatLeft - 0.5 && pt.x <= xThroatRight + 0.5) {
        return pt;
      }

      // 2. Bottom Cheek (pt.y < yMid)
      if (pt.y < yMid) {
        // Return flange F_1 (y <= yFL1 + 0.5)
        if (pt.y <= yFL1 + 0.5) {
          final signX = pt.x < xMid ? -1.0 : 1.0;
          return CadPoint2D(pt.x + signX * delta, pt.y - delta);
        }

        // Left mouth (Port 1: x < xMid)
        if (pt.x < xMid) {
          if (pt.x <= xThroatLeft + 0.5) {
            return CadPoint2D(pt.x - delta, pt.y - delta);
          }
          return CadPoint2D(pt.x, pt.y - delta);
        } else {
          // Right mouth (Port 2: x >= xMid)
          if (pt.x >= xThroatRight - 0.5) {
            return CadPoint2D(pt.x + delta, pt.y - delta);
          }
          return CadPoint2D(pt.x, pt.y - delta);
        }
      }

      // 3. Top Cheek (pt.y >= yMid)
      // Return flange F_0 (y >= yFL2 - 0.5)
      if (pt.y >= yFL2 - 0.5) {
        final signX = pt.x < xMid ? -1.0 : 1.0;
        return CadPoint2D(pt.x + signX * delta, pt.y + delta);
      }

      // Left mouth (Port 1: x < xMid)
      if (pt.x < xMid) {
        if (pt.x <= xThroatLeft + 0.5) {
          return CadPoint2D(pt.x - delta, pt.y + delta);
        }
        return CadPoint2D(pt.x, pt.y + delta);
      } else {
        // Right mouth (Port 2: x >= xMid)
        if (pt.x >= xThroatRight - 0.5) {
          return CadPoint2D(pt.x + delta, pt.y + delta);
        }
        return CadPoint2D(pt.x, pt.y + delta);
      }
    }

    final newContour = baseline.outerContour.map(transformPt).toList();

    final newBends = baseline.bends.map((b) {
      if (b.role == BendLineRole.flange || b.id.toUpperCase().startsWith('FL')) {
        final isBottom = (b.p1.y + b.p2.y) / 2.0 < yMid;
        final dY = isBottom ? -delta : delta;
        final p1 = CadPoint2D(b.p1.x + (b.p1.x < xMid ? -delta : delta), b.p1.y + dY);
        final p2 = CadPoint2D(b.p2.x + (b.p2.x < xMid ? -delta : delta), b.p2.y + dY);
        return b.copyWith(p1: p1, p2: p2);
      }
      return b;
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    final baseH = baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0;
    final targetH = baseH + delta;

    final newPunches = <CncPunchPrimitive>[];
    for (final p in baseline.punches) {
      if (!p.isCoupler) {
        newPunches.add(p.copyWith(center: transformPt(p.center)));
      }
    }

    final punchMap = {for (final p in baseline.punches) p.id: p};

    for (final flap in _outsideRiser90FlapConfigs) {
      final pInner = punchMap[flap.innerId];
      final pOuter = punchMap[flap.outerId];
      if (pInner == null && pOuter == null) continue;

      final CadPoint2D mBase;
      if (pInner != null && pOuter != null) {
        mBase = CadPoint2D((pInner.center.x + pOuter.center.x) / 2.0, (pInner.center.y + pOuter.center.y) / 2.0);
      } else {
        mBase = (pInner ?? pOuter)!.center;
      }

      // Scaled flap center
      final mTarget = CadPoint2D(mBase.x + flap.wxSign * (delta / 2.0), mBase.y + flap.wySign * (delta / 2.0));

      final repPunch = pInner ?? pOuter!;

      if (targetH < 95.0) {
        // Single slot centered on flap with respect to height
        newPunches.add(repPunch.copyWith(id: flap.innerId, center: mTarget, rotationDeg: flap.rotDeg));
      } else {
        // Two slots at 50mm pitch, centered on flap with respect to height
        final innerCenter = CadPoint2D(mTarget.x - 25.0 * flap.vx, mTarget.y - 25.0 * flap.vy);
        final outerCenter = CadPoint2D(mTarget.x + 25.0 * flap.vx, mTarget.y + 25.0 * flap.vy);

        newPunches.add(repPunch.copyWith(id: flap.innerId, center: innerCenter, rotationDeg: flap.rotDeg));

        final outerPunch =
            pOuter?.copyWith(id: flap.outerId, center: outerCenter, rotationDeg: flap.rotDeg) ??
            CncPunchPrimitive(
              id: flap.outerId,
              type: PunchType.obroundSlot,
              center: outerCenter,
              widthMm: repPunch.widthMm,
              lengthMm: repPunch.lengthMm,
              diameterMm: repPunch.diameterMm,
              rotationDeg: flap.rotDeg,
              role: CncPunchRole.coupler,
              parentFaceId: repPunch.parentFaceId,
              associatedPortId: flap.portId,
              layer: repPunch.layer,
              showLabel: true,
              isVisible: true,
            );
        newPunches.add(outerPunch);
      }
    }

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(p1: transformPt(cl.p1), p2: transformPt(cl.p2));
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final dx = newCenter.x - a.center.x;
      final dy = newCenter.y - a.center.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(outerContour: newContour, bends: newBends, cutLines: newCutLines);

    final hasCompleteTopology = baseline.faces.isNotEmpty && baseline.bends.isNotEmpty && baseline.bends.every((b) => b.parentFaceId.isNotEmpty);

    return baseline.copyWith(
      outerContour: newContour,
      bends: hasCompleteTopology ? newBends : (decomp.connectedBends.isNotEmpty ? decomp.connectedBends : newBends),
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

    final bends45List = baseline.bends.where((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0).toList();
    if (bends45List.length >= 2 || contract.variationName == '90_deg_inside_riser') {
      return _scaleInsideRiser90Height2D(baseline, delta);
    }

    final b45 = baseline.bends.firstWhere((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0, orElse: () => baseline.bends.first);
    final has45 = (b45.targetAngleDeg.abs() - 45.0).abs() < 15.0;

    double x1;
    double x2;
    if (has45 && (b45.p2.x - b45.p1.x).abs() > 20.0) {
      x1 = math.min(b45.p1.x, b45.p2.x);
      x2 = math.max(b45.p1.x, b45.p2.x);
    } else {
      final vertBends = baseline.bends.where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0).toList()
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
    final b3 = baseline.bends.firstWhere((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0, orElse: () => baseline.bends.first);
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
      return b.copyWith(p1: transformPt(b.p1), p2: transformPt(b.p2));
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    final newPunches = baseline.punches.map((p) {
      return p.copyWith(center: transformPunchCenter(p.center));
    }).toList();

    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(p1: transformPt(cl.p1), p2: transformPt(cl.p2));
    }).toList();

    final newArcs = baseline.arcs.map((a) {
      final newStart = transformPt(a.startPoint);
      final dx = newStart.x - a.startPoint.x;
      final dy = newStart.y - a.startPoint.y;
      return a.translate(dx, dy);
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(outerContour: newContour, bends: newBends, cutLines: newCutLines);

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
    final hasCompleteTopology = baseline.faces.isNotEmpty && baseline.bends.isNotEmpty && baseline.bends.every((b) => b.parentFaceId.isNotEmpty);

    if (hasCompleteTopology) {
      return doc;
    }

    return _normalizeRiserTopology(doc, x1, x2, yB3);
  }

  /// Dedicated 2D 90° Inside Riser Height Scaling:
  /// - Base floor web and floor flaps (between x1 and x2) remain fixed.
  /// - Sidewall cheeks expand outward along X by delta (-delta on left, +delta on right).
  /// - Return flanges FL1 and FL2 remain strictly vertical, translating rigidly in X.
  /// - All 4 cheek ears expand symmetrically along their respective 45° miter axes:
  ///   * Top-Left ear: (-delta, +delta)
  ///   * Top-Right ear: (+delta, +delta)
  ///   * Bottom-Left ear: (-delta, -delta)
  ///   * Bottom-Right ear: (+delta, -delta)
  /// - All 8 corner arcs translate rigidly with their respective ear tips, preserving radius and angles.
  /// - Coupler holes are centered on each ear with the universal 95mm rule:
  ///   * Height < 95mm: 1 slot centered on each ear (4 slots total).
  ///   * Height >= 95mm: 2 slots per ear with 50mm pitch (8 slots total).
  DsfDocument _scaleInsideRiser90Height2D(DsfDocument baseline, double delta) {
    if (baseline.bends.isEmpty) return baseline;

    final bends90 = baseline.bends.where((b) {
      final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
      return is90 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL');
    }).toList()
      ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));

    final double x1 = bends90.isNotEmpty ? (bends90.first.p1.x + bends90.first.p2.x) / 2.0 : 109.8925;
    final double x2 = bends90.isNotEmpty ? (bends90.last.p1.x + bends90.last.p2.x) / 2.0 : 207.8925;

    final returnFlanges = baseline.bends.where((b) =>
      b.role == BendLineRole.flange || b.layer == 'FLANGE' || b.id.toUpperCase().startsWith('FL')
    ).toList();
    double yFlangeMin = 87.0244;
    double yFlangeMax = 140.6640;
    if (returnFlanges.isNotEmpty) {
      yFlangeMin = returnFlanges.map((b) => math.min(b.p1.y, b.p2.y)).reduce(math.min);
      yFlangeMax = returnFlanges.map((b) => math.max(b.p1.y, b.p2.y)).reduce(math.max);
    }

    final double baseHeight = (baseline.parameters['height'] as num?)?.toDouble() ?? 100.0;
    final double newHeight = baseHeight + delta;

    CadPoint2D transformPt(CadPoint2D pt) {
      // 1. Base floor web and floor flaps (between x1 and x2)
      if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5) {
        return pt;
      }

      // 2. Left Cheek (x < x1)
      if (pt.x < x1 - 0.5) {
        if (pt.y > yFlangeMax + 0.5) {
          // Top-Left Ear: extends (-delta, +delta)
          return CadPoint2D(pt.x - delta, pt.y + delta);
        } else if (pt.y < yFlangeMin - 0.5) {
          // Bottom-Left Ear: extends (-delta, -delta)
          return CadPoint2D(pt.x - delta, pt.y - delta);
        } else {
          // Flange FL2 and middle wall section: translates strictly in -X
          return CadPoint2D(pt.x - delta, pt.y);
        }
      }

      // 3. Right Cheek (x > x2)
      if (pt.x > x2 + 0.5) {
        if (pt.y > yFlangeMax + 0.5) {
          // Top-Right Ear: extends (+delta, +delta)
          return CadPoint2D(pt.x + delta, pt.y + delta);
        } else if (pt.y < yFlangeMin - 0.5) {
          // Bottom-Right Ear: extends (+delta, -delta)
          return CadPoint2D(pt.x + delta, pt.y - delta);
        } else {
          // Flange FL1 and middle wall section: translates strictly in +X
          return CadPoint2D(pt.x + delta, pt.y);
        }
      }

      return pt;
    }

    final newContour = baseline.outerContour.map(transformPt).toList();

    final newBends = baseline.bends.map((b) {
      return b.copyWith(p1: transformPt(b.p1), p2: transformPt(b.p2));
    }).toList();

    final newFaces = baseline.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    // Symmetrical translation of the 8 corner arcs
    final newArcs = baseline.arcs.map((a) {
      CadPoint2D newCenter;
      if (a.center.x > x2) {
        if (a.center.y > 100.0) {
          // Top-Right: ARC_BND_1 and ARC_BND_2
          newCenter = CadPoint2D(a.center.x + delta, a.center.y + delta);
        } else {
          // Bottom-Right: ARC_BND_5 and ARC_BND_6
          newCenter = CadPoint2D(a.center.x + delta, a.center.y - delta);
        }
      } else {
        if (a.center.y > 100.0) {
          // Top-Left: ARC_BND_3 and ARC_BND_4
          newCenter = CadPoint2D(a.center.x - delta, a.center.y + delta);
        } else {
          // Bottom-Left: ARC_BND_7 and ARC_BND_8
          newCenter = CadPoint2D(a.center.x - delta, a.center.y - delta);
        }
      }
      return a.copyWith(center: newCenter);
    }).toList();

    // Universal 95mm rule for coupler slots:
    // Base centers: TR=(283.1368, 193.0402), TL=(34.6482, 193.0402), BR=(283.1368, 34.6482), BL=(34.6482, 34.6482)
    final mTR = CadPoint2D(283.1368 + delta / 2.0, 193.0402 + delta / 2.0);
    final mTL = CadPoint2D(34.6482 - delta / 2.0, 193.0402 + delta / 2.0);
    final mBR = CadPoint2D(283.1368 + delta / 2.0, 34.6482 - delta / 2.0);
    final mBL = CadPoint2D(34.6482 - delta / 2.0, 34.6482 - delta / 2.0);

    final newPunches = <CncPunchPrimitive>[];
    const dPitch = 25.0 / 1.4142135623730951; // ~17.6777 mm

    if (newHeight < 95.0) {
      // 1 slot per ear (4 slots total) centered precisely on each ear flap
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_1',
        type: PunchType.obroundSlot,
        center: mTR,
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 135.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_3',
        showLabel: true,
        isVisible: true,
      ));
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_3',
        type: PunchType.obroundSlot,
        center: mTL,
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 45.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_1',
        showLabel: true,
        isVisible: true,
      ));
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_5',
        type: PunchType.obroundSlot,
        center: mBR,
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 45.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_3',
        showLabel: true,
        isVisible: true,
      ));
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_7',
        type: PunchType.obroundSlot,
        center: mBL,
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 135.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_1',
        showLabel: true,
        isVisible: true,
      ));
    } else {
      // 2 slots per ear (8 slots total) at standard 50mm pitch
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_1',
        type: PunchType.obroundSlot,
        center: CadPoint2D(mTR.x - dPitch, mTR.y + dPitch),
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 135.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_3',
        showLabel: true,
        isVisible: true,
      ));
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_2',
        type: PunchType.obroundSlot,
        center: CadPoint2D(mTR.x + dPitch, mTR.y - dPitch),
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 135.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_3',
        showLabel: true,
        isVisible: true,
      ));

      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_3',
        type: PunchType.obroundSlot,
        center: CadPoint2D(mTL.x + dPitch, mTL.y + dPitch),
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 45.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_1',
        showLabel: true,
        isVisible: true,
      ));
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_4',
        type: PunchType.obroundSlot,
        center: CadPoint2D(mTL.x - dPitch, mTL.y - dPitch),
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 45.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_1',
        showLabel: true,
        isVisible: true,
      ));

      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_5',
        type: PunchType.obroundSlot,
        center: CadPoint2D(mBR.x - dPitch, mBR.y - dPitch),
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        role: CncPunchRole.coupler,
        rotationDeg: 45.0,
        layer: 'HOLES',
        parentFaceId: 'F_3',
        showLabel: true,
        isVisible: true,
      ));
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_6',
        type: PunchType.obroundSlot,
        center: CadPoint2D(mBR.x + dPitch, mBR.y + dPitch),
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        role: CncPunchRole.coupler,
        rotationDeg: 45.0,
        layer: 'HOLES',
        parentFaceId: 'F_3',
        showLabel: true,
        isVisible: true,
      ));

      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_7',
        type: PunchType.obroundSlot,
        center: CadPoint2D(mBL.x + dPitch, mBL.y - dPitch),
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 135.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_1',
        showLabel: true,
        isVisible: true,
      ));
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_8',
        type: PunchType.obroundSlot,
        center: CadPoint2D(mBL.x - dPitch, mBL.y + dPitch),
        widthMm: 8.0,
        lengthMm: 20.0,
        diameterMm: 8.0,
        rotationDeg: 135.0,
        role: CncPunchRole.coupler,
        layer: 'HOLES',
        parentFaceId: 'F_1',
        showLabel: true,
        isVisible: true,
      ));
    }

    return baseline.copyWith(
      outerContour: newContour,
      bends: newBends,
      faces: newFaces,
      arcs: newArcs,
      punches: newPunches,
      parameters: {...baseline.parameters, 'height': newHeight},
    );
  }

  /// Normalizes kinematic DAG topology for 45° Inside Riser fittings:
  /// - Central Floor Web (between x1 and x2, y < yB3) is the base anchor (Root of DAG, FaceRole.baseFloor).
  /// - Bottom Flap is child of Floor Web via B3 (45° bend UP).
  /// - Left Cheek is child of Floor Web via inner 90° bend UP.
  /// - Right Cheek is child of Floor Web via inner 90° bend UP.
  /// - Left/Right Flanges (if present) are children of Left/Right Cheeks via outer 90° bends UP.
  /// - Ensures exact 3D touching along the 45° miter line with zero separation.
  DsfDocument _normalizeRiserTopology(DsfDocument doc, double x1, double x2, double yB3) {
    final floorFace = doc.faces.firstWhere((f) {
      final cx = f.centroid.x;
      return cx >= x1 - 5.0 && cx <= x2 + 5.0 && f.centroid.y < yB3;
    }, orElse: () => doc.faces.firstWhere((f) => f.id == 'F_4' || f.id == 'F_2', orElse: () => doc.faces.first));

    final flapFace = doc.faces.firstWhere(
      (f) => f.id != floorFace.id && f.centroid.x >= x1 - 5.0 && f.centroid.x <= x2 + 5.0,
      orElse: () => doc.faces.firstWhere((f) => f.id == 'F_3' || f.id == 'F_1', orElse: () => doc.faces.first),
    );

    // Left faces: x < x1 - 5.0, sorted descending by centroid.x (cheek is closest to x1, flange is outer)
    final leftFaces = doc.faces.where((f) => f.centroid.x < x1 - 5.0).toList()..sort((a, b) => b.centroid.x.compareTo(a.centroid.x));
    final leftCheek = leftFaces.isNotEmpty ? leftFaces.first : null;
    final leftFlange = leftFaces.length > 1 ? leftFaces.last : null;

    // Right faces: x > x2 + 5.0, sorted ascending by centroid.x (cheek is closest to x2, flange is outer)
    final rightFaces = doc.faces.where((f) => f.centroid.x > x2 + 5.0).toList()..sort((a, b) => a.centroid.x.compareTo(b.centroid.x));
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
    }).toList()..sort((a, b) => ((b.p1.x + b.p2.x) / 2.0).compareTo((a.p1.x + a.p2.x) / 2.0)); // Inner bend first

    final right90Bends = doc.bends.where((b) {
      final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
      final midX = (b.p1.x + b.p2.x) / 2.0;
      return is90 && midX > midWebX;
    }).toList()..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0)); // Inner bend first

    final leftInnerBendId = left90Bends.isNotEmpty ? left90Bends.first.id : null;
    final leftOuterBendId = left90Bends.length > 1 ? left90Bends.last.id : null;

    final rightInnerBendId = right90Bends.isNotEmpty ? right90Bends.first.id : null;
    final rightOuterBendId = right90Bends.length > 1 ? right90Bends.last.id : null;

    final normalizedBends = doc.bends.map((b) {
      if ((b.targetAngleDeg.abs() - 45.0).abs() < 15.0) {
        return b.copyWith(parentFaceId: floorFace.id, childFaceId: flapFace.id, direction: BendDirection.up);
      } else if (b.id == leftInnerBendId && leftCheek != null) {
        return b.copyWith(parentFaceId: floorFace.id, childFaceId: leftCheek.id, direction: BendDirection.up);
      } else if (b.id == leftOuterBendId && leftCheek != null && leftFlange != null) {
        return b.copyWith(parentFaceId: leftCheek.id, childFaceId: leftFlange.id, direction: BendDirection.up);
      } else if (b.id == rightInnerBendId && rightCheek != null) {
        return b.copyWith(parentFaceId: floorFace.id, childFaceId: rightCheek.id, direction: BendDirection.up);
      } else if (b.id == rightOuterBendId && rightCheek != null && rightFlange != null) {
        return b.copyWith(parentFaceId: rightCheek.id, childFaceId: rightFlange.id, direction: BendDirection.up);
      }
      return b;
    }).toList();

    return doc.copyWith(baseFaceId: floorFace.id, faces: normalizedFaces, bends: normalizedBends);
  }

  /// Scales the canonical 2D flat blank for Width:
  /// - Floor web expands by delta.
  /// - Sidewalls & return flanges translate outward rigidly.
  /// - Coupler slots translate with their host sidewall (preserving shape and edge distance).
  DsfDocument _scaleWidth2D(DsfDocument baseline, double delta) {
    final doc = baseline.faces.isNotEmpty
        ? baseline
        : () {
            final decomp = PlanarFaceDecomposer.decompose(outerContour: baseline.outerContour, bends: baseline.bends, cutLines: baseline.cutLines);
            return baseline.copyWith(faces: decomp.faces, baseFaceId: decomp.baseFaceId);
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
      return b.copyWith(p1: transformPt(b.p1), p2: transformPt(b.p2));
    }).toList();

    // 3. Transform faces
    final newFaces = doc.faces.map((f) {
      final newVerts = f.vertices.map(transformPt).toList();
      return f.copyWith(vertices: newVerts);
    }).toList();

    // 4. Transform punches (RIGID: maintain exact shape, shift center with host region)
    final newPunches = doc.punches.map((p) {
      return p.copyWith(center: transformPt(p.center));
    }).toList();

    // 5. Transform cut lines
    final newCutLines = doc.cutLines.map((cl) {
      return cl.copyWith(p1: transformPt(cl.p1), p2: transformPt(cl.p2));
    }).toList();

    final decomp = PlanarFaceDecomposer.decompose(outerContour: newContour, bends: newBends, cutLines: newCutLines);

    final newArcs = doc.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final newStart = transformPt(a.startPoint);
      final newEnd = transformPt(a.endPoint);
      final startAng = math.atan2(newStart.y - newCenter.y, newStart.x - newCenter.x);
      final endAng = math.atan2(newEnd.y - newCenter.y, newEnd.x - newCenter.x);
      double sweep = (endAng - startAng) % (2.0 * math.pi);
      if (a.sweepAngleRad < 0) {
        if (sweep > 0) sweep -= 2.0 * math.pi;
      } else {
        if (sweep < 0) sweep += 2.0 * math.pi;
      }
      if (sweep.abs() < 1e-4) sweep = a.sweepAngleRad;
      return a.copyWith(center: newCenter, startAngleRad: startAng, sweepAngleRad: sweep);
    }).toList();

    return doc.copyWith(
      outerContour: newContour,
      bends: newBends,
      faces: decomp.faces.isNotEmpty ? decomp.faces : newFaces,
      baseFaceId: decomp.baseFaceId,
      punches: newPunches,
      cutLines: newCutLines,
      arcs: newArcs,
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

    final newArcs = baseline.arcs.map((a) {
      final newCenter = transformPt(a.center);
      final newStart = transformPt(a.startPoint);
      final newEnd = transformPt(a.endPoint);
      final startAng = math.atan2(newStart.y - newCenter.y, newStart.x - newCenter.x);
      final endAng = math.atan2(newEnd.y - newCenter.y, newEnd.x - newCenter.x);
      double sweep = (endAng - startAng) % (2.0 * math.pi);
      if (a.sweepAngleRad < 0) {
        if (sweep > 0) sweep -= 2.0 * math.pi;
      } else {
        if (sweep < 0) sweep += 2.0 * math.pi;
      }
      if (sweep.abs() < 1e-4) sweep = a.sweepAngleRad;
      return a.copyWith(center: newCenter, startAngleRad: startAng, sweepAngleRad: sweep);
    }).toList();

    return baseline.copyWith(
      outerContour: baseline.outerContour.map(transformPt).toList(),
      bends: baseline.bends.map((b) => b.copyWith(p1: transformPt(b.p1), p2: transformPt(b.p2))).toList(),
      faces: baseline.faces.map((f) => f.copyWith(vertices: f.vertices.map(transformPt).toList())).toList(),
      punches: baseline.punches.map((p) => p.copyWith(center: transformPt(p.center))).toList(),
      cutLines: baseline.cutLines.map((cl) => cl.copyWith(p1: transformPt(cl.p1), p2: transformPt(cl.p2))).toList(),
      arcs: newArcs,
    );
  }

  /// Dedicated 2D morpher for Straight Concentric Reducer.
  /// Slants from Port 1 (large end) to Port 2 (small end) like a bell mouth,
  /// with independent width and height scaling at both ends.
  /// Universal 95mm rule:
  /// - Height >= 95mm: 2 coupler slots at 50mm pitch.
  /// - Height < 95mm: 1 coupler slot centered.
  DsfDocument _scaleReducer2D(
    DsfDocument baseline, {
    required Map<String, CmsScalingParameter> parameters,
  }) {
    final scaleParams = ReducerScaleParameters.fromCmsParameters(
      parameters,
      baselineDoc: baseline,
    );
    final res = ReducerScaler.scale(baseline: baseline, parameters: scaleParams);
    return res.isValid ? res.document : baseline;
  }

  // ---------------------------------------------------------------------------
  // Setup from Phase 1 Verified Template
  // ---------------------------------------------------------------------------

  void _initModelFromPhase1({Map<String, double>? currentParameterValues}) {
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
        description: 'Derived 3D opening mouth for ${toNominalSize(p.width).toStringAsFixed(0)} × ${toNominalSize(p.height).toStringAsFixed(0)} mm channel.',
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
    if (contract == CmsProductContract.unequalTee || contract == CmsProductContract.unequalCross) {
      initialLinked = false;
    } else if (contract.scalingProfile == CmsScalingProfile.reducer || isReducerGeometry(baselineDocument)) {
      initialLinked = false;
    } else if (contract == CmsProductContract.equalTee || contract == CmsProductContract.equalCross) {
      initialLinked = true;
    } else if (baselinePorts.length >= 3) {
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
    if (initialLinked || (baselinePorts.length < 3 && contract.scalingProfile != CmsScalingProfile.reducer && !isReducerGeometry(baselineDocument))) {
      final curW = currentParameterValues?['width'] ?? (baselineDocument.parameters['width'] as num?)?.toDouble() ?? baselineWidth;
      final curH = currentParameterValues?['height'] ?? (baselineDocument.parameters['height'] as num?)?.toDouble() ?? baselineHeight;
      params['width'] = CmsScalingParameter(
        id: 'width',
        displayName: 'Width (W)',
        currentValue: curW,
        baselineValue: baselineWidth,
        minValidMm: minW,
        maxValidMm: maxW,
        unit: 'mm',
        teachingState: (curW - baselineWidth).abs() > 0.01 ? CmsParameterTeachingState.learned : CmsParameterTeachingState.untaught,
        stretchZoneIds: ['ZONE_FLOOR_WEB'],
        translationZoneIds: ['ZONE_SIDEWALLS_AND_FLANGES'],
        rigidGroupIds: rigidGroups.map((g) => g.id).toList(),
        derivedPortIds: derivedPorts.map((p) => p.portId).toList(),
      );
      params['height'] = CmsScalingParameter(
        id: 'height',
        displayName: 'Height (H)',
        currentValue: curH,
        baselineValue: baselineHeight,
        minValidMm: minH,
        maxValidMm: maxH,
        unit: 'mm',
        teachingState: (curH - baselineHeight).abs() > 0.01 ? CmsParameterTeachingState.learned : CmsParameterTeachingState.untaught,
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
        final double baseWidth;
        if (contract == CmsProductContract.unequalCross) {
          baseWidth = (i == 0 || i == 2) ? 50.0 : 100.0;
        } else if (contract.scalingProfile == CmsScalingProfile.reducer || isReducerGeometry(baselineDocument)) {
          baseWidth = i == 0 ? 100.0 : 50.0;
        } else {
          baseWidth = p.width;
        }
        final curW = currentParameterValues?[wId] ?? (baselineDocument.parameters[wId] as num?)?.toDouble() ?? baseWidth;
        params[wId] = CmsScalingParameter(
          id: wId,
          displayName: 'Port ${i + 1} Width',
          currentValue: curW,
          baselineValue: baseWidth,
          minValidMm: math.min(50.0, baseWidth - 50.0),
          maxValidMm: math.max(750.0, baseWidth + 200.0),
          unit: 'mm',
          teachingState: (curW - baseWidth).abs() > 0.01 ? CmsParameterTeachingState.learned : CmsParameterTeachingState.untaught,
        );
        final double baseHeight;
        if (contract.scalingProfile == CmsScalingProfile.reducer || isReducerGeometry(baselineDocument)) {
          baseHeight = i == 0 ? 100.0 : 50.0;
        } else if (contract == CmsProductContract.unequalTee && i == 1) {
          // Port 2 coupler on Unequal Tee has a 50mm baseline coupler height
          baseHeight = 50.0;
        } else if (contract == CmsProductContract.unequalTee) {
          baseHeight = 100.0;
        } else if (contract == CmsProductContract.unequalCross && (i == 0 || i == 2)) {
          // Port 1 and Port 3 couplers on Unequal Cross have a 50mm baseline coupler height
          baseHeight = 50.0;
        } else if (contract == CmsProductContract.unequalCross) {
          // Port 2 and Port 4 couplers have 100mm baseline coupler height
          baseHeight = 100.0;
        } else {
          baseHeight = p.height;
        }
        final curH = currentParameterValues?[hId] ?? (baselineDocument.parameters[hId] as num?)?.toDouble() ?? baseHeight;
        params[hId] = CmsScalingParameter(
          id: hId,
          displayName: 'Port ${i + 1} Height',
          currentValue: curH,
          baselineValue: baseHeight,
          minValidMm: math.min(50.0, baseHeight - 50.0),
          maxValidMm: math.max(300.0, baseHeight + 150.0),
          unit: 'mm',
          teachingState: (curH - baseHeight).abs() > 0.01 ? CmsParameterTeachingState.learned : CmsParameterTeachingState.untaught,
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

class _EqualCrossFlapConfig {
  final String innerId;
  final String outerId;
  final int wxSign;
  final int wySign;
  final double vx;
  final double vy;
  final double rotDeg;
  final String portId;

  const _EqualCrossFlapConfig({
    required this.innerId,
    required this.outerId,
    required this.wxSign,
    required this.wySign,
    required this.vx,
    required this.vy,
    required this.rotDeg,
    required this.portId,
  });
}

class _EqualTeeFlapConfig {
  final String innerId;
  final String outerId;
  final int wxSign;
  final bool hasWyShift;
  final double vx;
  final double vy;
  final double rotDeg;
  final String portId;

  const _EqualTeeFlapConfig({
    required this.innerId,
    required this.outerId,
    required this.wxSign,
    required this.hasWyShift,
    required this.vx,
    required this.vy,
    required this.rotDeg,
    required this.portId,
  });
}

class _OutsideRiser90FlapConfig {
  final String innerId;
  final String outerId;
  final double wxSign;
  final double wySign;
  final double vx;
  final double vy;
  final double rotDeg;
  final String portId;

  const _OutsideRiser90FlapConfig({
    required this.innerId,
    required this.outerId,
    required this.wxSign,
    required this.wySign,
    required this.vx,
    required this.vy,
    required this.rotDeg,
    required this.portId,
  });
}
