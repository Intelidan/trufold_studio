# TruFold Studio — Unequal Tee Parametric Scaling
## Detailed Agent Implementation Specification

**Product:** Unequal Tee  
**Status:** Implementation specification  
**Primary reference:** `Unequal Tee scaling details.pdf`  
**Reference geometry:** `unequal_tee_100x100x50x100x100x50x50.dxf`

---

# 1. Purpose

Implement a dedicated, deterministic **Unequal Tee scaling subroutine** in TruFold Studio.

Unequal Tee must be treated as a separate CMS product from Equal Tee.

The reason is geometric dependency:

- Equal Tee can largely scale using common Width/Height parameters.
- Unequal Tee has different port widths/heights.
- Changing one side can change the transition/junction geometry.
- The other side may need to remain unchanged.
- A compensating region must absorb the required dimensional change.
- Height behavior is not simple uniform scaling.

The reference document defines the following manufacturing/design behavior:

1. Example Unequal Tee:
   - Port 1: approximately `100W × 100H`
   - Port 2: approximately `50W × 100H`
   - Port 3: approximately `100W × 100H`
2. Increasing one side's width should not change the opposite side's width.
3. The increase is compensated by elongating the corresponding transition/central block.
4. The same principle applies when scaling the opposite side.
5. Product height is governed by the **highest port height**.
6. Lower-height ports use a reduced extension/flap height rather than reducing the entire product height.
7. The flap containing coupler holes is the relevant reduced extension.

These rules are explicitly documented in the supplied reference PDF. See the Unequal Tee sketch and scaling notes on pages 3–4. fileciteturn0file0L8-L24

---

# 2. Important Architecture Decision

Create a dedicated product solver:

```text
UnequalTeeScaler
```

Do **not** solve Unequal Tee by progressively adding special cases to:

```text
EqualTeeScaler
GenericTeeScaler
GenericDXFScaler
```

Do not perform blind affine scaling of the entire DXF.

Recommended flow:

```text
CMS Product Definition
        ↓
Unequal Tee Parameters
        ↓
UnequalTeeScaler
        ↓
Canonical 2D DSF geometry
        ↓
Structural geometry regeneration
        ↓
Bends / flanges / dependent geometry
        ↓
Constraint-driven feature placement
        ↓
2D validation
        ↓
KinematicFoldEngine
        ↓
3D validation
```

The **2D DSF document remains the canonical source**.

The 3D model is regenerated from the solved 2D geometry.

---

# 3. Product Separation

CMS must distinguish:

```text
Equal Tee
Unequal Tee
Equal Cross
Unequal Cross
```

For this sprint:

```text
IMPLEMENT:
    Unequal Tee

DO NOT IMPLEMENT:
    Unequal Cross
```

Do not generalize the Unequal Tee algorithm into the Unequal Cross routine yet.

The later Unequal Cross solver should be designed after the Tee geometry dependencies are understood and validated.

---

# 4. Reference Template

Reference Unequal Tee:

```text
Port 1 = 100W × 100H
Port 2 =  50W × 100H
Port 3 = 100W × 100H
```

The reference 2D sketch identifies regions:

```text
S1
S2
S3
```

These labels are useful conceptual region names, but **the agent must map the actual DXF entities to these regions before implementing transformations**.

Do not assume that a visual region in the screenshot corresponds to a single contiguous DXF entity group.

---

# 5. First Task — Inspect the Actual DXF

Before implementing scaling, inspect:

```text
unequal_tee_100x100x50x100x100x50x50.dxf
```

Build a geometry inventory.

Record for every relevant entity:

```text
entity ID
entity type
start/end points or center/radius
layer
length
orientation
connected neighbors
region/group
semantic role
```

The reference DXF contains:

```text
LINE
ARC
CIRCLE
```

Do not infer semantics from entity type alone.

An ordinary `LINE` can be:

- product edge
- bend line
- flange line
- construction/reference line
- feature boundary

---

# 6. Build a Semantic Geometry Map

The scaler should not operate directly on anonymous DXF entity indexes.

Create a semantic mapping layer.

Conceptual structure:

```dart
UnequalTeeGeometryMap {
  PortRegion port1;
  PortRegion port2;
  PortRegion port3;

  TeeRegion s1;
  TeeRegion s2;
  TeeRegion s3;

  CentralJunction junction;

  List<BendReference> bends;
  List<FlangeReference> flanges;

  List<FeatureGroup> featureGroups;

  List<GeometryConstraint> constraints;
}
```

The exact class names may follow the existing codebase, but the separation is required.

---

# 7. Geometry Categories

