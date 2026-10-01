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
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';

void main() {
  test('Verify 90 deg outside riser baseline folding and openings structure', () {
    final file = File('assets/dsf_templates/trunking_accessories/90_deg_outside_riser_100x100.dsf');
    expect(file.existsSync(), isTrue);

    final dsf = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    expect(dsf.outerContour.length, greaterThan(20));

    final foldResult = KinematicFoldEngine.foldDocument(dsf, foldProgress: 1.0);
    expect(foldResult.polygons.length, equals(5));

    final rawOpenings = Cms3DOpeningDetector.detectOpenings(
      document: dsf,
      foldResult: foldResult,
    );
    expect(rawOpenings.length, equals(2));


  });

  group('90° Outside Riser Dedicated Scaling & Port Detection', () {
    late DsfDocument dsf;

    setUp(() {
      final file = File('assets/dsf_templates/trunking_accessories/90_deg_outside_riser_100x100.dsf');
      expect(file.existsSync(), isTrue);
      dsf = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      dsf = dsf.copyWith(parameters: {'width': 100.0, 'height': 100.0});
    });

    test('1. Width scaling from 100mm to 200mm scales floor web in Y without altering length in X', () {
      final contract = CmsProductContract.outsideRiser90;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: dsf,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ],
      );

      controller.selectParameter('width');
      controller.evaluateMorph(200.0);
      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;

      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      expect(b2.p1.y - b1.p1.y, closeTo(198.0, 1.0), reason: 'Floor web expands to 200mm in Y');

      expect(scaled.outerContour[12].x, closeTo(227.81, 0.1), reason: 'Max X unchanged');
      expect(scaled.outerContour[5].x, closeTo(0.00, 0.1), reason: 'Min X unchanged');

      // Check arc start and end matching
      for (int i = 0; i < scaled.arcs.length; i++) {
        final a = scaled.arcs[i];
        final matchStart = scaled.outerContour.any((v) => v.distanceTo(a.startPoint) < 1.0);
        final matchEnd = scaled.outerContour.any((v) => v.distanceTo(a.endPoint) < 1.0);
        expect(matchStart, isTrue);
        expect(matchEnd, isTrue);
      }
    });

    test('2. Height scaling from 100mm to 150mm expands cheek mouth at 45° with 2 coupler slots', () {
      final contract = CmsProductContract.outsideRiser90;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: dsf,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ],
      );

      controller.selectParameter('height');
      controller.evaluateMorph(150.0);
      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;

      expect(scaled.punches.length, equals(8));

      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      expect(b1.p1.y, closeTo(106.0, 0.1));
      expect(b2.p1.y, closeTo(204.0, 0.1));

      final fl1 = scaled.bends.firstWhere((b) => b.id == 'FL1');
      expect(fl1.p1.y, closeTo(10.0 - 50.0, 0.5));

      for (int i = 0; i < scaled.arcs.length; i++) {
        final a = scaled.arcs[i];
        final matchStart = scaled.outerContour.any((v) => v.distanceTo(a.startPoint) < 1.0);
        final matchEnd = scaled.outerContour.any((v) => v.distanceTo(a.endPoint) < 1.0);
        expect(matchStart, isTrue);
        expect(matchEnd, isTrue);
      }
    });

    test('3. Height scaling to 60mm (< 95mm) reduces coupler slots to 1 per cheek mouth (4 total)', () {
      final contract = CmsProductContract.outsideRiser90;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: dsf,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ],
      );

      controller.selectParameter('height');
      controller.evaluateMorph(60.0);
      expect(controller.currentPreview, isNotNull);
      final scaled = controller.currentPreview!.scaledDocument;

      expect(scaled.punches.length, equals(4));
    });

    test('4. SS1: 3D folded openings have 45° angled normals depicting the 90° bending architecture', () {
      final foldResult = KinematicFoldEngine.foldDocument(dsf, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: dsf,
        foldResult: foldResult,
      );
      expect(rawOpenings.length, equals(2));

      final op1 = rawOpenings.firstWhere((op) => (op.floorEdgeP1.x + op.floorEdgeP2.x) / 2.0 < 100.0);
      final op2 = rawOpenings.firstWhere((op) => (op.floorEdgeP1.x + op.floorEdgeP2.x) / 2.0 > 100.0);

      // Port 1 normal is angled at 45° in (-X, -Z) pointing at coupler flap
      expect(op1.outwardNormal.x, closeTo(-1.0 / math.sqrt(2), 0.05));
      expect(op1.outwardNormal.y, closeTo(0.0, 0.05));
      expect(op1.outwardNormal.z, closeTo(-1.0 / math.sqrt(2), 0.05));

      // Port 2 normal is angled at 45° in (+X, -Z) pointing at coupler flap
      expect(op2.outwardNormal.x, closeTo(1.0 / math.sqrt(2), 0.05));
      expect(op2.outwardNormal.y, closeTo(0.0, 0.05));
      expect(op2.outwardNormal.z, closeTo(-1.0 / math.sqrt(2), 0.05));

      // Angle between the two port normals is 90 degrees (dot product == 0)
      final dot = op1.outwardNormal.x * op2.outwardNormal.x +
          op1.outwardNormal.y * op2.outwardNormal.y +
          op1.outwardNormal.z * op2.outwardNormal.z;
      expect(dot, closeTo(0.0, 1e-4), reason: 'Relative angle is exactly 90 degrees');

      final m1 = CmsOpeningPlaneAnalyzer.analyze(raw: op1, document: dsf, foldResult: foldResult);
      expect(m1.width, closeTo(100.0, 2.0));
      expect(m1.height, closeTo(100.0, 1.0));
      expect(m1.derivedMouthCorners.length, equals(4));

      // Verify that the port plane passes directly through the centers of the coupler holes
      final p1 = m1.derivedMouthCorners[0];
      final p3 = m1.derivedMouthCorners[1];
      final slot1Center = foldResult.punchCenters3D['SLOT_1']!;
      final slot2Center = foldResult.punchCenters3D['SLOT_2']!;

      // Direction of Cheek 1 port segment P1 -> P3
      final segDir = CadPoint3D(
        (p3.x - p1.x) / m1.height,
        (p3.y - p1.y) / m1.height,
        (p3.z - p1.z) / m1.height,
      );

      // Distance from SLOT_1 and SLOT_2 to line P1-P3 should be virtually zero
      final v1 = CadPoint3D(slot1Center.x - p1.x, slot1Center.y - p1.y, slot1Center.z - p1.z);
      final proj1 = v1.x * segDir.x + v1.y * segDir.y + v1.z * segDir.z;
      final perp1 = math.sqrt(
        (v1.x - proj1 * segDir.x) * (v1.x - proj1 * segDir.x) +
        (v1.y - proj1 * segDir.y) * (v1.y - proj1 * segDir.y) +
        (v1.z - proj1 * segDir.z) * (v1.z - proj1 * segDir.z),
      );
      expect(perp1, closeTo(0.0, 0.1), reason: 'Port boundary passes directly through SLOT_1 center');

      final v2 = CadPoint3D(slot2Center.x - p1.x, slot2Center.y - p1.y, slot2Center.z - p1.z);
      final proj2 = v2.x * segDir.x + v2.y * segDir.y + v2.z * segDir.z;
      final perp2 = math.sqrt(
        (v2.x - proj2 * segDir.x) * (v2.x - proj2 * segDir.x) +
        (v2.y - proj2 * segDir.y) * (v2.y - proj2 * segDir.y) +
        (v2.z - proj2 * segDir.z) * (v2.z - proj2 * segDir.z),
      );
      expect(perp2, closeTo(0.0, 0.1), reason: 'Port boundary passes directly through SLOT_2 center');
    });

    test('5. Cover generation for 90° outside riser matches flanged area length in X, extends at 45° at both ends, and scales width in Y', () {
      final coverData = TrunkingCoverGenerator.generateCover(dsf);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Cover top plate main face
      final topPlate = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      final verts = topPlate.vertices;
      final minX = verts.map((v) => v.x).reduce(math.min);
      final maxX = verts.map((v) => v.x).reduce(math.max);
      final minY = verts.map((v) => v.y).reduce(math.min);
      final maxY = verts.map((v) => v.y).reduce(math.max);

      // Main flat roof length in X between knees (~143.2mm)
      expect(maxX - minX, closeTo(143.17, 1.0), reason: 'Main roof length in X spans between knees');
      // Channel width in Y matches distance between B1 and B2 (~98mm + 2*clearance)
      expect(maxY - minY, closeTo(98.0 + 2 * TrunkingCoverGenerator.defaultCoverClearanceOffset, 1.0), reason: 'Cover width in Y matches channel width');

      // 2 roof bends (45°) and 6 side flange bends (90°) = 8 bends total
      expect(coverDoc.bends.length, equals(8));
      final roofBends = coverDoc.bends.where((b) => (b.targetAngleDeg - 45.0).abs() < 1.0).toList();
      expect(roofBends.length, equals(2), reason: '2 roof bends at 45° at both ends');

      // Both 45° angled extension faces exist
      expect(coverDoc.faces.any((f) => f.id == 'COVER_EXT_FACE_1'), isTrue);
      expect(coverDoc.faces.any((f) => f.id == 'COVER_EXT_FACE_2'), isTrue);

      // Verify 3D folding: extended portions slope down at 45° towards coupler flaps
      final coverMesh = KinematicFoldEngine.foldDocument(coverDoc, foldProgress: 1.0);
      final ext1Poly = coverMesh.polygons.firstWhere((p) => p.faceId == 'COVER_EXT_FACE_1');
      final ext2Poly = coverMesh.polygons.firstWhere((p) => p.faceId == 'COVER_EXT_FACE_2');
      expect(ext1Poly.normal.x.abs(), closeTo(0.707, 0.05), reason: 'Ext 1 slopes at 45°');
      expect(ext1Poly.normal.z, closeTo(0.707, 0.05), reason: 'Ext 1 slopes downwards');
      expect(ext2Poly.normal.x.abs(), closeTo(0.707, 0.05), reason: 'Ext 2 slopes at 45°');
      expect(ext2Poly.normal.z, closeTo(0.707, 0.05), reason: 'Ext 2 slopes downwards');

      // Test scaling template width to 200mm
      final contract = CmsProductContract.outsideRiser90;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: dsf,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ],
      );
      controller.selectParameter('width');
      controller.evaluateMorph(200.0);
      final scaledDoc = controller.currentPreview!.scaledDocument;

      final scaledCoverData = TrunkingCoverGenerator.generateCover(scaledDoc);
      expect(scaledCoverData, isNotNull);
      final scaledCoverDoc = scaledCoverData!.document;
      final scaledTop = scaledCoverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      final sVerts = scaledTop.vertices;
      final sMinX = sVerts.map((v) => v.x).reduce(math.min);
      final sMaxX = sVerts.map((v) => v.x).reduce(math.max);
      final sMinY = sVerts.map((v) => v.y).reduce(math.min);
      final sMaxY = sVerts.map((v) => v.y).reduce(math.max);

      // Cover width along Y increases to ~198mm (width expands)
      expect(sMaxY - sMinY, closeTo(198.0 + 2 * TrunkingCoverGenerator.defaultCoverClearanceOffset, 1.0), reason: 'Cover width expands in Y');
      // Cover length along X remains 143.17mm
      expect(sMaxX - sMinX, closeTo(143.17, 1.0), reason: 'Cover length in X unchanged');
    });

    test('6. Combined scaling (width=220, height=70) preserves all 8 corner arcs and properly positions coupler holes', () {
      final contract = CmsProductContract.outsideRiser90;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: dsf,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        ],
      );

      // First scale width to 220
      controller.selectParameter('width');
      controller.evaluateMorph(220.0);

      // Next scale height to 70 (< 95mm)
      controller.selectParameter('height');
      controller.evaluateMorph(70.0);

      final scaled = controller.currentPreview!.scaledDocument;

      // 1. All 8 arcs must match outer contour vertices
      expect(scaled.arcs.length, equals(8));
      for (int i = 0; i < scaled.arcs.length; i++) {
        final a = scaled.arcs[i];
        final matchStart = scaled.outerContour.any((v) => v.distanceTo(a.startPoint) < 1.0);
        final matchEnd = scaled.outerContour.any((v) => v.distanceTo(a.endPoint) < 1.0);
        expect(matchStart, isTrue, reason: 'Arc $i start matches contour');
        expect(matchEnd, isTrue, reason: 'Arc $i end matches contour');
      }

      // 2. Since height is 70 (< 95mm), exactly 4 coupler punches (1 per cheek mouth)
      expect(scaled.punches.length, equals(4));

      // 3. Punches must NOT overlap bends B1 or B2
      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      for (final p in scaled.punches) {
        expect((p.center.y - b1.p1.y).abs(), greaterThan(5.0), reason: 'Punch ${p.id} does not overlap B1');
        expect((p.center.y - b2.p1.y).abs(), greaterThan(5.0), reason: 'Punch ${p.id} does not overlap B2');
      }
    });
  });
}
