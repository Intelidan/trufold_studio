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
        riserDoc = DsfDocument.fromJson(json);

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
        expect(scaledFloorSpan, closeTo(145.55, 0.2));

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

        // 1. Floor web and bends B1, B2, B3 remain fixed in position
        final origB1 = riserDoc.bends.firstWhere((b) => b.id == 'B1');
        final origB2 = riserDoc.bends.firstWhere((b) => b.id == 'B2');
        final origB3 = riserDoc.bends.firstWhere((b) => b.id == 'B3');

        final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
        final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
        final b3 = scaledDoc.bends.firstWhere((b) => b.id == 'B3');

        expect(b1.p1.x, closeTo(origB1.p1.x, 0.1));
        expect(b2.p1.x, closeTo(origB2.p1.x, 0.1));
        expect(b3.p1.y, closeTo(origB3.p1.y, 0.1));

        // 2. Bottom floor flap F_1 grows along Y by delta * sqrt(2) (+50 * sqrt(2) mm)
        final origFloorFace = riserDoc.faces.firstWhere((f) => f.id == 'F_1');
        final scaledFloorFace = scaledDoc.faces.firstWhere((f) => f.id == 'F_1');
        final origFloorY = origFloorFace.vertices.map((v) => v.y).reduce((a, b) => a > b ? a : b) -
            origFloorFace.vertices.map((v) => v.y).reduce((a, b) => a < b ? a : b);
        final scaledFloorY = scaledFloorFace.vertices.map((v) => v.y).reduce((a, b) => a > b ? a : b) -
            scaledFloorFace.vertices.map((v) => v.y).reduce((a, b) => a < b ? a : b);
        expect(scaledFloorY, closeTo(origFloorY + 50.0 * math.sqrt(2), 0.1));

        // 2b. Flap F_1's open edge in 3D maintains constant relative distance to prongs' tip edge
        final baselineMesh = KinematicFoldEngine.foldDocument(riserDoc, foldProgress: 1.0);
        final scaledMesh = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);

        final basePolyF1 = baselineMesh.polygons.firstWhere((p) => p.faceId == 'F_1');
        final scaledPolyF1 = scaledMesh.polygons.firstWhere((p) => p.faceId == 'F_1');
        final baseMaxZ = basePolyF1.vertices.map((v) => v.z).reduce(math.max);
        final scaledMaxZ = scaledPolyF1.vertices.map((v) => v.z).reduce(math.max);
        expect(scaledMaxZ - baseMaxZ, closeTo(50.0, 0.5)); // Flap rises in Z by delta (50mm)

        // 2c. Port 2's glass face does NOT protrude beyond the folded part boundary
        final port1 = preview.derivedPorts.firstWhere((p) => p.id == 'PORT_1');
        final port2 = preview.derivedPorts.firstWhere((p) => p.id == 'PORT_2');
        final meshMaxZ = scaledMesh.polygons.expand((p) => p.vertices).map((v) => v.z).reduce(math.max);
        for (final corner in port2.derivedMouthCorners) {
          expect(corner.z, lessThanOrEqualTo(meshMaxZ + 0.1), reason: 'Port 2 corner must not protrude above part boundary');
        }
        // Top lips are separated in 3D (not stuck together)
        final lip1Y = port1.derivedMouthCorners[1].y;
        final lip2Y = port2.derivedMouthCorners[1].y;
        expect((lip2Y - lip1Y).abs(), greaterThan(40.0));

        // 3. Coupler slots remain undistorted (exact shape, pitch, and rotation)
        for (int i = 0; i < riserDoc.punches.length; i++) {
          final origPunch = riserDoc.punches[i];
          final scaledPunch = scaledDoc.punches[i];
          expect(scaledPunch.widthMm, equals(origPunch.widthMm));
          expect(scaledPunch.lengthMm, equals(origPunch.lengthMm));
          expect(scaledPunch.rotationDeg, equals(origPunch.rotationDeg));
        }

        // 4. Coupler slot pairs preserve exact 50.0 mm pitch and orientation
        final s3 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_3');
        final s4 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_4');
        final distS3S4 = math.sqrt(math.pow(s4.center.x - s3.center.x, 2) + math.pow(s4.center.y - s3.center.y, 2));
        final angleS3S4 = math.atan2(s3.center.y - s4.center.y, s3.center.x - s4.center.x) * 180 / math.pi;
        expect(distS3S4, closeTo(50.0, 0.1));
        expect(angleS3S4, closeTo(45.0, 0.1));

        final s1 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_1');
        final s2 = scaledDoc.punches.firstWhere((p) => p.id == 'SLOT_2');
        final distS1S2 = math.sqrt(math.pow(s2.center.x - s1.center.x, 2) + math.pow(s2.center.y - s1.center.y, 2));
        final angleS1S2 = math.atan2(s2.center.y - s1.center.y, s2.center.x - s1.center.x) * 180 / math.pi;
        expect(distS1S2, closeTo(50.0, 0.1));
        expect(angleS1S2, closeTo(-45.0, 0.1));

        // 5. Normalized kinematic DAG topology: Floor Web F_2 is base anchor
        expect(scaledDoc.baseFaceId, equals('F_2'));
        final scaledF2 = scaledDoc.faces.firstWhere((f) => f.id == 'F_2');
        expect(scaledF2.isBaseAnchor, isTrue);

        // 6. 3D folded mesh: 45° sidewall miter touches 45° bottom flap F_1
        final mesh = preview.foldedMesh;
        final polyF0 = mesh.polygons.firstWhere((p) => p.faceId == 'F_0');
        final polyF1 = mesh.polygons.firstWhere((p) => p.faceId == 'F_1');

        final f0P0 = polyF0.vertices[0];
        final f0P1 = polyF0.vertices[1];
        final f1P3 = polyF1.vertices[3];
        final f1P2 = polyF1.vertices[2];

        // Corner junction touches within sheet thickness clearance (<= 2.5 mm)
        expect(f0P0.distanceTo(f1P3), lessThan(2.5));

        // Both edges rise in 3D at exact 45° (dz / dy ≈ 1.0)
        final f0Slope = (f0P1.z - f0P0.z) / (f0P1.y - f0P0.y);
        final f1Slope = (f1P2.z - f1P3.z) / (f1P2.y - f1P3.y);
        expect(f0Slope, closeTo(1.0, 0.05));
        expect(f1Slope, closeTo(1.0, 0.01));
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

        // Verify B1/B2/B3 Y positions remain fixed
        final b3H = heightPreview.scaledDocument.bends.firstWhere((b) => b.id == 'B3');
        expect(b3H.p1.y, closeTo(128.65, 0.1));

        // Verify floor flap F_1 grows along Y by 192.5 * sqrt(2) mm
        final origFloor = riserDoc.faces.firstWhere((f) => f.id == 'F_1');
        final scaledFloor = heightPreview.scaledDocument.faces.firstWhere((f) => f.id == 'F_1');
        final origYRange = origFloor.vertices.map((v) => v.y).reduce(math.max) - origFloor.vertices.map((v) => v.y).reduce(math.min);
        final scaledYRange = scaledFloor.vertices.map((v) => v.y).reduce(math.max) - scaledFloor.vertices.map((v) => v.y).reduce(math.min);
        expect(scaledYRange, closeTo(origYRange + 192.5 * math.sqrt(2), 0.1));

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
        expect((b2W.p1.x - b1W.p1.x).abs(), closeTo(204.55, 0.2)); // Expanded width (95.55 + 109 = 204.55)
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

        // Height scaling does not stretch Y
        controller.selectParameter('height');
        controller.evaluateMorph(200.0);
        final heightPreview = controller.currentPreview!;
        final b3H = heightPreview.scaledDocument.bends.firstWhere((b) => b.id == 'B3');
        expect(b3H.p1.y, closeTo(128.65, 0.1));
      });

      test('Test I — 3D Folded Model smoothly expands corner arcs into curved boundaries and rims', () {
        // 1. Verify coupler slots in riserDoc
        expect(riserDoc.punches.every((p) => p.role == CncPunchRole.coupler), isTrue);
        expect(riserDoc.arcs.length, equals(8));

        // 2. Fold document into 3D mesh
        final mesh = KinematicFoldEngine.foldDocument(riserDoc, foldProgress: 1.0);
        final polyF0 = mesh.polygons.firstWhere((p) => p.faceId == 'F_0');
        final polyF3 = mesh.polygons.firstWhere((p) => p.faceId == 'F_3');

        // Instead of 15 straight chord vertices, faces are expanded into smooth curves
        expect(polyF0.vertices.length, greaterThan(30));
        expect(polyF3.vertices.length, greaterThan(30));
        expect(polyF0.boundaryLines.length, greaterThan(30));

        // 3. Test after morphing: arcs are preserved and scaled in lockstep
        final controller = CmsScalingController(
          baselineDocument: riserDoc,
          contract: CmsProductContract.bend45,
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
          contract: CmsProductContract.bend45,
          baselinePorts: riserBaselinePorts,
        );

        for (final targetH in [115.0, 130.0, 150.0]) {
          controller.selectParameter('height');
          controller.evaluateMorph(targetH);
          final preview = controller.currentPreview!;
          expect(preview.isValid, isTrue);

          final doc = preview.scaledDocument;
          final f0 = doc.faces.firstWhere((f) => f.id == 'F_0');
          final f3 = doc.faces.firstWhere((f) => f.id == 'F_3');

          for (final a in doc.arcs) {
            // 1. Radius must remain exactly 10.0 mm (no distortion into ellipse)
            expect(a.radius, closeTo(10.0, 0.001));

            // 2. Both arc endpoints must exactly match a vertex in the face (no gap/disconnection)
            final verts = (a.id == 'ARC_BND_3' || a.id == 'ARC_BND_4' || a.id == 'ARC_BND_5' || a.id == 'ARC_BND_6')
                ? f0.vertices
                : f3.vertices;

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

        print('DEBUG: Scaled FL1 y = ${scaledFL1.p1.y}');
        print('DEBUG: Scaled S5 = ${scaledS5.center}');
        print('DEBUG: Scaled S3 = ${scaledS3.center}');
        print('DEBUG: Distance FL1 to S5 = ${(scaledS5.center.y - scaledFL1.p1.y).abs()}');
        print('DEBUG: Distance S5 to S3 = ${scaledS5.center.distanceTo(scaledS3.center)}');

        // Both holes must stay at 50mm from each other
        expect(scaledS5.center.distanceTo(scaledS3.center), closeTo(50.0, 0.5));
        // SLOT_5 must remain at constant 24mm from FL1
        expect((scaledS5.center.y - scaledFL1.p1.y).abs(), closeTo(24.0, 0.5));
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
  });
}
