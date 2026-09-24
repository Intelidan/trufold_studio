# TruFold Studio - Trunking Accessory Covers
## Template, Parametric Scaling, 2D/3D Presentation, DSF Integration & Export

## 1. Purpose

Extend the completed **Cable Trunking Accessories base-part templating and scaling system** to support the corresponding **covers**.

The existing trunking accessory base part remains the primary modeled component. Each base product will now have a related cover component that is:

- stored in the same drawing/document,
- parametrically linked to the base dimensions,
- independently movable in the 2D flat workspace,
- shown by default in 2D with a user-controlled visibility toggle,
- optionally shown in 3D either separately or snapped on top of the base,
- saved inside the DSF as part of the product definition,
- exportable as DXF either alone, or together with the base arranged next to each other.

This is an extension of the existing CMS/template/scaling architecture, not a replacement for the already completed trunking accessory base templates.

---

## 2. Source Drawing

The attached reference PDF is the manufacturing/template reference for the trunking accessories **with cover (W/C)** drawings.

The PDF contains these 11 accessory/base + cover references:

1. Cable Trunking 90 Deg Bend W/C
2. Cable Trunking 45 Deg Bend W/C
3. Cable Trunking Equal Cross W/C
4. Cable Trunking Unequal Cross W/C
5. Cable Trunking 90 Deg Outside Riser W/C
6. Cable Trunking 90 Deg Inside Riser W/C
7. Cable Trunking 45 Deg Outside Riser W/C
8. Cable Trunking 45 Deg Inside Riser W/C
9. Cable Trunking Equal Tee W/C
10. Cable Trunking Unequal Tee W/C
11. Cable Trunking Reducer W/C

The PDF shows the base flat pattern together with a corresponding separate cover flat pattern for each accessory. Do not infer unshown dimensions from the PDF alone; the existing product template/scaling parameters and the user's cover rules are authoritative for implementation.

---

## 3. Core Product Concept

### 3.1 One base, one related cover

Every trunking accessory base should have an associated cover representation:

```text
Trunking Accessory Product
├── Base Part
└── Cover Part
```

The base remains the main product geometry.

The cover is a dependent but independently editable component.

The relationship is:

```text
Base Parameters
      │
      ├── Base Geometry
      │
      └── Cover Geometry
             ├── Cover Main Face
             └── Cover Flanges
```

The cover must not become a separate unrelated drawing that loses its relationship to the base dimensions.

---

## 4. Manufacturing Logic for Covers

The cover should be treated as a sheet-metal part that fits over the corresponding trunking accessory body.

### 4.1 Cover main size

The cover main flat pattern is approximately derived from the dimensional footprint of the corresponding base floor face/accessory footprint.

Do not hard-code a universal cover width or length for every accessory.

Instead, derive the cover dimensions from the already-established base product parameters and geometry.

Conceptually:

```text
Base Product Parameters
        ↓
Base Floor / Reference Face
        ↓
Cover Main Face Size
```

Where the manufacturing drawing requires additional allowance/offset, that allowance must be represented as a dedicated cover parameter rather than hidden inside arbitrary geometry constants.

Suggested future-ready parameters:

```text
coverClearance
coverOffset
coverFlangeLength
coverFlangeAngle
coverBendAllowance
```

Only introduce parameters that are required by the actual template/manufacturing geometry. Do not expose unnecessary settings to the user yet.

### 4.2 Cover flanges

The cover has additional flanges that fit over the vertical walls of the corresponding base/accessory.

Primary rule supplied for this implementation:

> The cover flange length is the same size as the corresponding trunking accessory wall width.

Therefore:

```text
cover flange length ≈ base wall width
```

The actual local geometry must be generated from the base wall/reference dimensions, not copied as a fixed number.

### 4.3 Cover follows accessory type

The cover geometry must respect the topology of the accessory.

Examples include:

- Bend cover follows the bend geometry.
- Tee cover follows the tee branches.
- Cross cover follows all cross branches.
- Unequal Tee cover follows the unequal branch proportions.
- Reducer cover follows the reducer transition.
- Riser covers follow the corresponding inside/outside riser geometry.

Do not build one generic rectangular cover routine and deform it into all product types.

Use the completed base product contract/scaler as the source of truth for product-specific geometry.

### 4.4 Extended Port Drop Flaps for Unequal Fittings (Unequal Tee & Unequal Cross)

