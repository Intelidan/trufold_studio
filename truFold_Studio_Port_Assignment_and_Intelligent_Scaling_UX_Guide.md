# truFold Studio — Professional Port Assignment UX & Intelligent Template Scaling

## Purpose

Define a professional, simple UI/UX and engineering workflow for converting existing flat DXF drawings into intelligent parametric templates.

The user should be able to assign a cable-tray/trunking fitting port with **one semantic action**:

> **Choose Port 1 → click the port opening edge → truFold automatically detects Width + Height A + Height B + direction → confirm.**

The user should not normally have to select three separate edges.

This guide focuses on Phase 1: existing DXF/template modification and intelligent scaling.

---

# 1. Executive Recommendation

The existing approach of manually selecting:

```text
W edge
H edge A
H edge B
```

is technically valid but is not the ideal professional UX.

Use:

```text
[ASSIGN PORT 1]
       ↓
Click one port opening / width edge
       ↓
Automatic geometry analysis
       ↓
W + H-A + H-B + direction detected
       ↓
Preview
       ↓
Accept
```

The manual W/H/H assignment should remain only as an **Advanced / Manual Recovery Mode**.

---

# 2. Important Architectural Distinction

The previous explanation that "edge identification is fundamental" is **partly correct internally, but too strong as a user-interface requirement**.

The CAD engine absolutely needs geometric/topological correspondence to know what moves when a parameter changes.

For example:

```text
W = 100 → 150
```

requires the engine to know:

- which region is the floor
- which walls belong to the port
- which bends belong to those walls
- which holes should move
- which holes must remain rigid
- which miters must move
- which datum should remain fixed

However:

> **The user does not need to manually identify all of those edges.**

The correct architecture is:

```text
USER ACTION
"Assign Port 1"
      ↓
PORT INFERENCE ENGINE
      ↓
INTERNAL REFERENCES
 ├─ width reference
 ├─ height reference A
 ├─ height reference B
 ├─ direction
 ├─ center/frame
 ├─ adjacent faces
 ├─ bend relationships
 ├─ stretch zones
 └─ rigid zones
```

So:

### Keep internal edge/topology identification.

### Hide unnecessary manual edge identification from the normal UX.

---

# 3. Closed Boundary vs. Semantic Port

A closed sheet boundary is still required for valid planar sheet geometry.

That is different from requiring the user to manually label every boundary edge.

```text
CLOSED GEOMETRY
┌─────────────────────┐
│                     │
│      SHEET FACE     │
│                     │
└─────────────────────┘
```

The B-Rep/geometry engine needs valid topology.

But a user should be able to say:

```text
"This opening is Port 1."
```

and let the software derive the semantic structure.

Therefore the design principle is:

> **Topology is an internal requirement; manual topology identification is not necessarily a user requirement.**

---

# 4. Professional Port Assignment UX

## Main command

Add a prominent contextual command:

```text
┌─────────────────────────────────────────────────────────┐
│ TEMPLATE                                                 │
│                                                         │
│ [ Assign Port ] [ Parameters ] [ Validate ] [ 3D ]     │
└─────────────────────────────────────────────────────────┘
```

When activated:

```text
┌─────────────────────────────────────────────────────────┐
│ ASSIGN PORT                                              │
│                                                         │
│ [ P1 ]   [ P2 ]   [ P3 ]   [ P4 ]                      │
│                                                         │
│ Select the opening edge of the port.                    │
└─────────────────────────────────────────────────────────┘
```

For an unequal tee:

```text
                 ┌──────────────┐
                 │    PORT 3    │
                 │    BRANCH    │
                 └──────┬───────┘
                        │
          ┌─────────────┴─────────────┐
          │                           │
          │                           │
       PORT 1                      PORT 2
       MAIN IN                     MAIN OUT
```

Workflow:

```text
Click P1
   ↓
Click P1 opening edge
   ↓
Auto-detect W/H-A/H-B
   ↓
Accept

Click P2
   ↓
Click P2 opening edge
   ↓
Auto-detect W/H-A/H-B
   ↓
Accept

Click P3
   ↓
Click branch opening edge
   ↓
Auto-detect W/H-A/H-B
   ↓
Accept
```

---

# 5. One Width + Two Heights

This should be a first-class concept in the data model.

A port is:

```text
Port
 ├── Width
 ├── Height A
 └── Height B
```

Do **not** model only:

```text
Port.width
Port.height
```

because future templates may contain different wall heights.

Example:

```text
Port 1

W   = 150
H-A = 50
H-B = 50
```

Unequal-wall possibility:

```text
Port 1

W   = 150
H-A = 50
H-B = 65
```

If H-A and H-B are equal, the UI can simply display:

```text
PORT 1
150 × 50 mm
```

If different:

```text
PORT 1
150 × 50 / 65 mm
```

The user does not need three floating dimension annotations.

---

# 6. What the User Clicks

The preferred click target is the **transverse opening/floor edge representing the port width**.

Conceptually:

```text
          SIDE WALL
              │
              │
      ┌───────┴───────┐
      │               │
      │     PORT      │
      │               │
      └───────────────┘
          ↑
          │
       CLICK HERE
       WIDTH EDGE
```

The selected edge becomes:

```text
Port.widthReference
```

The system then analyzes the surrounding geometry.

---

# 7. Automatic Height Detection

Suppose the selected edge is:

```text
A────────────────B
       WIDTH
```

The engine obtains:

```text
startVertex = A
endVertex   = B
```

and calculates:

```text
direction = normalize(B - A)
normal    = perpendicular(direction)
```

It then examines nearby and connected geometry on both sides.

```text
                  H-A
                   ↑
                   │
                   │
             A─────┼─────B
                  WIDTH
                   │
                   │
                   ↓
                  H-B
```

The engine does not simply search for the nearest lines.

It ranks candidates using topology and geometry.

---

# 8. Height Inference Rules

Candidate wall references should be evaluated using:

## 8.1 Topology

Prefer edges connected to the selected edge endpoints.

## 8.2 Orientation

A normal wall edge is approximately perpendicular to the width edge.

Use a tolerance rather than exact floating-point comparison.

Conceptually:

```text
Width direction ─────────→

Height direction
                    ↑
                    │
                    │
                  ≈ 90°
```

## 8.3 Bend relationship

A candidate connected through a recognized sheet-metal bend is stronger evidence than simple proximity.

## 8.4 Face relationship

Prefer candidates belonging to a wall face associated with the floor face.

## 8.5 Length similarity

If both walls are expected to be equal, similar lengths increase confidence.

But do not assume equality.

## 8.6 Opposite-side relationship

Once one wall is detected, search for its corresponding opposite wall.

---

# 9. Height Does Not Always Equal One Boundary Segment

This is important for real DXF templates.

A wall may be represented by:

```text
Outer edge
───────────────
       ↑
       │ H
       │
Bend ──┴────────────
```

But a corner relief may produce:

```text
─────────────┐
             │
             │
─────────────┘
```

Therefore the engine should identify the **wall region and its bend reference**, then calculate the design height.

Preferred hierarchy:

```text
1. Existing sheet-metal/bend metadata
        ↓
2. Bend-to-wall face relationship
        ↓
3. Topological adjacency
        ↓
4. Perpendicular boundary geometry
        ↓
5. Distance from bend reference to outer wall
        ↓
6. User-assisted selection
```

---

# 10. Port Inference Engine

Create or extend a dedicated service such as:

```dart
class PortInferenceEngine {
  PortInferenceResult inferFromWidthEdge({
    required CadDocument document,
    required String selectedEdgeId,
    required TemplateContext context,
  });
}
```

Result:

```dart
class PortInferenceResult {
  EdgeReference widthEdge;

  EdgeReference? heightEdgeA;
  EdgeReference? heightEdgeB;

  double? width;
  double? heightA;
  double? heightB;

  PortDirection? direction;

  double confidence;

  List<PortCandidate> alternatives;

  List<InferenceWarning> warnings;
}
```

Use stable geometry IDs.

---

# 11. Inference Pipeline

```text
USER CLICKS EDGE
       │
       ▼
Validate selected edge
       │
       ▼
Read endpoints
       │
       ▼
Calculate direction/normal
       │
       ▼
Inspect connected topology
       │
       ▼
Inspect adjacent faces
       │
       ▼
Inspect bend references
       │
       ▼
Find candidate wall A
       │
       ▼
Find candidate wall B
       │
       ▼
Calculate W / H-A / H-B
       │
       ▼
Determine port direction
       │
       ▼
Calculate confidence
       │
       ▼
Preview
       │
       ▼
User confirms
       │
       ▼
Create Port + dependencies
```

---

# 12. Preview Before Commit

