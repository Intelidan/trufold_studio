import 'package:flutter/material.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';
import '../theme/assembly_studio_theme.dart';

/// Authentic SketchUp-style "Measurement units" settings card matching Screenshot SS2.
/// Used both in Property Grid Panel as a collapsible section and in the Menu Bar Settings dialog.
class AssemblyMeasurementUnitsCard extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final bool isDialog;

  const AssemblyMeasurementUnitsCard({
    super.key,
    required this.viewModel,
    this.isDialog = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AssemblyStudioTheme(isLight: viewModel.isLightBackground);

    return Container(
      padding: EdgeInsets.all(isDialog ? 16 : 8),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(isDialog ? 8 : 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDialog) ...[
            Row(
              children: [
                Icon(Icons.straighten_rounded, size: 16, color: theme.accentSky),
                const SizedBox(width: 8),
                Text(
                  'Measurement units',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: theme.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 16, color: theme.textTertiary),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: theme.panelBorder),
            const SizedBox(height: 12),
          ],

          // 1. Format (SS2)
          _buildFieldLabel('Format', theme),
          const SizedBox(height: 3),
          _buildDropdownContainer(
            theme: theme,
            child: DropdownButton<MeasurementUnitFormat>(
              value: viewModel.unitFormat,
              isExpanded: true,
              dropdownColor: theme.cardBackground,
              style: TextStyle(fontSize: 10, color: theme.textPrimary),
              items: MeasurementUnitFormat.values.map((f) {
                return DropdownMenuItem(value: f, child: Text(f.label, style: TextStyle(fontSize: 10, color: theme.textPrimary)));
              }).toList(),
              onChanged: (val) {
                if (val != null) viewModel.setMeasurementSettings(format: val);
              },
            ),
          ),
          const SizedBox(height: 8),

          // 2. Length & Display precision (SS2)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Length', theme),
                    const SizedBox(height: 3),
                    _buildDropdownContainer(
                      theme: theme,
                      child: DropdownButton<MeasurementLengthUnit>(
                        value: viewModel.lengthUnit,
                        isExpanded: true,
                        dropdownColor: theme.cardBackground,
                        style: TextStyle(fontSize: 10, color: theme.textPrimary),
                        items: MeasurementLengthUnit.values.map((u) {
                          return DropdownMenuItem(value: u, child: Text(u.label, style: TextStyle(fontSize: 10, color: theme.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) viewModel.setMeasurementSettings(length: val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Display precision', theme),
                    const SizedBox(height: 3),
                    _buildDropdownContainer(
                      theme: theme,
                      child: DropdownButton<int>(
                        value: viewModel.lengthDisplayPrecision,
                        isExpanded: true,
                        dropdownColor: theme.cardBackground,
                        style: TextStyle(fontSize: 10, color: theme.textPrimary),
                        items: _buildLengthPrecisionItems(viewModel.lengthUnit, theme),
                        onChanged: (val) {
                          if (val != null) viewModel.setMeasurementSettings(lengthPrecision: val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 3. Area & Display precision (SS2)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Area', theme),
                    const SizedBox(height: 3),
                    _buildDropdownContainer(
                      theme: theme,
                      child: DropdownButton<MeasurementAreaUnit>(
                        value: viewModel.areaUnit,
                        isExpanded: true,
                        dropdownColor: theme.cardBackground,
                        style: TextStyle(fontSize: 10, color: theme.textPrimary),
                        items: MeasurementAreaUnit.values.map((u) {
                          return DropdownMenuItem(value: u, child: Text(u.label, style: TextStyle(fontSize: 10, color: theme.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) viewModel.setMeasurementSettings(area: val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    _buildDropdownContainer(
                      theme: theme,
                      child: DropdownButton<int>(
                        value: viewModel.areaDisplayPrecision,
                        isExpanded: true,
                        dropdownColor: theme.cardBackground,
                        style: TextStyle(fontSize: 10, color: theme.textPrimary),
                        items: [
                          DropdownMenuItem(value: 0, child: Text('0 ${viewModel.areaUnit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                          DropdownMenuItem(value: 1, child: Text('0.0 ${viewModel.areaUnit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                          DropdownMenuItem(value: 2, child: Text('0.00 ${viewModel.areaUnit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                        ],
                        onChanged: (val) {
                          if (val != null) viewModel.setMeasurementSettings(areaPrecision: val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 4. Volume & Display precision (SS2)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Volume', theme),
                    const SizedBox(height: 3),
                    _buildDropdownContainer(
                      theme: theme,
                      child: DropdownButton<MeasurementVolumeUnit>(
                        value: viewModel.volumeUnit,
                        isExpanded: true,
                        dropdownColor: theme.cardBackground,
                        style: TextStyle(fontSize: 10, color: theme.textPrimary),
                        items: MeasurementVolumeUnit.values.map((u) {
                          return DropdownMenuItem(value: u, child: Text(u.label, style: TextStyle(fontSize: 10, color: theme.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) viewModel.setMeasurementSettings(volume: val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    _buildDropdownContainer(
                      theme: theme,
                      child: DropdownButton<int>(
                        value: viewModel.volumeDisplayPrecision,
                        isExpanded: true,
                        dropdownColor: theme.cardBackground,
                        style: TextStyle(fontSize: 10, color: theme.textPrimary),
                        items: [
                          DropdownMenuItem(value: 0, child: Text('0 ${viewModel.volumeUnit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                          DropdownMenuItem(value: 1, child: Text('0.0 ${viewModel.volumeUnit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                          DropdownMenuItem(value: 2, child: Text('0.00 ${viewModel.volumeUnit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                        ],
                        onChanged: (val) {
                          if (val != null) viewModel.setMeasurementSettings(volumePrecision: val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 5. Enable length snapping row (SS2)
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: viewModel.enableLengthSnapping,
                  activeColor: theme.accentSky,
                  checkColor: Colors.white,
                  side: BorderSide(color: theme.inputBorder, width: 1.0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) {
                    viewModel.setMeasurementSettings(lengthSnapping: val ?? false);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Enable length snapping',
                  style: TextStyle(fontSize: 10, color: theme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 74,
                child: _buildDropdownContainer(
                  theme: theme,
                  child: DropdownButton<double>(
                    value: viewModel.lengthSnapStep,
                    isExpanded: true,
                    dropdownColor: theme.cardBackground,
                    style: TextStyle(fontSize: 9.5, color: theme.textPrimary),
                    items: [
                      DropdownMenuItem(value: 1.0, child: Text('1.0 ${viewModel.lengthUnit.symbol}', style: TextStyle(fontSize: 9.5, color: theme.textPrimary))),
                      DropdownMenuItem(value: 0.1, child: Text('0.1 ${viewModel.lengthUnit.symbol}', style: TextStyle(fontSize: 9.5, color: theme.textPrimary))),
                      DropdownMenuItem(value: 0.01, child: Text('0.01 ${viewModel.lengthUnit.symbol}', style: TextStyle(fontSize: 9.5, color: theme.textPrimary))),
                      DropdownMenuItem(value: 0.001, child: Text('0.001 ${viewModel.lengthUnit.symbol}', style: TextStyle(fontSize: 9.5, color: theme.textPrimary))),
                      DropdownMenuItem(value: 0.0001, child: Text('0.0001 ${viewModel.lengthUnit.symbol}', style: TextStyle(fontSize: 9.5, color: theme.textPrimary))),
                    ],
                    onChanged: (val) {
                      if (val != null) viewModel.setMeasurementSettings(snapStep: val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 6. Display units format checkbox (SS2)
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: viewModel.displayUnitsFormat,
                  activeColor: theme.accentSky,
                  checkColor: Colors.white,
                  side: BorderSide(color: theme.inputBorder, width: 1.0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) {
                    viewModel.setMeasurementSettings(showUnitsFormat: val ?? true);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Display units format',
                  style: TextStyle(fontSize: 10, color: theme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 7. Force display of 0" checkbox (SS2)
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: viewModel.forceDisplayInchesZero,
                  activeColor: theme.accentSky,
                  checkColor: Colors.white,
                  side: BorderSide(color: theme.inputBorder, width: 1.0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) {
                    viewModel.setMeasurementSettings(forceZeroInches: val ?? false);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Force display of 0"',
                  style: TextStyle(
                    fontSize: 10,
                    color: viewModel.lengthUnit == MeasurementLengthUnit.inches || viewModel.lengthUnit == MeasurementLengthUnit.feet
                        ? theme.textPrimary
                        : theme.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Divider and Angle Units Header (SS2)
          Divider(height: 1, color: theme.panelBorder),
          const SizedBox(height: 8),
          Text(
            'Angle Units',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.textPrimary),
          ),
          const SizedBox(height: 8),

          // 8. Angle & Display precision (SS2)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Angle', theme),
                    const SizedBox(height: 3),
                    _buildDropdownContainer(
                      theme: theme,
                      child: DropdownButton<MeasurementAngleUnit>(
                        value: viewModel.angleUnit,
                        isExpanded: true,
                        dropdownColor: theme.cardBackground,
                        style: TextStyle(fontSize: 10, color: theme.textPrimary),
                        items: MeasurementAngleUnit.values.map((u) {
                          return DropdownMenuItem(value: u, child: Text(u.label, style: TextStyle(fontSize: 10, color: theme.textPrimary)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) viewModel.setMeasurementSettings(angle: val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Display precision', theme),
                    const SizedBox(height: 3),
                    _buildDropdownContainer(
                      theme: theme,
                      child: DropdownButton<int>(
                        value: viewModel.angleDisplayPrecision,
                        isExpanded: true,
                        dropdownColor: theme.cardBackground,
                        style: TextStyle(fontSize: 10, color: theme.textPrimary),
                        items: [
                          DropdownMenuItem(value: 0, child: Text('0', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                          DropdownMenuItem(value: 1, child: Text('0.0', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                          DropdownMenuItem(value: 2, child: Text('0.00', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                          DropdownMenuItem(value: 3, child: Text('0.000', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
                        ],
                        onChanged: (val) {
                          if (val != null) viewModel.setMeasurementSettings(anglePrecision: val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 9. Enable angle snapping checkbox & snap degree (SS2)
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: viewModel.enableAngleSnapping,
                  activeColor: theme.accentSky,
                  checkColor: Colors.white,
                  side: BorderSide(color: theme.inputBorder, width: 1.0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) {
                    viewModel.setMeasurementSettings(angleSnapping: val ?? true);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Enable angle snapping',
                  style: TextStyle(fontSize: 10, color: theme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 74,
                child: _buildDropdownContainer(
                  theme: theme,
                  child: DropdownButton<double>(
                    value: viewModel.angleSnapDegrees,
                    isExpanded: true,
                    dropdownColor: theme.cardBackground,
                    style: TextStyle(fontSize: 10, color: theme.textPrimary),
                    items: const [
                      DropdownMenuItem(value: 1.0, child: Text('1.0', style: TextStyle(fontSize: 10))),
                      DropdownMenuItem(value: 5.0, child: Text('5.0', style: TextStyle(fontSize: 10))),
                      DropdownMenuItem(value: 15.0, child: Text('15.0', style: TextStyle(fontSize: 10))),
                      DropdownMenuItem(value: 30.0, child: Text('30.0', style: TextStyle(fontSize: 10))),
                      DropdownMenuItem(value: 45.0, child: Text('45.0', style: TextStyle(fontSize: 10))),
                    ],
                    onChanged: (val) {
                      if (val != null) viewModel.setMeasurementSettings(angleSnapStep: val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static List<DropdownMenuItem<int>> _buildLengthPrecisionItems(MeasurementLengthUnit unit, AssemblyStudioTheme theme) {
    return [
      DropdownMenuItem(value: 0, child: Text('0 ${unit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
      DropdownMenuItem(value: 1, child: Text('0.0 ${unit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
      DropdownMenuItem(value: 2, child: Text('0.00 ${unit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
      DropdownMenuItem(value: 3, child: Text('0.000 ${unit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
      DropdownMenuItem(value: 4, child: Text('0.0000 ${unit.symbol}', style: TextStyle(fontSize: 10, color: theme.textPrimary))),
    ];
  }

  Widget _buildFieldLabel(String label, AssemblyStudioTheme theme) {
    return Text(
      label,
      style: TextStyle(fontSize: 9.5, color: theme.textSecondary, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildDropdownContainer({required AssemblyStudioTheme theme, required Widget child}) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: theme.inputBackground,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: theme.inputBorder, width: 0.8),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }
}
