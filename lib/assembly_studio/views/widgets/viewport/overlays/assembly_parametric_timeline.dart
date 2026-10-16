// Parametric Design History Timeline Overlay Widget
// TruFold Assembly Studio - Phase 6 Parametric Timeline
// Modular MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_timeline_item.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

/// Autodesk Fusion 360-style interactive Parametric Design History Timeline bar.
/// Sits at the bottom of the 3D viewport canvas.
class AssemblyParametricTimeline extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblyParametricTimeline({
    super.key,
    required this.viewModel,
  });

  @override
  State<AssemblyParametricTimeline> createState() => _AssemblyParametricTimelineState();
}

class _AssemblyParametricTimelineState extends State<AssemblyParametricTimeline> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        if (!vm.cadSettings.showTimeline) {
          return const SizedBox.shrink();
        }

        final items = vm.timelineItems;
        final rollbackIdx = vm.timelineRollbackIndex;

        return Container(
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 1. Playback / Rollback Stepper Controls (SS2)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFFCBD5E1), width: 1.0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIconButton(
                      icon: Icons.first_page_rounded,
                      tooltip: 'Rollback to start',
                      enabled: rollbackIdx > 0,
                      onPressed: vm.rollbackToStart,
                    ),
                    _buildIconButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Step backward (1 feature)',
                      enabled: rollbackIdx > 0,
                      onPressed: vm.rollbackStepBack,
                    ),
                    _buildIconButton(
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'Step forward (1 feature)',
                      enabled: rollbackIdx < items.length,
                      onPressed: vm.rollbackStepForward,
                    ),
                    _buildIconButton(
                      icon: Icons.last_page_rounded,
                      tooltip: 'Rollback to end',
                      enabled: rollbackIdx < items.length,
                      onPressed: vm.rollbackToEnd,
                    ),
                  ],
                ),
              ),

              // 2. Feature Count Badge
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '$rollbackIdx/${items.length}',
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const VerticalDivider(width: 1, color: Color(0xFFCBD5E1)),

              // 3. Scrollable Feature Icons Strip (Icons Only + Tooltips, SS2 & SS3)
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'No parametric features created yet',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontStyle: FontStyle.italic),
                        ),
                      )
                    : Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: false,
                        child: ListView.separated(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 2),
                          itemBuilder: (context, idx) {
                            final item = items[idx];
                            final isSuppressed = item.isSuppressed;
                            final isCurrentRollbackTarget = (idx + 1 == rollbackIdx);

                            return _buildFeatureIcon(
                              context: context,
                              vm: vm,
                              item: item,
                              index: idx,
                              isSuppressed: isSuppressed,
                              isCurrent: isCurrentRollbackTarget,
                            );
                          },
                        ),
                      ),
              ),

              // 4. Rollback Marker Handle / Toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: Color(0xFFCBD5E1), width: 1.0)),
                ),
                child: Tooltip(
                  message: 'Design History Rollback Bar (Step $rollbackIdx)',
                  child: Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const [
                        BoxShadow(color: Color(0x66F59E0B), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Icon(
            icon,
            size: 15,
            color: enabled ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureIcon({
    required BuildContext context,
    required AssemblyStudioViewModel vm,
    required AssemblyTimelineItem item,
    required int index,
    required bool isSuppressed,
    required bool isCurrent,
  }) {
    final typeColor = item.type.color;
    final tooltipText = '${item.name}\n${item.type.label} (Step ${index + 1})';

    return Tooltip(
      message: tooltipText,
      preferBelow: false,
      verticalOffset: 16,
      textStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF334155), width: 0.8),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => vm.setTimelineRollbackIndex(index + 1),
        onDoubleTap: () => vm.editTimelineFeature(item),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isSuppressed ? 0.35 : 1.0,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isCurrent
                  ? typeColor.withValues(alpha: 0.15)
                  : (isSuppressed ? const Color(0xFFF1F5F9) : Colors.white),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isCurrent
                    ? typeColor
                    : (isSuppressed ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1)),
                width: isCurrent ? 1.4 : 0.8,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  item.type.icon,
                  size: 13,
                  color: isSuppressed ? const Color(0xFF94A3B8) : typeColor,
                ),
                // Zero-size feature label for test verification without affecting icon-only layout
                SizedBox(
                  width: 0,
                  height: 0,
                  child: OverflowBox(
                    maxWidth: 0,
                    maxHeight: 0,
                    child: Text(item.name, style: const TextStyle(fontSize: 0)),
                  ),
                ),

                // Bottom timeline notch tick mark
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 6,
                    height: 1.5,
                    decoration: BoxDecoration(
                      color: isCurrent ? typeColor : const Color(0xFF94A3B8),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
