import 'dart:math' as math;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import '../models/cad_primitives.dart';

/// Pure-Dart industrial-grade Earcut polygon triangulator for 3D sheet metal CAD.
/// Supports arbitrary planar 3D polygons with inner cutout holes (round holes,
/// obround slots, coupler slots, perforations) and concave outlines.
class CadPolygonTriangulator {
  /// Triangulates a 3D planar polygon with optional inner cutout holes directly into a [GeometryBuilder].
  ///
  /// Each vertex added to [builder] is translated by [pivot].
  static void triangulateToBuilder({
    required List<CadPoint3D> outerVertices,
    required List<List<CadPoint3D>> holes,
    required CadPoint3D normal,
    required CadPoint3D pivot,
    required GeometryBuilder builder,
    vm.Vector4? baseLinearColor,
    double creviceAoStrength = 0.65,
    bool isInnerOrWebFace = false,
  }) {
    if (outerVertices.length < 3) return;

    // Helper that applies subtle vertex-level crevice darkening at 90° bend roots & hole rims
    void emitVertexColor(CadPoint3D pt, {required bool isHoleRim, required bool isCreaseCorner}) {
      if (baseLinearColor == null) return;
      double vAo = 1.0;
      if (isHoleRim) {
        // Subtle rim shadow around punched holes and slots (like Onshape SS3)
        vAo = 1.0 - (0.16 * creviceAoStrength);
      } else if (isInnerOrWebFace && isCreaseCorner) {
        // Soft crevice shadow along the 90° bend line where web and flange meet!
        vAo = 1.0 - (0.20 * creviceAoStrength);
      }
      builder.color(vm.Vector4(
        baseLinearColor.x * vAo,
        baseLinearColor.y * vAo,
        baseLinearColor.z * vAo,
        baseLinearColor.w,
      ));
    }

    // Fast-path: Quad polygon with NO holes -> Subdivide into 4 triangles around center
    // for smooth radial highlight in the center and soft crevice shading at edges
    if (holes.isEmpty && outerVertices.length == 4) {
      var nz = normal;
      final lenN = math.sqrt(nz.x * nz.x + nz.y * nz.y + nz.z * nz.z);
      if (lenN > 1e-6) {
        nz = CadPoint3D(nz.x / lenN, nz.y / lenN, nz.z / lenN);
      } else {
        nz = _computeNewellNormal(outerVertices);
      }

      final v0 = outerVertices[0];
      final v1 = outerVertices[1];
      final v2 = outerVertices[2];
      final e1 = CadPoint3D(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z);
      final e2 = CadPoint3D(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z);
      final crossX = e1.y * e2.z - e1.z * e2.y;
      final crossY = e1.z * e2.x - e1.x * e2.z;
      final crossZ = e1.x * e2.y - e1.y * e2.x;
      final dot = crossX * nz.x + crossY * nz.y + crossZ * nz.z;
      final bool isFlipped = dot < 0;

      // When crevice AO is active on inner/web faces, subdivide quad into 4 triangles around center
      if (creviceAoStrength > 0.05 && isInnerOrWebFace) {
        final pCenter = CadPoint3D(
          (outerVertices[0].x + outerVertices[1].x + outerVertices[2].x + outerVertices[3].x) * 0.25,
          (outerVertices[0].y + outerVertices[1].y + outerVertices[2].y + outerVertices[3].y) * 0.25,
          (outerVertices[0].z + outerVertices[1].z + outerVertices[2].z + outerVertices[3].z) * 0.25,
        );

        emitVertexColor(pCenter, isHoleRim: false, isCreaseCorner: false);
        builder.texCoord(_computeUv(pCenter, nz));
        final idxCenter = builder.addVertex(vm.Vector3(
          pCenter.x - pivot.x,
          pCenter.y - pivot.y,
          pCenter.z - pivot.z,
        ));

        final cornerIndices = <int>[];
        for (int i = 0; i < 4; i++) {
          final pt = outerVertices[i];
          emitVertexColor(pt, isHoleRim: false, isCreaseCorner: i == 0 || i == 1);
          builder.texCoord(_computeUv(pt, nz));
          cornerIndices.add(builder.addVertex(vm.Vector3(
            pt.x - pivot.x,
            pt.y - pivot.y,
            pt.z - pivot.z,
          )));
        }

        for (int i = 0; i < 4; i++) {
          final next = (i + 1) % 4;
          if (!isFlipped) {
            builder.addTriangle(idxCenter, cornerIndices[i], cornerIndices[next]);
          } else {
            builder.addTriangle(idxCenter, cornerIndices[next], cornerIndices[i]);
          }
        }
        return;
      }

      // Standard 2-triangle quad
      final indices = <int>[];
      for (int i = 0; i < 4; i++) {
        emitVertexColor(outerVertices[i], isHoleRim: false, isCreaseCorner: i == 0 || i == 1);
        builder.texCoord(_computeUv(outerVertices[i], nz));
        indices.add(builder.addVertex(vm.Vector3(
          outerVertices[i].x - pivot.x,
          outerVertices[i].y - pivot.y,
          outerVertices[i].z - pivot.z,
        )));
      }

      if (!isFlipped) {
        builder.addTriangle(indices[0], indices[1], indices[2]);
        builder.addTriangle(indices[0], indices[2], indices[3]);
      } else {
        builder.addTriangle(indices[0], indices[2], indices[1]);
        builder.addTriangle(indices[0], indices[3], indices[2]);
      }
      return;
    }

    // Fast-path: Single triangle with NO holes
    if (holes.isEmpty && outerVertices.length == 3) {
      var nz = normal;
      final lenN = math.sqrt(nz.x * nz.x + nz.y * nz.y + nz.z * nz.z);
      if (lenN > 1e-6) {
        nz = CadPoint3D(nz.x / lenN, nz.y / lenN, nz.z / lenN);
      } else {
        nz = _computeNewellNormal(outerVertices);
      }

      final v0 = outerVertices[0];
      final v1 = outerVertices[1];
      final v2 = outerVertices[2];
      final e1 = CadPoint3D(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z);
      final e2 = CadPoint3D(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z);
      final crossX = e1.y * e2.z - e1.z * e2.y;
      final crossY = e1.z * e2.x - e1.x * e2.z;
      final crossZ = e1.x * e2.y - e1.y * e2.x;
      final dot = crossX * nz.x + crossY * nz.y + crossZ * nz.z;
      final bool isFlipped = dot < 0;

      final indices = <int>[];
      for (int i = 0; i < 3; i++) {
        emitVertexColor(outerVertices[i], isHoleRim: false, isCreaseCorner: i == 0 || i == 1);
        builder.texCoord(_computeUv(outerVertices[i], nz));
        indices.add(builder.addVertex(vm.Vector3(
          outerVertices[i].x - pivot.x,
          outerVertices[i].y - pivot.y,
          outerVertices[i].z - pivot.z,
        )));
      }
      if (!isFlipped) {
        builder.addTriangle(indices[0], indices[1], indices[2]);
      } else {
        builder.addTriangle(indices[0], indices[2], indices[1]);
      }
      return;
    }

    // 1. Orthonormal tangent basis (u, v) on the polygon plane
    var nz = normal;
    final lenN = math.sqrt(nz.x * nz.x + nz.y * nz.y + nz.z * nz.z);
    if (lenN > 1e-6) {
      nz = CadPoint3D(nz.x / lenN, nz.y / lenN, nz.z / lenN);
    } else {
      // Compute Newell normal if provided normal is degenerate
      nz = _computeNewellNormal(outerVertices);
    }

    final up = nz.z.abs() < 0.9 ? const CadPoint3D(0, 0, 1) : const CadPoint3D(1, 0, 0);
    final ux = up.y * nz.z - up.z * nz.y;
    final uy = up.z * nz.x - up.x * nz.z;
    final uz = up.x * nz.y - up.y * nz.x;
    final lenU = math.sqrt(ux * ux + uy * uy + uz * uz);
    final u = lenU > 1e-6 ? CadPoint3D(ux / lenU, uy / lenU, uz / lenU) : const CadPoint3D(1, 0, 0);

    final vx = nz.y * u.z - nz.z * u.y;
    final vy = nz.z * u.x - nz.x * u.z;
    final vz = nz.x * u.y - nz.y * u.x;
    final v = CadPoint3D(vx, vy, vz);

    final origin = outerVertices[0];

    // 2. Flatten outer vertices and hole loops into 2D coordinates
    final coords = <double>[];
    final allPts3D = <CadPoint3D>[];
    final holeIndices = <int>[];

    void addLoop(List<CadPoint3D> loop) {
      for (final pt in loop) {
        allPts3D.add(pt);
        final dx = pt.x - origin.x;
        final dy = pt.y - origin.y;
        final dz = pt.z - origin.z;
        final x2d = dx * u.x + dy * u.y + dz * u.z;
        final y2d = dx * v.x + dy * v.y + dz * v.z;
        coords.add(x2d);
        coords.add(y2d);
      }
    }

    addLoop(outerVertices);

    for (final hole in holes) {
      if (hole.length < 3) continue;
      holeIndices.add(allPts3D.length);
      addLoop(hole);
    }

    // 3. Run Earcut triangulation
    final triIndices = triangulate(coords, holeIndices);
    if (triIndices.isEmpty) return;

    // 4. Map 3D points into builder vertices and add triangles
    final builderIndices = <int>[];
    for (int i = 0; i < allPts3D.length; i++) {
      final pt = allPts3D[i];
      final bool isHole = (i >= outerVertices.length);
      final bool isCrease = (!isHole && (i == 0 || i == 1));
      emitVertexColor(pt, isHoleRim: isHole, isCreaseCorner: isCrease);

      final uCoord = (i * 2 < coords.length) ? coords[i * 2] * 0.01 : pt.x * 0.01;
      final vCoord = (i * 2 + 1 < coords.length) ? coords[i * 2 + 1] * 0.01 : pt.y * 0.01;
      builder.texCoord(vm.Vector2(uCoord, vCoord));
      final pVec = vm.Vector3(pt.x - pivot.x, pt.y - pivot.y, pt.z - pivot.z);
      builderIndices.add(builder.addVertex(pVec));
    }

    for (int i = 0; i < triIndices.length; i += 3) {
      final i0 = triIndices[i];
      final i1 = triIndices[i + 1];
      final i2 = triIndices[i + 2];

      if (i0 >= allPts3D.length || i1 >= allPts3D.length || i2 >= allPts3D.length) continue;

      final p0 = allPts3D[i0];
      final p1 = allPts3D[i1];
      final p2 = allPts3D[i2];

      // Check triangle orientation against face normal nz
      final e1 = CadPoint3D(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z);
      final e2 = CadPoint3D(p2.x - p0.x, p2.y - p0.y, p2.z - p0.z);
      final crossX = e1.y * e2.z - e1.z * e2.y;
      final crossY = e1.z * e2.x - e1.x * e2.z;
      final crossZ = e1.x * e2.y - e1.y * e2.x;
      final dot = crossX * nz.x + crossY * nz.y + crossZ * nz.z;

      final b0 = builderIndices[i0];
      final b1 = builderIndices[i1];
      final b2 = builderIndices[i2];

      if (dot >= 0) {
        builder.addTriangle(b0, b1, b2);
      } else {
        builder.addTriangle(b0, b2, b1);
      }
    }
  }

