// =============================================================================
// dds_instance_evaluator.dart
//
// Technical Data Sheet (TDS) Instance Evaluator Engine.
// Takes a DdsProductInstance and baseline DsfDocument and deterministically:
// 1. Scales base geometry using the analytical CMS scaling engine.
// 2. Synthesizes the live parametric cover via TrunkingCoverGenerator.
// 3. Folds both base and cover into 3D using KinematicFoldEngine.
// 4. Calculates physical material takeoff (blank surface area and net mass).
// 5. Preserves 100% template isolation (baseline template is never mutated).
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/cad_primitives.dart';
import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/cms/cms_product_contract.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../models/dds/dds_product_instance.dart';
import '../../models/trunking_cover_data.dart';
import '../cms/cms_3d_opening_detector.dart';
import '../cms/cms_opening_plane_analyzer.dart';
import '../cms/cms_port_matcher.dart';
import '../cms/cms_scaling_controller.dart';
import '../ladder/ladder_assembly_generator.dart';
import '../../models/ladder/ladder_assembly_models.dart';
import '../../models/ladder/ladder_assembly_parameters.dart';
import '../covers/trunking_cover_generator.dart';
import '../kinematic_fold_engine.dart';

/// The evaluated 2D documents, 3D meshes, and physical takeoff for a DDS instance.
class EvaluatedDdsInstance {
  final DdsProductInstance instance;
  final DsfDocument scaledBaseDocument;
  final TrunkingCoverData? coverData;
  final FoldedMeshResult baseMesh3D;
  final FoldedMeshResult? coverMesh3D;
  final FoldedMeshResult combinedMesh3D;
  final DdsCalculatedTakeoff calculatedTakeoff;
  final List<CmsPhysicalPort> scaledPorts;

  const EvaluatedDdsInstance({
    required this.instance,
    required this.scaledBaseDocument,
    this.coverData,
    required this.baseMesh3D,
    this.coverMesh3D,
    required this.combinedMesh3D,
    required this.calculatedTakeoff,
    this.scaledPorts = const [],
  });
}

class DdsInstanceEvaluator {
  /// Standard material density in kg/m³
  static const double densityMildSteel = 7850.0;
  static const double densityStainlessSteel = 8000.0;
  static const double densityAluminum = 2700.0;

  /// Resolves the material density in kg/m³ based on material name or code.
  static double resolveDensity(String materialName) {
    final matLower = materialName.toLowerCase();
    if (matLower.contains('plastic') || matLower.contains('pvc') || matLower.contains('poly')) {
      return 1200.0;
    }
    if (matLower.contains('copper')) {
      return 8960.0;
    }
    if (matLower.contains('alum') || matLower.contains('(al)') || matLower.contains('al ') || matLower.endsWith('al') || matLower.contains('5052')) {
      return densityAluminum; // 2700.0
    }
    if (matLower.contains('stainless') || matLower.contains('304') || matLower.contains('316') || matLower.contains('ss')) {
      return densityStainlessSteel; // 8000.0
    }
    if (matLower.contains('crca')) {
      return 7870.0;
    }
    return densityMildSteel; // 7850.0 (MS, HR, GI, HDG, etc.)
  }

