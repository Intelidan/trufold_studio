# TruFold Studio — Intelligent Parametric Template, Port Assignment & Scaling Walkthrough

## Purpose

This walkthrough defines how TruFold Studio should evolve from a normal DXF + DSF sheet-metal workflow into an intelligent parametric template workflow.

The key architectural decision is:

> **Do not rediscover sheet-metal bending information from the DXF when the DSF already stores it, and do not rebuild 3D geometry analysis when the application already has a working 3D simulation engine.**

The existing systems should become the foundation for template intelligence.

---

# 1. Core Concept

The current system already has three important layers:

```text
                 EXISTING SYSTEM

      ┌──────────────────────────────┐
      │          DXF Geometry        │
      │   Flat pattern / entities    │
      └──────────────┬───────────────┘
                     │
                     ▼
      ┌──────────────────────────────┐
      │           DSF JSON           │
      │      Bend / fold data        │
      └──────────────┬───────────────┘
                     │
                     ▼
      ┌──────────────────────────────┐
      │ Existing Sheet-Metal Engine  │
      │  Bend calculations / folding │
      └──────────────┬───────────────┘
                     │
                     ▼
      ┌──────────────────────────────┐
      │       Existing 3D Model      │
      │ Folded faces / topology /    │
      │ normals / adjacency / shape  │
      └──────────────────────────────┘
```

The new intelligent template system should sit above these existing components:

```text
 DXF + DSF
     │
     ▼
 Existing Bend / 3D Engine
     │
     ▼
 Structural Analysis
     │
     ├── Faces
     ├── Bends
     ├── Adjacency
     ├── Normals
     ├── Boundaries
     └── Folded 3D topology
     │
     ▼
 Product + Variation Rules
     │
     ▼
 Semantic Identification
     │
     ├── Ports
     ├── Branches
     ├── Junctions
     ├── Flanges
     ├── Coupler holes
     └── Perforation patterns
     │
     ▼
 Parametric Template Model
     │
     ▼
 Dependency / Constraint Graph
     │
     ▼
 Intelligent Scaling
     │
     ▼
 Regenerated DXF + DSF + 3D
```

---

# 2. Why DSF Changes the Design

A DXF mainly tells us **what geometry exists in the flat pattern**.

The DSF tells us **how that geometry behaves as sheet metal**.

The existing 3D simulator tells us **what the final folded structure looks like**.

Therefore the three sources have different responsibilities:

| Source | Responsibility |
|---|---|
| DXF | Exact flat geometry and entities |
| DSF | Bend lines, bend definitions, fold information |
| Existing 3D engine | Folded faces, topology, normals, adjacency, spatial relationships |
| Product type | General product family meaning |
| Variation | Expected topology and dimensional rules |
| User marking | Ambiguous semantic information that cannot safely be inferred |

The new implementation should preserve this separation.

---

# 3. Important Architectural Rule

## Use existing calculations first

Before writing any new algorithm, the agent should answer:

1. Does DSF already contain this information?
2. Can the existing bend engine calculate it?
3. Can the existing 3D simulation expose it?
4. Can the product variation rules define it?
5. Can it be derived from topology?
6. Does it actually need to be manually stored?

Only add new calculation logic when the existing system cannot provide the required information.

This prevents two different systems from calculating bends, dimensions, or 3D topology differently.

---

# 4. User Workflow

The target authoring workflow should be:

```text
Open Template Authoring
        │
        ▼
Load DXF
        │
        ▼
Load matching DSF
        │
        ▼
Select Product Type
        │
        ▼
Select Variation
        │
        ▼
Analyze
        │
        ▼
Run existing bend + 3D calculations
        │
        ▼
Build structural topology
        │
        ▼
Identify ports / branches / flanges / holes
        │
        ├── High confidence → automatic
        │
        └── Ambiguous → user review
        │
        ▼
Create semantic template
        │
        ▼
Assign driving parameters
        │
        ▼
Create dependency graph
        │
        ▼
Test scaling
        │
        ▼
Validate 2D + 3D
        │
        ▼
Save intelligent DSF/template
```

The objective is **automatic first, manual second**.

The user should not have to manually define information that the system can reliably derive.

---

# 5. Phase 0 — Audit the Existing Codebase

Before implementation, inspect the current TruFold codebase.

Create a technical audit covering at least:

```text
DXF importer/exporter
DSF loader/saver
DSF schema
Bend entity/model
Bend calculation engine
3D simulation engine
Face / edge / vertex representation
Face adjacency
Surface normals
Stable geometry IDs
Selection system
Hole detection
Perforation system
Coupler-hole handling
Constraint system
Parameter system
Template system
Undo / redo
Validation
TopologicalZoneMorpher
```

Especially inspect how the current 3D model is generated from DSF bending lines.

The agent should identify the exact existing functions/classes that can expose:

- bend-to-face relationships
- folded faces
- face normals
- face adjacency
- face boundaries
- edge classifications
- bend angles
- bend directions
- flat-to-folded mappings
- geometry IDs preserved from DXF/DSF

Do not create duplicate systems when these already exist.

---

# 6. Phase 1 — Load DXF and DSF as One Authoring Unit

The DXF and DSF must be treated as a linked pair.

```text
            Template Source
                  │
          ┌───────┴────────┐
          ▼                ▼
        DXF               DSF
   Flat geometry       Bend data
          │                │
          └───────┬────────┘
                  ▼
          Reconciliation
                  │
             Valid pair?
             /          \\
           Yes           No
           │              │
           ▼              ▼
       Continue       Clear error
```

Validation should check:

- referenced geometry exists
- bend IDs are valid
- no duplicate IDs
- no orphaned bend references
- expected geometry exists
- DSF and DXF version compatibility
- 3D fold can be generated successfully

Do not silently guess when the DXF and DSF cannot be reconciled.

---

# 7. Phase 2 — Use the Existing 3D Engine as the Structural Analyzer

This is the most important simplification.

The application already performs something close to:

```text
DXF
 +
DSF bending information
       │
       ▼
Bend calculations
       │
       ▼
Fold faces
       │
       ▼
3D model
```

Extend or expose this calculation so the template engine can access structural information.

For every folded face, the analysis model should ideally know:

```text
Face
├── faceId
├── sourceFlatGeometryIds
├── normal
├── area
├── boundaryEdges
├── adjacentFaces
├── parentBends
├── childBends
├── openBoundaries
├── orientation
└── semanticCandidate
```

For every bend:

```text
Bend
├── bendId
├── sourceDXFEntity
├── sourceDSFEntity
├── adjacentFaceA
├── adjacentFaceB
├── angle
├── direction
├── radius / bend parameters
├── bend line geometry
└── folded relationship
```

The exact field names should follow the existing codebase rather than introducing duplicate representations.

---

