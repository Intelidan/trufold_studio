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
import '../../../models/cad_constraint.dart';
import '../../../models/studio_tab_model.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../press_brake_machine_dialog.dart';
import '../punch_tooling_selector_dialog.dart';
import '../studio_tab_bar.dart';
import '../template_library_gallery_dialog.dart';
import '../template_authoring_wizard_dialog.dart';
import '../../../services/studio_clipboard_service.dart';
import 'studio_3d_tool_icons.dart';
import 'studio_menu_bar.dart';
import 'studio_tool_button_3d.dart';
import '../branding/trufold_3d_icon.dart';
import '../dds/dds_workspace_screen.dart';

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
          ),

          // 3. Enlarged CAD Toolbar with 3D Animated Action Icons
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
              onConfirmClearAll: _confirmClearAll,
            ),
          ),

          const SizedBox(width: 8),

          // Active Drawing Status Pill
          _buildActiveDrawingStatusPill(vm),

          const SizedBox(width: 6),

          // Quick Save Button
          Tooltip(
            message: 'Save Part (Ctrl+S)',
            child: InkWell(
              onTap: widget.onSaveFile,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF0284C7), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.save_outlined, size: 13, color: Color(0xFF38BDF8)),
                    SizedBox(width: 4),
                    Text(
                      'Save',
                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DdsWorkspaceScreen(
                      onOpenInEditor: (dsfDoc) {
                        widget.viewModel.loadDocument(dsfDoc);
                      },
                    ),
                  ),
                );
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
    } else if (activeTab != null && activeTab.title.trim().isNotEmpty && activeTab.title != 'Untitled Part') {
      primary = activeTab.title.trim();
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

  /// 2. Enlarged CAD Toolbar with Interactive 3D Animated Action Icons on Hover
  Widget _buildStudioToolbar(SheetMetalStudioViewModel vm) {
    return Container(
      height: 54,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Scrollable tool strip
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  // DRAW & PUNCH TOOLS (Bigger 3D Animated Action Icons!)
                  Studio3DToolButton(
                    toolType: Tool3DType.select,
                    fallbackIcon: Icons.near_me_outlined,
                    label: 'Select Tool',
                    shortcut: 'Esc / V',
                    description: 'Pick, drag, or inspect geometry in 2D and 3D',
                    isActive: vm.toolMode == StudioToolMode.select,
                    onTap: () => vm.setToolMode(StudioToolMode.select),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.drawPolyline,
                    fallbackIcon: Icons.horizontal_rule,
                    label: 'Line / Polyline',
                    shortcut: 'L',
                    description: 'Draw connected straight edges in 2D space',
                    isActive: vm.toolMode == StudioToolMode.drawPolyline,
                    onTap: () => vm.setToolMode(StudioToolMode.drawPolyline),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.drawRectangle,
                    fallbackIcon: Icons.crop_square,
                    label: 'Rectangle Punch',
                    shortcut: 'G',
                    description: 'Click to stamp preset punch or drag to size',
                    isActive: vm.toolMode == StudioToolMode.drawRectangle,
                    onTap: () => vm.setToolMode(StudioToolMode.drawRectangle),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.drawCircle,
                    fallbackIcon: Icons.radio_button_unchecked,
                    label: 'Circle Punch',
                    shortcut: 'C',
                    description: 'Click to stamp bolt hole or drag to size',
                    isActive: vm.toolMode == StudioToolMode.drawCircle,
                    onTap: () => vm.setToolMode(StudioToolMode.drawCircle),
                  ),
                  // Obround / Slot Punch (Placed directly near the Circle Punch tool)
                  Studio3DToolButton(
                    toolType: Tool3DType.addPunchObround,
                    fallbackIcon: Icons.crop_16_9,
                    label: 'Slot / Obround Punch',
                    shortcut: 'Slot',
                    description: 'Stamp elongated slot for bolt adjustment',
                    isActive: vm.toolMode == StudioToolMode.addPunchObround,
                    activeColor: const Color(0xFF0284C7),
                    onTap: () => vm.setToolMode(StudioToolMode.addPunchObround),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.drawArc,
                    fallbackIcon: Icons.gesture,
                    label: '3-Point Arc',
                    shortcut: 'A',
                    description: 'Draw tangential or radial curved arc',
                    isActive: vm.toolMode == StudioToolMode.drawArc,
                    onTap: () => vm.setToolMode(StudioToolMode.drawArc),
                  ),

                  _buildDivider(),

                  // SHEET METAL 3D FEATURES (Bending, Flanges, Cutting, Anchor)
                  Studio3DToolButton(
                    toolType: Tool3DType.addBend,
                    fallbackIcon: Icons.alt_route,
                    label: 'Add Bend Line',
                    shortcut: 'B',
                    description: 'Define press brake fold line (folds 0° to 90° in 3D)',
                    isActive: vm.toolMode == StudioToolMode.addBend,
                    activeColor: const Color(0xFF0284C7),
                    onTap: () => vm.setToolMode(StudioToolMode.addBend),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.addFlange,
                    fallbackIcon: Icons.border_outer,
                    label: 'Add Return Flange',
                    shortcut: 'F',
                    description: 'Extrude upward/downward edge return flange in 3D',
                    isActive: vm.toolMode == StudioToolMode.addFlange,
                    activeColor: const Color(0xFF0284C7),
                    onTap: () => vm.setToolMode(StudioToolMode.addFlange),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.addCut,
                    fallbackIcon: Icons.content_cut,
                    label: 'Add Cut / Slit Line',
                    shortcut: 'M',
                    description: 'Slice internal laser cuts, relief notches, and parting slits',
                    isActive: vm.toolMode == StudioToolMode.addCut,
                    activeColor: const Color(0xFFEF4444),
                    onTap: () => vm.setToolMode(StudioToolMode.addCut),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.perforationPattern,
                    fallbackIcon: Icons.grain,
                    label: 'Perforation Pattern',
                    shortcut: 'P',
                    description: 'Pattern matrix of perforated ventilation punch holes',
                    isActive: vm.toolMode == StudioToolMode.perforationPattern,
                    activeColor: const Color(0xFF0EA5E9),
                    onTap: () => vm.setToolMode(StudioToolMode.perforationPattern),
                  ),
                  // Prominent Base Floor Anchor Button with 3D Action
                  Studio3DToolButton(
                    toolType: Tool3DType.setBaseAnchor,
                    fallbackIcon: Icons.anchor,
                    label: 'Set Base Floor Anchor',
                    shortcut: 'Anchor',
                    description: 'Stationary ground face that stays fixed during 3D folding',
                    isActive: vm.toolMode == StudioToolMode.setBaseAnchor,
                    activeColor: const Color(0xFFD97706),
                    onTap: () => vm.setToolMode(StudioToolMode.setBaseAnchor),
                  ),

                  _buildDivider(),

                  // MODIFY TOOLS (Construction, Fillet, Chamfer, Mirror)
                  Studio3DToolButton(
                    toolType: Tool3DType.constructionToggle,
                    fallbackIcon: Icons.border_style,
                    label: 'Construction Mode',
                    shortcut: 'Q',
                    description: 'Toggle selected line between geometry and reference guide',
                    isActive: vm.isConstructionModeActive,
                    activeColor: const Color(0xFF00BCD4),
                    onTap: vm.toggleSelectedConstruction,
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.cornerFillet,
                    fallbackIcon: Icons.rounded_corner,
                    label: 'Corner Fillet',
                    shortcut: 'Shift+F',
                    description: 'Create smooth tangent rounded corner radius',
                    isActive: vm.toolMode == StudioToolMode.cornerFillet,
                    activeColor: const Color(0xFF06B6D4),
                    onTap: () => vm.setToolMode(StudioToolMode.cornerFillet),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.cornerChamfer,
                    fallbackIcon: Icons.crop_square_sharp,
                    label: 'Corner Chamfer',
                    shortcut: 'Shift+C',
                    description: 'Create 45° beveled corner cut',
                    isActive: vm.toolMode == StudioToolMode.cornerChamfer,
                    activeColor: const Color(0xFF06B6D4),
                    onTap: () => vm.setToolMode(StudioToolMode.cornerChamfer),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.modifyMirror,
                    fallbackIcon: Icons.flip,
                    label: 'Mirror Features',
                    shortcut: 'Mirror',
                    description: 'Reflect sketch entities across a symmetry axis',
                    isActive: vm.toolMode == StudioToolMode.modifyMirror,
                    activeColor: const Color(0xFF6366F1),
                    onTap: () => vm.setToolMode(StudioToolMode.modifyMirror),
                  ),

                  _buildDivider(),

                  // CONSTRAINTS & DIMENSIONS
                  Studio3DToolButton(
                    toolType: Tool3DType.dragDimension,
                    fallbackIcon: Icons.straighten,
                    label: 'Dimension',
                    shortcut: 'D',
                    description: 'Click and drag from Point A to Point B to display and place persistent dimension (Alt to move freely)',
                    isActive: vm.toolMode == StudioToolMode.dragDimension,
                    activeColor: const Color(0xFF0284C7),
                    onTap: () => vm.setToolMode(StudioToolMode.dragDimension),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.addDimension,
                    fallbackIcon: Icons.tune,
                    label: 'Dimensional Constraints',
                    shortcut: 'Shift+D',
                    description: 'Parametric geometric & distance constraints solver',
                    isActive: vm.toolMode == StudioToolMode.addDimension ||
                        vm.activeConstraintPickType == CadConstraintType.distance,
                    activeColor: const Color(0xFFEC4899),
                    onTap: () => vm.setToolMode(StudioToolMode.addDimension),
                  ),
                  _buildConstraintButton(
                    glyph: '●',
                    tooltip: 'Coincident Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.coincident),
                  ),
                  _buildConstraintButton(
                    glyph: '◎',
                    tooltip: 'Concentric Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.concentric),
                  ),
                  _buildConstraintButton(
                    glyph: '//',
                    tooltip: 'Parallel Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.parallel),
                  ),
                  _buildConstraintButton(
                    glyph: '⌒',
                    tooltip: 'Tangent / Collinear Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.collinear),
                  ),
                  _buildConstraintButton(
                    glyph: '─',
                    tooltip: 'Horizontal Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.horizontal),
                  ),
                  _buildConstraintButton(
                    glyph: '│',
                    tooltip: 'Vertical Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.vertical),
                  ),
                  _buildConstraintButton(
                    glyph: '⊥',
                    tooltip: 'Perpendicular Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.perpendicular),
                  ),
                  _buildConstraintButton(
                    glyph: '=',
                    tooltip: 'Equal Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.equal),
                  ),
                  _buildConstraintButton(
                    glyph: '🔒',
                    tooltip: 'Fix / Lock Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.fixed),
                  ),
                  _buildConstraintButton(
                    glyph: '◇',
                    tooltip: 'Symmetric Constraint',
                    onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.symmetric),
                  ),
                  _buildToolButton(
                    icon: Icons.functions,
                    tooltip: 'Constraint Manager & Relations',
                    isActive: vm.isConstraintManagerOpen,
                    onTap: vm.toggleConstraintManager,
                  ),

                  _buildDivider(),

                  // MACHINE & PUNCH TOOLING
                  Studio3DToolButton(
                    toolType: Tool3DType.pressBrake,
                    fallbackIcon: Icons.precision_manufacturing_outlined,
                    label: 'Machine Setup',
                    shortcut: 'Brake',
                    description: 'Press brake tonnage, stroke, and bend speeds',
                    isActive: false,
                    activeColor: const Color(0xFFF97316),
                    onTap: () => PressBrakeMachineDialog.show(context, vm),
                  ),
                  Studio3DToolButton(
                    toolType: Tool3DType.punchTooling,
                    fallbackIcon: Icons.hardware_outlined,
                    label: 'Punch Tooling',
                    shortcut: 'Tools',
                    description: 'Upper punch catalog and tip radius selection',
                    isActive: false,
                    activeColor: const Color(0xFFF97316),
                    onTap: () => PunchToolingSelectorDialog.show(context, vm),
                  ),

                  _buildDivider(),

                  // Parametric Templates Popover
                  _buildTemplatesDropdown(context, vm),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Sketch Palette Toggle Button (opens/closes non-persistent floating sketch palette)
          Tooltip(
            message: vm.isSketchPaletteOpen
                ? 'Close Sketch Palette'
                : 'Open Sketch Palette (Grid, Points, Linetype)',
            child: InkWell(
              onTap: vm.toggleSketchPalette,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7.5),
                decoration: BoxDecoration(
                  color: vm.isSketchPaletteOpen
                      ? const Color(0xFFE0F2FE)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: vm.isSketchPaletteOpen
                        ? const Color(0xFF0284C7)
                        : const Color(0xFFCBD5E1),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune,
                      size: 15,
                      color: vm.isSketchPaletteOpen
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF475569),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Palette',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: vm.isSketchPaletteOpen
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Green "FINISH SKETCH" Checkmark Button
          InkWell(
            onTap: widget.onFinishSketch,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                    blurRadius: 5,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check, size: 16, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    'FINISH SKETCH',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatesDropdown(BuildContext context, SheetMetalStudioViewModel vm) {
    return PopupMenuButton<String>(
      tooltip: 'Parametric Sheet Metal Templates',
      offset: const Offset(0, 42),
      onSelected: (value) {
        if (value == 'sample_bracket') {
          widget.onLoadSampleBracket?.call();
          return;
        }
        if (value == 'gallery') {
          if (widget.onOpenTemplateLibrary != null) {
            widget.onOpenTemplateLibrary!.call();
          } else {
            showDialog(
              context: context,
              builder: (ctx) => TemplateLibraryGalleryDialog(viewModel: vm),
            );
          }
          return;
        }
        if (value == 'author_wizard') {
          if (widget.onOpenTemplateAuthoring != null) {
            widget.onOpenTemplateAuthoring!.call();
          } else {
            showDialog(
              context: context,
              builder: (ctx) => TemplateAuthoringWizardDialog(viewModel: vm),
            );
          }
          return;
        }
        vm.setPropertyInspectorOpen(true);
        switch (value) {
          case 'tee':
            vm.loadTemplateTee();
            break;
          case 'bend90':
            vm.loadTemplateBend90();
            break;
          case 'bend45':
            vm.loadTemplateBend45();
            break;
          case 'reducer':
            vm.loadTemplateReducer();
            break;
          case 'cross':
            vm.loadTemplateCross();
            break;
          case 'straight':
            vm.loadTemplateStraight();
            break;
          case 'close':
            vm.closeTemplateMode();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'gallery',
          child: Row(
            children: [
              Icon(Icons.dashboard_customize, size: 16, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Text('Template Library...'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'author_wizard',
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, size: 16, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Author Template from DXF...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'sample_bracket',
          child: Row(
            children: [
              Icon(Icons.architecture, size: 16, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Text('Sample Sheet Metal Bracket'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'tee', child: Text('T-Piece Duct Fitting')),
        const PopupMenuItem(value: 'bend90', child: Text('90° Radius Elbow')),
        const PopupMenuItem(value: 'bend45', child: Text('45° Radius Elbow')),
        const PopupMenuItem(value: 'reducer', child: Text('Concentric Reducer')),
        const PopupMenuItem(value: 'cross', child: Text('4-Way Cross Fitting')),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: vm.isTemplateActive ? const Color(0xFFE0F2FE) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_mosaic_outlined,
              size: 16,
              color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF475569),
            ),
            const SizedBox(width: 5),
            Text(
              'Templates',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF334155),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 15, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 26,
      width: 1.0,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final actCol = activeColor ?? const Color(0xFF0284C7);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: isActive ? actCol.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive ? actCol : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? actCol : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _buildConstraintButton({
    required String glyph,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
              ),
              alignment: Alignment.center,
              child: Text(
                glyph,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ),
      ),
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
