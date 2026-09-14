// =============================================================================
// constraint_definition.dart
//
// Enhanced Constraint Definition Model per Phase 1 Master Guide
// Sections 7, 8, 10, 11, 49 & Sets 03, 04, 06.
//
// Encapsulates driving vs reference constraints, named parameter linking,
// stable geometry sub-references (EntityRef), and tolerance/conflict tracking.
// =============================================================================

import '../cad_constraint.dart';
import 'stable_geometry_reference.dart';

enum ConstraintMode {
  /// Driving constraint: actively controls geometry (e.g. WIDTH = 300 mm).
  driving,

  /// Reference constraint: passively measures/reports geometry without driving.
  reference,
}

enum ConstraintState {
  solved,
  underConstrained,
  overConstrained,
  conflict,
}

class ConstraintDefinition {
  final String id;
  final CadConstraintType type;
  final List<EntityRef> references;
  final double? targetValue;
  final String? parameterId; // Linked parameter name/id (e.g. 'WIDTH', 'BRANCH_WIDTH')
  final ConstraintMode mode;
  final bool isActive;
  final bool isSuppressed;
  final double toleranceMm;
  final String? conflictReason;
  final Map<String, dynamic> metadata;

  const ConstraintDefinition({
    required this.id,
    required this.type,
    required this.references,
    this.targetValue,
    this.parameterId,
    this.mode = ConstraintMode.driving,
    this.isActive = true,
    this.isSuppressed = false,
    this.toleranceMm = 1e-3,
    this.conflictReason,
    this.metadata = const {},
  });

  String get symbol => type.symbol;
  String get label => type.label;
  bool get requiresTwoEntities => type.requiresTwoEntities;
  bool get isDriving => mode == ConstraintMode.driving && !isSuppressed && isActive;

  /// Backwards-compatibility bridge from legacy [CadConstraint]
  factory ConstraintDefinition.fromLegacy(CadConstraint legacy) {
    return ConstraintDefinition(
      id: legacy.id,
      type: legacy.type,
      references: legacy.entityIds.map((id) => EntityRef.parse(id)).toList(),
      targetValue: legacy.parameterValue,
      parameterId: legacy.parameterId,
      mode: ConstraintMode.driving,
      isActive: legacy.isActive,
    );
  }

  /// Backwards-compatibility bridge to legacy [CadConstraint]
  CadConstraint toLegacy() {
    return CadConstraint(
      id: id,
      type: type,
      entityIds: references.map((r) => r.canonicalPath).toList(),
      parameterValue: targetValue,
      parameterId: parameterId,
      isActive: isActive && !isSuppressed,
    );
  }

  ConstraintDefinition copyWith({
    String? id,
    CadConstraintType? type,
    List<EntityRef>? references,
    double? targetValue,
    String? parameterId,
    ConstraintMode? mode,
    bool? isActive,
    bool? isSuppressed,
    double? toleranceMm,
    String? conflictReason,
    Map<String, dynamic>? metadata,
  }) {
    return ConstraintDefinition(
      id: id ?? this.id,
      type: type ?? this.type,
      references: references ?? this.references,
      targetValue: targetValue ?? this.targetValue,
      parameterId: parameterId ?? this.parameterId,
      mode: mode ?? this.mode,
      isActive: isActive ?? this.isActive,
      isSuppressed: isSuppressed ?? this.isSuppressed,
      toleranceMm: toleranceMm ?? this.toleranceMm,
      conflictReason: conflictReason ?? this.conflictReason,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'references': references.map((r) => r.toJson()).toList(),
        if (targetValue != null) 'targetValue': targetValue,
        if (parameterId != null) 'parameterId': parameterId,
        'mode': mode.name,
        'isActive': isActive,
        'isSuppressed': isSuppressed,
        'toleranceMm': toleranceMm,
        if (conflictReason != null) 'conflictReason': conflictReason,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ConstraintDefinition.fromJson(Map<String, dynamic> json) =>
      ConstraintDefinition(
        id: json['id'] as String,
        type: CadConstraintType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CadConstraintType.distance,
        ),
        references: (json['references'] as List<dynamic>?)
                ?.map((r) => EntityRef.fromJson(r as Map<String, dynamic>))
                .toList() ??
            (json['entityIds'] as List<dynamic>?)
                ?.map((id) => EntityRef.parse(id.toString()))
                .toList() ??
            const [],
        targetValue: (json['targetValue'] as num?)?.toDouble() ??
            (json['parameterValue'] as num?)?.toDouble(),
        parameterId: json['parameterId'] as String?,
        mode: ConstraintMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => ConstraintMode.driving,
        ),
        isActive: json['isActive'] as bool? ?? true,
        isSuppressed: json['isSuppressed'] as bool? ?? false,
        toleranceMm: (json['toleranceMm'] as num?)?.toDouble() ?? 1e-3,
        conflictReason: json['conflictReason'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
      );

  @override
  String toString() {
    final targetStr = targetValue != null ? ' = ${targetValue!.toStringAsFixed(1)}' : '';
    final paramStr = parameterId != null ? ' ($parameterId)' : '';
    return 'Constraint($label: ${references.join(' ↔ ')}$targetStr$paramStr)';
  }
}