Every relevant geometric entity should ultimately be assigned one of these semantic categories:

```text
FIXED
PORT_BOUND
COMPENSATION
DEPENDENT
FEATURE
RIGID
REFERENCE
```

## FIXED

Geometry that does not move during the particular scaling operation.

## PORT_BOUND

Geometry directly defining a port opening/boundary.

## COMPENSATION

Geometry whose position/length changes specifically to absorb a port dimension change.

## DEPENDENT

Geometry recalculated from the solved product structure.

Examples:

- transition edges
- intersection edges
- miter geometry
- bend lines
- flange boundaries

## FEATURE

Manufacturing features attached to the structural geometry.

Examples:

- coupler slots
- holes

## RIGID

Features that must retain their own physical dimensions.

Example:

```text
8 × 12 mm coupler slot
```

must never become:

```text
10 × 15 mm
```

because a surrounding region changed.

## REFERENCE

Construction/reference entities used for calculations but not necessarily exported as manufacturing geometry.

---

# 8. Do Not Use "Stretch Everything in Region"

Avoid logic such as:

```dart
for (entity in region.entities) {
  entity.scale(...)
}
```

This is unsafe for Unequal Tee because a region may contain:

- structural edges
- bend lines
- flanges
- slots
- arcs
- rigid features

which do not all share the same scaling rule.

Instead:

```text
Port parameter change
        ↓
solve structural reference geometry
        ↓
rebuild dependent structural entities
        ↓
reposition rigid features using constraints
```

---

# 9. Product Parameters

Define a product-level parameter model.

Conceptually:

```dart
class UnequalTeeParameters {
  PortParameters port1;
  PortParameters port2;
  PortParameters port3;
}
```

Each port needs at least:

```dart
class PortParameters {
  double width;
  double height;
}
```

Additional existing product-specific parameters may be included later, for example:

```text
bend angle
sheet thickness
flange length
corner treatment
coupler-hole standard
```

Do not add new user-facing parameters unless they are supported by the actual manufacturing/template definition.

---

# 10. Canonical Template Rule

Scaling must always start from a canonical state.

Preferred:

```text
Canonical DSF
+
Requested Unequal Tee Parameters
        ↓
UnequalTeeScaler
        ↓
Solved DSF
```

Do not accumulate transformations:

```text
100
 ↓
150
 ↓
120
 ↓
180
```

Instead:

```text
Canonical
   ↓
calculate 180 directly
```

This prevents cumulative distortion.

---

# 11. Width Scaling — Fundamental Rule

Unequal Tee width scaling is **side-specific**.

Example starting state:

```text
P1 = 100
P2 = 50
P3 = 100
```

Change:

```text
P1 = 150
P2 = 50
P3 = 100
```

Expected principle:

```text
P1 width changes
P2 width remains unchanged
P3 width remains unchanged
```

The geometry between P1 and the Tee junction must be recalculated.

The supplied reference explicitly states that when one side width is increased, the other side width should not change and the increase can be compensated by elongating the appropriate block. fileciteturn0file0L15-L18

---

# 12. Compensation Region Principle

Treat S1/S2/S3 as **product-specific geometric regions**, not generic stretch zones.

Use the concept:

```text
compensationRegion
```

rather than:

```text
stretchableRegion
```

Reason:

The region's final geometry is not arbitrary.

It is a consequence of the requested port dimensions.

Conceptually:

```text
Port Widths
    ↓
Determine port boundaries
    ↓
Determine fixed references
    ↓
Calculate junction geometry
    ↓
Calculate compensation region
    ↓
Calculate dependent edges
```

The exact formula must be derived from the reference template geometry.

Do not invent an arbitrary proportional scale factor.

---

# 13. Opposite-Side Compensation

The routine must work in both directions.

Example A:

```text
P1 increases
```

Expected:

```text
P1 → changes
P3 → unchanged
P2 → unchanged
P1-side compensation region → changes
```

Example B:

```text
P3 increases
```

Expected:

```text
P3 → changes
P1 → unchanged
P2 → unchanged
P3-side compensation region → changes
```

Never hard-code:

```text
always change S3
```

Instead create an explicit mapping:

```text
Port
  ↓
Adjacent Region
  ↓
Compensation Region
  ↓
Dependent Geometry
```

---

# 14. Port 2 / Branch Width

Do not assume that Port 2 behaves identically to Port 1 or Port 3.

Port 2 is the unequal branch in the reference template.

Its width may affect:

```text
branch opening
branch side boundaries
branch intersection with the main body
adjacent miter geometry
nearby flap geometry
feature placement
```

