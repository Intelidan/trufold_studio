# Implementation Plan: Delete Key Selection, Full-Screen Properties Panel, First-Class Arcs, Void Cutout Cleaning, Unsaved Tab Prompt, and Boundary Arc Sync

## Goal Description
Address 6 core functional and UX improvements across truFold Studio:
1. **Delete Key Support**: Pressing the `Delete` (or `Backspace`) key deletes any selected object(s), including punches, cut lines, bends, arcs, perforation patterns, dimensions, constraints, and multi-selection boxes.
2. **Full-Screen Properties Panel**: Enable the floating `CadPropertyInspector` to move across the entire screen, including over the split divider and 3D viewport, by lifting it into the root workspace Stack.
3. **Eliminate Duplicate Border Cut Lines**: When a closed rectangle or closed polyline is created, eliminate redundant `CadLineSegment` cut lines (`CUT C1..Cn`) around the perimeter so that it functions cleanly like a circle cutout void.
4. **First-Class 3-Point Arc Entity**: When drawing an arc with 3 points, instantiate a first-class `CadArc2D` entity in `document.arcs` with full property editing (radius, center, start/end angles) instead of discretizing it into 8 separate line segments (`CUT C1..C8`).
5. **Unsaved Edits Close Confirmation**: Prompt the user with a "Save", "Don't Save", or "Cancel" dialog when closing a file/tab if unsaved edits have been made.
6. **DXF Boundary Arc Normalization & Contour Sync**:
   - Normalize arc angles so unnormalized angles like `540.0°` and `630.0°` display and edit cleanly as `180.0°` and `270.0°`.
   - When updating a boundary arc, synchronize the outer boundary contour (`_document.outerContour`) so the contour vertices follow the arc curve rather than detaching or reverting to a straight chord line.

---

## User Review Required
> [!NOTE]
> - For Item 2 (Properties Panel over 3D View), the inspector position will be stored at the screen level and clamped to the total workspace width/height, allowing the user to place it anywhere on top of either the 2D canvas, 3D viewport, or across the center split divider.
> - For Item 5 (Unsaved Edits Dialog), if "Save" is chosen, the file will be saved and then closed. If "Don't Save" is chosen, the tab will close immediately. If "Cancel" is chosen, the tab will remain open.

---

## Proposed Changes

### Component 1: ViewModel Enhancements & Entity Architecture
#### [MODIFY] [sheet_metal_studio_viewmodel.dart](file:///d:/FlutterProjects/trufold_studio/lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart)
- **Item 1: Comprehensive Selection Deletion (`deleteSelectedEntities`)**:
  - Include `_selectedArcId`, `_selectedPatternId`, `_selectedDimensionId`, `_selectedConstraintId`, and all IDs in `_selectedEntityIds`.
  - Filter `_document.arcs`, `_document.perforationPatterns`, `_document.dimensions`, and `_document.constraints` to remove targeted IDs.
  - Reset selected ID states (`_selectedArcId = null`, `_selectedPatternId = null`, etc.) and call `_recomputeMesh()` and `notifyListeners()`.
- **Item 3: Remove Redundant Cut Lines in `addClosedCutoutVoid`**:
  - In `addClosedCutoutVoid(List<CadPoint2D> polygon)`: remove the loop adding duplicate `CadLineSegment` cut lines `C1..Cn` into `newCuts`. The cutout is already represented by `voidPunch` and `faces.holes`.
- **Item 4: First-Class Arc Entity Creation (`addArcEntity`)**:
  - Create `addArcEntity(CadPoint2D p1, CadPoint2D p2, CadPoint2D p3)` that instantiates `CadArc2D.from3Points(...)`, appends to `_document.arcs`, sets `_selectedArcId = arcId`, and opens the inspector.
  - In `handleCanvasClick` for `StudioToolMode.drawArc`, replace `addArcCut(p1, p2, p3)` with `addArcEntity(p1, p2, p3)`.
- **Item 5: Modification State Tracking**:
  - Add `bool _isModified = false;`, getter `bool get isModified => _isModified;`, `void markClean()`, and `void markModified()`.
  - In `recordHistory()`, set `_isModified = true`.
- **Item 6: Boundary Arc Contour Synchronization in `updateArc`**:
  - In `updateArc(CadArc2D updated)`: if `updated.isBoundary` or if the old arc matched points in `_document.outerContour`, locate the contour vertices matching `oldArc.startPoint` and `oldArc.endPoint`, and replace them with `updated.startPoint` and `updated.endPoint` (or the updated curve points).
  - This ensures `buildSmoothPolygonPath` in 2D and polygon triangulation in 3D continue to recognize the arc along the boundary contour without detaching.

