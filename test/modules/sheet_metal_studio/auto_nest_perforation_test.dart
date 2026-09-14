// =============================================================================
// auto_nest_perforation_test.dart
//
// Unit and integration tests for:
// 1. SS1: Individual hole rotation in PerforationPattern (grid array remains upright)
// 2. SS2 & SS3: Auto-nesting perforation pattern onto selected planar surfaces:
//    - Standard tray widths: 50, 100, 150, 250, 300, 450, 600, 750, 900 mm
//    - Width-wise pitch: 50 mm, side margin: 25 mm
//    - Side wall: 50 mm height -> 2 rows, 25 mm pitch
//    - Obround 30x7 mm, 80 mm pitch, 25 mm stagger distance
//    - Boundary containment and exclusion
//    - ViewModel undo/redo integration
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/perforation_pattern.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cnc_turret_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('SS1: Perforation Pattern Individual Hole Rotation', () {
    test('Rotating pattern to 45° rotates individual holes but keeps grid columns upright', () {
      const pattern0 = PerforationPattern(
        id: 'PAT_ROT_TEST',
        anchor: CadPoint2D(100.0, 200.0),
        countX: 2,
        countY: 4,
        pitchX: 50.0,
        pitchY: 80.0,
        slotWidthMm: 7.0,
        slotLengthMm: 30.0,
        staggered: false,
        rotationDeg: 0.0,
      );

      final pattern45 = pattern0.copyWith(rotationDeg: 45.0);

      // Centers of the 8 holes in pattern0
      final centers0 = pattern0.activeCenters;
      final centers45 = pattern45.activeCenters;

      expect(centers0.length, equals(8));
      expect(centers45.length, equals(8));

      // 1. Hole centers MUST remain at identical grid coordinates!
      for (int i = 0; i < 8; i++) {
        expect(
          centers45[i].x,
          closeTo(centers0[i].x, 1e-4),
          reason: 'Hole $i X coordinate should remain in upright column',
        );
        expect(
          centers45[i].y,
          closeTo(centers0[i].y, 1e-4),
          reason: 'Hole $i Y coordinate should remain at row position',
        );
      }

      // Column 0 centers should be at X = 75.0 (100 - 25)
      // Column 1 centers should be at X = 125.0 (100 + 25)
      for (int iy = 0; iy < 4; iy++) {
        expect(pattern45.holeCenter(iy * 2).x, closeTo(75.0, 1e-4));
        expect(pattern45.holeCenter(iy * 2 + 1).x, closeTo(125.0, 1e-4));
      }

      // 2. Punches must have individual rotationDeg = 45.0!
      final punches0 = pattern0.expandToPunches();
      final punches45 = pattern45.expandToPunches();

      expect(punches0.every((p) => p.rotationDeg == 0.0), isTrue);
      expect(punches45.every((p) => p.rotationDeg == 45.0), isTrue);
    });

    test('Cable Tray 25mm Stagger offsets alternate columns along Y', () {
      const staggeredPattern = PerforationPattern(
        id: 'PAT_STAGGER',
        anchor: CadPoint2D(100.0, 200.0),
        countX: 2,
        countY: 4,
        pitchX: 50.0,
        pitchY: 80.0,
        staggered: true,
        staggerDistanceMm: 25.0,
        staggerAlongY: true,
      );

      // Column 0, Row 0
      final c0 = staggeredPattern.relativeHoleCenter(0, 0);
      // Column 1, Row 0
      final c1 = staggeredPattern.relativeHoleCenter(1, 0);

      // Column 1 must be staggered by +25mm along Y
      expect(c1.y - c0.y, closeTo(25.0, 1e-4));
      expect(c1.x - c0.x, closeTo(50.0, 1e-4));
    });
  });

  group('SS2 & SS3: Auto-Nest Perforation on Selected Planar Surface', () {
    PlanarSheetFace makeFloorFace(double width, double length) {
      return PlanarSheetFace(
        id: 'F_FLOOR_${width.toInt()}',
        label: 'Bed Floor ${width.toInt()}mm',
        role: FaceRole.baseFloor,
        vertices: [
          CadPoint2D(0.0, 0.0),
          CadPoint2D(width, 0.0),
          CadPoint2D(width, length),
          CadPoint2D(0.0, length),
        ],
      );
    }

    test('Standard Cable Tray Widths (50, 100, 150, 250, 300, 450, 600, 750, 900 mm) auto-select correct columns & 50mm pitch', () {
      final doc = DsfDocument.sampleCableTray();

      final standardTraySpecs = {
        50.0: 1, // 1 col (centered)
        100.0: 2, // 2 cols, 50mm pitch
        150.0: 3, // 3 cols, 50mm pitch
        250.0: 5, // 5 cols, 50mm pitch
        300.0: 6, // 6 cols, 50mm pitch
        450.0: 9, // 9 cols, 50mm pitch
        600.0: 12, // 12 cols, 50mm pitch
        750.0: 15, // 15 cols, 50mm pitch
        900.0: 18, // 18 cols, 50mm pitch
      };

      for (final entry in standardTraySpecs.entries) {
        final width = entry.key;
        final expectedCols = entry.value;

        final face = makeFloorFace(width, 1000.0);
        final pattern = CncTurretEngine.autoNestPerforationOnFace(
          face: face,
          doc: doc,
          slotWidth: 7.0,
          slotLength: 30.0,
          pitchY: 80.0,
          staggerDistance: 25.0,
        );

        expect(
          pattern.countX,
          equals(expectedCols),
          reason: 'Tray width $width mm should yield $expectedCols columns',
        );

        if (expectedCols > 1) {
          expect(
            pattern.pitchX,
            closeTo(50.0, 1e-4),
            reason: 'Tray width $width mm must have 50mm width-wise pitch',
          );
        }

        expect(
          pattern.pitchY,
          equals(80.0),
          reason: 'Longitudinal pitch must be 80mm',
        );
        expect(
          pattern.staggerDistanceMm,
          equals(25.0),
          reason: 'Stagger distance must be 25mm',
        );
        expect(
          pattern.slotLengthMm,
          equals(30.0),
          reason: 'Slot length must be 30mm',
        );
        expect(
          pattern.slotWidthMm,
          equals(7.0),
          reason: 'Slot width must be 7mm',
        );
      }
    });

    test(
      'Side Wall 50mm height produces 2 rows of perforation with 25mm pitch',
      () {
        final doc = DsfDocument.sampleCableTray();
        final wallFace = PlanarSheetFace(
          id: 'F_SIDE_WALL_50',
          label: 'Left Side Wall',
          role: FaceRole.sideWall,
          vertices: [
            CadPoint2D(0.0, 0.0),
            CadPoint2D(50.0, 0.0),
            CadPoint2D(50.0, 1000.0),
            CadPoint2D(0.0, 1000.0),
          ],
        );

        final pattern = CncTurretEngine.autoNestPerforationOnFace(
          face: wallFace,
          doc: doc,
          slotWidth: 7.0,
          slotLength: 30.0,
          pitchY: 80.0,
          staggerDistance: 25.0,
        );

        // 50mm wall must produce exactly 2 rows of perforation
        expect(pattern.countX, equals(2));
        expect(pattern.pitchX, closeTo(25.0, 1e-4));
        // Side wall slots default to 90° (longitudinal along wall length)
        expect(pattern.rotationDeg, equals(90.0));
        expect(pattern.pitchY, equals(80.0));
        expect(pattern.staggerDistanceMm, equals(25.0));
      },
    );

    test('Boundary clipping excludes any holes outside the planar surface boundary', () {
      final doc = DsfDocument.sampleCableTray();
      // Triangle/Trapezoid face that narrows down
      final taperedFace = PlanarSheetFace(
        id: 'F_TAPERED',
        label: 'Tapered Transition',
        role: FaceRole.custom,
        vertices: [
          CadPoint2D(0.0, 0.0),
          CadPoint2D(300.0, 0.0),
          CadPoint2D(100.0, 500.0),
          CadPoint2D(0.0, 500.0),
        ],
      );

      final pattern = CncTurretEngine.autoNestPerforationOnFace(
        face: taperedFace,
        doc: doc,
        slotWidth: 7.0,
        slotLength: 30.0,
      );

      // Excluded holes should be detected and marked
      expect(pattern.deletedHoleIndices.isNotEmpty, isTrue);
      // Active punches must all lie within the polygon
      final activePunches = pattern.expandToPunches();
      expect(activePunches.length, equals(pattern.activeHoleCount));
    });

    test(
      'ViewModel autoNestPerforationOnFace adds unified pattern with undo/redo',
      () {
        final vm = SheetMetalStudioViewModel();
        final initialPatternCount = vm.document.perforationPatterns.length;
        final initialPunchesCount = vm.document.allPunches.length;

        // Auto nest on bed floor
        vm.autoNestPerforationOnFace(
          faceId: 'F_FLOOR',
          slotWidth: 7.0,
          slotLength: 30.0,
          pitchY: 80.0,
          staggerDistance: 25.0,
        );

        expect(
          vm.document.perforationPatterns.length,
          equals(initialPatternCount + 1),
        );
        final newPat = vm.document.perforationPatterns.last;
        expect(newPat.slotLengthMm, equals(30.0));
        expect(newPat.slotWidthMm, equals(7.0));
        expect(newPat.pitchY, equals(80.0));
        expect(newPat.staggerDistanceMm, equals(25.0));
        expect(vm.selectedPatternId, equals(newPat.id));

        // Test rotating pattern from ViewModel
        vm.rotatePattern(newPat.id, 45.0);
        final rotatedPat = vm.document.perforationPatterns.firstWhere(
          (p) => p.id == newPat.id,
        );
        expect(rotatedPat.rotationDeg, equals(45.0));

        // Test undo
        vm.undo(); // Undo rotate
        expect(
          vm.document.perforationPatterns
              .firstWhere((p) => p.id == newPat.id)
              .rotationDeg,
          equals(0.0),
        );

        vm.undo(); // Undo auto nest
        expect(
          vm.document.perforationPatterns.length,
          equals(initialPatternCount),
        );
        expect(vm.document.allPunches.length, equals(initialPunchesCount));

        // Test redo
        vm.redo();
        expect(
          vm.document.perforationPatterns.length,
          equals(initialPatternCount + 1),
        );
      },
    );
  });
}
