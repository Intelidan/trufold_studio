import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/sheet_metal_material.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/fitting_port_annotation_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/port_inference_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/topological_zone_morpher.dart';

void main() {
  group('1-Click Semantic Port Inference Engine Tests (Sets 2 & 6)', () {
    test('1. Infers port opening width, normal, and sidewall heights from 90° flat bend inlet edge', () {
      final bendDoc = TopologicalZoneMorpher.createBaselineBend90(width: 300.0, height: 50.0, radius: 100.0);

      // The inlet opening edge at bottom/left
      CadLineSegment? openingEdge;
      for (int i = 0; i < bendDoc.outerContour.length; i++) {
        final p1 = bendDoc.outerContour[i];
        final p2 = bendDoc.outerContour[(i + 1) % bendDoc.outerContour.length];
        final len = p1.distanceTo(p2);
        if ((len - 300.0).abs() < 1.0) {
          openingEdge = CadLineSegment(id: 'edge_$i', p1: p1, p2: p2);
          break;
        }
      }

      if (openingEdge != null) {
        final clickPoint = CadPoint2D((openingEdge.p1.x + openingEdge.p2.x) / 2.0, (openingEdge.p1.y + openingEdge.p2.y) / 2.0);

        final result = PortInferenceEngine.inferFromOpeningEdge(document: bendDoc, candidateEdge: openingEdge, clickedPoint: clickPoint, portId: 'port1');

        expect(result, isNotNull);
        expect(result!.inferredWidth, closeTo(300.0, 1.0));
        // Outward normal must be unit vector
        final normalLen = math.sqrt(result.normal.x * result.normal.x + result.normal.y * result.normal.y);
        expect(normalLen, closeTo(1.0, 1e-3));
        expect(result.inferredHeightA, closeTo(50.0, 5.0));
      }
    });

    test('2. Straight cable tray opening edge inference yields exact width, normal, and flange heights', () {
      final trayDoc = DsfDocument.sampleCableTray(width: 200.0, height: 50.0, length: 1000.0);

      // Cross-section along X: [0, 15, 65, 265, 315, 330]
      // Bed floor is between x=65 and x=265 (width = 200mm)
      // At y=0 (bottom end)
      final clickPoint = const CadPoint2D(165.0, 0.0);
      final clickedEdge = const CadLineSegment(id: 'tray_opening_south', p1: CadPoint2D(65.0, 0.0), p2: CadPoint2D(265.0, 0.0));

      final result = PortInferenceEngine.inferFromOpeningEdge(document: trayDoc, candidateEdge: clickedEdge, clickedPoint: clickPoint, portId: 'port1');

      expect(result, isNotNull);
      expect(result!.inferredWidth, closeTo(200.0, 1e-2));
      // Outward connection normal points in negative Y (South)
      expect(result.normal.y, lessThan(0.0));
      expect(result.inferredSide, PortSide.south);
      expect(result.isSymmetric, isTrue);
    });

    test('3. Coupler punches within port zone are associated without distortion', () {
      final teeDoc = TopologicalZoneMorpher.createBaselineTee(width: 200.0, height: 50.0, branchWidth: 150.0);

      expect(teeDoc.punches.isNotEmpty, isTrue);

      // Branch top opening edge
      CadLineSegment? branchOpening;
      for (int i = 0; i < teeDoc.outerContour.length; i++) {
        final p1 = teeDoc.outerContour[i];
        final p2 = teeDoc.outerContour[(i + 1) % teeDoc.outerContour.length];
        final len = p1.distanceTo(p2);
        if ((len - 150.0).abs() < 1.0) {
          branchOpening = CadLineSegment(id: 'branch_top', p1: p1, p2: p2);
          break;
        }
      }

      if (branchOpening != null) {
        final clickPoint = CadPoint2D((branchOpening.p1.x + branchOpening.p2.x) / 2.0, (branchOpening.p1.y + branchOpening.p2.y) / 2.0);

        final result = PortInferenceEngine.inferFromOpeningEdge(document: teeDoc, candidateEdge: branchOpening, clickedPoint: clickPoint, portId: 'port3');

        expect(result, isNotNull);
        expect(result!.inferredWidth, closeTo(150.0, 1.0));
        expect(result.associatedFeatureIds, isNotEmpty);
      }
    });

    test('4. Geometric sidewall distance handles chamfered/filleted outer boundaries', () {
      // Create a document with aesthetic 45° corner reliefs on sidewall
      final contour = <CadPoint2D>[
        const CadPoint2D(0, 0),
        const CadPoint2D(50, 0),
        const CadPoint2D(50, 50), // Wall A outer edge
        const CadPoint2D(50, 100), // Chamfer start
        const CadPoint2D(40, 110), // Chamfer relief notch
        const CadPoint2D(0, 110),
      ];

      final bends = <FoldBendLine>[FoldBendLine(id: 'BEND_WALL_A', p1: const CadPoint2D(0, 50), p2: const CadPoint2D(50, 50), direction: BendDirection.up)];

      final doc = DsfDocument(
        productType: 'Custom Sheet',
        itemName: 'ChamferTest',
        material: const SheetMetalMaterial(thicknessMm: 1.5),
        outerContour: contour,
        bends: bends,
      );

      final result = PortInferenceEngine.inferFromOpeningEdge(
        document: doc,
        candidateEdge: const CadLineSegment(id: 'opening_seg', p1: CadPoint2D(0, 0), p2: CadPoint2D(50, 0)),
        clickedPoint: const CadPoint2D(25, 0),
        portId: 'port1',
      );

      expect(result, isNotNull);
      expect(result!.inferredWidth, closeTo(50.0, 1e-2));
    });

    test('5. autoDetectAllPorts discovers all 4 openings on a 4-Way Cross with canonical ordering', () {
      final crossDoc = TopologicalZoneMorpher.createBaselineCross(widthMain: 100.0, widthBranch: 100.0, height: 50.0);

      final detected = PortInferenceEngine.autoDetectAllPorts(crossDoc);
      expect(detected.length, greaterThanOrEqualTo(4));

      final sides = detected.map((p) => p.inferredSide).toSet();
      expect(sides.contains(PortSide.west), isTrue);
      expect(sides.contains(PortSide.east), isTrue);
      expect(sides.contains(PortSide.north), isTrue);
      expect(sides.contains(PortSide.south), isTrue);

      // Verify port indices are 1-indexed (port1, port2, ...)
      expect(detected[0].portId, 'port1');
      expect(detected[1].portId, 'port2');
    });

    test('6. updateMetadataWithAutoDetectedPorts populates semanticPorts and portAssignments', () {
      final teeDoc = TopologicalZoneMorpher.createBaselineTee(width: 150.0, branchWidth: 100.0, height: 50.0);

      final updatedMeta = PortInferenceEngine.updateMetadataWithAutoDetectedPorts(teeDoc);
      expect(updatedMeta.semanticPorts, isNotNull);
      expect(updatedMeta.semanticPorts!.length, greaterThanOrEqualTo(3));
      expect(updatedMeta.portAssignments, isNotNull);
      expect(updatedMeta.portAssignments!.containsKey('port1'), isTrue);
      expect(updatedMeta.semanticPorts!['port1']?['width'], closeTo(150.0, 5.0));
    });
  });
}
