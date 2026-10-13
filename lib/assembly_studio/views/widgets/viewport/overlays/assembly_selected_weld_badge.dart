// Selected Weld Joint Overlay Badges & Banners
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

/// Top banner displayed when a weld joint is selected
class AssemblySelectedWeldBanner extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblySelectedWeldBanner({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final weld = viewModel.selectedWeld;
    if (weld == null) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x44000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.offline_bolt_rounded, color: Color(0xFF00E5FF), size: 18),
              const SizedBox(width: 8),
              Text(
                'Weld Joint Selected (${weld.jointDescription})',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
                onPressed: viewModel.deleteSelectedWeld,
                icon: const Icon(Icons.link_off_rounded, size: 14),
                label: const Text(
                  'Break Bond (Del)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => viewModel.selectWeld(null),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-center pill badge showing active weld specifications and break button
class AssemblySelectedWeldStatusBar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblySelectedWeldStatusBar({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final weld = viewModel.selectedWeld;
    if (weld == null) return const SizedBox.shrink();
    final isLight = viewModel.isLightBackground;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.96)
            : const Color(0xFF0F172A).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isLight ? const Color(0xFF0284C7) : const Color(0xFF00E5FF),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isLight ? const Color(0x18000000) : const Color(0x3300E5FF),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flash_on_rounded,
              color: isLight ? const Color(0xFF0284C7) : const Color(0xFF00E5FF),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              '${weld.weldSymbol} (${weld.weldLengthMm.toInt()}mm) • ${weld.standard}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
                color: isLight ? const Color(0xFF0F172A) : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => viewModel.breakBond(weld.partAId, weld.partBId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEF4444), width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_off_rounded, size: 13, color: Color(0xFFEF4444)),
                    SizedBox(width: 4),
                    Text(
                      'Break Bond',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => viewModel.selectWeld(null),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
