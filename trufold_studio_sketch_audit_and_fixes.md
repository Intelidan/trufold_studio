# TruFold Studio Repository Audit & Exact Code Fixes: `assembly_studio` & `sketch_draft_files`

## 1. Executive Summary of Findings

After auditing `lib/assembly_studio/` and `lib/sketch_draft_files/` in your `trufold_studio` repository, we identified **7 exact root-cause bugs**—including the exact lines of code that caused **1 drawn circle to produce 3 circles** in your screenshot (`image_6fb244.jpg`), why `Extrude` / `Fillet` / `Blind Cut` fail, and how three separate sketching generations are colliding.

| Bug / Symptom | Exact File & Line Numbers in `trufold_studio` | Root Cause in Code |
| :--- | :--- | :--- |
| **1. Drawing 1 Circle Creates Circle #2 (Ghost Hole at `(0,0)` Center of Rail)** | `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**lines 1369–1374**, **2074–2077**, and **3271–3322**) | When you click the 1st point (center) of a 2-click circle, `Listener.onPointerDown` (line 1371) sets `sketchInteractiveStartPoint` and returns while `activeSketchTool` is still `'circle'`. Immediately on mouse release, the child `GestureDetector.onTapUp` (line 2076) fires `_handleTapUp()` (line 3271), which executes legacy 1-click hole punching (`vm.addSketchFeature(featureType: 'circle', widthMm: 50.0)` at line 3313) right at the camera center (`(300, 50)` = `(0,0)` of `Sketch 1`)! |
| **2. Drawing 1 Circle Creates Circle #3 (Floating Circle on Right Datum Plane)** | `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` (**lines 3575–3625**) & `lib/assembly_studio/models/assembly_part.dart` (**lines 2277–2329**) | On the 2nd click of the circle, `addPrimitiveEntityToActivePlane()` (line 3589) **immediately** injects a `circle_hole` into `part.sketches` *before* Extrude/Cut is ever clicked, and copies **plane-centroid-relative** `entity.center = (-50, -10)` raw into **part-corner-relative** `feat.localCenter = (-50, -10)` (line 3599). Because `x = 0` of the rail is at the right end of the rail (at the datum triad), `x = -50` places a 3D hole `50mm` outside the right end of the rail on the datum plane! |
| **3. Multi-Shape Sketches Fail Validation (`"DANGLING GEOMETRY DETECTED"`)** | `lib/sketch_draft_files/math_and_processing/cad_profile_validator.dart` (**lines 15–52**) | `CADProfileValidator.validateProfile()` walks only **one** closed loop (`unvisited.removeAt(0)`) and then fails at **line 48** (`if (unvisited.isNotEmpty) return ValidationResult(isValidClosedLoop: false, reportFeedback: "DANGLING GEOMETRY DETECTED.")`). Drawing a 2nd circle, a rectangle + hole, or projecting a 3D edge (`isConstruction: false` at `viewmodel:787`) breaks loop validation and disables the `Extrude (E)` button! |
| **4. `100×` Unit Scale Mismatch in `sketch_draft_files` (`meters` vs `mm`)** | `lib/sketch_draft_files/math_and_processing/cad_corner_modifier.dart` (**lines 14, 34**) & `cad_constraint_solvers.dart` (**line 21**) | `sketch_draft_files` divides millimeter inputs by `100.0` (`double rad = radiusMm / 100.0;`), assuming 1 unit = 100mm, whereas `assembly_studio` uses `1 unit = 1.0 mm`. Clicking `Fillet 5mm` or `Chamfer 5mm` in `AssemblySketchParameterPanel` produces a `0.05mm` micro-segment and appends it to `plane.entities` without updating the rectangle in `plane.primitives`. |
| **5. `Extrude -> Cut` & `EXECUTE SURFACE FEATURE` Duplicate Features in Wrong Frame** | `lib/assembly_studio/engine/sketch/assembly_extrude_engine.dart` (**lines 440–471**) & `assembly_studio_viewmodel.dart` (**lines 3720–3781**) | Both methods append a **new** `AssemblySketchFeature` (`extruded_cut` / `custom_cut`) to `part.sketches` using plane-local `(cx, cy)` without converting through `plane.toWorld()` $\to$ `part.worldToLocal()`, and without removing the duplicate feature already added by `addPrimitiveEntityToActivePlane()`. |
| **6. Cuts Ignored on Non-Rail Faces & `Blind Cut` Ignored on Rails** | `lib/assembly_studio/models/assembly_part.dart` (**lines 2277–2330** & **1257, 1269**) | `_buildWebHoles()` only checks `targetFace.endsWith('_web')` and `_buildFlangeHoles()` only checks `flange_top`/`flange_bottom`. Cuts on `boxTubeStile` (`_boxtube_front`), `flatBar` (`_bar_top`), `angle` (`_leg_v`), or extruded bodies are ignored. Moreover, `isPassThrough: false` (`Blind Cut`) is ignored—all holes punch through both outer and inner walls. |
| **7. `CADBooleanEngine.executePassThroughCut` Deletes Whole Triangles** | `lib/sketch_draft_files/math_and_processing/cad_boolean_engine.dart` (**lines 11–44**) | `CADBooleanEngine` discards entire mesh triangles whose centroid lies inside the 2D loop (`if (_inside(center, path)) continue;`). On a rail face made of 2 large triangles, this either deletes half the rail face or does nothing, instead of passing hole contours to `CadPolygonTriangulator.triangulateWithHoles()`. |

