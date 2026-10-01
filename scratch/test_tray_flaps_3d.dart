import 'dart:convert';
import 'dart:io';

import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_bend_90_scaler.dart';

void main() {
  final file = File('assets/dsf_templates/tray_accessories/90_deg_bend_100x50.dsf');
  final doc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);

  final scaled = TrayBend90Scaler.scale(
    baseline: doc,
    targetWidth: 100.0,
    targetHeight: 50.0,
    targetRadius: 180.0,
    includeCouplerFlaps: true,
    couplerFlapLength: 30.0,
  );

  print('=== 2D FACES ===');
  for (final f in scaled.faces) {
    if (f.id == 'F_8' || f.id == 'F_FLAP_THROAT_P1' || f.id == 'F_1' || f.id == 'F_FLAP_WING_P1') {
      print('Face ${f.id}:');
      for (final v in f.vertices) {
        print('   (${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)})');
      }
    }
  }

  print('=== 2D BENDS ===');
  for (final b in scaled.bends) {
    if (b.id == 'B1' || b.id == 'BF_THROAT_P1' || b.id == 'B2' || b.id == 'BF_WING_P1') {
      print('Bend ${b.id}: p1=(${b.p1.x.toStringAsFixed(1)}, ${b.p1.y.toStringAsFixed(1)}) p2=(${b.p2.x.toStringAsFixed(1)}, ${b.p2.y.toStringAsFixed(1)}) angle=${b.targetAngleDeg} dir=${b.direction}');
    }
  }

  final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);

  print('=== 3D FOLDED FACES VERTICES ===');
  for (final poly in fold.polygons) {
    if (poly.faceId.startsWith('F_FLAP_') || poly.faceId == 'F_8' || poly.faceId == 'F_1' || poly.faceId == 'F_3') {
      print('Face ${poly.faceId}:');
      for (final v in poly.vertices) {
        print('   (${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}, ${v.z.toStringAsFixed(1)})');
      }
    }
  }
}
