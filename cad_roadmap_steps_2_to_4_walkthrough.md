flutter # CAD Studio: Implementation Blueprint & Walkthrough for Steps 2, 3 & 4

**Target Audience:** Autonomous Coding Agent / Pair Programmer  
**Context:** TruFold Studio (Danish FormMatrix Studio) Phase 1 Implementation  
**Status:** Step 1 (DSF Schema v2.0 Serialization) & SS1 (Fusion 360 Sketch View Redesign) are **COMPLETED**. This document specifies the precise technical roadmap, file paths, class signatures, algorithms, and testing matrices for **Step 2, Step 3, and Step 4**.

---

## Roadmap Overview

| Step | SET Ref | Title | Core Focus | Key Target Files |
| :--- | :--- | :--- | :--- | :--- |
| **Step 1** | **SET 22** | **DSF Schema v2.0 Serialization** | ✅ **COMPLETED** — Full round-trip JSON serialization for `constraintDefinitions`, `referenceGeometries`, and `templateParameters`. | [dsf_document.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/models/dsf_document.dart) |
| **Step 2** | **SET 17 & 19** | **Multi-Branch Contour Solving (Tees & Reducers)** | Extend `GeometricConstraintSolver` from simple rectangular bounds to multi-branch polyline contours (T-shapes, crosses, tapered reducers) via topological zones. | [geometric_constraint_solver.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/engine/constraints/geometric_constraint_solver.dart)<br>[topological_zone_morpher.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/engine/topological_zone_morpher.dart) |
| **Step 3** | **SET 12** | **Pattern Parameter DAG Binding** | Connect `PerforationPattern` properties (`pitchX`, `pitchY`, `countX`, `countY`) to named parameters and mathematical expressions in `DependencyGraphEngine`. | [perforation_pattern.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/models/perforation_pattern.dart)<br>[dependency_graph_engine.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/engine/constraints/dependency_graph_engine.dart)<br>[pattern_property_sheet.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/views/widgets/pattern_property_sheet.dart) |
| **Step 4** | **SET 13 & 23** | **Template Authoring Wizard & Library Gallery** | Build a guided 4-step "Author Template" modal workflow and visual template catalog gallery dialog with pre-bundled catalog presets. | [template_authoring_wizard_dialog.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/views/widgets/template_authoring_wizard_dialog.dart)<br>[template_library_gallery_dialog.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/views/widgets/template_library_gallery_dialog.dart)<br>[product_catalog_service.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/services/product_catalog_service.dart) |

---

## STEP 2: Multi-Branch Contour Solving for Unequal Tee & Reducer (SET 17 & 19)

### 1. Problem Statement
In `GeometricConstraintSolver._applyDistance`, boundary outer contour solving currently performs simple 1D bounding box scaling:
```dart
// Current rectangular boundary solving in geometric_constraint_solver.dart:
if ((idA == 'EDGE_LEFT' && idB == 'EDGE_RIGHT') || ...) {
  final scaleFactor = targetValue / currentWidth;
  for (int i = 0; i < workingContour.length; i++) {
    final newX = minX + (pt.x - minX) * scaleFactor;
    workingContour[i] = CadPoint2D(newX, pt.y);
  }
}
```
**Why this breaks for Cable Tray Fittings:**
- **Unequal Tee (`SET 17`)**: Has 3 distinct ports (`W1xH1` Main Run In, `W2xH2` Main Run Out, `W3xH3` Branch Run). Uniform scaling stretches the branch neck, shifts flange bend lines erroneously, and distorts the corner relief miters and coupler punch clusters!
- **Reducer (`SET 19`)**: Has 2 ports (`W_IN`, `W_OUT`) with an angled transition taper. Box scaling distorts the taper angle and changes wall flange heights instead of tapering the bed.

### 2. Architectural Design & Implementation Details

#### A. Contour Topology Classification
Create a dedicated classification utility:
`lib/sheet_metal_studio/engine/constraints/contour_topology_classifier.dart`
```dart
enum ContourTopologyType {
  rectangular,     // Straight cable tray, covers, flat plates
  tBranch,         // Equal & Unequal Tee (3 ports, 12-16 vertices)
  crossBranch,     // Equal & Unequal Cross (4 ports, 16-20 vertices)
  taperedReducer,  // Concentric / Eccentric Reducer (2 ports with angled transition)
  lBend,           // 90° and 45° flat bends
  arbitraryPoly,   // General irregular sheet metal polygon
}

class ContourTopologyClassifier {
  static ContourTopologyType classify(List<CadPoint2D> contour, List<FoldBendLine> bends);
}
```

