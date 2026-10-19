import '../../../engine/cad_brep_flutter_gpu_scene.dart' show CadToolbarFpsBadge;
// =============================================================================
// studio_ribbon_toolbar.dart
//
// Modern CAD Sketch & Sheet Metal Ribbon for truFold Studio by Danish.
// Features:
// - Decluttered Title Bar with Unique, Colorful, and Fun StudioMenuBar
// - Multi-File Document Tab Bar
// - Enlarged CAD Toolbar with Interactive 3D Animated Action Icons on Hover
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/studio_tab_model.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../studio_tab_bar.dart';
import '../dds/dds_template_library_dialog.dart';
import '../../../services/studio_clipboard_service.dart';
import 'studio_cad_tool_palette.dart';
import 'studio_menu_bar.dart';
import '../branding/trufold_3d_icon.dart';
import '../dds/dds_workspace_screen.dart';
import '../../../../assembly_studio/views/assembly_studio_screen.dart';

class StudioRibbonToolbar extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final List<StudioTab> tabs;
  final int activeTabIndex;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int> onTabClosed;
  final VoidCallback onNewTab;
  final VoidCallback onOpenFile;
  final VoidCallback onSaveFile;
  final VoidCallback? onSaveAsFile;
  final VoidCallback onFinishSketch;
  final VoidCallback? onSaveDdsProject;
  final VoidCallback? onExportDxf;
  final VoidCallback? onMaterialDialog;
  final VoidCallback? onLoadSampleBracket;
  final VoidCallback? onFittingDetails;
  final VoidCallback? onLoadSampleTray;
  final VoidCallback? onOpenTemplateLibrary;
  final VoidCallback? onOpenTemplateAuthoring;
  final VoidCallback? onOpenTdsWindow;
  final VoidCallback? onOpenCmsInspector;

  const StudioRibbonToolbar({
    super.key,
    required this.viewModel,
    required this.tabs,
    required this.activeTabIndex,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onNewTab,
    required this.onOpenFile,
    required this.onSaveFile,
    this.onSaveAsFile,
    required this.onFinishSketch,
    this.onSaveDdsProject,
    this.onExportDxf,
    this.onMaterialDialog,
    this.onLoadSampleBracket,
    this.onFittingDetails,
    this.onLoadSampleTray,
    this.onOpenTemplateLibrary,
    this.onOpenTemplateAuthoring,
    this.onOpenTdsWindow,
    this.onOpenCmsInspector,
  });

  @override
  State<StudioRibbonToolbar> createState() => _StudioRibbonToolbarState();
}

class _StudioRibbonToolbarState extends State<StudioRibbonToolbar> {
  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Top Title & Colorful Menu Bar (Decluttered!)
          _buildTopTitleBar(vm),

          // 2. Multi-File Document Tab Bar
          StudioTabBar(
            tabs: widget.tabs,
            activeIndex: widget.activeTabIndex,
            onSelectTab: widget.onTabSelected,
            onCloseTab: widget.onTabClosed,
            onNewTab: widget.onNewTab,
            onOpenFile: widget.onOpenFile,
            onSaveDsf: widget.onSaveFile,
            onSaveDdsProject: widget.onSaveDdsProject ?? () {},
            onCopySelection: () => StudioClipboardService.copySelection(widget.viewModel),
            onPasteClipboard: () => StudioClipboardService.pasteInto(widget.viewModel),
            viewportLayoutMode: vm.viewportLayoutMode,
            onViewportLayoutModeChanged: vm.setViewportLayoutMode,
            isRibbonCollapsed: vm.isRibbonCollapsed,
            onToggleRibbon: vm.toggleRibbonCollapsed,
            isCompactMode: vm.isCompactMode,
            onToggleCompactMode: vm.cycleUiDensityMode,
            uiDensityMode: vm.uiDensityMode,
            activeToolLabel: _labelForToolMode(vm.toolMode),
            activeToolIcon: _iconForToolMode(vm.toolMode),
          ),

