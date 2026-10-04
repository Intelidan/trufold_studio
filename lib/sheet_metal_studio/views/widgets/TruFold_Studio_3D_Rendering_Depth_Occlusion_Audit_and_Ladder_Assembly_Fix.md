# TruFold Studio — 3D Rendering, Depth & Occlusion Audit
## Foundation Fix Before Ladder Assembly Expansion

### Purpose

This implementation plan addresses a likely **3D rendering/depth-visibility issue** observed both in normal folded sheet-metal models and in the new ladder assembly.

The ladder screenshot appears to contain an assembly-geometry issue as well as a possible renderer-level occlusion problem. These must be treated as two separate layers:

```text
3D Problem
├── A. Assembly Geometry
│     └── Rung / side-rail mating and positioning
│
└── B. Rendering / Visibility
      └── Depth, occlusion, normals, z-fighting, etc.
```

The renderer problem should be audited before the ladder accessory assembly system is expanded.

---

# 1. Why This Audit Is Required

In normal folded 3D models, portions of a surface that should be obstructed by a front surface sometimes become visible when the camera is rotated.

The ladder assembly makes the symptom much more obvious because many independent parts are rendered together:

```text
Left Side Rail
Right Side Rail
Rung 1
Rung 2
Rung 3
...
```

However, the underlying rendering problem may already exist in ordinary single-product folded models.

Therefore:

> **Do not assume that all visible-through geometry in the ladder is caused by incorrect ladder geometry.**

The rendering pipeline must first be verified.

---

# 2. Separate the Two Problems

## A. Assembly Geometry Problem

The ladder screenshot suggests that some rungs may extend too far through or beyond the side rails.

This should be investigated independently as an assembly-definition issue.

Likely causes include:

- rung length calculated from nominal overall width instead of rail mating faces;
- side rails and rungs using different coordinate frames;
- incorrect mirrored rail transforms;
- incorrect inside/outside rail orientation;
- pass-through welding projection being applied without matching rail openings.

This is a model-generation problem.

---

## B. Rendering / Occlusion Problem

The application's ordinary folded 3D model can sometimes show a portion of a rear/obstructed face through a front opaque face during camera rotation.

This suggests a possible issue in:

- depth testing,
- depth-buffer behavior,
- face ordering,
- z-fighting,
- face normals,
- back-face culling,
- or camera/projection setup.

This is a rendering-pipeline problem.

---

# 3. Primary Rendering Requirement

For opaque sheet-metal geometry:

```text
Depth Test   = ENABLED
Depth Write  = ENABLED
```

The visible surface must be determined by actual camera-space depth.

Conceptually:

```text
Camera
  ↓
Projection
  ↓
Rasterization
  ↓
Depth Comparison
  ↓
Nearest Opaque Surface Wins
```

The renderer must not rely on approximate whole-face painter sorting as the primary occlusion mechanism.

Depth sorting may still be used for special cases, but opaque sheet-metal surfaces require proper depth-buffer testing.

---

# 4. Ordinary Folded Model Test — First Priority

Before modifying ladder geometry, select a normal folded DSF containing overlapping/occluding walls.

Rotate the model through:

```text
Front
45°
90°
135°
180°
```

and verify:

```text
Front opaque face
    ↓
Rear face remains hidden
```

The test must be repeated while continuously rotating the camera.

Acceptance:

> A rear surface must never become visible through a front opaque surface solely because the camera angle changes.

This is the most important test because it determines whether the issue is renderer-wide.

---

# 5. Multi-Component Assembly Test

After the ordinary model passes, test simple assemblies:

```text
2 components
5 components
10 components
20+ components
```

Verify that all components share the same world-space depth system.

Expected:

```text
Component A
Component B
Component C
...
        ↓
Common World Space
        ↓
Common Camera Space
        ↓
Common Depth Buffer
```

The renderer must not use an independent visibility/depth mechanism for ladder assemblies.

---

# 6. Z-Fighting Investigation

Check for nearly coincident faces.

Typical causes:

```text
Face A
────────────

Face B
────────────
```

with extremely small separation.

Investigate:

- duplicate faces;
- accidental coincident faces;
- front/back sheet surfaces generated at nearly identical positions;
- overlapping bend construction faces;
- assembly parts positioned almost exactly on one another.

Symptoms to distinguish:

### Occlusion error

A rear face is visible through a front face.

### Z-fighting

Two nearly coincident faces flicker, alternate visibility, or produce unstable surface patterns while the camera moves.

Do not solve actual duplicate geometry problems purely through renderer settings.

---

# 7. Face Normal / Back-Face Audit

