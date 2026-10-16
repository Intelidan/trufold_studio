# Onshape & SketchUp-Grade 3D Object Selection, Move, Rotate/Protractor (`Q`), Ctrl-Copy Arrays & Assembly Welding (`flutter_scene` & Canvas Fallback)
**Coding Agent Implementation Walkthrough & Architecture Guide (v3.1)**

## 1. Executive Summary & Architectural Goals

This specification extends the **v2.0 Onshape-Grade 3D CAD Rendering Pipeline** with a complete **SketchUp-style Object Manipulation, Protractor Rotation, Ctrl-Copy Array Duplication, and Assembly Welding Engine**. It enables users to:
1. **Click-select 3D parts** and inspect them inside a translucent bounding box with 27 semantic snap points + parametric hole centers.
2. **Press `M` (Move Tool)** for zero-drag **Click-Move-Click** translation with Arrow-Key axis locking (`→` Red X, `←` Green Y, `↑` Blue Z, `↓` Surface Normal).
3. **Press `Q` (Rotate / Protractor Tool)** for SketchUp's **3-Click Protractor Rotation** (1st click: pivot center + axis plane; 2nd click: `0°` reference arm; 3rd click: target angle with `15°` protractor tick snaps and magnetic object snapping).
4. **Tap `Ctrl` (Copy & Array Mode)** during any Move or Rotate to spawn a zero-copy GPU-instanced duplicate (`+` cursor badge), followed by typing **`*N` / `Nx` (Multiply Array)** or **`/N` (Divide Array)** to generate linear or radial part arrays on the fly.
5. **Magnetically snap and join/weld parts** into rigid `CadAssemblyGroup` sub-assemblies with coaxial hole alignment.

### Mandatory Repository Engine Rules (Enforced Throughout v3.1)
1. **Single-Precision `vector_math` Only:** Every file strictly imports `package:vector_math/vector_math.dart` (32-bit floats). `vector_math_64.dart` is forbidden to prevent type mismatches with `flutter_scene` nodes, transforms, and uniform buffers.
2. **Dual-Pipeline Symmetry (`flutter_scene` + 2D `Canvas` Fallback):** Because Windows desktop and headless widget tests may run without Impeller enabled, all visual overlays—translucent bounding boxes, 3D protractor gizmos, swept angle sectors, snap anchor markers, dashed R/G/B axis inference lines, and copy/array HUD readouts—are implemented symmetrically for both `flutter_scene_cad_mesh_builder.dart` (Flutter GPU) and `flutter_paint_3d_engine.dart` (`CustomPainter` Canvas fallback).
3. **Locked 60/120 FPS Silky-Smooth Manipulation:** Mouse movement during translation and rotation is driven by `MouseRegion.onHover` + `ChangeNotifier` matrix updates (`u_modelMatrix`), updating only 4×4 world transforms without calling `setState()` or duplicating vertex buffers.

## 2. Interaction Flow & State Machine (Move `M`, Rotate `Q`, & `Ctrl`-Copy Arrays)

| State | Trigger to Enter | Visual Feedback | User Capabilities |
| :--- | :--- | :--- | :--- |
| **`select`** | Initial state / `Esc` / Click part | Translucent cyan bounding box (`alpha: 0.14`) + 27 snap points + hole centers | Orbit, pan, zoom; press **`M`** for Move or **`Q`** for Rotate/Protractor |
| **`moveArmed`** | Press **`M`** while part is selected | 4-way move cursor; hovering highlights closest **Base Snap Point** | Hover to pick grab point; tap **`Ctrl`** to toggle Copy mode (`+` badge) |
| **`movingHover`** | **1st Move Click** on snap or surface | Dashed R/G/B axis line; magnetic snap badges; live copy preview if `isCopyMode` | Move mouse **without holding buttons**; press `→`/`←`/`↑`/`↓` to lock axis; tap `Ctrl` to toggle clone |
| **`rotateArmed`** | Press **`Q`** while part is selected | Color-coded **3D Protractor Ring** tracks cursor normal across faces/snaps | Press `→`/`←`/`↑`/`↓` to lock protractor plane normal (X/Y/Z/Normal); **1st Click** sets Pivot |
| **`rotatePickArm`** | **1st Rotate Click** on pivot point | Protractor anchored at 3D pivot; dashed radius arm follows cursor | Move mouse to define `0°` reference arm (snaps to corners/holes); **2nd Click** locks reference arm |
| **`rotatingHover`** | **2nd Rotate Click** on reference point | Shaded pie sector between `0°` arm and live arm; `15°` tick snaps; live degree readout | Move mouse freely to rotate part; tap **`Ctrl`** to toggle radial copy; **3rd Click** commits rotation |
| **`postCommitArray`** | **Final Click** of a `Ctrl`-Copy Move or Rotate | VCB HUD prompts for array expression (`*N`, `Nx`, or `/N`) | Type **`*4`** / **`4x`** (external multiply array) or **`/4`** (internal divide array) + `Enter` to generate linear or circular arrays; re-type to adjust count live! |

## 3. Phase 1: Scene Graph Entities, Zero-Allocation Cloning & Assembly Welding

To make `Ctrl`-copy and `*N` / `/N` array duplication instantaneous at 120 FPS, `CadSceneEntity.cloneInstance()` shares the underlying immutable `Float32List surfaceVertices` and `Uint16List surfaceIndices` buffers while allocating only a fresh `Matrix4 worldTransform`.

### `lib/cad_kernel/cad_entity_and_assembly.dart`
```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';

enum CadSnapType {
  corner,       // 8 AABB corners (SketchUp Green Endpoint)
  edgeMidpoint, // 12 AABB edge midpoints (SketchUp Cyan Midpoint)
  faceCenter,   // 6 AABB face centers (SketchUp Blue/Magenta Face Center)
  centroid,     // 1 Volumetric center
  holeCenter,   // Parametric cylindrical bore center (for coaxial bolt/pin mating)
  surfacePoint, // Arbitrary ray-cast point on a triangle face
}

class CadSnapPoint {
  final String id;
  final String ownerEntityId;
  final CadSnapType type;
  final Vector3 localPosition;
  final Vector3 localNormal; // Outward normal or hole axis for rotational alignment

  const CadSnapPoint({
    required this.id,
    required this.ownerEntityId,
    required this.type,
    required this.localPosition,
    required this.localNormal,
  });

  Vector3 worldPosition(Matrix4 worldTransform) =>
      worldTransform.transform3(localPosition.clone());

  Vector3 worldNormal(Matrix4 worldTransform) =>
      worldTransform.rotated3(localNormal.clone()).normalized();
}

/// Represents a rigid or coaxial weld between two CAD parts in an assembly.
class CadAssemblyWeld {
  final String weldId;
  final String partAId;
  final String partBId;
  final String snapPointAId;
  final String snapPointBId;
  final Matrix4 relativeTransformBtoA;

  CadAssemblyWeld({
    required this.weldId,
    required this.partAId,
    required this.partBId,
    required this.snapPointAId,
    required this.snapPointBId,
    required this.relativeTransformBtoA,
  });
}

class CadSceneEntity {
  final String id;
  final String name;

  /// If welded with other parts, all welded parts share the same assemblyGroupId.
  String? assemblyGroupId;

  /// Local-space triangle vertices [posX, posY, posZ, normX, normY, normZ] from v2.0
  final Float32List surfaceVertices;
  final Uint16List surfaceIndices;

  /// Local-space bounding box
  final Aabb3 localBounds;

  /// Explicit parametric snap points (e.g., hole centers added during CadSolidBuilder)
  final List<CadSnapPoint> featureSnapPoints;

  /// Cached 27 bounding-box snap points + parametric feature snap points
  late final List<CadSnapPoint> allSnapPoints;

  /// World transform mutated in-place during 120Hz hover-move/rotate without rebuilding meshes
  final Matrix4 worldTransform = Matrix4.identity();
  final Matrix4 _inverseWorldTransform = Matrix4.identity();

  CadSceneEntity({
    required this.id,
    required this.name,
    required this.surfaceVertices,
    required this.surfaceIndices,
    List<CadSnapPoint>? featureSnapPoints,
    Matrix4? initialTransform,
    this.assemblyGroupId,
  })  : featureSnapPoints = featureSnapPoints ?? [],
        localBounds = _computeLocalAabb(surfaceVertices) {
    if (initialTransform != null) {
      worldTransform.setFrom(initialTransform);
    }
    _syncInverse();
    allSnapPoints = [
      ..._generateBoundingBoxSnapPoints(id, localBounds),
      ...this.featureSnapPoints,
    ];
  }

  /// Creates a lightweight GPU-instanced clone for Ctrl-Copy and Linear/Radial Arrays.
  /// Reuses `surfaceVertices` and `surfaceIndices` without copying geometry buffers!
  CadSceneEntity cloneInstance({
    required String newId,
    String? newAssemblyGroupId,
    Matrix4? transformOverride,
  }) {
    final List<CadSnapPoint> clonedFeatures = featureSnapPoints
        .map((s) => CadSnapPoint(
              id: '${newId}_${s.id}',
              ownerEntityId: newId,
              type: s.type,
              localPosition: s.localPosition.clone(),
              localNormal: s.localNormal.clone(),
            ))
        .toList();

    return CadSceneEntity(
      id: newId,
      name: '$name (Copy)',
      surfaceVertices: surfaceVertices,
      surfaceIndices: surfaceIndices,
      featureSnapPoints: clonedFeatures,
      initialTransform: transformOverride ?? worldTransform.clone(),
      assemblyGroupId: newAssemblyGroupId,
    );
  }

  Matrix4 get inverseWorldTransform => _inverseWorldTransform;

  void setWorldTransform(Matrix4 nextTransform) {
    worldTransform.setFrom(nextTransform);
    _syncInverse();
  }

  void _syncInverse() {
    _inverseWorldTransform.setFrom(worldTransform);
    _inverseWorldTransform.invert();
  }

  static Aabb3 _computeLocalAabb(Float32List verts) {
    if (verts.isEmpty) {
      return Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1));
    }
    final Vector3 minV = Vector3(verts[0], verts[1], verts[2]);
    final Vector3 maxV = Vector3(verts[0], verts[1], verts[2]);

    for (int i = 0; i < verts.length; i += 6) {
      final double x = verts[i];
      final double y = verts[i + 1];
      final double z = verts[i + 2];
      if (x < minV.x) minV.x = x;
      if (y < minV.y) minV.y = y;
      if (z < minV.z) minV.z = z;
      if (x > maxV.x) maxV.x = x;
      if (y > maxV.y) maxV.y = y;
      if (z > maxV.z) maxV.z = z;
    }
    return Aabb3.minMax(minV, maxV);
  }

  /// Generates the 27 standard CAD bounding box snap anchors:
  /// 8 Corners + 12 Edge Midpoints + 6 Face Centers + 1 Centroid
  static List<CadSnapPoint> _generateBoundingBoxSnapPoints(
    String entityId,
    Aabb3 box,
  ) {
    final List<CadSnapPoint> snaps = [];
    final Vector3 min = box.min;
    final Vector3 max = box.max;
    final Vector3 mid = (min + max) * 0.5;

    final List<double> xs = [min.x, mid.x, max.x];
    final List<double> ys = [min.y, mid.y, max.y];
    final List<double> zs = [min.z, mid.z, max.z];

    for (int ix = 0; ix < 3; ix++) {
      for (int iy = 0; iy < 3; iy++) {
        for (int iz = 0; iz < 3; iz++) {
          final int midCount =
              (ix == 1 ? 1 : 0) + (iy == 1 ? 1 : 0) + (iz == 1 ? 1 : 0);

          CadSnapType type;
          if (midCount == 0) {
            type = CadSnapType.corner;
          } else if (midCount == 1) {
            type = CadSnapType.edgeMidpoint;
          } else if (midCount == 2) {
            type = CadSnapType.faceCenter;
          } else {
            type = CadSnapType.centroid;
          }

          final Vector3 pos = Vector3(xs[ix], ys[iy], zs[iz]);
          final Vector3 normal = Vector3(
            ix == 0 ? -1.0 : (ix == 2 ? 1.0 : 0.0),
            iy == 0 ? -1.0 : (iy == 2 ? 1.0 : 0.0),
            iz == 0 ? -1.0 : (iz == 2 ? 1.0 : 0.0),
          );
          if (normal.length2 > 0) normal.normalize();

          snaps.add(CadSnapPoint(
            id: '${entityId}_bbox_${ix}_${iy}_$iz',
            ownerEntityId: entityId,
            type: type,
            localPosition: pos,
            localNormal: normal,
          ));
        }
      }
    }
    return snaps;
  }
}
```

