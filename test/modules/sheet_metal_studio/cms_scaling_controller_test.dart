import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_scaling_model.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';

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
    });
  });
}
