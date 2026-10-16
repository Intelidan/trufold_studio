// Extrude Floating Overlay Inspector Dialog
// TruFold Assembly Studio - Phase 5 Feature Extrusion & Boolean Operations
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';

import 'package:trufold_studio/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/theme/assembly_studio_theme.dart';

class AssemblyExtrudeDialog extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblyExtrudeDialog({
    super.key,
    required this.viewModel,
  });

  @override
  State<AssemblyExtrudeDialog> createState() => _AssemblyExtrudeDialogState();
}

class _AssemblyExtrudeDialogState extends State<AssemblyExtrudeDialog> {
  late TextEditingController _distController;
  late TextEditingController _dist2Controller;
  late TextEditingController _taperController;

  @override
  void initState() {
    super.initState();
    final p = widget.viewModel.extrudeParams;
    _distController = TextEditingController(text: p.distanceMm.toStringAsFixed(1));
    _dist2Controller = TextEditingController(text: p.distanceSide2Mm.toStringAsFixed(1));
    _taperController = TextEditingController(text: p.taperAngleDeg.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant AssemblyExtrudeDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = widget.viewModel.extrudeParams;
    if (_distController.text != p.distanceMm.toStringAsFixed(1)) {
      _distController.text = p.distanceMm.toStringAsFixed(1);
    }
    if (_dist2Controller.text != p.distanceSide2Mm.toStringAsFixed(1)) {
      _dist2Controller.text = p.distanceSide2Mm.toStringAsFixed(1);
    }
    if (_taperController.text != p.taperAngleDeg.toStringAsFixed(1)) {
      _taperController.text = p.taperAngleDeg.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _distController.dispose();
    _dist2Controller.dispose();
    _taperController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final params = vm.extrudeParams;
    final plane = vm.activeSketchPlane;

    final segments = plane != null ? AssemblySurfaceSketchEngine.compilePlaneSegments(plane) : <CADLineSegment>[];
    final validation = segments.isNotEmpty ? CADProfileValidator.validateProfile(segments) : null;
    final hasValidProfile = validation != null && validation.isValidClosedLoop && validation.orderedPathVertices.length >= 3;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Onshape Header Bar with Title, Green Checkmark (Enter) and Red Cross (Esc)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.layers_rounded, color: AssemblyStudioTheme.onshapeBlue, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'EXTRUDE',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                // Green Checkmark Accept Button
                Tooltip(
                  message: 'Accept extrusion (Enter)',
                  child: InkWell(
                    onTap: hasValidProfile ? vm.executeExtrudeFeature : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: hasValidProfile ? AssemblyStudioTheme.onshapeGreen : const Color(0xFFCBD5E1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Red X Cancel Button
                Tooltip(
                  message: 'Cancel extrusion (Esc)',
                  child: InkWell(
                    onTap: vm.closeExtrudeDialog,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AssemblyStudioTheme.onshapeRed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: hasValidProfile ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: hasValidProfile ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasValidProfile ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                        color: hasValidProfile ? const Color(0xFF10B981) : const Color(0xFFDC2626),
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasValidProfile ? '1 Closed Profile Selected' : 'No Closed Profile on Plane',
                          style: TextStyle(
                            color: hasValidProfile ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Boolean Operation Selector (New, Add, Remove, Intersect)
                const Text(
                  'OPERATION',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: AssemblyExtrudeOperation.values.map((op) {
                    final isSel = params.operation == op;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(5),
                          onTap: () {
                            vm.updateExtrudeParams(params.copyWith(operation: op));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFEBF5FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: isSel ? AssemblyStudioTheme.onshapeBlue : const Color(0xFFE2E8F0),
                                width: isSel ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(op.icon, size: 14, color: isSel ? AssemblyStudioTheme.onshapeBlue : const Color(0xFF64748B)),
                                const SizedBox(height: 2),
                                Text(
                                  op.label,
                                  style: TextStyle(
                                    color: isSel ? AssemblyStudioTheme.onshapeBlue : const Color(0xFF334155),
                                    fontSize: 9.5,
                                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // Direction Selector
                const Text(
                  'DIRECTION',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: AssemblyExtrudeDirection.values.map((dir) {
                    final isSel = params.direction == dir;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(5),
                          onTap: () {
                            vm.updateExtrudeParams(params.copyWith(direction: dir));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFEBF5FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: isSel ? AssemblyStudioTheme.onshapeBlue : const Color(0xFFE2E8F0),
                                width: isSel ? 1.5 : 1.0,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                dir.label,
                                style: TextStyle(
                                  color: isSel ? AssemblyStudioTheme.onshapeBlue : const Color(0xFF334155),
                                  fontSize: 10,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // Extrude Distance 1
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      params.direction == AssemblyExtrudeDirection.symmetric ? 'DISTANCE (± mm)' : 'DISTANCE (mm)',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      height: 24,
                      child: TextField(
                        controller: _distController,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.w600),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AssemblyStudioTheme.onshapeBlue)),
                        ),
                        onSubmitted: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null) vm.updateExtrudeDistance(parsed);
                        },
                      ),
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
                    value: params.distanceMm.clamp(-150.0, 200.0),
                    min: -150.0,
                    max: 200.0,
                    onChanged: (val) {
                      vm.updateExtrudeDistance(val);
                    },
                  ),
                ),

                // Second Distance for Two-Side mode
                if (params.direction == AssemblyExtrudeDirection.twoSide) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SIDE 2 DISTANCE (mm)',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        height: 24,
                        child: TextField(
                          controller: _dist2Controller,
                          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.w600),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AssemblyStudioTheme.onshapeBlue)),
                          ),
                          onSubmitted: (val) {
                            final parsed = double.tryParse(val);
                            if (parsed != null) {
                              vm.updateExtrudeParams(params.copyWith(distanceSide2Mm: parsed));
                            }
                          },
                        ),
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
                      value: params.distanceSide2Mm.clamp(0.0, 200.0),
                      min: 0.0,
                      max: 200.0,
                      onChanged: (val) {
                        vm.updateExtrudeParams(params.copyWith(distanceSide2Mm: val));
                      },
                    ),
                  ),
                ],

                // Taper Angle
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TAPER ANGLE (deg)',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      height: 24,
                      child: TextField(
                        controller: _taperController,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.w600),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AssemblyStudioTheme.onshapeBlue)),
                        ),
                        onSubmitted: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null) {
                            vm.updateExtrudeParams(params.copyWith(taperAngleDeg: parsed));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: const Color(0xFFF59E0B),
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    thumbColor: const Color(0xFFD97706),
                  ),
                  child: Slider(
                    value: params.taperAngleDeg.clamp(-45.0, 45.0),
                    min: -45.0,
                    max: 45.0,
                    onChanged: (val) {
                      vm.updateExtrudeParams(params.copyWith(taperAngleDeg: val));
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        ),
                        onPressed: vm.closeExtrudeDialog,
                        child: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasValidProfile ? AssemblyStudioTheme.onshapeBlue : const Color(0xFFCBD5E1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          elevation: 0,
                        ),
                        onPressed: hasValidProfile ? vm.executeExtrudeFeature : null,
                        icon: const Icon(Icons.check_rounded, size: 14),
                        label: const Text(
                          'Extrude (E)',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
