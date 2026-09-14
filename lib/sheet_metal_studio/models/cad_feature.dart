// =============================================================================
// cad_feature.dart
//
// First-class CAD feature tree nodes per Master Guide #25, #27, #30.
// Represents Base Face, Bends, Holes, Patterns, Cutouts, and Reliefs.
// =============================================================================

import 'fold_bend_line.dart';
import 'corner_treatment.dart';
import 'dsf_document.dart';

enum CadFeatureType {
  baseSheet,
  bend,
  hole,
  holePattern,
  laserCut,
  reliefNotch,
  cornerChamfer,
}

abstract class CadFeature {
  final String id;
  final String name;
  final CadFeatureType type;
  final bool isVisible;
  final bool isSuppressed;
  final String? parentFeatureId;
  final Map<String, dynamic> properties;

  const CadFeature({
    required this.id,
    required this.name,
    required this.type,
    this.isVisible = true,
    this.isSuppressed = false,
    this.parentFeatureId,
    this.properties = const {},
  });

  Map<String, dynamic> toJson();
}

/// Feature representing the root planar base floor of a sheet metal part
class SheetBaseFeature extends CadFeature {
  final String faceId;
  final double areaMm2;

  const SheetBaseFeature({
    required super.id,
    required super.name,
    required this.faceId,
    this.areaMm2 = 0.0,
    super.isVisible,
    super.isSuppressed,
    super.properties,
  }) : super(type: CadFeatureType.baseSheet);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'baseSheet',
    'id': id,
    'name': name,
    'faceId': faceId,
    'areaMm2': areaMm2,
    'isVisible': isVisible,
    'isSuppressed': isSuppressed,
    'properties': properties,
  };

  factory SheetBaseFeature.fromJson(Map<String, dynamic> json) =>
      SheetBaseFeature(
        id: json['id'] as String,
        name: json['name'] as String,
        faceId: json['faceId'] as String,
        areaMm2: (json['areaMm2'] as num?)?.toDouble() ?? 0.0,
        isVisible: json['isVisible'] as bool? ?? true,
        isSuppressed: json['isSuppressed'] as bool? ?? false,
        properties: (json['properties'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Feature representing a press brake bend or return flange crease
class SheetBendFeature extends CadFeature {
  final String bendLineId;
  final double angleDeg;
  final double radiusMm;
  final BendLineRole role;
  final String direction; // 'up' or 'down'
  final double kFactor;

  const SheetBendFeature({
    required super.id,
    required super.name,
    required this.bendLineId,
    required this.angleDeg,
    required this.radiusMm,
    this.role = BendLineRole.bend,
    this.direction = 'up',
    this.kFactor = 0.40,
    super.isVisible,
    super.isSuppressed,
    super.parentFeatureId,
    super.properties,
  }) : super(type: CadFeatureType.bend);

  /// Whether this feature is an edge return flange
  bool get isFlange => role == BendLineRole.flange;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'bend',
    'id': id,
    'name': name,
    'bendLineId': bendLineId,
    'angleDeg': angleDeg,
    'radiusMm': radiusMm,
    'role': role.name,
    'direction': direction,
    'kFactor': kFactor,
    'isVisible': isVisible,
    'isSuppressed': isSuppressed,
    if (parentFeatureId != null) 'parentFeatureId': parentFeatureId,
    'properties': properties,
  };

  factory SheetBendFeature.fromJson(Map<String, dynamic> json) =>
      SheetBendFeature(
        id: json['id'] as String,
        name: json['name'] as String,
        bendLineId: json['bendLineId'] as String,
        angleDeg: (json['angleDeg'] as num).toDouble(),
        radiusMm: (json['radiusMm'] as num).toDouble(),
        role: BendLineRole.fromString(json['role'] as String?),
        direction: json['direction'] as String? ?? 'up',
        kFactor: (json['kFactor'] as num?)?.toDouble() ?? 0.40,
        isVisible: json['isVisible'] as bool? ?? true,
        isSuppressed: json['isSuppressed'] as bool? ?? false,
        parentFeatureId: json['parentFeatureId'] as String?,
        properties: (json['properties'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Feature representing a group of perforation punch holes
class SheetPatternFeature extends CadFeature {
  final String patternId;
  final String holeType; // 'obroundSlot', 'roundHole', 'square', 'rect'
  final int countX;
  final int countY;
  final double pitchX;
  final double pitchY;
  final bool staggered;

  const SheetPatternFeature({
    required super.id,
    required super.name,
    required this.patternId,
    required this.holeType,
    required this.countX,
    required this.countY,
    required this.pitchX,
    required this.pitchY,
    this.staggered = false,
    super.isVisible,
    super.isSuppressed,
    super.parentFeatureId,
    super.properties,
  }) : super(type: CadFeatureType.holePattern);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'holePattern',
    'id': id,
    'name': name,
    'patternId': patternId,
    'holeType': holeType,
    'countX': countX,
    'countY': countY,
    'pitchX': pitchX,
    'pitchY': pitchY,
    'staggered': staggered,
    'isVisible': isVisible,
    'isSuppressed': isSuppressed,
    if (parentFeatureId != null) 'parentFeatureId': parentFeatureId,
    'properties': properties,
  };

  factory SheetPatternFeature.fromJson(Map<String, dynamic> json) =>
      SheetPatternFeature(
        id: json['id'] as String,
        name: json['name'] as String,
        patternId: json['patternId'] as String,
        holeType: json['holeType'] as String,
        countX: json['countX'] as int,
        countY: json['countY'] as int,
        pitchX: (json['pitchX'] as num).toDouble(),
        pitchY: (json['pitchY'] as num).toDouble(),
        staggered: json['staggered'] as bool? ?? false,
        isVisible: json['isVisible'] as bool? ?? true,
        isSuppressed: json['isSuppressed'] as bool? ?? false,
        parentFeatureId: json['parentFeatureId'] as String?,
        properties: (json['properties'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Feature representing an individual CNC punch or drilled hole
class SheetHoleFeature extends CadFeature {
  final String punchId;
  final String holeType; // 'roundHole', 'obroundSlot', 'square', 'rectangle'
  final double x;
  final double y;
  final double diameterOrWidth;
  final double length;

  const SheetHoleFeature({
    required super.id,
    required super.name,
    required this.punchId,
    required this.holeType,
    required this.x,
    required this.y,
    this.diameterOrWidth = 8.0,
    this.length = 8.0,
    super.isVisible,
    super.isSuppressed,
    super.parentFeatureId,
    super.properties,
  }) : super(type: CadFeatureType.hole);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'hole',
    'id': id,
    'name': name,
    'punchId': punchId,
    'holeType': holeType,
    'x': x,
    'y': y,
    'diameterOrWidth': diameterOrWidth,
    'length': length,
    'isVisible': isVisible,
    'isSuppressed': isSuppressed,
    if (parentFeatureId != null) 'parentFeatureId': parentFeatureId,
    'properties': properties,
  };

  factory SheetHoleFeature.fromJson(Map<String, dynamic> json) =>
      SheetHoleFeature(
        id: json['id'] as String,
        name: json['name'] as String,
        punchId: json['punchId'] as String,
        holeType: json['holeType'] as String? ?? 'roundHole',
        x: (json['x'] as num?)?.toDouble() ?? 0.0,
        y: (json['y'] as num?)?.toDouble() ?? 0.0,
        diameterOrWidth: (json['diameterOrWidth'] as num?)?.toDouble() ?? 8.0,
        length: (json['length'] as num?)?.toDouble() ?? 8.0,
        isVisible: json['isVisible'] as bool? ?? true,
        isSuppressed: json['isSuppressed'] as bool? ?? false,
        parentFeatureId: json['parentFeatureId'] as String?,
        properties: (json['properties'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Feature representing a laser cut line, slit, or internal cutout
class SheetCutoutFeature extends CadFeature {
  final String cutId;
  final double lengthMm;

  const SheetCutoutFeature({
    required super.id,
    required super.name,
    required this.cutId,
    this.lengthMm = 0.0,
    super.isVisible,
    super.isSuppressed,
    super.parentFeatureId,
    super.properties,
  }) : super(type: CadFeatureType.laserCut);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'laserCut',
    'id': id,
    'name': name,
    'cutId': cutId,
    'lengthMm': lengthMm,
    'isVisible': isVisible,
    'isSuppressed': isSuppressed,
    if (parentFeatureId != null) 'parentFeatureId': parentFeatureId,
    'properties': properties,
  };

  factory SheetCutoutFeature.fromJson(Map<String, dynamic> json) =>
      SheetCutoutFeature(
        id: json['id'] as String,
        name: json['name'] as String,
        cutId: json['cutId'] as String,
        lengthMm: (json['lengthMm'] as num?)?.toDouble() ?? 0.0,
        isVisible: json['isVisible'] as bool? ?? true,
        isSuppressed: json['isSuppressed'] as bool? ?? false,
        parentFeatureId: json['parentFeatureId'] as String?,
        properties: (json['properties'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Feature representing a corner or bend relief notch
class SheetReliefFeature extends CadFeature {
  final String
  reliefType; // 'rectangular', 'roundTear', 'slit', 'fillet', 'chamfer'
  final double widthMm;
  final double depthMm;
  final String? associatedBendId;

  const SheetReliefFeature({
    required super.id,
    required super.name,
    required this.reliefType,
    this.widthMm = 2.0,
    this.depthMm = 3.0,
    this.associatedBendId,
    super.isVisible,
    super.isSuppressed,
    super.parentFeatureId,
    super.properties,
  }) : super(type: CadFeatureType.reliefNotch);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'reliefNotch',
    'id': id,
    'name': name,
    'reliefType': reliefType,
    'widthMm': widthMm,
    'depthMm': depthMm,
    if (associatedBendId != null) 'associatedBendId': associatedBendId,
    'isVisible': isVisible,
    'isSuppressed': isSuppressed,
    if (parentFeatureId != null) 'parentFeatureId': parentFeatureId,
    'properties': properties,
  };

  factory SheetReliefFeature.fromJson(Map<String, dynamic> json) =>
      SheetReliefFeature(
        id: json['id'] as String,
        name: json['name'] as String,
        reliefType: json['reliefType'] as String? ?? 'rectangular',
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 2.0,
        depthMm: (json['depthMm'] as num?)?.toDouble() ?? 3.0,
        associatedBendId: json['associatedBendId'] as String?,
        isVisible: json['isVisible'] as bool? ?? true,
        isSuppressed: json['isSuppressed'] as bool? ?? false,
        parentFeatureId: json['parentFeatureId'] as String?,
        properties: (json['properties'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Helper to build and manage the canonical CAD feature tree from a DsfDocument
class CadFeatureTreeBuilder {
  static List<CadFeature> buildFeatures(DsfDocument doc) {
    final features = <CadFeature>[];

    // 1. Base Geometry / Sheet
    features.add(
      SheetBaseFeature(
        id: 'FEAT_BASE',
        name: 'Base Geometry',
        faceId: doc.baseFaceId.isNotEmpty
            ? doc.baseFaceId
            : (doc.faces.isNotEmpty ? doc.faces.first.id : 'BASE'),
        areaMm2: doc.faces.isNotEmpty ? doc.faces.first.areaMm2 : 0.0,
      ),
    );

    // 2. Bends & Flanges
    int bendIdx = 1;
    int flangeIdx = 1;
    for (final bend in doc.bends) {
      final isFlange = bend.isFlange;
      features.add(
        SheetBendFeature(
          id: 'FEAT_${bend.id}',
          name: isFlange
              ? 'Flange ${flangeIdx.toString().padLeft(2, "0")} (${bend.id})'
              : 'Bend ${bendIdx.toString().padLeft(2, "0")} (${bend.id})',
          bendLineId: bend.id,
          angleDeg: bend.targetAngleDeg,
          radiusMm: bend.radiusMm,
          role: bend.role,
          direction: bend.direction == BendDirection.up ? 'up' : 'down',
          kFactor: bend.kFactor ?? doc.material.kFactor,
          isVisible: bend.isVisible,
          isSuppressed: !bend.isVisible,
        ),
      );
      if (isFlange) {
        flangeIdx++;
      } else {
        bendIdx++;
      }
    }

    // 3. Hole Patterns
    int patIdx = 1;
    for (final pat in doc.perforationPatterns) {
      features.add(
        SheetPatternFeature(
          id: 'FEAT_${pat.id}',
          name: 'Hole Pattern ${patIdx.toString().padLeft(2, "0")} (${pat.id})',
          patternId: pat.id,
          holeType: pat.holeType.name,
          countX: pat.countX,
          countY: pat.countY,
          pitchX: pat.pitchX,
          pitchY: pat.pitchY,
          staggered: pat.staggered,
          isVisible: pat.isVisible,
          isSuppressed: !pat.isVisible,
        ),
      );
      patIdx++;
    }

    // 4. Standalone Holes / Punches
    int holeIdx = 1;
    for (final p in doc.punches) {
      features.add(
        SheetHoleFeature(
          id: 'FEAT_${p.id}',
          name: 'Hole ${holeIdx.toString().padLeft(2, "0")} (${p.id})',
          punchId: p.id,
          holeType: p.type.name,
          x: p.center.x,
          y: p.center.y,
          diameterOrWidth: p.isRound ? p.diameterMm : p.widthMm,
          length: p.isRound ? p.diameterMm : p.lengthMm,
          isVisible: p.isVisible,
          isSuppressed: !p.isVisible,
        ),
      );
      holeIdx++;
    }

    // 5. Cutouts / Laser Slits
    int cutIdx = 1;
    for (final c in doc.cutLines) {
      features.add(
        SheetCutoutFeature(
          id: 'FEAT_${c.id}',
          name: 'Cutout ${cutIdx.toString().padLeft(2, "0")} (${c.id})',
          cutId: c.id,
          lengthMm: c.length,
          isVisible: true,
          isSuppressed: false,
        ),
      );
      cutIdx++;
    }

    // 6. Corner / Bend Reliefs
    int reliefIdx = 1;
    for (final corner in doc.corners) {
      features.add(
        SheetReliefFeature(
          id: 'FEAT_CR_${corner.vertexIndex}',
          name: 'Corner Relief ${reliefIdx.toString().padLeft(2, "0")}',
          reliefType: corner.type == CornerType.chamfer ? 'chamfer' : 'fillet',
          widthMm: corner.sizeMm,
          depthMm: corner.sizeMm,
        ),
      );
      reliefIdx++;
    }

    return features;
  }
}
