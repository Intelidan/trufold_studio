# 3D CAD Studio --- Phase 1 Implementation Master Guide

## Professional Sheet-Metal CAD, Existing DXF Template Modification, and Product Design Foundation

**Document type:** Engineering / coding-agent implementation
specification\
**Target application:** Existing Flutter-based 3D CAD Studio\
**Primary phase:** Phase 1\
**Future phase:** Phase 2 --- Parametric Cable Tray / Trunking / Cable
Ladder Product Generation\
**Status:** Implementation master guide

------------------------------------------------------------------------

# 1. Purpose of This Document

This document is the implementation roadmap for extending the existing
**3D CAD Studio** application into a professional sheet-metal CAD system
suitable for Bonn Metals product design and manufacturing workflows.

This is **not a greenfield CAD project**.

The current application already contains substantial working CAD
functionality. The coding agent has previously implemented most of the
core 3D CAD Studio features, including existing CAD interaction, 2D/3D
functionality, DXF import/export, DSF import/export, templates/design
functionality, bend-related functionality, and other CAD features.

Therefore:

> **Do not rebuild the CAD application from scratch. Inspect the
> existing implementation first, preserve working functionality, and
> extend or improve it only where required.**

The objective is to turn the existing working CAD Studio into a more
complete and professional sheet-metal CAD environment by:

1.  Auditing what already exists.
2.  Keeping existing working implementations wherever possible.
3.  Identifying missing or incomplete functionality.
4.  Improving the existing implementations where necessary.
5.  Adding features in controlled batches.
6.  Establishing a robust parametric/template architecture.
7.  Allowing existing manufactured DXF drawings to become intelligent
    editable templates.
8.  Preparing the architecture for a future fully parametric
    product-generation system.

------------------------------------------------------------------------

# 2. Critical Project Instruction

## DO NOT TREAT THIS AS A GREENFIELD IMPLEMENTATION

The agent must first inspect the existing codebase.

Before implementing any feature:

-   Find the existing implementation.
-   Understand how it currently works.
-   Determine whether it is complete.
-   Determine whether it is robust enough for the intended final CAD
    workflow.
-   Reuse it if possible.
-   Extend it if necessary.
-   Replace it only if there is a demonstrable technical reason.

Do not create duplicate:

-   geometry engines
-   renderers
-   dimension systems
-   bend systems
-   DXF systems
-   DSF systems
-   undo/redo systems
-   template systems
-   3D modeling systems

unless the existing implementation has been proven unsuitable.

The final application must have **one coherent CAD core**.

------------------------------------------------------------------------

# 3. Existing Application Baseline

The existing application already has substantial functionality developed
by the coding agent.

The agent should assume the following categories already exist in some
form and must **verify them rather than blindly reimplementing them**:

-   CAD Studio UI
-   2D editor
-   3D viewport
-   geometry handling
-   DXF import
-   DXF export
-   DSF import
-   DSF export
-   existing design/template functionality
-   bend functionality
-   3D model generation
-   save/load
-   CAD interactions
-   selection
-   editing
-   other previously implemented CAD features

Some functionality may be partial, inconsistent, or not sufficiently
professional for the new workflow.

The first task is therefore an **implementation audit**.

------------------------------------------------------------------------

# 4. Existing Files and Reference Drawings

Representative product drawings have been provided during development.

Current reference examples include:

-   `45_deg_bend_100x50.dxf`
-   `reducer_100x50x50.dxf`
-   `90_deg_outside_riser_100X50(1).dxf`
-   `unequal_cross_100x50x100x50(1).dxf`
-   `unequal_tee_100x50x100x50.dxf`

A technical datasheet example has also been provided showing actual
Bonn-style product documentation, including:

-   product views
-   sectional view
-   dimensions
-   material/finish information
-   cable tray dimensions
-   cover information
-   product variation table
-   title block
-   client/project information

These real drawings are to be treated as **engineering
reference/regression examples**, not merely visual inspiration.

------------------------------------------------------------------------

# 5. Product Context

The software is intended to support several Bonn product families.

## 5.1 Cable Tray

Typical products include:

-   straight cable trays
-   covers
-   bends
-   45-degree bends
-   90-degree bends
-   risers
-   reducers
-   tees
-   crosses
-   unequal tees
-   unequal crosses
-   couplers
-   related accessories

Many cable tray products use perforations/obround holes.

------------------------------------------------------------------------

## 5.2 Trunking

Trunking follows a similar general sheet-metal manufacturing concept but
normally does not use the same perforation patterns as cable trays.

Typical products include:

-   straight trunking
-   covers
-   bends
-   tees
-   crosses
-   reducers
-   risers
-   couplers
-   accessories

The same generic sheet-metal CAD core must be reusable for trunking.

Do not create a completely separate sheet-metal engine for trunking.

------------------------------------------------------------------------

## 5.3 Cable Ladder

Cable ladders are different.

They may contain:

-   left side rail
-   right side rail
-   connecting rungs
-   bends
-   tees
-   crosses
-   risers
-   reducers
-   other fabricated/welded components

The ladder system should eventually be represented as a **multipart
assembly/product**, not necessarily as one continuous sheet-metal blank.

Phase 1 should establish the assembly/component framework, while the
sophisticated parametric ladder generator belongs primarily to Phase 2.

------------------------------------------------------------------------

# 6. Core Strategic Principle

There are two different CAD workflows.

## Phase 1

> **I already have a manufactured drawing. Help me edit, dimension,
> engineer, and convert it into an intelligent reusable template.**

Workflow:

``` text
Existing DXF
    ↓
Import
    ↓
Analyze
    ↓
Clean / repair
    ↓
Recognize geometry/features
    ↓
Add dimensions and constraints
    ↓
Define sheet-metal features
    ↓
Add/edit bends
    ↓
Add/edit holes and patterns
    ↓
Generate / update 3D
    ↓
Validate
    ↓
Save intelligent DSF
    ↓
Generate TDS / DDS
```

## Phase 2

> **I want a product with these dimensions. Generate the complete design
> from engineering rules.**

Workflow:

``` text
Product type
    ↓
Parameters
    ↓
Engineering rules
    ↓
Skeleton
    ↓
Generated geometry
    ↓
Sheet-metal development
    ↓
Bends / holes / reliefs
    ↓
3D
    ↓
Validation
    ↓
DSF / DDS / DXF
```

Phase 1 must build the common CAD foundation required by both workflows.

------------------------------------------------------------------------

# 7. Final Phase 1 Goal

At the end of Phase 1, a user should be able to open an existing product
DXF and turn it into an intelligent sheet-metal design.

Example:

``` text
Open:
unequal_tee_100x50x100x50.dxf

        ↓

Analyze drawing

        ↓

Identify:
- outer geometry
- holes
- slots
- bend lines
- feature relationships

        ↓

Add/edit:
- dimensions
- constraints
- material
- thickness
- bends
- hole patterns

        ↓

Save as:
Unequal Tee Template

        ↓

Create instance

        ↓

Change controlled dimensions

        ↓

Regenerate affected geometry

        ↓

Generate:
- flat pattern
- 3D model
- dimensions
- manufacturing information

        ↓

Save:
DSF

        ↓

Generate:
TDS / DDS
```

The application must not require thousands of manually prepared DXF
files for every dimension combination.

------------------------------------------------------------------------

# 8. Fundamental Architecture

The final architecture should conceptually be:

``` text
                    3D CAD STUDIO
                          |
              +-----------+-----------+
              |                       |
             UI                 Application Layer
              |                       |
       +------+------+          Command System
       |             |                 |
      2D            3D                 |
       |             |                 |
       +------+------+-----------------+
                     |
                  CAD CORE
                     |
      +--------------+----------------+
      |              |                |
   Geometry      Dimensions       Constraints
      |              |                |
      +--------------+----------------+
                     |
                 FEATURES
                     |
       +-------------+-------------+
       |             |             |
      Bend          Hole        Pattern
       |             |             |
       +-------------+-------------+
                     |
               SHEET METAL CORE
                     |
       +-------------+-------------+
       |             |             |
  Flat Pattern      3D          Validation
                     |
          +----------+----------+
          |                     |
   Template Engine       Assembly Engine
          |                     |
   Existing DXF          Ladder / Multipart
          |                     |
          +----------+----------+
                     |
                 DSF / DDS
                     |
               FUTURE PHASE 2
                     |
        Parametric Product Generators
```

------------------------------------------------------------------------

# 9. Native CAD Model vs DXF

DXF must not become the native engineering model.

DXF is an interchange format.

The native model should contain semantic information.

Conceptually:

``` text
CadDocument
    |
    +-- Parameters
    +-- Geometry
    +-- Features
    +-- Dimensions
    +-- Constraints
    +-- SheetMetal
    +-- Assemblies
    +-- Manufacturing
    +-- Metadata
```

A raw DXF might say:

``` text
LINE x1 y1 x2 y2
```

The CAD model should eventually understand:

``` text
MainEdge
Bend_01
HolePattern_02
Branch_A
```

This semantic layer is essential for intelligent template modification.

------------------------------------------------------------------------

# 10. Stable IDs

Every persistent CAD object must have a stable unique ID.

Examples:

``` text
geom_01...
feature_bend_01...
hole_01...
pattern_01...
dimension_01...
parameter_width...
```

Do not reference objects using array indexes.

Bad:

``` text
bend[4]
line[127]
```

Good:

``` text
bendFeatureId = "bend_a83..."
geometryId = "edge_102..."
```

This is necessary for:

-   dependencies
-   dimensions
-   constraints
-   templates
-   undo/redo
-   DSF persistence
-   migrations
-   assemblies
-   cross-references

------------------------------------------------------------------------

# 11. Units

Use millimetres internally.

All engineering calculations should use a single internal unit system.

UI may display:

-   mm
-   inch

but conversion must occur at the UI/input boundary.

Create centralized tolerance definitions.

Do not scatter unexplained values such as:

``` text
0.001
0.01
0.1
```

throughout the code.

------------------------------------------------------------------------

# 12. Implementation Strategy

Every implementation stage must follow this sequence:

``` text
1. Inspect existing code.
2. Identify existing implementation.
3. Identify gaps.
4. Define minimum required change.
5. Implement.
6. Run existing tests.
7. Add regression tests.
8. Manually verify in CAD Studio.
9. Verify save/load.
10. Verify undo/redo.
11. Verify DXF/DSF compatibility where relevant.
12. Document completion.
```

Never implement ten major systems at once.

Each milestone should be split into small batches.

Each batch must leave the application:

-   compiling
-   runnable
-   usable
-   stable

------------------------------------------------------------------------

# 13. STEP 0 --- Complete Codebase Audit

Before modifying functionality, inspect:

## UI

-   main window
-   menus
-   toolbars
-   panels
-   properties
-   feature tree
-   viewport
-   status bar
-   dialogs

## CAD state

-   document state
-   selection state
-   editing state
-   command state
-   active tool
-   current view

## Geometry

-   lines
-   arcs
-   polylines
-   circles
-   slots
-   profiles
-   transforms

## 3D

-   mesh generation
-   folding
-   camera
-   rendering
-   synchronization

## DXF

-   importer
-   exporter
-   layers
-   entities
-   units
-   cleanup

## DSF

-   schema
-   serializer
-   deserializer
-   versioning
-   templates

## Existing template/design system

Inspect exactly how the current application represents:

-   templates
-   dimensions
-   parameters
-   editable geometry
-   relationships
-   regenerated geometry

## Existing bend system

Determine:

-   how bends are represented
-   how angles are stored
-   how radius is stored
-   how 3D folding is calculated
-   whether flat pattern is authoritative
-   whether bend allowance exists
-   whether K-factor exists

### Deliverable

Create an internal audit document:

``` text
CAD_IMPLEMENTATION_AUDIT.md
```

with:

``` text
EXISTING AND WORKING
EXISTING BUT INCOMPLETE
EXISTING BUT NEEDS REFACTOR
MISSING
DUPLICATE IMPLEMENTATIONS
HIGH-RISK AREAS
```

Do not proceed with major architecture changes until this audit is
complete.

------------------------------------------------------------------------

# 14. STEP 1 --- Stabilize the CAD Document Model

Verify or extend the existing document model.

Required conceptual entities:

``` text
CadDocument
CadPart
CadAssembly
CadGeometry
CadFeature
CadParameter
CadDimension
CadConstraint
CadMaterial
SheetMetalDefinition
ManufacturingDefinition
```

Do not necessarily create new classes if equivalent existing classes
already exist.

The goal is semantic separation, not unnecessary rewriting.

------------------------------------------------------------------------

# 15. STEP 2 --- Professional 2D CAD Viewport

Improve the existing 2D editor where required.

Required behavior:

-   zoom
-   pan
-   fit
-   mouse-wheel zoom
-   box selection
-   crossing selection
-   multi-selection
-   hover highlighting
-   object highlighting
-   grid
-   axes
-   coordinate readout
-   snap indicators
-   selection filters
-   construction geometry

## Snapping

Support or verify:

``` text
Endpoint
Midpoint
Center
Intersection
Perpendicular
Tangent
Nearest
Quadrant
Grid
Extension
```

The snap system must be reusable by:

-   drawing
-   dimensions
-   bend creation
-   hole placement
-   constraints
-   measurements

------------------------------------------------------------------------

# 16. STEP 3 --- Core 2D Geometry

Verify or implement:

``` text
Line
Polyline
Rectangle
Circle
Arc
Ellipse
Slot / Obround
Point
Construction Line
```

Slots are particularly important for Bonn cable tray drawings.

Where possible, a slot should be represented semantically:

``` text
Slot
    center
    length
    width
    rotation
```

rather than permanently treating it as unrelated lines and arcs.

This makes hole editing and pattern generation much easier.

------------------------------------------------------------------------

# 17. STEP 4 --- Modify Tools

Implement/verify in groups.

## Group A

``` text
Move
Copy
Rotate
Mirror
Delete
```

## Group B

``` text
Trim
Extend
Break
Join
```

## Group C

``` text
Offset
Fillet
Chamfer
```

## Group D

``` text
Linear Pattern
Circular Pattern
Mirror Pattern
```

Every modifying operation must go through the command/undo system.

------------------------------------------------------------------------

# 18. STEP 5 --- Selection and Properties

Professional CAD editing depends on reliable selection.

Selecting an entity must show its properties.

Examples:

### Line

``` text
Start X
Start Y
End X
End Y
Length
Angle
Layer
```

### Slot

``` text
Center X
Center Y
Length
Width
Rotation
```

### Bend

``` text
Angle
Radius
Direction
K-factor
Allowance
Relief
```

### Hole Pattern

``` text
Type
Size
Pitch
Count
Offset
Direction
```

The properties panel must become a primary editing mechanism.

------------------------------------------------------------------------

# 19. STEP 6 --- Dimensions

Dimensions are first-class CAD objects.

Required types:

``` text
Horizontal
Vertical
Aligned
Angular
Radius
Diameter
Arc Length
Distance
Center-to-Center
Edge-to-Edge
Hole-to-Edge
Hole-to-Hole
Bend-to-Edge
Bend-to-Bend
Overall
```

Each dimension must reference actual CAD entities.

