# CAD Implementation Audit (P0 Deliverable)
**Target Application:** Danish FormMatrix Studio (`trufold_studio`)\
**Engineering Document:** Phase 1 Master Architecture & Codebase Audit\
**Status:** Complete P0 Baseline Audit

---

## 1. Executive Summary & Architecture Map

TruFold Studio already contains a robust, highly optimized sheet-metal CAD engine built in pure Dart and Flutter. It is **not a greenfield project**; it already possesses full 2D interactive drafting, Rodney 3D forward-kinematic folding, CAM press-brake tool validation, turret punch clustering, and multi-format serialization.

```
                                  TRUFOLD STUDIO
                                        │
           ┌────────────────────────────┴────────────────────────────┐
           ▼                                                         ▼
   PRESENTATION LAYER (UI)                                  APPLICATION LAYER
  • SheetMetalStudioScreen                                 • SheetMetalStudioViewModel
  • UnfoldedCanvasWidget (2D Draftsman)                    • Multi-Document / Tab Session
  • Viewport3DWidget (360° Orbit Mesh)                     • Command History / Undo-Redo
  • PartsTreePanel (DAG Feature Hierarchy)                 • Selection & Hover Bus
  • Floating Inspectors (Bend, Punch, Pattern, Face)       • Dynamic Clipboard Service
           │                                                         │
           └────────────────────────────┬────────────────────────────┘
                                        ▼
                                 CAD & CAM CORE
  ┌─────────────────────────────────────┼─────────────────────────────────────┐
  ▼                                     ▼                                     ▼
GEOMETRY & SEGMENTATION              SHEET METAL & KINEMATICS              CAM & TOOLING
• CadPoint2D / CadLineSegment        • KinematicFoldEngine (Rodrigues)    • PressBrakeCamEngine
• PlanarFaceDecomposer               • FoldBendLine & BendDirection        • Trumpf / Amada / Wila Punches
• CornerTreatment & Reliefs          • SheetMetalMaterial & Neutral Axis   • CncTurretEngine (Auto-nest)
• MagneticSnapEngine                 • BendSequenceEngine (Collision)      • Obround / Round / Rect Slots
  └─────────────────────────────────────┼─────────────────────────────────────┘
                                        ▼
                               STORAGE & I/O LAYER
  • DsfDocument (Native v1.0 JSON Schema)
  • DxfMiniParser & DxfDsfImporter (Creo/SolidWorks/AutoCAD ASCII Ingestion)
  • DxfExporter (Layer-segregated Laser & Bend 2D Export)
  • ExportEngine3D (OBJ Wavefront 3D Mesh Export)
  • DdsPackage (Technical Datasheet Structured Container)
```

---

## 2. Existing Feature Inventory

### 2.1 Existing and Fully Working (Tested & Verified)
1. **2D Canvas Drafting Viewport**:
   - Smooth middle-mouse, right-mouse, and spacebar panning with zoom to point.
   - Dynamic grid rendering with sub-pixel alignment during canvas translation.
   - Snapping: continuous edge magnetic snapping, 5° increment angle snapping with 45°/90°/180° priority, and Alt key bypass.
   - Interactive drawing tools: Add Bend Line, Add Laser Cut Line, Stamp Single Punch, Auto-Nest Perforation Pattern, Set Base Anchor.
   - Movable dimension badges with automatic leader lines, anchor dots, auto-staggering, and double-click reset.
   - Single pitch interval dimension deduplication for high-density perforation patterns.
2. **3D Kinematic Fold Engine**:
   - Directed Acyclic Graph (DAG) tree construction from base anchor floor out to flanges.
   - Rodrigues rotation around arbitrary 3D bend line vectors.
   - Smooth continuous folding parameter $t \in [0.0, 1.0]$.
   - Cylindrical curved bend fillet mesh generation with normal vectors and physical sheet thickness rims.
   - Face boundary bend line clipping (eliminating laser cut overshoots).
   - 360° free-roaming spherical orbit, pan, zoom, isometric / orthogonal view presets, shaded / wireframe / glass visualization.
3. **Perforation & Punch Tooling**:
   - Parametric patterns: Obround slots, round holes, square, rectangle.
   - Live editable dimensions ($L, W, \varnothing$), Pitch X, Pitch Y, 50% staggered row offset, and 360° rotation dial.
   - Surface immobility: Applied perforations are strictly locked against mouse dragging, modifiable only parametrically.
   - Automatic hole-pattern face nesting with configurable edge clearances and corner exclusions.
4. **CAM & Press Brake Tooling**:
   - Machine catalog with Trumpf, Amada, Wila, and standard punch/die configurations.
   - Tonnage calculation, inside bend radius validation, V-die opening verification.
   - Bend sequence simulation with collision detection and part interference warnings.
5. **Feature Suppression ("Temporary Delete")**:
   - Complete `isVisible` toggle across Faces, Bends, Punches, and Patterns.
   - Synchronized 2D canvas dimension hiding and 3D kinematic fold mesh omission.
6. **State & Architecture**:
   - Multi-tab document support (`StudioTabBar`).
   - Single-step continuous drag undo/redo stack.
   - Bidirectional hover and selection highlighting between 2D tree, 2D canvas, and 3D viewport.

---

## 3. Existing but Incomplete Features

