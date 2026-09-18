# TruFold Studio — Automatic Guided UX
## Slow, Visual, Human-Friendly CMS Template Authoring

## Purpose

This walkthrough defines the UX and implementation behavior for TruFold Studio's CMS template-authoring process.

The goal is **not** to create an expert/manual mode.

The goal is to make the CMS authoring workflow feel like an intelligent system that performs the engineering work automatically while deliberately slowing the process down enough for the user to understand what TruFold has discovered and implemented.

The user should not be required to understand the internal CAD operations, topology graph, DSF structure, bend calculations, or dependency system.

The user provides:

1. CMS/product intent.
2. Basic port dimensions where required.
3. Any information that the application genuinely cannot determine automatically.
4. Simple confirmations when TruFold needs human verification.

TruFold then performs the technical work and visually explains each successful result.

---

# 1. Core UX Philosophy

The experience should feel like:

> **Tell TruFold what the product is → TruFold studies the drawing → TruFold folds the model → TruFold discovers the structure → TruFold implements one item at a time → TruFold shows the user exactly what it learned.**

Do not make the experience feel like a checklist where the user manually performs CAD operations.

Do not expose unnecessary technical choices.

Do not make the user repeatedly select tools.

Do not ask the user to identify geometry that can already be derived confidently from the DSF and folded 3D model.

The application should behave like a **visual engineering assistant**.

---

# 2. No Expert Mode

Do **not** implement an Expert / Manual / Advanced authoring personality as part of this workflow.

There should be one primary CMS authoring experience:

> **Automatic Guided Mode**

The system controls the sequence.

The system activates the required tools internally.

The system identifies candidates automatically.

The system applies high-confidence operations automatically.

The system asks the user for confirmation only when required.

The system can slow down between operations so that the user can see exactly what happened.

The user should never need to understand or manually orchestrate the underlying CAD operations.

---

# 3. The Fundamental Architecture

Use the existing TruFold capabilities as much as possible.

```text
DXF
 │
 ├────────────── clean 2D geometry
 │
 ▼
DSF
 │
 └────────────── bend information
 │
 ▼
Existing Sheet-Metal / Bend Engine
 │
 ▼
Existing Folded 3D Model
 │
 ▼
3D Structural Analysis
 │
 ├── faces
 ├── edges
 ├── bends
 ├── boundaries
 ├── openings
 └── topology
 │
 ▼
CMS Product / Variation Contract
 │
 ▼
Automatic Feature Discovery
 │
 ├── physical ports
 ├── bend features
 ├── flange features
 ├── coupler-hole groups
 └── other semantic entities
 │
 ▼
Semantic Template
 │
 ▼
Parameter / Dependency Graph
 │
 ▼
Interactive Scaling
 │
 ├── 2D update
 └── 3D update
```

The existing 3D engine should remain the structural source of truth wherever possible.

Do not build a second independent folding or bend-calculation system solely for CMS authoring.

---

# 4. The Most Important UX Principle: Automatic, But Observable

The system should not complete the entire template instantly and then show the final result.

Instead, once the required information is available, TruFold should execute the workflow in deliberate stages.

For each stage:

```text
Prepare
   ↓
Show intended area
   ↓
Perform operation automatically
   ↓
Update 2D
   ↓
Update / refold 3D
   ↓
Animate successful result
   ↓
Mark step complete
   ↓
Pause briefly for comprehension
   ↓
Continue automatically
```

The user should be able to visually follow the transformation.

This is not simply animation for decoration. The animation is the application's explanation of what it has understood.

---

# 5. CMS Entry Flow

When the user opens a DXF, show the existing DXF Inspector prompt:

> **Is this a CMS Part Drawing?**

Options:

```text
[ Yes — Start CMS Setup ]
[ No — Open Normally ]
```

If **No**:

- Remain in normal DXF editing mode.
- Do not show CMS workflow UI.
- Do not create CMS semantic entities.

