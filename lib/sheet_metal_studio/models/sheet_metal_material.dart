// =============================================================================
// sheet_metal_material.dart
//
// Physical properties & bend calculation formulas for sheet metal fabrication.
// Calculates Bend Allowance (BA), Bend Deduction (BD), and Setback (SB).
// =============================================================================

import 'dart:math' as math;

import 'sheet_metal_definition.dart';
export 'sheet_metal_definition.dart';

enum SheetMaterialType {
  mildSteel('MS', 'Mild Steel (MS)'),
  stainlessSteel('SS', 'Stainless Steel (SS)'),
  aluminium('AL', 'Aluminium (AL)');

  final String shortCode;
  final String displayName;
  const SheetMaterialType(this.shortCode, this.displayName);
}

enum SurfaceFinish {
  bare('Self / Mill Finish', 'Bare'),
  electroGalvanized('Electro-Galvanized', 'EG'),
  hotDipGalvanized('Hot-Dip Galvanized', 'HDG'),
  powderCoated('Powder Coated', 'PC'),
  epoxyCoated('Epoxy Coated', 'EX');

  final String displayName;
  final String code;
  const SurfaceFinish(this.displayName, this.code);
}

class SheetMetalMaterial {
  final double thicknessMm;
  final String materialGrade;
  final SheetMaterialType materialType;
  final SurfaceFinish finish;
  final double kFactor;
  final double defaultBendRadius;
  final double edgeChamferMm;
  final PaintCoatSpecification paintCoat;

  const SheetMetalMaterial({
    this.thicknessMm = 1.5,
    this.materialGrade = 'Pre-Galvanized Steel',
    this.materialType = SheetMaterialType.mildSteel,
    this.finish = SurfaceFinish.electroGalvanized,
    this.kFactor = 0.40,
    this.defaultBendRadius = 1.5,
    this.edgeChamferMm = 0.0,
    this.paintCoat = const PaintCoatSpecification(),
  });

  /// Material grade display name
  String get name => materialGrade;

  /// Inside bend radius in mm
  double get r => defaultBendRadius > 0 ? defaultBendRadius : thicknessMm;

  /// Density in kg/m³
  double get densityKgM3 {
    switch (materialType) {
      case SheetMaterialType.mildSteel:
        return 7850.0;
      case SheetMaterialType.stainlessSteel:
        return 8000.0;
      case SheetMaterialType.aluminium:
        return 2700.0;
    }
  }

  /// Ultimate tensile strength in MPa (N/mm²) for tonnage calculations
  double get tensileStrengthMpa {
    switch (materialType) {
      case SheetMaterialType.mildSteel:
        return 420.0; // Typical CR4 / IS 2062
      case SheetMaterialType.stainlessSteel:
        return 650.0; // SS 304
      case SheetMaterialType.aluminium:
        return 200.0; // AL 5052-H32
    }
  }

  /// Minimum inside bend radius factor (r_min = factor * T)
  double get minBendRadiusFactor {
    switch (materialType) {
      case SheetMaterialType.mildSteel:
        return 0.5;
      case SheetMaterialType.stainlessSteel:
        return 1.0;
      case SheetMaterialType.aluminium:
        return 0.5;
    }
  }

  /// Minimum recommended inside bend radius in mm
  double get minBendRadius => minBendRadiusFactor * thicknessMm;

  /// Calculates weight in kg for a given net surface area in mm²
  double calculateWeightKg({required double areaMm2, double holesAreaMm2 = 0.0}) {
    final netAreaMm2 = math.max(0.0, areaMm2 - holesAreaMm2);
    final volumeMm3 = netAreaMm2 * thicknessMm;
    final volumeM3 = volumeMm3 * 1e-9;
    return volumeM3 * densityKgM3;
  }

  /// Bend Allowance (BA): Length of the neutral axis within the bend arc.
  /// BA = (π / 180) * angleDeg * (r + kFactor * thicknessMm)
  double bendAllowance(double angleDeg) {
    return (math.pi / 180.0) * angleDeg.abs() * (r + kFactor * thicknessMm);
  }

  /// Outside Setback (OSB): Distance from apex to tangent point.
  /// OSB = tan(angleRad / 2) * (r + thicknessMm)
  double outsideSetback(double angleDeg) {
    final angleRad = (angleDeg.abs() * math.pi / 180.0);
    return math.tan(angleRad / 2.0) * (r + thicknessMm);
  }

  /// Inside Setback (ISB): Distance from apex to inner tangent point.
  /// ISB = tan(angleRad / 2) * r
  double insideSetback(double angleDeg) {
    final angleRad = (angleDeg.abs() * math.pi / 180.0);
    return math.tan(angleRad / 2.0) * r;
  }

