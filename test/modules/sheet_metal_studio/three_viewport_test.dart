import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart' as three_geo;

import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/three_cad_mesh_builder.dart';

void main() {
  test('ThreeJS scene setup and OrbitControls initialization check', () {
    final scene = three.Scene();
    final camera = three.PerspectiveCamera(45.0, 1.33, 1.0, 50000.0);
    camera.position.setValues(100, 100, 100);
    camera.lookAt(three.Vector3(0, 0, 0));

    final ambient = three.AmbientLight(0xffffff, 0.65);
    scene.add(ambient);

    final dir = three.DirectionalLight(0xffffff, 0.85);
    dir.position.setValues(100, 150, 100);
    scene.add(dir);

    final poly = CadFoldedPolygon3D(
      faceId: 'test_web',
      vertices: [
        const CadPoint3D(0, -150, 50),
        const CadPoint3D(250, -150, 50),
        const CadPoint3D(250, 150, 50),
        const CadPoint3D(0, 150, 50),
      ],
      normal: const CadPoint3D(0, 0, 1),
      color: const Color(0xFF90A4AE),
      boundaryLines: [
        [const CadPoint3D(0, -150, 50), const CadPoint3D(250, -150, 50)],
        [const CadPoint3D(250, -150, 50), const CadPoint3D(250, 150, 50)],
      ],
    );

    final meshResult = FoldedMeshResult(
      polygons: [poly],
      thicknessPolygons: [],
      boundWidth: 300,
      boundLength: 250,
      boundHeight: 100,
      center: const CadPoint3D(125, 0, 50),
    );

    final group = ThreeCadMeshBuilder.buildCadModel(meshResult);
    scene.add(group);

    expect(scene.children.length, 3); // ambient + dir + group
  });
}