Inspect:

- polygon winding;
- face normals;
- front/back orientation;
- back-face culling;
- double-sided material behavior.

A face that disappears or changes visibility when the camera rotates may have incorrect winding or normal orientation.

For sheet-metal folded faces, the normal convention must remain consistent through:

```text
2D DSF
   ↓
Fold generation
   ↓
3D face construction
   ↓
Assembly transform
```

Mirrored side rails must also preserve correct orientation.

---

# 8. Camera and Projection Audit

Verify that all geometry uses the same:

```text
World Transform
View Transform
Projection Transform
Depth Range
Near Plane
Far Plane
```

Check particularly:

- extremely small near plane;
- excessively large far plane;
- poor depth-buffer precision caused by an unnecessarily large depth range;
- inconsistent transforms between components.

A numerically unstable depth range can make otherwise correct geometry behave badly.

---

# 9. Ladder Assembly Geometry Audit

Once the renderer is verified, inspect the ladder assembly itself.

The ladder should be constructed as:

```text
Ladder Assembly
├── Left Side Rail
├── Right Side Rail
└── Rungs × N
```

The rung must not automatically have:

```text
rungLength = overallLadderWidth
```

unless that is actually the manufacturing dimension.

Instead, derive rung span from the rail mating geometry.

---

# 10. Correct Rung Span Model

For direct inside welding:

```text
Rung
    ↓
terminates at side-rail inside mating faces
```

Conceptually:

```text
Inside Face                     Inside Face
    │                               │
    │────── RUNG SPAN ─────────────│
```

For pass-through/outside welding:

```text
Rung
    ↓
passes through side-rail wall openings
    ↓
controlled projection beyond outer face
    ↓
outside weld
```

The penetration/projection must be a defined manufacturing quantity.

It must not occur accidentally because the rung was created at nominal overall width.

---

# 11. Ladder Assembly Coordinate System

Use one assembly coordinate system:

```text
LadderAssemblyFrame
│
├── LeftRail Transform
├── RightRail Transform
└── Rung Transforms
```

Recommended sequence:

```text
Create canonical side rails
Create canonical rung
        ↓
Calculate assembly positions
        ↓
Apply local component transforms
        ↓
Apply overall assembly transform
        ↓
Render
```

Avoid independently constructing components directly in world coordinates.

---

# 12. Side-Rail Mating Geometry

The assembly should explicitly know:

```text
leftRail.innerMatingFace
rightRail.innerMatingFace
```

and calculate:

```text
internalClearSpan =
distance(leftRail.innerMatingFace,
         rightRail.innerMatingFace)
```

Then:

### Direct weld

```text
rungSpan = internalClearSpan
```

or the project's defined welding termination allowance.

### Pass-through weld

```text
rungSpan =
internalClearSpan
+ leftPenetration
+ rightPenetration
```

where the penetration values are explicit manufacturing parameters.

---

# 13. Pass-Through Joint Must Generate Matching Rail Openings

When the pass-through method is selected:

```text
Rung
  ↓
Side Rail
  ↓
Rectangular Opening
  ↓
Rung passes through
  ↓
Outside Projection
  ↓
Outside Weld
```

The rail cutout and rung penetration must be generated from the same joint definition.

Never allow:

```text
Rung penetration = YES
Rail opening = NO
```

or:

```text
Rail opening exists
Rung does not pass through correctly
```

The joint is an assembly relationship, not two unrelated geometry modifications.

---

# 14. Joint Mode Definitions

Maintain exactly two primary manufacturing modes:

```text
DIRECT_INSIDE_WELD
PASS_THROUGH_OUTSIDE_WELD
```

The selected mode controls:

```text
Rung end condition
Rail opening generation
Rung penetration
Weld location
3D assembly representation
BOM/manufacturing metadata
```

Changing joint mode must regenerate the assembly from the canonical component definitions.

It must not incrementally modify the previous joint geometry.

---

# 15. Rendering Debug Mode

Add a temporary developer/debug option:

```text
3D Rendering Debug
```

with:

```text
[ ] Depth Test
[ ] Depth Write
[ ] Back-face Culling
[ ] Show Face Normals
[ ] Wireframe
[ ] Transparent Faces
[ ] Component IDs
[ ] Z-Fighting Diagnostics
```

Most important:

```text
Depth Test: ON / OFF
Depth Write: ON / OFF
```

This makes it possible to immediately distinguish renderer behavior from geometry problems.

---

# 16. Component ID Visualization

For assembly debugging, allow each component to display an ID:

