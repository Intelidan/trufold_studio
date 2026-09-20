# TRUFOLD CMS TEMPLATE SEED ARCHITECTURE
## "Teach This Product Once" — Architectural Specification & Product Roadmap

**Document Version:** 1.0  
**Status:** Approved Architectural Standard  
**Target System:** TruFold Studio CMS Engine (Cable Tray, Trunking, Fittings & Accessories)

---

## 1. Executive Summary & Paradigm Shift

### The Problem with Generic Geometric Heuristics
Previously, the system attempted to infer manufacturing bend lines directly from raw 2D DXF boundary silhouettes using generic geometric heuristics (`DxfAutoFoldEngine.detectCandidateLines`). 

A raw 2D DXF contour contains **geometry without manufacturing intent**. A line or notch pair on a flat sheet cannot unambiguously convey whether it is intended to be a 90° transverse bend, a 45° miter bend, a return flange lip, a construction line, or a relief boundary. This resulted in brittle behavior, such as generating a **65-line spiderweb connecting every dot to every other dot** on a 45° Inside Riser.

Writing separate hard-coded geometric detectors for every catalog fitting (e.g. `_detectBend45`, `_detectBend90`, `_detectInsideRiser`, `_detectOutsideRiser`, `_detectReducer`, `_detectTee`, `_detectCross`, `_detectCover`, etc.) is an anti-pattern that leads to severe maintenance debt.

### The Solution: "Teach This Product Once" (Template Seed)
In commercial cable management manufacturing, there are a finite number of standard product families and variations (~150 standard variations in total). 

Instead of asking a generic algorithm to guess manufacturing intent from ambiguous 2D contours:
1. **The user defines the manufacturing intent ONCE** (bends, flanges, and coupler slots). In the Studio's intuitive 2D canvas, this takes under 30 seconds.
2. TruFold converts that marked flat blank into an authoritative **Intelligent Template Seed (`.dsf`)**.
3. TruFold's 3D-first topological engine takes over: folding the model in 3D, automatically detecting physical channel mouths (ports), calculating exact opening dimensions, normals, and pinning callouts.
4. The user teaches the scaling behavior once (Phase 2), turning the seed into a fully parametric **Intelligent Template**.

---

## 2. Clean Separation of Responsibilities

The boundary between human expertise and automated computation is strictly decoupled:

```
┌────────────────────────────────────────────────────────┐
│               USER RESPONSIBILITY                      │
│           (Manufacturing Design Intent)                │
├────────────────────────────────────────────────────────┤
│  ✓ Mark / Confirm Bend Lines & Angles (e.g. 90°, 45°) │
│  ✓ Mark / Confirm Return Flange Lines (90° lips)      │
│  ✓ Identify / Confirm Coupler Slot Groups             │
└────────────────────────────────────────────────────────┘
                           │
                           ▼ (3D Kinematic Fold)
┌────────────────────────────────────────────────────────┐
│             TRUFOLD ENGINE RESPONSIBILITY              │
│       (3D Topology, Apertures & Spatial Reasoning)     │
├────────────────────────────────────────────────────────┤
│  ✓ Planar Face Decomposition (Floor, Sidewalls, Lips) │
│  ✓ 3D Kinematic Forward-Folding                       │
│  ✓ 3D Physical Opening Mouth Discovery                │
│  ✓ Port Dimensions (W × H), Normals & 3D Corners       │
│  ✓ 3D Callout Pinning & 2D Badge Synchronization       │
│  ✓ Feature-to-Face Spatial Anchoring                  │
└────────────────────────────────────────────────────────┘
                           │
                           ▼ (Phase 2)
┌────────────────────────────────────────────────────────┐
│             GENERIC SCALING ENGINE                     │
│               (Semantic Zone Morphing)                 │
├────────────────────────────────────────────────────────┤
│  ✓ Stretch Zones (e.g. Floor Web expands)             │
│  ✓ Translation Zones (e.g. Sidewalls translate rigidly)│
│  ✓ Rigid Feature Groups (e.g. Coupler slots stay fixed)│
│  ✓ Derived Ports (3D channel mouths dynamically adapt) │
└────────────────────────────────────────────────────────┘
```