If **Yes**:

Start the automatic CMS authoring flow.

---

# 6. Product Intent First

The user should first tell TruFold what the drawing represents.

```text
Category
   ↓
Product Type
   ↓
Variation
```

Example:

```text
Category: Cable Tray Fittings
Product Type: Bend
Variation: 45° Bend
```

Once the variation is selected, the application should understand the expected product topology and feature requirements.

The application should not ask the user to manually determine these structural requirements.

---

# 7. Dynamic Product Form

After variation selection, display a clean dynamic form generated from the product variation contract.

The form should contain only information that the user needs to provide.

Example for a 45° Bend:

```text
45° BEND

Physical Ports

┌─────────────────────────────┐
│ Port 1                      │
│ Width      [ 300 ] mm       │
│ Height     [ 150 ] mm       │
└─────────────────────────────┘

┌─────────────────────────────┐
│ Port 2                      │
│ Width      [ 300 ] mm       │
│ Height     [ 150 ] mm       │
└─────────────────────────────┘
```

Do not force inlet/outlet roles at this stage.

Physical port identity and semantic flow role are separate concepts.

For products where a semantic role is useful, TruFold may suggest one later based on product rules and geometry.

Examples:

- Bend/riser: either physical end may be an inlet or outlet.
- Equal Tee: the three physical ports can be identified without assuming which is inlet.
- Equal Cross: four physical ports can be identified without assuming flow direction.
- Unequal Tee/Cross: the largest-width port can be suggested as the main/inlet candidate, while other ports can be suggested as branches/outlets.

These role suggestions must remain separate from physical port detection.

---

# 8. Introduce the User to the Process

When the user starts the automatic process, do not immediately change many things silently.

Show a short transition card:

> **Let's build this template together.**
>
> TruFold will now study your drawing, fold the model, identify its openings, and build the CMS structure step by step.
>
> **Nothing will be changed without being shown to you.**

Button:

```text
[ Start Analysis → ]
```

After this point the application controls the sequence.

---

# 9. Automatic Analysis Stage

The first stage should be an animated analysis sequence.

Example:

```text
ANALYZING 45° BEND

✓ Reading DXF geometry
✓ Reading DSF bend information
● Folding 3D model...
○ Detecting openings
○ Measuring ports
○ Matching expected dimensions
```

The current operation should be visibly active.

Avoid fake long loading times. The animation should represent actual work where possible and only add a short comprehension pause where needed.

---

# 10. Automatic 3D Folded-Model Reveal

Once the existing sheet-metal engine produces a valid folded model, automatically present the folded result.

Recommended sequence:

1. Transition from flat 2D emphasis to 3D.
2. Slowly rotate the model to a useful inspection angle.
3. Fit the model to the viewport.
4. Highlight candidate openings.
5. Measure each opening.
6. Match candidates against the user's entered dimensions and product variation.

Example message:

> **I found 2 physical openings.**

Then:

```text
PORT 1    ✓ 300 × 150 mm
PORT 2    ✓ 300 × 150 mm
```

The application should visually point to each opening in the 3D model.

---

# 11. Automatic Port Discovery

Ports should be discovered from the folded 3D structure, not from a simplistic bend-count rule.

For example:

```text
45° Bend

2 physical ports
3 bend lines
2 flange lines
```

The three bends are structural features that produce the folded object.

The two ports are physical openings discovered from the resulting topology.

The system must not assume:

```text
1 port = 1 bend
1 port = 1 flange
```

Instead:

```text
DSF bends
   ↓
Folded 3D structure
   ↓
Open boundaries / openings
   ↓
Physical ports
```

---

# 12. Port Detection Animation

When TruFold discovers a port, use a short visual reveal.

Recommended behavior:

```text
3D model
   ↓
Opening edge begins to glow
   ↓
Glow travels around the opening
   ↓
Opening softly pulses 2–3 times
   ↓
Dimension label fades in
   ↓
Port badge appears
   ↓
Port becomes marked as complete
```