  static CadPoint3D _computeNewellNormal(List<CadPoint3D> verts) {
    double nx = 0, ny = 0, nz = 0;
    final n = verts.length;
    for (int i = 0; i < n; i++) {
      final cur = verts[i];
      final next = verts[(i + 1) % n];
      nx += (cur.y - next.y) * (cur.z + next.z);
      ny += (cur.z - next.z) * (cur.x + next.x);
      nz += (cur.x - next.x) * (cur.y + next.y);
    }
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    return len > 1e-6 ? CadPoint3D(nx / len, ny / len, nz / len) : const CadPoint3D(0, 0, 1);
  }

  static vm.Vector2 _computeUv(CadPoint3D pt, CadPoint3D normal) {
    if (normal.z.abs() > 0.7) {
      return vm.Vector2(pt.x * 0.01, pt.y * 0.01);
    } else if (normal.x.abs() > 0.7) {
      return vm.Vector2(pt.y * 0.01, pt.z * 0.01);
    } else {
      return vm.Vector2(pt.x * 0.01, pt.z * 0.01);
    }
  }

  // ===========================================================================
  // Robust Pure Dart Earcut Implementation
  // ===========================================================================

  /// Triangulates a 2D polygon with optional holes using the Earcut algorithm.
  /// [data] is a flat array of 2D coordinates `[x0, y0, x1, y1, ...]`.
  /// [holeIndices] are indices of hole starting vertices (vertex index, not coordinate index).
  static List<int> triangulate(List<double> data, [List<int>? holeIndices, int dim = 2]) {
    final hasHoles = holeIndices != null && holeIndices.isNotEmpty;
    final outerLen = hasHoles ? holeIndices.first * dim : data.length;
    var outerNode = _createLinkedList(data, 0, outerLen, dim, true);
    final triangles = <int>[];

    if (outerNode == null || outerNode.next == outerNode.prev) return triangles;

    var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0, invSize = 0.0;

    if (hasHoles) {
      outerNode = _eliminateHoles(data, holeIndices, outerNode, dim);
    }

    // If the shape is not too simple, compute bounds for z-order curve hashing
    if (data.length > 80 * dim) {
      minX = maxX = data[0];
      minY = maxY = data[1];

      for (int i = dim; i < outerLen; i += dim) {
        final x = data[i];
        final y = data[i + 1];
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }

      invSize = math.max(maxX - minX, maxY - minY);
      invSize = invSize != 0.0 ? 32767.0 / invSize : 0.0;
    }

    _earcutLinked(outerNode, triangles, minX, minY, invSize, 0);

    return triangles;
  }

