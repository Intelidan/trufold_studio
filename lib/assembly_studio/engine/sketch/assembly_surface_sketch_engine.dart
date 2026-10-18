import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../../sketch_draft_files/data_operations_persistance_compliers/cad_serializer.dart';
import '../../../sketch_draft_files/data_operations_persistance_compliers/cad_stl_exporter.dart';
import '../../../sketch_draft_files/math_and_processing/cad_boolean_engine.dart';
import '../../../sketch_draft_files/math_and_processing/cad_grid_solver.dart';
import '../../../sketch_draft_files/math_and_processing/cad_profile_validator.dart';
import '../../../sketch_draft_files/math_and_processing/cad_tessellator.dart';
import '../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../models/assembly_part.dart';
import 'cad_brep_topology_bridge.dart';

export '../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
export '../../../sketch_draft_files/data_operations_persistance_compliers/cad_serializer.dart';
export '../../../sketch_draft_files/data_operations_persistance_compliers/cad_stl_exporter.dart';
export '../../../sketch_draft_files/math_and_processing/cad_boolean_engine.dart';
export '../../../sketch_draft_files/math_and_processing/cad_constraint_solvers.dart';
export '../../../sketch_draft_files/math_and_processing/cad_corner_modifier.dart';
export '../../../sketch_draft_files/math_and_processing/cad_grid_solver.dart';
export '../../../sketch_draft_files/math_and_processing/cad_interfacing_engine.dart';
export '../../../sketch_draft_files/math_and_processing/cad_intersection_solver.dart';
export '../../../sketch_draft_files/math_and_processing/cad_profile_validator.dart';
export '../../../sketch_draft_files/math_and_processing/cad_raycaster.dart';
export '../../../sketch_draft_files/math_and_processing/cad_tessellator.dart';
export '../../../sketch_draft_files/procedural_layout_mesh_builders/cad_geometry_builders.dart';
export 'assembly_sketch_constraint_solver.dart';
export 'assembly_extrude_engine.dart';

enum SketchDimensionOrientation { horizontal, vertical, aligned, radial, diameter, angular }

class ResolvedLinearDimension2D {
  final vm.Vector2 anchor1; // On entity in Sketch 2D space
  final vm.Vector2 anchor2; // On entity in Sketch 2D space
  final vm.Vector2 dimLineStart; // On dimension line in Sketch 2D space
  final vm.Vector2 dimLineEnd;   // On dimension line in Sketch 2D space
  final vm.Vector2 witness1End;  // Overshoot tip 1
  final vm.Vector2 witness2End;  // Overshoot tip 2
  final vm.Vector2 labelCenter;
  final double measuredValue;

  ResolvedLinearDimension2D({
    required this.anchor1,
    required this.anchor2,
    required this.dimLineStart,
    required this.dimLineEnd,
    required this.witness1End,
    required this.witness2End,
    required this.labelCenter,
    required this.measuredValue,
  });
}

