# TruFold Studio: Onshape Sketcher, Parametric Feature Tree, Relational Dimensions & CSG Cut Master Specification

**Repository:** `Intelidan/trufold_studio`  
**Target Modules:**
- `lib/assembly_studio/engine/sketch/` (`assembly_extrude_engine.dart`, `assembly_sketch_constraint_solver.dart`, `assembly_surface_sketch_engine.dart`, `onshape_sketch_modify_engine.dart`)
- `lib/assembly_studio/models/` (`assembly_timeline_item.dart`, `assembly_document.dart`, `assembly_part.dart`)
- `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`
- `lib/assembly_studio/views/widgets/` (`assembly_3d_viewport.dart`, `assembly_browser_tree.dart`, `assembly_scene_hierarchy_tree.dart`)
- `lib/assembly_studio/views/widgets/viewport/overlays/` (`assembly_extrude_dialog.dart`, `assembly_onshape_sketch_dialog.dart`, `draggable_cad_dialog.dart`)
- `lib/assembly_studio/views/widgets/viewport/painters/` (`assembly_3d_surface_sketch_painter.dart`, `assembly_3d_extrude_painter.dart`, `assembly_sketch_overlay_painter.dart`, `assembly_magnetic_spots_painter.dart`)
- `lib/sketch_draft_files/math_and_processing/` (`cad_boolean_engine.dart`, `cad_constraint_solvers.dart`, `cad_profile_validator.dart`)

---

## Architecture & Engineering Guardrails
1. **Single-Precision Math:** Strictly use `package:vector_math/vector_math.dart` (`Vector2`, `Vector3`, `Matrix4`, `Float32List`). Never use `vector_math_64`.
2. **Dual-Pipeline Symmetry:** Any geometry, boolean cut, or lighting update applied to the CPU/Canvas fallback must identically synchronize with the `flutter_scene` / GPU vertex buffers.
3. **Zero-Allocation 120 FPS Hover Loop:** Do not call `setState()` inside pointer hover listeners; drive hover/snap/dimension previews through `AssemblyStudioViewModel` (`ChangeNotifier`) and `CustomPainter` repaint listenables.

---

## PART 1: Left Feature Tree Overhaul (`assembly_browser_tree.dart` & `assembly_timeline_item.dart`)

### 1.1 Unified Onshape-Style Chronological `Features (N)` List (SS3 & SS6)
**Current Bug:**
In `assembly_browser_tree.dart` and `assembly_scene_hierarchy_tree.dart`, items are split into static folders (`Default geometry`, `Construction`, `Sketches`, `Parts`, `Joints & Welds`). Solid modeling steps (`Extrude 1`, `Extrude 2`, `Tab 1`, `Mirror 1`) are missing from the main feature list, and `Sketch 1` displays cluttered `[2 3D]`, `[Closed]`, and inline pencil badges (`SS2`, `SS7`).

**Required Implementation:**
1. In `lib/assembly_studio/models/assembly_timeline_item.dart` and `assembly_document.dart`, unify sketches and solid operations into an ordered parametric list `List<AssemblyTimelineItem> featureTree`:
   ```dart
   enum AssemblyFeatureKind {
     sketch,
     extrude,
     revolve,
     sheetMetalModel,
     flange,
     tab,
     mirror,
     modifyJoint,
     hole,
   }

   class AssemblyTimelineItem {
     final String id;
     String name; // Editable in-place: "Sketch 1", "Extrude 1", "Tab 1", etc.
     final AssemblyFeatureKind kind;
     final String? parentSketchId; // For Extrude/Tab referencing a Sketch
     final Set<String> targetProfileIds; // Specific closed loop IDs inside parentSketchId
     ExtrudeOperationSpec? extrudeSpec;
     bool isVisible;
     bool isSuppressed;
     bool hasError;
     String? errorMessage;

     AssemblyTimelineItem({
       required this.id,
       required this.name,
       required this.kind,
       this.parentSketchId,
       Set<String>? targetProfileIds,
       this.extrudeSpec,
       this.isVisible = true,
       this.isSuppressed = false,
       this.hasError = false,
       this.errorMessage,
     }) : targetProfileIds = targetProfileIds ?? <String>{};
   }
   ```
