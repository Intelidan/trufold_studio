// =============================================================================
// cms_3d_opening_detector.dart
//
// Extracts raw physical candidate opening loops and boundaries from the 3D
// folded sheet-metal mesh per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md
// (Section 11).
// =============================================================================

import 'dart:math' as math;
import '../kinematic_fold_engine.dart';
import '../../models/cad_primitives.dart';
import '../../models/dsf_document.dart';
import '../../models/planar_sheet_face.dart';
import '../../models/fold_bend_line.dart';

/// Represents a raw, uninterpreted physical opening loop extracted from 3D topology.
class CmsRaw3DOpening {
  final String openingId;
  final List<CadPoint3D> boundary3DVertices;
  final CadPoint3D floorEdgeP1;
  final CadPoint3D floorEdgeP2;
  final CadPoint2D flatFloorEdgeP1;
  final CadPoint2D flatFloorEdgeP2;
  final String floorFaceId;
  final List<String> sidewallFaceIds;
  final CadPoint3D outwardNormal;

  const CmsRaw3DOpening({
    required this.openingId,
    required this.boundary3DVertices,
    required this.floorEdgeP1,
    required this.floorEdgeP2,
    required this.flatFloorEdgeP1,
    required this.flatFloorEdgeP2,
    required this.floorFaceId,
    required this.sidewallFaceIds,
    required this.outwardNormal,
  });
}

/// Discovers open channel mouth boundaries from the folded 3D mesh.
class Cms3DOpeningDetector {
  /// Extracts all candidate channel openings from the document and its folded 3D mesh.
  static List<CmsRaw3DOpening> detectOpenings({
    required DsfDocument document,
    required FoldedMeshResult foldResult,
  }) {
    if (document.faces.isEmpty || foldResult.polygons.isEmpty) return const [];

    // 1. Identify all Floor Web faces (anchor base + connected riser segments)
    final floorFaces = _identifyFloorFaces(document, foldResult);
    if (floorFaces.isEmpty) return const [];

    // 2. Identify 3D standing sidewall faces connected to the floor via 90° structural bends
    final sidewallFaces = _findSidewalls(document, floorFaces, foldResult);

    // 3. For each floor face, find open terminal edges (filtering out bend lines and cheek cuts)
    final rawOpenings = <CmsRaw3DOpening>[];
    int index = 1;

    for (final floorFace in floorFaces) {
      final candidateFloorEdges = _findOpenFloorEdges(document, floorFace, sidewallFaces, foldResult);

      for (final floorEdge in candidateFloorEdges) {
        final p1Flat = floorEdge.p1;
        final p2Flat = floorEdge.p2;

        // Transform flat floor edge to 3D using floor polygon vertices
        final floor3DPoly = foldResult.polygons.firstWhere(
          (p) => p.faceId == floorFace.id,
          orElse: () => foldResult.polygons.first,
        );

        final p1_3d = _mapFlatTo3D(p1Flat, floorFace.vertices, floor3DPoly.vertices);
        final p2_3d = _mapFlatTo3D(p2Flat, floorFace.vertices, floor3DPoly.vertices);

        // Compute outward normal vector along the floor plane in true 3D
        final edgeDx = p2_3d.x - p1_3d.x;
        final edgeDy = p2_3d.y - p1_3d.y;
        final edgeDz = p2_3d.z - p1_3d.z;
        final edgeLen = math.sqrt(edgeDx * edgeDx + edgeDy * edgeDy + edgeDz * edgeDz);
        if (edgeLen < 1e-4) continue;

        final uW = CadPoint3D(edgeDx / edgeLen, edgeDy / edgeLen, edgeDz / edgeLen);
        final floorNorm = floor3DPoly.normal;

        // In-plane perpendicular: uW x floorNorm
        var normX = uW.y * floorNorm.z - uW.z * floorNorm.y;
        var normY = uW.z * floorNorm.x - uW.x * floorNorm.z;
        var normZ = uW.x * floorNorm.y - uW.y * floorNorm.x;
        final normLen = math.sqrt(normX * normX + normY * normY + normZ * normZ);
        if (normLen > 1e-4) {
          normX /= normLen;
          normY /= normLen;
          normZ /= normLen;
        }

        // Ensure outward normal points AWAY from floor center
        final mid3D = CadPoint3D(
          (p1_3d.x + p2_3d.x) / 2.0,
          (p1_3d.y + p2_3d.y) / 2.0,
          (p1_3d.z + p2_3d.z) / 2.0,
        );
        final floorCenter = _polygonCenter3D(floor3DPoly.vertices);
        final toMidX = mid3D.x - floorCenter.x;
        final toMidY = mid3D.y - floorCenter.y;
        final toMidZ = mid3D.z - floorCenter.z;
        if (normX * toMidX + normY * toMidY + normZ * toMidZ < 0) {
          normX = -normX;
          normY = -normY;
          normZ = -normZ;
        }
        final outwardNormal = CadPoint3D(normX, normY, normZ);

        // Find sidewall faces adjacent to p1 and p2
        final adjacentSidewallIds = <String>[];
        for (final sw in sidewallFaces) {
          adjacentSidewallIds.add(sw.id);
        }

        // Collect loop vertices (Floor edge P1 -> P2)
        final loop3D = <CadPoint3D>[p1_3d, p2_3d];

        rawOpenings.add(CmsRaw3DOpening(
          openingId: 'raw_opening_$index',
          boundary3DVertices: loop3D,
          floorEdgeP1: p1_3d,
          floorEdgeP2: p2_3d,
          flatFloorEdgeP1: p1Flat,
          flatFloorEdgeP2: p2Flat,
          floorFaceId: floorFace.id,
          sidewallFaceIds: adjacentSidewallIds,
          outwardNormal: outwardNormal,
        ));
        index++;
      }
    }

    return rawOpenings;
  }