ResolvedLinearDimension2D computeOrthogonalDimension2D({
  required vm.Vector2 p1,
  required vm.Vector2 p2,
  required vm.Vector2 labelPosition2D,
  required SketchDimensionOrientation orientation,
  double witnessOvershootMm = 2.5,
}) {
  late vm.Vector2 measureDir;
  late vm.Vector2 perpNormal;

  if (orientation == SketchDimensionOrientation.horizontal) {
    measureDir = vm.Vector2(1.0, 0.0);
    perpNormal = vm.Vector2(0.0, 1.0);
  } else if (orientation == SketchDimensionOrientation.vertical) {
    measureDir = vm.Vector2(0.0, 1.0);
    perpNormal = vm.Vector2(1.0, 0.0);
  } else {
    // Aligned: strictly parallel to p1 -> p2
    final vm.Vector2 delta = p2 - p1;
    final double len = delta.length;
    measureDir = len > 1e-5 ? (delta / len) : vm.Vector2(1.0, 0.0);
    // Exact 90-degree perpendicular normal in 2D sketch plane: (-dy, dx)
    perpNormal = vm.Vector2(-measureDir.y, measureDir.x);
  }

  // Project labelPosition2D onto perpNormal to get signed perpendicular offset distance
  final vm.Vector2 mid = (p1 + p2) * 0.5;
  final double signedOffset = (labelPosition2D - mid).dot(perpNormal);
  final double sign = signedOffset >= 0.0 ? 1.0 : -1.0;

  // Project both anchors onto the dimension line so witness lines are 100% parallel to perpNormal
  final vm.Vector2 lineOrigin = mid + perpNormal * signedOffset;
  final double t1 = (p1 - lineOrigin).dot(measureDir);
  final double t2 = (p2 - lineOrigin).dot(measureDir);

  final vm.Vector2 dimStart = lineOrigin + measureDir * t1;
  final vm.Vector2 dimEnd = lineOrigin + measureDir * t2;

  final vm.Vector2 w1End = dimStart + perpNormal * (sign * witnessOvershootMm);
  final vm.Vector2 w2End = dimEnd + perpNormal * (sign * witnessOvershootMm);
  final double value = (t2 - t1).abs();

  return ResolvedLinearDimension2D(
    anchor1: p1,
    anchor2: p2,
    dimLineStart: dimStart,
    dimLineEnd: dimEnd,
    witness1End: w1End,
    witness2End: w2End,
    labelCenter: (dimStart + dimEnd) * 0.5,
    measuredValue: value,
  );
}

SketchDimensionOrientation inferOrientationFromCursor(vm.Vector2 p1, vm.Vector2 p2, vm.Vector2 cursor2D) {
  final double minX = math.min(p1.x, p2.x);
  final double maxX = math.max(p1.x, p2.x);
  final double minY = math.min(p1.y, p2.y);
  final double maxY = math.max(p1.y, p2.y);

  final bool outsideX = cursor2D.x < minX - 2.0 || cursor2D.x > maxX + 2.0;
  final bool outsideY = cursor2D.y < minY - 2.0 || cursor2D.y > maxY + 2.0;

  if (outsideX && !outsideY) {
    return SketchDimensionOrientation.vertical; // Cursor moved left/right of span -> Vertical dim
  } else if (outsideY && !outsideX) {
    return SketchDimensionOrientation.horizontal; // Cursor moved above/below span -> Horizontal dim
  }
  return SketchDimensionOrientation.aligned; // Cursor in diagonal quadrant -> Aligned dim
}

/// Orchestrates parametric 3D surface sketching, plane coordinate mapping,
/// profile loop validation, and CSG boolean cuts for OnShape / Fusion 360 workflows.
class AssemblySurfaceSketchEngine {
  final CADGridSolver gridSolver;

  AssemblySurfaceSketchEngine({double gridSpacing = 5.0})
      : gridSolver = CADGridSolver(gridSpacing: gridSpacing);

