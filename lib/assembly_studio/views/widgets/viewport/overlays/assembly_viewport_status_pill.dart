// Top-Right Status Pill (OSHA/ISO Compliance & Cut List / BOM)
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

class AssemblyViewportStatusPill extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback onShowComplianceAuditDialog;
  final VoidCallback onShowBomDialog;

  const AssemblyViewportStatusPill({
    super.key,
    required this.viewModel,
    required this.onShowComplianceAuditDialog,
    required this.onShowBomDialog,
  });

  @override
  Widget build(BuildContext context) {
    final report = viewModel.evaluateLadderCompliance();
    final isLight = viewModel.isLightBackground;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live OSHA / ISO Compliance Badge
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onShowComplianceAuditDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isLight
                  ? const Color(0xFFFFFFFF).withValues(alpha: 0.95)
                  : const Color(0xFF0F172A).withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: report.badgeColor.withValues(alpha: isLight ? 0.95 : 0.8),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isLight ? const Color(0x15000000) : Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  report.isCompliant ? Icons.verified_rounded : Icons.warning_amber_rounded,
                  color: report.badgeColor,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  report.badgeLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: report.badgeColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // BOM & Cut List Pill Button
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onShowBomDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isLight
                  ? const Color(0xFFFFFFFF).withValues(alpha: 0.95)
                  : const Color(0xFF0F172A).withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isLight
                    ? const Color(0xFF0284C7).withValues(alpha: 0.8)
                    : const Color(0xFF38BDF8).withValues(alpha: 0.7),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isLight ? const Color(0x15000000) : Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_rounded,
                  color: isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8),
                  size: 14,
                ),
                const SizedBox(width: 5),
                Text(
                  'Cut List / BOM',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
