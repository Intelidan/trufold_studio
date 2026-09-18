// =============================================================================
// studio_ribbon_toolbar.dart
//
// Single-Row CAD Sketch & Sheet Metal Toolbar for truFold Studio by Danish.
// - High-density single-row CAD toolbar
// - Tool Groups: File/Undo -> Draw -> Modify (with Construction Q) -> Constraints -> Dimensions -> Finish Sketch
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

class StudioRibbonToolbar extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final List<StudioTab> tabs;
  final int activeTabIndex;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int> onTabClosed;
  final VoidCallback onNewTab;
  final VoidCallback onOpenFile;
  final VoidCallback onSaveFile;
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
          // 1. Top Title & Quick Access Bar
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

          // 3. Single-Row Icon Toolbar
          _buildStudioToolbar(vm),
        ],
      ),
    );
  }

  /// 1. Top Title & Quick Access Bar
  Widget _buildTopTitleBar(SheetMetalStudioViewModel vm) {
    return Container(
      height: 34,
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.precision_manufacturing, color: Color(0xFF38BDF8), size: 16),
          const SizedBox(width: 8),
          const Text(
            'truFold Studio by Danish',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
          Tooltip(
            message: 'DSF Parameter Inspector & Auto-Fold Settings',
            child: InkWell(
              onTap: widget.onFittingDetails ?? () => vm.setFittingInspectorOpen(true),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                decoration: BoxDecoration(
                  color: (vm.detectedFittingMetadata != null && vm.detectedFittingMetadata!.isAssigned)
                      ? const Color(0xFF0284C7)
                      : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: (vm.detectedFittingMetadata != null && vm.detectedFittingMetadata!.isAssigned)
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFF475569),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune,
                      size: 13,
                      color: (vm.detectedFittingMetadata != null && vm.detectedFittingMetadata!.isAssigned)
                          ? Colors.white
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'DSF Inspector',
                      style: TextStyle(
                        color: (vm.detectedFittingMetadata != null && vm.detectedFittingMetadata!.isAssigned)
                            ? Colors.white
                            : const Color(0xFFE2E8F0),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Builder(
              builder: (context) {
                final activeTab = (widget.activeTabIndex >= 0 && widget.activeTabIndex < widget.tabs.length)
                    ? widget.tabs[widget.activeTabIndex]
                    : null;

                final meta = vm.detectedFittingMetadata;
                String primary = '';
                // 1. Product variant if available
                if (meta != null && meta.variantName.isNotEmpty && meta.variantName != 'None') {
                  primary = meta.variantName;
                }
                // 2. If not then product type
                else if (meta != null && meta.product.isNotEmpty && meta.product != 'None') {
                  primary = meta.product;
                }
                // 3. If not then category
                else if (meta != null && meta.category.isNotEmpty && meta.category != 'None') {
                  primary = meta.category;
                }
                // 4. Fallback to active tab title / doc item name
                else if (activeTab != null && activeTab.title.trim().isNotEmpty && activeTab.title != 'Untitled Part') {
                  primary = activeTab.title.trim();
                } else if (vm.document.itemName.trim().isNotEmpty) {
                  primary = vm.document.itemName.trim();
                } else {
                  primary = 'Sheet Metal Part';
                }

                // Dimension calculation
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
                  message: 'Active Drawing: $displayTitle',
                  child: InkWell(
                    onTap: () => vm.setFittingInspectorOpen(true),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF475569), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.architecture, size: 14, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 5),
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                displayTitle,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Save Part (.dsf)',
            child: InkWell(
              onTap: widget.onSaveFile,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.save_outlined, size: 14, color: Color(0xFF38BDF8)),
                    SizedBox(width: 4),
                    Text(
                      'Save .dsf',
                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.onExportDxf != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Export 2D Flat Pattern to DXF',
              child: InkWell(
                onTap: widget.onExportDxf,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Export DXF',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.undo, size: 16, color: Color(0xFFCBD5E1)),
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: vm.canUndo ? vm.undo : null,
            splashRadius: 14,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.redo, size: 16, color: Color(0xFFCBD5E1)),
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: vm.canRedo ? vm.redo : null,
            splashRadius: 14,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          if (widget.onMaterialDialog != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: widget.onMaterialDialog,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
          ],
          const SizedBox(width: 8),
          Tooltip(
            message: 'Press Brake Machine & Tooling Settings',
            child: InkWell(
              onTap: () => PressBrakeMachineDialog.show(context, vm),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.precision_manufacturing_outlined, size: 12, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 4),
                    Text(
                      vm.selectedMachine.name.split(' ').first,
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Upper Punch Tooling Catalog',
            child: InkWell(
              onTap: () => PunchToolingSelectorDialog.show(context, vm),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.hardware_outlined, size: 12, color: Color(0xFF38BDF8)),
                    SizedBox(width: 4),
                    Text(
                      'Punch Tooling',
                      style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
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

  /// 2. Single-Row Icon Toolbar
  Widget _buildStudioToolbar(SheetMetalStudioViewModel vm) {
    return Container(
      height: 44,
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
                  // Sketch Indicator pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.edit, size: 13, color: Color(0xFF2563EB)),
                        SizedBox(width: 4),
                        Text(
                          'Sketch1',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                  ),

                  _buildDivider(),

                  // DRAW TOOLS (Select, Line, Rectangle, Circle, Arc)
                  _buildToolButton(
                    icon: Icons.near_me_outlined,
                    tooltip: 'Select (Esc)',
                    isActive: vm.toolMode == StudioToolMode.select,
                    onTap: () => vm.setToolMode(StudioToolMode.select),
                  ),
                  _buildToolButton(
                    icon: Icons.horizontal_rule,
                    tooltip: 'Line (L) — Click & Drag or Click-Click',
                    isActive: vm.toolMode == StudioToolMode.drawPolyline,
                    onTap: () => vm.setToolMode(StudioToolMode.drawPolyline),
                  ),
                  _buildToolButton(
                    icon: Icons.crop_square,
                    tooltip: 'Corner Rectangle (G) — Click & Drag or Click-Click',
                    isActive: vm.toolMode == StudioToolMode.drawRectangle,
                    onTap: () => vm.setToolMode(StudioToolMode.drawRectangle),
                  ),
                  _buildToolButton(
                    icon: Icons.radio_button_unchecked,
                    tooltip: 'Center Point Circle (C) — Click & Drag or Click-Click',
                    isActive: vm.toolMode == StudioToolMode.drawCircle,
                    onTap: () => vm.setToolMode(StudioToolMode.drawCircle),
                  ),
                  _buildToolButton(
                    icon: Icons.gesture,
                    tooltip: '3-Point Arc (A) — Click & Drag or Click-Click',
                    isActive: vm.toolMode == StudioToolMode.drawArc,
                    onTap: () => vm.setToolMode(StudioToolMode.drawArc),
                  ),

                  _buildDivider(),

                  // SHEET METAL FEATURES (Bend Line, Flange, Cut Slit, Perforation, Base Anchor)
                  _buildToolButton(
                    icon: Icons.alt_route,
                    tooltip: 'Add Bend Line (B) — Click & Drag or Click-Click',
                    isActive: vm.toolMode == StudioToolMode.addBend,
                    onTap: () => vm.setToolMode(StudioToolMode.addBend),
                  ),
                  _buildToolButton(
                    icon: Icons.border_outer,
                    tooltip: 'Add Return Flange (F) — Click & Drag or Click-Click',
                    isActive: vm.toolMode == StudioToolMode.addFlange,
                    onTap: () => vm.setToolMode(StudioToolMode.addFlange),
                  ),
                  _buildToolButton(
                    icon: Icons.content_cut,
                    tooltip: 'Add Laser Cut Line / Slit (M) — Click & Drag or Click-Click',
                    isActive: vm.toolMode == StudioToolMode.addCut,
                    onTap: () => vm.setToolMode(StudioToolMode.addCut),
                  ),
                  _buildToolButton(
                    icon: Icons.grain,
                    tooltip: 'Perforation Pattern (P)',
                    isActive: vm.toolMode == StudioToolMode.perforationPattern,
                    onTap: () => vm.setToolMode(StudioToolMode.perforationPattern),
                  ),
                  _buildToolButton(
                    icon: Icons.anchor,
                    tooltip: 'Set Base Floor Anchor (Stationary face for folding)',
                    isActive: vm.toolMode == StudioToolMode.setBaseAnchor,
                    onTap: () => vm.setToolMode(StudioToolMode.setBaseAnchor),
                  ),

                  _buildDivider(),

                  // MODIFY & PUNCH TOOLS (Construction Q, Fillet, Chamfer, Mirror, Punches)
                  _buildToolButton(
                    icon: Icons.border_style,
                    tooltip: 'Construction Toggle (Q) — Toggle selected line to/from reference',
                    isActive: vm.isConstructionModeActive,
                    activeColor: const Color(0xFF00BCD4),
                    onTap: vm.toggleSelectedConstruction,
                  ),
                  _buildToolButton(
                    icon: Icons.rounded_corner,
                    tooltip: 'Fillet (Shift+F) — Rounded corner',
                    isActive: vm.toolMode == StudioToolMode.cornerFillet,
                    onTap: () => vm.setToolMode(StudioToolMode.cornerFillet),
                  ),
                  _buildToolButton(
                    icon: Icons.crop_square_sharp,
                    tooltip: 'Chamfer (Shift+C) — 45° corner cut',
                    isActive: vm.toolMode == StudioToolMode.cornerChamfer,
                    onTap: () => vm.setToolMode(StudioToolMode.cornerChamfer),
                  ),
                  _buildToolButton(
                    icon: Icons.flip,
                    tooltip: 'Mirror',
                    isActive: vm.toolMode == StudioToolMode.modifyMirror,
                    onTap: () => vm.setToolMode(StudioToolMode.modifyMirror),
                  ),
                  _buildToolButton(
                    icon: Icons.adjust,
                    tooltip: 'Round Hole Punch (Bolt clearance)',
                    isActive: vm.toolMode == StudioToolMode.addPunchRound,
                    onTap: () => vm.setToolMode(StudioToolMode.addPunchRound),
                  ),
                  _buildToolButton(
                    icon: Icons.check_box_outline_blank,
                    tooltip: 'Square / Rectangular Punch',
                    isActive: vm.toolMode == StudioToolMode.addPunchSquare,
                    onTap: () => vm.setToolMode(StudioToolMode.addPunchSquare),
                  ),
                  _buildToolButton(
                    icon: Icons.crop_16_9,
                    tooltip: 'Slot / Obround Punch',
                    isActive: vm.toolMode == StudioToolMode.addPunchObround,
                    onTap: () => vm.setToolMode(StudioToolMode.addPunchObround),
                  ),

                  _buildDivider(),

                  // CONSTRAINTS (CAD Glyphs)
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

                  _buildDivider(),

                  // DIMENSIONS & RELATIONS (Dimension D, Relations)
                  _buildToolButton(
                    icon: Icons.straighten,
                    tooltip: 'Smart Dimension (D)',
                    isActive: vm.toolMode == StudioToolMode.addDimension ||
                        vm.activeConstraintPickType == CadConstraintType.distance,
                    onTap: () => vm.setToolMode(StudioToolMode.addDimension),
                  ),
                  _buildToolButton(
                    icon: Icons.functions,
                    tooltip: 'Constraint Manager & Relations',
                    isActive: vm.isConstraintManagerOpen,
                    onTap: vm.toggleConstraintManager,
                  ),

                  _buildDivider(),

                  // MACHINE & PUNCH TOOLING
                  _buildToolButton(
                    icon: Icons.precision_manufacturing_outlined,
                    tooltip: 'Machine & Press Brake Settings',
                    isActive: false,
                    onTap: () => PressBrakeMachineDialog.show(context, vm),
                  ),
                  _buildToolButton(
                    icon: Icons.hardware_outlined,
                    tooltip: 'Punch Tooling Catalog',
                    isActive: false,
                    onTap: () => PunchToolingSelectorDialog.show(context, vm),
                  ),

                  _buildDivider(),

                  // Parametric Templates Popover
                  PopupMenuButton<String>(
                    tooltip: 'Parametric Sheet Metal Templates',
                    offset: const Offset(0, 36),
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
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: vm.isTemplateActive ? const Color(0xFFE0F2FE) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
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
                            size: 15,
                            color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF475569),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Templates',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF334155),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF64748B)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Green "FINISH SKETCH" Checkmark Button
          InkWell(
            onTap: widget.onFinishSketch,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check, size: 15, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'FINISH SKETCH',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
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

  Widget _buildDivider() {
    return Container(
      height: 22,
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
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: isActive ? actCol.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? actCol : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Icon(
            icon,
            size: 17,
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
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
              ),
              alignment: Alignment.center,
              child: Text(
                glyph,
                style: const TextStyle(
                  fontSize: 10,
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
}
