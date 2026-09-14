// =============================================================================
// planar_face_decomposer_test.dart
//
// Tests for PlanarFaceDecomposer:
// - Cut lines slicing planar sheets into distinct faces
// - Protection against halfway bend lines acting like cuts
// - Proper parent/child face assignment for valid through-bends
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';

void main() {
  group('PlanarFaceDecomposer Tests', () {
    // Standard 200 x 100 mm rectangular blank
    final outerContour = const [
      CadPoint2D(0, 0),
      CadPoint2D(200, 0),
      CadPoint2D(200, 100),
      CadPoint2D(0, 100),
    ];

    test('1. Full through-bend divides blank into 2 planar faces', () {
      final bend = const FoldBendLine(
        id: 'B1',
        p1: CadPoint2D(50, 0),
        p2: CadPoint2D(50, 100),
        direction: BendDirection.up,
        targetAngleDeg: 90.0,
      );

      final result = PlanarFaceDecomposer.decompose(
        outerContour: outerContour,
        bends: [bend],
      );

      expect(result.faces.length, equals(2), reason: 'A through bend line must slice the polygon into 2 faces');
      final connectedBend = result.connectedBends.first;
      expect(connectedBend.parentFaceId, isNotEmpty);
      expect(connectedBend.childFaceId, isNotEmpty);
      expect(connectedBend.parentFaceId, isNot(equals(connectedBend.childFaceId)));
    });

    test('2. Halfway bend line does NOT act like a cut and does not slice face', () {
      // Bend terminates halfway at y=50 instead of spanning all the way to y=100
      final halfwayBend = const FoldBendLine(
        id: 'B_HALF',
        p1: CadPoint2D(50, 0),
        p2: CadPoint2D(50, 50), // Halfway through the 100mm height
        direction: BendDirection.up,
        targetAngleDeg: 90.0,
      );

      final result = PlanarFaceDecomposer.decompose(
        outerContour: outerContour,
        bends: [halfwayBend],
      );

      // Sheet should NOT be severed into two separate faces!
      expect(result.faces.length, equals(1), reason: 'Halfway bend line must not sever the sheet blank');
      final processedBend = result.connectedBends.first;
      // Because it cannot slice the polygon, it is left open
      expect(processedBend.parentFaceId, isEmpty, reason: 'Halfway bend must be marked with empty parentFaceId');
    });

    test('3. Laser cut line slices face into 2 separate panels', () {
      final cut = const CadLineSegment(
        id: 'C1',
        p1: CadPoint2D(100, 0),
        p2: CadPoint2D(100, 100),
        layer: 'CUT',
      );

      final result = PlanarFaceDecomposer.decompose(
        outerContour: outerContour,
        bends: const [],
        cutLines: [cut],
      );

      expect(result.faces.length, equals(2), reason: 'Full through cut must divide blank into 2 distinct faces');
    });

    test('4. Combination of cut line and bend line slices correctly', () {
      // Cut line at x=100 (full through cut)
      final cut = const CadLineSegment(
        id: 'C1',
        p1: CadPoint2D(100, 0),
        p2: CadPoint2D(100, 100),
      );

      // Bend line at x=50 across the left piece (from y=0 to y=100)
      final bend = const FoldBendLine(
        id: 'B1',
        p1: CadPoint2D(50, 0),
        p2: CadPoint2D(50, 100),
        direction: BendDirection.up,
      );

      final result = PlanarFaceDecomposer.decompose(
        outerContour: outerContour,
        bends: [bend],
        cutLines: [cut],
      );

      // Cut divides 1 face into 2, bend divides the left piece into 2 -> total 3 faces
      expect(result.faces.length, equals(3));
      final connectedBend = result.connectedBends.first;
      expect(connectedBend.parentFaceId, isNotEmpty);
      expect(connectedBend.childFaceId, isNotEmpty);
    });

    test('5. Corner relief slit allows adjacent flange slicing', () {
      // Slit from edge at (50, 0) up to (50, 20)
      final slit = const CadLineSegment(
        id: 'SLIT1',
        p1: CadPoint2D(50, 0),
        p2: CadPoint2D(50, 20),
      );

      final result = PlanarFaceDecomposer.decompose(
        outerContour: outerContour,
        bends: const [],
        cutLines: [slit],
      );

      // Relief slit should be accommodated without crashing or severing the entire face
      expect(result.faces.isNotEmpty, isTrue);
    });

    test('6. Bend line snapped to cut slit endpoint successfully partitions face (SS1)', () {
      // Slit from edge at (50, 0) up to (50, 40)
      final slit = const CadLineSegment(
        id: 'SLIT1',
        p1: CadPoint2D(50, 0),
        p2: CadPoint2D(50, 40),
        layer: 'CUT',
      );

      // Bend line starting exactly at the slit tip (50, 40) to left edge (0, 40)
      final bend = const FoldBendLine(
        id: 'B1',
        p1: CadPoint2D(50, 40),
        p2: CadPoint2D(0, 40),
        direction: BendDirection.up,
        targetAngleDeg: 90.0,
      );

      final result = PlanarFaceDecomposer.decompose(
        outerContour: outerContour,
        bends: [bend],
        cutLines: [slit],
      );

      // Blank must be partitioned into 2 distinct faces (the corner flap and the remaining body)
      expect(result.faces.length, equals(2), reason: 'Slit + snapped bend line must slice corner flap into 2 faces');
      final connectedBend = result.connectedBends.first;
      expect(connectedBend.parentFaceId, isNotEmpty);
      expect(connectedBend.childFaceId, isNotEmpty);
      expect(connectedBend.parentFaceId, isNot(equals(connectedBend.childFaceId)));
    });
  });
}
