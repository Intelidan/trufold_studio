//
//1. 🗃️ Core Configuration & State Models (cad_models.dart)

// This file defines high-level data types, geometric primitives, topological trackers, constraints, and undo/redo snapshot mementos.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';
export 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';

enum SketchEntityType { line, rectangle, circle, polyline }

enum FeatureType { extrude, cut, bend }

/// Stores a parametric link between a 2D CADSketchPlane and a 3D feature/body derived from it.
class CADDependentFeatureLink {
  final String id;
  String operation; // 'newBody', 'join', 'cut', 'intersect', 'surfaceCut', 'bend'
  String? targetPartId;
  final List<String> createdPartIds;
  String? targetFaceId;
  double distanceMm;
  double distanceSide2Mm;
  double taperAngleDeg;
  String direction; // 'oneSide', 'symmetric', 'twoSide'
  bool isPassThrough;
  double bendAngleDeg;
  double bendRadiusMm;
  final List<String> profileEntityIds;

  CADDependentFeatureLink({
    required this.id,
    String? operation,
    String? operationType,
    this.targetPartId,
    String? createdPartId,
    List<String>? createdPartIds,
    this.targetFaceId,
    this.distanceMm = 25.0,
    double? distanceSide2Mm,
    double? secondDistanceMm,
    double? taperAngleDeg,
    double? draftAngleDeg,
    String? direction,
    String? directionName,
    this.isPassThrough = false,
    this.bendAngleDeg = 0.0,
    this.bendRadiusMm = 0.0,
    List<String>? profileEntityIds,
    Set<String>? targetProfileIds,
  })  : operation = operation ?? operationType ?? 'newBody',
        createdPartIds = createdPartIds ?? (createdPartId != null ? [createdPartId] : []),
        distanceSide2Mm = secondDistanceMm ?? distanceSide2Mm ?? 0.0,
        taperAngleDeg = draftAngleDeg ?? taperAngleDeg ?? 0.0,
        direction = directionName ?? direction ?? 'oneSide',
        profileEntityIds = profileEntityIds ?? (targetProfileIds != null ? targetProfileIds.toList() : []);

  String get operationType => operation;
  set operationType(String val) => operation = val;

  Set<String> get targetProfileIds => profileEntityIds.toSet();

  String? get createdPartId => createdPartIds.isNotEmpty ? createdPartIds.first : null;
  set createdPartId(String? id) {
    createdPartIds.clear();
    if (id != null) createdPartIds.add(id);
  }

  double get secondDistanceMm => distanceSide2Mm;
  set secondDistanceMm(double v) => distanceSide2Mm = v;

  double get draftAngleDeg => taperAngleDeg;
  set draftAngleDeg(double v) => taperAngleDeg = v;

  String get directionName => direction;
  set directionName(String v) => direction = v;
}

/// Parametric Extrude/Cut Feature Specification isolating operations per target profile (Section 6)
class ExtrudeFeatureSpec {
  final String featureId;
  final String sketchId;
  final Set<String> targetProfileIds;
  String operation; // 'newBody', 'join', 'cut', 'intersect'
  double depthMm;
  bool isSymmetric;
  final String? targetPartId;

