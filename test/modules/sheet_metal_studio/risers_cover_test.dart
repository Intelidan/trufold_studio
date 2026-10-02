import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';

void main() {
  final files = [
    'assets/dsf_templates/tray_accessories/45_deg_outside_riser_100_50.dsf',
    'assets/dsf_templates/tray_accessories/90_deg_inside_riser_100x50.dsf',
    'assets/dsf_templates/tray_accessories/90_deg_outside_riser_100X50.dsf',
    'assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf',
  ];

  for (final path in files) {
    test('Cover generation test for $path', () {
      final f = File(path);
      final dsf = DsfDocument.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);

      final coverData = TrunkingCoverGenerator.generateCover(dsf);
      expect(coverData, isNotNull, reason: 'Cover must be generated for $path');
      print('Cover for $path: faces=${coverData!.document.faces.length}, bends=${coverData.document.bends.length}');

      // Verify cover folds in 3D
      final foldResult = KinematicFoldEngine.foldDocument(coverData.document, foldProgress: 1.0);
      expect(foldResult.polygons.length, greaterThanOrEqualTo(1));
    });
  }
}
