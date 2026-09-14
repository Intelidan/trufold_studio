// =============================================================================
// fusion_browser_panel.dart
//
// Autodesk Fusion 360-style Left BROWSER Tree Panel for TruFold Studio.
// Matches Fusion 360's exact hierarchical organization:
// - Header: ◄ BROWSER ⚙
// - Part Root: ● (Unsaved) / itemName with eye visibility toggle
// - Document Settings (Units: mm, Material, Thickness)
// - Named Views (Top, Front, Right, Home)
// - Origin (X Axis, Y Axis, Z Axis, XY Plane)
// - Sketches (Sketch1 with active pencil / lock status)
// - Sheet Metal Features (Faces, Bends, Punches, Patterns, Laser Cuts, Press Brake CAM)
// =============================================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/dsf_document.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class FusionBrowserPanel extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback? onClose;
  final VoidCallback? onEditThickness;
  final VoidCallback? onEditMaterial;
  final double width;
  final ValueChanged<double>? onWidthChanged;

  const FusionBrowserPanel({
    super.key,
    required this.viewModel,
    this.onClose,
    this.onEditThickness,
    this.onEditMaterial,
    this.width = 260.0,
    this.onWidthChanged,
  });

  @override
  State<FusionBrowserPanel> createState() => _FusionBrowserPanelState();
}

class _FusionBrowserPanelState extends State<FusionBrowserPanel> {
  bool _expandDocSettings = false;
  bool _expandNamedViews = false;
  bool _expandOrigin = false;
  bool _expandSketches = true;
  bool _expandFeatures = true;
  bool _expandFaces = false;
  bool _expandBends = true;
  bool _expandPunches = true;
  bool _expandPatterns = true;
  bool _expandCuts = false;

  bool _sketch1Visible = true;
  bool _originVisible = true;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final doc = widget.viewModel.document;

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: widget.width,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78), // Translucent Fusion 360 glass HUD
                border: const Border(right: BorderSide(color: Color(0xFFCBD5E1), width: 1.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(2, 0),
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
                                isSelected: face.id == widget.viewModel.selectedFaceId,
                                isVisible: face.isVisible,
                                onToggleEye: () => widget.viewModel.toggleFaceVisibility(face.id),
                                onTap: () => widget.viewModel.selectFace(face.id),
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
                                isSelected: bend.id == widget.viewModel.selectedBendId,
                                isVisible: bend.isVisible,
                                onToggleEye: () => widget.viewModel.toggleBendVisibility(bend.id),
                                onTap: () => widget.viewModel.selectBend(bend.id),
                              ),
                          ],
                        ),

                        // Punches & Perforations Group
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
                                isSelected: punch.id == widget.viewModel.selectedPunchId,
                                isVisible: punch.isVisible,
                                onToggleEye: () => widget.viewModel.togglePunchVisibility(punch.id),
                                onTap: () => widget.viewModel.selectPunch(punch.id),
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
                                  isSelected: pat.id == widget.viewModel.selectedPatternId,
                                  isVisible: pat.isVisible,
                                  onToggleEye: () => widget.viewModel.togglePatternVisibility(pat.id),
                                  onTap: () => widget.viewModel.selectPattern(pat.id),
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
                                  isSelected: cut.id == widget.viewModel.selectedCutId,
                                  isVisible: cut.isVisible,
                                  onToggleEye: () => widget.viewModel.toggleCutVisibility(cut.id),
                                  onTap: () => widget.viewModel.selectCut(cut.id),
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

  /// 1. Header: ◄ BROWSER ⚙
  Widget _buildBrowserHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.45),
        border: const Border(bottom: BorderSide(color: Color(0x33CBD5E1), width: 1.0)),
      ),
      child: Row(
        children: [
          if (widget.onClose != null)
            InkWell(
              onTap: widget.onClose,
              child: const Icon(Icons.arrow_left, size: 18, color: Color(0xFF475569)),
            ),
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
          const Icon(Icons.settings_outlined, size: 14, color: Color(0xFF64748B)),
        ],
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

  /// Feature Sub-Group (Faces, Bends, Punches)
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

  /// Leaf Node (Individual feature / item with eye toggle)
  Widget _buildLeafNode({
    required String title,
    required IconData icon,
    Color? iconColor,
    bool isSelected = false,
    bool isVisible = true,
    bool hasEye = true,
    VoidCallback? onToggleEye,
    VoidCallback? onTap,
    Widget? trailingBadge,
  }) {
    return InkWell(
      onTap: onTap,
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
          ],
        ),
      ),
    );
  }
}
