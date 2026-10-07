// =============================================================================
// tray_reducer_scaler.dart
//
// Dedicated Parametric Analytical Scaling Engine for Cable Tray Reducers.
// Supports:
// 1. Straight (Concentric / Symmetrical) Reducer
// 2. Left Reducer (Left wall straight at 0°, Right wall tapers inward)
// 3. Right Reducer (Right wall straight at 0°, Left wall tapers inward)
//
// Preserves:
// - Exact 5 planar sheet faces (F_2 floor anchor, F_4 left wall, F_1 right wall,
//   F_3 left flange, F_0 right flange)
// - Exact 4 bend lines (B1, B2, FL1, FL2)
// - Independent Port 1 (W1, H1) and Port 2 (W2, H2) scaling
// - Universal 95mm Coupler Rule & Symmetrically centered floor perforations
// - Optional Coupler Flaps on all 4 corners with parallel duct run folding
// =============================================================================

import 'dart:math' as math;

import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/cms/cms_scaling_model.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';
import 'tray_bend_geometry_solver.dart';

/// Reducer horizontal alignment types.
enum ReducerAlignment {
  straight,
  left,
  right;

  static ReducerAlignment parse(dynamic val) {
    if (val == null) return ReducerAlignment.straight;
    final s = val.toString().toLowerCase().trim();
    if (s == 'left' || s == '1.0' || s == '1') return ReducerAlignment.left;
    if (s == 'right' || s == '2.0' || s == '2') return ReducerAlignment.right;
    return ReducerAlignment.straight;
  }
}

/// Parameters for Cable Tray Reducer scaling.
class TrayReducerScaleParameters {
  final double port1Width;
  final double port1Height;
  final double port2Width;
  final double port2Height;
  final double length;
  final ReducerAlignment alignment;
  final bool includeCouplerFlaps;
  final double couplerFlapLength;
  final double sheetThickness;
  final double flangeWidth;
  final double perforationPitch;
  final bool isOutsideFlange;
  final double? flangeAngle;

  const TrayReducerScaleParameters({
    this.port1Width = 100.0,
    this.port1Height = 50.0,
    this.port2Width = 50.0,
    this.port2Height = 50.0,
    this.length = 250.0,
    this.alignment = ReducerAlignment.straight,
    this.includeCouplerFlaps = false,
    this.couplerFlapLength = 90.0,
    this.sheetThickness = 1.5,
    this.flangeWidth = 13.0,
    this.perforationPitch = 100.0,
    this.isOutsideFlange = false,
    this.flangeAngle,
  });

  factory TrayReducerScaleParameters.fromDocumentAndCms(
    DsfDocument doc,
    Map<String, CmsScalingParameter> params, {
    bool? includeCouplerFlaps,
    double? couplerFlapLength,
    ReducerAlignment? alignment,
    bool? isOutsideFlange,
    double? flangeAngle,
  }) {
    double getVal(String key, double fallback) {
      if (params.containsKey(key)) return params[key]!.currentValue;
      final docVal = doc.parameters[key];
      if (docVal != null) return docVal.toDouble();
      return fallback;
    }

    final p1W = getVal('port1_width', getVal('width', getVal('widthIn', 100.0)));
    final p1H = getVal('port1_height', getVal('height', getVal('port1Height', 50.0)));
    final p2W = getVal('port2_width', getVal('port2Width', getVal('widthOut', 50.0)));
    final p2H = getVal('port2_height', getVal('port2Height', getVal('height', 50.0)));
    final len = getVal('length', 250.0);

    final effectiveFlaps = includeCouplerFlaps ?? ((params['include_coupler_flaps']?.currentValue ?? (doc.parameters['include_coupler_flaps'] ?? 0.0)) > 0.5);
    final effectiveFlapLen = couplerFlapLength ?? params['coupler_flap_length']?.currentValue ?? doc.parameters['coupler_flap_length'] ?? 90.0;

    final effectiveAlignment = alignment ?? ReducerAlignment.parse(params['reducer_alignment']?.currentValue ?? doc.parameters['reducer_alignment']);
    final effectiveIsOutside = isOutsideFlange ?? ((params['flange_direction']?.currentValue ?? doc.parameters['flange_direction'] ?? 0.0) > 0.5);

    final existingFlangeBend = doc.bends.firstWhere(
      (b) => b.id == 'FL1' || b.id == 'FL2' || b.role == BendLineRole.flange,
      orElse: () => doc.bends.firstWhere(
        (b) => b.layer.toUpperCase().contains('FLANGE'),
        orElse: () => const FoldBendLine(id: '', p1: CadPoint2D(0, 0), p2: CadPoint2D(0, 0), targetAngleDeg: 135.0),
      ),
    );
    final effectiveFlangeAngle =
        flangeAngle ??
        params['flange_angle']?.currentValue ??
        doc.parameters['flange_angle'] ??
        (existingFlangeBend.id.isNotEmpty ? existingFlangeBend.targetAngleDeg : null);

    return TrayReducerScaleParameters(
      port1Width: p1W,
      port1Height: p1H,
      port2Width: p2W,
      port2Height: p2H,
      length: len,
      alignment: effectiveAlignment,
      includeCouplerFlaps: effectiveFlaps,
      couplerFlapLength: effectiveFlapLen,
      sheetThickness: (doc.parameters['thickness'] ?? 1.5).toDouble(),
      flangeWidth: (doc.parameters['flange'] ?? 13.0).toDouble(),
      isOutsideFlange: effectiveIsOutside,
      flangeAngle: effectiveFlangeAngle,
    );
  }
}

