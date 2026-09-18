// =============================================================================
// cad_primitives.dart
//
// Standalone 2D and 3D geometric primitives for Sheet Metal Studio.
// Designed with zero dependencies on external app code so this entire module
// can be copied into any standalone Flutter/Dart application.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

export 'cad_geometry.dart' show CadArc2D;

/// 2D Coordinate Point (in mm)
@immutable
class CadPoint2D {
  final double x;
  final double y;

  const CadPoint2D(this.x, this.y);

  CadPoint2D operator +(CadPoint2D other) =>
      CadPoint2D(x + other.x, y + other.y);
  CadPoint2D operator -(CadPoint2D other) =>
      CadPoint2D(x - other.x, y - other.y);
  CadPoint2D operator *(double scale) => CadPoint2D(x * scale, y * scale);

  double get length => math.sqrt(x * x + y * y);

  double distanceTo(CadPoint2D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  Offset toOffset() => Offset(x, y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory CadPoint2D.fromJson(Map<String, dynamic> json) =>
      CadPoint2D((json['x'] as num).toDouble(), (json['y'] as num).toDouble());

  @override
  String toString() => 'CadPoint2D($x, $y)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CadPoint2D &&
          (x - other.x).abs() < 1e-4 &&
          (y - other.y).abs() < 1e-4;

  @override
  int get hashCode => Object.hash(x.round(), y.round());
}

/// 3D Coordinate Point (in mm)
@immutable
class CadPoint3D {
  final double x;
  final double y;
  final double z;

  const CadPoint3D(this.x, this.y, this.z);

  CadPoint3D operator +(CadPoint3D other) =>
      CadPoint3D(x + other.x, y + other.y, z + other.z);
  CadPoint3D operator -(CadPoint3D other) =>
      CadPoint3D(x - other.x, y - other.y, z - other.z);
  CadPoint3D operator *(double scale) =>
      CadPoint3D(x * scale, y * scale, z * scale);

  double dot(CadPoint3D other) => x * other.x + y * other.y + z * other.z;

  CadPoint3D cross(CadPoint3D other) => CadPoint3D(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  double get length => math.sqrt(x * x + y * y + z * z);
  double distanceTo(CadPoint3D other) => (this - other).length;

  CadPoint3D normalized() {
    final len = length;
    if (len < 1e-6) return const CadPoint3D(0, 0, 1);
    return CadPoint3D(x / len, y / len, z / len);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};
  factory CadPoint3D.fromJson(Map<String, dynamic> json) => CadPoint3D(
    (json['x'] as num).toDouble(),
    (json['y'] as num).toDouble(),
    (json['z'] as num).toDouble(),
  );

  @override
  String toString() => 'CadPoint3D($x, $y, $z)';
}

/// 3D Polygon Face for Shaded Rendering
class CadFoldedPolygon3D {
  final String faceId;
  final List<CadPoint3D> vertices;
  final CadPoint3D normal;
  final Color color;
  final bool drawWireframe;
  final List<List<CadPoint3D>> holes;
  final List<String> holePunchIds;
  final List<List<CadPoint3D>> cutSegments;
  final List<List<CadPoint3D>> boundaryLines;

  const CadFoldedPolygon3D({
    required this.faceId,
    required this.vertices,
    required this.normal,
    this.color = const Color(0xFFB0BEC5),
    this.drawWireframe = true,
    this.holes = const [],
    this.holePunchIds = const [],
    this.cutSegments = const [],
    this.boundaryLines = const [],
  });
}

/// 2D Line Segment (used for Laser Cut Lines, Slits, Partition Edges)
@immutable
class CadLineSegment {
  final String id;
  final CadPoint2D p1;
  final CadPoint2D p2;
  final String layer;
  final bool showLabel;

  const CadLineSegment({
    required this.id,
    required this.p1,
    required this.p2,
    this.layer = 'CUT',
    this.showLabel = true,
  });

  double get x1 => p1.x;
  double get y1 => p1.y;
  double get x2 => p2.x;
  double get y2 => p2.y;
  bool get isVisible => true;

  double get length => p1.distanceTo(p2);
  double get angleRad => math.atan2(p2.y - p1.y, p2.x - p1.x);
  double get angleDeg => angleRad * 180.0 / math.pi;
  CadPoint2D get midpoint =>
      CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);

  CadLineSegment copyWith({
    String? id,
    CadPoint2D? p1,
    CadPoint2D? p2,
    String? layer,
    bool? showLabel,
  }) {
    return CadLineSegment(
      id: id ?? this.id,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      layer: layer ?? this.layer,
      showLabel: showLabel ?? this.showLabel,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'p1': p1.toJson(),
    'p2': p2.toJson(),
    'layer': layer,
    'showLabel': showLabel,
  };

  factory CadLineSegment.fromJson(Map<String, dynamic> json) => CadLineSegment(
    id: json['id'] as String? ?? 'C1',
    p1: CadPoint2D.fromJson(json['p1'] as Map<String, dynamic>),
    p2: CadPoint2D.fromJson(json['p2'] as Map<String, dynamic>),
    layer: json['layer'] as String? ?? 'CUT',
    showLabel: json['showLabel'] as bool? ?? true,
  );

  @override
  String toString() => 'CadLineSegment($id, p1: $p1, p2: $p2, layer: $layer, showLabel: $showLabel)';
}
