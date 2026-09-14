# 3D CAD Studio — Phase 1 Implementation Guide
## Professional 2D Sheet-Metal CAD, Constraint-Based Templates, and Intelligent DXF Modification

**Status:** Implementation specification for the coding agent  
**Phase:** Phase 1  
**Future phase:** Phase 2 — parametric cable-tray/product generation  
**Explicit scope decision:** Ladder products and ladder accessories are excluded from this document and from the current implementation scope.

---

## 1. Purpose

Extend the existing **3D CAD Studio** into a professional sheet-metal CAD application.

The application already contains substantial working functionality, including:

- 2D CAD editing
- 3D CAD/model generation
- sheet-metal features
- DXF import/export
- DSF import/export
- existing template/design functionality
- existing CAD feature implementations

**Do not rebuild the CAD application.**

The coding agent must first audit the existing code, then reuse and extend it. Replace existing functionality only when there is a clear technical reason.

The primary new capability is a practical **2D constraint + parameter + dependency system** that converts existing DXF product drawings into intelligent, reusable templates.

---

# 2. Product Vision

The long-term objective is:

> **Do not create thousands of static DXF files for every dimensional variation. Create intelligent templates in which geometry is controlled by parameters, constraints, dependencies, patterns and sheet-metal rules.**

The target workflow is:

```text
Existing DXF
    ↓
Import
    ↓
Analyze geometry
    ↓
Clean/repair if required
    ↓
Identify main body
    ↓
Identify edges / references
    ↓
Identify holes / cutouts / bend lines
    ↓
Add constraints
    ↓
Add dimensions
    ↓
Create named parameters
    ↓
Create dependencies
    ↓
Create patterns
    ↓
Save intelligent template
    ↓
Enter new dimensions
    ↓
Recalculate constrained geometry
    ↓
Update sheet-metal features
    ↓
Update flat pattern
    ↓
Update 3D
    ↓
Validate
    ↓
Export DXF / DSF
    ↓
Generate DDS/TDS
```

This is **not simple DXF scaling**.

---

# 3. Current Product Scope

Phase 1 covers generic sheet-metal CAD and existing/predefined product templates for:

### Cable tray products/accessories

- Cable trays
- Cable tray covers
- 90° bends
- 45° bends where applicable
- Tees
- Unequal tees
- Crosses
- Unequal crosses
- Reducers
- Risers
- Couplers
- End-related sheet-metal components where applicable

### Trunking products/accessories

- Straight trunking
- Trunking covers
- Bends
- Tees
- Crosses
- Reducers
- Other sheet-metal accessories

### Generic sheet-metal parts

Any other flat DXF-based sheet-metal component that benefits from constraints and parameters.

### Explicitly excluded

Do **not** implement ladder or ladder accessories in this phase:

- ladder side rails
- ladder rungs
- ladder bends
- ladder tees
- ladder crosses
- ladder assemblies

Ladder can be addressed later as a separate product/assembly work package.

---

# 4. Critical Principle — Do Not Rebuild Existing CAD

The existing 3D CAD Studio has already implemented much of the CAD functionality.

Before writing new code, inspect:

- geometry classes
- sketch/editor
- selection
- snapping
- dimensions
- constraints, if any
- feature tree
- sheet-metal features
- bend system
- hole system
- patterns
- 2D rendering
- 3D rendering
- DXF importer/exporter
- DSF serializer/deserializer
- template system
- undo/redo
- application state
- recalculation/update pipeline

Create an audit:

```text
Feature
---------
Already implemented
Partially implemented
Missing
Needs modification
Needs integration
Potential conflict
```

The first deliverable should be an internal/current-architecture document before major new implementation begins.

**Never create a second geometry engine when the current one can be extended.**

---

# 5. Why Global DXF Scaling Is Not Enough

Do NOT implement:

```text
newWidth / oldWidth
        ↓
scale entire DXF
```

That approach will incorrectly change manufacturing-critical geometry.

For example, when a tray changes from 300 mm to 600 mm:

### Usually variable

- overall width
- side-wall positions
- bend positions
- branch locations
- pattern extent
- derived transition geometry

### Often fixed

- hole diameter
- obround dimensions
- bend radius
- flange height
- edge clearance
- material thickness
- certain hole pitches

Therefore the correct architecture is:

```text
Parameters
    ↓
Constraints
    ↓
Dependency graph
    ↓
Geometry regeneration
```

---

# 6. The Constraint System

The new constraint system should be inspired by the usability of professional sketchers such as Fusion 360 and Onshape, but **must remain intentionally smaller and simpler at first**.

The goal is not to reproduce every professional CAD constraint.

The goal is to support the relationships required for intelligent sheet-metal templates.

Examples:

```text
This hole is 25 mm from the left edge.
```

```text
These two holes are horizontally aligned.
```

```text
These two holes are symmetric about the centerline.
```

```text
These two circles have the same diameter.
```

```text
This edge is parallel to that edge.
```

```text
This feature is centered on the part.
```

These relationships must survive dimensional changes.

---

# 7. Constraint Types

## 7.1 Geometric constraints — initial set

Implement:

1. Coincident
2. Horizontal
3. Vertical
4. Parallel
5. Perpendicular
6. Collinear
7. Concentric
8. Equal
9. Symmetric
10. Fixed
11. Tangent

Prioritize the most useful constraints first.

## 7.2 Dimensional constraints — initial set

Implement:

1. Horizontal distance
2. Vertical distance
3. Aligned distance
4. Point-to-point distance
5. Radius
6. Diameter
7. Angle

Advanced dimension types can be added later:

- arc length
- center-to-center
- baseline dimensions
- chain dimensions
- coordinate dimensions

Do not delay the first template milestone for advanced dimensions.

---

# 8. Solver Scope

Do not attempt to build a massive nonlinear CAD solver immediately.

## Solver V1

```text
Coincident
Horizontal
Vertical
Distance
Radius
Diameter
Concentric
Parallel
Perpendicular
```

## Solver V2

```text
Equal
Symmetric
Tangent
Angle
Collinear
Fixed
```

The solver should report at minimum:

```text
Solved
Under-constrained
Over-constrained
Conflict
```

A detailed degrees-of-freedom engine can be improved later.

---

# 9. Stable Geometry References

Constraints must never rely on array indexes.

Do NOT store:

```text
lineIndex = 27
circleIndex = 18
```

Use stable entity IDs and sub-references.

Examples:

```text
Line001.start
Line001.end
Line001.edge

Circle001.center
Circle001.edge

Arc001.start
Arc001.end
Arc001.center
Arc001.edge
```

This is essential because template geometry may be regenerated and reordered.

---

# 10. Constraint Data Model

Conceptually:

```text
Constraint
├── id
├── type
├── entityReferences[]
├── value
├── parameterId
├── mode
├── suppressed
└── metadata
```

Example:

```text
Constraint {
    id: "C-001",
    type: "Distance",
    references: [
        "Hole001.center",
        "EDGE_LEFT"
    ],
    value: 25,
    mode: "driving"
}
```

Use the existing Dart/domain architecture wherever possible.

---

# 11. Driving vs Reference Dimensions

Support two modes.

## Driving

Controls geometry:

```text
WIDTH = 300 mm
```

## Reference

Reports geometry:

```text
Calculated spacing = 47.50 mm
```

A reference dimension must not drive geometry.

---

# 12. Construction and Reference Geometry

This is a critical part of the template system.

Support:

- construction line
- centerline
- construction point
- reference edge
- reference axis
- construction circle where useful

Construction geometry must not become manufacturing geometry.

Example:

```text
PART EDGE
──────────────────────────────

             - - - - - -
               CENTERLINE

──────────────────────────────
PART EDGE
```

The user should be able to constrain normal geometry to construction geometry.

---

# 13. Part Reference System

Each intelligent template should have stable references.

At minimum:

```text
ORIGIN
X_AXIS
Y_AXIS
CENTER_X
CENTER_Y
EDGE_LEFT
EDGE_RIGHT
EDGE_TOP
EDGE_BOTTOM
```

Where actual product geometry makes those references meaningful.

These references are much more robust than raw coordinates.

---

# 14. Centerline Workflow

The engineer should be able to:

1. Create a centerline.
2. Position it relative to the part.
3. Name it if necessary.
4. Use it as a constraint reference.

Example:

```text
             CENTER_X
────────────────────┼────────────────────
                    │
       ○            │            ○
                    │
```

Then apply:

```text
Symmetric(HoleLeft, HoleRight, CENTER_X)
```

If width changes, the holes remain symmetric.

---

# 15. Constraint UI

Extend the existing 2D editor rather than replacing it.

Suggested command groups:

```text
SKETCH

CREATE
Line | Polyline | Rectangle | Circle | Arc | Slot

REFERENCE
Construction | Centerline | Point

MODIFY
Trim | Extend | Fillet | Chamfer | Offset | Mirror

CONSTRAINTS
Coincident
Horizontal
Vertical
Parallel
Perpendicular
Concentric
Equal
Symmetric
Tangent
Fixed

DIMENSIONS
Distance
Horizontal
Vertical
Radius
Diameter
Angle

PATTERN
Linear
Rectangular

INSPECT
Measure
Show Constraints
Hide Constraints
```

The exact toolbar arrangement should follow the existing application's visual language.

---

# 16. Constraint Symbols

Show constraint symbols on the sketch.

Suggested semantics:

```text
Horizontal       ─
Vertical         │
Coincident       ●
Concentric       ◎
Parallel         //
Perpendicular    ⊥
Equal            =
Symmetric        ◇
Fixed            lock
```

The exact iconography may differ.

Consistency and readability are the important requirements.

---

# 17. Constraint Editing

Selecting a constraint should expose:

```text
Constraint
----------------
Type: Distance

References:
Hole001.center
EDGE_LEFT

Value:
25.00 mm

Mode:
Driving

[Edit]
[Delete]
```

Double-clicking a dimensional annotation should allow direct value editing.

---

# 18. Basic Constraint Examples

## Hole to edge

```text
EDGE_LEFT
│
│   25
│   ─────○
```

Internal relationship:

```text
Distance(Hole001.center, EDGE_LEFT) = 25
```

## Hole to hole

```text
○────────○
```

Relationships:

```text
Horizontal
Distance = 50 mm
```

## Symmetric holes

```text
○────────│────────○
         CENTER_X
```

Relationship:

```text
Symmetric
```

## Concentric geometry

```text
Outer circle
    ◎
Inner circle
```

Relationship:

```text
Concentric
```

---

# 19. Hole Geometry Must Be First-Class

Imported circles should be convertible to actual hole objects.

Conceptually:

```text
Hole
├── id
├── center
├── type
├── dimensions
├── orientation
├── constraints
└── patternMembership
```

Support:

- round
- slot
- obround
- rectangle
- square
- custom profiles where required

Reuse the existing hole implementation if it already exists.

---

# 20. Hole Patterns

Do not constrain hundreds of holes individually if the relationship can be represented as a pattern feature.

