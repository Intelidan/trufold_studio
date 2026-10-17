# TruFold Studio: Onshape Sketching UX Overhaul, 1-Click Inline Dimension Popover, Camera `'N'` Normal Alignment & Unified Extrude Guide

**Target Codebase:** `lib/assembly_studio/`, `lib/sheet_metal_studio/`, and `lib/sketch_draft_files/` (from your latest `lib and test.zip` upload)  
**Reference Screenshots & Docs:**
- **Current App (`image_31c8cd.jpg`):** Shows `Sketch 1` on a tilted rail face (`Camera 'N'` failed to orient flat to the face), a basic `Ø 64.0 mm` label at the circle center, and the intrusive right-side `CIRCLE PARAMETERS` modal (`Radius`, `Pos X`, `Pos Y`, `Pass-Through / Blind Cut / Impress`, `PUNCH PASS-THROUGH CUT`).
- **Onshape Sketch & CAD Dimensions (`image_31d02d.png`):** Shows `Sketch 2` oriented flat to the screen (`Normal To`), shaded closed profile, and authentic CAD engineering dimensions (`60`, `75`, `99`, `90`, `65`, `10`, `27°`, `Ø17`, `Ø33`, `R3`, `R10`) with witness/extension lines, leader lines, and crisp arrowheads.
- **Onshape Inline Floating Dimension Editor (`image_31d0a3.png`):** Clicking directly on the `60` dimension tag opens a compact floating popover right over the tag with an auto-focused `60 mm` input field, a `±` tolerance toggle button, a green check (`✓`), and a red cancel (`✕`).
- **Onshape Extrude Workflow (`image_31d127.png`):** Shows `Extrude 4` with `Solid | Surface | Thin` tabs, `New | Add | Remove | Intersect` boolean buttons, `Faces and sketch regions to extrude` (`Face of Sketch 2` highlighted in orange), `Blind` / `Through all` end-type dropdown, `Depth: 25 mm` with a Flip Direction (`⇄`) button, and a draggable 3D depth arrow manipulator.

---

## 1. Root-Cause Diagnosis of Every Issue You Reported

| Issue / Symptom | Exact File & Line Numbers in Your Uploaded Code | Root Cause in Code | Exact Fix in This Walkthrough |
| :--- | :--- | :--- | :--- |
| **1. Pressing `"N"` Does NOT Orient the Camera to Show the Front of the Sketching Face (`image_31c8cd.jpg`)** | `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**lines 369–377, 444–447, 513–516, 3271**) & `lib/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart` (**lines 68–75, 97, 246–251**) | **Four compounding bugs:**<br>**1) Scrambled Y/Z Axes in `_updateGpuCamera` (lines 445–446):** `CadPolygonTriangulator` builds the 3D GPU mesh in Z-Up coordinates `(x, y, z)`, where `_computeRotationMatrix(az, el)` has camera-to-eye `d = (m[8], m[9], m[10])` and `up = (m[4], m[5], m[6])`. However, `_updateGpuCamera` wrote `d = Vector3(-m[8], m[10], m[9])` and `up = Vector3(-m[4], m[6], m[5])`—swapping Y and Z! Thus, when sketching on the **Top Flange** (`normal = (0,0,1)`, `el = 90°`), the GPU camera moved to `+Y` `(0,1,0)` (looking at the **thin side edge** of the flange instead of the top face!). When sketching on the **Front Web** (`normal = (0,-1,0)`, `el = 0°`), the GPU camera moved to `-Z` `(0,0,-1)` (looking from **underneath**!).<br>**2) Stale Pivot in `_rebuildGpuCadModel` (lines 369–377):** Pressing `'N'` updates `_cameraPivot = cameraPivotOverride`, but `_rebuildGpuCadModel()` did not check `_cameraPivot != _lastCameraPivot`, leaving the 3D GPU mesh offset at the old `mesh.center` while the 2D sketch plane centered on `plane.origin`!<br>**3) Wrong `tentativeUp` in `createPlaneFromFacePolygon` (line 68):** Used `(0,1,0)` instead of Z-Up `(0,0,1)` for vertical walls, rotating the sketch grid 90° sideways.<br>**4) `onOrientNormal` Hardcoded `(0,0)` (line 3271):** Clicking the Normal button in the view bar called `_setCameraFromAngles(0, 0)` instead of `vm.alignCameraToActivePlaneNormal()`. | **1)** Fix `_updateGpuCamera` (`lines 445–447`) to use `d = Vector3(m[8], m[9], m[10])`, `up = Vector3(m[4], m[5], m[6])`, `right = Vector3(m[0], m[1], m[2])`.<br>**2)** Track `_lastCameraPivot` in `_rebuildGpuCadModel()` so changing `cameraPivotOverride` immediately re-centers the GPU mesh.<br>**3)** Prefer World `+Z (0,0,1)` as `tentativeUp` in `createPlaneFromFacePolygon`, and make `alignCameraToActivePlaneNormal()` work both in Sketch Mode AND whenever any 3D face (`doc.selectedFaceId`) is selected! |
| **2. Clunky Right-Side `CIRCLE PARAMETERS` Modal Instead of Onshape Clickable Dimension Tags (`image_31c8cd.jpg` vs `image_31d0a3.png`)** | `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**lines 3337–3348**) & `lib/assembly_studio/views/widgets/viewport/overlays/assembly_sketch_parameter_panel.dart` (**lines 88–341**) | Selecting any sketch entity opens a 290px white `CIRCLE PARAMETERS` modal (`Pos X`, `Pos Y`, `Radius`, `Pass-Through / Blind Cut / Impress`, `PUNCH PASS-THROUGH CUT`), mixing 2D sketching with 3D boolean hole punching, and requiring manual coordinate typing instead of clicking a dimension tag on the sketch. | Replace `AssemblySketchParameterPanel` with **`OnshapeDimensionEditPopover`** (`image_31d0a3.png`): clicking any dimension tag on the sketch opens a compact floating popover right over that tag with pre-selected `60 mm` input, `±` tolerance button, green `✓` (`Enter`), and red `✕` (`Esc`). |
| **3. Missing Onshape CAD Dimension Lines, Witness Lines, Arrowheads & 2-Entity Distance/Angle Dimensions (`image_31d02d.png`)** | `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart` (**lines 312–324, 597–615**) & `assembly_3d_viewport.dart` (**lines 1784–1824**) | **1)** `Assembly3DSurfaceSketchPainter` only drew a text pill at the circle center (`Ø 64.0 mm`) and drew tiny square symbols (`↔`, `∠`, `R`, `Ø`) for `plane.constraints` instead of CAD extension lines, arrowheads, leader lines, and angular arcs.<br>**2)** The `dimension` (`D`) tool only accepted 1 click on a single entity—it could not dimension **between two entities** (e.g. distance between a circle center and a line `65`, distance between two parallel lines `10`, or angle between two lines `27°`). | **1)** Upgrade `Assembly3DSurfaceSketchPainter` to draw full **ISO/ASME & Onshape CAD Dimensions** (extension witness lines, filled arrowheads, radial/diametric leaders, and angular arcs) and record each tag's screen `Rect` for 1-click editing.<br>**2)** Upgrade the `D` tool to support **1-Click Single Entity** AND **2-Click Entity-to-Entity** (Linear Distance & Angle `27°`) + drag-to-offset placement! |
| **4. Cannot Drag Sketch Entities, Endpoints, Circle Radii, or Dimension Offsets on the Sketch Plane** | `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (**lines 1825–1900 & 2148–2277**) | `onPointerDown` selected `hitPrimitive`, but `onPointerMove` had **zero drag handler** for `CADPrimitiveEntity`! You could not drag a circle center, drag a circle rim to change its radius, drag a line endpoint, or drag a dimension tag outward. | Add `_draggingSketchPrimitive`, `_draggingSketchHandleIndex`, and `_draggingDimensionConstraintId` handlers in `onPointerDown`, `onPointerMove`, and `onPointerUp` with real-time constraint solving at 60 FPS! |
| **5. `Extrude` Dialog Missing `Solid / Surface / Thin`, `End Type` Dropdown (`Blind` / `Through All`), Flip Direction (`⇄`), and Orange Region Highlight (`image_31d127.png`)** | `lib/assembly_studio/views/widgets/viewport/overlays/assembly_extrude_dialog.dart` (**lines 88–504**) | `AssemblyExtrudeDialog` lacked the `Solid | Surface | Thin` mode tabs, the `End type` (`Blind` / `Through all` / `Up to face`) dropdown, the Flip Direction (`⇄`) button next to `Depth`, and the `Faces and sketch regions to extrude` selection box shown in `image_31d127.png`. | Upgrade `AssemblyExtrudeDialog` and `AssemblyExtrudeParams` to match Onshape's `Extrude` inspector (`image_31d127.png`). |

---

## 2. Step 1: Fix Camera `"N"` ("View Normal to Sketch Plane") Orientation Across GPU & Canvas

### 1.1 Fix `createPlaneFromFacePolygon` & `createDatumPlane` in `lib/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart`
In `lib/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart` (**lines 67–126**), make `createPlaneFromFacePolygon` use World **Z-Up `(0, 0, 1)`** for vertical/angled walls and World **`+Y (0, 1, 0)`** for horizontal top/bottom faces, and orient `XZ Front Plane` with `normal = Vector3(0.0, -1.0, 0.0)` (facing the front camera at `-Y`):

```dart
// REPLACE lines 67-126 in lib/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart with:
    // Compute robust up vector tangent to face in Z-Up CAD coordinates:
    // - For vertical or angled faces (|normal.z| <= 0.90), World +Z (0, 0, 1) is screen-up.
    // - For horizontal top/bottom faces (|normal.z| > 0.90), World +Y (0, 1, 0) is screen-up.
    vm.Vector3 tentativeUp = vm.Vector3(0.0, 0.0, 1.0);
    if (normal.dot(tentativeUp).abs() > 0.90) {
      tentativeUp = vm.Vector3(0.0, 1.0, 0.0);
    }
    final up = (tentativeUp - normal * normal.dot(tentativeUp)).normalized();

    return CADSketchPlane(
      id: 'plane_${polygon.faceId}',
      origin: origin,
      normal: normal,
      up: up,
      targetPartId: partId,
      targetFaceId: polygon.faceId,
    );
  }

  /// Constructs a standard datum sketch plane (XY, XZ, or YZ).
  static CADSketchPlane createDatumPlane(String type, {vm.Vector3? customOrigin, double size = 140.0}) {
    final ori = customOrigin ?? vm.Vector3(0.0, 0.0, 0.0);
    switch (type.toUpperCase()) {
      case 'XZ':
        return CADSketchPlane(
          id: 'datum_XZ',
          name: 'XZ Front Plane',
          planeType: CADPlaneType.datumXZ,
          origin: ori,
          normal: vm.Vector3(0.0, -1.0, 0.0), // Faces the front camera (-Y)
          up: vm.Vector3(0.0, 0.0, 1.0),     // +Z is up on screen
          size: size,
          customColor: const Color(0xFF10B981),
        );
      case 'YZ':
        return CADSketchPlane(
          id: 'datum_YZ',
          name: 'YZ Right Plane',
          planeType: CADPlaneType.datumYZ,
          origin: ori,
          normal: vm.Vector3(1.0, 0.0, 0.0),  // Faces the right camera (+X)
          up: vm.Vector3(0.0, 0.0, 1.0),     // +Z is up on screen
          size: size,
          customColor: const Color(0xFFF59E0B),
        );
      case 'XY':
      default:
        return CADSketchPlane(
          id: 'datum_XY',
          name: 'XY Top Plane',
          planeType: CADPlaneType.datumXY,
          origin: ori,
          normal: vm.Vector3(0.0, 0.0, 1.0),  // Faces the top camera (+Z)
          up: vm.Vector3(0.0, 1.0, 0.0),     // +Y is up on screen
          size: size,
          customColor: const Color(0xFF0EA5E9),
        );
    }
  }
```

### 1.2 Fix `_updateGpuCamera`, `_rebuildGpuCadModel` Pivot Tracking & `onOrientNormal` in `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart`

1. **Add `CadPoint3D? _lastCameraPivot;` to `Assembly3DViewportState` (around line 85) and include it in `_rebuildGpuCadModel`'s dirty check (`lines 369–387`):**
```dart
// In lib/assembly_studio/views/widgets/assembly_3d_viewport.dart (around line 369):
    if (!force &&
        _cadModelNode != null &&
        docVersion == _lastDocVersion &&
        mesh.polygons.length == _lastMeshPolyCount &&
        targetSelectedFaceId == _lastSelectedFaceId &&
        targetSelectedWeldId == _lastSelectedWeldId &&
        targetRenderMode == _lastRenderMode &&
        targetPreset == _lastPreset &&
        targetWireframe == _lastShowWireframe &&
        currentPrefs == _lastGraphicsPreferences &&
        _cameraPivot == _lastCameraPivot) {
      return;
    }

    _lastDocVersion = docVersion;
    _lastMeshPolyCount = mesh.polygons.length;
    _lastSelectedFaceId = targetSelectedFaceId;
    _lastSelectedWeldId = targetSelectedWeldId;
    _lastRenderMode = targetRenderMode;
    _lastPreset = targetPreset;
    _lastShowWireframe = targetWireframe;
    _lastGraphicsPreferences = currentPrefs;
    _lastCameraPivot = _cameraPivot;
