//
//1. 🗃️ Core Configuration & State Models (cad_models.dart)

// This file defines high-level data types, geometric primitives, topological trackers, constraints, and undo/redo snapshot mementos.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

enum SketchEntityType { line, rectangle, circle, polyline }

enum FeatureType { extrude, cut }

enum WeldJointStyle { buttJoint, lapJoint, tJoint }

enum CADConstraintType { horizontal, vertical, perpendicular }

/// Represents a targeted local coordinate system bound to a 3D face or baseline plane
class CADSketchPlane {
  final String id;
  final vm.Vector3 origin;
  final vm.Vector3 normal;
  final vm.Vector3 up;
  final List<CADLineSegment> entities = [];
  final List<CADPrimitiveEntity> primitives = [];
  String? targetPartId;
  String? targetFaceId;

  CADSketchPlane({
    required this.id,
    required this.origin,
    required this.normal,
    required this.up,
    this.targetPartId,
    this.targetFaceId,
  });

  vm.Vector3 get xAxis => up.normalized().cross(normal.normalized()).normalized();
  vm.Vector3 get yAxis => up.normalized();
  vm.Vector3 get zAxis => normal.normalized();

  vm.Vector3 toWorld(Offset local) => origin + (xAxis * local.dx) + (yAxis * local.dy);
  Offset toLocal(vm.Vector3 world) {
    final d = world - origin;
    return Offset(d.dot(xAxis), d.dot(yAxis));
  }
}

/// Abstract base class mapping all structural 2D CAD entities
abstract class CADPrimitiveEntity {
  final String id;
  bool isSelected;
  bool isConstruction;
  FeatureType featureType;
  bool isPassThrough;
  double depthMm;

  CADPrimitiveEntity({
    required this.id,
    this.isSelected = false,
    this.isConstruction = false,
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

  CADLineSegment({required this.id, required this.start, required this.end, this.isDeleted = false, this.isConstruction = false});

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
      CADLineSegment(id: "${id}_top", start: p1, end: p2, isConstruction: isConstruction),
      CADLineSegment(id: "${id}_right", start: p2, end: p3, isConstruction: isConstruction),
      CADLineSegment(id: "${id}_bottom", start: p3, end: p4, isConstruction: isConstruction),
      CADLineSegment(id: "${id}_left", start: p4, end: p1, isConstruction: isConstruction),
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
      segments.add(CADLineSegment(id: "${id}_arc_$i", start: previousPoint, end: currentPoint, isConstruction: isConstruction));
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
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    return [CADLineSegment(id: id, start: start, end: end, isConstruction: isConstruction)];
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
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    final segments = <CADLineSegment>[];
    if (points.length < 2) return segments;
    for (int i = 0; i < points.length - 1; i++) {
      segments.add(CADLineSegment(id: '${id}_seg_$i', start: points[i], end: points[i + 1], isConstruction: isConstruction));
    }
    if (isClosed && points.length > 2) {
      segments.add(CADLineSegment(id: '${id}_seg_close', start: points.last, end: points.first, isConstruction: isConstruction));
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
