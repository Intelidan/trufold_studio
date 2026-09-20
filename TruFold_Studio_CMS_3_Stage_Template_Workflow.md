# TruFold Studio — CMS 3-Stage Template Workflow
## Manufacturing Definition → Port Mapping → Template Scaling

## 1. Architectural Decision

The CMS workflow should be divided into **three independently saveable stages**:

```text
STAGE 1
Manufacturing Definition
        ↓
STAGE 2
Automatic Port Mapping
        ↓
STAGE 3
Template / Parametric Scaling
```

This replaces the previous attempt to make the application automatically infer bend/flange structure from a new DXF.

There are only about 150 CMS product variations to author. Therefore, the user can manually define the manufacturing bend lines, flange lines and coupler holes once for each variation. The application should then automate the repetitive and complex work that follows.

### Governing principle

> **The user defines manufacturing intent once. TruFold Studio understands it, maps the ports and builds the scalable template.**

---

# 2. Do Not Build 150 Separate Algorithms

The application should **not** contain a separate hard-coded algorithm for every one of the approximately 150 CMS variations.

Avoid an architecture such as:

```text
UnequalTeeAlgorithm()
EqualTeeAlgorithm()
ReducerAlgorithm()
BendAlgorithm()
...
150 individual algorithms
```

Instead use:

```text
                 GENERIC ENGINE
                       │
          ┌────────────┴────────────┐
          │                         │
   Generic Port Engine       Generic Scaling Engine
          │                         │
          └────────────┬────────────┘
                       │
              CMS PRODUCT DEFINITION
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
        Bend          Tee        Reducer
        Config       Config        Config
```

Each CMS variation should primarily be represented by a **declarative product definition/configuration**, not a separate algorithm.

The product definition should describe:

- expected port count
- port roles
- port matching rules
- primary dimensions
- derived dimensions
- scaling dependencies
- protected features
- product-specific constraints

The generic engines interpret those rules.

---

# 3. Complete CMS Workflow

```text
Open DXF
   ↓
Is this a CMS Part Drawing?
   ├── No → Existing normal DXF workflow
   └── Yes
        ↓
   Select Product Type + Variation
        ↓
   ┌─────────────────────────────┐
   │ STAGE 1                     │
   │ Manufacturing Definition    │
   │                             │
   │ User defines:               │
   │ • Bend lines                │
   │ • Flange lines              │
   │ • Coupler / mounting holes │
   └──────────────┬──────────────┘
                  │
                SAVE
                  │
                  ▼
   ┌─────────────────────────────┐
   │ STAGE 2                     │
   │ Automatic Port Mapping      │
   │                             │
   │ • Fold 3D                   │
   │ • Find physical openings    │
   │ • Identify port candidates  │
   │ • Assign port roles         │
   └──────────────┬──────────────┘
                  │
                SAVE
                  │
                  ▼
   ┌─────────────────────────────┐
   │ STAGE 3                     │
   │ Template / Scaling          │
   │                             │
   │ • Parameters                │
   │ • Dependencies              │
   │ • Constraints               │
   │ • Protected features        │
   │ • Parametric scaling        │
   └──────────────┬──────────────┘
                  │
                SAVE
                  │
                  ▼
             COMPLETE CMS DSF
```

Each stage is a valid saved state.

---

# 4. Stage 1 — Manufacturing Definition

## Purpose

Stage 1 captures the manufacturing intent that the application should treat as authoritative.

The user defines:

```text
Bend Lines
Flange Lines
Coupler / Mounting Holes
```

The application must **not automatically regenerate or reinterpret these lines**.

## UX

Show:

```text
STEP 1

Define Manufacturing Structure

1. Mark bend lines
2. Mark flange / return lines
3. Mark coupler / mounting features

[ Save Manufacturing Definition ]
```

The user can save at this point even though port mapping has not been completed.

---

# 5. Stage 1 — Bend Authoring

The user manually creates or selects the bend lines in the 2D DXF view.

For each bend line:

1. Highlight the selected 2D line.
2. Preview the corresponding 3D fold where possible.
3. Briefly glow/pulse the affected area.
4. Allow undo.
5. Allow edit/delete before saving.

The user should not need to understand topology, graphs or scaling logic.

### Important

The user-authored bend lines become the **manufacturing source of truth**.

---

