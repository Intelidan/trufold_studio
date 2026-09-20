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
    var scaledDoc = _generateScaled2DDocument(
      baseline: baselineDocument,
      paramId: _activeParameterId,
      delta: delta,
    );
    final targetW = _activeParameterId == 'width' ? targetValue : (baselinePorts.isNotEmpty ? baselinePorts.first.width : 100.0);
    final targetH = _activeParameterId == 'height' ? targetValue : (baselinePorts.isNotEmpty ? baselinePorts.first.height : 100.0);
    scaledDoc = scaledDoc.copyWith(
      parameters: {
        ...scaledDoc.parameters,
        'width': targetW,
        'height': targetH,
        _activeParameterId: targetValue,
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

    // Reconcile channel height across ports (ports of the same fitting share channel cross-section)
    double? detectedChannelHeight;
    for (final m in initialMeasured) {
      if (m.height > 15.0) {
        if (detectedChannelHeight == null || m.height > detectedChannelHeight) {
          detectedChannelHeight = m.height;
        }
      }
    }

    final measured = initialMeasured.map((m) {
      if (detectedChannelHeight != null && (m.height - detectedChannelHeight).abs() > 3.0) {
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
    if (isInsideRiserGeometry(baselineDocument)) {
      return CmsScalingProfile.insideRiser;
    }

    return contract.scalingProfile;
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

    // 1. Dedicated Riser Scaling Profile (Section 2, 3, 4)
    if (profile == CmsScalingProfile.insideRiser ||
        profile == CmsScalingProfile.outsideRiser ||
        isInsideRiserGeometry(baseline)) {
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

    final longBends = baseline.bends.where((b) {
      final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
      final isStructural = b.role != BendLineRole.flange;
      return is90 && isStructural;
    }).toList();

    if (longBends.length < 2) return _scaleWidth2D(baseline, delta);

    final x1 = math.min(longBends[0].p1.x, longBends[1].p1.x);
    final x2 = math.max(longBends[0].p1.x, longBends[1].p1.x);
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
      baseFaceId: baseline.baseFaceId,
      punches: newPunches,
      cutLines: newCutLines,
      arcs: newArcs,
    );

    final b3 = baseline.bends.firstWhere(
      (b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0,
      orElse: () => baseline.bends.first,
    );
    final yB3 = b3.p1.y;

    return _normalizeRiserTopology(doc, x1 - halfDelta, x2 + halfDelta, yB3);
  }

  /// Dedicated 2D Riser Height Scaling:
  /// Dedicated 2D Riser Height Scaling:
  /// - Sidewall cheeks expand outward along X by delta.
  /// - 45° riser prongs shift outward along both X and Y (±delta, +delta), preserving
  ///   the exact 45° miter angle (dy / dx = 1.0) so they touch the 45° bottom flap bend F_1 in 3D.
  /// - Coupler slots translate rigidly on both the 45° prongs and straight sidewalls,
  ///   preserving their exact shape, pitch spacing, and rotation with zero distortion.
  /// - Floor web and bends B1, B2, B3 remain fixed.
  /// - Floor length along Y is never lengthened.
  DsfDocument _scaleRiserHeight2D(DsfDocument baseline, double delta) {
    if (baseline.bends.isEmpty) return baseline;

    final longBends = baseline.bends.where((b) {
      final is90 = (b.targetAngleDeg.abs() - 90.0).abs() < 15.0;
      final isStructural = b.role != BendLineRole.flange;
      return is90 && isStructural;
    }).toList();

    if (longBends.length < 2) return _scaleHeight2D(baseline, delta);

    final x1 = math.min(longBends[0].p1.x, longBends[1].p1.x);
    final x2 = math.max(longBends[0].p1.x, longBends[1].p1.x);

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

    // Threshold Y separating the straight run from the 45° riser prong (notch at y ≈ 85.6 - 88.6)
    final yProngThreshold = yB3 - (yB3 - 30.0) * 0.45; // ≈ 86.0 mm

    // Determine the stretch threshold X for left and right cheek:
    // Left cheek: inner corner arc ARC_BND_3 is near B1 (x1). The stretch zone is between ARC_BND_3 and ARC_BND_4.
    // Right cheek: inner corner arc ARC_BND_2 is near B2 (x2). The stretch zone is between ARC_BND_2 and ARC_BND_1.
    double xLeftStretch = x1 - 10.0;
    double xRightStretch = x2 + 10.0;

    for (final a in baseline.arcs) {
      if (a.center.y < yProngThreshold) {
        if ((a.center.x - x1).abs() <= 20.0) {
          xLeftStretch = math.min(xLeftStretch, a.center.x);
        }
        if ((a.center.x - x2).abs() <= 20.0) {
          xRightStretch = math.max(xRightStretch, a.center.x);
        }
      }
    }

    CadPoint2D transformPt(CadPoint2D pt) {
      // 1. Floor web and bottom floor (between x1 and x2)
      if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5) {
        if (pt.y <= yB3 + 0.5) {
          // Central floor web remains fixed
          return pt;
        } else {
          // Bottom 45° flap (F_1) grows along Y by delta * sqrt(2) so that its
          // 3D displacement (dy = delta, dz = delta) exactly matches the 3D displacement
          // of the 45° riser sidewall prongs, keeping the 3D distance between the flap's open
          // edge and the prongs' tip edge strictly constant with zero drift.
          final flapGrowth = delta * math.sqrt(2);
          return CadPoint2D(pt.x, pt.y + flapGrowth);
        }
      }

      // 2. Left Cheek (x < x1)
      if (pt.x < x1 - 0.5) {
        if (pt.y > yProngThreshold) {
          // 45° Riser Prong:
          // Shifts outward along X by -delta and upward along Y by +delta.
          // This ensures the 45° miter line (from (x1, yB3) to outer end) has slope
          // dy / (-dx) = (42.01 + delta) / (42.01 + delta) = 1.0 (EXACTLY 45°).
          // In 3D, dz / dy = 1.0, touching the 45° flap bend F_1 perfectly with zero gap.
          return CadPoint2D(pt.x - delta, pt.y + delta);
        } else {
          // Straight sidewall section:
          // Inner corner (x >= xLeftStretch - 0.5) remains fixed with B1 and PORT_1.
          // Outer sidewall (x < xLeftStretch - 0.5) translates rigidly outward by -delta.
          // The horizontal edge between them expands by delta, keeping all corner arcs and chamfers 100% invariant.
          if (pt.x >= xLeftStretch - 0.5) {
            return pt;
          } else {
            return CadPoint2D(pt.x - delta, pt.y);
          }
        }
      }

      // 3. Right Cheek (x > x2)
      if (pt.x > x2 + 0.5) {
        if (pt.y > yProngThreshold) {
          // 45° Riser Prong:
          // Shifts outward along X by +delta and upward along Y by +delta.
          // Preserves the 45° miter line (dy / dx = 1.0) so it touches F_1 in 3D.
          return CadPoint2D(pt.x + delta, pt.y + delta);
        } else {
          // Straight sidewall section:
          // Inner corner (x <= xRightStretch + 0.5) remains fixed with B2 and PORT_1.
          // Outer sidewall (x > xRightStretch + 0.5) translates rigidly outward by +delta.
          // The horizontal edge between them expands by delta, keeping all corner arcs and chamfers 100% invariant.
          if (pt.x <= xRightStretch + 0.5) {
            return pt;
          } else {
            return CadPoint2D(pt.x + delta, pt.y);
          }
        }
      }

      return pt;
    }

    CadPoint2D transformPunchCenter(CadPoint2D pt) {
      // 1. Floor punches: fixed (or bottom flap if y > yB3)
      if (pt.x >= x1 - 0.5 && pt.x <= x2 + 0.5) {
        if (pt.y > yB3 + 0.5) {
          final flapGrowth = delta * math.sqrt(2);
          return CadPoint2D(pt.x, pt.y + flapGrowth);
        }
        return pt;
      }

      // 2. Left Cheek punches
      if (pt.x < x1 - 0.5) {
        if (pt.y > yProngThreshold) {
          // Coupler slots on 45° prong (SLOT_3, SLOT_4):
          // Translate rigidly with the prong by (-delta, +delta).
          // Pitch spacing, angle relative to edge, and orientation are 100% preserved.
          return CadPoint2D(pt.x - delta, pt.y + delta);
        } else {
          // Coupler slots on straight sidewall (SLOT_7, SLOT_8):
          // Inner slot (SLOT_7) is anchored to inner edge near B1 (fixed dx = 0).
          // Outer slot (SLOT_8) is anchored to outer edge (translates dx = -delta).
          // Both maintain their exact 23.0 mm mounting edge setback.
          final xLeftMid = (minX + x1) / 2.0;
          if (pt.x > xLeftMid) {
            return pt;
          } else {
            return CadPoint2D(pt.x - delta, pt.y);
          }
        }
      }

      // 3. Right Cheek punches
      if (pt.x > x2 + 0.5) {
        if (pt.y > yProngThreshold) {
          // Coupler slots on 45° prong (SLOT_1, SLOT_2):
          // Translate rigidly with the prong by (+delta, +delta).
          return CadPoint2D(pt.x + delta, pt.y + delta);
        } else {
          // Coupler slots on straight sidewall (SLOT_5, SLOT_6):
          // Inner slot (SLOT_5) is anchored to inner edge near B2 (fixed dx = 0).
          // Outer slot (SLOT_6) is anchored to outer edge (translates dx = +delta).
          // Both maintain their exact 23.0 mm mounting edge setback.
          final xRightMid = (x2 + maxX) / 2.0;
          if (pt.x < xRightMid) {
            return pt;
          } else {
            return CadPoint2D(pt.x + delta, pt.y);
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

    return _normalizeRiserTopology(doc, x1, x2, yB3);
  }

  /// Normalizes kinematic DAG topology for 45° Inside Riser fittings:
  /// - Central Floor Web (between B1 and B2, y < yB3) is the base anchor (Root of DAG, FaceRole.baseFloor).
  /// - Bottom Flap is child of Floor Web via B3 (45° bend UP).
  /// - Left Cheek is child of Floor Web via B1 (90° bend UP).
  /// - Right Cheek is child of Floor Web via B2 (90° bend UP).
  /// - Ensures exact 3D touching along the 45° miter line with zero separation.
  DsfDocument _normalizeRiserTopology(DsfDocument doc, double x1, double x2, double yB3) {
    final floorFace = doc.faces.firstWhere(
      (f) {
        final cx = f.centroid.x;
        return cx >= x1 - 5.0 && cx <= x2 + 5.0 && f.centroid.y < yB3;
      },
      orElse: () => doc.faces.firstWhere((f) => f.id == 'F_2', orElse: () => doc.faces.first),
    );

    final flapFace = doc.faces.firstWhere(
      (f) => f.id != floorFace.id && f.centroid.x >= x1 - 5.0 && f.centroid.x <= x2 + 5.0,
      orElse: () => doc.faces.firstWhere((f) => f.id == 'F_1', orElse: () => doc.faces.first),
    );

    final leftCheek = doc.faces.firstWhere(
      (f) => f.centroid.x < x1 - 5.0,
      orElse: () => doc.faces.firstWhere((f) => f.id == 'F_0', orElse: () => doc.faces.first),
    );

    final rightCheek = doc.faces.firstWhere(
      (f) => f.centroid.x > x2 + 5.0,
      orElse: () => doc.faces.firstWhere((f) => f.id == 'F_3', orElse: () => doc.faces.first),
    );

    final normalizedFaces = doc.faces.map((f) {
      if (f.id == floorFace.id) {
        return f.copyWith(isBaseAnchor: true, role: FaceRole.baseFloor, label: 'Floor Web');
      } else if (f.id == flapFace.id) {
        return f.copyWith(isBaseAnchor: false, role: FaceRole.sideWall, label: 'Bottom Flap');
      } else if (f.id == leftCheek.id) {
        return f.copyWith(isBaseAnchor: false, role: FaceRole.sideWall, label: 'Left Sidewall Cheek');
      } else if (f.id == rightCheek.id) {
        return f.copyWith(isBaseAnchor: false, role: FaceRole.sideWall, label: 'Right Sidewall Cheek');
      }
      return f.copyWith(isBaseAnchor: false);
    }).toList();

    final normalizedBends = doc.bends.map((b) {
      if ((b.targetAngleDeg.abs() - 45.0).abs() < 15.0) {
        return b.copyWith(
          parentFaceId: floorFace.id,
          childFaceId: flapFace.id,
          direction: BendDirection.up,
        );
      } else if ((b.targetAngleDeg.abs() - 90.0).abs() < 15.0) {
        final midX = (b.p1.x + b.p2.x) / 2.0;
        if (midX <= (x1 + x2) / 2.0) {
          return b.copyWith(
            parentFaceId: floorFace.id,
            childFaceId: leftCheek.id,
            direction: BendDirection.up,
          );
        } else {
          return b.copyWith(
            parentFaceId: floorFace.id,
            childFaceId: rightCheek.id,
            direction: BendDirection.up,
          );
        }
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
