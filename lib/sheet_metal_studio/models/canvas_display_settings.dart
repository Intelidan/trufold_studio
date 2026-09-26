// =============================================================================
// canvas_display_settings.dart
//
// Immutable model for all 2D canvas display preferences.
// Controls unit-of-measure, per-category label visibility/style, zoom-adaptive
// declutter thresholds, and global canvas toggles.
// =============================================================================

import 'package:flutter/material.dart';
import 'cms/cms_physical_port.dart';
export 'cms/cms_physical_port.dart' show toNominalSize, toFabricatedSize, standardNominalSizes;

// ---------------------------------------------------------------------------
// Unit of Measure
// ---------------------------------------------------------------------------

enum CanvasUom {
  mm('mm'),
  inch('in'),
  fractionalInch('in (frac)');

  const CanvasUom(this.abbreviation);
  final String abbreviation;

  String get displayName => switch (this) {
        CanvasUom.mm => 'Millimetres (mm)',
        CanvasUom.inch => 'Decimal Inches (in)',
        CanvasUom.fractionalInch => 'Fractional Inches (in)',
      };
}

// ---------------------------------------------------------------------------
// Per-category label style
// ---------------------------------------------------------------------------

/// Styling for a single category of canvas labels.
class LabelStyle {
  final bool visible;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;

  const LabelStyle({
    this.visible = true,
    this.fontSize = 7.0,
    this.color = const Color(0xFF334155),
    this.fontWeight = FontWeight.w600,
  });

  LabelStyle copyWith({
    bool? visible,
    double? fontSize,
    Color? color,
    FontWeight? fontWeight,
  }) =>
      LabelStyle(
        visible: visible ?? this.visible,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        fontWeight: fontWeight ?? this.fontWeight,
      );

  TextStyle get textStyle => TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        letterSpacing: 0.2,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LabelStyle &&
          other.visible == visible &&
          other.fontSize == fontSize &&
          other.color == color &&
          other.fontWeight == fontWeight;

  @override
  int get hashCode => Object.hash(visible, fontSize, color, fontWeight);
}

// ---------------------------------------------------------------------------
// CanvasDisplaySettings
// ---------------------------------------------------------------------------

/// Full set of user-configurable 2D canvas display preferences.
class CanvasDisplaySettings {
  // ── Unit of Measure ─────────────────────────────────────────────────────
  final CanvasUom uom;

  /// Number of decimal places for mm and decimal-inch display.
  final int decimalPlaces;

  // ── Label Styles ────────────────────────────────────────────────────────
  final LabelStyle bendLabel;
  final LabelStyle faceLabel;
  final LabelStyle arcLabel;
  final LabelStyle dimTextLabel;
  final LabelStyle outsideDimLabel;
  final LabelStyle portBadgeLabel;

  // ── Declutter Thresholds ────────────────────────────────────────────────

  /// Minimum screen-space width OR height (px) a face must occupy before its
  /// size badge is drawn. Prevents tiny faces from showing crowded labels.
  final double faceLabelMinScreenSize;

  /// Zoom scale below which bend labels switch to compact form (ID + angle
  /// only, omitting the length string).
  final double bendLabelCompactZoomThreshold;

  /// Zoom scale below which bend labels are hidden entirely.
  final double bendLabelHideZoomThreshold;

  // ── Canvas Display Toggles ───────────────────────────────────────────────
  final bool showGrid;
  final bool showProfileFill;
  final bool showSnapPoints;
  final bool showConstructionGeometry;
  final bool showConstraints;
  final bool showDofDiagnostics;
  final bool showOpeningTags;
  final bool showDimensions;

