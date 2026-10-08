// =============================================================================
// studio_cad_tool_palette.dart
//
// Dockable & Detachable CAD Tool Palette for truFold Studio.
// Supports:
// - Top (Horizontal Ribbon Toolbar)
// - Left (Vertical Rail Dock)
// - Right (Vertical Rail Dock)
// - Detached (Floating Draggable Window)
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/cad_constraint.dart';
import '../../../models/cad_primitives.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../press_brake_machine_dialog.dart';
import '../punch_tooling_selector_dialog.dart';
import '../dds/dds_template_library_dialog.dart';
import 'studio_3d_tool_icons.dart';
import 'studio_tool_button_3d.dart';

class StudioCadToolPalette extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback onFinishSketch;
  final VoidCallback? onOpenTemplateLibrary;
  final bool isVertical;
  final bool isFloating;
  final ValueChanged<Offset>? onPositionChanged;
  final VoidCallback? onClose;

  const StudioCadToolPalette({
    super.key,
    required this.viewModel,
    required this.onFinishSketch,
    this.onOpenTemplateLibrary,
    this.isVertical = false,
    this.isFloating = false,
    this.onPositionChanged,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (isFloating) {
      return _buildFloatingPalette(context);
    } else if (isVertical) {
      return _buildVerticalDock(context);
    } else {
      return _buildHorizontalToolbar(context);
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Horizontal Ribbon Mode (Docked Top)
  // ---------------------------------------------------------------------------
  Widget _buildHorizontalToolbar(BuildContext context) {
    final vm = viewModel;
    final isCompact = vm.isCompactMode;
    final height = isCompact ? 44.0 : 52.0;

    return Container(
      height: height,
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
                  ..._buildDrawAndPunchTools(vm, isCompact: isCompact, isVert: false),
                  _buildDivider(isVert: false),
                  ..._buildSheetMetal3DTools(vm, isCompact: isCompact, isVert: false),
                  _buildDivider(isVert: false),
                  ..._buildModifyTools(vm, isCompact: isCompact, isVert: false),
                  _buildDivider(isVert: false),
                  ..._buildConstraintTools(vm, isCompact: isCompact, isVert: false),
                  _buildDivider(isVert: false),
                  ..._buildToolingTools(context, vm, isCompact: isCompact, isVert: false),
                  _buildDivider(isVert: false),
                  _buildTemplateLibraryButton(context, vm, isCompact: isCompact, isVert: false),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Dock Switcher Button
          _buildDockMenuButton(context, vm, isVert: false),

          const SizedBox(width: 6),

          // Sketch Palette Toggle Button
          _buildSketchPaletteToggle(vm, isCompact: isCompact, isVert: false),

          const SizedBox(width: 6),

          // Green FINISH SKETCH Checkmark Button
          _buildFinishSketchButton(isCompact: isCompact, isVert: false),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Vertical Dock Mode (Docked Left or Right)
  // ---------------------------------------------------------------------------
  Widget _buildVerticalDock(BuildContext context) {
    final vm = viewModel;
    final isCompact = vm.isCompactMode;
    final width = isCompact ? 44.0 : 48.0;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: vm.toolbarDockPosition.isLeft
              ? const BorderSide(color: Color(0xFFCBD5E1), width: 1.0)
              : BorderSide.none,
          left: vm.toolbarDockPosition.isRight
              ? const BorderSide(color: Color(0xFFCBD5E1), width: 1.0)
              : BorderSide.none,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        children: [
          // Top Dock Header with Dock Switcher
          Container(
            height: isCompact ? 28.0 : 32.0,
            color: const Color(0xFFF1F5F9),
            child: Center(
              child: _buildDockMenuButton(context, vm, isVert: true),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // Scrollable Vertical Tool Palette
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  ..._buildDrawAndPunchTools(vm, isCompact: isCompact, isVert: true),
                  _buildDivider(isVert: true),
                  ..._buildSheetMetal3DTools(vm, isCompact: isCompact, isVert: true),
                  _buildDivider(isVert: true),
                  ..._buildModifyTools(vm, isCompact: isCompact, isVert: true),
                  _buildDivider(isVert: true),
                  ..._buildConstraintTools(vm, isCompact: isCompact, isVert: true),
                  _buildDivider(isVert: true),
                  ..._buildToolingTools(context, vm, isCompact: isCompact, isVert: true),
                  _buildDivider(isVert: true),
                  _buildTemplateLibraryButton(context, vm, isCompact: isCompact, isVert: true),
                  _buildDivider(isVert: true),
                  _buildSketchPaletteToggle(vm, isCompact: isCompact, isVert: true),
                  const SizedBox(height: 4),
                  _buildFinishSketchButton(isCompact: isCompact, isVert: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Detached Floating Window Mode
  // ---------------------------------------------------------------------------
  Widget _buildFloatingPalette(BuildContext context) {
    final vm = viewModel;
    final isCompact = vm.isCompactMode;
    final width = isCompact ? 48.0 : 54.0;

    return Material(
      color: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF94A3B8), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Floating Drag Header
            GestureDetector(
              onPanUpdate: (details) {
                if (onPositionChanged != null) {
                  onPositionChanged!(details.delta);
                }
              },
              child: Container(
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(6.8)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.drag_indicator, size: 14, color: Colors.white70),
                    _buildDockMenuButton(context, vm, isVert: true, iconColor: Colors.white70),
                  ],
                ),
              ),
            ),

            // Scrollable Tools
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    ..._buildDrawAndPunchTools(vm, isCompact: isCompact, isVert: true),
                    _buildDivider(isVert: true),
                    ..._buildSheetMetal3DTools(vm, isCompact: isCompact, isVert: true),
                    _buildDivider(isVert: true),
                    ..._buildModifyTools(vm, isCompact: isCompact, isVert: true),
                    _buildDivider(isVert: true),
                    ..._buildConstraintTools(vm, isCompact: isCompact, isVert: true),
                    _buildDivider(isVert: true),
                    ..._buildToolingTools(context, vm, isCompact: isCompact, isVert: true),
                    _buildDivider(isVert: true),
                    _buildTemplateLibraryButton(context, vm, isCompact: isCompact, isVert: true),
                    _buildDivider(isVert: true),
                    _buildSketchPaletteToggle(vm, isCompact: isCompact, isVert: true),
                    const SizedBox(height: 4),
                    _buildFinishSketchButton(isCompact: isCompact, isVert: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tool Subsets
  // ---------------------------------------------------------------------------
  List<Widget> _buildDrawAndPunchTools(SheetMetalStudioViewModel vm, {required bool isCompact, required bool isVert}) {
    final btnSize = isVert ? (isCompact ? 32.0 : 36.0) : (isCompact ? 34.0 : 42.0);

    return [
      Studio3DToolButton(
        toolType: Tool3DType.select,
        fallbackIcon: Icons.near_me_outlined,
        label: 'Select Tool',
        shortcut: 'Esc / V',
        description: 'Pick, drag, or inspect geometry in 2D and 3D',
        isActive: vm.toolMode == StudioToolMode.select,
        onTap: () => vm.setToolMode(StudioToolMode.select),
        size: btnSize,
      ),
      Studio3DToolButton(
        toolType: Tool3DType.drawPolyline,
        fallbackIcon: Icons.horizontal_rule,
        label: 'Line / Polyline',
        shortcut: 'L',
        description: 'Draw connected straight edges in 2D space',
        isActive: vm.toolMode == StudioToolMode.drawPolyline,
        onTap: () => vm.setToolMode(StudioToolMode.drawPolyline),
        size: btnSize,
      ),
      Studio3DToolButton(
        toolType: Tool3DType.drawRectangle,
        fallbackIcon: Icons.crop_square,
        label: 'Rectangle Punch',
        shortcut: 'G',
        description: 'Click to stamp preset punch or drag to size',
        isActive: vm.toolMode == StudioToolMode.drawRectangle,
        onTap: () => vm.setToolMode(StudioToolMode.drawRectangle),
        size: btnSize,
      ),
      Studio3DToolButton(
        toolType: Tool3DType.drawCircle,
        fallbackIcon: Icons.radio_button_unchecked,
        label: 'Circle Punch',
        shortcut: 'C',
        description: 'Click to stamp bolt hole or drag to size',
        isActive: vm.toolMode == StudioToolMode.drawCircle,
        onTap: () => vm.setToolMode(StudioToolMode.drawCircle),
        size: btnSize,
      ),
      Studio3DToolButton(
        toolType: Tool3DType.addPunchObround,
        fallbackIcon: Icons.crop_16_9,
        label: 'Slot / Obround Punch',
        shortcut: 'Slot',
        description: 'Stamp elongated slot for bolt adjustment',
        isActive: vm.toolMode == StudioToolMode.addPunchObround,
        activeColor: const Color(0xFF0284C7),
        onTap: () => vm.setToolMode(StudioToolMode.addPunchObround),
        size: btnSize,
      ),
      Studio3DToolButton(
        toolType: Tool3DType.drawArc,
        fallbackIcon: Icons.gesture,
        label: '3-Point Arc',
        shortcut: 'A',
        description: 'Draw tangential or radial curved arc',
        isActive: vm.toolMode == StudioToolMode.drawArc,
        onTap: () => vm.setToolMode(StudioToolMode.drawArc),
        size: btnSize,
      ),
    ];
  }

  List<Widget> _buildSheetMetal3DTools(SheetMetalStudioViewModel vm, {required bool isCompact, required bool isVert}) {
    final btnSize = isVert ? (isCompact ? 32.0 : 36.0) : (isCompact ? 34.0 : 42.0);

    return [
      Studio3DToolButton(
        toolType: Tool3DType.addBend,
        fallbackIcon: Icons.alt_route,
        label: 'Add Bend Line',
        shortcut: 'B',
        description: 'Define press brake fold line (folds 0° to 90° in 3D)',
        isActive: vm.toolMode == StudioToolMode.addBend,
        activeColor: const Color(0xFF0284C7),
        onTap: () => vm.setToolMode(StudioToolMode.addBend),
        size: btnSize,
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
        size: btnSize,
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
        size: btnSize,
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
        size: btnSize,
      ),
      Studio3DToolButton(
        toolType: Tool3DType.setBaseAnchor,
        fallbackIcon: Icons.anchor,
        label: 'Set Base Floor Anchor',
        shortcut: 'Anchor',
        description: 'Stationary ground face that stays fixed during 3D folding',
        isActive: vm.toolMode == StudioToolMode.setBaseAnchor,
        activeColor: const Color(0xFFD97706),
        onTap: () => vm.setToolMode(StudioToolMode.setBaseAnchor),
        size: btnSize,
      ),
    ];
  }

  List<Widget> _buildModifyTools(SheetMetalStudioViewModel vm, {required bool isCompact, required bool isVert}) {
    final btnSize = isVert ? (isCompact ? 32.0 : 36.0) : (isCompact ? 34.0 : 42.0);

    return [
      Studio3DToolButton(
        toolType: Tool3DType.constructionToggle,
        fallbackIcon: Icons.border_style,
        label: 'Construction Mode',
        shortcut: 'Q',
        description: 'Toggle selected line between geometry and reference guide',
        isActive: vm.isConstructionModeActive,
        activeColor: const Color(0xFF00BCD4),
        onTap: vm.toggleSelectedConstruction,
        size: btnSize,
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
        size: btnSize,
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
        size: btnSize,
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
        size: btnSize,
      ),
    ];
  }

  List<Widget> _buildConstraintTools(SheetMetalStudioViewModel vm, {required bool isCompact, required bool isVert}) {
    final btnSize = isVert ? (isCompact ? 32.0 : 36.0) : (isCompact ? 34.0 : 42.0);

    return [
      Studio3DToolButton(
        toolType: Tool3DType.dragDimension,
        fallbackIcon: Icons.straighten,
        label: 'Dimension',
        shortcut: 'D',
        description: 'Click and drag from Point A to Point B to display and place persistent dimension',
        isActive: vm.toolMode == StudioToolMode.dragDimension,
        activeColor: const Color(0xFF0284C7),
        onTap: () => vm.setToolMode(StudioToolMode.dragDimension),
        size: btnSize,
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
        size: btnSize,
      ),
      _buildConstraintButton(
        glyph: '●',
        tooltip: 'Coincident Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.coincident),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '◎',
        tooltip: 'Concentric Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.concentric),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '//',
        tooltip: 'Parallel Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.parallel),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '⌒',
        tooltip: 'Tangent / Collinear Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.collinear),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '─',
        tooltip: 'Horizontal Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.horizontal),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '│',
        tooltip: 'Vertical Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.vertical),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '⊥',
        tooltip: 'Perpendicular Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.perpendicular),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '=',
        tooltip: 'Equal Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.equal),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '🔒',
        tooltip: 'Fix / Lock Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.fixed),
        isCompact: isCompact,
      ),
      _buildConstraintButton(
        glyph: '◇',
        tooltip: 'Symmetric Constraint',
        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.symmetric),
        isCompact: isCompact,
      ),
      _buildToolButton(
        icon: Icons.functions,
        tooltip: 'Constraint Manager & Relations',
        isActive: vm.isConstraintManagerOpen,
        onTap: vm.toggleConstraintManager,
        isCompact: isCompact,
      ),
    ];
  }

  List<Widget> _buildToolingTools(BuildContext context, SheetMetalStudioViewModel vm, {required bool isCompact, required bool isVert}) {
    final btnSize = isVert ? (isCompact ? 32.0 : 36.0) : (isCompact ? 34.0 : 42.0);

    return [
      Studio3DToolButton(
        toolType: Tool3DType.pressBrake,
        fallbackIcon: Icons.precision_manufacturing_outlined,
        label: 'Machine Setup',
        shortcut: 'Brake',
        description: 'Press brake tonnage, stroke, and bend speeds',
        isActive: false,
        activeColor: const Color(0xFFF97316),
        onTap: () => PressBrakeMachineDialog.show(context, vm),
        size: btnSize,
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
        size: btnSize,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Action Buttons & Dock Menu
  // ---------------------------------------------------------------------------
  Widget _buildDockMenuButton(BuildContext context, SheetMetalStudioViewModel vm, {required bool isVert, Color? iconColor}) {
    return PopupMenuButton<ToolbarDockPosition>(
      tooltip: 'Dock / Detach Toolbar (Top / Left / Right / Float)',
      initialValue: vm.toolbarDockPosition,
      onSelected: (pos) => vm.setToolbarDockPosition(pos),
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.view_quilt_outlined,
        size: isVert ? 16 : 18,
        color: iconColor ?? const Color(0xFF0284C7),
      ),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          enabled: false,
          height: 24,
          child: Text(
            'TOOLBAR POSITION',
            style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
          ),
        ),
        PopupMenuItem(
          value: ToolbarDockPosition.top,
          height: 32,
          child: Row(
            children: [
              Icon(Icons.vertical_align_top, size: 16, color: vm.toolbarDockPosition.isTop ? const Color(0xFF0284C7) : const Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text('Top (Horizontal Ribbon)', style: TextStyle(fontSize: 11.5, fontWeight: vm.toolbarDockPosition.isTop ? FontWeight.bold : FontWeight.normal)),
              if (vm.toolbarDockPosition.isTop) ...[
                const Spacer(),
                const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
              ],
            ],
          ),
        ),
        PopupMenuItem(
          value: ToolbarDockPosition.left,
          height: 32,
          child: Row(
            children: [
              Icon(Icons.border_left, size: 16, color: vm.toolbarDockPosition.isLeft ? const Color(0xFF0284C7) : const Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text('Left Side (Vertical Dock)', style: TextStyle(fontSize: 11.5, fontWeight: vm.toolbarDockPosition.isLeft ? FontWeight.bold : FontWeight.normal)),
              if (vm.toolbarDockPosition.isLeft) ...[
                const Spacer(),
                const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
              ],
            ],
          ),
        ),
        PopupMenuItem(
          value: ToolbarDockPosition.right,
          height: 32,
          child: Row(
            children: [
              Icon(Icons.border_right, size: 16, color: vm.toolbarDockPosition.isRight ? const Color(0xFF0284C7) : const Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text('Right Side (Vertical Dock)', style: TextStyle(fontSize: 11.5, fontWeight: vm.toolbarDockPosition.isRight ? FontWeight.bold : FontWeight.normal)),
              if (vm.toolbarDockPosition.isRight) ...[
                const Spacer(),
                const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem(
          value: ToolbarDockPosition.detached,
          height: 32,
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 16, color: vm.toolbarDockPosition.isDetached ? const Color(0xFF0284C7) : const Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text('Float / Detach (Palette)', style: TextStyle(fontSize: 11.5, fontWeight: vm.toolbarDockPosition.isDetached ? FontWeight.bold : FontWeight.normal)),
              if (vm.toolbarDockPosition.isDetached) ...[
                const Spacer(),
                const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateLibraryButton(BuildContext context, SheetMetalStudioViewModel vm, {required bool isCompact, required bool isVert}) {
    if (isVert) {
      return Tooltip(
        message: 'Template Library',
        child: InkWell(
          onTap: () {
            if (onOpenTemplateLibrary != null) {
              onOpenTemplateLibrary!();
            } else {
              DdsTemplateLibraryDialog.show(
                context,
                viewModel: vm,
                onOpenInEditor: (dsfDoc) => vm.loadDocument(dsfDoc),
              );
            }
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: isCompact ? 30 : 34,
            height: isCompact ? 30 : 34,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: vm.isTemplateActive ? const Color(0xFFE0F2FE) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: vm.isTemplateActive ? const Color(0xFF0284C7) : Colors.transparent,
                width: 1.0,
              ),
            ),
            child: Icon(
              Icons.dashboard_customize,
              size: isCompact ? 16 : 18,
              color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF475569),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Template Library (Browse & Insert Standard Templates)',
      child: InkWell(
        onTap: () {
          if (onOpenTemplateLibrary != null) {
            onOpenTemplateLibrary!();
          } else {
            DdsTemplateLibraryDialog.show(
              context,
              viewModel: vm,
              onOpenInEditor: (dsfDoc) => vm.loadDocument(dsfDoc),
            );
          }
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: isCompact ? 30 : 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
                Icons.dashboard_customize,
                size: isCompact ? 14 : 16,
                color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF475569),
              ),
              const SizedBox(width: 5),
              Text(
                'Template Library',
                style: TextStyle(
                  fontSize: isCompact ? 10.5 : 11.5,
                  fontWeight: FontWeight.w600,
                  color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSketchPaletteToggle(SheetMetalStudioViewModel vm, {required bool isCompact, required bool isVert}) {
    if (isVert) {
      return Tooltip(
        message: vm.isSketchPaletteOpen ? 'Close Sketch Palette' : 'Open Sketch Palette',
        child: InkWell(
          onTap: vm.toggleSketchPalette,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: isCompact ? 30 : 34,
            height: isCompact ? 30 : 34,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: vm.isSketchPaletteOpen ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: vm.isSketchPaletteOpen ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                width: 1.0,
              ),
            ),
            child: Icon(
              Icons.tune,
              size: isCompact ? 15 : 17,
              color: vm.isSketchPaletteOpen ? const Color(0xFF0284C7) : const Color(0xFF475569),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: vm.isSketchPaletteOpen
          ? 'Close Sketch Palette'
          : 'Open Sketch Palette (Grid, Points, Linetype)',
      child: InkWell(
        onTap: vm.toggleSketchPalette,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 7 : 9, vertical: isCompact ? 5 : 7.5),
          decoration: BoxDecoration(
            color: vm.isSketchPaletteOpen ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: vm.isSketchPaletteOpen ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                size: isCompact ? 13 : 15,
                color: vm.isSketchPaletteOpen ? const Color(0xFF0284C7) : const Color(0xFF475569),
              ),
              const SizedBox(width: 4),
              Text(
                'Palette',
                style: TextStyle(
                  fontSize: isCompact ? 10 : 11,
                  fontWeight: FontWeight.bold,
                  color: vm.isSketchPaletteOpen ? const Color(0xFF0284C7) : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinishSketchButton({required bool isCompact, required bool isVert}) {
    if (isVert) {
      return Tooltip(
        message: 'FINISH SKETCH',
        child: InkWell(
          onTap: onFinishSketch,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: isCompact ? 32 : 36,
            height: isCompact ? 32 : 36,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: const Icon(Icons.check, size: 18, color: Colors.white),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onFinishSketch,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 9 : 12, vertical: isCompact ? 6 : 8),
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
          children: [
            Icon(Icons.check, size: isCompact ? 14 : 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'FINISH SKETCH',
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompact ? 10 : 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider({required bool isVert}) {
    if (isVert) {
      return Container(
        width: 24,
        height: 1.0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: const Color(0xFFE2E8F0),
      );
    }
    return Container(
      height: 24,
      width: 1.0,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    required bool isCompact,
    Color? activeColor,
  }) {
    final actCol = activeColor ?? const Color(0xFF0284C7);
    final sz = isCompact ? 28.0 : 32.0;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: sz,
          height: sz,
          margin: const EdgeInsets.all(1.5),
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
            size: isCompact ? 15 : 18,
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
    required bool isCompact,
  }) {
    final outerSz = isCompact ? 26.0 : 30.0;
    final innerSz = isCompact ? 20.0 : 23.0;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: outerSz,
          height: outerSz,
          margin: const EdgeInsets.all(1.0),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Center(
            child: Container(
              width: innerSz,
              height: innerSz,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
              ),
              alignment: Alignment.center,
              child: Text(
                glyph,
                style: TextStyle(
                  fontSize: isCompact ? 9.5 : 10.5,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