## 4. Phase 2: Exact 3D Ray-Picking (`CadRayPicker`)

When the user clicks on the 3D canvas, we unproject the 2D screen coordinate through the inverse `ViewProjection` matrix into a 3D world `Ray`.
* **Two-Stage Picking:** First, transform the world ray into each object's local coordinate space (`entity.inverseWorldTransform`) and test against `entity.localBounds` (`Aabb3`). Second, if the ray intersects the `Aabb3`, run **Möller–Trumbore triangle intersection** against `surfaceVertices`/`surfaceIndices` so clicking through an interior hole in a plate accurately ignores the empty hole and selects whatever object is behind it.

### `lib/cad_kernel/cad_ray_picker.dart`
```dart
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';
import 'cad_entity_and_assembly.dart';

class CadRayHitResult {
  final CadSceneEntity entity;
  final Vector3 worldHitPoint;
  final Vector3 worldNormal;
  final double distance;

  const CadRayHitResult({
    required this.entity,
    required this.worldHitPoint,
    required this.worldNormal,
    required this.distance,
  });
}

class CadRayPicker {
  /// Unprojects a 2D viewport pixel [screenX, screenY] into a 3D world-space [Ray].
  static Ray screenPointToWorldRay({
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    final double ndcX = (2.0 * screenX) / viewportWidth - 1.0;
    final double ndcY = 1.0 - (2.0 * screenY) / viewportHeight;

    final Matrix4 invVP = (projectionMatrix * viewMatrix)..invert();

    final Vector4 nearClip = Vector4(ndcX, ndcY, -1.0, 1.0);
    final Vector4 farClip = Vector4(ndcX, ndcY, 1.0, 1.0);

    final Vector4 nearWorld4 = invVP.transform(nearClip);
    final Vector4 farWorld4 = invVP.transform(farClip);

    final Vector3 nearPoint = nearWorld4.xyz / nearWorld4.w;
    final Vector3 farPoint = farWorld4.xyz / farWorld4.w;
    final Vector3 dir = (farPoint - nearPoint).normalized();

    return Ray.originDirection(nearPoint, dir);
  }

  /// Picks the closest visible [CadSceneEntity] under the cursor.
  static CadRayHitResult? pickEntity({
    required Ray worldRay,
    required List<CadSceneEntity> entities,
    Set<String> excludedEntityIds = const {},
  }) {
    CadRayHitResult? closestHit;

    for (final entity in entities) {
      if (excludedEntityIds.contains(entity.id)) continue;

      final Matrix4 invModel = entity.inverseWorldTransform;
      final Vector3 localOrigin = invModel.transform3(worldRay.origin.clone());
      final Vector3 localDir =
          invModel.rotated3(worldRay.direction.clone()).normalized();
      final Ray localRay = Ray.originDirection(localOrigin, localDir);

      final double? aabbDist = _intersectRayAabb(localRay, entity.localBounds);
      if (aabbDist == null) continue;

      final hit = _intersectRayMesh(localRay, entity);
      if (hit != null) {
        final Vector3 worldPt = entity.worldTransform.transform3(hit.localPoint);
        final Vector3 worldNorm =
            entity.worldTransform.rotated3(hit.localNormal).normalized();
        final double worldDist = worldPt.distanceTo(worldRay.origin);

        if (closestHit == null || worldDist < closestHit.distance) {
          closestHit = CadRayHitResult(
            entity: entity,
            worldHitPoint: worldPt,
            worldNormal: worldNorm,
            distance: worldDist,
          );
        }
      }
    }

    return closestHit;
  }

  static double? _intersectRayAabb(Ray ray, Aabb3 box) {
    double tMin = -double.infinity;
    double tMax = double.infinity;

    for (int i = 0; i < 3; i++) {
      final double origin = ray.origin[i];
      final double dir = ray.direction[i];
      final double bMin = box.min[i];
      final double bMax = box.max[i];

      if (dir.abs() < 1e-8) {
        if (origin < bMin || origin > bMax) return null;
      } else {
        double t1 = (bMin - origin) / dir;
        double t2 = (bMax - origin) / dir;
        if (t1 > t2) {
          final double tmp = t1;
          t1 = t2;
          t2 = tmp;
        }
        if (t1 > tMin) tMin = t1;
        if (t2 < tMax) tMax = t2;
        if (tMin > tMax) return null;
      }
    }
    return tMax >= 0 ? (tMin >= 0 ? tMin : tMax) : null;
  }

  static ({Vector3 localPoint, Vector3 localNormal})? _intersectRayMesh(
    Ray localRay,
    CadSceneEntity entity,
  ) {
    final Float32List verts = entity.surfaceVertices;
    final Uint16List indices = entity.surfaceIndices;

    double closestT = double.infinity;
    Vector3? bestNormal;

    final Vector3 v0 = Vector3.zero();
    final Vector3 v1 = Vector3.zero();
    final Vector3 v2 = Vector3.zero();
    final Vector3 edge1 = Vector3.zero();
    final Vector3 edge2 = Vector3.zero();
    final Vector3 h = Vector3.zero();
    final Vector3 s = Vector3.zero();
    final Vector3 q = Vector3.zero();

    for (int i = 0; i < indices.length; i += 3) {
      final int i0 = indices[i] * 6;
      final int i1 = indices[i + 1] * 6;
      final int i2 = indices[i + 2] * 6;

      v0.setValues(verts[i0], verts[i0 + 1], verts[i0 + 2]);
      v1.setValues(verts[i1], verts[i1 + 1], verts[i1 + 2]);
      v2.setValues(verts[i2], verts[i2 + 1], verts[i2 + 2]);

      edge1
        ..setFrom(v1)
        ..sub(v0);
      edge2
        ..setFrom(v2)
        ..sub(v0);

      localRay.direction.crossInto(edge2, h);
      final double a = edge1.dot(h);
      if (a > -1e-7 && a < 1e-7) continue;

      final double f = 1.0 / a;
      s
        ..setFrom(localRay.origin)
        ..sub(v0);
      final double u = f * s.dot(h);
      if (u < 0.0 || u > 1.0) continue;

      s.crossInto(edge1, q);
      final double v = f * localRay.direction.dot(q);
      if (v < 0.0 || u + v > 1.0) continue;

      final double t = f * edge2.dot(q);
      if (t > 1e-5 && t < closestT) {
        closestT = t;
        bestNormal = edge1.cross(edge2).normalized();
      }
    }

    if (bestNormal == null) return null;
    return (
      localPoint: localRay.at(closestT),
      localNormal: bestNormal,
    );
  }
}
```

## 5. Phase 3: Unified Move (`M`), Protractor Rotate (`Q`), `Ctrl`-Copy & Array Controller

### Mathematical Foundations for Rotate (`Q`) & `Ctrl`-Copy Arrays
1. **3-Click Protractor Rotation (`Q` Key):**
   * **Click 1 (Set Pivot $\mathbf{P}_{\text{pivot}}$ & Normal Axis $\mathbf{N}$):** Locks the protractor origin and its normal vector $\mathbf{N}$ (automatically inferred from the hovered surface/hole normal, or locked to Red X `(1,0,0)`, Green Y `(0,1,0)`, or Blue Z `(0,0,1)` via the arrow keys).
   * **Click 2 (Set `0°` Reference Arm $\mathbf{U}_0$):** Projects the cursor ray (or snapped vertex) onto the plane $(\mathbf{P}_{\text{pivot}}, \mathbf{N})$ and computes the normalized reference direction:
     $$\mathbf{U}_0 = \frac{(\mathbf{P}_{\text{ref}} - \mathbf{P}_{\text{pivot}}) - \big((\mathbf{P}_{\text{ref}} - \mathbf{P}_{\text{pivot}}) \cdot \mathbf{N}\big)\mathbf{N}}{\left\|(\mathbf{P}_{\text{ref}} - \mathbf{P}_{\text{pivot}}) - \big((\mathbf{P}_{\text{ref}} - \mathbf{P}_{\text{pivot}}) \cdot \mathbf{N}\big)\mathbf{N}\right\|}$$
   * **Hover & Click 3 (Compute Signed Angle $\theta$ & Apply Pivot Rotation):** Projects the live hover point $\mathbf{P}_{\text{cur}}$ onto the plane $(\mathbf{P}_{\text{pivot}}, \mathbf{N})$ to obtain unit vector $\mathbf{U}_1$, then computes the full $[-\pi, \pi]$ signed rotation angle:
     $$\theta = \text{atan2}\big((\mathbf{U}_0 \times \mathbf{U}_1) \cdot \mathbf{N},\; \mathbf{U}_0 \cdot \mathbf{U}_1\big)$$
     If no external snap point is locked and $\theta$ is within `1.8°` of a `15°` protractor tick mark, $\theta$ snaps cleanly to that `15°` multiple. Each moving entity's world transform updates via:
     $$\mathbf{M}_{\text{world}} = \mathbf{T}(\mathbf{P}_{\text{pivot}}) \cdot \mathbf{R}(\mathbf{N}, \theta) \cdot \mathbf{T}(-\mathbf{P}_{\text{pivot}}) \cdot \mathbf{M}_{\text{init}}$$

2. **`Ctrl`-Copy & Live Linear/Radial Array Expressions (`*N`, `Nx`, `/N`):**
   * Tapping `Ctrl` (`LogicalKeyboardKey.controlLeft` / `controlRight` or `altLeft` on macOS) toggles `isCopyMode`. When enabled during an active move or rotation, the original source entities are restored to `_initialTransforms`, and a cloned group (`_activeCopyGroup`) moves/rotates with the cursor.
   * After the final placement click of a `Ctrl`-copy, the controller records the committed parameters (`_lastCommittedTranslationDelta` or `_lastCommittedRotationAngle` + pivot/axis) and opens the **Value Control Box (`vcbInputBuffer`)**.
   * Typing **`*4`** or **`4x` + `Enter`** spawns $N=4$ copies at steps $k = 1, 2, 3, 4$ ($k \cdot \Delta\mathbf{p}$ for linear move arrays, or $k \cdot \theta$ for radial protractor arrays).
   * Typing **`/4` + `Enter`** spawns $N=4$ copies subdividing the span at fractions $k / 4$ ($k = 1, 2, 3, 4$).
   * Typing a new multiplier/divisor immediately replaces `_lastArrayGeneratedEntities` in place, matching SketchUp's iterative array workflow!

