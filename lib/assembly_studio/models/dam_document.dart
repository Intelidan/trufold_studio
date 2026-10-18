// =============================================================================
// dam_document.dart
//
// TruFold Digital Assembly Model (.dam) Specification & Data Model.
// A self-contained, portable assembly definition storing 3D parts, kinematic
// joints, welds, sheet metal parameters, sketches, extrusions, cuts, and
// associated .dsf component definitions.
// =============================================================================

// Pure DTO specification with zero external dependencies


class DamDocument {
  static const String currentFormat = 'TRUFOLD_DAM';
  static const String currentVersion = '1.0';

  final String format;
  final String version;
  final String title;
  final String systemType; // 'Cable Ladder', 'Cable Tray', 'Cable Trunking', 'Custom'
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String units; // 'mm'
  final Map<String, dynamic> metadata;
  final List<DamPartData> parts;
  final List<DamWeldData> welds;
  final List<DamJointData> joints;
  final List<DamSketchPlaneData> sketchPlanes;
  final List<DamFeatureTreeItemData> featureTree;
  final Map<String, double> parameters;

  DamDocument({
    this.format = currentFormat,
    this.version = currentVersion,
    required this.title,
    this.systemType = 'Cable Management System',
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.units = 'mm',
    this.metadata = const {},
    this.parts = const [],
    this.welds = const [],
    this.joints = const [],
    this.sketchPlanes = const [],
    this.featureTree = const [],
    this.parameters = const {},
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'format': format,
        'version': version,
        'title': title,
        'systemType': systemType,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'units': units,
        'metadata': metadata,
        'parameters': parameters,
        'parts': parts.map((p) => p.toJson()).toList(),
        'welds': welds.map((w) => w.toJson()).toList(),
        'joints': joints.map((j) => j.toJson()).toList(),
        'sketchPlanes': sketchPlanes.map((s) => s.toJson()).toList(),
        'featureTree': featureTree.map((f) => f.toJson()).toList(),
      };

  factory DamDocument.fromJson(Map<String, dynamic> json) {
    return DamDocument(
      format: json['format'] as String? ?? currentFormat,
      version: json['version'] as String? ?? currentVersion,
      title: json['title'] as String? ?? 'Untitled Assembly',
      systemType: json['systemType'] as String? ?? 'Cable Management System',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      modifiedAt: json['modifiedAt'] != null ? DateTime.tryParse(json['modifiedAt'] as String) : null,
      units: json['units'] as String? ?? 'mm',
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      parameters: (json['parameters'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          {},
      parts: (json['parts'] as List<dynamic>?)
              ?.map((e) => DamPartData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      welds: (json['welds'] as List<dynamic>?)
              ?.map((e) => DamWeldData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      joints: (json['joints'] as List<dynamic>?)
              ?.map((e) => DamJointData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      sketchPlanes: (json['sketchPlanes'] as List<dynamic>?)
              ?.map((e) => DamSketchPlaneData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      featureTree: (json['featureTree'] as List<dynamic>?)
              ?.map((e) => DamFeatureTreeItemData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

// -----------------------------------------------------------------------------
// Serialized Part Data
// -----------------------------------------------------------------------------
class DamPartData {
  final String id;
  final String name;
  final String typeName;
  final double posX, posY, posZ;
  final double rotX, rotY, rotZ;
  final double length;
  final double height;
  final double flangeWidth;
  final double thickness;
  final bool isFlangeOutward;
  final int colorValue;
  final bool isVisible;
  final String? parentPartId;
  final String? matedSlotEntityId;
  final String mateStyle;
  final List<String> weldedToPartIds;
  final String? sourceDsfJson;
  final List<Map<String, dynamic>>? customPolygonsJson;
  final Map<String, dynamic> extraMetadata;

  DamPartData({
    required this.id,
    required this.name,
    required this.typeName,
    this.posX = 0,
    this.posY = 0,
    this.posZ = 0,
    this.rotX = 0,
    this.rotY = 0,
    this.rotZ = 0,
    this.length = 600,
    this.height = 100,
    this.flangeWidth = 20,
    this.thickness = 2.0,
    this.isFlangeOutward = false,
    this.colorValue = 0xFF6C9DC6,
    this.isVisible = true,
    this.parentPartId,
    this.matedSlotEntityId,
    this.mateStyle = 'passThrough',
    this.weldedToPartIds = const [],
    this.sourceDsfJson,
    this.customPolygonsJson,
    this.extraMetadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'typeName': typeName,
        'position': [posX, posY, posZ],
        'rotation': [rotX, rotY, rotZ],
        'length': length,
        'height': height,
        'flangeWidth': flangeWidth,
        'thickness': thickness,
        'isFlangeOutward': isFlangeOutward,
        'color': colorValue,
        'isVisible': isVisible,
        'parentPartId': parentPartId,
        'matedSlotEntityId': matedSlotEntityId,
        'mateStyle': mateStyle,
        'weldedToPartIds': weldedToPartIds,
        'sourceDsfJson': sourceDsfJson,
        'customPolygons': customPolygonsJson,
        'extraMetadata': extraMetadata,
      };

  factory DamPartData.fromJson(Map<String, dynamic> json) {
    final pos = (json['position'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0, 0.0];
    final rot = (json['rotation'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0, 0.0];
    return DamPartData(
      id: json['id'] as String? ?? 'part_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Part',
      typeName: json['typeName'] as String? ?? 'straightRail',
      posX: pos.isNotEmpty ? pos[0] : 0.0,
      posY: pos.length > 1 ? pos[1] : 0.0,
      posZ: pos.length > 2 ? pos[2] : 0.0,
      rotX: rot.isNotEmpty ? rot[0] : 0.0,
      rotY: rot.length > 1 ? rot[1] : 0.0,
      rotZ: rot.length > 2 ? rot[2] : 0.0,
      length: (json['length'] as num?)?.toDouble() ?? 600.0,
      height: (json['height'] as num?)?.toDouble() ?? 100.0,
      flangeWidth: (json['flangeWidth'] as num?)?.toDouble() ?? 20.0,
      thickness: (json['thickness'] as num?)?.toDouble() ?? 2.0,
      isFlangeOutward: json['isFlangeOutward'] as bool? ?? false,
      colorValue: json['color'] as int? ?? 0xFF6C9DC6,
      isVisible: json['isVisible'] as bool? ?? true,
      parentPartId: json['parentPartId'] as String?,
      matedSlotEntityId: json['matedSlotEntityId'] as String?,
      mateStyle: json['mateStyle'] as String? ?? 'passThrough',
      weldedToPartIds: (json['weldedToPartIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      sourceDsfJson: json['sourceDsfJson'] as String?,
      customPolygonsJson: (json['customPolygons'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList(),
      extraMetadata: (json['extraMetadata'] as Map<String, dynamic>?) ?? {},
    );
  }
}

// -----------------------------------------------------------------------------
// Serialized Weld Data
// -----------------------------------------------------------------------------
class DamWeldData {
  final String id;
  final String partAId;
  final String partBId;
  final double wx, wy, wz;
  final double ax, ay, az;
  final double weldLengthMm;
  final double weldSizeMm;
  final bool bothSides;
  final double? sWx, sWy, sWz;
  final String jointDescription;
  final String jointTypeName;
  final String mateStyle;

  DamWeldData({
    required this.id,
    required this.partAId,
    required this.partBId,
    required this.wx,
    required this.wy,
    required this.wz,
    this.ax = 1.0,
    this.ay = 0.0,
    this.az = 0.0,
    this.weldLengthMm = 40.0,
    this.weldSizeMm = 6.0,
    this.bothSides = false,
    this.sWx,
    this.sWy,
    this.sWz,
    this.jointDescription = 'Fillet Weld',
    this.jointTypeName = 'welded',
    this.mateStyle = 'passThrough',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'partAId': partAId,
        'partBId': partBId,
        'weldPoint': [wx, wy, wz],
        'weldAxis': [ax, ay, az],
        'weldLengthMm': weldLengthMm,
        'weldSizeMm': weldSizeMm,
        'bothSides': bothSides,
        'secondWeldPoint': sWx != null ? [sWx, sWy, sWz] : null,
        'jointDescription': jointDescription,
        'jointType': jointTypeName,
        'mateStyle': mateStyle,
      };

  factory DamWeldData.fromJson(Map<String, dynamic> json) {
    final pt = (json['weldPoint'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0, 0.0];
    final ax = (json['weldAxis'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [1.0, 0.0, 0.0];
    final sPt = (json['secondWeldPoint'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList();
    return DamWeldData(
      id: json['id'] as String? ?? 'weld_${DateTime.now().millisecondsSinceEpoch}',
      partAId: json['partAId'] as String? ?? '',
      partBId: json['partBId'] as String? ?? '',
      wx: pt.isNotEmpty ? pt[0] : 0.0,
      wy: pt.length > 1 ? pt[1] : 0.0,
      wz: pt.length > 2 ? pt[2] : 0.0,
      ax: ax.isNotEmpty ? ax[0] : 1.0,
      ay: ax.length > 1 ? ax[1] : 0.0,
      az: ax.length > 2 ? ax[2] : 0.0,
      weldLengthMm: (json['weldLengthMm'] as num?)?.toDouble() ?? 40.0,
      weldSizeMm: (json['weldSizeMm'] as num?)?.toDouble() ?? 6.0,
      bothSides: json['bothSides'] as bool? ?? false,
      sWx: sPt != null && sPt.isNotEmpty ? sPt[0] : null,
      sWy: sPt != null && sPt.length > 1 ? sPt[1] : null,
      sWz: sPt != null && sPt.length > 2 ? sPt[2] : null,
      jointDescription: json['jointDescription'] as String? ?? 'Fillet Weld',
      jointTypeName: json['jointType'] as String? ?? 'welded',
      mateStyle: json['mateStyle'] as String? ?? 'passThrough',
    );
  }
}

// -----------------------------------------------------------------------------
// Serialized Joint Data
// -----------------------------------------------------------------------------
class DamJointData {
  final String id;
  final String partAId;
  final String partBId;
  final String type; // 'welded', 'fused', 'hinged', 'slotMate'
  final Map<String, dynamic> parameters;

  DamJointData({
    required this.id,
    required this.partAId,
    required this.partBId,
    this.type = 'welded',
    this.parameters = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'partAId': partAId,
        'partBId': partBId,
        'type': type,
        'parameters': parameters,
      };

  factory DamJointData.fromJson(Map<String, dynamic> json) => DamJointData(
        id: json['id'] as String? ?? '',
        partAId: json['partAId'] as String? ?? '',
        partBId: json['partBId'] as String? ?? '',
        type: json['type'] as String? ?? 'welded',
        parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
      );
}

// -----------------------------------------------------------------------------
// Serialized Sketch Plane Data
// -----------------------------------------------------------------------------
class DamSketchPlaneData {
  final String id;
  final String name;
  final String planeType;
  final double ox, oy, oz;
  final double nx, ny, nz;
  final double ux, uy, uz;
  final double size;
  final String? targetPartId;
  final List<Map<String, dynamic>> primitives;
  final List<Map<String, dynamic>> constraints;

  DamSketchPlaneData({
    required this.id,
    required this.name,
    required this.planeType,
    required this.ox,
    required this.oy,
    required this.oz,
    required this.nx,
    required this.ny,
    required this.nz,
    required this.ux,
    required this.uy,
    required this.uz,
    this.size = 140.0,
    this.targetPartId,
    this.primitives = const [],
    this.constraints = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'planeType': planeType,
        'origin': [ox, oy, oz],
        'normal': [nx, ny, nz],
        'up': [ux, uy, uz],
        'size': size,
        'targetPartId': targetPartId,
        'primitives': primitives,
        'constraints': constraints,
      };

  factory DamSketchPlaneData.fromJson(Map<String, dynamic> json) {
    final o = (json['origin'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0, 0.0];
    final n = (json['normal'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0, 1.0];
    final u = (json['up'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 1.0, 0.0];
    return DamSketchPlaneData(
      id: json['id'] as String? ?? 'plane_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Sketch Plane',
      planeType: json['planeType'] as String? ?? 'custom',
      ox: o.isNotEmpty ? o[0] : 0.0,
      oy: o.length > 1 ? o[1] : 0.0,
      oz: o.length > 2 ? o[2] : 0.0,
      nx: n.isNotEmpty ? n[0] : 0.0,
      ny: n.length > 1 ? n[1] : 0.0,
      nz: n.length > 2 ? n[2] : 1.0,
      ux: u.isNotEmpty ? u[0] : 0.0,
      uy: u.length > 1 ? u[1] : 1.0,
      uz: u.length > 2 ? u[2] : 0.0,
      size: (json['size'] as num?)?.toDouble() ?? 140.0,
      targetPartId: json['targetPartId'] as String?,
      primitives: (json['primitives'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [],
      constraints: (json['constraints'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [],
    );
  }
}

// -----------------------------------------------------------------------------
// Serialized Feature Tree Item Data
// -----------------------------------------------------------------------------
class DamFeatureTreeItemData {
  final String id;
  final String name;
  final String kind;
  final String? entityId;
  final String? parentSketchId;
  final Map<String, dynamic> parameters;
  final bool isSuppressed;

  DamFeatureTreeItemData({
    required this.id,
    required this.name,
    required this.kind,
    this.entityId,
    this.parentSketchId,
    this.parameters = const {},
    this.isSuppressed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'entityId': entityId,
        'parentSketchId': parentSketchId,
        'parameters': parameters,
        'isSuppressed': isSuppressed,
      };

  factory DamFeatureTreeItemData.fromJson(Map<String, dynamic> json) => DamFeatureTreeItemData(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'sketch',
        entityId: json['entityId'] as String?,
        parentSketchId: json['parentSketchId'] as String?,
        parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
        isSuppressed: json['isSuppressed'] as bool? ?? false,
      );
}