  /// Evaluates [instance] against [baselineDoc] producing scaled 2D & 3D models.
  static EvaluatedDdsInstance evaluate({
    required DdsProductInstance instance,
    required DsfDocument baselineDoc,
  }) {
    // 0. Dedicated Generative Pipeline for Cable Ladders
    final tId = instance.templateReference.templateId.toLowerCase();
    final pName = instance.productName.toLowerCase();
    final isLadder = tId.contains('ladder') || pName.contains('ladder');

    if (isLadder) {
      final width = (instance.instanceParameters['width'] ?? instance.instanceParameters['W'] ?? 600.0);
      final height = (instance.instanceParameters['height'] ?? instance.instanceParameters['H'] ?? 100.0);
      final length = (instance.instanceParameters['length'] ?? instance.instanceParameters['L'] ?? 3000.0);
      final thickness = (instance.instanceParameters['thickness'] ?? instance.instanceParameters['T'] ?? 2.0);
      final flangeW = (instance.instanceParameters['flangeWidth'] ?? instance.instanceParameters['flange_width'] ?? 32.0);
      final endMargin = (instance.instanceParameters['endMarginPitch'] ?? instance.instanceParameters['end_rung_offset'] ?? 75.0);
      final targetPitch = (instance.instanceParameters['rungPitch'] ?? instance.instanceParameters['rung_pitch'] ?? 250.0);

      final jointStr = instance.instanceParameters['rungJointMethod']?.toString() ??
          (instance.instanceParameters['rung_joint_method'] == 0.0 ? 'directInsideWeld' : 'passThroughOutsideWeld');
      final jointMethod = LadderRungJointMethod.fromString(jointStr);

      final pitchModeStr = instance.instanceParameters['rungPitchMode']?.toString();
      final pitchMode = RungPitchMode.fromString(pitchModeStr);

      final flangeDir = (instance.instanceParameters['flange_direction'] ?? 0.0) == 1.0
          ? LadderFlangeDirection.outside
          : LadderFlangeDirection.inside;

      final ladderParams = LadderAssemblyParameters(
        width: width,
        height: height,
        length: length,
        thickness: thickness,
        flangeWidth: flangeW,
        flangeDirection: flangeDir,
        endMarginPitch: endMargin,
        intermediateTargetPitch: targetPitch,
        pitchMode: pitchMode,
        jointMethod: jointMethod,
        outsideWeldProjection: (instance.instanceParameters['outsideWeldProjection'] ?? 3.5),
        includeCover: instance.coverConfiguration.included,
        coverHeight: instance.coverConfiguration.flangeDepthMm > 0 ? instance.coverConfiguration.flangeDepthMm : 12.0,
        includeSpliceHoles: (instance.instanceParameters['include_splice_holes'] ?? 1.0) > 0.5,
        materialName: instance.material,
      );

      final DsfLadderAssembly ladderAssembly;
      if (tId.contains('inside_riser') || pName.contains('inside riser')) {
        final angle = (instance.instanceParameters['angle'] ?? (tId.contains('45') ? 45.0 : 90.0)).toDouble();
        final radius = (instance.instanceParameters['radius'] ?? 300.0).toDouble();
        ladderAssembly = LadderAssemblyGenerator.generateRiser(
          angleDeg: angle,
          radiusMm: radius,
          isInsideRiser: true,
          params: ladderParams,
        );
      } else if (tId.contains('outside_riser') || pName.contains('outside riser')) {
        final angle = (instance.instanceParameters['angle'] ?? (tId.contains('45') ? 45.0 : 90.0)).toDouble();
        final radius = (instance.instanceParameters['radius'] ?? 300.0).toDouble();
        ladderAssembly = LadderAssemblyGenerator.generateRiser(
          angleDeg: angle,
          radiusMm: radius,
          isInsideRiser: false,
          params: ladderParams,
        );
      } else if (tId.contains('bend') || pName.contains('bend')) {
        final angle = (instance.instanceParameters['angle'] ?? (tId.contains('45') ? 45.0 : 90.0)).toDouble();
        final radius = (instance.instanceParameters['radius'] ?? 300.0).toDouble();
        ladderAssembly = LadderAssemblyGenerator.generateHorizontalBend(
          angleDeg: angle,
          radiusMm: radius,
          params: ladderParams,
        );
      } else if (tId.contains('reducer') || pName.contains('reducer')) {
        final w1 = (instance.instanceParameters['width'] ?? instance.instanceParameters['W'] ?? 600.0).toDouble();
        final w2 = (instance.instanceParameters['port2_width'] ?? instance.instanceParameters['width2'] ?? instance.instanceParameters['W2'] ?? 300.0).toDouble();
        final len = (instance.instanceParameters['length'] ?? instance.instanceParameters['L'] ?? 500.0).toDouble();
        final alignment = instance.instanceParameters['alignment']?.toString() ?? 'straight';
        ladderAssembly = LadderAssemblyGenerator.generateReducer(
          width1: w1,
          width2: w2,
          length: len,
          alignment: alignment,
          params: ladderParams,
        );
      } else if (tId == 'ladder_unequal_tee' || (tId.contains('tee') && (tId.contains('unequal') || pName.contains('unequal')))) {
        final branchW = (instance.instanceParameters['port1_width'] ?? instance.instanceParameters['branch_width'] ?? instance.instanceParameters['width3'] ?? instance.instanceParameters['W3'] ?? 300.0).toDouble();
        final mainOutW = (instance.instanceParameters['port2_width'] ?? instance.instanceParameters['main_out_width'] ?? instance.instanceParameters['run_width'] ?? instance.instanceParameters['width2'] ?? instance.instanceParameters['W2'] ?? 450.0).toDouble();
        final mainInW = (instance.instanceParameters['port3_width'] ?? instance.instanceParameters['main_in_width'] ?? instance.instanceParameters['width1'] ?? instance.instanceParameters['width'] ?? instance.instanceParameters['W'] ?? 600.0).toDouble();
        final radius = (instance.instanceParameters['radius'] ?? 300.0).toDouble();
        ladderAssembly = LadderAssemblyGenerator.generateUnequalTee(
          mainInWidth: mainInW,
          mainOutWidth: mainOutW,
          branchWidth: branchW,
          radiusMm: radius,
          params: ladderParams,
        );
      } else if (tId.contains('tee') || pName.contains('tee')) {
        final w = (instance.instanceParameters['width'] ?? instance.instanceParameters['W'] ?? 600.0).toDouble();
        final radius = (instance.instanceParameters['radius'] ?? 300.0).toDouble();
        ladderAssembly = LadderAssemblyGenerator.generateEqualTee(
          width: w,
          radiusMm: radius,
          params: ladderParams,
        );
      } else if (tId == 'ladder_unequal_cross' || (tId.contains('cross') && (tId.contains('unequal') || pName.contains('unequal')))) {
        final westW = (instance.instanceParameters['port1_width'] ?? instance.instanceParameters['west_width'] ?? instance.instanceParameters['width1'] ?? instance.instanceParameters['width'] ?? instance.instanceParameters['W'] ?? 600.0).toDouble();
        final northW = (instance.instanceParameters['port2_width'] ?? instance.instanceParameters['north_width'] ?? instance.instanceParameters['branch_width'] ?? instance.instanceParameters['width3'] ?? instance.instanceParameters['W3'] ?? 450.0).toDouble();
        final eastW = (instance.instanceParameters['port3_width'] ?? instance.instanceParameters['east_width'] ?? instance.instanceParameters['width2'] ?? instance.instanceParameters['W2'] ?? 300.0).toDouble();
        final southW = (instance.instanceParameters['port4_width'] ?? instance.instanceParameters['south_width'] ?? instance.instanceParameters['width4'] ?? instance.instanceParameters['W4'] ?? 200.0).toDouble();
        final radius = (instance.instanceParameters['radius'] ?? 300.0).toDouble();
        ladderAssembly = LadderAssemblyGenerator.generateUnequalCross(
          westWidth: westW,
          eastWidth: eastW,
          northWidth: northW,
          southWidth: southW,
          radiusMm: radius,
          params: ladderParams,
        );
      } else if (tId.contains('cross') || pName.contains('cross')) {
        final w = (instance.instanceParameters['width'] ?? instance.instanceParameters['W'] ?? 600.0).toDouble();
        final radius = (instance.instanceParameters['radius'] ?? 300.0).toDouble();
        ladderAssembly = LadderAssemblyGenerator.generateEqualCross(
          width: w,
          radiusMm: radius,
          params: ladderParams,
        );
      } else {
        ladderAssembly = LadderAssemblyGenerator.generateStraightLadder(ladderParams);
      }

      final baseMesh3D = ladderAssembly.assembledMesh3D;
      final coverMesh3D = ladderAssembly.coverMesh3D;
      final combinedMesh3D = coverMesh3D != null
          ? baseMesh3D.combineWith(coverMesh3D, preserveCenter: true)
          : baseMesh3D;

      final density = resolveDensity(instance.material);
      final weightKg = ladderAssembly.hardwareBOM.totalSteelWeightKg;
      final areaM2 = weightKg / (density * (thickness / 1000.0));

      final takeoff = DdsCalculatedTakeoff(
        blankSurfaceAreaM2: areaM2,
        estimatedNetWeightKg: weightKg,
      );

      return EvaluatedDdsInstance(
        instance: instance.copyWith(calculatedTakeoff: takeoff),
        scaledBaseDocument: baselineDoc.copyWith(
          parameters: {
            ...baselineDoc.parameters,
            ...instance.instanceParameters,
          },
          metadata: {
            ...baselineDoc.metadata,
            'ladderAssembly': ladderAssembly,
          },
        ),
        coverData: null,
        baseMesh3D: baseMesh3D,
        coverMesh3D: coverMesh3D,
        combinedMesh3D: combinedMesh3D,
        calculatedTakeoff: takeoff,
        scaledPorts: ladderAssembly.splicePorts,
      );
    }

    // 1. Resolve CMS Product Contract & baseline ports
    final contract = _resolveContract(instance.templateReference.templateId, baselineDoc);
    final baselinePorts = _extractBaselinePorts(baselineDoc, contract);

    // 2. Perform Parametric Scaling
    final controller = CmsScalingController(
      contract: contract,
      baselineDocument: baselineDoc.copyWith(
        parameters: {
          ...baselineDoc.parameters,
          ...instance.instanceParameters,
        },
      ),
      baselinePorts: baselinePorts,
      currentParameterValues: instance.instanceParameters,
    );

    if ((instance.instanceParameters['include_coupler_flaps'] ?? 0.0) > 0.5) {
      controller.setIncludeCouplerFlaps(true);
    }
    if (instance.instanceParameters.containsKey('coupler_flap_length')) {
      controller.setCouplerFlapLength(instance.instanceParameters['coupler_flap_length']!);
    }

    // Apply instance parameter overrides
    for (final entry in instance.instanceParameters.entries) {
      if (controller.model.parameters.containsKey(entry.key)) {
        controller.selectParameter(entry.key);
        controller.evaluateMorph(entry.value);
      }
    }

    var scaledBaseDoc = controller.currentPreview?.scaledDocument ?? baselineDoc;

    // Apply flange direction override (0.0 = Inside Flange (BEND_UP), 1.0 = Outside Return (BEND_DOWN))
    if (instance.instanceParameters.containsKey('flange_direction')) {
      final isInside = (instance.instanceParameters['flange_direction'] ?? 0.0) == 0.0;
      final targetDir = isInside ? BendDirection.up : BendDirection.down;
      final targetLayer = isInside ? 'BEND_UP' : 'BEND_DOWN';
      final updatedBends = scaledBaseDoc.bends.map((b) {
        final isFlange = b.role == BendLineRole.flange ||
            b.layer.toUpperCase().contains('FLANGE') ||
            b.id.toUpperCase().startsWith('FL') ||
            b.parentFaceId.toUpperCase().contains('FLANGE') ||
            b.childFaceId.toUpperCase().contains('FLANGE');
        if (isFlange) {
          return b.copyWith(direction: targetDir, layer: targetLayer);
        }
        return b;
      }).toList();
      scaledBaseDoc = scaledBaseDoc.copyWith(bends: updatedBends);
    }

    // 3. Generate Live Parametric Cover
    TrunkingCoverData? coverData;
    if (instance.coverConfiguration.included) {
      final placementMode = _parsePlacementMode(instance.coverConfiguration.placementMode3D);
      coverData = TrunkingCoverGenerator.generateCover(
        scaledBaseDoc,
        parameterOverrides: instance.instanceParameters,
        flangeDepth: instance.coverConfiguration.flangeDepthMm,
        placementMode3D: placementMode,
      );
    }

    // 4. Fold Base Model in 3D
    final baseMesh3D = KinematicFoldEngine.foldDocument(
      scaledBaseDoc,
      foldProgress: 1.0,
      ensureBaseFloorAtBottom: false,
    );

    // 5. Fold and Position Cover in 3D
    FoldedMeshResult? coverMesh3D;
    if (coverData != null) {
      coverMesh3D = _buildCover3DMesh(coverData, instance.coverConfiguration);
    }

    // 6. Combine 3D Meshes
    final combinedMesh3D = coverMesh3D != null
        ? baseMesh3D.combineWith(coverMesh3D, preserveCenter: true)
        : baseMesh3D;

    // 7. Calculate Material Takeoff
    final takeoff = _calculateTakeoff(scaledBaseDoc, coverData?.document, instance.material);
    final scaledPorts = controller.currentPreview?.derivedPorts ?? baselinePorts;

    return EvaluatedDdsInstance(
      instance: instance.copyWith(calculatedTakeoff: takeoff),
      scaledBaseDocument: scaledBaseDoc,
      coverData: coverData,
      baseMesh3D: baseMesh3D,
      coverMesh3D: coverMesh3D,
      combinedMesh3D: combinedMesh3D,
      calculatedTakeoff: takeoff,
      scaledPorts: scaledPorts,
    );
  }

