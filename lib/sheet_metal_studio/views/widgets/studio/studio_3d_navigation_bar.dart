// =============================================================================
// studio_3d_navigation_bar.dart
//
// Floating Industrial CAD Navigation Bar for TruFold Studio 3D Viewport.
// Provides rapid, ergonomic access to:
// - Zoom to Fit (Fit All / Extents)
// - Standard Orthogonal & Isometric View Presets (Top, Bottom, Front, Back, Right, Left, Iso)
// - Turntable vs Free Trackball Orbit mode toggle
// - Pan tool mode toggle
// - Perspective vs Orthographic Camera Projection toggle
// - CAD Mouse Navigation Profiles (TruFold, SolidWorks, Fusion 360, Blender)
// =============================================================================

import 'package:flutter/material.dart';

import '../../../models/cad_primitives.dart';

class Studio3dNavigationBar extends StatelessWidget {
  final VoidCallback onFitAll;
  final void Function(double azimuth, double elevation) onSelectView;
  final bool isTurntable;
  final VoidCallback onToggleOrbitMode;
  final bool isPanToolActive;
  final VoidCallback onTogglePanTool;
  final bool isOrtho;
  final VoidCallback onToggleProjection;

  final bool showBorderLines;
  final VoidCallback? onToggleBorderLines;
  final bool isObstructedXRay;
  final VoidCallback? onToggleObstructedXRay;
  final CadShadingStyle currentShadingStyle;
  final ValueChanged<CadShadingStyle>? onShadingStyleChanged;
  final AntiAliasingQuality currentAntiAliasing;
  final ValueChanged<AntiAliasingQuality>? onAntiAliasingChanged;