```

2. **Fix `_updateGpuCamera` (`lines 444–448` in `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart`) so it uses the exact Z-Up rotation matrix vectors `(m[8], m[9], m[10])` and `(m[4], m[5], m[6])` instead of the scrambled `(-m[8], m[10], m[9])`:**
```dart
// REPLACE lines 444-448 in lib/assembly_studio/views/widgets/assembly_3d_viewport.dart with:
    final m = _computeRotationMatrix(_azimuthDeg, _elevationDeg);
    // CRITICAL FIX: The 3D GPU mesh in FlutterSceneCadMeshBuilder is built in Z-Up world coordinates
    // (x - pivot.x, y - pivot.y, z - pivot.z), identical to _projectPointPaint!
    // Using (m[8], m[9], m[10]) for eye-direction `d` and (m[4], m[5], m[6]) for `up`
    // ensures pressing 'N' (or Top/Front/Right views) orients the camera directly perpendicular
    // to the front of the sketching face!
    final right = vm_math.Vector3(m[0], m[1], m[2]).normalized();
    final up = vm_math.Vector3(m[4], m[5], m[6]).normalized();
    final d = vm_math.Vector3(m[8], m[9], m[10]).normalized();
```

3. **Allow `_elevationDeg` up to `±90.0°` in `_setCameraFromAngles` (`line 568`) and wire `onOrientNormal` (`line 3271`) to `vm.alignCameraToActivePlaneNormal()`:**
```dart
// In lib/assembly_studio/views/widgets/assembly_3d_viewport.dart (line 566-573):
  void _setCameraFromAngles(double az, double el) {
    _azimuthDeg = az % 360.0;
    _elevationDeg = el.clamp(-90.0, 90.0);
    widget.viewModel.azimuthDeg = _azimuthDeg;
    widget.viewModel.elevationDeg = _elevationDeg;
    _updateGpuCamera();
    _cameraRepaintNotifier.value++;
  }

// And at line 3271 in lib/assembly_studio/views/widgets/assembly_3d_viewport.dart:
                        onOrientNormal: () {
                          vm.alignCameraToActivePlaneNormal();
                        },
```

4. **Update `alignCameraToActivePlaneNormal()` in `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` (`lines 3448–3460`) so pressing `'N'` works BOTH inside Sketch Mode AND whenever any 3D face or datum plane is selected:**
```dart
// REPLACE lines 3448-3460 in lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart with:
  /// Aligns camera view directly perpendicular (normal view) facing the active sketch plane
  /// (or the currently selected 3D face / datum plane if not yet in Sketch Mode) and centers on its origin.
  void alignCameraToActivePlaneNormal() {
    vm_math.Vector3? targetNormal;
    CadPoint3D? targetOrigin;

    if (activeSketchPlane != null) {
      targetNormal = activeSketchPlane!.normal;
      targetOrigin = CadPoint3D(
        activeSketchPlane!.origin.x,
        activeSketchPlane!.origin.y,
        activeSketchPlane!.origin.z,
      );
    } else if (doc.selectedFaceId != null) {
      final cleanId = doc.selectedFaceId!.replaceFirst('plane_', '');
      final poly = assemblyMesh.allPolygons
          .where((p) => p.faceId == cleanId || p.faceId.startsWith(cleanId))
          .firstOrNull;
      if (poly != null && poly.vertices.isNotEmpty) {
        targetNormal = vm_math.Vector3(poly.normal.x, poly.normal.y, poly.normal.z);
        double cx = 0, cy = 0, cz = 0;
        for (final v in poly.vertices) {
          cx += v.x;
          cy += v.y;
          cz += v.z;
        }
        final n = poly.vertices.length;
        targetOrigin = CadPoint3D(cx / n, cy / n, cz / n);
      }
    }

    if (targetNormal == null || targetOrigin == null) return;

    pan = Offset.zero;
    cameraPivotOverride = targetOrigin;
    final angles = AssemblySurfaceSketchEngine.computeNormalViewCameraAngles(targetNormal);
    azimuthDeg = angles.azimuthDeg;
    elevationDeg = angles.elevationDeg;
    if (isSketchMode && !isOrthoProjection) {
      _previousOrthoBeforeSketch = isOrthoProjection;
      isOrthoProjection = true;
    } else {
      isOrthoProjection = true;
    }
    final maxDim = selectedPart != null ? math.max(selectedPart!.length, selectedPart!.height) : 400.0;
    zoom = (850.0 / (maxDim > 0 ? maxDim : 800.0)).clamp(0.65, 2.5);
    notifyListeners();
  }
```

---

## 3. Step 2: Upgrade `CadConstraint` & `AssemblySketchConstraintSolver` for Full Onshape Dimensions (`60`, `27°`, `Ø17`, `R10`, `±` Tolerance & Expressions)

### 2.1 Add Offset, Tolerance & Expression Fields to `lib/sheet_metal_studio/models/cad_constraint.dart`
Replace `CadConstraint` in `lib/sheet_metal_studio/models/cad_constraint.dart` (**lines 133–196**) so every dimension constraint can store its user-dragged witness-line offset (`labelOffset`), mathematical expression (`expression`, e.g. `"60/2"`), and bilateral tolerance (`tolerancePlus`, `toleranceMinus` for the `±` button in `image_31d0a3.png`):

```dart
// REPLACE lines 133-196 in lib/sheet_metal_studio/models/cad_constraint.dart with:
class CadConstraint {
  final String id;
  final CadConstraintType type;
  final List<String> entityIds; // IDs of geometry or feature entities involved
  final double? parameterValue; // Target value for dimensional constraints (mm or deg)
  final String? parameterId;    // Linked CadParameter ID if driven by user parameter
  final String? expression;     // Optional formula expression (e.g. "60/2" or "25+10")
  final double labelOffset;     // Witness-line offset distance in plane mm (default 18.0)
  final double? tolerancePlus;  // Optional +tolerance (mm or deg) from Onshape '±' popover
  final double? toleranceMinus; // Optional -tolerance (mm or deg)
  final bool isActive;

  const CadConstraint({
    required this.id,
    required this.type,
    required this.entityIds,
    this.parameterValue,
    this.parameterId,
    this.expression,
    this.labelOffset = 18.0,
    this.tolerancePlus,
    this.toleranceMinus,
    this.isActive = true,
  });

  String get symbol => type.symbol;
  String get label => type.label;

  bool get isDimensional =>
      type == CadConstraintType.distance ||
      type == CadConstraintType.angle ||
      type == CadConstraintType.radius ||
      type == CadConstraintType.diameter;

  CadConstraint copyWith({
    String? id,
    CadConstraintType? type,
    List<String>? entityIds,
    double? parameterValue,
    String? parameterId,
    String? expression,
    double? labelOffset,
    double? tolerancePlus,
    double? toleranceMinus,
    bool? isActive,
  }) {
    return CadConstraint(
      id: id ?? this.id,
      type: type ?? this.type,
      entityIds: entityIds ?? this.entityIds,
      parameterValue: parameterValue ?? this.parameterValue,
      parameterId: parameterId ?? this.parameterId,
      expression: expression ?? this.expression,
      labelOffset: labelOffset ?? this.labelOffset,
      tolerancePlus: tolerancePlus ?? this.tolerancePlus,
      toleranceMinus: toleranceMinus ?? this.toleranceMinus,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'entityIds': entityIds,
        if (parameterValue != null) 'parameterValue': parameterValue,
        if (parameterId != null) 'parameterId': parameterId,
        if (expression != null) 'expression': expression,
        'labelOffset': labelOffset,
        if (tolerancePlus != null) 'tolerancePlus': tolerancePlus,
        if (toleranceMinus != null) 'toleranceMinus': toleranceMinus,
        'isActive': isActive,
      };

  factory CadConstraint.fromJson(Map<String, dynamic> json) => CadConstraint(
        id: json['id'] as String,
        type: CadConstraintType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CadConstraintType.horizontal,
        ),
        entityIds: (json['entityIds'] as List<dynamic>).map((e) => e as String).toList(),
        parameterValue: (json['parameterValue'] as num?)?.toDouble(),
        parameterId: json['parameterId'] as String?,
        expression: json['expression'] as String?,
        labelOffset: (json['labelOffset'] as num?)?.toDouble() ?? 18.0,
        tolerancePlus: (json['tolerancePlus'] as num?)?.toDouble(),
        toleranceMinus: (json['toleranceMinus'] as num?)?.toDouble(),
        isActive: json['isActive'] as bool? ?? true,
      );
}
```

### 2.2 Upgrade `_applySingleConstraint` & `_solveDimensional` in `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart`
In `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart`:
1. Add `case CadConstraintType.angle:` to `_applySingleConstraint` (**line 210**):
```dart
      case CadConstraintType.distance:
      case CadConstraintType.radius:
      case CadConstraintType.diameter:
      case CadConstraintType.angle:
        return _solveDimensional(c, entityMap);
