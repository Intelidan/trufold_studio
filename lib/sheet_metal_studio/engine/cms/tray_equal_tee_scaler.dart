// =============================================================================
// tray_equal_tee_scaler.dart
//
// Dedicated Parametric Analytical Scaling Engine for Cable Tray Equal Tees.
//
// Architectural Principles:
// 1. Equal Scaling on all 3 ports: Top (Port 2), Left (Port 1), and Right (Port 3).
// 2. Height Invariance on Floor Web: Central floor web between B1, B2, B3 and
//    the 3 ports remains stationary during height scaling; only the 3 sidewalls
//    (Left 45° wall, Right 45° wall, Bottom back wall) expand perpendicularly outward.
// 3. Radius Scaling: Miter span expands proportionally with bend radius R.
// 4. Universal 95mm Coupler Rule:
//    - Height < 95mm: 1 row of coupler slots centered across 45° sidewalls.
//    - Height >= 95mm: 2 rows of coupler slots (50mm vertical pitch).
// 5. Port Opening Rectitude: Port mouths remain strictly perpendicular to
//    channel channels, never deflected by cheek punch averages.
// =============================================================================

import 'dart:math' as math;

import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';
import 'tray_bend_geometry_solver.dart';

class TrayEqualTeeScaleParameters {
  final double targetWidth;
  final double targetHeight;
  final double targetRadius;
  final double baselineWidth;
  final double baselineHeight;
  final double baselineRadius;
  final bool includeCouplerFlaps;
  final double couplerFlapLength;
  final double perforationPitch;

  double get dW => targetWidth - baselineWidth;
  double get dH => targetHeight - baselineHeight;
  double get dR => targetRadius - baselineRadius;

  bool get hasAnyChange =>
      (dW).abs() > 1e-4 ||
      (dH).abs() > 1e-4 ||
      (dR).abs() > 1e-4 ||
      includeCouplerFlaps ||
      (couplerFlapLength - 30.0).abs() > 1e-4 ||
      (perforationPitch - 100.0).abs() > 1e-4;

  const TrayEqualTeeScaleParameters({
    required this.targetWidth,
    required this.targetHeight,
    this.targetRadius = 180.0,
    this.baselineWidth = 100.0,
    this.baselineHeight = 50.0,
    this.baselineRadius = 180.0,
    this.includeCouplerFlaps = false,
    this.couplerFlapLength = 30.0,
    this.perforationPitch = 100.0,
  });
}

class TrayEqualTeeScaler {
  // Baseline geometric constants from assets/dsf_templates/tray_accessories/equal_tee_100x50.dsf
  static const double xMidBase = 237.42007201418437;
  static const double yTopBase = 44.547727214752896;
  static const double spanBase = 142.8723447994321;
  static const double hWall45Base = 50.00;
  static const double wFlange45Base = 13.00;
  static const double sideMouthLenBase = 99.79269208650803;
  static const double hWallBotBase = 50.20730791349167;
  static const double wFlangeBotBase = 13.00;

