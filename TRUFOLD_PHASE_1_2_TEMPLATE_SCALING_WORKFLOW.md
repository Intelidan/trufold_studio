# TruFold Studio — CMS Template Scaling Workflow

## Phase 1 Completion Summary + Phase 2 Intelligent Template Scaling

---

# Phase 1 — Completed CMS Template Authoring

Phase 1 establishes the intelligent CMS authoring foundation while preserving TruFold Studio’s normal DXF workflow: the user opens a regular DXF and, through the DXF Inspector, chooses whether it is a CMS Part Drawing; when CMS mode is selected, TruFold collects the Product Contract (category, product type, variation, and required physical dimensions), then guides the user through explicit bend-line and flange-line definition, using intelligent suggestions and synchronized 2D/3D highlighting while requiring the user to confirm or draw the actual manufacturing structure. Once the user-defined bend/flange structure is folded, TruFold derives physical openings from the folded 3D topology, matches those openings to semantic CMS ports, preserves relevant manufacturing features such as coupler holes and perforations, and stores the CMS intelligence in the DSF without altering the source DXF. The legacy flat-DXF opening-count/port-discovery flow, “19 openings” style dialog, manual edge-pointer assignment, and obsolete wizard state are retired or quarantined. The existing DXF parser, bend/fold engine, face decomposition, punch/feature handling, and rendering remain intact. Phase 1 therefore ends with a semantically understood CMS template whose product definition, bend structure, flange structure, folded topology, ports, and protected features are ready to drive Phase 2 intelligent scaling.

---

# Phase 2 — Intelligent Template Scaling

## 1. Objective

Phase 2 converts the Phase 1 CMS template into a reusable intelligent parametric template without turning TruFold into a traditional constraint-heavy CAD authoring tool.

The internal implementation may use constraints, dependency graphs, topology relationships, feature anchors, stretch zones, rigid zones, and regeneration algorithms. Those mechanisms should remain mostly invisible to the normal user.

The user experience should be:

```text
Select product dimension
        ↓
Change value
        ↓
Preview what will move
        ↓
2D + 3D model morph together
        ↓
Automatically validate
        ↓
Accept or cancel
        ↓
Template learns the scaling relationship
```

### Core UX principle

> **The user teaches TruFold how the product behaves; the user does not manually build a CAD constraint system.**

---

# 2. UX Goals

The Phase 2 experience must feel like a modern manufacturing intelligence system rather than a conventional CAD constraint editor.

## The user should feel

- The template is understanding the physical product.
- Dimension changes cause the model to physically respond.
- TruFold explains what it is doing visually.
- Important manufacturing features remain protected automatically.
- The user remains in control before a relationship is committed.

## The user should not need to understand

- Horizontal/vertical constraints.
- Coincident constraints.
- Parametric equation trees.
- Dependency graphs.
- Vertex-level manipulation.
- Raw DXF coordinates.
- Manual port-edge mapping.
- Individual hole relocation.

## Primary interaction language

```text
CHANGE → WATCH → UNDERSTAND → ACCEPT
```

---

# 3. Entry Point: “Teach Scaling”

At the end of Phase 1, the CMS template should expose a new action:

> **Teach Scaling**

For an already-trained template, the action becomes:

> **Edit Template Behavior**

The application enters a dedicated visual state:

```text
┌─────────────────────────────────────────────────────────────┐
│ TEMPLATE INTELLIGENCE                                       │
│                                                             │
│  2D Flat Pattern                 3D Folded Model            │
│                                                             │
│                                                             │
│                     CMS PARAMETERS                          │
│                                                             │
│  Width    300 mm      Height    100 mm                      │
│  Port 1   300 mm      Branch    200 mm                      │
│                                                             │
│             [ Preview Scaling ]                             │
└─────────────────────────────────────────────────────────────┘
```

The application should explain the objective with a short, non-technical message:

> **Teach TruFold what should move when the product dimensions change.**

---

# 4. Reuse Phase 1 Intelligence

Phase 2 must not rediscover everything from the DXF.

The DSF produced by Phase 1 becomes the authoritative starting point.

The scaling engine should consume:

```text
Product Contract
Bend Structure
Flange Structure
Folded 3D Topology
Physical Ports
Port Roles
Protected Features
Feature Groups
Existing dimension metadata
```

The scaling engine should therefore begin with a semantically understood model rather than a collection of anonymous lines.

---

# 5. Semantic Template Model

The internal model should contain stable semantic identities.

Recommended entities:

```text
Product
Variation
Port
Bend
Flange
Face
Feature
FeatureGroup
CouplerGroup
PerforationGroup
Dimension
ScalingRelationship
StretchZone
RigidZone
ReferenceAnchor
```

