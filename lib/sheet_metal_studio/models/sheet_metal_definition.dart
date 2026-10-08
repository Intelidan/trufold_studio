// =============================================================================
// sheet_metal_definition.dart
//
// Semantic Sheet-Metal Definition per Master Guide #26 (Step 12).
// Encapsulates:
// - Physical material grade & mechanical properties (GI, MS, HR, CRCA, SS304, SS316, AL)
// - Separate coating finishes (EG, HDG, 2HDG, 3HDG, PC, 2PC, 3PC, EX, 2EX, 3EX)
// - Engineering formulas: Neutral Axis, K-Factor, Bend Allowance (BA),
//   Outside Setback (OSB), Inside Setback (ISB), Bend Deduction (BD)
// - Corner & Bend Relief Rules
// =============================================================================

import 'dart:math' as math;
import 'paint_coat_specification.dart';
export 'paint_coat_specification.dart';

/// Standard sheet metal material grades with metallurgical properties
enum SheetMetalMaterialGrade {
  gi(
    code: 'GI',
    displayName: 'Galvanized Iron (GI)',
    densityKgM3: 7850.0,
    tensileStrengthMpa: 350.0,
    minBendFactor: 0.5,
    defaultKFactor: 0.38,
  ),
  ms(
    code: 'MS',
    displayName: 'Mild Steel (MS)',
    densityKgM3: 7850.0,
    tensileStrengthMpa: 400.0,
    minBendFactor: 0.5,
    defaultKFactor: 0.40,
  ),
  hr(
    code: 'HR',
    displayName: 'Hot Rolled Steel (HR)',
    densityKgM3: 7850.0,
    tensileStrengthMpa: 420.0,
    minBendFactor: 0.5,
    defaultKFactor: 0.42,
  ),
  crca(
    code: 'CRCA',
    displayName: 'Cold Rolled Close Annealed (CRCA)',
    densityKgM3: 7870.0,
    tensileStrengthMpa: 370.0,
    minBendFactor: 0.4,
    defaultKFactor: 0.38,
  ),
  ss304(
    code: 'SS304',
    displayName: 'Stainless Steel 304 (SS304)',
    densityKgM3: 8000.0,
    tensileStrengthMpa: 620.0,
    minBendFactor: 1.0,
    defaultKFactor: 0.44,
  ),
  ss316(
    code: 'SS316',
    displayName: 'Stainless Steel 316 (SS316)',
    densityKgM3: 8000.0,
    tensileStrengthMpa: 650.0,
    minBendFactor: 1.0,
    defaultKFactor: 0.44,
  ),
  aluminium(
    code: 'AL',
    displayName: 'Aluminium 5052 (AL)',
    densityKgM3: 2700.0,
    tensileStrengthMpa: 220.0,
    minBendFactor: 0.5,
    defaultKFactor: 0.33,
  );

  final String code;
  final String displayName;
  final double densityKgM3;
  final double tensileStrengthMpa;
  final double minBendFactor;
  final double defaultKFactor;

  const SheetMetalMaterialGrade({
    required this.code,
    required this.displayName,
    required this.densityKgM3,
    required this.tensileStrengthMpa,
    required this.minBendFactor,
    required this.defaultKFactor,
  });

  static SheetMetalMaterialGrade fromCode(String? code) {
    if (code == null) return SheetMetalMaterialGrade.ms;
    final c = code.trim().toUpperCase();
    for (final val in values) {
      if (val.code.toUpperCase() == c || val.name.toUpperCase() == c) {
        return val;
      }
    }
    if (c.contains('GALV')) return SheetMetalMaterialGrade.gi;
    if (c.contains('CRCA') || c.contains('COLD')) return SheetMetalMaterialGrade.crca;
    if (c.contains('HOT') || c.contains('HR')) return SheetMetalMaterialGrade.hr;
    if (c.contains('316')) return SheetMetalMaterialGrade.ss316;
    if (c.contains('304') || c.contains('STAIN')) return SheetMetalMaterialGrade.ss304;
    if (c.contains('ALUM')) return SheetMetalMaterialGrade.aluminium;
    return SheetMetalMaterialGrade.ms;
  }
}

/// Surface finishes / coatings represented independently from base material
enum CoatingFinish {
  none('NONE', 'Bare / Mill Finish'),
  eg('EG', 'Electro-Galvanized (EG)'),
  hdg('HDG', 'Hot-Dip Galvanized (HDG)'),
  twoHdg('2HDG', 'Double Hot-Dip Galvanized (2HDG)'),
  threeHdg('3HDG', 'Triple Hot-Dip Galvanized (3HDG)'),
  pc('PC', 'Powder Coated (PC)'),
  twoPc('2PC', 'Dual Powder Coated (2PC)'),
  threePc('3PC', 'Triple Powder Coated (3PC)'),
  ex('EX', 'Epoxy Coated (EX)'),
  twoEx('2EX', 'Dual Epoxy Coated (2EX)'),
  threeEx('3EX', 'Triple Epoxy Coated (3EX)');

