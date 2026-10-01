import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_bend_45_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_bend_90_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_equal_tee_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';

void main() {
  late DsfDocument unequalTeeDoc;
  late DsfDocument equalTeeDoc;
  late DsfDocument bend90Doc;
  late DsfDocument bend45Doc;
  late DsfDocument trunkingEqualTeeDoc;

  setUpAll(() {
    final utFile = File('assets/dsf_templates/tray_accessories/unequal_tee_100x50x100x50.dsf');
    unequalTeeDoc = DsfDocument.fromJson(jsonDecode(utFile.readAsStringSync()) as Map<String, dynamic>);

    final etFile = File('assets/dsf_templates/tray_accessories/equal_tee_100x50.dsf');
    equalTeeDoc = DsfDocument.fromJson(jsonDecode(etFile.readAsStringSync()) as Map<String, dynamic>);

    final b90File = File('assets/dsf_templates/tray_accessories/90_deg_bend_100x50.dsf');
    bend90Doc = DsfDocument.fromJson(jsonDecode(b90File.readAsStringSync()) as Map<String, dynamic>);

    final b45File = File('assets/dsf_templates/tray_accessories/45_deg_bend_100x50.dsf');
    bend45Doc = DsfDocument.fromJson(jsonDecode(b45File.readAsStringSync()) as Map<String, dynamic>);

    final trunkingFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
    trunkingEqualTeeDoc = DsfDocument.fromJson(jsonDecode(trunkingFile.readAsStringSync()) as Map<String, dynamic>);
  });

  group('Universal Coupler Flaps across All Cable Tray Accessories', () {
    test('TC-01: Universal Tray Accessory Identification', () {
      expect(CmsScalingController.isTrayAccessory(unequalTeeDoc), isTrue);
      expect(CmsScalingController.isTrayAccessory(equalTeeDoc), isTrue);
      expect(CmsScalingController.isTrayAccessory(bend90Doc), isTrue);
      expect(CmsScalingController.isTrayAccessory(bend45Doc), isTrue);

      expect(CmsScalingController.isTrayAccessory(trunkingEqualTeeDoc), isFalse);
    });

    test('TC-02: Equal Tee Coupler Flaps Synthesis, 3D Kinematics & Bend Angles', () {
      // 1. Without coupler flaps (baseline)
      final noFlaps = TrayEqualTeeScaler.scale(
        baseline: equalTeeDoc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        includeCouplerFlaps: false,
      );
      expect(noFlaps.faces.any((f) => f.id.startsWith('F_FLAP_')), isFalse);
      expect(noFlaps.bends.any((b) => b.id.startsWith('BF_')), isFalse);

      // 2. With coupler flaps enabled
      final withFlaps = TrayEqualTeeScaler.scale(
        baseline: equalTeeDoc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        includeCouplerFlaps: true,
        couplerFlapLength: 30.0,
      );

      final flapFaces = withFlaps.faces.where((f) => f.id.startsWith('F_FLAP_')).toList();
      expect(flapFaces.length, equals(6));
      expect(
        flapFaces.map((f) => f.id).toSet(),
        equals({'F_FLAP_1_P1', 'F_FLAP_1_P2', 'F_FLAP_3_P2', 'F_FLAP_3_P3', 'F_FLAP_6_P1', 'F_FLAP_6_P3'}),
      );

      final flapBends = withFlaps.bends.where((b) => b.id.startsWith('BF_')).toList();
      expect(flapBends.length, equals(6));
      expect(
        flapBends.map((b) => b.id).toSet(),
        equals({'BF_1_P1', 'BF_1_P2', 'BF_3_P2', 'BF_3_P3', 'BF_6_P1', 'BF_6_P3'}),
      );

      // Flap bend directions MUST be BendDirection.down to fold outward (parallel to tray run)
      for (final b in flapBends) {
        expect(b.direction, equals(BendDirection.down));
      }

      // Cheek flap angles are 45°
      final bf1P1 = flapBends.firstWhere((b) => b.id == 'BF_1_P1');
      final bf1P2 = flapBends.firstWhere((b) => b.id == 'BF_1_P2');
      expect(bf1P1.targetAngleDeg, closeTo(45.0, 0.1));
      expect(bf1P2.targetAngleDeg, closeTo(45.0, 0.1));

      // Back wall flap angles are 0° (coplanar extension)
      final bf6P1 = flapBends.firstWhere((b) => b.id == 'BF_6_P1');
      expect(bf6P1.targetAngleDeg, closeTo(0.0, 0.1));

      // 3. 3D Kinematics verification
      final fold3D = KinematicFoldEngine.foldDocument(withFlaps);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_1_P1'), isTrue);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_3_P2'), isTrue);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_3_P3'), isTrue);

      // Port 1 cheek flap (F_FLAP_1_P1) points outward along -X (normal in Y)
      final p1Flap = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P1');
      final n1 = (p1Flap.vertices[1] - p1Flap.vertices[0]).cross(p1Flap.vertices[2] - p1Flap.vertices[0]).normalized();
      expect(n1.x.abs(), closeTo(0.0, 0.05));
      expect(n1.y.abs(), closeTo(1.0, 0.05));

      // Port 2 flap (F_FLAP_3_P2) at branch (Top Port): runs along Y, normal in X
      final p2Flap = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P2');
      final n2 = (p2Flap.vertices[1] - p2Flap.vertices[0]).cross(p2Flap.vertices[2] - p2Flap.vertices[0]).normalized();
      expect(n2.x.abs(), closeTo(1.0, 0.05));
      expect(n2.y.abs(), closeTo(0.0, 0.05));

      // Port 3 flap (F_FLAP_3_P3) at Right Port: runs along X, normal in Y
      final p3Flap = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P3');
      final n3 = (p3Flap.vertices[1] - p3Flap.vertices[0]).cross(p3Flap.vertices[2] - p3Flap.vertices[0]).normalized();
      expect(n3.x.abs(), closeTo(0.0, 0.05));
      expect(n3.y.abs(), closeTo(1.0, 0.05));
    });

    test('TC-03: Tray 90° Flat Bend Coupler Flaps Synthesis & 3D Kinematics', () {
      // 1. Without coupler flaps
      final noFlaps = TrayBend90Scaler.scale(
        baseline: bend90Doc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        includeCouplerFlaps: false,
      );
      expect(noFlaps.faces.any((f) => f.id.startsWith('F_FLAP_')), isFalse);

      // 2. With coupler flaps enabled
      final withFlaps = TrayBend90Scaler.scale(
        baseline: bend90Doc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        includeCouplerFlaps: true,
        couplerFlapLength: 30.0,
      );

      final flapFaces = withFlaps.faces.where((f) => f.id.startsWith('F_FLAP_')).toList();
      expect(flapFaces.length, equals(4));
      expect(
        flapFaces.map((f) => f.id).toSet(),
        equals({'F_FLAP_THROAT_P1', 'F_FLAP_WING_P1', 'F_FLAP_THROAT_P2', 'F_FLAP_WING_P2'}),
      );

      final flapBends = withFlaps.bends.where((b) => b.id.startsWith('BF_')).toList();
      expect(flapBends.length, equals(4));
      for (final b in flapBends) {
        expect(b.direction, equals(BendDirection.down));
      }
      // Throat bends turn by 45° to match the connecting tray run
      expect(flapBends.firstWhere((b) => b.id == 'BF_THROAT_P1').targetAngleDeg, closeTo(45.0, 0.1));
      expect(flapBends.firstWhere((b) => b.id == 'BF_THROAT_P2').targetAngleDeg, closeTo(45.0, 0.1));
      // Wing walls are already parallel to connecting tray run, so wing flaps extend at 0°
      expect(flapBends.firstWhere((b) => b.id == 'BF_WING_P1').targetAngleDeg, closeTo(0.0, 0.1));
      expect(flapBends.firstWhere((b) => b.id == 'BF_WING_P2').targetAngleDeg, closeTo(0.0, 0.1));

      // 3. 3D Kinematics fold
      final fold3D = KinematicFoldEngine.foldDocument(withFlaps);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_THROAT_P1'), isTrue);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_WING_P1'), isTrue);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_THROAT_P2'), isTrue);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_WING_P2'), isTrue);

      // Both Port 1 flaps (throat and wing) must be mutually parallel with normal at 45°
      final pThroat1 = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_THROAT_P1');
      final nThroat1 = (pThroat1.vertices[1] - pThroat1.vertices[0]).cross(pThroat1.vertices[2] - pThroat1.vertices[0]).normalized();
      expect(nThroat1.x.abs(), closeTo(math.sqrt(2) / 2, 0.05));
      expect(nThroat1.y.abs(), closeTo(math.sqrt(2) / 2, 0.05));

      final pWing1 = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_WING_P1');
      final nWing1 = (pWing1.vertices[1] - pWing1.vertices[0]).cross(pWing1.vertices[2] - pWing1.vertices[0]).normalized();
      expect(nWing1.x.abs(), closeTo(math.sqrt(2) / 2, 0.05));
      expect(nWing1.y.abs(), closeTo(math.sqrt(2) / 2, 0.05));

      // Mutually parallel check: cross product of normals is 0
      final cross1 = nThroat1.cross(nWing1);
      expect(cross1.length, lessThan(0.05));
    });

    test('TC-04: Tray 45° Flat Bend Coupler Flaps Synthesis & 3D Kinematics', () {
      // 1. Without coupler flaps
      final noFlaps = TrayBend45Scaler.scale(
        baseline: bend45Doc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        includeCouplerFlaps: false,
      );
      expect(noFlaps.faces.any((f) => f.id.startsWith('F_FLAP_')), isFalse);

      // 2. With coupler flaps enabled
      final withFlaps = TrayBend45Scaler.scale(
        baseline: bend45Doc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        includeCouplerFlaps: true,
        couplerFlapLength: 30.0,
      );

      final flapFaces = withFlaps.faces.where((f) => f.id.startsWith('F_FLAP_')).toList();
      expect(flapFaces.length, equals(4));

      final flapBends = withFlaps.bends.where((b) => b.id.startsWith('BF_')).toList();
      expect(flapBends.length, equals(4));
      for (final b in flapBends) {
        expect(b.direction, equals(BendDirection.down));
      }
      // Throat bends turn by 22.5° for 45° bend
      expect(flapBends.firstWhere((b) => b.id == 'BF_THROAT_P1').targetAngleDeg, closeTo(22.5, 0.1));
      expect(flapBends.firstWhere((b) => b.id == 'BF_THROAT_P2').targetAngleDeg, closeTo(22.5, 0.1));
      // Wing walls are already parallel to connecting tray run
      expect(flapBends.firstWhere((b) => b.id == 'BF_WING_P1').targetAngleDeg, closeTo(0.0, 0.1));
      expect(flapBends.firstWhere((b) => b.id == 'BF_WING_P2').targetAngleDeg, closeTo(0.0, 0.1));

      // 3. 3D Kinematics fold
      final fold3D = KinematicFoldEngine.foldDocument(withFlaps);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_THROAT_P1'), isTrue);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_WING_P1'), isTrue);

      final pThroat1 = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_THROAT_P1');
      final nThroat1 = (pThroat1.vertices[1] - pThroat1.vertices[0]).cross(pThroat1.vertices[2] - pThroat1.vertices[0]).normalized();
      final pWing1 = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_WING_P1');
      final nWing1 = (pWing1.vertices[1] - pWing1.vertices[0]).cross(pWing1.vertices[2] - pWing1.vertices[0]).normalized();

      // Flaps are mutually parallel: cross product is 0
      final cross1 = nThroat1.cross(nWing1);
      expect(cross1.length, lessThan(0.05));
    });

    test('TC-05: CmsScalingController State & Parameter Integration for All Accessories', () {
      // Test with Tray Equal Tee
      const equalTeePorts = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 50.0),
      ];

      final ctrl = CmsScalingController(
        baselineDocument: equalTeeDoc,
        contract: CmsProductContract.equalTee,
        baselinePorts: equalTeePorts,
      );

      expect(ctrl.isCurrentTrayAccessory, isTrue);
      expect(ctrl.includeCouplerFlaps, isFalse);

      ctrl.setIncludeCouplerFlaps(true);
      expect(ctrl.includeCouplerFlaps, isTrue);

      final previewDoc = ctrl.previewDocument;
      expect(previewDoc.faces.any((f) => f.id.startsWith('F_FLAP_')), isTrue);

      // Test with Tray 90 Bend
      const bendPorts = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
      ];

      final ctrl90 = CmsScalingController(
        baselineDocument: bend90Doc,
        contract: CmsProductContract.bend90,
        baselinePorts: bendPorts,
      );
      expect(ctrl90.isCurrentTrayAccessory, isTrue);
      ctrl90.setIncludeCouplerFlaps(true);
      final preview90 = ctrl90.previewDocument;
      expect(preview90.faces.any((f) => f.id.startsWith('F_FLAP_')), isTrue);

      // Test with Trunking Equal Tee (should not be tray accessory)
      final ctrlTrunking = CmsScalingController(
        baselineDocument: trunkingEqualTeeDoc,
        contract: CmsProductContract.equalTee,
        baselinePorts: equalTeePorts,
      );
      expect(ctrlTrunking.isCurrentTrayAccessory, isFalse);
    });

    test('TC-06: Chamfered Flap Corners & Body Coupler Hole Visibility Suppression', () {
      // 1. Scaled bend with flaps
      final withFlaps = TrayBend90Scaler.scale(
        baseline: bend90Doc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        includeCouplerFlaps: true,
        couplerFlapLength: 30.0,
      );

      // Verify all flap faces have 6 vertices (with 2 chamfered end corners)
      final flapFaces = withFlaps.faces.where((f) => f.id.startsWith('F_FLAP_')).toList();
      expect(flapFaces.length, equals(4));
      for (final flap in flapFaces) {
        expect(flap.vertices.length, equals(6));
      }

      // Verify body coupler slots are marked invisible (not deleted)
      final flapPunches = withFlaps.punches.where((p) => p.id.startsWith('FLAP_SLOT_')).toList();
      final bodyCouplerPunches = withFlaps.punches.where((p) => p.role == CncPunchRole.coupler && !p.id.startsWith('FLAP_SLOT_')).toList();
      expect(flapPunches, isNotEmpty);
      expect(bodyCouplerPunches, isNotEmpty);
      for (final p in flapPunches) {
        expect(p.isVisible, isTrue);
      }
      for (final p in bodyCouplerPunches) {
        expect(p.isVisible, isFalse);
      }

      // 2. Scaled bend without flaps
      final noFlaps = TrayBend90Scaler.scale(
        baseline: bend90Doc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        includeCouplerFlaps: false,
      );

      final noFlapsBodyCouplers = noFlaps.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      expect(noFlapsBodyCouplers, isNotEmpty);
      for (final p in noFlapsBodyCouplers) {
        expect(p.isVisible, isTrue);
      }
    });
  });
}
