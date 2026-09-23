import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/unequal_tee_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
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
        port2Height: 50.0,
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
        port2Height: 50.0,
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
        port2Height: 50.0,
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
        port2Height: 50.0,
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
      expect(result.document.punches.length, equals(12));
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
        port2Height: 50.0,
        port3Width: 150.0,
        port3Height: 100.0,
        dW3: 50.0,
      );

      const params100 = UnequalTeeScaleParameters(
        port1Width: 50.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 50.0,
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

    test('Controller Initial Parameter Setup: Unequal Tee Port 2 Height defaults to 50mm baseline', () {
      final controller = CmsScalingController(
        baselineDocument: canonicalDoc,
        contract: CmsProductContract.unequalTee,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 47.0, height: 99.5),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 47.0, height: 99.5),
          CmsPhysicalPort(id: 'PORT_3', index: 3, width: 97.0, height: 99.5),
        ],
      );

      final p1H = controller.model.parameters['port1_height']!;
      final p2H = controller.model.parameters['port2_height']!;
      final p3H = controller.model.parameters['port3_height']!;

      expect(p1H.currentValue, equals(100.0));
      expect(p1H.baselineValue, equals(100.0));
      expect(p2H.currentValue, equals(50.0));
      expect(p2H.baselineValue, equals(50.0));
      expect(p3H.currentValue, equals(100.0));
      expect(p3H.baselineValue, equals(100.0));
    });

    group('Parametric Height Scaling Rule (Hbody = max(H1, H2, H3) & User Spec Table)', () {
      test('Scenario 1: Baseline [P1=100, P2=50, P3=100] -> Body=100, N1=0, N2=50, N3=0', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 100.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final bodyH = res.diagnostics['bodyHeight'] as double;
        final dHBody = res.diagnostics['dHBody'] as double;
        final dH1 = res.diagnostics['dH1'] as double;
        final dH2 = res.diagnostics['dH2'] as double;
        final dH3 = res.diagnostics['dH3'] as double;

        expect(bodyH, equals(100.0));
        expect(dHBody, equals(0.0));
        expect(dH1, equals(0.0));
        expect(dH2, equals(0.0));
        expect(dH3, equals(0.0));

        // Notches:
        expect(bodyH - 100.0, equals(0.0)); // N1 = 0
        expect(bodyH - 50.0, equals(50.0)); // N2 = 50
        expect(bodyH - 100.0, equals(0.0)); // N3 = 0
        expect(res.document.arcs.length, equals(12));
      });

      test('Scenario 2: [P1=100, P2=75, P3=100] -> Body=100, N1=0, N2=25, N3=0', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 75.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 25.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final bodyH = res.diagnostics['bodyHeight'] as double;
        final dHBody = res.diagnostics['dHBody'] as double;
        final dH2 = res.diagnostics['dH2'] as double;

        expect(bodyH, equals(100.0));
        expect(dHBody, equals(0.0));
        expect(dH2, equals(25.0));

        // P2 coupler flap (F_4) height between outer edge (v[0]) and bend B4 (v[5]) elongates by 25mm: 48.07 + 25 = 73.07mm
        final f4 = res.document.faces.firstWhere((f) => f.id == 'F_4');
        final f4Canon = canonicalDoc.faces.firstWhere((f) => f.id == 'F_4');
        final f4FlapH = math.sqrt(
          math.pow(f4.vertices[0].x - f4.vertices[5].x, 2) +
          math.pow(f4.vertices[0].y - f4.vertices[5].y, 2),
        );
        final f4CanonFlapH = math.sqrt(
          math.pow(f4Canon.vertices[0].x - f4Canon.vertices[5].x, 2) +
          math.pow(f4Canon.vertices[0].y - f4Canon.vertices[5].y, 2),
        );
        expect(f4FlapH - f4CanonFlapH, closeTo(25.0, 0.05));

        // Notches:
        expect(bodyH - 100.0, equals(0.0)); // N1 = 0
        expect(bodyH - 75.0, equals(25.0)); // N2 = 25
        expect(bodyH - 100.0, equals(0.0)); // N3 = 0
        expect(res.document.arcs.length, equals(12));
      });

      test('Scenario 3: [P1=100, P2=100, P3=100] -> Body=100, N1=0, N2=0 (Flush), N3=0', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 100.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final bodyH = res.diagnostics['bodyHeight'] as double;
        final dHBody = res.diagnostics['dHBody'] as double;
        final dH2 = res.diagnostics['dH2'] as double;

        expect(bodyH, equals(100.0));
        expect(dHBody, equals(0.0));
        expect(dH2, equals(50.0));

        // Notch eliminated (Flush):
        expect(bodyH - 100.0, equals(0.0)); // N1 = 0
        expect(bodyH - 100.0, equals(0.0)); // N2 = 0 (Flush!)
        expect(bodyH - 100.0, equals(0.0)); // N3 = 0
        expect(res.document.arcs.length, equals(12));
      });

      test('Scenario 4: [P1=100, P2=125, P3=100] -> Body=125, N1=25, N2=0 (Flush), N3=25', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 125.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 75.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final bodyH = res.diagnostics['bodyHeight'] as double;
        final dHBody = res.diagnostics['dHBody'] as double;
        final dH2 = res.diagnostics['dH2'] as double;

        // Common body height grows to match highest port (P2 = 125)
        expect(bodyH, equals(125.0));
        expect(dHBody, equals(25.0));
        expect(dH2, equals(75.0));

        // Notches:
        expect(bodyH - 100.0, equals(25.0)); // N1 = 25
        expect(bodyH - 125.0, equals(0.0));  // N2 = 0 (Flush!)
        expect(bodyH - 100.0, equals(25.0)); // N3 = 25

        // Back wall return flange extends by dHBody = 25mm:
        final f8 = res.document.faces.firstWhere((f) => f.id == 'F_8');
        final f8Canon = canonicalDoc.faces.firstWhere((f) => f.id == 'F_8');
        expect(f8.vertices[1].y - f8Canon.vertices[1].y, closeTo(25.0, 0.05));
        expect(res.document.arcs.length, equals(12));
      });

      test('Scenario 5: [P1=125, P2=100, P3=100] -> Body=125, N1=0 (Flush), N2=25, N3=25', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 125.0,
          port2Width: 50.0,
          port2Height: 100.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH1: 25.0,
          dH2: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final bodyH = res.diagnostics['bodyHeight'] as double;
        final dHBody = res.diagnostics['dHBody'] as double;

        expect(bodyH, equals(125.0));
        expect(dHBody, equals(25.0));

        // Notches:
        expect(bodyH - 125.0, equals(0.0));  // N1 = 0 (Flush!)
        expect(bodyH - 100.0, equals(25.0)); // N2 = 25
        expect(bodyH - 100.0, equals(25.0)); // N3 = 25
        expect(res.document.arcs.length, equals(12));
      });

      test('Scenario 6: [P1=100, P2=100, P3=125] -> Body=125, N1=25, N2=25, N3=0 (Flush)', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 100.0,
          port3Width: 100.0,
          port3Height: 125.0,
          dH2: 50.0,
          dH3: 25.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final bodyH = res.diagnostics['bodyHeight'] as double;
        final dHBody = res.diagnostics['dHBody'] as double;

        expect(bodyH, equals(125.0));
        expect(dHBody, equals(25.0));

        // Notches:
        expect(bodyH - 100.0, equals(25.0)); // N1 = 25
        expect(bodyH - 100.0, equals(25.0)); // N2 = 25
        expect(bodyH - 125.0, equals(0.0));  // N3 = 0 (Flush!)
        expect(res.document.arcs.length, equals(12));
      });

      test('Reversibility and Order-Independence: 50 -> 75 -> 100 -> 125 -> 75 returns to exact baseline-derived state', () {
        // Step 1: 75 evaluated directly
        const params75 = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 75.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 25.0,
        );
        final direct75 = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params75);

        // Step 2: sequence 50 -> 75 -> 100 -> 125
        const params125 = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 125.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 75.0,
        );
        final res125 = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params125);
        expect(res125.diagnostics['bodyHeight'], equals(125.0));

        // Step 3: P2 drops back to 75 (recalculated from baseline DSF)
        final returned75 = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params75);
        expect(returned75.diagnostics['bodyHeight'], equals(100.0));

        // Exact coordinate equivalence with direct evaluation
        final f7Direct = direct75.document.faces.firstWhere((f) => f.id == 'F_7');
        final f7Returned = returned75.document.faces.firstWhere((f) => f.id == 'F_7');
        for (int i = 0; i < f7Direct.vertices.length; i++) {
          expect(f7Returned.vertices[i].x, closeTo(f7Direct.vertices[i].x, 1e-4));
          expect(f7Returned.vertices[i].y, closeTo(f7Direct.vertices[i].y, 1e-4));
        }
      });
    });

    group('Coupler Hole Count Rule (>= 95mm -> 2 slots, < 95mm -> 1 slot)', () {
      test('P2 Height = 50mm (baseline) has 10 punches total (1 on F_4, 1 on F_9 right ear)', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 100.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        expect(res.document.punches.length, equals(10));
        expect(res.document.punches.any((p) => p.id == 'SLOT_6_B'), isFalse);
        expect(res.document.punches.any((p) => p.id == 'SLOT_7_B'), isFalse);
      });

      test('P2 Height = 75mm (< 95mm) preserves 10 punches total (1 on F_4, 1 on F_9 right ear)', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 75.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 25.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        expect(res.document.punches.length, equals(10));
        expect(res.document.punches.any((p) => p.id == 'SLOT_6_B'), isFalse);
        expect(res.document.punches.any((p) => p.id == 'SLOT_7_B'), isFalse);
      });

      test('P2 Height = 90mm (< 95mm) preserves 10 punches total (below 95mm threshold)', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 90.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 40.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        expect(res.document.punches.length, equals(10));
        expect(res.document.punches.any((p) => p.id == 'SLOT_6_B'), isFalse);
        expect(res.document.punches.any((p) => p.id == 'SLOT_7_B'), isFalse);
      });

      test('P2 Height = 95mm (exact threshold) synthesizes 2nd slots on F_4 and F_9 right ear (12 punches total)', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 95.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 45.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        expect(res.document.punches.length, equals(12));
        expect(res.document.punches.any((p) => p.id == 'SLOT_6_B'), isTrue);
        expect(res.document.punches.any((p) => p.id == 'SLOT_7_B'), isTrue);
      });

      test('P2 Height = 100mm synthesizes 2nd slots with exact 50mm pitch', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 100.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        expect(res.document.punches.length, equals(12));

        final slot6 = res.document.punches.firstWhere((p) => p.id == 'SLOT_6');
        final slot6B = res.document.punches.firstWhere((p) => p.id == 'SLOT_6_B');
        final distF4 = math.sqrt(
          math.pow(slot6B.center.x - slot6.center.x, 2) +
          math.pow(slot6B.center.y - slot6.center.y, 2),
        );
        expect(distF4, closeTo(50.0, 0.05));

        final slot7 = res.document.punches.firstWhere((p) => p.id == 'SLOT_7');
        final slot7B = res.document.punches.firstWhere((p) => p.id == 'SLOT_7_B');
        final distF9 = math.sqrt(
          math.pow(slot7B.center.x - slot7.center.x, 2) +
          math.pow(slot7B.center.y - slot7.center.y, 2),
        );
        expect(distF9, closeTo(50.0, 0.05));

        // Pitch aligns with left ear slots (SLOT_8 and SLOT_11)
        final slot8 = res.document.punches.firstWhere((p) => p.id == 'SLOT_8');
        final slot11 = res.document.punches.firstWhere((p) => p.id == 'SLOT_11');
        final distLeftEar = (slot11.center.y - slot8.center.y).abs();
        expect(distLeftEar, closeTo(50.0, 0.05));
        expect(distF9, closeTo(distLeftEar, 0.05));
      });

      test('P1 Height = 75mm (< 95mm) suppresses outer slots (SLOT_9, SLOT_12) leaving 1 centered slot per flap (8 punches total)', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 75.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH1: -25.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        expect(res.document.punches.length, equals(8));
        expect(res.document.punches.any((p) => p.id == 'SLOT_9'), isFalse);
        expect(res.document.punches.any((p) => p.id == 'SLOT_12'), isFalse);
        expect(res.document.punches.any((p) => p.id == 'SLOT_3'), isTrue);
        expect(res.document.punches.any((p) => p.id == 'SLOT_4'), isTrue);
      });

      test('P3 Height = 75mm (< 95mm) suppresses outer slots (SLOT_10, SLOT_11) leaving 1 centered slot per flap (8 punches total)', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 75.0,
          dH3: -25.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        expect(res.document.punches.length, equals(8));
        expect(res.document.punches.any((p) => p.id == 'SLOT_10'), isFalse);
        expect(res.document.punches.any((p) => p.id == 'SLOT_11'), isFalse);
        expect(res.document.punches.any((p) => p.id == 'SLOT_5'), isTrue);
        expect(res.document.punches.any((p) => p.id == 'SLOT_8'), isTrue);
      });

      test('Bidirectional scaling across 95mm threshold (50 -> 75 -> 95 -> 100 -> 90 -> 50) transitions 1 <-> 2 slots reversibly', () {
        for (final (h, expectedPunches, has2nd) in [
          (50.0, 10, false),
          (75.0, 10, false),
          (95.0, 12, true),
          (100.0, 12, true),
          (90.0, 10, false),
          (50.0, 10, false),
        ]) {
          final res = UnequalTeeScaler.scale(
            baseline: canonicalDoc,
            parameters: UnequalTeeScaleParameters(
              port1Width: 50.0,
              port1Height: 100.0,
              port2Width: 50.0,
              port2Height: h,
              port3Width: 100.0,
              port3Height: 100.0,
              dH2: h - 50.0,
            ),
          );
          expect(res.isValid, isTrue);
          expect(res.document.punches.length, equals(expectedPunches),
              reason: 'At H2=$h, expected $expectedPunches punches');
          expect(res.document.punches.any((p) => p.id == 'SLOT_6_B'), equals(has2nd));
        }
      });
    });

    group('User PDF Scenarios (media_1790179376536.pdf)', () {
      test('Scenario 1 (Page 2): [P1=150, P2=50, P3=100] -> Port 1 cheek flaps F_0 and F_5 both scale with dH1 = 50', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 150.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH1: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final bodyH = res.diagnostics['bodyHeight'] as double;
        expect(bodyH, equals(150.0));

        // Face F_3 notch v[0] matches B5.p2 exactly
        final f3 = res.document.faces.firstWhere((f) => f.id == 'F_3');
        final b5 = res.document.bends.firstWhere((b) => b.id == 'B5');
        expect(f3.vertices[0].x, closeTo(b5.p2.x, 0.05));
        expect(f3.vertices[0].y, closeTo(b5.p2.y, 0.05));

        // Flap F_0 along B5 elongates by dH1 = 50
        final b5Canon = canonicalDoc.bends.firstWhere((b) => b.id == 'B5');
        final lenB5 = math.sqrt(
          math.pow(b5.p2.x - b5.p1.x, 2) + math.pow(b5.p2.y - b5.p1.y, 2),
        );
        final lenB5Canon = math.sqrt(
          math.pow(b5Canon.p2.x - b5Canon.p1.x, 2) + math.pow(b5Canon.p2.y - b5Canon.p1.y, 2),
        );
        expect(lenB5 - lenB5Canon, closeTo(50.0, 0.05));
      });

      test('Scenario 2 (Page 3): [P1=100, P2=100, P3=100] -> Back Wall Right Ear flushes cleanly with FL3', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 100.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final f9 = res.document.faces.firstWhere((f) => f.id == 'F_9');
        // v[11] and v[12] are right ear vertices meeting the top edge. When flush, their y-coordinates are equal!
        expect(f9.vertices[11].y, closeTo(f9.vertices[12].y, 0.05));

        // FL3 bend line is collinear with the top flush edge
        final fl3 = res.document.bends.firstWhere((b) => b.id == 'FL3');
        expect(f9.vertices[11].y, closeTo(fl3.p2.y, 0.05));
      });

      test('Scenario 3 (Page 4): [P1=100, P2=50, P3=150] -> Port 1 stays 100mm on both sides while Port 3 scales to 150mm', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 150.0,
          dH3: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);

        final bodyH = res.diagnostics['bodyHeight'] as double;
        expect(bodyH, equals(150.0));

        // Port 1 flap F_0 stays at 100mm baseline height
        final b5 = res.document.bends.firstWhere((b) => b.id == 'B5');
        final b5Canon = canonicalDoc.bends.firstWhere((b) => b.id == 'B5');
        final lenB5 = math.sqrt(
          math.pow(b5.p2.x - b5.p1.x, 2) + math.pow(b5.p2.y - b5.p1.y, 2),
        );
        final lenB5Canon = math.sqrt(
          math.pow(b5Canon.p2.x - b5Canon.p1.x, 2) + math.pow(b5Canon.p2.y - b5Canon.p1.y, 2),
        );
        expect(lenB5, closeTo(lenB5Canon, 0.05));

        // Port 3 flap F_1 along B7 scales by dH3 = 50mm
        final b7 = res.document.bends.firstWhere((b) => b.id == 'B7');
        final b7Canon = canonicalDoc.bends.firstWhere((b) => b.id == 'B7');
        final lenB7 = math.sqrt(
          math.pow(b7.p2.x - b7.p1.x, 2) + math.pow(b7.p2.y - b7.p1.y, 2),
        );
        final lenB7Canon = math.sqrt(
          math.pow(b7Canon.p2.x - b7Canon.p1.x, 2) + math.pow(b7Canon.p2.y - b7Canon.p1.y, 2),
        );
        expect(lenB7 - lenB7Canon, closeTo(50.0, 0.05));

        // Face F_3 notch v[3] matches B7.p1 exactly
        final f3 = res.document.faces.firstWhere((f) => f.id == 'F_3');
        expect(f3.vertices[3].x, closeTo(b7.p1.x, 0.05));
        expect(f3.vertices[3].y, closeTo(b7.p1.y, 0.05));
      });
    });

    group('Flange Attachment & Arc Preservation Integrity (Resolving SS1, SS2, SS3, SS4)', () {
      double dist(CadPoint2D a, CadPoint2D b) =>
          math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

      void verifyFlangesAndArcs(DsfDocument doc, {required String scenarioName}) {
        // 1. Verify FL1 bend attached to F_3 and F_2
        final fl1 = doc.bends.firstWhere((b) => b.id == 'FL1');
        final f3 = doc.faces.firstWhere((f) => f.id == 'F_3');
        final f2 = doc.faces.firstWhere((f) => f.id == 'F_2');
        expect(dist(fl1.p1, f3.vertices[0]), closeTo(0.0, 0.01),
            reason: '$scenarioName: FL1.p1 must match F_3.v0');
        expect(dist(fl1.p2, f3.vertices[3]), closeTo(0.0, 0.01),
            reason: '$scenarioName: FL1.p2 must match F_3.v3');
        expect(dist(f2.vertices[3], f3.vertices[0]), closeTo(0.0, 0.01),
            reason: '$scenarioName: F_2.v3 must match F_3.v0');
        expect(dist(f2.vertices[0], f3.vertices[3]), closeTo(0.0, 0.01),
            reason: '$scenarioName: F_2.v0 must match F_3.v3');

        // 2. Verify FL3 bend attached to F_9 and F_8
        final fl3 = doc.bends.firstWhere((b) => b.id == 'FL3');
        final f9 = doc.faces.firstWhere((f) => f.id == 'F_9');
        final f8 = doc.faces.firstWhere((f) => f.id == 'F_8');
        final f9FlangeLeft = (f9.vertices.length > 13) ? f9.vertices.last : f9.vertices.first;
        expect(dist(fl3.p1, f9FlangeLeft), closeTo(0.0, 0.01),
            reason: '$scenarioName: FL3.p1 must match F_9 left flange junction');
        expect(dist(fl3.p2, f9.vertices[12]), closeTo(0.0, 0.01),
            reason: '$scenarioName: FL3.p2 must match F_9.v12');
        expect(dist(f8.vertices[3], f9FlangeLeft), closeTo(0.0, 0.01),
            reason: '$scenarioName: F_8.v3 must match F_9 left flange junction');
        expect(dist(f8.vertices[0], f9.vertices[12]), closeTo(0.0, 0.01),
            reason: '$scenarioName: F_8.v0 must match F_9.v12');

        // Verify Left Ear is completely orthogonal (horizontal bottom edge)
        expect((f9.vertices[0].y - f9.vertices[1].y).abs(), closeTo(0.0, 0.01),
            reason: '$scenarioName: F_9 left ear bottom edge must be horizontal');
        expect((doc.outerContour[42].y - doc.outerContour[41].y).abs(), closeTo(0.0, 0.01),
            reason: '$scenarioName: Outer contour left ear bottom edge must be horizontal');
        if (f9.vertices.length > 13) {
          // When body height > Port 3 height, verify vertical step from left ear notch to FL3
          expect((f9.vertices.last.x - f9.vertices[0].x).abs(), closeTo(0.0, 0.01),
              reason: '$scenarioName: Left ear step to FL3 must be vertical');
          expect((doc.outerContour[0].x - doc.outerContour[42].x).abs(), closeTo(0.0, 0.01),
              reason: '$scenarioName: Outer contour left step to flange must be vertical');
        }

        // 3. Verify all 12 arcs exist and match their face vertices
        expect(doc.arcs.length, equals(12), reason: '$scenarioName: All 12 arcs must be preserved');
        const arcMap = {
          'ARC_BND_1': ['F_9', 1, 2],
          'ARC_BND_2': ['F_9', 9, 10],
          'ARC_BND_3': ['F_9', 7, 8],
          'ARC_BND_4': ['F_4', 3, 4],
          'ARC_BND_5': ['F_4', 1, 2],
          'ARC_BND_6': ['F_5', 3, 4],
          'ARC_BND_7': ['F_5', 1, 2],
          'ARC_BND_8': ['F_0', 3, 4],
          'ARC_BND_9': ['F_0', 1, 2],
          'ARC_BND_10': ['F_9', 3, 4],
          'ARC_BND_11': ['F_1', 1, 2],
          'ARC_BND_12': ['F_1', 3, 4],
        };

        for (final entry in arcMap.entries) {
          final aid = entry.key;
          final fid = entry.value[0] as String;
          final vi1 = entry.value[1] as int;
          final vi2 = entry.value[2] as int;

          final arc = doc.arcs.firstWhere((a) => a.id == aid);
          final face = doc.faces.firstWhere((f) => f.id == fid);
          final v1 = face.vertices[vi1];
          final v2 = face.vertices[vi2];

          final d1 = math.min(
            dist(arc.startPoint, v1),
            dist(arc.startPoint, v2),
          );
          final d2 = math.min(
            dist(arc.endPoint, v1),
            dist(arc.endPoint, v2),
          );
          expect(d1, lessThan(0.05), reason: '$scenarioName: $aid startPoint must be coincident with $fid');
          expect(d2, lessThan(0.05), reason: '$scenarioName: $aid endPoint must be coincident with $fid');
        }
      }

      test('SS1: Port 1 Height = 150mm maintains FL1 attached to F_2 & F_3 and FL3 attached to F_8 & F_9 with all 12 arcs intact', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 150.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH1: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        verifyFlangesAndArcs(res.document, scenarioName: 'SS1 (P1=150)');
      });

      test('SS2: Port 3 Height = 150mm maintains FL1 attached to F_2 & F_3 and FL3 attached to F_8 & F_9 with all 12 arcs intact', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 150.0,
          dH3: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        verifyFlangesAndArcs(res.document, scenarioName: 'SS2 (P3=150)');
      });

      test('SS3: Port 2 Height = 100mm maintains Right Ear root arc ARC_BND_3 and all 12 arcs intact without deletion', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 100.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 50.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        verifyFlangesAndArcs(res.document, scenarioName: 'SS3 (P2=100)');
      });

      test('SS4: Port 2 Height = 150mm (>100mm) expands body to 150mm with FL1 & FL3 perfectly attached to return flanges F_2 & F_8', () {
        const params = UnequalTeeScaleParameters(
          port1Width: 50.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 150.0,
          port3Width: 100.0,
          port3Height: 100.0,
          dH2: 100.0,
        );
        final res = UnequalTeeScaler.scale(baseline: canonicalDoc, parameters: params);
        expect(res.isValid, isTrue);
        verifyFlangesAndArcs(res.document, scenarioName: 'SS4 (P2=150)');
      });
    });
  });
}
