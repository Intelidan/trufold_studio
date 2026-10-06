import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Supported types of CAD vector entities in the 2D drafting engine.
enum VectorCadEntityType {
  line,
  rect,
  circle,
  polyline,
  bend,
}

/// Base class for all vector entities rendered and edited on the 2D CAD canvas.
abstract class VectorCadEntity {
  final String id;
  final String label;
  final VectorCadEntityType type;
  final Color color;
  final double strokeWidth;
  final bool isSelected;
  final bool isLocked;
  final String layer;

  const VectorCadEntity({
    required this.id,
    required this.label,
    required this.type,
    this.color = const Color(0xFF00FFCC),
    this.strokeWidth = 2.0,
    this.isSelected = false,
    this.isLocked = false,
    this.layer = '0',
  });

  Rect get bounds;
  double get perimeter;
  double get area;

  bool hitTest(Offset pt, double tolerance);
  VectorCadEntity offsetBy(Offset delta);
  VectorCadEntity copyWith({bool? isSelected, Color? color, double? strokeWidth, bool? isLocked});
  Map<String, dynamic> toJson();
}

/// Linear CAD line segment (contour edge, cut line, or drafting construction).
class VectorCadLine extends VectorCadEntity {
  final Offset p1;
  final Offset p2;
  final bool isDashed;
  final String role; // 'perimeter', 'cut', 'bend', 'flange', 'construction'
  final double bendAngleDeg;
  final String bendDirection; // 'UP', 'DOWN'

  const VectorCadLine({
    required super.id,
    required super.label,
    super.type = VectorCadEntityType.line,
    super.color = const Color(0xFF00FFCC),
    super.strokeWidth = 2.0,
    super.isSelected = false,
    super.isLocked = false,
    super.layer = 'OUTLINE',
    required this.p1,
    required this.p2,
    this.isDashed = false,
    this.role = 'perimeter',
    this.bendAngleDeg = 0.0,
    this.bendDirection = 'UP',
  });

  double get length => (p2 - p1).distance;

  @override
  Rect get bounds => Rect.fromPoints(p1, p2).inflate(strokeWidth / 2);

  @override
  double get perimeter => length;

  @override
  double get area => 0.0;

  @override
  bool hitTest(Offset pt, double tolerance) {
    final dist = _distToSegment(pt, p1, p2);
    return dist <= tolerance;
  }

  @override
  VectorCadLine offsetBy(Offset delta) {
    return VectorCadLine(
      id: id,
      label: label,
      type: type,
      color: color,
      strokeWidth: strokeWidth,
      isSelected: isSelected,
      isLocked: isLocked,
      layer: layer,
      p1: p1 + delta,
      p2: p2 + delta,
      isDashed: isDashed,
      role: role,
      bendAngleDeg: bendAngleDeg,
      bendDirection: bendDirection,
    );
  }

  @override
  VectorCadLine copyWith({
    bool? isSelected,
    Color? color,
    double? strokeWidth,
    bool? isLocked,
    Offset? p1,
    Offset? p2,
    bool? isDashed,
    String? role,
    double? bendAngleDeg,
    String? bendDirection,
  }) {
    return VectorCadLine(
      id: id,
      label: label,
      type: type,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isSelected: isSelected ?? this.isSelected,
      isLocked: isLocked ?? this.isLocked,
      layer: layer,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      isDashed: isDashed ?? this.isDashed,
      role: role ?? this.role,
      bendAngleDeg: bendAngleDeg ?? this.bendAngleDeg,
      bendDirection: bendDirection ?? this.bendDirection,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'line',
        'label': label,
        'x1': p1.dx,
        'y1': p1.dy,
        'x2': p2.dx,
        'y2': p2.dy,
        'length': length,
        'role': role,
        'bendAngleDeg': bendAngleDeg,
      };

  static double _distToSegment(Offset p, Offset v, Offset w) {
    final l2 = (v - w).distanceSquared;
    if (l2 < 1e-6) return (p - v).distance;
    final t = (((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2).clamp(0.0, 1.0);
    final projection = Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy));
    return (p - projection).distance;
  }
}

/// Rectangular sheet metal face or cutout plate.
class VectorCadRect extends VectorCadEntity {
  final Offset p1; // Top-left anchor
  final Offset p2; // Bottom-right anchor
  final bool isFilled;
  final Color? fillColor;
  final String faceId;
  final String faceRole; // 'base', 'flange', 'sidewall', 'cover'

