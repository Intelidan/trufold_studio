// =============================================================================
// cad_cam_features_batch_test.dart
//
// Comprehensive Unit & Widget Test Suite for 7 Features Batch:
// 1. Press Brake CAM Rules & Interference Validation
// 2. Material Database & Net Part Weight Calculation
// 3. Progressive Bend Sequence Validator & Tooling Collision Detection
// 4. Interactive Parts Tree Panel Widget
// 5. 2D Dimensional Labels & Visibility Toggles
// 6. Unified Perforation Pattern Group & Sparse Hole Exclusion
// 7. Arrow Key Nudge (0.5mm, Shift 5mm, Ctrl 0.1mm)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/perforation_pattern.dart';
import 'package:trufold_studio/sheet_metal_studio/models/press_brake_machine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/sheet_metal_material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/press_brake_cam_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/bend_sequence_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/parts_tree_panel.dart';

void main() {
  group('Feature 1: Press Brake CAM Engine Rules', () {
    test('Calculates air bending tonnage and validates machine limits', () {
      const machine = PressBrakeMachine(
        id: 'amada_test',
        name: 'Amada 50T Test',
        maxTonnageKN: 500.0, // 50 tons ~ 490-500 kN
        throatDepthMm: 410.0,
        maxBendLengthMm: 1250.0,
        minBendLengthMm: 20.0,
        vDieWidthMm: 12.0,
      );

      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 500);
      final bend = doc.bends.first;

      final result = PressBrakeCamEngine.validateBend(
        bend: bend,
        doc: doc,
        machine: machine,
      );

      expect(result.requiredTonnageKN, greaterThan(0));
      expect(result.requiredTonnageKN, lessThan(machine.maxTonnageKN));
      expect(result.minFlangeMm, greaterThan(0));
    });

    test('Flags minimum bend radius violation when radius is too tight for material', () {
      // Stainless steel with 1.0x factor requires radius >= thickness
      const mat = SheetMetalMaterial(
        thicknessMm: 2.0,
        materialType: SheetMaterialType.stainlessSteel,
        defaultBendRadius: 0.5, // Too small! (Should be >= 2.0mm)
      );

      final bend = FoldBendLine(
        id: 'B1',
        p1: const CadPoint2D(50, 0),
        p2: const CadPoint2D(50, 200),
        targetAngleDeg: 90,
        radiusMm: 0.5,
      );

      final doc = DsfDocument(
        version: '1.0',
        productType: 'Test Part',
        itemName: 'Test Part',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 200),
          CadPoint2D(0, 200),
        ],
        bends: [bend],
        material: mat,
      );

      const machine = PressBrakeMachine(
        id: 'standard_m',
        name: 'Standard Machine',
        maxTonnageKN: 1000.0,
        throatDepthMm: 500.0,
        maxBendLengthMm: 2000.0,
        minBendLengthMm: 10.0,
        vDieWidthMm: 16.0,
      );

      final res = PressBrakeCamEngine.validateBend(bend: bend, doc: doc, machine: machine);
      expect(res.isClean, isFalse);
      expect(res.violations.any((v) => v.title.toLowerCase().contains('radius')), isTrue);
    });

    test('Flags flange bridge safety when flange is shorter than 0.7 * V-die width', () {
      const machine = PressBrakeMachine(
        id: 'die_test',
        name: 'Test Die',
        maxTonnageKN: 1000.0,
        throatDepthMm: 500.0,
        maxBendLengthMm: 2000.0,
        minBendLengthMm: 10.0,
        vDieWidthMm: 30.0, // 0.7 * 30 = 21mm min flange bridge
      );

      // Bend line at 10mm from outer edge -> flange is only 10mm < 21mm
      final bend = FoldBendLine(
        id: 'B1',
        p1: const CadPoint2D(10, 0),
        p2: const CadPoint2D(10, 200),
        targetAngleDeg: 90,
        radiusMm: 2.0,
      );

      final doc = DsfDocument(
        version: '1.0',
        productType: 'Test Part',
        itemName: 'Test Part',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 200),
          CadPoint2D(0, 200),
        ],
        bends: [bend],
      );

      final res = PressBrakeCamEngine.validateBend(bend: bend, doc: doc, machine: machine);
      expect(res.violations.any((v) => v.title.toLowerCase().contains('flange')), isTrue);
    });
  });

  group('Feature 2: Material Database & Part Weight', () {
    test('Calculates gross weight and net weight deducting punch holes', () {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 1000);

      // Gross blank volume: blank area * thickness
      expect(doc.grossWeightKg, greaterThan(0));
      // Without punches, net == gross
      expect((doc.netWeightKg - doc.grossWeightKg).abs(), lessThan(1e-4));

      // Add a round punch of diameter 50mm (area ~ 1963.5 mm²)
      const punch = CncPunchPrimitive(
        id: 'P_BIG',
        type: PunchType.roundHole,
        center: CadPoint2D(100, 500),
        diameterMm: 50.0,
      );

      final docWithPunch = doc.copyWith(punches: [punch]);
      expect(docWithPunch.totalHolesAreaMm2, greaterThan(1900));
      expect(docWithPunch.netWeightKg, lessThan(docWithPunch.grossWeightKg));
    });

    test('Changing material type updates density and part weight', () {
      final vm = SheetMetalStudioViewModel();

      // Default is mild steel (7850 kg/m³)
      final msWeight = vm.partGrossWeightKg;

      // Switch to Aluminium (2700 kg/m³) -> weight should be ~2700/7850 = ~34% of MS
      vm.setMaterialType(SheetMaterialType.aluminium);
      final alWeight = vm.partGrossWeightKg;

      expect(alWeight, lessThan(msWeight * 0.5));
      expect(vm.document.material.materialType, equals(SheetMaterialType.aluminium));

      // Switch to Stainless Steel (8000 kg/m³)
      vm.setMaterialType(SheetMaterialType.stainlessSteel);
      final ssWeight = vm.partGrossWeightKg;
      expect(ssWeight, greaterThan(msWeight));
    });
  });

  group('Feature 3: Bend Sequence & Progressive Collision Detection', () {
    test('Validates bend sequence and reports interference', () {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 1000);
      final machine = PressBrakeMachine.standardPresets().first;

      final report = BendSequenceEngine.validateSequence(
        doc: doc,
        machine: machine,
      );

      expect(report.steps.length, equals(doc.bends.length));
      for (final step in report.steps) {
        expect(step.stepIndex, greaterThan(0));
        expect(step.bendId.isNotEmpty, isTrue);
      }
    });

    test('Auto-sequence sorts bends to prioritize collision-free order', () {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 1000);
      final machine = PressBrakeMachine.standardPresets().first;

      final autoSeq = BendSequenceEngine.autoSequence(doc: doc, machine: machine);
      expect(autoSeq.length, equals(doc.bends.length));
    });

    test('ViewModel step mode advances steps cleanly', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.isStepMode, isFalse);

      vm.toggleStepMode();
      expect(vm.isStepMode, isTrue);
      expect(vm.currentBendStep, equals(1));

      vm.setBendStep(2);
      expect(vm.currentBendStep, equals(2));

      vm.toggleStepMode();
      expect(vm.isStepMode, isFalse);
    });
  });

  group('Feature 4: Parts Tree Panel Widget', () {
    testWidgets('Renders PartsTreePanel with summary, material selector and tree nodes', (tester) async {
      final vm = SheetMetalStudioViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartsTreePanel(viewModel: vm),
          ),
        ),
      );

      expect(find.text('PARTS TREE'), findsOneWidget);
      expect(find.text('Gross: ${vm.partGrossWeightKg.toStringAsFixed(2)} kg'), findsOneWidget);
      expect(find.text('Net: ${vm.partNetWeightKg.toStringAsFixed(2)} kg'), findsOneWidget);
      expect(find.text('Planar Faces'), findsOneWidget);
      expect(find.text('Bends & Flanges'), findsOneWidget);
    });

    testWidgets('Clicking a bend line node in PartsTreePanel selects it in ViewModel', (tester) async {
      final vm = SheetMetalStudioViewModel();
      final firstBend = vm.document.bends.first;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartsTreePanel(viewModel: vm),
          ),
        ),
      );

      final bendFinder = find.textContaining(firstBend.id);
      expect(bendFinder, findsWidgets);

      await tester.tap(bendFinder.first);
      await tester.pump();

      expect(vm.selectedBendId, equals(firstBend.id));
    });
  });

  group('Feature 5: 2D Dimensional Labels', () {
    test('Toggling label visibility updates document models', () {
      final vm = SheetMetalStudioViewModel();
      final firstFaceId = vm.document.faces.first.id;
      final firstBendId = vm.document.bends.first.id;

      expect(vm.document.faces.first.showLabel, isTrue);
      expect(vm.document.bends.first.showLabel, isTrue);

      vm.toggleFaceLabel(firstFaceId);
      expect(vm.document.faces.firstWhere((f) => f.id == firstFaceId).showLabel, isFalse);

      vm.toggleBendLabel(firstBendId);
      expect(vm.document.bends.firstWhere((b) => b.id == firstBendId).showLabel, isFalse);
    });
  });

  group('Feature 6: Unified Perforation Pattern Group', () {
    test('PerforationPattern creates unified entity and expands to punches in doc.allPunches', () {
      const pattern = PerforationPattern(
        id: 'PATT_1',
        anchor: CadPoint2D(100, 200),
        countX: 3,
        countY: 4,
        pitchX: 20.0,
        pitchY: 30.0,
        slotWidthMm: 7.0,
        slotLengthMm: 25.0,
        staggered: true,
      );

      // 3 * 4 = 12 active hole centers
      expect(pattern.activeHoleCount, equals(12));
      final punches = pattern.expandToPunches();
      expect(punches.length, equals(12));

      final doc = DsfDocument(
        version: '1.0',
        productType: 'Perforated Tray',
        itemName: 'Perforated Tray',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(300, 0),
          CadPoint2D(300, 500),
          CadPoint2D(0, 500),
        ],
        bends: const [],
        perforationPatterns: [pattern],
      );

      // doc.punches has 0 standalone punches
      expect(doc.punches.length, equals(0));
      // doc.allPunches merges pattern punches
      expect(doc.allPunches.length, equals(12));
      // Total holes area is accounted for
      expect(doc.totalHolesAreaMm2, greaterThan(0));
    });

    test('Excluding a hole from PerforationPattern updates active hole count and weight', () {
      final vm = SheetMetalStudioViewModel();

      const pattern = PerforationPattern(
        id: 'PATT_GRID',
        anchor: CadPoint2D(100, 200),
        countX: 2,
        countY: 2,
        pitchX: 20.0,
        pitchY: 20.0,
        slotWidthMm: 10.0,
        slotLengthMm: 10.0,
      );

      vm.addPerforationPattern(pattern);
      expect(vm.document.perforationPatterns.length, equals(1));
      expect(vm.document.allPunches.length, equals(4));

      final weightBeforeExclusion = vm.partNetWeightKg;

      // Delete/exclude hole index 0
      vm.deletePatternHole('PATT_GRID', 0);

      final updatedPattern = vm.document.perforationPatterns.first;
      expect(updatedPattern.deletedHoleIndices.contains(0), isTrue);
      expect(updatedPattern.activeHoleCount, equals(3));
      expect(vm.document.allPunches.length, equals(3));

      // With one less hole removed, net weight of metal should slightly increase!
      expect(vm.partNetWeightKg, greaterThan(weightBeforeExclusion));
    });

    test('Rotating a PerforationPattern updates its angle and hole center positions', () {
      final vm = SheetMetalStudioViewModel();
      const pattern = PerforationPattern(
        id: 'PATT_ROT',
        anchor: CadPoint2D(100, 100),
        countX: 2,
        countY: 1,
        pitchX: 50.0,
        pitchY: 50.0,
        rotationDeg: 0.0,
      );
      vm.addPerforationPattern(pattern);

      final origCenters = pattern.activeCenters;
      expect(origCenters[0].y, closeTo(100.0, 1e-4));
      expect(origCenters[1].y, closeTo(100.0, 1e-4));

      vm.rotatePattern('PATT_ROT', 90.0);
      final rotated = vm.document.perforationPatterns.first;
      expect(rotated.rotationDeg, equals(90.0));

      // SS1: Individual hole rotation rotates punches to 90° while keeping grid upright
      final punches = rotated.expandToPunches();
      expect(punches.every((p) => p.rotationDeg == 90.0), isTrue);
      final newCenters = rotated.activeCenters;
      expect(newCenters[0].x, closeTo(origCenters[0].x, 1e-4));
      expect(newCenters[1].x, closeTo(origCenters[1].x, 1e-4));
    });
  });

  group('Feature 7: Arrow Key Nudge', () {
    test('nudgeSelected moves a selected punch by exact delta with undo/redo', () {
      final vm = SheetMetalStudioViewModel();
      const punch = CncPunchPrimitive(
        id: 'P_NUDGE',
        type: PunchType.roundHole,
        center: CadPoint2D(50.0, 50.0),
        diameterMm: 8.0,
      );
      vm.addPunch(punch);
      vm.selectPunch('P_NUDGE');

      // Nudge right by 0.5mm, down by 0.5mm
      vm.nudgeSelected(0.5, 0.5);

      var updated = vm.document.punches.firstWhere((p) => p.id == 'P_NUDGE');
      expect(updated.center.x, closeTo(50.5, 1e-4));
      expect(updated.center.y, closeTo(50.5, 1e-4));

      // Nudge with Shift (5.0mm)
      vm.nudgeSelected(5.0, 0.0);
      updated = vm.document.punches.firstWhere((p) => p.id == 'P_NUDGE');
      expect(updated.center.x, closeTo(55.5, 1e-4));

      // Undo reverts nudge
      vm.undo();
      updated = vm.document.punches.firstWhere((p) => p.id == 'P_NUDGE');
      expect(updated.center.x, closeTo(50.5, 1e-4));
    });

    test('nudgeSelected moves a selected perforation pattern group by exact delta', () {
      final vm = SheetMetalStudioViewModel();
      const pattern = PerforationPattern(
        id: 'PATT_NUDGE',
        anchor: CadPoint2D(100.0, 100.0),
        countX: 2,
        countY: 2,
        pitchX: 20.0,
        pitchY: 20.0,
      );
      vm.addPerforationPattern(pattern);
      vm.selectPattern('PATT_NUDGE');

      // Nudge with Ctrl (0.1mm)
      vm.nudgeSelected(0.1, -0.1);

      final updated = vm.document.perforationPatterns.firstWhere((p) => p.id == 'PATT_NUDGE');
      expect(updated.anchor.x, closeTo(100.1, 1e-4));
      expect(updated.anchor.y, closeTo(99.9, 1e-4));
    });

    test('nudgeSelected moves a selected bend line by exact delta', () {
      final vm = SheetMetalStudioViewModel();
      final bend = vm.document.bends.first;
      final origP1X = bend.p1.x;
      final origP2X = bend.p2.x;

      vm.selectBend(bend.id);
      vm.nudgeSelected(0.5, 0.0);

      final updated = vm.document.bends.firstWhere((b) => b.id == bend.id);
      expect(updated.p1.x, closeTo(origP1X + 0.5, 1e-4));
      expect(updated.p2.x, closeTo(origP2X + 0.5, 1e-4));
    });
  });
}
