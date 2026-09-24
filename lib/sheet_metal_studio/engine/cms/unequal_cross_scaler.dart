// =============================================================================
// unequal_cross_scaler.dart
//
// Dedicated Parametric Scaling Engine for Unequal Cross Fittings.
// Implements the Analytical Geometry Rule:
// "Port heights and widths are independent inputs for all 4 ports (P1..P4).
//  Common body height is a derived value equal to the maximum port height:
//  Hbody = max(H1, H2, H3, H4).
//  A port's coupler area always follows its own port height and width, while the
//  shared body follows the maximum. The vertical difference between the body
//  and each port defines that port's orthogonal step/notch."
//
// Preserves:
// - All 17 planar faces (F_0 to F_16) with complete kinematic hierarchy
// - All 16 bend lines (B1 to B12, FL1 to FL4) with parent/child face links
// - All 16 corner fillet arcs (ARC_BND_1 to ARC_BND_16) at exact tangent corners (r=10mm)
// - All rigid coupler punches (SLOT_1 to SLOT_12) governed by the Universal 95mm Rule
// - Continuous closed outer contour (57+ vertices) with exact face vertex coincidence
// =============================================================================

import 'dart:math' as math;

import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/cms/cms_scaling_model.dart';
import '../../models/planar_sheet_face.dart';

/// Explicit parameters driving Unequal Cross scaling across all 4 ports.
class UnequalCrossScaleParameters {
  final double port1Width;
  final double port1Height;
  final double port2Width;
  final double port2Height;
  final double port3Width;
  final double port3Height;
  final double port4Width;
  final double port4Height;

  final double dW1;
  final double dH1;
  final double dW2;
  final double dH2;
  final double dW3;
  final double dH3;
  final double dW4;
  final double dH4;

  final double sheetThickness;
  final double flangeWidth;

  const UnequalCrossScaleParameters({
    required this.port1Width,
    required this.port1Height,
    required this.port2Width,
    required this.port2Height,
    required this.port3Width,
    required this.port3Height,
    required this.port4Width,
    required this.port4Height,
    this.dW1 = 0.0,
    this.dH1 = 0.0,
    this.dW2 = 0.0,
    this.dH2 = 0.0,
    this.dW3 = 0.0,
    this.dH3 = 0.0,
    this.dW4 = 0.0,
    this.dH4 = 0.0,
    this.sheetThickness = 1.5,
    this.flangeWidth = 10.0,
  });

