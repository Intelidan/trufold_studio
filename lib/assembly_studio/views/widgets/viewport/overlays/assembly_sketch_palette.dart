import 'package:flutter/material.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Floating Sketch Palette overlay matching Autodesk Fusion 360.
/// Provides rapid toggles for Look At (Normal View), Sketch Grid, Snap to Grid,
/// Show Constraints, Show Dimensions, Show Profile Shading, Construction Mode (X),
/// Slice Body, and Project Geometry (P).
class AssemblySketchPalette extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblySketchPalette({
    super.key,
    required this.viewModel,
  });

  @override
  State<AssemblySketchPalette> createState() => _AssemblySketchPaletteState();
}

class _AssemblySketchPaletteState extends State<AssemblySketchPalette> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        if (!vm.isSketchMode || vm.activeSketchPlane == null) {
          return const SizedBox.shrink();
        }

        final plane = vm.activeSketchPlane!;

        return Positioned(
          top: 60,
          right: 16,
          child: Material(
            color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: _isCollapsed ? 190 : 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFFE2E8F0),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              InkWell(
                onTap: () => setState(() => _isCollapsed = !_isCollapsed),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
                    border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded, size: 15, color: Color(0xFF0076CE)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'SKETCH PALETTE',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Icon(
                        _isCollapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        size: 16,
                        color: const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
              ),

              // Active Plane Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: const Color(0xFFEBF5FF),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: plane.customColor ?? const Color(0xFF0076CE),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        plane.name,
                        style: const TextStyle(
                          color: Color(0xFF0076CE),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Expanded Options List
              if (!_isCollapsed) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    children: [
                      // Degree of Freedom (DOF) Status Banner (Phase 4)
                      _buildDofStatusBanner(vm),

                      // Look At Normal Button
                      _buildActionButton(
                        icon: Icons.filter_center_focus_rounded,
                        label: 'Look At',
                        shortcut: 'S',
                        accentColor: const Color(0xFF0076CE),
                        onTap: vm.alignCameraToActivePlaneNormal,
                      ),
                      const SizedBox(height: 6),

                      // Project 3D Geometry Button
                      _buildActionButton(
                        icon: Icons.architecture_rounded,
                        label: vm.isProjectGeometryMode ? 'Projecting (Active)' : 'Project Geometry',
                        shortcut: 'P',
                        accentColor: const Color(0xFF7C3AED),
                        isActive: vm.isProjectGeometryMode,
                        onTap: vm.toggleProjectGeometryMode,
                      ),
                      const SizedBox(height: 6),

                      // Construction Mode Toggle
                      _buildActionButton(
                        icon: Icons.border_style_rounded,
                        label: vm.isSketchConstructionMode ? 'Construction: ON' : 'Construction: OFF',
                        shortcut: 'X',
                        accentColor: const Color(0xFFD97706),
                        isActive: vm.isSketchConstructionMode,
                        onTap: vm.toggleSketchConstructionMode,
                      ),
                      const SizedBox(height: 6),

                      // Extrude 3D Feature Action Button (Phase 5)
                      _buildActionButton(
                        icon: Icons.layers_rounded,
                        label: vm.isExtrudeMode ? 'Extruding (Active)' : 'Extrude Profile',
                        shortcut: 'E',
                        accentColor: const Color(0xFF0076CE),
                        isActive: vm.isExtrudeMode,
                        onTap: vm.toggleExtrudeMode,
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(color: Color(0xFFE2E8F0), height: 1),
                      ),

                      // Feature Toggles (Checkboxes)
                      _buildPaletteToggle(
                        label: 'Sketch Grid',
                        value: vm.showSketchGrid,
                        onChanged: (_) => vm.toggleSketchGrid(),
                      ),
                      _buildPaletteToggle(
                        label: 'Snap to Grid',
                        value: vm.showSketchSnap,
                        onChanged: (_) => vm.toggleSketchSnap(),
                      ),
                      _buildPaletteToggle(
                        label: 'Show Constraints',
                        value: vm.showSketchConstraints,
                        onChanged: (_) => vm.toggleSketchConstraints(),
                      ),
                      _buildPaletteToggle(
                        label: 'Show Dimensions',
                        value: vm.showSketchDimensions,
                        onChanged: (_) => vm.toggleSketchDimensions(),
                      ),
                      _buildPaletteToggle(
                        label: 'Show Profile',
                        value: vm.showSketchProfileShading,
                        onChanged: (_) => vm.toggleSketchProfileShading(),
                      ),
                      _buildPaletteToggle(
                        label: 'Slice 3D Body',
                        value: vm.isSketchSliceBody,
                        onChanged: (_) => vm.toggleSketchSliceBody(),
                      ),
                    ],
                  ),
                ),

                // Active Constraints List (Phase 4)
                if (plane.constraints.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ACTIVE CONSTRAINTS',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: plane.constraints.length,
                            itemBuilder: (context, idx) {
                              final c = plane.constraints[idx];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        c.symbol,
                                        style: const TextStyle(
                                          color: Color(0xFF0076CE),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          c.label,
                                          style: const TextStyle(
                                            color: Color(0xFF334155),
                                            fontSize: 10,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => vm.removeSketchConstraint(c.id),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Color(0xFFDC2626),
                                          size: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Extrude Profile Button (Phase 5)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                  child: ElevatedButton.icon(
                    onPressed: vm.toggleExtrudeMode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vm.isExtrudeMode ? const Color(0xFF16A34A) : const Color(0xFF0076CE),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.view_in_ar_rounded, size: 15),
                    label: const Text(
                      'Extrude Profile (E)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                // Finish Sketch Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: ElevatedButton.icon(
                    onPressed: vm.finishSketch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 15),
                    label: const Text(
                      'Finish Sketch',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  },
);
  }

  Widget _buildDofStatusBanner(AssemblyStudioViewModel vm) {
    final dofs = vm.sketchDegreesOfFreedom;
    final isConstrained = vm.isSketchFullyConstrained;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isConstrained ? const Color(0xFFECFDF5) : const Color(0xFFEBF5FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isConstrained ? const Color(0xFF10B981) : const Color(0xFF0076CE),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConstrained ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 13,
            color: isConstrained ? const Color(0xFF10B981) : const Color(0xFF0076CE),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isConstrained ? 'Fully Constrained (Black)' : 'Under-constrained: $dofs DOFs (Blue)',
              style: TextStyle(
                color: isConstrained ? const Color(0xFF065F46) : const Color(0xFF0076CE),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String shortcut,
    required Color accentColor,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFEBF5FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? accentColor : const Color(0xFFE2E8F0),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: isActive ? accentColor : const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? const Color(0xFF0F172A) : const Color(0xFF334155),
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
              ),
              child: Text(
                shortcut,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaletteToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
                activeColor: const Color(0xFF0076CE),
                checkColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                side: const BorderSide(color: Color(0xFF94A3B8), width: 1.2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: value ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
