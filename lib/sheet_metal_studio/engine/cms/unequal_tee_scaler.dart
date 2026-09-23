// =============================================================================
// unequal_tee_scaler.dart
//
// Dedicated Parametric Scaling Engine for Unequal Tee Fittings.
// Implements the Analytical Geometry Rule:
// "Port heights are independent inputs. Common body height is a derived value
//  equal to the maximum port height: Hbody = max(H1, H2, H3).
//  A port's coupler area always follows its own port height, while the shared
//  body follows the maximum. The vertical difference between the body and
//  each port defines that port's step/notch."
//
// Preserves:
// - All planar faces (F_0 to F_10) with complete kinematic hierarchy
// - All bend lines (B1 to B7, FL1, FL2, FL3) with parent/child face links
// - All 12 corner arcs (ARC_BND_1 to ARC_BND_12) at exact tangent corners
// - All 10 rigid coupler punches (SLOT_3 to SLOT_12)
// - Continuous closed outer contour with exact face vertex coincidence
//
// References:
// - TruFold_Studio_Unequal_Tee_Scaling_Agent_Spec.md
// - Unequal Tee scaling details.pdf
// - assets/dxf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf
// =============================================================================

import 'dart:math' as math;
import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/cms/cms_scaling_model.dart';
import '../../models/planar_sheet_face.dart';

/// Explicit parameters driving Unequal Tee scaling.
class UnequalTeeScaleParameters {
  final double port1Width;
  final double port1Height;
  final double port2Width;
  final double port2Height;
  final double port3Width;
  final double port3Height;
  final double dW1;
  final double dH1;
  final double dW2;
  final double dH2;
  final double dW3;
  final double dH3;
  final double sheetThickness;
  final double flangeWidth;

  const UnequalTeeScaleParameters({
    required this.port1Width,
    required this.port1Height,
    required this.port2Width,
    required this.port2Height,
    required this.port3Width,
    required this.port3Height,
    this.dW1 = 0.0,
    this.dH1 = 0.0,
    this.dW2 = 0.0,
    this.dH2 = 0.0,
    this.dW3 = 0.0,
    this.dH3 = 0.0,
    this.sheetThickness = 1.5,
    this.flangeWidth = 10.0,
  });

  /// Factory resolving parameters and deltas from CMS active scaling parameter map.
  factory UnequalTeeScaleParameters.fromCmsParameters(
    Map<String, CmsScalingParameter> params, {
    double defaultW1 = 50.0,
    double defaultH1 = 100.0,
    double defaultW2 = 50.0,
    double defaultH2 = 50.0,
    double defaultW3 = 100.0,
    double defaultH3 = 100.0,
    double defaultThickness = 1.5,
  }) {
    double getVal(String key, double fallback) {
      final p = params[key];
      if (p != null) return p.currentValue;
      return fallback;
    }

    double getDelta(String key, double fallbackBaseline) {
      final p = params[key];
      if (p != null) return p.currentValue - p.baselineValue;
      return 0.0;
    }

    final p1W = getVal('port1_width', defaultW1);
    final p1H = getVal('port1_height', defaultH1);
    final p2W = getVal('port2_width', defaultW2);
    final p2H = getVal('port2_height', defaultH2);
    final p3W = getVal('port3_width', defaultW3);
    final p3H = getVal('port3_height', defaultH3);

    final dW1 = getDelta('port1_width', defaultW1);
    final dW2 = getDelta('port2_width', defaultW2);
    final dW3 = getDelta('port3_width', defaultW3);
    final dH1 = getDelta('port1_height', defaultH1);
    final dH2 = getDelta('port2_height', defaultH2);
    final dH3 = getDelta('port3_height', defaultH3);

    return UnequalTeeScaleParameters(
      port1Width: p1W,
      port1Height: p1H,
      port2Width: p2W,
      port2Height: p2H,
      port3Width: p3W,
      port3Height: p3H,
      dW1: dW1,
      dH1: dH1,
      dW2: dW2,
      dH2: dH2,
      dW3: dW3,
      dH3: dH3,
      sheetThickness: getVal('thickness', defaultThickness),
      flangeWidth: getVal('flange', 10.0),
    );
  }

