// =============================================================================
// magnetic_snap_test.dart
//
// Unit tests for Magnetic Snapping Engine and Interactive Bend Line Operations.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/magnetic_snap_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('Magnetic Snap Engine & Interactive Bend Operations Tests', () {
    late DsfDocument doc;

    setUp(() {
      doc = DsfDocument.sampleCableTray(
        width: 100.0,
        height: 50.0,
        length: 3000.0,
        flange: 15.0,
      );
    });

    test('1. MagneticSnapEngine extracts corners, midpoints, and bend endpoints', () {
      final targets = MagneticSnapEngine.extractTargets(doc);

      expect(targets.isNotEmpty, isTrue);

      // Verify corner targets exist
      final hasCorners = targets.any((t) => t.type == SnapType.cornerVertex);
      expect(hasCorners, isTrue);

      // Verify bend endpoint targets exist
      final hasBendStarts = targets.any((t) => t.type == SnapType.bendEndpoint);
      expect(hasBendStarts, isTrue);

      // Test snapping when cursor is 1.5mm away from bend line at (15.0, 0.0)
      final snap = MagneticSnapEngine.findClosestSnap(
        cursorMm: const CadPoint2D(16.2, 0.8),
        targets: targets,
        snapRadiusMm: 10.0,
      );

      expect(snap, isNotNull);
      expect(snap!.point.x, closeTo(15.0, 1e-3));
      expect(snap.point.y, closeTo(0.0, 1e-3));
      expect(snap.type, equals(SnapType.bendEndpoint));

      // Test cursor outside radius returns null
      final farSnap = MagneticSnapEngine.findClosestSnap(
        cursorMm: const CadPoint2D(999.0, 999.0),
        targets: targets,
        snapRadiusMm: 10.0,
      );
      expect(farSnap, isNull);
    });

    test('2. Interactive bend addition, property update, and deletion in ViewModel', () {
      final vm = SheetMetalStudioViewModel(initialDocument: doc);
      final initialBendsCount = vm.document.bends.length;
      final initialFacesCount = vm.document.faces.length;

      expect(initialBendsCount, equals(4));
      expect(initialFacesCount, equals(5));

      // Set tool mode to add bend
      vm.setToolMode(StudioToolMode.addBend);
      expect(vm.toolMode, equals(StudioToolMode.addBend));

      // Simulate clicking point A and point B to add a transversal bend at Y = 1500
      vm.handleCanvasClick(const CadPoint2D(0.0, 1500.0));
      expect(vm.pendingBendStart, isNotNull);

      vm.handleCanvasClick(const CadPoint2D(230.0, 1500.0));
      expect(vm.pendingBendStart, isNull); // Cleared after completing line

      // Verify bend was created
      expect(vm.document.bends.length, equals(initialBendsCount + 1));
      final newBend = vm.document.bends.last;
      expect(newBend.p1.y, closeTo(1500.0, 1e-3));
      expect(newBend.p2.y, closeTo(1500.0, 1e-3));

      // Verify planar faces were re-decomposed
      expect(vm.document.faces.length, greaterThan(initialFacesCount));

      // Modify the new bend's angle and direction
      vm.updateBend(newBend.copyWith(
        targetAngleDeg: 45.0,
        direction: BendDirection.down,
      ));

      final updatedBend = vm.document.bends.firstWhere((b) => b.id == newBend.id);
      expect(updatedBend.targetAngleDeg, equals(45.0));
      expect(updatedBend.direction, equals(BendDirection.down));

      // Delete the bend line
      vm.deleteBendLine(newBend.id);
      expect(vm.document.bends.length, equals(initialBendsCount));
    });
  });
}