  /// Converts this material to a full semantic SheetMetalDefinition
  SheetMetalDefinition toDefinition() {
    return SheetMetalDefinition(
      material: SheetMetalMaterialGrade.fromCode(materialGrade),
      finish: CoatingFinish.fromCode(finish.code),
      thicknessMm: thicknessMm,
      defaultBendRadiusMm: defaultBendRadius,
      kFactor: kFactor,
      edgeChamferMm: edgeChamferMm,
      paintCoat: paintCoat,
    );
  }

  /// Creates a SheetMetalMaterial from a semantic SheetMetalDefinition
  factory SheetMetalMaterial.fromDefinition(SheetMetalDefinition def) {
    SheetMaterialType mType = SheetMaterialType.mildSteel;
    if (def.material == SheetMetalMaterialGrade.ss304 || def.material == SheetMetalMaterialGrade.ss316) {
      mType = SheetMaterialType.stainlessSteel;
    } else if (def.material == SheetMetalMaterialGrade.aluminium) {
      mType = SheetMaterialType.aluminium;
    }

    SurfaceFinish sFinish = SurfaceFinish.electroGalvanized;
    for (final f in SurfaceFinish.values) {
      if (f.code.toUpperCase() == def.finish.code.toUpperCase()) {
        sFinish = f;
        break;
      }
    }

    return SheetMetalMaterial(
      thicknessMm: def.thicknessMm,
      materialGrade: def.material.displayName,
      materialType: mType,
      finish: sFinish,
      kFactor: def.kFactor,
      defaultBendRadius: def.defaultBendRadiusMm,
      edgeChamferMm: def.edgeChamferMm,
      paintCoat: def.paintCoat,
    );
  }

  SheetMetalMaterial copyWith({
    double? thicknessMm,
    String? materialGrade,
    SheetMaterialType? materialType,
    SurfaceFinish? finish,
    double? kFactor,
    double? defaultBendRadius,
    double? edgeChamferMm,
    PaintCoatSpecification? paintCoat,
  }) {
    return SheetMetalMaterial(
      thicknessMm: thicknessMm ?? this.thicknessMm,
      materialGrade: materialGrade ?? this.materialGrade,
      materialType: materialType ?? this.materialType,
      finish: finish ?? this.finish,
      kFactor: kFactor ?? this.kFactor,
      defaultBendRadius: defaultBendRadius ?? this.defaultBendRadius,
      edgeChamferMm: edgeChamferMm ?? this.edgeChamferMm,
      paintCoat: paintCoat ?? this.paintCoat,
    );
  }

  Map<String, dynamic> toJson() => {
    'thicknessMm': thicknessMm,
    'materialGrade': materialGrade,
    'materialType': materialType.name,
    'finish': finish.name,
    'kFactor': kFactor,
    'defaultBendRadius': defaultBendRadius,
    'edgeChamferMm': edgeChamferMm,
    'paintCoat': paintCoat.toJson(),
  };

  factory SheetMetalMaterial.fromJson(Map<String, dynamic> json) {
    SheetMaterialType type = SheetMaterialType.mildSteel;
    if (json['materialType'] != null) {
      final typeStr = json['materialType'] as String;
      type = SheetMaterialType.values.firstWhere((v) => v.name == typeStr, orElse: () => SheetMaterialType.mildSteel);
    } else if (json['materialGrade'] != null) {
      final g = (json['materialGrade'] as String).toLowerCase();
      if (g.contains('stainless')) {
        type = SheetMaterialType.stainlessSteel;
      } else if (g.contains('alumin')) {
        type = SheetMaterialType.aluminium;
      }
    }

    SurfaceFinish finish = SurfaceFinish.electroGalvanized;
    if (json['finish'] != null) {
      final finishStr = json['finish'] as String;
      finish = SurfaceFinish.values.firstWhere((f) => f.name == finishStr, orElse: () => SurfaceFinish.electroGalvanized);
    }

    return SheetMetalMaterial(
      thicknessMm: (json['thicknessMm'] as num?)?.toDouble() ?? 1.5,
      materialGrade: json['materialGrade'] as String? ?? 'Pre-Galvanized Steel',
      materialType: type,
      finish: finish,
      kFactor: (json['kFactor'] as num?)?.toDouble() ?? 0.40,
      defaultBendRadius: (json['defaultBendRadius'] as num?)?.toDouble() ?? 1.5,
      edgeChamferMm: (json['edgeChamferMm'] as num?)?.toDouble() ?? 0.0,
      paintCoat: json['paintCoat'] != null ? PaintCoatSpecification.fromJson(json['paintCoat'] as Map<String, dynamic>) : const PaintCoatSpecification(),
    );
  }
}
