import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';

void main() {
  test('Verify 90 deg inside riser baseline folding and openings structure', () {
    final file = File('assets/dsf_templates/trunking_accessories/90_deg_inside_riser_100x100.dsf');
    expect(file.existsSync(), isTrue);

    final dsf = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    expect(dsf.outerContour.length, greaterThan(20));

    final foldResult = KinematicFoldEngine.foldDocument(dsf, foldProgress: 1.0);
    expect(foldResult.polygons.length, equals(7));

    final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: dsf, foldResult: foldResult);
    expect(rawOpenings.length, equals(2));

    // Both openings must have outward normals angled at 45°
    for (final raw in rawOpenings) {
      expect(raw.outwardNormal.z.abs(), closeTo(1.0 / math.sqrt(2), 0.05));
    }
  });

  group('90° Inside Riser Dedicated Scaling & Port Detection', () {
    late DsfDocument dsf;

    setUp(() {
      final file = File('assets/dsf_templates/trunking_accessories/90_deg_inside_riser_100x100.dsf');
      expect(file.existsSync(), isTrue);
      dsf = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      dsf = dsf.copyWith(parameters: {'width': 100.0, 'height': 100.0});
    });

    test('1. Requirement 1: 3D opening borders pass directly through coupler hole centers', () {
      final foldResult = KinematicFoldEngine.foldDocument(dsf, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: dsf, foldResult: foldResult);
      expect(rawOpenings.length, equals(2));

      for (final raw in rawOpenings) {
        final measured = CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: dsf, foldResult: foldResult);

        expect(measured.width, closeTo(100.0, 2.0));
        expect(measured.height, closeTo(100.0, 1.0));
        expect(measured.derivedMouthCorners.length, equals(4));

        final isPort1 = (raw.floorEdgeP1.y + raw.floorEdgeP2.y) / 2.0 > 113.84;
        final slotCheek1Id = isPort1 ? 'SLOT_3' : 'SLOT_7';
        final slotCheek2Id = isPort1 ? 'SLOT_1' : 'SLOT_5';

        final slotCheek1 = foldResult.punchCenters3D[slotCheek1Id]!;
        final slotCheek2 = foldResult.punchCenters3D[slotCheek2Id]!;

        // Direction of Cheek 1 side of the port mouth: P1 -> P3
        final p1 = measured.derivedMouthCorners[0];
        final p3 = measured.derivedMouthCorners[1];
        final segDir1 = CadPoint3D((p3.x - p1.x) / measured.height, (p3.y - p1.y) / measured.height, (p3.z - p1.z) / measured.height);

        final v1 = CadPoint3D(slotCheek1.x - p1.x, slotCheek1.y - p1.y, slotCheek1.z - p1.z);
        final proj1 = v1.x * segDir1.x + v1.y * segDir1.y + v1.z * segDir1.z;
        final perp1 = math.sqrt(
          (v1.x - proj1 * segDir1.x) * (v1.x - proj1 * segDir1.x) +
              (v1.y - proj1 * segDir1.y) * (v1.y - proj1 * segDir1.y) +
              (v1.z - proj1 * segDir1.z) * (v1.z - proj1 * segDir1.z),
        );
        expect(perp1, closeTo(0.0, 0.2), reason: 'Port boundary passes directly through Cheek 1 slot center');

        // Direction of Cheek 2 side of the port mouth: P2 -> P4
        final p2 = measured.derivedMouthCorners[3];
        final p4 = measured.derivedMouthCorners[2];
        final segDir2 = CadPoint3D((p4.x - p2.x) / measured.height, (p4.y - p2.y) / measured.height, (p4.z - p2.z) / measured.height);

        final v2 = CadPoint3D(slotCheek2.x - p2.x, slotCheek2.y - p2.y, slotCheek2.z - p2.z);
        final proj2 = v2.x * segDir2.x + v2.y * segDir2.y + v2.z * segDir2.z;
        final perp2 = math.sqrt(
          (v2.x - proj2 * segDir2.x) * (v2.x - proj2 * segDir2.x) +
              (v2.y - proj2 * segDir2.y) * (v2.y - proj2 * segDir2.y) +
              (v2.z - proj2 * segDir2.z) * (v2.z - proj2 * segDir2.z),
        );
        expect(perp2, closeTo(0.0, 0.2), reason: 'Port boundary passes directly through Cheek 2 slot center');
      }

      // Check flat callout floor edge connects cheek punches
      for (final raw in rawOpenings) {
        expect(raw.flatFloorEdgeP1.x, lessThan(60.0)); // Left cheek coupler hole
        expect(raw.flatFloorEdgeP2.x, greaterThan(250.0)); // Right cheek coupler hole
      }
    });

    test('2. Requirement 2: Height scaling to 150mm scales both ports symmetrically with 2 coupler slots at 50mm pitch', () {
      final contract = CmsProductContract.insideRiser90;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: dsf,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ],
      );

      controller.selectParameter('height');
      controller.evaluateMorph(150.0); // delta = +50mm
      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;

      // Base floor web remains invariant
      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      final b3 = scaled.bends.firstWhere((b) => b.id == 'B3');
      final b4 = scaled.bends.firstWhere((b) => b.id == 'B4');
      expect(b1.p1.x, closeTo(109.89, 0.1));
      expect(b2.p1.x, closeTo(207.89, 0.1));
      expect(b3.p1.y, closeTo(42.01, 0.1));
      expect(b4.p1.y, closeTo(185.68, 0.1));

      // Flanges FL1 and FL2 translate strictly in X by +50mm and -50mm
      final fl1 = scaled.bends.firstWhere((b) => b.id == 'FL1');
      final fl2 = scaled.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl1.p1.x, closeTo(303.64 + 50.0, 0.1));
      expect(fl2.p1.x, closeTo(14.14 - 50.0, 0.1));
      // Flange Y remains strictly unchanged
      expect(fl1.p1.y, closeTo(87.02, 0.1));
      expect(fl1.p2.y, closeTo(140.66, 0.1));

      // Coupler holes: 8 slots total (2 on each of the 4 ears) at 50mm pitch
      expect(scaled.punches.length, equals(8));
      final slot1 = scaled.punches.firstWhere((p) => p.id == 'SLOT_1');
      final slot2 = scaled.punches.firstWhere((p) => p.id == 'SLOT_2');
      final pitchTR = math.sqrt(math.pow(slot2.center.x - slot1.center.x, 2) + math.pow(slot2.center.y - slot1.center.y, 2));
      expect(pitchTR, closeTo(50.0, 0.1));

      final slot3 = scaled.punches.firstWhere((p) => p.id == 'SLOT_3');
      final slot4 = scaled.punches.firstWhere((p) => p.id == 'SLOT_4');
      final pitchTL = math.sqrt(math.pow(slot4.center.x - slot3.center.x, 2) + math.pow(slot4.center.y - slot3.center.y, 2));
      expect(pitchTL, closeTo(50.0, 0.1));

      // All 8 corner arcs are translated rigidly, retaining radius 10.0mm
      expect(scaled.arcs.length, equals(8));
      for (final arc in scaled.arcs) {
        expect(arc.radius, closeTo(10.0, 0.01));
      }

      // Check symmetrical ear growth:
      // Top-Right arc ARC_BND_1 center shifted by (+50, +50)
      final arc1 = scaled.arcs.firstWhere((a) => a.id == 'ARC_BND_1');
      expect(arc1.center.x, closeTo(310.71 + 50.0, 0.1));
      expect(arc1.center.y, closeTo(166.88 + 50.0, 0.1));

      // Bottom-Left arc ARC_BND_8 center shifted by (-50, -50)
      final arc8 = scaled.arcs.firstWhere((a) => a.id == 'ARC_BND_8');
      expect(arc8.center.x, closeTo(60.81 - 50.0, 0.1));
      expect(arc8.center.y, closeTo(7.07 - 50.0, 0.1));
    });

    test('3. Requirement 2: Height scaling to 60mm (< 95mm) reduces coupler slots to 1 centered per ear', () {
      final contract = CmsProductContract.insideRiser90;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: dsf,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ],
      );

      controller.selectParameter('height');
      controller.evaluateMorph(60.0); // delta = -40mm (< 95mm threshold)
      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;

      // Exactly 1 slot per ear (4 slots total)
      expect(scaled.punches.length, equals(4));

      // Verify each slot is centered on its ear
      final slotTR = scaled.punches.firstWhere((p) => p.id == 'SLOT_1');
      expect(slotTR.center.x, closeTo(283.14 - 20.0, 0.1));
      expect(slotTR.center.y, closeTo(193.04 - 20.0, 0.1));

      final slotTL = scaled.punches.firstWhere((p) => p.id == 'SLOT_3');
      expect(slotTL.center.x, closeTo(34.65 + 20.0, 0.1));
      expect(slotTL.center.y, closeTo(193.04 - 20.0, 0.1));

      final slotBR = scaled.punches.firstWhere((p) => p.id == 'SLOT_5');
      expect(slotBR.center.x, closeTo(283.14 - 20.0, 0.1));
      expect(slotBR.center.y, closeTo(34.65 + 20.0, 0.1));

      final slotBL = scaled.punches.firstWhere((p) => p.id == 'SLOT_7');
      expect(slotBL.center.x, closeTo(34.65 + 20.0, 0.1));
      expect(slotBL.center.y, closeTo(34.65 + 20.0, 0.1));
    });

    test('4. Width scaling from 100mm to 200mm expands base floor web symmetrically in X', () {
      final contract = CmsProductContract.insideRiser90;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: dsf,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ],
      );

      controller.selectParameter('width');
      controller.evaluateMorph(200.0); // delta = +100mm
      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;

      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      // B1 moves -50mm, B2 moves +50mm
      expect(b1.p1.x, closeTo(109.89 - 50.0, 0.1));
      expect(b2.p1.x, closeTo(207.89 + 50.0, 0.1));
      expect(b2.p1.x - b1.p1.x, closeTo(98.0 + 100.0, 0.1));
    });

    test('5. Requirement 3: Cover length is ~55mm centered on return flanges, touching bending area without overhanging', () {
      final coverData = TrunkingCoverGenerator.generateCover(dsf);

      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Cover top plate dimensions
      final topPlate = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      double cMinX = double.infinity, cMaxX = -double.infinity;
      double cMinY = double.infinity, cMaxY = -double.infinity;
      for (final v in topPlate.vertices) {
        if (v.x < cMinX) cMinX = v.x;
        if (v.x > cMaxX) cMaxX = v.x;
        if (v.y < cMinY) cMinY = v.y;
        if (v.y > cMaxY) cMaxY = v.y;
      }

      final coverLength = cMaxY - cMinY;
      expect(coverLength, closeTo(55.0, 0.5)); // Matches manufacturer length 55.0mm

      // Centered on return flanges (yMid ~ 113.84)
      final coverYMid = (cMinY + cMaxY) / 2.0;
      expect(coverYMid, closeTo(113.84, 0.5));

      // Extends ~0.68mm beyond the return flanges (87.02 to 140.66)
      expect(cMinY, closeTo(86.34, 0.5));
      expect(cMaxY, closeTo(141.34, 0.5));

      // Side drop flanges: exactly 2 flanges along the cheek edges
      final dropBends = coverDoc.bends.where((b) => b.direction == BendDirection.down).toList();
      expect(dropBends.length, equals(2));

      // Central mounting hole
      expect(coverDoc.punches.length, equals(1));
      final mountHole = coverDoc.punches.first;
      expect(mountHole.center.x, closeTo((cMinX + cMaxX) / 2.0, 0.1));
      expect(mountHole.center.y, closeTo(coverYMid, 0.1));
    });
  });
}
