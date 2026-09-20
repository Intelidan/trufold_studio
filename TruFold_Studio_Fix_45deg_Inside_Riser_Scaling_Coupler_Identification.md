# TruFold Studio — Fix 45° Inside Riser Scaling, Reset Dimensions & Coupler Identification

## 0. Purpose

Fix the current CMS teaching/scaling behavior for the 45° Inside Riser and establish a clean separation between:

1. **Manufacturing Definition** — user-authored bends, flanges and coupler features.
2. **Port Mapping** — automatic discovery and semantic mapping using the already-authored manufacturing structure.
3. **Template Scaling** — parameter-driven regeneration using product/scaling definitions.

This change must **not reintroduce automatic bend/flange inference**.

The user's manually authored bend and flange lines remain the manufacturing source of truth.

---

# 1. Problems to Fix

## 1.1 Width Scaling — 45° Inside Riser

Current behavior when changing width from 100 mm to 150 mm:

- cheek/prong profiles become distorted vertically and diagonally
- coupler slots become skewed/deformed
- the floor web does not expand correctly

### Root cause

`cms_scaling_controller.dart` currently routes products containing `45` through:

```dart
TopologicalZoneMorpher.morph(
  templateId: '45_deg_bend',
)
```

This incorrectly treats a 45° inside riser like a flat 45° bend.

A 45° bend's diagonal/miter morphology is not appropriate for the riser geometry.

### Required fix

Do not select scaling behavior using string matching such as:

```dart
prod.contains('45')
```

or even rely on product-name strings as the primary decision mechanism.

Use the CMS product/scaling contract to select an explicit scaling profile, for example:

```text
geometryFamily = riser
productType = inside_riser
angle = 45
scalingProfile = inside_riser_riser_web_cheek
```

Conceptually:

```text
Product Contract
      ↓
Scaling Profile
      ↓
Scaling Strategy
```

The scaling engine must therefore be able to distinguish:

```text
45° Bend
45° Inside Riser
45° Outside Riser
```

without relying on substring tests.

---

# 2. Dedicated Riser Scaling Strategy

Add dedicated scaling behavior for the inside-riser geometry.

Recommended conceptual methods:

```dart
_scaleRiserWidth2D(...)
_scaleRiserHeight2D(...)
```

These methods should operate from **authored/identified geometric zones and bend relationships**, not only raw global X/Y thresholds.

Avoid logic whose correctness depends on conditions such as:

```dart
pt.x < xB1
pt.x > xB2
pt.y > 100.0
```

unless those coordinates are derived from the baseline geometry dynamically.

Prefer stable geometry membership such as:

```text
Floor Web Zone
Left Cheek Zone
Right Cheek Zone
B1 Bend
B2 Bend
B3 Bend
Left Coupler Features
Right Coupler Features
```

This prevents scaling from becoming dependent on hard-coded baseline coordinates.

---

# 3. Width Scaling Rules

For a width change:

```text
ΔW = targetWidth - baselineWidth
```

The desired behavior is:

```text
                LEFT CHEEK        FLOOR WEB        RIGHT CHEEK
                    │                  │                 │
                    │<--- expands ---> │ <--- expands -->│
```

## 3.1 Floor web

The floor web between B1 and B2 must expand by the width delta.

For the known 100 × 100 template, the expected verification result is:

```text
Target width = 150 mm
Expected floor web width = 145.6 mm
```

Do not assume that the flat floor segment's baseline length equals the nominal product width.

The scaler must preserve the actual baseline geometry and apply the product-width delta to the appropriate structural span.

## 3.2 Left cheek

The left cheek should move rigidly outward by:

```text
-ΔW / 2
```

It must **not** be stretched or sheared.

## 3.3 Right cheek

The right cheek should move rigidly outward by:

```text
+ΔW / 2
```

It must **not** be stretched or sheared.

## 3.4 B1 and B2

B1 moves with the left side.

B2 moves with the right side.

## 3.5 B3

B3 must remain the transverse fold relationship associated with the riser structure.

Its endpoints/extent may need to update with the new web width, but the bend line itself must not be rotated into a diagonal miter geometry.

## 3.6 Coupler slots

All coupler slots attached to a cheek must undergo the same rigid transformation as the host cheek.

