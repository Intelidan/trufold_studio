// =============================================================================
// cms_teach_scaling_overlay.dart
//
// Interactive Floating Control Overlay for Phase 2: Intelligent Template Scaling.
// Features:
// - Non-technical "Teach Scaling" UI per TRUFOLD_PHASE_1_2_TEMPLATE_SCALING_WORKFLOW.md
// - Interactive Morph Scrubber evaluating canonical 2D sheet and folding in real time
// - Visual "What Moves?" dynamic diagram explaining Stretch, Translate, Rigid, and Derived
// - Light CAD Studio styling with emerald confirmations and sky-blue live metrics
// =============================================================================

import 'package:flutter/material.dart';
import '../../../engine/cms/cms_scaling_controller.dart';
import '../../../models/cms/cms_product_contract.dart';
import '../../../models/cms/cms_scaling_model.dart';

class CmsTeachScalingOverlay extends StatelessWidget {
  final CmsScalingController controller;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const CmsTeachScalingOverlay({
    super.key,
    required this.controller,
    required this.onAccept,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final param = controller.activeParameter;
        if (param == null) return const SizedBox.shrink();

        final isLearned = param.isLearned;
        final previewVal = controller.previewMorphValue;
        final baselineVal = param.baselineValue;
        final delta = previewVal - baselineVal;

        return Card(
          elevation: 8.0,
          shadowColor: Colors.black.withValues(alpha: 0.15),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
            side: const BorderSide(color: Color(0xFFBAE6FD), width: 1.5),
          ),
          child: Container(
            width: 440.0,
            padding: const EdgeInsets.all(18.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune, size: 14.0, color: Color(0xFF0284C7)),
                          SizedBox(width: 5.0),
                          Text(
                            'TEACH TEMPLATE SCALING',
                            style: TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0284C7),
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                      decoration: BoxDecoration(
                        color: isLearned ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4.0),
                        border: Border.all(
                          color: isLearned ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        param.teachingState.displayName.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.0,
                          fontWeight: FontWeight.w700,
                          color: isLearned ? const Color(0xFF059669) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6.0),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18.0, color: Color(0xFF64748B)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onCancel,
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),

                // Subtitle
                const Text(
                  'Teach TruFold how the 2D sheet and 3D fitting behave when dimensions change.',
                  style: TextStyle(
                    fontSize: 12.0,
                    color: Color(0xFF475569),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8.0),

                // Active Profile Indicator Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.architecture, size: 13.0, color: Color(0xFF15803D)),
                      const SizedBox(width: 5.0),
                      Text(
                        'Profile: ${controller.effectiveScalingProfile == CmsScalingProfile.insideRiser ? "45° Inside Riser (Floor Web & Cheeks)" : controller.effectiveScalingProfile.displayName}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14.0),

                // Parameter Selector Tabs (e.g. Width vs Height)
                Row(
                  children: controller.model.parameters.values.map((p) {
                    final isSelected = p.id == controller.activeParameterId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text('${p.displayName} (${p.currentValue.toStringAsFixed(0)} mm)'),
                        selected: isSelected,
                        selectedColor: const Color(0xFFE0F2FE),
                        labelStyle: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF334155),
                        ),
                        onSelected: (_) => controller.selectParameter(p.id),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14.0),

                // Interactive Morph Scrubber
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Live Morph: ${param.displayName}',
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Text(
                            '${previewVal.toStringAsFixed(1)} mm  (${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)} mm)',
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6.0),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF0284C7),
                          inactiveTrackColor: const Color(0xFFCBD5E1),
                          thumbColor: const Color(0xFF0284C7),
                          overlayColor: const Color(0x290284C7),
                          trackHeight: 4.0,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                        ),
                        child: Slider(
                          value: previewVal.clamp(param.minValidMm, param.maxValidMm),
                          min: param.minValidMm,
                          max: param.maxValidMm,
                          divisions: ((param.maxValidMm - param.minValidMm) / 5.0).round(),
                          onChanged: (val) => controller.evaluateMorph(val),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Baseline: ${baselineVal.toStringAsFixed(0)} mm',
                            style: const TextStyle(fontSize: 10.0, color: Color(0xFF64748B)),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.restart_alt, size: 13.0),
                            label: const Text('Reset', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                            onPressed: () => controller.resetToBaseline(),
                          ),
                          Text(
                            'Max: ${param.maxValidMm.toStringAsFixed(0)} mm',
                            style: const TextStyle(fontSize: 10.0, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14.0),

                // Visual "What Moves?" Semantic Diagram
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.hub_outlined, size: 14.0, color: Color(0xFF15803D)),
                          SizedBox(width: 6.0),
                          Text(
                            'WHAT MOVES (CANONICAL BEHAVIOR)',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF15803D),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      _buildBehaviorRow(
                        behavior: CmsGeometryBehavior.stretch,
                        label: 'Floor Web',
                        detail: 'Expands canonical 2D region along bend axis',
                        color: const Color(0xFF0284C7),
                      ),
                      const SizedBox(height: 4.0),
                      _buildBehaviorRow(
                        behavior: CmsGeometryBehavior.translate,
                        label: 'Sidewalls & Flanges',
                        detail: 'Shift outward rigidly; flange width stays locked',
                        color: const Color(0xFFD97706),
                      ),
                      const SizedBox(height: 4.0),
                      _buildBehaviorRow(
                        behavior: CmsGeometryBehavior.rigid,
                        label: controller.model.rigidFeatureGroups.isNotEmpty
                            ? controller.model.rigidFeatureGroups.first.name
                            : 'Coupler Slots',
                        detail: 'Preserve slot shape and mounting edge offset',
                        color: const Color(0xFF7C3AED),
                      ),
                      const SizedBox(height: 4.0),
                      _buildBehaviorRow(
                        behavior: CmsGeometryBehavior.derived,
                        label: 'Physical Ports (${controller.model.derivedPorts.length})',
                        detail: '3D channel mouth recalculated from folded mesh',
                        color: const Color(0xFF059669),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                          padding: const EdgeInsets.symmetric(vertical: 10.0),
                        ),
                        icon: const Icon(Icons.check_circle, size: 17.0),
                        label: const Text(
                          'Accept Scaling Model',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                        ),
                        onPressed: onAccept,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
                      ),
                      icon: const Icon(Icons.restart_alt, size: 16.0),
                      label: const Text('Reset Dimensions', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      onPressed: () => controller.resetToBaseline(),
                    ),
                    const SizedBox(width: 8.0),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
                      ),
                      onPressed: onCancel,
                      child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBehaviorRow({
    required CmsGeometryBehavior behavior,
    required String label,
    required String detail,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Text(
            behavior.displayName,
            style: TextStyle(
              fontSize: 9.0,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8.0),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11.0, color: Color(0xFF1E293B)),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: detail, style: const TextStyle(color: Color(0xFF64748B))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