  /// Constructs a [CADSketchPlane] directly on a 3D folded polygon face.
  static CADSketchPlane createPlaneFromFacePolygon({
    required CadFoldedPolygon3D polygon,
    String? partId,
  }) {
    if (polygon.vertices.isEmpty) {
      return createDatumPlane('XY');
    }

    // Compute polygon centroid as origin
    double sumX = 0, sumY = 0, sumZ = 0;
    for (final v in polygon.vertices) {
      sumX += v.x;
      sumY += v.y;
      sumZ += v.z;
    }
    final count = polygon.vertices.length;
    final origin = vm.Vector3(sumX / count, sumY / count, sumZ / count);

    // Compute normal
    double nx = polygon.normal.x;
    double ny = polygon.normal.y;
    double nz = polygon.normal.z;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    final normal = len > 1e-4
        ? vm.Vector3(nx / len, ny / len, nz / len)
        : vm.Vector3(0.0, 0.0, 1.0);

    // Compute robust up vector tangent to face in Z-Up CAD coordinates:
    // - For vertical or angled faces (|normal.z| <= 0.90), World +Z (0, 0, 1) is screen-up.
    // - For horizontal top/bottom faces (|normal.z| > 0.90), World +Y (0, 1, 0) is screen-up.
    vm.Vector3 tentativeUp = vm.Vector3(0.0, 0.0, 1.0);
    if (normal.dot(tentativeUp).abs() > 0.90) {
      tentativeUp = vm.Vector3(0.0, 1.0, 0.0);
    }
    final up = (tentativeUp - normal * normal.dot(tentativeUp)).normalized();

    final plane = CADSketchPlane(
      id: 'plane_${polygon.faceId}',
      origin: origin,
      normal: normal,
      up: up,
      targetPartId: partId,
      targetFaceId: polygon.faceId,
    );

    // Auto-imprint host part face borders and hole centers as locked reference entities
    if (polygon.vertices.length >= 3) {
      for (int i = 0; i < polygon.vertices.length; i++) {
        final vCurrent = polygon.vertices[i];
        final vNext = polygon.vertices[(i + 1) % polygon.vertices.length];
        final p1 = plane.toLocal(vm.Vector3(vCurrent.x, vCurrent.y, vCurrent.z));
        final p2 = plane.toLocal(vm.Vector3(vNext.x, vNext.y, vNext.z));
        plane.primitives.add(CADLineEntity(
          id: 'imprint_border_${polygon.faceId}_$i',
          start: p1,
          end: p2,
          isImprintedReference: true,
          isFixed: true,
          isFullyConstrained: true,
        ));
      }
    }

    if (polygon.holes.isNotEmpty) {
      for (int h = 0; h < polygon.holes.length; h++) {
        final hole = polygon.holes[h];
        if (hole.length < 3) continue;
        double hSumX = 0, hSumY = 0, hSumZ = 0;
        for (final hv in hole) {
          hSumX += hv.x;
          hSumY += hv.y;
          hSumZ += hv.z;
        }
        final holeCenterWorld = vm.Vector3(hSumX / hole.length, hSumY / hole.length, hSumZ / hole.length);
        final holeCenter2D = plane.toLocal(holeCenterWorld);
        final firstHolePt2D = plane.toLocal(vm.Vector3(hole.first.x, hole.first.y, hole.first.z));
        final radius = (firstHolePt2D - holeCenter2D).distance;
        plane.primitives.add(CADCircleEntity(
          id: 'imprint_hole_${polygon.faceId}_$h',
          center: holeCenter2D,
          radius: radius > 0.1 ? radius : 5.0,
          isImprintedReference: true,
          isFixed: true,
          isFullyConstrained: true,
        ));
      }
    }

    return plane;
  }

  /// Imprints the host part face outer border edges and hole centers directly onto [plane]
  /// so dimensional constraints can be attached between sketch geometry and 3D body borders (SS2 & SS5).
  static void imprintHostPartBRepToPlane(CADSketchPlane plane, AssemblyPart part) {
    final brep = CadPlanarFaceBRep.extractFromPartFace(
      part: part,
      planeOriginWorld: plane.origin,
      planeNormalWorld: plane.normal,
      planeUAxisWorld: plane.xAxis,
      planeVAxisWorld: plane.yAxis,
    );
    for (final border in brep.outerBorderEdges2D) {
      if (!plane.primitives.any((p) => p.id == border.id)) {
        plane.primitives.add(CADLineEntity(
          id: border.id,
          start: Offset(border.start2D.x, border.start2D.y),
          end: Offset(border.end2D.x, border.end2D.y),
          isImprintedReference: true,
          isFixed: true,
          isFullyConstrained: true,
        ));
      }
    }
    for (final hole in brep.holes2D) {
      if (!plane.primitives.any((p) => p.id == hole.id)) {
        plane.primitives.add(CADCircleEntity(
          id: hole.id,
          center: Offset(hole.center2D.x, hole.center2D.y),
          radius: hole.diameterMm / 2.0,
          isImprintedReference: true,
          isFixed: true,
          isFullyConstrained: true,
        ));
      }
    }
  }

