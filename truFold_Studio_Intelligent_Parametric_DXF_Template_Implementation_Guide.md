# truFold Studio — Intelligent Parametric DXF Template Architecture

## Engineering Review and Step-by-Step Implementation Guide

**Primary scope:** Extend the existing truFold Studio CAD application.  
**Phase 1:** Constraint-driven modification of existing sheet-metal DXF templates.  
**Future scope:** Native parametric generation of cable-management products in Phase 2.

---

## 1. Purpose

The existing truFold Studio application already contains a substantial working CAD foundation. The coding agent has implemented most of the following capabilities:

- 2D CAD/sketch editing
- 3D sheet-metal visualization
- Bend-related functionality
- DXF import and export
- DSF import and export
- Existing template/design functionality
- Selection and editing workflows
- Some port-assignment functionality
- Some template scaling or geometry-morphing functionality
- Some perforation regeneration
- Some 3D regeneration

**This document is not a request to rebuild the CAD application.**

The objective is to audit, preserve, extend, and improve the existing implementation so that an imported DXF can become an intelligent, reusable, parameter-driven template.

The final goal is:

```text
Existing DXF
    ↓
Clean and classify geometry
    ↓
Identify semantic features
    ↓
Add reference/construction geometry
    ↓
Add geometric and dimensional constraints
    ↓
Add named parameters and expressions
    ↓
Create feature dependencies
    ↓
Save as an intelligent DSF template
    ↓
Change W / H / L / R / port dimensions
    ↓
Recalculate dependent geometry
    ↓
Regenerate holes, reliefs, bends and patterns
    ↓
Rebuild flat pattern
    ↓
Update 3D model
    ↓
Validate
    ↓
Export DXF / DSF / technical data
```

The system must not rely primarily on blindly stretching DXF vertices.

---

## 2. Critical Architectural Direction

### 2.1 The DXF is starting geometry, not the final intelligence

An imported DXF may contain:

- Lines
- Arcs
- Polylines
- Circles
- Obround slots
- Cutouts
- Bend indicators
- Construction lines
- Reliefs
- Hole patterns
- Coupler holes
- Outer boundaries

A DXF generally does not fully describe why each element exists or how it should behave when a dimension changes.

The application must therefore convert raw geometry into a richer model containing:

- Semantic entities
- Reference geometry
- Geometric constraints
- Dimensional constraints
- Named parameters
- Feature dependencies
- Pattern definitions
- Port definitions
- Sheet-metal feature definitions
- Manufacturing rules

### 2.2 Zone morphing is a supporting mechanism

The existing `TopologicalZoneMorpher`, or equivalent geometry-morphing implementation, may be retained and improved.

However, it must not be the primary source of truth.

The correct relationship is:

```text
Parameters
    ↓
Constraints and dependency graph
    ↓
Feature recalculation
    ↓
Geometry transformation or regeneration
    ↓
Flat pattern and 3D update
```

Not:

```text
UI slider
    ↓
Move arbitrary vertices
    ↓
Stretch zones
    ↓
Hope geometry remains valid
```

Zone-based movement can remain useful for:

- Translating rigid feature groups
- Stretching known planar regions
- Preserving standard punch shapes
- Moving coupler-hole clusters
- Adjusting simple legacy templates

But every zone operation must be driven by explicit template rules.

---

## 3. Engineering Principles

### 3.1 Preserve existing working functionality

Before changing code, inspect and document:

1. Current geometry model
2. Current sketch model
3. Current constraint implementation
4. Current dimension implementation
5. Current sheet-metal engine
6. Current 2D renderer
7. Current 3D renderer
8. Current DXF importer/exporter
9. Current DSF serializer/deserializer
10. Current template system
11. Current undo/redo system
12. Current selection and picking system
13. Current validation system
14. Current port-assignment implementation
15. Current zone-morphing implementation

Do not replace a subsystem merely because it is incomplete. Extend it where practical.

### 3.2 One CAD engine only

Cable-tray accessories and trunking accessories must use the same core CAD engine.

Use shared infrastructure with product-specific rules.

```text
Shared SheetMetalTemplate
    ├── CableTrayAccessoryTemplate
    │      └── perforation rules
    └── TrunkingAccessoryTemplate
           └── no perforation or different hole rules
```

### 3.3 Explicit units

Use millimetres as the internal engineering unit where practical.

Do not mix screen pixels, DXF units, millimetres, and inches inside engineering calculations.

Screen coordinates must be converted before entering the engineering model.

### 3.4 Stable IDs

Every important object must have a stable ID.

Do not reference entities by array index.

Stable IDs are required for:

- Sketch entities
- Edges
- Vertices
- Constraints
- Dimensions
- Parameters
- Features
- Hole groups
- Bend features
- Ports
- Construction geometry
- Zones
- DSF references

### 3.5 Deterministic recalculation

