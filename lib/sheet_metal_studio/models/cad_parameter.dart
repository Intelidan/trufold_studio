// =============================================================================
// cad_parameter.dart
//
// First-class engineering parameter model for CAD templates and parts.
// Categorizes into User, Derived, and Feature parameters per Master Guide #36-#37.
// =============================================================================

enum CadParameterCategory {
  /// Directly entered by the user (e.g. Width = 300, Height = 100, Length = 3000)
  user,

  /// Calculated from formulas or geometry (e.g. FlatLength, HoleCount, Area, Weight)
  derived,

  /// Belonging directly to a feature (e.g. Bend01.Angle, HolePattern.PitchX)
  feature,
}

enum CadParameterType {
  length,
  angle,
  count,
  thickness,
  ratio,
  text,
  boolean,
}

class CadParameter {
  final String id;
  final String name;
  final double value;
  final String unit; // 'mm', 'deg', 'count', etc.
  final CadParameterCategory category;
  final CadParameterType type;
  final double? minValue;
  final double? maxValue;
  final double? step;
  final String? formula;
  final String source; // e.g. 'Template', 'User', 'CAM'
  final List<double>? allowedValues; // e.g. standard sheet thicknesses [1.2, 1.5, 2.0, 2.5, 3.0]
  final String? description;

  const CadParameter({
    required this.id,
    required this.name,
    required this.value,
    this.unit = 'mm',
    this.category = CadParameterCategory.user,
    this.type = CadParameterType.length,
    this.minValue,
    this.maxValue,
    this.step,
    this.formula,
    this.source = 'User',
    this.allowedValues,
    this.description,
  });

  /// Validates whether a candidate value satisfies parameter bounds and allowed value sets
  bool isValidValue(double candidate) {
    if (minValue != null && candidate < minValue!) return false;
    if (maxValue != null && candidate > maxValue!) return false;
    if (allowedValues != null && allowedValues!.isNotEmpty) {
      return allowedValues!.any((v) => (v - candidate).abs() < 1e-4);
    }
    return true;
  }

  CadParameter copyWith({
    String? id,
    String? name,
    double? value,
    String? unit,
    CadParameterCategory? category,
    CadParameterType? type,
    double? minValue,
    double? maxValue,
    double? step,
    String? formula,
    String? source,
    List<double>? allowedValues,
    String? description,
  }) {
    return CadParameter(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      type: type ?? this.type,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      step: step ?? this.step,
      formula: formula ?? this.formula,
      source: source ?? this.source,
      allowedValues: allowedValues ?? this.allowedValues,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
        'unit': unit,
        'category': category.name,
        'type': type.name,
        if (minValue != null) 'minValue': minValue,
        if (maxValue != null) 'maxValue': maxValue,
        if (step != null) 'step': step,
        if (formula != null) 'formula': formula,
        'source': source,
        if (allowedValues != null) 'allowedValues': allowedValues,
        if (description != null) 'description': description,
      };

  factory CadParameter.fromJson(Map<String, dynamic> json) => CadParameter(
        id: json['id'] as String,
        name: json['name'] as String,
        value: (json['value'] as num).toDouble(),
        unit: json['unit'] as String? ?? 'mm',
        category: CadParameterCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => CadParameterCategory.user,
        ),
        type: CadParameterType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CadParameterType.length,
        ),
        minValue: (json['minValue'] as num?)?.toDouble(),
        maxValue: (json['maxValue'] as num?)?.toDouble(),
        step: (json['step'] as num?)?.toDouble(),
        formula: json['formula'] as String?,
        source: json['source'] as String? ?? 'User',
        allowedValues: (json['allowedValues'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
        description: json['description'] as String?,
      );
}
