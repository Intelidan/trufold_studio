import 'dart:math' as math;
import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';
import 'tray_bend_geometry_solver.dart';

class TrayEqualCrossScaleParameters {
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
      includeCouplerFlaps ||
      (perforationPitch - 100.0).abs() > 1e-4 ||
      dW.abs() > 1e-4 ||
      dH.abs() > 1e-4 ||
      dR.abs() > 1e-4;

  const TrayEqualCrossScaleParameters({
    required this.targetWidth,
    required this.targetHeight,
    this.targetRadius = 180.0,
    this.baselineWidth = 100.0,
    this.baselineHeight = 50.0,
    this.baselineRadius = 180.0,
    this.includeCouplerFlaps = false,
    this.couplerFlapLength = 90.0,
    this.perforationPitch = 100.0,
  });
}

/// Standalone analytical parametric scaler for Cable Tray Equal Cross fittings.
///
/// Baseline geometry: 4 physical ports at 90° miter intersections, 4 diagonal 45°
/// cheek sidewalls, and 4 return flanges.
///
/// Preserves:
/// - Exact 45° corner cheek angles across all 4 quadrants
/// - Coupler punches follow the Universal 95mm Rule:
///     * H < 95mm: 1 row centered on sidewall height (v = H/2)
///     * H >= 95mm: 2 rows centered on sidewall height (v = H/2 ± 25mm)
///     * Positioned at u = 25, 75, L - 75, L - 25 along each cheek wall
/// - Integrated folding coupler flaps (8 tabs: 2 per cheek wall) when enabled
///     * 3 vertical obround slots (length = H - 20mm, width = 8mm, pitch = 25mm)
///     * BendDirection.down at 45° angle to align with straight tray runs
class TrayEqualCrossScaler {
  // Baseline geometric constants from assets/dsf_templates/tray_accessories/equal_cross_100x50.dsf
  static const double xMidBase = 237.42007201418437;
  static const double yMidBase = 237.42007201418437;
  static const double spanBase = 142.8723447994321;
  static const double hWallBase = 50.00;
  static const double wFlangeBase = 13.00;

