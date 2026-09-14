// =============================================================================
// flat_pattern_engine.dart
//
// Pure Dart Manufacturing Flat Pattern Developed Blank Engine.
// Implements Master Guide Step 18 (#27 / #32).
//
// Distinguishes strictly between:
// 1. Design Model: Nominal 3D component geometry
// 2. Flat Pattern Blank: Developed flat manufacturing blank taking into account
//    Bend Allowance (BA), Bend Deduction (BD), Neutral Axis, and Relief Cutouts.
// 3. Folded 3D Model: Kinematic mesh calculated by KinematicFoldEngine.
// =============================================================================

import 'dart:math' as math;

import '../models/cad_primitives.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/dsf_document.dart';
import '../models/fold_bend_line.dart';
import '../models/sheet_metal_definition.dart';

/// Manufacturing annotation for a bend line in the flat pattern
class FlatPatternBendAnnotation {
  final String bendId;
  final CadLineSegment centerLine;
  final CadLineSegment tangentLine1; // Inner tangent at -BA/2
  final CadLineSegment tangentLine2; // Outer tangent at +BA/2
  final double angleDeg;
  final BendDirection direction;
  final double radiusMm;
  final double allowanceMm;
  final double deductionMm;
  final double outsideSetbackMm;
  final String note;

  const FlatPatternBendAnnotation({
    required this.bendId,
    required this.centerLine,
    required this.tangentLine1,
    required this.tangentLine2,
    required this.angleDeg,
    required this.direction,
    required this.radiusMm,
    required this.allowanceMm,
    required this.deductionMm,
    required this.outsideSetbackMm,
    required this.note,
  });
}

/// A relief notch generated at bend terminations
class FlatPatternReliefNotch {
  final String bendId;
  final BendReliefType type;
  final CadPoint2D anchorPoint;
  final List<CadPoint2D> notchPolygon;
  final double widthMm;
  final double depthMm;

  const FlatPatternReliefNotch({
    required this.bendId,
    required this.type,
    required this.anchorPoint,
    required this.notchPolygon,
    required this.widthMm,
    required this.depthMm,
  });
}

/// Developed manufacturing blank calculation result
class FlatPatternResult {
  final List<CadPoint2D> developedBlankContour;
  final double developedWidthMm;
  final double developedLengthMm;
  final double nominalWidthMm;
  final double nominalLengthMm;
  final double totalBendDeductionMm;
  final List<FlatPatternBendAnnotation> bendAnnotations;
  final List<FlatPatternReliefNotch> reliefNotches;
  final List<CncPunchPrimitive> punches;
  final double thicknessMm;
  final double kFactor;
  final double neutralAxisMm;
  final String materialName;

  const FlatPatternResult({
    required this.developedBlankContour,
    required this.developedWidthMm,
    required this.developedLengthMm,
    required this.nominalWidthMm,
    required this.nominalLengthMm,
    required this.totalBendDeductionMm,
    required this.bendAnnotations,
    required this.reliefNotches,
    required this.punches,
    required this.thicknessMm,
    required this.kFactor,
    required this.neutralAxisMm,
    required this.materialName,
  });

  /// Stretch delta summary between nominal design model and developed flat blank
  String get deltaSummary =>
      'Nominal: ${nominalWidthMm.toStringAsFixed(1)}×${nominalLengthMm.toStringAsFixed(1)} mm | '
      'Developed: ${developedWidthMm.toStringAsFixed(1)}×${developedLengthMm.toStringAsFixed(1)} mm | '
      'Total BD: ${totalBendDeductionMm.toStringAsFixed(2)} mm (K=$kFactor)';
}

class FlatPatternEngine {
  /// Computes the complete manufacturing flat pattern developed blank
  static FlatPatternResult computeFlatPattern(DsfDocument doc) {
    final thickness = doc.material.thicknessMm;
    final kFactor = doc.material.kFactor;
    final neutralAxis = kFactor * thickness;
    final activeBends = doc.bends.where((b) => b.isVisible).toList();

    // 1. Calculate nominal dimensions from outer contour or faces
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;

    final contour = doc.outerContour.isNotEmpty
        ? doc.outerContour
        : (doc.faces.isNotEmpty
            ? doc.faces.expand((f) => f.vertices).toList()
            : [
                const CadPoint2D(0, 0),
                const CadPoint2D(100, 0),
                const CadPoint2D(100, 100),
                const CadPoint2D(0, 100),
              ]);

    for (final pt in contour) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }

    final nominalWidth = maxX > minX ? maxX - minX : 100.0;
    final nominalLength = maxY > minY ? maxY - minY : 100.0;

    // 2. Generate bend annotations & bend zone tangents
    final bendAnnotations = <FlatPatternBendAnnotation>[];
    final reliefNotches = <FlatPatternReliefNotch>[];
    double totalDeduction = 0.0;

    double horizDeduction = 0.0;
    double vertDeduction = 0.0;

    for (final bend in activeBends) {
      final ba = bend.calculateBendAllowance(
        sheetThicknessMm: thickness,
        kFactor: kFactor,
      );
      final osb = bend.calculateOutsideSetback(sheetThicknessMm: thickness);
      final bd = bend.calculateBendDeduction(
        sheetThicknessMm: thickness,
        kFactor: kFactor,
      );
      totalDeduction += bd;

      // Classify bend axis orientation (vertical vs horizontal bend line)
      final dx = (bend.p2.x - bend.p1.x).abs();
      final dy = (bend.p2.y - bend.p1.y).abs();
      if (dy > dx) {
        // Bend line runs vertically: deductions affect horizontal blank width
        horizDeduction += bd;
      } else {
        // Bend line runs horizontally: deductions affect vertical blank length
        vertDeduction += bd;
      }

      // Calculate tangent lines at ±BA / 2
      final halfBa = ba / 2.0;
      final normal = bend.unitNormal;

      final t1p1 = CadPoint2D(bend.p1.x - normal.x * halfBa, bend.p1.y - normal.y * halfBa);
      final t1p2 = CadPoint2D(bend.p2.x - normal.x * halfBa, bend.p2.y - normal.y * halfBa);
      final t2p1 = CadPoint2D(bend.p1.x + normal.x * halfBa, bend.p1.y + normal.y * halfBa);
      final t2p2 = CadPoint2D(bend.p2.x + normal.x * halfBa, bend.p2.y + normal.y * halfBa);

      final dirStr = bend.direction == BendDirection.up ? 'UP' : 'DOWN';
      final note =
          '${bend.id}: $dirStr ${bend.targetAngleDeg.toStringAsFixed(0)}° '
          'R${bend.radiusMm.toStringAsFixed(1)} (BA=${ba.toStringAsFixed(2)} BD=${bd.toStringAsFixed(2)})';

      bendAnnotations.add(
        FlatPatternBendAnnotation(
          bendId: bend.id,
          centerLine: CadLineSegment(id: '${bend.id}_CTR', p1: bend.p1, p2: bend.p2),
          tangentLine1: CadLineSegment(id: '${bend.id}_T1', p1: t1p1, p2: t1p2),
          tangentLine2: CadLineSegment(id: '${bend.id}_T2', p1: t2p1, p2: t2p2),
          angleDeg: bend.targetAngleDeg,
          direction: bend.direction,
          radiusMm: bend.radiusMm,
          allowanceMm: ba,
          deductionMm: bd,
          outsideSetbackMm: osb,
          note: note,
        ),
      );

      // 3. Generate Relief Notches if specified
      if (bend.reliefType != BendReliefType.none) {
        final rules = doc.material.toDefinition().reliefRules;
        final w = bend.reliefWidthMm ?? rules.minReliefWidth(thickness);
        final d = bend.reliefDepthMm ?? rules.minReliefDepth(bend.radiusMm, thickness);

        // Generate notch at p1 and p2
        final notch1 = _createReliefNotch(
          bendId: bend.id,
          type: bend.reliefType,
          anchor: bend.p1,
          tangentDir: bend.unitDirection * (-1.0),
          normalDir: normal,
          widthMm: w,
          depthMm: d,
        );
        final notch2 = _createReliefNotch(
          bendId: bend.id,
          type: bend.reliefType,
          anchor: bend.p2,
          tangentDir: bend.unitDirection,
          normalDir: normal,
          widthMm: w,
          depthMm: d,
        );

        reliefNotches.add(notch1);
        reliefNotches.add(notch2);
      }
    }

