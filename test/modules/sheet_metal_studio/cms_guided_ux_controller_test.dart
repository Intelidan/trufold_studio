// =============================================================================
// cms_guided_ux_controller_test.dart
//
// Verification tests for CmsGuidedUxController 7-Stage autonomous state machine
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 14, 18-20).
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_ux_state.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_guided_ux_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_mini_parser.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_geometry_recognition_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('CmsGuidedUxController 7-Stage Autonomous State Machine', () {
    test('1. Runs full end-to-end automatic discovery on pre-bent 45_deg_bend_100x100.dsf', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      expect(file.existsSync(), isTrue);

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      final controller = CmsGuidedUxController();
      expect(controller.phase, equals(CmsUxPhase.idle));

      // 1. Start Session
      controller.startSession(contract: CmsProductContract.bend45);
      expect(controller.phase, equals(CmsUxPhase.productSelected));
      expect(controller.milestones.length, equals(1));

      // 2. Run Automatic Discovery Sequence
      await controller.runAutomaticDiscovery(document: doc);

      // Verify final complete state
      expect(controller.phase, equals(CmsUxPhase.complete));
      expect(controller.discoveredPorts.length, equals(2));
      expect(controller.discoveredPorts[0].id, equals('PORT_1'));
      expect(controller.discoveredPorts[1].id, equals('PORT_2'));

      // Verify progressive narrative milestones across all stages
      final titles = controller.milestones.map((m) => m.title).toList();
      expect(titles.any((t) => t.contains('Product Intent Identified')), isTrue);
      expect(titles.any((t) => t.contains('Manufacturing Definition Verified') || t.contains('Bend Structure Verified')), isTrue);
      expect(titles.any((t) => t.contains('3D Channel Folded')), isTrue);
      expect(titles.any((t) => t.contains('3D Openings Located')), isTrue);
      expect(titles.any((t) => t.contains('Matched PORT_1')), isTrue);
      expect(titles.any((t) => t.contains('Matched PORT_2')), isTrue);
      expect(titles.any((t) => t.contains('Coupler Fasteners Protected')), isTrue);
      expect(titles.any((t) => t.contains('Smart Scaling Ready')), isTrue);

      // Verify classified coupler slots
      expect(controller.state.classifiedCouplerPunchIds.length, equals(8));
      expect(controller.state.progress, equals(1.0));
    });

    test('2. SheetMetalStudioViewModel runs startCleanCmsDiscovery end-to-end on DSF', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);
      final cleanDoc = doc.copyWith(metadata: {});

      final vm = SheetMetalStudioViewModel(initialDocument: cleanDoc);
      expect(vm.cmsGuidedController.phase, anyOf(equals(CmsUxPhase.idle), equals(CmsUxPhase.confirmingBends)));

      await vm.startCleanCmsDiscovery(contract: CmsProductContract.bend45);

      expect(vm.cmsGuidedController.phase, equals(CmsUxPhase.complete));
      expect(vm.cmsGuidedController.state.discoveredPorts.length, equals(2));
      expect(vm.cmsGuidedController.state.discoveredPorts[0].id, equals('PORT_1'));
      expect(vm.cmsGuidedController.state.discoveredPorts[1].id, equals('PORT_2'));
    });

    test('3. Raw 45° bend DXF pauses at Stage 2 suggestingBends, and user authorization advances pipeline', () async {
      final dxfFile = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dxf');
      expect(dxfFile.existsSync(), isTrue);

      final parsed = DxfMiniParser.parse(await dxfFile.readAsString());
      final rec = DxfGeometryRecognitionEngine.recognize(parsed);
      final rawDoc = rec.generatedDocument.copyWith(itemName: '45_deg_bend_100x100.dxf');

      // Raw DXF has 0 bends
      expect(rawDoc.bends.isEmpty, isTrue);

      final vm = SheetMetalStudioViewModel(initialDocument: rawDoc);
      expect(vm.cmsGuidedController.phase, equals(CmsUxPhase.idle));

      // 1. Start discovery sequence
      await vm.startCleanCmsDiscovery(contract: CmsProductContract.bend45);

      // 2. HARD GUARD CHECK: State machine MUST pause at suggestingBends (Stage 2)
      // It must NOT fold, must NOT detect 3D ports, and must NOT show an ambiguity prompt!
      expect(vm.cmsGuidedController.phase, equals(CmsUxPhase.suggestingBends));
      expect(vm.cmsGuidedController.state.suggestedBends.isNotEmpty, isTrue);
      expect(vm.cmsGuidedController.state.discoveredPorts.isEmpty, isTrue);

      // 3. User clicks [Use Suggested Bends]
      await vm.applyUserBends();

      // 4. Verification: Pipeline successfully completes through Stages 3..7
      expect(vm.cmsGuidedController.phase, equals(CmsUxPhase.complete));
      expect(vm.cmsGuidedController.state.discoveredPorts.length, equals(2));
      expect(vm.cmsGuidedController.state.discoveredPorts[0].id, equals('PORT_1'));
      expect(vm.cmsGuidedController.state.discoveredPorts[1].id, equals('PORT_2'));
      expect(vm.cmsGuidedController.state.classifiedCouplerPunchIds.length, equals(8));
      expect(vm.cmsGuidedController.state.progress, equals(1.0));
    });
  });
}
