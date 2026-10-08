import 'dart:ui' show Color;
import 'cad_material_preset.dart';

/// Supported secondary paint coating types for sheet metal routing products.
enum PaintCoatType {
  none('none', 'None (Unpainted / Bare)'),
  powderCoat('pc', 'Powder Coated (PC)'),
  epoxy('ex', 'Epoxy Coated (EX)');

  final String code;
  final String displayName;
  const PaintCoatType(this.code, this.displayName);

  bool get isPainted => this != PaintCoatType.none;

  static PaintCoatType fromCode(String? code) {
    if (code == null) return PaintCoatType.none;
    final lower = code.trim().toLowerCase();
    for (final val in values) {
      if (val.code.toLowerCase() == lower || val.name.toLowerCase() == lower) {
        return val;
      }
    }
    if (lower.contains('powder') || lower.contains('pc')) return PaintCoatType.powderCoat;
    if (lower.contains('epoxy') || lower.contains('ex')) return PaintCoatType.epoxy;
    return PaintCoatType.none;
  }
}

/// Universal RAL Classic industrial color definition for cable management routing.
class RalColor {
  final String code;
  final String name;
  final Color color;
  final String category;

  const RalColor(
    this.code,
    this.name,
    this.color, {
    this.category = 'Standard',
  });

  String get displayName => '$code $name';

  static const RalColor ral7035 = RalColor('RAL 7035', 'Light Grey', Color(0xFFC5C7C4), category: 'Grey');
  static const RalColor ral7032 = RalColor('RAL 7032', 'Pebble Grey', Color(0xFFB8B799), category: 'Grey');
  static const RalColor ral7016 = RalColor('RAL 7016', 'Anthracite Grey', Color(0xFF383E42), category: 'Grey');
  static const RalColor ral9005 = RalColor('RAL 9005', 'Jet Black', Color(0xFF0A0A0D), category: 'Black');
  static const RalColor ral9003 = RalColor('RAL 9003', 'Signal White', Color(0xFFECECE7), category: 'White');
  static const RalColor ral9006 = RalColor('RAL 9006', 'White Aluminium', Color(0xFFA5A8A6), category: 'Metallic');
  static const RalColor ral5012 = RalColor('RAL 5012', 'Light Blue', Color(0xFF2B82C9), category: 'Blue');
  static const RalColor ral1021 = RalColor('RAL 1021', 'Rape Yellow', Color(0xFFF3DA0B), category: 'Yellow');
  static const RalColor ral3000 = RalColor('RAL 3000', 'Flame Red', Color(0xFFAF2B1E), category: 'Red');
  static const RalColor ral6005 = RalColor('RAL 6005', 'Moss Green', Color(0xFF2F4538), category: 'Green');

  static const RalColor defaultRal = ral7035;

  /// Top 10 most common RAL colors in cable tray & routing installations
  static const List<RalColor> topCMSColors = [
    ral7035,
    ral7032,
    ral7016,
    ral9005,
    ral9003,
    ral9006,
    ral5012,
    ral1021,
    ral3000,
    ral6005,
  ];

  /// Standard RAL Classic industrial catalog
  static const List<RalColor> classicColors = [
    // Greys
    RalColor('RAL 7035', 'Light Grey', Color(0xFFC5C7C4), category: 'Grey'),
    RalColor('RAL 7032', 'Pebble Grey', Color(0xFFB8B799), category: 'Grey'),
    RalColor('RAL 7038', 'Agate Grey', Color(0xFFB0B0A4), category: 'Grey'),
    RalColor('RAL 7040', 'Window Grey', Color(0xFF989EA1), category: 'Grey'),
    RalColor('RAL 7016', 'Anthracite Grey', Color(0xFF383E42), category: 'Grey'),
    RalColor('RAL 7021', 'Black Grey', Color(0xFF2F3234), category: 'Grey'),
    RalColor('RAL 7001', 'Silver Grey', Color(0xFF8C969E), category: 'Grey'),
    // Whites & Metallics
    RalColor('RAL 9003', 'Signal White', Color(0xFFECECE7), category: 'White'),
    RalColor('RAL 9010', 'Pure White', Color(0xFFFFFFFF), category: 'White'),
    RalColor('RAL 9016', 'Traffic White', Color(0xFFF1F0EA), category: 'White'),
    RalColor('RAL 9006', 'White Aluminium', Color(0xFFA5A8A6), category: 'Metallic'),
    RalColor('RAL 9007', 'Grey Aluminium', Color(0xFF878581), category: 'Metallic'),
    // Blacks
    RalColor('RAL 9005', 'Jet Black', Color(0xFF0A0A0D), category: 'Black'),
    RalColor('RAL 9004', 'Signal Black', Color(0xFF282828), category: 'Black'),
    RalColor('RAL 9011', 'Graphite Black', Color(0xFF1C1C1C), category: 'Black'),
    // Blues
    RalColor('RAL 5012', 'Light Blue', Color(0xFF2B82C9), category: 'Blue'),
    RalColor('RAL 5015', 'Sky Blue', Color(0xFF007CB0), category: 'Blue'),
    RalColor('RAL 5017', 'Traffic Blue', Color(0xFF005B8C), category: 'Blue'),
    RalColor('RAL 5010', 'Gentian Blue', Color(0xFF0E467F), category: 'Blue'),
    RalColor('RAL 5005', 'Signal Blue', Color(0xFF154889), category: 'Blue'),
    // Greens
    RalColor('RAL 6005', 'Moss Green', Color(0xFF2F4538), category: 'Green'),
    RalColor('RAL 6018', 'Yellow Green', Color(0xFF48A43F), category: 'Green'),
    RalColor('RAL 6002', 'Leaf Green', Color(0xFF325928), category: 'Green'),
    // Yellows & Oranges
    RalColor('RAL 1021', 'Rape Yellow', Color(0xFFF3DA0B), category: 'Yellow'),
    RalColor('RAL 1023', 'Traffic Yellow', Color(0xFFF7BA0B), category: 'Yellow'),
    RalColor('RAL 1003', 'Signal Yellow', Color(0xFFE5A100), category: 'Yellow'),
    RalColor('RAL 2004', 'Pure Orange', Color(0xFFE25303), category: 'Orange'),
    RalColor('RAL 2000', 'Yellow Orange', Color(0xFFD4652F), category: 'Orange'),
    // Reds
    RalColor('RAL 3000', 'Flame Red', Color(0xFFAF2B1E), category: 'Red'),
    RalColor('RAL 3001', 'Signal Red', Color(0xFFA02128), category: 'Red'),
    RalColor('RAL 3020', 'Traffic Red', Color(0xFFCC0605), category: 'Red'),
  ];

