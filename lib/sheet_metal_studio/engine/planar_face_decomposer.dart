// =============================================================================
// planar_face_decomposer.dart
//
// Planar Graph Face Segmentation & Topology Engine.
// Splits an unfolded 2D sheet metal blank along press-brake bend lines into
// interconnected planar faces and constructs parent-child DAG relationships.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/fold_bend_line.dart';
import '../models/planar_sheet_face.dart';

class PlanarFaceDecomposer {
  /// Decomposes an outer contour, cut lines, and bend lines into planar faces and establishes
  /// parent-child topology for kinematic folding.
  static ({
    List<PlanarSheetFace> faces,
    List<FoldBendLine> connectedBends,
    String baseFaceId,
  }) decompose({
    required List<CadPoint2D> outerContour,
    required List<FoldBendLine> bends,
    List<CadLineSegment> cutLines = const [],
    String? preferredBaseFaceId,
  }) {
    if (outerContour.length < 3) {
      return (faces: [], connectedBends: bends, baseFaceId: '');
    }

    if (bends.isEmpty && cutLines.isEmpty) {
      final singleFace = PlanarSheetFace(
        id: 'F_BASE',
        label: 'Base Sheet',
        vertices: _normalizeCCW(outerContour),
        role: FaceRole.baseFloor,
        isBaseAnchor: true,
      );
      return (faces: [singleFace], connectedBends: bends, baseFaceId: 'F_BASE');
    }

    // 1. Process laser cut lines (through-cuts and corner relief slits)
    var activePolygons = <List<CadPoint2D>>[outerContour];

    for (final cut in cutLines) {
      final nextPolygons = <List<CadPoint2D>>[];
      for (final poly in activePolygons) {
        final split = _slicePolygon(poly, cut.p1, cut.p2);
        if (split != null && split.$1.length >= 3 && split.$2.length >= 3) {
          nextPolygons.add(split.$1);
          nextPolygons.add(split.$2);
        } else {
          final slitPoly = _tryInsertSlit(poly, cut.p1, cut.p2);
          nextPolygons.add(slitPoly ?? poly);
        }
      }
      activePolygons = nextPolygons;
    }

    // 2. Iteratively slice the polygon along each bend line
    final successfulSplits = <String>{};

    for (final bend in bends) {
      final nextPolygons = <List<CadPoint2D>>[];
      bool didSplit = false;
      for (final poly in activePolygons) {
        final split = _slicePolygon(poly, bend.p1, bend.p2);
        if (split != null && split.$1.length >= 3 && split.$2.length >= 3) {
          nextPolygons.add(split.$1);
          nextPolygons.add(split.$2);
          didSplit = true;
        } else {
          nextPolygons.add(poly);
        }
      }
      if (didSplit) {
        successfulSplits.add(bend.id);
      }
      activePolygons = nextPolygons;
    }

    // 3. Wrap into PlanarSheetFace objects with guaranteed Counter-Clockwise (CCW) winding
    final faces = <PlanarSheetFace>[];
    for (int i = 0; i < activePolygons.length; i++) {
      faces.add(PlanarSheetFace(
        id: 'F_$i',
        label: 'Panel $i',
        vertices: _normalizeCCW(activePolygons[i]),
        role: FaceRole.custom,
      ));
    }

    // 3. Find adjacent faces for each bend line
    final updatedBends = <FoldBendLine>[];
    for (final bend in bends) {
      if (!successfulSplits.contains(bend.id)) {
        // Bend did not partition any face (incomplete / open bend)
        updatedBends.add(bend.copyWith(
          parentFaceId: '',
          childFaceId: '',
        ));
        continue;
      }

      // Midpoint of bend line
      final mid = bend.midpoint;
      final u = bend.unitNormal;

      // Probe small offset on either side of the bend line
      const probeDist = 2.0;
      final probeA = CadPoint2D(mid.x + u.x * probeDist, mid.y + u.y * probeDist);
      final probeB = CadPoint2D(mid.x - u.x * probeDist, mid.y - u.y * probeDist);

      String faceAId = '';
      String faceBId = '';

      for (final face in faces) {
        if (faceAId.isEmpty && _isPointInsidePolygon(probeA, face.vertices)) {
          faceAId = face.id;
        }
        if (faceBId.isEmpty && _isPointInsidePolygon(probeB, face.vertices)) {
          faceBId = face.id;
        }
      }

      // If probe was outside due to concavity, fallback to closest centroids
      if (faceAId.isEmpty || faceBId.isEmpty || faceAId == faceBId) {
        final sortedByDist = faces.toList()
          ..sort((f1, f2) =>
              f1.centroid.distanceTo(mid).compareTo(f2.centroid.distanceTo(mid)));
        if (sortedByDist.length >= 2) {
          faceAId = sortedByDist[0].id;
          faceBId = sortedByDist[1].id;
        }
      }

      updatedBends.add(bend.copyWith(
        parentFaceId: faceAId,
        childFaceId: faceBId,
      ));
    }

    // 4. Determine the Base Anchor Face (Root of DAG)
    // Select face with largest 2D area (standard CAD convention for base sheet)
    String baseId = preferredBaseFaceId ?? '';
    if (baseId.isEmpty || !faces.any((f) => f.id == baseId)) {
      PlanarSheetFace largest = faces.first;
      double maxArea = -1.0;
      for (final f in faces) {
        final a = _computePolygonArea(f.vertices).abs();
        if (a > maxArea) {
          maxArea = a;
          largest = f;
        }
      }
      baseId = largest.id;
    }

    // 5. Direct the bend connections from Base Face outward (Parent -> Child DAG)
    final directedBends = _orientBendsFromBase(baseId, updatedBends, faces);

    // 6. Assign semantic roles based on depth from base floor
    final depthMap = _computeFaceDepths(baseId, directedBends);
    final finalizedFaces = faces.map((f) {
      final depth = depthMap[f.id] ?? 0;
      final isBase = f.id == baseId;
      FaceRole role;
      if (isBase) {
        role = FaceRole.baseFloor;
      } else if (depth == 1) {
        role = FaceRole.sideWall;
      } else if (depth >= 2) {
        role = FaceRole.returnFlange;
      } else {
        role = FaceRole.custom;
      }
      return f.copyWith(
        isBaseAnchor: isBase,
        role: role,
        label: isBase
            ? 'Bottom Base Floor'
            : (depth == 1 ? 'Side Wall' : 'Return Flange'),
      );
    }).toList();

    return (
      faces: finalizedFaces,
      connectedBends: directedBends,
      baseFaceId: baseId,
    );
  }

