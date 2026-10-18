# TruFold Studio: Onshape Sketcher, B-Rep + GPU Bridge, Feature Tree & CSG Cut Master Walkthrough

**Repository:** `Intelidan/trufold_studio`  
**Target Architecture:** Hybrid Parametric B-Rep Topology + Hardware GPU Z-Buffer (`flutter_scene` / `flutter_gpu`) + `CustomPaint` 2D Vector Overlay Pass.

---

## 0. Agent Execution Rules & Coding Tips (READ FIRST)

1. **Single-Precision Math Only:** Always import `package:vector_math/vector_math.dart` (`Vector2`, `Vector3`, `Matrix4`, `Float32List`). Never import `vector_math_64.dart`.
2. **Do Not Use CPU Painter's Algorithm for 3D Solids:** Keep all 3D solid parts and intersecting boolean preview prisms in the hardware Z-buffered GPU pass (`flutter_scene` / `flutter_gpu`). Never attempt to depth-sort or polygon-split 3D solid triangles in `CustomPainter`.
3. **2D Sketch Plane Coordinate Authority:** Perform 100% of sketch constraint solving, witness-line perpendicularity, 2-entity relational distances, and polygon rigid-body translations in **2D Sketch Plane `(u, v)` coordinates (`Vector2`)**. Only project to 3D/Screen coordinates inside `paint()` using the shared `viewProjectionMatrix`.
4. **X-Ray Hidden Snap Point Hovering:** Hole center points are stored analytically on each `AssemblyPart`. During hover (`MouseRegion.onHover`), project all candidate hole center points to screen space **without** Z-buffer culling so the user can hover and snap to hidden hole centers on back walls or inside C-channels when the cursor is within `18.0 px`.
5. **120 FPS Zero-Allocation Hover Loop:** Never call `setState()` during pointer hover/move events; mutate `AssemblyStudioViewModel` fields and trigger `notifyListeners()` for `CustomPainter` repaint.

---

## 1. NEW FILE: B-Rep Face & Part Border Topology Bridge
**File to Create:** `lib/assembly_studio/engine/sketch/cad_brep_topology_bridge.dart`

### Purpose
Eliminates slow "triangle soup" reverse-engineering by giving every 3D part face an explicit **B-Rep Planar Face descriptor** with its exact outer boundary edges (`imprintedBorders`), inner hole loops, and local 2D `(u, v)` coordinate frame. When a sketch is opened on a 3D part face, its outer borders and hole centers are immediately available as selectable, dimensionable 2D reference geometry (`SS5`).