  /// Constructs a standard datum sketch plane (XY, XZ, or YZ).
  static CADSketchPlane createDatumPlane(String type, {vm.Vector3? customOrigin, double size = 140.0}) {
    final ori = customOrigin ?? vm.Vector3(0.0, 0.0, 0.0);
    switch (type.toUpperCase()) {
      case 'XZ':
        return CADSketchPlane(
          id: 'datum_XZ',
          name: 'XZ Front Plane',
          planeType: CADPlaneType.datumXZ,
          origin: ori,
          normal: vm.Vector3(0.0, -1.0, 0.0), // Faces the front camera (-Y)
          up: vm.Vector3(0.0, 0.0, 1.0),     // +Z is up on screen
          size: size,
          customColor: const Color(0xFF10B981),
        );
      case 'YZ':
        return CADSketchPlane(
          id: 'datum_YZ',
          name: 'YZ Right Plane',
          planeType: CADPlaneType.datumYZ,
          origin: ori,
          normal: vm.Vector3(1.0, 0.0, 0.0),  // Faces the right camera (+X)
          up: vm.Vector3(0.0, 0.0, 1.0),     // +Z is up on screen
          size: size,
          customColor: const Color(0xFFF59E0B),
        );
      case 'XY':
      default:
        return CADSketchPlane(
          id: 'datum_XY',
          name: 'XY Top Plane',
          planeType: CADPlaneType.datumXY,
          origin: ori,
          normal: vm.Vector3(0.0, 0.0, 1.0),  // Faces the top camera (+Z)
          up: vm.Vector3(0.0, 1.0, 0.0),     // +Y is up on screen
          size: size,
          customColor: const Color(0xFF0EA5E9),
        );
    }
  }

  /// Constructs an Offset Construction Plane parallel to a reference plane at a given distance.
  static CADSketchPlane createOffsetPlane({
    required CADSketchPlane parentPlane,
    required double offsetMm,
    String? name,
    double size = 140.0,
  }) {
    final norm = parentPlane.normal.normalized();
    final newOrigin = parentPlane.origin + (norm * offsetMm);
    final id = 'offset_plane_${DateTime.now().millisecondsSinceEpoch}';
    final autoName = name ?? 'Offset Plane (${offsetMm >= 0 ? "+$offsetMm" : "$offsetMm"}mm)';

    return CADSketchPlane(
      id: id,
      name: autoName,
      planeType: CADPlaneType.offsetPlane,
      origin: newOrigin,
      normal: norm,
      up: parentPlane.up.normalized(),
      parentPlaneId: parentPlane.id,
      offsetDistance: offsetMm,
      size: size,
      customColor: const Color(0xFF8B5CF6),
    );
  }

  /// Constructs an Angle Construction Plane rotated around an axis.
  static CADSketchPlane createAnglePlane({
    required CADSketchPlane referencePlane,
    required vm.Vector3 axisOrigin,
    required vm.Vector3 axisDir,
    required double angleDeg,
    String? name,
    double size = 140.0,
  }) {
    final norm = referencePlane.normal.normalized();
    final up = referencePlane.up.normalized();
    final axis = axisDir.normalized();

    // Rodrigues' rotation formula
    final rad = angleDeg * math.pi / 180.0;
    vm.Vector3 rotate(vm.Vector3 v) {
      final cosT = math.cos(rad);
      final sinT = math.sin(rad);
      return (v * cosT) + (axis.cross(v) * sinT) + (axis * (axis.dot(v) * (1.0 - cosT)));
    }

    final newNormal = rotate(norm).normalized();
    final newUp = rotate(up).normalized();
    final id = 'angle_plane_${DateTime.now().millisecondsSinceEpoch}';
    final autoName = name ?? 'Plane at Angle (${angleDeg.toStringAsFixed(1)}°)';

    return CADSketchPlane(
      id: id,
      name: autoName,
      planeType: CADPlaneType.anglePlane,
      origin: axisOrigin,
      normal: newNormal,
      up: newUp,
      parentPlaneId: referencePlane.id,
      angleDeg: angleDeg,
      size: size,
      customColor: const Color(0xFFA855F7),
    );
  }

