import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sheet_metal_studio/models/cad_primitives.dart';
import '../../sheet_metal_studio/engine/kinematic_fold_engine.dart';

/// Type of modular component used in the assembly studio.
enum AssemblyPartType {
  rung,
  channel,
  angle,
  rod,
  bar,
  iBeam,
  straightRail,
  bentRail,
  // Phase 2 Industrial Ladder & Safety Accessories:
  walkThroughStile,
  boxTubeStile,
  diamondGripRung,
  wideStepTread,
  safetyCageHoop,
  safetyCageBellHoop,
  cageStrap,
  standoffBracket,
  baseFootPlate,
  splicePlate,
  swingGate,
}

/// Type of 3D joint / mate between parts in an assembly set.
enum AssemblyJointType { welded, fused, hinged, slotMate }

/// Definition of a segment in a multi-segment / bent rail.
class RailSegmentDefinition {
  final String id;
  double length;
  double bendAngleDeg; // Angle relative to preceding segment (e.g. 45°, 90°)
  bool hasFlangeVNotch; // Auto-cut V-notch on top & bottom flanges for bending

  RailSegmentDefinition({required this.id, required this.length, this.bendAngleDeg = 0.0, this.hasFlangeVNotch = true});

  RailSegmentDefinition copyWith({String? id, double? length, double? bendAngleDeg, bool? hasFlangeVNotch}) {
    return RailSegmentDefinition(
      id: id ?? this.id,
      length: length ?? this.length,
      bendAngleDeg: bendAngleDeg ?? this.bendAngleDeg,
      hasFlangeVNotch: hasFlangeVNotch ?? this.hasFlangeVNotch,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'length': length, 'bendAngleDeg': bendAngleDeg, 'hasFlangeVNotch': hasFlangeVNotch};

  factory RailSegmentDefinition.fromJson(Map<String, dynamic> json) => RailSegmentDefinition(
    id: json['id'] as String,
    length: (json['length'] as num).toDouble(),
    bendAngleDeg: (json['bendAngleDeg'] as num?)?.toDouble() ?? 0.0,
    hasFlangeVNotch: json['hasFlangeVNotch'] as bool? ?? true,
  );
}

/// Feature sketched directly on a part face (holes, slots, cuts, bends, punched rung slots).
class AssemblySketchFeature {
  final String id;
  final String featureType; // 'circle_hole', 'obround_slot', 'rect_cut', 'bend_line', 'rung_slot'
  CadPoint2D localCenter;
  double widthMm;
  double heightMm;
  double angleDeg;
  bool isRungSlotEntity; // When true, acts as an interactive punched rung hole entity
  String? matedRungPartId; // Id of C-channel rung linked to this slot entity
  String mateStyle; // 'passThrough' or 'directInside'
  bool isUpsideDown; // When true, mated rung is rotated upside down (180°)
  double distanceAlongRailMm; // Linear distance along the rail web from origin
  String targetFace; // 'web', 'flange_top', 'flange_bottom', or specific faceId

  AssemblySketchFeature({
    required this.id,
    required this.featureType,
    required this.localCenter,
    this.widthMm = 10.0,
    this.heightMm = 10.0,
    this.angleDeg = 0.0,
    this.isRungSlotEntity = false,
    this.matedRungPartId,
    this.mateStyle = 'passThrough',
    this.isUpsideDown = false,
    this.distanceAlongRailMm = 0.0,
    this.targetFace = 'web',
  });

  AssemblySketchFeature copyWith({
    String? id,
    String? featureType,
    CadPoint2D? localCenter,
    double? widthMm,
    double? heightMm,
    double? angleDeg,
    bool? isRungSlotEntity,
    String? matedRungPartId,
    String? mateStyle,
    bool? isUpsideDown,
    double? distanceAlongRailMm,
    String? targetFace,
  }) {
    return AssemblySketchFeature(
      id: id ?? this.id,
      featureType: featureType ?? this.featureType,
      localCenter: localCenter ?? this.localCenter,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      angleDeg: angleDeg ?? this.angleDeg,
      isRungSlotEntity: isRungSlotEntity ?? this.isRungSlotEntity,
      matedRungPartId: matedRungPartId ?? this.matedRungPartId,
      mateStyle: mateStyle ?? this.mateStyle,
      isUpsideDown: isUpsideDown ?? this.isUpsideDown,
      distanceAlongRailMm: distanceAlongRailMm ?? this.distanceAlongRailMm,
      targetFace: targetFace ?? this.targetFace,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'featureType': featureType,
    'localCenterX': localCenter.x,
    'localCenterY': localCenter.y,
    'widthMm': widthMm,
    'heightMm': heightMm,
    'angleDeg': angleDeg,
    'isRungSlotEntity': isRungSlotEntity,
    'matedRungPartId': matedRungPartId,
    'mateStyle': mateStyle,
    'isUpsideDown': isUpsideDown,
    'distanceAlongRailMm': distanceAlongRailMm,
    'targetFace': targetFace,
  };

  factory AssemblySketchFeature.fromJson(Map<String, dynamic> json) => AssemblySketchFeature(
    id: json['id'] as String,
    featureType: json['featureType'] as String,
    localCenter: CadPoint2D((json['localCenterX'] as num).toDouble(), (json['localCenterY'] as num).toDouble()),
    widthMm: (json['widthMm'] as num?)?.toDouble() ?? 10.0,
    heightMm: (json['heightMm'] as num?)?.toDouble() ?? 10.0,
    angleDeg: (json['angleDeg'] as num?)?.toDouble() ?? 0.0,
    isRungSlotEntity: json['isRungSlotEntity'] as bool? ?? false,
    matedRungPartId: json['matedRungPartId'] as String?,
    mateStyle: json['mateStyle'] as String? ?? 'passThrough',
    isUpsideDown: json['isUpsideDown'] as bool? ?? false,
    distanceAlongRailMm: (json['distanceAlongRailMm'] as num?)?.toDouble() ?? 0.0,
    targetFace: json['targetFace'] as String? ?? 'web',
  );
}

/// Represents a localized magnetic snap spot positioned on an entity surface.
class AssemblyMagneticSpot {
  final String id;
  final String partId;
  final CadPoint3D localPoint; // in local part coordinate space
  final CadPoint3D normal; // surface normal vector at the spot (e.g. 0, 0, 1)
  final String name;

  AssemblyMagneticSpot({
    required this.id,
    required this.partId,
    required this.localPoint,
    this.normal = const CadPoint3D(0.0, 0.0, 1.0),
    this.name = 'Magnetic Point',
  });

  /// Transforms this local spot to world 3D coordinates using the owning part's transform.
  CadPoint3D toWorldPoint(AssemblyPart part) => part.toWorld(localPoint);

  /// Transforms the spot's surface normal to world 3D coordinates.
  CadPoint3D toWorldNormal(AssemblyPart part) => part.normalToWorld(normal);

  Map<String, dynamic> toJson() => {
    'id': id,
    'partId': partId,
    'localPoint': {'x': localPoint.x, 'y': localPoint.y, 'z': localPoint.z},
    'normal': {'x': normal.x, 'y': normal.y, 'z': normal.z},
    'name': name,
  };

  factory AssemblyMagneticSpot.fromJson(Map<String, dynamic> json) {
    final lp = json['localPoint'] as Map<String, dynamic>;
    final norm = json['normal'] as Map<String, dynamic>?;
    return AssemblyMagneticSpot(
      id: json['id'] as String,
      partId: json['partId'] as String,
      localPoint: CadPoint3D((lp['x'] as num).toDouble(), (lp['y'] as num).toDouble(), (lp['z'] as num).toDouble()),
      normal: norm != null
          ? CadPoint3D((norm['x'] as num).toDouble(), (norm['y'] as num).toDouble(), (norm['z'] as num).toDouble())
          : const CadPoint3D(0.0, 0.0, 1.0),
      name: json['name'] as String? ?? 'Magnetic Point',
    );
  }
}

/// Represents a dynamic magnetic attraction link between two parts via magnetic spots.
/// Unlike welded joints, magnetically linked entities can rotate in place around the joint without breaking it.
class AssemblyMagneticJoint {
  final String id;
  final String partAId;
  final String spotAId;
  final String partBId;
  final String spotBId;
  final double currentAngleDeg;

  AssemblyMagneticJoint({
    required this.id,
    required this.partAId,
    required this.spotAId,
    required this.partBId,
    required this.spotBId,
    this.currentAngleDeg = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'partAId': partAId,
    'spotAId': spotAId,
    'partBId': partBId,
    'spotBId': spotBId,
    'currentAngleDeg': currentAngleDeg,
  };

  factory AssemblyMagneticJoint.fromJson(Map<String, dynamic> json) => AssemblyMagneticJoint(
    id: json['id'] as String,
    partAId: json['partAId'] as String,
    spotAId: json['spotAId'] as String,
    partBId: json['partBId'] as String,
    spotBId: json['spotBId'] as String,
    currentAngleDeg: (json['currentAngleDeg'] as num?)?.toDouble() ?? 0.0,
  );
}

/// Represents a persistent weld/bond/hinge/slot-mate connection between two parts in 3D.
class AssemblyWeldJoint {
  final String id;
  final String partAId;
  final String partBId;
  final CadPoint3D weldPoint; // In world coordinates (root of primary bead)
  final String jointDescription;
  final double weldSizeMm; // Leg size 'a' (e.g. 6mm)
  final AssemblyJointType jointType;
  final double hingeAngleDeg;
  final String mateStyle;
  final double weldLengthMm;
  final CadPoint3D weldAxis; // Vector along the seam axis
  final CadPoint3D? legDir1; // Vector along Part A surface away from root
  final CadPoint3D? legDir2; // Vector along Part B surface away from root
  final bool bothSides; // If true, generates dual fillet weld beads (top & bottom per SS4)
  final CadPoint3D? secondWeldPoint; // Root point of second bead if bothSides is true
  final CadPoint3D? secondLegDir1;
  final CadPoint3D? secondLegDir2;
  final List<CadPoint3D>? pathPoints;
  final String standard;

