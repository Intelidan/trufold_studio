// =============================================================================
// geometry_modify_engine.dart
//
// Industrial 2D CAD Geometry Modify Engine.
// Implements Step 4 (#17) of Phase 1 Specification:
// - Group A: Move, Copy, Rotate, Mirror, Delete
// - Group B: Trim, Extend, Break, Join
// - Group C: Offset, Fillet, Chamfer
// - Group D: Linear Pattern, Circular Pattern, Mirror Pattern
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/cad_geometry.dart';

/// Result of a corner fillet operation
class FilletResult {
  final CadLine2D trimmedLine1;
  final CadLine2D trimmedLine2;
  final CadArc2D filletArc;

  const FilletResult({
    required this.trimmedLine1,
    required this.trimmedLine2,
    required this.filletArc,
  });
}

/// Result of a corner chamfer operation
class ChamferResult {
  final CadLine2D trimmedLine1;
  final CadLine2D trimmedLine2;
  final CadLine2D chamferLine;

  const ChamferResult({
    required this.trimmedLine1,
    required this.trimmedLine2,
    required this.chamferLine,
  });
}

/// Industrial 2D CAD Geometry Modify Engine
class GeometryModifyEngine {
  // ---------------------------------------------------------------------------
  // GROUP A: Basic Transformations
  // ---------------------------------------------------------------------------

  /// Moves all specified entities by (dx, dy).
  static List<CadGeometry> move({
    required List<CadGeometry> entities,
    required double dx,
    required double dy,
  }) {
    return entities.map((e) => e.translate(dx, dy)).toList();
  }

  /// Copies all specified entities, offsets them by (dx, dy), and assigns new IDs.
  static List<CadGeometry> copy({
    required List<CadGeometry> entities,
    required double dx,
    required double dy,
    required String Function(String originalId) idGenerator,
  }) {
    final copies = <CadGeometry>[];
    for (final e in entities) {
      final moved = e.translate(dx, dy);
      final newId = idGenerator(e.id);
      copies.add(_reassignId(moved, newId));
    }
    return copies;
  }

  /// Rotates all entities around [center] by [angleRad].
  static List<CadGeometry> rotate({
    required List<CadGeometry> entities,
    required CadPoint2D center,
    required double angleRad,
  }) {
    return entities.map((e) => e.rotate(center, angleRad)).toList();
  }

  /// Mirrors all entities across mirror axis line (axisP1 -> axisP2).
  /// If [keepOriginal] is true, returns both original and mirrored entities with new IDs.
  static List<CadGeometry> mirror({
    required List<CadGeometry> entities,
    required CadPoint2D axisP1,
    required CadPoint2D axisP2,
    bool keepOriginal = false,
    String Function(String originalId)? idGenerator,
  }) {
    final mirrored = <CadGeometry>[];
    for (final e in entities) {
      final m = e.mirror(axisP1, axisP2);
      if (keepOriginal) {
        final newId = idGenerator != null ? idGenerator(e.id) : '${e.id}_mirrored';
        mirrored.add(_reassignId(m, newId));
      } else {
        mirrored.add(m);
      }
    }
    return keepOriginal ? [...entities, ...mirrored] : mirrored;
  }

  /// Deletes entities matching [targetIds].
  static List<CadGeometry> delete({
    required List<CadGeometry> entities,
    required Set<String> targetIds,
  }) {
    return entities.where((e) => !targetIds.contains(e.id)).toList();
  }

  // ---------------------------------------------------------------------------
  // GROUP B: Trim, Extend, Break, Join
  // ---------------------------------------------------------------------------

  /// Breaks a line into two subsegments at [breakPoint].
  /// Returns null if [breakPoint] does not lie on the line segment.
  static List<CadLine2D>? breakAtPoint({
    required CadLine2D subject,
    required CadPoint2D breakPoint,
    required String newId1,
    required String newId2,
    double tolerance = 0.5,
  }) {
    final proj = subject.projectPoint(breakPoint, clamped: true);
    if (breakPoint.distanceTo(proj) > tolerance) return null;
    if (proj.distanceTo(subject.p1) < 1e-3 || proj.distanceTo(subject.p2) < 1e-3) {
      return [subject]; // At endpoint, no split
    }

    return [
      subject.copyWith(id: newId1, p1: subject.p1, p2: proj),
      subject.copyWith(id: newId2, p1: proj, p2: subject.p2),
    ];
  }

