# TruFold Studio — Ladder Rung Joint & Welding Configuration
## Assembly-Level Implementation Specification

## 1. Purpose

Extend the Ladder Assembly architecture so the user can choose how each rung is joined to the two side rails / heights.

The ladder remains an assembly of reusable physical components rather than a single deformed DXF drawing.

Existing ladder component concepts remain unchanged:

```text
Ladder Assembly
├── Left Side Rail / Height
├── Right Side Rail / Height
└── Rungs × N
```

The new addition is an assembly-level **Rung Joint / Welding Method** parameter.

The two supported manufacturing methods are:

1. **Direct Inside Weld**
2. **Pass-Through Rail + Outside End Weld**

The first method welds each rung directly to the inside face of the side rail.

The second method creates a rectangular opening in the side rail, allows the rung to pass through the rail and protrude beyond the outside face, and welds the exposed rung end on the outside of the side rail for additional mechanical strength.

---

# 2. Core Manufacturing Concept

The ladder assembly must distinguish between:

```text
Rung Geometry
Side Rail Geometry
Joint Geometry
Weld Representation
```

The selected welding method changes the **joint construction**, not the fundamental rung profile.

```text
Rung
  +
Side Rail
  +
Joint Method
      ↓
Assembly Geometry
      ↓
2D / 3D Representation
      ↓
TDS / DDS Information
```

Do not duplicate the rung component definition for the two welding methods.

The same rung component must be reusable with either joint method.

---

# 3. Rung Component

The existing ladder rung is a C-slotted channel without a flange.

The current reference data identifies the shown rung section as approximately:

```text
Rung Size = 40 × 20 mm
```

and shows the ladder assembly using these rungs. fileciteturn7file0L2-L8

The rung should retain its existing geometry and persistent component identity.

Conceptually:

```text
RungComponent
├── profile = C-channel
├── width = 40 mm
├── depth = 20 mm
└── jointMethod = selected at assembly level
```

Do not modify the rung profile merely because the selected welding method changes.

---

# 4. Side Rail / Height Component

The side rail remains a flat sheet-metal component with the already-supported flange construction.

Existing flange functionality must be reused:

```text
Flange Angle
Inside Flange
Outside Flange
```

Flange bending is already implemented and must not be rebuilt for this feature.

The new welding feature must only add the necessary rung-joint geometry to the side rail.

---

# 5. Welding Method Parameter

Create an assembly parameter such as:

```text
Rung Joint Method
```

Use a strongly typed enum rather than arbitrary text.

Recommended values:

```dart
enum LadderRungJointMethod {
  directInsideWeld,
  passThroughOutsideWeld,
}
```

Suggested UI labels:

```text
Direct Inside Weld
Pass Through + Outside Weld
```

Avoid exposing implementation terminology such as enum names to the user.

---

# 6. Method A — Direct Inside Weld

## 6.1 Manufacturing geometry

In this mode, the rung terminates at the inside face of each side rail.

Conceptual section:

```text
       SIDE RAIL
          │
          │████  ← weld
==========│
   RUNG   │
==========│
          │
```

The rung does not pass through the side rail.

The side rail therefore has:

```text
No rung pass-through opening
```

at the rung location.

## 6.2 3D assembly

The rung endpoint is coincident/positioned against the inside side-rail face.

A weld/joint representation should be created at both ends.

Conceptually:

```text
Left Rail ← Rung → Right Rail
   weld             weld
```

## 6.3 2D representation

The side rail does not receive a rectangular rung opening.

The rung remains represented as a separate component meeting the inside face.

If the current drawing conventions support weld symbols or simplified joint marks, the weld can be represented using the existing annotation/technical drawing system.

Do not add manufacturing-detail geometry that is not part of the user's selected representation level.

## 6.4 Physical Rung Cut Length Formula

In Direct Inside Weld mode, the physical cut length of every straight C-channel rung blank is equal to the inside nominal width of the ladder:

$$L_{\text{rung}} = W_{\text{nominal}}$$

The cut ends sit flush against the planar web of each side rail's inner face. The structural MIG weld bead is placed internally around the contact perimeter of the $40 \times 20\,\text{mm}$ C-channel.

---

# 7. Method B — Pass Through + Outside Weld

## 7.1 Manufacturing geometry

In this mode, the rung passes through the side rail.

The side rail must therefore contain a rectangular opening at every rung location.

Conceptual section:

```text
             SIDE RAIL
                 │
=========┌───────┼───────┐=========
         │       │       │
         │ RUNG  │       │
=========└───────┼───────┘=========
                 │
              OUTSIDE
                 ↑
            EXPOSED RUNG END
                 │
              WELD HERE
```

The rung must extend through the side rail and protrude beyond its outside face.

The protruding outside end receives the weld.

The purpose of this method is to provide the stronger external welded joint requested by the user.

## 7.2 Side-rail opening & Tooling Clearance

At every rung position, generate a rectangular opening through the side rail.

The opening must be based on the actual rung envelope and an explicit manufacturing clearance rule:

$$\text{Opening Width} = W_{\text{rung}} + 2 \cdot c = 40.0\,\text{mm} + 2 \cdot (1.0\,\text{mm}) = 42.0\,\text{mm}$$
$$\text{Opening Height} = H_{\text{rung}} + 2 \cdot c = 20.0\,\text{mm} + 2 \cdot (1.0\,\text{mm}) = 22.0\,\text{mm}$$

Where:
- $W_{\text{rung}} = 40.0\,\text{mm}$ (standard C-channel width)
- $H_{\text{rung}} = 20.0\,\text{mm}$ (standard C-channel depth)
- $c = 1.0\,\text{mm}$ standard CNC turret punch / laser cutting clearance all-around for effortless rung insertion prior to welding jig fixturing.

Corner radii on the rectangular slot: default $R_{\text{corner}} = 0.5\,\text{mm}$ to $1.0\,\text{mm}$ to reflect standard CNC punching tools (e.g. standard $42 \times 22\,\text{mm}$ rectangular station tool).

## 7.3 Rung extension & Physical Cut Length Formula