Their geometry must remain unchanged:

```text
Slot length = unchanged
Slot width  = unchanged
Slot shape  = unchanged
Slot angle  = unchanged relative to host cheek
```

Only their position changes.

---

# 4. Height Scaling Rules

For a height change:

```text
ΔH = targetHeight - baselineHeight
```

The correct behavior is to make the cheek sidewalls taller.

The current bug incorrectly extends the floor along Y.

## 4.1 Floor web

The floor web must remain fixed.

Do not change its length/position because of height scaling.

## 4.2 B1 and B2

B1 and B2 remain fixed in position during height scaling.

## 4.3 B3

B3 remains fixed in its base structural relationship to the floor/bend system.

## 4.4 Left cheek

Expand the left cheek outward along the actual riser-height direction by the height delta.

The transformation must preserve the cheek profile rather than simply applying a global Y scale.

## 4.5 Right cheek

Expand the right cheek outward in the corresponding opposite direction.

Again, preserve the cheek profile.

## 4.6 Coupler slots

Coupler slots must retain their geometry and move according to their host cheek's scaling rule.

Their intended relationship to the bend line / outer rim must remain intact.

---

# 5. Important Geometry Rule — Do Not Double-Transform Shared Bend Geometry

Bend-line entities and vertices shared between zones can be affected by multiple zone transforms.

The implementation must prevent double movement.

Use a clear ownership rule, for example:

```text
Face/Zone owns interior geometry.
Bend edge owns its bend relationship.
Shared vertices are resolved once from the final structural positions.
```

Do not independently transform the same vertex once as part of the cheek and again as part of the floor.

---

# 6. Reset Dimensions

Add:

```dart
resetToBaseline()
```

to `CmsScalingController`.

It must:

1. Restore all active parameters to their baseline values.
2. Restore the active slider/control to the baseline value.
3. Recompute the preview geometry.
4. Recompute/update the 3D mesh.
5. Preserve the authored manufacturing seed.
6. Preserve existing port mapping data.
7. Preserve the saved DSF baseline.

The action is a **preview reset**, not a destructive reset of authored CMS information.

---

# 7. Teach Scaling UI — Reset Dimensions

Modify:

```text
cms_teach_scaling_overlay.dart
```

Add a visible:

```text
Reset Dimensions
```

button in the scaling controls/action row.

Expected behavior:

```text
User changes dimensions
       ↓
Preview changes
       ↓
User clicks Reset Dimensions
       ↓
Baseline dimensions restored immediately
       ↓
2D + 3D preview restored
```

For the test file:

```text
45_deg_inside_riser_100x100.dsf
```

reset should return the preview to the original 100 × 100 baseline state.

---

# 8. Coupler Hole Classification

Modify:

```text
cms_coupler_classifier.dart
```

## 8.1 Automatic candidate recognition

Broaden the automatic heuristic for standard cable-tray/trunking obround coupler slots.

Support approximately:

```text
8 × 12 mm
8 × 16 mm
8 × 20 mm
8 × 25 mm
```

Use appropriate geometric tolerances rather than exact string/size equality.

The classifier should recognize a reasonable family around these standard sizes.

## 8.2 Important: heuristic classification must not override explicit information

Use precedence similar to:

```text
1. Explicit semantic role stored on punch
2. Explicit COUPLER layer / metadata
3. User manually marked as coupler
4. Automatic heuristic candidate
5. Generic perforation
```

Explicit information always wins.

---

# 9. Interactive Coupler Identification Tool

The application must provide a direct identification mechanism because technically a coupler slot and an ordinary obround hole can have identical geometry.

The semantic difference is therefore an **identification/role**, not necessarily a different shape.

Add an action such as:

```text
Mark as Coupler Mounting Slot
```

and the inverse:

```text
Mark as Regular / Perforation
```

Suggested API:

```dart
markPunchAsCoupler(
  String punchId,
  {bool isCoupler = true},
)
```

Provide this capability in both the appropriate view model/controller layers needed by the UI and persistence path.

---

# 10. Where the Coupler Tool Appears

## Stage 1 — Manufacturing Definition

The user may identify couplers immediately after authoring the holes/slots.