#### B. Topological Zone Rules in `GeometricConstraintSolver`
In [geometric_constraint_solver.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/engine/constraints/geometric_constraint_solver.dart):
When resolving `CadConstraintType.distance` on boundary edges:
1. **Identify Topology Type**: If `tBranch` or `taperedReducer`:
2. **Unequal Tee Solving**:
   - **Parameter `MAIN_WIDTH` (or distance between Run Bottom & Run Top edges)**:
     - Displaces vertical branch vertices upward by `dW = newMainWidth - oldMainWidth`.
     - Translates horizontal branch bend lines and coupler punches within the upper zone by `dW`.
     - Preserves flange wall height (`H`) and corner relief miters.
   - **Parameter `BRANCH_WIDTH` (or distance across Branch Left & Branch Right edges)**:
     - Displaces right arm vertices horizontally by `dBw = newBranchWidth - oldBranchWidth`.
     - Translates right run bend lines and coupler punch clusters by `dBw`.
     - Keeps the left throat fillet and right throat fillet rigid without distortion.
3. **Reducer Solving**:
   - **Parameter `LENGTH`**: Expands transition along X axis (`x += dL * tx`).
   - **Parameters `WIDTH_A` (entry) and `WIDTH_B` (exit)**:
     - Computes normalized longitudinal ratio `tx = (pt.x - minX) / length`.
     - Calculates local width delta: `localDeltaW = dWA * (1.0 - tx) + dWB * tx`.
     - Symmetrically displaces top/bottom contour vertices: `y += (pt.y > midY ? 1 : -1) * (localDeltaW / 2.0)`.
     - Flange bend lines adjust angle/offset to match tapered bed contour while preserving strict flange wall height (`H`).
4. **Recomposition**:
   - Re-decomposes planar faces using `PlanarFaceDecomposer.decompose()` and updates the 3D folded mesh so the 3D viewport instantly reflects the morphed fitting!

### 3. Verification Plan for Step 2
Create unit test: `test/modules/sheet_metal_studio/multi_branch_contour_solver_test.dart`
- **Test 1**: Unequal Tee `100x50x100` $\to$ `300x50x150`. Verify that branch opening is exactly 150mm, main run is 300mm, flange heights remain 50mm, and coupler punches retain 25mm spacing.
- **Test 2**: Reducer `150x50x100` $\to$ `200x50x50`. Verify port A is 200mm, port B is 50mm, and taper transition edges are straight.
- **Test 3**: Over-constrained and conflict detection when user dimensions contradict blank geometry.

---

## STEP 3: Pattern Parameter DAG Binding (SET 12)

### 1. Problem Statement
In cable tray manufacturing, perforation patterns must respond dynamically to parameter changes:
- If tray `WIDTH` changes from `100mm` $\to$ `300mm`, the number of slot columns (`countX`) should increase automatically (e.g. `2 columns` $\to$ `6 columns`).
- If tray `LENGTH` changes from `1000mm` $\to$ `3000mm`, slot rows (`countY`) should scale to fill the bed.
- Currently, `PerforationPattern` has static numbers (`countX: 2, countY: 50, pitchX: 25.0, pitchY: 50.0`). They are not yet bound associatively to named expressions in `DependencyGraphEngine`.

### 2. Architectural Design & Implementation Details

#### A. Model Extension: `PerforationPattern`
In [perforation_pattern.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/models/perforation_pattern.dart):
Add expression binding properties:
```dart
class PerforationPattern {
  ...
  // Dynamic formula expressions (optional)
  final String? countXExpression;     // e.g. "floor((WIDTH - 2 * MARGIN) / PITCH_X)"
  final String? countYExpression;     // e.g. "floor((LENGTH - 2 * MARGIN) / PITCH_Y)"
  final String? pitchXParameter;      // e.g. "PITCH_X"
  final String? pitchYParameter;      // e.g. "PITCH_Y"
  final String? marginParameter;      // e.g. "EDGE_MARGIN"
```
Update `toJson()`, `fromJson()`, and `copyWith()`.

#### B. DAG Registration & Cycle Detection
In [dependency_graph_engine.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/engine/constraints/dependency_graph_engine.dart):
1. Register pattern node: `pattern:<patternId>` with `DependencyNodeType.pattern`.
2. Parse variable dependencies using `ExpressionParserEngine.extractVariables(countXExpression)`.
3. Add directed dependency edges:
   ```text
   WIDTH  ──┐
   MARGIN ──┼──> pattern:Pattern_Floor ──> punches:Holes ──> mesh3d
   PITCH_X──┘
   ```
