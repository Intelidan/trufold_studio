// =============================================================================
// tray_unequal_tee_scaler.dart
//
// Dedicated Parametric Analytical Scaling Engine for Cable Tray Unequal Tees.
//
// Architectural Principles:
// 1. Through-Run & Branch Decoupling:
//    - Port 1 (Left mouth) and Port 2 (Right mouth) define the through-run channel.
//    - Port 3 (Bottom mouth) defines the branch channel (typically reduced width).
// 2. Floor Invariance & 45° Miters:
//    - The central floor web between B1, B2, B3 and the mouths expands parametrically.
//    - Miter bends B1 and B2 maintain exact 45° orientation.
// 3. Radius Scaling:
//    - Miter span expands proportionally with bend radius R (180mm baseline).
// 4. Universal Coupler & Perforation Rule:
//    - Height < 95mm: 1 row of coupler slots centered across 45° sidewalls.
//    - Height >= 95mm: 2 rows of coupler slots (50mm vertical pitch).
//    - Perforations: 20mm setback from mouths, spaced at 50mm pitch.
// 5. Port Opening Rectitude:
//    - Port mouths remain strictly perpendicular to channel axes.
// =============================================================================

import 'dart:math' as math;

import '../../models/cad_primitives.dart';
import '../../models/cms/cms_scaling_model.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';
import 'tray_bend_geometry_solver.dart';

class TrayUnequalTeeScaleParameters {
  final double port1Width;
  final double port2Width;
  final double port3Width;
  final double port1Height;
  final double port2Height;
  final double port3Height;
  final double targetRadius;

  final double baselinePort1Width;
  final double baselinePort2Width;
  final double baselinePort3Width;
  final double baselinePort1Height;
  final double baselinePort2Height;
  final double baselinePort3Height;
  final double baselineRadius;
  final bool includeCouplerFlaps;
  final double couplerFlapLength;
  final double perforationPitch;

  double get targetHeight => port1Height;
  double get baselineHeight => baselinePort1Height;

  bool get hasAnyChange =>
      includeCouplerFlaps ||
      (perforationPitch - 100.0).abs() > 1e-4 ||
      (port1Width - baselinePort1Width).abs() > 1e-4 ||
      (port2Width - baselinePort2Width).abs() > 1e-4 ||
      (port3Width - baselinePort3Width).abs() > 1e-4 ||
      (port1Height - baselinePort1Height).abs() > 1e-4 ||
      (port2Height - baselinePort2Height).abs() > 1e-4 ||
      (port3Height - baselinePort3Height).abs() > 1e-4 ||
      (targetRadius - baselineRadius).abs() > 1e-4;

  const TrayUnequalTeeScaleParameters({
    this.port1Width = 100.0,
    this.port2Width = 100.0,
    this.port3Width = 50.0,
    double? port1Height,
    double? port2Height,
    double? port3Height,
    double? targetHeight,
    this.targetRadius = 180.0,
    this.baselinePort1Width = 100.0,
    this.baselinePort2Width = 100.0,
    this.baselinePort3Width = 50.0,
    double? baselinePort1Height,
    double? baselinePort2Height,
    double? baselinePort3Height,
    double? baselineHeight,
    this.baselineRadius = 180.0,
    this.includeCouplerFlaps = false,
    this.couplerFlapLength = 90.0,
    this.perforationPitch = 100.0,
  })  : port1Height = port1Height ?? targetHeight ?? 50.0,
        port2Height = port2Height ?? targetHeight ?? 50.0,
        port3Height = port3Height ?? targetHeight ?? 50.0,
        baselinePort1Height = baselinePort1Height ?? baselineHeight ?? 50.0,
        baselinePort2Height = baselinePort2Height ?? baselineHeight ?? 50.0,
        baselinePort3Height = baselinePort3Height ?? baselineHeight ?? 50.0;