2. In `lib/assembly_studio/views/widgets/assembly_browser_tree.dart`:
   - Render the top section as **`Features (N)`** containing:
     - Collapsible `Default geometry` (`Origin`, `Top`, `Front`, `Right`).
     - The chronological flat list of `featureTree` items (`Sketch 1`, `Extrude 1`, `Sketch 2`, `Extrude 2`, `Tab 1`, `Mirror 1`, etc.) with clean Onshape-style monochrome icons and a rollback bar at the bottom of the feature list.
   - Remove the `[Closed]` and `[2 3D]` pills from sketch rows in `assembly_browser_tree.dart`.
   - Render **`Parts (N)`** as a collapsible bottom section listing the resulting solid parts (`Left Side Rail`, `Right Side Rail`, `Rung #1`, etc.).

### 1.2 Single-Click Highlight vs. Double-Click Edit & Inline Rename (Item 2 & Item 6)
**Current Bug:**
Single-clicking `Sketch 1` in `assembly_browser_tree.dart` immediately activates Sketch Mode.

**Required Implementation (`assembly_browser_tree.dart` & `assembly_studio_viewmodel.dart`):**
1. **Single-Click (`onTap`):**
   - Calls `viewModel.selectTimelineFeature(item.id)`.
   - **Never** enters Sketch Mode on single click.
   - Highlights the associated 2D sketch geometry AND/OR 3D extruded faces/edges in **Onshape Orange (`#FF9800` 2.5px border + `#44FFB74D` translucent amber fill)** on the 3D model (`SS3`, `SS6`).
   - If the clicked item is a solid step (`Extrude 1`, `Tab 1`, `Mirror 1`), single-clicking highlights the step on the 3D model and opens its property inspector/dialog in read/edit preview mode; double-clicking opens the full modal dialog (`assembly_extrude_dialog.dart`).
2. **Double-Click (`onDoubleTap`):**
   - If `item.kind == AssemblyFeatureKind.sketch`, calls `viewModel.enterSketchMode(item.id)` and opens `AssemblyOnshapeSketchDialog`.
   - If `item.kind == AssemblyFeatureKind.extrude`, calls `viewModel.beginEditingExtrudeFeature(item.id)` and opens `AssemblyExtrudeDialog`.
3. **Editable Sketch & Feature Names:**
   - Add inline text editing to `assembly_browser_tree.dart` AND the title header of `assembly_onshape_sketch_dialog.dart` / `assembly_extrude_dialog.dart`.
   - Clicking the title in the dialog header or right-clicking / slow-double-clicking the name in the tree swaps the `Text` widget for an inline `TextField` that calls `viewModel.renameTimelineFeature(item.id, newName)`.

---

## PART 2: Onshape Sketch Visuals, Orthogonal Witness Lines & Dimension Engine (`assembly_3d_surface_sketch_painter.dart` & `assembly_sketch_constraint_solver.dart`)

### 2.1 Crisp Black Constrained Borders & Shaded Closed Profiles (Item 3 / SS2 vs SS4)
**Current Bug:**
In `assembly_3d_surface_sketch_painter.dart` and `assembly_sketch_overlay_painter.dart`, all sketch lines are drawn in cyan/blue (`#0288D1`), making defined sketches look unfinished compared to Onshape (`SS4`).

**Required Implementation:**
Update stroke and fill colors in `assembly_3d_surface_sketch_painter.dart`:
- **Constrained / Defined Sketch Entities:** `const Color(0xFF111111)` (1.65px crisp black stroke).
- **Under-Constrained Sketch Entities:** `const Color(0xFF1565C0)` (1.65px deep Onshape blue stroke).
- **Construction Geometry (`isConstruction == true`):** `const Color(0xFF546E7A)` dashed stroke (`dash: [5.0, 4.0]`).
- **Imprinted Host Part Borders (`isImprintedReference == true`):** `const Color(0xFF263238)` (1.2px solid stroke).
- **Hovered / Selected Entity or Tree-Highlighted Sketch:** `const Color(0xFFFF9800)` (2.4px amber/orange stroke) with `#38FFB74D` fill when highlighted from the tree (`SS3`).
- **Active Sketch Closed Loop Shading:** Fill all valid closed profiles (`cad_profile_validator.dart`) with `const Color(0x3890A4AE)` cool slate translucent fill (`SS4`).

