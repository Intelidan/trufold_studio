// =============================================================================
// cms_3d_opening_discovery_test.dart
//
// Sprint 2 verification tests for 3D opening discovery and plane analysis
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sprint 2).
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_dsf_importer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';

void main() {
  group('3D Physical Opening Discovery (Sprint 2)', () {
    test('1. Discovers and accurately measures 2 physical openings from 45_deg_bend_100x100.dsf 3D mesh', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      expect(file.existsSync(), isTrue);

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      // 1. 3D Forward-kinematics fold
      final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      // 2. Detect 3D physical openings
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: doc,
        foldResult: foldResult,
      );

      // 45° Bend must expose exactly 2 physical openings (Port 1 & Port 2)
      expect(rawOpenings.length, equals(2));

      // 3. Analyze each opening plane and measure W x H
      final measuredList = rawOpenings.map((raw) {
        return CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: doc);
      }).toList();

      expect(measuredList.length, equals(2));

      final expectedWidth = (doc.parameters['width'] as num?)?.toDouble() ?? 100.0;

      // Verify Opening 1
      final op1 = measuredList[0];
      expect(op1.width, closeTo(expectedWidth, 5.0), reason: 'Nominal width is $expectedWidth mm');
      expect(op1.height, greaterThanOrEqualTo(50.0), reason: 'Sidewall height is positive');
      expect(op1.normal.z.abs(), closeTo(0.0, 0.05), reason: 'Normal must be horizontal');

      // Verify Opening 2
      final op2 = measuredList[1];
      expect(op2.width, closeTo(expectedWidth, 5.0), reason: 'Nominal width is $expectedWidth mm');
      expect(op2.height, greaterThanOrEqualTo(50.0), reason: 'Sidewall height is positive');
      expect(op2.normal.z.abs(), closeTo(0.0, 0.05), reason: 'Normal must be horizontal');

      // Openings must have distinct orientations (45° miter bend)
      final dot = op1.normal.x * op2.normal.x + op1.normal.y * op2.normal.y;
      expect(dot, lessThan(0.99), reason: 'Port 1 and Port 2 must point in different directions');

      // Convert to clean candidate objects
      final cand1 = op1.toCandidate();
      expect(cand1.isReliefOrNotch, isFalse);
      expect(cand1.width, closeTo(expectedWidth, 5.0));
    });

    test('2. Discovers both physical openings on 45_deg_inside_riser_100x100 with 3 bends', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_inside_riser_100x100.dsf');
      expect(file.existsSync(), isTrue);

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      var doc = DsfDocument.fromJson(json);

      final bends = doc.bends;

      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: doc.outerContour,
        bends: bends,
        cutLines: doc.cutLines,
      );

      doc = doc.copyWith(
        bends: decomp.connectedBends,
        faces: decomp.faces,
        baseFaceId: decomp.baseFaceId,
      );

      final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: doc,
        foldResult: foldResult,
      );

      // 45° Inside Riser must discover BOTH physical openings:
      // Port 1: Top horizontal opening
      // Port 2: Bottom 45° angled opening
      expect(rawOpenings.length, equals(2), reason: 'Must detect exactly 2 openings for inside riser');

      final measuredList = rawOpenings.map((raw) {
        return CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: doc, foldResult: foldResult);
      }).toList();

      expect(measuredList.length, equals(2));
      for (final op in measuredList) {
        expect(op.width, closeTo(96.0, 5.0), reason: 'Width should be ~96mm');
        expect(op.height, closeTo(100.0, 5.0), reason: 'Height must match physical channel sidewall (~96-104mm) without extending over the cheek');
      }
    });

    test('3. Discovers both physical openings on 45_deg_outside_riser_100x100 with 2 bends & 2 flanges', () async {
      final dxfFile = File('assets/dxf_templates/trunking_accessories/45_deg_outside_riser_100x100.dxf');
      expect(dxfFile.existsSync(), isTrue);
      final dxfContent = dxfFile.readAsStringSync();

      var doc = DxfDsfImporter.importDxf(
        dxfContent,
        productType: 'outside_riser',
        itemName: '45_deg_outside_riser_100x100',
      );

      final bends = [
        FoldBendLine(
          id: 'B1',
          p1: const CadPoint2D(106.0, 30.0),
          p2: const CadPoint2D(106.0, 93.65),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.bend,
        ),
        FoldBendLine(
          id: 'B2',
          p1: const CadPoint2D(203.0, 30.0),
          p2: const CadPoint2D(203.0, 93.65),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.bend,
        ),
        FoldBendLine(
          id: 'FL1',
          p1: const CadPoint2D(10.0, 30.0),
          p2: const CadPoint2D(10.0, 123.42),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.flange,
        ),
        FoldBendLine(
          id: 'FL2',
          p1: const CadPoint2D(299.0, 30.0),
          p2: const CadPoint2D(299.0, 123.40),
          targetAngleDeg: 90.0,
          direction: BendDirection.up,
          role: BendLineRole.flange,
        ),
      ];

      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: doc.outerContour,
        bends: bends,
        cutLines: doc.cutLines,
        preferredBaseFaceId: 'F_1', // Intentionally stale cheek
      );

      doc = doc.copyWith(
        bends: decomp.connectedBends,
        faces: decomp.faces,
        baseFaceId: decomp.baseFaceId,
      );

      final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: doc,
        foldResult: foldResult,
      );

      expect(rawOpenings.length, equals(2), reason: 'Must detect exactly 2 openings for outside riser');

      final measuredList = rawOpenings.map((raw) {
        return CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: doc, foldResult: foldResult);
      }).toList();

      expect(measuredList.length, equals(2));
      for (final op in measuredList) {
        expect(op.width, closeTo(97.0, 5.0), reason: 'Width should be ~97mm');
        expect(op.height, closeTo(98.0, 5.0), reason: 'Height should match sidewall height ~96-100mm');
      }
    });
  });
}
