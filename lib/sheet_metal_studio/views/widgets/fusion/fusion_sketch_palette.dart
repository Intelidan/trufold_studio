// =============================================================================
// fusion_sketch_palette.dart
//
// Autodesk Fusion 360 Floating SKETCH PALETTE for TruFold Studio 2D Viewport.
// Matches Fusion 360's exact palette options:
// - Header: ⚙ SKETCH PALETTE ▸▸
// - Linetype toggle (Construction vs Normal)
// - Look At tool
// - Checkboxes:
//   * Sketch Grid
//   * Snap
//   * Slice
//   * Profile (Soft translucent blue closed-profile fill)
//   * Points (Vertex dot markers)
//   * Dimensions (Driving & reference dimension lines)
//   * Constraints (Constraint glyph badges)
//   * Projected Geometries
//   * Construction Geometries
//   * 3D Sketch
// - Finish Sketch action button
// =============================================================================

import 'package:flutter/material.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class FusionSketchPalette extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final bool showProfileFill;
  final bool showPoints;
  final ValueChanged<bool> onToggleProfileFill;
  final ValueChanged<bool> onTogglePoints;
  final VoidCallback onFinishSketch;

  const FusionSketchPalette({
    super.key,
    required this.viewModel,
    required this.showProfileFill,
    required this.showPoints,
    required this.onToggleProfileFill,
    required this.onTogglePoints,
    required this.onFinishSketch,
  });

  @override
  State<FusionSketchPalette> createState() => _FusionSketchPaletteState();
}

class _FusionSketchPaletteState extends State<FusionSketchPalette> {
  bool _isCollapsed = false;
  bool _isConstructionLinetype = false;
  bool _sketchGrid = true;
  bool _snap = true;
  bool _slice = false;
  bool _projectedGeometries = true;
  bool _threeDSketch = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;

    if (_isCollapsed) {
      return InkWell(
        onTap: () => setState(() => _isCollapsed = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              Icon(Icons.tune, size: 14, color: Color(0xFF0F172A)),
              SizedBox(width: 4),
              Text(
                'SKETCH PALETTE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_left, size: 14, color: Color(0xFF64748B)),
            ],
          ),
        ),
      );
    }

    return Container(
      width: 195,
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                const Icon(Icons.settings_outlined, size: 12, color: Color(0xFF475569)),
                const SizedBox(width: 5),
                const Expanded(
                  child: Text(
                    'SKETCH PALETTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _isCollapsed = true),
                  child: const Icon(Icons.fast_forward, size: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          // 2. Options Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: const [
                Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF64748B)),
                Text(
                  'Options',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
              ],
            ),
          ),

          // Linetype Toggle Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Linetype', style: TextStyle(fontSize: 10, color: Color(0xFF334155))),
                ),
                InkWell(
                  onTap: () {
                    setState(() => _isConstructionLinetype = !_isConstructionLinetype);
                    vm.toggleConstructionGeometry();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        fontSize: 9,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Look At', style: TextStyle(fontSize: 10, color: Color(0xFF334155))),
                ),
                InkWell(
                  onTap: vm.reset2DCanvas,
                  child: const Icon(Icons.remove_red_eye_outlined, size: 14, color: Color(0xFF0284C7)),
                ),
              ],
            ),
          ),

          const Divider(height: 8, thickness: 0.8, color: Color(0xFFE2E8F0)),

          // Checkboxes
          _buildPaletteCheckbox(
            label: 'Sketch Grid',
            value: _sketchGrid,
            onChanged: (v) => setState(() => _sketchGrid = v ?? true),
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
            label: 'Slice',
            value: _slice,
            onChanged: (v) => setState(() => _slice = v ?? false),
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
            label: 'Projected Geometries',
            value: _projectedGeometries,
            onChanged: (v) => setState(() => _projectedGeometries = v ?? true),
          ),
          _buildPaletteCheckbox(
            label: 'Construction Geometries',
            value: vm.showConstructionGeometry,
            onChanged: (v) => vm.toggleConstructionGeometry(),
          ),
          _buildPaletteCheckbox(
            label: '3D Sketch',
            value: _threeDSketch,
            onChanged: (v) => setState(() => _threeDSketch = v ?? false),
          ),

          const SizedBox(height: 6),

          // Bottom "Finish Sketch" Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: OutlinedButton(
              onPressed: widget.onFinishSketch,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 4),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                backgroundColor: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text(
                'Finish Sketch',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF334155)),
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