### 2.2 Fix Slanted Witness Lines, Draggable Dimensions & Mouse-Driven Orientation (Item 3 / SS2)
**Current Bug:**
1. In `SS2` (bottom-right red circle on the `50` dimension), the witness/extension lines at the ends of the dimension line are slanted instead of perpendicular ($90^\circ$) to the rectangle's edge.
2. Editing one dimension of a rectangle causes its second dimension line to disappear.
3. Regular polygons (Pentagon/Hexagon in `SS2`) have no default dimension.
4. Dimension lines cannot be dragged to reposition after creation.
5. Moving the mouse while creating a 2-point dimension does not switch orientation between Horizontal, Vertical, and Aligned.

**Required Implementation (`assembly_3d_surface_sketch_painter.dart` & `assembly_surface_sketch_engine.dart`):**

#### A. Strictly Orthogonal Witness Lines in 2D Sketch Plane Coordinates
Never compute witness line offsets in raw screen space! Compute all dimension geometry in **2D Sketch Plane Coordinates (`Vector2`)** and project the resulting 2D points to 3D/screen space:
```dart
enum SketchDimensionOrientation { horizontal, vertical, aligned, radial, diameter, angular }

class ResolvedLinearDimension2D {
  final Vector2 anchor1; // On entity in Sketch 2D space
  final Vector2 anchor2; // On entity in Sketch 2D space
  final Vector2 dimLineStart; // On dimension line in Sketch 2D space
  final Vector2 dimLineEnd;   // On dimension line in Sketch 2D space
  final Vector2 witness1End;  // Overshoot tip 1
  final Vector2 witness2End;  // Overshoot tip 2
  final Vector2 labelCenter;
  final double measuredValue;

  ResolvedLinearDimension2D({
    required this.anchor1,
    required this.anchor2,
    required this.dimLineStart,
    required this.dimLineEnd,
    required this.witness1End,
    required this.witness2End,
    required this.labelCenter,
    required this.measuredValue,
  });
}

ResolvedLinearDimension2D computeOrthogonalDimension2D({
  required Vector2 p1,
  required Vector2 p2,
  required Vector2 labelPosition2D,
  required SketchDimensionOrientation orientation,
  double witnessOvershootMm = 2.5,
}) {
  late Vector2 measureDir;
  late Vector2 perpNormal;

  if (orientation == SketchDimensionOrientation.horizontal) {
    measureDir = Vector2(1.0, 0.0);
    perpNormal = Vector2(0.0, 1.0);
  } else if (orientation == SketchDimensionOrientation.vertical) {
    measureDir = Vector2(0.0, 1.0);
    perpNormal = Vector2(1.0, 0.0);
  } else {
    // Aligned: strictly parallel to p1 -> p2
    final Vector2 delta = p2 - p1;
    final double len = delta.length;
    measureDir = len > 1e-5 ? (delta / len) : Vector2(1.0, 0.0);
    // Exact 90-degree perpendicular normal in 2D sketch plane: (-dy, dx)
    perpNormal = Vector2(-measureDir.y, measureDir.x);
  }

  // Project labelPosition2D onto perpNormal to get signed perpendicular offset distance
  final Vector2 mid = (p1 + p2) * 0.5;
  final double signedOffset = (labelPosition2D - mid).dot(perpNormal);
  final double sign = signedOffset >= 0.0 ? 1.0 : -1.0;

  // Project both anchors onto the dimension line so witness lines are 100% parallel to perpNormal
  final Vector2 lineOrigin = mid + perpNormal * signedOffset;
  final double t1 = (p1 - lineOrigin).dot(measureDir);
  final double t2 = (p2 - lineOrigin).dot(measureDir);

  final Vector2 dimStart = lineOrigin + measureDir * t1;
  final Vector2 dimEnd = lineOrigin + measureDir * t2;

  final Vector2 w1End = dimStart + perpNormal * (sign * witnessOvershootMm);
  final Vector2 w2End = dimEnd + perpNormal * (sign * witnessOvershootMm);
  final double value = (t2 - t1).abs();

  return ResolvedLinearDimension2D(
    anchor1: p1,
    anchor2: p2,
    dimLineStart: dimStart,
    dimLineEnd: dimEnd,
    witness1End: w1End,
    witness2End: w2End,
    labelCenter: (dimStart + dimEnd) * 0.5,
    measuredValue: value,
  );
}
```
Because `dimStart`, `dimEnd`, `w1End`, and `w2End` are computed in `SketchPlane` 2D space using the exact orthogonal basis `(measureDir, perpNormal)` and then projected via `sketchPlane.sketch2DToScreen(pt)`, the witness lines are **guaranteed to be parallel to the entity's perpendicular normal** at every 3D camera angle.

