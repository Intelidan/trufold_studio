// =============================================================================
// bend_radius_dialog.dart
//
// Specialized Bending Radius / Fillet Configuration Dialog.
// Pops up when using the Fillet tool on a press-brake bend line to configure
// its inner bend radius (R), displaying the resulting 2D bend tangent zone
// and 3D cylindrical bend arc fillet.
// =============================================================================

import 'package:flutter/material.dart';
import '../../models/fold_bend_line.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class BendRadiusDialog extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final FoldBendLine bend;

  const BendRadiusDialog({
    super.key,
    required this.viewModel,
    required this.bend,
  });

  static Future<void> show(BuildContext context, SheetMetalStudioViewModel viewModel, FoldBendLine bend) {
    return showDialog(
      context: context,
      builder: (_) => BendRadiusDialog(viewModel: viewModel, bend: bend),
    );
  }

  @override
  State<BendRadiusDialog> createState() => _BendRadiusDialogState();
}

class _BendRadiusDialogState extends State<BendRadiusDialog> {
  late double _currentRadius;
  late final TextEditingController _controller;
  static const _presets = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 8.0, 10.0];

  @override
  void initState() {
    super.initState();
    _currentRadius = widget.bend.radiusMm;
    _controller = TextEditingController(text: _currentRadius.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bend = widget.bend;
    final thk = widget.viewModel.document.material.thicknessMm;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.rounded_corner, color: Color(0xFF0284C7), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bend Fillet Radius (${bend.id})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${bend.direction == BendDirection.up ? "UP" : "DOWN"} ${bend.displayAngleDeg.toStringAsFixed(1)}° | Sheet Thk: ${thk.toStringAsFixed(1)}mm',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set the inside bend radius (R). This will display the curvature zone tangent lines on the 2D flat drawing and generate a smooth cylindrical bend arc in 3D:',
              style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 14),

            // Presets
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((r) {
                final isSelected = (_currentRadius - r).abs() < 1e-2;
                return ChoiceChip(
                  label: Text('R${r.toStringAsFixed(1)} mm'),
                  selected: isSelected,
                  selectedColor: const Color(0xFFE0F2FE),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF334155),
                  ),
                  onSelected: (_) {
                    setState(() {
                      _currentRadius = r;
                      _controller.text = r.toStringAsFixed(1);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Custom Input
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Inside Bend Radius R (mm)',
                hintText: 'e.g. 1.5',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: 'mm',
              ),
              onChanged: (val) {
                final parsed = double.tryParse(val);
                if (parsed != null && parsed > 0) {
                  setState(() => _currentRadius = parsed);
                }
              },
            ),
            const SizedBox(height: 12),

            // Calculation info badge
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFF0284C7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Outside Radius: R${(_currentRadius + thk).toStringAsFixed(1)}mm | Tangent zone: ±${_currentRadius.toStringAsFixed(1)}mm in flat layout',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final val = double.tryParse(_controller.text) ?? _currentRadius;
            if (val > 0) {
              widget.viewModel.setBendRadius(bend.id, val);
            }
            Navigator.of(context).pop();
          },
          child: const Text('Apply Radius'),
        ),
      ],
    );
  }
}
