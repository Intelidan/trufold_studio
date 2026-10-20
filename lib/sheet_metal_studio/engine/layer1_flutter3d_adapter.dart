import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/cad_primitives.dart';
import 'cad_brep_flutter_gpu_scene.dart';
import 'layer1_three_js_adapter.dart';

/// Layer 1 Option C: `flutter3d` Retained GPU + Path B Hierarchical B-Rep Adapter.
///
/// Implements the three structural Path B fixes:
/// 1. **Strict Back-Face Culling:** Checks both 3D view-space normal (`viewDot <= 1e-4`)
///    and 2D screen-space triangle winding relative to the camera (`cross2D <= 0.01`).
/// 2. **Hierarchical Assembly Depth Ordering:** Orders drawing by Assembly Parts and B-Rep Facets:
///    $$\text{Rear Rail} \longrightarrow \text{Cross Rungs \& Welds} \longrightarrow \text{Front Rail}$$
///    The Front Rail is drawn in its own final pass with solid opaque fills, physically preventing
///    background rungs from painting over it.
/// 3. **Dedicated Crease Pass Per Part:** Draws each part's/facet's `1.70px` Deep-Indigo (`#1E1B4B`)
///    technical ink borders immediately with that part's faces so foreground parts occlude background wireframes.
/// 4. **Distinct Flutter3D Shading:** Always-on **3-Band Stepped Cel/Toon** diffuse tones (`0.50`, `0.84`, `1.14`),
///    Cook-Torrance GGX microfacet specular band, and **Indigo/Cyan Schlick Fresnel grazing rim sheen**.
class Layer1Flutter3dAdapter {
  static double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  /// Renders the active `CadBRepModelData` using Path B Hierarchical Assembly Ordering
  /// and `flutter3d`'s 3-Band Cel/Toon + Cook-Torrance GGX PBR + Indigo Fresnel rim shader.
  static void renderFlutter3dPass({
    required Canvas canvas,
    required Size size,
    required Scene scene,
    required CadBRepModelData model,
    required ThreeJsRetainedBufferGeometry buffers,
  }) {
    if (buffers.compiledFacets.isEmpty) return;

    final m = scene.rotationMatrix;
    final prefs = model.preferences;
    final bool isGlobalTranslucent = model.renderMode == OnshapeRenderMode.translucent;
    final bool isWireframeOnly = model.renderMode == OnshapeRenderMode.unshaded;
    final bool shouldDrawWireframe =
        model.showWireframe && model.renderMode != OnshapeRenderMode.shadedWithoutEdges && prefs.lineWidth > 0.05;

    final double camDist = scene.effectiveFitDim * 3.8;
    final double eyeX = m[8] * camDist;
    final double eyeY = m[9] * camDist;
    final double eyeZ = m[10] * camDist;

    // 1. Build Path B Hierarchical Assembly Draw Queue (Rear Rail -> Cross Rungs -> Front Rail)
    final drawQueue = Layer1ThreeJsAdapter.buildHierarchicalAssemblyFacetQueue(
      buffers: buffers,
      scene: scene,
      size: size,
      eyeX: eyeX,
      eyeY: eyeY,
      eyeZ: eyeZ,
      isOrtho: scene.isOrtho,
      isGlobalTranslucent: isGlobalTranslucent,
    );

    // 2. Flutter3D Cook-Torrance GGX + 3-Band Cel/Toon Uniforms
    final shininessRatio = (prefs.shininess / 100.0).clamp(0.0, 1.0);
    final double roughness = (0.52 - shininessRatio * 0.36).clamp(0.14, 0.65);
    final double alpha2 = math.pow(roughness, 4).toDouble();

    const double keyLx = -0.38, keyLy = 0.46, keyLz = 0.80;

    final triPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final faceFillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Flutter3D signature Deep-Indigo (`#1E1B4B`) technical illustration ink outline pass
    final boundaryColor = prefs.highlightBoundaryEdges
        ? prefs.boundaryEdgeColor
        : const Color(0xFF1E1B4B);
    final creasePaint = Paint()
      ..color = isGlobalTranslucent ? boundaryColor.withValues(alpha: 0.60) : boundaryColor.withValues(alpha: 0.96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (prefs.lineWidth * 1.25).clamp(1.35, 2.8)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // 3. Execute Hierarchical Pass: Solid Face Fill + GPU Vertex Cel/Toon/GGX Pass + Dedicated Crease Pass Per Facet
    for (final pf in drawQueue) {
      final cf = pf.compiledFacet;
      final facet = pf.facet;

      if (!isWireframeOnly) {
        final pos3D = cf.positions3D;
        final norm3D = cf.normals3D;
        final baseColors = cf.baseColors;
        final int vertCount = pos3D.length ~/ 3;
        final shadedColors = Int32List(vertCount);

        double sumR = 0.0, sumG = 0.0, sumB = 0.0;
        final int targetAlpha = (isGlobalTranslucent || facet.isTranslucent) ? 110 : 255;

        for (int v = 0; v < vertCount; v++) {
          final int i3 = v * 3;
          final double px = pos3D[i3];
          final double py = pos3D[i3 + 1];
          final double pz = pos3D[i3 + 2];

          final double nx = norm3D[i3];
          final double ny = norm3D[i3 + 1];
          final double nz = norm3D[i3 + 2];

          double vnx = nx * m[0] + ny * m[1] + nz * m[2];
          double vny = nx * m[4] + ny * m[5] + nz * m[6];
          double vnz = nx * m[8] + ny * m[9] + nz * m[10];
          if (vnz < 0.0) {
            vnx = -vnx;
            vny = -vny;
            vnz = -vnz;
          }

          // Spatial view vector in camera space for Cel/Toon step bands & grazing Fresnel rim
          final double vCamX = px * m[0] + py * m[1] + pz * m[2];
          final double vCamY = px * m[4] + py * m[5] + pz * m[6];
          final double vCamZ = px * m[8] + py * m[9] + pz * m[10];
          final double dxCam = -vCamX * 0.0018;
          final double dyCam = -vCamY * 0.0018;
          final double dzCam = camDist - vCamZ * 0.0018;
          final double invVLen = 1.0 / math.sqrt(dxCam * dxCam + dyCam * dyCam + dzCam * dzCam);
          final double vx = dxCam * invVLen;
          final double vy = dyCam * invVLen;
          final double vz = dzCam * invVLen;

          final double hx = keyLx + vx;
          final double hy = keyLy + vy;
          final double hz = keyLz + vz;
          final double invHLen = 1.0 / math.sqrt(hx * hx + hy * hy + hz * hz);

          final double ndotl = (vnx * keyLx + vny * keyLy + vnz * keyLz).clamp(0.0, 1.0);
          final double wrapKey = ((vnx * keyLx + vny * keyLy + vnz * keyLz + 0.28) / 1.28).clamp(0.0, 1.0);
          final double ndoth = ((vnx * hx + vny * hy + vnz * hz) * invHLen).clamp(0.0, 1.0);
          final double ndotv = (vnx * vx + vny * vy + vnz * vz).clamp(0.001, 1.0);

          // 3-Band Stepped Cel/Toon Quantization (Shadow: 0.50 -> Midtone: 0.84 -> Key-Lit: 1.14)
          final double band1 = _smoothstep(0.28, 0.33, wrapKey);
          final double band2 = _smoothstep(0.66, 0.71, wrapKey);
          final double celTone = 0.50 + band1 * 0.34 + band2 * 0.30;

          // Stepped Cook-Torrance GGX Microfacet Specular Highlight Band
          final double denom = (ndoth * ndoth * (alpha2 - 1.0) + 1.0);
          final double dGgx = alpha2 / math.max(math.pi * denom * denom, 0.001);
          final double rawSpec = (dGgx * ndotl * 0.075).clamp(0.0, 0.50);
          final double steppedSpec = _smoothstep(0.14, 0.22, rawSpec) * 0.28;

          // Schlick Fresnel grazing rim sheen (Indigo/Cyan technical highlight at grazing angles)
          final double fresnelRim = math.pow(1.0 - ndotv, 3.0).toDouble() * 0.24;

          final int raw = baseColors[v];
          final int r0 = (raw >> 16) & 0xFF;
          final int g0 = (raw >> 8) & 0xFF;
          final int b0 = raw & 0xFF;

          final int rOut = (r0 * celTone * 0.96 + steppedSpec * 235.0 + fresnelRim * 115.0).round().clamp(0, 255);
          final int gOut = (g0 * celTone * 0.98 + steppedSpec * 242.0 + fresnelRim * 150.0).round().clamp(0, 255);
          final int bOut = (b0 * celTone * 1.05 + steppedSpec * 255.0 + fresnelRim * 255.0).round().clamp(0, 255);

          sumR += rOut;
          sumG += gOut;
          sumB += bOut;
          shadedColors[v] = (targetAlpha << 24) | (rOut << 16) | (gOut << 8) | bOut;
        }

        // Solid opaque base fill (`PathFillType.evenOdd`) seals sub-pixel seams and ensures
        // the Front Rail physically blocks 100% of background rungs and wireframes behind it!
        final double invVert = 1.0 / vertCount;
        faceFillPaint.color = Color.fromARGB(
          targetAlpha,
          (sumR * invVert).round().clamp(0, 255),
          (sumG * invVert).round().clamp(0, 255),
          (sumB * invVert).round().clamp(0, 255),
        );
        canvas.drawPath(pf.fillPath, faceFillPaint);

        // Hardware GPU vertex shading pass (`ui.Vertices.raw`) for Cel/Toon + GGX + Fresnel gradients
        final gpuVertices = ui.Vertices.raw(
          ui.VertexMode.triangles,
          pf.screenPositions,
          colors: shadedColors,
          indices: pf.culledIndices,
        );
        canvas.drawVertices(gpuVertices, BlendMode.srcOver, triPaint);
      } else {
        faceFillPaint.color = const Color(0xFFF8FAFC);
        canvas.drawPath(pf.fillPath, faceFillPaint);
      }

      // Path B Fix #3: Dedicated Crease Pass Immediately Per Facet/Part
      if (shouldDrawWireframe) {
        if (pf.strokePath != null) {
          canvas.drawPath(pf.strokePath!, creasePaint);
        }
        if (pf.holesStrokePath != null) {
          canvas.drawPath(pf.holesStrokePath!, creasePaint);
        }
      }
    }

    Scene.drawEngineHudWatermark(
      canvas,
      size,
      'Layer 1C: flutter3d (Path B Hierarchical B-Rep · GGX + 3-Band Cel/Toon)',
      const Color(0xFF6366F1),
    );
  }
}
