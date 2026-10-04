import 'dart:math' as math;

import '../../models/cad_primitives.dart';
import '../../models/cms/cms_scaling_model.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';
import 'tray_bend_geometry_solver.dart';

class TrayUnequalCrossScaleParameters {
  final double port1Width;
  final double port2Width;
  final double port3Width;
  final double port4Width;

  final double port1Height;
  final double port2Height;
  final double port3Height;
  final double port4Height;

  final double targetRadius;

  final double baselinePort1Width;
  final double baselinePort2Width;
  final double baselinePort3Width;
  final double baselinePort4Width;

  final double baselinePort1Height;
  final double baselinePort2Height;
  final double baselinePort3Height;
  final double baselinePort4Height;

  final double baselineRadius;
  final bool includeCouplerFlaps;
  final double couplerFlapLength;
  final double perforationPitch;

  bool get hasAnyChange =>
      includeCouplerFlaps ||
      (perforationPitch - 100.0).abs() > 1e-4 ||
      (port1Width - baselinePort1Width).abs() > 1e-4 ||
      (port2Width - baselinePort2Width).abs() > 1e-4 ||
      (port3Width - baselinePort3Width).abs() > 1e-4 ||
      (port4Width - baselinePort4Width).abs() > 1e-4 ||
      (port1Height - baselinePort1Height).abs() > 1e-4 ||
      (port2Height - baselinePort2Height).abs() > 1e-4 ||
      (port3Height - baselinePort3Height).abs() > 1e-4 ||
      (port4Height - baselinePort4Height).abs() > 1e-4 ||
      (targetRadius - baselineRadius).abs() > 1e-4;

  const TrayUnequalCrossScaleParameters({
    this.port1Width = 50.0,
    this.port2Width = 100.0,
    this.port3Width = 50.0,
    this.port4Width = 100.0,
    this.port1Height = 50.0,
    this.port2Height = 50.0,
    this.port3Height = 50.0,
    this.port4Height = 50.0,
    this.targetRadius = 180.0,
    this.baselinePort1Width = 50.0,
    this.baselinePort2Width = 100.0,
    this.baselinePort3Width = 50.0,
    this.baselinePort4Width = 100.0,
    this.baselinePort1Height = 50.0,
    this.baselinePort2Height = 50.0,
    this.baselinePort3Height = 50.0,
    this.baselinePort4Height = 50.0,
    this.baselineRadius = 180.0,
    this.includeCouplerFlaps = false,
    this.couplerFlapLength = 90.0,
    this.perforationPitch = 100.0,
  });

  factory TrayUnequalCrossScaleParameters.fromCmsParameters(
    Map<String, CmsScalingParameter> parameters, {
    required bool isLinked,
    bool? includeCouplerFlaps,
    double? couplerFlapLength,
    double? perforationPitch,
  }) {
    final effectiveIncludeFlaps = includeCouplerFlaps ?? ((parameters['include_coupler_flaps']?.currentValue ?? 0.0) > 0.5);
    final effectiveFlapLen = couplerFlapLength ?? (parameters['coupler_flap_length']?.currentValue ?? 90.0);
    final effectivePerfPitch = perforationPitch ?? (parameters['perforation_pitch']?.currentValue ?? 100.0);

    if (isLinked) {
      final w = parameters['width']?.currentValue ?? 100.0;
      final h = parameters['height']?.currentValue ?? 50.0;
      final r = parameters['radius']?.currentValue ?? 180.0;
      return TrayUnequalCrossScaleParameters(
        port1Width: w,
        port2Width: w,
        port3Width: w,
        port4Width: w,
        port1Height: h,
        port2Height: h,
        port3Height: h,
        port4Height: h,
        targetRadius: r,
        includeCouplerFlaps: effectiveIncludeFlaps,
        couplerFlapLength: effectiveFlapLen,
        perforationPitch: effectivePerfPitch,
      );
    }

    final p1W = parameters['port1_width']?.currentValue ?? parameters['port1_width']?.baselineValue ?? 50.0;
    final p2W = parameters['port2_width']?.currentValue ?? parameters['port2_width']?.baselineValue ?? 100.0;
    final p3W = parameters['port3_width']?.currentValue ?? parameters['port3_width']?.baselineValue ?? 50.0;
    final p4W = parameters['port4_width']?.currentValue ?? parameters['port4_width']?.baselineValue ?? 100.0;

    final p1H = parameters['port1_height']?.currentValue ?? parameters['port1_height']?.baselineValue ?? 50.0;
    final p2H = parameters['port2_height']?.currentValue ?? parameters['port2_height']?.baselineValue ?? 50.0;
    final p3H = parameters['port3_height']?.currentValue ?? parameters['port3_height']?.baselineValue ?? 50.0;
    final p4H = parameters['port4_height']?.currentValue ?? parameters['port4_height']?.baselineValue ?? 50.0;

    final r = parameters['radius']?.currentValue ?? 180.0;

    return TrayUnequalCrossScaleParameters(
      port1Width: p1W,
      port2Width: p2W,
      port3Width: p3W,
      port4Width: p4W,
      port1Height: p1H,
      port2Height: p2H,
      port3Height: p3H,
      port4Height: p4H,
      targetRadius: r,
      includeCouplerFlaps: effectiveIncludeFlaps,
      couplerFlapLength: effectiveFlapLen,
      perforationPitch: effectivePerfPitch,
    );
  }
}

