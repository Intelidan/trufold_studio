import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_bend_geometry_solver.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_bend_45_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_bend_90_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';

void main() {
  late DsfDocument doc45_100x50;
  late DsfDocument doc90_100x50;

  setUpAll(() {
    final file45 = File('assets/dsf_templates/tray_accessories/45_deg_bend_100x50.dsf');
    doc45_100x50 = DsfDocument.fromJson(jsonDecode(file45.readAsStringSync()) as Map<String, dynamic>);

    final file90 = File('assets/dsf_templates/tray_accessories/90_deg_bend_100x50.dsf');
    doc90_100x50 = DsfDocument.fromJson(jsonDecode(file90.readAsStringSync()) as Map<String, dynamic>);
  });

  group('Production Specification v3.5 — Tray 45° Bend Scaling', () {
    test('TC-01: Baseline 45° bend (100x50, R=180) exact reproduction', () {
      final sol = TrayBendGeometrySolver.solve(
        bendAngleDeg: 45.0,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        xMidBase: TrayBend45Scaler.xMid,
        yB1Base: TrayBend45Scaler.yB1,
        lB1Base: TrayBend45Scaler.lB1Base,
        lWingBase: TrayBend45Scaler.lExt,
      );

      expect(sol.lB1, closeTo(200.0, 1e-4));
      expect(sol.lWing, closeTo(49.70, 0.05));
      expect(sol.lB2, closeTo(184.70, 0.2));
      expect(sol.heightRows, 1);
      expect(sol.wingColumns, 1);
      expect(sol.totalWingPositions, 2);

      // Invariant check: (2 * wingTakeUp) + lB2 == totalSpan
      expect(2 * sol.wingTakeUp + sol.lB2, closeTo(sol.p2In.x - sol.p1In.x, 1e-4));

      final scaled = TrayBend45Scaler.scale(
        baseline: doc45_100x50,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
      );
      expect(scaled, isNotNull);

      // Fold to 3D
      final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      expect(fold.polygons.length, greaterThanOrEqualTo(9));
      final openings = Cms3DOpeningDetector.detectOpenings(document: scaled, foldResult: fold);
      expect(openings.length, 2);
    });

    test('TC-02: Height scaling (100x100, R=180, 45°) adds 1 row/hole per 25mm increase', () {
      final sol = TrayBendGeometrySolver.solve(
        bendAngleDeg: 45.0,
        targetWidth: 100.0,
        targetHeight: 100.0,
        targetRadius: 180.0,
        xMidBase: TrayBend45Scaler.xMid,
        yB1Base: TrayBend45Scaler.yB1,
        lB1Base: TrayBend45Scaler.lB1Base,
        lWingBase: TrayBend45Scaler.lExt,
      );

      expect(sol.lB1, closeTo(200.0, 1e-4));
      // For every 25mm increase in height: 50mm -> 1 row, 75mm -> 2 rows, 100mm -> 3 rows
      expect(sol.heightRows, 3);
      expect(sol.wingColumns, 1);
      // Wing holes: 2 at 50mm, 3 at 75mm, 4 at 100mm
      expect(sol.totalWingPositions, 4);

      final scaled = TrayBend45Scaler.scale(
        baseline: doc45_100x50,
        targetWidth: 100.0,
        targetHeight: 100.0,
        targetRadius: 180.0,
      );

      final couplerSlots = scaled.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      // B1 has 3 rows × 4 slots = 12 slots; Left wing has 4 slots; Right wing has 4 slots; Total = 20
      expect(couplerSlots.length, 20);

      // Straight side wall at H=100 (>=100mm) has 2 perforations
      final sideWallHoles = scaled.punches.where((p) => p.role == CncPunchRole.perforation && p.rotationDeg == 0.0 && p.center.y > 180.0).toList();
      expect(sideWallHoles.length, 2);
    });

    test('TC-03: Width scaling & wing doubling (450x50, R=180, 45°)', () {
      final sol = TrayBendGeometrySolver.solve(
        bendAngleDeg: 45.0,
        targetWidth: 450.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        xMidBase: TrayBend45Scaler.xMid,
        yB1Base: TrayBend45Scaler.yB1,
        lB1Base: TrayBend45Scaler.lB1Base,
        lWingBase: TrayBend45Scaler.lExt,
      );

      // B1 is strictly invariant to width!
      expect(sol.lB1, closeTo(200.0, 1e-4));

      // Wing growth: 49.70 + 0.2557009 * 350 ≈ 139.195mm (matches master template 139.17)
      expect(sol.lWing, closeTo(139.2, 0.1));

      // Base span B2 redistribution: wings consume width!
      expect(sol.lB2, closeTo(287.45, 0.5));

      // Invariant: wings consume base
      expect(2 * sol.wingTakeUp + sol.lB2, closeTo(sol.p2In.x - sol.p1In.x, 1e-4));

      // Wings double up: W >= 300 => WingColumns = 2. 2 holes × 2 cols = 4
      expect(sol.heightRows, 1);
      expect(sol.wingColumns, 2);
      expect(sol.totalWingPositions, 4);

      final scaled = TrayBend45Scaler.scale(
        baseline: doc45_100x50,
        targetWidth: 450.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
      );

      // B1 has 1 row (4 slots). Each wing has 2 holes × 2 cols = 4 slots. Total coupler = 4 + 4 + 4 = 12.
      final couplerSlots = scaled.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      expect(couplerSlots.length, 12);
    });

    test('TC-04: Combined 2x2 grid (450x100, R=180, 45°)', () {
      final sol = TrayBendGeometrySolver.solve(
        bendAngleDeg: 45.0,
        targetWidth: 450.0,
        targetHeight: 100.0,
        targetRadius: 180.0,
        xMidBase: TrayBend45Scaler.xMid,
        yB1Base: TrayBend45Scaler.yB1,
        lB1Base: TrayBend45Scaler.lB1Base,
        lWingBase: TrayBend45Scaler.lExt,
      );

      // Height = 100mm: 3 rows, 4 wing holes × 2 cols = 8 positions per wing
      expect(sol.heightRows, 3);
      expect(sol.wingColumns, 2);
      expect(sol.totalWingPositions, 8);

      final scaled = TrayBend45Scaler.scale(
        baseline: doc45_100x50,
        targetWidth: 450.0,
        targetHeight: 100.0,
        targetRadius: 180.0,
      );

      // B1 has 3 rows × 4 = 12 slots. Each wing has 4 holes × 2 cols = 8 slots. Total = 12 + 8 + 8 = 28 slots.
      final couplerSlots = scaled.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      expect(couplerSlots.length, 28);

      // Verify 3D folding
      final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      expect(fold.polygons.length, greaterThanOrEqualTo(9));
    });
  });

  group('Production Specification v3.5 — Tray 90° Bend Scaling', () {
    test('TC-05: Baseline 90° bend (100x50, R=180) exact reproduction', () {
      final sol = TrayBendGeometrySolver.solve(
        bendAngleDeg: 90.0,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        xMidBase: TrayBend90Scaler.xMid,
        yB1Base: TrayBend90Scaler.yB1,
        lB1Base: TrayBend90Scaler.lB1Base,
        lWingBase: TrayBend90Scaler.lExt,
      );

      expect(sol.lB1, closeTo(200.0, 1e-4));
      expect(sol.lWing, closeTo(66.10, 0.05));
      expect(sol.lB2, closeTo(247.94, 0.2));
      expect(sol.heightRows, 1);
      expect(sol.wingColumns, 1);

      // Invariant: 2 * wingTakeUp + lB2 == totalSpan
      expect(2 * sol.wingTakeUp + sol.lB2, closeTo(sol.p2In.x - sol.p1In.x, 1e-4));

      final scaled = TrayBend90Scaler.scale(
        baseline: doc90_100x50,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
      );
      expect(scaled, isNotNull);

      final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      expect(fold.polygons.length, greaterThanOrEqualTo(9));
      final openings = Cms3DOpeningDetector.detectOpenings(document: scaled, foldResult: fold);
      expect(openings.length, 2);
    });

    test('TC-06: 90° wing growth coefficient is 1 - sqrt(2)/2 ≈ 0.2928932', () {
      final sol = TrayBendGeometrySolver.solve(
        bendAngleDeg: 90.0,
        targetWidth: 450.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        xMidBase: TrayBend90Scaler.xMid,
        yB1Base: TrayBend90Scaler.yB1,
        lB1Base: TrayBend90Scaler.lB1Base,
        lWingBase: TrayBend90Scaler.lExt,
      );

      // Expected growth: 350 * (1 - sqrt(2)/2) ≈ 350 * 0.2928932 = 102.5126
      // lWing = 66.10 + 102.51 = 168.61mm
      expect(sol.lWing, closeTo(168.61, 0.1));
      expect(sol.wingColumns, 2); // W >= 300 doubles up wing columns
      expect(sol.heightRows, 1);
    });

    test('TC-07: Radius scaling with 4 discrete presets (180, 300, 600, 900 mm, 45°)', () {
      // 1. Preset 180 mm (minimum and default starting point)
      final sol180 = TrayBendGeometrySolver.solve(
        bendAngleDeg: 45.0,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
        xMidBase: TrayBend45Scaler.xMid,
        yB1Base: TrayBend45Scaler.yB1,
        lB1Base: TrayBend45Scaler.lB1Base,
        lWingBase: TrayBend45Scaler.lExt,
      );
      expect(sol180.lB1, 200.0);
      expect(sol180.heightRows, 1);
      expect(sol180.wingColumns, 1);

      // 2. Preset 300 mm
      final sol300 = TrayBendGeometrySolver.solve(
        bendAngleDeg: 45.0,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 300.0,
        xMidBase: TrayBend45Scaler.xMid,
        yB1Base: TrayBend45Scaler.yB1,
        lB1Base: TrayBend45Scaler.lB1Base,
        lWingBase: TrayBend45Scaler.lExt,
      );
      // Delta R = 300 - 180 = 120. Growth = 2 * 120 * tan(11.25°) = 240 * 0.19891237 = 47.739mm
      expect(sol300.lB1, closeTo(247.74, 0.1));
      expect(sol300.heightRows, 1);
      expect(sol300.wingColumns, 1);

      // 3. Preset 600 mm
      final sol600 = TrayBendGeometrySolver.solve(
        bendAngleDeg: 45.0,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 600.0,
        xMidBase: TrayBend45Scaler.xMid,
        yB1Base: TrayBend45Scaler.yB1,
        lB1Base: TrayBend45Scaler.lB1Base,
        lWingBase: TrayBend45Scaler.lExt,
      );
      // Delta R = 600 - 180 = 420. Growth = 2 * 420 * tan(11.25°) = 840 * 0.19891237 = 167.086mm
      expect(sol600.lB1, closeTo(367.09, 0.1));
      expect(sol600.heightRows, 1);
      expect(sol600.wingColumns, 1);

      // 4. Preset 900 mm
      final sol900 = TrayBendGeometrySolver.solve(
        bendAngleDeg: 45.0,
        targetWidth: 100.0,
        targetHeight: 50.0,
        targetRadius: 900.0,
        xMidBase: TrayBend45Scaler.xMid,
        yB1Base: TrayBend45Scaler.yB1,
        lB1Base: TrayBend45Scaler.lB1Base,
        lWingBase: TrayBend45Scaler.lExt,
      );
      // Delta R = 900 - 180 = 720. Growth = 2 * 720 * tan(11.25°) = 1440 * 0.19891237 = 286.434mm
      expect(sol900.lB1, closeTo(486.43, 0.1));
      expect(sol900.heightRows, 1);
      expect(sol900.wingColumns, 1);
    });

    test('TC-08: Perforation orientation and bottom wall slot across scaling (SS1-SS5)', () {
      // 1. 45° bend scaled to W=180 (SS2)
      final scaled45_180 = TrayBend45Scaler.scale(
        baseline: doc45_100x50,
        targetWidth: 180.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
      );

      final diag45Left = scaled45_180.punches.where((p) => (p.rotationDeg - 22.5).abs() < 1e-3).toList();
      final diag45Right = scaled45_180.punches.where((p) => (p.rotationDeg - 157.5).abs() < 1e-3).toList();
      expect(diag45Left.isNotEmpty, isTrue, reason: '45° left diagonal floor slots must have rotation 22.5°');
      expect(diag45Right.isNotEmpty, isTrue, reason: '45° right diagonal floor slots must have rotation 157.5°');

      // Verify bottom wall slot exists and is horizontal (0.0°)
      final bottomWall45 = scaled45_180.punches.where((p) => p.rotationDeg == 0.0 && p.center.y > 220.0).toList();
      expect(bottomWall45.length, 1, reason: 'Bottom wall perforation slot must exist at center');

      // 2. 90° bend scaled to W=150 (SS4)
      final scaled90_150 = TrayBend90Scaler.scale(
        baseline: doc90_100x50,
        targetWidth: 150.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
      );

      final diag90Left = scaled90_150.punches.where((p) => p.role == CncPunchRole.perforation && (p.rotationDeg - 45.0).abs() < 1e-3).toList();
      final diag90Right = scaled90_150.punches.where((p) => p.role == CncPunchRole.perforation && (p.rotationDeg - 135.0).abs() < 1e-3).toList();
      expect(diag90Left.length, equals(3), reason: '90° (W=150) flat base perforation must have 3 holes for width up to 200mm');
      expect(diag90Right.length, equals(3), reason: '90° (W=150) flat base perforation must have 3 holes for width up to 200mm');

      final bottomWall90 = scaled90_150.punches.where((p) => p.role == CncPunchRole.perforation && p.rotationDeg == 0.0 && p.center.y > 180.0).toList();
      expect(bottomWall90.length, 1, reason: '90° straight side wall perforation must have single hole for H <= 75mm');

      // 3. 90° bend scaled to W=75 (Single hole for from 50mm to 75mm width)
      final scaled90_75 = TrayBend90Scaler.scale(
        baseline: doc90_100x50,
        targetWidth: 75.0,
        targetHeight: 50.0,
        targetRadius: 180.0,
      );

      final diag9075Left = scaled90_75.punches.where((p) => p.role == CncPunchRole.perforation && (p.rotationDeg - 45.0).abs() < 1e-3).toList();
      final diag9075Right = scaled90_75.punches.where((p) => p.role == CncPunchRole.perforation && (p.rotationDeg - 135.0).abs() < 1e-3).toList();
      expect(diag9075Left.length, equals(1), reason: '90° (W=75) flat base perforation must be single hole for 50-75mm width');
      expect(diag9075Right.length, equals(1), reason: '90° (W=75) flat base perforation must be single hole for 50-75mm width');

      // 4. 90° bend scaled to H=100 (2 holes for >=100mm height)
      final scaled90H100 = TrayBend90Scaler.scale(
        baseline: doc90_100x50,
        targetWidth: 100.0,
        targetHeight: 100.0,
        targetRadius: 180.0,
      );
      final sideWallHoles90 = scaled90H100.punches.where((p) => p.role == CncPunchRole.perforation && p.rotationDeg == 0.0 && p.center.y > 180.0).toList();
      expect(sideWallHoles90.length, equals(2), reason: 'Straight side wall perforation must have 2 holes for H >= 100mm');
    });

    test('TC-09: Maximum Width 1200mm and Height 250mm scaling', () {
      final sol1200x250 = TrayBendGeometrySolver.solve(
        bendAngleDeg: 90.0,
        targetWidth: 1200.0,
        targetHeight: 250.0,
        targetRadius: 180.0,
        xMidBase: TrayBend90Scaler.xMid,
        yB1Base: TrayBend90Scaler.yB1,
        lB1Base: TrayBend90Scaler.lB1Base,
        lWingBase: TrayBend90Scaler.lExt,
      );
      // B1 invariant to width at baseline R=180
      expect(sol1200x250.lB1, closeTo(200.0, 1e-4));
      // Height 250mm: 1 + (250 - 50)/25 = 1 + 8 = 9 coupler rows
      expect(sol1200x250.heightRows, 9);
      // Width 1200mm (>= 300mm) has 2 wing columns
      expect(sol1200x250.wingColumns, 2);
      // Wing holes: 2 + 8 = 10 holes * 2 cols = 20 positions
      expect(sol1200x250.totalWingPositions, 20);

      final scaled90_1200 = TrayBend90Scaler.scale(
        baseline: doc90_100x50,
        targetWidth: 1200.0,
        targetHeight: 250.0,
        targetRadius: 180.0,
      );
      expect(scaled90_1200, isNotNull);
      final fold = KinematicFoldEngine.foldDocument(scaled90_1200, foldProgress: 1.0);
      expect(fold.polygons.length, greaterThanOrEqualTo(9));
      final openings = Cms3DOpeningDetector.detectOpenings(document: scaled90_1200, foldResult: fold);
      expect(openings.length, 2);
    });
  });
}
