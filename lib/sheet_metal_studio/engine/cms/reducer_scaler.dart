// =============================================================================
// reducer_scaler.dart
//
// Dedicated Parametric Analytical Scaling Engine for Straight Reducer Fittings.
// Implements the Analytical Local-Frame Geometry Rule:
// "A reducer consists of a tapered floor web and two slanted cheek sidewalls
//  joining Port 1 and Port 2. All cheek, coupler flap, flange, and punch geometry
//  is evaluated in local orthogonal (u, v) coordinate frames aligned along the
//  slanted floor-cheek bend lines (B3 and B4).
//  Because the local coordinate frame stays strictly attached to the bend line,
//  width scaling and height scaling never shear or rotate the coupler flaps in 2D,
//  and fold kinematics in 3D produce strictly vertical coupler flaps that remain
//  parallel to the duct run axis."
//
// Preserves:
// - All 9 planar faces (F_0 to F_8) with exact topological coincidence
// - All 8 bend lines (B1 to B6, FL1, FL2) with mathematically exact 3D fold angles
// - All rigid coupler punches (SLOT_1 to SLOT_6) governed by the Universal 95mm Rule
// - Continuous closed outer contour (35 vertices) with 100% face-vertex coincidence
// =============================================================================

import 'dart:math' as math;

import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/cms/cms_scaling_model.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';

/// Parameters driving Reducer scaling across Port 1 and Port 2.
class ReducerScaleParameters {
  final double port1Width;
  final double port1Height;
  final double port2Width;
  final double port2Height;

  final double dW1;
  final double dH1;
  final double dW2;
  final double dH2;

  final double sheetThickness;
  final double flangeWidth;

  const ReducerScaleParameters({
    required this.port1Width,
    required this.port1Height,
    required this.port2Width,
    required this.port2Height,
    this.dW1 = 0.0,
    this.dH1 = 0.0,
    this.dW2 = 0.0,
    this.dH2 = 0.0,
    this.sheetThickness = 1.5,
    this.flangeWidth = 10.0,
  });

  bool get hasAnyChange =>
      dW1.abs() > 1e-4 ||
      dH1.abs() > 1e-4 ||
      dW2.abs() > 1e-4 ||
      dH2.abs() > 1e-4;

  /// Factory resolving parameters and deltas from CMS active scaling parameter map.
  factory ReducerScaleParameters.fromCmsParameters(
    Map<String, CmsScalingParameter> params, {
    DsfDocument? baselineDoc,
    double defaultW1 = 100.0,
    double defaultH1 = 100.0,
    double defaultW2 = 50.0,
    double defaultH2 = 50.0,
    double defaultThickness = 1.5,
  }) {
    double getVal(String key, double fallback) {
      final p = params[key];
      if (p != null) return p.currentValue;
      return fallback;
    }

    double getDelta(String key) {
      final p = params[key];
      if (p != null) return p.currentValue - p.baselineValue;
      return 0.0;
    }

    final p1W = params.containsKey('port1_width')
        ? getVal('port1_width', defaultW1)
        : getVal('width', defaultW1);
    final p1H = params.containsKey('port1_height')
        ? getVal('port1_height', defaultH1)
        : getVal('height', defaultH1);
    final p2W = getVal('port2_width', defaultW2);
    final p2H = getVal('port2_height', defaultH2);

    final dW1 = params.containsKey('port1_width')
        ? getDelta('port1_width')
        : getDelta('width');
    final dH1 = params.containsKey('port1_height')
        ? getDelta('port1_height')
        : getDelta('height');
    final dW2 = getDelta('port2_width');
    final dH2 = getDelta('port2_height');

    return ReducerScaleParameters(
      port1Width: p1W,
      port1Height: p1H,
      port2Width: p2W,
      port2Height: p2H,
      dW1: dW1,
      dH1: dH1,
      dW2: dW2,
      dH2: dH2,
      sheetThickness: params['thickness']?.currentValue ?? defaultThickness,
      flangeWidth: params['flange']?.currentValue ?? 10.0,
    );
  }
}

