// =============================================================================
// studio_browser_panel.dart
//
// Left BROWSER Tree Panel for truFold Studio.
// Hierarchical organization:
// - Header: ◄ BROWSER ⚙
// - Part Root: ● (Unsaved) / itemName with eye visibility toggle
// - Document Settings (Units: mm, Material, Thickness)
// - Named Views (Top, Front, Right, Home)
// - Origin (X Axis, Y Axis, Z Axis, XY Plane)
// - Sketches (Sketch1 with active pencil / lock status)
// - Sheet Metal Features (Faces, Bends, Punches, Arcs, Patterns, Laser Cuts, Press Brake CAM)
// =============================================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/dsf_document.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../cms_perforation_dialog.dart';
import '../layer_manager_sheet.dart';
import '../press_brake_machine_dialog.dart';
import '../punch_tooling_selector_dialog.dart';
import '../studio_export_dialog.dart';
import '../studio_import_dialog.dart';

class StudioBrowserPanel extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback? onClose;
  final VoidCallback? onEditThickness;
  final VoidCallback? onEditMaterial;
  final double width;
  final ValueChanged<double>? onWidthChanged;
  final ValueChanged<Offset>? onPositionDelta;

  const StudioBrowserPanel({
    super.key,
    required this.viewModel,
    this.onClose,
    this.onEditThickness,
    this.onEditMaterial,
    this.width = 260.0,
    this.onWidthChanged,
    this.onPositionDelta,
  });

  @override
  State<StudioBrowserPanel> createState() => _StudioBrowserPanelState();
}

class _StudioBrowserPanelState extends State<StudioBrowserPanel> {
  bool _expandDocSettings = false;
  bool _expandNamedViews = false;
  bool _expandOrigin = false;
  bool _expandSketches = true;
  bool _expandFeatures = true;
  bool _expandFaces = false;
  bool _expandBends = true;
  bool _expandPunches = true;
  bool _expandArcs = true;
  bool _expandPatterns = true;
  bool _expandCuts = false;

  bool _sketch1Visible = true;
  bool _originVisible = true;
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final doc = widget.viewModel.document;

