# TruFold Studio — Legacy Isolation & Clean CMS Architecture Walkthrough

## Purpose

This walkthrough establishes a clean architectural reset before implementing the new **Automatic 3D Port Discovery, Semantic Port Assignment, and Constraint-Driven Scaling** system.

The previous CMS/port-assignment implementation was unsuccessful and introduced changes to the DSF format, manual port-edge assignment, CMS wizard state, and scaling bindings.

The new implementation must **not extend or depend on those legacy mechanisms** unless the audit proves that a specific utility is genuinely reusable.

The guiding principle is:

> **Treat the previous CMS implementation as a prototype. Preserve the proven CAD foundation, isolate the failed implementation, and build the new CMS intelligence on top of the existing stable sheet-metal engine.**

---

# 1. Non-Negotiable Architectural Principles

### 1.1 Do not rebuild the existing CAD engine

The following existing systems are valuable and must be preserved unless the audit discovers a concrete defect:

- DXF parser and entity models
- `CadLine2D`
- `CadArc2D`
- `outerContour`
- `KinematicFoldEngine`
- `PlanarFaceDecomposer`
- `CncPunchPrimitive`
- `CncPunchRole`
- Existing 3D viewport/camera controls
- Existing metallic rendering
- Existing 2D drafting canvas
- Existing zoom/pan behavior
- Existing magnetic snapping
- Existing proven DXF/DSF workflow

The new CMS system is an **intelligence layer around the existing CAD engine**, not a replacement CAD engine.

---

# 2. Legacy Implementation Audit

Before writing new CMS implementation code, perform a complete audit.

Create:

```text
docs/CMS_LEGACY_IMPLEMENTATION_AUDIT.md
```

The audit must identify every component introduced during the previous unsuccessful implementation.

## 2.1 Locate Legacy Code

Search the entire project for:

- `PortInferenceEngine`
- `manualPortEdges`
- `inferredSide`
- `edgeIndex`
- `CmsGuidedHudOverlay`
- `CmsAuthoringMixin`
- old CMS wizard states
- old port selection state
- old parameter-drive scaling bindings
- old CMS serialization fields
- old DSF metadata
- old port assignment models
- old tests
- old UI routes
- old ViewModel dependencies

Do not assume that a class is obsolete simply because its name contains CMS. Inspect its actual responsibility.

---

# 3. Legacy Classification

Every discovered component must be placed into exactly one of these groups.

## KEEP — Core CAD & Sheet-Metal Foundation

```text
Existing DXF parser & entity models
├── CadLine2D
├── CadArc2D
└── outerContour

Existing KinematicFoldEngine
└── 3D forward-kinematics folding from bend lines

Existing PlanarFaceDecomposer
└── Flat blank → planar faces

Existing CNC punch primitives
├── CncPunchPrimitive
└── CncPunchRole

Existing 3D viewport
├── camera controls
├── metallic rendering
└── model display

Existing 2D drafting canvas
├── zoom
├── pan
└── magnetic snap
```

These systems should remain stable.

---

# 4. REPLACE — Previous CMS Implementation

The following previous concepts are to be retired from active use.

## 4.1 Old Port Inference

Retire:

```text
Old PortInferenceEngine
```

Especially any implementation based primarily on:

- manually selected 2D opening edges
- array-indexed edge references
- inferred side numbers
- fragile edge ordering
- manually maintained opening-edge assignments

Replace with:

```text
Cms3DOpeningDetector
        ↓
CmsOpeningPlaneAnalyzer
        ↓
CmsPortMatcher
```

The new system discovers physical openings from the folded 3D geometry.

---

## 4.2 Old Port Selection HUD

Retire:

```text
Old port-edge picking HUD
Old manual selection state
Old manual opening-edge assignment
```

The normal workflow should no longer require the user to manually tell TruFold:

> "This exact edge is Port 1."

Instead, TruFold should discover physical openings automatically.

Manual intervention is reserved for genuine ambiguity.

---

## 4.3 Old CMS Wizard

Retire:

```text
CmsGuidedHudOverlay
CmsAuthoringMixin
Previous 7-step wizard
```

Replace with:

```text
CmsGuidedUxController
```

The new controller should operate as an autonomous, observable state machine.

It should:

- perform stages automatically
- expose progress
- animate successful discoveries
- update 2D and 3D simultaneously
- pause briefly for comprehension
- automatically continue when confidence is high
- ask the user only when ambiguity exists

---

## 4.4 Old Scaling Bindings

Retire previous manual parameter-drive bindings where they were tied directly to:

- specific edge indexes
- manually selected ports
- fragile geometry references
- CMS wizard state

Replace with:

```text
Topological Constraint Graph
        ↓
Physical Port Anchors
        ↓
Feature Dependencies
        ↓
Parametric Scaling
```

The new system should be based on physical/topological relationships rather than UI selections.

---

# 5. DSF Cleanup

## 5.1 DSF Responsibility

The DSF file must remain a clean representation of:

> **Sheet-metal geometry and persistent sheet-metal design data.**

It should not become a storage container for the CMS authoring wizard.

DSF may contain:

- Flat contour geometry
- DXF entities
- Bend lines
- Bend parameters
- Flanges
- Punches
- Punch roles
- Material information
- Other persistent sheet-metal information

Example:

```text
DSF
├── geometry
├── bends
├── flanges
├── punches
├── material
└── persistent drawing metadata
```

---

# 6. DSF Data to Remove/Deprecate

The following legacy concepts must not be required by the new architecture:

```text
manualPortEdges
inferredSide
edgeIndex
temporary CMS wizard state
temporary candidate selection state
animation state
progress state
UI state
fragile array-indexed port references
```

Specifically investigate:

```text
DxfFittingMetadata.manualPortEdges
```

and:

```text
inferredSide
edgeIndex
```

If these fields exist only because of the failed CMS implementation, remove them from the active DSF schema.

---

# 7. Important DSF Rule

## Do NOT redesign DSF around automatic port discovery.

Automatic port discovery is an **on-demand analysis operation**.

Conceptually:

```text
DSF
 ↓
Existing fold engine
 ↓
Folded 3D representation
 ↓
Automatic opening discovery
 ↓
Port matching
```

The DSF does not need to permanently store every temporary discovery result.

This prevents the drawing format from becoming coupled to a particular discovery algorithm.

---

# 8. DSF Compatibility Strategy

Do not immediately delete old DSF support.

First determine:

### A. Original DSF files

If they use the stable original structure:

> Continue supporting them.

### B. Experimental DSF files

If they contain fields introduced only for the failed CMS implementation:

> Treat them as legacy.

Determine whether they can be safely migrated.

### C. New DSF

The new implementation must have an explicit versioned format.

Do not invent a new schema until the current DSF implementation has been audited.

Recommended principle:

```text
DSF Version
    ↓
Deserializer
    ↓
Canonical internal DSF model
```

Legacy files may be migrated at load time if practical.

---

# 9. Legacy Code Policy

Do not immediately delete every legacy class.

Use a staged process:

```text
LEGACY
   ↓
AUDIT
   ↓
ISOLATE
   ↓
STOP NEW DEPENDENCIES
   ↓
NEW IMPLEMENTATION
   ↓
TEST
   ↓
REMOVE LEGACY
```

The new CMS code must never silently depend on legacy CMS code.

If a legacy utility is reused, document exactly why.

---

# 10. New CMS Domain Structure

Create a clean modular domain.

Recommended structure:

```text
lib/
└── sheet_metal_studio/
    ├── engine/
    │   └── cms/
    │       ├── cms_3d_opening_detector.dart
    │       ├── cms_opening_plane_analyzer.dart
    │       ├── cms_port_matcher.dart
    │       ├── cms_coupler_classifier.dart
    │       └── cms_port_reconciler.dart
    │
    ├── models/
    │   └── cms/
    │       ├── cms_physical_port.dart
    │       ├── cms_product_contract.dart
    │       └── cms_ux_state.dart
    │
    └── views/
        └── widgets/
            └── guided_cms/
                ├── cms_guided_stage_card.dart
                ├── cms_live_learned_card.dart
                ├── cms_ambiguity_resolver_dialog.dart
                ├── cms_2d_overlay_painter.dart
                └── cms_3d_opening_callout.dart
```

### File-size rule

Do not continue growing:

```text
unfolded_canvas_widget.dart
sheet_metal_studio_viewmodel.dart
```

New CMS capabilities must not be added to these monolithic files.

Target:

> **Each new dedicated source file should normally remain below ~350 lines.**

If a file grows beyond that, reassess its responsibilities.

---

# 11. Responsibility of Each New Engine

## `cms_3d_opening_detector.dart`

Responsible only for discovering candidate physical openings.

It should identify:

- boundary loops
- closed/open status
- candidate opening geometry
- associated faces
- topology relationships

It should NOT decide:

> "This is Port 1."

---

## `cms_opening_plane_analyzer.dart`

Responsible for analyzing a detected opening.

Calculate as appropriate:

- best-fit plane
- local coordinate system
- normal
- centroid
- width
- height
- perimeter
- orientation
- projected 2D representation