4. Check for circular feedback via `wouldCreateCycle(sourceId, dependentId)`.

#### C. Topological Recalculation in ViewModel
In `sheet_metal_studio_viewmodel.dart`:
When any parameter in `document.parameters` changes:
1. `DependencyGraphEngine.getTopologicalRecalculationOrder()` identifies dirty pattern nodes.
2. Evaluates the formula using `ExpressionParserEngine.evaluate(expr, parameters)`.
3. Updates `pattern.copyWith(countX: newCountX, countY: newCountY, pitchX: newPitchX, ...)`.
4. Re-nests punches via `pattern.generatePunches()`, ensuring punches adhere to CAM clearance rules (minimum distance from bend lines and edges).

#### D. UI Property Sheet Enhancement
In [pattern_property_sheet.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/views/widgets/pattern_property_sheet.dart):
- Add a formula toggle icon button (`fx`) next to Pitch X/Y and Hole Count fields.
- Clicking `fx` allows the designer to enter either a fixed numeric value or a CAD variable expression (e.g. `PITCH_X`, `floor((WIDTH - 40) / 25)`).

### 3. Verification Plan for Step 3
Create unit test: `test/modules/sheet_metal_studio/pattern_dag_binding_test.dart`
- **Test 1**: Bind `countX` to `floor((WIDTH - 40) / 25)`. Morphing `WIDTH` from 100 to 200 recalculates `countX` from 2 to 6 columns.
- **Test 2**: Bind `pitchY` to parameter `PITCH_Y`. Changing parameter live-updates array pitch on canvas.
- **Test 3**: Circular dependency protection: attempting to set `WIDTH = countX * PITCH_X` while `countX` depends on `WIDTH` throws `CircularDependencyException`.

---

## STEP 4: Template Authoring Wizard & Library Gallery (SET 13 & 23)

### 1. Problem Statement
To fulfill the long-term vision of **"Do not create thousands of static DXF files for every dimensional variation. Create intelligent templates"**:
Users need:
1. A **guided 4-step wizard** that turns any imported flat DXF into a reusable parametric template without manual code editing.
2. A **visual template gallery** where pre-bundled catalog fittings (cable trays, tees, reducers, crosses, trunking) can be browsed with 2D previews and instantiated with custom dimensions.

### 2. Architectural Design & Implementation Details

#### A. Guided Template Authoring Wizard (`TemplateAuthoringWizardDialog`)
Create: `lib/sheet_metal_studio/views/widgets/template_authoring_wizard_dialog.dart`
- **Step 1: Classification & Metadata**:
  - Name, Product Category (`Cable Tray`, `Cover`, `Fitting`, `Trunking`), Variant (`Straight`, `Tee`, `Reducer`, `Bend`, `Cross`, `Custom`).
  - Sheet metal rules: default material (GI, Aluminum, SS), thickness limits.
- **Step 2: Reference & Port Identification**:
  - Interactive selection on canvas for Entry Port 1, Exit Port 2, Branch Port 3.
  - Automatic detection of centerlines (`CENTER_X`, `CENTER_Y`) and bounding reference edges.
- **Step 3: Parameter & Constraint Assignment**:
  - Primary driving dimensions: `WIDTH`, `HEIGHT`, `LENGTH`, `BRANCH_WIDTH`, `RADIUS`.
  - Topological zones: defines rigid zones (coupler tabs, throat miters) vs expandable zones.
- **Step 4: Review, Validation & Save**:
  - Validates template under 3 test dimensions (nominal, minimum, maximum).
  - Saves as `TemplateParameterDefinition` in `.dsf` or exportable template JSON.

#### B. Visual Template Catalog Gallery (`TemplateLibraryGalleryDialog`)
Create: `lib/sheet_metal_studio/views/widgets/template_library_gallery_dialog.dart`
- Card grid gallery displaying pre-bundled factory presets from [product_catalog_service.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/services/product_catalog_service.dart):
  - Straight Cable Tray (`CT-100x50x3000`)
  - Cable Tray Equal & Unequal Tee (`CT-Tee-100x50x100`)
  - Cable Tray Reducer (`CT-Reducer-150x50x100`)
  - 90° & 45° Flat Bends
  - Straight Trunking & Trunking Tee
- **Features**:
  - Category tabs (`All`, `Cable Trays`, `Fittings`, `Covers`, `Trunking`).
  - Search bar filtering by name or dimension.
  - Interactive dimension sliders (`Width`, `Height`, `Length`).
  - Live 2D vector preview of the selected fitting.
  - "Instantiate in New Tab" button loading the generated part directly into `SheetMetalStudioScreen`.

