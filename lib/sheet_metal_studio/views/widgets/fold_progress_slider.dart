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
  final bool? isCollapsed;
  final VoidCallback? onToggleCollapse;

  const FoldProgressSlider({
    super.key,
    required this.viewModel,
    this.isCollapsed,
    this.onToggleCollapse,
  });

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
    final isCollapsed = widget.isCollapsed ?? vm.isFoldSliderCollapsed;
    final onToggle = widget.onToggleCollapse ?? vm.toggleFoldSliderCollapsed;

    if (isCollapsed) {
      return _buildCollapsedDock(vm, onToggle);
    }

    final isCompact = vm.isCompactMode;
    return Container(
      height: isCompact ? 32.0 : 38.0,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 6.0 : 10.0, vertical: 1.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
        boxShadow: [BoxShadow(color: Color(0x06000000), blurRadius: 3, offset: Offset(0, -1.5))],
      ),
      child: isStepMode ? _buildStepCamDock(vm, totalBends, onToggle) : _buildContinuousDock(vm, onToggle),
    );
  }

  /// Collapsed Sleek Dock (Only 20px ultra-thin height, freeing vertical space)
  Widget _buildCollapsedDock(SheetMetalStudioViewModel vm, VoidCallback onToggle) {
    final t = vm.foldProgress;
    final pct = (t * 100).toInt();

    String shortStage;
    Color stageColor;
    if (t <= 0.01) {
      shortStage = 'FLAT (0%)';
      stageColor = const Color(0xFF0284C7);
    } else if (t >= 0.99) {
      shortStage = '3D (100%)';
      stageColor = const Color(0xFF059669);
    } else {
      shortStage = 'FORMING ($pct%)';
      stageColor = const Color(0xFFD97706);
    }

    return Container(
      height: 20.0,
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
        boxShadow: [BoxShadow(color: Color(0x04000000), blurRadius: 2, offset: Offset(0, -1))],
      ),
      child: Row(
        children: [
          // Expand button & title
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Row(
                children: [
                  const Icon(Icons.keyboard_arrow_up, size: 14, color: Color(0xFF0284C7)),
                  const SizedBox(width: 3),
                  const Text(
                    'Fold:',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: stageColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                    child: Text(
                      shortStage,
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: stageColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Slim progress track
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: t,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(stageColor),
                minHeight: 3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Mini Play/Pause button
          IconButton(
            icon: Icon(_isAnimating ? Icons.pause : Icons.play_arrow, size: 14, color: const Color(0xFF0284C7)),
            tooltip: _isAnimating ? 'Pause' : 'Play',
            splashRadius: 10,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            onPressed: _toggleAutoPlay,
          ),
          const SizedBox(width: 4),
          // Expand Icon Tooltip
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(3),
            child: const Tooltip(
              message: 'Expand Folding Dock',
              child: Padding(
                padding: EdgeInsets.all(1.0),
                child: Icon(Icons.open_in_full, size: 11, color: Color(0xFF64748B)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 1. Continuous Slider Dock
  Widget _buildContinuousDock(SheetMetalStudioViewModel vm, VoidCallback onToggle) {
    final t = vm.foldProgress;
    final pct = (t * 100).toInt();
    final isCompact = vm.isCompactMode;

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
          icon: Icon(_isAnimating ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: const Color(0xFF0284C7), size: isCompact ? 20 : 24),
          tooltip: _isAnimating ? 'Pause Folding' : 'Play Folding Simulation',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: isCompact ? 22 : 26, minHeight: isCompact ? 22 : 26),
          onPressed: _toggleAutoPlay,
        ),
        const SizedBox(width: 6),

        // Status & Stage Title
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: isCompact ? 9.0 : 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'K: ${vm.document.material.kFactor.toStringAsFixed(2)} | T: ${vm.document.material.thicknessMm}mm',
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontSize: isCompact ? 8.0 : 9.0,
                height: 1.1,
              ),
            ),
          ],
        ),
        SizedBox(width: isCompact ? 8 : 14),

        // Interactive Progress Slider
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              activeTrackColor: const Color(0xFF0284C7),
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFF0284C7),
              overlayColor: const Color(0xFF0284C7).withValues(alpha: 0.15),
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: isCompact ? 5.5 : 6.5),
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
        const SizedBox(width: 8),

        // Quick Preset Buttons
        _presetButton('0% Flat', 0.0),
        _presetButton('50%', 0.5),
        _presetButton('100% 3D', 1.0),

        const SizedBox(width: 6),
        _modeToggleButton(isStep: false, onToggle: vm.toggleStepMode),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
          tooltip: 'Collapse Folding Dock',
          splashRadius: 12,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          onPressed: onToggle,
        ),
      ],
    );
  }

  /// 2. Step-by-Step CAM Dock
  Widget _buildStepCamDock(SheetMetalStudioViewModel vm, int totalBends, VoidCallback onToggle) {
    final isCompact = vm.isCompactMode;
    if (totalBends == 0) {
      return Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          const Text('No bends present in workpiece.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const Spacer(),
          _modeToggleButton(isStep: true, onToggle: vm.toggleStepMode),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, size: isCompact ? 16 : 20, color: const Color(0xFF64748B)),
            tooltip: 'Collapse Folding Dock',
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: isCompact ? 20 : 26, minHeight: isCompact ? 20 : 26),
            onPressed: onToggle,
          ),
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
          icon: Icon(Icons.skip_previous, size: isCompact ? 18 : 22),
          color: currentStep > 1 ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
          tooltip: 'Previous Bend Step',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: isCompact ? 22 : 28, minHeight: isCompact ? 22 : 28),
          onPressed: currentStep > 1 ? () => vm.setBendStep(currentStep - 1) : null,
        ),

        // Next Step Button
        IconButton(
          icon: Icon(Icons.skip_next, size: isCompact ? 18 : 22),
          color: currentStep < totalBends ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
          tooltip: 'Next Bend Step',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: isCompact ? 22 : 28, minHeight: isCompact ? 22 : 28),
          onPressed: currentStep < totalBends ? () => vm.setBendStep(currentStep + 1) : null,
        ),

        const SizedBox(width: 8),

        // Current Step Info
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'STEP $currentStep OF $totalBends: BEND $currentBendId',
                  style: TextStyle(
                    color: const Color(0xFF0F172A),
                    fontSize: isCompact ? 9.5 : 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 6),
                // Collision / Clear Badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isCompact ? 4 : 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: hasCollision ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(3.5),
                    border: Border.all(color: hasCollision ? const Color(0xFFF87171) : const Color(0xFF4ADE80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasCollision ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                        size: isCompact ? 9.5 : 11,
                        color: hasCollision ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 2.5),
                      Text(
                        hasCollision ? 'TOOL COLLISION' : 'CLEAR',
                        style: TextStyle(
                          fontSize: isCompact ? 8.0 : 9.0,
                          fontWeight: FontWeight.bold,
                          color: hasCollision ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              hasCollision ? (stepData?.reason ?? 'Flange interferes with upper punch tooling.') : 'Punch clearance verified. Ready for press-brake cycle.',
              style: TextStyle(
                color: hasCollision ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                fontSize: isCompact ? 8.5 : 10,
                height: 1.1,
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
                      border: Border.all(color: isCurrent ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0), width: isCurrent ? 1.5 : 1.0),
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
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 5 : 8, vertical: isCompact ? 2 : 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(3.5),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_fix_high, size: isCompact ? 10 : 12, color: const Color(0xFF16A34A)),
                  const SizedBox(width: 3),
                  Text(
                    'Auto-Seq',
                    style: TextStyle(fontSize: isCompact ? 9.0 : 10.0, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 6),

        // Mode Toggle Button
        _modeToggleButton(isStep: true, onToggle: vm.toggleStepMode),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(Icons.keyboard_arrow_down, size: isCompact ? 16 : 18, color: const Color(0xFF64748B)),
          tooltip: 'Collapse Folding Dock',
          splashRadius: 12,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: isCompact ? 20 : 24, minHeight: isCompact ? 20 : 24),
          onPressed: onToggle,
        ),
      ],
    );
  }

  Widget _presetButton(String label, double target) {
    final isCompact = widget.viewModel.isCompactMode;
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
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 8, vertical: isCompact ? 2 : 4),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(3.5),
          border: Border.all(color: active ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0), width: 1.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF0284C7) : const Color(0xFF475569),
            fontSize: isCompact ? 9.5 : 10.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _modeToggleButton({required bool isStep, required VoidCallback onToggle}) {
    final isCompact = widget.viewModel.isCompactMode;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(3.5),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 7, vertical: isCompact ? 2 : 4),
        decoration: BoxDecoration(
          color: isStep ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(3.5),
          border: Border.all(color: isStep ? const Color(0xFF3B82F6) : const Color(0xFFCBD5E1), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isStep ? Icons.alt_route : Icons.format_list_numbered, size: isCompact ? 11 : 12, color: isStep ? const Color(0xFF1D4ED8) : const Color(0xFF475569)),
            const SizedBox(width: 3),
            Text(
              isStep ? 'CAM' : 'Step',
              style: TextStyle(color: isStep ? const Color(0xFF1D4ED8) : const Color(0xFF475569), fontSize: isCompact ? 9.5 : 10.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
