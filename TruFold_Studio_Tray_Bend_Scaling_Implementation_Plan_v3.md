# TruFold Studio — Tray Accessories 45° & 90° Bend
# Parametric Scaling Implementation Plan (v3.5 — Production Specification)

---

## 1. Executive Summary & Drawing Forensic Analysis

A forensic analysis of the 5 reference PDF drawings and their corresponding master `.dsf` templates in `assets/dsf_templates/tray_accessories/`:
- **Page 1**: `45_deg_bend_100x50.dsf` ($W=100$, $H=50$, $R=300$)
- **Page 2**: `90_deg_bend_100x50.dsf` ($W=100$, $H=50$, $R=300$)
- **Page 3**: `45_deg_bend_100x100.dsf` ($W=100$, $H=100$, $R=300$)
- **Page 4**: `90_deg_bend_100x100.dsf` ($W=100$, $H=100$, $R=300$)
- **Page 5**: `45_deg_bend_450x50.dsf` ($W=450$, $H=50$, $R=300$)

### Key Geometric Findings:
1. **Inside Wall B1 is Invariant to Width $W$**:
   In `45_deg_bend_100x50.dsf`, $L_{B1} = 200.00\text{ mm}$.
   In `45_deg_bend_450x50.dsf`, $L_{B1} = 200.00\text{ mm}$ ($\Delta L = 0.00\text{ mm}$).
   In `90_deg_bend_100x50.dsf`, $L_{B1} = 200.00\text{ mm}$.
   $B1$ forms the inside throat chord of the bend; it depends solely on the inside bend radius $R$ and the straight port extension lengths, completely independent of channel width $W$.

2. **Port Opening Direction & Width**:
   Each port is inclined at $\theta_p = \alpha / 2$ ($22.5^\circ$ for 45° bend, $45.0^\circ$ for 90° bend).
   Port opening vector length is exactly equal to channel width $W$ ($100.0\text{ mm}$ and $450.0\text{ mm}$).

3. **Unified Analytical Wing Growth ($K_{\text{wing}}$)**:
   The wing panel length along its angled bend line follows a single analytical relationship for both bend angles:
   $$\theta_p = \frac{\alpha}{2}$$
   $$K_{\text{wing}}(\theta_p) = \tan(\theta_p) \times (1 - \sin\theta_p)$$
   - **45° Bend** ($\theta_p = 22.5^\circ$):
     $$K_{\text{wing}}(45^\circ) = \tan(22.5^\circ) \times (1 - \sin 22.5^\circ) = (\sqrt{2}-1)(1 - \sin 22.5^\circ) \approx 0.2557009$$
     $W=100 \rightarrow L_{\text{wing}} = 49.70\text{ mm}$, $W=450 \rightarrow L_{\text{wing}} = 139.17\text{ mm}$ ($\Delta L = 89.47\text{ mm} \approx 350 \times 0.2557$).
   - **90° Bend** ($\theta_p = 45.0^\circ$):
     $$K_{\text{wing}}(90^\circ) = \tan(45^\circ) \times (1 - \sin 45^\circ) = 1.0 \times \left(1 - \frac{\sqrt{2}}{2}\right) \approx 0.2928932$$
     $W=100 \rightarrow L_{\text{wing}} = 66.10\text{ mm}$.

4. **Base Span Redistribution ($L_{B2}$)**:
   The bottom outer wall consists of three segments: Left Wing ($B3$), Center Base Wall ($B2$), and Right Wing ($B4$).
   The wings project inward along the transverse axis by:
   $$\Delta X_{\text{wing}} = L_{\text{wing}} \cos\theta_p$$
   As wings grow, they take up width from the center base wall $B2$:
   $$L_{B2} = (P_{2,\text{in},x} - P_{1,\text{in},x}) - 2 \times \Delta X_{\text{wing}}$$
   **The straight base span is explicitly reduced by the wings' transverse take-up.**