It should return geometry measurements, not product semantics.

---

## `cms_port_matcher.dart`

Responsible for matching detected physical openings to the selected product contract.

Example:

```text
Detected Opening A
100 × 100
        ↓
Expected Port
100 × 100
        ↓
PORT 1
```

The matcher should consider:

- dimensions
- topology
- orientation
- position
- expected number of ports
- product type
- variation

---

## `cms_coupler_classifier.dart`

Responsible for identifying coupler mounting features.

It must distinguish:

```text
Coupler slots
```

from:

```text
Product perforations
```

Do not treat all holes as equivalent.

If the expected geometry is eight coupler slots, the system should identify them as a semantic feature group.

---

## `cms_port_reconciler.dart`

Responsible for maintaining stable physical port identity as geometry changes.

Example:

```text
Before scaling:
Port A = 100 × 100

After scaling:
Port A = 150 × 100
```

It must remain Port A.

Do not identify ports solely by array position.

---

# 12. CMS Models

## `cms_physical_port.dart`

A physical semantic port may contain:

- stable ID
- width
- height
- centroid
- normal
- boundary loop
- associated face
- local coordinate system
- confidence
- topology references

Do not store transient UI state here.

---

## `cms_product_contract.dart`

Defines what the selected product is expected to contain.

Examples:

```text
45° Bend
    Expected ports: 2
    Expected structural bends: 3
    Expected flanges: 2
```

```text
Equal Tee
    Expected ports: 3
```

```text
Equal Cross
    Expected ports: 4
```

```text
Unequal Tee
    Expected ports: 3
    Widths may differ
```

The contract describes **manufacturing/product expectations**, not temporary UI state.

---

## `cms_ux_state.dart`

Contains only the guided UX state machine.

Examples:

```text
idle
productSelected
analyzing
folding
detectingOpenings
matchingPorts
verifyingBends
classifyingCouplers
buildingConstraints
complete
ambiguityRequired
error
```

This state must never be serialized into DSF.

---

# 13. Clean Separation of Physical Port and Port Role

Do not mix:

> Physical Port

with:

> Inlet / Outlet / Branch

A physical port answers:

> "What opening exists here?"

A role answers:

> "How does this opening function within this product?"

Examples:

### Bend

```text
Physical Port A
Physical Port B
```

Roles may later be:

```text
Inlet
Outlet
```

### Unequal Tee

```text
Physical Port A
Physical Port B
Physical Port C
```

The system may infer the largest-width port as the likely main port, but this is a semantic assignment and should remain separate from physical discovery.

---

# 14. Automatic UX Philosophy

The guiding principle is:

> **Automatic, but deliberately observable.**

The user should see TruFold progressively understand the drawing.

Do not create unnecessary:

```text
Accept
Continue
Next
Confirm
```

buttons.

High-confidence stages should advance automatically.

Manual interaction should primarily occur when:

- confidence is low
- multiple candidates are equally plausible
- the geometry contradicts the product contract
- the user must provide missing manufacturing intent

---

# 15. Visual Language

The guided CMS experience should use a crisp engineering CAD aesthetic.

Preferred environment:

```text
Background:
White / very light gray

Typography:
Dark navy / charcoal

Active analysis:
Cyan / sky blue

Confirmed:
Emerald green

Ambiguity:
Amber
```

Avoid dark modal dialogs for this workflow.

The guided information should feel integrated into the CAD workspace.

---

# 16. Two-Synchronized-Views Principle

Whenever TruFold recognizes a feature:

> **Show it in both 2D and 3D.**

Example:

```text
2D:
Opening edge glows
        ↕
3D:
Corresponding physical opening glows
```

The user should understand the relationship:

> "This geometry in my flat DXF became this physical feature in the folded part."

This is a core UX principle.

---

# 17. Observable 45° Bend Workflow

Use the following as the reference UX for a 45° bend.

## Stage 1 — Product Intent

User opens:

```text
45_deg_bend_100x100.dxf
```

Prompt:

> **Is this a CMS Part Drawing?**

If yes:

```text
Category:
Trunking Accessories

Product:
Bend

Variation:
45° Bend
```

The dimension form is generated automatically.

Example:

```text
Port 1: 100 × 100
Port 2: 100 × 100
```

User starts:

> **Start Automatic Analysis →**

---

# 18. Stage 2 — 3D Fold and Opening Discovery

Display:

```text
ANALYZING 45° BEND

✓ Reading DXF geometry
✓ Reading DSF bend data
● Folding 3D model...
```

Then:

```text
✓ 3D Model Folded
● Detecting Physical Openings...
```

When an opening is discovered:

### 3D

- Camera gently focuses
- Opening rim glows
- Glow travels around the boundary
- Boundary pulses
- Dimension badge appears

Example:

```text
100.1 × 100.0 mm
```

### 2D

The corresponding geometry pulses at the same time.

Pause briefly for comprehension.

Then:

```text
✓ Physical Opening Detected
✓ Matched to Port 1
```

Repeat for Port 2.

---

# 19. Discovery vs Matching UX

Do not immediately call a newly detected opening:

```text
PORT 1
```

until the matcher has established the correspondence.

Use:

```text
Opening detected
        ↓
Measured
        ↓
Matched to Port 1
```

This makes the UX accurately reflect the internal architecture.

---

# 20. Stage 3 — Structural Bends

Display:

> **Verifying Structural Bends**

Example:

```text
B1
B2
B3
```

For each bend:

### 2D

- Bend line glows

### 3D

- Camera gently moves
- Corresponding bend seam pulses
- Small label appears

Example:

```text
✓ BEND 1
```

Pause briefly and continue automatically.

Then verify return flanges.

---

# 21. Stage 4 — Coupler Features

Display:

> **Identifying Fastener Hardware**

Coupler slots should pulse in both views.

Example:

```text
✓ 8 Coupler Slots Protected
```

These become rigid/invariant features for the scaling system where appropriate.

Do not assume every part universally has eight slots.

The product contract must determine the expected quantity.

---

# 22. Stage 5 — Live Understanding

Show a live summary:

```text
TRUFOLD UNDERSTOOD THIS PART

✓ 45° Bend Fitting
✓ 2 Physical Ports
✓ Port dimensions
✓ Structural bends
✓ Return flanges
✓ Coupler features
✓ Valid fold topology
```

Only show claims that the engine has actually verified.

Do not automatically claim:

```text
Watertight & Valid
```

unless the existing geometry engine explicitly verifies that condition.

Prefer specific validations such as:

```text
✓ Fold topology valid
✓ Opening boundaries valid
✓ Bend connectivity valid
✓ Coupler features associated
```

---

# 23. Parametric Scaling Demonstration

Once the template has been successfully understood, expose a simple user-facing parameter control.

Example:

```text
Width:
100 mm ─────●───── 150 mm
```

As the user moves it:

### 2D

- contour changes
- bend lines update
- dependent geometry updates

### 3D

- model regenerates
- physical dimensions update
- corresponding port dimensions update

### Rigid features

Coupler slots and other invariant features move according to their defined physical/topological relationships without being arbitrarily distorted.

---

# 24. Constraint Architecture

Do not build scaling around:

```text
edge index = X
```

or:

```text
selected edge = Y
```

Use physical/topological anchors.

Conceptually:

```text
Product Width
      ↓
Physical Port
      ↓
Port Boundary
      ↓
Bend Relationship
      ↓
Flange Relationship
      ↓
Feature Placement
```

The constraint graph should describe relationships, not UI history.

---

# 25. Port Identity During Scaling

Port identity must survive geometry changes.

Example:

```text
Before:
Port A = 100 × 100

Scale:
Width = 150

After:
Port A = 150 × 100
```

The system must not decide:

```text
Port B became Port A
```

simply because geometry arrays were reordered.

Stable identity should be based on topology/physical relationships.

---

# 26. Ambiguity Handling

Manual interaction should be exception-only.

Example:

```text
TruFold found 3 candidate openings.

Expected: 2

One candidate appears to be a relief opening.

Which should be treated as the product port?
```

Only then should the ambiguity resolver appear.

The dialog should be lightweight and visual.

Candidates should be highlighted in both 2D and 3D.

---

# 27. Existing Large Files

Do not add new CMS implementation into:

```text
unfolded_canvas_widget.dart
sheet_metal_studio_viewmodel.dart
```

unless there is an unavoidable integration point.

If integration code is required:

- keep it thin
- delegate to dedicated services/controllers
- avoid domain logic
- avoid serialization logic
- avoid geometry algorithms

---

# 28. Testing Requirements

Before declaring the new CMS architecture complete, test:

## Existing functionality

- Open existing DXF
- Save DXF
- Load DSF
- Save DSF
- Fold model
- 2D canvas
- 3D viewport
- Punch rendering
- Snap behavior

## Legacy compatibility

- Existing stable DSF
- Experimental/legacy DSF
- Migration where supported

## New CMS

- 45° bend
- Straight channel
- Equal tee
- Unequal tee
- Equal cross
- Unequal cross
- Reducer
- Bend/riser variants as supported by the product contract

