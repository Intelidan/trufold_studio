# TruFold Studio (v7.0): Parametric Sketch-to-Body Associativity, Select/Deactivate Tool, Onshape Sketch Aesthetics & Topological Polygon Bonding

**Repository Audited:** [Intelidan/trufold_studio](https://github.com/Intelidan/trufold_studio) (`master` branch, commit [`c151848`](https://github.com/Intelidan/trufold_studio/commit/c151848e0c81c5b6da50bd0f180954ae252e01f7))  
**Drop-In Updated Files Archive:** `trufold_parametric_sketch_v7_updated_files.zip` (18 modified files preserving exact repository relative paths)

---

## 1. Executive Summary & Root-Cause Matrix

| # | Core Requirement | Root Cause in `master` (`c151848`) | Exact Architectural Fix Implemented |
| :--- | :--- | :--- | :--- |
| **Core** | **Parametric Sketch-to-Body Associativity:** Re-editing a sketch after Extrude / Cut / Pass-Through / New Body / Bend must automatically update both the old body and any new body according to the new sketch dimensions. | **1) One-Shot Bake with No Dependency Link:** `AssemblyExtrudeEngine.executeExtrusion` generated a static mesh (`New Body` / `Join`) or appended a one-off `AssemblySketchFeature` (`Cut`) with no back-reference (`CADDependentFeatureLink`) on `CADSketchPlane`.<br>**2) Stale Edits:** Editing a dimension (`commitInlineSketchDimension`) or dragging a sketch entity updated only the 2D `CADPrimitiveEntity`—it never recalculated downstream `New Body` extrusions, `Joined` bosses, `Pass-Through / Blind Cuts`, or `Bend` lines.<br>**3) `New Body` Parts Ignored Sketch Cuts:** `AssemblyPart._buildCustomExtrudedPolygons()` returned `customPolygons` directly without subtracting `part.sketches` (`_applySketchesToCustomPolygons`), so sketching a cut on a newly extruded body never cut it! | **1)** Added `CADDependentFeatureLink` and `plane.dependentFeatures` (`cad_models.dart`) to track every `New Body`, `Join`, `Cut / Pass-Through`, and `Bend` driven by a `CADSketchPlane`.<br>**2)** Implemented `AssemblyExtrudeEngine.regenerateSketchDrivenFeatures()` and wired `vm.regenerateActiveSketchDependents()` into `commitInlineSketchDimension`, `addPrimitiveEntityToActivePlane`, `deleteSelectedSketchEntity`, `finishSketch`, and live 60 FPS viewport dragging (`assembly_3d_viewport.dart`).<br>**3)** Added `_applySketchesToCustomPolygons()` and dynamic `bend_line` synthesis in `assembly_part.dart`, plus 1-click **Re-edit Sketch (`editExistingSketchPlane`)** buttons in `AssemblyBrowserTree`. |
| **1** | **Deactivate a Tool / Dedicated `"Select"` Tool in Sketch Mode** | **1)** `onshapeSketchGroups` (`onshape_toolbar_items.dart`) had no `"Select"` tool item.<br>**2)** Clicking an active sketch tool (`line`, `circle`, `rectangle`, `dimension`) a second time in `setActiveSketchTool()` did not toggle it off.<br>**3)** Pressing `Escape` in `assembly_3d_viewport.dart:1079` while a drawing tool was active (with no start point yet clicked) immediately called `vm.finishSketch()` and exited Sketch Mode instead of returning to Select mode! | **1)** Added a dedicated **`Select` (`select_sketch_entity`, shortcut `V` / `Esc`)** button at the left of the Sketch Toolbar (`assembly_onshape_toolbar.dart`) and inside the floating Sketch Dialog (`assembly_onshape_sketch_dialog.dart`).<br>**2)** Updated `vm.setActiveSketchTool()` so clicking any active sketch tool a second time toggles it off to `'select_entity'`.<br>**3)** Updated `Escape` and `V` in `assembly_3d_viewport.dart` to call `vm.deactivateSketchToolToSelect()` first before exiting Sketch Mode. |
| **2** | **Elegant Onshape Sketch Entities, Shading, Plane Label & Dimensions (`image_41a6fb.png`)** | **1) Overlapping Nested Loop Shading:** `Assembly3DSurfaceSketchPainter` filled each loop in `allClosedLoops` separately (`PathFillType.nonZero`), painting over inner holes (`Ø12` inside `Ø33`) instead of subtracting them.<br>**2) Unaligned Dimension Text & Narrow Span Crowding:** Linear dimension numbers (`99`, `90`, `65`, `60`, `75`) were drawn horizontally instead of aligned parallel to the dimension line, and narrow spans (`10`) crammed inward arrows on top of the text.<br>**3) Horizontal Plane Label:** `Assembly3DPlanePainter` drew `"Sketch 1"` horizontally with a white pill background instead of rotating it along the top sky-blue border edge of the 3D sketch plane (`Sketch 2` in `image_41a6fb.png`). | **1)** Combined all closed loops into a single `Path()..fillType = PathFillType.evenOdd` in `Assembly3DSurfaceSketchPainter`, subtracting inner holes cleanly like Onshape's cool-slate profile fill (`#3494A3B8`).<br>**2)** Rotated linear dimension text parallel to its dimension line (`canvas.rotate(textAngle)`), added outside-inward arrows for narrow spans (`10`), and refined `1.45px` crisp geometry strokes with `2.5px` solid vertex dots.<br>**3)** Updated `Assembly3DPlanePainter` to auto-size the plane frame around all sketch entities/dimensions and rotate the `"Sketch N"` title along the top edge (`math.atan2(edge.dy, edge.dx)`). |
| **3** | **Closed Polygon / Rectangle Topological Bonding + Break & Rejoin Feature** | **1) Unbonded Line Endpoints:** Dragging a `CADLineEntity` or changing its length/angle dimension only moved that single line's `start`/`end`, leaving adjacent polygon segments behind and ripping the closed polygon open.<br>**2) Composite Lock-In:** `CADRegularPolygonEntity` and `CADRectangleEntity` could not be broken into individual segments to edit a single side, nor rejoined into a bonded closed loop. | **1)** Added `plane.isLoopBonded` and `plane.unbondedEntityIds` (`cad_models.dart`), `dragSegmentOrVertexPreservingBond` and `resizeLinePreservingPolygonBond` (`onshape_sketch_modify_engine.dart`), and `_propagateBondedVertexShift` (`assembly_sketch_constraint_solver.dart`) so connected sides automatically extend/shorten/follow while keeping every shared corner vertex closed.<br>**2)** Added **Break Polygon (`🔓 Break Loop`)** (`breakPolygonOrLoop`) and **Rejoin Polygon (`🔗 Rejoin Loop`)** (`rejoinPolygonSegments`) in the Sketch Toolbar, Sketch Dialog, and contextual parameter bar. |

