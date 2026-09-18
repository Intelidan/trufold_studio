# TruFold Studio (DSF Studio)
### Industrial Sheet Metal Kinematic 3D Folding & CAD/CAM Studio

---

## 1. Executive Summary & Architecture

**TruFold Studio (DSF Studio)** is an industrial-grade sheet metal CAD/CAM and forward-kinematic 3D folding engine developed in 100% pure Flutter/Dart.

It operates with **ZERO external dependencies** beyond Flutter's core framework (`package:flutter/material.dart`, `dart:math`, `dart:convert`). The entire engine, math solvers, 2D drawing board, 3D polygon renderer, and CAD/CAM importers/exporters are completely self-contained within `lib/modules/sheet_metal_studio/`.

### Core Capabilities:
1. **Interactive Unfolded 2D Drawing Board**:
   - Clean, high-contrast industrial light theme with millimeter grid lines and zoom/pan coordinates.
   - Independent mouse-wheel zooming and panning with zero canvas bleed (`ClipRect` isolation).
   - Single-click to deselect objects on canvas background.
   - Live foreshortening: as folds occur, 2D face panels contract interactively with faint dashed ghosted reference outlines of the initial flat blank.
2. **Rubber-Band Line Authoring & 45° Angle Snapping**:
   - Single-click initiation and dynamic dashed rubber-band cursor following.
   - Automatic orthogonal and 45° angle snapping ($0^\circ, 45^\circ, 90^\circ, 135^\circ, 180^\circ, 225^\circ, 270^\circ, 315^\circ$) with live on-canvas angle badges (e.g. `BEND 45°`, `CUT 90°`).
   - <kbd>Alt</kbd> key bypass: holding Alt unlocks free, continuous 360° rotation.
3. **Open / Incomplete Bend Handling**:
   - Finite line segment slicing: bend lines that stop in the middle of a face without reaching both boundaries or intersecting another line do not tear or crash the 3D model.
   - Visual warning badges (`⚠️ INCOMPLETE BEND`) and endpoint warning rings.
   - Interactive endpoint handles ($P_1$ and $P_2$): engineers can click and drag line endpoints to magnetically snap onto workpiece outer edges, corners, or intersecting bends.
4. **Laser Cut Line Tool (`+ Cut`)**:
   - Dedicated laser slit and cut line tool (`Icons.content_cut`).
   - Cuts slice/truncate sections when connecting boundaries, or remain as interior laser slits for forming tabs, reliefs, and vents.
   - Full layer classification (`CUT`), pure-Dart AutoCAD DXF export compatibility, and undo/redo history.
5. **Magnetic Snapping Engine**:
   - Continuous edge snapping (`SnapType.edgePoint`), corners, midpoints, hole centers, and cut endpoints.
   - Snapping activates within a 15mm radius with visual crosshairs and label indicators.
   - Toolbar toggle button to enable/disable magnetic snapping on demand.
6. **CNC Turret Punch & Constraint Engine**:
   - Punch primitives: Round tooling holes, Obround slots, and Rectangles/Squares.
   - CAD Studio style live edge distance constraints ($X, Y$ distances to workpiece edges and nearest bend lines).
   - Dynamic Obround end arc calculation: adjusting slot width and height automatically recalculates tangential end radiuses.
   - Immediate 3D hole rendering: punch holes cut into planar faces and appear immediately on folded 3D parts.
   - Corner contour treatments: 45° miter chamfers and cubic Bezier corner fillets.
7. **Forward-Kinematic 3D Folding Engine**:
   - Automatic Directed Acyclic Graph (DAG) construction rooted at an optimal base anchor face.
   - Smooth $0\%$ to $100\%$ kinematic fold progression using Rodrigues axis-angle rotation matrices.
   - Auto-play folding animation with smooth cubic easing.
   - Middle-mouse button and <kbd>Shift</kbd>+Left click 3D camera panning, mouse wheel camera zoom, and turntable orbit.
8. **CAD/CAM Exporters & Importers**:
   - **.dsf**: Native Danish Sheet Fold JSON format.
   - **.dxf**: Pure-Dart AutoCAD R12/2000 DXF with CNC layers (`CUT`, `BEND_UP`, `BEND_DOWN`, `HOLES`, `ANNOTATION`).
   - **.obj**: 3D Wavefront Mesh with solid sheet metal thickness extrusion.
   - **.stl**: 3D Stereolithography ASCII mesh for slicers, 3D printing, and CAM.
   - **.dds**: Danish Datasheet complete project package.