  /// Constructs a Midplane equidistant between two parallel planes.
  static CADSketchPlane createMidplane({
    required CADSketchPlane plane1,
    required CADSketchPlane plane2,
    String? name,
    double size = 140.0,
  }) {
    final midOrigin = (plane1.origin + plane2.origin) * 0.5;
    final id = 'midplane_${DateTime.now().millisecondsSinceEpoch}';
    final autoName = name ?? 'Midplane';

    return CADSketchPlane(
      id: id,
      name: autoName,
      planeType: CADPlaneType.midplane,
      origin: midOrigin,
      normal: plane1.normal.normalized(),
      up: plane1.up.normalized(),
      size: size,
      customColor: const Color(0xFF06B6D4),
    );
  }

  /// Constructs a Construction Plane passing through 3 3D points.
  static CADSketchPlane createPlaneFrom3Points({
    required vm.Vector3 p1,
    required vm.Vector3 p2,
    required vm.Vector3 p3,
    String? name,
    double size = 140.0,
  }) {
    final v1 = (p2 - p1).normalized();
    final v2 = (p3 - p1).normalized();
    final normal = v1.cross(v2).normalized();
    final up = v1;
    final id = 'plane_3pt_${DateTime.now().millisecondsSinceEpoch}';
    final autoName = name ?? '3-Point Plane';

    return CADSketchPlane(
      id: id,
      name: autoName,
      planeType: CADPlaneType.threePointPlane,
      origin: p1,
      normal: normal,
      up: up,
      size: size,
      customColor: const Color(0xFFEC4899),
    );
  }

  /// Calculates camera azimuth & elevation angles in degrees to look
  /// directly antiparallel to the plane normal (normal view).
  static ({double azimuthDeg, double elevationDeg}) computeNormalViewCameraAngles(vm.Vector3 normal) {
    final n = normal.normalized();
    final elevationDeg = math.asin(n.z.clamp(-1.0, 1.0)) * 180.0 / math.pi;
    final azimuthDeg = math.atan2(n.x, -n.y) * 180.0 / math.pi;
    return (azimuthDeg: azimuthDeg, elevationDeg: elevationDeg);
  }

  /// Compiles all primitive shapes on the plane into discrete line segments.
  /// If [targetEntityIds] is provided, only segments belonging to those primitives/entities are returned.
  static List<CADLineSegment> compilePlaneSegments(
    CADSketchPlane plane, {
    Iterable<String>? targetEntityIds,
  }) {
    final targets = targetEntityIds?.toSet();
    final segments = <CADLineSegment>[];
    if (targets == null || targets.isEmpty) {
      segments.addAll(plane.entities);
      for (final prim in plane.primitives) {
        segments.addAll(prim.toLineSegments());
      }
    } else {
      segments.addAll(
        plane.entities.where((e) => targets.contains(e.sourceEntityId ?? e.id) || targets.contains(e.id)),
      );
      for (final prim in plane.primitives) {
        if (targets.contains(prim.id)) {
          segments.addAll(prim.toLineSegments());
        }
      }
    }
    return segments;
  }

  /// Validates closed-loop integrity of active entities on the plane.
  /// If [targetEntityIds] is provided, validates loops strictly formed by those targeted entities.
  static ValidationResult validatePlaneLoop(
    CADSketchPlane plane, {
    Iterable<String>? targetEntityIds,
  }) {
    final segments = compilePlaneSegments(plane, targetEntityIds: targetEntityIds);
    return CADProfileValidator.validateProfile(segments);
  }

  /// Tessellates a validated 2D loop into triangle indices for interior shading.
  static Uint16List tessellateLoop(List<Offset> loopVertices) {
    return CADTessellator.tessellatePolygon(loopVertices);
  }

  /// Cuts a closed profile through a 3D surface mesh.
  static Map<String, dynamic> executePassThroughCut({
    required Float32List vertices,
    required Uint16List indices,
    required CADSketchPlane plane,
    required List<Offset> path,
    required double thickness,
  }) {
    return CADBooleanEngine.executePassThroughCut(
      srcV: vertices,
      srcI: indices,
      plane: plane,
      path: path,
      thickness: thickness,
    );
  }