# 6. Stage 1 — Flange Authoring

After bends, the user marks flange / return lines.

Do not attempt to infer whether an edge is a flange automatically.

The user already knows the manufacturing construction.

The application simply records it.

Provide the same visual feedback as for bends:

- 2D highlight
- corresponding 3D preview
- short glow/pulse animation
- undo/edit support

---

# 7. Stage 1 — Coupler / Manufacturing Features

Allow the user to mark relevant manufacturing features.

At minimum distinguish:

```text
○ Coupler / Mounting Hole
○ Perforation
○ Other Feature
```

This distinction is required because CMS scaling must not treat all holes as generic geometry.

Coupler / mounting features should be stored as semantic features where applicable.

---

# 8. Stage 1 — Saving the DSF

The DSF must be valid and reopenable immediately after Stage 1.

It should contain at least:

```text
Existing DXF geometry
+
Bend lines
+
Flange lines
+
Manufacturing features
+
CMS product identity
+
CMS workflow state
```

At this point:

```text
Manufacturing Definition = COMPLETE
Port Mapping              = NOT COMPLETE
Template Scaling          = NOT COMPLETE
```

The file is intentionally usable in this intermediate state.

---

# 9. Reopening a Stage-1 DSF

When a DSF is reopened and manufacturing data exists but port mapping does not, the application should recognize the state.

Example:

```text
CMS PART

Manufacturing definition is complete.

✓ Bend structure
✓ Flange structure
✓ Manufacturing features

Port mapping has not been completed.

[ Continue Port Mapping ]
[ Edit Manufacturing Definition ]
```

Do not force the user to repeat Stage 1.

---

# 10. Stage 2 — Automatic Port Mapping

This stage consumes the exact manufacturing definition saved during Stage 1.

### Critical rule

Stage 2 must **never redo Stage 1**.

Do not do:

```text
User defines bends
      ↓
Stage 2 automatically detects bends again
      ↓
Port mapping
```

Instead:

```text
Saved bend lines
Saved flange lines
Saved features
        ↓
Fold using those exact definitions
        ↓
Port discovery
```

---

# 11. Stage 2 — Use the Existing Automatic Port Algorithm

Reuse the existing port-mapping logic where possible.

The inputs are:

```text
User-authored bend lines
+
User-authored flange lines
+
Folded 3D model
+
CMS product definition
```

The algorithm should perform:

```text
Generate folded 3D
        ↓
Discover physical openings
        ↓
Measure openings
        ↓
Create port candidates
        ↓
Match candidates to product expectations
        ↓
Assign port IDs
        ↓
Assign semantic roles
        ↓
Store geometry relationships
```

---

# 12. Stage 2 — Physical Opening Discovery

Once the folded 3D structure is valid, automatically identify physical openings.

Candidate information should include:

```text
Opening ID
Boundary
Width
Height
Orientation
Connected faces
3D position
3D normal
Source 2D geometry
```

The user should not need to manually draw each port.

---

# 13. Stage 2 — Port Candidates

Convert physical opening candidates into stable port candidates.

Example conceptual data:

```json
{
  "id": "P1",
  "role": "main",
  "width": 300,
  "height": 100,
  "sourceOpeningId": "OPEN_01"
}
```

Retain geometric evidence such as:

- opening boundary
- connected face
- orientation
- source geometry
- dimensions

This makes the mapping inspectable and easier to debug.

---

# 14. Stage 2 — Product-Aware Port Mapping

The generic port-discovery algorithm should be combined with a CMS Product Definition.

The product definition tells the engine what is expected.

Example:

```text
Unequal Tee

Expected Port Count: 3

Roles:
- Main
- Branch 1
- Branch 2

Matching rules:
- main opening belongs to primary body
- branch openings belong to secondary body / branch geometry
```

The algorithm discovers geometry first and then interprets it according to the product contract.

---

# 15. Port Examples

## Simple Reducer

```text
Expected Ports:
2

Roles:
Inlet
Outlet
```

## Bend

```text
Expected Ports:
2

Roles:
Port A
Port B
```

These can subsequently be mapped to inlet/outlet semantics where required.

## Equal Tee

```text
Expected Ports:
3

Roles:
Main A
Main B
Branch
```

## Unequal Tee

```text
Expected Ports:
3

Roles:
Main
Branch 1
Branch 2
```