        if (_isCollapsed) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC).withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.09),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Expand Browser Panel',
                      child: InkWell(
                        onTap: () => setState(() => _isCollapsed = false),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5))),
                          ),
                          child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF0284C7)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildMiniIcon(
                      tooltip: 'Machine Settings',
                      icon: Icons.precision_manufacturing_outlined,
                      onTap: () => PressBrakeMachineDialog.show(context, widget.viewModel),
                    ),
                    _buildMiniIcon(
                      tooltip: 'Punch Tooling Catalog',
                      icon: Icons.hardware_outlined,
                      onTap: () => PunchToolingSelectorDialog.show(context, widget.viewModel),
                    ),
                    _buildMiniIcon(
                      tooltip: 'Drawing Layers',
                      icon: Icons.layers_outlined,
                      onTap: () => LayerManagerSheet.show(context, widget.viewModel),
                    ),
                    _buildMiniIcon(
                      tooltip: 'Perforations',
                      icon: Icons.grain,
                      onTap: () => CmsPerforationDialog.show(context, widget.viewModel),
                    ),
                    const SizedBox(height: 12),
                    RotatedBox(
                      quarterTurns: 3,
                      child: InkWell(
                        onTap: () => setState(() => _isCollapsed = false),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(
                            'BROWSER',
                            style: TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: widget.width,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC).withValues(alpha: 0.42), // Translucent foggy glass HUD
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.09),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Browser Header: ◄ BROWSER ⚙
                      _buildBrowserHeader(),

                      // Quick Studio Tools Strip (Layers, Perforations, Export, Import)
                      _buildQuickToolsStrip(),

                      // 2. Tree Body
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: [
                            // Root Node: ● (Unsaved) / itemName
                            _buildRootItem(doc),

                            // Document Settings
                            _buildExpandableNode(
                              title: 'Document Settings',
                              icon: Icons.folder_outlined,
                              isExpanded: _expandDocSettings,
                              onToggle: () => setState(() => _expandDocSettings = !_expandDocSettings),
                              children: [
                                _buildLeafNode(
                                  title: 'Units: mm',
                                  icon: Icons.straighten,
                                  hasEye: false,
                                ),
                                _buildLeafNode(
                                  title: 'Material: ${doc.material.materialType.shortCode}',
                                  icon: Icons.category_outlined,
                                  hasEye: false,
                                  onTap: widget.onEditMaterial,
                                ),
                                _buildLeafNode(
                                  title: 'Thickness: ${doc.material.thicknessMm} mm',
                                  icon: Icons.line_weight,
                                  hasEye: false,
                                  onTap: widget.onEditThickness,
                                ),
                              ],
                            ),

                            // Named Views
                            _buildExpandableNode(
                              title: 'Named Views',
                              icon: Icons.folder_outlined,
                              isExpanded: _expandNamedViews,
                              onToggle: () => setState(() => _expandNamedViews = !_expandNamedViews),
                              children: [
                                _buildLeafNode(
                                  title: 'Top',
                                  icon: Icons.videocam_outlined,
                                  onTap: widget.viewModel.reset2DCanvas,
                                ),
                                _buildLeafNode(
                                  title: 'Front',
                                  icon: Icons.videocam_outlined,
                                  onTap: widget.viewModel.reset2DCanvas,
                                ),
                                _buildLeafNode(
                                  title: 'Right',
                                  icon: Icons.videocam_outlined,
                                  onTap: null,
                                ),
                                _buildLeafNode(
                                  title: 'Home (Isometric)',
                                  icon: Icons.home_outlined,
                                  onTap: widget.viewModel.reset2DCanvas,
                                ),
                              ],
                            ),

                            // Origin
                            _buildExpandableNode(
                              title: 'Origin',
                              icon: Icons.folder_outlined,
                              isExpanded: _expandOrigin,
                              isVisible: _originVisible,
                              onToggleEye: () => setState(() => _originVisible = !_originVisible),
                              onToggle: () => setState(() => _expandOrigin = !_expandOrigin),
                              children: [
                                _buildLeafNode(title: 'X Axis', icon: Icons.east, iconColor: const Color(0xFFEF4444)),
                                _buildLeafNode(title: 'Y Axis', icon: Icons.north, iconColor: const Color(0xFF22C55E)),
                                _buildLeafNode(title: 'Z Axis', icon: Icons.north_east, iconColor: const Color(0xFF3B82F6)),
                                _buildLeafNode(title: 'XY Plane', icon: Icons.layers_outlined),
                              ],
                            ),

                            // Sketches
                            _buildExpandableNode(
                              title: 'Sketches',
                              icon: Icons.folder_outlined,
                              isExpanded: _expandSketches,
                              onToggle: () => setState(() => _expandSketches = !_expandSketches),
                              children: [
                                _buildLeafNode(
                                  title: 'Sketch1',
                                  icon: Icons.edit_note,
                                  iconColor: const Color(0xFF0284C7),
                                  isVisible: _sketch1Visible,
                                  onToggleEye: () => setState(() => _sketch1Visible = !_sketch1Visible),
                                  trailingBadge: widget.viewModel.activeConstraintDefinitions.isNotEmpty
                                      ? const Icon(Icons.lock, size: 12, color: Color(0xFF64748B))
                                      : const Icon(Icons.edit, size: 12, color: Color(0xFF0284C7)),
                                  onTap: () => widget.viewModel.setToolMode(StudioToolMode.select),
                                ),
                              ],
                            ),

                            // Sheet Metal Features
                            _buildExpandableNode(
                              title: 'Sheet Metal Bodies',
                              icon: Icons.layers,
                              isExpanded: _expandFeatures,
                              onToggle: () => setState(() => _expandFeatures = !_expandFeatures),
                              children: [
                                // Faces Group
                                _buildFeatureSubGroup(
                                  title: 'Faces (${doc.faces.length})',
                                  icon: Icons.crop_free,
                                  isExpanded: _expandFaces,
                                  onToggle: () => setState(() => _expandFaces = !_expandFaces),
                                  items: [
                                    for (final face in doc.faces)
                                      _buildLeafNode(
                                        title: '${face.label} [${face.id}]',
                                        icon: Icons.crop_portrait,
                                        isSelected: face.id == widget.viewModel.selectedFaceId ||
                                            widget.viewModel.selectedEntityIds.contains(face.id),
                                        isVisible: face.isVisible,
                                        onToggleEye: () => widget.viewModel.toggleFaceVisibility(face.id),
                                        onTap: () => widget.viewModel.selectFace(
                                          face.id,
                                          multiSelect: HardwareKeyboard.instance.isShiftPressed,
                                        ),
                                        onDoubleTap: () {
                                          widget.viewModel.selectFace(face.id);
                                          widget.viewModel.setPropertyInspectorOpen(true);
                                        },
                                      ),
                                  ],
                                ),

                                // Bends Group
                                _buildFeatureSubGroup(
                                  title: 'Bends (${doc.bends.length})',
                                  icon: Icons.alt_route,
                                  isExpanded: _expandBends,
                                  onToggle: () => setState(() => _expandBends = !_expandBends),
                                  items: [
                                    for (final bend in doc.bends)
                                      _buildLeafNode(
                                        title: '${bend.id} (${bend.angleDeg.round()}° R${bend.radiusMm})',
                                        icon: Icons.turn_right,
                                        isSelected: bend.id == widget.viewModel.selectedBendId ||
                                            widget.viewModel.selectedEntityIds.contains(bend.id),
                                        isVisible: bend.isVisible,
                                        onToggleEye: () => widget.viewModel.toggleBendVisibility(bend.id),
                                        onTap: () => widget.viewModel.selectBend(
                                          bend.id,
                                          multiSelect: HardwareKeyboard.instance.isShiftPressed,
                                        ),
                                        onDoubleTap: () {
                                          widget.viewModel.selectBend(bend.id);
                                          widget.viewModel.setPropertyInspectorOpen(true);
                                        },
                                        onDelete: () => widget.viewModel.deleteBendLine(bend.id),
                                      ),
                                  ],
                                ),

                                // Punches & Holes Group
                                _buildFeatureSubGroup(
                                  title: 'Punches (${doc.punches.length})',
                                  icon: Icons.radio_button_checked,
                                  isExpanded: _expandPunches,
                                  onToggle: () => setState(() => _expandPunches = !_expandPunches),
                                  items: [
                                    for (final punch in doc.punches)
                                      _buildLeafNode(
                                        title: '${punch.type.name.toUpperCase()} (${punch.center.x.round()}, ${punch.center.y.round()})',
                                        icon: Icons.adjust,
                                        isSelected: punch.id == widget.viewModel.selectedPunchId ||
                                            widget.viewModel.selectedEntityIds.contains(punch.id),
                                        isVisible: punch.isVisible,
                                        onToggleEye: () => widget.viewModel.togglePunchVisibility(punch.id),
                                        onTap: () => widget.viewModel.selectPunch(
                                          punch.id,
                                          multiSelect: HardwareKeyboard.instance.isShiftPressed,
                                        ),
                                        onDoubleTap: () {
                                          widget.viewModel.selectPunch(punch.id);
                                          widget.viewModel.setPropertyInspectorOpen(true);
                                        },
                                        onDelete: () => widget.viewModel.deletePunch(punch.id),
                                      ),
                                  ],
                                ),

                                // First-Class Arcs Group
                                if (doc.arcs.isNotEmpty)
                                  _buildFeatureSubGroup(
                                    title: 'Arcs (${doc.arcs.length})',
                                    icon: Icons.pie_chart_outline,
                                    isExpanded: _expandArcs,
                                    onToggle: () => setState(() => _expandArcs = !_expandArcs),
                                    items: [
                                      for (final arc in doc.arcs)
                                        _buildLeafNode(
                                          title: '${arc.id} (R${arc.radius.toStringAsFixed(1)}, L${arc.arcLength.toStringAsFixed(1)})',
                                          icon: Icons.all_inclusive,
                                          isSelected: arc.id == widget.viewModel.selectedArcId ||
                                              widget.viewModel.selectedEntityIds.contains(arc.id),
                                          isVisible: true,
                                          onTap: () {
                                            if (HardwareKeyboard.instance.isShiftPressed) {
                                              widget.viewModel.toggleEntitySelection(arc.id);
                                            } else {
                                              widget.viewModel.setSelectedArc(arc.id);
                                              widget.viewModel.setPropertyInspectorOpen(true);
                                            }
                                          },
                                          onDoubleTap: () {
                                            widget.viewModel.setSelectedArc(arc.id);
                                            widget.viewModel.setPropertyInspectorOpen(true);
                                          },
                                          onDelete: () => widget.viewModel.deleteArc(arc.id),
                                        ),
                                    ],
                                  ),

                                // Perforation Patterns
                                if (doc.perforationPatterns.isNotEmpty)
                                  _buildFeatureSubGroup(
                                    title: 'Patterns (${doc.perforationPatterns.length})',
                                    icon: Icons.grain,
                                    isExpanded: _expandPatterns,
                                    onToggle: () => setState(() => _expandPatterns = !_expandPatterns),
                                    items: [
                                      for (final pat in doc.perforationPatterns)
                                        _buildLeafNode(
                                          title: '${pat.id} (${pat.holeType.name})',
                                          icon: Icons.apps,
                                          isSelected: pat.id == widget.viewModel.selectedPatternId ||
                                              widget.viewModel.selectedEntityIds.contains(pat.id),
                                          isVisible: pat.isVisible,
                                          onToggleEye: () => widget.viewModel.togglePatternVisibility(pat.id),
                                          onTap: () => widget.viewModel.selectPattern(
                                            pat.id,
                                            null,
                                            HardwareKeyboard.instance.isShiftPressed,
                                          ),
                                          onDoubleTap: () {
                                            widget.viewModel.selectPattern(pat.id);
                                            widget.viewModel.setPropertyInspectorOpen(true);
                                          },
                                          onDelete: () => widget.viewModel.deletePattern(pat.id),
                                        ),
                                    ],
                                  ),

                                // Laser Cut Slits
                                if (doc.cutLines.isNotEmpty)
                                  _buildFeatureSubGroup(
                                    title: 'Cuts (${doc.cutLines.length})',
                                    icon: Icons.content_cut,
                                    isExpanded: _expandCuts,
                                    onToggle: () => setState(() => _expandCuts = !_expandCuts),
                                    items: [
                                      for (final cut in doc.cutLines)
                                        _buildLeafNode(
                                          title: 'Cut ${cut.id}',
                                          icon: Icons.timeline,
                                          isSelected: cut.id == widget.viewModel.selectedCutId ||
                                              widget.viewModel.selectedEntityIds.contains(cut.id),
                                          isVisible: cut.isVisible,
                                          onToggleEye: () => widget.viewModel.toggleCutVisibility(cut.id),
                                          onTap: () => widget.viewModel.selectCut(
                                            cut.id,
                                            multiSelect: HardwareKeyboard.instance.isShiftPressed,
                                          ),
                                          onDoubleTap: () {
                                            widget.viewModel.selectCut(cut.id);
                                            widget.viewModel.setPropertyInspectorOpen(true);
                                          },
                                          onDelete: () => widget.viewModel.deleteCut(cut.id),
                                        ),
                                    ],
                                  ),

                                // Construction Lines
                                if (widget.viewModel.customReferenceGeometries.isNotEmpty)
                                  _buildFeatureSubGroup(
                                    title: 'Construction (${widget.viewModel.customReferenceGeometries.length})',
                                    icon: Icons.architecture,
                                    isExpanded: true,
                                    onToggle: () {},
                                    items: [
                                      for (final ref in widget.viewModel.customReferenceGeometries)
                                        _buildLeafNode(
                                          title: ref.name,
                                          icon: Icons.border_style,
                                          iconColor: const Color(0xFF00BCD4),
                                          isVisible: ref.isVisible,
                                          onDelete: () => widget.viewModel.removeReferenceGeometry(ref.id),
                                        ),
                                    ],
                                  ),

                                // Press Brake & CAM Tooling Group
                                _buildFeatureSubGroup(
                                  title: 'Press Brake & CAM',
                                  icon: Icons.precision_manufacturing,
                                  isExpanded: true,
                                  onToggle: () {},
                                  items: [
                                    _buildLeafNode(
                                      title: 'Machine: ${widget.viewModel.selectedMachine.name}',
                                      icon: Icons.settings_suggest_outlined,
                                      hasEye: false,
                                      onTap: () => PressBrakeMachineDialog.show(context, widget.viewModel),
                                    ),
                                    _buildLeafNode(
                                      title: 'Tooling: ${widget.viewModel.selectedMachine.punchType.name.toUpperCase()}',
                                      icon: Icons.hardware_outlined,
                                      hasEye: false,
                                      onTap: () => PunchToolingSelectorDialog.show(context, widget.viewModel),
                                    ),
                                    _buildLeafNode(
                                      title: 'V-Die: ${widget.viewModel.selectedMachine.vDieWidthMm.toStringAsFixed(1)} mm',
                                      icon: Icons.view_column_outlined,
                                      hasEye: false,
                                      onTap: () => PressBrakeMachineDialog.show(context, widget.viewModel),
                                    ),
                                    _buildLeafNode(
                                      title: 'Auto-Sequence CAM (${widget.viewModel.bendSequence.length} steps)',
                                      icon: Icons.auto_fix_high,
                                      iconColor: const Color(0xFF0284C7),
                                      hasEye: false,
                                      onTap: () {
                                        widget.viewModel.autoGenerateBendSequence();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Generated automated bend sequence with ${widget.viewModel.bendSequence.length} steps.'),
                                            backgroundColor: const Color(0xFF0D9488),
                                            duration: const Duration(seconds: 3),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Draggable right-edge resize handle
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 10,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (details) {
                          widget.onWidthChanged?.call(details.delta.dx);
                        },
                        child: Container(
                          width: 10,
                          color: Colors.transparent,
                          alignment: Alignment.center,
                          child: Container(
                            width: 2.5,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF94A3B8).withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 1. Header: ◄ BROWSER ⚙ (Draggable)
  Widget _buildBrowserHeader() {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => widget.onPositionDelta?.call(details.delta),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.45), width: 0.8)),
          ),
          child: Row(
            children: [
              const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              const Text(
                'BROWSER',
                style: TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Tooltip(
                message: 'Collapse Browser',
                child: InkWell(
                  onTap: () => setState(() => _isCollapsed = true),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.chevron_left, size: 18, color: Color(0xFF64748B)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (widget.onClose != null)
                Tooltip(
                  message: 'Close Browser',
                  child: InkWell(
                    onTap: widget.onClose,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Quick Studio Tools Strip (Layers, Perforations, Export, Import)
  Widget _buildQuickToolsStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.30), width: 0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildQuickActionBtn(
            tooltip: 'Machine & Press Brake Settings',
            icon: Icons.precision_manufacturing_outlined,
            onTap: () => PressBrakeMachineDialog.show(context, widget.viewModel),
          ),
          _buildQuickActionBtn(
            tooltip: 'Punch Tooling Catalog',
            icon: Icons.hardware_outlined,
            onTap: () => PunchToolingSelectorDialog.show(context, widget.viewModel),
          ),
          _buildQuickActionBtn(
            tooltip: 'Drawing Layers',
            icon: Icons.layers_outlined,
            onTap: () => LayerManagerSheet.show(context, widget.viewModel),
          ),
          _buildQuickActionBtn(
            tooltip: 'Perforations & Pattern Generator',
            icon: Icons.grain,
            onTap: () => CmsPerforationDialog.show(context, widget.viewModel),
          ),
          _buildQuickActionBtn(
            tooltip: 'Import CAD File',
            icon: Icons.file_download_outlined,
            onTap: () => StudioImportDialog.show(context, widget.viewModel),
          ),
          _buildQuickActionBtn(
            tooltip: 'Export CAD / CAM',
            icon: Icons.file_upload_outlined,
            onTap: () => StudioExportDialog.show(context, widget.viewModel),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniIcon({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Icon(icon, size: 17, color: const Color(0xFF475569)),
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(3.0),
          child: Icon(icon, size: 15, color: const Color(0xFF475569)),
        ),
      ),
    );
  }

  /// Root Document Node: ● (Unsaved) / itemName
  Widget _buildRootItem(DsfDocument doc) {
    final title = doc.itemName.isNotEmpty ? doc.itemName : '(Unsaved)';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.radio_button_checked, size: 13, color: Color(0xFF0284C7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Icon(Icons.visibility_outlined, size: 14, color: Color(0xFF64748B)),
        ],
      ),
    );
  }

  /// Generic Expandable Folder/Node
  Widget _buildExpandableNode({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    bool isVisible = true,
    VoidCallback? onToggleEye,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: 16,
                  color: const Color(0xFF64748B),
                ),
                const SizedBox(width: 2),
                Icon(icon, size: 14, color: const Color(0xFF475569)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onToggleEye != null)
                  InkWell(
                    onTap: onToggleEye,
                    child: Icon(
                      isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 13,
                      color: isVisible ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
      ],
    );
  }

  /// Feature Sub-Group (Faces, Bends, Punches, Arcs)
  Widget _buildFeatureSubGroup({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: 14,
                  color: const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 2),
                Icon(icon, size: 13, color: const Color(0xFF64748B)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: items,
            ),
          ),
      ],
    );
  }

  /// Leaf Node (Individual feature / item with eye toggle & delete icon)
  Widget _buildLeafNode({
    required String title,
    required IconData icon,
    Color? iconColor,
    bool isSelected = false,
    bool isVisible = true,
    bool hasEye = true,
    VoidCallback? onToggleEye,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    VoidCallback? onDelete,
    Widget? trailingBadge,
  }) {
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7).withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: iconColor ?? (isSelected ? const Color(0xFF0284C7) : const Color(0xFF64748B))),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            ?trailingBadge,
            if (hasEye) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onToggleEye,
                child: Icon(
                  isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 13,
                  color: isVisible ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                ),
              ),
            ],
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(3),
                child: const Tooltip(
                  message: 'Delete',
                  child: Padding(
                    padding: EdgeInsets.all(1.0),
                    child: Icon(
                      Icons.delete_outline,
                      size: 13,
                      color: Color(0xFFEF4444),
                    ),
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
