# TruFold Studio: Complete Root-Cause Audit & Implementation Guide for All 7 Sketching, Extrude Cut & Onshape UX Fixes

**Repository Audited:** [Intelidan/trufold_studio](https://github.com/Intelidan/trufold_studio) (`master` branch, latest commit `0649b49` — *"Update 8 files for CAD studio and assembly viewport"*)  
**Drop-In Updated Files Archive:** `trufold_onshape_sketch_ux_updated_files.zip`

---

## 1. Executive Summary & Root-Cause Matrix for All 7 Issues

| # | Reported Issue | Exact File & Line Numbers in `master` (`0649b49`) | Root Cause in Code | Exact Fix Applied |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Remove camera reset on double-click** | `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**lines 2204, 2604**) & `lib/sheet_metal_studio/views/widgets/viewport_3d/flutter_scene_viewport_widget.dart` (**line 1698**) | **1)** `GestureDetector(onDoubleTap: _zoomToFit)` in both `assembly_3d_viewport.dart:2604` and `flutter_scene_viewport_widget.dart:1698` resets the camera zoom/pan/orbit whenever you double-click anywhere in the viewport (such as double-clicking a dimension tag or ending a polyline/spline).<br>**2)** In `assembly_3d_viewport.dart:2204`, `if (_clickCount == 2) vm.focusPartAndEnterSketch(...)` alsohijacked double-clicks on parts and re-centered the camera. | Removed `onDoubleTap: _zoomToFit` from both viewport `GestureDetector`s and removed the `_clickCount == 2` camera jump in `assembly_3d_viewport.dart`. |
| **2** | **SS1 (`image_3fcd80.jpg`): What are these yellow dotted lines?** | `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` (**lines 4074–4098**) & `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart` (**lines 410–429**) | Those are **Sketch Inference Alignment Guides** (`currentInferenceGuides`), meant to show a single horizontal or vertical alignment line when your cursor aligns with a key point. **Why they turned into thick yellow bands in SS1:** `updateSketchPlaneHover()` called `compilePlaneSegments(activeSketchPlane!)`, which tessellates every circle into **64 line segments** (`64` perimeter vertices), and then added a `600 mm` yellow dashed line for **every** vertex within `6.0 mm` of `rawLocalPos.dx` or `rawLocalPos.dy`! Hovering near a circle matched 15–20 perimeter vertices simultaneously, painting a thick band of parallel yellow dashed lines across the rail and vertically across the screen. | **1)** Changed `updateSketchPlaneHover()` to test **only true CAD key points** (Origin `(0,0)`, circle/arc centers, line endpoints/midpoints, and rectangle corners/centers—never the 64 tessellated perimeter points of a circle) with a tight `2.5 mm` snap tolerance, emitting at most **1 Horizontal** and **1 Vertical** guide.<br>**2)** Changed `Assembly3DSurfaceSketchPainter` to draw inference guides **only while actively drawing or dragging** (`sketchInteractiveStartPoint != null || isConstraintMode`), bounded cleanly between the reference vertex and the cursor! |
| **3** | **Clicking a dimension tag opens the editing box, but it doesn't accept numbers nor resize the entity** | `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**lines 715, 1002–1050, 1145–1157, 1229**) & `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` (**lines 3941–3995**) | **Three compounding bugs:**<br>**1) Keystroke interception (`assembly_3d_viewport.dart:1145`):** The parent `Focus(focusNode: _viewportFocusNode, onKeyEvent: ...)` only checked `!_vcbFocusNode.hasFocus`. When the floating dimension `TextField` had focus, `_viewportFocusNode.onKeyEvent` intercepted every number key (`0-9`, `.`, `-`), `Backspace` (line 1006), and `Enter` (line 1047, which called `vm.finishSketch()`!) and returned `KeyEventResult.handled`—blocking the `TextField` from receiving any numbers!<br>**2) Focus theft (`line 1229`):** Clicking inside the viewport immediately called `_viewportFocusNode.requestFocus()`, stealing focus away from the popover.<br>**3) Unconditional unit suffix re-insertion:** `_valueController` pre-filled `"36.1 mm"`, making typing awkward, and `commitInlineSketchDimension` did not directly update the primitive's radius/length/width before solving. | **1)** Added an `isTextInputFocused` guard at the top of `_viewportFocusNode.onKeyEvent` (`vm.activeEditingDimensionHit != null || primaryFocus.context?.widget is EditableText`) that returns `KeyEventResult.ignored` so all digits, `Backspace`, and `Enter` go straight to the dimension `TextField`.<br>**2)** Pre-filled the dimension `TextField` with the pure numeric string (`36.1`) with the unit (`mm` or `deg`) shown as a clean suffix label.<br>**3)** Updated `commitInlineSketchDimension` to directly resize the target primitive (`CADCircleEntity`, `CADLineEntity`, `CADRectangleEntity`, `CADCenterRectangleEntity`, `CADRegularPolygonEntity`, `CADSlotEntity`), run `solveSketchConstraints()`, and call `invalidateMeshCache()`. |
| **4** | **Extrude Cut does not cut the surface as intended (`SS2` & `SS3`)** | `lib/assembly_studio/engine/sketch/assembly_extrude_engine.dart` (**lines 440–478**), `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` (**lines 1054–1105, 5996**), & `lib/assembly_studio/models/assembly_part.dart` (**lines 1238, 2293**) | **Four bugs prevented Extrude Cut from cutting the 3D rail:**<br>**1) Stale Part Mesh Cache (`assembly_extrude_engine.dart:471` & `viewmodel.dart:5996`):** `executeExtrusion` appended `cutFeature` to `target.sketches`, and `executeExtrudeFeature` called `vm.invalidateMeshCache()`, which only cleared `_cachedAssemblyMesh = null`—it **never called `target.invalidateMeshCache()`**! So `target.build3DMesh()` returned its cached pre-cut `_cachedWorldMeshResult!` and the hole never appeared!<br>**2) Hardcoded `isPassThrough: false` (`assembly_extrude_engine.dart:465`):** Even with `Depth = -100.0 mm` (`SS2`), `isPassThrough` was hardcoded to `false`.<br>**3) Plane-2D vs. Part-Local-2D Offset Mismatch (`line 468`):** `customPolygonPoints` subtracted `(cx, cy)` in 2D sketch-plane axes instead of transforming each vertex via `plane.toWorld(p)` $\to$ `target.worldToLocal()`, AND included a duplicate closing vertex (`path.first == path.last`), which breaks Earcut hole triangulation.<br>**4) Staying in Sketch Mode after Cut:** After clicking `Extrude (E)`, the app stayed in 2D Sketch Mode, keeping the orange sketch circle (`Ø62.9` in `SS3`) drawn over the hole. | **1)** Added `target.invalidateMeshCache()` in `AssemblyExtrudeEngine.executeExtrusion` AND updated `vm.invalidateMeshCache()` to invalidate every part in `doc.parts`.<br>**2)** Set `isPassThrough: cutDepth >= target.thickness`, stripped the duplicate closing vertex, and mapped every loop vertex to part-local 2D coordinates via `plane.toWorld(p)` $\to$ `target.worldToLocal()`.<br>**3)** Updated `executeExtrudeFeature()` to extrude/cut **all** closed loops on the sketch plane and automatically call `finishSketch()` so the 3D cut hole is immediately visible. |
| **5** | **SS3 (`image_3fcda8.png`): The demo model's 4 mounting holes are not pass-through** | `lib/assembly_studio/models/assembly_part.dart` (**lines 1223–1239 & 1277–1287**) | In `_buildStraightRailPolygons()`, the 2×2 grid of Ø10mm splice mounting holes at both ends of the rail (`x in [35, 75, L-75, L-35]`) was added to `webHoles` (cutting the outer web face at `Y = 0`), **but line 1278 built `innerWebHoles` (at `Y = T * fDir`) ONLY from `_buildWebHoles(throughOnly: true)`**—completely omitting the 2×2 built-in splice holes! Thus, the inner web wall at `Y = T * fDir` remained a solid blue sheet blocking the back of all 4 holes (`SS3` top circle)! Furthermore, line 1238 passed a hardcoded `CadPoint3D(0, -1, 0)` normal to `_addHoleBoreWalls` instead of `CadPoint3D(0, -fDir, 0)`. | Built `innerWebHoles` from **all** non-blind loops in `webHoles` (so both the 2×2 demo splice holes AND user through-cuts punch cleanly through the inner web at `Y = T * fDir`) and passed `CadPoint3D(0.0, -fDir, 0.0)` to `_addHoleBoreWalls`. |
| **6** | **Deleting a constraint is not possible** | `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart` (**lines 392–408**), `assembly_3d_viewport.dart` (**line 1002**), & `assembly_sketch_parameter_panel.dart` | **1)** Constraint badges (`H`, `V`, `⊥`, `//`, `◎`, `=`) were painted on the canvas with **zero hit-test rectangles**, so clicking a constraint badge on the sketch did nothing.<br>**2)** Pressing `Delete` or `Backspace` in `assembly_3d_viewport.dart:1002` only checked `vm.selectedWeldId` and `vm.selectedPart`—it never checked `vm.selectedSketchConstraint`!<br>**3)** The floating dimension popover had no delete button to remove a driving dimension constraint. | **1)** Added `SketchConstraintBadgeHit` and `vm.sketchConstraintHitRects` so clicking any constraint badge on the canvas selects it (`vm.selectSketchConstraint`).<br>**2)** Wired `Delete` and `Backspace` in `assembly_3d_viewport.dart` to delete `vm.selectedSketchConstraint` (or `vm.selectedSketchEntity`).<br>**3)** Added a 1-click red **Delete (`🗑`)** button inside the dimension edit popover, a floating delete bar when a constraint badge is selected, and clickable `×` constraint chips on any selected entity! |
| **7** | **Make sketch lines, entities, hover highlighting (yellow), dimension tags/text, and sketch plane look sleek like Onshape (`SS4` / `image_3fcdde.png`)** | `assembly_3d_plane_painter.dart`, `assembly_3d_surface_sketch_painter.dart`, `assembly_3d_viewport.dart` (**line 4037**), & `onshape_toolbar_items.dart` (**lines 965–1083**) | **1) No Hover Highlight:** `_updateSketchHover()` never hit-tested sketch primitives or constraint badges under the mouse cursor, and selecting a constraint in the toolbar (`H`, `V`, `⊥`, `//`, `=`, `◎`) did nothing unless entities were pre-selected first.<br>**2) Cluttered Sketch Plane:** `Assembly3DPlanePainter` drew a heavy filled plane with a dense blue grid (`showSketchGrid = true`), central axis crosshairs, and kept all 3 global datum planes visible during sketching.<br>**3) Boxy Dimension Pills:** Dimension values were drawn inside bordered rectangular boxes instead of Onshape `SS4`'s clean borderless dark typography centered in a gap in the thin black witness/dimension line. | **1)** Added real-time entity & constraint hover detection in `_updateSketchHover()` (`hoveredSketchEntityId`, `hoveredSketchConstraintId`) + **Interactive Constraint Mode (`activeConstraintTool`)** so hovering over any line, circle, arc, or point highlights it in sleek Onshape Yellow/Orange (`#F59E0B`) with a soft halo, and clicking applies the constraint!<br>**2)** Styled `Assembly3DPlanePainter` and `Assembly3DSurfaceSketchPainter` to match Onshape `SS4` (`image_3fcdde.png`): thin sky-blue sketch plane frame (`#38BDF8`) with top-left `"Sketch 1"` label, crystal-clear interior (`showSketchGrid = false` by default), crisp black (`#0F172A`) / blue (`#0284C7`) geometry with filled dark vertex dots, and borderless dimension text centered in a clean break in the dimension line. |