Example identifiers:

```text
PORT_01
PORT_02
PORT_03

BEND_01
BEND_02
BEND_03

FLANGE_01
FLANGE_02

FEATURE_GROUP_01
```

### Important implementation rule

Do not make raw DXF line indexes the permanent semantic identity of template components.

Geometry may be regenerated, split, reordered, or transformed during scaling. Semantic IDs must remain stable.

---

# 6. Product Parameters

The application should automatically derive a product-specific parameter set from the CMS Product Contract and recognized topology.

Only parameters relevant to the selected product variation should be exposed.

## Examples

### Straight Tray

```text
Width
Height
Length
```

### 90° Bend

```text
Width
Height
Radius
Angle
```

### Equal Tee

```text
Width
Height
Main Length
Branch Length
```

### Unequal Tee

```text
Main Width
Main Height
Branch Width
Branch Height
Branch Length
```

### Unequal Cross

```text
Main Width
Main Height
Branch A Width
Branch A Height
Branch B Width
Branch B Height
```

Do not expose a generic “all possible CAD parameters” panel.

---

# 7. Parameter Behavior Types

Every product parameter should declare its intended behavior.

Recommended types:

```text
DIMENSION_DRIVING
DIMENSION_DERIVED
DIMENSION_LINKED
DIMENSION_INDEPENDENT
DIMENSION_LOCKED
```

Examples:

```text
Main Width        → DIMENSION_DRIVING
Port 1 Width      → DIMENSION_LINKED
Port Opening      → DIMENSION_DERIVED
Coupler Slot Size → DIMENSION_LOCKED
```

This keeps the user interface simple while allowing a sophisticated internal system.

---

# 8. Build the Scaling Relationship Graph

This is the core technical engine of Phase 2.

A product parameter should point to the geometry and semantic objects affected by that parameter.

Example:

```text
MAIN_WIDTH
    ↓
PORT_01 width
    ↓
PORT_01 opening
    ↓
PORT_01 surrounding faces
    ↓
associated bend locations
    ↓
associated flange locations
    ↓
stretch zones
    ↓
2D flat geometry
```

Another example:

```text
PORT_02_HEIGHT
    ↓
physical opening height
    ↓
connected wall height
    ↓
associated flange
    ↓
flat pattern region
```

### Relationship types

The engine should support at least:

```text
DRIVE
FOLLOW
OFFSET_FROM
CENTER_ON
ANCHOR_TO
PRESERVE
TRANSLATE_WITH
RESIZE_REGION
REGENERATE_PATTERN
DERIVE_FROM
```

---

# 9. Do Not Build a Blind Global Scale

The template must not simply apply a percentage scale to the entire DXF.

For example:

```text
300 mm → 400 mm
```

must not automatically mean:

```text
all geometry × 1.3333
```

That would incorrectly enlarge:

- Hole sizes.
- Coupler slots.
- Bend feature geometry.
- Manufacturing details.
- Flange thickness-related geometry.
- Fixed offsets.

Instead, scaling must be **semantic and region-based**.

---

# 10. Stretch Zones

The engine divides geometry into regions that can absorb dimensional changes.

Typical examples:

```text
MAIN_WALL_STRETCH_ZONE
SIDE_WALL_STRETCH_ZONE
BRANCH_WALL_STRETCH_ZONE
FLAT_REGION_STRETCH_ZONE
LONGITUDINAL_STRETCH_ZONE
```

Each zone should contain:

```text
zoneId
allowedDirections
associatedParameterIds
boundaryAnchors
protectedFeatures
connectedBends
connectedFlanges
scalingMode
```

### Typical scaling modes

```text
EXTEND
CONTRACT
TRANSLATE
CENTER
DISTRIBUTE
REGENERATE
```

---

# 11. Rigid Zones

Rigid zones contain geometry whose physical dimensions should remain unchanged.

Examples:

- Coupler holes.
- Coupler slots.
- Perforations.
- Small punch features.
- Feature groups with fixed dimensions.
- Manufacturing reference geometry.

A rigid feature should preserve:

```text
Size
Shape
Orientation
Internal pattern relationship
Manufacturing meaning
```

For example, a 7 × 20 mm coupler slot should not become 9 × 26 mm merely because the surrounding wall becomes wider.

---

# 12. Protected Feature Model

Phase 1 feature semantics should become explicit scaling behavior.

Example:

```text
COUPLER_GROUP_01

Geometry:
    SLOT_01
    SLOT_02
    SLOT_03
    SLOT_04

Behavior:
    PRESERVE_SIZE
    PRESERVE_ORIENTATION
    PRESERVE_PATTERN
    FOLLOW_REFERENCE_EDGE
```

