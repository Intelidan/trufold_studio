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

    final double lArcMid = rMid * angleRad;
    final int rungCount = math.max(2, (lArcMid / params.intermediateTargetPitch).round() + 1);

    final double rungCutLength = params.physicalRungCutLength;
    final slotDim = params.railSlotDimensions;
    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);

    // Developed Rail Blank Dimensions
    final double innerRailLength = (2 * leadIn) + (rIn * angleRad);
    final double outerRailLength = (2 * leadIn) + (rOut * angleRad);
    final double railFlatWidth = params.height + (2 * params.flangeWidth);

    // Station positions along inner and outer rails
    final innerStations = <double>[];
    final outerStations = <double>[];
    final rungAngles = <double>[];

    for (int i = 0; i < rungCount; i++) {
      final double alpha = angleRad * (i + 0.5) / rungCount;
      rungAngles.add(alpha);
      innerStations.add(leadIn + (rIn * alpha));
      outerStations.add(leadIn + (rOut * alpha));
    }

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
    );

    final rungPart = LadderAssemblyGenerator.generateCustomRungFlatBlank(
      rungCutLength: rungCutLength,
      material: material,
    );

    // Rung & Joint Instances
    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];
    final double rungCenterZ = 20.0;

    for (int i = 0; i < rungCount; i++) {
      final double alpha = rungAngles[i];
      final double cx = rMid * math.cos(alpha);
      final double cy = rMid * math.sin(alpha);

      rungs.add(LadderRungInstance(
        index: i,
        stationX: rMid * alpha,
        center3D: CadPoint3D(cx, cy, rungCenterZ),
        cutLength: rungCutLength,
        orientationAngleRad: alpha,
        jointMethod: params.jointMethod,
      ));

      // Inner Joint
      joints.add(LadderJointInstance(
        rungIndex: i,
        railSide: 'left',
        stationX: innerStations[i],
        weldCenter3D: CadPoint3D(rIn * math.cos(alpha), rIn * math.sin(alpha), rungCenterZ),
        slotCenter2D: CadPoint2D(innerStations[i], params.flangeWidth + 20.0),
        hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
        outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
      ));

      // Outer Joint
      joints.add(LadderJointInstance(
        rungIndex: i,
        railSide: 'right',
        stationX: outerStations[i],
        weldCenter3D: CadPoint3D(rOut * math.cos(alpha), rOut * math.sin(alpha), rungCenterZ),
        slotCenter2D: CadPoint2D(outerStations[i], params.flangeWidth + 20.0),
        hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
        outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
      ));
    }

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
      rungAngles: rungAngles,
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

    final double arcLength = r * angleRad;
    final int rungCount = math.max(2, (arcLength / params.intermediateTargetPitch).round() + 1);

    final double rungCutLength = params.physicalRungCutLength;
    final slotDim = params.railSlotDimensions;
    final material = SheetMetalMaterial(materialGrade: params.materialName, thicknessMm: params.thickness);

    final double railDevLength = (2 * leadIn) + arcLength;
    final double railFlatWidth = params.height + (2 * params.flangeWidth);

    final stations = <double>[];
    final rungAlphas = <double>[];

    for (int i = 0; i < rungCount; i++) {
      final double alpha = angleRad * (i + 0.5) / rungCount;
      rungAlphas.add(alpha);
      stations.add(leadIn + (r * alpha));
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

    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];
    final double halfW = params.width / 2.0;

    for (int i = 0; i < rungCount; i++) {
      final double alpha = rungAlphas[i];
      final double rx = r * math.sin(alpha);
      final double rz = isInsideRiser
          ? r * (1.0 - math.cos(alpha)) + 20.0
          : -(r * (1.0 - math.cos(alpha))) + 20.0;

      rungs.add(LadderRungInstance(
        index: i,
        stationX: stations[i],
        center3D: CadPoint3D(rx, 0.0, rz),
        cutLength: rungCutLength,
        orientationAngleRad: alpha,
        jointMethod: params.jointMethod,
      ));

      joints.add(LadderJointInstance(
        rungIndex: i,
        railSide: 'left',
        stationX: stations[i],
        weldCenter3D: CadPoint3D(rx, -halfW, rz),
        slotCenter2D: CadPoint2D(stations[i], params.flangeWidth + 20.0),
        hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
        outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
      ));

      joints.add(LadderJointInstance(
        rungIndex: i,
        railSide: 'right',
        stationX: stations[i],
        weldCenter3D: CadPoint3D(rx, halfW, rz),
        slotCenter2D: CadPoint2D(stations[i], params.flangeWidth + 20.0),
        hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
        outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
      ));
    }

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
          (r * math.sin(angleRad)) + (leadIn * math.cos(angleRad)),
          0.0,
          isInsideRiser
              ? (r * (1.0 - math.cos(angleRad))) + (leadIn * math.sin(angleRad)) + (params.height / 2.0)
              : -(r * (1.0 - math.cos(angleRad))) - (leadIn * math.sin(angleRad)) + (params.height / 2.0),
        ),
        normal: CadPoint3D(math.cos(angleRad), 0.0, isInsideRiser ? math.sin(angleRad) : -math.sin(angleRad)),
        width: params.width,
        height: params.height,
      ),
    ];

    final mesh3D = _buildRiserMesh(
      angleRad: angleRad,
      radius: r,
      leadIn: leadIn,
      isInsideRiser: isInsideRiser,
      rungAlphas: rungAlphas,
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
    required List<double> rungAngles,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final double H = params.height;
    final double F = params.flangeWidth;
    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented
        ? ((angleRad >= 1.3) ? 3 : 2)
        : 16;

    // 1. Inner Rail Mesh
    // Lead-in 1: straight tang along Y = -leadIn to Y = 0 at X = rIn
    polygons.add(CadFoldedPolygon3D(
      faceId: 'inner_rail_lead_in',
      vertices: [
        CadPoint3D(rIn, -leadIn, 0.0),
        CadPoint3D(rIn, 0.0, 0.0),
        CadPoint3D(rIn, 0.0, H),
        CadPoint3D(rIn, -leadIn, H),
      ],
      normal: const CadPoint3D(1.0, 0.0, 0.0),
      color: railColor,
    ));

    // Curved segments for inner rail
    for (int s = 0; s < segments; s++) {
      final double a1 = angleRad * s / segments;
      final double a2 = angleRad * (s + 1) / segments;
      final double x1 = rIn * math.cos(a1);
      final double y1 = rIn * math.sin(a1);
      final double x2 = rIn * math.cos(a2);
      final double y2 = rIn * math.sin(a2);

      // Web
      polygons.add(CadFoldedPolygon3D(
        faceId: 'inner_rail_web_$s',
        vertices: [
          CadPoint3D(x1, y1, 0.0),
          CadPoint3D(x2, y2, 0.0),
          CadPoint3D(x2, y2, H),
          CadPoint3D(x1, y1, H),
        ],
        normal: CadPoint3D((math.cos(a1) + math.cos(a2)) / 2, (math.sin(a1) + math.sin(a2)) / 2, 0.0),
        color: railColor,
      ));

      // Flanges (bottom and top)
      final double fSign = params.flangeDirection == LadderFlangeDirection.inside ? 1.0 : -1.0;
      final double rInF = rIn + (fSign * F);
      polygons.add(CadFoldedPolygon3D(
        faceId: 'inner_rail_bottom_flange_$s',
        vertices: [
          CadPoint3D(x1, y1, 0.0),
          CadPoint3D(x2, y2, 0.0),
          CadPoint3D(rInF * math.cos(a2), rInF * math.sin(a2), 0.0),
          CadPoint3D(rInF * math.cos(a1), rInF * math.sin(a1), 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: railColor,
      ));
    }

    // 2. Outer Rail Mesh
    polygons.add(CadFoldedPolygon3D(
      faceId: 'outer_rail_lead_in',
      vertices: [
        CadPoint3D(rOut, -leadIn, 0.0),
        CadPoint3D(rOut, 0.0, 0.0),
        CadPoint3D(rOut, 0.0, H),
        CadPoint3D(rOut, -leadIn, H),
      ],
      normal: const CadPoint3D(-1.0, 0.0, 0.0),
      color: railColor,
    ));

    for (int s = 0; s < segments; s++) {
      final double a1 = angleRad * s / segments;
      final double a2 = angleRad * (s + 1) / segments;
      final double x1 = rOut * math.cos(a1);
      final double y1 = rOut * math.sin(a1);
      final double x2 = rOut * math.cos(a2);
      final double y2 = rOut * math.sin(a2);

      polygons.add(CadFoldedPolygon3D(
        faceId: 'outer_rail_web_$s',
        vertices: [
          CadPoint3D(x1, y1, 0.0),
          CadPoint3D(x1, y1, H),
          CadPoint3D(x2, y2, H),
          CadPoint3D(x2, y2, 0.0),
        ],
        normal: CadPoint3D(-(math.cos(a1) + math.cos(a2)) / 2, -(math.sin(a1) + math.sin(a2)) / 2, 0.0),
        color: railColor,
      ));
    }

    // 3. Radial Spoke Rungs (40x20mm C-channel)
    final double rStart = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? rIn
        : rIn - params.thickness - params.outsideWeldProjection;
    final double rEnd = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? rOut
        : rOut + params.thickness + params.outsideWeldProjection;

    final thicknessPolygons = <CadFoldedPolygon3D>[];

    // Inner rail lead-in rim
    thicknessPolygons.add(CadFoldedPolygon3D(
      faceId: 'RIM_inner_rail_lead_in',
      vertices: [
        CadPoint3D(rIn, -leadIn, 0.0),
        CadPoint3D(rIn, -leadIn, H),
        CadPoint3D(rIn, 0.0, H),
        CadPoint3D(rIn, 0.0, 0.0),
      ],
      normal: const CadPoint3D(0.0, -1.0, 0.0),
      color: railColor,
    ));

    for (int i = 0; i < rungAngles.length; i++) {
      final double alpha = rungAngles[i];
      final double cosA = math.cos(alpha);
      final double sinA = math.sin(alpha);
      // Tangent unit vector (-sinA, cosA)
      final double halfRungW = 20.0;
      final double tx = -sinA * halfRungW;
      final double ty = cosA * halfRungW;

      final double zB = 20.0;
      final double zT = zB + 20.0;

      // Top slotted web of C-channel
      final double availableRad = (rEnd - rStart) - 40.0;
      final int slotCount = availableRad > 25.0 ? (availableRad / 45.0).floor() : 0;
      if (slotCount <= 0) {
        polygons.add(CadFoldedPolygon3D(
          faceId: 'rung_${i}_web',
          vertices: [
            CadPoint3D((rStart * cosA) - tx, (rStart * sinA) - ty, zT),
            CadPoint3D((rStart * cosA) + tx, (rStart * sinA) + ty, zT),
            CadPoint3D((rEnd * cosA) + tx, (rEnd * sinA) + ty, zT),
            CadPoint3D((rEnd * cosA) - tx, (rEnd * sinA) - ty, zT),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: rungColor,
        ));
      } else {
        final double pitch = availableRad / slotCount;
        double curR = rStart;
        for (int k = 0; k < slotCount; k++) {
          final double rMidSlot = rStart + 20.0 + (k + 0.5) * pitch;
          final double r1 = rMidSlot - 12.5;
          final double r2 = rMidSlot + 12.5;

          // Bridge before slot
          if (r1 > curR) {
            polygons.add(CadFoldedPolygon3D(
              faceId: 'rung_${i}_bridge_$k',
              vertices: [
                CadPoint3D((curR * cosA) - tx, (curR * sinA) - ty, zT),
                CadPoint3D((curR * cosA) + tx, (curR * sinA) + ty, zT),
                CadPoint3D((r1 * cosA) + tx, (r1 * sinA) + ty, zT),
                CadPoint3D((r1 * cosA) - tx, (r1 * sinA) - ty, zT),
              ],
              normal: const CadPoint3D(0.0, 0.0, 1.0),
              color: rungColor,
            ));
          }

          // Left strip beside slot
          polygons.add(CadFoldedPolygon3D(
            faceId: 'rung_${i}_l_$k',
            vertices: [
              CadPoint3D((r1 * cosA) - tx, (r1 * sinA) - ty, zT),
              CadPoint3D((r1 * cosA) - (tx * 0.35), (r1 * sinA) - (ty * 0.35), zT),
              CadPoint3D((r2 * cosA) - (tx * 0.35), (r2 * sinA) - (ty * 0.35), zT),
              CadPoint3D((r2 * cosA) - tx, (r2 * sinA) - ty, zT),
            ],
            normal: const CadPoint3D(0.0, 0.0, 1.0),
            color: rungColor,
          ));

          // Right strip beside slot
          polygons.add(CadFoldedPolygon3D(
            faceId: 'rung_${i}_r_$k',
            vertices: [
              CadPoint3D((r1 * cosA) + (tx * 0.35), (r1 * sinA) + (ty * 0.35), zT),
              CadPoint3D((r1 * cosA) + tx, (r1 * sinA) + ty, zT),
              CadPoint3D((r2 * cosA) + tx, (r2 * sinA) + ty, zT),
              CadPoint3D((r2 * cosA) + (tx * 0.35), (r2 * sinA) + (ty * 0.35), zT),
            ],
            normal: const CadPoint3D(0.0, 0.0, 1.0),
            color: rungColor,
          ));

          curR = r2;
        }

        if (rEnd > curR) {
          polygons.add(CadFoldedPolygon3D(
            faceId: 'rung_${i}_tail',
            vertices: [
              CadPoint3D((curR * cosA) - tx, (curR * sinA) - ty, zT),
              CadPoint3D((curR * cosA) + tx, (curR * sinA) + ty, zT),
              CadPoint3D((rEnd * cosA) + tx, (rEnd * sinA) + ty, zT),
              CadPoint3D((rEnd * cosA) - tx, (rEnd * sinA) - ty, zT),
            ],
            normal: const CadPoint3D(0.0, 0.0, 1.0),
            color: rungColor,
          ));
        }
      }

      // Side flanges of C-channel extending downwards from zT to zB
      polygons.add(CadFoldedPolygon3D(
        faceId: 'rung_${i}_flange_1',
        vertices: [
          CadPoint3D((rStart * cosA) - tx, (rStart * sinA) - ty, zT),
          CadPoint3D((rEnd * cosA) - tx, (rEnd * sinA) - ty, zT),
          CadPoint3D((rEnd * cosA) - tx, (rEnd * sinA) - ty, zB),
          CadPoint3D((rStart * cosA) - tx, (rStart * sinA) - ty, zB),
        ],
        normal: CadPoint3D(sinA, -cosA, 0.0),
        color: rungColor,
      ));

      polygons.add(CadFoldedPolygon3D(
        faceId: 'rung_${i}_flange_2',
        vertices: [
          CadPoint3D((rStart * cosA) + tx, (rStart * sinA) + ty, zB),
          CadPoint3D((rEnd * cosA) + tx, (rEnd * sinA) + ty, zB),
          CadPoint3D((rEnd * cosA) + tx, (rEnd * sinA) + ty, zT),
          CadPoint3D((rStart * cosA) + tx, (rStart * sinA) + ty, zT),
        ],
        normal: CadPoint3D(-sinA, cosA, 0.0),
        color: rungColor,
      ));

      // End caps in matching steel color
      polygons.add(CadFoldedPolygon3D(
        faceId: 'rung_${i}_cap_in',
        vertices: [
          CadPoint3D((rStart * cosA) - tx, (rStart * sinA) - ty, zB),
          CadPoint3D((rStart * cosA) + tx, (rStart * sinA) + ty, zB),
          CadPoint3D((rStart * cosA) + tx, (rStart * sinA) + ty, zT),
          CadPoint3D((rStart * cosA) - tx, (rStart * sinA) - ty, zT),
        ],
        normal: CadPoint3D(-cosA, -sinA, 0.0),
        color: rungColor,
      ));
      polygons.add(CadFoldedPolygon3D(
        faceId: 'rung_${i}_cap_out',
        vertices: [
          CadPoint3D((rEnd * cosA) - tx, (rEnd * sinA) - ty, zT),
          CadPoint3D((rEnd * cosA) + tx, (rEnd * sinA) + ty, zT),
          CadPoint3D((rEnd * cosA) + tx, (rEnd * sinA) + ty, zB),
          CadPoint3D((rEnd * cosA) - tx, (rEnd * sinA) - ty, zB),
        ],
        normal: CadPoint3D(cosA, sinA, 0.0),
        color: rungColor,
      ));
    }

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: rOut + leadIn,
      boundLength: rOut + leadIn,
      boundHeight: H,
      center: CadPoint3D((rIn + rOut) / 4.0, (rIn + rOut) / 4.0, H / 2.0),
    );
  }

  static FoldedMeshResult _buildRiserMesh({
    required double angleRad,
    required double radius,
    required double leadIn,
    required bool isInsideRiser,
    required List<double> rungAlphas,
    required LadderAssemblyParameters params,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final double halfW = params.width / 2.0;
    final double H = params.height;
    final bool isSegmented = params.accessoryStyle == LadderAccessoryStyle.segmented;
    final int segments = isSegmented ? 2 : 16;

    // Rails at Y = -halfW and Y = +halfW
    for (final yRail in [-halfW, halfW]) {
      final double normalY = yRail < 0 ? -1.0 : 1.0;

      // Bottom lead-in
      polygons.add(CadFoldedPolygon3D(
        faceId: 'riser_rail_lead_${yRail < 0 ? "left" : "right"}',
        vertices: [
          CadPoint3D(-leadIn, yRail, 0.0),
          CadPoint3D(0.0, yRail, 0.0),
          CadPoint3D(0.0, yRail, H),
          CadPoint3D(-leadIn, yRail, H),
        ],
        normal: CadPoint3D(0.0, normalY, 0.0),
        color: railColor,
      ));

      // Curved rail web
      for (int s = 0; s < segments; s++) {
        final double a1 = angleRad * s / segments;
        final double a2 = angleRad * (s + 1) / segments;
        final double x1 = radius * math.sin(a1);
        final double z1 = isInsideRiser ? radius * (1.0 - math.cos(a1)) : -radius * (1.0 - math.cos(a1));
        final double x2 = radius * math.sin(a2);
        final double z2 = isInsideRiser ? radius * (1.0 - math.cos(a2)) : -radius * (1.0 - math.cos(a2));

        polygons.add(CadFoldedPolygon3D(
          faceId: 'riser_rail_web_${yRail < 0 ? "l" : "r"}_$s',
          vertices: [
            CadPoint3D(x1, yRail, z1),
            CadPoint3D(x2, yRail, z2),
            CadPoint3D(x2, yRail, z2 + H),
            CadPoint3D(x1, yRail, z1 + H),
          ],
          normal: CadPoint3D(0.0, normalY, 0.0),
          color: railColor,
        ));
      }
    }

    // Straight horizontal rungs across Y
    final double yStart = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? -halfW
        : -halfW - params.thickness - params.outsideWeldProjection;
    final double yEnd = params.jointMethod == LadderRungJointMethod.directInsideWeld
        ? halfW
        : halfW + params.thickness + params.outsideWeldProjection;

    final thicknessPolygons = <CadFoldedPolygon3D>[];
    for (int i = 0; i < rungAlphas.length; i++) {
      final double a = rungAlphas[i];
      final double rx = radius * math.sin(a);
      final double rz = isInsideRiser
          ? radius * (1.0 - math.cos(a)) + 30.0
          : -radius * (1.0 - math.cos(a)) + 30.0;

      final rungPolys = LadderAssemblyGenerator.generateSlottedRung3DPolygons(
        rungId: 'riser_rung_$i',
        xCenter: rx,
        yStart: yStart,
        yEnd: yEnd,
        zTop: rz,
        rungW: 40.0,
        rungDepth: 20.0,
        thickness: params.thickness,
        color: rungColor,
        interiorHalfWidth: halfW,
      );
      polygons.addAll(rungPolys);
    }

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: params.width + (2 * params.flangeWidth),
      boundLength: (radius * math.sin(angleRad)) + (2 * leadIn),
      boundHeight: radius * (1.0 - math.cos(angleRad)) + H,
      center: CadPoint3D((radius * math.sin(angleRad)) / 2.0, 0.0, H / 2.0),
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