The agent must derive the correct dependency from the reference DXF.

Implement a dedicated path:

```text
solveBranchWidth()
```

rather than blindly routing Port 2 through a left/right compensation routine.

---

# 15. Width Delta Model

For each changed port:

```text
deltaWidth = requestedWidth - baseWidth
```

Use the canonical template as the reference.

Example:

```text
base P1 width = 100
requested P1 width = 150

deltaWidth = +50
```

The solver should then determine:

```text
which reference edge moves
which compensation region absorbs deltaWidth
which dependent edges must be regenerated
which features must be repositioned
```

Do not treat deltaWidth as a universal translation distance for every entity.

---

# 16. Reference Geometry

Introduce stable construction references for the Tee.

Possible references:

```text
Port 1 centerline
Port 2 centerline
Port 3 centerline
Port opening edges
Main junction center/reference
Side transition boundaries
Flange reference edges
Bend reference lines
```

The exact references must be derived from the actual template.

These references should remain stable even if underlying DXF entity IDs change after regeneration.

---

# 17. Intersection/Junction Solver

The central Tee junction is the key part of the algorithm.

The solver must explicitly calculate:

```text
junction boundaries
transition boundaries
side-wall boundaries
miter intersections
```

after port dimensions are established.

Do not simply modify the nearest existing line.

Preferred sequence:

```text
1. Solve port dimensions.
2. Solve port boundary positions.
3. Solve junction/reference positions.
4. Solve compensation regions.
5. Intersect/trim structural boundaries.
6. Regenerate dependent bends/flanges.
7. Reattach features.
```

---

# 18. Height Scaling — Separate Routine

Width and height must be handled by separate routines.

Create:

```text
solveUnequalTeeWidth()
solveUnequalTeeHeight()
```

Do not let a generic rectangle scaler process both axes.

The reference PDF explicitly defines a different height rule for unequal ports. fileciteturn0file0L19-L24

---

# 19. Maximum-Height Rule & Derived Body Architecture

### Explicit Specification Rule
> **Port heights are independent inputs. Common body height is a derived value equal to the maximum port height:**
> 
> $$H_{\text{body}} = \max(H_1, H_2, H_3)$$
> 
> **A port's coupler area always follows its own port height, while the shared body follows the maximum. The vertical difference between the body and each port defines that port's step/notch:**
> 
> $$\text{Notch}_i = H_{\text{body}} - H_i$$

### Canonical Determination Order
The body is never independently changed by individual ports. Instead, determine the maximum first:
```dart
final bodyHeight = max(
  port1Height,
  max(port2Height, port3Height),
);
```

Then map features deterministically:
- **Body geometry** $\leftarrow$ `bodyHeight` (Left cheek wall $FL1$, right cheek wall $FL2$, back wall main web $FL3$, return flanges $F_2, F_6, F_8$)
- **P1 coupler geometry** $\leftarrow$ `port1Height` (Flap $F_0$ along $B5$, Flap $F_5$ along $B6$, slots $SLOT_9, SLOT_12$)
- **P2 coupler geometry** $\leftarrow$ `port2Height` (Flap $F_4$ along $B4$, Right ear of $F_9$, slots $SLOT_6, SLOT_7$)
- **P3 coupler geometry** $\leftarrow$ `port3Height` (Flap $F_1$ along $B7$, Left ear of $F_9$, slots $SLOT_10, SLOT_11$)

This prevents order-dependent behavior and guarantees that scaling back and forth (e.g. $50 \to 75 \to 100 \to 125 \to 75$) returns to the exact baseline-derived state without accumulated error.

### Calibrated Verification Matrix

| P1 | P2 | P3 | Body | P1 notch | P2 notch | P3 notch | Status |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| 100 | 50 | 100 | 100 | 0 | 50 | 0 | Baseline state |
| 100 | 75 | 100 | 100 | 0 | 25 | 0 | P2 coupler grows +25mm |
| 100 | 100 | 100 | 100 | 0 | 0 | 0 | Flush state (notch eliminated) |
| 100 | 125 | 100 | 125 | 25 | 0 | 25 | P2 becomes max; entire body expands to 125 |
| 125 | 100 | 100 | 125 | 0 | 25 | 25 | P1 becomes max; entire body expands to 125 |
| 100 | 100 | 125 | 125 | 25 | 25 | 0 | P3 becomes max; entire body expands to 125 |

---

# 20. Lower-Port Height Rule

If a port has:

```text
portHeight < maxHeight
```

do not reduce the entire Tee structure to that height.

Instead:

```text
heightDifference = maxHeight - portHeight
```