Initial patterns:

- Linear
- Rectangular
- Equal spacing
- Symmetric
- Along edge where useful

Conceptually:

```text
Pattern
├── seed
├── direction
├── count
├── spacing
├── startOffset
└── endOffset
```

Example:

```text
○   ○   ○   ○   ○   ○
```

is better represented by a pattern than six unrelated circles.

---

# 21. Template Design Intent

A template must distinguish between:

### Fixed

```text
HOLE_DIAMETER = 10
EDGE_OFFSET = 25
PITCH = 50
```

### Parameter-driven

```text
PART_WIDTH = WIDTH
```

### Derived

```text
CENTER_X = WIDTH / 2
```

### Pattern-driven

```text
HOLE_COUNT
HOLE_SPACING
```

The template author controls the intended behavior.

The software must not guess design intent when there are multiple valid interpretations.

---

# 22. Parameter System

Initial parameter types:

```text
Length
Angle
Integer
Boolean
Enum
```

Examples:

```text
WIDTH          Length
HEIGHT         Length
LENGTH         Length
THICKNESS      Length
BEND_ANGLE     Angle
HOLE_COUNT     Integer
HAS_COVER      Boolean
MATERIAL       Enum
```

---

# 23. Named Parameters

Expose human-readable parameters.

Instead of:

```text
Constraint C17 = 300
```

the user should see:

```text
WIDTH = 300 mm
```

Then:

```text
Distance(EDGE_LEFT, EDGE_RIGHT) = WIDTH
```

This is the foundation of reusable templates.

---

# 24. Expressions

Start with a small expression system.

Support:

```text
+
-
*
/
()
```

Examples:

```text
CENTER = WIDTH / 2
```

```text
BRANCH_OFFSET = MAIN_WIDTH / 2 - BRANCH_WIDTH / 2
```

```text
AVAILABLE_LENGTH = LENGTH - 2 * EDGE_OFFSET
```

Do not initially build a large programming language.

---

# 25. Dependency Graph

Parameters and features require explicit dependencies.

Example:

```text
WIDTH
 │
 ├── RIGHT EDGE
 ├── CENTER_X
 ├── HOLE PATTERN
 ├── SIDE BEND
 └── 3D MODEL
```

For a tee:

```text
MAIN_WIDTH
 │
 ├── Main body
 ├── Main holes
 └── Main bends

BRANCH_WIDTH
 │
 ├── Branch body
 ├── Branch holes
 └── Branch bends

HEIGHT
 │
 └── Side walls
```

---

# 26. Recalculation Pipeline

There must be one authoritative update pipeline:

```text
Parameter Change
       ↓
Update Parameter Store
       ↓
Mark Dependencies Dirty
       ↓
Solve Constraints
       ↓
Update Sketch Geometry
       ↓
Update Feature Geometry
       ↓
Update Holes / Patterns
       ↓
Update Bends
       ↓
Update Flat Pattern
       ↓
Update 3D
       ↓
Update Dimensions
       ↓
Run Validation
       ↓
Update DSF State
```

Do not allow UI widgets to independently perform unrelated pieces of this calculation.

---

# 27. Incremental Recalculation

Use:

```text
Dirty Flags
Dependency Graph
Incremental Recalculation
Caching
```

If WIDTH changes, only affected geometry/features should recalculate.

Do not rebuild the entire CAD model for every mouse movement or parameter edit.

---

# 28. DXF → Intelligent Template Workflow

Provide a dedicated workflow:

```text
Import DXF
 ↓
Analyze geometry
 ↓
Define main body
 ↓
Define reference edges
 ↓
Identify holes/features
 ↓
Add construction geometry
 ↓
Add constraints
 ↓
Add dimensions
 ↓
Create parameters
 ↓
Create patterns
 ↓
Test
 ↓
Save template
```

The engineer should not have to redraw an existing DXF.

---

# 29. DXF Analysis

After import, show useful diagnostics:

```text
Lines:             120
Arcs:               14
Circles:            80
Polylines:           6
Closed profiles:     2
Possible bends:      8
Duplicate entities:  0
Gaps:                0
```

The exact statistics depend on the actual file.

Automatic recognition may suggest:

- outer boundary
- holes
- cutouts
- bend lines
- repeated patterns
- reference edges

The user must be able to override recognition.

Never silently alter source manufacturing geometry.

---

# 30. Main Body Definition

Provide:

> Define Main Body

The engineer selects the main profile.

Associate:

```text
Outer Boundary
Inner Cutouts
Holes
Bends
Features
```

with that part.

---

# 31. Reference Edge Definition

The engineer can select:

```text
Left Edge
Right Edge
Top Edge
Bottom Edge
```

and the system assigns:

```text
EDGE_LEFT
EDGE_RIGHT
EDGE_TOP
EDGE_BOTTOM
```

These become stable template references.

---

# 32. Converting Existing DXF Geometry

Do not require redrawing.

Preferred workflow:

```text
Imported DXF Geometry
        ↓
Select geometry
        ↓
Recognize / convert
        ↓
Native CAD geometry
        ↓
Apply constraints
```

Reuse imported geometry whenever technically possible.

---

# 33. Template Authoring Mode

Provide a dedicated workflow:

```text
1. Geometry
2. References
3. Constraints
4. Dimensions
5. Parameters
6. Patterns
7. Sheet Metal
8. Test
9. Save Template
```

The author should be able to go back to previous stages.

---

# 34. Template Author vs Template User

## Author mode

Shows:

- geometry
- references
- constraints
- dimensions
- parameters
- dependencies
- patterns
- sheet-metal rules