Example:

``` text
Dimension
    id
    referenceA
    referenceB
    measuredValue
    displayedValue
    units
    style
```

------------------------------------------------------------------------

# 20. STEP 7 --- Direct Dimension Editing

This is a critical user experience.

Example:

``` text
100 mm
```

User double-clicks:

``` text
150
```

Presses Enter.

The CAD geometry must update.

The dimension must remain associative.

This is not merely changing annotation text.

The geometry itself must change.

------------------------------------------------------------------------

# 21. STEP 8 --- Constraints

Implement/verify progressively.

## First group

``` text
Horizontal
Vertical
Coincident
Parallel
Perpendicular
```

## Second group

``` text
Concentric
Tangent
Equal
Symmetric
Collinear
Fixed
```

## Third group

``` text
Distance
Angle
Radius
Diameter
```

Do not attempt to create an unnecessarily complex general-purpose solver
if the existing application already has a suitable controlled mechanism.

Prioritize constraints that are useful for actual sheet-metal product
drawings.

------------------------------------------------------------------------

# 22. STEP 9 --- DXF Import Improvements

Existing DXF import must be preserved and improved only where needed.

Support/verify:

``` text
LINE
LWPOLYLINE
POLYLINE
ARC
CIRCLE
ELLIPSE
SPLINE
TEXT
DIMENSION
INSERT
```

depending on what the current implementation supports and what is
needed.

The importer should preserve:

-   geometry
-   layers
-   units where available
-   relevant metadata

------------------------------------------------------------------------

# 23. DXF Import Diagnostics

Do not silently modify imported drawings.

Provide diagnostics such as:

``` text
DXF IMPORT

✓ 124 geometry entities
✓ 38 closed profiles
✓ 42 slot-like profiles
✓ 16 possible bend lines

⚠ 3 duplicate entities
⚠ 2 open profiles
⚠ 1 geometry gap
```

Allow the user to review before cleanup.

Potential cleanup operations:

-   duplicate removal
-   zero-length removal
-   tiny-gap healing
-   endpoint joining
-   profile closure
-   slot recognition
-   repeated-hole detection

Original source geometry should remain recoverable.

------------------------------------------------------------------------

# 24. STEP 10 --- Geometry Recognition

The application must progressively convert raw DXF geometry into
semantic CAD features.

Recognize:

``` text
Outer Boundary
Inner Cutout
Hole
Slot
Bend Candidate
Construction Geometry
Repeated Pattern
Symmetry
```

For example, a set of repeated slot-shaped closed profiles may be
detected as:

``` text
24 Obround Holes
Possible pattern:
4 rows × 6 columns
```

The user should be able to confirm or correct the interpretation.

------------------------------------------------------------------------

# 25. STEP 11 --- Feature Tree

The final model tree should resemble:

``` text
MODEL
│
├── Base Geometry
├── Bend 01
├── Bend 02
├── Hole Pattern 01
├── Hole Pattern 02
├── Cutout 01
└── Construction Geometry
```

Selecting a feature should select/highlight all associated geometry.

Suppressing/deleting/editing a feature should update dependent geometry.

The feature tree should be compatible with future parametric templates.

------------------------------------------------------------------------

# 26. STEP 12 --- Sheet-Metal Definition

Introduce or improve a semantic sheet-metal definition.

Conceptually:

``` text
SheetMetalDefinition
    Material
    Thickness
    BendRadius
    KFactor
    BendAllowance
    BendDeduction
    NeutralAxis
    ReliefRules
```

Materials may eventually include:

``` text
GI
MS
HR
CRCA
SS304
SS316
Aluminium
```

Finishes/coatings should be represented separately from base material.

Possible coating values relevant to the manufacturing environment
include:

``` text
EG
HDG
2HDG
3HDG
PC
2PC
3PC
EX
2EX
3EX
```

Do not mix coating cost/finish with geometric material properties.

------------------------------------------------------------------------

# 27. STEP 13 --- Bend Feature

Bends must be first-class features.

Conceptually:

``` text
BendFeature
    id
    bendLine
    angle
    radius
    direction
    kFactor
    allowance
    deduction
    relief
```

User workflow:

``` text
Select line
    ↓
Add Bend
    ↓
Set angle
    ↓
Set radius
    ↓
Set direction
    ↓
Update 3D
```

The bend line in the flat pattern and the folded 3D geometry must remain
associative.

------------------------------------------------------------------------

# 28. STEP 14 --- Bend Editing

Selecting a bend should expose:

``` text
BEND

Angle:       [90°]
Radius:      [2.0 mm]
Direction:   [Inside ▼]
K-Factor:    [0.33]
Allowance:   [Auto]
Relief:      [Rectangular ▼]
```

Changing the bend must update:

-   flat pattern
-   3D
-   dimensions
-   bend data
-   validation

Example:

``` text
90° → 45°
```

must result in a genuine recalculation, not a visual rotation of the old
3D mesh.

------------------------------------------------------------------------

# 29. STEP 15 --- Bend Sequence / Folded Model

Where practical, introduce a bend sequence.

Example:

``` text
Bend 01
Bend 02
Bend 03
```

The 3D model should be able to:

-   fold
-   unfold
-   show flat state
-   show folded state
-   optionally animate folding/unfolding

This is useful for validating the actual sheet-metal construction.

------------------------------------------------------------------------

# 30. STEP 16 --- Hole Feature

Convert recognized holes into semantic features.

Required types:

``` text
Round
Obround
Rectangle
Square
Custom Profile
```

Each hole should have:

``` text
position
size
rotation
profile
```

------------------------------------------------------------------------

# 31. STEP 17 --- Hole Pattern Engine

Required patterns:

``` text
Linear
Rectangular
Circular
Along Edge
Equal Spacing
Mirror
```

For example:

``` text
Obround
30 × 7

Pitch = 50
Edge Offset = 25
```

Changing product length should automatically recalculate:

-   number of holes
-   positions
-   spacing
-   end offsets where applicable

------------------------------------------------------------------------

# 32. STEP 18 --- Flat Pattern Engine

The flat pattern must be a true manufacturing representation.

It must account for:

``` text
Thickness
Bend Radius
K-factor
Bend Allowance
Bend Deduction
Neutral Axis
Reliefs
Corner Treatments
```

Keep the distinction between:

``` text
Design Model
Flat Pattern
Folded 3D Model
```

They are related but not necessarily identical representations.

------------------------------------------------------------------------

# 33. STEP 19 --- 2D / 3D Synchronization

This is a core professional-CAD feature.

When selecting:

``` text
Bend 02
```

in 2D, the corresponding bend must be highlighted in 3D.

When selecting a 3D face/edge associated with a feature, the
corresponding 2D geometry/feature should be identified.

Synchronize:

-   selection
-   feature IDs
-   visibility
-   editing
-   dimensions where practical

Avoid duplicated state between the 2D and 3D systems.

------------------------------------------------------------------------

# 34. STEP 20 --- 3D Viewport

Verify or improve:

``` text
Rotate
Pan
Zoom
Fit
```

Views:

``` text
Front
Back
Left
Right
Top
Bottom
Isometric
```

Display modes:

``` text
Shaded
Shaded + Edges
Wireframe
Transparent
```

Add:

``` text
Flat / Folded toggle
```

where supported by the existing engine.

------------------------------------------------------------------------

# 35. STEP 21 --- Manufacturing Validation

Create or improve a validation engine.

Validate:

``` text
Open Profiles
Duplicate Geometry
Self Intersections
Invalid Bends
Bend Radius Too Small
Hole Too Close to Edge
Hole Too Close to Bend
Insufficient Relief
Bend Collision
Invalid Pattern
Invalid Thickness
Invalid Geometry
```

