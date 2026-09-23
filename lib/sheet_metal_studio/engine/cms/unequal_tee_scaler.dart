// =============================================================================
// unequal_tee_scaler.dart
//
// Dedicated Parametric Scaling Engine for Unequal Tee Fittings.
// Implements the Analytical Geometry Rule:
// "Do not move DXF entities because they happen to be in S1/S3.
//  Calculate the new Tee geometry from the port dimensions,
//  then reconstruct the dependent entities from that solved geometry."
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
    double defaultH2 = 100.0,
    double defaultW3 = 100.0,
    double defaultH3 = 100.0,
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

    return UnequalTeeScaleParameters(
      port1Width: getVal('port1_width', defaultW1),
      port1Height: getVal('port1_height', defaultH1),
      port2Width: getVal('port2_width', defaultW2),
      port2Height: getVal('port2_height', defaultH2),
      port3Width: getVal('port3_width', defaultW3),
      port3Height: getVal('port3_height', defaultH3),
      dW1: getDelta('port1_width'),
      dH1: getDelta('port1_height'),
      dW2: getDelta('port2_width'),
      dH2: getDelta('port2_height'),
      dW3: getDelta('port3_width'),
      dH3: getDelta('port3_height'),
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
      dH3.abs() > 1e-4;

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
    // If the user has not changed any values (e.g. initial dialog opening),
    // return the baseline template 100% untouched.
    if (!parameters.hasAnyChange) {
      return UnequalTeeScaleResult(
        document: baseline,
        isValid: true,
        diagnostics: {'status': 'unchanged_baseline'},
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
    final minY = verts.map((v) => v.y).reduce(math.min);
    final maxY = verts.map((v) => v.y).reduce(math.max);
    final midX = (minX + maxX) / 2.0;

    final dW1 = parameters.dW1;
    final dW2 = parameters.dW2;
    final dW3 = parameters.dW3;
    final dH1 = parameters.dH1;
    final dH2 = parameters.dH2;
    final dH3 = parameters.dH3;
    final dHBody = math.max(dH1, math.max(dH2, dH3));

    // 3. Right Cheek Coordinate Frame Setup
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

    // 3.1 Point transformation functions
    CadPoint2D transformRightPt(CadPoint2D pt) {
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

      final double vStar;
      if (dHBody.abs() > 1e-4 && v > 50.0) {
        vStar = v + dHBody;
      } else {
        vStar = v;
      }

      return CadPoint2D(
        pBotX + uStar * uX + vStar * vX,
        pBotY + uStar * uY + vStar * vY,
      );
    }

    CadPoint2D transformBackPt(CadPoint2D pt) {
      final double dx = pt.x < midX ? -dW1 / 2.0 : dW1 / 2.0;
      double dy = dW3;
      if (dHBody.abs() > 1e-4 && pt.y > maxY + 45.0) {
        dy += dHBody;
      }
      return CadPoint2D(pt.x + dx, pt.y + dy);
    }

    CadPoint2D transformLeftPt(CadPoint2D pt) {
      double x = pt.x - dW1 / 2.0;
      double y = pt.y;
      if (dHBody.abs() > 1e-4 && (pt.x + pt.y) < (minX + minY + 25.0)) {
        x -= dHBody / math.sqrt2;
        y -= dHBody / math.sqrt2;
      }
      return CadPoint2D(x, y);
    }

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
          nv = transformRightPt(v);
        } else if (_backFaceIds.contains(fid)) {
          nv = transformBackPt(v);
        } else if (_leftFaceIds.contains(fid)) {
          nv = transformLeftPt(v);
        } else if (fid == 'F_10') {
          nv = transformFloorPt(vi, v);
        } else {
          nv = v;
        }
        newVertices.add(nv);
        faceVertexMap['${fid}_v$vi'] = nv;
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
        newP1 = transformRightPt(b.p1);
        newP2 = transformRightPt(b.p2);
        if (bid == 'B4') {
          newTargetAngle = theta * 180.0 / math.pi;
        } else if (bid == 'B6') {
          newTargetAngle = 90.0 - (theta * 180.0 / math.pi);
        }
      } else if (_backBendIds.contains(bid)) {
        newP1 = transformBackPt(b.p1);
        newP2 = transformBackPt(b.p2);
      } else if (_leftBendIds.contains(bid)) {
        newP1 = transformLeftPt(b.p1);
        newP2 = transformLeftPt(b.p2);
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
    for (final cp in baseline.outerContour) {
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

    // 7. Transform Rigid Coupler Punches (preserving dimensions and tracking rotation)
    final newPunches = baseline.punches.map((p) {
      final pid = p.id;
      final CadPoint2D newCenter;
      double newRotation = p.rotationDeg;

      if (_rightPunchIds.contains(pid)) {
        newCenter = transformRightPt(p.center);
        newRotation = (newRotation + (deltaTheta * 180.0 / math.pi)) % 360.0;
      } else if (_backPunchIds.contains(pid)) {
        newCenter = transformBackPt(p.center);
      } else if (_leftPunchIds.contains(pid)) {
        newCenter = transformLeftPt(p.center);
      } else {
        newCenter = p.center;
      }

      return p.copyWith(
        center: newCenter,
        rotationDeg: newRotation,
      );
    }).toList();

    // 8. Transform All 12 Corner Arcs (preserving radii and rotating with parent face)
    final newArcs = baseline.arcs.map((a) {
      final aid = a.id;
      final CadPoint2D newCenter;
      double newStartAngle = a.startAngleRad;

      if (_rightArcIds.contains(aid)) {
        newCenter = transformRightPt(a.center);
        newStartAngle = (a.startAngleRad + deltaTheta) % (2 * math.pi);
      } else if (_backArcIds.contains(aid)) {
        newCenter = transformBackPt(a.center);
      } else if (_leftArcIds.contains(aid)) {
        newCenter = transformLeftPt(a.center);
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
    updatedParameters['height'] = parameters.maxHeight;
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
        'lB2': lB2,
        'thetaB2Deg': theta * 180.0 / math.pi,
        'arcCount': newArcs.length,
        'punchCount': newPunches.length,
      },
    );
  }
}
