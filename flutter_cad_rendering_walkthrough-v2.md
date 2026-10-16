# Onshape-Grade 3D CAD Rendering in Flutter (`flutter_scene` & Flutter GPU)
**Coding Agent Implementation Walkthrough & Architecture Guide (v2.0)**

---

## 1. Executive Summary & Architectural Goals
This specification defines the complete rendering, procedural geometry, and camera interaction pipeline required to achieve **Onshape-quality 3D CAD visualization** in Flutter using `flutter_scene` / Flutter GPU (Impeller).

### Target Visual & Performance Benchmarks:
1. **Concentrated Specular Shine:** Camera-locked "headlight" shading producing crisp specular bands along curved fillets and subtle gradients across flat walls, with **zero shadow-map overhead**.
2. **Seamless Antialiased Black Borders:** Continuous `1.25px–1.5px` topological feature edges with 3D mitered joins (no corner gaps), analytical `fwidth()` screen-space antialiasing, and clip-space depth bias (`z-bias`) to eliminate Z-fighting against coplanar surfaces.
3. **High-Resolution Curves & Split Normals:** Adaptive chordal tessellation (`32–96` segments per hole/arc) and strict vertex normal separation between flat plates, cylindrical bores, and smooth radial fillets.
4. **Planar Face Triangulation with Interior Holes:** Full Dart **2D Earcut Polygon Triangulator** (supporting outer boundaries + arbitrary high-resolution circular hole cutouts) projected into 3D space.
5. **Locked 60/120 FPS Orbiting & Panning:** Zero `setState()` calls during pointer gestures; static GPU vertex buffer caching with single 4×4 `ViewProjection` uniform updates per frame.

---

## 2. Phase 1: Lighting & Concentrated Shine (The CAD "Headlight")

### Why Spotlights Should Not Be Used for CAD Viewports
* **World-Space Lights Fail Inspection:** Scene-fixed spotlights leave parts of the model in darkness when the user orbits to the back side.
* **Shadow Maps Kill Mobile Frame Rates:** Dynamic shadow passes double geometry draw calls. CAD models rely on topological black edge borders—not shadows—for depth perception.

### Solution A: View-Space Blinn-Phong "Headlight" Shader (Recommended)
Lock a primary key light and a secondary studio fill light directly to **Camera View Space**. As the user rotates the part, the concentrated white specular reflection remains anchored relative to the viewer.

#### `shaders/cad_surface.vert`
```glsl
#version 460 core

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;

uniform mat4 u_modelViewMatrix;
uniform mat4 u_projectionMatrix;
uniform mat3 u_normalMatrix; // inverse transpose of mat3(u_modelViewMatrix)

layout(location = 0) out vec3 v_viewNormal;
layout(location = 1) out vec3 v_viewPos;

void main() {
  vec4 viewPos4 = u_modelViewMatrix * vec4(a_position, 1.0);
  v_viewPos = viewPos4.xyz;
  v_viewNormal = normalize(u_normalMatrix * a_normal);
  gl_Position = u_projectionMatrix * viewPos4;
}
```

#### `shaders/cad_surface.frag`
```glsl
#version 460 core

layout(location = 0) in vec3 v_viewNormal;
layout(location = 1) in vec3 v_viewPos;

uniform vec3 u_baseColor; // Default Onshape Blue: vec3(0.47, 0.62, 0.72)

layout(location = 0) out vec4 fragColor;

void main() {
  vec3 N = normalize(v_viewNormal);
  vec3 V = normalize(-v_viewPos); // Points toward the camera in view space

  // Primary key light (angled slightly top-left relative to camera)
  vec3 L1 = normalize(vec3(-0.25, 0.35, 0.90));
  vec3 H1 = normalize(L1 + V);

  // Secondary fill light (bottom-right so back-angled faces never go pitch black)
  vec3 L2 = normalize(vec3(0.40, -0.30, 0.60));

  float diff1 = max(dot(N, L1), 0.0);
  float diff2 = max(dot(N, L2), 0.0) * 0.35;

  // Concentrated Specular Shine (exponent 48.0 creates the tight Onshape highlight stripe)
  float spec = pow(max(dot(N, H1), 0.0), 48.0);

  vec3 ambient   = u_baseColor * 0.35;
  vec3 diffuse   = u_baseColor * (diff1 * 0.65 + diff2);
  vec3 highlight = vec3(1.0) * (spec * 0.55);

  fragColor = vec4(ambient + diffuse + highlight, 1.0);
}
```