```
2. Replace `_solveDimensional` (**lines 484–518**) so it solves:
   - **Single-entity dimensions:** Line length, Circle/Slot diameter (`Ø`), Circle/Arc/Polygon radius (`R`), Rectangle/CenterRectangle width & height (`id:w` / `id:h`).
   - **2-entity linear distances (`CadConstraintType.distance` with 2 `entityIds`):** Point/Circle-to-Point/Circle distance, Point/Circle-to-Line perpendicular distance (`65` in `image_31d02d.png`), and parallel Line-to-Line distance (`10` in `image_31d02d.png`).
   - **2-line angular dimensions (`CadConstraintType.angle` with 2 `entityIds`):** Rotates line 2 relative to line 1 around their intersection point to enforce the exact angle in degrees (`27°` in `image_31d02d.png`)!

```dart
// REPLACE lines 484-518 in lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart with:
  static bool _solveDimensional(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    final val = c.parameterValue;
    if (val == null || val <= 0) return false;
    if (c.entityIds.isEmpty) return false;

    final rawId0 = c.entityIds[0];
    final baseId0 = rawId0.split(':').first;
    final subKey0 = rawId0.contains(':') ? rawId0.split(':').last : '';
    final ent = entityMap[baseId0];
    if (ent == null) return false;

    // 1. ANGULAR DIMENSION BETWEEN 2 LINES (e.g. 27° in image_31d02d.png)
    if (c.type == CadConstraintType.angle && c.entityIds.length >= 2) {
      final ent2 = entityMap[c.entityIds[1].split(':').first];
      if (ent is CADLineEntity && ent2 is CADLineEntity) {
        final d1 = ent.end - ent.start;
        final d2 = ent2.end - ent2.start;
        final len1 = d1.distance;
        final len2 = d2.distance;
        if (len1 < 1e-4 || len2 < 1e-4) return false;

        final a1 = math.atan2(d1.dy, d1.dx);
        final a2 = math.atan2(d2.dy, d2.dx);
        double diff = a2 - a1;
        while (diff <= -math.pi) diff += 2.0 * math.pi;
        while (diff > math.pi) diff -= 2.0 * math.pi;
        final sign = diff >= 0 ? 1.0 : -1.0;
        final targetA2 = a1 + sign * (val * math.pi / 180.0);

        // Pivot around shared endpoint if coincident, otherwise ent2.start
        Offset pivot = ent2.start;
        bool pivotIsStart = true;
        if ((ent2.end - ent.start).distance < 1.0 || (ent2.end - ent.end).distance < 1.0) {
          pivot = ent2.end;
          pivotIsStart = false;
        }
        final dir2 = Offset(math.cos(targetA2), math.sin(targetA2));
        if (pivotIsStart) {
          ent2.end = pivot + dir2 * len2;
        } else {
          ent2.start = pivot - dir2 * len2;
        }
        return true;
      }
      return false;
    }

    // 2. TWO-ENTITY LINEAR DISTANCE (Point/Circle-to-Line, Line-to-Line, Center-to-Center)
    if (c.type == CadConstraintType.distance && c.entityIds.length >= 2) {
      final ent2 = entityMap[c.entityIds[1].split(':').first];
      if (ent2 == null) return false;

      // Case 2A: Line-to-Entity perpendicular distance (e.g. circle center to bottom line = 65mm)
      if (ent is CADLineEntity && ent2 is! CADLineEntity) {
        final lVec = ent.end - ent.start;
        final lLen = lVec.distance;
        if (lLen < 1e-4) return false;
        final unitN = Offset(-lVec.dy / lLen, lVec.dx / lLen);
        final p2 = _getEntityCenterOrAnchor(ent2);
        final signedDist = (p2.dx - ent.start.dx) * unitN.dx + (p2.dy - ent.start.dy) * unitN.dy;
        final sign = signedDist >= 0 ? 1.0 : -1.0;
        final delta = unitN * (sign * val - signedDist);
        _shiftEntityTo(ent2, p2 + delta);
        return true;
      } else if (ent2 is CADLineEntity && ent is! CADLineEntity) {
        final lVec = ent2.end - ent2.start;
        final lLen = lVec.distance;
        if (lLen < 1e-4) return false;
        final unitN = Offset(-lVec.dy / lLen, lVec.dx / lLen);
        final p1 = _getEntityCenterOrAnchor(ent);
        final signedDist = (p1.dx - ent2.start.dx) * unitN.dx + (p1.dy - ent2.start.dy) * unitN.dy;
        final sign = signedDist >= 0 ? 1.0 : -1.0;
        final delta = unitN * (sign * val - signedDist);
        _shiftEntityTo(ent, p1 + delta);
        return true;
      } else if (ent is CADLineEntity && ent2 is CADLineEntity) {
        // Parallel line-to-line distance (e.g. 10mm offset wall in image_31d02d.png)
        final lVec = ent.end - ent.start;
        final lLen = lVec.distance;
        if (lLen < 1e-4) return false;
        final unitN = Offset(-lVec.dy / lLen, lVec.dx / lLen);
        final mid2 = (ent2.start + ent2.end) * 0.5;
        final signedDist = (mid2.dx - ent.start.dx) * unitN.dx + (mid2.dy - ent.start.dy) * unitN.dy;
        final sign = signedDist >= 0 ? 1.0 : -1.0;
        final shift = unitN * (sign * val - signedDist);
        ent2.start = ent2.start + shift;
        ent2.end = ent2.end + shift;
        return true;
      } else {
        // Center-to-center / point-to-point distance
        final p1 = _getEntityCenterOrAnchor(ent);
        final p2 = _getEntityCenterOrAnchor(ent2);
        final d = p2 - p1;
        final len = d.distance;
        final dir = len > 1e-4 ? d / len : const Offset(1.0, 0.0);
        _shiftEntityTo(ent2, p1 + dir * val);
        return true;
      }
    }

    // 3. SINGLE-ENTITY DIMENSIONS (Radius, Diameter, Length, Width/Height)
    if (c.type == CadConstraintType.radius) {
      if (ent is CADCircleEntity) {
        ent.radius = val;
        return true;
      } else if (ent is CADCenterPointArcEntity) {
        ent.radius = val;
        return true;
      } else if (ent is CADRegularPolygonEntity) {
        ent.radius = val;
        return true;
      } else if (ent is CADArcEntity) {
        final chordVec = ent.endPoint - ent.startPoint;
        final chordLen = chordVec.distance;
        if (chordLen > 1e-4) {
          final clampedR = math.max(val, chordLen / 2.0);
          final mid = (ent.startPoint + ent.endPoint) * 0.5;
          final perp = Offset(-chordVec.dy / chordLen, chordVec.dx / chordLen);
          final currentSide = (ent.pointOnArc.dx - mid.dx) * perp.dx + (ent.pointOnArc.dy - mid.dy) * perp.dy;
          final sign = currentSide >= 0 ? 1.0 : -1.0;
          final hDist = math.sqrt(math.max(0.0, clampedR * clampedR - (chordLen / 2.0) * (chordLen / 2.0)));
          final sagitta = clampedR - hDist;
          ent.pointOnArc = mid + perp * (sign * (sagitta > 1e-4 ? sagitta : clampedR));
        }
        return true;
      }
    } else if (c.type == CadConstraintType.diameter) {
      if (ent is CADCircleEntity) {
        ent.radius = val / 2.0;
        return true;
      } else if (ent is CADSlotEntity) {
        ent.diameter = val;
        return true;
      }
    } else if (c.type == CadConstraintType.distance) {
      if (ent is CADLineEntity) {
        final d = ent.end - ent.start;
        final currLen = d.distance;
        if (currLen > 1e-4) {
          final unit = d / currLen;
          // Anchor start point if it is near origin or connected, otherwise scale symmetrically
          final mid = (ent.start + ent.end) * 0.5;
          ent.start = mid - unit * (val / 2.0);
          ent.end = mid + unit * (val / 2.0);
          return true;
        }
      } else if (ent is CADRectangleEntity) {
        if (subKey0 == 'h') {
          ent.height = val;
        } else {
          ent.width = val;
        }
        return true;
      } else if (ent is CADCenterRectangleEntity) {
        if (subKey0 == 'h') {
          ent.height = val;
        } else {
          ent.width = val;
        }
        return true;
      } else if (ent is CADSlotEntity) {
        final d = ent.endCenter - ent.startCenter;
        final len = d.distance;
        final unit = len > 1e-4 ? d / len : const Offset(1.0, 0.0);
        final mid = (ent.startCenter + ent.endCenter) * 0.5;
        ent.startCenter = mid - unit * (val / 2.0);
        ent.endCenter = mid + unit * (val / 2.0);
        return true;
      }
    }
    return false;
  }
