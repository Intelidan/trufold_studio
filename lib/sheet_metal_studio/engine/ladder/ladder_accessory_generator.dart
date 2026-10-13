import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/cad_primitives.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../models/ladder/ladder_assembly_models.dart';
import '../../models/ladder/ladder_assembly_parameters.dart';
import '../../models/sheet_metal_material.dart';
import '../kinematic_fold_engine.dart';
import 'ladder_assembly_generator.dart';

/// Pure generative engine for Cable Ladder Accessories:
/// - Horizontal Bends (30°, 45°, 60°, 90°)
/// - Inside & Outside Risers (30°, 45°, 90°)
/// - Reducers (Straight / Concentric, Left, Right)
/// - Equal & Unequal Tees
/// - Equal & Unequal Crosses
///
/// Implements the 4 deterministic trajectory patterns defined in the
/// TruFold Studio Ladder Specification:
/// 1. Radial Spokes (Bends)
/// 2. Slope Stations (Risers)
/// 3. Linearly Tapered Rungs (Reducers)
/// 4. Orthogonal Spine & Branch (Tees & Crosses)
class LadderAccessoryGenerator {
  static const double densitySteel = 7850.0;
  static const double rungProfileW = 40.0;
  static const double rungProfileLeg = 20.0;
  static const double rungBlankWidth = 80.0; // (2 * 20) + 40
  static const double defaultLeadIn = 75.0; // Tangent lead-in for splice couplers

  // Colors for 3D meshes
  static const Color railColor = Color(0xFF90A4AE);
  static const Color rungColor = Color(0xFF78909C);
  static const Color weldColor = Color(0xFF64748B);

  // ===========================================================================
  // 1. HORIZONTAL BENDS (Radial Spokes Pattern)
  // ===========================================================================

  static DsfLadderAssembly generateHorizontalBend({required double angleDeg, double radiusMm = 300.0, required LadderAssemblyParameters params}) {
    final double angleRad = angleDeg * math.pi / 180.0;
    final double rIn = radiusMm;
    final double rOut = radiusMm + params.width;
    final double rMid = radiusMm + (params.width / 2.0);
    final double leadIn = defaultLeadIn;

    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented ? ((angleDeg >= 75.0) ? 4 : ((angleDeg >= 35.0) ? 3 : 2)) : 16;

    final double lArcMid = rMid * angleRad;
    final int rungCount = isSegmented ? segments : math.max(2, (lArcMid / params.intermediateTargetPitch).round() + 1);

    final double rungCutLength = params.physicalRungCutLength;
    final slotDim = params.railSlotDimensions;
    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);

    // Developed Rail Blank Dimensions
    final double innerRailLength = (2 * leadIn) + (rIn * angleRad);
    final double outerRailLength = (2 * leadIn) + (rOut * angleRad);
    final double railFlatWidth = params.height + (2 * params.flangeWidth);

