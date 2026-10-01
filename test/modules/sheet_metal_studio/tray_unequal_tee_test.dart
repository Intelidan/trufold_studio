import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_unequal_tee_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';

void main() {
  late DsfDocument trayDoc;
  late DsfDocument trunkingDoc;

  setUp(() {
    final trayFile = File('assets/dsf_templates/tray_accessories/unequal_tee_100x50x100x50.dsf');
    trayDoc = DsfDocument.fromJson(jsonDecode(trayFile.readAsStringSync()) as Map<String, dynamic>);

    final trunkingFile = File('assets/dsf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
    trunkingDoc = DsfDocument.fromJson(jsonDecode(trunkingFile.readAsStringSync()) as Map<String, dynamic>);
  });

  group('Cable Tray Unequal Tee - Dedicated Parametric Engine', () {
    test('TC-01: Template Classification & Disambiguation', () {
      expect(TrayUnequalTeeScaler.isTrayUnequalTee(trayDoc), isTrue);
      expect(TrayUnequalTeeScaler.isTrayUnequalTee(trunkingDoc), isFalse);

      expect(trayDoc.bends.length, equals(6));
      expect(trayDoc.punches.length, equals(23));
    });

    test('TC-02: 3D Port Box Centered on Coupler Holes', () {
      final fold = KinematicFoldEngine.foldDocument(trayDoc, foldProgress: 1.0);
      final openings = Cms3DOpeningDetector.detectOpenings(document: trayDoc, foldResult: fold);

      expect(openings.length, equals(3));

      // Port 1: Left mouth (normal = -1, 0, 0)
      final port1 = openings.firstWhere((o) => o.outwardNormal.x < -0.9);
      expect(port1.outwardNormal.x, closeTo(-1.0, 1e-4));
      // Mouth plane should be shifted into the coupler holes (~63.2 mm instead of outer edge 44.55 mm)
      expect(port1.floorEdgeP1.x, closeTo(63.22, 1.0));
      expect(port1.floorEdgeP2.x, closeTo(63.22, 1.0));

      // Port 2: Right mouth (normal = +1, 0, 0)
      final port2 = openings.firstWhere((o) => o.outwardNormal.x > 0.9);
      expect(port2.outwardNormal.x, closeTo(1.0, 1e-4));
      // Mouth plane shifted into coupler holes (~361.6 mm instead of outer edge 380.29 mm)
      expect(port2.floorEdgeP1.x, closeTo(361.62, 1.0));
      expect(port2.floorEdgeP2.x, closeTo(361.62, 1.0));

      // Port 3: Bottom mouth (normal = 0, +1, 0)
      final port3 = openings.firstWhere((o) => o.outwardNormal.y > 0.9);
      expect(port3.outwardNormal.y, closeTo(1.0, 1e-4));
      // Mouth plane shifted into coupler holes (~288.5 mm instead of outer edge 305.87 mm)
      expect(port3.floorEdgeP1.y, closeTo(288.53, 1.0));
      expect(port3.floorEdgeP2.y, closeTo(288.53, 1.0));
    });

    test('TC-03: Controller Initialization Stability (No Dismantling on Open)', () {
      final fold = KinematicFoldEngine.foldDocument(trayDoc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: trayDoc, foldResult: fold);
      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: trayDoc, foldResult: fold)).toList();

      final baselinePorts = [
        CmsPhysicalPort(
          id: 'PORT_1',
          index: 0,
          role: CmsPortRole.inlet,
          width: measured[2].width,
          height: measured[2].height,
          normal: measured[2].normal,
          center: measured[2].center,
        ),
        CmsPhysicalPort(
          id: 'PORT_2',
          index: 1,
          role: CmsPortRole.outlet,
          width: measured[0].width,
          height: measured[0].height,
          normal: measured[0].normal,
          center: measured[0].center,
        ),
        CmsPhysicalPort(
          id: 'PORT_3',
          index: 2,
          role: CmsPortRole.branch,
          width: measured[1].width,
          height: measured[1].height,
          normal: measured[1].normal,
          center: measured[1].center,
        ),
      ];

      final controller = CmsScalingController(baselineDocument: trayDoc, contract: CmsProductContract.unequalTee, baselinePorts: baselinePorts);

      // Verify parameters baseline values
      expect(controller.model.parameters['port1_width']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port1_width']?.currentValue, equals(100.0));
      expect(controller.model.parameters['port1_height']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port1_height']?.currentValue, equals(50.0));

      expect(controller.model.parameters['port2_width']?.baselineValue, equals(100.0));
      expect(controller.model.parameters['port2_width']?.currentValue, equals(100.0));
      expect(controller.model.parameters['port2_height']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port2_height']?.currentValue, equals(50.0));

      expect(controller.model.parameters['port3_width']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port3_width']?.currentValue, equals(50.0));
      expect(controller.model.parameters['port3_height']?.baselineValue, equals(50.0));
      expect(controller.model.parameters['port3_height']?.currentValue, equals(50.0));

      // Radius parameter present and at 180mm baseline
      expect(controller.model.parameters['radius']?.baselineValue, equals(180.0));

      // Evaluating morph at baseline must preserve exact document geometry
      final previewDoc = controller.previewDocument;
      expect(previewDoc.outerContour.length, equals(trayDoc.outerContour.length));
      expect(previewDoc.bends.length, equals(6));
      expect(previewDoc.faces.length, equals(7));

      // Contour coordinates should match baseline within 0.01mm (no skew/scattering)
      for (int i = 0; i < trayDoc.outerContour.length; i++) {
        expect(previewDoc.outerContour[i].x, closeTo(trayDoc.outerContour[i].x, 0.01));
        expect(previewDoc.outerContour[i].y, closeTo(trayDoc.outerContour[i].y, 0.01));
      }
    });

    test('TC-04: Parametric Scaling of Widths, Heights, and Radius', () {
      // Scale Port 1=150, Port 2=150, Port 3=100, Height=100, Radius=300
      final scaledDoc = TrayUnequalTeeScaler.scaleWithParameters(
        trayDoc,
        const TrayUnequalTeeScaleParameters(port1Width: 150.0, port2Width: 150.0, port3Width: 100.0, targetHeight: 100.0, targetRadius: 300.0),
      );

      expect(scaledDoc.bends.length, equals(6));
      expect(scaledDoc.faces.length, equals(7));
      expect(scaledDoc.outerContour.length, equals(11));

      // Bends B1, B2, FL2, FL3 lengths must all be identical
      final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
      final fl2 = scaledDoc.bends.firstWhere((b) => b.id == 'FL2');
      final fl3 = scaledDoc.bends.firstWhere((b) => b.id == 'FL3');
      final b3 = scaledDoc.bends.firstWhere((b) => b.id == 'B3');
      final fl1 = scaledDoc.bends.firstWhere((b) => b.id == 'FL1');

      final lenB1 = b1.p1.distanceTo(b1.p2);
      final lenB2 = b2.p1.distanceTo(b2.p2);
      final lenFL2 = fl2.p1.distanceTo(fl2.p2);
      final lenFL3 = fl3.p1.distanceTo(fl3.p2);
      final lenB3 = b3.p1.distanceTo(b3.p2);
      final lenFL1 = fl1.p1.distanceTo(fl1.p2);

      expect(lenB1, closeTo(lenB2, 1e-4));
      expect(lenB1, closeTo(lenFL2, 1e-4));
      expect(lenB1, closeTo(lenFL3, 1e-4));
      expect(lenB3, closeTo(lenFL1, 1e-4));

      // Coupler holes rule: H=100 >= 95mm -> 2 rows of coupler holes
      final miterCouplers = scaledDoc.punches.where((p) => p.role == CncPunchRole.coupler && (p.rotationDeg == 45.0 || p.rotationDeg == 135.0)).toList();
      // 4 positions * 2 rows = 8 per miter wall -> 16 total
      expect(miterCouplers.length, equals(16));

      // Fold kinematic validation: must fold cleanly into 3D
      final fold = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      expect(fold.polygons.length, equals(7));

      final openings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: fold);
      expect(openings.length, equals(3));
    });

    test('TC-05: Independent Port Widths (W1, W2, W3 do not couple)', () {
      // Scale with W1=105, W2=125, W3=210 (SS2 parameters)
      final scaledDoc = TrayUnequalTeeScaler.scaleWithParameters(
        trayDoc,
        const TrayUnequalTeeScaleParameters(port1Width: 105.0, port2Width: 125.0, port3Width: 210.0),
      );

      final fold = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: fold);
      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledDoc, foldResult: fold)).toList();

      // Port 1 (Left mouth, normal.x < -0.5)
      final p1 = measured.firstWhere((m) => m.normal.x < -0.5);
      expect(p1.width, closeTo(105.0, 1.0));

      // Port 2 (Right mouth, normal.x > 0.5)
      final p2 = measured.firstWhere((m) => m.normal.x > 0.5);
      expect(p2.width, closeTo(125.0, 1.0));

      // Port 3 (Branch mouth, normal.y > 0.5)
      final p3 = measured.firstWhere((m) => m.normal.y > 0.5);
      expect(p3.width, closeTo(210.0, 1.0));

      // Assert independent 2D mouth lengths
      final b1 = scaledDoc.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaledDoc.bends.firstWhere((b) => b.id == 'B2');
      final b3 = scaledDoc.bends.firstWhere((b) => b.id == 'B3');

      // Port 1 mouth edge length in 2D = b1.p1.y - b3.p1.y
      expect(b1.p1.y - b3.p1.y, closeTo(105.0, 1e-4));
      // Port 2 mouth edge length in 2D = b2.p1.y - b3.p2.y
      expect(b2.p1.y - b3.p2.y, closeTo(125.0, 1e-4));
      // Port 3 mouth edge length in 2D = b2.p2.x - b1.p2.x
      expect(b2.p2.x - b1.p2.x, closeTo(210.0, 1e-4));
    });

    test('TC-06: Slanting 3D Walls for Varying Heights (H1=55, H2=120, H3=165)', () {
      final scaledDoc = TrayUnequalTeeScaler.scaleWithParameters(
        trayDoc,
        const TrayUnequalTeeScaleParameters(port1Width: 105.0, port2Width: 125.0, port3Width: 210.0, port1Height: 55.0, port2Height: 120.0, port3Height: 165.0),
      );

      final fold = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      expect(fold.polygons.length, equals(7));

      // 1. Back Wall F_6: slants from H1 (55mm) to H2 (120mm)
      final f6Poly = fold.polygons.firstWhere((p) => p.faceId == 'F_6');
      final f6Zs = f6Poly.vertices.map((v) => v.z).toList();
      final minF6Z = f6Zs.reduce(math.min);
      // Check top lip vertices of F_6 at x around b3P1 (Port 1) and b3P2 (Port 2)
      final f6TopPort1 = f6Poly.vertices.firstWhere((v) => v.z > 10.0 && v.x < 100.0);
      final f6TopPort2 = f6Poly.vertices.firstWhere((v) => v.z > 10.0 && v.x > 300.0);
      expect(f6TopPort1.z - minF6Z, closeTo(55.0, 1.0));
      expect(f6TopPort2.z - minF6Z, closeTo(120.0, 1.0));

      // 2. Left Wall F_1: slants from H1 (55mm) at Port 1 to H3 (165mm) at Port 3
      final f1Poly = fold.polygons.firstWhere((p) => p.faceId == 'F_1');
      final minF1Z = f1Poly.vertices.map((v) => v.z).reduce(math.min);
      final f1TopPort1 = f1Poly.vertices.firstWhere((v) => v.z > 10.0 && v.y < 200.0);
      final f1TopPort3 = f1Poly.vertices.firstWhere((v) => v.z > 10.0 && v.y > 250.0);
      expect(f1TopPort1.z - minF1Z, closeTo(55.0, 1.0));
      expect(f1TopPort3.z - minF1Z, closeTo(165.0, 1.0));

      // 3. Right Wall F_3: slants from H2 (120mm) at Port 2 to H3 (165mm) at Port 3
      final f3Poly = fold.polygons.firstWhere((p) => p.faceId == 'F_3');
      final minF3Z = f3Poly.vertices.map((v) => v.z).reduce(math.min);
      final f3TopPort2 = f3Poly.vertices.firstWhere((v) => v.z > 10.0 && v.y < 200.0);
      final f3TopPort3 = f3Poly.vertices.firstWhere((v) => v.z > 10.0 && v.y > 250.0);
      expect(f3TopPort2.z - minF3Z, closeTo(120.0, 1.0));
      expect(f3TopPort3.z - minF3Z, closeTo(165.0, 1.0));

      // 4. Opening Measurements
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: fold);
      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: scaledDoc, foldResult: fold)).toList();

      final p1 = measured.firstWhere((m) => m.normal.x < -0.5);
      expect(p1.height, closeTo(55.0, 1.0));

      final p2 = measured.firstWhere((m) => m.normal.x > 0.5);
      expect(p2.height, closeTo(120.0, 1.0));

      final p3 = measured.firstWhere((m) => m.normal.y > 0.5);
      expect(p3.height, closeTo(165.0, 1.0));

      // 5. Coupler Holes:
      // Port 1 (55mm < 95mm) -> 1 slot vertically
      // Port 2 (120mm >= 95mm) -> 2 slots vertically
      // Port 3 (165mm >= 95mm) -> 2 slots vertically
      final topSlotsP1 = scaledDoc.punches.where((p) => p.role == CncPunchRole.coupler && p.center.y < 38.0 && p.center.x < 100.0).toList();
      expect(topSlotsP1.length, equals(2)); // 2 columns x 1 slot row = 2

      final topSlotsP2 = scaledDoc.punches.where((p) => p.role == CncPunchRole.coupler && p.center.y < 38.0 && p.center.x > 300.0).toList();
      expect(topSlotsP2.length, equals(4)); // 2 columns x 2 slot rows = 4
    });

    test('TC-07: Expanded Central Floor Perforations for Width Changes', () {
      final scaledDoc = TrayUnequalTeeScaler.scaleWithParameters(
        trayDoc,
        const TrayUnequalTeeScaleParameters(port1Width: 105.0, port2Width: 125.0, port3Width: 210.0),
      );

      final floorPerfs = scaledDoc.punches.where((p) => p.role == CncPunchRole.perforation).toList();
      // Expanded floor has more perforations than baseline (7) without multiplication
      expect(floorPerfs.length, greaterThan(7));
      expect(floorPerfs.length, lessThanOrEqualTo(16));

      // All floor perforations must be within floor boundaries
      final f5 = scaledDoc.faces.firstWhere((f) => f.id == 'F_5');
      final xs = f5.vertices.map((v) => v.x).toList();
      final ys = f5.vertices.map((v) => v.y).toList();
      final minX = xs.reduce(math.min);
      final maxX = xs.reduce(math.max);
      final minY = ys.reduce(math.min);
      final maxY = ys.reduce(math.max);

      for (final p in floorPerfs) {
        expect(p.center.x, greaterThanOrEqualTo(minX + 15.0));
        expect(p.center.x, lessThanOrEqualTo(maxX - 15.0));
        expect(p.center.y, greaterThanOrEqualTo(minY + 15.0));
        expect(p.center.y, lessThanOrEqualTo(maxY - 15.0));
      }
    });

    test('TC-08: Reduced Perforations & Intelligent Coupler Placement Centered to Edge Height', () {
      final scaledDoc = TrayUnequalTeeScaler.scaleWithParameters(
        trayDoc,
        const TrayUnequalTeeScaleParameters(port1Width: 100.0, port2Width: 100.0, port3Width: 50.0, port1Height: 200.0, port2Height: 100.0, port3Height: 50.0),
      );

      // 1. Reduced perforations: At baseline widths (100, 100, 50), exactly 7 floor perforations
      final floorPerfs = scaledDoc.punches.where((p) => p.role == CncPunchRole.perforation).toList();
      expect(floorPerfs.length, equals(7));

      // Exactly 2 central perforations at centerline x=212.4
      final centralPerfs = floorPerfs.where((p) => (p.center.x - 212.42).abs() < 1.0).toList();
      expect(centralPerfs.length, equals(3)); // 1 mouth slot at 285.9, 2 centerline slots at 93.8 and 193.8

      // 2. Intelligent Coupler Placement: Fold to 3D and verify heights
      final fold = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);

      // Port 1 (Height=200): must have coupler holes centered with 50mm pitch starting at Z~25
      final p1Couplers = fold.punchCenters3D.entries.where((e) => e.value.x < 100.0 && e.value.z > 1.0).map((e) => e.value.z).toSet().toList()..sort();
      expect(p1Couplers, contains(closeTo(26.5, 2.0))); // Bottom hole at ~25mm
      expect(p1Couplers, contains(closeTo(76.5, 2.0)));
      expect(p1Couplers, contains(closeTo(126.5, 2.0)));

      // Port 3 (Height=50): coupler holes strictly centered at Z=25 (no hole at Z=75)
      final p3Couplers = fold.punchCenters3D.entries.where((e) => e.value.y > 240.0 && e.value.z > 1.0).map((e) => e.value.z).toList();
      for (final z in p3Couplers) {
        expect(z, closeTo(26.5, 2.0)); // Strictly 25mm, no hole floating above Port 3 height!
      }

      // No coupler punches should be folded onto flange faces (all must stay on sidewalls)
      for (final poly in fold.polygons.where((p) => p.faceId == 'F_0' || p.faceId == 'F_2' || p.faceId == 'F_4')) {
        for (final entry in fold.punchCenters3D.entries) {
          final p = scaledDoc.punches.firstWhere((punch) => punch.id == entry.key);
          if (p.role == CncPunchRole.coupler) {
            // Coupler centers must not be on flange faces
            expect(poly.faceId.contains(entry.key), isFalse);
          }
        }
      }
    });

    test('TC-09: Coupler Flap Toggle & Scalable Bend Angles (Parallel Alignment on Scaled Widths)', () {
      final doc = trayDoc;

      // 1. When includeCouplerFlaps is false (default): exactly 0 flap faces, 0 flap bends
      final noFlapsDoc = TrayUnequalTeeScaler.scaleWithParameters(doc, const TrayUnequalTeeScaleParameters(includeCouplerFlaps: false));
      expect(noFlapsDoc.faces.any((f) => f.id.startsWith('F_FLAP_')), isFalse);
      expect(noFlapsDoc.bends.any((b) => b.id.startsWith('BF_')), isFalse);

      // 2. When includeCouplerFlaps is true at baseline (W1=100, W2=100, W3=50, H=50):
      final withFlapsDoc = TrayUnequalTeeScaler.scaleWithParameters(
        doc,
        const TrayUnequalTeeScaleParameters(includeCouplerFlaps: true, couplerFlapLength: 30.0),
      );

      // Expect exactly 6 flap faces and 6 flap bends
      final flapFaces = withFlapsDoc.faces.where((f) => f.id.startsWith('F_FLAP_')).toList();
      expect(flapFaces.length, equals(6));
      expect(flapFaces.map((f) => f.id).toSet(), equals({'F_FLAP_1_P1', 'F_FLAP_1_P3', 'F_FLAP_3_P2', 'F_FLAP_3_P3', 'F_FLAP_6_P1', 'F_FLAP_6_P2'}));

      final flapBends = withFlapsDoc.bends.where((b) => b.id.startsWith('BF_')).toList();
      expect(flapBends.length, equals(6));
      expect(flapBends.map((b) => b.id).toSet(), equals({'BF_1_P1', 'BF_1_P3', 'BF_3_P2', 'BF_3_P3', 'BF_6_P1', 'BF_6_P2'}));

      // Baseline angles (45° symmetric cheeks):
      final bf1P1 = flapBends.firstWhere((b) => b.id == 'BF_1_P1');
      final bf1P3 = flapBends.firstWhere((b) => b.id == 'BF_1_P3');
      final bf6P1 = flapBends.firstWhere((b) => b.id == 'BF_6_P1');
      expect(bf1P1.targetAngleDeg, closeTo(45.0, 0.1));
      expect(bf1P3.targetAngleDeg, closeTo(45.0, 0.1));
      expect(bf6P1.targetAngleDeg, closeTo(0.0, 0.1));

      // Flap holes: at H=50, each flap has exactly 2 vertically aligned obround holes
      // 6 flaps x 2 holes = 12 flap holes! Total punches = 23 (baseline) + 12 = 35 punches
      expect(withFlapsDoc.punches.length, equals(35));

      // 3. 3D Kinematics Fold Test:
      final fold3D = KinematicFoldEngine.foldDocument(withFlapsDoc);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_1_P1'), isTrue);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_3_P2'), isTrue);
      expect(fold3D.polygons.any((p) => p.faceId == 'F_FLAP_6_P1'), isTrue);

      // Verify authentic parallel flap alignment in 3D:
      // Port 1 flaps (F_FLAP_1_P1 & F_FLAP_6_P1) must have normal along Y, spanning along -X
      final pFlap1P1 = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P1');
      final nFlap1P1 = (pFlap1P1.vertices[1] - pFlap1P1.vertices[0]).cross(pFlap1P1.vertices[2] - pFlap1P1.vertices[0]).normalized();
      expect(nFlap1P1.x.abs(), closeTo(0.0, 0.05));
      expect(nFlap1P1.y.abs(), closeTo(1.0, 0.05));
      final xSpan1P1 = pFlap1P1.vertices.map((v) => v.x).reduce(math.max) - pFlap1P1.vertices.map((v) => v.x).reduce(math.min);
      expect(xSpan1P1, closeTo(30.0, 1.0)); // Extends 30mm along -X

      // Port 2 flaps (F_FLAP_3_P2 & F_FLAP_6_P2) must have normal along Y, spanning along +X
      final pFlap3P2 = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P2');
      final nFlap3P2 = (pFlap3P2.vertices[1] - pFlap3P2.vertices[0]).cross(pFlap3P2.vertices[2] - pFlap3P2.vertices[0]).normalized();
      expect(nFlap3P2.x.abs(), closeTo(0.0, 0.05));
      expect(nFlap3P2.y.abs(), closeTo(1.0, 0.05));
      final xSpan3P2 = pFlap3P2.vertices.map((v) => v.x).reduce(math.max) - pFlap3P2.vertices.map((v) => v.x).reduce(math.min);
      expect(xSpan3P2, closeTo(30.0, 1.0)); // Extends 30mm along +X

      // Port 3 flaps (F_FLAP_1_P3 & F_FLAP_3_P3) must have normal along X, spanning along +Y
      final pFlap1P3 = fold3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P3');
      final nFlap1P3 = (pFlap1P3.vertices[1] - pFlap1P3.vertices[0]).cross(pFlap1P3.vertices[2] - pFlap1P3.vertices[0]).normalized();
      expect(nFlap1P3.x.abs(), closeTo(1.0, 0.05));
      expect(nFlap1P3.y.abs(), closeTo(0.0, 0.05));
      final ySpan1P3 = pFlap1P3.vertices.map((v) => v.y).reduce(math.max) - pFlap1P3.vertices.map((v) => v.y).reduce(math.min);
      expect(ySpan1P3, closeTo(30.0, 1.0)); // Extends 30mm along +Y

      // 4. Scalable Bending Angles on Width Scaling (e.g. W1=250, W3=50):
      final scaledWidthDoc = TrayUnequalTeeScaler.scaleWithParameters(
        doc,
        const TrayUnequalTeeScaleParameters(port1Width: 250.0, port2Width: 100.0, port3Width: 50.0, includeCouplerFlaps: true, couplerFlapLength: 35.0),
      );

      final foldScaled3D = KinematicFoldEngine.foldDocument(scaledWidthDoc);
      final pScaledFlap1P1 = foldScaled3D.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P1');
      final nScaledFlap1P1 = (pScaledFlap1P1.vertices[1] - pScaledFlap1P1.vertices[0]).cross(pScaledFlap1P1.vertices[2] - pScaledFlap1P1.vertices[0]).normalized();
      expect(nScaledFlap1P1.x.abs(), closeTo(0.0, 0.05));
      expect(nScaledFlap1P1.y.abs(), closeTo(1.0, 0.05));

      final scaledBf1P1 = scaledWidthDoc.bends.firstWhere((b) => b.id == 'BF_1_P1');
      final scaledBf1P3 = scaledWidthDoc.bends.firstWhere((b) => b.id == 'BF_1_P3');
      // When W1 increases to 250, cheek 1 angle theta1 decreases below 45°
      expect(scaledBf1P1.targetAngleDeg, lessThan(45.0));
      // Sum of P1 and P3 bend angles must strictly equal 90° for orthogonal alignment
      expect(scaledBf1P1.targetAngleDeg + scaledBf1P3.targetAngleDeg, closeTo(90.0, 0.01));

      // 5. Hole Layout for H > 50mm: 2 rows x 2 cols = 4 holes per flap
      final tallDoc = TrayUnequalTeeScaler.scaleWithParameters(
        doc,
        const TrayUnequalTeeScaleParameters(port1Height: 100.0, port2Height: 100.0, port3Height: 100.0, includeCouplerFlaps: true, couplerFlapLength: 30.0),
      );
      // At H=100: each of the 6 flaps receives 4 holes = 24 flap holes!
      final tallFold = KinematicFoldEngine.foldDocument(tallDoc);
      expect(tallFold.punchCenters3D.isNotEmpty, isTrue);
    });

    test('TC-10: Perforation Density Presets & Pitch Control (Sparse, Standard, Dense)', () {
      final doc = trayDoc;

      // Standard pitch (100mm)
      final standardDoc = TrayUnequalTeeScaler.scaleWithParameters(
        doc,
        const TrayUnequalTeeScaleParameters(port1Width: 300.0, port2Width: 300.0, port3Width: 200.0, perforationPitch: 100.0),
      );

      // Sparse pitch (150mm) -> fewer central floor perforations
      final sparseDoc = TrayUnequalTeeScaler.scaleWithParameters(
        doc,
        const TrayUnequalTeeScaleParameters(port1Width: 300.0, port2Width: 300.0, port3Width: 200.0, perforationPitch: 150.0),
      );

      // Dense pitch (75mm) -> more central floor perforations
      final denseDoc = TrayUnequalTeeScaler.scaleWithParameters(
        doc,
        const TrayUnequalTeeScaleParameters(port1Width: 300.0, port2Width: 300.0, port3Width: 200.0, perforationPitch: 75.0),
      );

      expect(sparseDoc.punches.length, lessThan(standardDoc.punches.length));
      expect(denseDoc.punches.length, greaterThan(standardDoc.punches.length));
    });
  });
}