The same concept should apply to perforation groups.

---

# 13. Pattern-Aware Features

Do not relocate every perforation or hole independently.

Treat repeated geometry as a semantic pattern.

Example:

```text
PERFORATION_PATTERN_01

Reference:
    EDGE_12

Direction:
    X

Spacing:
    50 mm

Count:
    derived / fixed

Behavior:
    preserve feature size
    preserve spacing rule
    adapt extent to host region
```

When the host region expands:

```text
Wall expands
      ↓
Pattern evaluates new usable length
      ↓
Pattern regenerates
      ↓
Feature geometry remains manufacturing-valid
```

---

# 14. Port-Centered Scaling

Ports are the most important semantic anchors for CMS scaling.

A port should be represented as a physical opening with topology, not just as a flat edge.

Example:

```text
PORT_01

Role:
    MAIN / INLET

Dimensions:
    Width
    Height

Connected topology:
    Opening
    Face group
    Bend group
    Flange group

Scaling behavior:
    Width-driven
    Height-driven
```

When the user changes a port dimension, the engine propagates the change into the physical structure connected to that port.

---

# 15. Port Role Rules

The existing CMS product rules should feed Phase 2.

Examples:

### Simple Reducer

```text
Port 1 → inlet
Port 2 → outlet
```

### Bend / Riser

```text
Port 1 → inlet or outlet
Port 2 → inlet or outlet
```

The system may assign a role based on the product contract or allow the user to set it where required.

### Unequal Tee / Cross

The product contract may identify the primary/highest-width port as the principal inlet and remaining ports as branches/outlets, subject to the CMS product rules already implemented in Phase 1.

Scaling must respect these semantic identities.

---

# 16. The Main UX: “Change a Dimension”

The user selects a dimension card.

Example:

```text
MAIN WIDTH
300 mm
```

They enter:

```text
400 mm
```

TruFold should NOT immediately modify the permanent template.

Instead, enter **Preview Scaling Mode**.

---

# 17. Live Morph Preview

The model should morph smoothly from the old state to the proposed state.

Example:

```text
300
 ↓
325
 ↓
350
 ↓
375
 ↓
400
```

The animation should be fast enough to feel responsive but slow enough that the user can perceive the dependency.

The same transition occurs in both:

- 2D flat pattern.
- 3D folded model.

---

# 18. Visualize What Moves

This is one of the signature TruFold UX features.

During scaling:

- Changed regions should softly glow.
- Translated geometry should pulse briefly.
- Protected features should remain visually stable.
- Affected ports should highlight.
- Associated bends should highlight.
- Associated flanges should highlight.
- Corresponding 2D and 3D regions should be synchronized.

The objective is for the user to immediately understand:

> **“This parameter controls this physical portion of the product.”**

---

# 19. The “What Moves?” Overlay

After the morph begins, display a temporary overlay such as:

```text
MAIN WIDTH

Controls:
✓ Main Wall
✓ Port 1 Opening
✓ Port 1 Bend Boundary
✓ Port 1 Flange Boundary

Preserves:
✓ Coupler Pattern
✓ Slot Dimensions
```

This overlay should fade away after the preview or after a short period.

Do not turn it into a permanent engineering report.

---

# 20. Synchronization Between 2D and 3D

The same semantic relationship must drive both representations.

Example:

```text
Parameter
   ↓
Semantic region
   ├── 2D geometry update
   └── 3D topology update
```

If the main wall expands:

### 2D

The corresponding flat region stretches.

### 3D

The physical wall expands.

### Port

The opening changes accordingly.

### Protected feature

The hole/slot remains intact.

This makes the result physically understandable rather than merely mathematically correct.

---

# 21. Automatic Relationship Discovery

The first scaling setup should be largely automated.

The engine should analyze the Phase 1 template and infer high-confidence relationships using:

- Product contract.
- Port identity.
- Folded topology.
- Bend adjacency.
- Flange adjacency.
- Feature proximity.
- Symmetry.
- Existing dimension metadata.
- Reference-edge relationships.
- Pattern semantics.

Example:

```text
Main Width detected
        ↓
Port 1 width is topologically linked
        ↓
Main wall region contains opening
        ↓
Flange follows wall boundary
        ↓
Coupler group is anchored to the edge
```

The engine proposes the relationship.

---

# 22. Human Confirmation of Automatic Relationships

Even high-confidence automatic relationships should be previewed before permanent commitment.

Example:

> **TruFold found a scaling relationship.**
>
> Increasing Main Width moves the main wall and Port 1 while preserving the coupler pattern.
>
> **Preview**