  /// Serializes feature history to JSON.
  static String serializeHistory(List<CADHistoryItem> history) {
    return CADSerializer.serializeHistory(history);
  }

  /// Deserializes feature history from JSON.
  static List<CADHistoryItem> deserializeHistory(String jsonStr) {
    return CADSerializer.deserializeHistory(jsonStr);
  }

  /// Exports mesh buffers to ASCII STL.
  static String exportToAsciiStl({
    required Float32List vertices,
    required Uint16List indices,
    required String modelName,
    int stride = 6,
  }) {
    return CADSTLExporter.exportToASCIISTL(
      vertices: vertices,
      indices: indices,
      name: modelName,
      stride: stride,
    );
  }

  /// Resolves any primitive entity or host part face B-Rep border/hole into 2D line or point geometry.
  static CadEntityGeometryRef? resolveEntityGeometry(
    String rawId,
    CADSketchPlane plane, {
    AssemblyPart? hostPart,
  }) {
    final baseId = rawId.split(':').first;
    final subKey = rawId.contains(':') ? rawId.split(':').last : null;

    // 1. Check host part B-Rep outer borders and holes
    if (hostPart != null) {
      final brep = CadPlanarFaceBRep.extractFromPartFace(
        part: hostPart,
        planeOriginWorld: plane.origin,
        planeNormalWorld: plane.normal,
        planeUAxisWorld: plane.xAxis,
        planeVAxisWorld: plane.yAxis,
      );
      for (final border in brep.outerBorderEdges2D) {
        if (border.id == baseId || border.id.startsWith(baseId) || baseId.startsWith(border.id)) {
          return CadEntityGeometryRef.line(
            id: border.id,
            start: Offset(border.start2D.x, border.start2D.y),
            end: Offset(border.end2D.x, border.end2D.y),
          );
        }
      }
      for (final hole in brep.holes2D) {
        if (hole.id == baseId || hole.id.startsWith(baseId) || baseId.startsWith(hole.id)) {
          return CadEntityGeometryRef.point(
            id: hole.id,
            center: Offset(hole.center2D.x, hole.center2D.y),
            radius: hole.diameterMm / 2.0,
          );
        }
      }
    }

    // 2. Check primitives on plane
    final prim = plane.primitives.where((p) => p.id == baseId).firstOrNull;
    if (prim == null) return null;

    if (prim is CADLineEntity) {
      return CadEntityGeometryRef.line(id: prim.id, start: prim.start, end: prim.end);
    } else if (prim is CADCircleEntity) {
      return CadEntityGeometryRef.point(id: prim.id, center: prim.center, radius: prim.radius);
    } else if (prim is CADRegularPolygonEntity) {
      return CadEntityGeometryRef.point(id: prim.id, center: prim.center, radius: prim.radius);
    } else if (prim is CADPointEntity) {
      return CadEntityGeometryRef.point(id: prim.id, center: prim.position);
    } else if (prim is CADRectangleEntity) {
      final p1 = prim.startPoint;
      final p2 = Offset(prim.startPoint.dx + prim.width, prim.startPoint.dy);
      final p3 = Offset(prim.startPoint.dx + prim.width, prim.startPoint.dy + prim.height);
      final p4 = Offset(prim.startPoint.dx, prim.startPoint.dy + prim.height);
      if (subKey == 'h' || subKey == 'left') return CadEntityGeometryRef.line(id: '${prim.id}:left', start: p1, end: p4);
      if (subKey == 'right') return CadEntityGeometryRef.line(id: '${prim.id}:right', start: p2, end: p3);
      if (subKey == 'top') return CadEntityGeometryRef.line(id: '${prim.id}:top', start: p4, end: p3);
      return CadEntityGeometryRef.line(id: '${prim.id}:w', start: p1, end: p2);
    } else if (prim is CADCenterRectangleEntity) {
      if (subKey == 'h' || subKey == 'left') return CadEntityGeometryRef.line(id: '${prim.id}:left', start: prim.topLeft, end: prim.bottomLeft);
      if (subKey == 'right') return CadEntityGeometryRef.line(id: '${prim.id}:right', start: prim.topRight, end: prim.bottomRight);
      if (subKey == 'top') return CadEntityGeometryRef.line(id: '${prim.id}:top', start: prim.topLeft, end: prim.topRight);
      return CadEntityGeometryRef.line(id: '${prim.id}:w', start: prim.bottomLeft, end: prim.bottomRight);
    } else if (prim is CADArcEntity) {
      final g = prim.computeCircumcircle();
      return CadEntityGeometryRef.point(id: prim.id, center: g?.center ?? prim.pointOnArc, radius: g?.radius ?? 10.0);
    } else if (prim is CADCenterPointArcEntity) {
      return CadEntityGeometryRef.point(id: prim.id, center: prim.center, radius: prim.radius);
    }
    return null;
  }