Use severity:

``` text
INFO
WARNING
ERROR
```

Clicking an error should locate/highlight the affected geometry.

------------------------------------------------------------------------

# 36. STEP 22 --- Parametric Parameter System

This is the bridge from CAD editing to product templates.

Parameters must be first-class objects.

Examples:

``` text
Width
Height
Length
Thickness
Angle
Radius
BranchWidth
BranchHeight
HolePitch
HoleOffset
```

Parameters should have:

``` text
id
name
value
unit
type
minimum
maximum
formula
source
```

------------------------------------------------------------------------

# 37. Parameter Categories

## User parameters

Directly entered by the user:

``` text
Width = 300
Height = 50
Length = 3000
```

## Derived parameters

Calculated:

``` text
FlatLength
HoleCount
TransitionLength
BendAllowance
```

## Feature parameters

Belong to a feature:

``` text
Bend01.Angle
Bend01.Radius
HolePattern01.Pitch
```

This distinction should be preserved.

------------------------------------------------------------------------

# 38. Dependency Graph

The template system must eventually use dependency tracking.

Example:

``` text
Width
  ↓
Outer Boundary
  ↓
Bend Location
  ↓
Available Hole Area
  ↓
Hole Pattern
  ↓
Flat Pattern
  ↓
3D
  ↓
Weight
  ↓
TDS
```

When Width changes, only dependent features should be recalculated.

Do not recompute the entire document unnecessarily.

------------------------------------------------------------------------

# 39. Existing DXF → Intelligent Template

This is the main Phase 1 product feature.

Workflow:

``` text
Open DXF
   ↓
Analyze
   ↓
Clean
   ↓
Recognize geometry
   ↓
Identify holes
   ↓
Identify bends
   ↓
Add dimensions
   ↓
Define parameters
   ↓
Define dependencies
   ↓
Save Template
```

The original DXF must be preserved.

The template is a new semantic representation derived from it.

------------------------------------------------------------------------

# 40. Template Storage

Conceptually:

``` text
Template
    |
    +-- Template Metadata
    +-- Source Drawing
    +-- Parameters
    +-- Geometry
    +-- Features
    +-- Dimensions
    +-- Constraints
    +-- Formulas
    +-- Dependencies
    +-- Sheet Metal Rules
    +-- Validation Rules
```

Do not store only the final line coordinates.

------------------------------------------------------------------------

# 41. Three Levels of Template Modification

Not all dimensional changes are equivalent.

## Level A --- Transform

Examples:

-   move
-   rotate
-   mirror
-   controlled offset
-   simple hole movement

## Level B --- Constraint Regeneration

Topology remains unchanged.

Examples:

-   simple riser
-   simple bend
-   cover
-   straight tray
-   controlled reducer

## Level C --- Full Parametric Regeneration

Topology or intersections can change.

Examples:

-   unequal tee
-   unequal cross
-   complex reducer
-   multi-branch fitting

Phase 1 should support Level A and Level B strongly and establish the
architecture for Level C.

Phase 2 should implement sophisticated Level C generators.

------------------------------------------------------------------------

# 42. Never Use Simple Scaling for Product Dimensions

A major design rule:

> Changing a product dimension must not automatically mean scaling the
> entire DXF.

For example:

``` text
100 mm → 300 mm
```

may require recalculating:

-   edge positions
-   bend positions
-   branch intersections
-   hole count
-   hole spacing
-   reliefs
-   transition geometry
-   bend allowances

Therefore the template must understand the design intent.

------------------------------------------------------------------------

# 43. Example --- Unequal Tee

A future parameter model may look like:

``` text
Main Branch
    Width
    Height

Branch A
    Width
    Height

Branch B
    Width
    Height

Common
    Thickness
    Bend Radius
    Hole Pattern
```

The existing unequal tee DXF is the **reference geometry**.

Phase 1 should allow the existing topology to be parameterized.

Phase 2 can later generate the complete tee from a
mathematical/engineering skeleton.

------------------------------------------------------------------------

# 44. Example --- Unequal Cross

Conceptually:

``` text
Cross
    Branch A
        Width
        Height

    Branch B
        Width
        Height

    Branch C
        Width
        Height

    Branch D
        Width
        Height
```

A change such as:

``` text
Branch A: 100 → 300
```

may affect:

-   outer boundary
-   branch transition
-   bend lines
-   hole regions
-   intersections

The engine must recalculate dependent geometry.

------------------------------------------------------------------------

# 45. Example --- Reducer

A reducer may have:

``` text
Input Width
Output Width
Height
Length
Thickness
Bend Radius
Hole Pattern
```

The generated transition geometry should depend on those parameters.

Do not hard-code a separate DXF for:

``` text
100→50
150→100
200→100
300→150
...
```

The Phase 1 template architecture must make this possible.

------------------------------------------------------------------------

# 46. Example --- 45° Bend

Parameters may include:

``` text
Width
Height
Angle
Radius
Thickness
Transition Length
Hole Pattern
```

The angle must be a real geometric parameter.

The same template should eventually support allowed variants such as:

``` text
30°
45°
60°
90°
```

subject to engineering rules.

------------------------------------------------------------------------

# 47. Example --- 90° Outside Riser

Represent as a bend chain rather than unrelated lines.

Conceptually:

``` text
Segment 1
    ↓
Bend 1
    ↓
Segment 2
    ↓
Bend 2
    ↓
Segment 3
```

Parameters:

``` text
Width
Height
Riser Height
Angle
Thickness
Radius
Hole Pattern
```

------------------------------------------------------------------------

# 48. Product Templates in Phase 1

Phase 1 templates should initially be **DXF-derived templates**.

Example:

``` text
Cable Tray 90° Bend Template
    source = existing DXF
    parameters = Width, Height, ...
```

Do not require every product to be generated completely from scratch in
Phase 1.

The template system is the bridge toward Phase 2.

------------------------------------------------------------------------

# 49. Product Library

Create or extend a product library.

Possible structure:

``` text
Cable Tray
    Straight
    Cover
    45° Bend
    90° Bend
    Riser
    Reducer
    Tee
    Cross
    Coupler

Trunking
    Straight
    Cover
    Bend
    Riser
    Reducer
    Tee
    Cross
    Coupler

Cable Ladder
    Straight
    Side Rail
    Rung
    Bend
    Riser
    Reducer
    Tee
    Cross
```

Initially, these can point to existing templates/DXFs.

------------------------------------------------------------------------

# 50. Multipart / Assembly Framework

Phase 1 should establish a basic assembly model.

Conceptually:

``` text
Assembly
    Component Instance
        componentId
        quantity
        position
        orientation
        relationship
```

Relationships:

``` text
Fixed
Attached
Patterned
Mirrored
Referenced
Repeated
```

Do not build a full mechanical assembly constraint solver yet.

------------------------------------------------------------------------

# 51. Cable Ladder Representation

A ladder can eventually be:

``` text
Cable Ladder Assembly
│
├── Left Side Rail
├── Right Side Rail
└── Rung Pattern
      ├── Rung 01
      ├── Rung 02
      ├── Rung 03
      └── ...
```

A rung should not be saved as ten unrelated unique designs.

Use:

``` text
Rung Feature
    +
Rung Instances
```

This supports:

-   quantity
-   equal spacing
-   individual positions
-   start/end offsets
-   future welding/fabrication information

------------------------------------------------------------------------

# 52. Ladder Rung Positioning

Support:

## Equal spacing

``` text
Start Offset
End Offset
Quantity
```

or:

``` text
Start
End
Pitch
```

## Individual positions

``` text
Rung 01 = 50
Rung 02 = 350
Rung 03 = 700
...
```