Never silently commit an uncertain inference.

After the click:

```text
┌───────────────────────────────┐
│ PORT 1 DETECTED               │
│                               │
│ Width        100.0 mm         │
│ Height A      50.0 mm         │
│ Height B      50.0 mm         │
│ Direction         ←           │
│                               │
│ ✓ Side walls detected         │
│                               │
│ [ Cancel ]       [ Accept ]   │
└───────────────────────────────┘
```

Canvas:

```text
        ┌─────────────────┐
        │                 │
        │    PORT 1       │
        │                 │
        └─────────────────┘
          highlighted
```

If uncertain:

```text
⚠ One side wall needs review.

[Pick Wall A] [Pick Wall B]
```

The manual process is therefore a fallback.

---

# 13. Confidence Levels

Use confidence internally.

For example:

```text
HIGH      95–100%
GOOD      75–94%
REVIEW    50–74%
MANUAL    <50%
```

The normal UI should preferably say:

```text
✓ Port geometry detected
```

rather than exposing algorithmic numbers.

---

# 14. Port Assignment State Machine

Use explicit editor states:

```text
IDLE
  ↓
ASSIGN_PORT
  ↓
WAITING_FOR_EDGE
  ↓
EDGE_SELECTED
  ↓
INFERRING
  ↓
PREVIEW_PORT
  ├───────────────┐
  ↓               ↓
ACCEPT           CANCEL
  ↓               ↓
PORT_ASSIGNED   WAITING_FOR_EDGE
  ↓
NEXT_PORT
```

This avoids accidental geometry modification.

---

# 15. Unequal Tee UI

For an unequal tee:

```text
┌──────────────────────────────────────────────────┐
│ ASSIGN TEE PORTS                                 │
│                                                  │
│ [ P1 MAIN IN ] [ P2 MAIN OUT ] [ P3 BRANCH ]   │
└──────────────────────────────────────────────────┘
```

Canvas:

```text
                   ┌───────────────┐
                   │ P3            │
                   │ 150 × 50      │
                   └───────┬───────┘
                           │
             ┌─────────────┴─────────────┐
             │                           │
        P1   │                           │   P2
      100×50 │                           │ 200×75
             │                           │
             └───────────────────────────┘
```

The user performs only three clicks.

---

# 16. Port Should Be a Semantic UI Object

Do not make raw edges the primary concept in the interface.

Use:

```text
P1 100 × 50
P2 200 × 75
P3 150 × 50
```

The user can select a port and see its properties.

Advanced inspector:

```text
PORT 3
──────────────────
Role: Branch

Width       150.00
Height A     50.00
Height B     50.00

Direction    North

Reference
  Width Edge: E142
  Wall A:     E143
  Wall B:     E151
```

Raw references belong in the advanced/authoring layer.

---

# 17. Port Coordinate Frame

Each port should have a local coordinate system.

```text
             +Y
              ↑
              │
              │
              O────────→ +X
             origin
```

Recommended:

```text
PortFrame
 ├── origin
 ├── outwardDirection
 ├── transverseDirection
 └── normal
```

Then:

```text
Width change
    ↓
move/stretch along transverse direction

Height A change
    ↓
move wall A

Height B change
    ↓
move wall B
```

This becomes the basis for future assembly connections.

---

# 18. Do Not "Scale the DXF"

This is the most important engineering rule.

Do not implement:

```text
DXF global X/Y scale
```

Instead:

```text
Parameter change
      ↓
Constraint/dependency graph
      ↓
Geometry rules
      ↓
Stretch affected zones
      ↓
Move rigid features
      ↓
Rebuild affected faces
      ↓
Rebuild bends
      ↓
Update 3D
```

Example:

```text
W = 100 → 150
```

does NOT mean:

```text
all X/Y coordinates × 1.5
```

because that would distort:

- holes
- slots
- reliefs
- bend radii
- tooling
- miter geometry

---

# 19. Intelligent Template Structure

A reusable template should eventually contain:

```text
Template
│
├── Geometry
│
├── Parameters
│   ├── W1
│   ├── H1A
│   ├── H1B
│   ├── W2
│   ├── H2A
│   ├── H2B
│   └── ...
│
├── Ports
│
├── Constraints
│
├── Dependencies
│
├── Stretch Zones
│
├── Rigid Zones
│
├── Bend Features
│
├── Hole/Slot Features
│
└── Validation Rules
```

