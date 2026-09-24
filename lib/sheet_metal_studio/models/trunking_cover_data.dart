// =============================================================================
// trunking_cover_data.dart
//
// Data model representing an associated Trunking Accessory Cover.
// Stores the cover's CAD geometry (as a first-class DsfDocument),
// 2D/3D visibility, independent 2D placement offset, snapping modes,
// and manufacturing properties.
// =============================================================================

import 'cad_primitives.dart';
import 'dsf_document.dart';

enum CoverPlacementMode2D {
  besideBase,
  snappedToBase,
  custom;

  String toJson() => name;

  static CoverPlacementMode2D fromJson(String? val) {
    if (val == null) return CoverPlacementMode2D.besideBase;
    return CoverPlacementMode2D.values.firstWhere(
      (e) => e.name.toLowerCase() == val.toLowerCase(),
      orElse: () => CoverPlacementMode2D.besideBase,
    );
  }
}

enum CoverPlacementMode3D {
  besideBase,
  snappedToBase,
  custom;

  String toJson() => name;

  static CoverPlacementMode3D fromJson(String? val) {
    if (val == null) return CoverPlacementMode3D.snappedToBase;
    return CoverPlacementMode3D.values.firstWhere(
      (e) => e.name.toLowerCase() == val.toLowerCase(),
      orElse: () => CoverPlacementMode3D.snappedToBase,
    );
  }
}

class TrunkingCoverData {
  /// The full-fledged sheet metal CAD definition of the cover.
  final DsfDocument document;

  /// Visibility in the 2D flat canvas (default: true).
  final bool isVisible2D;

  /// Visibility in the 3D viewport (default: true).
  final bool isVisible3D;

  /// 2D placement mode: beside base, snapped to base, or custom dragged offset.
  final CoverPlacementMode2D placementMode2D;

  /// 3D placement mode: beside base, snapped on top of base walls, or custom 3D offset.
  final CoverPlacementMode3D placementMode3D;

  /// Translation offset (in mm) applied to the cover in the 2D workspace.
  final CadPoint2D offset2D;

  /// Translation offset (in mm) applied to the cover in the 3D viewport (X, Y, Z lift/explosion).
  final CadPoint3D offset3D;

  /// Extensible container for cover-specific metadata (material, finish, partNumber, etc.).
  final Map<String, dynamic> properties;

  const TrunkingCoverData({
    required this.document,
    this.isVisible2D = true,
    this.isVisible3D = true,
    this.placementMode2D = CoverPlacementMode2D.besideBase,
    this.placementMode3D = CoverPlacementMode3D.snappedToBase,
    this.offset2D = const CadPoint2D(0, 0),
    this.offset3D = const CadPoint3D(0, 0, 0),
    this.properties = const {},
  });

  TrunkingCoverData copyWith({
    DsfDocument? document,
    bool? isVisible2D,
    bool? isVisible3D,
    CoverPlacementMode2D? placementMode2D,
    CoverPlacementMode3D? placementMode3D,
    CadPoint2D? offset2D,
    CadPoint3D? offset3D,
    Map<String, dynamic>? properties,
  }) {
    return TrunkingCoverData(
      document: document ?? this.document,
      isVisible2D: isVisible2D ?? this.isVisible2D,
      isVisible3D: isVisible3D ?? this.isVisible3D,
      placementMode2D: placementMode2D ?? this.placementMode2D,
      placementMode3D: placementMode3D ?? this.placementMode3D,
      offset2D: offset2D ?? this.offset2D,
      offset3D: offset3D ?? this.offset3D,
      properties: properties ?? this.properties,
    );
  }

  Map<String, dynamic> toJson() => {
    'document': document.toJson(),
    'isVisible2D': isVisible2D,
    'isVisible3D': isVisible3D,
    'placementMode2D': placementMode2D.toJson(),
    'placementMode3D': placementMode3D.toJson(),
    'offset2D': offset2D.toJson(),
    'offset3D': offset3D.toJson(),
    'properties': properties,
  };

  factory TrunkingCoverData.fromJson(Map<String, dynamic> json) {
    return TrunkingCoverData(
      document: DsfDocument.fromJson(json['document'] as Map<String, dynamic>),
      isVisible2D: json['isVisible2D'] as bool? ?? true,
      isVisible3D: json['isVisible3D'] as bool? ?? true,
      placementMode2D: CoverPlacementMode2D.fromJson(json['placementMode2D'] as String?),
      placementMode3D: CoverPlacementMode3D.fromJson(json['placementMode3D'] as String?),
      offset2D: json['offset2D'] != null
          ? CadPoint2D.fromJson(json['offset2D'] as Map<String, dynamic>)
          : const CadPoint2D(0, 0),
      offset3D: json['offset3D'] != null
          ? CadPoint3D.fromJson(json['offset3D'] as Map<String, dynamic>)
          : const CadPoint3D(0, 0, 0),
      properties: (json['properties'] as Map<String, dynamic>?) ?? const {},
    );
  }
}
