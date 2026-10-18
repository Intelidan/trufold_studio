# TruFold Studio: Onshape Sketcher, Extrude Isolation & Viewport Fixes (v2)
**Repository:** `Intelidan/trufold_studio`  
**Target Modules:** `lib/assembly_studio/`, `lib/sketch_draft_files/`, `shaders/`  
**Architecture Rules:** Single-precision `vector_math` (`Float32List`), Dual-Pipeline Symmetry (Flutter GPU + Canvas 2D Fallback), 120 FPS Zero-Allocation Hover Loop.

---

## 1. Fix Amber Hole Center Point Clutter on Part Selection (`SS1`)

### Problem
When selecting a 3D model or multi-part assembly, all hole center points across all parts highlight in amber (`#FFAB00`). Hole center points are strictly for proximity snapping or explicit point selection.

### Code Changes (`lib/assembly_studio/assembly_3d_viewport.dart` & `assembly_studio_viewmodel.dart`)
1. In `AssemblyStudioViewModel`, separate part selection from snap-point selection:
   ```dart
   final Set<String> selectedPartIds = {};
   final Set<String> selectedSnapPointIds = {};
   String? hoveredSnapPointId;
   ```
2. In `AssemblyOverlayPainter.paint(Canvas canvas, Size size)`:
   - **Remove** the loop that draws amber circles for all `part.holeCenters` when `selectedPartIds.contains(part.id)`.
   - Only render a hole center / snap point if **one** of the following is true:
     1. `viewModel.selectedSnapPointIds.contains(snapPoint.id)` (Explicitly clicked by the user).
     2. `viewModel.hoveredSnapPointId == snapPoint.id` (Mouse cursor is within `kSnapHoverRadiusPx = 18.0` pixels during an active Sketch, Move, or Measure tool).

```dart
void _paintHoleCenterSnapPoints(Canvas canvas, Size size) {
  final cursorScreen = viewModel.currentCursorScreenPos;
  final isSnappingToolActive = viewModel.isSketchModeActive ||
      viewModel.activeTool == StudioTool.move ||
      viewModel.activeTool == StudioTool.measure;

  for (final snap in viewModel.sceneSnapPoints) {
    final bool isExplicitlySelected = viewModel.selectedSnapPointIds.contains(snap.id);
    if (!isExplicitlySelected && !isSnappingToolActive) continue;

    final Offset? screenPt = projectWorldToScreen(snap.worldPosition, size);
    if (screenPt == null) continue;

    final double distToCursor = cursorScreen != null
        ? (screenPt - cursorScreen).distance
        : double.infinity;

    // Only show if explicitly selected OR cursor is within 18px proximity
    if (isExplicitlySelected || distToCursor <= 18.0) {
      final Paint fillPaint = Paint()
        ..color = isExplicitlySelected
            ? const Color(0xFFFFAB00) // Amber for selected
            : const Color(0xFF00E5FF) // Cyan for proximity snap preview
        ..style = PaintingStyle.fill;

      canvas.drawCircle(screenPt, isExplicitlySelected ? 4.5 : 3.5, fillPaint);
    }
  }
}
```

---

## 2. Lock Camera Position & Zoom During Sketch & Tool Transitions

### Problem
Activating Sketch Mode zooms the camera out; deactivating it zooms the camera back in. The camera must remain strictly where the user placed it.

### Code Changes (`lib/assembly_studio/assembly_studio_viewmodel.dart`)
1. Audit `enterSketchMode()`, `exitSketchMode()`, `activateExtrudeTool()`, and `selectEntity()`.
2. **Delete** all automatic calls to:
   - `_animateCameraToPlane()`
   - `fitCameraToBounds()`
   - `_cameraDistance = defaultSketchDistance`
   - `_savedCameraState` restore/override blocks on mode toggle.
3. Preserve the exact camera state matrices:
   ```dart
   void enterSketchMode(SketchPlane targetPlane) {
     // DO NOT mutate _cameraPosition, _cameraTarget, or _cameraDistance.
     _activeSketchPlane = targetPlane;
     _isSketchModeActive = true;
     notifyListeners();
   }

   void exitSketchMode({required bool commitChanges}) {
     // DO NOT restore or tween camera distance/zoom.
     if (!commitChanges) {
       _revertActiveSketchSession();
     }
     _isSketchModeActive = false;
     _activeSketchTool = SketchTool.none;
     notifyListeners();
   }
   ```

---

## 3. Fix Pitch-Dark Opposite Faces on 3D Parts (`SS1` Lighting Fix)