---

# 20. Constraint Foundation

The user's Fusion 360 / Onshape-style constraint idea is the correct foundation.

Start with a practical set:

### Geometric

```text
Coincident
Horizontal
Vertical
Parallel
Perpendicular
Concentric
Equal
Symmetric
Collinear
Tangent
Fixed
```

### Dimensional

```text
Distance
Horizontal distance
Vertical distance
Angle
Radius
Diameter
```

### Template-specific

```text
Edge-to-edge
Edge-to-hole-center
Hole-center-to-hole-center
Hole-to-bend
Bend-to-edge
Symmetric about centerline
```

Equality should be represented as a constraint.

Do not hard-code:

```text
H-A == H-B
```

unless the template explicitly defines that relationship.

---

# 21. Centerline-Based Scaling

For most fitting templates, create a reference datum/centerline.

```text
                 CENTERLINE
                     │
                     │
          ┌──────────┼──────────┐
          │          │          │
          │          │          │
          └──────────┼──────────┘
                     │
```

For a centered branch:

```text
              BRANCH
                │
                ▼
            ┌───────┐
            │       │
            └───┬───┘
                │
────────────────┼────────────────
             CENTERLINE
```

Width changes can then be constrained symmetrically around the centerline.

---

# 22. Rigid vs. Parametric Geometry

## Rigid features

Examples:

```text
Standard obround slot
Standard round hole
Corner relief
Tooling notch
Punch shape
```

Maintain:

```text
shape
size
orientation
internal dimensions
```

They may translate but should not stretch.

## Parametric features

Examples:

```text
Floor width
Floor length
Wall height
Taper
Branch width
Miter location
Transition geometry
```

These respond to parameters.

---

# 23. Stretch Zones

Use explicit zones.

```text
┌─────────────────────────────────────────┐
│ RIGID │     STRETCH BODY      │ RIGID  │
│       │                       │        │
│ HOLES │       FLOOR           │ HOLES  │
│       │                       │        │
└─────────────────────────────────────────┘
```

When length changes:

```text
Original:

[RIGID][------ BODY ------][RIGID]

New:

[RIGID][----------- BODY -----------][RIGID]
```

Rigid tooling remains undistorted.

---

# 24. Dependency Graph

Example for branch width:

```text
             P3 Width
                │
                ▼
         Branch Floor Zone
            /                   ▼          ▼
       Wall A       Wall B
           \          /
            ▼        ▼
              Miters
                 │
                 ▼
              Bend Data
                 │
                 ▼
                 3D
```

This is the correct way to think about scaling.

---

# 25. Unequal Tee Data Model

Use independent parameters:

```text
P1.width
P1.heightA
P1.heightB

P2.width
P2.heightA
P2.heightB

P3.width
P3.heightA
P3.heightB
```

Example:

```text
P1 = 100 × 50
P2 = 200 × 75
P3 = 150 × 50
```

Then changing P3:

```text
P3.width
150 → 200
```

should only affect geometry controlled by P3 and its dependencies.

---

# 26. Reducer Data Model

Reducer:

```text
P1 = 300 × 100
P2 = 150 × 50
```

The transition is generated from the two port frames.

For concentric reducer:

```text
       P1
   ┌─────────┐
    \       /
     \     /
      \   /
       \ /
       P2
```

The centerline/datum controls the symmetry.

For eccentric reducer:

```text
Reference side fixed
│
P1 ┌────────┐
   │           │         P2 └──────────┘
```

The fixed side should be represented by a constraint/datum, not a hard-coded coordinate rule.

---

# 27. Cross Data Model

Assign four ports:

```text
[ P1 ] [ P2 ] [ P3 ] [ P4 ]
```

Then:

```text
Click P1 opening
Click P2 opening
Click P3 opening
Click P4 opening
```

Each stores:

```text
W
H-A
H-B
direction
center
frame
```

This supports fully unequal crosses without creating hundreds of separate DXF templates.

---

# 28. Trunking Compatibility

Use the same generic port system for trunking.

Common:

```text
Port
Width
Height A
Height B
Direction
Frame
Constraints
Dependencies
```

Different product-specific features:

```text
Cable tray
 ├── perforations
 └── tray-specific tooling

Trunking
 ├── generally no perforation
 ├── cover relationships
 └── trunking-specific joints
```

The port system should therefore live in the generic template/CAD layer, not only in a cable-tray module.

