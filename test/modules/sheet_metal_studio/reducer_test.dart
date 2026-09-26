import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';

import 'package:trufold_studio/sheet_metal_studio/engine/dxf_dsf_importer.dart';

void main() {
  test('Test import of reducer_150x100x100x100.dxf', () {
    final dxfFile = File('assets/dxf_templates/trunking_accessories/reducer_150x100x100x100.dxf');
    if (dxfFile.existsSync()) {
      final doc = DxfDsfImporter.importDxf(dxfFile.readAsStringSync(), productType: 'reducer', itemName: 'reducer_150x100x100x100.dxf');
      print('Imported DXF baseFaceId: ${doc.baseFaceId}');
      print('Imported DXF bends count: ${doc.bends.length}');
      for (final b in doc.bends) {
        print('  Bend ${b.id}: angle=${b.targetAngleDeg}, dir=${b.direction}, parent=${b.parentFaceId}, child=${b.childFaceId}');
      }
      for (final f in doc.faces) {
        print('  Face ${f.id}: role=${f.role}, label=${f.label}');
      }
    }
  });
  test('Test decompose and fold of reducer_150x100x100x100', () {
    final file = File('assets/dxf_templates/trunking_accessories/reducer_150x100x100x100.dsf');
    expect(file.existsSync(), isTrue);

    final dsf = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    print('Initial baseFaceId in file: ${dsf.baseFaceId}');
    for (final f in dsf.faces) {
      print('  File face ${f.id}: role=${f.role}, label=${f.label}');
    }

    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: dsf.outerContour,
      bends: dsf.bends,
      cutLines: dsf.cutLines,
      preferredBaseFaceId: dsf.baseFaceId,
    );
    for (final f in decomp.faces) {
      print('  Decomp face ${f.id}: role=${f.role}, label=${f.label}');
    }

    final foldDoc = dsf.copyWith(
      faces: decomp.faces,
      bends: decomp.connectedBends,
      baseFaceId: decomp.baseFaceId,
    );

    // Save decomposed faces and bends to the file
    file.writeAsStringSync(jsonEncode(foldDoc.toJson()));
    print('Saved decomposed document to file with baseFaceId: ${foldDoc.baseFaceId}');

    final foldResult = KinematicFoldEngine.foldDocument(foldDoc, foldProgress: 1.0);
    print('Polygons folded count: ${foldResult.polygons.length}');
    for (final poly in foldResult.polygons) {
      final zs = poly.vertices.map((v) => v.z).toList();
      final minZ = zs.reduce((a, b) => a < b ? a : b);
      final maxZ = zs.reduce((a, b) => a > b ? a : b);
      print('Poly ${poly.faceId}: Z in [${minZ.toStringAsFixed(1)}, ${maxZ.toStringAsFixed(1)}]');
    }

    final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: foldDoc, foldResult: foldResult);
    print('\nRaw openings count: ${rawOpenings.length}');
    for (final raw in rawOpenings) {
      final measured = CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: foldDoc, foldResult: foldResult);
      print('Opening: normal=${measured.normal} W=${measured.width.toStringAsFixed(1)} H=${measured.height.toStringAsFixed(1)} center=${measured.center}');
    }
  });
}