  factory TrayUnequalTeeScaleParameters.fromCmsParameters(
    Map<String, CmsScalingParameter> parameters, {
    required bool isLinked,
    bool? includeCouplerFlaps,
    double? couplerFlapLength,
    double? perforationPitch,
  }) {
    final effectiveIncludeFlaps =
        includeCouplerFlaps ?? ((parameters['include_coupler_flaps']?.currentValue ?? 0.0) > 0.5);
    final effectiveFlapLen =
        couplerFlapLength ?? (parameters['coupler_flap_length']?.currentValue ?? 90.0);
    final effectivePerfPitch =
        perforationPitch ?? (parameters['perforation_pitch']?.currentValue ?? 100.0);

    if (isLinked) {
      final w = parameters['width']?.currentValue ?? 100.0;
      final h = parameters['height']?.currentValue ?? 50.0;
      final r = parameters['radius']?.currentValue ?? 180.0;
      return TrayUnequalTeeScaleParameters(
        port1Width: w,
        port2Width: w,
        port3Width: (parameters['port3_width']?.currentValue ?? (w / 2.0)).clamp(50.0, 1200.0),
        port1Height: h,
        port2Height: h,
        port3Height: h,
        targetRadius: r,
        includeCouplerFlaps: effectiveIncludeFlaps,
        couplerFlapLength: effectiveFlapLen,
        perforationPitch: effectivePerfPitch,
      );
    }

    final p1W = parameters['port1_width']?.currentValue ?? parameters['port1_width']?.baselineValue ?? 100.0;
    final p2W = parameters['port2_width']?.currentValue ?? parameters['port2_width']?.baselineValue ?? 100.0;
    final p3W = parameters['port3_width']?.currentValue ?? parameters['port3_width']?.baselineValue ?? 50.0;

    final p1H = parameters['port1_height']?.currentValue ?? parameters['port1_height']?.baselineValue ?? 50.0;
    final p2H = parameters['port2_height']?.currentValue ?? parameters['port2_height']?.baselineValue ?? 50.0;
    final p3H = parameters['port3_height']?.currentValue ?? parameters['port3_height']?.baselineValue ?? 50.0;

    final r = parameters['radius']?.currentValue ?? 180.0;

    return TrayUnequalTeeScaleParameters(
      port1Width: p1W,
      port2Width: p2W,
      port3Width: p3W,
      port1Height: p1H,
      port2Height: p2H,
      port3Height: p3H,
      targetRadius: r,
      includeCouplerFlaps: effectiveIncludeFlaps,
      couplerFlapLength: effectiveFlapLen,
      perforationPitch: effectivePerfPitch,
    );
  }
}

class TrayUnequalTeeScaler {
  // Baseline geometric constants from assets/dsf_templates/tray_accessories/unequal_tee_100x50x100x50.dsf
  static const double xBranchMidBase = 212.4200720141831;
  static const double yBranchBase = 305.8723447994296;
  static const double spanBase = 142.8723447994321;
  static const double hWallTopBase = 49.77150667386305;
  static const double hWall45Base = 50.00;
  static const double wFlangeBase = 13.00;