/// Standalone analytical parametric scaler for Cable Tray Unequal Cross fittings.
///
/// Features:
/// - Independent width and height control for all 4 ports (Port 1 West, Port 2 North, Port 3 East, Port 4 South).
/// - 4 diagonal corner cheek walls slant smoothly between adjacent port heights:
///     * NW wall slants from Port 2 height (North) to Port 1 height (West)
///     * SW wall slants from Port 1 height (West) to Port 4 height (South)
///     * SE wall slants from Port 4 height (South) to Port 3 height (East)
///     * NE wall slants from Port 3 height (East) to Port 2 height (North)
/// - Orthogonal port mouths with exact 45° miter bend lines
/// - Coupler punches follow the Universal 95mm Rule per individual port edge height
/// - Integrated folding coupler flaps (8 tabs) with 3 vertical slots per mouth edge
class TrayUnequalCrossScaler {
  // Baseline geometric constants from assets/dsf_templates/tray_accessories/unequal_cross_100x50x100x50.dsf
  static const double xMidBase = 237.42007201418437;
  static const double yMidBase = 212.42007201418437;
  static const double spanBase = 142.8723447994321;
  static const double wFlangeBase = 13.00;

  /// Determines whether [doc] is a Cable Tray Unequal Cross fitting.
  static bool isTrayUnequalCross(DsfDocument doc) {
    final name = '${doc.productType} ${doc.itemName} ${doc.metadata['appliedTemplate']} ${doc.metadata['fittingVariant']}'.toLowerCase();
    if (name.contains('trunking')) return false;
    final isCross = name.contains('cross');
    final isUnequal = name.contains('unequal');
    if (!isCross) return false;

    // Check for 8 bends (B1..B4, FL1..FL4) and no trunking ear bends
    final has8Bends = doc.bends.length == 8;
    final hasNoEarBends = !doc.bends.any((b) => b.id == 'B5' || b.id == 'B6' || b.id == 'B7' || b.id == 'B8');

    // If explicit "unequal" keyword is present with 8 bends and no ear bends
    if (isUnequal && has8Bends && hasNoEarBends) return true;
    if (isUnequal && hasNoEarBends) return true;

    return false;
  }