```dart
import 'dart:math' as math;
import 'package:vector_math/vector_math.dart';
import '../../models/assembly_part.dart';

class CadImprintedBorderEdge2D {
  final String id;
  final Vector2 start2D;
  final Vector2 end2D;
  final bool isFixedReference;

  const CadImprintedBorderEdge2D({
    required this.id,
    required this.start2D,
    required this.end2D,
    this.isFixedReference = true,
  });

  Vector2 get midpoint2D => (start2D + end2D) * 0.5;
  Vector2 get directionUnit {
    final d = end2D - start2D;
    final len = d.length;
    return len > 1e-5 ? d / len : Vector2(1.0, 0.0);
  }
}

class CadImprintedHole2D {
  final String id;
  final Vector2 center2D;
  final double diameterMm;

  const CadImprintedHole2D({
    required this.id,
    required this.center2D,
    required this.diameterMm,
  });
}

class CadPlanarFaceBRep {
  final String faceId;
  final String hostPartId;
  final Vector3 originWorld;
  final Vector3 uAxisWorld;
  final Vector3 vAxisWorld;
  final Vector3 normalWorld;
  final List<CadImprintedBorderEdge2D> outerBorderEdges2D;
  final List<CadImprintedHole2D> holes2D;

  const CadPlanarFaceBRep({
    required this.faceId,
    required this.hostPartId,
    required this.originWorld,
    required this.uAxisWorld,
    required this.vAxisWorld,
    required this.normalWorld,
    required this.outerBorderEdges2D,
    required this.holes2D,
  });

  Vector2 worldToSketch2D(Vector3 worldPt) {
    final Vector3 rel = worldPt - originWorld;
    return Vector2(rel.dot(uAxisWorld), rel.dot(vAxisWorld));
  }

  Vector3 sketch2DToWorld(Vector2 pt2D, {double normalOffsetMm = 0.0}) {
    return originWorld +
        (uAxisWorld * pt2D.x) +
        (vAxisWorld * pt2D.y) +
        (normalWorld * normalOffsetMm);
  }

  /// Extracts the exact rectangular/polygonal outer border edges and hole centers
  /// of the host AssemblyPart face so Sketch Mode can dimension directly to part borders (SS5).
  static CadPlanarFaceBRep extractFromPartFace({
    required AssemblyPart part,
    required Vector3 planeOriginWorld,
    required Vector3 planeNormalWorld,
    required Vector3 planeUAxisWorld,
    required Vector3 planeVAxisWorld,
  }) {
    final List<CadImprintedBorderEdge2D> borders = <CadImprintedBorderEdge2D>[];
    final List<CadImprintedHole2D> holes = <CadImprintedHole2D>[];

    Vector2 to2D(Vector3 w) {
      final rel = w - planeOriginWorld;
      return Vector2(rel.dot(planeUAxisWorld), rel.dot(planeVAxisWorld));
    }

    // Project part's oriented bounding box / topological coplanar boundary vertices onto (u, v)
    final List<Vector3> cornerPts = part.getWorldCorners();
    if (cornerPts.isNotEmpty) {
      double minU = double.infinity, maxU = -double.infinity;
      double minV = double.infinity, maxV = -double.infinity;
      for (final c in cornerPts) {
        final p2 = to2D(c);
        minU = math.min(minU, p2.x);
        maxU = math.max(maxU, p2.x);
        minV = math.min(minV, p2.y);
        maxV = math.max(maxV, p2.y);
      }
      final b0 = Vector2(minU, minV);
      final b1 = Vector2(maxU, minV);
      final b2 = Vector2(maxU, maxV);
      final b3 = Vector2(minU, maxV);

      borders.addAll([
        CadImprintedBorderEdge2D(id: 'border_bottom_${part.id}', start2D: b0, end2D: b1),
        CadImprintedBorderEdge2D(id: 'border_right_${part.id}', start2D: b1, end2D: b2),
        CadImprintedBorderEdge2D(id: 'border_top_${part.id}', start2D: b2, end2D: b3),
        CadImprintedBorderEdge2D(id: 'border_left_${part.id}', start2D: b3, end2D: b0),
      ]);
    }

    // Imprint existing hole centers on or parallel to this face
    for (int i = 0; i < part.holeCentersWorld.length; i++) {
      final Vector3 hc = part.holeCentersWorld[i];
      holes.add(
        CadImprintedHole2D(
          id: 'imprinted_hole_${part.id}_$i',
          center2D: to2D(hc),
          diameterMm: part.holeDiametersMm.length > i ? part.holeDiametersMm[i] : 12.0,
        ),
      );
    }

    return CadPlanarFaceBRep(
      faceId: 'face_${part.id}',
      hostPartId: part.id,
      originWorld: planeOriginWorld,
      uAxisWorld: planeUAxisWorld.normalized(),
      vAxisWorld: planeVAxisWorld.normalized(),
      normalWorld: planeNormalWorld.normalized(),
      outerBorderEdges2D: borders,
      holes2D: holes,
    );
  }
}
```

---

## 2. NEW FILE: Onshape Studio Camera-Locked Lighting & Shine Helper
**File to Create:** `lib/assembly_studio/views/widgets/viewport/painters/cad_gpu_studio_lighting_helper.dart`

### Purpose
Fixes **Issue 3 (`SS1` pitch-dark opposite faces)** and provides Onshape/SolidWorks satin metallic shading and specular shine. By locking the key light, fill light, and specular highlight to the **camera view basis** with a two-sided normal flip (`if (n.dot(v) < 0) n = -n`), opposite faces of C-channels and rails never turn black when orbiting.

