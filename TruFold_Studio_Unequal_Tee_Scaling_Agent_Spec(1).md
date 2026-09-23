# TruFold Studio — Unequal Tee Scaling Subroutine

## Implementation Specification

### Purpose

Implement a dedicated, deterministic **Unequal Tee scaling subroutine** named `UnequalTeeScaler` for TruFold Studio.

The subroutine must scale an existing, validated Unequal Tee CMS template from one size/variation to another while preserving the product's manufacturing logic, topology, flange structure, bend structure, and rigid features such as coupler holes and other constrained holes.

This is a **product-specific scaling routine**. It must not attempt to solve Unequal Tee scaling by applying a generic freeform geometric transformation to the entire DXF.

The architecture should use the existing **2D `DsfDocument` as the canonical scaling source** and regenerate the folded representation through the existing `KinematicFoldEngine` after the 2D geometry has been updated.

---

## 1. Scope

### In scope

- Unequal Tee CMS product only.
- Scaling an already taught/validated Unequal Tee template.
- Width/height/branch-size changes defined by the product contract.
- Preserving bend lines and flange lines as structural features.
- Preserving physical port topology and semantic port mappings.
- Constraint-driven movement of holes and other features.
- Correct treatment of coupler slots/holes as rigid manufacturing features.
- Regeneration of the folded 3D model from the scaled 2D source.
- Dimension reset/recalculation after scaling.
- Deterministic validation and clear user feedback.
- Compatibility with previously saved DSF templates where the required Unequal Tee information is available.

### Out of scope

- Automatic creation of bend lines for new CMS drawings.
- Automatic creation of flange lines for new CMS drawings.
- Generic AI/freeform scaling of arbitrary DXF geometry.
- Re-detecting the entire CMS product structure every time a dimension changes.
- Replacing the user's confirmed bend/flange structure.
- Independent scaling of the 3D model.

The legacy automatic bend/flange code may remain in the repository for reference, but it must not be part of the active Unequal Tee scaling pipeline.

---

# 2. Design Principles

## 2.1 Canonical source is 2D

The source of truth during scaling is the flattened 2D `DsfDocument`.

Scaling sequence:

`DsfDocument → apply Unequal Tee parametric changes → resolve constraints/features → validate 2D → KinematicFoldEngine → regenerate 3D`

Never perform an independent geometric scale on the folded 3D model.

## 2.2 Product logic before geometry

The scaler must understand the structure of an Unequal Tee before moving entities.

The product contract should define:

- Main/inlet branch dimensions.
- Branch/outlet dimensions.
- Branch count.
- Port identities.
- Bend relationships.
- Flange relationships.
- Which dimensions are driving parameters.
- Which features are rigid.
- Which zones are allowed to stretch.
- Which constraints must remain invariant.

## 2.3 Preserve structure, not just appearance

A scaled drawing is valid only when the manufacturing structure remains valid.

A visually similar shape is insufficient if:

- a coupler slot changes size,
- a hole migrates incorrectly,
- a bend line moves independently of the face it belongs to,
- a flange width changes unintentionally,
- a port changes identity,
- sheet-metal topology becomes invalid,
- or the folded result no longer corresponds to the intended Unequal Tee.

## 2.4 Deterministic behavior

The same source DSF, parameter values, and constraint state must produce the same scaled 2D and regenerated 3D result.

Avoid probabilistic feature matching during the actual scaling operation.

---

# 3. Unequal Tee Product Model

An Unequal Tee is a three-port sheet-metal branch component in which at least one branch dimension differs from another.

The implementation must represent the three physical ports explicitly rather than relying only on drawing position.

Example logical structure:

- `P_MAIN` — main/inlet port.
- `P_BRANCH_A` — first branch/outlet.
- `P_BRANCH_B` — second branch/outlet.

The exact semantic names may follow the existing CMS schema, but each port must have a stable ID.

Each port record should contain, where available:

```text
portId
role
width
height
orientation
center
connectedFaceId
openingGeometryId
edgeGeometryIds
```

### Port semantics

For Unequal Tee, the semantic role must not be inferred solely from geometric position during every scale operation.