Use geometry/topology and the product contract together.

A larger opening can be useful evidence for the primary/main port, but should not be the only rule when stronger geometric evidence is available.

Apply the same general principle to unequal crosses.

---

# 16. Stage 2 — Save Port Mapping Into DSF

After port mapping succeeds, save the DSF again.

The file now contains:

```text
Stage 1
Manufacturing Definition

+

Stage 2
Port Mapping
```

At this point:

```text
Manufacturing Definition = COMPLETE
Port Mapping              = COMPLETE
Template Scaling          = NOT COMPLETE
```

---

# 17. Reopening a Stage-2 DSF

When reopened:

```text
CMS PART

Manufacturing definition: ✓
Port mapping: ✓
Template scaling: not completed

[ Continue Template Scaling ]
[ Review Port Mapping ]
[ Edit Manufacturing Definition ]
```

Do not rerun port mapping unless the user changes the manufacturing definition.

---

# 18. Stage 3 — Template / Parametric Scaling

Stage 3 builds the scalable CMS template using:

```text
DXF geometry
+
Manufacturing definition
+
Port mapping
+
CMS product definition
```

This stage creates:

```text
Primary Parameters
Derived Parameters
Geometric Dependencies
Constraints
Protected Features
Scaling Rules
```

---

# 19. Product Definition Controls Both Port Mapping and Scaling

Each CMS variation should provide a declarative definition containing two major contracts.

## Port Contract

```text
Expected Port Count
Port IDs / Roles
Port Matching Rules
Port Relationships
```

## Scaling Contract

```text
Primary Parameters
Derived Parameters
Geometry Dependencies
Protected Features
Feature Constraints
Scaling Relationships
```

Conceptual structure:

```text
CMS Product Definition
────────────────────────────
Identity
  Category
  Product Type
  Variation

Port Contract
  Expected Count
  Roles
  Matching Rules

Parameter Contract
  Primary Parameters
  Derived Parameters

Scaling Contract
  Dependencies
  Constraints
  Protected Features
```

This allows all 150 variations to be handled by common engines.

---

# 20. Scaling Must Not Be Global DXF Stretching

Do not make the primary scaling implementation simply:

```text
Scale X
Scale Y
```

Instead:

```text
Change parameter
      ↓
Recalculate dependencies
      ↓
Update structural geometry
      ↓
Update port geometry
      ↓
Update bend/flange relationships
      ↓
Preserve constrained features
      ↓
Regenerate 3D
```

---

# 21. Example — Unequal Tee Scaling

Conceptual parameters:

```text
Main W
Main H
Branch W
Branch H
Branch Position
Flange F
```

Dependencies:

```text
Main Port
  ← Main W / Main H

Branch Port
  ← Branch W / Branch H

Branch Location
  ← Branch Position

Connected faces
  ← derived from parameters

Bend lines
  ← derived from updated face geometry

Coupler features
  ← constrained to relevant geometry
```

The generic scaling engine should execute these relationships from the product definition.

---

# 22. Feature Protection

Classify geometry into at least three categories.

## Structural Geometry

Responsive to parameters.

Examples:

- face boundaries
- bend positions
- flange dimensions
- port boundaries

## Protected Manufacturing Features

Preserve their manufacturing intent.

Examples:

- coupler holes
- mounting holes
- defined feature patterns

## Reference Geometry

Used for dependencies and construction.

Examples:

- centerlines
- construction lines
- parameter references

---

# 23. DSF Workflow State

The DSF should contain explicit CMS workflow metadata.

Conceptual structure:

```json
{
  "cms": {
    "enabled": true,
    "category": "tray_accessories",
    "productType": "tee",
    "variation": "unequal_tee",

    "workflow": {
      "stage": "PORT_MAPPING",
      "manufacturingDefinitionComplete": true,
      "portMappingComplete": true,
      "templateComplete": false
    }
  }
}
```

Recommended states:

```text
MANUFACTURING_DEFINITION
PORT_MAPPING
TEMPLATE_SCALING
COMPLETE
```

The explicit completion flags should remain useful even if the stage enum changes later.

---

# 24. DSF Backward Compatibility

New CMS data must be optional.

An existing DSF without CMS metadata must continue to behave as a normal DSF.

Conceptually:

```text
Old DSF
   ↓
No CMS section
   ↓
Open normally
```