  /// Factory resolving parameters and deltas from CMS active scaling parameter map.
  factory UnequalCrossScaleParameters.fromCmsParameters(
    Map<String, CmsScalingParameter> params, {
    double defaultW1 = 50.0,
    double defaultH1 = 50.0,
    double defaultW2 = 100.0,
    double defaultH2 = 100.0,
    double defaultW3 = 50.0,
    double defaultH3 = 50.0,
    double defaultW4 = 100.0,
    double defaultH4 = 100.0,
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
    final p4W = getVal('port4_width', defaultW4);
    final p4H = getVal('port4_height', defaultH4);

    final dW1 = getDelta('port1_width', defaultW1);
    final dW2 = getDelta('port2_width', defaultW2);
    final dW3 = getDelta('port3_width', defaultW3);
    final dW4 = getDelta('port4_width', defaultW4);
    final dH1 = getDelta('port1_height', defaultH1);
    final dH2 = getDelta('port2_height', defaultH2);
    final dH3 = getDelta('port3_height', defaultH3);
    final dH4 = getDelta('port4_height', defaultH4);

    return UnequalCrossScaleParameters(
      port1Width: p1W,
      port1Height: p1H,
      port2Width: p2W,
      port2Height: p2H,
      port3Width: p3W,
      port3Height: p3H,
      port4Width: p4W,
      port4Height: p4H,
      dW1: dW1,
      dH1: dH1,
      dW2: dW2,
      dH2: dH2,
      dW3: dW3,
      dH3: dH3,
      dW4: dW4,
      dH4: dH4,
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
      dW4.abs() > 1e-4 ||
      dH4.abs() > 1e-4 ||
      (port1Width - 50.0).abs() > 1e-4 ||
      (port1Height - 50.0).abs() > 1e-4 ||
      (port2Width - 100.0).abs() > 1e-4 ||
      (port2Height - 100.0).abs() > 1e-4 ||
      (port3Width - 50.0).abs() > 1e-4 ||
      (port3Height - 50.0).abs() > 1e-4 ||
      (port4Width - 100.0).abs() > 1e-4 ||
      (port4Height - 100.0).abs() > 1e-4;

  /// Product-wide maximum height governing core body height.
  double get maxHeight => math.max(math.max(port1Height, port2Height), math.max(port3Height, port4Height));
}

/// Result of an Unequal Cross scale operation.
class UnequalCrossScaleResult {
  final DsfDocument document;
  final bool isValid;
  final String? errorMessage;
  final Map<String, dynamic> diagnostics;

  const UnequalCrossScaleResult({required this.document, required this.isValid, this.errorMessage, this.diagnostics = const {}});
}

/// Helper internal descriptor for each quadrant.
class _QuadrantSpec {
  final String name;
  final String cheekId;
  final String flapHorizId;
  final String flapVertId;
  final String flangeId;
  final String bendBaseId;
  final String bendHorizId;
  final String bendVertId;
  final String bendFlangeId;
  final String baseArcHorizId;
  final String topArcHorizId;
  final String baseArcVertId;
  final String topArcVertId;
  final List<String> punchesHoriz;
  final List<String> punchesVert;
  final CadPoint2D p0Base;
  final CadPoint2D u0;
  final CadPoint2D v0;
  final CadPoint2D p0;
  final CadPoint2D p1;
  final double lB;
  final CadPoint2D uAxis;
  final CadPoint2D vAxis;
  final double deltaTheta;
  final double heightHoriz;
  final double dHeightHoriz;
  final double heightVert;
  final double dHeightVert;
  final double punchRotation;
  final String newPunchVertId;
  final double angleHorizDeg;
  final double angleVertDeg;

  const _QuadrantSpec({
    required this.name,
    required this.cheekId,
    required this.flapHorizId,
    required this.flapVertId,
    required this.flangeId,
    required this.bendBaseId,
    required this.bendHorizId,
    required this.bendVertId,
    required this.bendFlangeId,
    required this.baseArcHorizId,
    required this.topArcHorizId,
    required this.baseArcVertId,
    required this.topArcVertId,
    required this.punchesHoriz,
    required this.punchesVert,
    required this.p0Base,
    required this.u0,
    required this.v0,
    required this.p0,
    required this.p1,
    required this.lB,
    required this.uAxis,
    required this.vAxis,
    required this.deltaTheta,
    required this.heightHoriz,
    required this.dHeightHoriz,
    required this.heightVert,
    required this.dHeightVert,
    required this.punchRotation,
    required this.newPunchVertId,
    required this.angleHorizDeg,
    required this.angleVertDeg,
  });
}

/// Standalone analytical scaler for Unequal Cross fittings.
class UnequalCrossScaler {
  static const double _invSqrt2 = 0.7071067811865475;
  static const double _x0 = 153.65180361560642;
  static const double _y0 = 135.7228714274761;
  static const double _c = 40.0 * _invSqrt2; // 28.2842712474619

  /// Pure deterministic solver: scales the canonical Unequal Cross template
  /// to the target parameters while preserving all topological relationships,
  /// 16 corner fillet arcs, rigid coupler punches, and fold kinematics.
  static UnequalCrossScaleResult scale({required DsfDocument baseline, required UnequalCrossScaleParameters parameters}) {
    // 1. Invariance on zero delta:
    if (!parameters.hasAnyChange) {
      return UnequalCrossScaleResult(
        document: baseline,
        isValid: true,
        diagnostics: {'status': 'unchanged_baseline', 'bodyHeight': 100.0, 'dHBody': 0.0, 'dH1': 0.0, 'dH2': 0.0, 'dH3': 0.0, 'dH4': 0.0},
      );
    }

    final dW1 = parameters.dW1.abs() > 1e-4 ? parameters.dW1 : (parameters.port1Width - 50.0);
    final dW2 = parameters.dW2.abs() > 1e-4 ? parameters.dW2 : (parameters.port2Width - 100.0);
    final dW3 = parameters.dW3.abs() > 1e-4 ? parameters.dW3 : (parameters.port3Width - 50.0);
    final dW4 = parameters.dW4.abs() > 1e-4 ? parameters.dW4 : (parameters.port4Width - 100.0);

    final unbentW1 = 48.0 + dW1;
    final unbentW2 = 98.0 + dW2;
    final unbentW3 = 48.0 + dW3;
    final unbentW4 = 98.0 + dW4;

    final dH1 = parameters.dH1.abs() > 1e-4 ? parameters.dH1 : (parameters.port1Height - 50.0);
    final dH2 = parameters.dH2.abs() > 1e-4 ? parameters.dH2 : (parameters.port2Height - 100.0);
    final dH3 = parameters.dH3.abs() > 1e-4 ? parameters.dH3 : (parameters.port3Height - 50.0);
    final dH4 = parameters.dH4.abs() > 1e-4 ? parameters.dH4 : (parameters.port4Height - 100.0);

    final effectiveP1H = 50.0 + dH1;
    final effectiveP2H = 100.0 + dH2;
    final effectiveP3H = 50.0 + dH3;
    final effectiveP4H = 100.0 + dH4;

    final bodyHeight = math.max(math.max(effectiveP1H, effectiveP2H), math.max(effectiveP3H, effectiveP4H));
    final dHBody = bodyHeight - 100.0;

    // 2. Base Floor F_16: strict 90-deg orthogonal rectangular port mouths per independent port
    // Port 1 (West): vertical mouth of width unbentW1 at xWest (dx = 0)
    // Port 2 (North): horizontal mouth of width unbentW2 at yNorth (dy = 0)
    // Port 3 (East): vertical mouth of width unbentW3 at xEast (dx = 0)
    // Port 4 (South): horizontal mouth of width unbentW4 at ySouth (dy = 0)
    final maxWNs = math.max(unbentW2, unbentW4);
    final maxWWe = math.max(unbentW1, unbentW3);

    final xWest = _x0 - maxWNs / 2.0 - _c;
    final xEast = _x0 + maxWNs / 2.0 + _c;
    final yNorth = _y0 - maxWWe / 2.0 - _c;
    final ySouth = _y0 + maxWWe / 2.0 + _c;

    final newF16Verts = [
      CadPoint2D(xWest, _y0 + unbentW1 / 2.0), // v0: Port 1 (West) bottom
      CadPoint2D(xWest, _y0 - unbentW1 / 2.0), // v1: Port 1 (West) top
      CadPoint2D(_x0 - unbentW2 / 2.0, yNorth), // v2: Port 2 (North) left
      CadPoint2D(_x0 + unbentW2 / 2.0, yNorth), // v3: Port 2 (North) right
      CadPoint2D(xEast, _y0 - unbentW3 / 2.0), // v4: Port 3 (East) top
      CadPoint2D(xEast, _y0 + unbentW3 / 2.0), // v5: Port 3 (East) bottom
      CadPoint2D(_x0 + unbentW4 / 2.0, ySouth), // v6: Port 4 (South) right
      CadPoint2D(_x0 - unbentW4 / 2.0, ySouth), // v7: Port 4 (South) left
    ];

    // Helper to construct quadrant spec with dynamic bend vector and elongation
    _QuadrantSpec makeQuad({
      required String name,
      required String cheekId,
      required String flapHorizId,
      required String flapVertId,
      required String flangeId,
      required String bendBaseId,
      required String bendHorizId,
      required String bendVertId,
      required String bendFlangeId,
      required String baseArcHorizId,
      required String topArcHorizId,
      required String baseArcVertId,
      required String topArcVertId,
      required List<String> punchesHoriz,
      required List<String> punchesVert,
      required CadPoint2D p0Base,
      required CadPoint2D u0,
      required CadPoint2D v0,
      required CadPoint2D Function(CadPoint2D u) vFunc,
      required CadPoint2D p0,
      required CadPoint2D p1,
      required double heightHoriz,
      required double dHeightHoriz,
      required double heightVert,
      required double dHeightVert,
      required double punchRotation,
      required String newPunchVertId,
    }) {
      final bx = p1.x - p0.x;
      final by = p1.y - p0.y;
      final lB = math.sqrt(bx * bx + by * by);
      final uAxis = CadPoint2D(bx / lB, by / lB);
      final vAxis = vFunc(uAxis);
      final theta0 = math.atan2(u0.y, u0.x);
      final theta = math.atan2(uAxis.y, uAxis.x);
      final deltaTheta = theta - theta0;

      final absBx = bx.abs();
      final absBy = by.abs();
      final alphaDeg = math.atan2(absBy, absBx) * 180.0 / math.pi;
      final angleHorizDeg = 90.0 - alphaDeg;
      final angleVertDeg = alphaDeg;

      return _QuadrantSpec(
        name: name,
        cheekId: cheekId,
        flapHorizId: flapHorizId,
        flapVertId: flapVertId,
        flangeId: flangeId,
        bendBaseId: bendBaseId,
        bendHorizId: bendHorizId,
        bendVertId: bendVertId,
        bendFlangeId: bendFlangeId,
        baseArcHorizId: baseArcHorizId,
        topArcHorizId: topArcHorizId,
        baseArcVertId: baseArcVertId,
        topArcVertId: topArcVertId,
        punchesHoriz: punchesHoriz,
        punchesVert: punchesVert,
        p0Base: p0Base,
        u0: u0,
        v0: v0,
        p0: p0,
        p1: p1,
        lB: lB,
        uAxis: uAxis,
        vAxis: vAxis,
        deltaTheta: deltaTheta,
        heightHoriz: heightHoriz,
        dHeightHoriz: dHeightHoriz,
        heightVert: heightVert,
        dHeightVert: dHeightVert,
        punchRotation: punchRotation,
        newPunchVertId: newPunchVertId,
        angleHorizDeg: angleHorizDeg,
        angleVertDeg: angleVertDeg,
      );
    }

    final quadrants = [
      makeQuad(
        name: 'Q1_NE',
        cheekId: 'F_3',
        flapHorizId: 'F_1',
        flapVertId: 'F_0',
        flangeId: 'F_2',
        bendBaseId: 'B2',
        bendHorizId: 'B9',
        bendVertId: 'B8',
        bendFlangeId: 'FL3',
        baseArcHorizId: 'ARC_BND_12',
        topArcHorizId: 'ARC_BND_11',
        baseArcVertId: 'ARC_BND_9',
        topArcVertId: 'ARC_BND_10',
        punchesHoriz: const ['SLOT_7', 'SLOT_8'],
        punchesVert: const ['SLOT_9'],
        p0Base: const CadPoint2D(202.65180361560638, 83.43860018001283),
        u0: const CadPoint2D(_invSqrt2, _invSqrt2),
        v0: const CadPoint2D(_invSqrt2, -_invSqrt2),
        vFunc: (u) => CadPoint2D(u.y, -u.x),
        p0: newF16Verts[3],
        p1: newF16Verts[4],
        heightHoriz: effectiveP2H,
        dHeightHoriz: dH2,
        heightVert: effectiveP3H,
        dHeightVert: dH3,
        punchRotation: 135.0,
        newPunchVertId: 'SLOT_9_B',
      ),
      makeQuad(
        name: 'Q2_NW',
        cheekId: 'F_7',
        flapHorizId: 'F_5',
        flapVertId: 'F_4',
        flangeId: 'F_6',
        bendBaseId: 'B1',
        bendHorizId: 'B10',
        bendVertId: 'B5',
        bendFlangeId: 'FL2',
        baseArcHorizId: 'ARC_BND_4',
        topArcHorizId: 'ARC_BND_3',
        baseArcVertId: 'ARC_BND_1',
        topArcVertId: 'ARC_BND_2',
        punchesHoriz: const ['SLOT_1', 'PUNCH_CPY_8064'],
        punchesVert: const ['SLOT_3'],
        p0Base: const CadPoint2D(104.65180361560647, 83.43860018001283),
        u0: const CadPoint2D(-_invSqrt2, _invSqrt2),
        v0: const CadPoint2D(-_invSqrt2, -_invSqrt2),
        vFunc: (u) => CadPoint2D(-u.y, u.x),
        p0: newF16Verts[2],
        p1: newF16Verts[1],
        heightHoriz: effectiveP2H,
        dHeightHoriz: dH2,
        heightVert: effectiveP1H,
        dHeightVert: dH1,
        punchRotation: 45.0,
        newPunchVertId: 'SLOT_3_B',
      ),
      makeQuad(
        name: 'Q3_SE',
        cheekId: 'F_11',
        flapHorizId: 'F_9',
        flapVertId: 'F_8',
        flangeId: 'F_10',
        bendBaseId: 'B3',
        bendHorizId: 'B12',
        bendVertId: 'B7',
        bendFlangeId: 'FL4',
        baseArcHorizId: 'ARC_BND_16',
        topArcHorizId: 'ARC_BND_15',
        baseArcVertId: 'ARC_BND_13',
        topArcVertId: 'ARC_BND_14',
        punchesHoriz: const ['SLOT_10', 'SLOT_11'],
        punchesVert: const ['SLOT_12'],
        p0Base: const CadPoint2D(202.65180361560638, 188.00714267493942),
        u0: const CadPoint2D(_invSqrt2, -_invSqrt2),
        v0: const CadPoint2D(_invSqrt2, _invSqrt2),
        vFunc: (u) => CadPoint2D(-u.y, u.x),
        p0: newF16Verts[6],
        p1: newF16Verts[5],
        heightHoriz: effectiveP4H,
        dHeightHoriz: dH4,
        heightVert: effectiveP3H,
        dHeightVert: dH3,
        punchRotation: 45.0,
        newPunchVertId: 'SLOT_12_B',
      ),
      makeQuad(
        name: 'Q4_SW',
        cheekId: 'F_15',
        flapHorizId: 'F_13',
        flapVertId: 'F_12',
        flangeId: 'F_14',
        bendBaseId: 'B4',
        bendHorizId: 'B11',
        bendVertId: 'B6',
        bendFlangeId: 'FL1',
        baseArcHorizId: 'ARC_BND_8',
        topArcHorizId: 'ARC_BND_7',
        baseArcVertId: 'ARC_BND_5',
        topArcVertId: 'ARC_BND_6',
        punchesHoriz: const ['SLOT_4', 'SLOT_5'],
        punchesVert: const ['SLOT_6'],
        p0Base: const CadPoint2D(104.65180361560647, 188.00714267493925),
        u0: const CadPoint2D(-_invSqrt2, -_invSqrt2),
        v0: const CadPoint2D(-_invSqrt2, _invSqrt2),
        vFunc: (u) => CadPoint2D(u.y, -u.x),
        p0: newF16Verts[7],
        p1: newF16Verts[0],
        heightHoriz: effectiveP4H,
        dHeightHoriz: dH4,
        heightVert: effectiveP1H,
        dHeightVert: dH1,
        punchRotation: 135.0,
        newPunchVertId: 'SLOT_6_B',
      ),
    ];

    final quadByFace = <String, _QuadrantSpec>{};
    final quadByBend = <String, _QuadrantSpec>{};
    final quadByArc = <String, _QuadrantSpec>{};
    final quadByPunch = <String, _QuadrantSpec>{};

    for (final q in quadrants) {
      quadByFace[q.cheekId] = q;
      quadByFace[q.flapHorizId] = q;
      quadByFace[q.flapVertId] = q;
      quadByFace[q.flangeId] = q;

      quadByBend[q.bendBaseId] = q;
      quadByBend[q.bendHorizId] = q;
      quadByBend[q.bendVertId] = q;
      quadByBend[q.bendFlangeId] = q;

      quadByArc[q.baseArcHorizId] = q;
      quadByArc[q.topArcHorizId] = q;
      quadByArc[q.baseArcVertId] = q;
      quadByArc[q.topArcVertId] = q;

      for (final pid in q.punchesHoriz) {
        quadByPunch[pid] = q;
      }
      for (final pid in q.punchesVert) {
        quadByPunch[pid] = q;
      }
    }

    // 3. Local-to-Global Point Transformation in Quadrant Frame
    CadPoint2D transformQuadPt(CadPoint2D pt, _QuadrantSpec q, {String? fid, String? bid, String? pid, String? aid}) {
      final p0Base = q.p0Base;
      final u0 = q.u0;
      final v0 = q.v0;

      final rx = pt.x - p0Base.x;
      final ry = pt.y - p0Base.y;
      final lu = rx * u0.x + ry * u0.y;
      final lv = rx * v0.x + ry * v0.y;

      final double luStar;
      if (lu > 20.0) {
        luStar = q.lB + (lu - 40.0);
      } else {
        luStar = lu;
      }

      final dHh = q.dHeightHoriz;
      final dHv = q.dHeightVert;
      final hh = q.heightHoriz;
      final hv = q.heightVert;

      double lvStar = lv;

      if (fid == q.flapHorizId || bid == q.bendHorizId) {
        if (lv > 20.0) lvStar = lv + dHh;
      } else if (fid == q.flapVertId || bid == q.bendVertId) {
        if (lv > 20.0) lvStar = lv + dHv;
      } else if (fid == q.flangeId || bid == q.bendFlangeId) {
        lvStar = lv + dHBody;
      } else if (fid == q.cheekId) {
        if (lv < 5.0) {
          lvStar = lv;
        } else if (lu > 20.0) {
          if (lv < 70.0) {
            lvStar = lv + dHv;
          } else {
            lvStar = lv + dHBody;
          }
        } else {
          lvStar = lv + dHBody;
        }
      } else if (aid != null) {
        if (aid == q.topArcHorizId) {
          lvStar = lv + dHh;
        } else if (aid == q.topArcVertId) {
          lvStar = lv + dHv;
        } else {
          lvStar = lv;
        }
      } else if (pid != null) {
        if (q.punchesHoriz.contains(pid)) {
          if (pid == q.punchesHoriz[0]) {
            if (hh < 95.0) {
              lvStar = lv + (dHh + 50.0) / 2.0;
            } else {
              lvStar = lv;
            }
          } else {
            lvStar = lv + dHh;
          }
        } else if (q.punchesVert.contains(pid)) {
          if (hv < 95.0) {
            lvStar = lv + dHv / 2.0;
          } else {
            lvStar = lv;
          }
        }
      }

      final gx = q.p0.x + luStar * q.uAxis.x + lvStar * q.vAxis.x;
      final gy = q.p0.y + luStar * q.uAxis.y + lvStar * q.vAxis.y;
      return CadPoint2D(gx, gy);
    }

    // 4. Transform Faces
    final faceVertexMap = <String, CadPoint2D>{};
    final newFaces = <PlanarSheetFace>[];

    for (final f in baseline.faces) {
      final fid = f.id;
      if (fid == 'F_16' || f.isBaseAnchor || f.role == FaceRole.baseFloor) {
        newFaces.add(f.copyWith(vertices: newF16Verts));
        for (int vi = 0; vi < newF16Verts.length; vi++) {
          faceVertexMap['F_16_v$vi'] = newF16Verts[vi];
        }
        continue;
      }

      final q = quadByFace[fid];
      if (q == null) {
        newFaces.add(f);
        continue;
      }

      final nverts = <CadPoint2D>[];
      for (int vi = 0; vi < f.vertices.length; vi++) {
        final nv = transformQuadPt(f.vertices[vi], q, fid: fid);
        nverts.add(nv);
        faceVertexMap['${fid}_v$vi'] = nv;
      }

      // Orthogonal step vertex synthesis when body exceeds horizontal port height:
      if (fid == q.cheekId && dHBody > q.dHeightHoriz + 1e-4) {
        // Synthesize the horizontal flange junction vertex at (lu=0, lv=98.0 + dHBody)
        // to form a closed orthogonal vertical step down to the coupler flap at (lu=0, lv=98.0 + dHh).
        final p0 = q.p0;
        final v = q.vAxis;
        final lvFlange = 98.0 + dHBody;
        final stepJunction = CadPoint2D(p0.x + lvFlange * v.x, p0.y + lvFlange * v.y);
        nverts.add(stepJunction);
      }

      newFaces.add(f.copyWith(vertices: nverts));
    }

    // 5. Transform Bends
    final newBends = baseline.bends.map((b) {
      final bid = b.id;
      final q = quadByBend[bid];
      if (q == null) return b;

      final np1 = transformQuadPt(b.p1, q, bid: bid);
      final np2 = transformQuadPt(b.p2, q, bid: bid);

      double newTargetAngle = b.targetAngleDeg;
      if (bid == q.bendHorizId) {
        newTargetAngle = q.angleHorizDeg;
      } else if (bid == q.bendVertId) {
        newTargetAngle = q.angleVertDeg;
      }

      return b.copyWith(
        p1: np1,
        p2: np2,
        targetAngleDeg: newTargetAngle,
      );
    }).toList();

    // 6. Transform Arcs (preserving radius 10.0mm and rotating startAngle cleanly)
    final newArcs = baseline.arcs.map((a) {
      final aid = a.id;
      final q = quadByArc[aid];
      if (q == null) return a;

      final nc = transformQuadPt(a.center, q, aid: aid);
      final newStartAngle = a.startAngleRad + q.deltaTheta;
      return a.copyWith(center: nc, startAngleRad: newStartAngle);
    }).toList();

    // 7. Transform Punches with Universal 95mm Coupler Rule
    final suppressedPunchIds = <String>{};
    if (effectiveP2H < 95.0) {
      suppressedPunchIds.addAll({'SLOT_8', 'PUNCH_CPY_8064'});
    }
    if (effectiveP4H < 95.0) {
      suppressedPunchIds.addAll({'SLOT_5', 'SLOT_11'});
    }

    final newPunches = baseline.punches.where((p) => !suppressedPunchIds.contains(p.id)).map((p) {
      final pid = p.id;
      final q = quadByPunch[pid];
      if (q == null) return p;

      final nc = transformQuadPt(p.center, q, pid: pid);
      final newRot = p.rotationDeg + (q.deltaTheta * 180.0 / math.pi);
      return p.copyWith(center: nc, rotationDeg: newRot);
    }).toList();

    // Synthesize second coupler slot on vertical flaps when height >= 95mm (at 50mm pitch)
    for (final q in quadrants) {
      if (q.heightVert >= 95.0) {
        const uStar = 58.0;
        final vStar = 74.0 + (q.dHeightVert > 50.0 ? (q.dHeightVert - 50.0) : 0.0);
        final luStar = q.lB + (uStar - 40.0);
        final p0 = q.p0;
        final u = q.uAxis;
        final v = q.vAxis;
        final slotCenter = CadPoint2D(p0.x + luStar * u.x + vStar * v.x, p0.y + luStar * u.y + vStar * v.y);
        newPunches.add(
          CncPunchPrimitive(
            id: q.newPunchVertId,
            type: PunchType.obroundSlot,
            center: slotCenter,
            widthMm: 8.0,
            lengthMm: 20.0,
            rotationDeg: q.punchRotation + (q.deltaTheta * 180.0 / math.pi),
            role: CncPunchRole.coupler,
            parentFaceId: q.flapVertId,
            associatedPortId: q.name == 'Q1_NE' || q.name == 'Q3_SE' ? 'PORT_3' : 'PORT_1',
          ),
        );
      }
    }

    // 9. Transform Continuous Outer Contour by mapping directly to face vertices
    final newContour = <CadPoint2D>[];
    for (int ci = 0; ci < baseline.outerContour.length; ci++) {
      final cp = baseline.outerContour[ci];
      CadPoint2D? matchedPt;

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
      newContour.add(matchedPt ?? cp);
    }

    // 10. Update Document Parameters Map
    final updatedParameters = Map<String, double>.from(baseline.parameters);
    updatedParameters['port1Width'] = parameters.port1Width;
    updatedParameters['port1Height'] = parameters.port1Height;
    updatedParameters['port2Width'] = parameters.port2Width;
    updatedParameters['port2Height'] = parameters.port2Height;
    updatedParameters['port3Width'] = parameters.port3Width;
    updatedParameters['port3Height'] = parameters.port3Height;
    updatedParameters['port4Width'] = parameters.port4Width;
    updatedParameters['port4Height'] = parameters.port4Height;

    updatedParameters['port1_width'] = parameters.port1Width;
    updatedParameters['port1_height'] = parameters.port1Height;
    updatedParameters['port2_width'] = parameters.port2Width;
    updatedParameters['port2_height'] = parameters.port2Height;
    updatedParameters['port3_width'] = parameters.port3Width;
    updatedParameters['port3_height'] = parameters.port3Height;
    updatedParameters['port4_width'] = parameters.port4Width;
    updatedParameters['port4_height'] = parameters.port4Height;

    updatedParameters['width'] = parameters.port2Width;
    updatedParameters['height'] = bodyHeight;

    final scaledDoc = baseline.copyWith(
      outerContour: newContour,
      faces: newFaces,
      bends: newBends,
      punches: newPunches,
      arcs: newArcs,
      parameters: updatedParameters,
    );

    return UnequalCrossScaleResult(
      document: scaledDoc,
      isValid: true,
      diagnostics: {
        'status': 'scaled_success',
        'dW1': dW1,
        'dW2': dW2,
        'dW3': dW3,
        'dW4': dW4,
        'dHBody': dHBody,
        'dH1': dH1,
        'dH2': dH2,
        'dH3': dH3,
        'dH4': dH4,
        'bodyHeight': bodyHeight,
        'arcCount': newArcs.length,
        'punchCount': newPunches.length,
      },
    );
  }
}
