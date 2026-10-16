// =============================================================================
// cad_constraint.dart
//
// 2D Geometric and Dimensional Constraint model.
// Represents relations between CAD geometry entities (lines, points, bends).
// =============================================================================

enum CadConstraintType {
  // Geometric constraints
  horizontal,
  vertical,
  coincident,
  parallel,
  perpendicular,
  concentric,
  tangent,
  equal,
  symmetric,
  collinear,
  midpoint,
  normal,
  pierce,
  curvature,
  fixed,

  // Dimensional constraints
  distance,
  angle,
  radius,
  diameter;

  String get label {
    switch (this) {
      case CadConstraintType.horizontal:
        return 'Horizontal';
      case CadConstraintType.vertical:
        return 'Vertical';
      case CadConstraintType.coincident:
        return 'Coincident';
      case CadConstraintType.parallel:
        return 'Parallel';
      case CadConstraintType.perpendicular:
        return 'Perpendicular';
      case CadConstraintType.concentric:
        return 'Concentric';
      case CadConstraintType.tangent:
        return 'Tangent';
      case CadConstraintType.equal:
        return 'Equal';
      case CadConstraintType.symmetric:
        return 'Symmetric';
      case CadConstraintType.collinear:
        return 'Collinear';
      case CadConstraintType.midpoint:
        return 'Midpoint';
      case CadConstraintType.normal:
        return 'Normal';
      case CadConstraintType.pierce:
        return 'Pierce';
      case CadConstraintType.curvature:
        return 'Curvature';
      case CadConstraintType.fixed:
        return 'Fixed';
      case CadConstraintType.distance:
        return 'Distance';
      case CadConstraintType.angle:
        return 'Angle';
      case CadConstraintType.radius:
        return 'Radius';
      case CadConstraintType.diameter:
        return 'Diameter';
    }
  }

  String get symbol {
    switch (this) {
      case CadConstraintType.horizontal:
        return 'H';
      case CadConstraintType.vertical:
        return 'V';
      case CadConstraintType.coincident:
        return '•';
      case CadConstraintType.parallel:
        return '//';
      case CadConstraintType.perpendicular:
        return '⊥';
      case CadConstraintType.concentric:
        return '◎';
      case CadConstraintType.tangent:
        return '⌒';
      case CadConstraintType.equal:
        return '=';
      case CadConstraintType.symmetric:
        return '⇋';
      case CadConstraintType.collinear:
        return '⎻';
      case CadConstraintType.midpoint:
        return '⌖';
      case CadConstraintType.normal:
        return '⊥';
      case CadConstraintType.pierce:
        return '✕';
      case CadConstraintType.curvature:
        return '∿';
      case CadConstraintType.fixed:
        return '🔒';
      case CadConstraintType.distance:
        return '↔';
      case CadConstraintType.angle:
        return '∠';
      case CadConstraintType.radius:
        return 'R';
      case CadConstraintType.diameter:
        return 'Ø';
    }
  }

  bool get requiresTwoEntities {
    switch (this) {
      case CadConstraintType.horizontal:
      case CadConstraintType.vertical:
      case CadConstraintType.fixed:
      case CadConstraintType.radius:
      case CadConstraintType.diameter:
      case CadConstraintType.pierce:
        return false;
      default:
        return true;
    }
  }
}

class CadConstraint {
  final String id;
  final CadConstraintType type;
  final List<String> entityIds; // IDs of geometry or feature entities involved
  final double?
  parameterValue; // Target value for dimensional constraints (distance, angle)
  final String?
  parameterId; // Linked CadParameter ID if driven by user parameter
  final bool isActive;

  const CadConstraint({
    required this.id,
    required this.type,
    required this.entityIds,
    this.parameterValue,
    this.parameterId,
    this.isActive = true,
  });

  String get symbol => type.symbol;
  String get label => type.label;

  CadConstraint copyWith({
    String? id,
    CadConstraintType? type,
    List<String>? entityIds,
    double? parameterValue,
    String? parameterId,
    bool? isActive,
  }) {
    return CadConstraint(
      id: id ?? this.id,
      type: type ?? this.type,
      entityIds: entityIds ?? this.entityIds,
      parameterValue: parameterValue ?? this.parameterValue,
      parameterId: parameterId ?? this.parameterId,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'entityIds': entityIds,
    if (parameterValue != null) 'parameterValue': parameterValue,
    if (parameterId != null) 'parameterId': parameterId,
    'isActive': isActive,
  };

  factory CadConstraint.fromJson(Map<String, dynamic> json) => CadConstraint(
    id: json['id'] as String,
    type: CadConstraintType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => CadConstraintType.horizontal,
    ),
    entityIds: (json['entityIds'] as List<dynamic>)
        .map((e) => e as String)
        .toList(),
    parameterValue: (json['parameterValue'] as num?)?.toDouble(),
    parameterId: json['parameterId'] as String?,
    isActive: json['isActive'] as bool? ?? true,
  );
}