Once the port mapping has been confirmed during CMS teaching, persist it in DSF and reuse it.

For unequal products, the main/largest section may be designated as the inlet according to the product contract. Do not invent a new role assignment during scaling.

---

# 4. Required DSF Information

`UnequalTeeScaler` should refuse or safely fall back when the source template does not contain sufficient product information.

Recommended DSF structure:

```json
{
  "cms": {
    "category": "Tray Accessories",
    "productType": "Tee",
    "variation": "Unequal Tee",
    "templateVersion": 1
  },
  "productContract": {
    "parameters": {},
    "ports": [],
    "features": [],
    "zones": [],
    "constraints": []
  },
  "scaling": {
    "engine": "UnequalTeeScaler",
    "version": 1,
    "drivingParameters": [],
    "rigidFeatures": [],
    "stretchZones": [],
    "constraints": []
  }
}
```

The exact serialization should conform to the current DSF model and naming conventions used by TruFold Studio.

---

# 5. Driving Parameters

The scaler must operate on explicit engineering parameters rather than arbitrary global X/Y factors.

Typical driving parameters for an Unequal Tee may include:

```text
mainWidth
mainHeight
branchAWidth
branchAHeight
branchBWidth
branchBHeight
flangeWidth
sheetThickness   (only if relevant to geometry generation)
```

Only parameters actually supported by the specific product template should be exposed.

The scaler must distinguish between:

- **driving parameters** — values the user changes;
- **derived dimensions** — values recalculated from driving parameters;
- **fixed dimensions** — dimensions that must remain unchanged;
- **constraint dimensions** — relational dimensions that must remain satisfied.

Do not use a single uniform X/Y scaling factor for the full drawing.

---

# 6. Geometry Classification

Before scaling, every relevant entity must be classified into a product-aware role.

Examples:

### Structural geometry

- face boundaries
- bend lines
- flange lines
- port opening boundaries
- miter/junction geometry

### Manufacturing features

- coupler slots
- perforations
- mounting holes
- service holes
- cutouts

### Construction/reference geometry

- centers
- guide lines
- dimensions
- annotations
- construction points

Each entity should have a stable identity wherever possible.

The scaler should operate on persistent feature IDs rather than relying on DXF entity ordering.

---

# 7. Rigid vs Stretchable Regions

Unequal Tee scaling must use explicit zone classification.

## 7.1 Rigid regions

Rigid regions include geometry whose own dimensions must not be distorted.

Typical examples:

- coupler slots/holes
- fixed hole diameters
- slot widths and lengths
- fixed edge offsets
- flange widths when defined as fixed
- bend radii when the product contract requires them to remain fixed
- connector/coupler geometry

Rigid means the feature's intrinsic size is preserved. Its **position may change** according to constraints.

## 7.2 Stretch regions

Stretchable regions are allowed to absorb dimensional changes.

Examples may include:

- long straight web sections
- branch body lengths
- non-featured sheet areas

Stretching must happen along the direction associated with the parameter being changed.

Do not distort geometry perpendicular to the intended scaling direction.

---

# 8. Constraint-Driven Feature Movement

The interactive 2-entity dimension/constraint system developed for TruFold Studio must be usable by the scaler.

Constraints should be represented independently from display dimensions.

Typical constraint examples:

```text
hole center → outer edge midpoint
hole center → bend line
hole center → hole center
feature center → face edge
port edge → port edge
```

## 8.1 Hole-to-edge

If a hole center is constrained to an edge by a fixed distance, the hole must move so that the distance remains unchanged after scaling.

The hole diameter/slot dimensions remain rigid unless explicitly defined as a driving parameter.

## 8.2 Hole-to-hole

When two holes are constrained by a fixed distance/vector relationship, scaling the surrounding face must not independently distort the holes.

The appropriate hole(s) should translate to preserve the constraint.

## 8.3 Edge-driven constraints

When a constraint is tied to a face edge or bend line, movement of the driving edge must propagate to dependent features.

The dependency graph must prevent circular updates.

---

# 9. Constraint Resolution Order

Resolve scaling in a deterministic dependency order:

1. Validate source template.
2. Read target driving parameters.
3. Determine parameter deltas.
4. Move driving structural geometry.
5. Recompute derived edges/boundaries.
6. Resolve bend/flange structural positions.
7. Resolve port boundaries.
8. Resolve rigid feature positions using constraints.
9. Validate intrinsic rigid feature sizes.
10. Recalculate derived dimensions.
11. Validate 2D topology.
12. Regenerate folded 3D.
13. Validate 3D topology and port structure.
14. Commit only when all required checks pass.

A failed constraint resolution must not leave the DSF in a partially updated state.

Use transactional semantics:

```text
originalDocument
        ↓
clone / workingDocument
        ↓
apply scaling
        ↓
validate
        ↓
commit
```

On failure, discard the working result and preserve the original template.

---

# 10. Unequal Tee Scaling Algorithm

## Step 1 — Load template

Load the selected Unequal Tee DSF and verify:

- CMS category/product/variation match.
- `UnequalTeeScaler` is the declared scaling engine.
- Port mappings exist.
- Bend/flange structure exists.
- Required feature IDs exist.
- Required driving parameters exist.

## Step 2 — Capture baseline

Create a baseline snapshot of:

- all driving parameters;
- important face dimensions;
- bend positions;
- flange positions;
- port dimensions;
- feature dimensions;
- constraint values;
- rigid feature sizes;
- topology signatures.

## Step 3 — Apply requested parameter changes

Calculate target values from the new variation.

Example:

```text
mainWidth:   100 → 150
mainHeight:  100 → 150
branchA:      75 → 100
branchB:      50 → 75
```

Only explicitly supported dimensions should change.

## Step 4 — Update structural geometry

Move the controlling face edges/bend lines according to their parameter ownership.

Avoid applying a global scale transform.

For example:

```text
width delta  → width-owned edge groups
height delta → height-owned edge groups
branch delta → branch-owned edge groups
```

## Step 5 — Rebuild dependent geometry

Recompute geometry that is mathematically derived from the driving geometry, such as:

- miter intersections;
- branch junctions;
- corner intersections;
- bend-line endpoints;
- flange boundaries;
- face boundaries.

Do not use a generic `45°` morph for every geometry containing a 45-degree angle.

Geometry type and product role must determine the operation.

## Step 6 — Resolve ports

Use the persisted semantic port map.

Recompute the actual opening coordinates from the new structural geometry while retaining:

- stable `portId`;
- semantic role;
- width/height relationship;
- orientation;
- connected face.

The scaler must not randomly remap ports because their coordinates changed.

## Step 7 — Resolve rigid features

Move coupler slots, holes, and other rigid features through the constraint graph.

For each feature:

```text
if constrained-to-edge:
    preserve edge offset
elif constrained-to-hole:
    preserve relational vector/distance
elif constrained-to-face-frame:
    preserve local coordinates
else:
    use feature-specific product rule
```

Intrinsic feature geometry must remain unchanged unless the feature is explicitly parameterized.

## Step 8 — Recalculate dimensions

After geometry has settled:

- discard stale display dimensions;
- recompute derived measurements;
- update dimension labels/badges;
- preserve the underlying constraints.

Displayed dimension values must always reflect the final geometry, not intermediate geometry.

## Step 9 — Validate 2D

Run all 2D validators before generating 3D.

## Step 10 — Regenerate 3D

Pass the final 2D `DsfDocument` through `KinematicFoldEngine`.

The 3D result must be regenerated rather than separately transformed.

## Step 11 — Validate 3D

Check topology, connectivity, bend orientation, ports, and visible feature placement.

## Step 12 — Commit

Commit the scaled DSF only after all mandatory validations pass.

---

# 11. Special Handling of 45° Geometry

A prior failure mode showed that routing all 45-degree geometry through a generic `45_deg_bend` transformation can distort Unequal Tee features.

Therefore:

> **Never select a scaling algorithm solely because an angle equals 45°.**

Instead, identify geometry by:

1. feature ID;
2. owning face;
3. product role;
4. bend relationship;
5. parameter ownership;
6. explicit template rule.

This prevents the scaler from applying a 45-degree miter morph to unrelated cheek/prong geometry or coupler-slot structures.

---

# 12. Coupler Slot / Hole Handling

