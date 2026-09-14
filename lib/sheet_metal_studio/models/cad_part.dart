// =============================================================================
// cad_part.dart
//
// Represents a single manufacturable sheet metal blank / component.
// Holds geometry, features, dimensions, constraints, material, and flat blank bounds.
// =============================================================================

import 'cad_primitives.dart';
import 'cad_geometry.dart';
import 'cad_feature.dart';
import 'cad_dimension.dart';
import 'cad_constraint.dart';
import 'cad_parameter.dart';
import 'sheet_metal_material.dart';

class CadPart {
  final String id;
  final String name;
  final SheetMetalMaterial material;
  final List<CadPoint2D> outerContour;
  final List<CadGeometry> geometries;
  final List<CadFeature> features;
  final List<CadDimension> dimensions;
  final List<CadConstraint> constraints;
  final Map<String, CadParameter> parameters;
  final double flatBlankWidth;
  final double flatBlankLength;
  final bool isModified;

  const CadPart({
    required this.id,
    required this.name,
    this.material = const SheetMetalMaterial(),
    this.outerContour = const [],
    this.geometries = const [],
    this.features = const [],
    this.dimensions = const [],
    this.constraints = const [],
    this.parameters = const {},
    this.flatBlankWidth = 0.0,
    this.flatBlankLength = 0.0,
    this.isModified = false,
  });

  CadPart copyWith({
    String? id,
    String? name,
    SheetMetalMaterial? material,
    List<CadPoint2D>? outerContour,
    List<CadGeometry>? geometries,
    List<CadFeature>? features,
    List<CadDimension>? dimensions,
    List<CadConstraint>? constraints,
    Map<String, CadParameter>? parameters,
    double? flatBlankWidth,
    double? flatBlankLength,
    bool? isModified,
  }) {
    return CadPart(
      id: id ?? this.id,
      name: name ?? this.name,
      material: material ?? this.material,
      outerContour: outerContour ?? this.outerContour,
      geometries: geometries ?? this.geometries,
      features: features ?? this.features,
      dimensions: dimensions ?? this.dimensions,
      constraints: constraints ?? this.constraints,
      parameters: parameters ?? this.parameters,
      flatBlankWidth: flatBlankWidth ?? this.flatBlankWidth,
      flatBlankLength: flatBlankLength ?? this.flatBlankLength,
      isModified: isModified ?? this.isModified,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'material': material.toJson(),
        'outerContour': outerContour.map((p) => p.toJson()).toList(),
        'geometries': geometries.map((g) => g.toJson()).toList(),
        'features': features.map((f) => f.toJson()).toList(),
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'constraints': constraints.map((c) => c.toJson()).toList(),
        'parameters': parameters.map((k, v) => MapEntry(k, v.toJson())),
        'flatBlankWidth': flatBlankWidth,
        'flatBlankLength': flatBlankLength,
        'isModified': isModified,
      };

  factory CadPart.fromJson(Map<String, dynamic> json) => CadPart(
        id: json['id'] as String,
        name: json['name'] as String,
        material: json['material'] != null
            ? SheetMetalMaterial.fromJson(json['material'] as Map<String, dynamic>)
            : const SheetMetalMaterial(),
        outerContour: (json['outerContour'] as List<dynamic>?)
                ?.map((p) => CadPoint2D.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        dimensions: (json['dimensions'] as List<dynamic>?)
                ?.map((d) => CadDimension.fromJson(d as Map<String, dynamic>))
                .toList() ??
            const [],
        constraints: (json['constraints'] as List<dynamic>?)
                ?.map((c) => CadConstraint.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
        parameters: (json['parameters'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, CadParameter.fromJson(v as Map<String, dynamic>)),
            ) ??
            const {},
        flatBlankWidth: (json['flatBlankWidth'] as num?)?.toDouble() ?? 0.0,
        flatBlankLength: (json['flatBlankLength'] as num?)?.toDouble() ?? 0.0,
        isModified: json['isModified'] as bool? ?? false,
      );
}