Given the same template, parameters, material, thickness, bend settings, and constraints, the application should produce the same geometry.

Avoid hidden state and undocumented transformations.

### 3.6 Separate model, calculation, and rendering

Use a structure similar to:

```text
UI
    ↓
Application commands/state
    ↓
CAD domain model
    ↓
Constraint/dependency engine
    ↓
Geometry and sheet-metal calculations
    ↓
2D/3D renderers
```

Flutter widgets should not directly perform engineering geometry calculations.

---

## 4. Important Correction: Port Dimensions Are Not Always DXF Edge Lengths

A selected flat-pattern edge may be useful as a reference, but it is not automatically equal to the finished 3D port dimension.

The application must distinguish:

- 3D clear opening width
- 3D clear opening height
- Flat-pattern edge length
- Bend-to-bend distance
- Outer flange length
- Inside return length
- Developed length
- Neutral-axis length
- Finished external dimension

Therefore:

```text
Port opening width
    ≠ necessarily
Flat-pattern edge length
```

The difference may depend on:

- Material thickness
- Inside bend radius
- Bend angle
- K-factor
- Bend allowance
- Bend deduction
- Bend position
- Measurement reference

A port definition should be able to distinguish:

```text
openingWidth
openingHeight
flatReferenceWidth
flatReferenceHeight
bendToBendDistance
measurementReference
```

### Mandatory rule

> All sheet-metal development calculations must continue to use the existing sheet-metal bend and bend-allowance engine. Do not duplicate simplified bend calculations inside the template-scaling subsystem.

A simplified expression such as `W + 2H + 2F` may describe a cross-section conceptually, but it must not replace the actual development calculation.

---

## 5. Geometry Behavior Classification

Every geometry object or feature must be classified according to its behavior during recalculation.

### 5.1 Rigid geometry

Geometry that retains its own shape and dimensions.

Examples:

- Hole profiles
- Obround slot profiles
- Standard coupler slots
- M6/M8 hole profiles
- Standard relief cutouts
- Tooling features
- Standard notch shapes

Rigid does not necessarily mean fixed in position. A rigid feature may translate or rotate as a group.

### 5.2 Parametric geometry

Geometry controlled by parameters and constraints.

Examples:

- Port width
- Port height
- Overall length
- Bend radius
- Flange height
- Hole offset
- Hole pitch
- Pattern quantity
- Branch position

### 5.3 Derived geometry

Geometry calculated from other geometry or parameters.

Examples:

- Miter boundaries
- Junction boundaries
- Bend-line endpoints
- Tapered reducer edges
- Corner-relief locations
- Developed bend regions
- 3D folded faces

### 5.4 Pattern geometry

Repeated geometry generated from a pattern definition.

Examples:

- Floor perforations
- Side-wall holes
- Coupler-slot arrays
- Repeated mounting holes
- Repeated branch features

Pattern members should not normally be individually stretched.

### 5.5 Reference geometry

Non-manufacturing geometry used for positioning and constraints.

Examples:

- Centerlines
- Construction lines
- Datum axes
- Datum points
- Port centerlines
- Bend reference lines
- Symmetry axes
- Reference edges

Reference geometry must be selectable for constraints but excluded from manufacturing output by default.

---

## 6. Constraint System

The application should evolve toward a simple Fusion 360 / Onshape-style sketch constraint system.

Do not implement every advanced constraint immediately.

### 6.1 Initial geometric constraints

Implement or verify:

1. Coincident
2. Horizontal
3. Vertical
4. Parallel
5. Perpendicular
6. Concentric
7. Equal
8. Symmetric
9. Collinear
10. Midpoint
11. Fixed/Lock

### 6.2 Dimensional constraints

Support:

- Horizontal distance
- Vertical distance
- Aligned distance
- Radius
- Diameter
- Angle
- Point-to-line distance
- Edge-to-edge distance
- Center-to-center distance
- Hole-to-edge distance
- Hole-to-hole distance
- Bend-to-edge distance
- Bend-to-bend distance

A dimensional constraint should contain at least:

```text
constraintId
constraintType
referencedEntityIds
value
unit
isDriving
parameterReference
tolerance
suppressionState
```

### 6.3 Driving versus reference dimensions

A dimension must be either:

- **Driving:** controls geometry
- **Reference:** reports geometry without controlling it

Example:

```text
Driving:
    Port3Width = 200 mm

Reference:
    ActualFlatEdgeLength = 214.6 mm
```

Do not allow conflicting driving dimensions to control the same degree of freedom without a clear conflict response.

### 6.4 Constraint ownership

Constraints must reference stable entity IDs.

Example:

```text
Constraint:
    type = Symmetric
    entityA = edge_left
    entityB = edge_right
    symmetryReference = port3_centerline
```

Example:

```text
Constraint:
    type = Distance
    entityA = hole_center_01
    entityB = port_left_edge
    value = HoleEdgeOffset
```

