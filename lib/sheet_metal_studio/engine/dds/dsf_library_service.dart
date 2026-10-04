// =============================================================================
// dsf_library_service.dart
//
// DSF Template Library Discovery & Analysis Service.
// Discovers, inspects, and analyzes all .dsf templates in the app directory:
// 1. Scans assets/dxf_templates/ (and subdirectories) on disk and via AssetBundle.
// 2. Headless geometric inspection: calculates 2D bounding boxes, bend count,
//    punch count, and surface area.
// 3. 3D kinematic folding: computes folded mesh results for isometric previews.
// 4. Provides structured DsfLibraryItem models for tabular UI rendering.
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/dsf_document.dart';
import '../../models/dxf_fitting_metadata.dart';
import '../kinematic_fold_engine.dart';
import 'dds_template_resolver.dart';

/// Comprehensive metadata and geometry for a single DSF template in the library.
class DsfLibraryItem {
  final String templateId;
  final String displayName;
  final String fileName;
  final String category; // Legacy / fitting category (e.g. 'Flat Bends & Elbows')
  final String systemCategory; // 'Cable Ladders', 'Cable Trays', 'Cable Trunking'
  final String componentType; // 'Length' vs 'Accessory'
  final String fittingType; // 'Flat Bends & Elbows', 'Vertical Risers', 'Tees & Branches', 'Crosses & 4-Ways', 'Reducers & Transitions', 'Straight Lengths'
  final String description;
  final String defaultDimensions;
  final DsfDocument document;
  final FoldedMeshResult? foldedMesh;
  final int bendCount;
  final int punchCount;
  final double surfaceAreaMm2;
  final double boundWidthMm;
  final double boundHeightMm;

  const DsfLibraryItem({
    required this.templateId,
    required this.displayName,
    required this.fileName,
    required this.category,
    required this.systemCategory,
    required this.componentType,
    required this.fittingType,
    required this.description,
    required this.defaultDimensions,
    required this.document,
    this.foldedMesh,
    required this.bendCount,
    required this.punchCount,
    required this.surfaceAreaMm2,
    required this.boundWidthMm,
    required this.boundHeightMm,
  });

  double get surfaceAreaM2 => surfaceAreaMm2 / 1000000.0;
  double get estimatedWeightKg => surfaceAreaM2 * document.material.thicknessMm * 7.85;
}

class DsfLibraryService {
  static const String defaultTemplatesDir = 'assets/dsf_templates/trunking_accessories';

  static final Map<String, DsfLibraryItem> _cache = {};

  /// Loads all DSF templates from standard registry and discovers any on disk.
  static Future<List<DsfLibraryItem>> loadAllTemplates({String? baseDirectory}) async {
    if (_cache.isNotEmpty) {
      return _cache.values.toList();
    }

    final dirPath = baseDirectory ?? defaultTemplatesDir;
    final results = <DsfLibraryItem>[];

    // 1. Process all known standard templates in DdsTemplateResolver
    for (final entry in DdsTemplateResolver.standardTemplates.entries) {
      final templateId = entry.key;
      final fileName = entry.value;

      try {
        final doc = await _loadDsfDocument(dirPath, fileName);
        if (doc != null) {
          final item = _createLibraryItem(templateId, fileName, doc);
          _cache[templateId] = item;
          results.add(item);
        }
      } catch (e) {
        debugPrint('DsfLibraryService: Error loading standard $fileName: $e');
      }
    }

    // 2. Discover any additional .dsf files in tray, trunking, or ladders folders on desktop filesystem
    final directoriesToScan = <Directory>[];
    try {
      directoriesToScan.add(Directory(dirPath));
      directoriesToScan.add(Directory('assets/dsf_templates'));
      directoriesToScan.add(Directory('assets/dsf_templates/trunking_accessories'));
      directoriesToScan.add(Directory('assets/dsf_templates/tray_accessories'));
      directoriesToScan.add(Directory('assets/dsf_templates/ladders'));
      if (!kIsWeb) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        directoriesToScan.add(Directory('$exeDir/$dirPath'));
        directoriesToScan.add(Directory('$exeDir/assets/dsf_templates'));
        directoriesToScan.add(Directory('$exeDir/assets/dsf_templates/trunking_accessories'));
        directoriesToScan.add(Directory('$exeDir/assets/dsf_templates/tray_accessories'));
        directoriesToScan.add(Directory('$exeDir/assets/dsf_templates/ladders'));
      }
    } catch (_) {}

