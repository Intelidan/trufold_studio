// =============================================================================
// tray_bend_90_scaler.dart
//
// Dedicated Parametric Analytical Scaling Engine for 90° Cable Tray Bends.
// Production Specification v3.5.
//
// Solvers:
// 1. solveBendRadius: Handles inside throat arc, tangent offsets, and B1 chord.
// 2. solveWingGeometry: Analytical wing growth K_wing = tan(45°)*(1 - sin(45°)) = 1 - sqrt(2)/2.
// 3. solveBaseRedistribution: Straight base span L_B2 = Span - 2 * WingTakeUp.
// 4. solveCouplerPattern: Explicit HeightRows × WingColumns grid generation.
// =============================================================================

import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import 'tray_bend_geometry_solver.dart';

class TrayBend90ScaleParameters {
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

  const TrayBend90ScaleParameters({
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

class TrayBend90Scaler {
  static const double bendAngleDeg = 90.0;

  // Baseline reference constants (derived from assets/dsf_templates/tray_accessories/90_deg_bend_100x50.dsf)
  static const double xMid = 215.258405333407;
  static const double yB1 = 63.0;
  static const double lExt = 66.101749774983; // Baseline 90° wing length at W=100
  static const double lB1Base = 200.0;
  static const double p1InXBase = 44.54772721475245;
  static const double p1InYBase = 133.71067811865564;
  static const double p2InXBase = 385.96908345206157;
  static const double p2InYBase = 133.71067811865578;
  static const double c4XBase = 91.28932188134422;
  static const double c4YBase = 180.45227278524754;
  static const double c3XBase = 339.22748878546906;
  static const double c3YBase = 180.45227278524754;

  /// Checks whether [doc] matches the Cable Tray 90° Bend geometry.
  static bool isTrayBend90(DsfDocument doc) {
    final type = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (type.contains('trunking')) return false;
    final has90Bend = (type.contains('90') || type.contains('flat bend')) && type.contains('bend') && !type.contains('45');
    final has8Bends = doc.bends.length == 8;
    final has4Flanges = doc.bends.where((b) => b.role == BendLineRole.flange || (b.targetAngleDeg.abs() - 135.0).abs() < 10.0).length == 4;

    return (has90Bend && (has8Bends || has4Flanges)) || (has8Bends && has4Flanges && !type.contains('45'));
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
    final params = TrayBend90ScaleParameters(
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

  static DsfDocument scaleWithParameters(DsfDocument baseline, TrayBend90ScaleParameters params) {
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
