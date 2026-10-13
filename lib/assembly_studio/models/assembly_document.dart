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

  /// Constructs a real 3D stacked-dimes string of beads matching authentic welding bead geometry.
  /// Strictly maintains the exact drawn beads path, eliminates triangular wedges/partitions,
  /// and guarantees the beads sit proud on the exterior surfaces touched by the torch.
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
    // 1. Establish the 3D stroke path spine
    List<CadPoint3D> spinePoints;
    if (pathPoints != null && pathPoints.length >= 2) {
      spinePoints = pathPoints;
    } else {
      CadPoint3D u = axis;
      final uLen = math.sqrt(u.x * u.x + u.y * u.y + u.z * u.z);
      if (uLen > 1e-4) {
        u = CadPoint3D(u.x / uLen, u.y / uLen, u.z / uLen);
      } else {
        u = const CadPoint3D(1.0, 0.0, 0.0);
      }
      final len = math.max(12.0, length);
      spinePoints = [
        CadPoint3D(rootPt.x - u.x * (len / 2.0), rootPt.y - u.y * (len / 2.0), rootPt.z - u.z * (len / 2.0)),
        CadPoint3D(rootPt.x + u.x * (len / 2.0), rootPt.y + u.y * (len / 2.0), rootPt.z + u.z * (len / 2.0)),
      ];
    }

    // 2. Compute nominal outward normal from metal surfaces
    CadPoint3D nOutward = CadPoint3D(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z);
    final nLen = math.sqrt(nOutward.x * nOutward.x + nOutward.y * nOutward.y + nOutward.z * nOutward.z);
    if (nLen > 1e-4) {
      nOutward = CadPoint3D(nOutward.x / nLen, nOutward.y / nLen, nOutward.z / nLen);
    } else {
      nOutward = const CadPoint3D(0.0, 0.0, 1.0);
    }
    // Guarantee outward normal points towards positive hemisphere (never inverted underneath)
    if ((v1.z >= -0.01 || v2.z >= -0.01) && nOutward.z < -0.01) {
      nOutward = CadPoint3D(nOutward.x, nOutward.y, nOutward.z.abs());
    }

    // 3. Compute cumulative arc-length parameterization
    final cumDists = <double>[0.0];
    for (int i = 1; i < spinePoints.length; i++) {
      cumDists.add(cumDists.last + spinePoints[i].distanceTo(spinePoints[i - 1]));
    }
    final totalPathLen = cumDists.last;
    if (totalPathLen < 0.5) return;

    // Authentic stacked-dimes bead pitch & diameter
    final double beadRadius = math.max(3.2, legSize * 0.45);
    final double beadPitch = math.max(2.2, beadRadius * 0.68);
    final int numBeads = math.max(2, (totalPathLen / beadPitch).round());

    CadPoint3D getPointAtDist(double targetD) {
      final tDist = targetD.clamp(0.0, totalPathLen);
      for (int i = 0; i < cumDists.length - 1; i++) {
        if (tDist <= cumDists[i + 1]) {
          final segLen = cumDists[i + 1] - cumDists[i];
          final f = segLen > 1e-5 ? (tDist - cumDists[i]) / segLen : 0.0;
          final pA = spinePoints[i];
          final pB = spinePoints[i + 1];
          return CadPoint3D(pA.x + (pB.x - pA.x) * f, pA.y + (pB.y - pA.y) * f, pA.z + (pB.z - pA.z) * f);
        }
      }
      return spinePoints.last;
    }

    // 4. Generate stacked dime beads
    const int kFacets = 6;
    for (int k = 0; k <= numBeads; k++) {
      final distK = (k / numBeads) * totalPathLen;
      final cPt = getPointAtDist(distK);

      // Local tangent vector
      final nextPt = getPointAtDist(math.min(totalPathLen, distK + 2.0));
      final prevPt = getPointAtDist(math.max(0.0, distK - 2.0));
      var tX = nextPt.x - prevPt.x;
      var tY = nextPt.y - prevPt.y;
      var tZ = nextPt.z - prevPt.z;
      final tLen = math.sqrt(tX * tX + tY * tY + tZ * tZ);
      if (tLen > 1e-4) {
        tX /= tLen; tY /= tLen; tZ /= tLen;
      } else {
        tX = 1.0; tY = 0.0; tZ = 0.0;
      }
      final tangent = CadPoint3D(tX, tY, tZ);

      // Local binormal = nOutward x tangent
      var bX = nOutward.y * tangent.z - nOutward.z * tangent.y;
      var bY = nOutward.z * tangent.x - nOutward.x * tangent.z;
      var bZ = nOutward.x * tangent.y - nOutward.y * tangent.x;
      final bLen = math.sqrt(bX * bX + bY * bY + bZ * bZ);
      final binormal = bLen > 1e-4
          ? CadPoint3D(bX / bLen, bY / bLen, bZ / bLen)
          : (tangent.x.abs() < 0.9 ? const CadPoint3D(1.0, 0.0, 0.0) : const CadPoint3D(0.0, 1.0, 0.0));

      // Stacked dome geometry
      final double crownH = beadRadius * 0.65;
      final double relief = math.max(0.6, beadRadius * 0.12);
      final centerWithRelief = CadPoint3D(
        cPt.x + nOutward.x * relief,
        cPt.y + nOutward.y * relief,
        cPt.z + nOutward.z * relief,
      );

      final double apexZ = (nOutward.z >= -0.01 && (centerWithRelief.z + nOutward.z * crownH) < cPt.z)
          ? cPt.z
          : centerWithRelief.z + nOutward.z * crownH;
      final apex = CadPoint3D(
        centerWithRelief.x + nOutward.x * crownH,
        centerWithRelief.y + nOutward.y * crownH,
        apexZ,
      );

      // Rim vertices tilted backward along tangent (classic stacked dimes overlap)
      final rimVerts = <CadPoint3D>[];
      final baseVerts = <CadPoint3D>[];
      for (int f = 0; f < kFacets; f++) {
        final angle = f * (2.0 * math.pi / kFacets);
        final cosA = math.cos(angle);
        final sinA = math.sin(angle);

        final rawRimZ = centerWithRelief.z + binormal.z * (beadRadius * cosA) + tangent.z * (beadRadius * 0.85 * sinA - beadRadius * 0.20) + nOutward.z * (crownH * 0.22);
        final rimZ = (nOutward.z >= -0.01 && rawRimZ < cPt.z) ? cPt.z : rawRimZ;
        final rimPt = CadPoint3D(
          centerWithRelief.x + binormal.x * (beadRadius * cosA) + tangent.x * (beadRadius * 0.85 * sinA - beadRadius * 0.20) + nOutward.x * (crownH * 0.22),
          centerWithRelief.y + binormal.y * (beadRadius * cosA) + tangent.y * (beadRadius * 0.85 * sinA - beadRadius * 0.20) + nOutward.y * (crownH * 0.22),
          rimZ,
        );
        rimVerts.add(rimPt);

        final rawBaseZ = cPt.z + binormal.z * (beadRadius * 1.05 * cosA) + tangent.z * (beadRadius * 1.05 * sinA);
        final baseZ = (nOutward.z >= -0.01 && rawBaseZ < cPt.z) ? cPt.z : rawBaseZ;
        final basePt = CadPoint3D(
          cPt.x + binormal.x * (beadRadius * 1.05 * cosA) + tangent.x * (beadRadius * 1.05 * sinA),
          cPt.y + binormal.y * (beadRadius * 1.05 * cosA) + tangent.y * (beadRadius * 1.05 * sinA),
          baseZ,
        );
        baseVerts.add(basePt);
      }

      // Heat ripple color variation across successive beads (authentic steel tone, zero blue tint)
      final double beadPhase = (k % 2 == 0) ? 0.0 : 1.0;
      final Color coreColor;
      final Color rimColor;
      if (isSelected) {
        coreColor = const Color(0xFF00E5FF);
        rimColor = const Color(0xFF00E5FF);
      } else if (showWeldOverlay) {
        coreColor = (k == 0 || beadPhase == 0) ? const Color(0xFF3F3F46) : const Color(0xFF4B5563);
        rimColor = const Color(0xFF27272A);
      } else {
        coreColor = (k == 0 || beadPhase == 0) ? const Color(0xFF27272A) : const Color(0xFF3F3F46);
        rimColor = const Color(0xFF18181B);
      }

      // Add dome facets (apex to rim)
      for (int f = 0; f < kFacets; f++) {
        final vA = apex;
        final vB = rimVerts[f];
        final vC = rimVerts[(f + 1) % kFacets];
        allPolygons.add(
          CadFoldedPolygon3D(
            faceId: 'weld_$weldId',
            vertices: [vA, vB, vC],
            normal: nOutward,
            color: coreColor,
            drawWireframe: false,
          ),
        );

        // Skirt face attaching bead to metal surface
        final vBaseB = baseVerts[f];
        final vBaseC = baseVerts[(f + 1) % kFacets];
        allPolygons.add(
          CadFoldedPolygon3D(
            faceId: 'weld_$weldId',
            vertices: [vB, vBaseB, vBaseC, vC],
            normal: nOutward,
            color: rimColor,
            drawWireframe: false,
          ),
        );
      }
    }
  }
}

