// =============================================================================
// cms_product_contract.dart
//
// Catalog contracts defining expected physical topology (port count, bend count,
// flange count, fastener specs) for standard CMS fittings per
// TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Section 12).
// =============================================================================

import 'package:flutter/foundation.dart';

@immutable
class CmsProductContract {
  final String productType;
  final String variationName;
  final String displayName;

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
    expectedPortCount: 2,
    expectedStructuralBends: 2,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
  );

  static const straightTray = CmsProductContract(
    productType: 'straight',
    variationName: 'straight_tray',
    displayName: 'Straight Tray',
    expectedPortCount: 2,
    expectedStructuralBends: 2,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
  );

  static const equalTee = CmsProductContract(
    productType: 'tee',
    variationName: 'equal_tee',
    displayName: 'Equal Tee',
    expectedPortCount: 3,
    expectedStructuralBends: 3,
    expectedFlanges: 3,
    expectedCouplerSlotsPerPort: 4,
  );

  static const unequalTee = CmsProductContract(
    productType: 'tee',
    variationName: 'unequal_tee',
    displayName: 'Unequal Tee',
    expectedPortCount: 3,
    expectedStructuralBends: 3,
    expectedFlanges: 3,
    expectedCouplerSlotsPerPort: 4,
    hasRoleSuggestionRule: true,
  );

  static const concentricReducer = CmsProductContract(
    productType: 'reducer',
    variationName: 'concentric_reducer',
    displayName: 'Concentric Reducer',
    expectedPortCount: 2,
    expectedStructuralBends: 2,
    expectedFlanges: 2,
    expectedCouplerSlotsPerPort: 4,
    hasRoleSuggestionRule: true,
  );

  static const equalCross = CmsProductContract(
    productType: 'cross',
    variationName: 'equal_cross',
    displayName: 'Equal Cross',
    expectedPortCount: 4,
    expectedStructuralBends: 4,
    expectedFlanges: 4,
    expectedCouplerSlotsPerPort: 4,
  );

  static const unequalCross = CmsProductContract(
    productType: 'cross',
    variationName: 'unequal_cross',
    displayName: 'Unequal Cross',
    expectedPortCount: 4,
    expectedStructuralBends: 4,
    expectedFlanges: 4,
    expectedCouplerSlotsPerPort: 4,
    hasRoleSuggestionRule: true,
  );

  static const List<CmsProductContract> allContracts = [
    bend45,
    bend90,
    straightTray,
    equalTee,
    unequalTee,
    concentricReducer,
    equalCross,
    unequalCross,
  ];

  /// Disambiguated contract lookup prioritizing exact key matches.
  static CmsProductContract? lookup(String? productType, String? variantName) {
    if (productType == null && variantName == null) return null;
    final normType = (productType ?? '').trim().toLowerCase().replaceAll(' ', '_');
    final normVar = (variantName ?? '').trim().toLowerCase().replaceAll(' ', '_');

    // 1. Exact variation match
    for (final c in allContracts) {
      if (c.variationName == normVar) return c;
    }

    // 2. Exact productType match when variation is empty
    for (final c in allContracts) {
      if (c.productType == normType && normVar.isEmpty) return c;
    }

    // 3. Disambiguate 'unequal' before 'equal'
    if (normVar.contains('unequal') || normType.contains('unequal')) {
      if (normType.contains('tee') || normVar.contains('tee')) return unequalTee;
      if (normType.contains('cross') || normVar.contains('cross')) return unequalCross;
    }

    // 4. Fuzzy fallback
    if (normVar.contains('45') || normType.contains('45')) return bend45;
    if (normVar.contains('90') || normType.contains('90')) return bend90;
    if (normType.contains('tee') || normVar.contains('tee')) return equalTee;
    if (normType.contains('cross') || normVar.contains('cross')) return equalCross;
    if (normType.contains('reducer') || normVar.contains('reducer')) return concentricReducer;
    if (normType.contains('straight') || normVar.contains('straight')) return straightTray;

    return null;
  }
}
