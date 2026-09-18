// =============================================================================
// cnc_punch_primitive.dart
//
// Predefined CNC Turret Punch tools (Round, Obround/Slot, Square, Cluster).
// Generates exact 2D boundary polygons for rendering, DXF cutting, and 3D holes.
// =============================================================================

import 'dart:math' as math;

import 'cad_primitives.dart';

enum PunchType {
  roundHole,
  obroundSlot,
  square,
  rectangle,
  cluster,
  compound,
  ellipse;

  String get name => toString().split('.').last;
}

enum CncPunchRole {
  general,
  coupler,
  perforation,
  manufacturing,
  reference;

  String get name => toString().split('.').last;
}

class CncPunchPrimitive {
  final String id;
  final PunchType type;
  final CadPoint2D center;
  final double widthMm;
  final double lengthMm;
  final double diameterMm;
  final double rotationDeg;
  // Array parameters for perforation clusters
  final double spacingX;
  final double spacingY;
  final int countX;
  final int countY;
  final String layer;
  final List<CadPoint2D>? customBoundary;
  final bool showLabel;
  final bool isVisible;
  final CncPunchRole role;
  final String? parentFaceId;
  final String? associatedPortId;

  const CncPunchPrimitive({
    required this.id,
    required this.type,
    required this.center,
    this.widthMm = 7.0,
    this.lengthMm = 25.0,
    this.diameterMm = 8.0,
    this.rotationDeg = 0.0,
    this.spacingX = 0.0,
    this.spacingY = 0.0,
    this.countX = 1,
    this.countY = 1,
    this.layer = 'HOLES',
    this.customBoundary,
    this.showLabel = true,
    this.isVisible = true,
    this.role = CncPunchRole.general,
    this.parentFaceId,
    this.associatedPortId,
  });

  bool get isRound => type == PunchType.roundHole;
  bool get isSlot => type == PunchType.obroundSlot;
  bool get isEllipse => type == PunchType.ellipse;
  bool get isCoupler => role == CncPunchRole.coupler;
  bool get isPerforation => role == CncPunchRole.perforation;
  double get angleDeg => rotationDeg;
  PunchType get shape => type;

  /// Factory for standard round hole (e.g. M6, M8, M10 bolt clearance)
  factory CncPunchPrimitive.round({
    required String id,
    required CadPoint2D center,
    double diameterMm = 8.0,
    String layer = 'HOLES',
    bool showLabel = true,
    bool isVisible = true,
  }) => CncPunchPrimitive(id: id, type: PunchType.roundHole, center: center, diameterMm: diameterMm, layer: layer, showLabel: showLabel, isVisible: isVisible);

  /// Factory for standard Cable Tray Obround Slot (e.g. 7x25mm or 9x25mm)
  factory CncPunchPrimitive.obround({
    required String id,
    required CadPoint2D center,
    double widthMm = 7.0,
    double lengthMm = 25.0,
    double rotationDeg = 0.0,
    String layer = 'HOLES',
    bool showLabel = true,
    bool isVisible = true,
  }) => CncPunchPrimitive(
    id: id,
    type: PunchType.obroundSlot,
    center: center,
    widthMm: widthMm,
    lengthMm: lengthMm,
    rotationDeg: rotationDeg,
    layer: layer,
    showLabel: showLabel,
    isVisible: isVisible,
  );

  /// Factory for standard Ellipse punch hole (major axis lengthMm, minor axis widthMm)
  factory CncPunchPrimitive.ellipse({
    required String id,
    required CadPoint2D center,
    double lengthMm = 18.0,
    double widthMm = 12.0,
    double rotationDeg = 0.0,
    String layer = 'HOLES',
    bool showLabel = true,
    bool isVisible = true,
  }) => CncPunchPrimitive(
    id: id,
    type: PunchType.ellipse,
    center: center,
    lengthMm: lengthMm,
    widthMm: widthMm,
    rotationDeg: rotationDeg,
    layer: layer,
    showLabel: showLabel,
    isVisible: isVisible,
  );