For Unequal Tee and Unequal Cross, the accessory body height is determined by the maximum port height:
```text
H_body = max(H_1, H_2, ..., H_n)
```
While the base algorithm already adjusts the lower coupler flaps to match their respective port heights ($H_{port}$), the open mouth area above those lower coupler flaps must be enclosed by the cover.

Therefore, the cover features **extended 90° downward-protruding flaps** over port mouth openings where the port height is lower than the body height:

```text
portDropFlapLength = H_body - H_port
```

#### Manufacturing & Geometric Rules:
1. **Zero Flap for Max Height Port**: If $H_{port} == H_{body}$, no flap is generated (`length = 0`), leaving the mouth open for the matching trunking run.
2. **Downward Flap for Reduced Height Ports**: If $H_{port} < H_{body}$, an additional rectangular flap of length $H_{body} - H_{port}$ and width matching the port mouth width is generated, protruding outward from the cover mouth edge across a 90° fold line.
3. **Flap Alignment & Mating**: When folded in 3D, this flap bends down 90° and meets the top edge of the base body's retracted coupler flaps, creating a seamless, fully enclosed step-down transition.

#### Concrete Example:
- Base Ports:
  - Port 1: Width 100mm, Height 100mm
  - Port 2: Width 50mm, Height 50mm
  - Port 3: Width 100mm, Height 75mm
- Resulting Dimensions:
  - $H_{body} = \max(100, 50, 75) = 100\text{ mm}$
  - **Port 1 Cover Area**: $100 - 100 = 0\text{ mm}$ $\implies$ No drop flap.
  - **Port 2 Cover Area**: $100 - 50 = 50\text{ mm}$ $\implies$ 50 mm downward flap.
  - **Port 3 Cover Area**: $100 - 75 = 25\text{ mm}$ $\implies$ 25 mm downward flap.

---

## 5. Product-Specific Cover Architecture

Use the existing product-contract architecture and introduce a cover-specific layer.

Suggested conceptual structure:

```text
CmsProductContract
├── Base Contract
│   ├── product type
│   ├── ports
│   ├── dimensions
│   └── base scaler
│
└── Cover Contract
    ├── cover geometry definition
    ├── cover-to-base dependencies
    ├── cover flanges
    └── cover scaler
```

The first implementation should prefer deterministic product-specific cover routines for the 11 trunking accessory types rather than a highly generic automatic deformation engine.

This follows the same philosophy already used for the completed base templates: the number of product variants is limited enough that robust deterministic routines are preferable to a complex automatic inference system.

---

## 6. Cover Creation Workflow

### 6.1 Opening a completed trunking DSF with a cover

If the DSF already contains a cover:

```text
Open DSF
  ↓
Load Base
  ↓
Load Cover
  ↓
Load Cover Parameters / Relationship
  ↓
Show both in 2D
  ↓
Generate both in 3D
```

### 6.2 Opening a trunking DXF/DSF without a cover

A trunking base may already exist without a cover.

Provide a clear action:

```text
Create Cover
```

The application should then:

```text
Identify trunking product contract
        ↓
Read current base dimensions
        ↓
Create correct product-specific cover template
        ↓
Parametrically size cover from base
        ↓
Place cover beside base in 2D
        ↓
Add cover to current DSF
```

The user should not need to redraw the cover manually.

### 6.3 Do not silently modify the base

Creating a cover must not alter the existing base geometry, port mapping, bend definitions, or existing scaling parameters.

The cover is an additional component.

---

## 7. 2D Flat Workspace UX

### 7.1 Default visibility

When a trunking accessory has a cover:

```text
Base:   visible
Cover:  visible by default
```

Provide a prominent control:

```text
Show Covers
```

The control is a visibility toggle, not a geometry deletion operation.

Possible state model:

```text
showCoverIn2D = true / false
```

### 7.2 Cover placement beside base

The initial cover placement should be automatically arranged beside the base part with a clean non-overlapping gap.

The placement must be stored as a document-level transform, not baked irreversibly into the cover's local geometry.

Conceptually:

```text
Base local geometry
        +
Base document transform

Cover local geometry
        +
Cover document transform
```

This preserves the ability to move the cover independently.

### 7.3 Cover is movable

The cover should be selectable independently from the base.

Users should be able to:

- select the cover,
- drag it in the 2D workspace,
- move it without altering its geometry,
- rotate it if the existing 2D transform system supports controlled rotation,
- reset it to the automatic beside-base position.

