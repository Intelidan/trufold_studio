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
  static const double defaultLeadIn = 75.0;  // Tangent lead-in for splice couplers

  // Colors for 3D meshes
  static const Color railColor = Color(0xFF90A4AE);
  static const Color rungColor = Color(0xFF78909C);
  static const Color weldColor = Color(0xFF64748B);

  // ===========================================================================
  // 1. HORIZONTAL BENDS (Radial Spokes Pattern)
  // ===========================================================================

  static DsfLadderAssembly generateHorizontalBend({
    required double angleDeg,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) {
    final double angleRad = angleDeg * math.pi / 180.0;
    final double rIn = radiusMm;
    final double rOut = radiusMm + params.width;
    final double rMid = radiusMm + (params.width / 2.0);
    final double leadIn = defaultLeadIn;

    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented
        ? ((angleDeg >= 75.0) ? 4 : ((angleDeg >= 35.0) ? 3 : 2))
        : 16;

    final double lArcMid = rMid * angleRad;
    final int rungCount = isSegmented
        ? segments
        : math.max(2, (lArcMid / params.intermediateTargetPitch).round() + 1);

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

          c3D = CadPoint3D(
            (rMid * math.cos(angleRad)) + (outletT.x * dMid),
            (rMid * math.sin(angleRad)) + (outletT.y * dMid),
            rungCenterZ,
          );
          wIn = CadPoint3D(
            (rIn * math.cos(angleRad)) + (outletT.x * dMid),
            (rIn * math.sin(angleRad)) + (outletT.y * dMid),
            rungCenterZ,
          );
          wOut = CadPoint3D(
            (rOut * math.cos(angleRad)) + (outletT.x * dMid),
            (rOut * math.sin(angleRad)) + (outletT.y * dMid),
            rungCenterZ,
          );
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

        rungs.add(LadderRungInstance(
          index: i,
          stationX: rMid * alpha,
          center3D: c3D,
          cutLength: rungCutLength,
          orientationAngleRad: alpha,
          jointMethod: params.jointMethod,
        ));

        joints.add(LadderJointInstance(
          rungIndex: i,
          railSide: 'left',
          stationX: stIn,
          weldCenter3D: wIn,
          slotCenter2D: CadPoint2D(stIn, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ));

        joints.add(LadderJointInstance(
          rungIndex: i,
          railSide: 'right',
          stationX: stOut,
          weldCenter3D: wOut,
          slotCenter2D: CadPoint2D(stOut, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ));
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

        rungs.add(LadderRungInstance(
          index: i,
          stationX: rMid * alpha,
          center3D: CadPoint3D(cx, cy, rungCenterZ),
          cutLength: rungCutLength,
          orientationAngleRad: alpha,
          jointMethod: params.jointMethod,
        ));

        joints.add(LadderJointInstance(
          rungIndex: i,
          railSide: 'left',
          stationX: stIn,
          weldCenter3D: CadPoint3D(rIn * math.cos(alpha), rIn * math.sin(alpha), rungCenterZ),
          slotCenter2D: CadPoint2D(stIn, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ));

        joints.add(LadderJointInstance(
          rungIndex: i,
          railSide: 'right',
          stationX: stOut,
          weldCenter3D: CadPoint3D(rOut * math.cos(alpha), rOut * math.sin(alpha), rungCenterZ),
          slotCenter2D: CadPoint2D(stOut, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ));
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

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(
      rungCutLength: rungCutLength,
      material: material,
    );

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
    final mesh3D = _buildHorizontalBendMesh(
      angleRad: angleRad,
      rIn: rIn,
      rOut: rOut,
      leadIn: leadIn,
      rungs: rungs,
      joints: joints,
      params: params,
    );

    // BOM
    final double totalAreaM2 = (innerRailLength + outerRailLength) / 1000.0 * (railFlatWidth / 1000.0) +
        (rungCount * (rungCutLength / 1000.0) * (rungBlankWidth / 1000.0));
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
      productName: 'Cable Ladder ${angleDeg.round()}° ${stylePrefix}Horizontal Bend ${params.width.round()}×${params.height.round()}mm (R=${radiusMm.round()}mm)',
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
    final int segments = isSegmented
        ? ((angleDeg >= 75.0) ? 4 : ((angleDeg >= 35.0) ? 3 : 2))
        : 16;

    final double arcLength = r * angleRad;
    final int rungCount = isSegmented
        ? segments
        : math.max(2, (arcLength / params.intermediateTargetPitch).round() + 1);

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

        rungs.add(LadderRungInstance(
          index: i,
          stationX: st,
          center3D: cXz,
          cutLength: rungCutLength,
          orientationAngleRad: alpha,
          jointMethod: params.jointMethod,
        ));

        joints.add(LadderJointInstance(
          rungIndex: i,
          railSide: 'left',
          stationX: st,
          weldCenter3D: CadPoint3D(cXz.x, -halfW, cXz.z),
          slotCenter2D: CadPoint2D(st, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ));

        joints.add(LadderJointInstance(
          rungIndex: i,
          railSide: 'right',
          stationX: st,
          weldCenter3D: CadPoint3D(cXz.x, halfW, cXz.z),
          slotCenter2D: CadPoint2D(st, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ));
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
        final double rz = isInsideRiser
            ? r * (1.0 - math.cos(alpha)) + 20.0
            : -(r * (1.0 - math.cos(alpha))) + 20.0;
        final double st = leadIn + (r * alpha);
        stations.add(st);

        rungs.add(LadderRungInstance(
          index: i,
          stationX: st,
          center3D: CadPoint3D(rx, 0.0, rz),
          cutLength: rungCutLength,
          orientationAngleRad: alpha,
          jointMethod: params.jointMethod,
        ));

        joints.add(LadderJointInstance(
          rungIndex: i,
          railSide: 'left',
          stationX: st,
          weldCenter3D: CadPoint3D(rx, -halfW, rz),
          slotCenter2D: CadPoint2D(st, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ));

        joints.add(LadderJointInstance(
          rungIndex: i,
          railSide: 'right',
          stationX: st,
          weldCenter3D: CadPoint3D(rx, halfW, rz),
          slotCenter2D: CadPoint2D(st, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ));
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

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(
      rungCutLength: rungCutLength,
      material: material,
    );

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
        center: CadPoint3D(
          (pOutletBottom.x + pOutletTop.x) / 2.0,
          0.0,
          (pOutletBottom.z + pOutletTop.z) / 2.0,
        ),
        normal: tExit,
        width: params.width,
        height: params.height,
      ),
    ];

    final mesh3D = _buildRiserMesh(
      angleRad: angleRad,
      radius: r,
      leadIn: leadIn,
      isInsideRiser: isInsideRiser,
      rungs: rungs,
      joints: joints,
      params: params,
    );

    final double totalAreaM2 = 2 * (railDevLength / 1000.0) * (railFlatWidth / 1000.0) +
        (rungCount * (rungCutLength / 1000.0) * (rungBlankWidth / 1000.0));
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

      rungs.add(LadderRungInstance(
        index: i,
        stationX: x,
        center3D: CadPoint3D(x, yCenter, 20.0),
        cutLength: cutLen,
        jointMethod: params.jointMethod,
      ));

      joints.add(LadderJointInstance(
        rungIndex: i,
        railSide: 'left',
        stationX: x,
        weldCenter3D: CadPoint3D(x, yLeft, 20.0),
        slotCenter2D: CadPoint2D(x, params.flangeWidth + 20.0),
        hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
        outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
      ));

      joints.add(LadderJointInstance(
        rungIndex: i,
        railSide: 'right',
        stationX: x,
        weldCenter3D: CadPoint3D(x, yRight, 20.0),
        slotCenter2D: CadPoint2D(x, params.flangeWidth + 20.0),
        hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
        outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
      ));
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
    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(
      rungCutLength: avgRungLength,
      material: material,
    );

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

    final mesh3D = _buildReducerMesh(
      width1: width1,
      width2: width2,
      length: length,
      leadIn: leadIn,
      alignment: alignment,
      stations: stations,
      params: params,
    );

    final double totalAreaM2 = 2 * (length / 1000.0) * (railFlatWidth / 1000.0) +
        (rungCount * (avgRungLength / 1000.0) * (rungBlankWidth / 1000.0));
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

  static DsfLadderAssembly generateTee({
    required double mainWidth,
    required double branchWidth,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) {
    final double leadIn = defaultLeadIn;
    final double r = radiusMm;
    final double mainLength = (2 * leadIn) + (2 * r) + branchWidth;
    final double branchReach = leadIn + r + (mainWidth / 2.0);

    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);
    final double railFlatWidth = params.height + (2 * params.flangeWidth);

    // Spine rungs along main run
    final int spineRungCount = math.max(3, (mainLength / params.intermediateTargetPitch).round() + 1);
    final double rungCutLengthMain = params.physicalRungCutLength;

    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];

    for (int i = 0; i < spineRungCount; i++) {
      final double x = leadIn + ((mainLength - 2 * leadIn) * (i + 0.5) / spineRungCount);
      rungs.add(LadderRungInstance(
        index: i,
        stationX: x,
        center3D: CadPoint3D(x, 0.0, 20.0),
        cutLength: rungCutLengthMain,
        jointMethod: params.jointMethod,
      ));

      joints.add(LadderJointInstance(
        rungIndex: i,
        railSide: 'back',
        stationX: x,
        weldCenter3D: CadPoint3D(x, -mainWidth / 2.0, 20.0),
        hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
      ));
    }

    // Branch rungs
    final int branchRungCount = math.max(1, (r / params.intermediateTargetPitch).round());
    final double rungCutLengthBranch = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? branchWidth
        : branchWidth + (2 * params.thickness) + (2 * params.outsideWeldProjection);

    for (int j = 0; j < branchRungCount; j++) {
      final double y = (mainWidth / 2.0) + (r * (j + 0.5) / branchRungCount);
      final int idx = spineRungCount + j;
      rungs.add(LadderRungInstance(
        index: idx,
        stationX: y,
        center3D: CadPoint3D(mainLength / 2.0, y, 20.0),
        cutLength: rungCutLengthBranch,
        orientationAngleRad: math.pi / 2.0,
        jointMethod: params.jointMethod,
      ));
    }

    final leftRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'back_straight',
      name: 'Tee Back Rail Blank',
      params: params,
      railFlatLength: mainLength,
      railFlatWidth: railFlatWidth,
      stations: List.generate(spineRungCount, (i) => leadIn + ((mainLength - 2 * leadIn) * (i + 0.5) / spineRungCount)),
      slotDim: params.railSlotDimensions,
      material: material,
    );

    final cornerRailLength = (2 * leadIn) + (r * math.pi / 2.0);
    final rightRailPart = LadderAssemblyGenerator.generateCustomRailFlatBlank(
      railSide: 'corner_curved',
      name: 'Tee Corner Curved Rail Blank',
      params: params,
      railFlatLength: cornerRailLength,
      railFlatWidth: railFlatWidth,
      stations: [leadIn + (r * math.pi / 4.0)],
      slotDim: params.railSlotDimensions,
      material: material,
    );

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(
      rungCutLength: rungCutLengthMain,
      material: material,
    );

    final splicePorts = <CmsPhysicalPort>[
      CmsPhysicalPort(
        id: 'port_1_main_in',
        index: 1,
        center: CadPoint3D(0.0, 0.0, params.height / 2.0),
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        width: mainWidth,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_2_main_out',
        index: 2,
        center: CadPoint3D(mainLength, 0.0, params.height / 2.0),
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        width: mainWidth,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_3_branch',
        index: 3,
        center: CadPoint3D(mainLength / 2.0, branchReach, params.height / 2.0),
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        width: branchWidth,
        height: params.height,
      ),
    ];

    final mesh3D = _buildTeeMesh(
      mainWidth: mainWidth,
      branchWidth: branchWidth,
      radius: r,
      mainLength: mainLength,
      branchReach: branchReach,
      leadIn: leadIn,
      rungs: rungs,
      params: params,
    );

    final int totalRungCount = rungs.length;
    final double totalAreaM2 = (mainLength + 2 * cornerRailLength) / 1000.0 * (railFlatWidth / 1000.0) +
        (totalRungCount * (rungCutLengthMain / 1000.0) * (rungBlankWidth / 1000.0));
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
    return DsfLadderAssembly(
      id: 'LAD-TEE-${params.accessoryStyle.name.toUpperCase()}-${mainWidth.round()}X${branchWidth.round()}X${params.height.round()}',
      productName: 'Cable Ladder ${stylePrefix}Tee ${mainWidth.round()}×${branchWidth.round()}×${params.height.round()}mm (R=${radiusMm.round()}mm)',
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

  static DsfLadderAssembly generateCross({
    required double mainWidth,
    required double branchWidth,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) {
    final double leadIn = defaultLeadIn;
    final double r = radiusMm;
    final double spanX = (2 * leadIn) + (2 * r) + branchWidth;
    final double spanY = (2 * leadIn) + (2 * r) + mainWidth;

    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);
    final double railFlatWidth = params.height + (2 * params.flangeWidth);

    final int rungsPerArm = math.max(1, (r / params.intermediateTargetPitch).round());
    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];

    int idx = 0;
    // West & East arm rungs
    final double cutLenX = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? mainWidth
        : mainWidth + (2 * params.thickness) + (2 * params.outsideWeldProjection);

    for (int i = 0; i < rungsPerArm; i++) {
      final double xW = leadIn + (r * (i + 0.5) / rungsPerArm);
      rungs.add(LadderRungInstance(index: idx++, stationX: xW, center3D: CadPoint3D(xW, 0.0, 20.0), cutLength: cutLenX, jointMethod: params.jointMethod));
      final double xE = spanX - leadIn - (r * (i + 0.5) / rungsPerArm);
      rungs.add(LadderRungInstance(index: idx++, stationX: xE, center3D: CadPoint3D(xE, 0.0, 20.0), cutLength: cutLenX, jointMethod: params.jointMethod));
    }

    // South & North arm rungs
    final double cutLenY = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? branchWidth
        : branchWidth + (2 * params.thickness) + (2 * params.outsideWeldProjection);

    for (int i = 0; i < rungsPerArm; i++) {
      final double yS = -spanY / 2.0 + leadIn + (r * (i + 0.5) / rungsPerArm);
      rungs.add(LadderRungInstance(index: idx++, stationX: yS, center3D: CadPoint3D(spanX / 2.0, yS, 20.0), cutLength: cutLenY, orientationAngleRad: math.pi / 2.0, jointMethod: params.jointMethod));
      final double yN = spanY / 2.0 - leadIn - (r * (i + 0.5) / rungsPerArm);
      rungs.add(LadderRungInstance(index: idx++, stationX: yN, center3D: CadPoint3D(spanX / 2.0, yN, 20.0), cutLength: cutLenY, orientationAngleRad: math.pi / 2.0, jointMethod: params.jointMethod));
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

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(
      rungCutLength: cutLenX,
      material: material,
    );

    final splicePorts = <CmsPhysicalPort>[
      CmsPhysicalPort(id: 'port_1_west', index: 1, center: CadPoint3D(0.0, 0.0, params.height / 2.0), normal: const CadPoint3D(-1.0, 0.0, 0.0), width: mainWidth, height: params.height),
      CmsPhysicalPort(id: 'port_2_east', index: 2, center: CadPoint3D(spanX, 0.0, params.height / 2.0), normal: const CadPoint3D(1.0, 0.0, 0.0), width: mainWidth, height: params.height),
      CmsPhysicalPort(id: 'port_3_north', index: 3, center: CadPoint3D(spanX / 2.0, spanY / 2.0, params.height / 2.0), normal: const CadPoint3D(0.0, 1.0, 0.0), width: branchWidth, height: params.height),
      CmsPhysicalPort(id: 'port_4_south', index: 4, center: CadPoint3D(spanX / 2.0, -spanY / 2.0, params.height / 2.0), normal: const CadPoint3D(0.0, -1.0, 0.0), width: branchWidth, height: params.height),
    ];

    final mesh3D = _buildCrossMesh(
      mainWidth: mainWidth,
      branchWidth: branchWidth,
      radius: r,
      spanX: spanX,
      spanY: spanY,
      leadIn: leadIn,
      rungs: rungs,
      params: params,
    );

    final int totalRungCount = rungs.length;
    final double totalAreaM2 = 4 * (cornerRailLength / 1000.0) * (railFlatWidth / 1000.0) +
        (totalRungCount * (cutLenX / 1000.0) * (rungBlankWidth / 1000.0));
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
    return DsfLadderAssembly(
      id: 'LAD-CROSS-${params.accessoryStyle.name.toUpperCase()}-${mainWidth.round()}X${branchWidth.round()}X${params.height.round()}',
      productName: 'Cable Ladder ${stylePrefix}Cross ${mainWidth.round()}×${branchWidth.round()}×${params.height.round()}mm (R=${radiusMm.round()}mm)',
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
    final int segments = isSegmented
        ? ((angleRad >= 1.3) ? 4 : ((angleRad >= 0.6) ? 3 : 2))
        : 16;

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

    final pOutletIn = CadPoint3D(
      (rIn * math.cos(angleRad)) + (outletT.x * leadIn),
      (rIn * math.sin(angleRad)) + (outletT.y * leadIn),
      0.0,
    );
    final pOutletOut = CadPoint3D(
      (rOut * math.cos(angleRad)) + (outletT.x * leadIn),
      (rOut * math.sin(angleRad)) + (outletT.y * leadIn),
      0.0,
    );
    final pOutletInF = CadPoint3D(
      (rInF * math.cos(angleRad)) + (outletT.x * leadIn),
      (rInF * math.sin(angleRad)) + (outletT.y * leadIn),
      0.0,
    );
    final pOutletOutF = CadPoint3D(
      (rOutF * math.cos(angleRad)) + (outletT.x * leadIn),
      (rOutF * math.sin(angleRad)) + (outletT.y * leadIn),
      0.0,
    );

    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;
    final bool notchOuter = isSegmented && params.flangeDirection == LadderFlangeDirection.inside;
    final bool notchInner = isSegmented && params.flangeDirection == LadderFlangeDirection.outside;
    final double T = (params.thickness > 0.1 && params.thickness < 10.0) ? params.thickness : 2.0;

    final segList = <({
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
    })>[];

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
      polygons.add(CadFoldedPolygon3D(
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
      ));
      // Outer Bottom Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'inner_rail_bottom_flange_$s',
        vertices: [
          CadPoint3D(pStartIn.x, pStartIn.y, 0.0),
          CadPoint3D(pStartInF.x, pStartInF.y, 0.0),
          CadPoint3D(pEndInF.x, pEndInF.y, 0.0),
          CadPoint3D(pEndIn.x, pEndIn.y, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: railColor,
      ));
      // Outer Top Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'inner_rail_top_flange_$s',
        vertices: [
          CadPoint3D(pStartIn.x, pStartIn.y, H),
          CadPoint3D(pEndIn.x, pEndIn.y, H),
          CadPoint3D(pEndInF.x, pEndInF.y, H),
          CadPoint3D(pStartInF.x, pStartInF.y, H),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: railColor,
      ));

      // Inner Web
      polygons.add(CadFoldedPolygon3D(
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
      ));
      // Inner Bottom Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'inner_rail_bottom_flange_inner_$s',
        vertices: [
          CadPoint3D(pStartInInner.x, pStartInInner.y, T),
          CadPoint3D(pEndInInner.x, pEndInInner.y, T),
          CadPoint3D(pEndInF.x, pEndInF.y, T),
          CadPoint3D(pStartInF.x, pStartInF.y, T),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: railColor,
      ));
      // Inner Top Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'inner_rail_top_flange_inner_$s',
        vertices: [
          CadPoint3D(pStartInInner.x, pStartInInner.y, H - T),
          CadPoint3D(pStartInF.x, pStartInF.y, H - T),
          CadPoint3D(pEndInF.x, pEndInF.y, H - T),
          CadPoint3D(pEndInInner.x, pEndInInner.y, H - T),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: railColor,
      ));

      // Flange Lips (Rims)
      thicknessPolygons.add(CadFoldedPolygon3D(
        faceId: 'RIM_inner_top_flange_lip_$s',
        vertices: [
          CadPoint3D(pStartInF.x, pStartInF.y, H - T),
          CadPoint3D(pEndInF.x, pEndInF.y, H - T),
          CadPoint3D(pEndInF.x, pEndInF.y, H),
          CadPoint3D(pStartInF.x, pStartInF.y, H),
        ],
        normal: CadPoint3D(nIn.x * fSign, nIn.y * fSign, 0.0),
        color: railColor,
      ));
      thicknessPolygons.add(CadFoldedPolygon3D(
        faceId: 'RIM_inner_bottom_flange_lip_$s',
        vertices: [
          CadPoint3D(pStartInF.x, pStartInF.y, 0.0),
          CadPoint3D(pStartInF.x, pStartInF.y, T),
          CadPoint3D(pEndInF.x, pEndInF.y, T),
          CadPoint3D(pEndInF.x, pEndInF.y, 0.0),
        ],
        normal: CadPoint3D(nIn.x * fSign, nIn.y * fSign, 0.0),
        color: railColor,
      ));

      // V-Notch Rims on Inner Rail if notchInner
      if (notchInner) {
        if (seg.hasNotchStart) {
          thicknessPolygons.add(CadFoldedPolygon3D(
            faceId: 'RIM_inner_top_notch_start_$s',
            vertices: [
              CadPoint3D(pStartIn.x, pStartIn.y, H),
              CadPoint3D(pStartInF.x, pStartInF.y, H),
              CadPoint3D(pStartInF.x, pStartInF.y, H - T),
              CadPoint3D(pStartIn.x, pStartIn.y, H - T),
            ],
            normal: CadPoint3D(-tIn.x, -tIn.y, 0.0),
            color: railColor,
          ));
          thicknessPolygons.add(CadFoldedPolygon3D(
            faceId: 'RIM_inner_bottom_notch_start_$s',
            vertices: [
              CadPoint3D(pStartIn.x, pStartIn.y, 0.0),
              CadPoint3D(pStartIn.x, pStartIn.y, T),
              CadPoint3D(pStartInF.x, pStartInF.y, T),
              CadPoint3D(pStartInF.x, pStartInF.y, 0.0),
            ],
            normal: CadPoint3D(-tIn.x, -tIn.y, 0.0),
            color: railColor,
          ));
        }
        if (seg.hasNotchEnd) {
          thicknessPolygons.add(CadFoldedPolygon3D(
            faceId: 'RIM_inner_top_notch_end_$s',
            vertices: [
              CadPoint3D(pEndIn.x, pEndIn.y, H - T),
              CadPoint3D(pEndInF.x, pEndInF.y, H - T),
              CadPoint3D(pEndInF.x, pEndInF.y, H),
              CadPoint3D(pEndIn.x, pEndIn.y, H),
            ],
            normal: tIn,
            color: railColor,
          ));
          thicknessPolygons.add(CadFoldedPolygon3D(
            faceId: 'RIM_inner_bottom_notch_end_$s',
            vertices: [
              CadPoint3D(pEndIn.x, pEndIn.y, T),
              CadPoint3D(pEndIn.x, pEndIn.y, 0.0),
              CadPoint3D(pEndInF.x, pEndInF.y, 0.0),
              CadPoint3D(pEndInF.x, pEndInF.y, T),
            ],
            normal: tIn,
            color: railColor,
          ));
        }
      }

      // --- 2. OUTER RAIL SEGMENT (Thick C-Channel) ---
      // Outer Web
      polygons.add(CadFoldedPolygon3D(
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
      ));
      // Outer Bottom Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'outer_rail_bottom_flange_$s',
        vertices: [
          CadPoint3D(pStartOut.x, pStartOut.y, 0.0),
          CadPoint3D(pEndOut.x, pEndOut.y, 0.0),
          CadPoint3D(pEndOutF.x, pEndOutF.y, 0.0),
          CadPoint3D(pStartOutF.x, pStartOutF.y, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: railColor,
      ));
      // Outer Top Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'outer_rail_top_flange_$s',
        vertices: [
          CadPoint3D(pStartOut.x, pStartOut.y, H),
          CadPoint3D(pStartOutF.x, pStartOutF.y, H),
          CadPoint3D(pEndOutF.x, pEndOutF.y, H),
          CadPoint3D(pEndOut.x, pEndOut.y, H),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: railColor,
      ));

      // Inner Web
      polygons.add(CadFoldedPolygon3D(
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
      ));
      // Inner Bottom Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'outer_rail_bottom_flange_inner_$s',
        vertices: [
          CadPoint3D(pStartOutInner.x, pStartOutInner.y, T),
          CadPoint3D(pStartOutF.x, pStartOutF.y, T),
          CadPoint3D(pEndOutF.x, pEndOutF.y, T),
          CadPoint3D(pEndOutInner.x, pEndOutInner.y, T),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: railColor,
      ));
      // Inner Top Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'outer_rail_top_flange_inner_$s',
        vertices: [
          CadPoint3D(pStartOutInner.x, pStartOutInner.y, H - T),
          CadPoint3D(pEndOutInner.x, pEndOutInner.y, H - T),
          CadPoint3D(pEndOutF.x, pEndOutF.y, H - T),
          CadPoint3D(pStartOutF.x, pStartOutF.y, H - T),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: railColor,
      ));

      // Flange Lips (Rims)
      thicknessPolygons.add(CadFoldedPolygon3D(
        faceId: 'RIM_outer_top_flange_lip_$s',
        vertices: [
          CadPoint3D(pStartOutF.x, pStartOutF.y, H - T),
          CadPoint3D(pStartOutF.x, pStartOutF.y, H),
          CadPoint3D(pEndOutF.x, pEndOutF.y, H),
          CadPoint3D(pEndOutF.x, pEndOutF.y, H - T),
        ],
        normal: CadPoint3D(nOut.x * fSign, nOut.y * fSign, 0.0),
        color: railColor,
      ));
      thicknessPolygons.add(CadFoldedPolygon3D(
        faceId: 'RIM_outer_bottom_flange_lip_$s',
        vertices: [
          CadPoint3D(pStartOutF.x, pStartOutF.y, 0.0),
          CadPoint3D(pEndOutF.x, pEndOutF.y, 0.0),
          CadPoint3D(pEndOutF.x, pEndOutF.y, T),
          CadPoint3D(pStartOutF.x, pStartOutF.y, T),
        ],
        normal: CadPoint3D(nOut.x * fSign, nOut.y * fSign, 0.0),
        color: railColor,
      ));

      // V-Notch Rims on Outer Rail if notchOuter
      if (notchOuter) {
        if (seg.hasNotchStart) {
          thicknessPolygons.add(CadFoldedPolygon3D(
            faceId: 'RIM_outer_top_notch_start_$s',
            vertices: [
              CadPoint3D(pStartOut.x, pStartOut.y, H - T),
              CadPoint3D(pStartOutF.x, pStartOutF.y, H - T),
              CadPoint3D(pStartOutF.x, pStartOutF.y, H),
              CadPoint3D(pStartOut.x, pStartOut.y, H),
            ],
            normal: CadPoint3D(-tOut.x, -tOut.y, 0.0),
            color: railColor,
          ));
          thicknessPolygons.add(CadFoldedPolygon3D(
            faceId: 'RIM_outer_bottom_notch_start_$s',
            vertices: [
              CadPoint3D(pStartOut.x, pStartOut.y, 0.0),
              CadPoint3D(pStartOutF.x, pStartOutF.y, 0.0),
              CadPoint3D(pStartOutF.x, pStartOutF.y, T),
              CadPoint3D(pStartOut.x, pStartOut.y, T),
            ],
            normal: CadPoint3D(-tOut.x, -tOut.y, 0.0),
            color: railColor,
          ));
        }
        if (seg.hasNotchEnd) {
          thicknessPolygons.add(CadFoldedPolygon3D(
            faceId: 'RIM_outer_top_notch_end_$s',
            vertices: [
              CadPoint3D(pEndOut.x, pEndOut.y, H),
              CadPoint3D(pEndOutF.x, pEndOutF.y, H),
              CadPoint3D(pEndOutF.x, pEndOutF.y, H - T),
              CadPoint3D(pEndOut.x, pEndOut.y, H - T),
            ],
            normal: tOut,
            color: railColor,
          ));
          thicknessPolygons.add(CadFoldedPolygon3D(
            faceId: 'RIM_outer_bottom_notch_end_$s',
            vertices: [
              CadPoint3D(pEndOut.x, pEndOut.y, T),
              CadPoint3D(pEndOutF.x, pEndOutF.y, T),
              CadPoint3D(pEndOutF.x, pEndOutF.y, 0.0),
              CadPoint3D(pEndOut.x, pEndOut.y, 0.0),
            ],
            normal: tOut,
            color: railColor,
          ));
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
    final int segments = isSegmented
        ? ((angleRad >= 1.3) ? 4 : ((angleRad >= 0.6) ? 3 : 2))
        : 16;

    final tExit = CadPoint3D(math.cos(angleRad), 0.0, isInsideRiser ? math.sin(angleRad) : -math.sin(angleRad));
    final uExit = CadPoint3D(isInsideRiser ? -math.sin(angleRad) : math.sin(angleRad), 0.0, math.cos(angleRad));

    final mBottom = <CadPoint3D>[];
    final mTop = <CadPoint3D>[];

    final pInletBottom = CadPoint3D(-leadIn, 0.0, 0.0);
    final pInletTop = CadPoint3D(-leadIn, 0.0, H);

    final pCircBottom = CadPoint3D(radius * math.sin(angleRad), 0.0, isInsideRiser ? radius * (1.0 - math.cos(angleRad)) : -radius * (1.0 - math.cos(angleRad)));
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

    final riserSegList = <({
      CadPoint3D pbStart,
      CadPoint3D pbEnd,
      CadPoint3D ptStart,
      CadPoint3D ptEnd,
    })>[];

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
        riserSegList.add((
          pbStart: pInletBottom,
          pbEnd: const CadPoint3D(0.0, 0.0, 0.0),
          ptStart: pInletTop,
          ptEnd: CadPoint3D(0.0, 0.0, H),
        ));
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
        riserSegList.add((
          pbStart: pCircBottom,
          pbEnd: pOutletBottom,
          ptStart: ptCircTop,
          ptEnd: pOutletTop,
        ));
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
      polygons.add(CadFoldedPolygon3D(
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
      ));
      // Outer Bottom Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_bottom_flange_l_$s',
        vertices: [
          CadPoint3D(pbStart.x, -halfW, pbStart.z),
          CadPoint3D(pbStart.x, yLf, pbStart.z),
          CadPoint3D(pbEnd.x, yLf, pbEnd.z),
          CadPoint3D(pbEnd.x, -halfW, pbEnd.z),
        ],
        normal: CadPoint3D(-uSeg.x, 0.0, -uSeg.z),
        color: railColor,
      ));
      // Outer Top Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_top_flange_l_$s',
        vertices: [
          CadPoint3D(ptStart.x, -halfW, ptStart.z),
          CadPoint3D(ptEnd.x, -halfW, ptEnd.z),
          CadPoint3D(ptEnd.x, yLf, ptEnd.z),
          CadPoint3D(ptStart.x, yLf, ptStart.z),
        ],
        normal: uSeg,
        color: railColor,
      ));

      // Inner Web (offset +T along Y)
      polygons.add(CadFoldedPolygon3D(
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
      ));
      // Inner Bottom Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_bottom_flange_l_inner_$s',
        vertices: [
          CadPoint3D(pbStart.x + (uSeg.x * T), -halfW + T, pbStart.z + (uSeg.z * T)),
          CadPoint3D(pbEnd.x + (uSeg.x * T), -halfW + T, pbEnd.z + (uSeg.z * T)),
          CadPoint3D(pbEnd.x + (uSeg.x * T), yLf, pbEnd.z + (uSeg.z * T)),
          CadPoint3D(pbStart.x + (uSeg.x * T), yLf, pbStart.z + (uSeg.z * T)),
        ],
        normal: uSeg,
        color: railColor,
      ));
      // Inner Top Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_top_flange_l_inner_$s',
        vertices: [
          CadPoint3D(ptStart.x - (uSeg.x * T), -halfW + T, ptStart.z - (uSeg.z * T)),
          CadPoint3D(ptStart.x - (uSeg.x * T), yLf, ptStart.z - (uSeg.z * T)),
          CadPoint3D(ptEnd.x - (uSeg.x * T), yLf, ptEnd.z - (uSeg.z * T)),
          CadPoint3D(ptEnd.x - (uSeg.x * T), -halfW + T, ptEnd.z - (uSeg.z * T)),
        ],
        normal: CadPoint3D(-uSeg.x, 0.0, -uSeg.z),
        color: railColor,
      ));
      // Flange Lips
      thicknessPolygons.add(CadFoldedPolygon3D(
        faceId: 'RIM_riser_top_lip_l_$s',
        vertices: [
          CadPoint3D(ptStart.x, yLf, ptStart.z),
          CadPoint3D(ptEnd.x, yLf, ptEnd.z),
          CadPoint3D(ptEnd.x - (uSeg.x * T), yLf, ptEnd.z - (uSeg.z * T)),
          CadPoint3D(ptStart.x - (uSeg.x * T), yLf, ptStart.z - (uSeg.z * T)),
        ],
        normal: CadPoint3D(0.0, fSign, 0.0),
        color: railColor,
      ));
      thicknessPolygons.add(CadFoldedPolygon3D(
        faceId: 'RIM_riser_bottom_lip_l_$s',
        vertices: [
          CadPoint3D(pbStart.x, yLf, pbStart.z),
          CadPoint3D(pbStart.x + (uSeg.x * T), yLf, pbStart.z + (uSeg.z * T)),
          CadPoint3D(pbEnd.x + (uSeg.x * T), yLf, pbEnd.z + (uSeg.z * T)),
          CadPoint3D(pbEnd.x, yLf, pbEnd.z),
        ],
        normal: CadPoint3D(0.0, fSign, 0.0),
        color: railColor,
      ));

      // --- RIGHT RAIL (Y = +halfW, Inward = -Y) ---
      // Outer Web
      polygons.add(CadFoldedPolygon3D(
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
      ));
      // Outer Bottom Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_bottom_flange_r_$s',
        vertices: [
          CadPoint3D(pbStart.x, halfW, pbStart.z),
          CadPoint3D(pbEnd.x, halfW, pbEnd.z),
          CadPoint3D(pbEnd.x, yRf, pbEnd.z),
          CadPoint3D(pbStart.x, yRf, pbStart.z),
        ],
        normal: CadPoint3D(-uSeg.x, 0.0, -uSeg.z),
        color: railColor,
      ));
      // Outer Top Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_top_flange_r_$s',
        vertices: [
          CadPoint3D(ptStart.x, halfW, ptStart.z),
          CadPoint3D(ptStart.x, yRf, ptStart.z),
          CadPoint3D(ptEnd.x, yRf, ptEnd.z),
          CadPoint3D(ptEnd.x, halfW, ptEnd.z),
        ],
        normal: uSeg,
        color: railColor,
      ));

      // Inner Web (offset -T along Y)
      polygons.add(CadFoldedPolygon3D(
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
      ));
      // Inner Bottom Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_bottom_flange_r_inner_$s',
        vertices: [
          CadPoint3D(pbStart.x + (uSeg.x * T), halfW - T, pbStart.z + (uSeg.z * T)),
          CadPoint3D(pbStart.x + (uSeg.x * T), yRf, pbStart.z + (uSeg.z * T)),
          CadPoint3D(pbEnd.x + (uSeg.x * T), yRf, pbEnd.z + (uSeg.z * T)),
          CadPoint3D(pbEnd.x + (uSeg.x * T), halfW - T, pbEnd.z + (uSeg.z * T)),
        ],
        normal: uSeg,
        color: railColor,
      ));
      // Inner Top Flange
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_top_flange_r_inner_$s',
        vertices: [
          CadPoint3D(ptStart.x - (uSeg.x * T), halfW - T, ptStart.z - (uSeg.z * T)),
          CadPoint3D(ptEnd.x - (uSeg.x * T), halfW - T, ptEnd.z - (uSeg.z * T)),
          CadPoint3D(ptEnd.x - (uSeg.x * T), yRf, ptEnd.z - (uSeg.z * T)),
          CadPoint3D(ptStart.x - (uSeg.x * T), yRf, ptStart.z - (uSeg.z * T)),
        ],
        normal: CadPoint3D(-uSeg.x, 0.0, -uSeg.z),
        color: railColor,
      ));
      // Flange Lips
      thicknessPolygons.add(CadFoldedPolygon3D(
        faceId: 'RIM_riser_top_lip_r_$s',
        vertices: [
          CadPoint3D(ptStart.x, yRf, ptStart.z),
          CadPoint3D(ptStart.x - (uSeg.x * T), yRf, ptStart.z - (uSeg.z * T)),
          CadPoint3D(ptEnd.x - (uSeg.x * T), yRf, ptEnd.z - (uSeg.z * T)),
          CadPoint3D(ptEnd.x, yRf, ptEnd.z),
        ],
        normal: CadPoint3D(0.0, -fSign, 0.0),
        color: railColor,
      ));
      thicknessPolygons.add(CadFoldedPolygon3D(
        faceId: 'RIM_riser_bottom_lip_r_$s',
        vertices: [
          CadPoint3D(pbStart.x, yRf, pbStart.z),
          CadPoint3D(pbEnd.x, yRf, pbEnd.z),
          CadPoint3D(pbEnd.x + (uSeg.x * T), yRf, pbEnd.z + (uSeg.z * T)),
          CadPoint3D(pbStart.x + (uSeg.x * T), yRf, pbStart.z + (uSeg.z * T)),
        ],
        normal: CadPoint3D(0.0, -fSign, 0.0),
        color: railColor,
      ));
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

    final double totalMaxZ = isInsideRiser
        ? math.max(pOutletTop.z, radius + H)
        : math.max(H, leadIn);
    final double totalBoundHeight = isInsideRiser
        ? (pOutletTop.z + 10.0)
        : (radius + H + 10.0);

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: params.width + (2 * F),
      boundLength: pOutletBottom.x + leadIn,
      boundHeight: math.max(totalBoundHeight, 350.0),
      center: CadPoint3D(pOutletBottom.x / 2.0, 0.0, totalMaxZ / 2.0),
    );
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
    final double H = params.height;
    final double taperL = length - (2 * leadIn);

    // Left and right rail web polygons
    final double yL1 = alignment == 'left' ? -width1 / 2.0 : -width1 / 2.0;
    final double yL2 = alignment == 'left' ? -width1 / 2.0 : (alignment == 'right' ? (width1 / 2.0) - width2 : -width2 / 2.0);

    final double yR1 = alignment == 'right' ? width1 / 2.0 : width1 / 2.0;
    final double yR2 = alignment == 'right' ? width1 / 2.0 : (alignment == 'left' ? (-width1 / 2.0) + width2 : width2 / 2.0);

    // Left rail
    polygons.add(CadFoldedPolygon3D(
      faceId: 'reducer_left_rail',
      vertices: [
        CadPoint3D(0.0, yL1, 0.0),
        CadPoint3D(leadIn, yL1, 0.0),
        CadPoint3D(length - leadIn, yL2, 0.0),
        CadPoint3D(length, yL2, 0.0),
        CadPoint3D(length, yL2, H),
        CadPoint3D(length - leadIn, yL2, H),
        CadPoint3D(leadIn, yL1, H),
        CadPoint3D(0.0, yL1, H),
      ],
      normal: const CadPoint3D(0.0, -1.0, 0.0),
      color: railColor,
    ));

    // Right rail
    polygons.add(CadFoldedPolygon3D(
      faceId: 'reducer_right_rail',
      vertices: [
        CadPoint3D(0.0, yR1, 0.0),
        CadPoint3D(leadIn, yR1, 0.0),
        CadPoint3D(length - leadIn, yR2, 0.0),
        CadPoint3D(length, yR2, 0.0),
        CadPoint3D(length, yR2, H),
        CadPoint3D(length - leadIn, yR2, H),
        CadPoint3D(leadIn, yR1, H),
        CadPoint3D(0.0, yR1, H),
      ],
      normal: const CadPoint3D(0.0, 1.0, 0.0),
      color: railColor,
    ));

    final thicknessPolygons = <CadFoldedPolygon3D>[];
    // Rungs across tapering width
    for (int i = 0; i < stations.length; i++) {
      final double x = stations[i];
      final double t = (x - leadIn) / taperL;
      final double yL = yL1 + (t * (yL2 - yL1));
      final double yR = yR1 + (t * (yR2 - yR1));

      final double yStart = params.jointMethod == LadderRungJointMethod.directInsideWeld ? yL : yL - params.thickness - params.outsideWeldProjection;
      final double yEnd = params.jointMethod == LadderRungJointMethod.directInsideWeld ? yR : yR + params.thickness + params.outsideWeldProjection;
      final double halfCurSpan = (yR - yL).abs() / 2.0;

      final rungPolys = LadderAssemblyGenerator.generateSlottedRung3DPolygons(
        rungId: 'reducer_rung_$i',
        xCenter: x,
        yStart: yStart,
        yEnd: yEnd,
        zTop: 35.0,
        rungW: 40.0,
        rungDepth: 20.0,
        thickness: params.thickness,
        color: rungColor,
        interiorHalfWidth: halfCurSpan,
      );
      polygons.addAll(rungPolys);
    }

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: width1 + (2 * params.flangeWidth),
      boundLength: length,
      boundHeight: H,
      center: CadPoint3D(length / 2.0, 0.0, H / 2.0),
    );
  }

  static FoldedMeshResult _buildTeeMesh({
    required double mainWidth,
    required double branchWidth,
    required double radius,
    required double mainLength,
    required double branchReach,
    required double leadIn,
    required List<LadderRungInstance> rungs,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final double H = params.height;

    // Back continuous rail
    polygons.add(CadFoldedPolygon3D(
      faceId: 'tee_back_rail',
      vertices: [
        CadPoint3D(0.0, -mainWidth / 2.0, 0.0),
        CadPoint3D(mainLength, -mainWidth / 2.0, 0.0),
        CadPoint3D(mainLength, -mainWidth / 2.0, H),
        CadPoint3D(0.0, -mainWidth / 2.0, H),
      ],
      normal: const CadPoint3D(0.0, -1.0, 0.0),
      color: railColor,
    ));

    // Corner curved front rails
    final double xCenterLeft = leadIn + radius;
    final double xCenterRight = mainLength - leadIn - radius;
    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented ? 1 : 8;

    for (int s = 0; s < segments; s++) {
      final double a1 = (math.pi / 2.0) * s / segments;
      final double a2 = (math.pi / 2.0) * (s + 1) / segments;

      // Left branch corner
      final double xL1 = xCenterLeft - (radius * math.cos(a1));
      final double yL1 = (mainWidth / 2.0) + (radius * (1.0 - math.sin(a1)));
      final double xL2 = xCenterLeft - (radius * math.cos(a2));
      final double yL2 = (mainWidth / 2.0) + (radius * (1.0 - math.sin(a2)));

      polygons.add(CadFoldedPolygon3D(
        faceId: 'tee_corner_left_$s',
        vertices: [
          CadPoint3D(xL1, yL1, 0.0),
          CadPoint3D(xL2, yL2, 0.0),
          CadPoint3D(xL2, yL2, H),
          CadPoint3D(xL1, yL1, H),
        ],
        normal: const CadPoint3D(1.0, 1.0, 0.0),
        color: railColor,
      ));

      // Right branch corner
      final double xR1 = xCenterRight + (radius * math.cos(a1));
      final double yR1 = (mainWidth / 2.0) + (radius * (1.0 - math.sin(a1)));
      final double xR2 = xCenterRight + (radius * math.cos(a2));
      final double yR2 = (mainWidth / 2.0) + (radius * (1.0 - math.sin(a2)));

      polygons.add(CadFoldedPolygon3D(
        faceId: 'tee_corner_right_$s',
        vertices: [
          CadPoint3D(xR1, yR1, 0.0),
          CadPoint3D(xR1, yR1, H),
          CadPoint3D(xR2, yR2, H),
          CadPoint3D(xR2, yR2, 0.0),
        ],
        normal: const CadPoint3D(-1.0, 1.0, 0.0),
        color: railColor,
      ));
    }

    // Rungs
    final thicknessPolygons = <CadFoldedPolygon3D>[];
    for (int i = 0; i < rungs.length; i++) {
      final r = rungs[i];
      final bool isBranch = r.orientationAngleRad > 0.1;
      final double halfLen = r.cutLength / 2.0;

      if (!isBranch) {
        final rungPolys = LadderAssemblyGenerator.generateSlottedRung3DPolygons(
          rungId: 'tee_rung_$i',
          xCenter: r.center3D.x,
          yStart: r.center3D.y - halfLen,
          yEnd: r.center3D.y + halfLen,
          zTop: 35.0,
          rungW: 40.0,
          rungDepth: 20.0,
          thickness: params.thickness,
          color: rungColor,
          interiorHalfWidth: halfLen,
        );
        polygons.addAll(rungPolys);
      } else {
        polygons.add(CadFoldedPolygon3D(
          faceId: 'tee_branch_rung_$i',
          vertices: [
            CadPoint3D(r.center3D.x - halfLen, r.center3D.y - 20.0, 35.0),
            CadPoint3D(r.center3D.x + halfLen, r.center3D.y - 20.0, 35.0),
            CadPoint3D(r.center3D.x + halfLen, r.center3D.y + 20.0, 35.0),
            CadPoint3D(r.center3D.x - halfLen, r.center3D.y + 20.0, 35.0),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: rungColor,
        ));
      }
    }

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: mainLength,
      boundLength: branchReach + (mainWidth / 2.0),
      boundHeight: H,
      center: CadPoint3D(mainLength / 2.0, (branchReach - (mainWidth / 2.0)) / 2.0, H / 2.0),
    );
  }

  static FoldedMeshResult _buildCrossMesh({
    required double mainWidth,
    required double branchWidth,
    required double radius,
    required double spanX,
    required double spanY,
    required double leadIn,
    required List<LadderRungInstance> rungs,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final double H = params.height;

    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented ? 1 : 6;
    for (int q = 0; q < 4; q++) {
      final double sgnX = (q == 0 || q == 3) ? 1.0 : -1.0;
      final double sgnY = (q == 0 || q == 1) ? 1.0 : -1.0;
      final double cx = (spanX / 2.0) + (sgnX * ((branchWidth / 2.0) + radius));
      final double cy = (sgnY * ((mainWidth / 2.0) + radius));

      for (int s = 0; s < segments; s++) {
        final double a1 = (math.pi / 2.0) * s / segments;
        final double a2 = (math.pi / 2.0) * (s + 1) / segments;

        final double x1 = cx - (sgnX * radius * math.cos(a1));
        final double y1 = cy - (sgnY * radius * math.sin(a1));
        final double x2 = cx - (sgnX * radius * math.cos(a2));
        final double y2 = cy - (sgnY * radius * math.sin(a2));

        polygons.add(CadFoldedPolygon3D(
          faceId: 'cross_corner_${q}_$s',
          vertices: [
            CadPoint3D(x1, y1, 0.0),
            CadPoint3D(x2, y2, 0.0),
            CadPoint3D(x2, y2, H),
            CadPoint3D(x1, y1, H),
          ],
          normal: CadPoint3D(-sgnX, -sgnY, 0.0),
          color: railColor,
        ));
      }
    }

    final thicknessPolygons = <CadFoldedPolygon3D>[];
    // Cross rungs
    for (int i = 0; i < rungs.length; i++) {
      final r = rungs[i];
      final bool isVertical = r.orientationAngleRad > 0.1;
      final double halfLen = r.cutLength / 2.0;

      if (!isVertical) {
        final rungPolys = LadderAssemblyGenerator.generateSlottedRung3DPolygons(
          rungId: 'cross_rung_$i',
          xCenter: r.center3D.x,
          yStart: r.center3D.y - halfLen,
          yEnd: r.center3D.y + halfLen,
          zTop: 35.0,
          rungW: 40.0,
          rungDepth: 20.0,
          thickness: params.thickness,
          color: rungColor,
          interiorHalfWidth: halfLen,
        );
        polygons.addAll(rungPolys);
      } else {
        polygons.add(CadFoldedPolygon3D(
          faceId: 'cross_vert_rung_$i',
          vertices: [
            CadPoint3D(r.center3D.x - halfLen, r.center3D.y - 20.0, 35.0),
            CadPoint3D(r.center3D.x + halfLen, r.center3D.y - 20.0, 35.0),
            CadPoint3D(r.center3D.x + halfLen, r.center3D.y + 20.0, 35.0),
            CadPoint3D(r.center3D.x - halfLen, r.center3D.y + 20.0, 35.0),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: rungColor,
        ));
      }
    }

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: spanX,
      boundLength: spanY,
      boundHeight: H,
      center: CadPoint3D(spanX / 2.0, 0.0, H / 2.0),
    );
  }
}