```dart
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

    final int r = (baseAlbedo.red * diffuseFactor + 255.0 * specular).round().clamp(0, 255);
    final int g = (baseAlbedo.green * diffuseFactor + 255.0 * specular).round().clamp(0, 255);
    final int b = (baseAlbedo.blue * diffuseFactor + 255.0 * specular).round().clamp(0, 255);

    return Color.fromARGB(baseAlbedo.alpha, r, g, b);
  }
}
```
> **Agent Tip:** Call `CadGpuStudioLightingHelper.shadeCadSurface(...)` in `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (for all solid face & extrude prism rendering) and in `lib/sheet_metal_studio/engine/flutter_scene_cad_mesh_builder.dart` when baking vertex/face colors.

---

## 3. Fix Hole Center Point Clutter & Enable X-Ray Hover Snapping
**Files to Modify:**
- `lib/assembly_studio/views/widgets/viewport/painters/assembly_magnetic_spots_painter.dart`
- `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart`
- `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`

### Problem (First Request Item 1 & Item 7)
1. Selecting a multi-part 3D model highlights **all** hole center points in amber (`SS1`).
2. `SS2` shows dozens of distracting cyan/amber/purple dots across the viewport.
3. Requirement: Only explicitly selected hole center points should stay highlighted in amber, while hovering the mouse near **any** hole center point (including hidden ones behind faces) should highlight it for snapping.

### Exact Code Changes
1. In `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`, ensure hole center selection is tracked separately from part selection:
   ```dart
   final Set<String> selectedHoleCenterIds = <String>{};
   String? hoveredHoleCenterId;
   ```
   When `selectPart()` or `selectAllParts()` is called, **do not** populate `selectedHoleCenterIds`.
2. In `lib/assembly_studio/views/widgets/viewport/painters/assembly_magnetic_spots_painter.dart`:
   Replace the unconditional dot-rendering loop with proximity + explicit selection filtering:
   ```dart
   static const double kSnapProximityRadiusPx = 18.0;

   void paintHoleCenterSnaps(Canvas canvas, Size size) {
     final Offset? cursorPos = viewModel.lastMouseScreenOffset;

     for (final HoleSnapSpot spot in viewModel.allHoleCenterSpots) {
       final bool isExplicitlySelected =
           viewModel.selectedHoleCenterIds.contains(spot.id);

       // Project 3D hole center to 2D screen without Z-buffer occlusion
       // so hidden hole centers remain hover-snappable!
       final Offset? screenPt = viewModel.projectWorldToScreen(spot.worldCenter, size);
       if (screenPt == null) continue;

       final double distToCursor = cursorPos != null
           ? (screenPt - cursorPos).distance
           : double.infinity;
       final bool isHoveredForSnap = distToCursor <= kSnapProximityRadiusPx;

       // CRITICAL: Never draw unselected hole center dots unless the mouse is within 18px!
       if (!isExplicitlySelected && !isHoveredForSnap) {
         continue;
       }

       final Paint dotPaint = Paint()
         ..color = isExplicitlySelected
             ? const Color(0xFFFFAB00) // Amber for explicitly selected hole center
             : const Color(0xFF00E5FF) // Cyan ring/dot for proximity snap target
         ..style = PaintingStyle.fill;

       canvas.drawCircle(screenPt, isExplicitlySelected ? 4.5 : 4.0, dotPaint);

       if (isHoveredForSnap) {
         final Paint ringPaint = Paint()
           ..color = const Color(0xFF111111)
           ..strokeWidth = 1.2
           ..style = PaintingStyle.stroke;
         canvas.drawCircle(screenPt, 6.0, ringPaint);
       }
     }
   }
   ```
3. **Eliminate `SS2` Dot Clutter in `assembly_sketch_overlay_painter.dart` & `assembly_3d_viewport.dart`:**
   - Wrap the 27-point OBB bounding-box anchor painter in:
     ```dart
     if (viewModel.activeTool == AssemblyStudioTool.move && viewModel.isDraggingMoveGizmo) {
       _paint27PointBoundingBoxAnchors(canvas, size);
     }
     ```
   - In `assembly_extrude_engine.dart`, when tessellating a circular extrusion (`32` segments), **do not** add the 32 perimeter ring vertices to `part.snapPoints`. Only add the **top circle center** and **bottom circle center**.
   - In `assembly_3d_surface_sketch_painter.dart`, only draw vertex grip dots for a sketch entity if `entity.id == viewModel.selectedSketchEntityId || entity.id == viewModel.hoveredSketchEntityId`.

---

## 4. Lock Camera Position/Zoom & Prevent Sketch Mode Auto-Exit
**Files to Modify:**
- `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`
- `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart`

### Problem (First Request Items 2 & 4)
1. Activating Sketch Mode zooms the camera out; deactivating it zooms the camera in.
2. Editing a sketch entity (resizing, dragging, or editing a dimension) turns off Sketch Mode automatically.

### Exact Code Changes
1. In `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`:
   - Locate `enterSketchMode` / `activateSurfaceSketch` and `exitSketchMode` / `finishSketch` / `deactivateSurfaceSketch`.
   - **Delete** all lines that modify `_cameraDistance`, `_cameraZoom`, `_cameraTarget`, `_cameraPosition`, or restore `_preSketchCameraDistance`.
   - Camera position and zoom must remain **100% unchanged** when entering or leaving Sketch Mode, or when switching sketch tools (`Line`, `Rectangle`, `Circle`, `Polygon`, `Dimension`, `Extrude`).
   - Only align the camera orientation if the user explicitly presses the **`Normal (N)`** button inside `assembly_onshape_sketch_dialog.dart`, and even then, keep `_cameraDistance` constant.
2. **Prevent Sketch Mode Auto-Off on Entity Edit:**
   - Search `assembly_studio_viewmodel.dart` and `assembly_3d_viewport.dart` for every assignment `_isSketchModeActive = false` (or `_activeSketch = null`).
   - Remove any `_isSketchModeActive = false` inside:
     - `updateSketchEntity()`
     - `applyDimensionEdit()`
     - `onViewportPointerUp()`
     - `selectPart()` (when `isSketchModeActive` is true, clicking in the viewport must route exclusively to `surfaceSketchEngine.handlePointerDown()`, never to global 3D part selection).
   - `isSketchModeActive` may **only** be set to `false` inside:
     - `confirmActiveSketch()` (Green Checkmark button in `AssemblyOnshapeSketchDialog`)
     - `cancelActiveSketch()` (Red Cancel X button in `AssemblyOnshapeSketchDialog`)

---

## 5. Make `AssemblyExtrudeDialog` & `AssemblyOnshapeSketchDialog` Draggable
**Files to Modify:**
- `lib/assembly_studio/views/widgets/viewport/overlays/draggable_cad_dialog.dart`
- `lib/assembly_studio/views/widgets/viewport/overlays/assembly_extrude_dialog.dart`
- `lib/assembly_studio/views/widgets/viewport/overlays/assembly_onshape_sketch_dialog.dart`
- `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart`

### Exact Code Changes
In `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart`, replace any static `Positioned(top: ..., left: ..., child: AssemblyExtrudeDialog(...))` with `DraggableCadDialog`:
```dart
if (viewModel.isExtrudeDialogOpen)
  DraggableCadDialog(
    initialOffset: const Offset(310, 68),
    width: 310,
    child: AssemblyExtrudeDialog(viewModel: viewModel),
  ),