Then show the 2D + 3D morph.

Buttons:

```text
[ Accept ]     [ Cancel ]
```

After Accept:

```text
✓ Relationship added
```

---

# 23. Exception Handling for Ambiguous Geometry

The normal workflow should require minimal manual input.

If TruFold cannot safely determine a relationship, identify only the affected feature.

Example:

> **One feature needs your direction.**
>
> When Width increases, how should this feature behave?
>
> `Follow Left Edge`
> `Follow Right Edge`
> `Stay Centered`

The user should choose from simple product-behavior options.

Never expose raw coordinate editing merely because the automatic inference failed.

---

# 24. Feature Anchoring UX

For a feature that must remain attached to a reference, use a simple visual “pin” interaction.

The user selects a feature and chooses:

```text
PIN
```

TruFold then asks only where it should remain attached if ambiguity exists:

```text
Follow Edge
Stay Centered
Stay Fixed
```

A small pin icon can appear in the 2D and 3D views.

This replaces conventional constraint authoring with a physical-behavior metaphor.

---

# 25. Center-Based Relationships

Some features should remain centered as a region changes.

Example:

```text
Wall Width: 300 → 400
```

If a hole group is centered on the wall, it should remain centered instead of staying at a fixed left offset.

Relationship:

```text
CENTER_ON
```

The preview should visibly move the feature from the old center to the new center.

---

# 26. Edge-Follow Relationships

For features that maintain a manufacturing offset from an edge:

```text
FOLLOW_EDGE
```

Example:

```text
Hole center = 20 mm from flange edge
```

When the wall expands, the hole remains 20 mm from the defined reference edge.

The user should not need to enter a constraint equation.

---

# 27. Fixed Relationships

Some dimensions remain fixed regardless of product scaling.

Examples:

```text
Coupler slot width = 7 mm
Coupler slot length = 20 mm
Flange return = product-rule-defined fixed value
```

These should be represented as fixed semantic values, not as arbitrary geometry that happens to remain unchanged.

---

# 28. Linked Dimensions

Support simple linking between related CMS dimensions.

Example:

```text
Height A    100 mm
Height B    100 mm

[ Linked ✓ ]
```

Changing Height A may drive Height B.

The user can unlock the relationship:

```text
Height A    150 mm
Height B    100 mm

[ Linked ○ ]
```

The internal implementation should record this as a product-level relationship, not as a raw geometric constraint.

---

# 29. Scaling the Main Dimension of an Unequal Tee

Use the unequal tee as a key end-to-end test case.

Initial product:

```text
Main Width   300
Main Height  100
Branch Width 200
Branch Height 100
```

User changes:

```text
Main Width 300 → 400
```

Expected system behavior:

```text
1. Identify Main Width as the driving dimension.
2. Identify the corresponding principal port.
3. Identify connected wall regions.
4. Identify connected bend boundaries.
5. Identify connected flange boundaries.
6. Expand designated stretch zones.
7. Preserve rigid features.
8. Update opening geometry.
9. Rebuild/refresh flat pattern geometry.
10. Update folded 3D representation.
11. Validate CMS topology.
12. Validate manufacturing geometry.
13. Present final preview.
```

---

# 30. Scaling a Branch of an Unequal Tee

Example:

```text
Branch Width
200 → 250
```

Only the branch-associated region should respond unless the product contract explicitly defines a linked relationship.

Expected behavior:

```text
Branch Port
    ↓
Branch opening
    ↓
Branch wall region
    ↓
Branch bend/flange structure
    ↓
Corresponding flat geometry
```

The main port should remain unchanged unless the topology rules explicitly require propagation.

---

# 31. Scaling an Unequal Cross

The cross requires independent semantic port identity.

Example:

```text
PORT_01 = Main
PORT_02 = Branch A
PORT_03 = Branch B
PORT_04 = Branch C
```

Changing Branch B Width must not accidentally alter Branch A or Branch C.

The dependency graph must therefore be port-aware.

---

# 32. Global Product Resize vs. Local Port Resize

The scaling UI should distinguish between:

### Product dimension

Changes a broader region of the product.

Example:

```text
Overall Width
```

### Port dimension

Changes a specific physical opening.

Example:

```text
Port 02 Width
```

The visual UI should make the scope obvious.

Use the semantic name rather than exposing geometric implementation language.

---

# 33. Scaling by Dragging a Dimension in 2D

The system may optionally support direct dimension manipulation.

Example:

A dimension label is shown near the 2D geometry:

```text
←──── 300 mm ────→
```

The user drags the dimension endpoint.

As it moves:

- numeric value updates
- 2D geometry morphs
- 3D geometry morphs
- affected region glows
- protected features remain stable

Release the drag to enter the normal preview state.

This should be an interaction layer over the semantic parameter system, not a separate scaling engine.

---

# 34. Futuristic “Morph Timeline”

To make the behavior visually understandable, the preview can show a minimal temporary timeline:

```text
300 ━━━━━━━━━━━━━━━●━━━━ 400
```

Dragging the marker lets the user scrub between the original and new values.

This is particularly useful for complex templates because it lets the user inspect:

- when a feature moves
- when a region expands
- whether a branch remains connected
- whether a pattern regenerates correctly

The timeline should appear only during active preview.

---

# 35. Multi-Parameter Preview

The system should also support changing several product dimensions before committing.

Example:

```text
Main Width       300 → 400
Main Height      100 → 150
Branch Width     200 → 250
```

Then:

> **Preview changes**

All changes should morph together so that the user can evaluate the resulting physical product.

The preview engine must still retain parameter-level attribution so the user can understand which regions are controlled by which dimensions.

---

# 36. Undo and Revert

Scaling must remain reversible.

Required behavior:

```text
Preview → Cancel
```

restores the exact previous template state.

After Apply:

```text
Undo
```

should restore the prior committed state.

The scaling engine should therefore operate on a cloned/transactional template model until the user commits.

---

# 37. Transactional Regeneration Architecture

Recommended internal flow:

```text
Current Template
      ↓
Create Preview Snapshot
      ↓
Apply Parameter Changes
      ↓
Resolve Relationships
      ↓
Regenerate Geometry
      ↓
Rebuild 3D
      ↓
Rebuild/Update Flat Pattern
      ↓
Validate
      ↓
Preview Result
      ↓
Commit OR Discard
```

Do not mutate the authoritative template state during an unconfirmed preview.

---

# 38. Geometry Regeneration Strategy

The scaling engine should prefer semantic region modification over full geometric distortion.

Recommended sequence:

```text
1. Resolve changed parameters.
2. Resolve affected semantic objects.
3. Resolve stretch/rigid/translatable regions.
4. Move boundary anchors.
5. Extend/contract stretch regions.
6. Translate dependent features.
7. Regenerate feature patterns.
8. Reconstruct affected topology.
9. Recompute folds.
10. Update 3D.
11. Update 2D.
12. Validate.
```

This should minimize unnecessary geometry changes.

---

# 39. Bend Preservation

The scaling system must preserve the intended bend structure.

A dimension change should not casually:

- Delete bends.
- Create duplicate bends.
- Change bend direction.
- Break connected walls.
- Modify unrelated bend angles.

The semantic bend identity should survive regeneration.

If a bend location itself needs to move because a wall changes width, the bend should translate with the appropriate boundary relationship rather than being deleted and recreated as an unrelated element.

---

# 40. Flange Preservation

Flanges are explicitly user-defined in Phase 1.

Phase 2 should preserve that authored intent.

When the host wall changes:

```text
Wall boundary changes
       ↓
Flange boundary follows wall
       ↓
Flange width / return rule remains valid
       ↓
3D flange updates
       ↓
2D flat geometry updates
```

The engine should not silently change a user-defined flange into an auto-generated flange.

---

# 41. Port Opening Integrity

After every scaling operation, recompute the physical opening from the updated folded structure where required.

Do not assume that the original flat pattern width is always the final physical opening.

The folded topology remains the authoritative source for physical port geometry.

This is essential for tees, crosses, reducers, bends, and other non-trivial CMS accessories.

---

# 42. Product-Rule Formula Integration

Where the CMS Product Contract defines dimensional formulas, they should be used as semantic rules.

For example, a port-opening rule may be represented by the product engine rather than by manually stretching anonymous DXF edges.

The scaling pipeline becomes:

```text
Product Dimension
      ↓
CMS Product Rule
      ↓
Target Physical Port Size
      ↓
Semantic Geometry Update
      ↓
Folded Topology
      ↓
Flat Pattern
```

Existing CMS rules such as width/height/return relationships should be retained and integrated with the new scaling engine.

---

# 43. Protected Coupler Features

Coupler mounting holes must remain distinct from ordinary tray perforations.

Scaling must know whether a feature represents:

```text
COUPLER_FEATURE
PERFORATION
MOUNTING_FEATURE
OTHER_PUNCH_FEATURE
```

A coupler feature may follow an edge or port while retaining exact feature geometry.

Ordinary perforations may be pattern-regenerated.

This semantic distinction must survive the scaling process.

---

# 44. Automatic Safety Validation

Run validation after every preview.

## Geometry validation