---

# 29. DXF Normalization

Raw DXF should not be passed directly to PortInferenceEngine.

Recommended pipeline:

```text
DXF
 ↓
DXF Importer
 ↓
Geometry Normalizer
 ↓
Tolerance Cleanup
 ↓
Geometry Graph
 ↓
Face Detection
 ↓
Bend Detection
 ↓
Port Inference
```

The geometry graph should contain:

```text
Vertex
 ├── coordinates
 └── connected edges

Edge
 ├── start/end
 ├── curve type
 ├── length
 ├── direction
 ├── adjacent faces
 └── feature references

Face
 ├── boundary
 ├── area
 ├── normal
 └── feature/zone references
```

---

# 30. Port Inference Scoring

Candidate wall references can be ranked using:

```text
topology relationship
+
perpendicularity
+
bend relationship
+
face adjacency
+
length similarity
+
wall orientation
```

Create configurable inference weights rather than scattering unexplained constants through the code.

The algorithm should improve as more real Bonn DXF samples are tested.

---

# 31. Authoring Mode vs. Normal User Mode

## Template author

May see:

```text
Ports
Constraints
Datums
Stretch Zones
Rigid Zones
Dependencies
Feature References
Inference Results
```

## Normal template user

Should mainly see:

```text
Port sizes
Width
Height
Length
Material
Thickness
Perforation
```

Complexity belongs in the authoring layer.

---

# 32. Recommended Template Authoring UI

```text
┌─────────────────────────────────────────────────────────┐
│ TEMPLATE AUTHORING                                      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ 1. Define Ports                                         │
│    [P1] [P2] [P3]                                      │
│                                                         │
│ 2. Define Parameters                                    │
│    W1   H1A   H1B                                     │
│    W2   H2A   H2B                                     │
│    W3   H3A   H3B                                     │
│                                                         │
│ 3. Define Constraints                                   │
│    [Add Constraint]                                    │
│                                                         │
│ 4. Define Zones                                         │
│    [Rigid] [Stretch] [Pattern]                        │
│                                                         │
│ 5. Test                                                 │
│    [Minimum] [Nominal] [Maximum]                      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

# 33. Normal Template User UI

```text
┌─────────────────────────────────────────────────────────┐
│ UNEQUAL TEE                                             │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ MAIN IN       MAIN OUT       BRANCH                     │
│ W [100]       W [200]        W [150]                   │
│ H [50]        H [75]         H [50]                    │
│                                                         │
│ Length [300]                                             │
│                                                         │
│ Material [HDG]   Thickness [1.5]                       │
│                                                         │
│                 [ UPDATE MODEL ]                       │
└─────────────────────────────────────────────────────────┘
```

---

# 34. Scaling Example

Original:

```text
P1 = 100 × 50
P2 = 200 × 50
P3 = 150 × 50
```

New:

```text
P1 = 125 × 50
P2 = 250 × 75
P3 = 200 × 50
```

The engine performs:

```text
Parameter update
      ↓
Constraint solve
      ↓
Dependency evaluation
      ↓
Zone transformations
      ↓
Hole/slot anchoring
      ↓
Perforation re-nesting
      ↓
Face reconstruction
      ↓
Bend reconstruction
      ↓
3D update
      ↓
Validation
```

---

# 35. Perforation Rules

For cable trays:

```text
DO NOT STRETCH HOLES.
```

Instead:

```text
Face expands
     ↓
Calculate usable face
     ↓
Calculate available pattern area
     ↓
Recalculate rows/columns
     ↓
Place standard punch geometry
```

Example:

```text
Original:

○ ○ ○ ○ ○
○ ○ ○ ○ ○
○ ○ ○ ○ ○

Expanded:

○ ○ ○ ○ ○ ○ ○ ○
○ ○ ○ ○ ○ ○ ○ ○
○ ○ ○ ○ ○ ○ ○ ○
```

Slot dimensions remain unchanged.

For trunking, skip this stage when the product has no perforations.

---

# 36. What Happens When H-A Changes?

Example:

```text
H-A = 50 → 75
```

Only the associated wall should move/stretch.

```text
             H-A = 75
                 ↓
        ┌─────────────────┐
        │                 │
        │                 │
        │                 │
        └─────────────────┘
              FLOOR
        ┌─────────────────┐
        └─────────────────┘
             H-B = 50
