// =============================================================================
// cover_flange_dialog.dart
//
// Modal dialog allowing the user to select standard presets (8, 10, 12 Def, 15, 20, 25mm)
// or specify a custom downward flange depth for the trunking cover.
// =============================================================================

import 'package:flutter/material.dart';

import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

void showCoverFlangeDialog(BuildContext context, SheetMetalStudioViewModel viewModel) {
  double currentVal = viewModel.coverFlangeDepth;
  final controller = TextEditingController(text: currentVal.toStringAsFixed(0));
  final presets = [8.0, 10.0, 12.0, 15.0, 20.0, 25.0];

  showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            title: const Row(
              children: [
                Icon(Icons.straighten, size: 20, color: Color(0xFF0284C7)),
                SizedBox(width: 8),
                Text(
                  'Cover Flange Depth',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose or enter the downward flange height for the trunking cover.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Standard Presets:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: presets.map((p) {
                      final isSel = (currentVal - p).abs() < 0.5;
                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            currentVal = p;
                            controller.text = p.toStringAsFixed(0);
                          });
                          viewModel.setCoverFlangeDepth(p);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isSel ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
                          ),
                          child: Text(
                            '${p.toStringAsFixed(0)} mm${p == 12.0 ? ' (Def)' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                              color: isSel ? Colors.white : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Custom (mm):',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        height: 32,
                        child: TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onSubmitted: (txt) {
                            final val = double.tryParse(txt);
                            if (val != null && val >= 5.0 && val <= 100.0) {
                              setDialogState(() => currentVal = val);
                              viewModel.setCoverFlangeDepth(val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          final val = double.tryParse(controller.text);
                          if (val != null && val >= 5.0 && val <= 100.0) {
                            setDialogState(() => currentVal = val);
                            viewModel.setCoverFlangeDepth(val);
                          }
                        },
                        child: const Text('Apply', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    },
  );
}
