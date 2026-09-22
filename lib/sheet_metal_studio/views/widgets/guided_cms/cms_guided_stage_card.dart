// =============================================================================
// cms_guided_stage_card.dart
//
// Floating, light-themed engineering status card displaying active stage,
// progress, and verification metrics per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md
// (Sections 14, 15, 25).
// =============================================================================

import 'package:flutter/material.dart';

import '../../../models/cms/cms_ux_state.dart';
import '../../../engine/cms/cms_guided_ux_controller.dart';
import '../branding/trufold_3d_icon.dart';

class CmsGuidedStageCard extends StatelessWidget {
  final CmsGuidedUxController controller;
  final VoidCallback? onStartAnalysis;
  final VoidCallback? onContinueToPortMapping;
  final VoidCallback? onUseSuggestedBends;
  final VoidCallback? onEditBendsManually;
  final VoidCallback? onFinalizeTemplate;
  final VoidCallback? onStartTeachScaling;
  final VoidCallback? onIdentifyCouplers;
  final VoidCallback? onDismiss;

  const CmsGuidedStageCard({
    super.key,
    required this.controller,
    this.onStartAnalysis,
    this.onContinueToPortMapping,
    this.onUseSuggestedBends,
    this.onEditBendsManually,
    this.onFinalizeTemplate,
    this.onStartTeachScaling,
    this.onIdentifyCouplers,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        if (state.phase == CmsUxPhase.idle) return const SizedBox.shrink();

        final isComplete = state.phase == CmsUxPhase.complete;
        final isError = state.phase == CmsUxPhase.error;
        final isAmbiguity = state.phase == CmsUxPhase.ambiguityRequired;

        Color accentColor = const Color(0xFF0284C7); // Sky blue
        if (isComplete) accentColor = const Color(0xFF059669); // Emerald green
        if (isAmbiguity) accentColor = const Color(0xFFD97706); // Amber
        if (isError) accentColor = const Color(0xFFDC2626); // Crimson

        return Card(
          elevation: 6.0,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: BorderSide(color: accentColor.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Container(
            width: 400.0,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6.0)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isComplete ? Icons.check_circle : (isAmbiguity ? Icons.help_outline : Icons.auto_awesome), size: 14.0, color: accentColor),
                          const SizedBox(width: 4.0),
                          Text(
                            _phaseLabel(state.phase),
                            style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w700, color: accentColor, letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (onDismiss != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18.0, color: Color(0xFF64748B)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onDismiss,
                      ),
                  ],
                ),
                const SizedBox(height: 10.0),

                // Stage Title & 3D Animated Indicator Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Stage Title
                          Text(
                            state.stageTitle,
                            style: const TextStyle(
                              fontSize: 15.0,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A), // Dark slate
                            ),
                          ),
                          const SizedBox(height: 4.0),

                          // Subtitle
                          Text(state.stageSubtitle, style: const TextStyle(fontSize: 12.0, color: Color(0xFF475569), height: 1.3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    // True 3D Folding Indicator
                    TruFold3DIcon(
                      size: 38.0,
                      isAnimated: !isComplete && state.phase != CmsUxPhase.idle,
                      fixedFoldAngleDeg: isComplete ? 65.0 : (state.phase == CmsUxPhase.idle ? 0.0 : null),
                      sheetThickness: 2.2,
                      tColor: const Color(0xFF0284C7),
                      fColor: const Color(0xFF334155),
                      accentColor: accentColor,
                    ),
                  ],
                ),
                const SizedBox(height: 12.0),

                // Progress Indicator
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 6.0,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
                const SizedBox(height: 12.0),

                // Stage Action Row: Stage 1 Start
                if (state.phase == CmsUxPhase.productSelected && onStartAnalysis != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18.0),
                      label: const Text('Start Automatic Analysis', style: TextStyle(fontWeight: FontWeight.w600)),
                      onPressed: onStartAnalysis,
                    ),
                  ),

                // Stage Action Row: Stage 1 Empty Suggestions (Awaiting manual marking)
                if (state.phase == CmsUxPhase.suggestingBends && state.suggestedBends.isEmpty)
                  Row(
                    children: [
                      if (onEditBendsManually != null)
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              padding: const EdgeInsets.symmetric(vertical: 10.0),
                            ),
                            icon: const Icon(Icons.edit, size: 18.0),
                            label: const Text('Mark Bends on Canvas (B)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0)),
                            onPressed: onEditBendsManually,
                          ),
                        ),
                    ],
                  ),

                // Stage Action Row: Stage 1 Suggestions from Template
                if (state.phase == CmsUxPhase.suggestingBends && state.suggestedBends.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            padding: const EdgeInsets.symmetric(vertical: 10.0),
                          ),
                          icon: const Icon(Icons.check_circle_outline, size: 18.0),
                          label: const Text('Use Suggested Bends', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0)),
                          onPressed: onUseSuggestedBends,
                        ),
                      ),
                      if (onEditBendsManually != null) ...[
                        const SizedBox(width: 8.0),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
                          ),
                          icon: const Icon(Icons.edit, size: 16.0),
                          label: const Text('Mark Manually (B)', style: TextStyle(fontSize: 12.0)),
                          onPressed: onEditBendsManually,
                        ),
                      ],
                    ],
                  ),

                // Stage Action Row: Stage 1 Bends Defined -> Proceed to Stage 2 Port Mapping
                if (state.phase == CmsUxPhase.confirmingBends)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                padding: const EdgeInsets.symmetric(vertical: 10.0),
                              ),
                              icon: const Icon(Icons.hub_outlined, size: 18.0),
                              label: const Text('Auto-Map Ports (Stage 2) →', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.0)),
                              onPressed: onContinueToPortMapping ?? onStartAnalysis,
                            ),
                          ),
                          if (onEditBendsManually != null) ...[
                            const SizedBox(width: 8.0),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF475569),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
                              ),
                              icon: const Icon(Icons.edit, size: 16.0),
                              label: const Text('Edit Bends (B)', style: TextStyle(fontSize: 12.0)),
                              onPressed: onEditBendsManually,
                            ),
                          ],
                        ],
                      ),
                      if (onIdentifyCouplers != null) ...[
                        const SizedBox(height: 8.0),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              side: const BorderSide(color: Color(0xFF93C5FD)),
                              backgroundColor: const Color(0xFFEFF6FF),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                            ),
                            icon: const Icon(Icons.handshake_outlined, size: 16.0),
                            label: const Text('Identify Couplers', style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600)),
                            onPressed: onIdentifyCouplers,
                          ),
                        ),
                      ],
                    ],
                  ),

                // Stage Action Row: Stage 2 Complete -> Finalize & Teach Scaling (Stage 3)
                if (state.phase == CmsUxPhase.complete)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (onFinalizeTemplate != null)
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF059669),
                                  side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                                ),
                                icon: const Icon(Icons.check, size: 16.0),
                                label: const Text('Finalize & Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0)),
                                onPressed: onFinalizeTemplate,
                              ),
                            ),
                          if (onStartTeachScaling != null) ...[
                            const SizedBox(width: 8.0),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                                ),
                                icon: const Icon(Icons.tune, size: 16.0),
                                label: const Text('Template Scaling →', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0)),
                                onPressed: onStartTeachScaling,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (onIdentifyCouplers != null) ...[
                        const SizedBox(height: 6.0),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.handshake_outlined, size: 14.0),
                            label: const Text('Review / Identify Couplers', style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600)),
                            onPressed: onIdentifyCouplers,
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _phaseLabel(CmsUxPhase phase) {
    switch (phase) {
      case CmsUxPhase.idle:
        return 'IDLE';
      case CmsUxPhase.productSelected:
        return 'STAGE 1: PRODUCT INTENT';
      case CmsUxPhase.analyzingFlatGeometry:
        return 'STAGE 1: CHECKING GEOMETRY';
      case CmsUxPhase.suggestingBends:
        return 'STAGE 1: DEFINE BENDS';
      case CmsUxPhase.confirmingBends:
        return 'STAGE 1: BENDS DEFINED';
      case CmsUxPhase.folding:
        return 'STAGE 2: 3D KINEMATICS';
      case CmsUxPhase.detectingOpenings:
        return 'STAGE 2: 3D OPENINGS';
      case CmsUxPhase.matchingPorts:
        return 'STAGE 2: PORT MATCHING';
      case CmsUxPhase.classifyingCouplers:
        return 'STAGE 2: FASTENERS';
      case CmsUxPhase.buildingConstraints:
        return 'STAGE 2: SMART SCALING';
      case CmsUxPhase.complete:
        return 'STAGE 2: PORTS VERIFIED';
      case CmsUxPhase.ambiguityRequired:
        return 'RESOLUTION NEEDED';
      case CmsUxPhase.error:
        return 'ERROR';
    }
  }
}