A DSF containing bends but no port mapping should also remain valid:

```text
DSF
✓ Bend structure
✗ Port mapping
✗ Template scaling
```

On open, offer the appropriate next CMS stage rather than treating the file as corrupt or incomplete CAD.

---

# 25. Important Invalidation Rule

The three stages must have dependency-aware invalidation.

If the user modifies Stage 1 manufacturing definition:

```text
Stage 1 changes
      ↓
Port mapping becomes stale
      ↓
Template scaling becomes stale
```

Therefore:

```text
Modify bend/flange/coupler definition
        ↓
Invalidate Stage 2
        ↓
Invalidate Stage 3
```

The application should warn clearly before discarding stale downstream results.

Example:

```text
Manufacturing structure changed.

Existing port mapping and scaling relationships may no longer
match the new geometry.

[ Rebuild Port Mapping ]
[ Cancel ]
```

Likewise, changing only Stage 2 port mapping should invalidate the dependent parts of Stage 3 without unnecessarily destroying Stage 1.

---

# 26. Visual Progress UX

Keep the simplified guided experience.

Do not expose complicated CAD controls when the app is processing.

### Stage 1

```text
Define Manufacturing Structure

✓ Bend lines
✓ Flange lines
✓ Coupler features
```

### Stage 2

```text
Understanding your part...

✓ Reading manufacturing structure
✓ Folding 3D model
✓ Finding openings
✓ Identifying ports
✓ Assigning port relationships
```

### Stage 3

```text
Building your CMS template...

✓ Reading dimensions
✓ Building dependencies
✓ Protecting manufacturing features
✓ Building scaling relationships
✓ Testing regeneration
```

At each successful stage, briefly highlight the relevant 2D and 3D geometry with a glow/pulse animation.

---

# 27. Recommended CMS Product Definition Example

Conceptual example only; follow the project's existing schema.

```json
{
  "productType": "tee",
  "variation": "unequal_tee",

  "portContract": {
    "expectedCount": 3,
    "ports": [
      { "id": "main", "role": "main" },
      { "id": "branch1", "role": "branch" },
      { "id": "branch2", "role": "branch" }
    ]
  },

  "parameterContract": {
    "primary": [
      "mainWidth",
      "mainHeight",
      "branchWidth",
      "branchHeight",
      "branchPosition"
    ],
    "derived": []
  },

  "scalingContract": {
    "protectedFeatures": [
      "couplerHoles"
    ],
    "dependencies": [],
    "constraints": []
  }
}
```

This is illustrative. The implementation should adapt the concept to the actual existing data structures.

---

# 28. Agent Implementation Plan

## Set 0 — Audit Existing Architecture

Inspect:

- DXF Inspector
- CMS entry point
- current manual bend authoring
- current manual flange authoring
- current DSF persistence
- existing automatic port-mapping algorithm
- current scaling/template logic
- legacy auto bend/flange routines

Create:

```text
docs/CMS_3_STAGE_ARCHITECTURE_AUDIT.md
```

---

## Set 1 — Disconnect Auto Bend/Flange Detection

- Remove automatic bend detection from the active CMS path.
- Remove automatic flange detection from the active CMS path.
- Preserve legacy code where practical.
- Clearly mark it legacy/experimental.
- Ensure there is no hidden fallback that recreates bend/flange lines.

Acceptance criterion:

> A new CMS DXF never receives invented manufacturing bend/flange lines.

---

## Set 2 — Stage 1 Persistence

Ensure the manually authored:

- bend lines
- flange lines
- coupler/features

are saved in DSF.

A Stage-1 DSF must reopen correctly.

---

## Set 3 — Workflow State

Add CMS workflow metadata that allows the application to determine:

```text
Stage 1 complete?
Stage 2 complete?
Stage 3 complete?
```

Do not break existing DSFs.

---

## Set 4 — Stage 2 Port Mapping

Connect the existing port-mapping algorithm to the saved Stage-1 manufacturing definition.

Do not regenerate manufacturing lines.

Save port mappings back into DSF.

---

## Set 5 — Product Definition Layer

Create a declarative CMS product-definition mechanism capable of describing the approximately 150 variations.

It must describe:

- port expectations
- port roles
- port matching rules
- primary dimensions
- derived dimensions
- dependencies
- protected features
- constraints

Avoid product-specific code duplication.

