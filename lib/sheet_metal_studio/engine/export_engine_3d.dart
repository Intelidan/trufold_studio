// =============================================================================
// export_engine_3d.dart
//
// 3D Mesh Exporters for truFold Studio by Danish.
// Exports folded sheet metal geometry to industry standard 3D formats:
// 1. Wavefront OBJ (.obj) with vertex normals and triangular/quad faces.
// 2. Stereolithography STL (.stl) in standard ASCII format for 3D printing & CAM.
// Supports both zero-thickness mid-surface mesh and extruded solid body thickness!
// Designed with ZERO external dependencies for 100% standalone portability.
// =============================================================================

import '../models/cad_primitives.dart';

typedef ExportEngine3D = ExportEngine3d;

class ExportEngine3d {
  /// Exports a list of 3D folded polygons to standard Wavefront OBJ format.
  /// If [thicknessMm] > 0, extrudes the faces into a watertight solid sheet metal body.
  static String exportWavefrontObj({required List<CadFoldedPolygon3D> polygons, double thicknessMm = 0.0, String partName = 'DanishSheetMetalPart'}) {
    final sb = StringBuffer();
    sb.writeln('# -----------------------------------------------------------------------------');
    sb.writeln('# Wavefront OBJ Exported from truFold Studio by Danish');
    sb.writeln('# Part: $partName');
    sb.writeln('# Polygons: ${polygons.length}');
    sb.writeln('# Solid Thickness: ${thicknessMm > 0 ? '${thicknessMm}mm' : 'Mid-surface'}');
    sb.writeln('# -----------------------------------------------------------------------------');
    sb.writeln('o $partName');
    sb.writeln();

    final allVertices = <CadPoint3D>[];
    final allNormals = <CadPoint3D>[];
    final faceTriangles = <List<int>>[]; // 1-indexed vertex indices

    for (final poly in polygons) {
      if (poly.vertices.length < 3) continue;

      if (thicknessMm <= 0.0) {
        // Single surface mesh
        final norm = poly.normal.normalized();
        final normalIdx = allNormals.length + 1;
        allNormals.add(norm);

        final startVIdx = allVertices.length + 1;
        for (final v in poly.vertices) {
          allVertices.add(v);
        }

        // Triangulate polygon (fan triangulation)
        for (int i = 1; i < poly.vertices.length - 1; i++) {
          faceTriangles.add([startVIdx, startVIdx + i, startVIdx + i + 1, normalIdx]);
        }
      } else {
        // Solid body extrusion: Top face, Bottom face, and Side walls
        final norm = poly.normal.normalized();
        final halfT = thicknessMm / 2.0;
        final nPts = poly.vertices.length;

        // Top surface (+halfT)
        final topNormIdx = allNormals.length + 1;
        allNormals.add(norm);
        final topStartIdx = allVertices.length + 1;
        for (final v in poly.vertices) {
          allVertices.add(v + (norm * halfT));
        }

        // Bottom surface (-halfT)
        final botNorm = norm * -1.0;
        final botNormIdx = allNormals.length + 1;
        allNormals.add(botNorm);
        final botStartIdx = allVertices.length + 1;
        for (final v in poly.vertices) {
          allVertices.add(v + (norm * -halfT));
        }

        // Top triangles (CCW)
        for (int i = 1; i < nPts - 1; i++) {
          faceTriangles.add([topStartIdx, topStartIdx + i, topStartIdx + i + 1, topNormIdx]);
        }

        // Bottom triangles (CW for outward normal)
        for (int i = 1; i < nPts - 1; i++) {
          faceTriangles.add([botStartIdx, botStartIdx + i + 1, botStartIdx + i, botNormIdx]);
        }

        // Side wall quads (split into 2 triangles each)
        for (int i = 0; i < nPts; i++) {
          final nextI = (i + 1) % nPts;
          final t1 = topStartIdx + i;
          final t2 = topStartIdx + nextI;
          final b1 = botStartIdx + i;
          final b2 = botStartIdx + nextI;

          // Compute side normal
          final edgeV = allVertices[t2 - 1] - allVertices[t1 - 1];
          final edgeDown = allVertices[b1 - 1] - allVertices[t1 - 1];
          final sideNorm = edgeV.cross(edgeDown).normalized();
          final sideNormIdx = allNormals.length + 1;
          allNormals.add(sideNorm);

          faceTriangles.add([t1, b1, t2, sideNormIdx]);
          faceTriangles.add([t2, b1, b2, sideNormIdx]);
        }
      }
    }

    // Write vertices
    for (final v in allVertices) {
      sb.writeln('v ${_f(v.x)} ${_f(v.y)} ${_f(v.z)}');
    }
    sb.writeln();

    // Write normals
    for (final vn in allNormals) {
      sb.writeln('vn ${_f(vn.x)} ${_f(vn.y)} ${_f(vn.z)}');
    }
    sb.writeln();

    // Write faces (f v1//vn v2//vn v3//vn)
    sb.writeln('s 1');
    for (final tri in faceTriangles) {
      final v1 = tri[0];
      final v2 = tri[1];
      final v3 = tri[2];
      final vn = tri[3];
      sb.writeln('f $v1//$vn $v2//$vn $v3//$vn');
    }

    return sb.toString();
  }