```

If the template has:

```text
H-A = H-B
```

through a symmetry/equality constraint, both may update.

Otherwise they remain independent.

---

# 37. Port Assignment Should Create the Dependency Structure

When Port 1 is accepted, the system should create/reference:

```text
Port 1
│
├── widthReference
├── heightReferenceA
├── heightReferenceB
├── center
├── direction
├── localFrame
├── adjacentFaces
├── adjacentBends
├── constraints
├── dependencies
├── stretch zones
└── rigid zones
```

This is the bridge between simple UX and intelligent CAD.

---

# 38. Future Assembly Benefit

The port object should later become the common connection interface.

```text
ConnectionPort
 ├── width
 ├── height
 ├── center
 ├── direction
 ├── orientation
 └── systemType
```

Phase 2 can then connect:

```text
Straight Tray
      │
      ▼
90° Bend
      │
      ▼
Tee
      │
      ├── Branch
      ▼
Reducer
```

without creating a second unrelated connection system.

---

# 39. Phase 1 Implementation Sequence

The agent should implement this incrementally.

## Step 1 — Audit Existing Code

Inspect and reuse the current:

```text
DXF importer/exporter
DSF model
2D renderer
3D engine
Bend engine
Selection system
Constraint system
Undo/redo
Template system
Fitting Inspector
TopologicalZoneMorpher
```

**Do not rewrite working CAD systems unnecessarily.**

The current CAD Studio already contains substantial functionality.

---

## Step 2 — Verify Constraint Core

Verify:

```text
Coincident
Horizontal
Vertical
Parallel
Perpendicular
Concentric
Equal
Symmetric
Distance
Angle
Fixed
```

Add only what is missing.

---

## Step 3 — Verify Geometry Graph

Ensure normalized:

```text
Vertex
Edge
Face
Bend
Hole
Slot
Feature
```

with stable IDs.

---

## Step 4 — Implement Port Inference

Start with:

```text
Straight tray
```

Workflow:

```text
Assign Port
→ click width edge
→ infer W/H-A/H-B
→ preview
→ accept
```

Then add:

```text
90° bend
45° bend
tee
reducer
cross
```

one at a time.

---

## Step 5 — Polish Preview UX

Before complex scaling, make:

```text
Click
→ Detect
→ Highlight
→ Preview
→ Accept
```

reliable and intuitive.

---

## Step 6 — Convert Port Values to Parameters

After assignment:

```text
Port.width
Port.heightA
Port.heightB
```

become editable parameters.

---

## Step 7 — Implement Simple Stretch Zones

First test:

```text
Width
Length
Height
```

on simple straight geometry.

---

## Step 8 — Add Rigid Feature Anchoring

Add:

```text
holes
slots
coupler patterns
corner reliefs
```

Verify that they do not distort.

---

## Step 9 — Add Perforation Re-Nesting

Implement for cable trays only.

---

## Step 10 — Implement Equal Tee

Then:

```text
Equal Tee
→ Unequal Tee
→ Independent H-A/H-B
→ Miter dependencies
→ Tooling preservation
```

---

## Step 11 — Implement Reducer

Sequence:

```text
Equal transition
→ Concentric reducer
→ Unequal width
→ Unequal height
→ Eccentric reducer
```

---

## Step 12 — Implement Cross

Sequence:

```text
Equal cross
→ Two-width cross
→ Fully unequal cross
```

---

## Step 13 — Validation

Validate:

```text
✓ closed geometry
✓ no self intersection
✓ valid faces
✓ positive dimensions
✓ valid bend radius
✓ valid relief
✓ no hole collision
✓ valid edge distances
✓ no bend collision
✓ valid topology
```

---

## Step 14 — DSF Extension

The existing DSF implementation is already working.

Do not replace it unnecessarily.

Extend it to persist:

```text
template metadata
parameters
ports
constraints
dependencies
zones
inference references
```

Use schema versioning and preserve backward compatibility.

---

# 40. Minimum Acceptance Tests

## Test 1 — Straight Tray

```text
Import DXF
→ Assign Port
→ click opening edge
```

Expected:

```text
W detected
H-A detected
H-B detected
Direction detected
```

---

## Test 2 — Equal Tee

```text
P1 → click
P2 → click
P3 → click
```

Expected:

```text
3 ports assigned
```

---

## Test 3 — Unequal Tee

```text
P1 = 100 × 50
P2 = 200 × 75
P3 = 150 × 50
```

Expected:

```text
Each port independently stores:
W
H-A
H-B
```

---

## Test 4 — Change Branch Width

```text
P3 W:
150 → 200
```

Expected:

```text
Branch changes.
Main geometry does not globally scale.
Rigid tooling is not distorted.
3D updates.
```

---

## Test 5 — Change One Wall Height

```text
P3 H-A:
50 → 75
```

Expected:

```text
Only associated wall changes,
unless an explicit equality/symmetry constraint links H-A and H-B.
```

---

# 41. Final UX Target

The finished Phase 1 workflow should feel like:

```text
OPEN DXF
   │
   ▼
