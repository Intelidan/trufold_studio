import 'package:flutter/material.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';
import 'assembly_construction_plane_dialog.dart';

/// Floating top banner that appears when entering "Create Sketch" / Plane Selection Mode.
/// Guides the user to pick a plane or face, with quick-pick datum buttons.
class AssemblyPlaneSelectionBanner extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblyPlaneSelectionBanner({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    if (!viewModel.isPlaneSelectionMode) return const SizedBox.shrink();

    return Positioned(
      top: 56,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 860),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF0076CE),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon + Mode Title
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEBF5FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.layers_rounded,
                      size: 16,
                      color: Color(0xFF0076CE),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'CREATE SKETCH',
                            style: TextStyle(
                              color: Color(0xFF0076CE),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(width: 6),
                          Text(
                            '• Select plane or face',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        viewModel.hoveredPlaneId != null
                            ? 'Target: ${_formatPlaneTarget(viewModel.hoveredPlaneId!)} (Click to select)'
                            : 'Click any 3D datum plane, construction plane, or solid face',
                        style: TextStyle(
                          color: viewModel.hoveredPlaneId != null ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                          fontSize: 10,
                          fontWeight: viewModel.hoveredPlaneId != null ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Container(width: 1, height: 26, color: const Color(0xFFE2E8F0)),
                  const SizedBox(width: 12),

                  // Quick Select Datum Buttons
                  _QuickPlaneButton(
                    label: 'XY Top',
                    color: const Color(0xFF0076CE),
                    onTap: () => viewModel.selectPlaneForSketch(viewModel.datumPlaneXY),
                  ),
                  const SizedBox(width: 6),
                  _QuickPlaneButton(
                    label: 'XZ Front',
                    color: const Color(0xFF059669),
                    onTap: () => viewModel.selectPlaneForSketch(viewModel.datumPlaneXZ),
                  ),
                  const SizedBox(width: 6),
                  _QuickPlaneButton(
                    label: 'YZ Right',
                    color: const Color(0xFFD97706),
                    onTap: () => viewModel.selectPlaneForSketch(viewModel.datumPlaneYZ),
                  ),
                  const SizedBox(width: 8),

                  // Create Offset Construction Plane button
                  OutlinedButton.icon(
                    onPressed: () => _openConstructionPlaneDialog(context),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      backgroundColor: const Color(0xFFF8FAFC),
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 13, color: Color(0xFF475569)),
                    label: const Text(
                      '+ Construction Plane',
                      style: TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Cancel button
                  IconButton(
                    tooltip: 'Cancel (ESC)',
                    icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                    onPressed: viewModel.exitPlaneSelectionMode,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openConstructionPlaneDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AssemblyConstructionPlaneDialog(viewModel: viewModel),
    );
  }

  String _formatPlaneTarget(String id) {
    if (id == 'datum_XY') return 'XY Top Plane';
    if (id == 'datum_XZ') return 'XZ Front Plane';
    if (id == 'datum_YZ') return 'YZ Right Plane';
    if (id.startsWith('face:')) {
      final p = id.split(':');
      return 'Solid Face (${p.length >= 3 ? p[2] : id})';
    }
    return id;
  }
}

class _QuickPlaneButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickPlaneButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