  /// Scales [baseline] using [TrayUnequalCrossScaleParameters].
  static DsfDocument scaleWithParameters(DsfDocument baseline, TrayUnequalCrossScaleParameters params) {
    if (!params.hasAnyChange) return baseline;

    final w1 = params.port1Width; // West
    final w2 = params.port2Width; // North
    final w3 = params.port3Width; // East
    final w4 = params.port4Width; // South

    final h1 = params.port1Height; // West
    final h2 = params.port2Height; // North
    final h3 = params.port3Height; // East
    final h4 = params.port4Height; // South

    final r = params.targetRadius;
    final dR = r - 180.0;
    final span0 = spanBase + dR * math.tan(22.5 * math.pi / 180.0);

    final xMid = xMidBase;
    final yMid = yMidBase;

    // Independent mouth offsets:
    // West & East mouth distance from centerline depends on North & South widths
    // North & South mouth distance from centerline depends on West & East widths
    final maxWNs = math.max(w2, w4);
    final maxWWe = math.max(w1, w3);

    final distWE = span0 + maxWNs / 2.0;
    final distNS = span0 + maxWWe / 2.0;

    // 1. Four Port Mouth Edges (on base floor perimeter)
    // West Mouth (Port 1): vertical mouth at x = xWest
    final xWest = xMid - distWE;
    final pWestTop = CadPoint2D(xWest, yMid - w1 / 2.0);
    final pWestBot = CadPoint2D(xWest, yMid + w1 / 2.0);

    // North Mouth (Port 2): horizontal mouth at y = yNorth (smaller Y)
    final yNorth = yMid - distNS;
    final pNorthLeft = CadPoint2D(xMid - w2 / 2.0, yNorth);
    final pNorthRight = CadPoint2D(xMid + w2 / 2.0, yNorth);

    // East Mouth (Port 3): vertical mouth at x = xEast
    final xEast = xMid + distWE;
    final pEastTop = CadPoint2D(xEast, yMid - w3 / 2.0);
    final pEastBot = CadPoint2D(xEast, yMid + w3 / 2.0);

    // South Mouth (Port 4): horizontal mouth at y = ySouth (larger Y)
    final ySouth = yMid + distNS;
    final pSouthRight = CadPoint2D(xMid + w4 / 2.0, ySouth);
    final pSouthLeft = CadPoint2D(xMid - w4 / 2.0, ySouth);

    // 2. Corner Sidewall Tangent & Normal Outward Directions
    // NW Wall: pNorthLeft to pWestTop
    final dxNW = pWestTop.x - pNorthLeft.x;
    final dyNW = pWestTop.y - pNorthLeft.y;
    final lenNW = math.sqrt(dxNW * dxNW + dyNW * dyNW);
    final uNW = CadPoint2D(dxNW / lenNW, dyNW / lenNW);
    final nNW = CadPoint2D(-uNW.y, uNW.x);
    final thetaNW = math.atan2(uNW.x.abs(), uNW.y.abs()) * 180.0 / math.pi;

    // SW Wall: pWestBot to pSouthLeft
    final dxSW = pSouthLeft.x - pWestBot.x;
    final dySW = pSouthLeft.y - pWestBot.y;
    final lenSW = math.sqrt(dxSW * dxSW + dySW * dySW);
    final uSW = CadPoint2D(dxSW / lenSW, dySW / lenSW);
    final nSW = CadPoint2D(-uSW.y, uSW.x);
    final thetaSW = math.atan2(uSW.y.abs(), uSW.x.abs()) * 180.0 / math.pi;

    // SE Wall: pSouthRight to pEastBot
    final dxSE = pEastBot.x - pSouthRight.x;
    final dySE = pEastBot.y - pSouthRight.y;
    final lenSE = math.sqrt(dxSE * dxSE + dySE * dySE);
    final uSE = CadPoint2D(dxSE / lenSE, dySE / lenSE);
    final nSE = CadPoint2D(-uSE.y, uSE.x);
    final thetaSE = math.atan2(uSE.x.abs(), uSE.y.abs()) * 180.0 / math.pi;

    // NE Wall: pEastTop to pNorthRight
    final dxNE = pNorthRight.x - pEastTop.x;
    final dyNE = pNorthRight.y - pEastTop.y;
    final lenNE = math.sqrt(dxNE * dxNE + dyNE * dyNE);
    final uNE = CadPoint2D(dxNE / lenNE, dyNE / lenNE);
    final nNE = CadPoint2D(-uNE.y, uNE.x);
    final thetaNE = math.atan2(uNE.y.abs(), uNE.x.abs()) * 180.0 / math.pi;

    const wFlange = wFlangeBase; // 13.0 mm

    // NW Flange Bend Line & Outer Edge (F_8, FL1, F_7 in baseline)
    // Slants from h2 at North to h1 at West
    final fl1P1 = CadPoint2D(pNorthLeft.x + h2 * nNW.x, pNorthLeft.y + h2 * nNW.y);
    final fl1P2 = CadPoint2D(pWestTop.x + h1 * nNW.x, pWestTop.y + h1 * nNW.y);
    final vNW1 = CadPoint2D(pNorthLeft.x + (h2 + wFlange) * nNW.x, pNorthLeft.y + (h2 + wFlange) * nNW.y);
    final vNW2 = CadPoint2D(pWestTop.x + (h1 + wFlange) * nNW.x, pWestTop.y + (h1 + wFlange) * nNW.y);

    // SW Flange Bend Line & Outer Edge (F_5, FL4, F_4 in baseline)
    // Slants from h1 at West to h4 at South
    final fl4P1 = CadPoint2D(pWestBot.x + h1 * nSW.x, pWestBot.y + h1 * nSW.y);
    final fl4P2 = CadPoint2D(pSouthLeft.x + h4 * nSW.x, pSouthLeft.y + h4 * nSW.y);
    final vSW1 = CadPoint2D(pWestBot.x + (h1 + wFlange) * nSW.x, pWestBot.y + (h1 + wFlange) * nSW.y);
    final vSW2 = CadPoint2D(pSouthLeft.x + (h4 + wFlange) * nSW.x, pSouthLeft.y + (h4 + wFlange) * nSW.y);

    // SE Flange Bend Line & Outer Edge (F_3, FL3, F_2 in baseline)
    // Slants from h4 at South to h3 at East
    final fl3P1 = CadPoint2D(pSouthRight.x + h4 * nSE.x, pSouthRight.y + h4 * nSE.y);
    final fl3P2 = CadPoint2D(pEastBot.x + h3 * nSE.x, pEastBot.y + h3 * nSE.y);
    final vSE1 = CadPoint2D(pSouthRight.x + (h4 + wFlange) * nSE.x, pSouthRight.y + (h4 + wFlange) * nSE.y);
    final vSE2 = CadPoint2D(pEastBot.x + (h3 + wFlange) * nSE.x, pEastBot.y + (h3 + wFlange) * nSE.y);

    // NE Flange Bend Line & Outer Edge (F_1, FL2, F_0 in baseline)
    // Slants from h3 at East to h2 at North
    final fl2P1 = CadPoint2D(pEastTop.x + h3 * nNE.x, pEastTop.y + h3 * nNE.y);
    final fl2P2 = CadPoint2D(pNorthRight.x + h2 * nNE.x, pNorthRight.y + h2 * nNE.y);
    final vNE1 = CadPoint2D(pEastTop.x + (h3 + wFlange) * nNE.x, pEastTop.y + (h3 + wFlange) * nNE.y);
    final vNE2 = CadPoint2D(pNorthRight.x + (h2 + wFlange) * nNE.x, pNorthRight.y + (h2 + wFlange) * nNE.y);

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
    final b1 = FoldBendLine(id: 'B1', p1: pNorthLeft, p2: pWestTop, targetAngleDeg: 90.0, role: BendLineRole.bend, parentFaceId: 'F_6', childFaceId: 'F_8');
    final b4 = FoldBendLine(id: 'B4', p1: pWestBot, p2: pSouthLeft, targetAngleDeg: 90.0, role: BendLineRole.bend, parentFaceId: 'F_6', childFaceId: 'F_5');
    final b3 = FoldBendLine(id: 'B3', p1: pSouthRight, p2: pEastBot, targetAngleDeg: 90.0, role: BendLineRole.bend, parentFaceId: 'F_6', childFaceId: 'F_3');
    final b2 = FoldBendLine(id: 'B2', p1: pEastTop, p2: pNorthRight, targetAngleDeg: 90.0, role: BendLineRole.bend, parentFaceId: 'F_6', childFaceId: 'F_1');

    final existingFlangeBend = baseline.bends.firstWhere(
      (b) => b.id.startsWith('FL') || b.role == BendLineRole.flange,
      orElse: () => baseline.bends.firstWhere((b) => b.layer.toUpperCase().contains('FLANGE'), orElse: () => const FoldBendLine(id: '', p1: CadPoint2D(0, 0), p2: CadPoint2D(0, 0), targetAngleDeg: 135.0)),
    );
    final flangeAngle = baseline.parameters['flange_angle'] ??
        (existingFlangeBend.id.isNotEmpty ? existingFlangeBend.targetAngleDeg : 135.0);

    final fl1 = FoldBendLine(id: 'FL1', p1: fl1P1, p2: fl1P2, targetAngleDeg: flangeAngle, role: BendLineRole.flange, parentFaceId: 'F_8', childFaceId: 'F_7');
    final fl4 = FoldBendLine(id: 'FL4', p1: fl4P1, p2: fl4P2, targetAngleDeg: flangeAngle, role: BendLineRole.flange, parentFaceId: 'F_5', childFaceId: 'F_4');
    final fl3 = FoldBendLine(id: 'FL3', p1: fl3P1, p2: fl3P2, targetAngleDeg: flangeAngle, role: BendLineRole.flange, parentFaceId: 'F_3', childFaceId: 'F_2');
    final fl2 = FoldBendLine(id: 'FL2', p1: fl2P1, p2: fl2P2, targetAngleDeg: flangeAngle, role: BendLineRole.flange, parentFaceId: 'F_1', childFaceId: 'F_0');

    final newBends = [b1, b2, b3, b4, fl1, fl2, fl3, fl4];

    // 5. Faces
    // Central Base Floor F_6
    final f6 = PlanarSheetFace(
      id: 'F_6',
      role: FaceRole.baseFloor,
      vertices: [pNorthLeft, pNorthRight, pEastTop, pEastBot, pSouthRight, pSouthLeft, pWestBot, pWestTop],
      isBaseAnchor: true,
    );

    // NW Sidewall F_8 & Flange F_7
    final f8 = PlanarSheetFace(id: 'F_8', role: FaceRole.sideWall, vertices: [fl1P1, pNorthLeft, pWestTop, fl1P2]);
    final f7 = PlanarSheetFace(id: 'F_7', role: FaceRole.returnFlange, vertices: [fl1P2, vNW2, vNW1, fl1P1]);

    // SW Sidewall F_5 & Flange F_4
    final f5 = PlanarSheetFace(id: 'F_5', role: FaceRole.sideWall, vertices: [fl4P1, pWestBot, pSouthLeft, fl4P2]);
    final f4 = PlanarSheetFace(id: 'F_4', role: FaceRole.returnFlange, vertices: [fl4P2, vSW2, vSW1, fl4P1]);

    // SE Sidewall F_3 & Flange F_2
    final f3 = PlanarSheetFace(id: 'F_3', role: FaceRole.sideWall, vertices: [fl3P1, pSouthRight, pEastBot, fl3P2]);
    final f2 = PlanarSheetFace(id: 'F_2', role: FaceRole.returnFlange, vertices: [fl3P2, vSE2, vSE1, fl3P1]);

    // NE Sidewall F_1 & Flange F_0
    final f1 = PlanarSheetFace(id: 'F_1', role: FaceRole.sideWall, vertices: [fl2P1, pEastTop, pNorthRight, fl2P2]);
    final f0 = PlanarSheetFace(id: 'F_0', role: FaceRole.returnFlange, vertices: [fl2P2, vNE2, vNE1, fl2P1]);

    final newFaces = [f0, f1, f2, f3, f4, f5, f6, f7, f8];

    // 6. Coupler Flaps Synthesis (8 Tabs)
    final includeFlaps = params.includeCouplerFlaps;
    final lf = params.couplerFlapLength;

    final List<CadPoint2D> effectiveOuterContour;
    final List<FoldBendLine> effectiveBends;
    final List<PlanarSheetFace> effectiveFaces;

    if (includeFlaps) {
      // 1. Flap Faces extending collinear with cheek walls
      // NW Wall (F_8):
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
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(base: pWestTop, top: fl1P2, uDir: uNW, flapLength: lf, reverseWinding: true),
        label: 'Coupler Flap P1',
      );

      // SW Wall (F_5):
      //   - Flap SW at West Mouth (extends West along -uSW)
      //   - Flap SW at South Mouth (extends South along uSW)
      final fFlapSwP1 = PlanarSheetFace(
        id: 'F_FLAP_5_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pWestBot,
          top: fl4P1,
          uDir: CadPoint2D(-uSW.x, -uSW.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P1',
      );
      final fFlapSwP4 = PlanarSheetFace(
        id: 'F_FLAP_5_P4',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(base: pSouthLeft, top: fl4P2, uDir: uSW, flapLength: lf, reverseWinding: true),
        label: 'Coupler Flap P4',
      );

      // SE Wall (F_3):
      //   - Flap SE at South Mouth (extends South along -uSE)
      //   - Flap SE at East Mouth (extends East along uSE)
      final fFlapSeP4 = PlanarSheetFace(
        id: 'F_FLAP_3_P4',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: pSouthRight,
          top: fl3P1,
          uDir: CadPoint2D(-uSE.x, -uSE.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P4',
      );
      final fFlapSeP3 = PlanarSheetFace(
        id: 'F_FLAP_3_P3',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(base: pEastBot, top: fl3P2, uDir: uSE, flapLength: lf, reverseWinding: true),
        label: 'Coupler Flap P3',
      );

      // NE Wall (F_1):
      //   - Flap NE at East Mouth (extends East along -uNE)
      //   - Flap NE at North Mouth (extends North along uNE)
      final fFlapNeP3 = PlanarSheetFace(
        id: 'F_FLAP_1_P3',
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
        id: 'F_FLAP_1_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(base: pNorthRight, top: fl2P2, uDir: uNE, flapLength: lf, reverseWinding: true),
        label: 'Coupler Flap P2',
      );

      effectiveFaces = [...newFaces, fFlapNwP1, fFlapNwP2, fFlapSwP1, fFlapSwP4, fFlapSeP4, fFlapSeP3, fFlapNeP3, fFlapNeP2];

      // Flap Bends (realigned parallel to orthogonal port runs)
      final bfNwP2 = FoldBendLine(
        id: 'BF_8_P2',
        p1: pNorthLeft,
        p2: fl1P1,
        targetAngleDeg: thetaNW,
        role: BendLineRole.bend,
        parentFaceId: 'F_8',
        childFaceId: 'F_FLAP_8_P2',
        direction: BendDirection.down,
      );
      final bfNwP1 = FoldBendLine(
        id: 'BF_8_P1',
        p1: pWestTop,
        p2: fl1P2,
        targetAngleDeg: 90.0 - thetaNW,
        role: BendLineRole.bend,
        parentFaceId: 'F_8',
        childFaceId: 'F_FLAP_8_P1',
        direction: BendDirection.down,
      );

      final bfSwP1 = FoldBendLine(
        id: 'BF_5_P1',
        p1: pWestBot,
        p2: fl4P1,
        targetAngleDeg: thetaSW,
        role: BendLineRole.bend,
        parentFaceId: 'F_5',
        childFaceId: 'F_FLAP_5_P1',
        direction: BendDirection.down,
      );
      final bfSwP4 = FoldBendLine(
        id: 'BF_5_P4',
        p1: pSouthLeft,
        p2: fl4P2,
        targetAngleDeg: 90.0 - thetaSW,
        role: BendLineRole.bend,
        parentFaceId: 'F_5',
        childFaceId: 'F_FLAP_5_P4',
        direction: BendDirection.down,
      );

      final bfSeP4 = FoldBendLine(
        id: 'BF_3_P4',
        p1: pSouthRight,
        p2: fl3P1,
        targetAngleDeg: thetaSE,
        role: BendLineRole.bend,
        parentFaceId: 'F_3',
        childFaceId: 'F_FLAP_3_P4',
        direction: BendDirection.down,
      );
      final bfSeP3 = FoldBendLine(
        id: 'BF_3_P3',
        p1: pEastBot,
        p2: fl3P2,
        targetAngleDeg: 90.0 - thetaSE,
        role: BendLineRole.bend,
        parentFaceId: 'F_3',
        childFaceId: 'F_FLAP_3_P3',
        direction: BendDirection.down,
      );

      final bfNeP3 = FoldBendLine(
        id: 'BF_1_P3',
        p1: pEastTop,
        p2: fl2P1,
        targetAngleDeg: thetaNE,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P3',
        direction: BendDirection.down,
      );
      final bfNeP2 = FoldBendLine(
        id: 'BF_1_P2',
        p1: pNorthRight,
        p2: fl2P2,
        targetAngleDeg: 90.0 - thetaNE,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P2',
        direction: BendDirection.down,
      );

      effectiveBends = [...newBends, bfNwP1, bfNwP2, bfSwP1, bfSwP4, bfSeP4, bfSeP3, bfNeP3, bfNeP2];

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
        CadPoint2D(fl3P2.x + lf * uSE.x, fl3P2.y + lf * uSE.y),
        fl3P2,
        vSE2,
        vSE1,
        fl3P1,
        CadPoint2D(fl3P1.x - lf * uSE.x, fl3P1.y - lf * uSE.y),
        CadPoint2D(pSouthRight.x - lf * uSE.x, pSouthRight.y - lf * uSE.y),
        pSouthRight,
        pSouthLeft,
        CadPoint2D(pSouthLeft.x + lf * uSW.x, pSouthLeft.y + lf * uSW.y),
        CadPoint2D(fl4P2.x + lf * uSW.x, fl4P2.y + lf * uSW.y),
        fl4P2,
        vSW2,
        vSW1,
        fl4P1,
        CadPoint2D(fl4P1.x - lf * uSW.x, fl4P1.y - lf * uSW.y),
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
      w1: w1,
      w2: w2,
      w3: w3,
      w4: w4,
      h1: h1,
      h2: h2,
      h3: h3,
      h4: h4,
      pNorthLeft: pNorthLeft,
      pNorthRight: pNorthRight,
      pWestTop: pWestTop,
      pWestBot: pWestBot,
      pSouthLeft: pSouthLeft,
      pSouthRight: pSouthRight,
      pEastTop: pEastTop,
      pEastBot: pEastBot,
      uNW: uNW,
      uSW: uSW,
      uSE: uSE,
      uNE: uNE,
      nNW: nNW,
      nSW: nSW,
      nSE: nSE,
      nNE: nNE,
      includeCouplerFlaps: includeFlaps,
      couplerFlapLength: lf,
      perforationPitch: params.perforationPitch,
    );

    // 8. Update Parameters
    final newParams = Map<String, double>.from(baseline.parameters);
    newParams['width'] = math.max(math.max(w1, w2), math.max(w3, w4));
    newParams['height'] = math.max(math.max(h1, h2), math.max(h3, h4));
    newParams['radius'] = r;
    newParams['port1_width'] = w1;
    newParams['port1_height'] = h1;
    newParams['port2_width'] = w2;
    newParams['port2_height'] = h2;
    newParams['port3_width'] = w3;
    newParams['port3_height'] = h3;
    newParams['port4_width'] = w4;
    newParams['port4_height'] = h4;

    return baseline.copyWith(outerContour: effectiveOuterContour, bends: effectiveBends, faces: effectiveFaces, punches: newPunches, parameters: newParams);
  }

  static List<CncPunchPrimitive> _generatePunches({
    required DsfDocument baseline,
    required double w1,
    required double w2,
    required double w3,
    required double w4,
    required double h1,
    required double h2,
    required double h3,
    required double h4,
    required CadPoint2D pNorthLeft,
    required CadPoint2D pNorthRight,
    required CadPoint2D pWestTop,
    required CadPoint2D pWestBot,
    required CadPoint2D pSouthLeft,
    required CadPoint2D pSouthRight,
    required CadPoint2D pEastTop,
    required CadPoint2D pEastBot,
    required CadPoint2D uNW,
    required CadPoint2D uSW,
    required CadPoint2D uSE,
    required CadPoint2D uNE,
    required CadPoint2D nNW,
    required CadPoint2D nSW,
    required CadPoint2D nSE,
    required CadPoint2D nNE,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 90.0,
    double perforationPitch = 100.0,
  }) {
    final punches = <CncPunchPrimitive>[];
    final sampleSlot = baseline.punches.firstWhere((p) => p.isSlot || p.type == PunchType.obroundSlot, orElse: () => baseline.punches.first);

    int idCounter = 1;
    String nextSlotId() => 'SLOT_${idCounter++}';

    List<double> heightOffsets(double h) {
      if (h < 95.0) {
        return [h / 2.0];
      } else if (h < 175.0) {
        return [h / 2.0 - 25.0, h / 2.0 + 25.0];
      } else {
        return [h / 2.0 - 50.0, h / 2.0, h / 2.0 + 50.0];
      }
    }

    void addCheekPunches({
      required CadPoint2D pStart,
      required CadPoint2D pEnd,
      required double hStart,
      required double hEnd,
      required CadPoint2D uDir,
      required CadPoint2D nDir,
    }) {
      final dx = pEnd.x - pStart.x;
      final dy = pEnd.y - pStart.y;
      final wallLen = math.sqrt(dx * dx + dy * dy);
      final rotDeg = (math.atan2(nDir.y, nDir.x) * 180.0 / math.pi) % 180.0;

      // Holes near pStart (using hStart)
      final vOffsetsStart = heightOffsets(hStart);
      for (final u in [25.0, 75.0]) {
        final hU = hStart + (hEnd - hStart) * (u / wallLen);
        bool anyAdded = false;
        for (final v in vOffsetsStart) {
          // Intelligent placement: must clear bottom bend (>=10mm) and top flange bend line (<= hU - 15mm)
          if (v >= 10.0 && v <= hU - 15.0) {
            punches.add(
              sampleSlot.copyWith(
                id: nextSlotId(),
                center: CadPoint2D(pStart.x + u * uDir.x + v * nDir.x, pStart.y + u * uDir.y + v * nDir.y),
                role: CncPunchRole.coupler,
                rotationDeg: rotDeg,
                isVisible: !includeCouplerFlaps,
              ),
            );
            anyAdded = true;
          }
        }
        if (!anyAdded && hU >= 30.0) {
          final v = hU / 2.0;
          if (v >= 10.0 && v <= hU - 15.0) {
            punches.add(
              sampleSlot.copyWith(
                id: nextSlotId(),
                center: CadPoint2D(pStart.x + u * uDir.x + v * nDir.x, pStart.y + u * uDir.y + v * nDir.y),
                role: CncPunchRole.coupler,
                rotationDeg: rotDeg,
                isVisible: !includeCouplerFlaps,
              ),
            );
          }
        }
      }

      // Holes near pEnd (using hEnd)
      final vOffsetsEnd = heightOffsets(hEnd);
      for (final u in [wallLen - 75.0, wallLen - 25.0]) {
        final hU = hStart + (hEnd - hStart) * (u / wallLen);
        bool anyAdded = false;
        for (final v in vOffsetsEnd) {
          if (v >= 10.0 && v <= hU - 15.0) {
            punches.add(
              sampleSlot.copyWith(
                id: nextSlotId(),
                center: CadPoint2D(pStart.x + u * uDir.x + v * nDir.x, pStart.y + u * uDir.y + v * nDir.y),
                role: CncPunchRole.coupler,
                rotationDeg: rotDeg,
                isVisible: !includeCouplerFlaps,
              ),
            );
            anyAdded = true;
          }
        }
        if (!anyAdded && hU >= 30.0) {
          final v = hU / 2.0;
          if (v >= 10.0 && v <= hU - 15.0) {
            punches.add(
              sampleSlot.copyWith(
                id: nextSlotId(),
                center: CadPoint2D(pStart.x + u * uDir.x + v * nDir.x, pStart.y + u * uDir.y + v * nDir.y),
                role: CncPunchRole.coupler,
                rotationDeg: rotDeg,
                isVisible: !includeCouplerFlaps,
              ),
            );
          }
        }
      }
    }

    // A. NW Sidewall F_8 (pNorthLeft to pWestTop)
    addCheekPunches(pStart: pNorthLeft, pEnd: pWestTop, hStart: h2, hEnd: h1, uDir: uNW, nDir: nNW);

    // B. SW Sidewall F_5 (pWestBot to pSouthLeft)
    addCheekPunches(pStart: pWestBot, pEnd: pSouthLeft, hStart: h1, hEnd: h4, uDir: uSW, nDir: nSW);

    // C. SE Sidewall F_3 (pSouthRight to pEastBot)
    addCheekPunches(pStart: pSouthRight, pEnd: pEastBot, hStart: h4, hEnd: h3, uDir: uSE, nDir: nSE);

    // D. NE Sidewall F_1 (pEastTop to pNorthRight)
    addCheekPunches(pStart: pEastTop, pEnd: pNorthRight, hStart: h3, hEnd: h2, uDir: uNE, nDir: nNE);

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

    // West mouth (Port 1)
    for (final off in mouthOffsets(w1)) {
      punches.add(
        sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(pWestTop.x + 20.0, pWestTop.y + off), role: CncPunchRole.perforation, rotationDeg: 0.0),
      );
    }

    // East mouth (Port 3)
    for (final off in mouthOffsets(w3)) {
      punches.add(
        sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(pEastTop.x - 20.0, pEastTop.y + off), role: CncPunchRole.perforation, rotationDeg: 0.0),
      );
    }