This framework is required in Phase 1 even if full ladder generation is
deferred.

------------------------------------------------------------------------

# 53. DSF --- Existing Implementation Must Be Preserved

The application already has DSF import/export.

Do not replace the current DSF format unnecessarily.

First inspect:

-   current schema
-   current fields
-   backwards compatibility
-   current template data
-   current bend data
-   current geometry storage

Then make the **minimum controlled schema extension** required for the
new parametric capabilities.

------------------------------------------------------------------------

# 54. DSF Evolution

The DSF should eventually store:

``` text
Format
Schema Version
Application Version
Units
Document Metadata
Product
Parameters
Geometry
Features
Dimensions
Constraints
Sheet Metal
Material
Manufacturing
Assembly
Template Information
History
```

The existing DSF structure should be migrated rather than discarded.

------------------------------------------------------------------------

# 55. DSF Versioning

Introduce/verify:

``` text
schemaVersion
```

and migration support:

``` text
DSF v1
   ↓
Migration
   ↓
DSF v2
```

Do not make old valid DSFs unreadable without a deliberate migration
strategy.

------------------------------------------------------------------------

# 56. DDS / Technical Data Sheet

The application should eventually generate an intelligent technical data
sheet package.

The DDS should contain or reference:

``` text
Product Information
Client
Project
Product Type
Dimensions
Material
Thickness
Finish
2D Views
3D Views
BOM
Weight
Components
DSF
Revision
Approval
```

The screenshot supplied with the project should be used as a
visual/functional reference for the eventual TDS output.

------------------------------------------------------------------------

# 57. DDS Should Be Structured

Do not make DDS simply a renamed PDF.

The preferred architecture is a structured package containing:

``` text
Manifest
Product Data
Components
DSF Files
Preview Images
2D Views
3D View Data
Revision Data
```

The exact physical packaging mechanism can be finalized after the DSF
structure stabilizes.

------------------------------------------------------------------------

# 58. Professional Editor Layout

The final UI should approach a professional desktop CAD layout.

Conceptually:

``` text
+--------------------------------------------------------------+
| File Edit View Sketch Sheet Metal Measure Tools              |
+--------------------------------------------------------------+
| Contextual Toolbar                                           |
+------------+--------------------------------+----------------+
|            |                                |                |
| MODEL /    |                                | PROPERTIES     |
| FEATURE    |          2D / 3D VIEW          |                |
| TREE       |                                |                |
|            |                                |                |
|            |                                |                |
+------------+--------------------------------+----------------+
| Command / Input / Snap / Coordinates / Units / Status       |
+--------------------------------------------------------------+
```

The existing UI may differ. Do not redesign the whole interface
unnecessarily.

Improve the existing interface incrementally.

------------------------------------------------------------------------

# 59. Context-Sensitive Properties

The properties panel must change according to the selection.

Examples:

``` text
No selection
    → Document properties

Line selected
    → Line properties

Slot selected
    → Slot properties

Bend selected
    → Bend properties

Hole pattern selected
    → Pattern properties

Template selected
    → Template parameters
```

Direct numeric editing should be available whenever practical.

------------------------------------------------------------------------

# 60. Command System

All model-changing operations should use a command architecture.

Conceptually:

``` text
Command
    execute()
    undo()
```

Examples:

``` text
CreateLineCommand
MoveGeometryCommand
CreateDimensionCommand
EditDimensionCommand
CreateBendCommand
EditBendCommand
CreateHoleCommand
EditPatternCommand
ChangeParameterCommand
```

This ensures consistent:

-   undo
-   redo
-   history
-   scripting possibility
-   future automation

------------------------------------------------------------------------

# 61. Undo / Redo

Every meaningful user modification must be undoable.

Test:

``` text
Create
Edit
Delete
Dimension change
Bend change
Hole change
Pattern change
Template parameter change
```

Also verify that undo/redo survives save/load where the existing
application supports history persistence.

------------------------------------------------------------------------

# 62. Performance

The application may eventually contain large drawings and complex
patterns.

Do not recompute everything for every UI rebuild.

Separate:

``` text
CAD Model
```

from:

``` text
Flutter Widget Tree
```

Use dirty flags/dependency tracking.

Conceptually:

``` text
Parameter changed
    ↓
Find dependent features
    ↓
Mark dirty
    ↓
Recalculate affected geometry
    ↓
Update renderer
```

Avoid:

``` text
Parameter changed
    ↓
Recalculate entire document
    ↓
Rebuild entire UI
```

unless unavoidable.

------------------------------------------------------------------------

# 63. Geometry Tolerance

Use centralized tolerances.

Examples:

``` text
Coincidence tolerance
Intersection tolerance
DXF cleanup tolerance
Profile closure tolerance
Dimension comparison tolerance
Manufacturing validation tolerance
```

Make them configurable at the engineering-core level.

------------------------------------------------------------------------

# 64. Template Regeneration Architecture

The regeneration process should conceptually be:

``` text
Parameter Change
      ↓
Parameter Manager
      ↓
Dependency Graph
      ↓
Affected Features
      ↓
Feature Recalculation
      ↓
Geometry Regeneration
      ↓
Flat Pattern Update
      ↓
3D Update
      ↓
Dimensions Update
      ↓
Validation
      ↓
Dirty State Cleared
```

The UI should not directly perform geometric calculations.

------------------------------------------------------------------------

# 65. Feature Regeneration Order

A typical sheet-metal template may calculate in this order:

``` text
1. User parameters
2. Derived parameters
3. Product skeleton/reference geometry
4. Primary boundaries
5. Bend locations
6. Bend allowances
7. Cutouts
8. Hole features
9. Hole patterns
10. Reliefs
11. Dimensions
12. Flat pattern
13. Folded 3D
14. Validation
15. Manufacturing information
```

The exact order should be adapted to the existing CAD engine.

------------------------------------------------------------------------

# 66. Template Safety

When a user changes a parameter to an invalid value, do not produce
corrupt geometry silently.

Example:

``` text
Width = 10 mm
Height = 100 mm
Thickness = 3 mm
```

If the geometry becomes impossible:

``` text
ERROR
Width is below the minimum allowed for this template.
```

The old valid state should remain recoverable.

------------------------------------------------------------------------

# 67. Parameter Validation

Parameters can have:

``` text
minimum
maximum
step
unit
allowed values
formula constraints
```

Example:

``` text
Thickness:
Allowed:
1.2
1.5
2.0
2.5
3.0
```

or continuous values where appropriate.

Do not hard-code product restrictions into the UI only. They belong in
the engineering/template layer.

------------------------------------------------------------------------

# 68. Manufacturing Rules

Phase 1 should introduce a framework for rules such as:

``` text
Minimum bend radius
Minimum hole-edge distance
Minimum hole-bend distance
Minimum flange width
Minimum relief
Maximum unsupported geometry
Allowed thickness
```

The exact Bonn manufacturing rules can be progressively populated later.

------------------------------------------------------------------------

# 69. Engineering vs UI Separation

The following must not be implemented primarily inside Flutter widgets:

-   bend calculations
-   flat pattern calculations
-   hole pattern mathematics
-   DXF geometry transformations
-   constraints
-   dependency calculations
-   template regeneration
-   validation

Flutter widgets should invoke domain/application services.

------------------------------------------------------------------------

# 70. Testing Strategy

Create tests at multiple levels.

## Geometry

``` text
Line
Arc
Polyline
Slot
Intersection
Offset
Fillet
Trim
```

## Dimensions

``` text
Horizontal
Vertical
Aligned
Angular
Associative editing
```

## Sheet Metal

``` text
Bend
Allowance
K-factor
Flat pattern
Fold
Unfold
Relief
```