  static List<PlanarSheetFace> _identifyFloorFaces(DsfDocument doc, FoldedMeshResult mesh) {
    if (doc.faces.isEmpty) return const [];

    // 1. Rank candidate faces by structural connectivity (attached to 90° structural sidewall bends) + area
    PlanarSheetFace? baseFace;
    double bestScore = -1.0;

    for (final face in doc.faces) {
      int structuralBends = 0;
      for (final b in doc.bends) {
        if (b.role != BendLineRole.flange &&
            (b.parentFaceId == face.id || b.childFaceId == face.id) &&
            (b.targetAngleDeg.abs() - 90.0).abs() < 15.0) {
          structuralBends++;
        }
      }

      // Check folded 3D normal horizontality (|normal.z| > 0.7)
      final polyMatches = mesh.polygons.where((p) => p.faceId == face.id);
      final isHorizontal = polyMatches.isNotEmpty && polyMatches.first.normal.z.abs() > 0.7;

      if (mesh.polygons.isNotEmpty && !isHorizontal) {
        continue;
      }

      double score = structuralBends * 10000.0 + face.areaMm2;
      if (face.isBaseAnchor || face.id == doc.baseFaceId) {
        score += 500.0;
      }

      if (score > bestScore) {
        bestScore = score;
        baseFace = face;
      }
    }

    baseFace ??= doc.faces.first;

    // 2. Identify initial sidewalls attached to baseFace via 90° bends
    final sidewallIds = <String>{};
    for (final b in doc.bends) {
      if ((b.parentFaceId == baseFace.id || b.childFaceId == baseFace.id) &&
          b.role != BendLineRole.flange &&
          (b.targetAngleDeg.abs() - 90.0).abs() < 15.0) {
        final otherId = b.parentFaceId == baseFace.id ? b.childFaceId : b.parentFaceId;
        sidewallIds.add(otherId);
      }
    }

    // 3. Traverse connected floor faces (e.g. angled riser segments or stepped transitions)
    final floorFaceMap = <String, PlanarSheetFace>{baseFace.id: baseFace};
    final queue = <PlanarSheetFace>[baseFace];

    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final b in doc.bends) {
        final connects = b.parentFaceId == curr.id || b.childFaceId == curr.id;
        if (!connects || b.role == BendLineRole.flange) continue;

        final otherId = b.parentFaceId == curr.id ? b.childFaceId : b.parentFaceId;
        if (floorFaceMap.containsKey(otherId) || sidewallIds.contains(otherId)) continue;

        final otherFace = doc.faces.firstWhere(
          (f) => f.id == otherId,
          orElse: () => PlanarSheetFace(id: otherId, vertices: const []),
        );
        if (otherFace.vertices.isEmpty) continue;

        // Ensure this face is not a sidewall or flange
        // Sidewalls have 90° bends to base and stand vertical (|normal.z| < 0.3)
        final polyMatches = mesh.polygons.where((p) => p.faceId == otherId);
        final isVerticalWall = polyMatches.isNotEmpty && polyMatches.first.normal.z.abs() < 0.3;
        if (!isVerticalWall) {
          floorFaceMap[otherId] = otherFace;
          queue.add(otherFace);
        }
      }
    }

    return floorFaceMap.values.toList();
  }

  static List<PlanarSheetFace> _findSidewalls(DsfDocument doc, List<PlanarSheetFace> floorFaces, FoldedMeshResult mesh) {
    final sidewalls = <PlanarSheetFace>[];
    final floorFaceIds = floorFaces.map((f) => f.id).toSet();

    for (final bend in doc.bends) {
      final parentIsFloor = floorFaceIds.contains(bend.parentFaceId);
      final childIsFloor = floorFaceIds.contains(bend.childFaceId);
      if (!parentIsFloor && !childIsFloor) continue;
      if (bend.role == BendLineRole.flange) continue;

      final otherFaceId = parentIsFloor ? bend.childFaceId : bend.parentFaceId;
      if (floorFaceIds.contains(otherFaceId)) continue;

      final otherFace = doc.faces.firstWhere(
        (f) => f.id == otherFaceId,
        orElse: () => PlanarSheetFace(id: otherFaceId, vertices: const []),
      );

      if (otherFace.vertices.isNotEmpty && (bend.targetAngleDeg.abs() - 90.0).abs() < 15.0) {
        if (!sidewalls.any((s) => s.id == otherFace.id)) {
          sidewalls.add(otherFace);
        }
      }
    }
    return sidewalls;
  }

  static bool _isEdgeAlongSidewall(
    CadPoint3D p1,
    CadPoint3D p2,
    List<PlanarSheetFace> sidewalls,
    FoldedMeshResult foldResult,
  ) {
    for (final sw in sidewalls) {
      final swPolys = foldResult.polygons.where((p) => p.faceId == sw.id);
      if (swPolys.isEmpty) continue;
      final swPoly = swPolys.first;
      if (swPoly.vertices.isEmpty) continue;

      // Check distance of p1 and p2 to sidewall plane
      final v0 = swPoly.vertices.first;
      final norm = swPoly.normal;
      final d1 = ((p1.x - v0.x) * norm.x + (p1.y - v0.y) * norm.y + (p1.z - v0.z) * norm.z).abs();
      final d2 = ((p2.x - v0.x) * norm.x + (p2.y - v0.y) * norm.y + (p2.z - v0.z) * norm.z).abs();

      if (d1 < 3.0 && d2 < 3.0) {
        // Both endpoints lie in the plane of this single sidewall (cheek cut/seam)
        return true;
      }
    }
    return false;
  }

  static List<({CadPoint2D p1, CadPoint2D p2})> _findOpenFloorEdges(
    DsfDocument doc,
    PlanarSheetFace floor,
    List<PlanarSheetFace> sidewalls,
    FoldedMeshResult mesh,
  ) {
    final openEdges = <({CadPoint2D p1, CadPoint2D p2})>[];
    final verts = floor.vertices;
    if (verts.length < 3) return openEdges;

    final floor3DPoly = mesh.polygons.firstWhere(
      (p) => p.faceId == floor.id,
      orElse: () => mesh.polygons.first,
    );

    final n = verts.length;
    for (int i = 0; i < n; i++) {
      final p1 = verts[i];
      final p2 = verts[(i + 1) % n];
      final edgeLen = p1.distanceTo(p2);
      if (edgeLen < 15.0) continue; // Skip tiny relief notches

      // Check if any bend line lies on or very close to this edge
      bool hasBend = false;
      for (final b in doc.bends) {
        if (_segmentMatchesBend(p1, p2, b)) {
          hasBend = true;
          break;
        }
      }
      if (hasBend) continue;

      // Check if edge is a cheek cut running along a single sidewall
      final p1_3d = _mapFlatTo3D(p1, floor.vertices, floor3DPoly.vertices);
      final p2_3d = _mapFlatTo3D(p2, floor.vertices, floor3DPoly.vertices);

      if (_isEdgeAlongSidewall(p1_3d, p2_3d, sidewalls, mesh)) {
        continue; // Cheek cut along sidewall seam, not a channel mouth
      }

      openEdges.add((p1: p1, p2: p2));
    }
    return openEdges;
  }

  static bool _segmentMatchesBend(CadPoint2D p1, CadPoint2D p2, FoldBendLine bend) {
    final bp1 = bend.p1;
    final bp2 = bend.p2;

    // Check distance of endpoints to bend line
    final d1 = _distPointToSeg(p1, bp1, bp2);
    final d2 = _distPointToSeg(p2, bp1, bp2);
    if (d1 < 2.5 && d2 < 2.5) return true;

    final bd1 = _distPointToSeg(bp1, p1, p2);
    final bd2 = _distPointToSeg(bp2, p1, p2);
    if (bd1 < 2.5 && bd2 < 2.5) return true;

    return false;
  }

  static double _distPointToSeg(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y);
    if (l2 < 1e-6) return p.distanceTo(a);
    final t = math.max(0.0, math.min(1.0, ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2));
    final proj = CadPoint2D(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
    return p.distanceTo(proj);
  }

  static CadPoint3D _mapFlatTo3D(CadPoint2D pt, List<CadPoint2D> flatPoly, List<CadPoint3D> poly3D) {
    if (flatPoly.isEmpty || poly3D.isEmpty) return CadPoint3D(pt.x, pt.y, 0);

    // Find closest vertex in flatPoly
    int bestIdx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < flatPoly.length; i++) {
      final d = pt.distanceTo(flatPoly[i]);
      if (d < minDist) {
        minDist = d;
        bestIdx = i;
      }
    }

    if (minDist < 2.0 && bestIdx < poly3D.length) {
      return poly3D[bestIdx];
    }
    return CadPoint3D(pt.x, pt.y, 0.0);
  }

  static CadPoint3D _polygonCenter3D(List<CadPoint3D> vertices) {
    if (vertices.isEmpty) return const CadPoint3D(0, 0, 0);
    double sx = 0, sy = 0, sz = 0;
    for (final v in vertices) {
      sx += v.x;
      sy += v.y;
      sz += v.z;
    }
    final inv = 1.0 / vertices.length;
    return CadPoint3D(sx * inv, sy * inv, sz * inv);
  }
}