  /// Determines whether [doc] is a Cable Tray Equal Tee.
  static bool isTrayEqualTee(DsfDocument doc) {
    final name = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (name.contains('trunking')) return false;
    final isTee = name.contains('tee');
    final isUnequal = name.contains('unequal');
    if (!isTee || isUnequal) return false;

    // Check for 6 bends (B1, B2, B3, FL1, FL2, FL3) and no ear bends (B4..B7)
    final has6Bends = doc.bends.length == 6;
    final hasNoEarBends = !doc.bends.any((b) => b.id == 'B4' || b.id == 'B5' || b.id == 'B6' || b.id == 'B7');
    final has45Bend = doc.bends.any((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && ((b.p2.x - b.p1.x).abs() - (b.p2.y - b.p1.y).abs()).abs() < 2.0);

    return (isTee && !isUnequal && has6Bends && hasNoEarBends && has45Bend);
  }

  /// Scales [baseline] to [targetWidth], [targetHeight], and optional [targetRadius].
  static DsfDocument scale({
    required DsfDocument baseline,
    required double targetWidth,
    required double targetHeight,
    double targetRadius = 180.0,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 30.0,
    double perforationPitch = 100.0,
  }) {
    final params = TrayEqualTeeScaleParameters(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      targetRadius: targetRadius,
      baselineWidth: 100.0,
      baselineHeight: 50.0,
      baselineRadius: 180.0,
      includeCouplerFlaps: includeCouplerFlaps,
      couplerFlapLength: couplerFlapLength,
      perforationPitch: perforationPitch,
    );

    return scaleWithParameters(baseline, params);
  }

  static DsfDocument scaleWithParameters(DsfDocument baseline, TrayEqualTeeScaleParameters params) {
    if (!params.hasAnyChange) return baseline;

    final W = params.targetWidth;
    final H = params.targetHeight;
    final R = params.targetRadius;

    final dH = params.dH;
    final dR = params.dR;

    // Radius scaling adjusts the miter span
    final span = spanBase + dR * math.tan(22.5 * math.pi / 180.0);

    final xMid = xMidBase;
    final yTop = yTopBase;

    // 1. Floor Terminal Coordinates
    final pTopLeft = CadPoint2D(xMid - W / 2.0, yTop);
    final pTopRight = CadPoint2D(xMid + W / 2.0, yTop);

    final pB1Top = pTopLeft;
    final pB1Bot = CadPoint2D(pTopLeft.x - span, pTopLeft.y + span);

    final pB2Top = pTopRight;
    final pB2Bot = CadPoint2D(pTopRight.x + span, pTopRight.y + span);

    final sideMouthLen = sideMouthLenBase + (W - 100.0);
    final pLeftBottom = CadPoint2D(pB1Bot.x, pB1Bot.y + sideMouthLen);
    final pRightBottom = CadPoint2D(pB2Bot.x, pB2Bot.y + sideMouthLen);

    final b3Y = pLeftBottom.y;

    // 2. Wall Dimensions (Normal Outward Expansions)
    final hWall45 = hWall45Base + dH;
    const wFlange45 = wFlange45Base;
    final tot45 = hWall45 + wFlange45;

    final shift45X = -tot45 / math.sqrt(2);
    final shift45Y = -tot45 / math.sqrt(2);
    final fl45ShiftX = -hWall45 / math.sqrt(2);
    final fl45ShiftY = -hWall45 / math.sqrt(2);

    final shiftRight45X = tot45 / math.sqrt(2);
    final shiftRight45Y = -tot45 / math.sqrt(2);
    final flRight45ShiftX = hWall45 / math.sqrt(2);
    final flRight45ShiftY = -hWall45 / math.sqrt(2);

    final hWallBot = hWallBotBase + dH;
    const wFlangeBot = wFlangeBotBase;
    final totBot = hWallBot + wFlangeBot;

    // 3. Outer Contour Vertices (v0 to v9)
    final v0 = pTopLeft;
    final v1 = CadPoint2D(pB1Top.x + shift45X, pB1Top.y + shift45Y);
    final v2 = CadPoint2D(pB1Bot.x + shift45X, pB1Bot.y + shift45Y);
    final v3 = pB1Bot;
    final v4 = CadPoint2D(pLeftBottom.x, b3Y + totBot);
    final v5 = CadPoint2D(pRightBottom.x, b3Y + totBot);
    final v6 = pB2Bot;
    final v7 = CadPoint2D(pB2Bot.x + shiftRight45X, pB2Bot.y + shiftRight45Y);
    final v8 = CadPoint2D(pB2Top.x + shiftRight45X, pB2Top.y + shiftRight45Y);
    final v9 = pTopRight;

    final newOuterContour = [v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v0];

    // 4. Bends
    final b1 = FoldBendLine(id: 'B1', p1: pB1Top, p2: pB1Bot, targetAngleDeg: 90.0, role: BendLineRole.bend, parentFaceId: 'F_5', childFaceId: 'F_1');
    final b2 = FoldBendLine(id: 'B2', p1: pB2Bot, p2: pB2Top, targetAngleDeg: 90.0, role: BendLineRole.bend, parentFaceId: 'F_5', childFaceId: 'F_3');
    final b3 = FoldBendLine(
      id: 'B3',
      p1: pLeftBottom,
      p2: pRightBottom,
      targetAngleDeg: 90.0,
      role: BendLineRole.bend,
      parentFaceId: 'F_5',
      childFaceId: 'F_6',
    );

    final fl1 = FoldBendLine(
      id: 'FL1',
      p1: CadPoint2D(pB2Bot.x + flRight45ShiftX, pB2Bot.y + flRight45ShiftY),
      p2: CadPoint2D(pB2Top.x + flRight45ShiftX, pB2Top.y + flRight45ShiftY),
      targetAngleDeg: 135.0,
      role: BendLineRole.flange,
      parentFaceId: 'F_3',
      childFaceId: 'F_2',
    );
    final fl2 = FoldBendLine(
      id: 'FL2',
      p1: CadPoint2D(pB1Top.x + fl45ShiftX, pB1Top.y + fl45ShiftY),
      p2: CadPoint2D(pB1Bot.x + fl45ShiftX, pB1Bot.y + fl45ShiftY),
      targetAngleDeg: 135.0,
      role: BendLineRole.flange,
      parentFaceId: 'F_1',
      childFaceId: 'F_0',
    );
    final fl3 = FoldBendLine(
      id: 'FL3',
      p1: CadPoint2D(pLeftBottom.x, b3Y + hWallBot),
      p2: CadPoint2D(pRightBottom.x, b3Y + hWallBot),
      targetAngleDeg: 135.0,
      role: BendLineRole.flange,
      parentFaceId: 'F_6',
      childFaceId: 'F_4',
    );

    final newBends = [b1, b2, b3, fl1, fl2, fl3];

    // 5. Planar Faces
    final f5 = PlanarSheetFace(id: 'F_5', role: FaceRole.baseFloor, vertices: [pLeftBottom, pB1Bot, pB1Top, pB2Top, pB2Bot, pRightBottom], isBaseAnchor: true);
    final f1 = PlanarSheetFace(id: 'F_1', role: FaceRole.sideWall, vertices: [pB1Top, fl2.p1, fl2.p2, pB1Bot]);
    final f0 = PlanarSheetFace(id: 'F_0', role: FaceRole.returnFlange, vertices: [fl2.p1, v1, v2, fl2.p2]);
    final f3 = PlanarSheetFace(id: 'F_3', role: FaceRole.sideWall, vertices: [pB2Bot, fl1.p1, fl1.p2, pB2Top]);
    final f2 = PlanarSheetFace(id: 'F_2', role: FaceRole.returnFlange, vertices: [fl1.p1, v7, v8, fl1.p2]);
    final f6 = PlanarSheetFace(id: 'F_6', role: FaceRole.sideWall, vertices: [pRightBottom, fl3.p2, fl3.p1, pLeftBottom]);
    final f4 = PlanarSheetFace(id: 'F_4', role: FaceRole.returnFlange, vertices: [fl3.p2, v5, v4, fl3.p1]);

    final newFaces = [f0, f1, f2, f3, f4, f5, f6];

    final includeFlaps = params.includeCouplerFlaps;
    final lf = params.couplerFlapLength;

    const uWing1 = CadPoint2D(-0.7071067811865475, 0.7071067811865475);
    const uWing2 = CadPoint2D(0.7071067811865475, 0.7071067811865475);

    final List<CadPoint2D> effectiveOuterContour;
    final List<FoldBendLine> effectiveBends;
    final List<PlanarSheetFace> effectiveFaces;

    if (includeFlaps) {
      final fFlap1P1 = PlanarSheetFace(
        id: 'F_FLAP_1_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pB1Bot,
          top: fl2.p2,
          uDir: uWing1,
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P1',
      );

      final fFlap1P2 = PlanarSheetFace(
        id: 'F_FLAP_1_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pB1Top,
          top: fl2.p1,
          uDir: CadPoint2D(-uWing1.x, -uWing1.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P2',
      );

      final fFlap3P2 = PlanarSheetFace(
        id: 'F_FLAP_3_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pB2Top,
          top: fl1.p2,
          uDir: CadPoint2D(-uWing2.x, -uWing2.y),
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P2',
      );

      final fFlap3P3 = PlanarSheetFace(
        id: 'F_FLAP_3_P3',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pB2Bot,
          top: fl1.p1,
          uDir: uWing2,
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P3',
      );

      final fFlap6P1 = PlanarSheetFace(
        id: 'F_FLAP_6_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pLeftBottom,
          top: fl3.p1,
          uDir: const CadPoint2D(-1.0, 0.0),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P1',
      );

      final fFlap6P3 = PlanarSheetFace(
        id: 'F_FLAP_6_P3',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pRightBottom,
          top: fl3.p2,
          uDir: const CadPoint2D(1.0, 0.0),
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P3',
      );

      effectiveFaces = [...newFaces, fFlap1P1, fFlap1P2, fFlap3P2, fFlap3P3, fFlap6P1, fFlap6P3];

      // Flap Bends with BendDirection.down so they bend outward parallel to the straight tray runs
      final bf1P1 = FoldBendLine(
        id: 'BF_1_P1',
        p1: pB1Bot,
        p2: fl2.p2,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P1',
        direction: BendDirection.down,
      );

      final bf1P2 = FoldBendLine(
        id: 'BF_1_P2',
        p1: pB1Top,
        p2: fl2.p1,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P2',
        direction: BendDirection.down,
      );

      final bf3P2 = FoldBendLine(
        id: 'BF_3_P2',
        p1: pB2Top,
        p2: fl1.p2,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_3',
        childFaceId: 'F_FLAP_3_P2',
        direction: BendDirection.down,
      );

      final bf3P3 = FoldBendLine(
        id: 'BF_3_P3',
        p1: pB2Bot,
        p2: fl1.p1,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_3',
        childFaceId: 'F_FLAP_3_P3',
        direction: BendDirection.down,
      );

      final bf6P1 = FoldBendLine(
        id: 'BF_6_P1',
        p1: pLeftBottom,
        p2: fl3.p1,
        targetAngleDeg: 0.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_6',
        childFaceId: 'F_FLAP_6_P1',
        direction: BendDirection.down,
      );

      final bf6P3 = FoldBendLine(
        id: 'BF_6_P3',
        p1: pRightBottom,
        p2: fl3.p2,
        targetAngleDeg: 0.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_6',
        childFaceId: 'F_FLAP_6_P3',
        direction: BendDirection.down,
      );

      effectiveBends = [...newBends, bf1P1, bf1P2, bf3P2, bf3P3, bf6P1, bf6P3];

      effectiveOuterContour = [
        pTopLeft,
        CadPoint2D(pB1Top.x - lf * uWing1.x, pB1Top.y - lf * uWing1.y),
        CadPoint2D(fl2.p1.x - lf * uWing1.x, fl2.p1.y - lf * uWing1.y),
        fl2.p1,
        v1,
        v2,
        fl2.p2,
        CadPoint2D(fl2.p2.x + lf * uWing1.x, fl2.p2.y + lf * uWing1.y),
        CadPoint2D(pB1Bot.x + lf * uWing1.x, pB1Bot.y + lf * uWing1.y),
        pB1Bot,
        pLeftBottom,
        CadPoint2D(pLeftBottom.x - lf, pLeftBottom.y),
        CadPoint2D(fl3.p1.x - lf, fl3.p1.y),
        fl3.p1,
        v4,
        v5,
        fl3.p2,
        CadPoint2D(fl3.p2.x + lf, fl3.p2.y),
        CadPoint2D(pRightBottom.x + lf, pRightBottom.y),
        pRightBottom,
        pB2Bot,
        CadPoint2D(pB2Bot.x + lf * uWing2.x, pB2Bot.y + lf * uWing2.y),
        CadPoint2D(fl1.p1.x + lf * uWing2.x, fl1.p1.y + lf * uWing2.y),
        fl1.p1,
        v7,
        v8,
        fl1.p2,
        CadPoint2D(fl1.p2.x - lf * uWing2.x, fl1.p2.y - lf * uWing2.y),
        CadPoint2D(pB2Top.x - lf * uWing2.x, pB2Top.y - lf * uWing2.y),
        pB2Top,
        pTopRight,
        pTopLeft,
      ];
    } else {
      effectiveFaces = newFaces;
      effectiveBends = newBends;
      effectiveOuterContour = newOuterContour;
    }

    // 6. Punches Generation per Universal 95mm Rule
    final newPunches = _generatePunches(
      baseline: baseline,
      W: W,
      H: H,
      span: span,
      pTopLeft: pTopLeft,
      pTopRight: pTopRight,
      pB1Top: pB1Top,
      pB1Bot: pB1Bot,
      pB2Top: pB2Top,
      pB2Bot: pB2Bot,
      pLeftBottom: pLeftBottom,
      pRightBottom: pRightBottom,
      b3Y: b3Y,
      includeCouplerFlaps: includeFlaps,
      couplerFlapLength: lf,
      perforationPitch: params.perforationPitch,
    );

    // 7. Update Parameters and Ports Metadata
    final newParams = Map<String, double>.from(baseline.parameters);
    newParams['width'] = W;
    newParams['height'] = H;
    newParams['radius'] = R;
    newParams['port1_width'] = W;
    newParams['port1_height'] = H;
    newParams['port2_width'] = W;
    newParams['port2_height'] = H;
    newParams['port3_width'] = W;
    newParams['port3_height'] = H;

    return baseline.copyWith(outerContour: effectiveOuterContour, bends: effectiveBends, faces: effectiveFaces, punches: newPunches, parameters: newParams);
  }

  static List<CncPunchPrimitive> _generatePunches({
    required DsfDocument baseline,
    required double W,
    required double H,
    required double span,
    required CadPoint2D pTopLeft,
    required CadPoint2D pTopRight,
    required CadPoint2D pB1Top,
    required CadPoint2D pB1Bot,
    required CadPoint2D pB2Top,
    required CadPoint2D pB2Bot,
    required CadPoint2D pLeftBottom,
    required CadPoint2D pRightBottom,
    required double b3Y,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 30.0,
    double perforationPitch = 100.0,
  }) {
    final punches = <CncPunchPrimitive>[];
    final sampleSlot = baseline.punches.firstWhere((p) => p.isSlot || p.type == PunchType.obroundSlot, orElse: () => baseline.punches.first);

    int idCounter = 1;
    String nextSlotId() => 'SLOT_${idCounter++}';

    final heightRows = H >= 95.0 ? 2 : 1;
    final wallLen45 = span * math.sqrt(2);

    // --- A. Left 45° Wall Couplers (F_1) ---
    // Runs from pB1Top along (-1/sqrt(2), 1/sqrt(2)), normal outward (-1/sqrt(2), -1/sqrt(2))
    const uWing1 = CadPoint2D(-0.7071067811865475, 0.7071067811865475);
    const nWing1 = CadPoint2D(-0.7071067811865475, -0.7071067811865475);

    final uOffsets45 = [25.0, 75.0, wallLen45 - 75.0, wallLen45 - 25.0];
    final vOffsets45 = heightRows == 1 ? [H / 2.0] : [H / 2.0 - 25.0, H / 2.0 + 25.0];

    for (final v in vOffsets45) {
      for (final u in uOffsets45) {
        punches.add(
          sampleSlot.copyWith(
            id: nextSlotId(),
            center: CadPoint2D(pB1Top.x + u * uWing1.x + v * nWing1.x, pB1Top.y + u * uWing1.y + v * nWing1.y),
            role: CncPunchRole.coupler,
            rotationDeg: 45.0,
          ),
        );
      }
    }

    // --- B. Right 45° Wall Couplers (F_3) ---
    // Runs from pB2Top along (1/sqrt(2), 1/sqrt(2)), normal outward (1/sqrt(2), -1/sqrt(2))
    const uWing2 = CadPoint2D(0.7071067811865475, 0.7071067811865475);
    const nWing2 = CadPoint2D(0.7071067811865475, -0.7071067811865475);

    for (final v in vOffsets45) {
      for (final u in uOffsets45) {
        punches.add(
          sampleSlot.copyWith(
            id: nextSlotId(),
            center: CadPoint2D(pB2Top.x + u * uWing2.x + v * nWing2.x, pB2Top.y + u * uWing2.y + v * nWing2.y),
            role: CncPunchRole.coupler,
            rotationDeg: 135.0,
          ),
        );
      }
    }

    // --- C. Bottom Wall Couplers (F_5) ---
    // 2 groups of slots: near Left Port and near Right Port
    final xOffsetsBot = [pLeftBottom.x + 20.0, pLeftBottom.x + 70.0, pRightBottom.x - 70.0, pRightBottom.x - 20.0];
    final List<double> yOffsetsBot;
    if (H >= 95.0) {
      yOffsetsBot = [b3Y + H / 2.0 - 25.0, b3Y + H / 2.0 + 25.0];
    } else if ((H - 50.0).abs() < 1.0) {
      // Exact baseline compatibility at H=50 (2 rows)
      yOffsetsBot = [b3Y + 20.95, b3Y + 45.95];
    } else {
      // 1 slot centered on height for H < 95mm
      yOffsetsBot = [b3Y + H / 2.0];
    }

    for (final y in yOffsetsBot) {
      for (final x in xOffsetsBot) {
        punches.add(sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(x, y), role: CncPunchRole.coupler, rotationDeg: 0.0));
      }
    }

    // --- D. Floor Web Perforations (F_6) ---
    // Top Port: vertical slots at y = pTopLeft.y + 20.0
    final numTopSlots = math.max(2, (W / 50.0).round());
    for (int i = 0; i < numTopSlots; i++) {
      final x = pTopLeft.x + 25.0 + i * 50.0;
      punches.add(sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(x, pTopLeft.y + 20.0), role: CncPunchRole.perforation, rotationDeg: 90.0));
    }

    // Left Port: horizontal slots at x = pB1Bot.x + 20.0
    final numSideSlots = math.max(2, (W / 50.0).round());
    for (int i = 0; i < numSideSlots; i++) {
      final y = pB1Bot.y + 25.0 + i * 50.0;
      punches.add(sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(pB1Bot.x + 20.0, y), role: CncPunchRole.perforation, rotationDeg: 0.0));
    }