> **Core Principle**: The user defines **how the flat sheet folds**. TruFold determines **what physical openings emerge from that folded object**. The user never has to manually define, measure, or draw 3D ports.

---

## 3. The 3 Levels of Automation

TruFold formalizes product automation into three distinct operational tiers:

```
                          NEW CMS PRODUCT
                                 │
                                 ▼
                         PRODUCT INTENT
                                 │
                 ┌───────────────┴───────────────┐
                 │                               │
          TEMPLATE EXISTS                 NO TEMPLATE
                 │                               │
                 ▼                               ▼
       LEVEL 1: KNOWN TEMPLATE          LEVEL 3: GUIDED SEED
       (Full Instant Auto)              (Teach Once UX)
                 │                               │
                 │                         User marks:
                 │                         • Bends (3)
                 │                         • Flanges (2)
                 │                         • Couplers (1 group)
                 │                               │
                 └───────────────┬───────────────┘
                                 │
                                 ▼
                     LEVEL 2: SIMILAR TEMPLATE
                     (Semantic Transfer & Check)
                                 │
                                 ▼
                        3D KINEMATIC FOLD
                                 │
                                 ▼
                    AUTOMATIC 3D PORT DISCOVERY
                                 │
                                 ▼
                     TOPOLOGY VALIDATION PASSED
                                 │
                                 ▼
                        SAVE TEMPLATE SEED
                                 │
                                 ▼
                           TEACH SCALING
                                 │
                                 ▼
                       INTELLIGENT TEMPLATE
```

### Level 1: Known Template (Pre-Learned)
- **Condition**: An exact intelligent template exists in the catalog (e.g. `45_deg_bend_100x100`).
- **Behavior**: Instant 100% automated processing. Recognizes geometry, applies verified bends/flanges, folds in 3D, derives ports, and enables parametric scaling immediately.

### Level 2: Similar Template (Semantic Transfer)
- **Condition**: A template seed exists for the product family (e.g. `45_deg_inside_riser_100x100`), but incoming DXF has different dimensions (e.g. `45_deg_inside_riser_150x100`).
- **Behavior**: TruFold compares topological contours, transfers the semantic bend/flange/slot relationships from the seed, and validates against the product contract.
  - If confidence is high (≥ 90%): Proceeds automatically.
  - If confidence is moderate: Displays clean prompt: *"Recognized 45° Inside Riser structure; please confirm 1 bend line."*

### Level 3: New Template (Guided Seed Authoring)
- **Condition**: A product family never seen before (e.g. first time importing a new riser or reducer).
- **Behavior**: The app **does not** dump a 65-line spiderweb. Instead, it enters **Guided Template Seed Authoring**:
  1. User confirms product classification (Category, Product Type, Variation).
  2. User marks bends and flanges on canvas (or confirms obvious candidates).
  3. User confirms coupler punch group.
  4. TruFold folds in 3D, discovers ports, and saves the **Template Seed DSF**.
  5. The user is prompted: *"✦ TruFold Learned This Part. Ready to Teach Scaling →"*.

---

## 4. Lifecycle of a Sheet Metal Fitting

```
RAW DXF (Geometry Only)
   │
   ▼
TEACH ONCE (User marks 3 bends, 2 flanges, coupler slots)
   │
   ▼
TEMPLATE SEED DSF (Geometry + Manufacturing Semantics)
   │
   ▼
3D FOLD & AUTOMATIC PORT DISCOVERY (Apertures, dimensions, normals, corners)
   │
   ▼
TEMPLATE READY (Verified baseline DSF)
   │
   ▼
TEACH SCALING (Generic Stretch, Translate, Rigid, Derived zones)
   │
   ▼
INTELLIGENT TEMPLATE (Fully parametric, scalable product)
```

---

## 5. Generic Scaling Engine vs. Hard-Coded Morphers

