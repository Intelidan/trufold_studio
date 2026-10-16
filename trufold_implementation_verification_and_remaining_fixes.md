# TruFold Studio Implementation Verification Audit & Remaining Fixes

**Audit Scope:** Full verification of the uploaded `lib.zip` and `test.zip` against the Onshape 3D Visual Polish Spec (v4.0), the Surface Sketching Root-Cause Audit (`trufold_studio_sketch_audit_and_fixes.md`), and the Complete Onshape 2D/3D Sketching Engine Spec (`trufold_onshape_complete_sketch_engine_spec.md`).

## 1. Executive Scorecard

| Subsystem / Requirement | Status | Summary of Findings in Latest `lib/` & `test/` |
| :--- | :--- | :--- |
| **1. 3D Model Rendering: Shine & Studio Lighting** | **Implemented (95%)** | Both `flutter_scene_cad_mesh_builder.dart` (PBR `roughness: 0.22`, `metallic: 0.04`, ACES tone mapping, bent-normal AO) and `flutter_paint_3d_engine.dart` (3-light rig + hemisphere sky/ground ambient + GGX microfacet specular) are implemented. |
| **2. 3D Model Rendering: Corner Overhangs, Hole Spikes & Cracks** | **Implemented (90%)** | Consecutive duplicate hole vertices (`1e-4`) are stripped, shared 3D crease segments are deduplicated (`addedEdgeKeys`), and `0.75px` seam sealing eliminates diagonal triangle cracks on flat faces. |
| **3. 3D Model Rendering: Colors & Border Lines** | **Partial (Needs 3 Tweaks)** | Initial demo ladder rails use Onshape Steel-Blue (`#94B5CB`), **but**: (1) border lines are still pitch-black `#000000` instead of Onshape Slate-Charcoal `#1E2730`; (2) newly spawned parts in `AssemblyStudioViewModel` still default to dark slate grays (`#64748B`, `#546E7A`, `#37474F`); and (3) GPU edge ribbons in `flutter_scene_cad_mesh_builder.dart` still use world-space width (`0.55mm`) instead of constant screen-space pixels. |
| **4. "1 Circle Drawn = 3 Circles Rendered" Bug Fixes** | **Implemented (100%)** | `_handleTapUp` exits early when `activeSketchPlane != null` (`assembly_3d_viewport.dart:3275`), `addPrimitiveEntityToActivePlane` no longer mutates `part.sketches` (`assembly_studio_viewmodel.dart:3614`), and `_plane2DToPartFaceLocal` converts centroid coordinates to part-local coordinates (`viewmodel:3602`, `assembly_extrude_engine.dart:451`). |
| **5. All 10 Onshape Sketch Groups & 43 Tools** | **Implemented (95%)** | All 43 tools in `onshapeSketchGroups` (`onshape_toolbar_items.dart:597–1084`) are set to `isImplemented: true`, all 12 new primitive classes exist in `cad_models.dart:533–1083`, `OnshapeSketchModifyEngine` is complete, and viewport click/painter handlers are wired—**except** clicking with the `dimension` (`D`) tool active has no handler in `assembly_3d_viewport.dart`. |
| **6. Multi-Profile Loop Validation & `100×` Scaling Fix** | **Partial (Needs 2 Fixes)** | `CADProfileValidator` returns `allClosedLoops` with `0.25mm` tolerance and `CADCornerModifier` uses `1.0mm` scale, **but**: (1) `Assembly3DSurfaceSketchPainter:90–109` still only shades `orderedPathVertices` (the last loop) instead of all loops in `allClosedLoops`; and (2) `Blind Cut` in `assembly_part.dart:2342` still extrudes bore walls to full thickness `T` without a floor cap. |
| **7. Onshape 14 Constraints & DOF Solver** | **Partial (Needs 4 Fixes)** | All 14 constraint cases exist in `AssemblySketchConstraintSolver`, **but**: (1) over-constrained / conflicting entities never turn Red (`#EF4444`); (2) `_getEntityCenterOrAnchor` and `_shiftEntityTo` ignore the 10 newly added primitives (Ellipse, Polygon, Slot, AlignedRect, etc.); (3) `Midpoint`/`Pierce` deduct only `1` DOF instead of `2`; and (4) `Curvature` (`Shift+U`) only calls `_solveCoincident`, which fails on splines and arcs. |

