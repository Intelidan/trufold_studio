import 'dart:ui' show Rect;

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

/// Describes a clickable Onshape dimension tag rendered on the 2D/3D sketch canvas.
class SketchDimensionTagHit {
  final String tagKey;
  final Rect screenRect;
  final String primaryEntityId;
  final String? secondaryEntityId;
  final CadConstraintType constraintType;
  final String? existingConstraintId;
  final double currentValue;
  final String unitSuffix; // 'mm' or 'deg'
  final String? subKey;    // 'w' or 'h' for rectangles

  const SketchDimensionTagHit({
    required this.tagKey,
    required this.screenRect,
    required this.primaryEntityId,
    this.secondaryEntityId,
    required this.constraintType,
    this.existingConstraintId,
    required this.currentValue,
    this.unitSuffix = 'mm',
    this.subKey,
  });
}

class CadConstraint {
  final String id;
  final CadConstraintType type;
  final List<String> entityIds; // IDs of geometry or feature entities involved
  final double? parameterValue; // Target value for dimensional constraints (mm or deg)
  final String? parameterId;    // Linked CadParameter ID if driven by user parameter
  final String? expression;     // Optional formula expression (e.g. "60/2" or "25+10")
  final double labelOffset;     // Witness-line offset distance in plane mm (default 18.0)
  final double? tolerancePlus;  // Optional +tolerance (mm or deg) from Onshape '±' popover
  final double? toleranceMinus; // Optional -tolerance (mm or deg)
  final bool isActive;

  const CadConstraint({
    required this.id,
    required this.type,
    required this.entityIds,
    this.parameterValue,
    this.parameterId,
    this.expression,
    this.labelOffset = 18.0,
    this.tolerancePlus,
    this.toleranceMinus,
    this.isActive = true,
  });

  String get symbol => type.symbol;
  String get label => type.label;

  bool get isDimensional =>
      type == CadConstraintType.distance ||
      type == CadConstraintType.angle ||
      type == CadConstraintType.radius ||
      type == CadConstraintType.diameter;

  CadConstraint copyWith({
    String? id,
    CadConstraintType? type,
    List<String>? entityIds,
    double? parameterValue,
    String? parameterId,
    String? expression,
    double? labelOffset,
    double? tolerancePlus,
    double? toleranceMinus,
    bool? isActive,
  }) {
    return CadConstraint(
      id: id ?? this.id,
      type: type ?? this.type,
      entityIds: entityIds ?? this.entityIds,
      parameterValue: parameterValue ?? this.parameterValue,
      parameterId: parameterId ?? this.parameterId,
      expression: expression ?? this.expression,
      labelOffset: labelOffset ?? this.labelOffset,
      tolerancePlus: tolerancePlus ?? this.tolerancePlus,
      toleranceMinus: toleranceMinus ?? this.toleranceMinus,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'entityIds': entityIds,
        if (parameterValue != null) 'parameterValue': parameterValue,
        if (parameterId != null) 'parameterId': parameterId,
        if (expression != null) 'expression': expression,
        'labelOffset': labelOffset,
        if (tolerancePlus != null) 'tolerancePlus': tolerancePlus,
        if (toleranceMinus != null) 'toleranceMinus': toleranceMinus,
        'isActive': isActive,
      };

  factory CadConstraint.fromJson(Map<String, dynamic> json) => CadConstraint(
        id: json['id'] as String,
        type: CadConstraintType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CadConstraintType.horizontal,
        ),
        entityIds: (json['entityIds'] as List<dynamic>).map((e) => e as String).toList(),
        parameterValue: (json['parameterValue'] as num?)?.toDouble(),
        parameterId: json['parameterId'] as String?,
        expression: json['expression'] as String?,
        labelOffset: (json['labelOffset'] as num?)?.toDouble() ?? 18.0,
        tolerancePlus: (json['tolerancePlus'] as num?)?.toDouble(),
        toleranceMinus: (json['toleranceMinus'] as num?)?.toDouble(),
        isActive: json['isActive'] as bool? ?? true,
      );
}