---

## 2. Detailed Walkthrough of Changes by File

### 2.1 Remove Camera Reset on Double-Click (`assembly_3d_viewport.dart` & `flutter_scene_viewport_widget.dart`)
In `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart`:
1. Removed the double-click camera jump in `onPointerDown` (**line 2204**):
```dart
// REMOVED from lib/assembly_studio/views/widgets/assembly_3d_viewport.dart:
if (_clickCount == 2) {
  vm.focusPartAndEnterSketch(hitPart.id, faceId: hitPoly.faceId);
  return;
}
```
2. Removed `onDoubleTap: _zoomToFit` from the viewport `GestureDetector` (**line 2604** in `assembly_3d_viewport.dart` and **line 1698** in `lib/sheet_metal_studio/views/widgets/viewport_3d/flutter_scene_viewport_widget.dart`):
```dart
GestureDetector(
  behavior: HitTestBehavior.opaque,
  // Fix #1: Removed onDoubleTap: _zoomToFit so double-clicking never resets the camera!
  onTapUp: (details) {
    if (vm.isSketchMode || vm.pendingPlacement != null) {
      _handleTapUp(details.localPosition, size, mesh);
    }
  },
```

---

### 2.2 Fix SS1 Yellow Dotted Lines (`assembly_studio_viewmodel.dart` & `assembly_3d_surface_sketch_painter.dart`)
**What were those yellow dotted lines in `SS1` (`image_3fcd80.jpg`)?**
They are **Sketch Inference Alignment Guides** (`currentInferenceGuides`). Because `updateSketchPlaneHover()` previously called `compilePlaneSegments(activeSketchPlane!)`, every circle on the sketch plane was converted into **64 short line segments** (64 vertices around the perimeter). Whenever your mouse moved across the sketch plane, the loop checked all 64 perimeter vertices within `6.0 mm` in $X$ and $Y$ and spawned a `600 mm`-long yellow dashed line for **every** matching vertex—creating a solid band of parallel yellow dotted lines across the rail and vertically across the viewport!

