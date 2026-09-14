// =============================================================================
// cnc_turret_test.dart
//
// Comprehensive unit tests for CNC Turret Punch tools, dynamic obround arcs,
// edge/bend distance constraints, punch dragging, and corner contour treatments.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cnc_turret_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('CNC Turret Punch & Constraint Engine Tests', () {
    late DsfDocument doc;

    setUp(() {
      // Standard Cable Tray: W=100, H=50, L=3000, Flange=15
      // Total developed width = 15 + 50 + 100 + 50 + 15 = 230mm
      // Bends at X = 15 (B1), X = 65 (B2), X = 165 (B3), X = 215 (B4)
      doc = DsfDocument.sampleCableTray(
        width: 100.0,
        height: 50.0,
        length: 3000.0,
        flange: 15.0,
      );
    });

    test('1. Round Hole Punch creation, boundary polygon, and constraints', () {
      final punch = CncTurretEngine.createRoundHole(
        id: 'P_HOLE_1',
        center: const CadPoint2D(115.0, 500.0), // Center of bed floor (X in [65, 165])
        diameterMm: 10.0,
      );

      expect(punch.type, equals(PunchType.roundHole));
      expect(punch.diameterMm, equals(10.0));

      final poly = punch.toPolygon(circleSegments: 16);
      expect(poly.length, equals(16));

      // Each polygon vertex should be distance R = 5.0 from center
      for (final pt in poly) {
        expect(pt.distanceTo(punch.center), closeTo(5.0, 1e-3));
      }

      // Compute constraints
      final constraints = CncTurretEngine.computeConstraints(punch: punch, doc: doc);
      expect(constraints.distFromLeftMm, closeTo(115.0, 1e-2));
      expect(constraints.distFromRightMm, closeTo(230.0 - 115.0, 1e-2)); // 115.0
      expect(constraints.distFromBottomMm, closeTo(500.0, 1e-2));
      expect(constraints.distFromTopMm, closeTo(2500.0, 1e-2));

      // Nearest bend: B2 is at X=65 (dist 50), B3 is at X=165 (dist 50)
      expect(constraints.distToNearestBendMm, closeTo(50.0, 1e-2));
      expect(['B2', 'B3'].contains(constraints.nearestBendId), isTrue);
    });

    test('2. Obround Slot Punch creation and dynamic end arc geometry', () {
      // Cable tray perforation slot: 7mm wide x 25mm long
      final obround = CncTurretEngine.createObroundSlot(
        id: 'P_SLOT_1',
        center: const CadPoint2D(80.0, 200.0),
        widthMm: 7.0,
        lengthMm: 25.0,
        rotationDeg: 0.0,
      );

      expect(obround.type, equals(PunchType.obroundSlot));
      expect(obround.widthMm, equals(7.0));
      expect(obround.lengthMm, equals(25.0));

      final poly = obround.toPolygon(circleSegments: 16);
      expect(poly.isNotEmpty, isTrue);

      // Verify slot bounding envelope:
      // Length along X = 25mm -> X spans from (80 - 12.5) to (80 + 12.5) -> [67.5, 92.5]
      // Width along Y = 7mm -> Y spans from (200 - 3.5) to (200 + 3.5) -> [196.5, 203.5]
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      for (final pt in poly) {
        if (pt.x < minX) minX = pt.x;
        if (pt.x > maxX) maxX = pt.x;
        if (pt.y < minY) minY = pt.y;
        if (pt.y > maxY) maxY = pt.y;
      }

      expect(minX, closeTo(67.5, 0.1));
      expect(maxX, closeTo(92.5, 0.1));
      expect(minY, closeTo(196.5, 0.1));
      expect(maxY, closeTo(203.5, 0.1));

      // Dynamic modification: resize slot to 9mm width x 30mm length
      final modifiedObround = obround.copyWith(widthMm: 9.0, lengthMm: 30.0);
      final modifiedPoly = modifiedObround.toPolygon(circleSegments: 16);

      double mMinX = double.infinity, mMaxX = -double.infinity;
      double mMinY = double.infinity, mMaxY = -double.infinity;
      for (final pt in modifiedPoly) {
        if (pt.x < mMinX) mMinX = pt.x;
        if (pt.x > mMaxX) mMaxX = pt.x;
        if (pt.y < mMinY) mMinY = pt.y;
        if (pt.y > mMaxY) mMaxY = pt.y;
      }

      expect(mMinX, closeTo(80.0 - 15.0, 0.1)); // 65.0
      expect(mMaxX, closeTo(80.0 + 15.0, 0.1)); // 95.0
      expect(mMinY, closeTo(200.0 - 4.5, 0.1)); // 195.5
      expect(mMaxY, closeTo(200.0 + 4.5, 0.1)); // 204.5
    });

    test('3. Punch Dragging and Interactive ViewModel updates', () {
      final vm = SheetMetalStudioViewModel(initialDocument: doc);
      expect(vm.document.punches.isEmpty, isTrue);

      // Add a round hole
      vm.addPunch(CncPunchPrimitive.round(
        id: 'P_DRAG_TEST',
        center: const CadPoint2D(50.0, 100.0),
        diameterMm: 8.0,
      ));

      expect(vm.document.punches.length, equals(1));
      expect(vm.document.punches.first.center.x, closeTo(50.0, 1e-3));

      // Drag / Move punch to new location (100.0, 250.0)
      vm.updatePunch(vm.document.punches.first.moveTo(const CadPoint2D(100.0, 250.0)));

      expect(vm.document.punches.first.center.x, closeTo(100.0, 1e-3));
      expect(vm.document.punches.first.center.y, closeTo(250.0, 1e-3));

      // Verify constraint calculation reflects the new position
      final updatedConstraints = CncTurretEngine.computeConstraints(
        punch: vm.document.punches.first,
        doc: vm.document,
      );
      expect(updatedConstraints.distFromLeftMm, closeTo(100.0, 1e-2));
      expect(updatedConstraints.distFromBottomMm, closeTo(250.0, 1e-2));

      vm.dispose();
    });

    test('4. Corner Treatments: 45° Chamfer and Bezier Fillet', () {
      // 100x100 square plate
      final squareContour = [
        const CadPoint2D(0.0, 0.0),
        const CadPoint2D(100.0, 0.0),
        const CadPoint2D(100.0, 100.0),
        const CadPoint2D(0.0, 100.0),
      ];

      // Apply 10mm 45° chamfer to top-right corner (vertex 2: (100, 100))
      final chamfered = CncTurretEngine.applyCornerChamfer(
        contour: squareContour,
        vertexIndex: 2,
        chamferMm: 10.0,
      );

      // Original 4 vertices replaced by 5 vertices (corner split into 2)
      expect(chamfered.length, equals(5));
      expect(chamfered[2].x, closeTo(100.0, 1e-3));
      expect(chamfered[2].y, closeTo(90.0, 1e-3));
      expect(chamfered[3].x, closeTo(90.0, 1e-3));
      expect(chamfered[3].y, closeTo(100.0, 1e-3));

      // Apply 10mm fillet with 6 segments to bottom-left corner (vertex 0: (0, 0))
      final filleted = CncTurretEngine.applyCornerFillet(
        contour: squareContour,
        vertexIndex: 0,
        radiusMm: 10.0,
        arcSegments: 6,
      );

      // Replaces 1 vertex with 7 arc points
      expect(filleted.length, equals(3 + 7));
      // First arc point: along Y axis at (0, 10)
      expect(filleted.first.x, closeTo(0.0, 1e-3));
      expect(filleted.first.y, closeTo(10.0, 1e-3));
      // Last arc point: along X axis at (10, 0)
      expect(filleted[6].x, closeTo(10.0, 1e-3));
      expect(filleted[6].y, closeTo(0.0, 1e-3));
    });

    test('5. Punch JSON Serialization roundtrip in DsfDocument', () {
      final punch1 = CncTurretEngine.createRoundHole(
        id: 'P1',
        center: const CadPoint2D(50.0, 100.0),
        diameterMm: 6.5,
      );
      final punch2 = CncTurretEngine.createObroundSlot(
        id: 'P2',
        center: const CadPoint2D(120.0, 300.0),
        widthMm: 9.0,
        lengthMm: 35.0,
        rotationDeg: 90.0,
      );

      final docWithPunches = doc.copyWith(punches: [punch1, punch2]);
      final json = docWithPunches.toJson();
      final restored = DsfDocument.fromJson(json);

      expect(restored.punches.length, equals(2));
      expect(restored.punches[0].id, equals('P1'));
      expect(restored.punches[0].diameterMm, equals(6.5));
      expect(restored.punches[1].id, equals('P2'));
      expect(restored.punches[1].widthMm, equals(9.0));
      expect(restored.punches[1].lengthMm, equals(35.0));
      expect(restored.punches[1].rotationDeg, equals(90.0));
    });
  });
}
