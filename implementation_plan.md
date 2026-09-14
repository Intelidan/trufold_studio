# 3D CAD Studio --- Phase 1 Master Implementation Plan

This implementation plan details the full roadmap for transforming Danish FormMatrix Studio (`trufold_studio`) into an industry-standard sheet-metal CAD system per [Phase_1_Implementation_Guide.md](file:///f:/flutter_projects/trufold_studio/Phase_1_Implementation_Guide.md) and [product_variations.csv](file:///f:/flutter_projects/trufold_studio/product_variations.csv).

The plan is organized into **12 controlled, sequential batches** covering all Phase 1 milestones (P0 through P27) while preserving the existing working application and maintaining 100% test passing and zero compiler warnings.

---

## Complete Batch Roadmap Overview

```
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                         PHASE 1 EXECUTION ROADMAP                           │
 ├──────────┬───────────────────────────────────────────┬──────────────────────┤
 │ Batch 1  │ Step 1 (#14): CAD Document Model & IDs    │ P1                   │
 │ Batch 2  │ Step 2 (#15): 2D Viewport & Snapping      │ P2                   │
 │ Batch 3  │ Step 3 (#16) & Step 4 (#17): Geom & Modify│ P3, P4               │
 │ Batch 4  │ Step 5-7 (#18-#20): Dimensions & Direct   │ P5, P6, P7           │
 │ Batch 5  │ Step 8 (#21): 2D Geometric Constraints    │ P8                   │
 │ Batch 6  │ Step 9-10 (#22-#24): DXF Diagnostics/Recog│ P9, P10              │
 │ Batch 7  │ Step 11-15 (#25-#29): Feature Tree & Bends│ P11, P12, P13, P14   │
 │ Batch 8  │ Step 16-19 (#30-#33): Holes & 2D/3D Sync  │ P15, P16, P17        │
 │ Batch 9  │ Step 20-21 (#34-#35): 3D Modes & CAM Valid│ P18                  │
 │ Batch 10 │ Step 22-23 (#36-#48): DXF Template Morpher│ P19, P20, P21, P22   │
 │ Batch 11 │ Step 24 (#50-#52): Cable Ladder Assembly  │ P23                  │
 │ Batch 12 │ Step 25-28 (#53-#57): DSF v2, TDS & Lib   │ P24, P25, P26, P27   │
 └──────────┴───────────────────────────────────────────┴──────────────────────┘
```

---

## Detailed Batch Specifications

### Batch 1: Step 1 (#14) — Stabilize & Extend CAD Document Model & Stable ID Architecture

#### Objective
Establish the formal semantic CAD document architecture with stable unique IDs, strict mm unit normalization, and non-destructive backward compatibility with existing `.dsf` documents.

#### Conceptual Entities to Implement
We will establish semantic domain models in `lib/sheet_metal_studio/models/`:

1. **`CadDocument`**:
   - The root container holding document-level metadata, active parts, assemblies, shared parameters, units, tolerances, and versioning.
   - Seamlessly converts to and from existing [DsfDocument](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/models/dsf_document.dart).
2. **`CadPart`**:
   - Represents a single manufacturable sheet metal blank (e.g. cable tray body, cover, reducer flat blank).
   - Holds its own geometry collection, feature list, flat pattern, and 3D folded representation.
3. **`CadAssembly`**:
   - Represents a multi-part welded or assembled product (e.g. Cable Ladder = Left Rail + Right Rail + Rungs array + Welds).
4. **`CadGeometry` (Abstract Base & Primitives)**:
   - Typed geometric elements with persistent UUIDs: `CadLine2D`, `CadPolyline2D`, `CadArc2D`, `CadCircle2D`, `CadSlot2D`, `CadPoint2D`.
   - Replaces unstructured coordinate lists with typed CAD entities.
5. **`CadFeature` (Abstract Base & Types)**:
   - Parametric feature nodes: `SheetBaseFeature`, `BendFeature`, `HoleFeature`, `PatternFeature`, `CutoutFeature`, `ChamferFeature`.
6. **`CadParameter`**:
   - Strong parameter model: `id`, `name`, `value`, `unit`, `type` (user, derived, feature), `min`, `max`, `formula`, `source`.
7. **`CadDimension`**:
   - First-class associative dimension object: `id`, `type` (horizontal, vertical, aligned, angular, radius, diameter, hole-to-edge), `referenceA`, `referenceB`, `measuredValue`, `userOffset`, `isDriven`.
8. **`CadConstraint`**:
   - 2D constraint definition: `id`, `type` (horizontal, vertical, coincident, parallel, perpendicular, distance, etc.), `targetEntities`.
9. **`CadMaterial` & `SheetMetalDefinition`**:
   - Centralizes material grade (GI, MS, HR, CRCA, SS304, SS316, Aluminium), coating (EG, HDG, PC), thickness $T$, inner bend radius $R$, K-factor, bend allowance rules, and corner relief standards.
10. **`ManufacturingDefinition`**:
    - Machine limits, tooling catalogs, press brake punch/die setups, punch tonnage restrictions.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/models/cad_document.dart`
- [NEW] `lib/sheet_metal_studio/models/cad_part.dart`
- [NEW] `lib/sheet_metal_studio/models/cad_assembly.dart`
- [NEW] `lib/sheet_metal_studio/models/cad_geometry.dart`
- [NEW] `lib/sheet_metal_studio/models/cad_feature.dart`
- [NEW] `lib/sheet_metal_studio/models/cad_parameter.dart`
- [NEW] `lib/sheet_metal_studio/models/cad_dimension.dart`
- [NEW] `lib/sheet_metal_studio/models/cad_constraint.dart`
- [MODIFY] `lib/sheet_metal_studio/models/dsf_document.dart` (Add adapter bridge to `CadDocument`)
- [MODIFY] `lib/sheet_metal_studio/models/sheet_metal_material.dart` (Add finish/coating types: EG, HDG, PC, EX)
- [NEW] `test/modules/sheet_metal_studio/cad_document_model_test.dart`

---

### Batch 2: Step 2 (#15) — Professional 2D Viewport & Snapping Engine Overhaul

#### Objective
Elevate the 2D drafting canvas into a responsive AutoCAD/Fusion 360-style viewport with comprehensive object snaps and multi-selection filters.

#### Features
1. **Snap Engine Expansion** ([magnetic_snap_engine.dart](file:///f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/engine/magnetic_snap_engine.dart)):
   - Implement geometric object snaps with visual glyphs:
     - **Endpoint** (square glyph)
     - **Midpoint** (triangle glyph)
     - **Center** (circle glyph)
     - **Intersection** (X glyph)
     - **Perpendicular** (right-angle glyph)
     - **Tangent** (circle with tangent line glyph)
     - **Nearest** (hourglass glyph)
     - **Quadrant** (diamond glyph for arcs/circles)
     - **Grid** (crosshair)
   - Reusable across all drawing tools, dimension placement, and handle dragging.
2. **Selection System Overhaul**:
   - **Box Selection (Left-to-Right)**: Blue window; selects only entities fully enclosed.
   - **Crossing Selection (Right-to-Left)**: Green window with dashed border; selects any entity touched or enclosed.
   - Dynamic real-time cursor coordinate readout in the status bar (model coordinates $X, Y$ in mm).

#### Files to Modify
- [MODIFY] `lib/sheet_metal_studio/engine/magnetic_snap_engine.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart`
- [MODIFY] `lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart`
- [NEW] `test/modules/sheet_metal_studio/snap_and_selection_test.dart`

---

### Batch 3: Step 3 (#16) & Step 4 (#17) — Core 2D Geometry & CAD Modify Tools

#### Objective
Provide full parametric drafting primitives and classic CAD modification commands with complete Undo/Redo integration.

#### Features
1. **Core 2D Geometry Creation Tools**:
   - **Rectangle**: Corner-to-corner or Center-and-size with live dimensions.
   - **Circle**: Center + radius or 2-point diameter.
   - **Arc**: 3-point or Center-start-end.
   - **Slot / Obround**: First-class semantic creation (Length, Width, Rotation).
   - **Construction Lines**: Infinite or dashed reference lines.
2. **CAD Modify Toolset**:
   - **Move / Copy**: Base point to destination point.
   - **Rotate**: Base pivot point with interactive dial or angle input.
   - **Mirror**: Symmetrical reflection across any drawn or selected reference line.
   - **Trim / Extend**: Ray-segment trimming against boundary edges.
   - **Offset**: Parallel geometric offset with direction preview.
   - **Fillet / Chamfer**: Corner rounding or 45° bevelling on adjacent line segments.
   - All modify tools execute as reversible `CadCommand`s on the ViewModel undo stack.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/engine/cad_geometry_tools.dart`
- [NEW] `lib/sheet_metal_studio/engine/cad_modify_tools.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart`
- [MODIFY] `lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart`
- [NEW] `test/modules/sheet_metal_studio/cad_modify_tools_test.dart`

---

### Batch 4: Step 5-7 (#18-#20) — Context Properties, First-Class Dimensions & Direct Associative Dimension Editing

#### Objective
Make dimensions associative CAD objects and implement direct dimension-driven geometry modification (typing a new dimension changes the shape).

#### Features
1. **Context-Sensitive Properties Panel**:
   - Selecting any CAD entity updates the property inspector with live numeric fields (Line, Arc, Slot, Punch, Bend, Face).
2. **First-Class Dimension Placement**:
   - Interactive dimension tool: Horizontal, Vertical, Aligned, Radius, Diameter, Hole-to-Edge.
3. **Direct Associative Dimension Editing**:
   - Double-clicking any dimension badge opens an inline numeric input modal.
   - Typing a new value (e.g. changing `100.0` mm to `150.0` mm) shifts the referenced edge vertices by the delta.
   - Automatically recalculates dependent faces and 3D folded geometry.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/engine/dimension_solver.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart`
- [MODIFY] `lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart`
- [NEW] `test/modules/sheet_metal_studio/dimension_driving_test.dart`

---

### Batch 5: Step 8 (#21) — 2D Geometric Constraints Engine

#### Objective
Add a lightweight, stable 2D constraint solver tailored to sheet-metal product geometry without the fragility of general-purpose polynomial solvers.

#### Features
1. **Geometric Constraints**:
   - Horizontal, Vertical, Coincident, Parallel, Perpendicular, Collinear, Fixed.
2. **Dimensional Constraints**:
   - Distance, Angle, Radius, Symmetric.
3. Applied to flange lines, bend lines, and hole placement lines to ensure parts maintain parallel edges during resizing.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/engine/constraint_engine.dart`
- [MODIFY] `lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart`
- [NEW] `test/modules/sheet_metal_studio/constraint_engine_test.dart`

---

### Batch 6: Step 9-10 (#22-#24) — DXF Ingestion Diagnostics Wizard & Automatic Feature Recognition

#### Objective
Process real-world AutoCAD DXF files (e.g., from `assets/dxf_templates/`) regardless of coordinate offsets or numeric layer names.

#### Features
1. **Auto-Centering Normalizer**:
   - Automatically shifts raw CAD coordinates (e.g., $X \approx 2000, Y \approx 400$) so the bottom-left corner of the blank is at $(0,0)$.
2. **Interactive DXF Import Diagnostics & Layer Mapping Dialog**:
   - Scans entities and reports: Total lines, polylines, circles, layers, open loops.
   - Interactive mapping table: maps numeric AutoCAD layers (`100`, `71`, `43`, `0`) to semantic functions (`OUTLINE`, `BEND_UP`, `BEND_DOWN`, `HOLES`).
3. **Geometry Recognition**:
   - Converts pairs of parallel lines and semicircles into semantic `CadSlot2D` (obround slots).
   - Detects repeated hole grids and proposes grouping them into a `PerforationPattern`.
   - Heals microscopic gaps ($< 0.05$ mm) between laser outline lines.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/engine/dxf_geometry_recognizer.dart`
- [MODIFY] `lib/sheet_metal_studio/engine/dxf_mini_parser.dart`
- [MODIFY] `lib/sheet_metal_studio/engine/dxf_dsf_importer.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/studio_import_dialog.dart`
- [NEW] `test/modules/sheet_metal_studio/dxf_diagnostics_recognition_test.dart`

---

### Batch 7: Step 11-15 (#25-#29) — Unified Model Feature Tree & Semantic Sheet-Metal Engine (Bends, K-Factor, Allowances, Reliefs)

#### Objective
Provide a clean CAD feature tree with dependency tracking and complete sheet-metal engineering calculations (bend allowance, K-factor, bend deductions, bend sequence).

#### Features
1. **Model Feature Tree UI**:
   - Tree hierarchy: Document $\rightarrow$ Part $\rightarrow$ Base Face $\rightarrow$ Bends $\rightarrow$ Hole Patterns $\rightarrow$ Cutouts $\rightarrow$ Relieved Corners.
2. **Sheet Metal Bending Intelligence**:
   - K-factor table based on material and thickness ($K \approx 0.33$ to $0.44$).
   - Neutral axis calculation, Bend Allowance ($BA$) and Bend Deduction ($BD$) formulas:
     $$BA = \frac{\pi}{180} \cdot \theta \cdot (R + K \cdot T)$$
   - Automatic corner bend relief generator (rectangular notch or round teardrop) at flange intersections.
3. **Interactive Bend Sequence Simulator**:
   - Step-by-step bend animation ($1 \rightarrow 2 \rightarrow 3$) in 3D with press brake punch collision check.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/engine/sheet_metal_calc_engine.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/parts_tree_panel.dart`
- [MODIFY] `lib/sheet_metal_studio/engine/kinematic_fold_engine.dart`
- [MODIFY] `lib/sheet_metal_studio/models/fold_bend_line.dart`
- [NEW] `test/modules/sheet_metal_studio/sheet_metal_calc_test.dart`

---

### Batch 8: Step 16-19 (#30-#33) — Hole Features, Pattern Engine, Flat Pattern, & 2D↔3D Synchronization

#### Objective
Connect hole patterns and flat pattern geometry directly to the 3D folded model with bidirectional selection synchronization.

#### Features
1. **Dynamic Hole Pattern Expansion**:
   - Automatically calculates rows/columns based on face boundary minus margins:
     $$\text{cols} = \left\lfloor \frac{W - 2 \cdot \text{margin}_X}{\text{pitch}_X} \right\rfloor + 1$$
2. **Bidirectional 2D↔3D Selection Sync**:
   - Clicking a 3D folded flange highlights its 2D flat face and its parent bend line.
   - Selecting a hole pattern in the 2D feature tree highlights all 3D through-holes across the folded product.

#### Files to Modify
- [MODIFY] `lib/sheet_metal_studio/engine/cnc_turret_engine.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/viewport_3d_widget.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart`
- [NEW] `test/modules/sheet_metal_studio/selection_sync_test.dart`

---

### Batch 9: Step 20-21 (#34-#35) — 3D Viewport Display Modes & Manufacturing CAM Validation Engine

#### Objective
Ensure real-time 3D model inspection and automate CAM manufacturing rule validation.

#### Features
1. **3D Viewport Display Modes**:
   - Shaded, Shaded with Edges, Wireframe, Glass/Transparent, Orthogonal (Top, Front, Right, Isometric).
2. **CAM Validation Rules Engine**:
   - Hole-to-bend clearance check: $\text{distance} \ge 2.5 \cdot T + R$.
   - Hole-to-edge clearance check: $\text{distance} \ge 2 \cdot T$.
   - Minimum flange width check based on press brake V-die opening: $b_{\min} = 0.7 \cdot V$.
   - Highlights violating geometry on canvas with red warning tags and actionable tooltips.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/engine/manufacturing_validator.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/viewport_3d_widget.dart`
- [MODIFY] `lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart`
- [NEW] `test/modules/sheet_metal_studio/manufacturing_validation_test.dart`

---

### Batch 10: Step 22-23 (#36-#48) — Topological Zone Morphing Engine for Existing DXF Templates

#### Objective
Solve the 20,000 DXF file variation problem by enabling single DXF templates to be parametrically morphed into any dimension combination without distortion.

#### Features
1. **Topological Zone Partitioning**:
   - Analyzes fittings (Unequal Tee, Cross, Reducer, 45°/90° Bend, Riser).
   - Segregates invariant central hubs, directional extension zones, and corner relief anchors.
2. **Parametric Regeneration**:
   - Parameter manager with User Parameters:
     - **Tee**: $W_{\text{main}}, H_{\text{main}}, W_{\text{branch}}, H_{\text{branch}}, L_1, L_2$.
     - **Cross**: $W_{\text{main}}, H_{\text{main}}, W_{\text{branch1}}, W_{\text{branch2}}$.
     - **Reducer**: $W_{\text{in}}, W_{\text{out}}, H, L$.
     - **Bend**: $\text{Angle}, W, H, R$.
   - Propagates zone deltas: rigid corner relief miters translate without distortion, floor expands, bend lines follow perimeter, and standard tooling punch patterns automatically repopulate.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/engine/topological_zone_morpher.dart`
- [NEW] `lib/sheet_metal_studio/models/template_parameter_definition.dart`
- [MODIFY] `lib/sheet_metal_studio/views/widgets/active_tool_property_sheet.dart`
- [MODIFY] `lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart`
- [NEW] `test/modules/sheet_metal_studio/template_morphing_test.dart`

---

### Batch 11: Step 24 (#50-#52) — Multi-Part / Assembly & Fabrication Model (Cable Ladders)

#### Objective
Implement the assembly data model for fabricated and welded sheet-metal products like Cable Ladders (Side Rails + Rungs).

#### Features
1. **Assembly Structure**:
   - `CadAssembly` composed of multiple `CadPart` instances (`Left_Rail`, `Right_Rail`, and patterned `Rungs`).
2. **Ladder Parametric Generator**:
   - Inputs: Length ($3000$ mm default), Width ($100$ to $1000$ mm), Height ($50, 75, 100, 150$ mm), Rung Count (default $10$ per `product_variations.csv`) or Pitch ($250$ or $300$ mm).
   - Generates side rail flat drawings with rung weld marks.
   - Generates multi-part flat DXF layout (rails and rungs nested for laser/punch cutting).
   - Displays fully assembled 3D welded ladder.
   - Computes Bill of Materials (BOM) and total weight.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/engine/ladder_assembly_generator.dart`
- [MODIFY] `lib/sheet_metal_studio/models/cad_assembly.dart`
- [MODIFY] `lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart`
- [NEW] `test/modules/sheet_metal_studio/ladder_assembly_test.dart`

---

### Batch 12: Step 25-28 (#53-#57, #49) — DSF v2 Schema Migration, Technical Datasheet (TDS/DDS) Package Generator, & Bonn Product Template Library

#### Objective
Finalize data portability, professional PDF/vector technical documentation, and pre-packaged product templates.

#### Features
1. **DSF v2 Migration & Persistence**:
   - Seamlessly upgrades DSF v1 files to DSF v2 storing templates, parameters, and assembly definitions.
2. **Technical Datasheet (TDS / DDS) Generation**:
   - Exports high-resolution vector/PDF technical documentation matching Bonn Metals standards:
     - Dimensioned Orthogonal 2D Views (Top, Front, Side, Section)
     - 3D Isometric shaded rendering
     - Variation dimension table
     - Material, thickness, and finish (GI, HDG, PC) specifications
     - Title block with client, project, revision, and approval data
3. **Bonn Product Template Library**:
   - Direct catalog browser for Cable Tray, Trunking, and Cable Ladder accessories populated from `product_variations.csv`.

#### Files to Create/Modify
- [NEW] `lib/sheet_metal_studio/services/tds_generator_service.dart`
- [MODIFY] `lib/sheet_metal_studio/services/studio_file_service.dart`
- [MODIFY] `lib/sheet_metal_studio/models/dds_package.dart`
- [NEW] `lib/sheet_metal_studio/views/widgets/product_library_dialog.dart`
- [NEW] `test/modules/sheet_metal_studio/tds_generator_test.dart`

---

## Verification & Execution Protocol

Every batch will follow this strict execution sequence:
1. **Inspect**: Cross-reference with existing classes and tests.
2. **Implement**: Add new modular components without touching unrelated code.
3. **Compile & Analyze**: Run `flutter analyze lib/ test/` to enforce **zero warnings and zero errors**.
4. **Test**: Run unit and widget tests for the new batch plus regression tests on all existing 141 tests (`flutter test test/modules/sheet_metal_studio/`).
5. **Report**: Deliver a detailed walkthrough report at the completion of each batch before proceeding to the next.