          // 3. Enlarged CAD Toolbar with 3D Animated Action Icons (Collapsible & Dockable)
          if (!vm.isRibbonCollapsed && vm.toolbarDockPosition.isTop)
            _buildStudioToolbar(vm),
        ],
      ),
    );
  }

  /// 1. Top Title & Colorful Menu Bar (Decluttered & Structured)
  Widget _buildTopTitleBar(SheetMetalStudioViewModel vm) {
    return Container(
      height: 38,
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // Brand Logo & Title (True 3D Branding Icon)
          const TruFold3DIcon(
            size: 20,
            isAnimated: false,
            fixedFoldAngleDeg: 42.0,
            sheetThickness: 2.0,
            tColor: Color(0xFF38BDF8),
            fColor: Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          const Text(
            'truFold Studio by Danish',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 16, color: const Color(0xFF334155)),
          const SizedBox(width: 8),

          // Unique, Colorful, Intuitive Menu Bar
          Expanded(
            child: StudioMenuBar(
              viewModel: vm,
              onNewTab: widget.onNewTab,
              onOpenFile: widget.onOpenFile,
              onSaveFile: widget.onSaveFile,
              onSaveAsFile: widget.onSaveAsFile,
              onSaveDdsProject: widget.onSaveDdsProject,
              onExportDxf: widget.onExportDxf,
              onMaterialDialog: widget.onMaterialDialog,
              onLoadSampleBracket: widget.onLoadSampleBracket,
              onFittingDetails: widget.onFittingDetails,
              onLoadSampleTray: widget.onLoadSampleTray,
              onOpenTemplateLibrary: widget.onOpenTemplateLibrary,
              onOpenTemplateAuthoring: widget.onOpenTemplateAuthoring,
              onOpenTdsWindow: widget.onOpenTdsWindow,
              onConfirmClearAll: _confirmClearAll,
            ),
          ),

          const SizedBox(width: 8),

          // Active Drawing Status Pill
          const Padding(padding: EdgeInsets.only(right: 6), child: CadToolbarFpsBadge()),
          _buildActiveDrawingStatusPill(vm),

          // Parametric Template Library Action Button (Always visible on top bar)
          Tooltip(
            message: 'Parametric Template Library (Standard Cable Trays, Ladders & Trunking)',
            child: InkWell(
              onTap: () {
                if (widget.onOpenTemplateLibrary != null) {
                  widget.onOpenTemplateLibrary!();
                } else {
                  DdsTemplateLibraryDialog.show(
                    context,
                    viewModel: vm,
                    onOpenInEditor: (dsfDoc) => vm.loadDocument(dsfDoc),
                  );
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.35),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.dashboard_customize, size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Template Library',
                      style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // TDS Studio (.dds) Action Button
          Tooltip(
            message: 'Technical Data Sheet (TDS) Studio (.dds / Excel Import)',
            child: InkWell(
              onTap: () {
                if (widget.onOpenTdsWindow != null) {
                  widget.onOpenTdsWindow!();
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DdsWorkspaceScreen(
                        linkedViewModel: widget.viewModel,
                        isLightTheme: true,
                        onOpenInEditor: (dsfDoc) {
                          widget.viewModel.loadDocument(dsfDoc);
                        },
                      ),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.description_outlined, size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'TDS Studio',
                      style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // 3D Assembly Studio Action Button
          Tooltip(
            message: '3D Assembly Studio (Modular Ladder Parts, Welds, Segments & WYSIWYG Face Sketch)',
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AssemblyStudioScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.view_in_ar_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Assembly Studio',
                      style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),


          if (widget.onMaterialDialog != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Sheet Material & Gauge Settings',
              child: InkWell(
                onTap: widget.onMaterialDialog,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.science_outlined, size: 12, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 4),
                      Text(
                        '${vm.document.material.materialType.shortCode} | ${vm.document.material.thicknessMm}mm',
                        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(width: 4),

          // Quick Undo / Redo
          IconButton(
            icon: const Icon(Icons.undo, size: 15, color: Color(0xFFCBD5E1)),
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: vm.canUndo ? vm.undo : null,
            splashRadius: 14,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 15, color: Color(0xFFCBD5E1)),
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: vm.canRedo ? vm.redo : null,
            splashRadius: 14,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// Active Drawing Status Pill
  Widget _buildActiveDrawingStatusPill(SheetMetalStudioViewModel vm) {
    final activeTab = (widget.activeTabIndex >= 0 && widget.activeTabIndex < widget.tabs.length)
        ? widget.tabs[widget.activeTabIndex]
        : null;

    final meta = vm.detectedFittingMetadata;
    String primary = '';
    if (meta != null && meta.variantName.isNotEmpty && meta.variantName != 'None') {
      primary = meta.variantName;
    } else if (meta != null && meta.product.isNotEmpty && meta.product != 'None') {
      primary = meta.product;
    } else if (meta != null && meta.category.isNotEmpty && meta.category != 'None') {
      primary = meta.category;
    } else if (activeTab != null && activeTab.displayTitle.trim().isNotEmpty && activeTab.displayTitle != 'Untitled Part') {
      primary = activeTab.displayTitle.trim();
    } else if (vm.document.itemName.trim().isNotEmpty) {
      primary = vm.document.itemName.trim();
    } else {
      primary = 'Sheet Metal Part';
    }

    String dimStr = '';
    if (meta != null && meta.parameters.containsKey('width') && meta.parameters.containsKey('height')) {
      final w = meta.parameters['width']!.toStringAsFixed(meta.parameters['width']! % 1 == 0 ? 0 : 1);
      final h = meta.parameters['height']!.toStringAsFixed(meta.parameters['height']! % 1 == 0 ? 0 : 1);
      dimStr = '${w}x$h mm';
    } else if (vm.document.blankWidthMm > 0 && vm.document.blankLengthMm > 0) {
      dimStr = '${vm.document.blankWidthMm.toInt()}x${vm.document.blankLengthMm.toInt()} mm';
    }
    if (vm.document.material.thicknessMm > 0) {
      final th = vm.document.material.thicknessMm.toStringAsFixed(vm.document.material.thicknessMm % 1 == 0 ? 0 : 1);
      dimStr = dimStr.isNotEmpty ? '$dimStr (T:${th}mm)' : 'T:${th}mm';
    }

    final displayTitle = dimStr.isNotEmpty ? '$primary • $dimStr' : primary;

    return Tooltip(
      message: 'Active Drawing: $displayTitle (Click to open DSF Inspector)',
      child: InkWell(
        onTap: widget.onFittingDetails ?? () => vm.setFittingInspectorOpen(true),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF475569), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.architecture, size: 13, color: Color(0xFF38BDF8)),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  displayTitle,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelForToolMode(StudioToolMode mode) {
    switch (mode) {
      case StudioToolMode.select:
        return 'Select (Esc)';
      case StudioToolMode.drawPolyline:
        return 'Line / Polyline (L)';
      case StudioToolMode.drawRectangle:
      case StudioToolMode.addPunchSquare:
        return 'Rectangle Punch (G)';
      case StudioToolMode.drawCircle:
      case StudioToolMode.addPunchRound:
        return 'Circle Punch (C)';
      case StudioToolMode.addPunchObround:
        return 'Slot Punch';
      case StudioToolMode.drawArc:
        return 'Arc (A)';
      case StudioToolMode.addBend:
        return 'Add Bend (B)';
      case StudioToolMode.addFlange:
        return 'Add Flange (F)';
      case StudioToolMode.addCut:
        return 'Add Cut (M)';
      case StudioToolMode.perforationPattern:
        return 'Pattern (P)';
      case StudioToolMode.setBaseAnchor:
        return 'Base Anchor';
      case StudioToolMode.cornerFillet:
        return 'Fillet (Shift+F)';
      case StudioToolMode.cornerChamfer:
        return 'Chamfer (Shift+C)';
      case StudioToolMode.modifyMove:
        return 'Move';
      case StudioToolMode.modifyRotate:
        return 'Rotate';
      case StudioToolMode.modifyMirror:
        return 'Mirror';
      case StudioToolMode.modifyOffset:
        return 'Offset';
      case StudioToolMode.addDimension:
      case StudioToolMode.dragDimension:
        return 'Dimension (D)';
      case StudioToolMode.pickPortEdge:
      case StudioToolMode.assignPortSemantic:
        return 'Port Mapping';
      case StudioToolMode.pan:
        return 'Pan (H)';
    }
  }

  IconData _iconForToolMode(StudioToolMode mode) {
    switch (mode) {
      case StudioToolMode.select:
        return Icons.near_me_outlined;
      case StudioToolMode.drawPolyline:
        return Icons.horizontal_rule;
      case StudioToolMode.drawRectangle:
      case StudioToolMode.addPunchSquare:
        return Icons.crop_square;
      case StudioToolMode.drawCircle:
      case StudioToolMode.addPunchRound:
        return Icons.radio_button_unchecked;
      case StudioToolMode.addPunchObround:
        return Icons.crop_16_9;
      case StudioToolMode.drawArc:
        return Icons.architecture;
      case StudioToolMode.addBend:
      case StudioToolMode.addFlange:
        return Icons.layers_outlined;
      case StudioToolMode.addCut:
        return Icons.content_cut;
      case StudioToolMode.perforationPattern:
        return Icons.grid_view;
      case StudioToolMode.setBaseAnchor:
        return Icons.anchor;
      case StudioToolMode.cornerFillet:
      case StudioToolMode.cornerChamfer:
        return Icons.rounded_corner;
      case StudioToolMode.modifyMove:
        return Icons.open_with;
      case StudioToolMode.modifyRotate:
        return Icons.rotate_right;
      case StudioToolMode.modifyMirror:
        return Icons.flip;
      case StudioToolMode.modifyOffset:
        return Icons.copy_all;
      case StudioToolMode.addDimension:
      case StudioToolMode.dragDimension:
        return Icons.straighten;
      case StudioToolMode.pickPortEdge:
      case StudioToolMode.assignPortSemantic:
        return Icons.input;
      case StudioToolMode.pan:
        return Icons.pan_tool_outlined;
    }
  }

  /// 2. Enlarged CAD Toolbar with Interactive 3D Animated Action Icons (Delegates to StudioCadToolPalette)
  Widget _buildStudioToolbar(SheetMetalStudioViewModel vm) {
    return StudioCadToolPalette(
      viewModel: vm,
      onFinishSketch: widget.onFinishSketch,
      onOpenTemplateLibrary: widget.onOpenTemplateLibrary,
      isVertical: false,
    );
  }

  Future<void> _confirmClearAll(BuildContext context, SheetMetalStudioViewModel vm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 8),
            Text('Clear Drawing & Start Fresh?'),
          ],
        ),
        content: const Text(
          'This will remove all lines, arcs, punches, bends, flanges, patterns, and dimensions from the canvas, resetting to a clean blank sheet.\n\nYou can undo this action if needed.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      vm.clearAllDrawingEntities(resetToBlank: true);
    }
  }
}
