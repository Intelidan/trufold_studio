// =============================================================================
// cms_live_learned_card.dart
//
// Live, progressive narrative card displaying verified CAD features and invariants
// ("What TruFold Learned") per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md
// (Sections 14, 15, 20, 25).
// =============================================================================

import 'package:flutter/material.dart';
import '../../../engine/cms/cms_guided_ux_controller.dart';

class CmsLiveLearnedCard extends StatefulWidget {
  final CmsGuidedUxController controller;

  const CmsLiveLearnedCard({
    super.key,
    required this.controller,
  });

  @override
  State<CmsLiveLearnedCard> createState() => _CmsLiveLearnedCardState();
}

class _CmsLiveLearnedCardState extends State<CmsLiveLearnedCard> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final milestones = widget.controller.milestones;
        if (milestones.isEmpty) return const SizedBox.shrink();

        return Card(
          elevation: 5.0,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
          ),
          child: Container(
            width: 380.0,

            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card Header with toggle
                InkWell(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  borderRadius: BorderRadius.circular(6.0),
                  child: Row(
                    children: [
                      const Icon(Icons.school_outlined, size: 18.0, color: Color(0xFF0F172A)),
                      const SizedBox(width: 8.0),
                      const Text(
                        'What TruFold Learned',
                        style: TextStyle(
                          fontSize: 13.0,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        child: Text(
                          '${milestones.length}',
                          style: const TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18.0,
                        color: const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),

                // Milestones list
                if (_isExpanded) ...[
                  const SizedBox(height: 10.0),
                  const Divider(height: 1.0, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 8.0),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220.0),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: milestones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8.0),
                      itemBuilder: (context, index) {

                        final m = milestones[index];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2.0),
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 14.0,
                                color: Color(0xFF10B981), // Green
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.title,
                                    style: const TextStyle(
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  Text(
                                    m.detail,
                                    style: const TextStyle(
                                      fontSize: 11.0,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
