// 
// 2. 🧮 Pure Geometric Math & Processing Sub-routines
// cad_raycaster.dart
// Converts 2D mouse touches to 3D infinite ray vectors and implements the Möller–Trumbore intersection algorithm across indexed raw float buffers.


import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

class CADIntersectionResult {
  final vm.Vector3 point;
  final vm.Vector3 normal;
  final int faceIndex;
  final double distance;
  CADIntersectionResult({required this.point, required this.normal, required this.faceIndex, required this.distance});
}

class CADRaycaster {
  static vm.Ray computeScreenRay(Offset touch, Size viewportSize, vm.Matrix4 viewMatrix, vm.Matrix4 projectionMatrix) {
    final double ndcX = (touch.dx / viewportSize.width) * 2.0 - 1.0;
    final double ndcY = 1.0 - (touch.dy / viewportSize.height) * 2.0;
    final vm.Matrix4 invVP = (projectionMatrix * viewMatrix)..invert();

    final vm.Vector4 nearPointNDC = vm.Vector4(ndcX, ndcY, -1.0, 1.0);
    final vm.Vector4 farPointNDC = vm.Vector4(ndcX, ndcY, 1.0, 1.0);
    final vm.Vector4 nearWorld4 = invVP * nearPointNDC;
    final vm.Vector4 farWorld4 = invVP * farPointNDC;

    return vm.Ray.originDirection(
      vm.Vector3(nearWorld4.x / nearWorld4.w, nearWorld4.y / nearWorld4.w, nearWorld4.z / nearWorld4.w),
      (vm.Vector3(farWorld4.x / farWorld4.w, farWorld4.y / farWorld4.w, farWorld4.z / farWorld4.w) -
              vm.Vector3(nearWorld4.x / nearWorld4.w, nearWorld4.y / nearWorld4.w, nearWorld4.z / nearWorld4.w))
          .normalized(),
    );
  }

  static CADIntersectionResult? raycastMesh(vm.Ray ray, Float32List vertices, Uint16List indices, int stride) {
    CADIntersectionResult? closestHit;
    double minDistance = double.infinity;

    for (int i = 0; i < indices.length; i += 3) {
      int idx0 = indices[i] * stride;
      int idx1 = indices[i + 1] * stride;
      int idx2 = indices[i + 2] * stride;
      final v0 = vm.Vector3(vertices[idx0], vertices[idx0 + 1], vertices[idx0 + 2]);
      final v1 = vm.Vector3(vertices[idx1], vertices[idx1 + 1], vertices[idx1 + 2]);
      final v2 = vm.Vector3(vertices[idx2], vertices[idx2 + 1], vertices[idx2 + 2]);

      final edge1 = v1 - v0;
      final edge2 = v2 - v0;
      final h = ray.direction.cross(edge2);
      double a = edge1.dot(h);
      if (a.abs() < 0.00001) continue;

      double f = 1.0 / a;
      vm.Vector3 s = ray.origin - v0;
      double u = f * s.dot(h);
      if (u < 0.0 || u > 1.0) continue;
      final q = s.cross(edge1);
      double v = f * ray.direction.dot(q);
      if (v < 0.0 || u + v > 1.0) continue;

      double t = f * edge2.dot(q);
      if (t > 0.00001 && t < minDistance) {
        minDistance = t;
        closestHit = CADIntersectionResult(point: ray.origin + (ray.direction * t), normal: edge1.cross(edge2).normalized(), faceIndex: i ~/ 3, distance: t);
      }
    }
    return closestHit;
  }
}
