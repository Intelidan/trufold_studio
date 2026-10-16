import 'package:flutter/material.dart';
import '../../../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Interactive HUD rendering post-stroke weld quality metrics and fault anomaly marks sidebar.
/// Matches Section 4 decoupled UI specifications from welding_simulation_docs.md.
/// Positioned non-overlapping on the right side and elevated bottom, supporting minimize & dismiss.
class AssemblyWeldQualityHUD extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final void Function(CadPoint3D position)? onAnomalyTap;
  final VoidCallback? onInspectSeam;
  final VoidCallback? onResetCam;
  final VoidCallback? onDismiss;
  final VoidCallback? onToggleCardMinimize;
  final VoidCallback? onToggleSidebarMinimize;
  final bool? isCardMinimized;
  final bool? isSidebarMinimized;

  const AssemblyWeldQualityHUD({
    super.key,
    required this.viewModel,
    this.onAnomalyTap,
    this.onInspectSeam,
    this.onResetCam,
    this.onDismiss,
    this.onToggleCardMinimize,
    this.onToggleSidebarMinimize,
    this.isCardMinimized,
    this.isSidebarMinimized,
  });

  @override
  Widget build(BuildContext context) {
    if (viewModel.isCleanCanvasMode || !viewModel.showQualityHud) {
      return const SizedBox.shrink();
    }

    final eval = viewModel.latestWeldEvaluation;
    if (eval == null) return const SizedBox.shrink();

    final defects = eval.anomalies;
    final isPassing = eval.overallScore >= 75.0;
    final cardMinimized = isCardMinimized ?? viewModel.isQualityCardMinimized;
    final sidebarMinimized = isSidebarMinimized ?? viewModel.isAnomalySidebarMinimized;

    return Stack(
      children: [
        // -------------------------------------------------------------
        // 1. Interactive Fault Anomaly Marks Sidebar (Right Side - No Overlap)
        // -------------------------------------------------------------
        if (defects.isNotEmpty)
          sidebarMinimized
              ? _buildMinimizedAnomalyPill(context, defects.length)
              : _buildExpandedAnomalySidebar(context, defects),

        // -------------------------------------------------------------
        // 2. Core Scoring Evaluation Card Panel (Elevated Bottom Left - Clear of VCB)
        // -------------------------------------------------------------
        cardMinimized
            ? _buildMinimizedQualityPill(context, eval, isPassing)
            : _buildExpandedQualityCard(context, eval, isPassing),
      ],
    );
  }

  Widget _buildMinimizedAnomalyPill(BuildContext context, int count) {
    return Positioned(
      top: 110,
      right: 18,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggleSidebarMinimize ?? viewModel.toggleAnomalySidebarMinimized,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF7F1D1D).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
              boxShadow: const [
                BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 14),
                const SizedBox(width: 6),
                Text(
                  'FAULT ANOMALIES ($count)',
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_left, size: 14, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedAnomalySidebar(BuildContext context, List<dynamic> defects) {
    return Positioned(
      top: 110,
      right: 18,
      width: 280,
      bottom: 130,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
            boxShadow: const [
              BoxShadow(color: Color(0x18000000), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'FAULT ANOMALY MARKS (${defects.length})',
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Text('AWS D1.1', style: TextStyle(color: Color(0xFFB91C1C), fontSize: 8.5, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: onToggleSidebarMinimize ?? viewModel.toggleAnomalySidebarMinimized,
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Icon(Icons.keyboard_arrow_right, size: 14, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(6),
                  itemCount: defects.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 5),
                  itemBuilder: (context, index) {
                    final anomaly = defects[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => onAnomalyTap?.call(anomaly.position),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.center_focus_strong, color: Color(0xFFEF4444), size: 13),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${index + 1}. ${anomaly.description}',
                                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 10.5, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'X: ${anomaly.position.x.toInt()}  Y: ${anomaly.position.y.toInt()}  Z: ${anomaly.position.z.toInt()}mm',
                                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 13),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimizedQualityPill(BuildContext context, dynamic eval, bool isPassing) {
    return Positioned(
      bottom: 76,
      right: 18,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isPassing ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPassing ? Icons.verified : Icons.warning,
                size: 14,
                color: isPassing ? const Color(0xFF059669) : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 6),
              Text(
                'QUALITY METRIC GRADE: ${eval.overallScore.toStringAsFixed(1)}% (${eval.letterGrade})',
                style: TextStyle(
                  color: isPassing ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onToggleCardMinimize ?? viewModel.toggleQualityCardMinimized,
                borderRadius: BorderRadius.circular(3),
                child: const Icon(Icons.keyboard_arrow_up, size: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(3),
                child: const Icon(Icons.close, size: 13, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedQualityCard(BuildContext context, dynamic eval, bool isPassing) {
    return Positioned(
      bottom: 76,
      right: 18,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isPassing ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x18000000), blurRadius: 16, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPassing ? Icons.verified : Icons.warning,
                            size: 15,
                            color: isPassing ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'QUALITY METRIC GRADE: ${eval.overallScore.toStringAsFixed(1)}%',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isPassing ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: onToggleCardMinimize ?? viewModel.toggleQualityCardMinimized,
                          borderRadius: BorderRadius.circular(3),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Icon(Icons.keyboard_arrow_down, size: 14, color: Color(0xFF64748B)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: onDismiss,
                          borderRadius: BorderRadius.circular(3),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPassing ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isPassing ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                      ),
                      child: Text(
                        'Speed: ${eval.speedConsistency.toInt()}% | Uniformity: ${eval.profileUniformity.toInt()}%',
                        style: TextStyle(
                          color: isPassing ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onInspectSeam != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFE0F2FE),
                          foregroundColor: const Color(0xFF0076CE),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: onInspectSeam,
                        icon: const Icon(Icons.zoom_in, size: 13, color: Color(0xFF0076CE)),
                        label: const Text('INSPECT SEAM', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ),
                    if (onResetCam != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFF1F5F9),
                          foregroundColor: const Color(0xFF475569),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: onResetCam,
                        icon: const Icon(Icons.videocam_off, size: 13, color: Color(0xFF64748B)),
                        label: const Text('RESET CAM', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  eval.gradeFeedback,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
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