  final String code;
  final String displayName;
  const CoatingFinish(this.code, this.displayName);

  static CoatingFinish fromCode(String? code) {
    if (code == null) return CoatingFinish.none;
    final c = code.trim().toUpperCase();
    for (final val in values) {
      if (val.code.toUpperCase() == c || val.name.toUpperCase() == c) {
        return val;
      }
    }
    return CoatingFinish.none;
  }
}

/// Relief notch geometry for press brake bend relief & corner relief
enum BendReliefType {
  none('None'),
  rectangular('Rectangular Notch'),
  roundTear('Tear / Round Notch'),
  slit('Laser Slit');

  final String displayName;
  const BendReliefType(this.displayName);

  static BendReliefType fromString(String? val) {
    if (val == null) return BendReliefType.rectangular;
    for (final v in values) {
      if (v.name.toLowerCase() == val.toLowerCase() ||
          v.displayName.toLowerCase() == val.toLowerCase()) {
        return v;
      }
    }
    return BendReliefType.rectangular;
  }
}

/// Standard relief rules per industrial sheet metal fabrication guidelines
class ReliefRules {
  final BendReliefType defaultReliefType;
  final double? customWidthMm;
  final double? customDepthMm;

  const ReliefRules({
    this.defaultReliefType = BendReliefType.rectangular,
    this.customWidthMm,
    this.customDepthMm,
  });

  /// Recommended minimum relief width: W = max(1.0mm, T)
  double minReliefWidth(double thicknessMm) {
    return customWidthMm ?? math.max(1.0, thicknessMm);
  }

  /// Recommended minimum relief depth: D = max(1.0mm, R + T)
  double minReliefDepth(double radiusMm, double thicknessMm) {
    return customDepthMm ?? math.max(1.0, radiusMm + thicknessMm);
  }

  ReliefRules copyWith({
    BendReliefType? defaultReliefType,
    double? customWidthMm,
    double? customDepthMm,
  }) {
    return ReliefRules(
      defaultReliefType: defaultReliefType ?? this.defaultReliefType,
      customWidthMm: customWidthMm ?? this.customWidthMm,
      customDepthMm: customDepthMm ?? this.customDepthMm,
    );
  }

  Map<String, dynamic> toJson() => {
        'defaultReliefType': defaultReliefType.name,
        if (customWidthMm != null) 'customWidthMm': customWidthMm,
        if (customDepthMm != null) 'customDepthMm': customDepthMm,
      };

  factory ReliefRules.fromJson(Map<String, dynamic> json) => ReliefRules(
        defaultReliefType: BendReliefType.fromString(json['defaultReliefType'] as String?),
        customWidthMm: (json['customWidthMm'] as num?)?.toDouble(),
        customDepthMm: (json['customDepthMm'] as num?)?.toDouble(),
      );
}

/// Comprehensive semantic sheet-metal definition per Master Guide #26
class SheetMetalDefinition {
  final SheetMetalMaterialGrade material;
  final CoatingFinish finish;
  final double thicknessMm;
  final double defaultBendRadiusMm;
  final double kFactor;
  final ReliefRules reliefRules;
  final double edgeChamferMm;
  final PaintCoatSpecification paintCoat;

  const SheetMetalDefinition({
    this.material = SheetMetalMaterialGrade.gi,
    this.finish = CoatingFinish.eg,
    this.thicknessMm = 1.5,
    this.defaultBendRadiusMm = 1.5,
    this.kFactor = 0.38,
    this.reliefRules = const ReliefRules(),
    this.edgeChamferMm = 0.0,
    this.paintCoat = const PaintCoatSpecification(),
  });

  /// Material grade enum
  SheetMetalMaterialGrade get grade => material;

  /// Effective inside bend radius in mm
  double get r => defaultBendRadiusMm > 0 ? defaultBendRadiusMm : thicknessMm;

  /// Density in kg/m³
  double get densityKgM3 => material.densityKgM3;

  /// Ultimate tensile strength in MPa (N/mm²)
  double get tensileStrengthMpa => material.tensileStrengthMpa;

  /// Recommended minimum inside bend radius in mm
  double get minBendRadius => material.minBendFactor * thicknessMm;

  /// Distance from inner surface to neutral axis in mm: NA = K * T
  double get neutralAxis => (kFactor.clamp(0.25, 0.50)) * thicknessMm;