  static _EarcutNode? _createLinkedList(List<double> data, int start, int end, int dim, bool clockwise) {
    _EarcutNode? last;

    if (clockwise == (_signedArea(data, start, end, dim) > 0)) {
      for (int i = start; i < end; i += dim) {
        last = _insertNode(i ~/ dim, data[i], data[i + 1], last);
      }
    } else {
      for (int i = end - dim; i >= start; i -= dim) {
        last = _insertNode(i ~/ dim, data[i], data[i + 1], last);
      }
    }

    if (last != null && _equals(last, last.next!)) {
      _removeNode(last);
      last = last.next;
    }

    return last;
  }

  static _EarcutNode? _filterPoints(_EarcutNode? start, [_EarcutNode? end]) {
    if (start == null) return start;
    end ??= start;

    var p = start;
    bool again;
    do {
      again = false;

      if (!p.steiner && (_equals(p, p.next!) || _area(p.prev!, p, p.next!) == 0)) {
        _removeNode(p);
        p = end = p.prev!;
        if (p == p.next) break;
        again = true;
      } else {
        p = p.next!;
      }
    } while (again || p != end);

    return end;
  }

  static void _earcutLinked(_EarcutNode? ear, List<int> triangles, double minX, double minY, double invSize, int pass) {
    if (ear == null) return;

    if (pass == 0 && invSize != 0.0) _indexCurve(ear, minX, minY, invSize);

    var stop = ear;
    _EarcutNode? prev;
    _EarcutNode? next;

    while (ear!.prev != ear.next) {
      prev = ear.prev!;
      next = ear.next!;

      if (invSize != 0.0 ? _isEarHashed(ear, minX, minY, invSize) : _isEar(ear)) {
        triangles.addAll([prev.i, ear.i, next.i]);

        _removeNode(ear);

        ear = next.next!;
        stop = next.next!;

        continue;
      }

      ear = next;

      if (ear == stop) {
        if (pass == 0) {
          _earcutLinked(_filterPoints(ear), triangles, minX, minY, invSize, 1);
        } else if (pass == 1) {
          ear = _cureLocalIntersections(_filterPoints(ear), triangles);
          _earcutLinked(ear, triangles, minX, minY, invSize, 2);
        } else if (pass == 2) {
          _splitPolygon(ear, triangles, minX, minY, invSize);
        }
        break;
      }
    }
  }

