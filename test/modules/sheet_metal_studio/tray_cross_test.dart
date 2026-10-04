import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_equal_cross_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_unequal_cross_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';

void main() {
  late DsfDocument equalCrossDoc;
  late DsfDocument unequalCrossDoc;
  late DsfDocument trunkingCrossDoc;

  setUp(() {
    final eqFile = File('assets/dsf_templates/tray_accessories/equal_cross_100x50.dsf');
    equalCrossDoc = DsfDocument.fromJson(jsonDecode(eqFile.readAsStringSync()) as Map<String, dynamic>);

    final ueqFile = File('assets/dsf_templates/tray_accessories/unequal_cross_100x50x100x50.dsf');
    unequalCrossDoc = DsfDocument.fromJson(jsonDecode(ueqFile.readAsStringSync()) as Map<String, dynamic>);

    final trunkingFile = File('assets/dsf_templates/trunking_accessories/equal_cross_100x100.dsf');
    if (trunkingFile.existsSync()) {
      trunkingCrossDoc = DsfDocument.fromJson(jsonDecode(trunkingFile.readAsStringSync()) as Map<String, dynamic>);
    } else {
      trunkingCrossDoc = equalCrossDoc.copyWith(itemName: 'Trunking Equal Cross');
    }
  });

  group('Cable Tray Equal Cross - Dedicated Analytical Scaler', () {
    test('TC-01: Classification & Detection', () {
      expect(TrayEqualCrossScaler.isTrayEqualCross(equalCrossDoc), isTrue);
      expect(TrayEqualCrossScaler.isTrayEqualCross(unequalCrossDoc), isFalse);
      expect(TrayEqualCrossScaler.isTrayEqualCross(trunkingCrossDoc), isFalse);
    });

    test('TC-02: Scaling Width (SS2 fix)', () {
      final scaledW200 = TrayEqualCrossScaler.scale(
        baseline: equalCrossDoc,
        targetWidth: 200.0,
        targetHeight: 50.0,
      );

      // Verify all 4 mouths have width 200mm
      final b1 = scaledW200.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaledW200.bends.firstWhere((b) => b.id == 'B2');
      final b3 = scaledW200.bends.firstWhere((b) => b.id == 'B3');
      final b4 = scaledW200.bends.firstWhere((b) => b.id == 'B4');

      final northW = (b3.p2.x - b1.p1.x).abs();
      final southW = (b4.p1.x - b2.p2.x).abs();
      final westW = (b2.p1.y - b1.p2.y).abs();
      final eastW = (b4.p2.y - b3.p1.y).abs();

      expect(northW, closeTo(200.0, 1e-3));
      expect(southW, closeTo(200.0, 1e-3));
      expect(westW, closeTo(200.0, 1e-3));
      expect(eastW, closeTo(200.0, 1e-3));

      // 45° corner cheek angles preserved
      for (final b in [b1, b2, b3, b4]) {
        final dx = (b.p2.x - b.p1.x).abs();
        final dy = (b.p2.y - b.p1.y).abs();
        expect(dx, closeTo(dy, 1e-3));
      }

      // Coupler punches: 16 punches, all along cheek walls, at u = 25, 75, L-75, L-25
      final couplers = scaledW200.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      expect(couplers.length, equals(16));

      // 3D folding works
      final foldResult = KinematicFoldEngine.foldDocument(scaledW200, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);
    });

    test('TC-03: Scaling Height & Universal 95mm Rule (SS3 fix)', () {
      // H = 50mm (< 95mm): 1 row of 4 slots per cheek wall = 16 slots total
      final scaledH50 = TrayEqualCrossScaler.scale(
        baseline: equalCrossDoc,
        targetWidth: 100.0,
        targetHeight: 50.0,
      );
      final couplersH50 = scaledH50.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      expect(couplersH50.length, equals(16));

      // H = 100mm (>= 95mm): 2 rows of 4 slots per cheek wall = 32 slots total
      final scaledH100 = TrayEqualCrossScaler.scale(
        baseline: equalCrossDoc,
        targetWidth: 100.0,
        targetHeight: 100.0,
      );
      final couplersH100 = scaledH100.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      expect(couplersH100.length, equals(32));

      // Verify slot height offset is centered at H/2 ± 25mm (v = 25mm and 75mm from base bend)
      // Check NW wall coupler punches: base bend is B1
      final b1 = scaledH100.bends.firstWhere((b) => b.id == 'B1');
      // For any coupler punch on NW wall, distance from line B1 should be either 25mm or 75mm
      for (final p in couplersH100.where((p) => p.id.contains('NW'))) {
        final dist = _pointToLineDistance(p.center, b1.p1, b1.p2);
        expect(dist == 25.0 || dist == 75.0, isTrue, reason: 'Distance $dist should be 25 or 75');
      }

      // 3D folding works on H=100
      final foldResult = KinematicFoldEngine.foldDocument(scaledH100, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);
    });

    test('TC-04: Coupler Flaps Synthesis (SS4 fix)', () {
      final withFlaps = TrayEqualCrossScaler.scale(
        baseline: equalCrossDoc,
        targetWidth: 100.0,
        targetHeight: 50.0,
        includeCouplerFlaps: true,
        couplerFlapLength: 90.0,
      );

      // Flaps enabled: 8 flap bend lines (2 per cheek wall)
      final flapBends = withFlaps.bends.where((b) => b.id.startsWith('BF_')).toList();
      expect(flapBends.length, equals(8));

      // Flap bends should fold at 45° with BendDirection.down to align with straight tray runs
      for (final fb in flapBends) {
        expect(fb.targetAngleDeg, closeTo(45.0, 1e-3));
        expect(fb.direction, equals(BendDirection.down));
      }

      // Each flap has 3 vertical obround slots (8 flaps * 3 slots = 24 visible flap slots)
      final visibleCouplers = withFlaps.punches.where((p) => p.role == CncPunchRole.coupler && p.isVisible).toList();
      expect(visibleCouplers.length, equals(24));

      // Each slot length = H - 20 = 30mm, width = 8mm
      for (final slot in visibleCouplers) {
        expect(slot.lengthMm, closeTo(30.0, 1e-3));
        expect(slot.widthMm, closeTo(8.0, 1e-3));
      }

      // 3D folding works with flaps
      final foldResult = KinematicFoldEngine.foldDocument(withFlaps, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      final fNwP1 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_8_P1');
      final fSwP1 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P1');
      final fNwP2 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_8_P2');
      final fNeP2 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P2');
      final fNeP3 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P3');
      final fSeP3 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_5_P3');
      final fSwP4 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P4');
      final fSeP4 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_5_P4');

      print('DEBUG: Port 1 (West) flap normals: ${fNwP1.normal}, ${fSwP1.normal}');
      print('DEBUG: Port 2 (North) flap normals: ${fNwP2.normal}, ${fNeP2.normal}');
      print('DEBUG: Port 3 (East) flap normals: ${fNeP3.normal}, ${fSeP3.normal}');
      print('DEBUG: Port 4 (South) flap normals: ${fSwP4.normal}, ${fSeP4.normal}');
    });
  });

  group('Cable Tray Unequal Cross - Dedicated Analytical Scaler', () {
    test('TC-05: Classification & Detection', () {
      expect(TrayUnequalCrossScaler.isTrayUnequalCross(unequalCrossDoc), isTrue);
      expect(TrayUnequalCrossScaler.isTrayUnequalCross(equalCrossDoc), isFalse);
    });

    test('TC-06: Independent Port Widths (SS5-3 fix)', () {
      const params = TrayUnequalCrossScaleParameters(
        port1Width: 150.0, // West
        port2Width: 200.0, // North
        port3Width: 100.0, // East
        port4Width: 250.0, // South
        port1Height: 50.0,
        port2Height: 50.0,
        port3Height: 50.0,
        port4Height: 50.0,
      );

      final scaled = TrayUnequalCrossScaler.scaleWithParameters(unequalCrossDoc, params);

      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      final b3 = scaled.bends.firstWhere((b) => b.id == 'B3');
      final b4 = scaled.bends.firstWhere((b) => b.id == 'B4');

      final westW = (b4.p1.y - b1.p2.y).abs();
      final northW = (b2.p2.x - b1.p1.x).abs();
      final eastW = (b3.p2.y - b2.p1.y).abs();
      final southW = (b3.p1.x - b4.p2.x).abs();

      expect(westW, closeTo(150.0, 1e-3));
      expect(northW, closeTo(200.0, 1e-3));
      expect(eastW, closeTo(100.0, 1e-3));
      expect(southW, closeTo(250.0, 1e-3));

      // 3D folding works
      final foldResult = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);
    });

    test('TC-07: Independent Port Heights & Slanted Cheek Walls (SS5-2 fix)', () {
      const params = TrayUnequalCrossScaleParameters(
        port1Width: 100.0,
        port2Width: 100.0,
        port3Width: 100.0,
        port4Width: 100.0,
        port1Height: 50.0,  // West
        port2Height: 100.0, // North (>= 95mm)
        port3Height: 50.0,  // East
        port4Height: 100.0, // South (>= 95mm)
      );

      final scaled = TrayUnequalCrossScaler.scaleWithParameters(unequalCrossDoc, params);

      // Verify the 2D contour extends to support the 100mm heights
      final fl1 = scaled.bends.firstWhere((b) => b.id == 'FL1');
      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');

      // NW sidewall slants from North (h=100) to West (h=50)
      final dNorth = _pointToLineDistance(fl1.p1, b1.p1, b1.p2);
      final dWest = _pointToLineDistance(fl1.p2, b1.p1, b1.p2);
      expect(dNorth, closeTo(100.0, 1e-3));
      expect(dWest, closeTo(50.0, 1e-3));

      // Intelligent placement: slots must clear bottom bend (>=10mm) and top flange (<= hU - 15mm)
      // At tall end (h=100): u=25 has 2 slots, u=75 has 1 slot (top slot omitted to prevent overshoot on slanted wall) = 3 slots
      // At short end (h=50): u=L-75 has 1 slot, u=L-25 has 1 slot = 2 slots
      // 4 walls * 5 slots = 20 slots total (no overshooting)
      final couplers = scaled.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      expect(couplers.length, equals(20));

      // 3D folding works
      final foldResult = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);
    });

    test('TC-08: Unequal Cross Coupler Flaps (SS5-1 fix)', () {
      const params = TrayUnequalCrossScaleParameters(
        port1Width: 100.0,
        port2Width: 100.0,
        port3Width: 100.0,
        port4Width: 100.0,
        port1Height: 50.0,
        port2Height: 100.0,
        port3Height: 50.0,
        port4Height: 100.0,
        includeCouplerFlaps: true,
        couplerFlapLength: 90.0,
      );

      final withFlaps = TrayUnequalCrossScaler.scaleWithParameters(unequalCrossDoc, params);

      // 8 Flap bends
      final flapBends = withFlaps.bends.where((b) => b.id.startsWith('BF_')).toList();
      expect(flapBends.length, equals(8));

      // 24 flap slots (3 vertical slots per flap)
      final visibleCouplers = withFlaps.punches.where((p) => p.role == CncPunchRole.coupler && p.isVisible).toList();
      expect(visibleCouplers.length, equals(24));

      // 3D folding works with parallel orthogonal flaps
      final foldResult = KinematicFoldEngine.foldDocument(withFlaps, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      final fNwP1 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_8_P1');
      final fSwP1 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_5_P1');
      final fNwP2 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_8_P2');
      final fNeP2 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P2');
      final fNeP3 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P3');
      final fSeP3 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P3');
      final fSwP4 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_5_P4');
      final fSeP4 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P4');

      // Port 1 (West): flap normals along Y axis
      expect(fNwP1.normal.y.abs(), closeTo(1.0, 1e-2));
      expect(fSwP1.normal.y.abs(), closeTo(1.0, 1e-2));

      // Port 2 (North): flap normals along X axis
      expect(fNwP2.normal.x.abs(), closeTo(1.0, 1e-2));
      expect(fNeP2.normal.x.abs(), closeTo(1.0, 1e-2));

      // Port 3 (East): flap normals along Y axis
      expect(fNeP3.normal.y.abs(), closeTo(1.0, 1e-2));
      expect(fSeP3.normal.y.abs(), closeTo(1.0, 1e-2));

      // Port 4 (South): flap normals along X axis
      expect(fSwP4.normal.x.abs(), closeTo(1.0, 1e-2));
      expect(fSeP4.normal.x.abs(), closeTo(1.0, 1e-2));
    });

    test('TC-08b: SS3 & SS4 Unequal Cross Regression (Different Widths & Heights)', () {
      // Configuration matching SS3 & SS4
      const ss3Params = TrayUnequalCrossScaleParameters(
        port1Width: 125.0,
        port1Height: 100.0,
        port2Width: 100.0,
        port2Height: 50.0,
        port3Width: 50.0,
        port3Height: 125.0,
        port4Width: 100.0,
        port4Height: 50.0,
        includeCouplerFlaps: true,
        couplerFlapLength: 90.0,
      );

      final scaledDoc = TrayUnequalCrossScaler.scaleWithParameters(unequalCrossDoc, ss3Params);

      // Floor mouth perforations:
      // Port 3 (W=50) should have exactly 1 slot, centered, not overshooting mouth
      final pEastTop = scaledDoc.faces.firstWhere((f) => f.id == 'F_6').vertices[2];
      final pEastBot = scaledDoc.faces.firstWhere((f) => f.id == 'F_6').vertices[3];
      final eastMouthSlots = scaledDoc.punches.where((p) =>
        p.role == CncPunchRole.perforation &&
        (p.center.x - (pEastTop.x - 20.0)).abs() < 1.0
      ).toList();
      expect(eastMouthSlots.length, equals(1));
      expect(eastMouthSlots.first.center.y, closeTo((pEastTop.y + pEastBot.y) / 2.0, 1e-3));

      // Fold in 3D
      final foldResult = KinematicFoldEngine.foldDocument(scaledDoc, foldProgress: 1.0);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      // Verify flap normals in 3D are parallel per port even when cheek wall angles != 45°
      final fNwP1 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_8_P1');
      final fSwP1 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_5_P1');
      final fNwP2 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_8_P2');
      final fNeP2 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P2');
      final fNeP3 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_1_P3');
      final fSeP3 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P3');
      final fSwP4 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_5_P4');
      final fSeP4 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_FLAP_3_P4');

      expect(fNwP1.normal.y.abs(), closeTo(1.0, 1e-2));
      expect(fSwP1.normal.y.abs(), closeTo(1.0, 1e-2));
      expect(fNwP2.normal.x.abs(), closeTo(1.0, 1e-2));
      expect(fNeP2.normal.x.abs(), closeTo(1.0, 1e-2));
      expect(fNeP3.normal.y.abs(), closeTo(1.0, 1e-2));
      expect(fSeP3.normal.y.abs(), closeTo(1.0, 1e-2));
      expect(fSwP4.normal.x.abs(), closeTo(1.0, 1e-2));
      expect(fSeP4.normal.x.abs(), closeTo(1.0, 1e-2));

      // 3D Opening Detector & Opening Plane Analyzer: heightDir is +Z
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaledDoc, foldResult: foldResult);
      expect(rawOpenings.length, equals(4));
      for (final raw in rawOpenings) {
        final analyzed = CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: scaledDoc, foldResult: foldResult);
        expect(analyzed.heightDirection.z, closeTo(1.0, 1e-2));
      }
    });
  });

  group('CmsScalingController Integration - Cross Fittings', () {
    test('TC-09: Equal Cross in Controller', () {
      final controller = CmsScalingController(
        baselineDocument: equalCrossDoc,
        contract: CmsProductContract.equalCross,
        baselinePorts: [
          const CmsPhysicalPort(id: 'PORT_1', width: 100.0, height: 50.0, index: 1),
          const CmsPhysicalPort(id: 'PORT_2', width: 100.0, height: 50.0, index: 2),
          const CmsPhysicalPort(id: 'PORT_3', width: 100.0, height: 50.0, index: 3),
          const CmsPhysicalPort(id: 'PORT_4', width: 100.0, height: 50.0, index: 4),
        ],
      );

      expect(controller.isLinkedPorts, isTrue);
      expect(controller.model.parameters.containsKey('width'), isTrue);
      expect(controller.model.parameters.containsKey('height'), isTrue);

      // Scale W to 150
      controller.selectParameter('width');
      controller.evaluateMorph(150.0);
      expect(controller.previewDocument.parameters['width'], equals(150.0));

      // Scale H to 100 -> triggers 2-row punches
      controller.selectParameter('height');
      controller.evaluateMorph(100.0);
      expect(controller.previewDocument.parameters['height'], equals(100.0));
      expect(controller.previewDocument.punches.where((p) => p.role == CncPunchRole.coupler).length, equals(32));

      // Flaps toggle
      controller.setIncludeCouplerFlaps(true);
      expect(controller.previewDocument.bends.where((b) => b.id.startsWith('BF_')).length, equals(8));
    });

    test('TC-10: Unequal Cross in Controller (Independent Ports & Flaps)', () {
      final controller = CmsScalingController(
        baselineDocument: unequalCrossDoc,
        contract: CmsProductContract.unequalCross,
        baselinePorts: [
          const CmsPhysicalPort(id: 'PORT_1', width: 50.0, height: 50.0, index: 1),
          const CmsPhysicalPort(id: 'PORT_2', width: 100.0, height: 50.0, index: 2),
          const CmsPhysicalPort(id: 'PORT_3', width: 50.0, height: 50.0, index: 3),
          const CmsPhysicalPort(id: 'PORT_4', width: 100.0, height: 50.0, index: 4),
        ],
      );

      expect(controller.isLinkedPorts, isFalse);
      expect(controller.model.parameters.containsKey('port1_width'), isTrue);
      expect(controller.model.parameters.containsKey('port2_width'), isTrue);
      expect(controller.model.parameters.containsKey('port1_height'), isTrue);
      expect(controller.model.parameters.containsKey('port2_height'), isTrue);

      // Scale Port 1 Width to 150 -> other ports stay unchanged!
      controller.selectParameter('port1_width');
      controller.evaluateMorph(150.0);

      expect(controller.model.parameters['port1_width']!.currentValue, equals(150.0));
      expect(controller.model.parameters['port2_width']!.currentValue, equals(100.0));
      expect(controller.model.parameters['port3_width']!.currentValue, equals(50.0));
      expect(controller.model.parameters['port4_width']!.currentValue, equals(100.0));

      // Flaps toggle
      controller.setIncludeCouplerFlaps(true);
      expect(controller.previewDocument.bends.where((b) => b.id.startsWith('BF_')).length, equals(8));
    });

    test('TC-Debug: Opening detection on Equal Cross scaled', () {
      final scaled = TrayEqualCrossScaler.scale(
        baseline: equalCrossDoc,
        targetWidth: 200.0,
        targetHeight: 150.0,
      );
      final foldResult = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: scaled, foldResult: foldResult);
      print('DEBUG: Found ${rawOpenings.length} raw openings');
      final f8 = foldResult.polygons.firstWhere((p) => p.faceId == 'F_8');
      print('DEBUG F_8 vertices: ${f8.vertices}');
      for (final raw in rawOpenings) {
        final floorPoly = foldResult.polygons.where((p) => p.faceId == raw.floorFaceId).firstOrNull;
        print('DEBUG: raw ${raw.openingId}, floorFaceId: ${raw.floorFaceId}, floorPoly.normal: ${floorPoly?.normal}');
        final analyzed = CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: scaled, foldResult: foldResult);
        print('DEBUG: opening ${raw.openingId}, floorP1: ${analyzed.floorP1}, floorP2: ${analyzed.floorP2}, corners: ${analyzed.derivedMouthCorners}, heightDir: ${analyzed.heightDirection}, normal: ${analyzed.normal}, H: ${analyzed.height}');
      }
    });
  });
}

double _pointToLineDistance(CadPoint2D pt, CadPoint2D p1, CadPoint2D p2) {
  final dx = p2.x - p1.x;
  final dy = p2.y - p1.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < 1e-6) return 0.0;
  final cross = ((pt.x - p1.x) * dy - (pt.y - p1.y) * dx).abs();
  return cross / length;
}
