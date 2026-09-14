// =============================================================================
// press_brake_cam_engine.dart
//
// Press Brake CAM Rules & Interference Check Engine for Sheet Metal Studio.
// Evaluates press-brake tonnage, minimum inside bend radius, V-die opening bridge
// safety, bed length limits, and backgauge throat clearance.
// =============================================================================

import 'dart:math' as math;

import '../models/cad_primitives.dart';
import '../models/fold_bend_line.dart';
import '../models/planar_sheet_face.dart';
import '../models/press_brake_machine.dart';
import '../models/sheet_metal_material.dart';
import '../models/dsf_document.dart';

enum ViolationSeverity { warning, error }

class BendViolation {
  final String bendId;
  final String title;
  final String message;
  final ViolationSeverity severity;
  final double? actualValue;
  final double? limitValue;
  final String? unit;

  const BendViolation({
    required this.bendId,
    required this.title,
    required this.message,
    required this.severity,
    this.actualValue,
    this.limitValue,
    this.unit,
  });
}

class BendValidationResult {
  final String bendId;
  final double requiredTonnageKN;
  final double minFlangeMm;
  final double bendLengthMm;
  final List<BendViolation> violations;

  const BendValidationResult({
    required this.bendId,
    required this.requiredTonnageKN,
    required this.minFlangeMm,
    required this.bendLengthMm,
    required this.violations,
  });

  bool get hasErrors =>
      violations.any((v) => v.severity == ViolationSeverity.error);
  bool get hasWarnings =>
      violations.any((v) => v.severity == ViolationSeverity.warning);
  bool get isClean => violations.isEmpty;
}

class PressBrakeCamEngine {
  /// Air-bending tonnage required in kN:
  /// F = (1.42 * Rm * L * T²) / (V * 1000)
  /// where:
  /// - Rm is material tensile strength (N/mm² or MPa)
  /// - L is bend length (mm)
  /// - T is sheet thickness (mm)
  /// - V is V-die width opening (mm)
  static double calculateRequiredTonnageKN({
    required double bendLengthMm,
    required SheetMetalMaterial material,
    required double vDieWidthMm,
  }) {
    final rm = material.tensileStrengthMpa;
    final t = material.thicknessMm;
    final v = vDieWidthMm > 0 ? vDieWidthMm : 8.0 * t;
    if (v <= 0) return 0.0;

    return (1.42 * rm * bendLengthMm * t * t) / (v * 1000.0);
  }

  /// Minimum safe flange length (b_min ≈ 0.7 * V) so sheet doesn't fall into the V-die
  static double calculateMinFlangeMm(double vDieWidthMm) {
    return 0.70 * vDieWidthMm;
  }

