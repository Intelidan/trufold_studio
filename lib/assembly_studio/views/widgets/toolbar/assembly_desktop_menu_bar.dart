// Assembly Studio Desktop CAD Menu Bar (SS2)
// Full-featured menu bar providing File, Edit, View, Panels, Windows, Settings, and Help dropdowns.
// High contrast, crisp light aesthetic, instant zero-lag response.

import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cad_brep_flutter_gpu_scene.dart' hide Material;
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/assembly_viewport_dialogs.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/assembly_dsf_anatomy_dialog.dart';

class AssemblyDesktopMenuBar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback? onToggleLeftPanel;
  final VoidCallback? onToggleRightPanel;
  final VoidCallback? onToggleBottomDrawer;
  final bool isLeftPanelOpen;
  final bool isRightPanelOpen;
  final bool isBottomDrawerOpen;
  final VoidCallback? onResetPositions;

  const AssemblyDesktopMenuBar({
    super.key,
    required this.viewModel,
    this.onToggleLeftPanel,
    this.onToggleRightPanel,
    this.onToggleBottomDrawer,
    this.isLeftPanelOpen = true,
    this.isRightPanelOpen = true,
    this.isBottomDrawerOpen = false,
    this.onResetPositions,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final vm = viewModel;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFileMenu(context, vm),
            _buildEditMenu(context, vm),
            _buildViewMenu(context, vm),
            _buildPanelsMenu(context, vm),
            _buildWindowsMenu(context, vm),
            _buildSettingsMenu(context, vm),
            _buildHelpMenu(context, vm),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 1. FILE MENU
  // ---------------------------------------------------------------------------
  Widget _buildFileMenu(BuildContext context, AssemblyStudioViewModel vm) {
    return _buildMenuDropdown(
      title: 'File',
      items: [
        _buildItem(value: 'new', label: 'New Blank Assembly', shortcut: 'Ctrl+N', icon: Icons.create_new_folder_outlined),
        _buildItem(value: 'open', label: 'Open Assembly (.dam)...', shortcut: 'Ctrl+O', icon: Icons.folder_open_outlined),
        _buildItem(value: 'save', label: 'Save Assembly (.dam)', shortcut: 'Ctrl+S', icon: Icons.save_outlined),
        _buildItem(value: 'import_dsf', label: 'Import DSF Part(s)...', shortcut: 'Ctrl+I', icon: Icons.file_download_outlined),
        const PopupMenuDivider(),
        _buildItem(value: 'cad_anatomy', label: 'View Part CAD Anatomy...', icon: Icons.architecture_rounded, enabled: vm.selectedPart != null),
        const PopupMenuDivider(),
        _buildItem(value: 'sample_ladder', label: 'Load Cable Ladder Demo (600x1000mm)', icon: Icons.view_headline_rounded),
        _buildItem(value: 'sample_tray', label: 'Load Cable Tray Demo (Perforated + Bend)', icon: Icons.dashboard_outlined),
        _buildItem(value: 'sample_trunking', label: 'Load Cable Trunking Demo (Base + Cover)', icon: Icons.view_stream_rounded),
        _buildItem(value: 'sample_bent', label: 'Load Cable Ladder Tee Branch', icon: Icons.alt_route_rounded),
        const PopupMenuDivider(),
        _buildItem(value: 'bom', label: 'Cut List & Bill of Materials (BOM)', icon: Icons.table_chart_outlined),
        _buildItem(value: 'compliance', label: 'IEC 61537 / NEMA VE 1 Cable System Verification', icon: Icons.verified_user_outlined),
      ],
      onSelected: (val) {
        switch (val) {
          case 'new':
            vm.initBlankAssembly();
            break;
          case 'open':
            vm.openDamDocument(context: context);
            break;
          case 'save':
            vm.saveDamDocument(context: context);
            break;
          case 'import_dsf':
            vm.importDsfFiles(context: context);
            break;
          case 'cad_anatomy':
            if (vm.selectedPart != null) {
              AssemblyDsfAnatomyDialog.show(context, vm.selectedPart!, vm);
            }
            break;
          case 'sample_ladder':
            vm.loadStandardLadderDemo();
            break;
          case 'sample_tray':
            vm.loadCableTrayDemo();
            break;
          case 'sample_trunking':
            vm.loadCableTrunkingDemo();
            break;
          case 'sample_bent':
            vm.loadTeeAssemblyDemo();
            break;
          case 'bom':
            AssemblyViewportDialogs.showBomDialog(context, vm);
            break;
          case 'compliance':
            AssemblyViewportDialogs.showComplianceAuditDialog(context, vm);
            break;
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. EDIT MENU
  // ---------------------------------------------------------------------------
  Widget _buildEditMenu(BuildContext context, AssemblyStudioViewModel vm) {
    return _buildMenuDropdown(
      title: 'Edit',
      items: [
        _buildItem(value: 'undo', label: 'Undo', shortcut: 'Ctrl+Z', icon: Icons.undo_rounded, enabled: vm.canUndo),
        _buildItem(value: 'redo', label: 'Redo', shortcut: 'Ctrl+Y', icon: Icons.redo_rounded, enabled: vm.canRedo),
        const PopupMenuDivider(),
        _buildItem(value: 'select_all', label: 'Select All Parts', shortcut: 'Ctrl+A', icon: Icons.select_all_rounded),
        _buildItem(value: 'clear_selection', label: 'Clear Selection', shortcut: 'Esc', icon: Icons.deselect_rounded),
        _buildItem(value: 'invert_selection', label: 'Invert Selection', icon: Icons.swap_horiz_rounded),
        const PopupMenuDivider(),
        _buildItem(value: 'break_weld', label: 'Break Welds for Selected Part', icon: Icons.link_off_rounded, enabled: vm.selectedPart != null),
        _buildItem(value: 'delete', label: 'Delete Selected Part', shortcut: 'Del', icon: Icons.delete_outline_rounded, enabled: vm.selectedPart != null),
      ],
      onSelected: (val) {
        switch (val) {
          case 'undo':
            vm.undo();
            break;
          case 'redo':
            vm.redo();
            break;
          case 'select_all':
            vm.doc.selectedPartIds = vm.doc.parts.map((p) => p.id).toSet();
            if (vm.doc.parts.isNotEmpty) vm.doc.selectedPartId = vm.doc.parts.first.id;
            vm.notifyListeners();
            break;
          case 'clear_selection':
            vm.selectPart(null);
            break;
          case 'invert_selection':
            final allIds = vm.doc.parts.map((p) => p.id).toSet();
            vm.doc.selectedPartIds = allIds.difference(vm.doc.selectedPartIds);
            vm.doc.selectedPartId = vm.doc.selectedPartIds.firstOrNull;
            vm.notifyListeners();
            break;
          case 'break_weld':
            if (vm.selectedPart != null) {
              vm.breakAllBondsForPart(vm.selectedPart!.id);
            }
            break;
          case 'delete':
            vm.deleteSelectedPart();
            break;
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 3. VIEW MENU
  // ---------------------------------------------------------------------------
  Widget _buildViewMenu(BuildContext context, AssemblyStudioViewModel vm) {
    return _buildMenuDropdown(
      title: 'View',
      items: [
        _buildItem(value: 'iso', label: 'Isometric View', icon: Icons.view_in_ar_rounded),
        _buildItem(value: 'top', label: 'Top View', icon: Icons.vertical_align_top_rounded),
        _buildItem(value: 'front', label: 'Front View', icon: Icons.crop_portrait_rounded),
        _buildItem(value: 'right', label: 'Right Side View', icon: Icons.crop_landscape_rounded),
        _buildItem(value: 'fit', label: 'Zoom to Fit', shortcut: 'F', icon: Icons.filter_center_focus_rounded),
        _buildItem(value: 'normal', label: 'Align to Face Normal', shortcut: 'N', icon: Icons.explore_outlined),
        const PopupMenuDivider(),
        _buildCheckboxItem(value: 'planes', label: 'Datum Planes', isChecked: vm.showDatumPlanes, shortcut: 'P'),
        _buildCheckboxItem(value: 'construction', label: 'Construction Planes', isChecked: vm.showConstructionPlanes),
        _buildCheckboxItem(value: 'grid', label: '3D Floor Grid', isChecked: vm.showSketchGrid),
        _buildCheckboxItem(value: 'wireframe', label: 'Feature Wireframe Edges', isChecked: vm.showWireframe),
        _buildCheckboxItem(value: 'clean_canvas', label: 'Clean Canvas Mode', isChecked: vm.isCleanCanvasMode),
        const PopupMenuDivider(),
        _buildCheckboxItem(
          value: 'engine_custom_paint',
          label: 'Layer 1A: CustomPaint B-Rep + Newell 3D (v9.3 Backup)',
          isChecked: CadFpsTelemetry.activeEngine == CadLayer1Engine.customPaintV93,
        ),
        _buildCheckboxItem(
          value: 'engine_three_js',
          label: 'Layer 1B: three_js (WebGL2/ANGLE Hardware Z-Buffer)',
          isChecked: CadFpsTelemetry.activeEngine == CadLayer1Engine.threeJsGpu,
        ),
        _buildCheckboxItem(
          value: 'engine_flutter3d',
          label: 'Layer 1C: flutter3d (Impeller PBR/Toon Z-Buffer)',
          isChecked: CadFpsTelemetry.activeEngine == CadLayer1Engine.flutter3dGpu,
        ),
      ],
      onSelected: (val) {
        switch (val) {
          case 'iso':
            vm.setIsometricView();
            break;
          case 'top':
            vm.setTopView();
            break;
          case 'front':
            vm.setFrontView();
            break;
          case 'right':
            vm.setRightView();
            break;
          case 'fit':
            vm.zoomToFit();
            break;
          case 'normal':
            vm.alignCameraToActivePlaneNormal();
            break;
          case 'planes':
            vm.showDatumPlanes = !vm.showDatumPlanes;
            vm.showConstructionPlanes = vm.showDatumPlanes;
            vm.notifyDocChanged();
            break;
          case 'construction':
            vm.showConstructionPlanes = !vm.showConstructionPlanes;
            vm.notifyDocChanged();
            break;
          case 'grid':
            vm.toggleSketchGrid();
            break;
          case 'wireframe':
            vm.showWireframe = !vm.showWireframe;
            vm.notifyDocChanged();
            break;
          case 'clean_canvas':
            vm.toggleCleanCanvasMode();
            break;
          case 'engine_custom_paint':
            CadFpsTelemetry.setEngine(CadLayer1Engine.customPaintV93);
            vm.notifyDocChanged();
            break;
          case 'engine_three_js':
            CadFpsTelemetry.setEngine(CadLayer1Engine.threeJsGpu);
            vm.notifyDocChanged();
            break;
          case 'engine_flutter3d':
            CadFpsTelemetry.setEngine(CadLayer1Engine.flutter3dGpu);
            vm.notifyDocChanged();
            break;
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 4. PANELS MENU
  // ---------------------------------------------------------------------------
  Widget _buildPanelsMenu(BuildContext context, AssemblyStudioViewModel vm) {
    return _buildMenuDropdown(
      title: 'Panels',
      items: [
        _buildCheckboxItem(value: 'left_panel', label: 'Features & Parts Outliner (Left)', isChecked: isLeftPanelOpen),
        _buildCheckboxItem(value: 'right_panel', label: 'Property Inspector Grid (Right)', isChecked: isRightPanelOpen),
        _buildCheckboxItem(value: 'bottom_drawer', label: 'Asset & Component Drawer (Bottom)', isChecked: isBottomDrawerOpen),
        const PopupMenuDivider(),
        _buildCheckboxItem(value: 'timeline', label: 'Parametric History Timeline', isChecked: vm.cadSettings.showTimeline),
      ],
      onSelected: (val) {
        switch (val) {
          case 'left_panel':
            onToggleLeftPanel?.call();
            break;
          case 'right_panel':
            onToggleRightPanel?.call();
            break;
          case 'bottom_drawer':
            onToggleBottomDrawer?.call();
            break;
          case 'timeline':
            vm.cadSettings = vm.cadSettings.copyWith(showTimeline: !vm.cadSettings.showTimeline);
            vm.notifyListeners();
            break;
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 5. WINDOWS MENU
  // ---------------------------------------------------------------------------
  Widget _buildWindowsMenu(BuildContext context, AssemblyStudioViewModel vm) {
    return _buildMenuDropdown(
      title: 'Windows',
      items: [
        _buildCheckboxItem(value: 'views_bar', label: 'Standard Views Toolbar', isChecked: vm.showViewsToolbar),
        _buildCheckboxItem(value: 'joint_bar', label: 'Joint Configuration Toolbar', isChecked: vm.showJointStyleToolbar),
        _buildCheckboxItem(value: 'quality_hud', label: 'Weld Quality & Anomaly HUD', isChecked: vm.showQualityHud),
        _buildCheckboxItem(value: 'nav_bar', label: '3D Navigation Bar', isChecked: vm.show3dNavigationBar),
        const PopupMenuDivider(),
        _buildItem(value: 'reset_toolbars', label: 'Reset All Toolbar Positions', icon: Icons.restart_alt_rounded, color: const Color(0xFFDC2626)),
      ],
      onSelected: (val) {
        switch (val) {
          case 'views_bar':
            vm.toggleViewsToolbar();
            break;
          case 'joint_bar':
            vm.toggleJointStyleToolbar();
            break;
          case 'quality_hud':
            vm.toggleQualityHud();
            break;
          case 'nav_bar':
            vm.toggle3dNavigationBar();
            break;
          case 'reset_toolbars':
            onResetPositions?.call();
            break;
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 6. SETTINGS MENU
  // ---------------------------------------------------------------------------
  Widget _buildSettingsMenu(BuildContext context, AssemblyStudioViewModel vm) {
    return _buildMenuDropdown(
      title: 'Settings',
      items: [
        _buildItem(value: 'cad_settings', label: 'Parametric CAD & Viewport Settings...', icon: Icons.tune_rounded),
        _buildItem(value: 'units', label: 'Measurement Units & Precision...', icon: Icons.straighten_rounded),
        _buildItem(value: 'materials', label: 'Material Finish & PBR Shaders...', icon: Icons.palette_outlined),
        _buildItem(value: 'compliance_rules', label: 'OSHA / ISO Safety Compliance Rules...', icon: Icons.security_rounded),
      ],
      onSelected: (val) {
        switch (val) {
          case 'cad_settings':
            vm.isCadSettingsOpen = true;
            vm.notifyListeners();
            break;
          case 'units':
          case 'materials':
          case 'compliance_rules':
            vm.isCadSettingsOpen = true;
            vm.notifyListeners();
            break;
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 7. HELP MENU
  // ---------------------------------------------------------------------------
  Widget _buildHelpMenu(BuildContext context, AssemblyStudioViewModel vm) {
    return _buildMenuDropdown(
      title: 'Help',
      items: [
        _buildItem(value: 'shortcuts', label: 'Keyboard Shortcuts Reference', icon: Icons.keyboard_outlined),
        _buildItem(value: 'about', label: 'About TruFold Studio CAD', icon: Icons.info_outline_rounded),
      ],
      onSelected: (val) {
        if (val == 'shortcuts' || val == 'about') {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.white,
              title: const Row(
                children: [
                  Icon(Icons.layers_rounded, color: Color(0xFF0076CE)),
                  SizedBox(width: 8),
                  Text('TruFold Assembly Studio CAD', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('High-Performance Sheet Metal CAD & Parametric Assembly Engine.', style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
                  SizedBox(height: 12),
                  Text('• Shift+S: Enter 2D/3D Sketch Mode', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  Text('• Shift+E: Extrude 3D Solid Feature', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  Text('• N: Align Camera to Plane Normal', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  Text('• P: Toggle Datum & Construction Planes', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  Text('• F: Zoom to Fit Model in Viewport', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  Text('• Middle-Mouse Drag: Pan / Orbit Camera', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close', style: TextStyle(color: Color(0xFF0076CE), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MENU BUILDER HELPERS
  // ---------------------------------------------------------------------------
  Widget _buildMenuDropdown({
    required String title,
    required List<PopupMenuEntry<String>> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      tooltip: '$title Menu',
      position: PopupMenuPosition.under,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
      ),
      elevation: 6,
      itemBuilder: (_) => items,
      onSelected: onSelected,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        alignment: Alignment.center,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildItem({
    required String value,
    required String label,
    IconData? icon,
    String? shortcut,
    bool enabled = true,
    Color? color,
  }) {
    final itemColor = color ?? const Color(0xFF0F172A);

    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 30,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: enabled ? itemColor : const Color(0xFF94A3B8)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: enabled ? itemColor : const Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (shortcut != null) ...[
            const SizedBox(width: 14),
            Text(
              shortcut,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildCheckboxItem({
    required String value,
    required String label,
    required bool isChecked,
    String? shortcut,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 30,
      child: Row(
        children: [
          Icon(
            isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            size: 15,
            color: isChecked ? const Color(0xFF0076CE) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
            ),
          ),
          if (shortcut != null) ...[
            const SizedBox(width: 14),
            Text(
              shortcut,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }
}
