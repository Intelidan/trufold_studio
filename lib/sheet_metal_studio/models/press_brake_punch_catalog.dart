// =============================================================================
// press_brake_punch_catalog.dart
//
// Standard Market Press Brake Punch Tooling Catalog.
// Contains industry-standard upper punch profiles (European / Amada-Promecam / Wila)
// with mechanical specifications, collision clearances, and vector SVG cross-sections.
// =============================================================================

import 'press_brake_machine.dart';

class PressBrakePunchProfile {
  final PunchToolType type;
  final String id;
  final String name;
  final String standardCode;
  final double tipAngleDeg;
  final double tipRadiusMm;
  final double totalHeightMm;
  final double throatReliefMm;
  final double maxTonnageKNPerM;
  final String description;
  final String svgString;

  const PressBrakePunchProfile({
    required this.type,
    required this.id,
    required this.name,
    required this.standardCode,
    required this.tipAngleDeg,
    required this.tipRadiusMm,
    required this.totalHeightMm,
    required this.throatReliefMm,
    required this.maxTonnageKNPerM,
    required this.description,
    required this.svgString,
  });

  /// All 8 market-standard press brake punch profiles
  static List<PressBrakePunchProfile> standardCatalog() => [
    const PressBrakePunchProfile(
      type: PunchToolType.straight,
      id: 'PUNCH_STD_STRAIGHT_88',
      name: 'Standard Straight Punch 88°',
      standardCode: 'BIU-021 (Amada 10.125)',
      tipAngleDeg: 88.0,
      tipRadiusMm: 0.8,
      totalHeightMm: 150.0,
      throatReliefMm: 15.0,
      maxTonnageKNPerM: 1000.0,
      description: 'Universal standard punch for 90° air bending in sheet metal up to 3mm thickness.',
      svgString: '''
<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="metalGrad1" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#334155" />
      <stop offset="50%" stop-color="#64748B" />
      <stop offset="100%" stop-color="#334155" />
    </linearGradient>
  </defs>
  <!-- Tang clamp -->
  <rect x="38" y="5" width="24" height="20" fill="url(#metalGrad1)" stroke="#0F172A" stroke-width="1.5" rx="1" />
  <!-- Safety groove -->
  <rect x="38" y="12" width="6" height="5" fill="#1E293B" />
  <!-- Main Body -->
  <path d="M30 25 L70 25 L70 70 L52 110 L48 110 L30 70 Z" fill="url(#metalGrad1)" stroke="#0F172A" stroke-width="1.5" />
  <!-- Centerline -->
  <line x1="50" y1="5" x2="50" y2="115" stroke="#38BDF8" stroke-width="1" stroke-dasharray="3,2" />
  <!-- Tip indicator -->
  <circle cx="50" cy="110" r="2" fill="#38BDF8" />
  <text x="50" y="85" font-size="8" fill="#F8FAFC" text-anchor="middle" font-family="sans-serif" font-weight="bold">88°</text>
</svg>
''',
    ),
    const PressBrakePunchProfile(
      type: PunchToolType.gooseneck,
      id: 'PUNCH_GOOSENECK_85',
      name: 'Deep Gooseneck Punch 85°',
      standardCode: 'BIU-031 (Amada 10.155)',
      tipAngleDeg: 85.0,
      tipRadiusMm: 0.8,
      totalHeightMm: 175.0,
      throatReliefMm: 55.0,
      maxTonnageKNPerM: 650.0,
      description: 'Deep relief cutout for clearing return flanges, deep channels, and box profiles.',
      svgString: '''
<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="metalGrad2" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#334155" />
      <stop offset="50%" stop-color="#64748B" />
      <stop offset="100%" stop-color="#334155" />
    </linearGradient>
  </defs>
  <!-- Tang clamp -->
  <rect x="38" y="5" width="24" height="20" fill="url(#metalGrad2)" stroke="#0F172A" stroke-width="1.5" rx="1" />
  <!-- Safety groove -->
  <rect x="38" y="12" width="6" height="5" fill="#1E293B" />
  <!-- Gooseneck Body with Deep Throat Relief -->
  <path d="M30 25 L70 25 L70 45 C70 50 65 55 58 58 C35 65 32 78 48 108 L52 108 C32 75 42 60 70 55 L70 70 L52 110 L48 110 C35 75 30 60 30 25 Z" fill="url(#metalGrad2)" stroke="#0F172A" stroke-width="1.5" />
  <!-- Centerline -->
  <line x1="50" y1="5" x2="50" y2="115" stroke="#38BDF8" stroke-width="1" stroke-dasharray="3,2" />
  <!-- Tip indicator -->
  <circle cx="50" cy="110" r="2" fill="#38BDF8" />
  <!-- Relief arrow -->
  <text x="26" y="70" font-size="7" fill="#38BDF8" font-family="sans-serif" font-weight="bold">55mm</text>
  <text x="65" y="85" font-size="8" fill="#F8FAFC" text-anchor="middle" font-family="sans-serif" font-weight="bold">85°</text>
</svg>
''',
    ),
    const PressBrakePunchProfile(
      type: PunchToolType.semiGooseneck,
      id: 'PUNCH_SEMI_GOOSENECK_85',
      name: 'Semi-Gooseneck Punch 85°',
      standardCode: 'BIU-035 (Trumpf 126435)',
      tipAngleDeg: 85.0,
      tipRadiusMm: 0.8,
      totalHeightMm: 160.0,
      throatReliefMm: 35.0,
      maxTonnageKNPerM: 800.0,
      description: 'Balanced profile providing medium flange clearance with higher tonnage resistance than full gooseneck.',
      svgString: '''
<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="metalGrad3" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#334155" />
      <stop offset="50%" stop-color="#64748B" />
      <stop offset="100%" stop-color="#334155" />
    </linearGradient>
  </defs>
  <rect x="38" y="5" width="24" height="20" fill="url(#metalGrad3)" stroke="#0F172A" stroke-width="1.5" rx="1" />
  <rect x="38" y="12" width="6" height="5" fill="#1E293B" />
  <!-- Semi gooseneck cutout -->
  <path d="M30 25 L70 25 L70 50 C65 55 58 60 48 80 L52 110 L48 110 C38 80 40 60 30 50 Z" fill="url(#metalGrad3)" stroke="#0F172A" stroke-width="1.5" />
  <line x1="50" y1="5" x2="50" y2="115" stroke="#38BDF8" stroke-width="1" stroke-dasharray="3,2" />
  <circle cx="50" cy="110" r="2" fill="#38BDF8" />
  <text x="65" y="85" font-size="8" fill="#F8FAFC" text-anchor="middle" font-family="sans-serif" font-weight="bold">85°</text>
</svg>
''',
    ),
    const PressBrakePunchProfile(
      type: PunchToolType.acute,
      id: 'PUNCH_ACUTE_KNIFE_30',
      name: 'Acute Knife Punch 30°',
      standardCode: 'BIU-001 (Amada 10.101)',
      tipAngleDeg: 30.0,
      tipRadiusMm: 0.6,
      totalHeightMm: 150.0,
      throatReliefMm: 10.0,
      maxTonnageKNPerM: 500.0,
      description: 'Acute angle knife blade for tight air bending down to 30° and 1st stage hemming bends.',
      svgString: '''
<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="metalGrad4" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#334155" />
      <stop offset="50%" stop-color="#64748B" />
      <stop offset="100%" stop-color="#334155" />
    </linearGradient>
  </defs>
  <rect x="38" y="5" width="24" height="20" fill="url(#metalGrad4)" stroke="#0F172A" stroke-width="1.5" rx="1" />
  <rect x="38" y="12" width="6" height="5" fill="#1E293B" />
  <!-- Narrow 30 deg acute wedge -->
  <path d="M30 25 L70 25 L70 55 L52 112 L48 112 L30 55 Z" fill="url(#metalGrad4)" stroke="#0F172A" stroke-width="1.5" />
  <line x1="50" y1="5" x2="50" y2="115" stroke="#38BDF8" stroke-width="1" stroke-dasharray="3,2" />
  <circle cx="50" cy="112" r="1.5" fill="#38BDF8" />
  <text x="50" y="80" font-size="8" fill="#F8FAFC" text-anchor="middle" font-family="sans-serif" font-weight="bold">30°</text>
</svg>
''',
    ),
    const PressBrakePunchProfile(
      type: PunchToolType.sash,
      id: 'PUNCH_SASH_88',
      name: 'Narrow Sash Punch 88°',
      standardCode: 'BIU-051 (Wila Sash)',
      tipAngleDeg: 88.0,
      tipRadiusMm: 0.8,
      totalHeightMm: 175.0,
      throatReliefMm: 20.0,
      maxTonnageKNPerM: 700.0,
      description: 'Extra-slim body for narrow U-channels, electrical raceways, and window sash profiles.',
      svgString: '''
<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="metalGrad5" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#334155" />
      <stop offset="50%" stop-color="#64748B" />
      <stop offset="100%" stop-color="#334155" />
    </linearGradient>
  </defs>
  <rect x="38" y="5" width="24" height="20" fill="url(#metalGrad5)" stroke="#0F172A" stroke-width="1.5" rx="1" />
  <rect x="38" y="12" width="6" height="5" fill="#1E293B" />
  <!-- Slim straight shank -->
  <path d="M35 25 L65 25 L65 75 L52 110 L48 110 L35 75 Z" fill="url(#metalGrad5)" stroke="#0F172A" stroke-width="1.5" />
  <line x1="50" y1="5" x2="50" y2="115" stroke="#38BDF8" stroke-width="1" stroke-dasharray="3,2" />
  <circle cx="50" cy="110" r="2" fill="#38BDF8" />
  <text x="50" y="70" font-size="8" fill="#F8FAFC" text-anchor="middle" font-family="sans-serif" font-weight="bold">SASH</text>
</svg>
''',
    ),
    const PressBrakePunchProfile(
      type: PunchToolType.radius,
      id: 'PUNCH_RADIUS_R10',
      name: 'Large Radius Punch R10.0',
      standardCode: 'BIU-061 (Amada Round Nose)',
      tipAngleDeg: 80.0,
      tipRadiusMm: 10.0,
      totalHeightMm: 135.0,
      throatReliefMm: 25.0,
      maxTonnageKNPerM: 1200.0,
      description: 'Heavy nose radius preventing sheet outer cracking in aluminum alloys, stainless, and thick plate.',
      svgString: '''
<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="metalGrad6" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#334155" />
      <stop offset="50%" stop-color="#64748B" />
      <stop offset="100%" stop-color="#334155" />
    </linearGradient>
  </defs>
  <rect x="38" y="5" width="24" height="20" fill="url(#metalGrad6)" stroke="#0F172A" stroke-width="1.5" rx="1" />
  <rect x="38" y="12" width="6" height="5" fill="#1E293B" />
  <!-- Rounded bullnose bottom -->
  <path d="M30 25 L70 25 L70 70 L60 95 C55 110 45 110 40 95 L30 70 Z" fill="url(#metalGrad6)" stroke="#0F172A" stroke-width="1.5" />
  <line x1="50" y1="5" x2="50" y2="115" stroke="#38BDF8" stroke-width="1" stroke-dasharray="3,2" />
  <circle cx="50" cy="103" r="7" fill="none" stroke="#38BDF8" stroke-width="1.5" />
  <text x="50" y="80" font-size="8" fill="#F8FAFC" text-anchor="middle" font-family="sans-serif" font-weight="bold">R10</text>
</svg>
''',
    ),
    const PressBrakePunchProfile(
      type: PunchToolType.hemming,
      id: 'PUNCH_HEMMING_SPRING_30',
      name: 'Hemming Combination Punch 30°',
      standardCode: 'BIU-081 (Dutch Fold Flattening)',
      tipAngleDeg: 30.0,
      tipRadiusMm: 0.5,
      totalHeightMm: 160.0,
      throatReliefMm: 15.0,
      maxTonnageKNPerM: 1000.0,
      description: 'Two-in-one tooling: acute 30° pre-fold nose plus flat flattening table for safety hem borders.',
      svgString: '''
<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="metalGrad7" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#334155" />
      <stop offset="50%" stop-color="#64748B" />
      <stop offset="100%" stop-color="#334155" />
    </linearGradient>
  </defs>
  <rect x="38" y="5" width="24" height="20" fill="url(#metalGrad7)" stroke="#0F172A" stroke-width="1.5" rx="1" />
  <rect x="38" y="12" width="6" height="5" fill="#1E293B" />
  <!-- Hemming body with flat landing pad on side -->
  <path d="M25 25 L75 25 L75 60 L60 85 L52 112 L48 112 L40 85 L25 85 Z" fill="url(#metalGrad7)" stroke="#0F172A" stroke-width="1.5" />
  <line x1="50" y1="5" x2="50" y2="115" stroke="#38BDF8" stroke-width="1" stroke-dasharray="3,2" />
  <circle cx="50" cy="112" r="1.5" fill="#38BDF8" />
  <!-- Flat flattening face -->
  <line x1="25" y1="85" x2="40" y2="85" stroke="#F59E0B" stroke-width="2.5" />
  <text x="50" y="65" font-size="7" fill="#F8FAFC" text-anchor="middle" font-family="sans-serif" font-weight="bold">HEMMING</text>
</svg>
''',
    ),
    const PressBrakePunchProfile(
      type: PunchToolType.sword,
      id: 'PUNCH_SWORD_EXTENDED_88',
      name: 'Extended Sword Punch 88°',
      standardCode: 'BIU-091 (Deep Box Sword)',
      tipAngleDeg: 88.0,
      tipRadiusMm: 0.8,
      totalHeightMm: 210.0,
      throatReliefMm: 25.0,
      maxTonnageKNPerM: 600.0,
      description: 'Extended long-reach blade for deep electrical enclosures and 4-sided high box bends.',
      svgString: '''
<svg viewBox="0 0 100 120" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="metalGrad8" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#334155" />
      <stop offset="50%" stop-color="#64748B" />
      <stop offset="100%" stop-color="#334155" />
    </linearGradient>
  </defs>
  <rect x="38" y="5" width="24" height="20" fill="url(#metalGrad8)" stroke="#0F172A" stroke-width="1.5" rx="1" />
  <rect x="38" y="12" width="6" height="5" fill="#1E293B" />
  <!-- Long slender sword blade -->
  <path d="M42 25 L58 25 L58 95 L52 114 L48 114 L42 95 Z" fill="url(#metalGrad8)" stroke="#0F172A" stroke-width="1.5" />
  <line x1="50" y1="5" x2="50" y2="116" stroke="#38BDF8" stroke-width="1" stroke-dasharray="3,2" />
  <circle cx="50" cy="114" r="1.5" fill="#38BDF8" />
  <text x="50" y="65" font-size="7" fill="#F8FAFC" text-anchor="middle" font-family="sans-serif" font-weight="bold">SWORD</text>
</svg>
''',
    ),
  ];

  static PressBrakePunchProfile getForType(PunchToolType type) {
    return standardCatalog().firstWhere(
      (p) => p.type == type,
      orElse: () => standardCatalog().first,
    );
  }
}