  /// Determines whether [doc] is a Cable Tray Unequal Tee.
  static bool isTrayUnequalTee(DsfDocument doc) {
    final name = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (name.contains('trunking')) return false;

    final isTee = name.contains('tee');
    final isUnequal = name.contains('unequal');
    if (!isTee) return false;

    // Check for 6 bends (B1, B2, B3, FL1, FL2, FL3) and no trunking ear bends
    final has6Bends = doc.bends.length == 6;
    final hasNoEarBends = !doc.bends.any((b) => b.id == 'B4' || b.id == 'B5' || b.id == 'B6' || b.id == 'B7');
    final has45Bend = doc.bends.any((b) =>
        (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 &&
        ((b.p2.x - b.p1.x).abs() - (b.p2.y - b.p1.y).abs()).abs() < 2.0);

    // If explicit "unequal" keyword is present with 6 bends
    if (isUnequal && has6Bends && hasNoEarBends && has45Bend) return true;

    // Also detect unequal port dimensions if available
    if (has6Bends && hasNoEarBends && has45Bend) {
      final baseFloor = doc.faces.where((f) => f.isBaseAnchor || f.role == FaceRole.baseFloor).firstOrNull;
      if (baseFloor != null && baseFloor.vertices.length >= 6) {
        final xs = baseFloor.vertices.map((v) => v.x).toList()..sort();
        final ys = baseFloor.vertices.map((v) => v.y).toList()..sort();
        final floorW = xs.last - xs.first;
        final floorH = ys.last - ys.first;
        // In unequal tee 100x50x100x50, width is ~335.7 and height is ~243.1
        if ((floorW - 335.7).abs() < 20.0 && (floorH - 243.1).abs() < 20.0) {
          return true;
        }
      }
    }

    return false;
  }

  /// Scales [baseline] using [TrayUnequalTeeScaleParameters].
  static DsfDocument scaleWithParameters(DsfDocument baseline, TrayUnequalTeeScaleParameters params) {
    if (!params.hasAnyChange) return baseline;

    final w1 = params.port1Width;
    final w2 = params.port2Width;
    final w3 = params.port3Width;
    final h1 = params.port1Height;
    final h2 = params.port2Height;
    final h3 = params.port3Height;
    final r = params.targetRadius;

    final dR = r - 180.0;
    final span0 = spanBase + dR * math.tan(22.5 * math.pi / 180.0);

    // Independent mouth lengths:
    // Left mouth length = w1, Right mouth length = w2, Branch length = w3
    final maxW = math.max(w1, w2);
    final span1 = span0 + math.max(0.0, w2 - w1);
    final span2 = span0 + math.max(0.0, w1 - w2);

    // Branch mouth points along bottom edge
    final pBranchLeft = CadPoint2D(xBranchMidBase - w3 / 2.0, yBranchBase);
    final pBranchRight = CadPoint2D(xBranchMidBase + w3 / 2.0, yBranchBase);

    // Top horizontal bend line B3
    final yTop = yBranchBase - (span0 + maxW);
    final xB1Top = pBranchLeft.x - span1;
    final xB2Top = pBranchRight.x + span2;
    final b3P1 = CadPoint2D(xB1Top, yTop);
    final b3P2 = CadPoint2D(xB2Top, yTop);

    // Miter tops where 45° bends meet the mouth side edges
    final yB1Top = yTop + w1;
    final yB2Top = yTop + w2;
    final pB1Top = CadPoint2D(xB1Top, yB1Top);
    final pB2Top = CadPoint2D(xB2Top, yB2Top);

    // 45° sidewall unit normal vectors
    const invSqrt2 = 0.7071067811865475;
    const n1 = CadPoint2D(-invSqrt2, invSqrt2);
    const n2 = CadPoint2D(invSqrt2, invSqrt2);

    const wFlange = wFlangeBase; // 13.0 mm

    // 1. Back Wall F_6 & Flange F_4 (slants from h1 at Port 1 to h2 at Port 2)
    final fl1P1 = CadPoint2D(b3P2.x, yTop - h2);
    final fl1P2 = CadPoint2D(b3P1.x, yTop - h1);
    final v4 = CadPoint2D(b3P2.x, yTop - h2 - wFlange);
    final v5 = CadPoint2D(b3P1.x, yTop - h1 - wFlange);

    // 2. Left Wall F_1 & Flange F_0 (slants from h1 at Port 1 to h3 at Port 3)
    final fl2P1 = CadPoint2D(pB1Top.x + h1 * n1.x, pB1Top.y + h1 * n1.y);
    final fl2P2 = CadPoint2D(pBranchLeft.x + h3 * n1.x, pBranchLeft.y + h3 * n1.y);
    final v7 = CadPoint2D(pB1Top.x + (h1 + wFlange) * n1.x, pB1Top.y + (h1 + wFlange) * n1.y);
    final v8 = CadPoint2D(pBranchLeft.x + (h3 + wFlange) * n1.x, pBranchLeft.y + (h3 + wFlange) * n1.y);

    // 3. Right Wall F_3 & Flange F_2 (slants from h3 at Port 3 to h2 at Port 2)
    final fl3P1 = CadPoint2D(pBranchRight.x + h3 * n2.x, pBranchRight.y + h3 * n2.y);
    final fl3P2 = CadPoint2D(pB2Top.x + h2 * n2.x, pB2Top.y + h2 * n2.y);
    final v1 = CadPoint2D(pBranchRight.x + (h3 + wFlange) * n2.x, pBranchRight.y + (h3 + wFlange) * n2.y);
    final v2 = CadPoint2D(pB2Top.x + (h2 + wFlange) * n2.x, pB2Top.y + (h2 + wFlange) * n2.y);

    // Outer Contour Vertices (v0..v10)
    final v0 = pBranchRight;
    final v3 = pB2Top;
    final v6 = pB1Top;
    final v9 = pBranchLeft;
    final v10 = pBranchRight;

    final newOuterContour = [v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10];

    // Bends
    final b1 = FoldBendLine(
      id: 'B1',
      p1: pB1Top,
      p2: pBranchLeft,
      targetAngleDeg: 90.0,
      role: BendLineRole.bend,
      parentFaceId: 'F_5',
      childFaceId: 'F_1',
    );

    final b2 = FoldBendLine(
      id: 'B2',
      p1: pB2Top,
      p2: pBranchRight,
      targetAngleDeg: 90.0,
      role: BendLineRole.bend,
      parentFaceId: 'F_5',
      childFaceId: 'F_3',
    );

    final b3 = FoldBendLine(
      id: 'B3',
      p1: b3P1,
      p2: b3P2,
      targetAngleDeg: 90.0,
      role: BendLineRole.bend,
      parentFaceId: 'F_5',
      childFaceId: 'F_6',
    );

    final fl1 = FoldBendLine(
      id: 'FL1',
      p1: fl1P1,
      p2: fl1P2,
      targetAngleDeg: 135.0,
      role: BendLineRole.flange,
      parentFaceId: 'F_6',
      childFaceId: 'F_4',
    );

    final fl2 = FoldBendLine(
      id: 'FL2',
      p1: fl2P1,
      p2: fl2P2,
      targetAngleDeg: 135.0,
      role: BendLineRole.flange,
      parentFaceId: 'F_1',
      childFaceId: 'F_0',
    );

    final fl3 = FoldBendLine(
      id: 'FL3',
      p1: fl3P1,
      p2: fl3P2,
      targetAngleDeg: 135.0,
      role: BendLineRole.flange,
      parentFaceId: 'F_3',
      childFaceId: 'F_2',
    );

    final newBends = [b1, b2, fl2, fl3, b3, fl1];

    // Planar Faces
    final f5 = PlanarSheetFace(
      id: 'F_5',
      role: FaceRole.baseFloor,
      vertices: [b3P2, pB2Top, pBranchRight, pBranchLeft, pB1Top, b3P1],
      isBaseAnchor: true,
      label: 'Bottom Base Floor',
    );

    final f1 = PlanarSheetFace(
      id: 'F_1',
      role: FaceRole.sideWall,
      vertices: [fl2.p1, pB1Top, pBranchLeft, fl2.p2],
      label: 'Side Wall',
    );

    final f0 = PlanarSheetFace(
      id: 'F_0',
      role: FaceRole.returnFlange,
      vertices: [fl2.p2, v8, v7, fl2.p1],
      label: 'Return Flange',
    );

    final f3 = PlanarSheetFace(
      id: 'F_3',
      role: FaceRole.sideWall,
      vertices: [fl3.p1, pBranchRight, pB2Top, fl3.p2],
      label: 'Side Wall',
    );

    final f2 = PlanarSheetFace(
      id: 'F_2',
      role: FaceRole.returnFlange,
      vertices: [fl3.p2, v2, v1, fl3.p1],
      label: 'Return Flange',
    );

    final f6 = PlanarSheetFace(
      id: 'F_6',
      role: FaceRole.sideWall,
      vertices: [b3P1, fl1.p2, fl1.p1, b3P2],
      label: 'Side Wall',
    );

    final f4 = PlanarSheetFace(
      id: 'F_4',
      role: FaceRole.returnFlange,
      vertices: [fl1.p2, v5, v4, fl1.p1],
      label: 'Return Flange',
    );

    final newFaces = [f0, f1, f2, f3, f4, f5, f6];

    // Cheek vectors & angles for realigning coupler flap bend angles
    final vB1 = CadPoint2D(pBranchLeft.x - pB1Top.x, pBranchLeft.y - pB1Top.y);
    final lenB1 = math.sqrt(vB1.x * vB1.x + vB1.y * vB1.y);
    final u1 = CadPoint2D(vB1.x / lenB1, vB1.y / lenB1);
    final theta1 = math.atan2(vB1.y, vB1.x);

    final vB2 = CadPoint2D(pBranchRight.x - pB2Top.x, pBranchRight.y - pB2Top.y);
    final lenB2 = math.sqrt(vB2.x * vB2.x + vB2.y * vB2.y);
    final u2 = CadPoint2D(vB2.x / lenB2, vB2.y / lenB2);
    final theta2 = math.atan2(vB2.y, -vB2.x);

    final includeFlaps = params.includeCouplerFlaps;
    final lf = params.couplerFlapLength;

    final List<CadPoint2D> effectiveOuterContour;
    final List<FoldBendLine> effectiveBends;
    final List<PlanarSheetFace> effectiveFaces;

    if (includeFlaps) {
      // 1. Flap Faces
      final fFlap1P1 = PlanarSheetFace(
        id: 'F_FLAP_1_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pB1Top,
          top: fl2P1,
          uDir: CadPoint2D(-u1.x, -u1.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P1',
      );

      final fFlap1P3 = PlanarSheetFace(
        id: 'F_FLAP_1_P3',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pBranchLeft,
          top: fl2P2,
          uDir: u1,
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P3',
      );

      final fFlap3P2 = PlanarSheetFace(
        id: 'F_FLAP_3_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pB2Top,
          top: fl3P2,
          uDir: CadPoint2D(-u2.x, -u2.y),
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P2',
      );

      final fFlap3P3 = PlanarSheetFace(
        id: 'F_FLAP_3_P3',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pBranchRight,
          top: fl3P1,
          uDir: u2,
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P3',
      );

      final fFlap6P1 = PlanarSheetFace(
        id: 'F_FLAP_6_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: b3P1,
          top: fl1P2,
          uDir: const CadPoint2D(-1.0, 0.0),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P1',
      );

      final fFlap6P2 = PlanarSheetFace(
        id: 'F_FLAP_6_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: b3P2,
          top: fl1P1,
          uDir: const CadPoint2D(1.0, 0.0),
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P2',
      );

      effectiveFaces = [...newFaces, fFlap1P1, fFlap1P3, fFlap3P2, fFlap3P3, fFlap6P1, fFlap6P2];

      // 2. Flap Bends with scalable bending angles realigning parallel to straight length
      final bf1P1 = FoldBendLine(
        id: 'BF_1_P1',
        p1: pB1Top,
        p2: fl2P1,
        targetAngleDeg: theta1 * 180.0 / math.pi,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P1',
        direction: BendDirection.down,
      );

      final bf1P3 = FoldBendLine(
        id: 'BF_1_P3',
        p1: pBranchLeft,
        p2: fl2P2,
        targetAngleDeg: 90.0 - (theta1 * 180.0 / math.pi),
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P3',
        direction: BendDirection.down,
      );

      final bf3P2 = FoldBendLine(
        id: 'BF_3_P2',
        p1: pB2Top,
        p2: fl3P2,
        targetAngleDeg: theta2 * 180.0 / math.pi,
        role: BendLineRole.bend,
        parentFaceId: 'F_3',
        childFaceId: 'F_FLAP_3_P2',
        direction: BendDirection.down,
      );

      final bf3P3 = FoldBendLine(
        id: 'BF_3_P3',
        p1: pBranchRight,
        p2: fl3P1,
        targetAngleDeg: 90.0 - (theta2 * 180.0 / math.pi),
        role: BendLineRole.bend,
        parentFaceId: 'F_3',
        childFaceId: 'F_FLAP_3_P3',
        direction: BendDirection.down,
      );

      final bf6P1 = FoldBendLine(
        id: 'BF_6_P1',
        p1: b3P1,
        p2: fl1P2,
        targetAngleDeg: 0.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_6',
        childFaceId: 'F_FLAP_6_P1',
        direction: BendDirection.up,
      );

      final bf6P2 = FoldBendLine(
        id: 'BF_6_P2',
        p1: b3P2,
        p2: fl1P1,
        targetAngleDeg: 0.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_6',
        childFaceId: 'F_FLAP_6_P2',
        direction: BendDirection.up,
      );

      effectiveBends = [...newBends, bf1P1, bf1P3, bf3P2, bf3P3, bf6P1, bf6P2];

      // 3. Perimeter Contour with Flaps
      effectiveOuterContour = [
        pBranchRight,
        CadPoint2D(pBranchRight.x + lf * u2.x, pBranchRight.y + lf * u2.y),
        CadPoint2D(fl3P1.x + lf * u2.x, fl3P1.y + lf * u2.y),
        fl3P1,
        v1,
        v2,
        fl3P2,
        CadPoint2D(fl3P2.x - lf * u2.x, fl3P2.y - lf * u2.y),
        CadPoint2D(pB2Top.x - lf * u2.x, pB2Top.y - lf * u2.y),
        pB2Top,
        b3P2,
        CadPoint2D(b3P2.x + lf, b3P2.y),
        CadPoint2D(fl1P1.x + lf, fl1P1.y),
        fl1P1,
        v4,
        v5,
        fl1P2,
        CadPoint2D(fl1P2.x - lf, fl1P2.y),
        CadPoint2D(b3P1.x - lf, b3P1.y),
        b3P1,
        pB1Top,
        CadPoint2D(pB1Top.x - lf * u1.x, pB1Top.y - lf * u1.y),
        CadPoint2D(fl2P1.x - lf * u1.x, fl2P1.y - lf * u1.y),
        fl2P1,
        v7,
        v8,
        fl2P2,
        CadPoint2D(fl2P2.x + lf * u1.x, fl2P2.y + lf * u1.y),
        CadPoint2D(pBranchLeft.x + lf * u1.x, pBranchLeft.y + lf * u1.y),
        pBranchLeft,
        pBranchRight,
      ];
    } else {
      effectiveFaces = newFaces;
      effectiveBends = newBends;
      effectiveOuterContour = newOuterContour;
    }

    // Generate Punches with independent heights, central floor perforations & coupler flaps
    final newPunches = _generatePunches(
      baseline: baseline,
      w1: w1,
      w2: w2,
      w3: w3,
      h1: h1,
      h2: h2,
      h3: h3,
      span1: span1,
      span2: span2,
      b3P1: b3P1,
      b3P2: b3P2,
      pB1Top: pB1Top,
      pB2Top: pB2Top,
      pBranchLeft: pBranchLeft,
      pBranchRight: pBranchRight,
      yTop: yTop,
      fl2P1: fl2P1,
      fl2P2: fl2P2,
      fl3P1: fl3P1,
      fl3P2: fl3P2,
      fl1P1: fl1P1,
      fl1P2: fl1P2,
      u1: u1,
      u2: u2,
      perforationPitch: params.perforationPitch,
      includeCouplerFlaps: params.includeCouplerFlaps,
      couplerFlapLength: params.couplerFlapLength,
    );

    // Update metadata parameters
    final newParams = Map<String, double>.from(baseline.parameters);
    newParams['width'] = w1;
    newParams['height'] = h1;
    newParams['radius'] = r;
    newParams['port1_width'] = w1;
    newParams['port1_height'] = h1;
    newParams['port2_width'] = w2;
    newParams['port2_height'] = h2;
    newParams['port3_width'] = w3;
    newParams['port3_height'] = h3;

    return baseline.copyWith(
      outerContour: effectiveOuterContour,
      bends: effectiveBends,
      faces: effectiveFaces,
      punches: newPunches,
      parameters: newParams,
    );
  }

  /// Generates the standard coupler hole heights centered symmetrically on edge height [h].
  /// For any edge height h:
  /// - h=50: [25.0] (1 row, centered)
  /// - h=100: [25.0, 75.0] (2 rows, 50mm pitch, centered)
  /// - h=150: [25.0, 75.0, 125.0] (3 rows, 50mm pitch, centered)
  /// - h=200: [25.0, 75.0, 125.0, 175.0] (4 rows, 50mm pitch, centered)
  /// - h=250: [25.0, 75.0, 125.0, 175.0, 225.0] (5 rows, 50mm pitch, centered)
  static List<double> _couplerHeightsForEdge(double h) {
    final n = math.max(1, (h / 50.0).round());
    if (n == 1) {
      return [h / 2.0];
    }
    final start = (h - (n - 1) * 50.0) / 2.0;
    return List.generate(n, (k) => start + k * 50.0);
  }

  /// Synthesizes coupler holes and floor web perforations per standard tray principles.
  static List<CncPunchPrimitive> _generatePunches({
    required DsfDocument baseline,
    required double w1,
    required double w2,
    required double w3,
    required double h1,
    required double h2,
    required double h3,
    required double span1,
    required double span2,
    required CadPoint2D b3P1,
    required CadPoint2D b3P2,
    required CadPoint2D pB1Top,
    required CadPoint2D pB2Top,
    required CadPoint2D pBranchLeft,
    required CadPoint2D pBranchRight,
    required double yTop,
    required CadPoint2D fl2P1,
    required CadPoint2D fl2P2,
    required CadPoint2D fl3P1,
    required CadPoint2D fl3P2,
    required CadPoint2D fl1P1,
    required CadPoint2D fl1P2,
    required CadPoint2D u1,
    required CadPoint2D u2,
    double perforationPitch = 100.0,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 90.0,
  }) {
    final punches = <CncPunchPrimitive>[];
    final sampleSlot = baseline.punches.firstWhere(
      (p) => p.isSlot || p.type == PunchType.obroundSlot,
      orElse: () => baseline.punches.first,
    );

    int idCounter = 1;
    String nextSlotId() => 'SLOT_${idCounter++}';

    const invSqrt2 = 0.7071067811865475;
    const uWing1 = CadPoint2D(invSqrt2, invSqrt2);
    const nWing1 = CadPoint2D(-invSqrt2, invSqrt2);

    const uWing2 = CadPoint2D(-invSqrt2, invSqrt2);
    const nWing2 = CadPoint2D(invSqrt2, invSqrt2);

    // Dynamic normals for cheeks
    final n1 = CadPoint2D(-u1.y, u1.x);
    final n2 = CadPoint2D(u2.y, -u2.x);

    // --- A. Left 45° Wall Couplers (F_1) ---
    // Slants from h1 at Port 1 (u=0) to h3 at Port 3 (u=wallLen1)
    final wallLen1 = span1 * math.sqrt(2);
    final vHeightsP1 = _couplerHeightsForEdge(h1);
    for (final u in [26.0, 76.0]) {
      final hU = h1 + (h3 - h1) * (u / wallLen1);
      for (final v in vHeightsP1) {
        // Intelligent placement: must clear bottom bend (>=10mm) and top flange bend line (<= hU - 15mm)
        if (v >= 10.0 && v <= hU - 15.0) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(
                pB1Top.x + u * uWing1.x + v * nWing1.x,
                pB1Top.y + u * uWing1.y + v * nWing1.y,
              ),
              role: CncPunchRole.coupler,
              rotationDeg: 135.0,
            ),
          );
        }
      }
    }