Coupler holes are manufacturing features and must be treated as rigid features.

The scaler must preserve:

- hole/slot length;
- hole/slot width;
- slot orientation;
- slot geometry type;
- feature classification (`CncPunchRole.coupler` or current equivalent);
- required edge/feature offsets.

Only the position may change when constraints or product rules require it.

The scaler must never stretch a coupler slot because the parent face became longer or wider.

Feature matching after scaling should be ID-based first and geometric as a fallback.

---

# 13. Topology Preservation

The following must remain stable across supported scaling operations:

- number of physical faces;
- face adjacency graph;
- number of expected ports;
- port identities;
- bend connectivity;
- flange connectivity;
- manufacturing feature count, unless the product contract explicitly permits a change.

A topology signature may be computed before and after scaling.

Example concept:

```text
TopologySignature {
  faceCount
  bendCount
  flangeCount
  portCount
  featureCount
  adjacencyHash
}
```

The signature need not be byte-for-byte identical, but structural invariants must be enforced.

---

# 14. 2D-to-3D Consistency Checks

After regeneration through `KinematicFoldEngine`, verify:

- every expected planar face exists;
- bend relationships remain valid;
- flange faces remain attached to their parent faces;
- all three ports exist;
- port identity and orientation are preserved;
- no face is inverted unexpectedly;
- no self-intersection is introduced where prohibited;
- rigid features appear on the correct face;
- hole positions correspond to the final 2D source.

Where practical, compare 2D feature IDs to their folded 3D counterparts.

---

# 15. User Experience

The user experience should remain simple. The user should not need to understand the internal scaling algorithm.

### Recommended flow

```text
Open Unequal Tee template
        ↓
Choose target variation / dimensions
        ↓
Preview target parameters
        ↓
Apply scaling
        ↓
Animated 2D update
        ↓
Animated 3D regeneration
        ↓
Validation summary
        ↓
Accept / undo
```

During scaling, the UI can highlight the structural region currently being recalculated, for example:

- branch region;
- width-controlled edge;
- height-controlled edge;
- affected holes;
- final 3D branch topology.

The highlighting is visual feedback only and must not alter geometry.

---

# 16. Interactive Dimension Support

The Onshape-style two-entity dimension tool should serve as a constraint authoring mechanism during template teaching and correction.

Supported selection examples:

- hole center + hole center;
- hole center + edge;
- hole center + bend line;
- endpoint + endpoint;
- endpoint + edge midpoint;
- line + line;
- arc center + edge;
- other supported entity pairs.

The resulting constraint should store:

```text
constraintId
entityAId
entityBId
measurementType
axis/vector
nominalValue
parameterBinding
priority
```

The displayed badge is only a UI representation of the constraint.

---

# 17. Constraint Priority

Recommended priority classes:

### P0 — Product invariants

Must always hold.

Examples:

- port count;
- topology;
- coupler slot intrinsic size;
- mandatory feature presence.

### P1 — Driving parameter constraints

Directly controlled by the requested target variation.

### P2 — Manufacturing constraints

Examples:

- hole-to-edge offsets;
- hole-to-hole spacing;
- fixed flange dimensions;
- bend-related offsets.

### P3 — Derived/display dimensions

May be recalculated from the solved geometry.

If constraints conflict, the system must reject the scaling operation rather than silently distort a higher-priority rule.

---

# 18. Failure Handling

Use explicit failure codes rather than silently producing an incorrect drawing.

Suggested codes:

```text
UNEQUAL_TEE_TEMPLATE_MISSING
UNEQUAL_TEE_PARAMETER_MISSING
UNEQUAL_TEE_PORT_MAP_MISSING
UNEQUAL_TEE_FEATURE_MISSING
UNEQUAL_TEE_CONSTRAINT_CONFLICT
UNEQUAL_TEE_RIGID_FEATURE_DISTORTED
UNEQUAL_TEE_TOPOLOGY_CHANGED
UNEQUAL_TEE_2D_VALIDATION_FAILED
UNEQUAL_TEE_3D_REGENERATION_FAILED
UNEQUAL_TEE_3D_VALIDATION_FAILED
```

The UI should state the affected area in user-friendly language.

