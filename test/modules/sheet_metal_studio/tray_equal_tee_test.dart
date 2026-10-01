import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_equal_tee_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';

void main() {
  late DsfDocument baselineDoc;
  late DsfDocument trunkingDoc;

  setUp(() {
    final trayFile = File('assets/dsf_templates/tray_accessories/equal_tee_100x50.dsf');
    baselineDoc = DsfDocument.fromJson(jsonDecode(trayFile.readAsStringSync()) as Map<String, dynamic>);

    final trunkingFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
    trunkingDoc = DsfDocument.fromJson(jsonDecode(trunkingFile.readAsStringSync()) as Map<String, dynamic>);
  });

  group('Cable Tray Equal Tee - Dedicated Parametric Engine', () {
    test('TC-01: Template Classification & Baseline Geometry', () {
      expect(TrayEqualTeeScaler.isTrayEqualTee(baselineDoc), isTrue);
      expect(TrayEqualTeeScaler.isTrayEqualTee(trunkingDoc), isFalse);

      final fold = KinematicFoldEngine.foldDocument(baselineDoc, foldProgress: 1.0);
      final openings = Cms3DOpeningDetector.detectOpenings(document: baselineDoc, foldResult: fold);

      expect(openings.length, equals(3));

      // Opening 1: Left Port
      final leftPort = openings.firstWhere((o) => o.outwardNormal.x < -0.9);
      expect(leftPort.outwardNormal.x, closeTo(-1.0, 1e-4));
      expect(leftPort.outwardNormal.y.abs(), lessThan(1e-4));
      expect(leftPort.outwardNormal.z.abs(), lessThan(1e-4));

      // Opening 2: Top Port
      final topPort = openings.firstWhere((o) => o.outwardNormal.y < -0.9);
      expect(topPort.outwardNormal.y, closeTo(-1.0, 1e-4));
      expect(topPort.outwardNormal.x.abs(), lessThan(1e-4));
      expect(topPort.outwardNormal.z.abs(), lessThan(1e-4));

      // Opening 3: Right Port
      final rightPort = openings.firstWhere((o) => o.outwardNormal.x > 0.9);
      expect(rightPort.outwardNormal.x, closeTo(1.0, 1e-4));
      expect(rightPort.outwardNormal.y.abs(), lessThan(1e-4));
      expect(rightPort.outwardNormal.z.abs(), lessThan(1e-4));

      // Check baseline punch count
      expect(baselineDoc.punches.length, equals(24));
    });

    test('TC-02: Height Scaling Structure Invariance & 95mm Coupler Rule', () {
      // Scale to H=75mm (H < 95mm)
      final scaled75 = TrayEqualTeeScaler.scale(
        baseline: baselineDoc,
        targetWidth: 100.0,
        targetHeight: 75.0,
      );

      // Floor web and B1, B2, B3 must be 100% stationary
      final b1Base = baselineDoc.bends.firstWhere((b) => b.id == 'B1');
      final b1Scaled75 = scaled75.bends.firstWhere((b) => b.id == 'B1');
      expect(b1Scaled75.p1.x, closeTo(b1Base.p1.x, 1e-4));
      expect(b1Scaled75.p1.y, closeTo(b1Base.p1.y, 1e-4));
      expect(b1Scaled75.p2.x, closeTo(b1Base.p2.x, 1e-4));
      expect(b1Scaled75.p2.y, closeTo(b1Base.p2.y, 1e-4));

      final b3Base = baselineDoc.bends.firstWhere((b) => b.id == 'B3');
      final b3Scaled75 = scaled75.bends.firstWhere((b) => b.id == 'B3');
      expect(b3Scaled75.p1.y, closeTo(b3Base.p1.y, 1e-4));
      expect(b3Scaled75.p2.y, closeTo(b3Base.p2.y, 1e-4));
      // B3 must remain strictly horizontal (0.0 tilt)
      expect((b3Scaled75.p2.y - b3Scaled75.p1.y).abs(), lessThan(1e-4));

      // Flange FL3 expands down by deltaH = 25mm
      final fl3Base = baselineDoc.bends.firstWhere((b) => b.id == 'FL3');
      final fl3Scaled75 = scaled75.bends.firstWhere((b) => b.id == 'FL3');
      expect(fl3Scaled75.p1.y - fl3Base.p1.y, closeTo(25.0, 1e-4));
      expect(fl3Scaled75.p2.y - fl3Base.p2.y, closeTo(25.0, 1e-4));

      // Coupler punch rule for H=75 (<95mm): 1 slot centered on height
      final leftWallPunches75 = scaled75.punches.where((p) => p.role == CncPunchRole.coupler && p.rotationDeg == 45.0).toList();
      expect(leftWallPunches75.length, equals(4)); // 1 row of 4 slots

      final botWallPunches75 = scaled75.punches.where((p) => p.role == CncPunchRole.coupler && p.rotationDeg == 0.0).toList();
      expect(botWallPunches75.length, equals(4)); // 1 row of 4 slots (2 per corner)
      // Check centered on height: b3Y + H/2 = 278.97 + 37.5 = 316.47
      for (final p in botWallPunches75) {
        expect(p.center.y, closeTo(b3Scaled75.p1.y + 37.5, 1e-3));
      }

      // Scale to H=100mm (H >= 95mm)
      final scaled100 = TrayEqualTeeScaler.scale(
        baseline: baselineDoc,
        targetWidth: 100.0,
        targetHeight: 100.0,
      );

      final leftWallPunches100 = scaled100.punches.where((p) => p.role == CncPunchRole.coupler && p.rotationDeg == 45.0).toList();
      expect(leftWallPunches100.length, equals(8)); // 2 rows of 4 slots

      final botWallPunches100 = scaled100.punches.where((p) => p.role == CncPunchRole.coupler && p.rotationDeg == 0.0).toList();
      expect(botWallPunches100.length, equals(8)); // 2 rows of 4 slots = 8 slots
      // 50mm vertical pitch centered at H/2 = 50.0: rows at 25.0 and 75.0
      final b3_100 = scaled100.bends.firstWhere((b) => b.id == 'B3');
      final yValues = botWallPunches100.map((p) => p.center.y).toSet().toList()..sort();
      expect(yValues.length, equals(2));
      expect(yValues[0], closeTo(b3_100.p1.y + 25.0, 1e-3));
      expect(yValues[1], closeTo(b3_100.p1.y + 75.0, 1e-3));
      expect(yValues[1] - yValues[0], closeTo(50.0, 1e-3));
    });

    test('TC-03: Equal Width Scaling Across All 3 Ports', () {
      final scaled150 = TrayEqualTeeScaler.scale(
        baseline: baselineDoc,
        targetWidth: 150.0,
        targetHeight: 50.0,
      );

      // Top mouth:
      final fold150 = KinematicFoldEngine.foldDocument(scaled150, foldProgress: 1.0);
      final openings150 = Cms3DOpeningDetector.detectOpenings(document: scaled150, foldResult: fold150);
      expect(openings150.length, equals(3));

      final topPort = openings150.firstWhere((o) => o.outwardNormal.y < -0.9);
      final leftPort = openings150.firstWhere((o) => o.outwardNormal.x < -0.9);
      final rightPort = openings150.firstWhere((o) => o.outwardNormal.x > 0.9);

      // Verify all 3 flat opening edges scaled equally by deltaW = 50mm
      final topMouthFlatLen = topPort.flatFloorEdgeP1.distanceTo(topPort.flatFloorEdgeP2);
      expect(topMouthFlatLen, closeTo(150.0, 1e-3));

      final leftMouthFlatLen = leftPort.flatFloorEdgeP1.distanceTo(leftPort.flatFloorEdgeP2);
      expect(leftMouthFlatLen - (baselineDoc.faces.firstWhere((f) => f.id == 'F_6').vertices[0].y - baselineDoc.faces.firstWhere((f) => f.id == 'F_6').vertices[1].y), closeTo(50.0, 1e-3));

      final rightMouthFlatLen = rightPort.flatFloorEdgeP1.distanceTo(rightPort.flatFloorEdgeP2);
      expect(rightMouthFlatLen - (baselineDoc.faces.firstWhere((f) => f.id == 'F_6').vertices[5].y - baselineDoc.faces.firstWhere((f) => f.id == 'F_6').vertices[4].y), closeTo(50.0, 1e-3));

      // B3 length expands from 385.74mm by 50mm to 435.74mm
      final b3 = scaled150.bends.firstWhere((b) => b.id == 'B3');
      expect(b3.p2.x - b3.p1.x, closeTo(385.744690 + 50.0, 1e-3));
    });

    test('TC-04: CmsScalingController Integration & Preview Verification', () {
      const baselinePorts = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 50.0),
      ];

      final controller = CmsScalingController(
        baselineDocument: baselineDoc,
        contract: CmsProductContract.equalTee,
        baselinePorts: baselinePorts,
      );

      // Verify parameter initialization
      expect(controller.model.parameters.containsKey('width'), isTrue);
      expect(controller.model.parameters.containsKey('height'), isTrue);
      expect(controller.model.parameters.containsKey('radius'), isTrue);

      // Change height to 75mm
      controller.selectParameter('height');
      controller.evaluateMorph(75.0);
      expect(controller.currentPreview, isNotNull);
      expect(controller.currentPreview!.isValid, isTrue);

      final previewDoc75 = controller.previewDocument;
      final b375 = previewDoc75.bends.firstWhere((b) => b.id == 'B3');
      expect((b375.p2.y - b375.p1.y).abs(), lessThan(1e-4), reason: 'B3 must not tilt under height scaling');

      // Change height to 100mm
      controller.evaluateMorph(100.0);
      final previewDoc100 = controller.previewDocument;
      final b3100 = previewDoc100.bends.firstWhere((b) => b.id == 'B3');
      expect((b3100.p2.y - b3100.p1.y).abs(), lessThan(1e-4), reason: 'B3 must remain horizontal');

      // Coupler holes on previewDoc100 must be organized in 2 rows
      final couplers100 = previewDoc100.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      expect(couplers100.length, equals(24)); // 8 left 45 + 8 right 45 + 8 bottom

      // Change width to 150mm
      controller.selectParameter('width');
      controller.evaluateMorph(150.0);
      final previewDocW150 = controller.previewDocument;
      final b3W150 = previewDocW150.bends.firstWhere((b) => b.id == 'B3');
      expect(b3W150.p2.x - b3W150.p1.x, closeTo(385.744690 + 50.0, 1e-3));
    });
  });
}