```

---

## 4. Step 3: Render Authentic Onshape CAD Dimension Annotations & Hit-Testable Tags in `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart`

### What This Replaces
Instead of drawing a plain text pill inside the circle (`Ø 64.0 mm` in `image_31c8cd.jpg`), `Assembly3DSurfaceSketchPainter` now:
1. Draws **true Onshape CAD Dimension Annotations** (`image_31d02d.png`):
   - **Linear Dimensions (`60`, `75`, `99`, `90`, `65`, `10`):** Two witness/extension lines with a `3px` surface gap and `5px` extension past the dimension line, a dimension line with two filled CAD arrowheads (`◀─── 60 ───▶`), and a clickable dimension tag centered in the line break.
   - **Diameter (`Ø17`, `Ø33`) & Radius (`R3`, `R10`) Dimensions:** Leader line at `35°` from the circle/arc perimeter with a filled arrowhead touching the curve, a horizontal shoulder, and the clickable `Ø 64` or `R 10` tag.
   - **Angular Dimensions (`27°`):** Curved dimension arc between two non-parallel lines with filled arrowheads at both ends of the arc and the clickable `27°` tag at the midpoint of the arc.
2. Populates `viewModel.sketchDimensionHitRects` on every frame so clicking **any** dimension tag on the canvas (whether a driving `CadConstraint` dimension OR a default entity dimension!) immediately opens the floating **`OnshapeDimensionEditPopover`** right at that tag's screen coordinates (`image_31d0a3.png`)!

Replace `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart` with this complete, drop-in implementation:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Describes a clickable Onshape dimension tag rendered on the 2D/3D sketch canvas.
class SketchDimensionTagHit {
  final String tagKey;
  final Rect screenRect;
  final String primaryEntityId;
  final String? secondaryEntityId;
  final CadConstraintType constraintType;
  final String? existingConstraintId;
  final double currentValue;
  final String unitSuffix; // 'mm' or 'deg'
  final String? subKey;    // 'w' or 'h' for rectangles

  const SketchDimensionTagHit({
    required this.tagKey,
    required this.screenRect,
    required this.primaryEntityId,
    this.secondaryEntityId,
    required this.constraintType,
    this.existingConstraintId,
    required this.currentValue,
    this.unitSuffix = 'mm',
    this.subKey,
  });
}

/// Renders real-time 3D parametric sketch geometry and Onshape CAD Engineering Dimensions
/// (witness/extension lines, filled arrowheads, radial/diametric leaders, angular arcs,
/// and clickable inline dimension tags matching image_31d02d.png and image_31d0a3.png).
class Assembly3DSurfaceSketchPainter extends CustomPainter {
  final AssemblyStudioViewModel viewModel;
  final Offset Function(CadPoint3D) projectPoint;

  Assembly3DSurfaceSketchPainter({required this.viewModel, required this.projectPoint});

  @override
  void paint(Canvas canvas, Size size) {
    final plane = viewModel.activeSketchPlane;
    if (plane == null) return;

    viewModel.sketchDimensionHitRects.clear();

    final xAx = plane.xAxis;
    final yAx = plane.yAxis;
    final origin = plane.origin;

    Offset toScreen(Offset local) {
      final w = origin + (xAx * local.dx) + (yAx * local.dy);
      return projectPoint(CadPoint3D(w.x, w.y, w.z));
    }

    // 1. Procedural Plane Design Grid Overlay
    if (viewModel.showSketchGrid) {
      final gridPaint = Paint()
        ..color = const Color(0x260284C7)
        ..strokeWidth = 0.8;

      const double extent = 200.0;
      const double step = 20.0;
      final int lineCount = (extent / step).round();

      for (int i = -lineCount; i <= lineCount; i++) {
        final val = i * step;
        final s1 = toScreen(Offset(val, -extent));
        final e1 = toScreen(Offset(val, extent));
        if (s1 != Offset.zero && e1 != Offset.zero) {
          canvas.drawLine(s1, e1, gridPaint);
        }
        final s2 = toScreen(Offset(-extent, val));
        final e2 = toScreen(Offset(extent, val));
        if (s2 != Offset.zero && e2 != Offset.zero) {
          canvas.drawLine(s2, e2, gridPaint);
        }
      }
    }

    // Sketch Origin Crosshair & Axes (Onshape dark crosshair + subtle R/G axes)
    final scrOrigin = toScreen(Offset.zero);
    final scrXAxis = toScreen(const Offset(30.0, 0.0));
    final scrYAxis = toScreen(const Offset(0.0, 30.0));
    if (scrOrigin != Offset.zero) {
      if (scrXAxis != Offset.zero) {
        canvas.drawLine(scrOrigin, scrXAxis, Paint()..color = const Color(0x99EF4444)..strokeWidth = 1.6);
      }
      if (scrYAxis != Offset.zero) {
        canvas.drawLine(scrOrigin, scrYAxis, Paint()..color = const Color(0x9910B981)..strokeWidth = 1.6);
      }
      canvas.drawCircle(
        scrOrigin,
        4.0,
        Paint()
          ..color = const Color(0xFF334155)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // 2. Interior Shaded Closed Profiles (Onshape translucent steel-blue region fill + orange highlight when Extrude is active)
    final validation = viewModel.activeSketchValidation;
    if (viewModel.showSketchProfileShading && validation != null && validation.isValidClosedLoop) {
      final loopsToFill = validation.allClosedLoops.isNotEmpty
          ? validation.allClosedLoops
          : (validation.orderedPathVertices.length >= 3 ? [validation.orderedPathVertices] : <List<Offset>>[]);

      final isExtrudeHighlight = viewModel.isExtrudeMode;
      final fillPaint = Paint()
        ..color = isExtrudeHighlight ? const Color(0x45F59E0B) : const Color(0x320284C7)
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
          if (isExtrudeHighlight) {
            canvas.drawPath(
              fillPath,
              Paint()
                ..color = const Color(0xFFF59E0B)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4,
            );
          }
        }
      }
    }

    // Track which entities already have an explicit driving dimensional constraint
    final entitiesWithDrivingDim = <String>{};
    for (final c in plane.constraints) {
      if (c.isActive && c.isDimensional) {
        for (final eid in c.entityIds) {
          entitiesWithDrivingDim.add(eid);
        }
      }
    }

    // 3. Render Primitive Entities & Onshape CAD Dimensions
    for (final prim in plane.primitives) {
      final isSel = (prim.id == viewModel.selectedSketchEntity?.id) ||
          viewModel.selectedSketchEntityIds.contains(prim.id);
      final isConstrained = prim.isFullyConstrained;
      final isOverConstrained = viewModel.lastConstraintSolverResult?.conflictingConstraints
              .any((c) => c.entityIds.contains(prim.id)) ??
          false;

      final strokePaint = Paint()
        ..color = isOverConstrained
            ? const Color(0xFFEF4444) // Onshape Red for conflicting geometry
            : isSel
                ? const Color(0xFFF59E0B) // Onshape Amber/Orange for selected geometry
                : prim.isProjected
                    ? const Color(0xFFC084FC) // Purple for projected 3D geometry
                    : prim.isConstruction
                        ? const Color(0xFF475569) // Slate dashed for construction geometry
                        : isConstrained
                            ? const Color(0xFF0F172A) // Onshape Black for fully defined geometry
                            : const Color(0xFF0284C7) // Onshape Blue for under-defined geometry
        ..strokeWidth = isSel ? 2.6 : (prim.isConstruction ? 1.4 : 2.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final haloPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = strokePaint.strokeWidth + 2.0
        ..style = PaintingStyle.stroke;

      if (prim is CADRectangleEntity) {
        final p1Local = prim.startPoint;
        final p2Local = Offset(prim.startPoint.dx + prim.width, prim.startPoint.dy);
        final p3Local = Offset(prim.startPoint.dx + prim.width, prim.startPoint.dy + prim.height);
        final p4Local = Offset(prim.startPoint.dx, prim.startPoint.dy + prim.height);

        final p1 = toScreen(p1Local);
        final p2 = toScreen(p2Local);
        final p3 = toScreen(p3Local);
        final p4 = toScreen(p4Local);

        if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
          final rectPath = Path()
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..lineTo(p4.dx, p4.dy)
            ..close();

          canvas.drawPath(rectPath, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, rectPath, strokePaint);
          } else {
            canvas.drawPath(rectPath, strokePaint);
          }

          _drawVertexDot(canvas, p1, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p2, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p3, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p4, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p1,
              pB: p2,
              offsetPx: -26.0,
              label: _formatDimValue(prim.width),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: '${prim.id}:w',
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: prim.width,
                subKey: 'w',
              ),
            );
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p2,
              pB: p3,
              offsetPx: 28.0,
              label: _formatDimValue(prim.height),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: '${prim.id}:h',
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: prim.height,
                subKey: 'h',
              ),
            );
          }
        }
      } else if (prim is CADCenterRectangleEntity) {
        final p1 = toScreen(prim.topLeft);
        final p2 = toScreen(prim.topRight);
        final p3 = toScreen(prim.bottomRight);
        final p4 = toScreen(prim.bottomLeft);
        final cScr = toScreen(prim.center);

        if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
          final rectPath = Path()
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..lineTo(p4.dx, p4.dy)
            ..close();

          canvas.drawPath(rectPath, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, rectPath, strokePaint);
          } else {
            canvas.drawPath(rectPath, strokePaint);
          }

          if (prim.hasDiagonalConstruction || isSel) {
            final diagPaint = Paint()
              ..color = const Color(0xFF64748B).withValues(alpha: 0.65)
              ..strokeWidth = 1.1;
            _drawDashedLine(canvas, p1, p3, diagPaint);
            _drawDashedLine(canvas, p4, p2, diagPaint);
          }

          _drawVertexDot(canvas, cScr, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p1, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p2, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p3, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, p4, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p1,
              pB: p2,
              offsetPx: -26.0,
              label: _formatDimValue(prim.width),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: '${prim.id}:w',
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: prim.width,
                subKey: 'w',
              ),
            );
            _drawLinearCadDimension(
              canvas: canvas,
              pA: p2,
              pB: p3,
              offsetPx: 28.0,
              label: _formatDimValue(prim.height),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: '${prim.id}:h',
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: prim.height,
                subKey: 'h',
              ),
            );
          }
        }
      } else if (prim is CADArcEntity) {
        final geom = prim.computeCircumcircle();
        final sScr = toScreen(prim.startPoint);
        final eScr = toScreen(prim.endPoint);
        final mScr = toScreen(prim.pointOnArc);

        if (geom == null) {
          if (sScr != Offset.zero && eScr != Offset.zero) {
            canvas.drawLine(sScr, eScr, haloPaint);
            canvas.drawLine(sScr, eScr, strokePaint);
          }
        } else {
          final cScr = toScreen(geom.center);
          final arcPath = Path();
          const int numSegs = 36;
          for (int i = 0; i <= numSegs; i++) {
            final t = i / numSegs;
            final ang = geom.startAngle + t * geom.sweep;
            final ptLocal = Offset(geom.center.dx + geom.radius * math.cos(ang), geom.center.dy + geom.radius * math.sin(ang));
            final ptScr = toScreen(ptLocal);
            if (i == 0) {
              arcPath.moveTo(ptScr.dx, ptScr.dy);
            } else {
              arcPath.lineTo(ptScr.dx, ptScr.dy);
            }
          }

          canvas.drawPath(arcPath, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, arcPath, strokePaint);
          } else {
            canvas.drawPath(arcPath, strokePaint);
          }

          _drawVertexDot(canvas, sScr, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, eScr, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, cScr, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) && !entitiesWithDrivingDim.contains(prim.id)) {
            _drawRadialOrDiameterLeaderDimension(
              canvas: canvas,
              centerScr: cScr,
              rimScr: mScr,
              label: 'R${_formatDimValue(geom.radius)}',
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: prim.id,
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.radius,
                currentValue: geom.radius,
              ),
            );
          }
        }
      } else if (prim is CADCircleEntity) {
        final cScr = toScreen(prim.center);
        // 35° leader point on the circle rim (matches Onshape Ø17 / Ø33 in image_31d02d.png!)
        const double leaderAngle = -math.pi / 4.0;
        final rimLocal = Offset(
          prim.center.dx + prim.radius * math.cos(leaderAngle),
          prim.center.dy + prim.radius * math.sin(leaderAngle),
        );
        final rEdge = toScreen(rimLocal);

        if (cScr != Offset.zero) {
          final circlePath = Path();
          const int segs = 56;
          for (int i = 0; i <= segs; i++) {
            final theta = i * 2.0 * math.pi / segs;
            final ptLocal = Offset(
              prim.center.dx + prim.radius * math.cos(theta),
              prim.center.dy + prim.radius * math.sin(theta),
            );
            final ptScr = toScreen(ptLocal);
            if (i == 0) {
              circlePath.moveTo(ptScr.dx, ptScr.dy);
            } else {
              circlePath.lineTo(ptScr.dx, ptScr.dy);
            }
          }
          circlePath.close();

          canvas.drawPath(circlePath, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, circlePath, strokePaint);
          } else {
            canvas.drawPath(circlePath, strokePaint);
          }

          _drawVertexDot(canvas, cScr, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) &&
              !entitiesWithDrivingDim.contains(prim.id) &&
              rEdge != Offset.zero) {
            _drawRadialOrDiameterLeaderDimension(
              canvas: canvas,
              centerScr: cScr,
              rimScr: rEdge,
              label: 'Ø${_formatDimValue(prim.radius * 2.0)}',
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: prim.id,
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.diameter,
                currentValue: prim.radius * 2.0,
              ),
            );
          }
        }
      } else if (prim is CADLineEntity) {
        final sScr = toScreen(prim.start);
        final eScr = toScreen(prim.end);
        if (sScr != Offset.zero && eScr != Offset.zero) {
          canvas.drawLine(sScr, eScr, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedLine(canvas, sScr, eScr, strokePaint);
          } else {
            canvas.drawLine(sScr, eScr, strokePaint);
          }
          _drawVertexDot(canvas, sScr, strokePaint.color, isSel: isSel);
          _drawVertexDot(canvas, eScr, strokePaint.color, isSel: isSel);

          if ((isSel || viewModel.showSketchExpressions) &&
              !prim.isConstruction &&
              !entitiesWithDrivingDim.contains(prim.id)) {
            final len = (prim.end - prim.start).distance;
            _drawLinearCadDimension(
              canvas: canvas,
              pA: sScr,
              pB: eScr,
              offsetPx: -26.0,
              label: _formatDimValue(len),
              isDriving: false,
              hitInfo: SketchDimensionTagHit(
                tagKey: prim.id,
                screenRect: Rect.zero,
                primaryEntityId: prim.id,
                constraintType: CadConstraintType.distance,
                currentValue: len,
              ),
            );
          }
        }
      } else if (prim is CADPolylineEntity) {
        if (prim.points.isNotEmpty) {
          final polyPath = Path();
          bool firstPt = true;
          for (final pt in prim.points) {
            final scr = toScreen(pt);
            if (scr == Offset.zero) continue;
            if (firstPt) {
              polyPath.moveTo(scr.dx, scr.dy);
              firstPt = false;
            } else {
              polyPath.lineTo(scr.dx, scr.dy);
            }
          }
          if (prim.isClosed) polyPath.close();
          canvas.drawPath(polyPath, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, polyPath, strokePaint);
          } else {
            canvas.drawPath(polyPath, strokePaint);
          }
          for (final pt in prim.points) {
            _drawVertexDot(canvas, toScreen(pt), strokePaint.color, isSel: isSel);
          }
        }
      } else if (prim is CADPointEntity) {
        final ptScr = toScreen(prim.position);
        if (ptScr != Offset.zero) {
          _drawVertexDot(canvas, ptScr, strokePaint.color, isSel: isSel);
        }
      } else {
        final segs = prim.toLineSegments();
        if (segs.isNotEmpty) {
          final path = Path();
          for (final s in segs) {
            final pA = toScreen(s.start);
            final pB = toScreen(s.end);
            if (pA != Offset.zero && pB != Offset.zero) {
              path.moveTo(pA.dx, pA.dy);
              path.lineTo(pB.dx, pB.dy);
            }
          }
          canvas.drawPath(path, haloPaint);
          if (prim.isConstruction) {
            _drawCenterlineDashedPath(canvas, path, strokePaint);
          } else {
            canvas.drawPath(path, strokePaint);
          }
        }
        if (prim is CADRegularPolygonEntity) {
          final cPath = Path();
          for (int i = 0; i <= 36; i++) {
            final a = (2.0 * math.pi * i) / 36;
            final pt = toScreen(prim.center + Offset(math.cos(a), math.sin(a)) * prim.radius);
            if (i == 0) {
              cPath.moveTo(pt.dx, pt.dy);
            } else {
              cPath.lineTo(pt.dx, pt.dy);
            }
          }
          _drawCenterlineDashedPath(
            canvas,
            cPath,
            Paint()
              ..color = const Color(0xFF64748B)
              ..strokeWidth = 1.1
              ..style = PaintingStyle.stroke,
          );
          _drawVertexDot(canvas, toScreen(prim.center), strokePaint.color, isSel: isSel);
        }
      }
    }

    // 4. Render All Explicit Driving Dimensional Constraints (image_31d02d.png & image_31d0a3.png)
    for (final c in plane.constraints) {
      if (!c.isActive || !c.isDimensional) continue;
      _drawDrivingDimensionConstraint(canvas, plane, c, toScreen);
    }

    // 5. Render Geometric Constraint Glyphs (H, V, ⊥, //, ◎, ⌒, =, ⇋)
    if (viewModel.showSketchConstraints && plane.constraints.isNotEmpty) {
      for (final constraint in plane.constraints) {
        if (!constraint.isActive || constraint.isDimensional) continue;
        final isConstraintSelected = (viewModel.selectedSketchConstraint?.id == constraint.id) ||
            constraint.entityIds.any((id) => viewModel.selectedSketchEntityIds.contains(id));

        Offset? badgePos;
        if (constraint.entityIds.isNotEmpty) {
          final firstEnt = plane.primitives.where((p) => p.id == constraint.entityIds[0]).firstOrNull;
          if (firstEnt != null) {
            badgePos = toScreen(_getEntityBadgeAnchor(firstEnt));
          }
        }

        if (badgePos != null && badgePos != Offset.zero) {
          _drawConstraintBadge(canvas, badgePos, constraint.symbol, isHighlighted: isConstraintSelected);
        }
      }
    }

    // 6. Glowing Yellow Dashed Inferencing Alignment Lines + Live H/V Inference Badge
    final inferPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    const double inferExtent = 300.0;
    for (final match in viewModel.currentInferenceGuides) {
      if (match.isHorizontal) {
        final p1 = toScreen(Offset(-inferExtent, match.value));
        final p2 = toScreen(Offset(inferExtent, match.value));
        if (p1 != Offset.zero && p2 != Offset.zero) {
          _drawDashedLine(canvas, p1, p2, inferPaint);
        }
      } else {
        final p1 = toScreen(Offset(match.value, -inferExtent));
        final p2 = toScreen(Offset(match.value, inferExtent));
        if (p1 != Offset.zero && p2 != Offset.zero) {
          _drawDashedLine(canvas, p1, p2, inferPaint);
        }
      }
    }

    // 7. Live Interactive Sketch Rubber-Band Preview
    final hoverLocal = viewModel.activePlaneHoverLocal;
    if (viewModel.sketchInteractiveStartPoint != null && hoverLocal != null) {
      final pStart = viewModel.sketchInteractiveStartPoint!;
      final sScr = toScreen(pStart);
      final hScr = toScreen(hoverLocal);
      final previewPaint = Paint()
        ..color = const Color(0xFF0284C7)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;

      if (sScr != Offset.zero && hScr != Offset.zero) {
        final tool = viewModel.activeSketchTool;

        if (tool == 'rectangle' || tool == 'rect') {
          final x = math.min(pStart.dx, hoverLocal.dx);
          final y = math.min(pStart.dy, hoverLocal.dy);
          final w = (hoverLocal.dx - pStart.dx).abs();
          final h = (hoverLocal.dy - pStart.dy).abs();
          final p1 = toScreen(Offset(x, y));
          final p2 = toScreen(Offset(x + w, y));
          final p3 = toScreen(Offset(x + w, y + h));
          final p4 = toScreen(Offset(x, y + h));

          if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
            final rPath = Path()
              ..moveTo(p1.dx, p1.dy)
              ..lineTo(p2.dx, p2.dy)
              ..lineTo(p3.dx, p3.dy)
              ..lineTo(p4.dx, p4.dy)
              ..close();
            _drawDashedPath(canvas, rPath, previewPaint);
            _drawLinearCadDimension(canvas: canvas, pA: p1, pB: p2, offsetPx: -24.0, label: _formatDimValue(w), isDriving: false);
            _drawLinearCadDimension(canvas: canvas, pA: p2, pB: p3, offsetPx: 24.0, label: _formatDimValue(h), isDriving: false);
          }
        } else if (tool == 'center_rect') {
          final w = 2.0 * (hoverLocal.dx - pStart.dx).abs();
          final h = 2.0 * (hoverLocal.dy - pStart.dy).abs();
          final x = pStart.dx - w / 2.0;
          final y = pStart.dy - h / 2.0;
          final p1 = toScreen(Offset(x, y));
          final p2 = toScreen(Offset(x + w, y));
          final p3 = toScreen(Offset(x + w, y + h));
          final p4 = toScreen(Offset(x, y + h));

          if (p1 != Offset.zero && p2 != Offset.zero && p3 != Offset.zero && p4 != Offset.zero) {
            final rPath = Path()
              ..moveTo(p1.dx, p1.dy)
              ..lineTo(p2.dx, p2.dy)
              ..lineTo(p3.dx, p3.dy)
              ..lineTo(p4.dx, p4.dy)
              ..close();
            _drawDashedPath(canvas, rPath, previewPaint);
            _drawLinearCadDimension(canvas: canvas, pA: p1, pB: p2, offsetPx: -24.0, label: _formatDimValue(w), isDriving: false);
            _drawLinearCadDimension(canvas: canvas, pA: p2, pB: p3, offsetPx: 24.0, label: _formatDimValue(h), isDriving: false);
          }
        } else if (tool == 'circle' || tool == 'hole') {
          final rLocal = (hoverLocal - pStart).distance;
          final circlePath = Path();
          const int segs = 48;
          for (int i = 0; i <= segs; i++) {
            final theta = i * 2.0 * math.pi / segs;
            final ptLocal = Offset(
              pStart.dx + rLocal * math.cos(theta),
              pStart.dy + rLocal * math.sin(theta),
            );
            final ptScr = toScreen(ptLocal);
            if (i == 0) {
              circlePath.moveTo(ptScr.dx, ptScr.dy);
            } else {
              circlePath.lineTo(ptScr.dx, ptScr.dy);
            }
          }
          circlePath.close();
          _drawDashedPath(canvas, circlePath, previewPaint);
          _drawRadialOrDiameterLeaderDimension(
            canvas: canvas,
            centerScr: sScr,
            rimScr: hScr,
            label: 'Ø${_formatDimValue(rLocal * 2.0)}',
            isDriving: false,
          );
        } else if (tool == 'line' || tool == 'midpoint_line') {
          _drawDashedLine(canvas, sScr, hScr, previewPaint);
          _drawVertexDot(canvas, sScr, const Color(0xFF0284C7), isSel: true);
          final len = (hoverLocal - pStart).distance;
          _drawLinearCadDimension(canvas: canvas, pA: sScr, pB: hScr, offsetPx: -24.0, label: _formatDimValue(len), isDriving: false);

          // Show live Onshape H / V automatic constraint inference badge while drawing a line!
          final dx = (hoverLocal.dx - pStart.dx).abs();
          final dy = (hoverLocal.dy - pStart.dy).abs();
          if (len > 3.0) {
            if (dy < dx * 0.06) {
              _drawConstraintBadge(canvas, Offset((sScr.dx + hScr.dx) / 2, (sScr.dy + hScr.dy) / 2 + 18), 'H', isHighlighted: true);
            } else if (dx < dy * 0.06) {
              _drawConstraintBadge(canvas, Offset((sScr.dx + hScr.dx) / 2 + 18, (sScr.dy + hScr.dy) / 2), 'V', isHighlighted: true);
            }
          }
        }
      }
    }
  }

  /// Renders an explicit driving `CadConstraint` dimension (`distance`, `diameter`, `radius`, `angle`)
  /// using authentic Onshape CAD extension lines, arrowheads, leader lines, or angular arcs.
  void _drawDrivingDimensionConstraint(
    Canvas canvas,
    CADSketchPlane plane,
    CadConstraint c,
    Offset Function(Offset) toScreen,
  ) {
    if (c.entityIds.isEmpty) return;
    final val = c.parameterValue ?? 0.0;
    final rawId0 = c.entityIds[0];
    final baseId0 = rawId0.split(':').first;
    final subKey0 = rawId0.contains(':') ? rawId0.split(':').last : null;
    final e1 = plane.primitives.where((p) => p.id == baseId0).firstOrNull;
    if (e1 == null) return;

    final String formattedVal = _formatConstraintText(c, val);

    // 1. TWO-ENTITY DIMENSIONS (Angle 27° or Distance 60 / 65 / 10)
    if (c.entityIds.length >= 2) {
      final baseId1 = c.entityIds[1].split(':').first;
      final e2 = plane.primitives.where((p) => p.id == baseId1).firstOrNull;
      if (e2 == null) return;

      if (c.type == CadConstraintType.angle && e1 is CADLineEntity && e2 is CADLineEntity) {
        _drawAngularCadDimension(
          canvas: canvas,
          l1: e1,
          l2: e2,
          toScreen: toScreen,
          label: '$formattedVal°',
          hitInfo: SketchDimensionTagHit(
            tagKey: c.id,
            screenRect: Rect.zero,
            primaryEntityId: e1.id,
            secondaryEntityId: e2.id,
            constraintType: CadConstraintType.angle,
            existingConstraintId: c.id,
            currentValue: val,
            unitSuffix: 'deg',
          ),
        );
        return;
      }

      // Linear distance between two entities
      Offset pA;
      Offset pB;
      if (e1 is CADLineEntity && e2 is! CADLineEntity) {
        final anchor2 = _getEntityCenter(e2);
        pA = toScreen(_projectPointToInfiniteLine(anchor2, e1.start, e1.end));
        pB = toScreen(anchor2);
      } else if (e2 is CADLineEntity && e1 is! CADLineEntity) {
        final anchor1 = _getEntityCenter(e1);
        pA = toScreen(anchor1);
        pB = toScreen(_projectPointToInfiniteLine(anchor1, e2.start, e2.end));
      } else if (e1 is CADLineEntity && e2 is CADLineEntity) {
        final mid1 = (e1.start + e1.end) * 0.5;
        pA = toScreen(mid1);
        pB = toScreen(_projectPointToInfiniteLine(mid1, e2.start, e2.end));
      } else {
        pA = toScreen(_getEntityCenter(e1));
        pB = toScreen(_getEntityCenter(e2));
      }

      if (pA != Offset.zero && pB != Offset.zero) {
        _drawLinearCadDimension(
          canvas: canvas,
          pA: pA,
          pB: pB,
          offsetPx: c.labelOffset * 1.4,
          label: formattedVal,
          isDriving: true,
          hitInfo: SketchDimensionTagHit(
            tagKey: c.id,
            screenRect: Rect.zero,
            primaryEntityId: e1.id,
            secondaryEntityId: e2.id,
            constraintType: CadConstraintType.distance,
            existingConstraintId: c.id,
            currentValue: val,
          ),
        );
      }
      return;
    }

    // 2. SINGLE-ENTITY DRIVING DIMENSIONS
    if (c.type == CadConstraintType.diameter && e1 is CADCircleEntity) {
      final cScr = toScreen(e1.center);
      const double leaderAng = -math.pi / 4.0;
      final rScr = toScreen(Offset(
        e1.center.dx + e1.radius * math.cos(leaderAng),
        e1.center.dy + e1.radius * math.sin(leaderAng),
      ));
      if (cScr != Offset.zero && rScr != Offset.zero) {
        _drawRadialOrDiameterLeaderDimension(
          canvas: canvas,
          centerScr: cScr,
          rimScr: rScr,
          label: 'Ø$formattedVal',
          isDriving: true,
          hitInfo: SketchDimensionTagHit(
            tagKey: c.id,
            screenRect: Rect.zero,
            primaryEntityId: e1.id,
            constraintType: CadConstraintType.diameter,
            existingConstraintId: c.id,
            currentValue: val,
          ),
        );
      }
    } else if (c.type == CadConstraintType.radius) {
      Offset cScr = Offset.zero;
      Offset rScr = Offset.zero;
      if (e1 is CADCircleEntity) {
        cScr = toScreen(e1.center);
        rScr = toScreen(Offset(e1.center.dx + e1.radius * 0.707, e1.center.dy - e1.radius * 0.707));
      } else if (e1 is CADArcEntity) {
        final g = e1.computeCircumcircle();
        if (g != null) {
          cScr = toScreen(g.center);
          rScr = toScreen(e1.pointOnArc);
        }
      } else if (e1 is CADCenterPointArcEntity) {
        cScr = toScreen(e1.center);
        rScr = toScreen(e1.startPoint);
      }
      if (cScr != Offset.zero && rScr != Offset.zero) {
        _drawRadialOrDiameterLeaderDimension(
          canvas: canvas,
          centerScr: cScr,
          rimScr: rScr,
          label: 'R$formattedVal',
          isDriving: true,
          hitInfo: SketchDimensionTagHit(
            tagKey: c.id,
            screenRect: Rect.zero,
            primaryEntityId: e1.id,
            constraintType: CadConstraintType.radius,
            existingConstraintId: c.id,
            currentValue: val,
          ),
        );
      }
    } else if (c.type == CadConstraintType.distance) {
      if (e1 is CADLineEntity) {
        final pA = toScreen(e1.start);
        final pB = toScreen(e1.end);
        if (pA != Offset.zero && pB != Offset.zero) {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: pA,
            pB: pB,
            offsetPx: -c.labelOffset.abs() * 1.5,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
            ),
          );
        }
      } else if (e1 is CADRectangleEntity) {
        final p1 = toScreen(e1.startPoint);
        final p2 = toScreen(Offset(e1.startPoint.dx + e1.width, e1.startPoint.dy));
        final p3 = toScreen(Offset(e1.startPoint.dx + e1.width, e1.startPoint.dy + e1.height));
        if (subKey0 == 'h') {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p2,
            pB: p3,
            offsetPx: 28.0,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
              subKey: 'h',
            ),
          );
        } else {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p1,
            pB: p2,
            offsetPx: -26.0,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
              subKey: 'w',
            ),
          );
        }
      } else if (e1 is CADCenterRectangleEntity) {
        final p1 = toScreen(e1.topLeft);
        final p2 = toScreen(e1.topRight);
        final p3 = toScreen(e1.bottomRight);
        if (subKey0 == 'h') {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p2,
            pB: p3,
            offsetPx: 28.0,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
              subKey: 'h',
            ),
          );
        } else {
          _drawLinearCadDimension(
            canvas: canvas,
            pA: p1,
            pB: p2,
            offsetPx: -26.0,
            label: formattedVal,
            isDriving: true,
            hitInfo: SketchDimensionTagHit(
              tagKey: c.id,
              screenRect: Rect.zero,
              primaryEntityId: e1.id,
              constraintType: CadConstraintType.distance,
              existingConstraintId: c.id,
              currentValue: val,
              subKey: 'w',
            ),
          );
        }
      }
    }
  }

  /// Draws an authentic Onshape Linear Dimension with witness/extension lines,
  /// filled CAD arrowheads, and a clickable central dimension tag (matching image_31d02d.png).
  void _drawLinearCadDimension({
    required Canvas canvas,
    required Offset pA,
    required Offset pB,
    required double offsetPx,
    required String label,
    required bool isDriving,
    SketchDimensionTagHit? hitInfo,
  }) {
    final seg = pB - pA;
    final len = seg.distance;
    if (len < 6.0) return;

    final dir = seg / len;
    final sign = offsetPx >= 0 ? 1.0 : -1.0;
    final n = Offset(-dir.dy, dir.dx) * sign;
    final absOff = offsetPx.abs().clamp(16.0, 120.0);

    final dimA = pA + n * absOff;
    final dimB = pB + n * absOff;

    final dimColor = isDriving ? const Color(0xFF0F172A) : const Color(0xFF334155);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;

    // 1. Extension / witness lines (3px gap from entity vertex, 5px overshoot past dimension line)
    canvas.drawLine(pA + n * 3.0, dimA + n * 5.0, linePaint);
    canvas.drawLine(pB + n * 3.0, dimB + n * 5.0, linePaint);

    // 2. Dimension line + filled arrowheads at both ends
    canvas.drawLine(dimA, dimB, linePaint);
    _drawCadArrowhead(canvas, dimA, dir, dimColor);
    _drawCadArrowhead(canvas, dimB, -dir, dimColor);

    // 3. Clickable Dimension Value Tag centered on the dimension line
    final mid = (dimA + dimB) * 0.5;
    _drawClickableDimensionTag(canvas, mid, label, isDriving: isDriving, hitInfo: hitInfo);
  }

  /// Draws an Onshape Diameter (`Ø17`, `Ø33`) or Radius (`R3`, `R10`) leader dimension
  /// with an arrowhead on the perimeter and a horizontal shoulder leading to the tag.
  void _drawRadialOrDiameterLeaderDimension({
    required Canvas canvas,
    required Offset centerScr,
    required Offset rimScr,
    required String label,
    required bool isDriving,
    SketchDimensionTagHit? hitInfo,
  }) {
    final radial = rimScr - centerScr;
    final rLen = radial.distance;
    final unit = rLen > 1.0 ? radial / rLen : const Offset(0.707, -0.707);

    final elbow = rimScr + unit * 22.0;
    final shoulderDir = unit.dx >= 0 ? const Offset(14.0, 0.0) : const Offset(-14.0, 0.0);
    final tagAnchor = elbow + shoulderDir;

    final dimColor = isDriving ? const Color(0xFF0F172A) : const Color(0xFF334155);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;

    canvas.drawLine(rimScr, elbow, linePaint);
    canvas.drawLine(elbow, tagAnchor, linePaint);
    // Arrowhead pointing inward toward rimScr
    _drawCadArrowhead(canvas, rimScr, unit, dimColor);

    final tagCenter = tagAnchor + Offset(unit.dx >= 0 ? 22.0 : -22.0, 0.0);
    _drawClickableDimensionTag(canvas, tagCenter, label, isDriving: isDriving, hitInfo: hitInfo);
  }

  /// Draws an Onshape Angular Dimension (`27°` in image_31d02d.png) with a curved arc and arrowheads.
  void _drawAngularCadDimension({
    required Canvas canvas,
    required CADLineEntity l1,
    required CADLineEntity l2,
    required Offset Function(Offset) toScreen,
    required String label,
    SketchDimensionTagHit? hitInfo,
  }) {
    final s1 = toScreen(l1.start);
    final e1 = toScreen(l1.end);
    final s2 = toScreen(l2.start);
    final e2 = toScreen(l2.end);
    if (s1 == Offset.zero || e1 == Offset.zero || s2 == Offset.zero || e2 == Offset.zero) return;

    final vertex = _lineLineIntersectionScreen(s1, e1, s2, e2) ?? s1;
    final v1 = (e1 - vertex).distance > (s1 - vertex).distance ? (e1 - vertex) : (s1 - vertex);
    final v2 = (e2 - vertex).distance > (s2 - vertex).distance ? (e2 - vertex) : (s2 - vertex);
    if (v1.distance < 4.0 || v2.distance < 4.0) return;

    final a1 = math.atan2(v1.dy, v1.dx);
    final a2 = math.atan2(v2.dy, v2.dx);
    double sweep = a2 - a1;
    while (sweep <= -math.pi) sweep += 2.0 * math.pi;
    while (sweep > math.pi) sweep -= 2.0 * math.pi;

    const double arcR = 38.0;
    final arcRect = Rect.fromCircle(center: vertex, radius: arcR);
    final dimColor = const Color(0xFF0F172A);
    final linePaint = Paint()
      ..color = dimColor
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;

    canvas.drawArc(arcRect, a1, sweep, false, linePaint);

    final pArcStart = vertex + Offset(math.cos(a1), math.sin(a1)) * arcR;
    final pArcEnd = vertex + Offset(math.cos(a1 + sweep), math.sin(a1 + sweep)) * arcR;
    final tStart = Offset(-math.sin(a1), math.cos(a1)) * (sweep >= 0 ? 1.0 : -1.0);
    final tEnd = Offset(-math.sin(a1 + sweep), math.cos(a1 + sweep)) * (sweep >= 0 ? -1.0 : 1.0);
    _drawCadArrowhead(canvas, pArcStart, tStart, dimColor);
    _drawCadArrowhead(canvas, pArcEnd, tEnd, dimColor);

    final midAngle = a1 + sweep * 0.5;
    final tagCenter = vertex + Offset(math.cos(midAngle), math.sin(midAngle)) * arcR;
    _drawClickableDimensionTag(canvas, tagCenter, label, isDriving: true, hitInfo: hitInfo);
  }

  void _drawCadArrowhead(Canvas canvas, Offset tip, Offset inwardDir, Color color) {
    final len = inwardDir.distance;
    if (len < 1e-4) return;
    final u = inwardDir / len;
    final n = Offset(-u.dy, u.dx);
    const double arrowLen = 7.5;
    const double arrowHalfW = 2.6;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + u.dx * arrowLen + n.dx * arrowHalfW, tip.dy + u.dy * arrowLen + n.dy * arrowHalfW)
      ..lineTo(tip.dx + u.dx * arrowLen - n.dx * arrowHalfW, tip.dy + u.dy * arrowLen - n.dy * arrowHalfW)
      ..close();

    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  void _drawClickableDimensionTag(
    Canvas canvas,
    Offset center,
    String text, {
    required bool isDriving,
    SketchDimensionTagHit? hitInfo,
  }) {
    if (center == Offset.zero) return;
    final isBeingEdited = hitInfo != null &&
        viewModel.activeEditingDimensionTagKey == hitInfo.tagKey;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isDriving ? const Color(0xFF0F172A) : const Color(0xFF475569),
          fontSize: 11.5,
          fontWeight: isDriving ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 12.0,
      height: tp.height + 6.0,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3.5));

    // White background pill breaks the dimension line cleanly around the text (image_31d02d.png)
    canvas.drawRRect(
      rrect,
      Paint()..color = isBeingEdited ? const Color(0xFFE0F2FE) : const Color(0xF5FFFFFF),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = isBeingEdited
            ? const Color(0xFF0284C7)
            : isDriving
                ? const Color(0xFF94A3B8)
                : const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isBeingEdited ? 1.5 : 0.9,
    );

    tp.paint(canvas, Offset(center.dx - tp.width / 2.0, center.dy - tp.height / 2.0));

    if (hitInfo != null) {
      viewModel.sketchDimensionHitRects.add(SketchDimensionTagHit(
        tagKey: hitInfo.tagKey,
        screenRect: rect.inflate(5.0),
        primaryEntityId: hitInfo.primaryEntityId,
        secondaryEntityId: hitInfo.secondaryEntityId,
        constraintType: hitInfo.constraintType,
        existingConstraintId: hitInfo.existingConstraintId,
        currentValue: hitInfo.currentValue,
        unitSuffix: hitInfo.unitSuffix,
        subKey: hitInfo.subKey,
      ));
    }
  }

  void _drawVertexDot(Canvas canvas, Offset pt, Color color, {required bool isSel}) {
    if (pt == Offset.zero) return;
    canvas.drawCircle(pt, isSel ? 4.2 : 3.2, Paint()..color = Colors.white);
    canvas.drawCircle(
      pt,
      isSel ? 4.2 : 3.2,
      Paint()
        ..color = isSel ? const Color(0xFFF59E0B) : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  String _formatDimValue(double v) {
    return (v - v.roundToDouble()).abs() < 0.05
        ? v.round().toString()
        : v.toStringAsFixed(1);
  }

  String _formatConstraintText(CadConstraint c, double val) {
    final base = _formatDimValue(val);
    final tol = (c.tolerancePlus != null && c.tolerancePlus! > 0)
        ? ' ±${_formatDimValue(c.tolerancePlus!)}'
        : '';
    if (viewModel.showSketchExpressions && c.expression != null && c.expression!.isNotEmpty) {
      return '${c.expression} = $base$tol';
    }
    return '$base$tol';
  }

  Offset _getEntityCenter(CADPrimitiveEntity e) {
    if (e is CADCircleEntity) return e.center;
    if (e is CADPointEntity) return e.position;
    if (e is CADCenterRectangleEntity) return e.center;
    if (e is CADRectangleEntity) {
      return Offset(e.startPoint.dx + e.width * 0.5, e.startPoint.dy + e.height * 0.5);
    }
    if (e is CADLineEntity) return (e.start + e.end) * 0.5;
    if (e is CADArcEntity) return e.computeCircumcircle()?.center ?? e.pointOnArc;
    return Offset.zero;
  }

  static Offset _projectPointToInfiniteLine(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return a;
    final t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    return a + ab * t;
  }

  static Offset? _lineLineIntersectionScreen(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d = (p1.dx - p2.dx) * (p3.dy - p4.dy) - (p1.dy - p2.dy) * (p3.dx - p4.dx);
    if (d.abs() < 1e-5) return null;
    final pre = p1.dx * p2.dy - p1.dy * p2.dx;
    final post = p3.dx * p4.dy - p3.dy * p4.dx;
    final x = (pre * (p3.dx - p4.dx) - (p1.dx - p2.dx) * post) / d;
    final y = (pre * (p3.dy - p4.dy) - (p1.dy - p2.dy) * post) / d;
    return Offset(x, y);
  }

  Offset _getEntityBadgeAnchor(CADPrimitiveEntity e) {
    if (e is CADLineEntity) {
      return Offset((e.start.dx + e.end.dx) / 2.0, (e.start.dy + e.end.dy) / 2.0);
    } else if (e is CADCircleEntity) {
      return Offset(e.center.dx, e.center.dy - e.radius);
    } else if (e is CADArcEntity) {
      return e.pointOnArc;
    } else if (e is CADRectangleEntity) {
      return Offset(e.startPoint.dx + e.width / 2.0, e.startPoint.dy);
    } else if (e is CADCenterRectangleEntity) {
      return Offset(e.center.dx, e.center.dy - e.height / 2.0);
    }
    return Offset.zero;
  }

  void _drawConstraintBadge(Canvas canvas, Offset pos, String symbol, {bool isHighlighted = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(
          color: isHighlighted ? const Color(0xFFB45309) : const Color(0xFF0F172A),
          fontSize: 10.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos + const Offset(0, -10), width: math.max(16.0, tp.width + 6), height: math.max(16.0, tp.height + 4)),
      const Radius.circular(3),
    );

    canvas.drawRRect(badgeRect, Paint()..color = isHighlighted ? const Color(0xFFFEF3C7) : const Color(0xFFE2E8F0));
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = isHighlighted ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
    tp.paint(canvas, pos + Offset(-tp.width / 2, -10 - tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dist = (p2 - p1).distance;
    if (dist < 1.0) return;
    final dir = (p2 - p1) / dist;
    double walked = 0.0;
    while (walked < dist) {
      final start = p1 + dir * walked;
      final end = p1 + dir * math.min(walked + 5.0, dist);
      canvas.drawLine(start, end, paint);
      walked += 9.0;
    }
  }

  /// Draws Onshape long-short-long centerline construction dashing (`─── ╌ ───`)
  void _drawCenterlineDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dist = (p2 - p1).distance;
    if (dist < 1.0) return;
    final dir = (p2 - p1) / dist;
    double walked = 0.0;
    bool longDash = true;
    while (walked < dist) {
      final segLen = longDash ? 10.0 : 3.5;
      final start = p1 + dir * walked;
      final end = p1 + dir * math.min(walked + segLen, dist);
      canvas.drawLine(start, end, paint);
      walked += segLen + 3.5;
      longDash = !longDash;
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      double dist = 0.0;
      while (dist < metric.length) {
        final extract = metric.extractPath(dist, math.min(dist + 6.0, metric.length));
        canvas.drawPath(extract, paint);
        dist += 10.0;
      }
    }
  }

  void _drawCenterlineDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      double dist = 0.0;
      bool longDash = true;
      while (dist < metric.length) {
        final segLen = longDash ? 10.0 : 3.5;
        final extract = metric.extractPath(dist, math.min(dist + segLen, metric.length));
        canvas.drawPath(extract, paint);
        dist += segLen + 3.5;
        longDash = !longDash;
      }
    }
  }

  @override
  bool shouldRepaint(covariant Assembly3DSurfaceSketchPainter oldDelegate) => true;
}
```