5. **Coupler Hole Pattern (Rows $\times$ Columns)**:
   - **Sidewall Height Rows**: $N_{\text{rows},H} = \max(1, \lfloor H / 50 \rfloor)$ with vertical pitch **$50.0\text{ mm}$**.
   - **Wing Width Columns**: $N_{\text{cols},W} = (W \ge 300\text{ mm} ? 2 : 1)$ with longitudinal pitch **$50.0\text{ mm}$** along the wing bend line.
   - **Grid Multiplication**: Each wing contains a total of $N_{\text{rows},H} \times N_{\text{cols},W}$ coupler positions (e.g. for $450\times 100$: $2 \times 2 = 4$ positions per wing).
   - Inside wall $B1$ rows are driven **exclusively by $H$** (1 row for $H=50$, invariant to $W$).

---

## 2. Parameter Definitions & Constraints

| Parameter | Symbol | Range | Step | Default | Notes |
|---|---|---|---|---|---|
| **Tray Width** | $W$ | $50.0\text{ mm} - 900.0\text{ mm}$ | $25.0\text{ mm}$ | $100.0\text{ mm}$ | Channel width at port openings |
| **Flange Height** | $H$ | $50.0\text{ mm} - 150.0\text{ mm}$ | $25.0\text{ mm}$ | $50.0\text{ mm}$ | **Min = 50 mm** (preserves 38 mm slot setback) |
| **Bend Radius** | $R$ | $300.0\text{ mm} - 1000.0\text{ mm}$ | $50.0\text{ mm}$ | $300.0\text{ mm}$ | Inside throat radius; quick buttons `[300, 600, 900]` |
| **Bend Angle** | $\alpha$ | $\{45.0^\circ, 90.0^\circ\}$ | Fixed | Product | Fixed by fitting product definition |

> [!IMPORTANT]
> **Minimum Height Invariant ($H \ge 50.0\text{ mm}$)**:
> In the master templates, the coupler slot center is placed at $Y = 38.0\text{ mm}$ from the top edge ($12.0\text{ mm}$ setback from the bend line). A height of $H=25\text{ mm}$ would place the hole outside the sidewall sheet. Therefore, the supported height range for cable tray bends is strictly $H \in [50.0, 150.0]\text{ mm}$.

---

## 3. Four-Tier Modular Solver Architecture

To keep the scaler decoupled, testable, and clean, the scaling pipeline is divided into four distinct solver functions:

```text
User Parameters: (W, H, R, α)
        │
        ├──> 1. solveBendRadius(R, α) ───────────> B1 length, throat arc, outer port corners (P1out, P2out)
        │
        ├──> 2. solveWingGeometry(W, R, α) ──────> Wing length L_wing, inner port corners (P1in, P2in), wing vectors
        │
        ├──> 3. solveBaseRedistribution(...) ───> Straight base span L_B2, floor contour, B2/FL4 endpoints
        │
        └──> 4. solveCouplerPattern(W, H, α) ────> Rows × Cols grid on standing walls and wings
```

### 3.1 `solveBendRadius(double radius, double bendAngleDeg)`
- **Rule**: $B1$ is invariant to $W$.
- **Baseline Anchor**: At $R = 300.0\text{ mm}$, $L_{B1} = 200.00\text{ mm}$ exactly matching the master template.
- **Radius Scaling ($R > 300\text{ mm}$)**:
  $$\theta_p = \frac{\alpha}{2}$$
  $$\Delta R = R - 300.0$$
  The throat chord $L_{B1}$ and outer port endpoints scale with $\Delta R$ based on the bend tangent offset:
  $$L_{B1}(R) = L_{B1,\text{base}} + 2 \times \Delta R \times \tan\left(\frac{\theta_p}{2}\right)$$
- Output:
  - $L_{B1}(R)$
  - Outer port endpoints:
    $$P_{1,\text{out}} = \left( X_{\text{mid}} - \frac{L_{B1}(R)}{2}, \, Y_{B1} \right), \quad P_{2,\text{out}} = \left( X_{\text{mid}} + \frac{L_{B1}(R)}{2}, \, Y_{B1} \right)$$

