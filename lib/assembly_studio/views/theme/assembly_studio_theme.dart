import 'package:flutter/material.dart';

/// Centralized design tokens for the dual Light / Dark theme system across Assembly Studio.
/// Ensures consistent, high-contrast, glare-free aesthetic in both Light and Dark studio modes.
class AssemblyStudioTheme {
  final bool isLight;
  const AssemblyStudioTheme({required this.isLight});

  // Workbench scaffold background
  Color get scaffoldBackground => isLight ? const Color(0xFFF1F5F9) : const Color(0xFF141418);

  // Top header / menu bar
  Color get menuBarBackground => isLight ? Colors.white : const Color(0xFF16161C);
  Color get menuBarBorder => isLight ? const Color(0xFFE2E8F0) : const Color(0xFF262630);
  Color get menuTabTextColor => isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  Color get menuDividerColor => isLight ? const Color(0xFFE2E8F0) : const Color(0xFF2C2C38);

  // Panels (Hierarchy Tree, Inspector, Asset Drawer)
  Color get panelBackground => isLight ? Colors.white : const Color(0xFF1E1E24);
  Color get panelHeaderBackground => isLight ? const Color(0xFFF8FAFC) : const Color(0xFF16161A);
  Color get panelBorder => isLight ? const Color(0xFFE2E8F0) : const Color(0xFF2C2C34);
  Color get panelDivider => isLight ? const Color(0xFFF1F5F9) : const Color(0xFF282832);

  // Cards & Rows inside panels
  Color get cardBackground => isLight ? const Color(0xFFF8FAFC) : const Color(0xFF24242D);
  Color get cardSurface => cardBackground;
  Color get cardBorder => isLight ? const Color(0xFFE2E8F0) : const Color(0xFF33333E);
  Color get borderSubtle => cardBorder;
  Color get cardHoverBackground => isLight ? const Color(0xFFF1F5F9) : const Color(0xFF2A2A36);
  Color get cardActiveBackground => isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0284C7).withValues(alpha: 0.22);

  // Input Fields & Micro-nudge controls
  Color get inputBackground => isLight ? Colors.white : const Color(0xFF141418);
  Color get inputBorder => isLight ? const Color(0xFFCBD5E1) : const Color(0xFF33333E);
  Color get inputFocusBorder => isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8);

  // Status Bar
  Color get statusBarBackground => isLight ? const Color(0xFFF8FAFC) : const Color(0xFF111115);
  Color get statusBarBorder => isLight ? const Color(0xFFE2E8F0) : const Color(0xFF22222A);

  // Typography
  Color get textPrimary => isLight ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  Color get textSecondary => isLight ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1);
  Color get textTertiary => isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8);
  Color get textMuted => isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

  // Brand Accents
  Color get accentSky => isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8);
  Color get accentSkyBg => isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0284C7).withValues(alpha: 0.2);
  Color get accentEmerald => isLight ? const Color(0xFF059669) : const Color(0xFF10B981);
  Color get accentEmeraldBg => isLight ? const Color(0xFFD1FAE5) : const Color(0xFF10B981).withValues(alpha: 0.2);
  Color get accentAmber => isLight ? const Color(0xFFD97706) : const Color(0xFFF59E0B);
  Color get accentAmberBg => isLight ? const Color(0xFFFEF3C7) : const Color(0xFFF59E0B).withValues(alpha: 0.2);
  Color get accentRed => isLight ? const Color(0xFFDC2626) : const Color(0xFFEF4444);
  Color get accentPurple => isLight ? const Color(0xFF7C3AED) : const Color(0xFFA855F7);
}
