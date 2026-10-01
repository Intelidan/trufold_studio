// =============================================================================
// tray_bend_geometry_solver.dart
//
// Four-Tier Modular Analytical Geometry Solver for Cable Tray Bends (45° and 90°).
// Production Specification v3.5.
//
// Solvers:
// 1. solveBendRadius: Handles inside throat arc, tangent offsets, and B1 chord.
// 2. solveWingGeometry: Analytical wing growth K_wing = tan(θ_p)*(1 - sin(θ_p)).
// 3. solveBaseRedistribution: Straight base span L_B2 = Span - 2 * WingTakeUp.
// 4. solveCouplerPattern: Explicit HeightRows × WingColumns grid generation.
// =============================================================================

import 'dart:math' as math;
import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';

/// Solution state containing all derived geometric entities for a tray bend.
class TrayBendSolution {
  final double bendAngleDeg;
  final double thetaP; // Half-bend / port angle in radians
  final double width;
  final double height;
  final double radius;

  // Inside wall (B1)
  final double lB1;
  final CadPoint2D p1Out;
  final CadPoint2D p2Out;

  // Port inner corners (starts of wings)
  final CadPoint2D p1In;
  final CadPoint2D p2In;

  // Wings
  final double lWing;
  final double wingTakeUp;
  final CadPoint2D c1; // Inner corner where left wing meets center base
  final CadPoint2D c2; // Inner corner where right wing meets center base

  // Center straight base wall (B2)
  final double lB2;
  final double yB2;

  // Coupler pattern grid
  final int heightRows;
  final int wingColumns;
  final int totalWingPositions;

  const TrayBendSolution({
    required this.bendAngleDeg,
    required this.thetaP,
    required this.width,
    required this.height,
    required this.radius,
    required this.lB1,
    required this.p1Out,
    required this.p2Out,
    required this.p1In,
    required this.p2In,
    required this.lWing,
    required this.wingTakeUp,
    required this.c1,
    required this.c2,
    required this.lB2,
    required this.yB2,
    required this.heightRows,
    required this.wingColumns,
    required this.totalWingPositions,
  });
}