Example:

```text
        ┌─────────────┐
        │   PORT 1    │
        │ 300 × 150   │
        └─────────────┘
              ↑
        highlighted opening
```

Keep the animation short and professional.

Avoid excessive effects that make the CAD model difficult to inspect.

---

# 13. Simultaneous 2D Explanation

The same successful discovery must immediately be reflected on the 2D sketch.

Example:

```text
3D:
Port 1 opening glows and pulses.

2D:
The corresponding source region / edges glow and pulse.
```

The user should be able to see:

> **“This area of my flat drawing became that opening in the folded product.”**

This 2D ↔ 3D correspondence is a core UX feature.

---

# 14. Dual-Viewport Semantic Highlighting

Every important successful operation should have synchronized visual feedback.

When an item is highlighted in 3D:

- Highlight the corresponding 2D source geometry.
- Show a small matching label or badge.

When the application is explaining a 2D feature:

- Highlight the corresponding folded face, edge, bend, or opening in 3D.

Use a consistent identity system:

```text
P1 ↔ P1
B1 ↔ B1
B2 ↔ B2
F1 ↔ F1
C1 ↔ C1
```

The user should never wonder which 3D feature corresponds to the 2D feature being discussed.

---

# 15. Automatic Bend Implementation

Once ports are known and the variation contract says that bend features are required, TruFold should determine whether the DSF already contains sufficient bend information.

If the required bend information already exists:

```text
✓ Bend data found in DSF
```

Do not ask the user to redraw it.

If a bend still genuinely needs user input, enter a focused guided interaction.

The application must automatically activate the Bend Line tool internally.

The user should see:

> **Next: Bend Feature 2**
>
> I need the bend separating these two structural regions.

Then the expected candidate region is highlighted in both views.

If the user accepts it, the application immediately processes it and performs the success animation.

If the geometry itself can be derived or a suitable candidate can be identified automatically, perform the operation without requiring a manual click.

---

# 16. Do Not Use Port-by-Port Ownership for Structural Features

A product may have a different number of physical ports and bend/flange features.

For example:

```text
45° Bend
2 ports
3 bend lines
2 flange lines
```

Therefore the workflow must be variation-driven.

Correct model:

```text
45° Bend
 ├── P1
 ├── P2
 ├── B1
 ├── B2
 ├── B3
 ├── F1
 └── F2
```

Not:

```text
P1
 ├── B1
 └── F1

P2
 ├── B2
 └── F2
```

Relationships may connect ports to structural features, but ports do not own those features by default.

---

# 17. Bend Success Animation

After a bend feature is successfully created or recognized:

### 3D

- Refresh the folded model.
- Highlight the newly relevant bend/face transition.
- Use a soft pulse traveling across the bend.
- Briefly show the bend badge:

```text
✓ BEND 2
```

### 2D

- Highlight the corresponding bend line.
- Animate a short glow along the line.
- Keep the line highlighted briefly.

Then mark it complete:

```text
✓ Bend 2 complete
```

The application then continues to the next feature.

---

# 18. Automatic Flange Implementation

The same concept applies to flange features.

Do not ask:

> “Add flange line to Port 1.”

unless that relationship has actually been established for the particular variation.

Instead use:

> **Next: Flange Feature 1**

The application should derive or suggest the relevant flange region from the folded topology and variation rules.

After successful implementation:

### 3D

- Highlight the flange face.
- Pulse the face once or twice.
- Show its label.

### 2D

- Highlight the corresponding flange line/region.
- Show a matching badge.

Then:

```text
✓ Flange 1 complete
```

---

# 19. Automatic Coupler-Hole Recognition

Coupler holes should be treated as a separate semantic class from normal perforations.

For example:

```text
COUPLER_HOLE
PERFORATION_HOLE
OTHER_HOLE
```

When the system finds a likely coupler group:

```text
3D:
Connection region glows.

2D:
Coupler hole group pulses.

HUD:
✓ Coupler group identified
```

If the pattern can be confidently recognized, accept automatically.

If ambiguous:

> **I found two possible hole groups. Which one belongs to the coupler connection?**

Show the candidates directly on the geometry.

Do not ask the user to manually activate a selection tool first.

---

# 20. Automatic Completion vs Confirmation

Use confidence-based behavior.

### High confidence

Perform automatically.

```text
✓ Port detected
✓ Bend detected
✓ Flange detected
✓ Coupler pattern detected
```

### Medium confidence

Show the proposed result and ask for a simple confirmation.

```text
I believe this is Port 2.

[ Yes, that's correct ]
```

### Low confidence

Ask the user to choose between a small number of visually highlighted candidates.

Never ask the user to manually reproduce the entire process.

---

# 21. The User Should Never Be Lost

At every point there should be exactly one obvious current action.

The UI should always communicate:

```text
WHERE AM I?
WHAT DID TRUFOLD JUST DO?
WHAT IS TRUFOLD DOING NOW?
WHAT WILL HAPPEN NEXT?
```

Example:

> **Step 4 — Identifying Bend Features**
>
> ✓ 3D model folded successfully
> ✓ 2 physical ports detected
> ● Finding bend feature 2 of 3
> ○ Finding bend feature 3
> ○ Flange features
> ○ Coupler holes

The user should not need to interpret technical debug output.

---

# 22. Slow Down the Automatic Process Intentionally

The workflow should support a configurable comprehension pace internally, with a sensible default.

After important successful operations, briefly pause before moving on.

Recommended sequence:

```text
Operation finishes
   ↓
2D + 3D refresh
   ↓
Success animation
   ↓
Result remains visibly highlighted
   ↓
Short comprehension pause
   ↓
Next operation begins
```

Do not make the process artificially slow if a computational operation is already expensive.

The goal is **understandable automation**, not waiting.

---

# 23. “What TruFold Learned” Should Build Continuously

Do not wait until the end to show the learned model.

Maintain a live compact summary.

Example:

```text
WHAT TRUFOLD LEARNED

✓ 45° Bend
✓ 2 Physical Ports
✓ Port 1: 300 × 150
✓ Port 2: 300 × 150
✓ 3 Bend Features
✓ 2 Flange Features
✓ Coupler Group: Detected
✓ 3D Topology: Valid
```

Each new line should appear when that item has been successfully established.

This creates a sense of progress and trust.

---

# 24. Main HUD Design

Keep the main HUD visually simple.

Recommended structure:

```text
┌──────────────────────────────────────────────────────────┐
│  BUILDING CMS TEMPLATE                    4 / 7          │
│                                                          │
│  ✓ Product identified                                    │
│  ✓ Ports discovered                                      │
│  ● Bend features                                         │
│  ○ Flange features                                       │
│  ○ Coupler holes                                         │
│  ○ Review                                                 │
└──────────────────────────────────────────────────────────┘
```

Under the title:

> **Finding Bend Feature 2 of 3**

Then a short explanation:

> TruFold is matching the folded 3D structure with your 45° Bend template.

Do not overwhelm the screen with technical details.

---

# 25. Visual Language

Use animation as a language with consistent meanings.

### Suggested states

```text
Suggested       = soft pulse / dashed glow
Processing      = moving highlight
Successfully done = brief bright pulse + check
Needs review    = warm attention pulse
Conflict        = restrained warning highlight
```

Do not rely solely on color. Include icons, labels, motion, and state text so the meaning is clear.

---

# 26. 3D Animation Principles

The 3D model should never rotate or move excessively.

Use controlled camera behavior:

1. Fit model.
2. Rotate only when necessary to reveal a feature.
3. Zoom toward the active region.
4. Highlight the feature.
5. Return gently toward the normal inspection view.

When a port is found:

- camera may slightly orient toward the opening;
- opening boundary glows;
- opening pulses;
- dimension annotation appears;
- port badge appears.

When a bend is found:

- adjacent faces receive a synchronized highlight;
- bend edge pulses;
- 2D bend line receives the same semantic emphasis.

When a flange is found:

- flange face briefly illuminates;
- related bend remains subtly visible.

The animation must never obscure the engineering geometry.

---

# 27. 2D Animation Principles

The flat DXF remains readable and accurate.

Do not permanently recolor the DXF geometry merely to communicate the workflow.

Use temporary overlays:

```text
Glow
Pulse
Outline
Badge
Leader line
Dimension tag
Focus halo
```

After the success animation, the permanent semantic state should remain visible with a subtle stable indicator.

---

# 28. The User Should See Cause and Effect

Whenever possible, show:

```text
2D source feature
       ↓
fold / calculation
       ↓
3D result
```

Example:

> **Bend 2 recognized**

2D bend line glows → 3D model updates → folded transition glows.

This teaches the user what TruFold is doing without requiring a tutorial.

---

# 29. Automatic Port Role Suggestions

Physical port identification remains independent from flow role assignment.

For products where flow roles are useful, show a suggestion after physical ports are discovered.

Example — Unequal Tee:

```text
3 physical ports detected.

Port 1: 300 × 150
Port 2: 200 × 100
Port 3: 200 × 100

Suggested:
Port 1 → Main / Inlet candidate
Port 2 → Branch candidate
Port 3 → Branch / Outlet candidate
```

Explain the reason simply:

> Port 1 is the largest-width opening.

The user can accept the suggestion or leave it unassigned.

Do not use this heuristic as proof of actual flow direction.

---

# 30. No Unnecessary Manual Selection

The automatic system should always try this order:

```text
1. Existing DSF information
2. Existing 3D structural calculations
3. Product / variation rules
4. Geometry inference
5. User confirmation
6. User selection only as final fallback
```

This order is important.

The user should not be asked to manually identify something that the application already knows with high confidence.

---

# 31. Exceptions Become the User's Work

The user's attention should be reserved for ambiguity.

Good experience:

```text
✓ 2 ports automatically detected
✓ 3 bends automatically detected
✓ 2 flanges automatically detected
✓ Coupler pattern automatically detected

⚠ One ambiguous region

[ Review Ambiguous Region ]
```

Bad experience:

```text
Click Port 1
Click Bend 1
Click Flange 1
Click Port 2
Click Bend 2
...
```

The first experience feels intelligent.

The second feels like a conventional CAD wizard.

---

# 32. Guided Interaction Fallback

When the application cannot determine something automatically, enter a focused mini-step.

Example:

> **I found two possible Port 2 openings.**
>
> They are highlighted in the 2D and 3D views.
>
> **Which one matches the 200 × 100 mm port?**
>
> [ Candidate A ] [ Candidate B ]

Once the user selects one:

1. Save the semantic result.
2. Update both 2D and 3D.
3. Show success animation.
4. Continue automatically.

The fallback should feel like an exception, not the main workflow.

---

# 33. Safe Checkpoints

Before significant semantic changes, create a workflow checkpoint.

Examples:

```text
Checkpoint 1 — Product Intent
Checkpoint 2 — Port Discovery
Checkpoint 3 — Bend Structure
Checkpoint 4 — Flange Structure
Checkpoint 5 — Coupler Groups
Checkpoint 6 — Template Ready
```

The user-facing experience should not expose technical snapshots unless necessary.

Provide a simple:

> **Undo last TruFold action**

or:

> **Undo this step**

The system should restore both the document state and the authoring workflow state.

---

# 34. Interactive Scaling as a Visual Demonstration

Only after the semantic structure is valid should the workflow show scaling.

Instead of exposing a complicated parameter editor, show a simple demonstration:

```text
PORT WIDTH
300 mm ───────●──────── 500 mm
```

