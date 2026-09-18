// =============================================================================
// studio_import_dialog.dart
//
// Interactive Import Modal Dialog for truFold Studio by Danish.
// Allows users to:
// 1. Pick and open .dsf, .dxf, or .dds files from Windows disk or browser
// 2. Paste ASCII DXF or .dsf JSON strings to load custom geometry
// Automatically auto-classifies layers, slices planar faces, and folds into 3D!
// =============================================================================

import 'package:flutter/material.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../services/studio_file_service.dart';
import '../../engine/dxf_mini_parser.dart';
import '../../engine/dxf_import_diagnostics_engine.dart';
import '../../engine/dxf_geometry_recognition_engine.dart';
import 'dxf_import_diagnostics_dialog.dart';

class StudioImportDialog extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final ValueChanged<List<ImportedFileItem>>? onFilesImported;

  const StudioImportDialog({
    super.key,
    required this.viewModel,
    this.onFilesImported,
  });

  static Future<void> show(
    BuildContext context,
    SheetMetalStudioViewModel viewModel, {
    ValueChanged<List<ImportedFileItem>>? onFilesImported,
  }) {
    return showDialog(
      context: context,
      builder: (_) => StudioImportDialog(
        viewModel: viewModel,
        onFilesImported: onFilesImported,
      ),
    );
  }

  @override
  State<StudioImportDialog> createState() => _StudioImportDialogState();
}

class _StudioImportDialogState extends State<StudioImportDialog> {
  final TextEditingController _textController = TextEditingController();
  String? _errorMessage;
  bool _isPickingFile = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _handleFilePicker() async {
    setState(() {
      _isPickingFile = true;
      _errorMessage = null;
    });

    try {
      final rawFiles = await StudioFileService.pickRawFiles();
      if (!mounted) return;

      final items = <ImportedFileItem>[];
      for (final file in rawFiles) {
        final isDxf = file.fileName.toLowerCase().endsWith('.dxf');
        if (isDxf) {
          final parsed = DxfMiniParser.parse(file.content);
          final report = DxfImportDiagnosticsEngine.analyze(parsed);
          bool shouldHeal = true;
          if (mounted) {
            final chosenHeal = await DxfImportDiagnosticsDialog.show(
              context,
              report: report,
              fileName: file.fileName,
            );
            if (chosenHeal == null) continue;
            shouldHeal = chosenHeal;
          }

          final dataToRecognize = shouldHeal
              ? DxfImportDiagnosticsEngine.heal(parsed).healedData
              : parsed;
          final recognized = DxfGeometryRecognitionEngine.recognize(
            dataToRecognize,
            productType: file.fileName.replaceAll('.dxf', ''),
            itemName: file.fileName,
          );

          items.add(ImportedFileItem(
            fileName: file.fileName,
            document: recognized.generatedDocument,
            filePath: file.filePath,
          ));
        } else {
          final parsedItems = StudioFileService.parseContent(
            file.content,
            fileName: file.fileName,
            filePath: file.filePath,
          );
          items.addAll(parsedItems);
        }
      }

      if (items.isNotEmpty && mounted) {
        if (widget.onFilesImported != null) {
          widget.onFilesImported!(items);
        } else {
          widget.viewModel.loadDocument(items.first.document);
        }
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to pick/read file: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  Future<void> _handleImportText() async {
    final raw = _textController.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorMessage = 'Please select a file or paste DXF/DSF/DDS content.');
      return;
    }

    try {
      final isDxf = !raw.startsWith('{') && (raw.contains('SECTION') || raw.startsWith('0\n') || raw.startsWith('0\r\n'));
      if (isDxf) {
        final parsed = DxfMiniParser.parse(raw);
        final report = DxfImportDiagnosticsEngine.analyze(parsed);
        bool shouldHeal = true;
        if (mounted) {
          final chosenHeal = await DxfImportDiagnosticsDialog.show(
            context,
            report: report,
            fileName: 'Pasted Geometry.dxf',
          );
          if (chosenHeal == null) return;
          shouldHeal = chosenHeal;
        }

        final dataToRecognize = shouldHeal
            ? DxfImportDiagnosticsEngine.heal(parsed).healedData
            : parsed;
        final recognized = DxfGeometryRecognitionEngine.recognize(
          dataToRecognize,
          productType: 'Pasted Component',
          itemName: 'Pasted Geometry',
        );

        final items = [
          ImportedFileItem(
            fileName: 'Pasted Geometry.dxf',
            document: recognized.generatedDocument,
          ),
        ];

        if (widget.onFilesImported != null) {
          widget.onFilesImported!(items);
        } else {
          widget.viewModel.loadDocument(items.first.document);
        }
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final items = StudioFileService.parseContent(raw, fileName: 'Pasted Document');
      if (items.isNotEmpty) {
        if (widget.onFilesImported != null) {
          widget.onFilesImported!(items);
        } else {
          widget.viewModel.loadDocument(items.first.document);
        }
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() => _errorMessage = 'No valid CAD data found.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to parse file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141920),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF263238), width: 1.5),
      ),
      child: Container(
        width: 680,
        height: 540,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Bar
            Row(
              children: [
                const Icon(Icons.file_upload_outlined, color: Color(0xFF00E5FF), size: 22),
                const SizedBox(width: 10),
                const Text(
                  'IMPORT FLAT PATTERN / ASSEMBLY (.DSF, .DXF, .DDS)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(color: Color(0xFF263238), height: 18),

            // Top action: Pick File Button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2430),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2E3D4E)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Open Files (.dsf, .dxf, .dds)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Supports individual sheet folds (.dsf), flat DXFs, and multi-part data sheets (.dds).',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: _isPickingFile
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.folder_open, size: 16),
                    label: Text(_isPickingFile ? 'Opening...' : 'Browse / Pick File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isPickingFile ? null : _handleFilePicker,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            const Text(
              'Or paste ASCII DXF content (AutoCAD R12/2000) or .dsf / .dds JSON code directly:',
              style: TextStyle(color: Color(0xFF90A4AE), fontSize: 11),
            ),
            const SizedBox(height: 8),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF263238)),
                ),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFFCFD8DC),
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Paste ASCII DXF (ENTITIES section) or .dsf / .dds JSON here...',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Parse Pasted Text'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _handleImportText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