  const VectorCadRect({
    required super.id,
    required super.label,
    super.type = VectorCadEntityType.rect,
    super.color = const Color(0xFF00FFCC),
    super.strokeWidth = 2.0,
    super.isSelected = false,
    super.isLocked = false,
    super.layer = 'FACES',
    required this.p1,
    required this.p2,
    this.isFilled = true,
    this.fillColor,
    this.faceId = '',
    this.faceRole = 'base',
  });

  Rect get rect => Rect.fromPoints(p1, p2);

  double get width => rect.width;
  double get height => rect.height;

  @override
  Rect get bounds => rect.inflate(strokeWidth / 2);

  @override
  double get perimeter => 2.0 * (width + height);

  @override
  double get area => width * height;

  @override
  bool hitTest(Offset pt, double tolerance) {
    final r = rect;
    // Edge hit or interior hit
    final onEdge = (pt.dx >= r.left - tolerance && pt.dx <= r.right + tolerance &&
            ( (pt.dy - r.top).abs() <= tolerance || (pt.dy - r.bottom).abs() <= tolerance )) ||
        (pt.dy >= r.top - tolerance && pt.dy <= r.bottom + tolerance &&
            ( (pt.dx - r.left).abs() <= tolerance || (pt.dx - r.right).abs() <= tolerance ));
    return onEdge || r.contains(pt);
  }

  @override
  VectorCadRect offsetBy(Offset delta) {
    return VectorCadRect(
      id: id,
      label: label,
      type: type,
      color: color,
      strokeWidth: strokeWidth,
      isSelected: isSelected,
      isLocked: isLocked,
      layer: layer,
      p1: p1 + delta,
      p2: p2 + delta,
      isFilled: isFilled,
      fillColor: fillColor,
      faceId: faceId,
      faceRole: faceRole,
    );
  }

  @override
  VectorCadRect copyWith({
    bool? isSelected,
    Color? color,
    double? strokeWidth,
    bool? isLocked,
    Offset? p1,
    Offset? p2,
    bool? isFilled,
    Color? fillColor,
    String? faceId,
    String? faceRole,
  }) {
    return VectorCadRect(
      id: id,
      label: label,
      type: type,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isSelected: isSelected ?? this.isSelected,
      isLocked: isLocked ?? this.isLocked,
      layer: layer,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      isFilled: isFilled ?? this.isFilled,
      fillColor: fillColor ?? this.fillColor,
      faceId: faceId ?? this.faceId,
      faceRole: faceRole ?? this.faceRole,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'rect',
        'label': label,
        'x1': p1.dx,
        'y1': p1.dy,
        'x2': p2.dx,
        'y2': p2.dy,
        'width': width,
        'height': height,
        'perimeter': perimeter,
        'area': area,
        'faceRole': faceRole,
      };
}

/// Circular hole punch or round feature.
class VectorCadCircle extends VectorCadEntity {
  final Offset center;
  final double radius;
  final bool isFilled;
  final Color? fillColor;
  final bool isPunch;
  final String punchId;
  final String punchRole; // 'coupler', 'pilot', 'bolt', 'knockout'

  const VectorCadCircle({
    required super.id,
    required super.label,
    super.type = VectorCadEntityType.circle,
    super.color = const Color(0xFF00FFCC),
    super.strokeWidth = 2.0,
    super.isSelected = false,
    super.isLocked = false,
    super.layer = 'PUNCHES',
    required this.center,
    required this.radius,
    this.isFilled = true,
    this.fillColor,
    this.isPunch = true,
    this.punchId = '',
    this.punchRole = 'coupler',
  });

  double get diameter => radius * 2.0;

  @override
  Rect get bounds => Rect.fromCircle(center: center, radius: radius + strokeWidth / 2);

  @override
  double get perimeter => 2.0 * math.pi * radius;

  @override
  double get area => math.pi * radius * radius;

  @override
  bool hitTest(Offset pt, double tolerance) {
    final dist = (pt - center).distance;
    return (dist - radius).abs() <= tolerance || dist <= radius;
  }

