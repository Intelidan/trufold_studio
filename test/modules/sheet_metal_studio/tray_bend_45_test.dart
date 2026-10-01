import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';

import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_bend_45_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_dsf_importer.dart';

void main() {
  test('Inspect Tray 45 Deg Bend 100x50 DXF', () {
    final file = File('assets/dxf_templates/tray_accessories/45_deg_bend_100x50.dxf');
    final dxfDoc = DxfDsfImporter.importDxf(file.readAsStringSync(), productType: 'bend', itemName: '45_deg_bend_100x50.dxf');
    expect(dxfDoc.outerContour.length, greaterThan(10));
    expect(dxfDoc.punches.length, 15);
  });


  test('Verify Tray 45 Deg Bend Baseline, Openings, Cover Snapping, and Scaling', () {
    final file = File('assets/dxf_templates/tray_accessories/45_deg_bend_100x50.dxf');
    final dxfDoc = DxfDsfImporter.importDxf(file.readAsStringSync(), productType: 'bend', itemName: '45_deg_bend_100x50.dxf');

    // Build the baseline DSF document
    final bends = [
      const FoldBendLine(id: 'B1', p1: CadPoint2D(262.37739947550995, 63.0), p2: CadPoint2D(62.37739947550995, 63.0), direction: BendDirection.up, targetAngleDeg: 90.0, parentFaceId: 'F_6', childFaceId: 'F_8'),
      const FoldBendLine(id: 'B2', p1: CadPoint2D(254.7281661832228, 174.40763620066042), p2: CadPoint2D(70.02663276779799, 174.40763620066042), direction: BendDirection.up, targetAngleDeg: 90.0, parentFaceId: 'F_6', childFaceId: 'F_1'),
      const FoldBendLine(id: 'B3', p1: CadPoint2D(254.7281661832228, 174.40763620066042), p2: CadPoint2D(300.6457427120191, 155.38795325112835), direction: BendDirection.up, targetAngleDeg: 90.0, parentFaceId: 'F_6', childFaceId: 'F_3'),
      const FoldBendLine(id: 'B4', p1: CadPoint2D(70.02663276779799, 174.40763620066042), p2: CadPoint2D(24.109056239001124, 155.3879532511281), direction: BendDirection.up, targetAngleDeg: 90.0, parentFaceId: 'F_6', childFaceId: 'F_5'),
      const FoldBendLine(id: 'FL1', p1: CadPoint2D(62.37739947550995, 17.69180601295459), p2: CadPoint2D(262.37739947550995, 17.69180601295459), direction: BendDirection.up, targetAngleDeg: 135.0, role: BendLineRole.flange, parentFaceId: 'F_8', childFaceId: 'F_7'),
      const FoldBendLine(id: 'FL2', p1: CadPoint2D(50.89246114954199, 220.60161282622522), p2: CadPoint2D(4.818484962595159, 201.40715285929096), direction: BendDirection.up, targetAngleDeg: 135.0, role: BendLineRole.flange, parentFaceId: 'F_5', childFaceId: 'F_4'),
      const FoldBendLine(id: 'FL3', p1: CadPoint2D(70.02663276779799, 224.40763620066042), p2: CadPoint2D(254.7281661832228, 224.40763620066042), direction: BendDirection.up, targetAngleDeg: 135.0, role: BendLineRole.flange, parentFaceId: 'F_1', childFaceId: 'F_0'),
      const FoldBendLine(id: 'FL4', p1: CadPoint2D(273.8623378014779, 220.60161282622522), p2: CadPoint2D(319.9363139884247, 201.40715285929096), direction: BendDirection.up, targetAngleDeg: 135.0, role: BendLineRole.flange, parentFaceId: 'F_3', childFaceId: 'F_2'),
    ];

    // Decompose planar faces from contour and bends
    final decomp = PlanarFaceDecomposer.decompose(outerContour: dxfDoc.outerContour, bends: bends);

    final punches = dxfDoc.punches.map((p) {
      final isCoupler = {'SLOT_4', 'SLOT_7', 'SLOT_10', 'SLOT_11', 'SLOT_14', 'SLOT_15'}.contains(p.id);
      return p.copyWith(role: isCoupler ? CncPunchRole.coupler : CncPunchRole.perforation);
    }).toList();

    final baselineDoc = dxfDoc.copyWith(
      itemName: '45_deg_bend_100x50.dxf',
      productType: 'bend',
      bends: bends,
      faces: decomp.faces,
      baseFaceId: decomp.baseFaceId,
      punches: punches,
      parameters: {'width': 100.0, 'height': 50.0, 'port1_width': 100.0, 'port1_height': 50.0, 'port2_width': 100.0, 'port2_height': 50.0},
    );

    // Save clean baseline to assets/dsf_templates/tray_accessories/45_deg_bend_100x50.dsf
    final dsfOut = File('assets/dsf_templates/tray_accessories/45_deg_bend_100x50.dsf');
    dsfOut.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(baselineDoc.toJson()));

    // 1. Check Bend Angle display
    for (final b in baselineDoc.bends) {
      if (b.role == BendLineRole.flange) {
        expect(b.displayAngleDeg, 45.0);
        expect(b.targetAngleDeg, 135.0);
      }
    }

    // 2. Fold baseline and check opening detection
    final foldResult = KinematicFoldEngine.foldDocument(baselineDoc, foldProgress: 1.0);
    final openings = Cms3DOpeningDetector.detectOpenings(document: baselineDoc, foldResult: foldResult);
    expect(openings.length, 2);

    for (final raw in openings) {
      final measured = CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: baselineDoc, foldResult: foldResult);
      expect(measured.derivedMouthCorners.length, 4);
      expect(measured.flatP1, isNotNull);
      expect(measured.flatP2, isNotNull);
    }

    // Verify bend display angle (45° acute display for 135° inward return flange)
    final fl1 = baselineDoc.bends.firstWhere((b) => b.id == 'FL1');
    expect(fl1.displayAngleDeg, 45.0);

    // 3. Test Cover Generation and Snapping
    final cover = TrunkingCoverGenerator.generateCover(baselineDoc);
    expect(cover, isNotNull);
    final bodyHeightProp = (cover!.properties['bodyHeightMm'] as num).toDouble();
    expect(bodyHeightProp, closeTo(50.0, 2.0));
    final clearanceZ = (cover.properties['snappedClearanceZ'] as num).toDouble();
    expect(clearanceZ, closeTo(0.5, 0.1));

    // 4. Test Scaling via TrayBend45Scaler
    final scaled120 = TrayBend45Scaler.scale(
      baseline: baselineDoc,
      targetWidth: 120.0,
      targetHeight: 120.0,
    );
    expect(scaled120.parameters['width'], 120.0);
    expect(scaled120.parameters['height'], 120.0);

    final foldScaled = KinematicFoldEngine.foldDocument(scaled120, foldProgress: 1.0);
    expect(foldScaled.polygons.length, greaterThanOrEqualTo(9));

    final scaledOpenings = Cms3DOpeningDetector.detectOpenings(document: scaled120, foldResult: foldScaled);
    expect(scaledOpenings.length, 2);
    for (final raw in scaledOpenings) {
      final measured = CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: scaled120, foldResult: foldScaled);
      expect(measured.height, closeTo(120.0, 5.0));
    }

    // 5. Test SS3: Reduced Width (W = 50mm)
    final scaled50 = TrayBend45Scaler.scale(
      baseline: baselineDoc,
      targetWidth: 50.0,
      targetHeight: 50.0,
    );
    expect(scaled50.parameters['width'], 50.0);
    final b4_50 = scaled50.bends.firstWhere((b) => b.id == 'B4');
    final b4Len50 = b4_50.p1.distanceTo(b4_50.p2);
    expect(b4Len50, closeTo(36.9, 1.0)); // Wing scales down proportionally with K_wing = 0.2557

    final fold50 = KinematicFoldEngine.foldDocument(scaled50, foldProgress: 1.0);
    expect(fold50.polygons.length, greaterThanOrEqualTo(9));

    // 6. Test Changed Height (H = 100mm adds coupler rows)
    final scaled100 = TrayBend45Scaler.scale(
      baseline: baselineDoc,
      targetWidth: 100.0,
      targetHeight: 100.0,
    );
    expect(scaled100.parameters['height'], 100.0);
    final couplerSlots100 = scaled100.punches.where((p) => p.role == CncPunchRole.coupler).toList();
    expect(couplerSlots100.length, 20); // B1 has 3 rows × 4 = 12, wings have 4 holes × 2 = 8. Total = 20 (per 25mm increment rule)

    final fold100 = KinematicFoldEngine.foldDocument(scaled100, foldProgress: 1.0);
    expect(fold100.polygons.length, greaterThanOrEqualTo(9));

    // 7. Test Expanded Width (W = 200mm): B1 is invariant (200mm), wing grows to ~75.3mm
    final scaled200 = TrayBend45Scaler.scale(
      baseline: baselineDoc,
      targetWidth: 200.0,
      targetHeight: 50.0,
    );
    expect(scaled200.parameters['width'], 200.0);
    final b1_200 = scaled200.bends.firstWhere((b) => b.id == 'B1');
    final b1Len200 = b1_200.p1.distanceTo(b1_200.p2);
    expect(b1Len200, closeTo(200.0, 1.0)); // B1 is invariant to width

    final b4_200 = scaled200.bends.firstWhere((b) => b.id == 'B4');
    final b4Len200 = b4_200.p1.distanceTo(b4_200.p2);
    expect(b4Len200, closeTo(75.3, 1.0)); // Wing grows with K_wing: 49.7 + 0.2557 * 100 = 75.3mm

    final fold200 = KinematicFoldEngine.foldDocument(scaled200, foldProgress: 1.0);
    expect(fold200.polygons.length, greaterThanOrEqualTo(9));
  });
}









