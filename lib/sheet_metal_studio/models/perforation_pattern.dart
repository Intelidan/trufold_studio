// =============================================================================
// perforation_pattern.dart
//
// Represents a unified, grouped perforation pattern (grid array of CNC slots/holes).
// Holds array parameters, anchor center point, rotation, and sparse excluded/deleted holes.
// Prevents individual pattern holes from cluttering the CAD tree or drawing list.
// =============================================================================

import 'dart:math' as math;

import 'cad_primitives.dart';
import 'cnc_punch_primitive.dart';

class PerforationPattern {
  final String id;
  final CadPoint2D anchor; // Center coordinate of the entire grid array (in mm)
  final PunchType holeType; // obroundSlot, roundHole, etc.
  final double slotWidthMm; // Width of slot (or punch width)
  final double slotLengthMm; // Length of slot (or punch length)
  final double diameterMm; // Diameter if round hole
  final int countX; // Number of columns
  final int countY; // Number of rows
  final double pitchX; // Center-to-center spacing along X
  final double pitchY; // Center-to-center spacing along Y
  final bool staggered; // Whether adjacent columns/rows are staggered
  final double staggerDistanceMm; // Distance between staggered punches (default 25.0 mm center-to-center)
  final bool
  staggerAlongY; // Stagger adjacent columns along Y (true for CMS trays)
  final double
  rotationDeg; // Orientation angle of individual hole primitives in degrees
  final double
  gridRotationDeg; // Orientation angle of entire grid array layout in degrees
  final bool showLabel; // Whether dimensional label is visible
  final bool isVisible; // Whether pattern is visible/active (vs temporarily suppressed)
  final Set<int> deletedHoleIndices; // Sparse set of hole indices deleted by user
  final String layer;
  final String? targetFaceId; // Surface/face to which pattern is applied
  final String? countXExpression; // Dynamic formula expression for columns: e.g. "floor((WIDTH - 2 * MARGIN) / PITCH_X)"
  final String? countYExpression; // Dynamic formula expression for rows: e.g. "floor((LENGTH - 2 * MARGIN) / PITCH_Y)"
  final String? pitchXParameter; // Linked parameter name for pitch X: e.g. "PITCH_X"
  final String? pitchYParameter; // Linked parameter name for pitch Y: e.g. "PITCH_Y"
  final String? marginParameter; // Linked parameter name for margin: e.g. "EDGE_MARGIN" 

  const PerforationPattern({
    required this.id,
    required this.anchor,
    this.holeType = PunchType.obroundSlot,
    this.slotWidthMm = 7.0,
    this.slotLengthMm = 25.0,
    this.diameterMm = 8.0,
    required this.countX,
    required this.countY,
    required this.pitchX,
    required this.pitchY,
    this.staggered = false,
    this.staggerDistanceMm = 25.0,
    this.staggerAlongY = true,
    this.rotationDeg = 0.0,
    this.gridRotationDeg = 0.0,
    this.showLabel = true,
    this.isVisible = true,
    this.deletedHoleIndices = const {},
    this.layer = 'HOLES',
    this.targetFaceId,
    this.countXExpression,
    this.countYExpression,
    this.pitchXParameter,
    this.pitchYParameter,
    this.marginParameter,
  });

  /// Total potential hole count in the full rectangular grid
  int get totalHoleCount => countX * countY;

  /// Active, non-deleted hole count
  int get activeHoleCount => totalHoleCount - deletedHoleIndices.length;

  /// Unrotated local coordinate relative to the grid anchor for hole (ix, iy)
  CadPoint2D relativeHoleCenter(int ix, int iy) {
    final totalW = (countX - 1) * pitchX;
    final totalH = (countY - 1) * pitchY;
    final startX = -totalW / 2.0;
    final startY = -totalH / 2.0;

    double offsetX = 0.0;
    double offsetY = 0.0;
    if (staggered) {
      if (staggerAlongY) {
        if (ix % 2 == 1) {
          offsetY = staggerDistanceMm;
        }
      } else {
        if (iy % 2 == 1) {
          offsetX = (pitchX != 0) ? pitchX / 2.0 : staggerDistanceMm;
        }
      }
    }
    return CadPoint2D(
      startX + ix * pitchX + offsetX,
      startY + iy * pitchY + offsetY,
    );
  }

