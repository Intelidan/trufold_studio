// =============================================================================
// matrix4_math_helper.dart
//
// Standalone 3D Transformation Matrix & Rodrigues Rotation Math Helper.
// Performs 4x4 matrix multiplications and arbitrary-axis spatial rotations
// with zero external dependencies.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';

/// Row-major 4x4 Transformation Matrix
class TransformMatrix4 {
  final List<double> m; // 16 entries

  const TransformMatrix4._(this.m);

  /// Identity matrix
  factory TransformMatrix4.identity() {
    return TransformMatrix4._([
      1.0, 0.0, 0.0, 0.0,
      0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0,
    ]);
  }

  /// Translation matrix
  factory TransformMatrix4.translation(double tx, double ty, double tz) {
    return TransformMatrix4._([
      1.0, 0.0, 0.0, tx,
      0.0, 1.0, 0.0, ty,
      0.0, 0.0, 1.0, tz,
      0.0, 0.0, 0.0, 1.0,
    ]);
  }

  /// Rodrigues' 3D rotation matrix around arbitrary axis `u` passing through origin
  factory TransformMatrix4.rotationAxis(CadPoint3D axis, double angleRad) {
    final u = axis.normalized();
    final c = math.cos(angleRad);
    final s = math.sin(angleRad);
    final t = 1.0 - c;

    final x = u.x;
    final y = u.y;
    final z = u.z;

    return TransformMatrix4._([
      t * x * x + c,     t * x * y - s * z, t * x * z + s * y, 0.0,
      t * x * y + s * z, t * y * y + c,     t * y * z - s * x, 0.0,
      t * x * z - s * y, t * y * z + s * x, t * z * z + c,     0.0,
      0.0,               0.0,               0.0,               1.0,
    ]);
  }

  /// Rotation around arbitrary 3D line passing through `p0` with direction `axis`
  factory TransformMatrix4.rotationAroundLine(CadPoint3D p0, CadPoint3D axis, double angleRad) {
    // Translate p0 to origin -> Rotate -> Translate back
    final t1 = TransformMatrix4.translation(-p0.x, -p0.y, -p0.z);
    final r = TransformMatrix4.rotationAxis(axis, angleRad);
    final t2 = TransformMatrix4.translation(p0.x, p0.y, p0.z);

    return t2.multiply(r).multiply(t1);
  }

  /// Multiplies this matrix with another: Result = this * other
  TransformMatrix4 multiply(TransformMatrix4 other) {
    final res = List<double>.filled(16, 0.0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += m[row * 4 + k] * other.m[k * 4 + col];
        }
        res[row * 4 + col] = sum;
      }
    }
    return TransformMatrix4._(res);
  }

  /// Transforms a 3D point: [x', y', z', 1]^T = M * [x, y, z, 1]^T
  CadPoint3D transformPoint(CadPoint3D p) {
    final x = m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3];
    final y = m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7];
    final z = m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11];
    final w = m[12] * p.x + m[13] * p.y + m[14] * p.z + m[15];

    if (w != 1.0 && w.abs() > 1e-6) {
      return CadPoint3D(x / w, y / w, z / w);
    }
    return CadPoint3D(x, y, z);
  }

  /// Transforms a 3D direction / normal vector (ignores translation component)
  CadPoint3D transformVector(CadPoint3D v) {
    final x = m[0] * v.x + m[1] * v.y + m[2] * v.z;
    final y = m[4] * v.x + m[5] * v.y + m[6] * v.z;
    final z = m[8] * v.x + m[9] * v.y + m[10] * v.z;
    final len = math.sqrt(x * x + y * y + z * z);
    if (len < 1e-6) return const CadPoint3D(0, 0, 1);
    return CadPoint3D(x / len, y / len, z / len);
  }
}