  /// Whether any parameter has changed relative to its baseline.
  bool get hasAnyChange =>
      dW1.abs() > 1e-4 ||
      dH1.abs() > 1e-4 ||
      dW2.abs() > 1e-4 ||
      dH2.abs() > 1e-4 ||
      dW3.abs() > 1e-4 ||
      dH3.abs() > 1e-4 ||
      (port1Height - 100.0).abs() > 1e-4 ||
      (port2Height - 50.0).abs() > 1e-4 ||
      (port3Height - 100.0).abs() > 1e-4;

  /// Product-wide maximum height governing core body height.
  double get maxHeight => math.max(port1Height, math.max(port2Height, port3Height));
}

/// Result of an Unequal Tee scale operation.
class UnequalTeeScaleResult {
  final DsfDocument document;
  final bool isValid;
  final String? errorMessage;
  final Map<String, dynamic> diagnostics;

  const UnequalTeeScaleResult({
    required this.document,
    required this.isValid,
    this.errorMessage,
    this.diagnostics = const {},
  });
}

/// Standalone analytical scaler for Unequal Tee fittings.
class UnequalTeeScaler {
  static const Set<String> _rightFaceIds = {'F_7', 'F_4', 'F_5', 'F_6'};
  static const Set<String> _rightBendIds = {'B2', 'B4', 'B6', 'FL2'};
  static const Set<String> _rightPunchIds = {'SLOT_4', 'SLOT_6', 'SLOT_12'};
  static const Set<String> _rightArcIds = {'ARC_BND_4', 'ARC_BND_5', 'ARC_BND_6', 'ARC_BND_7'};

  static const Set<String> _backFaceIds = {'F_9', 'F_8'};
  static const Set<String> _backBendIds = {'B3', 'FL3'};
  static const Set<String> _backPunchIds = {'SLOT_7', 'SLOT_8', 'SLOT_11'};
  static const Set<String> _backArcIds = {'ARC_BND_1', 'ARC_BND_2', 'ARC_BND_3', 'ARC_BND_10'};

  static const Set<String> _leftFaceIds = {'F_3', 'F_1', 'F_0', 'F_2'};
  static const Set<String> _leftBendIds = {'B1', 'B5', 'B7', 'FL1'};
  static const Set<String> _leftPunchIds = {'SLOT_3', 'SLOT_5', 'SLOT_9', 'SLOT_10'};
  static const Set<String> _leftArcIds = {'ARC_BND_8', 'ARC_BND_9', 'ARC_BND_11', 'ARC_BND_12'};

  // Canonical baseline anchor points for Bend B2 (Right Cheek)
  static const double _pBot0X = 172.87063071855217;
  static const double _pBot0Y = 83.43860018001482;
  static const double _pTop0X = 215.29141392239853;
  static const double _pTop0Y = 175.86500705120807;