#### C. Fusion Ribbon Toolbar Integration
In [fusion_ribbon_toolbar.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/views/widgets/fusion/fusion_ribbon_toolbar.dart):
- Under `INSERT ▾` menu: Add `Template Library...` (opens gallery).
- Under `CREATE ▾` menu: Add `Author Template from DXF...` (opens wizard).

### 3. Verification Plan for Step 4
Create widget test: `test/modules/sheet_metal_studio/template_authoring_and_gallery_test.dart`
- **Test 1**: Authoring Wizard navigates all 4 steps, accepts edge selections, and produces valid `TemplateParameterDefinition`.
- **Test 2**: Template Gallery renders catalog cards, filters by category, and instantiates a new document in the studio.
- **Test 3**: Sliders in the gallery live-regenerate the thumbnail preview without errors.

---

## Complete Test & Verification Command Reference

```powershell
# 1. Run all sheet metal studio unit and widget tests
cmd.exe /c "F:\flutter\bin\flutter.bat test test\modules\sheet_metal_studio"

# 2. Run static analysis (must remain at 0 issues)
& "F:\flutter\bin\cache\dart-sdk\bin\dart.exe" analyze lib/sheet_metal_studio test/modules/sheet_metal_studio

# 3. Targeted test execution examples
cmd.exe /c "F:\flutter\bin\flutter.bat test test\modules\sheet_metal_studio\dsf_schema_v2_test.dart"
cmd.exe /c "F:\flutter\bin\flutter.bat test test\modules\sheet_metal_studio\geometric_constraint_solver_test.dart"
cmd.exe /c "F:\flutter\bin\flutter.bat test test\modules\sheet_metal_studio\dependency_graph_and_expressions_test.dart"
cmd.exe /c "F:\flutter\bin\flutter.bat test test\modules\sheet_metal_studio\sheet_metal_studio_screen_test.dart"
```

---

## Summary Checklist & Completion Status

- [x] **Step 1**: DSF Schema v2.0 Serialization & Backward Compatibility (**COMPLETED & VERIFIED**).
- [x] **SS1**: Autodesk Fusion 360 Sketch View Redesign (**COMPLETED & VERIFIED**).
- [x] **Step 2**: Implement `ContourTopologyClassifier` and multi-branch contour solving in `GeometricConstraintSolver` for Unequal Tee and Reducer (**COMPLETED & VERIFIED**).
  - Implemented `ContourTopologyClassifier` detecting rectangular, tee, cross, reducer, and complex polyline topologies.
  - Implemented `_applyDistanceTee` and `_applyDistanceReducer` in `GeometricConstraintSolver` with exact throat relief angles, wall heights ($H$), and rigid coupler punch clusters preservation.
  - Verified with 4 unit tests in `multi_branch_contour_solver_test.dart` (100% passing).
- [x] **Step 3**: Bind `PerforationPattern` dynamic properties to `DependencyGraphEngine` formulas and DAG dirty propagation (**COMPLETED & VERIFIED**).
  - Extended `PerforationPattern` with `formulaCountX`, `formulaCountY`, `paramPitchX`, `paramPitchY`.
  - Added math functions (`floor`, `ceil`, `round`, `abs`, `sqrt`, `min`, `max`) to `ExpressionParserEngine`.
  - Extended `DependencyGraphEngine` with pattern registration and expression re-evaluation.
  - Wired `recalculatePatternsFromParameters` into `TopologicalZoneMorpher` and `SheetMetalStudioViewModel`.
  - Added `fx` formula binding inputs and toggles into `PatternPropertySheet`.
  - Verified with 5 unit tests in `pattern_dag_binding_test.dart` (100% passing).
- [x] **Step 4**: Build `TemplateAuthoringWizardDialog` and `TemplateLibraryGalleryDialog`, and wire them into `FusionRibbonToolbar` (**COMPLETED & VERIFIED**).
  - Built guided 4-step `TemplateAuthoringWizardDialog` with Port Schematic live painter, zone configuration, and 3-point validation.
  - Built `TemplateLibraryGalleryDialog` visual catalog gallery with category filtering, dimension sliders, 2D vector preview, and direct studio instantiation.
  - Wired into `FusionRibbonToolbar` under `INSERT -> Template Library...` and `CREATE -> Author Tpl`.
  - Verified with 3 widget tests in `template_authoring_and_gallery_test.dart` (100% passing).
