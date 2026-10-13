import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../sheet_metal_studio/models/cad_primitives.dart';
import '../../sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'assembly_part.dart';

/// Full document state for an assembly project in the Assembly Studio.
class AssemblyDocument {
  String id;
  String title;
  List<AssemblyPart> parts;
  List<AssemblyWeldJoint> welds;
  List<AssemblyMagneticJoint> magneticJoints;
  String? selectedPartId;
  String? selectedFaceId;
  Set<String> selectedPartIds;
  String? selectedWeldId;

  AssemblyDocument({
    required this.id,
    this.title = 'Untitled Cable Ladder Assembly',
    List<AssemblyPart>? parts,
    List<AssemblyWeldJoint>? welds,
    List<AssemblyMagneticJoint>? magneticJoints,
    this.selectedPartId,
    this.selectedFaceId,
    Set<String>? selectedPartIds,
    this.selectedWeldId,
  })  : parts = parts ?? [],
        welds = welds ?? [],
        magneticJoints = magneticJoints ?? [],
        selectedPartIds = selectedPartIds ?? (selectedPartId != null ? {selectedPartId} : {});

  AssemblyPart? get selectedPart {
    if (selectedPartId == null) return null;
    return parts.where((p) => p.id == selectedPartId).firstOrNull;
  }

  List<AssemblyPart> get selectedParts {
    if (selectedPartIds.isEmpty) {
      if (selectedPartId != null) {
        final p = parts.where((x) => x.id == selectedPartId).firstOrNull;
        return p != null ? [p] : [];
      }
      return [];
    }
    return parts.where((p) => selectedPartIds.contains(p.id)).toList();
  }

  AssemblyWeldJoint? get selectedWeld {
    if (selectedWeldId == null) return null;
    return welds.where((w) => w.id == selectedWeldId).firstOrNull;
  }

  /// Combined 3D mesh of all parts and visual weld indicators in the assembly.
  FoldedMeshResult buildAssemblyMesh({bool showWeldOverlay = true}) {
    final allPolygons = <CadFoldedPolygon3D>[];
    final allThicknessPolygons = <CadFoldedPolygon3D>[];

    for (final part in parts) {
      if (!part.isVisible) continue;
      final partMesh = part.build3DMesh();
      allPolygons.addAll(partMesh.polygons);
      allThicknessPolygons.addAll(partMesh.thicknessPolygons);
    }

    // Add visual 3D fillet weld bead geometry (seamless solid triangular prisms per SS2)
    for (int w = 0; w < welds.length; w++) {
      final j = welds[w];
      final isSelectedWeld = selectedWeldId == j.id;

      // Primary fillet bead (e.g. contact seam)
      _buildFilletBeadMesh(
        allPolygons: allPolygons,
        weldId: j.id,
        rootPt: j.weldPoint,
        axis: j.weldAxis,
        v1: j.legDir1 ?? const CadPoint3D(0.0, 0.0, 1.0),
        v2: j.legDir2 ?? const CadPoint3D(0.0, 1.0, 0.0),
        legSize: j.weldSizeMm,
        length: j.weldLengthMm,
        isSelected: isSelectedWeld,
        showWeldOverlay: showWeldOverlay,
        pathPoints: j.pathPoints,
      );

      // Opposing fillet bead if both-sides fillet weld with a valid second seam point
      if (j.bothSides && j.secondWeldPoint != null) {
        final secPt = j.secondWeldPoint!;
        final secV1 = j.secondLegDir1 ?? CadPoint3D(-(j.legDir1?.x ?? 0.0), -(j.legDir1?.y ?? 0.0), -(j.legDir1?.z ?? 1.0));
        final secV2 = j.secondLegDir2 ?? (j.legDir2 ?? const CadPoint3D(0.0, 1.0, 0.0));
        _buildFilletBeadMesh(
          allPolygons: allPolygons,
          weldId: j.id,
          rootPt: secPt,
          axis: j.weldAxis,
          v1: secV1,
          v2: secV2,
          legSize: j.weldSizeMm,
          length: j.weldLengthMm,
          isSelected: isSelectedWeld,
          showWeldOverlay: showWeldOverlay,
        );
      }
    }

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    for (final poly in allPolygons) {
      for (final v in poly.vertices) {
        if (v.x < minX) minX = v.x;
        if (v.x > maxX) maxX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.y > maxY) maxY = v.y;
        if (v.z < minZ) minZ = v.z;
        if (v.z > maxZ) maxZ = v.z;
      }
    }

