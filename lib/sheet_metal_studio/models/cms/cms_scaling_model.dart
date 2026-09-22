// =============================================================================
// cms_scaling_model.dart
//
// Pure semantic model for Phase 2: Intelligent Template Scaling.
// Declares the 4 first-class geometric behaviors (STRETCH, TRANSLATE, RIGID, DERIVED),
// parameter teaching states, and semantic feature groups per
// TRUFOLD_PHASE_1_2_TEMPLATE_SCALING_WORKFLOW.md (Sections 5-15).
//
// CANONICAL GEOMETRY RULE:
// The 2D sheet-metal model is the single authoritative source of truth.
// Scaling operations modify canonical 2D geometry (DsfDocument). 3D model,
// physical port mouths, callouts, and face topology are regenerated/folded
// from that 2D state via KinematicFoldEngine.
// =============================================================================

import 'package:flutter/foundation.dart';
import '../cad_primitives.dart';
import 'cms_physical_port.dart';

/// The 4 first-class geometric behaviors in TruFold template scaling.
enum CmsGeometryBehavior {
  /// Flat web/floor regions that expand or contract to absorb dimensional deltas.
  stretch,

  /// Walls, flanges, and attached details that shift rigidly along the stretch delta.
  translate,

  /// Punches, coupler slots, and mounting holes that preserve exact size, shape, and edge offset.
  rigid,

  /// 3D port opening mouths, plane normals, and bounding extents derived from folded 3D kinematics.
  derived;

  String get displayName {
    switch (this) {
      case CmsGeometryBehavior.stretch:
        return 'STRETCH';
      case CmsGeometryBehavior.translate:
        return 'TRANSLATE';
      case CmsGeometryBehavior.rigid:
        return 'RIGID';
      case CmsGeometryBehavior.derived:
        return 'DERIVED';
    }
  }
}

/// Progressive teaching state for a product dimension.
enum CmsParameterTeachingState {
  /// Parameter has not been taught yet (baseline template default).
  untaught,

  /// Active learning/preview mode with morph slider.
  learning,

  /// User has validated and accepted this scaling behavior.
  learned;

  String get displayName {
    switch (this) {
      case CmsParameterTeachingState.untaught:
        return 'Untaught';
      case CmsParameterTeachingState.learning:
        return 'Learning';
      case CmsParameterTeachingState.learned:
        return 'Learned';
    }
  }
}

/// A product parameter declared for template scaling (e.g. Width, Height).
@immutable
class CmsScalingParameter {
  final String id;
  final String displayName;
  final double currentValue;
  final double baselineValue;
  final double minValidMm;
  final double maxValidMm;
  final String unit;
  final CmsParameterTeachingState teachingState;
  final List<String> stretchZoneIds;
  final List<String> translationZoneIds;
  final List<String> rigidGroupIds;
  final List<String> derivedPortIds;

  const CmsScalingParameter({
    required this.id,
    required this.displayName,
    required this.currentValue,
    required this.baselineValue,
    this.minValidMm = 50.0,
    this.maxValidMm = 1000.0,
    this.unit = 'mm',
    this.teachingState = CmsParameterTeachingState.untaught,
    this.stretchZoneIds = const [],
    this.translationZoneIds = const [],
    this.rigidGroupIds = const [],
    this.derivedPortIds = const [],
  });

  bool get isLearned => teachingState == CmsParameterTeachingState.learned;
  bool get isLearning => teachingState == CmsParameterTeachingState.learning;

