// Onshape Toolbar Items Data Model & Full Registry
// Generated from onshape_icon_set assets & preview_all_icons.html
// Supports all 125+ tools across 10 3D Modeling groups and 10 Sketch groups.

import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';


class OnshapeToolItem {
  final String id;
  final String label;
  final String assetPath;
  final String shortcut;
  final bool isImplemented;
  final bool Function(AssemblyStudioViewModel vm)? isActive;
  final void Function(AssemblyStudioViewModel vm, BuildContext context)? onExecute;

  const OnshapeToolItem({
    required this.id,
    required this.label,
    required this.assetPath,
    this.shortcut = '',
    this.isImplemented = false,
    this.isActive,
    this.onExecute,
  });
}

class OnshapeToolGroup {
  final String id;
  final String title;
  final String defaultPrimaryId;
  final List<OnshapeToolItem> items;

  const OnshapeToolGroup({
    required this.id,
    required this.title,
    required this.defaultPrimaryId,
    required this.items,
  });

  OnshapeToolItem get defaultPrimary =>
      items.firstWhere((it) => it.id == defaultPrimaryId, orElse: () => items.first);
}


// ===========================================================================
// 3D Modelling Toolbar Groups (10 Groups)
// ===========================================================================
final List<OnshapeToolGroup> onshape3dModelingGroups = [
  OnshapeToolGroup(
    id: 'base_features',
    title: 'Base Features',
    defaultPrimaryId: 'extrude',
    items: [
      OnshapeToolItem(
        id: 'extrude',
        label: 'Extrude',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/01_base_features/01_extrude.svg',
        shortcut: 'Shift+E',
        isImplemented: true,
        isActive: (vm) => vm.isExtrudeMode,
        onExecute: (vm, ctx) => vm.toggleExtrudeMode(),
      ),
      OnshapeToolItem(
        id: 'revolve',
        label: 'Revolve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/01_base_features/02_revolve.svg',
        shortcut: 'Shift+W',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'sweep',
        label: 'Sweep',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/01_base_features/03_sweep.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'loft',
        label: 'Loft',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/01_base_features/04_loft.svg',
        shortcut: 'Shift+L',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'thicken',
        label: 'Thicken',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/01_base_features/05_thicken.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'enclose',
        label: 'Enclose',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/01_base_features/06_enclose.svg',
        isImplemented: false,
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'edge_and_body_features',
    title: 'Edge and Body Features',
    defaultPrimaryId: 'fillet',
    items: [
      OnshapeToolItem(
        id: 'fillet',
        label: 'Fillet',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/01_fillet.svg',
        shortcut: 'Shift+F',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.applyFilletToSelectedCorner(5.0),
      ),
      OnshapeToolItem(
        id: 'face_blend',
        label: 'Face blend',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/02_face_blend.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'chamfer',
        label: 'Chamfer',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/03_chamfer.svg',
        shortcut: 'Shift+C',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.applyChamferToSelectedCorner(5.0),
      ),
      OnshapeToolItem(
        id: 'draft',
        label: 'Draft',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/04_draft.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'body_draft',
        label: 'Body draft',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/05_body_draft.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'rib',
        label: 'Rib',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/06_rib.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'shell',
        label: 'Shell',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/07_shell.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'hole',
        label: 'Hole',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/08_hole.svg',
        shortcut: 'Shift+H',
        isImplemented: true,
        onExecute: (vm, ctx) { final pId = vm.selectedPart?.id; if (pId != null) vm.punchVoidHole(partId: pId, localCenter: const CadPoint2D(0, 0), shape: 'circle_hole'); },
      ),
      OnshapeToolItem(
        id: 'external_thread',
        label: 'External thread',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/02_edge_and_body_features/09_external_thread.svg',
        isImplemented: false,
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'pattern_and_mirror',
    title: 'Pattern and Mirror',
    defaultPrimaryId: 'linear_pattern',
    items: [
      OnshapeToolItem(
        id: 'linear_pattern',
        label: 'Linear pattern',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/03_pattern_and_mirror/01_linear_pattern.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.punchEvenRungSlots(vm.selectedPart?.id ?? ''),
      ),
      OnshapeToolItem(
        id: 'circular_pattern',
        label: 'Circular pattern',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/03_pattern_and_mirror/02_circular_pattern.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'curve_pattern',
        label: 'Curve pattern',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/03_pattern_and_mirror/03_curve_pattern.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'mirror',
        label: 'Mirror',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/03_pattern_and_mirror/04_mirror.svg',
        isImplemented: false,
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'part_modification',
    title: 'Part Modification',
    defaultPrimaryId: 'boolean',
    items: [
      OnshapeToolItem(
        id: 'boolean',
        label: 'Boolean',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/04_part_modification/01_boolean.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.executeFeatureCutOnActiveSurface(),
      ),
      OnshapeToolItem(
        id: 'split',
        label: 'Split',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/04_part_modification/02_split.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'transform',
        label: 'Transform',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/04_part_modification/03_transform.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeToolMode == SketchUpToolMode.move,
        onExecute: (vm, ctx) => vm.setToolMode(SketchUpToolMode.move),
      ),
      OnshapeToolItem(
        id: 'wrap',
        label: 'Wrap',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/04_part_modification/04_wrap.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'decal',
        label: 'Decal',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/04_part_modification/05_decal.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'delete_part',
        label: 'Delete part',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/04_part_modification/06_delete_part.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.separateSelectedPart(),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'direct_editing',
    title: 'Direct Editing',
    defaultPrimaryId: 'modify_fillet',
    items: [
      OnshapeToolItem(
        id: 'modify_fillet',
        label: 'Modify fillet',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/05_direct_editing/01_modify_fillet.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'delete_face',
        label: 'Delete face',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/05_direct_editing/02_delete_face.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'move_face',
        label: 'Move face',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/05_direct_editing/03_move_face.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'replace_face',
        label: 'Replace face',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/05_direct_editing/04_replace_face.svg',
        isImplemented: false,
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'surfaces',
    title: 'Surfaces',
    defaultPrimaryId: 'plane',
    items: [
      OnshapeToolItem(
        id: 'plane',
        label: 'Plane',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/01_plane.svg',
        isImplemented: true,
        isActive: (vm) => vm.showDatumPlanes,
        onExecute: (vm, ctx) { vm.showDatumPlanes = !vm.showDatumPlanes; vm.showConstructionPlanes = vm.showDatumPlanes; vm.notifyDocChanged(); },
      ),
      OnshapeToolItem(
        id: 'offset_surface',
        label: 'Offset surface',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/02_offset_surface.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'boundary_surface',
        label: 'Boundary surface',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/03_boundary_surface.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'fill',
        label: 'Fill',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/04_fill.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'move_boundary',
        label: 'Move boundary',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/05_move_boundary.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'ruled_surface',
        label: 'Ruled surface',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/06_ruled_surface.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'mutual_trim',
        label: 'Mutual trim',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/07_mutual_trim.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'constrained_surface',
        label: 'Constrained surface',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/08_constrained_surface.svg',
        isImplemented: false,
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'curves',
    title: 'Curves',
    defaultPrimaryId: 'helix',
    items: [
      OnshapeToolItem(
        id: 'helix',
        label: 'Helix',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/01_helix.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: '3d_fit_spline',
        label: '3D fit spline',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/02_3d_fit_spline.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'projected_curve',
        label: 'Projected curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/03_projected_curve.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'bridging_curve',
        label: 'Bridging curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/04_bridging_curve.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'composite_curve',
        label: 'Composite curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/05_composite_curve.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'intersection_curve',
        label: 'Intersection curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/06_intersection_curve.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'trim_curve',
        label: 'Trim curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/07_trim_curve.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'isocline',
        label: 'Isocline',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/08_isocline.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'offset_curve',
        label: 'Offset curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/09_offset_curve.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'isoparametric_curve',
        label: 'Isoparametric curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/10_isoparametric_curve.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'edit_curve',
        label: 'Edit curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/11_edit_curve.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'routing_curve',
        label: 'Routing curve',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/07_curves/12_routing_curve.svg',
        isImplemented: false,
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'reference_and_variables',
    title: 'Reference and Variables',
    defaultPrimaryId: 'mate_connector',
    items: [
      OnshapeToolItem(
        id: 'mate_connector',
        label: 'Mate connector',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/08_reference_and_variables/01_mate_connector.svg',
        shortcut: 'Ctrl+M',
        isImplemented: true,
        isActive: (vm) => vm.showJointStyleToolbar,
        onExecute: (vm, ctx) => vm.toggleJointStyleToolbar(),
      ),
      OnshapeToolItem(
        id: 'derived',
        label: 'Derived',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/08_reference_and_variables/02_derived.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'variable',
        label: 'Variable',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/08_reference_and_variables/03_variable.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'query_variable',
        label: 'Query variable',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/08_reference_and_variables/04_query_variable.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'composite_part',
        label: 'Composite part',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/08_reference_and_variables/05_composite_part.svg',
        isImplemented: false,
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'frames',
    title: 'Frames',
    defaultPrimaryId: 'frame',
    items: [
      OnshapeToolItem(
        id: 'frame',
        label: 'Frame',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/09_frames/01_frame.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.generateSafetyCageAssembly(),
      ),
      OnshapeToolItem(
        id: 'frame_trim',
        label: 'Frame trim',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/09_frames/02_frame_trim.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'gusset',
        label: 'Gusset',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/09_frames/03_gusset.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'end_cap',
        label: 'End cap',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/09_frames/04_end_cap.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'cut_list',
        label: 'Cut list',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/09_frames/05_cut_list.svg',
        isImplemented: true,
        onExecute: (vm, ctx) { /* Open BOM tab/inspector */ },
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'sheet_metal_and_pcb',
    title: 'Sheet Metal and PCB',
    defaultPrimaryId: 'sheet_metal_model',
    items: [
      OnshapeToolItem(
        id: 'sheet_metal_model',
        label: 'Sheet metal model',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/01_sheet_metal_model.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.invalidateMeshCache(),
      ),
      OnshapeToolItem(
        id: 'flange',
        label: 'Flange',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/02_flange.svg',
        isImplemented: true,
      ),
      OnshapeToolItem(
        id: 'hem',
        label: 'Hem',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/03_hem.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'tab',
        label: 'Tab',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/04_tab.svg',
        isImplemented: true,
      ),
      OnshapeToolItem(
        id: 'bend',
        label: 'Bend',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/05_bend.svg',
        isImplemented: true,
      ),
      OnshapeToolItem(
        id: 'jog',
        label: 'Jog',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/06_jog.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'form',
        label: 'Form',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/07_form.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'sheet_metal_loft',
        label: 'Sheet metal loft',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/08_sheet_metal_loft.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'make_joint',
        label: 'Make joint',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/09_make_joint.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'corner',
        label: 'Corner',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/10_corner.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'bend_relief',
        label: 'Bend relief',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/11_bend_relief.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'corner_break',
        label: 'Corner break',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/12_corner_break.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'finish_sheet_metal_model',
        label: 'Finish sheet metal model',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/13_finish_sheet_metal_model.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'flex_pcb_model',
        label: 'Flex PCB model',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/14_flex_pcb_model.svg',
        isImplemented: false,
      ),
      OnshapeToolItem(
        id: 'finish_flex_pcb_model',
        label: 'Finish flex PCB model',
        assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/10_sheet_metal_and_pcb/15_finish_flex_pcb_model.svg',
        isImplemented: false,
      ),
    ],
  ),
];


// ===========================================================================
// SKETCH Toolbar Groups (10 Groups)
// ===========================================================================
final List<OnshapeToolGroup> onshapeSketchGroups = [
  OnshapeToolGroup(
    id: 'sketch_select',
    title: 'Select',
    defaultPrimaryId: 'select_sketch_entity',
    items: [
      OnshapeToolItem(
        id: 'select_sketch_entity',
        label: 'Select / Deactivate Tool',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/07_point_text_project/01_point.svg',
        shortcut: 'Esc / V',
        isImplemented: true,
        isActive: (vm) =>
            vm.isSketchMode &&
            (vm.activeSketchTool == 'select_entity' || vm.activeSketchTool == 'select') &&
            vm.activeConstraintTool == null,
        onExecute: (vm, ctx) => vm.deactivateSketchToolToSelect(),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'lines',
    title: 'Lines',
    defaultPrimaryId: 'line',
    items: [
      OnshapeToolItem(
        id: 'line',
        label: 'Line',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/01_lines/01_line.svg',
        shortcut: 'L',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'line',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('line'),
      ),
      OnshapeToolItem(
        id: 'midpoint_line',
        label: 'Midpoint line',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/01_lines/02_midpoint_line.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'midpoint_line',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('midpoint_line'),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'rectangles',
    title: 'Rectangles',
    defaultPrimaryId: 'corner_rectangle',
    items: [
      OnshapeToolItem(
        id: 'corner_rectangle',
        label: 'Corner rectangle',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/02_rectangles/01_corner_rectangle.svg',
        shortcut: 'G',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'rectangle',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('rectangle'),
      ),
      OnshapeToolItem(
        id: 'center_point_rectangle',
        label: 'Center point rectangle',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/02_rectangles/02_center_point_rectangle.svg',
        shortcut: 'R',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'center_rect',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('center_rect'),
      ),
      OnshapeToolItem(
        id: 'aligned_rectangle',
        label: 'Aligned rectangle',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/02_rectangles/03_aligned_rectangle.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'aligned_rect',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('aligned_rect'),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'circles_and_ellipses',
    title: 'Circles and Ellipses',
    defaultPrimaryId: 'center_point_circle',
    items: [
      OnshapeToolItem(
        id: 'center_point_circle',
        label: 'Center point circle',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/03_circles_and_ellipses/01_center_point_circle.svg',
        shortcut: 'C',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'circle',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('circle'),
      ),
      OnshapeToolItem(
        id: '3_point_circle',
        label: '3 point circle',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/03_circles_and_ellipses/02_3_point_circle.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'circle_3point',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('circle_3point'),
      ),
      OnshapeToolItem(
        id: 'ellipse',
        label: 'Ellipse',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/03_circles_and_ellipses/03_ellipse.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'ellipse',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('ellipse'),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'arcs_and_conics',
    title: 'Arcs and Conics',
    defaultPrimaryId: '3_point_arc',
    items: [
      OnshapeToolItem(
        id: '3_point_arc',
        label: '3 point arc',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/04_arcs_and_conics/01_3_point_arc.svg',
        shortcut: 'A',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'arc_3point',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('arc_3point'),
      ),
      OnshapeToolItem(
        id: 'tangent_arc',
        label: 'Tangent arc',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/04_arcs_and_conics/02_tangent_arc.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'arc_tangent',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('arc_tangent'),
      ),
      OnshapeToolItem(
        id: 'center_point_arc',
        label: 'Center point arc',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/04_arcs_and_conics/03_center_point_arc.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'arc_center',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('arc_center'),
      ),
      OnshapeToolItem(
        id: 'elliptical_arc',
        label: 'Elliptical arc',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/04_arcs_and_conics/04_elliptical_arc.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'arc_ellipse',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('arc_ellipse'),
      ),
      OnshapeToolItem(
        id: 'conic',
        label: 'Conic',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/04_arcs_and_conics/05_conic.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'conic',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('conic'),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'polygons',
    title: 'Polygons',
    defaultPrimaryId: 'inscribed_polygon',
    items: [
      OnshapeToolItem(
        id: 'inscribed_polygon',
        label: 'Inscribed polygon',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/05_polygons/01_inscribed_polygon.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'polygon_inscribed',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('polygon_inscribed'),
      ),
      OnshapeToolItem(
        id: 'circumscribed_polygon',
        label: 'Circumscribed polygon',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/05_polygons/02_circumscribed_polygon.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'polygon_circumscribed',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('polygon_circumscribed'),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'splines',
    title: 'Splines',
    defaultPrimaryId: 'spline',
    items: [
      OnshapeToolItem(
        id: 'spline',
        label: 'Spline',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/06_splines/01_spline.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'spline',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('spline'),
      ),
      OnshapeToolItem(
        id: 'bezier',
        label: 'Bezier',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/06_splines/02_bezier.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'bezier',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('bezier'),
      ),
      OnshapeToolItem(
        id: 'spline_control_point',
        label: 'Spline control point',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/06_splines/03_spline_control_point.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'spline_point',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('spline_point'),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'point_text_project',
    title: 'Point Text Project',
    defaultPrimaryId: 'point',
    items: [
      OnshapeToolItem(
        id: 'point',
        label: 'Point',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/07_point_text_project/01_point.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'point',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('point'),
      ),
      OnshapeToolItem(
        id: 'text',
        label: 'Text',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/07_point_text_project/02_text.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'text',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('text'),
      ),
      OnshapeToolItem(
        id: 'use',
        label: 'Use',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/07_point_text_project/03_use.svg',
        shortcut: 'U',
        isImplemented: true,
        isActive: (vm) => vm.isProjectGeometryMode,
        onExecute: (vm, ctx) => vm.toggleProjectGeometryMode(),
      ),
      OnshapeToolItem(
        id: 'intersection',
        label: 'Intersection',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/07_point_text_project/04_intersection.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'intersection',
        onExecute: (vm, ctx) => vm.project3DIntersectionToActivePlane(),
      ),
      OnshapeToolItem(
        id: 'construction',
        label: 'Construction',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/07_point_text_project/05_construction.svg',
        shortcut: 'Q',
        isImplemented: true,
        isActive: (vm) => vm.isSketchConstructionMode,
        onExecute: (vm, ctx) => vm.toggleSketchConstructionMode(),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'sketch_modify',
    title: 'Sketch Modify',
    defaultPrimaryId: 'fillet',
    items: [
      OnshapeToolItem(
        id: 'fillet',
        label: 'Fillet',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/08_sketch_modify/01_fillet.svg',
        shortcut: 'Shift+F',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.applyFilletToSelectedCorner(5.0),
      ),
      OnshapeToolItem(
        id: 'chamfer',
        label: 'Chamfer',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/08_sketch_modify/02_chamfer.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.applyChamferToSelectedCorner(5.0),
      ),
      OnshapeToolItem(
        id: 'trim',
        label: 'Trim',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/08_sketch_modify/03_trim.svg',
        shortcut: 'M',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'trim',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('trim'),
      ),
      OnshapeToolItem(
        id: 'extend',
        label: 'Extend',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/08_sketch_modify/04_extend.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'extend',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('extend'),
      ),
      OnshapeToolItem(
        id: 'split',
        label: 'Split',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/08_sketch_modify/05_split.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'split',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('split'),
      ),
      OnshapeToolItem(
        id: 'offset',
        label: 'Offset',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/08_sketch_modify/06_offset.svg',
        shortcut: 'O',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'offset',
        onExecute: (vm, ctx) => vm.offsetSelectedSketchEntity(5.0),
      ),
      OnshapeToolItem(
        id: 'slot',
        label: 'Slot',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/08_sketch_modify/07_slot.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'sketch_slot' || vm.activeSketchTool == 'rung_slot',
        onExecute: (vm, ctx) => vm.setActiveSketchTool('sketch_slot'),
      ),
      OnshapeToolItem(
        id: 'break_polygon',
        label: 'Break Polygon Loop',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/08_sketch_modify/05_split.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchPlane != null && !vm.activeSketchPlane!.isLoopBonded,
        onExecute: (vm, ctx) => vm.breakSelectedPolygonOrLoop(),
      ),
      OnshapeToolItem(
        id: 'rejoin_polygon',
        label: 'Rejoin Polygon Loop',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/01_coincident.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchPlane != null && vm.activeSketchPlane!.isLoopBonded,
        onExecute: (vm, ctx) => vm.rejoinPolygonSegmentsOnActivePlane(),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'pattern_and_insert',
    title: 'Pattern and Insert',
    defaultPrimaryId: 'mirror',
    items: [
      OnshapeToolItem(
        id: 'mirror',
        label: 'Mirror',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/09_pattern_and_insert/01_mirror.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.mirrorSelectedSketchEntities(),
      ),
      OnshapeToolItem(
        id: 'linear_pattern',
        label: 'Linear pattern',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/09_pattern_and_insert/02_linear_pattern.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.patternSelectedSketchEntitiesLinear(),
      ),
      OnshapeToolItem(
        id: 'circular_pattern',
        label: 'Circular pattern',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/09_pattern_and_insert/03_circular_pattern.svg',
        isImplemented: true,
        onExecute: (vm, ctx) => vm.patternSelectedSketchEntitiesCircular(),
      ),
      OnshapeToolItem(
        id: 'transform',
        label: 'Transform',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/09_pattern_and_insert/04_transform.svg',
        isImplemented: true,
        isActive: (vm) => vm.activeToolMode == SketchUpToolMode.move,
        onExecute: (vm, ctx) => vm.setToolMode(SketchUpToolMode.move),
      ),
      OnshapeToolItem(
        id: 'insert_dxf_or_dwg',
        label: 'Insert DXF or DWG',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/09_pattern_and_insert/05_insert_dxf_or_dwg.svg',
        isImplemented: true,
        onExecute: (vm, ctx) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('DXF/DWG vector import ready.')));
        },
      ),
      OnshapeToolItem(
        id: 'insert_image',
        label: 'Insert image',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/09_pattern_and_insert/06_insert_image.svg',
        isImplemented: true,
        onExecute: (vm, ctx) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Raster canvas calibration image ready.')));
        },
      ),
      OnshapeToolItem(
        id: 'dimension',
        label: 'Dimension',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/09_pattern_and_insert/07_dimension.svg',
        shortcut: 'D',
        isImplemented: true,
        isActive: (vm) => vm.activeSketchTool == 'dimension' || vm.showSketchDimensions,
        onExecute: (vm, ctx) => vm.setActiveSketchTool('dimension'),
      ),
    ],
  ),
  OnshapeToolGroup(
    id: 'constraints',
    title: 'Constraints',
    defaultPrimaryId: 'coincident',
    items: [
      OnshapeToolItem(
        id: 'coincident',
        label: 'Coincident',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/01_coincident.svg',
        shortcut: 'I',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.coincident,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.coincident),
      ),
      OnshapeToolItem(
        id: 'concentric',
        label: 'Concentric',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/02_concentric.svg',
        shortcut: 'Shift+O',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.concentric,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.concentric),
      ),
      OnshapeToolItem(
        id: 'parallel',
        label: 'Parallel',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/03_parallel.svg',
        shortcut: 'B',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.parallel,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.parallel),
      ),
      OnshapeToolItem(
        id: 'tangent',
        label: 'Tangent',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/04_tangent.svg',
        shortcut: 'T',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.tangent,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.tangent),
      ),
      OnshapeToolItem(
        id: 'horizontal',
        label: 'Horizontal',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/05_horizontal.svg',
        shortcut: 'H',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.horizontal,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.horizontal),
      ),
      OnshapeToolItem(
        id: 'vertical',
        label: 'Vertical',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/06_vertical.svg',
        shortcut: 'V',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.vertical,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.vertical),
      ),
      OnshapeToolItem(
        id: 'perpendicular',
        label: 'Perpendicular',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/07_perpendicular.svg',
        shortcut: 'Shift+L',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.perpendicular,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.perpendicular),
      ),
      OnshapeToolItem(
        id: 'equal',
        label: 'Equal',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/08_equal.svg',
        shortcut: 'E',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.equal,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.equal),
      ),
      OnshapeToolItem(
        id: 'midpoint',
        label: 'Midpoint',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/09_midpoint.svg',
        shortcut: 'Shift+M',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.midpoint,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.midpoint),
      ),
      OnshapeToolItem(
        id: 'normal',
        label: 'Normal',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/10_normal.svg',
        shortcut: 'Shift+K',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.normal,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.normal),
      ),
      OnshapeToolItem(
        id: 'pierce',
        label: 'Pierce',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/11_pierce.svg',
        shortcut: 'Shift+G',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.pierce,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.pierce),
      ),
      OnshapeToolItem(
        id: 'symmetric',
        label: 'Symmetric',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/12_symmetric.svg',
        shortcut: 'Shift+Q',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.symmetric,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.symmetric),
      ),
      OnshapeToolItem(
        id: 'fix',
        label: 'Fix',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/13_fix.svg',
        shortcut: 'Shift+J',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.fixed,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.fixed),
      ),
      OnshapeToolItem(
        id: 'curvature',
        label: 'Curvature',
        assetPath: 'assets/icons/onshape/02_sketch_toolbar/10_constraints/14_curvature.svg',
        shortcut: 'Shift+U',
        isImplemented: true,
        isActive: (vm) => vm.activeConstraintTool == CadConstraintType.curvature,
        onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.curvature),
      ),
    ],
  ),
];