The rung must continue through the rail sufficiently to create an exposed outside end for welding.

The physical cut length of the rung blank is:

$$L_{\text{rung}} = W_{\text{nominal}} + 2 \cdot T_{\text{rail}} + 2 \cdot \text{outsideWeldProjection}$$

Where:
- $W_{\text{nominal}}$ = nominal inner ladder width ($300, 450, 600, 750, 900\,\text{mm}$)
- $T_{\text{rail}}$ = side rail sheet metal thickness ($2.0\,\text{mm}$ standard, or $3.0\,\text{mm}$ heavy duty)
- $\text{outsideWeldProjection}$ = extension beyond the outer rail face ($3.0\,\text{mm}$ to $5.0\,\text{mm}$, default $= 3.5\,\text{mm}$) to provide a clean lip for laying the external MIG fillet weld bead.

Example: For a $W = 600\,\text{mm}$ ladder with $2.0\,\text{mm}$ rails and $3.5\,\text{mm}$ outside projection:
$$L_{\text{rung}} = 600 + 2(2.0) + 2(3.5) = 611.0\,\text{mm}$$

Do not shorten or distort the rung C-channel profile to achieve the joint.

## 7.4 3D assembly

The 3D assembly must visually and geometrically show:

```text
Rung
  ↓
Passes through rail
  ↓
Projects outside rail
  ↓
Outside weld location
```

The 3D representation should make the difference from Direct Inside Weld obvious.

---

# 8. Joint Geometry Must Be Generated from the Rung Pattern

The welding method applies to every rung instance in the assembly.

For a straight ladder:

```text
Rung Position 01 → Joint Method
Rung Position 02 → Joint Method
Rung Position 03 → Joint Method
...
Rung Position N  → Joint Method
```

Do not manually modify each rung.

The ladder assembly generator must apply the selected joint method to all rung instances.

---

# 9. Straight Ladder Parameters & Two-Pitch Engine

Existing straight-ladder parameters are driven by an industrial **Two-Pitch Calculation Engine**:

```text
Width (W)
Length (L)
End Margin Pitch (P_end - Header/Footer Offset)
Intermediate Rung Pitch (P_mid - Body Pitch)
Rung Pitch Mode (Equalized vs. Fixed)
Rung Joint Method
```

### 9.1 Why Two Distinct Pitches are Mandatory
In industrial cable ladders, rungs cannot be spaced uniformly from $0\,\text{mm}$ to $L\,\text{mm}$. The rail ends carry **coupler splice hole patterns** (typically spanning $75\,\text{mm}$ with $4 \times \varnothing 10\,\text{mm}$ holes or $20 \times 8\,\text{mm}$ obrounds, as seen on Page 1 & 55 of engineering standards).
- If a rung were placed at $0\,\text{mm}$ or $25\,\text{mm}$, it would collide with the coupler plate and splice bolts (M6 $\times$ 16 roofing bolts).
- Therefore, the ladder requires an **End Margin Pitch** ($P_{\text{end}}$, header/footer margin, typically $50\,\text{mm}$ to $75\,\text{mm}$) and an **Intermediate Pitch** ($P_{\text{mid}}$, typically $250\,\text{mm}$ or $300\,\text{mm}$).

### 9.2 Mathematical Formulation of the Rung Pattern

Given:
- Overall ladder length $L$ (e.g. $3000.0\,\text{mm}$)
- End margin pitch $P_{\text{end}}$ (default $75.0\,\text{mm}$, min $50.0\,\text{mm}$)
- Target intermediate pitch $P_{\text{target}}$ (default $250.0\,\text{mm}$)

**Step 1: Effective Intermediate Span**
$$\text{Span}_{\text{effective}} = L - 2 \cdot P_{\text{end}}$$
*Example: for $L = 3000\,\text{mm}$ and $P_{\text{end}} = 75\,\text{mm}$: $\text{Span}_{\text{effective}} = 3000 - 150 = 2850\,\text{mm}$.*

**Step 2: Number of Intermediate Bays ($k$) & Rung Count ($N_{\text{rungs}}$)**
$$k = \text{round}\left(\frac{\text{Span}_{\text{effective}}}{P_{\text{target}}}\right)$$
*Example: $k = \text{round}(2850 / 250) = \text{round}(11.4) = 11$ bays.*

Total rungs:
$$N_{\text{rungs}} = k + 1 = 12 \text{ rungs}$$

**Step 3: Actual Pitch ($P_{\text{actual}}$) by Pitch Mode**

```dart
enum RungPitchMode {
  equalizedPitch, // Automatically adjusts pitch to distribute rungs evenly across Span_effective
  fixedPitch,      // Enforces strictly P_target, floating the end margins symmetrically
}
```

- In **Equalized Mode** (Standard):
  $$P_{\text{actual}} = \frac{\text{Span}_{\text{effective}}}{k} = \frac{2850}{11} = 259.09\,\text{mm}$$
  Rung longitudinal coordinates along the rail axis:
  $$X_i = P_{\text{end}} + i \cdot P_{\text{actual}}, \quad \text{for } i \in [0, k]$$

- In **Fixed Pitch Mode**:
  $$P_{\text{actual}} = P_{\text{target}} = 250.0\,\text{mm}$$
  The remaining delta is absorbed symmetrically by the end margins:
  $$P_{\text{end\_floating}} = \frac{L - (k \cdot P_{\text{target}})}{2}$$

Changing the joint method must not change:
- ladder width,
- ladder length,
- rung pitch ($P_{\text{end}}$ and $P_{\text{actual}}$),
- rung count ($N_{\text{rungs}}$),
- side-rail spacing.

It changes only the construction of each rung-to-rail joint.

---

# 10. Interaction with Fixed Ladder Accessories & Trajectory Patterns

Ladder accessories (Bends, Risers, Tees, Crosses, Reducers) are **Fixed Manufactured Assemblies (Recipes)**, NOT dynamically stretched 2D DXF contours. 