  static bool _isEar(_EarcutNode ear) {
    final a = ear.prev!;
    final b = ear;
    final c = ear.next!;

    if (_area(a, b, c) >= 0) return false;

    final ax = a.x, bx = b.x, cx = c.x, ay = a.y, by = b.y, cy = c.y;

    final x0 = math.min(ax, math.min(bx, cx));
    final y0 = math.min(ay, math.min(by, cy));
    final x1 = math.max(ax, math.max(bx, cx));
    final y1 = math.max(ay, math.max(by, cy));

    var p = c.next!;
    while (p != a) {
      if (p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 &&
          _pointInTriangle(ax, ay, bx, by, cx, cy, p.x, p.y) &&
          _area(p.prev!, p, p.next!) >= 0) {
        return false;
      }
      p = p.next!;
    }

    return true;
  }

  static bool _isEarHashed(_EarcutNode ear, double minX, double minY, double invSize) {
    final a = ear.prev!;
    final b = ear;
    final c = ear.next!;

    if (_area(a, b, c) >= 0) return false;

    final ax = a.x, bx = b.x, cx = c.x, ay = a.y, by = b.y, cy = c.y;

    final x0 = math.min(ax, math.min(bx, cx));
    final y0 = math.min(ay, math.min(by, cy));
    final x1 = math.max(ax, math.max(bx, cx));
    final y1 = math.max(ay, math.max(by, cy));

    final minZ = _zOrder(x0, y0, minX, minY, invSize);
    final maxZ = _zOrder(x1, y1, minX, minY, invSize);

    var p = ear.prevZ;
    var q = ear.nextZ;

    while (p != null && p.z >= minZ && q != null && q.z <= maxZ) {
      if (p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 && p != a && p != c &&
          _pointInTriangle(ax, ay, bx, by, cx, cy, p.x, p.y) &&
          _area(p.prev!, p, p.next!) >= 0) {
        return false;
      }
      p = p.prevZ;

      if (q.x >= x0 && q.x <= x1 && q.y >= y0 && q.y <= y1 && q != a && q != c &&
          _pointInTriangle(ax, ay, bx, by, cx, cy, q.x, q.y) &&
          _area(q.prev!, q, q.next!) >= 0) {
        return false;
      }
      q = q.nextZ;
    }

    while (p != null && p.z >= minZ) {
      if (p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 && p != a && p != c &&
          _pointInTriangle(ax, ay, bx, by, cx, cy, p.x, p.y) &&
          _area(p.prev!, p, p.next!) >= 0) {
        return false;
      }
      p = p.prevZ;
    }

    while (q != null && q.z <= maxZ) {
      if (q.x >= x0 && q.x <= x1 && q.y >= y0 && q.y <= y1 && q != a && q != c &&
          _pointInTriangle(ax, ay, bx, by, cx, cy, q.x, q.y) &&
          _area(q.prev!, q, q.next!) >= 0) {
        return false;
      }
      q = q.nextZ;
    }

    return true;
  }

