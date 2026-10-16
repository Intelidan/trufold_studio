import 'package:flutter/material.dart';
import '../../../../models/assembly_part.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Floating HUD for selecting weld joint geometry configurations (Butt, Lap, T-Joint, Corner).
/// Matches Section 4 decoupled UI specifications from welding_simulation_docs.md.
/// Supports dragging, minimizing to a compact chip, and closing.
class AssemblyWeldJointStyleToolbar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final Offset? position;
  final Function(DragUpdateDetails)? onDragUpdate;
  final VoidCallback? onToggleMinimize;
  final VoidCallback? onClose;
  final bool? isMinimized;

  const AssemblyWeldJointStyleToolbar({
    super.key,
    required this.viewModel,
    this.position,
    this.onDragUpdate,
    this.onToggleMinimize,
    this.onClose,
    this.isMinimized,
  });

  @override
  Widget build(BuildContext context) {
    if (viewModel.isCleanCanvasMode || !viewModel.showJointStyleToolbar) {
      return const SizedBox.shrink();
    }

    final minimized = isMinimized ?? viewModel.isJointToolbarMinimized;
    final top = position?.dy ?? 62.0;
    final left = position?.dx ?? 106.0;

    return Positioned(
      top: top,
      left: left,
      child: Material(
        color: Colors.transparent,
        child: minimized
            ? _buildMinimizedCard(context)
            : _buildExpandedCard(context),
      ),
    );
  }

  Widget _buildMinimizedCard(BuildContext context) {
    final activeStyleLabel = _getStyleLabel(viewModel.activeJointStyle);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: const [
          BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          const SizedBox(width: 4),
          const Icon(Icons.architecture, size: 14, color: Color(0xFF0076CE)),
          const SizedBox(width: 6),
          Text(
            activeStyleLabel,
            style: const TextStyle(
              color: Color(0xFF0076CE),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onToggleMinimize ?? viewModel.toggleJointToolbarMinimized,
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.unfold_more, size: 14, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onClose ?? viewModel.toggleJointStyleToolbar,
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 12, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDragHandle(),
              const SizedBox(width: 4),
              const Icon(Icons.architecture, size: 14, color: Color(0xFF0076CE)),
              const SizedBox(width: 6),
              const Text(
                'SELECT JOINT CONFIGURATION',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 14),
              InkWell(
                onTap: onToggleMinimize ?? viewModel.toggleJointToolbarMinimized,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(Icons.keyboard_arrow_up, size: 13, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: onClose ?? viewModel.toggleJointStyleToolbar,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(Icons.close, size: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: WeldJointStyle.values.map((style) {
              final isSelected = viewModel.activeJointStyle == style;
              final label = _getStyleLabel(style);
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  selectedColor: const Color(0xFFE0F2FE),
                  backgroundColor: const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  labelStyle: TextStyle(
                    color: isSelected ? const Color(0xFF0076CE) : const Color(0xFF475569),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF0076CE) : const Color(0xFFE2E8F0),
                    width: 1.0,
                  ),
                  onSelected: (val) {
                    if (val) viewModel.setJointStyle(style);
                  },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onDragUpdate,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 2.2, height: 2.2, decoration: const BoxDecoration(color: Color(0xFF94A3B8), shape: BoxShape.circle)),
                  const SizedBox(width: 2),
                  Container(width: 2.2, height: 2.2, decoration: const BoxDecoration(color: Color(0xFF94A3B8), shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 2.5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 2.2, height: 2.2, decoration: const BoxDecoration(color: Color(0xFF94A3B8), shape: BoxShape.circle)),
                  const SizedBox(width: 2),
                  Container(width: 2.2, height: 2.2, decoration: const BoxDecoration(color: Color(0xFF94A3B8), shape: BoxShape.circle)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStyleLabel(WeldJointStyle style) {
    switch (style) {
      case WeldJointStyle.buttJoint:
        return 'BUTT JOINT';
      case WeldJointStyle.lapJoint:
        return 'LAP JOINT';
      case WeldJointStyle.tJoint:
        return 'T-JOINT';
      case WeldJointStyle.cornerJoint:
        return 'CORNER JOINT';
    }
  }
}
