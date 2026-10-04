import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_port_matcher.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';

void main() {
  group('Cable Tray 45° Inside Riser Port Detection, Cover & Scaling Tests', () {
    test('1. Accurately detect Port 1 and Port 2 at terminal openings with identical dimensions', () async {
      final file = File('assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: doc, foldResult: foldResult);
      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: doc, foldResult: foldResult)).toList();

      final contract = CmsProductContract.insideRiser45;
      final matchResult = CmsPortMatcher.match(measuredOpenings: measured, contract: contract);
      expect(matchResult.requiresUserResolution, isFalse);
      expect(matchResult.matchedPorts.length, equals(2));

      final p1 = matchResult.matchedPorts.firstWhere((p) => p.index == 1);
      final p2 = matchResult.matchedPorts.firstWhere((p) => p.index == 2);
      expect(p1.width, equals(p2.width));
      expect(p1.height, equals(p2.height));
      expect(p1.width, closeTo(100.0, 1.0));
      expect(p1.height, closeTo(50.0, 1.0));

      // Normal orientations: Port 1 is angled along [-0.707, 0, 0.707], Port 2 is straight along [1, 0, 0]
      expect(p1.normal.x, closeTo(-0.707, 0.05));
      expect(p1.normal.z, closeTo(0.707, 0.05));
      expect(p2.normal.x, closeTo(1.0, 0.05));
      expect(p2.normal.z.abs(), lessThan(0.05));
    });

    test('2. Generate 2-plane angular cover matching body angle with 4 drop flanges and 45° roof bend', () async {
      final file = File('assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      final coverData = TrunkingCoverGenerator.generateCover(doc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      final ext1Face = coverDoc.faces.firstWhere((f) => f.id == 'COVER_EXT_FACE_1');

      final xs = mainFace.vertices.map((v) => v.x).toList();
      final ys = mainFace.vertices.map((v) => v.y).toList();
      final lenX = xs.reduce(math.max) - xs.reduce(math.min);
      final widthY = ys.reduce(math.max) - ys.reduce(math.min);

      expect(lenX, closeTo(150.0, 1.0));
      expect(widthY, closeTo(100.0 + 2 * TrunkingCoverGenerator.defaultCoverClearanceOffset, 1.0));

      final extXs = ext1Face.vertices.map((v) => v.x).toList();
      final extLenX = extXs.reduce(math.max) - extXs.reduce(math.min);
      expect(extLenX, closeTo(150.0, 1.0));

      // 4 side drop flanges: 2 on flat arm, 2 on rising arm with miter relief notches
      final flanges = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flanges.length, equals(4));

      // 45° transverse roof bend connecting the 2 planes
      final roofBend = coverDoc.bends.firstWhere((b) => b.id == 'C_ROOF_B1');
      expect(roofBend.targetAngleDeg, closeTo(45.0, 0.1));
      expect(roofBend.direction, equals(BendDirection.up));

      // Verify 3D folding of 2-plane angular cover
      final coverMesh = KinematicFoldEngine.foldDocument(coverDoc, foldProgress: 1.0, ensureBaseFloorAtBottom: false);
      expect(coverMesh.polygons.length, greaterThanOrEqualTo(6));

      final mainPoly = coverMesh.polygons.firstWhere((p) => p.faceId == 'COVER_MAIN_FACE');
      final extPoly = coverMesh.polygons.firstWhere((p) => p.faceId == 'COVER_EXT_FACE_1');

      // Main face normal is flat (0, 0, 1)
      expect(mainPoly.normal.x.abs(), lessThan(0.05));
      expect(mainPoly.normal.y.abs(), lessThan(0.05));
      expect(mainPoly.normal.z, closeTo(1.0, 0.05));

      // Ext face bends 45° UP along -X: normal is inclined at 45° (+0.707, 0, 0.707) matching F_5 floor
      expect(extPoly.normal.x, closeTo(0.707, 0.05));
      expect(extPoly.normal.y.abs(), lessThan(0.05));
      expect(extPoly.normal.z, closeTo(0.707, 0.05));
    });

    test('3. Width scaling to 200mm expands floor symmetrically with matching scaled ports and cover', () async {
      final file = File('assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      final contract = CmsProductContract.insideRiser45;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: doc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        ],
      );

      controller.selectParameter('width');
      controller.evaluateMorph(200.0);
      final scaledDoc = controller.currentPreview!.scaledDocument;

      // Verify cheek bend distance is now 99 + 100 = 199mm
      final cheekBends = scaledDoc.bends
          .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
          .toList()
        ..sort((a, b) => ((a.p1.y + a.p2.y) / 2.0).compareTo((b.p1.y + b.p2.y) / 2.0));
      final y1 = (cheekBends.first.p1.y + cheekBends.first.p2.y) / 2.0;
      final y2 = (cheekBends.last.p1.y + cheekBends.last.p2.y) / 2.0;
      expect(y2 - y1, closeTo(200.0, 0.1));

      // Verify 3D folding and port detection
      final foldResult = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: foldResult);
      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledDoc, foldResult: foldResult)).toList();
      final matchResult = CmsPortMatcher.match(measuredOpenings: measured, contract: contract);
      final p1 = matchResult.matchedPorts.firstWhere((p) => p.index == 1);
      final p2 = matchResult.matchedPorts.firstWhere((p) => p.index == 2);
      expect(p1.width, closeTo(200.0, 1.0));
      expect(p2.width, closeTo(200.0, 1.0));
      expect(p1.height, closeTo(50.0, 1.0));
      expect(p2.height, closeTo(50.0, 1.0));

      // Verify scaled cover
      final coverData = TrunkingCoverGenerator.generateCover(scaledDoc);
      expect(coverData, isNotNull);
      final mainFace = coverData!.document.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      final ys = mainFace.vertices.map((v) => v.y).toList();
      final widthY = ys.reduce(math.max) - ys.reduce(math.min);
      expect(widthY, closeTo(199.0 + 2 * TrunkingCoverGenerator.defaultCoverClearanceOffset, 1.0));
    });

    test('4. Height scaling to 100mm expands sidewalls without distorting floor web, B5 or channel length', () async {
      final file = File('assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      final contract = CmsProductContract.insideRiser45;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: doc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        ],
      );

      controller.selectParameter('height');
      controller.evaluateMorph(100.0);
      final scaledDoc = controller.currentPreview!.scaledDocument;

      // Verify B5 remains invariant in position
      final b5 = scaledDoc.bends.firstWhere((b) => b.id == 'B5');
      expect(b5.p1.x, closeTo(150.0, 0.1));
      expect(b5.p2.x, closeTo(150.0, 0.1));
      expect(b5.p1.y, closeTo(63.0, 0.1));
      expect(b5.p2.y, closeTo(163.0, 0.1));

      // Verify 3D folding and port detection
      final foldResult = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: foldResult);
      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledDoc, foldResult: foldResult)).toList();
      final matchResult = CmsPortMatcher.match(measuredOpenings: measured, contract: contract);
      final p1 = matchResult.matchedPorts.firstWhere((p) => p.index == 1);
      final p2 = matchResult.matchedPorts.firstWhere((p) => p.index == 2);
      expect(p1.width, closeTo(100.0, 1.0));
      expect(p2.width, closeTo(100.0, 1.0));
      expect(p1.height, closeTo(100.0, 1.0));
      expect(p2.height, closeTo(100.0, 1.0));

      // Verify cover generation on height-scaled part
      final coverData = TrunkingCoverGenerator.generateCover(scaledDoc);
      expect(coverData, isNotNull);
    });

    test('5. Full 650x200mm scaling: body height matches port height (200mm) and 2-plane angular cover fits body', () async {
      final file = File('assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      final contract = CmsProductContract.insideRiser45;
      final controller = CmsScalingController(
        contract: contract,
        baselineDocument: doc,
        baselinePorts: const [
          CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
          CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
        ],
      );

      // Scale width to 650mm and height to 200mm
      controller.selectParameter('width');
      controller.evaluateMorph(650.0);

      controller.selectParameter('height');
      controller.evaluateMorph(200.0);
      final scaledDoc = controller.currentPreview!.scaledDocument;

      // Verify sidewall cheek height in 2D is 213mm (baseline 63 + delta 150)
      final cheekBends = scaledDoc.bends
          .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
          .toList()
        ..sort((a, b) => ((a.p1.y + a.p2.y) / 2.0).compareTo((b.p1.y + b.p2.y) / 2.0));
      final y1 = (cheekBends.first.p1.y + cheekBends.first.p2.y) / 2.0;
      final y2 = (cheekBends.last.p1.y + cheekBends.last.p2.y) / 2.0;
      final channelW = (y2 - y1).abs();
      expect(channelW, closeTo(650.0, 1.0));

      final minY = scaledDoc.outerContour.map((p) => p.y).reduce(math.min);
      final maxY = scaledDoc.outerContour.map((p) => p.y).reduce(math.max);
      final sidewallH = math.max((y1 - minY).abs(), (maxY - y2).abs());
      expect(sidewallH, closeTo(213.0, 1.0));

      // Fold in 3D and detect ports
      final foldResult = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: foldResult);
      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledDoc, foldResult: foldResult)).toList();
      final matchResult = CmsPortMatcher.match(measuredOpenings: measured, contract: contract);

      expect(matchResult.matchedPorts.length, equals(2));
      final p1 = matchResult.matchedPorts.firstWhere((p) => p.index == 1);
      final p2 = matchResult.matchedPorts.firstWhere((p) => p.index == 2);
      expect(p1.width, closeTo(650.0, 2.0));
      expect(p2.width, closeTo(650.0, 2.0));
      expect(p1.height, closeTo(200.0, 2.0));
      expect(p2.height, closeTo(200.0, 2.0));

      // Generate 2-plane angular cover for the 650x200mm scaled part
      final coverData = TrunkingCoverGenerator.generateCover(scaledDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      final ext1Face = coverDoc.faces.firstWhere((f) => f.id == 'COVER_EXT_FACE_1');
      expect(ext1Face.vertices.length, equals(4));

      final ys = mainFace.vertices.map((v) => v.y).toList();
      final coverWidthY = ys.reduce(math.max) - ys.reduce(math.min);
      expect(coverWidthY, closeTo(649.0 + 2 * TrunkingCoverGenerator.defaultCoverClearanceOffset, 1.0));

      // 4 side drop flanges with 22.5° miter relief notches
      final flanges = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flanges.length, equals(4));

      // Fold cover in 3D: roof bend 45° UP
      final coverMesh = KinematicFoldEngine.foldDocument(coverDoc, foldProgress: 1.0, ensureBaseFloorAtBottom: false);
      final mainPoly = coverMesh.polygons.firstWhere((p) => p.faceId == 'COVER_MAIN_FACE');
      final extPoly = coverMesh.polygons.firstWhere((p) => p.faceId == 'COVER_EXT_FACE_1');
      expect(mainPoly.normal.z, closeTo(1.0, 0.05));
      expect(extPoly.normal.x, closeTo(0.707, 0.05));
      expect(extPoly.normal.z, closeTo(0.707, 0.05));
    });

    test('6. Coupler Flaps Active on 45° Inside Riser: 0 extra ports, port border stays strictly on body coupler holes, and flaps fold vertical with sidewalls in 3D', () async {
      final file = File('assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      const riserPorts = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
      ];

      final controller = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.insideRiser45,
        baselinePorts: riserPorts,
      );

      // Turn on coupler flaps
      controller.setIncludeCouplerFlaps(true);
      final withFlapsDoc = controller.previewDocument;

      // 1. Verify flap bends are attached to the cheeks F_3, F_4, F_0, F_1 (NOT to floor F_5 or F_2)
      final bP1L = withFlapsDoc.bends.firstWhere((b) => b.id == 'BF_RISER_P1_L');
      final bP1R = withFlapsDoc.bends.firstWhere((b) => b.id == 'BF_RISER_P1_R');
      final bP2L = withFlapsDoc.bends.firstWhere((b) => b.id == 'BF_RISER_P2_L');
      final bP2R = withFlapsDoc.bends.firstWhere((b) => b.id == 'BF_RISER_P2_R');

      expect(bP1L.parentFaceId, equals('F_6'));
      expect(bP1R.parentFaceId, equals('F_8'));
      expect(bP2L.parentFaceId, equals('F_1'));
      expect(bP2R.parentFaceId, equals('F_3'));

      // 2. Verify 3D folding: All 4 flaps fold vertical with cheeks (|normal.z| < 0.1), NOT coplanar with floor
      final foldResult = KinematicFoldEngine.foldDocument(withFlapsDoc, foldProgress: 1.0);
      final flapPolyIds = ['F_FLAP_RISER_P1_L', 'F_FLAP_RISER_P1_R', 'F_FLAP_RISER_P2_L', 'F_FLAP_RISER_P2_R'];
      for (final flapId in flapPolyIds) {
        final polys = foldResult.polygons.where((p) => p.faceId == flapId).toList();
        expect(polys, isNotEmpty, reason: '$flapId must fold in 3D');
        for (final p in polys) {
          // Standing upright with sidewall cheeks
          expect(p.normal.z.abs(), lessThan(0.15), reason: '$flapId must be a vertical sidewall, not flat on floor');
        }
      }

      // 3. Opening detection: strictly 2 openings detected (0 extra spurious openings)
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: withFlapsDoc, foldResult: foldResult);
      expect(rawOpenings.length, equals(2), reason: 'Only Port 1 and Port 2 should exist, no spurious openings on flaps');

      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: withFlapsDoc, foldResult: foldResult)).toList();
      final contract = CmsProductContract.insideRiser45;
      final matchResult = CmsPortMatcher.match(measuredOpenings: measured, contract: contract);

      expect(matchResult.matchedPorts.length, equals(2));
      final p1 = matchResult.matchedPorts.firstWhere((p) => p.index == 1);
      final p2 = matchResult.matchedPorts.firstWhere((p) => p.index == 2);

      // 4. Critical User Mandate: Port border MUST pass across body coupler holes
      // Port 1 outer coupler punches are at x = 20.0
      // Port 2 outer coupler punches are at x = 280.0
      expect(p1.flatP1, isNotNull);
      expect(p1.flatP2, isNotNull);
      expect(p1.flatP1!.x, closeTo(20.0, 1.0), reason: 'Port 1 border must pass across x=20 coupler holes, not on flaps');
      expect(p1.flatP2!.x, closeTo(20.0, 1.0));

      expect(p2.flatP1, isNotNull);
      expect(p2.flatP2, isNotNull);
      expect(p2.flatP1!.x, closeTo(280.0, 1.0), reason: 'Port 2 border must pass across x=280 coupler holes, not on flaps');
      expect(p2.flatP2!.x, closeTo(280.0, 1.0));
    });

    test('7. PlanarFaceDecomposer correctly preserves baseFloor on angled floor and generates 2 sidewall flaps per port (4 total, 0 on floor)', () async {
      final file = File('assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rawDoc = DsfDocument.fromJson(json);

      // Decompose faces as the app does upon loading / editing
      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: rawDoc.outerContour,
        bends: rawDoc.bends,
        cutLines: rawDoc.cutLines,
        preferredBaseFaceId: rawDoc.baseFaceId,
      );
      final doc = rawDoc.copyWith(
        faces: decomp.faces,
        bends: decomp.connectedBends,
        baseFaceId: decomp.baseFaceId,
      );

      // Verify face classifications
      final f4 = doc.faces.firstWhere((f) => f.id == 'F_4');
      final f9 = doc.faces.firstWhere((f) => f.id == 'F_9');
      final f6 = doc.faces.firstWhere((f) => f.id == 'F_6');
      final f8 = doc.faces.firstWhere((f) => f.id == 'F_8');
      final f1 = doc.faces.firstWhere((f) => f.id == 'F_1');
      final f3 = doc.faces.firstWhere((f) => f.id == 'F_3');

      expect(f4.role, equals(FaceRole.baseFloor));
      expect(f9.role, equals(FaceRole.baseFloor), reason: 'Angled floor must be baseFloor, never sideWall');
      expect(f6.role, equals(FaceRole.sideWall), reason: 'Left top cheek must be sideWall');
      expect(f8.role, equals(FaceRole.sideWall), reason: 'Left bottom cheek must be sideWall');
      expect(f1.role, equals(FaceRole.sideWall), reason: 'Right top cheek must be sideWall');
      expect(f3.role, equals(FaceRole.sideWall), reason: 'Right bottom cheek must be sideWall');

      const riserPorts = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
      ];

      final controller = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.insideRiser45,
        baselinePorts: riserPorts,
      );

      controller.setIncludeCouplerFlaps(true);
      final withFlapsDoc = controller.previewDocument;

      // Exactly 4 flaps
      final flaps = withFlapsDoc.faces.where((f) => f.id.startsWith('F_FLAP_RISER_')).toList();
      expect(flaps.length, equals(4));
      expect(
        flaps.map((f) => f.id).toSet(),
        equals({'F_FLAP_RISER_P1_L', 'F_FLAP_RISER_P1_R', 'F_FLAP_RISER_P2_L', 'F_FLAP_RISER_P2_R'}),
      );

      // Verify no flap is parented to F_9 or F_4
      final flapBends = withFlapsDoc.bends.where((b) => b.id.startsWith('BF_RISER_')).toList();
      expect(flapBends.length, equals(4));
      for (final b in flapBends) {
        expect(b.parentFaceId, isNot(equals('F_9')), reason: 'No flap must attach to angled floor F_9');
        expect(b.parentFaceId, isNot(equals('F_4')), reason: 'No flap must attach to base floor F_4');
      }

      final bP1L = flapBends.firstWhere((b) => b.id == 'BF_RISER_P1_L');
      final bP1R = flapBends.firstWhere((b) => b.id == 'BF_RISER_P1_R');
      final bP2L = flapBends.firstWhere((b) => b.id == 'BF_RISER_P2_L');
      final bP2R = flapBends.firstWhere((b) => b.id == 'BF_RISER_P2_R');

      expect(bP1L.parentFaceId, equals('F_6'));
      expect(bP1R.parentFaceId, equals('F_8'));
      expect(bP2L.parentFaceId, equals('F_1'));
      expect(bP2R.parentFaceId, equals('F_3'));

      // Check 3D upright folding
      final foldResult = KinematicFoldEngine.foldDocument(withFlapsDoc, foldProgress: 1.0);
      for (final flap in flaps) {
        final polys = foldResult.polygons.where((p) => p.faceId == flap.id).toList();
        expect(polys, isNotEmpty);
        for (final p in polys) {
          expect(p.normal.z.abs(), lessThan(0.15), reason: 'Flap ${flap.id} must fold vertical with cheek in 3D');
        }
      }
    });

    test('8. Coupler flaps when height is scaled above 75mm (e.g. 100mm, 150mm): flaps remain strictly on horizontal side height walls, never on top flanged area', () async {
      final file = File('assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf');
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rawDoc = DsfDocument.fromJson(json);

      const riserPorts = [
        CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0),
        CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 50.0),
      ];

      final controller = CmsScalingController(
        baselineDocument: rawDoc,
        contract: CmsProductContract.insideRiser45,
        baselinePorts: riserPorts,
      );

      // Scale height to 100mm (height > 75mm where flat blank Y span exceeds X length)
      controller.setIncludeCouplerFlaps(true);
      controller.selectParameter('height');
      controller.evaluateMorph(100.0);
      final scaledDoc100 = controller.previewDocument;

      // 1. Verify 4 flaps exist
      final flaps100 = scaledDoc100.faces.where((f) => f.id.startsWith('F_FLAP_RISER_')).toList();
      expect(flaps100.length, equals(4));
      expect(
        flaps100.map((f) => f.id).toSet(),
        equals({'F_FLAP_RISER_P1_L', 'F_FLAP_RISER_P1_R', 'F_FLAP_RISER_P2_L', 'F_FLAP_RISER_P2_R'}),
      );

      // 2. Verify all 4 flaps are attached strictly to the sidewall cheeks F_6, F_8, F_1, F_3
      final flapBends100 = scaledDoc100.bends.where((b) => b.id.startsWith('BF_RISER_')).toList();
      expect(flapBends100.length, equals(4));

      final bP1L = flapBends100.firstWhere((b) => b.id == 'BF_RISER_P1_L');
      final bP1R = flapBends100.firstWhere((b) => b.id == 'BF_RISER_P1_R');
      final bP2L = flapBends100.firstWhere((b) => b.id == 'BF_RISER_P2_L');
      final bP2R = flapBends100.firstWhere((b) => b.id == 'BF_RISER_P2_R');

      expect(bP1L.parentFaceId, equals('F_6'), reason: 'Port 1 Left flap must attach to sidewall F_6, not return flange');
      expect(bP1R.parentFaceId, equals('F_8'), reason: 'Port 1 Right flap must attach to sidewall F_8, not return flange');
      expect(bP2L.parentFaceId, equals('F_1'), reason: 'Port 2 Left flap must attach to sidewall F_1, not return flange');
      expect(bP2R.parentFaceId, equals('F_3'), reason: 'Port 2 Right flap must attach to sidewall F_3, not return flange');

      // 3. Verify bend lines are strictly vertical at x = 0 (P1) and x = 300 (P2), spanning H = 100mm
      expect(bP1L.p1.x, closeTo(0.0, 1.0));
      expect(bP1L.p2.x, closeTo(0.0, 1.0));
      expect((bP1L.p1.y - bP1L.p2.y).abs(), closeTo(100.0, 1.0), reason: 'Flap bend span must match scaled height 100mm');

      expect(bP2L.p1.x, closeTo(300.0, 1.0));
      expect(bP2L.p2.x, closeTo(300.0, 1.0));
      expect((bP2L.p1.y - bP2L.p2.y).abs(), closeTo(100.0, 1.0), reason: 'Flap bend span must match scaled height 100mm');

      // 4. Verify 3D folding: All 4 flaps fold vertically upright with sidewalls (|normal.z| < 0.15)
      final foldResult100 = KinematicFoldEngine.foldDocument(scaledDoc100, foldProgress: 1.0);
      for (final flap in flaps100) {
        final polys = foldResult100.polygons.where((p) => p.faceId == flap.id).toList();
        expect(polys, isNotEmpty);
        for (final p in polys) {
          expect(p.normal.z.abs(), lessThan(0.15), reason: 'Flap ${flap.id} must fold vertically with sidewall in 3D');
        }
      }
    });
  });
}