  ExtrudeFeatureSpec({
    required this.featureId,
    required this.sketchId,
    required Set<String> targetProfileIds,
    this.operation = 'newBody',
    this.depthMm = 25.0,
    this.isSymmetric = false,
    this.targetPartId,
  }) : targetProfileIds = Set<String>.from(targetProfileIds);
}

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
  /// Parametric 3D features (New Body, Join, Cut, Pass-Through, Bend) driven by this sketch plane.
  final List<CADDependentFeatureLink> dependentFeatures = [];
  /// Whether closed polygon/rectangle segments on this plane are topologically bonded at corners.
  bool isLoopBonded = true;
  /// Entity IDs explicitly broken/unbonded via the Break Polygon tool.
  final Set<String> unbondedEntityIds = {};
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

  vm.Vector3 sketch2DToWorld(vm.Vector2 p2d) => toWorld(Offset(p2d.x, p2d.y));
  vm.Vector2 worldToSketch2D(vm.Vector3 world) {
    final l = toLocal(world);
    return vm.Vector2(l.dx, l.dy);
  }
  vm.Vector3 get planeNormal => zAxis;

  /// Dynamically auto-sizes this sketch plane's boundary to enclose all sketch entities & dimensions.
  void recalculateAutoSize() {
    if (primitives.isEmpty) return;
    double pMinX = -40.0, pMaxX = 40.0, pMinY = -40.0, pMaxY = 40.0;
    for (final prim in primitives) {
      for (final seg in prim.toLineSegments(curveResolution: 16)) {
        pMinX = math.min(pMinX, math.min(seg.start.dx, seg.end.dx));
        pMaxX = math.max(pMaxX, math.max(seg.start.dx, seg.end.dx));
        pMinY = math.min(pMinY, math.min(seg.start.dy, seg.end.dy));
        pMaxY = math.max(pMaxY, math.max(seg.start.dy, seg.end.dy));
      }
    }
    const double marginMm = 48.0;
    final double spanX = (pMaxX - pMinX) + marginMm * 2;
    final double spanY = (pMaxY - pMinY) + marginMm * 2;
    final double neededSize = math.max(spanX, spanY);
    if (neededSize > size) {
      size = neededSize;
    }
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
  bool isImprintedReference;
  bool isFixed;
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
    this.isImprintedReference = false,
    this.isFixed = false,
    this.sourceEntityId,
    this.isFullyConstrained = false,
    this.featureType = FeatureType.cut,
    this.isPassThrough = true,
    this.depthMm = 5.0,
  });

  /// Deconstructs the high-level shape parameters into discrete vector segments
  List<CADLineSegment> toLineSegments({int curveResolution = 36});
}

typedef SurfaceSketch = CADSketchPlane;

/// A mathematical 2D line segment structure tracking layout properties
class CADLineSegment {
  final String id;
  Offset start;
  Offset end;
  bool isDeleted;
  bool isConstruction;
  bool isProjected;
  bool isImprintedReference;
  bool isFullyConstrained;
  String? sourceEntityId;

