# TruFold Studio — CMS Legacy Implementation Audit & Isolation Matrix

**Document Reference**: `docs/CMS_LEGACY_IMPLEMENTATION_AUDIT.md`  
**Execution Date**: September 16, 2026  
**Status**: AUDITED & ISOLATED  
**Architecture Context**: `TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md` & `TRUFOLD_AUTOMATIC_GUIDED_UX_WALKTHROUGH.md`

---

## Executive Summary

This audit establishes a clean architectural reset prior to implementing the new **Automatic 3D Port Discovery, Semantic Port Assignment, and Constraint-Driven Scaling** system. 

The previous CMS implementation is designated as an **isolated prototype**. The proven CAD foundation, kinematic sheet-metal engine, 3D viewport, and core DSF format remain intact and protected. Fragile 2D manual port-edge marking, dark modal dialogs, and transient wizard states in DSF metadata are isolated and slated for clean replacement.

---

## 1. The Four-Category Isolation Matrix

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             LEGACY AUDIT MATRIX                             │
└─────────────────────────────────────────────────────────────────────────────┘
  KEEP (Core CAD Foundation)          REPLACE (To Be Re-architected)
  ├── DXF Parser & Primitives         ├── PortInferenceEngine (2D heuristics)
  ├── KinematicFoldEngine (3D fold)   ├── Manual Port-Edge Picking HUD
  ├── PlanarFaceDecomposer            ├── CmsGuidedHudOverlay & 7-Step Wizard
  ├── CncPunchPrimitive (Coupler role)├── CmsAuthoringMixin in ViewModel
  ├── Viewport3D & Shader Rendering   └── Fragile Edge-Indexed Scaling Bindings
  ├── 2D Drafting Canvas & Snapping   
  └── Core DSF Sheet-Metal Document   
                                      
  DEPRECATE (Remove from Active DSF)  REUSE CONCEPTUALLY (Geometry Math)
  ├── DxfFittingMetadata.manualPortEdges ├── Distance-to-segment & point-in-poly
  ├── Fragile array-indexed edge refs ├── 3D loop boundary extraction logic
  ├── Transient CMS wizard parameters ├── Local plane projection mathematics
  └── Old manual semanticPorts maps   └── Rigid invariant punch translation math
