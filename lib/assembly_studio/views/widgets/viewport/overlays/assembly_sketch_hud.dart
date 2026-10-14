// Onshape Direct 3D Sketch HUD
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

class AssemblySketchHud extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblySketchHud({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final part = vm.doc.parts.where((p) => p.id == vm.sketchPartId).firstOrNull;
    final partName = part?.name ?? 'Part';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x240284C7), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Direct Sketch: $partName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.0),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, color: Color(0xFFD97706), size: 13),
                  SizedBox(width: 4),
                  Text(
                    '3D Movement Locked',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildSketchToolChip(vm, 'select_entity', 'Select (V)', Icons.near_me_rounded),
            const SizedBox(width: 6),
            _buildSketchToolChip(vm, 'rectangle', 'Rectangle', Icons.crop_square_rounded),
            const SizedBox(width: 6),
            _buildSketchToolChip(vm, 'circle', 'Circle', Icons.circle_outlined),
            const SizedBox(width: 6),
            _buildSketchToolChip(vm, 'line', 'Line', Icons.show_chart_rounded),
            const SizedBox(width: 6),
            _buildSketchToolChip(vm, 'polyline', 'Polyline', Icons.polyline_rounded),
            const SizedBox(width: 6),
            _buildSketchToolChip(vm, 'bend_line', 'Bend Line', Icons.linear_scale_rounded),
            const SizedBox(width: 6),
            _buildSketchToolChip(vm, 'rung_slot', 'Punch Slot', Icons.crop_portrait_rounded),
            const SizedBox(width: 8),
            // Normal View Snap Button (Key: S)
            Tooltip(
              message: 'Focus Normal View (Shortcut: S)',
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.center_focus_strong_rounded, size: 14),
                label: const Text('Normal View (S)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                onPressed: () => vm.alignCameraToActivePlaneNormal(),
              ),
            ),
            const SizedBox(width: 6),
            // Export STL Button
            Tooltip(
              message: 'Export 3D Model to ASCII STL for 3D Printing',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.print_rounded, size: 14),
                label: const Text('Export STL', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final stl = await vm.generateIndustrialSTLFilePayload();
                  if (stl != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        content: Text('STL Compiled Successfully! (${(stl.length / 1024).toStringAsFixed(1)} KB)'),
                      ),
                    );
                  }
                },
              ),
            ),
            if (vm.selectedSketchFeatureId != null && part != null) ...[
              Builder(
                builder: (context) {
                  final feat = part.sketches.where((s) => s.id == vm.selectedSketchFeatureId).firstOrNull;
                  if (feat == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF3B82F6), width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app_rounded, size: 13, color: Color(0xFF2563EB)),
                        const SizedBox(width: 4),
                        Text(
                          '${feat.featureType.replaceAll('_', ' ').toUpperCase()}: X=${feat.localCenter.x.toInt()}mm',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Nudge -10mm',
                          child: InkWell(
                            onTap: () => vm.moveSketchFeature(part.id, feat.id, -10.0, 0.0),
                            child: const Icon(Icons.chevron_left_rounded, size: 16, color: Color(0xFF2563EB)),
                          ),
                        ),
                        Tooltip(
                          message: 'Nudge +10mm',
                          child: InkWell(
                            onTap: () => vm.moveSketchFeature(part.id, feat.id, 10.0, 0.0),
                            child: const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF2563EB)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Delete Entity',
                          child: InkWell(
                            onTap: () {
                              vm.removeSketchFeature(part.id, feat.id);
                              vm.selectSketchFeature(null);
                            },
                            child: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFEF4444)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Finish (Enter / Esc)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () => vm.finishSketch(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSketchToolChip(AssemblyStudioViewModel vm, String toolId, String label, IconData icon) {
    final isActive = vm.activeSketchTool == toolId;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        vm.activeSketchTool = toolId;
        vm.notifyDocChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? Colors.white : const Color(0xFF475569)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