#### B. Mouse Movement Determines Dimension Orientation During Creation
When the user is placing a dimension between `p1` and `p2`, dynamically update `previewDimension.orientation` on every `onPointerHover` event based on cursor position `cursor2D`:
```dart
SketchDimensionOrientation inferOrientationFromCursor(Vector2 p1, Vector2 p2, Vector2 cursor2D) {
  final double minX = math.min(p1.x, p2.x);
  final double maxX = math.max(p1.x, p2.x);
  final double minY = math.min(p1.y, p2.y);
  final double maxY = math.max(p1.y, p2.y);

  final bool outsideX = cursor2D.x < minX - 2.0 || cursor2D.x > maxX + 2.0;
  final bool outsideY = cursor2D.y < minY - 2.0 || cursor2D.y > maxY + 2.0;

  if (outsideX && !outsideY) {
    return SketchDimensionOrientation.vertical; // Cursor moved left/right of span -> Vertical dim
  } else if (outsideY && !outsideX) {
    return SketchDimensionOrientation.horizontal; // Cursor moved above/below span -> Horizontal dim
  }
  return SketchDimensionOrientation.aligned; // Cursor in diagonal quadrant -> Aligned dim
}
```

#### C. Draggable Dimension Lines After Placement
In `assembly_surface_sketch_engine.dart`:
- Add `String? draggedDimensionId` to the sketch interaction state.
- When `activeSketchTool == SketchTool.select` or `SketchTool.dimension`, hit-test existing dimension labels and dimension lines on `onPointerDown`.
- If hit, set `draggedDimensionId = dim.id` and update `dim.labelPosition2D = cursorSketch2D` on `onPointerMove`. Do **not** exit Sketch Mode or trigger entity selection while dragging a dimension label.

#### D. Preserve Both Rectangle Dimensions & Add Pentagon Construction Circle + Diameter
1. **Rectangle Dual Dimensions:** In `assembly_surface_sketch_engine.dart`, when creating a rectangle, assign distinct IDs `rectWidthDimId` (bound to top/bottom horizontal edge) and `rectHeightDimId` (bound to left/right vertical edge). When editing `rectWidthDimId`, update **only** the horizontal edge length; remove the code that clears or regenerates the rectangle's constraint list from scratch.
2. **Pentagon / Regular Polygon Dimension:** When finishing a regular polygon (`N >= 3` sides), automatically insert:
   - A dashed inscribed construction circle (`isConstruction = true`, center = polygon center, radius = inscribed radius).
   - An editable `SketchDimension` of type `SketchDimensionOrientation.diameter` (`Ø`) linked to the polygon's radius so editing the `Ø` value scales all $N$ vertices radially around the polygon centroid.

---

## PART 3: Multi-Entity & Part-Border Dimensions + Grey Driven Dimensions (Items 4 & 5 / SS4 & SS5)

### 3.1 Dimensioning Between 2 Geometric Entities and/or 3D Object Borders (`SS5`)
**Current Bug:**
Users can only dimension a single primitive. They cannot set a dimensional constraint between two separate entities (e.g., circle center to circle center `99`, circle center to part border `65` / `75`, arc center to part border `90`, line to part border `27°`, or point to top part border `76.8` in `SS5`).

**Required Implementation (`assembly_surface_sketch_engine.dart` & `assembly_sketch_constraint_solver.dart`):**
1. **Auto-Imprint Host Part Face Borders & Hole Centers on Sketch Entry:**
   When `enterSketchMode()` starts on a 3D part face, extract the outer boundary loop edges and existing hole centers of that 3D face and add them to the sketch as locked reference entities (`isImprintedReference = true`, `isFixed = true`).
