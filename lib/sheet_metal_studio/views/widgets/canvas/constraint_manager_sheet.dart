// =============================================================================
// constraint_manager_sheet.dart
//
// Floating On-Canvas Property Sheet for Managing Active Constraints
// per Phase 1 Master Guide Sections 15, 17 & Set 05.
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/cad_constraint.dart';
import '../../../models/constraints/constraint_definition.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class ConstraintManagerSheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const ConstraintManagerSheet({
    super.key,
    required this.viewModel,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    final constraints = viewModel.activeConstraintDefinitions;
    final conflicts = viewModel.currentSolverConflicts;

    return Container(
      width: 290,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          GestureDetector(
            onPanStart: onDragStartHeader,
            onPanUpdate: onDragHeader,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                const Icon(Icons.link, size: 15, color: Color(0xFF0284C7)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Constraints Manager',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Status Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: conflicts.isEmpty ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: conflicts.isEmpty ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  conflicts.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  size: 13,
                  color: conflicts.isEmpty ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    conflicts.isEmpty
                        ? '${constraints.length} constraints solved'
                        : '${conflicts.length} conflict(s) detected',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: conflicts.isEmpty ? const Color(0xFF166534) : const Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Quick Add Constraint Toolbar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _addBtn(context, 'H', 'Make Horizontal', CadConstraintType.horizontal),
              _addBtn(context, 'V', 'Make Vertical', CadConstraintType.vertical),
              _addBtn(context, '↔', 'Add Distance', CadConstraintType.distance),
              _addBtn(context, '⇋', 'Make Symmetric', CadConstraintType.symmetric),
              _addBtn(context, '//', 'Make Parallel', CadConstraintType.parallel),
              _addBtn(context, '🔒', 'Fix Entity', CadConstraintType.fixed),
            ],
          ),
          const Divider(height: 14),

          // Constraint List
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: constraints.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        'No constraints defined.\nSelect an edge or use the buttons above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: constraints.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (ctx, idx) {
                      final c = constraints[idx];
                      final isSelected = c.id == viewModel.selectedConstraintId;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFF0F9FF) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                c.symbol,
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.references.map((r) => r.canonicalPath).join(' ↔ '),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (c.targetValue != null)
                                    Text(
                                      'Target: ${c.targetValue!.toStringAsFixed(1)} mm${c.parameterId != null ? ' (${c.parameterId})' : ''}',
                                      style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                                    ),
                                ],
                              ),
                            ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 13, color: Color(0xFF0284C7)),
                                    tooltip: 'Edit Constraint Value/Parameter',
                                    onPressed: () => _showEditConstraintDialog(context, c),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(c.isActive ? Icons.visibility : Icons.visibility_off, size: 13, color: const Color(0xFF64748B)),
                                    tooltip: c.isActive ? 'Active (Click to suppress)' : 'Suppressed (Click to activate)',
                                    onPressed: () => viewModel.toggleConstraintDefinition(c.id),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 13, color: Color(0xFFEF4444)),
                                    tooltip: 'Delete Constraint',
                                    onPressed: () => viewModel.removeConstraintDefinition(c.id),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
            ],
          ),
        );
  }

  void _showEditConstraintDialog(BuildContext context, ConstraintDefinition c) {
    final valController = TextEditingController(
      text: c.targetValue != null ? c.targetValue!.toStringAsFixed(1) : '',
    );
    final paramController = TextEditingController(
      text: c.parameterId ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.tune, color: Color(0xFF0284C7), size: 18),
            const SizedBox(width: 8),
            Text('Edit ${c.label} Constraint', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.references.map((r) => r.canonicalPath).join(' ↔ '),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valController,
              decoration: const InputDecoration(
                labelText: 'Target Value (mm / deg)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: paramController,
              decoration: const InputDecoration(
                labelText: 'Linked Parameter ID (optional)',
                hintText: 'e.g. WIDTH, BRANCH_WIDTH, EDGE_OFFSET',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () {
              final val = double.tryParse(valController.text.trim());
              final param = paramController.text.trim().isEmpty ? null : paramController.text.trim();
              viewModel.updateConstraintDefinition(
                c.copyWith(
                  targetValue: val,
                  parameterId: param,
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Save & Solve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _addBtn(BuildContext context, String symbol, String tooltip, CadConstraintType type) {
    final isActive = viewModel.activeConstraintPickType == type;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => viewModel.startInteractiveConstraintPick(type),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 34,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isActive ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
          ),
          child: Text(
            symbol,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }
}