  /// Breaks a line between two points [p1] and [p2], removing the segment between them.
  static List<CadLine2D> breakBetweenPoints({
    required CadLine2D subject,
    required CadPoint2D p1,
    required CadPoint2D p2,
    required String newId1,
    required String newId2,
  }) {
    final proj1 = subject.projectPoint(p1, clamped: true);
    final proj2 = subject.projectPoint(p2, clamped: true);

    final d1 = subject.p1.distanceTo(proj1);
    final d2 = subject.p1.distanceTo(proj2);

    final firstPt = d1 <= d2 ? proj1 : proj2;
    final secondPt = d1 <= d2 ? proj2 : proj1;

    final result = <CadLine2D>[];
    if (subject.p1.distanceTo(firstPt) > 1e-3) {
      result.add(subject.copyWith(id: newId1, p1: subject.p1, p2: firstPt));
    }
    if (subject.p2.distanceTo(secondPt) > 1e-3) {
      result.add(subject.copyWith(id: newId2, p1: secondPt, p2: subject.p2));
    }
    return result;
  }

  /// Trims [subject] against cutting [boundaries].
  /// Finds all intersections, splits [subject] into segments, and removes the segment
  /// containing or closest to [pickPoint].
  static List<CadLine2D> trimLine({
    required CadLine2D subject,
    required List<CadGeometry> boundaries,
    required CadPoint2D pickPoint,
    required String Function(int index) idGenerator,
  }) {
    final intersections = <CadPoint2D>[];

    for (final b in boundaries) {
      if (b.id == subject.id) continue;
      if (b is CadLine2D) {
        final ix = subject.intersectWith(b, segmentOnly: true);
        if (ix != null) intersections.add(ix);
      } else if (b is CadPolyline2D) {
        for (final seg in b.toSegments()) {
          final ix = subject.intersectWith(seg, segmentOnly: true);
          if (ix != null) intersections.add(ix);
        }
      } else if (b is CadCircle2D) {
        final ixs = _intersectLineCircle(subject, b);
        intersections.addAll(ixs);
      }
    }

    if (intersections.isEmpty) {
      return [subject]; // No boundary intersections
    }

    // Sort intersection points along subject line from p1 to p2
    intersections.sort((a, b) =>
        subject.p1.distanceTo(a).compareTo(subject.p1.distanceTo(b)));

    // Remove duplicates within 1e-3
    final uniqueIxs = <CadPoint2D>[];
    for (final ix in intersections) {
      if (uniqueIxs.isEmpty || uniqueIxs.last.distanceTo(ix) > 1e-3) {
        uniqueIxs.add(ix);
      }
    }

    // Form segments: p1 -> ix0, ix0 -> ix1, ..., ixN -> p2
    final chainPoints = [subject.p1, ...uniqueIxs, subject.p2];
    final subsegments = <CadLine2D>[];

    for (int i = 0; i < chainPoints.length - 1; i++) {
      final a = chainPoints[i];
      final b = chainPoints[i + 1];
      if (a.distanceTo(b) > 1e-3) {
        subsegments.add(subject.copyWith(
          id: idGenerator(i),
          p1: a,
          p2: b,
        ));
      }
    }

    if (subsegments.length <= 1) return subsegments;

    // Find the subsegment closest to pickPoint and remove it (the trimmed segment)
    int closestIdx = 0;
    double closestDist = double.infinity;

    for (int i = 0; i < subsegments.length; i++) {
      final d = subsegments[i].distanceToPoint(pickPoint);
      if (d < closestDist) {
        closestDist = d;
        closestIdx = i;
      }
    }

    final remaining = <CadLine2D>[];
    for (int i = 0; i < subsegments.length; i++) {
      if (i != closestIdx) {
        remaining.add(subsegments[i]);
      }
    }
    return remaining;
  }