Moving the cover must not change the parametric dimensions.

### 7.4 Selection semantics

The cover should be treated as a component/group rather than as an arbitrary collection of unrelated lines.

Recommended selection identity:

```text
componentId = base / cover
```

This prevents accidental editing of cover geometry when the user is only moving the entire cover.

---

## 8. 2D Cover Snapping

Provide an additional command for placing the cover relative to the base:

```text
Snap Cover to Base
```

This is different from ordinary 2D beside-base placement.

### Beside-base state

```text
Base        Cover
[#####]     [#####]
```

### Snapped state

```text
      COVER
   [########]
   [########]
      BASE
```

The exact transformation must be derived from the base/cover coordinate frames and bend topology rather than from screen coordinates.

The snapped state should store its own transform state, for example:

```text
CoverPlacementMode:
- besideBase
- snappedToBase
- custom
```

Do not destroy the original cover flat geometry when entering snapped mode.

---

## 9. 3D Model Integration

The cover must be a true second sheet-metal component in the 3D scene.

### 9.1 Separate visibility

Provide independent controls:

```text
Base        ON/OFF
Cover       ON/OFF
```

### 9.2 Separate cover placement modes

The 3D scene should support:

```text
Cover visible beside base
Cover snapped onto base
Cover hidden
```

Recommended control:

```text
Show Cover
```

with an additional placement action such as:

```text
Snap Cover
```

### 9.3 Snapped cover

The snapped cover must use the base's 3D transform/topology to determine its placement.

The cover should not be manually rotated in space using guessed Euler angles.

Prefer:

```text
Base reference frame
      ↓
Cover mounting/reference frame
      ↓
Cover 3D transform
```

This should remain deterministic for bends, tees, crosses, risers, reducer, and other accessories.

### 9.4 Do not merge base and cover into one mesh

Keep them as separate model components.

```text
3D Scene
├── Base body
└── Cover body
```

This allows:

- separate visibility,
- separate selection,
- future cover properties,
- independent material/coating properties later,
- future cover-specific validation.

---

## 10. Secondary Detachable 3D Cover View

The user requested that the cover can also be shown in a secondary detachable/dragable/closable display window.

Implement this as a **secondary view of the same cover model state**, not as a second independent model.

Conceptually:

```text
Main 3D View
├── Base
└── Cover

Secondary Cover View
└── Same Cover 3D Component
```

The secondary window should support:

- drag/move,
- close,
- resize where supported by the existing window system,
- independent camera orbit/zoom,
- show/hide controls.

Closing the secondary view must not delete or hide the cover in the main scene.

Do not duplicate the underlying DSF geometry for the secondary view.

### Suggested implementation priority

Treat the detachable window as a presentation feature that can be implemented after the core cover model/DSF/scaling pipeline is stable.

It must not block the first cover implementation.

---

## 11. Scaling Architecture

The cover must scale from the same dimensional parameters that drive the base accessory.

Do not create an independent set of manually entered width/height values that can drift away from the base.

The scaling flow should be:

```text
User changes base product dimensions
              ↓
      Base scaler recalculates
              ↓
      Cover dependency resolver
              ↓
      Cover scaler recalculates
              ↓
       Base + Cover DSF
              ↓
      Rebuild folded 3D models
```

### 11.1 One canonical source

Continue using the 2D DSF geometry as the canonical scalable geometry.

Conceptually:

```text
DSF 2D Base Geometry ──> Base scaling
DSF 2D Cover Geometry ─> Cover scaling
             ↓
       3D regeneration
```

Do not independently scale an already-folded 3D cover mesh and then try to reconcile it back to 2D.

### 11.2 Cover dimensions derived from base parameters

Example conceptual dependency graph:

```text
Base W/H/branch dimensions
          │
          ├──────────> Base geometry
          │
          └──────────> Cover footprint
                         │
                         └──> Cover flanges
```

Where a cover feature depends on a wall width:

```text
coverFlangeLength = correspondingBaseWallWidth
```

Subject to the actual manufacturing geometry and any future explicitly defined clearance parameter.

### 11.3 Baseline-driven scaling

As with the existing CMS scaling system:

```text
Original template DSF
        ↓
Current parameter values
        ↓
Regenerate cover geometry
```

Do not accumulate transformations from the previous state.

This is essential for:

```text
100 → 150 → 200 → 150 → 100
```

to return to the original geometry.

---

## 12. Constraints and Feature Identity

The cover should participate in the existing constraint/feature identity architecture.

Important cover entities should receive persistent IDs, for example:

```text
COVER_FACE_MAIN
COVER_FLANGE_1
COVER_FLANGE_2
COVER_BEND_1
COVER_BEND_2
COVER_SLOT_1
...
```

Exact IDs should be product-specific where needed.

This is important because future scaling may need to maintain relationships between:

- cover edges,
- flange edges,
- bend lines,
- corner arcs,
- holes/punches,
- corresponding base edges.

The existing interactive two-entity constraint/dimension system should be capable of being extended to cover entities without creating a second dimensioning framework.

---

## 13. DSF Format Extension

The DSF format must be amended to support an optional cover component while remaining backward compatible.

### 13.1 Backward compatibility

Existing DSFs without a cover must remain valid.

Conceptually:

```json
{
  "version": "existing-version",
  "base": { ... }
}
```

must continue to load.

A newer DSF may contain:

```json
{
  "version": "new-version",
  "base": { ... },
  "cover": { ... }
}
```

Do not require old drawings to contain a cover object.

### 13.2 Suggested cover object

The exact schema should follow the project's existing DSF conventions, but conceptually the cover should contain:

```json
{
  "cover": {
    "present": true,
    "productType": "...",
    "geometry": { ... },
    "featureMetadata": { ... },
    "parameters": { ... },
    "placement2D": { ... },
    "placementMode2D": "besideBase",
    "placement3D": { ... },
    "placementMode3D": "snappedToBase",
    "visibility": {
      "showIn2D": true,
      "showIn3D": true
    },
    "properties": { ... }
  }
}
```

The exact field names should be adapted to existing DSF naming conventions rather than blindly introducing a parallel vocabulary.

### 13.3 Cover properties

The DSF should provide a place for future cover-specific properties even if they are not yet exposed in the UI.

Examples of future properties:

```text
cover material
coating
thickness
finish
mass
manufacturer notes
part number
cover-specific allowances
```

Do not implement unnecessary property logic now. Establish an extensible container.

---

## 14. DXF Export

When the user chooses DXF export for a trunking accessory with a cover, show an explicit export choice.

Recommended dialog:

```text
Export DXF

[ ] Base
[ ] Cover

Arrangement:
(o) Side-by-side
```

The user may choose:

```text
Base only
Cover only
Base + Cover
```

### 14.1 Base + Cover export

When both are selected:

- export both into the same DXF,
- place them next to each other,
- avoid overlap,
- preserve scale 1:1,
- preserve manufacturing geometry,
- preserve relevant layers/entity types according to the existing DXF exporter.

The export arrangement should be generated at export time.

Do not permanently move the document's actual 2D cover placement just to prepare the export.

### 14.2 Do not confuse document placement with export layout

Maintain:

```text
Document placement
```

separately from:

```text
Export arrangement
```

This prevents an export operation from unexpectedly changing the user's drawing.

---

## 15. Cover Template Generation

For a base opened without a cover, implement:

```text
Create Cover
```

The routine should:

1. identify the CMS product contract,
2. validate that the product supports a cover,
3. read the current base parameters,
4. obtain the corresponding cover template definition,
5. generate the cover flat geometry,
6. generate cover-specific bend/flange relationships,
7. associate the cover with the base,
8. place it beside the base,
9. save it into the DSF state.

### Important

The cover should be generated **explicitly by the app** from known product geometry.

Do not ask the user to manually identify every cover bend/flange for these known templates.

The user has already completed the difficult base template creation stage. The cover stage should leverage those known product contracts.

---

## 16. Product Registry

Add cover support to the trunking accessory product registry.

Conceptually:

```text
Product
├── baseTemplate
├── baseScaler
├── coverTemplate
├── coverScaler
└── coverPlacementResolver
```

Every supported trunking accessory should declare whether it has a cover:

```text
supportsCover = true
```

Do not infer cover availability from filename strings alone.

Use the product contract.

---

## 17. Cover Scaling Test Matrix

Tests must verify both base preservation and cover adaptation.

### Test A - Existing base unchanged

Scaling/creating the cover must not modify:

- base face topology,
- base bend definitions,
- base port assignments,
- base persistent feature IDs.

### Test B - Cover follows base dimensions

