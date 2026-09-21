// =============================================================================
// outside_riser_scaling_test.dart
//
// Verification of 45° Outside Riser height & width scaling, preserving:
// 1. Parallel vertical bends B1 and B2 (100% stationary and parallel).
// 2. Fixed central floor web.
// 3. Exact 45° miter angles on cheek mouth edges and top chamfers.
// 4. Rigid coupler slots (setbacks, orientations, and dimensions preserved).
// 5. Folded 3D channel with physical openings.
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_dsf_importer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';

void main() {
  group('45° Outside Riser Height Scaling', () {
    late DsfDocument baselineDoc;

    setUp(() {
      final dxfFile = File('assets/dxf_templates/trunking_accessories/45_deg_outside_riser_100x100.dxf');
      expect(dxfFile.existsSync(), isTrue);

      var imported = DxfDsfImporter.importDxf(
        dxfFile.readAsStringSync(),
        productType: 'outside_riser',
        itemName: '45_deg_outside_riser_100x100',
      );

      final bends = [
        FoldBendLine(
          id: 'B1',
          p1: const CadPoint2D(106.0, 30.0),
          p2: const CadPoint2D(106.0, 93.65),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.bend,
        ),
        FoldBendLine(
          id: 'B2',
          p1: const CadPoint2D(203.0, 30.0),
          p2: const CadPoint2D(203.0, 93.65),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.bend,
        ),
        FoldBendLine(
          id: 'FL1',
          p1: const CadPoint2D(10.0, 30.0),
          p2: const CadPoint2D(10.0, 123.42),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.flange,
        ),
        FoldBendLine(
          id: 'FL2',
          p1: const CadPoint2D(299.0, 30.0),
          p2: const CadPoint2D(299.0, 123.40),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.flange,
        ),
      ];

      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: imported.outerContour,
        bends: bends,
      );

      baselineDoc = imported.copyWith(
        bends: decomp.connectedBends,
        faces: decomp.faces,
        baseFaceId: decomp.baseFaceId,
        parameters: {'width': 97.0, 'height': 100.0},
      );
    });

    test('1. Scales height from 100mm to 300mm with zero distortion on bends, floor, and miters', () {
      final contract = CmsProductContract.outsideRiser45;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 97.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 97.0, height: 100.0),
        ],
      );

      controller.selectParameter('height');
      controller.evaluateMorph(300.0);
      expect(controller.currentPreview, isNotNull);
      final scaledDoc = controller.currentPreview!.scaledDocument;

      // Verify B1 and B2 remain vertical and parallel at exactly X=106.0 and X=203.0
      final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
      expect(b1.p1.x, closeTo(106.0, 0.01), reason: 'B1 p1.x remains at 106.0');
      expect(b1.p2.x, closeTo(106.0, 0.01), reason: 'B1 p2.x remains at 106.0');
      expect(b1.p1.y, closeTo(30.0, 0.1), reason: 'B1 p1.y remains fixed');
      expect(b1.p2.y, closeTo(93.65, 0.1), reason: 'B1 p2.y remains fixed');

      expect(b2.p1.x, closeTo(203.0, 0.01), reason: 'B2 p1.x remains at 203.0');
      expect(b2.p2.x, closeTo(203.0, 0.01), reason: 'B2 p2.x remains at 203.0');
      expect(b2.p1.y, closeTo(30.0, 0.1), reason: 'B2 p1.y remains fixed');
      expect(b2.p2.y, closeTo(93.65, 0.1), reason: 'B2 p2.y remains fixed');

      // Verify outer flanges FL1 and FL2 moved outward by delta = 200mm
      final fl1 = scaledDoc.bends.firstWhere((b) => b.id == 'FL1');
      final fl2 = scaledDoc.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl1.p1.x, closeTo(-190.0, 0.1), reason: 'FL1 moved from 10 to -190');
      expect(fl1.p2.x, closeTo(-190.0, 0.1), reason: 'FL1 moved from 10 to -190');
      expect(fl2.p1.x, closeTo(499.0, 0.1), reason: 'FL2 moved from 299 to 499');
      expect(fl2.p2.x, closeTo(499.0, 0.1), reason: 'FL2 moved from 299 to 499');

      // Verify FL1 top shifted upward by delta * (sqrt(2) - 1.0)
      final expectedYStep = 200.0 * (math.sqrt(2) - 1.0);
      expect(fl1.p2.y, closeTo(123.42 + expectedYStep, 0.5));
      expect(fl2.p2.y, closeTo(123.40 + expectedYStep, 0.5));

      // Verify Port 2 45° mouth outer corners
      final leftMouthOuter = scaledDoc.outerContour.where((p) => p.x < 0.0 && p.y > 300.0).firstOrNull;
      expect(leftMouthOuter, isNotNull);
      final expectedOuterX = 62.22 - 200.0 / math.sqrt(2);
      final expectedOuterY = 179.99 + 200.0 / math.sqrt(2);
      expect(leftMouthOuter!.x, closeTo(expectedOuterX, 0.5));
      expect(leftMouthOuter.y, closeTo(expectedOuterY, 0.5));

      // Verify Coupler slots
      expect(scaledDoc.punches.length, equals(8));
      for (final p in scaledDoc.punches) {
        expect(p.widthMm, closeTo(8.0, 0.01), reason: '${p.id} width preserved');
        expect(p.lengthMm, closeTo(20.0, 0.01), reason: '${p.id} length preserved');
      }

      final s7 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_7');
      final s8 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_8');
      expect(s7.center.x, closeTo(-166.77, 0.5), reason: 'SLOT_7 shifted with FL1');
      expect(s8.center.x, closeTo(83.23, 0.5), reason: 'SLOT_8 remained fixed near B1');
      expect(s7.rotationDeg, closeTo(0.0, 0.1));
      expect(s8.rotationDeg, closeTo(0.0, 0.1));

      final s5 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_5');
      final s6 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_6');
      expect(s5.center.x, closeTo(475.77, 0.5), reason: 'SLOT_5 shifted with FL2');
      expect(s6.center.x, closeTo(225.77, 0.5), reason: 'SLOT_6 remained fixed near B2');
      expect(s5.rotationDeg, closeTo(0.0, 0.1));
      expect(s6.rotationDeg, closeTo(0.0, 0.1));

      final s1 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_1');
      final s2 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_2');
      expect(s1.center.x, closeTo(103.16, 0.5), reason: 'SLOT_1 remained fixed near throat');
      expect(s1.center.y, closeTo(123.35, 0.5));
      expect(s2.center.x, closeTo(67.76 - 200.0 / math.sqrt(2), 0.5));
      expect(s2.center.y, closeTo(158.65 + 200.0 / math.sqrt(2), 0.5));
      expect(s1.rotationDeg, closeTo(135.0, 0.1));
      expect(s2.rotationDeg, closeTo(135.0, 0.1));

      final s3 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_3');
      final s4 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_4');
      expect(s3.center.x, closeTo(205.84, 0.5), reason: 'SLOT_3 remained fixed near throat');
      expect(s3.center.y, closeTo(123.33, 0.5));
      expect(s4.center.x, closeTo(241.24 + 200.0 / math.sqrt(2), 0.5));
      expect(s4.center.y, closeTo(158.63 + 200.0 / math.sqrt(2), 0.5));
      expect(s3.rotationDeg, closeTo(45.0, 0.1));
      expect(s4.rotationDeg, closeTo(45.0, 0.1));
    });

    test('2. Folds in 3D and accurately measures 300mm opening heights on both ports', () {
      final contract = CmsProductContract.outsideRiser45;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 97.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 97.0, height: 100.0),
        ],
      );

      controller.selectParameter('height');
      controller.evaluateMorph(300.0);
      expect(controller.currentPreview, isNotNull);
      final scaledDoc = controller.currentPreview!.scaledDocument;

      final docWithParams = scaledDoc.copyWith(
        parameters: {'width': 97.0, 'height': 300.0},
      );

      final foldResult = KinematicFoldEngine.foldDocument(docWithParams, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: docWithParams,
        foldResult: foldResult,
      );
      expect(rawOpenings.length, equals(2));

      final measured = rawOpenings.map((raw) {
        return CmsOpeningPlaneAnalyzer.analyze(
          raw: raw,
          document: docWithParams,
          foldResult: foldResult,
        );
      }).toList();

      for (final op in measured) {
        expect(op.width, closeTo(97.0, 2.0), reason: 'Width preserved at 97mm');
        expect(op.height, closeTo(300.0, 15.0), reason: 'Height scales to ~300mm');
      }
    });

    test('3. Scales width from 97mm to 200mm symmetrically expanding floor web', () {
      final contract = CmsProductContract.outsideRiser45;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 97.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 97.0, height: 100.0),
        ],
      );

      controller.selectParameter('width');
      controller.evaluateMorph(200.0);
      expect(controller.currentPreview, isNotNull);
      final scaledDoc = controller.currentPreview!.scaledDocument;

      // Half delta is (200 - 97) / 2 = 103 / 2 = 51.5
      final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
      expect(b1.p1.x, closeTo(106.0 - 51.5, 0.5));
      expect(b2.p1.x, closeTo(203.0 + 51.5, 0.5));

      // Floor span is now 200mm
      expect(b2.p1.x - b1.p1.x, closeTo(200.0, 1.0));

      // 1. Throat notch vertices must translate rigidly with cheeks (NO lag or distortion)
      final pt2 = scaledDoc.outerContour[2];
      final pt3 = scaledDoc.outerContour[3];
      final pt4 = scaledDoc.outerContour[4];
      expect(pt2.x, closeTo(124.38 - 51.5, 0.5), reason: 'Left throat pt2 translates rigidly with left cheek');
      expect(pt3.x, closeTo(124.39 - 51.5, 0.5), reason: 'Left throat pt3 translates rigidly with left cheek');
      expect(pt4.x, closeTo(62.22 - 51.5, 0.5), reason: 'Left mouth tip pt4 translates rigidly with left cheek');

      final pt27 = scaledDoc.outerContour[27];
      final pt28 = scaledDoc.outerContour[28];
      final pt29 = scaledDoc.outerContour[29];
      expect(pt28.x, closeTo(184.61 + 51.5, 0.5), reason: 'Right throat pt28 translates rigidly with right cheek');
      expect(pt29.x, closeTo(184.62 + 51.5, 0.5), reason: 'Right throat pt29 translates rigidly with right cheek');
      expect(pt27.x, closeTo(246.78 + 51.5, 0.5), reason: 'Right mouth tip pt27 translates rigidly with right cheek');

      // 2. Exact 45° miter angle preserved on both mouth edges (slope = 1.0)
      final leftMouthSlope = ((pt4.y - pt3.y) / (pt4.x - pt3.x)).abs();
      expect(leftMouthSlope, closeTo(1.0, 0.05), reason: 'Left mouth edge maintains exact 45° slope');

      final rightMouthSlope = ((pt28.y - pt27.y) / (pt28.x - pt27.x)).abs();
      expect(rightMouthSlope, closeTo(1.0, 0.05), reason: 'Right mouth edge maintains exact 45° slope');

      // 3. Coupler slots translate rigidly with zero distortion
      for (final p in scaledDoc.punches) {
        expect(p.widthMm, closeTo(8.0, 0.01));
        expect(p.lengthMm, closeTo(20.0, 0.01));
      }
      final s1 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_1');
      final s3 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_3');
      expect(s1.center.x, closeTo(103.16 - 51.5, 0.5), reason: 'SLOT_1 translates rigidly with left cheek');
      expect(s3.center.x, closeTo(205.84 + 51.5, 0.5), reason: 'SLOT_3 translates rigidly with right cheek');

      // 4. Fold 3D mesh and verify channel opening width is 200mm
      final foldResult = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: scaledDoc,
        foldResult: foldResult,
      );
      expect(rawOpenings.length, equals(2));
      final measured = rawOpenings.map((raw) {
        return CmsOpeningPlaneAnalyzer.analyze(
          raw: raw,
          document: scaledDoc,
          foldResult: foldResult,
        );
      }).toList();
      for (final op in measured) {
        expect(op.width, closeTo(200.0, 3.0), reason: 'Port width expands to 200mm');
      }

      // 5. Test Width 300mm (+203mm delta) — SS3 verification
      controller.evaluateMorph(300.0);
      final doc300 = controller.currentPreview!.scaledDocument;
      final halfDelta300 = 203.0 / 2.0; // 101.5mm
      final pt3_300 = doc300.outerContour[3];
      final pt4_300 = doc300.outerContour[4];
      final pt28_300 = doc300.outerContour[28];
      expect(pt3_300.x, closeTo(124.39 - halfDelta300, 0.5));
      expect(pt4_300.x, closeTo(62.22 - halfDelta300, 0.5));
      expect(pt28_300.x, closeTo(184.61 + halfDelta300, 0.5));

      final slope300 = ((pt4_300.y - pt3_300.y) / (pt4_300.x - pt3_300.x)).abs();
      expect(slope300, closeTo(1.0, 0.05), reason: 'Width 300mm maintains exact 45° slope without skewing');
    });

    test('4. Scales height down from 100mm to 60mm (-40mm delta) with proper inward cheek translation', () {
      final contract = CmsProductContract.outsideRiser45;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 97.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 97.0, height: 100.0),
        ],
      );

      controller.selectParameter('height');
      controller.evaluateMorph(60.0); // delta = -40.0
      expect(controller.currentPreview, isNotNull);
      final scaledDoc = controller.currentPreview!.scaledDocument;

      // B1 and B2 remain stationary
      final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
      expect(b1.p1.x, closeTo(106.0, 0.01));
      expect(b2.p1.x, closeTo(203.0, 0.01));

      // FL1 moves inward to 10 - (-40) = 50.0
      final fl1 = scaledDoc.bends.firstWhere((b) => b.id == 'FL1');
      final fl2 = scaledDoc.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl1.p1.x, closeTo(50.0, 0.1));
      expect(fl2.p1.x, closeTo(259.0, 0.1));
    });
  });
}