Check:

- Self-intersection.
- Invalid contours.
- Broken topology.
- Disconnected surfaces.
- Invalid face boundaries.

## Sheet-metal validation

Check:

- Bend connectivity.
- Fold consistency.
- Flange continuity.
- Flat-pattern consistency.

## CMS validation

Check:

- Expected port count.
- Port connectivity.
- Product variation topology.
- Inlet/outlet or branch semantics.

## Manufacturing validation

Check:

- Hole integrity.
- Feature spacing.
- Feature-to-bend clearance.
- Feature-to-edge clearance.
- Coupler integrity.

---

# 45. Validation UX

Do not interrupt the user with a technical error list during normal operation.

Use a compact state indicator:

```text
✓ Scaling Valid
```

or:

```text
⚠ Scaling Needs Attention
```

Clicking the warning should focus the affected area in both 2D and 3D.

Example:

> **Coupler slot is too close to the new bend boundary.**

The relevant feature should pulse in both views.

---

# 46. Invalid Preview Behavior

An invalid preview must never overwrite the committed template.

The user should see:

```text
Preview Result

⚠ Cannot apply this size

Reason:
The selected branch dimension causes a manufacturing feature
collision near the bend region.
```

Actions:

```text
[ Adjust Dimension ]
[ Cancel ]
```

Do not expose low-level solver failures as the primary UX.

---

# 47. Confidence Indicators

Automatic relationship discovery can use an internal confidence score, but the normal UI should remain simple.

Internally:

```text
Port relationship     0.98
Edge relationship     0.96
Feature anchor        0.94
Pattern relationship  0.91
```

The user-facing UI should translate this into:

```text
✓ Automatically understood
```

or, when needed:

```text
Needs your direction
```

Do not expose technical confidence numbers unless an advanced diagnostic/debug mode is explicitly needed by developers.

---

# 48. “Teach Once, Reuse Forever”

The major outcome of Phase 2 is not only that the current template scales.

It is that the scaling behavior is stored in the intelligent template.

The DSF should therefore retain:

```text
CMS Product Contract
Bend Structure
Flange Structure
Port Definitions
Feature Semantics
Parameter Definitions
Scaling Relationships
Stretch Zones
Rigid Zones
Anchors
Validation Rules
```

This allows the template to become a reusable product family definition.

---

# 49. Save Intelligent Template

Once the scaling behavior is successfully tested:

Display:

# ✦ Intelligent Template Ready

```text
UNEQUAL TEE

Adjustable:
✓ Main Width
✓ Main Height
✓ Branch Width
✓ Branch Height
✓ Branch Length

Preserved:
✓ Bend Structure
✓ Flanges
✓ Port Relationships
✓ Coupler Features
✓ Perforation Rules
```

Primary action:

```text
[ Save Intelligent Template ]
```

---

# 50. Template Test Mode

Before final save, provide a dedicated test mode.

The application should generate a few automatically selected test configurations near the original size.

Example:

```text
Original
300 / 100 / 200

Test A
350 / 100 / 200

Test B
400 / 150 / 250

Test C
250 / 100 / 150
```

For each test:

```text
Generate Preview
Validate
Show 2D
Show 3D
```

This allows the author to detect a bad relationship before the template enters production use.

---

# 51. Template Behavior Report

At the end of testing, show a simple visual summary.

Example:

```text
TEMPLATE BEHAVIOR

5 parameters understood
18 relationships established
11 features protected
6 stretch regions
4 feature groups
3 port relationships

Validation:
✓ Test A
✓ Test B
✓ Test C
```

The report should describe behavior, not expose raw CAD constraints.

---

# 52. End-User Product Configuration After Phase 2

Once the template has been authored, ordinary users should not enter “Teach Scaling” at all.

They should simply choose the product variation.

Example:

```text
CMS
 ↓
Tee
 ↓
Unequal Tee
```

Then a clean configurator appears:

```text
┌─────────────────────────────────────┐
│ UNEQUAL TEE                         │
│                                     │
│ Main Width       400 mm             │
│ Main Height      100 mm             │
│ Branch Width     250 mm             │
│ Branch Height    100 mm             │
│                                     │
│          [ Preview 3D ]             │
│          [ Generate ]               │
└─────────────────────────────────────┘
```

The underlying intelligent template performs the scaling automatically.

---

# 53. Product Generation Pipeline

The final production workflow becomes:

```text
Select CMS Product
        ↓
Select Variation
        ↓
Enter Dimensions
        ↓
Semantic Template Loads
        ↓
Scaling Relationships Resolve
        ↓
Geometry Regenerates
        ↓
Bends/Flanges Rebuild
        ↓
Ports Recompute
        ↓
Features Regenerate
        ↓
3D Model Updates
        ↓
Flat Pattern Updates
        ↓
Validation
        ↓
Generate DSF / DXF / TDS output
```