### 6.5 Constraint states

Expose:

- Fully constrained
- Under-constrained
- Over-constrained
- Conflicting
- Suppressed
- Invalid reference

A complete industrial-grade solver is not required immediately, but the model must be extensible.

---

## 7. Construction and Reference Geometry

Add or verify the ability to create:

- Construction lines
- Centerlines
- Datum points
- Reference axes
- Reference edges
- Port centerlines
- Symmetry lines
- Bend reference lines

Recommended behavior:

- Construction geometry is selectable.
- Construction geometry can receive constraints.
- Construction geometry can drive parameters.
- Construction geometry is not exported as cutting geometry by default.
- Centerlines can be used as symmetry references.
- Port dimensions can be centered around a centerline.

Example:

```text
Port 3 centerline
        │
        │
        │
────────┼──────── Main reference
        │
        │
```

If:

```text
Port3Width = 300 mm
```

then:

```text
Port3Left  = CenterX - 150 mm
Port3Right = CenterX + 150 mm
```

The branch expands symmetrically without manually moving unrelated vertices.

---

## 8. Named Parameters and Expressions

Templates must use named parameters instead of hardcoded numbers wherever practical.

### 8.1 Example parameters

```text
W
H
L
R
Thickness
FlangeHeight
InsideReturn
Port1Width
Port1Height
Port2Width
Port2Height
Port3Width
Port3Height
Port4Width
Port4Height
HoleOffset
HolePitch
PatternMargin
BranchOffset
AlignmentMode
```

### 8.2 Parameter record

A parameter should contain:

```text
parameterId
name
displayName
value
unit
minimum
maximum
defaultValue
expression
category
description
isUserEditable
isReadOnly
```

### 8.3 Expressions

Support expressions such as:

```text
Port3Width = W
Port3Left = Port3Center - Port3Width / 2
Port3Right = Port3Center + Port3Width / 2
OutsideRadius = InsideRadius + ChannelWidth
BranchOffset = (MainWidth - BranchWidth) / 2
```

Expressions must be parsed safely and evaluated deterministically.

Do not execute arbitrary code.

### 8.4 Parameter validation

Before applying a parameter change, validate:

- Minimum and maximum values
- Positive lengths
- Valid radius
- Valid thickness
- Valid bend radius
- Minimum material conditions
- Valid port relationships
- No impossible negative regions
- No self-intersections
- No invalid hole placement

---

## 9. Dependency Graph

The dependency graph is the central intelligence of the template system.

A dependency must be explicit.

Example:

```text
Port3Width
    ↓
Port3 reference edges
    ↓
Branch floor boundary
    ↓
Junction region
    ↓
Miter geometry
    ↓
Bend-line endpoints
    ↓
Flat-pattern face decomposition
    ↓
3D folded model
    ↓
Validation
```

Another example:

```text
PortWidth
    ↓
Available floor area
    ↓
Perforation pattern bounds
    ↓
Pattern count
    ↓
Hole positions
    ↓
Manufacturing output
```

### 9.1 Dependency node types

Support dependencies between:

- Parameters
- Sketch entities
- Reference geometry
- Features
- Hole groups
- Bend features
- Port definitions
- Pattern definitions
- Zones
- Derived faces
- 3D bodies
- Manufacturing outputs

### 9.2 Dirty-state recalculation

When a parameter changes:

```text
Parameter changed
    ↓
Mark dependent nodes dirty
    ↓
Recalculate affected nodes in dependency order
    ↓
Update renderers
    ↓
Run validation
```

Reuse any existing recalculation system where practical.

---

## 10. Semantic Port Model

A port is more than a selected edge.

A port should contain:

```text
portId
name
portType
direction
openingWidth
openingHeight
widthParameterId
heightParameterId
centerReferenceId
widthReferenceId
heightReferenceIds
orientation
connectionType
alignmentMode
associatedFeatureIds
```

Possible port types:

- Inlet
- Outlet
- Branch
- Cross arm
- Reducer large end
- Reducer small end

Possible direction values:

- North
- South
- East
- West
- Custom vector
- Custom angle

### 10.1 Port references

A port may reference:

- A width measurement
- A height measurement
- A centerline
- A boundary edge
- A bend line
- A side-wall pair
- A junction region

Do not assume one selected DXF edge fully defines a port.

### 10.2 Port dimensions

A port may contain:

```text
openingWidth
openingHeight
wallHeight
flatWidthReference
flatHeightReference
```

The UI must clearly distinguish user inputs, derived values, and reference measurements.

---

## 11. Hole and Pattern Relationships

Individual holes must retain their shape.

Changing a product dimension should generally move or regenerate holes, not distort their profiles.

### 11.1 Hole feature

```text
holeId
profileType
width
length
diameter
positionReference
orientation
isRigid
```

### 11.2 Hole group