  /// Builds and transforms the 3D folded mesh for the cover.
  static FoldedMeshResult? _buildCover3DMesh(
    TrunkingCoverData coverData,
    DdsCoverConfig coverConfig,
  ) {
    final baseCoverMesh = KinematicFoldEngine.foldDocument(
      coverData.document,
      foldProgress: 1.0,
      ensureBaseFloorAtBottom: false,
    );

    final isReducer = coverData.properties['isReducerCover'] == true;
    final clearanceZ = (coverData.properties['snappedClearanceZ'] as num?)?.toDouble() ??
        TrunkingCoverGenerator.defaultCoverClearanceZ;

    // Additional elevation if exploded view is requested
    final explodedLift = coverConfig.placementMode3D == 'exploded' ? 40.0 : 0.0;
    final totalClearanceZ = clearanceZ + explodedLift;

    if (isReducer && coverConfig.placementMode3D != 'besideBase') {
      final h1 = (coverData.properties['port1Height'] as num?)?.toDouble() ?? 100.0;
      final y1 = (coverData.properties['port1Y'] as num?)?.toDouble() ?? 0.0;
      final alpha = (coverData.properties['slopeAngleRad'] as num?)?.toDouble() ?? 0.0;
      final cosA = math.cos(alpha);
      final sinA = math.sin(alpha);

      final ox = coverConfig.customOffset3D.x;
      final oy = coverConfig.customOffset3D.y;
      final oz = coverConfig.customOffset3D.z;

      CadPoint3D transformPt(CadPoint3D p) {
        final yLocal = p.y - y1;
        final x3d = p.x + ox;
        final y3d = y1 + yLocal * cosA + p.z * sinA + oy;
        final z3d = (h1 + totalClearanceZ) - yLocal * sinA + p.z * cosA + oz;
        return CadPoint3D(x3d, y3d, z3d);
      }

      CadPoint3D transformNormal(CadPoint3D n) {
        final nx = n.x;
        final ny = n.y * cosA + n.z * sinA;
        final nz = -n.y * sinA + n.z * cosA;
        return CadPoint3D(nx, ny, nz);
      }

      return baseCoverMesh.transform(
        transformPt,
        transformNormal: transformNormal,
        colorOverride: const Color(0xFF64748B),
        faceIdPrefix: 'COVER',
      );
    }

    final double tx, ty, tz;
    if (coverConfig.placementMode3D == 'besideBase') {
      tx = coverData.offset2D.x + coverConfig.customOffset3D.x;
      ty = coverData.offset2D.y + coverConfig.customOffset3D.y;
      tz = coverConfig.customOffset3D.z;
    } else {
      // Snapped or exploded
      final bodyHeight = (coverData.properties['bodyHeightMm'] as num?)?.toDouble() ?? 100.0;
      tx = coverConfig.customOffset3D.x;
      ty = coverConfig.customOffset3D.y;
      tz = bodyHeight + totalClearanceZ + coverConfig.customOffset3D.z;
    }

    return baseCoverMesh.translate(
      tx,
      ty,
      tz,
      colorOverride: const Color(0xFF64748B),
      faceIdPrefix: 'COVER',
    );
  }