class TrayBendGeometrySolver {
  /// Computes the four-tier analytical solution for a given tray bend.
  static TrayBendSolution solve({
    required double bendAngleDeg,
    required double targetWidth,
    required double targetHeight,
    required double targetRadius,
    required double xMidBase,
    required double yB1Base,
    required double lB1Base,
    required double lWingBase,
  }) {
    // 0. Preliminary parameters
    final thetaP = (bendAngleDeg / 2.0) * (math.pi / 180.0);
    final sinTheta = math.sin(thetaP);
    final cosTheta = math.cos(thetaP);
    final tanTheta = math.tan(thetaP);

    // 1. Tier 1: solveBendRadius
    // B1 is invariant to Width. Baseline at R=180 reproduces lB1Base exactly.
    final deltaR = targetRadius - 180.0;
    final lB1 = lB1Base + 2.0 * deltaR * math.tan(thetaP / 2.0);
    final p1Out = CadPoint2D(xMidBase - lB1 / 2.0, yB1Base);
    final p2Out = CadPoint2D(xMidBase + lB1 / 2.0, yB1Base);

    // 2. Tier 2: solveWingGeometry
    // Ports incline outward by thetaP
    final p1In = CadPoint2D(
      p1Out.x - targetWidth * sinTheta,
      p1Out.y + targetWidth * cosTheta,
    );
    final p2In = CadPoint2D(
      p2Out.x + targetWidth * sinTheta,
      p2Out.y + targetWidth * cosTheta,
    );

    // Analytical wing growth coefficient: K_wing = tan(θ_p) * (1 - sin(θ_p))
    final kWing = tanTheta * (1.0 - sinTheta);
    final deltaW = targetWidth - 100.0;
    final deltaWingR = deltaR * math.tan(thetaP / 2.0) * sinTheta;
    final lWing = lWingBase + kWing * deltaW + deltaWingR;

    // Wing direction unit vectors:
    // Left wing runs from p1In towards center at angle +thetaP from horizontal
    final uWing1 = CadPoint2D(cosTheta, sinTheta);
    // Right wing runs from p2In towards center at angle -thetaP from horizontal
    final uWing2 = CadPoint2D(-cosTheta, sinTheta);

    final c1 = CadPoint2D(
      p1In.x + lWing * uWing1.x,
      p1In.y + lWing * uWing1.y,
    );
    final c2 = CadPoint2D(
      p2In.x + lWing * uWing2.x,
      p2In.y + lWing * uWing2.y,
    );

    // 3. Tier 3: solveBaseRedistribution
    final wingTakeUp = lWing * cosTheta;
    final totalSpan = p2In.x - p1In.x;
    final lB2 = totalSpan - 2.0 * wingTakeUp;
    final yB2 = (c1.y + c2.y) / 2.0;

    // 4. Tier 4: solveCouplerPattern
    // For every 25mm increase in height, add 1 row of coupler holes (1 at 50, 2 at 75, 3 at 100, etc.)
    final heightRows = 1 + math.max<int>(0, ((targetHeight - 50.0) / 25.0).round());
    final wingColumns = targetWidth >= 300.0 ? 2 : 1;
    final wingHolesCount = 2 + math.max<int>(0, ((targetHeight - 50.0) / 25.0).round());
    final totalWingPositions = wingHolesCount * wingColumns;

    return TrayBendSolution(
      bendAngleDeg: bendAngleDeg,
      thetaP: thetaP,
      width: targetWidth,
      height: targetHeight,
      radius: targetRadius,
      lB1: lB1,
      p1Out: p1Out,
      p2Out: p2Out,
      p1In: p1In,
      p2In: p2In,
      lWing: lWing,
      wingTakeUp: wingTakeUp,
      c1: c1,
      c2: c2,
      lB2: lB2,
      yB2: yB2,
      heightRows: heightRows,
      wingColumns: wingColumns,
      totalWingPositions: totalWingPositions,
    );
  }

