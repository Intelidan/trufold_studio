import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_dsf_importer.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_ux_state.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('CMS 3-Stage Workflow Architecture', () {
    late DsfDocument sampleBendDoc;

    setUp(() {
      final dsfFile = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final json = jsonDecode(dsfFile.readAsStringSync()) as Map<String, dynamic>;
      sampleBendDoc = DsfDocument.fromJson(json);
    });

    group('Product Contract Disambiguation', () {
      test('Disambiguates 45 deg inside riser from 45 deg flat bend', () {
        final riser45 = CmsProductContract.lookup(null, '45_deg_inside_riser.dxf');
        expect(riser45, isNotNull);
        expect(riser45!.productType, 'inside_riser');
        expect(riser45.variationName, '45_deg_inside_riser');
        expect(riser45.expectedPortCount, 2);
        expect(riser45.expectedStructuralBends, 3);
        expect(riser45.expectedFlanges, 2);

        final bend45 = CmsProductContract.lookup(null, '45_deg_bend.dxf');
        expect(bend45, isNotNull);
        expect(bend45!.productType, 'bend');
        expect(bend45.variationName, '45_deg_bend');
      });

      test('Disambiguates 90 deg inside riser and outside risers', () {
        final riser90 = CmsProductContract.lookup('Inside Riser', '90 Deg Inside Riser');
        expect(riser90, isNotNull);
        expect(riser90!.variationName, '90_deg_inside_riser');

        final outRiser45 = CmsProductContract.lookup('Outside Riser', '45 Deg Outside Riser');
        expect(outRiser45, isNotNull);
        expect(outRiser45!.variationName, '45_deg_outside_riser');
        expect(outRiser45.expectedStructuralBends, 2);

        final outRiser90 = CmsProductContract.lookup('Outside Riser', '90 Deg Outside Riser');
        expect(outRiser90, isNotNull);
        expect(outRiser90!.variationName, '90_deg_outside_riser');
        expect(outRiser90.expectedStructuralBends, 2);
      });
    });

    group('Stage 1: Manufacturing Definition', () {
      test('Empty blank does not create candidate line spiderwebs', () async {
        final emptyBlank = sampleBendDoc.copyWith(
          itemName: 'unknown_sample_blank.dxf',
          bends: const [],
          faces: const [],
        );

        final vm = SheetMetalStudioViewModel(initialDocument: emptyBlank);
        await vm.startCleanCmsDiscovery(contract: CmsProductContract.insideRiser45);

        // Stage 1 pauses awaiting user definition without spiderweb candidates
        expect(vm.cmsGuidedController.state.phase, CmsUxPhase.suggestingBends);
        expect(vm.cmsGuidedController.state.suggestedBends, isEmpty);
        expect(vm.cmsGuidedController.state.workflowStageIndex, 1);
        expect(vm.cmsGuidedController.state.stageTitle, contains('Define Bends'));
      });

      test('Loading a document with bends but no ports enters Stage 1 ready for Port Mapping', () {
        final stage1Doc = sampleBendDoc.copyWith(
          metadata: {
            'cmsWorkflow': {'stage': 'manufacturing_defined', 'stageIndex': 1},
          },
        );

        final vm = SheetMetalStudioViewModel(initialDocument: stage1Doc);
        expect(vm.cmsGuidedController.state.workflowStageIndex, 1);
        expect(vm.cmsGuidedController.state.phase, CmsUxPhase.confirmingBends);
        expect(vm.verifiedCmsPorts, isEmpty);
      });

      test('Saving a document with bends persists Stage 1 workflow metadata', () {
        final docWithBends = sampleBendDoc.copyWith(
          metadata: {},
        );

        final vm = SheetMetalStudioViewModel(initialDocument: docWithBends);
        final prepared = vm.prepareDocumentForSave();

        expect(prepared.metadata['cmsWorkflow'], isNotNull);
        expect(prepared.metadata['cmsWorkflow']['stage'], 'manufacturing_defined');
        expect(prepared.metadata['cmsWorkflow']['stageIndex'], 1);
      });
    });

    group('Stage 2: Automatic Port Mapping', () {
      test('continueCmsPortMapping folds 3D channel, discovers ports, and saves Stage 2', () async {
        final stage1Doc = sampleBendDoc.copyWith(
          metadata: {},
        );

        final vm = SheetMetalStudioViewModel(initialDocument: stage1Doc);
        expect(vm.verifiedCmsPorts, isEmpty);

        await vm.continueCmsPortMapping();

        // Must have discovered 2 physical ports
        expect(vm.verifiedCmsPorts.length, 2);
        expect(vm.cmsGuidedController.state.workflowStageIndex, 2);

        // Check save persistence
        final prepared = vm.prepareDocumentForSave();
        expect(prepared.metadata['cmsWorkflow']['stage'], 'ports_mapped');
        expect(prepared.metadata['cmsWorkflow']['stageIndex'], 2);
        expect(prepared.metadata['cmsTemplate'], isNotNull);
        expect((prepared.metadata['cmsTemplate']['ports'] as List).length, 2);
      });

      test('Reopening a Stage 2 DSF resumes at Stage 2 ready for Teach Scaling', () {
        final stage2Doc = sampleBendDoc.copyWith(
          metadata: {
            'cmsWorkflow': {'stage': 'ports_mapped', 'stageIndex': 2},
            'cmsTemplate': {
              'productType': 'bend',
              'variation': '45_deg_bend',
              'ports': [
                {'id': 'PORT_1', 'index': 1, 'width': 98.0, 'height': 100.0},
                {'id': 'PORT_2', 'index': 2, 'width': 98.0, 'height': 100.0},
              ],
            },
          },
        );

        final vm = SheetMetalStudioViewModel(initialDocument: stage2Doc);
        expect(vm.verifiedCmsPorts.length, 2);
        expect(vm.cmsGuidedController.state.workflowStageIndex, 2);
        expect(vm.cmsGuidedController.state.stageTitle, contains('Ports Mapped'));
      });

      test('45 deg inside riser discovers 2 ports without ambiguity even if baseFaceId was previously cheek', () async {
        final riserFile = File('assets/dxf_templates/trunking_accessories/45_deg_inside_riser_100x100.dsf');
        final json = jsonDecode(riserFile.readAsStringSync()) as Map<String, dynamic>;
        var riserDoc = DsfDocument.fromJson(json);
        // Simulate previous stale/bad base face assignment to left cheek
        riserDoc = riserDoc.copyWith(baseFaceId: 'F_0');

        final vm = SheetMetalStudioViewModel(initialDocument: riserDoc);
        await vm.continueCmsPortMapping();

        expect(vm.verifiedCmsPorts.length, 2);
        expect(vm.cmsGuidedController.state.hasAmbiguity, isFalse);
        expect(vm.cmsGuidedController.state.workflowStageIndex, 2);

        final p1 = vm.verifiedCmsPorts[0];
        final p2 = vm.verifiedCmsPorts[1];

        expect(p1.id, 'PORT_1');
        expect(p1.normal.y, closeTo(-1.0, 0.1), reason: 'PORT_1 is top mouth pointing in -Y');
        expect(p1.width, closeTo(96.0, 5.0));

        expect(p2.id, 'PORT_2');
        expect(p2.normal.y, closeTo(0.707, 0.1), reason: 'PORT_2 is 45° angled bottom mouth');
        expect(p2.normal.z, closeTo(0.707, 0.1));
        expect(p2.width, closeTo(96.0, 5.0));
      });

      test('45 deg outside riser discovers 2 ports without ambiguity even if baseFaceId was previously cheek', () async {
        final dxfFile = File('assets/dxf_templates/trunking_accessories/45_deg_outside_riser_100x100.dxf');
        expect(dxfFile.existsSync(), isTrue);
        final dxfContent = dxfFile.readAsStringSync();

        var outDoc = DxfDsfImporter.importDxf(
          dxfContent,
          productType: 'outside_riser',
          itemName: '45_deg_outside_riser_100x100',
        );

        final b1 = FoldBendLine(
          id: 'B1',
          p1: const CadPoint2D(106.0, 30.0),
          p2: const CadPoint2D(106.0, 93.65),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.bend,
        );
        final b2 = FoldBendLine(
          id: 'B2',
          p1: const CadPoint2D(203.0, 30.0),
          p2: const CadPoint2D(203.0, 93.65),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.bend,
        );
        final fl1 = FoldBendLine(
          id: 'FL1',
          p1: const CadPoint2D(10.0, 30.0),
          p2: const CadPoint2D(10.0, 123.42),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.flange,
        );
        final fl2 = FoldBendLine(
          id: 'FL2',
          p1: const CadPoint2D(299.0, 30.0),
          p2: const CadPoint2D(299.0, 123.40),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.flange,
        );

        // Simulate user defined bends with stale cheek baseFaceId
        outDoc = outDoc.copyWith(
          bends: [b1, b2, fl1, fl2],
          baseFaceId: 'F_1',
        );

        final vm = SheetMetalStudioViewModel(initialDocument: outDoc);
        await vm.continueCmsPortMapping();

        expect(vm.verifiedCmsPorts.length, 2);
        expect(vm.cmsGuidedController.state.hasAmbiguity, isFalse);
        expect(vm.cmsGuidedController.state.workflowStageIndex, 2);

        final p1 = vm.verifiedCmsPorts[0];
        final p2 = vm.verifiedCmsPorts[1];

        expect(p1.id, 'PORT_1');
        expect(p1.width, closeTo(97.0, 5.0));

        expect(p2.id, 'PORT_2');
        expect(p2.width, closeTo(97.0, 5.0));
      });
    });

    group('Stage 3: Teach Scaling', () {
      test('Transition to Stage 3, accepting scaling model persists Stage 3 metadata', () {
        final stage2Doc = sampleBendDoc.copyWith(
          metadata: {
            'cmsWorkflow': {'stage': 'ports_mapped', 'stageIndex': 2},
            'cmsTemplate': {
              'productType': 'bend',
              'variation': '45_deg_bend',
              'ports': [
                {'id': 'PORT_1', 'index': 1, 'width': 98.0, 'height': 100.0},
                {'id': 'PORT_2', 'index': 2, 'width': 98.0, 'height': 100.0},
              ],
            },
          },
        );

        final vm = SheetMetalStudioViewModel(initialDocument: stage2Doc);
        vm.startTeachScaling();
        expect(vm.isTeachScalingActive, isTrue);

        vm.acceptTeachScaling();
        expect(vm.isTeachScalingActive, isFalse);

        final prepared = vm.prepareDocumentForSave();
        expect(prepared.metadata['cmsWorkflow']['stage'], 'template_complete');
        expect(prepared.metadata['cmsWorkflow']['stageIndex'], 3);
      });
    });
  });
}
