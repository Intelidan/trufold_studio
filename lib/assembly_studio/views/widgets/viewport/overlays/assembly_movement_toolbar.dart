// SketchUp Movement & Tool Mode Floating Toolbar
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_material_preset.dart';

class AssemblyMovementToolbar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback onRebuildGpu;
  final VoidCallback onShowMagneticCouplingDialog;

  const AssemblyMovementToolbar({
    super.key,
    required this.viewModel,
    required this.onRebuildGpu,
    required this.onShowMagneticCouplingDialog,
  });

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final isLight = vm.isLightBackground;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.96)
            : const Color(0xFF14141A).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF2C2C38),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isLight ? const Color(0x18000000) : const Color(0x33000000),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildToolItem(
              isLight: isLight,
              icon: Icons.near_me_rounded,
              label: 'Select (V)',
              isActive: vm.activeToolMode == SketchUpToolMode.select,
              onPressed: () => vm.setToolMode(SketchUpToolMode.select),
            ),
            const SizedBox(width: 3),
            _buildToolItem(
              isLight: isLight,
              icon: Icons.open_with_rounded,
              label: 'Move (M)',
              isActive: vm.activeToolMode == SketchUpToolMode.move,
              onPressed: () => vm.setToolMode(SketchUpToolMode.move),
            ),
            const SizedBox(width: 3),
            _buildToolItem(
              isLight: isLight,
              icon: Icons.rotate_right_rounded,
              label: 'Rotate (R)',
              isActive: vm.activeToolMode == SketchUpToolMode.rotate,
              onPressed: () => vm.setToolMode(SketchUpToolMode.rotate),
            ),
            const SizedBox(width: 3),
            _buildToolItem(
              isLight: isLight,
              icon: Icons.horizontal_distribute_rounded,
              label: 'Bridge (B)',
              isActive: vm.activeToolMode == SketchUpToolMode.bridge,
              accentColor: const Color(0xFF0284C7),
              onPressed: () => vm.setToolMode(SketchUpToolMode.bridge),
            ),
            const SizedBox(width: 3),
            _buildToolItem(
              isLight: isLight,
              icon: Icons.blur_linear_rounded,
              label: 'Weld (W)',
              isActive: vm.activeToolMode == SketchUpToolMode.weld,
              accentColor: const Color(0xFFF59E0B),
              onPressed: () => vm.setToolMode(SketchUpToolMode.weld),
            ),
            const SizedBox(width: 3),
            _buildToolItem(
              isLight: isLight,
              icon: Icons.hub_rounded,
              label: 'Magnet (J)',
              isActive: vm.activeToolMode == SketchUpToolMode.magnetic,
              accentColor: const Color(0xFF818CF8),
              onPressed: () => vm.setToolMode(SketchUpToolMode.magnetic),
            ),
            const SizedBox(width: 5),
            Container(
              width: 1.0,
              height: 18,
              color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF2E2E3C),
            ),
            const SizedBox(width: 5),
            _buildToolItem(
              isLight: isLight,
              icon: Icons.edit_note_rounded,
              label: 'Direct Sketch (S)',
              isActive: false,
              accentColor: const Color(0xFF0284C7),
              onPressed: () => vm.focusPartAndEnterSketch(vm.selectedPart?.id),
            ),
            if (vm.selectedPart != null && vm.isPartBonded(vm.selectedPart!.id)) ...[
              const SizedBox(width: 5),
              Container(
                width: 1.0,
                height: 18,
                color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF2E2E3C),
              ),
              const SizedBox(width: 5),
              _buildToolItem(
                isLight: isLight,
                icon: Icons.link_off_rounded,
                label: 'Break Weld & Separate',
                isActive: false,
                accentColor: const Color(0xFFEF4444),
                onPressed: () => vm.separateSelectedPart(),
              ),
            ],
            if (vm.selectedPart != null && vm.isPartMagneticallyLinked(vm.selectedPart!.id)) ...[
              const SizedBox(width: 5),
              Container(
                width: 1.0,
                height: 18,
                color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF2E2E3C),
              ),
              const SizedBox(width: 5),
              _buildToolItem(
                isLight: isLight,
                icon: Icons.remove_circle_outline_rounded,
                label: 'Break Magnetic Link',
                isActive: false,
                accentColor: const Color(0xFFF43F5E),
                onPressed: () => vm.breakAllMagneticJointsForPart(vm.selectedPart!.id),
              ),
            ],
            if (vm.doc.parts.where((p) => p.magneticSpots.isNotEmpty).length >= 2) ...[
              const SizedBox(width: 5),
              Container(
                width: 1.0,
                height: 18,
                color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF2E2E3C),
              ),
              const SizedBox(width: 5),
              _buildToolItem(
                isLight: isLight,
                icon: Icons.link_rounded,
                label: 'Link Spots Dialog',
                isActive: false,
                accentColor: const Color(0xFF6366F1),
                onPressed: onShowMagneticCouplingDialog,
              ),
            ],
            const SizedBox(width: 5),
            Container(
              width: 1.0,
              height: 18,
              color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF2E2E3C),
            ),
            const SizedBox(width: 5),
            PopupMenuButton<CadMaterialPresetType>(
              tooltip: 'Material Finish & PBR Shaders',
              initialValue: vm.graphicsPreferences.materialSettings.preset,
              color: isLight ? Colors.white : const Color(0xFF1E293B),
              onSelected: (preset) {
                vm.setMaterialPreset(preset);
                onRebuildGpu();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: CadMaterialPresetType.pgi,
                  child: Text('Pre-Galvanized (PGI)', style: TextStyle(fontSize: 11)),
                ),
                const PopupMenuItem(
                  value: CadMaterialPresetType.hdg,
                  child: Text('Hot-Dip Galvanized (HDG Spangles)', style: TextStyle(fontSize: 11)),
                ),
                const PopupMenuItem(
                  value: CadMaterialPresetType.silver,
                  child: Text('Stainless Steel 304/316', style: TextStyle(fontSize: 11)),
                ),
                const PopupMenuItem(
                  value: CadMaterialPresetType.aluminum,
                  child: Text('Mill Aluminum', style: TextStyle(fontSize: 11)),
                ),
                const PopupMenuItem(
                  value: CadMaterialPresetType.chrome,
                  child: Text('Polished Chrome', style: TextStyle(fontSize: 11)),
                ),
                const PopupMenuItem(
                  value: CadMaterialPresetType.paint,
                  child: Text('Powder Coat (Dielectric)', style: TextStyle(fontSize: 11)),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                  border: Border.all(
                    color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 12, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      vm.graphicsPreferences.materialSettings.preset.label.split(' ').first,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: isLight ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              width: 1.0,
              height: 18,
              color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF2E2E3C),
            ),
            const SizedBox(width: 5),
            _buildToolItem(
              isLight: isLight,
              icon: isLight ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              label: isLight ? 'Dark Canvas' : 'Light Canvas',
              isActive: isLight,
              accentColor: const Color(0xFF0284C7),
              onPressed: () => vm.toggleBackgroundMode(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolItem({
    required bool isLight,
    required IconData icon,
    required String label,
    required bool isActive,
    Color? accentColor,
    required VoidCallback onPressed,
  }) {
    final activeCol = accentColor ?? const Color(0xFF0284C7);
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? activeCol : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isActive
                    ? Colors.white
                    : (accentColor ?? (isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8))),
              ),
              const SizedBox(width: 4),
              Text(
                label.split(' ').first,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: isActive
                      ? Colors.white
                      : (accentColor ?? (isLight ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