if (viewModel.isSketchModeActive)
  DraggableCadDialog(
    initialOffset: const Offset(56, 56),
    width: 280,
    child: AssemblyOnshapeSketchDialog(viewModel: viewModel),
  ),
```
Ensure `DraggableCadDialog` uses `GestureDetector(onPanUpdate: (d) => setState(() => _offset += d.delta))` so the user can drag the Extrude dialog box anywhere out of the way of the 3D model.

---

## 6. Unified Onshape Feature Tree, Single/Double Click & Inline Rename
**Files to Modify:**
- `lib/assembly_studio/models/assembly_timeline_item.dart`
- `lib/assembly_studio/views/widgets/assembly_browser_tree.dart`
- `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`

### Problem (Second Request Items 2 & 6 — `SS3` & `SS6`)
1. `assembly_browser_tree.dart` separates `Sketches` from solid steps and does not display `Extrude 1`, `Extrude 2`, `Tab 1`, `Mirror 1` in a unified chronological `Features (N)` tree like Onshape (`SS6`).
2. Single-clicking a sketch opens Sketch Mode instead of highlighting the sketch in orange (`SS3`).
3. Clicking an Extrude/solid step in the tree does not highlight that step on the 3D model and open its property dialog (`SS6`).
4. Sketch and feature names are not editable.

### Exact Code Changes
1. **Update `lib/assembly_studio/models/assembly_timeline_item.dart`:**
   Ensure every parametric operation (`Sketch 1`, `Extrude 1`, `Extrude 2`, `Tab 1`, `Mirror 1`, `Modify joint 1`) is stored as an `AssemblyTimelineItem` in `document.timelineItems`:
   ```dart
   enum TimelineFeatureType {
     sketch,
     extrude,
     tab,
     flange,
     mirror,
     modifyJoint,
     sheetMetalModel,
   }

   class AssemblyTimelineItem {
     final String id;
     String name; // Editable name
     final TimelineFeatureType type;
     final String? sketchId;
     final Set<String> targetEntityIds; // Specific sketch entity IDs for this Extrude/Cut
     ExtrudeFeatureConfig? extrudeConfig;
     bool isVisible;
     bool isSuppressed;
     bool hasError;

     AssemblyTimelineItem({
       required this.id,
       required this.name,
       required this.type,
       this.sketchId,
       Set<String>? targetEntityIds,
       this.extrudeConfig,
       this.isVisible = true,
       this.isSuppressed = false,
       this.hasError = false,
     }) : targetEntityIds = targetEntityIds ?? <String>{};
   }
   ```
2. **Update `lib/assembly_studio/views/widgets/assembly_browser_tree.dart`:**
   - Remove the separate `Sketches` folder and remove the `[2 3D]` and `[Closed]` badges on sketch rows.
   - Render a unified **`Features (${items.length})`** tree at the top (containing `Default geometry` followed by all chronological `AssemblyTimelineItem`s: `Sketch 1`, `Extrude 1`, `Sketch 2`, `Extrude 2`, etc.), and **`Parts (${parts.length})`** below it (`SS3` & `SS6`).
   - Wire click handlers on each `AssemblyTimelineItem` row:
     - **`onTap` (Single Click):**
       - If `item.type == TimelineFeatureType.sketch`: calls `viewModel.highlightSketchFromTree(item.sketchId!)`. **Does NOT enter Sketch Mode.** Draws `Sketch 1` on the 3D model with Onshape's `#FF9800` orange border and `#44FFB74D` translucent amber fill (`SS3`).
       - If `item.type == TimelineFeatureType.extrude` (or `tab`, `mirror`): calls `viewModel.selectAndEditFeatureStep(item.id)`, which highlights the affected 3D faces/cut walls in orange on the model AND opens `AssemblyExtrudeDialog` populated with that step's live parameters (`SS6`).
     - **`onDoubleTap` (Double Click):**
       - If `item.type == TimelineFeatureType.sketch`: calls `viewModel.enterSketchMode(item.sketchId!)` (`SS4`).
   - **Editable Names:**
     - Add inline `TextField` renaming to each row in `assembly_browser_tree.dart` (triggered via rename icon or right-click) AND make the title inside `assembly_onshape_sketch_dialog.dart` / `assembly_extrude_dialog.dart` an editable `TextField` bound to `item.name`.

