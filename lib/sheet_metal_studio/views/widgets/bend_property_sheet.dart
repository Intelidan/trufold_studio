// =============================================================================
// bend_property_sheet.dart
//
// Floating On-Canvas Property Inspector for selected Press-Brake Bend Lines.
// Allows rapid modification of:
// - Bend direction (UP/DOWN)
// - Angle (30°, 45°, 90°, 135°, custom fine slider)
// - Inside bend radius
// - Interactive CAD Edge Constraints (exact mm distance to Left, Bottom, Right, Top)
// - Immediate real-time refolding
// =============================================================================

import 'package:flutter/material.dart';

import '../../models/fold_bend_line.dart';
import '../../models/sheet_metal_definition.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class BendPropertySheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final FoldBendLine bend;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const BendPropertySheet({
    super.key,
    required this.viewModel,
    required this.bend,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = bend.direction == BendDirection.up;
    final themeColor = bend.isFlange
        ? const Color(0xFF8B5CF6)
        : (isUp ? const Color(0xFF0284C7) : const Color(0xFFD97706));
    final constraints = viewModel.getSelectedBendConstraints();
    final nearestEdgeOffset = viewModel.getNearestEdgeDistance(bend);

    return GestureDetector(
      onPanStart: onDragStartHeader,
      onPanUpdate: onDragHeader,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 220.0,
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6.0),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12.0,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              // Header: Drag handle + ID + Collapse + Close
              Row(
                children: [
                  const Icon(
                    Icons.drag_indicator,
                    size: 12,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: themeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${bend.isFlange ? "FLANGE" : "BEND"} ${bend.id}',
                    style: TextStyle(
                      color: bend.isVisible
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF94A3B8),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      decoration: bend.isVisible
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      bend.isVisible ? Icons.visibility : Icons.visibility_off,
                      size: 15,
                      color: bend.isVisible
                          ? themeColor
                          : const Color(0xFF94A3B8),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    onPressed: () => viewModel.toggleBendVisibility(bend.id),
                    tooltip: bend.isVisible
                        ? 'Hide / Suppress Line'
                        : 'Show / Unsuppress Line',
                  ),
                  const SizedBox(width: 2),
                  if (onToggleCollapse != null) ...[
                    InkWell(
                      onTap: onToggleCollapse,
                      child: Icon(
                        isCollapsed ? Icons.expand_more : Icons.expand_less,
                        size: 16,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 3),
                  ],
                  InkWell(
                    onTap: onClose ?? () => viewModel.selectBend(null),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              if (!isCollapsed) ...[
                const SizedBox(height: 6),

                // Role Switcher (Structural Bend vs Edge Return Flange)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  padding: const EdgeInsets.all(2.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () =>
                              viewModel.setBendRole(bend.id, BendLineRole.bend),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 3.5),
                            decoration: BoxDecoration(
                              color: !bend.isFlange
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(3.0),
                              boxShadow: !bend.isFlange
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.06,
                                        ),
                                        blurRadius: 3.0,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.change_history,
                                  size: 11,
                                  color: !bend.isFlange
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Bend',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: !bend.isFlange
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: !bend.isFlange
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => viewModel.setBendRole(
                            bend.id,
                            BendLineRole.flange,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 3.5),
                            decoration: BoxDecoration(
                              color: bend.isFlange
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(3.0),
                              boxShadow: bend.isFlange
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.06,
                                        ),
                                        blurRadius: 3.0,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.border_top,
                                  size: 11,
                                  color: bend.isFlange
                                      ? const Color(0xFF8B5CF6)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Flange',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: bend.isFlange
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: bend.isFlange
                                        ? const Color(0xFF7C3AED)
                                        : const Color(0xFF64748B),
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
                const SizedBox(height: 6),

                // Nearest Edge Offset & Quick Precision Set
                if (nearestEdgeOffset != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'EDGE OFFSET',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${nearestEdgeOffset.toStringAsFixed(2)} mm',
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (bend.isFlange) ...[
                        _offsetPresetChip(
                          '10mm',
                          10.0,
                          nearestEdgeOffset,
                          themeColor,
                        ),
                        _offsetPresetChip(
                          '13mm',
                          13.0,
                          nearestEdgeOffset,
                          themeColor,
                        ),
                        _offsetPresetChip(
                          '14mm',
                          14.0,
                          nearestEdgeOffset,
                          themeColor,
                        ),
                        _offsetPresetChip(
                          '15mm',
                          15.0,
                          nearestEdgeOffset,
                          themeColor,
                        ),
                      ] else ...[
                        _offsetPresetChip(
                          '50mm',
                          50.0,
                          nearestEdgeOffset,
                          themeColor,
                        ),
                        _offsetPresetChip(
                          '75mm',
                          75.0,
                          nearestEdgeOffset,
                          themeColor,
                        ),
                        _offsetPresetChip(
                          '100mm',
                          100.0,
                          nearestEdgeOffset,
                          themeColor,
                        ),
                        _offsetPresetChip(
                          '200mm',
                          200.0,
                          nearestEdgeOffset,
                          themeColor,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => viewModel.setBendDistanceToEdge(
                            bend.id,
                            nearestEdgeOffset - 1.0,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                '-1 mm',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                          onTap: () => viewModel.setBendDistanceToEdge(
                            bend.id,
                            nearestEdgeOffset + 1.0,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                '+1 mm',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],

                // Direction Toggle (UP vs DOWN)
                const Text(
                  'FOLD DIRECTION',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _directionButton(
                        label: '↑ (+Z)',
                        active: isUp,
                        color: const Color(0xFF0284C7),
                        onTap: () => viewModel.updateBend(
                          bend.copyWith(
                            direction: BendDirection.up,
                            layer: 'BEND_UP',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _directionButton(
                        label: '↓ (-Z)',
                        active: !isUp,
                        color: const Color(0xFFD97706),
                        onTap: () => viewModel.updateBend(
                          bend.copyWith(
                            direction: BendDirection.down,
                            layer: 'BEND_DOWN',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Angle Presets
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'BEND ANGLE',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${bend.targetAngleDeg.toStringAsFixed(1)}°',
                      style: TextStyle(
                        color: themeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _angleChip(25.0),
                    _angleChip(30.0),
                    _angleChip(45.0),
                    _angleChip(90.0),
                    _angleChip(135.0),
                  ],
                ),

                // Angle Fine Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.0,
                    activeTrackColor: themeColor,
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    thumbColor: themeColor,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5.0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10.0,
                    ),
                  ),
                  child: Slider(
                    value: bend.targetAngleDeg.clamp(0.0, 180.0),
                    min: 0.0,
                    max: 180.0,
                    onChanged: (val) => viewModel.updateBend(
                      bend.copyWith(targetAngleDeg: val),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Sheet Metal Edge Constraints
                if (constraints != null) ...[
                  const Text(
                    'EDGE CONSTRAINTS (MM)',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _constraintBox(
                          label: 'From Left',
                          value: constraints.distFromLeftMm,
                          onChanged: (val) => viewModel.setBendConstraint(
                            referenceEdge: 'Left',
                            targetDistanceMm: val,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _constraintBox(
                          label: 'From Bottom',
                          value: constraints.distFromBottomMm,
                          onChanged: (val) => viewModel.setBendConstraint(
                            referenceEdge: 'Bottom',
                            targetDistanceMm: val,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _constraintBox(
                          label: 'From Right',
                          value: constraints.distFromRightMm,
                          onChanged: (val) => viewModel.setBendConstraint(
                            referenceEdge: 'Right',
                            targetDistanceMm: val,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _constraintBox(
                          label: 'From Top',
                          value: constraints.distFromTopMm,
                          onChanged: (val) => viewModel.setBendConstraint(
                            referenceEdge: 'Top',
                            targetDistanceMm: val,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],

                // Inside Bend Radius - Compact Stepper (No bulky chip matrix)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'INSIDE RADIUS',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: bend.radiusMm > 0.5
                              ? () => viewModel.updateBend(
                                  bend.copyWith(
                                    radiusMm: (bend.radiusMm - 0.5).clamp(
                                      0.5,
                                      30.0,
                                    ),
                                  ),
                                )
                              : null,
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(2.0),
                            child: Icon(
                              Icons.remove_circle_outline,
                              size: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${bend.radiusMm.toStringAsFixed(1)} mm',
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => viewModel.updateBend(
                            bend.copyWith(
                              radiusMm: (bend.radiusMm + 0.5).clamp(0.5, 30.0),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(2.0),
                            child: Icon(
                              Icons.add_circle_outline,
                              size: 14,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // K-Factor Control
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'K-FACTOR',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      (bend.kFactor ?? viewModel.document.material.kFactor)
                          .toStringAsFixed(2),
                      style: TextStyle(
                        color: themeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.0,
                    activeTrackColor: themeColor,
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    thumbColor: themeColor,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 4.0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 8.0,
                    ),
                  ),
                  child: Slider(
                    value: (bend.kFactor ?? viewModel.document.material.kFactor)
                        .clamp(0.25, 0.50),
                    min: 0.25,
                    max: 0.50,
                    divisions: 25,
                    onChanged: (val) =>
                        viewModel.updateBend(bend.copyWith(kFactor: val)),
                  ),
                ),
                const SizedBox(height: 4),

                // Bend Allowance & Deduction Live Readout
                Builder(
                  builder: (context) {
                    final ba = bend.calculateBendAllowance(
                      sheetThicknessMm: viewModel.document.material.thicknessMm,
                      kFactor:
                          bend.kFactor ?? viewModel.document.material.kFactor,
                    );
                    final bd = bend.calculateBendDeduction(
                      sheetThicknessMm: viewModel.document.material.thicknessMm,
                      kFactor:
                          bend.kFactor ?? viewModel.document.material.kFactor,
                    );
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'BA: ${ba.toStringAsFixed(2)} mm',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'BD: ${bd.toStringAsFixed(2)} mm',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xFF0284C7),
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),

                // Bend Relief Selector
                const Text(
                  'CORNER / BEND RELIEF',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<BendReliefType>(
                      value: bend.reliefType,
                      isDense: true,
                      isExpanded: true,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        for (final r in BendReliefType.values)
                          DropdownMenuItem(
                            value: r,
                            child: Text(
                              r.displayName,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          viewModel.updateBend(bend.copyWith(reliefType: val));
                        }
                      },
                    ),
                  ),
                ),
                if (bend.reliefType != BendReliefType.none) ...[
                  const SizedBox(height: 4),
                  Builder(
                    builder: (context) {
                      final defRules = viewModel.document.material
                          .toDefinition()
                          .reliefRules;
                      final curW =
                          bend.reliefWidthMm ??
                          defRules.minReliefWidth(
                            viewModel.document.material.thicknessMm,
                          );
                      final curD =
                          bend.reliefDepthMm ??
                          defRules.minReliefDepth(
                            bend.radiusMm,
                            viewModel.document.material.thicknessMm,
                          );
                      return Row(
                        children: [
                          Expanded(
                            child: _constraintBox(
                              label: 'Relief W (mm)',
                              value: curW,
                              onChanged: (val) => viewModel.updateBend(
                                bend.copyWith(reliefWidthMm: val),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _constraintBox(
                              label: 'Relief D (mm)',
                              value: curD,
                              onChanged: (val) => viewModel.updateBend(
                                bend.copyWith(reliefDepthMm: val),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Dimension Label:',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        bend.showLabel
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 16,
                        color: bend.showLabel
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF94A3B8),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      splashRadius: 14,
                      tooltip: bend.showLabel
                          ? 'Hide Dimension Label'
                          : 'Show Dimension Label',
                      onPressed: () => viewModel.toggleBendLabel(bend.id),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // CAM Violation indicator if any
                Builder(
                  builder: (context) {
                    final vResult = viewModel.bendViolations[bend.id];
                    if (vResult == null || vResult.isClean) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final v in vResult.violations)
                            Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber,
                                  size: 12,
                                  color: Color(0xFFB45309),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    v.message,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),

                // Delete Bend Button
                SizedBox(
                  width: double.infinity,
                  height: 24,
                  child: OutlinedButton.icon(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 12,
                      color: Color(0xFFDC2626),
                    ),
                    label: const Text(
                      'Delete Bend',
                      style: TextStyle(color: Color(0xFFDC2626), fontSize: 10),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFFDC2626),
                        width: 0.8,
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    onPressed: () => viewModel.deleteBendLine(bend.id),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
  }

  Widget _directionButton({
    required String label,
    required bool active,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? color : const Color(0xFFCBD5E1)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? color : const Color(0xFF475569),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _angleChip(double angle) {
    final active = (bend.targetAngleDeg - angle).abs() < 0.1;
    return Expanded(
      child: InkWell(
        onTap: () => viewModel.updateBend(bend.copyWith(targetAngleDeg: angle)),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Center(
            child: Text(
              '${angle.toInt()}°',
              style: TextStyle(
                color: active
                    ? const Color(0xFF0284C7)
                    : const Color(0xFF475569),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _offsetPresetChip(
    String label,
    double targetVal,
    double currentVal,
    Color color,
  ) {
    final isClose = (currentVal - targetVal).abs() < 0.25;
    return Expanded(
      child: InkWell(
        onTap: () => viewModel.setBendDistanceToEdge(bend.id, targetVal),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: isClose
                ? color.withValues(alpha: 0.15)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isClose ? color : const Color(0xFFE2E8F0),
              width: isClose ? 1.0 : 0.6,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: isClose ? FontWeight.bold : FontWeight.w500,
                color: isClose ? color : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _constraintBox({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 8),
          ),
          const SizedBox(height: 2),
          TextFormField(
            initialValue: value.toStringAsFixed(1),
            key: ValueKey(value.round()),
            style: const TextStyle(
              color: Color(0xFF0284C7),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
            keyboardType: TextInputType.number,
            onFieldSubmitted: (text) {
              final v = double.tryParse(text);
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