## 2. Detailed Code Fixes for Your Coding Agent

### Fix 1: Stop `_handleTapUp` from Firing Legacy 1-Click Hole Punching During 2-Click Plane Sketching
**File:** `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**lines 2074–2078** and **3270–3322**)

In `assembly_3d_viewport.dart`, `Listener.onPointerDown` (line 1299) already handles all 3D Sketch Plane clicks (`rectangle`, `center_rect`, `circle`, `arc_3point`, `line`, `polyline`, `select_entity`). When `vm.activeSketchPlane != null`, `_handleTapUp` must **never** run its legacy `vm.addSketchFeature()` block!

```dart
// In lib/assembly_studio/views/widgets/assembly_3d_viewport.dart (around line 3270):
    // 2. DIRECT 3D SKETCHING ON THE MODEL (REAL-TIME 3D):
    if (vm.isSketchMode) {
      // CRITICAL FIX: When sketching on an active 3D CADSketchPlane, Listener.onPointerDown
      // handles all 2-click primitive creation and selection. Do NOT run legacy 1-click tap hole punching!
      if (vm.activeSketchPlane != null) {
        return;
      }
      // ... keep legacy fallback only if activeSketchPlane == null
```

### Fix 2: Stop `addPrimitiveEntityToActivePlane` from Prematurely Cutting the 3D Part & Fix Plane-to-Part Coordinate Conversion
**File:** `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` (**lines 3574–3781**)

In Onshape (`mastering-3d-modeling-ebook.pdf` p. 5 & `onshape.pdf` p. 6–8), drawing a 2D circle in Sketch Mode **only** adds the 2D `CADCircleEntity` to `activeSketchPlane.primitives`—it must **not** punch a hole in `part.sketches` until the user explicitly executes **Extrude (`Cut`)** or **Punch Pass-Through Cut (`executeFeatureCutOnActiveSurface`)**!
And when a cut *is* executed on a part face, you must convert the 2D sketch plane coordinate `Offset(u, v)` into the **Part's Local Coordinate System `(localX, localZ)`** via `plane.toWorld(uv)` $\to$ `part.worldToLocal(worldPt)`!

Add this helper method to `AssemblyPart` (`lib/assembly_studio/models/assembly_part.dart` right below `toWorld` at line 605):

```dart
  /// Inverse of [toWorld]: transforms a 3D World coordinate back into this part's local coordinate space [0..length, 0..height].
  CadPoint3D worldToLocal(CadPoint3D worldPt) {
    final dx = worldPt.x - position.x;
    final dy = worldPt.y - position.y;
    final dz = worldPt.z - position.z;

    final radX = -rotationDeg.x * math.pi / 180.0;
    final radY = -rotationDeg.y * math.pi / 180.0;
    final radZ = -rotationDeg.z * math.pi / 180.0;

    // Inverse Rz
    final x1 = dx * math.cos(radZ) - dy * math.sin(radZ);
    final y1 = dx * math.sin(radZ) + dy * math.cos(radZ);
    final z1 = dz;

    // Inverse Ry
    final x2 = x1 * math.cos(radY) + z1 * math.sin(radY);
    final y2 = y1;
    final z2 = -x1 * math.sin(radY) + z1 * math.cos(radY);

    // Inverse Rx
    final x3 = x2;
    final y3 = y2 * math.cos(radX) - z2 * math.sin(radX);
    final z3 = y2 * math.sin(radX) + z2 * math.cos(radX);

    return CadPoint3D(x3, y3, z3);
  }
```

Then update `addPrimitiveEntityToActivePlane`, `updateSelectedPrimitiveDimensions`, and `executeFeatureCutOnActiveSurface` in `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`:

```dart
  /// Converts a 2D point on [plane] into the host [part]'s local 2D face coordinates (0..length, 0..height).
  CadPoint2D _plane2DToPartFaceLocal(CADSketchPlane plane, AssemblyPart part, Offset planePt) {
    final worldVec = plane.toWorld(planePt);
    final local3D = part.worldToLocal(CadPoint3D(worldVec.x, worldVec.y, worldVec.z));
    final faceId = plane.targetFaceId ?? 'web';
    if (faceId.contains('flange_top') || faceId.contains('flange_bot') || faceId.contains('bar_top')) {
      return CadPoint2D(local3D.x, local3D.y.abs());
    }
    return CadPoint2D(local3D.x, local3D.z);
  }

  /// Adds a 2D parametric primitive entity directly to the active sketch plane.
  /// Pure Onshape behavior: drawing a 2D sketch curve NEVER mutates 3D part.sketches until Extrude/Cut is executed!
  void addPrimitiveEntityToActivePlane(CADPrimitiveEntity entity) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    activeSketchPlane!.primitives.add(entity);
    selectedSketchEntity = entity;
    selectedSketchFeatureId = entity.id;

    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(activeSketchPlane!);
    activeSketchValidation = CADProfileValidator.validateProfile(segments);

    solveSketchConstraints();
    notifyListeners();
  }
