// =============================================================================
// layer1_flutter3d_adapter.dart
//
// Layer 1 Dedicated 3D Engine: `flutter3d` Retained GPU B-Rep Renderer
//
// Architectural Highlights:
// 1. Fully Self-Contained 3D GPU Pipeline: ZERO dependencies on three_js.
// 2. Exact Newell 3D Ray-Plane Occlusion Testing: Solves flange and coupler-hole
//    see-through artifacts by casting exact 3D camera rays through 2D screen
//    intersections, ensuring foreground plates physically occlude background flanges.
// 3. Strict 3D + 2D Back-Face Culling: Combines 3D view-space normal testing
//    (`viewDot <= 1e-4`) with 2D screen winding (`cross2D <= 0.01`).
// 4. Host-Mapped Bore-First Ordering: Hole bores (`BORE_*`) draw immediately
//    before their host face so the solid `PathFillType.evenOdd` fill frames the hole.
// 5. Distinct Flutter3D PBR/Cel-Toon Shading: 3-Band stepped diffuse tones,
//    stepped Cook-Torrance GGX microfacet specular, and Schlick Fresnel grazing rim.
// =============================================================================

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../models/cad_primitives.dart';
import 'cad_brep_flutter_gpu_scene.dart';
import 'cad_polygon_triangulator.dart';

/// Compiled GPU + B-Rep facet for flutter3d hierarchical assembly rendering.
class Flutter3dCompiledFacet {
  final CompiledBRepFacet brepFacet;
  final int vertexOffset;
  final int vertexCount;
  final int indexOffset;
  final int indexCount;
  final int creaseOffset;
  final int creaseCount;
  final int topologicalSubLayer;
  final Float32List positions3D;
  final Float32List normals3D;
  final Int32List baseColors;
  final Uint16List triangleIndices;

  const Flutter3dCompiledFacet({
    required this.brepFacet,
    required this.vertexOffset,
    required this.vertexCount,
    required this.indexOffset,
    required this.indexCount,
    required this.creaseOffset,
    required this.creaseCount,
    required this.topologicalSubLayer,
    required this.positions3D,
    required this.normals3D,
    required this.baseColors,
    required this.triangleIndices,
  });
}

/// Logical grouping of facets belonging to a single CAD part in flutter3d.
class Flutter3dPartGroup {
  final String partId;
  final List<Flutter3dCompiledFacet> facets;
  final CadPoint3D centroid;
  final double minX, maxX;
  final double minY, maxY;
  final double minZ, maxZ;
  final bool isSideRail;
  final bool isCrossRung;
  final bool isWeldBead;

  const Flutter3dPartGroup({
    required this.partId,
    required this.facets,
    required this.centroid,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.minZ,
    required this.maxZ,
    required this.isSideRail,
    required this.isCrossRung,
    required this.isWeldBead,
  });
}

/// Retained GPU vertex & index buffers compiled directly from CAD B-Rep geometry.
class Flutter3dRetainedBufferGeometry {
  final Float32List positions3D;
  final Float32List normals3D;
  final Int32List baseColors;
  final Uint16List triangleIndices;
  final Uint8List triangleFlags;
  final Float32List lineSegmentPositions3D;
  final Float32List lineSegmentNormals3D;
  final List<Flutter3dCompiledFacet> compiledFacets;
  final List<Flutter3dPartGroup> partGroups;

  const Flutter3dRetainedBufferGeometry({
    required this.positions3D,
    required this.normals3D,
    required this.baseColors,
    required this.triangleIndices,
    required this.triangleFlags,
    required this.lineSegmentPositions3D,
    required this.lineSegmentNormals3D,
    required this.compiledFacets,
    required this.partGroups,
  });
}

/// Backward compatibility typedef for existing buffers
typedef ThreeJsRetainedBufferGeometry = Flutter3dRetainedBufferGeometry;

/// Projected front-facing facet ready for flutter3d hierarchical part & facet rendering.
class Flutter3dProjectedFacet {
  final Flutter3dCompiledFacet compiledFacet;
  final CompiledBRepFacet facet;
  final Float32List screenPositions;
  final Uint16List culledIndices;
  final int visibleTriCount;
  final Path fillPath;
  final Path? strokePath;
  final Path? holesStrokePath;
  final double viewDot;
  final double avgCamZ;
  final double minCamZ;
  final double maxCamZ;
  final double camSideNx;
  final double camSideNy;
  final double camSideNz;
  final double camSidePlaneD;
  final double minScrX;
  final double maxScrX;
  final double minScrY;
  final double maxScrY;
  final List<Offset> outerScreenPts;
  final double pCamX;
  final double pCamY;
  final double pCamZ;
  final double nCamX;
  final double nCamY;
  final double nCamZ;

  const Flutter3dProjectedFacet({
    required this.compiledFacet,
    required this.facet,
    required this.screenPositions,
    required this.culledIndices,
    required this.visibleTriCount,
    required this.fillPath,
    required this.strokePath,
    required this.holesStrokePath,
    required this.viewDot,
    required this.avgCamZ,
    required this.minCamZ,
    required this.maxCamZ,
    required this.camSideNx,
    required this.camSideNy,
    required this.camSideNz,
    required this.camSidePlaneD,
    required this.minScrX,
    required this.maxScrX,
    required this.minScrY,
    required this.maxScrY,
    required this.outerScreenPts,
    required this.pCamX,
    required this.pCamY,
    required this.pCamZ,
    required this.nCamX,
    required this.nCamY,
    required this.nCamZ,
  });
}

/// Backward compatibility typedef
typedef PathBProjectedFacet = Flutter3dProjectedFacet;