    // Station positions along inner and outer rails, rung 3D centers, and joint locations
    final innerStations = <double>[];
    final outerStations = <double>[];
    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];
    const double rungCenterZ = 20.0;

    if (isSegmented) {
      final double deltaPhi = angleRad / (segments - 1);
      final tanHalf = math.tan(deltaPhi / 2.0);
      final outletT = CadPoint3D(-math.sin(angleRad), math.cos(angleRad), 0.0);

      for (int i = 0; i < segments; i++) {
        CadPoint3D c3D;
        CadPoint3D wIn;
        CadPoint3D wOut;
        double alpha;
        double stIn;
        double stOut;

        if (i == 0) {
          // Inlet straight collar
          final double yMid = (-leadIn + (rMid * tanHalf)) / 2.0;
          alpha = 0.0;
          c3D = CadPoint3D(rMid, yMid, rungCenterZ);
          wIn = CadPoint3D(rIn, yMid, rungCenterZ);
          wOut = CadPoint3D(rOut, yMid, rungCenterZ);
          stIn = leadIn + yMid;
          stOut = leadIn + yMid;
        } else if (i == segments - 1) {
          // Outlet straight collar
          alpha = angleRad;
          final double dMid = (leadIn - (rMid * tanHalf)) / 2.0;

          c3D = CadPoint3D((rMid * math.cos(angleRad)) + (outletT.x * dMid), (rMid * math.sin(angleRad)) + (outletT.y * dMid), rungCenterZ);
          wIn = CadPoint3D((rIn * math.cos(angleRad)) + (outletT.x * dMid), (rIn * math.sin(angleRad)) + (outletT.y * dMid), rungCenterZ);
          wOut = CadPoint3D((rOut * math.cos(angleRad)) + (outletT.x * dMid), (rOut * math.sin(angleRad)) + (outletT.y * dMid), rungCenterZ);
          stIn = innerRailLength - leadIn + dMid;
          stOut = outerRailLength - leadIn + dMid;
        } else {
          // Intermediate straight facet
          alpha = i * deltaPhi;
          c3D = CadPoint3D(rMid * math.cos(alpha), rMid * math.sin(alpha), rungCenterZ);
          wIn = CadPoint3D(rIn * math.cos(alpha), rIn * math.sin(alpha), rungCenterZ);
          wOut = CadPoint3D(rOut * math.cos(alpha), rOut * math.sin(alpha), rungCenterZ);
          stIn = leadIn + (rIn * alpha);
          stOut = leadIn + (rOut * alpha);
        }

        innerStations.add(stIn);
        outerStations.add(stOut);

        rungs.add(
          LadderRungInstance(
            index: i,
            stationX: rMid * alpha,
            center3D: c3D,
            cutLength: rungCutLength,
            orientationAngleRad: alpha,
            jointMethod: params.jointMethod,
          ),
        );

        joints.add(
          LadderJointInstance(
            rungIndex: i,
            railSide: 'left',
            stationX: stIn,
            weldCenter3D: wIn,
            slotCenter2D: CadPoint2D(stIn, params.flangeWidth + 20.0),
            hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
            outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
          ),
        );

        joints.add(
          LadderJointInstance(
            rungIndex: i,
            railSide: 'right',
            stationX: stOut,
            weldCenter3D: wOut,
            slotCenter2D: CadPoint2D(stOut, params.flangeWidth + 20.0),
            hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
            outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
          ),
        );
      }
    } else {
      // Curved mode
      for (int i = 0; i < rungCount; i++) {
        final double alpha = angleRad * (i + 0.5) / rungCount;
        final double cx = rMid * math.cos(alpha);
        final double cy = rMid * math.sin(alpha);
        final double stIn = leadIn + (rIn * alpha);
        final double stOut = leadIn + (rOut * alpha);

        innerStations.add(stIn);
        outerStations.add(stOut);

        rungs.add(
          LadderRungInstance(
            index: i,
            stationX: rMid * alpha,
            center3D: CadPoint3D(cx, cy, rungCenterZ),
            cutLength: rungCutLength,
            orientationAngleRad: alpha,
            jointMethod: params.jointMethod,
          ),
        );

        joints.add(
          LadderJointInstance(
            rungIndex: i,
            railSide: 'left',
            stationX: stIn,
            weldCenter3D: CadPoint3D(rIn * math.cos(alpha), rIn * math.sin(alpha), rungCenterZ),
            slotCenter2D: CadPoint2D(stIn, params.flangeWidth + 20.0),
            hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
            outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
          ),
        );

        joints.add(
          LadderJointInstance(
            rungIndex: i,
            railSide: 'right',
            stationX: stOut,
            weldCenter3D: CadPoint3D(rOut * math.cos(alpha), rOut * math.sin(alpha), rungCenterZ),
            slotCenter2D: CadPoint2D(stOut, params.flangeWidth + 20.0),
            hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
            outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
          ),
        );
      }
    }

    // Developed Miter Bend Stations & V-Notch calculation
    final innerMiterStations = <double>[];
    final outerMiterStations = <double>[];
    double deltaPhi = 0.0;

    if (isSegmented) {
      deltaPhi = angleRad / (segments - 1);
      for (int k = 0; k < segments - 1; k++) {
        final double psi = (k + 0.5) * deltaPhi;
        innerMiterStations.add(leadIn + (rIn * psi));
        outerMiterStations.add(leadIn + (rOut * psi));
      }
    }

    final bool notchOuter = isSegmented && params.flangeDirection == LadderFlangeDirection.inside;
    final bool notchInner = isSegmented && params.flangeDirection == LadderFlangeDirection.outside;

    // Flat Blanks
    final leftRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'inner',
      name: 'Inner Curved Rail Blank',
      params: params,
      railFlatLength: innerRailLength,
      railFlatWidth: railFlatWidth,
      stations: innerStations,
      slotDim: slotDim,
      material: material,
      miterBendStations: isSegmented ? innerMiterStations : null,
      hasFlangeVNotches: notchInner,
      miterDeltaPhi: deltaPhi,
    );

    final rightRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'outer',
      name: 'Outer Curved Rail Blank',
      params: params,
      railFlatLength: outerRailLength,
      railFlatWidth: railFlatWidth,
      stations: outerStations,
      slotDim: slotDim,
      material: material,
      miterBendStations: isSegmented ? outerMiterStations : null,
      hasFlangeVNotches: notchOuter,
      miterDeltaPhi: deltaPhi,
    );

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(rungCutLength: rungCutLength, material: material);

    // Splice Ports
    final splicePorts = <CmsPhysicalPort>[
      CmsPhysicalPort(
        id: 'port_1_inlet',
        index: 1,
        center: CadPoint3D(rMid, -leadIn, params.height / 2.0),
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        width: params.width,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_2_outlet',
        index: 2,
        center: CadPoint3D(
          (rMid * math.cos(angleRad)) - (leadIn * math.sin(angleRad)),
          (rMid * math.sin(angleRad)) + (leadIn * math.cos(angleRad)),
          params.height / 2.0,
        ),
        normal: CadPoint3D(-math.sin(angleRad), math.cos(angleRad), 0.0),
        width: params.width,
        height: params.height,
      ),
    ];

    // 3D Assembly Mesh
    final mesh3D = _buildHorizontalBendMesh(angleRad: angleRad, rIn: rIn, rOut: rOut, leadIn: leadIn, rungs: rungs, joints: joints, params: params);

    // BOM
    final double totalAreaM2 =
        (innerRailLength + outerRailLength) / 1000.0 * (railFlatWidth / 1000.0) + (rungCount * (rungCutLength / 1000.0) * (rungBlankWidth / 1000.0));
    final double totalWeightKg = totalAreaM2 * (params.thickness / 1000.0) * densitySteel;

    final bom = LadderHardwareBOM(
      rungCount: rungCount,
      passThroughSlotCount: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 2 * rungCount : 0,
      weldJointCount: 2 * rungCount,
      totalWeldLengthMm: 2 * rungCount * (params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 120.0 : 80.0),
      spliceCouplerCount: 2,
      couplerBoltCount: 8,
      couplerNutCount: 8,
      couplerWasherCount: 8,
      totalSteelWeightKg: double.parse(totalWeightKg.toStringAsFixed(2)),
    );

    final stylePrefix = params.accessoryStyle == LadderAccessoryStyle.segmented ? 'Segmented ' : '';
    return DsfLadderAssembly(
      id: 'LAD-BEND-${params.accessoryStyle.name.toUpperCase()}-${angleDeg.round()}DEG-${params.width.round()}X${params.height.round()}',
      productName:
          'Cable Ladder ${angleDeg.round()}° ${stylePrefix}Horizontal Bend ${params.width.round()}×${params.height.round()}mm (R=${radiusMm.round()}mm)',
      parameters: params,
      leftRailBlank: leftRailPart,
      rightRailBlank: rightRailPart,
      rungBlank: rungPart,
      rungs: rungs,
      joints: joints,
      splicePorts: splicePorts,
      assembledMesh3D: mesh3D,
      hardwareBOM: bom,
    );
  }

  // ===========================================================================
  // 2. RISERS (Slope Stations Pattern)
  // ===========================================================================

  static DsfLadderAssembly generateRiser({
    required double angleDeg,
    double radiusMm = 300.0,
    required bool isInsideRiser,
    required LadderAssemblyParameters params,
  }) {
    final double angleRad = angleDeg * math.pi / 180.0;
    final double r = radiusMm;
    final double leadIn = defaultLeadIn;

    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented ? ((angleDeg >= 75.0) ? 4 : ((angleDeg >= 35.0) ? 3 : 2)) : 16;

    final double arcLength = r * angleRad;
    final int rungCount = isSegmented ? segments : math.max(2, (arcLength / params.intermediateTargetPitch).round() + 1);

    final double rungCutLength = params.physicalRungCutLength;
    final slotDim = params.railSlotDimensions;
    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);

    final double railDevLength = (2 * leadIn) + arcLength;
    final double railFlatWidth = params.height + (2 * params.flangeWidth);

    final stations = <double>[];
    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];
    final double halfW = params.width / 2.0;

    CadPoint3D pOutletBottom = const CadPoint3D(0.0, 0.0, 0.0);
    CadPoint3D pOutletTop = const CadPoint3D(0.0, 0.0, 0.0);
    CadPoint3D tExit = CadPoint3D(math.cos(angleRad), 0.0, isInsideRiser ? math.sin(angleRad) : -math.sin(angleRad));

    if (isSegmented) {
      final double deltaPhi = angleRad / (segments - 1);
      final cosHalf = math.cos(deltaPhi / 2.0);

      final mBottom = <CadPoint3D>[];
      final mTop = <CadPoint3D>[];

      for (int k = 0; k < segments - 1; k++) {
        final double psi = (k + 0.5) * deltaPhi;
        final double rScale = r / cosHalf;
        final double hScale = params.height / cosHalf;

        final double bx = rScale * math.sin(psi);
        final double bz = isInsideRiser ? (r - (rScale * math.cos(psi))) : (-r + (rScale * math.cos(psi)));
        mBottom.add(CadPoint3D(bx, 0.0, bz));

        final double nx = isInsideRiser ? -math.sin(psi) : math.sin(psi);
        final double nz = math.cos(psi);
        mTop.add(CadPoint3D(bx + (nx * hScale), 0.0, bz + (nz * hScale)));
      }

      final pInletBottom = CadPoint3D(-leadIn, 0.0, 0.0);
      final pInletTop = CadPoint3D(-leadIn, 0.0, params.height);

      final uExit = CadPoint3D(isInsideRiser ? -math.sin(angleRad) : math.sin(angleRad), 0.0, math.cos(angleRad));
      final pCircBottom = CadPoint3D(r * math.sin(angleRad), 0.0, isInsideRiser ? r * (1.0 - math.cos(angleRad)) : -r * (1.0 - math.cos(angleRad)));
      pOutletBottom = CadPoint3D(pCircBottom.x + (tExit.x * leadIn), 0.0, pCircBottom.z + (tExit.z * leadIn));
      pOutletTop = CadPoint3D(pOutletBottom.x + (uExit.x * params.height), 0.0, pOutletBottom.z + (uExit.z * params.height));

      for (int i = 0; i < segments; i++) {
        final pbStart = (i == 0) ? pInletBottom : mBottom[i - 1];
        final pbEnd = (i == segments - 1) ? pOutletBottom : mBottom[i];
        final ptStart = (i == 0) ? pInletTop : mTop[i - 1];
        final ptEnd = (i == segments - 1) ? pOutletTop : mTop[i];

        final pbMid = CadPoint3D((pbStart.x + pbEnd.x) / 2.0, 0.0, (pbStart.z + pbEnd.z) / 2.0);
        final ptMid = CadPoint3D((ptStart.x + ptEnd.x) / 2.0, 0.0, (ptStart.z + ptEnd.z) / 2.0);

        final uDiff = CadPoint3D(ptMid.x - pbMid.x, 0.0, ptMid.z - pbMid.z);
        final uLen = math.sqrt((uDiff.x * uDiff.x) + (uDiff.z * uDiff.z));
        final uNorm = uLen > 1e-6 ? CadPoint3D(uDiff.x / uLen, 0.0, uDiff.z / uLen) : const CadPoint3D(0.0, 0.0, 1.0);

        final cXz = CadPoint3D(pbMid.x + (uNorm.x * 20.0), 0.0, pbMid.z + (uNorm.z * 20.0));
        final double alpha = i * deltaPhi;

        double st;
        if (i == 0) {
          st = leadIn + pbMid.x;
        } else if (i == segments - 1) {
          st = railDevLength - (leadIn / 2.0);
        } else {
          st = leadIn + (r * alpha);
        }
        stations.add(st);

        rungs.add(
          LadderRungInstance(index: i, stationX: st, center3D: cXz, cutLength: rungCutLength, orientationAngleRad: alpha, jointMethod: params.jointMethod),
        );

        joints.add(
          LadderJointInstance(
            rungIndex: i,
            railSide: 'left',
            stationX: st,
            weldCenter3D: CadPoint3D(cXz.x, -halfW, cXz.z),
            slotCenter2D: CadPoint2D(st, params.flangeWidth + 20.0),
            hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
            outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
          ),
        );

        joints.add(
          LadderJointInstance(
            rungIndex: i,
            railSide: 'right',
            stationX: st,
            weldCenter3D: CadPoint3D(cXz.x, halfW, cXz.z),
            slotCenter2D: CadPoint2D(st, params.flangeWidth + 20.0),
            hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
            outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
          ),
        );
      }
    } else {
      // Curved mode
      final pCircBottom = CadPoint3D(r * math.sin(angleRad), 0.0, isInsideRiser ? r * (1.0 - math.cos(angleRad)) : -r * (1.0 - math.cos(angleRad)));
      final uExit = CadPoint3D(isInsideRiser ? -math.sin(angleRad) : math.sin(angleRad), 0.0, math.cos(angleRad));
      pOutletBottom = CadPoint3D(pCircBottom.x + (tExit.x * leadIn), 0.0, pCircBottom.z + (tExit.z * leadIn));
      pOutletTop = CadPoint3D(pOutletBottom.x + (uExit.x * params.height), 0.0, pOutletBottom.z + (uExit.z * params.height));

      for (int i = 0; i < rungCount; i++) {
        final double alpha = angleRad * (i + 0.5) / rungCount;
        final double rx = r * math.sin(alpha);
        final double rz = isInsideRiser ? r * (1.0 - math.cos(alpha)) + 20.0 : -(r * (1.0 - math.cos(alpha))) + 20.0;
        final double st = leadIn + (r * alpha);
        stations.add(st);

        rungs.add(
          LadderRungInstance(
            index: i,
            stationX: st,
            center3D: CadPoint3D(rx, 0.0, rz),
            cutLength: rungCutLength,
            orientationAngleRad: alpha,
            jointMethod: params.jointMethod,
          ),
        );

        joints.add(
          LadderJointInstance(
            rungIndex: i,
            railSide: 'left',
            stationX: st,
            weldCenter3D: CadPoint3D(rx, -halfW, rz),
            slotCenter2D: CadPoint2D(st, params.flangeWidth + 20.0),
            hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
            outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
          ),
        );

        joints.add(
          LadderJointInstance(
            rungIndex: i,
            railSide: 'right',
            stationX: st,
            weldCenter3D: CadPoint3D(rx, halfW, rz),
            slotCenter2D: CadPoint2D(st, params.flangeWidth + 20.0),
            hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
            outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
          ),
        );
      }
    }

    final railPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: isInsideRiser ? 'inside_riser' : 'outside_riser',
      name: '${isInsideRiser ? "Inside" : "Outside"} Riser Rail Blank',
      params: params,
      railFlatLength: railDevLength,
      railFlatWidth: railFlatWidth,
      stations: stations,
      slotDim: slotDim,
      material: material,
    );

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(rungCutLength: rungCutLength, material: material);

    final splicePorts = <CmsPhysicalPort>[
      CmsPhysicalPort(
        id: 'port_1_lower',
        index: 1,
        center: CadPoint3D(-leadIn, 0.0, params.height / 2.0),
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        width: params.width,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_2_upper',
        index: 2,
        center: CadPoint3D((pOutletBottom.x + pOutletTop.x) / 2.0, 0.0, (pOutletBottom.z + pOutletTop.z) / 2.0),
        normal: tExit,
        width: params.width,
        height: params.height,
      ),
    ];

    final mesh3D = _buildRiserMesh(angleRad: angleRad, radius: r, leadIn: leadIn, isInsideRiser: isInsideRiser, rungs: rungs, joints: joints, params: params);

    final double totalAreaM2 = 2 * (railDevLength / 1000.0) * (railFlatWidth / 1000.0) + (rungCount * (rungCutLength / 1000.0) * (rungBlankWidth / 1000.0));
    final double totalWeightKg = totalAreaM2 * (params.thickness / 1000.0) * densitySteel;

    final bom = LadderHardwareBOM(
      rungCount: rungCount,
      passThroughSlotCount: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 2 * rungCount : 0,
      weldJointCount: 2 * rungCount,
      totalWeldLengthMm: 2 * rungCount * (params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 120.0 : 80.0),
      spliceCouplerCount: 2,
      couplerBoltCount: 8,
      couplerNutCount: 8,
      couplerWasherCount: 8,
      totalSteelWeightKg: double.parse(totalWeightKg.toStringAsFixed(2)),
    );

    final String typeName = isInsideRiser ? 'Inside Riser' : 'Outside Riser';
    final stylePrefix = params.accessoryStyle == LadderAccessoryStyle.segmented ? 'Segmented ' : '';
    return DsfLadderAssembly(
      id: 'LAD-${params.accessoryStyle.name.toUpperCase()}-${isInsideRiser ? "IN" : "OUT"}-RISER-${angleDeg.round()}DEG-${params.width.round()}X${params.height.round()}',
      productName: 'Cable Ladder ${angleDeg.round()}° $stylePrefix$typeName ${params.width.round()}×${params.height.round()}mm (R=${radiusMm.round()}mm)',
      parameters: params,
      leftRailBlank: railPart,
      rightRailBlank: railPart,
      rungBlank: rungPart,
      rungs: rungs,
      joints: joints,
      splicePorts: splicePorts,
      assembledMesh3D: mesh3D,
      hardwareBOM: bom,
    );
  }

  // ===========================================================================
  // 3. REDUCERS (Linearly Tapered Rungs Pattern)
  // ===========================================================================

  static DsfLadderAssembly generateReducer({
    required double width1,
    required double width2,
    double length = 500.0,
    String alignment = 'straight',
    required LadderAssemblyParameters params,
  }) {
    final double leadIn = defaultLeadIn;
    final double taperLength = length - (2 * leadIn);
    final int rungCount = math.max(2, (taperLength / params.intermediateTargetPitch).round() + 1);
    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);
    final slotDim = params.railSlotDimensions;

    final stations = <double>[];
    final rungCutLengths = <double>[];
    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];

    for (int i = 0; i < rungCount; i++) {
      final double x = leadIn + (taperLength * (i + 0.5) / rungCount);
      stations.add(x);

      // Local width calculation based on alignment
      final double t = (x - leadIn) / taperLength;
      final double localW = width1 - (t * (width1 - width2));

      final double cutLen = params.jointMethod == LadderRungJointMethod.directInsideWeld
          ? localW
          : localW + (2 * params.thickness) + (2 * params.outsideWeldProjection);
      rungCutLengths.add(cutLen);

      double yCenter = 0.0;
      double yLeft = -localW / 2.0;
      double yRight = localW / 2.0;

      if (alignment == 'left') {
        yLeft = -width1 / 2.0;
        yRight = yLeft + localW;
        yCenter = (yLeft + yRight) / 2.0;
      } else if (alignment == 'right') {
        yRight = width1 / 2.0;
        yLeft = yRight - localW;
        yCenter = (yLeft + yRight) / 2.0;
      }

      rungs.add(LadderRungInstance(index: i, stationX: x, center3D: CadPoint3D(x, yCenter, 20.0), cutLength: cutLen, jointMethod: params.jointMethod));

      joints.add(
        LadderJointInstance(
          rungIndex: i,
          railSide: 'left',
          stationX: x,
          weldCenter3D: CadPoint3D(x, yLeft, 20.0),
          slotCenter2D: CadPoint2D(x, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ),
      );

      joints.add(
        LadderJointInstance(
          rungIndex: i,
          railSide: 'right',
          stationX: x,
          weldCenter3D: CadPoint3D(x, yRight, 20.0),
          slotCenter2D: CadPoint2D(x, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ),
      );
    }

    final double railFlatWidth = params.height + (2 * params.flangeWidth);
    final leftRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'left',
      name: 'Left Reducer Rail Blank',
      params: params,
      railFlatLength: length,
      railFlatWidth: railFlatWidth,
      stations: stations,
      slotDim: slotDim,
      material: material,
    );

    final rightRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'right',
      name: 'Right Reducer Rail Blank',
      params: params,
      railFlatLength: length,
      railFlatWidth: railFlatWidth,
      stations: stations,
      slotDim: slotDim,
      material: material,
    );

    final double avgRungLength = rungCutLengths.reduce((a, b) => a + b) / rungCutLengths.length;
    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(rungCutLength: avgRungLength, material: material);

    final splicePorts = <CmsPhysicalPort>[
      CmsPhysicalPort(
        id: 'port_1_wide',
        index: 1,
        center: CadPoint3D(0.0, 0.0, params.height / 2.0),
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        width: width1,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_2_narrow',
        index: 2,
        center: CadPoint3D(length, 0.0, params.height / 2.0),
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        width: width2,
        height: params.height,
      ),
    ];

    final mesh3D = _buildReducerMesh(width1: width1, width2: width2, length: length, leadIn: leadIn, alignment: alignment, stations: stations, params: params);

    final double totalAreaM2 = 2 * (length / 1000.0) * (railFlatWidth / 1000.0) + (rungCount * (avgRungLength / 1000.0) * (rungBlankWidth / 1000.0));
    final double totalWeightKg = totalAreaM2 * (params.thickness / 1000.0) * densitySteel;

    final bom = LadderHardwareBOM(
      rungCount: rungCount,
      passThroughSlotCount: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 2 * rungCount : 0,
      weldJointCount: 2 * rungCount,
      totalWeldLengthMm: 2 * rungCount * (params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 120.0 : 80.0),
      spliceCouplerCount: 2,
      couplerBoltCount: 8,
      couplerNutCount: 8,
      couplerWasherCount: 8,
      totalSteelWeightKg: double.parse(totalWeightKg.toStringAsFixed(2)),
    );

    return DsfLadderAssembly(
      id: 'LAD-RED-${width1.round()}X${width2.round()}X${params.height.round()}',
      productName: 'Cable Ladder Reducer ${width1.round()}×${width2.round()}×${params.height.round()}mm (L=${length.round()}mm)',
      parameters: params,
      leftRailBlank: leftRailPart,
      rightRailBlank: rightRailPart,
      rungBlank: rungPart,
      rungs: rungs,
      joints: joints,
      splicePorts: splicePorts,
      assembledMesh3D: mesh3D,
      hardwareBOM: bom,
    );
  }

  // ===========================================================================
  // 4. TEES & CROSSES (Orthogonal Spine & Branch Pattern)
  // ===========================================================================

  static DsfLadderAssembly generateEqualTee({required double width, double radiusMm = 300.0, required LadderAssemblyParameters params}) =>
      generateUnequalTee(mainInWidth: width, mainOutWidth: width, branchWidth: width, radiusMm: radiusMm, params: params);

  static DsfLadderAssembly generateUnequalTee({
    required double mainInWidth,
    required double mainOutWidth,
    required double branchWidth,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) {
    final double leadIn = defaultLeadIn;
    final double r = radiusMm;
    final double branchCenterX = leadIn + r + (branchWidth / 2.0);
    final double branchRightX = leadIn + r + branchWidth;
    final double mainLength = (2 * leadIn) + (2 * r) + branchWidth;
    final double throatY = math.max(mainInWidth, mainOutWidth) + r;
    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);
    final double railFlatWidth = params.height + (2 * params.flangeWidth);
    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;
    final double rungProj = isPassThrough ? params.outsideWeldProjection : 0.0;

    final double rungCutLengthBranch = branchWidth + (isPassThrough ? 2 * params.thickness + 2 * rungProj : 0.0);
    final double rungCutLengthMainIn = mainInWidth + (isPassThrough ? 2 * params.thickness + 2 * rungProj : 0.0);
    final double rungCutLengthMainOut = mainOutWidth + (isPassThrough ? 2 * params.thickness + 2 * rungProj : 0.0);

    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];
    int rungIdx = 0;

    // 1. Spine rungs along main run (parallel to Y, from back rail to front rails)
    // Exactly 4 spine stations: Port 3 inlet (50mm), inside corners (leadIn + r, branchRightX), Port 2 outlet (mainLength - 50mm)
    final spineStations = <double>[50.0, leadIn + r, branchRightX, mainLength - 50.0];

    for (final x in spineStations) {
      double spanY;
      double cutLen;
      final bool isInnerCornerRung = (x - (leadIn + r)).abs() < 1.0 || (x - branchRightX).abs() < 1.0;
      if (isInnerCornerRung) {
        // Vertical spine rungs connect directly into the horizontal inner rung at Y = throatY
        spanY = throatY;
        cutLen = spanY + (isPassThrough ? 2 * params.thickness + 2 * rungProj : 0.0);
      } else if (x < leadIn + r) {
        spanY = mainInWidth;
        cutLen = rungCutLengthMainIn;
      } else if (x > branchRightX) {
        spanY = mainOutWidth;
        cutLen = rungCutLengthMainOut;
      } else {
        spanY = math.max(mainInWidth, mainOutWidth);
        cutLen = spanY + (isPassThrough ? 2 * params.thickness + 2 * rungProj : 0.0);
      }
      rungs.add(
        LadderRungInstance(index: rungIdx, stationX: x, center3D: CadPoint3D(x, spanY / 2.0, 20.0), cutLength: cutLen, jointMethod: params.jointMethod),
      );
      joints.add(LadderJointInstance(rungIndex: rungIdx, railSide: 'back', stationX: x, weldCenter3D: CadPoint3D(x, 0.0, 20.0), hasOpening: isPassThrough));
      if (isInnerCornerRung) {
        joints.add(
          LadderJointInstance(
            rungIndex: rungIdx,
            railSide: (x - (leadIn + r)).abs() < 1.0 ? 'left_branch' : 'right_branch',
            stationX: throatY,
            weldCenter3D: CadPoint3D(x, throatY, 20.0),
            hasOpening: isPassThrough,
          ),
        );
      }
      rungIdx++;
    }

    // 2. Horizontal inner branch rung at Y = throatY joining the 2 bent side rails
    rungs.add(
      LadderRungInstance(
        index: rungIdx,
        stationX: throatY,
        center3D: CadPoint3D(branchCenterX, throatY, 20.0),
        cutLength: rungCutLengthBranch,
        orientationAngleRad: math.pi / 2.0,
        jointMethod: params.jointMethod,
      ),
    );
    joints.add(
      LadderJointInstance(
        rungIndex: rungIdx,
        railSide: 'left_branch',
        stationX: throatY,
        weldCenter3D: CadPoint3D(leadIn + r, throatY, 20.0),
        hasOpening: isPassThrough,
      ),
    );
    joints.add(
      LadderJointInstance(
        rungIndex: rungIdx,
        railSide: 'right_branch',
        stationX: throatY,
        weldCenter3D: CadPoint3D(branchRightX, throatY, 20.0),
        hasOpening: isPassThrough,
      ),
    );
    rungIdx++;

    // 3. Flat Blanks
    final leftRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'back_straight',
      name: 'Tee Back Rail Blank',
      params: params,
      railFlatLength: mainLength,
      railFlatWidth: railFlatWidth,
      stations: spineStations,
      slotDim: params.railSlotDimensions,
      material: material,
    );

    final double cornerCurveLen = params.accessoryStyle == LadderAccessoryStyle.segmented ? r * math.sqrt(2.0) : r * math.pi / 2.0;
    final double cornerRailLength = leadIn + cornerCurveLen;
    final leftCornerRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'corner_left',
      name: 'Tee Left Corner Rail Blank',
      params: params,
      railFlatLength: cornerRailLength,
      railFlatWidth: railFlatWidth,
      stations: [50.0, leadIn + (cornerCurveLen / 2.0), cornerRailLength - 25.0],
      miterBendStations: [leadIn],
      slotDim: params.railSlotDimensions,
      material: material,
    );

    final rightCornerRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'corner_right',
      name: 'Tee Right Corner Rail Blank',
      params: params,
      railFlatLength: cornerRailLength,
      railFlatWidth: railFlatWidth,
      stations: [25.0, cornerCurveLen / 2.0, cornerRailLength - 50.0],
      miterBendStations: [cornerCurveLen],
      slotDim: params.railSlotDimensions,
      material: material,
    );

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(rungCutLength: rungCutLengthBranch, material: material);

    // Port 1: Branch (P1 in UI) - ends directly at throatY
    // Port 2: Main Out / Right (P2 in UI)
    // Port 3: Main In / West (P3 in UI)
    final splicePorts = <CmsPhysicalPort>[
      CmsPhysicalPort(
        id: 'port_1_branch',
        index: 1,
        center: CadPoint3D(branchCenterX, throatY, params.height / 2.0),
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        width: branchWidth,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_2_main_out',
        index: 2,
        center: CadPoint3D(mainLength, mainOutWidth / 2.0, params.height / 2.0),
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        width: mainOutWidth,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_3_main_in',
        index: 3,
        center: CadPoint3D(0.0, mainInWidth / 2.0, params.height / 2.0),
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        width: mainInWidth,
        height: params.height,
      ),
    ];

    final mesh3D = _buildTeeMesh(
      mainInWidth: mainInWidth,
      mainOutWidth: mainOutWidth,
      branchWidth: branchWidth,
      radius: r,
      leadIn: leadIn,
      rungs: rungs,
      params: params,
    );

    final int totalRungCount = rungs.length;
    final double totalAreaM2 =
        (mainLength + 2 * cornerRailLength) / 1000.0 * (railFlatWidth / 1000.0) + (totalRungCount * (rungCutLengthBranch / 1000.0) * (rungBlankWidth / 1000.0));
    final double totalWeightKg = totalAreaM2 * (params.thickness / 1000.0) * densitySteel;

    final bom = LadderHardwareBOM(
      rungCount: totalRungCount,
      passThroughSlotCount: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 2 * totalRungCount : 0,
      weldJointCount: 2 * totalRungCount,
      totalWeldLengthMm: 2 * totalRungCount * (params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 120.0 : 80.0),
      spliceCouplerCount: 3,
      couplerBoltCount: 12,
      couplerNutCount: 12,
      couplerWasherCount: 12,
      totalSteelWeightKg: double.parse(totalWeightKg.toStringAsFixed(2)),
    );

    final stylePrefix = params.accessoryStyle == LadderAccessoryStyle.segmented ? 'Segmented ' : '';
    final bool isUnequal = (mainInWidth - branchWidth).abs() > 0.1 || (mainOutWidth - mainInWidth).abs() > 0.1;
    final String teeKind = isUnequal ? 'Unequal Tee' : 'Equal Tee';
    final String dims = isUnequal
        ? '${branchWidth.round()}×${mainOutWidth.round()}×${mainInWidth.round()}×${params.height.round()}mm'
        : '${mainInWidth.round()}×${branchWidth.round()}×${params.height.round()}mm';
    return DsfLadderAssembly(
      id: 'LAD-${isUnequal ? "UNEQUAL" : "EQUAL"}-TEE-${params.accessoryStyle.name.toUpperCase()}-${branchWidth.round()}X${mainOutWidth.round()}X${mainInWidth.round()}X${params.height.round()}',
      productName: 'Cable Ladder $stylePrefix$teeKind $dims (R=${radiusMm.round()}mm)',
      parameters: params,
      leftRailBlank: leftRailPart,
      rightRailBlank: leftCornerRailPart,
      additionalRailBlanks: [rightCornerRailPart],
      rungBlank: rungPart,
      rungs: rungs,
      joints: joints,
      splicePorts: splicePorts,
      assembledMesh3D: mesh3D,
      hardwareBOM: bom,
    );
  }

  static DsfLadderAssembly generateTee({
    required double mainWidth,
    required double branchWidth,
    double? runWidth,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) => generateUnequalTee(mainInWidth: mainWidth, mainOutWidth: runWidth ?? mainWidth, branchWidth: branchWidth, radiusMm: radiusMm, params: params);

  static DsfLadderAssembly generateEqualCross({required double width, double radiusMm = 300.0, required LadderAssemblyParameters params}) =>
      generateUnequalCross(westWidth: width, eastWidth: width, northWidth: width, southWidth: width, radiusMm: radiusMm, params: params);

  static DsfLadderAssembly generateUnequalCross({
    required double westWidth,
    required double eastWidth,
    required double northWidth,
    required double southWidth,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) {
    final double leadIn = defaultLeadIn;
    final double r = radiusMm;
    final double lWest = leadIn + r + math.max(northWidth, southWidth) / 2.0;
    final double lEast = leadIn + r + math.max(northWidth, southWidth) / 2.0;
    final double lNorth = leadIn + r + math.max(westWidth, eastWidth) / 2.0;
    final double lSouth = leadIn + r + math.max(westWidth, eastWidth) / 2.0;

    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);
    final double railFlatWidth = params.height + (2 * params.flangeWidth);

    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];

    int idx = 0;
    final double cutLenWest = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? westWidth
        : westWidth + (2 * params.thickness) + (2 * params.outsideWeldProjection);
    final double cutLenEast = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? eastWidth
        : eastWidth + (2 * params.thickness) + (2 * params.outsideWeldProjection);

    final double armSpanX = lWest - (math.max(northWidth, southWidth) / 2.0 + r / 2.0);
    final int rungsPerArmX = math.max(1, (armSpanX / params.intermediateTargetPitch).round());

    for (int i = 0; i < rungsPerArmX; i++) {
      final double xW = -lWest + leadIn / 2.0 + (armSpanX * (i + 0.5) / rungsPerArmX);
      rungs.add(LadderRungInstance(index: idx++, stationX: xW, center3D: CadPoint3D(xW, 0.0, 20.0), cutLength: cutLenWest, jointMethod: params.jointMethod));
      final double xE = lEast - leadIn / 2.0 - (armSpanX * (i + 0.5) / rungsPerArmX);
      rungs.add(LadderRungInstance(index: idx++, stationX: xE, center3D: CadPoint3D(xE, 0.0, 20.0), cutLength: cutLenEast, jointMethod: params.jointMethod));
    }

    final double cutLenSouth = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? southWidth
        : southWidth + (2 * params.thickness) + (2 * params.outsideWeldProjection);
    final double cutLenNorth = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? northWidth
        : northWidth + (2 * params.thickness) + (2 * params.outsideWeldProjection);

    final double armSpanY = lNorth - (math.max(westWidth, eastWidth) / 2.0 + r / 2.0);
    final int rungsPerArmY = math.max(1, (armSpanY / params.intermediateTargetPitch).round());

    for (int i = 0; i < rungsPerArmY; i++) {
      final double yS = -lSouth + leadIn / 2.0 + (armSpanY * (i + 0.5) / rungsPerArmY);
      rungs.add(
        LadderRungInstance(
          index: idx++,
          stationX: yS,
          center3D: CadPoint3D(0.0, yS, 20.0),
          cutLength: cutLenSouth,
          orientationAngleRad: math.pi / 2.0,
          jointMethod: params.jointMethod,
        ),
      );
      final double yN = lNorth - leadIn / 2.0 - (armSpanY * (i + 0.5) / rungsPerArmY);
      rungs.add(
        LadderRungInstance(
          index: idx++,
          stationX: yN,
          center3D: CadPoint3D(0.0, yN, 20.0),
          cutLength: cutLenNorth,
          orientationAngleRad: math.pi / 2.0,
          jointMethod: params.jointMethod,
        ),
      );
    }

    final cornerRailLength = (2 * leadIn) + (r * math.pi / 2.0);
    final cornerRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'corner_curved',
      name: 'Cross Corner Curved Rail Blank',
      params: params,
      railFlatLength: cornerRailLength,
      railFlatWidth: railFlatWidth,
      stations: [leadIn + (r * math.pi / 4.0)],
      slotDim: params.railSlotDimensions,
      material: material,
    );

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(rungCutLength: cutLenWest, material: material);

    final splicePorts = <CmsPhysicalPort>[
      CmsPhysicalPort(
        id: 'port_1_west',
        index: 1,
        center: CadPoint3D(-lWest, 0.0, params.height / 2.0),
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        width: westWidth,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_2_east',
        index: 2,
        center: CadPoint3D(lEast, 0.0, params.height / 2.0),
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        width: eastWidth,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_3_north',
        index: 3,
        center: CadPoint3D(0.0, lNorth, params.height / 2.0),
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        width: northWidth,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_4_south',
        index: 4,
        center: CadPoint3D(0.0, -lSouth, params.height / 2.0),
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        width: southWidth,
        height: params.height,
      ),
    ];

    final mesh3D = _buildCrossMesh(
      westWidth: westWidth,
      eastWidth: eastWidth,
      northWidth: northWidth,
      southWidth: southWidth,
      radius: r,
      leadIn: leadIn,
      params: params,
    );

    final int totalRungCount = rungs.length;
    final double totalAreaM2 =
        4 * (cornerRailLength / 1000.0) * (railFlatWidth / 1000.0) + (totalRungCount * (cutLenWest / 1000.0) * (rungBlankWidth / 1000.0));
    final double totalWeightKg = totalAreaM2 * (params.thickness / 1000.0) * densitySteel;

    final bom = LadderHardwareBOM(
      rungCount: totalRungCount,
      passThroughSlotCount: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 2 * totalRungCount : 0,
      weldJointCount: 2 * totalRungCount,
      totalWeldLengthMm: 2 * totalRungCount * (params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 120.0 : 80.0),
      spliceCouplerCount: 4,
      couplerBoltCount: 16,
      couplerNutCount: 16,
      couplerWasherCount: 16,
      totalSteelWeightKg: double.parse(totalWeightKg.toStringAsFixed(2)),
    );

    final stylePrefix = params.accessoryStyle == LadderAccessoryStyle.segmented ? 'Segmented ' : '';
    final bool isUnequal = (westWidth - eastWidth).abs() > 0.1 || (westWidth - northWidth).abs() > 0.1 || (northWidth - southWidth).abs() > 0.1;
    final String typeName = isUnequal ? 'Unequal Cross' : 'Equal Cross';
    final String dims = isUnequal
        ? '${westWidth.round()}×${eastWidth.round()}×${northWidth.round()}×${southWidth.round()}×${params.height.round()}mm'
        : '${westWidth.round()}×${northWidth.round()}×${params.height.round()}mm';
    return DsfLadderAssembly(
      id: 'LAD-${isUnequal ? "UNEQUAL" : "EQUAL"}-CROSS-${params.accessoryStyle.name.toUpperCase()}-${westWidth.round()}X${eastWidth.round()}X${northWidth.round()}X${southWidth.round()}X${params.height.round()}',
      productName: 'Cable Ladder $stylePrefix$typeName $dims (R=${radiusMm.round()}mm)',
      parameters: params,
      leftRailBlank: cornerRailPart,
      rightRailBlank: cornerRailPart,
      rungBlank: rungPart,
      rungs: rungs,
      joints: joints,
      splicePorts: splicePorts,
      assembledMesh3D: mesh3D,
      hardwareBOM: bom,
    );
  }

  static DsfLadderAssembly generateCross({
    required double mainWidth,
    required double branchWidth,
    double? eastWidth,
    double? southWidth,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) => generateUnequalCross(
    westWidth: mainWidth,
    eastWidth: eastWidth ?? mainWidth,
    northWidth: branchWidth,
    southWidth: southWidth ?? branchWidth,
    radiusMm: radiusMm,
    params: params,
  );

  // ===========================================================================
  // 3D MESH BUILDERS FOR ACCESSORIES
  // ===========================================================================

  static FoldedMeshResult _buildHorizontalBendMesh({
    required double angleRad,
    required double rIn,
    required double rOut,
    required double leadIn,
    required List<LadderRungInstance> rungs,
    required List<LadderJointInstance> joints,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final thicknessPolygons = <CadFoldedPolygon3D>[];
    final double H = params.height;
    final double F = params.flangeWidth > 0 ? params.flangeWidth : 32.0;
    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented ? ((angleRad >= 1.3) ? 4 : ((angleRad >= 0.6) ? 3 : 2)) : 16;

    final double fSign = params.flangeDirection == LadderFlangeDirection.inside ? 1.0 : -1.0;
    final double rInF = rIn + (fSign * F);
    final double rOutF = rOut - (fSign * F);

    // Outlet tangent vector
    final outletT = CadPoint3D(-math.sin(angleRad), math.cos(angleRad), 0.0);

    // Miter points and flange miter points
    final mIn = <CadPoint3D>[];
    final mOut = <CadPoint3D>[];
    final mInF = <CadPoint3D>[];
    final mOutF = <CadPoint3D>[];

    final pInletIn = CadPoint3D(rIn, -leadIn, 0.0);
    final pInletOut = CadPoint3D(rOut, -leadIn, 0.0);
    final pInletInF = CadPoint3D(rInF, -leadIn, 0.0);
    final pInletOutF = CadPoint3D(rOutF, -leadIn, 0.0);

    final pOutletIn = CadPoint3D((rIn * math.cos(angleRad)) + (outletT.x * leadIn), (rIn * math.sin(angleRad)) + (outletT.y * leadIn), 0.0);
    final pOutletOut = CadPoint3D((rOut * math.cos(angleRad)) + (outletT.x * leadIn), (rOut * math.sin(angleRad)) + (outletT.y * leadIn), 0.0);
    final pOutletInF = CadPoint3D((rInF * math.cos(angleRad)) + (outletT.x * leadIn), (rInF * math.sin(angleRad)) + (outletT.y * leadIn), 0.0);
    final pOutletOutF = CadPoint3D((rOutF * math.cos(angleRad)) + (outletT.x * leadIn), (rOutF * math.sin(angleRad)) + (outletT.y * leadIn), 0.0);

    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;
    final bool notchOuter = isSegmented && params.flangeDirection == LadderFlangeDirection.inside;
    final bool notchInner = isSegmented && params.flangeDirection == LadderFlangeDirection.outside;
    final double T = (params.thickness > 0.1 && params.thickness < 10.0) ? params.thickness : 2.0;

    final segList =
        <
          ({
            CadPoint3D pStartIn,
            CadPoint3D pEndIn,
            CadPoint3D pStartInF,
            CadPoint3D pEndInF,
            CadPoint3D pStartOut,
            CadPoint3D pEndOut,
            CadPoint3D pStartOutF,
            CadPoint3D pEndOutF,
            bool hasNotchStart,
            bool hasNotchEnd,
          })
        >[];

    if (isSegmented) {
      final double deltaPhi = angleRad / (segments - 1);
      final double cosHalf = math.cos(deltaPhi / 2.0);
      final double wNotch = F * math.tan(deltaPhi / 2.0);

      for (int k = 0; k < segments - 1; k++) {
        final double psi = (k + 0.5) * deltaPhi;
        final double scaleIn = rIn / cosHalf;
        final double scaleOut = rOut / cosHalf;
        final double scaleInF = rInF / cosHalf;
        final double scaleOutF = rOutF / cosHalf;

        mIn.add(CadPoint3D(scaleIn * math.cos(psi), scaleIn * math.sin(psi), 0.0));
        mOut.add(CadPoint3D(scaleOut * math.cos(psi), scaleOut * math.sin(psi), 0.0));
        mInF.add(CadPoint3D(scaleInF * math.cos(psi), scaleInF * math.sin(psi), 0.0));
        mOutF.add(CadPoint3D(scaleOutF * math.cos(psi), scaleOutF * math.sin(psi), 0.0));
      }

      for (int s = 0; s < segments; s++) {
        final pStartIn = (s == 0) ? pInletIn : mIn[s - 1];
        final pEndIn = (s == segments - 1) ? pOutletIn : mIn[s];

        final pStartOut = (s == 0) ? pInletOut : mOut[s - 1];
        final pEndOut = (s == segments - 1) ? pOutletOut : mOut[s];

        final dIn = CadPoint3D(pEndIn.x - pStartIn.x, pEndIn.y - pStartIn.y, 0.0);
        final lenIn = math.sqrt((dIn.x * dIn.x) + (dIn.y * dIn.y));
        final tIn = lenIn > 1e-6 ? CadPoint3D(dIn.x / lenIn, dIn.y / lenIn, 0.0) : const CadPoint3D(0.0, 1.0, 0.0);
        final nIn = CadPoint3D(tIn.y, -tIn.x, 0.0);

        final dOut = CadPoint3D(pEndOut.x - pStartOut.x, pEndOut.y - pStartOut.y, 0.0);
        final lenOut = math.sqrt((dOut.x * dOut.x) + (dOut.y * dOut.y));
        final tOut = lenOut > 1e-6 ? CadPoint3D(dOut.x / lenOut, dOut.y / lenOut, 0.0) : const CadPoint3D(0.0, 1.0, 0.0);
        final nOut = CadPoint3D(-tOut.y, tOut.x, 0.0);

        CadPoint3D pStartOutF;
        CadPoint3D pEndOutF;
        if (notchOuter) {
          pStartOutF = (s == 0)
              ? pInletOutF
              : CadPoint3D(pStartOut.x + (nOut.x * fSign * F) + (tOut.x * wNotch), pStartOut.y + (nOut.y * fSign * F) + (tOut.y * wNotch), 0.0);
          pEndOutF = (s == segments - 1)
              ? pOutletOutF
              : CadPoint3D(pEndOut.x + (nOut.x * fSign * F) - (tOut.x * wNotch), pEndOut.y + (nOut.y * fSign * F) - (tOut.y * wNotch), 0.0);
        } else {
          pStartOutF = (s == 0) ? pInletOutF : mOutF[s - 1];
          pEndOutF = (s == segments - 1) ? pOutletOutF : mOutF[s];
        }

        CadPoint3D pStartInF;
        CadPoint3D pEndInF;
        if (notchInner) {
          pStartInF = (s == 0)
              ? pInletInF
              : CadPoint3D(pStartIn.x + (nIn.x * fSign * F) + (tIn.x * wNotch), pStartIn.y + (nIn.y * fSign * F) + (tIn.y * wNotch), 0.0);
          pEndInF = (s == segments - 1)
              ? pOutletInF
              : CadPoint3D(pEndIn.x + (nIn.x * fSign * F) - (tIn.x * wNotch), pEndIn.y + (nIn.y * fSign * F) - (tIn.y * wNotch), 0.0);
        } else {
          pStartInF = (s == 0) ? pInletInF : mInF[s - 1];
          pEndInF = (s == segments - 1) ? pOutletInF : mInF[s];
        }

        segList.add((
          pStartIn: pStartIn,
          pEndIn: pEndIn,
          pStartInF: pStartInF,
          pEndInF: pEndInF,
          pStartOut: pStartOut,
          pEndOut: pEndOut,
          pStartOutF: pStartOutF,
          pEndOutF: pEndOutF,
          hasNotchStart: s > 0,
          hasNotchEnd: s < segments - 1,
        ));
      }
    } else {
      // Curved mode
      // 1. Inlet straight collar (if leadIn > 0.01)
      if (leadIn > 0.01) {
        segList.add((
          pStartIn: pInletIn,
          pEndIn: CadPoint3D(rIn, 0.0, 0.0),
          pStartInF: pInletInF,
          pEndInF: CadPoint3D(rInF, 0.0, 0.0),
          pStartOut: pInletOut,
          pEndOut: CadPoint3D(rOut, 0.0, 0.0),
          pStartOutF: pInletOutF,
          pEndOutF: CadPoint3D(rOutF, 0.0, 0.0),
          hasNotchStart: false,
          hasNotchEnd: false,
        ));
      }

      // 2. 16 curved arc segments
      for (int s = 0; s < segments; s++) {
        final double a1 = angleRad * s / segments;
        final double a2 = angleRad * (s + 1) / segments;
        segList.add((
          pStartIn: CadPoint3D(rIn * math.cos(a1), rIn * math.sin(a1), 0.0),
          pEndIn: CadPoint3D(rIn * math.cos(a2), rIn * math.sin(a2), 0.0),
          pStartInF: CadPoint3D(rInF * math.cos(a1), rInF * math.sin(a1), 0.0),
          pEndInF: CadPoint3D(rInF * math.cos(a2), rInF * math.sin(a2), 0.0),
          pStartOut: CadPoint3D(rOut * math.cos(a1), rOut * math.sin(a1), 0.0),
          pEndOut: CadPoint3D(rOut * math.cos(a2), rOut * math.sin(a2), 0.0),
          pStartOutF: CadPoint3D(rOutF * math.cos(a1), rOutF * math.sin(a1), 0.0),
          pEndOutF: CadPoint3D(rOutF * math.cos(a2), rOutF * math.sin(a2), 0.0),
          hasNotchStart: false,
          hasNotchEnd: false,
        ));
      }

      // 3. Outlet straight collar (if leadIn > 0.01)
      if (leadIn > 0.01) {
        segList.add((
          pStartIn: CadPoint3D(rIn * math.cos(angleRad), rIn * math.sin(angleRad), 0.0),
          pEndIn: pOutletIn,
          pStartInF: CadPoint3D(rInF * math.cos(angleRad), rInF * math.sin(angleRad), 0.0),
          pEndInF: pOutletInF,
          pStartOut: CadPoint3D(rOut * math.cos(angleRad), rOut * math.sin(angleRad), 0.0),
          pEndOut: pOutletOut,
          pStartOutF: CadPoint3D(rOutF * math.cos(angleRad), rOutF * math.sin(angleRad), 0.0),
          pEndOutF: pOutletOutF,
          hasNotchStart: false,
          hasNotchEnd: false,
        ));
      }
    }

    for (int s = 0; s < segList.length; s++) {
      final seg = segList[s];
      final pStartIn = seg.pStartIn;
      final pEndIn = seg.pEndIn;
      final pStartInF = seg.pStartInF;
      final pEndInF = seg.pEndInF;

      final pStartOut = seg.pStartOut;
      final pEndOut = seg.pEndOut;
      final pStartOutF = seg.pStartOutF;
      final pEndOutF = seg.pEndOutF;

      // Unit tangents and normals
      final dIn = CadPoint3D(pEndIn.x - pStartIn.x, pEndIn.y - pStartIn.y, 0.0);
      final lenIn = math.sqrt((dIn.x * dIn.x) + (dIn.y * dIn.y));
      final tIn = lenIn > 1e-6 ? CadPoint3D(dIn.x / lenIn, dIn.y / lenIn, 0.0) : const CadPoint3D(0.0, 1.0, 0.0);
      final nIn = CadPoint3D(tIn.y, -tIn.x, 0.0);

      final dOut = CadPoint3D(pEndOut.x - pStartOut.x, pEndOut.y - pStartOut.y, 0.0);
      final lenOut = math.sqrt((dOut.x * dOut.x) + (dOut.y * dOut.y));
      final tOut = lenOut > 1e-6 ? CadPoint3D(dOut.x / lenOut, dOut.y / lenOut, 0.0) : const CadPoint3D(0.0, 1.0, 0.0);
      final nOut = CadPoint3D(-tOut.y, tOut.x, 0.0);

      // Pass-through slot holes on rail web if active (snug 40.0 x 20.0 mm without large gaps)
      final innerWebHoles = <List<CadPoint3D>>[];
      final outerWebHoles = <List<CadPoint3D>>[];
      final innerWebHolesInner = <List<CadPoint3D>>[];
      final outerWebHolesInner = <List<CadPoint3D>>[];

      if (isSegmented && isPassThrough && s < rungs.length) {
        final jInList = joints.where((j) => j.rungIndex == s && j.railSide == 'left');
        final jOutList = joints.where((j) => j.rungIndex == s && j.railSide == 'right');

        if (jInList.isNotEmpty) {
          final jIn = jInList.first;
          // Snug 40.0 x 20.0 mm opening centered on C-channel rung
          innerWebHoles.add([
            CadPoint3D(jIn.weldCenter3D.x - (tIn.x * 20.0), jIn.weldCenter3D.y - (tIn.y * 20.0), 10.0),
            CadPoint3D(jIn.weldCenter3D.x + (tIn.x * 20.0), jIn.weldCenter3D.y + (tIn.y * 20.0), 10.0),
            CadPoint3D(jIn.weldCenter3D.x + (tIn.x * 20.0), jIn.weldCenter3D.y + (tIn.y * 20.0), 30.0),
            CadPoint3D(jIn.weldCenter3D.x - (tIn.x * 20.0), jIn.weldCenter3D.y - (tIn.y * 20.0), 30.0),
          ]);
          innerWebHolesInner.add([
            CadPoint3D(jIn.weldCenter3D.x + (nIn.x * T) - (tIn.x * 20.0), jIn.weldCenter3D.y + (nIn.y * T) - (tIn.y * 20.0), 10.0),
            CadPoint3D(jIn.weldCenter3D.x + (nIn.x * T) + (tIn.x * 20.0), jIn.weldCenter3D.y + (nIn.y * T) + (tIn.y * 20.0), 10.0),
            CadPoint3D(jIn.weldCenter3D.x + (nIn.x * T) + (tIn.x * 20.0), jIn.weldCenter3D.y + (nIn.y * T) + (tIn.y * 20.0), 30.0),
            CadPoint3D(jIn.weldCenter3D.x + (nIn.x * T) - (tIn.x * 20.0), jIn.weldCenter3D.y + (nIn.y * T) - (tIn.y * 20.0), 30.0),
          ]);
        }

        if (jOutList.isNotEmpty) {
          final jOut = jOutList.first;
          outerWebHoles.add([
            CadPoint3D(jOut.weldCenter3D.x - (tOut.x * 20.0), jOut.weldCenter3D.y - (tOut.y * 20.0), 10.0),
            CadPoint3D(jOut.weldCenter3D.x + (tOut.x * 20.0), jOut.weldCenter3D.y + (tOut.y * 20.0), 10.0),
            CadPoint3D(jOut.weldCenter3D.x + (tOut.x * 20.0), jOut.weldCenter3D.y + (tOut.y * 20.0), 30.0),
            CadPoint3D(jOut.weldCenter3D.x - (tOut.x * 20.0), jOut.weldCenter3D.y - (tOut.y * 20.0), 30.0),
          ]);
          outerWebHolesInner.add([
            CadPoint3D(jOut.weldCenter3D.x + (nOut.x * T) - (tOut.x * 20.0), jOut.weldCenter3D.y + (nOut.y * T) - (tOut.y * 20.0), 10.0),
            CadPoint3D(jOut.weldCenter3D.x + (nOut.x * T) + (tOut.x * 20.0), jOut.weldCenter3D.y + (nOut.y * T) + (tOut.y * 20.0), 10.0),
            CadPoint3D(jOut.weldCenter3D.x + (nOut.x * T) + (tOut.x * 20.0), jOut.weldCenter3D.y + (nOut.y * T) + (tOut.y * 20.0), 30.0),
            CadPoint3D(jOut.weldCenter3D.x + (nOut.x * T) - (tOut.x * 20.0), jOut.weldCenter3D.y + (nOut.y * T) - (tOut.y * 20.0), 30.0),
          ]);
        }
      }

      // Inner web offset points
      final pStartInInner = CadPoint3D(pStartIn.x + (nIn.x * T), pStartIn.y + (nIn.y * T), 0.0);
      final pEndInInner = CadPoint3D(pEndIn.x + (nIn.x * T), pEndIn.y + (nIn.y * T), 0.0);

      final pStartOutInner = CadPoint3D(pStartOut.x + (nOut.x * T), pStartOut.y + (nOut.y * T), 0.0);
      final pEndOutInner = CadPoint3D(pEndOut.x + (nOut.x * T), pEndOut.y + (nOut.y * T), 0.0);

      // --- 1. INNER RAIL SEGMENT (Thick C-Channel) ---
      // Outer Web
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'inner_rail_web_$s',
          vertices: [
            CadPoint3D(pStartIn.x, pStartIn.y, 0.0),
            CadPoint3D(pEndIn.x, pEndIn.y, 0.0),
            CadPoint3D(pEndIn.x, pEndIn.y, H),
            CadPoint3D(pStartIn.x, pStartIn.y, H),
          ],
          normal: nIn,
          color: railColor,
          holes: innerWebHoles,
        ),
      );
      // Outer Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'inner_rail_bottom_flange_$s',
          vertices: [
            CadPoint3D(pStartIn.x, pStartIn.y, 0.0),
            CadPoint3D(pStartInF.x, pStartInF.y, 0.0),
            CadPoint3D(pEndInF.x, pEndInF.y, 0.0),
            CadPoint3D(pEndIn.x, pEndIn.y, 0.0),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: railColor,
        ),
      );
      // Outer Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'inner_rail_top_flange_$s',
          vertices: [
            CadPoint3D(pStartIn.x, pStartIn.y, H),
            CadPoint3D(pEndIn.x, pEndIn.y, H),
            CadPoint3D(pEndInF.x, pEndInF.y, H),
            CadPoint3D(pStartInF.x, pStartInF.y, H),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: railColor,
        ),
      );

      // Inner Web
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'inner_rail_web_inner_$s',
          vertices: [
            CadPoint3D(pStartInInner.x, pStartInInner.y, T),
            CadPoint3D(pStartInInner.x, pStartInInner.y, H - T),
            CadPoint3D(pEndInInner.x, pEndInInner.y, H - T),
            CadPoint3D(pEndInInner.x, pEndInInner.y, T),
          ],
          normal: CadPoint3D(-nIn.x, -nIn.y, 0.0),
          color: railColor,
          holes: innerWebHolesInner,
        ),
      );
      // Inner Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'inner_rail_bottom_flange_inner_$s',
          vertices: [
            CadPoint3D(pStartInInner.x, pStartInInner.y, T),
            CadPoint3D(pEndInInner.x, pEndInInner.y, T),
            CadPoint3D(pEndInF.x, pEndInF.y, T),
            CadPoint3D(pStartInF.x, pStartInF.y, T),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: railColor,
        ),
      );
      // Inner Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'inner_rail_top_flange_inner_$s',
          vertices: [
            CadPoint3D(pStartInInner.x, pStartInInner.y, H - T),
            CadPoint3D(pStartInF.x, pStartInF.y, H - T),
            CadPoint3D(pEndInF.x, pEndInF.y, H - T),
            CadPoint3D(pEndInInner.x, pEndInInner.y, H - T),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: railColor,
        ),
      );

      // Flange Lips (Rims)
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_inner_top_flange_lip_$s',
          vertices: [
            CadPoint3D(pStartInF.x, pStartInF.y, H - T),
            CadPoint3D(pEndInF.x, pEndInF.y, H - T),
            CadPoint3D(pEndInF.x, pEndInF.y, H),
            CadPoint3D(pStartInF.x, pStartInF.y, H),
          ],
          normal: CadPoint3D(nIn.x * fSign, nIn.y * fSign, 0.0),
          color: railColor,
        ),
      );
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_inner_bottom_flange_lip_$s',
          vertices: [
            CadPoint3D(pStartInF.x, pStartInF.y, 0.0),
            CadPoint3D(pStartInF.x, pStartInF.y, T),
            CadPoint3D(pEndInF.x, pEndInF.y, T),
            CadPoint3D(pEndInF.x, pEndInF.y, 0.0),
          ],
          normal: CadPoint3D(nIn.x * fSign, nIn.y * fSign, 0.0),
          color: railColor,
        ),
      );

      // V-Notch Rims on Inner Rail if notchInner
      if (notchInner) {
        if (seg.hasNotchStart) {
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_inner_top_notch_start_$s',
              vertices: [
                CadPoint3D(pStartIn.x, pStartIn.y, H),
                CadPoint3D(pStartInF.x, pStartInF.y, H),
                CadPoint3D(pStartInF.x, pStartInF.y, H - T),
                CadPoint3D(pStartIn.x, pStartIn.y, H - T),
              ],
              normal: CadPoint3D(-tIn.x, -tIn.y, 0.0),
              color: railColor,
            ),
          );
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_inner_bottom_notch_start_$s',
              vertices: [
                CadPoint3D(pStartIn.x, pStartIn.y, 0.0),
                CadPoint3D(pStartIn.x, pStartIn.y, T),
                CadPoint3D(pStartInF.x, pStartInF.y, T),
                CadPoint3D(pStartInF.x, pStartInF.y, 0.0),
              ],
              normal: CadPoint3D(-tIn.x, -tIn.y, 0.0),
              color: railColor,
            ),
          );
        }
        if (seg.hasNotchEnd) {
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_inner_top_notch_end_$s',
              vertices: [
                CadPoint3D(pEndIn.x, pEndIn.y, H - T),
                CadPoint3D(pEndInF.x, pEndInF.y, H - T),
                CadPoint3D(pEndInF.x, pEndInF.y, H),
                CadPoint3D(pEndIn.x, pEndIn.y, H),
              ],
              normal: tIn,
              color: railColor,
            ),
          );
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_inner_bottom_notch_end_$s',
              vertices: [
                CadPoint3D(pEndIn.x, pEndIn.y, T),
                CadPoint3D(pEndIn.x, pEndIn.y, 0.0),
                CadPoint3D(pEndInF.x, pEndInF.y, 0.0),
                CadPoint3D(pEndInF.x, pEndInF.y, T),
              ],
              normal: tIn,
              color: railColor,
            ),
          );
        }
      }

      // --- 2. OUTER RAIL SEGMENT (Thick C-Channel) ---
      // Outer Web
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'outer_rail_web_$s',
          vertices: [
            CadPoint3D(pStartOut.x, pStartOut.y, 0.0),
            CadPoint3D(pStartOut.x, pStartOut.y, H),
            CadPoint3D(pEndOut.x, pEndOut.y, H),
            CadPoint3D(pEndOut.x, pEndOut.y, 0.0),
          ],
          normal: nOut,
          color: railColor,
          holes: outerWebHoles,
        ),
      );
      // Outer Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'outer_rail_bottom_flange_$s',
          vertices: [
            CadPoint3D(pStartOut.x, pStartOut.y, 0.0),
            CadPoint3D(pEndOut.x, pEndOut.y, 0.0),
            CadPoint3D(pEndOutF.x, pEndOutF.y, 0.0),
            CadPoint3D(pStartOutF.x, pStartOutF.y, 0.0),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: railColor,
        ),
      );
      // Outer Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'outer_rail_top_flange_$s',
          vertices: [
            CadPoint3D(pStartOut.x, pStartOut.y, H),
            CadPoint3D(pStartOutF.x, pStartOutF.y, H),
            CadPoint3D(pEndOutF.x, pEndOutF.y, H),
            CadPoint3D(pEndOut.x, pEndOut.y, H),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: railColor,
        ),
      );

      // Inner Web
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'outer_rail_web_inner_$s',
          vertices: [
            CadPoint3D(pStartOutInner.x, pStartOutInner.y, T),
            CadPoint3D(pEndOutInner.x, pEndOutInner.y, T),
            CadPoint3D(pEndOutInner.x, pEndOutInner.y, H - T),
            CadPoint3D(pStartOutInner.x, pStartOutInner.y, H - T),
          ],
          normal: CadPoint3D(-nOut.x, -nOut.y, 0.0),
          color: railColor,
          holes: outerWebHolesInner,
        ),
      );
      // Inner Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'outer_rail_bottom_flange_inner_$s',
          vertices: [
            CadPoint3D(pStartOutInner.x, pStartOutInner.y, T),
            CadPoint3D(pStartOutF.x, pStartOutF.y, T),
            CadPoint3D(pEndOutF.x, pEndOutF.y, T),
            CadPoint3D(pEndOutInner.x, pEndOutInner.y, T),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: railColor,
        ),
      );
      // Inner Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'outer_rail_top_flange_inner_$s',
          vertices: [
            CadPoint3D(pStartOutInner.x, pStartOutInner.y, H - T),
            CadPoint3D(pEndOutInner.x, pEndOutInner.y, H - T),
            CadPoint3D(pEndOutF.x, pEndOutF.y, H - T),
            CadPoint3D(pStartOutF.x, pStartOutF.y, H - T),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: railColor,
        ),
      );

      // Flange Lips (Rims)
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_outer_top_flange_lip_$s',
          vertices: [
            CadPoint3D(pStartOutF.x, pStartOutF.y, H - T),
            CadPoint3D(pStartOutF.x, pStartOutF.y, H),
            CadPoint3D(pEndOutF.x, pEndOutF.y, H),
            CadPoint3D(pEndOutF.x, pEndOutF.y, H - T),
          ],
          normal: CadPoint3D(nOut.x * fSign, nOut.y * fSign, 0.0),
          color: railColor,
        ),
      );
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_outer_bottom_flange_lip_$s',
          vertices: [
            CadPoint3D(pStartOutF.x, pStartOutF.y, 0.0),
            CadPoint3D(pEndOutF.x, pEndOutF.y, 0.0),
            CadPoint3D(pEndOutF.x, pEndOutF.y, T),
            CadPoint3D(pStartOutF.x, pStartOutF.y, T),
          ],
          normal: CadPoint3D(nOut.x * fSign, nOut.y * fSign, 0.0),
          color: railColor,
        ),
      );

      // V-Notch Rims on Outer Rail if notchOuter
      if (notchOuter) {
        if (seg.hasNotchStart) {
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_outer_top_notch_start_$s',
              vertices: [
                CadPoint3D(pStartOut.x, pStartOut.y, H - T),
                CadPoint3D(pStartOutF.x, pStartOutF.y, H - T),
                CadPoint3D(pStartOutF.x, pStartOutF.y, H),
                CadPoint3D(pStartOut.x, pStartOut.y, H),
              ],
              normal: CadPoint3D(-tOut.x, -tOut.y, 0.0),
              color: railColor,
            ),
          );
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_outer_bottom_notch_start_$s',
              vertices: [
                CadPoint3D(pStartOut.x, pStartOut.y, 0.0),
                CadPoint3D(pStartOutF.x, pStartOutF.y, 0.0),
                CadPoint3D(pStartOutF.x, pStartOutF.y, T),
                CadPoint3D(pStartOut.x, pStartOut.y, T),
              ],
              normal: CadPoint3D(-tOut.x, -tOut.y, 0.0),
              color: railColor,
            ),
          );
        }
        if (seg.hasNotchEnd) {
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_outer_top_notch_end_$s',
              vertices: [
                CadPoint3D(pEndOut.x, pEndOut.y, H),
                CadPoint3D(pEndOutF.x, pEndOutF.y, H),
                CadPoint3D(pEndOutF.x, pEndOutF.y, H - T),
                CadPoint3D(pEndOut.x, pEndOut.y, H - T),
              ],
              normal: tOut,
              color: railColor,
            ),
          );
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_outer_bottom_notch_end_$s',
              vertices: [
                CadPoint3D(pEndOut.x, pEndOut.y, T),
                CadPoint3D(pEndOutF.x, pEndOutF.y, T),
                CadPoint3D(pEndOutF.x, pEndOutF.y, 0.0),
                CadPoint3D(pEndOut.x, pEndOut.y, 0.0),
              ],
              normal: tOut,
              color: railColor,
            ),
          );
        }
      }
    }

    // --- 3. OPEN PORT RIMS (Physical 2mm Metal Wall Profile - NO Solid End Caps) ---
    // Port 1 (Inlet, normal [0, -1, 0])
    final pInletInInner = CadPoint3D(pInletIn.x + (1.0 * T), pInletIn.y, 0.0);
    final pInletOutInner = CadPoint3D(pInletOut.x - (1.0 * T), pInletOut.y, 0.0);

    thicknessPolygons.addAll([
      // Inner Rail Port 1 Profile Rim
      CadFoldedPolygon3D(
        faceId: 'RIM_inner_port1_web',
        vertices: [
          CadPoint3D(pInletIn.x, pInletIn.y, 0.0),
          CadPoint3D(pInletIn.x, pInletIn.y, H),
          CadPoint3D(pInletInInner.x, pInletInInner.y, H),
          CadPoint3D(pInletInInner.x, pInletInInner.y, 0.0),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_inner_port1_top_flange',
        vertices: [
          CadPoint3D(pInletIn.x, pInletIn.y, H),
          CadPoint3D(pInletInF.x, pInletInF.y, H),
          CadPoint3D(pInletInF.x, pInletInF.y, H - T),
          CadPoint3D(pInletInInner.x, pInletInInner.y, H - T),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_inner_port1_bottom_flange',
        vertices: [
          CadPoint3D(pInletIn.x, pInletIn.y, 0.0),
          CadPoint3D(pInletInInner.x, pInletInInner.y, T),
          CadPoint3D(pInletInF.x, pInletInF.y, T),
          CadPoint3D(pInletInF.x, pInletInF.y, 0.0),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: railColor,
      ),

      // Outer Rail Port 1 Profile Rim
      CadFoldedPolygon3D(
        faceId: 'RIM_outer_port1_web',
        vertices: [
          CadPoint3D(pInletOut.x, pInletOut.y, 0.0),
          CadPoint3D(pInletOutInner.x, pInletOutInner.y, 0.0),
          CadPoint3D(pInletOutInner.x, pInletOutInner.y, H),
          CadPoint3D(pInletOut.x, pInletOut.y, H),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_outer_port1_top_flange',
        vertices: [
          CadPoint3D(pInletOut.x, pInletOut.y, H),
          CadPoint3D(pInletOutInner.x, pInletOutInner.y, H - T),
          CadPoint3D(pInletOutF.x, pInletOutF.y, H - T),
          CadPoint3D(pInletOutF.x, pInletOutF.y, H),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_outer_port1_bottom_flange',
        vertices: [
          CadPoint3D(pInletOut.x, pInletOut.y, 0.0),
          CadPoint3D(pInletOutF.x, pInletOutF.y, 0.0),
          CadPoint3D(pInletOutF.x, pInletOutF.y, T),
          CadPoint3D(pInletOutInner.x, pInletOutInner.y, T),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: railColor,
      ),

      // Port 2 (Outlet, normal outletT)
      // Inner Rail Port 2 Profile Rim
      CadFoldedPolygon3D(
        faceId: 'RIM_inner_port2_web',
        vertices: [
          CadPoint3D(pOutletIn.x, pOutletIn.y, 0.0),
          CadPoint3D(pOutletIn.x + (math.cos(angleRad) * T), pOutletIn.y + (math.sin(angleRad) * T), 0.0),
          CadPoint3D(pOutletIn.x + (math.cos(angleRad) * T), pOutletIn.y + (math.sin(angleRad) * T), H),
          CadPoint3D(pOutletIn.x, pOutletIn.y, H),
        ],
        normal: outletT,
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_inner_port2_top_flange',
        vertices: [
          CadPoint3D(pOutletIn.x, pOutletIn.y, H),
          CadPoint3D(pOutletIn.x + (math.cos(angleRad) * T), pOutletIn.y + (math.sin(angleRad) * T), H - T),
          CadPoint3D(pOutletInF.x, pOutletInF.y, H - T),
          CadPoint3D(pOutletInF.x, pOutletInF.y, H),
        ],
        normal: outletT,
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_inner_port2_bottom_flange',
        vertices: [
          CadPoint3D(pOutletIn.x, pOutletIn.y, 0.0),
          CadPoint3D(pOutletInF.x, pOutletInF.y, 0.0),
          CadPoint3D(pOutletInF.x, pOutletInF.y, T),
          CadPoint3D(pOutletIn.x + (math.cos(angleRad) * T), pOutletIn.y + (math.sin(angleRad) * T), T),
        ],
        normal: outletT,
        color: railColor,
      ),

      // Outer Rail Port 2 Profile Rim
      CadFoldedPolygon3D(
        faceId: 'RIM_outer_port2_web',
        vertices: [
          CadPoint3D(pOutletOut.x, pOutletOut.y, 0.0),
          CadPoint3D(pOutletOut.x, pOutletOut.y, H),
          CadPoint3D(pOutletOut.x - (math.cos(angleRad) * T), pOutletOut.y - (math.sin(angleRad) * T), H),
          CadPoint3D(pOutletOut.x - (math.cos(angleRad) * T), pOutletOut.y - (math.sin(angleRad) * T), 0.0),
        ],
        normal: outletT,
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_outer_port2_top_flange',
        vertices: [
          CadPoint3D(pOutletOut.x, pOutletOut.y, H),
          CadPoint3D(pOutletOutF.x, pOutletOutF.y, H),
          CadPoint3D(pOutletOutF.x, pOutletOutF.y, H - T),
          CadPoint3D(pOutletOut.x - (math.cos(angleRad) * T), pOutletOut.y - (math.sin(angleRad) * T), H - T),
        ],
        normal: outletT,
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_outer_port2_bottom_flange',
        vertices: [
          CadPoint3D(pOutletOut.x, pOutletOut.y, 0.0),
          CadPoint3D(pOutletOut.x - (math.cos(angleRad) * T), pOutletOut.y - (math.sin(angleRad) * T), 0.0),
          CadPoint3D(pOutletOut.x - (math.cos(angleRad) * T), pOutletOut.y - (math.sin(angleRad) * T), T),
          CadPoint3D(pOutletOutF.x, pOutletOutF.y, T),
        ],
        normal: outletT,
        color: railColor,
      ),
    ]);

    // --- 4. ORIENTED RUNGS ---
    for (int i = 0; i < rungs.length; i++) {
      final rung = rungs[i];
      final double alpha = rung.orientationAngleRad;
      final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
        rungId: 'bend_rung_$i',
        centerTop: CadPoint3D(rung.center3D.x, rung.center3D.y, rung.center3D.z + 10.0),
        lengthDir: CadPoint3D(math.cos(alpha), math.sin(alpha), 0.0),
        widthDir: CadPoint3D(-math.sin(alpha), math.cos(alpha), 0.0),
        upDir: const CadPoint3D(0.0, 0.0, 1.0),
        interiorHalfSpan: (rOut - rIn) / 2.0,
        rungW: 40.0,
        rungDepth: 20.0,
        thickness: params.thickness,
        color: rungColor,
        isPassThrough: isPassThrough,
        outsideProjection: params.outsideWeldProjection,
      );
      polygons.addAll(rungPolys);
    }

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: rOut + leadIn + F,
      boundLength: rOut + leadIn + F,
      boundHeight: H,
      center: CadPoint3D((rIn + rOut) / 4.0, (rIn + rOut) / 4.0, H / 2.0),
    );
  }

  static FoldedMeshResult _buildRiserMesh({
    required double angleRad,
    required double radius,
    required double leadIn,
    required bool isInsideRiser,
    required List<LadderRungInstance> rungs,
    required List<LadderJointInstance> joints,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final thicknessPolygons = <CadFoldedPolygon3D>[];
    final double halfW = params.width / 2.0;
    final double H = params.height;
    final double F = params.flangeWidth > 0 ? params.flangeWidth : 32.0;
    final double fSign = params.flangeDirection == LadderFlangeDirection.inside ? 1.0 : -1.0;
    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented ? ((angleRad >= 1.3) ? 4 : ((angleRad >= 0.6) ? 3 : 2)) : 16;

    final tExit = CadPoint3D(math.cos(angleRad), 0.0, isInsideRiser ? math.sin(angleRad) : -math.sin(angleRad));
    final uExit = CadPoint3D(isInsideRiser ? -math.sin(angleRad) : math.sin(angleRad), 0.0, math.cos(angleRad));

    final mBottom = <CadPoint3D>[];
    final mTop = <CadPoint3D>[];

    final pInletBottom = CadPoint3D(-leadIn, 0.0, 0.0);
    final pInletTop = CadPoint3D(-leadIn, 0.0, H);

    final pCircBottom = CadPoint3D(
      radius * math.sin(angleRad),
      0.0,
      isInsideRiser ? radius * (1.0 - math.cos(angleRad)) : -radius * (1.0 - math.cos(angleRad)),
    );
    final pOutletBottom = CadPoint3D(pCircBottom.x + (tExit.x * leadIn), 0.0, pCircBottom.z + (tExit.z * leadIn));
    final pOutletTop = CadPoint3D(pOutletBottom.x + (uExit.x * H), 0.0, pOutletBottom.z + (uExit.z * H));

    if (isSegmented) {
      final double deltaPhi = angleRad / (segments - 1);
      final double cosHalf = math.cos(deltaPhi / 2.0);

      for (int k = 0; k < segments - 1; k++) {
        final double psi = (k + 0.5) * deltaPhi;
        final double rScale = radius / cosHalf;
        final double hScale = H / cosHalf;

        final double bx = rScale * math.sin(psi);
        final double bz = isInsideRiser ? (radius - (rScale * math.cos(psi))) : (-radius + (rScale * math.cos(psi)));
        mBottom.add(CadPoint3D(bx, 0.0, bz));

        final double nx = isInsideRiser ? -math.sin(psi) : math.sin(psi);
        final double nz = math.cos(psi);
        mTop.add(CadPoint3D(bx + (nx * hScale), 0.0, bz + (nz * hScale)));
      }
    }

    final riserSegList = <({CadPoint3D pbStart, CadPoint3D pbEnd, CadPoint3D ptStart, CadPoint3D ptEnd})>[];

    if (isSegmented) {
      for (int s = 0; s < segments; s++) {
        final pbStart = (s == 0) ? pInletBottom : mBottom[s - 1];
        final pbEnd = (s == segments - 1) ? pOutletBottom : mBottom[s];
        final ptStart = (s == 0) ? pInletTop : mTop[s - 1];
        final ptEnd = (s == segments - 1) ? pOutletTop : mTop[s];
        riserSegList.add((pbStart: pbStart, pbEnd: pbEnd, ptStart: ptStart, ptEnd: ptEnd));
      }
    } else {
      // Curved mode: include inlet collar, arc segments, and outlet collar
      if (leadIn > 0.01) {
        riserSegList.add((pbStart: pInletBottom, pbEnd: const CadPoint3D(0.0, 0.0, 0.0), ptStart: pInletTop, ptEnd: CadPoint3D(0.0, 0.0, H)));
      }
      for (int s = 0; s < segments; s++) {
        final double a1 = angleRad * s / segments;
        final double a2 = angleRad * (s + 1) / segments;
        final pbStart = CadPoint3D(radius * math.sin(a1), 0.0, isInsideRiser ? radius * (1.0 - math.cos(a1)) : -radius * (1.0 - math.cos(a1)));
        final pbEnd = CadPoint3D(radius * math.sin(a2), 0.0, isInsideRiser ? radius * (1.0 - math.cos(a2)) : -radius * (1.0 - math.cos(a2)));
        final u1 = CadPoint3D(isInsideRiser ? -math.sin(a1) : math.sin(a1), 0.0, math.cos(a1));
        final u2 = CadPoint3D(isInsideRiser ? -math.sin(a2) : math.sin(a2), 0.0, math.cos(a2));
        final ptStart = CadPoint3D(pbStart.x + (u1.x * H), 0.0, pbStart.z + (u1.z * H));
        final ptEnd = CadPoint3D(pbEnd.x + (u2.x * H), 0.0, pbEnd.z + (u2.z * H));
        riserSegList.add((pbStart: pbStart, pbEnd: pbEnd, ptStart: ptStart, ptEnd: ptEnd));
      }
      if (leadIn > 0.01) {
        final uExitFinal = CadPoint3D(isInsideRiser ? -math.sin(angleRad) : math.sin(angleRad), 0.0, math.cos(angleRad));
        final ptCircTop = CadPoint3D(pCircBottom.x + (uExitFinal.x * H), 0.0, pCircBottom.z + (uExitFinal.z * H));
        riserSegList.add((pbStart: pCircBottom, pbEnd: pOutletBottom, ptStart: ptCircTop, ptEnd: pOutletTop));
      }
    }

    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;

    for (int s = 0; s < riserSegList.length; s++) {
      final pbStart = riserSegList[s].pbStart;
      final pbEnd = riserSegList[s].pbEnd;
      final ptStart = riserSegList[s].ptStart;
      final ptEnd = riserSegList[s].ptEnd;

      // Unit tangent along rail and normal along web height
      final dSeg = CadPoint3D(pbEnd.x - pbStart.x, 0.0, pbEnd.z - pbStart.z);
      final lenSeg = math.sqrt((dSeg.x * dSeg.x) + (dSeg.z * dSeg.z));
      final tSeg = lenSeg > 1e-6 ? CadPoint3D(dSeg.x / lenSeg, 0.0, dSeg.z / lenSeg) : const CadPoint3D(1.0, 0.0, 0.0);

      final pbMid = CadPoint3D((pbStart.x + pbEnd.x) / 2.0, 0.0, (pbStart.z + pbEnd.z) / 2.0);
      final ptMid = CadPoint3D((ptStart.x + ptEnd.x) / 2.0, 0.0, (ptStart.z + ptEnd.z) / 2.0);
      final uDiff = CadPoint3D(ptMid.x - pbMid.x, 0.0, ptMid.z - pbMid.z);
      final uLen = math.sqrt((uDiff.x * uDiff.x) + (uDiff.z * uDiff.z));
      final uSeg = uLen > 1e-6 ? CadPoint3D(uDiff.x / uLen, 0.0, uDiff.z / uLen) : const CadPoint3D(0.0, 0.0, 1.0);

      final double T = (params.thickness > 0.1 && params.thickness < 10.0) ? params.thickness : 2.0;
      final leftWebHoles = <List<CadPoint3D>>[];
      final rightWebHoles = <List<CadPoint3D>>[];
      final leftWebHolesInner = <List<CadPoint3D>>[];
      final rightWebHolesInner = <List<CadPoint3D>>[];

      if (isSegmented && isPassThrough && s < rungs.length) {
        final rung = rungs[s];
        final rx = rung.center3D.x;
        final rz = rung.center3D.z;

        // Snug 40.0 x 20.0 mm cutout centered on rung
        leftWebHoles.add([
          CadPoint3D(rx - (tSeg.x * 20.0) - (uSeg.x * 10.0), -halfW, rz - (tSeg.z * 20.0) - (uSeg.z * 10.0)),
          CadPoint3D(rx + (tSeg.x * 20.0) - (uSeg.x * 10.0), -halfW, rz + (tSeg.z * 20.0) - (uSeg.z * 10.0)),
          CadPoint3D(rx + (tSeg.x * 20.0) + (uSeg.x * 10.0), -halfW, rz + (tSeg.z * 20.0) + (uSeg.z * 10.0)),
          CadPoint3D(rx - (tSeg.x * 20.0) + (uSeg.x * 10.0), -halfW, rz - (tSeg.z * 20.0) + (uSeg.z * 10.0)),
        ]);
        leftWebHolesInner.add([
          CadPoint3D(rx - (tSeg.x * 20.0) - (uSeg.x * 10.0), -halfW + T, rz - (tSeg.z * 20.0) - (uSeg.z * 10.0)),
          CadPoint3D(rx + (tSeg.x * 20.0) - (uSeg.x * 10.0), -halfW + T, rz + (tSeg.z * 20.0) - (uSeg.z * 10.0)),
          CadPoint3D(rx + (tSeg.x * 20.0) + (uSeg.x * 10.0), -halfW + T, rz + (tSeg.z * 20.0) + (uSeg.z * 10.0)),
          CadPoint3D(rx - (tSeg.x * 20.0) + (uSeg.x * 10.0), -halfW + T, rz - (tSeg.z * 20.0) + (uSeg.z * 10.0)),
        ]);

        rightWebHoles.add([
          CadPoint3D(rx - (tSeg.x * 20.0) - (uSeg.x * 10.0), halfW, rz - (tSeg.z * 20.0) - (uSeg.z * 10.0)),
          CadPoint3D(rx + (tSeg.x * 20.0) - (uSeg.x * 10.0), halfW, rz + (tSeg.z * 20.0) - (uSeg.z * 10.0)),
          CadPoint3D(rx + (tSeg.x * 20.0) + (uSeg.x * 10.0), halfW, rz + (tSeg.z * 20.0) + (uSeg.z * 10.0)),
          CadPoint3D(rx - (tSeg.x * 20.0) + (uSeg.x * 10.0), halfW, rz - (tSeg.z * 20.0) + (uSeg.z * 10.0)),
        ]);
        rightWebHolesInner.add([
          CadPoint3D(rx - (tSeg.x * 20.0) - (uSeg.x * 10.0), halfW - T, rz - (tSeg.z * 20.0) - (uSeg.z * 10.0)),
          CadPoint3D(rx + (tSeg.x * 20.0) - (uSeg.x * 10.0), halfW - T, rz + (tSeg.z * 20.0) - (uSeg.z * 10.0)),
          CadPoint3D(rx + (tSeg.x * 20.0) + (uSeg.x * 10.0), halfW - T, rz + (tSeg.z * 20.0) + (uSeg.z * 10.0)),
          CadPoint3D(rx - (tSeg.x * 20.0) + (uSeg.x * 10.0), halfW - T, rz - (tSeg.z * 20.0) + (uSeg.z * 10.0)),
        ]);
      }

      final double yLf = -halfW + (fSign * F);
      final double yRf = halfW - (fSign * F);

      // --- LEFT RAIL (Y = -halfW, Inward = +Y) ---
      // Outer Web
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_web_l_$s',
          vertices: [
            CadPoint3D(pbStart.x, -halfW, pbStart.z),
            CadPoint3D(pbEnd.x, -halfW, pbEnd.z),
            CadPoint3D(ptEnd.x, -halfW, ptEnd.z),
            CadPoint3D(ptStart.x, -halfW, ptStart.z),
          ],
          normal: const CadPoint3D(0.0, -1.0, 0.0),
          color: railColor,
          holes: leftWebHoles,
        ),
      );
      // Outer Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_bottom_flange_l_$s',
          vertices: [
            CadPoint3D(pbStart.x, -halfW, pbStart.z),
            CadPoint3D(pbStart.x, yLf, pbStart.z),
            CadPoint3D(pbEnd.x, yLf, pbEnd.z),
            CadPoint3D(pbEnd.x, -halfW, pbEnd.z),
          ],
          normal: CadPoint3D(-uSeg.x, 0.0, -uSeg.z),
          color: railColor,
        ),
      );
      // Outer Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_top_flange_l_$s',
          vertices: [
            CadPoint3D(ptStart.x, -halfW, ptStart.z),
            CadPoint3D(ptEnd.x, -halfW, ptEnd.z),
            CadPoint3D(ptEnd.x, yLf, ptEnd.z),
            CadPoint3D(ptStart.x, yLf, ptStart.z),
          ],
          normal: uSeg,
          color: railColor,
        ),
      );

      // Inner Web (offset +T along Y)
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_web_l_inner_$s',
          vertices: [
            CadPoint3D(pbStart.x + (uSeg.x * T), -halfW + T, pbStart.z + (uSeg.z * T)),
            CadPoint3D(ptStart.x - (uSeg.x * T), -halfW + T, ptStart.z - (uSeg.z * T)),
            CadPoint3D(ptEnd.x - (uSeg.x * T), -halfW + T, ptEnd.z - (uSeg.z * T)),
            CadPoint3D(pbEnd.x + (uSeg.x * T), -halfW + T, pbEnd.z + (uSeg.z * T)),
          ],
          normal: const CadPoint3D(0.0, 1.0, 0.0),
          color: railColor,
          holes: leftWebHolesInner,
        ),
      );
      // Inner Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_bottom_flange_l_inner_$s',
          vertices: [
            CadPoint3D(pbStart.x + (uSeg.x * T), -halfW + T, pbStart.z + (uSeg.z * T)),
            CadPoint3D(pbEnd.x + (uSeg.x * T), -halfW + T, pbEnd.z + (uSeg.z * T)),
            CadPoint3D(pbEnd.x + (uSeg.x * T), yLf, pbEnd.z + (uSeg.z * T)),
            CadPoint3D(pbStart.x + (uSeg.x * T), yLf, pbStart.z + (uSeg.z * T)),
          ],
          normal: uSeg,
          color: railColor,
        ),
      );
      // Inner Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_top_flange_l_inner_$s',
          vertices: [
            CadPoint3D(ptStart.x - (uSeg.x * T), -halfW + T, ptStart.z - (uSeg.z * T)),
            CadPoint3D(ptStart.x - (uSeg.x * T), yLf, ptStart.z - (uSeg.z * T)),
            CadPoint3D(ptEnd.x - (uSeg.x * T), yLf, ptEnd.z - (uSeg.z * T)),
            CadPoint3D(ptEnd.x - (uSeg.x * T), -halfW + T, ptEnd.z - (uSeg.z * T)),
          ],
          normal: CadPoint3D(-uSeg.x, 0.0, -uSeg.z),
          color: railColor,
        ),
      );
      // Flange Lips
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_riser_top_lip_l_$s',
          vertices: [
            CadPoint3D(ptStart.x, yLf, ptStart.z),
            CadPoint3D(ptEnd.x, yLf, ptEnd.z),
            CadPoint3D(ptEnd.x - (uSeg.x * T), yLf, ptEnd.z - (uSeg.z * T)),
            CadPoint3D(ptStart.x - (uSeg.x * T), yLf, ptStart.z - (uSeg.z * T)),
          ],
          normal: CadPoint3D(0.0, fSign, 0.0),
          color: railColor,
        ),
      );
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_riser_bottom_lip_l_$s',
          vertices: [
            CadPoint3D(pbStart.x, yLf, pbStart.z),
            CadPoint3D(pbStart.x + (uSeg.x * T), yLf, pbStart.z + (uSeg.z * T)),
            CadPoint3D(pbEnd.x + (uSeg.x * T), yLf, pbEnd.z + (uSeg.z * T)),
            CadPoint3D(pbEnd.x, yLf, pbEnd.z),
          ],
          normal: CadPoint3D(0.0, fSign, 0.0),
          color: railColor,
        ),
      );

      // --- RIGHT RAIL (Y = +halfW, Inward = -Y) ---
      // Outer Web
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_web_r_$s',
          vertices: [
            CadPoint3D(pbStart.x, halfW, pbStart.z),
            CadPoint3D(ptStart.x, halfW, ptStart.z),
            CadPoint3D(ptEnd.x, halfW, ptEnd.z),
            CadPoint3D(pbEnd.x, halfW, pbEnd.z),
          ],
          normal: const CadPoint3D(0.0, 1.0, 0.0),
          color: railColor,
          holes: rightWebHoles,
        ),
      );
      // Outer Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_bottom_flange_r_$s',
          vertices: [
            CadPoint3D(pbStart.x, halfW, pbStart.z),
            CadPoint3D(pbEnd.x, halfW, pbEnd.z),
            CadPoint3D(pbEnd.x, yRf, pbEnd.z),
            CadPoint3D(pbStart.x, yRf, pbStart.z),
          ],
          normal: CadPoint3D(-uSeg.x, 0.0, -uSeg.z),
          color: railColor,
        ),
      );
      // Outer Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_top_flange_r_$s',
          vertices: [
            CadPoint3D(ptStart.x, halfW, ptStart.z),
            CadPoint3D(ptStart.x, yRf, ptStart.z),
            CadPoint3D(ptEnd.x, yRf, ptEnd.z),
            CadPoint3D(ptEnd.x, halfW, ptEnd.z),
          ],
          normal: uSeg,
          color: railColor,
        ),
      );

      // Inner Web (offset -T along Y)
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_web_r_inner_$s',
          vertices: [
            CadPoint3D(pbStart.x + (uSeg.x * T), halfW - T, pbStart.z + (uSeg.z * T)),
            CadPoint3D(pbEnd.x + (uSeg.x * T), halfW - T, pbEnd.z + (uSeg.z * T)),
            CadPoint3D(ptEnd.x - (uSeg.x * T), halfW - T, ptEnd.z - (uSeg.z * T)),
            CadPoint3D(ptStart.x - (uSeg.x * T), halfW - T, ptStart.z - (uSeg.z * T)),
          ],
          normal: const CadPoint3D(0.0, -1.0, 0.0),
          color: railColor,
          holes: rightWebHolesInner,
        ),
      );
      // Inner Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_bottom_flange_r_inner_$s',
          vertices: [
            CadPoint3D(pbStart.x + (uSeg.x * T), halfW - T, pbStart.z + (uSeg.z * T)),
            CadPoint3D(pbStart.x + (uSeg.x * T), yRf, pbStart.z + (uSeg.z * T)),
            CadPoint3D(pbEnd.x + (uSeg.x * T), yRf, pbEnd.z + (uSeg.z * T)),
            CadPoint3D(pbEnd.x + (uSeg.x * T), halfW - T, pbEnd.z + (uSeg.z * T)),
          ],
          normal: uSeg,
          color: railColor,
        ),
      );
      // Inner Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'riser_rail_top_flange_r_inner_$s',
          vertices: [
            CadPoint3D(ptStart.x - (uSeg.x * T), halfW - T, ptStart.z - (uSeg.z * T)),
            CadPoint3D(ptEnd.x - (uSeg.x * T), halfW - T, ptEnd.z - (uSeg.z * T)),
            CadPoint3D(ptEnd.x - (uSeg.x * T), yRf, ptEnd.z - (uSeg.z * T)),
            CadPoint3D(ptStart.x - (uSeg.x * T), yRf, ptStart.z - (uSeg.z * T)),
          ],
          normal: CadPoint3D(-uSeg.x, 0.0, -uSeg.z),
          color: railColor,
        ),
      );
      // Flange Lips
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_riser_top_lip_r_$s',
          vertices: [
            CadPoint3D(ptStart.x, yRf, ptStart.z),
            CadPoint3D(ptStart.x - (uSeg.x * T), yRf, ptStart.z - (uSeg.z * T)),
            CadPoint3D(ptEnd.x - (uSeg.x * T), yRf, ptEnd.z - (uSeg.z * T)),
            CadPoint3D(ptEnd.x, yRf, ptEnd.z),
          ],
          normal: CadPoint3D(0.0, -fSign, 0.0),
          color: railColor,
        ),
      );
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_riser_bottom_lip_r_$s',
          vertices: [
            CadPoint3D(pbStart.x, yRf, pbStart.z),
            CadPoint3D(pbEnd.x, yRf, pbEnd.z),
            CadPoint3D(pbEnd.x + (uSeg.x * T), yRf, pbEnd.z + (uSeg.z * T)),
            CadPoint3D(pbStart.x + (uSeg.x * T), yRf, pbStart.z + (uSeg.z * T)),
          ],
          normal: CadPoint3D(0.0, -fSign, 0.0),
          color: railColor,
        ),
      );
    }

    // --- OPEN PORT PROFILE RIMS (Physical 2mm Metal Wall Profile - NO Solid End Caps) ---
    final double yLf = -halfW + (fSign * F);
    final double yRf = halfW - (fSign * F);
    final double T = (params.thickness > 0.1 && params.thickness < 10.0) ? params.thickness : 2.0;

    thicknessPolygons.addAll([
      // Left Rail Port 1 Profile Rim (Normal -1, 0, 0)
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_left_port1_web',
        vertices: [
          CadPoint3D(pInletBottom.x, -halfW, pInletBottom.z),
          CadPoint3D(pInletTop.x, -halfW, pInletTop.z),
          CadPoint3D(pInletTop.x, -halfW + T, pInletTop.z),
          CadPoint3D(pInletBottom.x, -halfW + T, pInletBottom.z),
        ],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_left_port1_top_flange',
        vertices: [
          CadPoint3D(pInletTop.x, -halfW, pInletTop.z),
          CadPoint3D(pInletTop.x, yLf, pInletTop.z),
          CadPoint3D(pInletTop.x, yLf, pInletTop.z - T),
          CadPoint3D(pInletTop.x, -halfW + T, pInletTop.z - T),
        ],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_left_port1_bottom_flange',
        vertices: [
          CadPoint3D(pInletBottom.x, -halfW, pInletBottom.z),
          CadPoint3D(pInletBottom.x, -halfW + T, pInletBottom.z + T),
          CadPoint3D(pInletBottom.x, yLf, pInletBottom.z + T),
          CadPoint3D(pInletBottom.x, yLf, pInletBottom.z),
        ],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),

      // Right Rail Port 1 Profile Rim (Normal -1, 0, 0)
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_right_port1_web',
        vertices: [
          CadPoint3D(pInletBottom.x, halfW, pInletBottom.z),
          CadPoint3D(pInletBottom.x, halfW - T, pInletBottom.z),
          CadPoint3D(pInletTop.x, halfW - T, pInletTop.z),
          CadPoint3D(pInletTop.x, halfW, pInletTop.z),
        ],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_right_port1_top_flange',
        vertices: [
          CadPoint3D(pInletTop.x, halfW, pInletTop.z),
          CadPoint3D(pInletTop.x, halfW - T, pInletTop.z - T),
          CadPoint3D(pInletTop.x, yRf, pInletTop.z - T),
          CadPoint3D(pInletTop.x, yRf, pInletTop.z),
        ],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_right_port1_bottom_flange',
        vertices: [
          CadPoint3D(pInletBottom.x, halfW, pInletBottom.z),
          CadPoint3D(pInletBottom.x, yRf, pInletBottom.z),
          CadPoint3D(pInletBottom.x, yRf, pInletBottom.z + T),
          CadPoint3D(pInletBottom.x, halfW - T, pInletBottom.z + T),
        ],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),

      // Left Rail Port 2 Profile Rim (Normal tExit)
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_left_port2_web',
        vertices: [
          CadPoint3D(pOutletBottom.x, -halfW, pOutletBottom.z),
          CadPoint3D(pOutletBottom.x, -halfW + T, pOutletBottom.z),
          CadPoint3D(pOutletTop.x, -halfW + T, pOutletTop.z),
          CadPoint3D(pOutletTop.x, -halfW, pOutletTop.z),
        ],
        normal: tExit,
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_left_port2_top_flange',
        vertices: [
          CadPoint3D(pOutletTop.x, -halfW, pOutletTop.z),
          CadPoint3D(pOutletTop.x - (uExit.x * T), -halfW + T, pOutletTop.z - (uExit.z * T)),
          CadPoint3D(pOutletTop.x - (uExit.x * T), yLf, pOutletTop.z - (uExit.z * T)),
          CadPoint3D(pOutletTop.x, yLf, pOutletTop.z),
        ],
        normal: tExit,
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_left_port2_bottom_flange',
        vertices: [
          CadPoint3D(pOutletBottom.x, -halfW, pOutletBottom.z),
          CadPoint3D(pOutletBottom.x, yLf, pOutletBottom.z),
          CadPoint3D(pOutletBottom.x + (uExit.x * T), yLf, pOutletBottom.z + (uExit.z * T)),
          CadPoint3D(pOutletBottom.x + (uExit.x * T), -halfW + T, pOutletBottom.z + (uExit.z * T)),
        ],
        normal: tExit,
        color: railColor,
      ),

      // Right Rail Port 2 Profile Rim (Normal tExit)
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_right_port2_web',
        vertices: [
          CadPoint3D(pOutletBottom.x, halfW, pOutletBottom.z),
          CadPoint3D(pOutletTop.x, halfW, pOutletTop.z),
          CadPoint3D(pOutletTop.x, halfW - T, pOutletTop.z),
          CadPoint3D(pOutletBottom.x, halfW - T, pOutletBottom.z),
        ],
        normal: tExit,
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_right_port2_top_flange',
        vertices: [
          CadPoint3D(pOutletTop.x, halfW, pOutletTop.z),
          CadPoint3D(pOutletTop.x, yRf, pOutletTop.z),
          CadPoint3D(pOutletTop.x - (uExit.x * T), yRf, pOutletTop.z - (uExit.z * T)),
          CadPoint3D(pOutletTop.x - (uExit.x * T), halfW - T, pOutletTop.z - (uExit.z * T)),
        ],
        normal: tExit,
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_riser_right_port2_bottom_flange',
        vertices: [
          CadPoint3D(pOutletBottom.x, halfW, pOutletBottom.z),
          CadPoint3D(pOutletBottom.x + (uExit.x * T), halfW - T, pOutletBottom.z + (uExit.z * T)),
          CadPoint3D(pOutletBottom.x + (uExit.x * T), yRf, pOutletBottom.z + (uExit.z * T)),
          CadPoint3D(pOutletBottom.x, yRf, pOutletBottom.z),
        ],
        normal: tExit,
        color: railColor,
      ),
    ]);

    // --- ORIENTED RUNGS ---
    for (int i = 0; i < rungs.length; i++) {
      final rung = rungs[i];
      final double alpha = rung.orientationAngleRad;
      final tRung = CadPoint3D(math.cos(alpha), 0.0, isInsideRiser ? math.sin(alpha) : -math.sin(alpha));
      final uRung = CadPoint3D(isInsideRiser ? -math.sin(alpha) : math.sin(alpha), 0.0, math.cos(alpha));

      final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
        rungId: 'riser_rung_$i',
        centerTop: CadPoint3D(rung.center3D.x + (uRung.x * 10.0), 0.0, rung.center3D.z + (uRung.z * 10.0)),
        lengthDir: const CadPoint3D(0.0, 1.0, 0.0),
        widthDir: tRung,
        upDir: uRung,
        interiorHalfSpan: halfW,
        rungW: 40.0,
        rungDepth: 20.0,
        thickness: params.thickness,
        color: rungColor,
        isPassThrough: isPassThrough,
        outsideProjection: params.outsideWeldProjection,
      );
      polygons.addAll(rungPolys);
    }

    final double totalMaxZ = isInsideRiser ? math.max(pOutletTop.z, radius + H) : math.max(H, leadIn);
    final double totalBoundHeight = isInsideRiser ? (pOutletTop.z + 10.0) : (radius + H + 10.0);

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: params.width + (2 * F),
      boundLength: pOutletBottom.x + leadIn,
      boundHeight: math.max(totalBoundHeight, 350.0),
      center: CadPoint3D(pOutletBottom.x / 2.0, 0.0, totalMaxZ / 2.0),
    );
  }

  /// Adds a solid C-channel rail segment with top & bottom flanges, inner faces,
  /// flange rims, sheet thickness, end connection holes, and rung pass-through slots.
  static void _buildCChannelRailSegment({
    required List<CadFoldedPolygon3D> polygons,
    required List<CadFoldedPolygon3D> thicknessPolygons,
    required String segmentId,
    required CadPoint3D pStart,
    required CadPoint3D pEnd,
    required CadPoint3D outwardNormal,
    required double height,
    required double flangeWidth,
    required double thickness,
    required Color color,
    bool flangeOutward = true,
    List<List<CadPoint3D>> webHoles = const [],
    List<List<CadPoint3D>> webHolesInner = const [],
    bool isStartEnd = false,
    bool isFinalEnd = false,
    bool includeEndCapStart = false,
    bool includeEndCapEnd = false,
  }) {
    final dSeg = CadPoint3D(pEnd.x - pStart.x, pEnd.y - pStart.y, pEnd.z - pStart.z);
    final segLen = math.sqrt(dSeg.x * dSeg.x + dSeg.y * dSeg.y + dSeg.z * dSeg.z);
    if (segLen < 1e-4) return;
    final tangent = CadPoint3D(dSeg.x / segLen, dSeg.y / segLen, dSeg.z / segLen);

    final nOut = outwardNormal;
    final nInward = CadPoint3D(-nOut.x, -nOut.y, -nOut.z);

    final double F = flangeWidth > 0 ? flangeWidth : 32.0;
    final double H = height > 0 ? height : 75.0;
    final double T = (thickness > 0.1 && thickness < 10.0) ? thickness : 2.0;

    final fVec = flangeOutward ? CadPoint3D(nOut.x * F, nOut.y * F, 0.0) : CadPoint3D(nInward.x * F, nInward.y * F, 0.0);

    final pStartF = CadPoint3D(pStart.x + fVec.x, pStart.y + fVec.y, pStart.z);
    final pEndF = CadPoint3D(pEnd.x + fVec.x, pEnd.y + fVec.y, pEnd.z);

    final pStartInner = CadPoint3D(pStart.x + nInward.x * T, pStart.y + nInward.y * T, pStart.z);
    final pEndInner = CadPoint3D(pEnd.x + nInward.x * T, pEnd.y + nInward.y * T, pEnd.z);

    final allWebHoles = <List<CadPoint3D>>[...webHoles];
    final allWebHolesInner = <List<CadPoint3D>>[...webHolesInner];

    // Splice / coupler connection holes (2x Ø10mm holes, 32mm from edge, 25mm vertical pitch)
    List<CadPoint3D> makeOctagon(CadPoint3D center) {
      const double r = 5.0; // Ø10mm
      const int steps = 8;
      final pts = <CadPoint3D>[];
      for (int k = 0; k < steps; k++) {
        final double ang = k * 2.0 * math.pi / steps;
        pts.add(CadPoint3D(center.x + (tangent.x * r * math.cos(ang)), center.y + (tangent.y * r * math.cos(ang)), center.z + (r * math.sin(ang))));
      }
      return pts;
    }

    if (isStartEnd && segLen >= 50.0) {
      final double z1 = (H / 2.0) - 12.5;
      final double z2 = (H / 2.0) + 12.5;
      final c1 = CadPoint3D(pStart.x + tangent.x * 32.0, pStart.y + tangent.y * 32.0, z1);
      final c2 = CadPoint3D(pStart.x + tangent.x * 32.0, pStart.y + tangent.y * 32.0, z2);

      final h1 = makeOctagon(c1);
      final h2 = makeOctagon(c2);
      allWebHoles.addAll([h1, h2]);

      allWebHolesInner.add(h1.map((p) => CadPoint3D(p.x + nInward.x * T, p.y + nInward.y * T, p.z)).toList());
      allWebHolesInner.add(h2.map((p) => CadPoint3D(p.x + nInward.x * T, p.y + nInward.y * T, p.z)).toList());
    }

    if (isFinalEnd && segLen >= 50.0) {
      final double z1 = (H / 2.0) - 12.5;
      final double z2 = (H / 2.0) + 12.5;
      final c1 = CadPoint3D(pEnd.x - tangent.x * 32.0, pEnd.y - tangent.y * 32.0, z1);
      final c2 = CadPoint3D(pEnd.x - tangent.x * 32.0, pEnd.y - tangent.y * 32.0, z2);

      final h1 = makeOctagon(c1);
      final h2 = makeOctagon(c2);
      allWebHoles.addAll([h1, h2]);

      allWebHolesInner.add(h1.map((p) => CadPoint3D(p.x + nInward.x * T, p.y + nInward.y * T, p.z)).toList());
      allWebHolesInner.add(h2.map((p) => CadPoint3D(p.x + nInward.x * T, p.y + nInward.y * T, p.z)).toList());
    }

    // 1. Outer Web
    polygons.add(
      CadFoldedPolygon3D(
        faceId: '${segmentId}_outer_web',
        vertices: [CadPoint3D(pStart.x, pStart.y, 0.0), CadPoint3D(pEnd.x, pEnd.y, 0.0), CadPoint3D(pEnd.x, pEnd.y, H), CadPoint3D(pStart.x, pStart.y, H)],
        normal: nOut,
        color: color,
        holes: allWebHoles,
      ),
    );

    // 2. Outer Bottom Flange (normal: 0, 0, -1)
    polygons.add(
      CadFoldedPolygon3D(
        faceId: '${segmentId}_outer_bottom_flange',
        vertices: [
          CadPoint3D(pStart.x, pStart.y, 0.0),
          CadPoint3D(pEnd.x, pEnd.y, 0.0),
          CadPoint3D(pEndF.x, pEndF.y, 0.0),
          CadPoint3D(pStartF.x, pStartF.y, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );

    // 3. Outer Top Flange (normal: 0, 0, 1)
    polygons.add(
      CadFoldedPolygon3D(
        faceId: '${segmentId}_outer_top_flange',
        vertices: [CadPoint3D(pStart.x, pStart.y, H), CadPoint3D(pStartF.x, pStartF.y, H), CadPoint3D(pEndF.x, pEndF.y, H), CadPoint3D(pEnd.x, pEnd.y, H)],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    // 4. Inner Web (normal: nInward)
    polygons.add(
      CadFoldedPolygon3D(
        faceId: '${segmentId}_inner_web',
        vertices: [
          CadPoint3D(pStartInner.x, pStartInner.y, T),
          CadPoint3D(pStartInner.x, pStartInner.y, H - T),
          CadPoint3D(pEndInner.x, pEndInner.y, H - T),
          CadPoint3D(pEndInner.x, pEndInner.y, T),
        ],
        normal: nInward,
        color: color,
        holes: allWebHolesInner,
      ),
    );

    // 5. Inner Bottom Flange (normal: 0, 0, 1)
    polygons.add(
      CadFoldedPolygon3D(
        faceId: '${segmentId}_inner_bottom_flange',
        vertices: [
          CadPoint3D(pStartInner.x, pStartInner.y, T),
          CadPoint3D(pStartF.x, pStartF.y, T),
          CadPoint3D(pEndF.x, pEndF.y, T),
          CadPoint3D(pEndInner.x, pEndInner.y, T),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    // 6. Inner Top Flange (normal: 0, 0, -1)
    polygons.add(
      CadFoldedPolygon3D(
        faceId: '${segmentId}_inner_top_flange',
        vertices: [
          CadPoint3D(pStartInner.x, pStartInner.y, H - T),
          CadPoint3D(pEndInner.x, pEndInner.y, H - T),
          CadPoint3D(pEndF.x, pEndF.y, H - T),
          CadPoint3D(pStartF.x, pStartF.y, H - T),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );

    // 7. Flange Rims / Lips
    final lipNormal = flangeOutward ? nOut : nInward;
    thicknessPolygons.add(
      CadFoldedPolygon3D(
        faceId: 'RIM_${segmentId}_top_flange_lip',
        vertices: flangeOutward
            ? [
                CadPoint3D(pStartF.x, pStartF.y, H - T),
                CadPoint3D(pEndF.x, pEndF.y, H - T),
                CadPoint3D(pEndF.x, pEndF.y, H),
                CadPoint3D(pStartF.x, pStartF.y, H),
              ]
            : [
                CadPoint3D(pStartF.x, pStartF.y, H),
                CadPoint3D(pEndF.x, pEndF.y, H),
                CadPoint3D(pEndF.x, pEndF.y, H - T),
                CadPoint3D(pStartF.x, pStartF.y, H - T),
              ],
        normal: lipNormal,
        color: color,
      ),
    );

    thicknessPolygons.add(
      CadFoldedPolygon3D(
        faceId: 'RIM_${segmentId}_bottom_flange_lip',
        vertices: flangeOutward
            ? [CadPoint3D(pStartF.x, pStartF.y, 0.0), CadPoint3D(pStartF.x, pStartF.y, T), CadPoint3D(pEndF.x, pEndF.y, T), CadPoint3D(pEndF.x, pEndF.y, 0.0)]
            : [CadPoint3D(pStartF.x, pStartF.y, T), CadPoint3D(pEndF.x, pEndF.y, T), CadPoint3D(pEndF.x, pEndF.y, 0.0), CadPoint3D(pStartF.x, pStartF.y, 0.0)],
        normal: lipNormal,
        color: color,
      ),
    );

    // 8. Cutout Sidewalls through sheet thickness
    for (int h = 0; h < allWebHoles.length; h++) {
      final loopOut = allWebHoles[h];
      final loopIn = allWebHolesInner[h];
      if (loopOut.length == loopIn.length) {
        for (int v = 0; v < loopOut.length; v++) {
          final pA = loopOut[v];
          final pB = loopOut[(v + 1) % loopOut.length];
          final pAIn = loopIn[v];
          final pBIn = loopIn[(v + 1) % loopIn.length];
          thicknessPolygons.add(CadFoldedPolygon3D(faceId: '${segmentId}_hole_${h}_wall_$v', vertices: [pA, pB, pBIn, pAIn], normal: nOut, color: color));
        }
      }
    }

    // 9. End Caps
    if (includeEndCapStart) {
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'CAP_${segmentId}_start',
          vertices: [
            CadPoint3D(pStart.x, pStart.y, 0.0),
            CadPoint3D(pStartInner.x, pStartInner.y, 0.0),
            CadPoint3D(pStartInner.x, pStartInner.y, H),
            CadPoint3D(pStart.x, pStart.y, H),
          ],
          normal: CadPoint3D(-tangent.x, -tangent.y, -tangent.z),
          color: color,
        ),
      );
    }
    if (includeEndCapEnd) {
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'CAP_${segmentId}_end',
          vertices: [
            CadPoint3D(pEnd.x, pEnd.y, 0.0),
            CadPoint3D(pEnd.x, pEnd.y, H),
            CadPoint3D(pEndInner.x, pEndInner.y, H),
            CadPoint3D(pEndInner.x, pEndInner.y, 0.0),
          ],
          normal: tangent,
          color: color,
        ),
      );
    }
  }

  /// Creates a rectangular pass-through slot hole on a rail web for a 40x20mm rung.
  static ({List<CadPoint3D> outer, List<CadPoint3D> inner}) _makeRungWebSlot({
    required CadPoint3D center,
    required CadPoint3D tangent,
    required CadPoint3D inwardNormal,
    required double thickness,
    double slotW = 40.0,
    double slotH = 20.0,
  }) {
    final double hw = slotW / 2.0;
    final double hh = slotH / 2.0;
    final p1 = CadPoint3D(center.x - tangent.x * hw, center.y - tangent.y * hw, center.z - hh);
    final p2 = CadPoint3D(center.x + tangent.x * hw, center.y + tangent.y * hw, center.z - hh);
    final p3 = CadPoint3D(center.x + tangent.x * hw, center.y + tangent.y * hw, center.z + hh);
    final p4 = CadPoint3D(center.x - tangent.x * hw, center.y - tangent.y * hw, center.z + hh);

    final outer = [p1, p2, p3, p4];
    final inner = outer.map((p) => CadPoint3D(p.x + inwardNormal.x * thickness, p.y + inwardNormal.y * thickness, p.z)).toList();
    return (outer: outer, inner: inner);
  }

  static FoldedMeshResult _buildReducerMesh({
    required double width1,
    required double width2,
    required double length,
    required double leadIn,
    required String alignment,
    required List<double> stations,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final thicknessPolygons = <CadFoldedPolygon3D>[];
    final double H = params.height > 0 ? params.height : 75.0;
    final double F = params.flangeWidth > 0 ? params.flangeWidth : 32.0;
    final double T = (params.thickness > 0.1 && params.thickness < 10.0) ? params.thickness : 2.0;
    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;
    const double zRungCenter = 25.0;

    // Rail datum Y values
    final double yL1 = -width1 / 2.0;
    final double yL2 = alignment == 'left' ? -width1 / 2.0 : (alignment == 'right' ? (width1 / 2.0) - width2 : -width2 / 2.0);

    final double yR1 = width1 / 2.0;
    final double yR2 = alignment == 'right' ? width1 / 2.0 : (alignment == 'left' ? (-width1 / 2.0) + width2 : width2 / 2.0);

    final pL0 = CadPoint3D(0.0, yL1, 0.0);
    final pL1 = CadPoint3D(leadIn, yL1, 0.0);
    final pL2 = CadPoint3D(length - leadIn, yL2, 0.0);
    final pL3 = CadPoint3D(length, yL2, 0.0);

    final pR0 = CadPoint3D(0.0, yR1, 0.0);
    final pR1 = CadPoint3D(leadIn, yR1, 0.0);
    final pR2 = CadPoint3D(length - leadIn, yR2, 0.0);
    final pR3 = CadPoint3D(length, yR2, 0.0);

    // Tangents and outward normals for left taper
    final dL1 = CadPoint3D(pL2.x - pL1.x, pL2.y - pL1.y, 0.0);
    final lenL1 = math.sqrt(dL1.x * dL1.x + dL1.y * dL1.y);
    final tL1 = lenL1 > 1e-4 ? CadPoint3D(dL1.x / lenL1, dL1.y / lenL1, 0.0) : const CadPoint3D(1.0, 0.0, 0.0);
    final nL1 = CadPoint3D(tL1.y, -tL1.x, 0.0);

    // Tangents and outward normals for right taper
    final dR1 = CadPoint3D(pR2.x - pR1.x, pR2.y - pR1.y, 0.0);
    final lenR1 = math.sqrt(dR1.x * dR1.x + dR1.y * dR1.y);
    final tR1 = lenR1 > 1e-4 ? CadPoint3D(dR1.x / lenR1, dR1.y / lenR1, 0.0) : const CadPoint3D(1.0, 0.0, 0.0);
    final nR1 = CadPoint3D(-tR1.y, tR1.x, 0.0);

    // Pass-through slot holes per segment
    final leftHoles0 = <List<CadPoint3D>>[];
    final leftHoles0In = <List<CadPoint3D>>[];
    final leftHoles1 = <List<CadPoint3D>>[];
    final leftHoles1In = <List<CadPoint3D>>[];
    final leftHoles2 = <List<CadPoint3D>>[];
    final leftHoles2In = <List<CadPoint3D>>[];

    final rightHoles0 = <List<CadPoint3D>>[];
    final rightHoles0In = <List<CadPoint3D>>[];
    final rightHoles1 = <List<CadPoint3D>>[];
    final rightHoles1In = <List<CadPoint3D>>[];
    final rightHoles2 = <List<CadPoint3D>>[];
    final rightHoles2In = <List<CadPoint3D>>[];

    for (int i = 0; i < stations.length; i++) {
      final double x = stations[i];
      final double yL = (x <= leadIn) ? yL1 : (x >= length - leadIn ? yL2 : yL1 + ((x - leadIn) / (length - 2 * leadIn)) * (yL2 - yL1));
      final double yR = (x <= leadIn) ? yR1 : (x >= length - leadIn ? yR2 : yR1 + ((x - leadIn) / (length - 2 * leadIn)) * (yR2 - yR1));

      if (isPassThrough) {
        if (x <= leadIn) {
          final slotL = _makeRungWebSlot(
            center: CadPoint3D(x, yL, zRungCenter),
            tangent: const CadPoint3D(1.0, 0.0, 0.0),
            inwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
            thickness: T,
          );
          leftHoles0.add(slotL.outer);
          leftHoles0In.add(slotL.inner);
          final slotR = _makeRungWebSlot(
            center: CadPoint3D(x, yR, zRungCenter),
            tangent: const CadPoint3D(1.0, 0.0, 0.0),
            inwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
            thickness: T,
          );
          rightHoles0.add(slotR.outer);
          rightHoles0In.add(slotR.inner);
        } else if (x >= length - leadIn) {
          final slotL = _makeRungWebSlot(
            center: CadPoint3D(x, yL, zRungCenter),
            tangent: const CadPoint3D(1.0, 0.0, 0.0),
            inwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
            thickness: T,
          );
          leftHoles2.add(slotL.outer);
          leftHoles2In.add(slotL.inner);
          final slotR = _makeRungWebSlot(
            center: CadPoint3D(x, yR, zRungCenter),
            tangent: const CadPoint3D(1.0, 0.0, 0.0),
            inwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
            thickness: T,
          );
          rightHoles2.add(slotR.outer);
          rightHoles2In.add(slotR.inner);
        } else {
          final slotL = _makeRungWebSlot(center: CadPoint3D(x, yL, zRungCenter), tangent: tL1, inwardNormal: CadPoint3D(-nL1.x, -nL1.y, 0.0), thickness: T);
          leftHoles1.add(slotL.outer);
          leftHoles1In.add(slotL.inner);
          final slotR = _makeRungWebSlot(center: CadPoint3D(x, yR, zRungCenter), tangent: tR1, inwardNormal: CadPoint3D(-nR1.x, -nR1.y, 0.0), thickness: T);
          rightHoles1.add(slotR.outer);
          rightHoles1In.add(slotR.inner);
        }
      }

      // Generate 3D slotted C-channel rung
      final double halfSpan = (yR - yL).abs() / 2.0;
      final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
        rungId: 'reducer_rung_$i',
        centerTop: CadPoint3D(x, (yL + yR) / 2.0, zRungCenter + 10.0),
        lengthDir: CadPoint3D(0.0, yR - yL, 0.0),
        widthDir: const CadPoint3D(1.0, 0.0, 0.0),
        upDir: const CadPoint3D(0.0, 0.0, 1.0),
        interiorHalfSpan: halfSpan,
        rungW: 40.0,
        rungDepth: 20.0,
        thickness: T,
        color: rungColor,
        isPassThrough: isPassThrough,
        outsideProjection: isPassThrough ? params.outsideWeldProjection : 0.0,
        slotLength: 25.0,
        slotWidth: 14.0,
      );
      polygons.addAll(rungPolys);
    }

    final bool isFlangeOutward = params.flangeDirection == LadderFlangeDirection.outside;

    // Build Left Rail (Solid C-Channel)
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'reducer_left_0',
      pStart: pL0,
      pEnd: pL1,
      outwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: leftHoles0,
      webHolesInner: leftHoles0In,
      isStartEnd: true,
      includeEndCapStart: true,
    );
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'reducer_left_1',
      pStart: pL1,
      pEnd: pL2,
      outwardNormal: nL1,
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: leftHoles1,
      webHolesInner: leftHoles1In,
    );
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'reducer_left_2',
      pStart: pL2,
      pEnd: pL3,
      outwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: leftHoles2,
      webHolesInner: leftHoles2In,
      isFinalEnd: true,
      includeEndCapEnd: true,
    );

    // Build Right Rail (Solid C-Channel)
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'reducer_right_0',
      pStart: pR0,
      pEnd: pR1,
      outwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: rightHoles0,
      webHolesInner: rightHoles0In,
      isStartEnd: true,
      includeEndCapStart: true,
    );
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'reducer_right_1',
      pStart: pR1,
      pEnd: pR2,
      outwardNormal: nR1,
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: rightHoles1,
      webHolesInner: rightHoles1In,
    );
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'reducer_right_2',
      pStart: pR2,
      pEnd: pR3,
      outwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: rightHoles2,
      webHolesInner: rightHoles2In,
      isFinalEnd: true,
      includeEndCapEnd: true,
    );

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: math.max(width1, width2) + (2 * F),
      boundLength: length,
      boundHeight: H,
      center: CadPoint3D(length / 2.0, 0.0, H / 2.0),
    );
  }

  static FoldedMeshResult _buildTeeMesh({
    required double mainInWidth,
    required double mainOutWidth,
    required double branchWidth,
    required double radius,
    required double leadIn,
    required List<LadderRungInstance> rungs,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final thicknessPolygons = <CadFoldedPolygon3D>[];
    final double H = params.height > 0 ? params.height : 75.0;
    final double F = params.flangeWidth > 0 ? params.flangeWidth : 32.0;
    final double T = (params.thickness > 0.1 && params.thickness < 10.0) ? params.thickness : 2.0;
    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;
    const double zRungCenter = 25.0;

    final double branchRightX = leadIn + radius + branchWidth;
    final double mainLength = (2 * leadIn) + (2 * radius) + branchWidth;
    final double throatY = math.max(mainInWidth, mainOutWidth) + radius;
    final bool isFlangeOutward = params.flangeDirection == LadderFlangeDirection.outside;

    final spineRungs = rungs.where((r) => r.orientationAngleRad < 0.1).toList();
    final branchRungs = rungs.where((r) => r.orientationAngleRad >= 0.1).toList();

    // 1. Back continuous straight rail along Y = 0 (from X = 0 to X = mainLength)
    final pBackStart = const CadPoint3D(0.0, 0.0, 0.0);
    final pBackMid = CadPoint3D(mainLength / 2.0, 0.0, 0.0);
    final pBackEnd = CadPoint3D(mainLength, 0.0, 0.0);

    final backHoles0 = <List<CadPoint3D>>[];
    final backHoles0In = <List<CadPoint3D>>[];
    final backHoles1 = <List<CadPoint3D>>[];
    final backHoles1In = <List<CadPoint3D>>[];

    if (isPassThrough) {
      for (final r in spineRungs) {
        final slot = _makeRungWebSlot(
          center: CadPoint3D(r.center3D.x, 0.0, zRungCenter),
          tangent: const CadPoint3D(1.0, 0.0, 0.0),
          inwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
          thickness: T,
        );
        if (r.center3D.x < mainLength / 2.0) {
          backHoles0.add(slot.outer);
          backHoles0In.add(slot.inner);
        } else {
          backHoles1.add(slot.outer);
          backHoles1In.add(slot.inner);
        }
      }
    }

    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'tee_back_seg_0',
      pStart: pBackStart,
      pEnd: pBackMid,
      outwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: backHoles0,
      webHolesInner: backHoles0In,
      isStartEnd: true,
      includeEndCapStart: true,
    );
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'tee_back_seg_1',
      pStart: pBackMid,
      pEnd: pBackEnd,
      outwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: backHoles1,
      webHolesInner: backHoles1In,
      isFinalEnd: true,
      includeEndCapEnd: true,
    );

    // 2. Left Inlet Collar Rail (from Port 3 to corner)
    final pLInlet0 = CadPoint3D(0.0, mainInWidth, 0.0);
    final pLInlet1 = CadPoint3D(leadIn, mainInWidth, 0.0);
    final leftInletHoles = <List<CadPoint3D>>[];
    final leftInletHolesIn = <List<CadPoint3D>>[];
    if (isPassThrough) {
      final slot = _makeRungWebSlot(
        center: CadPoint3D(50.0, mainInWidth, zRungCenter),
        tangent: const CadPoint3D(1.0, 0.0, 0.0),
        inwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
        thickness: T,
      );
      leftInletHoles.add(slot.outer);
      leftInletHolesIn.add(slot.inner);
    }
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'tee_left_inlet',
      pStart: pLInlet0,
      pEnd: pLInlet1,
      outwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: leftInletHoles,
      webHolesInner: leftInletHolesIn,
      isStartEnd: true,
      includeEndCapStart: true,
    );

    // 3. Left Corner Miter (reaches directly to throatY at inside corner leadIn + radius)
    final int cornerSegs = params.accessoryStyle == LadderAccessoryStyle.curved ? 16 : 1;
    final double cxL = leadIn;
    final double cyL = throatY;
    CadPoint3D pPrevL = pLInlet1;

    for (int s = 0; s < cornerSegs; s++) {
      final double a = (math.pi / 2.0) * (s + 1) / cornerSegs;
      final double px = cxL + radius * math.sin(a);
      final double py = cyL - radius * math.cos(a);
      final pNextL = CadPoint3D(px, py, 0.0);

      final dS = CadPoint3D(pNextL.x - pPrevL.x, pNextL.y - pPrevL.y, 0.0);
      final lenS = math.sqrt(dS.x * dS.x + dS.y * dS.y);
      final tS = lenS > 1e-4 ? CadPoint3D(dS.x / lenS, dS.y / lenS, 0.0) : const CadPoint3D(0.0, 1.0, 0.0);
      final nOutS = CadPoint3D(-tS.y, tS.x, 0.0);
      final nInwardS = CadPoint3D(-nOutS.x, -nOutS.y, 0.0);

      List<List<CadPoint3D>> segWebHoles = const [];
      List<List<CadPoint3D>> segWebHolesInner = const [];
      if (params.accessoryStyle == LadderAccessoryStyle.segmented && s == 0 && lenS >= 50.0) {
        final double slotL = math.min(40.0, lenS - 20.0);
        const double slotH = 16.0;
        final double hl = slotL / 2.0;
        final double hh = math.min(slotH / 2.0, (H - 20.0) / 2.0);
        final pMid = CadPoint3D((pPrevL.x + pNextL.x) / 2.0, (pPrevL.y + pNextL.y) / 2.0, H / 2.0);
        final slotOut = [
          CadPoint3D(pMid.x - tS.x * hl, pMid.y - tS.y * hl, pMid.z - hh),
          CadPoint3D(pMid.x + tS.x * hl, pMid.y + tS.y * hl, pMid.z - hh),
          CadPoint3D(pMid.x + tS.x * hl, pMid.y + tS.y * hl, pMid.z + hh),
          CadPoint3D(pMid.x - tS.x * hl, pMid.y - tS.y * hl, pMid.z + hh),
        ];
        final slotIn = slotOut.map((p) => CadPoint3D(p.x + nInwardS.x * T, p.y + nInwardS.y * T, p.z)).toList();
        segWebHoles = [slotOut];
        segWebHolesInner = [slotIn];
      }

      final bool isLast = s == cornerSegs - 1;
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'tee_left_miter_$s',
        pStart: pPrevL,
        pEnd: pNextL,
        outwardNormal: nOutS,
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        webHoles: segWebHoles,
        webHolesInner: segWebHolesInner,
        isFinalEnd: isLast,
        includeEndCapEnd: isLast,
      );
      pPrevL = pNextL;
    }

    // 4. Right Corner Miter (starts at branchRightX, throatY and sweeps to branchRightX + radius, mainOutWidth)
    final pRBranchMiterStart = CadPoint3D(branchRightX, throatY, 0.0);
    CadPoint3D pPrevR = pRBranchMiterStart;
    for (int s = 0; s < cornerSegs; s++) {
      final double b = (math.pi / 2.0) * (s + 1) / cornerSegs;
      final double px = branchRightX + radius * (1.0 - math.cos(b));
      final double py = throatY - radius * math.sin(b);
      final pNextR = CadPoint3D(px, py, 0.0);

      final dS = CadPoint3D(pNextR.x - pPrevR.x, pNextR.y - pPrevR.y, 0.0);
      final lenS = math.sqrt(dS.x * dS.x + dS.y * dS.y);
      final tS = lenS > 1e-4 ? CadPoint3D(dS.x / lenS, dS.y / lenS, 0.0) : const CadPoint3D(1.0, 0.0, 0.0);
      final nOutS = CadPoint3D(-tS.y, tS.x, 0.0);
      final nInwardS = CadPoint3D(-nOutS.x, -nOutS.y, 0.0);

      List<List<CadPoint3D>> segWebHoles = const [];
      List<List<CadPoint3D>> segWebHolesInner = const [];
      if (params.accessoryStyle == LadderAccessoryStyle.segmented && s == 0 && lenS >= 50.0) {
        final double slotL = math.min(40.0, lenS - 20.0);
        const double slotH = 16.0;
        final double hl = slotL / 2.0;
        final double hh = math.min(slotH / 2.0, (H - 20.0) / 2.0);
        final pMid = CadPoint3D((pPrevR.x + pNextR.x) / 2.0, (pPrevR.y + pNextR.y) / 2.0, H / 2.0);
        final slotOut = [
          CadPoint3D(pMid.x - tS.x * hl, pMid.y - tS.y * hl, pMid.z - hh),
          CadPoint3D(pMid.x + tS.x * hl, pMid.y + tS.y * hl, pMid.z - hh),
          CadPoint3D(pMid.x + tS.x * hl, pMid.y + tS.y * hl, pMid.z + hh),
          CadPoint3D(pMid.x - tS.x * hl, pMid.y - tS.y * hl, pMid.z + hh),
        ];
        final slotIn = slotOut.map((p) => CadPoint3D(p.x + nInwardS.x * T, p.y + nInwardS.y * T, p.z)).toList();
        segWebHoles = [slotOut];
        segWebHolesInner = [slotIn];
      }

      final bool isFirst = s == 0;
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'tee_right_miter_$s',
        pStart: pPrevR,
        pEnd: pNextR,
        outwardNormal: nOutS,
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        webHoles: segWebHoles,
        webHolesInner: segWebHolesInner,
        isStartEnd: isFirst,
        includeEndCapStart: isFirst,
      );
      pPrevR = pNextR;
    }

    // 5. Right Front Outlet Rail (from right corner to Port 2)
    final pROutletEnd = CadPoint3D(mainLength, mainOutWidth, 0.0);
    final rightOutletHoles = <List<CadPoint3D>>[];
    final rightOutletHolesIn = <List<CadPoint3D>>[];
    if (isPassThrough) {
      final slot = _makeRungWebSlot(
        center: CadPoint3D(mainLength - 50.0, mainOutWidth, zRungCenter),
        tangent: const CadPoint3D(1.0, 0.0, 0.0),
        inwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
        thickness: T,
      );
      rightOutletHoles.add(slot.outer);
      rightOutletHolesIn.add(slot.inner);
    }
    _buildCChannelRailSegment(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      segmentId: 'tee_right_outlet',
      pStart: pPrevR,
      pEnd: pROutletEnd,
      outwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
      height: H,
      flangeWidth: F,
      thickness: T,
      color: railColor,
      flangeOutward: isFlangeOutward,
      webHoles: rightOutletHoles,
      webHolesInner: rightOutletHolesIn,
      isFinalEnd: true,
      includeEndCapEnd: true,
    );

    // 6. 3D Slotted Rungs
    // 6a. Spine rungs along main run (parallel to Y)
    for (int i = 0; i < spineRungs.length; i++) {
      final r = spineRungs[i];
      final double spanY = r.cutLength - (isPassThrough ? 2 * T + 2 * (params.outsideWeldProjection) : 0.0);
      final double halfSpan = spanY / 2.0;

      final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
        rungId: 'tee_spine_rung_$i',
        centerTop: CadPoint3D(r.center3D.x, r.center3D.y, zRungCenter + 10.0),
        lengthDir: const CadPoint3D(0.0, 1.0, 0.0),
        widthDir: const CadPoint3D(1.0, 0.0, 0.0),
        upDir: const CadPoint3D(0.0, 0.0, 1.0),
        interiorHalfSpan: halfSpan,
        rungW: 40.0,
        rungDepth: 20.0,
        thickness: T,
        color: rungColor,
        isPassThrough: isPassThrough,
        outsideProjection: isPassThrough ? params.outsideWeldProjection : 0.0,
        slotLength: 25.0,
        slotWidth: 14.0,
      );
      polygons.addAll(rungPolys);
    }

    // 6b. Branch rungs along branch (parallel to X)
    for (int j = 0; j < branchRungs.length; j++) {
      final r = branchRungs[j];
      final double halfSpan = branchWidth / 2.0;

      final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
        rungId: 'tee_branch_rung_$j',
        centerTop: CadPoint3D(r.center3D.x, r.center3D.y, zRungCenter + 10.0),
        lengthDir: const CadPoint3D(1.0, 0.0, 0.0),
        widthDir: const CadPoint3D(0.0, 1.0, 0.0),
        upDir: const CadPoint3D(0.0, 0.0, 1.0),
        interiorHalfSpan: halfSpan,
        rungW: 40.0,
        rungDepth: 20.0,
        thickness: T,
        color: rungColor,
        isPassThrough: isPassThrough,
        outsideProjection: isPassThrough ? params.outsideWeldProjection : 0.0,
        slotLength: 25.0,
        slotWidth: 14.0,
      );
      polygons.addAll(rungPolys);
    }

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: mainLength,
      boundLength: throatY,
      boundHeight: H,
      center: CadPoint3D(mainLength / 2.0, throatY / 2.0, H / 2.0),
    );
  }

  static FoldedMeshResult _buildCrossMesh({
    required double westWidth,
    required double eastWidth,
    required double northWidth,
    required double southWidth,
    required double radius,
    required double leadIn,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final thicknessPolygons = <CadFoldedPolygon3D>[];
    final double H = params.height > 0 ? params.height : 75.0;
    final double F = params.flangeWidth > 0 ? params.flangeWidth : 32.0;
    final double T = (params.thickness > 0.1 && params.thickness < 10.0) ? params.thickness : 2.0;
    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;
    const double zRungCenter = 25.0;

    final double lWest = leadIn + radius + (math.max(northWidth, southWidth) / 2.0);
    final double lEast = leadIn + radius + (math.max(northWidth, southWidth) / 2.0);
    final double lNorth = leadIn + radius + (math.max(westWidth, eastWidth) / 2.0);
    final double lSouth = leadIn + radius + (math.max(westWidth, eastWidth) / 2.0);

    final int cornerSegs = params.accessoryStyle == LadderAccessoryStyle.curved ? 16 : 2;
    final bool isFlangeOutward = params.flangeDirection == LadderFlangeDirection.outside;

    // Corner 0: North-West (Port 1 West top to Port 3 North left)
    {
      final p0 = CadPoint3D(-lWest, westWidth / 2.0, 0.0);
      final p1 = CadPoint3D(-northWidth / 2.0 - radius, westWidth / 2.0, 0.0);
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'cross_c0_inlet',
        pStart: p0,
        pEnd: p1,
        outwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        isStartEnd: true,
        includeEndCapStart: true,
      );

      final double cArcX = -northWidth / 2.0 - radius;
      final double cArcY = westWidth / 2.0 + radius;
      CadPoint3D pPrev = p1;
      for (int s = 0; s < cornerSegs; s++) {
        final double a = (math.pi / 2.0) * (s + 1) / cornerSegs;
        final pNext = CadPoint3D(cArcX + radius * math.sin(a), cArcY - radius * math.cos(a), 0.0);
        final dS = CadPoint3D(pNext.x - pPrev.x, pNext.y - pPrev.y, 0.0);
        final lenS = math.sqrt(dS.x * dS.x + dS.y * dS.y);
        final tS = lenS > 1e-4 ? CadPoint3D(dS.x / lenS, dS.y / lenS, 0.0) : const CadPoint3D(0.0, 1.0, 0.0);
        _buildCChannelRailSegment(
          polygons: polygons,
          thicknessPolygons: thicknessPolygons,
          segmentId: 'cross_c0_miter_$s',
          pStart: pPrev,
          pEnd: pNext,
          outwardNormal: CadPoint3D(-tS.y, tS.x, 0.0),
          height: H,
          flangeWidth: F,
          thickness: T,
          color: railColor,
          flangeOutward: isFlangeOutward,
        );
        pPrev = pNext;
      }

      final pEnd = CadPoint3D(-northWidth / 2.0, lNorth, 0.0);
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'cross_c0_outlet',
        pStart: pPrev,
        pEnd: pEnd,
        outwardNormal: const CadPoint3D(-1.0, 0.0, 0.0),
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        isFinalEnd: true,
        includeEndCapEnd: true,
      );
    }

    // Corner 1: North-East (Port 3 North right to Port 2 East top)
    {
      final p0 = CadPoint3D(northWidth / 2.0, lNorth, 0.0);
      final p1 = CadPoint3D(northWidth / 2.0, eastWidth / 2.0 + radius, 0.0);
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'cross_c1_inlet',
        pStart: p0,
        pEnd: p1,
        outwardNormal: const CadPoint3D(1.0, 0.0, 0.0),
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        isStartEnd: true,
        includeEndCapStart: true,
      );

      final double cArcX = northWidth / 2.0 + radius;
      final double cArcY = eastWidth / 2.0 + radius;
      CadPoint3D pPrev = p1;
      for (int s = 0; s < cornerSegs; s++) {
        final double a = (math.pi / 2.0) * (s + 1) / cornerSegs;
        final pNext = CadPoint3D(cArcX - radius * math.cos(a), cArcY - radius * math.sin(a), 0.0);
        final dS = CadPoint3D(pNext.x - pPrev.x, pNext.y - pPrev.y, 0.0);
        final lenS = math.sqrt(dS.x * dS.x + dS.y * dS.y);
        final tS = lenS > 1e-4 ? CadPoint3D(dS.x / lenS, dS.y / lenS, 0.0) : const CadPoint3D(1.0, 0.0, 0.0);
        _buildCChannelRailSegment(
          polygons: polygons,
          thicknessPolygons: thicknessPolygons,
          segmentId: 'cross_c1_miter_$s',
          pStart: pPrev,
          pEnd: pNext,
          outwardNormal: CadPoint3D(-tS.y, tS.x, 0.0),
          height: H,
          flangeWidth: F,
          thickness: T,
          color: railColor,
          flangeOutward: isFlangeOutward,
        );
        pPrev = pNext;
      }

      final pEnd = CadPoint3D(lEast, eastWidth / 2.0, 0.0);
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'cross_c1_outlet',
        pStart: pPrev,
        pEnd: pEnd,
        outwardNormal: const CadPoint3D(0.0, 1.0, 0.0),
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        isFinalEnd: true,
        includeEndCapEnd: true,
      );
    }

    // Corner 2: South-East (Port 2 East bottom to Port 4 South right)
    {
      final p0 = CadPoint3D(lEast, -eastWidth / 2.0, 0.0);
      final p1 = CadPoint3D(southWidth / 2.0 + radius, -eastWidth / 2.0, 0.0);
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'cross_c2_inlet',
        pStart: p0,
        pEnd: p1,
        outwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        isStartEnd: true,
        includeEndCapStart: true,
      );

      final double cArcX = southWidth / 2.0 + radius;
      final double cArcY = -eastWidth / 2.0 - radius;
      CadPoint3D pPrev = p1;
      for (int s = 0; s < cornerSegs; s++) {
        final double a = (math.pi / 2.0) * (s + 1) / cornerSegs;
        final pNext = CadPoint3D(cArcX - radius * math.cos(a), cArcY + radius * math.cos(a), 0.0);
        final dS = CadPoint3D(pNext.x - pPrev.x, pNext.y - pPrev.y, 0.0);
        final lenS = math.sqrt(dS.x * dS.x + dS.y * dS.y);
        final tS = lenS > 1e-4 ? CadPoint3D(dS.x / lenS, dS.y / lenS, 0.0) : const CadPoint3D(0.0, -1.0, 0.0);
        _buildCChannelRailSegment(
          polygons: polygons,
          thicknessPolygons: thicknessPolygons,
          segmentId: 'cross_c2_miter_$s',
          pStart: pPrev,
          pEnd: pNext,
          outwardNormal: CadPoint3D(-tS.y, tS.x, 0.0),
          height: H,
          flangeWidth: F,
          thickness: T,
          color: railColor,
          flangeOutward: isFlangeOutward,
        );
        pPrev = pNext;
      }

      final pEnd = CadPoint3D(southWidth / 2.0, -lSouth, 0.0);
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'cross_c2_outlet',
        pStart: pPrev,
        pEnd: pEnd,
        outwardNormal: const CadPoint3D(1.0, 0.0, 0.0),
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        isFinalEnd: true,
        includeEndCapEnd: true,
      );
    }

    // Corner 3: South-West (Port 4 South left to Port 1 West bottom)
    {
      final p0 = CadPoint3D(-southWidth / 2.0, -lSouth, 0.0);
      final p1 = CadPoint3D(-southWidth / 2.0, -westWidth / 2.0 - radius, 0.0);
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'cross_c3_inlet',
        pStart: p0,
        pEnd: p1,
        outwardNormal: const CadPoint3D(-1.0, 0.0, 0.0),
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        isStartEnd: true,
        includeEndCapStart: true,
      );

      final double cArcX = -southWidth / 2.0 - radius;
      final double cArcY = -westWidth / 2.0 - radius;
      CadPoint3D pPrev = p1;
      for (int s = 0; s < cornerSegs; s++) {
        final double a = (math.pi / 2.0) * (s + 1) / cornerSegs;
        final pNext = CadPoint3D(cArcX + radius * math.cos(a), cArcY + radius * math.sin(a), 0.0);
        final dS = CadPoint3D(pNext.x - pPrev.x, pNext.y - pPrev.y, 0.0);
        final lenS = math.sqrt(dS.x * dS.x + dS.y * dS.y);
        final tS = lenS > 1e-4 ? CadPoint3D(dS.x / lenS, dS.y / lenS, 0.0) : const CadPoint3D(0.0, 1.0, 0.0);
        _buildCChannelRailSegment(
          polygons: polygons,
          thicknessPolygons: thicknessPolygons,
          segmentId: 'cross_c3_miter_$s',
          pStart: pPrev,
          pEnd: pNext,
          outwardNormal: CadPoint3D(-tS.y, tS.x, 0.0),
          height: H,
          flangeWidth: F,
          thickness: T,
          color: railColor,
          flangeOutward: isFlangeOutward,
        );
        pPrev = pNext;
      }

      final pEnd = CadPoint3D(-lWest, -westWidth / 2.0, 0.0);
      _buildCChannelRailSegment(
        polygons: polygons,
        thicknessPolygons: thicknessPolygons,
        segmentId: 'cross_c3_outlet',
        pStart: pPrev,
        pEnd: pEnd,
        outwardNormal: const CadPoint3D(0.0, -1.0, 0.0),
        height: H,
        flangeWidth: F,
        thickness: T,
        color: railColor,
        flangeOutward: isFlangeOutward,
        isFinalEnd: true,
        includeEndCapEnd: true,
      );
    }

    // 5. Cross rungs (on each of the 4 arms, non-overlapping)
    final double pitch = params.intermediateTargetPitch > 50.0 ? params.intermediateTargetPitch : 250.0;

    // West Arm Rungs (spanning Y)
    final double westArmSpan = lWest - (math.max(northWidth, southWidth) / 2.0) - radius - 20.0;
    if (westArmSpan > 50.0) {
      final int count = math.max(1, (westArmSpan / pitch).round());
      for (int i = 0; i < count; i++) {
        final double x = -lWest + 40.0 + (westArmSpan * (i + 0.5) / count);
        final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
          rungId: 'cross_west_rung_$i',
          centerTop: CadPoint3D(x, 0.0, zRungCenter + 10.0),
          lengthDir: const CadPoint3D(0.0, 1.0, 0.0),
          widthDir: const CadPoint3D(1.0, 0.0, 0.0),
          upDir: const CadPoint3D(0.0, 0.0, 1.0),
          interiorHalfSpan: westWidth / 2.0,
          rungW: 40.0,
          rungDepth: 20.0,
          thickness: T,
          color: rungColor,
          isPassThrough: isPassThrough,
          outsideProjection: isPassThrough ? params.outsideWeldProjection : 0.0,
          slotLength: 25.0,
          slotWidth: 14.0,
        );
        polygons.addAll(rungPolys);
      }
    }

    // East Arm Rungs (spanning Y)
    final double eastArmSpan = lEast - (math.max(northWidth, southWidth) / 2.0) - radius - 20.0;
    if (eastArmSpan > 50.0) {
      final int count = math.max(1, (eastArmSpan / pitch).round());
      for (int i = 0; i < count; i++) {
        final double x = lEast - 40.0 - (eastArmSpan * (i + 0.5) / count);
        final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
          rungId: 'cross_east_rung_$i',
          centerTop: CadPoint3D(x, 0.0, zRungCenter + 10.0),
          lengthDir: const CadPoint3D(0.0, 1.0, 0.0),
          widthDir: const CadPoint3D(1.0, 0.0, 0.0),
          upDir: const CadPoint3D(0.0, 0.0, 1.0),
          interiorHalfSpan: eastWidth / 2.0,
          rungW: 40.0,
          rungDepth: 20.0,
          thickness: T,
          color: rungColor,
          isPassThrough: isPassThrough,
          outsideProjection: isPassThrough ? params.outsideWeldProjection : 0.0,
          slotLength: 25.0,
          slotWidth: 14.0,
        );
        polygons.addAll(rungPolys);
      }
    }

    // North Arm Rungs (spanning X)
    final double northArmSpan = lNorth - (math.max(westWidth, eastWidth) / 2.0) - radius - 20.0;
    if (northArmSpan > 50.0) {
      final int count = math.max(1, (northArmSpan / pitch).round());
      for (int i = 0; i < count; i++) {
        final double y = lNorth - 40.0 - (northArmSpan * (i + 0.5) / count);
        final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
          rungId: 'cross_north_rung_$i',
          centerTop: CadPoint3D(0.0, y, zRungCenter + 10.0),
          lengthDir: const CadPoint3D(1.0, 0.0, 0.0),
          widthDir: const CadPoint3D(0.0, 1.0, 0.0),
          upDir: const CadPoint3D(0.0, 0.0, 1.0),
          interiorHalfSpan: northWidth / 2.0,
          rungW: 40.0,
          rungDepth: 20.0,
          thickness: T,
          color: rungColor,
          isPassThrough: isPassThrough,
          outsideProjection: isPassThrough ? params.outsideWeldProjection : 0.0,
          slotLength: 25.0,
          slotWidth: 14.0,
        );
        polygons.addAll(rungPolys);
      }
    }

    // South Arm Rungs (spanning X)
    final double southArmSpan = lSouth - (math.max(westWidth, eastWidth) / 2.0) - radius - 20.0;
    if (southArmSpan > 50.0) {
      final int count = math.max(1, (southArmSpan / pitch).round());
      for (int i = 0; i < count; i++) {
        final double y = -lSouth + 40.0 + (southArmSpan * (i + 0.5) / count);
        final rungPolys = LadderAssemblyGenerator.generateOrientedSlottedRung3DPolygons(
          rungId: 'cross_south_rung_$i',
          centerTop: CadPoint3D(0.0, y, zRungCenter + 10.0),
          lengthDir: const CadPoint3D(1.0, 0.0, 0.0),
          widthDir: const CadPoint3D(0.0, 1.0, 0.0),
          upDir: const CadPoint3D(0.0, 0.0, 1.0),
          interiorHalfSpan: southWidth / 2.0,
          rungW: 40.0,
          rungDepth: 20.0,
          thickness: T,
          color: rungColor,
          isPassThrough: isPassThrough,
          outsideProjection: isPassThrough ? params.outsideWeldProjection : 0.0,
          slotLength: 25.0,
          slotWidth: 14.0,
        );
        polygons.addAll(rungPolys);
      }
    }

    final double totalW = lWest + lEast;
    final double totalL = lNorth + lSouth;
    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: totalW,
      boundLength: totalL,
      boundHeight: H,
      center: CadPoint3D(0.0, 0.0, H / 2.0),
    );
  }
}