## 2. Detailed Audit of 3D Model Rendering (Onshape Look & Feel)

### What Is Working Well
1. **GGX Studio Shine & Hemisphere Lighting (`flutter_paint_3d_engine.dart:211–253` & `assembly_3d_viewport.dart:288–326`):**
   * The 2D Canvas engine computes view-space hemisphere ambient (`hemiFactor`), wrap-around key diffuse (`wrapKey`), and GGX microfacet specular (`roughness = 0.24`, clamped at `0.38`) so curved bends and cylinder bores get a crisp anodized/plastic sheen while flat faces remain uniform without white clipping.
   * The GPU engine uses `ToneMappingMode.aces`, ground-truth Ambient Occlusion (`ambientOcclusionBentNormals: true`), and `PhysicallyBasedMaterial(metallicFactor: 0.04, roughnessFactor: 0.22)`.
2. **Corner Overhangs ("Ears"), Hole Spikes & Diagonal Face Cracks Fixed (`flutter_scene_cad_mesh_builder.dart:190–266` & `flutter_paint_3d_engine.dart:299–397`):**
   * Consecutive duplicate vertices on circular hole rims are filtered out (`(pt - rawPts.first).Length < 1e-4`), eliminating `NaN` miter spikes.
   * Shared 3D crease segments are deduplicated via `addedEdgeKeys` / `addedWireframeEdgeKeys` (`kA.compareTo(kB) <= 0 ? '$kA|$kB' : '$kB|$kA'`), preventing double-drawn overlapping corner lines.
   * Flat triangle faces on the 2D Canvas are sealed with a `0.75px` same-color `seamBleedPaint` stroke (`flutter_paint_3d_engine.dart:519–525`), eliminating diagonal hypotenuse cracks.

### 3 Remaining Rendering Issues & Exact Fixes

#### Issue R1: Border Lines Are Pure Pitch-Black (`#000000`) Instead of Onshape Slate-Charcoal (`#1E2730`)
* **Where:**
  * `lib/sheet_metal_studio/engine/flutter_scene_cad_mesh_builder.dart` (**line 320**): `Color edgeColor = const Color(0xFF000000);`
  * `lib/sheet_metal_studio/views/widgets/viewport_3d/painters/flutter_paint_3d_engine.dart` (**lines 637 & 647**): `color = const Color(0xFF000000)` and `strokeWidth = 1.25`.
* **Why it matters:** Pure `#000000` at `100%` opacity looks harsh and cartoon-like against steel-blue faces. Onshape uses dark slate-charcoal (`#1E2730` with `88%–90%` opacity and `1.15px` width).
* **Fix:**
```dart
// In lib/sheet_metal_studio/engine/flutter_scene_cad_mesh_builder.dart (line 320):
Color edgeColor = const Color(0xE01E2730); // Onshape dark slate-charcoal

// In lib/sheet_metal_studio/views/widgets/viewport_3d/painters/flutter_paint_3d_engine.dart (lines 637 & 647):
final wirePaint = Paint()
  ..color = isGlassMode ? const Color(0xB81E2730) : const Color(0xE61E2730)
  ..strokeWidth = 1.15
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;
```

#### Issue R2: Newly Spawned Parts in `AssemblyStudioViewModel` Still Use Dark Slate-Gray Colors
* **Where:** `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` (**lines 1710–1830**, **1961–2108**, and **4611–4733**).
* **Why it matters:** While the initial demo ladder (`rail_left`, `rail_right`, `rung_1..4` at lines 4478–4521) was updated to Onshape Steel-Blue (`#94B5CB` and `#82A4BA`), adding any new Straight Rail, Bent Rail, C-Channel, L-Angle, Flat Bar, or I-Beam from the toolbar still assigns dark slate grays (`#64748B`, `#546E7A`, `#455A64`, `#37474F`).
* **Fix:** Update the fallback colors in `placePendingPartAt` (lines 1710–1830) and `addRung` / `addChannel` / `addAngle` / `addRod` / `addFlatBar` / `addIBeam` / `addStraightRail` / `addBentRail` (lines 1961–2108) to the Onshape CAD palette (`#94B5CB`, `#82A4BA`, `#749CBE`, `#6B93B5`).