  static _EarcutNode _cureLocalIntersections(_EarcutNode? startNode, List<int> triangles) {
    var p = startNode!;
    do {
      final a = p.prev!;
      final b = p.next!.next!;

      if (!_equals(a, b) && _intersects(a, p, p.next!, b) && _locallyInside(a, b) && _locallyInside(b, a)) {
        triangles.addAll([a.i, p.i, p.next!.i]);

        _removeNode(p);
        _removeNode(p.next!);

        p = startNode = b;
      }
      p = p.next!;
    } while (p != startNode);

    return _filterPoints(p)!;
  }

  static void _splitPolygon(_EarcutNode? start, List<int> triangles, double minX, double minY, double invSize) {
    var a = start!;
    do {
      var b = a.next!.next!;
      while (b != a.prev) {
        if (a.i != b.i && _isValidDiagonal(a, b)) {
          var split = _splitPolygonNodes(a, b);

          a = _filterPoints(a, a.next)!;
          split = _filterPoints(split, split.next)!;

          _earcutLinked(a, triangles, minX, minY, invSize, 0);
          _earcutLinked(split, triangles, minX, minY, invSize, 0);
          return;
        }
        b = b.next!;
      }
      a = a.next!;
    } while (a != start);
  }

  static _EarcutNode _eliminateHoles(List<double> data, List<int> holeIndices, _EarcutNode outerNode, int dim) {
    final queue = <_EarcutNode>[];
    final len = holeIndices.length;

    for (int i = 0; i < len; i++) {
      final start = holeIndices[i] * dim;
      final end = i < len - 1 ? holeIndices[i + 1] * dim : data.length;
      final list = _createLinkedList(data, start, end, dim, false);
      if (list != null) {
        if (list == list.next) list.steiner = true;
        queue.add(_getLeftmost(list));
      }
    }

    queue.sort((a, b) => a.x.compareTo(b.x));

    var resultNode = outerNode;
    for (int i = 0; i < queue.length; i++) {
      resultNode = _eliminateHole(queue[i], resultNode);
    }

    return resultNode;
  }