  AssemblyWeldJoint({
    required this.id,
    required this.partAId,
    required this.partBId,
    required this.weldPoint,
    this.jointDescription = 'Fillet Weld (6mm)',
    this.weldSizeMm = 6.0,
    this.jointType = AssemblyJointType.welded,
    this.hingeAngleDeg = 0.0,
    this.mateStyle = 'passThrough',
    this.weldLengthMm = 40.0,
    this.weldAxis = const CadPoint3D(1.0, 0.0, 0.0),
    this.legDir1,
    this.legDir2,
    this.bothSides = false,
    this.secondWeldPoint,
    this.secondLegDir1,
    this.secondLegDir2,
    this.pathPoints,
    this.standard = 'AWS D1.1 / ISO 2553',
  });

  /// Engineering weld callout symbol per AWS / ISO standard (SS4)
  String get weldSymbol => bothSides ? '△△ ${weldSizeMm.toInt()}mm Fillet (Both Sides)' : '△ ${weldSizeMm.toInt()}mm Fillet';

  /// Theoretical throat (t = 0.707 * a) per AWS D1.1 / ISO 2553 / ISO 5817 (SS5)
  double get throatMm => 0.7071 * weldSizeMm;

  AssemblyWeldJoint copyWith({
    String? id,
    String? partAId,
    String? partBId,
    CadPoint3D? weldPoint,
    String? jointDescription,
    double? weldSizeMm,
    AssemblyJointType? jointType,
    double? hingeAngleDeg,
    String? mateStyle,
    double? weldLengthMm,
    CadPoint3D? weldAxis,
    CadPoint3D? legDir1,
    CadPoint3D? legDir2,
    bool? bothSides,
    CadPoint3D? secondWeldPoint,
    CadPoint3D? secondLegDir1,
    CadPoint3D? secondLegDir2,
    List<CadPoint3D>? pathPoints,
    String? standard,
  }) {
    return AssemblyWeldJoint(
      id: id ?? this.id,
      partAId: partAId ?? this.partAId,
      partBId: partBId ?? this.partBId,
      weldPoint: weldPoint ?? this.weldPoint,
      jointDescription: jointDescription ?? this.jointDescription,
      weldSizeMm: weldSizeMm ?? this.weldSizeMm,
      jointType: jointType ?? this.jointType,
      hingeAngleDeg: hingeAngleDeg ?? this.hingeAngleDeg,
      mateStyle: mateStyle ?? this.mateStyle,
      weldLengthMm: weldLengthMm ?? this.weldLengthMm,
      weldAxis: weldAxis ?? this.weldAxis,
      legDir1: legDir1 ?? this.legDir1,
      legDir2: legDir2 ?? this.legDir2,
      bothSides: bothSides ?? this.bothSides,
      secondWeldPoint: secondWeldPoint ?? this.secondWeldPoint,
      secondLegDir1: secondLegDir1 ?? this.secondLegDir1,
      secondLegDir2: secondLegDir2 ?? this.secondLegDir2,
      pathPoints: pathPoints ?? this.pathPoints,
      standard: standard ?? this.standard,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'partAId': partAId,
    'partBId': partBId,
    'weldPoint': {'x': weldPoint.x, 'y': weldPoint.y, 'z': weldPoint.z},
    'jointDescription': jointDescription,
    'weldSizeMm': weldSizeMm,
    'jointType': jointType.name,
    'hingeAngleDeg': hingeAngleDeg,
    'mateStyle': mateStyle,
    'weldLengthMm': weldLengthMm,
    'weldAxis': {'x': weldAxis.x, 'y': weldAxis.y, 'z': weldAxis.z},
    if (legDir1 != null) 'legDir1': {'x': legDir1!.x, 'y': legDir1!.y, 'z': legDir1!.z},
    if (legDir2 != null) 'legDir2': {'x': legDir2!.x, 'y': legDir2!.y, 'z': legDir2!.z},
    'bothSides': bothSides,
    if (secondWeldPoint != null) 'secondWeldPoint': {'x': secondWeldPoint!.x, 'y': secondWeldPoint!.y, 'z': secondWeldPoint!.z},
    if (secondLegDir1 != null) 'secondLegDir1': {'x': secondLegDir1!.x, 'y': secondLegDir1!.y, 'z': secondLegDir1!.z},
    if (secondLegDir2 != null) 'secondLegDir2': {'x': secondLegDir2!.x, 'y': secondLegDir2!.y, 'z': secondLegDir2!.z},
    if (pathPoints != null) 'pathPoints': pathPoints!.map((p) => {'x': p.x, 'y': p.y, 'z': p.z}).toList(),
    'standard': standard,
  };

  factory AssemblyWeldJoint.fromJson(Map<String, dynamic> json) {
    final pt = json['weldPoint'] as Map<String, dynamic>;
    final ax = json['weldAxis'] as Map<String, dynamic>?;
    final ld1 = json['legDir1'] as Map<String, dynamic>?;
    final ld2 = json['legDir2'] as Map<String, dynamic>?;
    final sPt = json['secondWeldPoint'] as Map<String, dynamic>?;
    final sLd1 = json['secondLegDir1'] as Map<String, dynamic>?;
    final sLd2 = json['secondLegDir2'] as Map<String, dynamic>?;
    final rawPath = json['pathPoints'] as List<dynamic>?;
    final List<CadPoint3D>? pPts = rawPath?.map((e) {
      final m = e as Map<String, dynamic>;
      return CadPoint3D((m['x'] as num).toDouble(), (m['y'] as num).toDouble(), (m['z'] as num).toDouble());
    }).toList();

    return AssemblyWeldJoint(
      id: json['id'] as String,
      partAId: json['partAId'] as String,
      partBId: json['partBId'] as String,
      weldPoint: CadPoint3D((pt['x'] as num).toDouble(), (pt['y'] as num).toDouble(), (pt['z'] as num).toDouble()),
      jointDescription: json['jointDescription'] as String? ?? 'Fillet Weld (6mm)',
      weldSizeMm: (json['weldSizeMm'] as num?)?.toDouble() ?? 6.0,
      jointType: json['jointType'] != null ? AssemblyJointType.values.byName(json['jointType'] as String) : AssemblyJointType.welded,
      hingeAngleDeg: (json['hingeAngleDeg'] as num?)?.toDouble() ?? 0.0,
      mateStyle: json['mateStyle'] as String? ?? 'passThrough',
      weldLengthMm: (json['weldLengthMm'] as num?)?.toDouble() ?? 40.0,
      weldAxis: ax != null
          ? CadPoint3D((ax['x'] as num).toDouble(), (ax['y'] as num).toDouble(), (ax['z'] as num).toDouble())
          : const CadPoint3D(1.0, 0.0, 0.0),
      legDir1: ld1 != null ? CadPoint3D((ld1['x'] as num).toDouble(), (ld1['y'] as num).toDouble(), (ld1['z'] as num).toDouble()) : null,
      legDir2: ld2 != null ? CadPoint3D((ld2['x'] as num).toDouble(), (ld2['y'] as num).toDouble(), (ld2['z'] as num).toDouble()) : null,
      bothSides: json['bothSides'] as bool? ?? false,
      secondWeldPoint: sPt != null ? CadPoint3D((sPt['x'] as num).toDouble(), (sPt['y'] as num).toDouble(), (sPt['z'] as num).toDouble()) : null,
      secondLegDir1: sLd1 != null ? CadPoint3D((sLd1['x'] as num).toDouble(), (sLd1['y'] as num).toDouble(), (sLd1['z'] as num).toDouble()) : null,
      secondLegDir2: sLd2 != null ? CadPoint3D((sLd2['x'] as num).toDouble(), (sLd2['y'] as num).toDouble(), (sLd2['z'] as num).toDouble()) : null,
      pathPoints: pPts,
      standard: json['standard'] as String? ?? 'AWS D1.1 / ISO 2553',
    );
  }
}

/// Core modular 3D sheet metal part entity for direct manipulation & assembly.
class AssemblyPart {
  final String id;
  String name;
  final AssemblyPartType type;
  CadPoint3D position; // World X, Y, Z
  CadPoint3D rotationDeg; // World Roll, Pitch, Yaw in degrees
  double length; // mm
  double height; // mm (web height)
  double flangeWidth; // mm (default 20.0mm, editable)
  double thickness; // mm (default 2.0mm)
  bool isFlangeOutward; // outward vs inward flange
  Color color;
  bool isVisible; // Visibility in 3D scene / viewport
  List<RailSegmentDefinition> segments; // For bent rails
  List<AssemblySketchFeature> sketches; // Cuts/holes/slots drawn on part
  List<String> weldedToPartIds; // Parts bonded to this part
  List<AssemblyMagneticSpot> magneticSpots; // Placed magnetic snap spots on part surface
  List<String> magneticallyLinkedPartIds; // Parts linked via magnetic attraction
  String? parentPartId; // Parent part id if this belongs to a unified assembly set
  String? matedSlotEntityId; // Punched rung slot entity id if mated
  String mateStyle; // 'passThrough' or 'directInside'
  bool isRungUpsideDown; // Rotated upside down (180°) inside slot
  double hingeAngleDeg; // For hinged joints
  AssemblyJointType? jointType; // Active connection type (welded, fused, hinged, slotMate)
  String? groupId; // Virtual group id if part belongs to a group
  String? groupName; // Virtual group name (e.g. 'Rung Group 1', 'Main Frame')
  String? componentDefinitionId; // Shared definition ID for instanced components (SketchUp Component paradigm)

  bool get isComponentInstance => componentDefinitionId != null;

  AssemblyPart({
    required this.id,
    required this.name,
    required this.type,
    this.position = const CadPoint3D(0.0, 0.0, 0.0),
    this.rotationDeg = const CadPoint3D(0.0, 0.0, 0.0),
    this.length = 600.0,
    this.height = 100.0,
    this.flangeWidth = 20.0, // User requested 20mm editable flange
    this.thickness = 2.0,
    this.isFlangeOutward = false,
    this.color = const Color(0xFF90A4AE),
    this.isVisible = true,
    List<RailSegmentDefinition>? segments,
    List<AssemblySketchFeature>? sketches,
    List<String>? weldedToPartIds,
    List<AssemblyMagneticSpot>? magneticSpots,
    List<String>? magneticallyLinkedPartIds,
    this.parentPartId,
    this.matedSlotEntityId,
    this.mateStyle = 'passThrough',
    this.isRungUpsideDown = false,
    this.hingeAngleDeg = 0.0,
    this.jointType,
    this.groupId,
    this.groupName,
    this.componentDefinitionId,
  }) : segments = segments ?? [],
       sketches = sketches ?? [],
       weldedToPartIds = weldedToPartIds ?? [],
       magneticSpots = magneticSpots ?? [],
       magneticallyLinkedPartIds = magneticallyLinkedPartIds ?? [];

