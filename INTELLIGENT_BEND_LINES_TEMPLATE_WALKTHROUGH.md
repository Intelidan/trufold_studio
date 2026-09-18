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

# 9. Phase 4 — Port Identification from the 3D Calculation

Because the application already folds the model, port detection should use the folded structure rather than relying only on 2D coordinates.

A port is usually an opening or terminal region in the folded structure.

The algorithm should consider:

```text
Candidate Port
    │
    ├── Open boundary?
    ├── On expected structural face?
    ├── Connected to expected bend topology?
    ├── Matches expected variation topology?
    ├── Has expected width/height relationship?
    ├── Has expected orientation?
    ├── Is it part of a branch/junction?
    └── Has user confirmation?
```

The product variation rules then convert a geometric candidate into semantic meaning.

For example:

```text
                     Equal Tee
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
         Port A        Port B       Branch C
          Main           Main         Branch
```

The system does not need to guess this solely from DXF coordinates if the folded topology already exposes the three structural openings.

---

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

Classify:

```text
Port A = Main
Port B = Main
Port C = Branch
```

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
