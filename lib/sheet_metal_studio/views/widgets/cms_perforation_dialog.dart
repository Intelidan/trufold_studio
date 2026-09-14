// =============================================================================
// cms_perforation_dialog.dart
//
// Specialized Cable Management System (CMS) Perforation & Coupler Stamping Dialog.
// Allows users to auto-nest perforation patterns onto any selected planar surface
// (Bed Floor, Side Wall, etc.) with automatic width-wise modular pitch calculation
// (50, 100, 150, 250, 300, 450, 600, 750, 900 mm), Obround 30x7 mm standard,
// 80 mm pitch, 25 mm stagger distance, and individual hole rotation.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/planar_sheet_face.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'rotation_dial_widget.dart';

class CmsPerforationDialog extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final String? initialFaceId;

  const CmsPerforationDialog({
    super.key,
    required this.viewModel,
    this.initialFaceId,
  });

  static Future<void> show(
    BuildContext context,
    SheetMetalStudioViewModel viewModel, {
    String? faceId,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CmsPerforationDialog(
        viewModel: viewModel,
        initialFaceId: faceId,
      ),
    );
  }

  @override
  State<CmsPerforationDialog> createState() => _CmsPerforationDialogState();
}

class _CmsPerforationDialogState extends State<CmsPerforationDialog> {
  late String _selectedFaceId;
  PunchType _holeType = PunchType.obroundSlot;
  double _slotWidth = 7.0;
  double _slotLength = 30.0; // 30x7 mm standard
  double _diameterMm = 8.0;
  double _pitchY = 80.0; // 80 mm standard longitudinal pitch
  double _staggerDistance = 25.0; // 25 mm center-to-center stagger distance
  final double _endMargin = 50.0; // 50 mm standard end margin
  double _rotationDeg = 0.0; // Individual hole rotation angle
  bool _staggered = true;
  bool _autoWidthPitch = true;
  int _manualCols = 2;
  double _manualPitchX = 50.0;
  bool _includeCouplers = false;

  @override
  void initState() {
    super.initState();
    final faces = widget.viewModel.document.faces;
    final initialId = widget.initialFaceId ?? widget.viewModel.selectedFaceId;

    if (initialId != null && faces.any((f) => f.id == initialId)) {
      _selectedFaceId = initialId;
    } else {
      final base = faces.cast<PlanarSheetFace?>().firstWhere(
        (f) => f?.role == FaceRole.baseFloor,
        orElse: () => null,
      );
      _selectedFaceId = base?.id ?? (faces.isNotEmpty ? faces.first.id : '');
    }

    _updateDefaultsForFace(_selectedFaceId);
  }

  void _updateDefaultsForFace(String faceId) {
    final face = _getFace(faceId);
    if (face == null) return;

    final isSideWall = face.role == FaceRole.sideWall;
    if (isSideWall) {
      _rotationDeg = 90.0; // Side wall slots run longitudinally
      _includeCouplers = true;
    } else {
      _rotationDeg = 0.0; // Bed floor slots are transverse across width
      _includeCouplers = false;
    }
  }