```text
SIDE_RAIL_L
SIDE_RAIL_R
RUNG_01
RUNG_02
RUNG_03
...
```

This allows the developer to identify whether an apparent visibility error belongs to:

- the wrong component transform;
- wrong geometry;
- wrong component ordering;
- or the renderer's depth logic.

---

# 17. Diagnostic Test Cases

## Test 1 — Single Folded Body

```text
One DSF
Multiple folded faces
Opaque material
Camera rotation
```

Expected:

```text
No rear-face visibility through front opaque faces.
```

## Test 2 — Two Overlapping Components

```text
Component A
Component B
```

Expected:

```text
Correct nearest-surface visibility.
```

## Test 3 — Ladder Assembly

```text
2 rails
5–20 rungs
```

Expected:

```text
Rails occlude the appropriate portions of the rungs.
```

## Test 4 — Pass-Through Joint

Expected:

```text
Rung visible only where physically outside the rail.
```

## Test 5 — Direct Weld Joint

Expected:

```text
Rung terminates at the intended rail mating surface.
```

## Test 6 — Continuous Camera Rotation

Rotate continuously through a full 360°.

Expected:

```text
No sudden incorrect face appearance/disappearance.
```

## Test 7 — Reverse Joint Mode

```text
Direct Weld
    ↓
Pass Through
    ↓
Direct Weld
```

The final model must match a fresh Direct Weld evaluation.

---

# 18. Do Not Hide Rendering Problems with Transparency

Do not solve the issue by making sheet-metal faces semi-transparent.

Normal product mode should use opaque surfaces.

Transparency may be provided only as an explicit inspection/debug mode.

---

# 19. Do Not Use Depth Bias as the First Solution

Do not immediately add arbitrary:

```text
depth offsets
polygon offsets
manual Z shifts
```

These can hide symptoms while leaving incorrect geometry unresolved.

First determine whether the cause is:

```text
Incorrect geometry
Incorrect transforms
Duplicate geometry
Incorrect normals
Z-fighting
Depth-buffer configuration
```

Only then use a controlled numerical remedy if truly required.

---

# 20. Recommended Investigation Order

```text
STEP 1
Test ordinary folded DSF
        ↓
STEP 2
Verify depth testing / depth writing
        ↓
STEP 3
Check face normals / culling
        ↓
STEP 4
Check duplicate/coincident faces
        ↓
STEP 5
Check camera near/far depth precision
        ↓
STEP 6
Test multi-component scene
        ↓
STEP 7
Audit ladder assembly coordinate frames
        ↓
STEP 8
Audit rung span / mating geometry
        ↓
STEP 9
Audit pass-through rail openings
        ↓
STEP 10
Run full regression
```

---

# 21. Important Architecture Rule

The final system must separate:

```text
Geometry Correctness
```

from:

```text
Rendering Correctness
```

For example:

```text
Correct Rung Geometry
        +
Correct Rail Geometry
        +
Correct Transforms
        +
Correct Depth Testing
        =
Correct Ladder Rendering
```

A renderer should not be expected to correct incorrect assembly geometry.

Likewise, assembly code should not contain hacks intended to compensate for renderer occlusion problems.

---

# 22. Relationship to the Existing TruFold Architecture

Do not replace the existing:

- KinematicFoldEngine;
- canonical 2D DSF workflow;
- CMS product contracts;
- component/feature identity system.

The audit should make the 3D presentation layer more reliable while preserving the existing geometry pipeline.

The ladder assembly should remain a true assembly of reusable manufacturing components rather than being converted into one artificial folded mesh.

---

# 23. Acceptance Criteria

The work is complete when:

1. Ordinary folded DSFs have reliable opaque-surface occlusion during camera rotation.
2. Rear faces cannot become visible through front faces due solely to camera angle.
3. Z-fighting is identified and resolved where caused by duplicate/coincident geometry.
4. Face normals and winding are consistent.
5. Back-face culling behaves correctly.
6. Multi-component assemblies use the same depth-space system.
7. Ladder rungs and rails use one assembly coordinate frame.
8. Rung span is derived from actual rail mating geometry.
9. Direct-weld and pass-through-weld modes produce physically consistent geometry.
10. Pass-through mode creates corresponding rail openings.
11. Switching between joint modes is baseline-driven and reversible.
12. No renderer-specific hacks are embedded in the ladder geometry generator.

---

# 24. Final Principle

> **Do not treat the visible-through-face problem and the ladder rung/rail misalignment as one bug. Fix the 3D renderer's depth/occlusion foundation independently, then fix the ladder assembly's mating geometry. Both must be correct for the ladder system to become reliable.**
