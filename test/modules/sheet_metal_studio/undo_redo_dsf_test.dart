import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  test('History undo/redo test for punch move and property changes', () {
    final vm = SheetMetalStudioViewModel();
    final p = CncPunchPrimitive(
      id: 'P_TEST_1',
      type: PunchType.roundHole,
      center: const CadPoint2D(100, 100),
      diameterMm: 10.0,
    );
    vm.addPunch(p);
    expect(vm.undoStackLength, equals(1)); // 1 for add
    expect(vm.selectedPunchId, equals('P_TEST_1'));

    // 1. Property change: update diameter
    final punch = vm.document.punches.firstWhere((x) => x.id == 'P_TEST_1');
    vm.updatePunch(punch.copyWith(diameterMm: 20.0));
    expect(vm.undoStackLength, equals(2));
    expect(vm.document.punches.firstWhere((x) => x.id == 'P_TEST_1').diameterMm, equals(20.0));

    // Undo property change - ensures selection is maintained so property panel displays it
    vm.undo();
    expect(vm.undoStackLength, equals(1));
    expect(vm.document.punches.firstWhere((x) => x.id == 'P_TEST_1').diameterMm, equals(10.0));
    expect(vm.selectedPunchId, equals('P_TEST_1'));

    // Redo property change
    vm.redo();
    expect(vm.undoStackLength, equals(2));
    expect(vm.document.punches.firstWhere((x) => x.id == 'P_TEST_1').diameterMm, equals(20.0));
    expect(vm.selectedPunchId, equals('P_TEST_1'));

    // 2. Drag move
    vm.beginObjectDrag();
    vm.moveSelectedPunch(const CadPoint2D(150, 150));
    vm.endObjectDrag();
    expect(vm.undoStackLength, equals(3));
    expect(vm.document.punches.firstWhere((x) => x.id == 'P_TEST_1').center.x, equals(150.0));

    // Undo drag move
    vm.undo();
    expect(vm.document.punches.firstWhere((x) => x.id == 'P_TEST_1').center.x, equals(100.0));
    expect(vm.selectedPunchId, equals('P_TEST_1'));

    // Redo drag move
    vm.redo();
    expect(vm.document.punches.firstWhere((x) => x.id == 'P_TEST_1').center.x, equals(150.0));
    expect(vm.selectedPunchId, equals('P_TEST_1'));
  });

  test('History undo/redo test for bend property changes and moves', () {
    final vm = SheetMetalStudioViewModel();
    expect(vm.document.bends.isNotEmpty, isTrue);
    final initialBend = vm.document.bends.first;
    final initialAngle = initialBend.targetAngleDeg;

    // 1. Property change: update angle from initialAngle (45.0) to 60.0
    const newAngle = 60.0;
    vm.updateBend(initialBend.copyWith(targetAngleDeg: newAngle));
    expect(vm.undoStackLength, equals(1));
    expect(vm.document.bends.firstWhere((b) => b.id == initialBend.id).targetAngleDeg, equals(newAngle));

    // Undo angle change
    vm.undo();
    expect(vm.document.bends.firstWhere((b) => b.id == initialBend.id).targetAngleDeg, equals(initialAngle));
    expect(vm.selectedBendId, equals(initialBend.id));

    // Redo angle change
    vm.redo();
    expect(vm.document.bends.firstWhere((b) => b.id == initialBend.id).targetAngleDeg, equals(newAngle));
    expect(vm.selectedBendId, equals(initialBend.id));

    // 2. Bend move
    vm.selectBend(initialBend.id);
    vm.beginObjectDrag();
    vm.moveSelectedBend(const CadPoint2D(10, 0));
    vm.endObjectDrag();
    expect(vm.undoStackLength, equals(2));

    // Undo bend move
    vm.undo();
    final undoneBend = vm.document.bends.firstWhere((b) => b.id == initialBend.id);
    expect(undoneBend.p1.x, equals(initialBend.p1.x));
    expect(vm.selectedBendId, equals(initialBend.id));

    // Redo bend move
    vm.redo();
    final redoneBend = vm.document.bends.firstWhere((b) => b.id == initialBend.id);
    expect(redoneBend.p1.x, equals(initialBend.p1.x + 10));
    expect(vm.selectedBendId, equals(initialBend.id));
  });

  test('Multi-select nudge move and undo/redo', () {
    final vm = SheetMetalStudioViewModel();
    final p1 = CncPunchPrimitive(
      id: 'P_MULTI_1',
      type: PunchType.roundHole,
      center: const CadPoint2D(50, 50),
      diameterMm: 8.0,
    );
    final p2 = CncPunchPrimitive(
      id: 'P_MULTI_2',
      type: PunchType.roundHole,
      center: const CadPoint2D(80, 50),
      diameterMm: 8.0,
    );
    vm.addPunch(p1);
    vm.addPunch(p2);
    final baseUndoLen = vm.undoStackLength;

    // Select both punches
    vm.selectEntities({'P_MULTI_1', 'P_MULTI_2'});
    expect(vm.selectedEntityIds.length, equals(2));

    // Nudge selected entities by (5, 10)
    vm.nudgeSelected(5, 10);
    expect(vm.undoStackLength, equals(baseUndoLen + 1));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_1').center.x, equals(55.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_1').center.y, equals(60.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_2').center.x, equals(85.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_2').center.y, equals(60.0));

    // Undo nudge
    vm.undo();
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_1').center.x, equals(50.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_1').center.y, equals(50.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_2').center.x, equals(80.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_2').center.y, equals(50.0));

    // Redo nudge
    vm.redo();
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_1').center.x, equals(55.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_1').center.y, equals(60.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_2').center.x, equals(85.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_MULTI_2').center.y, equals(60.0));
  });

  test('Document loading preserves history undo/redo from DSF undoDeltas and featureHistory', () {
    final vm1 = SheetMetalStudioViewModel();
    final p = CncPunchPrimitive(
      id: 'P_PERSIST',
      type: PunchType.roundHole,
      center: const CadPoint2D(60, 60),
      diameterMm: 12.0,
    );
    vm1.addPunch(p);
    final punch = vm1.document.punches.firstWhere((x) => x.id == 'P_PERSIST');
    vm1.updatePunch(punch.copyWith(diameterMm: 24.0));

    final exportedDoc = vm1.document;
    expect(exportedDoc.undoDeltas.isNotEmpty, isTrue);

    // Load exported doc in a fresh ViewModel
    final vm2 = SheetMetalStudioViewModel();
    vm2.loadDocument(exportedDoc);

    // Verify undo stack was restored from exportedDoc.undoDeltas
    expect(vm2.undoStackLength, greaterThanOrEqualTo(1));
    expect(vm2.document.punches.firstWhere((x) => x.id == 'P_PERSIST').diameterMm, equals(24.0));

    // Undo should restore diameterMm to 12.0
    vm2.undo();
    expect(vm2.document.punches.firstWhere((x) => x.id == 'P_PERSIST').diameterMm, equals(12.0));

    // Redo should restore diameterMm to 24.0
    vm2.redo();
    expect(vm2.document.punches.firstWhere((x) => x.id == 'P_PERSIST').diameterMm, equals(24.0));
  });

  test('Cut line add, move, and endpoint update undo/redo', () {
    final vm = SheetMetalStudioViewModel();
    final initialCuts = vm.document.cutLines.length;

    // 1. Add cut line
    vm.addCutLine(const CadPoint2D(20, 20), const CadPoint2D(80, 20));
    expect(vm.document.cutLines.length, equals(initialCuts + 1));
    final cutId = vm.document.cutLines.last.id;
    expect(vm.selectedCutId, equals(cutId));

    // 2. Move cut line
    vm.beginObjectDrag();
    vm.moveSelectedCut(const CadPoint2D(0, 10));
    vm.endObjectDrag();
    expect(vm.document.cutLines.firstWhere((c) => c.id == cutId).p1.y, equals(30.0));

    // 3. Update cut endpoint
    vm.beginObjectDrag();
    vm.updateCutEndpoint(cutId: cutId, isP1: false, newPoint: const CadPoint2D(90, 30));
    vm.endObjectDrag();
    expect(vm.document.cutLines.firstWhere((c) => c.id == cutId).p2.x, equals(90.0));

    // Undo endpoint update
    vm.undo();
    expect(vm.document.cutLines.firstWhere((c) => c.id == cutId).p2.x, equals(80.0));
    expect(vm.selectedCutId, equals(cutId));

    // Undo move
    vm.undo();
    expect(vm.document.cutLines.firstWhere((c) => c.id == cutId).p1.y, equals(20.0));
    expect(vm.selectedCutId, equals(cutId));

    // Undo add
    vm.undo();
    expect(vm.document.cutLines.length, equals(initialCuts));
  });

  test('Advanced punch properties (type, angle, coupler role) undo/redo', () {
    final vm = SheetMetalStudioViewModel();
    final p = CncPunchPrimitive(
      id: 'P_ADV',
      type: PunchType.roundHole,
      center: const CadPoint2D(120, 120),
      diameterMm: 15.0,
    );
    vm.addPunch(p);

    // Update punch properties: change to slot, add length/width/rotation
    final punch = vm.document.punches.firstWhere((x) => x.id == 'P_ADV');
    vm.updatePunch(punch.copyWith(
      type: PunchType.obroundSlot,
      lengthMm: 30.0,
      widthMm: 15.0,
      rotationDeg: 45.0,
      role: CncPunchRole.coupler,
    ));

    expect(vm.document.punches.firstWhere((x) => x.id == 'P_ADV').type, equals(PunchType.obroundSlot));
    expect(vm.document.punches.firstWhere((x) => x.id == 'P_ADV').rotationDeg, equals(45.0));
    expect(vm.document.punches.firstWhere((x) => x.id == 'P_ADV').role, equals(CncPunchRole.coupler));

    // Undo property update
    vm.undo();
    final undone = vm.document.punches.firstWhere((x) => x.id == 'P_ADV');
    expect(undone.type, equals(PunchType.roundHole));
    expect(undone.rotationDeg, equals(0.0));
    expect(undone.role, equals(CncPunchRole.general));
    expect(vm.selectedPunchId, equals('P_ADV'));

    // Redo property update
    vm.redo();
    final redone = vm.document.punches.firstWhere((x) => x.id == 'P_ADV');
    expect(redone.type, equals(PunchType.obroundSlot));
    expect(redone.rotationDeg, equals(45.0));
    expect(redone.role, equals(CncPunchRole.coupler));
    expect(vm.selectedPunchId, equals('P_ADV'));
  });

  test('Continuous interactive drag moves smoothly across multiple steps with single undo', () {
    final vm = SheetMetalStudioViewModel();
    final p1 = CncPunchPrimitive(
      id: 'P_DRAG_1',
      type: PunchType.roundHole,
      center: const CadPoint2D(50, 50),
      diameterMm: 10.0,
    );
    final p2 = CncPunchPrimitive(
      id: 'P_DRAG_2',
      type: PunchType.roundHole,
      center: const CadPoint2D(80, 80),
      diameterMm: 10.0,
    );
    vm.addPunch(p1);
    vm.addPunch(p2);
    final baseUndo = vm.undoStackLength;

    // Multi-select both punches
    vm.selectEntities(['P_DRAG_1', 'P_DRAG_2']);
    expect(vm.selectedEntityIds.length, equals(2));

    // Simulate multi-step pointer drag
    vm.beginObjectDrag();
    expect(vm.isDraggingObject, isTrue);

    // Step 1: mouse moves 1 step (+5, +5)
    vm.moveSelectedEntities(5, 5);
    expect(vm.isDraggingObject, isTrue);
    expect(vm.undoStackLength, equals(baseUndo)); // No history recorded during drag
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_1').center.x, equals(55.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_2').center.x, equals(85.0));

    // Step 2: mouse moves step 2 (+10, +0) - verifies it is NOT stuck/detached
    vm.moveSelectedEntities(10, 0);
    expect(vm.isDraggingObject, isTrue);
    expect(vm.undoStackLength, equals(baseUndo));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_1').center.x, equals(65.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_2').center.x, equals(95.0));

    // Step 3: mouse moves step 3 (+0, -15)
    vm.moveSelectedEntities(0, -15);
    expect(vm.isDraggingObject, isTrue);
    expect(vm.undoStackLength, equals(baseUndo));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_1').center.y, equals(40.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_2').center.y, equals(70.0));

    // Finish drag
    vm.endObjectDrag();
    expect(vm.isDraggingObject, isFalse);
    expect(vm.undoStackLength, equals(baseUndo + 1)); // Exactly 1 atomic undo step for entire drag

    // Single Undo reverts entire continuous drag
    vm.undo();
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_1').center.x, equals(50.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_1').center.y, equals(50.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_2').center.x, equals(80.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_2').center.y, equals(80.0));

    // Redo restores final continuous drag position
    vm.redo();
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_1').center.x, equals(65.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_1').center.y, equals(40.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_2').center.x, equals(95.0));
    expect(vm.document.punches.firstWhere((p) => p.id == 'P_DRAG_2').center.y, equals(70.0));
  });
}