#### Issue R3: `cad_solid_builder_v4.dart` & `cad_topological_edge_builder.dart` Are Unused Standalone Files
* **Where:** `lib/sheet_metal_studio/engine/cad_solid_builder_v4.dart` and `lib/sheet_metal_studio/engine/cad_topological_edge_builder.dart`.
* **Why it matters:** Your agent created both files in `lib/sheet_metal_studio/engine/`, but nothing in `lib/` imports them (`FlutterSceneCadMeshBuilder` still uses `_addThickLineLoop` with a fixed `0.55mm` world-space ribbon width at line 187). When zooming in close on the GPU viewport, `0.55mm` ribbons scale up with camera zoom, whereas when zooming far out they become sub-pixel. Scaling `width` dynamically by camera distance or wiring `CadEdgeBuilder` keeps borders constant in screen space.

## 3. Detailed Audit of 2D/3D Surface Sketching & Extrude/Cut

### What Is Working Well
1. **Zero Duplicate Circles (`assembly_3d_viewport.dart:3275` & `assembly_studio_viewmodel.dart:3602–3626`):**
   * Drawing 1 circle on a part face now creates strictly 1 circle on `activeSketchPlane.primitives` and **0** premature cuts in `part.sketches`.
   * Executing a cut or extrude converts `(cxPlane, cyPlane)` through `_plane2DToPartFaceLocal()` (`plane.toWorld` $\to$ `part.worldToLocal`), placing the 3D hole at the exact spot on the rail rather than at the global datum origin.
2. **All 43 Sketch Toolbar Items Enabled (`onshape_toolbar_items.dart:597–1084`):**
   * Every tool across all 10 groups (`lines`, `rectangles`, `circles_and_ellipses`, `arcs_and_conics`, `polygons`, `splines`, `point_text_project`, `sketch_modify`, `pattern_and_insert`, `constraints`) has `isImplemented: true`.
3. **Modify Engine Suite (`onshape_sketch_modify_engine.dart:1–365`):**
   * `trimAtPoint`, `extendAtPoint`, `splitAtPoint`, `offsetEntity`, `mirrorEntitiesAcrossLine`, `createSketchLinearPattern`, and `createSketchCircularPattern` are cleanly implemented and verified by unit tests in `test/modules/assembly_studio/onshape_complete_sketch_engine_test.dart`.

### 3 Remaining Sketching & Cut Issues & Exact Fixes

#### Issue S1: Multi-Loop Interior Profile Shading Only Fills the Last Drawn Shape
* **Where:** `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart` (**lines 89–109**).
* **Root Cause:** `CADProfileValidator.validateProfile()` now extracts all closed loops into `validation.allClosedLoops`, but `Assembly3DSurfaceSketchPainter.paint()` still only draws a filled `Path` for `validation.orderedPathVertices` (which is only `closedLoops.last`). If a user draws 2 circles or a rectangle and a circle, the first shape loses its translucent blue Onshape region shading.
* **Fix:** Loop over `validation.allClosedLoops` in `Assembly3DSurfaceSketchPainter.paint()`:
```dart
// In lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart (lines 89-109):
    // 2. Interior Shaded Tessellated Profiles (shade ALL valid closed loops on the plane!)
    final validation = viewModel.activeSketchValidation;
    if (viewModel.showSketchProfileShading && validation != null && validation.isValidClosedLoop) {
      final loopsToFill = validation.allClosedLoops.isNotEmpty
          ? validation.allClosedLoops
          : (validation.orderedPathVertices.length >= 3 ? [validation.orderedPathVertices] : <List<Offset>>[]);
      final fillPaint = Paint()
        ..color = const Color(0x380284C7)
        ..style = PaintingStyle.fill;

      for (final loop in loopsToFill) {
        if (loop.length < 3) continue;
        final fillPath = Path();
        bool first = true;
        for (final pt in loop) {
          final scr = toScreen(pt);
          if (scr == Offset.zero) continue;
          if (first) {
            fillPath.moveTo(scr.dx, scr.dy);
            first = false;
          } else {
            fillPath.lineTo(scr.dx, scr.dy);
          }
        }
        if (!first) {
          fillPath.close();
          canvas.drawPath(fillPath, fillPaint);
        }
      }
    }
```

