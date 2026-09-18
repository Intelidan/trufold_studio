import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_geometry_recognition_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_mini_parser.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/magnetic_snap_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('DXF Obround Slot Arc Suppression Tests', () {
    test('unequal_cross template suppresses slot cap arcs and produces exact slot dimensions', () async {
      final file = File('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dxf');
      expect(file.existsSync(), isTrue, reason: 'Template DXF file must exist');
      final content = await file.readAsString();
      final parsed = DxfMiniParser.parse(content);

      final result = DxfGeometryRecognitionEngine.recognize(parsed);

      final doc = result.generatedDocument;

      // 1. Exactly 12 obround slots recognized
      expect(doc.punches.length, equals(12));
      for (final p in doc.punches) {
        expect(p.isSlot, isTrue);
        expect(p.widthMm, closeTo(8.0, 0.2));
        expect(p.lengthMm, closeTo(20.0, 0.2));
        expect(p.rotationDeg == 45.0 || p.rotationDeg == 135.0, isTrue);
      }

      // 2. All 24 semicircular cap arcs were consumed; doc.arcs should ONLY contain outer boundary fillet arcs (16 arcs)
      expect(doc.arcs.length, equals(16));
      for (final a in doc.arcs) {
        // Fillet arcs have radius 10.0
        expect(a.radius, closeTo(10.0, 0.5));
        expect(a.isBoundary, isTrue);
      }
    });
  });

  group('Shift + Click Multi-Selection Tests', () {
    test('toggleEntitySelection adds and removes entities from selectedEntityIds', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.selectedEntityIds, isEmpty);

      // Toggle first entity on
      vm.toggleEntitySelection('SLOT_1');
      expect(vm.selectedEntityIds, contains('SLOT_1'));
      expect(vm.selectedEntityIds.length, equals(1));

      // Toggle second entity on (Shift+Click)
      vm.toggleEntitySelection('BEND_1');
      expect(vm.selectedEntityIds, containsAll(['SLOT_1', 'BEND_1']));
      expect(vm.selectedEntityIds.length, equals(2));

      // Toggle third entity on
      vm.toggleEntitySelection('CUT_1');
      expect(vm.selectedEntityIds.length, equals(3));

      // Toggle first entity off
      vm.toggleEntitySelection('SLOT_1');
      expect(vm.selectedEntityIds, isNot(contains('SLOT_1')));
      expect(vm.selectedEntityIds, containsAll(['BEND_1', 'CUT_1']));
      expect(vm.selectedEntityIds.length, equals(2));

      // Clear selection
      vm.clearSelection();
      expect(vm.selectedEntityIds, isEmpty);
    });

    test('handleCanvasClick with multiSelect: true adds entities cumulatively without clearing', () {
      final vm = SheetMetalStudioViewModel();
      vm.loadDocument(DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: [
          const CadPoint2D(0, 0),
          const CadPoint2D(300, 0),
          const CadPoint2D(300, 300),
          const CadPoint2D(0, 300),
        ],
        punches: [
          CncPunchPrimitive.round(id: 'PUNCH_1', center: const CadPoint2D(50, 50), diameterMm: 10),
          CncPunchPrimitive.round(id: 'PUNCH_2', center: const CadPoint2D(150, 50), diameterMm: 10),
        ],
        bends: [
          FoldBendLine(
            id: 'BEND_1',
            p1: const CadPoint2D(10, 100),
            p2: const CadPoint2D(200, 100),
            direction: BendDirection.up,
            targetAngleDeg: 90,
            radiusMm: 1.5,
          ),
        ],
        cutLines: [
          CadLineSegment(
            id: 'CUT_1',
            p1: const CadPoint2D(20, 200),
            p2: const CadPoint2D(80, 200),
          ),
        ],
      ));

      vm.setToolMode(StudioToolMode.select);

      // 1. Single click on PUNCH_1 without shift
      vm.handleCanvasClick(const CadPoint2D(50, 50), multiSelect: false);
      expect(vm.selectedPunchId, equals('PUNCH_1'));
      expect(vm.selectedEntityIds, equals({'PUNCH_1'}));

      // 2. Shift + Click on PUNCH_2 adds to selection
      vm.handleCanvasClick(const CadPoint2D(150, 50), multiSelect: true);
      expect(vm.selectedEntityIds, containsAll(['PUNCH_1', 'PUNCH_2']));
      expect(vm.selectedEntityIds.length, equals(2));

      // 3. Shift + Click on BEND_1 adds to selection
      vm.handleCanvasClick(const CadPoint2D(50, 100), multiSelect: true);
      expect(vm.selectedEntityIds, containsAll(['PUNCH_1', 'PUNCH_2', 'BEND_1']));
      expect(vm.selectedEntityIds.length, equals(3));

      // 4. Shift + Click on CUT_1 adds to selection
      vm.handleCanvasClick(const CadPoint2D(50, 200), multiSelect: true);
      expect(vm.selectedEntityIds, containsAll(['PUNCH_1', 'PUNCH_2', 'BEND_1', 'CUT_1']));
      expect(vm.selectedEntityIds.length, equals(4));

      // 5. Shift + Click on empty space does NOT clear selection
      vm.handleCanvasClick(const CadPoint2D(250, 250), multiSelect: true);
      expect(vm.selectedEntityIds.length, equals(4));

      // 6. Shift + Click on PUNCH_1 again toggles it off
      vm.handleCanvasClick(const CadPoint2D(50, 50), multiSelect: true);
      expect(vm.selectedEntityIds, isNot(contains('PUNCH_1')));
      expect(vm.selectedEntityIds, containsAll(['PUNCH_2', 'BEND_1', 'CUT_1']));
      expect(vm.selectedEntityIds.length, equals(3));

      // 7. Regular click on PUNCH_1 without shift replaces entire multi-selection
      vm.handleCanvasClick(const CadPoint2D(50, 50), multiSelect: false);
      expect(vm.selectedPunchId, equals('PUNCH_1'));
      expect(vm.selectedEntityIds, equals({'PUNCH_1'}));

      // 8. Regular click on empty space without shift clears selection
      vm.handleCanvasClick(const CadPoint2D(250, 250), multiSelect: false);
      expect(vm.selectedEntityIds, isEmpty);
    });
  });

  group('Box Drag Selection (MagneticSnapEngine) Tests', () {
    late DsfDocument testDoc;

    setUp(() {
      testDoc = DsfDocument(
        productType: 'Test Product',
        itemName: 'Test Part',
        outerContour: [
          CadPoint2D(0, 0),
          CadPoint2D(200, 0),
          CadPoint2D(200, 200),
          CadPoint2D(0, 200),
        ],
        bends: [
          FoldBendLine(
            id: 'B1',
            p1: CadPoint2D(10, 50),
            p2: CadPoint2D(190, 50),
            direction: BendDirection.up,
            targetAngleDeg: 90,
            radiusMm: 1.5,
          ),
        ],
        cutLines: [
          CadLineSegment(
            id: 'C1',
            p1: CadPoint2D(20, 80),
            p2: CadPoint2D(40, 80),
          ),
        ],
        punches: [
          CncPunchPrimitive.obround(
            id: 'SLOT_A',
            center: CadPoint2D(50, 150),
            widthMm: 8,
            lengthMm: 20,
            rotationDeg: 45,
          ),
          CncPunchPrimitive.round(
            id: 'HOLE_B',
            center: CadPoint2D(150, 150),
            diameterMm: 10,
          ),
        ],
        arcs: [
          CadArc2D(
            id: 'ARC_1',
            center: CadPoint2D(100, 100),
            radius: 15,
            startAngleDeg: 0,
            endAngleDeg: 180,
            startPoint: CadPoint2D(115, 100),
            endPoint: CadPoint2D(85, 100),
            layer: 'CUT',
          ),
        ],
      );
    });

    test('evaluateWindowSelection selects elements strictly contained in cadBox', () {
      // Box enclosing only C1 and ARC_1
      final box = Rect.fromLTRB(15, 70, 120, 120);
      final selected = MagneticSnapEngine.evaluateWindowSelection(
        doc: testDoc,
        cadBox: box,
      );

      expect(selected, contains('C1'));
      expect(selected, contains('ARC_1'));
      expect(selected, isNot(contains('B1'))); // B1 spans 10 to 190, outside x=120
      expect(selected, isNot(contains('SLOT_A'))); // at (50, 150), y outside 120
      expect(selected, isNot(contains('HOLE_B'))); // at (150, 150)
    });

    test('evaluateCrossingSelection selects elements touching or intersecting cadBox', () {
      // Box intersecting B1 and SLOT_A
      final box = Rect.fromLTRB(40, 45, 60, 160);
      final selected = MagneticSnapEngine.evaluateCrossingSelection(
        doc: testDoc,
        cadBox: box,
      );

      expect(selected, contains('B1')); // crosses y=50 between x=40 and 60
      expect(selected, contains('SLOT_A')); // contains center (50, 150)
      expect(selected, isNot(contains('HOLE_B'))); // at (150, 150)
    });
  });
}
