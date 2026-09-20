# TruFold Studio — Interactive Constraint Dimensioning for CMS Template Scaling

## Purpose

Implement an Onshape-style interactive dimension and constraint tool that allows the user to teach TruFold Studio how geometry is related during template scaling.

This is not only a measurement/annotation feature.

A dimension created during template teaching should become a **persistent geometric constraint** that the CMS scaling engine can use later to decide:

- what moves
- what stays fixed
- what moves together
- what moves relative to an edge
- what moves relative to another feature
- what dimension changes when a master parameter changes

> **A dimension created during template teaching expresses design intent, not just a measurement.**

For example:

```text
Hole A ───────── Hole B
          50 mm
```

should mean:

```text
Distance(Hole A, Hole B) = 50 mm
```

and not merely that the two holes happened to be 50 mm apart in the original drawing.

---

# 1. Why This Is Important for CMS Template Scaling

The CMS scaling engine must understand geometric relationships rather than applying generic coordinate stretching.

Bad behavior:

```text
Width increases
      ↓
Entire cheek stretches
      ↓
Hole positions distort
```

Desired behavior:

```text
Width increases
      ↓
Structural geometry changes
      ↓
Constraint network re-solves
      ↓
Holes move only along permitted directions
      ↓
Hole-to-edge / hole-to-hole relationships remain valid
      ↓
Rigid punch geometry remains undistorted
```

For example:

```text
Outer Edge
    │
   15 mm
    │
  Hole A
    │
   50 mm
    │
  Hole B
```

When the template changes size:

```text
Outer Edge moves
        ↓
Hole A remains 15 mm from edge
        ↓
Hole B remains 50 mm from Hole A
```

The holes should not independently stretch.

---

# 2. User Workflow

Activate:

```text
Dimension / Constraint Tool
```

Interaction:

```text
Click Entity A
      ↓
Move Cursor
      ↓
Dynamic dimension preview
      ↓
Click Entity B
      ↓
Dimension / constraint created
      ↓
Editable badge appears immediately
      ↓
User enters exact value
      ↓
Constraint is committed
      ↓
Geometry solves
      ↓
Constraint remains attached to entities
```

The experience should be simple and Onshape-like without exposing internal solver complexity.

---

# 3. Supported Snap Entities

## Hole / Punch

Snap to:

```text
Center
```

Visual indicator:

```text
⊙ Hole Center
```

The anchor should resolve to the punch's actual geometric center.

---

## Circle / Arc

Support:

```text
Center
Start Point
End Point
Arc Midpoint
Quadrant
```

Use appropriate snap indicators.

---

## Line / Edge / Bend

Support:

```text
Endpoint 1
Endpoint 2
Midpoint
Perpendicular projection
```

Visual indicators:

```text
• Endpoint
⌖ Edge Midpoint
⊥ Perpendicular
```

The application should prefer the most meaningful snap based on cursor location.

---

# 4. Two-Click Dimension Creation

When the Dimension Tool is active:

### Click 1

Store:

```text
entityAId
anchorTypeA
pointA
```

### Cursor movement

Render:

```text
Rubberband dimension line
+
Extension/witness lines
+
Arrowheads
+
Live distance badge
```

The measurement updates continuously.

### Click 2

Store:

```text
entityBId
anchorTypeB
pointB
```

Immediately create the dimension constraint.

Then immediately activate the inline editable badge.

---

# 5. Inline Editable Badge

The badge should appear directly on or near the dimension line.

Example:

```text
        50.00 mm
Hole A ───────── Hole B
```

The user types:

```text
60
```

and presses:

```text
Enter
```

Result:

```text
Hole A ───────────── Hole B
          60 mm
```

Geometry updates immediately.

### Escape

Pressing `Esc` cancels the edit and leaves geometry unchanged.

---

# 6. Dimension vs Constraint

Every dimension has two conceptual roles:

### Reference Dimension

Shows the current measurement without driving geometry.

### Driving Constraint

Defines the required value and drives geometry.

CMS template teaching should primarily use **driving constraints**.

A reference dimension can still be useful for inspection.

Do not confuse a displayed measurement with a persistent relationship.

---

# 7. Persistent Dimension Data

Extend `CadDimension` so the dimension can resolve its anchors against the live document.

Suggested metadata:

```text
entityAId
entityBId

anchorTypeA
anchorTypeB

measurementType

value

isDriving

referenceEntityId
drivenEntityId

drivingMode
allowedMotion
```

Potential anchor types:

```text
center
midpoint
endpoint
startPoint
endPoint
arcMidpoint
quadrant
perpendicular
```

Potential measurement types:

```text
holeToHole
holeToEdge
centerToCenter
edgeToEdge
aligned
```

Use enums / typed structures consistent with the existing architecture.