    // 4. Calculate Developed Blank Envelope
    // Developed blank is reduced along bend deduction axes
    final developedWidth = math.max(1.0, nominalWidth - horizDeduction);
    final developedLength = math.max(1.0, nominalLength - vertDeduction);

    // Compute developed outer contour points
    final scaleX = nominalWidth > 1e-4 ? developedWidth / nominalWidth : 1.0;
    final scaleY = nominalLength > 1e-4 ? developedLength / nominalLength : 1.0;

    final developedContour = <CadPoint2D>[];
    for (final pt in contour) {
      final nx = minX + (pt.x - minX) * scaleX;
      final ny = minY + (pt.y - minY) * scaleY;
      developedContour.add(CadPoint2D(nx, ny));
    }

    return FlatPatternResult(
      developedBlankContour: developedContour,
      developedWidthMm: developedWidth,
      developedLengthMm: developedLength,
      nominalWidthMm: nominalWidth,
      nominalLengthMm: nominalLength,
      totalBendDeductionMm: totalDeduction,
      bendAnnotations: bendAnnotations,
      reliefNotches: reliefNotches,
      punches: doc.allPunches,
      thicknessMm: thickness,
      kFactor: kFactor,
      neutralAxisMm: neutralAxis,
      materialName: doc.material.materialGrade,
    );
  }

  static FlatPatternReliefNotch _createReliefNotch({
    required String bendId,
    required BendReliefType type,
    required CadPoint2D anchor,
    required CadPoint2D tangentDir,
    required CadPoint2D normalDir,
    required double widthMm,
    required double depthMm,
  }) {
    final halfW = widthMm / 2.0;
    final poly = <CadPoint2D>[];

    switch (type) {
      case BendReliefType.rectangular:
        // Rectangular cutout notch centered across the bend axis
        poly.add(CadPoint2D(
          anchor.x - normalDir.x * halfW,
          anchor.y - normalDir.y * halfW,
        ));
        poly.add(CadPoint2D(
          anchor.x - normalDir.x * halfW + tangentDir.x * depthMm,
          anchor.y - normalDir.y * halfW + tangentDir.y * depthMm,
        ));
        poly.add(CadPoint2D(
          anchor.x + normalDir.x * halfW + tangentDir.x * depthMm,
          anchor.y + normalDir.y * halfW + tangentDir.y * depthMm,
        ));
        poly.add(CadPoint2D(
          anchor.x + normalDir.x * halfW,
          anchor.y + normalDir.y * halfW,
        ));
        break;

      case BendReliefType.roundTear:
        // Semicircular tear cutout
        const segments = 8;
        final center = CadPoint2D(
          anchor.x + tangentDir.x * (depthMm - halfW),
          anchor.y + tangentDir.y * (depthMm - halfW),
        );
        poly.add(CadPoint2D(
          anchor.x - normalDir.x * halfW,
          anchor.y - normalDir.y * halfW,
        ));
        for (int i = 0; i <= segments; i++) {
          final th = math.pi * i / segments;
          poly.add(CadPoint2D(
            center.x - normalDir.x * halfW * math.cos(th) + tangentDir.x * halfW * math.sin(th),
            center.y - normalDir.y * halfW * math.cos(th) + tangentDir.y * halfW * math.sin(th),
          ));
        }
        poly.add(CadPoint2D(
          anchor.x + normalDir.x * halfW,
          anchor.y + normalDir.y * halfW,
        ));
        break;

      case BendReliefType.slit:
        // Thin laser slit line along the bend axis
        poly.add(anchor);
        poly.add(CadPoint2D(
          anchor.x + tangentDir.x * depthMm,
          anchor.y + tangentDir.y * depthMm,
        ));
        break;

      case BendReliefType.none:
        poly.add(anchor);
        break;
    }

    return FlatPatternReliefNotch(
      bendId: bendId,
      type: type,
      anchorPoint: anchor,
      notchPolygon: poly,
      widthMm: widthMm,
      depthMm: depthMm,
    );
  }
}