  /// Generates the list of 2D polygon vertices forming this punch's boundary.
  List<CadPoint2D> toPolygon({int circleSegments = 32}) {
    if (customBoundary != null && customBoundary!.isNotEmpty) {
      return customBoundary!;
    }

    final rad = rotationDeg * math.pi / 180.0;
    final cosR = math.cos(rad);
    final sinR = math.sin(rad);

    CadPoint2D rotate(double lx, double ly) {
      return CadPoint2D(center.x + (lx * cosR - ly * sinR), center.y + (lx * sinR + ly * cosR));
    }

    switch (type) {
      case PunchType.roundHole:
        final r = diameterMm / 2.0;
        final pts = <CadPoint2D>[];
        for (int i = 0; i < circleSegments; i++) {
          final a = (i / circleSegments) * 2 * math.pi;
          pts.add(CadPoint2D(center.x + r * math.cos(a), center.y + r * math.sin(a)));
        }
        return pts;

      case PunchType.obroundSlot:
        final w = widthMm;
        final l = lengthMm;
        final r = w / 2.0;
        final straightL = math.max(0.0, l - w);
        final halfL = straightL / 2.0;
        final pts = <CadPoint2D>[];
        final halfSegs = circleSegments ~/ 2;

        // Top arc (right side)
        for (int i = 0; i <= halfSegs; i++) {
          final a = -math.pi / 2.0 + (i / halfSegs) * math.pi;
          pts.add(rotate(halfL + r * math.cos(a), r * math.sin(a)));
        }
        // Bottom arc (left side)
        for (int i = 0; i <= halfSegs; i++) {
          final a = math.pi / 2.0 + (i / halfSegs) * math.pi;
          pts.add(rotate(-halfL + r * math.cos(a), r * math.sin(a)));
        }
        return pts;

      case PunchType.square:
      case PunchType.rectangle:
        final effW = (type == PunchType.square ? (widthMm > 0 ? widthMm : diameterMm) : widthMm);
        final effH = (type == PunchType.square ? (lengthMm > 0 ? lengthMm : (widthMm > 0 ? widthMm : diameterMm)) : lengthMm);
        final halfW = effW / 2.0;
        final halfH = effH / 2.0;
        return [rotate(-halfW, -halfH), rotate(halfW, -halfH), rotate(halfW, halfH), rotate(-halfW, halfH)];
      case PunchType.ellipse:
        final a = lengthMm / 2.0;
        final b = widthMm / 2.0;
        final segs = math.max(circleSegments, 24);
        final pts = <CadPoint2D>[];
        for (int i = 0; i < segs; i++) {
          final t = (i / segs) * 2 * math.pi;
          pts.add(rotate(a * math.cos(t), b * math.sin(t)));
        }
        return pts;

      case PunchType.compound:
        return customBoundary ?? [];
      case PunchType.cluster:
        return [];
    }
  }

  /// Surface area of the punch hole in mm²
  double get areaMm2 {
    if (customBoundary != null && customBoundary!.length >= 3) {
      double area = 0.0;
      for (int i = 0; i < customBoundary!.length; i++) {
        final j = (i + 1) % customBoundary!.length;
        area += customBoundary![i].x * customBoundary![j].y - customBoundary![j].x * customBoundary![i].y;
      }
      return (area / 2.0).abs();
    }
    switch (type) {
      case PunchType.roundHole:
        final r = diameterMm / 2.0;
        return math.pi * r * r;
      case PunchType.obroundSlot:
        final straight = math.max(0.0, lengthMm - widthMm);
        final r = widthMm / 2.0;
        return (straight * widthMm) + (math.pi * r * r);
      case PunchType.square:
        return diameterMm * diameterMm;
      case PunchType.rectangle:
        return widthMm * lengthMm;
      case PunchType.ellipse:
        return math.pi * (lengthMm / 2.0) * (widthMm / 2.0);
      case PunchType.cluster:
      case PunchType.compound:
        final poly = toPolygon();
        if (poly.length < 3) return 0.0;
        double area = 0.0;
        for (int i = 0; i < poly.length; i++) {
          final j = (i + 1) % poly.length;
          area += poly[i].x * poly[j].y - poly[j].x * poly[i].y;
        }
        return (area / 2.0).abs();
    }
  }