Changing dimensions continuously alters the discrete rung pitch and count, breaking standard manufacturing tooling and structural certifications. Therefore:
1. Accessories exist in standard catalog variants (e.g. $R = 300\,\text{mm}, 600\,\text{mm}$; $W = 300, 450, 600, 750, 900\,\text{mm}$; $H = 100\,\text{mm}$; $\theta = 30^\circ, 45^\circ, 60^\circ, 90^\circ$).
2. On the Technical Data Sheet (TDS), the viewport displays the clean representative engineering assembly, while the ISO 7200 Title Block and Dimension Table provide the specific manufacturing values.

### 10.1 Four Accessory Rung Trajectory Patterns

Rungs in accessories follow 4 distinct deterministic geometric classifications:

#### Pattern 1: Radial Spokes (Horizontal Bends $30^\circ, 45^\circ, 90^\circ$)
- Defined by center of curvature $(X_0, Y_0)$, inner radius $R$, outer radius $R + W$, and bend angle $\alpha$.
- Side rails are concentric circular arcs with straight tangent lead-ins ($75\,\text{mm}$–$100\,\text{mm}$) containing standard splice hole patterns.
- Rungs are straight C-channels of constant length $L_{\text{rung}}$ (derived per Section 6.4/7.3 for width $W$), placed as radial spokes pointing to $(X_0, Y_0)$ at angular increments:
  $$\theta_i = \theta_{\text{start}} + \frac{i \cdot \alpha}{N_{\text{rungs}} - 1}, \quad \text{for } i \in [0, N_{\text{rungs}}-1]$$
- In Pass-Through mode, the rectangular openings in the curved rail web are normal to the tangent of the arc at each $\theta_i$.

#### Pattern 2: Slope Stations (Inside & Outside Risers $30^\circ, 45^\circ, 60^\circ, 90^\circ$)
- Side rails are pre-cut profiled plates with $90^\circ$ flanges following the rise/drop angle $\alpha$.
- Rungs are straight horizontal members of constant length $L_{\text{rung}}$ spaced evenly along the inclined elevation plane.

#### Pattern 3: Linearly Tapered Rungs (Left, Right, and Concentric Reducers)
- Length of reducer is fixed (typically $L_{\text{reducer}} = 500\,\text{mm}$ to $600\,\text{mm}$).
- Rungs remain parallel to the entry/exit ports, but each individual rung $i$ has a unique physical cut length:
  $$W_i = W_1 - (W_1 - W_2) \cdot \frac{x_i}{L_{\text{taper}}}$$
- For a Left or Right Reducer, the inclined rail is oriented at angle $\phi = \arctan\left(\frac{|W_1 - W_2|}{L_{\text{taper}}}\right)$.
- In Pass-Through mode, the rectangular slot on the angled rail web is rotated by $\phi$ to ensure the straight orthogonal rung passes through cleanly without binding.

#### Pattern 4: Orthogonal Spine & Branch (Equal & Unequal Tees, Crosses)
- Main through-run retains standard straight ladder rung pitch.
- Branch legs contain transverse rungs positioned along the branch centerline perpendicular to the main run, maintaining clearance from the corner radius junction ($R = 300\,\text{mm}$ or $600\,\text{mm}$).

---

# 11. Joint Method Must Be Stored in DDS

The user's selected welding method belongs to the DDS product instance, not the master product template.

Conceptually:

```json
{
  "instanceParameters": {
    "width": 600.0,
    "length": 3000.0,
    "endRungOffset": 50.0,
    "rungPitch": 250.0,
    "rungJointMethod": "passThroughOutsideWeld"
  }
}
```

The master template remains the reusable baseline.

Opening a DDS should:

```text
Resolve Ladder Template
        ↓
Read instance parameters
        ↓
Read Rung Joint Method
        ↓
Generate ladder assembly
        ↓
Generate joint construction
        ↓
Generate 2D / 3D
```

Changing the joint method in DDS must never modify the master DSF template.

---

# 12. DSF Representation

The DSF/assembly template architecture must support the joint method as a capability of the ladder assembly definition.

Conceptually:

```text
Ladder Assembly Template
├── Side Rail Component
├── Rung Component
├── Rung Pattern Definition
└── Supported Joint Methods
      ├── directInsideWeld
      └── passThroughOutsideWeld
```

The selected instance method is stored with the product instance.

Do not create a separate master DSF solely because the welding method changes.

---

# 13. Rung Pattern and Welding Pattern Must Remain Linked

For straight ladder, rung positions are derived from:

```text
Length
End Rung Offset
Intermediate Rung Pitch
```

The welding geometry must inherit exactly those same rung positions.

Therefore:

```text
Rung Generator
     ↓
Rung Positions
     ↓
Joint Generator
     ↓
Side-Rail Openings / Weld Locations
```

This guarantees that a rung can never be visually located at one position while its rail opening/weld location is at another.

---

# 14. 2D Flat Geometry Rules

## Direct Inside Weld

Side rails contain no rung pass-through openings.

The flat side-rail geometry remains clean except for any existing manufacturing holes/features.

## Pass-Through + Outside Weld

The side rails receive one rectangular opening per rung position.

Opening placement must:

- remain centered/aligned to the rung axis,
- remain perpendicular to the local side-rail surface where applicable,
- not intersect flange bends,
- remain inside the structural side-rail material,
- preserve required edge distances,
- follow the curved/angled side-rail path in accessories.

Do not create openings from screen coordinates.

Use the rail's local coordinate system and the rung assembly transform.

### 14.3 Side-Rail Slot Height & Bend Relief Clearance Formula

To prevent material distortion or cracking during press-brake forming of the $20\,\text{mm}$ or $32\,\text{mm}$ return flanges, pass-through slots must be positioned outside the plastic deformation zone of the bend line:

$$Y_{\text{slot\_bottom}} \ge H_{\text{flange}} + R_{\text{bend}} + 2 \cdot T_{\text{sheet}}$$

Where:
- $H_{\text{flange}}$ = bottom flange width ($20.0\,\text{mm}$ or $32.0\,\text{mm}$)
- $R_{\text{bend}}$ = inner bend radius (typically $1.0 \cdot T_{\text{sheet}} = 2.0\,\text{mm}$)
- $T_{\text{sheet}}$ = side-rail thickness ($2.0\,\text{mm}$)

