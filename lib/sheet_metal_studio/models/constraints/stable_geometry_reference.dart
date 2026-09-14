// =============================================================================
// stable_geometry_reference.dart
//
// Stable entity and sub-element reference model per Phase 1 Master Guide
// Sections 9, 10, 13 & Set 02.
//
// Never relies on raw array indices. Supports:
// - Standard Part References: EDGE_LEFT, EDGE_RIGHT, EDGE_TOP, EDGE_BOTTOM
// - Centerlines & Origin: CENTER_X, CENTER_Y, ORIGIN, X_AXIS, Y_AXIS
// - Sub-Element References: Line001.start, Line001.end, Line001.edge
// - Punch / Hole References: Punch001.center, Punch001.edge
// - Arc References: Arc001.center, Arc001.start, Arc001.end
// - Part-to-Part Assembly References: PartA.EDGE_LEFT, PartB.EDGE_TOP
// =============================================================================

enum GeometrySubRefType {
  whole, // Refers to the whole entity / edge line
  start, // Start point (p1)
  end, // End point (p2)
  center, // Center point of circle, arc, or punch
  edge, // Boundary edge / circumference
  midpoint, // Midpoint of line segment
}

/// A stable, array-index-independent reference to an entity or sub-feature.
class EntityRef {
  /// Primary entity or reference name (e.g. 'EDGE_LEFT', 'CENTER_X', 'LINE_01', 'PUNCH_02')
  final String entityId;

  /// Sub-element selector (e.g. start, end, center, edge, whole)
  final GeometrySubRefType subRef;

  /// Optional parent part or body ID for multi-part / multi-body bindings (e.g. 'PART_MAIN', 'BRANCH_1')
  final String? partId;

  const EntityRef({
    required this.entityId,
    this.subRef = GeometrySubRefType.whole,
    this.partId,
  });

  /// Standard part reference constants
  static const EntityRef edgeLeft = EntityRef(entityId: 'EDGE_LEFT');
  static const EntityRef edgeRight = EntityRef(entityId: 'EDGE_RIGHT');
  static const EntityRef edgeTop = EntityRef(entityId: 'EDGE_TOP');
  static const EntityRef edgeBottom = EntityRef(entityId: 'EDGE_BOTTOM');
  static const EntityRef centerX = EntityRef(entityId: 'CENTER_X');
  static const EntityRef centerY = EntityRef(entityId: 'CENTER_Y');
  static const EntityRef origin = EntityRef(entityId: 'ORIGIN');
  static const EntityRef xAxis = EntityRef(entityId: 'X_AXIS');
  static const EntityRef yAxis = EntityRef(entityId: 'Y_AXIS');

  /// Creates reference to a punch/hole center
  factory EntityRef.punchCenter(String punchId, {String? partId}) => EntityRef(
        entityId: punchId,
        subRef: GeometrySubRefType.center,
        partId: partId,
      );

  /// Creates reference to a line start point
  factory EntityRef.lineStart(String lineId, {String? partId}) => EntityRef(
        entityId: lineId,
        subRef: GeometrySubRefType.start,
        partId: partId,
      );

  /// Creates reference to a line end point
  factory EntityRef.lineEnd(String lineId, {String? partId}) => EntityRef(
        entityId: lineId,
        subRef: GeometrySubRefType.end,
        partId: partId,
      );

  /// Creates reference to a line midpoint
  factory EntityRef.lineMidpoint(String lineId, {String? partId}) => EntityRef(
        entityId: lineId,
        subRef: GeometrySubRefType.midpoint,
        partId: partId,
      );

  /// Creates reference to an edge of an entity or contour segment
  factory EntityRef.edge(String edgeId, {String? partId}) => EntityRef(
        entityId: edgeId,
        subRef: GeometrySubRefType.edge,
        partId: partId,
      );

  /// Returns canonical string representation:
  /// e.g. "EDGE_LEFT", "PUNCH_01.center", "PartA.EDGE_TOP", "Line01.start"
  String get canonicalPath {
    final subStr = subRef == GeometrySubRefType.whole ? '' : '.${subRef.name}';
    if (partId != null && partId!.isNotEmpty) {
      return '$partId.$entityId$subStr';
    }
    return '$entityId$subStr';
  }

  /// Parses canonical string back to [EntityRef]
  factory EntityRef.parse(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return const EntityRef(entityId: '');

    // Check for standard built-ins first
    switch (trimmed.toUpperCase()) {
      case 'EDGE_LEFT':
        return EntityRef.edgeLeft;
      case 'EDGE_RIGHT':
        return EntityRef.edgeRight;
      case 'EDGE_TOP':
        return EntityRef.edgeTop;
      case 'EDGE_BOTTOM':
        return EntityRef.edgeBottom;
      case 'CENTER_X':
        return EntityRef.centerX;
      case 'CENTER_Y':
        return EntityRef.centerY;
      case 'ORIGIN':
        return EntityRef.origin;
      case 'X_AXIS':
        return EntityRef.xAxis;
      case 'Y_AXIS':
        return EntityRef.yAxis;
    }

    final parts = trimmed.split('.');
    if (parts.length == 1) {
      return EntityRef(entityId: parts[0]);
    } else if (parts.length == 2) {
      // Could be Entity.subRef or Part.Entity
      final sub = _matchSubRef(parts[1]);
      if (sub != null) {
        return EntityRef(entityId: parts[0], subRef: sub);
      } else {
        return EntityRef(partId: parts[0], entityId: parts[1]);
      }
    } else {
      // Part.Entity.subRef
      final sub = _matchSubRef(parts[2]) ?? GeometrySubRefType.whole;
      return EntityRef(partId: parts[0], entityId: parts[1], subRef: sub);
    }
  }

  static GeometrySubRefType? _matchSubRef(String s) {
    switch (s.toLowerCase()) {
      case 'start':
      case 'p1':
        return GeometrySubRefType.start;
      case 'end':
      case 'p2':
        return GeometrySubRefType.end;
      case 'center':
      case 'c':
        return GeometrySubRefType.center;
      case 'edge':
      case 'line':
        return GeometrySubRefType.edge;
      case 'mid':
      case 'midpoint':
        return GeometrySubRefType.midpoint;
      case 'whole':
        return GeometrySubRefType.whole;
      default:
        return null;
    }
  }

  bool get isStandardPartReference {
    final upper = entityId.toUpperCase();
    return upper == 'EDGE_LEFT' ||
        upper == 'EDGE_RIGHT' ||
        upper == 'EDGE_TOP' ||
        upper == 'EDGE_BOTTOM' ||
        upper == 'CENTER_X' ||
        upper == 'CENTER_Y' ||
        upper == 'ORIGIN';
  }

  bool get isCenterline =>
      entityId.toUpperCase() == 'CENTER_X' || entityId.toUpperCase() == 'CENTER_Y';

  Map<String, dynamic> toJson() => {
        'entityId': entityId,
        'subRef': subRef.name,
        if (partId != null) 'partId': partId,
      };

  factory EntityRef.fromJson(Map<String, dynamic> json) => EntityRef(
        entityId: json['entityId'] as String,
        subRef: GeometrySubRefType.values.firstWhere(
          (s) => s.name == json['subRef'],
          orElse: () => GeometrySubRefType.whole,
        ),
        partId: json['partId'] as String?,
      );

  @override
  String toString() => canonicalPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityRef &&
          entityId == other.entityId &&
          subRef == other.subRef &&
          partId == other.partId;

  @override
  int get hashCode => Object.hash(entityId, subRef, partId);
}