### Solution B: Ultra-Cheap MatCap Alternative
If targeting ultra-low-end hardware, replace the lighting math in `cad_surface.frag` with a MatCap lookup or analytical normal mapping:
```glsl
vec3 viewNormal = normalize(v_viewNormal);
vec2 matcapUV = viewNormal.xy * 0.495 + 0.5;
// Either sample a 512x512 MatCap texture or compute direct view-normal specular:
float spec = pow(max(dot(viewNormal, normalize(vec3(-0.2, 0.3, 1.0))), 0.0), 64.0);
```

### Solution C: Native `flutter_scene` PBR Configuration
If using standard `flutter_scene` nodes instead of custom `.fmat` shaders:
1. Create a single `DirectionalLight(castsShadow: false, intensity: 2.5)`.
2. Attach the `DirectionalLight` node as a **child of the `Camera` node** so it moves with the camera.
3. Configure the CAD material with `roughness: 0.25` and `metallic: 0.05`.

---

## 3. Phase 2: Seamless Antialiased Black Borders (CAD Topological Edges)

### Root Causes of Broken Lines in Procedural Meshes:
1. **Corner Gaps:** Extruding line segments independently perpendicular to their own direction creates wedge-shaped gaps at 90° corners and polygon joints.
2. **Z-Fighting (Swallowed Lines):** Drawing black borders at the exact same 3D coordinates as the blue triangle faces causes the GPU depth buffer to randomly clip the lines.
3. **Jagged Edges:** Standard `GL_LINES` lack multi-pixel antialiasing and consistent thickness across DPIs.

### Step 1: Dart 3D Mitered Line Ribbon Generator (`CadEdgeBuilder`)
Generates continuous quad strips where shared vertices compute the normalized bisector (**miter vector**) scaled by `1.0 / dot(miter, normal)` so corners meet seamlessly without gaps.

```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart';

class CadLineMeshData {
  /// Interleaved [posX, posY, posZ, edgeCoord] -> 4 floats per vertex
  /// edgeCoord ranges from -1.0 (left outer edge) to +1.0 (right outer edge)
  final Float32List vertexData;
  final Uint16List indices;
  CadLineMeshData(this.vertexData, this.indices);
}

class CadEdgeBuilder {
  final List<double> _verts = [];
  final List<int> _indices = [];
  int _vertexCount = 0;

  /// Adds a continuous 3D polyline or closed loop with seamless mitered corners.
  void addPolyline(
    List<Vector3> points, {
    required Vector3 surfaceNormal,
    required double worldHalfWidth,
    bool closed = true,
  }) {
    final int n = points.length;
    if (n < 2) return;

    final int startVertexIndex = _vertexCount;

    for (int i = 0; i < n; i++) {
      final Vector3 curr = points[i];
      final Vector3? prev = i > 0 ? points[i - 1] : (closed ? points[n - 1] : null);
      final Vector3? next = i < n - 1 ? points[i + 1] : (closed ? points[0] : null);

      Vector3 miterDir;
      double miterScale = 1.0;

      if (prev != null && next != null) {
        final Vector3 d1 = (curr - prev).normalized();
        final Vector3 d2 = (next - curr).normalized();

        final Vector3 n1 = d1.cross(surfaceNormal).normalized();
        final Vector3 n2 = d2.cross(surfaceNormal).normalized();

        final Vector3 miter = n1 + n2;
        if (miter.length2 < 1e-6) {
          miterDir = n1;
        } else {
          miterDir = miter.normalized();
          // Scale width by 1 / dot(miter, n1) so corners never pinch; clamp sharp spikes
          final double dot = miterDir.dot(n1).abs().clamp(0.35, 1.0);
          miterScale = 1.0 / dot;
        }
      } else if (next != null) {
        final Vector3 d = (next - curr).normalized();
        miterDir = d.cross(surfaceNormal).normalized();
      } else {
        final Vector3 d = (curr - prev!).normalized();
        miterDir = d.cross(surfaceNormal).normalized();
      }

      final Vector3 offset = miterDir * (worldHalfWidth * miterScale);

      // Left vertex (edgeCoord = -1.0)
      final Vector3 left = curr - offset;
      _verts.addAll([left.x, left.y, left.z, -1.0]);

      // Right vertex (edgeCoord = +1.0)
      final Vector3 right = curr + offset;
      _verts.addAll([right.x, right.y, right.z, 1.0]);

      _vertexCount += 2;
    }

    final int segCount = closed ? n : n - 1;
    for (int i = 0; i < segCount; i++) {
      final int i0 = startVertexIndex + (i * 2);
      final int i1 = i0 + 1;
      final int nextStep = closed ? ((i + 1) % n) : (i + 1);
      final int i2 = startVertexIndex + (nextStep * 2);
      final int i3 = i2 + 1;

      _indices.addAll([i0, i1, i2, i1, i3, i2]);
    }
  }

  CadLineMeshData build() => CadLineMeshData(
        Float32List.fromList(_verts),
        Uint16List.fromList(_indices),
      );
}
```