## User mode

Primarily shows:

```text
WIDTH
HEIGHT
LENGTH
THICKNESS
MATERIAL
FINISH
```

and product-specific parameters.

A normal template user should not need to understand the internal constraint graph.

---

# 35. Template Parameter Panel

Example:

```text
PARAMETERS

Main Dimensions
------------------------
Width          300 mm
Height          50 mm
Length        3000 mm

Material
------------------------
GI

Thickness
------------------------
1.5 mm

Perforation
------------------------
Type           Obround
Width             30 mm
Height             7 mm
Pitch              30 mm
```

Only expose parameters intentionally defined by the template author.

---

# 36. Template Test Mode

Before saving a template, allow multiple test configurations.

Example:

```text
TEST TEMPLATE

Width:       300
Height:       50
Length:     3000

[Generate]
```

Then:

```text
Width:       600
Height:       75
Length:     3000

[Generate]
```

Verify:

- body geometry
- holes
- patterns
- bends
- symmetry
- 3D
- flat pattern

---

# 37. Template Validation

Before production use, validate:

```text
✓ No unresolved constraints
✓ No conflicting constraints
✓ No orphaned constraints
✓ No missing references
✓ No circular dependencies
✓ No invalid dimensions
✓ No negative dimensions
✓ No self-intersections
✓ No invalid bend definitions
✓ No invalid hole placement
```

Errors should block production generation.

Warnings may remain if they are non-critical.

---

# 38. Unequal Tee Strategy

This is a major Phase 1 proof-of-concept.

Do NOT create hundreds of tee DXFs.

Create:

```text
TEE_TEMPLATE
```

with parameters:

```text
MAIN_WIDTH
MAIN_HEIGHT
BRANCH_WIDTH
BRANCH_HEIGHT
LENGTH
THICKNESS
```

The branch position should be driven by the main-body references and dimensions.

For a centered branch:

```text
CENTER_X = MAIN_WIDTH / 2

BRANCH_LEFT =
    CENTER_X - BRANCH_WIDTH / 2

BRANCH_RIGHT =
    CENTER_X + BRANCH_WIDTH / 2
```

Do not hard-code branch coordinates.

---

# 39. Unequal Cross Strategy

Use the same architecture.

Potential parameters:

```text
MAIN_WIDTH
MAIN_HEIGHT
BRANCH_WIDTH
BRANCH_HEIGHT
THICKNESS
```

Use:

- centerlines
- symmetry
- coincident relationships
- derived dimensions

where appropriate.

---

# 40. Reducer Strategy

Reducer is another important proof-of-concept.

Parameters:

```text
WIDTH_A
WIDTH_B
HEIGHT
LENGTH
THICKNESS
```

Derived transition geometry:

```text
Transition geometry
    =
function(WIDTH_A, WIDTH_B, HEIGHT, LENGTH)
```

The exact formula must be based on the actual product geometry/DXF and manufacturing intent.

Do not invent a generic reducer shape merely to satisfy the UI.

---

# 41. Cable Tray Template

The first serious real-world template should use an actual perforated cable tray DXF.

Suggested parameters:

```text
WIDTH
HEIGHT
LENGTH
THICKNESS
HOLE_TYPE
HOLE_WIDTH
HOLE_HEIGHT
HOLE_PITCH
EDGE_OFFSET
```

Some of these should remain fixed if they are product-standard values.

The template must preserve intentional:

- hole geometry
- hole relationships
- edge offsets
- patterns
- side walls
- bends

while allowing intentional dimensional changes.

---

# 42. Cable Tray Cover Template

Use an existing cover DXF.

Potential parameters:

```text
WIDTH
LENGTH
RETURN_HEIGHT
THICKNESS
```

Test that:

- width changes
- length changes
- return/flange behavior remains controlled
- bends remain associated
- thickness remains correct

---

# 43. 90° Bend Template

Use an existing bend DXF.

Potential parameters:

```text
WIDTH
HEIGHT
ANGLE
INNER_RADIUS
OUTER_RADIUS
THICKNESS
```

Expose only parameters that are actually meaningful to the real product geometry.

---

# 44. Trunking Templates

Use the same CAD/constraint/parameter architecture.

Main difference:

```text
Perforation = generally absent
```

Do not build a separate trunking CAD engine.

Reuse:

- sketch
- constraints
- parameters
- dependencies
- dimensions
- bends
- 3D
- DXF
- DSF
- DDS

---

# 45. Generic CAD vs Product Layer

Keep the architecture separated.

## Generic CAD

```text
Geometry
Sketch
Constraints
Dimensions
Parameters
Patterns
Bends
Sheet Metal
```

## Product layer

```text
Cable Tray
Cable Tray Cover
Tee
Cross
Reducer
Trunking
```

Product-specific geometry must use the generic CAD infrastructure.

---

# 46. Sheet-Metal Integration

The constraint system must integrate with the existing sheet-metal implementation.

Relevant concepts:

- bend line
- bend angle
- bend direction
- bend radius
- K-factor
- bend allowance
- bend deduction
- relief
- corner relief
- flat pattern
- folded 3D

If already implemented, reuse.

Only implement missing capabilities.

---

# 47. 2D ↔ 3D Associativity

A parameter change should propagate:

```text
2D
 ↓
Sheet-metal features
 ↓
Flat pattern
 ↓
3D
```

A bend modification should also propagate through the existing system.

Avoid maintaining unrelated duplicate model states.

---

# 48. Dimensions

Support professional dimensions, prioritizing template requirements:

- horizontal
- vertical
- aligned
- diameter
- radius
- angle
- center-to-center
- edge-to-center
- hole-to-hole
- bend-to-edge
- bend-to-bend
- overall dimensions

Double-clicking a driving dimension should edit the value.

---

# 49. Constraint Conflict Handling

Example:

```text
WIDTH = 300
```

while another relationship effectively requires:

```text
WIDTH = 400
```

Do not silently distort geometry.

Show:

```text
Constraint Conflict

Part width is constrained to:
300 mm
and
400 mm

[Edit]
[Suppress]
[Delete]
```

---

# 50. Circular Dependency Detection

Example:

```text
WIDTH
 ↓
HOLE_POSITION
 ↓
HOLE_SPACING
 ↓
WIDTH
```

Detect and reject circular dependencies.

Display:

> Circular dependency detected.

The system should identify the affected objects/parameters.

---

# 51. Undo / Redo

All operations must use the existing command/undo system.

Examples:

```text
Add Constraint
Edit Constraint
Delete Constraint

Add Parameter
Edit Parameter
Delete Parameter

Add Construction Geometry
Delete Construction Geometry

Create Pattern
Edit Pattern
Delete Pattern

Convert DXF Geometry
```

Do not bypass the existing undo architecture.

---

# 52. Selection and Snapping

Selection should support:

```text
Geometry
Edge
Point
Center
Constraint
Dimension
Pattern
Bend
Construction geometry
```

Snapping should support, where already available:

- endpoint
- midpoint
- center
- intersection
- perpendicular
- tangent
- nearest
- quadrant
- grid
- extension

Reuse the existing implementation.

---

# 53. Feature Tree

Extend the existing feature tree.

Conceptual structure:

```text
Template
│
├── Parameters
│
├── Sketch
│   ├── Geometry
│   ├── Construction
│   ├── Constraints
│   └── Dimensions
│
├── Patterns
├── Holes
├── Bends
├── Sheet Metal
└── 3D Result
```

Do not replace the existing tree if its architecture is already suitable.

---

# 54. DSF Extension

The existing DSF implementation already works.

Do not break it.

If additional information is needed, extend the existing schema to store:

```text
constructionGeometry
constraints
dimensions
parameters
dependencies
patterns
template metadata
```

Conceptual structure:

```text
DSF
├── document
├── units
├── material
├── geometry
├── constructionGeometry
├── constraints
├── dimensions
├── parameters
├── dependencies
├── features
├── holes
├── patterns
├── bends
├── sheetMetal
├── template
└── manufacturing
```

The exact schema must be based on the current DSF implementation.

---

# 55. DSF Versioning

Use explicit schema versioning.

Example:

```text
schemaVersion: 2
```

If the current implementation is version 1, implement:

```text
DSF v1
 ↓
Migration
 ↓
DSF v2
```

Existing DSF files must remain openable.

Do not make incompatible changes without migration.

---

# 56. DDS / TDS Direction

Phase 1 should eventually support a structured technical-data-sheet package.

Conceptually:

```text
DDS
├── Product Metadata
├── Client
├── Project
├── Technical Specifications
├── Parameters
├── Components
├── DSF Components
├── 2D Views
├── 3D Views
├── Dimensions
├── BOM
└── Revision History
```

DDS should be a structured engineering package, not merely a PDF.

Implementation can follow once the CAD/template foundation is stable.

---

# 57. Implementation Sets

The agent must implement the project in small, coherent sets.

After every set:

1. Build/compile.
2. Run existing tests.
3. Run new tests.
4. Manually verify the CAD UI.
5. Verify existing DXF functionality.
6. Verify existing DSF functionality.
7. Verify 3D functionality.
8. Record the completed work.
9. Only then proceed.

---

# 58. SET 00 — Complete Codebase Audit

### Objective

Understand the current system before modifying it.

### Inspect

- Geometry
- Sketch
- 2D editor
- 3D
- Features
- Dimensions
- Constraints
- DXF
- DSF
- Templates
- Undo/redo
- Rendering
- Recalculation

### Deliverable

Create:

```text
CURRENT_CAD_ARCHITECTURE.md
```

with:

```text
Existing
Reusable
Partial
Missing
Conflicting
Recommended extension point
```

### Acceptance

No major CAD subsystem is reimplemented before the audit.

---

# 59. SET 01 — Reference Geometry

Implement/extend:

- construction line
- centerline
- construction point
- reference edge
- reference axis

### Acceptance

Construction geometry:

- is visible
- is selectable
- can be constrained
- does not affect manufacturing geometry
- survives save/load

---

# 60. SET 02 — Stable Geometry References

Implement/extend stable sub-references:

```text
Line.start
Line.end
Line.edge
Circle.center
Circle.edge
Arc.start
Arc.end
Arc.center
Arc.edge
```

### Acceptance

A constraint can target an exact sub-element and survive save/load.

---

# 61. SET 03 — Basic Constraints

Implement:

```text
Coincident
Horizontal
Vertical
Parallel
Perpendicular
```

### Acceptance

Constrained geometry responds correctly when its driving geometry is changed.

---

# 62. SET 04 — Dimensional Constraints

Implement:

```text
Distance
Horizontal Distance
Vertical Distance
Radius
Diameter
Angle
```

### Acceptance

Double-clicking a driving dimension changes the geometry.

---

# 63. SET 05 — Constraint UI

Implement:

- constraint toolbar
- constraint symbols
- constraint selection
- properties panel
- edit
- delete
- show/hide constraints

### Acceptance

An engineer can create, inspect, edit and delete constraints without developer tools.

---

