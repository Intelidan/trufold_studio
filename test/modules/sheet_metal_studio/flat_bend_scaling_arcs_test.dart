import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/topological_zone_morpher.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/template_parameter_definition.dart';

void main() {
  group('45° Flat Bend Parametric Scaling & Arc Attachment Tests', () {
    late DsfDocument baselineDoc;
    late List<CmsPhysicalPort> baselinePorts;

    setUp(() {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      baselineDoc = DsfDocument.fromJson(json);

      baselinePorts = const [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 98.0, height: 100.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 98.0, height: 100.0),
      ];
    });

    test('1. Baseline verification: all 8 arcs attached to contour vertices (SS1 state)', () {
      expect(baselineDoc.arcs.length, equals(8));
      for (final arc in baselineDoc.arcs) {
        expect(arc.radius, closeTo(10.0, 1e-3));

        // Start point must be within 0.1mm of some contour vertex
        final hasStartMatch = baselineDoc.outerContour.any((v) => v.distanceTo(arc.startPoint) < 0.1);
        final hasEndMatch = baselineDoc.outerContour.any((v) => v.distanceTo(arc.endPoint) < 0.1);
        expect(hasStartMatch, isTrue, reason: 'Arc ${arc.id} startPoint must match contour vertex');
        expect(hasEndMatch, isTrue, reason: 'Arc ${arc.id} endPoint must match contour vertex');
      }
    });

    test('2. CmsScalingController: Width scaled from 98 to 200mm preserves all 8 fillet arcs with zero error (SS2 fix)', () {
      final controller = CmsScalingController(
        baselineDocument: baselineDoc,
        contract: CmsProductContract.bend45,
        baselinePorts: baselinePorts,
      );

      // Select width parameter and evaluate morph to 200mm
      controller.selectParameter('width');
      controller.evaluateMorph(200.0);

      final scaled = controller.previewDocument;
      expect(scaled.arcs.length, equals(8), reason: 'All 8 fillet arcs must exist in scaled document');

      // Check each arc: radius must stay 10.0mm, and endpoints must stay 100% attached to contour vertices
      for (final arc in scaled.arcs) {
        expect(arc.radius, closeTo(10.0, 1e-2), reason: 'Fillet radius must stay 10mm');

        final minStartDist = scaled.outerContour.map((v) => v.distanceTo(arc.startPoint)).reduce(math.min);
        final minEndDist = scaled.outerContour.map((v) => v.distanceTo(arc.endPoint)).reduce(math.min);

        expect(
          minStartDist,
          lessThan(0.1),
          reason: 'Arc ${arc.id} startPoint must stay attached to contour vertex (distance: $minStartDist mm)',
        );
        expect(
          minEndDist,
          lessThan(0.1),
          reason: 'Arc ${arc.id} endPoint must stay attached to contour vertex (distance: $minEndDist mm)',
        );
      }

      // Contour vertex matching for canvas painter: simulate canvas_painter arc matching loop
      final matchedArcIds = <String>{};
      final contour = scaled.outerContour;
      final n = contour.length;
      for (int i = 0; i < n; i++) {
        final current = contour[i];
        for (final arc in scaled.arcs) {
          final isAtStart = current.distanceTo(arc.startPoint) < 2.0;
          final isAtEnd = current.distanceTo(arc.endPoint) < 2.0;
          if (isAtStart || isAtEnd) {
            final targetPoint = isAtStart ? arc.endPoint : arc.startPoint;
            final next = contour[(i + 1) % n];
            final prev = contour[(i - 1 + n) % n];
            if (next.distanceTo(targetPoint) < 2.0 || prev.distanceTo(targetPoint) < 2.0) {
              matchedArcIds.add(arc.id);
              break;
            }
          }
        }
      }
      expect(matchedArcIds.length, equals(8), reason: 'Canvas painter must successfully match all 8 arcs to contour corners');
    });

    test('3. Universal 95mm Coupler Rule on 45° Flat Bend: 2 slots at 100mm, 1 slot at 50mm', () {
      final controller = CmsScalingController(
        baselineDocument: baselineDoc,
        contract: CmsProductContract.bend45,
        baselinePorts: baselinePorts,
      );

      // Height = 100mm (>= 95mm): exactly 2 slots per region (8 slots total at 50mm pitch)
      controller.selectParameter('height');
      controller.evaluateMorph(100.0);
      var scaled = controller.previewDocument;
      expect(scaled.punches.length, equals(8));

      // Height = 50mm (< 95mm): exactly 1 slot centered per region (4 slots total)
      controller.evaluateMorph(50.0);
      scaled = controller.previewDocument;
      expect(scaled.punches.length, equals(4), reason: 'When height < 95mm, exactly 1 slot per region');

      // Verify all 8 arcs are STILL attached when height is scaled
      for (final arc in scaled.arcs) {
        final minStartDist = scaled.outerContour.map((v) => v.distanceTo(arc.startPoint)).reduce(math.min);
        final minEndDist = scaled.outerContour.map((v) => v.distanceTo(arc.endPoint)).reduce(math.min);
        expect(minStartDist, lessThan(0.1), reason: 'Arc ${arc.id} startPoint must remain attached at H=50mm');
        expect(minEndDist, lessThan(0.1), reason: 'Arc ${arc.id} endPoint must remain attached at H=50mm');
      }
    });

    test('4. Direct TopologicalZoneMorpher.morph produces synchronized arcs', () {
      final template = TemplateParameterDefinition(
        templateId: '45_deg_bend',
        name: '45 Deg Bend',
        category: 'Trunking Fittings',
        productType: 'Bend',
        baselineParameters: {'width': 98.0, 'height': 100.0, 'flangeWidth': 15.0},
        parameters: const [],
      );

      final morphed = TopologicalZoneMorpher.morph(
        baselineDocument: baselineDoc,
        template: template,
        targetParameters: {'width': 200.0, 'height': 100.0, 'flangeWidth': 15.0},
      );

      expect(morphed.arcs.length, equals(8));
      for (final arc in morphed.arcs) {
        expect(arc.radius, closeTo(10.0, 1e-2));
        final minStartDist = morphed.outerContour.map((v) => v.distanceTo(arc.startPoint)).reduce(math.min);
        final minEndDist = morphed.outerContour.map((v) => v.distanceTo(arc.endPoint)).reduce(math.min);
        expect(minStartDist, lessThan(0.1));
        expect(minEndDist, lessThan(0.1));
      }
    });
  });

  group('90° Flat Bend Parametric Scaling & Symmetry Tests', () {
    late DsfDocument baselineDoc90;
    late List<CmsPhysicalPort> baselinePorts90;

    setUp(() {
      final file = File('assets/dxf_templates/trunking_accessories/90_deg_bend_100x100.dsf');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      baselineDoc90 = DsfDocument.fromJson(json);

      baselinePorts90 = const [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 98.0, height: 100.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 98.0, height: 100.0),
      ];
    });

    test('1. Baseline verification: all 8 arcs attached, both ports equal, symmetric geometry (SS1 state)', () {
      expect(baselineDoc90.arcs.length, equals(8));
      for (final arc in baselineDoc90.arcs) {
        expect(arc.radius, closeTo(10.0, 1e-3));
        final hasStartMatch = baselineDoc90.outerContour.any((v) => v.distanceTo(arc.startPoint) < 0.1);
        final hasEndMatch = baselineDoc90.outerContour.any((v) => v.distanceTo(arc.endPoint) < 0.1);
        expect(hasStartMatch, isTrue, reason: 'Arc ${arc.id} startPoint must match contour vertex');
        expect(hasEndMatch, isTrue, reason: 'Arc ${arc.id} endPoint must match contour vertex');
      }

      // Check symmetry across xCenter
      final bounds = baselineDoc90.outerContour.map((v) => v.x);
      final minX = bounds.reduce(math.min);
      final maxX = bounds.reduce(math.max);
      final xCenter = (minX + maxX) / 2.0;
      expect(xCenter, closeTo(137.225, 0.01));
    });

    test('2. Scaling Width from 98 to 150mm: both Port 1 and Port 2 scale equally and symmetrically to 150mm', () {
      final controller = CmsScalingController(
        baselineDocument: baselineDoc90,
        contract: CmsProductContract.bend90,
        baselinePorts: baselinePorts90,
      );

      controller.selectParameter('width');
      controller.evaluateMorph(150.0);

      final scaled = controller.previewDocument;
      final ports = controller.currentPreview!.derivedPorts;

      expect(ports.length, equals(2), reason: 'Must have exactly 2 ports');
      final p1 = ports.firstWhere((p) => p.id == 'PORT_1');
      final p2 = ports.firstWhere((p) => p.id == 'PORT_2');

      expect(p1.width, closeTo(150.0, 1.0), reason: 'Port 1 width must scale to 150mm');
      expect(p2.width, closeTo(150.0, 1.0), reason: 'Port 2 width must scale to 150mm');
      expect((p1.width - p2.width).abs(), lessThan(0.5), reason: 'Both ports must scale equally');

      // Check that all 8 fillet arcs stay attached
      for (final arc in scaled.arcs) {
        final minStartDist = scaled.outerContour.map((v) => v.distanceTo(arc.startPoint)).reduce(math.min);
        final minEndDist = scaled.outerContour.map((v) => v.distanceTo(arc.endPoint)).reduce(math.min);
        expect(minStartDist, lessThan(0.1), reason: 'Arc ${arc.id} startPoint attached at W=150');
        expect(minEndDist, lessThan(0.1), reason: 'Arc ${arc.id} endPoint attached at W=150');
      }
    });

    test('3. Scaling Width from 98 to 200mm (SS2 fix): symmetric equal scaling, no asymmetric port distortion', () {
      final controller = CmsScalingController(
        baselineDocument: baselineDoc90,
        contract: CmsProductContract.bend90,
        baselinePorts: baselinePorts90,
      );

      controller.selectParameter('width');
      controller.evaluateMorph(200.0);

      final scaled = controller.previewDocument;
      final ports = controller.currentPreview!.derivedPorts;

      expect(ports.length, equals(2), reason: 'Must have exactly 2 ports');
      final p1 = ports.firstWhere((p) => p.id == 'PORT_1');
      final p2 = ports.firstWhere((p) => p.id == 'PORT_2');

      expect(p1.width, closeTo(200.0, 1.5), reason: 'Port 1 width must scale to 200mm');
      expect(p2.width, closeTo(200.0, 1.5), reason: 'Port 2 width must scale to 200mm');
      expect((p1.width - p2.width).abs(), lessThan(0.5), reason: 'Both ports must scale symmetrically and equally');

      // Check contour symmetry about xCenter
      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      final b1Center = (b1.p1.x + b1.p2.x) / 2.0;
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      final b2Center = (b2.p1.x + b2.p2.x) / 2.0;
      expect(b1Center, closeTo(137.225, 0.05), reason: 'Outer bend B1 must remain centered on symmetry axis');
      expect(b2Center, closeTo(137.225, 0.05), reason: 'Inner bend B2 must remain centered on symmetry axis');

      // Verify all 8 arcs are attached
      for (final arc in scaled.arcs) {
        final minStartDist = scaled.outerContour.map((v) => v.distanceTo(arc.startPoint)).reduce(math.min);
        final minEndDist = scaled.outerContour.map((v) => v.distanceTo(arc.endPoint)).reduce(math.min);
        expect(minStartDist, lessThan(0.1), reason: 'Arc ${arc.id} startPoint attached at W=200');
        expect(minEndDist, lessThan(0.1), reason: 'Arc ${arc.id} endPoint attached at W=200');
      }
    });

    test('4. Scaling Height from 100 to 150mm: both Port 1 and Port 2 heights scale to 150mm', () {
      final controller = CmsScalingController(
        baselineDocument: baselineDoc90,
        contract: CmsProductContract.bend90,
        baselinePorts: baselinePorts90,
      );

      controller.selectParameter('height');
      controller.evaluateMorph(150.0);

      final ports = controller.currentPreview!.derivedPorts;
      expect(ports.length, equals(2));
      final p1 = ports.firstWhere((p) => p.id == 'PORT_1');
      final p2 = ports.firstWhere((p) => p.id == 'PORT_2');

      expect(p1.height, closeTo(150.0, 1.0));
      expect(p2.height, closeTo(150.0, 1.0));
    });
  });
}
