# Current CAD Architecture Audit (Set 00)
## Sheet Metal Studio — Existing Systems, Reusability & Extension Points

This audit provides a comprehensive inspection of the existing Sheet Metal Studio implementation per **Section 58 (SET 00 — Complete Codebase Audit)** of `Constraint_and_Intelligent_Template_Guide.md`.

---

## 1. Subsystem Audit Matrix

| Subsystem | Existing Implementation | Reusability | Status | Recommended Action |
|---|---|---|---|---|
| **2D Geometry Primitives** | `cad_primitives.dart` (`CadPoint2D`, `CadLineSegment`, `CadArcSegment`) | High | Working | Reuse as-is. Add stable edge/vertex sub-references. |
| **CAD Geometry System** | `cad_geometry.dart` (`CadGeometry`, `CadLineGeometry`, `CadCircleGeometry`, `CadArcGeometry`, `CadPolygonGeometry`) | High | Working | Reuse. Add entity reference identifiers (`id.start`, `id.end`, `id.edge`). |
| **Reference Geometry** | None (only implicit canvas bounding box) | Low | **Missing** | Implement `ReferenceGeometry` (construction line, centerline `CENTER_X`/`CENTER_Y`, reference edges `EDGE_LEFT/RIGHT/TOP/BOTTOM`). |
| **Constraint Model** | `cad_constraint.dart` (`CadConstraint`, `CadConstraintType`) | Medium | **Partial** | Extend entity IDs to support sub-element references (`EntityRef`), driving value vs parameterId, and part-to-part binding. |
| **Constraint Solver** | `constraint_solver.dart` (`ConstraintSolver`) | Low/Medium | **Partial / Not Binding** | Currently only shifts `cutLines` and punch coordinates; **does not touch `outerContour`** or part boundary edges! Must upgrade to solve boundary edges, part-to-part bindings, and punch/bend edge offsets. |
| **Stable Reference System** | None (raw string IDs only) | Low | **Missing** | Implement `StableGeometryReference` (`Line.start`, `Line.end`, `Circle.center`, `EDGE_LEFT`, `PART_A.EDGE_1`). |
| **Parameter System** | `cad_parameter.dart` (`CadParameter`, `CadParameterCategory`, `CadParameterType`) | High | Working (isolated) | Integrate directly with `DsfDocument` and constraint driver. Add expression evaluation (`WIDTH / 2`). |
| **Dependency Graph** | None (immediate procedural morphing) | Low | **Missing** | Implement `DependencyGraphEngine` (parameter $\to$ constraint $\to$ geometry $\to$ feature $\to$ 3D) with cycle detection. |
| **Hole & Punch System** | `cnc_punch_primitive.dart`, `cnc_turret_engine.dart` | High | Working | Reuse CNC punch primitives. Bind center coordinates via edge-distance and centerline constraints. |
| **Hole Patterns** | `perforation_pattern.dart`, `pattern_property_sheet.dart` | High | Working | Reuse pattern expansion. Integrate pattern extent with parameter constraints (`keep pitch` vs `keep count`). |
| **Sheet Metal Bends** | `fold_bend_line.dart`, `kinematic_fold_engine.dart`, `planar_face_decomposer.dart` | High | Working | Reuse bend lines, K-factor, and face decomposition. Bind bend lines to reference edges via constraints. |
| **2D Canvas Rendering** | `unfolded_canvas_widget.dart` | Medium | Working but **Bloated (5,384 lines)** | Decompose painter: extract constraint overlay, reference geometry overlay, and HUD into dedicated modular painters. |
| **3D Mesh Viewport** | `viewport_3d_widget.dart`, `export_engine_3d.dart` | High | Working | Reuse turntable 3D mesh rendering. Regenerate mesh when constraints update planar faces. |
| **ViewModel / State** | `sheet_metal_studio_viewmodel.dart` | Medium | Working but **Bloated (5,257 lines)** | Extract constraint, parameter, reference geometry, and template logic into modular mixins. |
| **DSF Format** | `dsf_document.dart` | High | Working | Extend schema version to preserve `referenceGeometry`, `parameters`, and `constraints` without breaking backwards compatibility. |
| **DXF Import / Export** | `dxf_mini_parser.dart`, `dxf_exporter.dart`, `dxf_geometry_recognition_engine.dart` | High | Working | Reuse geometry recognition. Feed recognized outer contour and holes into template constraint authoring. |
| **Undo / Redo** | `studio_command_delta.dart` | High | Working | Reuse command delta stack. Ensure constraint/parameter mutations record discrete undo deltas. |