2. **Two-Target Dimension Tool State Machine:**
   Update the Dimension Tool in `assembly_surface_sketch_engine.dart` to support a 2-anchor workflow:
   - **State 0 (`idle`):** User clicks Entity/Point/Border **A** (`_dimTargetA = hitTarget`).
     - If `_dimTargetA` is a line, circle, or arc, immediately show a 1-entity dimension preview (`Length`, `Ø`, or `R`) attached to the cursor.
   - **State 1 (`awaitingSecondTargetOrPlacement`):**
     - **Case A — User clicks empty canvas space:** Commits the 1-entity dimension at the cursor position and opens the value input box.
     - **Case B — User clicks a second Entity/Point/Imprinted Part Border B (`_dimTargetB = hitTarget`):** Transitions to **State 2 (`placingTwoEntityDimension`)**.
       - `Point/Center` + `Point/Center` $\rightarrow$ Linear distance (`Horizontal`, `Vertical`, or `Aligned` based on cursor movement, e.g., `99` in `SS5`).
       - `Point/Center` + `Line / Part Border` $\rightarrow$ Perpendicular distance from point to line (`60`, `65`, `76.8` in `SS5`).
       - `Line` + `Parallel Line / Part Border` $\rightarrow$ Perpendicular offset distance.
       - `Line` + `Non-Parallel Line / Part Border` $\rightarrow$ **Angular dimension (`27°` in `SS5`)** rendered with an arc and degree symbol `°`.
   - **State 2 (`placingTwoEntityDimension`):** User moves mouse to set orientation/offset and clicks to place the relational dimension.

### 3.2 Driven (Non-Editable Grey) Dimensions (`SS5` — `75` & `76.8`)
**Current Bug:**
Over-constrained reference dimensions cannot be created or are drawn in black instead of non-editable grey.

**Required Implementation:**
1. Add `bool isDriven` to `SketchDimension` (default `false`).
2. In `assembly_sketch_constraint_solver.dart`, when adding a new dimension:
   - Check if both target anchorsalready have **0 Degrees of Freedom** (e.g., both are imprinted part borders, or their relative distance is already locked by existing driving dimensions/constraints).
   - If over-constrained, set `dimension.isDriven = true` instead of rejecting the dimension.
   - Users can also right-click any dimension and toggle **"Driven / Driving"**.
3. In `assembly_3d_surface_sketch_painter.dart`:
   - If `dimension.isDriven == true`, draw the extension lines, dimension line, arrowheads, and text in **Onshape Driven Grey (`#8C96A0`)** (`SS5`: `75` and `76.8`).
   - Double-clicking a driven dimension does not open the value editor; its value updates automatically as a live readout whenever the geometry changes.

### 3.3 Rigid Closed Polygon / Polyline Constraint from Any Edge Center, Endpoint, or Centroid (Item 5)
**Current Bug:**
Constraining a closed polygon or closed polyline from one of its vertices or edge midpoints to another entity/border stretches that single vertex and deforms the polygon instead of moving the closed polygon as a rigid whole.

**Required Implementation (`assembly_sketch_constraint_solver.dart`):**
1. For every closed polyline or regular polygon (`SketchClosedLoop`), expose three snap/dimension anchor types:
   - **Line Endpoints (`vertex_i`)**
   - **Line Centers (`midpoint_i = (v_i + v_{i+1}) * 0.5`)**
   - **Polygon Center (`centroid = average(v_0 ... v_{n-1})`)** — render a subtle selectable center point when hovering inside or over the boundary of a closed polygon.
