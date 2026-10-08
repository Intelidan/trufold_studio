import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/cad_geometry.dart';
import '../../models/cad_part.dart';
import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';
import '../../models/dsf_document.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../models/ladder/ladder_assembly_models.dart';
import '../../models/ladder/ladder_assembly_parameters.dart';
import '../../models/sheet_metal_material.dart';
import '../../models/dxf_fitting_metadata.dart';
import '../dxf_exporter.dart';
import '../kinematic_fold_engine.dart';
import 'ladder_accessory_generator.dart';
import 'ladder_two_pitch_solver.dart';

/// Pure generative engine for Cable Ladders and Accessories.
/// Synthesizes complete multi-body assemblies (flat blanks for CAM nesting,
/// 3D kinematic meshes, joint topologies, and fastener BOMs) from engineering parameters.
class LadderAssemblyGenerator {
  /// Standard steel density in kg/m³
  static const double densitySteel = 7850.0;

  /// Generates a horizontal bend ladder assembly (30°, 45°, 60°, 90°).
  static DsfLadderAssembly generateHorizontalBend({required double angleDeg, double radiusMm = 300.0, required LadderAssemblyParameters params}) =>
      LadderAccessoryGenerator.generateHorizontalBend(angleDeg: angleDeg, radiusMm: radiusMm, params: params);

  /// Generates an inside or outside riser ladder assembly (30°, 45°, 90°).
  static DsfLadderAssembly generateRiser({
    required double angleDeg,
    double radiusMm = 300.0,
    required bool isInsideRiser,
    required LadderAssemblyParameters params,
  }) => LadderAccessoryGenerator.generateRiser(angleDeg: angleDeg, radiusMm: radiusMm, isInsideRiser: isInsideRiser, params: params);

  /// Generates a reducer ladder assembly (straight/concentric, left, right).
  static DsfLadderAssembly generateReducer({
    required double width1,
    required double width2,
    double length = 500.0,
    String alignment = 'straight',
    required LadderAssemblyParameters params,
  }) => LadderAccessoryGenerator.generateReducer(width1: width1, width2: width2, length: length, alignment: alignment, params: params);