```text
groupId
hostFaceId
hostPortId
patternType
holeProfile
holeWidth
holeLength
pitchX
pitchY
rowCount
columnCount
edgeOffset
startOffset
endOffset
patternOffset
alignment
behavior
```

### 11.3 Pattern behavior modes

Support:

1. Fixed count
2. Fixed pitch
3. Fill available area
4. Maintain edge margins
5. Center pattern
6. Align to reference centerline
7. Preserve end offsets

Example:

```text
W = 300 mm
    ↓
Available pattern area recalculated
    ↓
Number of columns recalculated
    ↓
Standard obround slots regenerated
```

The obround dimensions remain unchanged.

### 11.4 Hole constraints

Examples:

```text
Hole center is 15 mm from left edge
Hole center is 15 mm from right edge
Hole group is centered on port centerline
Hole row is parallel to bend line
Hole pitch is 30 mm
Hole pattern has equal spacing
```

---

## 12. Product-Specific Template Strategies

### 12.1 90-degree bend

Parameters:

```text
Width
Height
LengthIn
LengthOut
InsideRadius
Thickness
FlangeHeight
```

Dependencies:

```text
Port dimensions
    ↓
Straight-leg geometry
    ↓
Throat geometry
    ↓
Inner and outer bend boundaries
    ↓
Miter and relief features
    ↓
Bend lines
    ↓
3D
```

Do not assume every miter or relief is always rigid. Classify each feature as rigid, parametric, derived, or pattern-based.

### 12.2 Reducer

Support:

```text
WidthIn
WidthOut
HeightIn
HeightOut
Length
AlignmentMode
```

Alignment modes:

- Center
- Left
- Right

For a concentric reducer:

```text
Offset = (WidthIn - WidthOut) / 2
```

For left alignment:

```text
Left reference remains fixed
Right boundary absorbs the width difference
```

For right alignment:

```text
Right reference remains fixed
Left boundary absorbs the width difference
```

The reducer should not require separate DXF files for each width combination.

### 12.3 Equal tee

Begin with:

```text
MainWidth
MainHeight
BranchWidth
BranchHeight
Length
BranchCenter
```

Use centerlines and symmetry constraints wherever possible.

### 12.4 Unequal tee

Support independent values:

```text
Port1Width
Port1Height
Port2Width
Port2Height
Port3Width
Port3Height
```

The tee should contain semantic regions such as:

```text
MainCenterline
BranchCenterline
Port1Transition
Port2Transition
Port3Transition
JunctionRegion
MiterFeatures
ReliefFeatures
HoleGroups
BendFeatures
```

Changing one port must not blindly stretch the complete drawing.

Example:

```text
Port3Width changes
    ↓
Branch opening changes
    ↓
Branch floor changes
    ↓
Junction boundaries recalculate
    ↓
Miter features recalculate
    ↓
Bend-line endpoints recalculate
    ↓
Hole patterns recalculate
    ↓
3D updates
```

### 12.5 Equal cross

Use four port definitions and two reference centerlines.

Parameters:

```text
Port1Width
Port2Width
Port3Width
Port4Width
Port1Height
Port2Height
Port3Height
Port4Height
MainCenterX
MainCenterY
BranchCenterX
BranchCenterY
```

### 12.6 Unequal cross

Use the same architecture as the unequal tee, but with four independent port definitions and a junction-topology model.

Do not implement it as four unrelated edge-scaling operations.

### 12.7 Trunking accessories

Trunking accessories must reuse the same template, constraint, parameter, dependency, bend, DSF, and 3D systems.

Differences may include:

- No floor perforations
- Different flange or cover rules
- Different bend reliefs
- Different connection features
- Different dimensional standards

Do not create a separate CAD engine for trunking.

---

## 13. Manufacturing and Bend Calculations

The template system must use the existing sheet-metal engine for:

- Bend allowance
- Bend deduction
- K-factor
- Neutral axis
- Inside radius
- Outside radius
- Thickness compensation
- Flat-pattern development
- Folded 3D geometry

The template system defines geometric intent. It must not duplicate engineering calculations.

```text
Template parameters
    ↓
Geometric intent
    ↓
Existing sheet-metal engine
    ↓
Developed flat pattern
    ↓
3D folded result
```

---

## 14. DSF Evolution

The existing DSF format is already implemented and should be preserved where possible.

It may need a backward-compatible extension to store intelligent template data.

### 14.1 Recommended DSF additions

```text
schemaVersion
templateMetadata
parameters
expressions
constraints
referenceGeometry
semanticEntities
ports
features
dependencies
patterns
zones
sheetMetalSettings
manufacturingRules
validationSettings
```

### 14.2 Backward compatibility

The agent must:

1. Continue opening existing DSF files.
2. Detect the DSF schema version.
3. Migrate older files into the current internal model.
4. Preserve unknown fields where practical.
5. Avoid silently discarding data.
6. Write the current schema version on save.
7. Add migration tests.