## Scaling

- Width change
- Height change
- Port change
- Bend movement
- Flange movement
- Coupler feature preservation
- Perforation behavior

## Ambiguity

- Extra opening
- Missing opening
- Incorrect opening dimensions
- Multiple matching candidates

---

# 29. Legacy Removal Gate

Do not remove legacy code until:

```text
✓ New port discovery works
✓ New port matching works
✓ New UX works
✓ Scaling works
✓ Existing DXF workflow works
✓ Existing DSF workflow works
✓ Required legacy DSF files are migrated or intentionally unsupported
✓ Tests pass
✓ No active code depends on legacy CMS implementation
```

Then remove:

```text
Old PortInferenceEngine
Old port-edge HUD
Old CMS wizard
Old manual scaling bindings
Old transient DSF CMS fields
```

---

# 30. Implementation Order

The coding agent must follow this order.

## Sprint 0 — Legacy Audit & Isolation

1. Audit existing code.
2. Identify legacy CMS implementation.
3. Identify DSF changes.
4. Identify dependencies.
5. Document KEEP / REPLACE / DEPRECATE / REMOVE.
6. Stop new dependencies on legacy systems.
7. Confirm baseline CAD functionality.

## Sprint 1 — Clean CMS Domain

Implement:

```text
cms_physical_port.dart
cms_product_contract.dart
cms_ux_state.dart
```

No UI automation yet.

## Sprint 2 — 3D Opening Discovery

Implement:

```text
cms_3d_opening_detector.dart
cms_opening_plane_analyzer.dart
```

Prove that physical openings can be discovered from the folded model.

## Sprint 3 — Port Matching

Implement:

```text
cms_port_matcher.dart
cms_port_reconciler.dart
```

Prove physical port identity and matching.

## Sprint 4 — Guided UX

Implement:

```text
CmsGuidedUxController
cms_guided_stage_card.dart
cms_live_learned_card.dart
cms_2d_overlay_painter.dart
cms_3d_opening_callout.dart
```

Implement the slow, observable experience.

## Sprint 5 — Coupler Classification

Implement:

```text
cms_coupler_classifier.dart
```

Keep coupler features semantically separate from normal perforations.

## Sprint 6 — Constraint Graph

Implement topological/physical constraints anchored to discovered ports.

## Sprint 7 — Parametric Scaling

Demonstrate scaling on:

- 45° bend
- straight tray/channel
- unequal tee

## Sprint 8 — Legacy Removal

Only after validation:

- remove obsolete classes
- remove obsolete DSF fields
- remove old UI state
- remove old dependencies
- update documentation

---

# 31. Definition of Done

The new architecture is successful when:

### Architecture

- New CMS code is modular.
- No new CMS logic is added to monolithic widgets/ViewModels.
- Legacy CMS code is isolated.
- DSF remains clean.

### Discovery

- Ports are discovered from physical folded geometry.
- The system does not depend on manually selected edge indexes.
- Port identity survives scaling.

### UX

- User does not manually perform routine port assignment.
- The system progresses automatically when confidence is high.
- 2D and 3D provide synchronized visual feedback.
- Ambiguity produces a focused exception workflow.

### Scaling

- Parameters modify the template through physical/topological relationships.
- Coupler features remain correctly associated.
- Perforations remain semantically distinct.
- Unequal products are supported by the same architecture.

### Compatibility

- Existing core CAD behavior remains functional.
- Existing stable DSF files continue to work.
- Legacy experimental DSF files are either migrated or explicitly documented as obsolete.

---

# 32. Final Architectural Principle

The new TruFold architecture should follow this hierarchy:

```text
                 DXF / DSF
                     │
                     ▼
          Existing Sheet-Metal Engine
                     │
                     ▼
              Folded 3D Model
                     │
                     ▼
             Physical Discovery
                     │
              ┌──────┴──────┐
              ▼             ▼
           Openings      Features
              │
              ▼
          Port Matching
              │
              ▼
        Semantic Product Model
              │
              ▼
        Topological Constraints
              │
              ▼
        Parametric Scaling
              │
       ┌──────┴──────┐
       ▼             ▼
      2D             3D
       │             │
       └──────┬──────┘
              ▼
       Observable Guided UX
```

The core philosophy is:

> **The drawing stores the part. The CAD engine understands the geometry. The CMS layer understands the product. The constraint graph understands the relationships. The UX simply reveals that understanding to the user.**

Do not reverse this hierarchy by putting CMS wizard state or fragile port-selection information into the DSF drawing format.