  /// Validates an individual bend line against material and machine constraints
  static BendValidationResult validateBend({
    required FoldBendLine bend,
    required DsfDocument doc,
    required PressBrakeMachine machine,
  }) {
    final violations = <BendViolation>[];
    final t = doc.material.thicknessMm;
    final vDie = machine.vDieWidthMm > 0 ? machine.vDieWidthMm : 8.0 * t;
    final l = bend.length;

    // 1. Tonnage Check
    final reqTonnage = calculateRequiredTonnageKN(
      bendLengthMm: l,
      material: doc.material,
      vDieWidthMm: vDie,
    );

    if (reqTonnage > machine.maxTonnageKN) {
      violations.add(
        BendViolation(
          bendId: bend.id,
          title: 'Tonnage Capacity Exceeded',
          message:
              'Required force ${reqTonnage.toStringAsFixed(1)} kN exceeds machine limit (${machine.maxTonnageKN.toStringAsFixed(0)} kN / ${machine.maxTonnageTons.toStringAsFixed(0)}T)',
          severity: ViolationSeverity.error,
          actualValue: reqTonnage,
          limitValue: machine.maxTonnageKN,
          unit: 'kN',
        ),
      );
    }

    // 2. Minimum Inside Bend Radius Check
    final minRadius = doc.material.minBendRadius;
    if (bend.radiusMm < minRadius - 1e-3) {
      violations.add(
        BendViolation(
          bendId: bend.id,
          title: 'Bend Radius Too Tight',
          message:
              'Bend radius ${bend.radiusMm.toStringAsFixed(1)}mm is below minimum recommended ${minRadius.toStringAsFixed(1)}mm for ${doc.material.name} (Risk of outer surface cracking)',
          severity: ViolationSeverity.warning,
          actualValue: bend.radiusMm,
          limitValue: minRadius,
          unit: 'mm',
        ),
      );
    }

    // 3. Machine Bed Length Check
    if (l > machine.maxBendLengthMm) {
      violations.add(
        BendViolation(
          bendId: bend.id,
          title: 'Bed Length Exceeded',
          message:
              'Bend length ${l.toStringAsFixed(1)}mm exceeds machine bed length (${machine.maxBendLengthMm.toStringAsFixed(0)}mm)',
          severity: ViolationSeverity.error,
          actualValue: l,
          limitValue: machine.maxBendLengthMm,
          unit: 'mm',
        ),
      );
    } else if (l < machine.minBendLengthMm) {
      violations.add(
        BendViolation(
          bendId: bend.id,
          title: 'Tool Width Minimum',
          message:
              'Bend length ${l.toStringAsFixed(1)}mm is shorter than smallest tool segment (${machine.minBendLengthMm.toStringAsFixed(0)}mm)',
          severity: ViolationSeverity.warning,
          actualValue: l,
          limitValue: machine.minBendLengthMm,
          unit: 'mm',
        ),
      );
    }

    // 4. Safe Minimum Flange Length for V-Die
    final minFlange = calculateMinFlangeMm(vDie);
    PlanarSheetFace? childFace;
    for (final f in doc.faces) {
      if (f.id == bend.childFaceId) {
        childFace = f;
        break;
      }
    }

    double maxDistFromBend = 0.0;
    if (childFace != null && childFace.vertices.isNotEmpty) {
      for (final v in childFace.vertices) {
        final d = _distToInfiniteLine(v, bend.p1, bend.p2);
        if (d > maxDistFromBend) maxDistFromBend = d;
      }
    } else if (doc.outerContour.isNotEmpty) {
      // Fallback: estimate from outer contour points on the shorter side of the bend line
      double sideA = 0.0;
      double sideB = 0.0;
      final nx = -(bend.p2.y - bend.p1.y);
      final ny = bend.p2.x - bend.p1.x;
      for (final v in doc.outerContour) {
        final dot = (v.x - bend.p1.x) * nx + (v.y - bend.p1.y) * ny;
        final d = _distToInfiniteLine(v, bend.p1, bend.p2);
        if (dot > 0 && d > sideA) sideA = d;
        if (dot < 0 && d > sideB) sideB = d;
      }
      maxDistFromBend = (sideA > 0.1 && sideB > 0.1)
          ? math.min(sideA, sideB)
          : math.max(sideA, sideB);
    }

    if (maxDistFromBend > 0.1 && maxDistFromBend < minFlange) {
      violations.add(
        BendViolation(
          bendId: bend.id,
          title: 'Flange Too Short for V-Die',
          message:
              'Flange width (${maxDistFromBend.toStringAsFixed(1)}mm) is shorter than minimum safe V-die bridge (${minFlange.toStringAsFixed(1)}mm). Sheet may slip into the die gap.',
          severity: ViolationSeverity.warning,
          actualValue: maxDistFromBend,
          limitValue: minFlange,
          unit: 'mm',
        ),
      );
    }

    // 5. Throat Clearance / Backgauge Reach Check
    if (maxDistFromBend > machine.throatDepthMm) {
      violations.add(
        BendViolation(
          bendId: bend.id,
          title: 'Throat Depth Collision Risk',
          message:
              'Flange depth (${maxDistFromBend.toStringAsFixed(1)}mm) exceeds machine throat gap (${machine.throatDepthMm.toStringAsFixed(0)}mm). May collide with backgauge stop.',
          severity: ViolationSeverity.warning,
          actualValue: maxDistFromBend,
          limitValue: machine.throatDepthMm,
          unit: 'mm',
        ),
      );
    }

    return BendValidationResult(
      bendId: bend.id,
      requiredTonnageKN: reqTonnage,
      minFlangeMm: minFlange,
      bendLengthMm: l,
      violations: violations,
    );
  }

  /// Validates all bends in a document against the selected machine
  static Map<String, BendValidationResult> validateAllBends({
    required DsfDocument doc,
    required PressBrakeMachine machine,
  }) {
    final map = <String, BendValidationResult>{};
    for (final bend in doc.bends) {
      map[bend.id] = validateBend(bend: bend, doc: doc, machine: machine);
    }
    return map;
  }

  static double _distToInfiniteLine(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 < 1e-9) return p.distanceTo(a);
    final cross = ((p.x - a.x) * dy - (p.y - a.y) * dx).abs();
    return cross / math.sqrt(l2);
  }
}
