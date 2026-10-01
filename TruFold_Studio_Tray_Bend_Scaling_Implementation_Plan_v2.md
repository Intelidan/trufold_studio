# TruFold Studio — Tray Accessories 45° / 90° Bend
# Width, Wing, Coupler-Row & Bend-Radius Parametric Scaling
## Revised Implementation Plan

## 1. Scope

Implement dedicated parametric scaling for:

- Tray Accessories — 45° Bend
- Tray Accessories — 90° Bend

The supplied reference drawings establish the baseline geometry and show 100×50, 100×100 and 450×50 examples. The reference notes that coupler-hole sets increase with each 50 mm increase in height. fileciteturn3file0L2-L18

This implementation must remain product-specific. Do not push these rules into generic CMS scaling.

---

## 2. Core Scaling Principles

There are four independent but interacting inputs/rules:

```text
1. Width
2. Height
3. Bend Radius
4. Bend Angle (45° or 90°)
```

They must not be handled by one uniform geometric scale factor.

### Width controls

- growth of the angled end-wall/wings,
- redistribution of the total tray width between the straight base portion and the angled wings,
- wing-related bend endpoints and miter/transition geometry,
- additional coupler-hole row at widths >= 300 mm.

### Height controls

- vertical wall/flange geometry,
- number of coupler-hole sets based on 50 mm increments.

### Radius controls

- bend arc geometry,
- tangent points,
- bend-line/developed geometry,
- corresponding 3D bend curvature,
- downstream miter/wing geometry that depends on the bend radius.

### Angle controls

- fixed by product type:
  - 45° Bend
  - 90° Bend

---

# 3. Critical Width Rule — Wings Consume the Straight Base Width

This is an important manufacturing invariant and must be explicitly implemented.

When the tray width increases, the angled end-wall/wings grow into the available tray width. They are NOT simply added to the outside of a fixed-width straight base.

Therefore:

```text
Overall Tray Width
    =
Straight Base Span
+ Left Wing Take-Up
+ Right Wing Take-Up
```

For a symmetric bend:

```text
Straight Base Span
    =
Overall Tray Width
- Left Wing Take-Up
- Right Wing Take-Up
```

For symmetric geometry this may simplify to:

```text
Straight Base Span
    =
Overall Tray Width
- 2 × Wing Take-Up
```

IMPORTANT:

`Wing Take-Up` is the wing's transverse projection/consumed width in the base-width direction.

Do NOT automatically subtract the full angled-wall length. The angled wall length and its transverse projection are different geometric quantities, especially for 45° geometry.

The scaler must therefore maintain two related concepts:

```text
wingPanelLength
wingTakeUpWidth
```

rather than using one number for both.

### Width invariant

At every width:

```text
leftTakeUp + straightBaseSpan + rightTakeUp
≈ overallTrayWidth
```

within the existing CAD tolerance.

This is a primary acceptance test.

---

# 4. Wing Scaling

The supplied drawings show that the angled end-wall/wings increase substantially as width increases.

The observed reference behavior is approximately:

```text
45° Bend:
100 mm width → wing ≈ 50 mm
450 mm width → wing ≈ 139 mm

90° Bend:
100 mm width → wing ≈ 65–66 mm
```

The small drawing variations are acceptable for this implementation; do not waste implementation time attempting to reproduce sub-millimeter construction differences.

For the first scaler implementation, use the calibrated width-growth coefficient:

```text
Kwing ≈ 0.255
```

### 45° initial model

```dart
wingPanelLength45 =
    referenceWing45 +
    0.255 * (width - 100.0);
```

with:

```text
referenceWidth = 100 mm
referenceWing45 ≈ 50 mm
```

### 90° initial model

```dart
wingPanelLength90 =
    referenceWing90 +
    0.255 * (width - 100.0);
```

with:

```text
referenceWidth = 100 mm
referenceWing90 ≈ 65.5 mm
```

These formulas are calibration starting points, not permission to uniformly scale the entire DSF.

The scaler must convert the resulting wing geometry into the actual 2D contour and recalculate the remaining straight base span.

---

# 5. Wing / Base Redistribution

For each width evaluation:

```text
1. Calculate desired wing geometry.
2. Calculate each wing's transverse take-up.
3. Calculate the remaining straight base span.
4. Rebuild the floor/base contour around those three regions.
5. Recalculate connected bend endpoints.
6. Recalculate miter/intersection geometry.
7. Rebuild dependent flanges/walls.
8. Rebuild the coupler-hole pattern.
9. Rebuild/fold the 3D model.
```

Never do:

```text
scale complete base
+
scale complete wing
```

because that would double-count the width occupied by the wings.

---

# 6. Coupler-Hole Row Logic

The reference drawing explicitly establishes:

```text
50 mm height → 1 coupler set
100 mm height → 2 coupler sets
Every additional 50 mm → +1 set
```

Use:

```dart
int heightCouplerSets(double height) {
  return max(1, (height / 50.0).ceil());
}
```

Examples:

| Height | Height-based Sets |
|---:|---:|
| 50 | 1 |
| 100 | 2 |
| 150 | 3 |
| 200 | 4 |
| 250 | 5 |

---

# 7. Width-Based Additional Coupler Row

The 450 mm reference shows an additional coupler row even though the height is only 50 mm.

Therefore:

```dart
int widthCouplerBonus(double width) {
  return width >= 300.0 ? 1 : 0;
}
```

Total coupler-row count:

```dart
int totalCouplerRows(
    double width,
    double height,
) {
  return heightCouplerSets(height)
      + widthCouplerBonus(width);
}
```

Examples:

| Width | Height | Height Sets | Width Bonus | Total |
|---:|---:|---:|---:|---:|
| 100 | 50 | 1 | 0 | 1 |
| 100 | 100 | 2 | 0 | 2 |
| 250 | 50 | 1 | 0 | 1 |
| 300 | 50 | 1 | 1 | 2 |
| 450 | 50 | 1 | 1 | 2 |
| 300 | 100 | 2 | 1 | 3 |
| 450 | 100 | 2 | 1 | 3 |

Do not interpret the 300 mm rule as doubling the entire row count. It adds one width-driven row.

---

# 8. Coupler Holes Must Be Regenerated, Not Uniformly Scaled

When width or height changes:

```text
Wing/Base Geometry
        ↓
Determine required coupler rows
        ↓
Rebuild hole pattern
```

Do not stretch existing holes.

Preserve:

- hole/slot size,
- slot orientation,
- local row geometry,
- required edge clearances,
- coupler-hole role/identity.

The hole pattern should be generated from a deterministic pattern definition.

---

# 9. Bend Radius — New Required Parameter

The supplied bend drawings represent bends with:

```text
Radius = 300 mm
```

`Radius` must therefore become a first-class Tray Bend parameter.

Supported range:

```text
Minimum = 300 mm
Maximum = 1000 mm
```

Recommended standard UI step:

```text
50 mm
```

So the slider can evaluate:

```text
300
350
400
450
500
550
600
650
700
750
800
850
900
950
1000
```

### Quick-set buttons

Provide three quick actions:

```text
[300 mm] [600 mm] [900 mm]
```

These are shortcuts to the slider/value, not separate scaling modes.

---

# 10. Radius Must Affect Real Geometry

Radius is NOT a presentation-only parameter.

Changing radius must update:

```text
2D bend arc/developed geometry
Bend line locations
Tangent points
Arc centers
Wing / miter relationships where dependent
Base/wing redistribution where geometrically affected
3D bend curvature
```

For a bend angle θ, the analytical centerline arc length relationship is:

```text
L_arc = R × θ
```

where θ is expressed in radians.

Therefore:

```text
45°:
θ = π / 4

90°:
θ = π / 2
```

The actual DSF/scaler must use the project's existing bend-radius convention (inside radius, centerline radius, or other established sheet-metal definition). Do not introduce a second radius convention.

If the existing 300 mm template currently contains hard-coded radius geometry, identify and replace that hard-coded value with the new parameter.

---

# 11. Radius and Width Must Interact Correctly

The correct dependency is:

```text
Width + Radius + Angle
          ↓
Bend / Wing Geometry
          ↓
Straight Base Allocation
          ↓
Flanges / Walls
```

