// =============================================================================
// punch_tooling_selector_dialog.dart
//
// Interactive Visual Catalog Dialog for Press Brake Punch Tooling.
// Renders vector SVG cross-sections of market-standard upper punches:
// - Straight 88°, Gooseneck 85°, Semi-Gooseneck 85°, Acute 30°
// - Sash 88°, Radius R10, Hemming 30°, Extended Sword 88°
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/press_brake_punch_catalog.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class PunchToolingSelectorDialog extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;

  const PunchToolingSelectorDialog({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, SheetMetalStudioViewModel viewModel) {
    return showDialog(
      context: context,
      builder: (_) => PunchToolingSelectorDialog(viewModel: viewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = PressBrakePunchProfile.standardCatalog();
    final currentType = viewModel.selectedMachine.punchType;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A), // Dark slate CAD theme
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF334155), width: 1.5),
      ),
      child: Container(
        width: 820,
        height: 620,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.precision_manufacturing, color: Color(0xFF38BDF8), size: 22),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRESS BRAKE PUNCH TOOLING CATALOG',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Select market-standard upper punch tooling for collision analysis & bend sequencing',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(color: Color(0xFF334155), height: 20),

            // Punch Catalog Grid
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.95,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: catalog.length,
                itemBuilder: (context, index) {
                  final profile = catalog[index];
                  final isSelected = profile.type == currentType;

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      final updatedMachine = viewModel.selectedMachine.copyWith(
                        punchType: profile.type,
                      );
                      viewModel.setSelectedMachine(updatedMachine);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Selected punch tooling: ${profile.name} (${profile.standardCode})'),
                          backgroundColor: const Color(0xFF0284C7),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF334155),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Vector SVG Cross-Section Thumbnail
                          Container(
                            width: 75,
                            height: double.infinity,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: SvgPicture.string(
                              profile.svgString,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Specifications & Labels
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        profile.name,
                                        style: TextStyle(
                                          color: isSelected
                                              ? const Color(0xFF38BDF8)
                                              : Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelected)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0284C7),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'ACTIVE',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  profile.standardCode,
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Angle: ${profile.tipAngleDeg.toStringAsFixed(0)}°  |  Radius: R${profile.tipRadiusMm}mm  |  Relief: ${profile.throatReliefMm.toStringAsFixed(0)}mm',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  profile.description,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 9.5,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