### Problem
Opposite faces of C-channels and brackets facing away from the main directional light render nearly pitch black (`dot(N, L) <= 0.0`).

### Code Changes (`shaders/cad_pbr.frag` & Canvas 2D Face Shader in `assembly_3d_viewport.dart`)
1. **Camera-Attached Headlight + Half-Lambert Fill:** Ensure lighting is evaluated relative to the camera view vector `V` plus a hemisphere sky/ground gradient so no face ever drops below **45% brightness**.
2. **Normal Two-Sided Correction:** Flip normals that face away from the camera (`if (dot(N, V) < 0.0) N = -N;`) so thin sheet-metal flanges and boolean cuts never render inverted black faces.

```dart
// In Canvas / CPU Face Shading Pipeline & GPU Shader Equivalent:
Color computeCadFaceColor(Color baseColor, Vector3 worldNormal, Vector3 viewDir) {
  Vector3 n = worldNormal.normalized();
  final Vector3 v = viewDir.normalized();

  // 1. Two-sided normal guard for sheet metal & extruded walls
  if (n.dot(v) < 0.0) {
    n = -n;
  }

  // 2. Three-point studio rig in world + view space
  final Vector3 keyLight = Vector3(0.45, 0.80, 0.40).normalized();
  final Vector3 fillLight = Vector3(-0.60, -0.35, -0.70).normalized();

  // Half-Lambert wrapping prevents harsh black terminators on opposite sides
  final double keyTerm = (n.dot(keyLight) * 0.5 + 0.5);
  final double fillTerm = math.max(0.0, n.dot(fillLight));
  final double headlightTerm = math.max(0.0, n.dot(v)); // Camera headlight

  // Minimum ambient floor of 0.46 ensures opposite faces stay crisp CAD blue
  final double intensity = (0.38 +
          keyTerm * 0.36 +
          fillTerm * 0.18 +
          headlightTerm * 0.18)
      .clamp(0.46, 1.08);

  return Color.fromARGB(
    baseColor.alpha,
    (baseColor.red * intensity).round().clamp(0, 255),
    (baseColor.green * intensity).round().clamp(0, 255),
    (baseColor.blue * intensity).round().clamp(0, 255),
  );
}
```

---

## 4. Prevent Sketch Mode from Turning Off When Editing an Entity

### Problem
Editing a sketch entity (dragging a vertex, resizing a circle/rectangle, or confirming a dimension) automatically exits Sketch Mode.

### Code Changes (`lib/assembly_studio/assembly_3d_viewport.dart` & `assembly_studio_viewmodel.dart`)
1. Search the codebase for every place where `_isSketchModeActive = false` or `exitSketchMode()` is called.
2. Restrict `exitSketchMode()` **exclusively** to:
   - The **Confirm (Green Check)** button in the Sketch header bar.
   - The **Cancel (Red X)** button in the Sketch header bar.
3. In `onEntityEdited()` / `commitDimensionEdit()` / `onPointerUp()`:
   ```dart
   void updateSketchEntityGeometry(String entityId, SketchGeometry updatedGeom) {
     final sketch = activeSketch;
     if (sketch == null) return;

     sketch.updateEntity(entityId, updatedGeom);
     solveConstraints(sketch);
     rebuildAssociativeFeatures(sketch.id);

     // CRITICAL: Stay in Sketch Mode after editing an entity!
     // Return tool to SketchSelect so user can continue editing other entities.
     _activeSketchTool = SketchTool.select;
     notifyListeners();
   }
   ```

---

## 5. Make the Extrude Dialog Box Draggable

### Problem
The Extrude dialog box is fixed in place and blocks the 3D geometry being extruded.

### Code Changes (`lib/assembly_studio/widgets/draggable_cad_dialog.dart`)
Create a reusable `DraggableCadDialog` wrapper and wrap both the **Extrude Dialog** and **Sketch Dialog**:

```dart
class DraggableCadDialog extends StatefulWidget {
  final Widget child;
  final Offset initialOffset;
  final double width;

  const DraggableCadDialog({
    super.key,
    required this.child,
    this.initialOffset = const Offset(24, 72),
    this.width = 290,
  });

  @override
  State<DraggableCadDialog> createState() => _DraggableCadDialogState();
}

class _DraggableCadDialogState extends State<DraggableCadDialog> {
  late Offset _offset;

  @override
  void initState() {
    super.initState();
    _offset = widget.initialOffset;
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    return Positioned(
      left: _offset.dx.clamp(8.0, math.max(8.0, screenSize.width - widget.width - 8.0)),
      top: _offset.dy.clamp(8.0, math.max(8.0, screenSize.height - 260.0)),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onPanUpdate: (DragUpdateDetails details) {
          setState(() {
            _offset += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          child: widget.child,
        ),
      ),
    );
  }
}
```

