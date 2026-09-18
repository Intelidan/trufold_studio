// =============================================================================
// cms_dxf_inspector_dialog.dart
//
// Crisp Light CAD Theme DXF Inspector dialog shown upon opening a DXF file
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 15, 17, 25).
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/cms/cms_product_contract.dart';

class CmsDxfInspectorDialog extends StatefulWidget {
  final String fileName;
  final ValueChanged<CmsProductContract> onStartAnalysis;
  final VoidCallback onOpenNormally;

  const CmsDxfInspectorDialog({
    super.key,
    required this.fileName,
    required this.onStartAnalysis,
    required this.onOpenNormally,
  });

  static Future<CmsProductContract?> show(
    BuildContext context, {
    required String fileName,
  }) {
    return showDialog<CmsProductContract>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CmsDxfInspectorDialog(
        fileName: fileName,
        onStartAnalysis: (contract) => Navigator.of(ctx).pop(contract),
        onOpenNormally: () => Navigator.of(ctx).pop(null),
      ),
    );
  }

  @override
  State<CmsDxfInspectorDialog> createState() => _CmsDxfInspectorDialogState();
}

class _CmsDxfInspectorDialogState extends State<CmsDxfInspectorDialog> {
  late CmsProductContract _selectedContract;

  final List<CmsProductContract> _availableContracts = const [
    CmsProductContract.bend45,
    CmsProductContract.bend90,
    CmsProductContract.equalTee,
    CmsProductContract.unequalTee,
    CmsProductContract.equalCross,
    CmsProductContract.straightTray,
  ];

  @override
  void initState() {
    super.initState();
    _selectedContract = _inferContractFromFileName(widget.fileName);
  }

  CmsProductContract _inferContractFromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('45') && (lower.contains('bend') || lower.contains('elbow'))) {
      return CmsProductContract.bend45;
    }
    if (lower.contains('90') && (lower.contains('bend') || lower.contains('elbow'))) {
      return CmsProductContract.bend90;
    }
    if (lower.contains('unequal') && lower.contains('tee')) {
      return CmsProductContract.unequalTee;
    }
    if (lower.contains('tee')) {
      return CmsProductContract.equalTee;
    }
    if (lower.contains('cross')) {
      return CmsProductContract.equalCross;
    }
    if (lower.contains('tray') || lower.contains('trunking')) {
      return CmsProductContract.straightTray;
    }
    return CmsProductContract.bend45;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 8.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
      ),
      child: Container(
        width: 500.0,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Color(0xFF0284C7), size: 22.0),
                ),
                const SizedBox(width: 14.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CMS PART INSPECTOR',
                        style: TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      const Text(
                        'Is this a CMS Part Drawing?',
                        style: TextStyle(
                          fontSize: 17.0,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            const Divider(height: 1.0, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 16.0),

            // File Information Card
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 18.0, color: Color(0xFF475569)),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),

            // Product Contract Selector
            const Text(
              'Detected Product Fitting:',
              style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 6.0),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<CmsProductContract>(
                  value: _selectedContract,
                  isExpanded: true,
                  items: _availableContracts.map((c) {
                    return DropdownMenuItem<CmsProductContract>(
                      value: c,
                      child: Text(
                        '${c.displayName} (${c.expectedPortCount} Ports, ${c.expectedStructuralBends} Bends)',
                        style: const TextStyle(fontSize: 13.0, color: Color(0xFF0F172A)),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedContract = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20.0),

            // Explanatory note
            const Text(
              'TruFold will automatically fold the 3D model, discover channel openings, and lock rigid coupler fastener slots.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 20.0),

            // Actions Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onOpenNormally,
                  child: const Text('Open Normally (General CAD)', style: TextStyle(color: Color(0xFF64748B))),
                ),
                const SizedBox(width: 10.0),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18.0),
                  label: const Text('Start Automatic 3D Analysis', style: TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: () => widget.onStartAnalysis(_selectedContract),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