---

## 7. Onshape Sketch Visuals, Orthogonal Witness Lines, Multi-Entity & Border Dimensions, Driven Grey Dimensions & Rigid Polygons
**Files to Modify:**
- `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart`
- `lib/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart`
- `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart`

### 7.1 Crisp Black Sketch Borders & Shaded Profiles (Item 3 / `SS2` vs `SS4`)
In `assembly_3d_surface_sketch_painter.dart`:
- Change default constrained/defined entity stroke color from cyan to **Onshape Crisp Black `const Color(0xFF111111)`** (`strokeWidth: 1.65`).
- Under-constrained entities: `const Color(0xFF1565C0)` (`strokeWidth: 1.65`).
- Selected or tree-highlighted entities: `const Color(0xFFFF9800)` (`strokeWidth: 2.4`).
- Fill all closed profiles (`circle`, `rectangle`, `closed polygon`) with `const Color(0x3890A4AE)` (or `const Color(0x44FFB74D)` when highlighted from the feature tree as in `SS3`).

### 7.2 Strictly Parallel/Perpendicular Witness Lines, Draggable Dimensions & Mouse-Driven Orientation (Item 3 / `SS2`)
In `assembly_3d_surface_sketch_painter.dart` and `assembly_surface_sketch_engine.dart`:
1. **Fix Slanted Witness Lines (`SS2` right red circle):**
   Compute witness lines in 2D sketch coordinates `(u, v)` before projecting to 3D screen space:
   - For an **Aligned** dimension along segment $P_1 \to P_2$, let $\hat{d} = \frac{P_2 - P_1}{\Vert{}P_2 - P_1\Vert{}}$ and the exact perpendicular normal be $\hat{n} = (-\hat{d}_y, \hat{d}_x)$.
   - Witness line 1 runs from $P_1$ to $P_1 + \hat{n} \cdot s$, and Witness line 2 runs from $P_2$ to $P_2 + \hat{n} \cdot s$, where $s = (M - P_1) \cdot \hat{n}$ is the signed perpendicular offset of the dimension label $M$.
   - Project the 4 resulting 2D points to screen space via `projectSketch2DToScreen()`. This guarantees witness lines are **100% perpendicular to the measured edge** and never slanted.