  /// Transforms a local coordinate to world coordinates via anchor and gridRotationDeg.
  /// Does NOT apply individual hole rotationDeg to the grid coordinates, keeping the grid
  /// columns and rows upright and aligned with the sheet/face axis.
  CadPoint2D localToWorld(CadPoint2D local) {
    if (gridRotationDeg == 0.0) {
      return CadPoint2D(anchor.x + local.x, anchor.y + local.y);
    }
    final rad = gridRotationDeg * math.pi / 180.0;
    final cosR = math.cos(rad);
    final sinR = math.sin(rad);
    return CadPoint2D(
      anchor.x + (local.x * cosR - local.y * sinR),
      anchor.y + (local.x * sinR + local.y * cosR),
    );
  }

  /// World center coordinate for a specific hole index (0 <= index < totalHoleCount)
  CadPoint2D holeCenter(int index) {
    if (countX <= 0) return anchor;
    final iy = index ~/ countX;
    final ix = index % countX;
    return localToWorld(relativeHoleCenter(ix, iy));
  }

  /// Returns list of all active world center points
  List<CadPoint2D> get activeCenters {
    final list = <CadPoint2D>[];
    for (int iy = 0; iy < countY; iy++) {
      for (int ix = 0; ix < countX; ix++) {
        final idx = iy * countX + ix;
        if (!deletedHoleIndices.contains(idx)) {
          list.add(localToWorld(relativeHoleCenter(ix, iy)));
        }
      }
    }
    return list;
  }

  /// Expands pattern into CncPunchPrimitive instances for the kinematic fold engine, DXF export, etc.
  /// Individual holes are rotated around their own center by (rotationDeg + gridRotationDeg).
  List<CncPunchPrimitive> expandToPunches() {
    final punches = <CncPunchPrimitive>[];
    final punchRot = (rotationDeg + gridRotationDeg) % 360.0;

    for (int iy = 0; iy < countY; iy++) {
      for (int ix = 0; ix < countX; ix++) {
        final idx = iy * countX + ix;
        if (deletedHoleIndices.contains(idx)) continue;
        final center = localToWorld(relativeHoleCenter(ix, iy));

        if (holeType == PunchType.roundHole) {
          punches.add(
            CncPunchPrimitive.round(
              id: '${id}_$idx',
              center: center,
              diameterMm: diameterMm,
              layer: layer,
              showLabel: showLabel,
            ),
          );
        } else if (holeType == PunchType.square) {
          punches.add(
            CncPunchPrimitive(
              id: '${id}_$idx',
              type: PunchType.square,
              center: center,
              diameterMm: diameterMm > 0 ? diameterMm : slotWidthMm,
              rotationDeg: punchRot,
              layer: layer,
              showLabel: showLabel,
            ),
          );
        } else if (holeType == PunchType.rectangle) {
          punches.add(
            CncPunchPrimitive(
              id: '${id}_$idx',
              type: PunchType.rectangle,
              center: center,
              widthMm: slotWidthMm,
              lengthMm: slotLengthMm,
              rotationDeg: punchRot,
              layer: layer,
              showLabel: showLabel,
            ),
          );
        } else {
          punches.add(
            CncPunchPrimitive.obround(
              id: '${id}_$idx',
              center: center,
              widthMm: slotWidthMm,
              lengthMm: slotLengthMm,
              rotationDeg: punchRot,
              layer: layer,
              showLabel: showLabel,
            ),
          );
        }
      }
    }
    return punches;
  }

  /// Surface area of a single hole in mm²
  double get singleHoleAreaMm2 {
    if (holeType == PunchType.roundHole) {
      return math.pi * (diameterMm / 2.0) * (diameterMm / 2.0);
    } else if (holeType == PunchType.square) {
      final s = diameterMm > 0 ? diameterMm : slotWidthMm;
      return s * s;
    } else if (holeType == PunchType.rectangle) {
      return slotWidthMm * slotLengthMm;
    } else {
      final straight = math.max(0.0, slotLengthMm - slotWidthMm);
      final r = slotWidthMm / 2.0;
      return (straight * slotWidthMm) + (math.pi * r * r);
    }
  }