and reduce the relevant extension/flap height by the corresponding amount.

The supplied document specifically identifies the flap with coupler holes as the extension whose height is reduced. fileciteturn0file0L19-L24

---

# 21. Height Example

Example:

```text
P1 = 100H
P2 = 70H
P3 = 100H
```

Then:

```text
maxHeight = 100
```

Expected:

```text
overall Tee product height = 100

P1 = full height
P3 = full height

P2:
    main structural height remains referenced to maxHeight
    relevant flap/extension height = reduced by 30
```

Do NOT implement:

```text
scale P2 vertically by 0.70
```

That would distort the geometry.

---

# 22. If Multiple Ports Have Different Heights

Example:

```text
P1 = 120H
P2 = 80H
P3 = 100H
```

Then:

```text
maxHeight = 120
```

The solver must independently calculate the extension/flap reduction for:

```text
P2
P3
```

according to their height differences.

Do not assume the reference example is the only possible unequal combination.

---

# 23. Coupler Holes / Slots

Treat coupler holes as manufacturing features.

They are **not structural scaling geometry**.

Rules:

```text
slot shape = rigid
slot width = rigid
slot length = rigid
corner radius = rigid
orientation = controlled
position = constraint/reference driven
```

When a supporting flap changes:

```text
new supporting geometry
        ↓
locate feature reference
        ↓
apply preserved offsets/constraints
        ↓
move feature
```

Never apply an affine scale to coupler slots.

---

# 24. Constraint Integration

The interactive Onshape-style dimension/constraint system should complement the Unequal Tee solver.

Use constraints for secondary relationships such as:

```text
hole ↔ edge
hole ↔ hole
hole ↔ bend
slot ↔ edge
feature ↔ feature
```

The product solver determines:

```text
structural Tee geometry
```

The constraint system maintains:

```text
feature relationships
```

Architecture:

```text
UNEQUAL TEE SOLVER
        ↓
structural geometry
        ↓
feature reference geometry
        ↓
CONSTRAINT SYSTEM
        ↓
holes / slots / feature positions
```

Do not attempt to construct the entire Tee using generic interactive constraints.

---

# 25. Rigid Feature Detection

Where possible, classify manufacturing features semantically at template-learning time.

For example:

```text
FeatureRole.couplerSlot
```

or the equivalent existing enum.

Do not classify a coupler slot solely because it looks like an obround.

The CMS/template stage should preserve the semantic role.

---

# 26. Bend Lines

The user manually establishes bend lines during CMS drawing preparation.

Do not reintroduce automatic bend-line generation.

Unequal Tee scaling should **consume the existing confirmed bend structure**.

After structural geometry changes, bend references may need new coordinates, but the solver should not invent a new bend topology.

Process:

```text
Existing bend topology
        ↓
solve new boundary positions
        ↓
recalculate bend line coordinates
        ↓
validate connectivity
```

---

# 27. Flanges

The user manually establishes flange lines.

Do not introduce auto-flange-generation logic.

If flange geometry is dependent on a boundary that moved:

```text
new boundary
    ↓
move/recalculate corresponding flange geometry
```

But preserve the established flange topology and manufacturing role.

---

# 28. DSF as Source of Truth

The solved DSF should contain enough information to reproduce the scaled Tee.

Persist:

```text
Product Type = Unequal Tee
Port parameters
Geometry-stage data
Port mappings
Bend definitions
Flange definitions
Feature semantics
Constraint relationships
Scaling metadata where required
```

Do not require the original viewport state to reproduce the result.

---

# 29. Deterministic Regeneration

Given identical:

```text
base DSF
product parameters
constraint definitions
```

the solver must produce the same geometry within numerical tolerance.

Avoid random decisions.

Avoid nearest-entity heuristics when a semantic reference is available.

Prefer:

```text
semantic reference IDs
stable topology IDs
constraint anchors
```

over:

```text
nearest line
nearest point
first matching entity
```

---

# 30. Suggested Internal Pipeline

Implement conceptually:

```text
UnequalTeeScaler.scale(
    canonicalDsf,
    requestedParameters
)
```

Pipeline:

```text
A. Clone canonical geometry
B. Read current/template parameters
C. Validate requested dimensions
D. Resolve port references
E. Solve width geometry
F. Solve height geometry
G. Solve central junction
H. Solve transition geometry
I. Recalculate dependent bends
J. Recalculate dependent flanges
K. Reposition rigid features
L. Reapply feature constraints
M. Validate 2D topology
N. Commit DSF
O. Regenerate 3D
P. Validate folded topology
```

If any critical step fails:

```text
DO NOT commit the scaled geometry.
```

Return an actionable diagnostic.

---

# 31. Width Solver Pseudocode

Conceptual only — do not copy blindly:

```dart
SolvedGeometry solveWidth(
  UnequalTeeParameters base,
  UnequalTeeParameters target,
  GeometryMap map,
) {
  final delta1 = target.port1.width - base.port1.width;
  final delta2 = target.port2.width - base.port2.width;
  final delta3 = target.port3.width - base.port3.width;

  // 1. Resolve port boundary targets.
  final portTargets = solvePortBoundaries(
    base: base,
    target: target,
    map: map,
  );

  // 2. Solve each side-specific compensation region.
  final compensation = solveCompensationRegions(
    portTargets: portTargets,
    map: map,
  );

  // 3. Solve Tee junction/intersections.
  final junction = solveJunction(
    portTargets: portTargets,
    compensation: compensation,
    map: map,
  );

  // 4. Generate dependent structural geometry.
  return rebuildDependentGeometry(
    portTargets: portTargets,
    compensation: compensation,
    junction: junction,
    map: map,
  );
}
```

The implementation must be based on the actual reference geometry, not on this pseudocode's naming.

---

# 32. Height Solver Pseudocode

```dart
SolvedHeight solveHeight(
  UnequalTeeParameters target,
  GeometryMap map,
) {
  final maxHeight = max(
    target.port1.height,
    max(
      target.port2.height,
      target.port3.height,
    ),
  );

  final port1Delta = maxHeight - target.port1.height;
  final port2Delta = maxHeight - target.port2.height;
  final port3Delta = maxHeight - target.port3.height;

  // Preserve product height at maxHeight.
  // Reduce the appropriate lower-port flap/extension
  // according to the established template references.

  return solvePortHeightExtensions(
    maxHeight: maxHeight,
    deltas: [
      port1Delta,
      port2Delta,
      port3Delta,
    ],
    map: map,
  );
}
```

Again, the exact extension mapping must come from the actual DXF.

---

# 33. Do Not Invent Missing Geometry Rules

The supplied reference establishes the width compensation principle and the maximum-height/lower-flap rule.

It does **not** provide a complete mathematical formula for every DXF coordinate.

Therefore:

```text
Known from source:
    product behavior

Needs derivation:
    exact coordinate transformations
    exact compensation lengths
    exact reference anchors
    exact bend-line movement
    exact slot positioning rules
```

The agent must derive those from:

```text
reference DXF
reference 2D sketch
reference 3D model
existing TruFold geometry structures
```

If the geometry cannot be determined confidently:

```text
DO NOT GUESS
```

Instead emit a TODO/diagnostic describing the missing relationship.

---

# 34. Geometry Derivation Method

For the reference DXF:

1. Identify the three port openings.
2. Identify the sheet-metal faces represented in 2D.
3. Identify the structural edges belonging to each face.
4. Identify S1/S2/S3.
5. Identify the central junction boundaries.
6. Identify all bend lines.
7. Identify all flange boundaries.
8. Identify all coupler slots.
9. Determine which dimensions correspond to each port width/height.
10. Determine which lines move when a port dimension changes.
11. Determine which line remains fixed.
12. Determine which line absorbs the change.
13. Encode these relationships explicitly.

The objective is to obtain a relationship graph rather than a list of ad-hoc transformations.

---

# 35. Geometry Dependency Graph

The final implementation should conceptually represent:

```text
          P1 Width
             │
             ↓
       P1 boundaries
             │
             ↓
    P1 compensation region
             │
             ↓
       Tee junction
             │
      ┌──────┴──────┐
      ↓             ↓
   bends          flanges
      │             │
      └──────┬──────┘
             ↓
       dependent features
```

Similarly:

```text
          P3 Width
             │
             ↓
       P3 boundaries
             │
             ↓
    P3 compensation region
             │
             ↓
       Tee junction
```

Port 2 should have its own dependency path.

---

# 36. Multiple Parameter Changes

The solver must support changing more than one dimension in the same operation.

Example:

```text
P1:
    W = 150
    H = 120

P2:
    W = 70
    H = 80

P3:
    W = 120
    H = 100
```

Do not process this as a series of mutable transformations.

Instead:

```text
Canonical parameters
        ↓
Target parameter set
        ↓
One complete solve
```

This prevents order-dependent results.

---

# 37. Parameter Normalization

Before solving:

```text
Validate numeric values
Normalize units
Reject invalid/non-positive dimensions
Apply product-specific minimums if already defined
```

Do not silently clamp invalid product dimensions unless existing application conventions require it.

