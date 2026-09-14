// =============================================================================
// fusion_bottom_bar.dart
//
// Autodesk Fusion 360 Navigation Toolbar & TEXT COMMANDS Prompt for TruFold Studio.
// Matches Fusion 360's bottom layout:
// - Floating navigation toolstrip (Pan, Zoom, Fit, Display, Grid)
// - Collapsible TEXT COMMANDS prompt reporting under-constrained geometry
// =============================================================================

import 'package:flutter/material.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class FusionBottomBar extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;

  const FusionBottomBar({super.key, required this.viewModel});

  @override
  State<FusionBottomBar> createState() => _FusionBottomBarState();
}

class _FusionBottomBarState extends State<FusionBottomBar> {
  bool _isConsoleExpanded = false;
  final TextEditingController _textCmdCtrl = TextEditingController();

  @override
  void dispose() {
    _textCmdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final constraintCount = vm.activeConstraintDefinitions.length;
    final underConstrainedPoints = vm.document.outerContour.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Floating Navigation Toolbar (Centered above bottom bar)
        Center(
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFCBD5E1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildNavTool(
                  icon: Icons.pan_tool_outlined,
                  tooltip: 'Pan (Middle Mouse / Space)',
                  isActive: vm.toolMode == StudioToolMode.pan,
                  onTap: () => vm.setToolMode(StudioToolMode.pan),
                ),
                _buildNavTool(
                  icon: Icons.zoom_in,
                  tooltip: 'Zoom In / Out (Scroll Wheel)',
                  onTap: () => vm.zoom2DCanvas(1.2),
                ),
                _buildNavTool(
                  icon: Icons.fit_screen_outlined,
                  tooltip: 'Zoom to Fit (F)',
                  onTap: vm.reset2DCanvas,
                ),
                Container(width: 1, height: 16, color: const Color(0xFFCBD5E1), margin: const EdgeInsets.symmetric(horizontal: 4)),
                _buildNavTool(
                  icon: Icons.grid_on,
                  tooltip: 'Grid & Snaps',
                  isActive: vm.snapSettings.enableGrid,
                  onTap: vm.toggleGridSnap,
                ),
                _buildNavTool(
                  icon: Icons.layers_outlined,
                  tooltip: 'Display Settings',
                  onTap: () {},
                ),
                Container(width: 1, height: 16, color: const Color(0xFFCBD5E1), margin: const EdgeInsets.symmetric(horizontal: 4)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    vm.currentCursorMm != null
                        ? 'X: ${vm.currentCursorMm!.x.toStringAsFixed(1)} Y: ${vm.currentCursorMm!.y.toStringAsFixed(1)} mm'
                        : 'X: 0.0 Y: 0.0 mm',
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Fusion 360 TEXT COMMANDS Console Bar
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFFE2E8F0),
            border: Border(top: BorderSide(color: Color(0xFFCBD5E1))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Expand/Collapse Header
              InkWell(
                onTap: () => setState(() => _isConsoleExpanded = !_isConsoleExpanded),
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        _isConsoleExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 16,
                        color: const Color(0xFF475569),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'TEXT COMMANDS',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const Spacer(),
                      // Solver Constraint Status indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: constraintCount > 0 ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          constraintCount > 0
                              ? 'Active Constraints: $constraintCount'
                              : 'Under-constrained ($underConstrainedPoints points)',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: constraintCount > 0 ? const Color(0xFF0284C7) : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Console Expanded Log Body
              if (_isConsoleExpanded)
                Container(
                  height: 60,
                  width: double.infinity,
                  color: const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sketch.ShowUnderconstrained',
                          style: TextStyle(fontFamily: 'Consolas', fontSize: 10, color: Color(0xFF1E293B)),
                        ),
                        Text(
                          'Under constrained points: $underConstrainedPoints, constraints active: $constraintCount',
                          style: const TextStyle(fontFamily: 'Consolas', fontSize: 10, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavTool({
    required IconData icon,
    required String tooltip,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0284C7).withValues(alpha: 0.15) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 15,
            color: isActive ? const Color(0xFF0284C7) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
