// =============================================================================
// cms_teach_scaling_overlay.dart
//
// Best-in-class, user-friendly interactive floating overlay for Parametric
// Template Scaling.
//
// Features:
// - Non-intrusive, floating draggable CAD card (390px width)
// - Live real-time port specifications on each tab (e.g. Port 1: 50×150)
// - Segmented Width / Height switcher with directional iconography
// - Real-time Coupler Hole indicator (2 slots >= 95mm vs 1 slot < 95mm)
// - Quick fine-tuning steppers ([-5] and [+5]) + Direct tap-to-type numerical edit
// - Fast preset pills (including 95mm transition threshold)
// - Reversible Baseline Reset and high-contrast Apply Scaling action
// =============================================================================

import 'package:flutter/material.dart';

import '../../../engine/cms/cms_scaling_controller.dart';
import '../../../engine/cms/tray_unequal_tee_scaler.dart';

class CmsTeachScalingOverlay extends StatefulWidget {
  final CmsScalingController controller;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const CmsTeachScalingOverlay({super.key, required this.controller, required this.onAccept, required this.onCancel});

  @override
  State<CmsTeachScalingOverlay> createState() => _CmsTeachScalingOverlayState();
}

class _CmsTeachScalingOverlayState extends State<CmsTeachScalingOverlay> {
  Offset _dragOffset = Offset.zero;
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  bool _isEditingText = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double _getPortWidth(int idx) {
    final id = 'port${idx + 1}_width';
    if (widget.controller.activeParameterId == id) {
      return widget.controller.previewMorphValue;
    }
    return widget.controller.model.parameters[id]?.currentValue ??
        (idx < widget.controller.baselinePorts.length ? widget.controller.baselinePorts[idx].width : 100.0);
  }

  double _getPortHeight(int idx) {
    final id = 'port${idx + 1}_height';
    if (widget.controller.activeParameterId == id) {
      return widget.controller.previewMorphValue;
    }
    return widget.controller.model.parameters[id]?.currentValue ??
        (idx < widget.controller.baselinePorts.length ? widget.controller.baselinePorts[idx].height : 100.0);
  }

  String _getPortDescriptor(int idx) {
    if (widget.controller.baselinePorts.length == 3) {
      if (TrayUnequalTeeScaler.isTrayUnequalTee(widget.controller.baselineDocument)) {
        switch (idx) {
          case 0:
            return 'Left';
          case 1:
            return 'Right';
          case 2:
            return 'Branch';
        }
      }
      switch (idx) {
        case 0:
          return 'Branch';
        case 1:
          return 'Right';
        case 2:
          return 'Main';
      }
    } else if (widget.controller.baselinePorts.length == 4) {
      if (idx < widget.controller.baselinePorts.length) {
        final port = widget.controller.baselinePorts[idx];
        final nx = port.normal.x;
        final ny = port.normal.y;
        if (nx < -0.5) return 'West';
        if (nx > 0.5) return 'East';
        if (ny < -0.5) return 'North';
        if (ny > 0.5) return 'South';
      }
      switch (idx) {
        case 0:
          return 'West';
        case 1:
          return 'North';
        case 2:
          return 'East';
        case 3:
          return 'South';
      }
    }
    return 'P${idx + 1}';
  }

  void _stepValue(double step, double minVal, double maxVal, double currentVal) {
    final next = (currentVal + step).clamp(minVal, maxVal);
    widget.controller.evaluateMorph(next);
  }

  void _commitText(String text, double minVal, double maxVal) {
    final parsed = double.tryParse(text.trim());
    if (parsed != null) {
      final clamped = parsed.clamp(minVal, maxVal);
      widget.controller.evaluateMorph(clamped);
    }
    setState(() {
      _isEditingText = false;
    });
  }

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
        final isHeight = param.id.endsWith('_height') || param.id == 'height';
        final isRadius = param.id == 'radius';

        final profileName = widget.controller.effectiveScalingProfile.displayName.isNotEmpty
            ? widget.controller.effectiveScalingProfile.displayName
            : (widget.controller.contract.displayName.isNotEmpty
                ? widget.controller.contract.displayName
                : 'CMS Fitting');

