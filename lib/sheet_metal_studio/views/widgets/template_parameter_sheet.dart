// =============================================================================
// template_parameter_sheet.dart
//
// Floating On-Canvas Property Inspector for Active DXF/CAD Template Morphing
// per Phase 1 Master Guide (#36-#48, Milestones P19-P22).
// Allows live parametric modification of catalog fittings:
// - Sliders, steppers, and direct numeric input for driving parameters
// - Standard catalog size chips (e.g. 50, 100, 150, 200, 300, 450, 600, 750, 900 mm)
// - Real-time 2D flat blank & 3D folded mesh regeneration
// - Visual confirmation of invariant relief miters and rigid punch clusters
// =============================================================================

import 'package:flutter/material.dart';
import '../../models/cad_parameter.dart';
import '../../models/template_parameter_definition.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class TemplateParameterSheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final TemplateParameterDefinition template;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const TemplateParameterSheet({
    super.key,
    required this.viewModel,
    required this.template,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF0D9488); // Teal-600 for parametric templates
    final currentValues = viewModel.currentTemplateParams;

    return Container(
      width: 280.0,
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: themeColor.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Drag handle + Icon + Title + Collapse + Close
          GestureDetector(
            onPanStart: onDragStartHeader,
            onPanUpdate: onDragHeader,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.auto_awesome_mosaic_outlined, size: 14, color: themeColor),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Parametric Morphing Engine',
                        style: TextStyle(
                          fontSize: 9,
                          color: themeColor.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onToggleCollapse != null)
                  IconButton(
                    icon: Icon(
                      isCollapsed ? Icons.unfold_more : Icons.unfold_less,
                      size: 15,
                      color: const Color(0xFF64748B),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: isCollapsed ? 'Expand' : 'Collapse',
                    onPressed: onToggleCollapse,
                  ),
                const SizedBox(width: 6),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 15, color: Color(0xFF64748B)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Exit Template Mode',
                    onPressed: onClose,
                  ),
              ],
            ),
          ),

          if (isCollapsed) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: template.parameters.map((param) {
                final val = currentValues[param.id] ?? param.value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${param.id}: ${val.toStringAsFixed(0)}${param.unit}',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
                );
              }).toList(),
            ),
          ] else ...[
            const SizedBox(height: 10),
            // Info banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 12, color: Color(0xFF16A34A)),
                  SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Miters & punch anchors rigidly invariant',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Parameter Controllers
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: template.parameters.length,
                separatorBuilder: (_, _) => const Divider(height: 14, color: Color(0xFFE2E8F0)),
                itemBuilder: (context, index) {
                  final param = template.parameters[index];
                  final val = currentValues[param.id] ?? param.value;
                  return _buildParameterController(param, val);
                },
              ),
            ),

            const SizedBox(height: 10),
            // Footer with Blank Dimensions and Reset Button
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BLANK: ${viewModel.document.blankWidthMm.toStringAsFixed(0)} × ${viewModel.document.blankLengthMm.toStringAsFixed(0)} mm',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'WEIGHT: ${viewModel.partNetWeightKg.toStringAsFixed(2)} kg · ${viewModel.document.punches.length} punches',
                          style: const TextStyle(fontSize: 8.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      for (final entry in template.baselineParameters.entries) {
                        viewModel.updateTemplateParameter(entry.key, entry.value);
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.restart_alt, size: 11, color: Color(0xFF475569)),
                          SizedBox(width: 3),
                          Text(
                            'Reset',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParameterController(CadParameter param, double currentValue) {
    final step = param.step ?? 25.0;
    final minVal = param.minValue ?? 10.0;
    final maxVal = param.maxValue ?? (minVal + 1000.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row + numeric readout
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Tooltip(
                message: param.description ?? param.name,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        param.name,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${param.unit})',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
            // Stepper controls: [-] [value] [+]
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stepButton(
                  icon: Icons.remove,
                  onPressed: currentValue - step >= minVal
                      ? () => viewModel.updateTemplateParameter(param.id, currentValue - step)
                      : null,
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    currentValue.toStringAsFixed(currentValue % 1 == 0 ? 0 : 1),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _stepButton(
                  icon: Icons.add,
                  onPressed: currentValue + step <= maxVal
                      ? () => viewModel.updateTemplateParameter(param.id, currentValue + step)
                      : null,
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 4),

        // Continuous Slider
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2.5,
            activeTrackColor: const Color(0xFF0D9488),
            inactiveTrackColor: const Color(0xFFE2E8F0),
            thumbColor: const Color(0xFF0D9488),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            valueIndicatorTextStyle: const TextStyle(fontSize: 9, color: Colors.white),
          ),
          child: Slider(
            value: currentValue.clamp(minVal, maxVal),
            min: minVal,
            max: maxVal,
            divisions: ((maxVal - minVal) / step).round().clamp(1, 100),
            onChanged: (newVal) {
              viewModel.updateTemplateParameter(param.id, newVal);
            },
          ),
        ),

        // Quick Standard Catalog Size Chips
        if (param.allowedValues != null && param.allowedValues!.isNotEmpty) ...[
          const SizedBox(height: 2),
          SizedBox(
            height: 22,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: param.allowedValues!.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, chipIdx) {
                final chipVal = param.allowedValues![chipIdx];
                final isSelected = (currentValue - chipVal).abs() < 0.1;
                return InkWell(
                  onTap: () => viewModel.updateTemplateParameter(param.id, chipVal),
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFCBD5E1),
                        width: 1.0,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${chipVal.toInt()}',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepButton({required IconData icon, VoidCallback? onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: onPressed != null ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Icon(
          icon,
          size: 11,
          color: onPressed != null ? const Color(0xFF334155) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}