*Example:* For a $32\,\text{mm}$ return flange and $2.0\,\text{mm}$ sheet:
$$Y_{\text{slot\_bottom}} \ge 32.0 + 2.0 + 2(2.0) = 38.0\,\text{mm} \text{ from the flat sheet blank bottom edge}$$

In the longitudinal direction:
$$X_{\text{first\_slot}} \ge P_{\text{end}} \ge 50.0\,\text{mm}$$
Guarantees a minimum clearance of $50\,\text{mm}$ from the rail cut edge, completely isolating the rung slots from the $75\,\text{mm}$ coupler splice zone ($4 \times \varnothing 10\,\text{mm}$ holes).

---

# 15. 3D Joint Rules

## Direct Inside Weld

```text
Rung end
   ↓
inside rail face
   ↓
weld representation
```

## Pass-Through + Outside Weld

```text
Rung
 ↓
rail opening
 ↓
outside projection
 ↓
outside weld representation
```

The two modes must use the same rung centreline and assembly positioning system.

Only the termination/joint geometry changes.

---

# 16. Weld Representation

The initial implementation does not need to become a welding simulation engine.

Use a deterministic engineering representation.

Recommended internal data:

```text
RungJoint
├── method
├── rungId
├── leftRailId
├── rightRailId
├── openingGeometryId (nullable)
├── weldLocationLeft
├── weldLocationRight
└── outsideProjection (nullable)
```

The visual representation can remain simplified.

The important requirement is that the assembly knows **where and how the joint is constructed**.

---

# 17. Generative Studio UI/UX & Workspace Layout

Because cable ladders and their accessories are 100% generative assemblies synthesized by the engineering engine, the user interface completely eliminates manual CAD drafting. The user configures engineering intent through structured controls, and the app engine instantly generates the 3D kinematic model, constituent flat blanks, and submittal sheets.

### 17.1 Studio Layout Architecture

```text
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  TruFold Studio — [ CABLE LADDER STUDIO ]                       DDS Document: TDS-2026-001 (Rev 01)     │
├──────────────┬──────────────────────────────────────────────────────────────────────────┬──────────────┤
│ LADDER       │  [PART TABS]: (●) 3D Assembly  │ ( ) Left Rail  │ ( ) Right Rail  │ ( ) Rung Blank     │ LADDER       │
│ CATALOG      ├──────────────────────────────────────────────────────────────────────────┤ INSPECTOR    │
│              │                                                                          │              │
│ ┌──────────┐ │                                                                          │ 1. SYSTEM    │
│ │ Straight │ │                                3D ISOMETRIC VIEW                         │    GEOMETRY  │
│ │ Length   │ │                                                                          │              │
│ └──────────┘ │                                                                          │ 2. TWO-PITCH │
│ ┌──────────┐ │                                                                          │    ENGINE    │
│ │ 90° Bend │ │                                                                          │              │
│ └──────────┘ │                                                                          │ 3. RUNG JOINT│
│ ┌──────────┐ │                                                                          │    & WELD    │
│ │ Inside   │ │                                                                          │              │
│ │ Riser    │ │                                                                          │ 4. ACCESSORY │
│ └──────────┘ │                                                                          │    RECIPE    │
│ ┌──────────┐ │                                                                          │              │
│ │ Outside  │ │                                                                          │ 5. FASTENERS │
│ │ Riser    │ │                                                                          │    & BOM     │
│ └──────────┘ │                                                                          │              │
│ ┌──────────┐ ├──────────────────────────────────────────────────────────────────────────┤ 6. TDS SHEET │
│ │ Reducer  │ │  HUD: L=3000mm │ W=600mm │ H=100mm │ Rungs: 12 (Pitch: 259mm) │ Joint: PASS-THROUGH     │    SUBMITTAL │
│ └──────────┘ │  [ Export All Blanks to DXF ]   [ Open in TDS Studio ]   [ 3D Explode Assembly ] │              │
└──────────────┴──────────────────────────────────────────────────────────────────────────┴──────────────┘
```

### 17.2 Center Canvas & Contextual Part Switcher

Because a ladder is a multi-body assembly, the center canvas provides an instant tab switcher across all constituent parts:

```text
[ (●) 3D Assembly ]  [ ( ) Left Rail Flat ]  [ ( ) Right Rail Flat ]  [ ( ) Rung Blank ]  [ ( ) Cover Flat ]
```

1. **`3D Assembly` View (Primary Default)**:
   - Real-time kinematic 3D mesh rendering with smooth orbit, pan, and zoom.
   - **X-Ray / Weld Highlight Toggle**: Renders semi-transparent side rails with glowing amber weld fillets (internal fillet or external protruding stubs).
   - **Explode Slider (`0% — 100%`)**: Slides left rail left, right rail right, and cover upward to visually inspect joint engagement and rung slot alignment.
2. **`Left Rail Flat` & `Right Rail Flat` Blanks**:
   - Displays 1:1 CNC turret punch / laser cutting flat blanks.
   - Renders dashed bend lines for $90^\circ$ return flanges with bend deduction callouts.
   - Renders the $4 \times \varnothing 10\,\text{mm}$ coupler splice hole matrix at both ends.
   - Displays punched $42 \times 22\,\text{mm}$ rectangular rung slots when Pass-Through mode is active.
3. **`Rung Blank`**:
   - Displays the unbent sheet-metal blank for the $40 \times 20\,\text{mm}$ C-channel.
   - Shows the two $90^\circ$ longitudinal bend lines and the centered array of $25 \times 14\,\text{mm}$ obround cable-tie punches.
   - Dynamically displays the physical cut length: `L = 611.0 mm (Qty: 12)`.
4. **Multi-Part CAM Export**:
   - Action button: `[ Export Multi-Part DXF Pack ]` exports individual production-ready DXFs: `Left_Rail.dxf`, `Right_Rail.dxf`, `Rung_Blank.dxf`, and `Cover.dxf`.

---

# 18. Ladder Assembly Inspector (Right-Hand Panel)

