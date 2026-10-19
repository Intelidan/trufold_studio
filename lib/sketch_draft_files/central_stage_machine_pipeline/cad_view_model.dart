import 'package:flutter/material.dart';
import '../../sheet_metal_studio/engine/cad_brep_flutter_gpu_scene.dart' hide Material;

import '../cad_parameter_engine/cad_models.dart';
import '../math_and_processing/cad_constraint_solvers.dart';
import '../math_and_processing/cad_grid_solver.dart';
import '../math_and_processing/cad_intersection_solver.dart';
import '../math_and_processing/cad_profile_validator.dart';

class FullyLoadedCADViewModel extends ChangeNotifier {
  final Scene scene = Scene();
  final CADGridSolver gridSolver = CADGridSolver(gridSpacing: 0.1);

  List<CADHistoryItem> commandHistoryList = [];
  List<CADLineSegment> currentSketchSegments = [];
  List<GeometricConstraint> constraintsRegistry = [];

  CADSketchPlane? currentActivePlane;
  ValidationResult? activeValidationStatus;
  bool isFeatureExecutable = false;

  void executeParametricMeshRebuild() {
    enforceAppliedConstraintsLoop();
    currentSketchSegments = CADIntersectionSolver.computeSplits(currentSketchSegments);
    activeValidationStatus = CADProfileValidator.validateProfile(currentSketchSegments);
    isFeatureExecutable = activeValidationStatus?.isValidClosedLoop ?? false;
    notifyListeners();
  }

  void enforceAppliedConstraintsLoop() {
    for (var constraint in constraintsRegistry) {
      if (constraint.type == CADConstraintType.perpendicular) {
        final anchor = currentSketchSegments.firstWhere((s) => s.id == constraint.secondarySegmentId, orElse: () => null as dynamic);
        final target = currentSketchSegments.firstWhere((s) => s.id == constraint.primarySegmentId, orElse: () => null as dynamic);
        CADPerpendicularSolver.resolvePerpendicular(anchorSegment: anchor, targetSegment: target);
      }
    }
  }
}