  /// Slices a polygon by a finite segment passing between p1 and p2.
  /// Returns null if the segment does not completely span between two boundaries of the polygon.
  /// This prevents halfway bend lines from erroneously cutting faces or creating gaps.
  static (List<CadPoint2D>, List<CadPoint2D>)? _slicePolygon(
    List<CadPoint2D> poly,
    CadPoint2D p1,
    CadPoint2D p2,
  ) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return null;

    // 1. Try topological boundary chord slice (for corner relief cuts, slits, and boundary-to-boundary bends)
    final chordResult = _tryChordSlice(poly, p1, p2);
    if (chordResult != null) {
      return chordResult;
    }

    final nx = -dy / len;
    final ny = dx / len;

    double dist(CadPoint2D pt) => (pt.x - p1.x) * nx + (pt.y - p1.y) * ny;

    final polyA = <CadPoint2D>[];
    final polyB = <CadPoint2D>[];
    final rawIntersections = <CadPoint2D>[];

    const eps = 1e-4;

    for (int i = 0; i < poly.length; i++) {
      final cur = poly[i];
      final next = poly[(i + 1) % poly.length];

      final dCur = dist(cur);
      final dNext = dist(next);

      if (dCur > eps) {
        polyA.add(cur);
      } else if (dCur < -eps) {
        polyB.add(cur);
      } else {
        polyA.add(cur);
        polyB.add(cur);
      }

      // Check for edge intersection
      if ((dCur > eps && dNext < -eps) || (dCur < -eps && dNext > eps)) {
        final s = dCur / (dCur - dNext);
        final ix = cur.x + s * (next.x - cur.x);
        final iy = cur.y + s * (next.y - cur.y);
        final intersect = CadPoint2D(ix, iy);
        rawIntersections.add(intersect);
        polyA.add(intersect);
        polyB.add(intersect);
      } else if (dCur.abs() <= eps) {
        // Vertex is on the line — check if polygon crosses the line at this vertex
        final prev = poly[(i - 1 + poly.length) % poly.length];
        final dPrev = dist(prev);
        if ((dPrev > eps && dNext < -eps) || (dPrev < -eps && dNext > eps)) {
          rawIntersections.add(cur);
        }
      }
    }

