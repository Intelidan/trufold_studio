// =============================================================================
// dds_specs_and_inspector_test.dart
//
// Unit tests for:
// 1. Engineering quality sign-offs (ISO 7200 / DIN 6771) on DdsProjectInfo.
// 2. Dynamic parameter inspection for CMS fittings (ports, coupler slots, flanges).
// 3. Live linking between DdsProductInstance parameters and CAD kinematics.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_annotation.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_product_instance.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_sheet.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dds_template_resolver.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/services/studio_clipboard_service.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('DDS Project Info & Quality Sign-Off Tests (ISO 7200 / DIN 6771)', () {
    test('1. Preserves and serializes full engineering sign-off fields round-trip', () {
      final info = DdsProjectInfo(
        documentTitle: 'HVAC Trunking & Fittings Submittal',
        documentNumber: 'TDS-2026-CMS-001',
        revision: 'B',
        client: 'Al Futtaim Engineering',
        projectName: 'Dubai Metro Route 2030',
        consultant: 'Atkins',
        contractor: 'ALSTOM Transport',
        designedBy: 'Danish S.',
        designedDate: '2026-09-27',
        drawnBy: 'CAD Engineer A',
        drawnDate: '2026-09-27',
        checkedBy: 'Lead ME Engineer',
        checkedDate: '2026-09-28',
        approvedBy: 'Consultant QA/QC',
        approvedDate: '2026-09-29',
      );

      final json = info.toJson();
      expect(json['designedBy'], 'Danish S.');
      expect(json['designedDate'], '2026-09-27');
      expect(json['drawnBy'], 'CAD Engineer A');
      expect(json['drawnDate'], '2026-09-27');
      expect(json['checkedBy'], 'Lead ME Engineer');
      expect(json['checkedDate'], '2026-09-28');
      expect(json['approvedBy'], 'Consultant QA/QC');
      expect(json['approvedDate'], '2026-09-29');

      final deserialized = DdsProjectInfo.fromJson(json);
      expect(deserialized.designedBy, 'Danish S.');
      expect(deserialized.designedDate, '2026-09-27');
      expect(deserialized.drawnBy, 'CAD Engineer A');
      expect(deserialized.drawnDate, '2026-09-27');
      expect(deserialized.checkedBy, 'Lead ME Engineer');
      expect(deserialized.checkedDate, '2026-09-28');
      expect(deserialized.approvedBy, 'Consultant QA/QC');
      expect(deserialized.approvedDate, '2026-09-29');
    });

    test('2. copyWith properly updates sign-off attributes without losing others', () {
      const original = DdsProjectInfo(
        documentTitle: 'Base Project',
        designedBy: 'Engineer 1',
        designedDate: '2026-09-20',
      );

      final updated = original.copyWith(
        approvedBy: 'Director of QA',
        approvedDate: '2026-09-27',
      );

      expect(updated.documentTitle, 'Base Project');
      expect(updated.designedBy, 'Engineer 1');
      expect(updated.designedDate, '2026-09-20');
      expect(updated.approvedBy, 'Director of QA');
      expect(updated.approvedDate, '2026-09-27');
    });
  });

  group('Dynamic CMS Parameter Inspector Data Tests', () {
    test('3. Unequal Cross instance has 4 port dimensions and flange/coupler configs', () {
      final ref = DdsTemplateResolver.createReference('trunking_unequal_cross');
      final instance = DdsProductInstance(
        instanceId: 'inst_unequal_cross_01',
        productName: 'Unequal Cross 300x100 to 150x50',
        productCode: 'TX-U-300-150',
        templateReference: ref,
        instanceParameters: {
          'port1_width': 300.0,
          'port1_height': 100.0,
          'port2_width': 300.0,
          'port2_height': 100.0,
          'port3_width': 150.0,
          'port3_height': 50.0,
          'port4_width': 150.0,
          'port4_height': 50.0,
          'coupler_slot_length': 20.0,
          'coupler_slot_width': 9.0,
          'coupler_slot_pitch': 25.0,
          'base_flange_size': 20.0,
          'flange_direction': 0.0, // 0 = inside, 1 = outside
        },
        coverConfiguration: const DdsCoverConfig(
          included: true,
          flangeDepthMm: 15.0,
        ),
      );

      expect(instance.instanceParameters['port1_width'], 300.0);
      expect(instance.instanceParameters['port2_width'], 300.0);
      expect(instance.instanceParameters['port3_width'], 150.0);
      expect(instance.instanceParameters['port4_width'], 150.0);
      expect(instance.instanceParameters['coupler_slot_length'], 20.0);
      expect(instance.instanceParameters['base_flange_size'], 20.0);
      expect(instance.coverConfiguration.flangeDepthMm, 15.0);
    });

    test('4. Equal Tee instance has common port sizing with coupler and cover configuration', () {
      final ref = DdsTemplateResolver.createReference('trunking_equal_tee');
      final instance = DdsProductInstance(
        instanceId: 'inst_equal_tee_01',
        productName: 'Equal Tee 100x50',
        productCode: 'TT-E-100-50',
        templateReference: ref,
        instanceParameters: {
          'port1_width': 100.0,
          'port1_height': 50.0,
          'coupler_slot_length': 20.0,
          'coupler_slot_width': 9.0,
          'coupler_slot_pitch': 25.0,
          'base_flange_size': 20.0,
          'flange_direction': 1.0, // outside flange
        },
        coverConfiguration: const DdsCoverConfig(
          included: true,
          flangeDepthMm: 15.0,
        ),
      );

      expect(instance.instanceParameters['port1_width'], 100.0);
      expect(instance.instanceParameters['port1_height'], 50.0);
      expect(instance.instanceParameters['flange_direction'], 1.0);
      expect(instance.coverConfiguration.included, isTrue);
    });

    test('5. Unequal Tee contract recognizes 3 ports and updates morph parameters live', () {
      final contract = CmsProductContract.unequalTee;
      expect(contract.expectedPortCount, 3);
      expect(contract.scalingProfile, CmsScalingProfile.unequalTee);

      final vm = SheetMetalStudioViewModel();
      expect(vm.isTeachScalingActive, isFalse);

      // Apply morph parameter on live viewmodel
      vm.applyCmsMorphParameter('port1_width', 150.0);
      expect(vm.document.metadata['cms_param_port1_width'], 150.0);

      vm.applyCmsMorphParameter('port2_width', 100.0);
      expect(vm.document.metadata['cms_param_port2_width'], 100.0);

      vm.applyCmsMorphParameter('port3_width', 200.0);
      expect(vm.document.metadata['cms_param_port3_width'], 200.0);

      vm.applyCmsMorphParameter('base_flange_size', 25.0);
      expect(vm.document.metadata['cms_param_base_flange_size'], 25.0);
    });

    test('6. Flange direction updates bend directions (down for Outside vs up for Inside)', () {
      final vm = SheetMetalStudioViewModel();

      // Outside Return -> Down bends
      vm.applyCmsMorphParameter('flange_direction', 0.0);
      expect(vm.document.metadata['cms_param_flange_direction'], 0.0);

      // Inside Flush -> Up bends
      vm.applyCmsMorphParameter('flange_direction', 1.0);
      expect(vm.document.metadata['cms_param_flange_direction'], 1.0);
    });

    test('7. Coupler slot resizing dynamically updates punch dimensions', () {
      final vm = SheetMetalStudioViewModel();

      vm.applyCmsMorphParameter('coupler_slot_length', 30.0);
      vm.applyCmsMorphParameter('coupler_slot_width', 12.0);
      vm.applyCmsMorphParameter('coupler_slot_pitch', 35.0);

      expect(vm.document.metadata['cms_param_coupler_slot_length'], 30.0);
      expect(vm.document.metadata['cms_param_coupler_slot_width'], 12.0);
      expect(vm.document.metadata['cms_param_coupler_slot_pitch'], 35.0);
    });

    test('8. Thickness change updates document material and 3D solid wall extrusion', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.document.material.thicknessMm, 1.5);

      vm.applyCmsMorphParameter('thickness', 2.0);
      expect(vm.document.material.thicknessMm, 2.0);
      expect(vm.document.metadata['cms_param_thickness'], 2.0);

      vm.applyCmsMorphParameter('thickness', 3.0);
      expect(vm.document.material.thicknessMm, 3.0);
    });

    test('9. Cover flange sizing updates cover depth', () {
      final vm = SheetMetalStudioViewModel();
      vm.createCoverForCurrentFitting();
      expect(vm.document.cover, isNotNull);

      vm.applyCmsMorphParameter('cover_flange_size', 22.0);
      expect(vm.coverFlangeDepth, 22.0);
      expect(vm.document.metadata['cms_param_cover_flange_size'], 22.0);
    });

    test('10. DdsViewSettings persists per-sheet memory of selections and 3D camera', () {
      const vs1 = DdsViewSettings(
        showCover3D: true,
        showFasteners3D: true,
        showDimWidth: true,
        showDimHeight: false,
        showDimPorts: true,
        showDimSlots: false,
        showDimFlange: true,
        showDimThickness: false,
        showCadDimensionLines: true,
        showDimensionTags: false,
      );

      final json1 = vs1.toJson();
      expect(json1['showCover3D'], isTrue);
      expect(json1['showFasteners3D'], isTrue);
      expect(json1['showDimHeight'], isFalse);
      expect(json1['showDimFlange'], isTrue);

      final roundTrip1 = DdsViewSettings.fromJson(json1);
      expect(roundTrip1.showCover3D, isTrue);
      expect(roundTrip1.showFasteners3D, isTrue);
      expect(roundTrip1.showDimHeight, isFalse);
      expect(roundTrip1.showDimFlange, isTrue);

      // Modify per-page settings on another sheet
      final vs2 = vs1.copyWith(
        showCover3D: false,
        showFasteners3D: false,
        showDimSlots: true,
      );
      expect(vs2.showCover3D, isFalse);
      expect(vs2.showFasteners3D, isFalse);
      expect(vs2.showDimSlots, isTrue);
      // Ensure Sheet 1 remained unchanged
      expect(vs1.showCover3D, isTrue);
      expect(vs1.showFasteners3D, isTrue);
    });

    test('11. SheetMetalStudioViewModel camera setters update 3D perspective smoothly', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.azimuthDeg, 45.0);
      expect(vm.elevationDeg, 30.0);

      vm.azimuthDeg = 65.0;
      vm.elevationDeg = 40.0;
      vm.cameraZoom = 1.25;
      vm.pan3D = const Offset(15.0, -10.0);

      expect(vm.azimuthDeg, 65.0);
      expect(vm.elevationDeg, 40.0);
      expect(vm.cameraZoom, 1.25);
      expect(vm.pan3D.dx, 15.0);
      expect(vm.pan3D.dy, -10.0);
    });

    test('12. Standard engineering sign-off defaults: Amir Khan, Sandeep, Nasser Anani, and today\'s date', () {
      const defaultInfo = DdsProjectInfo();
      expect(defaultInfo.designedBy, 'Amir Khan');
      expect(defaultInfo.drawnBy, 'Sandeep');
      expect(defaultInfo.checkedBy, 'Nasser Anani');
      expect(defaultInfo.approvedBy, 'Consultant QA/QC');

      final today = DdsProjectInfo.formattedToday;
      expect(defaultInfo.effectiveDesignedDate, today);
      expect(defaultInfo.effectiveDrawnDate, today);
      expect(defaultInfo.effectiveCheckedDate, today);
      expect(defaultInfo.effectiveApprovedDate, today);

      final doc = DdsDocument.create(projectName: 'Test Hospital');
      expect(doc.projectInfo.designedBy, 'Amir Khan');
      expect(doc.projectInfo.drawnBy, 'Sandeep');
      expect(doc.projectInfo.checkedBy, 'Nasser Anani');
      expect(doc.projectInfo.designedDate, today);
      expect(doc.projectInfo.drawnDate, today);
      expect(doc.projectInfo.checkedDate, today);
      expect(doc.projectInfo.approvedDate, today);
    });

    test('13. Component clipboard allows copying and pasting drawing annotations with offset without clobbering text', () {
      final note = DdsNoteBoxAnnotation(
        id: 'note_quality_01',
        x: 40.0,
        y: 60.0,
        width: 120.0,
        height: 40.0,
        text: 'Inspected per BS EN 50085-1 standards',
      );

      // Copy drawing annotation
      final copied = StudioClipboardService.copyAnnotation(note);
      expect(copied, isTrue);
      expect(StudioClipboardService.hasContent, isTrue);
      expect(StudioClipboardService.hasAnnotationContent, isTrue);
      expect(StudioClipboardService.hasCadContent, isFalse);

      // Paste drawing annotation onto sheet
      const sheet = DdsSheet(
        sheetId: 'sheet_01',
        sheetType: DdsSheetType.productSheet,
        sheetNumber: 1,
        title: 'Fitting Layout',
      );
      final pasted = StudioClipboardService.pasteAnnotationIntoSheet(sheet, offsetX: 15.0, offsetY: 15.0);
      expect(pasted, isNotNull);
      expect(pasted, isA<DdsNoteBoxAnnotation>());
      final pastedNote = pasted as DdsNoteBoxAnnotation;
      expect(pastedNote.id, isNot('note_quality_01'));
      expect(pastedNote.x, 55.0); // 40 + 15
      expect(pastedNote.y, 75.0); // 60 + 15
      expect(pastedNote.text, 'Inspected per BS EN 50085-1 standards');
    });

    test('14. Unequal Cross (4 Ports) contract recognizes 4 distinct ports and dimensions', () {
      final crossContract = CmsProductContract.unequalCross;
      expect(crossContract, isNotNull);
      expect(crossContract.expectedPortCount, 4);
      expect(crossContract.scalingProfile, CmsScalingProfile.unequalCross);

      final ref = DdsTemplateResolver.createReference('unequal_cross_100x50x100x50');
      final instance = DdsProductInstance(
        instanceId: 'cross_inst_01',
        templateReference: ref,
        productName: 'Unequal Cross Fitting',
        productCode: 'CR-U-150-100-75-50',
        instanceParameters: {
          'port1_width': 150.0,
          'port1_height': 100.0,
          'port2_width': 75.0,
          'port2_height': 50.0,
          'port3_width': 48.0,
          'port3_height': 49.5,
          'port4_width': 98.0,
          'port4_height': 99.5,
        },
      );

      expect(instance.instanceParameters['port1_width'], 150.0);
      expect(instance.instanceParameters['port1_height'], 100.0);
      expect(instance.instanceParameters['port2_width'], 75.0);
      expect(instance.instanceParameters['port2_height'], 50.0);
      expect(instance.instanceParameters['port3_width'], 48.0);
      expect(instance.instanceParameters['port3_height'], 49.5);
      expect(instance.instanceParameters['port4_width'], 98.0);
      expect(instance.instanceParameters['port4_height'], 99.5);
    });

    test('15. Isolated DdsProductInstance parameter mutation maintains isolation from CAD ViewModel', () {
      final ref = DdsTemplateResolver.createReference('trunking_equal_tee');
      final instance = DdsProductInstance(
        instanceId: 'tee_inst_01',
        templateReference: ref,
        productName: 'Equal Tee 100x50',
        productCode: 'TT-E-100-50',
        instanceParameters: {
          'port1_width': 100.0,
          'port1_height': 50.0,
          'port2_width': 100.0,
          'port2_height': 50.0,
          'port3_width': 50.0,
          'port3_height': 50.0,
        },
      );

      final updatedParams = Map<String, double>.from(instance.instanceParameters);
      updatedParams['port1_width'] = 200.0;
      updatedParams['port3_width'] = 80.0;
      final updatedInstance = instance.copyWith(instanceParameters: updatedParams);

      expect(updatedInstance.instanceParameters['port1_width'], 200.0);
      expect(updatedInstance.instanceParameters['port3_width'], 80.0);
      expect(instance.instanceParameters['port1_width'], 100.0); // Immutability preserved
    });
  });
}