### `lib/cad_kernel/cad_move_and_snap_controller.dart`
```dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart';
import 'cad_entity_and_assembly.dart';
import 'cad_ray_picker.dart';

enum CadToolMode {
  select,
  moveArmed,       // User pressed 'M' -> waiting for 1st click to pick base point
  movingHover,     // 1st Move click done -> moving object smoothly with mouse hover
  rotateArmed,     // User pressed 'Q' -> hovering protractor to pick Pivot & Axis
  rotatePickArm,   // 1st Rotate click done -> hovering to pick 0-degree reference arm
  rotatingHover,   // 2nd Rotate click done -> rotating object smoothly with mouse hover
}

enum AxisLockMode {
  none,
  xRed,         // Right Arrow -> Vector3(1, 0, 0)
  yGreen,       // Left Arrow  -> Vector3(0, 1, 0)
  zBlue,        // Up Arrow    -> Vector3(0, 0, 1)
  localNormal,  // Down Arrow  -> Picked face/hole normal vector
}

class ActiveSnapMatch {
  final CadSnapPoint? sourceSnap;
  final CadSnapPoint targetSnap;
  final Vector3 snappedWorldPosition;
  final bool canAlignNormals;

  const ActiveSnapMatch({
    this.sourceSnap,
    required this.targetSnap,
    required this.snappedWorldPosition,
    this.canAlignNormals = false,
  });
}

class CadMoveAndSnapController extends ChangeNotifier {
  final List<CadSceneEntity> sceneEntities;
  final List<CadAssemblyWeld> welds = [];

  CadToolMode _toolMode = CadToolMode.select;
  CadToolMode get toolMode => _toolMode;

  CadSceneEntity? _selectedEntity;
  CadSceneEntity? get selectedEntity => _selectedEntity;

  /// Source entities selected before Move/Rotate began
  List<CadSceneEntity> _sourceGroup = [];

  /// Entities currently being transformed by hover (either _sourceGroup or _activeCopyGroup)
  List<CadSceneEntity> _movingGroup = [];
  List<CadSceneEntity> get movingGroup => _movingGroup;

  /// Cloned entities spawned when Ctrl-Copy (`isCopyMode`) is active during Move or Rotate
  final List<CadSceneEntity> _activeCopyGroup = [];

  /// Snapshot of initial world transforms of `_sourceGroup` before Move/Rotate started
  final Map<String, Matrix4> _initialTransforms = {};

  /// Whether SketchUp Ctrl-Copy mode (`+` badge) is active
  bool _isCopyMode = false;
  bool get isCopyMode => _isCopyMode;

  /// SketchUp Value Control Box (VCB) keyboard buffer for typing `*5`, `5x`, `/3`, distance, or angle
  String _vcbInputBuffer = '';
  String get vcbInputBuffer => _vcbInputBuffer;

  /// Stores the most recent committed Ctrl-copy operation so typing `*N` or `/N` generates arrays
  bool _canAcceptArrayInput = false;
  bool get canAcceptArrayInput => _canAcceptArrayInput;
  bool _lastCommitWasRotation = false;
  Vector3 _lastCommittedTranslationDelta = Vector3.zero();
  Vector3 _lastCommittedRotatePivot = Vector3.zero();
  Vector3 _lastCommittedRotateAxis = Vector3(0, 1, 0);
  double _lastCommittedRotateAngleRad = 0.0;
  final List<CadSceneEntity> _lastArrayGeneratedEntities = [];
  int _copyCounter = 1;

  /// Hover candidate snap point when choosing a grab/pivot point
  CadSnapPoint? _hoveredPickupSnap;
  CadSnapPoint? get hoveredPickupSnap => _hoveredPickupSnap;

  /// Grabbed base point in world space (for Move tool)
  Vector3? _baseGrabPointWorld;
  Vector3? get baseGrabPointWorld => _baseGrabPointWorld;
  Vector3 _baseGrabNormalWorld = Vector3(0, 0, 1);
  CadSnapPoint? _grabbedSourceSnap;

  /// Current live world point of the grabbed anchor during hover-move
  Vector3? _currentMovePointWorld;
  Vector3? get currentMovePointWorld => _currentMovePointWorld;

  /// Protractor / Rotate (`Q` key) state variables
  Vector3 _protractorPreviewPointWorld = Vector3.zero();
  Vector3 get protractorPreviewPointWorld => _protractorPreviewPointWorld;

  Vector3 _protractorPreviewNormalWorld = Vector3(0, 1, 0);
  Vector3 get protractorPreviewNormalWorld =>
      getLockedAxisVector() ?? _protractorPreviewNormalWorld;

  Vector3? _rotatePivotWorld;
  Vector3? get rotatePivotWorld => _rotatePivotWorld;

  Vector3 _rotateAxisWorld = Vector3(0, 1, 0);
  Vector3 get rotateAxisWorld => _rotateAxisWorld;

  Vector3? _rotateRefArmDirWorld; // Unit vector in rotation plane for 0° baseline
  Vector3? get rotateRefArmDirWorld => _rotateRefArmDirWorld;

  Vector3? _rotateCurrentArmDirWorld; // Unit vector in rotation plane for current angle
  Vector3? get rotateCurrentArmDirWorld => _rotateCurrentArmDirWorld;

  double _rotateCurrentAngleRad = 0.0;
  double get rotateCurrentAngleRad => _rotateCurrentAngleRad;
  double get rotateCurrentAngleDeg => _rotateCurrentAngleRad * (180.0 / pi);

  double _protractorRadiusWorld = 12.0;
  double get protractorRadiusWorld => _protractorRadiusWorld;

  /// Active arrow-key axis lock
  AxisLockMode _axisLock = AxisLockMode.none;
  AxisLockMode get axisLock => _axisLock;

  /// Active magnetic snap match on another object in the scene
  ActiveSnapMatch? _activeSnapMatch;
  ActiveSnapMatch? get activeSnapMatch => _activeSnapMatch;

  /// Whether final placement on a snapped point automatically welds the parts
  bool autoWeldOnSnap = true;
  bool alignRotationOnHoleSnap = true;
  Vector3 _dragPlaneNormal = Vector3(0, 1, 0);

  CadMoveAndSnapController({required this.sceneEntities});

  /// Returns the combined world-space Aabb3 of the selected entity (or its welded assembly group)
  Aabb3? getSelectedGroupWorldBounds() {
    if (_selectedEntity == null) return null;
    final group = _getEntitiesInGroup(_selectedEntity!);
    Aabb3? combined;
    for (final e in group) {
      final Aabb3 worldBox = _transformAabb(e.localBounds, e.worldTransform);
      if (combined == null) {
        combined = Aabb3.copy(worldBox);
      } else {
        combined.hull(worldBox);
      }
    }
    return combined;
  }

  List<CadSceneEntity> _getEntitiesInGroup(CadSceneEntity root) {
    if (root.assemblyGroupId == null) return [root];
    return sceneEntities
        .where((e) => e.assemblyGroupId == root.assemblyGroupId)
        .toList();
  }

  /// Keyboard handler for:
  /// - 'M' (Move Tool)
  /// - 'Q' (Rotate / Protractor Tool)
  /// - 'Ctrl' / 'Alt' (Toggle Copy Mode `+`)
  /// - Arrow Keys (Red/Green/Blue/Normal Axis Lock)
  /// - `*N`, `Nx`, `/N` + `Enter` (Linear & Radial Array Duplication)
  /// - 'Escape' (Cancel)
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    // 1. Activate Move Tool with 'M'
    if (key == LogicalKeyboardKey.keyM && _selectedEntity != null) {
      armMoveTool();
      return true;
    }

    // 2. Activate Rotate / Protractor Tool with 'Q'
    if (key == LogicalKeyboardKey.keyQ && _selectedEntity != null) {
      armRotateTool();
      return true;
    }

    // 3. Tap Ctrl (or Option/Alt) to toggle SketchUp Copy Mode (`+` cursor badge)
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      if (_toolMode == CadToolMode.moveArmed ||
          _toolMode == CadToolMode.movingHover ||
          _toolMode == CadToolMode.rotateArmed ||
          _toolMode == CadToolMode.rotatePickArm ||
          _toolMode == CadToolMode.rotatingHover) {
        toggleCopyMode();
        return true;
      }
    }

    // 4. Arrow Key Axis Locking (works in both Move and Rotate/Protractor modes!)
    if (_toolMode != CadToolMode.select) {
      if (key == LogicalKeyboardKey.arrowRight) {
        _toggleAxisLock(AxisLockMode.xRed);
        return true;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        _toggleAxisLock(AxisLockMode.yGreen);
        return true;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        _toggleAxisLock(AxisLockMode.zBlue);
        return true;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _toggleAxisLock(AxisLockMode.localNormal);
        return true;
      }
    }

    // 5. Value Control Box (VCB) Array Input (`*4`, `4x`, `/3` + Enter)
    if (_canAcceptArrayInput ||
        _toolMode == CadToolMode.movingHover ||
        _toolMode == CadToolMode.rotatingHover) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        if (_vcbInputBuffer.isNotEmpty) {
          _executeVcbCommand(_vcbInputBuffer.trim());
          _vcbInputBuffer = '';
          notifyListeners();
          return true;
        }
      } else if (key == LogicalKeyboardKey.backspace) {
        if (_vcbInputBuffer.isNotEmpty) {
          _vcbInputBuffer =
              _vcbInputBuffer.substring(0, _vcbInputBuffer.length - 1);
          notifyListeners();
          return true;
        }
      } else {
        final String? char = event.character;
        if (char != null && RegExp(r'^[0-9xX*\/.\-]$').hasMatch(char)) {
          _vcbInputBuffer += char;
          notifyListeners();
          return true;
        }
      }
    }

    // 6. Escape cancels active Move/Rotate or clears selection
    if (key == LogicalKeyboardKey.escape) {
      cancelOrDeselect();
      return true;
    }

    return false;
  }

  void armMoveTool() {
    if (_selectedEntity == null) return;
    _cleanupActiveCopyPreview();
    _toolMode = CadToolMode.moveArmed;
    _axisLock = AxisLockMode.none;
    _activeSnapMatch = null;
    _canAcceptArrayInput = false;
    _vcbInputBuffer = '';
    notifyListeners();
  }

  void armRotateTool() {
    if (_selectedEntity == null) return;
    _cleanupActiveCopyPreview();
    _toolMode = CadToolMode.rotateArmed;
    _axisLock = AxisLockMode.none;
    _activeSnapMatch = null;
    _canAcceptArrayInput = false;
    _vcbInputBuffer = '';

    final Aabb3? bounds = getSelectedGroupWorldBounds();
    if (bounds != null) {
      _protractorPreviewPointWorld = bounds.center;
      _protractorRadiusWorld =
          (bounds.max - bounds.min).length.clamp(6.0, 40.0) * 0.55;
    }
    _protractorPreviewNormalWorld = Vector3(0, 1, 0);
    notifyListeners();
  }

  /// Toggles SketchUp's Ctrl-Copy mode (`+` badge).
  /// Can be toggled either before picking up the object OR mid-move / mid-rotate!
  void toggleCopyMode() {
    _isCopyMode = !_isCopyMode;

    if (_toolMode == CadToolMode.movingHover ||
        _toolMode == CadToolMode.rotatingHover) {
      if (_isCopyMode) {
        // Restore original entities to their starting pose and spawn live clones
        for (final src in _sourceGroup) {
          final init = _initialTransforms[src.id];
          if (init != null) src.setWorldTransform(init);
        }
        _spawnLiveCopyGroup();
      } else {
        // Remove live clones and resume moving original entities
        final Matrix4? currentFirstTransform =
            _activeCopyGroup.isNotEmpty ? _activeCopyGroup.first.worldTransform.clone() : null;
        _cleanupActiveCopyPreview();
        _movingGroup = List<CadSceneEntity>.from(_sourceGroup);
        if (currentFirstTransform != null && _movingGroup.length == 1) {
          _movingGroup.first.setWorldTransform(currentFirstTransform);
        }
      }
    }
    notifyListeners();
  }

  void _spawnLiveCopyGroup() {
    _cleanupActiveCopyPreview();
    final String? newGroupId = _sourceGroup.length > 1
        ? 'assembly_copy_${DateTime.now().microsecondsSinceEpoch}'
        : null;

    for (final src in _sourceGroup) {
      final String cloneId = '${src.id}_copy_${_copyCounter++}';
      final CadSceneEntity clone = src.cloneInstance(
        newId: cloneId,
        newAssemblyGroupId: newGroupId,
        transformOverride: _initialTransforms[src.id]?.clone(),
      );
      _initialTransforms[clone.id] = _initialTransforms[src.id]!.clone();
      sceneEntities.add(clone);
      _activeCopyGroup.add(clone);
    }
    _movingGroup = List<CadSceneEntity>.from(_activeCopyGroup);
  }

  void _cleanupActiveCopyPreview() {
    for (final clone in _activeCopyGroup) {
      sceneEntities.remove(clone);
      _initialTransforms.remove(clone.id);
    }
    _activeCopyGroup.clear();
  }

  void _toggleAxisLock(AxisLockMode requested) {
    _axisLock = (_axisLock == requested) ? AxisLockMode.none : requested;
    if (_toolMode == CadToolMode.rotatePickArm ||
        _toolMode == CadToolMode.rotatingHover) {
      final Vector3? locked = getLockedAxisVector();
      if (locked != null) _rotateAxisWorld = locked.normalized();
    }
    notifyListeners();
  }

  Vector3? getLockedAxisVector() {
    switch (_axisLock) {
      case AxisLockMode.none:
        return null;
      case AxisLockMode.xRed:
        return Vector3(1.0, 0.0, 0.0);
      case AxisLockMode.yGreen:
        return Vector3(0.0, 1.0, 0.0);
      case AxisLockMode.zBlue:
        return Vector3(0.0, 0.0, 1.0);
      case AxisLockMode.localNormal:
        return _baseGrabNormalWorld;
    }
  }

  /// Handles all viewport clicks across Select, Move (`M`), and Rotate (`Q`) states.
  void onViewportClick({
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    final Ray worldRay = CadRayPicker.screenPointToWorldRay(
      screenX: screenX,
      screenY: screenY,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
    );

    // --- MOVE TOOL STATES ---
    if (_toolMode == CadToolMode.movingHover) {
      _commitMovePlacement();
      return;
    }

    if (_toolMode == CadToolMode.moveArmed && _selectedEntity != null) {
      _beginHoverMove(
        worldRay: worldRay,
        screenX: screenX,
        screenY: screenY,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
      );
      return;
    }

    // --- ROTATE / PROTRACTOR TOOL STATES ---
    if (_toolMode == CadToolMode.rotateArmed && _selectedEntity != null) {
      _beginRotatePickPivot(
        worldRay: worldRay,
        screenX: screenX,
        screenY: screenY,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
      );
      return;
    }

    if (_toolMode == CadToolMode.rotatePickArm) {
      _beginRotateHoverFromReferenceArm();
      return;
    }

    if (_toolMode == CadToolMode.rotatingHover) {
      _commitRotatePlacement();
      return;
    }

    // --- STANDARD SELECTION MODE ---
    final CadRayHitResult? hit = CadRayPicker.pickEntity(
      worldRay: worldRay,
      entities: sceneEntities,
    );

    _selectedEntity = hit?.entity;
    _toolMode = CadToolMode.select;
    _hoveredPickupSnap = null;
    _activeSnapMatch = null;
    _canAcceptArrayInput = false;
    notifyListeners();
  }

  /// Handles continuous `MouseRegion.onHover` movement (NO mouse button held down!).
  void onViewportHover({
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    if (_selectedEntity == null) return;

    final Ray worldRay = CadRayPicker.screenPointToWorldRay(
      screenX: screenX,
      screenY: screenY,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
    );

    // 1. Hovering in `moveArmed`: highlight snap points on the selected object
    if (_toolMode == CadToolMode.moveArmed) {
      final group = _getEntitiesInGroup(_selectedEntity!);
      final snap = _findClosestScreenSnapPoint(
        entities: group,
        screenX: screenX,
        screenY: screenY,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
        pixelThreshold: 16.0,
      );
      if (snap?.id != _hoveredPickupSnap?.id) {
        _hoveredPickupSnap = snap;
        notifyListeners();
      }
      return;
    }

    // 2. Hovering in `movingHover`: translate object smoothly + magnetic snap
    if (_toolMode == CadToolMode.movingHover && _baseGrabPointWorld != null) {
      _updateHoverMove(
        worldRay: worldRay,
        screenX: screenX,
        screenY: screenY,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
      );
      return;
    }

    // 3. Hovering in `rotateArmed`: orient Protractor Gizmo on hovered snap or surface face
    if (_toolMode == CadToolMode.rotateArmed) {
      _updateProtractorPreviewHover(
        worldRay: worldRay,
        screenX: screenX,
        screenY: screenY,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
      );
      return;
    }

    // 4. Hovering in `rotatePickArm`: update 0° starting reference arm on protractor plane
    if (_toolMode == CadToolMode.rotatePickArm && _rotatePivotWorld != null) {
      final Vector3? dir = _computeArmDirectionOnRotationPlane(
        worldRay: worldRay,
        screenX: screenX,
        screenY: screenY,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
      );
      if (dir != null) {
        _rotateRefArmDirWorld = dir;
        notifyListeners();
      }
      return;
    }

    // 5. Hovering in `rotatingHover`: compute live angle around pivot & rotate part at 120Hz!
    if (_toolMode == CadToolMode.rotatingHover &&
        _rotatePivotWorld != null &&
        _rotateRefArmDirWorld != null) {
      _updateHoverRotation(
        worldRay: worldRay,
        screenX: screenX,
        screenY: screenY,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
      );
    }
  }

  void _beginHoverMove({
    required Ray worldRay,
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    _sourceGroup = _getEntitiesInGroup(_selectedEntity!);
    _initialTransforms.clear();
    for (final e in _sourceGroup) {
      _initialTransforms[e.id] = e.worldTransform.clone();
    }

    if (_isCopyMode) {
      _spawnLiveCopyGroup();
    } else {
      _movingGroup = List<CadSceneEntity>.from(_sourceGroup);
    }

    final CadSnapPoint? clickedSnap = _findClosestScreenSnapPoint(
      entities: _sourceGroup,
      screenX: screenX,
      screenY: screenY,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      pixelThreshold: 16.0,
    );

    if (clickedSnap != null) {
      final CadSceneEntity owner =
          _sourceGroup.firstWhere((e) => e.id == clickedSnap.ownerEntityId);
      _grabbedSourceSnap = clickedSnap;
      _baseGrabPointWorld = clickedSnap.worldPosition(owner.worldTransform);
      _baseGrabNormalWorld = clickedSnap.worldNormal(owner.worldTransform);
    } else {
      final CadRayHitResult? surfaceHit = CadRayPicker.pickEntity(
        worldRay: worldRay,
        entities: _sourceGroup,
      );
      if (surfaceHit != null) {
        _grabbedSourceSnap = null;
        _baseGrabPointWorld = surfaceHit.worldHitPoint;
        _baseGrabNormalWorld = surfaceHit.worldNormal;
      } else {
        final Aabb3 bounds = getSelectedGroupWorldBounds()!;
        _grabbedSourceSnap = null;
        _baseGrabPointWorld = bounds.center;
        _baseGrabNormalWorld = Vector3(0, 1, 0);
      }
    }

    _currentMovePointWorld = _baseGrabPointWorld!.clone();

    final Vector3 camForward = Vector3(
      -viewMatrix.entry(2, 0),
      -viewMatrix.entry(2, 1),
      -viewMatrix.entry(2, 2),
    ).normalized();
    _dragPlaneNormal =
        camForward.y.abs() > 0.35 ? Vector3(0, 1, 0) : camForward;

    _toolMode = CadToolMode.movingHover;
    notifyListeners();
  }

  void _updateHoverMove({
    required Ray worldRay,
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    final Set<String> movingIds = _movingGroup.map((e) => e.id).toSet();
    final List<CadSceneEntity> staticTargets =
        sceneEntities.where((e) => !movingIds.contains(e.id)).toList();

    final CadSnapPoint? targetSnap = _findClosestScreenSnapPoint(
      entities: staticTargets,
      screenX: screenX,
      screenY: screenY,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      pixelThreshold: 15.0,
    );

    final Vector3? lockedAxis = getLockedAxisVector();
    Vector3 nextWorldPoint;

    if (targetSnap != null) {
      final CadSceneEntity targetOwner =
          staticTargets.firstWhere((e) => e.id == targetSnap.ownerEntityId);
      final Vector3 targetWorldPos =
          targetSnap.worldPosition(targetOwner.worldTransform);

      if (lockedAxis != null) {
        final double projDistance =
            (targetWorldPos - _baseGrabPointWorld!).dot(lockedAxis);
        nextWorldPoint = _baseGrabPointWorld! + lockedAxis * projDistance;
      } else {
        nextWorldPoint = targetWorldPos;
      }

      _activeSnapMatch = ActiveSnapMatch(
        sourceSnap: _grabbedSourceSnap,
        targetSnap: targetSnap,
        snappedWorldPosition: targetWorldPos,
        canAlignNormals: alignRotationOnHoleSnap &&
            _grabbedSourceSnap?.type == CadSnapType.holeCenter &&
            targetSnap.type == CadSnapType.holeCenter,
      );
    } else {
      _activeSnapMatch = null;
      if (lockedAxis != null) {
        nextWorldPoint = _projectRayOntoAxisLine(
          ray: worldRay,
          axisOrigin: _baseGrabPointWorld!,
          axisDir: lockedAxis,
        );
      } else {
        nextWorldPoint = _intersectRayWithPlane(
              ray: worldRay,
              planePoint: _baseGrabPointWorld!,
              planeNormal: _dragPlaneNormal,
            ) ??
            _currentMovePointWorld!;
      }
    }

    _currentMovePointWorld = nextWorldPoint;
    final Vector3 translationDelta = nextWorldPoint - _baseGrabPointWorld!;

    for (final entity in _movingGroup) {
      final Matrix4 initMat = _initialTransforms[entity.id]!;

      if (_activeSnapMatch != null &&
          _activeSnapMatch!.canAlignNormals &&
          _grabbedSourceSnap != null &&
          lockedAxis == null) {
        final CadSceneEntity targetOwner = staticTargets.firstWhere(
            (e) => e.id == _activeSnapMatch!.targetSnap.ownerEntityId);
        final Vector3 srcNorm =
            _grabbedSourceSnap!.worldNormal(initMat).normalized();
        final Vector3 dstNorm = _activeSnapMatch!.targetSnap
            .worldNormal(targetOwner.worldTransform)
            .normalized();

        final Quaternion rotAlign =
            Quaternion.fromTwoVectors(srcNorm, -dstNorm);
        final Matrix4 rotMat = Matrix4.compose(
          Vector3.zero(),
          rotAlign,
          Vector3(1, 1, 1),
        );

        final Vector3 pivot = _baseGrabPointWorld!;
        final Matrix4 mated = Matrix4.identity()
          ..translate(nextWorldPoint.x, nextWorldPoint.y, nextWorldPoint.z)
          ..multiply(rotMat)
          ..translate(-pivot.x, -pivot.y, -pivot.z)
          ..multiply(initMat);

        entity.setWorldTransform(mated);
      } else {
        final Matrix4 translated = Matrix4.identity()
          ..translate(
            translationDelta.x,
            translationDelta.y,
            translationDelta.z,
          )
          ..multiply(initMat);
        entity.setWorldTransform(translated);
      }
    }

    notifyListeners();
  }

  void _commitMovePlacement() {
    final Vector3 delta =
        (_currentMovePointWorld ?? Vector3.zero()) -
        (_baseGrabPointWorld ?? Vector3.zero());

    if (_isCopyMode) {
      // Record linear copy delta so typing `*N` or `/N` generates a Linear Array!
      _canAcceptArrayInput = true;
      _lastCommitWasRotation = false;
      _lastCommittedTranslationDelta = delta;
      _lastArrayGeneratedEntities
        ..clear()
        ..addAll(_activeCopyGroup);
      _activeCopyGroup.clear();
    } else if (_activeSnapMatch != null &&
        autoWeldOnSnap &&
        _selectedEntity != null) {
      final CadSceneEntity targetEntity = sceneEntities.firstWhere(
        (e) => e.id == _activeSnapMatch!.targetSnap.ownerEntityId,
      );
      weldEntities(_selectedEntity!, targetEntity, _activeSnapMatch!);
    }

    _toolMode = CadToolMode.select;
    _axisLock = AxisLockMode.none;
    _isCopyMode = false;
    _baseGrabPointWorld = null;
    _currentMovePointWorld = null;
    _grabbedSourceSnap = null;
    _activeSnapMatch = null;
    notifyListeners();
  }

  // ===========================================================================
  // ROTATE / PROTRACTOR (`Q` KEY) IMPLEMENTATION
  // ===========================================================================

  void _updateProtractorPreviewHover({
    required Ray worldRay,
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    final CadSnapPoint? snap = _findClosestScreenSnapPoint(
      entities: sceneEntities,
      screenX: screenX,
      screenY: screenY,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      pixelThreshold: 16.0,
    );

    if (snap != null) {
      final CadSceneEntity owner =
          sceneEntities.firstWhere((e) => e.id == snap.ownerEntityId);
      _hoveredPickupSnap = snap;
      _protractorPreviewPointWorld = snap.worldPosition(owner.worldTransform);
      _baseGrabNormalWorld = snap.worldNormal(owner.worldTransform);
      if (_axisLock == AxisLockMode.none) {
        _protractorPreviewNormalWorld = _baseGrabNormalWorld;
      }
      notifyListeners();
      return;
    }

    _hoveredPickupSnap = null;
    final CadRayHitResult? hit = CadRayPicker.pickEntity(
      worldRay: worldRay,
      entities: sceneEntities,
    );
    if (hit != null) {
      _protractorPreviewPointWorld = hit.worldHitPoint;
      _baseGrabNormalWorld = hit.worldNormal;
      if (_axisLock == AxisLockMode.none) {
        _protractorPreviewNormalWorld = hit.worldNormal;
      }
      notifyListeners();
    }
  }

  /// 1st Click in Rotate Mode: Locks the 3D Pivot Point and Axis of Rotation
  void _beginRotatePickPivot({
    required Ray worldRay,
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    _updateProtractorPreviewHover(
      worldRay: worldRay,
      screenX: screenX,
      screenY: screenY,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
    );

    _rotatePivotWorld = _protractorPreviewPointWorld.clone();
    _rotateAxisWorld = protractorPreviewNormalWorld.normalized();

    // Default initial reference arm perpendicular to _rotateAxisWorld
    final Vector3 helper = _rotateAxisWorld.x.abs() < 0.9
        ? Vector3(1, 0, 0)
        : Vector3(0, 1, 0);
    _rotateRefArmDirWorld = _rotateAxisWorld.cross(helper).normalized();
    _rotateCurrentArmDirWorld = _rotateRefArmDirWorld!.clone();
    _rotateCurrentAngleRad = 0.0;

    _toolMode = CadToolMode.rotatePickArm;
    notifyListeners();
  }

  /// 2nd Click in Rotate Mode: Locks the 0° Reference Arm and begins live rotation
  void _beginRotateHoverFromReferenceArm() {
    if (_selectedEntity == null || _rotatePivotWorld == null) return;

    _sourceGroup = _getEntitiesInGroup(_selectedEntity!);
    _initialTransforms.clear();
    for (final e in _sourceGroup) {
      _initialTransforms[e.id] = e.worldTransform.clone();
    }

    if (_isCopyMode) {
      _spawnLiveCopyGroup();
    } else {
      _movingGroup = List<CadSceneEntity>.from(_sourceGroup);
    }

    _rotateCurrentArmDirWorld = _rotateRefArmDirWorld?.clone();
    _rotateCurrentAngleRad = 0.0;
    _toolMode = CadToolMode.rotatingHover;
    notifyListeners();
  }

  void _updateHoverRotation({
    required Ray worldRay,
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    final Vector3? rawDir = _computeArmDirectionOnRotationPlane(
      worldRay: worldRay,
      screenX: screenX,
      screenY: screenY,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
    );
    if (rawDir == null) return;

    final Vector3 u0 = _rotateRefArmDirWorld!;
    final Vector3 n = _rotateAxisWorld;

    // Signed angle in [-pi, pi] around axis n
    double angleRad = atan2(u0.cross(rawDir).dot(n), u0.dot(rawDir));

    // Protractor 15-degree tick snapping when not locked to an external vertex
    if (_activeSnapMatch == null) {
      const double stepRad = 15.0 * (pi / 180.0);
      final double nearestTick = (angleRad / stepRad).round() * stepRad;
      if ((angleRad - nearestTick).abs() < (1.8 * pi / 180.0)) {
        angleRad = nearestTick;
      }
    }

    _rotateCurrentAngleRad = angleRad;
    final Quaternion qRot = Quaternion.axisAngle(n, angleRad);
    _rotateCurrentArmDirWorld = qRot.rotated(u0).normalized();

    _applyRotationAroundPivot(
      entities: _movingGroup,
      pivot: _rotatePivotWorld!,
      axis: n,
      angleRad: angleRad,
    );

    notifyListeners();
  }

  void _applyRotationAroundPivot({
    required List<CadSceneEntity> entities,
    required Vector3 pivot,
    required Vector3 axis,
    required double angleRad,
  }) {
    final Quaternion q = Quaternion.axisAngle(axis.normalized(), angleRad);
    final Matrix4 rotMat = Matrix4.compose(
      Vector3.zero(),
      q,
      Vector3(1.0, 1.0, 1.0),
    );

    for (final entity in entities) {
      final Matrix4 initMat = _initialTransforms[entity.id]!;
      final Matrix4 nextMat = Matrix4.identity()
        ..translate(pivot.x, pivot.y, pivot.z)
        ..multiply(rotMat)
        ..translate(-pivot.x, -pivot.y, -pivot.z)
        ..multiply(initMat);
      entity.setWorldTransform(nextMat);
    }
  }

  /// 3rd Click in Rotate Mode: Commits the rotation (and arms Radial Array input if Ctrl-Copy was active)
  void _commitRotatePlacement() {
    if (_isCopyMode && _rotatePivotWorld != null) {
      _canAcceptArrayInput = true;
      _lastCommitWasRotation = true;
      _lastCommittedRotatePivot = _rotatePivotWorld!.clone();
      _lastCommittedRotateAxis = _rotateAxisWorld.clone();
      _lastCommittedRotateAngleRad = _rotateCurrentAngleRad;
      _lastArrayGeneratedEntities
        ..clear()
        ..addAll(_activeCopyGroup);
      _activeCopyGroup.clear();
    }

    _toolMode = CadToolMode.select;
    _axisLock = AxisLockMode.none;
    _isCopyMode = false;
    _rotatePivotWorld = null;
    _rotateRefArmDirWorld = null;
    _rotateCurrentArmDirWorld = null;
    _activeSnapMatch = null;
    notifyListeners();
  }

  Vector3? _computeArmDirectionOnRotationPlane({
    required Ray worldRay,
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
  }) {
    final Set<String> movingIds = _movingGroup.map((e) => e.id).toSet();
    final List<CadSceneEntity> staticTargets =
        sceneEntities.where((e) => !movingIds.contains(e.id)).toList();

    final CadSnapPoint? snap = _findClosestScreenSnapPoint(
      entities: staticTargets,
      screenX: screenX,
      screenY: screenY,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      viewMatrix: viewMatrix,
      projectionMatrix: projectionMatrix,
      pixelThreshold: 15.0,
    );

    Vector3? pointOnPlane;
    if (snap != null) {
      final CadSceneEntity owner =
          staticTargets.firstWhere((e) => e.id == snap.ownerEntityId);
      final Vector3 snapWorld = snap.worldPosition(owner.worldTransform);
      _activeSnapMatch = ActiveSnapMatch(
        targetSnap: snap,
        snappedWorldPosition: snapWorld,
      );
      // Project snapped 3D point onto the protractor plane
      final Vector3 v = snapWorld - _rotatePivotWorld!;
      pointOnPlane =
          _rotatePivotWorld! + (v - _rotateAxisWorld * v.dot(_rotateAxisWorld));
    } else {
      _activeSnapMatch = null;
      pointOnPlane = _intersectRayWithPlane(
        ray: worldRay,
        planePoint: _rotatePivotWorld!,
        planeNormal: _rotateAxisWorld,
      );
    }

    if (pointOnPlane == null) return null;
    final Vector3 radial = pointOnPlane - _rotatePivotWorld!;
    if (radial.length2 < 1e-6) return null;
    return radial.normalized();
  }

  // ===========================================================================
  // SKETCHUP VALUE CONTROL BOX (VCB): `*N`, `Nx`, `/N` ARRAY DUPLICATION
  // ===========================================================================

  /// Parses SketchUp VCB expressions:
  /// - `*4` or `4x` -> External Multiply Array (4 copies at 1x, 2x, 3x, 4x step)
  /// - `/4`         -> Internal Divide Array (4 copies at 1/4, 2/4, 3/4, 4/4 span)
  /// - Numeric value while hovering -> Exact distance or exact angle in degrees
  void _executeVcbCommand(String expr) {
    final String lower = expr.toLowerCase();

    // Case A: Multiply Array (`*4` or `4x`) or Divide Array (`/4`) after a Ctrl-Copy
    final bool isMultiply = lower.startsWith('*') || lower.endsWith('x');
    final bool isDivide = lower.startsWith('/');

    if (_canAcceptArrayInput && (isMultiply || isDivide)) {
      final String digits = lower.replaceAll(RegExp(r'[^0-9]'), '');
      final int? count = int.tryParse(digits);
      if (count == null || count < 1 || count > 200) return;

      // Remove previous array copies so the user can interactively type `4x`, then `6x`, then `/3`!
      for (final oldCopy in _lastArrayGeneratedEntities) {
        sceneEntities.remove(oldCopy);
      }
      _lastArrayGeneratedEntities.clear();

      for (int k = 1; k <= count; k++) {
        final double factor = isDivide ? (k / count) : k.toDouble();
        final String? arrayGroupId = _sourceGroup.length > 1
            ? 'assembly_array_${DateTime.now().microsecondsSinceEpoch}_$k'
            : null;

        for (final src in _sourceGroup) {
          final Matrix4 baseInit = _initialTransforms[src.id]!;
          Matrix4 stepTransform;

          if (_lastCommitWasRotation) {
            final double stepAngle = _lastCommittedRotateAngleRad * factor;
            final Quaternion q = Quaternion.axisAngle(
              _lastCommittedRotateAxis.normalized(),
              stepAngle,
            );
            final Matrix4 rotMat =
                Matrix4.compose(Vector3.zero(), q, Vector3(1, 1, 1));
            final Vector3 p = _lastCommittedRotatePivot;
            stepTransform = Matrix4.identity()
              ..translate(p.x, p.y, p.z)
              ..multiply(rotMat)
              ..translate(-p.x, -p.y, -p.z)
              ..multiply(baseInit);
          } else {
            final Vector3 stepDelta = _lastCommittedTranslationDelta * factor;
            stepTransform = Matrix4.identity()
              ..translate(stepDelta.x, stepDelta.y, stepDelta.z)
              ..multiply(baseInit);
          }

          final CadSceneEntity arrayClone = src.cloneInstance(
            newId: '${src.id}_arr_${_copyCounter++}',
            newAssemblyGroupId: arrayGroupId,
            transformOverride: stepTransform,
          );
          sceneEntities.add(arrayClone);
          _lastArrayGeneratedEntities.add(arrayClone);
        }
      }
      return;
    }

    // Case B: Typing an exact angle in degrees while in `rotatingHover`
    final double? typedValue = double.tryParse(lower);
    if (typedValue != null &&
        _toolMode == CadToolMode.rotatingHover &&
        _rotatePivotWorld != null) {
      _rotateCurrentAngleRad = typedValue * (pi / 180.0);
      _applyRotationAroundPivot(
        entities: _movingGroup,
        pivot: _rotatePivotWorld!,
        axis: _rotateAxisWorld,
        angleRad: _rotateCurrentAngleRad,
      );
      _commitRotatePlacement();
    }
  }

  /// Joins/welds two parts into a rigid assembly so future moves/rotations transform them together.
  void weldEntities(
    CadSceneEntity movingPart,
    CadSceneEntity targetPart,
    ActiveSnapMatch snapMatch,
  ) {
    final String groupId = targetPart.assemblyGroupId ??
        movingPart.assemblyGroupId ??
        'assembly_${DateTime.now().microsecondsSinceEpoch}';

    for (final e in _getEntitiesInGroup(movingPart)) {
      e.assemblyGroupId = groupId;
    }
    for (final e in _getEntitiesInGroup(targetPart)) {
      e.assemblyGroupId = groupId;
    }

    final Matrix4 relBtoA =
        targetPart.inverseWorldTransform * movingPart.worldTransform;

    welds.add(CadAssemblyWeld(
      weldId: 'weld_${welds.length + 1}',
      partAId: targetPart.id,
      partBId: movingPart.id,
      snapPointAId: snapMatch.targetSnap.id,
      snapPointBId: snapMatch.sourceSnap?.id ?? 'surface_origin',
      relativeTransformBtoA: relBtoA,
    ));
  }

  void cancelOrDeselect() {
    if (_toolMode == CadToolMode.movingHover ||
        _toolMode == CadToolMode.rotatingHover) {
      _cleanupActiveCopyPreview();
      for (final entity in _sourceGroup) {
        final init = _initialTransforms[entity.id];
        if (init != null) entity.setWorldTransform(init);
      }
      _toolMode = CadToolMode.select;
      _axisLock = AxisLockMode.none;
      _isCopyMode = false;
      _activeSnapMatch = null;
      _baseGrabPointWorld = null;
      _currentMovePointWorld = null;
      _rotatePivotWorld = null;
    } else if (_toolMode != CadToolMode.select) {
      _toolMode = CadToolMode.select;
      _isCopyMode = false;
      _hoveredPickupSnap = null;
      _rotatePivotWorld = null;
    } else {
      _selectedEntity = null;
      _canAcceptArrayInput = false;
    }
    _vcbInputBuffer = '';
    notifyListeners();
  }

  CadSnapPoint? _findClosestScreenSnapPoint({
    required List<CadSceneEntity> entities,
    required double screenX,
    required double screenY,
    required double viewportWidth,
    required double viewportHeight,
    required Matrix4 viewMatrix,
    required Matrix4 projectionMatrix,
    required double pixelThreshold,
  }) {
    final Matrix4 vp = projectionMatrix * viewMatrix;
    CadSnapPoint? bestSnap;
    double bestDistSq = pixelThreshold * pixelThreshold;

    for (final entity in entities) {
      for (final snap in entity.allSnapPoints) {
        final Vector3 worldPos = snap.worldPosition(entity.worldTransform);
        final Vector2? screenPt = projectWorldToScreen(
          worldPos: worldPos,
          vpMatrix: vp,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
        );
        if (screenPt == null) continue;

        final double dx = screenPt.x - screenX;
        final double dy = screenPt.y - screenY;
        final double dSq = dx * dx + dy * dy;

        final double priorityBias =
            (snap.type == CadSnapType.holeCenter ||
                    snap.type == CadSnapType.corner)
                ? 0.85
                : 1.0;

        if (dSq * priorityBias < bestDistSq) {
          bestDistSq = dSq * priorityBias;
          bestSnap = snap;
        }
      }
    }
    return bestSnap;
  }

  static Vector2? projectWorldToScreen({
    required Vector3 worldPos,
    required Matrix4 vpMatrix,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    final Vector4 clip =
        vpMatrix.transform(Vector4(worldPos.x, worldPos.y, worldPos.z, 1.0));
    if (clip.w <= 0.0001) return null;

    final double ndcX = clip.x / clip.w;
    final double ndcY = clip.y / clip.w;

    return Vector2(
      (ndcX + 1.0) * 0.5 * viewportWidth,
      (1.0 - ndcY) * 0.5 * viewportHeight,
    );
  }

  static Vector3 _projectRayOntoAxisLine({
    required Ray ray,
    required Vector3 axisOrigin,
    required Vector3 axisDir,
  }) {
    final Vector3 a = axisDir.normalized();
    final Vector3 d = ray.direction.normalized();
    final Vector3 w0 = ray.origin - axisOrigin;

    final double b = a.dot(d);
    final double denom = 1.0 - b * b;
    if (denom.abs() < 1e-5) return axisOrigin;

    final double c = a.dot(w0);
    final double f = d.dot(w0);
    final double t = (c - b * f) / denom;
    return axisOrigin + a * t;
  }

  static Vector3? _intersectRayWithPlane({
    required Ray ray,
    required Vector3 planePoint,
    required Vector3 planeNormal,
  }) {
    final double denom = planeNormal.dot(ray.direction);
    if (denom.abs() < 1e-5) return null;
    final double t = (planePoint - ray.origin).dot(planeNormal) / denom;
    if (t < 0) return null;
    return ray.at(t);
  }

  static Aabb3 _transformAabb(Aabb3 localBox, Matrix4 transform) {
    final Vector3 min = localBox.min;
    final Vector3 max = localBox.max;
    final List<Vector3> corners = [
      Vector3(min.x, min.y, min.z),
      Vector3(max.x, min.y, min.z),
      Vector3(min.x, max.y, min.z),
      Vector3(max.x, max.y, min.z),
      Vector3(min.x, min.y, max.z),
      Vector3(max.x, min.y, max.z),
      Vector3(min.x, max.y, max.z),
      Vector3(max.x, max.y, max.z),
    ];
    final Vector3 first = transform.transform3(corners[0]);
    final Aabb3 result = Aabb3.minMax(first.clone(), first.clone());
    for (int i = 1; i < 8; i++) {
      result.hullPoint(transform.transform3(corners[i]));
    }
    return result;
  }
}
```

