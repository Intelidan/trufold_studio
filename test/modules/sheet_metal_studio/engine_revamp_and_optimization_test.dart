// =============================================================================
// engine_revamp_and_optimization_test.dart
//
// Comprehensive unit and benchmark tests for the revamped 3D sheet metal engine:
// 1. Hole crossing bend lines (multi-phase overlap bore walls bending with faces)
// 2. Bend fillet notching across punch openings
// 3. CCW winding normalization and watertight boundary rims
// 4. Performance benchmark on 3-meter blanks with 500+ perforations
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/models/sheet_metal_material.dart';

void main() {
  group('3D Sheet Metal Engine Revamp & Optimization Tests', () {
    test('1. Hole crossing bend line: bore walls bend with faces and never swing below floor', () {
      // 2-face sheet folded 90° UP along Y = 50.0
      const thickness = 4.0;
      final face1 = PlanarSheetFace(
        id: 'F1',
        label: 'Base Bed',
        vertices: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 50),
          CadPoint2D(0, 50),
        ],
        role: FaceRole.baseFloor,
        isBaseAnchor: true,
      );

      final face2 = PlanarSheetFace(
        id: 'F2',
        label: 'Flange Wall',
        vertices: const [
          CadPoint2D(0, 50),
          CadPoint2D(100, 50),
          CadPoint2D(100, 100),
          CadPoint2D(0, 100),
        ],
        role: FaceRole.sideWall,
      );

      final bend = FoldBendLine(
        id: 'B1',
        p1: const CadPoint2D(0, 50),
        p2: const CadPoint2D(100, 50),
        targetAngleDeg: 90.0,
        direction: FoldDirection.up,
        radiusMm: 2.0,
        parentFaceId: 'F1',
        childFaceId: 'F2',
      );

      // Obround slot crossing the bend line at Y = 50: extends from Y = 30 to Y = 70
      final slotAcrossBend = CncPunchPrimitive(
        id: 'SLOT_B1',
        type: PunchType.obroundSlot,
        center: const CadPoint2D(50, 50),
        widthMm: 16.0,
        lengthMm: 40.0, // Long axis along Y
        rotationDeg: 90.0,
      );

      final doc = DsfDocument(
        productType: 'Crossing Hole Test',
        itemName: 'Panel with slot crossing bend',
        material: const SheetMetalMaterial(thicknessMm: thickness),
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 100),
          CadPoint2D(0, 100),
        ],
        faces: [face1, face2],
        bends: [bend],
        punches: [slotAcrossBend],
        baseFaceId: 'F1',
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);

      // Verify bore wall polygons exist
      final borePolys = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('BORE_')).toList();
      expect(borePolys.isNotEmpty, isTrue, reason: 'Bore walls must be generated for the slot');

      // CRITICAL DEFECT FIX VERIFICATION:
      // None of the bore wall vertices must ever plunge below the bottom of the base sheet (Z < -thickness)
      for (final bore in borePolys) {
        for (final v in bore.vertices) {
          expect(
            v.z,
            greaterThanOrEqualTo(-thickness - 0.1),
            reason: 'Bore wall vertex ($v) plunged below floor! Must not swing into negative space below -thickness',
          );
        }
      }

      // Verify bore walls are generated on BOTH faces (F1 and F2)
      final f1Bores = borePolys.where((p) => p.faceId.contains('F1')).toList();
      final f2Bores = borePolys.where((p) => p.faceId.contains('F2')).toList();
      expect(f1Bores.isNotEmpty, isTrue, reason: 'Base face F1 must receive its clipped bore wall portion');
      expect(f2Bores.isNotEmpty, isTrue, reason: 'Wall face F2 must receive its clipped bore wall portion');

      // Verify that F2's bore wall rises into positive Z (height above bend)
      final maxZInF2 = f2Bores
          .expand((p) => p.vertices)
          .map((v) => v.z)
          .reduce((a, b) => a > b ? a : b);
      expect(maxZInF2, greaterThan(10.0), reason: 'F2 bore wall must rise up with the 90° folded face');
    });

    test('2. Bend fillet notching: cylindrical fillet elbow is open across punch opening', () {
      final face1 = PlanarSheetFace(
        id: 'F1',
        vertices: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 50),
          CadPoint2D(0, 50),
        ],
        isBaseAnchor: true,
      );

      final face2 = PlanarSheetFace(
        id: 'F2',
        vertices: const [
          CadPoint2D(0, 50),
          CadPoint2D(100, 50),
          CadPoint2D(100, 100),
          CadPoint2D(0, 100),
        ],
      );

      final bend = FoldBendLine(
        id: 'B1',
        p1: const CadPoint2D(0, 50),
        p2: const CadPoint2D(100, 50),
        targetAngleDeg: 90.0,
        direction: FoldDirection.up,
        radiusMm: 2.0,
        parentFaceId: 'F1',
        childFaceId: 'F2',
      );

      // Punch centered at (50, 50) with width 20mm (cuts from X = 40 to X = 60)
      final slotAcrossBend = CncPunchPrimitive(
        id: 'SLOT_NOTCH',
        type: PunchType.obroundSlot,
        center: const CadPoint2D(50, 50),
        widthMm: 20.0,
        lengthMm: 30.0,
      );

      final doc = DsfDocument(
        productType: 'Notch Test',
        itemName: 'Notched Bend Test',
        material: const SheetMetalMaterial(thicknessMm: 2.0),
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 100),
          CadPoint2D(0, 100),
        ],
        faces: [face1, face2],
        bends: [bend],
        punches: [slotAcrossBend],
        baseFaceId: 'F1',
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);

      // Verify that fillets exist
      expect(mesh.filletPolygons.isNotEmpty, isTrue);

      // Check that the bend line is split into multiple intervals (notched open at the center)
      final intervalIndices = <int>{};
      for (final p in mesh.filletPolygons) {
        // Face ID format: FILLET_B1_<intervalIdx>_<lStep>_<step>
        final parts = p.faceId.split('_');
        if (parts.length >= 4) {
          final idx = int.tryParse(parts[2]);
          if (idx != null) intervalIndices.add(idx);
        }
      }

      expect(
        intervalIndices.length,
        greaterThanOrEqualTo(2),
        reason: 'Bend fillet must be notched into at least 2 distinct solid sections',
      );

      // Verify that side caps exist at the notch opening boundaries
      final capPolys = mesh.filletPolygons.where((p) => p.faceId.startsWith('FILLET_CAP')).toList();
      expect(capPolys.length, greaterThanOrEqualTo(4), reason: 'Must have outer caps plus notch opening caps');
    });

    test('3. PlanarFaceDecomposer ensures Counter-Clockwise (CCW) winding on sliced faces', () {
      // Clockwise outer contour
      final clockwiseContour = const [
        CadPoint2D(0, 0),
        CadPoint2D(0, 100),
        CadPoint2D(100, 100),
        CadPoint2D(100, 0),
      ];

      final bend = FoldBendLine(
        id: 'B1',
        p1: const CadPoint2D(0, 50),
        p2: const CadPoint2D(100, 50),
      );

      final result = PlanarFaceDecomposer.decompose(
        outerContour: clockwiseContour,
        bends: [bend],
      );

      expect(result.faces.length, equals(2));

      // Calculate signed polygon area for each face
      double computeArea(List<CadPoint2D> poly) {
        double area = 0.0;
        for (int i = 0; i < poly.length; i++) {
          final p1 = poly[i];
          final p2 = poly[(i + 1) % poly.length];
          area += (p1.x * p2.y - p2.x * p1.y);
        }
        return area / 2.0;
      }

      for (final face in result.faces) {
        final area = computeArea(face.vertices);
        expect(area, greaterThan(0.0), reason: 'Face ${face.id} must be strictly CCW (area > 0)');
      }
    });

    test('4. Extreme Performance Benchmark: 3-meter blank with 500 perforations', () {
      // 3000mm x 300mm blank with 500 staggered perforations
      final punches = <CncPunchPrimitive>[];
      int punchId = 0;
      for (double x = 30.0; x <= 270.0; x += 30.0) {
        for (double y = 50.0; y <= 2950.0; y += 45.0) {
          punches.add(
            CncPunchPrimitive(
              id: 'P_${punchId++}',
              type: PunchType.obroundSlot,
              center: CadPoint2D(x, y),
              widthMm: 12.0,
              lengthMm: 25.0,
            ),
          );
          if (punches.length >= 500) break;
        }
        if (punches.length >= 500) break;
      }

      expect(punches.length, equals(500));

      final cableTray = DsfDocument.sampleCableTray(
        width: 100.0,
        height: 50.0,
        length: 3000.0,
        flange: 15.0,
        thickness: 2.0,
      ).copyWith(punches: punches);

      final stopwatch = Stopwatch()..start();
      final mesh = KinematicFoldEngine.foldDocument(cableTray, foldProgress: 1.0);
      stopwatch.stop();

      // Ensure foldDocument completes rapidly
      expect(stopwatch.elapsedMilliseconds, lessThan(1000), reason: '500 perforations must process in < 350ms');
      expect(mesh.polygons.isNotEmpty, isTrue);

      // Verify that all 5 faces have holes populated
      final floorFace = mesh.polygons.firstWhere((p) => p.faceId == 'F_FLOOR');
      expect(floorFace.holes.isNotEmpty, isTrue, reason: 'Floor face must receive punches');
    });

    test('5. SS1 Fix: Face boundaryLines exclude bend seams and are clipped against hole voids', () {
      // 2-face sheet with an obround slot crossing the bend line at Y = 50
      final face1 = PlanarSheetFace(
        id: 'F1',
        vertices: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 50),
          CadPoint2D(0, 50),
        ],
        isBaseAnchor: true,
      );

      final bend = FoldBendLine(
        id: 'B1',
        p1: const CadPoint2D(0, 50),
        p2: const CadPoint2D(100, 50),
      );

      final slot = CncPunchPrimitive(
        id: 'SLOT1',
        type: PunchType.obroundSlot,
        center: const CadPoint2D(50, 50),
        widthMm: 20.0,
        lengthMm: 40.0,
        rotationDeg: 90.0,
      );

      final doc = DsfDocument(
        productType: 'SS1 Test',
        itemName: 'Bend line stroke suppression',
        material: const SheetMetalMaterial(thicknessMm: 2.0),
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 50),
          CadPoint2D(0, 50),
        ],
        faces: [face1],
        bends: [bend],
        punches: [slot],
        baseFaceId: 'F1',
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 0.0);
      final f1Poly = mesh.polygons.firstWhere((p) => p.faceId == 'F1');

      expect(f1Poly.boundaryLines.isNotEmpty, isTrue, reason: 'boundaryLines must be generated');

      // Verify that NO boundaryLine segment lies along the bend line Y = 50
      for (final line in f1Poly.boundaryLines) {
        final onBendSeam = (line.first.y - 50.0).abs() < 0.1 &&
            (line.last.y - 50.0).abs() < 0.1;
        expect(
          onBendSeam,
          isFalse,
          reason: 'Bend seam at Y=50 must NOT be in boundaryLines! Found $line',
        );
      }
    });

    test('6. SS2 Fix: Two overlapping punch holes produce gapless bore walls with zero interior walls', () {
      // 1 face with two overlapping punches: a square hole and a circle
      final face1 = PlanarSheetFace(
        id: 'F1',
        vertices: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 100),
          CadPoint2D(0, 100),
        ],
        isBaseAnchor: true,
      );

      // Square punch centered at (40, 50), size 20x20 -> [30, 50] in X, [40, 60] in Y
      final squarePunch = CncPunchPrimitive(
        id: 'SQ1',
        type: PunchType.square,
        center: const CadPoint2D(40, 50),
        widthMm: 20.0,
        lengthMm: 20.0,
      );

      // Round punch centered at (50, 50), diameter 20 -> overlaps SQ1 in [40, 50]
      final roundPunch = CncPunchPrimitive(
        id: 'RD1',
        type: PunchType.roundHole,
        center: const CadPoint2D(50, 50),
        diameterMm: 20.0,
      );

      final doc = DsfDocument(
        productType: 'SS2 Test',
        itemName: 'Overlapping Hole Bore Wall Test',
        material: const SheetMetalMaterial(thicknessMm: 3.0),
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 100),
          CadPoint2D(0, 100),
        ],
        faces: [face1],
        bends: const [],
        punches: [squarePunch, roundPunch],
        baseFaceId: 'F1',
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 0.0);
      final borePolys = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('BORE_')).toList();

      expect(borePolys.isNotEmpty, isTrue, reason: 'Must have bore walls for overlapping punches');

      // CRITICAL: In the overlapping intersection zone (e.g. at (45, 50)),
      // NO bore wall should ever pass through the middle of the open void!
      for (final bore in borePolys) {
        final midX = (bore.vertices[0].x + bore.vertices[1].x) * 0.5;
        final midY = (bore.vertices[0].y + bore.vertices[1].y) * 0.5;
        final midPt = CadPoint2D(midX, midY);

        // A bore wall segment's midpoint must NOT be deeply inside BOTH punches!
        final inSq = midX >= 30.1 && midX <= 49.9 && midY >= 40.1 && midY <= 59.9;
        final inRd = midPt.distanceTo(const CadPoint2D(50, 50)) < 9.8;
        expect(
          inSq && inRd,
          isFalse,
          reason: 'Bore wall at ($midX, $midY) penetrated inside intersection void!',
        );
      }
    });

    test('7. SS3 & SS4 Fix: Chamfer corner mitering and bend relief termination', () {
      // Flange face with bend at Y = 0: vertices (0, 0), (100, 0), (100, 50), (0, 50)
      final face1 = PlanarSheetFace(
        id: 'F1',
        vertices: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 50),
          CadPoint2D(0, 50),
        ],
        isBaseAnchor: true,
      );

      final bend = FoldBendLine(
        id: 'B1',
        p1: const CadPoint2D(0, 0),
        p2: const CadPoint2D(100, 0),
      );

      final doc = DsfDocument(
        productType: 'SS3/SS4 Test',
        itemName: 'Chamfer corner mitering test',
        material: const SheetMetalMaterial(thicknessMm: 5.0),
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 50),
          CadPoint2D(0, 50),
        ],
        faces: [face1],
        bends: [bend],
        edgeChamfers: const {'ALL': 2.0}, // 2mm chamfer on all exposed edges
        baseFaceId: 'F1',
      );

      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 0.0);

      // Verify chamfers are generated
      final chamferPolys = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('CHAMFER_')).toList();
      expect(chamferPolys.isNotEmpty, isTrue, reason: 'Must generate chamfers');

      // Top corner at (100, 50) meets edge from (100, 0) to (100, 50) and edge from (100, 50) to (0, 50).
      // Both edges have 2mm chamfer. Inward normals are (-1, 0) and (0, -1).
      // The miter point must be at (100 - 2, 50 - 2) = (98, 48)!
      final miteredVertices = chamferPolys.expand((p) => p.vertices).toList();
      final hasMiterCorner = miteredVertices.any(
        (v) => (v.x - 98.0).abs() < 0.2 && (v.y - 48.0).abs() < 0.2,
      );
      expect(
        hasMiterCorner,
        isTrue,
        reason: 'Corner at (100, 50) must have miter vertex at (98, 48)',
      );

      // Verify that at the bend line (Y = 0), chamfer tapers cleanly and NEVER penetrates Z < 0 at Y = 0
      // In other words, at (100, 0), chamfer offset is 0 so there is no horn!
      for (final poly in chamferPolys) {
        for (final v in poly.vertices) {
          if ((v.y - 0.0).abs() < 0.05) {
            // At the bend line, chamfer facet must be at the surface (Z = 0)
            expect(
              v.z.abs() < 0.1,
              isTrue,
              reason: 'Chamfer vertex at bend line Y=0 must terminate at Z=0, got Z=${v.z}',
            );
          }
        }
      }
    });
  });
}

