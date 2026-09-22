// =============================================================================
// cms_product_contract.dart
//
// Catalog contracts defining expected physical topology (port count, bend count,
// flange count, fastener specs) for standard CMS fittings per
// TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Section 12).
// =============================================================================

import 'package:flutter/foundation.dart';

enum CmsScalingProfile {
  flatBend45,
  flatBend90,
  insideRiser,
  outsideRiser,
  tee,
  cross,
  straight,
  generic;

  String get displayName {
    switch (this) {
      case CmsScalingProfile.flatBend45:
        return '45° Flat Bend';
      case CmsScalingProfile.flatBend90:
        return '90° Flat Bend';
      case CmsScalingProfile.insideRiser:
        return '45° Inside Riser (Floor Web & Cheeks)';
      case CmsScalingProfile.outsideRiser:
        return '45° Outside Riser (Floor Web & Cheeks)';
      case CmsScalingProfile.tee:
        return 'Tee Duct Fitting';
      case CmsScalingProfile.cross:
        return 'Cross Fitting';
      case CmsScalingProfile.straight:
        return 'Straight Cable Tray';
      case CmsScalingProfile.generic:
        return 'Standard Fitting';
    }
  }
}

@immutable
class CmsProductContract {
  final String productType;
  final String variationName;
  final String displayName;
  final CmsScalingProfile scalingProfile;

  /// Expected number of physical channel mouth openings in the folded model.
  final int expectedPortCount;

  /// Expected number of main structural fold lines (floor-to-wall).
  final int expectedStructuralBends;

  /// Expected number of outer return flange lips.
  final int expectedFlanges;

  /// Expected coupler slot count per port (usually 4: 2 on each sidewall).
  final int expectedCouplerSlotsPerPort;

  /// Standard fastener slot length in mm.
  final double couplerSlotLengthMm;

  /// Standard fastener slot width in mm.
  final double couplerSlotWidthMm;

  /// Dimensional tolerance in mm when matching measured 3D openings.
  final double dimensionalToleranceMm;

  /// Whether flow roles can be inferred from physical geometry (e.g. largest width on Unequal Tee).
  final bool hasRoleSuggestionRule;

  const CmsProductContract({
    required this.productType,
    required this.variationName,
    required this.displayName,
    required this.expectedPortCount,
    required this.expectedStructuralBends,
    required this.expectedFlanges,
    this.scalingProfile = CmsScalingProfile.generic,
    this.expectedCouplerSlotsPerPort = 4,
    this.couplerSlotLengthMm = 12.0,
    this.couplerSlotWidthMm = 8.0,
    this.dimensionalToleranceMm = 3.5,
    this.hasRoleSuggestionRule = false,
  });

  int get totalExpectedCouplerSlots => expectedPortCount * expectedCouplerSlotsPerPort;

  // ---------------------------------------------------------------------------
  // Standard Catalog Contracts
  // ---------------------------------------------------------------------------

  static const bend45 = CmsProductContract(
    productType: 'bend',
    variationName: '45_deg_bend',
    displayName: '45° Bend',
    scalingProfile: CmsScalingProfile.flatBend45,
    expectedPortCount: 2,
    expectedStructuralBends: 3,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
    dimensionalToleranceMm: 3.5,
  );

  static const bend90 = CmsProductContract(
    productType: 'bend',
    variationName: '90_deg_bend',
    displayName: '90° Bend',
    scalingProfile: CmsScalingProfile.flatBend90,
    expectedPortCount: 2,
    expectedStructuralBends: 2,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
  );

  static const straightTray = CmsProductContract(
    productType: 'straight',
    variationName: 'straight_tray',
    displayName: 'Straight Tray',
    scalingProfile: CmsScalingProfile.straight,
    expectedPortCount: 2,
    expectedStructuralBends: 2,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
  );

  static const tee = CmsProductContract(
    productType: 'tee',
    variationName: 'tee',
    displayName: 'Tee',
    scalingProfile: CmsScalingProfile.tee,
    expectedPortCount: 3,
    expectedStructuralBends: 3,
    expectedFlanges: 3,
    expectedCouplerSlotsPerPort: 4,
  );
  static const equalTee = tee;
  static const unequalTee = tee;