  CADLineSegment({
    required this.id,
    required this.start,
    required this.end,
    this.isDeleted = false,
    this.isConstruction = false,
    this.isProjected = false,
    this.isImprintedReference = false,
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
    super.isImprintedReference,
    super.isFixed,
    super.isFullyConstrained,
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
    super.isImprintedReference,
    super.isFixed,
    super.isFullyConstrained,
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

/// 1. Midpoint Line (01_lines/02_midpoint_line.svg)
/// Click 1 = Midpoint (center), Click 2 = Endpoint -> extends symmetrically to (2*center - endPoint, endPoint).
class CADMidpointLineEntity extends CADLineEntity {
  Offset get midpoint => Offset((start.dx + end.dx) / 2.0, (start.dy + end.dy) / 2.0);

  CADMidpointLineEntity({
    required super.id,
    required Offset midpoint,
    required Offset endpoint,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
  }) : super(
          start: Offset(2.0 * midpoint.dx - endpoint.dx, 2.0 * midpoint.dy - endpoint.dy),
          end: endpoint,
        );

  void updateFromMidpointAndEnd(Offset mid, Offset endPt) {
    start = Offset(2.0 * mid.dx - endPt.dx, 2.0 * mid.dy - endPt.dy);
    end = endPt;
  }
}

/// 2. Aligned Rectangle (02_rectangles/03_aligned_rectangle.svg)
/// 3-Click Angled Rectangle: p1 -> p2 defines primary edge & angle; p3 defines perpendicular height.
class CADAlignedRectangleEntity extends CADPrimitiveEntity {
  Offset corner1;
  Offset corner2;
  double height; // Signed perpendicular offset from edge (corner1 -> corner2)
  bool hasDiagonalConstruction;

  CADAlignedRectangleEntity({
    required super.id,
    required this.corner1,
    required this.corner2,
    required this.height,
    this.hasDiagonalConstruction = false,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  double get width => (corner2 - corner1).distance;

  List<Offset> get corners {
    final edge = corner2 - corner1;
    final len = edge.distance;
    final dir = len > 1e-5 ? edge / len : const Offset(1.0, 0.0);
    final perp = Offset(-dir.dy, dir.dx) * height;
    return [
      corner1,
      corner2,
      corner2 + perp,
      corner1 + perp,
    ];
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    final c = corners;
    return [
      CADLineSegment(id: '${id}_e0', start: c[0], end: c[1], isConstruction: isConstruction),
      CADLineSegment(id: '${id}_e1', start: c[1], end: c[2], isConstruction: isConstruction),
      CADLineSegment(id: '${id}_e2', start: c[2], end: c[3], isConstruction: isConstruction),
      CADLineSegment(id: '${id}_e3', start: c[3], end: c[0], isConstruction: isConstruction),
    ];
  }
}

/// 3. 3-Point Perimeter Circle (03_circles_and_ellipses/02_3_point_circle.svg)
/// Defined by 3 perimeter points (p1, p2, p3); automatically computes circumcenter & radius.
class CADThreePointCircleEntity extends CADCircleEntity {
  Offset p1;
  Offset p2;
  Offset p3;

  CADThreePointCircleEntity({
    required super.id,
    required this.p1,
    required this.p2,
    required this.p3,
    super.isSelected,
    super.isConstruction,
  }) : super(
          center: _computeCenter(p1, p2, p3),
          radius: _computeRadius(p1, p2, p3),
        );

  void recomputeFromThreePoints() {
    center = _computeCenter(p1, p2, p3);
    radius = _computeRadius(p1, p2, p3);
  }

  static Offset _computeCenter(Offset a, Offset b, Offset c) {
    final d = 2.0 * (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
    if (d.abs() < 1e-6) return (a + c) * 0.5;
    final a2 = a.dx * a.dx + a.dy * a.dy;
    final b2 = b.dx * b.dx + b.dy * b.dy;
    final c2 = c.dx * c.dx + c.dy * c.dy;
    final ux = (a2 * (b.dy - c.dy) + b2 * (c.dy - a.dy) + c2 * (a.dy - b.dy)) / d;
    final uy = (a2 * (c.dx - b.dx) + b2 * (a.dx - c.dx) + c2 * (b.dx - a.dx)) / d;
    return Offset(ux, uy);
  }

  static double _computeRadius(Offset a, Offset b, Offset c) {
    final center = _computeCenter(a, b, c);
    return (a - center).distance.clamp(0.1, 10000.0);
  }
}

/// 4. Ellipse & Elliptical Arc (03_circles_and_ellipses/03_ellipse.svg & 04_elliptical_arc.svg)
/// 3-Click Ellipse: Click 1 = Center, Click 2 = Major Axis tip (defines radiusX & rotationRad), Click 3 = Minor radiusY.
class CADEllipseEntity extends CADPrimitiveEntity {
  Offset center;
  double radiusX;
  double radiusY;
  double rotationRad;
  double startAngleRad;
  double sweepAngleRad;

  CADEllipseEntity({
    required super.id,
    required this.center,
    required this.radiusX,
    required this.radiusY,
    this.rotationRad = 0.0,
    this.startAngleRad = 0.0,
    this.sweepAngleRad = 2.0 * math.pi,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
  });

  bool get isFullEllipse => (sweepAngleRad.abs() - 2.0 * math.pi).abs() < 1e-3;

  Offset pointAtParam(double tAngle) {
    final lx = radiusX * math.cos(tAngle);
    final ly = radiusY * math.sin(tAngle);
    final cosR = math.cos(rotationRad);
    final sinR = math.sin(rotationRad);
    return Offset(
      center.dx + lx * cosR - ly * sinR,
      center.dy + lx * sinR + ly * cosR,
    );
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 48}) {
    final segs = <CADLineSegment>[];
    Offset prev = pointAtParam(startAngleRad);
    for (int i = 1; i <= curveResolution; i++) {
      final t = startAngleRad + sweepAngleRad * (i / curveResolution);
      final curr = pointAtParam(t);
      segs.add(CADLineSegment(
        id: '${id}_el_$i',
        start: prev,
        end: curr,
        isConstruction: isConstruction,
      ));
      prev = curr;
    }
    return segs;
  }
}

/// 5. Center Point Arc (04_arcs_and_conics/03_center_point_arc.svg)
/// 3-Click Arc: Click 1 = Center, Click 2 = Start Point (sets radius & startAngle), Click 3 = End Angle.
class CADCenterPointArcEntity extends CADPrimitiveEntity {
  Offset center;
  double radius;
  double startAngleRad;
  double sweepAngleRad;

  CADCenterPointArcEntity({
    required super.id,
    required this.center,
    required this.radius,
    required this.startAngleRad,
    required this.sweepAngleRad,
    super.isSelected,
    super.isConstruction,
  });

  Offset get startPoint => Offset(
        center.dx + radius * math.cos(startAngleRad),
        center.dy + radius * math.sin(startAngleRad),
      );

  Offset get endPoint => Offset(
        center.dx + radius * math.cos(startAngleRad + sweepAngleRad),
        center.dy + radius * math.sin(startAngleRad + sweepAngleRad),
      );

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 32}) {
    final segs = <CADLineSegment>[];
    final steps = math.max(8, (curveResolution * (sweepAngleRad.abs() / (2.0 * math.pi))).round());
    Offset prev = startPoint;
    for (int i = 1; i <= steps; i++) {
      final a = startAngleRad + sweepAngleRad * (i / steps);
      final curr = Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a));
      segs.add(CADLineSegment(id: '${id}_cparc_$i', start: prev, end: curr, isConstruction: isConstruction));
      prev = curr;
    }
    return segs;
  }
}

/// 6. Tangent Arc (04_arcs_and_conics/02_tangent_arc.svg — onshape.pdf p. 30)
/// 2-Click Arc: Starts at [startPoint] with locked unit tangent vector [startTangentDir], ending at [endPoint].
class CADTangentArcEntity extends CADArcEntity {
  Offset startTangentDir;