  /// Calculates the exact distance or angle between two CAD entity references.
  static ({CadConstraintType type, double value, String unit}) computeTwoEntityDistance(
    CadEntityGeometryRef g1,
    CadEntityGeometryRef g2,
  ) {
    if (g1.isLine && g2.isLine) {
      final d1 = g1.end - g1.start;
      final d2 = g2.end - g2.start;
      final cross = (d1.dx * d2.dy - d1.dy * d2.dx).abs();
      final lenProd = d1.distance * d2.distance;
      if (lenProd > 1e-4 && (cross / lenProd) > 0.08) {
        final dot = (d1.dx * d2.dx + d1.dy * d2.dy) / lenProd;
        final angDeg = math.acos(dot.clamp(-1.0, 1.0)) * 180.0 / math.pi;
        return (type: CadConstraintType.angle, value: (angDeg * 10).roundToDouble() / 10.0, unit: 'deg');
      } else {
        final lLen = d1.distance;
        final n = Offset(-d1.dy / lLen, d1.dx / lLen);
        final dist = ((g2.start.dx - g1.start.dx) * n.dx + (g2.start.dy - g1.start.dy) * n.dy).abs();
        return (type: CadConstraintType.distance, value: (dist * 10).roundToDouble() / 10.0, unit: 'mm');
      }
    } else if (g1.isLine && !g2.isLine) {
      final lVec = g1.end - g1.start;
      final lLen = lVec.distance;
      final unitN = Offset(-lVec.dy / lLen, lVec.dx / lLen);
      final dist = ((g2.center.dx - g1.start.dx) * unitN.dx + (g2.center.dy - g1.start.dy) * unitN.dy).abs();
      return (type: CadConstraintType.distance, value: (dist * 10).roundToDouble() / 10.0, unit: 'mm');
    } else if (!g1.isLine && g2.isLine) {
      final lVec = g2.end - g2.start;
      final lLen = lVec.distance;
      final unitN = Offset(-lVec.dy / lLen, lVec.dx / lLen);
      final dist = ((g1.center.dx - g2.start.dx) * unitN.dx + (g1.center.dy - g2.start.dy) * unitN.dy).abs();
      return (type: CadConstraintType.distance, value: (dist * 10).roundToDouble() / 10.0, unit: 'mm');
    } else {
      final dist = (g2.center - g1.center).distance;
      return (type: CadConstraintType.distance, value: (dist * 10).roundToDouble() / 10.0, unit: 'mm');
    }
  }
}

class CadEntityGeometryRef {
  final String id;
  final bool isLine;
  final Offset start;
  final Offset end;
  final Offset center;
  final double radius;

  CadEntityGeometryRef.line({
    required this.id,
    required this.start,
    required this.end,
  })  : isLine = true,
        center = (start + end) * 0.5,
        radius = 0.0;

  CadEntityGeometryRef.point({
    required this.id,
    required this.center,
    this.radius = 0.0,
  })  : isLine = false,
        start = center,
        end = center;
}