    // North mouth (Port 2)
    for (final off in mouthOffsets(w2)) {
      punches.add(
        sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(pNorthLeft.x + off, pNorthLeft.y + 20.0), role: CncPunchRole.perforation, rotationDeg: 90.0),
      );
    }

    // South mouth (Port 4)
    for (final off in mouthOffsets(w4)) {
      punches.add(
        sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(pSouthLeft.x + off, pSouthLeft.y - 20.0), role: CncPunchRole.perforation, rotationDeg: 90.0),
      );
    }

    // Centerline Floor Slot
    final xMid = (pNorthLeft.x + pNorthRight.x) / 2.0;
    final yMid = (pWestTop.y + pWestBot.y) / 2.0;
    punches.add(sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(xMid, yMid), role: CncPunchRole.perforation, rotationDeg: 0.0));

    // F. Coupler Flap Slots (when flaps active)
    if (includeCouplerFlaps) {
      void addFlapPunches({required CadPoint2D origin, required CadPoint2D uDir, required CadPoint2D vDir, required double height, required double rotDeg}) {
        final slotLen = math.max(10.0, height - 20.0);
        const slotWid = 8.0;
        const slotPitch = 25.0;

        final uCenter = couplerFlapLength / 2.0;
        final uList = [uCenter - slotPitch, uCenter, uCenter + slotPitch];
        final v = height / 2.0;
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

      final rotNW = (math.atan2(nNW.y, nNW.x) * 180.0 / math.pi) % 180.0;
      final rotSW = (math.atan2(nSW.y, nSW.x) * 180.0 / math.pi) % 180.0;
      final rotSE = (math.atan2(nSE.y, nSE.x) * 180.0 / math.pi) % 180.0;
      final rotNE = (math.atan2(nNE.y, nNE.x) * 180.0 / math.pi) % 180.0;

      // NW Wall tabs
      addFlapPunches(origin: pNorthLeft, uDir: CadPoint2D(-uNW.x, -uNW.y), vDir: nNW, height: h2, rotDeg: rotNW);
      addFlapPunches(origin: pWestTop, uDir: uNW, vDir: nNW, height: h1, rotDeg: rotNW);

      // SW Wall tabs
      addFlapPunches(origin: pWestBot, uDir: CadPoint2D(-uSW.x, -uSW.y), vDir: nSW, height: h1, rotDeg: rotSW);
      addFlapPunches(origin: pSouthLeft, uDir: uSW, vDir: nSW, height: h4, rotDeg: rotSW);

      // SE Wall tabs
      addFlapPunches(origin: pSouthRight, uDir: CadPoint2D(-uSE.x, -uSE.y), vDir: nSE, height: h4, rotDeg: rotSE);
      addFlapPunches(origin: pEastBot, uDir: uSE, vDir: nSE, height: h3, rotDeg: rotSE);

      // NE Wall tabs
      addFlapPunches(origin: pEastTop, uDir: CadPoint2D(-uNE.x, -uNE.y), vDir: nNE, height: h3, rotDeg: rotNE);
      addFlapPunches(origin: pNorthRight, uDir: uNE, vDir: nNE, height: h2, rotDeg: rotNE);
    }

    return punches;
  }
}