---

## 2. How Parametric Sketch-to-Body Associativity Works in CAD & TruFold Studio

In parametric feature-based CAD systems ([Onshape Working with Constraints](https://cad.onshape.com/help/Content/Sketch/working_with_constraints.htm), [Onshape Troubleshooting Sketch Geometry](https://cad.onshape.com/help/Content/Sketch/troubleshooting_sketch_geometry.htm)), a 2D sketch is not merely a temporary stencil that gets discarded after an extrusion or cut—it is the **live mathematical parent** of every 3D solid feature referencing it:

1. **Parent-Child Dependency Graph (`CADSketchPlane.dependentFeatures`):**
   - Whenever you execute an operation from a sketch—whether creating a **`New Body`**, **`Joining`** a boss onto an existing part, punching a **`Cut` / `Pass-Through`** hole or slot, or defining a **`Bend` line**—`AssemblyExtrudeEngine.executeExtrusion()` records a `CADDependentFeatureLink` on `plane.dependentFeatures`:
     ```dart
     class CADDependentFeatureLink {
       final String featureId;
       final String targetPartId; // Host part (for Cut/Join/Bend) or newly created part (for New Body)
       final String operation;    // 'newBody', 'join', 'cut', 'intersect', 'bend'
       final double distanceMm;
       final bool isSymmetric;
       final bool isTwoSided;
       final double secondDistanceMm;
       final double draftAngleDeg;
       final bool isPassThrough;
       final double bendAngleDeg;
       final double bendRadiusMm;
     }
     ```
2. **Outer Boundary vs. Inner Hole Loop Classification (`classifyOuterAndHoleLoops`):**
   - When a sketch contains both an outer profile (such as the angled bracket contour in `image_41a6fb.png`) and interior closed loops (such as the `Ø12` hole inside the `Ø33` boss), `AssemblyExtrudeEngine.classifyOuterAndHoleLoops()` uses signed shoelace area and point-in-polygon containment to separate outer solid contours from interior through-holes.
   - `generateExtrudedSolid()` then emits a single top cap and bottom cap `CadFoldedPolygon3D` with `holes: holeLoops`, and 4-vertex side quads (`drawWireframe: true`)—so extruding a `New Body` from a sketch with interior circles automatically punches those through-holes right through the new 3D body!
3. **Real-Time & Post-Edit Regeneration (`regenerateSketchDrivenFeatures`):**
   - When you re-open any saved sketch via the **Sketches** folder in the Browser Tree (`vm.editExistingSketchPlane(planeId)`) and edit a dimension (`commitInlineSketchDimension`), drag a line or circle (`onPointerMove`), or add/delete a hole:
     - **`New Body` links:** Rebuilds the target `AssemblyPart`'s `customPolygons`, bounding dimensions (`width`, `length`, `height`), and origin from the updated sketch loops while preserving all downstream cuts attached to that body.
     - **`Join` links:** Replaces the sketch plane's joined boss polygons in `targetPart.joinedExtrusionsByPlane[plane.id]` and recomputes `targetPart.customPolygons`.
     - **`Cut / Pass-Through` links:** Replaces all `AssemblySketchFeature` cuts associated with `planeId == plane.id` on `targetPart` (supporting both standard sheet-metal rails/channels AND custom extruded `New Body` parts via `_applySketchesToCustomPolygons`), immediately resizing or moving the 3D holes and internal bore walls.
     - **`Bend` links:** Updates `bend_line` features on `targetPart.sketches`, folding the part along the sketch line at `bendAngleDeg`.

---

## 3. Detailed Walkthrough of All 4 Requirements

### 3.1 Parametric Sketch-to-Body Regeneration (`assembly_extrude_engine.dart`, `assembly_part.dart`, `assembly_studio_viewmodel.dart`)
- **In `lib/assembly_studio/models/assembly_part.dart`:**
  - Added `sourceSketchPlaneId` and `joinedExtrusionsByPlane` to `AssemblyPart`.
  - Added `_applySketchesToCustomPolygons()` inside `_buildCustomExtrudedPolygons()`: when a `New Body` part has `sketches` (such as a `custom_cut` or `circle_hole` sketched on one of its 3D faces), it projects the hole loop onto the target front face, punches the matching exit hole through the opposite parallel back face (when `isPassThrough` or `cutDepthMm >= thickness`), and generates the 3D cylindrical/polygonal bore walls connecting them!
  - Added dynamic `bend_line` synthesis inside `_buildStraightRailPolygons()` so any sketch line marked as a **Bend Line (`FeatureType.bend`)** folds the 3D body along that line.
- **In `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`:**
  - Added `regenerateActiveSketchDependents()` and wired it into `commitInlineSketchDimension()`, `addPrimitiveEntityToActivePlane()`, `deleteSelectedSketchEntity()`, `finishSketch()`, and live dragging in `assembly_3d_viewport.dart`.
  - Added `editExistingSketchPlane(String planeId)` so clicking the **Edit Sketch (`Icons.edit_note_rounded`)** icon next to any sketch or part in `AssemblyBrowserTree` re-enters Sketch Mode on that exact plane and aligns the camera normal to it.

### 3.2 Deactivate Tool / Dedicated `"Select"` Tool in Sketch Mode (`onshape_toolbar_items.dart`, `assembly_onshape_toolbar.dart`, `assembly_3d_viewport.dart`)
- **Prominent `"Select"` Button in the Sketch Toolbar (`assembly_onshape_toolbar.dart` & `onshape_toolbar_items.dart`):**
  - Added a dedicated **`Select` (`select_sketch_entity`, shortcut `Esc / V`)** tool button at the far-left of the Sketch Toolbar with a blue active state when `vm.activeSketchTool == 'select_entity' && vm.activeConstraintTool == null`.
- **Click Active Tool Again to Deactivate (`assembly_studio_viewmodel.dart`):**
  - In `setActiveSketchTool(String tool)`, clicking the currently active tool a second time (`if (activeSketchTool == tool && tool != 'select_entity')`) automatically deactivates it and returns to `'select_entity'`.
- **`Esc` & `V` Key + Right-Click Tool Deactivation (`assembly_3d_viewport.dart` & `assembly_onshape_sketch_dialog.dart`):**
  - Pressing `Escape` (or `V`) while any drawing tool (`line`, `circle`, `rectangle`, `dimension`, etc.) or constraint tool is active calls `vm.deactivateSketchToolToSelect()` to return to Select mode instead of prematurely closing the sketch.
  - Added a 1-click **`Select Mode (Esc)` / `End Tool (Esc)`** pill inside the floating `Sketch 1` dialog (`assembly_onshape_sketch_dialog.dart`).

### 3.3 Onshape `Sketch 2` Visual Elegance (`assembly_3d_surface_sketch_painter.dart` & `assembly_3d_plane_painter.dart`)
- **Even-Odd Shaded Closed Profiles (`assembly_3d_surface_sketch_painter.dart`):**
  - Uses `Path()..fillType = PathFillType.evenOdd` across all closed loops on the plane with Onshape's translucent cool-slate fill (`#3494A3B8`), so nested holes (`Ø12` inside `Ø33` in `image_41a6fb.png`) are automatically unshaded cutouts inside the shaded outer profile.
- **Parallel-Aligned Dimension Text & Narrow Span Outside Arrows (`assembly_3d_surface_sketch_painter.dart`):**
  - Linear dimensions (`99`, `90`, `65`, `60`, `75`) rotate their borderless text label parallel to the dimension line (`rotationRad: textAngle`, automatically kept upright in $(-\pi/2, \pi/2]$).
  - Narrow linear spans (`10` in `image_41a6fb.png`) automatically flip their arrowheads outside pointing inward (`_drawCadArrowhead(canvas, dimA, -dir, dimColor)`) with short external tails so the number is never overlapped by arrowheads.
- **Rotated Top-Left `"Sketch N"` Plane Frame (`assembly_3d_plane_painter.dart`):**
  - Dynamically expands the sky-blue sketch plane boundary (`#7DD3FC`) to enclose all sketch primitives and dimension witness lines, and renders `"Sketch 1"` / `"Sketch 2"` in the top-left corner rotated parallel to the top edge of the 3D plane (`image_41a6fb.png`).

### 3.4 Closed Polygon Topological Bonding + Break & Rejoin Feature (`onshape_sketch_modify_engine.dart`, `assembly_sketch_constraint_solver.dart`, `assembly_sketch_parameter_panel.dart`)
- **Unbreakable Closed Polygon Bond (`dragSegmentOrVertexPreservingBond` & `resizeLinePreservingPolygonBond`):**
  - When a polygon, rectangle, or closed line loop is bonded (`plane.isLoopBonded == true`):
    - Dragging any corner vertex moves all connected line endpoints sharing that vertex together.
    - Dragging any side translates that side's two endpoints AND moves the shared endpoints of the two adjacent connected sides along with it so the connected sides stretch/shorten and the polygon never breaks open!
    - Changing any side's length or angle dimension in the inline dimension editor (`commitInlineSketchDimension` $\to$ `_solveDimensional` $\to$ `_propagateBondedVertexShift`) shifts the connected neighbor segment's shared vertex by the exact same delta, keeping the polygon closed.
- **1-Click Break Polygon (`🔓 Break Loop`) & Rejoin Polygon (`🔗 Rejoin Loop`):**
  - Clicking **`Break Loop`** (in the Sketch Modify toolbar, Sketch Dialog, or bottom contextual bar) decomposes composite rectangles/regular polygons into individual `CADLineEntity` segments and marks them unbonded (`plane.unbondedEntityIds`) so individual segments can be moved away or detached freely.
  - Clicking **`Rejoin Loop`** snaps nearby open endpoints together (`snapTolerance = 25.0 mm`), clears `plane.unbondedEntityIds`, sets `plane.isLoopBonded = true`, and restores automatic Coincident corner constraints to seal the closed polygon!