### Step 2: Depth-Biased & Antialiased Line Shaders

#### `shaders/cad_line.vert`
```glsl
#version 460 core

layout(location = 0) in vec3 a_position;
layout(location = 1) in float a_edgeCoord; // -1.0 to +1.0

uniform mat4 u_mvp;
layout(location = 0) out float v_edgeCoord;

void main() {
  vec4 clipPos = u_mvp * vec4(a_position, 1.0);

  // CRITICAL CHECKPOINT: Pull the line slightly toward the camera in clip space
  // Prevents flat plates from swallowing hole borders at grazing angles
  clipPos.z -= 0.0006 * clipPos.w;

  v_edgeCoord = a_edgeCoord;
  gl_Position = clipPos;
}
```

#### `shaders/cad_line.frag`
```glsl
#version 460 core

layout(location = 0) in float v_edgeCoord;
layout(location = 0) out vec4 fragColor;

void main() {
  float dist = abs(v_edgeCoord);
  float aaWidth = fwidth(dist);
  float alpha = 1.0 - smoothstep(1.0 - aaWidth * 1.5, 1.0, dist);

  // Onshape charcoal-slate line color (#1E2730)
  fragColor = vec4(0.118, 0.153, 0.188, alpha);
}
```

---

## 4. Phase 3: Procedural Fillets, Adaptive Holes & Vertex Normal Separation

### Rules for CAD Vertex Normals
| Feature Type | Vertex Sharing Rule | Normal Direction | Black Edge Emission |
| :--- | :--- | :--- | :--- |
| **Flat Plate / Wall** | Duplicate vertices at all 90° edges & hole rims | Constant face normal `N` | Emit closed outer loop + closed hole loops |
| **Curved Fillet (Bend)** | Share vertices across interior steps `i = 1..segments-1` | Smooth radial vector `(pos - arcCenter).normalized()` | Emit **only** at `i = 0` and `i = segments` tangent boundaries + 2 end arcs |
| **Cylindrical Hole Bore** | Separate vertices from top/bottom flat plates | Inward radial vector `-radialOut` | Emit closed circular loop at top rim & bottom rim |

### Adaptive Circle Tessellation Helper
Never hardcode 8 segments (octagons) for holes or fillets. Compute segment count from chordal error:

```dart
int getSegmentsForCircle(double radius, {double maxChordError = 0.03}) {
  final double ratio = (maxChordError / radius).clamp(0.0001, 0.5);
  final double angle = 2.0 * acos(1.0 - ratio);
  final int segments = (2.0 * pi / angle).ceil();
  return segments.clamp(36, 96);
}
```

---

## 5. Phase 4: 2D Polygon Triangulation with Interior Holes (Dart Earcut)

When generating a flat CAD plate with circular holes, you cannot simply render a solid quad over the top—the quad will cover up the cylindrical holes. You must **triangulate the 2D outer boundary polygon with the interior 2D circular hole loops subtracted**, and then lift those 2D vertices into 3D space.

