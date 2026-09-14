// =============================================================================
// fusion_ribbon_toolbar.dart
//
// Autodesk Fusion 360-style Sketch Ribbon & Workspace Header for TruFold Studio.
// Replaces the legacy action-chip header with Fusion 360's exact Ribbon structure:
// - Top document tab strip with unsaved status bar
// - Workspace selector (DESIGN dropdown) and mode tabs (SOLID, SHEET METAL, SKETCH)
// - Ribbon command groups: CREATE, MODIFY, CONSTRAINTS, DIMENSIONS, INSPECT, INSERT, SELECT
// - Dedicated green "FINISH SKETCH" checkmark button
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/cad_constraint.dart';
import '../../../models/studio_tab_model.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../studio_tab_bar.dart';
import '../template_library_gallery_dialog.dart';
import '../template_authoring_wizard_dialog.dart';
import '../../../services/studio_clipboard_service.dart';

class FusionRibbonToolbar extends StatefulWidget {
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

  const FusionRibbonToolbar({
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
  State<FusionRibbonToolbar> createState() => _FusionRibbonToolbarState();
}

class _FusionRibbonToolbarState extends State<FusionRibbonToolbar> {
  String _activeWorkspaceTab = 'SKETCH';

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9), // Fusion 360 light gray ribbon background
        border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Top Title & Quick Access Bar (Dark/Slate Fusion 360 title bar)
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

          // 3. Secondary Workspace Navigation Bar (DESIGN dropdown + SOLID, SHEET METAL, SKETCH tabs)
          _buildWorkspaceNavBar(),

          // 4. Main Sketch Ribbon Tool Groups (CREATE, MODIFY, CONSTRAINTS, DIMENSIONS, FINISH SKETCH)
          _buildSketchRibbon(vm),
        ],
      ),
    );
  }

  /// 1. Top Title & Quick Access Bar
  Widget _buildTopTitleBar(SheetMetalStudioViewModel vm) {
    return Container(
      height: 36,
      color: const Color(0xFF0F172A), // Dark slate title bar
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.precision_manufacturing, color: Color(0xFF38BDF8), size: 16),
          const SizedBox(width: 8),
          const Text(
            'DANISH FORMMATRIX STUDIO (DSF)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          // Action Buttons: Fitting Details (if applicable) -> Sample Tray -> Save .dsf -> Undo -> Redo
          if (vm.document.productType.toLowerCase().contains('tee') ||
              vm.document.productType.toLowerCase().contains('fitting') ||
              vm.document.productType.toLowerCase().contains('elbow') ||
              vm.document.productType.toLowerCase().contains('reducer') ||
              vm.document.productType.toLowerCase().contains('cross')) ...[
            InkWell(
              onTap: widget.onFittingDetails ?? () => vm.setPropertyInspectorOpen(true),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Fitting Details & Auto Fold',
                  style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          InkWell(
            onTap: widget.onLoadSampleTray ?? () => vm.loadSampleCableTray(),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Sample Tray (100x50)',
                style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Save Part (.dsf) (Ctrl+S)',
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
        ],
      ),
    );
  }

  /// 2. Workspace Navigation Bar (DESIGN dropdown + SOLID, SHEET METAL, SKETCH tabs)
  Widget _buildWorkspaceNavBar() {
    const tabs = ['SOLID', 'SURFACE', 'MESH', 'SHEET METAL', 'PLASTIC', 'UTILITIES', 'SKETCH'];

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
      ),
      child: Row(
        children: [
          // DESIGN Mode Pill Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A), // Fusion 360 black dropdown button
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DESIGN',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, color: Colors.white, size: 14),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Workspace Tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in tabs) ...[
                    _buildWorkspaceTab(tab),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceTab(String name) {
    final isActive = _activeWorkspaceTab == name;
    return InkWell(
      onTap: () {
        setState(() => _activeWorkspaceTab = name);
        if (name == 'SHEET METAL' || name == 'SOLID') {
          widget.onFinishSketch();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF0284C7) : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            color: isActive ? const Color(0xFF0284C7) : const Color(0xFF64748B),
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  /// 3. Main Sketch Ribbon Tool Groups (CREATE, MODIFY, CONSTRAINTS, DIMENSIONS, FINISH SKETCH)
  Widget _buildSketchRibbon(SheetMetalStudioViewModel vm) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Ribbon Groups in a horizontal scrollable view
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  // GROUP 1: CREATE
                  _buildRibbonGroup(
                    title: 'CREATE',
                    children: [
                      _buildRibbonButton(
                        icon: Icons.horizontal_rule,
                        label: 'Line',
                        isActive: vm.toolMode == StudioToolMode.drawPolyline || vm.toolMode == StudioToolMode.addCut,
                        onTap: () => vm.setToolMode(StudioToolMode.drawPolyline),
                      ),
                      _buildRibbonButton(
                        icon: Icons.crop_square,
                        label: 'Rectangle',
                        isActive: vm.toolMode == StudioToolMode.drawRectangle,
                        onTap: () => vm.setToolMode(StudioToolMode.drawRectangle),
                      ),
                      _buildRibbonButton(
                        icon: Icons.radio_button_unchecked,
                        label: 'Circle',
                        isActive: vm.toolMode == StudioToolMode.drawCircle || vm.toolMode == StudioToolMode.addPunchRound,
                        onTap: () => vm.setToolMode(StudioToolMode.drawCircle),
                      ),
                      _buildRibbonButton(
                        icon: Icons.gesture,
                        label: 'Arc / Bend',
                        isActive: vm.toolMode == StudioToolMode.drawArc || vm.toolMode == StudioToolMode.addBend,
                        onTap: () => vm.setToolMode(StudioToolMode.drawArc),
                      ),
                      _buildRibbonButton(
                        icon: Icons.grain,
                        label: 'Perforation',
                        isActive: vm.toolMode == StudioToolMode.perforationPattern,
                        onTap: () => vm.setToolMode(StudioToolMode.perforationPattern),
                      ),
                      _buildRibbonButton(
                        icon: Icons.auto_fix_high,
                        label: 'Author Tpl',
                        isActive: false,
                        onTap: () {
                          if (widget.onOpenTemplateAuthoring != null) {
                            widget.onOpenTemplateAuthoring!.call();
                          } else {
                            showDialog(
                              context: context,
                              builder: (ctx) => TemplateAuthoringWizardDialog(viewModel: vm),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  _buildRibbonDivider(),

                  // GROUP 2: MODIFY
                  _buildRibbonGroup(
                    title: 'MODIFY',
                    children: [
                      _buildRibbonButton(
                        icon: Icons.rounded_corner,
                        label: 'Fillet',
                        isActive: vm.toolMode == StudioToolMode.cornerFillet,
                        onTap: () => vm.setToolMode(StudioToolMode.cornerFillet),
                      ),
                      _buildRibbonButton(
                        icon: Icons.content_cut,
                        label: 'Cut Slit',
                        isActive: vm.toolMode == StudioToolMode.addCut,
                        onTap: () => vm.setToolMode(StudioToolMode.addCut),
                      ),
                      _buildRibbonButton(
                        icon: Icons.flip,
                        label: 'Mirror',
                        isActive: vm.toolMode == StudioToolMode.modifyMirror,
                        onTap: () => vm.setToolMode(StudioToolMode.modifyMirror),
                      ),
                    ],
                  ),
                  _buildRibbonDivider(),

                  // GROUP 3: CONSTRAINTS (Fusion 360 Glyphs)
                  _buildRibbonGroup(
                    title: 'CONSTRAINTS',
                    children: [
                      _buildConstraintGlyphButton(
                        symbol: '─│',
                        tooltip: 'Horizontal / Vertical',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.horizontal),
                      ),
                      _buildConstraintGlyphButton(
                        symbol: '●',
                        tooltip: 'Coincident',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.coincident),
                      ),
                      _buildConstraintGlyphButton(
                        symbol: '⌒',
                        tooltip: 'Tangent',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.collinear),
                      ),
                      _buildConstraintGlyphButton(
                        symbol: '=',
                        tooltip: 'Equal',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.equal),
                      ),
                      _buildConstraintGlyphButton(
                        symbol: '//',
                        tooltip: 'Parallel',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.parallel),
                      ),
                      _buildConstraintGlyphButton(
                        symbol: '⊥',
                        tooltip: 'Perpendicular',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.perpendicular),
                      ),
                      _buildConstraintGlyphButton(
                        symbol: '◎',
                        tooltip: 'Concentric',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.concentric),
                      ),
                      _buildConstraintGlyphButton(
                        symbol: '🔒',
                        tooltip: 'Fix / Unfix',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.fixed),
                      ),
                      _buildConstraintGlyphButton(
                        symbol: '◇',
                        tooltip: 'Symmetry',
                        onTap: () => vm.startInteractiveConstraintPick(CadConstraintType.symmetric),
                      ),
                    ],
                  ),
                  _buildRibbonDivider(),

                  // GROUP 4: DIMENSIONS & PARAMETERS
                  _buildRibbonGroup(
                    title: 'DIMENSIONS',
                    children: [
                      _buildRibbonButton(
                        icon: Icons.straighten,
                        label: 'Dimension',
                        isActive: vm.toolMode == StudioToolMode.addDimension || vm.activeConstraintPickType == CadConstraintType.distance,
                        onTap: () => vm.setToolMode(StudioToolMode.addDimension),
                      ),
                      _buildRibbonButton(
                        icon: Icons.functions,
                        label: 'Constraints',
                        isActive: vm.isConstraintManagerOpen,
                        onTap: () => vm.toggleConstraintManager(),
                      ),
                    ],
                  ),
                  _buildRibbonDivider(),

                  // GROUP 5: INSPECT
                  _buildRibbonGroup(
                    title: 'INSPECT',
                    children: [
                      _buildRibbonButton(
                        icon: Icons.speed,
                        label: 'Measure',
                        isActive: false,
                        onTap: () {},
                      ),
                    ],
                  ),
                  _buildRibbonDivider(),

                  // GROUP 5b: INSERT
                  _buildRibbonGroup(
                    title: 'INSERT',
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Parametric Templates & Components',
                        offset: const Offset(0, 48),
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
                          const PopupMenuItem(
                            value: 'tee',
                            child: Text('T-Piece Duct Fitting (90° Branch)'),
                          ),
                          const PopupMenuItem(
                            value: 'bend90',
                            child: Text('90° Radius Segmented Elbow'),
                          ),
                          const PopupMenuItem(
                            value: 'bend45',
                            child: Text('45° Radius Elbow'),
                          ),
                          const PopupMenuItem(
                            value: 'reducer',
                            child: Text('Concentric Rectangular Reducer'),
                          ),
                          const PopupMenuItem(
                            value: 'cross',
                            child: Text('4-Way Cross Fitting'),
                          ),
                          const PopupMenuItem(
                            value: 'straight',
                            child: Text('Standard Straight Duct Segment'),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: vm.isTemplateActive ? const Color(0xFFE0F2FE) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.auto_awesome_mosaic_outlined,
                                size: 18,
                                color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF475569),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Template',
                                style: TextStyle(
                                  color: vm.isTemplateActive ? const Color(0xFF0284C7) : const Color(0xFF334155),
                                  fontSize: 9.5,
                                  fontWeight: vm.isTemplateActive ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildRibbonButton(
                        icon: Icons.auto_awesome,
                        label: 'Auto Fold',
                        isActive: vm.isFittingInspectorOpen,
                        onTap: vm.toggleFittingInspector,
                      ),
                    ],
                  ),
                  _buildRibbonDivider(),

                  // GROUP 6: SELECT
                  _buildRibbonGroup(
                    title: 'SELECT',
                    children: [
                      _buildRibbonButton(
                        icon: Icons.near_me,
                        label: 'Select',
                        isActive: vm.toolMode == StudioToolMode.select,
                        onTap: () => vm.setToolMode(StudioToolMode.select),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Prominent Green "FINISH SKETCH" Button on Far Right
          const SizedBox(width: 8),
          _buildFinishSketchButton(),
        ],
      ),
    );
  }

  /// Fusion 360 Ribbon Group Container with bottom category title
  Widget _buildRibbonGroup({required String title, required List<Widget> children}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 9.0,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: Color(0xFF64748B),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 11, color: Color(0xFF64748B)),
          ],
        ),
      ],
    );
  }

  Widget _buildRibbonDivider() {
    return Container(
      height: 44,
      width: 1.0,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFCBD5E1),
    );
  }

  /// Standard Ribbon Action Button (Icon + Label)
  Widget _buildRibbonButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 44,
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0284C7).withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? const Color(0xFF0284C7) : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? const Color(0xFF0284C7) : const Color(0xFF334155),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? const Color(0xFF0284C7) : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Crisp Geometric Constraint Glyph Button (Fusion 360 Style)
  Widget _buildConstraintGlyphButton({
    required String symbol,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final isPickingThis = widget.viewModel.activeConstraintPickType != null;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 26,
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: isPickingThis ? const Color(0xFFF1F5F9) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF94A3B8), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  symbol,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Big Green "✓ FINISH SKETCH ▾" Button on the Far Right
  Widget _buildFinishSketchButton() {
    return InkWell(
      onTap: widget.onFinishSketch,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF16A34A), // Fusion 360 Green
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF16A34A).withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, size: 16, color: Color(0xFF16A34A)),
            ),
            SizedBox(width: 8),
            Text(
              'FINISH SKETCH',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}