2. **Rigid-Body Translation in `AssemblySketchConstraintSolver`:**
   When a relational dimension (e.g., distance from part border or another entity to a polygon's vertex, edge midpoint, or centroid) is edited and produces a required displacement vector $\Delta \mathbf{u} = (dx, dy)$:
   ```dart
   void applyRelationalDistanceToClosedPolygon({
     required SketchClosedLoop polygonLoop,
     required String constrainedAnchorId,
     required Vector2 requiredDelta,
   }) {
     // Check if another vertex/edge of this same polygon is explicitly anchored externally
     final bool hasOpposingExternalLock = polygonLoop.vertexIds.any(
       (vid) => vid != constrainedAnchorId && isVertexLockedExternally(vid),
     );

     if (!hasOpposingExternalLock) {
       // Move the ENTIRE closed polygon/polyline rigidly as a single unit!
       for (final String vid in polygonLoop.vertexIds) {
         final Vector2 current = getVertexPosition(vid);
         setVertexPosition(vid, current + requiredDelta);
       }
       polygonLoop.recomputeCentroid();
     } else {
       // Only deform if the user explicitly locked two different vertices of the same polygon
       solveLocalVertexDelta(constrainedAnchorId, requiredDelta);
     }
   }
   ```

---

## PART 4: Per-Profile Extrude Isolation, True CSG Pass-Through Cut & Feature Mutation (`assembly_extrude_engine.dart` & `cad_boolean_engine.dart`)

### 4.1 Isolate Extrude / Cut Operations Per Selected Sketch Profile (First Request Item 6)
**Current Bug:**
In `assembly_extrude_engine.dart`, extruding or cutting one selected sketch entity applies the extrusion/cut to **all** entities in that sketch.

**Required Implementation (`assembly_extrude_engine.dart` & `assembly_extrude_dialog.dart`):**
1. Every closed profile in a sketch (`circle_1`, `rect_1`, `poly_1`) must have its own `profileId`.
2. `ExtrudeOperationSpec` must store `final Set<String> selectedProfileIds` (displayed as removable chips in the `"Faces and sketch regions to extrude"` box inside `assembly_extrude_dialog.dart`, matching `SS6` & `SS7`).
3. `AssemblyExtrudeEngine.execute()` must filter `sketch.closedProfiles` strictly by `spec.selectedProfileIds.contains(profile.id)`. Unselected profiles in the same sketch must **never** be extruded or cut by that feature.

### 4.2 Fix Cut Operation Creating a New Body Instead of a Pass-Through Hole (Item 7 / SS6, SS7, SS8)
**Current Bug:**
In `SS7` and `SS8`, selecting `Cut` (`Remove`) with `Symmetric` / `Blind 25.0 mm` on the circle in `Sketch 1` creates a red preview cylinder and then spawns a solid protruding cylinder (`Extruded Body 1` in the `Parts` tree of `SS7` and visible in `SS8`) instead of cutting a hole through `Right Side Rail`.

**Root Cause:**
`assembly_extrude_engine.dart` generates a new `AssemblyPart` mesh for `ExtrudeOperation.cut` (or fails the host part lookup and falls back to `newBody`) instead of subtracting the cutter prism from the intersecting `AssemblyPart` meshes via `cad_boolean_engine.dart`.

**Required Implementation (`lib/assembly_studio/engine/sketch/assembly_extrude_engine.dart`):**
1. When `spec.operation == ExtrudeOperation.cut`:
   - **Never** append a new `AssemblyPart` (`Extruded Body N`) to `document.parts`!
   - Construct the 3D cutter prism mesh along `sketchPlane.normal`:
     - If `spec.endType == ExtrudeEndType.throughAll`: set cutter extent from `-maxSceneBound` to `+maxSceneBound` along the cut direction.
     - If `spec.direction == ExtrudeDirection.symmetric`: extrude from `-spec.depthMm * 0.5 - 0.05` to `+spec.depthMm * 0.5 + 0.05` (adding a `0.05 mm` coplanar epsilon so the cutter cleanly pierces both the front and back faces of thin sheet-metal flanges/rails).
     - If `spec.direction == ExtrudeDirection.oneSide`: automatically orient the default cut direction **into** the host part (`-sketchPlane.normal`) and extend starting offset by `+0.05 mm` outside the host face.
2. Execute true boolean subtraction against the host part (and any intersecting parts in `mergeScope`):
   ```dart
   void executeExtrudeCut({
     required AssemblyDocument document,
     required SurfaceSketch sketch,
     required ExtrudeOperationSpec spec,
   }) {
     final List<SketchClosedProfile> targetProfiles = sketch.closedProfiles
         .where((p) => spec.selectedProfileIds.contains(p.id))
         .toList();
     if (targetProfiles.isEmpty) return;

     for (final profile in targetProfiles) {
       final CadSolidMesh cutterMesh = buildCutterPrismMesh(
         sketch: sketch,
         profile: profile,
         spec: spec,
         coplanarEpsilonMm: 0.05,
       );

       // Find target parts to cut (hostPartId first, plus any part whose AABB intersects cutterMesh)
       final List<AssemblyPart> candidateParts = document.parts.where((part) {
         if (spec.mergeScopePartIds.isNotEmpty) {
           return spec.mergeScopePartIds.contains(part.id);
         }
         if (sketch.hostPartId != null && part.id == sketch.hostPartId) {
           return true;
         }
         return part.worldBoundingBox.intersects(cutterMesh.worldBoundingBox);
       }).toList();

       for (final AssemblyPart targetPart in candidateParts) {
         targetPart.mesh = CadBooleanEngine.subtract(
           target: targetPart.mesh,
           cutter: cutterMesh,
         );
         // Register circular cut as a snappable 3D hole with inner cylindrical wall + top/bottom rims
         if (profile.isCircle) {
           targetPart.registerCutHole(
             centerWorld: sketch.sketch2DToWorld(profile.centroid2D),
             axisWorld: sketch.planeNormal,
             diameterMm: profile.diameterMm,
             depthMm: spec.depthMm,
           );
         }
         targetPart.recomputeNormalsAndBounds();
       }
     }
   }
   ```

### 4.3 Non-Destructive Parametric Replay: Editing a Sketch or Extrude Cancels Previous Operation (Item 7)
**Current Bug:**
Performing an Extrude (`Join` or `New Body`), finishing the sketch, and then re-opening the sketch or Extrude dialog to change that geometry's operation to `Cut` leaves the old `Extruded Body 1` in the scene and stacks the new operation on top.

**Required Implementation (`assembly_studio_viewmodel.dart` & `assembly_extrude_engine.dart`):**
1. **Store Base Part Snapshots:** Every `AssemblyPart` stores an immutable `_baseMeshSnapshot` (its state prior to parametric feature tree evaluation), and `AssemblyDocument` tracks which `AssemblyPart` instances were spawned by `ExtrudeOperation.newBody` via `part.createdByFeatureId`.
2. **Lookup Existing Feature When Re-Extruding a Profile:**
   When the user selects a sketch profile that already belongs to an existing `AssemblyTimelineItem` (`Extrude N`) and opens the Extrude tool—or double-clicks `Extrude N` in the Feature Tree—load that existing `AssemblyTimelineItem` into `AssemblyExtrudeDialog` instead of creating a duplicate timeline item.
3. **Full Parametric Rollback & Replay (`rebuildFeatureTimeline()`):**
   Whenever any `Sketch` or `Extrude` feature is edited, changed from `New Body`/`Join` to `Cut`, suppressed, or deleted:
   ```dart
   void rebuildFeatureTimeline() {
     // 1. Remove all parts that were dynamically spawned by previous 'New Body' extrude features
     document.parts.removeWhere((p) => p.createdByFeatureId != null);

     // 2. Restore all original assembly parts to their clean pre-feature base mesh
     for (final AssemblyPart part in document.parts) {
       part.restoreToBaseMeshSnapshot();
     }

     // 3. Replay all active features in chronological order from featureTree
     for (final AssemblyTimelineItem item in document.featureTree) {
       if (item.isSuppressed) continue;
       if (item.kind == AssemblyFeatureKind.extrude && item.extrudeSpec != null) {
         final SurfaceSketch? sketch = document.findSketchById(item.parentSketchId);
         if (sketch != null) {
           AssemblyExtrudeEngine.applyFeature(
             document: document,
             featureItem: item,
             sketch: sketch,
             spec: item.extrudeSpec!,
           );
         }
       }
     }

     syncGpuSceneMeshes();
     notifyListeners();
   }
   ```
   This guarantees that changing a profile from `New Body` or `Join` to `Cut` **completely cancels and removes** the previous `Extruded Body 1` and performs a clean pass-through cut on the rail.

---

## PART 5: Viewport UX, Camera Lock, Lighting & Dot Clutter Fixes (First Request Items 1, 2, 3, 4, 5, 7)

### 5.1 Only Highlight Hole Center Points on Proximity Snap or Explicit Selection (`assembly_magnetic_spots_painter.dart`)
- In `lib/assembly_studio/views/widgets/viewport/painters/assembly_magnetic_spots_painter.dart` and `assembly_3d_viewport.dart`:
  - **Remove** the logic that highlights all hole center points in amber when a multi-part 3D model is selected.
  - Only draw a hole center point if:
    1. Its ID is in `viewModel.selectedHoleCenterIds` (amber `#FFAB00`), OR
    2. A snapping tool (`Move`, `Sketch`, `Measure`) is active AND the mouse cursor is within **18.0 px** screen distance of that hole center.

### 5.2Eliminate Floating Dot Clutter (`assembly_sketch_overlay_painter.dart` & `assembly_3d_extrude_painter.dart`)
- Do **not** emit 32-segment cylinder tessellation vertices as snap points in `assembly_extrude_engine.dart`.
- Do **not** render the 27-point OBB bounding box dots unless `viewModel.activeTool == AssemblyTool.move` is actively dragging.
- In `assembly_3d_surface_sketch_painter.dart`, only render vertex grip dots for the **currently hovered or selected sketch entity**, never for all unselected entities simultaneously.

### 5.3 Zero Automatic Camera Zoom on Sketch Mode Toggle (`assembly_studio_viewmodel.dart`)
- In `enterSketchMode()` and `exitSketchMode()` inside `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`:
  - Remove all calls that modify `_cameraRadius`, `_cameraZoom`, `_cameraTarget`, or tween the camera distance when activating/deactivating Sketch Mode or selecting sketch tools.
  - Only align the camera normal to the sketch plane if the user explicitly clicks the **`Normal (N)`** button inside `assembly_onshape_sketch_dialog.dart` (and even then, preserve `_cameraDistance` so zoom never jumps).

### 5.4 Sketch Mode Persistence During Entity Edits (`assembly_3d_viewport.dart`)
- Audit all pointer/gesture callbacks in `assembly_3d_viewport.dart` and `assembly_surface_sketch_engine.dart`.
- Editing a sketch entity (dragging a line/vertex, editing a dimension value, or extruding a profile from within the sketch) must **never** set `isSketchModeActive = false`.
- Only clicking the **Green Checkmark (`confirmSketch()`)** or **Red Cancel X (`cancelSketch()`)** in `assembly_onshape_sketch_dialog.dart` may exit Sketch Mode.

### 5.5 Ensure `AssemblyExtrudeDialog` and `AssemblyOnshapeSketchDialog` Use `DraggableCadDialog`
- Verify that `lib/assembly_studio/views/widgets/viewport/overlays/assembly_extrude_dialog.dart` and `assembly_onshape_sketch_dialog.dart` are wrapped in `DraggableCadDialog` (`lib/assembly_studio/views/widgets/viewport/overlays/draggable_cad_dialog.dart`) inside `assembly_3d_viewport.dart`, with drag handles on their top title bars so the user can freely drag both dialogs anywhere in the viewport.

### 5.6 Fix Dark Opposite Faces on 3D Model (`assembly_3d_viewport.dart` & `flutter_scene_cad_mesh_builder.dart`)
- In `assembly_3d_viewport.dart` (Canvas face shading) and the GPU lighting rig:
  - Flip back-facing normals toward the camera (`if (normal.dot(viewDir) < 0) normal = -normal;`) so inside walls of C-channels and holes never render black.
  - Add a **Camera-Space Headlight (`0.22` weight)** + **Half-Lambert wrap (`dot(N, L) * 0.5 + 0.5`)** with an ambient floor of **`0.46`** so opposite faces of the blue steel rails stay clearly illuminated and readable from every orbit angle.

---

## PART 6: Automated Verification Test Suite (`test/modules/assembly_studio/onshape_complete_sketch_engine_test.dart`)

Add the following regression tests to `test/modules/assembly_studio/onshape_complete_sketch_engine_test.dart`:
1. **`singleClickSketchHighlightsOnly_doubleClickEntersSketchMode`:** Verifies single-clicking `Sketch 1` in `AssemblyBrowserTree` sets `highlightedFeatureId` without setting `isSketchModeActive = true`, and double-clicking sets `isSketchModeActive = true`.
2. **`witnessLinesAreStrictlyPerpendicularToMeasuredEdge`:** Verifies `computeOrthogonalDimension2D` produces witness vectors whose dot product with the measured edge direction is `0.0` ($\pm 10^{-5}$).
3. **`twoEntityAndBorderDimensions_supportDrivenGreyState`:** Verifies placing a dimension between two circle centers (`99`) and between a circle center and an imprinted part border (`65`), and marks over-constrained dimensions as `isDriven == true`.
4. **`closedPolygonMovesRigidlyWhenConstrainedFromEdgeMidpointOrCenter`:** Verifies changing a distance constraint attached to a pentagon/polygon edge midpoint translates all polygon vertices by the exact same $\Delta \mathbf{u}$ vector without distorting internal edge lengths.
5. **`extrudeCutSubtractsFromRail_andEditingOperationReplacesPreviousBody`:** Verifies creating a `New Body` extrude and then editing that same `Extrude 1` step to `Cut` removes `Extruded Body 1` and performs a boolean pass-through cut on `Right Side Rail`.