  /// Extends [subject] line segment towards the nearest boundary in [boundaries].
  /// If [extendStart] is true, extends from p1 backwards. Otherwise extends from p2 forward.
  static CadLine2D? extendLine({
    required CadLine2D subject,
    required List<CadGeometry> boundaries,
    required bool extendStart,
    double maxDistance = 2000.0,
  }) {
    final origin = extendStart ? subject.p1 : subject.p2;
    final dir = extendStart
        ? (subject.p1 - subject.p2)
        : (subject.p2 - subject.p1);
    final len = dir.length;
    if (len < 1e-6) return null;
    final udir = CadPoint2D(dir.x / len, dir.y / len);

    final testRayEnd = origin + udir * maxDistance;
    final ray = CadLine2D(id: 'ray', p1: origin, p2: testRayEnd);

    CadPoint2D? closestIx;
    double closestDist = double.infinity;

    for (final b in boundaries) {
      if (b.id == subject.id) continue;
      if (b is CadLine2D) {
        final ix = ray.intersectWith(b, segmentOnly: true);
        if (ix != null && ix.distanceTo(origin) > 1e-3) {
          final d = origin.distanceTo(ix);
          if (d < closestDist) {
            closestDist = d;
            closestIx = ix;
          }
        }
      } else if (b is CadPolyline2D) {
        for (final seg in b.toSegments()) {
          final ix = ray.intersectWith(seg, segmentOnly: true);
          if (ix != null && ix.distanceTo(origin) > 1e-3) {
            final d = origin.distanceTo(ix);
            if (d < closestDist) {
              closestDist = d;
              closestIx = ix;
            }
          }
        }
      }
    }

    if (closestIx == null) return null;

    if (extendStart) {
      return subject.copyWith(p1: closestIx);
    } else {
      return subject.copyWith(p2: closestIx);
    }
  }

  /// Joins a set of connecting or collinear lines.
  /// If all lines form a continuous chain, returns a `CadPolyline2D`.
  /// If two lines are collinear, merges them into a single `CadLine2D`.
  static List<CadGeometry> joinLines({
    required List<CadLine2D> lines,
    required String newId,
    double tolerance = 0.1,
  }) {
    if (lines.isEmpty) return const [];
    if (lines.length == 1) return lines;

    // Check if exactly two collinear lines
    if (lines.length == 2) {
      final l1 = lines[0];
      final l2 = lines[1];
      // Check collinearity
      final angleDiff = (l1.angleRad - l2.angleRad).abs() % math.pi;
      final isCollinear = angleDiff < 1e-3 || (math.pi - angleDiff) < 1e-3;

      if (isCollinear) {
        // Find connecting endpoints
        if (l1.p2.distanceTo(l2.p1) <= tolerance) {
          return [l1.copyWith(id: newId, p2: l2.p2)];
        } else if (l1.p2.distanceTo(l2.p2) <= tolerance) {
          return [l1.copyWith(id: newId, p2: l2.p1)];
        } else if (l1.p1.distanceTo(l2.p1) <= tolerance) {
          return [l1.copyWith(id: newId, p1: l2.p2)];
        } else if (l1.p1.distanceTo(l2.p2) <= tolerance) {
          return [l1.copyWith(id: newId, p1: l2.p1)];
        }
      }
    }

    // Attempt chaining into a continuous polyline
    final remaining = List<CadLine2D>.from(lines);
    final chain = <CadPoint2D>[remaining.first.p1, remaining.first.p2];
    remaining.removeAt(0);

    bool joinedAny = true;
    while (remaining.isNotEmpty && joinedAny) {
      joinedAny = false;
      for (int i = 0; i < remaining.length; i++) {
        final seg = remaining[i];
        if (seg.p1.distanceTo(chain.last) <= tolerance) {
          chain.add(seg.p2);
          remaining.removeAt(i);
          joinedAny = true;
          break;
        } else if (seg.p2.distanceTo(chain.last) <= tolerance) {
          chain.add(seg.p1);
          remaining.removeAt(i);
          joinedAny = true;
          break;
        } else if (seg.p2.distanceTo(chain.first) <= tolerance) {
          chain.insert(0, seg.p1);
          remaining.removeAt(i);
          joinedAny = true;
          break;
        } else if (seg.p1.distanceTo(chain.first) <= tolerance) {
          chain.insert(0, seg.p2);
          remaining.removeAt(i);
          joinedAny = true;
          break;
        }
      }
    }

    final isClosed = chain.length > 2 && chain.first.distanceTo(chain.last) <= tolerance;
    final poly = CadPolyline2D(
      id: newId,
      vertices: chain,
      isClosed: isClosed,
      layer: lines.first.layer,
      isConstruction: lines.first.isConstruction,
    );

    return [poly, ...remaining];
  }