## Holes

``` text
Round
Slot
Pattern
Count
Spacing
```

## DXF

Use actual reference files.

## DSF

Test:

``` text
Save
Load
Migration
Template parameters
Features
Dimensions
Bends
```

## Template

Test:

``` text
Parameter change
Dependency propagation
Geometry regeneration
Invalid parameter handling
```

## Assembly

Test:

``` text
Component
Instance
Quantity
Position
Pattern
```

------------------------------------------------------------------------

# 71. Golden Reference Drawings

Use the supplied real drawings as regression fixtures.

At minimum:

``` text
45° Bend 100×50
Reducer 100×50×50
90° Outside Riser 100×50
Unequal Cross 100×50×100×50
Unequal Tee 100×50×100×50
```

For each, compare generated/reference characteristics:

``` text
Overall dimensions
Outer boundary
Bend locations
Bend count
Hole count
Hole locations
Slot dimensions
Area
```

Use defined tolerances.

The goal is not necessarily byte-for-byte DXF equality.

The goal is engineering/geometric equivalence.

------------------------------------------------------------------------

# 72. Implementation Batch Rules

Each feature must be implemented in small batches.

Example:

## Dimension batch

``` text
Batch 01 — Dimension data model
Batch 02 — Horizontal dimension calculation
Batch 03 — Horizontal rendering
Batch 04 — Vertical dimension
Batch 05 — Selection
Batch 06 — Editing
Batch 07 — Associativity
Batch 08 — Undo/redo
Batch 09 — Save/load
Batch 10 — Regression tests
```

Do the same for every major feature.

------------------------------------------------------------------------

# 73. Definition of Done

A feature is not complete merely because it appears on screen.

A CAD feature is complete when applicable:

``` text
✓ Create
✓ Select
✓ Edit
✓ Delete
✓ Undo
✓ Redo
✓ Save
✓ Reload
✓ Correct rendering
✓ Correct geometry
✓ Correct 2D/3D relationship
✓ Correct dependency behavior
✓ Validation
✓ Regression test
```

Not every item applies to every feature, but the agent must explicitly
identify exceptions.

------------------------------------------------------------------------

# 74. Phase 1 Milestone Sequence

Implement in this order unless the code audit demonstrates a strong
reason to reorder.

``` text
P0  Codebase / architecture audit

P1  CAD document and ID stabilization

P2  2D viewport / interaction improvements

P3  Core geometry verification

P4  Modify tools verification

P5  Selection / properties

P6  Dimensions

P7  Direct dimension editing

P8  Constraints

P9  DXF import diagnostics

P10 DXF geometry recognition

P11 Feature tree

P12 Sheet-metal definition

P13 Bend system improvements

P14 Flat pattern improvements

P15 2D ↔ 3D synchronization

P16 Hole features

P17 Hole patterns

P18 Manufacturing validation

P19 Parameter system

P20 Dependency graph

P21 Existing-DXF intelligent templates

P22 Controlled template regeneration

P23 Multipart / assembly framework

P24 DSF schema extension / migration

P25 TDS / DDS foundation

P26 Product template library

P27 Full regression / performance / UX pass
```

------------------------------------------------------------------------

# 75. P0 --- Audit Acceptance Criteria

The agent must produce:

``` text
- architecture map
- existing feature inventory
- missing feature inventory
- duplicate implementation inventory
- DXF flow
- DSF flow
- 2D rendering flow
- 3D rendering flow
- bend flow
- template flow
- undo/redo flow
```

No unnecessary rewrite should occur during P0.

------------------------------------------------------------------------

# 76. P1 --- CAD Document Acceptance Criteria

Verify:

``` text
✓ Stable IDs
✓ Central units
✓ Document metadata
✓ Geometry collection
✓ Feature collection
✓ Parameter collection
✓ Dimension collection
✓ Constraint collection
✓ Existing files remain readable
```

------------------------------------------------------------------------

# 77. P2/P3/P4 --- CAD Editor Acceptance Criteria

The existing editor should feel like a professional CAD environment.

Verify:

``` text
✓ Smooth zoom/pan
✓ Reliable selection
✓ Accurate snapping
✓ Correct coordinates
✓ Core geometry editing
✓ Modify tools
✓ Undo/redo
```

Do not proceed to complex template work if basic geometry editing is
unstable.

------------------------------------------------------------------------

# 78. P5/P6/P7 --- Dimension Acceptance Criteria

User can:

``` text
Create dimension
Select dimension
Move dimension annotation
Edit dimension
Change geometry through dimension
Undo dimension edit
Save
Reload
```

Dimension values must reflect actual geometry.

------------------------------------------------------------------------

# 79. P8 --- Constraint Acceptance Criteria

At minimum:

``` text
Horizontal
Vertical
Coincident
Parallel
Perpendicular
Distance
Angle
```

Test constraints on actual product geometry, not only artificial test
rectangles.

------------------------------------------------------------------------

# 80. P9/P10 --- DXF Acceptance Criteria

For each supplied DXF:

``` text
✓ Opens
✓ Correct scale
✓ Correct orientation
✓ Geometry preserved
✓ Layers preserved where applicable
✓ Holes visible
✓ Slots recognized where possible
✓ Bend candidates identified
✓ No silent destructive cleanup
```

------------------------------------------------------------------------

# 81. P12/P13/P14 --- Sheet-Metal Acceptance Criteria

For supplied product examples:

``` text
✓ Material
✓ Thickness
✓ Bend definitions
✓ Bend angle
✓ Bend radius
✓ Bend direction
✓ Flat pattern
✓ Folded 3D
✓ Unfolded state
```

The current working 3D engine should be reused and extended rather than
rewritten.

------------------------------------------------------------------------

# 82. P16/P17 --- Hole Acceptance Criteria

For the supplied cable tray/accessory drawings:

``` text
✓ Detect existing holes
✓ Detect obrounds
✓ Edit size
✓ Edit position
✓ Create pattern
✓ Change pitch
✓ Change quantity
✓ Regenerate positions
✓ Save/reload
```

------------------------------------------------------------------------

# 83. P19/P20 --- Parametric Engine Acceptance Criteria

A simple existing DXF template should be convertible to:

``` text
Parameter-driven template
```

Changing a parameter must update the correct dependent geometry.

Test:

``` text
Width
Height
Length
Thickness
Hole Pitch
Hole Offset
Bend Angle
```

where applicable.

------------------------------------------------------------------------

# 84. P21/P22 --- Template Acceptance Criteria

At least one real supplied DXF should become an intelligent template.

Recommended first candidates:

1.  Straight/cover-type geometry
2.  45° bend
3.  Riser
4.  Reducer
5.  Unequal tee
6.  Unequal cross

Do not start with the most complex product if a simpler template can
validate the engine.

------------------------------------------------------------------------

# 85. P23 --- Assembly Acceptance Criteria

Create a test ladder assembly:

``` text
Left Side Rail
Right Side Rail
10 Rungs
```

Support:

``` text
Equal spacing
Individual positioning
Quantity
Component references
Basic BOM
```

------------------------------------------------------------------------

# 86. P24 --- DSF Acceptance Criteria

Existing DSF files must continue to open.

New DSFs should preserve:

``` text
Geometry
Features
Bends
Dimensions
Parameters
Templates
Material
Thickness
Assembly data where applicable
```

Use schema versioning.

------------------------------------------------------------------------

# 87. P25 --- DDS/TDS Acceptance Criteria

Generate a technical document containing:

``` text
Product name
Product dimensions
Material
Thickness
Finish
2D drawing
3D view
BOM
Weight where available
Revision
Client/project metadata
```

It should be generated from the CAD model rather than manually
duplicating data.

