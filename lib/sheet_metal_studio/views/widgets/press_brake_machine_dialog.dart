// =============================================================================
// press_brake_machine_dialog.dart
//
// Interactive Machine Settings & CAM Tooling Configuration Dialog.
// Allows configuring:
// - Industrial Press Brake Presets (Amada, Trumpf, Bystronic, etc.)
// - Tonnage, Bed Length, Daylight, Throat Depth, and V-Die Opening Width
// - Upper Punch Tool Profile selection with SVG preview
// - Automated Bend Sequencing & CAM Collision Verification
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/press_brake_machine.dart';
import '../../models/press_brake_punch_catalog.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'punch_tooling_selector_dialog.dart';

class PressBrakeMachineDialog extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;

  const PressBrakeMachineDialog({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, SheetMetalStudioViewModel viewModel) {
    return showDialog(
      context: context,
      builder: (_) => PressBrakeMachineDialog(viewModel: viewModel),
    );
  }

  @override
  State<PressBrakeMachineDialog> createState() => _PressBrakeMachineDialogState();
}

class _PressBrakeMachineDialogState extends State<PressBrakeMachineDialog> {
  late PressBrakeMachine _currentMachine;
  late double _vDieWidth;

  @override
  void initState() {
    super.initState();
    _currentMachine = widget.viewModel.selectedMachine;
    _vDieWidth = _currentMachine.vDieWidthMm;
  }

  void _applyMachinePreset(String presetId) {
    final preset = PressBrakeMachine.standardPresets().firstWhere(
      (m) => m.id == presetId,
      orElse: () => PressBrakeMachine.standardPresets().first,
    );
    setState(() {
      _currentMachine = preset.copyWith(
        punchType: _currentMachine.punchType,
      );
      _vDieWidth = _currentMachine.vDieWidthMm;
    });
    widget.viewModel.setSelectedMachine(_currentMachine);
  }

  void _updateVDie(double vDie) {
    setState(() {
      _vDieWidth = vDie;
      _currentMachine = _currentMachine.copyWith(vDieWidthMm: vDie);
    });
    widget.viewModel.setSelectedMachine(_currentMachine);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final punchProfile = PressBrakePunchProfile.getForType(_currentMachine.punchType);
    final presets = PressBrakeMachine.standardPresets();

    return Dialog(
      backgroundColor: const Color(0xFF0F172A), // Dark slate CAD theme
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF334155), width: 1.5),
      ),
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.precision_manufacturing, color: Color(0xFF38BDF8), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PRESS BRAKE MACHINE & CAM SETTINGS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Configure machine limits, V-Die tooling, and upper punch profiles for CAM bending simulation.',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF1E293B), height: 1),
            const SizedBox(height: 16),

            // Content Rows
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Machine Preset & Specs
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MACHINE PRESET',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: presets.any((m) => m.id == _currentMachine.id)
                                ? _currentMachine.id
                                : presets.first.id,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            items: [
                              for (final m in presets)
                                DropdownMenuItem(
                                  value: m.id,
                                  child: Text(m.name),
                                ),
                            ],
                            onChanged: (id) {
                              if (id != null) _applyMachinePreset(id);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Machine Specifications Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          children: [
                            _buildSpecRow('Max Tonnage', '${_currentMachine.maxTonnageTons.toStringAsFixed(0)} metric tons (${_currentMachine.maxTonnageKN.toStringAsFixed(0)} kN)'),
                            const SizedBox(height: 8),
                            _buildSpecRow('Max Bed Length', '${_currentMachine.maxBendLengthMm.toStringAsFixed(0)} mm'),
                            const SizedBox(height: 8),
                            _buildSpecRow('Throat Depth', '${_currentMachine.throatDepthMm.toStringAsFixed(0)} mm'),
                            const SizedBox(height: 8),
                            _buildSpecRow('Daylight (Open Height)', '${_currentMachine.openHeightMm.toStringAsFixed(0)} mm'),
                            const SizedBox(height: 8),
                            _buildSpecRow('Min Flange Length', '${_currentMachine.minBendLengthMm.toStringAsFixed(0)} mm'),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      // V-Die Width Selector
                      Row(
                        children: [
                          const Text(
                            'V-DIE OPENING (V):',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_vDieWidth.toStringAsFixed(1)} mm',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _vDieWidth.clamp(6.0, 50.0),
                        min: 6.0,
                        max: 50.0,
                        divisions: 44,
                        activeColor: const Color(0xFF0284C7),
                        inactiveColor: const Color(0xFF334155),
                        label: '${_vDieWidth.toStringAsFixed(1)} mm',
                        onChanged: _updateVDie,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 20),

                // Right Column: Active Punch Tool Profile & CAM
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'UPPER PUNCH TOOLING',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 70,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: SvgPicture.string(punchProfile.svgString),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    punchProfile.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${punchProfile.standardCode}  •  ${punchProfile.tipAngleDeg.toStringAsFixed(0)}° tip',
                                    style: const TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Tip Radius: R${punchProfile.tipRadiusMm.toStringAsFixed(1)} mm',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Button: Change Punch Tooling from Catalog
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.grid_view_rounded, size: 14, color: Color(0xFF38BDF8)),
                          label: const Text('BROWSE FULL PUNCH CATALOG...'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(color: Color(0xFF0284C7)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () async {
                            await PunchToolingSelectorDialog.show(context, vm);
                            setState(() {
                              _currentMachine = vm.selectedMachine;
                            });
                          },
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Automated CAM Bend Sequence
                      const Text(
                        'BEND SEQUENCE & CAM COLLISION',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.alt_route, size: 14, color: Color(0xFF38BDF8)),
                                const SizedBox(width: 6),
                                Text(
                                  'Bends in Sequence: ${vm.bendSequence.length}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.auto_fix_high, size: 14),
                                label: const Text('AUTO-OPTIMIZE BEND SEQUENCE'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: () {
                                  vm.autoGenerateBendSequence();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Optimized bend sequence for ${_currentMachine.name} with ${vm.bendSequence.length} steps.'),
                                      backgroundColor: const Color(0xFF0D9488),
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            // Footer Close
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildSpecRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
        const Spacer(),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
