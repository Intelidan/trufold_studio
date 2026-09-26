// =============================================================================
// line_property_sheet.dart
//
// Floating On-Canvas Property Inspector for selected CAD Line Segments / Cut Lines.
// Allows rapid modification of endpoints (X1, Y1, X2, Y2), computed length,
// angle in degrees, layer classification, and visibility.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/cad_primitives.dart';
import '../../models/cad_constraint.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'cad_number_spinner.dart';

class LinePropertySheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final CadLineSegment line;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const LinePropertySheet({
    super.key,
    required this.viewModel,
    required this.line,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF6366F1); // Indigo / Violet for line geometry

    final dx = line.x2 - line.x1;
    final dy = line.y2 - line.y1;
    final length = math.sqrt(dx * dx + dy * dy);
    final angleDeg = (math.atan2(dy, dx) * 180.0 / math.pi) % 360.0;

    return Container(
      width: 250.0,
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: themeColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16.0, offset: const Offset(0, 4))],
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
                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: themeColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${line.id} (LINE SEGMENT)',
                    style: TextStyle(
                      color: line.isVisible ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => viewModel.toggleCutVisibility(line.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      line.isVisible ? Icons.visibility : Icons.visibility_off,
                      size: 14,
                      color: line.isVisible ? const Color(0xFF475569) : const Color(0xFFDC2626),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (onToggleCollapse != null)
                  InkWell(
                    onTap: onToggleCollapse,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(isCollapsed ? Icons.expand_more : Icons.expand_less, size: 16, color: const Color(0xFF64748B)),
                    ),
                  ),
                const SizedBox(width: 4),
                if (onClose != null)
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                    ),
                  ),
              ],
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),

            // Endpoint 1 (X1, Y1)
            Row(
              children: [
                const SizedBox(
                  width: 32,
                  child: Text(
                    'P1',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
                ),
                Expanded(
                  child: _buildCoordinateField(
                    label: 'X',
                    value: line.x1,
                    onSubmitted: (v) {
                      _updateLine(viewModel, line.copyWith(p1: CadPoint2D(v, line.y1)));
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildCoordinateField(
                    label: 'Y',
                    value: line.y1,
                    onSubmitted: (v) {
                      _updateLine(viewModel, line.copyWith(p1: CadPoint2D(line.x1, v)));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Endpoint 2 (X2, Y2)
            Row(
              children: [
                const SizedBox(
                  width: 32,
                  child: Text(
                    'P2',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
                ),
                Expanded(
                  child: _buildCoordinateField(
                    label: 'X',
                    value: line.x2,
                    onSubmitted: (v) {
                      _updateLine(viewModel, line.copyWith(p2: CadPoint2D(v, line.y2)));
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildCoordinateField(
                    label: 'Y',
                    value: line.y2,
                    onSubmitted: (v) {
                      _updateLine(viewModel, line.copyWith(p2: CadPoint2D(line.x2, v)));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Length & Angle
            Row(
              children: [
                Expanded(
                  child: _buildValueField(
                    label: 'Length (mm)',
                    value: length,
                    onSubmitted: (newLen) {
                      if (newLen > 0 && length > 1e-4) {
                        final factor = newLen / length;
                        final newX2 = line.x1 + dx * factor;
                        final newY2 = line.y1 + dy * factor;
                        _updateLine(viewModel, line.copyWith(p2: CadPoint2D(newX2, newY2)));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildReadOnlyField(label: 'Angle', value: '${angleDeg.toStringAsFixed(1)}°'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Layer selector
            Row(
              children: [
                const Text(
                  'Layer: ',
                  style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: line.layer.isNotEmpty ? line.layer : 'CUT',
                        isExpanded: true,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 'CUT', child: Text('CUT')),
                          DropdownMenuItem(value: 'OUTLINE', child: Text('OUTLINE')),
                          DropdownMenuItem(value: 'CONSTRUCTION', child: Text('CONSTRUCTION')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            _updateLine(viewModel, line.copyWith(layer: val));
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Delete button
                InkWell(
                  onTap: () => viewModel.deleteCut(line.id),
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
                        Text(
                          'Del',
                          style: TextStyle(fontSize: 9, color: Color(0xFFDC2626), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Size Dimension Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Size Dimension:',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    line.showLabel ? Icons.visibility : Icons.visibility_off,
                    size: 16,
                    color: line.showLabel ? const Color(0xFF6366F1) : const Color(0xFF94A3B8),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  splashRadius: 14,
                  tooltip: line.showLabel ? 'Hide Size Dimension' : 'Show Size Dimension',
                  onPressed: () => viewModel.toggleCutLabel(line.id),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),

            // Geometric Constraints Section
            const Text(
              'CONSTRAINTS',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildConstraintButton(
                  label: 'H',
                  tooltip: 'Make Horizontal',
                  onTap: () => viewModel.applyConstraint(CadConstraintType.horizontal, targetEntityIds: [line.id]),
                ),
                const SizedBox(width: 4),
                _buildConstraintButton(
                  label: 'V',
                  tooltip: 'Make Vertical',
                  onTap: () => viewModel.applyConstraint(CadConstraintType.vertical, targetEntityIds: [line.id]),
                ),
                const SizedBox(width: 4),
                _buildConstraintButton(
                  label: '🔒',
                  tooltip: 'Fix Line',
                  onTap: () => viewModel.applyConstraint(CadConstraintType.fixed, targetEntityIds: [line.id]),
                ),
              ],
            ),
            ...viewModel.constraints
                .where((c) => c.entityIds.contains(line.id))
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(3)),
                          child: Text(
                            c.symbol,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(c.label, style: const TextStyle(fontSize: 10, color: Color(0xFF334155))),
                        ),
                        InkWell(
                          onTap: () => viewModel.removeConstraint(c.id),
                          child: const Icon(Icons.close, size: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildConstraintButton({required String label, required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
        ),
      ),
    );
  }

  void _updateLine(SheetMetalStudioViewModel vm, CadLineSegment updated) {
    vm.updateCutLine(updated);
  }

  Widget _buildCoordinateField({required String label, required double value, required ValueChanged<double> onSubmitted}) {
    return CadNumberSpinner(label: label, value: value, step: 1.0, decimals: 1, suffix: 'mm', onChanged: onSubmitted);
  }

  Widget _buildValueField({required String label, required double value, required ValueChanged<double> onSubmitted}) {
    return CadNumberSpinner(label: label, value: value, step: 1.0, decimals: 1, suffix: label.contains('Angle') ? '°' : 'mm', onChanged: onSubmitted);
  }

  Widget _buildReadOnlyField({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(fontSize: 10, color: Color(0xFF334155), fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
