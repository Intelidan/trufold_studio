// =============================================================================
// dxf_dsf_importer_test.dart
//
// Unit tests for DXF and DSF Ingestion & Planar Face Segmentation.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_dsf_importer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';

void main() {
  group('DXF & DSF Ingestion & Face Segmentation Tests', () {
    // Standard ASCII DXF string with EDGES, BEND_UP, BEND_DOWN, and HOLES
    const sampleDxf = '''
0
SECTION
2
ENTITIES
0
LINE
8
EDGES
62
7
10
0.0
20
0.0
11
200.0
21
0.0
0
LINE
8
EDGES
62
7
10
200.0
20
0.0
11
200.0
21
100.0
0
LINE
8
EDGES
62
7
10
200.0
20
100.0
11
0.0
21
100.0
0
LINE
8
EDGES
62
7
10
0.0
20
100.0
11
0.0
21
0.0
0
LINE
8
BEND_UP
62
4
10
50.0
20
0.0
11
50.0
21
100.0
0
LINE
8
BEND_DOWN
62
2
10
150.0
20
0.0
11
150.0
21
100.0
0
CIRCLE
8
HOLES
10
100.0
20
50.0
40
5.0
0
ENDSEC
0
EOF
''';

    test('1. DXF Import with layer classification & punch extraction', () {
      final doc = DxfDsfImporter.importDxf(
        sampleDxf,
        productType: 'Z-Bracket',
        itemName: 'BR-200x100',
      );

      expect(doc.productType, equals('Z-Bracket'));
      expect(doc.itemName, equals('BR-200x100'));

      // 4 boundary lines forming a 200x100 rectangle
      expect(doc.blankWidthMm, closeTo(200.0, 1e-3));
      expect(doc.blankLengthMm, closeTo(100.0, 1e-3));

      // 2 bend lines extracted
      expect(doc.bends.length, equals(2));
      expect(doc.bends[0].direction, equals(BendDirection.up));
      expect(doc.bends[0].layer, equals('BEND_UP'));
      expect(doc.bends[1].direction, equals(BendDirection.down));
      expect(doc.bends[1].layer, equals('BEND_DOWN'));

      // 1 punch hole extracted (diameter 10mm)
      expect(doc.punches.length, equals(1));
      expect(doc.punches[0].diameterMm, closeTo(10.0, 1e-3));
    });

    test('2. Planar face decomposition from bend lines', () {
      final doc = DxfDsfImporter.importDxf(sampleDxf);

      // The 2 bend lines (at X=50 and X=150) split the rectangle into 3 faces:
      // Face A: X in [0, 50] (area 50 * 100 = 5000)
      // Face B: X in [50, 150] (area 100 * 100 = 10000 -> Largest, so Base Floor)
      // Face C: X in [150, 200] (area 50 * 100 = 5000)
      expect(doc.faces.length, equals(3));

      // Check base anchor face selection
      final baseFace = doc.faces.firstWhere((f) => f.id == doc.baseFaceId);
      expect(baseFace.isBaseAnchor, isTrue);
      expect(baseFace.role, equals(FaceRole.baseFloor));

      // Check DAG connections on bends
      for (final bend in doc.bends) {
        expect(bend.parentFaceId.isNotEmpty, isTrue);
        expect(bend.childFaceId.isNotEmpty, isTrue);
        expect(bend.parentFaceId, isNot(equals(bend.childFaceId)));
      }
    });

    test('3. Immediate 3D folding from imported DXF', () {
      final doc = DxfDsfImporter.importDxf(sampleDxf);

      // Fold at t = 0.0 (Flat)
      final flatMesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 0.0);
      expect(flatMesh.boundHeight, closeTo(0.0, 1e-3));

      // Fold at t = 1.0 (Fully folded Z-bracket)
      final foldedMesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      expect(foldedMesh.polygons.length, equals(3));

      // Base floor stays at Z = 0.0
      final basePoly = foldedMesh.polygons.firstWhere((p) => p.faceId == doc.baseFaceId);
      for (final v in basePoly.vertices) {
        expect(v.z, closeTo(0.0, 1e-3));
      }

      // One flange folds UP (+Z > 0)
      final hasUpVertex = foldedMesh.polygons.any((p) => p.vertices.any((v) => v.z > 10.0));
      expect(hasUpVertex, isTrue, reason: 'BEND_UP must fold upwards into +Z');

      // The other flange folds DOWN (-Z < 0)
      final hasDownVertex = foldedMesh.polygons.any((p) => p.vertices.any((v) => v.z < -10.0));
      expect(hasDownVertex, isTrue, reason: 'BEND_DOWN must fold downwards into -Z');

      // Overall 3D height spans from negative Z to positive Z (50mm up with R=1.5mm, 50mm down with R+T=3.0mm: total 104.5mm)
      expect(foldedMesh.boundHeight, closeTo(104.5, 1.0));
    });
  });
}
