// Viewport Dialogs & Context Menu
// Modularized for TruFold MVVM Architecture

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

class AssemblyViewportDialogs {
  // ---------------------------------------------------------------------------
  // INTERACTIVE COMPLIANCE AUDIT & 1-CLICK AUTO-FIX DIALOG
  // ---------------------------------------------------------------------------
  static void showComplianceAuditDialog(BuildContext context, AssemblyStudioViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final report = vm.evaluateLadderCompliance();

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(report.isCompliant ? Icons.verified_user_rounded : Icons.shield_rounded, color: report.badgeColor, size: 26),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'OSHA 1910 & EN ISO 14122-4 Audit',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                ),
                                const Text(
                                  'Automated Live Industrial Safety Verification',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: report.badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: report.badgeColor, width: 1.0),
                            ),
                            child: Text(
                              report.overallStatus.name.toUpperCase(),
                              style: TextStyle(color: report.badgeColor, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFE2E8F0), height: 1),
                      const SizedBox(height: 12),

                      // Checklist items
                      Expanded(
                        child: ListView.separated(
                          itemCount: report.items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final item = report.items[idx];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: item.statusColor.withValues(alpha: 0.3), width: 1.0),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(item.statusIcon, color: item.statusColor, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: item.statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          item.statusLabel,
                                          style: TextStyle(color: item.statusColor, fontWeight: FontWeight.bold, fontSize: 9.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Standard: ${item.standardCode}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                                  const SizedBox(height: 4),
                                  Text(item.description, style: const TextStyle(fontSize: 11, color: Color(0xFF334155))),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.recommendation,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontStyle: FontStyle.italic,
                                            color: item.isPass ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                          ),
                                        ),
                                      ),
                                      if (!item.isPass && item.fixActionId.isNotEmpty)
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0076CE),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          icon: const Icon(Icons.flash_on_rounded, size: 13),
                                          label: const Text('Auto-Fix', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                          onPressed: () {
                                            switch (item.fixActionId) {
                                              case 'fix_rung_pitch':
                                                vm.autoFixRungSpacing();
                                                break;
                                              case 'fix_clear_width':
                                                vm.autoFixClearWidth();
                                                break;
                                              case 'fix_wall_clearance':
                                                vm.autoFixWallClearance();
                                                break;
                                              case 'fix_cage_height':
                                                vm.autoFixCageHeight();
                                                break;
                                              case 'fix_parapet_extension':
                                                vm.autoFixParapetExtension();
                                                break;
                                            }
                                            setDialogState(() {});
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Footer Actions
                      Row(
                        children: [
                          if (!report.isCompliant)
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                                label: const Text('Auto-Fix All Issues', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  vm.autoFixAllComplianceIssues();
                                  setDialogState(() {});
                                },
                              ),
                            ),
                          if (!report.isCompliant) const SizedBox(width: 10),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Close', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // INTERACTIVE BILL OF MATERIALS (BOM) & CUT LIST DIALOG
  // ---------------------------------------------------------------------------
  static void showBomDialog(BuildContext context, AssemblyStudioViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) {
        final bom = vm.generateBillOfMaterials();

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_rounded, color: Color(0xFF0076CE), size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bill of Materials & Cut List (${bom.assemblyTitle})',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            const Text(
                              'Fabrication Part Takeoff, Profile Cut Lengths & Weld Metrics',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0076CE).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF0076CE), width: 1.0),
                        ),
                        child: Text(
                          '${bom.totalPartCount} PARTS',
                          style: const TextStyle(color: Color(0xFF0076CE), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Stat Summary Cards
                  Row(
                    children: [
                      _buildBomStatBox('Total Weight', '${bom.totalWeightKg.toStringAsFixed(1)} kg', const Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      _buildBomStatBox('Cut Parts', '${bom.totalPartCount} pcs', const Color(0xFF0076CE)),
                      const SizedBox(width: 8),
                      _buildBomStatBox('Fillet Welds', '${bom.totalWeldCount} joints', const Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      _buildBomStatBox('Weld Seam', '${(bom.totalWeldLengthMm / 1000.0).toStringAsFixed(2)} m', const Color(0xFF334155)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Color(0xFFE2E8F0), height: 1),
                  const SizedBox(height: 10),

                  // Table
                  Expanded(
                    child: SingleChildScrollView(
                      child: Table(
                        columnWidths: const {
                          0: FixedColumnWidth(40),
                          1: FixedColumnWidth(65),
                          2: FlexColumnWidth(2.5),
                          3: FlexColumnWidth(2.2),
                          4: FixedColumnWidth(45),
                          5: FixedColumnWidth(75),
                          6: FixedColumnWidth(65),
                          7: FixedColumnWidth(65),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                            children: [
                              _buildTh('#'),
                              _buildTh('Mark'),
                              _buildTh('Description'),
                              _buildTh('Profile'),
                              _buildTh('Qty'),
                              _buildTh('Cut (mm)'),
                              _buildTh('Unit (kg)'),
                              _buildTh('Total (kg)'),
                            ],
                          ),
                          ...bom.items.map((it) {
                            return TableRow(
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
                              ),
                              children: [
                                _buildTd(it.itemNumber),
                                _buildTd(it.partMark, bold: true, color: const Color(0xFF0076CE)),
                                _buildTd(it.description),
                                _buildTd(it.profile),
                                _buildTd('${it.quantity}'),
                                _buildTd(it.cutLengthMm.toStringAsFixed(0)),
                                _buildTd(it.unitWeightKg.toStringAsFixed(2)),
                                _buildTd(it.totalWeightKg.toStringAsFixed(2)),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Actions
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0076CE),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.file_download_rounded, size: 16),
                        label: const Text('Export CSV', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: bom.toCsv()));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('BOM CSV copied to clipboard!')));
                        },
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF334155),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          backgroundColor: const Color(0xFFF8FAFC),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy Markdown', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: bom.toMarkdown()));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('BOM Markdown table copied to clipboard!')));
                        },
                      ),
                      const Spacer(),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildBomStatBox(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildTh(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
        textAlign: TextAlign.left,
      ),
    );
  }

  static Widget _buildTd(String val, {bool bold = false, Color color = const Color(0xFF0F172A)}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        val,
        style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color),
        textAlign: TextAlign.left,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAGNETIC COUPLING DIALOG
  // ---------------------------------------------------------------------------
  static void showMagneticCouplingDialog(BuildContext context, AssemblyStudioViewModel vm, {VoidCallback? onRebuildGpu}) {
    final spotsList = <(AssemblyPart, AssemblyMagneticSpot)>[];
    for (final part in vm.doc.parts) {
      if (!part.isVisible) continue;
      for (final spot in part.magneticSpots) {
        spotsList.add((part, spot));
      }
    }

    if (spotsList.length < 2) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('At least 2 magnetic spots must be placed on different entities first.'), duration: Duration(seconds: 3)));
      return;
    }

    var selectedItem1 = spotsList.first;
    var validSpotsFor2 = spotsList.where((item) => item.$1.id != selectedItem1.$1.id).toList();
    if (validSpotsFor2.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Both spots currently belong to the same entity. Place a spot on a second entity first.'), duration: Duration(seconds: 3)),
      );
      return;
    }
    var selectedItem2 = validSpotsFor2.first;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final availableFor2 = spotsList.where((item) => item.$1.id != selectedItem1.$1.id).toList();
            if (!availableFor2.contains(selectedItem2) && availableFor2.isNotEmpty) {
              selectedItem2 = availableFor2.first;
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: const Color(0xFF0076CE).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.hub_rounded, color: Color(0xFF0076CE), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Magnetic Snap & Coupling',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                ),
                                Text('Attract & link entities via magnetic snap points', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Magnetic Point 1 (Anchor Entity)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<(AssemblyPart, AssemblyMagneticSpot)>(
                            value: selectedItem1,
                            isExpanded: true,
                            dropdownColor: Colors.white,
                            items: spotsList.map((item) {
                              return DropdownMenuItem(
                                value: item,
                                child: Text('${item.$1.name} • ${item.$2.name}', style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A))),
                              );
                            }).toList(),
                            onChanged: (newVal) {
                              if (newVal != null) {
                                setDialogState(() {
                                  selectedItem1 = newVal;
                                  final newAvailable2 = spotsList.where((it) => it.$1.id != selectedItem1.$1.id).toList();
                                  if (newAvailable2.isNotEmpty) {
                                    selectedItem2 = newAvailable2.first;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Magnetic Point 2 (Attracted Entity)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Note: Selecting a magnetic point from the same entity is disabled.',
                        style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<(AssemblyPart, AssemblyMagneticSpot)>(
                            value: availableFor2.contains(selectedItem2) ? selectedItem2 : (availableFor2.isNotEmpty ? availableFor2.first : null),
                            isExpanded: true,
                            dropdownColor: Colors.white,
                            items: availableFor2.map((item) {
                              return DropdownMenuItem(
                                value: item,
                                child: Text('${item.$1.name} • ${item.$2.name}', style: const TextStyle(fontSize: 12, color: Color(0xFF0076CE))),
                              );
                            }).toList(),
                            onChanged: (newVal) {
                              if (newVal != null) {
                                setDialogState(() {
                                  selectedItem2 = newVal;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.info_outline_rounded, color: Color(0xFF0076CE), size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Upon linking, Entity 2 will be attracted and joined to Entity 1. '
                                'Unlike welded joints, magnetically linked entities can rotate in place without breaking the joint. '
                                'The magnetic joint can also be broken on demand.',
                                style: TextStyle(fontSize: 10.5, color: Color(0xFF334155), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0076CE),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () {
                              final success = vm.createMagneticJoint(
                                partAId: selectedItem1.$1.id,
                                spotAId: selectedItem1.$2.id,
                                partBId: selectedItem2.$1.id,
                                spotBId: selectedItem2.$2.id,
                              );
                              Navigator.of(ctx).pop();
                              if (success) {
                                onRebuildGpu?.call();
                                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                  SnackBar(
                                    content: Text('Entities "${selectedItem1.$1.name}" and "${selectedItem2.$1.name}" magnetically linked!'),
                                    backgroundColor: const Color(0xFF059669),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // PROMPT GROUP NAME & CREATE GROUP DIALOG
  // ---------------------------------------------------------------------------
  static Future<String?> promptGroupName(BuildContext context, AssemblyStudioViewModel vm) async {
    if (!vm.canGroupSelectedParts) return null;
    final defaultName = 'Group ${vm.nextGroupNumber}';
    final controller = TextEditingController(text: defaultName);

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFF383844)),
        ),
        title: Row(
          children: const [
            Icon(Icons.workspaces_outlined, size: 18, color: Color(0xFF38BDF8)),
            SizedBox(width: 8),
            Text(
              'Create Virtual Group',
              style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a name for this group. Grouped parts act as a single unit and move together rigidly without physical welding.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Group Name',
                labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF475569)),
                  borderRadius: BorderRadius.circular(6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onSubmitted: (val) {
                final trimmed = val.trim();
                Navigator.of(ctx).pop(trimmed.isNotEmpty ? trimmed : defaultName);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () {
              final trimmed = controller.text.trim();
              Navigator.of(ctx).pop(trimmed.isNotEmpty ? trimmed : defaultName);
            },
            child: const Text('Create Group', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CAD CONTEXT MENU
  // ---------------------------------------------------------------------------
  static Future<void> showContextMenu(
    BuildContext context,
    Offset globalPos,
    AssemblyStudioViewModel vm, {
    required VoidCallback onZoomToFit,
    required Future<void> Function() onPromptGroupNameAndGroup,
  }) async {
    final canGroup = vm.canGroupSelectedParts;
    final canUngroup = vm.canUngroupSelectedParts;
    final hasSelection = vm.doc.selectedPartIds.isNotEmpty;

    final items = <PopupMenuEntry<String>>[
      if (canGroup)
        PopupMenuItem<String>(
          value: 'group',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.workspaces_outlined, size: 14, color: Color(0xFF38BDF8)),
              SizedBox(width: 8),
              Text('Group Selection', style: TextStyle(fontSize: 11, color: Color(0xFFE2E8F0))),
              Spacer(),
              Text('Ctrl+G', style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
            ],
          ),
        ),
      if (canUngroup)
        PopupMenuItem<String>(
          value: 'ungroup',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.group_off_outlined, size: 14, color: Color(0xFFF43F5E)),
              SizedBox(width: 8),
              Text('Ungroup', style: TextStyle(fontSize: 11, color: Color(0xFFE2E8F0))),
              Spacer(),
              Text('Ctrl+Shift+G', style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
            ],
          ),
        ),
      if (hasSelection && vm.doc.selectedPartIds.length >= 2)
        PopupMenuItem<String>(
          value: 'weld',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.hardware_rounded, size: 14, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('Manual Weld Torch (W)', style: TextStyle(fontSize: 11, color: Color(0xFFE2E8F0))),
            ],
          ),
        ),
      if (hasSelection) ...[
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'duplicate',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.copy_rounded, size: 14, color: Color(0xFF94A3B8)),
              SizedBox(width: 8),
              Text('Duplicate', style: TextStyle(fontSize: 11, color: Color(0xFFE2E8F0))),
              Spacer(),
              Text('Ctrl+D', style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
              Spacer(),
              Text('Del', style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'clear_selection',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.deselect_outlined, size: 14, color: Color(0xFF94A3B8)),
              SizedBox(width: 8),
              Text('Clear Selection', style: TextStyle(fontSize: 11, color: Color(0xFFE2E8F0))),
              Spacer(),
              Text('Esc', style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ],
      if (!hasSelection) ...[
        PopupMenuItem<String>(
          value: 'select_all',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.select_all_rounded, size: 14, color: Color(0xFF38BDF8)),
              SizedBox(width: 8),
              Text('Select All', style: TextStyle(fontSize: 11, color: Color(0xFFE2E8F0))),
              Spacer(),
              Text('Ctrl+A', style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'zoom_fit',
          height: 32,
          child: Row(
            children: const [
              Icon(Icons.crop_free_rounded, size: 14, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Zoom to Fit', style: TextStyle(fontSize: 11, color: Color(0xFFE2E8F0))),
              Spacer(),
              Text('Double-Tap / F', style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ],
    ];

    if (items.isEmpty) return;

    final screenSize = MediaQuery.of(context).size;
    final double menuX = (globalPos.dx.clamp(8.0, math.max(8.0, screenSize.width - 220.0))).toDouble();
    final double menuY = (globalPos.dy.clamp(8.0, math.max(8.0, screenSize.height - 280.0))).toDouble();

    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: menuX,
              top: menuY,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E24),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF383844), width: 1),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(fontSize: 11, color: Color(0xFFE2E8F0)),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in items)
                            if (item is PopupMenuItem<String>)
                              InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => Navigator.of(dialogContext).pop(item.value),
                                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: item.child),
                              )
                            else if (item is PopupMenuDivider)
                              const Divider(height: 1, color: Color(0xFF383844)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (choice == null) return;
    if (choice == 'group') {
      await onPromptGroupNameAndGroup();
    } else if (choice == 'ungroup') {
      vm.ungroupSelectedParts();
    } else if (choice == 'weld') {
      vm.setToolMode(SketchUpToolMode.weld);
      vm.setVcbState(label: 'Weld Tool', value: 'Ready', hint: 'Click and drag torch to paint weld beads along entity seam');
    } else if (choice == 'duplicate') {
      vm.duplicateSelectedPart();
    } else if (choice == 'delete') {
      vm.deleteSelectedPart();
    } else if (choice == 'clear_selection') {
      vm.clearSelection();
    } else if (choice == 'select_all') {
      vm.selectAllParts();
    } else if (choice == 'zoom_fit') {
      onZoomToFit();
    }
  }
}
