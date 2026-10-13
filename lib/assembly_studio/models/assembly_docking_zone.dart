import '../../sheet_metal_studio/models/cad_primitives.dart';
import 'assembly_part.dart';

/// Distinct classifications for interactive 3D snapping points in the Assembly Studio.
enum AssemblySnapPointType {
  /// Bounding box corners / end vertices
  boundingBoxCorner,

  /// Bounding box 12 edge midpoints
  boundingBoxEdgeCenter,

  /// Overall 3D centroid of the part
  boundingBoxCentroid,

  /// Axial end cap or side web centers
  boundingBoxFaceCenter,

  /// Center point of a punched hole, slot, or cutout (circle, obround, rect)
  holeCenter,

  /// Perimeter vertices / quadrant endpoints along a hole outline
  holePerimeter,

  /// Center point of an interactive sketch feature drawn on the part
  sketchCenter,

  /// Endpoints / corners of an interactive sketch feature drawn on the part
  sketchEndpoint,
}

/// Represents an interactive 3D snapping point on an assembly entity.
/// Supports bounding boxes, hole centers/outlines, and sketched features.
class AssemblySnapPoint {
  /// Unique identifier for this snap point.
  final String id;

  /// ID of the owning [AssemblyPart].
  final String partId;

  /// Absolute 3D world coordinates.
  final CadPoint3D worldPosition;

  /// 3D coordinates relative to the part origin.
  final CadPoint3D localPosition;

  /// Surface normal vector at this snap point (if applicable).
  final CadPoint3D normal;

  /// Specific classification of this snap point.
  final AssemblySnapPointType type;

  /// User-friendly label displayed in VCB HUD and visual badges.
  final String label;

  /// Optional feature or hole index / id.
  final String? featureId;

  const AssemblySnapPoint({
    required this.id,
    required this.partId,
    required this.worldPosition,
    required this.localPosition,
    this.normal = const CadPoint3D(0.0, 0.0, 1.0),
    required this.type,
    required this.label,
    this.featureId,
  });

  /// True if this snap point represents a hole center or sketch center.
  bool get isCenter =>
      type == AssemblySnapPointType.holeCenter ||
      type == AssemblySnapPointType.sketchCenter ||
      type == AssemblySnapPointType.boundingBoxCentroid;

  /// True if this point originates from a hole or sketch.
  bool get isHoleOrSketch =>
      type == AssemblySnapPointType.holeCenter ||
      type == AssemblySnapPointType.holePerimeter ||
      type == AssemblySnapPointType.sketchCenter ||
      type == AssemblySnapPointType.sketchEndpoint;

  @override
  String toString() => 'AssemblySnapPoint($id, $type, pos=$worldPosition, label=$label)';
}

/// Represents a designated mating or drop zone on an assembly entity
/// (e.g., punched rung slots, mounting cleats, wall bracket mating pads).
class AssemblyDropZone {
  final String id;
  final String partId;
  final CadPoint3D center; // in world space
  final CadPoint3D size; // dimensions (dx, dy, dz)
  final CadPoint3D normal;
  final String label;
  final String? targetFace;

  const AssemblyDropZone({
    required this.id,
    required this.partId,
    required this.center,
    required this.size,
    this.normal = const CadPoint3D(0.0, 0.0, 1.0),
    required this.label,
    this.targetFace,
  });

  /// Evaluates whether a 3D world point falls within this drop zone's catchment envelope.
  bool containsPoint(CadPoint3D worldPt, {double toleranceMm = 20.0}) {
    final halfX = (size.x / 2.0) + toleranceMm;
    final halfY = (size.y / 2.0) + toleranceMm;
    final halfZ = (size.z / 2.0) + toleranceMm;

    return (worldPt.x - center.x).abs() <= halfX &&
        (worldPt.y - center.y).abs() <= halfY &&
        (worldPt.z - center.z).abs() <= halfZ;
  }
}

/// Dynamic state for smooth, animated snap transitions (ease-out cubic lerp).
class SnapAnimationState {
  final AssemblyPart sourcePart;
  final CadPoint3D startPosition;
  final CadPoint3D targetPosition;
  final AssemblySnapPoint sourceSnap;
  final AssemblySnapPoint targetSnap;
  final double progress; // 0.0 to 1.0
  final bool isComplete;

  const SnapAnimationState({
    required this.sourcePart,
    required this.startPosition,
    required this.targetPosition,
    required this.sourceSnap,
    required this.targetSnap,
    required this.progress,
    this.isComplete = false,
  });

  /// Returns the current interpolated position along the curve.
  CadPoint3D get currentPosition {
    return CadPoint3D(
      startPosition.x + (targetPosition.x - startPosition.x) * progress,
      startPosition.y + (targetPosition.y - startPosition.y) * progress,
      startPosition.z + (targetPosition.z - startPosition.z) * progress,
    );
  }
}
