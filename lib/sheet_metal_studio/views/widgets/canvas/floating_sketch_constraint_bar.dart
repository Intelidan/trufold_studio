// =============================================================================
// floating_sketch_constraint_bar.dart
//
// Floating Contextual Quick Constraint Bar for truFold Studio Canvas.
// Appears when 1 or 2 CAD entities (lines, points, punches) are selected,
// presenting valid geometric and dimensional constraints in an Onshape-grade UX.
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/cad_constraint.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class FloatingSketchConstraintBar extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final ValueChanged<CadConstraintType> onApplyConstraint;
  final VoidCallback? onStartDimension;
  final VoidCallback? onDismiss;

  const FloatingSketchConstraintBar({
    super.key,
    required this.viewModel,
    required this.onApplyConstraint,
    this.onStartDimension,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final availableConstraints = getAvailableConstraints(viewModel);
    if (availableConstraints.isEmpty) return const SizedBox.shrink();

    final selectedCount = {
      if (viewModel.selectedCutId != null) viewModel.selectedCutId!,
      if (viewModel.selectedBendId != null) viewModel.selectedBendId!,
      if (viewModel.selectedPunchId != null) viewModel.selectedPunchId!,
      ...viewModel.selectedEntityIds,
    }.length;

    return Material(
      color: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle / Header tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link, size: 13, color: Color(0xFF0284C7)),
                  const SizedBox(width: 4),
                  Text(
                    'CONSTRAIN ($selectedCount)',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const SizedBox(
              height: 18,
              child: VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
            ),
            const SizedBox(width: 6),

            // Constraint Buttons
            for (final type in availableConstraints) ...[
              _buildConstraintButton(context, type),
              const SizedBox(width: 4),
            ],

            if (onDismiss != null) ...[
              const SizedBox(width: 2),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 13, color: Color(0xFF94A3B8)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConstraintButton(BuildContext context, CadConstraintType type) {
    final isDistance = type == CadConstraintType.distance;
    final tooltipText = '${type.label} (${type.symbol})';

    return Tooltip(
      message: isDistance ? 'Smart Dimension (D)' : tooltipText,
      child: InkWell(
        onTap: () {
          if (isDistance && onStartDimension != null) {
            onStartDimension!();
          } else {
            onApplyConstraint(type);
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                type.symbol,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                type.label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Evaluates available constraints based on current selection in the ViewModel.
  static List<CadConstraintType> getAvailableConstraints(SheetMetalStudioViewModel viewModel) {
    final selectedIds = <String>{};
    if (viewModel.selectedCutId != null) selectedIds.add(viewModel.selectedCutId!);
    if (viewModel.selectedBendId != null) selectedIds.add(viewModel.selectedBendId!);
    if (viewModel.selectedPunchId != null) selectedIds.add(viewModel.selectedPunchId!);
    selectedIds.addAll(viewModel.selectedEntityIds);

    if (selectedIds.isEmpty) return const [];

    int lineCount = 0;
    int punchCount = 0;

    for (final id in selectedIds) {
      if (viewModel.document.cutLines.any((c) => c.id == id) ||
          viewModel.document.bends.any((b) => b.id == id) ||
          viewModel.document.dimensions.any((d) => d.id == id) ||
          id.startsWith('EDGE_') ||
          id.startsWith('CUT_') ||
          id.startsWith('BEND_') ||
          id.startsWith('dim_') ||
          id.startsWith('DIM_')) {
        lineCount++;
      } else if (viewModel.document.punches.any((p) => p.id == id) ||
          id.startsWith('PUNCH_') ||
          id.startsWith('P')) {
        punchCount++;
      }
    }

    final totalCount = selectedIds.length;
    final available = <CadConstraintType>[];

    if (totalCount == 1) {
      if (lineCount == 1) {
        available.addAll([
          CadConstraintType.horizontal,
          CadConstraintType.vertical,
          CadConstraintType.fixed,
        ]);
      } else if (punchCount == 1) {
        available.add(CadConstraintType.fixed);
      } else {
        available.addAll([
          CadConstraintType.horizontal,
          CadConstraintType.vertical,
          CadConstraintType.fixed,
        ]);
      }
    } else if (totalCount == 2) {
      if (lineCount == 2) {
        available.addAll([
          CadConstraintType.angle,
          CadConstraintType.parallel,
          CadConstraintType.perpendicular,
          CadConstraintType.equal,
          CadConstraintType.collinear,
          CadConstraintType.distance,
        ]);
      } else if (punchCount == 2) {
        available.addAll([
          CadConstraintType.concentric,
          CadConstraintType.equal,
          CadConstraintType.distance,
        ]);
      } else if (lineCount == 1 && punchCount == 1) {
        available.addAll([
          CadConstraintType.coincident,
          CadConstraintType.symmetric,
          CadConstraintType.distance,
        ]);
      } else {
        available.addAll([
          CadConstraintType.coincident,
          CadConstraintType.horizontal,
          CadConstraintType.vertical,
          CadConstraintType.distance,
          CadConstraintType.equal,
        ]);
      }
    } else {
      available.addAll([
        CadConstraintType.equal,
        CadConstraintType.symmetric,
        CadConstraintType.fixed,
      ]);
    }

    return available;
  }

  static bool canApplyHorizontal(SheetMetalStudioViewModel vm) =>
      getAvailableConstraints(vm).contains(CadConstraintType.horizontal);

  static bool canApplyVertical(SheetMetalStudioViewModel vm) =>
      getAvailableConstraints(vm).contains(CadConstraintType.vertical);

  static bool canApplyFixed(SheetMetalStudioViewModel vm) =>
      getAvailableConstraints(vm).contains(CadConstraintType.fixed);

  static bool canApplyParallel(SheetMetalStudioViewModel vm) =>
      getAvailableConstraints(vm).contains(CadConstraintType.parallel);

  static bool canApplyPerpendicular(SheetMetalStudioViewModel vm) =>
      getAvailableConstraints(vm).contains(CadConstraintType.perpendicular);

  static bool canApplyEqual(SheetMetalStudioViewModel vm) =>
      getAvailableConstraints(vm).contains(CadConstraintType.equal);

  static bool canApplyCoincident(SheetMetalStudioViewModel vm) =>
      getAvailableConstraints(vm).contains(CadConstraintType.coincident);

  static bool canApplyConcentric(SheetMetalStudioViewModel vm) =>
      getAvailableConstraints(vm).contains(CadConstraintType.concentric);
}