The inspector completely removes unrelated sheet-metal controls (such as floor bed perforations) and replaces them with dedicated ladder assembly sections:

### 18.1 Section 1: System Geometry & Rail Profile
- **Nominal Width ($W$)**: Dropdown presets ($150, 300, 450, 600, 750, 900\,\text{mm}$) + Custom numeric field.
- **Side Rail Height ($H$)**: Standard height presets ($50, 75, 100, 125, 150\,\text{mm}$).
- **Overall Length ($L$)**: Default $3000.0\,\text{mm}$ (or $6000.0\,\text{mm}$).
- **Flange Direction & Width**:
  - Width: $20.0\,\text{mm}$ or $32.0\,\text{mm}$.
  - Segmented toggle: `[ Inside Flange ]` | `[ Outside Flange ]`.
  - Bend Angle: Fixed $90^\circ$ (sheet gauge $2.0\,\text{mm}$ or $3.0\,\text{mm}$).

### 18.2 Section 2: Two-Pitch Calculation Engine
- **End Margin Pitch ($P_{\text{end}}$)**:
  - Header/footer clearance (default $75.0\,\text{mm}$, minimum $50.0\,\text{mm}$) to isolate rungs from coupler splice plates and bolts.
- **Intermediate Target Pitch ($P_{\text{target}}$)**:
  - Quick selector: `[ 150mm ]` `[ 200mm ]` `[ 250mm ]` `[ 300mm ]`.
- **Pitch Mode Toggle**:
  - `(●) Equalized Pitch`: Evenly distributes rungs across the effective span ($P_{\text{actual}} = \frac{\text{Span}}{k}$).
  - `( ) Fixed Pitch`: Strictly enforces $P_{\text{target}}$ with floating end margins.
- **Live Rung Counter Badge**: Displays green status pill, e.g. `12 Rungs (Pitch: 259.1 mm)`.

### 18.3 Section 3: Rung Joint & Welding Strategy Card

```text
┌──────────────────────────────────────────────────────────┐
│  RUNG JOINT / WELDING METHOD                             │
│                                                          │
│  [  Direct Inside Weld  ]   [★ Pass-Through + Outside W. ]│
│                                                          │
│  • Rail Punching:         Punched 42×22 mm Rect. Slots   │
│  • Outside Projection:    [ 3.5 mm ]  (Lip for Fillet)   │
│  • Rung Cut Length:       611.0 mm  (W + 2T + 2*Proj)    │
│  • Joint Strength:        High-Load / Heavy Industrial   │
└──────────────────────────────────────────────────────────┘
```

- **Interactive Switch**: Immediately re-evaluates the assembly model, 2D flat blanks, 3D meshes, and TDS notes.

### 18.4 Section 4: Cover & Fasteners HUD
- **Ladder Cover Toggle**: `[ Include Cover ]` with cover depth selector ($12\,\text{mm}$–$15\,\text{mm}$).
- **Splice Coupler End Ports**: Checkbox to toggle the $4 \times \varnothing 10\,\text{mm}$ splice hole matrix.
- **Live Hardware Tally HUD**: Displays exact count of rungs, splice couplers, M6 $\times$ 16 roofing bolts, M8 $\times$ 30 support bolts, nuts, and star washers.

---

# 19. Accessory Configuration UX (Catalog Recipes)

When configuring **Ladder Accessories** (Bends, Risers, Reducers, Tees, Crosses), manual drafting is completely replaced by **Catalog Recipe Selection**:

```text
┌────────────────────────────────────────────────────────┐
│  ADD ACCESSORY: CABLE LADDER 90° HORIZONTAL BEND       │
├────────────────────────────────────────────────────────┤
│  Catalog Standard Size:                                │
│  Radius (R):  [ 300 mm ▾ ]  (or 600 mm)                │
│  Width (W):   [ 600 mm ▾ ]  (300, 450, 600, 750, 900)  │
│  Height (H):  [ 100 mm ▾ ]                             │
│                                                        │
│  Rung Joint:  (●) Pass-Through  ( ) Direct Inside      │
│                                                        │
│  Rung Pattern Recipe:                                  │
│  • 4 Radial Rungs @ 0°, 30°, 60°, 90°                  │
│  • Tangent Extensions: 100 mm with standard splice     │
│                                                        │
│  [ Generate 3D & Add to TDS Sheet ]                    │
└────────────────────────────────────────────────────────┘
```

- **Industrial Reliability**: The user selects standard dimensions from catalog dropdowns. The engine automatically applies the validated topological recipe (radial rungs, faceted rails, rotated reducer slots, splice ports), ensuring that rung pitch and structural integrity are never violated by arbitrary freeform distortion.
- **Full Joint Flexibility**: Even on fixed catalog accessories, the user can toggle between Direct Inside Weld and Pass-Through + Outside Weld, updating the 3D model and constituent cut sheets immediately.

---

# 20. BOM, Hardware & Fastener Takeoff

The selected joint method and ladder assembly parameters directly drive the manufacturing Bill of Materials (BOM) and Hardware Takeoff:

### 20.1 Sheet Metal Component Takeoff

| Component | Quantity | Dimensions / Material | Notes |
|---|---|---|---|
| Side Rails | 2 | Length $L$, Height $H$, Thickness $T_{\text{rail}}$ | Flat blank with $90^\circ$ inside/outside return flanges |
| C-Channel Rungs | $N_{\text{rungs}}$ | $40 \times 20 \times 2.0\,\text{mm}$, Length $L_{\text{rung}}$ | $25 \times 14\,\text{mm}$ obround cable-tie punches |
| Ladder Cover | 1 (Optional) | Length $L$, Width $W + 65\,\text{mm}$, Height $12\,\text{mm}$ | Formed sheet metal cover |

Where $L_{\text{rung}}$ is dynamically computed per Section 6.4 or 7.3:
- Direct Inside Weld: $L_{\text{rung}} = W_{\text{nominal}}$
- Pass-Through + Outside Weld: $L_{\text{rung}} = W_{\text{nominal}} + 2 \cdot T_{\text{rail}} + 2 \cdot \text{outsideWeldProjection}$