---

# 54. Recommended UX States

Implement the scaling UI as explicit states rather than one large screen.

```text
IDLE
 ↓
SCALING_SETUP
 ↓
RELATIONSHIP_DISCOVERY
 ↓
RELATIONSHIP_REVIEW
 ↓
PREVIEW
 ↓
VALIDATING
 ↓
VALID
   or
INVALID
 ↓
COMMIT / CANCEL
 ↓
READY
```

This state machine should be separate from the underlying geometry algorithms.

---

# 55. Recommended Animation States

The 2D/3D visual system should support semantic focus states:

```text
NORMAL
HIGHLIGHTED
PULSING
MOVING
PROTECTED
WARNING
SUCCESS
```

Examples:

### Moving

A wall being expanded during scaling.

### Protected

A coupler hole that should remain unchanged.

### Warning

A feature approaching an invalid manufacturing condition.

### Success

A newly established scaling relationship.

The visual language from Phase 1 should be reused so the whole CMS workflow feels like one coherent system.

---

# 56. Technical Architecture

Recommended separation:

```text
CMS Product Contract
        ↓
Template Semantic Model
        ↓
Scaling Relationship Engine
        ↓
Geometry Transformation Engine
        ↓
Fold / Topology Engine
        ↓
Feature / Pattern Engine
        ↓
Validation Engine
        ↓
2D Renderer + 3D Renderer
```

### UI should not directly manipulate geometry

The UI sends semantic requests such as:

```text
setParameter("mainWidth", 400)
```

not:

```text
moveVertex(143, +100)
```

The scaling engine decides how the geometry responds.

---

# 57. Data Model Requirements

Recommended conceptual structure:

```text
CmsTemplate
 ├── contract
 ├── dimensions
 ├── ports
 ├── bends
 ├── flanges
 ├── features
 ├── featureGroups
 ├── scalingRelationships
 ├── stretchZones
 ├── rigidZones
 ├── anchors
 └── validationRules
```

Each relationship should be serializable into the DSF template metadata.

Example conceptually:

```json
{
  "parameterId": "mainWidth",
  "relationType": "RESIZE_REGION",
  "targetId": "MAIN_WALL_STRETCH_ZONE",
  "preserve": ["COUPLER_GROUP_01"],
  "update": ["PORT_01", "FLANGE_01"]
}
```

The exact implementation should follow the existing DSF schema rather than introducing a parallel file format unnecessarily.

---

# 58. Performance Requirements

Scaling preview must feel interactive.

Recommended approach:

```text
Parameter edit
      ↓
Fast preview regeneration
      ↓
Render updated result
      ↓
Run full validation asynchronously in the same interaction state
```

For complex geometry, use a staged update:

1. Immediate visual preview.
2. Topology confirmation.
3. Manufacturing validation.
4. Final commit.

The user should see movement quickly rather than waiting for every expensive operation before any visual feedback appears.

---

# 59. Error Recovery

The scaling engine should be able to recover to the last known valid state.

Maintain:

```text
Last Valid Template
Current Preview
Pending Relationship
```

If regeneration fails:

```text
Discard Preview
Restore Last Valid State
Explain Affected Area
```

The user should never be left with a partially regenerated model.

---

# 60. Developer Implementation Order

Implement Phase 2 in dependency order.

## Sprint 2A — Semantic Scaling Foundation

- Create semantic parameter model.
- Create stable IDs.
- Create scaling relationship structures.
- Integrate Phase 1 CMS metadata.
- Add DSF serialization/deserialization for scaling metadata.

## Sprint 2B — Geometry Classification

- Detect stretch zones.
- Detect rigid zones.
- Detect anchors.
- Classify protected feature groups.
- Connect feature patterns to semantic references.

## Sprint 2C — Relationship Engine

- Implement DRIVE.
- Implement FOLLOW.
- Implement OFFSET_FROM.
- Implement CENTER_ON.
- Implement ANCHOR_TO.
- Implement PRESERVE.
- Implement TRANSLATE_WITH.
- Implement RESIZE_REGION.
- Implement REGENERATE_PATTERN.
- Implement DERIVE_FROM.

## Sprint 2D — Preview Engine

- Transactional preview state.
- Parameter editing.
- Morph animation.
- 2D synchronization.
- 3D synchronization.
- Affected-region highlighting.
- Protected-feature highlighting.

## Sprint 2E — Validation

