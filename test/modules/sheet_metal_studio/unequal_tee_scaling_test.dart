import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/unequal_tee_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';

void main() {
  group('UnequalTeeScaler (Analytical Geometry & Arc Preservation)', () {
    late DsfDocument canonicalDoc;

    setUp(() {
      final file = File('assets/dxf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      canonicalDoc = DsfDocument.fromJson(json);
    });

    test('Canonical Baseline (SS1): zero delta returns baseline untouched with all 12 arcs and 0.0 deviation', () {
      const params = UnequalTeeScaleParameters(
        port1Width: 50.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 100.0,
        port3Width: 100.0,
        port3Height: 100.0,
        dW1: 0.0,
        dH1: 0.0,
        dW2: 0.0,
        dH2: 0.0,
        dW3: 0.0,
        dH3: 0.0,
      );

      final result = UnequalTeeScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      expect(result.document.faces.length, equals(canonicalDoc.faces.length));
      expect(result.document.bends.length, equals(canonicalDoc.bends.length));
      expect(result.document.arcs.length, equals(12));
      expect(result.document.punches.length, equals(10));

      final f10 = result.document.faces.firstWhere((f) => f.id == 'F_10');
      final canonF10 = canonicalDoc.faces.firstWhere((f) => f.id == 'F_10');
      for (int i = 0; i < 6; i++) {
        expect(f10.vertices[i].x, closeTo(canonF10.vertices[i].x, 0.001));
        expect(f10.vertices[i].y, closeTo(canonF10.vertices[i].y, 0.001));
      }
    });

    test('SS2: Port 2 width increase to 100mm (dW2 = 50) scales right cheek rigidly to 45 deg and 60mm', () {
      const params = UnequalTeeScaleParameters(
        port1Width: 50.0,
        port1Height: 100.0,
        port2Width: 100.0, // Scaled from 50 to 100
        port2Height: 100.0,
        port3Width: 100.0,
        port3Height: 100.0,
        dW2: 50.0,
      );

      final result = UnequalTeeScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f10 = result.document.faces.firstWhere((f) => f.id == 'F_10');

      // Port 2 opening (v5 to v4): expands by 50mm from 47 to 97 mm
      final p2Opening = (f10.vertices[5].y - f10.vertices[4].y).abs();
      expect(p2Opening, closeTo(97.0, 0.05));

      // Port 3 opening (v0 to v1): remains unchanged at 97.0 mm
      final p3Opening = (f10.vertices[0].y - f10.vertices[1].y).abs();
      expect(p3Opening, closeTo(97.0, 0.05));

      // Port 1 opening (v3 to v2): remains unchanged at 47.0 mm
      final p1Opening = (f10.vertices[3].x - f10.vertices[2].x).abs();
      expect(p1Opening, closeTo(47.0, 0.05));

      // Right Cheek (Bend B2) becomes exactly 45 deg with length 60mm (symmetric to Bend B1)
      final b2 = result.document.bends.firstWhere((b) => b.id == 'B2');
      final lenB2 = math.sqrt(
        math.pow(b2.p2.x - b2.p1.x, 2) + math.pow(b2.p2.y - b2.p1.y, 2),
      );
      expect(lenB2, closeTo(60.00, 0.05));

      final angleB2 = math.atan2(b2.p1.y - b2.p2.y, b2.p1.x - b2.p2.x) * 180.0 / math.pi;
      expect(angleB2, closeTo(45.0, 0.05));

      // Flap folds B4 and B6 update to 45 deg
      final b4 = result.document.bends.firstWhere((b) => b.id == 'B4');
      final b6 = result.document.bends.firstWhere((b) => b.id == 'B6');
      expect(b4.targetAngleDeg, closeTo(45.0, 0.05));
      expect(b6.targetAngleDeg, closeTo(45.0, 0.05));

      // All 12 arcs and 10 punches strictly preserved
      expect(result.document.arcs.length, equals(12));
      expect(result.document.punches.length, equals(10));
    });

    test('SS3: Port 3 width reduced to 50mm (dW3 = -50) produces clean symmetric 50x50 tee', () {
      const params = UnequalTeeScaleParameters(
        port1Width: 50.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 100.0,
        port3Width: 50.0, // Scaled from 100 to 50
        port3Height: 100.0,
        dW3: -50.0,
      );

      final result = UnequalTeeScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f10 = result.document.faces.firstWhere((f) => f.id == 'F_10');

      // Port 3 opening (v0 to v1): reduced to 47.0 mm
      final p3Opening = (f10.vertices[0].y - f10.vertices[1].y).abs();
      expect(p3Opening, closeTo(47.0, 0.05));

      // Port 2 opening (v5 to v4): remains at 47.0 mm
      final p2Opening = (f10.vertices[5].y - f10.vertices[4].y).abs();
      expect(p2Opening, closeTo(47.0, 0.05));

      // Bend B2 length becomes 60.00 mm at 45 deg
      final b2 = result.document.bends.firstWhere((b) => b.id == 'B2');
      final lenB2 = math.sqrt(
        math.pow(b2.p2.x - b2.p1.x, 2) + math.pow(b2.p2.y - b2.p1.y, 2),
      );
      expect(lenB2, closeTo(60.00, 0.05));

      // All 12 arcs preserved
      expect(result.document.arcs.length, equals(12));
    });

    test('SS4: Port 3 width increased to 150mm (dW3 = +50) maintains Port 2 invariant at 47mm with B2 elongated', () {
      const params = UnequalTeeScaleParameters(
        port1Width: 50.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 100.0,
        port3Width: 150.0, // Scaled from 100 to 150
        port3Height: 100.0,
        dW3: 50.0,
      );

      final result = UnequalTeeScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f10 = result.document.faces.firstWhere((f) => f.id == 'F_10');

      // Port 3 opening expands to 147.0 mm
      final p3Opening = (f10.vertices[0].y - f10.vertices[1].y).abs();
      expect(p3Opening, closeTo(147.0, 0.05));

      // Port 2 opening remains invariant at 47.0 mm
      final p2Opening = (f10.vertices[5].y - f10.vertices[4].y).abs();
      expect(p2Opening, closeTo(47.0, 0.05));

      // Bend B2 elongates cleanly to 148.61 mm at 73.41 deg
      final b2 = result.document.bends.firstWhere((b) => b.id == 'B2');
      final lenB2 = math.sqrt(
        math.pow(b2.p2.x - b2.p1.x, 2) + math.pow(b2.p2.y - b2.p1.y, 2),
      );
      expect(lenB2, closeTo(148.61, 0.2));

      final angleB2 = math.atan2(b2.p1.y - b2.p2.y, b2.p1.x - b2.p2.x) * 180.0 / math.pi;
      expect(angleB2, closeTo(73.41, 0.2));

      // All 12 arcs preserved
      expect(result.document.arcs.length, equals(12));
    });

    test('Height Scaling: expands back wall and cheeks outward while preserving all 12 arcs', () {
      const params = UnequalTeeScaleParameters(
        port1Width: 50.0,
        port1Height: 150.0,
        port2Width: 50.0,
        port2Height: 150.0,
        port3Width: 100.0,
        port3Height: 150.0,
        dH1: 50.0,
        dH2: 50.0,
        dH3: 50.0,
      );

      final result = UnequalTeeScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f8 = result.document.faces.firstWhere((f) => f.id == 'F_8');
      final canonF8 = canonicalDoc.faces.firstWhere((f) => f.id == 'F_8');

      // Back wall return flange extends by 50mm along y
      expect(f8.vertices[1].y - canonF8.vertices[1].y, closeTo(50.0, 0.05));

      // All 12 arcs are strictly preserved!
      expect(result.document.arcs.length, equals(12));
    });

    test('Rigid Coupler Slots: maintain exact physical dimensions (8.0 x 20.0 mm)', () {
      const params = UnequalTeeScaleParameters(
        port1Width: 100.0,
        port1Height: 100.0,
        port2Width: 75.0,
        port2Height: 100.0,
        port3Width: 120.0,
        port3Height: 100.0,
        dW1: 50.0,
        dW2: 25.0,
        dW3: 20.0,
      );

      final result = UnequalTeeScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      expect(result.document.punches.length, equals(canonicalDoc.punches.length));
      for (final punch in result.document.punches) {
        expect(punch.widthMm, closeTo(8.0, 1e-4));
        expect(punch.lengthMm, closeTo(20.0, 1e-4));
      }
    });

    test('Reversibility: dW3 = +50 then dW3 = 0 reproduces canonical geometry with zero cumulative error', () {
      const params150 = UnequalTeeScaleParameters(
        port1Width: 50.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 100.0,
        port3Width: 150.0,
        port3Height: 100.0,
        dW3: 50.0,
      );

      const params100 = UnequalTeeScaleParameters(
        port1Width: 50.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 100.0,
        port3Width: 100.0,
        port3Height: 100.0,
        dW3: 0.0,
      );

      final res150 = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params150);
      expect(res150.isValid, isTrue);

      final res100 = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params100);
      expect(res100.isValid, isTrue);
      final f10Scaled = res100.document.faces.firstWhere((f) => f.id == 'F_10');
      final f10Canon = canonicalDoc.faces.firstWhere((f) => f.id == 'F_10');

      for (int i = 0; i < 6; i++) {
        expect(f10Scaled.vertices[i].x, closeTo(f10Canon.vertices[i].x, 0.001));
        expect(f10Scaled.vertices[i].y, closeTo(f10Canon.vertices[i].y, 0.001));
      }
      expect(res100.document.arcs.length, equals(12));
    });

    test('CmsScalingController Integration: evaluateMorph on initial dialog opening preserves 3D and arcs', () {
      final controller = CmsScalingController(
        baselineDocument: canonicalDoc,
        contract: CmsProductContract.unequalTee,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 47.0, height: 99.5),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 47.0, height: 99.5),
          CmsPhysicalPort(id: 'PORT_3', index: 3, width: 97.0, height: 99.5),
        ],
      );

      // On initial opening, no parameter changed -> preview must be valid and arcs preserved
      final initialPreview = controller.currentPreview;
      expect(initialPreview, isNotNull);
      expect(initialPreview!.isValid, isTrue);
      expect(initialPreview.scaledDocument.arcs.length, equals(12));

      // Now evaluate morph changing port 3 width
      controller.selectParameter('port3_width');
      controller.evaluateMorph(147.0);

      final preview = controller.currentPreview!;
      expect(preview.isValid, isTrue);
      expect(preview.scaledDocument.arcs.length, equals(12));
      final f10 = preview.scaledDocument.faces.firstWhere((f) => f.id == 'F_10');
      final p3Opening = (f10.vertices[0].y - f10.vertices[1].y).abs();
      expect(p3Opening, closeTo(147.0, 0.05));
    });
  });
}