```

And in `executeFeatureCutOnActiveSurface` (`assembly_studio_viewmodel.dart:3720`) and `AssemblyExtrudeEngine.executeExtrusion` (`assembly_extrude_engine.dart:440`), convert `(cx, cy)` from `plane` space to `part` local space using `_plane2DToPartFaceLocal(activeSketchPlane!, part, Offset(cx, cy))`:

```dart
  void executeFeatureCutOnActiveSurface({bool isPassThrough = true, double depthMm = 5.0}) {
    if (activeSketchPlane == null) return;
    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(activeSketchPlane!);
    final validation = CADProfileValidator.validateProfile(segments);
    activeSketchValidation = validation;

    if (!validation.isValidClosedLoop || validation.orderedPathVertices.isEmpty) {
      notifyListeners();
      return;
    }

    _recordUndo();
    final part = doc.parts.where((p) => p.id == (activeSketchPlane!.targetPartId ?? sketchPartId)).firstOrNull ?? selectedPart;
    if (part == null) return;

    final path = validation.orderedPathVertices;
    double sumX = 0, sumY = 0;
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final pt in path) {
      sumX += pt.dx;
      sumY += pt.dy;
      if (pt.dx < minX) minX = pt.dx;
      if (pt.dx > maxX) maxX = pt.dx;
      if (pt.dy < minY) minY = pt.dy;
      if (pt.dy > maxY) maxY = pt.dy;
    }
    final count = path.length;
    final cxPlane = sumX / count;
    final cyPlane = sumY / count;
    final w = maxX - minX;
    final h = maxY - minY;

    // CRITICAL FIX: Convert from Sketch Plane (centroid origin) to Part Local (corner origin)!
    final partLocalCenter = _plane2DToPartFaceLocal(activeSketchPlane!, part, Offset(cxPlane, cyPlane));
    final featureId = selectedSketchEntity?.id != null ? 'cut_${selectedSketchEntity!.id}' : _generateId('feature_cut');

    final feat = AssemblySketchFeature(
      id: featureId,
      featureType: 'custom_cut',
      localCenter: partLocalCenter,
      widthMm: w > 0 ? w : 10.0,
      heightMm: h > 0 ? h : 10.0,
      targetFace: activeSketchPlane!.targetFaceId ?? 'web',
      isPassThrough: isPassThrough,
      isSurfaceImpress: !isPassThrough && depthMm == 0.0,
      cutDepthMm: depthMm,
      customPolygonPoints: path.map((p) => Offset(p.dx - cxPlane, p.dy - cyPlane)).toList(),
      planeId: activeSketchPlane!.id,
    );

    // Replace existing cut from the same sketch entity so editing Pos X / Pos Y moves the hole instead of leaving a ghost hole!
    part.sketches.removeWhere((s) => s.id == featureId);
    part.sketches.add(feat);
    part.invalidateMeshCache();
    syncComponentInstances(part.id);
    notifyListeners();
  }