# 8. Phase 3 — Build the Folded Face / Bend Graph

The agent should convert the existing calculation result into a traversable topology graph.

Example:

```text
       Face A
          │
       Bend 1
          │
       Face B
       /     \\
   Bend 2    Bend 3
     │          │
   Face C     Face D
```

This graph is more useful for template intelligence than raw DXF coordinates.

For example, a wall face may be identified as:

```text
Base Face
  │
  ├── Bend
  │    └── Side Wall
  │
  ├── Bend
  │    └── Side Wall
  │
  └── Bend
       └── End Wall
```

This gives the system a structural description of the component.

---

# 9. Phase 4 — Physical Port Identification vs Semantic Role Assignment

Because the application already folds the model, port detection should use the folded structure rather than relying only on 2D coordinates.

The most important architectural distinction is:

> **First identify the physical ports. Then, separately, determine whether any port should be called an inlet, outlet, branch, main port, or another semantic role.**

A port is primarily a physical connection/opening region in the folded model. Its flow direction is not necessarily encoded by its geometry.

## 9.1 Physical Port Detection

```text
Existing DXF + DSF
        │
        ▼
Existing bend calculations
        │
        ▼
Existing folded 3D model
        │
        ▼
Find terminal/open connection regions
        │
        ├── Opening / boundary
        ├── Host face
        ├── Width / height
        ├── Orientation / normal
        ├── Bend path
        ├── Junction relationship
        └── Stable Port ID
```

The application should be able to conclude things such as:

```text
Port P01
Physical size = 300 × 150 mm
Host face = F12
Opening boundary = E44
Orientation = +X
```

without yet deciding whether P01 is an inlet or an outlet.

## 9.2 Semantic Role Assignment Is a Separate Layer

After physical ports are found, the product/variation rules can assign structural roles where appropriate:

```text
Physical Port
     │
     ▼
Role Assignment
     │
     ├── Main / Primary
     ├── Inlet
     ├── Outlet
     ├── Branch
     ├── Secondary Outlet
     └── Neutral / User Defined
```

Do not hardcode:

```text
Port 1 = Inlet
Port 2 = Outlet
```

unless that relationship is guaranteed by the product definition.

This is especially important for bends, risers, equal tees, and equal crosses, where the same physical part may be installed with a different flow direction.

## 9.3 Product-Specific Role Rules

### 2-Port Reducer

A simple reducer has two physical ports, usually with a large end and a small end.

The application can confidently determine:

```text
Port A = Large End
Port B = Small End
```

But whether the large end is the inlet or outlet should remain a semantic assignment unless the product definition explicitly fixes that convention.

Recommended flow:

```text
Detect Port A + Port B
        ↓
Compare widths
        ↓
Large End / Small End
        ↓
Assign Inlet / Outlet only if required
```

### Bend / Riser

A bend or riser normally has two physical ports. Either one may be the inlet depending on how the part is used.

```text
Port A = Physical End
Port B = Physical End

Inlet / Outlet = Not assumed
```

The template should remain reusable without forcing a flow direction.

### Equal Tee

An Equal Tee can have three equal-sized ports. The 3D topology can identify the **structural branch relationship**, but it cannot reliably determine which main port is the inlet.

```text
          Port C
          Branch
             │
             │
Port A ── Junction ── Port B
 Main              Main
```

The application can therefore infer:

```text
Port A = Main
Port B = Main
Port C = Branch
```

but should not silently infer:

```text
Port A = Inlet
Port B = Outlet
```

Either main port may be used as the inlet.

### Equal Cross

An Equal Cross can have four equal-sized ports, so there may be no geometric basis for selecting an inlet or outlet.

The app should identify:

```text
Port A
Port B
Port C
Port D
```

and preserve the physical/topological relationships. Flow roles remain neutral until the user or a downstream rule requires them.

### Unequal Tee

For an Unequal Tee, width can provide a useful default semantic hint.

The recommended rule is:

```text
Compare port widths
        ↓
Largest-width port
        ↓
Primary / Main port candidate
        ↓
Remaining ports
        ↓
Branch / Outlet candidates
```

The largest-width port can be suggested as the **primary/main inlet candidate** when the CMS workflow needs an inlet. The remaining ports can be suggested as branches or outlets according to the variation definition.

However, this must remain a **suggestion**, not an immutable assignment. The user should be able to reverse or change the role.

### Unequal Cross

Use the same default heuristic:

```text
Largest-width port
        ↓
Primary / Main / Inlet candidate
        ↓
Other ports
        ↓
Branch / Outlet candidates
```

The variation definition should determine the exact terminology and whether secondary ports are treated as branches, outlets, or a neutral secondary class.

## 9.4 Assignment Confidence

Every automatically suggested role should carry a confidence level and a reason.

```text
Port P03
Physical size: 200 × 100 mm

Suggested role: Branch
Reason: Equal Tee branch topology
Confidence: HIGH

[ Accept ] [ Change Role ]
```

Another example:

```text
Port P01
Physical size: 300 × 150 mm

Suggested role: Primary / Main
Reason: Largest width in Unequal Tee
Confidence: MEDIUM

[ Accept ] [ Change Role ]
```

The confidence applies to the **semantic interpretation**, not to the existence of the physical port itself.

## 9.5 Role Assignment Decision Engine

```text
Detect physical ports
        │
        ▼
Read product + variation rules
        │
        ▼
Determine structural relationship
        │
        ├── Branch can be inferred?
        ├── Main path can be inferred?
        ├── Large/small end can be inferred?
        └── Flow direction can be inferred?
                     │
                     ▼
             Generate suggestions
                     │
              ┌──────┴──────┐
             HIGH          AMBIGUOUS
              │                │
              ▼                ▼
       Preselect + explain   Keep neutral or
       + allow override      ask user when required
```

The key principle is:

> **Geometry establishes what a port physically is. Product rules establish what it structurally represents. Flow direction should only be assigned when it is actually known or explicitly provided.**

# 10. Port Detection Confidence

Each automatic identification should carry a confidence level.

Suggested model:

```text
HIGH
    topology + variation + dimensions agree

MEDIUM
    topology strongly suggests a port,
    but semantic role is ambiguous

LOW
    geometric candidate only
```

Example:

```text
Port Candidate #1
├── Face: F12
├── Open Boundary: E44
├── Width: 300
├── Height: 100
├── Orientation: Main Axis
├── Variation Match: YES
└── Confidence: HIGH
```

High-confidence candidates can be accepted automatically.

Medium- and low-confidence candidates should appear in a review screen.

---

# 11. Phase 5 — Branch Identification

Branches should be represented as topology, not merely as marked lines.

Example semantic structure:

```text
Product
│
├── MainPath
│   ├── Port A
│   └── Port B
│
├── Branch
│   └── Port C
│
└── Junction
```

For different product families:

```text
Reducer
  Main Port A ───── Main Port B

Equal Tee
        Branch C
           │
           │
Port A ─ Junction ─ Port B

Equal Cross
           Port C
              │
Port A ─── Junction ─── Port B
              │
           Port D
```

The variation definition should specify expected topology.

The geometry engine determines actual topology.

The template engine matches the two.

---

# 12. Phase 6 — Flange Identification

Bend lines are especially useful for flange identification.

A flange can be represented as:

```text
Parent Face
    │
    ▼
Bend
    │
    ▼
Flange Face
    │
    ▼
Outer Boundary
```

The semantic record should reference the actual existing geometry IDs where possible.

Example:

```text
Flange
├── flangeId
├── parentFaceId
├── bendId
├── flangeFaceId
├── width
├── direction
├── symmetry
└── parameterOwner
```

This is much safer than storing only an X/Y rectangle.

---

# 13. Phase 7 — Coupler Holes vs Regular Perforations

This distinction must be explicit.

Do not treat every hole as the same feature.

Recommended semantic classes:

```text
HOLE
├── COUPLER_HOLE
├── PERFORATION_HOLE
├── MANUFACTURING_HOLE
└── REFERENCE_HOLE
```

The exact classification names can match the existing codebase.

### Coupler holes

Coupler holes normally have a functional relationship to a connection area.

They should be stored as a group/pattern, not as unrelated circles.

```text
CouplerHoleGroup
├── groupId
├── hostFaceId
├── relatedPortId / connectionRegion
├── holeProfile
├── count
├── spacing
├── edge offsets
├── orientation
├── symmetry
└── regenerationRule
```

### Regular perforations

Regular perforations should be represented as a pattern:

```text
PerforationPattern
├── hostFaceId
├── profile
├── pitch
├── direction
├── margins
├── count
├── excludedZones
└── regenerationRule
```

When dimensions change, the pattern should be regenerated using its rules.

Do not blindly stretch each hole independently.

---

# 14. User Marking Workflow

The user should only have to mark information that cannot be confidently inferred.

Suggested authoring tools:

```text
[ Mark Bend ]
[ Mark Flange ]
[ Mark Port ]
[ Mark Branch ]
[ Mark Coupler Holes ]
[ Mark Reference ]
[ Confirm Candidate ]
[ Reject Candidate ]
[ Validate ]
```

However, the UI should not force the user to mark bends that are already reliably available from DSF.

The default workflow is:

```text
Automatic analysis
       │
       ▼
High confidence → accept
       │
       ▼
Ambiguous → user review
       │
       ▼
User correction becomes semantic metadata
```

The correction should be stored so that the template becomes more intelligent rather than losing the correction after the current session.

---

# 15. Product and Variation Rules

The product/variation system should provide the semantic expectations.

Do not hardcode coordinate-based rules for every individual DXF.

Example conceptual definition:

```json
{
  "productType": "CableTrayFitting",
  "variationName": "EqualTee",
  "topology": {
    "ports": 3,
    "mainPorts": 2,
    "branches": 1,
    "junctions": 1
  },
  "features": {
    "couplerHoles": true,
    "perforations": true,
    "flanges": true
  }
}
```

The actual schema should use the project's existing conventions.

The important principle is:

> **Variation rules describe what the product should be; geometry analysis describes what the loaded model actually contains.**

The template system reconciles the two.

---

# 16. Semantic Template Model

After analysis, create an intermediate semantic model.

This should sit between raw geometry and scaling logic.

Conceptually:

```text
Template
│
├── ProductType
├── Variation
├── Faces
├── Bends
├── Flanges
├── Ports
├── Branches
├── Junctions
├── CouplerHoleGroups
├── PerforationPatterns
├── Parameters
├── Constraints
├── Dependencies
└── References
```

This model becomes the source for intelligent scaling.

---

# 17. Parameter Ownership

Every important dimension should have a clear owner.

Example:

```text
W = overall width
│
├── Port Width
│    └── Host Face
│         └── Boundary
│              └── Perforation Region
│
└── Related Coupler Hole Reference
```

Another example:

```text
H = overall height
│
├── Port Height
│
├── Wall Height
│
└── Flange Bend Position
```

Avoid having several unrelated values that all appear to represent the same physical dimension.

There should be one driving parameter and derived/reference values downstream.

---

# 18. Driving vs Derived Dimensions

Every dimension should be classified.

### Driving

Values the user changes directly:

```text
Width
Height
Length
Branch Width
Port Width
Port Height
Flange Width
```

### Derived

Calculated from driving values:

```text
Bend-to-bend distance
Developed length
Opening size
Folded face position
```

### Reference

Values shown to the user but not used to drive geometry:

```text
3D opening measurement
Current hole count
Calculated developed length
```

This separation is essential for predictable scaling.

---

# 19. Dependency Graph

The dependency graph should show how one parameter changes the model.

Example:

```text
User changes BranchWidth
          │
          ▼
     Branch Port
          │
          ▼
     Branch Face
          │
          ▼
      Junction
          │
          ▼
 Related Bend References
          │
          ▼
 Coupler Hole References
          │
          ▼
 Perforation Region
          │
          ▼
     Flat Geometry
          │
          ▼
 Existing Sheet-Metal Engine
          │
          ▼
        3D Model
```

The agent should implement this as an explicit dependency mechanism rather than scattered event handlers.

---

# 20. Intelligent Scaling

## Critical principle

Intelligent scaling is **not** simply:

```text
DXF X × 1.2
DXF Y × 1.2
```

It is:

```text
Change parameter
       │
       ▼
Evaluate dependencies
       │
       ▼
Move/regenerate affected semantic features
       │
       ▼
Rebuild affected geometry
       │
       ▼
Run sheet-metal development
       │
       ▼
Regenerate 3D
```

Different geometry has different behavior.

---

# 21. Geometry Behavior Classes

Classify geometry/features as:

```text
RIGID
    Must not distort.

PARAMETRIC
    Position/size controlled by dimensions.

DERIVED
    Recalculated from other values.

PATTERN
    Regenerated using a rule.

REFERENCE
    Display/measurement only.
```

Example:

| Feature | Behavior |
|---|---|
| Coupler hole profile | Rigid |
| Coupler hole spacing | Parametric |
| Regular perforation grid | Pattern |
| Flange width | Parametric |
| Bend allowance | Derived |
| 3D opening dimension | Reference |
| Port boundary | Parametric/Derived |
| Product centerline | Reference/Constraint |

---

# 22. Scaling Algorithm

Recommended execution sequence:

```text
Start parameter change
        │
        ▼
Validate requested value
        │
        ▼
Find affected dependency nodes
        │
        ▼
Update driving dimensions
        │
        ▼
Update port / branch geometry
        │
        ▼
Update bend references
        │
        ▼
Update flange geometry
        │
        ▼
Update coupler-hole groups
        │
        ▼
Regenerate perforation patterns
        │
        ▼
Regenerate derived flat geometry
        │
        ▼
Run existing sheet-metal development
        │
        ▼
Rebuild 3D simulation
        │
        ▼
Run validation
        │
    ┌───┴────┐
  Valid    Invalid
    │          │
    ▼          ▼
 Commit     Rollback
```

Invalid intermediate states should never partially overwrite the valid template.

Use transactional updates where practical.

---

# 23. How Bend Lines Help Scaling

The existing bend lines should be treated as structural anchors.

For example:

```text
Flat Pattern

┌─────────────────────────────┐
│                             │
│          Face A             │
│-----------------------------│ ← Bend Line 1
│          Face B             │
│-----------------------------│ ← Bend Line 2
│          Face C             │
└─────────────────────────────┘
```

The scaling system should understand:

```text
Face A
  ↕ Bend 1
Face B
  ↕ Bend 2
Face C
```

Instead of stretching the entire rectangle, it can move structural regions while preserving the intended bend relationships.

This is where bend-line-aware scaling becomes much more reliable than generic DXF scaling.

---

# 24. Existing TopologicalZoneMorpher

`TopologicalZoneMorpher` can be used as part of the implementation, but it should not become a blind replacement for the semantic dependency system.

Recommended hierarchy:

```text
Parameter
   │
   ▼
Semantic Dependency
   │
   ▼
Feature Regeneration
   │
   ├── Parametric geometry
   ├── Pattern regeneration
   ├── Bend updates
   └── Constraint updates
        │
        ▼
TopologicalZoneMorpher
   │
   └── Used where controlled zone morphing is appropriate
```

Use zone morphing only when the region is explicitly classified as morphable.

Do not use global deformation as the primary architecture.

---

# 25. 2D and 3D Must Share One Source of Truth

The 2D DXF and 3D model should never be independently edited/calculated from different parameter sets.

Correct architecture:

```text
             Semantic Template
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
      2D Geometry         Bend/3D Engine
          │                   │
          ▼                   ▼
        DXF                  3D
```

After a parameter change:

```text
One parameter change
       │
       ▼
One dependency graph
       │
       ├──────────────┐
       ▼              ▼
    Updated 2D     Updated 3D
```

This keeps the flat and folded representations synchronized.

---

# 26. Intelligent DSF Schema Extension

Existing DSF bend data should remain valid.

Add intelligent metadata rather than replacing the established bend structure.

Conceptual structure:

```json
{
  "schemaVersion": 2,

  "bends": [],

  "source": {
    "dxfReference": "...",
    "geometryVersion": "..."
  },

  "product": {
    "productType": "...",
    "variationName": "..."
  },

  "semanticEntities": {
    "faces": [],
    "flanges": [],
    "ports": [],
    "branches": [],
    "junctions": []
  },

  "holeGroups": {
    "coupler": [],
    "perforation": [],
    "other": []
  },

  "parameters": [],
  "expressions": [],
  "constraints": [],
  "dependencies": [],
  "patterns": [],
  "zones": [],
  "validation": {}
}
```

Do not copy values unnecessarily when an existing DSF ID/reference can be used.

Stable IDs are especially important.

---

# 27. Backward Compatibility

Existing DSF files must continue to open.

Recommended flow:

```text
Load DSF
   │
   ▼
Detect schema version
   │
   ├── Old DSF → migration adapter
   │
   └── New DSF → direct load
          │
          ▼
Preserve existing bend information
          │
          ▼
Build semantic layer
          │
          ▼
Continue normal workflow
```

Do not break the existing bending functionality while adding semantic template features.

---

# 28. Template Authoring UI

The first screen should remain simple.

Suggested layout:

```text
Template Authoring

Product Type:   [ Cable Tray Fitting ▼ ]
Variation:      [ Equal Tee ▼ ]

DXF:            ✓ Loaded
DSF:            ✓ Loaded
3D Simulation:  ✓ Available

             [ ANALYZE ]
```

After analysis:

```text
Analysis Complete

Faces:              12
Bends:               8
Candidate Ports:     3
Branches:            1
Flanges:             4
Coupler Groups:      2
Perforation Groups:  4

High Confidence:    11
Needs Review:        2

       [ REVIEW ]   [ BUILD TEMPLATE ]
```

---

# 29. Review Screen

The review screen should overlay semantic information onto the existing 2D/3D model.

Example:

```text
3D View

      ┌──────── Port A
      │
  ┌───┴─────────────┐
  │     Main Face   │──── Port B
  │                 │
  └───────┬─────────┘
          │
          │ Branch
          ▼
       Port C
```

The user should be able to click a candidate and choose:

```text
[ Confirm as Port ]
[ Confirm as Branch ]
[ Mark as Reference ]
[ Reject ]
```

Corrections become part of the intelligent template metadata.

---

# 30. Equal Tee Example — End to End

Use Equal Tee as an early proof of concept because it demonstrates multiple ports, a branch, junction topology, bends, holes, and scaling dependencies.

## Step 1

Load:

```text
EqualTee.dxf
EqualTee.dsf
```

## Step 2

DSF provides bend lines and bend information.

## Step 3

Existing 3D engine folds the model.

## Step 4

Analyze folded topology.

Expected result conceptually:

```text
3 main structural faces
+
branch face
+
opening boundaries
+
connecting bends
```

## Step 5

Variation rules say:

```text
Expected Ports = 3
Main Ports = 2
Branches = 1
Junctions = 1
```

## Step 6

Match geometric candidates against the variation.

## Step 7

Classify **physical topology first**, then assign semantic roles.

```text
Physical Ports
Port A
Port B
Port C
```

For an Equal Tee, the application can usually infer:

```text
Port A = Main
Port B = Main
Port C = Branch
```

But it should not arbitrarily choose which main port is the inlet:

```text
Port A = Inlet   ← NOT assumed
Port B = Outlet  ← NOT assumed
```

Instead maintain:

```text
Port A → Main / Inlet-or-Outlet
Port B → Main / Inlet-or-Outlet
Port C → Branch
```

If a downstream process needs flow direction, present a simple role-assignment step at that point.

## Step 8

Locate coupler holes relative to the connection regions.

## Step 9

Identify regular perforation areas separately.

## Step 10

Create semantic template.

## Step 11

Assign parameters:

```text
MainWidth
MainHeight
MainLength
BranchWidth
BranchHeight
BranchLength
FlangeWidth
HolePitch
```

## Step 12

Test:

```text
BranchWidth: 300 → 400
```

The system should update the branch region rather than stretch unrelated geometry.

## Step 13

Existing bend/development calculations run again.

## Step 14

3D model regenerates.

## Step 15

Validate.

---

