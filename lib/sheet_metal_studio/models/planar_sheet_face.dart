// =============================================================================
// planar_sheet_face.dart
//
// Represents an individual planar polygon panel in the unfolded sheet metal blank.
// Part of the kinematic tree.
// =============================================================================

import 'cad_primitives.dart';

/// Semantic role of the face within the sheet metal part
enum FaceRole {
  baseFloor, // Stationary ground anchor face (Z = 0)
  sideWall, // Vertical or angled side wall
  returnFlange, // Stiffening return lip / flange
  mountingTab, // Stamped bracket mounting ear
  coverPanel, // Top cover sheet
  custom, // General planar panel
}

class PlanarSheetFace {
  final String id;
  final String label;
  final List<CadPoint2D> vertices;
  final FaceRole role;
  final bool isBaseAnchor;
  final List<List<CadPoint2D>> holes;
  final String layer;
  final bool showLabel;
  final bool isVisible;

  const PlanarSheetFace({
    required this.id,
    this.label = '',
    required this.vertices,
    this.role = FaceRole.custom,
    this.isBaseAnchor = false,
    this.holes = const [],
    this.layer = 'FACES',
    this.showLabel = true,
    this.isVisible = true,
  });

  /// Approximate centroid of the planar face
  CadPoint2D get centroid {
    if (vertices.isEmpty) return const CadPoint2D(0, 0);
    double sx = 0.0, sy = 0.0;
    for (final v in vertices) {
      sx += v.x;
      sy += v.y;
    }
    return CadPoint2D(sx / vertices.length, sy / vertices.length);
  }

  /// Surface area of the outer face polygon in mm² (shoelace formula)
  double get areaMm2 {
    if (vertices.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < vertices.length; i++) {
      final j = (i + 1) % vertices.length;
      area += vertices[i].x * vertices[j].y - vertices[j].x * vertices[i].y;
    }
    return (area / 2.0).abs();
  }

  PlanarSheetFace copyWith({
    String? id,
    String? label,
    List<CadPoint2D>? vertices,
    FaceRole? role,
    bool? isBaseAnchor,
    List<List<CadPoint2D>>? holes,
    String? layer,
    bool? showLabel,
    bool? isVisible,
  }) {
    return PlanarSheetFace(
      id: id ?? this.id,
      label: label ?? this.label,
      vertices: vertices ?? this.vertices,
      role: role ?? this.role,
      isBaseAnchor: isBaseAnchor ?? this.isBaseAnchor,
      holes: holes ?? this.holes,
      layer: layer ?? this.layer,
      showLabel: showLabel ?? this.showLabel,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'vertices': vertices.map((v) => v.toJson()).toList(),
    'role': role.name,
    'isBaseAnchor': isBaseAnchor,
    'holes': holes.map((loop) => loop.map((v) => v.toJson()).toList()).toList(),
    'layer': layer,
    'showLabel': showLabel,
    'isVisible': isVisible,
  };

  factory PlanarSheetFace.fromJson(Map<String, dynamic> json) =>
      PlanarSheetFace(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        vertices: (json['vertices'] as List? ?? [])
            .map((e) => CadPoint2D.fromJson(e as Map<String, dynamic>))
            .toList(),
        role: FaceRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => FaceRole.custom,
        ),
        isBaseAnchor: json['isBaseAnchor'] as bool? ?? false,
        holes: (json['holes'] as List? ?? [])
            .map(
              (loop) => (loop as List)
                  .map((e) => CadPoint2D.fromJson(e as Map<String, dynamic>))
                  .toList(),
            )
            .toList(),
        layer: json['layer'] as String? ?? 'FACES',
        showLabel: json['showLabel'] as bool? ?? true,
        isVisible: json['isVisible'] as bool? ?? true,
      );
}