9. **History & State Management**:
   - Full Undo / Redo engine (<kbd>Ctrl+Z</kbd> / <kbd>Ctrl+Y</kbd>) across all actions.
   - Single-step drag recording: continuous multi-frame object dragging collapses into a single undo step upon mouse release.
   - Floating, draggable parameter property sheets for bends and punches.

---

## 2. Standalone Portability & Zero-Dependency Guarantee

The module `lib/modules/sheet_metal_studio/` has **zero external package dependencies** and **zero references** to the parent application.

### Standalone Migration Steps:
1. Copy the entire folder `lib/modules/sheet_metal_studio/` into your new Flutter project's `lib/` directory.
2. In your `main.dart`, import and display the screen:
```dart
import 'package:flutter/material.dart';
import 'modules/sheet_metal_studio/views/sheet_metal_studio_screen.dart';

void main() {
  runApp(const MaterialApp(
    title: 'TruFold Studio',
    debugShowCheckedModeBanner: false,
    home: SheetMetalStudioScreen(),
  ));
}
```
Or launch with an existing `.dsf` document:
```dart
SheetMetalStudioScreen.open(context, initialDocument: myDocument);
```

---

## 3. Directory & File Structure Map

```
lib/modules/sheet_metal_studio/
├── README.md                            # Comprehensive module architectural manual
│
├── models/                              # Immutable Domain & Geometric Models
│   ├── cad_primitives.dart              # CadPoint2D, CadPoint3D, CadFoldedPolygon3D, CadLineSegment
│   ├── sheet_metal_material.dart        # Material grades, K-Factor, Bend Allowance (BA), Bend Deduction (BD)
│   ├── fold_bend_line.dart              # Press-brake bend line (p1, p2, angle, radius, UP/DOWN direction)
│   ├── planar_sheet_face.dart           # Segmented planar sheet face (base floor, walls, return flanges)
│   ├── cnc_punch_primitive.dart         # CNC Turret tools: Round, Obround/Slot, Square, Rectangle
│   ├── corner_treatment.dart            # Corner miter chamfers and Bezier fillets
│   ├── dsf_document.dart                # .dsf Document Specification, JSON serializer, cutLines, sample loaders
│   └── dds_package.dart                 # .dds Danish Datasheet container (tooling, metadata, camera state)
│
├── engine/                              # Mathematical & Algorithmic Engines (Pure Dart)
│   ├── matrix4_math_helper.dart         # 4x4 Transformation Matrix & 3D Rodrigues axis-angle rotation
│   ├── kinematic_fold_engine.dart       # DAG forward kinematics, auto-oriented surface normals, fold interpolation
│   ├── dxf_mini_parser.dart             # Pure-Dart ASCII DXF parser (LINE, LWPOLYLINE, ARC, CIRCLE, TEXT)
│   ├── planar_face_decomposer.dart      # Finite segment polygon slicing, boundary verification, open bend detection
│   ├── dxf_dsf_importer.dart            # Auto-classifies layers (BEND_UP, BEND_DOWN, CUT, HOLES) into DSF
│   ├── magnetic_snap_engine.dart        # Magnetic snap target extractor (continuous edge, corners, bends, cuts)
│   ├── cnc_turret_engine.dart           # Punch generation, edge/bend constraints, and corner treatments
│   ├── export_engine_3d.dart            # Wavefront OBJ & ASCII STL 3D mesh exporter with solid thickness
│   └── dxf_exporter.dart                # Pure-Dart AutoCAD R12/2000 DXF generator with CNC layers
│
├── viewmodels/                          # MVVM State Management
│   └── sheet_metal_studio_viewmodel.dart# Central coordinator for 2D canvas, 3D orbit, tools, history, and folds
│
└── views/                               # SolidWorks-Style Dual-Viewport CAD UI
    ├── sheet_metal_studio_screen.dart   # Main scaffold with header, toolbar, keyboard shortcuts, and dual viewports
    └── widgets/
        ├── split_pane_divider.dart      # Draggable vertical divider with hover glow & double-tap 50/50 reset
        ├── unfolded_canvas_widget.dart  # 2D live canvas, rubber-banding, 45° angle pill, warning rings, endpoint handles
        ├── viewport_3d_widget.dart      # 3D interactive viewport, turntable orbit, middle-mouse panning, wheel zoom
        ├── fold_progress_slider.dart    # Bottom dock slider with auto-play animation and 0% to 100% jumps
        ├── bend_property_sheet.dart     # Draggable floating inspector for press-brake bend angles, radii, and directions
        ├── punch_property_sheet.dart    # Draggable floating inspector for CNC punch dimensions and edge constraints
        ├── studio_export_dialog.dart    # Modal dialog for previewing and exporting .dsf, .dxf, .obj, .stl, .dds
        └── studio_import_dialog.dart    # Modal dialog for importing and auto-folding custom DXF / DSF code
```