/// Dedicated 3D Engine: `flutter3d` Retained GPU B-Rep Renderer.
class Layer1Flutter3dAdapter {
  static double _srgbToLinear(double s) {
    final c = s.clamp(0.0, 1.0);
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static int _linearToSrgbByte(double c) {
    final clamped = c.clamp(0.0, 1.0);
    final s = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * math.pow(clamped, 1.0 / 2.4).toDouble() - 0.055;
    return (s.clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
  }

  static double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  static int _classifyTopologicalSubLayer(CompiledBRepFacet facet) {
    final fid = facet.faceId;
    if (facet.isWeld || fid.startsWith('WELD_') || fid.startsWith('weld_')) {
      return 3; // Weld beads sit on top of structural joints
    }
    if (fid.startsWith('BORE_') || fid.contains('_BORE_') || fid.contains('_bore_')) {
      return 0; // Internal hole bores draw first inside the part
    }
    if (fid.startsWith('RIM_') || fid.contains('_rim_') || fid.contains('_end_cap_') || fid.startsWith('CHAMFER_')) {
      return 1; // Thin sheet-metal rims / end caps
    }
    return 2; // Primary structural webs, flanges, and planar walls
  }

  /// Compiles `model.rawFacets` into compact GPU vertex & index buffers for flutter3d.
  static Flutter3dRetainedBufferGeometry compileBufferGeometry(CadBRepModelData model) {
    final allPosList = <double>[];
    final allNormList = <double>[];
    final allColorList = <int>[];
    final allIndexList = <int>[];
    final allTriFlagsList = <int>[];
    final allLinePosList = <double>[];
    final allLineNormList = <double>[];

    final compiledFacets = <Flutter3dCompiledFacet>[];
    final facetsByPart = <String, List<Flutter3dCompiledFacet>>{};

    const double creaseNormalBiasMm = 0.08;
    final double aoStrength = (model.preferences.ambientOcclusion / 100.0).clamp(0.0, 1.0);

    for (final facet in model.rawFacets) {
      final builder = GeometryBuilder(deduplicate: false);
      final baseSrgb = facet.baseSrgbColor;
      final n = facet.normal;
      final normVec = vm.Vector3(n.x, n.y, n.z);

      final fid = facet.faceId;
      double featureAo = 1.0;
      if (fid.startsWith('BORE_') || fid.contains('_bore_')) {
        featureAo = 1.0 - (0.35 * aoStrength);
      } else if (fid.contains('_inner_web')) {
        featureAo = 1.0 - (0.24 * aoStrength);
      } else if (fid.contains('_inner_flange')) {
        featureAo = 1.0 - (0.18 * aoStrength);
      } else if (fid.startsWith('RIM_') || fid.contains('_rim_') || fid.contains('_end_cap_')) {
        featureAo = 1.0 - (0.14 * aoStrength);
      }

      final baseLinear = vm.Vector4(
        _srgbToLinear((baseSrgb.r * featureAo).clamp(0.0, 1.0)),
        _srgbToLinear((baseSrgb.g * featureAo).clamp(0.0, 1.0)),
        _srgbToLinear((baseSrgb.b * featureAo).clamp(0.0, 1.0)),
        facet.isTranslucent ? 0.38 : 1.0,
      );

      builder.color(baseLinear);
      builder.normal(normVec);

      CadPolygonTriangulator.triangulateToBuilder(
        outerVertices: facet.vertices,
        holes: facet.holes,
        normal: facet.normal,
        pivot: const CadPoint3D(0, 0, 0),
        baseLinearColor: baseLinear,
        builder: builder,
        creviceAoStrength: (model.preferences.ambientOcclusion / 100.0).clamp(0.0, 1.0),
      );

      if (builder.vertexCount == 0 || builder.triangleCount == 0) continue;
      final triGeom = builder.build();

      final fPos = Float32List.fromList(triGeom.positions);
      final fNorm = Float32List.fromList(triGeom.normals);
      final fIndices = Uint16List.fromList(triGeom.indices);

      final int vCount = fPos.length ~/ 3;
      final fColors = Int32List(vCount);
      final rawLinearColors = triGeom.colors;
      for (int v = 0; v < vCount; v++) {
        final int c4 = v * 4;
        if (c4 + 3 < rawLinearColors.length) {
          final int rByte = _linearToSrgbByte(rawLinearColors[c4]);
          final int gByte = _linearToSrgbByte(rawLinearColors[c4 + 1]);
          final int bByte = _linearToSrgbByte(rawLinearColors[c4 + 2]);
          final int aByte = (rawLinearColors[c4 + 3].clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
          fColors[v] = (aByte << 24) | (rByte << 16) | (gByte << 8) | bByte;
        } else {
          final int rByte = (baseSrgb.r * 255.0).round().clamp(0, 255);
          final int gByte = (baseSrgb.g * 255.0).round().clamp(0, 255);
          final int bByte = (baseSrgb.b * 255.0).round().clamp(0, 255);
          fColors[v] = (0xFF << 24) | (rByte << 16) | (gByte << 8) | bByte;
        }
      }

      final fCreaseList = <double>[];
      for (final seg in facet.boundarySegments) {
        final a = seg.$1;
        final b = seg.$2;
        fCreaseList.addAll([
          a.x + n.x * creaseNormalBiasMm,
          a.y + n.y * creaseNormalBiasMm,
          a.z + n.z * creaseNormalBiasMm,
          b.x + n.x * creaseNormalBiasMm,
          b.y + n.y * creaseNormalBiasMm,
          b.z + n.z * creaseNormalBiasMm,
        ]);
      }
      for (final hLoop in facet.holes) {
        for (int i = 0; i < hLoop.length; i++) {
          final a = hLoop[i];
          final b = hLoop[(i + 1) % hLoop.length];
          fCreaseList.addAll([
            a.x + n.x * creaseNormalBiasMm,
            a.y + n.y * creaseNormalBiasMm,
            a.z + n.z * creaseNormalBiasMm,
            b.x + n.x * creaseNormalBiasMm,
            b.y + n.y * creaseNormalBiasMm,
            b.z + n.z * creaseNormalBiasMm,
          ]);
        }
      }

      final vOffset = allPosList.length ~/ 3;
      final iOffset = allIndexList.length;
      final cOffset = allLinePosList.length ~/ 3;

      allPosList.addAll(fPos);
      allNormList.addAll(fNorm);
      allColorList.addAll(fColors);

      for (int i = 0; i < fIndices.length; i++) {
        allIndexList.add(vOffset + fIndices[i]);
      }

      final int subLayer = _classifyTopologicalSubLayer(facet);
      for (int t = 0; t < fIndices.length ~/ 3; t++) {
        allTriFlagsList.add(subLayer);
      }

      allLinePosList.addAll(fCreaseList);
      for (int c = 0; c < fCreaseList.length ~/ 3; c++) {
        allLineNormList.addAll([n.x, n.y, n.z]);
      }

      final cf = Flutter3dCompiledFacet(
        brepFacet: facet,
        vertexOffset: vOffset,
        vertexCount: vCount,
        indexOffset: iOffset,
        indexCount: fIndices.length,
        creaseOffset: cOffset,
        creaseCount: fCreaseList.length ~/ 3,
        topologicalSubLayer: subLayer,
        positions3D: fPos,
        normals3D: fNorm,
        baseColors: fColors,
        triangleIndices: fIndices,
      );

      compiledFacets.add(cf);
      facetsByPart.putIfAbsent(facet.partId, () => <Flutter3dCompiledFacet>[]).add(cf);
    }

    final partGroups = <Flutter3dPartGroup>[];
    facetsByPart.forEach((partId, groupFacets) {
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      double minZ = double.infinity, maxZ = -double.infinity;
      double sx = 0.0, sy = 0.0, sz = 0.0;
      double totalWeight = 0.0;

      for (final gf in groupFacets) {
        final bf = gf.brepFacet;
        if (bf.minX < minX) minX = bf.minX;
        if (bf.maxX > maxX) maxX = bf.maxX;
        if (bf.minY < minY) minY = bf.minY;
        if (bf.maxY > maxY) maxY = bf.maxY;
        if (bf.minZ < minZ) minZ = bf.minZ;
        if (bf.maxZ > maxZ) maxZ = bf.maxZ;
        final double w = gf.topologicalSubLayer == 2 ? 10.0 : 1.0;
        sx += bf.centroid.x * w;
        sy += bf.centroid.y * w;
        sz += bf.centroid.z * w;
        totalWeight += w;
      }

      final invW = totalWeight > 0 ? 1.0 / totalWeight : 1.0;
      final lowerId = partId.toLowerCase();
      final isSideRail = lowerId.startsWith('rail_') || lowerId.contains('rail') || lowerId.startsWith('stile_');
      final isWeldBead = lowerId.startsWith('weld_');
      final isCrossRung = !isSideRail && !isWeldBead && (lowerId.startsWith('rung_') || lowerId.contains('rung') || lowerId.contains('cross'));

      partGroups.add(
        Flutter3dPartGroup(
          partId: partId,
          facets: groupFacets,
          centroid: CadPoint3D(sx * invW, sy * invW, sz * invW),
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          minZ: minZ,
          maxZ: maxZ,
          isSideRail: isSideRail,
          isCrossRung: isCrossRung,
          isWeldBead: isWeldBead,
        ),
      );
    });

    return Flutter3dRetainedBufferGeometry(
      positions3D: Float32List.fromList(allPosList),
      normals3D: Float32List.fromList(allNormList),
      baseColors: Int32List.fromList(allColorList),
      triangleIndices: Uint16List.fromList(allIndexList),
      triangleFlags: Uint8List.fromList(allTriFlagsList),
      lineSegmentPositions3D: Float32List.fromList(allLinePosList),
      lineSegmentNormals3D: Float32List.fromList(allLineNormList),
      compiledFacets: compiledFacets,
      partGroups: partGroups,
    );
  }

  /// Projects a single `Flutter3dCompiledFacet` with strict 3D and 2D backface culling.
  static Flutter3dProjectedFacet? projectAndCullFacet({
    required Flutter3dCompiledFacet cf,
    required Scene scene,
    required Size size,
    required double eyeX,
    required double eyeY,
    required double eyeZ,
    required bool isOrtho,
    required bool isGlobalTranslucent,
  }) {
    final facet = cf.brepFacet;
    final m = scene.rotationMatrix;
    final bool effectiveTranslucent = isGlobalTranslucent || facet.isTranslucent;

    // 1. 3D View-Space / Perspective Ray Normal Check
    final vnz = facet.normal.x * m[8] + facet.normal.y * m[9] + facet.normal.z * m[10];

    double viewDot;
    if (isOrtho) {
      viewDot = vnz;
    } else {
      final vx = eyeX - facet.centroid.x;
      final vy = eyeY - facet.centroid.y;
      final vz = eyeZ - facet.centroid.z;
      final vLen = math.sqrt(vx * vx + vy * vy + vz * vz);
      viewDot = vLen > 1e-6 ? (facet.normal.x * vx + facet.normal.y * vy + facet.normal.z * vz) / vLen : vnz;
    }

    if (!effectiveTranslucent && facet.cullBackface && viewDot <= 1e-4) {
      return null;
    }

    // 2. Project compact facet vertices to 2D screen space
    final pos3D = cf.positions3D;
    final int vertCount = pos3D.length ~/ 3;
    final screenPts = Float32List(vertCount * 2);
    double minScrX = double.infinity, maxScrX = -double.infinity;
    double minScrY = double.infinity, maxScrY = -double.infinity;

    for (int v = 0; v < vertCount; v++) {
      final int i3 = v * 3;
      final int i2 = v * 2;
      final scr = scene.projectRelativePointToScreen(
        CadPoint3D(pos3D[i3], pos3D[i3 + 1], pos3D[i3 + 2]),
        size,
      );
      if (scr == null) return null;
      screenPts[i2] = scr.dx;
      screenPts[i2 + 1] = scr.dy;
      if (scr.dx < minScrX) minScrX = scr.dx;
      if (scr.dx > maxScrX) maxScrX = scr.dx;
      if (scr.dy < minScrY) minScrY = scr.dy;
      if (scr.dy > maxScrY) maxScrY = scr.dy;
    }

    // 3. Strict 2D Screen-Space Winding Check (`cross2D <= 0.01`)
    final indices = cf.triangleIndices;
    final int triCount = indices.length ~/ 3;
    final culledIdxList = Uint16List(indices.length);
    int outIdx = 0;

    for (int t = 0; t < triCount; t++) {
      final int ti = t * 3;
      final int i0 = indices[ti];
      final int i1 = indices[ti + 1];
      final int i2 = indices[ti + 2];

      final double x0 = screenPts[i0 * 2], y0 = screenPts[i0 * 2 + 1];
      final double x1 = screenPts[i1 * 2], y1 = screenPts[i1 * 2 + 1];
      final double x2 = screenPts[i2 * 2], y2 = screenPts[i2 * 2 + 1];

      final double cross2D = (x1 - x0) * (y0 - y2) - (y0 - y1) * (x2 - x0);
      if (!effectiveTranslucent && facet.cullBackface) {
        if (cross2D <= 0.01) continue;
      } else {
        if (cross2D.abs() <= 0.01) continue;
      }

      culledIdxList[outIdx++] = i0;
      culledIdxList[outIdx++] = i1;
      culledIdxList[outIdx++] = i2;
    }

    if (outIdx == 0) {
      if (facet.cullBackface || facet.boundarySegments.isEmpty) {
        return null;
      }
    }

    // 4. Build analytic B-Rep outer + hole Path
    final outerPath = Path();
    final outerPts = <Offset>[];
    double sumZ = 0.0;
    double minZ = double.infinity;
    double maxZ = -double.infinity;

    for (int i = 0; i < facet.vertices.length; i++) {
      final v = facet.vertices[i];
      final cz = v.x * m[8] + v.y * m[9] + v.z * m[10];
      sumZ += cz;
      if (cz < minZ) minZ = cz;
      if (cz > maxZ) maxZ = cz;

      final pt = scene.projectRelativePointToScreen(v, size);
      if (pt == null) return null;
      outerPts.add(pt);
      if (i == 0) {
        outerPath.moveTo(pt.dx, pt.dy);
      } else {
        outerPath.lineTo(pt.dx, pt.dy);
      }
    }
    outerPath.close();

    final fillPath = Path()..fillType = PathFillType.evenOdd;
    fillPath.addPath(outerPath, Offset.zero);

    Path? holesStrokePath;
    if (facet.holes.isNotEmpty) {
      holesStrokePath = Path();
      for (final hLoop in facet.holes) {
        if (hLoop.length < 3) continue;
        final hPath = Path();
        bool hStarted = false;
        for (int i = 0; i < hLoop.length; i++) {
          final hv = hLoop[i];
          final hpt = scene.projectRelativePointToScreen(hv, size);
          if (hpt == null) continue;
          if (!hStarted) {
            hPath.moveTo(hpt.dx, hpt.dy);
            hStarted = true;
          } else {
            hPath.lineTo(hpt.dx, hpt.dy);
          }
        }
        if (hStarted) {
          hPath.close();
          fillPath.addPath(hPath, Offset.zero);
          holesStrokePath.addPath(hPath, Offset.zero);
        }
      }
    }

    Path? strokePath;
    if (facet.boundarySegments.isNotEmpty) {
      strokePath = Path();
      for (final seg in facet.boundarySegments) {
        final p0 = scene.projectRelativePointToScreen(seg.$1, size);
        final p1 = scene.projectRelativePointToScreen(seg.$2, size);
        if (p0 != null && p1 != null) {
          strokePath.moveTo(p0.dx, p0.dy);
          strokePath.lineTo(p1.dx, p1.dy);
        }
      }
    }

    final orientSign = viewDot >= 0.0 ? 1.0 : -1.0;
    final fn = facet.normal;
    final cnx = fn.x * orientSign;
    final cny = fn.y * orientSign;
    final cnz = fn.z * orientSign;
    final refV = facet.vertices[0];
    final cPlaneD = cnx * refV.x + cny * refV.y + cnz * refV.z;

    final vnxCam = (fn.x * m[0] + fn.y * m[1] + fn.z * m[2]) * orientSign;
    final vnyCam = (fn.x * m[4] + fn.y * m[5] + fn.z * m[6]) * orientSign;
    final vnzCam = (fn.x * m[8] + fn.y * m[9] + fn.z * m[10]) * orientSign;

    final pCamX = refV.x * m[0] + refV.y * m[1] + refV.z * m[2];
    final pCamY = refV.x * m[4] + refV.y * m[5] + refV.z * m[6];
    final pCamZ = refV.x * m[8] + refV.y * m[9] + refV.z * m[10];

    return Flutter3dProjectedFacet(
      compiledFacet: cf,
      facet: facet,
      screenPositions: screenPts,
      culledIndices: Uint16List.sublistView(culledIdxList, 0, outIdx),
      visibleTriCount: outIdx ~/ 3,
      fillPath: fillPath,
      strokePath: strokePath,
      holesStrokePath: holesStrokePath,
      viewDot: viewDot,
      avgCamZ: sumZ / facet.vertices.length,
      minCamZ: minZ,
      maxCamZ: maxZ,
      camSideNx: cnx,
      camSideNy: cny,
      camSideNz: cnz,
      camSidePlaneD: cPlaneD,
      minScrX: minScrX,
      maxScrX: maxScrX,
      minScrY: minScrY,
      maxScrY: maxScrY,
      outerScreenPts: outerPts,
      pCamX: pCamX,
      pCamY: pCamY,
      pCamZ: pCamZ,
      nCamX: vnxCam,
      nCamY: vnyCam,
      nCamZ: vnzCam,
    );
  }

  static bool _pointInPolygon2D(Offset pt, List<Offset> poly) {
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final pi = poly[i];
      final pj = poly[j];
      if (((pi.dy > pt.dy) != (pj.dy > pt.dy)) && (pt.dx < (pj.dx - pi.dx) * (pt.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  static Offset? _segmentIntersection2D(Offset p1, Offset p2, Offset p3, Offset p4) {
    final s1x = p2.dx - p1.dx;
    final s1y = p2.dy - p1.dy;
    final s2x = p4.dx - p3.dx;
    final s2y = p4.dy - p3.dy;
    final denom = -s2x * s1y + s1x * s2y;
    if (denom.abs() < 1e-5) return null;
    final s = (-s1y * (p1.dx - p3.dx) + s1x * (p1.dy - p3.dy)) / denom;
    final t = (s2x * (p1.dy - p3.dy) - s2y * (p1.dx - p3.dx)) / denom;
    if (s > 0.005 && s < 0.995 && t > 0.005 && t < 0.995) {
      return Offset(p1.dx + t * s1x, p1.dy + t * s1y);
    }
    return null;
  }

  static bool _isStrictlyInsidePolygon2D(Offset pt, List<Offset> poly) {
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final abx = b.dx - a.dx;
      final aby = b.dy - a.dy;
      final lenSq = abx * abx + aby * aby;
      if (lenSq > 1e-6) {
        final t = (((pt.dx - a.dx) * abx + (pt.dy - a.dy) * aby) / lenSq).clamp(0.0, 1.0);
        final dx = a.dx + abx * t - pt.dx;
        final dy = a.dy + aby * t - pt.dy;
        if (dx * dx + dy * dy < 0.04) return false;
      }
    }
    return _pointInPolygon2D(pt, poly);
  }

  static Offset? _find2DPolygonOverlapPoint(List<Offset> polyA, List<Offset> polyB) {
    if (polyA.length < 3 || polyB.length < 3) return null;

    double cxA = 0.0, cyA = 0.0;
    for (final p in polyA) {
      cxA += p.dx;
      cyA += p.dy;
    }
    final centroidA = Offset(cxA / polyA.length, cyA / polyA.length);
    if (_isStrictlyInsidePolygon2D(centroidA, polyB)) return centroidA;

    double cxB = 0.0, cyB = 0.0;
    for (final p in polyB) {
      cxB += p.dx;
      cyB += p.dy;
    }
    final centroidB = Offset(cxB / polyB.length, cyB / polyB.length);
    if (_isStrictlyInsidePolygon2D(centroidB, polyA)) return centroidB;

    final pts = <Offset>[];
    for (final a in polyA) {
      final insetA = Offset(a.dx + (centroidA.dx - a.dx) * 0.02, a.dy + (centroidA.dy - a.dy) * 0.02);
      if (_isStrictlyInsidePolygon2D(insetA, polyB)) pts.add(insetA);
    }
    for (final b in polyB) {
      final insetB = Offset(b.dx + (centroidB.dx - b.dx) * 0.02, b.dy + (centroidB.dy - b.dy) * 0.02);
      if (_isStrictlyInsidePolygon2D(insetB, polyA)) pts.add(insetB);
    }
    for (int i = 0; i < polyA.length; i++) {
      final a0 = polyA[i];
      final a1 = polyA[(i + 1) % polyA.length];
      for (int j = 0; j < polyB.length; j++) {
        final b0 = polyB[j];
        final b1 = polyB[(j + 1) % polyB.length];
        final inter = _segmentIntersection2D(a0, a1, b0, b1);
        if (inter != null) pts.add(inter);
      }
    }

    if (pts.isEmpty) return null;
    double sx = 0.0, sy = 0.0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  static double? _evalRayPlaneCamZ({
    required Flutter3dProjectedFacet pf,
    required Offset screenPt,
    required double cx,
    required double cy,
    required double scale,
    required double cameraDist,
    required bool isOrtho,
  }) {
    final ux = (screenPt.dx - cx) / scale;
    final uy = -(screenPt.dy - cy) / scale;

    if (isOrtho) {
      if (pf.nCamZ.abs() < 1e-4) return pf.avgCamZ;
      return pf.pCamZ - (pf.nCamX * (ux - pf.pCamX) + pf.nCamY * (uy - pf.pCamY)) / pf.nCamZ;
    } else {
      final denom = pf.nCamX * ux + pf.nCamY * uy - pf.nCamZ * cameraDist;
      if (denom.abs() < 1e-5) return pf.avgCamZ;
      final numer = pf.nCamX * pf.pCamX + pf.nCamY * pf.pCamY + pf.nCamZ * (pf.pCamZ - cameraDist);
      final t = numer / denom;
      if (t <= 0.01) return null;
      return cameraDist * (1.0 - t);
    }
  }

  static bool _doesFacetPObscureQ(
    Flutter3dProjectedFacet p,
    Flutter3dProjectedFacet q, {
    required double cx,
    required double cy,
    required double scale,
    required double cameraDist,
    required bool isOrtho,
  }) {
    final dotNormals = (p.facet.normal.x * q.facet.normal.x +
            p.facet.normal.y * q.facet.normal.y +
            p.facet.normal.z * q.facet.normal.z)
        .abs();
    if (dotNormals > 0.999) {
      final planeDiff = (p.camSideNx * (q.facet.centroid.x - p.facet.centroid.x) +
              p.camSideNy * (q.facet.centroid.y - p.facet.centroid.y) +
              p.camSideNz * (q.facet.centroid.z - p.facet.centroid.z))
          .abs();
      if (planeDiff < 0.08) return false;
    }

    final overlapPt = _find2DPolygonOverlapPoint(p.outerScreenPts, q.outerScreenPts);
    if (overlapPt == null) {
      return false;
    }

    final zP = _evalRayPlaneCamZ(pf: p, screenPt: overlapPt, cx: cx, cy: cy, scale: scale, cameraDist: cameraDist, isOrtho: isOrtho);
    final zQ = _evalRayPlaneCamZ(pf: q, screenPt: overlapPt, cx: cx, cy: cy, scale: scale, cameraDist: cameraDist, isOrtho: isOrtho);

    if (zP != null && zQ != null && (zP - zQ).abs() > 0.12) {
      return zP > zQ;
    }

    const double eps = 0.20;
    double qMaxInP = -double.infinity;
    double qMinInP = double.infinity;
    for (final v in q.facet.vertices) {
      final d = p.camSideNx * (v.x - p.facet.centroid.x) +
          p.camSideNy * (v.y - p.facet.centroid.y) +
          p.camSideNz * (v.z - p.facet.centroid.z);
      if (d < qMinInP) qMinInP = d;
      if (d > qMaxInP) qMaxInP = d;
    }
    if (qMaxInP <= eps && qMinInP < -eps) return true;

    return p.avgCamZ > q.avgCamZ + 0.25;
  }

  /// Orders surviving front-facing facets within a single part using Newell 3D ray-plane depth sorting.
  static List<Flutter3dProjectedFacet> sortFacetsWithinPart(
    List<Flutter3dProjectedFacet> partFacets, {
    required double cx,
    required double cy,
    required double scale,
    required double cameraDist,
    required bool isOrtho,
  }) {
    if (partFacets.length <= 1) return partFacets;

    final boresByHost = <String, List<Flutter3dProjectedFacet>>{};
    final orphanBores = <Flutter3dProjectedFacet>[];
    final structural = <Flutter3dProjectedFacet>[];
    final welds = <Flutter3dProjectedFacet>[];

    for (final pf in partFacets) {
      final layer = pf.compiledFacet.topologicalSubLayer;
      final fid = pf.facet.faceId;
      if (layer == 0) {
        String? hostId;
        if (fid.startsWith('BORE_')) {
          final rest = fid.substring(5);
          final pIdx = rest.indexOf('_punch_');
          if (pIdx > 0) {
            hostId = rest.substring(0, pIdx);
          } else {
            final fIdx = rest.indexOf('_');
            if (fIdx > 0) hostId = rest.substring(0, fIdx);
          }
        }
        if (hostId != null) {
          boresByHost.putIfAbsent(hostId, () => <Flutter3dProjectedFacet>[]).add(pf);
        } else {
          orphanBores.add(pf);
        }
      } else if (layer == 3) {
        welds.add(pf);
      } else {
        structural.add(pf);
      }
    }

    // 1. Initial back-to-front depth sort
    structural.sort((a, b) => a.avgCamZ.compareTo(b.avgCamZ));
    welds.sort((a, b) => a.avgCamZ.compareTo(b.avgCamZ));
    orphanBores.sort((a, b) => a.avgCamZ.compareTo(b.avgCamZ));

    // 2. Newell Topological Ray-Plane Occlusion Pass
    final sCount = structural.length;
    if (sCount > 1) {
      final movedAtStep = <int>{};
      int i = 0;
      while (i < sCount - 1) {
        movedAtStep.clear();
        bool promotedAny = true;
        int guard = 0;

        while (promotedAny && guard < sCount) {
          promotedAny = false;
          guard++;
          final p = structural[i];

          for (int j = i + 1; j < sCount; j++) {
            final q = structural[j];

            if (p.maxCamZ < q.minCamZ - 0.2) continue;
            if (p.maxScrX < q.minScrX || p.minScrX > q.maxScrX || p.maxScrY < q.minScrY || p.minScrY > q.maxScrY) continue;
            if (movedAtStep.contains(identityHashCode(q))) continue;

            if (_doesFacetPObscureQ(p, q, cx: cx, cy: cy, scale: scale, cameraDist: cameraDist, isOrtho: isOrtho)) {
              structural.removeAt(j);
              structural.insert(i, q);
              movedAtStep.add(identityHashCode(q));
              promotedAny = true;
              break;
            }
          }
        }
        i++;
      }
    }

    final ordered = <Flutter3dProjectedFacet>[];
    ordered.addAll(orphanBores);

    final drawnHosts = <String>{};
    for (final sf in structural) {
      final hostId = sf.facet.faceId;
      if (!drawnHosts.contains(hostId) && boresByHost.containsKey(hostId)) {
        ordered.addAll(boresByHost[hostId]!);
        drawnHosts.add(hostId);
      }
      ordered.add(sf);
    }

    for (final entry in boresByHost.entries) {
      if (!drawnHosts.contains(entry.key)) {
        ordered.addAll(entry.value);
      }
    }

    ordered.addAll(welds);
    return ordered;
  }

  /// Builds the complete hierarchical assembly draw sequence for flutter3d.
  static List<Flutter3dProjectedFacet> buildHierarchicalAssemblyFacetQueue({
    required Flutter3dRetainedBufferGeometry buffers,
    required Scene scene,
    required Size size,
    required double eyeX,
    required double eyeY,
    required double eyeZ,
    required bool isOrtho,
    required bool isGlobalTranslucent,
  }) {
    final m = scene.rotationMatrix;

    final effectiveFitDim = scene.effectiveFitDim;
    final minScreen = math.min(size.width, size.height);
    final baseScale = (minScreen * 0.72) / effectiveFitDim;
    final scale = (baseScale * scene.zoom) > 1e-6 ? (baseScale * scene.zoom) : 1.0;
    final cameraDist = math.max(effectiveFitDim * 3.0, 1200.0);
    final cx = size.width * 0.5 + scene.pan.dx;
    final cy = size.height * 0.5 + scene.pan.dy;

    // Project & cull facets per part group
    final sideRails = <({Flutter3dPartGroup group, double camZ, List<Flutter3dProjectedFacet> facets})>[];
    final crossRungs = <({Flutter3dPartGroup group, double camZ, List<Flutter3dProjectedFacet> facets})>[];
    final weldParts = <({Flutter3dPartGroup group, double camZ, List<Flutter3dProjectedFacet> facets})>[];
    final otherParts = <({Flutter3dPartGroup group, double camZ, List<Flutter3dProjectedFacet> facets})>[];

    for (final group in buffers.partGroups) {
      final projected = <Flutter3dProjectedFacet>[];
      for (final cf in group.facets) {
        final pf = projectAndCullFacet(
          cf: cf,
          scene: scene,
          size: size,
          eyeX: eyeX,
          eyeY: eyeY,
          eyeZ: eyeZ,
          isOrtho: isOrtho,
          isGlobalTranslucent: isGlobalTranslucent,
        );
        if (pf != null) {
          projected.add(pf);
        }
      }
      if (projected.isEmpty) continue;

      final sortedPartFacets = sortFacetsWithinPart(
        projected,
        cx: cx,
        cy: cy,
        scale: scale,
        cameraDist: cameraDist,
        isOrtho: isOrtho,
      );
      final c = group.centroid;
      final double partCamZ = c.x * m[8] + c.y * m[9] + c.z * m[10];

      final entry = (group: group, camZ: partCamZ, facets: sortedPartFacets);
      if (group.isSideRail) {
        sideRails.add(entry);
      } else if (group.isCrossRung) {
        crossRungs.add(entry);
      } else if (group.isWeldBead) {
        weldParts.add(entry);
      } else {
        otherParts.add(entry);
      }
    }

    sideRails.sort((a, b) => a.camZ.compareTo(b.camZ));
    crossRungs.sort((a, b) => a.camZ.compareTo(b.camZ));
    weldParts.sort((a, b) => a.camZ.compareTo(b.camZ));
    otherParts.sort((a, b) => a.camZ.compareTo(b.camZ));

    final orderedQueue = <Flutter3dProjectedFacet>[];

    if (sideRails.length >= 2) {
      final rearRails = sideRails.sublist(0, sideRails.length - 1);
      final frontRail = sideRails.last;

      final rearRailIsRight = rearRails.any((r) => r.group.partId.contains('right'));
      final rearWelds = <({Flutter3dPartGroup group, double camZ, List<Flutter3dProjectedFacet> facets})>[];
      final frontWelds = <({Flutter3dPartGroup group, double camZ, List<Flutter3dProjectedFacet> facets})>[];

      for (final w in weldParts) {
        final wid = w.group.partId.toLowerCase();
        final isRightWeld = wid.contains('right');
        if ((rearRailIsRight && isRightWeld) || (!rearRailIsRight && !isRightWeld)) {
          rearWelds.add(w);
        } else {
          frontWelds.add(w);
        }
      }

      // PASS 1A: Rear Rail Base, Web & Far Flange
      final rearOverhangFlanges = <Flutter3dProjectedFacet>[];
      for (final rr in rearRails) {
        final bool camAboveRearRail = isOrtho ? (m[10] >= 0.0) : (eyeZ >= rr.group.centroid.z);
        for (final pf in rr.facets) {
          final fid = pf.facet.faceId;
          final bool isCameraSideFlange = camAboveRearRail
              ? (fid.contains('flange_top') || fid.contains('rim_top'))
              : (fid.contains('flange_bottom') || fid.contains('rim_bottom'));
          if (isCameraSideFlange) {
            rearOverhangFlanges.add(pf);
          } else {
            orderedQueue.add(pf);
          }
        }
      }

      // PASS 1B: Cross Rungs + Rear-Rail Inner Fillet Welds + Other Mid Parts
      for (final op in otherParts) {
        if (op.camZ <= frontRail.camZ) {
          orderedQueue.addAll(op.facets);
        }
      }
      for (final rung in crossRungs) {
        orderedQueue.addAll(rung.facets);
      }
      for (final rw in rearWelds) {
        orderedQueue.addAll(rw.facets);
      }

      // PASS 1C: Rear Rail Camera-Side Overhanging Flange + Front-Rail Welds
      orderedQueue.addAll(rearOverhangFlanges);
      for (final fw in frontWelds) {
        orderedQueue.addAll(fw.facets);
      }

      // PASS 2: Front Rail
      orderedQueue.addAll(frontRail.facets);

      for (final op in otherParts) {
        if (op.camZ > frontRail.camZ) {
          orderedQueue.addAll(op.facets);
        }
      }
    } else {
      final allParts = <({Flutter3dPartGroup group, double camZ, List<Flutter3dProjectedFacet> facets})>[
        ...sideRails,
        ...otherParts,
        ...crossRungs,
        ...weldParts,
      ]..sort((a, b) => a.camZ.compareTo(b.camZ));

      for (final p in allParts) {
        orderedQueue.addAll(p.facets);
      }

      // Inter-part Newell pass across multi-part assemblies
      if (allParts.length > 1 && orderedQueue.length > 1) {
        final oCount = orderedQueue.length;
        final movedAtStep = <int>{};
        int i = 0;
        while (i < oCount - 1) {
          movedAtStep.clear();
          bool promotedAny = true;
          int guard = 0;
          while (promotedAny && guard < oCount) {
            promotedAny = false;
            guard++;
            final p = orderedQueue[i];
            for (int j = i + 1; j < oCount; j++) {
              final q = orderedQueue[j];
              if (p.maxCamZ < q.minCamZ - 0.2) continue;
              if (p.maxScrX < q.minScrX || p.minScrX > q.maxScrX || p.maxScrY < q.minScrY || p.minScrY > q.maxScrY) continue;
              if (movedAtStep.contains(identityHashCode(q))) continue;
              if (_doesFacetPObscureQ(p, q, cx: cx, cy: cy, scale: scale, cameraDist: cameraDist, isOrtho: isOrtho)) {
                orderedQueue.removeAt(j);
                orderedQueue.insert(i, q);
                movedAtStep.add(identityHashCode(q));
                promotedAny = true;
                break;
              }
            }
          }
          i++;
        }
      }
    }

    return orderedQueue;
  }

  /// Renders the active `CadBRepModelData` using flutter3d's dedicated Cel/Toon PBR shader.
  static void renderFlutter3dPass({
    required Canvas canvas,
    required Size size,
    required Scene scene,
    required CadBRepModelData model,
    required Flutter3dRetainedBufferGeometry buffers,
  }) {
    if (buffers.compiledFacets.isEmpty) return;

    final m = scene.rotationMatrix;
    final prefs = model.preferences;
    final bool isGlobalTranslucent = model.renderMode == OnshapeRenderMode.translucent;
    final bool isWireframeOnly = model.renderMode == OnshapeRenderMode.unshaded;
    final bool shouldDrawWireframe =
        model.showWireframe && model.renderMode != OnshapeRenderMode.shadedWithoutEdges && prefs.lineWidth > 0.05;

    final double camDist = scene.effectiveFitDim * 3.8;
    final double eyeX = m[8] * camDist;
    final double eyeY = m[9] * camDist;
    final double eyeZ = m[10] * camDist;

    // 1. Build flutter3d Hierarchical Assembly Draw Queue with Newell 3D ray-plane occlusion
    final drawQueue = buildHierarchicalAssemblyFacetQueue(
      buffers: buffers,
      scene: scene,
      size: size,
      eyeX: eyeX,
      eyeY: eyeY,
      eyeZ: eyeZ,
      isOrtho: scene.isOrtho,
      isGlobalTranslucent: isGlobalTranslucent,
    );

    // 2. Flutter3D Cook-Torrance GGX + 3-Band Cel/Toon Uniforms
    final shininessRatio = (prefs.shininess / 100.0).clamp(0.0, 1.0);
    final double roughness = (0.52 - shininessRatio * 0.36).clamp(0.14, 0.65);
    final double alpha2 = math.pow(roughness, 4).toDouble();

    const double keyLx = -0.38, keyLy = 0.46, keyLz = 0.80;

    final triPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final faceFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final boundaryColor = prefs.highlightBoundaryEdges ? prefs.boundaryEdgeColor : const Color(0xFF1E1B4B);
    final creasePaint = Paint()
      ..color = isGlobalTranslucent ? boundaryColor.withValues(alpha: 0.60) : boundaryColor.withValues(alpha: 0.96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (prefs.lineWidth * 1.25).clamp(1.35, 2.8)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // 3. Render Pass: Solid Face Fill + GPU Vertex Cel/Toon/GGX Pass + Dedicated Crease Pass
    for (final pf in drawQueue) {
      final cf = pf.compiledFacet;
      final facet = pf.facet;

      if (!isWireframeOnly) {
        final pos3D = cf.positions3D;
        final norm3D = cf.normals3D;
        final baseColors = cf.baseColors;
        final int vertCount = pos3D.length ~/ 3;
        final shadedColors = Int32List(vertCount);

        double sumR = 0.0, sumG = 0.0, sumB = 0.0;
        final int targetAlpha = (isGlobalTranslucent || facet.isTranslucent) ? 110 : 255;

        for (int v = 0; v < vertCount; v++) {
          final int i3 = v * 3;
          final double px = pos3D[i3];
          final double py = pos3D[i3 + 1];
          final double pz = pos3D[i3 + 2];

          final double nx = norm3D[i3];
          final double ny = norm3D[i3 + 1];
          final double nz = norm3D[i3 + 2];

          double vnx = nx * m[0] + ny * m[1] + nz * m[2];
          double vny = nx * m[4] + ny * m[5] + nz * m[6];
          double vnz = nx * m[8] + ny * m[9] + nz * m[10];
          if (vnz < 0.0) {
            vnx = -vnx;
            vny = -vny;
            vnz = -vnz;
          }

          final double vCamX = px * m[0] + py * m[1] + pz * m[2];
          final double vCamY = px * m[4] + py * m[5] + pz * m[6];
          final double vCamZ = px * m[8] + py * m[9] + pz * m[10];
          final double dxCam = -vCamX * 0.0018;
          final double dyCam = -vCamY * 0.0018;
          final double dzCam = camDist - vCamZ * 0.0018;
          final double invVLen = 1.0 / math.sqrt(dxCam * dxCam + dyCam * dyCam + dzCam * dzCam);
          final double vx = dxCam * invVLen;
          final double vy = dyCam * invVLen;
          final double vz = dzCam * invVLen;

          final double hx = keyLx + vx;
          final double hy = keyLy + vy;
          final double hz = keyLz + vz;
          final double invHLen = 1.0 / math.sqrt(hx * hx + hy * hy + hz * hz);

          final double ndotl = (vnx * keyLx + vny * keyLy + vnz * keyLz).clamp(0.0, 1.0);
          final double wrapKey = ((vnx * keyLx + vny * keyLy + vnz * keyLz + 0.28) / 1.28).clamp(0.0, 1.0);
          final double ndoth = ((vnx * hx + vny * hy + vnz * hz) * invHLen).clamp(0.0, 1.0);
          final double ndotv = (vnx * vx + vny * vy + vnz * vz).clamp(0.001, 1.0);

          // 3-Band Stepped Cel/Toon Quantization (Shadow: 0.50 -> Midtone: 0.84 -> Key-Lit: 1.14)
          final double band1 = _smoothstep(0.28, 0.33, wrapKey);
          final double band2 = _smoothstep(0.66, 0.71, wrapKey);
          final double celTone = 0.50 + band1 * 0.34 + band2 * 0.30;

          // Stepped Cook-Torrance GGX Microfacet Specular Highlight Band
          final double denom = (ndoth * ndoth * (alpha2 - 1.0) + 1.0);
          final double dGgx = alpha2 / math.max(math.pi * denom * denom, 0.001);
          final double rawSpec = (dGgx * ndotl * 0.075).clamp(0.0, 0.50);
          final double steppedSpec = _smoothstep(0.14, 0.22, rawSpec) * 0.28;

          // Schlick Fresnel grazing rim sheen (Indigo/Cyan technical highlight)
          final double fresnelRim = math.pow(1.0 - ndotv, 3.0).toDouble() * 0.24;

          final int raw = baseColors[v];
          final int r0 = (raw >> 16) & 0xFF;
          final int g0 = (raw >> 8) & 0xFF;
          final int b0 = raw & 0xFF;

          final int rOut = (r0 * celTone * 0.96 + steppedSpec * 235.0 + fresnelRim * 115.0).round().clamp(0, 255);
          final int gOut = (g0 * celTone * 0.98 + steppedSpec * 242.0 + fresnelRim * 150.0).round().clamp(0, 255);
          final int bOut = (b0 * celTone * 1.05 + steppedSpec * 255.0 + fresnelRim * 255.0).round().clamp(0, 255);

          sumR += rOut;
          sumG += gOut;
          sumB += bOut;
          shadedColors[v] = (targetAlpha << 24) | (rOut << 16) | (gOut << 8) | bOut;
        }

        if (pf.culledIndices.isNotEmpty) {
          // Solid opaque base fill (`PathFillType.evenOdd`) ensures foreground plates physically block background flanges
          final double invVert = 1.0 / vertCount;
          faceFillPaint.color = Color.fromARGB(
            targetAlpha,
            (sumR * invVert).round().clamp(0, 255),
            (sumG * invVert).round().clamp(0, 255),
            (sumB * invVert).round().clamp(0, 255),
          );
          canvas.drawPath(pf.fillPath, faceFillPaint);

          // Hardware GPU vertex shading pass (`ui.Vertices.raw`)
          final gpuVertices = ui.Vertices.raw(
            ui.VertexMode.triangles,
            pf.screenPositions,
            colors: shadedColors,
            indices: pf.culledIndices,
          );
          canvas.drawVertices(gpuVertices, BlendMode.srcOver, triPaint);
        }
      } else {
        faceFillPaint.color = const Color(0xFFF8FAFC);
        canvas.drawPath(pf.fillPath, faceFillPaint);
      }

      // Dedicated Crease Pass Immediately Per Facet
      if (shouldDrawWireframe) {
        if (pf.strokePath != null) {
          canvas.drawPath(pf.strokePath!, creasePaint);
        }
        if (pf.holesStrokePath != null) {
          canvas.drawPath(pf.holesStrokePath!, creasePaint);
        }
      }
    }

    Scene.drawEngineHudWatermark(
      canvas,
      size,
      'Layer 1C: flutter3d (Path B Hierarchical B-Rep · GGX + 3-Band Cel/Toon)',
      const Color(0xFF6366F1),
    );
  }
}
