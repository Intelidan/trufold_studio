// =============================================================================
// cad_geometry.dart
//
// Standalone, semantic 2D CAD Geometry entities with stable unique IDs.
// Provides Point, Line, Polyline, Arc, Circle, Ellipse, Rectangle, and
// Obround Slot primitives with industrial transformation mathematics.
// =============================================================================

import 'dart:math' as math;

import 'cad_primitives.dart';

/// 2D Axis-Aligned Bounding Box in mm
class CadBoundingBox2D {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const CadBoundingBox2D({required this.minX, required this.minY, required this.maxX, required this.maxY});

  double get width => maxX - minX;
  double get height => maxY - minY;
  CadPoint2D get center => CadPoint2D((minX + maxX) / 2.0, (minY + maxY) / 2.0);

  bool contains(CadPoint2D p) => p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY;

  bool intersects(CadBoundingBox2D other) => !(other.minX > maxX || other.maxX < minX || other.minY > maxY || other.maxY < minY);

  CadBoundingBox2D expand(CadBoundingBox2D other) {
    return CadBoundingBox2D(
      minX: math.min(minX, other.minX),
      minY: math.min(minY, other.minY),
      maxX: math.max(maxX, other.maxX),
      maxY: math.max(maxY, other.maxY),
    );
  }

  factory CadBoundingBox2D.fromPoints(Iterable<CadPoint2D> points) {
    if (points.isEmpty) {
      return const CadBoundingBox2D(minX: 0, minY: 0, maxX: 0, maxY: 0);
    }
    double minX = points.first.x;
    double minY = points.first.y;
    double maxX = points.first.x;
    double maxY = points.first.y;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return CadBoundingBox2D(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}

/// Helper math routines for 2D geometry transformations
class CadTransformMath {
  static CadPoint2D rotatePoint(CadPoint2D pt, CadPoint2D origin, double angleRad) {
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final dx = pt.x - origin.x;
    final dy = pt.y - origin.y;
    return CadPoint2D(origin.x + dx * cosA - dy * sinA, origin.y + dx * sinA + dy * cosA);
  }

  static CadPoint2D mirrorPoint(CadPoint2D pt, CadPoint2D axisP1, CadPoint2D axisP2) {
    final dx = axisP2.x - axisP1.x;
    final dy = axisP2.y - axisP1.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return pt;

    // Vector from axisP1 to pt
    final wx = pt.x - axisP1.x;
    final wy = pt.y - axisP1.y;

    // Dot product with axis direction vector
    final dot = (wx * dx + wy * dy) / lenSq;

    // Projection of pt onto mirror axis
    final projX = axisP1.x + dot * dx;
    final projY = axisP1.y + dot * dy;

    // Mirrored point is P' = 2*Proj - Pt
    return CadPoint2D(2.0 * projX - pt.x, 2.0 * projY - pt.y);
  }

  static CadPoint2D scalePoint(CadPoint2D pt, CadPoint2D origin, double factorX, double factorY) {
    return CadPoint2D(origin.x + (pt.x - origin.x) * factorX, origin.y + (pt.y - origin.y) * factorY);
  }
}

/// Base class for all 2D persistent CAD geometry
abstract class CadGeometry {
  final String id;
  final String layer;
  final bool isVisible;
  final bool isConstruction;

  const CadGeometry({required this.id, this.layer = '0', this.isVisible = true, this.isConstruction = false});

  CadGeometry translate(double dx, double dy);
  CadGeometry rotate(CadPoint2D origin, double angleRad);
  CadGeometry mirror(CadPoint2D axisP1, CadPoint2D axisP2);
  CadGeometry scale(CadPoint2D origin, double factorX, double factorY);
  CadBoundingBox2D get boundingBox;

  Map<String, dynamic> toJson();

  static CadGeometry fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'point':
        return CadPointEntity2D.fromJson(json);
      case 'line':
        return CadLine2D.fromJson(json);
      case 'polyline':
        return CadPolyline2D.fromJson(json);
      case 'arc':
        return CadArc2D.fromJson(json);
      case 'circle':
        return CadCircle2D.fromJson(json);
      case 'ellipse':
        return CadEllipse2D.fromJson(json);
      case 'rectangle':
        return CadRectangle2D.fromJson(json);
      case 'slot':
        return CadSlot2D.fromJson(json);
      default:
        throw ArgumentError('Unknown CadGeometry type: $type');
    }
  }
}

/// Standalone 2D Point Entity
class CadPointEntity2D extends CadGeometry {
  final CadPoint2D point;

  const CadPointEntity2D({required super.id, required this.point, super.layer, super.isVisible, super.isConstruction});

  @override
  CadPointEntity2D translate(double dx, double dy) => copyWith(point: CadPoint2D(point.x + dx, point.y + dy));

  @override
  CadPointEntity2D rotate(CadPoint2D origin, double angleRad) => copyWith(point: CadTransformMath.rotatePoint(point, origin, angleRad));

  @override
  CadPointEntity2D mirror(CadPoint2D axisP1, CadPoint2D axisP2) => copyWith(point: CadTransformMath.mirrorPoint(point, axisP1, axisP2));

  @override
  CadPointEntity2D scale(CadPoint2D origin, double factorX, double factorY) => copyWith(point: CadTransformMath.scalePoint(point, origin, factorX, factorY));

  @override
  CadBoundingBox2D get boundingBox => CadBoundingBox2D(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y);