---

## 4. Kinematic & Mathematical Foundation

### 4.1 Forward Kinematics (DAG)
When a bend line divides two faces (e.g. Floor and Left Wall):
- A coordinate frame is established along the bend vector $\vec{u} = \frac{p_2 - p_1}{\|p_2 - p_1\|}$.
- The rotation angle $\theta(t)$ is smoothly interpolated: $\theta(t) = t \times \theta_{\text{target}}$.
- The rotation matrix $\mathbf{R}(\vec{u}, \theta)$ is computed using Rodrigues' formula:
$$\mathbf{R}(\vec{u}, \theta) = \mathbf{I} + (\sin\theta)\mathbf{K} + (1 - \cos\theta)\mathbf{K}^2$$
where $\mathbf{K}$ is the cross-product skew-symmetric matrix of $\vec{u}$.

### 4.2 Finite Segment Polygon Partitioning
Naive line slicing extends lines to infinity, causing spurious cuts across distant sheet panels. `PlanarFaceDecomposer` enforces finite segment verification:
$$\text{Edge Intersection } I = P_1 + t \cdot (P_2 - P_1)$$
An intersection only splits the face if $t \in [t_{\min}, t_{\max}]$ where $t_{\min} = -\frac{2.5}{\|P_2 - P_1\|}$ and $t_{\max} = 1.0 + \frac{2.5}{\|P_2 - P_1\|}$. If a line stops in the interior of a panel, `_slicePolygon` returns `null`, the parent face is preserved, and the bend line is marked with `parentFaceId: ''` and `childFaceId: ''` (incomplete bend).

### 4.3 Sheet Metal Mechanics
- **Bend Allowance ($BA$):**
  $$BA = \frac{\pi}{180} \times \theta \times (R_{\text{in}} + K \times T)$$
- **Outside Setback ($OSB$):**
  $$OSB = \tan\left(\frac{\theta}{2}\right) \times (R_{\text{in}} + T)$$
- **Bend Deduction ($BD$):**
  $$BD = 2 \times OSB - BA$$
where $T$ is sheet thickness and $K$ is material K-Factor (default $0.40$).

---

## 5. Verification Suite

The entire module is validated by 32 comprehensive unit and widget tests in `test/modules/sheet_metal_studio/`:
- `cnc_turret_test.dart`: Round, Obround, and Square punch creation, dynamic arc geometry, edge constraints, corner fillets/chamfers, JSON roundtrip.
- `dxf_dsf_importer_test.dart`: AutoCAD DXF ingestion, CNC layer classification, punch extraction, planar face decomposition, 3D folding.
- `export_engine_test.dart`: Wavefront OBJ (mid-surface & solid thickness), ASCII STL mesh, AutoCAD DXF, DDS package bundles, and DSF JSON.
- `kinematic_fold_engine_test.dart`: Rodrigues rotations, DAG kinematics, progressive folding ($0.0 \to 0.5 \to 1.0$).
- `magnetic_snap_test.dart`: Corner, midpoint, bend endpoint, and continuous edge snapping.
- `sheet_metal_studio_screen_test.dart`: Mouse wheel zooming, panning, deselect on empty canvas, immediate 3D hole rendering, Undo/Redo stack, single-step multi-frame drag recording, CAD Studio edge constraints, 45° angle snapping, incomplete bend detection, endpoint drag-to-edge snapping, and laser cut lines.