---

## 6. Isolate Extrude & Cut Operations Per Selected Sketch Profile (`SS2`)

### Problem
In `SS2`, extruding or cutting one selected sketch entity (e.g., the circle) forces all other entities in the same sketch (e.g., the tilted rectangle) to extrude or cut with the exact same parameters.

### Root Cause
`AssemblyExtrudeEngine` was iterating over `sketch.entities` instead of filtering by the specific `selectedProfileIds` stored on the individual `ExtrudeFeature`.

### Code Changes (`lib/assembly_studio/assembly_extrude_engine.dart` & `assembly_studio_viewmodel.dart`)
1. Give each `SketchEntity` / `ClosedProfile` its own unique `id`.
2. Define `ExtrudeFeatureSpec` to bind strictly to `targetProfileIds`:
   ```dart
   class ExtrudeFeatureSpec {
     final String featureId;
     final String sketchId;
     final Set<String> targetProfileIds; // ONLY these profiles are extruded/cut
     ExtrudeOperation operation; // newBody, add, cut, intersect
     double depthMm;
     bool isSymmetric;

     ExtrudeFeatureSpec({
       required this.featureId,
       required this.sketchId,
       required Set<String> targetProfileIds,
       this.operation = ExtrudeOperation.add,
       this.depthMm = 25.0,
       this.isSymmetric = false,
     }) : targetProfileIds = Set<String>.from(targetProfileIds);
   }
   ```
3. In `AssemblyExtrudeEngine.buildFeatureGeometry()`:
   ```dart
   List<CadSolidBody> executeExtrudeFeature(
     SketchPlane sketch,
     ExtrudeFeatureSpec featureSpec,
     List<CadSolidBody> existingBodies,
   ) {
     // Filter strictly to the profiles assigned to THIS featureSpec
     final List<SketchEntity> targetEntities = sketch.entities
         .where((e) => featureSpec.targetProfileIds.contains(e.id) && e.isClosedProfile)
         .toList();

     if (targetEntities.isEmpty) return existingBodies;

     // Generate independent 3D prism/cut only for targetEntities
     return _applyBooleanExtrude(
       targetEntities: targetEntities,
       operation: featureSpec.operation,
       depthMm: featureSpec.depthMm,
       existingBodies: existingBodies,
     );
   }
   ```
4. When the user opens the Extrude dialog and clicks a second sketch entity, only add it to the current `ExtrudeFeatureSpec.targetProfileIds` if the Extrude dialog's **"Faces and sketch regions to extrude"** selector box is active. Otherwise, separate extrude operations create separate `ExtrudeFeatureSpec` nodes in the feature tree.

---

## 7. Eliminate Distracting Vertex / Bounding Box Dot Clutter (`SS2`)

### Problem
`SS2` displays dozens of cyan, green, purple, and amber dots floating across the extruded cylinder, rectangle, and wireframe bounding box.

### Root Cause
1. The 27-point OBB (`OrientedBoundingBox`) gizmo dots are being drawn whenever a feature or part is selected, even when the `Move` tool is inactive.
2. When a circle is extruded into a 32-segment cylinder, all 32 perimeter vertices on the top and bottom rings are being registered as snap/control dots.
3. Inactive sketch constraint/midpoint dots are rendered globally.

### Code Changes (`lib/assembly_studio/assembly_3d_viewport.dart` & `assembly_extrude_engine.dart`)
1. **Hide 27-Point OBB Dots Unless Move Tool is Active:**
   ```dart
   if (viewModel.activeTool == StudioTool.move && viewModel.selectedPartIds.isNotEmpty) {
     _paint27PointMoveAnchors(canvas, size);
   }
   ```
2. **Do Not Register Cylinder Tessellation Vertices as Snap Points:**
   In `AssemblyExtrudeEngine`, when generating a cylinder mesh from a `SketchCircle`:
   - Tag the 32 side-wall vertices with `isTessellationVertex = true`.
   - Only export **2 snap points** for a cylinder/hole: `topCenter` and `bottomCenter` (plus the 4 quadrant points at $0^\circ, 90^\circ, 180^\circ, 270^\circ$ only when hovered).
3. **Cull Sketch Control Dots by Entity Hover/Selection:**
   Inside `SketchOverlayPainter`:
   - Do **not** draw midpoint, quadrant, or corner dots for all entities at once.
   - Only draw manipulation handles for the **single entity currently selected or hovered** inside active Sketch Mode.