  /// Extracts baseline ports from metadata or discovers them from geometry.
  static List<CmsPhysicalPort> _extractBaselinePorts(DsfDocument doc, CmsProductContract contract) {
    final meta = doc.metadata['cmsTemplate'];
    if (meta is Map) {
      if (meta['baselinePorts'] is List) {
        try {
          return (meta['baselinePorts'] as List)
              .whereType<Map>()
              .map((m) => CmsPhysicalPort.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        } catch (_) {}
      }
      if (meta['ports'] is List) {
        try {
          return (meta['ports'] as List)
              .whereType<Map>()
              .map((m) => CmsPhysicalPort.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        } catch (_) {}
      }
    }

    try {
      final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: doc, foldResult: foldResult);
      if (rawOpenings.isNotEmpty) {
        final measured = rawOpenings
            .map((r) => CmsOpeningPlaneAnalyzer.analyze(
                  raw: r,
                  document: doc,
                  foldResult: foldResult,
                ))
            .toList();
        final matchResult = CmsPortMatcher.match(
          measuredOpenings: measured,
          contract: contract,
        );
        return matchResult.matchedPorts;
      }
    } catch (_) {}

    return const [];
  }

  /// Calculates total blank surface area (m²) and estimated net mass (kg).
  static DdsCalculatedTakeoff _calculateTakeoff(
    DsfDocument baseDoc,
    DsfDocument? coverDoc,
    String materialName,
  ) {
    double totalAreaMm2 = 0.0;

    // Sum polygon face areas in base document
    for (final face in baseDoc.faces) {
      totalAreaMm2 += face.areaMm2.abs();
    }

    // Add cover face areas if present
    if (coverDoc != null) {
      for (final face in coverDoc.faces) {
        totalAreaMm2 += face.areaMm2.abs();
      }
    }

    final totalAreaM2 = totalAreaMm2 / 1000000.0;
    final thicknessMm = baseDoc.material.thicknessMm > 0 ? baseDoc.material.thicknessMm : 1.5;

    final double density = resolveDensity(materialName);

    // Mass (kg) = Area (m²) * Thickness (m) * Density (kg/m³)
    final massKg = totalAreaM2 * (thicknessMm / 1000.0) * density;

    return DdsCalculatedTakeoff(
      blankSurfaceAreaM2: double.parse(totalAreaM2.toStringAsFixed(3)),
      estimatedNetWeightKg: double.parse(massKg.toStringAsFixed(2)),
    );
  }

  static CmsProductContract _resolveContract(String templateId, DsfDocument doc) {
    final lowerId = templateId.toLowerCase();
    final lowerType = doc.productType.toLowerCase();

    if (lowerId.contains('reducer') || lowerType.contains('reducer')) {
      return CmsProductContract.straightReducer;
    }
    if (lowerId.contains('unequal_cross') || lowerType.contains('unequal cross')) {
      return CmsProductContract.unequalCross;
    }
    if (lowerId.contains('equal_cross') || lowerType.contains('cross')) {
      return CmsProductContract.equalCross;
    }
    if (lowerId.contains('unequal_tee') || lowerType.contains('unequal tee')) {
      return CmsProductContract.unequalTee;
    }
    if (lowerId.contains('tee')) {
      return CmsProductContract.equalTee;
    }
    if (lowerId.contains('inside_riser')) {
      if (lowerId.contains('90')) return CmsProductContract.insideRiser90;
      return CmsProductContract.insideRiser45;
    }
    if (lowerId.contains('outside_riser')) {
      if (lowerId.contains('90')) return CmsProductContract.outsideRiser90;
      return CmsProductContract.outsideRiser45;
    }
    if (lowerId.contains('45')) {
      return CmsProductContract.bend45;
    }
    return CmsProductContract.bend90;
  }

  static CoverPlacementMode3D _parsePlacementMode(String mode) {
    switch (mode) {
      case 'besideBase':
        return CoverPlacementMode3D.besideBase;
      case 'exploded':
      case 'snappedToBase':
      default:
        return CoverPlacementMode3D.snappedToBase;
    }
  }
}
