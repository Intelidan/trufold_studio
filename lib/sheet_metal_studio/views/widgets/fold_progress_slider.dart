// =============================================================================
// fold_progress_slider.dart
//
// Interactive Bottom Dock for Sheet Metal Folding Progression.
// Connects 2D flat drawing and 3D folded model with smooth real-time slider,
// preset buttons (0% Flat, 50% Forming, 100% Folded), auto-play animation,
// and Press Brake CAM Step-by-Step validation mode with collision inspection.
// Light CAD theme with Sky Blue accents.
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class FoldProgressSlider extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;

  const FoldProgressSlider({super.key, required this.viewModel});

  @override
  State<FoldProgressSlider> createState() => _FoldProgressSliderState();
}

class _FoldProgressSliderState extends State<FoldProgressSlider> {
  Timer? _animTimer;
  bool _isAnimating = false;
  double _animDirection = 1.0;

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  void _toggleAutoPlay() {
    if (_isAnimating) {
      _animTimer?.cancel();
      setState(() => _isAnimating = false);
    } else {
      setState(() => _isAnimating = true);
      _animTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
        double next = widget.viewModel.foldProgress + (0.015 * _animDirection);
        if (next >= 1.0) {
          next = 1.0;
          _animDirection = -1.0;
        } else if (next <= 0.0) {
          next = 0.0;
          _animDirection = 1.0;
        }
        widget.viewModel.setFoldProgress(next);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final isStepMode = vm.isStepMode;
    final totalBends = vm.document.bends.length;

    return Container(
      height: 72.0,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: isStepMode ? _buildStepCamDock(vm, totalBends) : _buildContinuousDock(vm),
    );
  }

  /// 1. Continuous Slider Dock
  Widget _buildContinuousDock(SheetMetalStudioViewModel vm) {
    final t = vm.foldProgress;
    final pct = (t * 100).toInt();

    String statusLabel;
    Color statusColor;
    if (t <= 0.01) {
      statusLabel = 'FLAT BLANK (CNC Laser / Punching)';
      statusColor = const Color(0xFF0284C7);
    } else if (t >= 0.99) {
      statusLabel = '3D FORMED PRODUCT (Press Brake Complete)';
      statusColor = const Color(0xFF059669);
    } else {
      statusLabel = 'PRESS BRAKE FORMING ($pct%)';
      statusColor = const Color(0xFFD97706);
    }

    return Row(
      children: [
        // Play / Pause Animation Button
        IconButton(
          icon: Icon(
            _isAnimating ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: const Color(0xFF0284C7),
            size: 32,
          ),
          tooltip: _isAnimating ? 'Pause Folding' : 'Play Folding Simulation',
          onPressed: _toggleAutoPlay,
        ),
        const SizedBox(width: 8),

        // Status & Stage Title
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'K-Factor: ${vm.document.material.kFactor.toStringAsFixed(2)} | Thickness: ${vm.document.material.thicknessMm}mm',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
            ),
          ],
        ),
        const SizedBox(width: 16),

        // Interactive Progress Slider
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4.0,
              activeTrackColor: const Color(0xFF0284C7),
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFF0284C7),
              overlayColor: const Color(0xFF0284C7).withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
            ),
            child: Slider(
              value: t,
              min: 0.0,
              max: 1.0,
              onChanged: (val) {
                if (_isAnimating) {
                  _animTimer?.cancel();
                  setState(() => _isAnimating = false);
                }
                vm.setFoldProgress(val);
              },
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Quick Preset Buttons
        _presetButton('0% Flat', 0.0),
        _presetButton('50%', 0.5),
        _presetButton('100% 3D', 1.0),

        const SizedBox(width: 8),
        _modeToggleButton(isStep: false, onToggle: vm.toggleStepMode),
      ],
    );
  }

  /// 2. Step-by-Step CAM Dock
  Widget _buildStepCamDock(SheetMetalStudioViewModel vm, int totalBends) {
    if (totalBends == 0) {
      return Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          const Text('No bends present in workpiece.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const Spacer(),
          _modeToggleButton(isStep: true, onToggle: vm.toggleStepMode),
        ],
      );
    }

    final currentStep = vm.currentBendStep.clamp(1, totalBends);
    final seq = vm.bendSequence;
    final currentBendId = (currentStep <= seq.length) ? seq[currentStep - 1] : '';
    final report = vm.bendSequenceReport;
    final stepData = report.stepForBend(currentBendId);
    final hasCollision = stepData?.hasCollision ?? false;

    return Row(
      children: [
        // Previous Step Button
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 22),
          color: currentStep > 1 ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
          tooltip: 'Previous Bend Step',
          onPressed: currentStep > 1 ? () => vm.setBendStep(currentStep - 1) : null,
        ),

        // Next Step Button
        IconButton(
          icon: const Icon(Icons.skip_next, size: 22),
          color: currentStep < totalBends ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
          tooltip: 'Next Bend Step',
          onPressed: currentStep < totalBends ? () => vm.setBendStep(currentStep + 1) : null,
        ),

        const SizedBox(width: 8),

        // Current Step Info
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'STEP $currentStep OF $totalBends: BEND $currentBendId',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                // Collision / Clear Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasCollision ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: hasCollision ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasCollision ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                        size: 11,
                        color: hasCollision ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        hasCollision ? 'TOOL COLLISION' : 'CLEAR',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: hasCollision ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              hasCollision
                  ? (stepData?.reason ?? 'Flange interferes with upper punch tooling.')
                  : 'Punch clearance verified. Ready for press-brake cycle.',
              style: TextStyle(
                color: hasCollision ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                fontSize: 10,
              ),
            ),
          ],
        ),

        const SizedBox(width: 16),

        // Step Dots Timeline
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(totalBends, (index) {
                final stepNum = index + 1;
                final bendId = index < seq.length ? seq[index] : '';
                final isCurrent = stepNum == currentStep;
                final isPast = stepNum < currentStep;
                final stepCol = report.stepForBend(bendId)?.hasCollision ?? false;

                Color dotColor;
                if (stepCol) {
                  dotColor = const Color(0xFFEF4444);
                } else if (isCurrent) {
                  dotColor = const Color(0xFF0284C7);
                } else if (isPast) {
                  dotColor = const Color(0xFF10B981);
                } else {
                  dotColor = const Color(0xFFCBD5E1);
                }

                return InkWell(
                  onTap: () => vm.setBendStep(stepNum),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCurrent ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                        width: isCurrent ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$stepNum: $bendId',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent ? const Color(0xFF0284C7) : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Auto-Sequence Action Button
        Tooltip(
          message: 'Sort bends automatically for collision-free folding sequence',
          child: InkWell(
            onTap: vm.autoSequenceBends,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.auto_fix_high, size: 12, color: Color(0xFF16A34A)),
                  SizedBox(width: 4),
                  Text(
                    'Auto-Seq',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Mode Toggle Button
        _modeToggleButton(isStep: true, onToggle: vm.toggleStepMode),
      ],
    );
  }

  Widget _presetButton(String label, double target) {
    final active = (widget.viewModel.foldProgress - target).abs() < 0.02;

    return InkWell(
      onTap: () {
        if (_isAnimating) {
          _animTimer?.cancel();
          setState(() => _isAnimating = false);
        }
        widget.viewModel.setFoldProgress(target);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF0284C7) : const Color(0xFF475569),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _modeToggleButton({required bool isStep, required VoidCallback onToggle}) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isStep ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isStep ? const Color(0xFF3B82F6) : const Color(0xFFCBD5E1),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isStep ? Icons.alt_route : Icons.format_list_numbered,
              size: 13,
              color: isStep ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
            ),
            const SizedBox(width: 4),
            Text(
              isStep ? 'Step CAM' : 'Step Mode',
              style: TextStyle(
                color: isStep ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
