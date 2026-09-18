import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/constraints/entity_constraint_state.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/canvas/floating_sketch_constraint_bar.dart';

void main() {
  group('Onshape-Grade Sketch Constraints & Dimensions Interactions', () {
    late SheetMetalStudioViewModel vm;

    setUp(() {
      vm = SheetMetalStudioViewModel();
      vm.loadSampleCableTray();
      // Add a test cut line
      vm.addCutLine(
        const CadPoint2D(20.0, 30.0),
        const CadPoint2D(120.0, 30.0),
      );
    });

    test('1. 1-click line measurement creates dimension in addDimension mode', () {
      final initialDimCount = vm.document.dimensions.length;
      vm.setToolMode(StudioToolMode.addDimension);
      final cut = vm.document.cutLines.last;
      final midPoint = CadPoint2D(
        (cut.p1.x + cut.p2.x) / 2.0,
        (cut.p1.y + cut.p2.y) / 2.0,
      );

      // Single click on the cut line
      vm.handleCanvasClick(midPoint, snapRadiusMm: 5.0);

      // Should have created a dimension directly for that edge
      expect(vm.document.dimensions.length, equals(initialDimCount + 1));
      final createdDim = vm.document.dimensions.last;
      expect(createdDim.referenceAId, equals(cut.id));
      expect(createdDim.pointA?.x, equals(cut.p1.x));
      expect(createdDim.pointB?.x, equals(cut.p2.x));
      expect(createdDim.measuredValue, closeTo(100.0, 0.01));
      expect(vm.toolMode, equals(StudioToolMode.select));
    });

    test('2. commitInteractiveDimension adds dimension and drives geometry', () {
      final initialDimCount = vm.document.dimensions.length;
      const pA = CadPoint2D(10.0, 10.0);
      const pB = CadPoint2D(10.0, 60.0);

      // Commit interactive dimension with custom value
      final dim = vm.commitInteractiveDimension(
        pA: pA,
        pB: pB,
        offset: 30.0,
        customValue: 75.0,
      );

      expect(dim, isNotNull);
      expect(vm.document.dimensions.length, equals(initialDimCount + 1));
      final added = vm.document.dimensions.last;
      expect(added.pointA?.x, equals(10.0));
      expect(added.pointB?.x, equals(10.0));
      expect(added.measuredValue, closeTo(75.0, 0.01));
    });

    test('3. FloatingSketchConstraintBar correctly filters and applies constraints for 1 entity', () {
      final cut = vm.document.cutLines.last;
      vm.selectCut(cut.id);

      expect(FloatingSketchConstraintBar.canApplyHorizontal(vm), isTrue);
      expect(FloatingSketchConstraintBar.canApplyVertical(vm), isTrue);
      expect(FloatingSketchConstraintBar.canApplyFixed(vm), isTrue);
      // 2-entity constraints should be false for 1 entity
      expect(FloatingSketchConstraintBar.canApplyParallel(vm), isFalse);
      expect(FloatingSketchConstraintBar.canApplyPerpendicular(vm), isFalse);

      // Apply Horizontal constraint
      vm.applyConstraint(CadConstraintType.horizontal);

      final hasHoriz = vm.activeConstraintDefinitions.any(
        (c) => c.type == CadConstraintType.horizontal &&
            c.references.any((r) => r.entityId == cut.id),
      );
      expect(hasHoriz, isTrue);
    });

    test('4. FloatingSketchConstraintBar applies parallel/perpendicular for 2 selected entities', () {
      // Add second cut line
      vm.addCutLine(
        const CadPoint2D(20.0, 60.0),
        const CadPoint2D(120.0, 65.0),
      );
      final cut1 = vm.document.cutLines[vm.document.cutLines.length - 2];
      final cut2 = vm.document.cutLines.last;

      vm.selectEntities([cut1.id, cut2.id]);

      expect(vm.selectedEntityIds.length, equals(2));
      expect(FloatingSketchConstraintBar.canApplyParallel(vm), isTrue);
      expect(FloatingSketchConstraintBar.canApplyPerpendicular(vm), isTrue);
      expect(FloatingSketchConstraintBar.canApplyEqual(vm), isTrue);

      // Apply Parallel
      vm.applyConstraint(CadConstraintType.parallel);

      final hasParallel = vm.activeConstraintDefinitions.any(
        (c) => c.type == CadConstraintType.parallel &&
            c.references.any((r) => r.entityId == cut1.id) &&
            c.references.any((r) => r.entityId == cut2.id),
      );
      expect(hasParallel, isTrue);
    });

    test('5. getEntityConstraintState detects Under, Fully, and Over constrained DOF states', () {
      final cut = vm.document.cutLines.last;

      // 5a. Initially without constraints -> underConstrained (CAD Blue)
      final stateInitial = vm.getEntityConstraintState(cut.id);
      expect(stateInitial, equals(EntityConstraintState.underConstrained));
      expect(stateInitial.color, equals(const Color(0xFF0284C7)));

      // 5b. Apply Fixed constraint -> fullyConstrained (Slate Black)
      vm.selectCut(cut.id);
      vm.applyConstraint(CadConstraintType.fixed);

      final stateFixed = vm.getEntityConstraintState(cut.id);
      expect(stateFixed, equals(EntityConstraintState.fullyConstrained));
      expect(stateFixed.color, equals(const Color(0xFF0F172A)));

      // 5c. Apply conflicting Horizontal AND Vertical -> overConstrained (Crimson Red)
      vm.applyConstraint(CadConstraintType.horizontal);
      vm.applyConstraint(CadConstraintType.vertical);

      final stateConflicted = vm.getEntityConstraintState(cut.id);
      expect(stateConflicted, equals(EntityConstraintState.overConstrained));
      expect(stateConflicted.color, equals(const Color(0xFFEF4444)));
    });

    test('6. Constraint deletion removes constraint and resolves conflict', () {
      final cut = vm.document.cutLines.last;
      vm.selectCut(cut.id);
      vm.applyConstraint(CadConstraintType.fixed);
      vm.applyConstraint(CadConstraintType.horizontal);
      vm.applyConstraint(CadConstraintType.vertical);

      expect(vm.getEntityConstraintState(cut.id), equals(EntityConstraintState.overConstrained));

      // Find the vertical constraint definition and remove it
      final vertDef = vm.activeConstraintDefinitions.firstWhere(
        (c) => c.type == CadConstraintType.vertical && c.references.any((r) => r.entityId == cut.id),
      );
      vm.removeConstraint(vertDef.id);

      // Conflict should be resolved
      expect(vm.getEntityConstraintState(cut.id), equals(EntityConstraintState.fullyConstrained));
    });

    test('7. DOF diagnostics toggle switches state properly', () {
      expect(vm.showDofDiagnostics, isFalse);
      vm.toggleDofDiagnostics();
      expect(vm.showDofDiagnostics, isTrue);
      vm.setShowDofDiagnostics(false);
      expect(vm.showDofDiagnostics, isFalse);
    });
  });
}