---

## 5. Step 4: Replace the Clunky `CIRCLE PARAMETERS` Modal with Onshape's Floating Inline Dimension Popover (`image_31d0a3.png`)

### Complete Replacement for `lib/assembly_studio/views/widgets/viewport/overlays/assembly_sketch_parameter_panel.dart`
Look at `image_31d0a3.png`: when you click a dimension tag on the sketch (like `60` or `Ø 64`), Onshape opens a **compact floating inline popover** anchored directly at the clicked tag's `(x, y)` screen coordinate with:
- Auto-focused, pre-selected value field (`60 mm` or `27 deg`, supporting arithmetic expressions like `60/2` or `25+15`)
- `±` Tolerance toggle button (exactly as shown in `image_31d0a3.png`!)
- Green Check (`✓` / `Enter`) and Red Cancel (`✕` / `Esc`) buttons

And when a sketch entity is selected without an active dimension popover, a non-intrusive, compact Onshape Quick-Action Bar lets the user toggle `Construction (Q)`, add a `Dimension (D)`, apply `Fillet` / `Chamfer`, open `Extrude (E)`, or `Delete`—completely eliminating the clunky `CIRCLE PARAMETERS` modal (`image_31c8cd.jpg`)!

Replace the entire contents of `lib/assembly_studio/views/widgets/viewport/overlays/assembly_sketch_parameter_panel.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../sheet_metal_studio/engine/constraints/expression_parser_engine.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Onshape Inline Floating Dimension Popover (matches image_31d0a3.png) +
/// Compact Contextual Sketch Quick-Action Pill (replaces the clunky CIRCLE PARAMETERS modal).
class AssemblySketchParameterPanel extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback? onRebuildModel;

  const AssemblySketchParameterPanel({
    super.key,
    required this.viewModel,
    this.onRebuildModel,
  });

  @override
  State<AssemblySketchParameterPanel> createState() => _AssemblySketchParameterPanelState();
}

class _AssemblySketchParameterPanelState extends State<AssemblySketchParameterPanel> {
  late TextEditingController _valueController;
  late TextEditingController _tolController;
  final FocusNode _focusNode = FocusNode();
  String? _lastTagKey;
  bool _showTolerance = false;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController();
    _tolController = TextEditingController(text: '0.1');
    _syncFromActiveDimension();
  }

  @override
  void didUpdateWidget(covariant AssemblySketchParameterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromActiveDimension();
  }

  void _syncFromActiveDimension() {
    final hit = widget.viewModel.activeEditingDimensionHit;
    if (hit != null && hit.tagKey != _lastTagKey) {
      _lastTagKey = hit.tagKey;
      final formatted = (hit.currentValue - hit.currentValue.roundToDouble()).abs() < 0.05
          ? hit.currentValue.round().toString()
          : hit.currentValue.toStringAsFixed(1);
      _valueController.text = '$formatted ${hit.unitSuffix}';
      _valueController.selection = TextSelection(baseOffset: 0, extentOffset: formatted.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else if (hit == null) {
      _lastTagKey = null;
    }
  }

  void _commitDimension() {
    final vm = widget.viewModel;
    final hit = vm.activeEditingDimensionHit;
    if (hit == null) return;

    final raw = _valueController.text
        .replaceAll('mm', '')
        .replaceAll('deg', '')
        .replaceAll('°', '')
        .replaceAll('Ø', '')
        .replaceAll('R', '')
        .trim();

    double? parsed = double.tryParse(raw);
    String? expr;
    if (parsed == null && raw.isNotEmpty) {
      try {
        parsed = ExpressionParserEngine.evaluate(raw, const {});
        expr = raw;
      } catch (_) {}
    }

    if (parsed != null && parsed > 0) {
      final double? tol = _showTolerance ? double.tryParse(_tolController.text.trim()) : null;
      vm.commitInlineSketchDimension(
        hit: hit,
        newValue: parsed,
        expression: expr,
        tolerancePlusMinus: tol,
      );
      widget.onRebuildModel?.call();
    } else {
      vm.closeInlineSketchDimensionEditor();
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _tolController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final hit = vm.activeEditingDimensionHit;

    // 1. ONSHAPE INLINE FLOATING DIMENSION POPOVER (image_31d0a3.png)
    if (hit != null) {
      return Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFF94A3B8), width: 1.0),
            boxShadow: const [
              BoxShadow(color: Color(0x29000000), blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dimension Value Input Box (e.g. "60 mm")
                  Container(
                    width: 104,
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF0284C7), width: 1.6),
                    ),
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                          vm.closeInlineSketchDimensionEditor();
                        }
                      },
                      child: TextField(
                        controller: _valueController,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 5),
                        ),
                        onSubmitted: (_) => _commitDimension(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Onshape '±' Tolerance Button (image_31d0a3.png)
                  Tooltip(
                    message: 'Toggle ± Tolerance',
                    child: InkWell(
                      onTap: () => setState(() => _showTolerance = !_showTolerance),
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        width: 26,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _showTolerance ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: _showTolerance ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: const Text(
                          '±',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Green Check (Accept / Enter)
                  Tooltip(
                    message: 'Accept dimension (Enter)',
                    child: InkWell(
                      onTap: _commitDimension,
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        width: 24,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Icon(Icons.check, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  // Cancel (Esc)
                  Tooltip(
                    message: 'Cancel (Esc)',
                    child: InkWell(
                      onTap: vm.closeInlineSketchDimensionEditor,
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        width: 24,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                ],
              ),
              if (_showTolerance) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tol ±',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 72,
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: TextField(
                        controller: _tolController,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        onSubmitted: (_) => _commitDimension(),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    // 2. COMPACT CONTEXTUAL SKETCH ACTION BAR (When an entity is selected, no bulky modal!)
    final entity = vm.selectedSketchEntity;
    if (entity == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCBD5E1)),
          boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCompactActionChip(
              icon: Icons.power_input_rounded,
              label: entity.isConstruction ? 'Solid (Q)' : 'Construction (Q)',
              isActive: entity.isConstruction,
              onTap: vm.toggleSketchConstructionMode,
            ),
            const SizedBox(width: 4),
            _buildCompactActionChip(
              icon: Icons.straighten_rounded,
              label: 'Dimension (D)',
              isActive: vm.activeSketchTool == 'dimension',
              onTap: () {
                final hitMatch = vm.sketchDimensionHitRects
                    .where((h) => h.primaryEntityId == entity.id)
                    .firstOrNull;
                if (hitMatch != null) {
                  vm.openInlineSketchDimensionEditor(hitMatch);
                } else {
                  vm.setActiveSketchTool('dimension');
                }
              },
            ),
            const SizedBox(width: 4),
            _buildCompactActionChip(
              icon: Icons.layers_rounded,
              label: 'Extrude (E)',
              isActive: vm.isExtrudeMode,
              onTap: vm.toggleExtrudeMode,
            ),
            const SizedBox(width: 4),
            IconButton(
               visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              tooltip: 'Delete Sketch Entity (Del)',
              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
              onPressed: () {
                vm.deleteSelectedSketchEntity();
                widget.onRebuildModel?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactActionChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isActive ? const Color(0xFF0284C7) : const Color(0xFF475569)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isActive ? const Color(0xFF0284C7) : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 6. Step 5: Wire Inline Dimension Editing, 2-Entity Dimensioning & Direct Dragging in `AssemblyStudioViewModel` & `Assembly3DViewport`

### 5.1 Add Inline Dimension & Direct Manipulation Methods to `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`
Add these fields and methods to `AssemblyStudioViewModel` (around line 665 & line 3850 in `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart`):

```dart
// 1. Add fields to AssemblyStudioViewModel (around line 665):
  /// Hit-test rectangles for all dimension tags rendered in the current frame
  final List<SketchDimensionTagHit> sketchDimensionHitRects = [];

  /// Currently open inline floating dimension popover target (image_31d0a3.png)
  SketchDimensionTagHit? activeEditingDimensionHit;
  String? get activeEditingDimensionTagKey => activeEditingDimensionHit?.tagKey;

  /// First clicked entity when using the 2-click Onshape Dimension ('D') tool
  String? dimensionFirstEntityId;

