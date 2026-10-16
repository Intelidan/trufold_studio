// Multi-Part Selection Floating Action Banner
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

class AssemblySelectionToolbar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback onPromptGroupNameAndGroup;

  const AssemblySelectionToolbar({
    super.key,
    required this.viewModel,
    required this.onPromptGroupNameAndGroup,
  });

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    if (vm.selectedPartIds.length < 2) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFF0076CE), width: 1.5),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF0076CE), size: 18),
              const SizedBox(width: 8),
              Text(
                '${vm.selectedPartIds.length} Parts Selected',
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0076CE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () {
                  vm.setToolMode(SketchUpToolMode.weld);
                  vm.setVcbState(
                    label: 'Weld Tool',
                    value: 'Ready',
                    hint: 'Click and drag torch to paint weld beads along entity seam',
                  );
                },
                icon: const Icon(Icons.hardware_rounded, size: 15),
                label: const Text(
                  'Manual Weld Torch (W)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              if (vm.canGroupSelectedParts) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: onPromptGroupNameAndGroup,
                  icon: const Icon(Icons.workspaces_outlined, size: 14),
                  label: const Text('Group (Ctrl+G)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
              if (vm.canUngroupSelectedParts) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626), width: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: vm.ungroupSelectedParts,
                  icon: const Icon(Icons.group_off_outlined, size: 14),
                  label: const Text('Ungroup (Ctrl+Shift+G)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
              const SizedBox(width: 8),
              InkWell(
                onTap: vm.clearSelection,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
