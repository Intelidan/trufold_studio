import 'package:flutter/material.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Floating HUD giving the user complete control over Canvas clutter:
/// - Clean Canvas Mode (1-click hide all floating overlays)
/// - Checkbox toggles for each toolbar (Views, Joint Style, Quality HUD, 3D Navigation)
/// - Reset Toolbar Positions button
class AssemblyCanvasControlsHUD extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback onResetPositions;

  const AssemblyCanvasControlsHUD({
    super.key,
    required this.viewModel,
    required this.onResetPositions,
  });

  @override
  Widget build(BuildContext context) {
    final isClean = viewModel.isCleanCanvasMode;

    if (isClean) {
      return Positioned(
        top: 14,
        left: 60,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: viewModel.toggleCleanCanvasMode,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
              boxShadow: [
                BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 1),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_off, size: 14, color: Color(0xFF38BDF8)),
                SizedBox(width: 6),
                Text(
                  'Clean Canvas Active (Tap to Restore)',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Positioned(
      bottom: 16,
      left: 14,
      child: Material(
        color: Colors.transparent,
        child: PopupMenuButton<String>(
          tooltip: 'Canvas Layout & Toolbar Visibility',
          color: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.white12),
          ),
          position: PopupMenuPosition.over,
          itemBuilder: (ctx) => [
            PopupMenuItem<String>(
              enabled: false,
              child: Row(
                children: [
                  const Icon(Icons.dashboard_customize, size: 14, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  Text(
                    'CANVAS TOOLBAR MANAGER',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'clean_canvas',
              child: Row(
                children: [
                  Icon(
                    viewModel.isCleanCanvasMode ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  const Text('Clean Canvas Mode', style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'toggle_views',
              child: Row(
                children: [
                  Icon(
                    viewModel.showViewsToolbar ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  const Text('Standard Views Toolbar', style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'toggle_joints',
              child: Row(
                children: [
                  Icon(
                    viewModel.showJointStyleToolbar ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  const Text('Joint Configuration Toolbar', style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'toggle_quality',
              child: Row(
                children: [
                  Icon(
                    viewModel.showQualityHud ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  const Text('Weld Quality & Anomaly HUD', style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'toggle_nav',
              child: Row(
                children: [
                  Icon(
                    viewModel.show3dNavigationBar ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  const Text('3D Navigation Bar', style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'reset_positions',
              child: const Row(
                children: [
                  Icon(Icons.restart_alt, size: 16, color: Color(0xFFF59E0B)),
                  SizedBox(width: 8),
                  Text('Reset Toolbar Positions', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
          onSelected: (val) {
            switch (val) {
              case 'clean_canvas':
                viewModel.toggleCleanCanvasMode();
                break;
              case 'toggle_views':
                viewModel.toggleViewsToolbar();
                break;
              case 'toggle_joints':
                viewModel.toggleJointStyleToolbar();
                break;
              case 'toggle_quality':
                viewModel.toggleQualityHud();
                break;
              case 'toggle_nav':
                viewModel.toggle3dNavigationBar();
                break;
              case 'reset_positions':
                onResetPositions();
                break;
            }
          },
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.layers_outlined, size: 14, color: Color(0xFF38BDF8)),
                SizedBox(width: 5),
                Text('Toolbars', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                SizedBox(width: 2),
                Icon(Icons.arrow_drop_down, size: 14, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