### The Anti-Pattern: Hard-Coded Product Morphers
Writing individual functions like `_morphInsideRiser()`, `_morphOutsideRiser()`, `_morphTee()`, `_morphCross()` creates exponential code bloat.

### The Standard: Generic Semantic Zone Scaling
Every sheet metal fitting in cable management can be decomposed into 4 universal zone types:

1. **Stretch Zones**:
   - Planar faces that expand along an axis (e.g. floor web expands along X/transverse axis when Width increases).
2. **Translation Zones**:
   - Rigid faces and bend lines that shift outward as a unit (e.g. standing sidewalls and return flanges translate rigidly by `delta / 2` without stretching).
3. **Rigid Feature Groups**:
   - Fastener patterns (e.g. coupler slots, earth studs) that maintain exact internal geometry and a fixed distance from reference edges.
4. **Derived 3D Ports**:
   - Channel mouths whose geometry is not hardcoded, but derived mathematically from the folded 3D rim boundary after morphing.

---

## 6. Pipeline Modifications Required

### 1. Prune Raw Geometric Heuristics from Guided CMS
- **File**: `lib/sheet_metal_studio/engine/cms/cms_guided_ux_controller.dart`
- **Change**: Remove the fallback call to `DxfAutoFoldEngine.detectCandidateLines(contour)` that produced the 65-line spiderweb.
- **New Behavior**:
  - If document has bends: validate against contract and proceed immediately to 3D folding.
  - If document has no bends: transition to **Guided Seed Authoring**, cleanly prompting the user to mark bends and flanges using the canvas CAD tools.

### 2. Isolate Legacy Geometric Algorithms
- **File**: `lib/sheet_metal_studio/engine/dxf_auto_fold_engine.dart`
- **Change**: Keep `detectCandidateLines` strictly isolated for optional one-off interactive CAD snapping or manual proximity aids. Never allow it to dump unpruned candidate lines into the automated CMS state machine.

### 3. Expand Product Contracts
- **File**: `lib/sheet_metal_studio/models/cms/cms_product_contract.dart`
- **Additions**:
  - `insideRiser45` (45° Inside Riser): 2 ports, 3 structural bends (two 90°, one 45°), 2 flanges (90°).
  - `insideRiser90` (90° Inside Riser): 2 ports, 3 structural bends (two 90°, one 90°), 2 flanges (90°).
  - `outsideRiser45` (45° Outside Riser): 2 ports, 3 structural bends, 2 flanges.
  - `outsideRiser90` (90° Outside Riser): 2 ports, 3 structural bends, 2 flanges.
- **Inference Disambiguation**: Ensure `"riser"` keywords are matched before generic angle numbers (`"45"`, `"90"`).

### 4. Stage 2 UX Modernization
- **File**: `lib/sheet_metal_studio/views/widgets/guided_cms/cms_guided_stage_card.dart`
- **UX States**:
  - **High Confidence**: *"✓ Found bend structure (3 Bends, 2 Flanges). [Use Structure]"*
  - **New Product / No Bends**: *"New CMS Product: Let's teach TruFold this bend structure once. [Start Guided Definition]"*
  - **Completion Card**: *"✦ TruFold Learned This Part: 3 Bends, 2 Flanges, 2 Ports, 1 Coupler Group. [Teach Scaling →]"*

---

## 7. Immediate Next Steps for Inside Riser

1. Implement the pipeline update in `CmsGuidedUxController` and `CmsProductContract`.
2. Load the 45° Inside Riser with the user-defined bends and flanges from SS2.
3. Verify that `KinematicFoldEngine` folds the 3-bend + 2-flange riser into 3D.
4. Verify that `Cms3DOpeningDetector` and `CmsOpeningPlaneAnalyzer` automatically discover the 2 ports (Port 1 horizontal mouth, Port 2 angled 45° mouth).
5. Save the verified document as `assets/dxf_templates/trunking_accessories/45_deg_inside_riser_100x100.dsf` — establishing the authoritative **Template Seed**.
