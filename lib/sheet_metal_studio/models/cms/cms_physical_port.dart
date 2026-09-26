// =============================================================================
// cms_physical_port.dart
//
// Pure semantic model representing a verified physical opening of a folded
// sheet-metal fitting, completely decoupled from flow-direction semantics.
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 11 & 12).
// =============================================================================

import 'package:flutter/foundation.dart';
import '../cad_primitives.dart';

/// Provenance indicating how a physical port was discovered.
enum PortDetectionSource {
  /// Discovered directly from open 3D boundary loops of the folded model.
  foldedTopology,

  /// Measured and matched against expected user/contract dimensions.
  dimensionMatched,

  /// Inferred from product variation structural rules.
  productRule,

  /// Explicitly confirmed by the user during ambiguity resolution.
  userConfirmed,

  /// Manually specified by the user as an exception fallback.
  userMarked,

  /// Migrated from legacy DSF metadata.
  migrated,
}

/// Optional semantic flow role for a physical port.
enum CmsPortRole {
  unassigned,
  bidirectional,
  main,
  inlet,
  outlet,
  branch;

  String get displayName {
    switch (this) {
      case CmsPortRole.unassigned:
        return 'Unassigned';
      case CmsPortRole.bidirectional:
        return 'Bidirectional';
      case CmsPortRole.main:
        return 'Main';
      case CmsPortRole.inlet:
        return 'Inlet';
      case CmsPortRole.outlet:
        return 'Outlet';
      case CmsPortRole.branch:
        return 'Branch';
    }
  }
}

/// Standard catalog nominal sizes for cable trunking & fittings.
const List<double> standardNominalSizes = [
  25.0, 50.0, 75.0, 100.0, 125.0, 150.0, 175.0, 200.0, 225.0, 250.0, 300.0, 350.0, 400.0, 450.0, 500.0, 600.0, 750.0, 900.0,
];

/// Converts an internal fabricated or expanded dimension to its clean rounded catalog nominal figure.
/// E.g. 98mm or 101mm -> 100mm, 47mm/48mm or 51mm -> 50mm, 148mm/151mm -> 150mm.
double toNominalSize(double valMm) {
  if (valMm < 20.0) return valMm;
  for (final nom in standardNominalSizes) {
    if ((valMm - nom).abs() <= 1.6 ||
        (valMm - (nom - 2.0)).abs() <= 1.2 ||
        (valMm - (nom - 3.0)).abs() <= 0.8 ||
        (valMm - (nom + 1.5)).abs() <= 0.8 ||
        (valMm - (nom + 2.0)).abs() <= 1.0) {
      return nom;
    }
  }
  final candidate = (valMm / 5.0).round() * 5.0;
  if ((valMm - candidate).abs() <= 1.6 ||
      (valMm - (candidate - 2.0)).abs() <= 1.2 ||
      (valMm - (candidate - 3.0)).abs() <= 0.8 ||
      (valMm - (candidate + 1.5)).abs() <= 0.8) {
    return candidate;
  }
  return valMm;
}

/// Converts a nominal catalog/user-assigned dimension to the internal fabricated
/// sketch dimension (strictly 2mm lesser than shown in drawings, e.g. 100mm -> 98mm).
double toFabricatedSize(double nominalMm) {
  if (nominalMm < 20.0) return nominalMm;
  return nominalMm - 2.0;
}

/// Represents an actual physical terminal opening of the folded sheet-metal fitting.
@immutable
class CmsPhysicalPort {
  /// Clean nominal catalog width (e.g. 100mm for fabricated 98mm).
  double get nominalWidth => toNominalSize(width);

  /// Clean nominal catalog height (e.g. 50mm for fabricated 48mm).
  double get nominalHeight => toNominalSize(height);

  /// Formatted nominal dimensions string (e.g. "100 × 50 mm").
  String get displayDimensions => '${nominalWidth.toStringAsFixed(0)} × ${nominalHeight.toStringAsFixed(0)} mm';
  /// Stable physical port identifier (e.g. 'PORT_1', 'PORT_2').
  final String id;

  /// 1-based index for consistent display and ordering.
  final int index;

  /// Measured opening width across the floor web (in mm).
  final double width;

  /// Measured vertical sidewall height from floor to top lip (in mm).
  final double height;

  /// Nominal or measured return flange lip width (in mm).
  final double flange;

  /// 3D centroid of the opening mouth.
  final CadPoint3D center;

  /// 2D midpoint of the opening edge on the flat blank.
  final CadPoint2D flatCenter;

  /// Outward unit normal vector pointing out of the open channel mouth.
  final CadPoint3D normal;

  /// 3D unit vector aligned with the floor width opening direction.
  final CadPoint3D widthDirection;