Example:

> Scaling could not be completed because the required branch-to-hole constraint could not be preserved. Your original template was not changed.

Avoid exposing internal stack traces in normal UI.

---

# 19. Validation Checklist

## Source validation

- [ ] Correct CMS category.
- [ ] Product type = Tee.
- [ ] Variation = Unequal Tee.
- [ ] Required port mappings exist.
- [ ] Bend structure exists.
- [ ] Flange structure exists.
- [ ] Required features are identified.
- [ ] Scaling contract is present.

## Parameter validation

- [ ] Requested values are within allowed product limits.
- [ ] No unsupported parameter is changed.
- [ ] No negative/zero invalid dimensions are accepted.
- [ ] Minimum manufacturing dimensions are respected.

## Geometry validation

- [ ] Structural edges move according to ownership.
- [ ] No generic global scaling is used.
- [ ] Junction geometry remains connected.
- [ ] Bend lines remain associated with correct faces.
- [ ] Flanges remain associated with correct faces.

## Feature validation

- [ ] Coupler slots remain rigid.
- [ ] Hole diameters remain unchanged unless parameterized.
- [ ] Slot dimensions remain unchanged unless parameterized.
- [ ] Hole-to-edge constraints remain satisfied.
- [ ] Hole-to-hole constraints remain satisfied.
- [ ] Features remain on their intended face.

## Port validation

- [ ] Port count remains three.
- [ ] Port IDs remain stable.
- [ ] Port roles remain stable.
- [ ] Port widths/heights match the target contract.
- [ ] Port orientation is valid.

## 3D validation

- [ ] KinematicFoldEngine successfully regenerates the model.
- [ ] Face connectivity remains valid.
- [ ] No unintended inversion occurs.
- [ ] No invalid self-intersection occurs.
- [ ] All ports are physically present.

---

# 20. Recommended Class Structure

Use a dedicated class rather than embedding product-specific rules inside a generic scaler.

Conceptual API:

```dart
class UnequalTeeScaler {
  UnequalTeeScaleResult scale({
    required DsfDocument source,
    required UnequalTeeScaleParameters target,
  });
}
```

Supporting concepts:

```dart
class UnequalTeeScaleParameters {
  final double? mainWidth;
  final double? mainHeight;
  final double? branchAWidth;
  final double? branchAHeight;
  final double? branchBWidth;
  final double? branchBHeight;
  final double? flangeWidth;
}
```

Result:

```dart
class UnequalTeeScaleResult {
  final DsfDocument document;
  final bool valid;
  final List<ScalingIssue> issues;
  final ScalingReport report;
}
```

Avoid hard-coding parameter assumptions throughout unrelated CAD classes.

---

# 21. Separation of Responsibilities

`UnequalTeeScaler` should orchestrate product rules, while reusable lower-level services perform general geometry operations.

Suggested separation:

```text
UnequalTeeScaler
 ├── ParameterResolver
 ├── UnequalTeeGeometryRules
 ├── ConstraintSolver
 ├── FeatureMover
 ├── PortStateUpdater
 ├── DimensionRecalculator
 ├── DsfValidator
 └── KinematicFoldEngine
```

The exact class names may be adapted to the current codebase.

The key requirement is that Unequal Tee product logic remains isolated and testable.

---

# 22. Logging / Diagnostics

Add structured diagnostics for development builds.

For each scaling operation, log:

```text
source template
source parameters
target parameters
changed parameters
moved structural entities
resolved constraints
moved rigid features
port updates
validation results
```

A concise user-facing report should be generated after a successful scale.

Example:

```text
Unequal Tee scaled successfully

Main: 100 × 100 → 150 × 150
Branch A: 75 × 50 → 100 × 75
Branch B: 50 × 50 → 75 × 50

12 constraints preserved
8 coupler slots preserved
3 ports preserved
3D regenerated successfully
```

The exact wording may be adapted to the existing UI.

---

# 23. Testing Strategy

Tests must cover both geometry and manufacturing intent.

## Unit tests

Test:

- parameter delta calculations;
- zone classification;
- edge movement;
- constraint resolution;
- hole-to-edge preservation;
- hole-to-hole preservation;
- rigid feature preservation;
- port state preservation;
- topology checks;
- dimension recalculation.