### 20.2 Joint & Fabrication Operations

| Operation | Direct Inside Weld | Pass-Through + Outside Weld |
|---|---|---|
| Rail Pass-Through Slots | 0 | $2 \times N_{\text{rungs}}$ punched $42 \times 22\,\text{mm}$ slots |
| MIG Weld Joints | $2 \times N_{\text{rungs}}$ internal fillet welds | $2 \times N_{\text{rungs}}$ external fillet weld beads |
| Weld Seam Total Length | $2 \times N_{\text{rungs}} \times (2 \times 20 + 40)\,\text{mm}$ | $2 \times N_{\text{rungs}} \times 2(40 + 20)\,\text{mm}$ |

### 20.3 Standard Splice Hardware & Fastener Takeoff

Per engineering submittal standards (Bonn Metal / TruFold Submittal Pages 55–60):
- **Splice Couplers**: 2 units per ladder length ($W = 145\,\text{mm}, H = 95\,\text{mm}, T = 2.0\,\text{mm}$, 4 obrounds $20 \times 8\,\text{mm}$)
- **Coupler Fasteners**: 
  - $8 \times$ SS316 Roofing Bolts M6 $\times$ 16
  - $8 \times$ SS316 Star Washers M6
  - $8 \times$ SS316 Hex Flange Nuts M6
- **Hold-Down Clamps** (Support Fixing):
  - $2 \times$ C-clamp ($W = 40\,\text{mm}, H = H_{\text{rail}} + 5\,\text{mm}$)
  - $2 \times$ SS316 Roofing Bolts M8 $\times$ 30 + M8 Washers + M8 Nuts
- **Cover Holding Clamps** (when cover is enabled):
  - Typically 4 to 6 units per $3000\,\text{mm}$ length ($W = 30\,\text{mm}, H = H_{\text{rail}} + 15\,\text{mm}$ with M6 top bolt)

This metadata is stored directly in the evaluated assembly instance for export to Excel submittals and ERP costing.

---

# 21. TDS (Technical Data Sheet) Submittal Studio Presentation UX

In the TDS Studio tab, TruFold generates standardized engineering submittal drawings conforming to the 119-page industrial standard (Bonn Metal / TruFold Submittal Specification):

### 21.1 Automated Submittal Sheet Layout (ISO 7200 A4/A3)

```text
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ ┌───────────────────────────┐ ┌───────────────────────────────────────────────────────┐ │
│ │ SECTION VIEW: C-RUNG      │ │ MAIN ISOMETRIC VIEW                                   │ │
│ │ • 40×20 mm C-Channel      │ │ • Assembled Cable Ladder + Cover                      │ │
│ │ • Obround 25×14 mm        │ │ • Rung pitch & rail height annotations                │ │
│ │ • Flange 32 mm / H=100 mm │ │                                                       │ │
│ └───────────────────────────┘ └───────────────────────────────────────────────────────┘ │
│ ┌───────────────────────────┐ ┌───────────────────────────┐ ┌─────────────────────────┐ │
│ │ DETAIL: MIG WELDING       │ │ DETAIL: SPLICE COUPLER    │ │ DETAIL: HOLD DOWN CLAMP │ │
│ │ • Pass-Through Stub 3.5mm │ │ • 145×95 mm Coupler       │ │ • W=40 mm, H=105 mm     │ │
│ │ • External Fillet Bead    │ │ • M6×16 Roofing Bolt / Nut│ │ • M8×30 Roofing Bolt    │ │
│ └───────────────────────────┘ └───────────────────────────┘ └─────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────────────────────────────────┐ │
│ │ PROJECT DIMENSION TABLE & SCHEDULE (SN, Width, Height, Radius, Length, QTY)         │ │
│ ├──────────────────────────────────────────────────────────┬──────────────────────────┤ │
│ │ NOTES: MATERIAL HDG 2mm │ RUNG SPACING 250mm            │ CLIENT: KENT GAD         │ │
│ │ RUNG JOINT: PASS-THROUGH + OUTSIDE MIG WELDING           │ BONN METAL CONS. IND.    │ │
│ │ ALL FLANGE 32mm │ HARDWARES SS316                        │ DWG NO: TRU-LAD-01 REV:01│ │
│ └──────────────────────────────────────────────────────────┴──────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 21.2 Viewport Generation Logic

1. **Main 3D Isometric Viewport**:
   - The engine positions the camera at standard isometric azimuth/elevation ($45^\circ / 35.264^\circ$).
   - If cover is enabled, the cover is rendered either flush mounted or slightly elevated (exploded ghost view) with leader lines.
2. **Transverse Section Viewport**:
   - Automatically cuts a transverse cross-section through the ladder at a representative rung position.
   - Dimensions the $40.0\,\text{mm}$ rung width, $20.0\,\text{mm}$ rung depth, $100.0\,\text{mm}$ side-rail height, and $32.0\,\text{mm}$ return flanges.
3. **Engineering Detail Callouts**:
   - **Joint Detail**: Shows a close-up section of the rung terminating at the rail. Displays `"MIG WELDING"` callout arrow pointing to the fillet joint.
   - **Hardware Detail**: Automatically embeds standard CAD 2D/3D blocks of the M6 $\times$ 16 roofing bolt, star washer, and hex nut alongside the $145 \times 95\,\text{mm}$ coupler plate.
4. **Representative Viewport Principle for Fixed Accessories**:
   - For all fixed accessories (Bends, Risers, Reducers, Tees, Crosses), the visual viewport renders the clean canonical geometry of that family.
   - The embedded ISO 7200 table dynamically tabulates all project sizes (e.g. Row 1: $W=300, R=300$; Row 2: $W=600, R=600$; Row 3: $W=900, R=600$).
   - This eliminates the need to draw separate drawings for each width variation while delivering certified submittals.

---

# 22. Visual Micro-Feedback & Transition Animations

When the user modifies parameters in the Generative Ladder Studio:

1. **Joint Method Switch Animation (Inside $\leftrightarrow$ Outside)**:
   - When toggling from *Direct Inside Weld* to *Pass-Through + Outside Weld*, the 3D canvas plays a smooth $250\,\text{ms}$ kinematic transition:
     - Rectangular slots visually punch into the rail webs.
     - Rungs smoothly extend outward by $3.5\,\text{mm}$ through the slots.
     - Amber glowing rings illuminate around the exposed outside ends to confirm the external weld location.
2. **Interactive Rung Hover Inspector**:
   - Hovering the mouse over any individual rung in the 3D or 2D canvas highlights that rung in cyan.
   - A contextual tooltip displays: `Rung #04 | Position X: 852.3 mm | Cut Length: 611.0 mm | Welded`.