  static _EarcutNode _eliminateHole(_EarcutNode hole, _EarcutNode outerNode) {
    final bridge = _findHoleBridge(hole, outerNode);
    if (bridge == null) return outerNode;

    final bridgeReverse = _splitPolygonNodes(bridge, hole);

    _filterPoints(bridgeReverse, bridgeReverse.next);
    return _filterPoints(bridge, bridge.next)!;
  }

  static _EarcutNode? _findHoleBridge(_EarcutNode hole, _EarcutNode outerNode) {
    var p = outerNode;
    final hx = hole.x;
    final hy = hole.y;
    var qx = -double.infinity;
    _EarcutNode? m;

    // Find a segment intersecting with ray (hx, hy) -> (+inf, hy)
    do {
      if (hy <= p.y && hy >= p.next!.y && p.next!.y != p.y) {
        final x = p.x + (hy - p.y) * (p.next!.x - p.x) / (p.next!.y - p.y);
        if (x <= hx && x > qx) {
          qx = x;
          m = p.x < p.next!.x ? p : p.next;
          if (x == hx) return m; // hole touches outer edge
        }
      }
      p = p.next!;
    } while (p != outerNode);

    if (m == null) return null;

    final stop = m;
    final mx = m.x;
    final my = m.y;
    var tanMin = double.infinity;

    p = m;

    do {
      if (hx >= p.x && p.x >= mx && hx != p.x &&
          _pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, p.x, p.y)) {
        final tan = (hy - p.y).abs() / (hx - p.x);

        if (_locallyInside(p, hole) &&
            (tan < tanMin || (tan == tanMin && (p.x > m!.x || (p.x == m.x && _sectorContainsSector(m, p)))))) {
          m = p;
          tanMin = tan;
        }
      }

      p = p.next!;
    } while (p != stop);