  AssemblyPart copyWith({
    String? id,
    String? name,
    AssemblyPartType? type,
    CadPoint3D? position,
    CadPoint3D? rotationDeg,
    double? length,
    double? height,
    double? flangeWidth,
    double? thickness,
    bool? isFlangeOutward,
    Color? color,
    bool? isVisible,
    List<RailSegmentDefinition>? segments,
    List<AssemblySketchFeature>? sketches,
    List<String>? weldedToPartIds,
    List<AssemblyMagneticSpot>? magneticSpots,
    List<String>? magneticallyLinkedPartIds,
    String? parentPartId,
    String? matedSlotEntityId,
    String? mateStyle,
    bool? isRungUpsideDown,
    double? hingeAngleDeg,
    AssemblyJointType? jointType,
    String? groupId,
    String? groupName,
    bool clearGroup = false,
    String? componentDefinitionId,
    bool clearComponent = false,
  }) {
    return AssemblyPart(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      position: position ?? this.position,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      length: length ?? this.length,
      height: height ?? this.height,
      flangeWidth: flangeWidth ?? this.flangeWidth,
      thickness: thickness ?? this.thickness,
      isFlangeOutward: isFlangeOutward ?? this.isFlangeOutward,
      color: color ?? this.color,
      isVisible: isVisible ?? this.isVisible,
      segments: segments ?? List.from(this.segments),
      sketches: sketches ?? List.from(this.sketches),
      weldedToPartIds: weldedToPartIds ?? List.from(this.weldedToPartIds),
      magneticSpots: magneticSpots ?? List.from(this.magneticSpots),
      magneticallyLinkedPartIds: magneticallyLinkedPartIds ?? List.from(this.magneticallyLinkedPartIds),
      parentPartId: parentPartId ?? this.parentPartId,
      matedSlotEntityId: matedSlotEntityId ?? this.matedSlotEntityId,
      mateStyle: mateStyle ?? this.mateStyle,
      isRungUpsideDown: isRungUpsideDown ?? this.isRungUpsideDown,
      hingeAngleDeg: hingeAngleDeg ?? this.hingeAngleDeg,
      jointType: jointType ?? this.jointType,
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      groupName: clearGroup ? null : (groupName ?? this.groupName),
      componentDefinitionId: clearComponent ? null : (componentDefinitionId ?? this.componentDefinitionId),
    );
  }

  /// Transforms a local point into World coordinates using position and rotationDeg.
  CadPoint3D toWorld(CadPoint3D p) {
    // 1. Rotate around X, Y, Z
    final radX = rotationDeg.x * math.pi / 180.0;
    final radY = rotationDeg.y * math.pi / 180.0;
    final radZ = rotationDeg.z * math.pi / 180.0;

    // Rx
    var x = p.x;
    var y = p.y * math.cos(radX) - p.z * math.sin(radX);
    var z = p.y * math.sin(radX) + p.z * math.cos(radX);

    // Ry
    final x1 = x * math.cos(radY) + z * math.sin(radY);
    final y1 = y;
    final z1 = -x * math.sin(radY) + z * math.cos(radY);

    // Rz
    final x2 = x1 * math.cos(radZ) - y1 * math.sin(radZ);
    final y2 = x1 * math.sin(radZ) + y1 * math.cos(radZ);
    final z2 = z1;

    // 2. Translate
    return CadPoint3D(x2 + position.x, y2 + position.y, z2 + position.z);
  }

  /// Transforms a local direction vector (normal) into World coordinates.
  CadPoint3D normalToWorld(CadPoint3D n) {
    final radX = rotationDeg.x * math.pi / 180.0;
    final radY = rotationDeg.y * math.pi / 180.0;
    final radZ = rotationDeg.z * math.pi / 180.0;

    var x = n.x;
    var y = n.y * math.cos(radX) - n.z * math.sin(radX);
    var z = n.y * math.sin(radX) + n.z * math.cos(radX);

    final x1 = x * math.cos(radY) + z * math.sin(radY);
    final y1 = y;
    final z1 = -x * math.sin(radY) + z * math.cos(radY);

    final x2 = x1 * math.cos(radZ) - y1 * math.sin(radZ);
    final y2 = x1 * math.sin(radZ) + y1 * math.cos(radZ);
    final z2 = z1;

    return CadPoint3D(x2, y2, z2);
  }

  /// Transforms a World point into local part coordinates (inverse of toWorld).
  CadPoint3D toLocal(CadPoint3D w) {
    final x = w.x - position.x;
    final y = w.y - position.y;
    final z = w.z - position.z;

    // Inverse Rz
    final radZ = -rotationDeg.z * math.pi / 180.0;
    final x1 = x * math.cos(radZ) - y * math.sin(radZ);
    final y1 = x * math.sin(radZ) + y * math.cos(radZ);
    final z1 = z;

    // Inverse Ry
    final radY = -rotationDeg.y * math.pi / 180.0;
    final x2 = x1 * math.cos(radY) + z1 * math.sin(radY);
    final y2 = y1;
    final z2 = -x1 * math.sin(radY) + z1 * math.cos(radY);

    // Inverse Rx
    final radX = -rotationDeg.x * math.pi / 180.0;
    final x3 = x2;
    final y3 = y2 * math.cos(radX) - z2 * math.sin(radX);
    final z3 = y2 * math.sin(radX) + z2 * math.cos(radX);

    return CadPoint3D(x3, y3, z3);
  }

  /// Generates the raw constituent 3D polygons for this part in Local coordinates.
  void _buildLocalPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    switch (type) {
      case AssemblyPartType.rung:
        _buildRungPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.channel:
        _buildChannelPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.angle:
        _buildAnglePolygons(polys, thickPolys);
        break;
      case AssemblyPartType.rod:
        _buildRodPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.bar:
        _buildBarPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.iBeam:
        _buildIBeamPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.straightRail:
        _buildStraightRailPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.bentRail:
        _buildBentRailPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.walkThroughStile:
        _buildWalkThroughStilePolygons(polys, thickPolys);
        break;
      case AssemblyPartType.boxTubeStile:
        _buildBoxTubeStilePolygons(polys, thickPolys);
        break;
      case AssemblyPartType.diamondGripRung:
        _buildDiamondGripRungPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.wideStepTread:
        _buildWideStepTreadPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.safetyCageHoop:
        _buildSafetyCageHoopPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.safetyCageBellHoop:
        _buildSafetyCageBellHoopPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.cageStrap:
        _buildCageStrapPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.standoffBracket:
        _buildStandoffBracketPolygons(polys, thickPolys);
        break;
      case AssemblyPartType.baseFootPlate:
        _buildBaseFootPlatePolygons(polys, thickPolys);
        break;
      case AssemblyPartType.splicePlate:
        _buildSplicePlatePolygons(polys, thickPolys);
        break;
      case AssemblyPartType.swingGate:
        _buildSwingGatePolygons(polys, thickPolys);
        break;
    }
  }

  /// Returns the exact local min and max bounding extent computed from actual mesh geometry.
  (CadPoint3D, CadPoint3D) getLocalBounds() {
    final polys = <CadFoldedPolygon3D>[];
    final thickPolys = <CadFoldedPolygon3D>[];
    _buildLocalPolygons(polys, thickPolys);

    if (polys.isEmpty) {
      return (const CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(length > 0 ? length : 100.0, flangeWidth > 0 ? flangeWidth : 20.0, height > 0 ? height : 40.0));
    }

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    for (final poly in polys) {
      for (final v in poly.vertices) {
        if (v.x < minX) minX = v.x;
        if (v.x > maxX) maxX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.y > maxY) maxY = v.y;
        if (v.z < minZ) minZ = v.z;
        if (v.z > maxZ) maxZ = v.z;
      }
    }

    return (CadPoint3D(minX, minY, minZ), CadPoint3D(maxX, maxY, maxZ));
  }

  /// Returns the 8 corners of the tight Oriented Bounding Box (OBB) transformed to World coordinates.
  List<CadPoint3D> getOrientedBoundingBoxCorners() {
    final bounds = getLocalBounds();
    final minPt = bounds.$1;
    final maxPt = bounds.$2;
    return [
      toWorld(CadPoint3D(minPt.x, minPt.y, minPt.z)),
      toWorld(CadPoint3D(maxPt.x, minPt.y, minPt.z)),
      toWorld(CadPoint3D(maxPt.x, maxPt.y, minPt.z)),
      toWorld(CadPoint3D(minPt.x, maxPt.y, minPt.z)),
      toWorld(CadPoint3D(minPt.x, minPt.y, maxPt.z)),
      toWorld(CadPoint3D(maxPt.x, minPt.y, maxPt.z)),
      toWorld(CadPoint3D(maxPt.x, maxPt.y, maxPt.z)),
      toWorld(CadPoint3D(minPt.x, maxPt.y, maxPt.z)),
    ];
  }

  /// Returns SketchUp-style bounding box snapping points in World coordinates:
  /// - 8 Corners / Ends
  /// - 1 3D Centroid / Center
  /// - 2 Axial End Cap Centers (Start at X=minX, Finish at X=maxX)
  /// - 4 Side / Web Centers
  List<CadPoint3D> getBoundingBoxSnapPoints() {
    final bounds = getLocalBounds();
    final minPt = bounds.$1;
    final maxPt = bounds.$2;
    final midX = (minPt.x + maxPt.x) / 2.0;
    final midY = (minPt.y + maxPt.y) / 2.0;
    final midZ = (minPt.z + maxPt.z) / 2.0;

    return [
      // 8 Corners / Ends
      toWorld(CadPoint3D(minPt.x, minPt.y, minPt.z)),
      toWorld(CadPoint3D(maxPt.x, minPt.y, minPt.z)),
      toWorld(CadPoint3D(maxPt.x, maxPt.y, minPt.z)),
      toWorld(CadPoint3D(minPt.x, maxPt.y, minPt.z)),
      toWorld(CadPoint3D(minPt.x, minPt.y, maxPt.z)),
      toWorld(CadPoint3D(maxPt.x, minPt.y, maxPt.z)),
      toWorld(CadPoint3D(maxPt.x, maxPt.y, maxPt.z)),
      toWorld(CadPoint3D(minPt.x, maxPt.y, maxPt.z)),
      // Overall 3D Centroid Center
      toWorld(CadPoint3D(midX, midY, midZ)),
      // Axial End Cap Centers (Start & End of part)
      toWorld(CadPoint3D(minPt.x, midY, midZ)),
      toWorld(CadPoint3D(maxPt.x, midY, midZ)),
      // Side / Web Face Centers
      toWorld(CadPoint3D(midX, minPt.y, midZ)),
      toWorld(CadPoint3D(midX, maxPt.y, midZ)),
      toWorld(CadPoint3D(midX, midY, minPt.z)),
      toWorld(CadPoint3D(midX, midY, maxPt.z)),
    ];
  }

