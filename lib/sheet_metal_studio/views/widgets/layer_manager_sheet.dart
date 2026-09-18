// =============================================================================
// layer_manager_sheet.dart
//
// Drawing Component Layer Manager for truFold Studio by Danish.
// Allows engineers to inspect CAD/CAM layers, toggle layer visibility,
// customize stroke colors, select line types, and monitor entity counts.
// =============================================================================

import 'package:flutter/material.dart';

import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../models/dsf_layer.dart';

class LayerManagerSheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;

  const LayerManagerSheet({super.key, required this.viewModel});

  static Future<void> show(
    BuildContext context,
    SheetMetalStudioViewModel viewModel,
  ) {
    return showDialog(
      context: context,
      builder: (_) => LayerManagerSheet(viewModel: viewModel),
    );
  }

  static const List<int> _cadColorPalette = [
    0xFF0F172A, // Slate 900 / Black
    0xFF0284C7, // Cyan / Sky Blue
    0xFFD97706, // Amber / Orange
    0xFFE11D48, // Rose / Red
    0xFF059669, // Emerald / Green
    0xFF7C3AED, // Violet / Purple
    0xFF64748B, // Slate 500 / Gray
    0xFF2563EB, // Royal Blue
    0xFFCA8A04, // Yellow Gold
    0xFFDC2626, // Crimson
    0xFF0D9488, // Teal
    0xFF475569, // Charcoal
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final layers = viewModel.document.effectiveLayers;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: 620,
            constraints: const BoxConstraints(maxHeight: 640),
            padding: const EdgeInsets.all(24),
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
                      child: const Icon(
                        Icons.layers,
                        color: Color(0xFF0284C7),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'DRAWING COMPONENT LAYERS',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Manage CAD layer assignments, visibility, CAM colors, and line types',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 8),

                // Table Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: const [
                      SizedBox(
                        width: 36,
                        child: Text(
                          'COLOR',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'LAYER NAME',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'LINE TYPE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Text(
                          'ENTITIES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 76,
                        child: Center(
                          child: Text(
                            'ACTIONS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Layer List
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: layers.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final layer = layers[index];
                      final entityCount = viewModel.getEntityCountForLayer(
                        layer.name,
                      );
                      return _buildLayerRow(context, layer, entityCount);
                    },
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 12),

                // Footer
                Row(
                  children: [
                    Text(
                      '${layers.length} Layers Total',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayerRow(BuildContext context, DsfLayer layer, int entityCount) {
    final layerColor = Color(layer.colorHex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Color Swatch with Quick Palette Picker
          InkWell(
            onTap: () => _showColorPicker(context, layer),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: layerColor,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: layerColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),

          // Layer Name & Description
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  layer.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: layer.isVisible
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                if (layer.description != null)
                  Text(
                    layer.description!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Line Type Dropdown
          Expanded(
            flex: 2,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value:
                      [
                        'CONTINUOUS',
                        'DASHED',
                        'DOTTED',
                        'CENTER',
                      ].contains(layer.lineType)
                      ? layer.lineType
                      : 'CONTINUOUS',
                  isDense: true,
                  icon: const Icon(Icons.arrow_drop_down, size: 16),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w500,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'CONTINUOUS',
                      child: Text('CONTINUOUS'),
                    ),
                    DropdownMenuItem(value: 'DASHED', child: Text('DASHED')),
                    DropdownMenuItem(value: 'DOTTED', child: Text('DOTTED')),
                    DropdownMenuItem(value: 'CENTER', child: Text('CENTER')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      viewModel.setLayerLineType(layer.name, val);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Entity Count Badge
          SizedBox(
            width: 70,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: entityCount > 0
                    ? const Color(0xFFEFF6FF)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: entityCount > 0
                      ? const Color(0xFFBFDBFE)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                '$entityCount items',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: entityCount > 0
                      ? const Color(0xFF1D4ED8)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Action Buttons: Visibility & Lock
          SizedBox(
            width: 76,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    layer.isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: layer.isVisible
                        ? const Color(0xFF0284C7)
                        : const Color(0xFFCBD5E1),
                  ),
                  tooltip: layer.isVisible ? 'Hide Layer' : 'Show Layer',
                  onPressed: () => viewModel.toggleLayerVisibility(layer.name),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    layer.isLocked ? Icons.lock : Icons.lock_open,
                    size: 18,
                    color: layer.isLocked
                        ? const Color(0xFFD97706)
                        : const Color(0xFFCBD5E1),
                  ),
                  tooltip: layer.isLocked ? 'Unlock Layer' : 'Lock Layer',
                  onPressed: () => viewModel.toggleLayerLock(layer.name),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context, DsfLayer layer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Select Color for "${layer.name}"',
          style: const TextStyle(fontSize: 14),
        ),
        content: SizedBox(
          width: 260,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: _cadColorPalette.map((colorVal) {
              final isSelected = layer.colorHex == colorVal;
              return InkWell(
                onTap: () {
                  viewModel.setLayerColor(layer.name, colorVal);
                  Navigator.of(ctx).pop();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(colorVal),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Colors.black
                          : const Color(0xFFCBD5E1),
                      width: isSelected ? 2.5 : 1.0,
                    ),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: Color(colorVal).withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