/// Result of Reducer scaling operation.
class ReducerScaleResult {
  final DsfDocument document;
  final bool isValid;
  final Map<String, dynamic> diagnostics;

  const ReducerScaleResult({
    required this.document,
    required this.isValid,
    required this.diagnostics,
  });
}

/// Standalone analytical scaler for Straight Reducer fittings.
class ReducerScaler {
  /// Pure deterministic solver: scales the canonical Reducer template
  /// to the target parameters while preserving all topological relationships,
  /// rigid coupler punches, and fold kinematics.
  static ReducerScaleResult scale({
    required DsfDocument baseline,
    required ReducerScaleParameters parameters,
  }) {
    // 1. Invariance on zero delta:
    if (!parameters.hasAnyChange) {
      return ReducerScaleResult(
        document: baseline,
        isValid: true,
        diagnostics: {'status': 'unchanged_baseline'},
      );
    }

    // 2. Extract baseline floor datum (F_8)
    final floorFace = baseline.faces.firstWhere(
      (f) => f.id == 'F_8' || f.isBaseAnchor || f.role == FaceRole.baseFloor,
      orElse: () => baseline.faces.first,
    );
    final floorVerts = floorFace.vertices;
    final minY = floorVerts.map((v) => v.y).reduce(math.min);
    final maxY = floorVerts.map((v) => v.y).reduce(math.max);
    final lengthL = (maxY - minY).abs() > 1.0 ? (maxY - minY) : 150.0;
    final y1 = minY;
    final y2 = maxY;

    // Baseline floor widths at Port 1 (y1) and Port 2 (y2)
    final port1FloorVerts = floorVerts.where((v) => (v.y - y1).abs() < 1.0).toList();
    final port2FloorVerts = floorVerts.where((v) => (v.y - y2).abs() < 1.0).toList();

    final baseFloorW1 = port1FloorVerts.length >= 2
        ? (port1FloorVerts[0].x - port1FloorVerts[1].x).abs()
        : 97.8243;
    final baseFloorW2 = port2FloorVerts.length >= 2
        ? (port2FloorVerts[0].x - port2FloorVerts[1].x).abs()
        : 45.1757;

    final xMid = (floorVerts.map((v) => v.x).reduce(math.min) +
            floorVerts.map((v) => v.x).reduce(math.max)) /
        2.0;

    final dW1 = parameters.dW1;
    final dH1 = parameters.dH1;
    final dW2 = parameters.dW2;
    final dH2 = parameters.dH2;

    final floorW1 = baseFloorW1 + dW1;
    final floorW2 = baseFloorW2 + dW2;

    final halfW1 = floorW1 / 2.0;
    final halfW2 = floorW2 / 2.0;

    final p1Floor = CadPoint2D(xMid - halfW1, y1);
    final p2Floor = CadPoint2D(xMid + halfW1, y1);
    final p3Floor = CadPoint2D(xMid - halfW2, y2);
    final p4Floor = CadPoint2D(xMid + halfW2, y2);

    // 3. Local coordinate frame setups:
    // Left cheek frame (anchored at p1Floor, u points towards p3Floor along B3):
    final bxL = p3Floor.x - p1Floor.x;
    final byL = p3Floor.y - p1Floor.y;
    final lB = math.sqrt(bxL * bxL + byL * byL);
    final uxL = bxL / lB;
    final uyL = byL / lB;
    final vxL = -uyL;
    final vyL = uxL;

    // Right cheek frame (anchored at p2Floor, u points towards p4Floor along B4):
    final bxR = p4Floor.x - p2Floor.x;
    final byR = p4Floor.y - p2Floor.y;
    final uxR = bxR / lB;
    final uyR = byR / lB;
    final vxR = uyR;
    final vyR = -uxR;

    // Cheek heights (4mm manufacturing clearance from nominal port height):
    final vP1 = (100.0 - 4.0) + dH1; // 96.0 + dH1
    final vP2 = (50.0 - 4.0) + dH2;  // 46.0 + dH2

    // 3D bend angle for flaps:
    final deltaW = halfW1 - halfW2;
    final thetaRad = math.atan2(deltaW, lengthL);
    final thetaDeg = (thetaRad * 180.0 / math.pi).abs();
    final isNormal = deltaW >= -1e-4;

    CadPoint2D toXyLeft(double u, double v) =>
        CadPoint2D(p1Floor.x + u * uxL + v * vxL, p1Floor.y + u * uyL + v * vyL);

    CadPoint2D toXyRight(double u, double v) =>
        CadPoint2D(p2Floor.x + u * uxR + v * vxR, p2Floor.y + u * uyR + v * vyR);

    // Return flange geometry along FL1 / FL2 in (u, v):
    final du = (lB - 5.0) - 11.808;
    final dv = vP2 - vP1;
    final lFl = math.sqrt(du * du + dv * dv);
    final eU = du / lFl;
    final eV = dv / lFl;
    final nU = -eV;
    final nV = eU;
    const dist = 9.385; // return flange depth

    final f5UV0 = lB - 5.0;
    final f5VV0 = vP2;
    final f5UV1 = f5UV0 - 10.24 * eU + dist * nU;
    final f5VV1 = f5VV0 - 10.24 * eV + dist * nV;
    final f5UV3 = 11.808;
    final f5VV3 = vP1;
    final f5UV2 = f5UV3 + 10.92 * eU + dist * nU;
    final f5VV2 = f5VV3 + 10.92 * eV + dist * nV;

    // 4. Construct Scaled Faces
    final faceVertexMap = <String, CadPoint2D>{};
    final newFaces = baseline.faces.map((f) {
      List<CadPoint2D> verts;
      switch (f.id) {
        case 'F_8': // Bottom Base Floor
          verts = [p1Floor, p2Floor, p4Floor, p3Floor];
          break;
        case 'F_7': // Left Cheek Side Wall
          verts = [
            toXyLeft(lB, vP2),
            toXyLeft(lB - 5.0, vP2),
            toXyLeft(11.808, vP1),
            toXyLeft(6.808, vP1),
            toXyLeft(1.808, vP1),
            toXyLeft(0.0, 0.0),
            toXyLeft(lB, 0.0),
          ];
          break;
        case 'F_4': // Port 1 Left Coupler Flap
          verts = [
            toXyLeft(1.808, vP1),
            toXyLeft(-23.192, vP1),
            toXyLeft(-28.198, vP1 - 7.0),
            toXyLeft(-28.264, 7.0),
            toXyLeft(-23.270, 0.0),
            toXyLeft(0.0, 0.0),
          ];
          break;
        case 'F_6': // Port 2 Left Coupler Flap
          verts = [
            toXyLeft(lB, 0.0),
            toXyLeft(lB + 25.0, 0.0),
            toXyLeft(lB + 30.0, 7.0),
            toXyLeft(lB + 30.0, vP2 - 7.0),
            toXyLeft(lB + 25.0, vP2),
            toXyLeft(lB, vP2),
          ];
          break;
        case 'F_5': // Left Return Flange
          verts = [
            toXyLeft(f5UV0, f5VV0),
            toXyLeft(f5UV1, f5VV1),
            toXyLeft(f5UV2, f5VV2),
            toXyLeft(f5UV3, f5VV3),
          ];
          break;
        case 'F_3': // Right Cheek Side Wall
          verts = [
            toXyRight(lB, 0.0),
            toXyRight(0.0, 0.0),
            toXyRight(1.808, vP1),
            toXyRight(6.808, vP1),
            toXyRight(11.808, vP1),
            toXyRight(lB - 5.0, vP2),
            toXyRight(lB, vP2),
          ];
          break;
        case 'F_0': // Port 1 Right Coupler Flap
          verts = [
            toXyRight(0.0, 0.0),
            toXyRight(-23.270, 0.0),
            toXyRight(-28.264, 7.0),
            toXyRight(-28.198, vP1 - 7.0),
            toXyRight(-23.192, vP1),
            toXyRight(1.808, vP1),
          ];
          break;
        case 'F_2': // Port 2 Right Coupler Flap
          verts = [
            toXyRight(lB, vP2),
            toXyRight(lB + 25.0, vP2),
            toXyRight(lB + 30.0, vP2 - 7.0),
            toXyRight(lB + 30.0, 7.0),
            toXyRight(lB + 25.0, 0.0),
            toXyRight(lB, 0.0),
          ];
          break;
        case 'F_1': // Right Return Flange
          verts = [
            toXyRight(f5UV3, f5VV3),
            toXyRight(f5UV2, f5VV2),
            toXyRight(f5UV1, f5VV1),
            toXyRight(f5UV0, f5VV0),
          ];
          break;
        default:
          verts = f.vertices;
      }
      for (int vi = 0; vi < verts.length; vi++) {
        faceVertexMap['${f.id}_v$vi'] = verts[vi];
      }
      return f.copyWith(vertices: verts);
    }).toList();

    // 5. Construct Scaled Bends with 3D Fold Angles
    final newBends = baseline.bends.map((b) {
      CadPoint2D newP1;
      CadPoint2D newP2;
      double newAngle = b.targetAngleDeg;
      BendDirection newDir = b.direction;
      String newLayer = b.layer;

      switch (b.id) {
        case 'B3':
          newP1 = toXyLeft(lB, 0.0);
          newP2 = toXyLeft(0.0, 0.0);
          newAngle = 90.0;
          newDir = BendDirection.up;
          newLayer = 'BEND_UP';
          break;
        case 'B4':
          newP1 = toXyRight(0.0, 0.0);
          newP2 = toXyRight(lB, 0.0);
          newAngle = 90.0;
          newDir = BendDirection.up;
          newLayer = 'BEND_UP';
          break;
        case 'B1':
          newP1 = toXyLeft(0.0, 0.0);
          newP2 = toXyLeft(1.808, vP1);
          newAngle = thetaDeg;
          newDir = isNormal ? BendDirection.up : BendDirection.down;
          newLayer = isNormal ? 'BEND_UP' : 'BEND_DOWN';
          break;
        case 'B2':
          newP1 = toXyRight(0.0, 0.0);
          newP2 = toXyRight(1.808, vP1);
          newAngle = thetaDeg;
          newDir = isNormal ? BendDirection.up : BendDirection.down;
          newLayer = isNormal ? 'BEND_UP' : 'BEND_DOWN';
          break;
        case 'B5':
          newP1 = toXyLeft(lB, 0.0);
          newP2 = toXyLeft(lB, vP2);
          newAngle = thetaDeg;
          newDir = isNormal ? BendDirection.down : BendDirection.up;
          newLayer = isNormal ? 'BEND_DOWN' : 'BEND_UP';
          break;
        case 'B6':
          newP1 = toXyRight(lB, 0.0);
          newP2 = toXyRight(lB, vP2);
          newAngle = thetaDeg;
          newDir = isNormal ? BendDirection.down : BendDirection.up;
          newLayer = isNormal ? 'BEND_DOWN' : 'BEND_UP';
          break;
        case 'FL1':
          newP1 = toXyLeft(11.808, vP1);
          newP2 = toXyLeft(lB - 5.0, vP2);
          newAngle = 90.0;
          newDir = BendDirection.up;
          newLayer = 'BEND_UP';
          break;
        case 'FL2':
          newP1 = toXyRight(lB - 5.0, vP2);
          newP2 = toXyRight(11.808, vP1);
          newAngle = 90.0;
          newDir = BendDirection.up;
          newLayer = 'BEND_UP';
          break;
        default:
          newP1 = b.p1;
          newP2 = b.p2;
      }
      return b.copyWith(
        p1: newP1,
        p2: newP2,
        targetAngleDeg: newAngle,
        direction: newDir,
        layer: newLayer,
      );
    }).toList();

    // 6. Construct Continuous Outer Contour with Exact Face Vertex Coincidence
    final newContour = <CadPoint2D>[];
    for (int ci = 0; ci < baseline.outerContour.length; ci++) {
      final cp = baseline.outerContour[ci];
      CadPoint2D? matchedPt;
      for (final bf in baseline.faces) {
        for (int vi = 0; vi < bf.vertices.length; vi++) {
          final bv = bf.vertices[vi];
          if ((bv.x - cp.x).abs() < 1e-2 && (bv.y - cp.y).abs() < 1e-2) {
            matchedPt = faceVertexMap['${bf.id}_v$vi'];
            break;
          }
        }
        if (matchedPt != null) break;
      }
      newContour.add(matchedPt ?? cp);
    }

    // 7. Synthesize Coupler Punches with Universal 95mm Rule
    final newPunches = <CncPunchPrimitive>[];
    final refSlot = baseline.punches.isNotEmpty
        ? baseline.punches.first
        : const CncPunchPrimitive(
            id: 'SLOT',
            type: PunchType.obroundSlot,
            center: CadPoint2D(0, 0),
            widthMm: 7.0,
            lengthMm: 14.0,
          );

    // Port 1 Punches:
    const uSlot1 = -18.687;
    final vMid1 = vP1 / 2.0;
    final rot1L = (180.0 - thetaDeg) % 360.0;
    final rot1R = thetaDeg % 360.0;

    if (parameters.port1Height >= 95.0) {
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_5',
        center: toXyLeft(uSlot1, vMid1 - 25.0),
        rotationDeg: rot1L,
      ));
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_6',
        center: toXyLeft(uSlot1, vMid1 + 25.0),
        rotationDeg: rot1L,
      ));
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_2',
        center: toXyRight(uSlot1, vMid1 - 25.0),
        rotationDeg: rot1R,
      ));
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_3',
        center: toXyRight(uSlot1, vMid1 + 25.0),
        rotationDeg: rot1R,
      ));
    } else {
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_5',
        center: toXyLeft(uSlot1, vMid1),
        rotationDeg: rot1L,
      ));
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_2',
        center: toXyRight(uSlot1, vMid1),
        rotationDeg: rot1R,
      ));
    }

    // Port 2 Punches:
    final uSlot2 = lB + 20.019;
    final vMid2 = vP2 / 2.0;
    final rot2L = (180.0 - thetaDeg) % 360.0;
    final rot2R = thetaDeg % 360.0;

    if (parameters.port2Height >= 95.0) {
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_4',
        center: toXyLeft(uSlot2, vMid2 + 25.0),
        rotationDeg: rot2L,
      ));
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_4_B',
        center: toXyLeft(uSlot2, vMid2 - 25.0),
        rotationDeg: rot2L,
      ));
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_1',
        center: toXyRight(uSlot2, vMid2 + 25.0),
        rotationDeg: rot2R,
      ));
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_1_B',
        center: toXyRight(uSlot2, vMid2 - 25.0),
        rotationDeg: rot2R,
      ));
    } else {
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_4',
        center: toXyLeft(uSlot2, vMid2),
        rotationDeg: rot2L,
      ));
      newPunches.add(refSlot.copyWith(
        id: 'SLOT_1',
        center: toXyRight(uSlot2, vMid2),
        rotationDeg: rot2R,
      ));
    }

    final updatedParams = Map<String, double>.from(baseline.parameters);
    updatedParams['port1_width'] = parameters.port1Width;
    updatedParams['port1_height'] = parameters.port1Height;
    updatedParams['port2_width'] = parameters.port2Width;
    updatedParams['port2_height'] = parameters.port2Height;
    updatedParams['width'] = parameters.port1Width;
    updatedParams['height'] = parameters.port1Height;

    final scaledDoc = baseline.copyWith(
      faces: newFaces,
      bends: newBends,
      outerContour: newContour,
      punches: newPunches,
      parameters: updatedParams,
    );

    return ReducerScaleResult(
      document: scaledDoc,
      isValid: true,
      diagnostics: {
        'status': 'success',
        'thetaDeg': thetaDeg,
        'lB': lB,
        'port1Width': parameters.port1Width,
        'port1Height': parameters.port1Height,
        'port2Width': parameters.port2Width,
        'port2Height': parameters.port2Height,
      },
    );
  }
}