  CadPointEntity2D copyWith({String? id, CadPoint2D? point, String? layer, bool? isVisible, bool? isConstruction}) {
    return CadPointEntity2D(
      id: id ?? this.id,
      point: point ?? this.point,
      layer: layer ?? this.layer,
      isVisible: isVisible ?? this.isVisible,
      isConstruction: isConstruction ?? this.isConstruction,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'point',
    'id': id,
    'layer': layer,
    'isVisible': isVisible,
    'isConstruction': isConstruction,
    'point': point.toJson(),
  };

  factory CadPointEntity2D.fromJson(Map<String, dynamic> json) => CadPointEntity2D(
    id: json['id'] as String,
    point: CadPoint2D.fromJson(json['point'] as Map<String, dynamic>),
    layer: json['layer'] as String? ?? '0',
    isVisible: json['isVisible'] as bool? ?? true,
    isConstruction: json['isConstruction'] as bool? ?? false,
  );
}

/// 2D Line Segment
class CadLine2D extends CadGeometry {
  final CadPoint2D p1;
  final CadPoint2D p2;

  const CadLine2D({required super.id, required this.p1, required this.p2, super.layer, super.isVisible, super.isConstruction});

  double get length => p1.distanceTo(p2);
  double get angleRad => math.atan2(p2.y - p1.y, p2.x - p1.x);
  double get angleDeg => angleRad * 180.0 / math.pi;

  CadPoint2D get midpoint => CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);

  @override
  CadLine2D translate(double dx, double dy) => copyWith(p1: CadPoint2D(p1.x + dx, p1.y + dy), p2: CadPoint2D(p2.x + dx, p2.y + dy));

  @override
  CadLine2D rotate(CadPoint2D origin, double angleRad) =>
      copyWith(p1: CadTransformMath.rotatePoint(p1, origin, angleRad), p2: CadTransformMath.rotatePoint(p2, origin, angleRad));

  @override
  CadLine2D mirror(CadPoint2D axisP1, CadPoint2D axisP2) =>
      copyWith(p1: CadTransformMath.mirrorPoint(p1, axisP1, axisP2), p2: CadTransformMath.mirrorPoint(p2, axisP1, axisP2));

  @override
  CadLine2D scale(CadPoint2D origin, double factorX, double factorY) =>
      copyWith(p1: CadTransformMath.scalePoint(p1, origin, factorX, factorY), p2: CadTransformMath.scalePoint(p2, origin, factorX, factorY));

  @override
  CadBoundingBox2D get boundingBox => CadBoundingBox2D.fromPoints([p1, p2]);

  /// Generates a parallel offset line at specified distance.
  CadLine2D offset(double distance, {bool sidePositive = true}) {
    final len = length;
    if (len < 1e-6) return copyWith();
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    // Perpendicular normal (-dy, dx)
    final nx = -dy / len;
    final ny = dx / len;
    final factor = sidePositive ? distance : -distance;
    final off = CadPoint2D(nx * factor, ny * factor);
    return copyWith(p1: p1 + off, p2: p2 + off);
  }

  /// Finds intersection point with another 2D line segment or infinite line
  CadPoint2D? intersectWith(CadLine2D other, {bool segmentOnly = true}) {
    final x1 = p1.x, y1 = p1.y;
    final x2 = p2.x, y2 = p2.y;
    final x3 = other.p1.x, y3 = other.p1.y;
    final x4 = other.p2.x, y4 = other.p2.y;

    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-9) return null; // Parallel or collinear

    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    final u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / denom;

    if (segmentOnly && (t < -1e-4 || t > 1.0001 || u < -1e-4 || u > 1.0001)) {
      return null;
    }

    return CadPoint2D(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
  }

  /// Projects a point onto the line segment (clamped to segment bounds if clamped is true)
  CadPoint2D projectPoint(CadPoint2D pt, {bool clamped = true}) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return p1;

    double t = ((pt.x - p1.x) * dx + (pt.y - p1.y) * dy) / lenSq;
    if (clamped) {
      t = t.clamp(0.0, 1.0);
    }
    return CadPoint2D(p1.x + t * dx, p1.y + t * dy);
  }

  /// Distance from a point to this line segment
  double distanceToPoint(CadPoint2D pt) {
    final proj = projectPoint(pt, clamped: true);
    return pt.distanceTo(proj);
  }

  CadLine2D copyWith({String? id, CadPoint2D? p1, CadPoint2D? p2, String? layer, bool? isVisible, bool? isConstruction}) {
    return CadLine2D(
      id: id ?? this.id,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      layer: layer ?? this.layer,
      isVisible: isVisible ?? this.isVisible,
      isConstruction: isConstruction ?? this.isConstruction,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'line',
    'id': id,
    'layer': layer,
    'isVisible': isVisible,
    'isConstruction': isConstruction,
    'p1': p1.toJson(),
    'p2': p2.toJson(),
  };

  factory CadLine2D.fromJson(Map<String, dynamic> json) => CadLine2D(
    id: json['id'] as String,
    p1: CadPoint2D.fromJson(json['p1'] as Map<String, dynamic>),
    p2: CadPoint2D.fromJson(json['p2'] as Map<String, dynamic>),
    layer: json['layer'] as String? ?? '0',
    isVisible: json['isVisible'] as bool? ?? true,
    isConstruction: json['isConstruction'] as bool? ?? false,
  );
}

/// 2D Polyline (Sequence of vertices)
class CadPolyline2D extends CadGeometry {
  final List<CadPoint2D> vertices;
  final bool isClosed;

  const CadPolyline2D({required super.id, required this.vertices, this.isClosed = false, super.layer, super.isVisible, super.isConstruction});

