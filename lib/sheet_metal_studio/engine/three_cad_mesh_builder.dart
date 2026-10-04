import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart' as three_geo;

import '../models/cad_primitives.dart';
import 'kinematic_fold_engine.dart';

/// Converts TruFold Studio's [FoldedMeshResult] into hardware-accelerated [three.Group]
/// with true GPU Depth Testing (Z-buffer), metallic PBR shading, and crisp boundary edges.
class ThreeCadMeshBuilder {
  /// Builds a complete hardware-accelerated 3D model from a [FoldedMeshResult].
  static three.Group buildCadModel(
    FoldedMeshResult meshResult, {
    String? selectedFaceId,
    String? hoveredFaceId,
    String? selectedPunchId,
    String? hoveredPunchId,
    bool showWireframe = true,
  }) {
    final rootGroup = three.Group();
    final pivot = meshResult.center;

    // Sub-group for shaded faces
    final facesGroup = three.Group();
    // Sub-group for crisp boundary lines and laser cuts
    final edgesGroup = three.Group();

    final lineCoords = <double>[];
    final laserCutCoords = <double>[];

    for (final poly in meshResult.allPolygons) {
      if (poly.vertices.length < 3) continue;

      // 1. Shaded Face with automatic hole triangulation
      final faceMesh = _createFaceMesh(poly, pivot: pivot, isSelected: poly.faceId == selectedFaceId, isHovered: poly.faceId == hoveredFaceId);
      if (faceMesh != null) {
        facesGroup.add(faceMesh);
      }

      // 2. Collect boundary lines for hardware edge rendering
      for (final seg in poly.boundaryLines) {
        if (seg.length >= 2) {
          for (int i = 0; i < seg.length - 1; i++) {
            lineCoords.addAll([
              seg[i].x - pivot.x,
              seg[i].y - pivot.y,
              seg[i].z - pivot.z,
              seg[i + 1].x - pivot.x,
              seg[i + 1].y - pivot.y,
              seg[i + 1].z - pivot.z,
            ]);
          }
        }
      }

      // 3. Laser cut traces
      for (final seg in poly.cutSegments) {
        if (seg.length >= 2) {
          for (int i = 0; i < seg.length - 1; i++) {
            laserCutCoords.addAll([
              seg[i].x - pivot.x,
              seg[i].y - pivot.y,
              seg[i].z - pivot.z,
              seg[i + 1].x - pivot.x,
              seg[i + 1].y - pivot.y,
              seg[i + 1].z - pivot.z,
            ]);
          }
        }
      }
    }

    rootGroup.add(facesGroup);

    // 4. Batch-rendered outline edges (single draw call)
    if (showWireframe && lineCoords.isNotEmpty) {
      final edgeGeo = three.BufferGeometry();
      edgeGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(lineCoords, 3));
      final edgeMat = three.LineBasicMaterial.fromMap({
        'color': 0x334155, // Slate 700 crisp CAD edge
        'linewidth': 1.0,
        'depthTest': true,
        'depthWrite': false, // Avoid z-fighting with adjacent face
      });
      edgesGroup.add(three.LineSegments(edgeGeo, edgeMat));
    }

    // 5. Laser cut lines (cyan dashed / distinct CAD color)
    if (laserCutCoords.isNotEmpty) {
      final laserGeo = three.BufferGeometry();
      laserGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(laserCutCoords, 3));
      final laserMat = three.LineBasicMaterial.fromMap({
        'color': 0x0284C7, // Vivid cyan-blue laser kerf
        'linewidth': 1.5,
        'depthTest': true,
        'depthWrite': false,
      });
      edgesGroup.add(three.LineSegments(laserGeo, laserMat));
    }

    rootGroup.add(edgesGroup);
    return rootGroup;
  }

  static three.Mesh? _createFaceMesh(CadFoldedPolygon3D poly, {required CadPoint3D pivot, bool isSelected = false, bool isHovered = false}) {
    final n = poly.normal;
    final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
    final nz = lenN > 1e-6 ? CadPoint3D(n.x / lenN, n.y / lenN, n.z / lenN) : const CadPoint3D(0, 0, 1);

    // Orthonormal tangent basis (u, v) on polygon plane
    final up = nz.z.abs() < 0.9 ? const CadPoint3D(0, 0, 1) : const CadPoint3D(1, 0, 0);

    final ux = up.y * nz.z - up.z * nz.y;
    final uy = up.z * nz.x - up.x * nz.z;
    final uz = up.x * nz.y - up.y * nz.x;
    final lenU = math.sqrt(ux * ux + uy * uy + uz * uz);
    if (lenU < 1e-6) return null;
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
      return (dx * u.x + dy * u.y + dz * u.z, dx * v.x + dy * v.y + dz * v.z);
    }

    // Outer contour
    final shape = three.Shape();
    final p0 = projectTo2D(poly.vertices[0]);
    shape.moveTo(p0.$1, p0.$2);
    for (int i = 1; i < poly.vertices.length; i++) {
      final pi = projectTo2D(poly.vertices[i]);
      shape.lineTo(pi.$1, pi.$2);
    }
    shape.closePath();

    // Inner cutout holes (slots, perforations, punch openings)
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

    three.BufferGeometry geometry;
    try {
      geometry = three_geo.ShapeGeometry([shape]);
    } catch (_) {
      return null;
    }

    // Material color: selection highlights or metallic sheet steel
    int colorHex = poly.color.toARGB32() & 0xFFFFFF;
    if (isSelected) {
      colorHex = 0x38BDF8; // Light blue selection
    } else if (isHovered) {
      colorHex = 0xBAE6FD; // Cyan hover
    }

    final material = three.MeshStandardMaterial.fromMap({
      'color': colorHex,
      'roughness': 0.40,
      'metalness': 0.60,
      'side': three.DoubleSide,
      'depthTest': true,
      'depthWrite': true,
    });

    final mesh = three.Mesh(geometry, material);
    mesh.name = poly.faceId;

    // Apply 3D coordinate system transformation:
    // Centered around meshResult.center
    final mat4 = three.Matrix4();
    mat4.makeBasis(three.Vector3(u.x, u.y, u.z), three.Vector3(v.x, v.y, v.z), three.Vector3(nz.x, nz.y, nz.z));
    mat4.setPosition(origin.x - pivot.x, origin.y - pivot.y, origin.z - pivot.z);
    mesh.applyMatrix4(mat4);

    return mesh;
  }
}
