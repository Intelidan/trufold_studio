import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/structural_topology_analyzer.dart';

void main() {
  group('StructuralTopologyAnalyzer Tests (3D Bend Topology & Contract Matching)', () {
    test('1. Analyzes 45_deg_bend_100x100.dsf using bend lines, folded topology, and catalog contract', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      expect(file.existsSync(), isTrue, reason: '45_deg_bend_100x100.dsf must exist');

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      // Verify baseline document elements
      expect(doc.outerContour.length, greaterThan(10));
      expect(doc.bends.length, greaterThanOrEqualTo(5), reason: 'Must contain bends B1-B5');
      expect(doc.punches.length, equals(8), reason: 'Must contain 8 coupler punch slots (4 at top inlet, 4 at bottom branch tabs)');

      // Run structural analysis
      final result = StructuralTopologyAnalyzer.analyze(
        doc,
        productType: 'Bend',
        variantName: '45 Deg Bend',
      );

      // 1. Verify Floor Web and Sidewalls identified
      expect(result.floorFace, isNotNull);
      expect(result.sidewallFaces.isNotEmpty, isTrue);

      // 2. Verify Ports discovered
      expect(result.detectedPorts.length, equals(2), reason: '45 Deg Bend has exactly 2 ports (Inlet & Outlet)');
      final port1 = result.detectedPorts[0];
      final port2 = result.detectedPorts[1];
      expect(port1.portId, equals('port1'));
      expect(port2.portId, equals('port2'));

      // 3. Verify Coupler Holes classified
      expect(result.couplerPunches.length, equals(8), reason: 'All 8 obround slots are coupler holes');
      for (final cp in result.couplerPunches) {
        expect(cp.isCoupler, isTrue);
        expect(cp.associatedPortId, isNotNull);
      }

      // 4. Verify Contract Matching & High Confidence
      expect(result.matchedContract, isNotNull);
      expect(result.matchedContract!.expectedPortCount, equals(2));
      expect(result.isHighConfidence, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.9));
    });
  });
}