  /// Returns the 12 bounding box edge midpoints in World coordinates:
  /// - 4 along X axis
  /// - 4 along Y axis
  /// - 4 along Z axis
  List<CadPoint3D> getBoundingBoxEdgeCenterPoints() {
    final bounds = getLocalBounds();
    final minPt = bounds.$1;
    final maxPt = bounds.$2;
    final midX = (minPt.x + maxPt.x) / 2.0;
    final midY = (minPt.y + maxPt.y) / 2.0;
    final midZ = (minPt.z + maxPt.z) / 2.0;

    return [
      // 4 along X axis
      toWorld(CadPoint3D(midX, minPt.y, minPt.z)),
      toWorld(CadPoint3D(midX, maxPt.y, minPt.z)),
      toWorld(CadPoint3D(midX, minPt.y, maxPt.z)),
      toWorld(CadPoint3D(midX, maxPt.y, maxPt.z)),
      // 4 along Y axis
      toWorld(CadPoint3D(minPt.x, midY, minPt.z)),
      toWorld(CadPoint3D(maxPt.x, midY, minPt.z)),
      toWorld(CadPoint3D(minPt.x, midY, maxPt.z)),
      toWorld(CadPoint3D(maxPt.x, midY, maxPt.z)),
      // 4 along Z axis
      toWorld(CadPoint3D(minPt.x, minPt.y, midZ)),
      toWorld(CadPoint3D(maxPt.x, minPt.y, midZ)),
      toWorld(CadPoint3D(maxPt.x, maxPt.y, midZ)),
      toWorld(CadPoint3D(minPt.x, maxPt.y, midZ)),
    ];
  }

  /// Returns the snap points for all holes cut or punched into this part in World coordinates:
  /// - Centroid / center of each hole loop
  /// - Perimeter vertices / endpoints of each hole loop
  List<CadPoint3D> getHoleSnapPoints({FoldedMeshResult? cachedMesh}) {
    final points = <CadPoint3D>[];
    final mesh = cachedMesh ?? build3DMesh();
    for (final poly in mesh.polygons) {
      for (final hole in poly.holes) {
        if (hole.isEmpty) continue;
        double sumX = 0, sumY = 0, sumZ = 0;
        for (final v in hole) {
          sumX += v.x;
          sumY += v.y;
          sumZ += v.z;
          points.add(v); // Hole perimeter endpoints
        }
        // Hole center
        points.add(CadPoint3D(sumX / hole.length, sumY / hole.length, sumZ / hole.length));
      }
    }
    return points;
  }

  /// Returns the snap points for all sketches drawn on this part in World coordinates:
  /// - Center point of each sketch feature
  /// - Quadrant / corner endpoints of each sketch feature
  List<CadPoint3D> getSketchSnapPoints() {
    final points = <CadPoint3D>[];
    for (final feat in sketches) {
      final centerLocal = CadPoint3D(feat.localCenter.x, feat.localCenter.y, 0.0);
      points.add(toWorld(centerLocal)); // Sketch Center

      final halfW = feat.widthMm / 2.0;
      final halfH = feat.heightMm / 2.0;
      final rad = feat.angleDeg * math.pi / 180.0;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      for (final offset in [(-halfW, -halfH), (halfW, -halfH), (halfW, halfH), (-halfW, halfH), (0.0, -halfH), (0.0, halfH), (-halfW, 0.0), (halfW, 0.0)]) {
        final rotX = offset.$1 * cosA - offset.$2 * sinA;
        final rotY = offset.$1 * sinA + offset.$2 * cosA;
        points.add(toWorld(CadPoint3D(feat.localCenter.x + rotX, feat.localCenter.y + rotY, 0.0)));
      }
    }
    return points;
  }

  /// Returns ALL snap candidate points for this part:
  /// - Bounding box corners & centroid
  /// - 12 Edge midpoints
  /// - Hole center & perimeter endpoints
  /// - Sketch center & endpoints
  List<CadPoint3D> getAllSnapCandidatePoints({FoldedMeshResult? cachedMesh}) {
    return [...getBoundingBoxSnapPoints(), ...getBoundingBoxEdgeCenterPoints(), ...getHoleSnapPoints(cachedMesh: cachedMesh), ...getSketchSnapPoints()];
  }

  /// Generates the complete 3D folded geometry (polygons & thickness walls) for this part in World space.
  FoldedMeshResult build3DMesh() {
    final polys = <CadFoldedPolygon3D>[];
    final thickPolys = <CadFoldedPolygon3D>[];
    _buildLocalPolygons(polys, thickPolys);

    // Transform all polygons to world coordinates
    final worldPolys = polys.map((p) => _transformPoly(p)).toList();
    final worldThickPolys = thickPolys.map((p) => _transformPoly(p)).toList();

    double bw = length;
    double bl = height;
    double bh = flangeWidth > 0 ? flangeWidth : 20.0;
    if (type == AssemblyPartType.safetyCageHoop || type == AssemblyPartType.safetyCageBellHoop) {
      bw = 700.0;
      bl = 700.0;
      bh = 50.0;
    } else if (type == AssemblyPartType.walkThroughStile) {
      bw = length > 0 ? length : 1060.0;
      bl = height > 0 ? height : 300.0;
      bh = flangeWidth > 0 ? flangeWidth : 30.0;
    }

    return FoldedMeshResult(polygons: worldPolys, thicknessPolygons: worldThickPolys, boundWidth: bw, boundLength: bl, boundHeight: bh, center: position);
  }

  CadFoldedPolygon3D _transformPoly(CadFoldedPolygon3D p) {
    final wVerts = p.vertices.map((v) => toWorld(v)).toList();
    final wNorm = normalToWorld(p.normal);
    final wHoles = p.holes.map((loop) => loop.map((v) => toWorld(v)).toList()).toList();
    return CadFoldedPolygon3D(faceId: p.faceId, vertices: wVerts, holes: wHoles, normal: wNorm, color: p.color);
  }

  void _buildRungPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // 40x20mm C-channel rung along X axis from X = 0 to X = length
    const double rungW = 40.0;
    const double rungD = 20.0;
    final T = thickness;
    final L = length;

    // Flip upside down if specified: web moves from Z=rungD to Z=0 and flanges invert
    final double webZ = isRungUpsideDown ? 0.0 : rungD;
    final double flangeEdgeZ = isRungUpsideDown ? rungD : 0.0;
    final CadPoint3D webNorm = isRungUpsideDown ? const CadPoint3D(0.0, 0.0, -1.0) : const CadPoint3D(0.0, 0.0, 1.0);

    // Web face
    final topFace = [
      CadPoint3D(0.0, -rungW / 2.0, webZ),
      CadPoint3D(L, -rungW / 2.0, webZ),
      CadPoint3D(L, rungW / 2.0, webZ),
      CadPoint3D(0.0, rungW / 2.0, webZ),
    ];

    // Obround slots along web
    final holes = <List<CadPoint3D>>[];
    const double slotPitch = 50.0;
    const double slotL = 25.0;
    const double slotW = 14.0;
    if (L > 80.0) {
      final count = ((L - 60.0) / slotPitch).floor();
      for (int i = 0; i < count; i++) {
        final cx = 35.0 + (i * slotPitch);
        holes.add(_makeObroundSlot(cx, 0.0, webZ, slotL, slotW));
      }
    }

    polys.add(CadFoldedPolygon3D(faceId: '${id}_top_web', vertices: topFace, holes: holes, normal: webNorm, color: color));

    // Flanges: Y = +rungW/2 and Y = -rungW/2
    // Front flange
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_flange_front',
        vertices: [
          CadPoint3D(0.0, rungW / 2.0, webZ),
          CadPoint3D(L, rungW / 2.0, webZ),
          CadPoint3D(L, rungW / 2.0, flangeEdgeZ),
          CadPoint3D(0.0, rungW / 2.0, flangeEdgeZ),
        ],
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        color: color,
      ),
    );