  double get totalLength {
    if (vertices.length < 2) return 0.0;
    double len = 0.0;
    for (int i = 0; i < vertices.length - 1; i++) {
      len += vertices[i].distanceTo(vertices[i + 1]);
    }
    if (isClosed && vertices.length > 2) {
      len += vertices.last.distanceTo(vertices.first);
    }
    return len;
  }

  List<CadLine2D> toSegments() {
    if (vertices.length < 2) return const [];
    final segs = <CadLine2D>[];
    for (int i = 0; i < vertices.length - 1; i++) {
      segs.add(CadLine2D(id: '${id}_seg_$i', p1: vertices[i], p2: vertices[i + 1], layer: layer, isVisible: isVisible, isConstruction: isConstruction));
    }
    if (isClosed && vertices.length > 2) {
      segs.add(CadLine2D(id: '${id}_seg_close', p1: vertices.last, p2: vertices.first, layer: layer, isVisible: isVisible, isConstruction: isConstruction));
    }
    return segs;
  }

  @override
  CadPolyline2D translate(double dx, double dy) => copyWith(vertices: vertices.map((v) => CadPoint2D(v.x + dx, v.y + dy)).toList());

  @override
  CadPolyline2D rotate(CadPoint2D origin, double angleRad) =>
      copyWith(vertices: vertices.map((v) => CadTransformMath.rotatePoint(v, origin, angleRad)).toList());

  @override
  CadPolyline2D mirror(CadPoint2D axisP1, CadPoint2D axisP2) =>
      copyWith(vertices: vertices.map((v) => CadTransformMath.mirrorPoint(v, axisP1, axisP2)).toList());

  @override
  CadPolyline2D scale(CadPoint2D origin, double factorX, double factorY) =>
      copyWith(vertices: vertices.map((v) => CadTransformMath.scalePoint(v, origin, factorX, factorY)).toList());

  @override
  CadBoundingBox2D get boundingBox => CadBoundingBox2D.fromPoints(vertices);

  CadPolyline2D copyWith({String? id, List<CadPoint2D>? vertices, bool? isClosed, String? layer, bool? isVisible, bool? isConstruction}) {
    return CadPolyline2D(
      id: id ?? this.id,
      vertices: vertices ?? this.vertices,
      isClosed: isClosed ?? this.isClosed,
      layer: layer ?? this.layer,
      isVisible: isVisible ?? this.isVisible,
      isConstruction: isConstruction ?? this.isConstruction,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'polyline',
    'id': id,
    'layer': layer,
    'isVisible': isVisible,
    'isConstruction': isConstruction,
    'vertices': vertices.map((v) => v.toJson()).toList(),
    'isClosed': isClosed,
  };

  factory CadPolyline2D.fromJson(Map<String, dynamic> json) => CadPolyline2D(
    id: json['id'] as String,
    vertices: (json['vertices'] as List<dynamic>).map((v) => CadPoint2D.fromJson(v as Map<String, dynamic>)).toList(),
    isClosed: json['isClosed'] as bool? ?? false,
    layer: json['layer'] as String? ?? '0',
    isVisible: json['isVisible'] as bool? ?? true,
    isConstruction: json['isConstruction'] as bool? ?? false,
  );
}

/// 2D Circular Arc
class CadArc2D extends CadGeometry {
  final CadPoint2D center;
  final double radius;
  final double startAngleRad;
  final double sweepAngleRad;
  final bool isBoundary;

  CadArc2D({
    required super.id,
    required this.center,
    required this.radius,
    double? startAngleRad,
    double? sweepAngleRad,
    double? startAngleDeg,
    double? endAngleDeg,
    CadPoint2D? startPoint,
    CadPoint2D? endPoint,
    bool isClockwise = false,
    this.isBoundary = true,
    super.layer,
    super.isVisible,
    super.isConstruction,
  }) : startAngleRad = startAngleRad ?? ((startAngleDeg ?? 0.0) * math.pi / 180.0),
       sweepAngleRad = sweepAngleRad ?? _calcSweepRad(startAngleDeg, endAngleDeg, isClockwise);

  static double _calcSweepRad(double? startDeg, double? endDeg, bool isClockwise) {
    if (startDeg == null || endDeg == null) return math.pi;
    double sweepDeg;
    if (isClockwise) {
      sweepDeg = endDeg <= startDeg ? (endDeg - startDeg) : (endDeg - startDeg - 360.0);
    } else {
      sweepDeg = endDeg >= startDeg ? (endDeg - startDeg) : (endDeg - startDeg + 360.0);
    }
    return sweepDeg * math.pi / 180.0;
  }

  double get startAngleDeg => startAngleRad * 180.0 / math.pi;
  double get sweepAngleDeg => sweepAngleRad * 180.0 / math.pi;
  double get endAngleDeg => (startAngleRad + sweepAngleRad) * 180.0 / math.pi;
  double get arcLength => length;
  bool get isClockwise => sweepAngleRad < 0;

  double distanceTo(CadPoint2D pt) {
    final dCenter = center.distanceTo(pt);
    final radialDist = (dCenter - radius).abs();
    final ang = math.atan2(pt.y - center.y, pt.x - center.x);

    double normalize(double a) {
      double res = a % (2.0 * math.pi);
      if (res < 0) res += 2.0 * math.pi;
      return res;
    }

    final start = normalize(startAngleRad);
    final end = normalize(startAngleRad + sweepAngleRad);
    final pAng = normalize(ang);

    bool isBetween;
    if (sweepAngleRad >= 0) {
      if (start <= end) {
        isBetween = pAng >= start && pAng <= end;
      } else {
        isBetween = pAng >= start || pAng <= end;
      }
    } else {
      if (end <= start) {
        isBetween = pAng >= end && pAng <= start;
      } else {
        isBetween = pAng >= end || pAng <= start;
      }
    }

    if (isBetween) {
      return radialDist;
    }
    return math.min(startPoint.distanceTo(pt), endPoint.distanceTo(pt));
  }