# 64. SET 06 — Solver State

Implement:

```text
Solved
Under-constrained
Over-constrained
Conflict
```

Detailed DOF calculation is not required initially.

### Acceptance

Conflicting constraints are detected and reported.

---

# 65. SET 07 — Symmetry / Equal / Concentric

Implement:

```text
Symmetric
Equal
Concentric
```

### Acceptance

Symmetric geometry remains symmetric after dimensional changes.

---

# 66. SET 08 — Parameter System

Implement:

```text
Parameter
Name
Type
Value
Unit
Expression
```

### Acceptance

A driving dimension can reference a named parameter such as:

```text
WIDTH = 300 mm
```

---

# 67. SET 09 — Expressions

Implement simple formulas:

```text
+
-
*
/
()
```

Example:

```text
CENTER = WIDTH / 2
```

### Acceptance

Derived values recalculate correctly.

---

# 68. SET 10 — Dependency Graph

Implement:

```text
Parameter
 ↓
Constraint
 ↓
Geometry
 ↓
Feature
 ↓
3D
```

### Acceptance

Only affected objects are recalculated and circular dependencies are detected.

---

# 69. SET 11 — Hole Intelligence

Implement/extend:

- hole object
- hole center reference
- hole dimensions
- hole-to-edge
- hole-to-hole
- hole-to-centerline

### Acceptance

Hole positions can be controlled by relationships rather than only raw coordinates.

---

# 70. SET 12 — Hole Patterns

Implement:

- linear
- rectangular
- equal spacing
- symmetric

### Acceptance

Patterns remain valid when the parent geometry changes.

---

# 71. SET 13 — DXF-to-Template Workflow

Implement:

```text
Import DXF
 ↓
Analyze
 ↓
Define main body
 ↓
Define references
 ↓
Identify holes/features
 ↓
Add constraints
 ↓
Add parameters
 ↓
Add patterns
 ↓
Save template
```

### Acceptance

An existing DXF can become an intelligent template without redrawing the entire component.

---

# 72. SET 14 — Straight Cable Tray Template

Use an actual existing cable tray DXF.

Test:

```text
WIDTH
HEIGHT
LENGTH
THICKNESS
Hole geometry
Hole pattern
Bends
```

### Acceptance

Changing dimensions produces controlled geometry while preserving intentional hole/bend/manufacturing properties.

---

# 73. SET 15 — Cable Tray Cover

Use an actual cover DXF.

Test:

```text
WIDTH
LENGTH
RETURN_HEIGHT
THICKNESS
```

### Acceptance

The cover changes correctly without globally scaling manufacturing-critical geometry.

---

# 74. SET 16 — 90° Bend

Use an existing bend DXF.

Test meaningful parameters such as:

```text
WIDTH
HEIGHT
ANGLE
RADIUS
THICKNESS
```

### Acceptance

2D, flat pattern and 3D remain consistent.

---

# 75. SET 17 — Unequal Tee

This is the primary advanced Phase 1 proof.

Parameters:

```text
MAIN_WIDTH
MAIN_HEIGHT
BRANCH_WIDTH
BRANCH_HEIGHT
LENGTH
THICKNESS
```

### Acceptance

At least two significantly different dimensional configurations are generated from the same template and remain valid.

---

# 76. SET 18 — Unequal Cross

Implement after the tee proof-of-concept.

Use actual product geometry to define the parameter/dependency model.

### Acceptance

Changing branch dimensions does not destroy main-body, hole or bend relationships.

---

# 77. SET 19 — Reducer

Parameters:

```text
WIDTH_A
WIDTH_B
HEIGHT
LENGTH
THICKNESS
```

### Acceptance

Different width combinations generate valid geometry from the same template.

---

# 78. SET 20 — Trunking

Apply the same architecture to trunking and its accessories.

### Acceptance

The same generic constraint/parameter/dependency engine works for non-perforated sheet-metal products.

---

# 79. SET 21 — Manufacturing Validation

Integrate template regeneration with existing validation.

Check as applicable:

- self-intersections
- open profiles
- invalid bends
- hole edge distance
- hole/bend interference
- minimum bend radius
- invalid thickness
- invalid dimensions
- sheet-size limitations

---

# 80. SET 22 — DSF Integration

Persist:

- parameters
- constraints
- dependencies
- construction geometry
- patterns
- template metadata

Ensure old DSF files remain compatible.

---

# 81. SET 23 — Template Library

Templates should have metadata such as:

```text
Template Name
Product Type
Revision
Description
Parameters
Material Rules
Thickness Rules
Created By
Modified Date
```

Examples:

```text
Cable Tray
Cable Tray Cover
Cable Tray 90 Bend
Cable Tray Tee
Cable Tray Unequal Tee
Cable Tray Cross
Cable Tray Unequal Cross
Cable Tray Reducer
Trunking
Trunking Tee
...
```

---

# 82. SET 24 — Regression Testing

Build a test library from real product files.

For each template:

```text
Load
 ↓
Generate nominal size
 ↓
Generate smaller size
 ↓
Generate larger size
 ↓
Validate
 ↓
3D
 ↓
Flat pattern
 ↓
DXF export
 ↓
DSF save
 ↓
Reload
 ↓
Compare
```

Use actual manufacturing dimensions rather than arbitrary test sizes where possible.

---

# 83. First Proof-of-Concept

The first important demonstration should be an actual perforated cable tray DXF.

Author:

```text
Reference edges
Centerline
Hole objects
Hole-to-edge constraints
Hole-to-hole constraints
Symmetry
Pattern
Width
Height
Length
```

