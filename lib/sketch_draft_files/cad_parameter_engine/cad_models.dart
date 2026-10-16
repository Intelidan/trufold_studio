//
//1. 🗃️ Core Configuration & State Models (cad_models.dart)

// This file defines high-level data types, geometric primitives, topological trackers, constraints, and undo/redo snapshot mementos.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';
export 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';

enum SketchEntityType { line, rectangle, circle, polyline }

enum FeatureType { extrude, cut }

enum WeldJointStyle { buttJoint, lapJoint, tJoint }

enum CADConstraintType { horizontal, vertical, perpendicular }

enum CADPlaneType {
  datumXY,
  datumXZ,
  datumYZ,
  offsetPlane,
  anglePlane,
  facePlane,
  midplane,
  threePointPlane,
}

/// Represents a targeted local coordinate system bound to a 3D face, datum origin, or construction plane
class CADSketchPlane {
  final String id;
  String name;
  final vm.Vector3 origin;
  final vm.Vector3 normal;
  final vm.Vector3 up;
  final List<CADLineSegment> entities = [];
  final List<CADPrimitiveEntity> primitives = [];
  final List<CadConstraint> constraints = [];
  String? targetPartId;
  String? targetFaceId;
  CADPlaneType planeType;
  double size;
  double? offsetDistance;
  String? parentPlaneId;
  double? angleDeg;
  bool isVisible;
  Color? customColor;

  CADSketchPlane({
    required this.id,
    required this.origin,
    required this.normal,
    required this.up,
    this.targetPartId,
    this.targetFaceId,
    String? name,
    this.planeType = CADPlaneType.facePlane,
    this.size = 140.0,
    this.offsetDistance,
    this.parentPlaneId,
    this.angleDeg,
    this.isVisible = true,
    this.customColor,
  }) : name = name ?? id;

  vm.Vector3 get xAxis => up.normalized().cross(normal.normalized()).normalized();
  vm.Vector3 get yAxis => up.normalized();
  vm.Vector3 get zAxis => normal.normalized();

  vm.Vector3 toWorld(Offset local) => origin + (xAxis * local.dx) + (yAxis * local.dy);
  Offset toLocal(vm.Vector3 world) {
    final d = world - origin;
    return Offset(d.dot(xAxis), d.dot(yAxis));
  }

  /// Computes the 4 corners of this plane's visual quad boundary in 3D world space.
  List<vm.Vector3> getQuadCorners({double? customHalfSize}) {
    final half = (customHalfSize ?? (size / 2.0));
    final x = xAxis * half;
    final y = yAxis * half;
    return [
      origin - x - y,
      origin + x - y,
      origin + x + y,
      origin - x + y,
    ];
  }

  /// Calculates whether a 3D ray (e.g. from mouse unprojection) penetrates this plane's boundary.
  ({bool hit, double t, vm.Vector3? hitWorld, Offset? hitLocal}) intersectRay(
    vm.Vector3 rayOrigin,
    vm.Vector3 rayDir, {
    double? maxExtent,
  }) {
    final planeNormal = zAxis;
    final denom = rayDir.dot(planeNormal);
    if (denom.abs() < 1e-6) {
      return (hit: false, t: -1.0, hitWorld: null, hitLocal: null);
    }
    final diff = origin - rayOrigin;
    final t = diff.dot(planeNormal) / denom;
    if (t < 0.0) {
      return (hit: false, t: t, hitWorld: null, hitLocal: null);
    }
    final hitWorld = rayOrigin + (rayDir * t);
    final hitLocal = toLocal(hitWorld);
    final extent = maxExtent ?? (size / 2.0);
    final inBounds = hitLocal.dx.abs() <= extent && hitLocal.dy.abs() <= extent;
    return (hit: inBounds, t: t, hitWorld: hitWorld, hitLocal: hitLocal);
  }
}

/// Abstract base class mapping all structural 2D CAD entities
abstract class CADPrimitiveEntity {
  final String id;
  bool isSelected;
  bool isConstruction;
  bool isProjected;
  String? sourceEntityId;
  bool isFullyConstrained;
  FeatureType featureType;
  bool isPassThrough;
  double depthMm;

  CADPrimitiveEntity({
    required this.id,
    this.isSelected = false,
    this.isConstruction = false,
    this.isProjected = false,
    this.sourceEntityId,
    this.isFullyConstrained = false,
    this.featureType = FeatureType.cut,
    this.isPassThrough = true,
    this.depthMm = 5.0,
  });

  /// Deconstructs the high-level shape parameters into discrete vector segments
  List<CADLineSegment> toLineSegments({int curveResolution = 36});
}

/// A mathematical 2D line segment structure tracking layout properties
class CADLineSegment {
  final String id;
  Offset start;
  Offset end;
  bool isDeleted;
  bool isConstruction;
  bool isProjected;
  bool isFullyConstrained;
  String? sourceEntityId;