  List<CadPoint2D> toPolygon({double maxStepDeg = 5.0}) {
    final sweep = sweepAngleDeg;
    final numSteps = math.max(2, (sweep.abs() / maxStepDeg).ceil());
    final pts = <CadPoint2D>[];
    for (int i = 0; i <= numSteps; i++) {
      final angRad = (startAngleDeg + (sweep * i / numSteps)) * math.pi / 180.0;
      pts.add(CadPoint2D(center.x + radius * math.cos(angRad), center.y + radius * math.sin(angRad)));
    }
    return pts;
  }

  double get length => radius * sweepAngleRad.abs();

  CadPoint2D get startPoint => CadPoint2D(center.x + radius * math.cos(startAngleRad), center.y + radius * math.sin(startAngleRad));

  CadPoint2D get endPoint =>
      CadPoint2D(center.x + radius * math.cos(startAngleRad + sweepAngleRad), center.y + radius * math.sin(startAngleRad + sweepAngleRad));

  CadPoint2D get midpoint =>
      CadPoint2D(center.x + radius * math.cos(startAngleRad + sweepAngleRad / 2.0), center.y + radius * math.sin(startAngleRad + sweepAngleRad / 2.0));

  /// Constructs an arc through 3 points (start p1, intermediate p2, end p3)
  factory CadArc2D.from3Points({
    required String id,
    required CadPoint2D p1,
    required CadPoint2D p2,
    required CadPoint2D p3,
    String layer = '0',
    bool isVisible = true,
    bool isConstruction = false,
  }) {
    final x1 = p1.x, y1 = p1.y;
    final x2 = p2.x, y2 = p2.y;
    final x3 = p3.x, y3 = p3.y;

    final d = 2.0 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2));
    if (d.abs() < 1e-6) {
      // Collinear fallback: flat arc
      final mid = CadPoint2D((x1 + x3) / 2.0, (y1 + y3) / 2.0);
      return CadArc2D(
        id: id,
        center: mid,
        radius: p1.distanceTo(p3) / 2.0,
        startAngleRad: math.atan2(y1 - mid.y, x1 - mid.x),
        sweepAngleRad: math.pi,
        layer: layer,
        isVisible: isVisible,
        isConstruction: isConstruction,
      );
    }

    final ux = ((x1 * x1 + y1 * y1) * (y2 - y3) + (x2 * x2 + y2 * y2) * (y3 - y1) + (x3 * x3 + y3 * y3) * (y1 - y2)) / d;
    final uy = ((x1 * x1 + y1 * y1) * (x3 - x2) + (x2 * x2 + y2 * y2) * (x1 - x3) + (x3 * x3 + y3 * y3) * (x2 - x1)) / d;
    final center = CadPoint2D(ux, uy);
    final radius = center.distanceTo(p1);

    final a1 = math.atan2(p1.y - center.y, p1.x - center.x);
    final a2 = math.atan2(p2.y - center.y, p2.x - center.x);
    final a3 = math.atan2(p3.y - center.y, p3.x - center.x);

    // Normalize angles relative to a1
    double d2 = (a2 - a1) % (2.0 * math.pi);
    double d3 = (a3 - a1) % (2.0 * math.pi);

    double sweep;
    if (d2 < d3) {
      // Counter-clockwise
      sweep = d3;
    } else {
      // Clockwise
      sweep = d3 - 2.0 * math.pi;
    }