  CADTangentArcEntity({
    required super.id,
    required super.startPoint,
    required super.endPoint,
    required this.startTangentDir,
    super.isSelected,
    super.isConstruction,
  }) : super(
          pointOnArc: _computeTangentArcMidpoint(startPoint, endPoint, startTangentDir),
        );

  void updateEndPoint(Offset nextEnd) {
    endPoint = nextEnd;
    pointOnArc = _computeTangentArcMidpoint(startPoint, endPoint, startTangentDir);
  }

  static Offset _computeTangentArcMidpoint(Offset p0, Offset p1, Offset tangentDir) {
    final chord = p1 - p0;
    final chordLen = chord.distance;
    if (chordLen < 1e-4) return (p0 + p1) * 0.5;
    final tLen = tangentDir.distance;
    final tUnit = tLen > 1e-5 ? tangentDir / tLen : const Offset(1.0, 0.0);
    // Normal to start tangent is (-tUnit.dy, tUnit.dx)
    final n = Offset(-tUnit.dy, tUnit.dx);
    final denom = 2.0 * (chord.dx * n.dx + chord.dy * n.dy);
    if (denom.abs() < 1e-5) return (p0 + p1) * 0.5;
    final rSigned = (chord.dx * chord.dx + chord.dy * chord.dy) / denom;
    final center = p0 + n * rSigned;
    final r = rSigned.abs();
    final a0 = math.atan2(p0.dy - center.dy, p0.dx - center.dx);
    final a1 = math.atan2(p1.dy - center.dy, p1.dx - center.dx);
    double sweep = a1 - a0;
    // Ensure initial arc velocity along sweep matches tUnit
    final initTangent = Offset(-math.sin(a0), math.cos(a0));
    final dot = initTangent.dx * tUnit.dx + initTangent.dy * tUnit.dy;
    if (dot >= 0) {
      while (sweep <= 0) {
        sweep += 2.0 * math.pi;
      }
    } else {
      while (sweep >= 0) {
        sweep -= 2.0 * math.pi;
      }
    }
    final midAngle = a0 + sweep * 0.5;
    return Offset(center.dx + r * math.cos(midAngle), center.dy + r * math.sin(midAngle));
  }
}

/// 7. Conic Curve (04_arcs_and_conics/05_conic.svg)
/// Rational quadratic Bézier conic through startPoint, apexPoint, endPoint with rho in (0.05..0.95).
/// rho = 0.5 is a parabola, rho < 0.5 is an ellipse, rho > 0.5 is a hyperbola.
class CADConicEntity extends CADPrimitiveEntity {
  Offset startPoint;
  Offset endPoint;
  Offset apexControlPoint;
  double rho; // Default 0.5

  CADConicEntity({
    required super.id,
    required this.startPoint,
    required this.endPoint,
    required this.apexControlPoint,
    this.rho = 0.5,
    super.isSelected,
    super.isConstruction,
  });

  Offset evaluateAt(double t) {
    final w = rho / (1.0 - rho).clamp(0.05, 20.0);
    final u = 1.0 - t;
    final b0 = u * u;
    final b1 = 2.0 * u * t * w;
    final b2 = t * t;
    final denom = b0 + b1 + b2;
    return (startPoint * b0 + apexControlPoint * b1 + endPoint * b2) / denom;
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 32}) {
    final segs = <CADLineSegment>[];
    Offset prev = startPoint;
    for (int i = 1; i <= curveResolution; i++) {
      final curr = evaluateAt(i / curveResolution);
      segs.add(CADLineSegment(id: '${id}_conic_$i', start: prev, end: curr, isConstruction: isConstruction));
      prev = curr;
    }
    return segs;
  }
}

