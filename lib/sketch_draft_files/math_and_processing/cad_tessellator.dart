// Triangulates arbitrary non-convex or convex polygons via ear-clipping logic to generate render faces.

import 'dart:typed_data';

import 'package:flutter/material.dart';

class CADTessellator {
  static Uint16List tessellatePolygon(List<Offset> vertices) {
    List<Offset> poly = List.from(vertices);
    if (poly.length > 2 && (poly.first - poly.last).distance < 0.001) poly.removeLast();
    if (poly.length < 3) return Uint16List(0);

    List<int> pool = List.generate(poly.length, (i) => i);
    List<int> res = [];
    int vCount = poly.length;
    int timeout = 2 * vCount;

    while (vCount > 2 && timeout-- > 0) {
      bool earFound = false;
      for (int i = 0; i < vCount; i++) {
        int prev = pool[(i - 1 + vCount) % vCount];
        int curr = pool[i];
        int next = pool[(i + 1) % vCount];
        if (_isEar(poly[prev], poly[curr], poly[next], poly, pool)) {
          res.addAll([prev, curr, next]);
          pool.removeAt(i);
          vCount--;
          earFound = true;
          break;
        }
      }
      if (!earFound) break;
    }
    return Uint16List.fromList(res);
  }

  static bool _isEar(Offset p1, Offset p2, Offset p3, List<Offset> poly, List<int> pool) {
    if (((p2.dx - p1.dx) * (p3.dy - p1.dy) - (p2.dy - p1.dy) * (p3.dx - p1.dx)) <= 0) return false;
    for (int idx in pool) {
      Offset pt = poly[idx];
      if (pt == p1 || pt == p2 || pt == p3) continue;
      if (_inTriangle(pt, p1, p2, p3)) return false;
    }
    return true;
  }

  static bool _inTriangle(Offset p, Offset a, Offset b, Offset c) {
    double d1 = _sign(p, a, b);
    double d2 = _sign(p, b, c);
    double d3 = _sign(p, c, a);
    return !(((d1 < 0) || (d2 < 0) || (d3 < 0)) && ((d1 > 0) || (d2 > 0) || (d3 > 0)));
  }

  static double _sign(Offset p1, Offset p2, Offset p3) => (p1.dx - p3.dx) * (p2.dy - p3.dy) - (p2.dx - p3.dx) * (p1.dy - p3.dy);
}
