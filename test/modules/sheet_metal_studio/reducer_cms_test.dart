import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'dart:math' as math;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DsfDocument baselineDoc;

  setUpAll(() {
    final file = File('assets/dsf_templates/trunking_accessories/reducer_100x100x50x50.dsf');
    expect(file.existsSync(), isTrue, reason: 'Reducer template file must exist');
    final jsonStr = file.readAsStringSync();
    baselineDoc = DsfDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    baselineDoc = baselineDoc.copyWith(parameters: {
      'port1_width': 100.0,
      'port1_height': 100.0,
      'port2_width': 50.0,
      'port2_height': 50.0,
      'width': 100.0,
      'height': 100.0,
    });
  });

  group('Reducer Dedicated Scaling, Ports & Cover Verification', () {
    test('1. Baseline Reducer port discovery: borders pass through coupler hole centers', () {
      final foldResult = KinematicFoldEngine.foldDocument(baselineDoc, foldProgress: 1.0);
      expect(foldResult.punchCenters3D.isNotEmpty, isTrue);

      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: baselineDoc, foldResult: foldResult);
      expect(rawOpenings.length, equals(2), reason: 'Reducer has 2 ports (Port 1 large, Port 2 small)');

      final analyzedPorts = rawOpenings.map((raw) => CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: baselineDoc, foldResult: foldResult)).toList();
      expect(analyzedPorts.length, equals(2));

      // Verify port border passes through punch centers in 3D
      final port1 = analyzedPorts.firstWhere((p) => p.normal.y < 0);
      final port2 = analyzedPorts.firstWhere((p) => p.normal.y > 0);

      expect(port1.width, closeTo(100.5, 1.0), reason: 'Port 1 width passes directly through coupler hole centers');
      expect(port1.height, closeTo(100.0, 3.0));

      expect(port2.width, closeTo(48.1, 2.5), reason: 'Port 2 width passes directly through coupler hole centers');
      expect(port2.height, closeTo(50.0, 2.0));
    });

    test('2. Independent Port 1 & Port 2 Width & Height scaling with 95mm rule', () {
      final controller = CmsScalingController(
        contract: CmsProductContract.straightReducer,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 50.0, height: 50.0),
        ],
      );

      // Scale Port 1 to 150x120 (>=95mm => 2 slots), Port 2 to 70x60 (<95mm => 1 slot)
      controller.selectParameter('port1_width');
      controller.evaluateMorph(150.0);
      controller.selectParameter('port1_height');
      controller.evaluateMorph(120.0);
      controller.selectParameter('port2_width');
      controller.evaluateMorph(70.0);
      controller.selectParameter('port2_height');
      controller.evaluateMorph(60.0);

      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;
      expect(scaled.outerContour.isNotEmpty, isTrue);

      // Verify Coupler punches count and placement:
      // Port 1 (dH1 >= 95): 2 ears * 2 slots = 4 slots (SLOT_5, SLOT_6 on left; SLOT_2, SLOT_3 on right)
      // Port 2 (dH2 < 95): 2 ears * 1 slot = 2 slots (SLOT_4 on left; SLOT_1 on right)
      // Total slots = 6
      final slots = scaled.punches.where((p) => p.isSlot).toList();
      expect(slots.length, equals(6));

      final slot5 = slots.firstWhere((p) => p.id == 'SLOT_5');
      final slot6 = slots.firstWhere((p) => p.id == 'SLOT_6');
      final slot2 = slots.firstWhere((p) => p.id == 'SLOT_2');
      final slot3 = slots.firstWhere((p) => p.id == 'SLOT_3');
      final slot4 = slots.firstWhere((p) => p.id == 'SLOT_4');
      final slot1 = slots.firstWhere((p) => p.id == 'SLOT_1');

      // Slot pitch on Port 1 should be exactly 50mm
      expect(slot5.center.distanceTo(slot6.center), closeTo(50.0, 0.1));
      expect(slot2.center.distanceTo(slot3.center), closeTo(50.0, 0.1));

      // Slot 4 and Slot 1 should be present as single centered slots
      expect(slot4.center.x, isNotNull);
      expect(slot1.center.x, isNotNull);
      expect(slots.any((p) => p.id == 'SLOT_4_B'), isFalse);
      expect(slots.any((p) => p.id == 'SLOT_1_B'), isFalse);
    });

    test('3. Scaling Port 2 height to >= 95mm generates 2 coupler slots at 50mm pitch', () {
      final controller = CmsScalingController(
        contract: CmsProductContract.straightReducer,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 50.0, height: 50.0),
        ],
      );

      // Scale Port 2 height to 100mm
      controller.selectParameter('port2_height');
      controller.evaluateMorph(100.0);

      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;
      final slots = scaled.punches.where((p) => p.isSlot).toList();
      // Both Port 1 and Port 2 are >= 95mm => 4 + 4 = 8 slots
      expect(slots.length, equals(8));

      final slot4 = slots.firstWhere((p) => p.id == 'SLOT_4');
      final slot4B = slots.firstWhere((p) => p.id == 'SLOT_4_B');
      expect(slot4.center.distanceTo(slot4B.center), closeTo(50.0, 0.1));
    });

    test('4. Scaling Port 1 height to < 95mm reduces Port 1 coupler slots to 1 centered', () {
      final controller = CmsScalingController(
        contract: CmsProductContract.straightReducer,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 50.0, height: 50.0),
        ],
      );

      // Scale Port 1 height to 60mm
      controller.selectParameter('port1_height');
      controller.evaluateMorph(60.0);

      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;

      final slots = scaled.punches.where((p) => p.isSlot).toList();
      // Both Port 1 (60mm) and Port 2 (50mm) are < 95mm => 2 + 2 = 4 slots
      expect(slots.length, equals(4));

      expect(slots.any((p) => p.id == 'SLOT_6'), isFalse);
      expect(slots.any((p) => p.id == 'SLOT_3'), isFalse);
      expect(slots.any((p) => p.id == 'SLOT_4_B'), isFalse);
      expect(slots.any((p) => p.id == 'SLOT_1_B'), isFalse);
    });

    test('5. Reducer Cover Generation: trapezoidal top with 2 side flanges, hypotenuse length, and 3D slope matching body top', () {
      final coverData = TrunkingCoverGenerator.generateCover(baselineDoc);

      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;
      expect(coverDoc.bends.length, equals(2), reason: 'Reducer cover has 2 side drop flanges (open at both ports)');

      for (final b in coverDoc.bends) {
        expect(b.targetAngleDeg.abs(), closeTo(90.0, 1.0));
      }

      // Check central mounting hole punch
      final mountHoles = coverDoc.punches.where((p) => p.id == 'COVER_MOUNT_HOLE').toList();
      expect(mountHoles.length, equals(1));
      expect(mountHoles.first.diameterMm, closeTo(6.0, 0.1));

      // Side flanges depth should be default flange depth
      final sideFlangeFaces = coverDoc.faces.where((f) => f.role == FaceRole.returnFlange || f.id.startsWith('COVER_FLANGE')).toList();
      expect(sideFlangeFaces.length, equals(2));

      // Reducer metadata: hypotenuse length L_slanted = sqrt(150^2 + 50^2) ~ 158.11mm
      expect(coverData.properties['isReducerCover'], isTrue);
      expect(coverData.properties['slantedLength'], closeTo(158.11, 0.5));
      expect(coverData.properties['slopeAngleRad'], closeTo(0.32175, 0.01));
      expect(coverData.properties['port1Height'], equals(100.0));
      expect(coverData.properties['port2Height'], equals(50.0));

      // 3D Viewport verification via SheetMetalStudioViewModel:
      final vm = SheetMetalStudioViewModel(initialDocument: baselineDoc);
      vm.createCoverForCurrentFitting();
      expect(vm.hasCover, isTrue);

      final coverMesh = vm.coverMesh;
      expect(coverMesh, isNotNull);

      // Find cover top plate polygon
      final topPoly = coverMesh!.polygons.firstWhere((p) => p.faceId.contains('COVER_MAIN_FACE'));

      // Verify surface normal has positive Y and positive Z, matching the slope angle alpha = 18.43°
      expect(topPoly.normal.y, closeTo(math.sin(0.32175), 0.02));
      expect(topPoly.normal.z, closeTo(math.cos(0.32175), 0.02));
      expect(topPoly.normal.x.abs(), lessThan(0.01));

      // Verify vertices in 3D:
      // At Port 1 (Y ~ 26.62mm), Z must be at Port 1 height 100mm + defaultCoverClearanceZ (5mm) = 105.0mm
      const clrZ = TrunkingCoverGenerator.defaultCoverClearanceZ;
      final p1Verts = topPoly.vertices.where((v) => (v.y - 26.62).abs() < 2.0).toList();
      expect(p1Verts.isNotEmpty, isTrue);
      for (final v in p1Verts) {
        expect(v.z, closeTo(100.0 + clrZ, 0.5), reason: 'Cover at Port 1 must be at H1 (100mm) + clearance');
      }

      // At Port 2 (Y ~ 176.62mm), Z must be at Port 2 height 50mm + defaultCoverClearanceZ (5mm) = 55.0mm
      final p2Verts = topPoly.vertices.where((v) => (v.y - 176.62).abs() < 2.0).toList();
      expect(p2Verts.isNotEmpty, isTrue);
      for (final v in p2Verts) {
        expect(v.z, closeTo(50.0 + clrZ, 0.5), reason: 'Cover at Port 2 must be at H2 (50mm) + clearance');
      }

      // Dynamic CMS scaling verification: scale Port 1 to 155mm, Port 2 to 95mm
      vm.startTeachScaling();
      vm.scalingController!.selectParameter('port1_height');
      vm.scalingController!.evaluateMorph(155.0);
      vm.scalingController!.selectParameter('port2_height');
      vm.scalingController!.evaluateMorph(95.0);

      final scaledCoverMesh = vm.coverMesh;
      expect(scaledCoverMesh, isNotNull);
      final scaledTopPoly = scaledCoverMesh!.polygons.firstWhere((p) => p.faceId.contains('COVER_MAIN_FACE'));

      final scaledP1Verts = scaledTopPoly.vertices.where((v) => (v.y - 26.62).abs() < 2.0).toList();
      expect(scaledP1Verts.isNotEmpty, isTrue);
      for (final v in scaledP1Verts) {
        expect(v.z, closeTo(155.0 + clrZ, 0.5), reason: 'Cover at Port 1 must follow scaled H1 (155mm)');
      }

      final scaledP2Verts = scaledTopPoly.vertices.where((v) => (v.y - 176.62).abs() < 2.0).toList();
      expect(scaledP2Verts.isNotEmpty, isTrue);
      for (final v in scaledP2Verts) {
        expect(v.z, closeTo(95.0 + clrZ, 0.5), reason: 'Cover at Port 2 must follow scaled H2 (95mm)');
      }
    });

    test('6. Width scaling preserves strictly vertical, parallel coupler flaps in 3D without angular tilting', () {
      final controller = CmsScalingController(
        contract: CmsProductContract.straightReducer,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 50.0, height: 50.0),
        ],
      );

      // Scale Port 1 width to 225.0 mm (Scenario SS2 from user bug report)
      controller.selectParameter('port1_width');
      controller.evaluateMorph(225.0);

      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;
      final foldResult = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);

      // Verify all 4 coupler flaps (F_0, F_4 at Port 1; F_2, F_6 at Port 2)
      for (final poly in foldResult.polygons) {
        if (poly.faceId == 'F_4' || poly.faceId == 'F_0' || poly.faceId == 'F_6' || poly.faceId == 'F_2') {
          // Normal Z must be virtually zero: strictly vertical flap in 3D
          expect(poly.normal.z.abs(), lessThan(0.015),
              reason: '${poly.faceId} normal Z must be near 0 (no out-of-plane tilt), got ${poly.normal.z}');
          // Normal Y must be virtually zero: flap strictly parallel to duct run Y-axis
          expect(poly.normal.y.abs(), lessThan(0.015),
              reason: '${poly.faceId} normal Y must be near 0 (parallel to Y axis), got ${poly.normal.y}');
          // Normal X must be near 1.0 or -1.0
          expect(poly.normal.x.abs(), closeTo(1.0, 0.02));
        }
      }
    });

    test('7. Height scaling preserves flat horizontal flap edges, orthogonal cheek notches, and vertical hole alignment in 3D', () {
      final controller = CmsScalingController(
        contract: CmsProductContract.straightReducer,
        baselineDocument: baselineDoc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 50.0, height: 50.0),
        ],
      );

      // Scale Port 1 height to 155.0 mm (Scenario SS3) and Port 2 height to 95.0 mm (Scenario SS4)
      controller.selectParameter('port1_height');
      controller.evaluateMorph(155.0);
      controller.selectParameter('port2_height');
      controller.evaluateMorph(95.0);

      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;
      final foldResult = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);

      for (final poly in foldResult.polygons) {
        if (poly.faceId == 'F_4' || poly.faceId == 'F_0') {
          // Port 1 flaps (height 155mm -> cheek height 151mm)
          expect(poly.normal.z.abs(), lessThan(0.015));
          expect(poly.normal.y.abs(), lessThan(0.015));
          final zs = poly.vertices.map((v) => v.z).toList();
          final minZ = zs.reduce((a, b) => a < b ? a : b);
          final maxZ = zs.reduce((a, b) => a > b ? a : b);
          expect(minZ, closeTo(1.5, 0.5));
          expect(maxZ, closeTo(151.0 + 1.5, 0.5));
        } else if (poly.faceId == 'F_6' || poly.faceId == 'F_2') {
          // Port 2 flaps (height 95mm -> cheek height 91mm)
          expect(poly.normal.z.abs(), lessThan(0.015));
          expect(poly.normal.y.abs(), lessThan(0.015));
          final zs = poly.vertices.map((v) => v.z).toList();
          final minZ = zs.reduce((a, b) => a < b ? a : b);
          final maxZ = zs.reduce((a, b) => a > b ? a : b);
          expect(minZ, closeTo(1.5, 0.5));
          expect(maxZ, closeTo(91.0 + 1.5, 0.5));
        }
      }
    });
  });
}