If a request cannot produce valid geometry:

```text
return ScalingError
```

with the affected parameter identified.

---

# 38. Topology Preservation

The solver must preserve expected topology.

Before scaling record:

```text
number of ports
number of structural faces
bend graph
flange graph
feature groups
```

After scaling compare the expected topology.

The objective is:

```text
geometry dimensions change
topological identity remains stable
```

unless a deliberately supported parameter combination causes a legitimate topology change.

---

# 39. 2D Validation

Implement validation checks:

### Port dimensions

```text
Measured Port 1 width == target
Measured Port 2 width == target
Measured Port 3 width == target
```

### Heights

Validate the documented max-height rule.

### Connectivity

```text
No required disconnected edge
No unintended gap
No unintended overlap
```

### Intersections

```text
No self-intersections in structural faces
No invalid line crossings
```

### Bend lines

```text
Expected bend lines present
Bend endpoints remain attached
```

### Flanges

```text
Expected flange geometry present
Flanges remain attached
```

### Features

```text
All required coupler slots remain
Slot dimensions unchanged
Slot geometry not distorted
```

---

# 40. 3D Validation

After solving 2D:

```text
Solved DSF
    ↓
KinematicFoldEngine
```

Verify:

```text
all expected faces exist
all expected folds exist
all three ports exist
port dimensions match target
no obvious self-intersection
no collapsed face
no disconnected folded face
```

The 3D model should be regenerated rather than transformed independently.

---

# 41. Failed Solve Behavior

If the solver detects:

```text
invalid intersection
negative compensation region
collapsed geometry
feature collision
broken bend
broken flange
invalid topology
```

then:

```text
do not save
do not overwrite canonical DSF
do not partially commit
```

Show an understandable error.

Example:

```text
Unable to scale Unequal Tee:
Port 2 width creates an invalid junction geometry.
No changes were saved.
```

---

# 42. Debug Visualization

During development, add a debug mode that can display:

```text
P1 region
P2 region
P3 region
S1
S2
S3
fixed references
moving references
compensation regions
bend references
flange references
coupler feature anchors
```

Also display arrows/vectors for moved reference geometry.

Example conceptual visualization:

```text
FIXED ────────────────
                      →
                 moved reference
                      →
                 compensation
```

This will make geometry errors much easier to diagnose than inspecting raw DXF coordinates.

---

# 43. Scaling Preview UX

When the user changes a dimension in the UI:

1. Update the target parameter.
2. Run a non-destructive preview solve.
3. Highlight the affected region.
4. Show changed geometry in 2D.
5. Regenerate 3D.
6. Show the corresponding affected region in 3D.
7. Only commit after validation succeeds.

The UX should remain automatic and guided.

Do not require the user to manually select dozens of geometry entities.

The user should be editing **product dimensions**, not repairing the solver.

---

# 44. Preserve User-Created Constraints

If the user has created interactive dimensions/constraints:

```text
constraint A
constraint B
constraint C
```

the scaler must respect those constraints where they are compatible with the product contract.

However:

```text
Product geometry parameters
```

remain the authoritative drivers for:

```text
port width
port height
junction geometry
overall product structure
```

A conflicting generic constraint must not silently corrupt the product solver.

Detect and report conflicts.

---

# 45. Constraint Re-solve Strategy

Recommended:

```text
1. Solve product geometry.
2. Update structural reference entities.
3. Re-evaluate constraints.
4. Move/rebuild feature geometry.
5. Validate constraints.
```

For a feature constraint:

```text
hole ↔ edge
```

the reference edge must survive scaling semantically.

Do not attach the constraint permanently to a raw DXF array index.

---

# 46. Feature Anchoring

Each rigid feature should ideally have:

```text
feature semantic ID
host region
reference entity
offset/vector
orientation rule
rigid dimensions
```

Conceptual:

```text
CouplerSlotGroup {
    hostRegion: S1
    reference: flapOuterEdge
    offset: 20
    orientation: perpendicularToReference
    size: fixed
}
```

Use the existing project conventions where available.

---

# 47. Recommended Test Matrix

Use the reference template:

```text
P1 = 100W × 100H
P2 =  50W × 100H
P3 = 100W × 100H
```

Create tests for:

## Width

```text
Test W1:
P1 100 → 150

Test W2:
P1 100 → 75

Test W3:
P3 100 → 150

Test W4:
P3 100 → 75

Test W5:
P2 50 → 75

Test W6:
P2 50 → 30
```

## Height