  @override
  VectorCadCircle offsetBy(Offset delta) {
    return VectorCadCircle(
      id: id,
      label: label,
      type: type,
      color: color,
      strokeWidth: strokeWidth,
      isSelected: isSelected,
      isLocked: isLocked,
      layer: layer,
      center: center + delta,
      radius: radius,
      isFilled: isFilled,
      fillColor: fillColor,
      isPunch: isPunch,
      punchId: punchId,
      punchRole: punchRole,
    );
  }

  @override
  VectorCadCircle copyWith({
    bool? isSelected,
    Color? color,
    double? strokeWidth,
    bool? isLocked,
    Offset? center,
    double? radius,
    bool? isFilled,
    Color? fillColor,
    bool? isPunch,
    String? punchId,
    String? punchRole,
  }) {
    return VectorCadCircle(
      id: id,
      label: label,
      type: type,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isSelected: isSelected ?? this.isSelected,
      isLocked: isLocked ?? this.isLocked,
      layer: layer,
      center: center ?? this.center,
      radius: radius ?? this.radius,
      isFilled: isFilled ?? this.isFilled,
      fillColor: fillColor ?? this.fillColor,
      isPunch: isPunch ?? this.isPunch,
      punchId: punchId ?? this.punchId,
      punchRole: punchRole ?? this.punchRole,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'circle',
        'label': label,
        'cx': center.dx,
        'cy': center.dy,
        'radius': radius,
        'diameter': diameter,
        'perimeter': perimeter,
        'area': area,
        'punchRole': punchRole,
      };
}

/// Arbitrary polygon or multi-segment blank perimeter.
class VectorCadPolyline extends VectorCadEntity {
  final List<Offset> points;
  final bool isClosed;
  final bool isFilled;
  final Color? fillColor;

  const VectorCadPolyline({
    required super.id,
    required super.label,
    super.type = VectorCadEntityType.polyline,
    super.color = const Color(0xFF00FFCC),
    super.strokeWidth = 2.0,
    super.isSelected = false,
    super.isLocked = false,
    super.layer = 'OUTLINE',
    required this.points,
    this.isClosed = true,
    this.isFilled = false,
    this.fillColor,
  });

  @override
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.dx, maxX = points.first.dx;
    double minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(strokeWidth / 2);
  }

  @override
  double get perimeter {
    if (points.length < 2) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      sum += (points[i + 1] - points[i]).distance;
    }
    if (isClosed && points.length > 2) {
      sum += (points.first - points.last).distance;
    }
    return sum;
  }

  @override
  double get area {
    if (points.length < 3 || !isClosed) return 0.0;
    double a = 0.0;
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      a += (p1.dx * p2.dy - p2.dx * p1.dy);
    }
    return a.abs() / 2.0;
  }

  @override
  bool hitTest(Offset pt, double tolerance) {
    if (points.length < 2) return false;
    for (int i = 0; i < points.length - 1; i++) {
      if (VectorCadLine._distToSegment(pt, points[i], points[i + 1]) <= tolerance) return true;
    }
    if (isClosed && points.length > 2) {
      if (VectorCadLine._distToSegment(pt, points.last, points.first) <= tolerance) return true;
    }
    return false;
  }

  @override
  VectorCadPolyline offsetBy(Offset delta) {
    return VectorCadPolyline(
      id: id,
      label: label,
      type: type,
      color: color,
      strokeWidth: strokeWidth,
      isSelected: isSelected,
      isLocked: isLocked,
      layer: layer,
      points: points.map((p) => p + delta).toList(),
      isClosed: isClosed,
      isFilled: isFilled,
      fillColor: fillColor,
    );
  }

  @override
  VectorCadPolyline copyWith({
    bool? isSelected,
    Color? color,
    double? strokeWidth,
    bool? isLocked,
    List<Offset>? points,
    bool? isClosed,
    bool? isFilled,
    Color? fillColor,
  }) {
    return VectorCadPolyline(
      id: id,
      label: label,
      type: type,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isSelected: isSelected ?? this.isSelected,
      isLocked: isLocked ?? this.isLocked,
      layer: layer,
      points: points ?? this.points,
      isClosed: isClosed ?? this.isClosed,
      isFilled: isFilled ?? this.isFilled,
      fillColor: fillColor ?? this.fillColor,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'polyline',
        'label': label,
        'pointsCount': points.length,
        'perimeter': perimeter,
        'area': area,
      };
}