### 14.3 Legacy DXF-based templates

A legacy template may initially contain only geometry, bend information, hole information, port assignments, and zone definitions.

Allow gradual enrichment:

```text
Legacy DXF/DSF
    ↓
Add semantic references
    ↓
Add constraints
    ↓
Add parameters
    ↓
Add dependencies
    ↓
Save as intelligent template
```

---

## 15. User Interface Requirements

The UI should expose the intelligence without overwhelming the user.

### 15.1 Sketch/editor tools

Provide or verify:

- Select
- Line
- Polyline
- Rectangle
- Circle
- Arc
- Obround/slot
- Construction line
- Centerline
- Point
- Trim
- Extend
- Offset
- Mirror
- Move
- Rotate
- Copy
- Measure
- Dimension
- Constraint tools

### 15.2 Constraint toolbar

Initially include:

- Coincident
- Horizontal
- Vertical
- Parallel
- Perpendicular
- Concentric
- Equal
- Symmetric
- Distance
- Angle
- Fix/Lock

### 15.3 Constraint visualization

Display:

- Constraint icons
- Driving dimensions
- Reference dimensions
- Construction geometry
- Selected-constraint highlights
- Over-constraint warnings
- Under-constraint indicators
- Suppressed constraints

### 15.4 Parameter panel

Display:

- Parameter name
- Current value
- Unit
- Minimum
- Maximum
- Expression
- Driving/reference state
- Description
- Reset action

### 15.5 Template inspector

Allow:

- Product family selection
- Product type selection
- Port listing
- Port dimension editing
- Port reference assignment
- Parameter editing
- Constraint inspection
- Pattern editing
- Zone inspection
- Dependency preview
- Validation status
- Save as template

### 15.6 Documentation accuracy

Do not document or expose a control until it is actually implemented.

Do not claim that a dialog minimizes, that a context menu exists, or that a shortcut works unless the code supports it.

---

## 16. Step-by-Step Implementation Sequence

The agent must proceed in small, verifiable sets.

Do not start with unequal tees or unequal crosses.

### Set 0 — Repository and architecture audit

Tasks:

- Inspect the existing codebase.
- Map the current CAD architecture.
- Identify duplicate or overlapping systems.
- Record existing functionality.
- Record missing functionality.
- Record the current DSF schema.
- Record current template and morphing behavior.
- Identify regression risks.

Deliverable:

```text
CAD_ENGINE_AUDIT.md
```

Acceptance criteria:

- No major subsystem is rewritten without justification.
- Existing import/export and 3D workflows remain operational.
- The agent documents where each new feature will integrate.

### Set 1 — Stabilize the internal geometry model

Tasks:

- Verify stable IDs.
- Verify millimetre-based internal units.
- Separate model coordinates from screen coordinates.
- Verify entity ownership.
- Verify geometry tolerances.
- Verify serialization of entities.

Acceptance criteria:

- Existing DXF files still open.
- Existing DSF files still open.
- Existing 2D and 3D views still work.
- Entity IDs remain stable after edits and save/load.

### Set 2 — Constraint data model

Tasks:

- Add or extend the constraint model.
- Implement the initial constraint types.
- Store entity references by stable ID.
- Support driving/reference state.
- Add constraint validation.
- Add conflict reporting.

Acceptance criteria:

- A line can be made horizontal.
- Two points can be made coincident.
- Two entities can be made symmetric around a centerline.
- A distance can be assigned and edited.
- Invalid references are reported.
- Existing CAD behavior is not broken.

### Set 3 — Constraint solver integration

Tasks:

- Audit any existing solver.
- Reuse it if suitable.
- Implement a minimal deterministic solver or adapter.
- Add solve status.
- Add under-constrained and over-constrained reporting.
- Add solve-failure recovery.

Acceptance criteria:

- A constrained rectangle can resize correctly.
- A symmetric feature remains symmetric after a dimension change.
- Conflicting constraints do not silently corrupt geometry.
- Failed solves preserve the last valid state or clearly mark the document invalid.

### Set 4 — Construction/reference geometry

Tasks:

- Add construction lines.
- Add centerlines.
- Add datum points.
- Add reference edges.
- Allow constraints to reference construction geometry.
- Exclude construction geometry from manufacturing output by default.

Acceptance criteria:

- A port can be centered around a construction line.
- A hole group can be aligned to a centerline.
- Construction geometry is visibly distinguishable.
- Construction geometry survives DSF save/load.

### Set 5 — Named parameters and expressions

Tasks:

- Add parameter records.
- Add parameter editing UI.
- Add units and limits.
- Add safe expression evaluation.
- Add parameter dependency tracking.
- Add validation.

Acceptance criteria:

- A parameter named `W` can drive a distance.
- Changing `W` updates constrained geometry.
- Invalid values are rejected.
- Expressions are saved and restored.
- No arbitrary executable code can be evaluated.

### Set 6 — Dependency graph

Tasks:

- Add explicit dependency nodes.
- Add dependency edges.
- Add dirty-state propagation.
- Add deterministic recalculation order.
- Add cycle detection.
- Add recalculation diagnostics.

Acceptance criteria:

- Changing one parameter updates only affected features.
- Cyclic dependencies are detected.
- Recalculation order is reproducible.
- The UI can display a basic dependency chain.

Example:

```text
W
 ↓
Port edge
 ↓
Face boundary
 ↓
Hole pattern
 ↓
Flat pattern
 ↓
3D
```

### Set 7 — Semantic geometry classification

Tasks:

- Classify entities as rigid, parametric, derived, pattern, or reference.
- Add semantic labels.
- Add feature ownership.
- Allow authoring tools to assign classifications.

Acceptance criteria:

- A standard obround remains undistorted.
- A derived miter can be regenerated.
- A reference centerline is not exported as cutting geometry.
- A pattern is regenerated rather than stretched.

### Set 8 — Port model and port assignment

Tasks:

- Extend the current port system.
- Separate port opening dimensions from flat-edge measurements.
- Add port centerline/reference support.
- Add width and height references.
- Add port direction and orientation.
- Add driving versus reference dimensions.
- Preserve current port-assignment workflows where they work.

Acceptance criteria:

- A port can be assigned to an existing DXF.
- The port has stable references.
- Width and height can be edited independently.
- The UI distinguishes opening dimensions from flat measurements.
- Invalid or duplicate port assignments are reported.

### Set 9 — First intelligent DXF template

Use **one simple existing 90-degree bend DXF**.

Tasks:

1. Import the DXF.
2. Clean and validate geometry.
3. Identify the outer boundary.
4. Identify bend lines.
5. Identify side-wall regions.
6. Add a centerline or datum.
7. Add one driving width parameter.
8. Add one driving height parameter.
9. Add constraints.
10. Save as an intelligent DSF template.
11. Change width.
12. Change height.
13. Recalculate geometry.
14. Rebuild the flat pattern.
15. Update 3D.
16. Validate the result.

Acceptance criteria:

- The original template remains recoverable.
- Width changes affect intended geometry only.
- Height changes affect intended geometry only.
- Standard holes retain their shape.
- 2D and 3D remain synchronized.
- Invalid configurations are rejected.

### Set 10 — Hole relationship and pattern engine

Tasks:

- Convert one existing hole group into a pattern feature.
- Add edge references.
- Add pitch and margin parameters.
- Add fixed-count and fixed-pitch modes.
- Add fill-available-area mode.
- Preserve hole profile dimensions.

Acceptance criteria:

- Hole dimensions remain constant.
- Hole positions update when the host region changes.
- Hole count updates when configured to do so.
- Hole groups remain aligned to their reference edge or centerline.
- Holes do not cross forbidden boundaries.

### Set 11 — 90-degree bend template

Tasks:

- Add complete port definitions.
- Add radius parameter.
- Add miter and relief dependencies.
- Add bend-line dependencies.
- Add validation.
- Reuse the existing sheet-metal engine for development and 3D.

Acceptance criteria:

- Width, height, length, and radius can be edited.
- The folded model updates.
- Flat-pattern dimensions remain consistent with the sheet-metal engine.
- Reliefs and miters remain valid.
- No duplicate bend calculation is introduced.

### Set 12 — Reducer template

Parameters:

```text
WidthIn
WidthOut
HeightIn
HeightOut
Length
AlignmentMode
```

Tasks:

- Implement concentric alignment.
- Implement left alignment.
- Implement right alignment.
- Add tapered derived geometry.
- Add port dependencies.
- Add validation.

Acceptance criteria:

- Widths can be changed independently.
- Alignment mode works without separate DXF files.
- Taper boundaries remain connected.
- No self-intersections occur within valid limits.
- Flat and folded representations agree.

### Set 13 — Equal tee

Tasks:

- Add main and branch centerlines.
- Add semantic junction region.
- Add branch width and height parameters.
- Add miter and relief dependencies.
- Add hole-group ownership.
- Add validation.

Acceptance criteria:

- Main and branch dimensions can be changed.
- The branch remains aligned to its reference centerline.
- Junction geometry remains connected.
- Holes and reliefs update correctly.
- The result is not produced by indiscriminate global scaling.

### Set 14 — Unequal tee

Support:

```text
Port1Width
Port1Height
Port2Width
Port2Height
Port3Width
Port3Height
```

Tasks:

- Define tee topology.
- Define main and branch centerlines.
- Define port-transition regions.
- Define junction region.
- Define derived miter geometry.
- Define relief behavior.
- Define hole-group behavior.
- Define bend-line dependencies.
- Add independent-port validation.

