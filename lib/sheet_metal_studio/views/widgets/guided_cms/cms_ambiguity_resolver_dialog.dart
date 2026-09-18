// =============================================================================
// cms_ambiguity_resolver_dialog.dart
//
// Exception-handling visual candidate picker for resolving geometric ambiguities
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 14, 25).
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/cms/cms_physical_port.dart';
import '../../../models/cms/cms_product_contract.dart';
import '../../../models/cms/cms_ux_state.dart';

class CmsAmbiguityResolverDialog extends StatefulWidget {
  final CmsProductContract contract;
  final List<CmsPortCandidate> candidateOpenings;
  final ValueChanged<List<CmsPhysicalPort>> onResolved;
  final VoidCallback onCancel;

  const CmsAmbiguityResolverDialog({
    super.key,
    required this.contract,
    required this.candidateOpenings,
    required this.onResolved,
    required this.onCancel,
  });

  @override
  State<CmsAmbiguityResolverDialog> createState() => _CmsAmbiguityResolverDialogState();
}

class _CmsAmbiguityResolverDialogState extends State<CmsAmbiguityResolverDialog> {
  late final Map<int, String?> _portAssignments; // portIndex (1..N) -> candidateId

  @override
  void initState() {
    super.initState();
    _portAssignments = {};
    for (int i = 1; i <= widget.contract.expectedPortCount; i++) {
      _portAssignments[i] = i <= widget.candidateOpenings.length
          ? widget.candidateOpenings[i - 1].candidateId
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
      ),
      child: Container(
        width: 520.0,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Warning Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7), // Amber
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22.0),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Port Ambiguity Resolution',
                        style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Expected ${widget.contract.expectedPortCount} ports for ${widget.contract.displayName}, '
                        'but discovered ${widget.candidateOpenings.length} candidates.',
                        style: const TextStyle(fontSize: 12.0, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18.0),
            const Divider(height: 1.0, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 16.0),

            // Port Assignment Selectors
            ...List.generate(widget.contract.expectedPortCount, (idx) {
              final portIndex = idx + 1;
              final assignedCandidateId = _portAssignments[portIndex];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4.0),
                        ),

                        child: Text(
                          'PORT $portIndex',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.0, color: Color(0xFF0284C7)),
                        ),
                      ),
                      const SizedBox(width: 14.0),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: assignedCandidateId,
                            hint: const Text('Select candidate opening...', style: TextStyle(fontSize: 13.0)),
                            isExpanded: true,
                            items: widget.candidateOpenings.map((cand) {
                              return DropdownMenuItem<String>(
                                value: cand.candidateId,
                                child: Text(
                                  '${cand.candidateId} (${cand.width.toStringAsFixed(1)} × ${cand.height.toStringAsFixed(1)} mm)',
                                  style: const TextStyle(fontSize: 13.0, color: Color(0xFF1E293B)),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _portAssignments[portIndex] = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 16.0),

            // Actions Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                const SizedBox(width: 10.0),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  ),
                  onPressed: _canSubmit() ? _submitResolution : null,
                  child: const Text('Confirm Assignments'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _canSubmit() {
    for (int i = 1; i <= widget.contract.expectedPortCount; i++) {
      if (_portAssignments[i] == null) return false;
    }
    return true;
  }

  void _submitResolution() {
    final resolved = <CmsPhysicalPort>[];
    for (int i = 1; i <= widget.contract.expectedPortCount; i++) {
      final candId = _portAssignments[i];
      final cand = widget.candidateOpenings.firstWhere((c) => c.candidateId == candId);

      resolved.add(CmsPhysicalPort(
        id: 'PORT_$i',
        index: i,
        width: cand.width,
        height: cand.height,
        center: cand.center,
        normal: cand.normal,
        confidence: 1.0,
        detectionSource: PortDetectionSource.userConfirmed,
      ));
    }
    widget.onResolved(resolved);
  }
}
