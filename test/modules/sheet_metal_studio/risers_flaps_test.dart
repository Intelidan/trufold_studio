import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';

void main() {
  final testConfigs = [
    {
      'path': 'assets/dsf_templates/tray_accessories/45_deg_outside_riser_100_50.dsf',
      'contract': CmsProductContract.outsideRiser45,
    },
    {
      'path': 'assets/dsf_templates/tray_accessories/90_deg_inside_riser_100x50.dsf',
      'contract': CmsProductContract.insideRiser90,
    },
    {
      'path': 'assets/dsf_templates/tray_accessories/90_deg_outside_riser_100X50.dsf',
      'contract': CmsProductContract.outsideRiser90,
    },
    {
      'path': 'assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf',
      'contract': CmsProductContract.insideRiser45,
    },
  ];

  for (final cfg in testConfigs) {
    final path = cfg['path'] as String;
    final contract = cfg['contract'] as CmsProductContract;

    test('Coupler flaps and hole visibility for $path', () {
      final f = File(path);
      final dsf = DsfDocument.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);

      const dummyPorts = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
      ];

      final ctrl = CmsScalingController(
        baselineDocument: dsf,
        contract: contract,
        baselinePorts: dummyPorts,
      );

      // Baseline: flaps off
      expect(ctrl.includeCouplerFlaps, isFalse);
      final previewNoFlaps = ctrl.previewDocument;
      expect(previewNoFlaps.faces.any((face) => face.id.startsWith('F_FLAP_RISER_')), isFalse);
      expect(previewNoFlaps.bends.any((b) => b.id.startsWith('BF_RISER_')), isFalse);

      final bodyCouplersNoFlaps = previewNoFlaps.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      for (final p in bodyCouplersNoFlaps) {
        expect(p.isVisible, isTrue, reason: 'Body coupler punches should be visible when flaps are disabled');
      }

      // Turn on coupler flaps
      ctrl.setIncludeCouplerFlaps(true);
      expect(ctrl.includeCouplerFlaps, isTrue);
      final previewWithFlaps = ctrl.previewDocument;

      final flapFaces = previewWithFlaps.faces.where((face) => face.id.startsWith('F_FLAP_RISER_')).toList();
      expect(flapFaces.length, equals(4), reason: 'Must synthesize exactly 4 coupler flaps on $path');
      for (final flap in flapFaces) {
        expect(flap.vertices.length, equals(6), reason: 'Each flap must have 6 chamfered vertices');
      }

      final flapBends = previewWithFlaps.bends.where((b) => b.id.startsWith('BF_RISER_')).toList();
      expect(flapBends.length, equals(4), reason: 'Must synthesize exactly 4 flap root bends');

      // Verify body coupler punches are hidden and flap punches are visible
      final bodyCouplersWithFlaps = previewWithFlaps.punches
          .where((p) => p.role == CncPunchRole.coupler && !p.id.startsWith('FLAP_SLOT_RISER_'))
          .toList();
      for (final p in bodyCouplersWithFlaps) {
        expect(p.isVisible, isFalse, reason: 'Body coupler punch ${p.id} must be hidden when flaps are active');
      }

      final flapPunches = previewWithFlaps.punches.where((p) => p.id.startsWith('FLAP_SLOT_RISER_')).toList();
      expect(flapPunches.length, equals(12), reason: '4 flaps * 3 slots = 12 flap slots');
      for (final p in flapPunches) {
        expect(p.isVisible, isTrue, reason: 'Flap punch ${p.id} must be visible');
      }

      // Verify 3D folding: All 4 flaps fold vertically (|normal.z| < 0.15)
      final foldResult = KinematicFoldEngine.foldDocument(previewWithFlaps, foldProgress: 1.0);
      for (final flap in flapFaces) {
        final polys = foldResult.polygons.where((p) => p.faceId == flap.id).toList();
        expect(polys, isNotEmpty, reason: '${flap.id} must exist in 3D mesh');
        for (final poly in polys) {
          expect(poly.normal.z.abs(), lessThan(0.15), reason: '${flap.id} must fold vertically with sidewall');
        }
      }

      // Verify opening detection: strictly 2 terminal ports (no spurious openings on flaps)
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: previewWithFlaps, foldResult: foldResult);
      expect(rawOpenings.length, equals(2), reason: 'Must detect exactly 2 terminal openings with flaps active on $path');
    });
  }
}