2. **Mouse Movement Defines Dimension Orientation During Creation:**
   While placing a dimension between $P_1$ and $P_2$, inspect the live 2D cursor position `cursor2D`:
   - If `cursor2D.x` is outside $[\min(x_1, x_2), \max(x_1, x_2)]$ while `cursor2D.y` is within the Y-span $\rightarrow$ switch to **Vertical ($\Delta Y$)** orientation.
   - If `cursor2D.y` is outside $[\min(y_1, y_2), \max(y_1, y_2)]$ while `cursor2D.x` is within the X-span $\rightarrow$ switch to **Horizontal ($\Delta X$)** orientation.
   - Otherwise $\rightarrow$ **Aligned ($L$)** orientation.
3. **Draggable Dimension Lines:**
   In `assembly_surface_sketch_engine.dart`, hit-test dimension labels/lines in `onPointerDown`. When dragging a dimension (`_draggingDimensionId != null`), update `dim.labelOffset2D = cursor2D` in `onPointerMove`.
4. **Fix Rectangle Disappearing 2nd Dimension & Pentagon Missing Dimension (`SS2`):**
   - **Rectangle:** Store `widthDimId` and `heightDimId` on the rectangle entity. When `applyDimensionValue(dimId, newValue)` runs, only update the edge pair corresponding to `dimId` and **never clear or recreate** the sibling dimension.
   - **Pentagon / Polygon:** When creating a regular polygon in `assembly_surface_sketch_engine.dart`, automatically attach an inscribed dashed construction circle and a default `Ø` diameter dimension (`SketchDimensionType.diameter`) so the pentagon/hexagon always displays its diameter dimension and scales radially when edited.

### 7.3 Relational Dimensions Between 2 Entities or Part Borders + Grey Driven Dimensions (Item 4 / `SS5`)
In `assembly_surface_sketch_engine.dart` and `assembly_sketch_constraint_solver.dart`:
1. **Two-Entity & Border Selection in Dimension Tool:**
   When the Dimension tool is active:
   - **Click 1** selects `anchorA` (any sketch vertex, line, circle/arc center, polygon centroid/midpoint, OR any `CadImprintedBorderEdge2D` / `CadImprintedHole2D` from `CadPlanarFaceBRep`).
   - **Click 2** on a second entity/border selects `anchorB` and creates a **2-Entity Relational Dimension**:
     - `Center/Point` to `Center/Point` $\rightarrow$ Linear distance (`99` in `SS5`).
     - `Center/Point` to `Line / Object Border` $\rightarrow$ Perpendicular distance (`60`, `65`, `75`, `76.8`, `90` in `SS5`).
     - `Line` to `Non-Parallel Line / Object Border` $\rightarrow$ Angular dimension in degrees (`27°` in `SS5`).
2. **Driven (Non-Editable Grey) Dimensions (`75` & `76.8` in `SS5`):**
   - Add `bool isDriven` to your dimension model.
   - If both `anchorA` and `anchorB` are already fully constrained (e.g., two fixed object borders, or a geometry whose position is already locked by driving dimensions), set `dim.isDriven = true`.
   - In `assembly_3d_surface_sketch_painter.dart`, render `isDriven == true` dimensions in **Grey (`const Color(0xFF8C96A0)`)** and disable the double-click edit popover on them while dynamically updating their displayed measurement whenever the sketch changes.