  /// Determines whether [doc] is a Cable Tray Equal Cross.
  static bool isTrayEqualCross(DsfDocument doc) {
    final name = '${doc.productType} ${doc.itemName} ${doc.metadata['appliedTemplate']} ${doc.metadata['fittingVariant']}'.toLowerCase();
    if (name.contains('trunking')) return false;
    final isCross = name.contains('cross');
    final isUnequal = name.contains('unequal');
    if (!isCross || isUnequal) return false;

    // Check for 8 bends (B1..B4, FL1..FL4) and 4 corner 45° bends
    final has8Bends = doc.bends.length == 8;
    final hasNoEarBends = !doc.bends.any((b) => b.id == 'B5' || b.id == 'B6' || b.id == 'B7' || b.id == 'B8');
    final count45Bends = doc.bends.where((b) =>
        (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 &&
        ((b.p2.x - b.p1.x).abs() - (b.p2.y - b.p1.y).abs()).abs() < 2.0).length;

    return (isCross && !isUnequal && (has8Bends || count45Bends >= 4) && hasNoEarBends);
  }

  /// Scales [baseline] to [targetWidth], [targetHeight], and optional [targetRadius].
  static DsfDocument scale({
    required DsfDocument baseline,
    required double targetWidth,
    required double targetHeight,
    double targetRadius = 180.0,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 90.0,
    double perforationPitch = 100.0,
  }) {
    final params = TrayEqualCrossScaleParameters(
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

  static DsfDocument scaleWithParameters(DsfDocument baseline, TrayEqualCrossScaleParameters params) {
    if (!params.hasAnyChange) return baseline;

    final W = params.targetWidth;
    final H = params.targetHeight;
    final R = params.targetRadius;

    final dR = params.dR;

    // Miter span governed by bend radius
    final span = spanBase + dR * math.tan(22.5 * math.pi / 180.0);

    final xMid = xMidBase;
    final yMid = yMidBase;
    final halfW = W / 2.0;
    final dist = span + halfW;

    // 1. Four Port Mouth Edges (on base floor perimeter)
    // West Mouth (Port 1): vertical mouth at x = xWest
    final xWest = xMid - dist;
    final pWestTop = CadPoint2D(xWest, yMid - halfW);
    final pWestBot = CadPoint2D(xWest, yMid + halfW);

    // North Mouth (Port 2): horizontal mouth at y = yNorth (smaller Y)
    final yNorth = yMid - dist;
    final pNorthLeft = CadPoint2D(xMid - halfW, yNorth);
    final pNorthRight = CadPoint2D(xMid + halfW, yNorth);

    // East Mouth (Port 3): vertical mouth at x = xEast
    final xEast = xMid + dist;
    final pEastTop = CadPoint2D(xEast, yMid - halfW);
    final pEastBot = CadPoint2D(xEast, yMid + halfW);

    // South Mouth (Port 4): horizontal mouth at y = ySouth (larger Y)
    final ySouth = yMid + dist;
    final pSouthRight = CadPoint2D(xMid + halfW, ySouth);
    final pSouthLeft = CadPoint2D(xMid - halfW, ySouth);

    // 2. Corner Sidewall Normal Outward Directions & Flange Offsets
    // NW Corner (between North Left and West Top): normal (-1/sqrt2, -1/sqrt2)
    // SW Corner (between West Bot and South Left): normal (-1/sqrt2, 1/sqrt2)
    // SE Corner (between South Right and East Bot): normal (1/sqrt2, 1/sqrt2)
    // NE Corner (between East Top and North Right): normal (1/sqrt2, -1/sqrt2)
    const invSqrt2 = 0.7071067811865475;
    const nNW = CadPoint2D(-invSqrt2, -invSqrt2);
    const nSW = CadPoint2D(-invSqrt2, invSqrt2);
    const nSE = CadPoint2D(invSqrt2, invSqrt2);
    const nNE = CadPoint2D(invSqrt2, -invSqrt2);

    const wFlange = wFlangeBase; // 13.0 mm
    final totH = H + wFlange;

    // NW Flange Bend Line & Outer Edge (F_8, FL1, F_7 in baseline)
    final fl1P1 = CadPoint2D(pNorthLeft.x + H * nNW.x, pNorthLeft.y + H * nNW.y);
    final fl1P2 = CadPoint2D(pWestTop.x + H * nNW.x, pWestTop.y + H * nNW.y);
    final vNW1 = CadPoint2D(pNorthLeft.x + totH * nNW.x, pNorthLeft.y + totH * nNW.y);
    final vNW2 = CadPoint2D(pWestTop.x + totH * nNW.x, pWestTop.y + totH * nNW.y);

    // SW Flange Bend Line & Outer Edge (F_1, FL3, F_0 in baseline)
    final fl3P1 = CadPoint2D(pWestBot.x + H * nSW.x, pWestBot.y + H * nSW.y);
    final fl3P2 = CadPoint2D(pSouthLeft.x + H * nSW.x, pSouthLeft.y + H * nSW.y);
    final vSW1 = CadPoint2D(pWestBot.x + totH * nSW.x, pWestBot.y + totH * nSW.y);
    final vSW2 = CadPoint2D(pSouthLeft.x + totH * nSW.x, pSouthLeft.y + totH * nSW.y);

    // SE Flange Bend Line & Outer Edge (F_5, FL4, F_4 in baseline)
    final fl4P1 = CadPoint2D(pSouthRight.x + H * nSE.x, pSouthRight.y + H * nSE.y);
    final fl4P2 = CadPoint2D(pEastBot.x + H * nSE.x, pEastBot.y + H * nSE.y);
    final vSE1 = CadPoint2D(pSouthRight.x + totH * nSE.x, pSouthRight.y + totH * nSE.y);
    final vSE2 = CadPoint2D(pEastBot.x + totH * nSE.x, pEastBot.y + totH * nSE.y);

    // NE Flange Bend Line & Outer Edge (F_3, FL2, F_2 in baseline)
    final fl2P1 = CadPoint2D(pEastTop.x + H * nNE.x, pEastTop.y + H * nNE.y);
    final fl2P2 = CadPoint2D(pNorthRight.x + H * nNE.x, pNorthRight.y + H * nNE.y);
    final vNE1 = CadPoint2D(pEastTop.x + totH * nNE.x, pEastTop.y + totH * nNE.y);
    final vNE2 = CadPoint2D(pNorthRight.x + totH * nNE.x, pNorthRight.y + totH * nNE.y);

    // 3. Base Outer Contour (without coupler flaps)
    final baseOuterContour = [
      pWestTop,
      pWestBot,
      vSW1,
      vSW2,
      pSouthLeft,
      pSouthRight,
      vSE1,
      vSE2,
      pEastBot,
      pEastTop,
      vNE1,
      vNE2,
      pNorthRight,
      pNorthLeft,
      vNW1,
      vNW2,
      pWestTop,
    ];

    // 4. Bends
    final b1 = FoldBendLine(
      id: 'B1',
      p1: pNorthLeft,
      p2: pWestTop,
      targetAngleDeg: 90.0,
      role: BendLineRole.bend,
      parentFaceId: 'F_6',
      childFaceId: 'F_8',
    );
    final b2 = FoldBendLine(
      id: 'B2',
      p1: pWestBot,
      p2: pSouthLeft,
      targetAngleDeg: 90.0,
      role: BendLineRole.bend,
      parentFaceId: 'F_6',
      childFaceId: 'F_1',
    );
    final b3 = FoldBendLine(
      id: 'B3',
      p1: pEastTop,
      p2: pNorthRight,
      targetAngleDeg: 90.0,
      role: BendLineRole.bend,
      parentFaceId: 'F_6',
      childFaceId: 'F_3',
    );
    final b4 = FoldBendLine(
      id: 'B4',
      p1: pSouthRight,
      p2: pEastBot,
      targetAngleDeg: 90.0,
      role: BendLineRole.bend,
      parentFaceId: 'F_6',
      childFaceId: 'F_5',
    );

    final existingFlangeBend = baseline.bends.firstWhere(
      (b) => b.id.startsWith('FL') || b.role == BendLineRole.flange,
      orElse: () => baseline.bends.firstWhere((b) => b.layer.toUpperCase().contains('FLANGE'), orElse: () => const FoldBendLine(id: '', p1: CadPoint2D(0, 0), p2: CadPoint2D(0, 0), targetAngleDeg: 135.0)),
    );
    final flangeAngle = baseline.parameters['flange_angle'] ??
        (existingFlangeBend.id.isNotEmpty ? existingFlangeBend.targetAngleDeg : 135.0);

    final fl1 = FoldBendLine(
      id: 'FL1',
      p1: fl1P1,
      p2: fl1P2,
      targetAngleDeg: flangeAngle,
      role: BendLineRole.flange,
      parentFaceId: 'F_8',
      childFaceId: 'F_7',
    );
    final fl2 = FoldBendLine(
      id: 'FL2',
      p1: fl2P1,
      p2: fl2P2,
      targetAngleDeg: flangeAngle,
      role: BendLineRole.flange,
      parentFaceId: 'F_3',
      childFaceId: 'F_2',
    );
    final fl3 = FoldBendLine(
      id: 'FL3',
      p1: fl3P1,
      p2: fl3P2,
      targetAngleDeg: flangeAngle,
      role: BendLineRole.flange,
      parentFaceId: 'F_1',
      childFaceId: 'F_0',
    );
    final fl4 = FoldBendLine(
      id: 'FL4',
      p1: fl4P1,
      p2: fl4P2,
      targetAngleDeg: flangeAngle,
      role: BendLineRole.flange,
      parentFaceId: 'F_5',
      childFaceId: 'F_4',
    );

    final newBends = [b1, b2, b3, b4, fl1, fl2, fl3, fl4];

    // 5. Faces
    // Central Base Floor F_6
    final f6 = PlanarSheetFace(
      id: 'F_6',
      role: FaceRole.baseFloor,
      vertices: [
        pNorthLeft,
        pNorthRight,
        pEastTop,
        pEastBot,
        pSouthRight,
        pSouthLeft,
        pWestBot,
        pWestTop,
      ],
      isBaseAnchor: true,
    );

    // NW Sidewall F_8 & Flange F_7
    final f8 = PlanarSheetFace(id: 'F_8', role: FaceRole.sideWall, vertices: [fl1P1, pNorthLeft, pWestTop, fl1P2]);
    final f7 = PlanarSheetFace(id: 'F_7', role: FaceRole.returnFlange, vertices: [fl1P2, vNW2, vNW1, fl1P1]);

    // SW Sidewall F_1 & Flange F_0
    final f1 = PlanarSheetFace(id: 'F_1', role: FaceRole.sideWall, vertices: [fl3P1, pWestBot, pSouthLeft, fl3P2]);
    final f0 = PlanarSheetFace(id: 'F_0', role: FaceRole.returnFlange, vertices: [fl3P2, vSW2, vSW1, fl3P1]);

    // SE Sidewall F_5 & Flange F_4
    final f5 = PlanarSheetFace(id: 'F_5', role: FaceRole.sideWall, vertices: [fl4P1, pSouthRight, pEastBot, fl4P2]);
    final f4 = PlanarSheetFace(id: 'F_4', role: FaceRole.returnFlange, vertices: [fl4P2, vSE2, vSE1, fl4P1]);

    // NE Sidewall F_3 & Flange F_2
    final f3 = PlanarSheetFace(id: 'F_3', role: FaceRole.sideWall, vertices: [fl2P1, pEastTop, pNorthRight, fl2P2]);
    final f2 = PlanarSheetFace(id: 'F_2', role: FaceRole.returnFlange, vertices: [fl2P2, vNE2, vNE1, fl2P1]);

    final newFaces = [f0, f1, f2, f3, f4, f5, f6, f7, f8];

    // 6. Coupler Flaps Synthesis (8 Tabs)
    final includeFlaps = params.includeCouplerFlaps;
    final lf = params.couplerFlapLength;

    final List<CadPoint2D> effectiveOuterContour;
    final List<FoldBendLine> effectiveBends;
    final List<PlanarSheetFace> effectiveFaces;

    if (includeFlaps) {
      // Cheek wall unit tangents:
      // NW: from North to West: (-invSqrt2, invSqrt2)
      const uNW = CadPoint2D(-invSqrt2, invSqrt2);
      // SW: from West to South: (invSqrt2, invSqrt2)
      const uSW = CadPoint2D(invSqrt2, invSqrt2);
      // SE: from South to East: (invSqrt2, -invSqrt2)
      const uSE = CadPoint2D(invSqrt2, -invSqrt2);
      // NE: from East to North: (-invSqrt2, -invSqrt2)
      const uNE = CadPoint2D(-invSqrt2, -invSqrt2);

      // 8 Integrated Folding Flaps:
      // NW Wall:
      //   - Flap NW at North Mouth (extends North along -uNW)
      //   - Flap NW at West Mouth (extends West along uNW)
      final fFlapNwP2 = PlanarSheetFace(
        id: 'F_FLAP_8_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pNorthLeft,
          top: fl1P1,
          uDir: CadPoint2D(-uNW.x, -uNW.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P2',
      );
      final fFlapNwP1 = PlanarSheetFace(
        id: 'F_FLAP_8_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pWestTop,
          top: fl1P2,
          uDir: uNW,
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P1',
      );

      // SW Wall:
      //   - Flap SW at West Mouth (extends West along -uSW)
      //   - Flap SW at South Mouth (extends South along uSW)
      final fFlapSwP1 = PlanarSheetFace(
        id: 'F_FLAP_1_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pWestBot,
          top: fl3P1,
          uDir: CadPoint2D(-uSW.x, -uSW.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P1',
      );
      final fFlapSwP4 = PlanarSheetFace(
        id: 'F_FLAP_1_P4',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pSouthLeft,
          top: fl3P2,
          uDir: uSW,
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P4',
      );

      // SE Wall:
      //   - Flap SE at South Mouth (extends South along -uSE)
      //   - Flap SE at East Mouth (extends East along uSE)
      final fFlapSeP4 = PlanarSheetFace(
        id: 'F_FLAP_5_P4',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pSouthRight,
          top: fl4P1,
          uDir: CadPoint2D(-uSE.x, -uSE.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P4',
      );
      final fFlapSeP3 = PlanarSheetFace(
        id: 'F_FLAP_5_P3',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pEastBot,
          top: fl4P2,
          uDir: uSE,
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P3',
      );

      // NE Wall:
      //   - Flap NE at East Mouth (extends East along -uNE)
      //   - Flap NE at North Mouth (extends North along uNE)
      final fFlapNeP3 = PlanarSheetFace(
        id: 'F_FLAP_3_P3',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pEastTop,
          top: fl2P1,
          uDir: CadPoint2D(-uNE.x, -uNE.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P3',
      );
      final fFlapNeP2 = PlanarSheetFace(
        id: 'F_FLAP_3_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pNorthRight,
          top: fl2P2,
          uDir: uNE,
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P2',
      );

      effectiveFaces = [
        ...newFaces,
        fFlapNwP1,
        fFlapNwP2,
        fFlapSwP1,
        fFlapSwP4,
        fFlapSeP4,
        fFlapSeP3,
        fFlapNeP3,
        fFlapNeP2,
      ];

      // Flap Bends (all 45° with BendDirection.down to align parallel to tray runs)
      final bfNwP2 = FoldBendLine(
        id: 'BF_8_P2',
        p1: pNorthLeft,
        p2: fl1P1,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_8',
        childFaceId: 'F_FLAP_8_P2',
        direction: BendDirection.down,
      );
      final bfNwP1 = FoldBendLine(
        id: 'BF_8_P1',
        p1: pWestTop,
        p2: fl1P2,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_8',
        childFaceId: 'F_FLAP_8_P1',
        direction: BendDirection.down,
      );

      final bfSwP1 = FoldBendLine(
        id: 'BF_1_P1',
        p1: pWestBot,
        p2: fl3P1,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P1',
        direction: BendDirection.down,
      );
      final bfSwP4 = FoldBendLine(
        id: 'BF_1_P4',
        p1: pSouthLeft,
        p2: fl3P2,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P4',
        direction: BendDirection.down,
      );

      final bfSeP4 = FoldBendLine(
        id: 'BF_5_P4',
        p1: pSouthRight,
        p2: fl4P1,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_5',
        childFaceId: 'F_FLAP_5_P4',
        direction: BendDirection.down,
      );
      final bfSeP3 = FoldBendLine(
        id: 'BF_5_P3',
        p1: pEastBot,
        p2: fl4P2,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_5',
        childFaceId: 'F_FLAP_5_P3',
        direction: BendDirection.down,
      );

      final bfNeP3 = FoldBendLine(
        id: 'BF_3_P3',
        p1: pEastTop,
        p2: fl2P1,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_3',
        childFaceId: 'F_FLAP_3_P3',
        direction: BendDirection.down,
      );
      final bfNeP2 = FoldBendLine(
        id: 'BF_3_P2',
        p1: pNorthRight,
        p2: fl2P2,
        targetAngleDeg: 45.0,
        role: BendLineRole.bend,
        parentFaceId: 'F_3',
        childFaceId: 'F_FLAP_3_P2',
        direction: BendDirection.down,
      );

      effectiveBends = [
        ...newBends,
        bfNwP1,
        bfNwP2,
        bfSwP1,
        bfSwP4,
        bfSeP4,
        bfSeP3,
        bfNeP3,
        bfNeP2,
      ];

      effectiveOuterContour = [
        pNorthLeft,
        pNorthRight,
        CadPoint2D(pNorthRight.x + lf * uNE.x, pNorthRight.y + lf * uNE.y),
        CadPoint2D(fl2P2.x + lf * uNE.x, fl2P2.y + lf * uNE.y),
        fl2P2,
        vNE2,
        vNE1,
        fl2P1,
        CadPoint2D(fl2P1.x - lf * uNE.x, fl2P1.y - lf * uNE.y),
        CadPoint2D(pEastTop.x - lf * uNE.x, pEastTop.y - lf * uNE.y),
        pEastTop,
        pEastBot,
        CadPoint2D(pEastBot.x + lf * uSE.x, pEastBot.y + lf * uSE.y),
        CadPoint2D(fl4P2.x + lf * uSE.x, fl4P2.y + lf * uSE.y),
        fl4P2,
        vSE2,
        vSE1,
        fl4P1,
        CadPoint2D(fl4P1.x - lf * uSE.x, fl4P1.y - lf * uSE.y),
        CadPoint2D(pSouthRight.x - lf * uSE.x, pSouthRight.y - lf * uSE.y),
        pSouthRight,
        pSouthLeft,
        CadPoint2D(pSouthLeft.x + lf * uSW.x, pSouthLeft.y + lf * uSW.y),
        CadPoint2D(fl3P2.x + lf * uSW.x, fl3P2.y + lf * uSW.y),
        fl3P2,
        vSW2,
        vSW1,
        fl3P1,
        CadPoint2D(fl3P1.x - lf * uSW.x, fl3P1.y - lf * uSW.y),
        CadPoint2D(pWestBot.x - lf * uSW.x, pWestBot.y - lf * uSW.y),
        pWestBot,
        pWestTop,
        CadPoint2D(pWestTop.x + lf * uNW.x, pWestTop.y + lf * uNW.y),
        CadPoint2D(fl1P2.x + lf * uNW.x, fl1P2.y + lf * uNW.y),
        fl1P2,
        vNW2,
        vNW1,
        fl1P1,
        CadPoint2D(fl1P1.x - lf * uNW.x, fl1P1.y - lf * uNW.y),
        CadPoint2D(pNorthLeft.x - lf * uNW.x, pNorthLeft.y - lf * uNW.y),
        pNorthLeft,
      ];
    } else {
      effectiveFaces = newFaces;
      effectiveBends = newBends;
      effectiveOuterContour = baseOuterContour;
    }

    // 7. Punches Generation per Universal 95mm Rule
    final newPunches = _generatePunches(
      baseline: baseline,
      W: W,
      H: H,
      span: span,
      pNorthLeft: pNorthLeft,
      pNorthRight: pNorthRight,
      pWestTop: pWestTop,
      pWestBot: pWestBot,
      pSouthLeft: pSouthLeft,
      pSouthRight: pSouthRight,
      pEastTop: pEastTop,
      pEastBot: pEastBot,
      fl1P1: fl1P1,
      fl1P2: fl1P2,
      fl2P1: fl2P1,
      fl2P2: fl2P2,
      fl3P1: fl3P1,
      fl3P2: fl3P2,
      fl4P1: fl4P1,
      fl4P2: fl4P2,
      includeCouplerFlaps: includeFlaps,
      couplerFlapLength: lf,
      perforationPitch: params.perforationPitch,
    );

    // 8. Update Parameters
    final newParams = Map<String, double>.from(baseline.parameters);
    newParams['width'] = W;
    newParams['height'] = H;
    newParams['radius'] = R;
    for (int i = 1; i <= 4; i++) {
      newParams['port${i}_width'] = W;
      newParams['port${i}_height'] = H;
    }

    return baseline.copyWith(
      outerContour: effectiveOuterContour,
      bends: effectiveBends,
      faces: effectiveFaces,
      punches: newPunches,
      parameters: newParams,
    );
  }

  static List<CncPunchPrimitive> _generatePunches({
    required DsfDocument baseline,
    required double W,
    required double H,
    required double span,
    required CadPoint2D pNorthLeft,
    required CadPoint2D pNorthRight,
    required CadPoint2D pWestTop,
    required CadPoint2D pWestBot,
    required CadPoint2D pSouthLeft,
    required CadPoint2D pSouthRight,
    required CadPoint2D pEastTop,
    required CadPoint2D pEastBot,
    required CadPoint2D fl1P1,
    required CadPoint2D fl1P2,
    required CadPoint2D fl2P1,
    required CadPoint2D fl2P2,
    required CadPoint2D fl3P1,
    required CadPoint2D fl3P2,
    required CadPoint2D fl4P1,
    required CadPoint2D fl4P2,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 90.0,
    double perforationPitch = 100.0,
  }) {
    final punches = <CncPunchPrimitive>[];
    final sampleSlot = baseline.punches.firstWhere(
      (p) => p.isSlot || p.type == PunchType.obroundSlot,
      orElse: () => baseline.punches.first,
    );

    int idCounter = 1;
    String nextSlotId() => 'SLOT_${idCounter++}';

    final heightRows = H >= 95.0 ? 2 : 1;
    final wallLen = span * math.sqrt(2);
    final uOffsets = [25.0, 75.0, wallLen - 75.0, wallLen - 25.0];
    final vOffsets = heightRows == 1 ? [H / 2.0] : [H / 2.0 - 25.0, H / 2.0 + 25.0];

    const invSqrt2 = 0.7071067811865475;

    // A. NW Sidewall F_8 (runs from pNorthLeft to pWestTop)
    const uNW = CadPoint2D(-invSqrt2, invSqrt2);
    const nNW = CadPoint2D(-invSqrt2, -invSqrt2);
    for (final v in vOffsets) {
      for (final u in uOffsets) {
        punches.add(
          sampleSlot.copyWith(
            id: nextSlotId(),
            center: CadPoint2D(pNorthLeft.x + u * uNW.x + v * nNW.x, pNorthLeft.y + u * uNW.y + v * nNW.y),
            role: CncPunchRole.coupler,
            rotationDeg: 45.0,
            isVisible: !includeCouplerFlaps,
          ),
        );
      }
    }

    // B. SW Sidewall F_1 (runs from pWestBot to pSouthLeft)
    const uSW = CadPoint2D(invSqrt2, invSqrt2);
    const nSW = CadPoint2D(-invSqrt2, invSqrt2);
    for (final v in vOffsets) {
      for (final u in uOffsets) {
        punches.add(
          sampleSlot.copyWith(
            id: nextSlotId(),
            center: CadPoint2D(pWestBot.x + u * uSW.x + v * nSW.x, pWestBot.y + u * uSW.y + v * nSW.y),
            role: CncPunchRole.coupler,
            rotationDeg: 135.0,
            isVisible: !includeCouplerFlaps,
          ),
        );
      }
    }

    // C. SE Sidewall F_5 (runs from pSouthRight to pEastBot)
    const uSE = CadPoint2D(invSqrt2, -invSqrt2);
    const nSE = CadPoint2D(invSqrt2, invSqrt2);
    for (final v in vOffsets) {
      for (final u in uOffsets) {
        punches.add(
          sampleSlot.copyWith(
            id: nextSlotId(),
            center: CadPoint2D(pSouthRight.x + u * uSE.x + v * nSE.x, pSouthRight.y + u * uSE.y + v * nSE.y),
            role: CncPunchRole.coupler,
            rotationDeg: 45.0,
            isVisible: !includeCouplerFlaps,
          ),
        );
      }
    }

    // D. NE Sidewall F_3 (runs from pEastTop to pNorthRight)
    const uNE = CadPoint2D(-invSqrt2, -invSqrt2);
    const nNE = CadPoint2D(invSqrt2, -invSqrt2);
    for (final v in vOffsets) {
      for (final u in uOffsets) {
        punches.add(
          sampleSlot.copyWith(
            id: nextSlotId(),
            center: CadPoint2D(pEastTop.x + u * uNE.x + v * nNE.x, pEastTop.y + u * uNE.y + v * nNE.y),
            role: CncPunchRole.coupler,
            rotationDeg: 135.0,
            isVisible: !includeCouplerFlaps,
          ),
        );
      }
    }

    // E. Floor Web Perforations (F_6)
    List<double> mouthOffsets(double width) {
      if (width < 75.0) return [width / 2.0];
      final count = math.max(1, (width / 50.0).floor());
      final half = width / 2.0;
      final offs = <double>[];
      if (count.isOdd) {
        offs.add(half);
        for (int k = 1; k <= count ~/ 2; k++) {
          offs.add(half - k * 50.0);
          offs.add(half + k * 50.0);
        }
      } else {
        for (int k = 0; k < count ~/ 2; k++) {
          offs.add(half - 25.0 - k * 50.0);
          offs.add(half + 25.0 + k * 50.0);
        }
      }
      offs.sort();
      return offs.where((o) => o >= 15.0 && o <= width - 15.0).toList();
    }

    final mouthOffs = mouthOffsets(W);
    // West mouth: horizontal slots (offset +20mm in X)
    for (final off in mouthOffs) {
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(pWestTop.x + 20.0, pWestTop.y + off),
        role: CncPunchRole.perforation,
        rotationDeg: 0.0,
      ));
    }

    // East mouth: horizontal slots (offset -20mm in X)
    for (final off in mouthOffs) {
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(pEastTop.x - 20.0, pEastTop.y + off),
        role: CncPunchRole.perforation,
        rotationDeg: 0.0,
      ));
    }

    // North mouth: vertical slots (offset +20mm in Y)
    for (final off in mouthOffs) {
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(pNorthLeft.x + off, pNorthLeft.y + 20.0),
        role: CncPunchRole.perforation,
        rotationDeg: 90.0,
      ));
    }

    // South mouth: vertical slots (offset -20mm in Y)
    for (final off in mouthOffs) {
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(pSouthLeft.x + off, pSouthLeft.y - 20.0),
        role: CncPunchRole.perforation,
        rotationDeg: 90.0,
      ));
    }