### Complete Zero-Dependency Dart Earcut Triangulator (Outer Loop + Holes)
This self-contained implementation merges interior hole loops into the outer polygon via mutual-visibility bridge edges and triangulates the resulting simple polygon via ear-clipping.

```dart
import 'dart:math';
import 'package:vector_math/vector_math_64.dart';

class CadPolygonTriangulator {
  /// Triangulates a planar 2D outer contour (counter-clockwise) with zero or more
  /// interior hole contours.
  ///
  /// Returns a combined list of [outVertices2D] and triangle [indices] (multiples of 3).
  static ({List<Vector2> vertices, List<int> indices}) triangulateWithHoles({
    required List<Vector2> outerLoop,
    List<List<Vector2>> holes = const [],
  }) {
    // 1. Ensure outerLoop is Counter-Clockwise (CCW)
    List<Vector2> polygon = List<Vector2>.from(outerLoop);
    if (_signedArea(polygon) < 0) {
      polygon = polygon.reversed.toList();
    }

    // 2. Ensure all holes are Clockwise (CW) and sort holes right-to-left by max X
    final List<List<Vector2>> sortedHoles = holes.map((h) {
      final copy = List<Vector2>.from(h);
      return _signedArea(copy) > 0 ? copy.reversed.toList() : copy;
    }).toList();

    sortedHoles.sort((a, b) {
      final double maxXa = a.map((p) => p.x).reduce(max);
      final double maxXb = b.map((p) => p.x).reduce(max);
      return maxXb.compareTo(maxXa);
    });

    // 3. Splice each hole into the outer polygon using rightmost bridge search
    for (final hole in sortedHoles) {
      polygon = _spliceHoleIntoPolygon(polygon, hole);
    }

    // 4. Run ear-clipping on the merged simple polygon
    final List<int> triangles = _earcutSimplePolygon(polygon);
    return (vertices: polygon, indices: triangles);
  }

  static double _signedArea(List<Vector2> pts) {
    double area = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final Vector2 p1 = pts[i];
      final Vector2 p2 = pts[(i + 1) % pts.length];
      area += (p1.x * p2.y - p2.x * p1.y);
    }
    return area * 0.5;
  }

  static List<Vector2> _spliceHoleIntoPolygon(
    List<Vector2> outer,
    List<Vector2> hole,
  ) {
    // Find rightmost vertex in the hole
    int holeMaxIdx = 0;
    for (int i = 1; i < hole.length; i++) {
      if (hole[i].x > hole[holeMaxIdx].x) {
        holeMaxIdx = i;
      }
    }
    final Vector2 m = hole[holeMaxIdx];

    // Cast a ray +X from M to find the closest intersection with an outer edge
    double bestIntersectX = double.infinity;
    int bestOuterIdx = -1;

    final int n = outer.length;
    for (int i = 0; i < n; i++) {
      final Vector2 p1 = outer[i];
      final Vector2 p2 = outer[(i + 1) % n];

      // Check if segment straddles m.y
      if ((p1.y > m.y) != (p2.y > m.y)) {
        final double intersectX =
            p1.x + (m.y - p1.y) * (p2.x - p1.x) / (p2.y - p1.y);
        if (intersectX >= m.x && intersectX < bestIntersectX) {
          bestIntersectX = intersectX;
          // Pick the endpoint of this edge with larger X as initial bridge candidate
          bestOuterIdx = (p1.x >= p2.x) ? i : (i + 1) % n;
        }
      }
    }

    if (bestOuterIdx == -1) {
      // Fallback: closest vertex to the right of M
      double minDist = double.infinity;
      for (int i = 0; i < n; i++) {
        if (outer[i].x >= m.x) {
          final double d = outer[i].distanceToSquared(m);
          if (d < minDist) {
            minDist = d;
            bestOuterIdx = i;
          }
        }
      }
    }

    final Vector2 pCandidate = outer[bestOuterIdx];
    final Vector2 intersectPt = Vector2(bestIntersectX, m.y);

    // Check if any reflex outer vertex lies inside the triangle (m, intersectPt, pCandidate)
    // If so, select the one that minimizes the angle with the +X ray from m
    int bridgeIdx = bestOuterIdx;
    double minAngle = double.infinity;

    for (int i = 0; i < n; i++) {
      final Vector2 v = outer[i];
      if (_pointInTriangle(v, m, intersectPt, pCandidate)) {
        final Vector2 dir = (v - m).normalized();
        final double angle = dir.y.abs();
        if (angle < minAngle) {
          minAngle = angle;
          bridgeIdx = i;
        }
      }
    }

    // Build merged vertex list with a zero-width bridge between outer[bridgeIdx] and hole[holeMaxIdx]
    final List<Vector2> merged = [];
    for (int i = 0; i <= bridgeIdx; i++) {
      merged.add(outer[i]);
    }
    for (int i = 0; i <= hole.length; i++) {
      merged.add(hole[(holeMaxIdx + i) % hole.length]);
    }
    for (int i = bridgeIdx; i < outer.length; i++) {
      merged.add(outer[i]);
    }

    return merged;
  }

  static List<int> _earcutSimplePolygon(List<Vector2> poly) {
    final List<int> indices = [];
    final List<int> vList = List<int>.generate(poly.length, (i) => i);

    int count = vList.length;
    int guard = count * 4;
    int curr = 0;

    while (count > 2 && guard > 0) {
      guard--;
      final int prevIdx = (curr + count - 1) % count;
      final int nextIdx = (curr + 1) % count;

      final int i0 = vList[prevIdx];
      final int i1 = vList[curr % count];
      final int i2 = vList[nextIdx];

      if (_isEar(poly, vList, count, i0, i1, i2)) {
        indices.addAll([i0, i1, i2]);
        vList.removeAt(curr % count);
        count--;
        guard = count * 4;
      } else {
        curr = (curr + 1) % count;
      }
    }
    return indices;
  }

  static bool _isEar(
    List<Vector2> poly,
    List<int> vList,
    int count,
    int i0,
    int i1,
    int i2,
  ) {
    final Vector2 a = poly[i0];
    final Vector2 b = poly[i1];
    final Vector2 c = poly[i2];

    // Convex check (CCW)
    final double cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (cross <= 1e-7) return false;

    // Ensure no other active vertex lies inside triangle (a, b, c)
    for (int j = 0; j < count; j++) {
      final int vi = vList[j];
      if (vi == i0 || vi == i1 || vi == i2) continue;
      final Vector2 p = poly[vi];
      if ((p - a).length2 < 1e-9 ||
          (p - b).length2 < 1e-9 ||
          (p - c).length2 < 1e-9) {
        continue;
      }
      if (_pointInTriangle(p, a, b, c)) return false;
    }
    return true;
  }

  static bool _pointInTriangle(Vector2 p, Vector2 a, Vector2 b, Vector2 c) {
    final double d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y);
    final double d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y);
    final double d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y);

    final bool hasNeg = (d1 < -1e-7) || (d2 < -1e-7) || (d3 < -1e-7);
    final bool hasPos = (d1 > 1e-7) || (d2 > 1e-7) || (d3 > 1e-7);
    return !(hasNeg && hasPos);
  }
}
```

