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

    // Compute robust up vector tangent to face
    vm.Vector3 tentativeUp = vm.Vector3(0.0, 1.0, 0.0);
    if (normal.dot(tentativeUp).abs() > 0.85) {
      tentativeUp = vm.Vector3(0.0, 0.0, 1.0);
      if (normal.dot(tentativeUp).abs() > 0.85) {
        tentativeUp = vm.Vector3(1.0, 0.0, 0.0);
      }
    }
    final up = (tentativeUp - normal * normal.dot(tentativeUp)).normalized();

    return CADSketchPlane(
      id: 'plane_${polygon.faceId}',
      origin: origin,
      normal: normal,
      up: up,
      targetPartId: partId,
      targetFaceId: polygon.faceId,
    );
  }

  /// Constructs a standard datum sketch plane (XY, XZ, or YZ).
  static CADSketchPlane createDatumPlane(String type, {vm.Vector3? customOrigin}) {
    final ori = customOrigin ?? vm.Vector3(0.0, 0.0, 0.0);
    switch (type.toUpperCase()) {
      case 'XZ':
        return CADSketchPlane(
          id: 'datum_XZ',
          origin: ori,
          normal: vm.Vector3(0.0, 1.0, 0.0),
          up: vm.Vector3(0.0, 0.0, 1.0),
        );
      case 'YZ':
        return CADSketchPlane(
          id: 'datum_YZ',
          origin: ori,
          normal: vm.Vector3(1.0, 0.0, 0.0),
          up: vm.Vector3(0.0, 1.0, 0.0),
        );
      case 'XY':
      default:
        return CADSketchPlane(
          id: 'datum_XY',
          origin: ori,
          normal: vm.Vector3(0.0, 0.0, 1.0),
          up: vm.Vector3(0.0, 1.0, 0.0),
        );
    }
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
  static List<CADLineSegment> compilePlaneSegments(CADSketchPlane plane) {
    final segments = <CADLineSegment>[...plane.entities];
    for (final prim in plane.primitives) {
      segments.addAll(prim.toLineSegments());
    }
    return segments;
  }

  /// Validates closed-loop integrity of active entities on the plane.
  static ValidationResult validatePlaneLoop(CADSketchPlane plane) {
    final segments = compilePlaneSegments(plane);
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
}
