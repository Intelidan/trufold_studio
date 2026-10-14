//Performs mesh boundary modifications by running point-in-polygon filtration pipelines across vertex matrices.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../cad_parameter_engine/cad_models.dart';

class CADBooleanEngine {
  static Map<String, dynamic> executePassThroughCut({
    required Float32List srcV,
    required Uint16List srcI,
    required CADSketchPlane plane,
    required List<Offset> path,
    required double thickness,
  }) {
    List<double> finalV = [];
    List<int> finalI = [];
    int idxTracker = 0;
    final z = plane.normal.normalized();
    final y = plane.up.normalized();
    final x = y.cross(z).normalized();

    for (int i = 0; i < srcI.length; i += 3) {
      int i0 = srcI[i] * 6;
      int i1 = srcI[i + 1] * 6;
      int i2 = srcI[i + 2] * 6;
      final v0 = vm.Vector3(srcV[i0], srcV[i0 + 1], srcV[i0 + 2]);
      final v1 = vm.Vector3(srcV[i1], srcV[i1 + 1], srcV[i1 + 2]);
      final v2 = vm.Vector3(srcV[i2], srcV[i2 + 1], srcV[i2 + 2]);

      Offset l0 = Offset((v0 - plane.origin).dot(x), (v0 - plane.origin).dot(y));
      Offset l1 = Offset((v1 - plane.origin).dot(x), (v1 - plane.origin).dot(y));
      Offset l2 = Offset((v2 - plane.origin).dot(x), (v2 - plane.origin).dot(y));
      Offset center = Offset((l0.dx + l1.dx + l2.dx) / 3, (l0.dy + l1.dy + l2.dy) / 3);

      if (_inside(center, path)) {
        continue;
      } // Exclude faces within target boundary profile loop

      finalV.addAll([v0.x, v0.y, v0.z, srcV[i0 + 3], srcV[i0 + 4], srcV[i0 + 5]]);
      finalV.addAll([v1.x, v1.y, v1.z, srcV[i1 + 3], srcV[i1 + 4], srcV[i1 + 5]]);
      finalV.addAll([v2.x, v2.y, v2.z, srcV[i2 + 3], srcV[i2 + 4], srcV[i2 + 5]]);
      finalI.addAll([idxTracker, idxTracker + 1, idxTracker + 2]);
      idxTracker += 3;
    }
    return {'vertices': Float32List.fromList(finalV), 'indices': Uint16List.fromList(finalI)};
  }

  static bool _inside(Offset pt, List<Offset> poly) {
    bool res = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      if ((poly[i].dy > pt.dy) != (poly[j].dy > pt.dy) && (pt.dx < (poly[j].dx - poly[i].dx) * (pt.dy - poly[i].dy) / (poly[j].dy - poly[i].dy) + poly[i].dx)) {
        res = !res;
      }
      j = i;
    }
    return res;
  }
}
