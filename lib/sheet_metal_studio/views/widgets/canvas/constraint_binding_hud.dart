// =============================================================================
// constraint_binding_hud.dart
//
// Floating On-Canvas Guidance HUD for Interactive 2-Click Constraint Binding
// per Phase 1 Master Guide Sections 15, 17 & Set 05.
// =============================================================================

import 'package:flutter/material.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class ConstraintBindingHud extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;

  const ConstraintBindingHud({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final pickType = viewModel.activeConstraintPickType;
    if (pickType == null) return const SizedBox.shrink();

    final step1Done = viewModel.firstPickedEntityRef != null;
    final title = step1Done
        ? 'Step 2: Select 2nd Edge or Reference to bind to ${viewModel.firstPickedEntityRef!.canonicalPath}'
        : 'Step 1: Select 1st Edge or Entity for ${pickType.label} Constraint';

    return Center(
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF0F172A),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  pickType.symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => viewModel.cancelInteractiveConstraintPick(),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 10.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