    // Right Port: horizontal slots at x = pB2Bot.x - 20.0
    for (int i = 0; i < numSideSlots; i++) {
      final y = pB2Bot.y + 25.0 + i * 50.0;
      punches.add(sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(pB2Bot.x - 20.0, y), role: CncPunchRole.perforation, rotationDeg: 0.0));
    }

    // Centerline Floor Slots: along x = (pTopLeft.x + pTopRight.x) / 2.0
    final xMid = (pTopLeft.x + pTopRight.x) / 2.0;
    punches.add(sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(xMid, pTopLeft.y + span * 0.78564), role: CncPunchRole.perforation, rotationDeg: 0.0));
    punches.add(sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(xMid, b3Y - 22.18), role: CncPunchRole.perforation, rotationDeg: 0.0));

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
      }) {
        final slotLen = math.min(20.0, math.max(12.0, couplerFlapLength - 8.0));
        if (H <= 50.0) {
          final u = couplerFlapLength / 2.0;
          final vOffsets = H <= 35.0 ? [H * 0.3, H * 0.7] : [15.0, 35.0];
          for (final v in vOffsets) {
            punches.add(
              sampleSlot.copyWith(
                id: nextSlotId(),
                center: CadPoint2D(origin.x + u * uDir.x + v * vDir.x, origin.y + u * uDir.y + v * vDir.y),
                lengthMm: slotLen,
                role: CncPunchRole.coupler,
                rotationDeg: rotDeg,
                isVisible: true,
              ),
            );
          }
        } else {
          final uCols = [couplerFlapLength * 0.35, couplerFlapLength * 0.75];
          final vPitch = math.min(50.0, H - 30.0);
          final vOffsets = [H / 2.0 - vPitch / 2.0, H / 2.0 + vPitch / 2.0];
          for (final u in uCols) {
            for (final v in vOffsets) {
              punches.add(
                sampleSlot.copyWith(
                  id: nextSlotId(),
                  center: CadPoint2D(origin.x + u * uDir.x + v * vDir.x, origin.y + u * uDir.y + v * vDir.y),
                  lengthMm: slotLen,
                  role: CncPunchRole.coupler,
                  rotationDeg: rotDeg,
                  isVisible: true,
                ),
              );
            }
          }
        }
      }

      addFlapPunches(origin: pB1Bot, uDir: uWing1, vDir: nWing1, rotDeg: 135.0);
      addFlapPunches(origin: pB1Top, uDir: CadPoint2D(-uWing1.x, -uWing1.y), vDir: nWing1, rotDeg: 135.0);
      addFlapPunches(origin: pB2Top, uDir: CadPoint2D(-uWing2.x, -uWing2.y), vDir: nWing2, rotDeg: 45.0);
      addFlapPunches(origin: pB2Bot, uDir: uWing2, vDir: nWing2, rotDeg: 45.0);
      addFlapPunches(origin: pLeftBottom, uDir: const CadPoint2D(-1.0, 0.0), vDir: const CadPoint2D(0.0, 1.0), rotDeg: 0.0);
      addFlapPunches(origin: pRightBottom, uDir: const CadPoint2D(1.0, 0.0), vDir: const CadPoint2D(0.0, 1.0), rotDeg: 0.0);
    }

    return punches;
  }
}