  static RalColor fromCode(String? code) {
    if (code == null) return defaultRal;
    final cleaned = code.trim().toUpperCase().replaceAll(' ', '');
    for (final c in classicColors) {
      if (c.code.toUpperCase().replaceAll(' ', '') == cleaned) {
        return c;
      }
    }
    for (final c in classicColors) {
      if (cleaned.contains(c.code.replaceAll(' ', '')) || c.name.toUpperCase().replaceAll(' ', '') == cleaned) {
        return c;
      }
    }
    return defaultRal;
  }

  static RalColor? find(String query) {
    final q = query.trim().toUpperCase();
    if (q.isEmpty) return null;
    for (final c in classicColors) {
      if (c.code.toUpperCase().contains(q) || c.name.toUpperCase().contains(q)) {
        return c;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'color': color.toARGB32(),
        'category': category,
      };

  factory RalColor.fromJson(Map<String, dynamic> json) {
    final code = json['code'] as String? ?? 'RAL 7035';
    final name = json['name'] as String? ?? 'Light Grey';
    final colorVal = json['color'] as int?;
    final category = json['category'] as String? ?? 'Standard';
    return RalColor(
      code,
      name,
      colorVal != null ? Color(colorVal) : const Color(0xFFC5C7C4),
      category: category,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RalColor &&
        other.code == code &&
        other.name == name &&
        other.color.toARGB32() == color.toARGB32();
  }

  @override
  int get hashCode => Object.hash(code, name, color.toARGB32());
}

/// Complete secondary paint coat specification applied over primary substrate (GI, HDG, MS, etc.).
class PaintCoatSpecification {
  final PaintCoatType type;
  final RalColor ralColor;
  final double roughness;

  const PaintCoatSpecification({
    this.type = PaintCoatType.none,
    this.ralColor = RalColor.defaultRal,
    this.roughness = 0.30,
  });

  /// True when secondary paint or powder coating is active
  bool get isPainted => type.isPainted;

  /// User-facing descriptive label (e.g. "Powder Coated [RAL 7035 Light Grey]")
  String get displayLabel {
    if (!isPainted) return 'None (Unpainted Mill/Galv)';
    final typeName = type == PaintCoatType.powderCoat ? 'Powder Coated' : 'Epoxy Painted';
    return '$typeName [${ralColor.displayName}]';
  }

  /// Creates a ready-to-render PBR CadMaterialSettings for the 3D viewport
  CadMaterialSettings toCadMaterialSettings() {
    return CadMaterialSettings(
      preset: CadMaterialPresetType.paint,
      baseColor: ralColor.color,
      roughness: roughness,
      isPlastic: true, // Dielectric polymer film
      useSpangles: false, // Paint obscures underlying spangle
      spangleScale: 45.0,
    );
  }

  PaintCoatSpecification copyWith({
    PaintCoatType? type,
    RalColor? ralColor,
    double? roughness,
  }) {
    return PaintCoatSpecification(
      type: type ?? this.type,
      ralColor: ralColor ?? this.ralColor,
      roughness: roughness ?? this.roughness,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'ralColor': ralColor.toJson(),
        'roughness': roughness,
      };

  factory PaintCoatSpecification.fromJson(Map<String, dynamic> json) {
    return PaintCoatSpecification(
      type: PaintCoatType.fromCode(json['type'] as String?),
      ralColor: json['ralColor'] != null
          ? RalColor.fromJson(json['ralColor'] as Map<String, dynamic>)
          : RalColor.defaultRal,
      roughness: (json['roughness'] as num?)?.toDouble() ?? 0.30,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaintCoatSpecification &&
        other.type == type &&
        other.ralColor == ralColor &&
        (other.roughness - roughness).abs() < 1e-4;
  }

  @override
  int get hashCode => Object.hash(type, ralColor, roughness);
}