/// Standalone analytical scaler for Cable Tray Reducer fittings.
class TrayReducerScaler {
  /// Classifier: identifies if [document] is a Cable Tray Reducer fitting.
  static bool isTrayReducer(DsfDocument document) {
    final lowerName = '${document.itemName} ${document.productType}'.toLowerCase();
    if (!lowerName.contains('reducer')) return false;

    // Cable tray reducer has 5 faces (F_0 to F_4) and 4 bends (B1, B2, FL1, FL2).
    // Trunking reducer has 9 faces (F_0 to F_8) with integrated trunking flap bends.
    final has5Faces = document.faces.length == 5;
    final hasB1andFL1 = document.bends.any((b) => b.id == 'B1') && document.bends.any((b) => b.id == 'FL1');
    final isNotTrunking = !lowerName.contains('trunking') && !document.faces.any((f) => f.id == 'F_8');

    return (has5Faces && hasB1andFL1) || (lowerName.contains('tray') && hasB1andFL1) || isNotTrunking;
  }

  /// Scales the baseline document to target dimensions and alignment.
  static DsfDocument scaleWithParameters(DsfDocument baseline, TrayReducerScaleParameters params) {
    final w1 = params.port1Width;
    final h1 = params.port1Height;
    final w2 = params.port2Width;
    final h2 = params.port2Height;
    final lengthL = params.length;
    final wFlange = params.flangeWidth;
    final alignment = params.alignment;
    final includeFlaps = params.includeCouplerFlaps;
    final lf = params.couplerFlapLength;

    // 1. Datum Geometry
    // Centerline datum X from baseline or default 112.6873
    final floorFace = baseline.faces.firstWhere((f) => f.id == 'F_2' || f.isBaseAnchor || f.role == FaceRole.baseFloor, orElse: () => baseline.faces.first);
    final floorVerts = floorFace.vertices;
    final xMid = floorVerts.isNotEmpty ? (floorVerts.map((v) => v.x).reduce(math.min) + floorVerts.map((v) => v.x).reduce(math.max)) / 2.0 : 112.6873;

    // Port 1 Mouth (Inlet) at y = 0
    final p1Left = CadPoint2D(xMid - w1 / 2.0, 0.0);
    final p1Right = CadPoint2D(xMid + w1 / 2.0, 0.0);

    // Port 2 Mouth (Outlet) at y = lengthL
    final CadPoint2D p2Left;
    final CadPoint2D p2Right;

    switch (alignment) {
      case ReducerAlignment.left:
        // Left wall is straight (0° to Y axis, collinear with Port 1 Left)
        // Right wall tapers inward to meet Port 2 width
        p2Left = CadPoint2D(p1Left.x, lengthL);
        p2Right = CadPoint2D(p1Left.x + w2, lengthL);
        break;
      case ReducerAlignment.right:
        // Right wall is straight (0° to Y axis, collinear with Port 1 Right)
        // Left wall tapers inward to meet Port 2 width
        p2Right = CadPoint2D(p1Right.x, lengthL);
        p2Left = CadPoint2D(p1Right.x - w2, lengthL);
        break;
      case ReducerAlignment.straight:
        // Symmetrical concentric taper about xMid
        p2Left = CadPoint2D(xMid - w2 / 2.0, lengthL);
        p2Right = CadPoint2D(xMid + w2 / 2.0, lengthL);
        break;
    }

    // 2. Sidewall Vectors & Outward Normals
    // Left cheek bend B1: from p2Left to p1Left
    final dxLeft = p1Left.x - p2Left.x;
    final dyLeft = p1Left.y - p2Left.y; // -lengthL
    final lenLeft = math.sqrt(dxLeft * dxLeft + dyLeft * dyLeft);
    final uLeft = CadPoint2D(dxLeft / lenLeft, dyLeft / lenLeft);
    // Outward normal in 2D flat sheet (points West/Left): (u.y, -u.x)
    final nLeft = CadPoint2D(uLeft.y, -uLeft.x);
    final thetaLeft = math.atan2(uLeft.x.abs(), uLeft.y.abs()) * 180.0 / math.pi;

    // Right cheek bend B2: from p2Right to p1Right
    final dxRight = p1Right.x - p2Right.x;
    final dyRight = p1Right.y - p2Right.y; // -lengthL
    final lenRight = math.sqrt(dxRight * dxRight + dyRight * dyRight);
    final uRight = CadPoint2D(dxRight / lenRight, dyRight / lenRight);
    // Outward normal in 2D flat sheet (points East/Right): (-u.y, u.x)
    final nRight = CadPoint2D(-uRight.y, uRight.x);
    final thetaRight = math.atan2(uRight.x.abs(), uRight.y.abs()) * 180.0 / math.pi;

    final isOutside = params.isOutsideFlange;
    final flangeDir = isOutside ? BendDirection.down : BendDirection.up;
    final flangeLayer = isOutside ? 'BEND_DOWN' : 'BEND_UP';
    final existingFlangeBend = baseline.bends.firstWhere(
      (b) => b.id == 'FL1' || b.id == 'FL2' || b.role == BendLineRole.flange,
      orElse: () => baseline.bends.firstWhere(
        (b) => b.layer.toUpperCase().contains('FLANGE'),
        orElse: () => const FoldBendLine(id: '', p1: CadPoint2D(0, 0), p2: CadPoint2D(0, 0), targetAngleDeg: 135.0),
      ),
    );
    final flangeAngle =
        params.flangeAngle ?? baseline.parameters['flange_angle'] ?? (existingFlangeBend.id.isNotEmpty ? existingFlangeBend.targetAngleDeg : 135.0);

    // 3. Flange Bend Lines & Outer Corners
    // Left Sidewall (F_4) top edge (FL1) & flange (F_3) outer edge
    // Slants from h2 at Port 2 to h1 at Port 1
    final fl1P1 = CadPoint2D(p2Left.x + h2 * nLeft.x, p2Left.y + h2 * nLeft.y);
    final fl1P2 = CadPoint2D(p1Left.x + h1 * nLeft.x, p1Left.y + h1 * nLeft.y);

    // Left Flange outward normal and shift:
    final vFL1 = CadPoint2D(fl1P1.x - fl1P2.x, fl1P1.y - fl1P2.y);
    final lenFL1 = math.sqrt(vFL1.x * vFL1.x + vFL1.y * vFL1.y);
    final uFL1 = lenFL1 > 1e-9 ? CadPoint2D(vFL1.x / lenFL1, vFL1.y / lenFL1) : const CadPoint2D(0.0, 1.0);
    CadPoint2D nFL1 = CadPoint2D(-uFL1.y, uFL1.x);
    if (nFL1.x * nLeft.x + nFL1.y * nLeft.y < 0) {
      nFL1 = CadPoint2D(uFL1.y, -uFL1.x);
    }
    final sLeft = _computeFlangeShift(
      p1Base: p1Left,
      p2Base: p2Left,
      flP1: fl1P2,
      flP2: fl1P1,
      nFL: nFL1,
      uFL: uFL1,
      wFlange: wFlange,
      isLeft: true,
      isOutside: isOutside,
      flangeAngleDeg: flangeAngle,
    );
    final vLeft1 = CadPoint2D(fl1P1.x + wFlange * nFL1.x + sLeft * uFL1.x, fl1P1.y + wFlange * nFL1.y + sLeft * uFL1.y);
    final vLeft2 = CadPoint2D(fl1P2.x + wFlange * nFL1.x + sLeft * uFL1.x, fl1P2.y + wFlange * nFL1.y + sLeft * uFL1.y);

    // Right Sidewall (F_1) top edge (FL2) & flange (F_0) outer edge
    // Slants from h1 at Port 1 to h2 at Port 2
    final fl2P1 = CadPoint2D(p1Right.x + h1 * nRight.x, p1Right.y + h1 * nRight.y);
    final fl2P2 = CadPoint2D(p2Right.x + h2 * nRight.x, p2Right.y + h2 * nRight.y);

    // Right Flange outward normal and shift:
    final vFL2 = CadPoint2D(fl2P2.x - fl2P1.x, fl2P2.y - fl2P1.y);
    final lenFL2 = math.sqrt(vFL2.x * vFL2.x + vFL2.y * vFL2.y);
    final uFL2 = lenFL2 > 1e-9 ? CadPoint2D(vFL2.x / lenFL2, vFL2.y / lenFL2) : const CadPoint2D(0.0, 1.0);
    CadPoint2D nFL2 = CadPoint2D(-uFL2.y, uFL2.x);
    if (nFL2.x * nRight.x + nFL2.y * nRight.y < 0) {
      nFL2 = CadPoint2D(uFL2.y, -uFL2.x);
    }
    final sRight = _computeFlangeShift(
      p1Base: p1Right,
      p2Base: p2Right,
      flP1: fl2P1,
      flP2: fl2P2,
      nFL: nFL2,
      uFL: uFL2,
      wFlange: wFlange,
      isLeft: false,
      isOutside: isOutside,
      flangeAngleDeg: flangeAngle,
    );
    final vRight1 = CadPoint2D(fl2P1.x + wFlange * nFL2.x + sRight * uFL2.x, fl2P1.y + wFlange * nFL2.y + sRight * uFL2.y);
    final vRight2 = CadPoint2D(fl2P2.x + wFlange * nFL2.x + sRight * uFL2.x, fl2P2.y + wFlange * nFL2.y + sRight * uFL2.y);

    // 4. Faces
    // Central Base Floor F_2 (Anchor)
    final f2 = PlanarSheetFace(id: 'F_2', role: FaceRole.baseFloor, vertices: [p2Right, p2Left, p1Left, p1Right], isBaseAnchor: true, label: 'Base Floor');

    // Left Sidewall F_4 & Flange F_3
    final f4 = PlanarSheetFace(id: 'F_4', role: FaceRole.sideWall, vertices: [fl1P2, p1Left, p2Left, fl1P1], label: 'Left Sidewall');
    final f3 = PlanarSheetFace(id: 'F_3', role: FaceRole.returnFlange, vertices: [fl1P1, vLeft1, vLeft2, fl1P2], label: 'Left Flange');

    // Right Sidewall F_1 & Flange F_0
    final f1 = PlanarSheetFace(id: 'F_1', role: FaceRole.sideWall, vertices: [fl2P2, p2Right, p1Right, fl2P1], label: 'Right Sidewall');
    final f0 = PlanarSheetFace(id: 'F_0', role: FaceRole.returnFlange, vertices: [fl2P1, vRight1, vRight2, fl2P2], label: 'Right Flange');

    final newFaces = [f0, f1, f2, f3, f4];

    // 5. Bends
    final b1 = FoldBendLine(id: 'B1', p1: p2Left, p2: p1Left, targetAngleDeg: 90.0, role: BendLineRole.bend, parentFaceId: 'F_2', childFaceId: 'F_4');
    final b2 = FoldBendLine(id: 'B2', p1: p2Right, p2: p1Right, targetAngleDeg: 90.0, role: BendLineRole.bend, parentFaceId: 'F_2', childFaceId: 'F_1');
    final fl1 = FoldBendLine(
      id: 'FL1',
      p1: fl1P1,
      p2: fl1P2,
      targetAngleDeg: flangeAngle,
      role: BendLineRole.flange,
      parentFaceId: 'F_4',
      childFaceId: 'F_3',
      direction: flangeDir,
      layer: flangeLayer,
    );
    final fl2 = FoldBendLine(
      id: 'FL2',
      p1: fl2P1,
      p2: fl2P2,
      targetAngleDeg: flangeAngle,
      role: BendLineRole.flange,
      parentFaceId: 'F_1',
      childFaceId: 'F_0',
      direction: flangeDir,
      layer: flangeLayer,
    );

    final newBends = [b1, b2, fl1, fl2];

    // 6. Base Outer Contour (without coupler flaps)
    final baseOuterContour = [p1Left, p1Right, fl2P1, vRight1, vRight2, fl2P2, p2Right, p2Left, fl1P1, vLeft1, vLeft2, fl1P2, p1Left];

    // 7. Coupler Flaps (4 Tabs) when enabled
    final List<PlanarSheetFace> effectiveFaces;
    final List<FoldBendLine> effectiveBends;
    final List<CadPoint2D> effectiveOuterContour;

    if (includeFlaps) {
      // Flap 1: Left Sidewall at Port 1 (extends North along uLeft)
      final fFlapLeftP1 = PlanarSheetFace(
        id: 'F_FLAP_4_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(base: p1Left, top: fl1P2, uDir: uLeft, flapLength: lf, reverseWinding: false),
        label: 'Coupler Flap P1 Left',
      );

      // Flap 2: Left Sidewall at Port 2 (extends South along -uLeft)
      final fFlapLeftP2 = PlanarSheetFace(
        id: 'F_FLAP_4_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: p2Left,
          top: fl1P1,
          uDir: CadPoint2D(-uLeft.x, -uLeft.y),
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap P2 Left',
      );

      // Flap 3: Right Sidewall at Port 1 (extends North along uRight)
      final fFlapRightP1 = PlanarSheetFace(
        id: 'F_FLAP_1_P1',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(base: p1Right, top: fl2P1, uDir: uRight, flapLength: lf, reverseWinding: true),
        label: 'Coupler Flap P1 Right',
      );

      // Flap 4: Right Sidewall at Port 2 (extends South along -uRight)
      final fFlapRightP2 = PlanarSheetFace(
        id: 'F_FLAP_1_P2',
        role: FaceRole.sideWall,
        vertices: TrayBendGeometrySolver.createChamferedFlapVertices(
          base: p2Right,
          top: fl2P2,
          uDir: CadPoint2D(-uRight.x, -uRight.y),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap P2 Right',
      );

      effectiveFaces = [...newFaces, fFlapLeftP1, fFlapLeftP2, fFlapRightP1, fFlapRightP2];

      // Flap bends: fold to align strictly parallel to duct run
      final bfLeftP1 = FoldBendLine(
        id: 'BF_4_P1',
        p1: p1Left,
        p2: fl1P2,
        targetAngleDeg: thetaLeft,
        role: BendLineRole.bend,
        parentFaceId: 'F_4',
        childFaceId: 'F_FLAP_4_P1',
        direction: BendDirection.up,
      );
      final bfLeftP2 = FoldBendLine(
        id: 'BF_4_P2',
        p1: p2Left,
        p2: fl1P1,
        targetAngleDeg: thetaLeft,
        role: BendLineRole.bend,
        parentFaceId: 'F_4',
        childFaceId: 'F_FLAP_4_P2',
        direction: BendDirection.down,
      );
      final bfRightP1 = FoldBendLine(
        id: 'BF_1_P1',
        p1: p1Right,
        p2: fl2P1,
        targetAngleDeg: thetaRight,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P1',
        direction: BendDirection.up,
      );
      final bfRightP2 = FoldBendLine(
        id: 'BF_1_P2',
        p1: p2Right,
        p2: fl2P2,
        targetAngleDeg: thetaRight,
        role: BendLineRole.bend,
        parentFaceId: 'F_1',
        childFaceId: 'F_FLAP_1_P2',
        direction: BendDirection.down,
      );

      effectiveBends = [...newBends, bfLeftP1, bfLeftP2, bfRightP1, bfRightP2];

      effectiveOuterContour = [
        p1Left,
        p1Right,
        CadPoint2D(p1Right.x + lf * uRight.x, p1Right.y + lf * uRight.y),
        CadPoint2D(fl2P1.x + lf * uRight.x, fl2P1.y + lf * uRight.y),
        fl2P1,
        vRight1,
        vRight2,
        fl2P2,
        CadPoint2D(fl2P2.x - lf * uRight.x, fl2P2.y - lf * uRight.y),
        CadPoint2D(p2Right.x - lf * uRight.x, p2Right.y - lf * uRight.y),
        p2Right,
        p2Left,
        CadPoint2D(p2Left.x - lf * uLeft.x, p2Left.y - lf * uLeft.y),
        CadPoint2D(fl1P1.x - lf * uLeft.x, fl1P1.y - lf * uLeft.y),
        fl1P1,
        vLeft1,
        vLeft2,
        fl1P2,
        CadPoint2D(fl1P2.x + lf * uLeft.x, fl1P2.y + lf * uLeft.y),
        CadPoint2D(p1Left.x + lf * uLeft.x, p1Left.y + lf * uLeft.y),
        p1Left,
      ];
    } else {
      effectiveFaces = newFaces;
      effectiveBends = newBends;
      effectiveOuterContour = baseOuterContour;
    }

    // 8. Punches Generation per Universal 95mm & Centered Mouth Rules
    final newPunches = _generatePunches(
      baseline: baseline,
      w1: w1,
      h1: h1,
      w2: w2,
      h2: h2,
      p1Left: p1Left,
      p1Right: p1Right,
      p2Left: p2Left,
      p2Right: p2Right,
      uLeft: uLeft,
      nLeft: nLeft,
      uRight: uRight,
      nRight: nRight,
      includeCouplerFlaps: includeFlaps,
      couplerFlapLength: lf,
    );

    // 9. Update Parameters & Metadata
    final newParams = Map<String, double>.from(baseline.parameters);
    newParams['width'] = math.max(w1, w2);
    newParams['widthIn'] = w1;
    newParams['widthOut'] = w2;
    newParams['height'] = math.max(h1, h2);
    newParams['port1_width'] = w1;
    newParams['port1_height'] = h1;
    newParams['port2_width'] = w2;
    newParams['port2_height'] = h2;
    newParams['port1Width'] = w1;
    newParams['port1Height'] = h1;
    newParams['port2Width'] = w2;
    newParams['port2Height'] = h2;
    newParams['length'] = lengthL;
    newParams['reducer_alignment'] = alignment == ReducerAlignment.left ? 1.0 : (alignment == ReducerAlignment.right ? 2.0 : 0.0);
    newParams['flange_direction'] = isOutside ? 1.0 : 0.0;
    newParams['flange_angle'] = flangeAngle;

    final newMetadata = Map<String, dynamic>.from(baseline.metadata);
    final variantStr = alignment == ReducerAlignment.left ? 'Left Reducer' : (alignment == ReducerAlignment.right ? 'Right Reducer' : 'Reducer (straight)');
    newMetadata['fittingVariant'] = variantStr;
    newMetadata['variantName'] = variantStr;
    newMetadata['reducer_alignment'] = alignment.name;

    if (newMetadata['fittingMetadata'] is Map) {
      final fittingMeta = Map<String, dynamic>.from(newMetadata['fittingMetadata'] as Map);
      fittingMeta['variantName'] = variantStr;
      final fParams = Map<String, dynamic>.from(fittingMeta['parameters'] as Map? ?? {});
      fParams['widthIn'] = w1;
      fParams['widthOut'] = w2;
      fParams['height'] = math.max(h1, h2);
      fParams['port1Width'] = w1;
      fParams['port1Height'] = h1;
      fParams['port2Width'] = w2;
      fParams['port2Height'] = h2;
      fParams['length'] = lengthL;
      fParams['reducer_alignment'] = alignment.name;
      fittingMeta['parameters'] = fParams;
      newMetadata['fittingMetadata'] = fittingMeta;
    }

    return baseline.copyWith(
      outerContour: effectiveOuterContour,
      bends: effectiveBends,
      faces: effectiveFaces,
      punches: newPunches,
      parameters: newParams,
      metadata: newMetadata,
    );
  }

  static List<CncPunchPrimitive> _generatePunches({
    required DsfDocument baseline,
    required double w1,
    required double h1,
    required double w2,
    required double h2,
    required CadPoint2D p1Left,
    required CadPoint2D p1Right,
    required CadPoint2D p2Left,
    required CadPoint2D p2Right,
    required CadPoint2D uLeft,
    required CadPoint2D nLeft,
    required CadPoint2D uRight,
    required CadPoint2D nRight,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 90.0,
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

    // A. Sidewall Coupler Punches
    void addCheekCouplers({
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

      // Holes near pStart (Port 2, using hStart = h2)
      final vOffsetsStart = heightOffsets(hStart);
      for (final u in [25.0, 75.0]) {
        final hU = hStart + (hEnd - hStart) * (u / wallLen);
        bool anyAdded = false;
        for (final v in vOffsetsStart) {
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

      // Holes near pEnd (Port 1, using hEnd = h1)
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

    // Left Sidewall F_4 (from p2Left to p1Left)
    addCheekCouplers(pStart: p2Left, pEnd: p1Left, hStart: h2, hEnd: h1, uDir: uLeft, nDir: nLeft);

    // Right Sidewall F_1 (from p2Right to p1Right)
    addCheekCouplers(pStart: p2Right, pEnd: p1Right, hStart: h2, hEnd: h1, uDir: uRight, nDir: nRight);

    // B. Floor Web Perforations at Mouths
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

    // Port 1 Mouth (Inlet at y = 0, slots offset +20mm in Y)
    for (final off in mouthOffsets(w1)) {
      punches.add(
        sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(p1Left.x + off, p1Left.y + 20.0), role: CncPunchRole.perforation, rotationDeg: 90.0),
      );
    }

    // Port 2 Mouth (Outlet at y = lengthL, slots offset -20mm in Y)
    for (final off in mouthOffsets(w2)) {
      punches.add(
        sampleSlot.copyWith(id: nextSlotId(), center: CadPoint2D(p2Left.x + off, p2Left.y - 20.0), role: CncPunchRole.perforation, rotationDeg: 90.0),
      );
    }

    // C. Coupler Flap Slots (when flaps active)
    if (includeCouplerFlaps) {
      void addFlapPunches({required CadPoint2D origin, required CadPoint2D uDir, required CadPoint2D vDir, required double height, required double rotDeg}) {
        final slotLen = math.max(10.0, height - 20.0);
        const slotWid = 8.0;
        const slotPitch = 25.0;

        final uCenter = couplerFlapLength / 2.0;
        final uList = [uCenter - slotPitch, uCenter, uCenter + slotPitch];
        final v = height / 2.0;
        if (couplerFlapLength < 20.0) return;
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

      final rotLeft = (math.atan2(nLeft.y, nLeft.x) * 180.0 / math.pi) % 180.0;
      final rotRight = (math.atan2(nRight.y, nRight.x) * 180.0 / math.pi) % 180.0;

      // Port 1 Flaps (using h1)
      addFlapPunches(origin: p1Left, uDir: uLeft, vDir: nLeft, height: h1, rotDeg: rotLeft);
      addFlapPunches(origin: p1Right, uDir: uRight, vDir: nRight, height: h1, rotDeg: rotRight);

      // Port 2 Flaps (using h2)
      addFlapPunches(origin: p2Left, uDir: CadPoint2D(-uLeft.x, -uLeft.y), vDir: nLeft, height: h2, rotDeg: rotLeft);
      addFlapPunches(origin: p2Right, uDir: CadPoint2D(-uRight.x, -uRight.y), vDir: nRight, height: h2, rotDeg: rotRight);
    }

    return punches;
  }

  /// Calculates the 2D shift along the flange bend line so that in 3D, the outer flange corners
  /// lie strictly in the port mouth planes (Y = 0.0 at Port 1 and Y = lengthL at Port 2),
  /// keeping the flange ends straight and flush with the product's edge.
  static double _computeFlangeShift({
    required CadPoint2D p1Base,
    required CadPoint2D p2Base,
    required CadPoint2D flP1,
    required CadPoint2D flP2,
    required CadPoint2D nFL,
    required CadPoint2D uFL,
    required double wFlange,
    required bool isLeft,
    required bool isOutside,
    required double flangeAngleDeg,
  }) {
    // 1. Base bend B (from p2Base to p1Base)
    final p2_3d = CadPoint3D(p2Base.x, p2Base.y, 0.0);

    final dx = p1Base.x - p2Base.x;
    final dy = p1Base.y - p2Base.y;
    final bLen = math.sqrt(dx * dx + dy * dy);
    final bLine = CadPoint2D(dx / bLen, dy / bLen);
    final nWall = isLeft ? CadPoint2D(bLine.y, -bLine.x) : CadPoint2D(-bLine.y, bLine.x);
    final bCrossZ = bLine.x * nWall.y - bLine.y * nWall.x;

    var axisB = CadPoint3D(dx / bLen, dy / bLen, 0.0);
    if (bCrossZ < 0) {
      axisB = CadPoint3D(-axisB.x, -axisB.y, 0.0);
    }
    final axBP2 = CadPoint3D(p2_3d.x + axisB.x, p2_3d.y + axisB.y, 0.0);

    // Bend endpoints for FL in DSF document:
    // Left: FL1 is from flP2 (at Port 2) to flP1 (at Port 1)
    // Right: FL2 is from flP1 (at Port 1) to flP2 (at Port 2)
    final bendFlP1 = isLeft ? flP2 : flP1;
    final bendFlP2 = isLeft ? flP1 : flP2;

    final flP1_3d = _rotAxis(p2_3d, axBP2, 90.0, CadPoint3D(bendFlP1.x, bendFlP1.y, 0.0));
    final flP2_3d = _rotAxis(p2_3d, axBP2, 90.0, CadPoint3D(bendFlP2.x, bendFlP2.y, 0.0));

    final flDirDx = bendFlP2.x - bendFlP1.x;
    final flDirDy = bendFlP2.y - bendFlP1.y;
    final flLen = math.sqrt(flDirDx * flDirDx + flDirDy * flDirDy);
    final flLine = CadPoint2D(flDirDx / flLen, flDirDy / flLen);
    final flCrossZ = flLine.x * nFL.y - flLine.y * nFL.x;

    var axisFL = CadPoint3D(flP2_3d.x - flP1_3d.x, flP2_3d.y - flP1_3d.y, flP2_3d.z - flP1_3d.z);
    final flLen3 = math.sqrt(axisFL.x * axisFL.x + axisFL.y * axisFL.y + axisFL.z * axisFL.z);
    axisFL = CadPoint3D(axisFL.x / flLen3, axisFL.y / flLen3, axisFL.z / flLen3);
    if (flCrossZ < 0) {
      axisFL = CadPoint3D(-axisFL.x, -axisFL.y, -axisFL.z);
    }
    final axFLP2 = CadPoint3D(flP1_3d.x + axisFL.x, flP1_3d.y + axisFL.y, flP1_3d.z + axisFL.z);

    final flSign = isOutside ? -1.0 : 1.0;
    CadPoint3D fold(CadPoint2D pt) {
      final pS1 = _rotAxis(p2_3d, axBP2, 90.0, CadPoint3D(pt.x, pt.y, 0.0));
      return _rotAxis(flP1_3d, axFLP2, flSign * flangeAngleDeg, pS1);
    }

    // Exact affine root at flP1 (Port 1 mouth, target y = 0.0 in 3D)
    final y0 = fold(CadPoint2D(flP1.x + wFlange * nFL.x, flP1.y + wFlange * nFL.y)).y;
    final y1 = fold(CadPoint2D(flP1.x + wFlange * nFL.x + uFL.x, flP1.y + wFlange * nFL.y + uFL.y)).y;
    final dyPt = y1 - y0;
    return dyPt.abs() > 1e-9 ? -y0 / dyPt : 0.0;
  }

  /// Exact 3D Rodrigues vector rotation around an arbitrary axis from p1 to p2.
  static CadPoint3D _rotAxis(CadPoint3D p1, CadPoint3D p2, double angleDeg, CadPoint3D pt) {
    final rad = angleDeg * math.pi / 180.0;
    final ax = p2.x - p1.x;
    final ay = p2.y - p1.y;
    final az = p2.z - p1.z;
    final len = math.sqrt(ax * ax + ay * ay + az * az);
    if (len < 1e-9) return pt;
    final ux = ax / len;
    final uy = ay / len;
    final uz = az / len;

    final px = pt.x - p1.x;
    final py = pt.y - p1.y;
    final pz = pt.z - p1.z;

    final cx = uy * pz - uz * py;
    final cy = uz * px - ux * pz;
    final cz = ux * py - uy * px;

    final dot = ux * px + uy * py + uz * pz;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);

    final rx = px * cosA + cx * sinA + ux * dot * (1.0 - cosA);
    final ry = py * cosA + cy * sinA + uy * dot * (1.0 - cosA);
    final rz = pz * cosA + cz * sinA + uz * dot * (1.0 - cosA);

    return CadPoint3D(rx + p1.x, ry + p1.y, rz + p1.z);
  }
}