#### Issue S2: Clicking a Sketch Entity with the `Dimension ('D')` Tool Active Does Not Trigger `applyDrivingSketchDimension`
* **Where:** `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**around line 1615**).
* **Root Cause:** Selecting the Dimension tool (`D`) sets `vm.activeSketchTool = 'dimension'`, and `vm.applyDrivingSketchDimension(...)` exists in `AssemblyStudioViewModel` (line 3853), but `assembly_3d_viewport.dart` has no `else if (tool == 'dimension')` handler inside `onPointerDown`!
* **Fix:** In `assembly_3d_viewport.dart` (right after `else if (tool == 'split')` at line 1615), when `tool == 'dimension'`, hit-test the clicked primitive, select it, and either apply a driving dimension constraint (locking its current radius/diameter/length as a driving `CadConstraint` and focusing the VCB/parameter panel) so the entity immediately receives a driving dimension constraint:
```dart
// In lib/assembly_studio/views/widgets/assembly_3d_viewport.dart (right after tool == 'split' at line 1615):
                              } else if (tool == 'dimension') {
                                CADPrimitiveEntity? hitPrim;
                                for (final p in plane.primitives.reversed) {
                                  if (p is CADCircleEntity && (localPoint - p.center).distance <= p.radius + 6.0) {
                                    hitPrim = p;
                                    break;
                                  } else if (p is CADLineEntity && _distanceToSegment(localPoint, p.start, p.end) <= 6.0) {
                                    hitPrim = p;
                                    break;
                                  } else {
                                    for (final seg in p.toLineSegments()) {
                                      if (_distanceToSegment(localPoint, seg.start, seg.end) <= 6.0) {
                                        hitPrim = p;
                                        break;
                                      }
                                    }
                                    if (hitPrim != null) break;
                                  }
                                }
                                if (hitPrim != null) {
                                  vm.selectSketchPrimitive(hitPrim);
                                  final double currentVal = hitPrim is CADCircleEntity
                                      ? hitPrim.radius * 2.0
                                      : hitPrim is CADLineEntity
                                          ? (hitPrim.end - hitPrim.start).distance
                                          : hitPrim is CADRectangleEntity
                                              ? hitPrim.width
                                              : 20.0;
                                  vm.applyDrivingSketchDimension(
                                    entityId: hitPrim.id,
                                    valueMmOrDeg: currentVal,
                                  );
                                  vm.setVcbState(
                                    label: '📏 Driving Dimension',
                                    value: '${currentVal.toStringAsFixed(1)} mm',
                                    hint: 'Type new dimension in mm + Enter',
                                  );
                                  setState(() {});
                                }
                                return;
                              }
```

#### Issue S3: `Blind Cut` Bore Walls Still Extrude to Full Wall Thickness `T` Without a Pocket Floor Cap
* **Where:** `lib/assembly_studio/models/assembly_part.dart` (**lines 1244, 1248, 1285, and 2342–2373**).
* **Root Cause:** Although `innerWebHoles` and `innerTopHoles` now pass `throughOnly: true` so a blind cut does not punch through the back wall, `_addHoleBoreWalls(thickPolys, webHoles, normal, T)` still uses the full wall thickness `T` for every hole's bore depth and does not add a floor cap polygon at `math.min(sk.cutDepthMm, T)` when `!sk.isPassThrough && sk.cutDepthMm < T`.

## 4. Detailed Audit of All 14 Onshape Constraints & DOF Solver

### What Is Working Well
* All 14 constraint types (`coincident`, `concentric`, `parallel`, `tangent`, `horizontal`, `vertical`, `perpendicular`, `equal`, `midpoint`, `normal`, `pierce`, `symmetric`, `fixed`, `curvature`) are wired into the toolbar (`onshape_toolbar_items.dart:965–1083`) and dispatched in `AssemblySketchConstraintSolver._applySingleConstraint()` (`assembly_sketch_constraint_solver.dart:145–183`).
* `Symmetric`, `Midpoint`, `Normal`, and `Pierce` work accurately for lines, circles, and points.

### 4 Constraint Solver Bugs to Fix

#### Bug C1: Over-Constrained / Conflicting Entities Never Turn Red (`#EF4444`)
* **Where:**
  * `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart` (**lines 100–126**)
  * `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart` (**lines 114–126**)