As the value changes:

```text
Parameter change
      ↓
2D geometry morphs
      ↓
3D model regenerates
      ↓
Relevant feature highlights
      ↓
Result dimensions update
```

Show small status confirmations:

```text
✓ Port opening updated
✓ Bend relationships preserved
✓ Flange relationship preserved
✓ Coupler positions updated
✓ 3D model regenerated
```

This gives the user confidence that the template is genuinely intelligent.

---

# 35. Success Animation for Scaling

When the scaling preview succeeds:

### 2D

- Changed region softly morphs.
- Updated boundary briefly pulses.
- Dimension label updates.

### 3D

- Related opening smoothly changes size.
- Model remains stable.
- Updated port briefly glows.

Then show:

> **Scaling behavior verified ✓**

---

# 36. Final Review Should Be a Story of What Happened

At the end, do not merely show a technical checklist.

Show a compact visual narrative:

```text
TRUFOLD UNDERSTOOD THIS PART

45° Bend

2 Physical Ports
3 Bend Features
2 Flange Features
1 Coupler Group

3D topology valid ✓
Scaling behavior verified ✓
```

The 2D and 3D previews should remain visible.

Each learned item should be clickable to highlight its corresponding geometry.

---

# 37. Final Readiness State

Use a clear status:

```text
TEMPLATE READY ✓
```

or:

```text
TEMPLATE NEEDS 1 REVIEW
```

For unresolved issues, provide a direct action:

> **Port 2 dimension mismatch**
>
> Expected: 200 × 100 mm
> Detected: 200 × 120 mm
>
> [ Review Port 2 ]

The user should never have to search for the cause of a failure.

---

# 38. Save Behavior

Maintain the established save rules:

- Base DXF remains clean in memory.
- Bend and CMS semantic information are stored in DSF.
- Ctrl + S saves/overwrites the DSF.
- DXF export happens only when explicitly requested.

The final save should say:

> **CMS template saved successfully**
>
> Your intelligent structure is now stored in the DSF.

---

# 39. State Machine

The implementation should model the UX as a state machine.

```text
DXF_INSPECTION
      ↓
PRODUCT_INTENT
      ↓
PORT_DIMENSIONS
      ↓
ANALYZING
      ↓
FOLDING_3D
      ↓
DISCOVERING_PORTS
      ↓
DISCOVERING_STRUCTURAL_FEATURES
      ↓
IMPLEMENTING_BENDS
      ↓
IMPLEMENTING_FLANGES
      ↓
CLASSIFYING_COUPLER_HOLES
      ↓
VALIDATING
      ↓
SCALING_PREVIEW
      ↓
REVIEW_LEARNED
      ↓
TEMPLATE_READY
```

For each state define:

- what the system is doing;
- what the user sees;
- what 2D animation is shown;
- what 3D animation is shown;
- what constitutes success;
- what causes a retry;
- what causes user confirmation;
- what gets persisted into DSF.

---

# 40. Automatic Progression Rules

The workflow should automatically progress when:

1. The current operation has successfully completed.
2. Required semantic data has been persisted.
3. 2D and 3D representations are synchronized.
4. Validation for the current state passes.

Do not require the user to repeatedly press `Accept & Continue` after every automatic operation.

Use manual confirmation only when there is genuine uncertainty.

For major milestones, the application can pause and show:

> **Port structure complete ✓**

then automatically continue after a short comprehension pause.

---

# 41. Agent Implementation Guidance

Before implementing a new subsystem, inspect existing code for:

- DXF importer/exporter
- DSF serializer/deserializer
- Bend line model
- Bend calculations
- Existing 3D simulation
- Folded face / edge topology
- Existing selection and hit-testing
- Existing highlighting / overlay infrastructure
- Hole detection
- Coupler-hole handling
- Perforation pattern handling
- Template parameter system
- Constraints / dependencies
- TopologicalZoneMorpher
- Undo/redo and document snapshots
- Existing validation services