  /// Pure deterministic solver: scales the canonical Unequal Tee template
  /// to the target parameters while preserving all topological relationships,
  /// 12 corner arcs, rigid coupler punches, and fold kinematics.
  static UnequalTeeScaleResult scale({
    required DsfDocument baseline,
    required UnequalTeeScaleParameters parameters,
  }) {
    // 1. Invariance on zero delta:
    if (!parameters.hasAnyChange) {
      return UnequalTeeScaleResult(
        document: baseline,
        isValid: true,
        diagnostics: {
          'status': 'unchanged_baseline',
          'bodyHeight': 100.0,
          'dHBody': 0.0,
          'dH1': 0.0,
          'dH2': 0.0,
          'dH3': 0.0,
        },
      );
    }

    // 2. Extract base floor datum (F_10)
    final baseFloor = baseline.faces.firstWhere(
      (f) => f.id == 'F_10' || f.isBaseAnchor || f.role == FaceRole.baseFloor,
      orElse: () => baseline.faces.first,
    );
    final verts = baseFloor.vertices;
    final minX = verts.map((v) => v.x).reduce(math.min);
    final maxX = verts.map((v) => v.x).reduce(math.max);
    final midX = (minX + maxX) / 2.0;

    final dW1 = parameters.dW1;
    final dW2 = parameters.dW2;
    final dW3 = parameters.dW3;

    // Derived Body Height and Independent Port Height Deltas:
    // Hbody = max(H1, H2, H3)
    // "Port heights are independent inputs. Common body height is a derived value
    //  equal to the maximum port height. A port's coupler area always follows its
    //  own port height, while the shared body follows the maximum. The vertical
    //  difference between the body and each port defines that port's step/notch."
    final dH1 = parameters.dH1.abs() > 1e-4
        ? parameters.dH1
        : (parameters.port1Height - 100.0);
    final dH2 = parameters.dH2.abs() > 1e-4
        ? parameters.dH2
        : (parameters.port2Height - 50.0);
    final dH3 = parameters.dH3.abs() > 1e-4
        ? parameters.dH3
        : (parameters.port3Height - 100.0);

    final effectiveP1H = 100.0 + dH1;
    final effectiveP2H = 50.0 + dH2;
    final effectiveP3H = 100.0 + dH3;

    final bodyHeight = math.max(
      effectiveP1H,
      math.max(effectiveP2H, effectiveP3H),
    );
    final dHBody = bodyHeight - 100.0;

    // 3. Right Cheek Coordinate Frame Setup (anchored along Bend B2)
    final bx0 = _pTop0X - _pBot0X;
    final by0 = _pTop0Y - _pBot0Y;
    final l0 = math.sqrt(bx0 * bx0 + by0 * by0);
    final u0X = bx0 / l0;
    final u0Y = by0 / l0;
    final v0X = u0Y;
    final v0Y = -u0X;
    final theta0 = math.atan2(by0, bx0);

    final pBotX = _pBot0X + dW1 / 2.0;
    final pBotY = _pBot0Y;
    final pTopX = _pTop0X + dW1 / 2.0;
    final pTopY = _pTop0Y + dW3 - dW2;
    final bx = pTopX - pBotX;
    final by = pTopY - pBotY;
    final lB2 = math.sqrt(bx * bx + by * by);
    final uX = bx / lB2;
    final uY = by / lB2;
    final vX = uY;
    final vY = -uX;
    final theta = math.atan2(by, bx);
    final deltaTheta = theta - theta0;

    // 3.1 Right Side Point Transformation
    CadPoint2D transformRightPt(CadPoint2D pt, {String? fid, String? bid, String? pid, String? aid}) {
      final rx = pt.x - _pBot0X;
      final ry = pt.y - _pBot0Y;
      final u = rx * u0X + ry * u0Y;
      final v = rx * v0X + ry * v0Y;

      final double uStar;
      if (u > l0 / 2.0) {
        uStar = lB2 + (u - l0);
      } else {
        uStar = u;
      }

      double vStar = v;
      if (fid == 'F_4') {
        // P2 coupler flap: scales with dH2
        if (v > 20.0) vStar = v + dH2;
      } else if (fid == 'F_5') {
        // P1 coupler flap: scales with dH1
        if (v > 50.0) vStar = v + dH1;
      } else if (fid == 'F_6') {
        // Return flange: scales with dHBody
        vStar = v + dHBody;
      } else if (fid == 'F_7') {
        // Cheek side wall: FL2 edge scales with dHBody, B4 top edge scales with dH2
        if (v > 80.0) {
          vStar = v + dHBody;
        } else if (v > 30.0) {
          vStar = v + dH2;
        }
      } else if (bid == 'B4') {
        if (v > 20.0) vStar = v + dH2;
      } else if (bid == 'B6') {
        if (v > 50.0) vStar = v + dH1;
      } else if (bid == 'FL2') {
        vStar = v + dHBody;
      } else if (pid == 'SLOT_4') {
        if (effectiveP1H < 95.0) {
          vStar = v + (dH1 + 50.0) / 2.0;
        } else {
          vStar = v;
        }
      } else if (pid == 'SLOT_6') {
        if (effectiveP2H >= 95.0) {
          vStar = v;
        } else {
          vStar = v + dH2 / 2.0;
        }
      } else if (pid == 'SLOT_12') {
        vStar = v + dH1;
      } else if (aid == 'ARC_BND_5') {
        vStar = v + dH2;
      } else if (aid == 'ARC_BND_4') {
        vStar = v;
      } else if (aid == 'ARC_BND_6') {
        vStar = v + dH1;
      } else if (aid == 'ARC_BND_7') {
        vStar = v;
      }

      return CadPoint2D(
        pBotX + uStar * uX + vStar * vX,
        pBotY + uStar * uY + vStar * vY,
      );
    }

    // 3.2 Back Wall Point Transformation
    const yBack0 = 222.86500705120665;
    CadPoint2D transformBackPt(CadPoint2D pt, {String? fid, String? bid, String? pid, String? aid}) {
      final double dx = pt.x < midX ? -dW1 / 2.0 : dW1 / 2.0;
      double dy = dW3;
      final yRel = pt.y - yBack0;

      if (fid == 'F_8' || bid == 'FL3') {
        dy += dHBody;
      } else if (fid == 'F_9') {
        if (pt.x >= 215.0) {
          // Right Ear (Port 2)
          if (yRel > 70.0) {
            // Vertex 12 (bottom corner connecting to FL3)
            dy += dHBody;
          } else if (yRel > 20.0) {
            // Vertices 9, 10, 11 (top edge of Right Ear)
            dy += dH2;
          }
        } else if (pt.x <= 84.0) {
          // Left Ear area: all vertices in the lower ear region scale with dH3
          if (yRel > 70.0) {
            dy += dH3;
          }
        } else {
          // Main Web (FL3 area)
          if (yRel > 70.0) {
            dy += dHBody;
          }
        }
      } else if (pid == 'SLOT_7') {
        if (effectiveP2H >= 95.0) {
          dy += 0.0;
        } else {
          dy += dH2 / 2.0;
        }
      } else if (pid == 'SLOT_8') {
        if (effectiveP3H < 95.0) {
          dy += (dH3 + 50.0) / 2.0;
        } else {
          dy += 0.0;
        }
      } else if (pid == 'SLOT_11') {
        dy += dH3;
      } else if (aid == 'ARC_BND_2') {
        dy += dH2;
      } else if (aid == 'ARC_BND_3') {
        // Base corner of Right Ear: stays at base (0 height delta)
        dy += 0.0;
      } else if (aid == 'ARC_BND_1') {
        dy += dH3;
      } else if (aid == 'ARC_BND_10') {
        // Base corner of Left Ear: stays at base (0 height delta)
        dy += 0.0;
      }

      return CadPoint2D(pt.x + dx, pt.y + dy);
    }

    // 3.3 Left Side Point Transformation
    const pB10X = 125.86500705120397;
    const pB10Y = 83.43860018001482;
    CadPoint2D transformLeftPt(CadPoint2D pt, {String? fid, String? bid, String? pid, String? aid}) {
      double dx = -dW1 / 2.0;
      double dy = 0.0;
      final distNorm = -((pt.x - pB10X) + (pt.y - pB10Y)) / math.sqrt2;

      if (fid == 'F_2' || bid == 'FL1') {
        dx -= dHBody / math.sqrt2;
        dy -= dHBody / math.sqrt2;
      } else if (fid == 'F_0' || bid == 'B5' || pid == 'SLOT_9' || aid == 'ARC_BND_9') {
        if (distNorm > 40.0) {
          dx -= dH1 / math.sqrt2;
          dy -= dH1 / math.sqrt2;
        }
      } else if (pid == 'SLOT_3') {
        if (effectiveP1H < 95.0) {
          final s = (dH1 + 50.0) / 2.0;
          dx -= s / math.sqrt2;
          dy -= s / math.sqrt2;
        }
      } else if (aid == 'ARC_BND_8') {
        // Base corner of F_0: stays at base
      } else if (fid == 'F_1' || bid == 'B7' || pid == 'SLOT_10' || aid == 'ARC_BND_12') {
        if (distNorm > 40.0) {
          dx -= dH3 / math.sqrt2;
          dy -= dH3 / math.sqrt2;
        }
      } else if (pid == 'SLOT_5') {
        if (effectiveP3H < 95.0) {
          final s = (dH3 + 50.0) / 2.0;
          dx -= s / math.sqrt2;
          dy -= s / math.sqrt2;
        }
      } else if (aid == 'ARC_BND_11') {
        // Base corner of F_1: stays at base
      } else if (fid == 'F_3') {
        // Face F_3 (Left Cheek Side Wall):
        // The entire top rim (connecting to FL1 and return flange F_2) scales with dHBody.
        // Both v[0] and v[3] stay coincident with FL1.p1 and FL1.p2.
        if (distNorm > 80.0) {
          dx -= dHBody / math.sqrt2;
          dy -= dHBody / math.sqrt2;
        }
      }

      return CadPoint2D(pt.x + dx, pt.y + dy);
    }

    // 3.4 Base Floor Point Transformation
    CadPoint2D transformFloorPt(int vi, CadPoint2D pt) {
      switch (vi) {
        case 0:
          return CadPoint2D(pt.x - dW1 / 2.0, pt.y + dW3);
        case 1:
          return CadPoint2D(pt.x - dW1 / 2.0, pt.y);
        case 2:
          return CadPoint2D(pt.x - dW1 / 2.0, pt.y);
        case 3:
          return CadPoint2D(pt.x + dW1 / 2.0, pt.y);
        case 4:
          return CadPoint2D(pt.x + dW1 / 2.0, pt.y + dW3 - dW2);
        case 5:
          return CadPoint2D(pt.x + dW1 / 2.0, pt.y + dW3);
        default:
          return pt;
      }
    }

    // 4. Transform Faces
    final faceVertexMap = <String, CadPoint2D>{};
    final newFaces = baseline.faces.map((f) {
      final fid = f.id;
      final newVertices = <CadPoint2D>[];
      for (int vi = 0; vi < f.vertices.length; vi++) {
        final v = f.vertices[vi];
        final CadPoint2D nv;
        if (_rightFaceIds.contains(fid)) {
          nv = transformRightPt(v, fid: fid);
        } else if (_backFaceIds.contains(fid)) {
          nv = transformBackPt(v, fid: fid);
        } else if (_leftFaceIds.contains(fid)) {
          nv = transformLeftPt(v, fid: fid);
        } else if (fid == 'F_10') {
          nv = transformFloorPt(vi, v);
        } else {
          nv = v;
        }
        newVertices.add(nv);
        faceVertexMap['${fid}_v$vi'] = nv;
      }
      if (fid == 'F_9' && dHBody > dH3 + 1e-4) {
        // When body height exceeds Port 3 height, synthesize the left flange junction
        // vertex at (83.44 + dx, 320.865 + dW3 + dHBody) to create a clean orthogonal
        // vertical step from the left ear notch down to FL3 / F_8.
        final dx = -dW1 / 2.0;
        final leftFlangeJunction = CadPoint2D(
          83.43860018001396 + dx,
          yBack0 + 98.0 + dW3 + dHBody,
        );
        newVertices.add(leftFlangeJunction);
      }
      return f.copyWith(vertices: newVertices);
    }).toList();

    // 5. Transform Bends (including dynamic target angle updates for B4 & B6)
    final newBends = baseline.bends.map((b) {
      final bid = b.id;
      final CadPoint2D newP1;
      final CadPoint2D newP2;
      double newTargetAngle = b.targetAngleDeg;

      if (_rightBendIds.contains(bid)) {
        newP1 = transformRightPt(b.p1, bid: bid);
        newP2 = transformRightPt(b.p2, bid: bid);
        if (bid == 'B4') {
          newTargetAngle = theta * 180.0 / math.pi;
        } else if (bid == 'B6') {
          newTargetAngle = 90.0 - (theta * 180.0 / math.pi);
        }
      } else if (_backBendIds.contains(bid)) {
        newP1 = transformBackPt(b.p1, bid: bid);
        newP2 = transformBackPt(b.p2, bid: bid);
      } else if (_leftBendIds.contains(bid)) {
        newP1 = transformLeftPt(b.p1, bid: bid);
        newP2 = transformLeftPt(b.p2, bid: bid);
      } else {
        newP1 = b.p1;
        newP2 = b.p2;
      }

      return b.copyWith(
        p1: newP1,
        p2: newP2,
        targetAngleDeg: newTargetAngle,
      );
    }).toList();

    // 6. Transform Continuous Outer Contour by mapping to face vertices
    final newContour = <CadPoint2D>[];
    for (int ci = 0; ci < baseline.outerContour.length; ci++) {
      final cp = baseline.outerContour[ci];
      CadPoint2D? matchedPt;
      if (ci == 0) {
        // Point 0 in baseline outer contour is the left flange junction connecting to F_8.
        // It must scale with dHBody to stay attached to the flange.
        final dx = -dW1 / 2.0;
        matchedPt = CadPoint2D(
          83.43860018001396 + dx,
          yBack0 + 98.0 + dW3 + dHBody,
        );
      } else if (ci == baseline.outerContour.length - 1) {
        // The last point in baseline outer contour (ci == 42) is the left ear notch corner
        // ending the coupler flap perimeter. It must scale with dH3.
        final dx = -dW1 / 2.0;
        matchedPt = CadPoint2D(
          83.43860018001396 + dx,
          yBack0 + 98.0 + dW3 + dH3,
        );
      } else {
        for (final bf in baseline.faces) {
          for (int vi = 0; vi < bf.vertices.length; vi++) {
            final bv = bf.vertices[vi];
            if ((bv.x - cp.x).abs() < 1e-3 && (bv.y - cp.y).abs() < 1e-3) {
              matchedPt = faceVertexMap['${bf.id}_v$vi'];
              break;
            }
          }
          if (matchedPt != null) break;
        }
      }
      newContour.add(matchedPt ?? cp);
    }

    // 7. Transform Rigid Coupler Punches (preserving dimensions and tracking rotation)
    // Universal Rule: For any port whose height < 95.0mm, show only 1 coupler hole (centered).
    // When height >= 95.0mm, show 2 coupler holes.
    final suppressedPunchIds = <String>{};
    if (effectiveP1H < 95.0) {
      suppressedPunchIds.addAll({'SLOT_9', 'SLOT_12'});
    }
    if (effectiveP3H < 95.0) {
      suppressedPunchIds.addAll({'SLOT_10', 'SLOT_11'});
    }

    final newPunches = baseline.punches
        .where((p) => !suppressedPunchIds.contains(p.id))
        .map((p) {
      final pid = p.id;
      final CadPoint2D newCenter;
      double newRotation = p.rotationDeg;

      if (_rightPunchIds.contains(pid)) {
        newCenter = transformRightPt(p.center, pid: pid);
        newRotation = (newRotation + (deltaTheta * 180.0 / math.pi)) % 360.0;
      } else if (_backPunchIds.contains(pid)) {
        newCenter = transformBackPt(p.center, pid: pid);
      } else if (_leftPunchIds.contains(pid)) {
        newCenter = transformLeftPt(p.center, pid: pid);
      } else {
        newCenter = p.center;
      }

      return p.copyWith(
        center: newCenter,
        rotationDeg: newRotation,
      );
    }).toList();

    // 7.1 When Port 2 height is >= 95mm, synthesize 2nd coupler slots on Flap F_4 and Face F_9 Right Ear
    if (effectiveP2H >= 95.0) {
      // 1. Second slot on Flap F_4 (SLOT_6_B) at 50mm pitch from SLOT_6 along flap v-axis
      final double uStar6B = lB2 + (121.29651490779239 - l0);
      final double vStar6B = 23.648083578093917 + 50.0 + (dH2 > 50.0 ? (dH2 - 50.0) : 0.0);
      final slot6BCenter = CadPoint2D(
        pBotX + uStar6B * uX + vStar6B * vX,
        pBotY + uStar6B * uY + vStar6B * vY,
      );
      final slot6BRot = (155.0 + (deltaTheta * 180.0 / math.pi)) % 360.0;
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_6_B',
        type: PunchType.obroundSlot,
        center: slot6BCenter,
        widthMm: 8.0,
        lengthMm: 20.0,
        rotationDeg: slot6BRot,
        role: CncPunchRole.coupler,
        parentFaceId: 'F_4',
        associatedPortId: 'PORT_2',
      ));