## 6. Phase 4: Dual-Pipeline Rendering (Flutter GPU + Canvas Fallback)

To honor your repository's **Dual-Pipeline Architecture Rule**, the translucent selection bounding box, the 27 snap points, the SketchUp Red/Green/Blue axis lock lines, the **3D Protractor Ring with `15°` ticks and swept angle sector**, and the **`+` Copy / Array Value Control Box HUD** are built symmetrically across both pipelines.

### Pipeline A: Flutter GPU (`flutter_scene_cad_mesh_builder.dart`)
Generates both the translucent bounding box mesh (`alpha: 0.14`, `depthWriteEnabled: false`) and a procedural 3D Protractor Ring + Swept Angle Fan mesh using single-precision `package:vector_math/vector_math.dart`.

```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';

class FlutterSceneSelectionBoxMesh {
  final Float32List boxVertices; // [posX, posY, posZ, normX, normY, normZ]
  final Uint16List boxIndices;

  FlutterSceneSelectionBoxMesh({
    required this.boxVertices,
    required this.boxIndices,
  });
}

class FlutterSceneSelectionBoxBuilder {
  /// Builds the 6 translucent quad faces for an Aabb3.
  /// Render with `u_baseColor = vec4(0.18, 0.58, 0.96, 0.14)` and `depthWrite: false`.
  static FlutterSceneSelectionBoxMesh buildFromAabb(
    Aabb3 box, {
    double pad = 0.04,
  }) {
    final Vector3 min = box.min - Vector3.all(pad);
    final Vector3 max = box.max + Vector3.all(pad);

    final List<double> verts = [];
    final List<int> indices = [];
    int vCount = 0;

    void addQuad(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, Vector3 n) {
      final int base = vCount;
      for (final p in [p0, p1, p2, p3]) {
        verts.addAll([p.x, p.y, p.z, n.x, n.y, n.z]);
        vCount++;
      }
      indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    final c000 = Vector3(min.x, min.y, min.z);
    final c100 = Vector3(max.x, min.y, min.z);
    final c110 = Vector3(max.x, max.y, min.z);
    final c010 = Vector3(min.x, max.y, min.z);
    final c001 = Vector3(min.x, min.y, max.z);
    final c101 = Vector3(max.x, min.y, max.z);
    final c111 = Vector3(max.x, max.y, max.z);
    final c011 = Vector3(min.x, max.y, max.z);

    addQuad(c001, c101, c111, c011, Vector3(0, 0, 1));
    addQuad(c100, c000, c010, c110, Vector3(0, 0, -1));
    addQuad(c011, c111, c110, c010, Vector3(0, 1, 0));
    addQuad(c000, c100, c101, c001, Vector3(0, -1, 0));
    addQuad(c101, c100, c110, c111, Vector3(1, 0, 0));
    addQuad(c000, c001, c011, c010, Vector3(-1, 0, 0));

    return FlutterSceneSelectionBoxMesh(
      boxVertices: Float32List.fromList(verts),
      boxIndices: Uint16List.fromList(indices),
    );
  }

  /// Builds a 3D translucent swept sector fan for the SketchUp Protractor (`Q` key)
  static FlutterSceneSelectionBoxMesh buildProtractorSectorMesh({
    required Vector3 pivot,
    required Vector3 normal,
    required Vector3 refArmDir,
    required double angleRad,
    required double radius,
    int segments = 36,
  }) {
    final List<double> verts = [];
    final List<int> indices = [];

    verts.addAll([pivot.x, pivot.y, pivot.z, normal.x, normal.y, normal.z]);

    for (int i = 0; i <= segments; i++) {
      final double t = i / segments;
      final Quaternion q = Quaternion.axisAngle(normal, angleRad * t);
      final Vector3 radial = q.rotated(refArmDir).normalized() * radius;
      final Vector3 pt = pivot + radial;
      verts.addAll([pt.x, pt.y, pt.z, normal.x, normal.y, normal.z]);
    }

    for (int i = 1; i <= segments; i++) {
      indices.addAll([0, i, i + 1]);
    }

    return FlutterSceneSelectionBoxMesh(
      boxVertices: Float32List.fromList(verts),
      boxIndices: Uint16List.fromList(indices),
    );
  }
}
```