  /// Transforms planar sheet metal document entities using piecewise zonal mapping.
  static DsfDocument transformDocument({
    required DsfDocument baseline,
    required TrayBendSolution solution,
    required double xMidBase,
    required double yB1Base,
    required double lB1Base,
    required double lWingBase,
    required double c4XBase,
    required double c4YBase,
    required double c3XBase,
    required double c3YBase,
    required double p1InXBase,
    required double p1InYBase,
    required double p2InXBase,
    required double p2InYBase,
    bool includeCouplerFlaps = false,
    double couplerFlapLength = 30.0,
  }) {
    final W = solution.width;
    final H = solution.height;
    final dH = H - 50.0;
    final sinTheta = math.sin(solution.thetaP);
    final cosTheta = math.cos(solution.thetaP);

    final nWing1 = CadPoint2D(-sinTheta, cosTheta);
    final uWing1 = CadPoint2D(cosTheta, sinTheta);
    final nWing2 = CadPoint2D(sinTheta, cosTheta);
    final uWing2 = CadPoint2D(-cosTheta, sinTheta);

    final p1OutXBase = xMidBase - lB1Base / 2.0;
    final p2OutXBase = xMidBase + lB1Base / 2.0;

    // Piecewise point transformer
    CadPoint2D transformPt(CadPoint2D pt) {
      final x = pt.x;
      final y = pt.y;

      // 1. Inside Wall & Return Flange FL1 (y <= yB1Base + 0.001)
      if (y <= yB1Base + 0.001) {
        final tX = (x - p1OutXBase) / (p2OutXBase - p1OutXBase);
        final nx = solution.p1Out.x + tX * (solution.p2Out.x - solution.p1Out.x);

        double ny = y;
        if (y < yB1Base - 0.001) {
          final distFromB1 = yB1Base - y;
          if (distFromB1 >= 45.0) {
            // Return flange point: translate with dH
            ny = y - dH;
          } else {
            // Sidewall point: stretch with H / 50.0
            ny = yB1Base - distFromB1 * (H / 50.0);
          }
        }
        return CadPoint2D(nx, ny);
      }

      // 2. Left Wing Wall & Return Flange FL2/FL4
      final relX1 = x - p1InXBase;
      final relY1 = y - p1InYBase;
      final u1 = relX1 * uWing1.x + relY1 * uWing1.y;
      final v1 = relX1 * nWing1.x + relY1 * nWing1.y;

      if (v1 > -0.5 && u1 >= -5.0 && u1 <= lWingBase + 10.0 && x <= c4XBase + 0.5) {
        final uNorm = (u1 / lWingBase).clamp(0.0, 1.0);
        final scaledU = uNorm * solution.lWing;

        double newV1 = v1;
        if (v1 > 1.0) {
          if (v1 >= 48.0) {
            newV1 = v1 + dH;
          } else {
            newV1 = v1 * (H / 50.0);
          }
        }
        return CadPoint2D(
          solution.p1In.x + scaledU * uWing1.x + newV1 * nWing1.x,
          solution.p1In.y + scaledU * uWing1.y + newV1 * nWing1.y,
        );
      }

      // 3. Right Wing Wall & Return Flange FL3
      final relX2 = x - p2InXBase;
      final relY2 = y - p2InYBase;
      final u2 = relX2 * uWing2.x + relY2 * uWing2.y;
      final v2 = relX2 * nWing2.x + relY2 * nWing2.y;

      if (v2 > -0.5 && u2 >= -5.0 && u2 <= lWingBase + 10.0 && x >= c3XBase - 0.5) {
        final uNorm = (u2 / lWingBase).clamp(0.0, 1.0);
        final scaledU = uNorm * solution.lWing;

        double newV2 = v2;
        if (v2 > 1.0) {
          if (v2 >= 48.0) {
            newV2 = v2 + dH;
          } else {
            newV2 = v2 * (H / 50.0);
          }
        }
        return CadPoint2D(
          solution.p2In.x + scaledU * uWing2.x + newV2 * nWing2.x,
          solution.p2In.y + scaledU * uWing2.y + newV2 * nWing2.y,
        );
      }

      // 4. Center Straight Base Wall & Flange (y >= c4YBase - 0.001, between c4 and c3)
      if (y >= c4YBase - 0.001) {
        final tX = (x - c4XBase) / math.max(1.0, c3XBase - c4XBase);
        final nx = solution.c1.x + tX * (solution.c2.x - solution.c1.x);

        final distY = y - c4YBase;
        double ny = solution.yB2;
        if (distY > 1.0) {
          if (distY >= 48.0) {
            ny = solution.yB2 + distY + dH;
          } else {
            ny = solution.yB2 + distY * (H / 50.0);
          }
        }
        return CadPoint2D(nx, ny);
      }

      // 5. Floor Web: smoothly mapped between top B1 and bottom inner walls B2/wings
      final tY = ((y - yB1Base) / (c4YBase - yB1Base)).clamp(0.0, 1.0);
      final ny = yB1Base + tY * (solution.yB2 - yB1Base);

      final xLeftBase = (1.0 - tY) * p1OutXBase + tY * c4XBase;
      final xRightBase = (1.0 - tY) * p2OutXBase + tY * c3XBase;
      final tX = (x - xLeftBase) / math.max(1.0, xRightBase - xLeftBase);

      final xLeftNew = (1.0 - tY) * solution.p1Out.x + tY * solution.c1.x;
      final xRightNew = (1.0 - tY) * solution.p2Out.x + tY * solution.c2.x;
      final nx = xLeftNew + tX * (xRightNew - xLeftNew);

      return CadPoint2D(nx, ny);
    }

    // 1. Transform Contour
    final newOuterContour = baseline.outerContour.map(transformPt).toList();

    // 2. Transform Bend Lines
    final newBends = baseline.bends.map((b) {
      return b.copyWith(
        p1: transformPt(b.p1),
        p2: transformPt(b.p2),
      );
    }).toList();

    // 3. Transform Faces
    final newFaces = baseline.faces.map((f) {
      return f.copyWith(
        vertices: f.vertices.map(transformPt).toList(),
      );
    }).toList();

    // 4. Transform Cut Lines
    final newCutLines = baseline.cutLines.map((cl) {
      return cl.copyWith(
        p1: transformPt(cl.p1),
        p2: transformPt(cl.p2),
      );
    }).toList();

    // 5. Generate Reconstructed Punches
    final newPunches = generatePunches(
      baseline: baseline,
      solution: solution,
      nWing1: nWing1,
      uWing1: uWing1,
      nWing2: nWing2,
      uWing2: uWing2,
    );

    final List<CadPoint2D> effectiveOuterContour;
    final List<FoldBendLine> effectiveBends;
    final List<PlanarSheetFace> effectiveFaces;
    final effectivePunches = List<CncPunchPrimitive>.from(newPunches);

    if (includeCouplerFlaps) {
      // Body coupler holes on the side walls are made invisible so they do not overlap
      // with the coupler flap connecting holes. They remain in the document and become
      // visible again if coupler flaps are toggled off.
      for (int i = 0; i < effectivePunches.length; i++) {
        if (effectivePunches[i].role == CncPunchRole.coupler) {
          effectivePunches[i] = effectivePunches[i].copyWith(isVisible: false);
        }
      }

      final lf = couplerFlapLength;
      final thetaDeg = solution.thetaP * 180.0 / math.pi;
      final dirPort1 = CadPoint2D(-cosTheta, -sinTheta);
      final dirPort2 = CadPoint2D(cosTheta, -sinTheta);

      String findFaceIdAt(CadPoint2D pt, String defaultId) {
        for (final f in newFaces) {
          if (f.role == FaceRole.sideWall && f.vertices.any((v) => (v.x - pt.x).abs() < 2.0 && (v.y - pt.y).abs() < 2.0)) {
            return f.id;
          }
        }
        return defaultId;
      }

      final throatParent1 = findFaceIdAt(solution.p1Out, 'F_8');
      final wingParent1 = findFaceIdAt(solution.p1In, 'F_1');
      final throatParent2 = findFaceIdAt(solution.p2Out, 'F_8');
      final wingParent2 = findFaceIdAt(solution.p2In, 'F_3');

      final throatTop1 = CadPoint2D(solution.p1Out.x, solution.p1Out.y - H);
      final fFlapThroat1 = PlanarSheetFace(
        id: 'F_FLAP_THROAT_P1',
        role: FaceRole.sideWall,
        vertices: createChamferedFlapVertices(
          base: solution.p1Out,
          top: throatTop1,
          uDir: const CadPoint2D(-1.0, 0.0),
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap Port 1 Throat',
      );

      final wingTop1 = CadPoint2D(solution.p1In.x + H * nWing1.x, solution.p1In.y + H * nWing1.y);
      final fFlapWing1 = PlanarSheetFace(
        id: 'F_FLAP_WING_P1',
        role: FaceRole.sideWall,
        vertices: createChamferedFlapVertices(
          base: solution.p1In,
          top: wingTop1,
          uDir: dirPort1,
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap Port 1 Wing',
      );

      final throatTop2 = CadPoint2D(solution.p2Out.x, solution.p2Out.y - H);
      final fFlapThroat2 = PlanarSheetFace(
        id: 'F_FLAP_THROAT_P2',
        role: FaceRole.sideWall,
        vertices: createChamferedFlapVertices(
          base: solution.p2Out,
          top: throatTop2,
          uDir: const CadPoint2D(1.0, 0.0),
          flapLength: lf,
          reverseWinding: true,
        ),
        label: 'Coupler Flap Port 2 Throat',
      );

      final wingTop2 = CadPoint2D(solution.p2In.x + H * nWing2.x, solution.p2In.y + H * nWing2.y);
      final fFlapWing2 = PlanarSheetFace(
        id: 'F_FLAP_WING_P2',
        role: FaceRole.sideWall,
        vertices: createChamferedFlapVertices(
          base: solution.p2In,
          top: wingTop2,
          uDir: dirPort2,
          flapLength: lf,
          reverseWinding: false,
        ),
        label: 'Coupler Flap Port 2 Wing',
      );

      effectiveFaces = [...newFaces, fFlapThroat1, fFlapWing1, fFlapThroat2, fFlapWing2];

      final bfThroat1 = FoldBendLine(
        id: 'BF_THROAT_P1',
        p1: solution.p1Out,
        p2: throatTop1,
        targetAngleDeg: thetaDeg,
        role: BendLineRole.bend,
        parentFaceId: throatParent1,
        childFaceId: 'F_FLAP_THROAT_P1',
        direction: BendDirection.down,
      );

      final bfWing1 = FoldBendLine(
        id: 'BF_WING_P1',
        p1: solution.p1In,
        p2: wingTop1,
        targetAngleDeg: 0.0, // Wing wall is already parallel to connecting tray run
        role: BendLineRole.bend,
        parentFaceId: wingParent1,
        childFaceId: 'F_FLAP_WING_P1',
        direction: BendDirection.down,
      );

      final bfThroat2 = FoldBendLine(
        id: 'BF_THROAT_P2',
        p1: solution.p2Out,
        p2: throatTop2,
        targetAngleDeg: thetaDeg,
        role: BendLineRole.bend,
        parentFaceId: throatParent2,
        childFaceId: 'F_FLAP_THROAT_P2',
        direction: BendDirection.down,
      );

      final bfWing2 = FoldBendLine(
        id: 'BF_WING_P2',
        p1: solution.p2In,
        p2: wingTop2,
        targetAngleDeg: 0.0, // Wing wall is already parallel to connecting tray run
        role: BendLineRole.bend,
        parentFaceId: wingParent2,
        childFaceId: 'F_FLAP_WING_P2',
        direction: BendDirection.down,
      );

      effectiveBends = [...newBends, bfThroat1, bfWing1, bfThroat2, bfWing2];
      effectiveOuterContour = newOuterContour;

      // Flap punches
      final sampleSlot = baseline.punches.firstWhere(
        (p) => p.isSlot || p.type == PunchType.obroundSlot,
        orElse: () => baseline.punches.first,
      );
      int flapSlotCounter = 100;
      final slotLen = math.min(20.0, math.max(12.0, lf - 8.0));
      void addFlapSlot({
        required CadPoint2D origin,
        required CadPoint2D uDir,
        required CadPoint2D vDir,
        required double rotDeg,
      }) {
        if (H <= 50.0) {
          final u = lf / 2.0;
          final vOffsets = [H * 0.3, H * 0.7];
          for (final v in vOffsets) {
            effectivePunches.add(sampleSlot.copyWith(
              id: 'FLAP_SLOT_${flapSlotCounter++}',
              center: CadPoint2D(origin.x + u * uDir.x + v * vDir.x, origin.y + u * uDir.y + v * vDir.y),
              lengthMm: slotLen,
              role: CncPunchRole.coupler,
              rotationDeg: rotDeg,
              isVisible: true,
            ));
          }
        } else {
          final uCols = [lf * 0.35, lf * 0.75];
          final vOffsets = [H / 2.0 - 25.0, H / 2.0 + 25.0];
          for (final u in uCols) {
            for (final v in vOffsets) {
              effectivePunches.add(sampleSlot.copyWith(
                id: 'FLAP_SLOT_${flapSlotCounter++}',
                center: CadPoint2D(origin.x + u * uDir.x + v * vDir.x, origin.y + u * uDir.y + v * vDir.y),
                lengthMm: slotLen,
                role: CncPunchRole.coupler,
                rotationDeg: rotDeg,
                isVisible: true,
              ));
            }
          }
        }
      }

      addFlapSlot(origin: solution.p1Out, uDir: const CadPoint2D(-1.0, 0.0), vDir: const CadPoint2D(0.0, -1.0), rotDeg: 0.0);
      addFlapSlot(origin: solution.p1In, uDir: dirPort1, vDir: nWing1, rotDeg: (math.atan2(dirPort1.y, dirPort1.x) * 180.0 / math.pi) % 180.0);
      addFlapSlot(origin: solution.p2Out, uDir: const CadPoint2D(1.0, 0.0), vDir: const CadPoint2D(0.0, -1.0), rotDeg: 0.0);
      addFlapSlot(origin: solution.p2In, uDir: dirPort2, vDir: nWing2, rotDeg: (math.atan2(dirPort2.y, dirPort2.x) * 180.0 / math.pi) % 180.0);
    } else {
      effectiveOuterContour = newOuterContour;
      effectiveBends = newBends;
      effectiveFaces = newFaces;
    }

    // 6. Return updated DSF Document
    final newParams = Map<String, double>.from(baseline.parameters);
    newParams['width'] = W;
    newParams['height'] = H;
    newParams['radius'] = solution.radius;
    newParams['bend_angle'] = solution.bendAngleDeg;
    newParams['wing_length'] = solution.lWing;
    newParams['straight_base_span'] = solution.lB2;
    newParams['wing_take_up'] = solution.wingTakeUp;
    newParams['coupler_rows'] = solution.heightRows.toDouble();
    newParams['coupler_columns'] = solution.wingColumns.toDouble();

    return baseline.copyWith(
      outerContour: effectiveOuterContour,
      bends: effectiveBends,
      faces: effectiveFaces,
      cutLines: newCutLines,
      punches: effectivePunches,
      parameters: newParams,
    );
  }

  /// Creates a 6-vertex planar flap polygon with 45° corner cuts / chamfers on both outer corners.
  static List<CadPoint2D> createChamferedFlapVertices({
    required CadPoint2D base,
    required CadPoint2D top,
    required CadPoint2D uDir,
    required double flapLength,
    double chamferSize = 8.0,
    bool reverseWinding = false,
  }) {
    final lf = flapLength;
    final dx = top.x - base.x;
    final dy = top.y - base.y;
    final H = math.sqrt(dx * dx + dy * dy);
    final vDir = H > 1e-6 ? CadPoint2D(dx / H, dy / H) : const CadPoint2D(0.0, 1.0);
    final c = math.min(chamferSize, math.min(lf * 0.35, H * 0.25));

    final p0 = base;
    final p1 = top;
    final p2 = CadPoint2D(top.x + (lf - c) * uDir.x, top.y + (lf - c) * uDir.y);
    final p3 = CadPoint2D(top.x + lf * uDir.x - c * vDir.x, top.y + lf * uDir.y - c * vDir.y);
    final p4 = CadPoint2D(base.x + lf * uDir.x + c * vDir.x, base.y + lf * uDir.y + c * vDir.y);
    final p5 = CadPoint2D(base.x + (lf - c) * uDir.x, base.y + (lf - c) * uDir.y);

    if (reverseWinding) {
      return [p0, p5, p4, p3, p2, p1];
    }
    return [p0, p1, p2, p3, p4, p5];
  }

  /// Generates the deterministic coupler and perforation punch pattern.
  static List<CncPunchPrimitive> generatePunches({
    required DsfDocument baseline,
    required TrayBendSolution solution,
    required CadPoint2D nWing1,
    required CadPoint2D uWing1,
    required CadPoint2D nWing2,
    required CadPoint2D uWing2,
  }) {
    final punches = <CncPunchPrimitive>[];
    final sampleSlot = baseline.punches.firstWhere(
      (p) => p.isSlot || p.type == PunchType.obroundSlot,
      orElse: () => baseline.punches.first,
    );

    int idCounter = 1;
    String nextSlotId() => 'SLOT_${idCounter++}';

    final W = solution.width;
    final p1Out = solution.p1Out;
    final p2Out = solution.p2Out;
    final p1In = solution.p1In;
    final p2In = solution.p2In;
    final yB1 = p1Out.y;
    final xMid = (p1Out.x + p2Out.x) / 2.0;

    // --- A. Coupler Slots on Inside Wall (above B1) ---
    // For every 25mm increase, add 1 row of coupler holes at 25mm vertical pitch.
    // 2 slots near Left Port and 2 slots near Right Port.
    // Distance between middle coupler hole groups is increased to at least 75.0 mm (leaving a wider central bridge).
    const double centralBridge = 75.0;
    final double desiredPitch = solution.lB1 >= 275.0 ? 75.0 : 50.0;
    final double maxCol2 = xMid - centralBridge / 2.0;
    final double xCol1 = p1Out.x + 25.0;
    final double xCol2 = math.min(p1Out.x + 25.0 + desiredPitch, maxCol2);
    final double minCol3 = xMid + centralBridge / 2.0;
    final double xCol4 = p2Out.x - 25.0;
    final double xCol3 = math.max(p2Out.x - 25.0 - desiredPitch, minCol3);

    for (int row = 0; row < solution.heightRows; row++) {
      // Row pitch 25mm: row 0 at (yB1 - 25), row 1 at (yB1 - 50), row 2 at (yB1 - 75), etc.
      final yOffset = 25.0 + row * 25.0;
      final ySlot = yB1 - yOffset;

      // Port 1 outer mouth coupler pair
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(xCol1, ySlot),
        role: CncPunchRole.coupler,
        rotationDeg: 90.0,
      ));
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(xCol2, ySlot),
        role: CncPunchRole.coupler,
        rotationDeg: 90.0,
      ));