# 31. Suggested POC Order

Do not start with the most complicated product family.

Recommended sequence:

```text
1. Simple 90° Bend
        ↓
2. Straight / Simple Fitting
        ↓
3. Reducer
        ↓
4. Equal Tee
        ↓
5. Unequal Tee
        ↓
6. Equal Cross
        ↓
7. Unequal Cross
```

The first POC should prove the architecture rather than every possible product rule.

---

# 32. Validation Strategy

Validation should exist at three levels.

## Geometry validation

```text
No duplicate geometry
No broken references
No zero-length entities
No unintended intersections
Valid boundaries
Valid topology
```

## Sheet-metal validation

```text
Valid bends
Valid bend angles
Valid bend radii
Valid development
Successful fold/unfold
```

## Product validation

```text
Expected port count
Unique port IDs
Valid branch topology
Valid flange relationships
Valid coupler groups
Valid perforation patterns
No holes in forbidden regions
Required dimensions available
```

All three should pass before committing a new template version.

---

# 33. Transactional Scaling / Rollback

A parameter change should not immediately destroy the currently valid template.

Use:

```text
Current Valid State
        │
        ▼
Create Working State
        │
        ▼
Apply Parameter Change
        │
        ▼
Regenerate
        │
        ▼
Validate
     /      \\
   Pass     Fail
    │         │
    ▼         ▼
 Commit    Rollback
```

This is particularly important for complex branches and junctions.

---

# 34. Agent Implementation Rules

The agent implementing this feature should follow these rules:

### Rule 1
Reuse the DSF bend information.

### Rule 2
Reuse the existing 3D simulation calculations.

### Rule 3
Expose existing structural/topological information rather than recalculate it.

### Rule 4
Use product variation rules for semantic meaning.

### Rule 5
Automatic detection first; manual correction second.

### Rule 6
Keep coupler holes and regular perforations as different feature classes.

### Rule 7
Regenerate patterns rather than scaling individual pattern entities.

### Rule 8
Use semantic dependencies for scaling.

### Rule 9
Do not make global DXF stretching the primary scaling mechanism.

### Rule 10
Keep bend calculations in the existing sheet-metal engine.

### Rule 11
Use stable IDs everywhere possible.

### Rule 12
Keep 2D and 3D generated from the same semantic model.

### Rule 13
Use `TopologicalZoneMorpher` only where controlled zone morphing is appropriate.

### Rule 14
Never silently accept ambiguous topology.

### Rule 15
Validate before committing regenerated geometry.

---

# 35. Recommended Data Flow in Code

Conceptual service architecture:

```text
TemplateAuthoringController
          │
          ▼
TemplateAnalysisService
          │
          ├── DXF Loader
          ├── DSF Loader
          ├── Bend Engine Adapter
          └── 3D Simulation Adapter
          │
          ▼
StructuralAnalysisModel
          │
          ▼
ProductVariationMatcher
          │
          ▼
SemanticFeatureBuilder
          │
          ▼
ParametricTemplate
          │
          ▼
DependencyGraph
          │
          ▼
TemplateRegenerator
          │
          ├── Parametric Geometry
          ├── Hole Pattern Generator
          ├── Controlled Zone Morphing
          └── Existing Sheet-Metal Engine
          │
          ▼
ValidationService
          │
          ▼
DXF / DSF / 3D Output
```

The exact classes should be adapted to the existing architecture rather than created blindly.

---

# 36. Agent Investigation Checklist

Before implementing each feature, the agent should ask:

```text
[ ] Does an existing function already calculate this?
[ ] Is this information already present in DSF?
[ ] Can the existing 3D simulation expose it?
[ ] Is this a geometry property or semantic property?
[ ] Can the variation rules define it?
[ ] Can it be derived from topology?
[ ] Does it need user input?
[ ] Is it a driving parameter or derived value?
[ ] What features depend on it?
[ ] What happens when it changes?
[ ] How will it be validated?
[ ] Can the operation be rolled back safely?
```

This checklist should be used before adding new calculation logic.

---

# 37. Recommended First Implementation Sprint

The first sprint should prove the following chain end-to-end:

```text
DXF + DSF
   ↓
Existing 3D simulation
   ↓
Extract folded faces + bend relationships
   ↓
Identify candidate openings
   ↓
Match against one product variation
   ↓
Identify ports
   ↓
Identify one branch
   ↓
Identify one coupler-hole group
   ↓
Create semantic template
   ↓
Change one parameter
   ↓
Regenerate geometry
   ↓
Regenerate 3D
   ↓
Validate
```

A successful Equal Tee POC will establish whether the architecture works before implementing every product variation.

---

# 38. Final Architecture

The intended long-term architecture is:

```text
                    ┌───────────────┐
                    │      DXF      │
                    │ Flat Geometry │
                    └───────┬───────┘
                            │
                    ┌───────▼───────┐
                    │      DSF      │
                    │ Bend/Feature  │
                    │ Information   │
                    └───────┬───────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │ Existing Sheet-Metal    │
              │ Bend + Fold Calculation │
              └────────────┬────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │ Existing 3D Simulation  │
              │ Faces / Normals /       │
              │ Adjacency / Boundaries  │
              └────────────┬────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │ Structural Analysis     │
              └────────────┬────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
      Product Rules              User Corrections
              │                         │
              └────────────┬────────────┘
                           ▼
              ┌─────────────────────────┐
              │   Semantic Template     │
              │ Ports / Branches /      │
              │ Flanges / Holes / etc.  │
              └────────────┬────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │ Parameters + Constraints│
              │ + Dependency Graph      │
              └────────────┬────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │ Intelligent Regenerator │
              │                         │
              │ Parametric geometry     │
              │ Hole patterns           │
              │ Bend references         │
              │ Controlled morphing     │
              └────────────┬────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │ Existing Sheet-Metal    │
              │ Development / 3D Fold  │
              └────────────┬────────────┘
                           │
                           ▼
                    ┌───────────────┐
                    │ Validation    │
                    └───────┬───────┘
                            │
                            ▼
                    DXF + DSF + 3D
```

---

# 39. Definition of Done

The feature should be considered successful when an author can:

1. Open a DXF and matching DSF.
2. Select a product type and variation.
3. Run structural analysis using the existing bend/3D engine.
4. Automatically identify high-confidence faces, ports, branches, flanges, and hole groups.
5. Review and correct ambiguous candidates.
6. Save these relationships as an intelligent semantic template.
7. Change driving dimensions such as width, height, length, or branch dimensions.
8. Regenerate affected geometry using dependencies rather than global stretching.
9. Preserve rigid geometry and regenerate patterned geometry correctly.
10. Reuse the existing bend/development engine.
11. Regenerate the 3D model.
12. Validate both 2D and 3D results.
13. Save the enhanced DSF while preserving existing bend data.
14. Reopen the template and continue editing without losing semantic relationships.