Example:

```text
STEP 3 — Manufacturing Features

Select coupler mounting slots.

[ Identify Couplers ]

[ Continue ]
```

The user's explicit classification must be stored in the DSF.

## Stage 2 — Port Mapping

Provide an optional:

```text
Review / Identify Couplers
```

action if automatic recognition produced uncertain candidates.

However, Stage 2 must **not silently overwrite explicit Stage 1 classifications**.

## 2D Context Menu / Properties

When a punch/hole/slot is selected, expose:

```text
Coupler Mounting Slot   [ ON / OFF ]
```

This allows correction at any time.

---

# 11. Do Not Auto-Label Every Matching Slot as a Coupler

A geometric heuristic such as `8 × 20 mm` is useful for finding candidates, but shape/size alone is not absolute proof of manufacturing intent.

Therefore:

```text
Candidate ≠ confirmed semantic role
```

Use a confidence/state model where practical:

```text
confirmedCoupler
candidateCoupler
regularPerforation
```

At minimum, preserve the difference between explicit/user-confirmed classification and heuristic classification.

For an action like:

```text
Identify Couplers
```

the user can be presented with the detected candidate set and confirm them rather than forcing every candidate to become a coupler.

---

# 12. DSF Persistence

Coupler identity must be stored in DSF.

Example conceptual data:

```json
{
  "punches": [
    {
      "id": "PUNCH_017",
      "role": "coupler",
      "source": "user"
    }
  ]
}
```

The exact schema must follow the existing DSF model.

Do not introduce a second competing punch/feature storage system.

Existing DSFs without coupler metadata remain valid.

---

# 13. Stage-State Integration

This fix must fit the three-stage CMS workflow.

## Stage 1

```text
Manufacturing Definition

✓ Bend lines
✓ Flange lines
✓ Coupler identification
```

Save DSF.

Stage 1 complete means:

```text
manufacturingDefinitionComplete = true
```

Port mapping may still be absent.

## Stage 2

```text
Automatic Port Mapping

Consumes Stage 1 data.

Does NOT regenerate/infer bend or flange lines.
```

It may use coupler metadata when interpreting openings/features.

Save DSF.

## Stage 3

```text
Template Scaling

Consumes:
✓ Manufacturing seed
✓ Port mapping
✓ Product definition
✓ Scaling profile
✓ Feature classifications
```

---

# 14. Reopening a Partially Completed DSF

When a DSF is reopened, inspect its CMS workflow state.

Example:

```text
✓ Manufacturing definition
✓ Coupler identification
✗ Port mapping
✗ Template scaling
```

Show:

```text
CMS PART

Manufacturing definition is complete.
Port mapping is not yet complete.

[ Continue Port Mapping ]
[ Edit Manufacturing Definition ]
```

Similarly:

```text
✓ Manufacturing definition
✓ Port mapping
✗ Template scaling
```

should offer:

```text
[ Continue Template Scaling ]
[ Review Port Mapping ]
```

---

# 15. Product-Level Scaling Architecture

Do not hard-code 150 independent algorithms.

The system should use:

```text
Product Contract
      ↓
Scaling Profile
      ↓
Generic Scaling Engine
```

The 45 product definitions can select reusable scaling behaviors.

For example:

```text
45° Inside Riser
→ scalingProfile = INSIDE_RISER
```

while:

```text
45° Bend
→ scalingProfile = FLAT_BEND_45
```

This is the correct way to prevent the current `contains('45')` routing bug.

Variations should primarily provide dimensions/options to the reusable product/scaling behavior.

---

# 16. Required Automated Tests

## Test A — 45° Inside Riser Width

File:

```text
45_deg_inside_riser_100x100.dsf
```

Change width:

```text
100 → 150 mm
```

Verify:

- floor web reaches the expected structural width (145.6 mm in the current reference case)
- left cheek remains rigid
- right cheek remains rigid
- cheek profiles are not skewed
- B1/B2 move correctly
- B3 retains its correct transverse fold relationship
- coupler slots retain exact shape and orientation
- no 22.5° diagonal miter morphology is introduced

## Test B — 45° Inside Riser Height

Change:

```text
100 → 150 mm
```

Verify:

- cheek sidewalls become taller
- floor length remains fixed
- B1/B2 remain fixed
- B3 relationship remains valid
- coupler slots remain undistorted

## Test C — Reset Dimensions

Change multiple parameters, then press:

```text
Reset Dimensions
```

Verify:

- all parameters return to baseline
- slider values return to baseline
- 2D preview returns to baseline
- 3D preview returns to baseline
- bend/flange metadata is untouched
- port mapping is untouched

## Test D — Coupler Recognition

Verify that the 20 mm obround slots in:

```text
45_deg_inside_riser_100x100.dsf
```

become automatic coupler **candidates** and can be confirmed as couplers.

## Test E — Explicit Coupler Marking

Select a normal obround slot and mark it:

```text
Coupler Mounting Slot = ON
```

Verify the semantic role is stored in DSF.

Toggle it off and verify the role changes back appropriately.

## Test F — Backward Compatibility

Open an older DSF without the new CMS/coupler metadata.

Verify it remains openable and behaves as before.

---

# 17. Manual Verification Checklist

In TruFold Studio:

### Width

Drag width from 100 to 150 mm.

Confirm:

```text
✓ Floor expands
✓ Cheeks translate rigidly
✓ Cheek profile does not skew
✓ Coupler slots remain rectangular/obround and aligned
```

### Height

Drag height from 100 to 150 mm.

Confirm:

```text
✓ Sidewalls grow taller
✓ Floor does not lengthen
✓ Bend structure remains correct
✓ Coupler slots remain undistorted
```

### Reset

Click:

```text
Reset Dimensions
```

Confirm:

```text
✓ All dimensions return to baseline
✓ 2D resets
✓ 3D resets
```

### Couplers

Select a slot.

Confirm:

```text
✓ Coupler Mounting Slot toggle exists
✓ Role can be assigned manually
✓ Role is preserved after save/reopen
```

---

# 18. Implementation Guardrails

Do not:

- re-enable automatic bend-line generation
- re-enable automatic flange-line generation
- route risers through the flat-bend 45° morpher
- use product-name substring matching as the primary scaling strategy
- globally stretch the DXF for riser scaling
- deform coupler slots when scaling cheeks
- silently overwrite explicit user coupler classifications
- create a separate CMS feature persistence system outside DSF
- create 150 independent scaling algorithms

Do:

- keep the legacy automatic bend/flange code isolated
- use explicit product/scaling profiles
- use the authored manufacturing structure as the source of truth
- use zone/feature relationships instead of brittle raw coordinates where possible
- make coupler identity semantic and persistent
- preserve Stage 1/Stage 2/Stage 3 resumability

---

# 19. Definition of Done

The fix is complete when:

1. `45° Inside Riser` no longer uses the `45° flat bend` morph strategy.
2. Width scaling expands the correct web and rigidly moves the cheeks.
3. Height scaling increases cheek height without extending the floor.
4. Coupler slots remain geometrically intact during both width and height changes.
5. `Reset Dimensions` immediately restores all scaling parameters and previews to baseline.
6. Standard 8 mm × 12–25 mm obround slots are recognized as coupler candidates.
7. Any selected punch can be explicitly marked/unmarked as a coupler.
8. Explicit/manual coupler classification overrides heuristic classification.
9. Coupler identity is persisted in DSF.
10. Stage 2 consumes Stage 1 manufacturing data instead of recreating it.
11. Existing non-CMS and older DSF files remain backward compatible.
12. The solution uses reusable product/scaling profiles rather than 150 separate algorithms.

---

# Final Principle

```text
STAGE 1
Human defines manufacturing intent
        ↓
SAVE DSF
        ↓
STAGE 2
Application discovers and maps ports
        ↓
SAVE DSF
        ↓
STAGE 3
Application builds reusable parametric scaling
        ↓
COMPLETE CMS TEMPLATE
```

For the 45° Inside Riser specifically:

```text
User-authored bends/flanges
        ↓
Existing folding engine
        ↓
Dedicated Riser scaling profile
        ↓
Correct port mapping
        ↓
Protected semantic coupler features
        ↓
Parametric scaling
```

The geometry is taught once; the application should then preserve that manufacturing intent throughout port mapping and scaling.