    final double width = (maxX > minX) ? (maxX - minX) : 1000.0;
    final double length = (maxY > minY) ? (maxY - minY) : 1000.0;
    final double height = (maxZ > minZ) ? (maxZ - minZ) : 300.0;
    final CadPoint3D center = (maxX > minX && maxY > minY && maxZ > minZ)
        ? CadPoint3D((minX + maxX) / 2.0, (minY + maxY) / 2.0, (minZ + maxZ) / 2.0)
        : const CadPoint3D(0.0, 0.0, 0.0);

    return FoldedMeshResult(
      polygons: allPolygons,
      thicknessPolygons: allThicknessPolygons,
      boundWidth: math.max(width, 100.0),
      boundLength: math.max(length, 100.0),
      boundHeight: math.max(height, 50.0),
      center: center,
    );
  }

  AssemblyDocument clone() {
    return AssemblyDocument(
      id: id,
      title: title,
      parts: parts.map((p) => p.copyWith()).toList(),
      welds: welds.map((w) => AssemblyWeldJoint.fromJson(w.toJson())).toList(),
      magneticJoints: magneticJoints.map((m) => AssemblyMagneticJoint.fromJson(m.toJson())).toList(),
      selectedPartId: selectedPartId,
      selectedFaceId: selectedFaceId,
      selectedPartIds: Set<String>.from(selectedPartIds),
      selectedWeldId: selectedWeldId,
    );
  }

  /// Constructs a seamless, solid 3D fillet weld bead prism matching AutoCAD CAD standards (SS2).
  /// Strictly eliminates interior partition lines, prevents internal bleed-through,
  /// and supports selective distinguishable translucent overlay highlighting.
  static void _buildFilletBeadMesh({
    required List<CadFoldedPolygon3D> allPolygons,
    required String weldId,
    required CadPoint3D rootPt,
    required CadPoint3D axis,
    required CadPoint3D v1,
    required CadPoint3D v2,
    required double legSize,
    required double length,
    required bool isSelected,
    bool showWeldOverlay = true,
    List<CadPoint3D>? pathPoints,
  }) {
    final double a = math.max(2.5, legSize * 1.2);
    final double len = math.max(10.0, length);

    // 1. Normalize seam axis u
    CadPoint3D u = axis;
    final uLen = math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z);
    if (uLen > 1e-4) {
      u = CadPoint3D(u.x / uLen, u.y / uLen, u.z / uLen);
    } else {
      u = const CadPoint3D(1.0, 0.0, 0.0);
    }

    // 2. Ensure dir1 and dir2 are perpendicular to u and normalized
    CadPoint3D dir1 = v1;
    final dot1 = dir1.x * u.x + dir1.y * u.y + dir1.z * u.z;
    dir1 = CadPoint3D(dir1.x - dot1 * u.x, dir1.y - dot1 * u.y, dir1.z - dot1 * u.z);
    final len1 = math.sqrt(dir1.x * dir1.x + dir1.y * dir1.y + dir1.z * dir1.z);
    if (len1 > 1e-4) {
      dir1 = CadPoint3D(dir1.x / len1, dir1.y / len1, dir1.z / len1);
    } else {
      dir1 = (u.x.abs() < 0.9) ? const CadPoint3D(1.0, 0.0, 0.0) : const CadPoint3D(0.0, 0.0, 1.0);
      final d = dir1.x * u.x + dir1.y * u.y + dir1.z * u.z;
      dir1 = CadPoint3D(dir1.x - d * u.x, dir1.y - d * u.y, dir1.z - d * u.z);
      final l = math.sqrt(dir1.x * dir1.x + dir1.y * dir1.y + dir1.z * dir1.z);
      dir1 = CadPoint3D(dir1.x / l, dir1.y / l, dir1.z / l);
    }

    CadPoint3D dir2 = v2;
    final dot2 = dir2.x * u.x + dir2.y * u.y + dir2.z * u.z;
    dir2 = CadPoint3D(dir2.x - dot2 * u.x, dir2.y - dot2 * u.y, dir2.z - dot2 * u.z);
    final len2 = math.sqrt(dir2.x * dir2.x + dir2.y * dir2.y + dir2.z * dir2.z);
    if (len2 > 1e-4) {
      dir2 = CadPoint3D(dir2.x / len2, dir2.y / len2, dir2.z / len2);
    } else {
      dir2 = CadPoint3D(
        u.y * dir1.z - u.z * dir1.y,
        u.z * dir1.x - u.x * dir1.z,
        u.x * dir1.y - u.y * dir1.x,
      );
      final l2 = math.sqrt(dir2.x * dir2.x + dir2.y * dir2.y + dir2.z * dir2.z);
      if (l2 > 1e-4) dir2 = CadPoint3D(dir2.x / l2, dir2.y / l2, dir2.z / l2);
    }

    // Ensure crown points strictly away from solid faces and never underneath horizontal plates
    if (v1.z > 0.01 && dir2.z < -0.01) {
      dir2 = CadPoint3D(dir2.x, dir2.y, -dir2.z);
    }

    // Throat crown direction (bisector of dir1 and dir2)
    final sumX = dir1.x + dir2.x;
    final sumY = dir1.y + dir2.y;
    final sumZ = dir1.z + dir2.z;
    final sumLen = math.sqrt(sumX * sumX + sumY * sumY + sumZ * sumZ);
    CadPoint3D nCrown = (sumLen > 1e-4)
        ? CadPoint3D(sumX / sumLen, sumY / sumLen, sumZ / sumLen)
        : CadPoint3D(dir1.x, dir1.y, dir1.z);

    if ((v1.z >= 0.0 || v2.z >= 0.0) && nCrown.z < -0.01) {
      nCrown = CadPoint3D(nCrown.x, nCrown.y, -nCrown.z);
    }

    // Theoretical throat (t = 0.707 * a per AWS D1.1 / ISO 2553)
    final double throat = 0.7071 * a;

    // Pre-calculate profile points at each cross-section slice
    final rootPts = <CadPoint3D>[];
    final toe1Pts = <CadPoint3D>[];
    final toe2Pts = <CadPoint3D>[];
    final crownPts = <CadPoint3D>[];
    final int rippleCount;

    if (pathPoints != null && pathPoints.length >= 2) {
      final pts = pathPoints;
      rippleCount = math.max(8, pts.length * 2);
      for (int k = 0; k <= rippleCount; k++) {
        final double factor = (k / rippleCount) * (pts.length - 1);
        final int idx = factor.floor().clamp(0, pts.length - 2);
        final double frac = factor - idx;
        final p0 = pts[idx];
        final p1 = pts[idx + 1];
        final rPt = CadPoint3D(
          p0.x + (p1.x - p0.x) * frac,
          p0.y + (p1.y - p0.y) * frac,
          p0.z + (p1.z - p0.z) * frac,
        );
        final double swell = 1.30 + 0.25 * math.cos(k * math.pi * 2.0);
        rootPts.add(rPt);
        toe1Pts.add(CadPoint3D(rPt.x + dir1.x * a, rPt.y + dir1.y * a, rPt.z + dir1.z * a));
        toe2Pts.add(CadPoint3D(rPt.x + dir2.x * a, rPt.y + dir2.y * a, rPt.z + dir2.z * a));
        crownPts.add(CadPoint3D(
          rPt.x + nCrown.x * (throat * swell),
          rPt.y + nCrown.y * (throat * swell),
          rPt.z + nCrown.z * (throat * swell),
        ));
      }
    } else {
      // Subdivide weld seam into smooth longitudinal slices with subtle bead scalloping
      rippleCount = math.max(8, (len / 3.5).round());
      final double step = len / rippleCount;

      for (int k = 0; k <= rippleCount; k++) {
        final double t = -len / 2.0 + k * step;
        // Authentic prominent convex crown swell with pronounced 3D weld bead scallops (SS2)
        final double swell = 1.30 + 0.25 * math.cos(k * math.pi * 2.0);
        final rPt = CadPoint3D(rootPt.x + u.x * t, rootPt.y + u.y * t, rootPt.z + u.z * t);
        rootPts.add(rPt);
        toe1Pts.add(CadPoint3D(rPt.x + dir1.x * a, rPt.y + dir1.y * a, rPt.z + dir1.z * a));
        toe2Pts.add(CadPoint3D(rPt.x + dir2.x * a, rPt.y + dir2.y * a, rPt.z + dir2.z * a));
        crownPts.add(CadPoint3D(
          rPt.x + nCrown.x * (throat * swell),
          rPt.y + nCrown.y * (throat * swell),
          rPt.z + nCrown.z * (throat * swell),
        ));
      }
    }

    // Base color for end caps & weld boundary (AWS D1.1 / ISO 2553)
    final Color baseBeadColor = isSelected
        ? const Color(0xFF00E5FF)
        : (showWeldOverlay ? const Color(0xD9F59E0B) : const Color(0xFF78909C));

    for (int k = 0; k < rippleCount; k++) {
      // Authentic molten welding bead coloration with heat ripple gradation across crests & troughs (SS2)
      final double rippleT = 0.5 + 0.5 * math.sin(k * math.pi * 2.0);
      final Color beadColor;
      if (isSelected) {
        beadColor = const Color(0xFF00E5FF); // Vibrant selection cyan #00E5FF
      } else if (showWeldOverlay) {
        // First slice matches exact spec amber D9F59E0B, subsequent slices feature molten golden crest highlights
        beadColor = (k == 0)
            ? const Color(0xD9F59E0B)
            : Color.lerp(const Color(0xD9F59E0B), const Color(0xFFFBBF24), rippleT * 0.45)!;
      } else {
        // Solid tempered steel bead finish with subtle heat ripple
        beadColor = (k == 0)
            ? const Color(0xFF78909C)
            : Color.lerp(const Color(0xFF78909C), const Color(0xFF90A4AE), rippleT * 0.35)!;
      }

      // Exposed outer face 1: Toe1 to Crown (prominent convex surface with bead scallop crescent crest)
      allPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'weld_$weldId',
          vertices: [toe1Pts[k], toe1Pts[k + 1], crownPts[k + 1], crownPts[k]],
          normal: CadPoint3D(
            dir1.x * 0.707 + nCrown.x * 0.707,
            dir1.y * 0.707 + nCrown.y * 0.707,
            dir1.z * 0.707 + nCrown.z * 0.707,
          ),
          color: beadColor,
          drawWireframe: false,
        ),
      );

      // Exposed outer face 2: Crown to Toe2 (prominent convex surface with bead scallop crescent crest)
      allPolygons.add(
        CadFoldedPolygon3D(
          faceId: 'weld_$weldId',
          vertices: [crownPts[k], crownPts[k + 1], toe2Pts[k + 1], toe2Pts[k]],
          normal: CadPoint3D(
            dir2.x * 0.707 + nCrown.x * 0.707,
            dir2.y * 0.707 + nCrown.y * 0.707,
            dir2.z * 0.707 + nCrown.z * 0.707,
          ),
          color: beadColor,
          drawWireframe: false,
        ),
      );
    }

    // Start end cap at -len / 2 (solid planar cap, no interior partitions)
    allPolygons.add(
      CadFoldedPolygon3D(
        faceId: 'weld_$weldId',
        vertices: [rootPts[0], toe1Pts[0], crownPts[0]],
        normal: CadPoint3D(-u.x, -u.y, -u.z),
        color: baseBeadColor,
        drawWireframe: false,
      ),
    );
    allPolygons.add(
      CadFoldedPolygon3D(
        faceId: 'weld_$weldId',
        vertices: [rootPts[0], crownPts[0], toe2Pts[0]],
        normal: CadPoint3D(-u.x, -u.y, -u.z),
        color: baseBeadColor,
        drawWireframe: false,
      ),
    );

    // End cap at +len / 2 (solid planar cap, no interior partitions)
    final last = rippleCount;
    allPolygons.add(
      CadFoldedPolygon3D(
        faceId: 'weld_$weldId',
        vertices: [rootPts[last], crownPts[last], toe1Pts[last]],
        normal: u,
        color: baseBeadColor,
        drawWireframe: false,
      ),
    );
    allPolygons.add(
      CadFoldedPolygon3D(
        faceId: 'weld_$weldId',
        vertices: [rootPts[last], toe2Pts[last], crownPts[last]],
        normal: u,
        color: baseBeadColor,
        drawWireframe: false,
      ),
    );
  }
}