    // Centerline Floor Slot
    final xMid = (pNorthLeft.x + pNorthRight.x) / 2.0;
    final yMid = (pWestTop.y + pWestBot.y) / 2.0;
    punches.add(sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(xMid, yMid), role: CncPunchRole.perforation, rotationDeg: 0.0));

    // F. Coupler Flap Slots (when flaps active)
    if (includeCouplerFlaps) {
      void addFlapPunches({
        required CadPoint2D origin,
        required CadPoint2D uDir,
        required CadPoint2D vDir,
        required double rotDeg,
      }) {
        final slotLen = math.max(10.0, H - 20.0);
        const slotWid = 8.0;
        const slotPitch = 25.0;

        final uCenter = couplerFlapLength / 2.0;
        final uList = [uCenter - slotPitch, uCenter, uCenter + slotPitch];
        final v = H / 2.0;
        for (final u in uList) {
          punches.add(
            sampleSlot.copyWith(
              id: nextSlotId(),
              center: CadPoint2D(origin.x + u * uDir.x + v * vDir.x, origin.y + u * uDir.y + v * vDir.y),
              lengthMm: slotLen,
              widthMm: slotWid,
              role: CncPunchRole.coupler,
              rotationDeg: rotDeg,
              isVisible: true,
            ),
          );
        }
      }

      const uNW = CadPoint2D(-invSqrt2, invSqrt2);
      const uSW = CadPoint2D(invSqrt2, invSqrt2);
      const uSE = CadPoint2D(invSqrt2, -invSqrt2);
      const uNE = CadPoint2D(-invSqrt2, -invSqrt2);

      // NW Wall tabs
      addFlapPunches(origin: pNorthLeft, uDir: CadPoint2D(-uNW.x, -uNW.y), vDir: nNW, rotDeg: 45.0);
      addFlapPunches(origin: pWestTop, uDir: uNW, vDir: nNW, rotDeg: 45.0);

      // SW Wall tabs
      addFlapPunches(origin: pWestBot, uDir: CadPoint2D(-uSW.x, -uSW.y), vDir: nSW, rotDeg: 135.0);
      addFlapPunches(origin: pSouthLeft, uDir: uSW, vDir: nSW, rotDeg: 135.0);

      // SE Wall tabs
      addFlapPunches(origin: pSouthRight, uDir: CadPoint2D(-uSE.x, -uSE.y), vDir: nSE, rotDeg: 45.0);
      addFlapPunches(origin: pEastBot, uDir: uSE, vDir: nSE, rotDeg: 45.0);

      // NE Wall tabs
      addFlapPunches(origin: pEastTop, uDir: CadPoint2D(-uNE.x, -uNE.y), vDir: nNE, rotDeg: 135.0);
      addFlapPunches(origin: pNorthRight, uDir: uNE, vDir: nNE, rotDeg: 45.0);
    }

    return punches;
  }
}
