import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_annotation.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_sheet.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_product_instance.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DDS Annotation copyWith & Manipulation Tests', () {
    test('LinearDimension copyWith modifies coordinates and properties', () {
      const dim = DdsLinearDimensionAnnotation(
        id: 'dim_1',
        p1: CadPoint2D(10, 20),
        p2: CadPoint2D(100, 20),
      );

      final moved = dim.copyWith(
        p1: const CadPoint2D(15, 25),
        p2: const CadPoint2D(105, 25),
        textOverride: '90.0 mm REF',
      );

      expect(moved.p1.x, 15);
      expect(moved.p1.y, 25);
      expect(moved.p2.x, 105);
      expect(moved.textOverride, '90.0 mm REF');
    });

    test('LeaderNote copyWith modifies target and text position', () {
      const leader = DdsLeaderNoteAnnotation(
        id: 'lead_1',
        targetPoint: CadPoint2D(50, 50),
        textPosition: CadPoint2D(80, 80),
        text: 'Coupler Flap',
      );

      final moved = leader.copyWith(
        targetPoint: const CadPoint2D(55, 55),
        textPosition: const CadPoint2D(85, 85),
        text: 'Coupler Flap (4x M6)',
      );

      expect(moved.targetPoint.x, 55);
      expect(moved.textPosition.x, 85);
      expect(moved.text, 'Coupler Flap (4x M6)');
    });

    test('NoteBox and ApprovalStamp copyWith modifies x, y, text, and status', () {
      const box = DdsNoteBoxAnnotation(
        id: 'box_1',
        x: 30,
        y: 40,
        width: 100,
        height: 50,
        text: 'Sample Note',
      );

      final movedBox = box.copyWith(
        x: 35,
        y: 45,
        width: 120,
        text: 'Updated Note',
      );

      expect(movedBox.x, 35);
      expect(movedBox.y, 45);
      expect(movedBox.width, 120);
      expect(movedBox.text, 'Updated Note');

      const stamp = DdsApprovalStampAnnotation(
        id: 'stamp_1',
        x: 200,
        y: 150,
        status: 'For Approval',
        reviewedBy: 'John',
      );

      final approved = stamp.copyWith(
        status: 'Approved as Noted',
        reviewedBy: 'Lead Engineer',
      );

      expect(approved.status, 'Approved as Noted');
      expect(approved.reviewedBy, 'Lead Engineer');
    });
  });

  group('DDS Sheet Deletion & Renumbering Tests', () {
    test('Deleting sheet renumbers remaining sheets and updates TOC', () {
      final doc = DdsDocument(
        ddsHeader: DdsHeader.fresh(),
        projectInfo: const DdsProjectInfo(
          documentTitle: 'Hospital Cable Management System',
          client: 'Apex Health Corp',
          documentNumber: 'TDS-2026-001',
        ),
        sheets: const [
          DdsSheet(
            sheetId: 'sheet_01',
            sheetType: DdsSheetType.coverSchedule,
            sheetNumber: 1,
            title: 'Transmittal & Schedule',
          ),
          DdsSheet(
            sheetId: 'sheet_02',
            sheetType: DdsSheetType.productSheet,
            sheetNumber: 2,
            title: 'Straight Reducer 150x100 to 75x50',
            productInstanceId: 'inst_01',
          ),
        ],
        productInstances: const [
          DdsProductInstance(
            instanceId: 'inst_01',
            productName: 'Straight Reducer 150x100 to 75x50',
            templateReference: DdsTemplateReference(
              templateId: 'straight_reducer',
              baselineFileName: 'reducer_150_75.dsf',
            ),
          ),
        ],
      );
      expect(doc.sheets.length, 2);

      // Add a third sheet
      const sheet3 = DdsSheet(
        sheetId: 'sheet_03',
        sheetType: DdsSheetType.productSheet,
        sheetNumber: 3,
        title: '90° Flat Gusset Bend',
        productInstanceId: 'inst_02',
      );
      var threeSheetDoc = doc.copyWith(
        sheets: [...doc.sheets, sheet3],
        productInstances: [
          ...doc.productInstances,
          const DdsProductInstance(
            instanceId: 'inst_02',
            productName: '90° Flat Gusset Bend',
            templateReference: DdsTemplateReference(
              templateId: 'flat_bend_90',
              baselineFileName: 'bend_90.dsf',
            ),
          ),
        ],
      );
      threeSheetDoc = threeSheetDoc.updateToc();
      expect(threeSheetDoc.sheets.length, 3);

      // Delete sheet at index 1 (the middle sheet)
      final updatedSheets = List<DdsSheet>.from(threeSheetDoc.sheets)..removeAt(1);
      final renumbered = <DdsSheet>[];
      for (int i = 0; i < updatedSheets.length; i++) {
        renumbered.add(updatedSheets[i].copyWith(sheetNumber: i + 1));
      }

      var finalDoc = threeSheetDoc.copyWith(sheets: renumbered).updateToc();
      expect(finalDoc.sheets.length, 2);
      expect(finalDoc.sheets[0].sheetNumber, 1);
      expect(finalDoc.sheets[1].sheetNumber, 2);
      expect(finalDoc.sheets[1].title, '90° Flat Gusset Bend');
    });
  });

  group('Dedicated Fitting ViewModel Port Visibility Tests', () {
    test('SheetMetalStudioViewModel toggles CMS port highlights cleanly', () {
      final vm = SheetMetalStudioViewModel(initialDocument: DsfDocument.sampleCableTray());
      expect(vm.showCmsPortHighlights, true);

      vm.showCmsPortHighlights = false;
      expect(vm.showCmsPortHighlights, false);

      vm.showCmsPortHighlights = true;
      expect(vm.showCmsPortHighlights, true);
    });
  });
}
