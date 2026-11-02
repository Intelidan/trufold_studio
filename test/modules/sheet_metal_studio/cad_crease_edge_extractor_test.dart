import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cad_crease_edge_extractor.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

void main() {
  group('CadCreaseEdgeExtractor Tests', () {
    test('Flat quad split into 2 coplanar triangles eliminates diagonal seam', () {
      // Quad from (0,0,0) to (10,10,0) split into 2 triangles
      final t1 = CadFoldedPolygon3D(
        vertices: const [
          CadPoint3D(0.0, 0.0, 0.0),
          CadPoint3D(10.0, 0.0, 0.0),
          CadPoint3D(10.0, 10.0, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: Colors.blue,
        faceId: 'FACE_1',
      );
      final t2 = CadFoldedPolygon3D(
        vertices: const [
          CadPoint3D(0.0, 0.0, 0.0),
          CadPoint3D(10.0, 10.0, 0.0),
          CadPoint3D(0.0, 10.0, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: Colors.blue,
        faceId: 'FACE_2',
      );

      final segments = CadCreaseEdgeExtractor.extractCreaseSegments([t1, t2]);
      
      // Should have exactly 4 perimeter edges, 0 diagonal edges
      expect(segments.length, equals(4));

      final diagKey = CadCreaseEdgeExtractor.edgeKey(
        const CadPoint3D(0.0, 0.0, 0.0),
        const CadPoint3D(10.0, 10.0, 0.0),
      );
      final survivingKeys = CadCreaseEdgeExtractor.computeSurvivingCreaseKeys([t1, t2]);
      expect(survivingKeys.contains(diagKey), isFalse, reason: 'Coplanar diagonal seam must be discarded');
    });

    test('Smooth cylindrical fillet strip seam (< 24°) is discarded by crease extractor but detected by tangent extractor', () {
      const angleRad = 10.0 * math.pi / 180.0;
      final n2 = CadPoint3D(0.0, math.sin(angleRad), math.cos(angleRad));

      final f1 = CadFoldedPolygon3D(
        vertices: const [
          CadPoint3D(0.0, 0.0, 0.0),
          CadPoint3D(10.0, 0.0, 0.0),
          CadPoint3D(10.0, 5.0, 0.0),
          CadPoint3D(0.0, 5.0, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: Colors.grey,
        faceId: 'BEND_STRIP_1',
      );
      final f2 = CadFoldedPolygon3D(
        vertices: [
          const CadPoint3D(0.0, 5.0, 0.0),
          const CadPoint3D(10.0, 5.0, 0.0),
          CadPoint3D(10.0, 5.0 + 5.0 * math.cos(angleRad), 5.0 * math.sin(angleRad)),
          CadPoint3D(0.0, 5.0 + 5.0 * math.cos(angleRad), 5.0 * math.sin(angleRad)),
        ],
        normal: n2,
        color: Colors.grey,
        faceId: 'BEND_STRIP_2',
      );

      final sharedSeamKey = CadCreaseEdgeExtractor.edgeKey(
        const CadPoint3D(0.0, 5.0, 0.0),
        const CadPoint3D(10.0, 5.0, 0.0),
      );

      final creaseKeys = CadCreaseEdgeExtractor.computeSurvivingCreaseKeys(
        [f1, f2],
        creaseAngleThresholdDeg: 24.0,
      );
      expect(creaseKeys.contains(sharedSeamKey), isFalse, reason: '10° bend strip seam must be filtered out');

      final tangentSegs = CadCreaseEdgeExtractor.extractTangentSegments(
        [f1, f2],
        creaseAngleThresholdDeg: 24.0,
      );
      expect(tangentSegs.length, equals(1), reason: 'Shared seam is recognized as a tangent transition');
    });

    test('Sharp 90° flange fold is retained as a crisp crease edge', () {
      final web = CadFoldedPolygon3D(
        vertices: const [
          CadPoint3D(0.0, 0.0, 0.0),
          CadPoint3D(50.0, 0.0, 0.0),
          CadPoint3D(50.0, 20.0, 0.0),
          CadPoint3D(0.0, 20.0, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: Colors.blueGrey,
        faceId: 'WEB_BOTTOM',
      );
      final flange = CadFoldedPolygon3D(
        vertices: const [
          CadPoint3D(0.0, 20.0, 0.0),
          CadPoint3D(50.0, 20.0, 0.0),
          CadPoint3D(50.0, 20.0, 15.0),
          CadPoint3D(0.0, 20.0, 15.0),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: Colors.blueGrey,
        faceId: 'FLANGE_SIDE',
      );

      final bendLineKey = CadCreaseEdgeExtractor.edgeKey(
        const CadPoint3D(0.0, 20.0, 0.0),
        const CadPoint3D(50.0, 20.0, 0.0),
      );

      final creaseKeys = CadCreaseEdgeExtractor.computeSurvivingCreaseKeys([web, flange]);
      expect(creaseKeys.contains(bendLineKey), isTrue, reason: '90° sharp bend fold must be retained');
    });

    test('Inner punch hole cutouts are retained as clean perimeter boundaries', () {
      final sheetWithHole = CadFoldedPolygon3D(
        vertices: const [
          CadPoint3D(0.0, 0.0, 0.0),
          CadPoint3D(100.0, 0.0, 0.0),
          CadPoint3D(100.0, 100.0, 0.0),
          CadPoint3D(0.0, 100.0, 0.0),
        ],
        holes: const [
          [
            CadPoint3D(40.0, 40.0, 0.0),
            CadPoint3D(60.0, 40.0, 0.0),
            CadPoint3D(60.0, 60.0, 0.0),
            CadPoint3D(40.0, 60.0, 0.0),
          ]
        ],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: Colors.blueGrey,
        faceId: 'SHEET_WITH_SLOT',
      );

      final segments = CadCreaseEdgeExtractor.extractCreaseSegments([sheetWithHole]);
      // 4 outer sheet edges + 4 inner hole edges = 8 edges
      expect(segments.length, equals(8));
    });
  });
}