Reuse existing infrastructure where possible.

Do not create parallel implementations of bend mathematics, folding, or selection unless the existing implementation genuinely lacks the required capability.

---

# 42. Recommended Internal Data Model

A port should be a physical semantic entity.

```dart
CmsPhysicalPort {
  String portId;
  int index;
  double? width;
  double? height;
  double? flange;
  PortDetectionSource source;
  double confidence;
  String? faceId;
  List<String> boundaryEdgeIds;
  PortRole? role;
  PortRole? suggestedRole;
  String? roleSource;
  String? suggestionReason;
}
```

A bend should remain independently identifiable.

```dart
CmsBendFeature {
  String bendId;
  List<String> edgeIds;
  List<String> adjacentFaceIds;
  double angle;
  String source;
}
```

A flange should remain independently identifiable.

```dart
CmsFlangeFeature {
  String flangeId;
  String? hostFaceId;
  String? parentBendId;
  List<String> boundaryEdgeIds;
}
```

This prevents the product model from assuming one-to-one ownership between ports and structural features.

---

# 43. Semantic Relationship Graph

Use relationships such as:

```text
Port P1
   │
   ├── touches / opens at Face F1
   └── related to Bend B1

Bend B1
   ├── connects Face F1
   └── connects Face F2

Flange F1
   ├── hosted by Face F2
   └── derived from Bend B1
```

The exact relationships should be based on the existing CAD topology.

The graph becomes the foundation for intelligent scaling.

---

# 44. Important Engineering Rule

Do not infer a physical port merely because there is a particular number of bend lines.

Do not infer a bend because there is a particular number of ports.

Do not infer an inlet/outlet role simply from port numbering.

Use:

```text
DSF
+
3D folded topology
+
product variation contract
+
geometry measurements
+
optional user confirmation
```

to derive the semantic model.

---

# 45. Example: 45° Bend

Expected product contract:

```text
Physical ports: 2
Bend features: 3
Flange features: 2
```

Automatic process:

```text
User selects 45° Bend
        ↓
User enters Port 1 / Port 2 W × H
        ↓
TruFold reads DSF
        ↓
3D model folds
        ↓
TruFold detects 2 openings
        ↓
2 ports highlighted in 3D
        ↓
2 corresponding regions highlighted in 2D
        ↓
Port dimensions matched
        ↓
3 bend features identified
        ↓
Each bend visually highlighted as it is established
        ↓
2 flange features identified
        ↓
Each flange visually highlighted as it is established
        ↓
Coupler holes classified
        ↓
Validation
        ↓
Scaling preview
        ↓
Ready
```

The user should feel that TruFold **assembled the understanding of the part in front of them**.

---

# 46. Example: Equal Tee

Expected:

```text
3 physical ports
```

The system should discover the three openings from the folded topology.

Do not automatically designate a particular port as inlet unless the product workflow explicitly requires a role.

The animation should reveal the ports one at a time:

```text
Port 1 ✓
Port 2 ✓
Port 3 ✓
```

The user sees all three become visually understood in both 2D and 3D.

---

# 47. Example: Unequal Tee

Expected:

```text
3 physical ports
```

After dimensions are measured:

```text
P1 = 300 × 150
P2 = 200 × 100
P3 = 200 × 100
```

TruFold can suggest:

```text
P1 → Main / Inlet candidate
P2 → Branch candidate
P3 → Branch / Outlet candidate
```

Show the reason and confidence.

Never present the inference as geometry-proven flow direction.

---

# 48. What Makes This UX Feel Different

The following characteristics are mandatory design goals:

### A. The user gives intent, not instructions

The user says what the part is.

TruFold determines how to analyze it.

### B. The system shows its reasoning visually

Every important discovery is animated in 2D and 3D.

### C. Automation is deliberately observable

The user sees the model becoming understood step by step.