* **Root Cause:**
  1. In `AssemblySketchConstraintSolver.solve()`, if a user applies two conflicting constraints to the same entity (for example, both `Horizontal` and `Vertical` on the same line, or two different `diameter` dimensions on the same circle, or `Horizontal` on a `Fixed` tilted line), `_applySingleConstraint` blindly overwrites the coordinates and returns `true`.
  2. In `Assembly3DSurfaceSketchPainter.paint()` (lines 115–125), `strokePaint.color` only checks `isSel`, `isProjected`, `isConstruction`, and `isConstrained`—it never checks if the entity belongs to a conflicting constraint in `viewModel.lastConstraintSolverResult?.conflictingConstraints`!
* **Fix:**
  1. In `AssemblySketchConstraintSolver.solve()`, detect conflicting constraint pairs (e.g., `horizontal` + `vertical` on the same 1-entity line, duplicate dimensional constraints with different `parameterValue`, or geometric constraints that fail a post-iteration residual check) and add them to `conflicting`.
  2. In `Assembly3DSurfaceSketchPainter.paint()` (line 115), highlight any entity referenced by `conflictingConstraints` (or constraint badges in `conflictingConstraints`) in Onshape Over-Constrained Evil Red (`const Color(0xFFEF4444)`):
```dart
// In lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart (line 114):
      final isOverConstrained = viewModel.lastConstraintSolverResult?.conflictingConstraints
              .any((c) => c.entityIds.contains(prim.id)) ??
          false;
      final strokePaint = Paint()
        ..color = isOverConstrained
            ? const Color(0xFFEF4444) // Onshape Red for over-constrained / conflicting geometry!
            : isSel
            ? const Color(0xFFF59E0B) // Amber for selected
            : prim.isProjected
            ? const Color(0xFFC084FC) // Purple/Magenta for projected geometry
            : prim.isConstruction
            ? const Color(0xFF38BDF8) // Light blue for construction
            : isConstrained
            ? const Color(0xFF0F172A) // Black / Slate 900 for fully constrained geometry
            : const Color(0xFF0284C7) // Blue for under-constrained geometry
```