  const CanvasDisplaySettings({
    this.uom = CanvasUom.mm,
    this.decimalPlaces = 1,
    // Bend labels — blue for up-bends, amber for down-bends (handled in
    // painter per-bend). The style here defines font size, weight and the
    // default colour used when no per-direction colour overrides are needed.
    this.bendLabel = const LabelStyle(
      visible: true,
      fontSize: 7.0,
      color: Color(0xFF0369A1),
      fontWeight: FontWeight.bold,
    ),
    this.faceLabel = const LabelStyle(
      visible: true,
      fontSize: 7.0,
      color: Color(0xFF334155),
      fontWeight: FontWeight.w600,
    ),
    this.arcLabel = const LabelStyle(
      visible: false,
      fontSize: 7.0,
      color: Color(0xFF0891B2),
      fontWeight: FontWeight.w600,
    ),
    this.dimTextLabel = const LabelStyle(
      visible: true,
      fontSize: 7.0,
      color: Color(0xFFD97706),
      fontWeight: FontWeight.bold,
    ),
    this.outsideDimLabel = const LabelStyle(
      visible: true,
      fontSize: 7.0,
      color: Color(0xFF475569),
      fontWeight: FontWeight.w500,
    ),
    this.portBadgeLabel = const LabelStyle(
      visible: true,
      fontSize: 7.0,
      color: Color(0xFF0F766E),
      fontWeight: FontWeight.w600,
    ),
    this.faceLabelMinScreenSize = 48.0,
    this.bendLabelCompactZoomThreshold = 0.6,
    this.bendLabelHideZoomThreshold = 0.25,
    this.showGrid = true,
    this.showProfileFill = true,
    this.showSnapPoints = true,
    this.showConstructionGeometry = true,
    this.showConstraints = true,
    this.showDofDiagnostics = false,
    this.showOpeningTags = true,
    this.showDimensions = true,
  });