- Geometry validation.
- Bend validation.
- Flange validation.
- Port validation.
- Feature clearance validation.
- CMS topology validation.

## Sprint 2F — Automatic Relationship Discovery

- Infer high-confidence relationships.
- Present preview.
- Accept/cancel workflow.
- Exception handling.

## Sprint 2G — Template Testing

- Automated test sizes.
- Preview each configuration.
- Validate each configuration.
- Save successful template behavior.

## Sprint 2H — Production Configurator

- Load intelligent template.
- Present product-specific parameters.
- Generate variant.
- Update 2D/3D.
- Export DSF/DXF/TDS outputs.

---

# 61. End-to-End Authoring Workflow

The complete Phase 2 authoring experience should look like this:

```text
PHASE 1 TEMPLATE COMPLETE
        ↓
Open “Teach Scaling”
        ↓
TruFold reads Product Contract + Topology
        ↓
Product dimensions appear automatically
        ↓
Engine identifies candidate relationships
        ↓
User selects first important parameter
        ↓
Change value
        ↓
2D + 3D morph preview
        ↓
Affected regions highlight
        ↓
Protected features remain stable
        ↓
Validation
        ↓
Accept relationship
        ↓
Repeat for remaining parameters
        ↓
Automatic test configurations
        ↓
All tests valid
        ↓
Save Intelligent Template
```

---

# 62. End-to-End User Workflow After Authoring

```text
CMS
 ↓
Product
 ↓
Variation
 ↓
Enter dimensions
 ↓
Preview
 ↓
2D + 3D morph
 ↓
Automatic validation
 ↓
Generate
```

The user no longer has to think about the template’s internal scaling behavior.

---

# 63. Definition of Done

Phase 2 should not be considered complete merely because dimensions can numerically change.

The implementation is complete only when the following are true:

### UX

- Scaling feels guided and visual.
- User does not need to understand CAD constraints.
- 2D and 3D always communicate the same change.
- Every important automatic change can be previewed before commit.
- Animations clearly show affected geometry.

### Semantics

- Product dimensions are semantic.
- Ports remain semantic.
- Bends remain semantic.
- Flanges remain semantic.
- Feature groups remain semantic.

### Geometry

- Stretch regions expand appropriately.
- Rigid regions remain intact.
- Bends remain valid.
- Flanges follow the authored structure.
- Flat pattern remains coherent.
- Folded 3D remains coherent.

### Manufacturing

- Coupler features remain protected.
- Perforation patterns remain valid.
- Feature clearances are checked.
- Invalid results cannot be committed.

### Reusability

- Scaling relationships are saved in DSF.
- A trained template can generate multiple product variations.
- The template survives application reload.
- The scaling behavior is deterministic.

---

# 64. Signature TruFold Experience

The final interaction should feel like this:

> **“I changed the product size, and TruFold showed me exactly how the physical product changes before I committed it.”**

That is the central UX goal for Phase 2.

The sophisticated dependency system should remain underneath the experience, while the visible product remains simple, visual, animated, manufacturing-aware, and easy enough for a user who does not understand parametric CAD.

---

# 65. Implementation Guardrails

Do not regress the normal DXF workflow.

Do not require CMS features for ordinary DXFs.

Do not replace user-authored flange definition with automatic flange generation.

Do not rely on global geometric scale factors.

Do not expose the dependency graph as the primary UI.

Do not silently create ambiguous relationships.

Do not commit unvalidated geometry.

Do not let protected manufacturing features deform with surrounding geometry unless the product rule explicitly permits it.

Do not use raw DXF line indexes as the permanent identity of semantic CMS elements.

Do not separate the 2D and 3D scaling engines; both must reflect the same semantic template state.

---

# 66. Final Architecture Vision

The full CMS system should ultimately behave as a chain of increasingly intelligent representations:

```text
PRODUCT CONTRACT
      ↓
FLAT GEOMETRY UNDERSTANDING
      ↓
USER-CONFIRMED BEND STRUCTURE
      ↓
USER-CONFIRMED FLANGE STRUCTURE
      ↓
FOLDED 3D TOPOLOGY
      ↓
PHYSICAL OPENING DISCOVERY
      ↓
PORT MATCHING
      ↓
FEATURE SEMANTICS
      ↓
TEMPLATE SCALING INTELLIGENCE
      ↓
LIVE 2D + 3D MORPH PREVIEW
      ↓
AUTOMATIC VALIDATION
      ↓
REUSABLE INTELLIGENT TEMPLATE
      ↓
ONE-CLICK CMS PRODUCT GENERATION
```

Phase 2 should therefore be implemented as an extension of the Phase 1 semantic model, not as a separate generic CAD scaling module.