```text
Test H1:
P1 100 → 150

Test H2:
P1 100 → 75

Test H3:
P2 100 → 150

Test H4:
P2 100 → 75

Test H5:
P3 100 → 150

Test H6:
P3 100 → 75
```

## Combined

```text
Test C1:
P1 W + H

Test C2:
P2 W + H

Test C3:
P3 W + H

Test C4:
all three widths changed

Test C5:
all three heights changed

Test C6:
all widths and heights changed together
```

The exact expected coordinate values should be derived from the reference template and solver rules before hard-coding assertions.

---

# 48. Invariance Tests

When changing P1 width:

```text
P3 port width must remain unchanged.
```

When changing P3 width:

```text
P1 port width must remain unchanged.
```

When changing P2 width:

```text
P1/P3 widths must remain unchanged
unless a documented junction dependency specifically requires movement of non-port reference geometry.
```

When changing a lower port height:

```text
overall product maximum height remains max(port heights)
```

Coupler slot dimensions must remain unchanged in every test.

---

# 49. Round-Trip Tests

The following should work:

```text
100 → 150 → 100
```

and:

```text
100 → 75 → 100
```

The final geometry should match the canonical result within numerical tolerance.

Also test:

```text
A → B
A → C
```

directly from canonical A.

The direct A→C result must not depend on whether B was previously generated.

---

# 50. No Cumulative Distortion

Test sequence:

```text
canonical
→ 150
→ 200
→ 120
→ 80
→ canonical
```

The final result should match a fresh canonical solve.

This is a critical regression test.

---

# 51. Avoid Generic "45°" Routing

Do not route Unequal Tee entities through generic product logic merely because a line/arc contains:

```text
45
```

or because a bend angle is 45°.

Earlier scaling work showed that routing every 45° feature through another product's miter morph can distort unrelated geometry.

Unequal Tee must use its own structural references.

Only use generic bend geometry calculations where the bend topology explicitly calls for them.

---

# 52. Legacy Auto-Bend/Auto-Flange Code

Do not reactivate the old automatic:

```text
auto bend-line generation
auto flange generation
```

pipeline.

The new Unequal Tee solver assumes:

```text
bend lines were established by the user
flange lines were established by the user
```

The scaler updates their positions when necessary while preserving their semantic identity.

---

# 53. Data Migration / Backward Compatibility

Existing DSF files may not contain Unequal Tee semantic metadata.

When an existing Unequal Tee is opened:

```text
detect product type
check for semantic geometry map
```

If absent:

```text
enter guided template-learning/mapping step
```

Do not silently guess an entity mapping.

Once learned:

```text
store the semantic mapping in DSF
```

so future scaling is deterministic.

---

# 54. First-Run Learning

The first reference Unequal Tee should be used to teach the application:

```text
Port 1
Port 2
Port 3
S1
S2
S3
junction
bend lines
flanges
coupler slots
```

After the user confirms the mapping:

```text
Save learned mapping
```

Future variants of the same CMS product can reuse the product contract.

The mapping must be persistent.

---

# 55. Do Not Over-Automate Template Learning

The user has already chosen the product workflow in which:

```text
user confirms bend lines
user confirms flange lines
then application discovers/learns ports
then template scaling is taught
```

Do not introduce a large Expert/Automatic personality system.

The workflow should remain:

```text
guided
slow enough to understand
automatic after confirmation
visually highlighted
```

---

# 56. What the Agent Must NOT Do

Do not:

```text
❌ scale the complete DXF uniformly
❌ scale the folded 3D model independently
❌ stretch coupler slots
❌ modify an opposite port when the rule says it remains fixed
❌ reduce the complete product height for a lower port
❌ regenerate bends automatically from scratch
❌ generate flanges automatically
❌ guess missing geometric relationships
❌ accumulate transformations from the previously modified geometry
❌ encode the solution as dozens of entity-index-specific hacks
❌ merge Unequal Tee with Unequal Cross logic
```

---

# 57. Preferred Solver Structure

Recommended conceptual architecture:

```text
UnequalTeeProductDefinition
│
├── parameter schema
├── port definitions
├── region definitions
├── reference definitions
├── bend definitions
├── flange definitions
└── feature definitions

UnequalTeeScaler
│
├── validateParameters()
├── solveWidth()
├── solveHeight()
├── solveJunction()
├── solveCompensationRegions()
├── solveDependentGeometry()
├── solveFeatures()
└── validate()

UnequalTeeGeometryMap
│
├── ports
├── S1/S2/S3
├── references
├── junction
├── bends
├── flanges
└── features
```

Adapt this to existing TruFold architecture rather than duplicating existing CAD infrastructure.

---