```

### Fix 3: Support Multi-Profile Sketches in `CADProfileValidator.validateProfile`
**File:** `lib/sketch_draft_files/math_and_processing/cad_profile_validator.dart` (**lines 11–53**)

Currently, `CADProfileValidator.validateProfile` rejects any sketch that has more than one closed profile (or a projected reference edge) with `"DANGLING GEOMETRY DETECTED."`. Replace it with a multi-loop extractor that extracts **all** valid closed loops on the sketch plane:

```dart
class ValidationResult {
  final bool isValidClosedLoop;
  final String reportFeedback;
  final List<Offset> orderedPathVertices;
  final List<List<Offset>> allClosedLoops;

  ValidationResult({
    required this.isValidClosedLoop,
    required this.reportFeedback,
    this.orderedPathVertices = const [],
    this.allClosedLoops = const [],
  });
}

class CADProfileValidator {
  static const double vertexTolerance = 0.25; // 0.25 mm tolerance (fixed from 0.005m!)

  static ValidationResult validateProfile(List<CADLineSegment> segments) {
    // Ignore deleted, construction, and projected reference segments when extracting closed profiles
    final activeSegments = segments
        .where((s) => !s.isDeleted && !s.isConstruction && !s.isProjected)
        .toList();
    if (activeSegments.isEmpty) {
      return ValidationResult(isValidClosedLoop: false, reportFeedback: "Empty sketch profile.");
    }

    final List<CADLineSegment> unvisited = List.from(activeSegments);
    final List<List<Offset>> closedLoops = [];

    while (unvisited.isNotEmpty) {
      final first = unvisited.removeAt(0);
      final List<Offset> path = [first.start];
      Offset currentTip = first.end;
      bool moving = true;

      while (moving && unvisited.isNotEmpty) {
        moving = false;
        for (int i = 0; i < unvisited.length; i++) {
          final cand = unvisited[i];
          if ((cand.start - currentTip).distance <= vertexTolerance) {
            path.add(currentTip);
            currentTip = cand.end;
            unvisited.removeAt(i);
            moving = true;
            break;
          } else if ((cand.end - currentTip).distance <= vertexTolerance) {
            path.add(currentTip);
            currentTip = cand.start;
            unvisited.removeAt(i);
            moving = true;
            break;
          }
        }
        if ((currentTip - path.first).distance <= vertexTolerance && path.length >= 3) {
          break;
        }
      }

      if ((currentTip - path.first).distance <= vertexTolerance && path.length >= 3) {
        path.add(path.first);
        closedLoops.add(path);
      }
    }

    if (closedLoops.isEmpty) {
      return ValidationResult(
        isValidClosedLoop: false,
        reportFeedback: "OPEN LOOP ERROR: Loop is not watertight.",
      );
    }

    return ValidationResult(
      isValidClosedLoop: true,
      reportFeedback: "${closedLoops.length} Closed Profile(s) Ready",
      orderedPathVertices: closedLoops.last, // Most recently drawn or selected closed profile
      allClosedLoops: closedLoops,
    );
  }
}
```

### Fix 4: Fix the `100×` Millimeter Scaling Bug in `cad_corner_modifier.dart` & `cad_constraint_solvers.dart`
**Files:**
* `lib/sketch_draft_files/math_and_processing/cad_corner_modifier.dart` (**lines 14, 34, 65**)
* `lib/sketch_draft_files/math_and_processing/cad_constraint_solvers.dart` (**lines 14, 21**)

Remove the `/ 100.0` division and increase the vertex coincidence tolerance from `0.005` (5 microns) to `0.25` (0.25 mm):

```dart
// In lib/sketch_draft_files/math_and_processing/cad_corner_modifier.dart:
  static List<CADLineSegment> applyChamfer({required CADLineSegment segA, required CADLineSegment segB, required double offsetMm}) {
    final double offset = offsetMm; // Fixed: assembly_studio uses 1 unit = 1.0 mm (do not divide by 100!)
    ...
  }

  static List<CADLineSegment> applyFillet({required CADLineSegment segA, required CADLineSegment segB, required double radiusMm, int resCount = 12}) {
    final double rad = radiusMm; // Fixed: 1 unit = 1.0 mm
    ...
  }

  static Map<String, dynamic>? _vertex(CADLineSegment a, CADLineSegment b) {
    const double tol = 0.25; // 0.25 mm tolerance
    if ((a.start - b.start).distance < tol) return {'v': a.start, 'sA': true, 'sB': true};
    if ((a.start - b.end).distance < tol) return {'v': a.start, 'sA': true, 'sB': false};
    if ((a.end - b.start).distance < tol) return {'v': a.end, 'sA': false, 'sB': true};
    if ((a.end - b.end).distance < tol) return {'v': a.end, 'sA': false, 'sB': false};
    return null;
  }
