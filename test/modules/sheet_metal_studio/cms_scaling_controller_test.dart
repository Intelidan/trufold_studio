import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_scaling_model.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_coupler_classifier.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_dimension.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';

void main() {
  group('CmsScalingController (Canonical Geometry Rule)', () {
    late DsfDocument baselineDoc;
    late List<CmsPhysicalPort> baselinePorts;

    setUp(() {
      final dsfFile = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final json = jsonDecode(dsfFile.readAsStringSync()) as Map<String, dynamic>;
      baselineDoc = DsfDocument.fromJson(json);

      baselinePorts = const [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 98.0, height: 100.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 98.0, height: 100.0),
      ];
    });

    test('Initializes scaling model with dynamic rigid groups and untaught parameters', () {
      final controller = CmsScalingController(
        baselineDocument: baselineDoc,
        contract: CmsProductContract.bend45,
        baselinePorts: baselinePorts,
      );

      expect(controller.model.parameters.containsKey('width'), isTrue);
      expect(controller.model.parameters.containsKey('height'), isTrue);
      expect(controller.model.parameters['width']!.teachingState, CmsParameterTeachingState.untaught);

      // Verify dynamic feature group naming (never hardcoded!)
      expect(controller.model.rigidFeatureGroups, isNotEmpty);
      expect(controller.model.rigidFeatureGroups.first.name, contains('Coupler Slots'));
      expect(controller.model.rigidFeatureGroups.first.punchIds.length, baselineDoc.punches.where((p) => p.isSlot).length);
    });

    test('Evaluating morph strictly modifies canonical 2D sheet and regenerates 3D', () {
      final controller = CmsScalingController(
        baselineDocument: baselineDoc,
        contract: CmsProductContract.bend45,
        baselinePorts: baselinePorts,
      );

      final baselineContourWidth = baselineDoc.blankWidthMm;

      // Evaluate morph to 150mm (+50mm delta)
      controller.evaluateMorph(150.0);

      expect(controller.currentPreview, isNotNull);
      final preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);

      // Canonical 2D sheet geometry must have expanded
      expect(preview.scaledDocument.blankWidthMm, greaterThan(baselineContourWidth));

      // 3D mesh must be folded from that exact 2D state
      expect(preview.foldedMesh.polygons, isNotEmpty);

      // Coupler slot punches must preserve their exact width and length
      for (int i = 0; i < baselineDoc.punches.length; i++) {
        final origPunch = baselineDoc.punches[i];
        final scaledPunch = preview.scaledDocument.punches[i];
        expect(scaledPunch.widthMm, equals(origPunch.widthMm));
        expect(scaledPunch.lengthMm, equals(origPunch.lengthMm));
      }

      // Derived 3D ports must be present
      expect(preview.derivedPorts, isNotEmpty);
    });

    test('Accepting scaling model marks parameter as learned and persists into DSF metadata', () {
      final controller = CmsScalingController(
        baselineDocument: baselineDoc,
        contract: CmsProductContract.bend45,
        baselinePorts: baselinePorts,
      );

      controller.selectParameter('width');
      controller.evaluateMorph(150.0);

      final committedDoc = controller.acceptScalingModel();
      expect(controller.model.parameters['width']!.isLearned, isTrue);

      // Verify persistence in DSF metadata
      final meta = committedDoc.metadata['cmsTemplate'] as Map<String, dynamic>?;
      expect(meta, isNotNull);
      final scalingModelJson = meta!['scalingModel'] as Map<String, dynamic>?;
      expect(scalingModelJson, isNotNull);
      expect(scalingModelJson!['parameters']['width']['teachingState'], 'learned');

      // Verify derived scaled ports are persisted into DSF metadata
      final portsJson = meta['ports'] as List?;
      expect(portsJson, isNotNull);
      expect(portsJson!.length, equals(baselinePorts.length));
      final scaledPort1 = portsJson.first as Map<String, dynamic>;
      expect(scaledPort1['width'], greaterThan(140.0));
    });

    test('Round-trip save and reopen DSF preserves scaled port dimensions in SheetMetalStudioViewModel', () {
      final vm = SheetMetalStudioViewModel(initialDocument: baselineDoc);
      vm.startCleanCmsDiscovery(contract: CmsProductContract.bend45);
      vm.finalizeCmsTemplate(openInspector: false);

      // Start Teach Scaling and evaluate morph to 150mm
      vm.startTeachScaling();
      expect(vm.isTeachScalingActive, isTrue);
      vm.scalingController!.selectParameter('width');
      vm.scalingController!.evaluateMorph(150.0);

      // Accept scaling
      vm.acceptTeachScaling();
      expect(vm.isTeachScalingActive, isFalse);
      expect(vm.verifiedCmsPorts.first.width, greaterThan(140.0));

      // Simulate Save
      final savedDoc = vm.prepareDocumentForSave();
      final jsonString = jsonEncode(savedDoc.toJson());

      // Simulate Reopen
      final reopenedDoc = DsfDocument.parseJsonString(jsonString);
      final reopenedVm = SheetMetalStudioViewModel(initialDocument: reopenedDoc);

      expect(reopenedVm.verifiedCmsPorts, isNotEmpty);
      expect(reopenedVm.activeCmsPorts, isNotEmpty);
      expect(reopenedVm.activeCmsPorts.first.width, greaterThan(140.0));
      expect(reopenedVm.activeCmsPorts.last.width, greaterThan(140.0));
      expect(reopenedVm.activeCmsPorts.first.derivedMouthCorners.length, equals(4));
    });

    group('45° Inside Riser Scaling & Coupler Tests (Section 16)', () {
      late DsfDocument riserDoc;
      late List<CmsPhysicalPort> riserBaselinePorts;

      setUp(() {
        final dsfFile = File('assets/dxf_templates/trunking_accessories/45_deg_inside_riser_100x100.dsf');
        final json = jsonDecode(dsfFile.readAsStringSync()) as Map<String, dynamic>;
        var doc = DsfDocument.fromJson(json);

        const faceMap = {
          'F_3': 'F_1', // Flap
          'F_4': 'F_2', // Central floor web (base anchor)
          'F_2': 'F_3', // Left cheek
          'F_5': 'F_0', // Right cheek
          'F_1': 'F_4', // Left flange
          'F_0': 'F_5', // Right flange
        };

        // Normalize canonical bend IDs so B1=left vertical bend, B2=right vertical bend, B3=transverse 45 bend, FL1/FL2=flanges
        final normalizedBends = doc.bends.map((b) {
          String newId = b.id;
          BendLineRole newRole = b.role;
          if (b.targetAngleDeg == 45.0 || ((b.p1.y - 128.65).abs() < 1.0 && (b.p2.y - 128.65).abs() < 1.0)) {
            newId = 'B3';
          } else {
            final avgX = (b.p1.x + b.p2.x) / 2.0;
            if (avgX < 50.0) {
              newId = 'FL1';
              newRole = BendLineRole.flange;
            } else if (avgX > 250.0) {
              newId = 'FL2';
              newRole = BendLineRole.flange;
            } else if (avgX < 150.0) {
              newId = 'B1';
              newRole = BendLineRole.bend;
            } else {
              newId = 'B2';
              newRole = BendLineRole.bend;
            }
          }
          return b.copyWith(
            id: newId,
            role: newRole,
            parentFaceId: faceMap[b.parentFaceId] ?? b.parentFaceId,
            childFaceId: faceMap[b.childFaceId] ?? b.childFaceId,
          );
        }).toList();

        final punches = List<CncPunchPrimitive>.from(doc.punches);
        if (!punches.any((p) => p.id == 'SLOT_5')) {
          punches.addAll([
            CncPunchPrimitive(
              id: 'SLOT_5',
              type: PunchType.obroundSlot,
              center: const CadPoint2D(228.1938, 9.8247),
              widthMm: 8.0,
              lengthMm: 20.0,
              role: CncPunchRole.coupler,
            ),
            CncPunchPrimitive(
              id: 'SLOT_6',
              type: PunchType.obroundSlot,
              center: const CadPoint2D(278.1938, 9.8247),
              widthMm: 8.0,
              lengthMm: 20.0,
              role: CncPunchRole.coupler,
            ),
            CncPunchPrimitive(
              id: 'SLOT_7',
              type: PunchType.obroundSlot,
              center: const CadPoint2D(86.19, 9.8247),
              widthMm: 8.0,
              lengthMm: 20.0,
              role: CncPunchRole.coupler,
            ),
            CncPunchPrimitive(
              id: 'SLOT_8',
              type: PunchType.obroundSlot,
              center: const CadPoint2D(36.19, 9.8247),
              widthMm: 8.0,
              lengthMm: 20.0,
              role: CncPunchRole.coupler,
            ),
          ]);
        }

        final normalizedFaces = doc.faces.map((f) {
          final mappedId = faceMap[f.id] ?? f.id;
          return f.copyWith(
            id: mappedId,
            isBaseAnchor: mappedId == 'F_2',
          );
        }).toList();

        riserDoc = doc.copyWith(
          bends: normalizedBends,
          faces: normalizedFaces,
          baseFaceId: 'F_2',
          punches: punches,
          dimensions: const [],
          constraints: const [],
        );

        riserBaselinePorts = const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ];
      });

      test('Test A — 45° Inside Riser Width Scaling (100 -> 150 mm)', () {
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        controller.selectParameter('width');
        controller.evaluateMorph(150.0);

        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        final scaledDoc = preview.scaledDocument;

        // 1. Floor web reaches expected structural width (145.6 mm)
        final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
        final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
        final scaledFloorSpan = (b2.p1.x - b1.p1.x).abs();
        expect(scaledFloorSpan, closeTo(145.8, 0.5));

        // 2. B3 retains its transverse fold relationship (y remains 128.65, angle 45)
        final b3 = scaledDoc.bends.firstWhere((b) => b.id == 'B3');
        expect(b3.targetAngleDeg, equals(45.0));
        expect(b3.p1.y, closeTo(128.65, 0.1));
        expect(b3.p2.y, closeTo(128.65, 0.1));

        // 3. Cheeks move rigidly by -25 and +25 without skew
        final origB1 = riserDoc.bends.firstWhere((b) => b.id == 'B1');
        final origB2 = riserDoc.bends.firstWhere((b) => b.id == 'B2');
        expect(b1.p1.x, closeTo(origB1.p1.x - 25.0, 0.1));
        expect(b2.p1.x, closeTo(origB2.p1.x + 25.0, 0.1));

        // 4. Coupler slots retain exact shape, dimensions and rotation
        expect(scaledDoc.punches.length, equals(riserDoc.punches.length));
        for (int i = 0; i < riserDoc.punches.length; i++) {
          final origPunch = riserDoc.punches[i];
          final scaledPunch = scaledDoc.punches[i];
          expect(scaledPunch.widthMm, equals(origPunch.widthMm));
          expect(scaledPunch.lengthMm, equals(origPunch.lengthMm));
          expect(scaledPunch.rotationDeg, equals(origPunch.rotationDeg));
        }
      });

      test('Test B — 45° Inside Riser Height Scaling (100 -> 150 mm)', () {
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        controller.selectParameter('height');
        controller.evaluateMorph(150.0);

        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);
        final scaledDoc = preview.scaledDocument;

        // 1. Floor web width remains fixed (B1, B2 fixed in X), and B3 shifts by +22.175 mm
        final origB1 = riserDoc.bends.firstWhere((b) => b.id == 'B1');
        final origB2 = riserDoc.bends.firstWhere((b) => b.id == 'B2');
        final origB3 = riserDoc.bends.firstWhere((b) => b.id == 'B3');

        final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
        final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
        final b3 = scaledDoc.bends.firstWhere((b) => b.id == 'B3');

        expect(b1.p1.x, closeTo(origB1.p1.x, 0.1));
        expect(b2.p1.x, closeTo(origB2.p1.x, 0.1));
        expect(b3.p1.y, closeTo(origB3.p1.y + 22.175, 0.1));

        // 2. Floor flap F_1 length expands proportionally to maintain 0 miter gap with cheek prongs
        final origFloorFace = riserDoc.faces.firstWhere((f) => f.id == 'F_1');
        final scaledFloorFace = scaledDoc.faces.firstWhere((f) => f.id == 'F_1');
        final origFloorY = origFloorFace.vertices.map((v) => v.y).reduce((a, b) => a > b ? a : b) -
            origFloorFace.vertices.map((v) => v.y).reduce((a, b) => a < b ? a : b);
        final scaledFloorY = scaledFloorFace.vertices.map((v) => v.y).reduce((a, b) => a > b ? a : b) -
            scaledFloorFace.vertices.map((v) => v.y).reduce((a, b) => a < b ? a : b);
        expect(scaledFloorY, closeTo(origFloorY + 21.125, 1.5));

        // 2b. Both PORT_1 and PORT_2 heights scale synchronously to 150 mm
        final port1 = preview.derivedPorts.firstWhere((p) => p.id == 'PORT_1');
        final port2 = preview.derivedPorts.firstWhere((p) => p.id == 'PORT_2');
        expect(port1.height, closeTo(150.0, 3.5), reason: 'Port 1 height must scale to ~150 mm');
        expect(port2.height, closeTo(150.0, 3.5), reason: 'Port 2 height must scale to ~150 mm');
        expect((port1.height - port2.height).abs(), lessThan(4.0), reason: 'Entry and exit ports must scale together');

        // 2c. Port 2's glass face does NOT protrude beyond the folded part boundary
        final scaledMesh = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
        final meshMaxZ = scaledMesh.polygons.expand((p) => p.vertices).map((v) => v.z).reduce(math.max);
        for (final corner in port2.derivedMouthCorners) {
          expect(corner.z, lessThanOrEqualTo(meshMaxZ + 0.1), reason: 'Port 2 corner must not protrude above part boundary');
        }
        // Top lips are separated in 3D (not stuck together)
        final lip1Y = port1.derivedMouthCorners[1].y;
        final lip2Y = port2.derivedMouthCorners[1].y;
        expect((lip2Y - lip1Y).abs(), greaterThan(20.0));

        // 3. Coupler slots remain undistorted (exact shape, pitch, and rotation)
        for (int i = 0; i < riserDoc.punches.length; i++) {
          final origPunch = riserDoc.punches[i];
          final scaledPunch = scaledDoc.punches[i];
          expect(scaledPunch.widthMm, equals(origPunch.widthMm));
          expect(scaledPunch.lengthMm, equals(origPunch.lengthMm));
          expect(scaledPunch.rotationDeg, equals(origPunch.rotationDeg));
        }

        // 4. Coupler slot pairs maintain exact 45.0° alignment along the expanded mouth edge
        final s3 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_3');
        final s4 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_4');
        final distS3S4 = math.sqrt(math.pow(s4.center.x - s3.center.x, 2) + math.pow(s4.center.y - s3.center.y, 2));
        final angleS3S4 = math.atan2(s3.center.y - s4.center.y, s3.center.x - s4.center.x) * 180 / math.pi;
        expect(distS3S4, closeTo(100.0, 0.5), reason: 'SLOT_3 and SLOT_4 expand with the 150mm mouth');
        expect(angleS3S4, closeTo(45.0, 0.1));

        final s1 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_1');
        final s2 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_2');
        final distS1S2 = math.sqrt(math.pow(s2.center.x - s1.center.x, 2) + math.pow(s2.center.y - s1.center.y, 2));
        final angleS1S2 = math.atan2(s2.center.y - s1.center.y, s2.center.x - s1.center.x) * 180 / math.pi;
        expect(distS1S2, closeTo(100.0, 0.5), reason: 'SLOT_1 and SLOT_2 expand with the 150mm mouth');
        expect(angleS1S2, closeTo(-45.0, 0.1));

        // 5. Normalized kinematic DAG topology: Floor Web F_2 is base anchor
        expect(scaledDoc.baseFaceId, equals('F_2'));
        final scaledF2 = scaledDoc.faces.firstWhere((f) => f.id == 'F_2');
        expect(scaledF2.isBaseAnchor, isTrue);

        // 6. Test scaling to 200 mm (SS3): Both ports reach ~200 mm synchronously
        controller.evaluateMorph(200.0);
        final preview200 = controller.currentPreview!;
        final p1_200 = preview200.derivedPorts.firstWhere((p) => p.id == 'PORT_1');
        final p2_200 = preview200.derivedPorts.firstWhere((p) => p.id == 'PORT_2');
        expect(p1_200.height, closeTo(200.0, 4.0), reason: 'Port 1 height must scale to ~200 mm');
        expect(p2_200.height, closeTo(200.0, 4.0), reason: 'Port 2 height must scale to ~200 mm');
        expect((p1_200.height - p2_200.height).abs(), lessThan(5.0), reason: 'Both ports must scale synchronously to 200 mm');
      });

      test('Test C — Reset Dimensions restores baseline parameters and geometry', () {
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        controller.selectParameter('width');
        controller.evaluateMorph(150.0);
        expect(controller.previewMorphValue, equals(150.0));
        expect(controller.currentPreview!.scaledDocument.blankWidthMm, greaterThan(riserDoc.blankWidthMm));

        // Press Reset Dimensions
        controller.resetToBaseline();

        expect(controller.previewMorphValue, equals(100.0));
        expect(controller.model.parameters['width']!.currentValue, equals(100.0));
        expect(controller.model.parameters['height']!.currentValue, equals(100.0));
        expect(controller.currentPreview!.scaledDocument.blankWidthMm, closeTo(riserDoc.blankWidthMm, 0.1));
      });

      test('Test D — Coupler Recognition recognizes 20mm obround slots in 45 deg inside riser', () {
        final result = CmsCouplerClassifier.classify(
          document: riserDoc,
          contract: CmsProductContract.insideRiser45,
          ports: riserBaselinePorts,
        );

        // 20mm obround slots must become coupler slots
        expect(result.couplerSlots, isNotEmpty);
        expect(result.couplerSlots.any((p) => p.lengthMm >= 19.5 && p.lengthMm <= 20.5), isTrue);
      });

      test('Test E — Explicit Coupler Marking toggles semantic role in DSF', () {
        final vm = SheetMetalStudioViewModel(initialDocument: riserDoc);
        final firstPunch = riserDoc.punches.first;

        // Explicitly mark as coupler
        vm.markPunchAsCoupler(firstPunch.id, isCoupler: true);
        final punchAfterMark = vm.document.punches.firstWhere((p) => p.id == firstPunch.id);
        expect(punchAfterMark.role, equals(CncPunchRole.coupler));

        // Toggle back to regular/perforation
        vm.markPunchAsCoupler(firstPunch.id, isCoupler: false);
        final punchAfterUnmark = vm.document.punches.firstWhere((p) => p.id == firstPunch.id);
        expect(punchAfterUnmark.role, equals(CncPunchRole.perforation));
      });

      test('Test F — Backward Compatibility with older DSF files', () {
        final oldFile = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
        final oldDoc = DsfDocument.fromJson(jsonDecode(oldFile.readAsStringSync()) as Map<String, dynamic>);

        // Should open without error
        final vm = SheetMetalStudioViewModel(initialDocument: oldDoc);
        expect(vm.document.productType, equals('45_deg_bend_100x100'));
        expect(vm.document.faces, isNotEmpty);
      });

      test('Test G — End-to-End ViewModel flow for 45° Inside Riser (reproducing SS1 & SS2)', () async {
        final vm = SheetMetalStudioViewModel(initialDocument: riserDoc);

        // 1. Map ports
        await vm.continueCmsPortMapping();

        // 2. Start Teach Scaling
        vm.startTeachScaling();
        expect(vm.isTeachScalingActive, isTrue);

        final ctrl = vm.scalingController!;
        expect(ctrl.effectiveScalingProfile, equals(CmsScalingProfile.insideRiser));

        // 3. Test SS1: Height scaling to 290.0 mm (+192.5 mm) must NOT lengthen parts along Y
        ctrl.selectParameter('height');
        ctrl.evaluateMorph(290.0);
        final heightPreview = ctrl.currentPreview!;
        expect(heightPreview.isValid, isTrue);

        // Verify B3 shifts synchronously with height expansion (+85.38 mm for +192.5 mm delta)
        final b3H = heightPreview.scaledDocument.bends.firstWhere((b) => b.id == 'B3');
        expect(b3H.p1.y, closeTo(128.65 + 44.35 * (192.5 / 100.0), 0.2));

        // Verify floor flap length expands synchronously
        final origFloor = riserDoc.faces.firstWhere(
          (f) => f.centroid.x >= 112.0 && f.centroid.x <= 209.0 && f.centroid.y > 128.0,
        );
        final scaledFloor = heightPreview.scaledDocument.faces.firstWhere(
          (f) => f.centroid.x >= 112.0 && f.centroid.x <= 209.0 && f.centroid.y > 128.0,
        );
        final origYRange = origFloor.vertices.map((v) => v.y).reduce(math.max) - origFloor.vertices.map((v) => v.y).reduce(math.min);
        final scaledYRange = scaledFloor.vertices.map((v) => v.y).reduce(math.max) - scaledFloor.vertices.map((v) => v.y).reduce(math.min);
        expect(scaledYRange, closeTo(origYRange + 42.25 * (192.5 / 100.0), 0.5));

        // Verify both ports scale synchronously
        final port1 = heightPreview.derivedPorts.firstWhere((p) => p.id == 'PORT_1');
        final port2 = heightPreview.derivedPorts.firstWhere((p) => p.id == 'PORT_2');
        expect(port1.height, closeTo(290.0, 5.0));
        expect(port2.height, closeTo(290.0, 5.0));

        // 4. Test SS2: Width scaling to 205.0 mm must NOT produce a trapezoidal miter
        ctrl.selectParameter('width');
        ctrl.evaluateMorph(205.0);
        final widthPreview = ctrl.currentPreview!;
        expect(widthPreview.isValid, isTrue);

        // Floor web must expand uniformly (B1 and B2 must remain vertical, not skewed into a trapezoid)
        final b1W = widthPreview.scaledDocument.bends.firstWhere((b) => b.id == 'B1');
        final b2W = widthPreview.scaledDocument.bends.firstWhere((b) => b.id == 'B2');
        expect((b1W.p1.x - b1W.p2.x).abs(), closeTo(0.7, 0.2)); // Vertical line
        expect((b2W.p1.x - b2W.p2.x).abs(), closeTo(0.25, 0.2)); // Vertical line
        expect(b2W.p1.x - b1W.p1.x, closeTo(205.0 - 5.0, 5.0)); // 200 mm channel width

        // 5. Test Height scaling with 200 mm parameter
        ctrl.selectParameter('height');
        ctrl.evaluateMorph(200.0);
        final heightPreview2 = ctrl.currentPreview!;
        final b3H2 = heightPreview2.scaledDocument.bends.firstWhere((b) => b.id == 'B3');
        expect(b3H2.p1.y, closeTo(174.1, 0.5));
      });

      test('Test H — Geometric Riser Detection overrides generic/unrelated productType and contract', () {
        // Document with generic/unknown productType and no 'riser' string
        final genericRiserDoc = riserDoc.copyWith(
          productType: 'Sheet Metal Part',
          itemName: 'Custom_Part_001.dxf',
        );

        // Geometrically detected as inside riser
        expect(CmsScalingController.isInsideRiserGeometry(genericRiserDoc), isTrue);

        // Even when passed bend45 contract, effectiveScalingProfile is insideRiser
        final controller = CmsScalingController(
          baselineDocument: genericRiserDoc,
          contract: CmsProductContract.bend45,
          baselinePorts: riserBaselinePorts,
        );
        expect(controller.effectiveScalingProfile, equals(CmsScalingProfile.insideRiser));

        // Height scaling to 200 mm shifts B3 to 173.0 mm matching official 100x200.dxf
        controller.selectParameter('height');
        controller.evaluateMorph(200.0);
        final heightPreview = controller.currentPreview!;
        final b3H = heightPreview.scaledDocument.bends.firstWhere((b) => b.id == 'B3');
        expect(b3H.p1.y, closeTo(173.0, 0.2));
      });

      test('Test I — 3D Folded Model smoothly expands corner arcs into curved boundaries and rims', () {
        // 1. Verify coupler slots in riserDoc
        expect(riserDoc.punches.every((p) => p.role == CncPunchRole.coupler), isTrue);
        expect(riserDoc.arcs.length, equals(8));

        // 2. Fold document into 3D mesh
        final mesh = KinematicFoldEngine.foldDocument(riserDoc, foldProgress: 1.0);
        final polyF0 = mesh.polygons.firstWhere((p) => p.faceId == 'F_0');
        final polyF4 = mesh.polygons.firstWhere((p) => p.faceId == 'F_4');

        // Instead of 15 straight chord vertices, faces are expanded into smooth curves
        expect(polyF0.vertices.length, greaterThan(30));
        expect(polyF4.vertices.length, greaterThan(30));
        expect(polyF0.boundaryLines.length, greaterThan(30));

        // 3. Test after morphing: arcs are preserved and scaled in lockstep
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );
        controller.selectParameter('width');
        controller.evaluateMorph(150.0);
        final widthPreview = controller.currentPreview!;
        expect(widthPreview.scaledDocument.arcs.length, equals(8));

        final scaledMesh = KinematicFoldEngine.foldDocument(widthPreview.scaledDocument, foldProgress: 1.0);
        final scaledPolyF0 = scaledMesh.polygons.firstWhere((p) => p.faceId == 'F_0');
        expect(scaledPolyF0.vertices.length, greaterThan(30));
      });

      test('Test J — Height Scaling preserves all corner arcs and chamfers with exact original radius (10.0mm) and 0.0mm endpoint deviation', () {
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        for (final targetH in [115.0, 130.0, 150.0]) {
          controller.selectParameter('height');
          controller.evaluateMorph(targetH);
          final preview = controller.currentPreview!;
          expect(preview.isValid, isTrue);

          final doc = preview.scaledDocument;
          final f0 = doc.faces.firstWhere((f) => f.id == 'F_0');
          final f4 = doc.faces.firstWhere((f) => f.id == 'F_4');

          for (final a in doc.arcs) {
            // 1. Radius must remain exactly 10.0 mm (no distortion into ellipse)
            expect(a.radius, closeTo(10.0, 0.001));

            // 2. Both arc endpoints must exactly match a vertex in the face (no gap/disconnection)
            final verts = (a.id == 'ARC_BND_3' || a.id == 'ARC_BND_4' || a.id == 'ARC_BND_5' || a.id == 'ARC_BND_6')
                ? f4.vertices
                : f0.vertices;

            final d1 = verts.map((v) => a.startPoint.distanceTo(v)).reduce(math.min);
            final d2 = verts.map((v) => a.endPoint.distanceTo(v)).reduce(math.min);

            expect(d1, closeTo(0.0, 0.05), reason: 'Arc ${a.id} startPoint must match face vertex');
            expect(d2, closeTo(0.0, 0.05), reason: 'Arc ${a.id} endPoint must match face vertex');
          }
        }
      });

      test('Test K — Resolving SS1 & SS2: Coupler holes with independent edge constraints maintain exact 23.0 mm distance from host edges and move apart as height expands', () {
        // Reproduce SS1: Attach 23.0 mm dimensions to SLOT_5 (inner edge) and SLOT_6 (outer edge)
        final dimInner = CadDimension(
          id: 'dim_slot5_inner',
          type: CadDimensionType.holeToEdge,
          referenceAId: 'SLOT_5',
          referenceBId: 'CONTOUR_EDGE_23',
          pointA: const CadPoint2D(228.1938, 9.8247),
          pointB: const CadPoint2D(205.1938, 9.8247),
          measuredValue: 23.0,
          isDriven: false,
          isDriving: true,
        );
        final dimOuter = CadDimension(
          id: 'dim_slot6_outer',
          type: CadDimensionType.holeToEdge,
          referenceAId: 'SLOT_6',
          referenceBId: 'CONTOUR_EDGE_27',
          pointA: const CadPoint2D(278.1938, 9.8247),
          pointB: const CadPoint2D(301.1938, 9.8247),
          measuredValue: 23.0,
          isDriven: false,
          isDriving: true,
        );

        final docWithDims = riserDoc.copyWith(
          dimensions: [dimInner, dimOuter],
        );

        final controller = CmsScalingController(
          baselineDocument: docWithDims,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        // Scale Height from 98 mm to 150 mm (+52.0 mm)
        controller.selectParameter('height');
        controller.evaluateMorph(150.0);
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        final scaledDoc = preview.scaledDocument;

        // 1. SLOT_5 (inner hole): must remain fixed at x ≈ 228.19 (dx = 0)
        final scaledS5 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_5');
        expect(scaledS5.center.x, closeTo(228.19, 0.2), reason: 'SLOT_5 must NOT translate right; must stay 23mm from inner edge');

        // 2. SLOT_6 (outer hole): must translate with outer edge by +50.0 mm (x ≈ 328.19)
        final scaledS6 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_6');
        expect(scaledS6.center.x, closeTo(278.19 + 50.0, 0.3), reason: 'SLOT_6 must translate with outer edge');

        // 3. Both holes must have moved apart (from 50.0 mm to 100.0 mm pitch)
        final distS5S6 = (scaledS6.center.x - scaledS5.center.x).abs();
        expect(distS5S6, closeTo(100.0, 0.4), reason: 'SLOT_5 and SLOT_6 must move apart during height expansion');

        // 4. Dimensions must strictly preserve 23.0 mm measured values (NOT 75.5 or 29.5 mm)
        final scaledDimInner = scaledDoc.dimensions.firstWhere((d) => d.id == 'dim_slot5_inner');
        final scaledDimOuter = scaledDoc.dimensions.firstWhere((d) => d.id == 'dim_slot6_outer');
        expect(scaledDimInner.measuredValue, closeTo(23.0, 0.2), reason: 'Inner dimension must remain 23.0 mm (never 75.5 mm)');
        expect(scaledDimOuter.measuredValue, closeTo(23.0, 0.2), reason: 'Outer dimension must remain 23.0 mm (never 29.5 mm)');

        // 5. Same behavior on Left Cheek (SLOT_7 and SLOT_8)
        final scaledS7 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_7');
        final scaledS8 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_8');
        expect(scaledS7.center.x, closeTo(86.19, 0.2), reason: 'SLOT_7 must remain fixed near inner edge');
        expect(scaledS8.center.x, closeTo(36.19 - 50.0, 0.3), reason: 'SLOT_8 must translate with outer edge');
        final distS7S8 = (scaledS7.center.x - scaledS8.center.x).abs();
        expect(distS7S8, closeTo(100.0, 0.4), reason: 'SLOT_7 and SLOT_8 must move apart');
      });

      test('Test L — Punch-to-Punch Distance Lock: When 2 coupler holes are constrained to each other, they stay at the exact same distance from each other', () {
        // Constrain SLOT_5 to inner edge, and constrain SLOT_6 to SLOT_5 with a 50.0 mm hole-to-hole dimension
        final dimInner = CadDimension(
          id: 'dim_slot5_inner',
          type: CadDimensionType.holeToEdge,
          referenceAId: 'SLOT_5',
          referenceBId: 'CONTOUR_EDGE_23',
          pointA: const CadPoint2D(228.1938, 9.8247),
          pointB: const CadPoint2D(205.1938, 9.8247),
          measuredValue: 23.0,
          isDriven: false,
          isDriving: true,
        );
        final dimHoleToHole = CadDimension(
          id: 'dim_slot5_slot6',
          type: CadDimensionType.holeToHole,
          referenceAId: 'SLOT_5',
          referenceBId: 'SLOT_6',
          pointA: const CadPoint2D(228.1938, 9.8247),
          pointB: const CadPoint2D(278.1938, 9.8247),
          measuredValue: 50.0,
          isDriven: false,
          isDriving: true,
        );

        final docWithHoleConstraint = riserDoc.copyWith(
          dimensions: [dimInner, dimHoleToHole],
        );

        final controller = CmsScalingController(
          baselineDocument: docWithHoleConstraint,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        // Scale Height from 98 mm to 150 mm (+52.0 mm)
        controller.selectParameter('height');
        controller.evaluateMorph(150.0);
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        final scaledDoc = preview.scaledDocument;
        final scaledS5 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_5');
        final scaledS6 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_6');

        // Distance between SLOT_5 and SLOT_6 must remain strictly 50.0 mm
        final dist = (scaledS6.center.x - scaledS5.center.x).abs();
        expect(dist, closeTo(50.0, 0.1), reason: 'Two holes constrained to each other must stay at the exact same distance');
      });

      test('Test O — Centering Rule: When 2 parts are dimensionally constrained to each other without edge anchors, keep them at the center during template scaling', () {
        // Constrain ONLY SLOT_5 to SLOT_6 with a 50.0 mm hole-to-hole dimension (NO edge constraints)
        final dimHoleToHole = CadDimension(
          id: 'dim_slot5_slot6_pure',
          type: CadDimensionType.holeToHole,
          referenceAId: 'SLOT_5',
          referenceBId: 'SLOT_6',
          pointA: const CadPoint2D(228.1938, 9.8247),
          pointB: const CadPoint2D(278.1938, 9.8247),
          measuredValue: 50.0,
          isDriven: false,
          isDriving: true,
        );

        final docPureConstraint = riserDoc.copyWith(
          dimensions: [dimHoleToHole],
        );

        final controller = CmsScalingController(
          baselineDocument: docPureConstraint,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        // Scale Height from 98 mm to 150 mm (+52.0 mm)
        controller.selectParameter('height');
        controller.evaluateMorph(150.0);
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        final scaledDoc = preview.scaledDocument;
        final scaledS5 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_5');
        final scaledS6 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_6');

        // 1. Distance between them must remain strictly 50.0 mm
        final dist = (scaledS6.center.x - scaledS5.center.x).abs();
        expect(dist, closeTo(50.0, 0.1), reason: 'Pitch between holes must remain exactly 50 mm');

        // 2. The pair must stay at the center of the expanded cheek tab!
        // Inner boundary is at bend line x = 205.1938 (x2).
        // Outer boundary is the vertical tab edge near SLOT_6.
        final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2' || ((b.targetAngleDeg.abs() - 90.0).abs() < 10.0 && b.p1.x > 100));
        final innerX = b2.p1.x;
        double outerX = innerX;
        for (int i = 0; i < scaledDoc.outerContour.length; i++) {
          final a = scaledDoc.outerContour[i];
          final b = scaledDoc.outerContour[(i + 1) % scaledDoc.outerContour.length];
          if (a.x > innerX && (b.x - a.x).abs() < 1.0 && (b.y - a.y).abs() > 2.0 && a.y < 50.0) {
            outerX = a.x;
            break;
          }
        }

        final marginInner = (scaledS5.center.x - innerX).abs();
        final marginOuter = (outerX - scaledS6.center.x).abs();

        // The margins to inner and outer edges must be equal (centered!)
        expect(marginInner, closeTo(marginOuter, 0.5),
          reason: 'Group must remain strictly centered with equal margins (inner: $marginInner mm, outer: $marginOuter mm)');
      });

      test('Test M — Universal Fallback: Unconstrained coupler holes automatically maintain host edge setback without user constraints', () {
        // Raw riserDoc with ZERO explicit dimensions or constraints
        expect(riserDoc.dimensions, isEmpty);
        expect(riserDoc.constraints, isEmpty);

        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        controller.selectParameter('height');
        controller.evaluateMorph(150.0);
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        final scaledDoc = preview.scaledDocument;
        final scaledS5 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_5');
        final scaledS6 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_6');

        // Even without constraints, fallback maintains mounting edge setback:
        // SLOT_5 stays at x ≈ 228.19
        expect(scaledS5.center.x, closeTo(228.19, 0.2));
        // SLOT_6 moves to x ≈ 328.19
        expect(scaledS6.center.x, closeTo(278.19 + 50.0, 0.3));
        // Pitch moves apart to ~100 mm
        expect((scaledS6.center.x - scaledS5.center.x).abs(), closeTo(100.0, 0.4));
      });

      test('Test N — Universal CMS Scope: Coupler holes on other fittings (45 deg bend) maintain pitch and relative constraints during width scaling', () {
        final controller = CmsScalingController(
          baselineDocument: baselineDoc,
          contract: CmsProductContract.bend45,
          baselinePorts: baselinePorts,
        );

        controller.selectParameter('width');
        controller.evaluateMorph(150.0);
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        final scaledDoc = preview.scaledDocument;
        expect(scaledDoc.punches.length, equals(baselineDoc.punches.length));

        // Coupler punch slots must preserve their shape and dimensions
        for (int i = 0; i < baselineDoc.punches.length; i++) {
          final orig = baselineDoc.punches[i];
          final scaled = scaledDoc.punches[i];
          expect(scaled.widthMm, equals(orig.widthMm));
          expect(scaled.lengthMm, equals(orig.lengthMm));
        }
      });

      test('Test P — Reproduce Bug 3: 45 deg bend height scaling with 24mm edge constraint and 50mm pitch constraint', () {
        final s5 = baselineDoc.punches.firstWhere((p) => p.id == 'SLOT_5');
        final s3 = baselineDoc.punches.firstWhere((p) => p.id == 'SLOT_3');
        final fl1 = baselineDoc.bends.firstWhere((b) => b.id == 'FL1');

        final dimEdge = CadDimension(
          id: 'dim_edge_s5',
          type: CadDimensionType.holeToEdge,
          referenceAId: 'FL1',
          referenceBId: 'SLOT_5',
          pointA: CadPoint2D(s5.center.x, fl1.p1.y),
          pointB: s5.center,
          measuredValue: 24.0,
          isDriven: false,
          isDriving: true,
        );

        final dimPitch = CadDimension(
          id: 'dim_s5_s3',
          type: CadDimensionType.holeToHole,
          referenceAId: 'SLOT_5',
          referenceBId: 'SLOT_3',
          pointA: s5.center,
          pointB: s3.center,
          measuredValue: 50.0,
          isDriven: false,
          isDriving: true,
        );

        final docWithDims = baselineDoc.copyWith(
          dimensions: [dimEdge, dimPitch],
        );

        final controller = CmsScalingController(
          baselineDocument: docWithDims,
          contract: CmsProductContract.bend45,
          baselinePorts: baselinePorts,
        );

        controller.selectParameter('height');
        controller.evaluateMorph(150.0);
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        final scaledDoc = preview.scaledDocument;
        final scaledS5 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_5');
        final scaledS3 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_3');
        final scaledFL1 = scaledDoc.bends.firstWhere((b) => b.id == 'FL1');


        // Both holes must stay at 50mm from each other
        expect(scaledS5.center.distanceTo(scaledS3.center), closeTo(50.0, 0.5));
        // SLOT_5 must remain at constant 24mm from FL1
        expect((scaledS5.center.y - scaledFL1.p1.y).abs(), closeTo(24.0, 0.5));
      });

      test('Test Q — Resolving SS2 & SS3: Scaling Width first and then Height preserves left cheek without distortion or spilled coupler holes', () {
        // 1. Initial controller with baseline riserDoc (width ~96mm, height ~98mm)
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        // Step 1: Scale Width to 185 mm (+89 mm) as in SS3
        controller.selectParameter('width');
        controller.evaluateMorph(185.0);
        final widthPreview = controller.currentPreview!;
        expect(widthPreview.isValid, isTrue);

        // Accept the width morph so the document now has 185mm width
        final docAfterWidth = widthPreview.scaledDocument;

        // Step 2: Now scale Height on the width-scaled document to 135 mm (+37.5 mm) as in SS2
        final heightController = CmsScalingController(
          baselineDocument: docAfterWidth,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: widthPreview.derivedPorts,
        );

        heightController.selectParameter('height');
        heightController.evaluateMorph(135.0);
        final preview135 = heightController.currentPreview!;
        expect(preview135.isValid, isTrue);

        final doc135 = preview135.scaledDocument;

        // Verify left cheek prongs and flanges:
        final fl1Orig = docAfterWidth.bends.firstWhere((b) => b.id == 'FL1');
        final fl1_135 = doc135.bends.firstWhere((b) => b.id == 'FL1');
        expect((fl1_135.p1.x - fl1_135.p2.x).abs(), closeTo((fl1Orig.p1.x - fl1Orig.p2.x).abs(), 0.05));

        // Coupler slots on left cheek:
        final s3_135 = doc135.punches.firstWhere((p) => p.id == 'SLOT_3');
        final s4_135 = doc135.punches.firstWhere((p) => p.id == 'SLOT_4');

        // SLOT_3 and SLOT_4 maintain 45° angle
        final angle135 = math.atan2(s3_135.center.y - s4_135.center.y, s3_135.center.x - s4_135.center.x) * 180 / math.pi;
        expect(angle135, closeTo(45.0, 0.1));

        // Neither slot is spilled out: both slot centers must be well within the outerContour bounds
        double minContourX = double.infinity;
        double maxContourX = -double.infinity;
        for (final pt in doc135.outerContour) {
          if (pt.x < minContourX) minContourX = pt.x;
          if (pt.x > maxContourX) maxContourX = pt.x;
        }
        expect(s4_135.center.x, greaterThan(minContourX));
        expect(s3_135.center.x, greaterThan(minContourX));
        expect(s4_135.center.x, lessThan(maxContourX));
        expect(s3_135.center.x, lessThan(maxContourX));

        // Step 3: Now scale Height down to 125 mm as in SS3
        heightController.evaluateMorph(125.0);
        final preview125 = heightController.currentPreview!;
        expect(preview125.isValid, isTrue);

        final doc125 = preview125.scaledDocument;
        final fl1_125 = doc125.bends.firstWhere((b) => b.id == 'FL1');
        expect((fl1_125.p1.x - fl1_125.p2.x).abs(), closeTo((fl1Orig.p1.x - fl1Orig.p2.x).abs(), 0.05));

        final s3_125 = doc125.punches.firstWhere((p) => p.id == 'SLOT_3');
        final s4_125 = doc125.punches.firstWhere((p) => p.id == 'SLOT_4');
        final angle125 = math.atan2(s3_125.center.y - s4_125.center.y, s3_125.center.x - s4_125.center.x) * 180 / math.pi;
        expect(angle125, closeTo(45.0, 0.1));

        // 3D Folded Model is valid and both ports scale
        final mesh135 = KinematicFoldEngine.foldDocument(doc135, foldProgress: 1.0);
        expect(mesh135.polygons, isNotEmpty);
      });

      test('Test R — Resolving Requests 4 & 5: Moving width slider and switching to height slider preserves both, and re-opening dialog reflects real drawing size', () {
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        // 1. Move Width slider to 150.0 mm
        controller.selectParameter('width');
        controller.evaluateMorph(150.0);
        expect(controller.model.parameters['width']!.currentValue, equals(150.0));

        // 2. Switch tab to Height without width reverting
        controller.selectParameter('height');
        expect(controller.model.parameters['width']!.currentValue, equals(150.0)); // Width is preserved!

        // 3. Move Height slider to 135.0 mm
        controller.evaluateMorph(135.0);
        expect(controller.model.parameters['height']!.currentValue, equals(135.0));
        expect(controller.model.parameters['width']!.currentValue, equals(150.0)); // Both active!

        // 4. Preview document combines both width (+50mm) and height (+35mm)
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);
        final scaledDoc = preview.scaledDocument;

        // Floor width expanded by ~50mm
        final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
        final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
        expect((b2.p1.x - b1.p1.x).abs(), closeTo(145.8, 0.5));

        // B3 height expanded by ~15.5mm
        final b3 = scaledDoc.bends.firstWhere((b) => b.id == 'B3');
        expect(b3.p1.y, greaterThan(140.0));

        // 5. Accept Scaling Model
        final acceptedDoc = controller.acceptScalingModel();
        final derivedPorts = preview.derivedPorts;

        // 6. User re-opens the template scaling dialog (Request 5)
        final reopenedController = CmsScalingController(
          baselineDocument: acceptedDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: derivedPorts,
        );

        // Slider takes the actual real place just as the drawing!
        expect(reopenedController.model.parameters['width']!.currentValue, closeTo(150.0, 1.0));
        expect(reopenedController.model.parameters['height']!.currentValue, closeTo(135.0, 1.0));
      });

      test('Test S — Resolving SS1, SS2 & SS3: 45° Inside Riser height scaling to 150mm and 200mm extends mouth upward and preserves return flange FL1/FL2', () {
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.insideRiser45,
          baselinePorts: riserBaselinePorts,
        );

        controller.selectParameter('height');

        // --- 1. Scale Height to 150mm (+50mm delta) ---
        controller.evaluateMorph(150.0);
        final preview150 = controller.currentPreview!;
        expect(preview150.isValid, isTrue);
        final doc150 = preview150.scaledDocument;

        // Outer corner anchor test: Point at X <= 25.0 must stay at baseline Y (approx 115-120mm) and NOT shift down into flange
        final outerCornerPts150 = doc150.outerContour.where((p) => p.x <= 25.0 && p.y >= 110.0 && p.y <= 125.0).toList();
        expect(outerCornerPts150, isNotEmpty);
        for (final pt in outerCornerPts150) {
          expect(pt.y, closeTo(116.9, 2.0)); // Y is anchored (actual DSF corner is ~116.92mm)
        }

        // Return flange FL1 test: FL1 must remain vertical and not intersect diagonal cut
        final fl1_150 = doc150.bends.firstWhere((b) => b.id == 'FL1');
        expect(fl1_150.p1.y, lessThan(90.0));
        expect(fl1_150.p2.y, lessThan(90.0));

        // Fold 3D mesh at 150mm: Both ports must scale cleanly to ~150mm
        final mesh150 = KinematicFoldEngine.foldDocument(doc150, foldProgress: 1.0);
        expect(mesh150.polygons, isNotEmpty);
        final ports150 = preview150.derivedPorts;
        expect(ports150.first.height, closeTo(148.0, 4.0));
        expect(ports150.last.height, closeTo(151.0, 4.0));

        // --- 2. Scale Height to 200mm (+100mm delta as in official DXF) ---
        controller.evaluateMorph(200.0);
        final preview200 = controller.currentPreview!;
        expect(preview200.isValid, isTrue);
        final doc200 = preview200.scaledDocument;

        // Outer corner anchor test: Still anchored at Y ~ 116.9mm
        final outerCornerPts200 = doc200.outerContour.where((p) => p.x <= 25.0 && p.y >= 110.0 && p.y <= 125.0).toList();
        expect(outerCornerPts200, isNotEmpty);
        for (final pt in outerCornerPts200) {
          expect(pt.y, closeTo(116.9, 2.0));
        }

        // Fold 3D mesh at 200mm: Both ports must scale cleanly to ~200mm
        final mesh200 = KinematicFoldEngine.foldDocument(doc200, foldProgress: 1.0);
        expect(mesh200.polygons, isNotEmpty);
        final ports200 = preview200.derivedPorts;
        expect(ports200.first.height, closeTo(198.0, 4.0));
        expect(ports200.last.height, closeTo(202.0, 4.0));
      });

      test('Test T — Multi-port Tee and Cross fittings support Equal (Linked) and Unequal (Independent) scaling modes', () {
        // Create a 3-port Tee mock fitting (no 'side' field in CmsPhysicalPort; use normal vectors instead)
        final p1 = CmsPhysicalPort(id: 'P1', index: 1, width: 100.0, height: 50.0, normal: const CadPoint3D(0, 1, 0), center: const CadPoint3D(0, 100, 25));
        final p2 = CmsPhysicalPort(id: 'P2', index: 2, width: 100.0, height: 50.0, normal: const CadPoint3D(1, 0, 0), center: const CadPoint3D(100, 0, 25));
        final p3 = CmsPhysicalPort(id: 'P3', index: 3, width: 100.0, height: 50.0, normal: const CadPoint3D(0, -1, 0), center: const CadPoint3D(0, -100, 25));

        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.tee, // equalTee is an alias for .tee
          baselinePorts: [p1, p2, p3],
        );

        // Verify initial state: multi-port fitting defaults to linked ports
        expect(controller.isMultiPortFitting, isTrue);
        expect(controller.isLinkedPorts, isTrue);
        expect(controller.model.parameters.containsKey('width'), isTrue);
        expect(controller.model.parameters.containsKey('height'), isTrue);

        // Toggle to Unequal (Independent) mode
        controller.togglePortLinking(false);
        expect(controller.isLinkedPorts, isFalse);
        expect(controller.model.parameters.containsKey('port1_width'), isTrue);
        expect(controller.model.parameters.containsKey('port2_width'), isTrue);
        expect(controller.model.parameters.containsKey('port3_width'), isTrue);

        // Switch to Port 2 and morph its width independently
        controller.setActivePortIndex(1);
        expect(controller.activePortIndex, equals(1));
        expect(controller.activeParameterId, equals('port2_width'));

        controller.evaluateMorph(150.0);
        expect(controller.model.parameters['port2_width']!.currentValue, equals(150.0));
        // Port 1 and Port 3 remain at baseline 100mm!
        expect(controller.model.parameters['port1_width']!.currentValue, equals(100.0));
        expect(controller.model.parameters['port3_width']!.currentValue, equals(100.0));
      });

      test('Test U — Unequal Tee Independent Height Scaling preserves max body height and retracts flaps for lower-height ports', () {
        final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
        final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
        final teeDoc = DsfDocument.fromJson(json);

        final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
        final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
        final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);

        final controller = CmsScalingController(
          baselineDocument: teeDoc,
          contract: CmsProductContract.tee,
          baselinePorts: [p1, p2, p3],
        );

        // Toggle to unlinked/independent mode
        controller.togglePortLinking(false);
        expect(controller.isLinkedPorts, isFalse);
        expect(controller.model.parameters.containsKey('port2_height'), isTrue);

        // Scale Port 2 height down to 50mm
        controller.selectParameter('port2_height');
        controller.evaluateMorph(50.0);

        expect(controller.currentPreview, isNotNull);
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        // Port 2 height is 50mm, while Ports 1 & 3 maintain 100mm
        final ports = preview.derivedPorts;
        final port2 = ports.firstWhere((p) => p.index == 2);
        final port1 = ports.firstWhere((p) => p.index == 1);
        final port3 = ports.firstWhere((p) => p.index == 3);
        expect(port2.height, equals(50.0));
        expect(port1.height, equals(100.0));
        expect(port3.height, equals(100.0));

        // 3D mesh is folded with valid polygons
        expect(preview.foldedMesh.polygons, isNotEmpty);
      });

      test('Test V — Unequal Cross Independent Height Scaling maintains separate port dimensions', () {
        final crossFile = File('assets/dxf_templates/trunking_accessories/equal_cross_100x100.dsf');
        final json = jsonDecode(crossFile.readAsStringSync()) as Map<String, dynamic>;
        final crossDoc = DsfDocument.fromJson(json);

        final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
        final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
        final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);
        final p4 = const CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0);

        final controller = CmsScalingController(
          baselineDocument: crossDoc,
          contract: CmsProductContract.cross,
          baselinePorts: [p1, p2, p3, p4],
        );

        // Toggle to unlinked/independent mode
        controller.togglePortLinking(false);
        expect(controller.isLinkedPorts, isFalse);
        expect(controller.model.parameters.containsKey('port4_height'), isTrue);

        // Scale Port 4 height down to 50mm
        controller.selectParameter('port4_height');
        controller.evaluateMorph(50.0);

        expect(controller.currentPreview, isNotNull);
        final preview = controller.currentPreview!;
        expect(preview.isValid, isTrue);

        final ports = preview.derivedPorts;
        final port4 = ports.firstWhere((p) => p.index == 4);
        final port1 = ports.firstWhere((p) => p.index == 1);
        expect(port4.height, equals(50.0));
        expect(port1.height, equals(100.0));
      });
    });

    test('Opening DSF with stale port metadata auto-synchronizes port visualization from folded 3D mesh', () {
      // Create a document with 150mm scaled geometry, but intentionally inject stale 98mm ports in metadata
      final controller = CmsScalingController(
        baselineDocument: baselineDoc,
        contract: CmsProductContract.bend45,
        baselinePorts: baselinePorts,
      );
      controller.selectParameter('width');
      controller.evaluateMorph(150.0);
      final preview = controller.currentPreview!;

      // Simulate a document saved with the previous bug (geometry is 150mm, but cmsTemplate['ports'] has baseline 98mm)
      final buggyMeta = Map<String, dynamic>.from(preview.scaledDocument.metadata);
      final buggyCms = Map<String, dynamic>.from(buggyMeta['cmsTemplate'] as Map? ?? {});
      buggyCms['ports'] = baselinePorts.map((p) => p.toJson()).toList(); // stale 98mm
      buggyMeta['cmsTemplate'] = buggyCms;
      final buggyDoc = preview.scaledDocument.copyWith(metadata: buggyMeta);

      // Load into ViewModel
      final vm = SheetMetalStudioViewModel(initialDocument: buggyDoc);

      // _recomputeMesh auto-syncs from folded 3D mesh
      expect(vm.verifiedCmsPorts, isNotEmpty);
      expect(vm.activeCmsPorts, isNotEmpty);
      expect(vm.activeCmsPorts.first.width, greaterThan(140.0));
      expect(vm.activeCmsPorts.last.width, greaterThan(140.0));
    });

    test('Test W — Equal Tee straightforward width and height scaling scales all 3 ports uniformly', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final teeDoc = DsfDocument.fromJson(json);

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);

      final controller = CmsScalingController(
        baselineDocument: teeDoc,
        contract: CmsProductContract.equalTee,
        baselinePorts: [p1, p2, p3],
      );

      expect(controller.effectiveScalingProfile, equals(CmsScalingProfile.equalTee));
      expect(controller.isMultiPortFitting, isTrue);
      expect(controller.isLinkedPorts, isTrue);

      // Scale unified width from 100 to 150mm
      controller.selectParameter('width');
      controller.evaluateMorph(150.0);

      final previewW = controller.currentPreview!;
      expect(previewW.isValid, isTrue);
      for (final port in previewW.derivedPorts) {
        expect(port.width, closeTo(150.0, 5.0));
      }

      // Scale unified height from 100 to 125mm
      controller.selectParameter('height');
      controller.evaluateMorph(125.0);

      final previewH = controller.currentPreview!;
      expect(previewH.isValid, isTrue);
      for (final port in previewH.derivedPorts) {
        expect(port.height, closeTo(125.0, 5.0));
      }
    });

    test('Test X — Equal Cross straightforward 4-way width and height scaling scales all 4 ports uniformly', () {
      final crossFile = File('assets/dxf_templates/trunking_accessories/equal_cross_100x100.dsf');
      final json = jsonDecode(crossFile.readAsStringSync()) as Map<String, dynamic>;
      final crossDoc = DsfDocument.fromJson(json);

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);
      final p4 = const CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0);

      final controller = CmsScalingController(
        baselineDocument: crossDoc,
        contract: CmsProductContract.equalCross,
        baselinePorts: [p1, p2, p3, p4],
      );

      expect(controller.effectiveScalingProfile, equals(CmsScalingProfile.equalCross));
      expect(controller.isMultiPortFitting, isTrue);
      expect(controller.isLinkedPorts, isTrue);

      // Scale width from 100 to 140mm
      controller.selectParameter('width');
      controller.evaluateMorph(140.0);

      final preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      for (final port in preview.derivedPorts) {
        expect(port.width, closeTo(140.0, 5.0));
      }
    });

    test('Test Y — Product profile resolution distinguishes equal and unequal contracts', () {
      expect(CmsProductContract.equalTee.scalingProfile, equals(CmsScalingProfile.equalTee));
      expect(CmsProductContract.unequalTee.scalingProfile, equals(CmsScalingProfile.unequalTee));
      expect(CmsProductContract.equalCross.scalingProfile, equals(CmsScalingProfile.equalCross));
      expect(CmsProductContract.unequalCross.scalingProfile, equals(CmsScalingProfile.unequalCross));

      expect(CmsProductContract.lookup('tee', 'equal_tee'), equals(CmsProductContract.equalTee));
      expect(CmsProductContract.lookup('tee', 'unequal_tee'), equals(CmsProductContract.unequalTee));
      expect(CmsProductContract.lookup('cross', 'equal_cross'), equals(CmsProductContract.equalCross));
      expect(CmsProductContract.lookup('cross', 'unequal_cross'), equals(CmsProductContract.unequalCross));
    });

    test('Test Z1 — Equal Cross Width Scaling preserves all 16 corner fillet arcs and moves vertices synchronously (Resolving SS2 & SS3)', () {
      final crossFile = File('assets/dxf_templates/trunking_accessories/equal_cross_100x100.dsf');
      final json = jsonDecode(crossFile.readAsStringSync()) as Map<String, dynamic>;
      final crossDoc = DsfDocument.fromJson(json);

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);
      final p4 = const CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0);

      final controller = CmsScalingController(
        baselineDocument: crossDoc,
        contract: CmsProductContract.equalCross,
        baselinePorts: [p1, p2, p3, p4],
      );

      // Scale width from 100mm to 200mm (SS3 scenario)
      controller.selectParameter('width');
      controller.evaluateMorph(200.0);

      final preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      final scaledDoc = preview.scaledDocument;

      // 1. All 16 corner fillet arcs MUST be preserved
      expect(scaledDoc.arcs.length, equals(16));
      for (final arc in scaledDoc.arcs) {
        expect(arc.radius, closeTo(10.0, 1e-4));
        // Every arc start and end point must coincide with an outer contour vertex
        final hasMatchingStart = scaledDoc.outerContour.any((v) => v.distanceTo(arc.startPoint) < 0.1);
        final hasMatchingEnd = scaledDoc.outerContour.any((v) => v.distanceTo(arc.endPoint) < 0.1);
        expect(hasMatchingStart, isTrue, reason: 'Arc ${arc.id} startPoint must coincide with outer contour');
        expect(hasMatchingEnd, isTrue, reason: 'Arc ${arc.id} endPoint must coincide with outer contour');
      }

      // 2. Arc centers MUST move with the scale (no stale coordinates at baseline)
      for (int i = 0; i < 16; i++) {
        final baselineArc = crossDoc.arcs[i];
        final scaledArc = scaledDoc.arcs[i];
        expect(scaledArc.center.distanceTo(baselineArc.center), greaterThan(10.0),
            reason: 'Arc ${scaledArc.id} must move with width scale, not stay at baseline');
      }
    });

    test('Test Z2 — Equal Cross Height Scaling expands cheeks at 45 degrees without shear distortion (Resolving SS4)', () {
      final crossFile = File('assets/dxf_templates/trunking_accessories/equal_cross_100x100.dsf');
      final json = jsonDecode(crossFile.readAsStringSync()) as Map<String, dynamic>;
      final crossDoc = DsfDocument.fromJson(json);

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);
      final p4 = const CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0);

      final controller = CmsScalingController(
        baselineDocument: crossDoc,
        contract: CmsProductContract.equalCross,
        baselinePorts: [p1, p2, p3, p4],
      );

      // Scale height from 100mm to 150mm (SS4 scenario)
      controller.selectParameter('height');
      controller.evaluateMorph(150.0);

      final preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      final scaledDoc = preview.scaledDocument;

      // 1. All 16 bends preserved with exact fold angles
      expect(scaledDoc.bends.length, equals(16));
      final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
      expect(b1.p1.distanceTo(b1.p2), closeTo(40.0, 0.1)); // Corner bend stays 40mm

      final fl2 = scaledDoc.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl2.p1.distanceTo(fl2.p2), closeTo(40.0, 0.1)); // Flange bend stays 40mm

      // Cheek length along 45° angle grew by 50mm
      final b5 = scaledDoc.bends.firstWhere((b) => b.id == 'B5');
      final baselineB5 = crossDoc.bends.firstWhere((b) => b.id == 'B5');
      expect(b5.p1.distanceTo(b5.p2) - baselineB5.p1.distanceTo(baselineB5.p2), closeTo(50.0, 0.1));

      // 2. 3D folded mesh is valid with standing side walls and clean ports
      expect(preview.foldedMesh.polygons.isNotEmpty, isTrue);
      for (final port in preview.derivedPorts) {
        expect(port.height, closeTo(150.0, 5.0));
      }
    });

    test('Test Z3 — Equal Cross Coupler Holes Universal 95mm Rule (1 slot < 95mm, 2 slots >= 95mm centered)', () {
      final crossFile = File('assets/dxf_templates/trunking_accessories/equal_cross_100x100.dsf');
      final json = jsonDecode(crossFile.readAsStringSync()) as Map<String, dynamic>;
      final crossDoc = DsfDocument.fromJson(json);

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);
      final p4 = const CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0);

      final controller = CmsScalingController(
        baselineDocument: crossDoc,
        contract: CmsProductContract.equalCross,
        baselinePorts: [p1, p2, p3, p4],
      );

      // Case A: Height < 95mm (75mm) -> Exactly 1 slot per flap = 8 slots total
      controller.selectParameter('height');
      controller.evaluateMorph(75.0);

      var preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      var scaledDoc = preview.scaledDocument;
      expect(scaledDoc.punches.length, equals(8));

      // Case B: Height >= 95mm (150mm) -> Exactly 2 slots per flap = 16 slots total at 50mm pitch
      controller.evaluateMorph(150.0);
      preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      scaledDoc = preview.scaledDocument;
      expect(scaledDoc.punches.length, equals(16));

      // Verify pitch between pair on flap 1 (SLOT_1 and SLOT_2)
      final slot1 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_1');
      final slot2 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_2');
      expect(slot1.center.distanceTo(slot2.center), closeTo(50.0, 0.1));

      // Verify pitch between pair on flap 3 (SLOT_5 and SLOT_6)
      final slot5 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_5');
      final slot6 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_6');
      expect(slot5.center.distanceTo(slot6.center), closeTo(50.0, 0.1));

      // Case C: Scale back down to 50mm (< 95mm) -> Returns to 1 slot per flap = 8 slots total
      controller.evaluateMorph(50.0);
      preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      scaledDoc = preview.scaledDocument;
      expect(scaledDoc.punches.length, equals(8));
    });

    test('Test Z4 — Equal Tee preserves all 12 fillet arcs (r=10mm) and vertices without orphan anchoring dots (Resolving SS1, SS2, SS3)', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final teeDoc = DsfDocument.fromJson(json);

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);

      final controller = CmsScalingController(
        baselineDocument: teeDoc,
        contract: CmsProductContract.equalTee,
        baselinePorts: [p1, p2, p3],
      );

      controller.selectParameter('width');
      controller.evaluateMorph(200.0);

      final preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      final scaledDoc = preview.scaledDocument;

      // 1. All 12 corner fillet arcs MUST be preserved
      expect(scaledDoc.arcs.length, equals(12));
      for (final arc in scaledDoc.arcs) {
        expect(arc.radius, closeTo(10.0, 1e-4));
        // Every arc start and end point must coincide with an outer contour vertex
        final hasMatchingStart = scaledDoc.outerContour.any((v) => v.distanceTo(arc.startPoint) < 0.1);
        final hasMatchingEnd = scaledDoc.outerContour.any((v) => v.distanceTo(arc.endPoint) < 0.1);
        expect(hasMatchingStart, isTrue, reason: 'Arc ${arc.id} startPoint must coincide with outer contour');
        expect(hasMatchingEnd, isTrue, reason: 'Arc ${arc.id} endPoint must coincide with outer contour');
      }

      // 2. Arc centers MUST move with the scale (no stale coordinates at baseline)
      for (int i = 0; i < 12; i++) {
        final baselineArc = teeDoc.arcs[i];
        final scaledArc = scaledDoc.arcs[i];
        expect(scaledArc.center.distanceTo(baselineArc.center), greaterThan(10.0),
            reason: 'Arc ${scaledArc.id} must move with width scale, not stay at baseline');
      }
    });

    test('Test Z5 — Equal Tee Height Scaling expands cheeks at 45 degrees and bottom sidewall vertically without distortion (Resolving SS4)', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final teeDoc = DsfDocument.fromJson(json);

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);

      final controller = CmsScalingController(
        baselineDocument: teeDoc,
        contract: CmsProductContract.equalTee,
        baselinePorts: [p1, p2, p3],
      );

      // Scale height from 100mm to 150mm
      controller.selectParameter('height');
      controller.evaluateMorph(150.0);

      final preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      final scaledDoc = preview.scaledDocument;

      // 1. All 10 bends preserved with exact fold geometry
      expect(scaledDoc.bends.length, equals(10));
      final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
      expect(b1.p1.distanceTo(b1.p2), closeTo(40.0, 0.1)); // Corner base bend stays 40mm

      final fl2 = scaledDoc.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl2.p1.distanceTo(fl2.p2), closeTo(40.0, 0.1)); // Flange bend stays 40mm

      // Cheek length along 45° angle grew by 50mm
      final b5 = scaledDoc.bends.firstWhere((b) => b.id == 'B5');
      final baselineB5 = teeDoc.bends.firstWhere((b) => b.id == 'B5');
      expect(b5.p1.distanceTo(b5.p2) - baselineB5.p1.distanceTo(baselineB5.p2), closeTo(50.0, 0.1));

      // Sidewall distance between B3 and FL1 grew by 50mm
      final b3 = scaledDoc.bends.firstWhere((b) => b.id == 'B3');
      final fl1 = scaledDoc.bends.firstWhere((b) => b.id == 'FL1');
      expect((fl1.p1.y - b3.p1.y) - 97.0, closeTo(50.0, 0.1));

      // 2. 3D folded mesh is valid with standing side walls and clean ports
      expect(preview.foldedMesh.polygons.isNotEmpty, isTrue);
      for (final port in preview.derivedPorts) {
        expect(port.height, closeTo(150.0, 5.0));
      }
    });

    test('Test Z6 — Equal Tee Coupler Holes Universal 95mm Rule (1 slot < 95mm, 2 slots >= 95mm centered)', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final teeDoc = DsfDocument.fromJson(json);

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);

      final controller = CmsScalingController(
        baselineDocument: teeDoc,
        contract: CmsProductContract.equalTee,
        baselinePorts: [p1, p2, p3],
      );

      // Case A: Height < 95mm (75mm) -> Exactly 1 slot per region = 6 slots total
      controller.selectParameter('height');
      controller.evaluateMorph(75.0);

      var preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      var scaledDoc = preview.scaledDocument;
      expect(scaledDoc.punches.length, equals(6));

      // Case B: Height >= 95mm (150mm) -> Exactly 2 slots per region = 12 slots total at 50mm pitch
      controller.evaluateMorph(150.0);
      preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      scaledDoc = preview.scaledDocument;
      expect(scaledDoc.punches.length, equals(12));

      // Verify pitch on Left Cheek Port 1 flap (SLOT_9 and SLOT_10)
      final slot9 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_9');
      final slot10 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_10');
      expect(slot9.center.distanceTo(slot10.center), closeTo(50.0, 0.1));

      // Verify pitch on Bottom Sidewall Port 3 side (SLOT_8 and SLOT_7)
      final slot8 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_8');
      final slot7 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_7');
      expect(slot8.center.distanceTo(slot7.center), closeTo(50.0, 0.1));

      // Case C: Scale back down to 50mm (< 95mm) -> Returns to 1 slot per region = 6 slots total
      controller.evaluateMorph(50.0);
      preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      scaledDoc = preview.scaledDocument;
      expect(scaledDoc.punches.length, equals(6));
    });
  });
}