  /// Generates an equal or unequal tee ladder assembly.
  static DsfLadderAssembly generateTee({
    required double mainWidth,
    required double branchWidth,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) => LadderAccessoryGenerator.generateTee(mainWidth: mainWidth, branchWidth: branchWidth, radiusMm: radiusMm, params: params);

  /// Generates an equal or unequal cross ladder assembly.
  static DsfLadderAssembly generateCross({
    required double mainWidth,
    required double branchWidth,
    double radiusMm = 300.0,
    required LadderAssemblyParameters params,
  }) => LadderAccessoryGenerator.generateCross(mainWidth: mainWidth, branchWidth: branchWidth, radiusMm: radiusMm, params: params);

  /// Generates a complete straight cable ladder assembly.
  static DsfLadderAssembly generateStraightLadder(LadderAssemblyParameters params) {
    // 1. Solve Rung Pattern via the Two-Pitch Engine
    final pitchResult = LadderTwoPitchSolver.solve(params);
    final stations = pitchResult.rungStationsX;
    final int rungCount = stations.length;

    // 2. Physical Rung Dimensions & Slots
    final double rungCutLength = params.physicalRungCutLength;
    final slotDim = params.railSlotDimensions;

    // Side Rail Flat Blank Dimensions:
    // Web height: H, Flange width: flangeWidth (top and bottom return flanges)
    final double railFlatWidth = params.height + (2 * params.flangeWidth);
    final double railFlatLength = params.length;

    // Material spec
    final material = SheetMetalMaterial(
      materialGrade: params.materialName,
      thicknessMm: params.thickness,
      paintCoat: params.paintCoat,
    );

    // 3. Generate Flat Blanks (CadPart) for CAM / Nesting
    final leftRailPart = generateCustomRailFlatBlank(
      railSide: 'left',
      params: params,
      railFlatLength: railFlatLength,
      railFlatWidth: railFlatWidth,
      stations: stations,
      slotDim: slotDim,
      material: material,
    );

    final rightRailPart = generateCustomRailFlatBlank(
      railSide: 'right',
      params: params,
      railFlatLength: railFlatLength,
      railFlatWidth: railFlatWidth,
      stations: stations,
      slotDim: slotDim,
      material: material,
    );

    final rungPart = generateCustomRungFlatBlank(rungCutLength: rungCutLength, material: material);

    CadPart? coverPart;
    if (params.includeCover) {
      coverPart = _generateCoverFlatBlank(params: params, material: material);
    }

    // 4. Spatial Instances & Joint Topologies
    final rungs = <LadderRungInstance>[];
    final joints = <LadderJointInstance>[];

    final double halfW = params.width / 2.0;
    final double rungCenterZ = 20.0; // Rung seated 20mm above bottom rail web

    for (int i = 0; i < rungCount; i++) {
      final double x = stations[i];

      rungs.add(
        LadderRungInstance(index: i, stationX: x, center3D: CadPoint3D(x, 0.0, rungCenterZ), cutLength: rungCutLength, jointMethod: params.jointMethod),
      );

      // Left Joint
      joints.add(
        LadderJointInstance(
          rungIndex: i,
          railSide: 'left',
          stationX: x,
          weldCenter3D: CadPoint3D(
            x,
            params.jointMethod == LadderRungJointMethod.directInsideWeld ? -halfW : -halfW - params.thickness - (params.outsideWeldProjection / 2),
            rungCenterZ,
          ),
          slotCenter2D: CadPoint2D(x, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ),
      );

      // Right Joint
      joints.add(
        LadderJointInstance(
          rungIndex: i,
          railSide: 'right',
          stationX: x,
          weldCenter3D: CadPoint3D(
            x,
            params.jointMethod == LadderRungJointMethod.directInsideWeld ? halfW : halfW + params.thickness + (params.outsideWeldProjection / 2),
            rungCenterZ,
          ),
          slotCenter2D: CadPoint2D(x, params.flangeWidth + 20.0),
          hasOpening: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld,
          outsideProjection: params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? params.outsideWeldProjection : 0.0,
        ),
      );
    }

    // 5. Splice Ports for Couplers
    final splicePorts = <CmsPhysicalPort>[
      CmsPhysicalPort(
        id: 'port_start',
        index: 1,
        center: CadPoint3D(0.0, 0.0, params.height / 2.0),
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        width: params.width,
        height: params.height,
      ),
      CmsPhysicalPort(
        id: 'port_end',
        index: 2,
        center: CadPoint3D(params.length, 0.0, params.height / 2.0),
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        width: params.width,
        height: params.height,
      ),
    ];

    // 6. Generate 3D Kinematic Mesh
    final mesh3D = _generate3DAssemblyMesh(params: params, stations: stations, rungCutLength: rungCutLength, rungCenterZ: rungCenterZ);

    FoldedMeshResult? coverMesh3D;
    if (params.includeCover) {
      coverMesh3D = _generateCoverMesh3D(params: params);
    }

    // 7. Hardware & BOM Takeoff Calculation
    final bom = _calculateBOM(params: params, rungCount: rungCount, rungCutLength: rungCutLength);

    return DsfLadderAssembly(
      id: 'LAD-${params.width.round()}X${params.height.round()}-${params.length.round()}',
      productName: 'Cable Ladder Straight Length ${params.width.round()}×${params.height.round()}mm (L=${params.length.round()}mm)',
      parameters: params,
      leftRailBlank: leftRailPart,
      rightRailBlank: rightRailPart,
      rungBlank: rungPart,
      coverBlank: coverPart,
      rungs: rungs,
      joints: joints,
      splicePorts: splicePorts,
      assembledMesh3D: mesh3D,
      coverMesh3D: coverMesh3D,
      hardwareBOM: bom,
    );
  }

  // ---------------------------------------------------------------------------
  // FLAT BLANK GENERATION (CAM / TURRET PUNCHING / LASER CUTTING)
  // ---------------------------------------------------------------------------

  static CadPart generateCustomRailFlatBlank({
    required String railSide,
    String? name,
    required LadderAssemblyParameters params,
    required double railFlatLength,
    required double railFlatWidth,
    required List<double> stations,
    required ({double width, double height}) slotDim,
    required SheetMetalMaterial material,
    List<double>? miterBendStations,
    bool hasFlangeVNotches = false,
    double miterDeltaPhi = 0.0,
  }) {
    final geometries = <CadGeometry>[];

    final double F = params.flangeWidth > 0 ? params.flangeWidth : 32.0;
    final double H = params.height;
    final double W = railFlatWidth; // 2 * F + H

    final sortedStations = (miterBendStations != null && miterBendStations.isNotEmpty)
        ? (List<double>.from(miterBendStations)..sort())
        : <double>[];

    final outerContour = <CadPoint2D>[];

    if (hasFlangeVNotches && sortedStations.isNotEmpty && miterDeltaPhi > 1e-4) {
      final double wNotch = F * math.tan(miterDeltaPhi / 2.0);

      // Start at bottom-left corner
      outerContour.add(const CadPoint2D(0.0, 0.0));

      // 1. Bottom edge (Y = 0.0) with V-notches pointing up to apex (X_k, F)
      for (final st in sortedStations) {
        final double xStart = math.max(0.0, st - wNotch);
        final double xEnd = math.min(railFlatLength, st + wNotch);
        outerContour.add(CadPoint2D(xStart, 0.0));
        outerContour.add(CadPoint2D(st, F));
        outerContour.add(CadPoint2D(xEnd, 0.0));
      }
      outerContour.add(CadPoint2D(railFlatLength, 0.0));

      // 2. Right edge
      outerContour.add(CadPoint2D(railFlatLength, W));

      // 3. Top edge (Y = W) with V-notches pointing down to apex (X_k, F + H)
      // Traverse in descending order
      for (final st in sortedStations.reversed) {
        final double xEnd = math.min(railFlatLength, st + wNotch);
        final double xStart = math.max(0.0, st - wNotch);
        outerContour.add(CadPoint2D(xEnd, W));
        outerContour.add(CadPoint2D(st, F + H));
        outerContour.add(CadPoint2D(xStart, W));
      }
      outerContour.add(CadPoint2D(0.0, W));
    } else {
      outerContour.addAll([
        const CadPoint2D(0.0, 0.0),
        CadPoint2D(railFlatLength, 0.0),
        CadPoint2D(railFlatLength, railFlatWidth),
        CadPoint2D(0.0, railFlatWidth),
      ]);
    }

    // Transverse bend lines across web at miter stations
    if (sortedStations.isNotEmpty) {
      for (int k = 0; k < sortedStations.length; k++) {
        final double x = sortedStations[k];
        geometries.add(
          CadLine2D(
            id: '${railSide}_miter_bend_$k',
            p1: CadPoint2D(x, F),
            p2: CadPoint2D(x, F + H),
            layer: 'BEND_TRANSVERSE',
          ),
        );
      }
    }

    // 2. Longitudinal Bend Lines
    // Bottom flange bend line
    geometries.add(
      CadLine2D(id: '${railSide}_bend_bottom', p1: CadPoint2D(0.0, F), p2: CadPoint2D(railFlatLength, F), layer: 'BEND_90'),
    );
    // Top flange bend line
    geometries.add(
      CadLine2D(
        id: '${railSide}_bend_top',
        p1: CadPoint2D(0.0, F + H),
        p2: CadPoint2D(railFlatLength, F + H),
        layer: 'BEND_90',
      ),
    );

    // 3. Coupler Splice Holes (4x Ø10mm at both ends)
    if (params.includeSpliceHoles) {
      final double webCenterY = params.flangeWidth + (params.height / 2.0);
      const double holeSpacingY = 40.0;
      final y1 = webCenterY - (holeSpacingY / 2.0);
      final y2 = webCenterY + (holeSpacingY / 2.0);

      // Start splice holes (X = 35mm, X = 75mm)
      for (final x in [35.0, 75.0]) {
        for (final y in [y1, y2]) {
          geometries.add(
            CadCircle2D(
              id: '${railSide}_splice_start_${x.round()}_${y.round()}',
              center: CadPoint2D(x, y),
              radius: 5.0, // Ø10mm
              layer: 'CUT_HOLES',
            ),
          );
        }
      }

      // End splice holes (X = L - 75mm, X = L - 35mm)
      for (final x in [railFlatLength - 75.0, railFlatLength - 35.0]) {
        for (final y in [y1, y2]) {
          geometries.add(
            CadCircle2D(
              id: '${railSide}_splice_end_${x.round()}_${y.round()}',
              center: CadPoint2D(x, y),
              radius: 5.0, // Ø10mm
              layer: 'CUT_HOLES',
            ),
          );
        }
      }
    }

    // 4. Rectangular Pass-Through Slots (if active)
    if (params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld) {
      final double slotCenterY = params.flangeWidth + 20.0; // Seated 20mm above bottom bend

      for (int i = 0; i < stations.length; i++) {
        final double x = stations[i];
        geometries.add(
          CadRectangle2D(
            id: '${railSide}_rung_slot_$i',
            center: CadPoint2D(x, slotCenterY),
            widthMm: slotDim.width, // 42mm
            heightMm: slotDim.height, // 22mm
            layer: 'CUT_SLOTS',
          ),
        );
      }
    }

    return CadPart(
      id: '${railSide}_rail_blank',
      name: name ?? '${railSide.toUpperCase()} Side Rail Blank',
      material: material,
      outerContour: outerContour,
      geometries: geometries,
      flatBlankWidth: railFlatWidth,
      flatBlankLength: railFlatLength,
    );
  }

  static CadPart generateCustomRungFlatBlank({required double rungCutLength, required SheetMetalMaterial material}) {
    const double profileW = 40.0;
    const double thickness = 2.0;

    // Formed C-Channel Rung Profile (40mm width by rungCutLength)
    final outerContour = [const CadPoint2D(0.0, 0.0), CadPoint2D(rungCutLength, 0.0), CadPoint2D(rungCutLength, profileW), const CadPoint2D(0.0, profileW)];

    final geometries = <CadGeometry>[];

    // Longitudinal channel leg return / flange edge lines
    geometries.add(
      CadLine2D(id: 'rung_flange_front_edge', p1: const CadPoint2D(0.0, thickness), p2: CadPoint2D(rungCutLength, thickness), layer: 'FORMED_EDGES'),
    );
    geometries.add(
      CadLine2D(
        id: 'rung_flange_back_edge',
        p1: CadPoint2D(0.0, profileW - thickness),
        p2: CadPoint2D(rungCutLength, profileW - thickness),
        layer: 'FORMED_EDGES',
      ),
    );

    // Array of 25x14mm Obrounds along web centerline
    const double obroundLength = 25.0;
    const double obroundWidth = 14.0;
    const double obroundPitch = 50.0;
    const double margin = 30.0;

    final double availableLength = rungCutLength - (2 * margin);
    if (availableLength > obroundLength) {
      final int count = (availableLength / obroundPitch).floor();
      final double actualPitch = availableLength / count;
      final double webCenterY = profileW / 2.0;

      for (int i = 0; i < count; i++) {
        final double x = margin + (i * actualPitch) + (obroundLength / 2.0);
        geometries.add(
          CadSlot2D(id: 'rung_obround_$i', center: CadPoint2D(x, webCenterY), lengthMm: obroundLength, widthMm: obroundWidth, layer: 'CUT_OBROUNDS'),
        );
      }
    }

    return CadPart(
      id: 'rung_blank',
      name: 'Rung Blank (40×20 C-Channel)',
      material: material,
      outerContour: outerContour,
      geometries: geometries,
      flatBlankWidth: profileW,
      flatBlankLength: rungCutLength,
    );
  }

  static CadPart _generateCoverFlatBlank({required LadderAssemblyParameters params, required SheetMetalMaterial material}) {
    final double coverFlatWidth = params.width + (2 * params.coverHeight) + 4.0;
    final double coverLength = params.length;

    return CadPart(
      id: 'cover_blank',
      name: 'Ladder Formed Cover Blank',
      material: material,
      outerContour: [const CadPoint2D(0.0, 0.0), CadPoint2D(coverLength, 0.0), CadPoint2D(coverLength, coverFlatWidth), CadPoint2D(0.0, coverFlatWidth)],
      geometries: [
        CadLine2D(id: 'cover_bend_1', p1: CadPoint2D(0.0, params.coverHeight), p2: CadPoint2D(coverLength, params.coverHeight), layer: 'BEND_90'),
        CadLine2D(
          id: 'cover_bend_2',
          p1: CadPoint2D(0.0, coverFlatWidth - params.coverHeight),
          p2: CadPoint2D(coverLength, coverFlatWidth - params.coverHeight),
          layer: 'BEND_90',
        ),
      ],
      flatBlankWidth: coverFlatWidth,
      flatBlankLength: coverLength,
    );
  }

  // ---------------------------------------------------------------------------
  // 3D KINEMATIC MESH GENERATION (ISOMETRIC / SOLID SHADED CANVAS)
  // ---------------------------------------------------------------------------

  /// Builds 3D slotted C-channel rung polygons (40x20mm) oriented in 3D space with authentic
  /// 25x14mm obround slots cut into its top web (+upDir), downward side flanges (-upDir),
  /// pass-through outside weld projections with end caps, and clean steel color.
  static List<CadFoldedPolygon3D> generateOrientedSlottedRung3DPolygons({
    required String rungId,
    required CadPoint3D centerTop,
    required CadPoint3D lengthDir,
    required CadPoint3D widthDir,
    required CadPoint3D upDir,
    required double interiorHalfSpan,
    required double rungW,
    required double rungDepth,
    required double thickness,
    required Color color,
    required bool isPassThrough,
    required double outsideProjection,
    double slotLength = 25.0,
    double slotWidth = 14.0,
    double slotPitch = 50.0,
    double slotMargin = 30.0,
  }) {
    final polys = <CadFoldedPolygon3D>[];

    // Normalize orientation frame
    final double lLen = math.sqrt(lengthDir.x * lengthDir.x + lengthDir.y * lengthDir.y + lengthDir.z * lengthDir.z);
    final uDir = lLen > 1e-6 ? CadPoint3D(lengthDir.x / lLen, lengthDir.y / lLen, lengthDir.z / lLen) : const CadPoint3D(0.0, 1.0, 0.0);

    final double wLen = math.sqrt(widthDir.x * widthDir.x + widthDir.y * widthDir.y + widthDir.z * widthDir.z);
    final vDir = wLen > 1e-6 ? CadPoint3D(widthDir.x / wLen, widthDir.y / wLen, widthDir.z / wLen) : const CadPoint3D(1.0, 0.0, 0.0);

    final double uUpLen = math.sqrt(upDir.x * upDir.x + upDir.y * upDir.y + upDir.z * upDir.z);
    final wDir = uUpLen > 1e-6 ? CadPoint3D(upDir.x / uUpLen, upDir.y / uUpLen, upDir.z / uUpLen) : const CadPoint3D(0.0, 0.0, 1.0);

    // Coordinate mapping helper from local (u, v, w) to 3D world space
    CadPoint3D pWorld(double u, double v, double w) {
      return CadPoint3D(
        centerTop.x + (uDir.x * u) + (vDir.x * v) + (wDir.x * w),
        centerTop.y + (uDir.y * u) + (vDir.y * v) + (wDir.y * w),
        centerTop.z + (uDir.z * u) + (vDir.z * v) + (wDir.z * w),
      );
    }

    CadPoint3D nWorld(double nu, double nv, double nw) {
      return CadPoint3D(
        (uDir.x * nu) + (vDir.x * nv) + (wDir.x * nw),
        (uDir.y * nu) + (vDir.y * nv) + (wDir.y * nw),
        (uDir.z * nu) + (vDir.z * nv) + (wDir.z * nw),
      );
    }

    final double t = (thickness > 0.1 && thickness < (rungW / 3)) ? thickness : 1.5;
    final double v1 = -rungW / 2.0;
    final double v2 = rungW / 2.0;

    final double uIntStart = -interiorHalfSpan;
    final double uIntEnd = interiorHalfSpan;
    final double uStart = isPassThrough ? (uIntStart - t - outsideProjection) : uIntStart;
    final double uEnd = isPassThrough ? (uIntEnd + t + outsideProjection) : uIntEnd;

    // --- 1. OBROUND SLOTS CUTOUTS (25x14mm) ALONG U-AXIS ON TOP WEB ---
    final double availableLength = (uIntEnd - uIntStart) - (2.0 * slotMargin);
    final int slotCount = availableLength > slotLength ? (availableLength / slotPitch).floor() : 0;
    final double hwSlot = math.min(slotWidth, rungW - 10.0) / 2.0;
    final holes = <List<CadPoint3D>>[];
    final holesInner = <List<CadPoint3D>>[];

    if (slotCount > 0) {
      final double actualPitch = availableLength / slotCount;
      final double rSlot = hwSlot; // 7mm radius
      final double straightHalf = math.max(0.0, (slotLength / 2.0) - rSlot); // (25-14)/2 = 5.5mm

      for (int k = 0; k < slotCount; k++) {
        final double slotCenterU = uIntStart + slotMargin + (k + 0.5) * actualPitch;
        final holeVertices = <CadPoint3D>[];
        final holeVerticesInner = <CadPoint3D>[];

        // Semicircular cap at +U end (angles -pi/2 to pi/2)
        const int arcSteps = 16;
        for (int a = 0; a <= arcSteps; a++) {
          final double angle = -math.pi / 2.0 + (math.pi * a / arcSteps);
          final double u = (slotCenterU + straightHalf) + (rSlot * math.cos(angle));
          final double v = rSlot * math.sin(angle);
          holeVertices.add(pWorld(u, v, 0.0));
          holeVerticesInner.add(pWorld(u, v, -t));
        }

        // Semicircular cap at -U end (angles pi/2 to 3*pi/2)
        for (int a = 0; a <= arcSteps; a++) {
          final double angle = math.pi / 2.0 + (math.pi * a / arcSteps);
          final double u = (slotCenterU - straightHalf) + (rSlot * math.cos(angle));
          final double v = rSlot * math.sin(angle);
          holeVertices.add(pWorld(u, v, 0.0));
          holeVerticesInner.add(pWorld(u, v, -t));
        }

        holes.add(holeVertices);
        holesInner.add(holeVerticesInner);
      }
    }

    final bool hasLeftProj = isPassThrough && (outsideProjection > 0.01 || t > 0.01);
    final bool hasRightProj = isPassThrough && (outsideProjection > 0.01 || t > 0.01);

    // --- 2. LEFT PASS-THROUGH PROJECTION ---
    if (hasLeftProj) {
      // Top web
      polys.add(CadFoldedPolygon3D(
        faceId: '${rungId}_proj_left_top',
        vertices: [pWorld(uStart, v1, 0.0), pWorld(uIntStart, v1, 0.0), pWorld(uIntStart, v2, 0.0), pWorld(uStart, v2, 0.0)],
        normal: nWorld(0.0, 0.0, 1.0),
        color: color,
      ));
      // Front flange
      polys.add(CadFoldedPolygon3D(
        faceId: '${rungId}_proj_left_front',
        vertices: [pWorld(uStart, v1, 0.0), pWorld(uStart, v1, -rungDepth), pWorld(uIntStart, v1, -rungDepth), pWorld(uIntStart, v1, 0.0)],
        normal: nWorld(0.0, -1.0, 0.0),
        color: color,
      ));
      // Back flange
      polys.add(CadFoldedPolygon3D(
        faceId: '${rungId}_proj_left_back',
        vertices: [pWorld(uStart, v2, 0.0), pWorld(uIntStart, v2, 0.0), pWorld(uIntStart, v2, -rungDepth), pWorld(uStart, v2, -rungDepth)],
        normal: nWorld(0.0, 1.0, 0.0),
        color: color,
      ));
      // Open C-channel tip wall profile rims (y = uStart) - NO solid cap
      polys.add(CadFoldedPolygon3D(
        faceId: 'RIM_${rungId}_cap_left_top',
        vertices: [pWorld(uStart, v1, -t), pWorld(uStart, v2, -t), pWorld(uStart, v2, 0.0), pWorld(uStart, v1, 0.0)],
        normal: nWorld(-1.0, 0.0, 0.0),
        color: color,
      ));
      polys.add(CadFoldedPolygon3D(
        faceId: 'RIM_${rungId}_cap_left_front',
        vertices: [pWorld(uStart, v1, -rungDepth), pWorld(uStart, v1 + t, -rungDepth), pWorld(uStart, v1 + t, -t), pWorld(uStart, v1, -t)],
        normal: nWorld(-1.0, 0.0, 0.0),
        color: color,
      ));
      polys.add(CadFoldedPolygon3D(
        faceId: 'RIM_${rungId}_cap_left_back',
        vertices: [pWorld(uStart, v2 - t, -rungDepth), pWorld(uStart, v2, -rungDepth), pWorld(uStart, v2, -t), pWorld(uStart, v2 - t, -t)],
        normal: nWorld(-1.0, 0.0, 0.0),
        color: color,
      ));
    }

    // --- 3. RIGHT PASS-THROUGH PROJECTION ---
    if (hasRightProj) {
      // Top web
      polys.add(CadFoldedPolygon3D(
        faceId: '${rungId}_proj_right_top',
        vertices: [pWorld(uIntEnd, v1, 0.0), pWorld(uEnd, v1, 0.0), pWorld(uEnd, v2, 0.0), pWorld(uIntEnd, v2, 0.0)],
        normal: nWorld(0.0, 0.0, 1.0),
        color: color,
      ));
      // Front flange
      polys.add(CadFoldedPolygon3D(
        faceId: '${rungId}_proj_right_front',
        vertices: [pWorld(uIntEnd, v1, 0.0), pWorld(uIntEnd, v1, -rungDepth), pWorld(uEnd, v1, -rungDepth), pWorld(uEnd, v1, 0.0)],
        normal: nWorld(0.0, -1.0, 0.0),
        color: color,
      ));
      // Back flange
      polys.add(CadFoldedPolygon3D(
        faceId: '${rungId}_proj_right_back',
        vertices: [pWorld(uIntEnd, v2, 0.0), pWorld(uEnd, v2, 0.0), pWorld(uEnd, v2, -rungDepth), pWorld(uIntEnd, v2, -rungDepth)],
        normal: nWorld(0.0, 1.0, 0.0),
        color: color,
      ));
      // Open C-channel tip wall profile rims (y = uEnd) - NO solid cap
      polys.add(CadFoldedPolygon3D(
        faceId: 'RIM_${rungId}_cap_right_top',
        vertices: [pWorld(uEnd, v1, 0.0), pWorld(uEnd, v2, 0.0), pWorld(uEnd, v2, -t), pWorld(uEnd, v1, -t)],
        normal: nWorld(1.0, 0.0, 0.0),
        color: color,
      ));
      polys.add(CadFoldedPolygon3D(
        faceId: 'RIM_${rungId}_cap_right_front',
        vertices: [pWorld(uEnd, v1, -rungDepth), pWorld(uEnd, v1, -t), pWorld(uEnd, v1 + t, -t), pWorld(uEnd, v1 + t, -rungDepth)],
        normal: nWorld(1.0, 0.0, 0.0),
        color: color,
      ));
      polys.add(CadFoldedPolygon3D(
        faceId: 'RIM_${rungId}_cap_right_back',
        vertices: [pWorld(uEnd, v2 - t, -rungDepth), pWorld(uEnd, v2 - t, -t), pWorld(uEnd, v2, -t), pWorld(uEnd, v2, -rungDepth)],
        normal: nWorld(1.0, 0.0, 0.0),
        color: color,
      ));
    }

    // --- 4. INTERIOR RUNG SPAN ---
    // Outer top web with true obround slots
    final topBoundaryLines = <List<CadPoint3D>>[
      [pWorld(uIntStart, v1, 0.0), pWorld(uIntEnd, v1, 0.0)],
      [pWorld(uIntEnd, v2, 0.0), pWorld(uIntStart, v2, 0.0)],
      if (!hasLeftProj) [pWorld(uIntStart, v1, 0.0), pWorld(uIntStart, v2, 0.0)],
      if (!hasRightProj) [pWorld(uIntEnd, v1, 0.0), pWorld(uIntEnd, v2, 0.0)],
      for (final h in holes)
        for (int i = 0; i < h.length; i++)
          [h[i], h[(i + 1) % h.length]],
    ];

    polys.add(CadFoldedPolygon3D(
      faceId: '${rungId}_top_web',
      vertices: [pWorld(uIntStart, v1, 0.0), pWorld(uIntEnd, v1, 0.0), pWorld(uIntEnd, v2, 0.0), pWorld(uIntStart, v2, 0.0)],
      normal: nWorld(0.0, 0.0, 1.0),
      color: color,
      holes: holes,
      boundaryLines: topBoundaryLines,
    ));

    // Front flange
    polys.add(CadFoldedPolygon3D(
      faceId: '${rungId}_flange_front',
      vertices: [pWorld(uIntStart, v1, 0.0), pWorld(uIntStart, v1, -rungDepth), pWorld(uIntEnd, v1, -rungDepth), pWorld(uIntEnd, v1, 0.0)],
      normal: nWorld(0.0, -1.0, 0.0),
      color: color,
      boundaryLines: [
        [pWorld(uIntStart, v1, -rungDepth), pWorld(uIntEnd, v1, -rungDepth)],
      ],
    ));

    // Back flange
    polys.add(CadFoldedPolygon3D(
      faceId: '${rungId}_flange_back',
      vertices: [pWorld(uIntStart, v2, 0.0), pWorld(uIntEnd, v2, 0.0), pWorld(uIntEnd, v2, -rungDepth), pWorld(uIntStart, v2, -rungDepth)],
      normal: nWorld(0.0, 1.0, 0.0),
      color: color,
      boundaryLines: [
        [pWorld(uIntStart, v2, -rungDepth), pWorld(uIntEnd, v2, -rungDepth)],
      ],
    ));

    // --- 5. PHYSICAL SHEET THICKNESS: INNER FACES & BOTTOM LIPS ---
    // Inner top web with matching cutout holes through sheet thickness
    polys.add(CadFoldedPolygon3D(
      faceId: '${rungId}_top_web_inner',
      vertices: [
        pWorld(uStart, v1 + t, -t),
        pWorld(uStart, v2 - t, -t),
        pWorld(uEnd, v2 - t, -t),
        pWorld(uEnd, v1 + t, -t),
      ],
      normal: nWorld(0.0, 0.0, -1.0),
      color: color,
      holes: holesInner,
    ));

    // Cutout sidewalls for slots in the top web (physical sheet thickness through metal)
    for (int hIdx = 0; hIdx < holes.length; hIdx++) {
      final hVerts = holes[hIdx];
      final hInner = holesInner[hIdx];
      for (int v = 0; v < hVerts.length; v++) {
        final pA = hVerts[v];
        final pB = hVerts[(v + 1) % hVerts.length];
        final pAInner = hInner[v];
        final pBInner = hInner[(v + 1) % hInner.length];

        final du = pB.x - pA.x;
        final dv = pB.y - pA.y;
        final dw = pB.z - pA.z;
        final crossX = dv * (pAInner.z - pA.z) - dw * (pAInner.y - pA.y);
        final crossY = dw * (pAInner.x - pA.x) - du * (pAInner.z - pA.z);
        final crossZ = du * (pAInner.y - pA.y) - dv * (pAInner.x - pA.x);
        final cLen = math.sqrt(crossX * crossX + crossY * crossY + crossZ * crossZ);
        final norm = cLen > 1e-6 ? CadPoint3D(crossX / cLen, crossY / cLen, crossZ / cLen) : const CadPoint3D(0.0, 0.0, 1.0);

        polys.add(
          CadFoldedPolygon3D(
            faceId: '${rungId}_slot_${hIdx}_wall_$v',
            vertices: [pA, pB, pBInner, pAInner],
            normal: norm,
            color: color,
          ),
        );
      }
    }

    // Inner front flange
    polys.add(CadFoldedPolygon3D(
      faceId: '${rungId}_flange_front_inner',
      vertices: [
        pWorld(uStart, v1 + t, -rungDepth),
        pWorld(uEnd, v1 + t, -rungDepth),
        pWorld(uEnd, v1 + t, -t),
        pWorld(uStart, v1 + t, -t),
      ],
      normal: nWorld(0.0, 1.0, 0.0),
      color: color,
    ));

    // Inner back flange
    polys.add(CadFoldedPolygon3D(
      faceId: '${rungId}_flange_back_inner',
      vertices: [
        pWorld(uStart, v2 - t, -t),
        pWorld(uEnd, v2 - t, -t),
        pWorld(uEnd, v2 - t, -rungDepth),
        pWorld(uStart, v2 - t, -rungDepth),
      ],
      normal: nWorld(0.0, -1.0, 0.0),
      color: color,
    ));

    // Bottom lip on front flange (thickness t)
    polys.add(CadFoldedPolygon3D(
      faceId: 'RIM_${rungId}_front_lip',
      vertices: [
        pWorld(uStart, v1, -rungDepth),
        pWorld(uStart, v1 + t, -rungDepth),
        pWorld(uEnd, v1 + t, -rungDepth),
        pWorld(uEnd, v1, -rungDepth),
      ],
      normal: nWorld(0.0, 0.0, -1.0),
      color: color,
    ));

    // Bottom lip on back flange (thickness t)
    polys.add(CadFoldedPolygon3D(
      faceId: 'RIM_${rungId}_back_lip',
      vertices: [
        pWorld(uStart, v2 - t, -rungDepth),
        pWorld(uStart, v2, -rungDepth),
        pWorld(uEnd, v2, -rungDepth),
        pWorld(uEnd, v2 - t, -rungDepth),
      ],
      normal: nWorld(0.0, 0.0, -1.0),
      color: color,
    ));

    return polys;
  }

  /// Builds 3D slotted C-channel rung polygons with top slotted web, downward side flanges,
  /// flange rims and end caps in clean galvanized steel color.
  static List<CadFoldedPolygon3D> generateSlottedRung3DPolygons({
    required String rungId,
    required double xCenter,
    required double yStart,
    required double yEnd,
    required double zTop,
    required double rungW,
    required double rungDepth,
    required double thickness,
    required Color color,
    double interiorHalfWidth = 0.0,
    double slotLength = 25.0,
    double slotWidth = 14.0,
    double slotPitch = 50.0,
    double slotMargin = 30.0,
  }) {
    final polys = <CadFoldedPolygon3D>[];
    final double x1 = xCenter - (rungW / 2.0);
    final double x2 = xCenter + (rungW / 2.0);
    final double zBottom = zTop - rungDepth;

    final double halfSpan = interiorHalfWidth > 0 ? interiorHalfWidth : ((yEnd - yStart).abs() / 2.0);
    final double yIntStart = -halfSpan;
    final double yIntEnd = halfSpan;

    final double availableLength = (yIntEnd - yIntStart) - (2.0 * slotMargin);
    final int slotCount = availableLength > slotLength ? (availableLength / slotPitch).floor() : 0;
    final double hwSlot = math.min(slotWidth, rungW - 10.0) / 2.0;

    final holes = <List<CadPoint3D>>[];

    if (slotCount > 0) {
      final double actualPitch = availableLength / slotCount;
      final double rSlot = hwSlot; // radius of obround semicircles (7mm)
      final double straightHalf = math.max(0.0, (slotLength / 2.0) - rSlot); // (25-14)/2 = 5.5mm

      for (int k = 0; k < slotCount; k++) {
        final double slotCenterY = yIntStart + slotMargin + (k + 0.5) * actualPitch;
        final holeVertices = <CadPoint3D>[];

        // Semicircular cap at +Y end (from angle 0 to pi)
        const int arcSteps = 16;
        for (int a = 0; a <= arcSteps; a++) {
          final double angle = math.pi * a / arcSteps;
          final double hx = xCenter + (rSlot * math.cos(angle));
          final double hy = (slotCenterY + straightHalf) + (rSlot * math.sin(angle));
          holeVertices.add(CadPoint3D(hx, hy, zTop));
        }

        // Semicircular cap at -Y end (from angle pi to 2*pi)
        for (int a = 0; a <= arcSteps; a++) {
          final double angle = math.pi + (math.pi * a / arcSteps);
          final double hx = xCenter + (rSlot * math.cos(angle));
          final double hy = (slotCenterY - straightHalf) + (rSlot * math.sin(angle));
          holeVertices.add(CadPoint3D(hx, hy, zTop));
        }

        holes.add(holeVertices);
      }
    }

    final double t = (thickness > 0.1 && thickness < (rungW / 3)) ? thickness : 1.5;
    final double x1Inner = x1 + t;
    final double x2Inner = x2 - t;
    final double zTopInner = zTop - t;

    final bool hasLeftProj = yStart < yIntStart - 0.5;
    final bool hasRightProj = yEnd > yIntEnd + 0.5;

    // --- 1. LEFT PASS-THROUGH OUTSIDE WELD PROJECTION [yStart .. yIntStart] ---
    if (hasLeftProj) {
      // Outer top web
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_left_top',
          vertices: [CadPoint3D(x1, yStart, zTop), CadPoint3D(x2, yStart, zTop), CadPoint3D(x2, yIntStart, zTop), CadPoint3D(x1, yIntStart, zTop)],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: color,
          boundaryLines: [
            [CadPoint3D(x1, yStart, zTop), CadPoint3D(x2, yStart, zTop)],
            [CadPoint3D(x1, yStart, zTop), CadPoint3D(x1, yIntStart, zTop)],
            [CadPoint3D(x2, yStart, zTop), CadPoint3D(x2, yIntStart, zTop)],
          ],
        ),
      );

      // Inner top web
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_left_top_inner',
          vertices: [
            CadPoint3D(x1Inner, yStart, zTopInner),
            CadPoint3D(x1Inner, yIntStart, zTopInner),
            CadPoint3D(x2Inner, yIntStart, zTopInner),
            CadPoint3D(x2Inner, yStart, zTopInner),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: color,
        ),
      );

      // Outer front flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_left_front',
          vertices: [CadPoint3D(x1, yStart, zTop), CadPoint3D(x1, yIntStart, zTop), CadPoint3D(x1, yIntStart, zBottom), CadPoint3D(x1, yStart, zBottom)],
          normal: const CadPoint3D(-1.0, 0.0, 0.0),
          color: color,
          boundaryLines: [
            [CadPoint3D(x1, yStart, zTop), CadPoint3D(x1, yStart, zBottom)],
            [CadPoint3D(x1, yStart, zBottom), CadPoint3D(x1, yIntStart, zBottom)],
          ],
        ),
      );

      // Inner front flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_left_front_inner',
          vertices: [
            CadPoint3D(x1Inner, yStart, zBottom),
            CadPoint3D(x1Inner, yIntStart, zBottom),
            CadPoint3D(x1Inner, yIntStart, zTopInner),
            CadPoint3D(x1Inner, yStart, zTopInner),
          ],
          normal: const CadPoint3D(1.0, 0.0, 0.0),
          color: color,
        ),
      );

      // Outer back flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_left_back',
          vertices: [CadPoint3D(x2, yStart, zBottom), CadPoint3D(x2, yIntStart, zBottom), CadPoint3D(x2, yIntStart, zTop), CadPoint3D(x2, yStart, zTop)],
          normal: const CadPoint3D(1.0, 0.0, 0.0),
          color: color,
          boundaryLines: [
            [CadPoint3D(x2, yStart, zBottom), CadPoint3D(x2, yStart, zTop)],
            [CadPoint3D(x2, yStart, zBottom), CadPoint3D(x2, yIntStart, zBottom)],
          ],
        ),
      );

      // Inner back flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_left_back_inner',
          vertices: [
            CadPoint3D(x2Inner, yStart, zTopInner),
            CadPoint3D(x2Inner, yIntStart, zTopInner),
            CadPoint3D(x2Inner, yIntStart, zBottom),
            CadPoint3D(x2Inner, yStart, zBottom),
          ],
          normal: const CadPoint3D(-1.0, 0.0, 0.0),
          color: color,
        ),
      );

      // Bottom return rims on left projection
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_proj_left_front_lip',
          vertices: [
            CadPoint3D(x1, yStart, zBottom),
            CadPoint3D(x1, yIntStart, zBottom),
            CadPoint3D(x1Inner, yIntStart, zBottom),
            CadPoint3D(x1Inner, yStart, zBottom),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: color,
        ),
      );
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_proj_left_back_lip',
          vertices: [
            CadPoint3D(x2Inner, yStart, zBottom),
            CadPoint3D(x2Inner, yIntStart, zBottom),
            CadPoint3D(x2, yIntStart, zBottom),
            CadPoint3D(x2, yStart, zBottom),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: color,
        ),
      );

      // Open C-channel cross-section profile at the projecting tip (y = yStart)
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_cap_left_top',
          vertices: [CadPoint3D(x1, yStart, zTopInner), CadPoint3D(x2, yStart, zTopInner), CadPoint3D(x2, yStart, zTop), CadPoint3D(x1, yStart, zTop)],
          normal: const CadPoint3D(0.0, -1.0, 0.0),
          color: color,
          boundaryLines: const [],
        ),
      );
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_cap_left_front',
          vertices: [
            CadPoint3D(x1, yStart, zBottom),
            CadPoint3D(x1Inner, yStart, zBottom),
            CadPoint3D(x1Inner, yStart, zTopInner),
            CadPoint3D(x1, yStart, zTopInner),
          ],
          normal: const CadPoint3D(0.0, -1.0, 0.0),
          color: color,
        ),
      );
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_cap_left_back',
          vertices: [
            CadPoint3D(x2Inner, yStart, zBottom),
            CadPoint3D(x2, yStart, zBottom),
            CadPoint3D(x2, yStart, zTopInner),
            CadPoint3D(x2Inner, yStart, zTopInner),
          ],
          normal: const CadPoint3D(0.0, -1.0, 0.0),
          color: color,
        ),
      );
    }

    // --- 2. INTERIOR RUNG SPAN [yIntStart .. yIntEnd] ---
    // Outer top web
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${rungId}_top_web',
        vertices: [CadPoint3D(x1, yIntStart, zTop), CadPoint3D(x2, yIntStart, zTop), CadPoint3D(x2, yIntEnd, zTop), CadPoint3D(x1, yIntEnd, zTop)],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
        holes: holes,
        boundaryLines: [
          [CadPoint3D(x1, yIntStart, zTop), CadPoint3D(x1, yIntEnd, zTop)],
          [CadPoint3D(x2, yIntStart, zTop), CadPoint3D(x2, yIntEnd, zTop)],
          if (!hasLeftProj) [CadPoint3D(x1, yIntStart, zTop), CadPoint3D(x2, yIntStart, zTop)],
          if (!hasRightProj) [CadPoint3D(x1, yIntEnd, zTop), CadPoint3D(x2, yIntEnd, zTop)],
          for (final h in holes)
            for (int i = 0; i < h.length; i++)
              [CadPoint3D(h[i].x, h[i].y, zTop), CadPoint3D(h[(i + 1) % h.length].x, h[(i + 1) % h.length].y, zTop)],
        ],
      ),
    );

    // Inner top web with matching cutout holes
    final innerHoles = holes.map((h) => h.map((p) => CadPoint3D(p.x, p.y, zTopInner)).toList()).toList();
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${rungId}_top_web_inner',
        vertices: [
          CadPoint3D(x1Inner, yIntStart, zTopInner),
          CadPoint3D(x1Inner, yIntEnd, zTopInner),
          CadPoint3D(x2Inner, yIntEnd, zTopInner),
          CadPoint3D(x2Inner, yIntStart, zTopInner),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
        holes: innerHoles,
        boundaryLines: const [], // Single border rule: do not duplicate on inner face
      ),
    );

    // Cutout sidewalls for slots in the top web (physical sheet thickness through metal)
    // NOTE: bore wall facets do NOT have boundary lines, preventing faceted chord segments around hole arcs
    for (int hIdx = 0; hIdx < holes.length; hIdx++) {
      final hVerts = holes[hIdx];
      for (int v = 0; v < hVerts.length; v++) {
        final pA = hVerts[v];
        final pB = hVerts[(v + 1) % hVerts.length];
        final dx = pB.x - pA.x;
        final dy = pB.y - pA.y;
        final len = math.sqrt(dx * dx + dy * dy);
        final nx = len > 1e-6 ? (dy / len) : 0.0;
        final ny = len > 1e-6 ? (-dx / len) : 0.0;

        polys.add(
          CadFoldedPolygon3D(
            faceId: '${rungId}_slot_${hIdx}_wall_$v',
            vertices: [CadPoint3D(pA.x, pA.y, zTop), CadPoint3D(pB.x, pB.y, zTop), CadPoint3D(pB.x, pB.y, zTopInner), CadPoint3D(pA.x, pA.y, zTopInner)],
            normal: CadPoint3D(nx, ny, 0.0),
            color: color,
            boundaryLines: const [], // No chord segments around hole arcs
          ),
        );
      }
    }

    // Outer front flange
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${rungId}_flange_front',
        vertices: [CadPoint3D(x1, yIntStart, zTop), CadPoint3D(x1, yIntEnd, zTop), CadPoint3D(x1, yIntEnd, zBottom), CadPoint3D(x1, yIntStart, zBottom)],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: color,
        boundaryLines: [
          [CadPoint3D(x1, yIntStart, zBottom), CadPoint3D(x1, yIntEnd, zBottom)],
          if (!hasLeftProj) [CadPoint3D(x1, yIntStart, zTop), CadPoint3D(x1, yIntStart, zBottom)],
          if (!hasRightProj) [CadPoint3D(x1, yIntEnd, zTop), CadPoint3D(x1, yIntEnd, zBottom)],
        ],
      ),
    );

    // Inner front flange
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${rungId}_flange_front_inner',
        vertices: [
          CadPoint3D(x1Inner, yIntStart, zBottom),
          CadPoint3D(x1Inner, yIntEnd, zBottom),
          CadPoint3D(x1Inner, yIntEnd, zTopInner),
          CadPoint3D(x1Inner, yIntStart, zTopInner),
        ],
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: color,
        boundaryLines: const [], // Single border rule: do not duplicate on inner face
      ),
    );

    // Outer back flange
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${rungId}_flange_back',
        vertices: [CadPoint3D(x2, yIntStart, zBottom), CadPoint3D(x2, yIntEnd, zBottom), CadPoint3D(x2, yIntEnd, zTop), CadPoint3D(x2, yIntStart, zTop)],
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: color,
        boundaryLines: [
          [CadPoint3D(x2, yIntStart, zBottom), CadPoint3D(x2, yIntEnd, zBottom)],
          if (!hasLeftProj) [CadPoint3D(x2, yIntStart, zBottom), CadPoint3D(x2, yIntStart, zTop)],
          if (!hasRightProj) [CadPoint3D(x2, yIntEnd, zBottom), CadPoint3D(x2, yIntEnd, zTop)],
        ],
      ),
    );

    // Inner back flange
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${rungId}_flange_back_inner',
        vertices: [
          CadPoint3D(x2Inner, yIntStart, zTopInner),
          CadPoint3D(x2Inner, yIntEnd, zTopInner),
          CadPoint3D(x2Inner, yIntEnd, zBottom),
          CadPoint3D(x2Inner, yIntStart, zBottom),
        ],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: color,
        boundaryLines: const [], // Single border rule: do not duplicate on inner face
      ),
    );

    // Bottom return lips / thickness rims
    polys.add(
      CadFoldedPolygon3D(
        faceId: 'RIM_${rungId}_front_lip',
        vertices: [
          CadPoint3D(x1, yIntStart, zBottom),
          CadPoint3D(x1, yIntEnd, zBottom),
          CadPoint3D(x1Inner, yIntEnd, zBottom),
          CadPoint3D(x1Inner, yIntStart, zBottom),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
        boundaryLines: const [],
      ),
    );
    polys.add(
      CadFoldedPolygon3D(
        faceId: 'RIM_${rungId}_back_lip',
        vertices: [
          CadPoint3D(x2Inner, yIntStart, zBottom),
          CadPoint3D(x2Inner, yIntEnd, zBottom),
          CadPoint3D(x2, yIntEnd, zBottom),
          CadPoint3D(x2, yIntStart, zBottom),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
        boundaryLines: const [],
      ),
    );

    // End caps for direct inside weld
    if (!hasLeftProj) {
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_cap_left',
          vertices: [CadPoint3D(x1, yIntStart, zBottom), CadPoint3D(x2, yIntStart, zBottom), CadPoint3D(x2, yIntStart, zTop), CadPoint3D(x1, yIntStart, zTop)],
          normal: const CadPoint3D(0.0, -1.0, 0.0),
          color: color,
        ),
      );
    }

    if (!hasRightProj) {
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_cap_right',
          vertices: [CadPoint3D(x1, yIntEnd, zTop), CadPoint3D(x2, yIntEnd, zTop), CadPoint3D(x2, yIntEnd, zBottom), CadPoint3D(x1, yIntEnd, zBottom)],
          normal: const CadPoint3D(0.0, 1.0, 0.0),
          color: color,
        ),
      );
    }

    // --- 3. RIGHT PASS-THROUGH OUTSIDE WELD PROJECTION [yIntEnd .. yEnd] ---
    if (hasRightProj) {
      // Outer top web
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_right_top',
          vertices: [CadPoint3D(x1, yIntEnd, zTop), CadPoint3D(x2, yIntEnd, zTop), CadPoint3D(x2, yEnd, zTop), CadPoint3D(x1, yEnd, zTop)],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: color,
          boundaryLines: [
            [CadPoint3D(x1, yEnd, zTop), CadPoint3D(x2, yEnd, zTop)],
            [CadPoint3D(x1, yIntEnd, zTop), CadPoint3D(x1, yEnd, zTop)],
            [CadPoint3D(x2, yIntEnd, zTop), CadPoint3D(x2, yEnd, zTop)],
          ],
        ),
      );

      // Inner top web
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_right_top_inner',
          vertices: [
            CadPoint3D(x1Inner, yIntEnd, zTopInner),
            CadPoint3D(x1Inner, yEnd, zTopInner),
            CadPoint3D(x2Inner, yEnd, zTopInner),
            CadPoint3D(x2Inner, yIntEnd, zTopInner),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: color,
        ),
      );

      // Outer front flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_right_front',
          vertices: [CadPoint3D(x1, yIntEnd, zTop), CadPoint3D(x1, yEnd, zTop), CadPoint3D(x1, yEnd, zBottom), CadPoint3D(x1, yIntEnd, zBottom)],
          normal: const CadPoint3D(-1.0, 0.0, 0.0),
          color: color,
          boundaryLines: [
            [CadPoint3D(x1, yEnd, zTop), CadPoint3D(x1, yEnd, zBottom)],
            [CadPoint3D(x1, yIntEnd, zBottom), CadPoint3D(x1, yEnd, zBottom)],
          ],
        ),
      );

      // Inner front flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_right_front_inner',
          vertices: [
            CadPoint3D(x1Inner, yIntEnd, zBottom),
            CadPoint3D(x1Inner, yEnd, zBottom),
            CadPoint3D(x1Inner, yEnd, zTopInner),
            CadPoint3D(x1Inner, yIntEnd, zTopInner),
          ],
          normal: const CadPoint3D(1.0, 0.0, 0.0),
          color: color,
        ),
      );

      // Outer back flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_right_back',
          vertices: [CadPoint3D(x2, yIntEnd, zBottom), CadPoint3D(x2, yEnd, zBottom), CadPoint3D(x2, yEnd, zTop), CadPoint3D(x2, yIntEnd, zTop)],
          normal: const CadPoint3D(1.0, 0.0, 0.0),
          color: color,
          boundaryLines: [
            [CadPoint3D(x2, yEnd, zBottom), CadPoint3D(x2, yEnd, zTop)],
            [CadPoint3D(x2, yIntEnd, zBottom), CadPoint3D(x2, yEnd, zBottom)],
          ],
        ),
      );

      // Inner back flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${rungId}_proj_right_back_inner',
          vertices: [
            CadPoint3D(x2Inner, yIntEnd, zTopInner),
            CadPoint3D(x2Inner, yEnd, zTopInner),
            CadPoint3D(x2Inner, yEnd, zBottom),
            CadPoint3D(x2Inner, yIntEnd, zBottom),
          ],
          normal: const CadPoint3D(-1.0, 0.0, 0.0),
          color: color,
        ),
      );

      // Bottom return lips on right projection
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_proj_right_front_lip',
          vertices: [
            CadPoint3D(x1, yIntEnd, zBottom),
            CadPoint3D(x1, yEnd, zBottom),
            CadPoint3D(x1Inner, yEnd, zBottom),
            CadPoint3D(x1Inner, yIntEnd, zBottom),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: color,
        ),
      );
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_proj_right_back_lip',
          vertices: [
            CadPoint3D(x2Inner, yIntEnd, zBottom),
            CadPoint3D(x2Inner, yEnd, zBottom),
            CadPoint3D(x2, yEnd, zBottom),
            CadPoint3D(x2, yIntEnd, zBottom),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: color,
        ),
      );

      // Open C-channel cross-section profile at the projecting tip (y = yEnd)
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_cap_right_top',
          vertices: [CadPoint3D(x1, yEnd, zTop), CadPoint3D(x2, yEnd, zTop), CadPoint3D(x2, yEnd, zTopInner), CadPoint3D(x1, yEnd, zTopInner)],
          normal: const CadPoint3D(0.0, 1.0, 0.0),
          color: color,
          boundaryLines: const [],
        ),
      );
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_cap_right_front',
          vertices: [CadPoint3D(x1, yEnd, zTopInner), CadPoint3D(x1Inner, yEnd, zTopInner), CadPoint3D(x1Inner, yEnd, zBottom), CadPoint3D(x1, yEnd, zBottom)],
          normal: const CadPoint3D(0.0, 1.0, 0.0),
          color: color,
        ),
      );
      polys.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_${rungId}_cap_right_back',
          vertices: [CadPoint3D(x2Inner, yEnd, zTopInner), CadPoint3D(x2, yEnd, zTopInner), CadPoint3D(x2, yEnd, zBottom), CadPoint3D(x2Inner, yEnd, zBottom)],
          normal: const CadPoint3D(0.0, 1.0, 0.0),
          color: color,
        ),
      );
    }

    return polys;
  }

  static FoldedMeshResult _generate3DAssemblyMesh({
    required LadderAssemblyParameters params,
    required List<double> stations,
    required double rungCutLength,
    required double rungCenterZ,
  }) {
    final polygons = <CadFoldedPolygon3D>[];
    final thicknessPolygons = <CadFoldedPolygon3D>[];

    final double halfW = params.width / 2.0;
    final double L = params.length;
    final double H = params.height;
    final double F = params.flangeWidth;
    final double T = params.thickness > 0 ? params.thickness : 2.0;

    const railColor = Color(0xFF90A4AE); // Blue-grey sheet steel
    const rungColor = Color(0xFF78909C); // Slightly darker rung channel

    // --- 1. LEFT & RIGHT RAIL COORDINATES ---
    final double yL = -halfW;
    final double yLBottomFlange = params.flangeDirection == LadderFlangeDirection.inside ? yL + F : yL - F;
    final double yLTopFlange = params.flangeDirection == LadderFlangeDirection.inside ? yL + F : yL - F;
    final double innerSignL = params.flangeDirection == LadderFlangeDirection.inside ? 1.0 : -1.0;
    final double yLInner = yL + (innerSignL * T);

    final double yR = halfW;
    final double yRBottomFlange = params.flangeDirection == LadderFlangeDirection.inside ? yR - F : yR + F;
    final double yRTopFlange = params.flangeDirection == LadderFlangeDirection.inside ? yR - F : yR + F;
    final double innerSignR = params.flangeDirection == LadderFlangeDirection.inside ? -1.0 : 1.0;
    final double yRInner = yR + (innerSignR * T);

    // --- 2. LONGITUDINAL RAIL SUBDIVISION ---
    // Subdivide side rails into segments between rung stations (~250mm each)
    // so painter's algorithm depth sorting evaluates localized bounding boxes and depths!
    final xBreaks = <double>[0.0];
    for (int i = 0; i < stations.length - 1; i++) {
      xBreaks.add((stations[i] + stations[i + 1]) / 2.0);
    }
    xBreaks.add(L);

    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;
    final double slotW = params.railSlotDimensions.width; // 42.0mm
    final double slotH = params.railSlotDimensions.height; // 22.0mm
    final double halfSlotW = slotW / 2.0;
    final double zSlotBottom = rungCenterZ - (slotH / 2.0);
    final double zSlotTop = rungCenterZ + (slotH / 2.0);

    for (int s = 0; s < xBreaks.length - 1; s++) {
      final double xStart = xBreaks[s];
      final double xEnd = xBreaks[s + 1];

      // Matching pass-through slot openings on rail web where rungs penetrate:
      final leftWebHoles = <List<CadPoint3D>>[];
      final rightWebHoles = <List<CadPoint3D>>[];
      final leftInnerHoles = <List<CadPoint3D>>[];
      final rightInnerHoles = <List<CadPoint3D>>[];

      if (isPassThrough && s < stations.length) {
        final double stX = stations[s];
        if (stX >= xStart && stX <= xEnd) {
          final xSlotMin = stX - halfSlotW;
          final xSlotMax = stX + halfSlotW;

          leftWebHoles.add([
            CadPoint3D(xSlotMin, yL, zSlotBottom),
            CadPoint3D(xSlotMax, yL, zSlotBottom),
            CadPoint3D(xSlotMax, yL, zSlotTop),
            CadPoint3D(xSlotMin, yL, zSlotTop),
          ]);
          leftInnerHoles.add([
            CadPoint3D(xSlotMin, yLInner, zSlotBottom),
            CadPoint3D(xSlotMin, yLInner, zSlotTop),
            CadPoint3D(xSlotMax, yLInner, zSlotTop),
            CadPoint3D(xSlotMax, yLInner, zSlotBottom),
          ]);

          rightWebHoles.add([
            CadPoint3D(xSlotMin, yR, zSlotBottom),
            CadPoint3D(xSlotMin, yR, zSlotTop),
            CadPoint3D(xSlotMax, yR, zSlotTop),
            CadPoint3D(xSlotMax, yR, zSlotBottom),
          ]);
          rightInnerHoles.add([
            CadPoint3D(xSlotMin, yRInner, zSlotBottom),
            CadPoint3D(xSlotMax, yRInner, zSlotBottom),
            CadPoint3D(xSlotMax, yRInner, zSlotTop),
            CadPoint3D(xSlotMin, yRInner, zSlotTop),
          ]);
        }
      }

      final isFirst = (s == 0);
      final isLast = (s == xBreaks.length - 2);

      final leftWebEdges = <List<CadPoint3D>>[
        [CadPoint3D(xStart, yL, 0.0), CadPoint3D(xEnd, yL, 0.0)],
        [CadPoint3D(xStart, yL, H), CadPoint3D(xEnd, yL, H)],
      ];
      if (isFirst) leftWebEdges.add([CadPoint3D(xStart, yL, 0.0), CadPoint3D(xStart, yL, H)]);
      if (isLast) leftWebEdges.add([CadPoint3D(xEnd, yL, 0.0), CadPoint3D(xEnd, yL, H)]);
      for (final h in leftWebHoles) {
        for (int i = 0; i < h.length; i++) {
          leftWebEdges.add([h[i], h[(i + 1) % h.length]]);
        }
      }

      // --- Left Rail Segment (Solid Thick C-Channel Steel) ---
      // 1. Outer Web
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'left_rail_web_$s',
          vertices: [CadPoint3D(xStart, yL, 0.0), CadPoint3D(xEnd, yL, 0.0), CadPoint3D(xEnd, yL, H), CadPoint3D(xStart, yL, H)],
          normal: const CadPoint3D(0.0, -1.0, 0.0),
          color: railColor,
          holes: leftWebHoles,
          boundaryLines: leftWebEdges,
        ),
      );
      // 2. Outer Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'left_rail_bottom_flange_$s',
          vertices: [CadPoint3D(xStart, yL, 0.0), CadPoint3D(xStart, yLBottomFlange, 0.0), CadPoint3D(xEnd, yLBottomFlange, 0.0), CadPoint3D(xEnd, yL, 0.0)],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: railColor,
          boundaryLines: [
            [CadPoint3D(xStart, yLBottomFlange, 0.0), CadPoint3D(xEnd, yLBottomFlange, 0.0)],
            if (isFirst) [CadPoint3D(xStart, yL, 0.0), CadPoint3D(xStart, yLBottomFlange, 0.0)],
            if (isLast) [CadPoint3D(xEnd, yL, 0.0), CadPoint3D(xEnd, yLBottomFlange, 0.0)],
          ],
        ),
      );
      // 3. Outer Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'left_rail_top_flange_$s',
          vertices: [CadPoint3D(xStart, yL, H), CadPoint3D(xEnd, yL, H), CadPoint3D(xEnd, yLTopFlange, H), CadPoint3D(xStart, yLTopFlange, H)],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: railColor,
          boundaryLines: [
            [CadPoint3D(xStart, yLTopFlange, H), CadPoint3D(xEnd, yLTopFlange, H)],
            if (isFirst) [CadPoint3D(xStart, yL, H), CadPoint3D(xStart, yLTopFlange, H)],
            if (isLast) [CadPoint3D(xEnd, yL, H), CadPoint3D(xEnd, yLTopFlange, H)],
          ],
        ),
      );

      // 4. Solid Thickness Rims / Lips
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_left_top_flange_lip_$s',
          vertices: [
            CadPoint3D(xStart, yLTopFlange, H - T),
            CadPoint3D(xEnd, yLTopFlange, H - T),
            CadPoint3D(xEnd, yLTopFlange, H),
            CadPoint3D(xStart, yLTopFlange, H),
          ],
          normal: CadPoint3D(0.0, innerSignL, 0.0),
          color: railColor,
        ),
      );
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_left_bottom_flange_lip_$s',
          vertices: [
            CadPoint3D(xStart, yLBottomFlange, 0.0),
            CadPoint3D(xEnd, yLBottomFlange, 0.0),
            CadPoint3D(xEnd, yLBottomFlange, T),
            CadPoint3D(xStart, yLBottomFlange, T),
          ],
          normal: CadPoint3D(0.0, innerSignL, 0.0),
          color: railColor,
        ),
      );

      // 5. Solid Inner Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'left_rail_top_flange_inner_$s',
          vertices: [
            CadPoint3D(xStart, yLTopFlange, H - T),
            CadPoint3D(xStart, yLInner, H - T),
            CadPoint3D(xEnd, yLInner, H - T),
            CadPoint3D(xEnd, yLTopFlange, H - T),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: railColor,
          boundaryLines: const [],
        ),
      );

      // 6. Solid Inner Web (with matching pass-through slots)
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'left_rail_web_inner_$s',
          vertices: [
            CadPoint3D(xStart, yLInner, T),
            CadPoint3D(xStart, yLInner, H - T),
            CadPoint3D(xEnd, yLInner, H - T),
            CadPoint3D(xEnd, yLInner, T),
          ],
          normal: CadPoint3D(0.0, innerSignL, 0.0),
          color: railColor,
          holes: leftInnerHoles,
          boundaryLines: const [],
        ),
      );

      // 7. Solid Inner Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'left_rail_bottom_flange_inner_$s',
          vertices: [
            CadPoint3D(xStart, yLInner, T),
            CadPoint3D(xEnd, yLInner, T),
            CadPoint3D(xEnd, yLBottomFlange, T),
            CadPoint3D(xStart, yLBottomFlange, T),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: railColor,
          boundaryLines: const [],
        ),
      );

      final rightWebEdges = <List<CadPoint3D>>[
        [CadPoint3D(xStart, yR, 0.0), CadPoint3D(xEnd, yR, 0.0)],
        [CadPoint3D(xStart, yR, H), CadPoint3D(xEnd, yR, H)],
      ];
      if (isFirst) rightWebEdges.add([CadPoint3D(xStart, yR, 0.0), CadPoint3D(xStart, yR, H)]);
      if (isLast) rightWebEdges.add([CadPoint3D(xEnd, yR, 0.0), CadPoint3D(xEnd, yR, H)]);
      for (final h in rightWebHoles) {
        for (int i = 0; i < h.length; i++) {
          rightWebEdges.add([h[i], h[(i + 1) % h.length]]);
        }
      }

      // --- Right Rail Segment (Solid Thick C-Channel Steel) ---
      // 1. Outer Web
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'right_rail_web_$s',
          vertices: [CadPoint3D(xStart, yR, 0.0), CadPoint3D(xStart, yR, H), CadPoint3D(xEnd, yR, H), CadPoint3D(xEnd, yR, 0.0)],
          normal: const CadPoint3D(0.0, 1.0, 0.0),
          color: railColor,
          holes: rightWebHoles,
          boundaryLines: rightWebEdges,
        ),
      );
      // 2. Outer Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'right_rail_bottom_flange_$s',
          vertices: [CadPoint3D(xStart, yR, 0.0), CadPoint3D(xEnd, yR, 0.0), CadPoint3D(xEnd, yRBottomFlange, 0.0), CadPoint3D(xStart, yRBottomFlange, 0.0)],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: railColor,
          boundaryLines: [
            [CadPoint3D(xStart, yRBottomFlange, 0.0), CadPoint3D(xEnd, yRBottomFlange, 0.0)],
            if (isFirst) [CadPoint3D(xStart, yR, 0.0), CadPoint3D(xStart, yRBottomFlange, 0.0)],
            if (isLast) [CadPoint3D(xEnd, yR, 0.0), CadPoint3D(xEnd, yRBottomFlange, 0.0)],
          ],
        ),
      );
      // 3. Outer Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'right_rail_top_flange_$s',
          vertices: [CadPoint3D(xStart, yR, H), CadPoint3D(xStart, yRTopFlange, H), CadPoint3D(xEnd, yRTopFlange, H), CadPoint3D(xEnd, yR, H)],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: railColor,
          boundaryLines: [
            [CadPoint3D(xStart, yRTopFlange, H), CadPoint3D(xEnd, yRTopFlange, H)],
            if (isFirst) [CadPoint3D(xStart, yR, H), CadPoint3D(xStart, yRTopFlange, H)],
            if (isLast) [CadPoint3D(xEnd, yR, H), CadPoint3D(xEnd, yRTopFlange, H)],
          ],
        ),
      );

      // 4. Solid Thickness Rims / Lips
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_right_top_flange_lip_$s',
          vertices: [
            CadPoint3D(xStart, yRTopFlange, H),
            CadPoint3D(xEnd, yRTopFlange, H),
            CadPoint3D(xEnd, yRTopFlange, H - T),
            CadPoint3D(xStart, yRTopFlange, H - T),
          ],
          normal: CadPoint3D(0.0, innerSignR, 0.0),
          color: railColor,
        ),
      );
      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'RIM_right_bottom_flange_lip_$s',
          vertices: [
            CadPoint3D(xStart, yRBottomFlange, T),
            CadPoint3D(xEnd, yRBottomFlange, T),
            CadPoint3D(xEnd, yRBottomFlange, 0.0),
            CadPoint3D(xStart, yRBottomFlange, 0.0),
          ],
          normal: CadPoint3D(0.0, innerSignR, 0.0),
          color: railColor,
        ),
      );

      // 5. Solid Inner Top Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'right_rail_top_flange_inner_$s',
          vertices: [
            CadPoint3D(xStart, yRTopFlange, H - T),
            CadPoint3D(xEnd, yRTopFlange, H - T),
            CadPoint3D(xEnd, yRInner, H - T),
            CadPoint3D(xStart, yRInner, H - T),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: railColor,
          boundaryLines: const [],
        ),
      );

      // 6. Solid Inner Web (with matching pass-through slots)
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'right_rail_web_inner_$s',
          vertices: [
            CadPoint3D(xStart, yRInner, T),
            CadPoint3D(xEnd, yRInner, T),
            CadPoint3D(xEnd, yRInner, H - T),
            CadPoint3D(xStart, yRInner, H - T),
          ],
          normal: CadPoint3D(0.0, innerSignR, 0.0),
          color: railColor,
          holes: rightInnerHoles,
          boundaryLines: const [],
        ),
      );

      // 7. Solid Inner Bottom Flange
      polygons.add(
        CadFoldedPolygon3D(
          faceId: 'right_rail_bottom_flange_inner_$s',
          vertices: [
            CadPoint3D(xStart, yRInner, T),
            CadPoint3D(xStart, yRBottomFlange, T),
            CadPoint3D(xEnd, yRBottomFlange, T),
            CadPoint3D(xEnd, yRInner, T),
          ],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: railColor,
          boundaryLines: const [],
        ),
      );
    }

    // --- Complete End Port Caps (Port 1 at X=0, Port 2 at X=L) ---
    // Caps the entire C-channel profile (web, top flange, bottom flange) for solid thick steel
    // Port 1 at X=0 (Normal in -X)
    thicknessPolygons.addAll([
      // Left Rail End Caps
      CadFoldedPolygon3D(
        faceId: 'RIM_left_port1_web',
        vertices: [CadPoint3D(0.0, yL, 0.0), CadPoint3D(0.0, yL, H), CadPoint3D(0.0, yLInner, H), CadPoint3D(0.0, yLInner, 0.0)],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_left_port1_top_flange',
        vertices: [CadPoint3D(0.0, yL, H), CadPoint3D(0.0, yLTopFlange, H), CadPoint3D(0.0, yLTopFlange, H - T), CadPoint3D(0.0, yLInner, H - T)],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_left_port1_bottom_flange',
        vertices: [CadPoint3D(0.0, yL, 0.0), CadPoint3D(0.0, yLInner, T), CadPoint3D(0.0, yLBottomFlange, T), CadPoint3D(0.0, yLBottomFlange, 0.0)],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      // Right Rail End Caps
      CadFoldedPolygon3D(
        faceId: 'RIM_right_port1_web',
        vertices: [CadPoint3D(0.0, yR, 0.0), CadPoint3D(0.0, yRInner, 0.0), CadPoint3D(0.0, yRInner, H), CadPoint3D(0.0, yR, H)],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_right_port1_top_flange',
        vertices: [CadPoint3D(0.0, yR, H), CadPoint3D(0.0, yRInner, H - T), CadPoint3D(0.0, yRTopFlange, H - T), CadPoint3D(0.0, yRTopFlange, H)],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_right_port1_bottom_flange',
        vertices: [CadPoint3D(0.0, yR, 0.0), CadPoint3D(0.0, yRBottomFlange, 0.0), CadPoint3D(0.0, yRBottomFlange, T), CadPoint3D(0.0, yRInner, T)],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: railColor,
      ),
    ]);

    // Port 2 at X=L (Normal in +X)
    thicknessPolygons.addAll([
      // Left Rail End Caps
      CadFoldedPolygon3D(
        faceId: 'RIM_left_port2_web',
        vertices: [CadPoint3D(L, yL, 0.0), CadPoint3D(L, yLInner, 0.0), CadPoint3D(L, yLInner, H), CadPoint3D(L, yL, H)],
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_left_port2_top_flange',
        vertices: [CadPoint3D(L, yL, H), CadPoint3D(L, yLInner, H - T), CadPoint3D(L, yLTopFlange, H - T), CadPoint3D(L, yLTopFlange, H)],
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_left_port2_bottom_flange',
        vertices: [CadPoint3D(L, yL, 0.0), CadPoint3D(L, yLBottomFlange, 0.0), CadPoint3D(L, yLBottomFlange, T), CadPoint3D(L, yLInner, T)],
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: railColor,
      ),
      // Right Rail End Caps
      CadFoldedPolygon3D(
        faceId: 'RIM_right_port2_web',
        vertices: [CadPoint3D(L, yR, 0.0), CadPoint3D(L, yR, H), CadPoint3D(L, yRInner, H), CadPoint3D(L, yRInner, 0.0)],
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_right_port2_top_flange',
        vertices: [CadPoint3D(L, yR, H), CadPoint3D(L, yRTopFlange, H), CadPoint3D(L, yRTopFlange, H - T), CadPoint3D(L, yRInner, H - T)],
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: railColor,
      ),
      CadFoldedPolygon3D(
        faceId: 'RIM_right_port2_bottom_flange',
        vertices: [CadPoint3D(L, yR, 0.0), CadPoint3D(L, yRInner, T), CadPoint3D(L, yRBottomFlange, T), CadPoint3D(L, yRBottomFlange, 0.0)],
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: railColor,
      ),
    ]);

    // --- 3. C-CHANNEL RUNGS (40x20mm with slotted top web & downward flanges) ---
    const double rungW = 40.0;
    const double rungDepth = 20.0;
    final double zRungTop = rungCenterZ + (rungDepth / 2.0);

    // Y bounds of each rung depending on joint method:
    // In Direct Inside Weld: rungs terminate flush at the inside mating faces (yLInner to yRInner)
    // In Pass-Through Outside Weld: rungs pass through the rails and project by outsideWeldProjection
    final double yRungStart = params.jointMethod == LadderRungJointMethod.directInsideWeld ? yL : yL - params.outsideWeldProjection;
    final double yRungEnd = params.jointMethod == LadderRungJointMethod.directInsideWeld ? yR : yR + params.outsideWeldProjection;

    for (int i = 0; i < stations.length; i++) {
      final double xMid = stations[i];
      final rungPolys = generateSlottedRung3DPolygons(
        rungId: 'rung_$i',
        xCenter: xMid,
        yStart: yRungStart,
        yEnd: yRungEnd,
        zTop: zRungTop,
        rungW: rungW,
        rungDepth: rungDepth,
        thickness: T,
        color: rungColor,
        interiorHalfWidth: halfW,
      );
      polygons.addAll(rungPolys);
    }

    return FoldedMeshResult(
      polygons: polygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: params.width + (2 * F),
      boundLength: L,
      boundHeight: H,
      center: CadPoint3D(L / 2.0, 0.0, H / 2.0),
    );
  }

  static FoldedMeshResult _generateCoverMesh3D({required LadderAssemblyParameters params}) {
    final polygons = <CadFoldedPolygon3D>[];
    final double L = params.length;
    final double halfW = (params.width / 2.0) + 2.0; // 2mm clearance over rails
    final double zCover = params.height + 2.0;
    const coverColor = Color(0xFFB0BEC5);

    // Main horizontal cover roof
    polygons.add(
      CadFoldedPolygon3D(
        faceId: 'cover_roof',
        vertices: [CadPoint3D(0.0, -halfW, zCover), CadPoint3D(L, -halfW, zCover), CadPoint3D(L, halfW, zCover), CadPoint3D(0.0, halfW, zCover)],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: coverColor,
      ),
    );

    // Left and right downward lips
    final double zLip = zCover - params.coverHeight;
    polygons.add(
      CadFoldedPolygon3D(
        faceId: 'cover_left_lip',
        vertices: [CadPoint3D(0.0, -halfW, zCover), CadPoint3D(0.0, -halfW, zLip), CadPoint3D(L, -halfW, zLip), CadPoint3D(L, -halfW, zCover)],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: coverColor,
      ),
    );

    polygons.add(
      CadFoldedPolygon3D(
        faceId: 'cover_right_lip',
        vertices: [CadPoint3D(0.0, halfW, zCover), CadPoint3D(L, halfW, zCover), CadPoint3D(L, halfW, zLip), CadPoint3D(0.0, halfW, zLip)],
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        color: coverColor,
      ),
    );

    return FoldedMeshResult(
      polygons: polygons,
      boundWidth: params.width + 4.0,
      boundLength: L,
      boundHeight: params.coverHeight,
      center: CadPoint3D(L / 2.0, 0.0, zCover),
    );
  }

  // ---------------------------------------------------------------------------
  // BILL OF MATERIALS & HARDWARE TAKEOFF
  // ---------------------------------------------------------------------------

  static LadderHardwareBOM _calculateBOM({required LadderAssemblyParameters params, required int rungCount, required double rungCutLength}) {
    final bool isPassThrough = params.jointMethod == LadderRungJointMethod.passThroughOutsideWeld;
    final int slotCount = isPassThrough ? (2 * rungCount) : 0;
    final int weldCount = 2 * rungCount;

    // Approximate weld seam length per rung joint:
    // C-channel has perimeter: 20mm + 40mm + 20mm = 80mm
    final double weldPerJointMm = isPassThrough ? 120.0 : 80.0;
    final double totalWeldMm = weldCount * weldPerJointMm;

    // Total steel weight calculation
    final double railAreaM2 = 2 * (params.length / 1000.0) * ((params.height + 2 * params.flangeWidth) / 1000.0);
    const double rungBlankWidthM = 0.080;
    final double rungAreaM2 = rungCount * (rungCutLength / 1000.0) * rungBlankWidthM;
    final double totalAreaM2 = railAreaM2 + rungAreaM2;
    final double totalWeightKg = totalAreaM2 * (params.thickness / 1000.0) * densitySteel;

    final int coverClamps = params.includeCover ? math.max(4, (params.length / 600.0).round()) : 0;

    return LadderHardwareBOM(
      rungCount: rungCount,
      passThroughSlotCount: slotCount,
      weldJointCount: weldCount,
      totalWeldLengthMm: totalWeldMm,
      spliceCouplerCount: 2,
      couplerBoltCount: 8,
      couplerNutCount: 8,
      couplerWasherCount: 8,
      holdDownClampCount: 2,
      holdDownBoltCount: 2,
      coverClampCount: coverClamps,
      totalSteelWeightKg: double.parse(totalWeightKg.toStringAsFixed(2)),
    );
  }

  // ---------------------------------------------------------------------------
  // DSF DOCUMENT SERIALIZATION & CATALOG EXPORT
  // ---------------------------------------------------------------------------

  /// Converts a multi-part [DsfLadderAssembly] into a unified multi-blank [DsfDocument].
  static DsfDocument createAssemblyDsfDocument(DsfLadderAssembly assembly) {
    // 1. Deduplicate constituent blanks so the user sees only 1 copy of unique entities.
    // For standard ladder: display 1 side rail and 1 rung (remaining are identical copies).
    // For accessories: display distinct rails and distinct rungs (if sizes vary along the product's path).
    final parts = <CadPart>[];

    // Side Rails deduplication:
    final leftRail = assembly.leftRailBlank;
    final rightRail = assembly.rightRailBlank;

    bool areBlanksIdentical(CadPart a, CadPart b) {
      if ((a.flatBlankLength - b.flatBlankLength).abs() > 0.5) return false;
      if ((a.flatBlankWidth - b.flatBlankWidth).abs() > 0.5) return false;
      if (a.outerContour.length != b.outerContour.length) return false;
      if (a.geometries.length != b.geometries.length) return false;
      return true;
    }

    if (areBlanksIdentical(leftRail, rightRail)) {
      parts.add(
        CadPart(
          id: 'side_rail_blank',
          name: 'Side Rail Blank (Qty: 2)',
          material: leftRail.material,
          outerContour: leftRail.outerContour,
          geometries: leftRail.geometries,
          flatBlankWidth: leftRail.flatBlankWidth,
          flatBlankLength: leftRail.flatBlankLength,
        ),
      );
    } else {
      parts.add(leftRail);
      parts.add(rightRail);
    }

    // Rungs deduplication:
    final uniqueRungLengths = <double, int>{};
    for (final r in assembly.rungs) {
      final len = (r.cutLength * 10).round() / 10.0;
      final existingKey = uniqueRungLengths.keys.where((k) => (k - len).abs() < 0.5).firstOrNull;
      if (existingKey != null) {
        uniqueRungLengths[existingKey] = uniqueRungLengths[existingKey]! + 1;
      } else {
        uniqueRungLengths[len] = 1;
      }
    }

    if (uniqueRungLengths.isEmpty) {
      parts.add(assembly.rungBlank);
    } else if (uniqueRungLengths.length == 1) {
      final entry = uniqueRungLengths.entries.first;
      final rungPart = generateCustomRungFlatBlank(rungCutLength: entry.key, material: assembly.rungBlank.material);
      parts.add(
        CadPart(
          id: 'rung_blank',
          name: 'Rung Blank (Qty: ${entry.value})',
          material: rungPart.material,
          outerContour: rungPart.outerContour,
          geometries: rungPart.geometries,
          flatBlankWidth: rungPart.flatBlankWidth,
          flatBlankLength: rungPart.flatBlankLength,
        ),
      );
    } else {
      int rIdx = 1;
      for (final entry in uniqueRungLengths.entries) {
        final rungPart = generateCustomRungFlatBlank(rungCutLength: entry.key, material: assembly.rungBlank.material);
        parts.add(
          CadPart(
            id: 'rung_blank_$rIdx',
            name: 'Rung Blank ${entry.key.toStringAsFixed(1)}mm (Qty: ${entry.value})',
            material: rungPart.material,
            outerContour: rungPart.outerContour,
            geometries: rungPart.geometries,
            flatBlankWidth: rungPart.flatBlankWidth,
            flatBlankLength: rungPart.flatBlankLength,
          ),
        );
        rIdx++;
      }
    }

    if (assembly.coverBlank != null) {
      parts.add(assembly.coverBlank!);
    }

    final allCutLines = <CadLineSegment>[];
    final allBends = <FoldBendLine>[];
    final allPunches = <CncPunchPrimitive>[];
    final allFaces = <PlanarSheetFace>[];

    double currentOffsetX = 0.0;
    double maxPartHeight = 0.0;

    for (int pIdx = 0; pIdx < parts.length; pIdx++) {
      final part = parts[pIdx];
      final partDoc = DxfExporter.partToDsfDocument(part);

      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final pt in part.outerContour) {
        if (pt.x < minX) minX = pt.x;
        if (pt.y < minY) minY = pt.y;
        if (pt.x > maxX) maxX = pt.x;
        if (pt.y > maxY) maxY = pt.y;
      }
      final partW = (minX.isFinite && maxX.isFinite) ? (maxX - minX) : 100.0;
      final partH = (minY.isFinite && maxY.isFinite) ? (maxY - minY) : 100.0;

      // Rotate 90° CCW if wide so length is vertical along Y
      final bool rotate90 = partW >= partH;
      final double placedW = rotate90 ? partH : partW;
      final double placedH = rotate90 ? partW : partH;
      if (placedH > maxPartHeight) maxPartHeight = placedH;

      CadPoint2D transformPt(CadPoint2D pt) {
        if (rotate90) {
          return CadPoint2D(currentOffsetX + (maxY - pt.y), pt.x - minX);
        } else {
          return CadPoint2D(currentOffsetX + (pt.x - minX), pt.y - minY);
        }
      }

      // Independent planar face for this blank (avoids artificial enclosing sheet)
      allFaces.add(
        PlanarSheetFace(
          id: part.id,
          label: part.name.isNotEmpty ? part.name : 'Component Blank',
          role: FaceRole.baseFloor,
          vertices: part.outerContour.map(transformPt).toList(),
        ),
      );

      // Outer contour to cutLines (showLabel: false avoids clutter of CUT badges on outer blank boundary)
      for (int i = 0; i < part.outerContour.length; i++) {
        final pt1 = part.outerContour[i];
        final pt2 = part.outerContour[(i + 1) % part.outerContour.length];
        allCutLines.add(CadLineSegment(id: '${part.id}_cut_$i', p1: transformPt(pt1), p2: transformPt(pt2), layer: 'OUTLINE', showLabel: false));
      }

      // Bends
      for (final b in partDoc.bends) {
        allBends.add(
          FoldBendLine(
            id: '${part.id}_${b.id}',
            p1: transformPt(b.p1),
            p2: transformPt(b.p2),
            targetAngleDeg: b.targetAngleDeg,
            radiusMm: b.radiusMm,
            direction: b.direction,
            kFactor: b.kFactor,
          ),
        );
      }

      // Punches
      for (final p in partDoc.punches) {
        allPunches.add(
          CncPunchPrimitive(
            id: '${part.id}_${p.id}',
            center: transformPt(p.center),
            type: p.type,
            widthMm: p.widthMm,
            lengthMm: p.lengthMm,
            diameterMm: p.diameterMm,
            rotationDeg: rotate90 ? ((p.rotationDeg + 90.0) % 360.0) : p.rotationDeg,
            role: p.role,
            layer: p.layer,
          ),
        );
      }

      // Cut lines from partDoc
      for (final cl in partDoc.cutLines) {
        allCutLines.add(CadLineSegment(id: '${part.id}_${cl.id}', p1: transformPt(cl.p1), p2: transformPt(cl.p2), layer: cl.layer));
      }

      if (part.id == 'rung_blank' || part.id.startsWith('rung_blank')) {
        // Draw the authentic C-Channel Cross-Section profile (40x20mm) next to the rung top view (per ISO Datasheet)
        final double csX = currentOffsetX + placedW + 25.0;
        const double csW = 40.0;
        const double csH = 20.0;
        const double csT = 2.0;
        const double csY = 20.0;

        final channelProfileLines = [
          CadLineSegment(id: 'rung_cs_outer_left', p1: CadPoint2D(csX, csY + csH), p2: CadPoint2D(csX, csY), layer: 'OUTLINE', showLabel: false),
          CadLineSegment(id: 'rung_cs_outer_bottom', p1: CadPoint2D(csX, csY), p2: CadPoint2D(csX + csW, csY), layer: 'OUTLINE', showLabel: false),
          CadLineSegment(id: 'rung_cs_outer_right', p1: CadPoint2D(csX + csW, csY), p2: CadPoint2D(csX + csW, csY + csH), layer: 'OUTLINE', showLabel: false),
          CadLineSegment(
            id: 'rung_cs_lip_right',
            p1: CadPoint2D(csX + csW, csY + csH),
            p2: CadPoint2D(csX + csW - csT, csY + csH),
            layer: 'OUTLINE',
            showLabel: false,
          ),
          CadLineSegment(
            id: 'rung_cs_inner_right',
            p1: CadPoint2D(csX + csW - csT, csY + csH),
            p2: CadPoint2D(csX + csW - csT, csY + csT),
            layer: 'OUTLINE',
            showLabel: false,
          ),
          CadLineSegment(
            id: 'rung_cs_inner_bottom',
            p1: CadPoint2D(csX + csW - csT, csY + csT),
            p2: CadPoint2D(csX + csT, csY + csT),
            layer: 'OUTLINE',
            showLabel: false,
          ),
          CadLineSegment(
            id: 'rung_cs_inner_left',
            p1: CadPoint2D(csX + csT, csY + csT),
            p2: CadPoint2D(csX + csT, csY + csH),
            layer: 'OUTLINE',
            showLabel: false,
          ),
          CadLineSegment(id: 'rung_cs_lip_left', p1: CadPoint2D(csX + csT, csY + csH), p2: CadPoint2D(csX, csY + csH), layer: 'OUTLINE', showLabel: false),
        ];
        allCutLines.addAll(channelProfileLines);
        currentOffsetX += csW + 35.0;
      }

      currentOffsetX += placedW + 80.0;
    }

    final outerContour = <CadPoint2D>[];

    final isStraight =
        !assembly.id.contains('BEND') &&
        !assembly.id.contains('RISER') &&
        !assembly.id.contains('TEE') &&
        !assembly.id.contains('CROSS') &&
        !assembly.id.contains('REDUCER');
    final category = isStraight ? FittingCategory.length : FittingCategory.ladderAccessories;
    final product = isStraight
        ? 'Ladder'
        : (assembly.id.contains('BEND')
              ? FittingProductType.bend
              : (assembly.id.contains('IN-RISER')
                    ? FittingProductType.insideRiser
                    : (assembly.id.contains('OUT-RISER')
                          ? FittingProductType.outsideRiser
                          : (assembly.id.contains('TEE')
                                ? FittingProductType.tee
                                : (assembly.id.contains('CROSS')
                                      ? FittingProductType.cross
                                      : (assembly.id.contains('REDUCER') ? FittingProductType.reducer : 'Ladder'))))));

    final fittingMeta = DxfFittingMetadata(
      category: category,
      product: product,
      variantName: assembly.productName,
      flangeMm: assembly.parameters.flangeWidth,
      parameters: {
        'width': assembly.parameters.width,
        'height': assembly.parameters.height,
        'length': assembly.parameters.length,
        'thickness': assembly.parameters.thickness,
        'flange_width': assembly.parameters.flangeWidth,
        'rung_cut_length': assembly.parameters.physicalRungCutLength,
        'end_margin_pitch': assembly.parameters.endMarginPitch,
        'rung_pitch': assembly.parameters.intermediateTargetPitch,
      },
    );

    return DsfDocument(
      productType: 'cable_ladder',
      itemName: assembly.productName,
      material: assembly.leftRailBlank.material,
      outerContour: outerContour,
      faces: allFaces,
      baseFaceId: allFaces.isNotEmpty ? allFaces.first.id : '',
      bends: allBends,
      punches: allPunches,
      cutLines: allCutLines,
      parameters: {
        'width': assembly.parameters.width,
        'height': assembly.parameters.height,
        'length': assembly.parameters.length,
        'thickness': assembly.parameters.thickness,
        'flange_width': assembly.parameters.flangeWidth,
        'flange_direction': assembly.parameters.flangeDirection == LadderFlangeDirection.outside ? 1.0 : 0.0,
        'accessory_style': assembly.parameters.accessoryStyle == LadderAccessoryStyle.segmented ? 1.0 : 0.0,
        'rung_cut_length': assembly.parameters.physicalRungCutLength,
        'rung_joint_method': assembly.parameters.jointMethod == LadderRungJointMethod.passThroughOutsideWeld ? 1.0 : 0.0,
        'outside_weld_projection': assembly.parameters.outsideWeldProjection,
        'end_margin_pitch': assembly.parameters.endMarginPitch,
        'rung_pitch': assembly.parameters.intermediateTargetPitch,
        'rung_count': assembly.hardwareBOM.rungCount.toDouble(),
        'total_weight_kg': assembly.hardwareBOM.totalSteelWeightKg,
      },
      metadata: {
        'isLadderAssembly': true,
        'assemblyId': assembly.id,
        'productCode': assembly.id.toUpperCase(),
        'fittingMetadata': fittingMeta.toJson(),
        'category': category,
        'fittingCategory': category,
        'product': product,
        'fittingProduct': product,
        'variantName': assembly.productName,
        'fittingVariant': assembly.productName,
        'ladderParameters': assembly.parameters.toJson(),
        'rungCount': assembly.hardwareBOM.rungCount,
        'totalSteelWeightKg': assembly.hardwareBOM.totalSteelWeightKg,
        'passThroughSlotCount': assembly.hardwareBOM.passThroughSlotCount,
        'weldJointCount': assembly.hardwareBOM.weldJointCount,
        'totalWeldLengthMm': assembly.hardwareBOM.totalWeldLengthMm,
      },
    );
  }

  /// Synthesizes or reconstructs a full [DsfLadderAssembly] from any ladder [DsfDocument].
  static DsfLadderAssembly generateFromDocument(DsfDocument doc) {
    LadderAssemblyParameters params;
    final ladderParamMap = doc.metadata['ladderParameters'];
    if (ladderParamMap is Map) {
      final mergedMap = Map<String, dynamic>.from(ladderParamMap);
      if (doc.parameters.containsKey('width')) mergedMap['width'] = doc.parameters['width'];
      if (doc.parameters.containsKey('height')) mergedMap['height'] = doc.parameters['height'];
      if (doc.parameters.containsKey('length')) mergedMap['length'] = doc.parameters['length'];
      if (doc.parameters.containsKey('flange_width')) mergedMap['flangeWidth'] = doc.parameters['flange_width'];
      if (doc.parameters.containsKey('thickness')) mergedMap['thickness'] = doc.parameters['thickness'];
      if (doc.parameters.containsKey('flange_direction')) {
        mergedMap['flangeDirection'] = doc.parameters['flange_direction']! > 0.5 ? 'outside' : 'inside';
      }
      if (doc.parameters.containsKey('accessory_style')) {
        mergedMap['accessoryStyle'] = doc.parameters['accessory_style'] == 1.0 ? 'segmented' : 'curved';
      }
      if (doc.parameters.containsKey('rung_joint_method')) {
        mergedMap['jointMethod'] = doc.parameters['rung_joint_method']! > 0.5 ? 'passThroughOutsideWeld' : 'directInsideWeld';
      }
      if (doc.parameters.containsKey('rung_pitch')) {
        mergedMap['intermediateTargetPitch'] = doc.parameters['rung_pitch'];
      }
      if (doc.parameters.containsKey('outside_weld_projection')) {
        mergedMap['outsideWeldProjection'] = doc.parameters['outside_weld_projection'];
      }
      if (doc.parameters.containsKey('outsideWeldProjection')) {
        mergedMap['outsideWeldProjection'] = doc.parameters['outsideWeldProjection'];
      }
      if (doc.parameters.containsKey('end_margin_pitch')) {
        mergedMap['endMarginPitch'] = doc.parameters['end_margin_pitch'];
      }
      if (doc.parameters.containsKey('endMarginPitch')) {
        mergedMap['endMarginPitch'] = doc.parameters['endMarginPitch'];
      }
      if (doc.parameters.containsKey('include_cover')) {
        mergedMap['includeCover'] = doc.parameters['include_cover']! > 0.5;
      }
      if (doc.parameters.containsKey('includeCover')) {
        mergedMap['includeCover'] = doc.parameters['includeCover']! > 0.5;
      }
      params = LadderAssemblyParameters.fromJson(mergedMap);
    } else {
      final targetPitch = (doc.parameters['rung_pitch'] ?? doc.parameters['intermediateTargetPitch'] ?? 250.0).toDouble();
      params = LadderAssemblyParameters(
        width: (doc.parameters['width'] ?? 600.0).toDouble(),
        height: (doc.parameters['height'] ?? 100.0).toDouble(),
        length: (doc.parameters['length'] ?? 3000.0).toDouble(),
        thickness: (doc.parameters['thickness'] ?? doc.material.thicknessMm).toDouble(),
        flangeWidth: (doc.parameters['flange_width'] ?? doc.parameters['flangeWidth'] ?? 32.0).toDouble(),
        flangeDirection: (doc.parameters['flange_direction'] ?? 0.0) > 0.5 ? LadderFlangeDirection.outside : LadderFlangeDirection.inside,
        accessoryStyle: (doc.parameters['accessory_style'] == 0.0 || (doc.metadata['accessoryStyle']?.toString().contains('curve') ?? false))
            ? LadderAccessoryStyle.curved
            : LadderAccessoryStyle.segmented,
        jointMethod: (doc.parameters['rung_joint_method'] ?? 1.0) > 0.5 ? LadderRungJointMethod.passThroughOutsideWeld : LadderRungJointMethod.directInsideWeld,
        outsideWeldProjection: (doc.parameters['outside_weld_projection'] ?? doc.parameters['outsideWeldProjection'] ?? 3.5).toDouble(),
        endMarginPitch: (doc.parameters['end_margin_pitch'] ?? doc.parameters['endMarginPitch'] ?? (targetPitch / 2.0)).toDouble(),
        intermediateTargetPitch: targetPitch,
        includeCover: (doc.parameters['include_cover'] ?? doc.parameters['includeCover'] ?? 0.0) > 0.5,
        materialName: doc.material.materialGrade.isNotEmpty ? doc.material.materialGrade : 'HDG',
        paintCoat: doc.material.paintCoat,
      );
    }

    final id = (doc.metadata['assemblyId']?.toString() ?? doc.itemName).toUpperCase();
    final name = doc.itemName.toLowerCase();

    if (id.contains('BEND') || name.contains('bend')) {
      final angle = (doc.parameters['angle'] ?? doc.parameters['bend_angle'] ?? (name.contains('45') ? 45.0 : 90.0)).toDouble();
      final radius = (doc.parameters['radius'] ?? 300.0).toDouble();
      return generateHorizontalBend(angleDeg: angle, radiusMm: radius, params: params);
    } else if (id.contains('IN-RISER') || (name.contains('inside') && name.contains('riser'))) {
      final angle = (doc.parameters['angle'] ?? (name.contains('45') ? 45.0 : 90.0)).toDouble();
      final radius = (doc.parameters['radius'] ?? 300.0).toDouble();
      return generateRiser(angleDeg: angle, radiusMm: radius, isInsideRiser: true, params: params);
    } else if (id.contains('OUT-RISER') || (name.contains('outside') && name.contains('riser'))) {
      final angle = (doc.parameters['angle'] ?? (name.contains('45') ? 45.0 : 90.0)).toDouble();
      final radius = (doc.parameters['radius'] ?? 300.0).toDouble();
      return generateRiser(angleDeg: angle, radiusMm: radius, isInsideRiser: false, params: params);
    } else if (id.contains('TEE') || name.contains('tee')) {
      final branchW = (doc.parameters['branch_width'] ?? doc.parameters['port3_width'] ?? params.width).toDouble();
      final radius = (doc.parameters['radius'] ?? 300.0).toDouble();
      return generateTee(mainWidth: params.width, branchWidth: branchW, radiusMm: radius, params: params);
    } else if (id.contains('CROSS') || name.contains('cross')) {
      final branchW = (doc.parameters['branch_width'] ?? doc.parameters['port4_width'] ?? params.width).toDouble();
      final radius = (doc.parameters['radius'] ?? 300.0).toDouble();
      return generateCross(mainWidth: params.width, branchWidth: branchW, radiusMm: radius, params: params);
    } else if (id.contains('REDUCER') || name.contains('reducer')) {
      final w2 = (doc.parameters['width2'] ?? doc.parameters['port2_width'] ?? params.width / 2.0).toDouble();
      final len = (doc.parameters['length'] ?? 500.0).toDouble();
      final align = doc.parameters['reducer_alignment'] == 1.0 ? 'left' : (doc.parameters['reducer_alignment'] == 2.0 ? 'right' : 'straight');
      return generateReducer(width1: params.width, width2: w2, length: len, alignment: align, params: params);
    } else {
      return generateStraightLadder(params);
    }
  }

  /// Saves the [DsfLadderAssembly] as a JSON-encoded .dsf file in `assets/dsf_templates/ladders/`.
  static Future<File> saveAssemblyDsfFile(DsfLadderAssembly assembly, {String? fileName, String? targetDirectory}) async {
    final dsfDoc = createAssemblyDsfDocument(assembly);
    final dirPath = targetDirectory ?? 'assets/dsf_templates/ladders';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final cleanName = (fileName != null && fileName.trim().isNotEmpty)
        ? (fileName.endsWith('.dsf') ? fileName.trim() : '${fileName.trim()}.dsf')
        : '${assembly.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_').toLowerCase()}.dsf';
    final file = File('${dir.path}/$cleanName');
    final jsonStr = dsfDoc.toPrettyJson();
    await file.writeAsString(jsonStr);
    return file;
  }
}
