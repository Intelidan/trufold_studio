// =============================================================================
// studio_theme.dart
//
// Centralized Universal UI & Typography System for TruFold Studio.
// Provides standardized, readable CAD typography scale, theme tokens,
// and consistent HUD/badge styling across viewports, toolbars, and palettes.
// =============================================================================

import 'package:flutter/material.dart';

/// Centralized universal typography scale
class StudioTypography {
  // Base font family
  static const String fontFamily = 'Roboto';

  // 1. Micro Labels & Tags (formerly 8.5–9.5px -> enhanced to 11.0px)
  static const TextStyle micro = TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600, letterSpacing: 0.2);

  static const TextStyle microBold = TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, letterSpacing: 0.2);

  // 2. Captions & Badges (formerly 10.0–10.5px -> enhanced to 12.0px)
  static const TextStyle caption = TextStyle(fontSize: 12.0, fontWeight: FontWeight.w500);

  static const TextStyle captionBold = TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold);

  // 3. Body Text (formerly 11.0–12.0px -> enhanced to 13.5px)
  static const TextStyle bodySmall = TextStyle(fontSize: 13.0, fontWeight: FontWeight.normal);

  static const TextStyle bodySmallBold = TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600);

  static const TextStyle body = TextStyle(fontSize: 14.0, fontWeight: FontWeight.normal);

  static const TextStyle bodyBold = TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold);

  // 4. Titles & Headers (formerly 12.0–13.0px -> enhanced to 15.0–16.5px)
  static const TextStyle titleSmall = TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, letterSpacing: 0.4);

  static const TextStyle title = TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, letterSpacing: 0.5);

  static const TextStyle titleLarge = TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, letterSpacing: 0.5);

  // 5. Canvas HUD & Badges
  static const TextStyle canvasBadgeDim = TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3);

  static const TextStyle canvasBadgeTitle = TextStyle(fontSize: 11.0, fontWeight: FontWeight.w700, letterSpacing: 0.3);
}

/// Centralized UI Colors
class StudioColors {
  // Brand & Technical Accents
  static const Color primaryBlue = Color(0xFF0284C7);
  static const Color primaryNavy = Color(0xFF0F172A);
  static const Color accentTeal = Color(0xFF0D9488);
  static const Color accentViolet = Color(0xFF8B5CF6);
  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentGreen = Color(0xFF16A34A);

  // Canvas & Surfaces
  static const Color canvasBg = Color(0xFFF8FAFC);
  static const Color borderLight = Color(0xFFCBD5E1);
  static const Color borderDark = Color(0xFF475569);
  static const Color textMain = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);
}

/// Global ThemeData factory for TruFold Studio
ThemeData createStudioTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: StudioColors.canvasBg,
    colorScheme: ColorScheme.fromSeed(seedColor: StudioColors.primaryBlue, brightness: Brightness.light),
    textTheme: const TextTheme(
      bodySmall: TextStyle(fontSize: 12.5, color: StudioColors.textSecondary),
      bodyMedium: TextStyle(fontSize: 13.5, color: StudioColors.textMain),
      bodyLarge: TextStyle(fontSize: 14.5, color: StudioColors.textMain),
      labelSmall: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
      titleSmall: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(fontSize: 17.5, fontWeight: FontWeight.bold),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: const TextStyle(fontSize: 12.0, color: Colors.white),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(4)),
    ),
  );
}
