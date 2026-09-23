import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/unequal_cross_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';

double _hypot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

void main() {
  group('UnequalCrossScaler (Analytical Parametric Scaling Engine)', () {
    late DsfDocument canonicalDoc;

    setUp(() {
      final file = File('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      canonicalDoc = DsfDocument.fromJson(json);
    });

    test('Canonical Baseline: zero delta returns baseline untouched with all 16 arcs and 0.0 deviation', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 50.0,
        port3Width: 100.0,
        port3Height: 100.0,
        port4Width: 50.0,
        port4Height: 50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      expect(result.document.faces.length, equals(canonicalDoc.faces.length));
      expect(result.document.bends.length, equals(canonicalDoc.bends.length));
      expect(result.document.arcs.length, equals(16));
      expect(result.document.punches.length, equals(12));

      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      final canonF16 = canonicalDoc.faces.firstWhere((f) => f.id == 'F_16');
      for (int i = 0; i < 8; i++) {
        expect(f16.vertices[i].x, closeTo(canonF16.vertices[i].x, 0.001));
        expect(f16.vertices[i].y, closeTo(canonF16.vertices[i].y, 0.001));
      }
    });

    test('Width Scaling: Port 2 width increase to 100mm (dW2 = 50) maintains 40mm corner bends at 45 deg', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 100.0,
        port2Width: 100.0,
        port2Height: 50.0,
        port3Width: 100.0,
        port3Height: 100.0,
        port4Width: 50.0,
        port4Height: 50.0,
        dW2: 50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      // Port 2 opening between v4 and v5 should expand from 48mm to 98mm
      final p2Opening = (f16.vertices[5].y - f16.vertices[4].y).abs();
      expect(p2Opening, closeTo(98.0, 0.01));

      // Bends B2 and B3 must remain exactly 40.0mm
      final b2 = result.document.bends.firstWhere((b) => b.id == 'B2');
      final b2Len = _hypot(b2.p2.x - b2.p1.x, b2.p2.y - b2.p1.y);
      expect(b2Len, closeTo(40.0, 0.01));

      final b3 = result.document.bends.firstWhere((b) => b.id == 'B3');
      final b3Len = _hypot(b3.p2.x - b3.p1.x, b3.p2.y - b3.p1.y);
      expect(b3Len, closeTo(40.0, 0.01));

      // All 16 fillet arcs must be preserved
      expect(result.document.arcs.length, equals(16));
    });

    test('Width Scaling: Port 4 width increase to 100mm (dW4 = 50) maintains 40mm corner bends B1 and B4', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 50.0,
        port3Width: 100.0,
        port3Height: 100.0,
        port4Width: 100.0,
        port4Height: 50.0,
        dW4: 50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      // Port 4 opening between v1 and v0 should expand from 48mm to 98mm
      final p4Opening = (f16.vertices[0].y - f16.vertices[1].y).abs();
      expect(p4Opening, closeTo(98.0, 0.01));

      final b1 = result.document.bends.firstWhere((b) => b.id == 'B1');
      final b1Len = _hypot(b1.p2.x - b1.p1.x, b1.p2.y - b1.p1.y);
      expect(b1Len, closeTo(40.0, 0.01));

      final b4 = result.document.bends.firstWhere((b) => b.id == 'B4');
      final b4Len = _hypot(b4.p2.x - b4.p1.x, b4.p2.y - b4.p1.y);
      expect(b4Len, closeTo(40.0, 0.01));

      expect(result.document.arcs.length, equals(16));
    });

    test('Derived Body Height: Hbody = max(H1, H2, H3, H4) when Port 2 increases to 75mm', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 75.0,
        port3Width: 100.0,
        port3Height: 100.0,
        port4Width: 50.0,
        port4Height: 50.0,
        dH2: 25.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      expect(result.diagnostics['bodyHeight'], equals(100.0));
      expect(result.diagnostics['dHBody'], equals(0.0));

      // Flap F_0 (Port 2 top flap) should scale with dH2 = 25 (span 73mm)
      final b8 = result.document.bends.firstWhere((b) => b.id == 'B8');
      final b8Len = _hypot(b8.p2.x - b8.p1.x, b8.p2.y - b8.p1.y);
      expect(b8Len, closeTo(73.0, 0.01));

      // Return flange FL3 should remain at body height 100 (0 delta)
      final fl3 = result.document.bends.firstWhere((b) => b.id == 'FL3');
      final canonFl3 = canonicalDoc.bends.firstWhere((b) => b.id == 'FL3');
      expect(fl3.p1.x, closeTo(canonFl3.p1.x, 0.01));
      expect(fl3.p1.y, closeTo(canonFl3.p1.y, 0.01));
    });

    test('Derived Body Height: Hbody = max(H1, H2, H3, H4) when Port 2 increases to 125mm', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 125.0,
        port3Width: 100.0,
        port3Height: 100.0,
        port4Width: 50.0,
        port4Height: 50.0,
        dH2: 75.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // Body height should expand to 125mm (dHBody = 25.0)
      expect(result.diagnostics['bodyHeight'], equals(125.0));
      expect(result.diagnostics['dHBody'], equals(25.0));

      // Return flange FL3 should expand with dHBody = 25.0
      final fl3 = result.document.bends.firstWhere((b) => b.id == 'FL3');
      final canonFl3 = canonicalDoc.bends.firstWhere((b) => b.id == 'FL3');
      final shift = _hypot(fl3.p1.x - canonFl3.p1.x, fl3.p1.y - canonFl3.p1.y);
      expect(shift, closeTo(25.0, 0.01));

      // Port 1 flap F_1 should NOT expand with body, it follows H1 = 100 (dH1 = 0)
      final b9 = result.document.bends.firstWhere((b) => b.id == 'B9');
      final b9Len = _hypot(b9.p2.x - b9.p1.x, b9.p2.y - b9.p1.y);
      expect(b9Len, closeTo(98.0, 0.01));
    });

    test('Universal 95mm Coupler Rule: Port 2 height >= 95mm synthesizes 2nd slots on F_0 and F_8 at 50mm pitch', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 95.0,
        port3Width: 100.0,
        port3Height: 100.0,
        port4Width: 50.0,
        port4Height: 50.0,
        dH2: 45.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // Baseline 12 punches + 2 synthesized on Port 2 = 14 punches
      expect(result.document.punches.length, equals(14));

      final slot9 = result.document.punches.firstWhere((p) => p.id == 'SLOT_9');
      final slot9B = result.document.punches.firstWhere((p) => p.id == 'SLOT_9_B');
      final pitchF0 = _hypot(slot9B.center.x - slot9.center.x, slot9B.center.y - slot9.center.y);
      expect(pitchF0, closeTo(50.0, 0.01));

      final slot12 = result.document.punches.firstWhere((p) => p.id == 'SLOT_12');
      final slot12B = result.document.punches.firstWhere((p) => p.id == 'SLOT_12_B');
      final pitchF8 = _hypot(slot12B.center.x - slot12.center.x, slot12B.center.y - slot12.center.y);
      expect(pitchF8, closeTo(50.0, 0.01));
    });

    test('Universal 95mm Coupler Rule: Both Port 2 and Port 4 >= 95mm yields 16 total punches', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 100.0,
        port3Width: 100.0,
        port3Height: 100.0,
        port4Width: 50.0,
        port4Height: 100.0,
        dH2: 50.0,
        dH4: 50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // All 4 ports are >= 95mm, each port has 2 flaps with 2 slots each = 4 * 2 * 2 = 16 punches
      expect(result.document.punches.length, equals(16));
    });

    test('Universal 95mm Coupler Rule: Port 1 height < 95mm suppresses 2nd slot and centers remaining slot', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 75.0,
        port2Width: 50.0,
        port2Height: 50.0,
        port3Width: 100.0,
        port3Height: 100.0,
        port4Width: 50.0,
        port4Height: 50.0,
        dH1: -25.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // Baseline 12 punches - 2 suppressed on Port 1 = 10 punches
      expect(result.document.punches.length, equals(10));
      expect(result.document.punches.any((p) => p.id == 'SLOT_8'), isFalse);
      expect(result.document.punches.any((p) => p.id == 'PUNCH_CPY_8064'), isFalse);

      // Remaining slots SLOT_7 and SLOT_1 must exist
      expect(result.document.punches.any((p) => p.id == 'SLOT_7'), isTrue);
      expect(result.document.punches.any((p) => p.id == 'SLOT_1'), isTrue);
    });

    test('Universal 95mm Coupler Rule: Bidirectional reversibility when scaling up then down', () {
      // 1. Scale Port 2 up to 100mm -> 14 punches
      final scaledUp = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: const UnequalCrossScaleParameters(
          port1Width: 100.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 100.0,
          port3Width: 100.0,
          port3Height: 100.0,
          port4Width: 50.0,
          port4Height: 50.0,
          dH2: 50.0,
        ),
      );
      expect(scaledUp.document.punches.length, equals(14));

      // 2. Scale Port 2 down to 50mm -> 12 punches
      final scaledDown = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: const UnequalCrossScaleParameters(
          port1Width: 100.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 50.0,
          port3Width: 100.0,
          port3Height: 100.0,
          port4Width: 50.0,
          port4Height: 50.0,
          dH2: 0.0,
        ),
      );
      expect(scaledDown.document.punches.length, equals(12));
    });

    test('Arc Fillet Preservation: All 16 arcs preserve r=10.0mm under arbitrary multi-port scaling', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 150.0,
        port1Height: 120.0,
        port2Width: 75.0,
        port2Height: 80.0,
        port3Width: 80.0,
        port3Height: 90.0,
        port4Width: 60.0,
        port4Height: 110.0,
        dW1: 50.0,
        dH1: 20.0,
        dW2: 25.0,
        dH2: 30.0,
        dW3: -20.0,
        dH3: -10.0,
        dW4: 10.0,
        dH4: 60.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      expect(result.document.arcs.length, equals(16));
      for (final arc in result.document.arcs) {
        expect(arc.radius, equals(10.0));
      }
    });

    test('Controller Integration: CmsScalingController correctly initializes and scales Unequal Cross', () {
      const ports = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 50.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0),
        CmsPhysicalPort(id: 'PORT_4', index: 4, width: 50.0, height: 50.0),
      ];

      final controller = CmsScalingController(
        baselineDocument: canonicalDoc,
        contract: CmsProductContract.unequalCross,
        baselinePorts: ports,
      );

      expect(controller.model.parameters['port1_width']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port1_height']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port2_width']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port2_height']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port3_width']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port3_height']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port4_width']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port4_height']?.baselineValue, equals(50.0));

      // Test scaling through controller
      controller.selectParameter('port2_height');
      controller.evaluateMorph(95.0);
      expect(controller.currentPreview, isNotNull);
      final previewDoc = controller.currentPreview!.scaledDocument;
      expect(previewDoc.punches.length, equals(14));
      expect(previewDoc.arcs.length, equals(16));
    });

    test('Width Scaling: Port 1 width increase to 150mm & Port 3 decrease to 50mm maintains symmetry and 40mm corner bends', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 150.0,
        port1Height: 100.0,
        port2Width: 50.0,
        port2Height: 50.0,
        port3Width: 50.0,
        port3Height: 100.0,
        port4Width: 50.0,
        port4Height: 50.0,
        dW1: 50.0,
        dW3: -50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      // Port 1 opening (v2 to v3) should be 148.0mm (unbent 150 - 2)
      final p1Opening = (f16.vertices[3].x - f16.vertices[2].x).abs();
      expect(p1Opening, closeTo(148.0, 0.01));

      // Port 3 opening (v7 to v6) should be 48.0mm (unbent 50 - 2)
      final p3Opening = (f16.vertices[6].x - f16.vertices[7].x).abs();
      expect(p3Opening, closeTo(48.0, 0.01));

      // All 4 diagonal corner bends must remain 40.0mm
      for (final bid in ['B1', 'B2', 'B3', 'B4']) {
        final b = result.document.bends.firstWhere((bend) => bend.id == bid);
        final len = _hypot(b.p2.x - b.p1.x, b.p2.y - b.p1.y);
        expect(len, closeTo(40.0, 0.01));
      }
    });

    test('Asymmetric Heights: Port 3 height 125mm with Port 1 height 75mm correctly creates orthogonal steps', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 75.0,
        port2Width: 50.0,
        port2Height: 50.0,
        port3Width: 100.0,
        port3Height: 125.0,
        port4Width: 50.0,
        port4Height: 50.0,
        dH1: -25.0,
        dH3: 25.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // Hbody = max(75, 50, 125, 50) = 125.0
      expect(result.diagnostics['bodyHeight'], equals(125.0));

      // Port 3 flaps (F_9, F_13) have H3 >= 95 -> 2 slots each
      // Port 1 flaps (F_1, F_5) have H1 < 95 -> 1 slot each
      // Port 2 flaps (F_0, F_8) have H2 < 95 -> 1 slot each
      // Port 4 flaps (F_4, F_12) have H4 < 95 -> 1 slot each
      // Total punches = 2*2 + 2*1 + 2*1 + 2*1 = 4 + 2 + 2 + 2 = 10 punches
      expect(result.document.punches.length, equals(10));
    });

    test('Continuous Closed Outer Contour: All contour points coincide with face vertices without gaps', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 120.0,
        port1Height: 110.0,
        port2Width: 80.0,
        port2Height: 95.0,
        port3Width: 90.0,
        port3Height: 100.0,
        port4Width: 70.0,
        port4Height: 60.0,
        dW1: 20.0,
        dH1: 10.0,
        dW2: 30.0,
        dH2: 45.0,
        dW3: -10.0,
        dH3: 0.0,
        dW4: 20.0,
        dH4: 10.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final contour = result.document.outerContour;
      expect(contour.length, equals(canonicalDoc.outerContour.length));

      // Every contour point must match at least one face vertex
      final allFaceVerts = result.document.faces.expand((f) => f.vertices).toList();
      for (int i = 0; i < contour.length; i++) {
        final cp = contour[i];
        final hasMatch = allFaceVerts.any((fv) => _hypot(fv.x - cp.x, fv.y - cp.y) < 0.01);
        expect(hasMatch, isTrue, reason: 'Contour point $i ($cp) must coincide with a face vertex');
      }

      // Contour first and last points must close cleanly with Port 4 bottom flap
      final startPt = contour.first;
      final endPt = contour.last;
      expect(_hypot(startPt.x - endPt.x, startPt.y - endPt.y), closeTo(0.0, 0.01));
    });
  });
}