    return CadArc2D(
      id: id,
      center: center,
      radius: radius,
      startAngleRad: a1,
      sweepAngleRad: sweep,
      layer: layer,
      isVisible: isVisible,
      isConstruction: isConstruction,
    );
  }

  /// Samples vertices along the arc
  List<CadPoint2D> samplePoints([int count = 16]) {
    final pts = <CadPoint2D>[];
    for (int i = 0; i <= count; i++) {
      final t = i / count;
      final angle = startAngleRad + t * sweepAngleRad;
      pts.add(CadPoint2D(center.x + radius * math.cos(angle), center.y + radius * math.sin(angle)));
    }
    return pts;
  }

  @override
  CadArc2D translate(double dx, double dy) => copyWith(center: CadPoint2D(center.x + dx, center.y + dy));

  @override
  CadArc2D rotate(CadPoint2D origin, double angleRad) =>
      copyWith(center: CadTransformMath.rotatePoint(center, origin, angleRad), startAngleRad: startAngleRad + angleRad);

  @override
  CadArc2D mirror(CadPoint2D axisP1, CadPoint2D axisP2) {
    final mirroredCenter = CadTransformMath.mirrorPoint(center, axisP1, axisP2);
    final mirroredStart = CadTransformMath.mirrorPoint(startPoint, axisP1, axisP2);
    final mirroredEnd = CadTransformMath.mirrorPoint(endPoint, axisP1, axisP2);
    final newStartAngle = math.atan2(mirroredStart.y - mirroredCenter.y, mirroredStart.x - mirroredCenter.x);
    final newEndAngle = math.atan2(mirroredEnd.y - mirroredCenter.y, mirroredEnd.x - mirroredCenter.x);
    var sweep = (newEndAngle - newStartAngle) % (2.0 * math.pi);
    // Mirroring flips chirality
    if (sweepAngleRad > 0) {
      sweep = sweep - 2.0 * math.pi;
    }
    return copyWith(center: mirroredCenter, startAngleRad: newStartAngle, sweepAngleRad: sweep == 0.0 ? -2.0 * math.pi : sweep);
  }

  @override
  CadArc2D scale(CadPoint2D origin, double factorX, double factorY) {
    final avgFactor = (factorX.abs() + factorY.abs()) / 2.0;
    return copyWith(center: CadTransformMath.scalePoint(center, origin, factorX, factorY), radius: radius * avgFactor);
  }

  @override
  CadBoundingBox2D get boundingBox => CadBoundingBox2D.fromPoints(samplePoints(16));

  CadArc2D copyWith({
    String? id,
    CadPoint2D? center,
    double? radius,
    double? startAngleRad,
    double? sweepAngleRad,
    double? startAngleDeg,
    double? endAngleDeg,
    CadPoint2D? startPoint,
    CadPoint2D? endPoint,
    bool? isClockwise,
    String? layer,
    bool? isBoundary,
    bool? isVisible,
    bool? isConstruction,
  }) {
    final effectiveStartRad = startAngleRad ?? (startAngleDeg != null ? startAngleDeg * math.pi / 180.0 : this.startAngleRad);
    double effectiveSweepRad;
    if (sweepAngleRad != null) {
      effectiveSweepRad = sweepAngleRad;
    } else if (endAngleDeg != null || startAngleDeg != null || isClockwise != null) {
      final sDeg = startAngleDeg ?? (startAngleRad != null ? startAngleRad * 180.0 / math.pi : this.startAngleDeg);
      final eDeg = endAngleDeg ?? this.endAngleDeg;
      final cw = isClockwise ?? this.isClockwise;
      effectiveSweepRad = _calcSweepRad(sDeg, eDeg, cw);
    } else {
      effectiveSweepRad = this.sweepAngleRad;
    }

    return CadArc2D(
      id: id ?? this.id,
      center: center ?? this.center,
      radius: radius ?? this.radius,
      startAngleRad: effectiveStartRad,
      sweepAngleRad: effectiveSweepRad,
      layer: layer ?? this.layer,
      isBoundary: isBoundary ?? this.isBoundary,
      isVisible: isVisible ?? this.isVisible,
      isConstruction: isConstruction ?? this.isConstruction,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'arc',
    'id': id,
    'layer': layer,
    'isVisible': isVisible,
    'isConstruction': isConstruction,
    'center': center.toJson(),
    'radius': radius,
    'startAngleRad': startAngleRad,
    'sweepAngleRad': sweepAngleRad,
  };

  factory CadArc2D.fromJson(Map<String, dynamic> json) => CadArc2D(
    id: json['id'] as String,
    center: CadPoint2D.fromJson(json['center'] as Map<String, dynamic>),
    radius: (json['radius'] as num).toDouble(),
    startAngleRad: (json['startAngleRad'] as num).toDouble(),
    sweepAngleRad: (json['sweepAngleRad'] as num).toDouble(),
    layer: json['layer'] as String? ?? '0',
    isVisible: json['isVisible'] as bool? ?? true,
    isConstruction: json['isConstruction'] as bool? ?? false,
  );
}

/// 2D Circle
class CadCircle2D extends CadGeometry {
  final CadPoint2D center;
  final double radius;

  const CadCircle2D({required super.id, required this.center, required this.radius, super.layer, super.isVisible, super.isConstruction});

  double get diameter => radius * 2.0;
  double get circumference => 2.0 * math.pi * radius;
  double get area => math.pi * radius * radius;

  factory CadCircle2D.from2Points({
    required String id,
    required CadPoint2D p1,
    required CadPoint2D p2,
    String layer = '0',
    bool isVisible = true,
    bool isConstruction = false,
  }) {
    final center = CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
    return CadCircle2D(id: id, center: center, radius: p1.distanceTo(p2) / 2.0, layer: layer, isVisible: isVisible, isConstruction: isConstruction);
  }

  factory CadCircle2D.from3Points({
    required String id,
    required CadPoint2D p1,
    required CadPoint2D p2,
    required CadPoint2D p3,
    String layer = '0',
    bool isVisible = true,
    bool isConstruction = false,
  }) {
    final d = 2.0 * (p1.x * (p2.y - p3.y) + p2.x * (p3.y - p1.y) + p3.x * (p1.y - p2.y));
    if (d.abs() < 1e-6) {
      return CadCircle2D.from2Points(id: id, p1: p1, p2: p3, layer: layer, isVisible: isVisible, isConstruction: isConstruction);
    }
    final ux = ((p1.x * p1.x + p1.y * p1.y) * (p2.y - p3.y) + (p2.x * p2.x + p2.y * p2.y) * (p3.y - p1.y) + (p3.x * p3.x + p3.y * p3.y) * (p1.y - p2.y)) / d;
    final uy = ((p1.x * p1.x + p1.y * p1.y) * (p3.x - p2.x) + (p2.x * p2.x + p2.y * p2.y) * (p1.x - p3.x) + (p3.x * p3.x + p3.y * p3.y) * (p2.x - p1.x)) / d;
    final center = CadPoint2D(ux, uy);
    return CadCircle2D(id: id, center: center, radius: center.distanceTo(p1), layer: layer, isVisible: isVisible, isConstruction: isConstruction);
  }

  List<CadPoint2D> samplePoints([int count = 32]) {
    final pts = <CadPoint2D>[];
    for (int i = 0; i < count; i++) {
      final a = (i / count) * 2.0 * math.pi;
      pts.add(CadPoint2D(center.x + radius * math.cos(a), center.y + radius * math.sin(a)));
    }
    return pts;
  }