**How we fixed it (`lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart:4069`):**
- `updateSketchPlaneHover()` now inspects **only true CAD key points** (Origin `Offset.zero`, circle/arc centers, line endpoints & midpoints, and rectangle corners/centers—never tessellated circle perimeter segments).
- Tightened the inference snap threshold to `2.5 mm` and emitted at most **one** Horizontal match (`bestH`) and **one** Vertical match (`bestV`).
- In `Assembly3DSurfaceSketchPainter.paint()`, inference guides only render while actively drawing a shape or applying a constraint, and draw a crisp, short dashed segment strictly from the reference key point (`match.refVertex`) to the current cursor position (`hoverLocal`)—just like Onshape!

---

### 2.3 Fix Inline Dimension Editing Box Not Accepting Numbers or Resizing Entities (`assembly_3d_viewport.dart`, `assembly_sketch_parameter_panel.dart`, `assembly_studio_viewmodel.dart`)
In `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**line 715**), `_viewportFocusNode.onKeyEvent` previously intercepted all number keys (`0-9`, `.`, `-`), `Backspace`, and `Enter` whenever the floating dimension popover (`AssemblySketchParameterPanel`) was open. We added an explicit focus check at the very top of `onKeyEvent`:

```dart
onKeyEvent: (node, event) {
  // CRITICAL FIX (Issue #3): When the inline dimension editor popover is open (or any TextField has focus),
  // let the TextField receive all digits (0-9, ., -), Backspace, and Enter directly!
  final primaryFocus = FocusManager.instance.primaryFocus;
  final isTextInputFocused = _vcbFocusNode.hasFocus ||
      vm.activeEditingDimensionHit != null ||
      (primaryFocus != null && primaryFocus != _viewportFocusNode && primaryFocus.context?.widget is EditableText);

  if (isTextInputFocused) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape && vm.activeEditingDimensionHit != null) {
      vm.closeInlineSketchDimensionEditor();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
```
And in `commitInlineSketchDimension()` (`assembly_studio_viewmodel.dart`), we directly update the primitive's geometry (`prim.radius`, line `start`/`end`, rectangle `width`/`height`, polygon `radius`, or slot `diameter`/`length`) before running `solveSketchConstraints()` and `invalidateMeshCache()`, guaranteeing that typing any number or formula (like `80` or `120/2`) and pressing `Enter` (or clicking `✓`) immediately resizes the entity!

---

### 2.4 Fix Extrude Cut Not Cutting the Surface (`SS2` & `SS3`) & Fix Demo Model's Non-Passthrough Holes (`SS3`)

#### A. Why the Demo Model's 4 Mounting Holes Were Not Pass-Through (`SS3` Top Circle)
In `lib/assembly_studio/models/assembly_part.dart` (**lines 1223–1287**), `_buildStraightRailPolygons` created the 2×2 grid of Ø10mm splice holes in `webHoles` (which cut the outer web at `Y = 0`), but **line 1278** built `innerWebHoles` (which cuts the inner web at `Y = T * fDir`) using only `_buildWebHoles(throughOnly: true)`—leaving the inner web solid blue behind all 4 demo holes!
We updated lines 1238 & 1278 in `lib/assembly_studio/models/assembly_part.dart` so all non-blind `webHoles` (both the built-in 2×2 splice holes and user through-cuts) cut `innerWebHoles` and extrude bore walls along `CadPoint3D(0.0, -fDir, 0.0)`:

```dart
    // Sketches & holes on web
    webHoles.addAll(_buildWebHoles(depthsOut: webDepths, isBlindOut: webBlind));
    _addBendLinePolygons(polys, H);
    // CRITICAL FIX (Issue #5 & #4): Bore walls must extrude from Y = 0 to Y = T * fDir!
    _addHoleBoreWalls(thickPolys, webHoles, CadPoint3D(0.0, -fDir, 0.0), T, holeDepths: webDepths, isBlindList: webBlind);
...
    // Inner Web face (real thickness T, Item 4 & Issue #5):
    // Include ALL non-blind webHoles (both the 2x2 built-in splice mounting holes AND user through-cuts)
    // so the demo model's 4 splice holes punch cleanly through the back wall (SS3)!
    final innerWebHoles = <List<CadPoint3D>>[
      for (int i = 0; i < webHoles.length; i++)
        if (i >= webBlind.length || !webBlind[i])
          webHoles[i].map((pt) => CadPoint3D(pt.x, T * fDir, pt.z)).toList(),
    ];
```

#### B. Why Extrude Cut Did Not Cut the Surface (`SS2` & `SS3` Bottom Circle)
In `lib/assembly_studio/engine/sketch/assembly_extrude_engine.dart` (**lines 440–478**):
1. Added `target.invalidateMeshCache()` after `target.sketches.add(cutFeature)` (and updated `vm.invalidateMeshCache()` to invalidate all parts in `doc.parts`) so `target.build3DMesh()` immediately rebuilds the 3D rail with the new hole instead of returning the stale cached mesh.
2. Stripped the duplicate closing vertex from `profilePoints` (`cleanLoop.first == cleanLoop.last`), mapped every vertex through `plane.toWorld(p)` $\to$ `target.worldToLocal(...)` into exact part-local 2D face coordinates, and set `isPassThrough: cutDepth >= target.thickness`.
3. In `executeExtrudeFeature()` (`assembly_studio_viewmodel.dart`), we now iterate over **all** closed loops in `validation.allClosedLoops` and call `finishSketch()` once the cut succeeds so the 3D hole is immediately visible without the 2D orange sketch circle covering it.

---

### 2.5 Fix Constraint Deletion & Onshape `SS4` Sketch Plane, Hover Highlight & Dimension Styling
1. **3 Ways to Delete Any Constraint (Issue #6):**
   - **Click any Constraint Badge (`H`, `V`, `⊥`, `//`, `◎`, `=`) on the Sketch:** Highlights the badge in amber and opens a floating **Delete Constraint (`🗑`)** bar; pressing `Delete` or `Backspace` (or clicking `🗑`) removes it immediately.
   - **Click any Driving Dimension Tag:** Opens the inline dimension popover, which now includes a red **Delete Driving Dimension (`🗑`)** button right next to `✓` and `✕`.
   - **Select any Constrained Sketch Entity:** The bottom quick-action bar lists all active constraints on that entity as clickable amber chips (`H ×`, `Ø62.9 ×`)—click any chip to remove that constraint in 1 click!
2. **Sleek Onshape `SS4` Visual Styling & Yellow Hover Highlight (Issue #7):**
   - **Interactive Constraint Mode & Yellow Hover Highlight (`#F59E0B`):** Selecting any constraint in the toolbar (`Coincident`, `Parallel`, `Perpendicular`, `Horizontal`, `Vertical`, `Tangent`, `Concentric`, `Equal`, etc.) arms `vm.activeConstraintTool`. Moving the mouse over any sketch line, circle, arc, or point highlights the hovered entity in **Onshape Yellow/Orange (`#F59E0B`)** with a soft glow; clicking the highlighted entity (or two entities for relational constraints) applies the constraint immediately.
   - **Onshape `SS4` Sketch Plane (`assembly_3d_plane_painter.dart`):** Renders a thin, crisp sky-blue rectangle border (`#38BDF8`, `1.2px`) with `"Sketch 1"` in the top-left corner, a crystal-clear interior (`showSketchGrid = false` by default), and automatically hides unselected global datum planes while sketching on a part face.
   - **Onshape `SS4` Dimension Callouts (`assembly_3d_surface_sketch_painter.dart`):** Thin black witness/extension lines (`0.95px`), slender filled CAD arrowheads, and **clean borderless dimension text** (`99`, `60`, `27°`, `Ø17`, `R10`) centered inside a break in the dimension line (with a subtle hover border when your mouse passes over the text to edit it).