------------------------------------------------------------------------

# 88. P26 --- Product Library Acceptance Criteria

The user should be able to find:

``` text
Cable Tray
Trunking
Cable Ladder
```

and their existing template families.

Templates should have:

``` text
Name
Family
Version
Description
Preview
Source
Parameter list
```

------------------------------------------------------------------------

# 89. UI Workflow --- Existing DXF

Final workflow:

``` text
START
  ↓
Open DXF
  ↓
Import Diagnostics
  ↓
2D Editor
  ↓
Clean / Repair
  ↓
Recognize Features
  ↓
Add / Edit Dimensions
  ↓
Add / Edit Bends
  ↓
Edit Holes / Patterns
  ↓
3D
  ↓
Validate
  ↓
Save DSF
  ↓
Generate TDS / DDS
```

------------------------------------------------------------------------

# 90. UI Workflow --- Template

``` text
Open DXF
   ↓
Convert to Template
   ↓
Define Parameters
   ↓
Define Dimensions
   ↓
Define Feature Relationships
   ↓
Define Hole Patterns
   ↓
Define Bend Parameters
   ↓
Test Regeneration
   ↓
Save Template
```

------------------------------------------------------------------------

# 91. UI Workflow --- Template Instance

``` text
Select Template
   ↓
Create New Instance
   ↓
Enter Dimensions
   ↓
Preview
   ↓
Generate
   ↓
Validate
   ↓
Save DSF
```

------------------------------------------------------------------------

# 92. Important UX Requirement

The user should not need to understand the underlying dependency graph.

The interface should expose simple engineering parameters.

For example:

``` text
UNEQUAL TEE

Main Branch
Width       [300]
Height      [100]

Branch 1
Width       [150]
Height      [75]

Branch 2
Width       [200]
Height      [50]

Thickness   [1.5]

Hole Pattern
[Obround 30 × 7]

          [Generate]
```

The dependency engine remains behind the UI.

------------------------------------------------------------------------

# 93. Do Not Over-Automate DXF Recognition

DXF recognition will not always be correct.

Therefore:

``` text
Automatic Recognition
        +
User Confirmation
        +
Manual Correction
```

is preferable to an opaque automatic process.

The user must be able to say:

``` text
This line is a bend.
This slot is a hole.
These 24 holes are one pattern.
This dimension controls this edge.
```

------------------------------------------------------------------------

# 94. Product Templates Must Allow Manual Overrides

Even after parameterization, the user should be able to manually modify
appropriate features.

A template should not become a locked black box.

However, if manual geometry modification breaks a parametric
relationship, the system should clearly communicate the state.

Possible states:

``` text
Fully Parametric
Partially Parametric
Manual Override
Invalid
```

------------------------------------------------------------------------

# 95. Template Regeneration and Manual Overrides

Example:

``` text
Width = 300
```

User manually moves a hole.

The application should know:

``` text
HolePattern01
    status = Manual Override
```

Later changing Width should not silently overwrite that manual change.

Provide a controlled option:

``` text
Reapply Pattern
```

or:

``` text
Restore Parametric Control
```

------------------------------------------------------------------------

# 96. History / Feature Ordering

Where the existing CAD system supports a feature history, maintain
predictable ordering.

Example:

``` text
Base Geometry
    ↓
Bend 01
    ↓
Bend 02
    ↓
Hole Pattern 01
    ↓
Cutout
```

Dependent features should know what they depend on.

Avoid hidden geometry mutations that bypass the history system.

------------------------------------------------------------------------

# 97. Error Handling

Engineering failures must be explicit.

Bad:

``` text
Generate failed.
```

Better:

``` text
Cannot regenerate Bend 03.

Reason:
Required bend radius 1.5 mm is below the minimum allowed
for thickness 2.0 mm.

Affected:
Bend 03
Flat Pattern
3D Model
```

Allow the user to fix the parameter.

------------------------------------------------------------------------

# 98. Logging / Diagnostics

Create engineering-level diagnostic logging for:

``` text
DXF import
Template regeneration
Bend calculation
Flat pattern
3D generation
DSF migration
Validation
```

Do not flood normal user logs.

Provide developer diagnostics that can be enabled when debugging.

------------------------------------------------------------------------

# 99. Future Phase 2 --- Parametric Product Generation

Phase 2 should reuse the Phase 1 CAD core.

Do not create a second CAD engine.

Phase 2 adds:

``` text
Product Generator
    ↓
Engineering Skeleton
    ↓
Generated Geometry
    ↓
Sheet Metal Features
    ↓
Flat Pattern
    ↓
3D
```

------------------------------------------------------------------------

# 100. Phase 2 Product Families

## Cable Tray

``` text
Straight Tray
Cover
45° Bend
90° Bend
Riser
Reducer
Tee
Unequal Tee
Cross
Unequal Cross
Coupler
```

## Trunking

``` text
Straight
Cover
Bend
Riser
Reducer
Tee
Cross
Coupler
```

Usually without cable-tray perforation patterns.

## Cable Ladder

``` text
Straight Ladder
Side Rail
Rung
Bend
Tee
Cross
Riser
Reducer
```

with assembly/fabrication logic.

------------------------------------------------------------------------

# 101. Phase 2 Parametric Inputs

Typical tray/fitting parameters:

``` text
Product Type
Width
Height
Length
Branch Width
Branch Height
Angle
Thickness
Material
Finish
Bend Radius
Hole Type
Hole Width
Hole Length
Pitch
Edge Offset
Cover
```

Changes must propagate through the entire model.

------------------------------------------------------------------------

# 102. Phase 2 Perforation Engine

Support:

``` text
Hole Type
Hole Width
Hole Length
Pitch
Rows
Columns
Edge Offset
Pattern Offset
Direction
```

Different faces may eventually have different patterns:

``` text
Bottom
Left Wall
Right Wall
Cover
End Connection
```

------------------------------------------------------------------------

# 103. Phase 2 Fitting Generator

Future generators:

``` text
Straight
Bend
Riser
Reducer
Tee
Unequal Tee
Cross
Unequal Cross
Coupler
Cover
```

The generator should create geometry from parameters rather than editing
a stored DXF.

------------------------------------------------------------------------

# 104. Phase 2 Connection Intelligence

Future components should expose connection interfaces.

Conceptually:

``` text
ConnectionPoint
    position
    direction
    width
    height
    systemType
```

Then:

``` text
Tray 300×100
      ↓
90° Bend 300×100
      ↓
Tray 300×100
      ↓
Reducer
      ↓
Tray 200×75
```

The system can detect incompatible connections and suggest a reducer
where appropriate.

------------------------------------------------------------------------

# 105. Phase 2 Ladder Generation

The ladder generator will eventually create:

``` text
Side Rail
Side Rail
Rungs
```

and support:

``` text
Rung quantity
Rung pitch
Start offset
End offset
Weld/fabrication information
```

Fittings become assemblies or multi-part products.

------------------------------------------------------------------------

# 106. Phase 2 Must Reuse Phase 1

The following must be common:

``` text
Geometry Engine
Dimension Engine
Constraint Engine
Bend Engine
Hole Engine
Pattern Engine
Flat Pattern Engine
3D Engine
Validation Engine
Command System
Undo/Redo
DSF
DDS
Renderer
```

Only the product-generation layer is new.

------------------------------------------------------------------------

# 107. Long-Term Architecture

The final architecture should conceptually become:

``` text
                     3D CAD STUDIO
                           |
                    COMMON CAD CORE
                           |
        +------------------+------------------+
        |                  |                  |
   Generic CAD       Sheet Metal        Assembly CAD
        |                  |                  |
        +------------------+------------------+
                           |
                  PRODUCT INTELLIGENCE
                           |
        +------------------+------------------+
        |                  |                  |
    Cable Tray         Trunking          Cable Ladder
        |                  |                  |
   Generators          Generators        Generators
        |                  |                  |
        +------------------+------------------+
                           |
                      DSF / DDS / DXF
```