---

# 8. Driving Priority

The solver must determine which geometry is allowed to move.

Do **not** simply implement:

```text
Always move Entity B
```

because CMS templates commonly contain multiple interdependent constraints.

Instead define:

```text
referenceEntity
drivenEntity
allowedMotion
```

and inspect the existing degrees of freedom before solving.

---

## Case A — Hole to Fixed Edge

Example:

```text
Edge
 │
25 mm
 │
Hole
```

Changing:

```text
25 → 30
```

should move the hole.

```text
Edge = fixed/reference
Hole = driven
Motion = edge normal
```

---

## Case B — Hole to Bend

If the bend is fixed:

```text
Bend
 │
20 mm
 │
Hole
```

Changing the distance moves the hole relative to the bend.

---

## Case C — Hole to Hole

Example:

```text
Hole A ───── Hole B
     50 mm
```

If Hole A is the reference and Hole B is movable:

```text
Hole A = reference
Hole B = driven
Motion = along valid constraint direction
```

Changing:

```text
50 → 75
```

moves Hole B to satisfy the new distance.

However, before moving B, the solver must inspect B's other constraints.

---

## Case D — Two Constrained Holes

Example:

```text
Edge
 │ 15
Hole A
 │ 50
Hole B
```

The solver should preserve both relationships.

Changing sidewall height may move the edge:

```text
Edge moves
   ↓
Hole A maintains 15 mm
   ↓
Hole B maintains 50 mm from Hole A
```

This must be solved as a network, not as independent hole translations.

---

## Case E — Edge/Bend to Edge/Bend

Example:

```text
Bend B1 ───── Bend B2
       100 mm
```

The system should drive the appropriate structural geometry or linked parameter.

It must not blindly translate a bend if the relationship is controlled by a higher-level CMS parameter.

---

# 9. Allowed Motion

Each constraint should determine a valid motion direction.

Examples:

```text
Hole → Edge
Allowed motion:
  Edge normal
```

```text
Hole → Hole
Allowed motion:
  Constraint vector
```

```text
Hole → Centerline
Allowed motion:
  Normal to centerline
```

```text
Edge → Edge
Allowed motion:
  Associated structural parameter
```

This prevents unintended movement.

---

# 10. Constraint Network

The system should model relationships as a network.

Example:

```text
          Outer Edge
               │
              15
               │
             Hole A
               │
              50
               │
             Hole B
```

Conceptually:

```text
OuterEdge
   │
   └── distance = 15 ──> HoleA
                           │
                           └── distance = 50 ──> HoleB
```

During scaling:

```text
Template Parameter Changes
          ↓
Constraint Network Re-solves
          ↓
Hole A moves correctly
          ↓
Hole B follows correctly
```

This is the intended CMS behavior.

---

# 11. Constraint Precedence

Recommended authority hierarchy:

```text
1. Fixed geometry / explicit anchors
2. CMS structural constraints
3. User-created driving constraints
4. Derived geometry
5. Reference dimensions
```

The exact solver implementation may differ, but the system must avoid allowing a newly created dimension to unexpectedly destroy a higher-level structural relationship.

When constraints conflict, do not silently distort geometry.

Show:

```text
Constraint conflict

These dimensions cannot all be satisfied.

[ Review Constraints ]
```

and leave the document in the last valid state.

---

# 12. CMS Template Scaling Integration

This tool is primarily part of **Stage 3 — Template Scaling**.

The overall CMS workflow becomes:

```text
STAGE 1
Manufacturing Definition
        ↓
User defines:
  Bends
  Flanges
  Couplers

STAGE 2
Port Mapping
        ↓
Application:
  Fold 3D
  Find openings
  Map ports

STAGE 3
Template Scaling
        ↓
User teaches:
  Dimensions
  Constraints
  Feature relationships

        ↓
Scaling Engine
        ↓
Parameter model
+
Constraint graph
+
Protected features
```

Therefore the interactive dimension tool is one of the mechanisms by which the user teaches the application the scaling behavior.

---

# 13. Example — Riser Scaling

The user may teach a riser with:

```text
B1 ↔ B2 = W

Outer Edge ↔ Coupler Hole = 15

Hole A ↔ Hole B = 50
```

The template understands:

```text
W = primary parameter

Hole setback = 15 mm
Hole pitch = 50 mm
```

When the template changes:

```text
Primary parameter
      ↓
Structural geometry changes
      ↓
Constraints re-solve
      ↓
Holes move along permitted directions
      ↓
Coupler slots remain rigid
      ↓
3D model regenerates
```

This is preferable to manually writing special coordinate rules for every hole.

---

# 14. Coupler Holes and Constraints

A coupler slot may have both:

```text
Semantic Feature Identity
+
Geometric Constraints
```

