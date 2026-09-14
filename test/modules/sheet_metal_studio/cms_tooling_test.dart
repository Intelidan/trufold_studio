// =============================================================================
// cms_tooling_test.dart
//
// Tests for Cable Management System (CMS) Specialized Tooling:
// - Tray bed perforation arrays (7x25mm and 9x25mm slots)
// - Side-rail coupler slot pairs for splice plates
// - ViewModel stamping integration
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cnc_turret_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('CMS Tooling Engine Tests', () {
    late DsfDocument trayDoc;

    setUp(() {
      // 100mm width, 50mm height, 1000mm length, 15mm flange
      trayDoc = DsfDocument.sampleCableTray(
        width: 100.0,
        height: 50.0,
        length: 1000.0,
        flange: 15.0,
      );
    });

    test('1. generateTrayPerforationArray creates slots within bed floor boundaries', () {
      final slots = CncTurretEngine.generateTrayPerforationArray(
        doc: trayDoc,
        slotWidth: 7.0,
        slotLength: 25.0,
        rows: 2,
        pitchY: 100.0,
        sideMargin: 20.0,
        endMargin: 50.0,
        rotationDeg: 90.0,
        layer: 'HOLES',
      );

      expect(slots.isNotEmpty, isTrue);
      // For 1000mm length with endMargin=50mm: span is 50mm to 950mm = 900mm / 100mm pitch = 10 y-lines.
      // 10 y-lines * 2 rows = 20 slots.
      expect(slots.length, equals(20));

      // Check base floor X range:
      // In sampleCableTray:
      // left flange = 15, left wall = 50 -> base floor starts at X = 65, width = 100 -> ends at X = 165.
      for (final slot in slots) {
        expect(slot.type, equals(PunchType.obroundSlot));
        expect(slot.widthMm, equals(7.0));
        expect(slot.lengthMm, equals(25.0));
        expect(slot.rotationDeg, equals(90.0));
        expect(slot.layer, equals('HOLES'));

        // Center must be within base floor X range [65, 165]
        expect(slot.center.x, greaterThanOrEqualTo(65.0));
        expect(slot.center.x, lessThanOrEqualTo(165.0));

        // Center must be within Y range [50, 950]
        expect(slot.center.y, greaterThanOrEqualTo(50.0));
        expect(slot.center.y, lessThanOrEqualTo(950.0));
      }
    });

    test(
      '2. generateSideRailCouplerSlots creates coupler pairs on side walls',
      () {
        final couplers = CncTurretEngine.generateSideRailCouplerSlots(
          doc: trayDoc,
          slotWidth: 7.0,
          slotLength: 20.0,
          endOffset: 25.0,
          verticalSpacing: 25.0,
          layer: 'HOLES',
        );

        // There are 2 side walls (left wall and right wall)
        // On each wall, there are 2 ends (startY and endY)
        expect(couplers.isNotEmpty, isTrue);
        expect(couplers.length, greaterThanOrEqualTo(4));

        for (final slot in couplers) {
          expect(slot.type, equals(PunchType.obroundSlot));
          expect(slot.widthMm, equals(7.0));
          expect(slot.lengthMm, equals(20.0));
          expect(slot.layer, equals('HOLES'));
        }
      },
    );

    test('3. ViewModel stamps perforations and updates 3D mesh', () {
      final vm = SheetMetalStudioViewModel(initialDocument: trayDoc);
      expect(vm.document.allPunches.isEmpty, isTrue);

      vm.stampCableTrayPerforations(
        slotWidth: 9.0,
        slotLength: 25.0,
        rows: 3,
        pitchY: 100.0,
      );

      expect(vm.document.allPunches.isNotEmpty, isTrue);
      expect(vm.document.perforationPatterns.isNotEmpty, isTrue);
      expect(vm.document.allPunches.first.widthMm, equals(9.0));
      expect(vm.document.allPunches.first.lengthMm, equals(25.0));

      // Mesh should be recomputed
      expect(vm.currentMesh, isNotNull);

      // Undo should revert punches
      expect(vm.canUndo, isTrue);
      vm.undo();
      expect(vm.document.allPunches.isEmpty, isTrue);

      // Redo should restore punches
      expect(vm.canRedo, isTrue);
      vm.redo();
      expect(vm.document.allPunches.isNotEmpty, isTrue);
    });
  });
}