### Pipeline B: 2D Canvas Overlay & Fallback Painter (`flutter_paint_3d_engine.dart`)
Renders:
1. **Translucent Bounding Box (6 shaded faces + 12 crisp edges)** around the selected object or welded assembly.
2. **27 Interactive Snap Points + Hole Center Anchors**.
3. **SketchUp-Style 3D Protractor Ring (`Q` Key)** projected into 3D perspective with **color-coded axis alignment** (Red X, Green Y, Blue Z, Magenta Normal), **`15°` degree radial tick marks**, **reference & live arms**, and a **translucent swept angle pie sector**.
4. **SketchUp `+` Copy Badge & Live Value Control Box (VCB) HUD** in the bottom-right corner showing live Distance, Rotation Angle (`°`), or typed Array Multiplier (`*4`, `4x`, `/3`).

```dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' hide Colors;
import '../cad_kernel/cad_entity_and_assembly.dart';
import '../cad_kernel/cad_move_and_snap_controller.dart';

class CadSelectionAndSnapOverlayPainter extends CustomPainter {
  final CadMoveAndSnapController moveController;
  final Matrix4 viewMatrix;
  final Matrix4 projectionMatrix;

  CadSelectionAndSnapOverlayPainter({
    required this.moveController,
    required this.viewMatrix,
    required this.projectionMatrix,
    required Listenable repaintListenable,
  }) : super(repaint: repaintListenable);

  @override
  void paint(Canvas canvas, Size size) {
    final CadSceneEntity? selected = moveController.selectedEntity;
    if (selected == null) return;

    final Matrix4 vp = projectionMatrix * viewMatrix;

    // 1. Draw Translucent Bounding Box around selected part (or welded assembly)
    final Aabb3? groupBounds = moveController.getSelectedGroupWorldBounds();
    if (groupBounds != null) {
      _drawTranslucentBoundingBox(canvas, size, vp, groupBounds);
    }

    // 2. Draw Snap Points on the Selected Object
    _drawEntitySnapAnchors(canvas, size, vp, selected);

    // 3. Draw Move Tool Axis Lock Line + Travel Vector
    if (moveController.toolMode == CadToolMode.movingHover &&
        moveController.baseGrabPointWorld != null &&
        moveController.currentMovePointWorld != null) {
      _drawAxisLockAndMoveVector(
        canvas,
        size,
        vp,
        moveController.baseGrabPointWorld!,
        moveController.currentMovePointWorld!,
        moveController.axisLock,
        moveController.getLockedAxisVector(),
      );
    }

    // 4. Draw SketchUp 3D Protractor Gizmo when in Rotate (`Q`) modes
    if (moveController.toolMode == CadToolMode.rotateArmed ||
        moveController.toolMode == CadToolMode.rotatePickArm ||
        moveController.toolMode == CadToolMode.rotatingHover) {
      final Vector3 pivot = moveController.rotatePivotWorld ??
          moveController.protractorPreviewPointWorld;
      final Vector3 axis = moveController.rotatePivotWorld != null
          ? moveController.rotateAxisWorld
          : moveController.protractorPreviewNormalWorld;

      _draw3DProtractorGizmo(
        canvas: canvas,
        size: size,
        vp: vp,
        pivot: pivot,
        axisNormal: axis,
        radius: moveController.protractorRadiusWorld,
        refArmDir: moveController.rotateRefArmDirWorld,
        curArmDir: moveController.rotateCurrentArmDirWorld,
        angleRad: moveController.rotateCurrentAngleRad,
        isRotating: moveController.toolMode == CadToolMode.rotatingHover,
      );
    }

    // 5. Draw Hover Pickup Snap Badge or Magnetic Target Snap Badge
    if (moveController.hoveredPickupSnap != null &&
        (moveController.toolMode == CadToolMode.moveArmed ||
            moveController.toolMode == CadToolMode.rotateArmed)) {
      final Vector3 wPos = moveController.hoveredPickupSnap!
          .worldPosition(selected.worldTransform);
      final Vector2? sPt = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: wPos,
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      if (sPt != null) {
        _drawSketchUpSnapBadge(
          canvas,
          Offset(sPt.x, sPt.y),
          moveController.hoveredPickupSnap!.type,
          isTargetSnap: false,
        );
      }
    }

    if (moveController.activeSnapMatch != null) {
      final match = moveController.activeSnapMatch!;
      final Vector2? sPt = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: match.snappedWorldPosition,
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      if (sPt != null) {
        _drawSketchUpSnapBadge(
          canvas,
          Offset(sPt.x, sPt.y),
          match.targetSnap.type,
          isTargetSnap: true,
        );
      }
    }

    // 6. Draw Bottom-Right SketchUp Value Control Box (VCB) & Ctrl-Copy `+` Indicator
    _drawSketchUpVcbHud(canvas, size);
  }

  void _draw3DProtractorGizmo({
    required Canvas canvas,
    required Size size,
    required Matrix4 vp,
    required Vector3 pivot,
    required Vector3 axisNormal,
    required double radius,
    required Vector3? refArmDir,
    required Vector3? curArmDir,
    required double angleRad,
    required bool isRotating,
  }) {
    final Vector3 n = axisNormal.normalized();
    final Color protractorColor = _colorForNormal(n);

    // Build orthonormal basis (u, v) in the protractor plane
    final Vector3 u = (refArmDir != null && refArmDir.length2 > 1e-4)
        ? refArmDir.normalized()
        : n
            .cross(n.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0))
            .normalized();
    final Vector3 v = n.cross(u).normalized();

    final Vector2? center2D = CadMoveAndSnapController.projectWorldToScreen(
      worldPos: pivot,
      vpMatrix: vp,
      viewportWidth: size.width,
      viewportHeight: size.height,
    );
    if (center2D == null) return;
    final Offset centerOffset = Offset(center2D.x, center2D.y);

    // 1. If rotating, draw translucent swept pie-sector between 0° arm and current arm
    if (isRotating && refArmDir != null && angleRad.abs() > 1e-4) {
      final Path sectorPath = Path()..moveTo(centerOffset.dx, centerOffset.dy);
      const int fanSteps = 32;
      for (int i = 0; i <= fanSteps; i++) {
        final double a = angleRad * (i / fanSteps);
        final Vector3 pt3D = pivot + (u * cos(a) + v * sin(a)) * radius;
        final Vector2? sPt = CadMoveAndSnapController.projectWorldToScreen(
          worldPos: pt3D,
          vpMatrix: vp,
          viewportWidth: size.width,
          viewportHeight: size.height,
        );
        if (sPt != null) {
          sectorPath.lineTo(sPt.x, sPt.y);
        }
      }
      sectorPath.close();
      canvas.drawPath(
        sectorPath,
        Paint()
          ..color = protractorColor.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill,
      );
    }

    // 2. Draw outer & inner 3D protractor rings (72 segments)
    final Path outerRing = Path();
    bool started = false;
    const int ringSegs = 72;
    for (int i = 0; i <= ringSegs; i++) {
      final double a = (2.0 * pi * i) / ringSegs;
      final Vector3 pt3D = pivot + (u * cos(a) + v * sin(a)) * radius;
      final Vector2? sPt = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: pt3D,
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      if (sPt == null) continue;
      if (!started) {
        outerRing.moveTo(sPt.x, sPt.y);
        started = true;
      } else {
        outerRing.lineTo(sPt.x, sPt.y);
      }
    }

    final Paint ringPaint = Paint()
      ..color = protractorColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(outerRing, ringPaint);

    // 3. Draw 24 radial degree tick marks (every 15 degrees, just like SketchUp!)
    for (int tick = 0; tick < 24; tick++) {
      final double a = (2.0 * pi * tick) / 24.0;
      final bool isMajor90 = (tick % 6 == 0);
      final double innerFactor = isMajor90 ? 0.78 : 0.88;

      final Vector3 dir = u * cos(a) + v * sin(a);
      final Vector2? pIn = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: pivot + dir * (radius * innerFactor),
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      final Vector2? pOut = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: pivot + dir * radius,
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      if (pIn != null && pOut != null) {
        canvas.drawLine(
          Offset(pIn.x, pIn.y),
          Offset(pOut.x, pOut.y),
          Paint()
            ..color = protractorColor
            ..strokeWidth = isMajor90 ? 2.2 : 1.3,
        );
      }
    }

    // 4. Draw 0° Reference Arm and Live Current Arm
    if (refArmDir != null) {
      final Vector2? refTip = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: pivot + refArmDir * (radius * 1.25),
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      if (refTip != null) {
        _drawDashedLine(
          canvas,
          centerOffset,
          Offset(refTip.x, refTip.y),
          Paint()
            ..color = protractorColor
            ..strokeWidth = 1.8,
        );
      }
    }

    if (isRotating && curArmDir != null) {
      final Vector2? curTip = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: pivot + curArmDir * (radius * 1.25),
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      if (curTip != null) {
        canvas.drawLine(
          centerOffset,
          Offset(curTip.x, curTip.y),
          Paint()
            ..color = const Color(0xFFFFB300)
            ..strokeWidth = 2.4,
        );
      }
    }

    canvas.drawCircle(centerOffset, 4.0, Paint()..color = protractorColor);
  }

  Color _colorForNormal(Vector3 n) {
    if (n.x.abs() > 0.95) return const Color(0xFFE53935); // SketchUp Red (X)
    if (n.y.abs() > 0.95) return const Color(0xFF43A047); // SketchUp Green (Y)
    if (n.z.abs() > 0.95) return const Color(0xFF1E88E5); // SketchUp Blue (Z)
    return const Color(0xFFD81B60); // SketchUp Magenta (Custom Surface Normal)
  }

  void _drawSketchUpVcbHud(Canvas canvas, Size size) {
    String label = 'Ready (Click to Select, M = Move, Q = Rotate)';
    if (moveController.toolMode == CadToolMode.moveArmed) {
      label = moveController.isCopyMode
          ? 'Move [+ COPY]: Click base point (Ctrl toggles Copy)'
          : 'Move: Click base/snap point (Tap Ctrl for Copy)';
    } else if (moveController.toolMode == CadToolMode.movingHover) {
      final double dist = (moveController.currentMovePointWorld! -
              moveController.baseGrabPointWorld!)
          .length;
      final String copyTag = moveController.isCopyMode ? '[+ COPY] ' : '';
      label =
          '${copyTag}Distance: ${dist.toStringAsFixed(2)}  |  Arrows = Lock Axis';
    } else if (moveController.toolMode == CadToolMode.rotateArmed) {
      label =
          'Rotate (Q): Click pivot point (Arrows = Lock Red/Green/Blue Plane)';
    } else if (moveController.toolMode == CadToolMode.rotatePickArm) {
      label = 'Rotate (Q): Click 2nd point to set 0° reference arm';
    } else if (moveController.toolMode == CadToolMode.rotatingHover) {
      final String copyTag = moveController.isCopyMode ? '[+ COPY] ' : '';
      final String deg = moveController.rotateCurrentAngleDeg.toStringAsFixed(1);
      label = '${copyTag}Angle: $deg°  |  Type angle or click to place';
    } else if (moveController.canAcceptArrayInput) {
      label =
          'Copy Placed! Type *N (e.g. *4 or 4x) to Multiply Array, or /N (e.g. /4) to Divide + Enter';
    }

    if (moveController.vcbInputBuffer.isNotEmpty) {
      label = '$label   [ Input: ${moveController.vcbInputBuffer} ]';
    }

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final Rect pillRect = Rect.fromLTWH(
      size.width - tp.width - 32,
      size.height - 42,
      tp.width + 20,
      28,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, const Radius.circular(6)),
      Paint()..color = const Color(0xCC1E2730),
    );
    tp.paint(canvas, Offset(pillRect.left + 10, pillRect.top + 6));
  }

  void _drawTranslucentBoundingBox(
    Canvas canvas,
    Size size,
    Matrix4 vp,
    Aabb3 box,
  ) {
    final Vector3 min = box.min;
    final Vector3 max = box.max;

    final List<Vector3> corners3D = [
      Vector3(min.x, min.y, min.z),
      Vector3(max.x, min.y, min.z),
      Vector3(max.x, max.y, min.z),
      Vector3(min.x, max.y, min.z),
      Vector3(min.x, min.y, max.z),
      Vector3(max.x, min.y, max.z),
      Vector3(max.x, max.y, max.z),
      Vector3(min.x, max.y, max.z),
    ];

    final List<Offset?> corners2D = corners3D.map((c) {
      final pt = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: c,
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      return pt == null ? null : Offset(pt.x, pt.y);
    }).toList();

    if (corners2D.any((c) => c == null)) return;

    final List<List<int>> faces = [
      [0, 1, 2, 3],
      [4, 5, 6, 7],
      [0, 1, 5, 4],
      [2, 3, 7, 6],
      [1, 2, 6, 5],
      [0, 3, 7, 4],
    ];

    final Paint facePaint = Paint()
      ..color = const Color(0x222994F2)
      ..style = PaintingStyle.fill;

    for (final f in faces) {
      final Path path = Path()
        ..moveTo(corners2D[f[0]]!.dx, corners2D[f[0]]!.dy)
        ..lineTo(corners2D[f[1]]!.dx, corners2D[f[1]]!.dy)
        ..lineTo(corners2D[f[2]]!.dx, corners2D[f[2]]!.dy)
        ..lineTo(corners2D[f[3]]!.dx, corners2D[f[3]]!.dy)
        ..close();
      canvas.drawPath(path, facePaint);
    }

    const List<(int, int)> edges = [
      (0, 1), (1, 2), (2, 3), (3, 0),
      (4, 5), (5, 6), (6, 7), (7, 4),
      (0, 4), (1, 5), (2, 6), (3, 7),
    ];

    final Paint edgePaint = Paint()
      ..color = const Color(0xFF1E88E5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final (i0, i1) in edges) {
      canvas.drawLine(corners2D[i0]!, corners2D[i1]!, edgePaint);
    }
  }

  void _drawEntitySnapAnchors(
    Canvas canvas,
    Size size,
    Matrix4 vp,
    CadSceneEntity entity,
  ) {
    final Paint cornerPaint = Paint()
      ..color = const Color(0xFF43A047)
      ..style = PaintingStyle.fill;
    final Paint midPaint = Paint()
      ..color = const Color(0xFF00ACC1)
      ..style = PaintingStyle.fill;
    final Paint holePaint = Paint()
      ..color = const Color(0xFFD81B60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    for (final snap in entity.allSnapPoints) {
      final Vector3 wPos = snap.worldPosition(entity.worldTransform);
      final Vector2? sPt = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: wPos,
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      if (sPt == null) continue;
      final Offset center = Offset(sPt.x, sPt.y);

      switch (snap.type) {
        case CadSnapType.corner:
          canvas.drawCircle(center, 3.2, cornerPaint);
          break;
        case CadSnapType.edgeMidpoint:
          canvas.drawRect(
            Rect.fromCenter(center: center, width: 5.5, height: 5.5),
            midPaint,
          );
          break;
        case CadSnapType.holeCenter:
          canvas.drawCircle(center, 5.0, holePaint);
          canvas.drawLine(
            center.translate(-3, 0),
            center.translate(3, 0),
            holePaint,
          );
          canvas.drawLine(
            center.translate(0, -3),
            center.translate(0, 3),
            holePaint,
          );
          break;
        case CadSnapType.faceCenter:
        case CadSnapType.centroid:
        case CadSnapType.surfacePoint:
          canvas.drawCircle(
            center,
            2.5,
            Paint()..color = const Color(0x991E88E5),
          );
          break;
      }
    }
  }

  void _drawAxisLockAndMoveVector(
    Canvas canvas,
    Size size,
    Matrix4 vp,
    Vector3 baseWorld,
    Vector3 currentWorld,
    AxisLockMode lockMode,
    Vector3? lockedAxisDir,
  ) {
    if (lockMode != AxisLockMode.none && lockedAxisDir != null) {
      final Color axisColor = switch (lockMode) {
        AxisLockMode.xRed => const Color(0xFFE53935),
        AxisLockMode.yGreen => const Color(0xFF43A047),
        AxisLockMode.zBlue => const Color(0xFF1E88E5),
        AxisLockMode.localNormal => const Color(0xFFD81B60),
        AxisLockMode.none => const Color(0xFF90A4AE),
      };

      final Vector3 pStart = baseWorld - lockedAxisDir * 500.0;
      final Vector3 pEnd = baseWorld + lockedAxisDir * 500.0;

      final Vector2? s0 = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: pStart,
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );
      final Vector2? s1 = CadMoveAndSnapController.projectWorldToScreen(
        worldPos: pEnd,
        vpMatrix: vp,
        viewportWidth: size.width,
        viewportHeight: size.height,
      );

      if (s0 != null && s1 != null) {
        _drawDashedLine(
          canvas,
          Offset(s0.x, s0.y),
          Offset(s1.x, s1.y),
          Paint()
            ..color = axisColor
            ..strokeWidth = 2.0,
        );
      }
    }

    final Vector2? bScreen = CadMoveAndSnapController.projectWorldToScreen(
      worldPos: baseWorld,
      vpMatrix: vp,
      viewportWidth: size.width,
      viewportHeight: size.height,
    );
    final Vector2? cScreen = CadMoveAndSnapController.projectWorldToScreen(
      worldPos: currentWorld,
      vpMatrix: vp,
      viewportWidth: size.width,
      viewportHeight: size.height,
    );

    if (bScreen != null && cScreen != null) {
      canvas.drawLine(
        Offset(bScreen.x, bScreen.y),
        Offset(cScreen.x, cScreen.y),
        Paint()
          ..color = const Color(0xFFFFB300)
          ..strokeWidth = 2.2,
      );
    }
  }

  void _drawSketchUpSnapBadge(
    Canvas canvas,
    Offset screenPos,
    CadSnapType type, {
    required bool isTargetSnap,
  }) {
    final Color badgeColor =
        isTargetSnap ? const Color(0xFF00E676) : const Color(0xFFFFC107);

    final Paint strokePaint = Paint()
      ..color = badgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final Paint fillPaint = Paint()
      ..color = badgeColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    if (type == CadSnapType.edgeMidpoint) {
      final Rect r = Rect.fromCenter(center: screenPos, width: 13, height: 13);
      canvas.drawRect(r, fillPaint);
      canvas.drawRect(r, strokePaint);
    } else if (type == CadSnapType.holeCenter ||
        type == CadSnapType.faceCenter) {
      final Path diamond = Path()
        ..moveTo(screenPos.dx, screenPos.dy - 8)
        ..lineTo(screenPos.dx + 8, screenPos.dy)
        ..lineTo(screenPos.dx, screenPos.dy + 8)
        ..lineTo(screenPos.dx - 8, screenPos.dy)
        ..close();
      canvas.drawPath(diamond, fillPaint);
      canvas.drawPath(diamond, strokePaint);
    } else {
      canvas.drawCircle(screenPos, 7.0, fillPaint);
      canvas.drawCircle(screenPos, 7.0, strokePaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashLength = 7.0;
    const double gapLength = 5.0;
    final Offset delta = p2 - p1;
    final double totalDist = delta.distance;
    if (totalDist < 1.0) return;
    final Offset dir = delta / totalDist;

    double curr = 0.0;
    while (curr < totalDist) {
      final double end = (curr + dashLength).clamp(0.0, totalDist);
      canvas.drawLine(p1 + dir * curr, p1 + dir * end, paint);
      curr += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant CadSelectionAndSnapOverlayPainter oldDelegate) =>
      true;
}
```