Example:

```text
Coupler Slot A
  ├── role = coupler
  ├── rigid size
  ├── setback from edge = 15 mm
  └── pitch to Slot B = 50 mm
```

Scaling should preserve:

- slot length
- slot width
- slot orientation
- coupler semantic role
- host face/cheek association
- edge setback constraints
- hole-to-hole pitch constraints

The punch geometry should normally move as a rigid feature rather than deform.

---

# 15. Hole Groups

The system should allow multiple holes/punches to participate in a relationship.

Example:

```text
Coupler Group
├── Slot A
├── Slot B
├── Slot C
└── Slot D
```

Possible relationships:

```text
Slot A → Slot B = 50 mm
Slot B → Slot C = 50 mm
Slot C → Slot D = 50 mm
```

Or a group can be governed by:

```text
Pattern spacing = 50 mm
Count = 4
```

The initial dimension tool does not need to implement a full pattern system, but its data model should not prevent future feature-pattern constraints.

---

# 16. User Experience

Recommended interaction:

```text
Select Dimension Tool
        ↓
Hover entity
        ↓
Snap indicator appears
        ↓
Click
        ↓
Move cursor
        ↓
Dynamic dimension preview
        ↓
Hover second entity
        ↓
Snap indicator
        ↓
Click
        ↓
Editable badge
        ↓
Type value
        ↓
Enter
        ↓
Geometry solves
```

Do not show equations or solver terminology during normal use.

Keep complexity inside the engine.

---

# 17. Visual Language

### Hover

Use clear visual indicators:

```text
⊙ Hole Center
⌖ Edge Midpoint
• Endpoint
⊕ Arc Center
⊥ Perpendicular
```

### Selected

Highlight:

```text
dimension line
anchors
associated geometry
```

### Driving constraint

Make it visually distinct from a reference dimension.

### Solved

Briefly highlight the affected 2D geometry and corresponding 3D geometry.

This should match the established TruFold guided-workflow language.

---

# 18. Undo / Redo

Every dimension action must participate in the existing undo/redo system.

Supported operations:

```text
Create constraint
Edit value
Delete constraint
Convert reference → driving
Convert driving → reference
```

Undo must restore both:

```text
Constraint state
+
Geometry state
```

---

# 19. DSF Persistence

The DSF must store constraints so the template remains intelligent after reopening.

Conceptual example:

```json
{
  "dimensions": [
    {
      "id": "DIM_001",
      "entityA": "PUNCH_A",
      "anchorA": "center",
      "entityB": "PUNCH_B",
      "anchorB": "center",
      "measurementType": "holeToHole",
      "value": 50.0,
      "isDriving": true,
      "drivingMode": "alongConstraintVector"
    }
  ]
}
```

Use the existing DSF versioning/backward-compatibility strategy.

Old DSF files that contain no dimensions/constraints must remain valid.

---

# 20. Stable Entity References

Constraints must use stable entity identifiers.

Avoid relying on:

```text
array index
DXF primitive position
temporary vertex index
mesh face index
```

Prefer persistent IDs such as:

```text
PUNCH_A
EDGE_B1
BEND_B2
ARC_03
```

When geometry regenerates during scaling, the constraint system must resolve the stable ID against the regenerated live geometry.

---

# 21. Direct Dimension Driver

Extend:

```text
DirectDimensionDriver
```

to support:

### Hole-to-Hole

Move the driven punch along the permitted constraint direction.

### Hole-to-Edge

Move the punch along the edge normal.

### Arc-to-Line

Move the appropriate center/linked geometry according to allowed degrees of freedom.

### Endpoint-to-Edge Midpoint

Adjust the endpoint or the associated structural length.

### Structural Edge-to-Edge

Drive the linked structural parameter when one exists.

The driver must respect the constraint graph before applying movement.

---

# 22. Solver Safety

Before committing a driving value:

1. Resolve both anchors.
2. Determine the measured distance.
3. Determine valid motion.
4. Inspect existing constraints.
5. Check feasibility.
6. Apply the requested change.
7. Re-solve dependent constraints.
8. Validate resulting geometry.
9. Commit only if the resulting state is valid.

If the target value cannot be satisfied:

```text
Unable to satisfy this dimension.
```

Do not leave partially modified geometry.

---

# 23. Automated Tests

Create:

```text
test/modules/sheet_metal_studio/cad_dimension_interactive_test.dart
```

Test:

## Snap

- punch center
- circle center
- arc center
- arc endpoints
- edge midpoint
- line endpoints
- perpendicular projection

## Dimension creation

- two-click interaction
- rubberband preview
- dimension categorization
- inline badge activation

## Driving geometry

- hole-to-hole distance
- hole-to-edge setback
- endpoint-to-edge
- structural edge relationship