Acceptance criteria:

- Each port can be changed independently.
- Main inlet and outlet can have different dimensions.
- The branch can have a different width and height.
- Junction geometry remains connected.
- Miter and relief geometry remains valid.
- Hole patterns remain valid.
- Invalid combinations are rejected with useful messages.
- The system does not require a separate DXF for each variation.

This is the primary architectural proof of the Phase 1 system.

### Set 15 — Equal cross

Tasks:

- Add four port definitions.
- Add two centerline systems.
- Add junction topology.
- Add derived quadrant and relief geometry.
- Add validation.

Acceptance criteria:

- Four ports can be configured.
- Equal configurations work.
- Port changes propagate to the correct regions.
- The junction remains connected.

### Set 16 — Unequal cross

Tasks:

- Extend the equal-cross topology.
- Add independent port dimensions.
- Add independent height values.
- Add derived junction behavior.
- Add miter and relief dependencies.
- Add pattern and hole ownership.

Acceptance criteria:

- Four independent port sizes are supported.
- Changes do not distort rigid features.
- Junction geometry remains valid.
- Invalid combinations are rejected clearly.

### Set 17 — Trunking templates

Tasks:

- Reuse all generic infrastructure.
- Add trunking-specific product rules.
- Disable or omit perforation behavior where not applicable.
- Add trunking-specific flange, cover, relief, and connection features.
- Add template classification.

Acceptance criteria:

- Trunking templates use the same CAD engine.
- No tray perforation is generated unless explicitly configured.
- Existing sheet-metal, DSF, and 3D functionality remains shared.

---

## 17. Validation Rules

Validation should run after every successful recalculation and before export.

### Geometry validation

Check:

- Closed outer boundary
- Open contours
- Zero-length entities
- Duplicate entities
- Self-intersections
- Invalid arcs
- Invalid polygons
- Disconnected regions
- Non-manifold conditions where relevant

### Constraint validation

Check:

- Missing entity references
- Conflicting constraints
- Cyclic dependencies
- Invalid dimensions
- Over-constrained geometry
- Under-constrained critical features
- Suppressed or stale references

### Sheet-metal validation

Check:

- Invalid thickness
- Invalid bend radius
- Impossible bend geometry
- Invalid relief
- Bend collisions
- Insufficient edge distance
- Hole too close to bend
- Hole too close to edge
- Negative or zero developed regions

### Product validation

Check:

- Port dimensions within limits
- Port orientation
- Port compatibility
- Junction connectivity
- Reducer alignment
- Miter validity
- Coupler-feature placement
- Pattern boundaries
- Minimum material margins

Use useful messages such as:

```text
Port 3 width is too large for the available junction region.
```

rather than:

```text
Geometry failed.
```

---

## 18. Undo, Redo, and Transaction Safety

Parameter changes should be transactional.

Recommended behavior:

1. Capture the current valid state.
2. Apply the requested parameter change.
3. Recalculate dependencies.
4. Validate the result.
5. Commit if valid.
6. Roll back or mark invalid if unsuccessful.

A slider must not leave the document partially updated.

Undo/redo must cover:

- Parameter changes
- Constraint changes
- Port assignments
- Pattern changes
- Template authoring
- Geometry edits
- Feature additions/removals

---

## 19. Testing Strategy

### 19.1 Unit tests

Test:

- Geometry operations
- Constraint records
- Constraint solving
- Parameter expressions
- Dependency ordering
- Cycle detection
- Port calculations
- Pattern calculations
- Reducer alignment
- Tee topology
- Cross topology
- Validation rules
- DSF migration

### 19.2 Golden/template tests

Maintain representative templates for:

- Simple 90-degree bend
- 45-degree bend
- Reducer
- Equal tee
- Unequal tee
- Equal cross
- Unequal cross
- Trunking accessory

For each template, store:

- Input parameters
- Expected key dimensions
- Expected feature count
- Expected hole count
- Expected bend count
- Expected validation status
- Expected 3D bounding box
- Expected export behavior

### 19.3 Parameter-sweep tests

For each supported template, test:

- Minimum valid dimensions
- Nominal dimensions
- Maximum valid dimensions
- Intermediate values
- Invalid values
- Width changes
- Height changes
- Length changes
- Radius changes
- Port changes

### 19.4 Regression tests

Every existing DXF and DSF workflow must continue to work:

- Open DXF
- Edit DXF
- Export DXF
- Open DSF
- Save DSF
- Generate 3D
- Add bend
- Add hole
- Undo/redo
- Existing template workflow

---

## 20. Performance Requirements

The application should not perform a complete document rebuild for every Flutter widget rebuild.

Use:

- Dirty flags
- Cached geometry
- Incremental recalculation
- Separate model and render state
- Batched parameter updates
- Throttled preview recalculation where appropriate
- Background computation where already supported
- Deterministic cache invalidation

