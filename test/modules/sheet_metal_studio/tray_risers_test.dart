import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';

void main() {
  final riserConfigs = [
    {
      'id': 'SS1',
      'name': '45° Outside Riser',
      'path': 'assets/dsf_templates/tray_accessories/45_deg_outside_riser_100_50.dsf',
      'contract': CmsProductContract.outsideRiser45,
    },
    {
      'id': 'SS2',
      'name': '90° Inside Riser',
      'path': 'assets/dsf_templates/tray_accessories/90_deg_inside_riser_100x50.dsf',
      'contract': CmsProductContract.insideRiser90,
    },
    {
      'id': 'SS3',
      'name': '90° Outside Riser',
      'path': 'assets/dsf_templates/tray_accessories/90_deg_outside_riser_100X50.dsf',
      'contract': CmsProductContract.outsideRiser90,
    },
    {
      'id': 'SS4',
      'name': '45° Inside Riser',
      'path': 'assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf',
      'contract': CmsProductContract.insideRiser45,
    },
  ];

  group('Cable Tray Risers Comprehensive Verification (SS1 - SS4)', () {
    for (final cfg in riserConfigs) {
      final riserId = cfg['id'] as String;
      final name = cfg['name'] as String;
      final path = cfg['path'] as String;
      final contract = cfg['contract'] as CmsProductContract;

      group('$riserId: $name ($path)', () {
        late DsfDocument doc;

        setUp(() {
          final file = File(path);
          expect(file.existsSync(), isTrue, reason: 'Template file must exist: $path');
          final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          doc = DsfDocument.fromJson(jsonMap);
        });

        test('1. 3D Port Identification: Detects exactly 2 terminal mouth openings', () {
          final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
          final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: doc, foldResult: foldResult);
          expect(rawOpenings.length, equals(2), reason: '$name must detect exactly 2 terminal openings in 3D');

          final ports = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: doc, foldResult: foldResult)).toList();
          if (name.contains('90° Outside')) {
            final p1 = ports.firstWhere((p) => p.flatP1.y < 200.0);
            final p2 = ports.firstWhere((p) => p.flatP1.y > 200.0);
            expect(p1.flatP1.y, closeTo(20.0, 1.0), reason: 'Port 1 must be at top mouth coupler line y=20mm');
            expect(p2.flatP1.y, closeTo(380.0, 1.0), reason: 'Port 2 must be at bottom mouth coupler line y=380mm');
            expect(p1.normal.y, closeTo(-0.707, 0.05), reason: 'Port 1 3D normal must tilt outward along 45° arm');
            expect(p1.normal.z, closeTo(-0.707, 0.05), reason: 'Port 1 3D normal must have -Z component along arm');
            expect(p2.normal.y, closeTo(0.707, 0.05), reason: 'Port 2 3D normal must tilt outward along 45° arm');
            expect(p2.normal.z, closeTo(-0.707, 0.05), reason: 'Port 2 3D normal must have -Z component along arm');
          }
          for (final p in ports) {
            expect(p.width, closeTo(100.0, 1.0), reason: 'Port width must be exactly 100mm baseline');
            expect(p.height, closeTo(50.0, 1.0), reason: 'Port height must be exactly 50mm baseline');
          }
        });

        test('2. Coupler Flaps Synthesis & 3D Upright Folding', () {
          const dummyPorts = [
            CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
            CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
          ];

          final ctrl = CmsScalingController(
            baselineDocument: doc,
            contract: contract,
            baselinePorts: dummyPorts,
          );

          ctrl.setIncludeCouplerFlaps(true);
          final flapsDoc = ctrl.previewDocument;

          final flapFaces = flapsDoc.faces.where((f) => f.id.startsWith('F_FLAP_RISER_')).toList();
          expect(flapFaces.length, equals(4), reason: 'Must have 4 synthesized coupler flaps (2 per port)');

          for (final f in flapFaces) {
            expect(f.vertices.length, equals(6), reason: 'Each flap must be a 6-vertex chamfered polygon');
          }

          final flapBends = flapsDoc.bends.where((b) => b.id.startsWith('BF_RISER_')).toList();
          expect(flapBends.length, equals(4), reason: 'Must have 4 flap bend lines');
          for (final b in flapBends) {
            expect(b.targetAngleDeg, equals(0.0), reason: 'Flap bends must be coplanar (0°) with sidewalls');
          }

          // Verify 3D folding: flaps fold upright with sidewalls and raw openings remain strictly 2
          final foldFlaps = KinematicFoldEngine.foldDocument(flapsDoc, foldProgress: 1.0);
          final rawOpeningsWithFlaps = Cms3DOpeningDetector.detectOpenings(document: flapsDoc, foldResult: foldFlaps);
          expect(rawOpeningsWithFlaps.length, equals(2), reason: 'Coupler flaps must not create phantom mouth openings');
        });

        test('3. Coupler Holes Hide/Unhide Toggle', () {
          const dummyPorts = [
            CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
            CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
          ];

          final ctrl = CmsScalingController(
            baselineDocument: doc,
            contract: contract,
            baselinePorts: dummyPorts,
          );

          // With flaps enabled: body coupler holes must be hidden
          ctrl.setIncludeCouplerFlaps(true);
          final activeDoc = ctrl.previewDocument;
          final hiddenHoles = activeDoc.punches.where((p) => p.role == CncPunchRole.coupler && !p.id.startsWith('FLAP_SLOT_RISER_') && !p.isVisible).toList();
          expect(hiddenHoles.isNotEmpty, isTrue, reason: 'Body coupler holes must be hidden when flaps are active');

          // With flaps disabled: body coupler holes must be restored
          ctrl.setIncludeCouplerFlaps(false);
          final restoredDoc = ctrl.previewDocument;
          final allUnhidden = restoredDoc.punches.where((p) => p.role == CncPunchRole.coupler && !p.isVisible).toList();
          expect(allUnhidden.isEmpty, isTrue, reason: 'All coupler holes must be visible when flaps are disabled');
        });

        test('4. Parametric Width Scaling (100 -> 200mm)', () {
          const dummyPorts = [
            CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
            CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
          ];

          final ctrl = CmsScalingController(
            baselineDocument: doc,
            contract: contract,
            baselinePorts: dummyPorts,
          );

          ctrl.selectParameter('width');
          ctrl.evaluateMorph(200.0);
          final scaledW = ctrl.currentPreview!.scaledDocument;

          final foldW = KinematicFoldEngine.foldDocument(scaledW, foldProgress: 1.0);
          final rawW = Cms3DOpeningDetector.detectOpenings(document: scaledW, foldResult: foldW);
          expect(rawW.length, equals(2), reason: 'Width scaled riser must retain exactly 2 terminal openings');

          final portsW = rawW.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledW, foldResult: foldW)).toList();
          for (final p in portsW) {
            expect(p.width, closeTo(200.0, 10.0), reason: 'Scaled port width must be close to 200mm');
            expect(p.height, closeTo(50.0, 5.0), reason: 'Port height must remain ~50mm when only width is scaled');
          }
        });

        test('5. Parametric Height Scaling (50 -> 100mm)', () {
          const dummyPorts = [
            CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
            CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
          ];

          final ctrl = CmsScalingController(
            baselineDocument: doc,
            contract: contract,
            baselinePorts: dummyPorts,
          );

          ctrl.selectParameter('height');
          ctrl.evaluateMorph(100.0);
          final scaledH = ctrl.currentPreview!.scaledDocument;

          final foldH = KinematicFoldEngine.foldDocument(scaledH, foldProgress: 1.0);
          final rawH = Cms3DOpeningDetector.detectOpenings(document: scaledH, foldResult: foldH);
          expect(rawH.length, equals(2), reason: 'Height scaled riser must retain exactly 2 terminal openings');

          final portsH = rawH.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledH, foldResult: foldH)).toList();
          for (final p in portsH) {
            expect(p.height, closeTo(100.0, 5.0), reason: 'Scaled port height must be close to 100mm');
          }
          if (name.contains('90° Outside')) {
            final midPunches = scaledH.punches.where((p) => (p.center.y - 200.0).abs() < 1.0).toList();
            expect(midPunches.length, equals(4), reason: 'Height 100mm must synthesize 4 centralized slots on middle wall');
            final armPunches = scaledH.punches.where((p) => (p.center.y - 200.0).abs() > 10.0).toList();
            expect(armPunches.length, equals(32), reason: 'Height 100mm must synthesize 4 columns x 2 rows x 4 arm regions = 32 slots');
          }
        });

        test('6. Parametric Cover Generation for Baseline & Scaled Parts', () {
          // Baseline cover
          final baseCover = TrunkingCoverGenerator.generateCover(doc);
          expect(baseCover, isNotNull, reason: 'Cover must be generated for baseline $name');
          final foldBaseCover = KinematicFoldEngine.foldDocument(baseCover!.document, foldProgress: 1.0);
          expect(foldBaseCover.polygons.length, greaterThanOrEqualTo(1), reason: 'Baseline cover must fold in 3D');

          // Scaled width cover
          final ctrl = CmsScalingController(
            baselineDocument: doc,
            contract: contract,
            baselinePorts: const [
              CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
              CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
            ],
          );
          ctrl.selectParameter('width');
          ctrl.evaluateMorph(200.0);
          final scaledW = ctrl.currentPreview!.scaledDocument;

          final scaledCover = TrunkingCoverGenerator.generateCover(scaledW);
          expect(scaledCover, isNotNull, reason: 'Cover must be generated for width-scaled $name');
          final foldScaledCover = KinematicFoldEngine.foldDocument(scaledCover!.document, foldProgress: 1.0);
          expect(foldScaledCover.polygons.length, greaterThanOrEqualTo(1), reason: 'Width-scaled cover must fold in 3D');
        });
      });
    }
  });
}