### 7.4 Rigid Closed Polygon / Polyline Constraint & Translation (Item 5)
In `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart`:
1. Expose **3 selectable dimension anchors** for every closed polygon/polyline:
   - **Line Endpoints (`vertex_i`)**
   - **Line Centers (`midpoint_i = (v_i + v_{i+1}) * 0.5`)**
   - **Polygon Center (`centroid = sum(v_i) / N`)**
2. When a dimensional constraint between an external reference (such as an object border or another entity) and **any** vertex, edge midpoint, or centroid of a closed polygon is edited by $\Delta \mathbf{u} = (\Delta u, \Delta v)$:
   ```dart
   void translateClosedPolygonRigidly(
     SketchPolygonEntity poly,
     Vector2 delta2D,
   ) {
     // Translate ALL vertices of the closed polygon/polyline together as a rigid body
     for (int i = 0; i < poly.vertices2D.length; i++) {
       poly.vertices2D[i] = poly.vertices2D[i] + delta2D;
     }
     poly.recomputeCentroid();
   }
   ```
   This guarantees the entire closed polygon moves as a single unit without distorting its sides.

---

## 8. Isolate Per-Entity Extrudes, Fix CSG Pass-Through Cut & Cancel Previous Operation on Edit
**Files to Modify:**
- `lib/assembly_studio/engine/sketch/assembly_extrude_engine.dart`
- `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`
- `lib/sketch_draft_files/math_and_processing/cad_boolean_engine.dart`

### Problem (First Request Item 6 & Second Request Item 7 — `SS2`, `SS6`, `SS7`, `SS8`)
1. Extruding or cutting one sketch entity applies the same extrude/cut to **all** entities in that sketch (`SS2`).
2. Selecting `Cut` (`SS7`) creates a new solid cylinder body (`Extruded Body 1` in `SS7` & `SS8`) instead of cutting a pass-through hole in `Right Side Rail`.
3. Re-opening a sketch or editing an existing extrude operation (`Join` / `New Body` $\to$ `Cut`) does not cancel the previous operation.

### Exact Code Changes (`lib/assembly_studio/engine/sketch/assembly_extrude_engine.dart`)

#### 8.1 Per-Entity Profile Isolation (`targetEntityIds`)
In `AssemblyExtrudeEngine`:
- Never loop over `sketch.entities` unconditionally.
- Require `Set<String> targetEntityIds` in `ExtrudeFeatureConfig`.
- Only extrude/cut the specific sketch entities whose `id` is inside `config.targetEntityIds`:
```dart
final List<SketchEntity> targetEntities = sketch.entities
    .where((e) => config.targetEntityIds.contains(e.id) && e.isClosedLoop)
    .toList();
```

#### 8.2 True Pass-Through Boolean Cut (`ExtrudeOperation.cut`)
When `config.operation == ExtrudeOperation.cut`:
1. **Do NOT create or add an `Extruded Body` to `document.parts`!**
2. Build the 3D cutter prism in world space with a `+0.1 mm` pierce epsilon so coplanar faces on thin rails/flanges are cleanly penetrated:
   ```dart
   static void applyExtrudeCutToHostParts({
     required AssemblyDocument document,
     required SurfaceSketch sketch,
     required List<SketchEntity> targetEntities,
     required ExtrudeFeatureConfig config,
   }) {
     for (final SketchEntity entity in targetEntities) {
       // 1. Build cutter volume (for Symmetric or Through-All, pierce both sides of the rail wall)
       final double halfDepth = (config.endType == ExtrudeEndType.throughAll)
           ? 500.0
           : (config.direction == ExtrudeDirection.symmetric
               ? config.depthMm * 0.5 + 0.1
               : config.depthMm + 0.1);

       final CadSolidMesh cutterPrism = buildExtrudedPrismMesh(
         sketch: sketch,
         entity: entity,
         startOffsetMm: config.direction == ExtrudeDirection.symmetric ? -halfDepth : -0.1,
         endOffsetMm: halfDepth,
       );

       // 2. Find target part(s) (hostPartId or intersecting parts)
       final Iterable<AssemblyPart> targetParts = document.parts.where((p) {
         if (p.createdByExtrudeFeatureId != null && p.id == config.featureId) return false;
         if (sketch.hostPartId != null && p.id == sketch.hostPartId) return true;
         return p.worldBounds.intersects(cutterPrism.worldBounds);
       });

       // 3. Subtract cutterPrism from targetPart mesh & punch pass-through topological hole
       for (final AssemblyPart part in targetParts) {
         part.mesh = CadBooleanEngine.subtract(
           targetSolid: part.mesh,
           cutterSolid: cutterPrism,
         );
         if (entity is SketchCircleEntity) {
           part.addPassThroughCutHole(
             id: 'cut_hole_${config.featureId}_${entity.id}',
             centerWorld: sketch.sketch2DToWorld(entity.center2D),
             normalWorld: sketch.planeNormalWorld,
             diameterMm: entity.radiusMm * 2.0,
           );
         }
         part.rebuildTopologicalFacesAndNormals();
       }
     }
   }
   ```