  /// 3D unit vector aligned with the vertical sidewall height direction.
  final CadPoint3D heightDirection;

  /// IDs of planar faces that physically form this opening (floor + standing sidewalls).
  final List<String> hostFaceIds;

  /// Identifier of the 3D boundary loop representing the open channel rim.
  final String? boundaryLoopId;

  /// IDs of 2D/3D boundary line segments contributing to this opening mouth.
  final List<String> boundaryEdgeIds;

  /// Floor edge endpoint 1 in 3D world space.
  final CadPoint3D? floorP1;

  /// Floor edge endpoint 2 in 3D world space.
  final CadPoint3D? floorP2;

  /// Derived 4 corners of the channel mouth [P1 (floor), P3 (lip), P4 (lip), P2 (floor)].
  /// Note: This is derived 3D geometry folded from the canonical 2D sheet, not the permanent semantic identity.
  final List<CadPoint3D> derivedMouthCorners;

  /// Anchor point on the top rim mouth center where 3D callout is pinned/pegged.
  final CadPoint3D? calloutAnchor;

  /// Detection confidence (0.0 to 1.0).
  final double confidence;

  /// Detection provenance.
  final PortDetectionSource detectionSource;

  /// Optional active semantic flow role (nullable/unassigned by default).
  final CmsPortRole? role;

  /// Suggested role proposed by product-specific rules (e.g. largest width -> main).
  final CmsPortRole? suggestedRole;

  /// Source of the role assignment ('user', 'product_rule', 'unassigned').
  final String? roleSource;

  /// Human-readable rationale for the suggested role.
  final String? suggestionReason;

  const CmsPhysicalPort({
    required this.id,
    required this.index,
    required this.width,
    required this.height,
    this.flange = 15.0,
    this.center = const CadPoint3D(0, 0, 0),
    this.flatCenter = const CadPoint2D(0, 0),
    this.normal = const CadPoint3D(0, 0, 1),
    this.widthDirection = const CadPoint3D(1, 0, 0),
    this.heightDirection = const CadPoint3D(0, 1, 0),
    this.hostFaceIds = const [],
    this.boundaryLoopId,
    this.boundaryEdgeIds = const [],
    this.floorP1,
    this.floorP2,
    this.derivedMouthCorners = const [],
    this.calloutAnchor,
    this.confidence = 1.0,
    this.detectionSource = PortDetectionSource.foldedTopology,
    this.role,
    this.suggestedRole,
    this.roleSource,
    this.suggestionReason,
  });


  bool get isHighConfidence => confidence >= 0.85;

