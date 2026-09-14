// =============================================================================
// studio_export_dialog.dart
//
// Interactive CAD/CAM Export & Download Dialog for Danish FormMatrix Studio.
// Supports instant preview, copy-to-clipboard, and export for:
// - .dsf (Danish Sheet Fold - Full Kinematic 2D/3D JSON)
// - .dxf (AutoCAD CNC Laser & Press Brake DXF with standard layers)
// - .obj (3D Wavefront Mesh with solid sheet metal thickness)
// - .stl (3D ASCII Stereolithography mesh)
// - .dds (Danish Datasheet complete project container)
// Designed with ZERO external dependencies for 100% standalone portability.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/dds_package.dart';
import '../../engine/export_engine_3d.dart';
import '../../engine/dxf_exporter.dart';
import '../../engine/kinematic_fold_engine.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../services/studio_file_service.dart';

enum ExportFormatType {
  dsf('Danish Sheet Fold (.dsf)', 'dsf', 'Full kinematic 2D/3D layout, bend recipes, and product parameters'),
  dxf('AutoCAD CNC Laser (.dxf)', 'dxf', 'R12 ASCII DXF with CUT, BEND_UP, BEND_DOWN, and HOLES layers'),
  obj('3D Wavefront Mesh (.obj)', 'obj', 'Folded 3D mesh with solid sheet metal thickness extrusion'),
  stl('3D Stereolithography (.stl)', 'stl', 'Standard ASCII STL format for 3D printing, CAM, and slicers'),
  dds('Danish Datasheet (.dds)', 'dds', 'Engineering datasheet container with tooling and camera state');

  final String label;
  final String extension;
  final String description;

  const ExportFormatType(this.label, this.extension, this.description);
}

class StudioExportDialog extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;

  const StudioExportDialog({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, SheetMetalStudioViewModel viewModel) {
    return showDialog(
      context: context,
      builder: (_) => StudioExportDialog(viewModel: viewModel),
    );
  }

  @override
  State<StudioExportDialog> createState() => _StudioExportDialogState();
}

class _StudioExportDialogState extends State<StudioExportDialog> {
  ExportFormatType _selectedFormat = ExportFormatType.dsf;
  bool _copied = false;
  double _solidThickness = 1.5;

  @override
  void initState() {
    super.initState();
    _solidThickness = widget.viewModel.document.material.thicknessMm;
  }

  String _generateContent() {
    final doc = widget.viewModel.document;

    switch (_selectedFormat) {
      case ExportFormatType.dsf:
        return doc.toJsonString(pretty: true);

      case ExportFormatType.dxf:
        return DxfExporter.exportDxf(doc);

      case ExportFormatType.obj:
        final foldedMesh = KinematicFoldEngine.computeFold(doc: doc, foldProgress: 1.0);
        return ExportEngine3d.exportWavefrontObj(
          polygons: foldedMesh,
          thicknessMm: _solidThickness,
          partName: doc.partNumber.replaceAll(' ', '_'),
        );

      case ExportFormatType.stl:
        final foldedMesh = KinematicFoldEngine.computeFold(doc: doc, foldProgress: 1.0);
        return ExportEngine3d.exportAsciiStl(
          polygons: foldedMesh,
          thicknessMm: _solidThickness,
          solidName: doc.partNumber.replaceAll(' ', '_'),
        );

      case ExportFormatType.dds:
        final pkg = DdsPackage.create(
          document: doc,
          projectName: 'Standard Project',
          customerName: 'Bonn Industries',
          drawingNumber: doc.partNumber,
          orbitAngleX: widget.viewModel.azimuthDeg,
          orbitAngleY: widget.viewModel.elevationDeg,
          foldProgress: widget.viewModel.foldProgress,
          showWireframe: widget.viewModel.showWireframe,
        );
        return pkg.toJsonString(pretty: true);
    }
  }

  String get _fileName {
    final cleanPart = widget.viewModel.document.partNumber.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '$cleanPart.${_selectedFormat.extension}';
  }

  @override
  Widget build(BuildContext context) {
    final content = _generateContent();
    final byteSize = content.length;
    final lineCount = content.split('\n').length;

    return Dialog(
      backgroundColor: const Color(0xFF141920),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF263238), width: 1.5),
      ),
      child: Container(
        width: 720,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.file_download_outlined, color: Color(0xFF00E5FF), size: 22),
                const SizedBox(width: 10),
                const Text(
                  'EXPORT CAD / CAM FILES',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(color: Color(0xFF263238), height: 20),

            // Format Selection Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ExportFormatType.values.map((fmt) {
                final isSelected = fmt == _selectedFormat;
                return ChoiceChip(
                  label: Text(fmt.label),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                  backgroundColor: const Color(0xFF1E242B),
                  labelStyle: TextStyle(
                    color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF37474F),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedFormat = fmt;
                        _copied = false;
                      });
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 8),
            Text(
              _selectedFormat.description,
              style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11),
            ),

            // Optional 3D Solid Thickness Slider for OBJ / STL
            if (_selectedFormat == ExportFormatType.obj || _selectedFormat == ExportFormatType.stl) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B222A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF37474F)),
                ),
                child: Row(
                  children: [
                    const Text('3D Solid Thickness:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 8),
                    Text(
                      _solidThickness > 0 ? '${_solidThickness.toStringAsFixed(1)} mm' : 'Mid-surface (0mm)',
                      style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: _solidThickness,
                          min: 0.0,
                          max: 5.0,
                          divisions: 10,
                          activeColor: const Color(0xFF00E5FF),
                          onChanged: (val) => setState(() => _solidThickness = val),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // File stats badge
            Row(
              children: [
                Text(
                  'Filename: $_fileName',
                  style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'Lines: $lineCount | Size: ${(byteSize / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Content Preview Box
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF263238)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      color: Color(0xFFCFD8DC),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Action Buttons
            Row(
              children: [
                OutlinedButton.icon(
                  icon: Icon(
                    _copied ? Icons.check_circle : Icons.copy,
                    color: _copied ? Colors.greenAccent : Colors.white70,
                    size: 15,
                  ),
                  label: Text(
                    _copied ? 'COPIED TO CLIPBOARD' : 'COPY CONTENT',
                    style: TextStyle(
                      color: _copied ? Colors.greenAccent : Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _copied ? Colors.greenAccent : const Color(0xFF37474F)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: content));
                    setState(() => _copied = true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied $_fileName to clipboard!'),
                          backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.8),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download, size: 15, color: Colors.black),
                  label: Text(
                    'DOWNLOAD $_fileName',
                    style: const TextStyle(color: Colors.black, fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: content));
                    final saved = await StudioFileService.saveFile(
                      fileName: _fileName,
                      content: content,
                      dialogTitle: 'Save / Download $_fileName',
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(saved
                              ? 'Saved $_fileName successfully!'
                              : 'Export copied to clipboard (Save cancelled or downloaded).'),
                          backgroundColor: saved ? const Color(0xFF00C853) : const Color(0xFF00E5FF),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