  CncPunchPrimitive copyWith({
    String? id,
    PunchType? type,
    CadPoint2D? center,
    double? widthMm,
    double? lengthMm,
    double? diameterMm,
    double? rotationDeg,
    double? spacingX,
    double? spacingY,
    int? countX,
    int? countY,
    String? layer,
    List<CadPoint2D>? customBoundary,
    bool? showLabel,
    bool? isVisible,
    CncPunchRole? role,
    String? parentFaceId,
    String? associatedPortId,
  }) {
    return CncPunchPrimitive(
      id: id ?? this.id,
      type: type ?? this.type,
      center: center ?? this.center,
      widthMm: widthMm ?? this.widthMm,
      lengthMm: lengthMm ?? this.lengthMm,
      diameterMm: diameterMm ?? this.diameterMm,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      spacingX: spacingX ?? this.spacingX,
      spacingY: spacingY ?? this.spacingY,
      countX: countX ?? this.countX,
      countY: countY ?? this.countY,
      layer: layer ?? this.layer,
      customBoundary: customBoundary ?? this.customBoundary,
      showLabel: showLabel ?? this.showLabel,
      isVisible: isVisible ?? this.isVisible,
      role: role ?? this.role,
      parentFaceId: parentFaceId ?? this.parentFaceId,
      associatedPortId: associatedPortId ?? this.associatedPortId,
    );
  }

  CncPunchPrimitive moveTo(CadPoint2D newCenter) {
    if (customBoundary != null) {
      final dx = newCenter.x - center.x;
      final dy = newCenter.y - center.y;
      final shifted = customBoundary!.map((p) => CadPoint2D(p.x + dx, p.y + dy)).toList();
      return copyWith(center: newCenter, customBoundary: shifted);
    }
    return copyWith(center: newCenter);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'center': center.toJson(),
    'widthMm': widthMm,
    'lengthMm': lengthMm,
    'diameterMm': diameterMm,
    'rotationDeg': rotationDeg,
    'spacingX': spacingX,
    'spacingY': spacingY,
    'countX': countX,
    'countY': countY,
    'layer': layer,
    'showLabel': showLabel,
    'isVisible': isVisible,
    'role': role.name,
    if (parentFaceId != null) 'parentFaceId': parentFaceId,
    if (associatedPortId != null) 'associatedPortId': associatedPortId,
    if (customBoundary != null) 'customBoundary': customBoundary!.map((p) => p.toJson()).toList(),
  };

  factory CncPunchPrimitive.fromJson(Map<String, dynamic> json) => CncPunchPrimitive(
    id: json['id'] as String? ?? '',
    type: PunchType.values.firstWhere((t) => t.name == json['type'], orElse: () => PunchType.roundHole),
    center: CadPoint2D.fromJson(json['center'] as Map<String, dynamic>),
    widthMm: (json['widthMm'] as num?)?.toDouble() ?? 7.0,
    lengthMm: (json['lengthMm'] as num?)?.toDouble() ?? 25.0,
    diameterMm: (json['diameterMm'] as num?)?.toDouble() ?? 8.0,
    rotationDeg: (json['rotationDeg'] as num?)?.toDouble() ?? 0.0,
    spacingX: (json['spacingX'] as num?)?.toDouble() ?? 0.0,
    spacingY: (json['spacingY'] as num?)?.toDouble() ?? 0.0,
    countX: json['countX'] as int? ?? 1,
    countY: json['countY'] as int? ?? 1,
    layer: json['layer'] as String? ?? 'HOLES',
    showLabel: json['showLabel'] as bool? ?? true,
    isVisible: json['isVisible'] as bool? ?? true,
    role: json['role'] != null
        ? CncPunchRole.values.firstWhere((r) => r.name == json['role'], orElse: () => CncPunchRole.general)
        : CncPunchRole.general,
    parentFaceId: json['parentFaceId'] as String?,
    associatedPortId: json['associatedPortId'] as String?,
    customBoundary: (json['customBoundary'] as List<dynamic>?)?.map((e) => CadPoint2D.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
