// Rotation Mathematical Engine & Plane Intersections
// Modularized for TruFold MVVM Architecture

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

class AssemblyRotateMathHelper {
  /// Ray-to-plane intersection
  static CadPoint3D intersectPlane({
    required Offset screenPos,
    required Size size,
    required FoldedMeshResult mesh,
    required GizmoAxis axis,
    required CadPoint3D planeOrigin,
    required (vm_math.Vector3, vm_math.Vector3) Function(Offset screenPos, Size size, FoldedMeshResult mesh) getRay,
  }) {
    final (rayOrigin, rayDir) = getRay(screenPos, size, mesh);
    final vm_math.Vector3 normal;
    if (axis == GizmoAxis.x) {
      normal = vm_math.Vector3(1.0, 0.0, 0.0);
    } else if (axis == GizmoAxis.y) {
      normal = vm_math.Vector3(0.0, 1.0, 0.0);
    } else {
      normal = vm_math.Vector3(0.0, 0.0, 1.0);
    }

    final denom = rayDir.dot(normal);
    if (denom.abs() > 1e-5) {
      final diff = vm_math.Vector3(
        planeOrigin.x - rayOrigin.x,
        planeOrigin.y - rayOrigin.y,
        planeOrigin.z - rayOrigin.z,
      );
      final t = diff.dot(normal) / denom;
      if (t > 0) {
        final hit = rayOrigin + rayDir * t;
        return CadPoint3D(hit.x, hit.y, hit.z);
      }
    }
    return planeOrigin;
  }

  /// Computes signed rotation angle around the given primary axis
  static double calculateSignedAngleDeg({
    required CadPoint3D center,
    required CadPoint3D baselinePt,
    required CadPoint3D currentPt,
    required GizmoAxis axis,
  }) {
    double u1x, u1y, u2x, u2y;
    if (axis == GizmoAxis.x) {
      u1x = baselinePt.y - center.y;
      u1y = baselinePt.z - center.z;
      u2x = currentPt.y - center.y;
      u2y = currentPt.z - center.z;
    } else if (axis == GizmoAxis.y) {
      u1x = baselinePt.z - center.z;
      u1y = baselinePt.x - center.x;
      u2x = currentPt.z - center.z;
      u2y = currentPt.x - center.x;
    } else {
      u1x = baselinePt.x - center.x;
      u1y = baselinePt.y - center.y;
      u2x = currentPt.x - center.x;
      u2y = currentPt.y - center.y;
    }

    final len1 = math.sqrt(u1x * u1x + u1y * u1y);
    final len2 = math.sqrt(u2x * u2x + u2y * u2y);
    if (len1 < 1e-4 || len2 < 1e-4) return 0.0;

    final n1x = u1x / len1;
    final n1y = u1y / len1;
    final n2x = u2x / len2;
    final n2y = u2y / len2;

    final dot = (n1x * n2x + n1y * n2y).clamp(-1.0, 1.0);
    final cross = n1x * n2y - n1y * n2x;
    return math.atan2(cross, dot) * 180.0 / math.pi;
  }

  /// Calculates protractor screen radius
  static double computeProtractorScreenRadius({
    required CadPoint3D center,
    required GizmoAxis axis,
    required Size size,
    required FoldedMeshResult mesh,
    required Offset Function(CadPoint3D pt) projectPoint,
  }) {
    final centerScreen = projectPoint(center);
    final CadPoint3D testOffset;
    if (axis == GizmoAxis.x) {
      testOffset = CadPoint3D(center.x, center.y + 100.0, center.z);
    } else if (axis == GizmoAxis.y) {
      testOffset = CadPoint3D(center.x, center.y, center.z + 100.0);
    } else {
      testOffset = CadPoint3D(center.x + 100.0, center.y, center.z);
    }
    final screenTest = projectPoint(testOffset);
    final dScreen = (screenTest - centerScreen).distance;
    return dScreen > 5.0 ? dScreen : 100.0;
  }

  /// 15° Snapping when near protractor ring
  static double snapRotateAngle({
    required double rawAngleDeg,
    required Offset cursorScreen,
    required Offset centerScreen,
    required double screenRadius,
    required bool snapToGrid,
  }) {
    final dist = (cursorScreen - centerScreen).distance;
    final isNearRing = dist < screenRadius * 1.4;
    if (snapToGrid && isNearRing) {
      return (rawAngleDeg / 15.0).round() * 15.0;
    } else {
      return (rawAngleDeg * 10.0).round() / 10.0;
    }
  }

  /// Transforms position and rotation around center point
  static (CadPoint3D, CadPoint3D) computeRotatedTransform({
    required CadPoint3D startPos,
    required CadPoint3D startRot,
    required CadPoint3D centerPoint,
    required GizmoAxis axis,
    required double angleDeg,
  }) {
    final rad = angleDeg * math.pi / 180.0;
    final dist = math.sqrt(
      math.pow(startPos.x - centerPoint.x, 2) +
          math.pow(startPos.y - centerPoint.y, 2) +
          math.pow(startPos.z - centerPoint.z, 2),
    );
    CadPoint3D newPos = startPos;
    CadPoint3D newRot = startRot;

    if (axis == GizmoAxis.x) {
      if (dist > 1.0) {
        final dy = startPos.y - centerPoint.y;
        final dz = startPos.z - centerPoint.z;
        final ry = centerPoint.y + (dy * math.cos(rad) - dz * math.sin(rad));
        final rz = centerPoint.z + (dy * math.sin(rad) + dz * math.cos(rad));
        newPos = CadPoint3D(startPos.x, ry, rz);
      }
      newRot = CadPoint3D((startRot.x + angleDeg) % 360.0, startRot.y, startRot.z);
    } else if (axis == GizmoAxis.y) {
      if (dist > 1.0) {
        final dz = startPos.z - centerPoint.z;
        final dx = startPos.x - centerPoint.x;
        final rz = centerPoint.z + (dz * math.cos(rad) - dx * math.sin(rad));
        final rx = centerPoint.x + (dz * math.sin(rad) + dx * math.cos(rad));
        newPos = CadPoint3D(rx, startPos.y, rz);
      }
      newRot = CadPoint3D(startRot.x, (startRot.y + angleDeg) % 360.0, startRot.z);
    } else {
      if (dist > 1.0) {
        final dx = startPos.x - centerPoint.x;
        final dy = startPos.y - centerPoint.y;
        final rx = centerPoint.x + (dx * math.cos(rad) - dy * math.sin(rad));
        final ry = centerPoint.y + (dx * math.sin(rad) + dy * math.cos(rad));
        newPos = CadPoint3D(rx, ry, startPos.z);
      }
      newRot = CadPoint3D(startRot.x, startRot.y, (startRot.z + angleDeg) % 360.0);
    }

    return (newPos, newRot);
  }
}