  /// Total cut area removed by all active holes in this pattern
  double get totalHolesAreaMm2 => singleHoleAreaMm2 * activeHoleCount;

  /// Returns true if a point is within the bounding radius of this pattern
  bool containsPoint(CadPoint2D pt) {
    final totalW = (countX - 1) * pitchX + math.max(slotLengthMm, slotWidthMm);
    final totalH =
        (countY - 1) * pitchY +
        math.max(slotLengthMm, slotWidthMm) +
        (staggered ? staggerDistanceMm : 0.0);
    final maxRadius = math.sqrt(totalW * totalW + totalH * totalH) / 2.0;
    return anchor.distanceTo(pt) <= maxRadius;
  }

  /// Returns the axis-aligned bounding box of this perforation pattern in world coordinates.
  ({double left, double top, double right, double bottom}) calculateBounds() {
    final centers = activeCenters;
    final hw = (holeType == PunchType.roundHole
            ? (diameterMm > 0 ? diameterMm : slotWidthMm)
            : math.max(slotLengthMm, slotWidthMm)) /
        2.0;
    if (centers.isEmpty) {
      return (
        left: anchor.x - hw,
        top: anchor.y - hw,
        right: anchor.x + hw,
        bottom: anchor.y + hw,
      );
    }
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    for (final c in centers) {
      if (c.x - hw < minX) minX = c.x - hw;
      if (c.y - hw < minY) minY = c.y - hw;
      if (c.x + hw > maxX) maxX = c.x + hw;
      if (c.y + hw > maxY) maxY = c.y + hw;
    }
    return (left: minX, top: minY, right: maxX, bottom: maxY);
  }

  /// Finds index of hole closest to the given world point if within radius
  int? findHoleAt(CadPoint2D pt, {double maxDistMm = 15.0}) {
    int? closestIdx;
    double closestDist = maxDistMm;

    for (int iy = 0; iy < countY; iy++) {
      for (int ix = 0; ix < countX; ix++) {
        final idx = iy * countX + ix;
        if (deletedHoleIndices.contains(idx)) continue;
        final c = localToWorld(relativeHoleCenter(ix, iy));
        final d = c.distanceTo(pt);
        if (d < closestDist) {
          closestDist = d;
          closestIdx = idx;
        }
      }
    }
    return closestIdx;
  }

