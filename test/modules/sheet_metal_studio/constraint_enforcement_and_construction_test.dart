import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/constraints/geometric_constraint_solver.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/constraints/constraint_definition.dart';
import 'package:trufold_studio/sheet_metal_studio/models/constraints/reference_geometry.dart';
import 'package:trufold_studio/sheet_metal_studio/models/constraints/stable_geometry_reference.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('Constraint Enforcement & Construction Lines Tests', () {
    late SheetMetalStudioViewModel vm;

    setUp(() {
      vm = SheetMetalStudioViewModel();
      vm.loadSampleCableTray();
      vm.addPunch(CncPunchPrimitive.round(
        id: 'PUNCH_TEST_1',
        center: const CadPoint2D(50.0, 50.0),
        diameterMm: 10.0,
      ));
    });

    test('1. Fixed constraint blocks live dragging of punch', () {
      final punchId = vm.document.punches.first.id;
      final initialCenter = vm.document.punches.first.center;

      // Select the punch
      vm.selectPunch(punchId);

      // Add fixed constraint on this punch
      vm.addConstraint(CadConstraint(
        id: 'FIX_PUNCH_1',
        type: CadConstraintType.fixed,
        entityIds: [punchId],
      ));

      // Attempt to move the punch via moveSelectedPunch
      vm.moveSelectedPunch(CadPoint2D(initialCenter.x + 25.0, initialCenter.y + 10.0));

      final punchAfter = vm.document.punches.firstWhere((p) => p.id == punchId);
      expect(punchAfter.center.x, equals(initialCenter.x),
          reason: 'Punch position must remain locked when fixed constraint is active');
      expect(punchAfter.center.y, equals(initialCenter.y),
          reason: 'Punch position must remain locked when fixed constraint is active');
    });

    test('2. Fixed constraint blocks keyboard nudge of punch', () {
      final punchId = vm.document.punches.first.id;
      final initialCenter = vm.document.punches.first.center;

      vm.selectPunch(punchId);
      vm.addConstraint(CadConstraint(
        id: 'FIX_PUNCH_NUDGE',
        type: CadConstraintType.fixed,
        entityIds: [punchId],
      ));

      vm.nudgeSelected(5.0, 5.0);

      final punchAfter = vm.document.punches.firstWhere((p) => p.id == punchId);
      expect(punchAfter.center.x, equals(initialCenter.x));
      expect(punchAfter.center.y, equals(initialCenter.y));
    });

    test('3. Fixed constraint blocks bend line live dragging and nudge', () {
      final bendId = vm.document.bends.first.id;
      final initialP1 = vm.document.bends.first.p1;

      vm.selectBend(bendId);
      vm.addConstraint(CadConstraint(
        id: 'FIX_BEND_1',
        type: CadConstraintType.fixed,
        entityIds: [bendId],
      ));

      // Attempt move
      vm.moveSelectedBend(const CadPoint2D(10.0, 0.0));

      final bendAfterMove = vm.document.bends.firstWhere((b) => b.id == bendId);
      expect(bendAfterMove.p1.x, equals(initialP1.x));

      // Attempt nudge
      vm.nudgeSelectedBend(5.0, 0.0);
      final bendAfterNudge = vm.document.bends.firstWhere((b) => b.id == bendId);
      expect(bendAfterNudge.p1.x, equals(initialP1.x));
    });

    test('4. Construction line participates in distance constraint solver', () {
      // Add a horizontal construction line at Y = 50.0
      final constLine = ReferenceGeometry(
        id: 'CL_Y50',
        name: 'Construction Guide Y50',
        type: ReferenceGeometryType.constructionLine,
        p1: const CadPoint2D(0, 50),
        p2: const CadPoint2D(200, 50),
      );
      vm.addReferenceGeometry(constLine);

      // Create a punch and constrain its distance to the construction line to 20mm
      final punch = CncPunchPrimitive.round(
        id: 'PUNCH_CONST_TEST',
        center: const CadPoint2D(50, 40),
        diameterMm: 8.0,
      );
      vm.loadDocument(vm.document.copyWith(punches: [...vm.document.punches, punch]));

      final distanceConstraint = ConstraintDefinition(
        id: 'DIST_TO_CONST',
        type: CadConstraintType.distance,
        references: [
          const EntityRef(entityId: 'PUNCH_CONST_TEST', subRef: GeometrySubRefType.center),
          const EntityRef(entityId: 'CL_Y50'),
        ],
        targetValue: 20.0,
      );

      final result = GeometricConstraintSolver.solve(
        document: vm.document,
        overrideConstraints: [distanceConstraint],
        customReferences: vm.allReferenceGeometries,
      );

      expect(result.success, isTrue);
      final solvedPunch = result.updatedDocument.punches.firstWhere((p) => p.id == 'PUNCH_CONST_TEST');
      // Should be 50 - 20 = 30 or 50 + 20 = 70
      final distToY50 = (solvedPunch.center.y - 50.0).abs();
      expect((distToY50 - 20.0).abs() < 1e-3, isTrue,
          reason: 'Punch Y must be exactly 20mm away from horizontal construction line at Y=50');
    });

    test('5. Construction line participates in coincident constraint solver', () {
      final constLine = ReferenceGeometry(
        id: 'CL_VERT',
        name: 'Vertical Centerline',
        type: ReferenceGeometryType.constructionLine,
        p1: const CadPoint2D(75, 0),
        p2: const CadPoint2D(75, 200),
      );
      vm.addReferenceGeometry(constLine);

      final punch = CncPunchPrimitive.round(
        id: 'PUNCH_COINCIDENT',
        center: const CadPoint2D(12, 80),
        diameterMm: 6.0,
      );
      vm.loadDocument(vm.document.copyWith(punches: [...vm.document.punches, punch]));

      final coincidentConstraint = ConstraintDefinition(
        id: 'COIN_TO_CONST',
        type: CadConstraintType.coincident,
        references: [
          const EntityRef(entityId: 'PUNCH_COINCIDENT', subRef: GeometrySubRefType.center),
          const EntityRef(entityId: 'CL_VERT'),
        ],
      );

      final result = GeometricConstraintSolver.solve(
        document: vm.document,
        overrideConstraints: [coincidentConstraint],
        customReferences: vm.allReferenceGeometries,
      );

      expect(result.success, isTrue);
      final solvedPunch = result.updatedDocument.punches.firstWhere((p) => p.id == 'PUNCH_COINCIDENT');
      expect((solvedPunch.center.x - 75.0).abs() < 1e-3, isTrue,
          reason: 'Punch X must snap directly onto the vertical construction line at X=75');
    });

    test('6. toggleSelectedConstruction converts cut line to construction line', () {
      // Add a laser cut line
      final cut = CadLineSegment(
        id: 'CUT_FOR_CONSTRUCTION',
        p1: const CadPoint2D(10, 20),
        p2: const CadPoint2D(80, 20),
      );
      vm.loadDocument(vm.document.copyWith(cutLines: [...vm.document.cutLines, cut]));
      vm.selectCut('CUT_FOR_CONSTRUCTION');

      final initialConstCount = vm.customReferenceGeometries.length;
      vm.toggleSelectedConstruction();

      // Cut should be removed from cutLines
      expect(vm.document.cutLines.any((c) => c.id == 'CUT_FOR_CONSTRUCTION'), isFalse);
      // And added as a construction reference geometry
      expect(vm.customReferenceGeometries.length, equals(initialConstCount + 1));
      expect(vm.customReferenceGeometries.last.type, equals(ReferenceGeometryType.constructionLine));
      expect(vm.customReferenceGeometries.last.p1, equals(const CadPoint2D(10, 20)));
    });

    test('7. Smooth sub-pixel dragging moves entities with high precision', () {
      final punchId = vm.document.punches.first.id;
      vm.selectPunch(punchId);

      // Sub-pixel drag: e.g. +0.35mm, +0.12mm
      final candidate = CadPoint2D(
        vm.document.punches.first.center.x + 0.35,
        vm.document.punches.first.center.y + 0.12,
      );
      vm.moveSelectedPunch(candidate);

      final moved = vm.document.punches.firstWhere((p) => p.id == punchId);
      expect((moved.center.x - candidate.x).abs() < 1e-4, isTrue);
      expect((moved.center.y - candidate.y).abs() < 1e-4, isTrue);
    });
  });
}