  static const concentricReducer = CmsProductContract(
    productType: 'reducer',
    variationName: 'concentric_reducer',
    displayName: 'Concentric Reducer',
    scalingProfile: CmsScalingProfile.generic,
    expectedPortCount: 2,
    expectedStructuralBends: 2,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
    hasRoleSuggestionRule: true,
  );

  static const cross = CmsProductContract(
    productType: 'cross',
    variationName: 'cross',
    displayName: 'Cross',
    scalingProfile: CmsScalingProfile.cross,
    expectedPortCount: 4,
    expectedStructuralBends: 4,
    expectedFlanges: 4,
    expectedCouplerSlotsPerPort: 4,
  );
  static const equalCross = cross;
  static const unequalCross = cross;

  static const insideRiser45 = CmsProductContract(
    productType: 'inside_riser',
    variationName: '45_deg_inside_riser',
    displayName: '45° Inside Riser',
    scalingProfile: CmsScalingProfile.insideRiser,
    expectedPortCount: 2,
    expectedStructuralBends: 3,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
  );

  static const insideRiser90 = CmsProductContract(
    productType: 'inside_riser',
    variationName: '90_deg_inside_riser',
    displayName: '90° Inside Riser',
    scalingProfile: CmsScalingProfile.insideRiser,
    expectedPortCount: 2,
    expectedStructuralBends: 3,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
  );

  static const outsideRiser45 = CmsProductContract(
    productType: 'outside_riser',
    variationName: '45_deg_outside_riser',
    displayName: '45° Outside Riser',
    scalingProfile: CmsScalingProfile.outsideRiser,
    expectedPortCount: 2,
    expectedStructuralBends: 2,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
  );

  static const outsideRiser90 = CmsProductContract(
    productType: 'outside_riser',
    variationName: '90_deg_outside_riser',
    displayName: '90° Outside Riser',
    scalingProfile: CmsScalingProfile.outsideRiser,
    expectedPortCount: 2,
    expectedStructuralBends: 2,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
  );

  static const List<CmsProductContract> allContracts = [
    bend45,
    bend90,
    insideRiser45,
    insideRiser90,
    outsideRiser45,
    outsideRiser90,
    straightTray,
    tee,
    concentricReducer,
    cross,
  ];

  /// Disambiguated contract lookup prioritizing exact key matches.
  static CmsProductContract? lookup(String? productType, String? variantName) {
    if (productType == null && variantName == null) return null;
    final normType = (productType ?? '').trim().toLowerCase().replaceAll(' ', '_');
    final normVar = (variantName ?? '').trim().toLowerCase().replaceAll(' ', '_');
    final combined = '${normType}_$normVar';

    // 1. Exact variation match
    for (final c in allContracts) {
      if (c.variationName == normVar) return c;
    }

    // 2. Exact productType match when variation is empty
    for (final c in allContracts) {
      if (c.productType == normType && normVar.isEmpty) return c;
    }

    // 3. Risers (inside and outside) - MUST check before generic 45/90 flat bends
    if (combined.contains('inside') && (combined.contains('riser') || combined.contains('rise'))) {
      if (combined.contains('90')) return insideRiser90;
      return insideRiser45;
    }
    if (combined.contains('outside') && (combined.contains('riser') || combined.contains('rise'))) {
      if (combined.contains('90')) return outsideRiser90;
      return outsideRiser45;
    }
    if (combined.contains('riser')) {
      if (combined.contains('90')) return insideRiser90;
      return insideRiser45;
    }

    // 4. Reducers, Tees, Crosses, Straights
    if (combined.contains('reducer')) return concentricReducer;
    if (combined.contains('tee')) return tee;
    if (combined.contains('cross')) return cross;
    if (combined.contains('straight') || combined.contains('tray') || combined.contains('trunking')) return straightTray;

    // 6. Generic angle bends (flat bends) - require bend/elbow/tray/trunking keywords or explicit angle+bend pattern
    final hasBendKeyword = combined.contains('bend') || combined.contains('elbow') || combined.contains('tray') || combined.contains('trunking');
    if (hasBendKeyword) {
      if (combined.contains('90')) return bend90;
      return bend45;
    }
    if (RegExp(r'(^|[_\s])(45|90)[\s_]*(deg|degree)?[\s_]*(bend|elbow)').hasMatch(combined)) {
      if (combined.contains('90')) return bend90;
      return bend45;
    }

    return null;
  }
}