---

# 40. Key Message for the Implementing Agent

The most important design decision is this:

> **The DSF is the source of truth for bending. The existing 3D simulator is the source of truth for folded structural topology. Product variation rules provide semantic expectations. The intelligent template layer connects these systems and adds parameter ownership, dependencies, constraints, and regeneration rules.**

Do not build a second sheet-metal engine.

Do not build a second 3D solver.

Do not use global DXF scaling as the main parametric mechanism.

Build the semantic layer and dependency system around the capabilities TruFold Studio already has.

---

# 37. New UX Concept — DXF Inspector as the Intelligent Entry Point

A major improvement is to begin the intelligent workflow immediately when the user opens a DXF.

The DXF Inspector should first identify the nature of the drawing and ask one simple question:

> **Is this a CMS Part Drawing?**

Use a prominent but lightweight control:

```text
┌─────────────────────────────────────────────────────────────┐
│ DXF Inspector                                               │
│                                                             │
│  Drawing detected                                           │
│                                                             │
│  Is this a CMS Part Drawing?                                │
│                                                             │
│          [ Yes — Start CMS Setup ]   [ No — Open Normally ] │
└─────────────────────────────────────────────────────────────┘
```

If **No** is selected, the normal DXF workflow continues without additional complexity.

If **Yes** is selected, the CMS authoring workflow begins.

This prevents the intelligent template system from making every DXF user go through product-specific forms.

---

# 38. CMS Part Information Form

After selecting CMS Part Drawing, display the minimum product identity information needed to guide the rest of the process.

Recommended fields:

```text
Category
[ Tray Accessories ▼ ]

Product Type
[ Tee ▼ ]

Variation
[ Unequal Tee ▼ ]
```

The form should be **progressive**:

```text
Category selected
      ↓
Product Type options filtered
      ↓
Product Type selected
      ↓
Variation options filtered
      ↓
Variation selected
      ↓
Variation-specific input form generated
```

Do not present every possible field at once.

The application should reveal only the information relevant to the selected product.

---

# 39. Dynamic Port / Branch Input Form

Once the variation is selected, generate the form dynamically from the product variation definition.

For example, an Unequal Tee could display:

```text
┌─────────────────────────────────────────────────────────────┐
│ UNEQUAL TEE                                                 │
│                                                             │
│  PORT 1 — MAIN INLET                                        │
│  Width    [ 300 ] mm                                        │
│  Height   [ 150 ] mm                                        │
│                                                             │
│  PORT 2 — MAIN OUTLET                                       │
│  Width    [ 300 ] mm                                        │
│  Height   [ 150 ] mm                                        │
│                                                             │
│  PORT 3 — BRANCH                                            │
│  Width    [ 200 ] mm                                        │
│  Height   [ 100 ] mm                                        │
│                                                             │
│                      [ Continue → ]                         │
└─────────────────────────────────────────────────────────────┘
```

The number of port/branch cards should come from the variation definition rather than being hardcoded.

Each section should have semantic labels such as:

- Main Inlet
- Main Outlet
- Branch
- Secondary Branch
- Port 1 / Port 2 / Port 3 when a more neutral naming convention is required

The application should distinguish **port identity** from **geometry location**. The user provides the product intent first; the system later associates that intent with actual faces/regions in the DXF.

---

# 40. Dynamic Form — Separate Physical Port Data from Role Data

The variation-specific form should collect the dimensions required to recognize the physical ports, while role information remains context-aware.

For example, an Equal Tee may initially show:

```text
EQUAL TEE

Port A
Width   [ 300 ] mm
Height  [ 150 ] mm

Port B
Width   [ 300 ] mm
Height  [ 150 ] mm

Port C
Width   [ 300 ] mm
Height  [ 150 ] mm

Detected structural role after analysis:
Port A → Main
Port B → Main
Port C → Branch

Flow direction:
[ Not specified ]
```

For an Unequal Tee, the app can make a stronger suggestion after dimensions are entered:

```text
Port A  300 × 150   ← Largest width
Port B  200 × 100
Port C  150 × 100

Suggested:
Port A → Primary / Main / Inlet candidate
Port B → Outlet / Branch candidate
Port C → Branch candidate

[ Accept Suggestions ] [ Adjust Roles ]
```

The application should never make the user repeatedly enter something that the product geometry and variation rules can determine safely.

# 40. Make the Form Feel Like a Configuration Experience

Avoid a conventional spreadsheet-style data-entry form.

Use compact cards, large numeric inputs, unit labels, contextual icons, and a live miniature representation of the selected variation.

Recommended structure:

```text
       UNEQUAL TEE
     ┌─────────────┐
     │    PORT 3   │
     │   200 × 100 │
     └──────┬──────┘
            │
   ┌────────┴────────┐
   │                 │
 PORT 1           PORT 2
 300×150           300×150
```

When the user edits a dimension, the miniature preview should update immediately.

This creates the feeling that the application is **understanding the part**, not merely collecting data.

---

# 41. Port Setup Should Become the Workflow Contract

The dimensions entered at this stage should become the expected semantic contract for the later analysis.

For example:

```text
CMS Product Definition
        │
        ├── Product = Tee
        ├── Variation = Unequal Tee
        ├── Port 1 = 300 × 150
        ├── Port 2 = 300 × 150
        └── Branch = 200 × 100
                 │
                 ▼
       Geometry Analysis
                 │
                 ▼
       Find candidate regions
                 │
                 ▼
        Compare geometry
                 │
                 ▼
       Match semantic ports
```

This makes the user's input useful throughout the entire automated process rather than treating it as metadata.

---

# 42. Guided Demarcation Mode

After the basic product information is entered, the application should switch into a dedicated **Guided Demarcation Mode**.

The system should not simply display a blank DXF and say "draw bend lines."

Instead, it should guide the user through one small action at a time.

Example:

```text
STEP 1 OF 6
Identify Port 1

The system expects:
Port 1 — 300 × 150 mm

Please add the BEND LINE for Port 1.

[ Start Guided Action ]
```

The drawing should highlight the region where the operation is expected.

Once the user completes the operation:

```text
✓ Bend line for Port 1 detected

Next:
Add the FLANGE LINE for Port 1.

[ Continue → ]
```

Then:

```text
✓ Port 1 complete

NEXT
Port 2 — 300 × 150 mm

1. Add bend line
2. Add flange line

[ Continue → ]
```

This is much easier to understand than presenting all possible drawing tools at the same time.

---

# 43. Two Possible Guidance Modes

The application should support two authoring strategies depending on the product variation.

### Port-by-Port Mode

```text
Port 1
  ↓
Bend line
  ↓
Flange line
  ↓
Complete Port 1
  ↓
Port 2
  ↓
Bend line
  ↓
Flange line
```

