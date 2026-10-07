// =============================================================================
// studio_bottom_bar.dart
//
// Interactive Navigation Toolbar & TEXT COMMANDS Prompt for truFold Studio.
// Layout:
// - Floating navigation toolstrip (Pan, Zoom, Fit, Display, Grid)
// - Collapsible TEXT COMMANDS prompt reporting under-constrained geometry
// =============================================================================

import 'package:flutter/material.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../../models/dynamic_dimension_input_state.dart';

class StudioBottomBar extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;

  const StudioBottomBar({super.key, required this.viewModel});

  @override
  State<StudioBottomBar> createState() => _StudioBottomBarState();
}

class _StudioBottomBarState extends State<StudioBottomBar> {
  bool _isConsoleExpanded = false;
  final TextEditingController _textCmdCtrl = TextEditingController();

  @override
  void dispose() {
    _textCmdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final constraintCount = vm.activeConstraintDefinitions.length;
        final underConstrainedPoints = vm.document.outerContour.length;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 0. Dynamic Dimension Input Command Bar (Visible during active drawing)
            if (vm.isDrawingInProgress)
              _buildDynamicInputCommandBar(vm, vm.dynamicInputState),

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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
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
                  tooltip: 'Zoom to Fit',
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
                PopupMenuButton<String>(
                  tooltip: 'Curve & Mesh Quality (2D: ${vm.curveResolution2D} seg, 3D: ${vm.curveResolution3D} seg)',
                  onSelected: (val) {
                    if (val.startsWith('2d_')) {
                      vm.setCurveResolution2D(int.parse(val.substring(3)));
                    } else if (val.startsWith('3d_')) {
                      vm.setCurveResolution3D(int.parse(val.substring(3)));
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem<String>(
                      enabled: false,
                      height: 24,
                      child: Text('2D CURVE RESOLUTION (CANVAS / DXF)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                    ),
                    PopupMenuItem(
                      value: '2d_16',
                      child: Row(
                        children: [
                          const Text('Draft (16 seg)', style: TextStyle(fontSize: 11)),
                          const Spacer(),
                          if (vm.curveResolution2D == 16) const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: '2d_32',
                      child: Row(
                        children: [
                          const Text('Standard (32 seg)', style: TextStyle(fontSize: 11)),
                          const Spacer(),
                          if (vm.curveResolution2D == 32) const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: '2d_64',
                      child: Row(
                        children: [
                          const Text('Smooth CAD (64 seg)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          if (vm.curveResolution2D == 64) const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: '2d_128',
                      child: Row(
                        children: [
                          const Text('Ultra 4K (128 seg)', style: TextStyle(fontSize: 11)),
                          const Spacer(),
                          if (vm.curveResolution2D == 128) const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      enabled: false,
                      height: 24,
                      child: Text('3D MODEL MESH QUALITY (FOLDING / FILLETS)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                    ),
                    PopupMenuItem(
                      value: '3d_16',
                      child: Row(
                        children: [
                          const Text('Fast / Performance (16 seg)', style: TextStyle(fontSize: 11)),
                          const Spacer(),
                          if (vm.curveResolution3D == 16) const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: '3d_32',
                      child: Row(
                        children: [
                          const Text('Balanced / Default (32 seg)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          if (vm.curveResolution3D == 32) const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: '3d_64',
                      child: Row(
                        children: [
                          const Text('High Fidelity (64 seg)', style: TextStyle(fontSize: 11)),
                          const Spacer(),
                          if (vm.curveResolution3D == 64) const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.blur_linear, size: 12, color: Color(0xFF0284C7)),
                        const SizedBox(width: 4),
                        Text(
                          '2D: ${vm.curveResolution2D} | 3D: ${vm.curveResolution3D}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, height: 16, color: const Color(0xFFCBD5E1), margin: const EdgeInsets.symmetric(horizontal: 4)),
                Tooltip(
                  message: 'Drawing Mode: Click & Drag (Release to Commit) or Click-Move-Click',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFBFDBFE), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gesture, size: 11, color: Color(0xFF2563EB)),
                        SizedBox(width: 3),
                        Text(
                          'Click & Drag',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                  ),
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
      ),

        // 2. TEXT COMMANDS Console Bar
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
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: constraintCount > 0 ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            constraintCount > 0
                                ? 'Active Constraints: $constraintCount'
                                : 'Under-constrained ($underConstrainedPoints pts)',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: constraintCount > 0 ? const Color(0xFF0284C7) : const Color(0xFFB45309),
                            ),
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
  },
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

  /// Builds the professional CAD Dynamic Dimension Input bar displayed in the 2D view footer.
  Widget _buildDynamicInputCommandBar(SheetMetalStudioViewModel vm, DynamicDimensionInputState inputState) {
    final mode = vm.toolMode;
    final hasTyped = inputState.hasTypedPrimary;
    final primaryVal = inputState.formatPrimary(mode);
    final isSecActive = inputState.isEditingSecondary;
    final secondaryLabel = inputState.getSecondaryLabel(mode);
    final hasSec = secondaryLabel != null;
    final hasTypedSec = inputState.hasTypedSecondary;
    final secVal = inputState.formatSecondary(mode);
    final promptTitle = inputState.getPromptTitle(mode);
    final primaryLabel = inputState.getPrimaryLabel(mode);
    final unit = inputState.unit;
    final angleDeg = inputState.angleDeg;

    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF0284C7).withValues(alpha: 0.8),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active CAD pulse indicator
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 8),
            // Prompt title
            Text(
              'COMMAND: ${promptTitle.toUpperCase()}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Color(0xFFF8FAFC),
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 16, color: const Color(0xFF334155)),
            const SizedBox(width: 10),
            // Primary input box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: !isSecActive ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: !isSecActive ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                  width: !isSecActive ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$primaryLabel: ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: !isSecActive ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    primaryVal,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: hasTyped ? const Color(0xFFFACC15) : const Color(0xFFF8FAFC),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: !isSecActive ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                    ),
                  ),
                  if (!isSecActive && hasTyped) ...[
                    const SizedBox(width: 3),
                    Container(width: 4, height: 10, color: const Color(0xFF38BDF8)),
                  ],
                ],
              ),
            ),
            // Secondary input box (if applicable)
            if (hasSec) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF475569), width: 0.8),
                ),
                child: const Text(
                  'Tab ⇄',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isSecActive ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSecActive ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                    width: isSecActive ? 1.4 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$secondaryLabel: ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSecActive ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      secVal,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: hasTypedSec ? const Color(0xFFFACC15) : const Color(0xFFF8FAFC),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isSecActive ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                      ),
                    ),
                    if (isSecActive && hasTypedSec) ...[
                      const SizedBox(width: 3),
                      Container(width: 4, height: 10, color: const Color(0xFF38BDF8)),
                    ],
                  ],
                ),
              ),
            ],
            // Angle indicator
            if (angleDeg.abs() > 0.05) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '∠ ${angleDeg.toStringAsFixed(1)}°',
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 10),
            Container(width: 1, height: 16, color: const Color(0xFF334155)),
            const SizedBox(width: 8),
            // Apply chip
            InkWell(
              onTap: () => vm.commitCurrentDrawingWithDynamicInput(),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 11, color: Colors.white),
                    SizedBox(width: 3),
                    Text(
                      '↵ Enter',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            // Cancel chip
            InkWell(
              onTap: () => vm.cancelActiveDrawing(),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 11, color: Color(0xFFCBD5E1)),
                    SizedBox(width: 2),
                    Text(
                      'Esc',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
