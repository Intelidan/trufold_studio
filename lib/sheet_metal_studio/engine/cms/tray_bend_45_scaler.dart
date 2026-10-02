// =============================================================================
// tray_bend_45_scaler.dart
//
// Dedicated Parametric Analytical Scaling Engine for 45° Cable Tray Bends.
// Production Specification v3.5.
//
// Solvers:
// 1. solveBendRadius: Handles inside throat arc, tangent offsets, and B1 chord.
// 2. solveWingGeometry: Analytical wing growth K_wing = tan(22.5°)*(1 - sin(22.5°)).
// 3. solveBaseRedistribution: Straight base span L_B2 = Span - 2 * WingTakeUp.
// 4. solveCouplerPattern: Explicit HeightRows × WingColumns grid generation.
// =============================================================================

import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import 'tray_bend_geometry_solver.dart';

class TrayBend45ScaleParameters {
  final double targetWidth;
  final double targetHeight;
  final double targetRadius;
  final double baselineWidth;
  final double baselineHeight;
  final double baselineRadius;
  final bool includeCouplerFlaps;
  final double couplerFlapLength;

  double get dW => targetWidth - baselineWidth;
  double get dH => targetHeight - baselineHeight;
  double get dR => targetRadius - baselineRadius;

  bool get hasAnyChange =>
      (dW).abs() > 1e-4 ||
      (dH).abs() > 1e-4 ||
      (dR).abs() > 1e-4 ||
      includeCouplerFlaps ||
      (couplerFlapLength - 90.0).abs() > 1e-4;

  const TrayBend45ScaleParameters({
    required this.targetWidth,
    required this.targetHeight,
    this.targetRadius = 180.0,
    this.baselineWidth = 100.0,
    this.baselineHeight = 50.0,
    this.baselineRadius = 180.0,
    this.includeCouplerFlaps = false,
    this.couplerFlapLength = 90.0,
  });
}

class TrayBend45Scaler {
  static const double bendAngleDeg = 45.0;

  // Baseline reference constants (derived from assets/dsf_templates/tray_accessories/45_deg_bend_100x50.dsf)
  static const double xMid = 162.37739947551;
  static const double yB1 = 63.0;
  static const double lExt = 49.70068407421832; // Baseline 50mm straight port extension
  static const double lB1Base = 200.0;
  static const double p1InXBase = 24.109056239000967;
  static const double p1InYBase = 155.38795325112867;
  static const double p2InXBase = 300.64574271201905;
  static const double p2InYBase = 155.38795325112867;
  static const double c4XBase = 70.02663276779899;
  static const double c4YBase = 174.40763620066042;
  static const double c3XBase = 254.728166183221;
  static const double c3YBase = 174.40763620066042;

  /// Checks whether [doc] matches the Cable Tray 45° Bend geometry.
  static bool isTrayBend45(DsfDocument doc) {
    final type = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (type.contains('trunking')) return false;
    final has45Bend = type.contains('45') && type.contains('bend');
    final has8Bends = doc.bends.length == 8;
    final has4Flanges = doc.bends.where((b) => b.role == BendLineRole.flange || (b.targetAngleDeg.abs() - 135.0).abs() < 10.0).length == 4;

    return (has45Bend && (has8Bends || has4Flanges)) || (has8Bends && has4Flanges);
  }

  /// Scales [baseline] to [targetWidth], [targetHeight], and [targetRadius].
  static DsfDocument scale({
    required DsfDocument baseline,
    required double targetWidth,
    required double targetHeight,
    double targetRadius = 180.0,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 90.0,
  }) {
    final params = TrayBend45ScaleParameters(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      targetRadius: targetRadius,
      baselineWidth: 100.0,
      baselineHeight: 50.0,
      baselineRadius: 180.0,
      includeCouplerFlaps: includeCouplerFlaps,
      couplerFlapLength: couplerFlapLength,
    );

    return scaleWithParameters(baseline, params);
  }

  static DsfDocument scaleWithParameters(DsfDocument baseline, TrayBend45ScaleParameters params) {
    final W = params.targetWidth;
    final H = params.targetHeight;
    final R = params.targetRadius;

    if (!params.hasAnyChange) return baseline;

    // 1. Compute Four-Tier Modular Solution
    final solution = TrayBendGeometrySolver.solve(
      bendAngleDeg: bendAngleDeg,
      targetWidth: W,
      targetHeight: H,
      targetRadius: R,
      xMidBase: xMid,
      yB1Base: yB1,
      lB1Base: lB1Base,
      lWingBase: lExt,
    );

    // 2. Transform Document
    return TrayBendGeometrySolver.transformDocument(
      baseline: baseline,
      solution: solution,
      xMidBase: xMid,
      yB1Base: yB1,
      lB1Base: lB1Base,
      lWingBase: lExt,
      c4XBase: c4XBase,
      c4YBase: c4YBase,
      c3XBase: c3XBase,
      c3YBase: c3YBase,
      p1InXBase: p1InXBase,
      p1InYBase: p1InYBase,
      p2InXBase: p2InXBase,
      p2InYBase: p2InYBase,
      includeCouplerFlaps: params.includeCouplerFlaps,
      couplerFlapLength: params.couplerFlapLength,
    );
  }
}
