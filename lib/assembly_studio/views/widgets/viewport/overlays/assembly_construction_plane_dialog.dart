import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;
import '../../../../viewmodels/assembly_studio_viewmodel.dart';
import '../../../theme/assembly_studio_theme.dart';

/// Modal dialog for creating 3D Construction Planes (Offset Plane or Plane at Angle)
class AssemblyConstructionPlaneDialog extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblyConstructionPlaneDialog({
    super.key,
    required this.viewModel,
  });

  @override
  State<AssemblyConstructionPlaneDialog> createState() => _AssemblyConstructionPlaneDialogState();
}

class _AssemblyConstructionPlaneDialogState extends State<AssemblyConstructionPlaneDialog> {
  String _planeType = 'offset'; // 'offset' or 'angle'
  late String _selectedParentPlaneId;
  double _offsetDistance = 25.0; // mm
  double _angleDeg = 45.0; // deg
  final double _planeSize = 140.0; // mm

  @override
  void initState() {
    super.initState();
    final planes = widget.viewModel.allAvailablePlanes;
    _selectedParentPlaneId = planes.isNotEmpty ? planes.first.id : 'datum_XY';
  }

  @override
  Widget build(BuildContext context) {
    final planes = widget.viewModel.allAvailablePlanes;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
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
                    color: AssemblyStudioTheme.onshapeBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.layers_rounded, color: AssemblyStudioTheme.onshapeBlue, size: 18),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONSTRUCTION PLANE',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Parametric 3D reference datum',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Plane Type Segmented Control
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TypeButton(
                      label: 'Offset Plane',
                      icon: Icons.height_rounded,
                      isSelected: _planeType == 'offset',
                      onTap: () => setState(() => _planeType = 'offset'),
                    ),
                  ),
                  Expanded(
                    child: _TypeButton(
                      label: 'Plane at Angle',
                      icon: Icons.rotate_90_degrees_cw_rounded,
                      isSelected: _planeType == 'angle',
                      onTap: () => setState(() => _planeType = 'angle'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Reference Parent Plane Selector
            const Text(
              'REFERENCE PLANE',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: planes.any((p) => p.id == _selectedParentPlaneId)
                      ? _selectedParentPlaneId
                      : (planes.isNotEmpty ? planes.first.id : null),
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500),
                  items: planes.map((p) {
                    return DropdownMenuItem<String>(
                      value: p.id,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: p.customColor ?? AssemblyStudioTheme.onshapeBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(p.name, style: const TextStyle(color: Color(0xFF0F172A))),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedParentPlaneId = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Offset Distance or Angle Slider
            if (_planeType == 'offset') ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'OFFSET DISTANCE',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_offsetDistance >= 0 ? "+${_offsetDistance.toStringAsFixed(1)}" : _offsetDistance.toStringAsFixed(1)} mm',
                    style: const TextStyle(color: AssemblyStudioTheme.onshapeBlue, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _offsetDistance,
                min: -200.0,
                max: 200.0,
                divisions: 80,
                activeColor: AssemblyStudioTheme.onshapeBlue,
                inactiveColor: const Color(0xFFE2E8F0),
                onChanged: (v) => setState(() => _offsetDistance = v),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ROTATION ANGLE',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_angleDeg.toStringAsFixed(1)}°',
                    style: const TextStyle(color: AssemblyStudioTheme.onshapeBlue, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _angleDeg,
                min: -180.0,
                max: 180.0,
                divisions: 72,
                activeColor: AssemblyStudioTheme.onshapeBlue,
                inactiveColor: const Color(0xFFE2E8F0),
                onChanged: (v) => setState(() => _angleDeg = v),
              ),
            ],

            const SizedBox(height: 20),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _createPlane,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AssemblyStudioTheme.onshapeBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Create Plane', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _createPlane() {
    if (_planeType == 'offset') {
      final newPlane = widget.viewModel.addOffsetConstructionPlane(
        parentPlaneId: _selectedParentPlaneId,
        offsetMm: _offsetDistance,
        size: _planeSize,
      );
      Navigator.of(context).pop();
      widget.viewModel.selectPlaneForSketch(newPlane);
    } else {
      final refPlane = widget.viewModel.allAvailablePlanes
          .where((p) => p.id == _selectedParentPlaneId)
          .firstOrNull;
      final axisDir = refPlane?.xAxis ?? vm.Vector3(1, 0, 0);
      final axisOrigin = refPlane?.origin ?? vm.Vector3(0, 0, 0);

      final newPlane = widget.viewModel.addAngleConstructionPlane(
        referencePlaneId: _selectedParentPlaneId,
        axisOrigin: axisOrigin,
        axisDir: axisDir,
        angleDeg: _angleDeg,
        size: _planeSize,
      );
      Navigator.of(context).pop();
      widget.viewModel.selectPlaneForSketch(newPlane);
    }
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AssemblyStudioTheme.onshapeBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
