import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_annotation.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_product_instance.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_sheet.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dds_template_resolver.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dsf_library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DSF Template Library Service Tests', () {
    test('1. Loads all standard DSF templates synchronously from assets directory', () {
      final items = DsfLibraryService.loadAllTemplatesSync(
        baseDirectory: 'assets/dxf_templates/trunking_accessories',
      );

      expect(items, isNotEmpty);
      expect(items.length, greaterThanOrEqualTo(10));

      for (final item in items) {
        expect(item.templateId, isNotEmpty);
        expect(item.displayName, isNotEmpty);
        expect(item.fileName.endsWith('.dsf'), isTrue);
        expect(item.category, isNotEmpty);
        expect(item.defaultDimensions, isNotEmpty);
        expect(item.document.faces, isNotEmpty);
        expect(item.surfaceAreaMm2, greaterThan(0));

        // Templates with bends should generate a 3D folded mesh
        if (item.document.bends.isNotEmpty) {
          expect(item.foldedMesh, isNotNull);
          expect(item.foldedMesh!.polygons, isNotEmpty);
        }
      }

      // Check specific standard templates are present
      final ids = items.map((i) => i.templateId).toList();
      expect(ids.contains('trunking_reducer'), isTrue);
      expect(ids.contains('trunking_equal_tee'), isTrue);
      expect(ids.contains('trunking_bend_90'), isTrue);
      expect(ids.contains('trunking_inside_riser_90'), isTrue);
    });

    test('2. Adding DSF library item to DdsDocument creates populated sheet and updates TOC', () {
      final items = DsfLibraryService.loadAllTemplatesSync(
        baseDirectory: 'assets/dxf_templates/trunking_accessories',
      );
      final reducerItem = items.firstWhere((i) => i.templateId == 'trunking_reducer');

      var doc = DdsDocument.create(
        documentTitle: 'Submittal Binder 2026',
        documentNumber: 'TDS-SUB-01',
      );

      final newInstance = DdsProductInstance(
        instanceId: 'inst_lib_01',
        productName: reducerItem.displayName,
        productCode: 'RED-100-50',
        orderLine: const DdsOrderLine(
          lineNumber: '001',
          customerItemReference: 'RED-001',
          quantity: 10,
        ),
        templateReference: DdsTemplateResolver.createReference(reducerItem.templateId),
        instanceParameters: {},
        coverConfiguration: const DdsCoverConfig(included: true),
        material: reducerItem.document.material.materialGrade,
        finish: reducerItem.document.material.finish.name,
      );

      doc = doc.addProductInstance(newInstance, sheetTitle: reducerItem.displayName);

      expect(doc.productInstances.length, 1);
      expect(doc.sheets.length, 2); // Cover page + Product sheet
      expect(doc.coverScheduleSheet.tableOfContents.length, 1);
      expect(doc.coverScheduleSheet.tableOfContents.first.productName, reducerItem.displayName);
      expect(doc.coverScheduleSheet.tableOfContents.first.customerRef, 'RED-001');
      expect(doc.coverScheduleSheet.tableOfContents.first.quantity, 10);
    });
  });

  group('Interactive Annotations & Markups Tests', () {
    test('3. Serializes all 5 annotation types round-trip (toJson -> fromJson)', () {
      final dim = DdsLinearDimensionAnnotation(
        id: 'dim_01',
        p1: const CadPoint2D(10, 20),
        p2: const CadPoint2D(110, 20),
        prefix: 'W = ',
        suffix: ' mm',
        offsetDistance: 15.0,
      );

      final leader = const DdsLeaderNoteAnnotation(
        id: 'lead_01',
        targetPoint: CadPoint2D(50, 50),
        textPosition: CadPoint2D(80, 80),
        text: 'Coupler Flap (4x M6 Slots)',
      );

      final note = const DdsNoteBoxAnnotation(
        id: 'note_01',
        x: 20,
        y: 150,
        width: 80,
        height: 30,
        text: 'NOTE: Pre-galvanized mild steel Z275.',
      );

      final cloud = const DdsRevisionCloudAnnotation(
        id: 'cloud_01',
        points: [CadPoint2D(10, 10), CadPoint2D(50, 10), CadPoint2D(50, 40), CadPoint2D(10, 40)],
        revisionTag: 'Δ1',
      );

      final stamp = const DdsApprovalStampAnnotation(
        id: 'stamp_01',
        x: 180,
        y: 160,
        width: 70,
        height: 25,
        status: 'APPROVED AS NOTED',
        reviewedBy: 'Consultant Engineer',
        reviewDate: '2026-09-26',
      );

      final sheet = DdsSheet(
        sheetId: 'sheet_01',
        sheetType: DdsSheetType.productSheet,
        sheetNumber: 2,
        title: 'Straight Reducer Detail',
        annotations: [dim, leader, note, cloud, stamp],
      );

      final jsonStr = jsonEncode(sheet.toJson());
      final restored = DdsSheet.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

      expect(restored.annotations.length, 5);
      expect(restored.annotations[0], isA<DdsLinearDimensionAnnotation>());
      expect((restored.annotations[0] as DdsLinearDimensionAnnotation).displayText, 'W = 100.0 mm');
      expect(restored.annotations[1], isA<DdsLeaderNoteAnnotation>());
      expect((restored.annotations[1] as DdsLeaderNoteAnnotation).text, 'Coupler Flap (4x M6 Slots)');
      expect(restored.annotations[2], isA<DdsNoteBoxAnnotation>());
      expect((restored.annotations[2] as DdsNoteBoxAnnotation).text, contains('Pre-galvanized'));
      expect(restored.annotations[3], isA<DdsRevisionCloudAnnotation>());
      expect((restored.annotations[3] as DdsRevisionCloudAnnotation).revisionTag, 'Δ1');
      expect(restored.annotations[4], isA<DdsApprovalStampAnnotation>());
      expect((restored.annotations[4] as DdsApprovalStampAnnotation).status, 'APPROVED AS NOTED');
    });
  });
}
