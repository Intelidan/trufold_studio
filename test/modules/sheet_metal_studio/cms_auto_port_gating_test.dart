import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_ux_state.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('CMS Auto Port Gating Architecture', () {
    late DsfDocument zToolDoc;
    late DsfDocument riserDoc;
    late DsfDocument bendDoc;

    setUp(() {
      final zToolFile = File('assets/dxf_templates/trunking_accessories/Z tool.dsf');
      zToolDoc = DsfDocument.fromJson(jsonDecode(zToolFile.readAsStringSync()) as Map<String, dynamic>);

      final riserFile = File('assets/dxf_templates/trunking_accessories/45_deg_inside_riser_100x100.dsf');
      riserDoc = DsfDocument.fromJson(jsonDecode(riserFile.readAsStringSync()) as Map<String, dynamic>);

      final bendFile = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      bendDoc = DsfDocument.fromJson(jsonDecode(bendFile.readAsStringSync()) as Map<String, dynamic>);
    });

    group('1. DsfDocument.isCmsDrawing Classification', () {
      test('Identifies CMS templates with cmsTemplate/fittingMetadata as CMS drawings', () {
        expect(riserDoc.isCmsDrawing, isTrue);
        expect(bendDoc.isCmsDrawing, isTrue);
      });

      test('Identifies non-CMS parts (Z tool, brackets, blanks) as non-CMS drawings', () {
        expect(zToolDoc.isCmsDrawing, isFalse);

        final genericBracket = DsfDocument(
          productType: 'Sheet Metal Part',
          itemName: 'mounting_bracket_45.dsf',
          outerContour: [
            CadPoint2D(0, 0),
            CadPoint2D(100, 0),
            CadPoint2D(100, 100),
            CadPoint2D(0, 100),
          ],
          bends: const [],
        );
        expect(genericBracket.isCmsDrawing, isFalse);

        final genericPanel = DsfDocument(
          productType: 'Enclosure Panel',
          itemName: 'panel_90.dsf',
          outerContour: [
            CadPoint2D(0, 0),
            CadPoint2D(200, 0),
            CadPoint2D(200, 200),
            CadPoint2D(0, 200),
          ],
          bends: const [],
        );
        expect(genericPanel.isCmsDrawing, isFalse);
      });

      test('CmsProductContract.lookup does not falsely match arbitrary filenames containing 45 or 90', () {
        expect(CmsProductContract.lookup(null, 'bracket_45.dsf'), isNull);
        expect(CmsProductContract.lookup(null, 'mounting_plate_90.dsf'), isNull);
        expect(CmsProductContract.lookup('Sheet Metal Part', 'chassis_45.dxf'), isNull);

        // Legitimate CMS bends still match
        expect(CmsProductContract.lookup(null, '45_deg_bend.dsf'), isNotNull);
        expect(CmsProductContract.lookup(null, '90_deg_bend.dsf'), isNotNull);
        expect(CmsProductContract.lookup('Tray Accessories', '45_bend'), isNotNull);
      });
    });

    group('2. ViewModel Auto Port Gating on Non-CMS Drawings', () {
      test('Non-CMS drawing (Z tool) does not enter CMS Stage 1 or activate guided controller', () {
        final vm = SheetMetalStudioViewModel(initialDocument: zToolDoc);

        expect(vm.isCmsDrawing, isFalse);
        expect(vm.cmsGuidedController.state.phase, equals(CmsUxPhase.idle));
        expect(vm.cmsGuidedController.state.isActive, isFalse);
        expect(vm.verifiedCmsPorts, isEmpty);
      });

      test('continueCmsPortMapping is a no-op on non-CMS drawings', () async {
        final vm = SheetMetalStudioViewModel(initialDocument: zToolDoc);

        await vm.continueCmsPortMapping();

        expect(vm.verifiedCmsPorts, isEmpty);
        expect(vm.cmsGuidedController.state.phase, equals(CmsUxPhase.idle));
      });

      test('autoDetectAndAssignAllPorts is a no-op on non-CMS drawings', () {
        final vm = SheetMetalStudioViewModel(initialDocument: zToolDoc);

        vm.autoDetectAndAssignAllPorts();

        expect(vm.cmsGuidedController.state.phase, equals(CmsUxPhase.idle));
      });

      test('prepareDocumentForSave does not inject cmsWorkflow into non-CMS drawings', () {
        final vm = SheetMetalStudioViewModel(initialDocument: zToolDoc);

        final saved = vm.prepareDocumentForSave();

        expect(saved.metadata.containsKey('cmsWorkflow'), isFalse);
      });
    });

    group('3. Auto Port Execution for Legitimate CMS Drawings', () {
      test('CMS drawing with bends executes continueCmsPortMapping and discovers ports', () async {
        // Strip ports and workflow to simulate Stage 1
        final meta = Map<String, dynamic>.from(bendDoc.metadata);
        meta.remove('cmsWorkflow');
        if (meta['cmsTemplate'] is Map) {
          final t = Map<String, dynamic>.from(meta['cmsTemplate'] as Map);
          t.remove('ports');
          meta['cmsTemplate'] = t;
        }

        final stage1CmsDoc = bendDoc.copyWith(metadata: meta);
        expect(stage1CmsDoc.isCmsDrawing, isTrue);

        final vm = SheetMetalStudioViewModel(initialDocument: stage1CmsDoc);
        expect(vm.isCmsDrawing, isTrue);

        await vm.continueCmsPortMapping();

        expect(vm.verifiedCmsPorts.length, equals(2));
        expect(vm.cmsGuidedController.state.workflowStageIndex, equals(2));
      });

      test('loadDsf with non-CMS DSF leaves controller idle; with CMS DSF initiates mapping', () async {
        final vm = SheetMetalStudioViewModel();

        // 1. Load non-CMS DSF
        await vm.loadDsf(zToolDoc.toJsonString());
        expect(vm.isCmsDrawing, isFalse);
        expect(vm.cmsGuidedController.state.phase, equals(CmsUxPhase.idle));
        expect(vm.verifiedCmsPorts, isEmpty);

        // 2. Load CMS DSF
        final meta = Map<String, dynamic>.from(bendDoc.metadata);
        meta.remove('cmsWorkflow');
        if (meta['cmsTemplate'] is Map) {
          final t = Map<String, dynamic>.from(meta['cmsTemplate'] as Map);
          t.remove('ports');
          meta['cmsTemplate'] = t;
        }
        final stage1CmsDoc = bendDoc.copyWith(metadata: meta);

        await vm.loadDsf(stage1CmsDoc.toJsonString());

        expect(vm.isCmsDrawing, isTrue);
        expect(vm.verifiedCmsPorts.length, equals(2));
        expect(vm.cmsGuidedController.state.workflowStageIndex, equals(2));
      });
    });
  });
}