3. **Explode View Scrubbing**:
   - Scrubbing the Explode Slider from $0\%$ to $100\%$ expands the assembly along the transverse axis ($Y$) and vertical axis ($Z$), exposing the interlocking slot-and-tenon geometry clearly for QA verification.

---

# 23. Validation Rules

The generator must reject invalid assembly states before generating flat blanks or 3D meshes:

### 23.1 Pass-Through Method Validation Rules

Reject if:
1. **Bend Relief Violation**:
   $$Y_{\text{slot\_bottom}} < H_{\text{flange}} + R_{\text{bend}} + 2 \cdot T_{\text{sheet}}$$
   *(Slot edge enters the plastic bend deformation zone of the return flange).*
2. **Splice Zone Encroachment**:
   $$X_{\text{slot}} < P_{\text{end}} \quad \text{or} \quad X_{\text{slot}} > (L - P_{\text{end}})$$
   where $P_{\text{end}} < 50.0\,\text{mm}$ *(Slot collides with coupler splice plate or M6 roofing bolt heads).*
3. **Insufficient Outside Projection**:
   $$\text{outsideWeldProjection} < 2.5\,\text{mm}$$
   *(Inadequate protrusion to lay an AWS/ISO compliant external fillet weld bead).*
4. **Tooling Clearance Out of Bounds**:
   $$\text{clearance} < 0.5\,\text{mm} \quad \text{or} \quad \text{clearance} > 2.0\,\text{mm}$$

### 23.2 Direct Inside Weld Validation Rules

Reject if:
1. **Rung Length Mismatch**:
   $$|L_{\text{rung}} - W_{\text{nominal}}| > 0.5\,\text{mm}$$
   *(Rung is either too short, creating a gap exceeding weld bridge tolerance, or too long, bowing the side rails).*
2. **Out of Plane Positioning**:
   Rung contact centroid deviates from the inner rail web plane by more than $0.1\,\text{mm}$.

### 23.3 Universal Assembly Rules

Reject if:
1. Rung pitch $P_{\text{actual}} < 150.0\,\text{mm}$ (excessive weight and cable bundling constriction).
2. Rung pitch $P_{\text{actual}} > 450.0\,\text{mm}$ (exceeds NEMA VE-1 / IEC 61537 maximum unsupported cable sag limits).
3. Rung centerline and joint/opening location do not coincide.

---

# 24. Automated Tests

## Test A — Direct Inside Weld

For a straight ladder:

```text
Generate N rungs
Generate 2 side rails
Select Direct Inside Weld
```

Verify:

- N rungs exist;
- 2 rails exist;
- no rung pass-through openings are created;
- every rung terminates at the inside rail faces;
- one joint exists at each rung/rail intersection.

## Test B — Pass-Through + Outside Weld

Verify:

- N rungs exist;
- 2 rails exist;
- 2 × N rail openings exist;
- every rung passes through both rails;
- every rung has an outside projection;
- outside weld locations correspond to the rung endpoints.

## Test C — Pattern Integrity

Change:

```text
Length
End Offset
Pitch
```

Verify that rung positions update and all joint/opening positions follow automatically.

## Test D — Width Change

Change ladder width.

Verify:

- side-rail separation updates;
- rung length updates;
- joint positions remain correctly attached to rails;
- no opening/weld is left behind.

## Test E — Method Switch

```text
Direct Inside Weld
→ Pass Through + Outside Weld
→ Direct Inside Weld
```

The final assembly must be geometrically equivalent to a fresh Direct Inside Weld evaluation from the same template and parameter state.

## Test F — DDS Round Trip

```text
Create Ladder
→ select joint method
→ save DDS
→ close
→ reopen DDS
```

Verify that the exact joint method and resulting assembly state are restored.

## Test G — Legacy Ladder DDS/DSF

Existing ladder documents without the new parameter must continue loading.

Use a safe default declared by the product contract.

Do not silently assume a manufacturing method if the existing document already contains enough information to determine one.

---

# 25. Backward Compatibility

Existing ladder DSFs must remain valid.

Existing DDS files without `rungJointMethod` must remain valid.

Recommended loading behaviour:

```text
No stored joint method
        ↓
Use product-contract default
        ↓
Mark value as Template Default
```

The default must be explicitly defined per ladder product family rather than hard-coded globally if manufacturing conventions differ.

---

# 26. Recommended Architecture & Multi-Body Assembly Model

```text
LadderAssemblyGenerator
│
├── SideRailGenerator (Left & Right Rails)
│     ├── Flange Profile & Bend Line Engine
│     ├── Splice Hole Pattern (4× Ø10mm / 20×8mm obrounds)
│     └── Pass-Through Rectangular Punch Pattern (if Pass-Through)
│
├── RungGenerator (C-Channel blanks)
│     ├── 40×20mm Profile Unfold
│     ├── 25×14mm Obround Punch Array
│     └── Length Solver (W vs W + 2T + 2*Projection)
│
├── RungPatternGenerator
│     ├── Two-Pitch Solver (P_end vs P_mid)
│     └── Trajectory Classifier (Straight, Radial, Slope, Tapered, Orthogonal)
│
└── RungJointGenerator
      ├── DirectInsideWeldJoint (flush fit, internal fillet)
      └── PassThroughOutsideWeldJoint (clearance slot, outside projection, external fillet)
```

### 26.1 Multi-Body Data Contract (`DsfLadderAssembly`)