Do not calculate wing geometry from width alone and then simply change the bend arc afterward.

For example:

```text
Width = 450
Radius = 300
```

and:

```text
Width = 450
Radius = 900
```

must each produce internally consistent:

- bend geometry,
- wing geometry,
- straight base span,
- tangent/miter relationships.

The actual relationship may be product-specific, so use the existing reference template geometry and analytical construction rather than inventing an independent generic formula.

---

# 12. Radius Does NOT Automatically Change Coupler-Row Count

The coupler-row rules remain driven by width and height:

```text
Rows = ceil(H / 50) + (W >= 300 ? 1 : 0)
```

Changing:

```text
R = 300 → 600 → 900
```

must not change the number of coupler rows unless a future manufacturing rule explicitly declares such a dependency.

The radius changes the bend geometry, not the hole-count rule.

---

# 13. Radius UI — DSF Fittings & Template Inspector

Add:

```text
Bend Radius
```

to the **DSF Fittings & Template Inspector** dialog for Tray 45° Bend and Tray 90° Bend.

UI:

```text
Bend Radius
[────────────●────────────]
300 mm                    1000 mm

[300] [600] [900]
```

Requirements:

- Default = 300 mm for existing templates.
- Minimum = 300 mm.
- Maximum = 1000 mm.
- Slider value displayed numerically.
- Quick-set buttons set the slider exactly.
- Editing radius immediately regenerates the model.
- Radius value must be saved in the DSF where the DSF represents a scalable tray-bend instance/template state.
- For DDS/TDS instances, the selected radius is stored in DDS, not written back into the master template.

---

# 14. Radius UI — TDS Studio Parameter Panel

Add the same parameter to the DDS/TDS parameter table.

Example:

| Parameter | Value | Unit | Source | State |
|---|---:|---|---|---|
| Width | 450 | mm | DDS Instance | Editable |
| Height | 50 | mm | DDS Instance | Editable |
| Bend Angle | 45 | ° | Template | Fixed |
| Bend Radius | 300 | mm | DDS Instance | Editable |
| Coupler Rows | 2 | sets | Derived | Read-only |
| Straight Base Span | Derived | mm | Derived | Read-only |

The user should be able to edit:

```text
Bend Radius = 600
```

and see 2D + 3D update immediately.

---

# 15. Recommended Parameter State Model

For tray bends:

```text
USER PARAMETERS
----------------
Width
Height
Radius

FIXED TEMPLATE PARAMETERS
-------------------------
Bend Angle
Product Type
Port topology
Coupler-hole size
Manufacturing feature definitions

DERIVED PARAMETERS
------------------
Wing Panel Length
Wing Take-Up
Straight Base Span
Coupler Row Count
Arc Length
Tangent Locations
Miter Intersections
```

This prevents users from directly editing calculated geometry that should remain controlled by the scaler.

---

# 16. Important Baseline / Instance Rule

The master DSF template remains untouched.

For example:

```text
MASTER TEMPLATE
45° Bend
W=100
H=50
R=300
```

DDS:

```text
W=450
H=100
R=600
```

The engine does:

```text
Resolve 45° Bend DSF
        ↓
Load baseline geometry
        ↓
Apply DDS:
  W = 450
  H = 100
  R = 600
        ↓
Calculate derived geometry
        ↓
Render 2D
        ↓
Fold 3D
```

This follows the established TruFold DDS/template architecture.

---

# 17. Test Matrix

Minimum test matrix:

### Width

```text
100
150
200
250
300
350
400
450
```

### Height

```text
50
100
150
```

### Radius

```text
300
600
900
1000
```

### Angles

```text
45°
90°
```

Representative tests:

```text
100×50 R300
100×100 R300
450×50 R300
450×100 R300

450×50 R600
450×50 R900
450×50 R1000

300×50 R300
300×100 R300
```

---

# 18. Specific Acceptance Tests

## Test A — Width redistribution

For every tested width:

```text
Left wing take-up
+ Straight base span
+ Right wing take-up
≈ Overall width
```

The straight base span must decrease as the wings consume additional width.

## Test B — Height coupler count

```text
H=50  → 1 height set
H=100 → 2 height sets
H=150 → 3 height sets
```