## Golden template tests

Maintain known Unequal Tee DSF fixtures for representative variations.

For each fixture:

```text
load known DSF
→ scale to target
→ validate
→ compare expected topology/features/dimensions
```

Do not rely only on pixel/image comparison.

## Regression tests

Include the previously observed failure mode where increasing dimensions caused:

- cheek/prong distortion;
- coupler-slot distortion;
- incorrect 45-degree morphing;
- incorrect port geometry.

The test must prove that the dedicated `UnequalTeeScaler` no longer routes that geometry through the inappropriate generic `45_deg_bend` transformation.

---

# 24. Example Scaling Scenario

Source:

```text
Unequal Tee
Main:     100 × 100
Branch A:  75 × 75
Branch B:  50 × 50
Flange:    20
```

Target:

```text
Main:     150 × 150
Branch A: 100 × 100
Branch B:  75 × 75
Flange:    20
```

Expected behavior:

1. Main and branch dimensions change according to the product contract.
2. Flange width remains 20 because it is fixed.
3. Bend lines move with their owning structural geometry.
4. Junctions are reconstructed from the updated structural edges.
5. Port identities remain unchanged.
6. Coupler slots maintain their exact intrinsic dimensions.
7. Constrained holes reposition to preserve their defined offsets/relationships.
8. Derived dimensions are recalculated.
9. 3D is regenerated from the new 2D geometry.
10. The final topology remains an Unequal Tee.

---

# 25. Backward Compatibility

Existing legacy DSF files should not be modified destructively merely to enable the new scaler.

Where possible:

- read existing product metadata;
- migrate missing non-critical fields with safe defaults;
- mark migrated records explicitly;
- preserve unknown DSF fields;
- retain legacy scaling metadata for backward compatibility.

If required information is genuinely absent, show a guided message indicating that the template needs to be taught/updated before Unequal Tee scaling is enabled.

---

# 26. Implementation Guardrails

The agent implementing this specification must follow these rules:

1. Do not introduce automatic bend-line generation into this scaler.
2. Do not introduce automatic flange-line generation into this scaler.
3. Do not apply global X/Y scaling to the full DXF.
4. Do not scale 3D independently from 2D.
5. Do not identify geometry solely by angle.
6. Do not stretch coupler holes/slots.
7. Do not silently remap port roles.
8. Do not overwrite the source document before validation completes.
9. Do not silently ignore unresolved constraints.
10. Do not treat display dimensions as the source of truth; constraints and geometry are the source of truth.

---

# 27. Definition of Done

The implementation is complete when all of the following are true:

- [ ] `UnequalTeeScaler` exists as a dedicated product-specific scaling implementation.
- [ ] Scaling is driven by explicit Unequal Tee parameters.
- [ ] Canonical scaling source is `DsfDocument`.
- [ ] Structural bend/flange relationships remain intact.
- [ ] Constraint-driven feature movement is supported.
- [ ] Rigid coupler holes/slots remain undistorted.
- [ ] Port identities and topology remain stable.
- [ ] The previous 45-degree distortion failure is covered by regression tests.
- [ ] 2D validation runs before 3D regeneration.
- [ ] 3D is regenerated through `KinematicFoldEngine`.
- [ ] 3D validation runs before commit.
- [ ] Failed scaling leaves the original template unchanged.
- [ ] Diagnostics/reporting are available.
- [ ] Representative Unequal Tee fixtures pass automated tests.

---

# 28. Architectural Intent

This routine is the model for the broader TruFold Studio product-specific scaling architecture.

The general pattern should be:

```text
CMS Product
   ↓
Product Contract
   ↓
Dedicated Scaler
   ↓
2D Constraint / Feature Resolution
   ↓
Validated DsfDocument
   ↓
KinematicFoldEngine
   ↓
Validated Folded 3D
```

Each CMS product with unique geometry should be allowed to have its own deterministic scaling subroutine rather than forcing every product into one generic transformation algorithm.

The user should experience this as a simple parametric resize, while the implementation preserves the deeper CAD/manufacturing intent underneath.
