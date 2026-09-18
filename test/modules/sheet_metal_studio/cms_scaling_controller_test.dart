import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_scaling_model.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

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