## 7. Phase 5: Interactive Viewport Widget Wiring (Zero-`setState` 120 FPS Loop)

### `lib/ui/cad_interactive_viewport.dart`
```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../cad_kernel/cad_move_and_snap_controller.dart';
import 'cad_selection_and_snap_overlay_painter.dart';

class CadInteractiveViewport extends StatefulWidget {
  final CadMoveAndSnapController moveController;
  final dynamic cameraController; // CadCameraController from v2.0

  const CadInteractiveViewport({
    super.key,
    required this.moveController,
    required this.cameraController,
  });

  @override
  State<CadInteractiveViewport> createState() => _CadInteractiveViewportState();
}

class _CadInteractiveViewportState extends State<CadInteractiveViewport> {
  final FocusNode _viewportFocusNode = FocusNode();

  @override
  void dispose() {
    _viewportFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        widget.cameraController.updateViewport(width, height);

        return Focus(
          focusNode: _viewportFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            final handled = widget.moveController.handleKeyEvent(event);
            return handled ? KeyEventResult.handled : KeyEventResult.ignored;
          },
          child: MouseRegion(
            // Crucial for SketchUp workflow: both Move ('M') and Rotate ('Q') update on HOVER!
            onHover: (PointerHoverEvent event) {
              widget.moveController.onViewportHover(
                screenX: event.localPosition.dx,
                screenY: event.localPosition.dy,
                viewportWidth: width,
                viewportHeight: height,
                viewMatrix: widget.cameraController.viewMatrix,
                projectionMatrix: widget.cameraController.projectionMatrix,
              );
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails details) {
                _viewportFocusNode.requestFocus();
                widget.moveController.onViewportClick(
                  screenX: details.localPosition.dx,
                  screenY: details.localPosition.dy,
                  viewportWidth: width,
                  viewportHeight: height,
                  viewMatrix: widget.cameraController.viewMatrix,
                  projectionMatrix: widget.cameraController.projectionMatrix,
                );
              },
              // Camera orbit & pan remain available even while moving or rotating an object!
              onScaleUpdate: (ScaleUpdateDetails details) {
                if (details.pointerCount == 1) {
                  widget.cameraController.onOrbitDelta(
                    details.focalPointDelta.dx,
                    details.focalPointDelta.dy,
                  );
                } else if (details.pointerCount >= 2) {
                  widget.cameraController.onPanDelta(
                    details.focalPointDelta.dx,
                    details.focalPointDelta.dy,
                  );
                  widget.cameraController.onZoomScale(details.scale);
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Layer 1: Primary 3D Scene (flutter_scene GPU or Canvas 3D Fallback)
                  // Repaints via Listenable.merge([cameraController, moveController])
                  const SizedBox.expand(),

                  // Layer 2: Bounding Box, 27 Snaps, R/G/B Axis Locks, 3D Protractor & VCB HUD
                  CustomPaint(
                    painter: CadSelectionAndSnapOverlayPainter(
                      moveController: widget.moveController,
                      viewMatrix: widget.cameraController.viewMatrix,
                      projectionMatrix: widget.cameraController.projectionMatrix,
                      repaintListenable: Listenable.merge([
                        widget.cameraController,
                        widget.moveController,
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

## 8. Final Verification Checklist for the Coding Agent
- [ ] **Single-Precision `vector_math` Verified:** All files import `package:vector_math/vector_math.dart` and never `vector_math_64.dart`.
- [ ] **Through-Holes Ignored During Ray-Picking:** Clicking inside a bore hole created by `CadPolygonTriangulator` passes cleanly through the hole and picks the object behind it via Möller–Trumbore triangle intersection.
- [ ] **True SketchUp Move (`M`) & Protractor Rotate (`Q`) Workflows:** Pressing `M` uses 2 clicks (`Click Base -> Hover Move -> Click Place`); pressing `Q` uses 3 clicks (`Click Pivot -> Click 0° Reference Arm -> Hover Rotate with 15° Tick Snaps -> Click Place`).
- [ ] **Arrow-Key Axis Locking Active in Both Move & Rotate:** Pressing `→` (Red X), `←` (Green Y), `↑` (Blue Z), or `↓` (Magenta Surface Normal) locks either the translation line or the 3D protractor normal plane.
- [ ] **Zero-Copy `Ctrl` Duplication & Live `*N` / `/N` Arrays:** Tapping `Ctrl` toggles `isCopyMode` (`+` badge) using shared `Float32List` GPU vertex buffers; typing `*4`, `4x`, or `/4` + `Enter` after placing a copy generates linear or radial arrays and supports live count replacement.
- [ ] **Magnetic Snapping & Assembly Welding:** Moving near another object's snap point snaps the active part and joins/welds the parts into a shared `assemblyGroupId` on the final click.