  @override
  CadCircle2D translate(double dx, double dy) => copyWith(center: CadPoint2D(center.x + dx, center.y + dy));

  @override
  CadCircle2D rotate(CadPoint2D origin, double angleRad) => copyWith(center: CadTransformMath.rotatePoint(center, origin, angleRad));

  @override
  CadCircle2D mirror(CadPoint2D axisP1, CadPoint2D axisP2) => copyWith(center: CadTransformMath.mirrorPoint(center, axisP1, axisP2));

  @override
  CadCircle2D scale(CadPoint2D origin, double factorX, double factorY) {
    final avgFactor = (factorX.abs() + factorY.abs()) / 2.0;
    return copyWith(center: CadTransformMath.scalePoint(center, origin, factorX, factorY), radius: radius * avgFactor);
  }

  @override
  CadBoundingBox2D get boundingBox => CadBoundingBox2D(minX: center.x - radius, minY: center.y - radius, maxX: center.x + radius, maxY: center.y + radius);

  CadCircle2D copyWith({String? id, CadPoint2D? center, double? radius, String? layer, bool? isVisible, bool? isConstruction}) {
    return CadCircle2D(
      id: id ?? this.id,
      center: center ?? this.center,
      radius: radius ?? this.radius,
      layer: layer ?? this.layer,
      isVisible: isVisible ?? this.isVisible,
      isConstruction: isConstruction ?? this.isConstruction,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'circle',
    'id': id,
    'layer': layer,
    'isVisible': isVisible,
    'isConstruction': isConstruction,
    'center': center.toJson(),
    'radius': radius,
  };

  factory CadCircle2D.fromJson(Map<String, dynamic> json) => CadCircle2D(
    id: json['id'] as String,
    center: CadPoint2D.fromJson(json['center'] as Map<String, dynamic>),
    radius: (json['radius'] as num).toDouble(),
    layer: json['layer'] as String? ?? '0',
    isVisible: json['isVisible'] as bool? ?? true,
    isConstruction: json['isConstruction'] as bool? ?? false,
  );
}

/// 2D Ellipse
class CadEllipse2D extends CadGeometry {
  final CadPoint2D center;
  final double radiusX;
  final double radiusY;
  final double rotationDeg;

  const CadEllipse2D({
    required super.id,
    required this.center,
    required this.radiusX,
    required this.radiusY,
    this.rotationDeg = 0.0,
    super.layer,
    super.isVisible,
    super.isConstruction,
  });

  double get area => math.pi * radiusX * radiusY;

  /// Ramanujan approximation for ellipse perimeter
  double get perimeter {
    final a = radiusX;
    final b = radiusY;
    final h = math.pow(a - b, 2) / math.pow(a + b, 2);
    return math.pi * (a + b) * (1.0 + (3.0 * h) / (10.0 + math.sqrt(4.0 - 3.0 * h)));
  }

  List<CadPoint2D> samplePoints([int count = 32]) {
    final pts = <CadPoint2D>[];
    final rotRad = rotationDeg * math.pi / 180.0;
    final cosR = math.cos(rotRad);
    final sinR = math.sin(rotRad);

    for (int i = 0; i < count; i++) {
      final a = (i / count) * 2.0 * math.pi;
      final ex = radiusX * math.cos(a);
      final ey = radiusY * math.sin(a);
      pts.add(CadPoint2D(center.x + ex * cosR - ey * sinR, center.y + ex * sinR + ey * cosR));
    }
    return pts;
  }

  @override
  CadEllipse2D translate(double dx, double dy) => copyWith(center: CadPoint2D(center.x + dx, center.y + dy));

  @override
  CadEllipse2D rotate(CadPoint2D origin, double angleRad) {
    final newCenter = CadTransformMath.rotatePoint(center, origin, angleRad);
    final newRot = (rotationDeg + angleRad * 180.0 / math.pi) % 360.0;
    return copyWith(center: newCenter, rotationDeg: newRot);
  }

  @override
  CadEllipse2D mirror(CadPoint2D axisP1, CadPoint2D axisP2) {
    final newCenter = CadTransformMath.mirrorPoint(center, axisP1, axisP2);
    final axisAngleDeg = math.atan2(axisP2.y - axisP1.y, axisP2.x - axisP1.x) * 180.0 / math.pi;
    final newRot = (2.0 * axisAngleDeg - rotationDeg) % 360.0;
    return copyWith(center: newCenter, rotationDeg: newRot);
  }

  @override
  CadEllipse2D scale(CadPoint2D origin, double factorX, double factorY) {
    return copyWith(center: CadTransformMath.scalePoint(center, origin, factorX, factorY), radiusX: radiusX * factorX.abs(), radiusY: radiusY * factorY.abs());
  }

  @override
  CadBoundingBox2D get boundingBox => CadBoundingBox2D.fromPoints(samplePoints(32));

