// =============================================================================
// kinematic_fold_engine_test.dart
//
// Unit tests for the Sheet Metal Kinematic Folding Math Engine and .dsf model.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';

void main() {
  group('Sheet Metal Kinematic Folding Engine Tests', () {
    late DsfDocument cableTrayDoc;

    setUp(() {
      // 100mm width, 50mm height, 3000mm length, 15mm flange, 1.5mm thickness
      cableTrayDoc = DsfDocument.sampleCableTray(
        width: 100.0,
        height: 50.0,
        length: 3000.0,
        flange: 15.0,
        thickness: 1.5,
      );
    });

    test('1. Unfolded blank properties (t = 0.0)', () {
      // Total blank width = 15 + 50 + 100 + 50 + 15 = 230mm
      expect(cableTrayDoc.blankWidthMm, closeTo(230.0, 1e-3));
      expect(cableTrayDoc.blankLengthMm, closeTo(3000.0, 1e-3));
      expect(cableTrayDoc.faces.length, equals(5));
      expect(cableTrayDoc.bends.length, equals(4));

      // Fold at t = 0.0 (completely flat blank)
      final flatMesh = KinematicFoldEngine.foldDocument(cableTrayDoc, foldProgress: 0.0);

      expect(flatMesh.polygons.length, equals(5));
      // All vertices must have Z = 0.0
      for (final poly in flatMesh.polygons) {
        for (final v in poly.vertices) {
          expect(v.z, closeTo(0.0, 1e-3), reason: 'All vertices must be flat at t = 0.0');
        }
      }
      expect(flatMesh.boundHeight, closeTo(0.0, 1e-3));
      expect(flatMesh.boundWidth, closeTo(230.0, 1e-3));
    });

    test('2. Fully folded 3D model properties (t = 1.0)', () {
      final foldedMesh = KinematicFoldEngine.foldDocument(cableTrayDoc, foldProgress: 1.0);

      expect(foldedMesh.polygons.length, equals(5));

      // Find the base floor polygon
      final floorPoly = foldedMesh.polygons.firstWhere((p) => p.faceId == 'F_FLOOR');
      for (final v in floorPoly.vertices) {
        expect(v.z, closeTo(0.0, 1e-3), reason: 'Base floor must remain at Z = 0.0');
      }

      // Find left wall polygon
      final leftWallPoly = foldedMesh.polygons.firstWhere((p) => p.faceId == 'F_LEFT_WALL');
      // Must reach height of 50mm + bend radius (1.5mm) in Z since wall welds to fillet arc terminal edge
      final maxZLeft = leftWallPoly.vertices.map((v) => v.z).reduce((a, b) => a > b ? a : b);
      expect(maxZLeft, closeTo(51.5, 1e-2), reason: 'Side wall must extend vertically to 50mm + 1.5mm bend radius');

      // Check width between side walls (at X = 65mm and X = 165mm)
      // Base floor has X from 65 to 165 -> width is 100mm
      final minXFloor = floorPoly.vertices.map((v) => v.x).reduce((a, b) => a < b ? a : b);
      final maxXFloor = floorPoly.vertices.map((v) => v.x).reduce((a, b) => a > b ? a : b);
      expect(maxXFloor - minXFloor, closeTo(100.0, 1e-3), reason: 'Tray width must be exactly 100mm');

      // Overall height should be > 50mm (due to 45° return flange pointing inward/downward)
      expect(foldedMesh.boundHeight, greaterThanOrEqualTo(50.0));

      // Bounding width should be approximately 100mm (with fillet offset)
      expect(foldedMesh.boundWidth, closeTo(100.0, 4.0));
    });

    test('3. Progressive folding progression (0.0 -> 0.5 -> 1.0)', () {
      final mesh0 = KinematicFoldEngine.foldDocument(cableTrayDoc, foldProgress: 0.0);
      final meshHalf = KinematicFoldEngine.foldDocument(cableTrayDoc, foldProgress: 0.5);
      final mesh1 = KinematicFoldEngine.foldDocument(cableTrayDoc, foldProgress: 1.0);

      // Height should increase monotonically as sheet folds up
      expect(mesh0.boundHeight, closeTo(0.0, 1e-3));
      expect(meshHalf.boundHeight, greaterThan(0.0));
      expect(mesh1.boundHeight, greaterThan(meshHalf.boundHeight));

      // Bound width should decrease as sides fold up
      expect(mesh0.boundWidth, closeTo(230.0, 1e-3));
      expect(meshHalf.boundWidth, lessThan(mesh0.boundWidth));
      expect(mesh1.boundWidth, lessThan(meshHalf.boundWidth));
    });

    test('4. JSON serialization round-trip (.dsf format)', () {
      final jsonMap = cableTrayDoc.toJson();
      final reconstructed = DsfDocument.fromJson(jsonMap);

      expect(reconstructed.format, equals('DANISH_SHEET_FOLD'));
      expect(reconstructed.version, anyOf(equals('1.0'), equals('2.0')));
      expect(reconstructed.productType, equals('Perforated Cable Tray'));
      expect(reconstructed.material.thicknessMm, equals(1.5));
      expect(reconstructed.bends.length, equals(4));
      expect(reconstructed.faces.length, equals(5));
      expect(reconstructed.parameters['W'], equals(100.0));
      expect(reconstructed.parameters['H'], equals(50.0));
    });

    test('5. Child face welds directly to fillet arc terminal edge (SS2 & SS3)', () {
      final foldedMesh = KinematicFoldEngine.foldDocument(cableTrayDoc, foldProgress: 1.0);

      // Fillets must exist
      expect(foldedMesh.filletPolygons.isNotEmpty, isTrue);

      // Check fillet for left wall bend (B2 at x = 65)
      // Fillet B2 inside facets
      final b2Fillets = foldedMesh.filletPolygons.where((f) => f.faceId.startsWith('FILLET_B2_')).toList();
      expect(b2Fillets.isNotEmpty, isTrue);

      // Terminal edges at P1 (first segment, last angular step) and P2 (last segment, last angular step)
      final firstSegmentTerminal = b2Fillets.firstWhere((f) => f.faceId.endsWith('_5'));
      final lastSegmentTerminal = b2Fillets.lastWhere((f) => f.faceId.endsWith('_5'));
      final filletTerminalV1 = firstSegmentTerminal.vertices[3]; // inB1 at P1
      final filletTerminalV2 = lastSegmentTerminal.vertices[2]; // inB2 at P2

      // Left wall polygon vertices
      final leftWallPoly = foldedMesh.polygons.firstWhere((p) => p.faceId == 'F_LEFT_WALL');

      // The left wall should contain vertices welding to the terminal edge of the fillet
      final hasMatchingV1 = leftWallPoly.vertices.any((v) =>
          (v.x - filletTerminalV1.x).abs() < 0.05 &&
          (v.y - filletTerminalV1.y).abs() < 0.05 &&
          (v.z - filletTerminalV1.z).abs() < 0.05);

      final hasMatchingV2 = leftWallPoly.vertices.any((v) =>
          (v.x - filletTerminalV2.x).abs() < 0.05 &&
          (v.y - filletTerminalV2.y).abs() < 0.05 &&
          (v.z - filletTerminalV2.z).abs() < 0.05);

      expect(hasMatchingV1, isTrue, reason: 'Child face must weld to fillet terminal edge vertex 1');
      expect(hasMatchingV2, isTrue, reason: 'Child face must weld to fillet terminal edge vertex 2');
    });

    test('6. Laser cut lines across bend lines generate cutSegments on 3D faces (SS4 & SS5)', () {
      // Add a laser cut line traversing across the base floor into the left wall
      final cutDoc = cableTrayDoc.copyWith(
        cutLines: [
          const CadLineSegment(
            id: 'CUT_TRANSVERSAL',
            p1: CadPoint2D(50.0, 1000.0), // In left wall (x in [15, 65])
            p2: CadPoint2D(80.0, 1000.0), // In base floor (x in [65, 165])
            layer: 'CUT',
          ),
        ],
      );

      final foldedMesh = KinematicFoldEngine.foldDocument(cutDoc, foldProgress: 1.0);

      // Both base floor and left wall must have cutSegments
      final floorPoly = foldedMesh.polygons.firstWhere((p) => p.faceId == 'F_FLOOR');
      final leftWallPoly = foldedMesh.polygons.firstWhere((p) => p.faceId == 'F_LEFT_WALL');

      expect(floorPoly.cutSegments.isNotEmpty, isTrue, reason: 'Floor face must receive clipped cut segment');
      expect(leftWallPoly.cutSegments.isNotEmpty, isTrue, reason: 'Left wall face must receive clipped cut segment');
    });

    test('7. Radial outward normals for primary and secondary bend fillets', () {
      final foldedMesh = KinematicFoldEngine.foldDocument(cableTrayDoc, foldProgress: 1.0);

      // Verify all fillet facets have unit normals and point away from their cylinder center
      expect(foldedMesh.filletPolygons.isNotEmpty, isTrue);
      for (final poly in foldedMesh.filletPolygons) {
        expect(poly.normal.length, closeTo(1.0, 1e-2));

        // Facet vertices quad
        final v = poly.vertices;
        expect(v.length, equals(4));
        expect(poly.normal.length, greaterThan(0.99));
      }

      // Check secondary lip bend B1
      final b1Fillets = foldedMesh.filletPolygons.where((f) => f.faceId.startsWith('FILLET_B1_')).toList();
      expect(b1Fillets.isNotEmpty, isTrue);
      for (final f in b1Fillets) {
        expect(f.normal.length, closeTo(1.0, 1e-2));
      }
    });
  });
}

