// =============================================================================
// punch_property_sheet.dart
//
// Floating On-Canvas Property Inspector for selected CNC Turret Punches.
// Allows rapid modification of size (diameter, width, length), rotation, and
// exact millimeter distance constraints from edges and press-brake bends.
// Light CAD theme with Emerald Green accents.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/cnc_punch_primitive.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../engine/cnc_turret_engine.dart';
import 'rotation_dial_widget.dart';
import 'cad_number_spinner.dart';

class PunchPropertySheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final CncPunchPrimitive punch;
  final List<CncPunchPrimitive>? punches;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const PunchPropertySheet({
    super.key,
    required this.viewModel,
    required this.punch,
    this.punches,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF059669); // Emerald green for punches
    final punchList = punches ?? [punch];
    final isMulti = punchList.length > 1;
    final punchIds = punchList.map((p) => p.id).toList();
    final allVisible = punchList.every((p) => p.isVisible);
    final isCoupler = punchList.every((p) => p.role == CncPunchRole.coupler);
    final allShowLabel = punchList.every((p) => p.showLabel);

    final constraints = CncTurretEngine.computeConstraints(punch: punch, doc: viewModel.document);
    final overlapping = viewModel.findOverlappingPunches(punch.id);

    return GestureDetector(
      onPanStart: onDragStartHeader,
      onPanUpdate: onDragHeader,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 285.0,
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: themeColor.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16.0, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Drag Handle + Punch Type + Collapse + Close
            Row(
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: themeColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isMulti
                        ? '${punchList.length} HOLES (${punch.type.name.toUpperCase()})'
                        : '${punch.id} (${punch.type.name.toUpperCase()})',
                    style: TextStyle(
                      color: allVisible ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      decoration: allVisible ? null : TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    allVisible ? Icons.visibility : Icons.visibility_off,
                    size: 16,
                    color: allVisible ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  onPressed: () {
                    if (isMulti) {
                      viewModel.toggleSelectedPunchesVisibility(punchIds: punchIds, isVisible: !allVisible);
                    } else {
                      viewModel.togglePunchVisibility(punch.id);
                    }
                  },
                  tooltip: allVisible ? 'Hide / Suppress (Temp Delete)' : 'Show / Unsuppress',
                ),
                if (onToggleCollapse != null) ...[
                  InkWell(
                    onTap: onToggleCollapse,
                    child: Icon(isCollapsed ? Icons.expand_more : Icons.expand_less, size: 18, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(width: 4),
                ],
                InkWell(
                  onTap: onClose ?? () {
                    if (isMulti) {
                      viewModel.clearSelection();
                    } else {
                      viewModel.selectPunch(null);
                    }
                  },
                  child: const Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                ),
              ],
            ),
            if (!isCollapsed) ...[
              const SizedBox(height: 10),

              // Coupler Mounting Slot Toggle (Section 9 & 10.3)
              Container(
                margin: const EdgeInsets.only(bottom: 10.0),
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: isCoupler
                      ? const Color(0xFFFAF5FF)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(
                    color: isCoupler
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.handshake_outlined,
                            size: 15.0,
                            color: isCoupler
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6.0),
                          Flexible(
                            child: Text(
                              isMulti ? 'Coupler Mounting Slots (${punchList.length})' : 'Coupler Mounting Slot',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                                color: isCoupler
                                    ? const Color(0xFF6D28D9)
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: isCoupler,
                        activeThumbColor: const Color(0xFF7C3AED),
                        activeTrackColor: const Color(0xFFDDD6FE),
                        onChanged: (val) {
                          if (isMulti) {
                            viewModel.toggleSelectedPunchCouplerRole(isCoupler: val);
                          } else {
                            viewModel.markPunchAsCoupler(punch.id, isCoupler: val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Overlapping Holes Merge Option (single-selection only)
              if (!isMulti && overlapping.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.layers, size: 14, color: Color(0xFFB45309)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Overlaps ${overlapping.length} hole(s): ${overlapping.map((p) => p.id).join(", ")}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.merge_type, size: 14),
                          label: const Text('Merge Overlapping Holes', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          onPressed: () => viewModel.mergeOverlappingPunches(punch.id),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Size Controls
              if (punch.type == PunchType.roundHole) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'HOLE DIAMETER',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                    CadNumberSpinner(
                      value: punch.diameterMm,
                      min: 1.0,
                      max: 500.0,
                      step: 0.5,
                      decimals: 1,
                      suffix: 'mm',
                      width: 105,
                      onChanged: (val) {
                        if (isMulti) {
                          viewModel.updateSelectedPunches(punchIds: punchIds, diameterMm: val);
                        } else {
                          viewModel.updatePunch(punch.copyWith(diameterMm: val));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _presetSizeChip('M4 (4.5)', 4.5, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, diameterMm: 4.5);
                      } else {
                        viewModel.updatePunch(punch.copyWith(diameterMm: 4.5));
                      }
                    }),
                    _presetSizeChip('M6 (6.6)', 6.6, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, diameterMm: 6.6);
                      } else {
                        viewModel.updatePunch(punch.copyWith(diameterMm: 6.6));
                      }
                    }),
                    _presetSizeChip('M8 (9.0)', 9.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, diameterMm: 9.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(diameterMm: 9.0));
                      }
                    }),
                    _presetSizeChip('M10 (11)', 11.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, diameterMm: 11.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(diameterMm: 11.0));
                      }
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.change_circle_outlined, size: 14, color: themeColor),
                    label: const Text(
                      'Convert to Ellipse',
                      style: TextStyle(color: themeColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: themeColor, width: 0.8),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: () {
                      if (isMulti) {
                        for (final p in punchList) {
                          viewModel.updatePunch(
                            p.copyWith(
                              type: PunchType.ellipse,
                              lengthMm: (p.diameterMm * 1.5).roundToDouble(),
                              widthMm: p.diameterMm,
                              rotationDeg: 0.0,
                            ),
                          );
                        }
                      } else {
                        viewModel.updatePunch(
                          punch.copyWith(
                            type: PunchType.ellipse,
                            lengthMm: (punch.diameterMm * 1.5).roundToDouble(),
                            widthMm: punch.diameterMm,
                            rotationDeg: 0.0,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ] else if (punch.type == PunchType.square || punch.type == PunchType.rectangle) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SIZE MODIFIER',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                    Flexible(
                      child: Text(
                        '${punch.lengthMm.toStringAsFixed(1)} × ${punch.widthMm.toStringAsFixed(1)} mm',
                        style: const TextStyle(color: themeColor, fontSize: 11, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: CadNumberSpinner(
                        label: 'Length / Width (X)',
                        value: punch.lengthMm,
                        min: 1.0,
                        max: 2000.0,
                        step: 1.0,
                        decimals: 1,
                        suffix: 'mm',
                        onChanged: (val) {
                          if (isMulti) {
                            viewModel.updateSelectedPunches(
                              punchIds: punchIds,
                              lengthMm: val,
                              widthMm: punch.type == PunchType.square ? val : null,
                            );
                          } else {
                            viewModel.updatePunch(punch.copyWith(lengthMm: val, widthMm: punch.type == PunchType.square ? val : punch.widthMm));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: CadNumberSpinner(
                        label: 'Height / Depth (Y)',
                        value: punch.widthMm,
                        min: 1.0,
                        max: 2000.0,
                        step: 1.0,
                        decimals: 1,
                        suffix: 'mm',
                        onChanged: (val) {
                          if (isMulti) {
                            viewModel.updateSelectedPunches(
                              punchIds: punchIds,
                              widthMm: val,
                              lengthMm: punch.type == PunchType.square ? val : null,
                            );
                          } else {
                            viewModel.updatePunch(punch.copyWith(widthMm: val, lengthMm: punch.type == PunchType.square ? val : punch.lengthMm));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _presetSizeChip('10x10', 10.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: 10.0, widthMm: 10.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: 10.0, widthMm: 10.0));
                      }
                    }),
                    _presetSizeChip('15x15', 15.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: 15.0, widthMm: 15.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: 15.0, widthMm: 15.0));
                      }
                    }),
                    _presetSizeChip('20x20', 20.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: 20.0, widthMm: 20.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: 20.0, widthMm: 20.0));
                      }
                    }),
                    _presetSizeChip('25x25', 25.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: 25.0, widthMm: 25.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: 25.0, widthMm: 25.0));
                      }
                    }),
                    _presetSizeChip('30x30', 30.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: 30.0, widthMm: 30.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: 30.0, widthMm: 30.0));
                      }
                    }),
                  ],
                ),
                const SizedBox(height: 8),
              ] else if (punch.type == PunchType.ellipse) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'ELLIPSE (MAJOR x MINOR)',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${punch.lengthMm.toStringAsFixed(1)} x ${punch.widthMm.toStringAsFixed(1)} mm',
                      style: const TextStyle(color: themeColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Major Axis (L):',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${punch.lengthMm.toStringAsFixed(1)} mm',
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.0,
                    activeTrackColor: themeColor,
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    thumbColor: themeColor,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                  ),
                  child: Slider(
                    value: punch.lengthMm.clamp(2.0, math.max(60.0, punch.lengthMm)),
                    min: 2.0,
                    max: math.max(60.0, punch.lengthMm),
                    divisions: math.max(1, ((math.max(60.0, punch.lengthMm) - 2.0) * 2).round()),
                    onChanged: (val) {
                      final rounded = (val * 2).round() / 2.0;
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: rounded);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: rounded));
                      }
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Minor Axis (W):',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${punch.widthMm.toStringAsFixed(1)} mm',
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.0,
                    activeTrackColor: themeColor,
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    thumbColor: themeColor,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                  ),
                  child: Slider(
                    value: punch.widthMm.clamp(2.0, math.max(60.0, punch.widthMm)),
                    min: 2.0,
                    max: math.max(60.0, punch.widthMm),
                    divisions: math.max(1, ((math.max(60.0, punch.widthMm) - 2.0) * 2).round()),
                    onChanged: (val) {
                      final rounded = (val * 2).round() / 2.0;
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, widthMm: rounded);
                      } else {
                        viewModel.updatePunch(punch.copyWith(widthMm: rounded));
                      }
                    },
                  ),
                ),
                Row(
                  children: [
                    _presetSizeChip('18x12', 18.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: 18.0, widthMm: 12.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: 18.0, widthMm: 12.0));
                      }
                    }),
                    _presetSizeChip('25x15', 25.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: 25.0, widthMm: 15.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: 25.0, widthMm: 15.0));
                      }
                    }),
                    _presetSizeChip('30x20', 30.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, lengthMm: 30.0, widthMm: 20.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(lengthMm: 30.0, widthMm: 20.0));
                      }
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.circle_outlined, size: 14, color: Color(0xFF0284C7)),
                    label: const Text(
                      'Convert to Circle',
                      style: TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0284C7), width: 0.8),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: () {
                      if (isMulti) {
                        for (final p in punchList) {
                          viewModel.updatePunch(
                            p.copyWith(type: PunchType.roundHole, diameterMm: p.widthMm, rotationDeg: 0.0),
                          );
                        }
                      } else {
                        viewModel.updatePunch(punch.copyWith(type: PunchType.roundHole, diameterMm: punch.widthMm, rotationDeg: 0.0));
                      }
                    },
                  ),
                ),
              ] else if (punch.type == PunchType.obroundSlot) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'SLOT WIDTH x LENGTH',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${punch.widthMm.toInt()} x ${punch.lengthMm.toInt()} mm',
                      style: const TextStyle(color: themeColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _presetSizeChip('7x25', 7.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, widthMm: 7.0, lengthMm: 25.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(widthMm: 7.0, lengthMm: 25.0));
                      }
                    }),
                    _presetSizeChip('9x25', 9.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, widthMm: 9.0, lengthMm: 25.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(widthMm: 9.0, lengthMm: 25.0));
                      }
                    }),
                    _presetSizeChip('9x35', 9.0, () {
                      if (isMulti) {
                        viewModel.updateSelectedPunches(punchIds: punchIds, widthMm: 9.0, lengthMm: 35.0);
                      } else {
                        viewModel.updatePunch(punch.copyWith(widthMm: 9.0, lengthMm: 35.0));
                      }
                    }),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Constraint Readout & Positioning (only for individual selection)
              if (!isMulti) ...[
                const Text(
                  'EDGE CONSTRAINTS (MM)',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _constraintBox(
                        label: 'Left Edge (X)',
                        value: constraints.distFromLeftMm,
                        onChanged: (newX) => viewModel.setPunchEdgeConstraint(punchId: punch.id, referenceEdge: 'Left', targetDistanceMm: newX),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _constraintBox(
                        label: 'Bottom Edge (Y)',
                        value: constraints.distFromBottomMm,
                        onChanged: (newY) => viewModel.setPunchEdgeConstraint(punchId: punch.id, referenceEdge: 'Bottom', targetDistanceMm: newY),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (constraints.distToNearestBendMm != null)
                  Text(
                    'Nearest Bend (${constraints.nearestBendId}): ${constraints.distToNearestBendMm!.toStringAsFixed(1)} mm',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontFamily: 'monospace'),
                  ),
                const SizedBox(height: 10),
              ],

              // Rotation: Interactive dial for obround, ellipse, and other non-circular punches (SS2)
              // Note: Circles are rotationally invariant, so rotation is omitted for round holes
              if (punch.type != PunchType.roundHole) ...[
                RotationDialWidget(
                  angleDeg: punch.rotationDeg,
                  label: 'Rotation Dial',
                  onAngleChanged: (newAngle) {
                    if (isMulti) {
                      viewModel.updateSelectedPunches(punchIds: punchIds, rotationDeg: newAngle);
                    } else {
                      viewModel.updatePunch(punch.copyWith(rotationDeg: newAngle));
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Size Dimension:',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      allShowLabel ? Icons.visibility : Icons.visibility_off,
                      size: 16,
                      color: allShowLabel ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    splashRadius: 14,
                    tooltip: allShowLabel ? 'Hide Size Dimension' : 'Show Size Dimension',
                    onPressed: () {
                      if (isMulti) {
                        viewModel.toggleSelectedPunchesLabel(punchIds: punchIds, showLabel: !allShowLabel);
                      } else {
                        viewModel.togglePunchLabel(punch.id);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFDC2626)),
                  label: Text(
                    isMulti ? 'Delete ${punchList.length} Punches' : 'Delete Punch',
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFDC2626), width: 0.8),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () {
                    if (isMulti) {
                      viewModel.deleteSelectedEntities();
                    } else {
                      viewModel.deleteSelectedPunch();
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _presetSizeChip(String label, double val, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF334155), fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _constraintBox({required String label, required double value, required ValueChanged<double> onChanged}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 8)),
          const SizedBox(height: 2),
          CadNumberSpinner(value: value, min: 0.0, max: 5000.0, step: 1.0, decimals: 1, suffix: 'mm', onChanged: onChanged),
        ],
      ),
    );
  }
}
