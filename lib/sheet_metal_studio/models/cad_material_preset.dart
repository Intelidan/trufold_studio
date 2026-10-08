import 'dart:ui' show Color;
import 'package:vector_math/vector_math.dart' as vm;

/// Supported material & finish presets for TruFold Studio CAD viewport.
enum CadMaterialPresetType {
  hdg('hdg', 'Hot-Dip Galvanized Iron (HDG)'),
  pgi('pgi', 'Pre-Galvanized Iron (PGI)'),
  plastic('plastic', 'Plastic (Standard Glossy)'),
  chrome('chrome', 'Chrome'),
  silver('silver', 'Silver / Stainless'),
  gold('gold', 'Gold'),
  copper('copper', 'Copper'),
  aluminum('aluminum', 'Aluminum'),
  ironSteel('ironSteel', 'Iron / Steel'),
  paint('paint', 'Painted / Powder Coated (Dielectric)'),
  custom('custom', 'Custom Shader');

  final String id;
  final String label;
  const CadMaterialPresetType(this.id, this.label);
}

/// PBR material and procedural shader configuration settings.
/// Maps directly to the uniforms in assets/materials/master_materials.fmat:
/// - baseColorFactor (vec4)
/// - roughnessFactor (float)
/// - isPlastic (float: 1.0 dielectric, 0.0 conductor)
/// - materialMode (float: 1.0 procedural Voronoi spangle, 0.0 standard)
/// - spangleScale (float: crystal tile density, 20.0 to 60.0)
class CadMaterialSettings {
  final CadMaterialPresetType preset;
  final Color baseColor;
  final double roughness;
  final bool isPlastic;
  final bool useSpangles;
  final double spangleScale;

  const CadMaterialSettings({
    this.preset = CadMaterialPresetType.pgi,
    this.baseColor = const Color(0xFFA6AABC), // Linear RGB ~ [0.65, 0.67, 0.68]
    this.roughness = 0.28,
    this.isPlastic = false,
    this.useSpangles = false,
    this.spangleScale = 45.0,
  });

