//
// cad_grid_solver.dart

// Performs projection coordinate translations between world space and local drawing grids with step-rounding.

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

class CADGridSolver {
  final double gridSpacing;
  CADGridSolver({this.gridSpacing = 0.05});

  Offset projectWorldToLocalPlane(vm.Vector3 worldPoint, vm.Vector3 planeOrigin, vm.Vector3 planeNormal, vm.Vector3 planeUp) {
    final vm.Vector3 zAxis = planeNormal.normalized();
    final vm.Vector3 yAxis = planeUp.normalized();
    final vm.Vector3 xAxis = yAxis.cross(zAxis).normalized();
    final vm.Vector3 localDelta = worldPoint - planeOrigin;
    return Offset(localDelta.dot(xAxis), localDelta.dot(yAxis));
  }

  Offset snapToGrid(Offset rawLocalPos) {
    return Offset((rawLocalPos.dx / gridSpacing).round() * gridSpacing, (rawLocalPos.dy / gridSpacing).round() * gridSpacing);
  }

  vm.Vector3 projectLocalPlaneToWorld(Offset snappedLocalPos, vm.Vector3 planeOrigin, vm.Vector3 planeNormal, vm.Vector3 planeUp) {
    final vm.Vector3 zAxis = planeNormal.normalized();
    final vm.Vector3 yAxis = planeUp.normalized();
    return planeOrigin + (yAxis.cross(zAxis).normalized() * snappedLocalPos.dx) + (yAxis * snappedLocalPos.dy);
  }
}