  PerforationPattern copyWith({
    String? id,
    CadPoint2D? anchor,
    PunchType? holeType,
    double? slotWidthMm,
    double? slotLengthMm,
    double? diameterMm,
    int? countX,
    int? countY,
    double? pitchX,
    double? pitchY,
    bool? staggered,
    double? staggerDistanceMm,
    bool? staggerAlongY,
    double? rotationDeg,
    double? gridRotationDeg,
    bool? showLabel,
    bool? isVisible,
    Set<int>? deletedHoleIndices,
    String? layer,
    String? targetFaceId,
    String? countXExpression,
    String? countYExpression,
    String? pitchXParameter,
    String? pitchYParameter,
    String? marginParameter,
  }) {
    return PerforationPattern(
      id: id ?? this.id,
      anchor: anchor ?? this.anchor,
      holeType: holeType ?? this.holeType,
      slotWidthMm: slotWidthMm ?? this.slotWidthMm,
      slotLengthMm: slotLengthMm ?? this.slotLengthMm,
      diameterMm: diameterMm ?? this.diameterMm,
      countX: countX ?? this.countX,
      countY: countY ?? this.countY,
      pitchX: pitchX ?? this.pitchX,
      pitchY: pitchY ?? this.pitchY,
      staggered: staggered ?? this.staggered,
      staggerDistanceMm: staggerDistanceMm ?? this.staggerDistanceMm,
      staggerAlongY: staggerAlongY ?? this.staggerAlongY,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      gridRotationDeg: gridRotationDeg ?? this.gridRotationDeg,
      showLabel: showLabel ?? this.showLabel,
      isVisible: isVisible ?? this.isVisible,
      deletedHoleIndices: deletedHoleIndices ?? this.deletedHoleIndices,
      layer: layer ?? this.layer,
      targetFaceId: targetFaceId ?? this.targetFaceId,
      countXExpression: countXExpression ?? this.countXExpression,
      countYExpression: countYExpression ?? this.countYExpression,
      pitchXParameter: pitchXParameter ?? this.pitchXParameter,
      pitchYParameter: pitchYParameter ?? this.pitchYParameter,
      marginParameter: marginParameter ?? this.marginParameter,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'anchor': anchor.toJson(),
    'holeType': holeType.name,
    'slotWidthMm': slotWidthMm,
    'slotLengthMm': slotLengthMm,
    'diameterMm': diameterMm,
    'countX': countX,
    'countY': countY,
    'pitchX': pitchX,
    'pitchY': pitchY,
    'staggered': staggered,
    'staggerDistanceMm': staggerDistanceMm,
    'staggerAlongY': staggerAlongY,
    'rotationDeg': rotationDeg,
    'gridRotationDeg': gridRotationDeg,
    'showLabel': showLabel,
    'isVisible': isVisible,
    'deletedHoleIndices': deletedHoleIndices.toList(),
    'layer': layer,
    'targetFaceId': targetFaceId,
    if (countXExpression != null) 'countXExpression': countXExpression,
    if (countYExpression != null) 'countYExpression': countYExpression,
    if (pitchXParameter != null) 'pitchXParameter': pitchXParameter,
    if (pitchYParameter != null) 'pitchYParameter': pitchYParameter,
    if (marginParameter != null) 'marginParameter': marginParameter,
  };

  factory PerforationPattern.fromJson(Map<String, dynamic> json) {
    return PerforationPattern(
      id: json['id'] as String,
      anchor: CadPoint2D.fromJson(json['anchor'] as Map<String, dynamic>),
      holeType: PunchType.values.firstWhere(
        (v) => v.name == json['holeType'],
        orElse: () => PunchType.obroundSlot,
      ),
      slotWidthMm: (json['slotWidthMm'] as num?)?.toDouble() ?? 7.0,
      slotLengthMm: (json['slotLengthMm'] as num?)?.toDouble() ?? 25.0,
      diameterMm: (json['diameterMm'] as num?)?.toDouble() ?? 8.0,
      countX: (json['countX'] as num?)?.toInt() ?? 1,
      countY: (json['countY'] as num?)?.toInt() ?? 1,
      pitchX: (json['pitchX'] as num?)?.toDouble() ?? 30.0,
      pitchY: (json['pitchY'] as num?)?.toDouble() ?? 100.0,
      staggered: json['staggered'] as bool? ?? false,
      staggerDistanceMm:
          (json['staggerDistanceMm'] as num?)?.toDouble() ?? 25.0,
      staggerAlongY: json['staggerAlongY'] as bool? ?? true,
      rotationDeg: (json['rotationDeg'] as num?)?.toDouble() ?? 0.0,
      gridRotationDeg: (json['gridRotationDeg'] as num?)?.toDouble() ?? 0.0,
      showLabel: json['showLabel'] as bool? ?? true,
      isVisible: json['isVisible'] as bool? ?? true,
      deletedHoleIndices: ((json['deletedHoleIndices'] as List<dynamic>?) ?? [])
          .map((e) => (e as num).toInt())
          .toSet(),
      layer: json['layer'] as String? ?? 'HOLES',
      targetFaceId: json['targetFaceId'] as String?,
      countXExpression: json['countXExpression'] as String?,
      countYExpression: json['countYExpression'] as String?,
      pitchXParameter: json['pitchXParameter'] as String?,
      pitchYParameter: json['pitchYParameter'] as String?,
      marginParameter: json['marginParameter'] as String?,
    );
  }
}