// 2. Add methods to AssemblyStudioViewModel (around line 3880):
  void openInlineSketchDimensionEditor(SketchDimensionTagHit hit) {
    activeEditingDimensionHit = hit;
    notifyListeners();
  }

  void closeInlineSketchDimensionEditor() {
    activeEditingDimensionHit = null;
    dimensionFirstEntityId = null;
    notifyListeners();
  }

  /// Commits an edited value from the floating OnshapeDimensionEditPopover (image_31d0a3.png)
  void commitInlineSketchDimension({
    required SketchDimensionTagHit hit,
    required double newValue,
    String? expression,
    double? tolerancePlusMinus,
  }) {
    if (activeSketchPlane == null) return;
    _recordUndo();

    final primaryKey = hit.subKey != null ? '${hit.primaryEntityId}:${hit.subKey}' : hit.primaryEntityId;
    final entityIds = <String>[
      primaryKey,
      if (hit.secondaryEntityId != null) hit.secondaryEntityId!,
    ];

    if (hit.existingConstraintId != null) {
      final idx = activeSketchPlane!.constraints.indexWhere((c) => c.id == hit.existingConstraintId);
      if (idx != -1) {
        activeSketchPlane!.constraints[idx] = activeSketchPlane!.constraints[idx].copyWith(
          parameterValue: newValue,
          expression: expression,
          tolerancePlus: tolerancePlusMinus,
          toleranceMinus: tolerancePlusMinus,
        );
      }
    } else {
      // Check if a matching dimensional constraint already exists
      final existingIdx = activeSketchPlane!.constraints.indexWhere(
        (c) => c.type == hit.constraintType && c.entityIds.join('|') == entityIds.join('|'),
      );
      if (existingIdx != -1) {
        activeSketchPlane!.constraints[existingIdx] = activeSketchPlane!.constraints[existingIdx].copyWith(
          parameterValue: newValue,
          expression: expression,
          tolerancePlus: tolerancePlusMinus,
          toleranceMinus: tolerancePlusMinus,
        );
      } else {
        activeSketchPlane!.constraints.add(CadConstraint(
          id: 'dim_${DateTime.now().millisecondsSinceEpoch}',
          type: hit.constraintType,
          entityIds: entityIds,
          parameterValue: newValue,
          expression: expression,
          tolerancePlus: tolerancePlusMinus,
          toleranceMinus: tolerancePlusMinus,
        ));
      }
    }

    activeEditingDimensionHit = null;
    dimensionFirstEntityId = null;
    solveSketchConstraints();
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }
```

### 5.2 Position the Floating `OnshapeDimensionEditPopover` & Wire Direct Sketch Dragging in `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart`

1. **Position `AssemblySketchParameterPanel` right at the clicked dimension tag's screen coordinates (`assembly_3d_viewport.dart:3337–3348`):**
```dart
// REPLACE lines 3337-3348 in lib/assembly_studio/views/widgets/assembly_3d_viewport.dart with:
                  if (vm.isSketchMode && (vm.activeEditingDimensionHit != null || vm.selectedSketchEntity != null))
                    Positioned(
                      left: vm.activeEditingDimensionHit != null
                          ? (vm.activeEditingDimensionHit!.screenRect.center.dx - 75.0).clamp(16.0, size.width - 240.0)
                          : (size.width / 2.0 - 160.0),
                      top: vm.activeEditingDimensionHit != null
                          ? (vm.activeEditingDimensionHit!.screenRect.top - 42.0).clamp(56.0, size.height - 100.0)
                          : (size.height - 68.0),
                      child: AssemblySketchParameterPanel(
                        viewModel: vm,
                        onRebuildModel: () {
                          setState(() {});
                          _rebuildGpuCadModel();
                        },
                      ),
                    ),