  PlanarSheetFace? _getFace(String faceId) {
    try {
      return widget.viewModel.document.faces.firstWhere((f) => f.id == faceId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final faces = widget.viewModel.document.faces;
    final activeFace = _getFace(_selectedFaceId);

    // Compute active face dimensions
    double faceW = 0.0, faceL = 0.0;
    if (activeFace != null && activeFace.vertices.isNotEmpty) {
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      for (final v in activeFace.vertices) {
        if (v.x < minX) minX = v.x;
        if (v.x > maxX) maxX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.y > maxY) maxY = v.y;
      }
      final dx = maxX - minX;
      final dy = maxY - minY;
      faceW = dy >= dx ? dx : dy;
      faceL = dy >= dx ? dy : dx;
    }

    // Auto calculate width-wise specs
    int autoCols = 1;
    double autoPitchX = 0.0;
    if (activeFace != null) {
      final isWall = activeFace.role == FaceRole.sideWall || (faceW >= 35.0 && faceW <= 65.0 && activeFace.role != FaceRole.baseFloor);
      if (isWall) {
        autoCols = math.max(1, (faceW / 25.0).round());
        autoPitchX = autoCols > 1 ? (faceW - 25.0) / (autoCols - 1) : 0.0;
      } else {
        autoCols = math.max(1, (faceW / 50.0).round());
        autoPitchX = autoCols > 1 ? (faceW - 50.0) / (autoCols - 1) : 0.0;
      }
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.grid_view, color: Color(0xFF0284C7), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto-Nest Perforation Pattern',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          'Fits perforation pattern to selected planar surface & tray width',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // 1. Target Plane / Surface Selection
              const Text(
                'Target Plane / Surface',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              if (faces.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: faces.any((f) => f.id == _selectedFaceId) ? _selectedFaceId : faces.first.id,
                      items: faces.map((f) {
                        final label = f.label.isNotEmpty ? f.label : f.id;
                        final roleName = f.role.name;
                        return DropdownMenuItem(
                          value: f.id,
                          child: Row(
                            children: [
                              Icon(
                                f.role == FaceRole.baseFloor
                                    ? Icons.layers
                                    : f.role == FaceRole.sideWall
                                        ? Icons.view_sidebar
                                        : Icons.crop_din,
                                size: 16,
                                color: const Color(0xFF0284C7),
                              ),
                              const SizedBox(width: 8),
                              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Text('($roleName)', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedFaceId = val;
                            _updateDefaultsForFace(val);
                          });
                        }
                      },
                    ),
                  ),
                ),
              if (activeFace != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Surface Dimensions: ${faceW.toStringAsFixed(0)} mm (width) × ${faceL.toStringAsFixed(0)} mm (length)',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 14),

              // 2. Standard Presets
              const Text(
                'Hole Type & Size Preset',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _presetChip(
                    label: 'Obround 30x7 mm (SS2/SS3 Standard)',
                    selected: _holeType == PunchType.obroundSlot && _slotLength == 30.0 && _slotWidth == 7.0,
                    onTap: () => setState(() {
                      _holeType = PunchType.obroundSlot;
                      _slotLength = 30.0;
                      _slotWidth = 7.0;
                    }),
                  ),
                  _presetChip(
                    label: 'Obround 25x7 mm (BS EN 61537)',
                    selected: _holeType == PunchType.obroundSlot && _slotLength == 25.0 && _slotWidth == 7.0,
                    onTap: () => setState(() {
                      _holeType = PunchType.obroundSlot;
                      _slotLength = 25.0;
                      _slotWidth = 7.0;
                    }),
                  ),
                  _presetChip(
                    label: 'Obround 25x9 mm (Heavy Duty)',
                    selected: _holeType == PunchType.obroundSlot && _slotLength == 25.0 && _slotWidth == 9.0,
                    onTap: () => setState(() {
                      _holeType = PunchType.obroundSlot;
                      _slotLength = 25.0;
                      _slotWidth = 9.0;
                    }),
                  ),
                  _presetChip(
                    label: 'Round Hole Ø 8 mm',
                    selected: _holeType == PunchType.roundHole,
                    onTap: () => setState(() {
                      _holeType = PunchType.roundHole;
                      _diameterMm = 8.0;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 3. Width-wise Pitch Auto-Selection
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Auto-Select Pitch Width-wise',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        Switch(
                          value: _autoWidthPitch,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) => setState(() => _autoWidthPitch = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (_autoWidthPitch) ...[
                      Text(
                        'Conforms to standard tray widths (50, 100, 150, 250, 300, 450, 600, 750, 900 mm).',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Text(
                          'Auto Result: $autoCols ${autoCols == 1 ? "column" : "columns"} '
                          '| Pitch: ${autoPitchX.toStringAsFixed(1)} mm '
                          '| Side margin: 25 mm',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _numField(
                              label: 'Columns Across Width',
                              value: _manualCols.toDouble(),
                              min: 1,
                              max: 20,
                              onChanged: (v) => setState(() => _manualCols = v.round()),
                              helper: '$_manualCols cols',
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _numField(
                              label: 'Pitch Width-wise (mm)',
                              value: _manualPitchX,
                              min: 10,
                              max: 150,
                              onChanged: (v) => setState(() => _manualPitchX = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Longitudinal Pitch & Stagger
              Row(
                children: [
                  Expanded(
                    child: _numField(
                      label: 'Longitudinal Pitch',
                      value: _pitchY,
                      min: 30,
                      max: 200,
                      onChanged: (v) => setState(() => _pitchY = v),
                      helper: '${_pitchY.toStringAsFixed(0)} mm',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _numField(
                      label: 'Stagger Distance',
                      value: _staggerDistance,
                      min: 0,
                      max: 60,
                      onChanged: (v) => setState(() => _staggerDistance = v),
                      helper: '${_staggerDistance.toStringAsFixed(0)} mm',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 5. Individual Hole Rotation (SS1) & Stagger
              RotationDialWidget(
                angleDeg: _rotationDeg,
                onAngleChanged: (deg) => setState(() => _rotationDeg = deg),
                label: 'Individual Hole Rotation',
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Stagger Adjacent Columns:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  Switch(
                    value: _staggered,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _staggered = v),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 6. Coupler Slot Pairs Option
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: CheckboxListTile(
                  value: _includeCouplers,
                  onChanged: (v) => setState(() => _includeCouplers = v ?? false),
                  title: const Text(
                    'Stamp Side-Rail Coupler Slot Pairs',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  subtitle: const Text(
                    'Adds 7x20mm slots at both ends of side walls for splice plates.',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.bolt, size: 16),
                    label: const Text('Auto-Nest Perforation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () {
                      widget.viewModel.autoNestPerforationOnFace(
                        faceId: _selectedFaceId,
                        holeType: _holeType,
                        slotWidth: _slotWidth,
                        slotLength: _slotLength,
                        diameterMm: _diameterMm,
                        pitchY: _pitchY,
                        staggerDistance: _staggerDistance,
                        endMargin: _endMargin,
                        rotationDeg: _rotationDeg,
                        staggered: _staggered,
                        overrideCols: _autoWidthPitch ? null : _manualCols,
                        overridePitchX: _autoWidthPitch ? null : _manualPitchX,
                      );

                      if (_includeCouplers) {
                        widget.viewModel.stampSideRailCouplers(
                          slotWidth: _slotWidth,
                          slotLength: 20.0,
                          endOffset: 25.0,
                          verticalSpacing: 25.0,
                        );
                      }
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip({required String label, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? const Color(0xFF0284C7) : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _numField({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
            Text(helper ?? '${value.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: const Color(0xFF0284C7),
            inactiveColor: const Color(0xFFE2E8F0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