  CadEllipse2D copyWith({
    String? id,
    CadPoint2D? center,
    double? radiusX,
    double? radiusY,
    double? rotationDeg,
    String? layer,
    bool? isVisible,
    bool? isConstruction,
  }) {
    return CadEllipse2D(
      id: id ?? this.id,
      center: center ?? this.center,
      radiusX: radiusX ?? this.radiusX,
      radiusY: radiusY ?? this.radiusY,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      layer: layer ?? this.layer,
      isVisible: isVisible ?? this.isVisible,
      isConstruction: isConstruction ?? this.isConstruction,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ellipse',
    'id': id,
    'layer': layer,
    'isVisible': isVisible,
    'isConstruction': isConstruction,
    'center': center.toJson(),
    'radiusX': radiusX,
    'radiusY': radiusY,
    'rotationDeg': rotationDeg,
  };

  factory CadEllipse2D.fromJson(Map<String, dynamic> json) => CadEllipse2D(
    id: json['id'] as String,
    center: CadPoint2D.fromJson(json['center'] as Map<String, dynamic>),
    radiusX: (json['radiusX'] as num).toDouble(),
    radiusY: (json['radiusY'] as num).toDouble(),
    rotationDeg: (json['rotationDeg'] as num?)?.toDouble() ?? 0.0,
    layer: json['layer'] as String? ?? '0',
    isVisible: json['isVisible'] as bool? ?? true,
    isConstruction: json['isConstruction'] as bool? ?? false,
  );
}

/// 2D Semantic Rectangle
class CadRectangle2D extends CadGeometry {
  final CadPoint2D center;
  final double widthMm;
  final double heightMm;
  final double rotationDeg;

  const CadRectangle2D({
    required super.id,
    required this.center,
    required this.widthMm,
    required this.heightMm,
    this.rotationDeg = 0.0,
    super.layer,
    super.isVisible,
    super.isConstruction,
  });

  double get area => widthMm * heightMm;
  double get perimeter => 2.0 * (widthMm + heightMm);

  factory CadRectangle2D.fromCorners({
    required String id,
    required CadPoint2D corner1,
    required CadPoint2D corner2,
    String layer = '0',
    bool isVisible = true,
    bool isConstruction = false,
  }) {
    final center = CadPoint2D((corner1.x + corner2.x) / 2.0, (corner1.y + corner2.y) / 2.0);
    return CadRectangle2D(
      id: id,
      center: center,
      widthMm: (corner2.x - corner1.x).abs(),
      heightMm: (corner2.y - corner1.y).abs(),
      rotationDeg: 0.0,
      layer: layer,
      isVisible: isVisible,
      isConstruction: isConstruction,
    );
  }

  /// 4 Corner vertices rotated by rotationDeg
  List<CadPoint2D> toBoundaryPoints() {
    final hw = widthMm / 2.0;
    final hh = heightMm / 2.0;
    final unrotated = [
      CadPoint2D(center.x - hw, center.y - hh),
      CadPoint2D(center.x + hw, center.y - hh),
      CadPoint2D(center.x + hw, center.y + hh),
      CadPoint2D(center.x - hw, center.y + hh),
    ];
    if (rotationDeg == 0.0) return unrotated;
    final rotRad = rotationDeg * math.pi / 180.0;
    return unrotated.map((p) => CadTransformMath.rotatePoint(p, center, rotRad)).toList();
  }

  CadPolyline2D toPolyline() =>
      CadPolyline2D(id: '${id}_poly', vertices: toBoundaryPoints(), isClosed: true, layer: layer, isVisible: isVisible, isConstruction: isConstruction);

  @override
  CadRectangle2D translate(double dx, double dy) => copyWith(center: CadPoint2D(center.x + dx, center.y + dy));

  @override
  CadRectangle2D rotate(CadPoint2D origin, double angleRad) {
    final newCenter = CadTransformMath.rotatePoint(center, origin, angleRad);
    final newRot = (rotationDeg + angleRad * 180.0 / math.pi) % 360.0;
    return copyWith(center: newCenter, rotationDeg: newRot);
  }

  @override
  CadRectangle2D mirror(CadPoint2D axisP1, CadPoint2D axisP2) {
    final newCenter = CadTransformMath.mirrorPoint(center, axisP1, axisP2);
    final axisAngleDeg = math.atan2(axisP2.y - axisP1.y, axisP2.x - axisP1.x) * 180.0 / math.pi;
    final newRot = (2.0 * axisAngleDeg - rotationDeg) % 360.0;
    return copyWith(center: newCenter, rotationDeg: newRot);
  }

  @override
  CadRectangle2D scale(CadPoint2D origin, double factorX, double factorY) {
    return copyWith(
      center: CadTransformMath.scalePoint(center, origin, factorX, factorY),
      widthMm: widthMm * factorX.abs(),
      heightMm: heightMm * factorY.abs(),
    );
  }

  @override
  CadBoundingBox2D get boundingBox => CadBoundingBox2D.fromPoints(toBoundaryPoints());

  CadRectangle2D copyWith({
    String? id,
    CadPoint2D? center,
    double? widthMm,
    double? heightMm,
    double? rotationDeg,
    String? layer,
    bool? isVisible,
    bool? isConstruction,
  }) {
    return CadRectangle2D(
      id: id ?? this.id,
      center: center ?? this.center,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      layer: layer ?? this.layer,
      isVisible: isVisible ?? this.isVisible,
      isConstruction: isConstruction ?? this.isConstruction,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'rectangle',
    'id': id,
    'layer': layer,
    'isVisible': isVisible,
    'isConstruction': isConstruction,
    'center': center.toJson(),
    'widthMm': widthMm,
    'heightMm': heightMm,
    'rotationDeg': rotationDeg,
  };

  factory CadRectangle2D.fromJson(Map<String, dynamic> json) => CadRectangle2D(
    id: json['id'] as String,
    center: CadPoint2D.fromJson(json['center'] as Map<String, dynamic>),
    widthMm: (json['widthMm'] as num).toDouble(),
    heightMm: (json['heightMm'] as num).toDouble(),
    rotationDeg: (json['rotationDeg'] as num?)?.toDouble() ?? 0.0,
    layer: json['layer'] as String? ?? '0',
    isVisible: json['isVisible'] as bool? ?? true,
    isConstruction: json['isConstruction'] as bool? ?? false,
  );
}

/// 2D Obround Slot (Standard CNC Turret Punch slot)
/// Semantically represented: center, length, width, rotation
class CadSlot2D extends CadGeometry {
  final CadPoint2D center;
  final double lengthMm;
  final double widthMm;
  final double rotationDeg;