EXISTING FLAT DRAWING
   │
   ▼
[ ASSIGN PORT ]
   │
   ▼
CLICK OPENING EDGE
   │
   ▼
AUTO-DETECT
W + H-A + H-B + DIRECTION
   │
   ▼
PREVIEW
   │
   ▼
ACCEPT
   │
   ▼
ASSIGN NEXT PORT
   │
   ▼
PORTS COMPLETE
   │
   ▼
PARAMETER PANEL
   │
   ├── P1 W/H
   ├── P2 W/H
   ├── P3 W/H
   └── Length
   │
   ▼
UPDATE MODEL
   │
   ├──────────────┐
   ▼              ▼
  2D              3D
   │              │
   └──────┬───────┘
          ▼
       VALIDATE
          │
          ▼
       SAVE DSF
```

---

# 42. What Normal Users Should Never Need to Do

Normal template users should not have to:

- identify raw edge IDs
- select two separate height edges
- manually move every hole
- manually stretch the DXF
- redraw tees for every size
- redraw reducers for every size
- manually reposition every miter
- manually rebuild 3D
- understand B-Rep topology
- understand the dependency graph

Those are CAD-engine responsibilities.

---

# 43. What Template Authors May Need to Do

Advanced authoring may expose:

```text
Select reference
Add constraint
Define datum
Define stretch zone
Define rigid zone
Define pattern
Define dependency
Define port
Review inference
```

This is appropriate for building reusable templates.

---

# 44. Phase 2 Compatibility

Phase 1:

```text
Existing DXF
      ↓
Infer semantic structure
      ↓
Create intelligent template
      ↓
Modify dimensions
      ↓
Generate revised flat pattern
```

Phase 2:

```text
User parameters
      ↓
Select product type
      ↓
Generate semantic product
      ↓
Generate geometry
      ↓
Generate flat pattern
      ↓
Generate bends
      ↓
Generate 3D
```

Both should share:

```text
Geometry Engine
Constraint Engine
Parameter Engine
Port Model
Bend Engine
Feature System
Validation
2D Renderer
3D Renderer
DSF
DDS/TDS
```

Phase 2 should not require a separate CAD engine.

---

# 45. Core Product Principle

The final truFold Studio experience should follow:

> **Simple interaction, intelligent internal representation.**

The user says:

```text
"This is Port 3."
```

The CAD engine understands:

```text
Width reference
Height A
Height B
Center
Direction
Port frame
Adjacent faces
Bends
Stretch zones
Rigid zones
Hole dependencies
Miter dependencies
3D dependencies
```

That is the desired architecture.

---

# 46. Final Recommendation to the Coding Agent

The current implementation should be **extended and refined, not discarded**.

The existing `DxfFittingParameterDialog` manual workflow may remain as an advanced recovery tool:

```text
Advanced:
Select W edge
Select H-A
Select H-B
```

But the primary workflow should be:

```text
[Assign Port 1]
       ↓
Click opening edge
       ↓
Auto-infer W/H-A/H-B
       ↓
Preview
       ↓
Accept
```

The interface should expose **engineering intent**, not internal topology.

The target experience is:

```text
             USER
               │
               ▼
        "ASSIGN PORT"
               │
               ▼
          ONE CLICK
               │
               ▼
       PORT INFERENCE
               │
        ┌──────┼──────┐
        ▼      ▼      ▼
        W     H-A    H-B
        │      │      │
        └──────┼──────┘
               ▼
        PARAMETER GRAPH
               │
               ▼
        INTELLIGENT MORPH
               │
        ┌──────┴──────┐
        ▼             ▼
       2D             3D
        │             │
        └──────┬──────┘
               ▼
          MANUFACTURING
```

**This should be the Phase 1 target for professional port assignment and intelligent DXF-template scaling.**