This is preferable when each port is a distinct logical unit and the user benefits from completing one unit before moving on.

### Operation-by-Operation Mode

```text
Add all bend lines
       ↓
Review bends
       ↓
Add all flange lines
       ↓
Review flanges
       ↓
Add coupler-hole groups
```

This may be faster for experienced users.

The variation definition should decide which mode is recommended, while allowing an advanced user to switch modes.

---

# 44. The App Should Always Explain Why It Is Asking for an Input

Every manual action should answer three questions:

```text
WHAT am I doing?
WHERE should I do it?
WHY does the application need it?
```

Example:

> **Add Bend Line — Port 2**
>
> This line will define the fold separating the Port 2 wall from its adjacent face. It will be used later to identify the port boundary and control intelligent scaling.

This dramatically improves user confidence because the user understands the purpose of the action.

---

# 45. Use Visual Focus Rather Than Instructions Alone

When the app asks for an action, visually isolate the relevant geometry.

Suggested behavior:

```text
Entire drawing       → dimmed
Target region        → highlighted
Expected edge/area   → glowing guide
Completed features   → confirmed state
Unrelated geometry   → subdued
```

The user should feel that the system is saying:

> "Work here next."

rather than:

> "Here is a DXF. Figure it out."

---

# 46. Show Progress as a Manufacturing Checklist

Use a clear persistent progress indicator.

Example:

```text
CMS TEMPLATE SETUP

✓ Product information
✓ Port dimensions
✓ Port 1 bend
✓ Port 1 flange
● Port 2 bend       ← current
○ Port 2 flange
○ Port 3 bend
○ Port 3 flange
○ Coupler holes
○ Perforation recognition
○ Validation
```

This gives the user a strong sense of progression and completion.

Avoid progress bars that only show percentages. The user should know **what has actually been completed**.

---

# 47. Let the System Detect Completion Automatically

The user should not need to press "Done" repeatedly when the geometry itself provides enough evidence.

For example:

```text
User draws bend line
        ↓
Application detects valid line
        ↓
Checks intersection / expected region
        ↓
Checks relationship to port candidate
        ↓
Marks action complete
        ↓
Moves to next step
```

Show:

> ✓ Bend line accepted

rather than requiring another confirmation unless ambiguity exists.

---

# 48. Confidence-Based Automation

Every automatically identified feature should have an internal confidence level.

Example:

```text
Port 1   ██████████ 98%   ✓ Auto identified
Port 2   ████████░░ 84%   ✓ Suggested
Port 3   █████░░░░░ 51%   ⚠ Review required
```

Do not expose unnecessarily technical mathematics to the user. Translate confidence into simple states:

- **Confirmed automatically**
- **Suggested — please verify**
- **Needs your input**

This allows the system to be highly automated without pretending that every inference is certain.

---

# 49. Candidate Suggestions Instead of Blank Decisions

When the system is unsure which geometry represents a port, do not immediately ask:

> "Select Port 3."

Instead present candidates.

```text
Which region is Port 3?

    [ Candidate A ]
    [ Candidate B ]
    [ Candidate C ]

The system selected Candidate B as the best match.

[ Accept B ]   [ Choose another ]
```

The application should do the analysis first and ask the user only to resolve ambiguity.

---

# 50. Smart Next-Step Engine

The authoring system should maintain a task state machine.

Example:

```text
STATE: PRODUCT_DEFINED
        ↓
STATE: PORT_DIMENSIONS_DEFINED
        ↓
STATE: IDENTIFY_PORT_1
        ↓
STATE: ADD_PORT_1_BEND
        ↓
STATE: ADD_PORT_1_FLANGE
        ↓
STATE: VALIDATE_PORT_1
        ↓
STATE: IDENTIFY_PORT_2
        ↓
...
```

The system should determine the next valid action from the state instead of relying entirely on the user to decide what to do next.

This is one of the most important changes for making the application feel automated.

---

# 51. Use a "Copilot" Style Interaction Without Taking Control Away

The application should act like an intelligent manufacturing assistant.

For example:

> **Port 1 is ready.**
>
> I found a face matching the requested 300 × 150 mm port.
>
> Next, add the bend line along the highlighted boundary.

After completion:

> **Port 1 bend accepted.**
>
> The flange appears to be 40 mm wide based on the drawing.
>
> Add or confirm the flange line.

The system can suggest values and geometry, but the user remains the final authority when ambiguity exists.

---

# 52. Smart Defaults and "Accept Suggestion"

When the system can derive a value reliably, pre-fill it.

Example:

```text
Flange Width
[ 40 mm ]

Suggested from geometry

[ Accept ]   [ Edit ]
```

Do not force the user to manually enter information that already exists in the DXF/DSF or can be derived from geometry.

---

# 53. Undo Should Feel Safe

Guided authoring encourages users to experiment. Therefore every guided step should be reversible.

Provide a clear:

```text
← Undo last step
```

The system should also maintain checkpoints:

```text
Checkpoint
✓ Product setup
✓ Ports defined
✓ Port 1 complete
● Port 2 in progress
```

If a later analysis fails, the user should be able to return to the last valid checkpoint rather than repairing a corrupted template manually.

---

# 54. Live 2D + 3D Feedback During Authoring

A particularly strong UX improvement is to keep the existing 3D simulation visible while the user is defining the template.

Example layout:

```text
┌───────────────────────┬──────────────────────────────┐
│                       │                              │
│       2D DXF          │         3D MODEL            │
│                       │                              │
│   Guided geometry     │    Live folded structure    │
│   marking             │                              │
│                       │                              │
└───────────────────────┴──────────────────────────────┘

                  NEXT ACTION
          Add bend line for Port 2
```

When the user creates a bend line, the corresponding 3D fold should update or preview immediately where technically practical.

This creates a powerful feedback loop:

```text
User action → 2D change → DSF/bend calculation → 3D result
```

The user can therefore visually understand why the line matters.

---

# 55. Highlight Relationships Across 2D and 3D

When the user selects Port 2 in the 2D drawing, highlight the corresponding face in 3D.

When the user selects a 3D face, highlight its associated 2D region.

When the user selects a bend in DSF, highlight:

```text
2D bend line
      ↕
DSF bend entity
      ↕
3D folded edge
```

This establishes a visible connection between all three representations.

---

# 56. Make Completed Geometry Visually Rewarding

The workflow should provide subtle positive feedback.

For example:

```text
✓ PORT 1 COMPLETE
```

with a brief visual transition from "working" to "confirmed".

Completed ports can receive a stable visual state, while the active port remains visually emphasized.

Avoid excessive animations. The goal is professional engineering software with a feeling of progress, not a game interface.

---

# 57. Prevent Mistakes Before They Happen

The app should actively constrain invalid actions during guided mode.

For example, when Port 2 is active:

- the relevant region remains active
- unrelated drawing tools can be disabled or de-emphasized
- invalid bend directions can be flagged
- lines outside the expected area can be rejected or treated as drafts
- duplicated bend lines can be detected

Show the problem next to the feature rather than forcing the user to discover it during final validation.

Example:

> ⚠ This bend line does not connect to the expected Port 2 boundary.
>
> Try extending it to the highlighted edge.

---

# 58. Separate Beginner and Expert Interaction Modes

The same engine can support two UX levels.

### Guided Mode

```text
One task at a time
Automatic validation
Suggested geometry
Strong visual guidance
```

### Expert Mode

```text
All tools available
Batch marking
Manual semantic assignment
Direct parameter editing
Faster navigation
```

The important rule is that both modes must create the same underlying semantic model.

UX mode should not create a second data model.

---

# 59. Add a "What the App Learned" Review Step

Before saving the template, show a human-readable summary.

Example:

```text
TRUFOLD UNDERSTANDING

Product       Unequal Tee
Ports         3

Port 1        300 × 150 mm
Port 2        300 × 150 mm
Branch        200 × 100 mm

Bends         8 identified
Flanges       6 identified
Coupler sets  3 identified
Perforation   6 regions identified

3D topology   Valid
Scaling       Ready

[ Review ]                         [ Save Template ]
```

This is an important trust-building step. The user can see what the application believes the drawing represents before committing it as a reusable template.

---

# 60. Add a Visual "Template Readiness" State

Instead of only showing technical validation messages, give the template a simple readiness state.

```text
TEMPLATE STATUS

● Geometry analyzed
● Product understood
● Ports assigned
● Bends linked
● Flanges linked
● Hole groups classified
● Scaling dependencies created
● 2D / 3D validation passed

             TEMPLATE READY ✓
```

If something is missing:

```text
TEMPLATE NOT READY

⚠ Port 3 flange has not been identified

[ Resolve this issue → ]
```

Clicking the issue should take the user directly to the relevant guided step.

---

# 61. Make Errors Actionable

Avoid technical messages such as:

> `PortTopologyValidationException: expectedFaceCount=3`

Instead display:

> **Port 3 could not be confirmed.**
>
> The selected region does not match the expected 200 × 100 mm branch.
>
> [ Show candidate regions ]

The technical diagnostic can remain available in an expandable "Details" section for engineers and developers.

---

# 62. Intelligent Re-Check Instead of Repeating the Entire Process

After the user changes one feature, do not restart analysis from zero unless necessary.

Example:

```text
User changes Port 3 flange
        ↓
Revalidate affected flange
        ↓
Recalculate dependent dimensions
        ↓
Update affected scaling rules
        ↓
Recalculate 3D if required
        ↓
Run targeted validation
```

The system should use dependency awareness to make authoring feel responsive.

---

# 63. "Teach the System" Through User Corrections

When the system proposes a candidate and the user corrects it, store the correction as semantic information for the current template.

Example:

```text
System:
Candidate B = Port 3

User:
Choose Candidate C

Stored:
Port 3 → Face/Region C
```

Do not silently convert such corrections into global assumptions about unrelated products. Template-specific corrections and reusable product rules should remain separate.

---

# 64. Variation Definitions Should Drive the UX

The product variation definition should describe not only geometry rules but also the recommended authoring workflow.

A variation configuration could conceptually contain:

```json
{
  "productType": "tee",
  "variation": "unequal",
  "ports": 3,
  "portDefinitions": [
    { "role": "main_inlet", "requiresWidth": true, "requiresHeight": true },
    { "role": "main_outlet", "requiresWidth": true, "requiresHeight": true },
    { "role": "branch", "requiresWidth": true, "requiresHeight": true }
  ],
  "authoringWorkflow": "PORT_BY_PORT",
  "requiredSteps": [
    "identify_port",
    "add_bend",
    "add_flange",
    "validate_port"
  ]
}
```

This allows the UI to generate itself from product intelligence rather than accumulating hardcoded screens for each product.

---

# 65. Recommended End-to-End User Experience

The ideal interaction becomes:

```text
USER OPENS DXF
       ↓
DXF INSPECTOR
       ↓
"Is this a CMS Part Drawing?"
       ↓
      YES
       ↓
CATEGORY
       ↓
PRODUCT TYPE
       ↓
VARIATION
       ↓
DYNAMIC PORT / BRANCH FORM
       ↓
USER ENTERS WIDTH + HEIGHT
       ↓
LIVE PRODUCT PREVIEW
       ↓
"I understand what this part should contain."
       ↓
ANALYZE DXF + DSF
       ↓
EXISTING 3D ANALYSIS
       ↓
AUTO-DETECT CANDIDATES
       ↓
GUIDED DEMARCATION
       ↓
PORT 1
  → Bend
  → Flange
  → Validate
       ↓
PORT 2
  → Bend
  → Flange
  → Validate
       ↓
BRANCH / PORT 3
       ↓
COUPLER HOLES
       ↓
PERFORATION REGIONS
       ↓
"WHAT THE APP LEARNED"
       ↓
SCALING TEST
       ↓
2D + 3D VALIDATION
       ↓
TEMPLATE READY ✓
```

The important UX principle is:

> **The user supplies product intent; the application supplies geometric intelligence; the user confirms only where human judgment is needed.**

---

# 66. Design Principle — Make the Application Feel Automated Without Hiding Control

The goal is not to remove the user from the process.

The goal is to remove unnecessary decisions.

The application should continuously follow this loop:

```text
UNDERSTAND
   ↓
SUGGEST
   ↓
GUIDE
   ↓
VERIFY
   ↓
AUTOMATE
   ↓
SHOW RESULT
```

At every stage, the user should know:

- what the application understood
- what it is asking the user to do
- what it will do next
- what information has been accepted
- what remains unresolved

That combination is what will make the workflow feel intelligent, modern, high-tech, and enjoyable without sacrificing engineering control.

---

# 67. Implementation Priority for the Agent

The agent should implement the UX in this order:

```text
1. DXF Inspector CMS detection
        ↓
2. Category / Product / Variation selector
        ↓
3. Dynamic port/branch dimension form
        ↓
4. Variation-driven workflow definition
        ↓
5. Guided task/state engine
        ↓
6. Existing DXF + DSF + 3D analysis integration
        ↓
7. Automatic candidate identification
        ↓
8. Guided bend/flange marking
        ↓
9. Coupler/perforation classification
        ↓
10. Live 2D/3D relationship highlighting
        ↓
11. Confidence + ambiguity handling
        ↓
12. "What the App Learned" review
        ↓
13. Dependency-driven scaling
        ↓
14. Final validation and template readiness
```

The agent should build the **workflow/state framework first** because the later automation features can plug into the same guided-action architecture.

