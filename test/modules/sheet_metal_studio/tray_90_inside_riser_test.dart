import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_port_matcher.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';

void main() {
  group('Cable Tray 90° Inside Riser Diagnostic & Regression Tests', () {
    late DsfDocument doc;

    setUp(() {
      final file = File('assets/dsf_templates/tray_accessories/90_deg_inside_riser_100x50.dsf');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      doc = DsfDocument.fromJson(json);
    });

    test('1. Baseline Port Detection: accurately detect Port 1 (top) and Port 2 (bottom) at terminal openings', () {
      final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: doc, foldResult: foldResult);
      expect(rawOpenings.length, equals(2), reason: 'Must detect exactly 2 terminal openings');

      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: doc, foldResult: foldResult)).toList();
      for (final m in measured) {
        expect(m.width, closeTo(100.0, 5.0), reason: 'Channel width must be 100mm, not 150mm');
        expect(m.height, closeTo(50.0, 5.0), reason: 'Cheek height must be 50mm');
      }

      final matchResult = CmsPortMatcher.match(measuredOpenings: measured, contract: CmsProductContract.insideRiser90);
      expect(matchResult.matchedPorts.length, equals(2));
      final p1 = matchResult.matchedPorts.firstWhere((p) => p.index == 1);
      final p2 = matchResult.matchedPorts.firstWhere((p) => p.index == 2);

      // Port 1 is at top (y ~ 20 in 2D), Port 2 is at bottom (y ~ 380 in 2D)
      expect(p1.width, closeTo(100.0, 5.0));
      expect(p2.width, closeTo(100.0, 5.0));

      // 3D outward normals:
      // Top port slopes UP along -Y: (0, -0.707, 0.707)
      expect(p1.normal.y, closeTo(-1.0 / math.sqrt(2), 0.05));
      expect(p1.normal.z, closeTo(1.0 / math.sqrt(2), 0.05));

      // Bottom port slopes UP along +Y: (0, 0.707, 0.707)
      expect(p2.normal.y, closeTo(1.0 / math.sqrt(2), 0.05));
      expect(p2.normal.z, closeTo(1.0 / math.sqrt(2), 0.05));
    });

    test('2. Coupler flap slots on vertical risers must be 3 parallel obrounds (rotationDeg: 0.0)', () {
      final ctrl = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.insideRiser90,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        ],
      );

      ctrl.setIncludeCouplerFlaps(true);
      final flapsDoc = ctrl.previewDocument;
      final flapSlots = flapsDoc.punches.where((p) => p.id.startsWith('FLAP_SLOT_RISER_')).toList();
      expect(flapSlots.length, equals(12), reason: '4 flaps * 3 slots = 12 slots');

      for (final slot in flapSlots) {
        expect(slot.rotationDeg, equals(0.0), reason: 'Vertical riser flap slots must have rotationDeg = 0.0 to be parallel to cheek height');
      }
    });

    test('3. Height scaling > 75mm (e.g. 125mm) preserves vertical riser orientation and 3D folding', () {
      final ctrl = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.insideRiser90,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        ],
      );

      ctrl.setIncludeCouplerFlaps(true);
      ctrl.selectParameter('height');
      ctrl.evaluateMorph(125.0);

      final scaledDoc = ctrl.previewDocument;

      // Cheek bends must be recognized as vertical cheek bends
      // Flaps must be attached to the mouths (P1 at top y < 200, P2 at bottom y > 200), NOT side walls
      final flapFaces = scaledDoc.faces.where((f) => f.id.startsWith('F_FLAP_RISER_')).toList();
      expect(flapFaces.length, equals(4), reason: 'Must have 4 synthesized flaps');

      final p1Flaps = flapFaces.where((f) => f.id.contains('P1')).toList();
      final p2Flaps = flapFaces.where((f) => f.id.contains('P2')).toList();
      expect(p1Flaps.length, equals(2));
      expect(p2Flaps.length, equals(2));

      for (final f in p1Flaps) {
        final minY = f.vertices.map((v) => v.y).reduce(math.min);
        expect(minY, lessThan(100.0), reason: 'P1 flaps must be at the top mouth');
      }

      for (final f in p2Flaps) {
        final maxY = f.vertices.map((v) => v.y).reduce(math.max);
        expect(maxY, greaterThan(300.0), reason: 'P2 flaps must be at the bottom mouth');
      }

      // 3D folding must retain 2 mouth openings
      final foldResult = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: foldResult);
      expect(rawOpenings.length, equals(2), reason: 'Must detect exactly 2 terminal openings after scaling height to 125mm');

      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledDoc, foldResult: foldResult)).toList();
      for (final m in measured) {
        expect(m.height, closeTo(125.0, 5.0), reason: 'Scaled height must be close to 125mm');
        expect(m.width, closeTo(100.0, 5.0), reason: 'Width must remain 100mm');
      }
    });

    test('4. 3-Bug Regression: baseline height 50mm, 3D port alignment passing through outer coupler holes, bounded flap slot length', () {
      final foldInit = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      final rawInit = Cms3DOpeningDetector.detectOpenings(document: doc, foldResult: foldInit);
      final measuredInit = rawInit.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: doc, foldResult: foldInit)).toList();
      final portsInit = CmsPortMatcher.match(measuredOpenings: measuredInit, contract: CmsProductContract.insideRiser90).matchedPorts;

      final ctrl = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.insideRiser90,
        baselinePorts: portsInit,
      );
      // Bug 1: Template height must be recognized as 50.0mm (not 75mm)
      expect(ctrl.model.parameters['height']?.baselineValue, equals(50.0), reason: 'Baseline height must be 50.0mm');
      expect(ctrl.model.parameters['width']?.baselineValue, equals(100.0), reason: 'Baseline width must be 100.0mm');

      ctrl.setIncludeCouplerFlaps(true);
      final flapsDoc = ctrl.previewDocument;
      final foldResult = KinematicFoldEngine.foldDocument(flapsDoc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: flapsDoc, foldResult: foldResult);
      expect(rawOpenings.length, 2);

      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: flapsDoc, foldResult: foldResult)).toList();
      for (final m in measured) {
        expect(m.width, closeTo(100.0, 5.0));
        expect(m.height, closeTo(50.0, 5.0));
        // Bug 2: 3D port floor edges must be elevated on the 3D sloped mouth (>70mm in Z, not 0.0 on flat ground)
        expect(m.floorP1.z, greaterThan(70.0), reason: 'Floor P1 must be on the 3D sloped mouth, not flat at Z=0');
        expect(m.floorP2.z, greaterThan(70.0), reason: 'Floor P2 must be on the 3D sloped mouth, not flat at Z=0');
      }

      // Check flat coordinates pass through outer coupler hole rows (y=20 for top, y=380 for bottom)
      final topPort = measured.firstWhere((m) => m.flatP1.y < 100.0);
      final bottomPort = measured.firstWhere((m) => m.flatP1.y > 300.0);
      expect(topPort.flatP1.y, closeTo(20.0, 1.0), reason: 'Top port line must pass through outer coupler hole row at y=20');
      expect(bottomPort.flatP1.y, closeTo(380.0, 1.0), reason: 'Bottom port line must pass through outer coupler hole row at y=380');

      // Coupler Flap Obround Hole Rule: The end of the coupler obround holes must be at a 10mm margin
      // from the flap's top and bottom borders: slotLen = H - 20mm (e.g. H=50 -> 30mm, H=100 -> 80mm, H=125 -> 105mm, H=150 -> 130mm)
      final flapSlots50 = flapsDoc.punches.where((p) => p.id.contains('FLAP_SLOT_RISER')).toList();
      expect(flapSlots50.isNotEmpty, isTrue);
      for (final s in flapSlots50) {
        expect(s.lengthMm, closeTo(30.0, 1e-3), reason: 'At H=50mm, flap slot length must be 30mm (50 - 20mm margins)');
      }

      // Scale height to 100mm and verify flap slots elongate to 80mm
      ctrl.selectParameter('height');
      ctrl.evaluateMorph(100.0);
      final scaledDoc100 = ctrl.previewDocument;
      final scaledFlapSlots100 = scaledDoc100.punches.where((p) => p.id.contains('FLAP_SLOT_RISER')).toList();
      expect(scaledFlapSlots100.isNotEmpty, isTrue);
      for (final s in scaledFlapSlots100) {
        expect(s.lengthMm, closeTo(80.0, 1e-3), reason: 'At H=100mm, flap slot length must be 80mm (100 - 20mm margins)');
      }

      // Scale height to 125mm and verify flap slots elongate to 105mm
      ctrl.evaluateMorph(125.0);
      final scaledDoc125 = ctrl.previewDocument;
      final scaledFlapSlots125 = scaledDoc125.punches.where((p) => p.id.contains('FLAP_SLOT_RISER')).toList();
      expect(scaledFlapSlots125.isNotEmpty, isTrue);
      for (final s in scaledFlapSlots125) {
        expect(s.lengthMm, closeTo(105.0, 1e-3), reason: 'At H=125mm, flap slot length must be 105mm (125 - 20mm margins)');
      }

      // Scale height to 150mm and verify flap slots elongate to 130mm
      ctrl.evaluateMorph(150.0);
      final scaledDoc150 = ctrl.previewDocument;
      final scaledFlapSlots150 = scaledDoc150.punches.where((p) => p.id.contains('FLAP_SLOT_RISER')).toList();
      expect(scaledFlapSlots150.isNotEmpty, isTrue);
      for (final s in scaledFlapSlots150) {
        expect(s.lengthMm, closeTo(130.0, 1e-3), reason: 'At H=150mm, flap slot length must be 130mm (150 - 20mm margins)');
      }
    });

    test('5. Sidewall angular cuts adapt to height scaling (SS2 fix): edges meet in 3D without overlapping or colliding', () {
      final ctrl = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.insideRiser90,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        ],
      );

      for (final testH in [75.0, 100.0, 150.0]) {
        ctrl.selectParameter('height');
        ctrl.evaluateMorph(testH);
        final mesh = ctrl.currentPreview!.foldedMesh;

        // Verify adjacent cheek faces F_1 and F_6 meet at the miter seam in 3D
        final p1 = mesh.polygons.firstWhere((p) => p.faceId == 'F_1');
        final p6 = mesh.polygons.firstWhere((p) => p.faceId == 'F_6');
        double minLeftSeam = double.infinity;
        for (final v1 in p1.vertices) {
          for (final v6 in p6.vertices) {
            final d = (v1.x - v6.x).abs() + (v1.y - v6.y).abs() + (v1.z - v6.z).abs();
            if (d < minLeftSeam) minLeftSeam = d;
          }
        }
        expect(minLeftSeam, lessThan(1.5), reason: 'At H=$testH, F_1 and F_6 miter seam must meet in 3D without gap');

        // All 6 sidewall cheeks must fold strictly vertical (normal.x = ±1, normal.y ≈ 0, normal.z ≈ 0)
        for (final cheekId in ['F_1', 'F_6', 'F_11', 'F_3', 'F_8', 'F_13']) {
          final poly = mesh.polygons.firstWhere((p) => p.faceId == cheekId);
          expect(poly.normal.x.abs(), closeTo(1.0, 0.05), reason: 'Cheek $cheekId must be vertical');
          expect(poly.normal.y.abs(), lessThan(0.05));
          expect(poly.normal.z.abs(), lessThan(0.05));
        }
      }
    });

    test('6. Coupler hole scaling along height, 1/2 holes rule for straight wall, and round-trip scaling', () {
      final ctrl = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.insideRiser90,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        ],
      );

      // --- H = 50mm (baseline) ---
      ctrl.selectParameter('height');
      ctrl.evaluateMorph(50.0);
      final doc50 = ctrl.previewDocument;
      final midSlots50 = doc50.punches.where((p) => p.role == CncPunchRole.general).toList();
      // For H < 100mm: 1 hole per side = 2 total
      expect(midSlots50.length, equals(2), reason: 'At H=50 (<100mm), exactly 1 hole in center per side');
      expect(midSlots50.first.center.y, closeTo(200.0, 0.5));
      expect(midSlots50.first.center.x, closeTo(63.0 - 25.0, 1.0)); // centered at x1 - H/2

      // --- H = 75mm ---
      ctrl.evaluateMorph(75.0);
      final doc75 = ctrl.previewDocument;
      final midSlots75 = doc75.punches.where((p) => p.role == CncPunchRole.general).toList();
      expect(midSlots75.length, equals(2), reason: 'At H=75 (<100mm), exactly 1 hole in center per side');

      // Check coupler columns: slotCols = max(1, (75/25).round()) = 3 columns
      final armSlots75P1Left = doc75.punches.where((p) => p.role == CncPunchRole.coupler && p.center.y < 100.0 && p.center.x < 63.0).toList();
      final distinctXs75 = armSlots75P1Left.map((p) => (p.center.x * 10).round() / 10).toSet();
      expect(distinctXs75.length, equals(3), reason: 'At H=75mm, must have 3 columns of coupler slots along cheek height');

      // --- H = 100mm ---
      ctrl.evaluateMorph(100.0);
      final doc100 = ctrl.previewDocument;
      final midSlots100 = doc100.punches.where((p) => p.role == CncPunchRole.general).toList();
      // For H >= 100mm: 2 holes per side = 4 total
      expect(midSlots100.length, equals(4), reason: 'At H=100 (>=100mm), exactly 2 holes per side at 50mm pitch');
      final leftMidXs = midSlots100.where((p) => p.center.x < 63.0).map((p) => p.center.x).toList()..sort();
      expect(leftMidXs.length, 2);
      expect((leftMidXs.last - leftMidXs.first).abs(), closeTo(50.0, 1.0), reason: '2 holes must be at 50mm pitch');

      // --- Round-trip scaling (50 -> 75 -> 50mm) to verify no 25mm offset/gap ---
      ctrl.evaluateMorph(75.0);
      expect(ctrl.previewDocument.parameters['height'], equals(75.0));

      ctrl.evaluateMorph(50.0);
      expect(ctrl.previewDocument.parameters['height'], equals(50.0), reason: 'Must return to 50mm, NOT 25mm (no 25mm gap)');
      final leftCheekBend = ctrl.previewDocument.bends.firstWhere((b) => (b.p1.x - 63.0).abs() < 1.0);
      final leftFlangeBend = ctrl.previewDocument.bends.firstWhere((b) => b.id == 'FL1');
      expect((leftCheekBend.p1.x - leftFlangeBend.p1.x).abs(), closeTo(50.0, 1.0), reason: 'Cheek width must return to exactly 50mm');
    });
  });
}