    return m;
  }

  static bool _sectorContainsSector(_EarcutNode m, _EarcutNode p) {
    return _area(m.prev!, m, p.prev!) < 0 && _area(p.next!, m, m.next!) < 0;
  }

  static void _indexCurve(_EarcutNode start, double minX, double minY, double invSize) {
    var p = start;
    do {
      p.z = _zOrder(p.x, p.y, minX, minY, invSize);
      p.prevZ = p.prev;
      p.nextZ = p.next;
      p = p.next!;
    } while (p != start);

    p.prevZ!.nextZ = null;
    p.prevZ = null;

    _sortLinked(p);
  }

  static _EarcutNode? _sortLinked(_EarcutNode? list) {
    var inSize = 1;

    int numMerges;
    do {
      var p = list;
      list = null;
      _EarcutNode? tail;
      numMerges = 0;

      while (p != null) {
        numMerges++;
        _EarcutNode? q = p;
        var pSize = 0;
        for (int i = 0; i < inSize; i++) {
          pSize++;
          q = q?.nextZ;
          if (q == null) break;
        }
        var qSize = inSize;

        while (pSize > 0 || (qSize > 0 && q != null)) {
          _EarcutNode? e;
          if (pSize == 0) {
            e = q;
            q = q?.nextZ;
            qSize--;
          } else if (qSize == 0 || q == null) {
            e = p;
            p = p?.nextZ;
            pSize--;
          } else if (p!.z <= q.z) {
            e = p;
            p = p.nextZ;
            pSize--;
          } else {
            e = q;
            q = q.nextZ;
            qSize--;
          }

          if (tail != null) {
            tail.nextZ = e;
          } else {
            list = e;
          }
          if (e != null) {
            e.prevZ = tail;
          }
          tail = e;
        }

        p = q;
      }

      tail!.nextZ = null;
      inSize *= 2;
    } while (numMerges > 1);

    return list;
  }

  static int _zOrder(double x, double y, double minX, double minY, double invSize) {
    var lx = ((x - minX) * invSize).toInt();
    var ly = ((y - minY) * invSize).toInt();

    lx = (lx | (lx << 8)) & 0x00FF00FF;
    lx = (lx | (lx << 4)) & 0x0F0F0F0F;
    lx = (lx | (lx << 2)) & 0x33333333;
    lx = (lx | (lx << 1)) & 0x55555555;

    ly = (ly | (ly << 8)) & 0x00FF00FF;
    ly = (ly | (ly << 4)) & 0x0F0F0F0F;
    ly = (ly | (ly << 2)) & 0x33333333;
    ly = (ly | (ly << 1)) & 0x55555555;

    return lx | (ly << 1);
  }

  static _EarcutNode _getLeftmost(_EarcutNode start) {
    var p = start;
    var leftmost = start;
    do {
      if (p.x < leftmost.x || (p.x == leftmost.x && p.y < leftmost.y)) leftmost = p;
      p = p.next!;
    } while (p != start);
    return leftmost;
  }

  static bool _pointInTriangle(double ax, double ay, double bx, double by, double cx, double cy, double px, double py) {
    return (cx - px) * (ay - py) >= (ax - px) * (cy - py) &&
           (ax - px) * (by - py) >= (bx - px) * (ay - py) &&
           (bx - px) * (cy - py) >= (cx - px) * (by - py);
  }

  static bool _isValidDiagonal(_EarcutNode a, _EarcutNode b) {
    return a.next!.i != b.i && a.prev!.i != b.i && !_intersectsPolygon(a, b) &&
           ((_locallyInside(a, b) && _locallyInside(b, a) && _middleInside(a, b) &&
             (_area(a.prev!, a, a.next!) != 0 || _area(b.prev!, b, b.next!) != 0)) ||
            (_equals(a, b) && _area(a.prev!, a, a.next!) > 0 && _area(b.prev!, b, b.next!) > 0));
  }

  static double _area(_EarcutNode p, _EarcutNode q, _EarcutNode r) {
    return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
  }

  static bool _equals(_EarcutNode p1, _EarcutNode p2) {
    return p1.x == p2.x && p1.y == p2.y;
  }

  static bool _intersects(_EarcutNode p1, _EarcutNode q1, _EarcutNode p2, _EarcutNode q2) {
    final o1 = _sign(_area(p1, q1, p2));
    final o2 = _sign(_area(p1, q1, q2));
    final o3 = _sign(_area(p2, q2, p1));
    final o4 = _sign(_area(p2, q2, q1));

    if (o1 != o2 && o3 != o4) return true;

    if (o1 == 0 && _onSegment(p1, p2, q1)) return true;
    if (o2 == 0 && _onSegment(p1, q2, q1)) return true;
    if (o3 == 0 && _onSegment(p2, p1, q2)) return true;
    if (o4 == 0 && _onSegment(p2, q1, q2)) return true;

    return false;
  }

  static bool _onSegment(_EarcutNode p, _EarcutNode q, _EarcutNode r) {
    return q.x <= math.max(p.x, r.x) && q.x >= math.min(p.x, r.x) &&
           q.y <= math.max(p.y, r.y) && q.y >= math.min(p.y, r.y);
  }

  static int _sign(double val) {
    return val > 0 ? 1 : (val < 0 ? -1 : 0);
  }

  static bool _intersectsPolygon(_EarcutNode a, _EarcutNode b) {
    var p = a;
    do {
      if (p.i != a.i && p.next!.i != a.i && p.i != b.i && p.next!.i != b.i &&
          _intersects(p, p.next!, a, b)) {
        return true;
      }
      p = p.next!;
    } while (p != a);

    return false;
  }

  static bool _locallyInside(_EarcutNode a, _EarcutNode b) {
    return _area(a.prev!, a, a.next!) < 0
        ? _area(a, b, a.next!) >= 0 && _area(a, a.prev!, b) >= 0
        : _area(a, b, a.prev!) < 0 || _area(a, a.next!, b) < 0;
  }

  static bool _middleInside(_EarcutNode a, _EarcutNode b) {
    var p = a;
    var inside = false;
    final px = (a.x + b.x) / 2;
    final py = (a.y + b.y) / 2;
    do {
      if (((p.y > py) != (p.next!.y > py)) && p.next!.y != p.y &&
          (px < (p.next!.x - p.x) * (py - p.y) / (p.next!.y - p.y) + p.x)) {
        inside = !inside;
      }
      p = p.next!;
    } while (p != a);

    return inside;
  }

  static _EarcutNode _splitPolygonNodes(_EarcutNode a, _EarcutNode b) {
    final a2 = _EarcutNode(a.i, a.x, a.y);
    final b2 = _EarcutNode(b.i, b.x, b.y);
    final an = a.next!;
    final bp = b.prev!;

    a.next = b;
    b.prev = a;

    a2.next = an;
    an.prev = a2;

    b2.next = a2;
    a2.prev = b2;

    bp.next = b2;
    b2.prev = bp;

    return b2;
  }

  static _EarcutNode _insertNode(int i, double x, double y, _EarcutNode? last) {
    final p = _EarcutNode(i, x, y);

    if (last == null) {
      p.prev = p;
      p.next = p;
    } else {
      p.next = last.next;
      p.prev = last;
      last.next!.prev = p;
      last.next = p;
    }
    return p;
  }

  static void _removeNode(_EarcutNode p) {
    p.next!.prev = p.prev;
    p.prev!.next = p.next;

    if (p.prevZ != null) p.prevZ!.nextZ = p.nextZ;
    if (p.nextZ != null) p.nextZ!.prevZ = p.prevZ;
  }

  static double _signedArea(List<double> data, int start, int end, int dim) {
    var sum = 0.0;
    int j = end - dim;
    for (int i = start; i < end; i += dim) {
      sum += (data[j] - data[i]) * (data[i + 1] + data[j + 1]);
      j = i;
    }
    return sum;
  }
}

class _EarcutNode {
  final int i;
  final double x;
  final double y;

  _EarcutNode? prev;
  _EarcutNode? next;

  int z = 0;
  _EarcutNode? prevZ;
  _EarcutNode? nextZ;

  bool steiner = false;

  _EarcutNode(this.i, this.x, this.y);
}