  CADLineSegment({
    required this.id,
    required this.start,
    required this.end,
    this.isDeleted = false,
    this.isConstruction = false,
    this.isProjected = false,
    this.isFullyConstrained = false,
    this.sourceEntityId,
  });

  bool isTouched(Offset point, double tolerance) {
    double x1 = start.dx;
    double y1 = start.dy;
    double x2 = end.dx;
    double y2 = end.dy;
    double px = point.dx;
    double py = point.dy;

    double l2 = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1);
    if (l2 == 0) return (point - start).distance < tolerance;

    double t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2;
    t = t.clamp(0.0, 1.0);

    Offset projection = Offset(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
    return (point - projection).distance < tolerance;
  }
}

class CADRectangleEntity extends CADPrimitiveEntity {
  Offset startPoint;
  double width;
  double height;

  CADRectangleEntity({
    required super.id,
    required this.startPoint,
    required this.width,
    required this.height,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
    super.sourceEntityId,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    final p1 = startPoint;
    final p2 = Offset(startPoint.dx + width, startPoint.dy);
    final p3 = Offset(startPoint.dx + width, startPoint.dy + height);
    final p4 = Offset(startPoint.dx, startPoint.dy + height);

    return [
      CADLineSegment(id: "${id}_top", start: p1, end: p2, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId),
      CADLineSegment(id: "${id}_right", start: p2, end: p3, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId),
      CADLineSegment(id: "${id}_bottom", start: p3, end: p4, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId),
      CADLineSegment(id: "${id}_left", start: p4, end: p1, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId),
    ];
  }
}

class CADCircleEntity extends CADPrimitiveEntity {
  Offset center;
  double radius;

  CADCircleEntity({
    required super.id,
    required this.center,
    required this.radius,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
    super.sourceEntityId,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    List<CADLineSegment> segments = [];
    double angleStep = (2 * math.pi) / curveResolution;

    Offset previousPoint = Offset(center.dx + radius * math.cos(0), center.dy + radius * math.sin(0));

    for (int i = 1; i <= curveResolution; i++) {
      double currentAngle = i * angleStep;
      Offset currentPoint = Offset(center.dx + radius * math.cos(currentAngle), center.dy + radius * math.sin(currentAngle));
      segments.add(CADLineSegment(id: "${id}_arc_$i", start: previousPoint, end: currentPoint, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId));
      previousPoint = currentPoint;
    }
    return segments;
  }
}

class CADLineEntity extends CADPrimitiveEntity {
  Offset start;
  Offset end;

  CADLineEntity({
    required super.id,
    required this.start,
    required this.end,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
    super.sourceEntityId,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    return [CADLineSegment(id: id, start: start, end: end, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId)];
  }
}

class CADPolylineEntity extends CADPrimitiveEntity {
  final List<Offset> points;
  final bool isClosed;

  CADPolylineEntity({
    required super.id,
    required this.points,
    this.isClosed = true,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
    super.sourceEntityId,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    final segments = <CADLineSegment>[];
    if (points.length < 2) return segments;
    for (int i = 0; i < points.length - 1; i++) {
      segments.add(CADLineSegment(id: '${id}_seg_$i', start: points[i], end: points[i + 1], isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId));
    }
    if (isClosed && points.length > 2) {
      segments.add(CADLineSegment(id: '${id}_seg_close', start: points.last, end: points.first, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId));
    }
    return segments;
  }
}

class CADCenterRectangleEntity extends CADPrimitiveEntity {
  Offset center;
  double width;
  double height;
  bool hasDiagonalConstruction;

  CADCenterRectangleEntity({
    required super.id,
    required this.center,
    required this.width,
    required this.height,
    this.hasDiagonalConstruction = true,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
    super.sourceEntityId,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  Offset get topLeft => Offset(center.dx - width / 2.0, center.dy - height / 2.0);
  Offset get topRight => Offset(center.dx + width / 2.0, center.dy - height / 2.0);
  Offset get bottomRight => Offset(center.dx + width / 2.0, center.dy + height / 2.0);
  Offset get bottomLeft => Offset(center.dx - width / 2.0, center.dy + height / 2.0);

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    final p1 = topLeft;
    final p2 = topRight;
    final p3 = bottomRight;
    final p4 = bottomLeft;

    final segs = [
      CADLineSegment(id: "${id}_top", start: p1, end: p2, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId),
      CADLineSegment(id: "${id}_right", start: p2, end: p3, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId),
      CADLineSegment(id: "${id}_bottom", start: p3, end: p4, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId),
      CADLineSegment(id: "${id}_left", start: p4, end: p1, isConstruction: isConstruction, isProjected: isProjected, sourceEntityId: sourceEntityId),
    ];

    if (hasDiagonalConstruction) {
      segs.add(CADLineSegment(id: "${id}_diag1", start: p1, end: p3, isConstruction: true, isProjected: isProjected, sourceEntityId: sourceEntityId));
      segs.add(CADLineSegment(id: "${id}_diag2", start: p4, end: p2, isConstruction: true, isProjected: isProjected, sourceEntityId: sourceEntityId));
    }

    return segs;
  }
}

class CADArcGeometry {
  final Offset center;
  final double radius;
  final double startAngle;
  final double sweep;