  const Studio3dNavigationBar({
    super.key,
    required this.onFitAll,
    required this.onSelectView,
    required this.isTurntable,
    required this.onToggleOrbitMode,
    required this.isPanToolActive,
    required this.onTogglePanTool,
    required this.isOrtho,
    required this.onToggleProjection,
    this.showBorderLines = true,
    this.onToggleBorderLines,
    this.isObstructedXRay = false,
    this.onToggleObstructedXRay,
    this.currentShadingStyle = CadShadingStyle.realisticPbr,
    this.onShadingStyleChanged,
    this.currentAntiAliasing = AntiAliasingQuality.high,
    this.onAntiAliasingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Fit All / Focus (Key: F)
          _NavIconButton(
            icon: Icons.fit_screen,
            tooltip: 'Zoom to Fit All (F / Home)',
            onPressed: onFitAll,
          ),
          const _NavDivider(),

          // 2. Preset Views Dropdown
          _buildPresetViewsMenu(context),
          const _NavDivider(),

          // 3. Orbit Style: Turntable (level horizon) vs Free Orbit
          _NavIconButton(
            icon: isTurntable ? Icons.screen_rotation : Icons.rotate_90_degrees_ccw,
            isActive: isTurntable,
            tooltip: isTurntable
                ? 'Turntable Orbit Active (Level Horizon Locked)\nClick for Free Orbit'
                : 'Free Trackball Orbit Active\nClick for Turntable Orbit',
            onPressed: onToggleOrbitMode,
          ),

          // 4. Pan Tool Toggle
          _NavIconButton(
            icon: Icons.pan_tool_outlined,
            isActive: isPanToolActive,
            tooltip: isPanToolActive
                ? 'Pan Mode Active (Left-Click to Pan)\nClick to Exit Pan Mode'
                : 'Pan Tool (Click to Pan with Left Mouse)',
            onPressed: onTogglePanTool,
          ),
          const _NavDivider(),

          // 5. Projection Mode (Perspective vs Ortho)
          _NavIconButton(
            icon: isOrtho ? Icons.grid_4x4 : Icons.view_in_ar,
            isActive: isOrtho,
            tooltip: isOrtho
                ? 'Orthographic (Parallel CAD) Active (5)\nClick for Perspective 3D'
                : 'Perspective 3D Active (5)\nClick for Orthographic (Parallel CAD)',
            onPressed: onToggleProjection,
          ),
          const _NavDivider(),

          // 6. Visual Shading Style (2D Anime Cel Drawing vs PBR Metal)
          _buildShadingStyleMenu(context),

          // 7. Smart Obstructed X-Ray View (Solid front, ghosted back)
          _NavIconButton(
            icon: Icons.layers_outlined,
            isActive: isObstructedXRay,
            tooltip: isObstructedXRay
                ? 'Smart Obstructed X-Ray Active\n(Solid front, ghosted internal/back features)\nClick to Deactivate'
                : 'Smart Obstructed X-Ray\n(Shows occluded internal features through solid front)',
            onPressed: onToggleObstructedXRay ?? () {},
          ),

          // 8. CAD Border Lines Toggle
          _NavIconButton(
            icon: Icons.border_style,
            isActive: showBorderLines,
            tooltip: showBorderLines
                ? 'CAD Border Lines Active (Click to Hide)'
                : 'CAD Border Lines Hidden (Click to Show)',
            onPressed: onToggleBorderLines ?? () {},
          ),
          const _NavDivider(),

          // 9. Anti-Aliasing Quality & Detail
          _buildAntiAliasingMenu(context),
          const _NavDivider(),

          // 10. Onshape Navigation Guide Indicator
          _buildNavInfoButton(context),
        ],
      ),
    );
  }


  Widget _buildPresetViewsMenu(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Standard CAD View Presets',
      padding: EdgeInsets.zero,
      offset: const Offset(-170, 0),
      icon: const Icon(Icons.grid_view_rounded, size: 16, color: Color(0xFF475569)),
      itemBuilder: (context) => [
        _buildPopupItem(0, Icons.view_in_ar, 'Isometric View (0)', 45, 30),
        const PopupMenuDivider(height: 1),
        _buildPopupItem(1, Icons.flip_to_front, 'Top Plan View (7)', 0, 89.9),
        _buildPopupItem(2, Icons.flip_to_back, 'Bottom View (9)', 0, -89.9),
        const PopupMenuDivider(height: 1),
        _buildPopupItem(3, Icons.crop_portrait, 'Front Elevation (1)', 0, 0),
        _buildPopupItem(4, Icons.photo_size_select_actual_outlined, 'Back Elevation', 180, 0),
        const PopupMenuDivider(height: 1),
        _buildPopupItem(5, Icons.crop_landscape, 'Right Side View (3)', 90, 0),
        _buildPopupItem(6, Icons.crop_16_9, 'Left Side View', -90, 0),
      ],
      onSelected: (val) {
        switch (val) {
          case 0: onSelectView(45, 30); break;
          case 1: onSelectView(0, 89.9); break;
          case 2: onSelectView(0, -89.9); break;
          case 3: onSelectView(0, 0); break;
          case 4: onSelectView(180, 0); break;
          case 5: onSelectView(90, 0); break;
          case 6: onSelectView(-90, 0); break;
        }
      },
    );
  }

  PopupMenuItem<int> _buildPopupItem(int value, IconData icon, String label, double az, double el) {
    return PopupMenuItem<int>(
      value: value,
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF0284C7)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildNavInfoButton(BuildContext context) {
    return Tooltip(
      message: 'Onshape CAD Mouse Navigation:\n• Right-Click Drag: Rotate 3D Model\n• Left-Click Drag: Pan / Select\n• Middle-Click Drag: Pan\n• Mouse Wheel: Smooth Zoom',
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Icon(Icons.mouse_rounded, size: 16, color: Color(0xFF0284C7)),
      ),
    );
  }

  Widget _buildShadingStyleMenu(BuildContext context) {
    return PopupMenuButton<CadShadingStyle>(
      tooltip: 'Visual Shading Style (2D Anime Drawn vs PBR)',
      padding: EdgeInsets.zero,
      offset: const Offset(-240, 0),
      icon: Icon(
        currentShadingStyle == CadShadingStyle.celShaded2D
            ? Icons.auto_awesome
            : Icons.palette_outlined,
        size: 16,
        color: currentShadingStyle == CadShadingStyle.celShaded2D
            ? const Color(0xFF0284C7)
            : const Color(0xFF475569),
      ),
      itemBuilder: (context) => CadShadingStyle.values.map((style) {
        final isSelected = style == currentShadingStyle;
        return PopupMenuItem<CadShadingStyle>(
          value: style,
          height: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 14,
                    color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    style.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  style.description,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onSelected: onShadingStyleChanged,
    );
  }

  Widget _buildAntiAliasingMenu(BuildContext context) {
    return PopupMenuButton<AntiAliasingQuality>(
      tooltip: 'Anti-Aliasing Detail & Resolution',
      padding: EdgeInsets.zero,
      offset: const Offset(-200, 0),
      icon: Icon(
        Icons.high_quality,
        size: 16,
        color: currentAntiAliasing == AntiAliasingQuality.ultra
            ? const Color(0xFF0284C7)
            : const Color(0xFF475569),
      ),
      itemBuilder: (context) => AntiAliasingQuality.values.map((q) {
        final isSelected = q == currentAntiAliasing;
        return PopupMenuItem<AntiAliasingQuality>(
          value: q,
          height: 38,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 14,
                color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 8),
              Text(
                q.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onSelected: onAntiAliasingChanged,
    );
  }
}


class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;

  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFE0F2FE) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? const Color(0xFF0284C7) : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? const Color(0xFF0284C7) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}

class _NavDivider extends StatelessWidget {
  const _NavDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: const Color(0xFFE2E8F0),
    );
  }
}
