import 'package:flutter/material.dart';

import '../../../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// OnShape / Fusion 360 Style Parametric Dimension & Feature Modifier Panel.
/// Opens when any sketch entity is selected on a 3D surface.
class AssemblySketchParameterPanel extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback? onRebuildModel;

  const AssemblySketchParameterPanel({super.key, required this.viewModel, this.onRebuildModel});

  @override
  State<AssemblySketchParameterPanel> createState() => _AssemblySketchParameterPanelState();
}

class _AssemblySketchParameterPanelState extends State<AssemblySketchParameterPanel> {
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late TextEditingController _radiusController;
  late TextEditingController _posXController;
  late TextEditingController _posYController;
  late TextEditingController _depthController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController();
    _heightController = TextEditingController();
    _radiusController = TextEditingController();
    _posXController = TextEditingController();
    _posYController = TextEditingController();
    _depthController = TextEditingController();
    _syncFromEntity();
  }

  @override
  void didUpdateWidget(covariant AssemblySketchParameterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromEntity();
  }

  void _syncFromEntity() {
    final entity = widget.viewModel.selectedSketchEntity;
    if (entity == null) return;

    if (entity is CADRectangleEntity) {
      _widthController.text = entity.width.toStringAsFixed(1);
      _heightController.text = entity.height.toStringAsFixed(1);
      _posXController.text = entity.startPoint.dx.toStringAsFixed(1);
      _posYController.text = entity.startPoint.dy.toStringAsFixed(1);
    } else if (entity is CADCircleEntity) {
      _radiusController.text = entity.radius.toStringAsFixed(1);
      _posXController.text = entity.center.dx.toStringAsFixed(1);
      _posYController.text = entity.center.dy.toStringAsFixed(1);
    } else if (entity is CADLineEntity) {
      final len = (entity.end - entity.start).distance;
      _widthController.text = len.toStringAsFixed(1);
      _posXController.text = entity.start.dx.toStringAsFixed(1);
      _posYController.text = entity.start.dy.toStringAsFixed(1);
    }
    _depthController.text = entity.depthMm.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _radiusController.dispose();
    _posXController.dispose();
    _posYController.dispose();
    _depthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final entity = vm.selectedSketchEntity;
    if (entity == null) return const SizedBox.shrink();

    String typeName = 'ENTITY';
    IconData typeIcon = Icons.crop_square_rounded;
    if (entity is CADRectangleEntity) {
      typeName = 'RECTANGLE';
      typeIcon = Icons.crop_square_rounded;
    } else if (entity is CADCircleEntity) {
      typeName = 'CIRCLE';
      typeIcon = Icons.circle_outlined;
    } else if (entity is CADLineEntity) {
      typeName = 'LINE';
      typeIcon = Icons.show_chart_rounded;
    } else if (entity is CADPolylineEntity) {
      typeName = 'POLYLINE';
      typeIcon = Icons.polyline_rounded;
    }

    return Container(
      width: 290,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withAlpha(245), // Slate 900
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(typeIcon, color: const Color(0xFF38BDF8), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$typeName PARAMETERS',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => vm.selectSketchPrimitive(null),
                child: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 18),

          // Dimension inputs
          if (entity is CADRectangleEntity) ...[
            _buildInputField('Width (mm)', _widthController, (val) {
              final d = double.tryParse(val);
              if (d != null && d > 0) vm.updateSelectedPrimitiveDimensions(width: d);
            }),
            const SizedBox(height: 8),
            _buildInputField('Height (mm)', _heightController, (val) {
              final d = double.tryParse(val);
              if (d != null && d > 0) vm.updateSelectedPrimitiveDimensions(height: d);
            }),
          ] else if (entity is CADCircleEntity) ...[
            _buildInputField('Radius (mm)', _radiusController, (val) {
              final d = double.tryParse(val);
              if (d != null && d > 0) vm.updateSelectedPrimitiveDimensions(radius: d);
            }),
          ] else if (entity is CADLineEntity) ...[
            _buildInputField('Length (mm)', _widthController, (val) {}),
          ],

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildInputField('Pos X', _posXController, (val) {
                  final x = double.tryParse(val);
                  if (x != null) {
                    final curr = entity is CADRectangleEntity
                        ? entity.startPoint
                        : entity is CADCircleEntity
                        ? entity.center
                        : Offset.zero;
                    vm.updateSelectedPrimitiveDimensions(position: Offset(x, curr.dy));
                  }
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInputField('Pos Y', _posYController, (val) {
                  final y = double.tryParse(val);
                  if (y != null) {
                    final curr = entity is CADRectangleEntity
                        ? entity.startPoint
                        : entity is CADCircleEntity
                        ? entity.center
                        : Offset.zero;
                    vm.updateSelectedPrimitiveDimensions(position: Offset(curr.dx, y));
                  }
                }),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Text(
            'FEATURE OPERATION',
            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          // Mode Toggle: Pass-Through Cut vs Blind Cut vs Impress
          Row(
            children: [
              _buildFeatureModeButton(
                label: 'Pass-Through',
                isSelected: entity.featureType == FeatureType.cut && entity.isPassThrough,
                onTap: () {
                  vm.updateSelectedPrimitiveDimensions(featureType: FeatureType.cut, isPassThrough: true);
                },
              ),
              const SizedBox(width: 4),
              _buildFeatureModeButton(
                label: 'Blind Cut',
                isSelected: entity.featureType == FeatureType.cut && !entity.isPassThrough,
                onTap: () {
                  vm.updateSelectedPrimitiveDimensions(featureType: FeatureType.cut, isPassThrough: false);
                },
              ),
              const SizedBox(width: 4),
              _buildFeatureModeButton(
                label: 'Impress',
                isSelected: entity.featureType == FeatureType.extrude,
                onTap: () {
                  vm.updateSelectedPrimitiveDimensions(featureType: FeatureType.extrude, isPassThrough: false, depthMm: 0.0);
                },
              ),
            ],
          ),

          if (!entity.isPassThrough && entity.featureType == FeatureType.cut) ...[
            const SizedBox(height: 8),
            _buildInputField('Depth (mm)', _depthController, (val) {
              final d = double.tryParse(val);
              if (d != null && d > 0) vm.updateSelectedPrimitiveDimensions(depthMm: d);
            }),
          ],

          const SizedBox(height: 12),
          // Geometry Modification (Fillet / Chamfer / Construction)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.rounded_corner_rounded, size: 14),
                  label: const Text('Fillet 5mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  onPressed: () => vm.applyFilletToSelectedCorner(5.0),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.square_foot_rounded, size: 14),
                  label: const Text('Chamfer 5mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  onPressed: () => vm.applyChamferToSelectedCorner(5.0),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          // Cutout 3D Hole Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(38),
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.handyman_rounded, size: 15),
            label: Text(
              entity.isPassThrough ? 'PUNCH PASS-THROUGH CUT' : 'EXECUTE SURFACE FEATURE',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              vm.executeFeatureCutOnActiveSurface(isPassThrough: entity.isPassThrough, depthMm: entity.depthMm);
              widget.onRebuildModel?.call();
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF0284C7),
                  content: Text(entity.isPassThrough ? '3D Pass-Through Hole punched cleanly through model!' : 'Surface feature modification applied!'),
                ),
              );
            },
          ),

          const SizedBox(height: 6),
          // Delete button
          InkWell(
            onTap: () {
              vm.deleteSelectedSketchEntity();
              widget.onRebuildModel?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Delete Entity',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 3),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureModeButton({required String label, required bool isSelected, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
          ),
          child: Text(
            label,
            style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 9.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
          ),
        ),
      ),
    );
  }
}
