// Parametric CAD Settings Dialog Overlay Widget
// TruFold Assembly Studio - Phase 6 Settings
// Modular MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/theme/assembly_studio_theme.dart';

/// Modal dialog for configuring parametric CAD modeling units, grid snapping, extrude defaults, and viewport preferences.
class AssemblyCadSettingsDialog extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblyCadSettingsDialog({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final settings = viewModel.cadSettings;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 380,
              constraints: const BoxConstraints(maxHeight: 560),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.settings_suggest_rounded, color: AssemblyStudioTheme.onshapeBlue, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'CAD & VIEWPORT SETTINGS',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: viewModel.closeCadSettingsDialog,
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(2.0),
                            child: Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Settings Content Sections (Scrollable)
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // A. GRID & SNAPPING
                          _buildSectionTitle('GRID & SNAPPING'),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [0.0, 1.0, 5.0, 10.0, 25.0].map((snap) {
                              final isSel = settings.gridSnapMm == snap;
                              final label = snap == 0.0 ? 'Off' : '${snap.toInt()} mm';
                              return ChoiceChip(
                                label: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                                    color: isSel ? Colors.white : const Color(0xFF334155),
                                  ),
                                ),
                                selected: isSel,
                                selectedColor: AssemblyStudioTheme.onshapeBlue,
                                backgroundColor: const Color(0xFFF1F5F9),
                                side: BorderSide(color: isSel ? AssemblyStudioTheme.onshapeBlue : const Color(0xFFCBD5E1)),
                                onSelected: (_) {
                                  viewModel.updateCadSettings(settings.copyWith(gridSnapMm: snap));
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          _buildSwitchRow(
                            title: 'Auto-Constraint Inference',
                            subtitle: 'Snaps perpendicular, parallel, & coincident automatically',
                            value: settings.autoConstraintInference,
                            onChanged: (val) {
                              viewModel.updateCadSettings(settings.copyWith(autoConstraintInference: val));
                            },
                          ),

                          const Divider(color: Color(0xFFE2E8F0), height: 24),

                          // B. UNITS & STANDARDS
                          _buildSectionTitle('UNITS SYSTEM'),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSegmentButton(
                                  label: 'Metric (mm / kg)',
                                  isSelected: !settings.isImperial,
                                  onTap: () {
                                    viewModel.updateCadSettings(settings.copyWith(isImperial: false));
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildSegmentButton(
                                  label: 'Imperial (in / lb)',
                                  isSelected: settings.isImperial,
                                  onTap: () {
                                    viewModel.updateCadSettings(settings.copyWith(isImperial: true));
                                  },
                                ),
                              ),
                            ],
                          ),

                          const Divider(color: Color(0xFFE2E8F0), height: 24),

                          // C. EXTRUSION DEFAULTS
                          _buildSectionTitle('DEFAULT EXTRUDE FEATURE'),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Default Distance:', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                              Text(
                                '${settings.defaultExtrudeDistanceMm.toStringAsFixed(1)} mm',
                                style: const TextStyle(color: AssemblyStudioTheme.onshapeBlue, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.0,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              activeTrackColor: AssemblyStudioTheme.onshapeBlue,
                              inactiveTrackColor: const Color(0xFFE2E8F0),
                              thumbColor: AssemblyStudioTheme.onshapeBlue,
                            ),
                            child: Slider(
                              value: settings.defaultExtrudeDistanceMm,
                              min: 5.0,
                              max: 200.0,
                              onChanged: (val) {
                                viewModel.updateCadSettings(
                                  settings.copyWith(defaultExtrudeDistanceMm: double.parse(val.toStringAsFixed(1))),
                                );
                              },
                            ),
                          ),

                          const Divider(color: Color(0xFFE2E8F0), height: 24),

                          // D. VIEWPORT & VISUAL STYLES
                          _buildSectionTitle('VIEWPORT PREFERENCES'),
                          const SizedBox(height: 6),
                          _buildSwitchRow(
                            title: 'Parametric Timeline Bar',
                            subtitle: 'Show bottom design history rollback strip',
                            value: settings.showTimeline,
                            onChanged: (val) {
                              viewModel.updateCadSettings(settings.copyWith(showTimeline: val));
                            },
                          ),
                          const SizedBox(height: 6),
                          _buildSwitchRow(
                            title: 'Show Constraint Badges',
                            subtitle: 'Display geometric icons on sketch entities',
                            value: settings.showConstraintBadges,
                            onChanged: (val) {
                              viewModel.updateCadSettings(settings.copyWith(showConstraintBadges: val));
                            },
                          ),
                          const SizedBox(height: 6),
                          _buildSwitchRow(
                            title: 'Show DOF Cues (Blue / Black)',
                            subtitle: 'Blue = Under-constrained, Black = Fully constrained',
                            value: settings.showDofBadges,
                            onChanged: (val) {
                              viewModel.updateCadSettings(settings.copyWith(showDofBadges: val));
                            },
                          ),
                          const SizedBox(height: 6),
                          _buildSwitchRow(
                            title: 'Show Origin Axes',
                            subtitle: 'Display 3D origin triad coordinate marker',
                            value: settings.showOriginAxes,
                            onChanged: (val) {
                              viewModel.updateCadSettings(settings.copyWith(showOriginAxes: val));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3. Footer Action Button
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(9)),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AssemblyStudioTheme.onshapeBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: viewModel.closeCadSettingsDialog,
                      child: const Text('Save & Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AssemblyStudioTheme.onshapeBlue : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? AssemblyStudioTheme.onshapeBlue : const Color(0xFFCBD5E1)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5)),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeThumbColor: AssemblyStudioTheme.onshapeBlue,
          activeTrackColor: AssemblyStudioTheme.onshapeBlue.withValues(alpha: 0.4),
          inactiveThumbColor: const Color(0xFF94A3B8),
          inactiveTrackColor: const Color(0xFFE2E8F0),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
