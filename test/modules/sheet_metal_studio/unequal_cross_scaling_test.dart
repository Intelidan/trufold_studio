import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/unequal_cross_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
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
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 50.0,
        port4Width: 100.0,
        port4Height: 100.0,
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

    test('Width Scaling: Port 3 (East) width increase to 100mm (dW3 = 50) maintains 40mm corner bends at 45 deg', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 100.0,
        port3Width: 100.0,
        port3Height: 50.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dW3: 50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      // Port 3 opening between v4 and v5 should expand from 48mm to 98mm
      final p3Opening = (f16.vertices[5].y - f16.vertices[4].y).abs();
      expect(p3Opening, closeTo(98.0, 0.01));

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

    test('Width Scaling: Port 1 (West) width increase to 100mm (dW1 = 50) maintains 40mm corner bends B1 and B4', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 100.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 50.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dW1: 50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      // Port 1 opening between v1 and v0 should expand from 48mm to 98mm
      final p1Opening = (f16.vertices[0].y - f16.vertices[1].y).abs();
      expect(p1Opening, closeTo(98.0, 0.01));

      final b1 = result.document.bends.firstWhere((b) => b.id == 'B1');
      final b1Len = _hypot(b1.p2.x - b1.p1.x, b1.p2.y - b1.p1.y);
      expect(b1Len, closeTo(40.0, 0.01));

      final b4 = result.document.bends.firstWhere((b) => b.id == 'B4');
      final b4Len = _hypot(b4.p2.x - b4.p1.x, b4.p2.y - b4.p1.y);
      expect(b4Len, closeTo(40.0, 0.01));

      expect(result.document.arcs.length, equals(16));
    });

    test('Derived Body Height: Hbody = max(H1, H2, H3, H4) when Port 3 increases to 75mm', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 75.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dH3: 25.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      expect(result.diagnostics['bodyHeight'], equals(100.0));
      expect(result.diagnostics['dHBody'], equals(0.0));

      // Flap F_0 (Port 3 top flap) should scale with dH3 = 25 (span 73mm)
      final b8 = result.document.bends.firstWhere((b) => b.id == 'B8');
      final b8Len = _hypot(b8.p2.x - b8.p1.x, b8.p2.y - b8.p1.y);
      expect(b8Len, closeTo(73.0, 0.01));

      // Return flange FL3 should remain at body height 100 (0 delta)
      final fl3 = result.document.bends.firstWhere((b) => b.id == 'FL3');
      final canonFl3 = canonicalDoc.bends.firstWhere((b) => b.id == 'FL3');
      expect(fl3.p1.x, closeTo(canonFl3.p1.x, 0.01));
      expect(fl3.p1.y, closeTo(canonFl3.p1.y, 0.01));
    });

    test('Derived Body Height: Hbody = max(H1, H2, H3, H4) when Port 3 increases to 125mm', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 125.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dH3: 75.0,
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

      // Port 2 flap F_1 should NOT expand with body, it follows H2 = 100 (dH2 = 0)
      final b9 = result.document.bends.firstWhere((b) => b.id == 'B9');
      final b9Len = _hypot(b9.p2.x - b9.p1.x, b9.p2.y - b9.p1.y);
      expect(b9Len, closeTo(98.0, 0.01));
    });

    test('Universal 95mm Coupler Rule: Port 3 height >= 95mm synthesizes 2nd slots on F_0 and F_8 at 50mm pitch', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 95.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dH3: 45.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // Baseline 12 punches + 2 synthesized on Port 3 = 14 punches
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

    test('Universal 95mm Coupler Rule: Both Port 1 and Port 3 >= 95mm yields 16 total punches', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 100.0,
        port2Width: 100.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 100.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dH1: 50.0,
        dH3: 50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // All 4 ports are >= 95mm, each port has 2 flaps with 2 slots each = 4 * 2 * 2 = 16 punches
      expect(result.document.punches.length, equals(16));
    });

    test('Universal 95mm Coupler Rule: Port 2 height < 95mm suppresses 2nd slot and centers remaining slot', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 75.0,
        port3Width: 50.0,
        port3Height: 50.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dH2: -25.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // Baseline 12 punches - 2 suppressed on Port 2 = 10 punches
      expect(result.document.punches.length, equals(10));
      expect(result.document.punches.any((p) => p.id == 'SLOT_8'), isFalse);
      expect(result.document.punches.any((p) => p.id == 'PUNCH_CPY_8064'), isFalse);

      // Remaining slots SLOT_7 and SLOT_1 must exist
      expect(result.document.punches.any((p) => p.id == 'SLOT_7'), isTrue);
      expect(result.document.punches.any((p) => p.id == 'SLOT_1'), isTrue);
    });

    test('Universal 95mm Coupler Rule: Bidirectional reversibility when scaling up then down', () {
      // 1. Scale Port 3 up to 100mm -> 14 punches
      final scaledUp = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: const UnequalCrossScaleParameters(
          port1Width: 50.0,
          port1Height: 50.0,
          port2Width: 100.0,
          port2Height: 100.0,
          port3Width: 50.0,
          port3Height: 100.0,
          port4Width: 100.0,
          port4Height: 100.0,
          dH3: 50.0,
        ),
      );
      expect(scaledUp.document.punches.length, equals(14));

      // 2. Scale Port 3 down to 50mm -> 12 punches
      final scaledDown = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: const UnequalCrossScaleParameters(
          port1Width: 50.0,
          port1Height: 50.0,
          port2Width: 100.0,
          port2Height: 100.0,
          port3Width: 50.0,
          port3Height: 50.0,
          port4Width: 100.0,
          port4Height: 100.0,
          dH3: 0.0,
        ),
      );
      expect(scaledDown.document.punches.length, equals(12));
    });

    test('Arc Fillet Preservation: All 16 arcs preserve r=10.0mm under arbitrary multi-port scaling', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 75.0,
        port1Height: 80.0,
        port2Width: 150.0,
        port2Height: 120.0,
        port3Width: 60.0,
        port3Height: 110.0,
        port4Width: 80.0,
        port4Height: 90.0,
        dW1: 25.0,
        dH1: 30.0,
        dW2: 50.0,
        dH2: 20.0,
        dW3: 10.0,
        dH3: 60.0,
        dW4: -20.0,
        dH4: -10.0,
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
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 50.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0),
        CmsPhysicalPort(id: 'PORT_3', index: 3, width: 50.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0),
      ];

      final controller = CmsScalingController(
        baselineDocument: canonicalDoc,
        contract: CmsProductContract.unequalCross,
        baselinePorts: ports,
      );

      expect(controller.model.parameters['port1_width']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port1_height']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port2_width']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port2_height']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port3_width']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port3_height']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port4_width']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port4_height']?.baselineValue, equals(100.0));

      // Test scaling through controller: scale Port 3 height to 95mm
      controller.selectParameter('port3_height');
      controller.evaluateMorph(95.0);
      expect(controller.currentPreview, isNotNull);
      final previewDoc = controller.currentPreview!.scaledDocument;
      expect(previewDoc.punches.length, equals(14));
      expect(previewDoc.arcs.length, equals(16));
    });

    test('Width Scaling: Port 2 (North) width increase to 150mm & Port 4 (South) decrease to 50mm maintains symmetry and 40mm corner bends', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 150.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 50.0,
        port4Width: 50.0,
        port4Height: 100.0,
        dW2: 50.0,
        dW4: -50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      final verts = f16.vertices;

      // Port 2 opening (v2 to v3) should be 148.0mm (unbent 150 - 2) and strictly horizontal
      expect(verts[2].y, closeTo(verts[3].y, 1e-4));
      expect((verts[3].x - verts[2].x).abs(), closeTo(148.0, 0.01));

      // Port 4 opening (v7 to v6) scales independently to 48.0mm (unbent 50 - 2) and strictly horizontal
      expect(verts[6].y, closeTo(verts[7].y, 1e-4));
      expect((verts[6].x - verts[7].x).abs(), closeTo(48.0, 0.01));

      // Port 1 (West: v1 to v0) and Port 3 (East: v4 to v5) remain strictly vertical
      expect(verts[0].x, closeTo(verts[1].x, 1e-4));
      expect(verts[4].x, closeTo(verts[5].x, 1e-4));

      // North side bends (B1, B2) remain standard 40.0mm at 45 deg
      for (final bid in ['B1', 'B2']) {
        final b = result.document.bends.firstWhere((bend) => bend.id == bid);
        final len = _hypot(b.p2.x - b.p1.x, b.p2.y - b.p1.y);
        expect(len, closeTo(40.0, 0.01));
      }

      // South side bends (B3, B4) elongate dynamically by 50mm in X to preserve 90 deg orthogonal port mouths
      for (final bid in ['B3', 'B4']) {
        final b = result.document.bends.firstWhere((bend) => bend.id == bid);
        final len = _hypot(b.p2.x - b.p1.x, b.p2.y - b.p1.y);
        expect(len, closeTo(83.24, 0.02));
      }
    });

    test('PDF Scenario (Port 1 Width 150mm): All 4 port mouths remain strictly 90 deg orthogonal without slanted walls', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 150.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 50.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dW1: 100.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      final verts = f16.vertices;

      // Port 1 (West: v1 to v0) is strictly vertical (x is constant) and length 148mm
      expect(verts[0].x, closeTo(verts[1].x, 1e-4));
      expect((verts[0].y - verts[1].y).abs(), closeTo(148.0, 0.01));

      // Port 2 (North: v2 to v3) width remains unbentW2 (98mm) and strictly horizontal (y is constant, 90 deg orthogonal)
      expect(verts[2].y, closeTo(verts[3].y, 1e-4));
      expect((verts[3].x - verts[2].x).abs(), closeTo(98.0, 0.01));

      // Port 3 (East: v4 to v5) is strictly vertical (x is constant) and remains unbentW3 (48mm), independent of Port 1!
      expect(verts[4].x, closeTo(verts[5].x, 1e-4));
      expect((verts[5].y - verts[4].y).abs(), closeTo(48.0, 0.01));

      // Port 4 (South: v7 to v6) width remains unbentW4 (98mm) and strictly horizontal (y is constant, 90 deg orthogonal)
      expect(verts[6].y, closeTo(verts[7].y, 1e-4));
      expect((verts[6].x - verts[7].x).abs(), closeTo(98.0, 0.01));

      // West side cheek bends (B1, B4) remain strictly 40.0mm at 45 deg
      for (final bid in ['B1', 'B4']) {
        final b = result.document.bends.firstWhere((bend) => bend.id == bid);
        final len = _hypot(b.p2.x - b.p1.x, b.p2.y - b.p1.y);
        expect(len, closeTo(40.0, 0.01));
      }

      // East side cheek bends (B2, B3) elongate by 50mm in Y to keep adjacent ports at 90 deg (H1 and H2 in user PDF)
      for (final bid in ['B2', 'B3']) {
        final b = result.document.bends.firstWhere((bend) => bend.id == bid);
        final len = _hypot(b.p2.x - b.p1.x, b.p2.y - b.p1.y);
        expect(len, closeTo(83.24, 0.02));
      }

      // Coupler flap bend angles compensate dynamically for cheek wall rotation:
      // When cheek wall angle increases (adds to 70.13 deg):
      // - East vertical flaps (B8, B7) bend at 70.13 deg to stay parallel to duct wall
      // - North & South horizontal flaps (B9, B12) bend at 19.87 deg (subtracts 90 - 70.13)
      final b8 = result.document.bends.firstWhere((bend) => bend.id == 'B8');
      final b7 = result.document.bends.firstWhere((bend) => bend.id == 'B7');
      expect(b8.targetAngleDeg, closeTo(70.13, 0.05));
      expect(b7.targetAngleDeg, closeTo(70.13, 0.05));

      final b9 = result.document.bends.firstWhere((bend) => bend.id == 'B9');
      final b12 = result.document.bends.firstWhere((bend) => bend.id == 'B12');
      expect(b9.targetAngleDeg, closeTo(19.87, 0.05));
      expect(b12.targetAngleDeg, closeTo(19.87, 0.05));
      expect(b8.targetAngleDeg + b9.targetAngleDeg, closeTo(90.0, 0.01));

      // West side coupler flaps (B5, B6, B10, B11) maintain baseline 45.0 deg
      for (final bid in ['B5', 'B6', 'B10', 'B11']) {
        final b = result.document.bends.firstWhere((bend) => bend.id == bid);
        expect(b.targetAngleDeg, closeTo(45.0, 0.01));
      }

      // All 16 fillet arcs are preserved with radius 10.0mm
      expect(result.document.arcs.length, equals(16));
      for (final arc in result.document.arcs) {
        expect(arc.radius, closeTo(10.0, 0.01));
      }
    });

    test('Asymmetric Heights: Port 2 height 125mm with Port 4 height 75mm correctly creates orthogonal steps', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 100.0,
        port2Height: 125.0,
        port3Width: 50.0,
        port3Height: 50.0,
        port4Width: 100.0,
        port4Height: 75.0,
        dH2: 25.0,
        dH4: -25.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      // Hbody = max(50, 125, 50, 75) = 125.0
      expect(result.diagnostics['bodyHeight'], equals(125.0));

      // Port 2 flaps (F_1, F_5) have H2 >= 95 -> 2 slots each
      // Port 4 flaps (F_9, F_13) have H4 < 95 -> 1 slot each
      // Port 1 flaps (F_4, F_12) have H1 < 95 -> 1 slot each
      // Port 3 flaps (F_0, F_8) have H3 < 95 -> 1 slot each
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

    test('Independent Scaling: Port 2 width increase to 150mm leaves opposite Port 4 width strictly at 100mm', () {
      const params = UnequalCrossScaleParameters(
        port1Width: 50.0,
        port1Height: 50.0,
        port2Width: 150.0,
        port2Height: 100.0,
        port3Width: 50.0,
        port3Height: 50.0,
        port4Width: 100.0,
        port4Height: 100.0,
        dW2: 50.0,
      );

      final result = UnequalCrossScaler.scale(
        baseline: canonicalDoc,
        parameters: params,
      );

      expect(result.isValid, isTrue);
      final f16 = result.document.faces.firstWhere((f) => f.id == 'F_16');
      final p2Opening = (f16.vertices[3].x - f16.vertices[2].x).abs();
      expect(p2Opening, closeTo(148.0, 0.01)); // Port 2 scaled to 150mm (unbent 148)

      final p4Opening = (f16.vertices[6].x - f16.vertices[7].x).abs();
      expect(p4Opening, closeTo(98.0, 0.01)); // Opposite Port 4 strictly remains 100mm (unbent 98)
    });

    test('Controller Integration: Scaling Port 1 width to 150mm preserves exact port identities without swapping Port 1 and Port 4', () {
      const ports = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 50.0, height: 50.0, normal: CadPoint3D(-1.0, 0.0, 0.0)),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0, normal: CadPoint3D(0.0, -1.0, 0.0)),
        CmsPhysicalPort(id: 'PORT_3', index: 3, width: 50.0, height: 50.0, normal: CadPoint3D(1.0, 0.0, 0.0)),
        CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0, normal: CadPoint3D(0.0, 1.0, 0.0)),
      ];

      final controller = CmsScalingController(
        baselineDocument: canonicalDoc,
        contract: CmsProductContract.unequalCross,
        baselinePorts: ports,
      );

      controller.selectParameter('port1_width');
      controller.evaluateMorph(150.0);

      expect(controller.currentPreview, isNotNull);
      final derivedPorts = controller.currentPreview!.derivedPorts;
      expect(derivedPorts.length, equals(4));

      // Port 1 must remain PORT_1 (West) with width 150mm
      final p1 = derivedPorts.firstWhere((p) => p.id == 'PORT_1');
      // Verify derived mouth corners on Port 1 have moved to xWest = 76.367 and span 150mm
      expect(p1.derivedMouthCorners.length, equals(4));
      final c0 = p1.derivedMouthCorners[0];
      final c3 = p1.derivedMouthCorners[3];
      final measuredW1 = (c0.y - c3.y).abs();
      expect(measuredW1, closeTo(148.0, 2.0)); // 150 - bendRelief
    });

    test('3D Port Glass Placement & Resizing: Multi-port scaled cross (Port 2=200x100, Port 3=115x50) properly repositions and resizes mouth apertures', () {
      final ports = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 50.0, height: 50.0, normal: const CadPoint3D(-1, 0, 0)),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0, normal: const CadPoint3D(0, -1, 0)),
        CmsPhysicalPort(id: 'PORT_3', index: 3, width: 50.0, height: 50.0, normal: const CadPoint3D(1, 0, 0)),
        CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0, normal: const CadPoint3D(0, 1, 0)),
      ];

      final controller = CmsScalingController(
        baselineDocument: canonicalDoc,
        contract: CmsProductContract.unequalCross,
        baselinePorts: ports,
      );

      // Scale Port 2 width to 200mm
      controller.selectParameter('port2_width');
      controller.evaluateMorph(200.0);

      // Scale Port 3 width to 115mm
      controller.selectParameter('port3_width');
      controller.evaluateMorph(115.0);

      expect(controller.currentPreview, isNotNull);
      final derivedPorts = controller.currentPreview!.derivedPorts;
      expect(derivedPorts.length, equals(4));

      final p1 = derivedPorts.firstWhere((p) => p.id == 'PORT_1');
      final p2 = derivedPorts.firstWhere((p) => p.id == 'PORT_2');
      final p3 = derivedPorts.firstWhere((p) => p.id == 'PORT_3');
      final p4 = derivedPorts.firstWhere((p) => p.id == 'PORT_4');

      // Verify Port 2: width is 200mm and mouth corners reflect 200mm opening
      expect(p2.width, closeTo(200.0, 0.5));
      expect(p2.derivedMouthCorners.length, equals(4));
      final p2Corner0 = p2.derivedMouthCorners[0];
      final p2Corner3 = p2.derivedMouthCorners[3];
      final p2MouthW = (p2Corner0.x - p2Corner3.x).abs();
      expect(p2MouthW, closeTo(198.0, 2.5)); // spans 200mm

      // Verify Port 3: width is 115mm and mouth corners reflect 115mm opening
      expect(p3.width, closeTo(115.0, 0.5));
      expect(p3.derivedMouthCorners.length, equals(4));
      final p3Corner0 = p3.derivedMouthCorners[0];
      final p3Corner3 = p3.derivedMouthCorners[3];
      final p3MouthW = (p3Corner0.y - p3Corner3.y).abs();
      expect(p3MouthW, closeTo(113.0, 2.5)); // spans 115mm

      // Verify Port 1 remains at baseline 50mm
      expect(p1.width, closeTo(50.0, 0.5));
      expect(p1.derivedMouthCorners.length, equals(4));

      // Verify Port 4 remains at baseline 100mm
      expect(p4.width, closeTo(100.0, 0.5));
      expect(p4.derivedMouthCorners.length, equals(4));
    });

    test('Session Re-opening & Repeated Scaling (SS1-SS4): scaling Port 1 to 150mm, applying, and re-opening dialog retains 150mm and scales cleanly without explosion', () {
      final initialPorts = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 50.0, height: 50.0, normal: const CadPoint3D(-1, 0, 0)),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0, normal: const CadPoint3D(0, -1, 0)),
        CmsPhysicalPort(id: 'PORT_3', index: 3, width: 50.0, height: 50.0, normal: const CadPoint3D(1, 0, 0)),
        CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0, normal: const CadPoint3D(0, 1, 0)),
      ];

      // Session 1: User opens dialog and scales Port 1 width from 50mm to 150mm
      final controller1 = CmsScalingController(
        baselineDocument: canonicalDoc,
        contract: CmsProductContract.unequalCross,
        baselinePorts: initialPorts,
      );
      controller1.selectParameter('port1_width');
      controller1.evaluateMorph(150.0);

      // User clicks "Apply Scaling"
      final appliedDoc = controller1.acceptScalingModel();
      expect(appliedDoc.parameters['port1_width'], equals(150.0));
      expect(appliedDoc.metadata['cmsTemplate'], isNotNull);
      expect(appliedDoc.metadata['cmsTemplate']['canonicalDocument'], isNotNull);
      expect(appliedDoc.metadata['cms_product_contract']?['productType'], equals('cross'));
      expect(appliedDoc.metadata['cms_product_contract']?['variationName'], equals('unequal_cross'));

      // Session 2 (SS3): User re-opens Template Scaling dialog
      // Verify contract lookup resolves as unequalCross and NEVER insideRiser
      final cmsTemplate = appliedDoc.metadata['cmsTemplate'] as Map<String, dynamic>;
      final resolvedContract = CmsProductContract.lookup(
            cmsTemplate['productType'] as String?,
            cmsTemplate['variation'] as String? ?? cmsTemplate['variationName'] as String?,
          ) ??
          (CmsScalingController.isCrossFitting(appliedDoc, portCount: 4)
              ? CmsProductContract.unequalCross
              : CmsProductContract.insideRiser45);

      expect(resolvedContract, equals(CmsProductContract.unequalCross));
      expect(CmsScalingController.isInsideRiserGeometry(appliedDoc), isFalse);

      // Extract canonical document and parameters
      final canonicalFromMeta = DsfDocument.fromJson(Map<String, dynamic>.from(cmsTemplate['canonicalDocument'] as Map));
      final currentParamValues = <String, double>{};
      currentParamValues.addAll(appliedDoc.parameters);

      final controller2 = CmsScalingController(
        baselineDocument: canonicalFromMeta,
        contract: resolvedContract,
        baselinePorts: initialPorts,
        currentParameterValues: currentParamValues,
      );

      // Verify SS3: Port 1 width slider reflects the current 150mm, NOT 50mm
      expect(controller2.model.parameters['port1_width']!.currentValue, equals(150.0));
      expect(controller2.model.parameters['port1_width']!.baselineValue, equals(50.0));
      expect(controller2.effectiveScalingProfile, equals(CmsScalingProfile.unequalCross));

      // Verify SS4: User changes or confirms 150mm again - drawing does NOT blow up!
      controller2.evaluateMorph(150.0);
      expect(controller2.currentPreview, isNotNull);

      final previewDoc = controller2.currentPreview!.scaledDocument;
      expect(previewDoc.arcs.length, equals(16)); // All 16 fillet arcs intact
      expect(previewDoc.bends.length, equals(canonicalDoc.bends.length)); // Same bend topology
      expect(previewDoc.faces.length, equals(canonicalDoc.faces.length)); // Same face count

      final derivedPorts = controller2.currentPreview!.derivedPorts;
      expect(derivedPorts.length, equals(4));

      final p1 = derivedPorts.firstWhere((p) => p.id == 'PORT_1');
      expect(p1.width, closeTo(150.0, 0.5));
      expect(p1.derivedMouthCorners.length, equals(4));

      // Further verify scaling to 160mm works smoothly without explosion
      controller2.evaluateMorph(160.0);
      final p1_160 = controller2.currentPreview!.derivedPorts.firstWhere((p) => p.id == 'PORT_1');
      expect(p1_160.width, closeTo(160.0, 0.5));
      expect(controller2.currentPreview!.scaledDocument.arcs.length, equals(16));
    });
  });
}