---

### Component 2: Geometry Models & Angle Normalization
#### [MODIFY] [cad_geometry.dart](file:///d:/FlutterProjects/trufold_studio/lib/sheet_metal_studio/models/cad_geometry.dart)
- In `CadArc2D`:
  - Add static helper `normalizeAngleDeg(double deg) => (deg % 360.0 + 360.0) % 360.0;`.
  - In constructor and getters, normalize `startAngleDeg` and `endAngleDeg` to `[0, 360)`.
  - Ensure `_calcSweepRad` operates on normalized angles so sweep angles are always calculated reliably.

#### [MODIFY] [dxf_geometry_recognition_engine.dart](file:///d:/FlutterProjects/trufold_studio/lib/sheet_metal_studio/engine/dxf_geometry_recognition_engine.dart)
- In `DxfGeometryRecognitionEngine`:
  - Normalize start and end angles of raw DXF arcs when creating `CadArc2D` entities (`ARC_BND_...` and `CUT_ARC_...`).

#### [MODIFY] [arc_property_sheet.dart](file:///d:/FlutterProjects/trufold_studio/lib/sheet_metal_studio/views/widgets/arc_property_sheet.dart)
- In `ArcPropertySheet`:
  - Initialize `_startAngleCtrl` and `_endAngleCtrl` using normalized angles (`CadArc2D.normalizeAngleDeg`).
  - In `_applyChanges()`, normalize user input angles before constructing the updated arc.

---

### Component 3: Screen & Canvas Keybindings & Properties Panel
#### [MODIFY] [sheet_metal_studio_screen.dart](file:///d:/FlutterProjects/trufold_studio/lib/sheet_metal_studio/views/sheet_metal_studio_screen.dart)
- **Item 1: Keyboard Shortcuts**:
  - Add `const SingleActivator(LogicalKeyboardKey.delete): _handleDeleteKey,` and `const SingleActivator(LogicalKeyboardKey.backspace): _handleDeleteKey,` calling `_viewModel.deleteSelectedEntities()`.
- **Item 2: Full-Screen Floating Properties Panel**:
  - In `UnfoldedCanvasWidget`, pass `renderFloatingInspectors: false`.
  - In `_SheetMetalStudioScreenState`, maintain `Offset _inspectorPosition = const Offset(320, 80);`.
  - In the main `Stack` of `SheetMetalStudioScreen`, render `CadPropertyInspector` directly, allowing dragging anywhere across `totalW` and `totalH` over the 3D viewport.
- **Item 5: Unsaved Edits Tab Close Prompt**:
  - In `_handleCloseTab(int index)`:
    - If `_tabs[index].isModified || _tabs[index].viewModel.isModified`, display an `AlertDialog` with "Save", "Don't Save", and "Cancel".
    - If "Save", call `_handleSaveActiveFile()`, then proceed to remove and dispose tab.
    - If "Don't Save", proceed to remove and dispose tab.
    - If "Cancel", abort without closing.

#### [MODIFY] [unfolded_canvas_widget.dart](file:///d:/FlutterProjects/trufold_studio/lib/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart)
- In `onKeyEvent`:
  - On `LogicalKeyboardKey.delete` or `LogicalKeyboardKey.backspace`, call `viewModel.deleteSelectedEntities()`.

---

## Verification Plan

### Automated Tests
- Run existing and new test suites:
  ```powershell
  flutter test test/modules/sheet_metal_studio/
  ```
- Add test coverage in `test/modules/sheet_metal_studio/studio_enhancements_test.dart`:
  1. `deleteSelectedEntities()` deletes arcs, cut lines, punches, and patterns.
  2. `addCutRectangle()` creates only `voidPunch` and does NOT generate duplicate cut lines `CUT C1..Cn`.
  3. `drawArc` creates a first-class `CadArc2D` entity in `_document.arcs` with editable radius and center.
  4. `CadArc2D` normalizes `540.0°` to `180.0°` and `630.0°` to `270.0°`.
  5. `updateArc()` on boundary arc updates `_document.outerContour` coordinates to prevent detachment.
  6. ViewModel tracks `isModified` when edits are made and cleans it on `markClean()`.

### Static Analysis
- Run `flutter analyze lib/ test/` to verify zero analyzer warnings or errors.
