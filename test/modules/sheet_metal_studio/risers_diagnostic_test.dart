import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';

void main() {
  final files = [
    'assets/dsf_templates/tray_accessories/45_deg_outside_riser_100_50.dsf',
    'assets/dsf_templates/tray_accessories/90_deg_inside_riser_100x50.dsf',
    'assets/dsf_templates/tray_accessories/90_deg_outside_riser_100X50.dsf',
    'assets/dsf_templates/tray_accessories/45_deg_inside_riser_100_50.dsf',
  ];

  for (final path in files) {
    test('Test with corrected face roles for $path', () {
      final f = File(path);
      var dsf = DsfDocument.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);

      // Templates now have the correct roles directly embedded
      final fold = KinematicFoldEngine.foldDocument(dsf, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: dsf, foldResult: fold);

      print('=== FILE: $path ===');
      print('Detected raw openings: ${rawOpenings.length}');
      for (final op in rawOpenings) {
        final measured = CmsOpeningPlaneAnalyzer.analyze(raw: op, document: dsf, foldResult: fold);
        print('  Port ${measured.openingId}: center=(${measured.center.x.toStringAsFixed(1)}, ${measured.center.y.toStringAsFixed(1)}, ${measured.center.z.toStringAsFixed(1)}), normal=(${measured.normal.x.toStringAsFixed(2)}, ${measured.normal.y.toStringAsFixed(2)}, ${measured.normal.z.toStringAsFixed(2)}), W=${measured.width.toStringAsFixed(1)}, H=${measured.height.toStringAsFixed(1)}');
      }
      expect(rawOpenings.length, equals(2));
    });
  }
}