  CmsPhysicalPort copyWith({
    String? id,
    int? index,
    double? width,
    double? height,
    double? flange,
    CadPoint3D? center,
    CadPoint2D? flatCenter,
    CadPoint3D? normal,
    CadPoint3D? widthDirection,
    CadPoint3D? heightDirection,
    List<String>? hostFaceIds,
    String? boundaryLoopId,
    List<String>? boundaryEdgeIds,
    CadPoint3D? floorP1,
    CadPoint3D? floorP2,
    List<CadPoint3D>? derivedMouthCorners,
    CadPoint3D? calloutAnchor,
    double? confidence,
    PortDetectionSource? detectionSource,
    CmsPortRole? role,
    CmsPortRole? suggestedRole,
    String? roleSource,
    String? suggestionReason,
  }) {
    return CmsPhysicalPort(
      id: id ?? this.id,
      index: index ?? this.index,
      width: width ?? this.width,
      height: height ?? this.height,
      flange: flange ?? this.flange,
      center: center ?? this.center,
      flatCenter: flatCenter ?? this.flatCenter,
      normal: normal ?? this.normal,
      widthDirection: widthDirection ?? this.widthDirection,
      heightDirection: heightDirection ?? this.heightDirection,
      hostFaceIds: hostFaceIds ?? this.hostFaceIds,
      boundaryLoopId: boundaryLoopId ?? this.boundaryLoopId,
      boundaryEdgeIds: boundaryEdgeIds ?? this.boundaryEdgeIds,
      floorP1: floorP1 ?? this.floorP1,
      floorP2: floorP2 ?? this.floorP2,
      derivedMouthCorners: derivedMouthCorners ?? this.derivedMouthCorners,
      calloutAnchor: calloutAnchor ?? this.calloutAnchor,
      confidence: confidence ?? this.confidence,
      detectionSource: detectionSource ?? this.detectionSource,
      role: role ?? this.role,
      suggestedRole: suggestedRole ?? this.suggestedRole,
      roleSource: roleSource ?? this.roleSource,
      suggestionReason: suggestionReason ?? this.suggestionReason,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'index': index,
        'width': width,
        'height': height,
        'flange': flange,
        'center': [center.x, center.y, center.z],
        'flatCenter': [flatCenter.x, flatCenter.y],
        'normal': [normal.x, normal.y, normal.z],
        'widthDirection': [widthDirection.x, widthDirection.y, widthDirection.z],
        'heightDirection': [heightDirection.x, heightDirection.y, heightDirection.z],
        'hostFaceIds': hostFaceIds,
        if (boundaryLoopId != null) 'boundaryLoopId': boundaryLoopId,
        'boundaryEdgeIds': boundaryEdgeIds,
        if (floorP1 != null) 'floorP1': [floorP1!.x, floorP1!.y, floorP1!.z],
        if (floorP2 != null) 'floorP2': [floorP2!.x, floorP2!.y, floorP2!.z],
        if (derivedMouthCorners.isNotEmpty)
          'derivedMouthCorners': derivedMouthCorners.map((p) => [p.x, p.y, p.z]).toList(),
        if (calloutAnchor != null) 'calloutAnchor': [calloutAnchor!.x, calloutAnchor!.y, calloutAnchor!.z],
        'confidence': confidence,
        'detectionSource': detectionSource.name,
        if (role != null) 'role': role!.name,
        if (suggestedRole != null) 'suggestedRole': suggestedRole!.name,
        if (roleSource != null) 'roleSource': roleSource,
        if (suggestionReason != null) 'suggestionReason': suggestionReason,
      };

  factory CmsPhysicalPort.fromJson(Map<String, dynamic> json) {
    CadPoint3D parseVec(dynamic raw, CadPoint3D fallback) {
      if (raw is List && raw.length >= 3) {
        return CadPoint3D(
          (raw[0] as num).toDouble(),
          (raw[1] as num).toDouble(),
          (raw[2] as num).toDouble(),
        );
      }
      return fallback;
    }

    CadPoint2D parseVec2(dynamic raw, CadPoint2D fallback) {
      if (raw is List && raw.length >= 2) {
        return CadPoint2D(
          (raw[0] as num).toDouble(),
          (raw[1] as num).toDouble(),
        );
      }
      return fallback;
    }

    List<CadPoint3D> parseVecList(dynamic raw) {
      if (raw is List) {
        return raw.map((item) => parseVec(item, const CadPoint3D(0, 0, 0))).toList();
      }
      return const [];
    }

    PortDetectionSource parseSource(String? name) {
      return PortDetectionSource.values.firstWhere(
        (s) => s.name == name,
        orElse: () => PortDetectionSource.foldedTopology,
      );
    }

    CmsPortRole? parseRole(String? name) {
      if (name == null) return null;
      return CmsPortRole.values.firstWhere(
        (r) => r.name == name,
        orElse: () => CmsPortRole.unassigned,
      );
    }

    return CmsPhysicalPort(
      id: json['id'] as String? ?? 'PORT_1',
      index: (json['index'] as num?)?.toInt() ?? 1,
      width: (json['width'] as num?)?.toDouble() ?? 100.0,
      height: (json['height'] as num?)?.toDouble() ?? 100.0,
      flange: (json['flange'] as num?)?.toDouble() ?? 15.0,
      center: parseVec(json['center'], const CadPoint3D(0, 0, 0)),
      flatCenter: parseVec2(json['flatCenter'], const CadPoint2D(0, 0)),
      normal: parseVec(json['normal'], const CadPoint3D(0, 0, 1)),
      widthDirection: parseVec(json['widthDirection'], const CadPoint3D(1, 0, 0)),
      heightDirection: parseVec(json['heightDirection'], const CadPoint3D(0, 1, 0)),
      hostFaceIds: (json['hostFaceIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      boundaryLoopId: json['boundaryLoopId'] as String?,
      boundaryEdgeIds: (json['boundaryEdgeIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      floorP1: json['floorP1'] != null ? parseVec(json['floorP1'], const CadPoint3D(0, 0, 0)) : null,
      floorP2: json['floorP2'] != null ? parseVec(json['floorP2'], const CadPoint3D(0, 0, 0)) : null,
      derivedMouthCorners: parseVecList(json['derivedMouthCorners']),
      calloutAnchor: json['calloutAnchor'] != null ? parseVec(json['calloutAnchor'], const CadPoint3D(0, 0, 0)) : null,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      detectionSource: parseSource(json['detectionSource'] as String?),
      role: parseRole(json['role'] as String?),
      suggestedRole: parseRole(json['suggestedRole'] as String?),
      roleSource: json['roleSource'] as String?,
      suggestionReason: json['suggestionReason'] as String?,
    );
  }
}

