import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sheet_metal_studio/models/cad_constraint.dart';
import '../../sheet_metal_studio/models/cad_primitives.dart';
import '../viewmodels/assembly_studio_viewmodel.dart';
import 'theme/assembly_studio_theme.dart';
import 'widgets/assembly_scene_hierarchy_tree.dart';
import 'widgets/assembly_browser_tree.dart';
import 'widgets/assembly_asset_drawer.dart';
import 'widgets/assembly_inspector_panel.dart';
import 'widgets/assembly_3d_viewport.dart';
import 'widgets/assembly_onshape_top_bar.dart';

enum LeftPanelMode { browser, outliner }

/// Minimalist CAD Studio Interface modeled on PTC Onshape.
/// Follows Onshape's exact lightweight, glare-free light aesthetic,
/// single dynamic contextual ribbon, floating sketch feature card, and hotkeys.
class AssemblyStudioScreen extends StatefulWidget {
  final AssemblyStudioViewModel? viewModel;

  const AssemblyStudioScreen({super.key, this.viewModel});

  @override
  State<AssemblyStudioScreen> createState() => _AssemblyStudioScreenState();
}

class _AssemblyStudioScreenState extends State<AssemblyStudioScreen> {
  late final AssemblyStudioViewModel _viewModel;
  bool _isBottomDrawerCollapsed = true;
  bool _isLeftOutlinerOpen = true;
  bool _isRightInspectorOpen = true;
  int _activeTabIndex = 0;
  final LeftPanelMode _leftPanelMode = LeftPanelMode.browser;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? AssemblyStudioViewModel();
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    if (widget.viewModel == null) {
      _viewModel.dispose();
    }
    super.dispose();
  }

  void _onViewModelChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = AssemblyStudioTheme(isLight: _viewModel.isLightBackground);

    return CallbackShortcuts(
      bindings: {
        // Undo / Redo
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => _viewModel.undo(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => _viewModel.redo(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () => _viewModel.redo(),

        // Onshape Part Studio / Modeling Shortcuts
        const SingleActivator(LogicalKeyboardKey.keyS, shift: true): () => _viewModel.enterSketchMode(),
        const SingleActivator(LogicalKeyboardKey.keyE, shift: true): () => _viewModel.toggleExtrudeMode(),

        // Onshape 3D Navigation Shortcuts
        const SingleActivator(LogicalKeyboardKey.keyN): () => _viewModel.alignCameraToActivePlaneNormal(),
        const SingleActivator(LogicalKeyboardKey.keyP): () {
          _viewModel.showDatumPlanes = !_viewModel.showDatumPlanes;
          _viewModel.showConstructionPlanes = _viewModel.showDatumPlanes;
          _viewModel.notifyDocChanged();
        },
        const SingleActivator(LogicalKeyboardKey.keyF): () => _viewModel.zoomToFit(),

        // Onshape 2D Sketch Drafting Shortcuts
        const SingleActivator(LogicalKeyboardKey.keyL): () {
          if (_viewModel.isSketchMode) _viewModel.setActiveSketchTool('line');
        },
        const SingleActivator(LogicalKeyboardKey.keyG): () {
          if (_viewModel.isSketchMode) _viewModel.setActiveSketchTool('rectangle');
        },
        const SingleActivator(LogicalKeyboardKey.keyR): () {
          if (_viewModel.isSketchMode) _viewModel.setActiveSketchTool('center_rect');
        },
        const SingleActivator(LogicalKeyboardKey.keyC): () {
          if (_viewModel.isSketchMode) _viewModel.setActiveSketchTool('circle');
        },
        const SingleActivator(LogicalKeyboardKey.keyA): () {
          if (_viewModel.isSketchMode) _viewModel.setActiveSketchTool('arc_3point');
        },
        const SingleActivator(LogicalKeyboardKey.keyU): () {
          if (_viewModel.isSketchMode) _viewModel.toggleProjectGeometryMode();
        },
        const SingleActivator(LogicalKeyboardKey.keyQ): () {
          if (_viewModel.isSketchMode) _viewModel.toggleSketchConstructionMode();
        },
        const SingleActivator(LogicalKeyboardKey.keyD): () {
          if (_viewModel.isSketchMode) _viewModel.toggleSketchDimensions();
        },

        // Onshape Constraints Shortcuts
        const SingleActivator(LogicalKeyboardKey.keyI): () {
          if (_viewModel.isSketchMode) _viewModel.applySketchConstraint(CadConstraintType.coincident);
        },
        const SingleActivator(LogicalKeyboardKey.keyB): () {
          if (_viewModel.isSketchMode) _viewModel.applySketchConstraint(CadConstraintType.parallel);
        },
        const SingleActivator(LogicalKeyboardKey.keyT): () {
          if (_viewModel.isSketchMode) _viewModel.applySketchConstraint(CadConstraintType.tangent);
        },
        const SingleActivator(LogicalKeyboardKey.keyH): () {
          if (_viewModel.isSketchMode) _viewModel.applySketchConstraint(CadConstraintType.horizontal);
        },
        const SingleActivator(LogicalKeyboardKey.keyV): () {
          if (_viewModel.isSketchMode) _viewModel.applySketchConstraint(CadConstraintType.vertical);
        },
        const SingleActivator(LogicalKeyboardKey.keyE): () {
          if (_viewModel.isSketchMode) _viewModel.applySketchConstraint(CadConstraintType.equal);
        },

        // Accept & Cancel
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_viewModel.isSketchMode) _viewModel.exitSketchMode();
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_viewModel.isSketchMode) _viewModel.finishSketch();
        },
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              // 1. Onshape Top Bar: Document Header & Contextual Dynamic Ribbon
              AssemblyOnshapeTopBar(
                viewModel: _viewModel,
                onToggleLeftPanel: () => setState(() => _isLeftOutlinerOpen = !_isLeftOutlinerOpen),
                onToggleRightPanel: () => setState(() => _isRightInspectorOpen = !_isRightInspectorOpen),
                onToggleBottomDrawer: () => setState(() => _isBottomDrawerCollapsed = !_isBottomDrawerCollapsed),
                isLeftPanelOpen: _isLeftOutlinerOpen,
                isRightPanelOpen: _isRightInspectorOpen,
                isBottomDrawerOpen: !_isBottomDrawerCollapsed,
                onResetPositions: () {
                  setState(() {
                    _isLeftOutlinerOpen = true;
                    _isRightInspectorOpen = true;
                    _isBottomDrawerCollapsed = false;
                  });
                },
              ),

              // 2. Main Studio Workspace Layout: Outliner Tree | 3D Viewport + Asset Drawer | Property Grid
              Expanded(
                child: Row(
                  children: [
                    // Left Scene Hierarchy Outliner / CAD Browser Tree
                    if (_isLeftOutlinerOpen)
                      _leftPanelMode == LeftPanelMode.browser
                          ? AssemblyBrowserTree(viewModel: _viewModel, width: 245.0)
                          : AssemblySceneHierarchyTree(viewModel: _viewModel, width: 245.0),

                    // Center 3D Interactive Viewport with direct 3D model editing + Bottom Asset Shelf
                    Expanded(
                      child: Column(
                        children: [
                          // Primary 3D Canvas Viewport (Maximizes Space)
                          Expanded(child: Assembly3DViewport(viewModel: _viewModel)),

                          // Bottom Collapsible Asset View Drawer (Common Parts, Welds, BOM Cut-List)
                          if (!_isBottomDrawerCollapsed)
                            AssemblyAssetDrawer(
                              viewModel: _viewModel,
                              isCollapsed: _isBottomDrawerCollapsed,
                              onToggleCollapse: () {
                                setState(() {
                                  _isBottomDrawerCollapsed = !_isBottomDrawerCollapsed;
                                });
                              },
                            ),
                        ],
                      ),
                    ),

                    // Right Property Grid Inspector
                    if (_isRightInspectorOpen) AssemblyInspectorPanel(viewModel: _viewModel, width: 265.0),
                  ],
                ),
              ),

              // 3. Onshape Document Tabs Bar (Part Studio 1, Assembly 1, +)
              _buildOnshapeDocumentTabsBar(theme),

              // 4. Bottom Minimal Status Bar (Height 20px)
              _buildBottomStatusBar(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnshapeDocumentTabsBar(AssemblyStudioTheme theme) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Tab Manager Icon
          const Tooltip(
            message: 'Tab Manager',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: Icon(Icons.table_chart_rounded, size: 14, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 4),

          // Add Tab Button (+)
          Tooltip(
            message: 'Insert new element',
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: const Icon(Icons.add, size: 12, color: Color(0xFF334155)),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Part Studio 1 Tab
          _buildDocumentTab(
            index: 0,
            label: 'Part Studio 1',
            icon: Icons.view_in_ar_rounded,
            isSelected: _activeTabIndex == 0,
            onTap: () => setState(() => _activeTabIndex = 0),
          ),

          const SizedBox(width: 2),

          // Assembly 1 Tab
          _buildDocumentTab(
            index: 1,
            label: 'Assembly 1',
            icon: Icons.hub_rounded,
            isSelected: _activeTabIndex == 1,
            onTap: () => setState(() => _activeTabIndex = 1),
          ),

          const Spacer(),

          // Asset Drawer Toggle
          Tooltip(
            message: _isBottomDrawerCollapsed ? 'Show Fabrication Drawer' : 'Hide Fabrication Drawer',
            child: InkWell(
              onTap: () => setState(() => _isBottomDrawerCollapsed = !_isBottomDrawerCollapsed),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isBottomDrawerCollapsed ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 13,
                      color: const Color(0xFF475569),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'BOM & Parts',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTab({required int index, required String label, required IconData icon, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          border: isSelected
              ? const Border(
                  top: BorderSide(color: AssemblyStudioTheme.onshapeBlue, width: 2.5),
                  left: BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
                  right: BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isSelected ? AssemblyStudioTheme.onshapeBlue : const Color(0xFF64748B)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatusBar(AssemblyStudioTheme theme) {
    final parts = _viewModel.doc.parts.length;
    final welds = _viewModel.doc.welds.length;
    final tool = _viewModel.activeToolMode.name.toUpperCase();
    final axis = _viewModel.lockedAxis == GizmoAxis.none ? 'FREE' : _viewModel.lockedAxis.name.toUpperCase();
    final isGpu = _viewModel.renderEngine == Cad3dEngineMode.flutterGpu;

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.statusBarBackground,
        border: Border(top: BorderSide(color: theme.statusBarBorder, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 10, color: Color(0xFF34D399)),
                  const SizedBox(width: 5),
                  Text('Ready', style: TextStyle(fontSize: 8.5, color: theme.textTertiary)),
                  const SizedBox(width: 12),
                  Text('Tool: $tool', style: TextStyle(fontSize: 8.5, color: theme.accentSky)),
                  const SizedBox(width: 12),
                  Text('Axis Lock: $axis', style: TextStyle(fontSize: 8.5, color: theme.accentAmber)),
                  const SizedBox(width: 24),
                  Text(
                    'Scene: $parts Parts • $welds Welds • Snap: ${_viewModel.snapToGrid ? "ON" : "OFF"} • 15° Protractor: ${_viewModel.snapTo15Degrees ? "ON" : "OFF"} • Theme: ${_viewModel.isLightBackground ? "LIGHT" : "DARK"}',
                    style: TextStyle(fontSize: 8, color: theme.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Active 3D Engine: ${_viewModel.renderEngine.label}\nClick to toggle between GPU and 2D Canvas',
            child: InkWell(
              onTap: _viewModel.toggleRenderEngine,
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isGpu ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFF0C4A6E).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isGpu ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isGpu ? Icons.speed_rounded : Icons.brush_rounded,
                      size: 9,
                      color: isGpu ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isGpu ? 'Engine: Flutter GPU' : 'Engine: 2D Canvas',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: isGpu ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