  /// Factory constructors matching precise PBR / Voronoi specifications
  factory CadMaterialSettings.preset(CadMaterialPresetType type, {Color? customColor, double? customRoughness}) {
    switch (type) {
      case CadMaterialPresetType.hdg:
        // Darker gray, weathered crystalline silver, high roughness, procedural Voronoi spangles
        return CadMaterialSettings(
          preset: type,
          baseColor: const Color(0xFF8C8F91), // Linear [0.55, 0.56, 0.57]
          roughness: 0.55,
          isPlastic: false,
          useSpangles: true,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.pgi:
        // Rolled flat and smooth, microscopic uniform zinc spangles, clean metallic gray
        return CadMaterialSettings(
          preset: type,
          baseColor: const Color(0xFFA6AABC), // Linear [0.65, 0.67, 0.68]
          roughness: 0.28,
          isPlastic: false,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.plastic:
        // Dielectric polymer (metallic 0.0), uniform smooth glossy finish
        return CadMaterialSettings(
          preset: type,
          baseColor: customColor ?? const Color(0xFF1E88E5), // Vivid blue [0.1, 0.1, 0.8] or custom
          roughness: 0.20,
          isPlastic: true,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.chrome:
        // Near-perfect specular mirror surface
        return CadMaterialSettings(
          preset: type,
          baseColor: const Color(0xFFF2F2F2), // Linear [0.95, 0.95, 0.95]
          roughness: 0.05,
          isPlastic: false,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.silver:
        // Bright, slightly warm, sharp reflections
        return CadMaterialSettings(
          preset: type,
          baseColor: const Color(0xFFF7F5E8), // Linear [0.97, 0.96, 0.91]
          roughness: 0.15,
          isPlastic: false,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.gold:
        // Vibrant, saturated yellow-gold reflectance
        return CadMaterialSettings(
          preset: type,
          baseColor: const Color(0xFFFFC961), // Linear [1.00, 0.79, 0.38]
          roughness: 0.20,
          isPlastic: false,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.copper:
        // Deep reddish-orange undertones
        return CadMaterialSettings(
          preset: type,
          baseColor: const Color(0xFFF2A38A), // Linear [0.95, 0.64, 0.54]
          roughness: 0.25,
          isPlastic: false,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.aluminum:
        // Standard soft, semi-matte silver sheen
        return CadMaterialSettings(
          preset: type,
          baseColor: const Color(0xFFE8EBEB), // Linear [0.91, 0.92, 0.92]
          roughness: 0.35,
          isPlastic: false,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.ironSteel:
        // Darker, industrial gray profile
        return CadMaterialSettings(
          preset: type,
          baseColor: const Color(0xFF8F9194), // Linear [0.56, 0.57, 0.58]
          roughness: 0.40,
          isPlastic: false,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.paint:
        // Dielectric polymer coating with universal RAL or custom pigment (metallic 0.0)
        return CadMaterialSettings(
          preset: type,
          baseColor: customColor ?? const Color(0xFFC5C7C4), // Default RAL 7035 Light Grey
          roughness: customRoughness ?? 0.30,
          isPlastic: true,
          useSpangles: false,
          spangleScale: 45.0,
        );

      case CadMaterialPresetType.custom:
        return CadMaterialSettings(
          preset: type,
          baseColor: customColor ?? const Color(0xFF70A5C2),
          roughness: customRoughness ?? 0.35,
          isPlastic: false,
          useSpangles: false,
          spangleScale: 45.0,
        );
    }
  }

  /// Maps CMS / DSF Material grade string to the appropriate 3D shader preset.
  static CadMaterialPresetType presetFromMaterialGrade(String grade) {
    final upper = grade.toUpperCase();
    if (upper.contains('HDG') || upper.contains('HOT DIP')) {
      return CadMaterialPresetType.hdg;
    } else if (upper.contains('GI') || upper.contains('GALV') || upper.contains('DX51D')) {
      return CadMaterialPresetType.pgi;
    } else if (upper.contains('ALUM') || RegExp(r'\bAL\b').hasMatch(upper) || upper.contains('5052')) {
      return CadMaterialPresetType.aluminum;
    } else if (upper.contains('SS') || upper.contains('304') || upper.contains('316') || upper.contains('STAINLESS')) {
      return CadMaterialPresetType.silver;
    } else if (upper.contains('MS') || upper.contains('HR') || upper.contains('CRCA') || upper.contains('STEEL')) {
      return CadMaterialPresetType.ironSteel;
    } else if (upper.contains('PAINT') || upper.contains('POWDER') || upper.contains('EPOXY') || upper.contains('RAL')) {
      return CadMaterialPresetType.paint;
    } else if (upper.contains('PLASTIC') || upper.contains('PVC') || upper.contains('POLY')) {
      return CadMaterialPresetType.plastic;
    } else if (upper.contains('COPPER')) {
      return CadMaterialPresetType.copper;
    } else if (upper.contains('BRASS') || upper.contains('GOLD')) {
      return CadMaterialPresetType.gold;
    } else if (upper.contains('CHROME')) {
      return CadMaterialPresetType.chrome;
    }
    return CadMaterialPresetType.pgi;
  }

  /// Returns the corresponding standard SheetMetal Material Grade code.
  String toMaterialGradeCode() {
    switch (preset) {
      case CadMaterialPresetType.hdg:
        return 'HDG';
      case CadMaterialPresetType.pgi:
        return 'GI';
      case CadMaterialPresetType.plastic:
        return 'PLASTIC';
      case CadMaterialPresetType.chrome:
        return 'CHROME';
      case CadMaterialPresetType.silver:
        return 'SS304';
      case CadMaterialPresetType.gold:
        return 'GOLD';
      case CadMaterialPresetType.copper:
        return 'COPPER';
      case CadMaterialPresetType.aluminum:
        return 'AL';
      case CadMaterialPresetType.ironSteel:
        return 'MS';
      case CadMaterialPresetType.paint:
        return 'PAINT';
      case CadMaterialPresetType.custom:
        return 'GI';
    }
  }

  /// Linear RGB Vector4 for Shader uniform binding
  vm.Vector4 toLinearRgbVector4() {
    return vm.Vector4(
      baseColor.r,
      baseColor.g,
      baseColor.b,
      baseColor.a,
    );
  }

  CadMaterialSettings copyWith({
    CadMaterialPresetType? preset,
    Color? baseColor,
    double? roughness,
    bool? isPlastic,
    bool? useSpangles,
    double? spangleScale,
  }) {
    return CadMaterialSettings(
      preset: preset ?? this.preset,
      baseColor: baseColor ?? this.baseColor,
      roughness: roughness ?? this.roughness,
      isPlastic: isPlastic ?? this.isPlastic,
      useSpangles: useSpangles ?? this.useSpangles,
      spangleScale: spangleScale ?? this.spangleScale,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CadMaterialSettings &&
        other.preset == preset &&
        other.baseColor.toARGB32() == baseColor.toARGB32() &&
        (other.roughness - roughness).abs() < 1e-4 &&
        other.isPlastic == isPlastic &&
        other.useSpangles == useSpangles &&
        (other.spangleScale - spangleScale).abs() < 1e-4;
  }

  @override
  int get hashCode => Object.hash(
        preset,
        baseColor.toARGB32(),
        roughness,
        isPlastic,
        useSpangles,
        spangleScale,
      );
}