Unlike single-body tray fittings, a ladder is an assembly yielding multiple manufacturable sheet-metal blanks:

```dart
class DsfLadderAssembly {
  final String id;
  final String productName;
  final LadderAssemblyParameters parameters;
  
  // Constituent manufacturable blanks for CAM / Turret Punch / Laser nesting
  final CadPart leftRailBlank;
  final CadPart rightRailBlank;
  final CadPart rungBlank; // Canonical 40x20 C-channel flat blank
  final CadPart? coverBlank; // Formed cover blank (optional)
  
  // Spatial 3D / Assembly relationships
  final List<LadderRungInstance> rungInstances;
  final List<LadderJointInstance> jointInstances;
  final List<CmsPhysicalPort> splicePorts; // Rail end ports for couplers
  
  // Assembled 3D Mesh for viewport & TDS rendering
  final FoldedMeshResult assembledMesh3D;
  final FoldedMeshResult? coverMesh3D;
}
```

### 26.2 Dual Export Pipeline: CAM Nesting vs. TDS Presentation

```text
                         LadderAssemblyGenerator
                                   │
         ┌─────────────────────────┴─────────────────────────┐
         ▼                                                   ▼
  [CAM / Nesting Export]                            [TDS Presentation Engine]
  • leftRailBlank.dxf                               • Clean 3D Isometric View
  • rightRailBlank.dxf                              • Transverse Section View
  • rungBlank.dxf × N_rungs                         • Dynamic Dimension Table
  • coverBlank.dxf (optional)                       • Hardware & Weld Callouts
```

---

# 27. Important Separation of Concerns

Keep these concepts separate:

```text
Rung Profile
≠
Rung Position
≠
Side Rail Profile
≠
Joint Method
≠
Weld Representation
```

Changing the welding method must not alter the rung profile or rung pitch.

Changing rung pitch must automatically relocate the joints/openings.

Changing side-rail flange angle must regenerate rail/joint geometry through the existing flange system.

---

# 28. Roadmap: Preparation for Phase 2 (Fittings & Fasteners)

Following completion of the Ladder & Accessory assemblies, the architecture seamlessly accommodates the downstream fittings and hardware ecosystem:

### 28.1 Pre-Engineered Attachment Ports

1. **Splice Connection Ports (Couplers)**:
   - The ends of both side rails feature a standard $4 \times \varnothing 10\,\text{mm}$ (or $20 \times 8\,\text{mm}$ obround) hole matrix with $75\,\text{mm}$ vertical center-to-center and $40\,\text{mm}$ longitudinal spacing.
   - When the Coupler module is activated, **Straight Couplers** (Page 55), **Expansion Couplers** (Page 56), **Adjustable Horizontal Couplers** (Page 58), and **Adjustable Vertical Couplers** (Page 57) attach directly to these pre-defined ports.
2. **Support Clamping Zones (Hold-Down Clamps & Baseposts)**:
   - The bottom return flange ($20\,\text{mm}$ or $32\,\text{mm}$) establishes continuous clamp zones where **Cable Ladder Hold-Down Clamps** (Page 59, $W = 40\,\text{mm}$, with M8 $\times$ 30 roofing bolts) grip the ladder to structural cantilever arms or floor baseposts.
3. **Cover Retention Interface (Cover Holding Clamps)**:
   - The top return flange lip accepts wrap-around **Cable Ladder Cover Holding Clamps** (Page 60, $W = 30\,\text{mm}, H = H_{\text{rail}} + 15\,\text{mm}$) secured with an M6 top clamping bolt.

### 28.2 Automated Fastener BOM Engine

The assembly data model directly exposes exact fastener counts:
- M6 $\times$ 16 Roofing Bolts, Star Washers & Hex Nuts (Couplers)
- M8 $\times$ 30 Roofing Bolts, Washers & Hex Nuts (Hold-Down Clamps)
- M6 Clamping Fasteners (Cover Clamps)

---

# 29. Agent Instructions — Do Not Over-Engineer

1. Do not rebuild the existing ladder side-rail flange system.
2. Do not replace the existing rung C-channel component.
3. Do not turn fixed ladder accessories into freely scalable fittings.
4. Do not create separate duplicate rung libraries for the two welding methods.
5. Do not stretch or distort the rung profile.
6. Generate all joint/opening geometry from the actual rung assembly positions.
7. Do not use screen coordinates to place rail openings.
8. Keep joint method as an assembly/product-instance parameter.
9. Store the selected method in DDS, not in the master template as a user override.
10. Rebuild from the canonical template/assembly definition for each parameter state.
11. Keep unsupported joint methods unavailable in the UI.
12. Preserve backward compatibility with existing DSF/DDS ladder documents.

---

# 30. Acceptance Criteria

The feature is complete when:

1. The user can select **Direct Inside Weld** or **Pass Through + Outside Weld** where the product supports both.
2. The selected method updates the complete ladder assembly immediately.
3. Direct Inside Weld creates rung-to-inner-rail joints without pass-through openings.
4. Pass Through + Outside Weld creates rectangular rail openings for each rung and an outside rung projection/weld location.
5. Rung position/count remains controlled by the existing ladder pitch and length logic.
6. Width changes continue to update rung length and rail separation correctly.
7. The joint/opening locations always follow the rung positions.
8. 2D and 3D views show the selected construction method correctly.
9. DDS stores the selected joint method as an instance value.
10. The master ladder template remains unchanged.
11. TDS displays the selected rung joint method and derived assembly information.
12. BOM/manufacturing metadata can determine the relevant joint/opening/weld counts.
13. Legacy DSF/DDS documents continue to open correctly.
14. Switching methods and then returning to the original method produces the same result as a fresh baseline evaluation.

---

# 31. Final Principle

> **A ladder rung is a reusable physical component. The welding method is an assembly-level construction rule that determines how that rung terminates at the side rail. Direct Inside Weld terminates the rung at the inside rail face; Pass Through + Outside Weld cuts a rectangular opening in the rail, passes the rung through it, and welds the exposed outside end. The same rung pattern and side-rail assembly system must support both methods without duplicating the component library.**
