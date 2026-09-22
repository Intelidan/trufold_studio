// =============================================================================
// cms_teach_scaling_overlay.dart
//
// Interactive Floating Control Overlay for Parametric Template Scaling.
// Features:
// - Draggable floating panel that users can reposition freely over the canvas
// - Compact, non-intrusive CAD layout without verbose clutter
// - Seamless multi-parameter morphing (Width + Height simultaneously)
// =============================================================================

import 'package:flutter/material.dart';
import '../../../engine/cms/cms_scaling_controller.dart';
import '../../../models/cms/cms_product_contract.dart';

class CmsTeachScalingOverlay extends StatefulWidget {
  final CmsScalingController controller;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const CmsTeachScalingOverlay({
    super.key,
    required this.controller,
    required this.onAccept,
    required this.onCancel,
  });

  @override
  State<CmsTeachScalingOverlay> createState() => _CmsTeachScalingOverlayState();
}

class _CmsTeachScalingOverlayState extends State<CmsTeachScalingOverlay> {
  Offset _dragOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final param = widget.controller.activeParameter;
        if (param == null) return const SizedBox.shrink();

        final previewVal = widget.controller.previewMorphValue;
        final baselineVal = param.baselineValue;
        final delta = previewVal - baselineVal;

        final profileName = widget.controller.effectiveScalingProfile == CmsScalingProfile.insideRiser
            ? '45° Inside Riser'
            : widget.controller.effectiveScalingProfile.displayName;

        return Transform.translate(
          offset: _dragOffset,
          child: Card(
            elevation: 8.0,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
              side: const BorderSide(color: Color(0xFFBAE6FD), width: 1.2),
            ),
            child: Container(
              width: 360.0,
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Draggable Header Bar
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        _dragOffset += details.delta;
                      });
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: Row(
                        children: [
                          const Icon(Icons.drag_indicator, size: 16.0, color: Color(0xFF64748B)),
                          const SizedBox(width: 4.0),
                          const Text(
                            'TEMPLATE SCALING',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: Text(
                              profileName,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6.0),
                          IconButton(
                            icon: const Icon(Icons.close, size: 17.0, color: Color(0xFF64748B)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: widget.onCancel,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10.0),

                  // Multi-Port Fitting Configuration (Tee & Cross)
                  if (widget.controller.isMultiPortFitting) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6.0),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => widget.controller.togglePortLinking(true),
                              borderRadius: BorderRadius.circular(4.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: widget.controller.isLinkedPorts ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4.0),
                                  boxShadow: widget.controller.isLinkedPorts
                                      ? [const BoxShadow(color: Color(0x10000000), blurRadius: 2, offset: Offset(0, 1))]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.link,
                                      size: 13.0,
                                      color: widget.controller.isLinkedPorts ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 4.0),
                                    Text(
                                      'Equal (Linked)',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: widget.controller.isLinkedPorts ? FontWeight.bold : FontWeight.w500,
                                        color: widget.controller.isLinkedPorts ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => widget.controller.togglePortLinking(false),
                              borderRadius: BorderRadius.circular(4.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: !widget.controller.isLinkedPorts ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4.0),
                                  boxShadow: !widget.controller.isLinkedPorts
                                      ? [const BoxShadow(color: Color(0x10000000), blurRadius: 2, offset: Offset(0, 1))]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.link_off,
                                      size: 13.0,
                                      color: !widget.controller.isLinkedPorts ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 4.0),
                                    Text(
                                      'Unequal (Independent)',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: !widget.controller.isLinkedPorts ? FontWeight.bold : FontWeight.w500,
                                        color: !widget.controller.isLinkedPorts ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8.0),

                    // Port Selector Row when in Unequal Mode
                    if (!widget.controller.isLinkedPorts) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(widget.controller.baselinePorts.length, (idx) {
                            final port = widget.controller.baselinePorts[idx];
                            final isSelected = idx == widget.controller.activePortIndex;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: ChoiceChip(
                                label: Text('Port ${idx + 1} (${port.width.toInt()}×${port.height.toInt()})'),
                                selected: isSelected,
                                selectedColor: const Color(0xFFEDE9FE),
                                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
                                labelStyle: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFF475569),
                                ),
                                onSelected: (_) => widget.controller.setActivePortIndex(idx),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                    ],
                  ],

                  // Parameter Tabs (Width vs Height)
                  Row(
                    children: (widget.controller.isLinkedPorts
                            ? widget.controller.model.parameters.values.toList()
                            : widget.controller.model.parameters.values.where((p) {
                                final prefix = 'port${widget.controller.activePortIndex + 1}_';
                                return p.id.startsWith(prefix);
                              }).toList())
                        .map((p) {
                      final isSelected = p.id == widget.controller.activeParameterId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          label: Text('${p.displayName} (${p.currentValue.toStringAsFixed(0)} mm)'),
                          selected: isSelected,
                          selectedColor: const Color(0xFFE0F2FE),
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                          labelStyle: TextStyle(
                            fontSize: 11.0,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF334155),
                          ),
                          onSelected: (_) => widget.controller.selectParameter(p.id),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10.0),

                  // Morph Slider Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              param.displayName,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              '${previewVal.toStringAsFixed(1)} mm (${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)} mm)',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4.0),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFF0284C7),
                            inactiveTrackColor: const Color(0xFFCBD5E1),
                            thumbColor: const Color(0xFF0284C7),
                            overlayColor: const Color(0x290284C7),
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                          ),
                          child: Slider(
                            value: previewVal.clamp(param.minValidMm, param.maxValidMm),
                            min: param.minValidMm,
                            max: param.maxValidMm,
                            divisions: ((param.maxValidMm - param.minValidMm) / 5.0).round().clamp(1, 500),
                            onChanged: (val) => widget.controller.evaluateMorph(val),
                          ),
                        ),
                        // Regular Preset Sizes (Width: 50, 100, 150, 225, 300, 450, 600, 750 / Height: 50, 75, 100, 150, 200)
                        const SizedBox(height: 4.0),
                        Wrap(
                          spacing: 4.0,
                          runSpacing: 4.0,
                          children: (param.id == 'width'
                                  ? const [50.0, 100.0, 150.0, 225.0, 300.0, 450.0, 600.0, 750.0]
                                  : const [50.0, 75.0, 100.0, 150.0, 200.0])
                              .map((size) {
                            final isSelected = (previewVal - size).abs() < 0.5;
                            return InkWell(
                              onTap: () => widget.controller.evaluateMorph(size),
                              borderRadius: BorderRadius.circular(4.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 3.0),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(4.0),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                                    width: 1.0,
                                  ),
                                ),
                                child: Text(
                                  '${size.toInt()}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8.0),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Baseline: ${baselineVal.toStringAsFixed(0)} mm',
                              style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF0284C7),
                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 0.0),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.restart_alt, size: 12.0),
                              label: const Text('Reset', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w600)),
                              onPressed: () => widget.controller.resetToBaseline(),
                            ),
                            Text(
                              'Max: ${param.maxValidMm.toStringAsFixed(0)} mm',
                              style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12.0),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                          ),
                          icon: const Icon(Icons.check, size: 15.0),
                          label: const Text(
                            'Apply Scaling',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0),
                          ),
                          onPressed: widget.onAccept,
                        ),
                      ),
                      const SizedBox(width: 6.0),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
                        ),
                        onPressed: widget.onCancel,
                        child: const Text('Cancel', style: TextStyle(fontSize: 11.5)),
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
}