### 3.2 `solveWingGeometry(double width, double radius, double bendAngleDeg, ...)`
- **Port Inner Corners**:
  $$P_{1,\text{in}} = P_{1,\text{out}} + \left( -W \sin\theta_p, \, W \cos\theta_p \right)$$
  $$P_{2,\text{in}} = P_{2,\text{out}} + \left( W \sin\theta_p, \, W \cos\theta_p \right)$$
- **Analytical Wing Growth**:
  $$K_{\text{wing}}(\theta_p) = \tan(\theta_p) \times (1 - \sin\theta_p)$$
  $$L_{\text{wing}}(W, R) = L_{\text{wing,base}} + K_{\text{wing}}(\theta_p) \times (W - 100.0) + \Delta L_{\text{wing}}(R)$$
  - For 45° bend: $K_{\text{wing}} \approx 0.2557009$
  - For 90° bend: $K_{\text{wing}} \approx 0.2928932$
- **Wing Inner Corner Points** (where wings meet center base wall $B2$):
  $$C_1 = P_{1,\text{in}} + L_{\text{wing}} \times \left( \cos\theta_p, \, \sin\theta_p \right)$$
  $$C_2 = P_{2,\text{in}} + L_{\text{wing}} \times \left( -\cos\theta_p, \, \sin\theta_p \right)$$

### 3.3 `solveBaseRedistribution(CadPoint2D p1In, CadPoint2D p2In, double lWing, double theta_p)`
- **Transverse Take-Up**:
  $$\text{WingTakeUp} = L_{\text{wing}} \cos\theta_p$$
- **Straight Base Span $L_{B2}$**:
  $$Y_{B2} = C_{1,y} = C_{2,y}$$
  $$L_{B2} = (P_{2,\text{in},x} - P_{1,\text{in},x}) - 2 \times \text{WingTakeUp}$$
- **Invariant**:
  $$\text{WingTakeUp} + L_{B2} + \text{WingTakeUp} \equiv P_{2,\text{in},x} - P_{1,\text{in},x}$$
  As $W$ increases, wings lengthen and project further inward, directly consuming the available base span and narrowing $B2$ relative to the total envelope.

### 3.4 `solveCouplerPattern(double width, double height, double bendAngleDeg)`
- **Formula**:
  $$\text{WingHeightRows} = \max(1, \lfloor H / 50 \rfloor)$$
  $$\text{WingColumns} = \begin{cases} 1 & \text{if } W < 300.0\text{ mm} \\ 2 & \text{if } W \ge 300.0\text{ mm} \end{cases}$$
  $$\text{TotalWingHolePositions} = \text{WingHeightRows} \times \text{WingColumns}$$

- **Coupler Grid Table**:

| Width ($W$) | Height ($H$) | Height Rows | Wing Columns | Holes per Wing | Holes on Inside Wall $B1$ |
|---|---|---|---|---|---|
| $100\text{ mm}$ | $50\text{ mm}$ | 1 | 1 | **1 set** (2 slots) | 1 row (4 slots: 2 left, 2 right) |
| $100\text{ mm}$ | $100\text{ mm}$ | 2 | 1 | **2 sets** (4 slots) | 2 rows (8 slots: 4 left, 4 right) |
| $100\text{ mm}$ | $150\text{ mm}$ | 3 | 1 | **3 sets** (6 slots) | 3 rows (12 slots) |
| $300\text{ mm}$ | $50\text{ mm}$ | 1 | 2 | **2 sets** (4 slots) | 1 row (4 slots) |
| $450\text{ mm}$ | $50\text{ mm}$ | 1 | 2 | **2 sets** (4 slots) | 1 row (4 slots) |
| $450\text{ mm}$ | $100\text{ mm}$ | 2 | 2 | **4 sets** (8 slots) | 2 rows (8 slots) |
| $450\text{ mm}$ | $150\text{ mm}$ | 3 | 2 | **6 sets** (12 slots) | 3 rows (12 slots) |