#### Bug C2: `_getEntityCenterOrAnchor` & `_shiftEntityTo` Ignore the 10 New Sketch Primitives
* **Where:** `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart` (**lines 46–62** and **523–559**).
* **Root Cause:** `computeInitialDof`, `_getEntityCenterOrAnchor`, and `_shiftEntityTo` were not updated when the 10 new primitive classes (`CADAlignedRectangleEntity`, `CADEllipseEntity`, `CADCenterPointArcEntity`, `CADConicEntity`, `CADRegularPolygonEntity`, `CADSplineEntity`, `CADSlotEntity`, `CADTextEntity`) were added to `cad_models.dart`. Applying `Midpoint`, `Symmetric`, `Concentric`, or `Pierce` to any of those new shapes returns `Offset.zero` and does not move the shape!
* **Fix:** Add branches for all new primitives in `_getEntityCenterOrAnchor` and `_shiftEntityTo`:
```dart
// In lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart (lines 523-559):
  static Offset _getEntityCenterOrAnchor(CADPrimitiveEntity e) {
    if (e is CADLineEntity) {
      return Offset((e.start.dx + e.end.dx) / 2.0, (e.start.dy + e.end.dy) / 2.0);
    } else if (e is CADCircleEntity) {
      return e.center;
    } else if (e is CADEllipseEntity) {
      return e.center;
    } else if (e is CADCenterPointArcEntity) {
      return e.center;
    } else if (e is CADRegularPolygonEntity) {
      return e.center;
    } else if (e is CADSlotEntity) {
      return (e.startCenter + e.endCenter) * 0.5;
    } else if (e is CADAlignedRectangleEntity) {
      final c = e.corners;
      return (c[0] + c[2]) * 0.5;
    } else if (e is CADConicEntity) {
      return e.apexControlPoint;
    } else if (e is CADSplineEntity) {
      return e.controlPoints.isNotEmpty ? e.controlPoints.first : Offset.zero;
    } else if (e is CADTextEntity) {
      return e.origin;
    } else if (e is CADRectangleEntity) {
      return Offset(e.startPoint.dx + e.width / 2.0, e.startPoint.dy + e.height / 2.0);
    } else if (e is CADCenterRectangleEntity) {
      return e.center;
    } else if (e is CADArcEntity) {
      return e.computeCircumcircle()?.center ?? e.startPoint;
    } else if (e is CADPointEntity) {
      return e.position;
    }
    return Offset.zero;
  }

  static void _shiftEntityTo(CADPrimitiveEntity e, Offset newAnchor) {
    final curr = _getEntityCenterOrAnchor(e);
    final delta = newAnchor - curr;
    if (e is CADLineEntity) {
      e.start = e.start + delta;
      e.end = e.end + delta;
    } else if (e is CADThreePointCircleEntity) {
      e.p1 = e.p1 + delta;
      e.p2 = e.p2 + delta;
      e.p3 = e.p3 + delta;
      e.recomputeFromThreePoints();
    } else if (e is CADCircleEntity) {
      e.center = newAnchor;
    } else if (e is CADEllipseEntity) {
      e.center = newAnchor;
    } else if (e is CADCenterPointArcEntity) {
      e.center = newAnchor;
    } else if (e is CADRegularPolygonEntity) {
      e.center = newAnchor;
    } else if (e is CADSlotEntity) {
      e.startCenter = e.startCenter + delta;
      e.endCenter = e.endCenter + delta;
    } else if (e is CADAlignedRectangleEntity) {
      e.corner1 = e.corner1 + delta;
      e.corner2 = e.corner2 + delta;
    } else if (e is CADConicEntity) {
      e.startPoint = e.startPoint + delta;
      e.endPoint = e.endPoint + delta;
      e.apexControlPoint = e.apexControlPoint + delta;
    } else if (e is CADSplineEntity) {
      for (int i = 0; i < e.controlPoints.length; i++) {
        e.controlPoints[i] = e.controlPoints[i] + delta;
      }
    } else if (e is CADTextEntity) {
      e.origin = newAnchor;
    } else if (e is CADRectangleEntity) {
      e.startPoint = e.startPoint + delta;
    } else if (e is CADCenterRectangleEntity) {
      e.center = newAnchor;
    } else if (e is CADArcEntity) {
      e.startPoint = e.startPoint + delta;
      e.endPoint = e.endPoint + delta;
      e.pointOnArc = e.pointOnArc + delta;
    } else if (e is CADPointEntity) {
      e.position = newAnchor;
    }
  }
```

#### Bug C3: `Midpoint` and `Pierce` Deduct Only `1` DOF Instead of `2` DOFs
* **Where:** `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart` (**lines 507–517**).
* **Root Cause:** Locking a point or circle center to a line's midpoint (`Midpoint`) or to a 3D pierce point (`Pierce`) constrains both $X$ and $Y$ (`2` DOFs), whereas `_deductDegreesOfFreedom` only subtracts `1` DOF. Move `CadConstraintType.midpoint`, `CadConstraintType.pierce`, and `CadConstraintType.symmetric` to the `- 2` DOF block alongside `concentric` and `coincident`.

#### Bug C4: `_solveCurvature` (`Shift+U`) Fails on Splines, Conics & Arcs
* **Where:** `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart` (**lines 652–654**).
* **Root Cause:** `_solveCurvature` delegates to `_solveCoincident`, which only checks `if (e1 is CADLineEntity && e2 is CADLineEntity)` or `else if (e2 is CADLineEntity)`. When applied to a `CADSplineEntity`, `CADConicEntity`, or `CADArcEntity`, it returns `false` and marks the constraint as conflicting.
* **Fix:** Update `_solveCurvature` so it snaps the closest endpoints of splines, arcs, conics, or lines together and aligns their tangent control points at the shared junction.