## Test C — Width coupler threshold

```text
W=299 → no width bonus
W=300 → +1 width row
W=450 → +1 width row
```

## Test D — Radius

```text
R=300 → baseline geometry
R=600 → larger bend radius
R=900 → larger bend radius
R=1000 → maximum supported radius
```

Verify 2D and 3D remain consistent.

## Test E — Radius reversibility

```text
300 → 600 → 900 → 300
```

must return to the baseline geometry.

## Test F — Combined scaling

```text
100×50 R300
       ↓
450×100 R900
       ↓
150×50 R300
```

The final result must match a fresh evaluation from the original template with:

```text
W=150
H=50
R=300
```

This ensures scaling is baseline-driven and not cumulative.

## Test G — 45° / 90° separation

Changing the 45° bend parameters must never route through 90° geometry logic, and vice versa.

Shared utilities may be used, but the product-specific geometric construction remains independent.

---

# 19. Geometry Integrity

Every generated result must verify:

- closed face contours,
- coincident connected vertices,
- valid bend connectivity,
- tangent continuity where expected,
- correct bend radius,
- correct wing/base partition,
- no self-intersection,
- no duplicate geometry,
- correct coupler-hole pattern,
- correct 3D folded orientation.

The existing CAD tolerance policy must be reused.

---

# 20. Implementation Architecture

Recommended dedicated scaler components:

```text
tray_45_deg_bend_scaler.dart
tray_90_deg_bend_scaler.dart
tray_bend_geometry.dart
tray_bend_coupler_pattern.dart
tray_bend_radius_geometry.dart
```

Or equivalent project naming if matching the existing CMS architecture.

Conceptually:

```text
Tray Bend Scaler
│
├── Width Solver
│    ├── Wing Length
│    ├── Wing Take-Up
│    └── Straight Base Span
│
├── Height Solver
│    └── Coupler Rows
│
├── Radius Solver
│    ├── Bend Arc
│    ├── Tangency
│    └── Developed Geometry
│
├── Coupler Pattern Generator
│
└── 3D Regeneration
```

---

# 21. Most Important Agent Instructions

1. Do not uniformly scale the complete bend drawing.
2. Do not treat wing growth as material added outside the tray width.
3. Preserve the width partition:
   `Overall Width = Wing Take-Up + Straight Base + Wing Take-Up`.
4. Keep wing panel length separate from wing transverse take-up.
5. Coupler holes are regenerated from pattern rules; they are never stretched.
6. Height determines one additional coupler set per 50 mm.
7. Width >= 300 mm adds one additional coupler row.
8. Radius is a real geometric parameter from 300 to 1000 mm.
9. 45° and 90° bends use separate product-specific geometric construction.
10. Radius changes must regenerate both 2D flat geometry and 3D folded geometry.
11. Recalculate from the original template for every parameter state; never accumulate transforms.
12. DDS stores user-selected width, height and radius; master DSF remains the template source.
13. Add Bend Radius to both:
    - DSF Fittings & Template Inspector
    - TDS Studio Parameters panel.
14. Provide quick radius buttons:
    `[300] [600] [900]`.
15. Keep derived geometry read-only in the parameter UI.

---

# 22. Final Scaling Model

The intended model is:

```text
                  WIDTH
                    │
           ┌────────┴────────┐
           ▼                 ▼
      Wing Growth       Coupler Bonus
           │             W >= 300
           ▼                 │
   Wing Transverse           │
      Take-Up                │
           │                 │
           ▼                 │
  Straight Base Span         │
           │                 │
           └────────┬────────┘
                    │
                    ▼
             2D Base Geometry
                    ▲
                    │
                  HEIGHT
                    │
                    ▼
            Height Coupler Sets
              ceil(H / 50)

                    +

                  RADIUS
                    │
                    ▼
          Bend / Arc / Tangency
                    │
                    ▼
             2D + 3D Geometry
```

The fundamental invariant is:

> **Increasing tray width causes the angled wings to grow while consuming part of the straight base width. Increasing height adds coupler-hole sets at every 50 mm. Radius independently controls the bend curvature/developed geometry from 300 to 1000 mm.**