```

---

## 2. Category 1: KEEP — Core CAD & Sheet-Metal Foundation

These components represent proven, stable CAD and sheet-metal systems. They are preserved without breaking changes:

| Component / Subsystem | Location | Responsibility & Value |
| :--- | :--- | :--- |
| **DXF Parser & Entities** | `lib/sheet_metal_studio/services/dxf_geometry_recognition_engine.dart` | Parses raw flat 2D DXF entities (`CadLine2D`, `CadArc2D`, `outerContour`, layer definitions). Preserves pristine DXF geometry in memory. |
| **Kinematic Fold Engine** | `lib/sheet_metal_studio/engine/kinematic_fold_engine.dart` | Forward-kinematics 3D folding from bend lines ($B1, B2, \dots$) into a valid 3D mesh (`FoldedMeshResult`). Serves as the structural source of truth. |
| **Planar Face Decomposer** | `lib/sheet_metal_studio/engine/planar_face_decomposer.dart` | Partitions 2D outer contour and bend lines into connected planar faces ($F0, F1, \dots$). |
| **Punch Role Classification** | `lib/sheet_metal_studio/models/cnc_punch_primitive.dart` | Semantic punch roles (`CncPunchRole.coupler`, `CncPunchRole.perforation`). Crucial for protecting $8 \times 12\text{ mm}$ coupler slots from distortion. |
| **3D Viewport & Renderer** | `lib/sheet_metal_studio/views/widgets/viewport_3d_widget.dart` | High-performance shaded 3D viewport, turntable orbit, camera controls, and metallic directional lighting. |
| **2D Drafting Canvas** | `lib/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart` | Pan, zoom, mouse-wheel controls, coordinate transforms, and `MagneticSnapEngine`. |
| **Core DSF Document** | `lib/sheet_metal_studio/models/dsf_document.dart` | Standardized sheet-metal document format: material specs, thickness, outer contour, bends, cut lines, punches, and layers. |

---

## 3. Category 2: REPLACE — Previous CMS Implementation

These systems were introduced specifically for the prototype port-assignment and manual edge-marking workflow. They will **not** be extended or reused as the foundation for the new architecture:

### 3.1 `PortInferenceEngine`
* **File**: `lib/sheet_metal_studio/engine/port_inference_engine.dart`
* **Legacy Role**: Attempted to guess ports on flat 2D boundary polygons using ray casts and contour traversal.
* **Why Replacing**: In 2D, a channel mouth looks identical to a relief notch. It forced manual edge-clicking when heuristics failed.
* **Clean Replacement**:
  - `Cms3DOpeningDetector`: Extracts actual open boundary loops from the folded 3D mesh.
  - `CmsOpeningPlaneAnalyzer`: Projects the 3D loop onto the local cross-section plane to measure true $W \times H$ and normal $\vec{n}$.
  - `CmsPortMatcher`: Matches measured 3D openings against expected product contracts.

### 3.2 Manual Port-Edge Picking HUD & In-Canvas Callouts
* **Location**: `unfolded_canvas_widget.dart` (lines 2267–2460, 5758, 7095)
* **Legacy Role**: Rendered floating prompt banners: *"Click Opening Edge for PORT_1"* and maintained manual selection state (`_activeEditingPortId`, `_portEditorScreenPos`).
* **Why Replacing**: Caused the non-responsive clicking behavior shown in the user audit. The app should discover openings automatically from 3D rather than demanding manual 2D edge selection.
* **Clean Replacement**: Automatic 3D opening detection. Manual interaction is invoked only when candidate count $\neq$ expected count (Ambiguity Resolution).

### 3.3 Previous 7-Step Guided Wizard & Mixin
* **Files**:
  - `lib/sheet_metal_studio/views/widgets/guided_authoring/cms_guided_hud_overlay.dart`
  - `lib/sheet_metal_studio/viewmodels/mixins/cms_authoring_mixin.dart`
  - `lib/sheet_metal_studio/views/widgets/guided_authoring/cms_review_and_readiness_dialog.dart`
* **Legacy Role**: Orchestrated a 7-step sequential wizard (`dxfInspection` $\to$ `productIntent` $\to$ `portDimensions` $\to$ `guidedDemarcation` $\to$ `reviewLearned`).
* **Why Replacing**: Enforced a rigid, dark-themed, step-by-step questionnaire that required manual clicking for operations the engine could perform automatically.
* **Clean Replacement**: `CmsGuidedUxController` — an autonomous, observable state machine that executes high-confidence steps automatically, animates 2D $\leftrightarrow$ 3D discoveries with deliberate comprehension pauses, and uses 100% Light CAD Theme.

### 3.4 Fragile Parameter-Drive Scaling Bindings
* **Location**: `unfolded_canvas_widget.dart` (lines 3550–3650)
* **Legacy Role**: Resolved driving parameter keys by looking for ad-hoc string keys (`widthIn`, `widthMain`, `port1Width`) and manually mapped edge coordinates.
* **Why Replacing**: Scaling broke if edge indexes or parameter names shifted.
* **Clean Replacement**: Topological Constraint Graph anchored directly on verified `CmsPhysicalPort` entities.

---

## 4. Category 3: DEPRECATE & REMOVE FROM DSF

To ensure the `.dsf` format remains a **clean, universal sheet-metal format**, the following fields are deprecated and will not be serialized in the new architecture:

```text
DxfFittingMetadata
├── manualPortEdges          <-- DEPRECATED (Do not write in new DSF)
├── portAssignments          <-- DEPRECATED (Replaced by clean CmsPhysicalPort)
├── semanticPorts            <-- DEPRECATED (Flow roles are optional annotations)
└── fragile edgeIndex refs   <-- REMOVED FROM ACTIVE SCHEMA
```

* **Compatibility Rule**: Existing legacy DSF files containing `manualPortEdges` will be parsed passively on read for backward compatibility, but new templates authored under the clean CMS pipeline will **not** contaminate DSF files with these transient structures.

---

## 5. Category 4: REUSE CONCEPTUALLY (Geometry Math Only)

The following pure mathematical functions and algorithms will be reused as stateless utilities:

1. **Orthogonal Plane Projection**: Projecting 3D vertices onto a local plane defined by origin $\vec{C}$ and normal $\vec{n}$ to compute 2D width and height.
2. **Point-in-Polygon & Distance-to-Segment**: Fast collision testing used to check which punch centers reside on specific sidewall faces.
3. **Rigid Fastener Translation**: Calculating rigid offset vectors $\vec{v} = (\Delta X, \Delta Y)$ for coupler mounting punches so they translate with their host face without dimension distortion.

---

## 6. Modularity Commitment & File Size Limits

To remedy file bloat in `unfolded_canvas_widget.dart` (7,474 lines) and `sheet_metal_studio_viewmodel.dart` (7,432 lines), the new architecture strictly enforces:

> **All new CMS engines, models, controllers, and UI widgets will be authored in dedicated, single-responsibility files under ~350 lines each.**

### Target File Organization:

```text
lib/sheet_metal_studio/
├── engine/
│   └── cms/                                 <-- NEW DEDICATED DOMAIN
│       ├── cms_3d_opening_detector.dart      // Extracts 3D boundary loops (~250 lines)
│       ├── cms_opening_plane_analyzer.dart   // Fits plane, measures W × H & normal (~200 lines)
│       ├── cms_port_matcher.dart             // Matches measured 3D loops to contracts (~220 lines)
│       ├── cms_coupler_classifier.dart       // Classifies sidewall fastener slots (~180 lines)
│       └── cms_port_reconciler.dart          // Stable port ID reconciliation (~150 lines)
│
├── models/
│   └── cms/
│       ├── cms_physical_port.dart            // Pure semantic port model (~120 lines)
│       ├── cms_product_contract.dart         // Variation contracts & topologies (~200 lines)
│       └── cms_ux_state.dart                 // Autonomous state machine states (~100 lines)
│
└── views/widgets/guided_cms/                 <-- 100% LIGHT CAD THEME
    ├── cms_guided_stage_card.dart            // Light floating status card (~200 lines)
    ├── cms_live_learned_card.dart            // Live continuous narrative card (~180 lines)
    ├── cms_ambiguity_resolver_dialog.dart    // Visual exception candidate picker (~250 lines)
    ├── cms_2d_overlay_painter.dart           // 2D glow, pulse & callout painter (~220 lines)
    └── cms_3d_opening_callout.dart           // 3D glowing mouth & dimension pills (~200 lines)
```

---

## 7. Legacy Removal Gate (Sprint 8)

Legacy components will remain isolated during development. They will **only** be retired once the following gate criteria are verified:

- [ ] New `Cms3DOpeningDetector` successfully extracts boundary loops from folded 3D models.
- [ ] New `CmsOpeningPlaneAnalyzer` accurately measures $W$ and $H$ on straight and 45° miter openings.
- [ ] New `CmsPortMatcher` auto-matches Port 1 and Port 2 on `45_deg_bend_100x100.dsf` with high confidence.
- [ ] New Observable Guided UX completes end-to-end in the 100% Light CAD Theme.
- [ ] Parametric scaling updates both 2D and 3D while preserving rigid coupler slots.
- [ ] Baseline DXF import/export and original DSF loading pass 100% of existing tests.
- [ ] Zero active code references `PortInferenceEngine` or `manualPortEdges`.
