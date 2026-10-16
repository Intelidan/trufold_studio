// Complete Onshape Dynamic Contextual Ribbon Toolbar
// TruFold Assembly Studio - Phase 7 Onshape Transformation
// Seamlessly switches between 3D Modeling Toolbar and 2D Sketch Toolbar.
// Features responsive unpacking matching SS1/SS2 on wide screens,
// and elegant grouped sub-menus matching PDF page 1 / page 14 on standard screens.

import 'package:flutter/material.dart';
import '../../../viewmodels/assembly_studio_viewmodel.dart';
import '../../theme/assembly_studio_theme.dart';
import '../../../models/onshape_toolbar_items.dart';
import 'onshape_toolbar_widgets.dart';

class AssemblyOnshapeToolbar extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblyOnshapeToolbar({super.key, required this.viewModel});

  @override
  State<AssemblyOnshapeToolbar> createState() => _AssemblyOnshapeToolbarState();
}

class _AssemblyOnshapeToolbarState extends State<AssemblyOnshapeToolbar> {
  // Map of group ID -> current primary tool item
  final Map<String, OnshapeToolItem> _primaryTools = {};

  OnshapeToolItem _getPrimaryTool(OnshapeToolGroup group) {
    return _primaryTools[group.id] ?? group.defaultPrimary;
  }

  void _setPrimaryTool(OnshapeToolGroup group, OnshapeToolItem item) {
    setState(() {
      _primaryTools[group.id] = item;
    });
  }

  OnshapeToolGroup _findGroup(List<OnshapeToolGroup> list, String groupId) {
    return list.firstWhere(
      (g) => g.id == groupId,
      orElse: () => list.first,
    );
  }