      // 2. Second slot on Face F_9 Right Ear (SLOT_7_B) at 50mm pitch from SLOT_7
      final double dxRightEar = 235.29141392239853 < midX ? -dW1 / 2.0 : dW1 / 2.0;
      final double dyRightEar = dW3 + 50.0 + (dH2 > 50.0 ? (dH2 - 50.0) : 0.0);
      final slot7BCenter = CadPoint2D(
        235.29141392239853 + dxRightEar,
        246.8650070512066 + dyRightEar,
      );
      newPunches.add(CncPunchPrimitive(
        id: 'SLOT_7_B',
        type: PunchType.obroundSlot,
        center: slot7BCenter,
        widthMm: 8.0,
        lengthMm: 20.0,
        rotationDeg: 90.0,
        role: CncPunchRole.coupler,
        parentFaceId: 'F_9',
        associatedPortId: 'PORT_2',
      ));
    }

    // 8. Transform All 12 Corner Arcs (preserving radii and rotating with parent face)
    final newArcs = baseline.arcs.map((a) {
      final aid = a.id;
      final CadPoint2D newCenter;
      double newStartAngle = a.startAngleRad;

      if (_rightArcIds.contains(aid)) {
        newCenter = transformRightPt(a.center, aid: aid);
        newStartAngle = (a.startAngleRad + deltaTheta) % (2 * math.pi);
      } else if (_backArcIds.contains(aid)) {
        newCenter = transformBackPt(a.center, aid: aid);
      } else if (_leftArcIds.contains(aid)) {
        newCenter = transformLeftPt(a.center, aid: aid);
      } else {
        newCenter = a.center;
      }

      return a.copyWith(
        center: newCenter,
        startAngleRad: newStartAngle,
      );
    }).toList();

    // 9. Cut lines
    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(
        p1: transformBackPt(cl.p1),
        p2: transformBackPt(cl.p2),
      );
    }).toList();

    // 10. Update Parameters Map
    final updatedParameters = Map<String, double>.from(baseline.parameters);
    updatedParameters['port1Width'] = parameters.port1Width;
    updatedParameters['port1Height'] = parameters.port1Height;
    updatedParameters['port2Width'] = parameters.port2Width;
    updatedParameters['port2Height'] = parameters.port2Height;
    updatedParameters['port3Width'] = parameters.port3Width;
    updatedParameters['port3Height'] = parameters.port3Height;
    updatedParameters['port1_width'] = parameters.port1Width;
    updatedParameters['port1_height'] = parameters.port1Height;
    updatedParameters['port2_width'] = parameters.port2Width;
    updatedParameters['port2_height'] = parameters.port2Height;
    updatedParameters['port3_width'] = parameters.port3Width;
    updatedParameters['port3_height'] = parameters.port3Height;
    updatedParameters['width'] = parameters.port2Width;
    updatedParameters['height'] = bodyHeight;
    updatedParameters['branchWidth'] = parameters.port1Width;

    final scaledDoc = baseline.copyWith(
      outerContour: newContour,
      faces: newFaces,
      bends: newBends,
      punches: newPunches,
      arcs: newArcs,
      cutLines: newCutLines,
      parameters: updatedParameters,
    );

    return UnequalTeeScaleResult(
      document: scaledDoc,
      isValid: true,
      diagnostics: {
        'status': 'scaled_success',
        'dW1': dW1,
        'dW2': dW2,
        'dW3': dW3,
        'dHBody': dHBody,
        'dH1': dH1,
        'dH2': dH2,
        'dH3': dH3,
        'bodyHeight': bodyHeight,
        'lB2': lB2,
        'thetaB2Deg': theta * 180.0 / math.pi,
        'arcCount': newArcs.length,
        'punchCount': newPunches.length,
      },
    );
  }
}
