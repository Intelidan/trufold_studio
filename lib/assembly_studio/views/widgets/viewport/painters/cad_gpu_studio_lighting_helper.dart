import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

class CadGpuStudioLightingHelper {
  /// Evaluates Onshape-grade camera-locked studio shading + specular highlight.
  /// Guarantees a minimum luminance floor of 0.48 so opposite faces NEVER appear dark.
  static Color shadeCadSurface({
    required Color baseAlbedo,
    required Vector3 worldNormal,
    required Vector3 cameraPosition,
    required Vector3 surfaceWorldPoint,
    required Vector3 cameraUp,
    double metallicSpecular = 0.28,
    double shininess = 28.0,
  }) {
    Vector3 n = worldNormal.normalized();
    final Vector3 v = (cameraPosition - surfaceWorldPoint).normalized();

    // 1. Two-Sided Normal Guard: Flip normals pointing away from the camera
    // so back-faces, inner C-channel webs, and boolean cut walls are always lit.
    if (n.dot(v) < 0.0) {
      n = -n;
    }

    // 2. Construct Camera-Space Orthonormal Basis (Right, Up, Forward)
    Vector3 camRight = v.cross(cameraUp);
    if (camRight.length2 < 1e-5) {
      camRight = Vector3(1.0, 0.0, 0.0);
    } else {
      camRight.normalize();
    }
    final Vector3 camTrueUp = camRight.cross(v).normalized();

    // 3. Camera-Locked Studio Lights (Moves with user's eye like Onshape/SolidWorks)
    final Vector3 keyLightDir = (v * 0.55 + camRight * 0.45 + camTrueUp * 0.65).normalized();
    final Vector3 fillLightDir = (v * 0.40 - camRight * 0.65 - camTrueUp * 0.35).normalized();
    final Vector3 rimLightDir = (-v * 0.25 + camTrueUp * 0.85).normalized();

    // Half-Lambert wrap (dot * 0.5 + 0.5) prevents harsh black shadow terminators
    final double keyDiffuse = n.dot(keyLightDir) * 0.5 + 0.5;
    final double fillDiffuse = math.max(0.0, n.dot(fillLightDir));
    final double headlight = math.max(0.0, n.dot(v));
    final double rim = math.pow(1.0 - math.max(0.0, n.dot(v)), 3.0).toDouble() *
        math.max(0.0, n.dot(rimLightDir));

    // Blinn-Phong Specular Shine for metallic CAD aesthetic
    final Vector3 halfVec = (keyLightDir + v).normalized();
    final double specAngle = math.max(0.0, n.dot(halfVec));
    final double specular = math.pow(specAngle, shininess).toDouble() * metallicSpecular;

    // Combine with a 0.48 minimum floor so dark blue steel never crushes to black
    final double diffuseFactor = (0.36 +
            keyDiffuse * 0.38 +
            fillDiffuse * 0.16 +
            headlight * 0.14 +
            rim * 0.08)
        .clamp(0.48, 1.06);

    final a = (baseAlbedo.a * 255.0).round().clamp(0, 255);
    final r = (baseAlbedo.r * 255.0 * diffuseFactor + 255.0 * specular).round().clamp(0, 255);
    final g = (baseAlbedo.g * 255.0 * diffuseFactor + 255.0 * specular).round().clamp(0, 255);
    final b = (baseAlbedo.b * 255.0 * diffuseFactor + 255.0 * specular).round().clamp(0, 255);

    return Color.fromARGB(a, r, g, b);
  }
}