## Constraint persistence

- save constraint
- reopen DSF
- resolve stable entity IDs
- restore driving behavior

## Solver behavior

- one movable feature
- two movable punches
- constrained punch chain
- fixed reference geometry
- conflict detection

## Undo/Redo

Verify both geometry and constraint state.

---

# 24. Manual Verification

## Basic Hole-to-Hole

1. Open the unfolded 2D canvas.
2. Activate Dimension Tool.
3. Hover over Hole 1.
4. Verify hole-center snap indicator.
5. Click Hole 1.
6. Move to Hole 2.
7. Verify dynamic dimension preview.
8. Click Hole 2.
9. Verify editable badge.
10. Enter `60`.
11. Press Enter.
12. Verify exact 60 mm center-to-center distance.
13. Verify the dimension remains present as a driving constraint.

---

## Hole-to-Edge

1. Select Dimension Tool.
2. Click hole center.
3. Click the edge.
4. Enter a setback.
5. Verify hole moves normal to edge.
6. Verify slot shape and orientation remain rigid.

---

## Constraint Chain

Create:

```text
Edge → Hole A = 15
Hole A → Hole B = 50
```

Then change the edge/structural dimension.

Expected:

```text
Hole A remains 15 mm from edge.
Hole B remains 50 mm from Hole A.
```

---

# 25. CMS Teaching Workflow

The complete teaching workflow should be:

```text
STEP 1 — MANUFACTURING

User defines:
  ✓ Bend lines
  ✓ Flange lines
  ✓ Coupler holes

Save DSF

        ↓

STEP 2 — PORT MAPPING

Application:
  ✓ Fold 3D
  ✓ Find physical openings
  ✓ Map ports
  ✓ Store port mappings

Save DSF

        ↓

STEP 3 — TEMPLATE SCALING

User teaches:
  ✓ Dimensions
  ✓ Hole positions
  ✓ Feature relationships
  ✓ Structural relationships

Application:
  ✓ Builds dependency graph
  ✓ Builds parameter model
  ✓ Solves constraints
  ✓ Validates scaling

Save complete CMS template
```

The dimension/constraint tool is a primary Stage 3 teaching mechanism.

---

# 26. Important Architecture Rule

The template must not remember only:

```text
Where the hole was.
```

It must remember:

```text
Why the hole was there.
```

Bad template information:

```text
Hole X = 143.2
Hole Y = 62.7
```

Better:

```text
Hole is 15 mm from outer edge.
Hole is 50 mm from previous coupler hole.
Hole moves with the host cheek.
Hole remains rigid.
```

That is the information needed by the scaling engine.

---

# 27. Relationship Between CMS Parameters and Constraints

A complete template should eventually have:

```text
CMS Parameter
      ↓
Geometric Dependency
      ↓
Constraint
      ↓
Entity Motion
```

Example:

```text
Width = 150
      ↓
B1 ↔ B2 = Width
      ↓
Floor / cheek structure updates
      ↓
Coupler constraints re-solve
      ↓
Ports update
      ↓
3D model regenerates
```

Do not duplicate the same relationship as unrelated hard-coded rules in multiple scaling routines.

Where a relationship has been taught through an interactive constraint, the scaling engine should use that persistent constraint rather than creating another independent coordinate rule.

---

# 28. Design for Reuse Across CMS Products

The constraint engine must be generic.

Do not create:

```text
45DegreeRiserHoleSolver
UnequalTeeHoleSolver
ReducerHoleSolver
```

for every product.

Instead use:

```text
Generic Constraint Engine
        +
CMS Product Definition
        +
Persistent Template Constraints
```

The 45° riser, tee, cross, reducer, bend, trunking accessory, etc. should reuse the same fundamental constraint machinery.

Product-specific logic should define:

- expected geometry
- primary parameters
- semantic port rules
- allowed structural relationships

The constraint engine determines how constrained entities move within those relationships.

---

# 29. Final Objective

The final user experience should feel extremely simple:

```text
User clicks two things
        ↓
Dimension appears
        ↓
User types value
        ↓
Geometry moves
        ↓
TruFold remembers the relationship
```

Later:

```text
User changes Width / Height / Branch Dimension
        ↓
Template parameters change
        ↓
Constraint graph re-solves
        ↓
Only permitted geometry moves
        ↓
Constrained holes follow correctly
        ↓
Protected features remain rigid
        ↓
Ports remain associated
        ↓
3D regenerates
```

## Final rule

> **Dimensions teach the template how geometry is related.**
>
> **Constraints preserve those relationships during scaling.**
>
> **The scaling engine moves only the geometry that is permitted to move.**
>
> **The user should never have to manually reposition every hole after changing a template dimension.**