    final scannedPaths = <String>{};
    for (final dir in directoriesToScan) {
      try {
        if (dir.existsSync()) {
          final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.toLowerCase().endsWith('.dsf'));
          for (final file in files) {
            if (!scannedPaths.add(file.path.toLowerCase())) continue;
            final fileName = file.uri.pathSegments.last;
            // Check if already loaded
            if (_cache.values.any((i) => i.fileName.toLowerCase() == fileName.toLowerCase())) {
              continue;
            }

            try {
              final content = file.readAsStringSync();
              final jsonMap = jsonDecode(content) as Map<String, dynamic>;
              final doc = DsfDocument.fromJson(jsonMap);
              final templateId = 'custom_${fileName.replaceAll('.dsf', '').replaceAll(' ', '_').toLowerCase()}';
              final item = _createLibraryItem(templateId, fileName, doc);
              _cache[templateId] = item;
              results.add(item);
            } catch (e) {
              debugPrint('DsfLibraryService: Error reading custom file $fileName: $e');
            }
          }
        }
      } catch (_) {
        // In web or restricted environments, directory list may be unavailable
      }
    }

    return results;
  }

  /// Synchronously loads templates (for desktop CLI / unit tests).
  static List<DsfLibraryItem> loadAllTemplatesSync({String? baseDirectory}) {
    if (_cache.isNotEmpty) {
      return _cache.values.toList();
    }

    final dirPath = baseDirectory ?? defaultTemplatesDir;
    final results = <DsfLibraryItem>[];

    for (final entry in DdsTemplateResolver.standardTemplates.entries) {
      final templateId = entry.key;
      final fileName = entry.value;

      final candidatePaths = [
        '$dirPath/$fileName',
        'assets/dsf_templates/trunking_accessories/$fileName',
        'assets/dsf_templates/tray_accessories/$fileName',
        'assets/dsf_templates/ladders/$fileName',
        'assets/dsf_templates/$fileName',
        if (!kIsWeb) ...[
          '${File(Platform.resolvedExecutable).parent.path}/$dirPath/$fileName',
          '${File(Platform.resolvedExecutable).parent.path}/assets/dsf_templates/trunking_accessories/$fileName',
          '${File(Platform.resolvedExecutable).parent.path}/assets/dsf_templates/tray_accessories/$fileName',
          '${File(Platform.resolvedExecutable).parent.path}/assets/dsf_templates/ladders/$fileName',
          '${File(Platform.resolvedExecutable).parent.path}/assets/dsf_templates/$fileName',
        ],
        'assets/dxf_templates/trunking_accessories/$fileName',
      ];

      for (final p in candidatePaths) {
        final file = File(p);
        if (file.existsSync()) {
          try {
            final content = file.readAsStringSync();
            final jsonMap = jsonDecode(content) as Map<String, dynamic>;
            final doc = DsfDocument.fromJson(jsonMap);
            final item = _createLibraryItem(templateId, fileName, doc);
            _cache[templateId] = item;
            results.add(item);
            break;
          } catch (e) {
            debugPrint('DsfLibraryService: Sync load error for $fileName: $e');
          }
        }
      }
    }

    return results;
  }

  /// Clears cached library items.
  static void clearCache() {
    _cache.clear();
  }

  static Future<DsfDocument?> _loadDsfDocument(String dirPath, String fileName) async {
    // Try Flutter asset bundle first
    final candidateAssetPaths = [
      '$dirPath/$fileName',
      'assets/dsf_templates/trunking_accessories/$fileName',
      'assets/dsf_templates/tray_accessories/$fileName',
      'assets/dsf_templates/ladders/$fileName',
      'assets/dsf_templates/$fileName',
      'assets/dxf_templates/trunking_accessories/$fileName',
    ];

    for (final assetPath in candidateAssetPaths) {
      try {
        final jsonStr = await rootBundle.loadString(assetPath);
        return DsfDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      } catch (_) {}
    }

    // Fallback to direct File read on Desktop
    final candidateFilePaths = [
      '$dirPath/$fileName',
      'assets/dsf_templates/trunking_accessories/$fileName',
      'assets/dsf_templates/tray_accessories/$fileName',
      'assets/dsf_templates/ladders/$fileName',
      'assets/dsf_templates/$fileName',
      if (!kIsWeb) ...[
        '${File(Platform.resolvedExecutable).parent.path}/$dirPath/$fileName',
        '${File(Platform.resolvedExecutable).parent.path}/assets/dsf_templates/trunking_accessories/$fileName',
        '${File(Platform.resolvedExecutable).parent.path}/assets/dsf_templates/tray_accessories/$fileName',
        '${File(Platform.resolvedExecutable).parent.path}/assets/dsf_templates/ladders/$fileName',
        '${File(Platform.resolvedExecutable).parent.path}/assets/dsf_templates/$fileName',
      ],
      'assets/dxf_templates/trunking_accessories/$fileName',
    ];

    for (final p in candidateFilePaths) {
      final file = File(p);
      if (file.existsSync()) {
        try {
          final content = await file.readAsString();
          return DsfDocument.fromJson(jsonDecode(content) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    return null;
  }

  static DsfLibraryItem _createLibraryItem(String templateId, String fileName, DsfDocument doc) {
    final fittingMeta = DxfFittingMetadata.fromDocument(doc);
    final variantMeta = doc.metadata['fittingVariant'] as String? ??
        doc.metadata['variantName'] as String?;
    final metaVariant = fittingMeta?.variantName;
    final displayName = (variantMeta != null && variantMeta.trim().isNotEmpty)
        ? variantMeta.trim()
        : (DdsTemplateResolver.templateDisplayNames[templateId] ??
            (metaVariant != null && metaVariant.isNotEmpty && metaVariant != 'Standard'
                ? metaVariant
                : _formatDisplayNameFromFileName(fileName)));

    // Bounding box, area & kinematic / generative mesh
    FoldedMeshResult? mesh;
    double totalArea = 0.0;
    int bendCount = doc.bends.length;
    int punchCount = doc.punches.length;
    double boundW = 300.0;
    double boundH = 300.0;

    if (doc.metadata['isLadderAssembly'] == true || doc.productType == 'cable_ladder') {
      final double totalWeightKg = (doc.metadata['totalSteelWeightKg'] as num?)?.toDouble() ?? 5.0;
      totalArea = (totalWeightKg / (doc.material.thicknessMm * 7.85)) * 1000000.0;
      bendCount = ((doc.metadata['rungCount'] as num?)?.toInt() ?? 4) * 2 + 4;
      punchCount = (doc.metadata['passThroughSlotCount'] as num?)?.toInt() ?? 0;
      boundW = (doc.metadata['width'] as num?)?.toDouble() ?? 300.0;
      boundH = (doc.metadata['length'] as num?)?.toDouble() ?? 1500.0;
      if (doc.faces.isNotEmpty) {
        double minX = double.infinity, minY = double.infinity;
        double maxX = -double.infinity, maxY = -double.infinity;
        for (final face in doc.faces) {
          for (final v in face.vertices) {
            if (v.x < minX) minX = v.x;
            if (v.y < minY) minY = v.y;
            if (v.x > maxX) maxX = v.x;
            if (v.y > maxY) maxY = v.y;
          }
        }
        if (minX.isFinite && maxX.isFinite) boundW = maxX - minX;
        if (minY.isFinite && maxY.isFinite) boundH = maxY - minY;
      }
      try {
        if (doc.bends.isNotEmpty) {
          mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
        }
      } catch (_) {}
    } else {
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final face in doc.faces) {
        totalArea += face.areaMm2;
        for (final v in face.vertices) {
          if (v.x < minX) minX = v.x;
          if (v.y < minY) minY = v.y;
          if (v.x > maxX) maxX = v.x;
          if (v.y > maxY) maxY = v.y;
        }
      }
      boundW = (minX.isFinite && maxX.isFinite) ? (maxX - minX) : 200.0;
      boundH = (minY.isFinite && maxY.isFinite) ? (maxY - minY) : 200.0;
      try {
        if (doc.bends.isNotEmpty) {
          mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
        }
      } catch (e) {
        debugPrint('DsfLibraryService: Warning - kinematic fold failed for $fileName: $e');
      }
    }

    final systemCategory = _resolveSystemCategory(templateId, fileName, doc);
    final componentType = _resolveComponentType(templateId, fileName, doc);
    final fittingType = _resolveFittingType(templateId, fileName, componentType);
    final dims = _resolveDefaultDimensions(templateId, fileName, doc);
    final desc = _resolveDescription(templateId, displayName, dims);

    return DsfLibraryItem(
      templateId: templateId,
      displayName: displayName,
      fileName: fileName,
      category: fittingType,
      systemCategory: systemCategory,
      componentType: componentType,
      fittingType: fittingType,
      description: desc,
      defaultDimensions: dims,
      document: doc,
      foldedMesh: mesh,
      bendCount: bendCount,
      punchCount: punchCount,
      surfaceAreaMm2: totalArea > 0 ? totalArea : (boundW * boundH * 0.7),
      boundWidthMm: boundW,
      boundHeightMm: boundH,
    );
  }

  static String _formatDisplayNameFromFileName(String fileName) {
    final clean = fileName.replaceAll('.dsf', '').replaceAll('_', ' ');
    return clean.split(' ').map((word) {
      if (word.isEmpty) return '';
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
  }

  static String _resolveSystemCategory(String templateId, String fileName, DsfDocument doc) {
    final lower = '$templateId $fileName ${doc.productType} ${doc.metadata['category'] ?? ''}'.toLowerCase();
    if (lower.contains('ladder')) return 'Cable Ladders';
    if (lower.contains('tray')) return 'Cable Trays';
    if (lower.contains('trunking')) return 'Cable Trunking';
    return 'Cable Trunking';
  }

  static String _resolveComponentType(String templateId, String fileName, DsfDocument doc) {
    final lower = '$templateId $fileName ${doc.itemName}'.toLowerCase();
    if (lower.contains('straight') || lower.contains('length') || lower.contains('3000mm') || lower.contains('channel')) {
      return 'Length';
    }
    return 'Accessory';
  }

  static String _resolveFittingType(String templateId, String fileName, String componentType) {
    if (componentType == 'Length') return 'Straight Lengths';
    final lower = '$templateId $fileName'.toLowerCase();
    if (lower.contains('bend') || lower.contains('elbow')) return 'Flat Bends & Elbows';
    if (lower.contains('riser')) return 'Vertical Risers';
    if (lower.contains('tee')) return 'Tees & Branches';
    if (lower.contains('cross')) return 'Crosses & 4-Ways';
    if (lower.contains('reducer')) return 'Reducers & Transitions';
    return 'Fittings & Accessories';
  }

  static String _resolveDefaultDimensions(String templateId, String fileName, DsfDocument doc) {
    final lower = '$templateId $fileName'.toLowerCase();
    if (lower.contains('ladder_straight')) return 'W: 300 mm, H: 100 mm, L: 3000 mm';
    if (lower.contains('ladder_bend_90')) return 'W: 300 mm, H: 100 mm, 90° Flat Bend (R300)';
    if (lower.contains('ladder_bend_45')) return 'W: 300 mm, H: 100 mm, 45° Flat Bend (R300)';
    if (lower.contains('ladder_inside_riser_90')) return 'W: 300 mm, H: 100 mm, 90° Inside Riser (R300)';
    if (lower.contains('ladder_outside_riser_90')) return 'W: 300 mm, H: 100 mm, 90° Outside Riser (R300)';
    if (lower.contains('ladder_reducer')) return 'W1: 400 mm → W2: 200 mm, H: 100 mm';
    if (lower.contains('ladder_equal_tee')) return 'All Ports: 300×100 mm (R300)';
    if (lower.contains('ladder_equal_cross')) return 'All Ports: 300×100 mm (R300)';
    if (lower.contains('reducer')) return 'Port 1: 100×100 mm → Port 2: 50×50 mm';
    if (lower.contains('unequal_tee')) return 'Run: 100×100 mm, Branch: 50×50 mm';
    if (lower.contains('equal_tee')) return 'All 3 Ports: 100×100 mm';
    if (lower.contains('unequal_cross')) return 'Run: 100×50 mm, Cross: 100×50 mm';
    if (lower.contains('equal_cross')) return 'All 4 Ports: 100×100 mm';
    if (lower.contains('inside_riser_90')) return 'Port: 100×100 mm, Angle: 90° Inside';
    if (lower.contains('outside_riser_90')) return 'Port: 100×100 mm, Angle: 90° Outside';
    if (lower.contains('inside_riser_45')) return 'Port: 100×100 mm, Angle: 45° Inside';
    if (lower.contains('outside_riser_45')) return 'Port: 100×100 mm, Angle: 45° Outside';
    if (lower.contains('bend_90')) return 'Port: 100×100 mm, Angle: 90° Flat';
    if (lower.contains('bend_45')) return 'Port: 100×100 mm, Angle: 45° Flat';
    if (lower.contains('z_tool') || lower.contains('z tool')) return 'Offset Step: 100 mm';

    return '${doc.material.materialGrade} (${doc.material.thicknessMm} mm)';
  }

  static String _resolveDescription(String templateId, String displayName, String dims) {
    return 'Standard cable management $displayName with integrated coupler holes and parametric bends. Baseline: $dims.';
  }
}