  const CADArcGeometry({
    required this.center,
    required this.radius,
    required this.startAngle,
    required this.sweep,
  });
}

class CADArcEntity extends CADPrimitiveEntity {
  Offset startPoint;
  Offset endPoint;
  Offset pointOnArc;

  CADArcEntity({
    required super.id,
    required this.startPoint,
    required this.endPoint,
    required this.pointOnArc,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
    super.sourceEntityId,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  /// Computes the 2D circumcircle geometry passing through startPoint, pointOnArc, and endPoint.
  /// Returns null if the three points are collinear.
  CADArcGeometry? computeCircumcircle() {
    final x1 = startPoint.dx;
    final y1 = startPoint.dy;
    final x2 = endPoint.dx;
    final y2 = endPoint.dy;
    final x3 = pointOnArc.dx;
    final y3 = pointOnArc.dy;

    final d = 2.0 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2));
    if (d.abs() < 1e-7) return null; // Collinear fallback

    final d1 = x1 * x1 + y1 * y1;
    final d2 = x2 * x2 + y2 * y2;
    final d3 = x3 * x3 + y3 * y3;

    final cx = (d1 * (y2 - y3) + d2 * (y3 - y1) + d3 * (y1 - y2)) / d;
    final cy = (d1 * (x3 - x2) + d2 * (x1 - x3) + d3 * (x2 - x1)) / d;
    final center = Offset(cx, cy);
    final radius = (startPoint - center).distance;

    final a1 = math.atan2(y1 - cy, x1 - cx);
    final a2 = math.atan2(y2 - cy, x2 - cx);
    final a3 = math.atan2(y3 - cy, x3 - cx);

    double norm(double a) {
      while (a < 0) {
        a += 2.0 * math.pi;
      }
      while (a >= 2.0 * math.pi) {
        a -= 2.0 * math.pi;
      }
      return a;
    }

    final rel2 = norm(a2 - a1);
    final rel3 = norm(a3 - a1);
    final isCcw = (rel3 > 0.0 && rel3 < rel2);
    final sweep = isCcw ? rel2 : (rel2 - 2.0 * math.pi);

    return CADArcGeometry(
      center: center,
      radius: radius,
      startAngle: a1,
      sweep: sweep,
    );
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 24}) {
    final geom = computeCircumcircle();
    if (geom == null) {
      return [
        CADLineSegment(
          id: '${id}_linear',
          start: startPoint,
          end: endPoint,
          isConstruction: isConstruction,
          isProjected: isProjected,
          sourceEntityId: sourceEntityId,
        ),
      ];
    }

    final segments = <CADLineSegment>[];
    final steps = math.max(6, (curveResolution * (geom.sweep.abs() / (2.0 * math.pi))).round());
    Offset prev = startPoint;
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final angle = geom.startAngle + t * geom.sweep;
      final curr = (i == steps)
          ? endPoint
          : Offset(geom.center.dx + geom.radius * math.cos(angle), geom.center.dy + geom.radius * math.sin(angle));
      segments.add(
        CADLineSegment(
          id: '${id}_arc_$i',
          start: prev,
          end: curr,
          isConstruction: isConstruction,
          isProjected: isProjected,
          sourceEntityId: sourceEntityId,
        ),
      );
      prev = curr;
    }
    return segments;
  }
}

class GeometricConstraint {
  final String id;
  final CADConstraintType type;
  final String primarySegmentId;
  final String? secondarySegmentId;

  GeometricConstraint({required this.id, required this.type, required this.primarySegmentId, this.secondarySegmentId});

  String get iconSymbol {
    switch (type) {
      case CADConstraintType.horizontal:
        return "─";
      case CADConstraintType.vertical:
        return "│";
      case CADConstraintType.perpendicular:
        return "└";
    }
  }
}

class CADHistoryItem {
  final String id;
  final String name;
  final DateTime timestamp;
  bool isActive;
  final CADSketchPlane? referencePlane;
  FeatureType featureType;
  double modificationDepth;

  CADHistoryItem({
    required this.id,
    required this.name,
    required this.timestamp,
    this.isActive = true,
    this.referencePlane,
    this.featureType = FeatureType.cut,
    this.modificationDepth = 0.5,
  });
}

class CADWorkspaceSnapshot {
  final List<CADPrimitiveEntity> primitivesRegistry;
  final List<CADLineSegment> sketchSegments;

  CADWorkspaceSnapshot({required List<CADPrimitiveEntity> primitives, required List<CADLineSegment> segments})
    : primitivesRegistry = List.from(primitives),
      sketchSegments = segments
          .map((s) => CADLineSegment(id: s.id, start: s.start, end: s.end, isDeleted: s.isDeleted, isConstruction: s.isConstruction))
          .toList();
}