### D. Manual interaction is the exception

Only ambiguity requires user action.

### E. Every successful action has a visible result

Nothing should happen silently.

### F. The application always knows what happens next

The user never needs to navigate the workflow manually.

---

# 49. Anti-Patterns to Avoid

Do not implement:

```text
❌ One bend per port
❌ One flange per port
❌ Port 1 automatically means inlet
❌ Repeated Accept & Continue for automatic operations
❌ Manual tool selection when the workflow knows the tool required
❌ Silent geometry changes
❌ Static instructions without canvas feedback
❌ 2D changes without matching 3D feedback
❌ 3D changes without matching 2D feedback
❌ Instant completion with no explanation
❌ Long wizard sequences where most steps can be automated
❌ Expert-mode complexity exposed to the user
```

---

# 50. Acceptance Criteria

The implementation is successful only when the following behavior is observable.

### Product setup

- User opens DXF.
- DXF Inspector asks whether this is a CMS Part Drawing.
- CMS mode collects category, product type and variation.
- Dynamic physical-port fields are generated from variation rules.
- User provides required dimensions.

### Automatic analysis

- TruFold reads DXF + DSF.
- Existing bend engine is reused.
- Existing 3D folding engine produces the model.
- Application analyzes folded topology.
- Physical ports are discovered from openings/candidate boundaries.
- Port dimensions are measured from the folded model.
- Measurements are matched against the user's entered dimensions.

### Structural authoring

- Bend count is variation-driven.
- Flange count is variation-driven.
- Ports do not own bends/flanges by default.
- Coupler holes are a separate semantic class.

### UX behavior

- The automatic workflow controls the sequence.
- Required tools are activated internally.
- 3D and 2D regions are highlighted during every important operation.
- Successful operations produce a short glow/pulse/highlight animation.
- The successful feature remains subtly marked afterward.
- The workflow progresses automatically after comprehension pauses.
- Manual input occurs only when automatic analysis is ambiguous.
- User can see what TruFold has learned throughout the process.

### Scaling

- Semantic relationships are persisted.
- Scaling modifies the correct dependent geometry.
- 2D and 3D update together.
- The resulting product can be validated before commit.

### Persistence

- CMS semantic information persists in DSF.
- Clean DXF remains unchanged in memory.
- Existing DSF bend information remains compatible.
- Save/reopen preserves the learned semantic template.

---

# 51. Agent Completion Checklist

Before declaring Sprint implementation complete, verify:

```text
[ ] Existing DSF bend data is reused.
[ ] Existing 3D folding is reused.
[ ] Folded topology can expose candidate openings.
[ ] Physical ports are discovered independently of bend count.
[ ] Product variation defines expected topology.
[ ] Physical port roles are separate from flow roles.
[ ] Bend features are independent semantic entities.
[ ] Flange features are independent semantic entities.
[ ] Coupler holes are separate from normal perforations.
[ ] Automatic confidence is implemented.
[ ] Ambiguous cases have a simple guided fallback.
[ ] The user does not need an Expert mode.
[ ] The workflow controls the sequence automatically.
[ ] Important operations animate in 3D.
[ ] Important operations animate in 2D.
[ ] 2D and 3D highlighting remain synchronized.
[ ] Each successful operation has a visible completion state.
[ ] The process deliberately pauses briefly so users can understand changes.
[ ] The workflow can progress automatically.
[ ] Scaling uses the learned semantic/dependency graph.
[ ] 2D and 3D scaling remain synchronized.
[ ] DSF persistence stores the resulting intelligent template.
```

---

# Final UX Principle

The final experience should feel like this:

> **“I told TruFold what this drawing is. TruFold understood the drawing, folded it, found the ports, understood the bends and flanges, showed me what it discovered, and built the intelligent template for me.”**

The user's involvement should provide **intent, confirmation, and confidence** — not repetitive CAD labor.

That is the intended personality of the CMS authoring experience.