For slider interaction:

- Preview updates may be throttled.
- The final value must be fully recalculated and validated.
- The UI must not display stale 3D geometry as current.

---

## 21. What the Agent Must Not Do

The coding agent must not:

1. Rewrite the entire CAD Studio without an audit.
2. Create a second independent CAD engine.
3. Treat arbitrary vertex stretching as the complete parametric system.
4. Treat a flat DXF edge as automatically equal to a 3D port dimension.
5. Duplicate existing sheet-metal bend-development calculations.
6. Distort standard hole or slot profiles when dimensions change.
7. Begin with unequal tee or unequal cross before proving the architecture on a simple template.
8. Hardcode thousands of product variations.
9. Create separate DXFs for every dimension combination.
10. Silently repair invalid geometry.
11. Silently discard old DSF fields.
12. Claim UI controls or workflows that are not implemented.
13. Add manufacturing-machine-specific logic to the general geometry engine.
14. Make every miter or relief rigid by default.
15. Make every region stretchable by default.
16. Use array indices as persistent entity references.
17. Allow arbitrary executable expressions.
18. Leave the model partially updated after a failed parameter change.

---

## 22. Definition of Done for Phase 1

Phase 1 is successful when the application can:

1. Open an existing DXF.
2. Preserve the original geometry.
3. Identify and classify important geometry.
4. Add reference/construction geometry.
5. Define simple geometric constraints.
6. Define driving and reference dimensions.
7. Define named parameters.
8. Define safe expressions.
9. Build a dependency graph.
10. Assign semantic ports.
11. Convert one existing DXF into an intelligent template.
12. Change template dimensions.
13. Recalculate dependent geometry.
14. Regenerate hole patterns without distorting hole profiles.
15. Recalculate bend lines and reliefs.
16. Use the existing sheet-metal engine for flat development.
17. Update the 3D model.
18. Validate the result.
19. Save the intelligent template in an extended DSF format.
20. Reopen the saved DSF without losing intelligence.
21. Support a 90-degree bend.
22. Support a reducer.
23. Support an equal tee.
24. Support an unequal tee.
25. Progress toward equal and unequal crosses.
26. Reuse the same engine for trunking accessories.

---

## 23. Brief Future Direction: Phase 2

Phase 2 should focus on native parametric generation of cable-management products rather than modifying an existing DXF.

### Phase 1

```text
Existing DXF
    ↓
Add intelligence
    ↓
Modify dimensions
    ↓
Generate valid variations
```

### Phase 2

```text
Product type
    ↓
Width / height / length
    ↓
Material / thickness / finish
    ↓
Perforation configuration
    ↓
Accessory configuration
    ↓
Generate geometry from rules
    ↓
Generate flat pattern
    ↓
Generate 3D
    ↓
Generate DSF / DDS / manufacturing outputs
```

Possible Phase 2 generators include:

- Straight cable tray
- Cable tray cover
- 90-degree tray bend
- 45-degree tray bend
- Tee
- Cross
- Riser
- Reducer
- Coupler
- End plate
- Trunking and trunking accessories

Phase 2 must reuse:

- Phase 1 constraints
- Parameter system
- Dependency graph
- Geometry kernel
- Sheet-metal engine
- 2D editor
- 3D renderer
- Validation system
- DSF format
- Technical-data/document system

Phase 2 must not become a separate CAD product inside the same application.

---

## 24. Final Instruction to the Coding Agent

The current port assignment, zone morphing, perforation regeneration, and 3D update functionality are valuable foundations. Preserve them where practical.

However, the final architecture must evolve toward:

```text
Parameters
    +
Geometric constraints
    +
Dimensional constraints
    +
Reference geometry
    +
Semantic features
    +
Dependency graph
    +
Pattern definitions
    +
Existing sheet-metal engine
    ↓
Intelligent parametric template
```

The first objective is not to support every accessory immediately.

The first objective is to prove that one existing DXF can be converted into a stable intelligent template, then changed through parameters while preserving intended relationships between:

- Edges
- Centerlines
- Ports
- Holes
- Hole patterns
- Bend lines
- Reliefs
- Miters
- Coupler features
- Flat-pattern faces
- 3D folded faces

The recommended progression is:

```text
Audit
    ↓
Constraint model
    ↓
Constraint solver integration
    ↓
Construction geometry
    ↓
Parameters and expressions
    ↓
Dependency graph
    ↓
Semantic classification
    ↓
Port model
    ↓
One simple DXF template
    ↓
Hole pattern
    ↓
90-degree bend
    ↓
Reducer
    ↓
Equal tee
    ↓
Unequal tee
    ↓
Equal cross
    ↓
Unequal cross
    ↓
Trunking accessories
```

The final product objective is:

> Define the intelligence once, then generate thousands of valid product variations from dimensions and rules without maintaining thousands of separate AutoCAD DXF files.
