// =============================================================================
// studio_sketch_palette.dart
//
// Floating SKETCH PALETTE for truFold Studio 2D Viewport.
// Palette options:
// - Header: ⚙ SKETCH PALETTE ▸▸
// - Linetype toggle (Construction vs Normal)
// - Look At tool
// - Checkboxes:
//   * Sketch Grid
//   * Snap
//   * Profile (Soft translucent blue closed-profile fill)
//   * Points (Vertex dot markers)
//   * Dimensions (Driving & reference dimension lines)
//   * Constraints (Constraint glyph badges)
//   * Construction Geometries
// - Finish Sketch action button
// =============================================================================

import 'package:flutter/material.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class StudioSketchPalette extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final bool showProfileFill;
  final bool showPoints;
  final bool showGrid;
  final ValueChanged<bool> onToggleProfileFill;
  final ValueChanged<bool> onTogglePoints;
  final ValueChanged<bool> onToggleGrid;
  final VoidCallback onFinishSketch;

  const StudioSketchPalette({
    super.key,
    required this.viewModel,
    required this.showProfileFill,
    required this.showPoints,
    this.showGrid = true,
    required this.onToggleProfileFill,
    required this.onTogglePoints,
    required this.onToggleGrid,
    required this.onFinishSketch,
  });

  @override
  State<StudioSketchPalette> createState() => _StudioSketchPaletteState();
}

class _StudioSketchPaletteState extends State<StudioSketchPalette> {
  bool _isCollapsed = false;
  bool _isConstructionLinetype = false;
  bool _snap = true;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;

    if (_isCollapsed) {
      return InkWell(
        onTap: () => setState(() => _isCollapsed = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFCBD5E1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 15, color: Color(0xFF0F172A)),
              SizedBox(width: 5),
              Text(
                'SKETCH PALETTE',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_left, size: 15, color: Color(0xFF64748B)),
            ],
          ),
        ),
      );
    }

    return Container(
      width: 205,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Bar: ⚙ SKETCH PALETTE ▸▸
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_outlined, size: 13, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'SKETCH PALETTE',
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _isCollapsed = true),
                  child: const Icon(Icons.fast_forward, size: 14, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          // 2. Options Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: const [
                Icon(Icons.arrow_drop_down, size: 15, color: Color(0xFF64748B)),
                Text(
                  'Options',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
              ],
            ),
          ),

          // Linetype Toggle Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Linetype', style: TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
                ),
                InkWell(
                  onTap: () {
                    setState(() => _isConstructionLinetype = !_isConstructionLinetype);
                    vm.toggleConstructionGeometry();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: _isConstructionLinetype ? const Color(0xFFD97706).withValues(alpha: 0.2) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: _isConstructionLinetype ? const Color(0xFFD97706) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Text(
                      _isConstructionLinetype ? '---' : '──',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _isConstructionLinetype ? const Color(0xFFD97706) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Look At Camera
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Look At', style: TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
                ),
                InkWell(
                  onTap: vm.reset2DCanvas,
                  child: const Icon(Icons.remove_red_eye_outlined, size: 15, color: Color(0xFF0284C7)),
                ),
              ],
            ),
          ),

          // Input Mode indicator & explanation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Input Mode', style: TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
                ),
                Tooltip(
                  message: 'Click & Drag Mode (Onshape CAD)\n• Click down, drag to shape, release to commit.\n• Or click-move-click for step-by-step points.',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFBFDBFE), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gesture, size: 12, color: Color(0xFF2563EB)),
                        SizedBox(width: 4),
                        Text(
                          'Click & Drag',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 8, thickness: 0.8, color: Color(0xFFE2E8F0)),

          // Checkboxes
          _buildPaletteCheckbox(
            label: 'Sketch Grid',
            value: widget.showGrid,
            onChanged: (v) => widget.onToggleGrid(v ?? true),
          ),
          _buildPaletteCheckbox(
            label: 'Snap',
            value: _snap,
            onChanged: (v) {
              setState(() => _snap = v ?? true);
              if (vm.magneticSnapEnabled != _snap) vm.toggleMagneticSnap();
            },
          ),
          _buildPaletteCheckbox(
            label: 'Profile',
            value: widget.showProfileFill,
            onChanged: (v) => widget.onToggleProfileFill(v ?? true),
          ),
          _buildPaletteCheckbox(
            label: 'Points',
            value: widget.showPoints,
            onChanged: (v) => widget.onTogglePoints(v ?? true),
          ),
          _buildPaletteCheckbox(
            label: 'Dimensions',
            value: vm.showDimensions,
            onChanged: (v) => vm.toggleDimensions(),
          ),
          _buildPaletteCheckbox(
            label: 'Constraints',
            value: vm.showConstraints,
            onChanged: (v) => vm.toggleConstraints(),
          ),
          _buildPaletteCheckbox(
            label: 'Construction Geometries',
            value: vm.showConstructionGeometry,
            onChanged: (v) => vm.toggleConstructionGeometry(),
          ),

          const SizedBox(height: 6),

          // Bottom "Finish Sketch" Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: OutlinedButton(
              onPressed: widget.onFinishSketch,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 5),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                backgroundColor: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text(
                'Finish Sketch',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(
            width: 22,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: const Color(0xFF0284C7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ],
      ),
    );
  }
}