---

## 2. Root Cause Analysis: Why Constraints Were Not Binding

1. **Outer Contour Disconnect**:
   - In `constraint_solver.dart`, only `workingCuts`, `workingBends`, and `workingPunches` were modified during relaxation passes.
   - `document.outerContour` was passed into `PlanarFaceDecomposer` unchanged.
   - Any constraint placed on an edge (left, right, top, bottom, or contour segment) was completely disregarded when generating the updated document!
2. **Missing Reference Abstraction**:
   - `bend_property_sheet.dart` and `punch_property_sheet.dart` presented "Edge Constraints (MM)" textboxes that only performed one-off coordinate shifts (`shiftX = targetDistanceMm - current`). They **never instantiated a persistent `CadConstraint`** or recorded an edge dependency.
3. **No Multi-Part / Multi-Edge Binding**:
   - There was no concept of binding an edge of Part A (or a branch) to an edge of Part B (or main body) with coincident, distance, or collinear relations.
4. **Hardcoded Topological Morphing**:
   - `topological_zone_morpher.dart` used hardcoded geometric scaling offsets (`t * dW`, `x += dBw`) instead of evaluating a formal constraint graph, directly violating Rule 5 and Rule 13 of the guide.

---

## 3. Modular Architecture Refactoring Strategy

To satisfy the user's requirement to **"keep the code clean and splitted"** and eliminate the 5000-line monolithic files:

```text
lib/sheet_metal_studio/
├── engine/
│   ├── constraints/
│   │   ├── stable_geometry_reference.dart      # Stable ID & sub-element parser/resolver
│   │   ├── reference_geometry_engine.dart      # Construction lines, centerlines, reference edges
│   │   ├── geometric_constraint_solver.dart    # Upgraded boundary, edge-to-edge & part-to-part solver
│   │   ├── dependency_graph_engine.dart        # Parameter -> Constraint -> Feature DAG
│   │   └── expression_parser_engine.dart       # Mathematical formula parser (+, -, *, /, ())
│   └── ... (existing engines preserved)
├── models/
│   ├── constraints/
│   │   ├── reference_geometry.dart             # Centerline, construction line, reference edge models
│   │   └── constraint_definition.dart          # Upgraded constraint model with driving modes
│   └── ... (existing models preserved)
├── viewmodels/
│   ├── mixins/
│   │   ├── constraint_viewmodel_mixin.dart     # Constraint CRUD, solving, and conflict handling
│   │   ├── parameter_viewmodel_mixin.dart      # Named parameters & formula evaluation
│   │   └── reference_geometry_mixin.dart       # Reference edges & centerlines
│   └── sheet_metal_studio_viewmodel.dart       # Composed coordinator delegating to mixins
└── views/
    └── widgets/
        └── canvas/
            ├── canvas_constraint_painter.dart  # Renders constraint symbols & leader lines
            ├── canvas_reference_painter.dart   # Renders dashed centerlines & reference edges
            └── constraint_manager_sheet.dart   # Floating inspector for edge & part binding
```

This guarantees that:
- Zero existing features are broken or reimplemented from scratch.
- `sheet_metal_studio_viewmodel.dart` and `unfolded_canvas_widget.dart` do not grow larger; in fact, constraint logic is cleanly factored out.
- Constraint solving binds edges, parts, centerlines, punches, and bends reliably.