```

2. **Check `vm.sketchDimensionHitRects` FIRST inside `onPointerDown` when `vm.isSketchMode` is true (`assembly_3d_viewport.dart:1320`) so clicking ANY dimension tag immediately opens the inline popover (`image_31d0a3.png`):**
```dart
// Insert right at line 1321 in lib/assembly_studio/views/widgets/assembly_3d_viewport.dart (inside if (vm.isSketchMode && (event.buttons & kPrimaryMouseButton) != 0)):
                          // 0. Check if the user clicked directly on an Onshape Dimension Tag (image_31d0a3.png)!
                          for (final dimHit in vm.sketchDimensionHitRects.reversed) {
                            if (dimHit.screenRect.contains(event.localPosition)) {
                              vm.openInlineSketchDimensionEditor(dimHit);
                              setState(() {});
                              return;
                            }
                          }
                          if (vm.activeEditingDimensionHit != null) {
                            vm.closeInlineSketchDimensionEditor();
                          }
```

3. **Upgrade `else if (tool == 'dimension')` (`assembly_3d_viewport.dart:1784–1824`) to support both 1-Entity and 2-Entity (Distance `60` & Angle `27°`) Dimensioning + Immediate Inline Popover:**
```dart
// REPLACE lines 1784-1824 in lib/assembly_studio/views/widgets/assembly_3d_viewport.dart with:
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
                                    // If a 1st entity was already clicked for a 2-entity relational dimension:
                                    if (vm.dimensionFirstEntityId != null && vm.dimensionFirstEntityId != hitPrim.id) {
                                      final firstEnt = plane.primitives.where((p) => p.id == vm.dimensionFirstEntityId).firstOrNull;
                                      if (firstEnt != null) {
                                        CadConstraintType relType = CadConstraintType.distance;
                                        double initVal = 25.0;
                                        String unit = 'mm';

                                        if (firstEnt is CADLineEntity && hitPrim is CADLineEntity) {
                                          final d1 = firstEnt.end - firstEnt.start;
                                          final d2 = hitPrim.end - hitPrim.start;
                                          final cross = (d1.dx * d2.dy - d1.dy * d2.dx).abs();
                                          final lenProd = d1.distance * d2.distance;
                                          if (lenProd > 1e-4 && (cross / lenProd) > 0.05) {
                                            // Non-parallel lines -> Angular Dimension (e.g. 27° in image_31d02d.png!)
                                            relType = CadConstraintType.angle;
                                            final dot = (d1.dx * d2.dx + d1.dy * d2.dy) / lenProd;
                                            initVal = math.acos(dot.clamp(-1.0, 1.0)) * 180.0 / math.pi;
                                            unit = 'deg';
                                          } else {
                                            // Parallel lines -> Perpendicular distance
                                            final lLen = d1.distance;
                                            final n = Offset(-d1.dy / lLen, d1.dx / lLen);
                                            initVal = ((hitPrim.start.dx - firstEnt.start.dx) * n.dx + (hitPrim.start.dy - firstEnt.start.dy) * n.dy).abs();
                                          }
                                        } else {
                                          // Point/Circle to Line or Point/Circle to Point/Circle
                                          final c1 = firstEnt is CADCircleEntity ? firstEnt.center : (firstEnt is CADLineEntity ? (firstEnt.start + firstEnt.end) * 0.5 : Offset.zero);
                                          final c2 = hitPrim is CADCircleEntity ? hitPrim.center : (hitPrim is CADLineEntity ? (hitPrim.start + hitPrim.end) * 0.5 : Offset.zero);
                                          initVal = (c2 - c1).distance;
                                        }

                                        final newConstraint = CadConstraint(
                                          id: 'dim_${DateTime.now().millisecondsSinceEpoch}',
                                          type: relType,
                                          entityIds: [firstEnt.id, hitPrim.id],
                                          parameterValue: initVal,
                                        );
                                        plane.constraints.add(newConstraint);
                                        vm.dimensionFirstEntityId = null;
                                        vm.solveSketchConstraints();
                                        vm.openInlineSketchDimensionEditor(SketchDimensionTagHit(
                                          tagKey: newConstraint.id,
                                          screenRect: Rect.fromCenter(center: event.localPosition, width: 60, height: 24),
                                          primaryEntityId: firstEnt.id,
                                          secondaryEntityId: hitPrim.id,
                                          constraintType: relType,
                                          existingConstraintId: newConstraint.id,
                                          currentValue: initVal,
                                          unitSuffix: unit,
                                        ));
                                        setState(() {});
                                        return;
                                      }
                                    }

                                    // 1st click on an entity: apply driving dimension & open inline popover immediately,
                                    // while also recording dimensionFirstEntityId in case the user clicks a 2nd entity!
                                    vm.dimensionFirstEntityId = hitPrim.id;
                                    vm.selectSketchPrimitive(hitPrim);
                                    final double currentVal = hitPrim is CADCircleEntity
                                        ? hitPrim.radius * 2.0
                                        : hitPrim is CADLineEntity
                                            ? (hitPrim.end - hitPrim.start).distance
                                            : hitPrim is CADRectangleEntity
                                                ? hitPrim.width
                                                : hitPrim is CADCenterRectangleEntity
                                                    ? hitPrim.width
                                                    : 20.0;
                                    final dimType = hitPrim is CADCircleEntity
                                        ? CadConstraintType.diameter
                                        : (hitPrim is CADArcEntity || hitPrim is CADCenterPointArcEntity)
                                            ? CadConstraintType.radius
                                            : CadConstraintType.distance;
                                    vm.applyDrivingSketchDimension(
                                      entityId: hitPrim.id,
                                      valueMmOrDeg: currentVal,
                                    );
                                    final createdConstraint = plane.constraints.lastOrNull;
                                    vm.openInlineSketchDimensionEditor(SketchDimensionTagHit(
                                      tagKey: createdConstraint?.id ?? hitPrim.id,
                                      screenRect: Rect.fromCenter(center: event.localPosition, width: 60, height: 24),
                                      primaryEntityId: hitPrim.id,
                                      constraintType: dimType,
                                      existingConstraintId: createdConstraint?.id,
                                      currentValue: currentVal,
                                    ));
                                    setState(() {});
                                  } else {
                                    vm.dimensionFirstEntityId = null;
                                  }
                                  return;
                                }