------------------------------------------------------------------------

# 108. Phase 1 vs Phase 2 Boundary

## Phase 1

Focus on:

``` text
Professional CAD editor
+
Sheet-metal intelligence
+
Existing DXF modification
+
DXF-derived templates
+
Dimensions
+
Constraints
+
Bends
+
Holes
+
Patterns
+
Flat pattern
+
3D
+
Validation
+
Assemblies
+
DSF
+
DDS/TDS
```

## Phase 2

Focus on:

``` text
Fully parametric product generation
+
Cable tray generators
+
Trunking generators
+
Cable ladder generators
+
Complex tee/cross/reducer mathematics
+
Connection intelligence
+
Product configurator
```

------------------------------------------------------------------------

# 109. What Not to Do in Phase 1

Do not spend Phase 1 primarily on:

``` text
Full automatic tee generation from scratch
Full automatic cross generation from scratch
Complete cable routing
Load calculations
Structural analysis
Advanced nesting
CNC post processors
ERP integration
Complex assembly solver
Full product configurator
```

These are future capabilities.

------------------------------------------------------------------------

# 110. Priority Order

If implementation resources are limited, prioritize:

``` text
1. Existing CAD stability
2. 2D editing
3. Dimensions
4. DXF handling
5. Sheet-metal bends
6. 2D/3D synchronization
7. Holes/patterns
8. Flat pattern
9. Validation
10. Parametric parameters
11. DXF templates
12. Template regeneration
13. Assembly
14. DSF extension
15. DDS/TDS
16. Product library
```

------------------------------------------------------------------------

# 111. Agent Working Method

For every task, the agent should report internally or in its
implementation notes:

``` text
TASK
What is being implemented?

EXISTING
What already exists?

CHANGE
What will be changed?

DEPENDENCIES
What existing systems are affected?

IMPLEMENTATION
What files/classes/services are modified?

TEST
What automated/manual tests are added?

REGRESSION
What existing functionality was verified?

STATUS
Complete / Partial / Blocked
```

This makes the project manageable across many iterations.

------------------------------------------------------------------------

# 112. Do Not Make Large Unrelated Refactors

Avoid combining:

``` text
New feature
+
Renderer rewrite
+
State-management rewrite
+
DXF rewrite
+
UI redesign
```

in one change.

Prefer:

``` text
One feature
One controlled architectural improvement
Tests
Verification
```

This is especially important because the current CAD Studio is already
functional.

------------------------------------------------------------------------

# 113. Preserve Existing User Work

The agent must protect:

-   existing DXF files
-   existing DSF files
-   existing templates
-   existing CAD projects
-   existing 3D designs

Before changing file formats:

``` text
Backup / migration
```

must be considered.

------------------------------------------------------------------------

# 114. Final Phase 1 User Experience

The finished application should make the user feel that they are using a
genuine sheet-metal CAD system rather than a DXF viewer/editor.

The workflow should feel like:

``` text
DRAW
EDIT
DIMENSION
CONSTRAIN
BEND
HOLE
PATTERN
FOLD
UNFOLD
MEASURE
VALIDATE
SAVE
DOCUMENT
```

and, for existing products:

``` text
IMPORT
UNDERSTAND
PARAMETERIZE
MODIFY
REGENERATE
```

------------------------------------------------------------------------

# 115. Final Acceptance Test

Before declaring Phase 1 complete, the agent must demonstrate:

## CAD

``` text
✓ Professional 2D editor
✓ Existing 3D editor preserved/improved
✓ Reliable selection
✓ Snapping
✓ Geometry tools
✓ Modify tools
✓ Dimensions
✓ Direct dimension editing
✓ Constraints
```

## Sheet Metal

``` text
✓ Bend
✓ Radius
✓ Angle
✓ Direction
✓ K-factor
✓ Allowance
✓ Relief
✓ Flat pattern
✓ Folded 3D
```

## DXF

``` text
✓ Import
✓ Export
✓ Diagnostics
✓ Recognition
✓ Cleanup
```

## Template

``` text
✓ Existing DXF → template
✓ Parameters
✓ Dependencies
✓ Controlled regeneration
✓ Manual override handling
```

## Holes

``` text
✓ Hole
✓ Slot
✓ Pattern
✓ Recalculation
```

## Assembly

``` text
✓ Components
✓ Instances
✓ Repetition
✓ Basic ladder assembly
```

## Files

``` text
✓ DSF
✓ DSF migration/versioning
✓ DDS/TDS
```

## Engineering

``` text
✓ Validation
✓ Regression tests
✓ Real sample DXF tests
```

------------------------------------------------------------------------

# 116. Final Development Philosophy

The CAD Studio should evolve in layers.

Do not jump directly from:

``` text
DXF editor
```

to:

``` text
Full parametric product generator
```

Build the foundation:

``` text
Geometry
    ↓
Features
    ↓
Dimensions
    ↓
Constraints
    ↓
Sheet Metal
    ↓
Bends
    ↓
Holes
    ↓
Patterns
    ↓
Flat Pattern
    ↓
3D
    ↓
Validation
    ↓
Parameters
    ↓
Dependencies
    ↓
Templates
    ↓
Assemblies
    ↓
Product Intelligence
```

Each layer should build on the previous layer.

------------------------------------------------------------------------

# 117. Most Important Instruction to the Agent

> **The existing 3D CAD Studio is already a working application. This
> project is an extension and maturation of that application, not a
> rewrite. Preserve what works, inspect before changing, reuse existing
> implementations, and add capabilities in small tested batches.**

> **The Phase 1 goal is to create a professional sheet-metal CAD
> environment capable of importing existing manufactured DXFs, editing
> them with real CAD dimensions/features, adding sheet-metal
> intelligence, generating synchronized 3D models, and converting
> selected existing DXFs into intelligent reusable templates.**

> **The Phase 2 goal is to use the same CAD core to generate cable tray,
> trunking, and cable ladder products directly from engineering
> parameters.**

> **Do not implement Phase 2 prematurely. Build Phase 1 so that Phase 2
> becomes an extension of the same architecture rather than a second CAD
> system.**

------------------------------------------------------------------------

# 118. Immediate Next Action for the Agent

Start with:

``` text
P0 — COMPLETE CODEBASE AUDIT
```

Do not begin by implementing new product generators.

First identify:

1.  What CAD functionality already exists.
2.  What sheet-metal functionality already exists.
3.  What DXF functionality already exists.
4.  What DSF functionality already exists.
5.  What template functionality already exists.
6.  What 2D/3D synchronization already exists.
7.  What dimension functionality already exists.
8.  What hole/pattern functionality already exists.
9.  What assembly functionality already exists.
10. What is missing.
11. What is incomplete.
12. What needs only UI improvement.
13. What needs engineering-core improvement.
14. What needs file-schema changes.

Then create an implementation plan based on the actual codebase.

**Do not assume a feature is missing simply because it is listed in this
document. Verify it first.**

------------------------------------------------------------------------

# 119. Success Criterion

The success of Phase 1 is not the number of buttons/features
implemented.

The success criterion is:

> **Can a real Bonn manufactured DXF be opened, understood, edited using
> professional CAD tools, dimensionally modified, bent/folded correctly,
> regenerated where appropriate, validated, saved as an intelligent DSF,
> and documented as a technical data sheet --- while preserving the
> existing working CAD Studio functionality?**

If yes, Phase 1 has achieved its objective.
