// =============================================================================
// studio_file_service.dart
//
// Cross-Platform File Service for truFold Studio by Danish.
// Supports picking, opening, and creating/saving 3 core file types across Windows & Web:
// 1. .dsf (Danish Sheet Fold - individual part format)
// 2. .dxf (AutoCAD ASCII DXF flat pattern geometry)
// 3. .dds (Danish Data Sheet - multi-part project/assembly combining .dsf files)
// =============================================================================

import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/dsf_document.dart';
import '../engine/dxf_dsf_importer.dart';
import '../engine/dxf_exporter.dart';

class ImportedFileItem {
  final String fileName;
  final DsfDocument document;
  final String? filePath;

  const ImportedFileItem({
    required this.fileName,
    required this.document,
    this.filePath,
  });
}

class RawPickedFile {
  final String fileName;
  final String content;
  final String? filePath;

  const RawPickedFile({
    required this.fileName,
    required this.content,
    this.filePath,
  });
}

class StudioFileService {
  /// Picks raw files without parsing immediately, allowing UI to run diagnostics.
  static Future<List<RawPickedFile>> pickRawFiles() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dsf', 'dxf', 'dds'],
        // ignore: deprecated_member_use
        allowMultiple: true,
      );

      if (files.isEmpty) {
        return [];
      }

      final List<RawPickedFile> rawItems = [];
      for (final file in files) {
        String? rawContent;
        try {
          final bytes = await file.readAsBytes();
          rawContent = utf8.decode(bytes, allowMalformed: true);
        } catch (e) {
          debugPrint('Error reading bytes from file ${file.name}: $e');
        }

        if (rawContent == null || rawContent.trim().isEmpty) continue;
        rawItems.add(
          RawPickedFile(
            fileName: file.name,
            content: rawContent,
            filePath: kIsWeb ? null : file.path,
          ),
        );
      }

      return rawItems;
    } catch (e) {
      debugPrint('Error picking raw files in StudioFileService: $e');
      return [];
    }
  }

  /// Picks one or more .dsf, .dxf, or .dds files from disk or browser.
  /// Works seamlessly on Windows, macOS, Linux, and Flutter Web.
  static Future<List<ImportedFileItem>> pickFiles() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dsf', 'dxf', 'dds'],
        // ignore: deprecated_member_use
        allowMultiple: true,
      );

      if (files.isEmpty) {
        return [];
      }

      final List<ImportedFileItem> items = [];

      for (final file in files) {
        String? rawContent;
        try {
          final bytes = await file.readAsBytes();
          rawContent = utf8.decode(bytes, allowMalformed: true);
        } catch (e) {
          debugPrint('Error reading bytes from file ${file.name}: $e');
        }

        if (rawContent == null || rawContent.trim().isEmpty) continue;

        final parsed = parseContent(
          rawContent,
          fileName: file.name,
          filePath: kIsWeb ? null : file.path,
        );
        items.addAll(parsed);
      }

      return items;
    } catch (e) {
      debugPrint('Error picking files in StudioFileService: $e');
      return [];
    }
  }

  /// Direct overwrite save to an existing file on disk.
  static Future<bool> saveFileDirect({
    required String filePath,
    required String content,
  }) async {
    try {
      if (!kIsWeb) {
        final file = io.File(filePath);
        await file.writeAsString(content, flush: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error direct-saving file in StudioFileService: $e');
      return false;
    }
  }

  /// Prompts user with a Save As dialog, writes content, and returns the saved file path.
  static Future<String?> saveFileAs({
    required String fileName,
    required String content,
    String? dialogTitle,
  }) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(content));
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : 'dsf';
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        dialogTitle: dialogTitle ?? 'Save CAD File ($fileName)',
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (uri == null) return null;
      String filePath;
      try {
        filePath = uri.toFilePath();
      } catch (_) {
        filePath = uri.path;
      }
      if (!kIsWeb) {
        try {
          final file = io.File(filePath);
          await file.writeAsString(content, flush: true);
        } catch (_) {}
      }
      return filePath;
    } catch (e) {
      debugPrint('Error in saveFileAs in StudioFileService: $e');
      return null;
    }
  }

  /// Saves content to disk or triggers browser download for .dsf, .dxf, or .dds.
  static Future<bool> saveFile({
    required String fileName,
    required String content,
    String? dialogTitle,
  }) async {
    final res = await saveFileAs(fileName: fileName, content: content, dialogTitle: dialogTitle);
    return res != null;
  }

  /// Parses file content (.dsf, .dxf, or .dds) into one or more DsfDocuments.
  static List<ImportedFileItem> parseContent(
    String raw, {
    String fileName = 'Imported Part',
    String? filePath,
  }) {
    final trimmed = raw.trim();
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    // 1. Check for .dds (Danish Data Sheet - multi-part assembly)
    if (ext == 'dds' ||
        trimmed.contains('"DANISH_DATA_SHEET"') ||
        (trimmed.startsWith('{') && trimmed.contains('"parts"'))) {
      try {
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic> && decoded['parts'] is List) {
          final List parts = decoded['parts'] as List;
          final List<ImportedFileItem> items = [];
          for (int i = 0; i < parts.length; i++) {
            final partDoc = DsfDocument.fromJson(
              parts[i] as Map<String, dynamic>,
            );
            final partName = partDoc.itemName.isNotEmpty
                ? partDoc.itemName
                : '${fileName.replaceAll('.dds', '')} - Part ${i + 1}';
            items.add(
              ImportedFileItem(
                fileName: '$partName.dsf',
                document: partDoc,
                filePath: filePath,
              ),
            );
          }
          if (items.isNotEmpty) return items;
        } else if (decoded is List) {
          final List<ImportedFileItem> items = [];
          for (int i = 0; i < decoded.length; i++) {
            final partDoc = DsfDocument.fromJson(
              decoded[i] as Map<String, dynamic>,
            );
            final partName = partDoc.itemName.isNotEmpty
                ? partDoc.itemName
                : '${fileName.replaceAll('.dds', '')} - Part ${i + 1}';
            items.add(
              ImportedFileItem(
                fileName: '$partName.dsf',
                document: partDoc,
                filePath: filePath,
              ),
            );
          }
          if (items.isNotEmpty) return items;
        }
      } catch (_) {
        // Fall through if parsing as DDS fails
      }
    }

    // 2. Check for .dsf JSON format
    if (ext == 'dsf' ||
        (trimmed.startsWith('{') && trimmed.contains('outerContour'))) {
      try {
        final doc = DsfDocument.parseJsonString(trimmed);
        final baseName = fileName.endsWith('.dsf') ? fileName : '$fileName.dsf';
        return [
          ImportedFileItem(
            fileName: baseName,
            document: doc,
            filePath: filePath,
          ),
        ];
      } catch (_) {
        // Fall through to DXF
      }
    }

    // 3. Fallback: Parse as DXF ASCII flat pattern
    try {
      final doc = DxfDsfImporter.importDxf(
        trimmed,
        productType: fileName.replaceAll('.dxf', ''),
      );
      final baseName = fileName.endsWith('.dxf')
          ? fileName
          : (fileName.endsWith('.dsf') ? fileName : '$fileName.dxf');
      return [
        ImportedFileItem(fileName: baseName, document: doc, filePath: filePath),
      ];
    } catch (e) {
      throw FormatException('Unable to parse file "$fileName": $e');
    }
  }

  /// Serializes multiple open DsfDocuments into a single .dds (Danish Data Sheet) project JSON.
  static String createDdsString(
    List<DsfDocument> documents, {
    String projectName = 'Danish FormMatrix Assembly',
  }) {
    final ddsData = {
      'format': 'DANISH_DATA_SHEET',
      'version': '1.0',
      'projectName': projectName,
      'exportedAt': DateTime.now().toIso8601String(),
      'partCount': documents.length,
      'parts': documents.map((d) => d.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(ddsData);
  }

  /// Exports a document as ASCII DXF string.
  static String exportDxfString(DsfDocument document) {
    return DxfExporter.exportDxf(document);
  }

  /// Creates a new default blank sheet metal document.
  static DsfDocument createBlankDsf({String itemName = 'New Blank Part'}) {
    return DsfDocument.sampleCableTray(
      width: 100,
      height: 50,
      length: 300,
    ).copyWith(itemName: itemName, productType: 'Sheet Metal Part');
  }
}