- **Spacing & Setbacks**:
  - Vertical row pitch on all standing walls: **$50.0\text{ mm}$**
  - Wing column shift along wing bend line: **$50.0\text{ mm}$** ($\vec{v} = 50.0 \times (\cos\theta_p, \sin\theta_p)$)
  - Center wall $B2$: 0 coupler holes.

---

## 4. UI Architecture & Integration

### 4.1 DSF Fittings & Template Inspector (`dxf_fitting_parameter_dialog.dart`)
- **Location**: Section 2 (Port Parameters & Edge Assignment) when the loaded fitting is a Tray Bend (45° or 90°).
- **Controls**:
  ```text
  ┌─────────────────────────────────────────────────────────────┐
  │ 📐 Bend Radius (Inside Throat)                     [600 mm] │
  │ ───●─────────────────────────────────────────────────────── │
  │ 300 mm                                              1000 mm │
  │                                                             │
  │ [ 300 mm ]          [ 600 mm ]          [ 900 mm ]          │
  └─────────────────────────────────────────────────────────────┘
  ```
- **Slider**: Range `300.0` to `1000.0`, step `50.0`.
- **Quick-Set Buttons**: One-touch selection for `300 mm`, `600 mm`, and `900 mm`.
- **State Handling**: Updates `DsfFittingMetadata.instanceParameters['radius']` and triggers real-time 2D/3D kinematic regeneration.

### 4.2 TDS Studio Parameters Panel
- **`dds_parameter_table.dart`**:
  - Expose `Bend Radius` as an editable parameter (`ParameterSource.instanceEditable`) for bend fittings.
- **`dds_cms_parameter_inspector.dart`**:
  - Render the Radius slider and quick-action chips directly below MOUTH ($W \times H$) controls for `flatBend45` and `flatBend90`.
  - Derived parameters (Straight Base Span, Wing Panel Length, Coupler Holes Count) are rendered as read-only engineering badges.

---

## 5. Verification & Acceptance Test Suite

| Test ID | Test Configuration | Expected Verification Criteria |
|---|---|---|
| **TC-01** | $100 \times 50$, $R=300$, $45^\circ$ | **Exact baseline reproduction**: $L_{B1} = 200.00$, $L_{\text{wing}} = 49.70$, $L_{B2} = 184.70$, 1 row on $B1$, 1 column on wings. |
| **TC-02** | $100 \times 100$, $R=300$, $45^\circ$ | **Height scaling**: $B1$ has 2 rows (pitch 50 mm); wings have 2 rows $\times$ 1 col = 2 sets; $L_{B1} = 200.00$. |
| **TC-03** | $450 \times 50$, $R=300$, $45^\circ$ | **Wing doubling & base reduction**: $B1$ has 1 row ($L_{B1} = 200.00$); wings have 1 row $\times$ 2 cols = 2 sets (pitch 50 mm); $L_{\text{wing}} \approx 139.17$; base $L_{B2} \approx 287.45$. |
| **TC-04** | $450 \times 100$, $R=300$, $45^\circ$ | **Combined $2 \times 2$ grid**: Wings have 2 rows $\times$ 2 cols = 4 sets (8 slots per wing); $B1$ has 2 rows. |
| **TC-05** | $100 \times 50$, $R=300$, $90^\circ$ | **90° baseline reproduction**: $L_{B1} = 200.00$, $L_{\text{wing}} = 66.10$, $L_{B2} = 247.94$, 1 row $\times$ 1 col on wings. |
| **TC-06** | $450 \times 50$, $R=300$, $90^\circ$ | **90° wing doubling**: $K_{\text{wing}} = 0.29289$; wings double to 2 columns; base $B2$ span reduced accordingly. |
| **TC-07** | $100 \times 50$, $R=600 / 900$, $45^\circ$ | **Radius expansion**: $L_{B1}$ expands smoothly with $\Delta R$; hole counts remain invariant to $R$. |
| **TC-08** | Invariant check | $\forall W$: $(2 \times L_{\text{wing}} \cos\theta_p) + L_{B2} \equiv P_{2,\text{in},x} - P_{1,\text{in},x}$ within $0.05\text{ mm}$ tolerance. |