  CanvasDisplaySettings copyWith({
    CanvasUom? uom,
    int? decimalPlaces,
    LabelStyle? bendLabel,
    LabelStyle? faceLabel,
    LabelStyle? arcLabel,
    LabelStyle? dimTextLabel,
    LabelStyle? outsideDimLabel,
    LabelStyle? portBadgeLabel,
    double? faceLabelMinScreenSize,
    double? bendLabelCompactZoomThreshold,
    double? bendLabelHideZoomThreshold,
    bool? showGrid,
    bool? showProfileFill,
    bool? showSnapPoints,
    bool? showConstructionGeometry,
    bool? showConstraints,
    bool? showDofDiagnostics,
    bool? showOpeningTags,
    bool? showDimensions,
  }) =>
      CanvasDisplaySettings(
        uom: uom ?? this.uom,
        decimalPlaces: decimalPlaces ?? this.decimalPlaces,
        bendLabel: bendLabel ?? this.bendLabel,
        faceLabel: faceLabel ?? this.faceLabel,
        arcLabel: arcLabel ?? this.arcLabel,
        dimTextLabel: dimTextLabel ?? this.dimTextLabel,
        outsideDimLabel: outsideDimLabel ?? this.outsideDimLabel,
        portBadgeLabel: portBadgeLabel ?? this.portBadgeLabel,
        faceLabelMinScreenSize:
            faceLabelMinScreenSize ?? this.faceLabelMinScreenSize,
        bendLabelCompactZoomThreshold:
            bendLabelCompactZoomThreshold ?? this.bendLabelCompactZoomThreshold,
        bendLabelHideZoomThreshold:
            bendLabelHideZoomThreshold ?? this.bendLabelHideZoomThreshold,
        showGrid: showGrid ?? this.showGrid,
        showProfileFill: showProfileFill ?? this.showProfileFill,
        showSnapPoints: showSnapPoints ?? this.showSnapPoints,
        showConstructionGeometry:
            showConstructionGeometry ?? this.showConstructionGeometry,
        showConstraints: showConstraints ?? this.showConstraints,
        showDofDiagnostics: showDofDiagnostics ?? this.showDofDiagnostics,
        showOpeningTags: showOpeningTags ?? this.showOpeningTags,
        showDimensions: showDimensions ?? this.showDimensions,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasDisplaySettings &&
          other.uom == uom &&
          other.decimalPlaces == decimalPlaces &&
          other.bendLabel == bendLabel &&
          other.faceLabel == faceLabel &&
          other.arcLabel == arcLabel &&
          other.dimTextLabel == dimTextLabel &&
          other.outsideDimLabel == outsideDimLabel &&
          other.portBadgeLabel == portBadgeLabel &&
          other.faceLabelMinScreenSize == faceLabelMinScreenSize &&
          other.bendLabelCompactZoomThreshold == bendLabelCompactZoomThreshold &&
          other.bendLabelHideZoomThreshold == bendLabelHideZoomThreshold &&
          other.showGrid == showGrid &&
          other.showProfileFill == showProfileFill &&
          other.showSnapPoints == showSnapPoints &&
          other.showConstructionGeometry == showConstructionGeometry &&
          other.showConstraints == showConstraints &&
          other.showDofDiagnostics == showDofDiagnostics &&
          other.showOpeningTags == showOpeningTags &&
          other.showDimensions == showDimensions;

  @override
  int get hashCode => Object.hashAll([
        uom,
        decimalPlaces,
        bendLabel,
        faceLabel,
        arcLabel,
        dimTextLabel,
        outsideDimLabel,
        portBadgeLabel,
        faceLabelMinScreenSize,
        bendLabelCompactZoomThreshold,
        bendLabelHideZoomThreshold,
        showGrid,
        showProfileFill,
        showSnapPoints,
        showConstructionGeometry,
        showConstraints,
        showDofDiagnostics,
        showOpeningTags,
        showDimensions,
      ]);
}

// ---------------------------------------------------------------------------
// UOM formatting helper
// ---------------------------------------------------------------------------

/// Formats a millimetre value to a display string according to [settings].
/// If [roundToNominal] is true, internal fabricated sizes (e.g. 98mm, 48mm, 148mm)
/// are formatted as rounded catalog nominal figures (e.g. 100mm, 50mm, 150mm).
String formatMeasure(double mm, CanvasDisplaySettings settings, {bool roundToNominal = false}) {
  final val = roundToNominal ? toNominalSize(mm) : mm;
  switch (settings.uom) {
    case CanvasUom.mm:
      final dp = roundToNominal ? 0 : settings.decimalPlaces;
      return '${val.toStringAsFixed(dp)} mm';
    case CanvasUom.inch:
      final inches = val / 25.4;
      return '${inches.toStringAsFixed(settings.decimalPlaces)}"';
    case CanvasUom.fractionalInch:
      return _toFractionalInch(val);
  }
}

/// Formats two mm dimensions as a "W × H" string according to [settings].
/// If [roundToNominal] is true, dimensions are rounded to standard catalog figures.
String formatDimPair(double aMm, double bMm, CanvasDisplaySettings settings, {bool roundToNominal = false}) {
  final aVal = roundToNominal ? toNominalSize(aMm) : aMm;
  final bVal = roundToNominal ? toNominalSize(bMm) : bMm;
  switch (settings.uom) {
    case CanvasUom.mm:
      final dp = roundToNominal ? 0 : settings.decimalPlaces;
      return '${aVal.toStringAsFixed(dp)} × ${bVal.toStringAsFixed(dp)} mm';
    case CanvasUom.inch:
      final dp = settings.decimalPlaces;
      final a = (aVal / 25.4).toStringAsFixed(dp);
      final b = (bVal / 25.4).toStringAsFixed(dp);
      return '$a × $b"';
    case CanvasUom.fractionalInch:
      return '${_toFractionalInch(aVal)} × ${_toFractionalInch(bVal)}';
  }
}

String _toFractionalInch(double mm) {
  const denominators = [2, 4, 8, 16, 32];
  final totalInches = mm / 25.4;
  final wholeInches = totalInches.floor();
  final fractionalPart = totalInches - wholeInches;

  if (fractionalPart < 0.01) {
    return wholeInches == 0 ? '0"' : '$wholeInches"';
  }

  // Find the closest standard fraction
  int bestNum = 1, bestDen = 2;
  double bestErr = double.infinity;
  for (final den in denominators) {
    final num = (fractionalPart * den).round();
    if (num == 0) continue;
    if (num == den) {
      // rounds to next whole inch
      return '${wholeInches + 1}"';
    }
    final err = (fractionalPart - num / den).abs();
    if (err < bestErr) {
      bestErr = err;
      bestNum = num;
      bestDen = den;
    }
  }

  // Reduce fraction
  int g = _gcd(bestNum, bestDen);
  bestNum ~/= g;
  bestDen ~/= g;

  if (wholeInches == 0) return '$bestNum/$bestDen"';
  return '$wholeInches-$bestNum/$bestDen"';
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