| Feature | Current State | Gap to Reach Industry Standard |
|---|---|---|
| **DXF Ingestion** | Reads ASCII DXF lines, polylines, circles; classifies layers by name (`BEND_UP`, `EDGES`, etc.). | Real-world Bonn DXFs use AutoCAD numeric layers (`100`, `71`, `43`, etc.) and arbitrary world coordinates; lacks interactive layer-mapping wizard and repair diagnostics (gap healing, zero-length removal). |
| **DXF Template Modification** | Static import creates a rigid `DsfDocument`. | Cannot dynamically change dimensions ($W, H, L$) of imported DXF geometry; lacks topological zone morphing and parameter dependency graph. |
| **Direct Dimension Editing** | Dimension badges can be dragged and repositioned. | Double-clicking a dimension badge resets its position, but does **not yet edit the underlying geometry** (e.g. typing `150` on a `100` dimension to stretch the part). |
| **Geometric Constraints** | Edge constraints exist on selected bends (Fusion 360 style: distance to Left/Bottom/Right/Top). | General 2D constraints (Horizontal, Vertical, Parallel, Perpendicular, Tangent, Coincident) are not yet integrated into a unified 2D constraint engine. |
| **Assemblies / Multi-Part** | `DsfDocument` represents a single contiguous folded blank (`CadPart`). | No `CadAssembly` representation for welded cable ladders (Left Side Rail + Right Side Rail + Rungs array) with multi-part flat patterns and BOM. |
| **TDS / DDS Generation** | `DdsPackage` model exists with metadata and manifest. | Lacks automated PDF / Vector technical datasheet generation with dimensioned 2D Orthogonal views, 3D render, and title block. |

---

## 4. Existing but Needs Refactoring

1. **DXF Coordinate Normalization**:
   - Current importer imports DXF geometry at raw coordinates (e.g. $X \approx 2000, Y \approx 400$).
   - *Refactor*: Automatically translate imported bounding box origin to $(0,0)$ with user-defined anchor or center.
2. **Dimension Model Formalization**:
   - Current dimensions in 2D canvas are computed dynamically in `_drawOutsideDimensions` and `_drawFaceDimensions`.
   - *Refactor*: Promote dimensions to first-class CAD objects (`CadDimension`) stored in the document model with persistent IDs and entity references (`referenceA`, `referenceB`, `formula`, `driven`).

---

## 5. Missing Systems (Phase 1 Target Scope)

1. **Topological Zone Morphing & DXF Template Engine (The Core Requirement)**:
   - Ability to load reference DXFs (`unequal_tee_100x50x100x50.dxf`, `reducer_100x50x50.dxf`, `45_deg_bend_100x50.dxf`) and partition them into parametric control zones.
   - Parameter manager with User Parameters (`Main_W`, `Main_H`, `Branch_W`, `Branch_H`, `Radius`, `Thickness`).
   - Zone delta propagation that preserves bend relief miters while expanding floor and wall dimensions.
2. **Interactive DXF Import Diagnostics & Layer Mapping Wizard**:
   - Diagnostics dialog displaying entity counts, open loops, duplicate vertices, and color-to-layer assignment.
   - User confirmation allowing arbitrary numeric layers to be mapped to `OUTLINE`, `BEND_UP`, `BEND_DOWN`, `HOLES`.
3. **Multi-Part / Assembly Engine (Cable Ladder Foundation)**:
   - `CadAssembly` containing multiple `CadPart` instances.
   - Ladder generator skeleton: Side rails + Rungs array (equal spacing, pitch, start/end offsets).
   - Multi-part flat drawing layout and welded assembly 3D view.
4. **Associative Direct Dimension Editing**:
   - Double-clicking a dimension badge opens an inline numeric input dialog. Entering a new value propagates through the parameter system to alter geometry.

---

## 6. Duplicate Implementations & High-Risk Areas

- **Duplicate Implementations**: None currently. The codebase has maintained a clean single-core approach.
- **High-Risk Area 1 (Complex Intersections in Tees & Crosses)**:
  - In an unequal tee, changing branch width shifts the intersection vertices of the 45° corner miters. If done blindly via scaling, the miters distort. Must use vector-based boundary translation preserving miter angles.
- **High-Risk Area 2 (Hole Pattern Overflow)**:
  - When floor width decreases, fixed hole counts can punch holes outside the sheet metal boundary. The pattern engine must dynamically clamp hole counts based on available boundary area minus minimum edge clearances.

---

## 7. Data Flow Pipelines

### 7.1 DXF Ingestion Pipeline
```
Raw ASCII DXF ──> DxfMiniParser ──> Entities & Layers ──> DxfImportDiagnostics
                                                                 │
DsfDocument <── PlanarFaceDecomposer <── Layer Mapper & Healer ──┘
```

### 7.2 Parametric Template Regeneration Pipeline
```
User Parameter Input (e.g. Branch_W = 200)
       │
       ▼
ParameterManager & Dependency Graph
       │
       ▼
Topological Zone Morpher
 • Shifts branch boundary vectors
 • Translates corner relief miters rigidly
 • Relocates and scales bend lines
 • Re-triangulates PlanarSheetFaces
       │
       ▼
Perforation Pattern Auto-Recalculation
 • Computes new available floor width/length
 • countX = floor((W - 2*margin) / pitchX)
 • Generates standard CNC punch primitives
       │
       ▼
KinematicFoldEngine (3D Regeneration)
 • Rebuilds DAG tree from base anchor
 • Rotates planar panels around new bend axes
 • Re-meshes bend arc fillets
       │
       ▼
Canvas 2D & Viewport 3D Renderers Update
```

---

## 8. Audit Conclusion & Roadmap Alignment

TruFold Studio's existing foundations in Dart/Flutter are rock-solid, fully tested (141 passing tests, zero static analysis issues), and cleanly organized.

The path forward does **not** involve rewriting. Instead, it involves adding the **Topological Template Morphing Engine**, **DXF Diagnostic Wizard**, **Direct Dimension Driving**, and **Multi-Part Assembly Model** as modular extensions to the existing CAD core.