    final vHeightsP3 = _couplerHeightsForEdge(h3);
    for (final u in [wallLen1 - 76.0, wallLen1 - 26.0]) {
      final hU = h1 + (h3 - h1) * (u / wallLen1);
      for (final v in vHeightsP3) {
        if (v >= 10.0 && v <= hU - 15.0) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(
                pB1Top.x + u * uWing1.x + v * nWing1.x,
                pB1Top.y + u * uWing1.y + v * nWing1.y,
              ),
              role: CncPunchRole.coupler,
              rotationDeg: 135.0,
            ),
          );
        }
      }
    }

    // --- B. Right 45° Wall Couplers (F_3) ---
    // Slants from h2 at Port 2 (u=0) to h3 at Port 3 (u=wallLen2)
    final wallLen2 = span2 * math.sqrt(2);
    final vHeightsP2 = _couplerHeightsForEdge(h2);
    for (final u in [26.0, 76.0]) {
      final hU = h2 + (h3 - h2) * (u / wallLen2);
      for (final v in vHeightsP2) {
        if (v >= 10.0 && v <= hU - 15.0) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(
                pB2Top.x + u * uWing2.x + v * nWing2.x,
                pB2Top.y + u * uWing2.y + v * nWing2.y,
              ),
              role: CncPunchRole.coupler,
              rotationDeg: 45.0,
            ),
          );
        }
      }
    }

    final vHeights2P3 = _couplerHeightsForEdge(h3);
    for (final u in [wallLen2 - 76.0, wallLen2 - 26.0]) {
      final hU = h2 + (h3 - h2) * (u / wallLen2);
      for (final v in vHeights2P3) {
        if (v >= 10.0 && v <= hU - 15.0) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(
                pB2Top.x + u * uWing2.x + v * nWing2.x,
                pB2Top.y + u * uWing2.y + v * nWing2.y,
              ),
              role: CncPunchRole.coupler,
              rotationDeg: 45.0,
            ),
          );
        }
      }
    }

    // --- C. Top Back Wall Couplers (F_6) ---
    // Slants from h1 at Port 1 (x=b3P1.x) to h2 at Port 2 (x=b3P2.x)
    final isBaseH = (h1 - 50.0).abs() < 1.0 && (h2 - 50.0).abs() < 1.0;
    final topWallSpan = b3P2.x - b3P1.x;

    // Near Port 1 (height h1)
    for (final x in [b3P1.x + 20.0, b3P1.x + 70.0]) {
      final hX = h1 + (h2 - h1) * ((x - b3P1.x) / topWallSpan);
      final yOffsetsTopP1 = isBaseH ? [yTop - 12.27, yTop - 37.27] : _couplerHeightsForEdge(h1).map((v) => yTop - v).toList();
      for (final y in yOffsetsTopP1) {
        final v = yTop - y;
        if (isBaseH || (v >= 10.0 && v <= hX - 15.0)) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(x, y),
              role: CncPunchRole.coupler,
              rotationDeg: 0.0,
            ),
          );
        }
      }
    }

    // Near Port 2 (height h2)
    for (final x in [b3P2.x - 70.0, b3P2.x - 20.0]) {
      final hX = h1 + (h2 - h1) * ((x - b3P1.x) / topWallSpan);
      final yOffsetsTopP2 = isBaseH ? [yTop - 12.27, yTop - 37.27] : _couplerHeightsForEdge(h2).map((v) => yTop - v).toList();
      for (final y in yOffsetsTopP2) {
        final v = yTop - y;
        if (isBaseH || (v >= 10.0 && v <= hX - 15.0)) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(x, y),
              role: CncPunchRole.coupler,
              rotationDeg: 0.0,
            ),
          );
        }
      }
    }

    // --- D. Floor Web Perforations (F_5) ---
    // Port 1 (Left mouth) slots: vertical column at x = pB1Top.x + 20.0
    final numP1Slots = math.max(2, (w1 / 50.0).round());
    for (int i = 0; i < numP1Slots; i++) {
      final y = yTop + 25.23 + i * 50.0;
      punches.add(
        sampleSlot.copyWith(
          id: nextSlotId(),
          center: CadPoint2D(pB1Top.x + 20.0, y),
          role: CncPunchRole.perforation,
          rotationDeg: 0.0,
        ),
      );
    }

    // Port 2 (Right mouth) slots: vertical column at x = pB2Top.x - 20.0
    final numP2Slots = math.max(2, (w2 / 50.0).round());
    for (int i = 0; i < numP2Slots; i++) {
      final y = yTop + 25.23 + i * 50.0;
      punches.add(
        sampleSlot.copyWith(
          id: nextSlotId(),
          center: CadPoint2D(pB2Top.x - 20.0, y),
          role: CncPunchRole.perforation,
          rotationDeg: 0.0,
        ),
      );
    }

    // Port 3 (Bottom branch) slots: horizontal row at y = yBranchBase - 20.0, vertical slots
    final numP3Slots = math.max(1, (w3 / 50.0).round());
    if (numP3Slots == 1) {
      punches.add(
        sampleSlot.copyWith(
          id: nextSlotId(),
          center: CadPoint2D(xBranchMidBase, yBranchBase - 20.0),
          role: CncPunchRole.perforation,
          rotationDeg: 90.0,
        ),
      );
    } else {
      for (int i = 0; i < numP3Slots; i++) {
        final x = pBranchLeft.x + 25.0 + i * 50.0;
        punches.add(
          sampleSlot.copyWith(
            id: nextSlotId(),
            center: CadPoint2D(x, yBranchBase - 20.0),
            role: CncPunchRole.perforation,
            rotationDeg: 90.0,
          ),
        );
      }
    }

    // Central Floor slots: adjustable pitch pattern (Sparse 150mm, Standard 100mm, Dense 75mm)
    final centralCols = <double>[xBranchMidBase];
    final maxHalfCols = (((b3P2.x - b3P1.x) / 2.0) / perforationPitch).floor();
    for (int c = 1; c <= maxHalfCols; c++) {
      for (final sign in [-1.0, 1.0]) {
        final x = xBranchMidBase + sign * c * perforationPitch;
        // Require at least 85mm clearance from mouth edge slots
        if (x >= b3P1.x + 85.0 && x <= b3P2.x - 85.0) {
          centralCols.add(x);
        }
      }
    }
    centralCols.sort();

    int rowIdx = 0;
    while (true) {
      final y = yTop + 30.83 + rowIdx * perforationPitch;
      if (y > yBranchBase - 55.0) break;

      for (final x in centralCols) {
        // Clearance to 45° miter bend B1
        final distB1 = (yBranchBase - y) - (pBranchLeft.x - x);
        // Clearance to 45° miter bend B2
        final distB2 = (yBranchBase - y) - (x - pBranchRight.x);

        if (distB1 >= 32.0 && distB2 >= 32.0) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(x, y),
              role: CncPunchRole.perforation,
              rotationDeg: 0.0,
            ),
          );
        }
      }
      rowIdx++;
    }

    // --- E. Coupler Flap Slots ---
    if (includeCouplerFlaps) {
      // Body coupler holes on the side walls are made invisible so they do not overlap
      // with the coupler flap connecting holes. They remain in the document and become
      // visible again if coupler flaps are toggled off.
      for (int i = 0; i < punches.length; i++) {
        if (punches[i].role == CncPunchRole.coupler) {
          punches[i] = punches[i].copyWith(isVisible: false);
        }
      }

      void addFlapPunches({
        required CadPoint2D origin,
        required CadPoint2D uDir,
        required CadPoint2D vDir,
        required double rotDeg,
        required double hPort,
      }) {
        final slotLen = math.max(10.0, hPort - 20.0);
        const slotWid = 8.0;
        const slotPitch = 25.0;

        final uCenter = couplerFlapLength / 2.0;
        final uOffsets = [uCenter - slotPitch, uCenter, uCenter + slotPitch];
        final v = hPort / 2.0;
        if (couplerFlapLength < 20.0) return;
        for (final u in uOffsets) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(
                origin.x + u * uDir.x + v * vDir.x,
                origin.y + u * uDir.y + v * vDir.y,
              ),
              lengthMm: slotLen,
              widthMm: slotWid,
              role: CncPunchRole.coupler,
              rotationDeg: rotDeg,
              isVisible: true,
            ),
          );
        }
      }

      final rotCheek1 = ((math.atan2(n1.y, n1.x) * 180.0 / math.pi) % 180.0 + 180.0) % 180.0;
      final rotCheek2 = ((math.atan2(n2.y, n2.x) * 180.0 / math.pi) % 180.0 + 180.0) % 180.0;

      // Cheek 1 Flaps (Port 1 and Port 3)
      addFlapPunches(
        origin: pB1Top,
        uDir: CadPoint2D(-u1.x, -u1.y),
        vDir: n1,
        rotDeg: rotCheek1,
        hPort: h1,
      );
      addFlapPunches(
        origin: pBranchLeft,
        uDir: u1,
        vDir: n1,
        rotDeg: rotCheek1,
        hPort: h3,
      );

      // Cheek 3 Flaps (Port 2 and Port 3)
      addFlapPunches(
        origin: pB2Top,
        uDir: CadPoint2D(-u2.x, -u2.y),
        vDir: n2,
        rotDeg: rotCheek2,
        hPort: h2,
      );
      addFlapPunches(
        origin: pBranchRight,
        uDir: u2,
        vDir: n2,
        rotDeg: rotCheek2,
        hPort: h3,
      );

      // Back Wall Flaps (Port 1 and Port 2)
      addFlapPunches(
        origin: b3P1,
        uDir: const CadPoint2D(-1.0, 0.0),
        vDir: const CadPoint2D(0.0, -1.0),
        rotDeg: 90.0,
        hPort: h1,
      );
      addFlapPunches(
        origin: b3P2,
        uDir: const CadPoint2D(1.0, 0.0),
        vDir: const CadPoint2D(0.0, -1.0),
        rotDeg: 90.0,
        hPort: h2,
      );
    }

    return punches;
  }
}
