# CAD Engine Audit & Architectural Baseline

**truFold Studio — Sheet Metal CAD / CAM Engine**  
**Date:** September 2026  
**Reference Guides:**
- `truFold_Studio_Intelligent_Parametric_DXF_Template_Implementation_Guide.md`
- `truFold_Studio_Port_Assignment_and_Intelligent_Scaling_UX_Guide.md`

---

## 1. Executive Summary

This audit document establishes the technical baseline of truFold Studio's geometric constraint solving, topological classification, expression evaluation, DAG dependency tracking, and zone morphing engines. It documents existing capabilities, code surfaces, interfaces, and the precise evolution path toward a constraint-driven parametric template and 1-click semantic port inference system.

---

## 2. Component Inventory & Analysis

### 2.1 Geometric Constraint Solver (`lib/sheet_metal_studio/engine/constraints/geometric_constraint_solver.dart`)
- **File Size:** ~52 KB (1,388 lines).
- **Core Interface:**
  ```dart
  static GeometricSolverResult solve({
    required DsfDocument document,
    List<ConstraintDefinition>? overrideConstraints,
    Map<String, double>? parameterOverrides,
    List<ReferenceGeometry>? customReferences,
  })
  ```
- **Capabilities**:
  - Solves driving and reference constraints (`CadConstraintType`: distance, coincident, parallel, perpendicular, concentric, equal, collinear, fixed, symmetric).
  - Integrates with `ContourTopologyClassifier` for branch-zone awareness (`tBranch`, `taperedReducer`, `crossBranch`, `rectangular`, `lBend`).
  - Synthesizes driving constraints dynamically when parameters change (e.g. `DRIVE_MAIN_WIDTH`, `DRIVE_BRANCH_WIDTH`, `DRIVE_LENGTH`).
  - Updates outer contour boundary vertices, fold bend lines, punch holes, and cut lines.
  - Re-evaluates planar face topology via `PlanarFaceDecomposer` after geometric resolution.
- **Identified Improvement Points**:
  - Rigid features (coupler punch holes, mounting slots, corner miter reliefs) must be translated as rigid clusters based on port reference frames rather than individually constrained, preventing dimensional distortion or ovalization during scaling.
  - Sidewall flange heights must support independent dual-height driving constraints ($H_A$ and $H_B$).

---

### 2.2 Directed Acyclic Graph (DAG) Engine (`lib/sheet_metal_studio/engine/constraints/dependency_graph_engine.dart`)
- **File Size:** ~10 KB (320 lines).
- **Core Interface:**
  - `DependencyGraphEngine`: Nodes (`parameter`, `constraint`, `referenceGeometry`, `contourGeometry`, `cutLine`, `bendLine`, `punch`, `pattern`, `mesh3d`), directed edges, cycle detection (`findCycle()`, `wouldCreateCycle()`), topological sort (`getRecalculationOrder()`), dirty propagation (`markDirty()`, `getDirtyNodes()`).
  - `evaluatePattern(PerforationPattern pattern, Map<String, double> parameters)`: Evaluates dynamic perforation formulas for `countXExpression`, `countYExpression`, `pitchXParameter`, and `pitchYParameter`.
- **Capabilities**:
  - Prevents circular references with `CircularDependencyException`.
  - Enables selective, high-performance incremental recalculation.
- **Role in Evolution**:
  - Serves as the backbone orchestrator: Parameter changed -> Dirty mark -> Formula evaluation -> Constraint update -> Solver -> Feature regeneration -> 3D Mesh update.

---

### 2.3 Mathematical Expression Parser (`lib/sheet_metal_studio/engine/constraints/expression_parser_engine.dart`)
- **File Size:** ~9 KB (306 lines).
- **Capabilities**:
  - Lexical tokenizer and recursive descent parser supporting binary operators (`+`, `-`, `*`, `/`), unary negation (`-`), parentheses (`(` `)`), float/integer literals, and named identifier lookup.
  - Supported helper functions: `floor`, `ceil`, `round`, `abs`, `sqrt`, `min`, `max`.
  - `extractVariables(expression)`: Discovers parameter dependencies to build DAG edges automatically.
- **Status**: Production-ready. Requires no architectural modification.

---

### 2.4 Reference & Construction Geometry Engine (`lib/sheet_metal_studio/engine/constraints/reference_geometry_engine.dart` & models)
- **Files**:
  - `lib/sheet_metal_studio/models/constraints/reference_geometry.dart` (172 lines)
  - `lib/sheet_metal_studio/models/constraints/stable_geometry_reference.dart` (210 lines)
  - `lib/sheet_metal_studio/engine/constraints/reference_geometry_engine.dart` (320 lines)
- **Capabilities**:
  - Derives canonical reference edges (`EDGE_LEFT`, `EDGE_RIGHT`, `EDGE_TOP`, `EDGE_BOTTOM`) and centerlines (`CENTER_X`, `CENTER_Y`, `ORIGIN`).
  - Resolves stable entity references (`EntityRef`) by semantic path (e.g. `EDGE_LEFT`, `PUNCH_01.center`, `Line01.start`, `Arc01.midpoint`).
  - Excluded strictly from CAM manufacturing cut lines via `isManufacturingExcluded = true`.
- **Status**: Solid foundation. Ready for direct integration with the Port Inference Engine.

---

### 2.5 Topological Zone Morpher (`lib/sheet_metal_studio/engine/topological_zone_morpher.dart`)
- **File Size:** ~35 KB (1,041 lines).
- **Current Behavior**:
  - Creates synthetic baseline templates (`createBaselineForTemplate`) for standard catalog shapes: `cableTrayTee`, `cableTrayBend90`, `cableTrayBend45`, `cableTrayReducer`, `cableTrayCross`, `cableTrayStraight`.
  - Performs bounding-box delta shifting (`_morphTee`, `_morphBend90`, `_morphReducer`, etc.) using linear coordinate factors.
- **Architectural Decision (Per User Feedback)**:
  - **Do NOT remove or rewrite `TopologicalZoneMorpher`.**
  - Retain it as a reliable fallback and baseline generator.
  - Introduce the constraint-driven scaling pipeline alongside it. Where semantic constraints and templates are defined, the constraint pipeline is primary; for arbitrary unconstrained geometry, the zone morpher remains available.

---

### 2.6 Port Definition & Detection Architecture
- **Current State**:
  - `TemplatePortDefinition`: Currently defines only `widthParamKey` and `heightParamKey` (single height).
  - `ProductPortOpening`: Only holds a single `widthMm` and `heightMm`.
  - Port picking workflow requires separate user clicks for Width Edge and Height Edges.
- **Evolution Path (Per User Guidance)**:
  - Extend `TemplatePortDefinition` with `heightAParamKey`, `heightBParamKey`, `defaultHeightA`, `defaultHeightB`, `side` (`PortSide`), `outwardNormalAngleRad`, and `associatedFeatureIds`.
  - Create `PortInferenceEngine`: Clicked edge is an input hint. Wall height ($H_A, H_B$) is determined geometrically as the perpendicular distance from the bend line / base floor reference to the outermost sidewall boundary, accounting for fillets, chamfers, and aesthetic relief cuts. Outward connection direction is computed as the outward port normal vector.