```

### Fix 5: Convert `CADRectangleEntity` into Editable Line Segments When Applying Sketch Fillets or Chamfers
**File:** `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` (**lines 3805–3825**)

Currently, `applyChamferToSelectedCorner` and `applyFilletToSelectedCorner` mutate a temporary list from `compilePlaneSegments()` without replacing the `CADRectangleEntity` in `activeSketchPlane!.primitives`. Fix both methods so they convert the selected rectangle into its 4 `CADLineSegment` edges in `activeSketchPlane!.entities`, apply the corner fillet/chamfer to the meeting edges, and re-validate the loop:

```dart
  void _convertSelectedRectangleToSegmentsIfNeeded() {
    if (activeSketchPlane == null) return;
    final sel = selectedSketchEntity;
    if (sel is CADRectangleEntity || sel is CADCenterRectangleEntity) {
      activeSketchPlane!.primitives.remove(sel);
      final segs = sel!.toLineSegments().where((s) => !s.isConstruction).toList();
      activeSketchPlane!.entities.addAll(segs);
      selectedSketchEntity = null;
    }
  }

  void applyChamferToSelectedCorner(double offsetMm) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    _convertSelectedRectangleToSegmentsIfNeeded();
    final segs = activeSketchPlane!.entities.where((s) => !s.isDeleted && !s.isConstruction).toList();
    if (segs.length < 2) return;
    final newSegs = CADCornerModifier.applyChamfer(segA: segs[0], segB: segs[1], offsetMm: offsetMm);
    activeSketchPlane!.entities.addAll(newSegs);
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }

  void applyFilletToSelectedCorner(double radiusMm) {
    if (activeSketchPlane == null) return;
    _recordUndo();
    _convertSelectedRectangleToSegmentsIfNeeded();
    final segs = activeSketchPlane!.entities.where((s) => !s.isDeleted && !s.isConstruction).toList();
    if (segs.length < 2) return;
    final newSegs = CADCornerModifier.applyFillet(segA: segs[0], segB: segs[1], radiusMm: radiusMm);
    activeSketchPlane!.entities.addAll(newSegs);
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }
```

### Fix 6: Support `Blind Cut` vs. `Pass-Through` and All Part Faces in `AssemblyPart`
**File:** `lib/assembly_studio/models/assembly_part.dart` (**lines 1228–1305**, **1561–1775**, and **2277–2362**)

1. In `_buildWebHoles()` (`line 2281`), broaden the face filter so cuts on `boxTubeStile` (`_boxtube_front`), `flatBar` (`_bar_top`), `iBeam` (`_ibeam_web`), and `angle` (`_leg_v`) are included:
   ```dart
   final isWebLike = sk.targetFace == 'web' ||
       sk.targetFace.endsWith('_web') ||
       sk.targetFace.endsWith('_front') ||
       sk.targetFace.endsWith('_leg_v') ||
       sk.targetFace.endsWith('_bar_top') ||
       sk.targetFace.isEmpty;
   ```
2. For **`Blind Cut` (`sk.isPassThrough == false`)**:
   - Cut the outer face polygon (`polys`) and bore walls to depth `math.min(sk.cutDepthMm, T)`, and **only** subtract the hole from the inner face (`innerWebHoles` / `innerTopHoles` / `innerBottomHoles`) when `sk.isPassThrough || sk.cutDepthMm >= T`! If `sk.cutDepthMm < T`, cap the bottom of the blind pocket at depth `sk.cutDepthMm` with a circular/polygon floor cap!

## 3. Verification Checklist for the Coding Agent
- [ ] Run `flutter test test/modules/assembly_studio/parametric_surface_sketching_test.dart` after applying Fixes 1–6.
- [ ] Verify that drawing **1 circle** on any rail face renders **only 1 circle** on that face (zero ghost hole at `(0,0)` on the 1st click, and zero floating circle on the right datum plane on the 2nd click).
- [ ] Verify that editing `Pos X`, `Pos Y`, or `Radius` in `AssemblySketchParameterPanel` moves the 2D circle and updates any committed cut hole in place without leaving a stale hole behind.
- [ ] Verify that drawing multiple circles or rectangles on the same sketch plane keeps `isValidClosedLoop == true` so the `Extrude (E)` dialog remains active.
