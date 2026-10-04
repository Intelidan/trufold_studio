import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart' as three_geo;

import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

three.Object3D createMeshFromCadPolygon(CadFoldedPolygon3D poly) {
  if (poly.vertices.length < 3) return three.Group();

  final n = poly.normal;
  final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
  final nz = lenN > 1e-6 ? CadPoint3D(n.x / lenN, n.y / lenN, n.z / lenN) : const CadPoint3D(0, 0, 1);

  final up = nz.z.abs() < 0.9 ? const CadPoint3D(0, 0, 1) : const CadPoint3D(1, 0, 0);

  final ux = up.y * nz.z - up.z * nz.y;
  final uy = up.z * nz.x - up.x * nz.z;
  final uz = up.x * nz.y - up.y * nz.x;
  final lenU = math.sqrt(ux * ux + uy * uy + uz * uz);
  final u = CadPoint3D(ux / lenU, uy / lenU, uz / lenU);

  final vx = nz.y * u.z - nz.z * u.y;
  final vy = nz.z * u.x - nz.x * u.z;
  final vz = nz.x * u.y - nz.y * u.x;
  final v = CadPoint3D(vx, vy, vz);

  final origin = poly.vertices[0];

  (double, double) projectTo2D(CadPoint3D pt) {
    final dx = pt.x - origin.x;
    final dy = pt.y - origin.y;
    final dz = pt.z - origin.z;
    return (
      dx * u.x + dy * u.y + dz * u.z,
      dx * v.x + dy * v.y + dz * v.z,
    );
  }

  final shape = three.Shape();
  final p0 = projectTo2D(poly.vertices[0]);
  shape.moveTo(p0.$1, p0.$2);
  for (int i = 1; i < poly.vertices.length; i++) {
    final pi = projectTo2D(poly.vertices[i]);
    shape.lineTo(pi.$1, pi.$2);
  }
  shape.closePath();

  for (final hole in poly.holes) {
    if (hole.length < 3) continue;
    final holePath = three.Path();
    final hp0 = projectTo2D(hole[0]);
    holePath.moveTo(hp0.$1, hp0.$2);
    for (int i = 1; i < hole.length; i++) {
      final hpi = projectTo2D(hole[i]);
      holePath.lineTo(hpi.$1, hpi.$2);
    }
    holePath.closePath();
    shape.holes.add(holePath);
  }

  final geometry = three_geo.ShapeGeometry([shape]);

  final material = three.MeshStandardMaterial.fromMap({
    'color': poly.color.value & 0xFFFFFF,
    'roughness': 0.45,
    'metalness': 0.55,
    'side': three.DoubleSide,
    'depthTest': true,
    'depthWrite': true,
  });

  final mesh = three.Mesh(geometry, material);

  final mat4 = three.Matrix4();
  mat4.makeBasis(
    three.Vector3(u.x, u.y, u.z),
    three.Vector3(v.x, v.y, v.z),
    three.Vector3(nz.x, nz.y, nz.z),
  );
  mat4.setPosition(origin.x, origin.y, origin.z);
  mesh.applyMatrix4(mat4);

  return mesh;
}

three.LineSegments createEdgesMesh(List<CadFoldedPolygon3D> polygons) {
  final lineCoords = <double>[];

  for (final poly in polygons) {
    for (final seg in poly.boundaryLines) {
      if (seg.length >= 2) {
        for (int i = 0; i < seg.length - 1; i++) {
          lineCoords.addAll([
            seg[i].x, seg[i].y, seg[i].z,
            seg[i + 1].x, seg[i + 1].y, seg[i + 1].z,
          ]);
        }
      }
    }
  }

  final geometry = three.BufferGeometry();
  if (lineCoords.isNotEmpty) {
    geometry.setAttribute(
      three.Attribute.position,
      three.Float32BufferAttribute.fromList(lineCoords, 3),
    );
  }

  final material = three.LineBasicMaterial.fromMap({
    'color': 0x334155,
    'linewidth': 1.0,
    'depthTest': true,
    'depthWrite': true,
  });

  return three.LineSegments(geometry, material);
}

void main() {
  test('Convert CadFoldedPolygon3D to Three.js Object3D with hole and edges', () {
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
        [const CadPoint3D(250, 150, 50), const CadPoint3D(0, 150, 50)],
        [const CadPoint3D(0, 150, 50), const CadPoint3D(0, -150, 50)],
      ],
      holes: [
        [
          const CadPoint3D(50, -20, 50),
          const CadPoint3D(100, -20, 50),
          const CadPoint3D(100, 20, 50),
          const CadPoint3D(50, 20, 50),
        ]
      ],
    );

    final object3d = createMeshFromCadPolygon(poly);
    expect(object3d, isNotNull);
    expect(object3d is three.Mesh, isTrue);

    final edges = createEdgesMesh([poly]);
    expect(edges, isNotNull);
    expect(edges.geometry, isNotNull);
  });
}
