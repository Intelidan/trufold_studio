// =============================================================================
// solid_geometry_and_chamfer_test.dart
//
// Comprehensive unit tests verifying:
// 1. SS1: Solid Hole Pass-Through Bore Walls across sheet metal thickness
// 2. SS2 & SS3: Continuous Solid 3D Curved Elbow Bend Fillets with concentric radii & caps
// 3. 3D Edge Chamfering (45° bevel) on thick sheets
// 4. DSF serialization / deserialization of edge chamfer settings
// 5. ViewModel Chamfer control methods and undo/redo support
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/models/sheet_metal_material.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('Solid Sheet Metal Geometry & Chamfering Tests', () {
    test('1. SS1: Punch holes generate solid pass-through vertical bore walls', () {
      const thickness = 5.0; // 5mm thick sheet
      final outerContour = [
        const CadPoint2D(0, 0),
        const CadPoint2D(100, 0),
        const CadPoint2D(100, 100),
        const CadPoint2D(0, 100),
      ];

      final face = PlanarSheetFace(
        id: 'F_BASE',
        label: 'Base Plate',
        vertices: outerContour,
        isBaseAnchor: true,
      );

      final punchRound = CncPunchPrimitive(
        id: 'P_ROUND_1',
        type: PunchType.roundHole,
        center: const CadPoint2D(50, 50),
        diameterMm: 10.0,
      );

      final doc = DsfDocument(
        productType: 'Thick Plate',
        itemName: 'TP-5MM',
        material: const SheetMetalMaterial(thicknessMm: thickness),
        outerContour: outerContour,
        faces: [face],
        bends: [],
        punches: [punchRound],
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 0.0);

      // Verify top face has hole
      final topFace = mesh.polygons.firstWhere((p) => p.faceId == 'F_BASE');
      expect(topFace.holes.length, equals(1));

      // Verify bottom face has hole
      final botFace = mesh.thicknessPolygons.firstWhere((p) => p.faceId == 'F_BASE_BOT');
      expect(botFace.holes.length, equals(1));

      // Verify solid bore walls exist in thicknessPolygons
      final borePolys = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('BORE_F_BASE_P_ROUND_1')).toList();
      expect(borePolys, isNotEmpty, reason: 'Must generate solid cylindrical bore wall facets');

      // Check each bore wall connects z=0 to z=-5mm
      for (final bore in borePolys) {
        expect(bore.vertices.length, equals(4));
        final zVals = bore.vertices.map((v) => v.z).toList();
        final maxZ = zVals.reduce((a, b) => a > b ? a : b);
        final minZ = zVals.reduce((a, b) => a < b ? a : b);
        expect(maxZ, closeTo(0.0, 1e-3), reason: 'Bore wall top must meet z=0');
        expect(minZ, closeTo(-thickness, 1e-3), reason: 'Bore wall bottom must reach z=-5mm');

        // Verify normal points into the hole cavity (horizontal normal, normal.z ≈ 0)
        expect(bore.normal.z.abs(), lessThan(0.1));
      }
    });

    test('2. SS2 & SS3: Bend fillets generate solid 3D curved elbow with inside, outside and side caps', () {
      const thickness = 5.0;
      const radius = 8.0;

      final doc = DsfDocument(
        productType: 'Bracket',
        itemName: 'BRK-5MM',
        material: const SheetMetalMaterial(
          thicknessMm: thickness,
          defaultBendRadius: radius,
        ),
        outerContour: [
          const CadPoint2D(0, 0),
          const CadPoint2D(200, 0),
          const CadPoint2D(200, 100),
          const CadPoint2D(0, 100),
        ],
        faces: [
          const PlanarSheetFace(
            id: 'F_PARENT',
            vertices: [
              CadPoint2D(0, 0),
              CadPoint2D(100, 0),
              CadPoint2D(100, 100),
              CadPoint2D(0, 100),
            ],
            isBaseAnchor: true,
          ),
          const PlanarSheetFace(
            id: 'F_CHILD',
            vertices: [
              CadPoint2D(100, 0),
              CadPoint2D(200, 0),
              CadPoint2D(200, 100),
              CadPoint2D(100, 100),
            ],
          ),
        ],
        bends: [
          FoldBendLine(
            id: 'B1',
            p1: const CadPoint2D(100, 0),
            p2: const CadPoint2D(100, 100),
            direction: FoldDirection.down,
            targetAngleDeg: 90.0,
            radiusMm: radius,
            parentFaceId: 'F_PARENT',
            childFaceId: 'F_CHILD',
          ),
        ],
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);

      // Verify inside curved surface facets exist (6 angular steps across longitudinal segments)
      final inFillets = mesh.filletPolygons.where((p) => p.faceId.startsWith('FILLET_B1_')).toList();
      expect(inFillets.isNotEmpty, isTrue);
      expect(inFillets.length % 6, equals(0), reason: 'Multiples of 6 angular steps of inside cylindrical facets');

      // Verify outside curved surface facets exist (concentric radius R + thickness = 13mm)
      final outFillets = mesh.filletPolygons.where((p) => p.faceId.startsWith('FILLET_OUT_B1_')).toList();
      expect(outFillets.isNotEmpty, isTrue);
      expect(outFillets.length % 6, equals(0), reason: 'Multiples of 6 angular steps of outside cylindrical facets');

      // Verify annular side caps exist at both ends of the bend line
      final cap1 = mesh.filletPolygons.where((p) => p.faceId.startsWith('FILLET_CAP1_B1_')).toList();
      final cap2 = mesh.filletPolygons.where((p) => p.faceId.startsWith('FILLET_CAP2_B1_')).toList();
      expect(cap1.length, equals(6), reason: '6 steps of annular cap quads at P1 end');
      expect(cap2.length, equals(6), reason: '6 steps of annular cap quads at P2 end');

      // Verify rim suppression: No flat rim quad generated along the bend line for parent or child
      final bendRims = mesh.thicknessPolygons.where((p) {
        if (!p.faceId.startsWith('RIM_')) return false;
        // Check if any rim vertex is on the bend seam (x ≈ 100)
        final allXNear100 = p.vertices.every((v) => (v.x - 100.0).abs() < 1.0);
        return allXNear100;
      }).toList();
      expect(bendRims, isEmpty, reason: 'Bend seam must not have square rim quads blocking the curved elbow');
    });

    test('3. 3D Edge Chamfering creates 45° beveled facets on exposed sheet edges', () {
      const thickness = 5.0;
      const chamfer = 1.5;

      final doc = DsfDocument(
        productType: 'Thick Chamfered Plate',
        itemName: 'TCP-5MM',
        material: const SheetMetalMaterial(
          thicknessMm: thickness,
          edgeChamferMm: chamfer,
        ),
        outerContour: [
          const CadPoint2D(0, 0),
          const CadPoint2D(100, 0),
          const CadPoint2D(100, 100),
          const CadPoint2D(0, 100),
        ],
        faces: [
          const PlanarSheetFace(
            id: 'F_BASE',
            vertices: [
              CadPoint2D(0, 0),
              CadPoint2D(100, 0),
              CadPoint2D(100, 100),
              CadPoint2D(0, 100),
            ],
            isBaseAnchor: true,
          ),
        ],
        bends: [],
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 0.0);

      // Verify CHAMFER facets exist
      final chamferFacets = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('CHAMFER_F_BASE_')).toList();
      expect(chamferFacets.length, equals(4), reason: 'Each of the 4 outer edges has a 45° chamfer facet');

      // Verify chamfer facet geometry: Top reaches z=0, bottom reaches z = -1.5mm
      for (final ch in chamferFacets) {
        expect(ch.vertices.length, equals(4));
        final zVals = ch.vertices.map((v) => v.z).toList();
        final maxZ = zVals.reduce((a, b) => a > b ? a : b);
        final minZ = zVals.reduce((a, b) => a < b ? a : b);
        expect(maxZ, closeTo(0.0, 1e-3));
        expect(minZ, closeTo(-chamfer, 1e-3));
      }

      // Verify vertical RIM facets below the chamfer: Start at z = -1.5mm and reach z = -5.0mm
      final rimFacets = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('RIM_F_BASE_')).toList();
      expect(rimFacets.length, equals(4));
      for (final rim in rimFacets) {
        final zVals = rim.vertices.map((v) => v.z).toList();
        final maxZ = zVals.reduce((a, b) => a > b ? a : b);
        final minZ = zVals.reduce((a, b) => a < b ? a : b);
        expect(maxZ, closeTo(-chamfer, 1e-3));
        expect(minZ, closeTo(-thickness, 1e-3));
      }
    });

    test('4. DSF serialization round-trip stores and restores edge chamfer settings', () {
      final original = DsfDocument(
        productType: 'Chamfered Part',
        itemName: 'CP-100',
        material: const SheetMetalMaterial(
          thicknessMm: 4.0,
          edgeChamferMm: 1.2,
        ),
        outerContour: [
          const CadPoint2D(0, 0),
          const CadPoint2D(80, 0),
          const CadPoint2D(80, 60),
          const CadPoint2D(0, 60),
        ],
        bends: [],
        edgeChamfers: {
          'F_0_1': 2.0,
          'F_0_3': 1.5,
        },
      );

      final json = original.toJson();
      final restored = DsfDocument.fromJson(json);

      expect(restored.material.edgeChamferMm, equals(1.2));
      expect(restored.edgeChamfers['F_0_1'], equals(2.0));
      expect(restored.edgeChamfers['F_0_3'], equals(1.5));
    });

    test('5. ViewModel edge chamfer manipulation and undo/redo support', () {
      final doc = DsfDocument(
        productType: 'VM Test',
        itemName: 'VM-1',
        material: const SheetMetalMaterial(thicknessMm: 3.0),
        outerContour: [
          const CadPoint2D(0, 0),
          const CadPoint2D(100, 0),
          const CadPoint2D(100, 100),
          const CadPoint2D(0, 100),
        ],
        faces: [
          const PlanarSheetFace(
            id: 'F_0',
            vertices: [
              CadPoint2D(0, 0),
              CadPoint2D(100, 0),
              CadPoint2D(100, 100),
              CadPoint2D(0, 100),
            ],
            isBaseAnchor: true,
          ),
        ],
        bends: [],
      );

      final vm = SheetMetalStudioViewModel(initialDocument: doc);
      expect(vm.currentEdgeChamfer, equals(0.0));

      // Apply global edge chamfer
      vm.setGlobalEdgeChamfer(1.0);
      expect(vm.currentEdgeChamfer, equals(1.0));
      expect(vm.document.material.edgeChamferMm, equals(1.0));

      // Test specific edge chamfer
      vm.setEdgeChamfer('F_0_2', 1.8);
      expect(vm.edgeChamfers['F_0_2'], equals(1.8));

      // Test toggle edge chamfer
      vm.toggleEdgeChamfer('F_0_0');
      expect(vm.edgeChamfers.containsKey('F_0_0'), isTrue);

      vm.toggleEdgeChamfer('F_0_0');
      expect(vm.edgeChamfers.containsKey('F_0_0'), isFalse);

      // Test Undo
      expect(vm.canUndo, isTrue);
      vm.undo(); // Undo toggle 2 -> restores toggle 1 state where F_0_0 was added
      expect(vm.edgeChamfers.containsKey('F_0_0'), isTrue);

      vm.undo(); // Undo toggle 1 -> restores setEdgeChamfer state
      expect(vm.edgeChamfers.containsKey('F_0_0'), isFalse);
      expect(vm.edgeChamfers.containsKey('F_0_2'), isTrue);

      vm.undo(); // Undo setEdgeChamfer -> restores globalEdgeChamfer state
      expect(vm.edgeChamfers.containsKey('F_0_2'), isFalse);
      expect(vm.currentEdgeChamfer, equals(1.0));

      vm.undo(); // Undo setGlobalEdgeChamfer -> restores initial state
      expect(vm.currentEdgeChamfer, equals(0.0));
    });

    test('7. Overlapping holes cull internal bore walls inside intersecting void', () {
      // Create a document with a round hole overlapping a square hole (as in user screenshot)
      const contour = [
        CadPoint2D(0, 0),
        CadPoint2D(200, 0),
        CadPoint2D(200, 200),
        CadPoint2D(0, 200),
      ];

      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'OverlapTest',
        outerContour: contour,
        material: const SheetMetalMaterial(thicknessMm: 5.0),
        faces: const [
          PlanarSheetFace(
            id: 'F_BASE',
            isBaseAnchor: true,
            vertices: contour,
          ),
        ],
        bends: const [],
        punches: [
          // Square hole at center (100, 100) size 40x40 -> bounds [80, 120] x [80, 120]
          const CncPunchPrimitive(
            id: 'P_SQUARE',
            type: PunchType.square,
            center: CadPoint2D(100, 100),
            widthMm: 40.0,
            lengthMm: 40.0,
            diameterMm: 40.0,
          ),
          // Round hole overlapping the bottom edge of the square at (100, 80) with diameter 24 (radius 12)
          // Its top half extends into the square hole void (y from 80 to 92)!
          CncPunchPrimitive.round(
            id: 'P_ROUND',
            center: const CadPoint2D(100, 80),
            diameterMm: 24.0,
          ),
        ],
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 0.0);

      // Extract all bore wall facets
      final boreWalls = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('BORE_')).toList();
      expect(boreWalls.isNotEmpty, isTrue);

      // Verify NO bore wall segment has its midpoint inside the square hole [81, 119] x [81, 119]
      for (final bore in boreWalls) {
        final avgX = bore.vertices.map((v) => v.x).reduce((a, b) => a + b) / 4.0;
        final avgY = bore.vertices.map((v) => v.y).reduce((a, b) => a + b) / 4.0;
        final isStrictlyInsideSquare = (avgX > 82.0 && avgX < 118.0 && avgY > 82.0 && avgY < 118.0);
        expect(
          isStrictlyInsideSquare,
          isFalse,
          reason: 'Bore wall at ($avgX, $avgY) must not slice through overlapping square hole void!',
        );
      }
    });

    test('8. Bend fillets and sheet rims have outward normals pointing into air', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'NormalsTest',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(150, 0),
          CadPoint2D(150, 100),
          CadPoint2D(0, 100),
        ],
        material: const SheetMetalMaterial(thicknessMm: 3.0),
        faces: const [
          PlanarSheetFace(
            id: 'F_BASE',
            isBaseAnchor: true,
            vertices: [
              CadPoint2D(0, 0),
              CadPoint2D(100, 0),
              CadPoint2D(100, 100),
              CadPoint2D(0, 100),
            ],
          ),
          PlanarSheetFace(
            id: 'F_FLANGE',
            vertices: [
              CadPoint2D(100, 0),
              CadPoint2D(150, 0),
              CadPoint2D(150, 100),
              CadPoint2D(100, 100),
            ],
          ),
        ],
        bends: [
          FoldBendLine(
            id: 'B_UP',
            p1: const CadPoint2D(100, 0),
            p2: const CadPoint2D(100, 100),
            direction: FoldDirection.up,
            targetAngleDeg: 90.0,
            radiusMm: 5.0,
            parentFaceId: 'F_BASE',
            childFaceId: 'F_FLANGE',
          ),
        ],
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);

      // Inside fillet facets must have non-zero outward normals pointing towards cylinder axis
      final insideFillets = mesh.filletPolygons.where((p) => p.faceId.startsWith('FILLET_B_UP_')).toList();
      expect(insideFillets.isNotEmpty, isTrue);
      for (final f in insideFillets) {
        expect(f.normal.length, greaterThan(0.9), reason: 'Inside fillet normal must be unit length');
      }

      // Outside fillet facets must have outward normals pointing away from cylinder axis
      final outsideFillets = mesh.filletPolygons.where((p) => p.faceId.startsWith('FILLET_OUT_B_UP_')).toList();
      expect(outsideFillets.isNotEmpty, isTrue);
      for (final f in outsideFillets) {
        expect(f.normal.length, greaterThan(0.9), reason: 'Outside fillet normal must be unit length');
      }

      // Exterior rims must have outward normals
      final rims = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('RIM_')).toList();
      expect(rims.isNotEmpty, isTrue);
      for (final r in rims) {
        expect(r.normal.length, greaterThan(0.9), reason: 'Rim normal must be unit length');
      }
    });
  });
}