---

## 6. Phase 5: Unified `CadSolidBuilder` (Plates with Holes + Smooth Fillets + Bores)

This builder combines the **2D Earcut Triangulator**, **Adaptive Hole Bores**, **Smooth Radial Fillets**, and **`CadEdgeBuilder`** so you can construct complete Onshape-style sheet-metal brackets in one pass.

```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart';

class CadSurfaceMeshData {
  /// Interleaved [posX, posY, posZ, normX, normY, normZ] -> 6 floats per vertex
  final Float32List vertices;
  final Uint16List indices;
  CadSurfaceMeshData(this.vertices, this.indices);
}

class CircularHoleSpec {
  final Vector2 center2D;
  final double radius;
  CircularHoleSpec(this.center2D, this.radius);
}

class CadSolidBuilder {
  final List<double> _verts = [];
  final List<int> _indices = [];
  int _vertexCount = 0;

  int _addVertex(Vector3 pos, Vector3 normal) {
    _verts.addAll([pos.x, pos.y, pos.z, normal.x, normal.y, normal.z]);
    return _vertexCount++;
  }

  /// 1. Builds a 3D extruded planar plate with arbitrary circular through-holes,
  /// inner hole bores, and all top/bottom black CAD edges.
  void addExtrudedPlateWithHoles({
    required Vector3 origin,
    required Vector3 uAxis, // Unit X axis on plate plane
    required Vector3 vAxis, // Unit Y axis on plate plane
    required List<Vector2> outerBoundary2D,
    required List<CircularHoleSpec> holes,
    required double thickness,
    required CadEdgeBuilder edgeBuilder,
    double edgeHalfWidth = 0.06,
  }) {
    final Vector3 topNormal = uAxis.cross(vAxis).normalized();
    final Vector3 bottomNormal = -topNormal;

    // Generate high-res 2D hole contours
    final List<List<Vector2>> holeLoops2D = [];
    for (final h in holes) {
      final int segs = getSegmentsForCircle(h.radius);
      final List<Vector2> loop = [];
      for (int i = 0; i < segs; i++) {
        final double a = (2.0 * pi * i) / segs;
        loop.add(Vector2(
          h.center2D.x + cos(a) * h.radius,
          h.center2D.y + sin(a) * h.radius,
        ));
      }
      holeLoops2D.add(loop);
    }

    // Triangulate planar face with holes subtracted
    final result = CadPolygonTriangulator.triangulateWithHoles(
      outerLoop: outerBoundary2D,
      holes: holeLoops2D,
    );

    Vector3 to3D(Vector2 p, double zOffset) =>
        origin + (uAxis * p.x) + (vAxis * p.y) + (topNormal * zOffset);

    // A. Emit TOP face (zOffset = 0)
    final int topStartIdx = _vertexCount;
    for (final p2d in result.vertices) {
      _addVertex(to3D(p2d, 0.0), topNormal);
    }
    for (int i = 0; i < result.indices.length; i += 3) {
      _indices.addAll([
        topStartIdx + result.indices[i],
        topStartIdx + result.indices[i + 1],
        topStartIdx + result.indices[i + 2],
      ]);
    }

    // B. Emit BOTTOM face (zOffset = -thickness, reversed winding)
    final int botStartIdx = _vertexCount;
    for (final p2d in result.vertices) {
      _addVertex(to3D(p2d, -thickness), bottomNormal);
    }
    for (int i = 0; i < result.indices.length; i += 3) {
      _indices.addAll([
        botStartIdx + result.indices[i + 2],
        botStartIdx + result.indices[i + 1],
        botStartIdx + result.indices[i],
      ]);
    }

    // C. Emit Top & Bottom Outer Black Border Loops
    final List<Vector3> topOuter3D =
        outerBoundary2D.map((p) => to3D(p, 0.0)).toList();
    final List<Vector3> botOuter3D =
        outerBoundary2D.map((p) => to3D(p, -thickness)).toList();

    edgeBuilder.addPolyline(
      topOuter3D,
      surfaceNormal: topNormal,
      worldHalfWidth: edgeHalfWidth,
      closed: true,
    );
    edgeBuilder.addPolyline(
      botOuter3D,
      surfaceNormal: bottomNormal,
      worldHalfWidth: edgeHalfWidth,
      closed: true,
    );

    // D. Emit Cylindrical Hole Bores + Top/Bottom Rim Black Borders
    for (final h in holes) {
      final Vector3 holeCenterTop = to3D(h.center2D, 0.0);
      addCylindricalHole(
        centerTop: holeCenterTop,
        plateNormal: topNormal,
        radius: h.radius,
        depth: thickness,
        edgeBuilder: edgeBuilder,
        edgeHalfWidth: edgeHalfWidth,
      );
    }
  }

  /// 2. Generates a smooth Onshape-style curved sheet-metal bend (Fillet)
  void addCurvedFillet({
    required Vector3 arcCenterStart,
    required Vector3 arcCenterEnd,
    required Vector3 startRadialDir,
    required Vector3 endRadialDir,
    required double innerRadius,
    required double thickness,
    required CadEdgeBuilder edgeBuilder,
    double edgeHalfWidth = 0.06,
    int segments = 28,
  }) {
    final Vector3 axisDir = (arcCenterEnd - arcCenterStart).normalized();
    final double totalAngle =
        acos(startRadialDir.dot(endRadialDir).clamp(-1.0, 1.0));
    final Vector3 rotAxis = startRadialDir.cross(endRadialDir).normalized();

    final int outerBaseIdx = _vertexCount;
    final List<Vector3> startArcLoop = [];
    final List<Vector3> endArcLoop = [];

    for (int i = 0; i <= segments; i++) {
      final double t = i / segments;
      final Quaternion q = Quaternion.axisAngle(rotAxis, totalAngle * t);
      final Vector3 radialNormal = q.rotated(startRadialDir).normalized();

      final Vector3 p0 =
          arcCenterStart + radialNormal * (innerRadius + thickness);
      final Vector3 p1 =
          arcCenterEnd + radialNormal * (innerRadius + thickness);

      _addVertex(p0, radialNormal);
      _addVertex(p1, radialNormal);

      startArcLoop.add(p0);
      endArcLoop.add(p1);
    }

    for (int i = 0; i < segments; i++) {
      final int b = outerBaseIdx + i * 2;
      _indices.addAll([b, b + 1, b + 2, b + 1, b + 3, b + 2]);
    }

    // Emit ONLY the 2 tangent boundaries and 2 end profile arcs
    edgeBuilder.addPolyline(
      [startArcLoop.first, endArcLoop.first],
      surfaceNormal: startRadialDir,
      worldHalfWidth: edgeHalfWidth,
      closed: false,
    );
    edgeBuilder.addPolyline(
      [startArcLoop.last, endArcLoop.last],
      surfaceNormal: endRadialDir,
      worldHalfWidth: edgeHalfWidth,
      closed: false,
    );
    edgeBuilder.addPolyline(
      startArcLoop,
      surfaceNormal: -axisDir,
      worldHalfWidth: edgeHalfWidth,
      closed: false,
    );
    edgeBuilder.addPolyline(
      endArcLoop,
      surfaceNormal: axisDir,
      worldHalfWidth: edgeHalfWidth,
      closed: false,
    );
  }

  /// 3. Generates a high-resolution cylindrical hole bore with separate inward normals
  void addCylindricalHole({
    required Vector3 centerTop,
    required Vector3 plateNormal,
    required double radius,
    required double depth,
    required CadEdgeBuilder edgeBuilder,
    double edgeHalfWidth = 0.06,
  }) {
    final int segments = getSegmentsForCircle(radius);

    final Vector3 helper =
        plateNormal.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
    final Vector3 tangent = plateNormal.cross(helper).normalized();
    final Vector3 bitangent = plateNormal.cross(tangent).normalized();

    final int baseIdx = _vertexCount;
    final List<Vector3> topRimPoints = [];
    final List<Vector3> bottomRimPoints = [];

    for (int i = 0; i <= segments; i++) {
      final double angle = (2 * pi * i) / segments;
      final Vector3 radialOut =
          (tangent * cos(angle) + bitangent * sin(angle)).normalized();

      final Vector3 topPos = centerTop + radialOut * radius;
      final Vector3 botPos = topPos - plateNormal * depth;

      final Vector3 inwardNormal = -radialOut;
      _addVertex(topPos, inwardNormal);
      _addVertex(botPos, inwardNormal);

      if (i < segments) {
        topRimPoints.add(topPos);
        bottomRimPoints.add(botPos);
      }
    }

    for (int i = 0; i < segments; i++) {
      final int b = baseIdx + i * 2;
      _indices.addAll([b, b + 1, b + 2, b + 1, b + 3, b + 2]);
    }

    edgeBuilder.addPolyline(
      topRimPoints,
      surfaceNormal: plateNormal,
      worldHalfWidth: edgeHalfWidth,
      closed: true,
    );
    edgeBuilder.addPolyline(
      bottomRimPoints,
      surfaceNormal: -plateNormal,
      worldHalfWidth: edgeHalfWidth,
      closed: true,
    );
  }

  CadSurfaceMeshData build() => CadSurfaceMeshData(
        Float32List.fromList(_verts),
        Uint16List.fromList(_indices),
      );
}
```