  // ---------------------------------------------------------------------------
  // GROUP C: Offset, Fillet, Chamfer
  // ---------------------------------------------------------------------------

  /// Creates a parallel offset of [line] by [distance].
  static CadLine2D offsetLine({
    required CadLine2D line,
    required double distance,
    required String newId,
    bool sidePositive = true,
  }) {
    return line.offset(distance, sidePositive: sidePositive).copyWith(id: newId);
  }

  /// Offsets a closed 2D polygon outward (positive distance) or inward (negative distance).
  static List<CadPoint2D> offsetPolygon({
    required List<CadPoint2D> polygon,
    required double distance,
  }) {
    final n = polygon.length;
    if (n < 3) return polygon;

    // Determine winding order (positive = CCW)
    double area2 = 0.0;
    for (int i = 0; i < n; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % n];
      area2 += (p2.x - p1.x) * (p2.y + p1.y);
    }
    final isCcw = area2 < 0;

    // Offset each edge outward by distance
    final offsetEdges = <CadLine2D>[];
    for (int i = 0; i < n; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % n];
      final edge = CadLine2D(id: 'e$i', p1: p1, p2: p2);
      // If CCW, outward offset is right normal (!isCcw)
      offsetEdges.add(edge.offset(distance, sidePositive: !isCcw));
    }

    // Intersect consecutive offset edges to find new vertices corresponding to polygon[i]
    final newVertices = <CadPoint2D>[];
    for (int i = 0; i < n; i++) {
      final prevEdge = offsetEdges[(i - 1 + n) % n];
      final currEdge = offsetEdges[i];
      final ix = prevEdge.intersectWith(currEdge, segmentOnly: false);
      if (ix != null) {
        newVertices.add(ix);
      } else {
        newVertices.add(currEdge.p1);
      }
    }
    return newVertices;
  }

  /// Computes a corner fillet between two intersecting lines [line1] and [line2] with [radius].
  /// Shortens both lines to the tangent points and returns a tangent arc.
  static FilletResult? filletCorner({
    required CadLine2D line1,
    required CadLine2D line2,
    required double radius,
    required String filletArcId,
  }) {
    if (radius <= 0) return null;

    // Find intersection vertex V of infinite lines
    final v = line1.intersectWith(line2, segmentOnly: false);
    if (v == null) return null; // Parallel lines

    // Determine vectors pointing away from vertex V along line1 and line2
    final farPt1 = line1.p1.distanceTo(v) > line1.p2.distanceTo(v) ? line1.p1 : line1.p2;
    final farPt2 = line2.p1.distanceTo(v) > line2.p2.distanceTo(v) ? line2.p1 : line2.p2;

    final d1 = farPt1 - v;
    final d2 = farPt2 - v;
    final len1 = d1.length;
    final len2 = d2.length;
    if (len1 < 1e-6 || len2 < 1e-6) return null;

    final u1 = CadPoint2D(d1.x / len1, d1.y / len1);
    final u2 = CadPoint2D(d2.x / len2, d2.y / len2);

    // Interior angle between lines
    final dot = (u1.x * u2.x + u1.y * u2.y).clamp(-1.0, 1.0);
    final theta = math.acos(dot);
    if (theta < 1e-3 || (math.pi - theta) < 1e-3) return null;

    // Tangent distance from vertex V
    final halfTheta = theta / 2.0;
    final tDist = radius / math.tan(halfTheta);

    if (tDist > len1 || tDist > len2) {
      // Radius too large for segment lengths
      return null;
    }

    // Tangent points
    final t1 = v + u1 * tDist;
    final t2 = v + u2 * tDist;

    // Arc center C along bisector
    final bisector = CadPoint2D(u1.x + u2.x, u1.y + u2.y);
    final bLen = bisector.length;
    if (bLen < 1e-6) return null;
    final ub = CadPoint2D(bisector.x / bLen, bisector.y / bLen);
    final cDist = radius / math.sin(halfTheta);
    final center = v + ub * cDist;

    // Construct fillet arc
    final a1 = math.atan2(t1.y - center.y, t1.x - center.x);
    final a2 = math.atan2(t2.y - center.y, t2.x - center.x);

    var sweep = (a2 - a1) % (2.0 * math.pi);
    // Check orientation relative to vertex
    final midAngle = a1 + sweep / 2.0;
    final arcMid = CadPoint2D(
      center.x + radius * math.cos(midAngle),
      center.y + radius * math.sin(midAngle),
    );
    if (arcMid.distanceTo(v) > center.distanceTo(v)) {
      // Wrong arc side, flip sweep
      sweep = sweep - 2.0 * math.pi;
    }

    final arc = CadArc2D(
      id: filletArcId,
      center: center,
      radius: radius,
      startAngleRad: a1,
      sweepAngleRad: sweep,
      layer: line1.layer,
      isConstruction: line1.isConstruction,
    );

    // Trimmed lines: keep farPt to tangent point
    final trimmed1 = line1.copyWith(
      p1: farPt1,
      p2: t1,
    );
    final trimmed2 = line2.copyWith(
      p1: farPt2,
      p2: t2,
    );

    return FilletResult(
      trimmedLine1: trimmed1,
      trimmedLine2: trimmed2,
      filletArc: arc,
    );
  }

  /// Computes a corner chamfer between two intersecting lines [line1] and [line2].
  static ChamferResult? chamferCorner({
    required CadLine2D line1,
    required CadLine2D line2,
    required double dist1,
    required double dist2,
    required String chamferLineId,
  }) {
    if (dist1 <= 0 || dist2 <= 0) return null;

    final v = line1.intersectWith(line2, segmentOnly: false);
    if (v == null) return null;

    final farPt1 = line1.p1.distanceTo(v) > line1.p2.distanceTo(v) ? line1.p1 : line1.p2;
    final farPt2 = line2.p1.distanceTo(v) > line2.p2.distanceTo(v) ? line2.p1 : line2.p2;

    final d1 = farPt1 - v;
    final d2 = farPt2 - v;
    final len1 = d1.length;
    final len2 = d2.length;
    if (len1 < dist1 || len2 < dist2) return null;

    final u1 = CadPoint2D(d1.x / len1, d1.y / len1);
    final u2 = CadPoint2D(d2.x / len2, d2.y / len2);

    final cp1 = v + u1 * dist1;
    final cp2 = v + u2 * dist2;

    final chamfer = CadLine2D(
      id: chamferLineId,
      p1: cp1,
      p2: cp2,
      layer: line1.layer,
      isConstruction: line1.isConstruction,
    );

    final trimmed1 = line1.copyWith(p1: farPt1, p2: cp1);
    final trimmed2 = line2.copyWith(p1: farPt2, p2: cp2);

    return ChamferResult(
      trimmedLine1: trimmed1,
      trimmedLine2: trimmed2,
      chamferLine: chamfer,
    );
  }

  // ---------------------------------------------------------------------------
  // GROUP D: Patterns
  // ---------------------------------------------------------------------------

  /// Generates a 2D rectangular / linear array pattern of [entities].
  static List<CadGeometry> linearPattern({
    required List<CadGeometry> entities,
    required int countX,
    required int countY,
    required double pitchX,
    required double pitchY,
    double angleDeg = 0.0,
    required String Function(String baseId, int col, int row) idGenerator,
  }) {
    final result = <CadGeometry>[];
    final rad = angleDeg * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);

    for (int row = 0; row < countY; row++) {
      for (int col = 0; col < countX; col++) {
        // Base coordinate in grid
        final gx = col * pitchX;
        final gy = row * pitchY;
        // Rotated offset
        final dx = gx * cosA - gy * sinA;
        final dy = gx * sinA + gy * cosA;

        for (final e in entities) {
          final moved = e.translate(dx, dy);
          final newId = idGenerator(e.id, col, row);
          result.add(_reassignId(moved, newId));
        }
      }
    }
    return result;
  }

  /// Generates a circular polar array pattern of [entities] around [center].
  static List<CadGeometry> circularPattern({
    required List<CadGeometry> entities,
    required CadPoint2D center,
    required int count,
    required double totalAngleDeg,
    bool rotateEntities = true,
    required String Function(String baseId, int index) idGenerator,
  }) {
    if (count <= 0) return const [];
    final result = <CadGeometry>[];
    final stepAngleRad = (totalAngleDeg / count) * math.pi / 180.0;

    for (int i = 0; i < count; i++) {
      final angle = i * stepAngleRad;
      for (final e in entities) {
        CadGeometry transformed;
        if (rotateEntities) {
          transformed = e.rotate(center, angle);
        } else {
          // Translate only (revolving without local rotation)
          final eCenter = e.boundingBox.center;
          final rotatedCenter = CadTransformMath.rotatePoint(eCenter, center, angle);
          final dx = rotatedCenter.x - eCenter.x;
          final dy = rotatedCenter.y - eCenter.y;
          transformed = e.translate(dx, dy);
        }
        final newId = idGenerator(e.id, i);
        result.add(_reassignId(transformed, newId));
      }
    }
    return result;
  }

  /// Generates a mirrored pattern array across axis line.
  static List<CadGeometry> mirrorPattern({
    required List<CadGeometry> entities,
    required CadPoint2D axisP1,
    required CadPoint2D axisP2,
    required String Function(String baseId) idGenerator,
  }) {
    return mirror(
      entities: entities,
      axisP1: axisP1,
      axisP2: axisP2,
      keepOriginal: true,
      idGenerator: idGenerator,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  static CadGeometry _reassignId(CadGeometry geom, String newId) {
    if (geom is CadPointEntity2D) return geom.copyWith(id: newId);
    if (geom is CadLine2D) return geom.copyWith(id: newId);
    if (geom is CadPolyline2D) return geom.copyWith(id: newId);
    if (geom is CadArc2D) return geom.copyWith(id: newId);
    if (geom is CadCircle2D) return geom.copyWith(id: newId);
    if (geom is CadEllipse2D) return geom.copyWith(id: newId);
    if (geom is CadRectangle2D) return geom.copyWith(id: newId);
    if (geom is CadSlot2D) return geom.copyWith(id: newId);
    return geom;
  }

  static List<CadPoint2D> _intersectLineCircle(CadLine2D line, CadCircle2D circle) {
    final d = line.p2 - line.p1;
    final f = line.p1 - circle.center;

    final a = d.x * d.x + d.y * d.y;
    final b = 2.0 * (f.x * d.x + f.y * d.y);
    final c = f.x * f.x + f.y * f.y - circle.radius * circle.radius;

    final disc = b * b - 4.0 * a * c;
    if (disc < 0 || a.abs() < 1e-9) return const [];

    final ixs = <CadPoint2D>[];
    final sqrtDisc = math.sqrt(disc);
    final t1 = (-b - sqrtDisc) / (2.0 * a);
    final t2 = (-b + sqrtDisc) / (2.0 * a);

    if (t1 >= -1e-4 && t1 <= 1.0001) {
      ixs.add(CadPoint2D(line.p1.x + t1 * d.x, line.p1.y + t1 * d.y));
    }
    if (t2 >= -1e-4 && t2 <= 1.0001 && (t2 - t1).abs() > 1e-4) {
      ixs.add(CadPoint2D(line.p1.x + t2 * d.x, line.p1.y + t2 * d.y));
    }
    return ixs;
  }
}
