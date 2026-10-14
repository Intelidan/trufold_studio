// Generates 3D drawing grids, dynamic dashed construction patterns, and inference guides using raw unlit line segment vertex buffers.

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../cad_parameter_engine/cad_models.dart';

class CADGeometryBuilders {
  static Node buildGridNode({required vm.Vector3 origin, required vm.Vector3 normal, required vm.Vector3 up, double spacing = 0.1, int count = 20}) {
    final z = normal.normalized();
    final y = up.normalized();
    final x = y.cross(z).normalized();
    final List<double> v = [];
    double ext = (count ~/ 2) * spacing;

    for (int i = 0; i <= count; i++) {
      double o = -ext + (i * spacing);
      vm.Vector3 sW = origin + (x * o) - (y * ext);
      vm.Vector3 eW = origin + (x * o) + (y * ext);
      v.addAll([sW.x, sW.y, sW.z, eW.x, eW.y, eW.z]);
    }
    final lineData = LineSegmentData(positions: Float32List.fromList(v));
    final lineGeom = LineSegmentsGeometry(lineData, width: 1.0);
    final mat = UnlitMaterial()..baseColorFactor = vm.Vector4(0.2, 0.5, 1.0, 0.35);
    return Node(
      mesh: Mesh(lineGeom, mat),
    );
  }

  static Node? buildDashedMesh({required List<CADLineSegment> pool, required vm.Vector3 ori, required vm.Vector3 nrm, required vm.Vector3 up}) {
    final active = pool.where((s) => !s.isDeleted && s.isConstruction).toList();
    if (active.isEmpty) return null;
    final z = nrm.normalized();
    final y = up.normalized();
    final x = y.cross(z).normalized();
    final List<double> v = [];

    for (var s in active) {
      vm.Vector3 sW = ori + (x * s.start.dx) + (y * s.start.dy);
      vm.Vector3 eW = ori + (x * s.end.dx) + (y * s.end.dy);
      vm.Vector3 d = eW - sW;
      double dist = d.length;
      if (dist < 0.01) continue;
      vm.Vector3 dir = d.normalized();
      double walked = 0.0;
      while (walked < dist) {
        double end = (walked + 0.06).clamp(0, dist);
        vm.Vector3 p1 = sW + (dir * walked);
        vm.Vector3 p2 = sW + (dir * end);
        v.addAll([p1.x, p1.y, p1.z, p2.x, p2.y, p2.z]);
        walked += 0.1;
      }
    }
    if (v.isEmpty) return null;
    final lineData = LineSegmentData(positions: Float32List.fromList(v));
    final lineGeom = LineSegmentsGeometry(lineData, width: 1.5);
    final mat = UnlitMaterial()..baseColorFactor = vm.Vector4(0.2, 0.7, 1.0, 0.9);
    return Node(
      mesh: Mesh(lineGeom, mat),
    );
  }
}