---

## 7. Phase 6: Zero-Jank Camera Orbiting & GPU Buffer Management

### Critical Performance Rules for the Coding Agent
1. **NEVER call `setState()` inside `onScaleUpdate` / `onPanUpdate`:** Rebuilding Flutter's widget tree at 120Hz causes severe frame drops. Pass a `CadCameraController` (`ChangeNotifier`) directly to the render loop or `CustomPainter(repaint: cameraController)`.
2. **NEVER regenerate or re-upload meshes during camera orbit:** `CadSolidBuilder.build()` and `CadEdgeBuilder.build()` must run **only** when CAD parameters change. During camera rotation, only update the `u_modelViewMatrix` and `u_mvp` uniform matrices.
3. **Quaternion Turntable / Arcball Orbit:** Avoid Euler angle gimbal lock by maintaining spherical coordinates or a `Quaternion` camera orientation around a 3D `target` pivot.

```dart
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

class CadCameraController extends ChangeNotifier {
  Vector3 target = Vector3.zero();
  double distance = 50.0;
  double yaw = 0.6;
  double pitch = 0.45;

  final Matrix4 _viewMatrix = Matrix4.identity();
  final Matrix4 _projMatrix = Matrix4.identity();

  Matrix4 get viewMatrix => _viewMatrix;
  Matrix4 get projectionMatrix => _projMatrix;

  void updateViewport(double width, double height) {
    final double aspect = width / (height == 0 ? 1 : height);
    setPerspectiveMatrix(_projMatrix, 0.785398, aspect, 0.5, 2000.0);
    _recomputeViewMatrix();
  }

  void onOrbitDelta(double dx, double dy) {
    yaw -= dx * 0.007;
    pitch = (pitch + dy * 0.007).clamp(-1.52, 1.52);
    _recomputeViewMatrix();
    notifyListeners(); // Triggers GPU repaint ONLY—does not rebuild widget tree!
  }

  void onPanDelta(double dx, double dy) {
    final double panSpeed = distance * 0.0015;
    final Vector3 right = Vector3(
      _viewMatrix.entry(0, 0),
      _viewMatrix.entry(1, 0),
      _viewMatrix.entry(2, 0),
    );
    final Vector3 up = Vector3(
      _viewMatrix.entry(0, 1),
      _viewMatrix.entry(1, 1),
      _viewMatrix.entry(2, 1),
    );

    target -= right * (dx * panSpeed);
    target += up * (dy * panSpeed);
    _recomputeViewMatrix();
    notifyListeners();
  }

  void onZoomScale(double scaleFactor) {
    distance = (distance / scaleFactor).clamp(2.0, 1000.0);
    _recomputeViewMatrix();
    notifyListeners();
  }

  void _recomputeViewMatrix() {
    final double x = target.x + distance * cos(pitch) * sin(yaw);
    final double y = target.y + distance * sin(pitch);
    final double z = target.z + distance * cos(pitch) * cos(yaw);

    setViewMatrix(_viewMatrix, Vector3(x, y, z), target, Vector3(0, 1, 0));
  }
}
```

---

## 8. Final Verification Checklist for the Coding Agent
- [ ] **No Scene Spotlights:** Confirmed that scene spotlights and shadow maps (`castsShadow: true`) are removed in favor of the view-space headlight shader or camera-parented `DirectionalLight`.
- [ ] **Line Width Reduced:** `worldHalfWidth` is tuned so lines render at `~1.25–1.5px` on screen (60–70% thinner than initial prototype).
- [ ] **Closed Loops Enabled:** All hole rims and rectangular cutouts pass `closed: true` to `CadEdgeBuilder.addPolyline` so miter vectors join all corners seamlessly.
- [ ] **Depth Bias Active:** `clipPos.z -= 0.0006 * clipPos.w;` is active in `cad_line.vert` so blue faces never clip or swallow hole borders.
- [ ] **High-Res Holes & Earcut Active:** All circular holes use `getSegmentsForCircle()` (`>= 36` segments) and subtract their interior loops from the flat plate using `CadPolygonTriangulator.triangulateWithHoles()`.
- [ ] **Decoupled Render Loop:** `GestureDetector` mutates `CadCameraController` without invoking `setState()`.
