// =============================================================================
// studio_menu_bar.dart
//
// Unique, Intuitive, Colorful, and Fun Menu Bar for truFold Studio by Danish.
// Features:
// - Light background for all popup menus with crisp typography and borders
// - Instant menu opening (0ms, no sliding or delay) via AnimationStyle.noAnimation
// - Clear All button directly integrated in the menu bar
// - Unlinked/placeholder items and context-dependent actions are cleanly greyed out
// =============================================================================

import 'package:flutter/material.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../../services/studio_clipboard_service.dart';
import '../press_brake_machine_dialog.dart';
import '../punch_tooling_selector_dialog.dart';
import '../template_library_gallery_dialog.dart';
import '../template_authoring_wizard_dialog.dart';
import '../branding/trufold_app_icon_painter.dart';

class StudioMenuBar extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback onNewTab;
  final VoidCallback onOpenFile;
  final VoidCallback onSaveFile;
  final VoidCallback? onSaveAsFile;
  final VoidCallback? onSaveDdsProject;
  final VoidCallback? onExportDxf;
  final VoidCallback? onMaterialDialog;
  final VoidCallback? onLoadSampleBracket;
  final VoidCallback? onFittingDetails;
  final VoidCallback? onLoadSampleTray;
  final VoidCallback? onOpenTemplateLibrary;
  final VoidCallback? onOpenTemplateAuthoring;
  final Future<void> Function(BuildContext, SheetMetalStudioViewModel) onConfirmClearAll;

  const StudioMenuBar({
    super.key,
    required this.viewModel,
    required this.onNewTab,
    required this.onOpenFile,
    required this.onSaveFile,
    this.onSaveAsFile,
    this.onSaveDdsProject,
    this.onExportDxf,
    this.onMaterialDialog,
    this.onLoadSampleBracket,
    this.onFittingDetails,
    this.onLoadSampleTray,
    this.onOpenTemplateLibrary,
    this.onOpenTemplateAuthoring,
    required this.onConfirmClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. FILE (Emerald Green)
          _buildMenuButton(
            context: context,
            title: 'File',
            icon: Icons.folder_outlined,
            themeColor: const Color(0xFF10B981),
            menuItems: _buildFileMenuItems(context),
          ),

          // 2. EDIT (Warm Amber)
          _buildMenuButton(
            context: context,
            title: 'Edit',
            icon: Icons.edit_note_outlined,
            themeColor: const Color(0xFFF59E0B),
            menuItems: _buildEditMenuItems(context),
          ),

          // 3. SKETCH & 2D (Sky Blue)
          _buildMenuButton(
            context: context,
            title: 'Sketch',
            icon: Icons.draw_outlined,
            themeColor: const Color(0xFF0284C7),
            menuItems: _buildSketchMenuItems(context),
          ),

          // 4. SHEET METAL 3D (Electric Indigo)
          _buildMenuButton(
            context: context,
            title: 'Sheet Metal',
            icon: Icons.view_in_ar_outlined,
            themeColor: const Color(0xFF6366F1),
            menuItems: _buildSheetMetalMenuItems(context),
          ),

          // 5. CONSTRAINTS (Hot Magenta)
          _buildMenuButton(
            context: context,
            title: 'Constraints',
            icon: Icons.all_inclusive,
            themeColor: const Color(0xFFEC4899),
            menuItems: _buildConstraintMenuItems(context),
          ),

          // 6. MACHINE & TOOLING (Tangerine)
          _buildMenuButton(
            context: context,
            title: 'Tooling',
            icon: Icons.handyman_outlined,
            themeColor: const Color(0xFFF97316),
            menuItems: _buildToolingMenuItems(context),
          ),

          // 7. TEMPLATES (Deep Violet)
          _buildMenuButton(
            context: context,
            title: 'Templates',
            icon: Icons.auto_awesome_mosaic_outlined,
            themeColor: const Color(0xFFA855F7),
            menuItems: _buildTemplateMenuItems(context),
          ),

          // 8. VIEW & PANELS (Teal Cyan)
          _buildMenuButton(
            context: context,
            title: 'View',
            icon: Icons.dashboard_outlined,
            themeColor: const Color(0xFF06B6D4),
            menuItems: _buildViewMenuItems(context),
          ),

          // 9. HELP (Mint Lime)
          _buildMenuButton(
            context: context,
            title: 'Help',
            icon: Icons.help_outline_rounded,
            themeColor: const Color(0xFF14B8A6),
            menuItems: _buildHelpMenuItems(context),
          ),

          // Clear All Button (Integrated in Menu Bar)
          Container(
            height: 16,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: const Color(0xFF334155),
          ),
          Tooltip(
            message: 'Clear All & Reset Canvas (Start Fresh)',
            child: InkWell(
              onTap: () => onConfirmClearAll(context, viewModel),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.restart_alt, size: 13, color: Color(0xFFF87171)),
                    SizedBox(width: 4),
                    Text(
                      'Clear All',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFCA5A5),
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

  /// Builds an individual top-level menu dropdown button with light background and instant opening
  Widget _buildMenuButton({
    required BuildContext context,
    required String title,
    required IconData icon,
    Color? themeColor,
    required List<PopupMenuEntry<void>> menuItems,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
          ),
          elevation: 10,
          shadowColor: const Color(0x33000000),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE2E8F0),
          space: 6,
          thickness: 0.8,
        ),
      ),
      child: PopupMenuButton<void>(
        tooltip: '$title Menu',
        offset: const Offset(0, 30),
        popUpAnimationStyle: AnimationStyle.noAnimation, // Instant menu: no sliding animation
        itemBuilder: (ctx) => menuItems,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
              const SizedBox(width: 5),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF64748B)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. FILE MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildFileMenuItems(BuildContext context) {
    const col = Color(0xFF10B981);
    return [
      _buildMenuHeader('File Operations', col),
      _buildItem(
        icon: Icons.note_add_outlined,
        title: 'New Blank Part',
        subtitle: 'Start a new sheet metal design tab',
        shortcut: 'Ctrl+N',
        themeColor: col,
        onTap: onNewTab,
      ),
      _buildItem(
        icon: Icons.file_open_outlined,
        title: 'Open File...',
        subtitle: 'Open .dsf, .dxf, or .dds project',
        shortcut: 'Ctrl+O',
        themeColor: col,
        onTap: onOpenFile,
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.save_outlined,
        title: 'Save Part',
        subtitle: 'Save active tab to .dsf format',
        shortcut: 'Ctrl+S',
        themeColor: col,
        onTap: onSaveFile,
      ),
      _buildItem(
        icon: Icons.save_as_outlined,
        title: 'Save Part As...',
        subtitle: onSaveAsFile != null ? 'Save to a new filename or location' : 'Not linked in current tab',
        shortcut: 'Ctrl+Shift+S',
        enabled: onSaveAsFile != null,
        themeColor: col,
        onTap: onSaveAsFile ?? () {},
      ),
      _buildItem(
        icon: Icons.archive_outlined,
        title: 'Save DDS Project Container',
        subtitle: onSaveDdsProject != null ? 'Package all open workspace tabs into .dds' : 'Not linked in current tab',
        shortcut: 'Ctrl+Shift+D',
        enabled: onSaveDdsProject != null,
        themeColor: const Color(0xFFF59E0B),
        onTap: onSaveDdsProject ?? () {},
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.download_outlined,
        title: 'Export 2D Flat Pattern to DXF',
        subtitle: onExportDxf != null ? 'Generate CAM ready cutting profile with bend layers' : 'Not linked in current tab',
        shortcut: 'Ctrl+E',
        enabled: onExportDxf != null,
        themeColor: col,
        onTap: onExportDxf ?? () {},
      ),
      _buildItem(
        icon: Icons.science_outlined,
        title: 'Sheet Material & Gauge Library',
        subtitle: onMaterialDialog != null ? 'Configure thickness, K-Factor, and metal alloy' : 'Not linked in current tab',
        enabled: onMaterialDialog != null,
        themeColor: const Color(0xFF0284C7),
        onTap: onMaterialDialog ?? () {},
      ),
    ];
  }

  bool _hasSelection(SheetMetalStudioViewModel vm) {
    return vm.selectedBendId != null ||
        vm.selectedPunchId != null ||
        vm.selectedCutId != null ||
        vm.selectedPatternId != null ||
        vm.selectedArcId != null ||
        vm.selectedDimensionId != null ||
        vm.selectedEntityIds.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // 2. EDIT MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildEditMenuItems(BuildContext context) {
    const col = Color(0xFFF59E0B);
    final vm = viewModel;
    final hasSelection = _hasSelection(vm);

    return [
      _buildMenuHeader('History & Clipboard', col),
      _buildItem(
        icon: Icons.undo,
        title: 'Undo',
        subtitle: vm.canUndo ? 'Revert last drawing or bend edit' : 'No previous edits to undo',
        shortcut: 'Ctrl+Z',
        enabled: vm.canUndo,
        themeColor: col,
        onTap: vm.canUndo ? vm.undo : () {},
      ),
      _buildItem(
        icon: Icons.redo,
        title: 'Redo',
        subtitle: vm.canRedo ? 'Re-apply previously undone change' : 'No edits to redo',
        shortcut: 'Ctrl+Y',
        enabled: vm.canRedo,
        themeColor: col,
        onTap: vm.canRedo ? vm.redo : () {},
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.copy,
        title: 'Copy Feature',
        subtitle: hasSelection ? 'Copy selected lines or punches to clipboard' : 'Select an entity to copy',
        shortcut: 'Ctrl+C',
        enabled: hasSelection,
        themeColor: col,
        onTap: () => StudioClipboardService.copySelection(vm),
      ),
      _buildItem(
        icon: Icons.paste,
        title: 'Paste Feature',
        subtitle: StudioClipboardService.hasContent
            ? 'Paste clipboard features into active canvas'
            : 'Clipboard is empty',
        shortcut: 'Ctrl+V',
        enabled: StudioClipboardService.hasContent,
        themeColor: col,
        onTap: () => StudioClipboardService.pasteInto(vm),
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.tune,
        title: 'Properties Inspector',
        subtitle: vm.isPropertyInspectorOpen
            ? 'Hide floating properties panel'
            : 'Show properties for active selection',
        shortcut: 'Ctrl+1',
        themeColor: col,
        onTap: vm.togglePropertyInspector,
      ),
      _buildItem(
        icon: Icons.select_all,
        title: 'Select All',
        subtitle: 'Select all entities on canvas',
        shortcut: 'Ctrl+A',
        themeColor: col,
        onTap: vm.selectAll,
      ),
      _buildItem(
        icon: Icons.restart_alt,
        title: 'Clear All & Reset Canvas',
        subtitle: 'Reset workpiece to clean blank sheet',
        themeColor: const Color(0xFFEF4444),
        onTap: () => onConfirmClearAll(context, vm),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 3. SKETCH & 2D MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildSketchMenuItems(BuildContext context) {
    const col = Color(0xFF0284C7);
    final vm = viewModel;
    final hasSelection = _hasSelection(vm);

    return [
      _buildMenuHeader('2D CAD Primitives', col),
      _buildItem(
        icon: Icons.near_me_outlined,
        title: 'Select / Pointer',
        subtitle: 'Pick, drag, or inspect geometry',
        shortcut: 'Esc / V',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.select),
      ),
      _buildItem(
        icon: Icons.horizontal_rule,
        title: 'Line / Polyline',
        subtitle: 'Draw connected straight edges',
        shortcut: 'L',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.drawPolyline),
      ),
      _buildItem(
        icon: Icons.crop_square,
        title: 'Rectangle Punch',
        subtitle: 'Stamp rectangular hole or contour',
        shortcut: 'G',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.drawRectangle),
      ),
      _buildItem(
        icon: Icons.radio_button_unchecked,
        title: 'Circle / Bolt Hole Punch',
        subtitle: 'Stamp circular bolt holes or pilot holes',
        shortcut: 'C',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.drawCircle),
      ),
      _buildItem(
        icon: Icons.crop_16_9,
        title: 'Slot / Obround Punch',
        subtitle: 'Stamp elongated slot for bolt alignment',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.addPunchObround),
      ),
      _buildItem(
        icon: Icons.gesture,
        title: '3-Point Arc',
        subtitle: 'Draw tangential or radial curved arcs',
        shortcut: 'A',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.drawArc),
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.border_style,
        title: 'Construction Line Mode',
        subtitle: hasSelection
            ? 'Toggle selected line between geometry and reference guide'
            : 'Select lines to toggle construction guide',
        shortcut: 'Q',
        enabled: hasSelection,
        themeColor: const Color(0xFF00BCD4),
        onTap: vm.toggleSelectedConstruction,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 4. SHEET METAL 3D MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildSheetMetalMenuItems(BuildContext context) {
    const col = Color(0xFF6366F1);
    final vm = viewModel;
    final hasSelection = _hasSelection(vm);

    return [
      _buildMenuHeader('Sheet Metal Features', col),
      _buildItem(
        icon: Icons.alt_route,
        title: 'Add Bend Line',
        subtitle: 'Define press brake fold line (0° to 180°)',
        shortcut: 'B',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.addBend),
      ),
      _buildItem(
        icon: Icons.border_outer,
        title: 'Add Return Flange',
        subtitle: 'Extrude upward/downward edge flanges',
        shortcut: 'F',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.addFlange),
      ),
      _buildItem(
        icon: Icons.content_cut,
        title: 'Add Laser Cut Line / Slit',
        subtitle: 'Define internal parting slits and relief cuts',
        shortcut: 'M',
        themeColor: const Color(0xFFEF4444),
        onTap: () => vm.setToolMode(StudioToolMode.addCut),
      ),
      _buildItem(
        icon: Icons.grain,
        title: 'Perforation Pattern',
        subtitle: 'Staggered or linear punch grid matrix',
        shortcut: 'P',
        themeColor: const Color(0xFF0EA5E9),
        onTap: () => vm.setToolMode(StudioToolMode.perforationPattern),
      ),
      _buildItem(
        icon: Icons.anchor,
        title: 'Set Base Floor Anchor',
        subtitle: 'Pin down the stationary ground face for folding',
        shortcut: 'Anchor',
        themeColor: const Color(0xFFD97706),
        onTap: () => vm.setToolMode(StudioToolMode.setBaseAnchor),
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.crop_16_9,
        title: 'Slot / Obround Punch',
        subtitle: 'Stamp elongated slot for bolt alignment',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.addPunchObround),
      ),
      _buildItem(
        icon: Icons.rounded_corner,
        title: 'Corner Fillet',
        subtitle: 'Create smooth tangent rounded corner',
        shortcut: 'Shift+F',
        themeColor: const Color(0xFF06B6D4),
        onTap: () => vm.setToolMode(StudioToolMode.cornerFillet),
      ),
      _buildItem(
        icon: Icons.crop_square_sharp,
        title: 'Corner Chamfer',
        subtitle: 'Create 45° beveled corner cut',
        shortcut: 'Shift+C',
        themeColor: const Color(0xFF06B6D4),
        onTap: () => vm.setToolMode(StudioToolMode.cornerChamfer),
      ),
      _buildItem(
        icon: Icons.flip,
        title: 'Mirror Features',
        subtitle: hasSelection ? 'Reflect entities across symmetry line' : 'Select entities to mirror',
        enabled: hasSelection,
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.modifyMirror),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 5. CONSTRAINTS MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildConstraintMenuItems(BuildContext context) {
    const col = Color(0xFFEC4899);
    final vm = viewModel;
    return [
      _buildMenuHeader('Geometric & Dimensional Constraints', col),
      _buildItem(
        icon: Icons.straighten,
        title: 'Dimension',
        subtitle: 'Click & drag from A to B (Alt free)',
        shortcut: 'D',
        themeColor: const Color(0xFF0284C7),
        onTap: () => vm.setToolMode(StudioToolMode.dragDimension),
      ),
      _buildItem(
        icon: Icons.tune,
        title: 'Dimensional Constraints',
        subtitle: 'Constrain distance, length, or angle',
        shortcut: 'Shift+D',
        themeColor: col,
        onTap: () => vm.setToolMode(StudioToolMode.addDimension),
      ),
      _buildItem(
        icon: Icons.functions,
        title: 'Constraint Manager & Relations',
        subtitle: 'View, edit, and solve geometric relations',
        themeColor: col,
        onTap: vm.toggleConstraintManager,
      ),
      const PopupMenuDivider(),
      // Unlinked/placeholder constraint options are greyed out with clear status
      _buildItem(
        icon: Icons.fiber_manual_record,
        title: 'Coincident Constraint',
        subtitle: 'Not linked • Requires point pair selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
      _buildItem(
        icon: Icons.trip_origin,
        title: 'Concentric Constraint',
        subtitle: 'Not linked • Requires circle pair selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
      _buildItem(
        icon: Icons.reorder,
        title: 'Parallel Constraint',
        subtitle: 'Not linked • Requires line pair selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
      _buildItem(
        icon: Icons.show_chart,
        title: 'Tangent / Collinear Constraint',
        subtitle: 'Not linked • Requires curve alignment selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
      _buildItem(
        icon: Icons.minimize,
        title: 'Horizontal Constraint',
        subtitle: 'Not linked • Requires line selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
      _buildItem(
        icon: Icons.more_vert,
        title: 'Vertical Constraint',
        subtitle: 'Not linked • Requires line selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
      _buildItem(
        icon: Icons.square_foot,
        title: 'Perpendicular Constraint',
        subtitle: 'Not linked • Requires line pair selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
      _buildItem(
        icon: Icons.drag_handle,
        title: 'Equal Length Constraint',
        subtitle: 'Not linked • Requires line pair selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
      _buildItem(
        icon: Icons.lock_outline,
        title: 'Fix / Lock Coordinate',
        subtitle: 'Not linked • Requires vertex selection',
        themeColor: col,
        enabled: false,
        onTap: () {},
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 6. MACHINE & TOOLING MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildToolingMenuItems(BuildContext context) {
    const col = Color(0xFFF97316);
    final vm = viewModel;
    return [
      _buildMenuHeader('Press Brake & CNC Turret Tooling', col),
      _buildItem(
        icon: Icons.precision_manufacturing_outlined,
        title: 'Press Brake Machine & Tonnage Setup',
        subtitle: '${vm.selectedMachine.name} • Max ${vm.selectedMachine.maxTonnageTons.toInt()}T',
        themeColor: col,
        onTap: () => PressBrakeMachineDialog.show(context, vm),
      ),
      _buildItem(
        icon: Icons.hardware_outlined,
        title: 'Upper Punch Tooling Catalog',
        subtitle: 'Gooseneck, straight, and acute angle punches',
        themeColor: col,
        onTap: () => PunchToolingSelectorDialog.show(context, vm),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 7. TEMPLATES MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildTemplateMenuItems(BuildContext context) {
    const col = Color(0xFFA855F7);
    final vm = viewModel;
    return [
      _buildMenuHeader('Parametric Design Catalog', col),
      _buildItem(
        icon: Icons.dashboard_customize,
        title: 'Template Library Gallery...',
        subtitle: 'Browse HVAC fittings, brackets, and enclosures',
        themeColor: col,
        onTap: () {
          if (onOpenTemplateLibrary != null) {
            onOpenTemplateLibrary!.call();
          } else {
            showDialog(
              context: context,
              builder: (ctx) => TemplateLibraryGalleryDialog(viewModel: vm),
            );
          }
        },
      ),
      _buildItem(
        icon: Icons.auto_fix_high,
        title: 'Author Template from DXF Wizard...',
        subtitle: 'Turn custom DXF drawings into reusable parametric templates',
        themeColor: const Color(0xFF10B981),
        onTap: () {
          if (onOpenTemplateAuthoring != null) {
            onOpenTemplateAuthoring!.call();
          } else {
            showDialog(
              context: context,
              builder: (ctx) => TemplateAuthoringWizardDialog(viewModel: vm),
            );
          }
        },
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.architecture,
        title: 'Sample Sheet Metal Bracket',
        subtitle: onLoadSampleBracket != null
            ? '90° flanged mounting bracket with bolt holes'
            : 'Not available in current mode',
        enabled: onLoadSampleBracket != null,
        themeColor: col,
        onTap: onLoadSampleBracket ?? () {},
      ),
      _buildItem(
        icon: Icons.view_sidebar_outlined,
        title: 'Sample Cable Tray (100x50x3000mm)',
        subtitle: onLoadSampleTray != null
            ? 'Cable management profile with return flanges'
            : 'Not available in current mode',
        enabled: onLoadSampleTray != null,
        themeColor: col,
        onTap: onLoadSampleTray ?? () {},
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.call_split,
        title: 'T-Piece Duct Fitting',
        subtitle: 'Parametric 3-way branching duct',
        themeColor: col,
        onTap: () {
          vm.setPropertyInspectorOpen(true);
          vm.loadTemplateTee();
        },
      ),
      _buildItem(
        icon: Icons.turn_right,
        title: '90° Radius Elbow',
        subtitle: 'Smooth radius ventilation bend',
        themeColor: col,
        onTap: () {
          vm.setPropertyInspectorOpen(true);
          vm.loadTemplateBend90();
        },
      ),
      _buildItem(
        icon: Icons.alt_route,
        title: '45° Radius Elbow',
        subtitle: '45-degree angled duct elbow',
        themeColor: col,
        onTap: () {
          vm.setPropertyInspectorOpen(true);
          vm.loadTemplateBend45();
        },
      ),
      _buildItem(
        icon: Icons.compress,
        title: 'Concentric Reducer',
        subtitle: 'Transition between two duct sizes',
        themeColor: col,
        onTap: () {
          vm.setPropertyInspectorOpen(true);
          vm.loadTemplateReducer();
        },
      ),
      _buildItem(
        icon: Icons.add_road,
        title: '4-Way Cross Fitting',
        subtitle: 'Cruciform duct distribution cross',
        themeColor: col,
        onTap: () {
          vm.setPropertyInspectorOpen(true);
          vm.loadTemplateCross();
        },
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 8. VIEW & PANELS MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildViewMenuItems(BuildContext context) {
    const col = Color(0xFF06B6D4);
    final vm = viewModel;
    return [
      _buildMenuHeader('Workspace & Inspectors', col),
      _buildItem(
        icon: Icons.tune,
        title: 'CAD Properties Inspector',
        subtitle: vm.isPropertyInspectorOpen
            ? 'Hide floating properties panel'
            : 'Inspect & edit part/selection parameters',
        shortcut: 'Ctrl+1',
        themeColor: col,
        onTap: vm.togglePropertyInspector,
      ),
      _buildItem(
        icon: Icons.auto_awesome,
        title: 'DSF Parameter Inspector',
        subtitle: 'Auto-fold rules and metadata inspector',
        themeColor: col,
        onTap: onFittingDetails ?? () => vm.setFittingInspectorOpen(true),
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.vertical_split,
        title: 'Dual Viewport Split (50% / 50%)',
        subtitle: 'Balanced 2D flat and 3D folded views',
        themeColor: col,
        onTap: () => vm.setSplitRatio(0.50),
      ),
      _buildItem(
        icon: Icons.space_dashboard,
        title: 'Focus 2D Canvas (75% / 25%)',
        subtitle: 'Expanded drafting canvas view',
        themeColor: col,
        onTap: () => vm.setSplitRatio(0.75),
      ),
      _buildItem(
        icon: Icons.view_in_ar,
        title: 'Focus 3D Viewport (25% / 75%)',
        subtitle: 'Expanded 3D folded inspection view',
        themeColor: col,
        onTap: () => vm.setSplitRatio(0.25),
      ),
      const PopupMenuDivider(),
      _buildItem(
        icon: Icons.center_focus_strong,
        title: 'Reset 3D Isometric Camera',
        subtitle: '45° azimuth, 35° elevation isometric view',
        themeColor: col,
        onTap: () => vm.setPresetView(azimuth: 45, elevation: 35),
      ),
      _buildItem(
        icon: Icons.vertical_align_top,
        title: 'Top Down Camera View',
        subtitle: 'Plan view looking down on sheet metal',
        themeColor: col,
        onTap: () => vm.setPresetView(azimuth: 0, elevation: 89),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 9. HELP MENU ITEMS (Light Theme)
  // ---------------------------------------------------------------------------
  List<PopupMenuEntry<void>> _buildHelpMenuItems(BuildContext context) {
    const col = Color(0xFF14B8A6);
    return [
      _buildMenuHeader('Documentation & Shortcuts', col),
      _buildItem(
        icon: Icons.keyboard_outlined,
        title: 'Keyboard Shortcuts Guide',
        subtitle: 'B: Bend • F: Flange • M: Cut • L: Line • D: Dimension',
        themeColor: col,
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
              ),
              title: const Row(
                children: [
                  Icon(Icons.keyboard, color: Color(0xFF0284C7), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Keyboard Shortcuts',
                    style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    _ShortcutRow('B', 'Add Bend Line (Ctrl toggles Auto Bend)'),
                    _ShortcutRow('F', 'Add Return Flange'),
                    _ShortcutRow('M', 'Laser Cut / Slit Line'),
                    _ShortcutRow('L', 'Draw Line / Polyline'),
                    _ShortcutRow('G', 'Rectangle / Square Punch'),
                    _ShortcutRow('C', 'Circle / Bolt Hole Punch'),
                    _ShortcutRow('Slot', 'Obround / Slot Punch'),
                    _ShortcutRow('A', '3-Point Curved Arc'),
                    _ShortcutRow('D', 'Dimension Measurement (Alt Free)'),
                    _ShortcutRow('Shift+D', 'Dimensional Constraints Solver'),
                    _ShortcutRow('Shift+F', 'Corner Fillet'),
                    _ShortcutRow('Shift+C', 'Corner Chamfer'),
                    _ShortcutRow('Esc / V', 'Select Tool Mode'),
                    _ShortcutRow('Ctrl+S', 'Save Active Part'),
                    _ShortcutRow('Ctrl+Z / Y', 'Undo / Redo'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
      _buildItem(
        icon: Icons.info_outline,
        title: 'About truFold Studio',
        subtitle: 'Advanced Sheet Metal CAD & Unfolding Engine by Danish',
        themeColor: col,
        onTap: () {
          showAboutDialog(
            context: context,
            applicationIcon: const TruFoldAppIconTile(size: 54, isDark: true),
            applicationName: 'truFold Studio',
            applicationVersion: '1.0.0 Pro',
            applicationLegalese: '© Danish Sheet Metal CAD Solutions. All rights reserved.',
          );
        },
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Helper builders for rich popup menu items (Light Theme)
  // ---------------------------------------------------------------------------
  static PopupMenuItem<void> _buildMenuHeader(String title, [Color? themeColor]) {
    return PopupMenuItem<void>(
      enabled: false,
      height: 28,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF64748B),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static PopupMenuItem<void> _buildItem({
    required IconData icon,
    required String title,
    required String subtitle,
    String? shortcut,
    Color? themeColor,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return PopupMenuItem<void>(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: enabled ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
              child: Icon(
                icon,
                size: 15,
                color: enabled ? const Color(0xFF334155) : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: enabled ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (shortcut != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: enabled ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: enabled ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  shortcut,
                  style: TextStyle(
                    color: enabled ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                    fontSize: 9.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String keyString;
  final String actionString;

  const _ShortcutRow(this.keyString, this.actionString);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 60),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            alignment: Alignment.center,
            child: Text(
              keyString,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              actionString,
              style: const TextStyle(color: Color(0xFF334155), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