# 58. Logging / Diagnostics

During development, log:

```text
Base parameters
Target parameters

Port boundary movement:
    P1
    P2
    P3

Compensation:
    region
    old dimension
    new dimension
    delta

Height:
    maxHeight
    per-port height
    extension reduction

Features:
    moved features
    preserved size
    reference used

Validation:
    port dimensions
    topology
    constraints
```

This will make it possible to understand why a generated template failed.

---

# 59. Acceptance Criteria

The Unequal Tee implementation is complete only when:

### Product separation

```text
Equal Tee and Unequal Tee use separate product logic.
```

### Width

```text
Changing one port width does not unintentionally alter another
port's actual opening width.

The required compensation occurs in the correct region.
```

### Height

```text
Overall product height follows the maximum port height.

Lower-height ports reduce the appropriate extension/flap,
not the complete product height.
```

### Features

```text
Coupler slots remain rigid.
Feature relationships remain valid.
```

### 2D

```text
No invalid intersections.
No unintended gaps.
Bend/flange topology preserved.
```

### 3D

```text
KinematicFoldEngine regenerates a valid Tee.
```

### Determinism

```text
same input → same output
```

### Reversibility

```text
canonical → modified → canonical
```

returns the canonical geometry within tolerance.

---

# 60. Recommended Development Order

Do the implementation in this exact order.

## Phase 1 — DXF audit

Map the reference DXF:

```text
ports
S1/S2/S3
junction
bends
flanges
features
```

No scaling code yet.

## Phase 2 — Semantic geometry map

Create stable semantic references.

## Phase 3 — Width solver

Implement:

```text
P1 width
P2 width
P3 width
```

with side-specific compensation.

## Phase 4 — Junction solver

Ensure the central Tee intersection regenerates correctly.

## Phase 5 — Height solver

Implement:

```text
maxHeight
lower-port flap reduction
```

## Phase 6 — Feature repositioning

Reapply coupler-slot positions and constraints.

## Phase 7 — 2D validation

Run all structural tests.

## Phase 8 — 3D regeneration

Regenerate using `KinematicFoldEngine`.

## Phase 9 — 3D validation

Verify ports/faces/bends.

## Phase 10 — UI integration

Expose product dimensions and preview behavior.

## Phase 11 — Regression tests

Run complete width/height/combined/round-trip matrix.

---

# 61. Critical Design Rule for Future Unequal Cross

Do not implement Unequal Cross now.

However, structure the Tee implementation so the following architectural concepts can be reused:

```text
Product Parameters
        ↓
Semantic Port Definitions
        ↓
Reference Geometry
        ↓
Side-specific Geometry Solver
        ↓
Compensation Regions
        ↓
Central Junction Solver
        ↓
Dependent Bend/Flange Geometry
        ↓
Feature Constraints
```

The future Unequal Cross solver will likely need:

```text
side A
side B
side C
side D
```

and a more complex central junction dependency graph.

The Tee solver should therefore be clean enough that the future Cross solver can reuse the **framework**, while retaining independent geometry rules.

---

# 62. Important Implementation Philosophy

The goal is not:

> "Make the existing DXF look stretched correctly."

The goal is:

> **"Reconstruct the correct manufacturing geometry from the Unequal Tee's product dimensions."**

That distinction should guide every implementation decision.

The application is not merely editing a drawing.

It is learning a **parametric manufacturing template**.

For Unequal Tee:

```text
Port dimensions
      ↓
manufacturing geometry
      ↓
flat pattern
      ↓
folded product
```

That is the correct direction of dependency.

---

# 63. Final Agent Instruction

Before writing the solver, inspect the actual reference DXF and document the exact semantic mapping.

Create a development note containing:

```text
Port 1:
    boundary entities
    center/reference
    connected regions

Port 2:
    boundary entities
    center/reference
    connected regions

Port 3:
    boundary entities
    center/reference
    connected regions

S1:
    entities
    fixed references
    compensation behavior

S2:
    entities
    fixed references
    compensation behavior

S3:
    entities
    fixed references
    compensation behavior

Junction:
    reference entities
    intersection rules

Bends:
    semantic IDs
    dependency rules

Flanges:
    semantic IDs
    dependency rules

Coupler slots:
    semantic IDs
    anchor/reference rules
```

Only after this mapping is confirmed should the actual transformation formulas be implemented.

**Do not guess the missing formulas.**

Derive them from the supplied Unequal Tee template and the established manufacturing relationships.

Once the Unequal Tee solver passes the complete validation matrix, use its architecture and lessons to design the separate **Unequal Cross** solver.