Then test:

```text
300 × 50 × 3000
```

changing to:

```text
600 × 75 × 3000
```

Expected:

```text
✓ Body changes
✓ Side walls update
✓ Bend positions update
✓ Hole diameter remains correct
✓ Edge offsets remain correct
✓ Hole relationships remain correct
✓ Symmetry remains correct
✓ Pattern behavior follows its defined rule
✓ 3D updates
✓ Flat pattern updates
✓ DXF export works
✓ DSF save/reload works
```

If this works reliably, the architecture is suitable for the more complex tee/cross/reducer templates.

---

# 84. Important Pattern Design Rule

When a part becomes wider, hole patterns can behave differently.

The template author must define whether the pattern should:

### Option A — Keep pitch

```text
50 mm pitch
```

and add/remove instances.

### Option B — Keep count

```text
6 holes
```

and redistribute spacing.

### Option C — Use a bounded rule

```text
25 mm edge offset
50 mm maximum pitch
```

The system must not guess.

The pattern rule is part of the template's design intent.

---

# 85. No Hidden Product-Specific Coordinate Hacks

Avoid code like:

```text
if template == "tee":
    hole37.x += 25
```

unless the behavior is represented by a formal feature, constraint, parameter, pattern or dependency.

Product behavior should become reusable domain functionality.

---

# 86. No Separate CAD Engines

Do not create separate generic engines such as:

```text
CableTrayConstraintEngine
TrunkingConstraintEngine
ReducerConstraintEngine
```

Instead use:

```text
Generic Geometry Engine
Generic Sketch Engine
Generic Constraint Engine
Generic Parameter Engine
Generic Dependency Engine
Generic Sheet-Metal Engine
```

with product-specific features on top.

---

# 87. Error Handling

If regeneration fails:

```text
Template Regeneration Failed

Reason:
Branch width exceeds available main-body width.

Affected:
BRANCH_WIDTH
BRANCH_POSITION
```

Do not display a misleading valid-looking 3D result.

Where appropriate, retain the last valid state while clearly showing that the current parameter set is invalid.

---

# 88. Performance

Requirements:

- stable IDs
- incremental solving
- dependency tracking
- cached geometry
- no unnecessary Flutter rebuilds
- no full model regeneration for unrelated edits
- centralized unit handling
- centralized geometry tolerances

Use consistent internal units, preferably millimetres for this product domain.

---

# 89. Precision and Tolerance

Do not scatter unexplained numeric tolerances through the code.

Use named constants/configuration such as:

```text
GEOMETRY_TOLERANCE
POINT_TOLERANCE
ANGLE_TOLERANCE
SNAP_TOLERANCE
PROFILE_CLOSURE_TOLERANCE
```

---

# 90. Testing Architecture

Engineering calculations must be testable independently of Flutter UI.

Separate:

```text
Geometry tests
Constraint tests
Parameter tests
Dependency tests
Template tests
Sheet-metal tests
DXF tests
DSF tests
```

from:

```text
UI tests
```

---

# 91. Minimum Constraint Tests

Test:

```text
Horizontal
Vertical
Coincident
Parallel
Perpendicular
Distance
Radius
Diameter
Concentric
Symmetric
Equal
```

For each:

```text
Initial geometry
 ↓
Apply constraint
 ↓
Change driving value
 ↓
Solve
 ↓
Verify result
```

---

# 92. Minimum Dependency Tests

Test:

```text
WIDTH
 ↓
CENTER_X
 ↓
Hole position
```

Change WIDTH and verify the full dependency chain.

Also test circular dependency rejection.

---

# 93. DXF Regression Tests

Existing DXF behavior must not regress.

For representative files:

```text
Import
 ↓
Display
 ↓
Edit
 ↓
Export
 ↓
Reload
```

Verify geometry, units and important product entities.

---

# 94. DSF Regression Tests

Existing DSF files must remain loadable.

Test:

```text
Old DSF
 ↓
Open
 ↓
Edit
 ↓
Save
 ↓
Reload
```

Also:

```text
New DSF
 ↓
Save
 ↓
Reload
```

Verify that constraints and parameters persist.

---

# 95. Agent Operating Rules

## Rule 1 — Audit first

Never start with a large rewrite.

## Rule 2 — Reuse existing code

If a feature already works, extend it.

## Rule 3 — Preserve 3D CAD Studio

Do not rebuild the existing 3D CAD implementation simply to introduce constraints.

## Rule 4 — One CAD engine

Do not create duplicate geometry engines.

## Rule 5 — Intelligent templates are not DXF scaling

Use constraints, parameters, patterns and dependencies.

## Rule 6 — Stable IDs

Never attach persistent constraints to array indexes.

## Rule 7 — Generic first

Keep generic CAD functionality separate from product-specific rules.

## Rule 8 — Undo/redo

All user-editable operations must integrate with the existing command/undo architecture.

## Rule 9 — Test engineering logic

Important calculations must have automated tests.

## Rule 10 — Preserve file compatibility

Do not break DXF or DSF.

## Rule 11 — One coherent implementation set at a time

Do not mix unrelated major systems in one change.

## Rule 12 — Keep the application working

After each implementation set the project must compile and remain usable.

## Rule 13 — No hidden coordinate hacks

Represent design intent formally.

## Rule 14 — Incremental recalculation

Do not unnecessarily rebuild the complete model.

## Rule 15 — Inspect actual DXFs

Where product-specific behavior is required, use real product drawings as the source of truth.

---

# 96. Definition of Done — Phase 1

Phase 1 is successful when the application can reliably perform:

```text
Open existing DXF
        ↓
Edit geometry
        ↓
Create reference geometry
        ↓
Add constraints
        ↓
Add dimensions
        ↓
Create named parameters
        ↓
Create patterns
        ↓
Create dependencies
        ↓
Save intelligent template
        ↓
Enter new dimensions
        ↓
Regenerate geometry
        ↓
Regenerate sheet metal
        ↓
Regenerate 3D
        ↓
Validate
        ↓
Export DXF
        ↓
Save DSF
        ↓
Create DDS/TDS
```

The real proof is:

> **One existing real-world DXF can become an intelligent template and produce many valid dimensional variations without manually redrawing the geometry.**

---

# 97. Phase 2 — Future Direction

Phase 2 should build on the Phase 1 architecture.

Phase 1 is:

> **Geometry-first: I already have a DXF; make it intelligent and editable.**

Phase 2 becomes:

> **Product-first: I want a cable tray/product with these specifications; generate the geometry from scratch.**

Phase 2 should reuse:

- geometry engine
- sketch engine
- constraint solver
- parameter system
- dependency graph
- sheet-metal engine
- hole/pattern engine
- 2D renderer
- 3D renderer
- dimensions
- validation
- DSF
- DDS
- undo/redo

---

# 98. Phase 2 Product Generator — Future Example

```text
NEW CABLE TRAY

Product Type:
Perforated Tray

Width:
300 mm

Height:
50 mm

Length:
3000 mm

Thickness:
1.5 mm

Material:
GI

Finish:
HDG

Perforation:
Obround

Hole:
30 × 7 mm

Pitch:
30 mm

[GENERATE]
```

The future generator can create:

```text
Parametric geometry
      ↓
Perforation
      ↓
Bend geometry
      ↓
Flat pattern
      ↓
3D
      ↓
Validation
      ↓
DSF
      ↓
DDS/TDS
```

---

# 99. Phase 2 Future Product Families

Potential future generators include:

### Cable tray

- straight tray
- cover
- 90° bend
- 45° bend
- tee
- unequal tee
- cross
- unequal cross
- reducer
- riser
- coupler
- end plate

### Trunking

- straight trunking
- cover
- bends
- tee
- cross
- reducer
- other accessories

Ladder remains outside the current scope and should be handled in a separate future work package.

---

# 100. Phase 2 Connection Intelligence

Future product components may expose:

```text
ConnectionPoint
├── Position
├── Direction
├── Width
├── Height
└── SystemType
```

This can allow:

```text
Tray
 ↓
90° Bend
 ↓
Tray
 ↓
Tee
```

with intelligent compatibility checking.

For example:

```text
Connection mismatch

Tray width: 300 mm
Branch width: 200 mm

Suggested:
Unequal fitting / reducer
```

This is future functionality and should not delay Phase 1.

---

# 101. Phase 2 Perforation Engine

Future parametric generation should support:

```text
Hole Type
Hole Width
Hole Height
Pitch
Rows
Columns
Edge Offset
Pattern Offset
```

Patterns may differ between:

```text
Bottom
Side Walls
Cover
```

The Phase 1 pattern architecture should be reusable for this future engine.

---

# 102. Long-Term Architecture

The intended architecture is:

```text
                    CAD CORE
                       │
       ┌───────────────┼────────────────┐
       │               │                │
   Sketch/2D       Constraints      Parameters
       │               │                │
       └───────────────┼────────────────┘
                       │
                Dependency Graph
                       │
                Sheet Metal Engine
                       │
          ┌────────────┴─────────────┐
          │                          │
   Phase 1 Templates          Phase 2 Generators
          │                          │
 Existing DXF → Smart        Parameters → Geometry
          │                          │
          └────────────┬─────────────┘
                       │
                     3D
                       │
              Flat Pattern / DXF
                       │
                     DSF
                       │
                     DDS
```

---

# 103. Final Implementation Priority

Follow this order:

```text
1. Existing code audit
2. Reference geometry
3. Stable geometry references
4. Basic constraints
5. Dimensional constraints
6. Constraint UI
7. Solver state/conflict handling
8. Symmetry / Equal / Concentric
9. Named parameters
10. Expressions
11. Dependency graph
12. Hole relationships
13. Hole patterns
14. DXF → intelligent template workflow
15. Straight tray template
16. Cover template
17. Bend template
18. Unequal tee
19. Unequal cross
20. Reducer
21. Trunking templates
22. Validation integration
23. DSF extension/migration
24. Template library
25. Regression testing
26. DDS/TDS integration
```

---

# 104. Final Principle for the Coding Agent

The most important principle is:

> **The intelligent template system is a constrained parametric geometry system, not a DXF scaling system.**

DXF provides the initial geometry.

Constraints define relationships.

Dimensions define measurable design intent.

Parameters expose intentional product dimensions.

Patterns define repeated geometry.

Dependencies define recalculation.

The sheet-metal engine defines manufacturing behavior.

The existing 3D engine produces the folded model.

DSF stores the engineering model.

DDS/TDS packages the product information.

The coding agent must build these capabilities progressively while preserving the existing working 3D CAD Studio.

**Do not implement the entire system in one step.**

Every implementation set must produce a stable, testable improvement toward:

```text
EXISTING DXF
     ↓
INTELLIGENT TEMPLATE
     ↓
PARAMETERS
     ↓
CONSTRAINTS
     ↓
DEPENDENCIES
     ↓
AUTOMATIC REGENERATION
     ↓
2D + 3D + FLAT PATTERN
     ↓
DXF + DSF + DDS
```