    // Back flange
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_flange_back',
        vertices: [
          CadPoint3D(0.0, -rungW / 2.0, flangeEdgeZ),
          CadPoint3D(L, -rungW / 2.0, flangeEdgeZ),
          CadPoint3D(L, -rungW / 2.0, webZ),
          CadPoint3D(0.0, -rungW / 2.0, webZ),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    // Flange bottom returns / thickness rims
    final double rimZ = flangeEdgeZ;
    thickPolys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_rim_front',
        vertices: [
          CadPoint3D(0.0, rungW / 2.0, rimZ),
          CadPoint3D(L, rungW / 2.0, rimZ),
          CadPoint3D(L, (rungW / 2.0) - T, rimZ),
          CadPoint3D(0.0, (rungW / 2.0) - T, rimZ),
        ],
        normal: isRungUpsideDown ? const CadPoint3D(0.0, 0.0, 1.0) : const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );
    thickPolys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_rim_back',
        vertices: [
          CadPoint3D(0.0, (-rungW / 2.0) + T, rimZ),
          CadPoint3D(L, (-rungW / 2.0) + T, rimZ),
          CadPoint3D(L, -rungW / 2.0, rimZ),
          CadPoint3D(0.0, -rungW / 2.0, rimZ),
        ],
        normal: isRungUpsideDown ? const CadPoint3D(0.0, 0.0, 1.0) : const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );
  }

  void _buildStraightRailPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // C-channel rail along X axis from X = 0 to X = length, web height H, flange F (default 20mm)
    final H = height;
    final F = flangeWidth;
    final T = thickness;
    final L = length;
    final fDir = isFlangeOutward ? 1.0 : -1.0;

    // Web face at Y = 0: from X = 0 to L, Z = 0 to H
    final webHoles = <List<CadPoint3D>>[];

    // Splice holes on web at both ends (2x2 grid, Ø10mm)
    if (L >= 100.0) {
      final z1 = (H / 2.0) - 12.5;
      final z2 = (H / 2.0) + 12.5;
      for (final x in [35.0, 75.0, L - 75.0, L - 35.0]) {
        for (final z in [z1, z2]) {
          webHoles.add(_makeOctagonHole(CadPoint3D(x, 0.0, z), 5.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)));
        }
      }
    }

    // Sketches & holes on web
    webHoles.addAll(_buildWebHoles());
    _addBendLinePolygons(polys, H);
    _addHoleBoreWalls(thickPolys, webHoles, const CadPoint3D(0.0, -1.0, 0.0), T);

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_web',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(L, 0.0, 0.0), CadPoint3D(L, 0.0, H), CadPoint3D(0.0, 0.0, H)],
        holes: webHoles,
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    // Top flange: Z = H, Y extends by F * fDir
    final topHoles = _buildFlangeHoles('flange_top', H, fDir);
    _addHoleBoreWalls(thickPolys, topHoles, const CadPoint3D(0.0, 0.0, 1.0), T);
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_flange_top',
        vertices: [CadPoint3D(0.0, 0.0, H), CadPoint3D(L, 0.0, H), CadPoint3D(L, F * fDir, H), CadPoint3D(0.0, F * fDir, H)],
        holes: topHoles,
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    // Bottom flange: Z = 0, Y extends by F * fDir
    final bottomHoles = _buildFlangeHoles('flange_bottom', 0.0, fDir);
    _addHoleBoreWalls(thickPolys, bottomHoles, const CadPoint3D(0.0, 0.0, -1.0), T);
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_flange_bottom',
        vertices: [CadPoint3D(0.0, F * fDir, 0.0), CadPoint3D(L, F * fDir, 0.0), CadPoint3D(L, 0.0, 0.0), CadPoint3D(0.0, 0.0, 0.0)],
        holes: bottomHoles,
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );

    // End caps & Flange rims
    thickPolys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_rim_top',
        vertices: [CadPoint3D(0.0, F * fDir, H), CadPoint3D(L, F * fDir, H), CadPoint3D(L, F * fDir, H - T), CadPoint3D(0.0, F * fDir, H - T)],
        normal: CadPoint3D(0.0, fDir, 0.0),
        color: color,
      ),
    );
    thickPolys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_rim_bottom',
        vertices: [CadPoint3D(0.0, F * fDir, T), CadPoint3D(L, F * fDir, T), CadPoint3D(L, F * fDir, 0.0), CadPoint3D(0.0, F * fDir, 0.0)],
        normal: CadPoint3D(0.0, fDir, 0.0),
        color: color,
      ),
    );
  }

  void _buildBentRailPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    if (segments.isEmpty) {
      _buildStraightRailPolygons(polys, thickPolys);
      return;
    }

    final H = height;
    final F = flangeWidth;
    final fDir = isFlangeOutward ? 1.0 : -1.0;

    var curPos = const CadPoint3D(0.0, 0.0, 0.0);
    var curAngleRad = 0.0;

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      curAngleRad += (seg.bendAngleDeg * math.pi / 180.0);

      final dirX = math.cos(curAngleRad);
      final dirY = math.sin(curAngleRad);
      final normalX = -dirY;
      final normalY = dirX;

      final pStart = curPos;
      final pEnd = CadPoint3D(curPos.x + dirX * seg.length, curPos.y + dirY * seg.length, 0.0);

      // Web polygon
      final w0 = pStart;
      final w1 = pEnd;
      final w2 = CadPoint3D(pEnd.x, pEnd.y, H);
      final w3 = CadPoint3D(pStart.x, pStart.y, H);

      // Splice holes on end segments
      final segHoles = <List<CadPoint3D>>[];
      if ((i == 0 || i == segments.length - 1) && seg.length >= 80.0) {
        final z1 = (H / 2.0) - 12.5;
        final z2 = (H / 2.0) + 12.5;
        final offsets = i == 0 ? [35.0, 75.0] : [seg.length - 75.0, seg.length - 35.0];
        for (final off in offsets) {
          for (final z in [z1, z2]) {
            final center = CadPoint3D(pStart.x + dirX * off, pStart.y + dirY * off, z);
            segHoles.add(_makeOctagonHole(center, 5.0, CadPoint3D(dirX, dirY, 0.0), const CadPoint3D(0.0, 0.0, 1.0)));
          }
        }
      }

      polys.add(
        CadFoldedPolygon3D(faceId: '${id}_seg_${i}_web', vertices: [w0, w1, w2, w3], holes: segHoles, normal: CadPoint3D(normalX, normalY, 0.0), color: color),
      );

      // Flange with auto-cut V-notch at bend vertices
      final double notchMargin = seg.hasFlangeVNotch && seg.bendAngleDeg.abs() > 0.1 ? F * math.tan(seg.bendAngleDeg.abs() * math.pi / 360.0) : 0.0;
      final pStartF = CadPoint3D(pStart.x + normalX * F * fDir, pStart.y + normalY * F * fDir, H);
      final pEndF = CadPoint3D(pEnd.x + normalX * F * fDir, pEnd.y + normalY * F * fDir, H);

      // Top flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_seg_${i}_flange_top',
          vertices: [CadPoint3D(pStart.x + dirX * notchMargin, pStart.y + dirY * notchMargin, H), CadPoint3D(pEnd.x, pEnd.y, H), pEndF, pStartF],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: color,
        ),
      );

      // Bottom flange
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_seg_${i}_flange_bottom',
          vertices: [
            CadPoint3D(pStartF.x, pStartF.y, 0.0),
            CadPoint3D(pEndF.x, pEndF.y, 0.0),
            pEnd,
            CadPoint3D(pStart.x + dirX * notchMargin, pStart.y + dirY * notchMargin, 0.0),
          ],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: color,
        ),
      );

      curPos = pEnd;
    }
  }

  void _buildChannelPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    final f = flangeWidth > 0 ? flangeWidth : 35.0;
    final h = height > 0 ? height : 75.0;
    final l = length;

    final webHoles = _buildWebHoles();
    _addBendLinePolygons(polys, h);

    // Web (facing -Y)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_web',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(l, 0.0, 0.0), CadPoint3D(l, 0.0, h), CadPoint3D(0.0, 0.0, h)],
        holes: webHoles,
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    // Top Flange (facing +Z)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_flange_top',
        vertices: [CadPoint3D(0.0, 0.0, h), CadPoint3D(l, 0.0, h), CadPoint3D(l, f, h), CadPoint3D(0.0, f, h)],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    // Bottom Flange (facing -Z)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_flange_bot',
        vertices: [CadPoint3D(0.0, f, 0.0), CadPoint3D(l, f, 0.0), CadPoint3D(l, 0.0, 0.0), CadPoint3D(0.0, 0.0, 0.0)],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );
  }

  void _buildAnglePolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    final legA = height > 0 ? height : 50.0;
    final legB = flangeWidth > 0 ? flangeWidth : 50.0;
    final l = length;

    final webHoles = _buildWebHoles();
    _addBendLinePolygons(polys, legA);

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_leg_v',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(l, 0.0, 0.0), CadPoint3D(l, 0.0, legA), CadPoint3D(0.0, 0.0, legA)],
        holes: webHoles,
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_leg_h',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(0.0, legB, 0.0), CadPoint3D(l, legB, 0.0), CadPoint3D(l, 0.0, 0.0)],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );
  }

  void _buildRodPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    final radius = (height > 0 ? height : 20.0) / 2.0;
    final l = length;
    const int segments = 12;

    for (int i = 0; i < segments; i++) {
      final a1 = (i * 2.0 * math.pi) / segments;
      final a2 = ((i + 1) * 2.0 * math.pi) / segments;
      final y1 = radius * math.cos(a1);
      final z1 = radius * math.sin(a1);
      final y2 = radius * math.cos(a2);
      final z2 = radius * math.sin(a2);

      final midA = (a1 + a2) / 2.0;
      final ny = math.cos(midA);
      final nz = math.sin(midA);

      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_cylinder_$i',
          vertices: [CadPoint3D(0.0, y1, z1), CadPoint3D(l, y1, z1), CadPoint3D(l, y2, z2), CadPoint3D(0.0, y2, z2)],
          normal: CadPoint3D(0.0, ny, nz),
          color: color,
        ),
      );
    }
  }

  void _buildBarPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    final w = flangeWidth > 0 ? flangeWidth : (height > 0 ? height : 40.0);
    final t = thickness > 0 ? thickness : 6.0;
    final l = length;

    final webHoles = _buildWebHoles();
    _addBendLinePolygons(polys, w);

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_bar_top',
        vertices: [CadPoint3D(0.0, -w / 2.0, t), CadPoint3D(l, -w / 2.0, t), CadPoint3D(l, w / 2.0, t), CadPoint3D(0.0, w / 2.0, t)],
        holes: webHoles,
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_bar_bot',
        vertices: [CadPoint3D(0.0, w / 2.0, 0.0), CadPoint3D(l, w / 2.0, 0.0), CadPoint3D(l, -w / 2.0, 0.0), CadPoint3D(0.0, -w / 2.0, 0.0)],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_bar_side1',
        vertices: [CadPoint3D(0.0, w / 2.0, 0.0), CadPoint3D(0.0, w / 2.0, t), CadPoint3D(l, w / 2.0, t), CadPoint3D(l, w / 2.0, 0.0)],
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        color: color,
      ),
    );

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_bar_side2',
        vertices: [CadPoint3D(0.0, -w / 2.0, 0.0), CadPoint3D(l, -w / 2.0, 0.0), CadPoint3D(l, -w / 2.0, t), CadPoint3D(0.0, -w / 2.0, t)],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );
  }

  void _buildIBeamPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    final h = height > 0 ? height : 100.0;
    final f = flangeWidth > 0 ? flangeWidth : 60.0;
    final l = length;

    final webHoles = _buildWebHoles();
    _addBendLinePolygons(polys, h);

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_ibeam_web',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(l, 0.0, 0.0), CadPoint3D(l, 0.0, h), CadPoint3D(0.0, 0.0, h)],
        holes: webHoles,
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_ibeam_flange_top',
        vertices: [CadPoint3D(0.0, -f / 2.0, h), CadPoint3D(l, -f / 2.0, h), CadPoint3D(l, f / 2.0, h), CadPoint3D(0.0, f / 2.0, h)],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_ibeam_flange_bot',
        vertices: [CadPoint3D(0.0, f / 2.0, 0.0), CadPoint3D(l, f / 2.0, 0.0), CadPoint3D(l, -f / 2.0, 0.0), CadPoint3D(0.0, -f / 2.0, 0.0)],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );
  }

  void _buildWalkThroughStilePolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // OSHA 1060mm flared parapet walk-through top extension
    final h = height > 0 ? height : 100.0;
    final f = flangeWidth > 0 ? flangeWidth : 30.0;
    final totalLen = length > 0 ? length : 1060.0;
    const double straightSpliceLen = 350.0;
    final fDir = isFlangeOutward ? 1.0 : -1.0;

    // 1. Lower vertical splice section (straight C-channel)
    final spliceHoles = <List<CadPoint3D>>[];
    for (final x in [50.0, 150.0, 250.0]) {
      for (final z in [h * 0.3, h * 0.7]) {
        spliceHoles.add(_makeOctagonHole(CadPoint3D(x, 0.0, z), 6.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)));
      }
    }
    spliceHoles.addAll(_buildWebHoles());

    // Lower web
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_walkthrough_splice_web',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(straightSpliceLen, 0.0, 0.0), CadPoint3D(straightSpliceLen, 0.0, h), CadPoint3D(0.0, 0.0, h)],
        holes: spliceHoles,
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    // Lower flanges
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_walkthrough_splice_flange_top',
        vertices: [CadPoint3D(0.0, 0.0, h), CadPoint3D(straightSpliceLen, 0.0, h), CadPoint3D(straightSpliceLen, f * fDir, h), CadPoint3D(0.0, f * fDir, h)],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_walkthrough_splice_flange_bot',
        vertices: [
          CadPoint3D(0.0, f * fDir, 0.0),
          CadPoint3D(straightSpliceLen, f * fDir, 0.0),
          CadPoint3D(straightSpliceLen, 0.0, 0.0),
          CadPoint3D(0.0, 0.0, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );

    // 2. Curved walk-through arch with outward step-through flare
    const int arcSteps = 8;
    final arcLen = totalLen - straightSpliceLen;
    const double flareMaxY = 120.0; // Outward flare for wide step-through clearance

    for (int i = 0; i < arcSteps; i++) {
      final t0 = i / arcSteps;
      final t1 = (i + 1) / arcSteps;

      final x0 = straightSpliceLen + arcLen * t0;
      final x1 = straightSpliceLen + arcLen * t1;

      // Flare Y follows smooth sine curve
      final y0 = fDir * flareMaxY * math.sin(t0 * math.pi * 0.5);
      final y1 = fDir * flareMaxY * math.sin(t1 * math.pi * 0.5);

      // Web polygon for this segment
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_walkthrough_arc_web_$i',
          vertices: [CadPoint3D(x0, y0, 0.0), CadPoint3D(x1, y1, 0.0), CadPoint3D(x1, y1, h), CadPoint3D(x0, y0, h)],
          normal: const CadPoint3D(0.0, -1.0, 0.0),
          color: color,
        ),
      );

      // Flange top
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_walkthrough_arc_flange_top_$i',
          vertices: [CadPoint3D(x0, y0, h), CadPoint3D(x1, y1, h), CadPoint3D(x1, y1 + f * fDir, h), CadPoint3D(x0, y0 + f * fDir, h)],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: color,
        ),
      );

      // Flange bot
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_walkthrough_arc_flange_bot_$i',
          vertices: [CadPoint3D(x0, y0 + f * fDir, 0.0), CadPoint3D(x1, y1 + f * fDir, 0.0), CadPoint3D(x1, y1, 0.0), CadPoint3D(x0, y0, 0.0)],
          normal: const CadPoint3D(0.0, 0.0, -1.0),
          color: color,
        ),
      );
    }
  }

  void _buildBoxTubeStilePolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // 60x40mm (or height x flangeWidth) Rectangular Hollow Section (RHS) tube stile
    final h = height > 0 ? height : 60.0;
    final w = flangeWidth > 0 ? flangeWidth : 40.0;
    final l = length;

    final webHoles = <List<CadPoint3D>>[];
    const double slotPitch = 250.0;
    if (l >= 150.0) {
      final slotCount = ((l - 80.0) / slotPitch).floor() + 1;
      for (int i = 0; i < slotCount; i++) {
        final cx = 50.0 + (i * slotPitch);
        if (cx + 20.0 < l) {
          webHoles.add(_makeObroundSlot(cx, 0.0, h / 2.0, 40.0, 20.0));
        }
      }
    }
    webHoles.addAll(_buildWebHoles());

    // Front web (Y = 0)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_boxtube_front',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(l, 0.0, 0.0), CadPoint3D(l, 0.0, h), CadPoint3D(0.0, 0.0, h)],
        holes: webHoles,
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    // Back web (Y = w)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_boxtube_back',
        vertices: [CadPoint3D(0.0, w, h), CadPoint3D(l, w, h), CadPoint3D(l, w, 0.0), CadPoint3D(0.0, w, 0.0)],
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        color: color,
      ),
    );

    // Top face (Z = h)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_boxtube_top',
        vertices: [CadPoint3D(0.0, 0.0, h), CadPoint3D(l, 0.0, h), CadPoint3D(l, w, h), CadPoint3D(0.0, w, h)],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    // Bottom face (Z = 0)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_boxtube_bot',
        vertices: [CadPoint3D(0.0, w, 0.0), CadPoint3D(l, w, 0.0), CadPoint3D(l, 0.0, 0.0), CadPoint3D(0.0, 0.0, 0.0)],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );
  }

  void _buildDiamondGripRungPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // 40x20mm serrated diamond grip-strut rung
    const double rungW = 40.0;
    const double rungD = 20.0;
    final l = length;

    final topHoles = <List<CadPoint3D>>[];
    const double pitch = 45.0;
    if (l > 80.0) {
      final count = ((l - 60.0) / pitch).floor();
      for (int i = 0; i < count; i++) {
        final cx = 35.0 + (i * pitch);
        // Diamond hole on top web (XY plane at Z = rungD)
        topHoles.add([CadPoint3D(cx - 10.0, 0.0, rungD), CadPoint3D(cx, 8.0, rungD), CadPoint3D(cx + 10.0, 0.0, rungD), CadPoint3D(cx, -8.0, rungD)]);
      }
    }

    // Top web
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_diamond_web',
        vertices: [
          CadPoint3D(0.0, -rungW / 2.0, rungD),
          CadPoint3D(l, -rungW / 2.0, rungD),
          CadPoint3D(l, rungW / 2.0, rungD),
          CadPoint3D(0.0, rungW / 2.0, rungD),
        ],
        holes: topHoles,
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    // Front flange
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_diamond_flange_front',
        vertices: [CadPoint3D(0.0, rungW / 2.0, 0.0), CadPoint3D(l, rungW / 2.0, 0.0), CadPoint3D(l, rungW / 2.0, rungD), CadPoint3D(0.0, rungW / 2.0, rungD)],
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        color: color,
      ),
    );

    // Back flange
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_diamond_flange_back',
        vertices: [
          CadPoint3D(0.0, -rungW / 2.0, rungD),
          CadPoint3D(l, -rungW / 2.0, rungD),
          CadPoint3D(l, -rungW / 2.0, 0.0),
          CadPoint3D(0.0, -rungW / 2.0, 0.0),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );
  }

  void _buildWideStepTreadPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // 80x25mm wide flanged safety step tread
    const double treadD = 80.0;
    const double treadH = 25.0;
    final l = length;

    // Tread surface on top
    final treadHoles = <List<CadPoint3D>>[];
    if (l > 100.0) {
      // 3 longitudinal traction obround slots
      for (final y in [-20.0, 0.0, 20.0]) {
        treadHoles.add(_makeObroundSlot(l / 2.0, y, treadH, l * 0.65, 8.0));
      }
    }

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_step_web',
        vertices: [
          CadPoint3D(0.0, -treadD / 2.0, treadH),
          CadPoint3D(l, -treadD / 2.0, treadH),
          CadPoint3D(l, treadD / 2.0, treadH),
          CadPoint3D(0.0, treadD / 2.0, treadH),
        ],
        holes: treadHoles,
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    // Front nosing lip
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_step_nosing',
        vertices: [
          CadPoint3D(0.0, treadD / 2.0, 0.0),
          CadPoint3D(l, treadD / 2.0, 0.0),
          CadPoint3D(l, treadD / 2.0, treadH),
          CadPoint3D(0.0, treadD / 2.0, treadH),
        ],
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        color: color,
      ),
    );

    // Rear return lip
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_step_rear',
        vertices: [
          CadPoint3D(0.0, -treadD / 2.0, treadH),
          CadPoint3D(l, -treadD / 2.0, treadH),
          CadPoint3D(l, -treadD / 2.0, 5.0),
          CadPoint3D(0.0, -treadD / 2.0, 5.0),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    // End mounting cleats with bolt holes (left and right)
    for (final x in [0.0, l]) {
      final sign = x == 0.0 ? -1.0 : 1.0;
      final cleatHoles = [
        _makeOctagonHole(CadPoint3D(x, -18.0, 12.5), 5.0, const CadPoint3D(0.0, 1.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
        _makeOctagonHole(CadPoint3D(x, 18.0, 12.5), 5.0, const CadPoint3D(0.0, 1.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
      ];
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_cleat_$x',
          vertices: [
            CadPoint3D(x, -treadD / 2.0, 0.0),
            CadPoint3D(x, treadD / 2.0, 0.0),
            CadPoint3D(x, treadD / 2.0, treadH + 15.0),
            CadPoint3D(x, -treadD / 2.0, treadH + 15.0),
          ],
          holes: cleatHoles,
          normal: CadPoint3D(sign, 0.0, 0.0),
          color: const Color(0xFF64748B),
        ),
      );
    }
  }

  void _buildSafetyCageHoopPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // Standard circular safety cage hoop (Ø700mm inside clearance)
    _buildCircularCageHoopGeometry(polys, isBellMouth: false);
  }

  void _buildSafetyCageBellHoopPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // Flared entry bell hoop (widened Ø800mm opening with 30° entry flare)
    _buildCircularCageHoopGeometry(polys, isBellMouth: true);
  }

  void _buildCircularCageHoopGeometry(List<CadFoldedPolygon3D> polys, {required bool isBellMouth}) {
    // Horseshoe hoop arch in Y-Z plane from Left rail (Y=0, Z=0) out to Z=700mm, back to Right rail (Y=600, Z=0)
    const double hoopW = 50.0; // 50mm flat bar width along X
    final double halfX = hoopW / 2.0;
    const double railSpan = 600.0;
    final double archR = isBellMouth ? 390.0 : 350.0;
    final double centerZ = isBellMouth ? 390.0 : 350.0;
    final double centerY = railSpan / 2.0;

    const int steps = 14;
    // Generate horseshoe arc points in Y-Z plane
    final outerPts = <CadPoint2D>[];
    final innerPts = <CadPoint2D>[];

    // Left straight entry leg from Y = 0 to start of arc
    outerPts.add(const CadPoint2D(0.0, 0.0));
    innerPts.add(const CadPoint2D(0.0, 0.0));

    // Arc from angle math.pi to 0
    for (int i = 0; i <= steps; i++) {
      final ang = math.pi - (i * math.pi / steps);
      final rOut = archR + 5.0;
      final rIn = archR;
      outerPts.add(CadPoint2D(centerY + rOut * math.cos(ang), centerZ + rOut * math.sin(ang)));
      innerPts.add(CadPoint2D(centerY + rIn * math.cos(ang), centerZ + rIn * math.sin(ang)));
    }

    // Right straight exit leg
    outerPts.add(const CadPoint2D(railSpan, 0.0));
    innerPts.add(const CadPoint2D(railSpan, 0.0));

    // Outer and Inner ring polygon strips
    for (int i = 0; i < outerPts.length - 1; i++) {
      final p0 = outerPts[i];
      final p1 = outerPts[i + 1];

      // Outer face
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_hoop_out_$i',
          vertices: [CadPoint3D(-halfX, p0.x, p0.y), CadPoint3D(halfX, p0.x, p0.y), CadPoint3D(halfX, p1.x, p1.y), CadPoint3D(-halfX, p1.x, p1.y)],
          normal: const CadPoint3D(0.0, 0.0, 1.0),
          color: isBellMouth ? const Color(0xFFF59E0B) : color,
        ),
      );

      // Side edge (+X)
      final q0 = innerPts[i];
      final q1 = innerPts[i + 1];
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_hoop_edge_$i',
          vertices: [CadPoint3D(halfX, p0.x, p0.y), CadPoint3D(halfX, q0.x, q0.y), CadPoint3D(halfX, q1.x, q1.y), CadPoint3D(halfX, p1.x, p1.y)],
          normal: const CadPoint3D(1.0, 0.0, 0.0),
          color: isBellMouth ? const Color(0xFFD97706) : color,
        ),
      );
    }
  }

  void _buildCageStrapPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // 30x3.0mm flat steel bar vertical strap along X
    const double strapW = 30.0;
    const double strapT = 3.0;
    final l = length;

    final strapHoles = <List<CadPoint3D>>[];
    const double hoopPitch = 750.0;
    if (l >= 300.0) {
      final count = (l / hoopPitch).floor() + 1;
      for (int i = 0; i < count; i++) {
        final cx = math.min(i * hoopPitch, l - 30.0);
        strapHoles.add(_makeOctagonHole(CadPoint3D(cx, 0.0, strapT), 4.5, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 1.0, 0.0)));
      }
    }

    // Top face (Z = strapT)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_strap_top',
        vertices: [
          CadPoint3D(0.0, -strapW / 2.0, strapT),
          CadPoint3D(l, -strapW / 2.0, strapT),
          CadPoint3D(l, strapW / 2.0, strapT),
          CadPoint3D(0.0, strapW / 2.0, strapT),
        ],
        holes: strapHoles,
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    // Bottom face (Z = 0)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_strap_bot',
        vertices: [
          CadPoint3D(0.0, strapW / 2.0, 0.0),
          CadPoint3D(l, strapW / 2.0, 0.0),
          CadPoint3D(l, -strapW / 2.0, 0.0),
          CadPoint3D(0.0, -strapW / 2.0, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );
  }

  void _buildStandoffBracketPolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // Heavy-duty 175mm wall standoff bracket with slotted wall anchor holes
    final standoffDepth = length > 0 ? length : 175.0; // Standoff depth from ladder stile to wall
    const double flgW = 50.0;
    const double flgH = 80.0;
    const double wallPlateW = 120.0;
    const double wallPlateH = 60.0;

    // 1. Stile mounting flange at Z = 0 (attaches to ladder rail flange)
    final stileHoles = [
      _makeOctagonHole(CadPoint3D(0.0, -flgW * 0.3, flgH * 0.3), 5.5, const CadPoint3D(0.0, 1.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
      _makeOctagonHole(CadPoint3D(0.0, -flgW * 0.3, flgH * 0.7), 5.5, const CadPoint3D(0.0, 1.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
    ];
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_standoff_stile_flg',
        vertices: [CadPoint3D(0.0, -flgW, 0.0), CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(0.0, 0.0, flgH), CadPoint3D(0.0, -flgW, flgH)],
        holes: stileHoles,
        normal: const CadPoint3D(1.0, 0.0, 0.0),
        color: color,
      ),
    );

    // 2. Standoff cantilever arm connecting stile to wall
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_standoff_arm_top',
        vertices: [CadPoint3D(0.0, 0.0, flgH), CadPoint3D(-standoffDepth, 0.0, flgH), CadPoint3D(-standoffDepth, flgW, flgH), CadPoint3D(0.0, flgW, flgH)],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_standoff_arm_web',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(-standoffDepth, 0.0, 0.0), CadPoint3D(-standoffDepth, 0.0, flgH), CadPoint3D(0.0, 0.0, flgH)],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    // 3. Wall foot anchor plate (at X = -standoffDepth)
    final wallHoles = [
      _makeObroundSlot(-standoffDepth, -wallPlateW * 0.3, flgH * 0.5, 25.0, 12.0),
      _makeObroundSlot(-standoffDepth, wallPlateW * 0.3, flgH * 0.5, 25.0, 12.0),
    ];
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_standoff_wall_plate',
        vertices: [
          CadPoint3D(-standoffDepth, -wallPlateW / 2.0, (flgH - wallPlateH) / 2.0),
          CadPoint3D(-standoffDepth, wallPlateW / 2.0, (flgH - wallPlateH) / 2.0),
          CadPoint3D(-standoffDepth, wallPlateW / 2.0, (flgH + wallPlateH) / 2.0),
          CadPoint3D(-standoffDepth, -wallPlateW / 2.0, (flgH + wallPlateH) / 2.0),
        ],
        holes: wallHoles,
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: const Color(0xFF64748B),
      ),
    );
  }

  void _buildBaseFootPlatePolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // Heavy-duty base mounting shoe (120x100x6mm plate with 4 chemical anchor holes + vertical stile cleats)
    const double plateL = 120.0;
    const double plateW = 100.0;
    const double plateT = 6.0;
    const double cleatH = 80.0;

    // Floor plate with 4 anchor holes
    final anchorHoles = [
      _makeOctagonHole(CadPoint3D(25.0, -30.0, plateT), 7.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 1.0, 0.0)),
      _makeOctagonHole(CadPoint3D(25.0, 30.0, plateT), 7.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 1.0, 0.0)),
      _makeOctagonHole(CadPoint3D(plateL - 25.0, -30.0, plateT), 7.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 1.0, 0.0)),
      _makeOctagonHole(CadPoint3D(plateL - 25.0, 30.0, plateT), 7.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 1.0, 0.0)),
    ];

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_foot_base_top',
        vertices: [
          CadPoint3D(0.0, -plateW / 2.0, plateT),
          CadPoint3D(plateL, -plateW / 2.0, plateT),
          CadPoint3D(plateL, plateW / 2.0, plateT),
          CadPoint3D(0.0, plateW / 2.0, plateT),
        ],
        holes: anchorHoles,
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        color: color,
      ),
    );

    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_foot_base_bot',
        vertices: [
          CadPoint3D(0.0, plateW / 2.0, 0.0),
          CadPoint3D(plateL, plateW / 2.0, 0.0),
          CadPoint3D(plateL, -plateW / 2.0, 0.0),
          CadPoint3D(0.0, -plateW / 2.0, 0.0),
        ],
        normal: const CadPoint3D(0.0, 0.0, -1.0),
        color: color,
      ),
    );

    // Vertical stile sandwich cleats (left & right)
    for (final y in [-18.0, 18.0]) {
      final sign = y < 0 ? -1.0 : 1.0;
      final cleatHoles = [
        _makeOctagonHole(CadPoint3D(plateL * 0.4, y, plateT + cleatH * 0.4), 6.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
        _makeOctagonHole(CadPoint3D(plateL * 0.65, y, plateT + cleatH * 0.7), 6.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
      ];
      polys.add(
        CadFoldedPolygon3D(
          faceId: '${id}_foot_cleat_$y',
          vertices: [
            CadPoint3D(15.0, y, plateT),
            CadPoint3D(plateL - 15.0, y, plateT),
            CadPoint3D(plateL - 15.0, y, plateT + cleatH),
            CadPoint3D(15.0, y, plateT + cleatH),
          ],
          holes: cleatHoles,
          normal: CadPoint3D(0.0, sign, 0.0),
          color: const Color(0xFF475569),
        ),
      );
    }
  }

  void _buildSplicePlatePolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // 250x80x3.0mm stile splice fishplate with 4-hole pattern
    final l = length > 0 ? length : 250.0;
    final w = height > 0 ? height : 80.0;
    const double t = 3.0;

    final boltHoles = [
      _makeOctagonHole(CadPoint3D(40.0, 0.0, w * 0.3), 5.5, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
      _makeOctagonHole(CadPoint3D(40.0, 0.0, w * 0.7), 5.5, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
      _makeOctagonHole(CadPoint3D(l - 40.0, 0.0, w * 0.3), 5.5, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
      _makeOctagonHole(CadPoint3D(l - 40.0, 0.0, w * 0.7), 5.5, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 0.0, 1.0)),
    ];

    // Front face
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_splice_front',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(l, 0.0, 0.0), CadPoint3D(l, 0.0, w), CadPoint3D(0.0, 0.0, w)],
        holes: boltHoles,
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: color,
      ),
    );

    // Back face
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_splice_back',
        vertices: [CadPoint3D(0.0, t, w), CadPoint3D(l, t, w), CadPoint3D(l, t, 0.0), CadPoint3D(0.0, t, 0.0)],
        normal: const CadPoint3D(0.0, 1.0, 0.0),
        color: color,
      ),
    );
  }

  void _buildSwingGatePolygons(List<CadFoldedPolygon3D> polys, List<CadFoldedPolygon3D> thickPolys) {
    // OSHA self-closing safety swing gate (600x400mm)
    final w = length > 0 ? length : 600.0;
    const double h = 420.0;
    const double barSize = 25.0;

    // 1. Top handrail bar
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_gate_top_rail',
        vertices: [CadPoint3D(0.0, 0.0, h - barSize), CadPoint3D(w, 0.0, h - barSize), CadPoint3D(w, 0.0, h), CadPoint3D(0.0, 0.0, h)],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: const Color(0xFFFBBF24),
      ),
    );

    // 2. Mid knee rail
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_gate_mid_rail',
        vertices: [
          CadPoint3D(0.0, 0.0, (h / 2.0) - (barSize / 2.0)),
          CadPoint3D(w, 0.0, (h / 2.0) - (barSize / 2.0)),
          CadPoint3D(w, 0.0, (h / 2.0) + (barSize / 2.0)),
          CadPoint3D(0.0, 0.0, (h / 2.0) + (barSize / 2.0)),
        ],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: const Color(0xFFFBBF24),
      ),
    );

    // 3. Bottom toe kickplate (100mm high sheet metal)
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_gate_toe_plate',
        vertices: [CadPoint3D(0.0, 0.0, 0.0), CadPoint3D(w, 0.0, 0.0), CadPoint3D(w, 0.0, 100.0), CadPoint3D(0.0, 0.0, 100.0)],
        normal: const CadPoint3D(0.0, -1.0, 0.0),
        color: const Color(0xFFE2E8F0),
      ),
    );

    // 4. Vertical hinge barrel on left post
    polys.add(
      CadFoldedPolygon3D(
        faceId: '${id}_gate_hinge_barrel',
        vertices: [CadPoint3D(-15.0, -15.0, 0.0), CadPoint3D(15.0, -15.0, 0.0), CadPoint3D(15.0, 15.0, h), CadPoint3D(-15.0, 15.0, h)],
        normal: const CadPoint3D(-1.0, 0.0, 0.0),
        color: const Color(0xFF0F172A),
      ),
    );
  }

  List<List<CadPoint3D>> _buildWebHoles() {
    final webHoles = <List<CadPoint3D>>[];
    for (final sk in sketches) {
      if (sk.targetFace == 'web' || sk.targetFace.endsWith('_web') || sk.targetFace.isEmpty) {
        if (sk.featureType == 'circle_hole') {
          webHoles.add(
            _makeOctagonHole(
              CadPoint3D(sk.localCenter.x, 0.0, sk.localCenter.y),
              sk.widthMm / 2.0,
              const CadPoint3D(1.0, 0.0, 0.0),
              const CadPoint3D(0.0, 0.0, 1.0),
            ),
          );
        } else if (sk.featureType == 'obround_slot') {
          webHoles.add(_makeObroundSlotXZ(sk.localCenter.x, 0.0, sk.localCenter.y, sk.widthMm, sk.heightMm));
        } else if (sk.featureType == 'rung_slot' || sk.isRungSlotEntity || sk.featureType == 'rect_cut' || sk.featureType == 'rect_slot') {
          webHoles.add(_makeRectSlot(sk.localCenter.x, 0.0, sk.localCenter.y, sk.widthMm, sk.heightMm));
        }
      }
    }
    return webHoles;
  }

  List<List<CadPoint3D>> _buildFlangeHoles(String faceKey, double zCoord, double fDir) {
    final flgHoles = <List<CadPoint3D>>[];
    for (final sk in sketches) {
      if (sk.targetFace == faceKey || sk.targetFace.endsWith(faceKey)) {
        final cy = sk.localCenter.y * fDir;
        if (sk.featureType == 'circle_hole') {
          flgHoles.add(
            _makeOctagonHole(CadPoint3D(sk.localCenter.x, cy, zCoord), sk.widthMm / 2.0, const CadPoint3D(1.0, 0.0, 0.0), const CadPoint3D(0.0, 1.0, 0.0)),
          );
        } else if (sk.featureType == 'obround_slot') {
          flgHoles.add(_makeObroundSlot(sk.localCenter.x, cy, zCoord, sk.widthMm, sk.heightMm));
        } else if (sk.featureType == 'rect_cut' || sk.featureType == 'rect_slot') {
          flgHoles.add(_makeRectSlotXY(sk.localCenter.x, cy, zCoord, sk.widthMm, sk.heightMm));
        }
      }
    }
    return flgHoles;
  }

  void _addHoleBoreWalls(List<CadFoldedPolygon3D> thickPolys, List<List<CadPoint3D>> holes, CadPoint3D faceNormal, double t) {
    for (int h = 0; h < holes.length; h++) {
      final loop = holes[h];
      for (int i = 0; i < loop.length; i++) {
        final v0 = loop[i];
        final v1 = loop[(i + 1) % loop.length];
        final v1In = CadPoint3D(v1.x - faceNormal.x * t, v1.y - faceNormal.y * t, v1.z - faceNormal.z * t);
        final v0In = CadPoint3D(v0.x - faceNormal.x * t, v0.y - faceNormal.y * t, v0.z - faceNormal.z * t);
        thickPolys.add(CadFoldedPolygon3D(faceId: '${id}_bore_${h}_$i', vertices: [v0, v1, v1In, v0In], normal: faceNormal, color: const Color(0xFF334155)));
      }
    }
  }

  void _addBendLinePolygons(List<CadFoldedPolygon3D> polys, double faceH) {
    for (final sk in sketches) {
      if (sk.featureType == 'bend_line') {
        polys.add(
          CadFoldedPolygon3D(
            faceId: '${id}_bend_${sk.id}',
            vertices: [
              CadPoint3D(sk.localCenter.x - 1.0, -0.2, 0.0),
              CadPoint3D(sk.localCenter.x + 1.0, -0.2, 0.0),
              CadPoint3D(sk.localCenter.x + 1.0, -0.2, faceH),
              CadPoint3D(sk.localCenter.x - 1.0, -0.2, faceH),
            ],
            normal: const CadPoint3D(0.0, -1.0, 0.0),
            color: const Color(0xFFF59E0B),
          ),
        );
      }
    }
  }

  List<CadPoint3D> _makeRectSlot(double cx, double cy, double cz, double lengthMm, double heightMm) {
    final hw = lengthMm / 2.0;
    final hh = heightMm / 2.0;
    return [CadPoint3D(cx - hw, cy, cz - hh), CadPoint3D(cx + hw, cy, cz - hh), CadPoint3D(cx + hw, cy, cz + hh), CadPoint3D(cx - hw, cy, cz + hh)];
  }

  List<CadPoint3D> _makeRectSlotXY(double cx, double cy, double cz, double lengthMm, double widthMm) {
    final hw = lengthMm / 2.0;
    final hh = widthMm / 2.0;
    return [CadPoint3D(cx - hw, cy - hh, cz), CadPoint3D(cx + hw, cy - hh, cz), CadPoint3D(cx + hw, cy + hh, cz), CadPoint3D(cx - hw, cy + hh, cz)];
  }

  List<CadPoint3D> _makeObroundSlotXZ(double cx, double cy, double cz, double lengthMm, double heightMm) {
    const int steps = 6;
    final r = heightMm / 2.0;
    final hl = math.max(0.0, (lengthMm - heightMm) / 2.0);
    final pts = <CadPoint3D>[];

    // Right cap
    for (int k = 0; k <= steps; k++) {
      final a = -math.pi / 2.0 + (math.pi * k / steps);
      pts.add(CadPoint3D(cx + hl + r * math.cos(a), cy, cz + r * math.sin(a)));
    }
    // Left cap
    for (int k = 0; k <= steps; k++) {
      final a = math.pi / 2.0 + (math.pi * k / steps);
      pts.add(CadPoint3D(cx - hl + r * math.cos(a), cy, cz + r * math.sin(a)));
    }
    return pts;
  }

  List<CadPoint3D> _makeObroundSlot(double cx, double cy, double cz, double lengthMm, double widthMm) {
    const int steps = 6;
    final r = widthMm / 2.0;
    final hl = (lengthMm - widthMm) / 2.0;
    final pts = <CadPoint3D>[];

    // Right cap
    for (int k = 0; k <= steps; k++) {
      final a = -math.pi / 2.0 + (math.pi * k / steps);
      pts.add(CadPoint3D(cx + hl + r * math.cos(a), cy + r * math.sin(a), cz));
    }
    // Left cap
    for (int k = 0; k <= steps; k++) {
      final a = math.pi / 2.0 + (math.pi * k / steps);
      pts.add(CadPoint3D(cx - hl + r * math.cos(a), cy + r * math.sin(a), cz));
    }
    return pts;
  }

  List<CadPoint3D> _makeOctagonHole(CadPoint3D center, double r, CadPoint3D u, CadPoint3D v) {
    const int steps = 8;
    final pts = <CadPoint3D>[];
    for (int k = 0; k < steps; k++) {
      final ang = k * 2.0 * math.pi / steps;
      pts.add(
        CadPoint3D(
          center.x + u.x * r * math.cos(ang) + v.x * r * math.sin(ang),
          center.y + u.y * r * math.cos(ang) + v.y * r * math.sin(ang),
          center.z + u.z * r * math.cos(ang) + v.z * r * math.sin(ang),
        ),
      );
    }
    return pts;
  }
}
