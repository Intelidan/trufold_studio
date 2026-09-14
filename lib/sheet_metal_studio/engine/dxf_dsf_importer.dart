// =============================================================================
// dxf_dsf_importer.dart
//
// Ingestion engine for Danish Sheet Fold (.dsf) and standard CAD DXF files.
// Automatically classifies layers (BEND_UP, BEND_DOWN, CUT/EDGES, HOLES)
// according to international sheet metal CAD/CAM conventions (Creo, SolidWorks,
// DraftSight) and triggers planar face decomposition and geometry recognition.
// =============================================================================

import '../models/sheet_metal_material.dart';
import '../models/dsf_document.dart';
import 'dxf_mini_parser.dart';
import 'dxf_geometry_recognition_engine.dart';

class DxfDsfImporter {
  /// Ingests a native `.dsf` JSON string directly.
  static DsfDocument importDsf(String dsfJsonContent) {
    return DsfDocument.parseJsonString(dsfJsonContent);
  }

  /// Ingests a raw ASCII DXF string and reconstructs a full [DsfDocument].
  static DsfDocument importDxf(
    String dxfContent, {
    String productType = 'Sheet Metal Part',
    String itemName = 'Imported Component',
    SheetMetalMaterial material = const SheetMetalMaterial(),
  }) {
    final parsed = DxfMiniParser.parse(dxfContent);
    return DxfGeometryRecognitionEngine.recognize(
      parsed,
      productType: productType,
      itemName: itemName,
      material: material,
    ).generatedDocument;
  }
}