  /// Validates if K-factor is within typical manufacturing limits [0.33, 0.44]
  bool get isKFactorStandard => kFactor >= 0.33 && kFactor <= 0.44;

  /// Bend Allowance (BA): Arc length of the neutral axis within the bend zone.
  /// BA = (π / 180) * |θ| * (R + K * T)
  double bendAllowance(double angleDeg, [double? radiusMm]) {
    final effectiveR = (radiusMm != null && radiusMm > 0) ? radiusMm : r;
    return (math.pi / 180.0) * angleDeg.abs() * (effectiveR + kFactor * thicknessMm);
  }

  /// Outside Setback (OSB): Distance from bend apex to tangent point along the outer face.
  /// OSB = tan(|θ| / 2) * (R + T)
  double outsideSetback(double angleDeg, [double? radiusMm]) {
    final effectiveR = (radiusMm != null && radiusMm > 0) ? radiusMm : r;
    final angleRad = (angleDeg.abs() * math.pi / 180.0);
    return math.tan(angleRad / 2.0) * (effectiveR + thicknessMm);
  }

  /// Inside Setback (ISB): Distance from apex to inner tangent point.
  /// ISB = tan(|θ| / 2) * R
  double insideSetback(double angleDeg, [double? radiusMm]) {
    final effectiveR = (radiusMm != null && radiusMm > 0) ? radiusMm : r;
    final angleRad = (angleDeg.abs() * math.pi / 180.0);
    return math.tan(angleRad / 2.0) * effectiveR;
  }

  /// Bend Deduction (BD): Length deducted from the sum of the nominal flange legs.
  /// BD = 2 * OSB - BA
  double bendDeduction(double angleDeg, [double? radiusMm]) {
    return 2.0 * outsideSetback(angleDeg, radiusMm) - bendAllowance(angleDeg, radiusMm);
  }

  /// Calculates weight in kg for a given net surface area in mm²
  double calculateWeightKg({required double areaMm2, double holesAreaMm2 = 0.0}) {
    final netAreaMm2 = math.max(0.0, areaMm2 - holesAreaMm2);
    final volumeMm3 = netAreaMm2 * thicknessMm;
    final volumeM3 = volumeMm3 * 1e-9;
    return volumeM3 * densityKgM3;
  }

  SheetMetalDefinition copyWith({
    SheetMetalMaterialGrade? material,
    CoatingFinish? finish,
    double? thicknessMm,
    double? defaultBendRadiusMm,
    double? kFactor,
    ReliefRules? reliefRules,
    double? edgeChamferMm,
    PaintCoatSpecification? paintCoat,
  }) {
    return SheetMetalDefinition(
      material: material ?? this.material,
      finish: finish ?? this.finish,
      thicknessMm: thicknessMm ?? this.thicknessMm,
      defaultBendRadiusMm: defaultBendRadiusMm ?? this.defaultBendRadiusMm,
      kFactor: kFactor ?? this.kFactor,
      reliefRules: reliefRules ?? this.reliefRules,
      edgeChamferMm: edgeChamferMm ?? this.edgeChamferMm,
      paintCoat: paintCoat ?? this.paintCoat,
    );
  }

  Map<String, dynamic> toJson() => {
        'material': material.code,
        'finish': finish.code,
        'thicknessMm': thicknessMm,
        'defaultBendRadiusMm': defaultBendRadiusMm,
        'kFactor': kFactor,
        'reliefRules': reliefRules.toJson(),
        'edgeChamferMm': edgeChamferMm,
        'paintCoat': paintCoat.toJson(),
      };

  factory SheetMetalDefinition.fromJson(Map<String, dynamic> json) {
    final matCode = json['material'] as String?;
    final finishCode = json['finish'] as String?;

    return SheetMetalDefinition(
      material: SheetMetalMaterialGrade.fromCode(matCode),
      finish: CoatingFinish.fromCode(finishCode),
      thicknessMm: (json['thicknessMm'] as num?)?.toDouble() ?? 1.5,
      defaultBendRadiusMm: (json['defaultBendRadiusMm'] as num?)?.toDouble() ?? 1.5,
      kFactor: (json['kFactor'] as num?)?.toDouble() ?? 0.38,
      reliefRules: json['reliefRules'] != null
          ? ReliefRules.fromJson(json['reliefRules'] as Map<String, dynamic>)
          : const ReliefRules(),
      edgeChamferMm: (json['edgeChamferMm'] as num?)?.toDouble() ?? 0.0,
      paintCoat: json['paintCoat'] != null
          ? PaintCoatSpecification.fromJson(json['paintCoat'] as Map<String, dynamic>)
          : const PaintCoatSpecification(),
    );
  }
}