  OnshapeToolItem _findItem(OnshapeToolGroup group, String itemId) {
    return group.items.firstWhere(
      (it) => it.id == itemId,
      orElse: () => group.items.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final isSketch = vm.isSketchMode;

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: AssemblyStudioTheme.onshapeToolbarBg,
        border: Border(bottom: BorderSide(color: AssemblyStudioTheme.onshapeBorder, width: 1.0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1350;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: isSketch
                  ? _buildSketchToolbar(context, vm, isWide)
                  : _build3DModelingToolbar(context, vm, isWide),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. 3D MODELLING TOOLBAR (SS1 / PDF Page 1)
  // ---------------------------------------------------------------------------
  List<Widget> _build3DModelingToolbar(BuildContext context, AssemblyStudioViewModel vm, bool isWide) {
    final groups = onshape3dModelingGroups;
    final gBase = _findGroup(groups, 'base_features');
    final gEdge = _findGroup(groups, 'edge_and_body_features');
    final gPattern = _findGroup(groups, 'pattern_and_mirror');
    final gPartMod = _findGroup(groups, 'part_modification');
    final gDirect = _findGroup(groups, 'direct_editing');
    final gSurfaces = _findGroup(groups, 'surfaces');
    final gCurves = _findGroup(groups, 'curves');
    final gRef = _findGroup(groups, 'reference_and_variables');
    final gFrames = _findGroup(groups, 'frames');
    final gSheetMetal = _findGroup(groups, 'sheet_metal_and_pcb');

    final widgets = <Widget>[
      // Undo & Redo
      _buildIconButton(
        assetPath: 'assets/icons/onshape/undo.svg',
        tooltip: 'Undo (Ctrl+Z)',
        onTap: vm.undo,
        isEnabled: vm.canUndo,
      ),
      _buildIconButton(
        assetPath: 'assets/icons/onshape/redo.svg',
        tooltip: 'Redo (Ctrl+Y)',
        onTap: vm.redo,
        isEnabled: vm.canRedo,
      ),

      const OnshapeToolbarDivider(),

      // Sketch Mode Activation Button
      _buildSketchButton(vm: vm),

      const OnshapeToolbarDivider(),
    ];

    if (isWide) {
      // --- RESPONSIVE EXPANDED LAYOUT (Matches SS1) ---
      // Base Features: Extrude, Revolve, Sweep, Loft, Thicken (v)
      widgets.add(OnshapeToolButton(item: _findItem(gBase, 'extrude'), viewModel: vm));
      widgets.add(OnshapeToolButton(item: _findItem(gBase, 'revolve'), viewModel: vm));
      widgets.add(OnshapeToolButton(item: _findItem(gBase, 'sweep'), viewModel: vm));
      widgets.add(OnshapeToolButton(item: _findItem(gBase, 'loft'), viewModel: vm));
      widgets.add(_buildSplitButton(gBase, defaultItem: _findItem(gBase, 'thicken')));

      widgets.add(const OnshapeToolbarDivider());

      // Edge and Body Features: Fillet (v), Chamfer (v), Draft (v), Rib (v), Shell (v), Hole (v), External thread (v)
      widgets.add(_buildSplitButton(gEdge, defaultItem: _findItem(gEdge, 'fillet')));
      widgets.add(_buildSplitButton(gEdge, defaultItem: _findItem(gEdge, 'chamfer')));
      widgets.add(_buildSplitButton(gEdge, defaultItem: _findItem(gEdge, 'draft')));
      widgets.add(_buildSplitButton(gEdge, defaultItem: _findItem(gEdge, 'rib')));
      widgets.add(_buildSplitButton(gEdge, defaultItem: _findItem(gEdge, 'shell')));
      widgets.add(_buildSplitButton(gEdge, defaultItem: _findItem(gEdge, 'hole')));
      widgets.add(_buildSplitButton(gEdge, defaultItem: _findItem(gEdge, 'external_thread')));

      widgets.add(const OnshapeToolbarDivider());

      // Pattern & Mirror: Linear pattern (v), Mirror
      widgets.add(_buildSplitButton(gPattern, defaultItem: _findItem(gPattern, 'linear_pattern')));
      widgets.add(OnshapeToolButton(item: _findItem(gPattern, 'mirror'), viewModel: vm));

      widgets.add(const OnshapeToolbarDivider());

      // Part Modification: Boolean (v), Split (v), Transform (v), Wrap (v)
      widgets.add(_buildSplitButton(gPartMod, defaultItem: _findItem(gPartMod, 'boolean')));
      widgets.add(_buildSplitButton(gPartMod, defaultItem: _findItem(gPartMod, 'split')));
      widgets.add(_buildSplitButton(gPartMod, defaultItem: _findItem(gPartMod, 'transform')));
      widgets.add(_buildSplitButton(gPartMod, defaultItem: _findItem(gPartMod, 'wrap')));

      widgets.add(const OnshapeToolbarDivider());

      // Direct Editing: Modify fillet (v)
      widgets.add(_buildSplitButton(gDirect));

      widgets.add(const OnshapeToolbarDivider());

      // Surfaces: Plane (v), Offset surface (v)
      widgets.add(_buildSplitButton(gSurfaces, defaultItem: _findItem(gSurfaces, 'plane')));
      widgets.add(_buildSplitButton(gSurfaces, defaultItem: _findItem(gSurfaces, 'offset_surface')));

      widgets.add(const OnshapeToolbarDivider());

      // Curves: Helix (v), 3D fit spline (v)
      widgets.add(_buildSplitButton(gCurves, defaultItem: _findItem(gCurves, 'helix')));
      widgets.add(_buildSplitButton(gCurves, defaultItem: _findItem(gCurves, '3d_fit_spline')));

      widgets.add(const OnshapeToolbarDivider());

      // Reference & Variables: Mate connector (v), Variable (v)
      widgets.add(_buildSplitButton(gRef, defaultItem: _findItem(gRef, 'mate_connector')));
      widgets.add(_buildSplitButton(gRef, defaultItem: _findItem(gRef, 'variable')));

      widgets.add(const OnshapeToolbarDivider());

      // Frames: Frame (v), Gusset (v)
      widgets.add(_buildSplitButton(gFrames, defaultItem: _findItem(gFrames, 'frame')));
      widgets.add(_buildSplitButton(gFrames, defaultItem: _findItem(gFrames, 'gusset')));

      widgets.add(const OnshapeToolbarDivider());

      // Sheet Metal: Sheet metal model (v), Flange (v)
      widgets.add(_buildSplitButton(gSheetMetal, defaultItem: _findItem(gSheetMetal, 'sheet_metal_model')));
      widgets.add(_buildSplitButton(gSheetMetal, defaultItem: _findItem(gSheetMetal, 'flange')));
    } else {
      // --- STANDARD / COMPACT SUB-MENU LAYOUT (Matches PDF Page 1) ---
      // 10 main groups with their primary icon and dropdown caret
      widgets.add(_buildSplitButton(gBase));
      widgets.add(_buildSplitButton(gEdge));
      widgets.add(_buildSplitButton(gPattern));
      widgets.add(_buildSplitButton(gPartMod));
      widgets.add(_buildSplitButton(gDirect));
      widgets.add(_buildSplitButton(gSurfaces));
      widgets.add(_buildSplitButton(gCurves));
      widgets.add(_buildSplitButton(gRef));
      widgets.add(_buildSplitButton(gFrames));
      widgets.add(_buildSplitButton(gSheetMetal));
    }

    // Right-side view utilities
    widgets.add(const OnshapeToolbarDivider());
    widgets.addAll(_buildViewUtilities(vm));

    return widgets;
  }

  // ---------------------------------------------------------------------------
  // 2. SKETCH TOOLBAR (SS2 / PDF Page 14)
  // ---------------------------------------------------------------------------
  List<Widget> _buildSketchToolbar(BuildContext context, AssemblyStudioViewModel vm, bool isWide) {
    final groups = onshapeSketchGroups;
    final gLines = _findGroup(groups, 'lines');
    final gRect = _findGroup(groups, 'rectangles');
    final gCircle = _findGroup(groups, 'circles_and_ellipses');
    final gArc = _findGroup(groups, 'arcs_and_conics');
    final gPoly = _findGroup(groups, 'polygons');
    final gSpline = _findGroup(groups, 'splines');
    final gPointText = _findGroup(groups, 'point_text_project');
    final gModify = _findGroup(groups, 'sketch_modify');
    final gPattern = _findGroup(groups, 'pattern_and_insert');
    final gConstraints = _findGroup(groups, 'constraints');

    // 3D base features shown in sketch toolbar (Extrude, Revolve)
    final g3dBase = _findGroup(onshape3dModelingGroups, 'base_features');
    final extrudeItem = _findItem(g3dBase, 'extrude');
    final revolveItem = _findItem(g3dBase, 'revolve');

    final widgets = <Widget>[
      // Extrude & Revolve buttons
      OnshapeToolButton(item: extrudeItem, viewModel: vm),
      OnshapeToolButton(item: revolveItem, viewModel: vm),

      const OnshapeToolbarDivider(),
    ];

    if (isWide) {
      // --- RESPONSIVE EXPANDED SKETCH LAYOUT (Matches SS2) ---
      // Lines, Rect, Circle, Arc, Poly, Spline
      widgets.add(_buildSplitButton(gLines));
      widgets.add(_buildSplitButton(gRect));
      widgets.add(_buildSplitButton(gCircle));
      widgets.add(_buildSplitButton(gArc));
      widgets.add(_buildSplitButton(gPoly));
      widgets.add(_buildSplitButton(gSpline));

      // Point, Text, Use (v), Construction
      widgets.add(OnshapeToolButton(item: _findItem(gPointText, 'point'), viewModel: vm));
      widgets.add(OnshapeToolButton(item: _findItem(gPointText, 'text'), viewModel: vm));
      widgets.add(_buildSplitButton(gPointText, defaultItem: _findItem(gPointText, 'use')));
      widgets.add(OnshapeToolButton(item: _findItem(gPointText, 'construction'), viewModel: vm));

      widgets.add(const OnshapeToolbarDivider());

      // Modify: Fillet (v), Trim (v), Offset (v), Slot
      widgets.add(_buildSplitButton(gModify, defaultItem: _findItem(gModify, 'fillet')));
      widgets.add(_buildSplitButton(gModify, defaultItem: _findItem(gModify, 'trim')));
      widgets.add(_buildSplitButton(gModify, defaultItem: _findItem(gModify, 'offset')));
      widgets.add(OnshapeToolButton(item: _findItem(gModify, 'slot'), viewModel: vm));

      widgets.add(const OnshapeToolbarDivider());

      // Pattern / Insert: Mirror (v), Linear Pattern (v), Insert DXF (v), Dimension
      widgets.add(_buildSplitButton(gPattern, defaultItem: _findItem(gPattern, 'mirror')));
      widgets.add(_buildSplitButton(gPattern, defaultItem: _findItem(gPattern, 'linear_pattern')));
      widgets.add(_buildSplitButton(gPattern, defaultItem: _findItem(gPattern, 'insert_dxf_or_dwg')));
      widgets.add(OnshapeToolButton(item: _findItem(gPattern, 'dimension'), viewModel: vm));

      widgets.add(const OnshapeToolbarDivider());

      // Constraints Matrix: all 14 constraints laid out directly side-by-side
      for (final cItem in gConstraints.items) {
        widgets.add(OnshapeToolButton(item: cItem, viewModel: vm));
      }
    } else {
      // --- STANDARD / COMPACT SUB-MENU SKETCH LAYOUT (Matches PDF Page 14) ---
      widgets.add(_buildSplitButton(gLines));
      widgets.add(_buildSplitButton(gRect));
      widgets.add(_buildSplitButton(gCircle));
      widgets.add(_buildSplitButton(gArc));
      widgets.add(_buildSplitButton(gPoly));
      widgets.add(_buildSplitButton(gSpline));

      widgets.add(OnshapeToolButton(item: _findItem(gPointText, 'point'), viewModel: vm));
      widgets.add(OnshapeToolButton(item: _findItem(gPointText, 'text'), viewModel: vm));
      widgets.add(_buildSplitButton(gPointText, defaultItem: _findItem(gPointText, 'use')));
      widgets.add(OnshapeToolButton(item: _findItem(gPointText, 'construction'), viewModel: vm));

      widgets.add(const OnshapeToolbarDivider());

      widgets.add(_buildSplitButton(gModify));
      widgets.add(OnshapeToolButton(item: _findItem(gPattern, 'dimension'), viewModel: vm));

      widgets.add(const OnshapeToolbarDivider());

      // Constraints group (Equal '=' as primary icon with dropdown caret)
      widgets.add(_buildSplitButton(gConstraints, defaultItem: _findItem(gConstraints, 'equal')));
    }

    // Right-side view utilities
    widgets.add(const OnshapeToolbarDivider());
    widgets.addAll(_buildViewUtilities(vm));

    return widgets;
  }

  // ---------------------------------------------------------------------------
  // Helper Builders
  // ---------------------------------------------------------------------------
  Widget _buildSplitButton(OnshapeToolGroup group, {OnshapeToolItem? defaultItem}) {
    final primary = defaultItem ?? _getPrimaryTool(group);
    return OnshapeToolbarSplitButton(
      group: group,
      primaryItem: primary,
      viewModel: widget.viewModel,
      onSelectTool: (selected) => _setPrimaryTool(group, selected),
    );
  }

  Widget _buildSketchButton({required AssemblyStudioViewModel vm}) {
    final isSketch = vm.isSketchMode;
    return Tooltip(
      message: isSketch
          ? 'Finish active sketch (Enter)'
          : 'New Sketch (Shift+S)',
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (isSketch) {
              vm.finishSketch();
            } else {
              vm.enterSketchMode();
            }
          },
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isSketch ? const Color(0xFFE0EDFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isSketch ? const Color(0xFF2F80ED) : const Color(0xFFD0D5DD),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OnshapeIconWidget(
                  assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/01_base_features/01_extrude.svg',
                  size: 16,
                  isEnabled: true,
                  isActive: isSketch,
                ),
                const SizedBox(width: 5),
                Text(
                  'Sketch',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSketch ? const Color(0xFF1570EF) : const Color(0xFF344054),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required String assetPath,
    required String tooltip,
    required VoidCallback onTap,
    required bool isEnabled,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: isEnabled ? onTap : null,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Center(
              child: OnshapeIconWidget(
                assetPath: assetPath,
                size: 20,
                isEnabled: isEnabled,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildViewUtilities(AssemblyStudioViewModel vm) {
    return [
      // View Normal to (N)
      Tooltip(
        message: 'View Normal To (N)',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: vm.alignCameraToActivePlaneNormal,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: const Center(
                child: OnshapeIconWidget(
                  assetPath: 'assets/icons/onshape/normal_view.svg',
                  size: 20,
                  isEnabled: true,
                ),
              ),
            ),
          ),
        ),
      ),

      // Datum Planes Toggle (P)
      Tooltip(
        message: 'Toggle Planes Visibility (P)',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              vm.showDatumPlanes = !vm.showDatumPlanes;
              vm.showConstructionPlanes = vm.showDatumPlanes;
              vm.notifyDocChanged();
            },
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: vm.showDatumPlanes ? const Color(0xFFE0EDFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: vm.showDatumPlanes ? const Color(0xFF2F80ED) : Colors.transparent,
                  width: 1.0,
                ),
              ),
              child: Center(
                child: OnshapeIconWidget(
                  assetPath: 'assets/icons/onshape/01_3d_modelling_toolbar/06_surfaces/01_plane.svg',
                  size: 20,
                  isEnabled: true,
                  isActive: vm.showDatumPlanes,
                ),
              ),
            ),
          ),
        ),
      ),

      // Zoom to Fit (F)
      Tooltip(
        message: 'Zoom to Fit (F)',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: vm.zoomToFit,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: const Center(
                child: OnshapeIconWidget(
                  assetPath: 'assets/icons/onshape/zoom_fit.svg',
                  size: 20,
                  isEnabled: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