        final isMultiPort = !widget.controller.isLinkedPorts && widget.controller.baselinePorts.length >= 3;
        final activePortIdx = widget.controller.activePortIndex;

        return Transform.translate(
          offset: _dragOffset,
          child: Card(
            elevation: 10.0,
            shadowColor: const Color(0x330F172A),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.0),
              side: const BorderSide(color: Color(0xFFBAE6FD), width: 1.4),
            ),
            child: Container(
              width: 390.0,
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Draggable Header Bar
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
                            style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: 0.6),
                          ),
                          const Spacer(),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(5.0),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: Text(
                                profileName,
                                style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6.0),
                          IconButton(
                            icon: const Icon(Icons.close, size: 17.0, color: Color(0xFF64748B)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Close',
                            onPressed: widget.onCancel,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10.0),

                  // 2. Multi-Port Navigator with Live Dimensions (Unequal Tee & Cross)
                  if (isMultiPort) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(widget.controller.baselinePorts.length, (idx) {
                          final isSelected = idx == activePortIdx;
                          final curW = _getPortWidth(idx);
                          final curH = _getPortHeight(idx);
                          final descriptor = _getPortDescriptor(idx);

                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: InkWell(
                              onTap: () => widget.controller.setActivePortIndex(idx),
                              borderRadius: BorderRadius.circular(8.0),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.5),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFEDE9FE) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: Border.all(color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFFE2E8F0), width: isSelected ? 1.5 : 1.0),
                                  boxShadow: isSelected ? [const BoxShadow(color: Color(0x1F7C3AED), blurRadius: 4.0, offset: Offset(0, 1.5))] : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                      size: 13.0,
                                      color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 4.0),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Port ${idx + 1} ($descriptor)',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                            color: isSelected ? const Color(0xFF5B21B6) : const Color(0xFF475569),
                                          ),
                                        ),
                                        Text(
                                          '${curW.toStringAsFixed(0)} × ${curH.toStringAsFixed(0)} mm',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'monospace',
                                            color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFF1E293B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 8.0),

                    // 3. Segmented Dimension Selector: Width vs Height
                    Row(
                      children: [
                        Expanded(
                          child: _buildDimensionSegment(
                            title: 'Width',
                            icon: Icons.swap_horiz,
                            dimensionValue: _getPortWidth(activePortIdx),
                            isSelected: !isHeight,
                            activeColor: const Color(0xFF0284C7),
                            activeBg: const Color(0xFFE0F2FE),
                            onTap: () {
                              widget.controller.selectParameter('port${activePortIdx + 1}_width');
                            },
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: _buildDimensionSegment(
                            title: 'Height',
                            icon: Icons.height,
                            dimensionValue: _getPortHeight(activePortIdx),
                            isSelected: isHeight,
                            activeColor: const Color(0xFF7C3AED),
                            activeBg: const Color(0xFFEDE9FE),
                            onTap: () {
                              widget.controller.selectParameter('port${activePortIdx + 1}_height');
                            },
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // For Linked / Single-Port fittings
                    Wrap(
                      spacing: 6.0,
                      runSpacing: 4.0,
                      children: widget.controller.model.parameters.values.map((p) {
                        final isSelected = p.id == widget.controller.activeParameterId;
                        return ChoiceChip(
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
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 10.0),

                  // 4. Interactive Dimension Control Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11.0, vertical: 9.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row A: Dimension Name, Delta Badge & Coupler Hole Pill
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                param.displayName,
                                style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (delta.abs() > 0.05)
                              Container(
                                margin: const EdgeInsets.only(right: 6.0),
                                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: delta > 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                child: Text(
                                  '${delta > 0 ? "+" : ""}${delta.toStringAsFixed(1)} mm',
                                  style: TextStyle(
                                    fontSize: 10.0,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: delta > 0 ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            // Coupler Hole Status indicator when adjusting Height
                            if (isHeight)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                decoration: BoxDecoration(
                                  color: previewVal >= 95.0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4.0),
                                  border: Border.all(color: previewVal >= 95.0 ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6.0,
                                      height: 6.0,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: previewVal >= 95.0 ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                      ),
                                    ),
                                    const SizedBox(width: 4.0),
                                    Text(
                                      previewVal >= 95.0 ? '2 Slots (≥95mm)' : '1 Slot (<95mm)',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: previewVal >= 95.0 ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8.0),

                        // Row B: Quick Stepper Buttons [-5] & [+5] + Direct Numerical Input
                        Row(
                          children: [
                            // Decrement button
                            _buildStepButton(
                              icon: Icons.remove,
                              label: '-5',
                              tooltip: 'Decrease by 5 mm',
                              onPressed: () => _stepValue(-5.0, param.minValidMm, param.maxValidMm, previewVal),
                            ),
                            const SizedBox(width: 6.0),

                            // Value display with tap-to-type capability
                            Expanded(
                              child: _isEditingText
                                  ? SizedBox(
                                      height: 32.0,
                                      child: TextField(
                                        controller: _textController,
                                        focusNode: _focusNode,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Color(0xFF0F172A)),
                                        decoration: InputDecoration(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(6.0),
                                            borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                                          ),
                                          suffixText: 'mm',
                                          suffixStyle: const TextStyle(fontSize: 10.0, color: Color(0xFF64748B)),
                                        ),
                                        onSubmitted: (val) => _commitText(val, param.minValidMm, param.maxValidMm),
                                      ),
                                    )
                                  : InkWell(
                                      onTap: () {
                                        setState(() {
                                          _isEditingText = true;
                                          _textController.text = previewVal.toStringAsFixed(0);
                                        });
                                        _focusNode.requestFocus();
                                      },
                                      borderRadius: BorderRadius.circular(6.0),
                                      child: Container(
                                        height: 32.0,
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6.0),
                                          border: Border.all(color: const Color(0xFFCBD5E1)),
                                        ),
                                        alignment: Alignment.center,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '${previewVal.toStringAsFixed(1)} mm',
                                              style: TextStyle(
                                                fontSize: 13.0,
                                                fontWeight: FontWeight.w800,
                                                fontFamily: 'monospace',
                                                color: isHeight ? const Color(0xFF7C3AED) : const Color(0xFF0284C7),
                                              ),
                                            ),
                                            const SizedBox(width: 4.0),
                                            const Icon(Icons.edit, size: 12.0, color: Color(0xFF94A3B8)),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 6.0),

                            // Increment button
                            _buildStepButton(
                              icon: Icons.add,
                              label: '+5',
                              tooltip: 'Increase by 5 mm',
                              onPressed: () => _stepValue(5.0, param.minValidMm, param.maxValidMm, previewVal),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6.0),

                        // Row C: Smooth Slider
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: isHeight ? const Color(0xFF7C3AED) : const Color(0xFF0284C7),
                            inactiveTrackColor: const Color(0xFFCBD5E1),
                            thumbColor: isHeight ? const Color(0xFF7C3AED) : const Color(0xFF0284C7),
                            overlayColor: isHeight ? const Color(0x297C3AED) : const Color(0x290284C7),
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                          ),
                          child: Slider(
                            value: previewVal.clamp(param.minValidMm, param.maxValidMm),
                            min: param.minValidMm,
                            max: param.maxValidMm,
                            divisions: ((param.maxValidMm - param.minValidMm) / 5.0).round().clamp(1, 500),
                            onChanged: (val) {
                              if (_isEditingText) {
                                setState(() => _isEditingText = false);
                              }
                              widget.controller.evaluateMorph(val);
                            },
                          ),
                        ),

                        // Row D: Quick Presets (Including 95mm for height)
                        Wrap(
                          spacing: 4.5,
                          runSpacing: 4.0,
                          children: (isRadius
                                  ? const [180.0, 300.0, 600.0, 900.0]
                                  : (isHeight
                                      ? const [50.0, 75.0, 95.0, 100.0, 150.0, 200.0, 250.0]
                                      : const [50.0, 75.0, 100.0, 150.0, 200.0, 300.0, 450.0, 600.0, 900.0, 1200.0]))
                              .map((size) {
                            final isSelected = (previewVal - size).abs() < 0.5;
                            final isThreshold = isHeight && size == 95.0;
                            return InkWell(
                              onTap: () {
                                if (_isEditingText) {
                                  setState(() => _isEditingText = false);
                                }
                                widget.controller.evaluateMorph(size);
                              },
                              borderRadius: BorderRadius.circular(5.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isHeight ? const Color(0xFF7C3AED) : const Color(0xFF0284C7))
                                      : (isThreshold ? const Color(0xFFF0FDF4) : const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(5.0),
                                  border: Border.all(
                                    color: isSelected
                                        ? (isHeight ? const Color(0xFF7C3AED) : const Color(0xFF0284C7))
                                        : (isThreshold ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1)),
                                    width: isThreshold && !isSelected ? 1.2 : 1.0,
                                  ),
                                ),
                                child: Text(
                                  '${size.toInt()}${isThreshold ? "★" : ""}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? Colors.white : (isThreshold ? const Color(0xFF15803D) : const Color(0xFF1E293B)),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8.0),

                        // Row E: Baseline, Reset, Max
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Baseline: ${baselineVal.toStringAsFixed(0)} mm',
                                style: const TextStyle(fontSize: 10.0, color: Color(0xFF64748B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                if (_isEditingText) {
                                  setState(() => _isEditingText = false);
                                }
                                widget.controller.resetToBaseline();
                              },
                              borderRadius: BorderRadius.circular(4.0),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.restart_alt, size: 13.0, color: Color(0xFF0284C7)),
                                    SizedBox(width: 2.0),
                                    Text(
                                      'Reset',
                                      style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.w700, color: Color(0xFF0284C7)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                'Max: ${param.maxValidMm.toStringAsFixed(0)} mm',
                                style: const TextStyle(fontSize: 10.0, color: Color(0xFF64748B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.controller.isCurrentTrayAccessory) ...[
                    _buildPerforationControlCard(),
                    _buildCouplerFlapsCard(),
                  ],
                  const SizedBox(height: 12.0),

                  // 5. Action Buttons (Apply Scaling & Cancel)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            elevation: 1.5,
                            shadowColor: const Color(0x33059669),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            padding: const EdgeInsets.symmetric(vertical: 9.0),
                          ),
                          icon: const Icon(Icons.check_circle_rounded, size: 16.0),
                          label: const Text('Apply Scaling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                          onPressed: widget.onAccept,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                          padding: const EdgeInsets.symmetric(vertical: 9.0, horizontal: 12.0),
                        ),
                        onPressed: widget.onCancel,
                        child: const Text('Cancel', style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600)),
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

  Widget _buildDimensionSegment({
    required String title,
    required IconData icon,
    required double dimensionValue,
    required bool isSelected,
    required Color activeColor,
    required Color activeBg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 5.0),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(7.0),
          border: Border.all(color: isSelected ? activeColor : const Color(0xFFE2E8F0), width: isSelected ? 1.4 : 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13.0, color: isSelected ? activeColor : const Color(0xFF64748B)),
            const SizedBox(width: 4.0),
            Text(
              '$title: ',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : const Color(0xFF475569),
              ),
            ),
            Text(
              '${dimensionValue.toStringAsFixed(0)}mm',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: isSelected ? activeColor : const Color(0xFF0F172A)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepButton({required IconData icon, required String label, required String tooltip, required VoidCallback onPressed}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6.0),
        child: Container(
          height: 32.0,
          padding: const EdgeInsets.symmetric(horizontal: 7.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6.0),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13.0, color: const Color(0xFF475569)),
              Text(
                label.replaceFirst('+', '').replaceFirst('-', ''),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPerforationControlCard() {
    final pitch = widget.controller.perforationPitch;
    final totalPunches = widget.controller.currentPreview?.scaledDocument.punches.length ??
        widget.controller.baselineDocument.punches.length;

    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9.0),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_on_rounded, size: 13.0, color: Color(0xFF0284C7)),
              const SizedBox(width: 5.0),
              const Expanded(
                child: Text(
                  'Perforations Control',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                  '$totalPunches Punches',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Row(
            children: [
              _buildStepButton(
                icon: Icons.remove,
                label: '-25',
                tooltip: 'Decrease pitch by 25 mm (more holes)',
                onPressed: () => widget.controller.setPerforationPitch(pitch - 25.0),
              ),
              const SizedBox(width: 6.0),
              Expanded(
                child: Container(
                  height: 30.0,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5.0),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    'Pitch: ${pitch.toStringAsFixed(0)} mm',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: Color(0xFF0284C7),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6.0),
              _buildStepButton(
                icon: Icons.add,
                label: '+25',
                tooltip: 'Increase pitch by 25 mm (fewer holes)',
                onPressed: () => widget.controller.setPerforationPitch(pitch + 25.0),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF0284C7),
              inactiveTrackColor: const Color(0xFFCBD5E1),
              thumbColor: const Color(0xFF0284C7),
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
            ),
            child: Slider(
              value: pitch.clamp(75.0, 200.0),
              min: 75.0,
              max: 200.0,
              divisions: 25,
              onChanged: (val) => widget.controller.setPerforationPitch(val),
            ),
          ),
          Wrap(
            spacing: 5.0,
            children: [
              _buildPitchPresetChip('Sparse', 150.0, pitch),
              _buildPitchPresetChip('Standard', 100.0, pitch),
              _buildPitchPresetChip('Dense', 75.0, pitch),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPitchPresetChip(String label, double targetPitch, double currentPitch) {
    final isSelected = (currentPitch - targetPitch).abs() < 1.0;
    return InkWell(
      onTap: () => widget.controller.setPerforationPitch(targetPitch),
      borderRadius: BorderRadius.circular(4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: Text(
          '$label (${targetPitch.toInt()}mm)',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _buildCouplerFlapsCard() {
    final hasFlaps = widget.controller.includeCouplerFlaps;
    final flapLen = widget.controller.couplerFlapLength;
    final targetLen = widget.controller.targetCouplerFlapLength;
    final isAnimating = widget.controller.isAnimatingCouplerFlaps;
    final activePortIdx = widget.controller.activePortIndex;
    final activeH = _getPortHeight(activePortIdx);

    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9.0),
        border: Border.all(
          color: hasFlaps ? const Color(0xFF8B5CF6) : const Color(0xFFE2E8F0),
          width: hasFlaps ? 1.3 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded, size: 14.0, color: Color(0xFF7C3AED)),
              const SizedBox(width: 5.0),
              const Expanded(
                child: Text(
                  'Coupler Flaps',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: hasFlaps,
                  activeThumbColor: const Color(0xFF7C3AED),
                  onChanged: (val) => widget.controller.setIncludeCouplerFlaps(val, animate: true),
                ),
              ),
            ],
          ),
          if (hasFlaps || isAnimating) ...[
            const SizedBox(height: 4.0),
            Row(
              children: [
                _buildStepButton(
                  icon: Icons.remove,
                  label: '-5',
                  tooltip: 'Decrease flap length by 5 mm',
                  onPressed: () => widget.controller.setCouplerFlapLength(targetLen - 5.0),
                ),
                const SizedBox(width: 6.0),
                Expanded(
                  child: Container(
                    height: 30.0,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5.0),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Text(
                      isAnimating
                          ? 'Length: ${flapLen.toStringAsFixed(0)} mm'
                          : 'Length: ${targetLen.toStringAsFixed(0)} mm',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6.0),
                _buildStepButton(
                  icon: Icons.add,
                  label: '+5',
                  tooltip: 'Increase flap length by 5 mm',
                  onPressed: () => widget.controller.setCouplerFlapLength(targetLen + 5.0),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF7C3AED),
                inactiveTrackColor: const Color(0xFFCBD5E1),
                thumbColor: const Color(0xFF7C3AED),
                trackHeight: 3.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              ),
              child: Slider(
                value: targetLen.clamp(20.0, 50.0),
                min: 20.0,
                max: 50.0,
                divisions: 6,
                onChanged: isAnimating ? null : (val) => widget.controller.setCouplerFlapLength(val),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 10.0, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 4.0),
                  Expanded(
                    child: Text(
                      activeH <= 50.0
                          ? '2 vertically aligned obround holes (H ≤ 50mm)'
                          : '4 holes (2 rows × 2 cols, H > 50mm)',
                      style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.w600, color: Color(0xFF5B21B6)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2.0),
            const Text(
              'Flap bend angles β(θ) dynamically realign parallel to connecting run',
              style: TextStyle(fontSize: 8.5, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}