/// 8. Inscribed & Circumscribed Regular Polygon (05_polygons/01 & 02)
/// Supports N = 3..50 sides with construction circle.
class CADRegularPolygonEntity extends CADPrimitiveEntity {
  Offset center;
  double radius;
  int sides; // 3..50 (default 6)
  double rotationRad;
  bool isInscribed; // true = radius is to vertex; false = radius is apothem to flat side midpoint

  CADRegularPolygonEntity({
    required super.id,
    required this.center,
    required this.radius,
    this.sides = 6,
    this.rotationRad = 0.0,
    this.isInscribed = true,
    super.isSelected,
    super.isConstruction,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  double get vertexRadius => isInscribed ? radius : radius / math.cos(math.pi / sides.clamp(3, 50));

  List<Offset> get vertices {
    final n = sides.clamp(3, 50);
    final rV = vertexRadius;
    return List.generate(n, (i) {
      final a = rotationRad + (2.0 * math.pi * i) / n;
      return Offset(center.dx + rV * math.cos(a), center.dy + rV * math.sin(a));
    });
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    final pts = vertices;
    final segs = <CADLineSegment>[];
    for (int i = 0; i < pts.length; i++) {
      segs.add(CADLineSegment(
        id: '${id}_poly_$i',
        start: pts[i],
        end: pts[(i + 1) % pts.length],
        isConstruction: isConstruction,
      ));
    }
    return segs;
  }
}

/// 9. Fit-Point Spline & Bézier Curve (06_splines/01_spline.svg & 02_bezier.svg)
class CADSplineEntity extends CADPrimitiveEntity {
  final List<Offset> controlPoints;
  final bool isBezier; // false = Catmull-Rom interpolating fit spline; true = De Casteljau Bézier
  final bool isClosed;

  CADSplineEntity({
    required super.id,
    required this.controlPoints,
    this.isBezier = false,
    this.isClosed = false,
    super.isSelected,
    super.isConstruction,
  });

  void insertControlPoint(Offset pt) {
    if (controlPoints.length < 2) {
      controlPoints.add(pt);
      return;
    }
    int bestInsertIdx = controlPoints.length;
    double bestDist = double.infinity;
    for (int i = 0; i < controlPoints.length - 1; i++) {
      final mid = (controlPoints[i] + controlPoints[i + 1]) * 0.5;
      final d = (pt - mid).distance;
      if (d < bestDist) {
        bestDist = d;
        bestInsertIdx = i + 1;
      }
    }
    controlPoints.insert(bestInsertIdx, pt);
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 48}) {
    if (controlPoints.length < 2) return [];
    if (controlPoints.length == 2) {
      return [CADLineSegment(id: '${id}_sp_0', start: controlPoints[0], end: controlPoints[1], isConstruction: isConstruction)];
    }

    final sampled = <Offset>[];
    if (isBezier) {
      for (int i = 0; i <= curveResolution; i++) {
        sampled.add(_deCasteljau(controlPoints, i / curveResolution));
      }
    } else {
      // Catmull-Rom C1 interpolating spline through all fit points
      final pts = <Offset>[
        isClosed ? controlPoints.last : controlPoints.first,
        ...controlPoints,
        isClosed ? controlPoints.first : controlPoints.last,
        if (isClosed) controlPoints[1],
      ];
      const int subSteps = 12;
      for (int i = 0; i < pts.length - 3; i++) {
        final p0 = pts[i];
        final p1 = pts[i + 1];
        final p2 = pts[i + 2];
        final p3 = pts[i + 3];
        for (int s = 0; s <= subSteps; s++) {
          if (i > 0 && s == 0) continue;
          final t = s / subSteps;
          final t2 = t * t;
          final t3 = t2 * t;
          final x = 0.5 * ((2.0 * p1.dx) + (-p0.dx + p2.dx) * t + (2.0 * p0.dx - 5.0 * p1.dx + 4.0 * p2.dx - p3.dx) * t2 + (-p0.dx + 3.0 * p1.dx - 3.0 * p2.dx + p3.dx) * t3);
          final y = 0.5 * ((2.0 * p1.dy) + (-p0.dy + p2.dy) * t + (2.0 * p0.dy - 5.0 * p1.dy + 4.0 * p2.dy - p3.dy) * t2 + (-p0.dy + 3.0 * p1.dy - 3.0 * p2.dy + p3.dy) * t3);
          sampled.add(Offset(x, y));
        }
      }
    }

    final segs = <CADLineSegment>[];
    for (int i = 0; i < sampled.length - 1; i++) {
      segs.add(CADLineSegment(id: '${id}_sp_$i', start: sampled[i], end: sampled[i + 1], isConstruction: isConstruction));
    }
    return segs;
  }

  static Offset _deCasteljau(List<Offset> pts, double t) {
    List<Offset> work = List.from(pts);
    while (work.length > 1) {
      final next = <Offset>[];
      for (int i = 0; i < work.length - 1; i++) {
        next.add(Offset.lerp(work[i], work[i + 1], t)!);
      }
      work = next;
    }
    return work.first;
  }
}

/// 10. Sketch Obround Slot (08_sketch_modify/07_slot.svg)
/// True Onshape Slot: Centerline from [startCenter] to [endCenter] with [diameter] (two parallel lines + two 180° semicircular caps).
class CADSlotEntity extends CADPrimitiveEntity {
  Offset startCenter;
  Offset endCenter;
  double diameter;