  CmsScalingParameter copyWith({
    String? id,
    String? displayName,
    double? currentValue,
    double? baselineValue,
    double? minValidMm,
    double? maxValidMm,
    String? unit,
    CmsParameterTeachingState? teachingState,
    List<String>? stretchZoneIds,
    List<String>? translationZoneIds,
    List<String>? rigidGroupIds,
    List<String>? derivedPortIds,
  }) {
    return CmsScalingParameter(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      currentValue: currentValue ?? this.currentValue,
      baselineValue: baselineValue ?? this.baselineValue,
      minValidMm: minValidMm ?? this.minValidMm,
      maxValidMm: maxValidMm ?? this.maxValidMm,
      unit: unit ?? this.unit,
      teachingState: teachingState ?? this.teachingState,
      stretchZoneIds: stretchZoneIds ?? this.stretchZoneIds,
      translationZoneIds: translationZoneIds ?? this.translationZoneIds,
      rigidGroupIds: rigidGroupIds ?? this.rigidGroupIds,
      derivedPortIds: derivedPortIds ?? this.derivedPortIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'currentValue': currentValue,
        'baselineValue': baselineValue,
        'minValidMm': minValidMm,
        'maxValidMm': maxValidMm,
        'unit': unit,
        'teachingState': teachingState.name,
        'stretchZoneIds': stretchZoneIds,
        'translationZoneIds': translationZoneIds,
        'rigidGroupIds': rigidGroupIds,
        'derivedPortIds': derivedPortIds,
      };

  factory CmsScalingParameter.fromJson(Map<String, dynamic> json) {
    return CmsScalingParameter(
      id: json['id'] as String? ?? 'width',
      displayName: json['displayName'] as String? ?? 'Width',
      currentValue: (json['currentValue'] as num?)?.toDouble() ?? 100.0,
      baselineValue: (json['baselineValue'] as num?)?.toDouble() ?? 100.0,
      minValidMm: (json['minValidMm'] as num?)?.toDouble() ?? 50.0,
      maxValidMm: (json['maxValidMm'] as num?)?.toDouble() ?? 1000.0,
      unit: json['unit'] as String? ?? 'mm',
      teachingState: CmsParameterTeachingState.values.firstWhere(
        (s) => s.name == json['teachingState'],
        orElse: () => CmsParameterTeachingState.untaught,
      ),
      stretchZoneIds: (json['stretchZoneIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      translationZoneIds: (json['translationZoneIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      rigidGroupIds: (json['rigidGroupIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      derivedPortIds: (json['derivedPortIds'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}

/// Region of the flat sheet metal blank that absorbs expansion/contraction.
@immutable
class CmsStretchZone {
  final String id;
  final String description;
  final List<String> faceIds;
  final CadPoint2D axis;

  const CmsStretchZone({
    required this.id,
    required this.description,
    required this.faceIds,
    this.axis = const CadPoint2D(1.0, 0.0),
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'faceIds': faceIds,
        'axis': [axis.x, axis.y],
      };

  factory CmsStretchZone.fromJson(Map<String, dynamic> json) {
    CadPoint2D parseAxis(dynamic raw) {
      if (raw is List && raw.length >= 2) {
        return CadPoint2D((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
      }
      return const CadPoint2D(1.0, 0.0);
    }

    return CmsStretchZone(
      id: json['id'] as String? ?? 'stretch_zone',
      description: json['description'] as String? ?? '',
      faceIds: (json['faceIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      axis: parseAxis(json['axis']),
    );
  }
}

/// Region of connected sidewall and flange geometry that moves rigidly.
@immutable
class CmsTranslationZone {
  final String id;
  final String description;
  final List<String> faceIds;
  final List<String> bendIds;
  final List<String> flangeIds;
  final CadPoint2D direction;

  const CmsTranslationZone({
    required this.id,
    required this.description,
    required this.faceIds,
    this.bendIds = const [],
    this.flangeIds = const [],
    this.direction = const CadPoint2D(1.0, 0.0),
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'faceIds': faceIds,
        'bendIds': bendIds,
        'flangeIds': flangeIds,
        'direction': [direction.x, direction.y],
      };

  factory CmsTranslationZone.fromJson(Map<String, dynamic> json) {
    CadPoint2D parseDir(dynamic raw) {
      if (raw is List && raw.length >= 2) {
        return CadPoint2D((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
      }
      return const CadPoint2D(1.0, 0.0);
    }

    return CmsTranslationZone(
      id: json['id'] as String? ?? 'translation_zone',
      description: json['description'] as String? ?? '',
      faceIds: (json['faceIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      bendIds: (json['bendIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      flangeIds: (json['flangeIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      direction: parseDir(json['direction']),
    );
  }
}

/// Protected semantic feature group (coupler slots, punch holes, perforations).
/// Features maintain exact dimensions, orientation, and reference mounting edge distance.
@immutable
class CmsRigidFeatureGroup {
  final String id;
  final String name; // Computed dynamically, e.g. "Coupler Slots (8)", never hardcoded!
  final List<String> punchIds;
  final String hostFaceId;
  final String description;

  const CmsRigidFeatureGroup({
    required this.id,
    required this.name,
    required this.punchIds,
    required this.hostFaceId,
    this.description = 'Preserves punch dimensions and mounting distance',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'punchIds': punchIds,
        'hostFaceId': hostFaceId,
        'description': description,
      };

  factory CmsRigidFeatureGroup.fromJson(Map<String, dynamic> json) {
    return CmsRigidFeatureGroup(
      id: json['id'] as String? ?? 'rigid_group',
      name: json['name'] as String? ?? 'Protected Features',
      punchIds: (json['punchIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      hostFaceId: json['hostFaceId'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

/// Derived port representation whose mouth geometry recalculates from the folded 3D state.
@immutable
class CmsDerivedPort {
  final String portId;
  final CmsPortRole? role;
  final String description;

  const CmsDerivedPort({
    required this.portId,
    this.role,
    this.description = '3D mouth aperture automatically derives from folded geometry',
  });

  Map<String, dynamic> toJson() => {
        'portId': portId,
        if (role != null) 'role': role!.name,
        'description': description,
      };

  factory CmsDerivedPort.fromJson(Map<String, dynamic> json) {
    CmsPortRole? parseRole(String? r) {
      if (r == null) return null;
      return CmsPortRole.values.firstWhere((e) => e.name == r, orElse: () => CmsPortRole.unassigned);
    }

    return CmsDerivedPort(
      portId: json['portId'] as String? ?? 'PORT_1',
      role: parseRole(json['role'] as String?),
      description: json['description'] as String? ?? '',
    );
  }
}

/// Complete parametric scaling model for a CMS product template.
@immutable
class CmsScalingModel {
  final String templateId;
  final String category;
  final String productType;
  final String variation;
  final Map<String, CmsScalingParameter> parameters;
  final List<CmsStretchZone> stretchZones;
  final List<CmsTranslationZone> translationZones;
  final List<CmsRigidFeatureGroup> rigidFeatureGroups;
  final List<CmsDerivedPort> derivedPorts;
  final bool isLinkedPorts;
  final int activePortIndex;

  const CmsScalingModel({
    required this.templateId,
    required this.category,
    required this.productType,
    required this.variation,
    this.parameters = const {},
    this.stretchZones = const [],
    this.translationZones = const [],
    this.rigidFeatureGroups = const [],
    this.derivedPorts = const [],
    this.isLinkedPorts = true,
    this.activePortIndex = 0,
  });

  bool get isFullyTaught =>
      parameters.isNotEmpty && parameters.values.every((p) => p.isLearned);

  bool get hasUntaughtParameters =>
      parameters.values.any((p) => p.teachingState == CmsParameterTeachingState.untaught);

  CmsScalingModel copyWith({
    String? templateId,
    String? category,
    String? productType,
    String? variation,
    Map<String, CmsScalingParameter>? parameters,
    List<CmsStretchZone>? stretchZones,
    List<CmsTranslationZone>? translationZones,
    List<CmsRigidFeatureGroup>? rigidFeatureGroups,
    List<CmsDerivedPort>? derivedPorts,
    bool? isLinkedPorts,
    int? activePortIndex,
  }) {
    return CmsScalingModel(
      templateId: templateId ?? this.templateId,
      category: category ?? this.category,
      productType: productType ?? this.productType,
      variation: variation ?? this.variation,
      parameters: parameters ?? this.parameters,
      stretchZones: stretchZones ?? this.stretchZones,
      translationZones: translationZones ?? this.translationZones,
      rigidFeatureGroups: rigidFeatureGroups ?? this.rigidFeatureGroups,
      derivedPorts: derivedPorts ?? this.derivedPorts,
      isLinkedPorts: isLinkedPorts ?? this.isLinkedPorts,
      activePortIndex: activePortIndex ?? this.activePortIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'templateId': templateId,
        'category': category,
        'productType': productType,
        'variation': variation,
        'parameters': parameters.map((k, v) => MapEntry(k, v.toJson())),
        'stretchZones': stretchZones.map((z) => z.toJson()).toList(),
        'translationZones': translationZones.map((z) => z.toJson()).toList(),
        'rigidFeatureGroups': rigidFeatureGroups.map((g) => g.toJson()).toList(),
        'derivedPorts': derivedPorts.map((p) => p.toJson()).toList(),
        'isLinkedPorts': isLinkedPorts,
        'activePortIndex': activePortIndex,
      };

  factory CmsScalingModel.fromJson(Map<String, dynamic> json) {
    final paramsRaw = json['parameters'] as Map<String, dynamic>? ?? {};
    final params = paramsRaw.map(
      (k, v) => MapEntry(k, CmsScalingParameter.fromJson(v as Map<String, dynamic>)),
    );

    return CmsScalingModel(
      templateId: json['templateId'] as String? ?? 'template_1',
      category: json['category'] as String? ?? 'Trunking Accessories',
      productType: json['productType'] as String? ?? 'bend',
      variation: json['variation'] as String? ?? '45_deg',
      parameters: params,
      stretchZones: (json['stretchZones'] as List<dynamic>? ?? [])
          .map((z) => CmsStretchZone.fromJson(z as Map<String, dynamic>))
          .toList(),
      translationZones: (json['translationZones'] as List<dynamic>? ?? [])
          .map((z) => CmsTranslationZone.fromJson(z as Map<String, dynamic>))
          .toList(),
      rigidFeatureGroups: (json['rigidFeatureGroups'] as List<dynamic>? ?? [])
          .map((g) => CmsRigidFeatureGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
      derivedPorts: (json['derivedPorts'] as List<dynamic>? ?? [])
          .map((p) => CmsDerivedPort.fromJson(p as Map<String, dynamic>))
          .toList(),
      isLinkedPorts: json['isLinkedPorts'] as bool? ?? true,
      activePortIndex: json['activePortIndex'] as int? ?? 0,
    );
  }
}