For representative products, change the base dimensions and verify:

```text
base size changes
       ↓
cover footprint changes
       ↓
cover flange dimensions remain linked
```

### Test C - Flange dependency

For every cover flange:

```text
measured cover flange length
    ≈ corresponding base wall width
```

within the accepted manufacturing tolerance.

### Test D - Reversibility

Verify sequences such as:

```text
Baseline → larger → smaller → Baseline
```

return to the baseline cover geometry.

### Test E - Visibility

Verify:

```text
showCoverIn2D = true
showCoverIn2D = false
```

without modifying geometry.

Likewise independently:

```text
showCoverIn3D = true / false
```

### Test F - Beside vs snapped

Verify the cover can switch between:

```text
besideBase
snappedToBase
custom
```

without altering local cover geometry.

### Test G - DSF round trip

Verify:

```text
DSF save
  ↓
DSF reopen
  ↓
Base + Cover restored
```

including:

- cover geometry,
- cover parameters,
- cover visibility state where intended,
- 2D placement,
- cover relationship to the base.

### Test H - Legacy DSF

Open an existing trunking DSF created before cover support.

Expected:

```text
Load succeeds
Cover = absent
Create Cover action available
```

### Test I - DXF export

Verify all three choices:

```text
Base only
Cover only
Base + Cover
```

and verify that Base + Cover are positioned side-by-side in the exported DXF without changing the document's saved placement.

---

## 18. Geometry Integrity Tests

For representative cover templates, verify:

- closed outer contours,
- coincident connected vertices,
- valid bend connections,
- preserved arc radii where applicable,
- preserved punch dimensions,
- no accidental duplicate edges,
- no self-intersections,
- correct flange connectivity,
- correct relationship between cover bends and base wall geometry.

The exact tolerance should reuse the project's existing CAD geometry tolerance policy.

Do not introduce a different tolerance only for covers unless necessary.

---

## 19. 3D Verification

For each supported accessory class, verify three views/states:

### State 1 - Base only

```text
Base visible
Cover hidden
```

### State 2 - Base + cover beside

```text
Base visible
Cover visible
Cover positioned separately for inspection
```

### State 3 - Base + cover snapped

```text
Base visible
Cover fitted over base
```

The snapped cover should align with the corresponding accessory walls and should not visibly float, penetrate, or rotate incorrectly.

---

## 20. Recommended UX Flow

The preferred UX should remain simple and guided rather than exposing expert-level CAD operations.

### Existing trunking drawing with no cover

```text
Open DXF / DSF
        ↓
Recognize trunking product
        ↓
[Create Cover]
        ↓
Cover generated
        ↓
Cover appears beside base
        ↓
3D cover becomes available
```

### Existing trunking drawing with cover

```text
Open
 ↓
Base + Cover loaded
 ↓
Cover visible by default
```

### Useful controls

Keep the main toolbar/context controls simple:

```text
Show Cover
Snap Cover
Create Cover
Export DXF
```

Avoid adding an extensive cover-specific settings panel during the first implementation.

---

## 21. Visual Feedback

Continue the established guided visual language used elsewhere in TruFold Studio.

When a cover is created or regenerated:

- highlight the newly created cover in 2D,
- briefly highlight the corresponding 3D cover component,
- animate the cover region without changing geometry,
- make it obvious that the cover has been successfully linked to the base.

The interaction should feel like the application learned/generated another product component, not like the user is starting a second CAD project.

---

## 22. Important Separation of Responsibilities

Keep these concepts separate:

```text
1. Cover Geometry
2. Cover Parameters
3. Cover-to-Base Dependency
4. 2D Cover Placement
5. 3D Cover Placement
6. Cover Visibility
7. DXF Export Arrangement
```

Changing one must not accidentally mutate another.

Example:

```text
Moving cover in 2D
      ≠ changing cover dimensions

Hiding cover
      ≠ deleting cover

Exporting side-by-side
      ≠ moving cover in document

Snapping cover in 3D
      ≠ changing cover flat geometry
```

This separation is fundamental to keeping the feature robust.

---

## 23. Recommended Implementation Order

Implement in this dependency order:

### Phase 1 - Data model

- Add optional cover section to DSF.
- Add cover component identity.
- Add backward-compatible loading.
- Add cover placement/visibility state.

### Phase 2 - Cover template definitions

Implement explicit templates for the 11 trunking accessory W/C types.

