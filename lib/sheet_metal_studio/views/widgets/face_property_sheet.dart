// =============================================================================
// face_property_sheet.dart
//
// Floating On-Canvas Property Inspector for selected Planar Sheet Faces.
// Allows rapid inspection of:
// - Semantic Role (Base Floor, Side Wall, Return Flange, Mounting Tab, Cover Panel)
// - Surface Area (mm²)
// - Base Anchor status & toggle
// - Auto-Nest Perforation Pattern button
// - Feature Suppression / Temporary Delete (Hides in 2D and omits from 3D fold mesh)
// - Dimension label toggle
// =============================================================================

import 'package:flutter/material.dart';

import '../../models/planar_sheet_face.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class FacePropertySheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final PlanarSheetFace face;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const FacePropertySheet({
    super.key,
    required this.viewModel,
    required this.face,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF0284C7); // Sky blue for planar faces

    return Container(
      width: 260.0,
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: face.isVisible
              ? themeColor.withValues(alpha: 0.6)
              : const Color(0xFF94A3B8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          GestureDetector(
            onPanStart: onDragStartHeader,
            onPanUpdate: onDragHeader,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: face.isVisible
                        ? themeColor
                        : const Color(0xFF94A3B8),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${face.id}: ${_formatRole(face.role)}',
                    style: TextStyle(
                      color: face.isVisible
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      decoration: face.isVisible
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Quick Suppress / Visibility Icon
                IconButton(
                  icon: Icon(
                    face.isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 16,
                    color: face.isVisible
                        ? const Color(0xFF0284C7)
                        : const Color(0xFF94A3B8),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 22,
                    minHeight: 22,
                  ),
                  onPressed: () => viewModel.toggleFaceVisibility(face.id),
                  tooltip: face.isVisible
                      ? 'Hide / Suppress Part (Temp Delete)'
                      : 'Show / Unsuppress Part',
                ),
                if (onToggleCollapse != null) ...[
                  InkWell(
                    onTap: onToggleCollapse,
                    child: Icon(
                      isCollapsed
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 18,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
                InkWell(
                  onTap: onClose ?? () => viewModel.selectFace(null),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),

          if (!isCollapsed) ...[
            const Divider(height: 12.0, color: Color(0xFFE2E8F0)),

            // 2. Metrics (Area & Anchor)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Surface Area:',
                  style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
                Text(
                  '${face.areaMm2.toStringAsFixed(1)} mm²',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Base Anchor (Z=0):',
                  style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
                face.isBaseAnchor
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFF0284C7)),
                        ),
                        child: const Text(
                          'ANCHOR',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      )
                    : TextButton(
                        onPressed: () => viewModel.setBaseAnchorFace(face.id),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text(
                          'Set as Anchor',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ),
              ],
            ),

            const SizedBox(height: 8),

            // 3. Auto-Nest Perforation on this Surface Action
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.grid_view, size: 13),
                label: const Text(
                  'Auto-Nest Perforation on this Surface',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: () {
                  viewModel.selectFace(face.id);
                  viewModel.setToolMode(StudioToolMode.perforationPattern);
                },
              ),
            ),

            const SizedBox(height: 8),

            // 4. Suppression / Active Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Part Active / Visible (3D & 2D):',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: face.isVisible,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeThumbColor: const Color(0xFF0284C7),
                  onChanged: (_) => viewModel.toggleFaceVisibility(face.id),
                ),
              ],
            ),

            // 5. Dimension Tag Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Dimension Tag:',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    face.showLabel ? Icons.visibility : Icons.visibility_off,
                    size: 16,
                    color: face.showLabel ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  splashRadius: 14,
                  tooltip: face.showLabel ? 'Hide Dimension Tag' : 'Show Dimension Tag',
                  onPressed: () => viewModel.toggleFaceLabel(face.id),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _formatRole(FaceRole role) {
    switch (role) {
      case FaceRole.baseFloor:
        return 'Base Floor (Anchor)';
      case FaceRole.sideWall:
        return 'Side Wall';
      case FaceRole.returnFlange:
        return 'Return Flange';
      case FaceRole.mountingTab:
        return 'Mounting Tab';
      case FaceRole.coverPanel:
        return 'Cover Panel';
      case FaceRole.custom:
        return 'Planar Surface';
    }
  }
}