      // Port 2 outer mouth coupler pair
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(xCol3, ySlot),
        role: CncPunchRole.coupler,
        rotationDeg: 90.0,
      ));
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(xCol4, ySlot),
        role: CncPunchRole.coupler,
        rotationDeg: 90.0,
      ));
    }

    // --- B. Coupler Slots on Left Wing (attached to B4/B3) ---
    // For every 25mm increase in height, add 1 coupler hole (2 at 50, 3 at 75, 4 at 100, etc.)
    final wingHolesCount = 2 + math.max<int>(0, ((solution.height - 50.0) / 25.0).round());
    final wingRot1 = solution.bendAngleDeg == 45.0 ? 22.5 : 45.0;
    for (int col = 0; col < solution.wingColumns; col++) {
      final uShift = 25.0 + col * 50.0;
      for (int k = 0; k < wingHolesCount; k++) {
        final vShift = 12.5 + k * 25.0;
        final cp = CadPoint2D(
          p1In.x + uShift * uWing1.x + vShift * nWing1.x,
          p1In.y + uShift * uWing1.y + vShift * nWing1.y,
        );
        punches.add(sampleSlot.copyWith(
          id: nextSlotId(),
          center: cp,
          role: CncPunchRole.coupler,
          rotationDeg: wingRot1,
        ));
      }
    }

    // --- C. Coupler Slots on Right Wing ---
    final wingRot2 = solution.bendAngleDeg == 45.0 ? 157.5 : 135.0;
    for (int col = 0; col < solution.wingColumns; col++) {
      final uShift = 25.0 + col * 50.0;
      for (int k = 0; k < wingHolesCount; k++) {
        final vShift = 12.5 + k * 25.0;
        final cp = CadPoint2D(
          p2In.x + uShift * uWing2.x + vShift * nWing2.x,
          p2In.y + uShift * uWing2.y + vShift * nWing2.y,
        );
        punches.add(sampleSlot.copyWith(
          id: nextSlotId(),
          center: cp,
          role: CncPunchRole.coupler,
          rotationDeg: wingRot2,
        ));
      }
    }

    // --- D. Centerline Floor Perforations ---
    final floorDepth = solution.yB2 - yB1;
    final List<double> floorSlotsY;
    if (solution.bendAngleDeg == 45.0) {
      if (floorDepth < 200.0) {
        const numFloor = 2;
        final margin = (floorDepth - (numFloor - 1) * 50.0) / 2.0;
        floorSlotsY = [for (int i = 0; i < numFloor; i++) yB1 + margin + i * 50.0];
      } else {
        final numFloor = math.max(2, (floorDepth / 75.0).floor());
        final margin = (floorDepth - (numFloor - 1) * 75.0) / 2.0;
        floorSlotsY = [for (int i = 0; i < numFloor; i++) yB1 + margin + i * 75.0];
      }
    } else {
      // 90 deg bend
      if (floorDepth < 200.0) {
        floorSlotsY = [yB1 + floorDepth * 0.71];
      } else {
        final numFloor = math.max(2, (floorDepth / 75.0).floor());
        final margin = (floorDepth - (numFloor - 1) * 75.0) / 2.0;
        floorSlotsY = [for (int i = 0; i < numFloor; i++) yB1 + margin + i * 75.0];
      }
    }

    for (final y in floorSlotsY) {
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(xMid, y),
        role: CncPunchRole.perforation,
        rotationDeg: 0.0,
      ));
    }

    // --- E. Straight Side Wall Perforation ---
    // Single hole for up to 75mm height, 2 holes for >= 100mm height.
    // Centered horizontally at xMid on the straight side wall (between B2 and FL3).
    final int numSideWallHoles = solution.height >= 100.0 ? 2 : 1;
    final List<double> sideWallYOffsets;
    if (numSideWallHoles == 1) {
      sideWallYOffsets = [solution.yB2 + solution.height / 2.0];
    } else {
      sideWallYOffsets = [
        solution.yB2 + solution.height / 2.0 - 25.0,
        solution.yB2 + solution.height / 2.0 + 25.0,
      ];
    }

    for (final y in sideWallYOffsets) {
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(xMid, y),
        role: CncPunchRole.perforation,
        rotationDeg: 0.0,
      ));
    }

    // --- F. Diagonal Floor Perforations near Port Openings ---
    // Exact orientation aligned with port mouth vectors:
    // Port 1 (Left):  +22.5° for 45° bend, +45.0° for 90° bend.
    // Port 2 (Right): +157.5° for 45° bend, +135.0° for 90° bend.
    // Offset setback v = 20.0mm inward into the floor face.
    // Single hole for from 50mm to 75mm width, then 2 holes for up to 100mm width, and 3 holes for up to 200mm width.
    final int numDiag;
    if (W <= 75.0) {
      numDiag = 1;
    } else if (W <= 100.0) {
      numDiag = 2;
    } else if (W <= 200.0) {
      numDiag = 3;
    } else {
      numDiag = 3 + ((W - 200.0) / 100.0).ceil();
    }

    final rotDiag1 = solution.bendAngleDeg == 45.0 ? 22.5 : 45.0;
    final rotDiag2 = solution.bendAngleDeg == 45.0 ? 157.5 : 135.0;
    const vInward = 20.0;

    final sinTheta = math.sin(solution.thetaP);
    final cosTheta = math.cos(solution.thetaP);

    for (int i = 0; i < numDiag; i++) {
      final u = (W / numDiag) * (i + 0.5);

      // Port 1 (Left Ray): runs along (-sin θ, cos θ), inward normal (cos θ, sin θ)
      final x1 = p1Out.x - u * sinTheta + vInward * cosTheta;
      final y1 = p1Out.y + u * cosTheta + vInward * sinTheta;
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(x1, y1),
        role: CncPunchRole.perforation,
        rotationDeg: rotDiag1,
      ));

      // Port 2 (Right Ray): runs along (sin θ, cos θ), inward normal (-cos θ, sin θ)
      final x2 = p2Out.x + u * sinTheta - vInward * cosTheta;
      final y2 = p2Out.y + u * cosTheta + vInward * sinTheta;
      punches.add(sampleSlot.copyWith(
        id: nextSlotId(),
        center: CadPoint2D(x2, y2),
        role: CncPunchRole.perforation,
        rotationDeg: rotDiag2,
      ));
    }

    return punches;
  }
}