### Phase 3 - Cover scaling

Connect cover dimensions to the existing base product parameters.

### Phase 4 - 2D integration

- show/hide,
- automatic beside-base placement,
- independent selection,
- independent movement,
- reset placement,
- snap-to-base placement.

### Phase 5 - 3D integration

- folded cover generation,
- separate visibility,
- beside/base-relative presentation,
- snapped cover placement.

### Phase 6 - DXF export

Implement base/cover/both export choices and non-destructive side-by-side export arrangement.

### Phase 7 - Secondary detachable cover viewer

Add the detachable/dragable/closable cover-focused 3D viewer once the core pipeline is stable.

### Phase 8 - Validation

Run product-by-product geometry, DSF, scaling, 2D, 3D, and DXF tests.

---

## 24. Additional Design Recommendations

### 24.1 Treat cover as a first-class CMS component

Do not implement the cover merely as a visual overlay. It should have a persistent identity and its own geometry representation.

This is important for future requirements such as:

- cover-specific material/coating,
- separate BOM item,
- separate manufacturing calculation,
- separate DXF export,
- cover-specific bend information,
- cover-specific punch/coupler holes,
- separate costing/weight.

### 24.2 Keep cover and base parameter linkage explicit

Use explicit dependency metadata where possible.

For example:

```text
CoverFlange_1.length
    dependsOn -> BaseWall_1.width
```

This will integrate well with the existing constraint-driven scaling architecture.

### 24.3 Avoid destructive regeneration

When the cover is regenerated from changed parameters, regenerate from the canonical template definition rather than repeatedly modifying the previously generated cover geometry.

### 24.4 Preserve future extensibility

The first release should not attempt to solve every possible cover-specific property.

Build the component/schema boundaries now so those properties can be added later without another DSF redesign.

### 24.5 Secondary viewer should share the same model state

Do not create a second copy of the cover's DSF geometry solely for the detached display. Both views should reference the same cover model/document state.

---

## 25. Acceptance Criteria

The implementation is complete when all of the following are true:

1. Every supported trunking accessory base can have its corresponding cover.
2. The 11 W/C product types in the reference drawing are represented by explicit cover templates.
3. A cover is generated automatically for a trunking base that does not yet contain one.
4. Cover dimensions change correctly when the base dimensions change.
5. Cover flange lengths remain linked to their corresponding base wall widths.
6. Cover can be moved independently in 2D.
7. Cover is visible by default in the 2D drawing and can be hidden with a Show Cover control.
8. Cover can be shown/hidden independently in 3D.
9. Cover can be displayed beside the base or snapped over the base in 3D.
10. Cover can be opened in a detachable/dragable/closable secondary 3D viewer without creating a second independent geometry state.
11. DSF stores base + cover together and remains backward compatible with legacy base-only DSFs.
12. DXF export can export Base, Cover, or Base + Cover.
13. Base + Cover DXF export places the two parts next to each other without modifying the document's actual placement.
14. Scaling is baseline-driven and reversible.
15. Base geometry and base parameters remain unaffected by cover creation, movement, visibility changes, and export.
16. Cover geometry passes contour/connectivity/feature integrity checks.

---

## 26. Implementation Principle

The core rule for the entire feature is:

> **The cover is an independently selectable and displayable sheet-metal component, but it remains parametrically derived from and linked to its corresponding trunking accessory base.**

The base and cover should therefore behave as **one product definition with two physical parts**, not as two unrelated drawings.

---

## 27. Agent Instruction - Do Not Over-Engineer the First Pass

Do not introduce a new generic CAD inference engine for covers.

Do not require the user to manually define cover bend/flange lines for the known trunking accessory products.

Do not rebuild the already completed trunking base templating/scaling logic.

Do not modify the legacy automatic bend/flange generation pipeline just to support covers.

Use the existing product contracts, 2D DSF canonical geometry, deterministic product-specific scaling routines, folded 3D regeneration, persistent feature IDs, and existing UI conventions.

The first goal is a reliable pipeline:

```text
Existing Trunking Base
        ↓
Create / Load Cover
        ↓
Parametric Cover Link
        ↓
2D Base + Cover
        ↓
3D Base + Cover
        ↓
Snap / Hide / Move
        ↓
DSF Save / Reopen
        ↓
DXF Base / Cover / Both
```

Only after this pipeline is stable should additional cover-specific properties and advanced viewer features be expanded.