    if (polyA.length >= 3 && polyB.length >= 3 && rawIntersections.isNotEmpty) {
      // Deduplicate intersections
      final intersections = <CadPoint2D>[];
      for (final pt in rawIntersections) {
        if (!intersections.any((existing) => existing.distanceTo(pt) < 1.0)) {
          intersections.add(pt);
        }
      }

      if (intersections.length < 2) return null;

      // Project all boundary crossing points onto segment parameter t:
      // t = 0.0 at p1, t = 1.0 at p2
      final tValues = intersections
          .map((pt) => ((pt.x - p1.x) * dx + (pt.y - p1.y) * dy) / (len * len))
          .toList()
        ..sort();

      final snapTolT = 3.5 / len;
      final tMin = tValues.first;
      final tMax = tValues.last;

      // Segment [p1, p2] (t in [0.0, 1.0]) must cover the polygon's chord [tMin, tMax]:
      // 1. Segment must overlap the chord
      if (tMin > 1.0 + snapTolT || tMax < -snapTolT) {
        return null;
      }
      // 2. Endpoints of [p1, p2] must reach or exceed the polygon boundaries (no halfway cuts)
      if (0.0 > tMin + snapTolT || 1.0 < tMax - snapTolT) {
        return null;
      }

      // Check 3: Area of both resulting sub-polygons must be non-zero (> 1.0 mm²)
      if (_computePolygonArea(polyA).abs() < 1.0 || _computePolygonArea(polyB).abs() < 1.0) {
        return null;
      }

      return (polyA, polyB);
    }
    return null;
  }

  /// Slices a polygon along a chord segment [p1, p2] where both endpoints lie on
  /// boundary edges or vertices (such as corner cuts or slits snapped to ends).
  static (List<CadPoint2D>, List<CadPoint2D>)? _tryChordSlice(
    List<CadPoint2D> poly,
    CadPoint2D p1,
    CadPoint2D p2,
  ) {
    if (poly.length < 3) return null;
    const snapTol = 3.5;

    int edgeIdx1 = -1;
    CadPoint2D? proj1;
    double bestDist1 = snapTol;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final d = _distToSegment(p1, a, b);
      if (d <= bestDist1) {
        bestDist1 = d;
        edgeIdx1 = i;
        proj1 = _projectToSegment(p1, a, b);
      }
    }

    int edgeIdx2 = -1;
    CadPoint2D? proj2;
    double bestDist2 = snapTol;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final d = _distToSegment(p2, a, b);
      if (d <= bestDist2) {
        bestDist2 = d;
        edgeIdx2 = i;
        proj2 = _projectToSegment(p2, a, b);
      }
    }

    if (edgeIdx1 == -1 || edgeIdx2 == -1 || proj1 == null || proj2 == null) {
      return null;
    }

    if (proj1.distanceTo(proj2) < 2.0) {
      return null;
    }

    // Midpoint of segment must lie inside or on polygon boundary
    final mid = CadPoint2D((proj1.x + proj2.x) / 2.0, (proj1.y + proj2.y) / 2.0);
    final isInside = _isPointInsidePolygon(CadPoint2D(mid.x + 1e-3, mid.y + 1e-3), poly) ||
        _isPointInsidePolygon(CadPoint2D(mid.x - 1e-3, mid.y - 1e-3), poly) ||
        _isPointInsidePolygon(mid, poly);
    if (!isInside) {
      bool nearBoundary = false;
      for (int i = 0; i < poly.length; i++) {
        if (_distToSegment(mid, poly[i], poly[(i + 1) % poly.length]) <= 1.0) {
          nearBoundary = true;
          break;
        }
      }
      if (!nearBoundary) return null;
    }

    // Build augmented polygon with proj1 and proj2 inserted
    final aug = <CadPoint2D>[];
    int idx1InAug = -1;
    int idx2InAug = -1;

    for (int i = 0; i < poly.length; i++) {
      final cur = poly[i];
      if (cur.distanceTo(proj1) < 0.1 && idx1InAug == -1) {
        idx1InAug = aug.length;
        aug.add(cur);
      } else if (cur.distanceTo(proj2) < 0.1 && idx2InAug == -1) {
        idx2InAug = aug.length;
        aug.add(cur);
      } else {
        aug.add(cur);
      }

      if (i == edgeIdx1 && idx1InAug == -1) {
        idx1InAug = aug.length;
        aug.add(proj1);
      }
      if (i == edgeIdx2 && idx2InAug == -1) {
        idx2InAug = aug.length;
        aug.add(proj2);
      }
    }

    if (idx1InAug == -1 || idx2InAug == -1 || idx1InAug == idx2InAug) {
      return null;
    }

    final firstIdx = math.min(idx1InAug, idx2InAug);
    final secondIdx = math.max(idx1InAug, idx2InAug);

    final loop1 = <CadPoint2D>[];
    for (int i = firstIdx; i <= secondIdx; i++) {
      loop1.add(aug[i]);
    }

    final loop2 = <CadPoint2D>[];
    for (int i = secondIdx; i < aug.length; i++) {
      loop2.add(aug[i]);
    }
    for (int i = 0; i <= firstIdx; i++) {
      loop2.add(aug[i]);
    }

    final clean1 = _cleanPolygon(loop1);
    final clean2 = _cleanPolygon(loop2);

    if (clean1.length >= 3 && clean2.length >= 3) {
      final area1 = _computePolygonArea(clean1).abs();
      final area2 = _computePolygonArea(clean2).abs();
      if (area1 >= 1.0 && area2 >= 1.0) {
        return (clean1, clean2);
      }
    }
    return null;
  }

  static List<CadPoint2D> _cleanPolygon(List<CadPoint2D> poly) {
    if (poly.isEmpty) return poly;
    final res = <CadPoint2D>[poly.first];
    for (int i = 1; i < poly.length; i++) {
      if (poly[i].distanceTo(res.last) > 0.05) {
        res.add(poly[i]);
      }
    }
    if (res.length > 1 && res.last.distanceTo(res.first) < 0.05) {
      res.removeLast();
    }
    return res;
  }

  /// Attempts to insert an incision slit cut into a polygon boundary.
  /// If one endpoint lies on an edge and the other is in the interior,
  /// inserts the slit loop into the polygon perimeter so subsequent bends can snap to it.
  static List<CadPoint2D>? _tryInsertSlit(
    List<CadPoint2D> poly,
    CadPoint2D p1,
    CadPoint2D p2,
  ) {
    if (poly.length < 3) return null;
    const snapTol = 3.5;

    int edgeIdx1 = -1;
    CadPoint2D? proj1;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      if (_distToSegment(p1, a, b) <= snapTol) {
        edgeIdx1 = i;
        proj1 = _projectToSegment(p1, a, b);
        break;
      }
    }

    int edgeIdx2 = -1;
    CadPoint2D? proj2;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      if (_distToSegment(p2, a, b) <= snapTol) {
        edgeIdx2 = i;
        proj2 = _projectToSegment(p2, a, b);
        break;
      }
    }

    if (edgeIdx1 != -1 && edgeIdx2 == -1) {
      return _buildSlitPolygon(poly, edgeIdx1, proj1 ?? p1, p2);
    } else if (edgeIdx2 != -1 && edgeIdx1 == -1) {
      return _buildSlitPolygon(poly, edgeIdx2, proj2 ?? p2, p1);
    }
    return null;
  }

  static List<CadPoint2D> _buildSlitPolygon(
    List<CadPoint2D> poly,
    int edgeIdx,
    CadPoint2D pEdge,
    CadPoint2D pTip,
  ) {
    final result = <CadPoint2D>[];
    for (int i = 0; i <= edgeIdx; i++) {
      result.add(poly[i]);
    }
    result.add(pEdge);
    result.add(pTip);
    result.add(pEdge);
    for (int i = edgeIdx + 1; i < poly.length; i++) {
      result.add(poly[i]);
    }
    return result;
  }

  static double _distToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 < 1e-8) return p.distanceTo(a);
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
    final proj = CadPoint2D(a.x + t * dx, a.y + t * dy);
    return p.distanceTo(proj);
  }

  static CadPoint2D _projectToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 < 1e-8) return a;
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
    return CadPoint2D(a.x + t * dx, a.y + t * dy);
  }

  /// Computes polygon area using shoelace formula
  static double _computePolygonArea(List<CadPoint2D> poly) {
    if (poly.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < poly.length; i++) {
      final cur = poly[i];
      final next = poly[(i + 1) % poly.length];
      area += (cur.x * next.y) - (next.x * cur.y);
    }
    return area / 2.0;
  }

  /// Enforces Counter-Clockwise (CCW) winding order for all face polygons
  static List<CadPoint2D> _normalizeCCW(List<CadPoint2D> poly) {
    if (poly.length < 3) return poly;
    if (_computePolygonArea(poly) < 0.0) {
      return poly.reversed.toList();
    }
    return poly;
  }

  /// Ray-casting point-in-polygon test
  static bool isPointInsidePolygon(CadPoint2D pt, List<CadPoint2D> poly) {
    if (poly.length < 3) return false;
    bool inside = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      if ((poly[i].y > pt.y) != (poly[j].y > pt.y) &&
          pt.x <
              (poly[j].x - poly[i].x) * (pt.y - poly[i].y) /
                      (poly[j].y - poly[i].y) +
                  poly[i].x) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  static bool _isPointInsidePolygon(CadPoint2D pt, List<CadPoint2D> poly) =>
      isPointInsidePolygon(pt, poly);

  /// Re-orients all bends so parentFaceId is closer to Base than childFaceId
  static List<FoldBendLine> _orientBendsFromBase(
    String baseId,
    List<FoldBendLine> bends,
    List<PlanarSheetFace> faces,
  ) {
    final visited = <String>{baseId};
    final directed = <FoldBendLine>[];
    final remainingBends = bends.toList();

    while (remainingBends.isNotEmpty) {
      bool progress = false;
      for (int i = 0; i < remainingBends.length; i++) {
        final b = remainingBends[i];
        if (visited.contains(b.parentFaceId) && !visited.contains(b.childFaceId)) {
          directed.add(b);
          visited.add(b.childFaceId);
          remainingBends.removeAt(i);
          progress = true;
          break;
        } else if (visited.contains(b.childFaceId) && !visited.contains(b.parentFaceId)) {
          // Invert parent and child so parent is the known/closer face
          directed.add(b.copyWith(
            parentFaceId: b.childFaceId,
            childFaceId: b.parentFaceId,
          ));
          visited.add(b.parentFaceId);
          remainingBends.removeAt(i);
          progress = true;
          break;
        }
      }
      if (!progress) {
        // Disconnected bends, add as is
        directed.addAll(remainingBends);
        break;
      }
    }

    return directed;
  }

  /// Computes graph depth (distance in bends) from the base anchor face
  static Map<String, int> _computeFaceDepths(
    String baseId,
    List<FoldBendLine> directedBends,
  ) {
    final depths = <String, int>{baseId: 0};
    for (final b in directedBends) {
      final pDepth = depths[b.parentFaceId] ?? 0;
      depths[b.childFaceId] = pDepth + 1;
    }
    return depths;
  }
}
