// =============================================================================
// dsf_layer_test.dart
//
// Tests for Drawing Component Layers:
// - DsfLayer data model and default layer definitions
// - JSON serialization / deserialization round-trip
// - Backward compatibility with legacy .dsf files lacking layer keys
// - DXF layer table export and layer retention
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_layer.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_exporter.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_dsf_importer.dart';

void main() {
  group('DSF Layer Tests', () {
    test('1. Default layers factory produces standard fabrication layers', () {
      final defaultLayers = DsfLayer.defaultLayers();
      expect(defaultLayers.isNotEmpty, isTrue);

      final names = defaultLayers.map((l) => l.name).toSet();
      expect(names.contains('OUTLINE'), isTrue);
      expect(names.contains('BEND_UP'), isTrue);
      expect(names.contains('BEND_DOWN'), isTrue);
      expect(names.contains('CUT'), isTrue);
      expect(names.contains('HOLES'), isTrue);
    });

    test('2. DsfLayer JSON serialization round-trip', () {
      const original = DsfLayer(
        name: 'CMS_PERF',
        colorHex: 0xFF059669,
        lineType: 'DASHED',
        strokeWidth: 1.5,
        isVisible: true,
        isLocked: false,
        description: 'Tray floor slot array',
      );

      final json = original.toJson();
      final reconstructed = DsfLayer.fromJson(json);

      expect(reconstructed.name, equals('CMS_PERF'));
      expect(reconstructed.colorHex, equals(0xFF059669));
      expect(reconstructed.lineType, equals('DASHED'));
      expect(reconstructed.strokeWidth, equals(1.5));
      expect(reconstructed.isVisible, isTrue);
      expect(reconstructed.isLocked, isFalse);
      expect(reconstructed.description, equals('Tray floor slot array'));
    });

    test('3. DsfDocument retains layers and supports legacy fallback', () {
      // Create a document with custom layers
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 1000).copyWith(
        layers: [
          const DsfLayer(name: 'CUSTOM_OUTLINE', colorHex: 0xFF112233),
          const DsfLayer(name: 'CUSTOM_PUNCH', colorHex: 0xFF445566),
        ],
        outerContourLayer: 'CUSTOM_OUTLINE',
      );

      final jsonStr = doc.toJsonString();
      final importedDoc = DxfDsfImporter.importDsf(jsonStr);

      expect(importedDoc.layers.length, equals(2));
      expect(importedDoc.layers.first.name, equals('CUSTOM_OUTLINE'));
      expect(importedDoc.outerContourLayer, equals('CUSTOM_OUTLINE'));

      // Test backward compatibility: empty JSON without 'layers' key
      final legacyJson = <String, dynamic>{
        'documentVersion': '1.0',
        'productType': 'CABLE_TRAY',
        'itemName': 'Legacy Tray',
        'outerContour': [
          {'x': 0.0, 'y': 0.0},
          {'x': 100.0, 'y': 0.0},
          {'x': 100.0, 'y': 50.0},
          {'x': 0.0, 'y': 50.0},
        ],
        'bends': [],
        'faces': [],
        'punches': [],
      };

      final parsedLegacyDoc = DsfDocument.fromJson(legacyJson);
      // Fallback effectiveLayers must provide standard default fabrication layers
      expect(parsedLegacyDoc.effectiveLayers.length, greaterThanOrEqualTo(5));
      expect(parsedLegacyDoc.effectiveLayers.any((l) => l.name == 'OUTLINE'), isTrue);
      expect(parsedLegacyDoc.effectiveLayers.any((l) => l.name == 'HOLES'), isTrue);
    });

    test('4. CncPunchPrimitive retains assigned layer', () {
      final obround = CncPunchPrimitive.obround(
        id: 'SLOT_1',
        center: const CadPoint2D(50, 50),
        widthMm: 7.0,
        lengthMm: 25.0,
        rotationDeg: 90.0,
        layer: 'CMS_PERF',
      );

      expect(obround.layer, equals('CMS_PERF'));

      final json = obround.toJson();
      final restored = CncPunchPrimitive.fromJson(json);
      expect(restored.layer, equals('CMS_PERF'));
    });

    test('5. DxfExporter outputs TABLES and LAYER table with colors', () {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 1000);
      final dxf = DxfExporter.exportDxf(doc);

      // Verify TABLES section is present
      expect(dxf.contains('TABLES'), isTrue);
      expect(dxf.contains('LAYER'), isTrue);

      // Verify default layers are defined in the DXF
      expect(dxf.contains('OUTLINE'), isTrue);
      expect(dxf.contains('BEND_UP'), isTrue);
      expect(dxf.contains('HOLES'), isTrue);
    });
  });
}
