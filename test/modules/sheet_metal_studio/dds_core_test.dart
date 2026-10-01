import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_annotation.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_product_instance.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_sheet.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dds_template_resolver.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dds_instance_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DDS Core Models & Serialization Tests', () {
    test('1. DdsDocument serialization round-trip (toJson -> fromJson)', () {
      final doc = DdsDocument(
        ddsHeader: DdsHeader.fresh(),
        projectInfo: const DdsProjectInfo(
          documentTitle: 'Hospital Cable Management System',
          client: 'Apex Health Corp',
          projectName: 'Phase 2 Expansion',
          documentNumber: 'TDS-2026-0042',
          revision: 'B',
          preparedBy: 'Chief Engineer',
          approvedBy: 'Director QA',
          orderInfo: DdsOrderInfo(
            orderNumber: 'PO-88991',
            sourceType: 'manual',
            totalOrderQuantity: 25,
          ),
        ),
        productInstances: [
          DdsProductInstance(
            instanceId: 'inst_01',
            productName: 'Equal Tee 150x100',
            orderLine: const DdsOrderLine(
              orderNumber: 'PO-88991',
              lineNumber: '001',
              customerItemReference: 'TEE-100-HDG',
              customerDescription: 'Cable Trunking Equal Tee 100x100',
              quantity: 25,
            ),
            templateReference: const DdsTemplateReference(
              templateId: 'trunking_equal_tee',
              baselineFileName: 'equal_tee_100x100.dsf',
            ),
            instanceParameters: {'width': 150.0, 'height': 100.0},
            coverConfiguration: const DdsCoverConfig(
              included: true,
              placementMode3D: 'exploded',
            ),
            material: 'Hot Dip Galvanized',
            finish: 'HDG ISO 1461',
            calculatedTakeoff: const DdsCalculatedTakeoff(
              blankSurfaceAreaM2: 0.45,
              estimatedNetWeightKg: 5.3,
            ),
          ),
        ],
        sheets: [
          DdsSheet(
            sheetId: 'sheet_cover',
            sheetNumber: 1,
            title: 'DOCUMENT INFORMATION & SCHEDULE',
            sheetType: DdsSheetType.coverSchedule,
            viewSettings: const DdsViewSettings(paperSize: 'A4_Landscape'),
            annotations: [
              const DdsNoteBoxAnnotation(
                id: 'note_1',
                x: 50,
                y: 50,
                width: 200,
                height: 40,
                text: 'All dimensions in millimeters unless noted.',
              ),
            ],
          ),
          const DdsSheet(
            sheetId: 'sheet_01',
            sheetNumber: 2,
            productInstanceId: 'inst_01',
            title: 'EQUAL TEE 150x100 (HDG)',
            sheetType: DdsSheetType.productSheet,
          ),
        ],
      );

      final updatedDoc = doc.updateToc();
      expect(updatedDoc.coverScheduleSheet.tableOfContents.length, equals(1));
      expect(updatedDoc.coverScheduleSheet.tableOfContents.first.customerRef, equals('TEE-100-HDG'));
      expect(updatedDoc.coverScheduleSheet.tableOfContents.first.quantity, equals(25));

      final jsonMap = updatedDoc.toJson();
      final roundTrip = DdsDocument.fromJson(jsonMap);

      expect(roundTrip.projectInfo.documentNumber, equals('TDS-2026-0042'));
      expect(roundTrip.projectInfo.client, equals('Apex Health Corp'));
      expect(roundTrip.productInstances.length, equals(1));
      expect(roundTrip.productInstances.first.instanceParameters['width'], equals(150.0));
      expect(roundTrip.productInstances.first.coverConfiguration.included, isTrue);
      expect(roundTrip.sheets.length, equals(2));
      final firstAnnotation = roundTrip.sheets.first.annotations.first;
      expect(firstAnnotation, isA<DdsNoteBoxAnnotation>());
      expect((firstAnnotation as DdsNoteBoxAnnotation).text, contains('millimeters'));
    });
  });

  group('DDS Template Resolver Tests', () {
    test('2. Template resolver matches known filenames and keywords', () {
      final reducerMatch = DdsTemplateResolver.matchByDescription('Cable Trunking Reducer 100 to 50');
      expect(reducerMatch, isNotNull);
      expect(reducerMatch!.templateId, equals('trunking_reducer'));

      final teeMatch = DdsTemplateResolver.matchByDescription('Equal Tee Duct Fitting 100x100');
      expect(teeMatch, isNotNull);
      expect(teeMatch!.templateId, equals('trunking_equal_tee'));

      final riserInsideMatch = DdsTemplateResolver.matchByDescription('90 deg inside riser 100x100');
      expect(riserInsideMatch, isNotNull);
      expect(riserInsideMatch!.templateId, equals('trunking_inside_riser_90'));
    });
  });

  group('DDS Instance Evaluator Tests', () {
    test('3. Evaluates Reducer instance with overrides and cover generation', () {
      final templateFile = File('assets/dsf_templates/trunking_accessories/reducer_100x100x50x50.dsf');
      expect(templateFile.existsSync(), isTrue, reason: 'Reducer template must exist');

      final baseDoc = DsfDocument.fromJson(jsonDecode(templateFile.readAsStringSync()) as Map<String, dynamic>);

      final instance = DdsProductInstance(
        instanceId: 'inst_reducer_01',
        productName: 'Straight Reducer 120x80 to 60x40',
        orderLine: const DdsOrderLine(
          orderNumber: 'ORD-101',
          lineNumber: '1',
          customerItemReference: 'RED-100-50',
          customerDescription: 'Straight Reducer 100x100 to 50x50',
          quantity: 10,
        ),
        templateReference: const DdsTemplateReference(
          templateId: 'trunking_reducer',
          baselineFileName: 'reducer_100x100x50x50.dsf',
        ),
        instanceParameters: {
          'port1_width': 120.0,
          'port1_height': 80.0,
          'port2_width': 60.0,
          'port2_height': 40.0,
        },
        coverConfiguration: const DdsCoverConfig(
          included: true,
          placementMode3D: 'exploded',
        ),
        material: 'Mild Steel',
      );

      final evalResult = DdsInstanceEvaluator.evaluate(
        instance: instance,
        baselineDoc: baseDoc,
      );

      expect(evalResult.scaledBaseDocument, isNotNull);
      expect(evalResult.baseMesh3D.polygons.isNotEmpty, isTrue);
      expect(evalResult.coverData, isNotNull);
      expect(evalResult.coverMesh3D, isNotNull);
      expect(evalResult.combinedMesh3D.polygons.length, greaterThan(evalResult.baseMesh3D.polygons.length));
      expect(evalResult.calculatedTakeoff.blankSurfaceAreaM2, greaterThan(0.0));
      expect(evalResult.calculatedTakeoff.estimatedNetWeightKg, greaterThan(0.0));
    });

    test('4. Blank sheet, annotation styling colors, and 3D lock view settings', () {
      final blankSheet = DdsSheet(
        sheetId: 'sheet_blank_01',
        sheetNumber: 2,
        sheetType: DdsSheetType.blankSheet,
        title: 'Blank Drafting Sheet',
        annotations: [
          DdsNoteBoxAnnotation(
            id: 'note_1',
            x: 10,
            y: 20,
            width: 80,
            height: 40,
            text: 'Fabrication note',
            backgroundColor: '#FFFBEB',
            textColor: '#78350F',
            lineColor: '#D97706',
          ),
          DdsLeaderNoteAnnotation(
            id: 'leader_1',
            targetPoint: CadPoint2D(50, 50),
            textPosition: CadPoint2D(100, 80),
            text: 'Coupler Flap',
            textColor: '#0284C7',
            lineColor: '#0284C7',
          ),
        ],
        viewSettings: const DdsViewSettings(
          is3DModelLocked: true,
          showCover3D: false,
        ),
      );

      expect(blankSheet.isBlankSheet, isTrue);
      expect(blankSheet.isCoverPage, isFalse);

      final json = blankSheet.toJson();
      final restored = DdsSheet.fromJson(json);

      expect(restored.isBlankSheet, isTrue);
      expect(restored.viewSettings.is3DModelLocked, isTrue);
      expect(restored.annotations.length, equals(2));

      final note = restored.annotations[0] as DdsNoteBoxAnnotation;
      expect(note.backgroundColor, equals('#FFFBEB'));
      expect(note.textColor, equals('#78350F'));
      expect(note.lineColor, equals('#D97706'));

      final recolored = note.withColors(backgroundColor: '#FFFFFF', textColor: '#000000');
      expect(recolored.backgroundColor, equals('#FFFFFF'));
      expect(recolored.textColor, equals('#000000'));
      expect(recolored.lineColor, equals('#D97706'));
    });

    test('5. DdsNoteArrow border root attachment, serialization and deletion', () {
      final arrow1 = DdsNoteArrow(
        id: 'arrow_top',
        tip: CadPoint2D(60, 20),
        root: CadPoint2D(60, 30), // Attached to top border
        anchorEntity: 'port_1',
      );
      final arrow2 = DdsNoteArrow(
        id: 'arrow_left',
        tip: CadPoint2D(20, 50),
        root: CadPoint2D(40, 50), // Attached to left border
      );

      final noteBox = DdsNoteBoxAnnotation(
        id: 'note_with_arrows',
        x: 40,
        y: 30,
        width: 60,
        height: 40,
        text: 'Arrow test note',
        arrows: [arrow1, arrow2],
      );

      // Verify arrows list and properties
      expect(noteBox.arrows.length, equals(2));
      expect(noteBox.arrows.first.root?.x, equals(60.0));
      expect(noteBox.arrows.first.root?.y, equals(30.0));
      expect(noteBox.arrows.first.tip.x, equals(60.0));
      expect(noteBox.arrows.first.anchorEntity, equals('port_1'));

      // Serialization round-trip
      final json = noteBox.toJson();
      final roundTrip = DdsNoteBoxAnnotation.fromJson(json);

      expect(roundTrip.arrows.length, equals(2));
      expect(roundTrip.arrows.first.id, equals('arrow_top'));
      expect(roundTrip.arrows.first.root?.x, equals(60.0));
      expect(roundTrip.arrows.first.root?.y, equals(30.0));
      expect(roundTrip.arrows.first.tip.x, equals(60.0));
      expect(roundTrip.arrows.first.anchorEntity, equals('port_1'));
      expect(roundTrip.arrows[1].id, equals('arrow_left'));
      expect(roundTrip.arrows[1].root?.x, equals(40.0));
      expect(roundTrip.arrows[1].anchorEntity, isNull);

      // Test arrow deletion (deleting arrow_top)
      final withoutArrow1 = noteBox.copyWith(
        arrows: noteBox.arrows.where((a) => a.id != 'arrow_top').toList(),
      );
      expect(withoutArrow1.arrows.length, equals(1));
      expect(withoutArrow1.arrows.first.id, equals('arrow_left'));

      // Test deleting all arrows
      final withoutAnyArrows = withoutArrow1.copyWith(
        arrows: withoutArrow1.arrows.where((a) => a.id != 'arrow_left').toList(),
      );
      expect(withoutAnyArrows.arrows, isEmpty);
    });
  });
}