  /// Exports a list of 3D folded polygons to standard ASCII STL format.
  /// Widely compatible with slicers (Cura, PrusaSlicer), FreeCAD, Blender, and SolidWorks.
  static String exportAsciiStl({required List<CadFoldedPolygon3D> polygons, double thicknessMm = 0.0, String solidName = 'DanishSheetMetalPart'}) {
    final sb = StringBuffer();
    final cleanName = solidName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    sb.writeln('solid $cleanName');

    void writeFacet(CadPoint3D v1, CadPoint3D v2, CadPoint3D v3, CadPoint3D norm) {
      sb.writeln('  facet normal ${_f(norm.x)} ${_f(norm.y)} ${_f(norm.z)}');
      sb.writeln('    outer loop');
      sb.writeln('      vertex ${_f(v1.x)} ${_f(v1.y)} ${_f(v1.z)}');
      sb.writeln('      vertex ${_f(v2.x)} ${_f(v2.y)} ${_f(v2.z)}');
      sb.writeln('      vertex ${_f(v3.x)} ${_f(v3.y)} ${_f(v3.z)}');
      sb.writeln('    endloop');
      sb.writeln('  endfacet');
    }

    for (final poly in polygons) {
      if (poly.vertices.length < 3) continue;

      if (thicknessMm <= 0.0) {
        final norm = poly.normal.normalized();
        for (int i = 1; i < poly.vertices.length - 1; i++) {
          writeFacet(poly.vertices[0], poly.vertices[i], poly.vertices[i + 1], norm);
        }
      } else {
        final norm = poly.normal.normalized();
        final halfT = thicknessMm / 2.0;
        final nPts = poly.vertices.length;

        final topVertices = poly.vertices.map((v) => v + (norm * halfT)).toList();
        final botVertices = poly.vertices.map((v) => v + (norm * -halfT)).toList();
        final botNorm = norm * -1.0;

        // Top surface
        for (int i = 1; i < nPts - 1; i++) {
          writeFacet(topVertices[0], topVertices[i], topVertices[i + 1], norm);
        }

        // Bottom surface (reversed winding)
        for (int i = 1; i < nPts - 1; i++) {
          writeFacet(botVertices[0], botVertices[i + 1], botVertices[i], botNorm);
        }

        // Side walls
        for (int i = 0; i < nPts; i++) {
          final nextI = (i + 1) % nPts;
          final t1 = topVertices[i];
          final t2 = topVertices[nextI];
          final b1 = botVertices[i];
          final b2 = botVertices[nextI];

          final edgeV = t2 - t1;
          final edgeDown = b1 - t1;
          final sideNorm = edgeV.cross(edgeDown).normalized();

          writeFacet(t1, b1, t2, sideNorm);
          writeFacet(t2, b1, b2, sideNorm);
        }
      }
    }

    sb.writeln('endsolid $cleanName');
    return sb.toString();
  }

  static String _f(double val) {
    if (val.abs() < 1e-6) return '0.000';
    return val.toStringAsFixed(3);
  }
}
