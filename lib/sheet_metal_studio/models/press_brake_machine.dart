// =============================================================================
// press_brake_machine.dart
//
// Press Brake Machine Specifications & Tooling Database for CAM Rules.
// Stores mechanical limits (Tonnage, Bed Length, Daylight, Throat Depth, V-Die),
// and punch profile definitions for collision analysis.
// =============================================================================

/// Punch tool profile type for press-brake collision analysis
enum PunchToolType {
  straight,      // Standard straight wedge punch (88° / 90°)
  gooseneck,     // Relief cutout throat for clearing pre-folded flanges (85°)
  semiGooseneck, // Medium relief cutout punch (85°)
  acute,         // Acute knife tool (30°) for tight air bending & hemming prep
  sash,          // Narrow channel sash punch (88°) for deep U-channels
  radius,        // Large radius round nose punch (R5.0 / R10.0)
  hemming,       // Hemming / Dutch fold flattening punch (30° / flat)
  sword,         // Extended sword punch (88°) for deep narrow enclosures
}

class PressBrakeMachine {
  final String id;
  final String name;
  final double maxTonnageKN;     // Maximum pressing force in kN (10 kN ≈ 1 metric ton)
  final double throatDepthMm;    // Frame throat gap / maximum flange back-gauge reach
  final double maxBendLengthMm;  // Maximum bed/ram bend length in mm
  final double minBendLengthMm;  // Shortest tooling segment in mm
  final double openHeightMm;     // Daylight open height (ram up to bed)
  final double vDieWidthMm;      // Default V-die opening width
  final PunchToolType punchType; // Upper punch profile

  const PressBrakeMachine({
    required this.id,
    required this.name,
    required this.maxTonnageKN,
    required this.throatDepthMm,
    required this.maxBendLengthMm,
    this.minBendLengthMm = 20.0,
    this.openHeightMm = 450.0,
    this.vDieWidthMm = 12.0,
    this.punchType = PunchToolType.straight,
  });

  /// Maximum pressing force in metric tons
  double get maxTonnageTons => maxTonnageKN / 9.80665;

  PressBrakeMachine copyWith({
    String? id,
    String? name,
    double? maxTonnageKN,
    double? throatDepthMm,
    double? maxBendLengthMm,
    double? minBendLengthMm,
    double? openHeightMm,
    double? vDieWidthMm,
    PunchToolType? punchType,
  }) {
    return PressBrakeMachine(
      id: id ?? this.id,
      name: name ?? this.name,
      maxTonnageKN: maxTonnageKN ?? this.maxTonnageKN,
      throatDepthMm: throatDepthMm ?? this.throatDepthMm,
      maxBendLengthMm: maxBendLengthMm ?? this.maxBendLengthMm,
      minBendLengthMm: minBendLengthMm ?? this.minBendLengthMm,
      openHeightMm: openHeightMm ?? this.openHeightMm,
      vDieWidthMm: vDieWidthMm ?? this.vDieWidthMm,
      punchType: punchType ?? this.punchType,
    );
  }

  /// Standard industrial press brake presets
  static List<PressBrakeMachine> standardPresets() => [
    const PressBrakeMachine(
      id: 'amada_hfp_50',
      name: 'Amada HFP-5028 (50T / 2m)',
      maxTonnageKN: 500.0,
      throatDepthMm: 410.0,
      maxBendLengthMm: 2050.0,
      minBendLengthMm: 20.0,
      openHeightMm: 470.0,
      vDieWidthMm: 12.0,
      punchType: PunchToolType.straight,
    ),
    const PressBrakeMachine(
      id: 'trumpf_trubend_3066',
      name: 'Trumpf TruBend 3066 (66T / Gooseneck)',
      maxTonnageKN: 660.0,
      throatDepthMm: 420.0,
      maxBendLengthMm: 2040.0,
      minBendLengthMm: 15.0,
      openHeightMm: 470.0,
      vDieWidthMm: 12.0,
      punchType: PunchToolType.gooseneck,
    ),
    const PressBrakeMachine(
      id: 'generic_workshop_100t',
      name: 'Industrial Heavy Brake (100T / 3.1m)',
      maxTonnageKN: 1000.0,
      throatDepthMm: 500.0,
      maxBendLengthMm: 3100.0,
      minBendLengthMm: 25.0,
      openHeightMm: 520.0,
      vDieWidthMm: 16.0,
      punchType: PunchToolType.straight,
    ),
    const PressBrakeMachine(
      id: 'heavy_duty_250t',
      name: 'Heavy Plate Brake (250T / 4m)',
      maxTonnageKN: 2500.0,
      throatDepthMm: 600.0,
      maxBendLengthMm: 4100.0,
      minBendLengthMm: 50.0,
      openHeightMm: 650.0,
      vDieWidthMm: 24.0,
      punchType: PunchToolType.straight,
    ),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PressBrakeMachine && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
