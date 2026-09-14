// =============================================================================
// reference_geometry.dart
//
// Reference and Construction Geometry Model per Phase 1 Master Guide
// Sections 12, 13, 14 & Set 01.
//
// Models non-manufacturing geometry used to define design intent:
// - Construction lines (dashed, excluded from CAM laser/punch cutting)
// - Centerlines (CENTER_X, CENTER_Y for symmetry and hole alignments)
// - Reference edges (EDGE_LEFT, EDGE_RIGHT, EDGE_TOP, EDGE_BOTTOM)
// - Reference points & reference axes
// =============================================================================

import '../cad_primitives.dart';

enum ReferenceGeometryType {
  constructionLine,
  centerline,
  referenceEdge,
  constructionPoint,
  referenceAxis,
}

class ReferenceGeometry {
  final String id;
  final String name;
  final ReferenceGeometryType type;
  final CadPoint2D p1;
  final CadPoint2D p2;
  final bool isInfinite;
  final bool isLocked;
  final bool isVisible;
  final String? parentPartId;

  /// Crucial rule per Guide Section 12: Construction geometry must never become
  /// physical manufacturing cut lines or toolpaths.
  bool get isManufacturingExcluded => true;

  const ReferenceGeometry({
    required this.id,
    required this.name,
    required this.type,
    required this.p1,
    required this.p2,
    this.isInfinite = false,
    this.isLocked = false,
    this.isVisible = true,
    this.parentPartId,
  });

  /// Factory for a vertical centerline at given X coordinate
  factory ReferenceGeometry.centerlineX({
    required double x,
    required double minY,
    required double maxY,
    String id = 'CENTER_X',
    String? parentPartId,
  }) =>
      ReferenceGeometry(
        id: id,
        name: 'Centerline X',
        type: ReferenceGeometryType.centerline,
        p1: CadPoint2D(x, minY),
        p2: CadPoint2D(x, maxY),
        isInfinite: true,
        parentPartId: parentPartId,
      );

  /// Factory for a horizontal centerline at given Y coordinate
  factory ReferenceGeometry.centerlineY({
    required double y,
    required double minX,
    required double maxX,
    String id = 'CENTER_Y',
    String? parentPartId,
  }) =>
      ReferenceGeometry(
        id: id,
        name: 'Centerline Y',
        type: ReferenceGeometryType.centerline,
        p1: CadPoint2D(minX, y),
        p2: CadPoint2D(maxX, y),
        isInfinite: true,
        parentPartId: parentPartId,
      );

  /// Factory for a standard reference edge (e.g. EDGE_LEFT, EDGE_BOTTOM)
  factory ReferenceGeometry.edge({
    required String id,
    required String name,
    required CadPoint2D p1,
    required CadPoint2D p2,
    String? parentPartId,
  }) =>
      ReferenceGeometry(
        id: id,
        name: name,
        type: ReferenceGeometryType.referenceEdge,
        p1: p1,
        p2: p2,
        isInfinite: false,
        parentPartId: parentPartId,
      );

  CadPoint2D get midpoint => CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);

  double get length => p1.distanceTo(p2);

  double get angleRad => (p2.y - p1.y).abs() < 1e-6 && (p2.x - p1.x).abs() < 1e-6
      ? 0.0
      : (p2.y - p1.y) == 0.0 && p2.x >= p1.x
          ? 0.0
          : (p2.x - p1.x) == 0.0
              ? (p2.y >= p1.y ? 1.57079632679 : -1.57079632679)
              : (p2.y - p1.y) / (p2.x - p1.x);

  bool get isVertical => (p1.x - p2.x).abs() < 1e-4;
  bool get isHorizontal => (p1.y - p2.y).abs() < 1e-4;

  ReferenceGeometry copyWith({
    String? id,
    String? name,
    ReferenceGeometryType? type,
    CadPoint2D? p1,
    CadPoint2D? p2,
    bool? isInfinite,
    bool? isLocked,
    bool? isVisible,
    String? parentPartId,
  }) {
    return ReferenceGeometry(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      isInfinite: isInfinite ?? this.isInfinite,
      isLocked: isLocked ?? this.isLocked,
      isVisible: isVisible ?? this.isVisible,
      parentPartId: parentPartId ?? this.parentPartId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'p1': p1.toJson(),
        'p2': p2.toJson(),
        'isInfinite': isInfinite,
        'isLocked': isLocked,
        'isVisible': isVisible,
        if (parentPartId != null) 'parentPartId': parentPartId,
      };

  factory ReferenceGeometry.fromJson(Map<String, dynamic> json) =>
      ReferenceGeometry(
        id: json['id'] as String,
        name: json['name'] as String,
        type: ReferenceGeometryType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ReferenceGeometryType.constructionLine,
        ),
        p1: CadPoint2D.fromJson(json['p1'] as Map<String, dynamic>),
        p2: CadPoint2D.fromJson(json['p2'] as Map<String, dynamic>),
        isInfinite: json['isInfinite'] as bool? ?? false,
        isLocked: json['isLocked'] as bool? ?? false,
        isVisible: json['isVisible'] as bool? ?? true,
        parentPartId: json['parentPartId'] as String?,
      );
}
