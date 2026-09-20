// =============================================================================
// dimension_property_sheet.dart
//
// Floating On-Canvas Property Inspector for selected associative CAD dimensions.
// Allows rapid modification of measured/driven value, driving status, prefix,
// suffix, tolerances, and layer visibility.
// =============================================================================

import 'package:flutter/material.dart';
import '../../models/cad_dimension.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../engine/associative_dimension_engine.dart';

class DimensionPropertySheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final CadDimension dimension;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const DimensionPropertySheet({
    super.key,
    required this.viewModel,
    required this.dimension,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF0284C7); // Sky Blue for dimensions

    final displayText = AssociativeDimensionEngine.formatDimensionText(dimension);

    return Container(
      width: 260.0,
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Drag Handle + Title + Collapse + Close
          GestureDetector(
            onPanStart: onDragStartHeader,
            onPanUpdate: onDragHeader,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: themeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${dimension.id} (${dimension.type.name.toUpperCase()})',
                    style: TextStyle(
                      color: dimension.isVisible
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onToggleCollapse != null)
                  InkWell(
                    onTap: onToggleCollapse,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        isCollapsed ? Icons.expand_more : Icons.expand_less,
                        size: 16,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                if (onClose != null)
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),

            // Orientation / Alignment Selector
            Row(
              children: [
                _buildOrientationOption(
                  label: 'Horizontal ↔',
                  isSelected: dimension.type == CadDimensionType.horizontal,
                  onTap: () {
                    viewModel.updateDimension(dimension.copyWith(type: CadDimensionType.horizontal));
                  },
                ),
                const SizedBox(width: 4),
                _buildOrientationOption(
                  label: 'Vertical ↕',
                  isSelected: dimension.type == CadDimensionType.vertical,
                  onTap: () {
                    viewModel.updateDimension(dimension.copyWith(type: CadDimensionType.vertical));
                  },
                ),
                const SizedBox(width: 4),
                _buildOrientationOption(
                  label: 'Aligned ⤢',
                  isSelected: dimension.type == CadDimensionType.aligned ||
                      dimension.type == CadDimensionType.holeToHole ||
                      dimension.type == CadDimensionType.holeToEdge,
                  onTap: () {
                    viewModel.updateDimension(dimension.copyWith(type: CadDimensionType.aligned));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Dimension Value & Driving Status
            Row(
              children: [
                Expanded(
                  child: _buildValueField(
                    label: 'Target Value (${dimension.units})',
                    value: dimension.measuredValue,
                    onSubmitted: (newVal) {
                      viewModel.driveDimension(dimension.id, newVal);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Driving', style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: () {
                        final updated = dimension.copyWith(isDriven: !dimension.isDriven);
                        viewModel.updateDimension(updated);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: !dimension.isDriven ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: !dimension.isDriven ? const Color(0xFF38BDF8) : const Color(0xFFCBD5E1),
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          !dimension.isDriven ? 'DRIVING' : 'DRIVEN',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: !dimension.isDriven ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Prefix & Suffix
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    label: 'Prefix (e.g. Ø, R)',
                    value: dimension.prefix ?? '',
                    onSubmitted: (s) {
                      viewModel.updateDimension(dimension.copyWith(prefix: s.isEmpty ? null : s));
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildTextField(
                    label: 'Suffix (e.g. TYP)',
                    value: dimension.suffix ?? '',
                    onSubmitted: (s) {
                      viewModel.updateDimension(dimension.copyWith(suffix: s.isEmpty ? null : s));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Tolerances (+Upper / -Lower)
            Row(
              children: [
                Expanded(
                  child: _buildNullableValueField(
                    label: '+Tol (Upper)',
                    value: dimension.toleranceUpper,
                    onSubmitted: (val) {
                      viewModel.updateDimension(dimension.copyWith(toleranceUpper: val));
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildNullableValueField(
                    label: '-Tol (Lower)',
                    value: dimension.toleranceLower,
                    onSubmitted: (val) {
                      viewModel.updateDimension(dimension.copyWith(toleranceLower: val));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Preview & Delete Button
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Preview: $displayText',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => viewModel.removeDimension(dimension.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFFCA5A5), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 12, color: Color(0xFFDC2626)),
                        SizedBox(width: 2),
                        Text('Del', style: TextStyle(fontSize: 9, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValueField({
    required String label,
    required double value,
    required ValueChanged<double> onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
          ),
          child: Center(
            child: TextField(
              controller: TextEditingController(text: value.toStringAsFixed(1)),
              style: const TextStyle(fontSize: 10, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onSubmitted: (s) {
                final d = double.tryParse(s.trim());
                if (d != null) onSubmitted(d);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNullableValueField({
    required String label,
    required double? value,
    required ValueChanged<double?> onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
          ),
          child: Center(
            child: TextField(
              controller: TextEditingController(text: value != null ? value.toStringAsFixed(2) : ''),
              style: const TextStyle(fontSize: 10, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: '±0.00',
                hintStyle: TextStyle(fontSize: 9, color: Color(0xFFCBD5E1)),
              ),
              onSubmitted: (s) {
                if (s.trim().isEmpty) {
                  onSubmitted(null);
                } else {
                  final d = double.tryParse(s.trim());
                  if (d != null) onSubmitted(d);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    required ValueChanged<String> onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
          ),
          child: Center(
            child: TextField(
              controller: TextEditingController(text: value),
              style: const TextStyle(fontSize: 10, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onSubmitted: onSubmitted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrientationOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 24,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFFCBD5E1),
              width: 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9.0,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }
}
