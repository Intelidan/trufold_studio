// Onshape-style Floating Sketch Dialog Card
// TruFold Assembly Studio - Phase 7 Onshape Transformation
// Matches Onshape's exact sketch dialog layout, light theme, green check / red X, and options

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/theme/assembly_studio_theme.dart';

/// Floating modal dialog for active 2D/3D Sketch operations matching Onshape CAD.
class AssemblyOnshapeSketchDialog extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback? onAccept;
  final VoidCallback? onCancel;

  const AssemblyOnshapeSketchDialog({super.key, required this.viewModel, this.onAccept, this.onCancel});

  @override
  State<AssemblyOnshapeSketchDialog> createState() => _AssemblyOnshapeSketchDialogState();
}

class _AssemblyOnshapeSketchDialogState extends State<AssemblyOnshapeSketchDialog> {
  bool _isCollapsed = false;
  bool _disableImprinting = false;
  bool _showErrors = true;
  bool _isFinalPreview = true;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final plane = vm.activeSketchPlane;
    final planeName = plane?.name ?? (vm.sketchPartId != null ? 'Face of ${vm.sketchPartId}' : 'Select Plane');

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Draggable Header with Editable Title, Collapse Toggle, and Green Check / Red X buttons (Item 5c)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(
                        top: const Radius.circular(5),
                        bottom: _isCollapsed ? const Radius.circular(5) : Radius.zero,
                      ),
                      border: _isCollapsed ? null : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.drag_indicator_rounded, size: 14, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_note_rounded, size: 16, color: AssemblyStudioTheme.onshapeBlue),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            plane != null && plane.name.isNotEmpty
                                ? plane.name
                                : 'Sketch ${vm.savedSketchPlanes.indexOf(plane ?? vm.datumPlaneXY) + 1 > 0 ? vm.savedSketchPlanes.indexOf(plane ?? vm.datumPlaneXY) + 1 : 1}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B), letterSpacing: 0.2),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Collapse / Expand Toggle Button (Item 5c)
                        Tooltip(
                          message: _isCollapsed ? 'Expand sketch panel' : 'Collapse sketch panel',
                          child: InkWell(
                            onTap: () => setState(() => _isCollapsed = !_isCollapsed),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(
                                _isCollapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                                size: 16,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Green Checkmark Accept Button
                        Tooltip(
                          message: 'Accept sketch (Enter)',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onAccept ?? () => vm.finishSketch(),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(color: AssemblyStudioTheme.onshapeGreen, shape: BoxShape.circle),
                              child: const Icon(Icons.check, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        // Red X Cancel Button
                        Tooltip(
                          message: 'Cancel sketch (Esc)',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onCancel ?? () => vm.exitSketchMode(),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(color: AssemblyStudioTheme.onshapeRed, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

              // 2. Body Options (Hidden when collapsed)
              if (!_isCollapsed)
                Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sketch Plane Selector Field
                  const Text(
                    'Sketch plane',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: plane != null ? AssemblyStudioTheme.onshapeBlue : const Color(0xFFCBD5E1), width: 1.0),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.layers_rounded, size: 13, color: AssemblyStudioTheme.onshapeBlue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            planeName,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (plane != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              vm.cancelActiveSketch();
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.close, size: 13, color: Color(0xFF64748B)),
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (vm.sketchPartId != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFBAE6FD), width: 1.0),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_rounded, size: 11, color: Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Direct Sketch: ${vm.sketchPartId}',
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFDE68A), width: 1.0),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded, size: 10, color: Color(0xFFD97706)),
                          SizedBox(width: 4),
                          Text(
                            '3D Movement Locked',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Select / Deactivate Tool + Polygon Bond Status Bar (Requirements #1 & #3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: vm.deactivateSketchToolToSelect,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: (vm.activeSketchTool == 'select_entity' && vm.activeConstraintTool == null)
                                    ? const Color(0xFFE0F2FE)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: (vm.activeSketchTool == 'select_entity' && vm.activeConstraintTool == null)
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.near_me_rounded,
                                    size: 11,
                                    color: (vm.activeSketchTool == 'select_entity' && vm.activeConstraintTool == null)
                                        ? const Color(0xFF0284C7)
                                        : const Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      (vm.activeSketchTool == 'select_entity' && vm.activeConstraintTool == null)
                                          ? 'Select Mode (Esc)'
                                          : 'End Tool (${vm.activeConstraintTool?.label ?? vm.activeSketchTool})',
                                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: (plane?.isLoopBonded ?? true)
                              ? 'Break Polygon Loop into Independent Segments'
                              : 'Rejoin & Bond Polygon Loop',
                          child: InkWell(
                            onTap: () {
                              if (plane?.isLoopBonded ?? true) {
                                vm.breakSelectedPolygonOrLoop();
                              } else {
                                vm.rejoinPolygonSegmentsOnActivePlane();
                              }
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: (plane?.isLoopBonded ?? true) ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: (plane?.isLoopBonded ?? true) ? const Color(0xFF0284C7) : const Color(0xFFF59E0B),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    (plane?.isLoopBonded ?? true) ? Icons.link_rounded : Icons.link_off_rounded,
                                    size: 11,
                                    color: (plane?.isLoopBonded ?? true) ? const Color(0xFF0284C7) : const Color(0xFFB45309),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    (plane?.isLoopBonded ?? true) ? 'Bonded' : 'Rejoin',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: (plane?.isLoopBonded ?? true) ? const Color(0xFF0284C7) : const Color(0xFFB45309),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Checkboxes: Disable imprinting, Show constraints, Show expressions, Show errors
                  _buildCheckboxRow(
                    label: 'Disable imprinting',
                    value: _disableImprinting,
                    onChanged: (val) => setState(() => _disableImprinting = val ?? false),
                  ),
                  _buildCheckboxRow(
                    label: 'Show constraints',
                    value: vm.showSketchConstraints,
                    onChanged: (val) {
                      vm.showSketchConstraints = val ?? true;
                      vm.notifyDocChanged();
                    },
                  ),
                  _buildCheckboxRow(
                    label: 'Show expressions',
                    value: vm.showSketchExpressions,
                    onChanged: (val) {
                      vm.showSketchExpressions = val ?? true;
                      vm.notifyDocChanged();
                    },
                  ),
                  _buildCheckboxRow(label: 'Show errors', value: _showErrors, onChanged: (val) => setState(() => _showErrors = val ?? true)),

                  const SizedBox(height: 8),

                  // Quick Normal To (N) Action & Help
                  Container(
                    padding: const EdgeInsets.only(top: 8),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1.0)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // View Normal To (N)
                          InkWell(
                            onTap: vm.alignCameraToActivePlaneNormal,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.center_focus_strong_rounded, size: 12, color: AssemblyStudioTheme.onshapeBlue),
                                  SizedBox(width: 4),
                                  Text(
                                    'Normal (N)',
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Final Preview Badge
                          InkWell(
                            onTap: () => setState(() => _isFinalPreview = !_isFinalPreview),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: _isFinalPreview ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: _isFinalPreview ? const Color(0xFF38BDF8) : const Color(0xFFCBD5E1)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.remove_red_eye_rounded,
                                    size: 11,
                                    color: _isFinalPreview ? AssemblyStudioTheme.onshapeBlue : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Final',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: _isFinalPreview ? AssemblyStudioTheme.onshapeBlue : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Help Icon
                          const Tooltip(
                            message: 'Onshape Sketch Documentation & Shortcuts',
                            child: Icon(Icons.help_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxRow({required String label, required bool value, required ValueChanged<bool?> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: AssemblyStudioTheme.onshapeBlue,
                checkColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF334155))),
          ],
        ),
      ),
    );
  }
}