#### 8.3 Non-Destructive Feature Rollback & Replay (Cancels Previous Extrude Automatically)
In `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`:
1. Save a clean `_baseMeshSnapshot` on every initial `AssemblyPart` before features are applied, and tag any part created by `ExtrudeOperation.newBody` with `createdByExtrudeFeatureId = featureItem.id`.
2. When a user re-opens a sketch or clicks a geometry that already has an `AssemblyTimelineItem` (`Extrude N`) and changes its operation (e.g., from `New Body` or `Join` to `Cut`), update that existing `AssemblyTimelineItem.extrudeConfig` in-place and call `rebuildParametricTimeline()`:
   ```dart
   void rebuildParametricTimeline() {
     // 1. Cancel/remove all bodies spawned by previous 'New Body' extrusions
     document.parts.removeWhere((p) => p.createdByExtrudeFeatureId != null);

     // 2. Reset all base parts (e.g. Right Side Rail, Left Side Rail) to their pre-extrude state
     for (final AssemblyPart part in document.parts) {
       part.restoreBaseMeshSnapshot();
     }

     // 3. Replay all active timeline features in chronological order
     for (final AssemblyTimelineItem item in document.timelineItems) {
       if (item.isSuppressed) continue;
       if (item.type == TimelineFeatureType.extrude && item.extrudeConfig != null) {
         final SurfaceSketch? sketch = document.findSketchById(item.sketchId);
         if (sketch != null) {
           AssemblyExtrudeEngine.executeFeature(
             document: document,
             featureItem: item,
             sketch: sketch,
             config: item.extrudeConfig!,
           );
         }
       }
     }

     syncSceneWithGpuViewport();
     notifyListeners();
   }
   ```

---

## 9. Verification Test Cases to Add
**File to Modify:** `test/modules/assembly_studio/onshape_complete_sketch_engine_test.dart`

Add and run `flutter test test/modules/assembly_studio/onshape_complete_sketch_engine_test.dart` to verify:
1. **`holeCenters_onlyHighlightOnProximityOrExplicitSelection_includingHiddenXRayHover`**: Selecting all parts leaves `selectedHoleCenterIds` empty; hovering within `18px` of a hidden hole center sets `hoveredHoleCenterId`.
2. **`cameraZoomAndPosition_remainLockedOnSketchActivateAndDeactivate`**: `viewModel.cameraDistance` and `viewModel.cameraPosition` are identical before `enterSketchMode()`, during tool changes, and after `confirmActiveSketch()`.
3. **`featureTree_singleClickHighlightsOnly_doubleClickOpensSketchOrExtrudeDialog`**: Single-clicking `Sketch 1` sets `highlightedSketchId` without activating Sketch Mode; single-clicking `Extrude 1` highlights the 3D step and opens its property dialog; renaming updates `item.name`.
4. **`dimensions_witnessLinesOrthogonal_twoEntitiesAndBorders_drivenGrey`**: Witness line vectors have `0.0` dot product with measured edge; dimensioning between two circle centers (`99`) and entity-to-border (`65`) works; over-constrained dimension (`76.8`) is marked `isDriven == true`.
5. **`closedPolygon_movesRigidlyAsWholeFromMidpointVertexOrCenter`**: Editing a distance constraint from a part border to a pentagon edge midpoint translates all 5 vertices by the exact same $\Delta \mathbf{u}$ vector.
6. **`extrudeCut_punchesPassThroughHole_andEditingOperationCancelsPreviousExtrudeBody`**: Creating a `New Body` extrude spawns `Extruded Body 1`; editing that geometry's extrude operation to `Cut` removes `Extruded Body 1` and cuts a pass-through hole in `Right Side Rail`.