  const CadSlot2D({
    required super.id,
    required this.center,
    required this.lengthMm,
    required this.widthMm,
    this.rotationDeg = 0.0,
    super.layer = 'HOLES',
    super.isVisible,
    super.isConstruction,
  });

  double get radius => widthMm / 2.0;
  double get centerToCenterDistance => math.max(0.0, lengthMm - widthMm);

  factory CadSlot2D.fromCenterlineRadius({
    required String id,
    required CadPoint2D p1,
    required CadPoint2D p2,
    required double radius,
    String layer = 'HOLES',
    bool isVisible = true,
    bool isConstruction = false,
  }) {
    final center = CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
    final c2c = p1.distanceTo(p2);
    final angleDeg = math.atan2(p2.y - p1.y, p2.x - p1.x) * 180.0 / math.pi;
    return CadSlot2D(
      id: id,
      center: center,
      lengthMm: c2c + 2.0 * radius,
      widthMm: radius * 2.0,
      rotationDeg: angleDeg,
      layer: layer,
      isVisible: isVisible,
      isConstruction: isConstruction,
    );
  }

  /// Evaluates full outer boundary loop (two semicircles + two straight edges)
  List<CadPoint2D> toBoundaryPoints({int arcResolution = 16}) {
    final pts = <CadPoint2D>[];
    final halfC2C = centerToCenterDistance / 2.0;
    final r = radius;

    // Local points before rotation:
    // Semicircle right centered at (+halfC2C, 0)
    for (int i = 0; i <= arcResolution; i++) {
      final a = -math.pi / 2.0 + (i / arcResolution) * math.pi;
      pts.add(CadPoint2D(halfC2C + r * math.cos(a), r * math.sin(a)));
    }
    // Semicircle left centered at (-halfC2C, 0)
    for (int i = 0; i <= arcResolution; i++) {
      final a = math.pi / 2.0 + (i / arcResolution) * math.pi;
      pts.add(CadPoint2D(-halfC2C + r * math.cos(a), r * math.sin(a)));
    }

    final rotRad = rotationDeg * math.pi / 180.0;
    return pts.map((p) => CadTransformMath.rotatePoint(p + center, center, rotRad)).toList();
  }

  @override
  CadSlot2D translate(double dx, double dy) => copyWith(center: CadPoint2D(center.x + dx, center.y + dy));

  @override
  CadSlot2D rotate(CadPoint2D origin, double angleRad) {
    final newCenter = CadTransformMath.rotatePoint(center, origin, angleRad);
    final newRot = (rotationDeg + angleRad * 180.0 / math.pi) % 360.0;
    return copyWith(center: newCenter, rotationDeg: newRot);
  }

  @override
  CadSlot2D mirror(CadPoint2D axisP1, CadPoint2D axisP2) {
    final newCenter = CadTransformMath.mirrorPoint(center, axisP1, axisP2);
    final axisAngleDeg = math.atan2(axisP2.y - axisP1.y, axisP2.x - axisP1.x) * 180.0 / math.pi;
    final newRot = (2.0 * axisAngleDeg - rotationDeg) % 360.0;
    return copyWith(center: newCenter, rotationDeg: newRot);
  }

  @override
  CadSlot2D scale(CadPoint2D origin, double factorX, double factorY) {
    final avgFactor = (factorX.abs() + factorY.abs()) / 2.0;
    return copyWith(center: CadTransformMath.scalePoint(center, origin, factorX, factorY), lengthMm: lengthMm * factorX.abs(), widthMm: widthMm * avgFactor);
  }

  @override
  CadBoundingBox2D get boundingBox => CadBoundingBox2D.fromPoints(toBoundaryPoints());

  CadSlot2D copyWith({
    String? id,
    CadPoint2D? center,
    double? lengthMm,
    double? widthMm,
    double? rotationDeg,
    String? layer,
    bool? isVisible,
    bool? isConstruction,
  }) {
    return CadSlot2D(
      id: id ?? this.id,
      center: center ?? this.center,
      lengthMm: lengthMm ?? this.lengthMm,
      widthMm: widthMm ?? this.widthMm,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      layer: layer ?? this.layer,
      isVisible: isVisible ?? this.isVisible,
      isConstruction: isConstruction ?? this.isConstruction,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'slot',
    'id': id,
    'layer': layer,
    'isVisible': isVisible,
    'isConstruction': isConstruction,
    'center': center.toJson(),
    'lengthMm': lengthMm,
    'widthMm': widthMm,
    'rotationDeg': rotationDeg,
  };

  factory CadSlot2D.fromJson(Map<String, dynamic> json) => CadSlot2D(
    id: json['id'] as String,
    center: CadPoint2D.fromJson(json['center'] as Map<String, dynamic>),
    lengthMm: (json['lengthMm'] as num).toDouble(),
    widthMm: (json['widthMm'] as num).toDouble(),
    rotationDeg: (json['rotationDeg'] as num?)?.toDouble() ?? 0.0,
    layer: json['layer'] as String? ?? 'HOLES',
    isVisible: json['isVisible'] as bool? ?? true,
    isConstruction: json['isConstruction'] as bool? ?? false,
  );
}