  CADSlotEntity({
    required super.id,
    required this.startCenter,
    required this.endCenter,
    this.diameter = 20.0,
    super.isSelected,
    super.isConstruction,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  double get radius => diameter * 0.5;

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 32}) {
    final axis = endCenter - startCenter;
    final len = axis.distance;
    final u = len > 1e-5 ? axis / len : const Offset(1.0, 0.0);
    final n = Offset(-u.dy, u.dx);
    final r = radius;
    final baseAngle = math.atan2(n.dy, n.dx);

    final pts = <Offset>[];
    final capSteps = math.max(8, curveResolution ~/ 2);

    // End cap around endCenter from -n to +n
    for (int i = 0; i <= capSteps; i++) {
      final a = (baseAngle - math.pi) + math.pi * (i / capSteps);
      pts.add(endCenter + Offset(math.cos(a), math.sin(a)) * r);
    }
    // Start cap around startCenter from +n to -n
    for (int i = 0; i <= capSteps; i++) {
      final a = baseAngle + math.pi * (i / capSteps);
      pts.add(startCenter + Offset(math.cos(a), math.sin(a)) * r);
    }

    final segs = <CADLineSegment>[];
    for (int i = 0; i < pts.length; i++) {
      segs.add(CADLineSegment(
        id: '${id}_slot_$i',
        start: pts[i],
        end: pts[(i + 1) % pts.length],
        isConstruction: isConstruction,
      ));
    }
    return segs;
  }
}

/// 11. Standalone Sketch Point (07_point_text_project/01_point.svg)
class CADPointEntity extends CADPrimitiveEntity {
  Offset position;

  CADPointEntity({
    required super.id,
    required this.position,
    super.isSelected,
    super.isProjected,
    super.sourceEntityId,
  }) : super(isConstruction: true);

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) => const [];
}

/// 12. Parametric 2D Sketch Text Entity (07_point_text_project/02_text.svg)
class CADTextEntity extends CADPrimitiveEntity {
  Offset origin;
  String text;
  double heightMm;

  CADTextEntity({
    required super.id,
    required this.origin,
    required this.text,
    this.heightMm = 15.0,
    super.isSelected,
    super.isConstruction,
  });

  double get widthMm => math.max(heightMm, text.length * heightMm * 0.62);

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    // Bounding frame for extrusion/engraving profile
    final p1 = origin;
    final p2 = Offset(origin.dx + widthMm, origin.dy);
    final p3 = Offset(origin.dx + widthMm, origin.dy + heightMm);
    final p4 = Offset(origin.dx, origin.dy + heightMm);
    return [
      CADLineSegment(id: '${id}_t0', start: p1, end: p2, isConstruction: isConstruction),
      CADLineSegment(id: '${id}_t1', start: p2, end: p3, isConstruction: isConstruction),
      CADLineSegment(id: '${id}_t2', start: p3, end: p4, isConstruction: isConstruction),
      CADLineSegment(id: '${id}_t3', start: p4, end: p1, isConstruction: isConstruction),
    ];
  }
}