```

4. **Add Automatic `Horizontal (H)` / `Vertical (V)` Constraint Inference When Drawing Lines (`assembly_3d_viewport.dart:1447–1461`):**
```dart
// In lib/assembly_studio/views/widgets/assembly_3d_viewport.dart (lines 1447-1461):
                                  final pStart = vm.sketchInteractiveStartPoint!;
                                  if ((snapped - pStart).distance > 0.1) {
                                    Offset finalEnd = snapped;
                                    CadConstraintType? autoDirConstraint;
                                    final dx = (snapped.dx - pStart.dx).abs();
                                    final dy = (snapped.dy - pStart.dy).abs();
                                    if (dy < dx * 0.06) {
                                      finalEnd = Offset(snapped.dx, pStart.dy);
                                      autoDirConstraint = CadConstraintType.horizontal;
                                    } else if (dx < dy * 0.06) {
                                      finalEnd = Offset(pStart.dx, snapped.dy);
                                      autoDirConstraint = CadConstraintType.vertical;
                                    }
                                    final newLine = CADLineEntity(
                                      id: 'line_${DateTime.now().millisecondsSinceEpoch}',
                                      start: pStart,
                                      end: finalEnd,
                                      isConstruction: vm.isSketchConstructionMode,
                                    );
                                    vm.addPrimitiveEntityToActivePlane(newLine);
                                    if (autoDirConstraint != null) {
                                      plane.constraints.add(CadConstraint(
                                        id: 'auto_${autoDirConstraint.name}_${newLine.id}',
                                        type: autoDirConstraint,
                                        entityIds: [newLine.id],
                                      ));
                                      vm.solveSketchConstraints();
                                    }
                                    // Continuous chaining: next segment starts where current finished
                                    vm.setInteractiveSketchStart(finalEnd);
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
```

5. **Add Direct On-Plane Dragging for Sketch Entities, Endpoints & Circle Radii (`assembly_3d_viewport.dart`):**
   - Add fields to `Assembly3DViewportState`:
     ```dart
     CADPrimitiveEntity? _draggingSketchPrimitive;
     String _draggingSketchPartRole = 'body'; // 'center', 'rim', 'start', 'end', 'body'
     Offset? _sketchDragLastLocal;
     ```
   - When `hitPrimitive != null` in `onPointerDown` (`line 1888`), initialize `_draggingSketchPrimitive = hitPrimitive; _sketchDragLastLocal = localPoint;` and detect whether the click was near `center`, `rim`, `start`, or `end`:
     ```dart
     _draggingSketchPrimitive = hitPrimitive;
     _sketchDragLastLocal = localPoint;
     if (hitPrimitive is CADCircleEntity) {
       _draggingSketchPartRole = (localPoint - hitPrimitive.center).distance <= 6.0 ? 'center' : 'rim';
     } else if (hitPrimitive is CADLineEntity) {
       if ((localPoint - hitPrimitive.start).distance <= 6.0) {
         _draggingSketchPartRole = 'start';
       } else if ((localPoint - hitPrimitive.end).distance <= 6.0) {
         _draggingSketchPartRole = 'end';
       } else {
         _draggingSketchPartRole = 'body';
       }
     } else {
       _draggingSketchPartRole = 'body';
     }
     ```
   - Inside `onPointerMove` (`line 2185`), when `vm.isSketchMode && _draggingSketchPrimitive != null && (event.buttons & kPrimaryMouseButton) != 0`:
     ```dart
     if (vm.isSketchMode && _draggingSketchPrimitive != null && vm.activeSketchPlane != null && (event.buttons & kPrimaryMouseButton) != 0) {
       final plane = vm.activeSketchPlane!;
       final currLocal = _unprojectScreenToPlane(event.localPosition, plane, size, mesh);
       if (currLocal != null && _sketchDragLastLocal != null) {
         final delta = currLocal - _sketchDragLastLocal!;
         _sketchDragLastLocal = currLocal;
         final prim = _draggingSketchPrimitive!;
         if (!prim.isFullyConstrained) {
           if (prim is CADCircleEntity) {
             if (_draggingSketchPartRole == 'center') {
               prim.center += delta;
             } else {
               prim.radius = (currLocal - prim.center).distance.clamp(1.0, 5000.0);
             }
           } else if (prim is CADLineEntity) {
             if (_draggingSketchPartRole == 'start') {
               prim.start = currLocal;
             } else if (_draggingSketchPartRole == 'end') {
               prim.end = currLocal;
             } else {
               prim.start += delta;
               prim.end += delta;
             }
           } else if (prim is CADRectangleEntity) {
             prim.startPoint += delta;
           } else if (prim is CADCenterRectangleEntity) {
             prim.center += delta;
           }
           vm.solveSketchConstraints();
           vm.activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(plane);
           vm.notifyDocChanged();
           setState(() {});
         }
       }
       return;
     }
     ```
   - And reset `_draggingSketchPrimitive = null; _sketchDragLastLocal = null;` in `onPointerUp` (`line 2281`).

---

## 7. Step 6: Upgrade `AssemblyExtrudeDialog` to Match Onshape's `Extrude` Dialog (`image_31d127.png`)

In `lib/assembly_studio/views/widgets/viewport/overlays/assembly_extrude_dialog.dart`, add:
1. **Top Domain Tabs (`Solid` | `Surface` | `Thin`)** right below the header bar (`image_31d127.png`).
2. **Boolean Operation Tabs (`New` | `Add` | `Remove` | `Intersect`)** styled as Onshape's segmented tab bar.
3. **`Faces and sketch regions to extrude` Box:** Displays `Face of ${plane?.name ?? 'Sketch 1'}` with the blue active left border and clear (`×`) button.
4. **`End type` Dropdown (`Blind`, `Through all`, `Up to next`, `Up to face`, `Up to vertex`)** + **Flip Direction (`⇄`) Icon Button** right next to the `Depth` input field (`25 mm`)!

```dart
// Add to _AssemblyExtrudeDialogState in lib/assembly_studio/views/widgets/viewport/overlays/assembly_extrude_dialog.dart:
  int _domainTabIndex = 0; // 0 = Solid, 1 = Surface, 2 = Thin
  String _endType = 'Blind'; // 'Blind', 'Through all', 'Up to next', 'Up to face', 'Up to vertex'
```

And inside the `AssemblyExtrudeDialog` body (`lines 150–345` of `assembly_extrude_dialog.dart`), render:
- The `Solid | Surface | Thin` tab row
- The `New | Add | Remove | Intersect` row
- The `Faces and sketch regions to extrude` card showing `Face of ${plane?.name ?? 'Sketch 1'}`
- The `End type` dropdown (`Blind` vs `Through all`) and the `Depth` row with the **Flip Direction (`Icons.swap_horiz_rounded`)** button that negates `params.distanceMm` (`vm.updateExtrudeDistance(-params.distanceMm)`) in 1 click!

---

## 8. Final Verification Checklist for the Coding Agent

- [ ] **Camera `'N'` Shows the Front of the Sketching Face (`assembly_3d_viewport.dart:445–448` & `369–387`):** `_updateGpuCamera` uses `d = Vector3(m[8], m[9], m[10])` and `up = Vector3(m[4], m[5], m[6])` (eliminating the Y/Z axis swap), and `_rebuildGpuCadModel` tracks `_lastCameraPivot` so pressing `'N'` (or clicking `Normal (N)`) centers and orients the camera flat to any Top, Web, Side, or Angled sketch face.
- [ ] **Authentic Onshape CAD Dimension Annotations (`assembly_3d_surface_sketch_painter.dart`):** Linear, Diameter (`Ø`), Radius (`R`), and Angular (`27°`) dimensions render with extension/witness lines, leader lines, filled CAD arrowheads, and clickable white dimension tags (`image_31d02d.png`).
- [ ] **1-Click Floating Inline Dimension Popover (`assembly_sketch_parameter_panel.dart`):** Clicking any dimension tag opens the compact floating `OnshapeDimensionEditPopover` right over that tag with pre-selected value (`60 mm`), `±` tolerance toggle, green `✓` (`Enter`), and red `✕` (`Esc`) (`image_31d0a3.png`), replacing the clunky `CIRCLE PARAMETERS` modal (`image_31c8cd.jpg`).
- [ ] **2-Entity Relational Dimensioning & Direct Sketch Dragging (`assembly_3d_viewport.dart` & `assembly_sketch_constraint_solver.dart`):** Clicking two lines with `D` creates an Angular (`27°`) or Parallel Distance (`10`) dimension; clicking a circle/point and a line creates a linear offset dimension (`65`); and dragging unconstrained vertices, circle centers, or circle rims updates the sketch at 60 FPS.
- [ ] **Onshape `Extrude` Workflow (`assembly_extrude_dialog.dart`):** Includes `Solid | Surface | Thin` tabs, `New | Add | Remove | Intersect` operations, `Faces and sketch regions to extrude`, `Blind` / `Through all` end types, Flip Direction (`⇄`), and the live 3D depth arrow manipulator (`image_31d127.png`).
