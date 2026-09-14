// =============================================================================
// dimension_drive_dialog.dart
//
// Double-click Direct Dimension Driving Dialog per Master Guide Step 7 (#20).
// Allows instant inline editing of CAD dimensions to drive geometry directly.
// =============================================================================

import 'package:flutter/material.dart';

import '../../models/cad_dimension.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../engine/associative_dimension_engine.dart';

class DimensionDriveDialog extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final CadDimension dimension;

  const DimensionDriveDialog({
    super.key,
    required this.viewModel,
    required this.dimension,
  });

  /// Displays the modal drive dialog
  static Future<void> show(
    BuildContext context, {
    required SheetMetalStudioViewModel viewModel,
    required CadDimension dimension,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) =>
          DimensionDriveDialog(viewModel: viewModel, dimension: dimension),
    );
  }

  @override
  State<DimensionDriveDialog> createState() => _DimensionDriveDialogState();
}

class _DimensionDriveDialogState extends State<DimensionDriveDialog> {
  late TextEditingController _controller;
  late bool _driveGeometry;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.dimension.measuredValue.toStringAsFixed(1),
    );
    _driveGeometry = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final text = _controller.text.trim();
    final val = double.tryParse(text);

    if (val == null) {
      setState(() => _errorMessage = 'Please enter a valid number');
      return;
    }

    if (val <= 0.0 && widget.dimension.type != CadDimensionType.angular) {
      setState(() => _errorMessage = 'Value must be greater than 0');
      return;
    }

    if (_driveGeometry) {
      widget.viewModel.driveDimension(widget.dimension.id, val);
    } else {
      widget.viewModel.updateDimension(
        widget.dimension.copyWith(measuredValue: val, isDriven: true),
      );
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dim = widget.dimension;
    final formattedCurrent = AssociativeDimensionEngine.formatDimensionText(
      dim,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 16,
      backgroundColor: Colors.white,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.straighten,
                    size: 20,
                    color: Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Drive Dimension',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '${dim.type.name.toUpperCase()} • $formattedCurrent',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 16),

            // Value Input Field
            Text(
              'Target Dimension (${dim.units}):',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _errorMessage != null
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFCBD5E1),
                  width: 1.2,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _apply(),
                    ),
                  ),
                  Text(
                    dim.units,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
              ),
            ],
            const SizedBox(height: 12),

            // Drive Geometry Checkbox
            InkWell(
              onTap: () => setState(() => _driveGeometry = !_driveGeometry),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _driveGeometry,
                      activeColor: const Color(0xFF0284C7),
                      onChanged: (v) =>
                          setState(() => _driveGeometry = v ?? true),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Drive CAD Geometry directly',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Modifying driving dimensions updates CAD elements, recomputes planar faces & 3D folds with 50-step Undo.',
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 18),

            // Buttons: Cancel & Apply
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
                ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Apply Drive',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