---

## Set 6 — Stage 3 Scaling

Connect the product definition to the generic scaling/dependency engine.

Ensure changes to primary parameters regenerate:

- 2D geometry
- bend relationships
- flange relationships
- ports
- protected features where constrained
- 3D model

---

## Set 7 — Stage Invalidation

Implement dependency-aware invalidation.

```text
Stage 1 changed
→ invalidate 2 and 3

Stage 2 changed
→ invalidate dependent parts of 3

Stage 3 changed
→ Stage 1 and 2 remain valid
```

---

## Set 8 — UX Polish

Provide the guided stage-based experience with:

- clear current stage
- save at every stage
- resume on reopen
- animated 2D/3D confirmation
- review/edit actions
- no expert-level interactions

---

# 29. Acceptance Tests

## Test A — Stage 1 Save

User defines bends, flanges and coupler holes.

Expected:

```text
DSF saves successfully.
```

On reopen:

```text
Manufacturing definition = complete
Port mapping = incomplete
```

---

## Test B — Resume Port Mapping

Open a Stage-1 DSF.

Expected option:

```text
[ Continue Port Mapping ]
```

---

## Test C — Port Mapping

Run Stage 2.

Expected:

- existing bends used exactly
- existing flange lines used exactly
- folded model generated
- openings discovered
- ports assigned
- port data saved

---

## Test D — Resume Scaling

Open a Stage-2 DSF.

Expected:

```text
[ Continue Template Scaling ]
```

---

## Test E — Product Definition

Create several different CMS variations through configuration only.

Expected:

- different port counts supported
- different port roles supported
- different parameter sets supported
- different scaling dependencies supported

without creating a new algorithm class for every variation.

---

## Test F — Stage Invalidation

Change a Stage-1 bend line.

Expected:

```text
Stage 2 becomes stale.
Stage 3 becomes stale.
Stage 1 remains valid.
```

---

## Test G — Backward Compatibility

Open an older normal DSF without CMS metadata.

Expected:

```text
Normal DSF workflow continues unchanged.
```

---

# 30. Final Architecture

```text
                         CMS PRODUCT DEFINITION
                                  │
                                  ▼
       ┌─────────────────────────────────────────────┐
       │ STAGE 1                                     │
       │ MANUFACTURING DEFINITION                    │
       │                                             │
       │ HUMAN                                       │
       │ • Bend lines                                │
       │ • Flange lines                              │
       │ • Coupler / manufacturing features         │
       └──────────────────────┬──────────────────────┘
                              │
                            SAVE
                              │
                              ▼
       ┌─────────────────────────────────────────────┐
       │ STAGE 2                                     │
       │ AUTOMATIC PORT MAPPING                      │
       │                                             │
       │ GENERIC ENGINE                              │
       │ • Fold using saved manufacturing structure  │
       │ • Find physical openings                    │
       │ • Create candidates                         │
       │ • Apply product contract                    │
       │ • Assign ports / roles                      │
       └──────────────────────┬──────────────────────┘
                              │
                            SAVE
                              │
                              ▼
       ┌─────────────────────────────────────────────┐
       │ STAGE 3                                     │
       │ TEMPLATE / PARAMETRIC SCALING               │
       │                                             │
       │ GENERIC ENGINE                              │
       │ • Parameters                                │
       │ • Dependencies                              │
       │ • Constraints                               │
       │ • Protected features                        │
       │ • Regeneration                              │
       └──────────────────────┬──────────────────────┘
                              │
                            SAVE
                              │
                              ▼
                     COMPLETE CMS DSF
```

## Core Rules

1. **Never auto-invent manufacturing bend/flange intent.**
2. **Stage 1 is manually authored and independently saveable.**
3. **Stage 2 consumes Stage-1 data; it never recreates it.**
4. **Stage 2 port mappings are saved in the DSF.**
5. **Stage 3 consumes the saved port mapping and builds scaling dependencies.**
6. **The approximately 150 CMS variations are product definitions/configurations, not 150 independent algorithms.**
7. **Changing an earlier stage invalidates dependent later stages.**
8. **Existing non-CMS DSFs remain backward compatible.**
9. **The user can stop and resume at any stage.**

> **Human defines manufacturing structure once.**
>
> **TruFold Studio discovers ports automatically and builds the reusable parametric template from that definition.**
