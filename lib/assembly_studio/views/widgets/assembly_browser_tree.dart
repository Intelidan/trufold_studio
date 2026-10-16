// Autodesk Fusion 360 Style Assembly Browser Tree Widget
// TruFold Assembly Studio - Phase 6 Browser Tree
// Modular MVVM Architecture (<600 lines)

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/theme/assembly_studio_theme.dart';

/// Autodesk Fusion 360-style hierarchical Browser Tree inspector.
/// Groups Origin, Construction Planes, Sketches, Bodies, and Joints/Welds.
class AssemblyBrowserTree extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;
  final double width;

  const AssemblyBrowserTree({super.key, required this.viewModel, this.width = 245.0});

  @override
  State<AssemblyBrowserTree> createState() => _AssemblyBrowserTreeState();
}

class _AssemblyBrowserTreeState extends State<AssemblyBrowserTree> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _collapsedFolderIds = {};
  String _filterQuery = '';

  AssemblyStudioTheme get theme => AssemblyStudioTheme(isLight: widget.viewModel.isLightBackground);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _filterQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleFolder(String folderId) {
    setState(() {
      if (_collapsedFolderIds.contains(folderId)) {
        _collapsedFolderIds.remove(folderId);
      } else {
        _collapsedFolderIds.add(folderId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final allSketches = <CADSketchPlane>[...vm.savedSketchPlanes];
        if (vm.activeSketchPlane != null && !allSketches.any((s) => s.id == vm.activeSketchPlane!.id)) {
          allSketches.add(vm.activeSketchPlane!);
        }
        for (final p in vm.allAvailablePlanes) {
          if (p.primitives.isNotEmpty && !allSketches.any((s) => s.id == p.id)) {
            allSketches.add(p);
          }
        }
        final constructionCount = vm.constructionPlanes.length;
        final bodiesCount = vm.doc.parts.length;
        final weldsCount = vm.doc.welds.length;

        return Container(
          width: widget.width,
          decoration: BoxDecoration(
            color: theme.panelBackground,
            border: Border(right: BorderSide(color: theme.panelBorder, width: 1.0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Bar
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: theme.panelHeaderBackground,
                  border: Border(bottom: BorderSide(color: theme.panelBorder, width: 1.0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_rounded, color: AssemblyStudioTheme.onshapeBlue, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Features (${allSketches.length + constructionCount + (vm.timelineItems.length)})',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: theme.textPrimary),
                      ),
                    ),
                    // Quick Action: Add Construction Plane
                    Tooltip(
                      message: 'Add Construction Plane',
                      child: InkWell(
                        onTap: () {
                          vm.addOffsetConstructionPlane(parentPlaneId: 'datum_xy', offsetMm: 25.0, name: 'Offset Plane ${vm.constructionPlanes.length + 1}');
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(3.0),
                          child: Icon(Icons.add_box_rounded, size: 14, color: Color(0xFFF59E0B)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Quick Action: Settings
                    Tooltip(
                      message: 'CAD & Viewport Settings',
                      child: InkWell(
                        onTap: vm.toggleCadSettingsDialog,
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(3.0),
                          child: Icon(Icons.settings_rounded, size: 14, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Search / Filter Field (Matches Onshape 'Filter by name or type')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.panelBackground,
                  border: Border(bottom: BorderSide(color: theme.panelBorder, width: 1.0)),
                ),
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: theme.inputBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.inputBorder, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 12, color: theme.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: TextStyle(fontSize: 10, color: theme.textPrimary),
                          cursorColor: AssemblyStudioTheme.onshapeBlue,
                          decoration: InputDecoration(
                            hintText: 'Filter by name or type',
                            hintStyle: TextStyle(fontSize: 9.5, color: theme.textMuted),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_filterQuery.isNotEmpty)
                        GestureDetector(
                          onTap: _searchCtrl.clear,
                          child: Icon(Icons.close_rounded, size: 11, color: theme.textTertiary),
                        ),
                    ],
                  ),
                ),
              ),

              // 3. Tree View: Features & Parts List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    // Folder 1: Default Geometry (Origin, Top, Front, Right)
                    _buildFolderHeader(
                      id: 'folder_default_geometry',
                      title: 'Default geometry',
                      icon: Icons.layers_outlined,
                      color: AssemblyStudioTheme.onshapeBlue,
                      countText: '4',
                      isVisible: vm.showDatumPlanes,
                      onToggleVisibility: vm.toggleDatumPlanesVisibility,
                    ),
                    if (!_collapsedFolderIds.contains('folder_default_geometry')) ...[
                      _buildOriginItem('Origin', Icons.adjust_rounded, null, vm),
                      _buildOriginItem('Top', Icons.crop_square_rounded, vm.datumPlaneXY, vm),
                      _buildOriginItem('Front', Icons.crop_square_rounded, vm.datumPlaneXZ, vm),
                      _buildOriginItem('Right', Icons.crop_square_rounded, vm.datumPlaneYZ, vm),
                    ],

                    // Folder 2: Construction Planes
                    _buildFolderHeader(
                      id: 'folder_construction',
                      title: 'Construction',
                      icon: Icons.layers_outlined,
                      color: const Color(0xFFF59E0B),
                      countText: '$constructionCount',
                      isVisible: vm.showConstructionPlanes,
                      onToggleVisibility: vm.toggleConstructionPlanesVisibility,
                    ),
                    if (!_collapsedFolderIds.contains('folder_construction')) ...[
                      if (vm.constructionPlanes.isEmpty)
                        _buildEmptyFolderHint('No construction planes created')
                      else
                        ...vm.constructionPlanes.map((plane) => _buildConstructionItem(plane, vm)),
                    ],

                    // Folder 3: Sketches
                    _buildFolderHeader(
                      id: 'folder_sketches',
                      title: 'Sketches',
                      icon: Icons.draw_rounded,
                      color: AssemblyStudioTheme.onshapeBlue,
                      countText: '${allSketches.length}',
                    ),
                    if (!_collapsedFolderIds.contains('folder_sketches')) ...[
                      if (allSketches.isEmpty)
                        _buildEmptyFolderHint('No active sketches (Press S or select plane)')
                      else
                        ...allSketches.map((plane) => _buildSketchItem(plane, vm)),
                    ],

                    // Folder 4: Parts (Matches Onshape 'Parts (N)')
                    _buildFolderHeader(
                      id: 'folder_bodies',
                      title: 'Parts',
                      icon: Icons.view_in_ar_rounded,
                      color: AssemblyStudioTheme.onshapeBlue,
                      countText: '$bodiesCount',
                    ),
                    if (!_collapsedFolderIds.contains('folder_bodies')) ...[
                      if (vm.doc.parts.isEmpty) _buildEmptyFolderHint('No bodies present') else ...vm.doc.parts.map((part) => _buildBodyItem(part, vm)),
                    ],

                    // Folder 5: Joints & Welds
                    _buildFolderHeader(
                      id: 'folder_welds',
                      title: 'Joints & Welds',
                      icon: Icons.flash_on_rounded,
                      color: const Color(0xFFA855F7),
                      countText: '$weldsCount',
                    ),
                    if (!_collapsedFolderIds.contains('folder_welds')) ...[
                      if (vm.doc.welds.isEmpty) _buildEmptyFolderHint('No welds present') else ...vm.doc.welds.map((weld) => _buildWeldItem(weld, vm)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderHeader({
    required String id,
    required String title,
    required IconData icon,
    required Color color,
    required String countText,
    bool isVisible = true,
    VoidCallback? onToggleVisibility,
  }) {
    final isCollapsed = _collapsedFolderIds.contains(id);

    return InkWell(
      onTap: () => _toggleFolder(id),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: theme.panelHeaderBackground.withValues(alpha: 0.6),
          border: Border(bottom: BorderSide(color: theme.panelBorder.withValues(alpha: 0.5), width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(isCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded, size: 14, color: theme.textTertiary),
            const SizedBox(width: 4),
            Icon(isCollapsed ? Icons.folder_rounded : Icons.folder_open_rounded, size: 13, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: theme.textPrimary),
              ),
            ),
            Text(
              countText,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.textTertiary),
            ),
            const SizedBox(width: 6),
            if (onToggleVisibility != null)
              GestureDetector(
                onTap: onToggleVisibility,
                child: Icon(
                  isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  size: 13,
                  color: isVisible ? const Color(0xFF38BDF8) : theme.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFolderHint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4, right: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: theme.textMuted),
      ),
    );
  }

  Widget _buildOriginItem(String name, IconData icon, CADSketchPlane? plane, AssemblyStudioViewModel vm) {
    if (_filterQuery.isNotEmpty && !name.toLowerCase().contains(_filterQuery)) return const SizedBox.shrink();
    final isPlaneActive = (plane != null && vm.activeSketchPlane?.id == plane.id && vm.isSketchMode);

    return InkWell(
      onTap: () {
        if (plane != null) {
          vm.selectPlaneForSketch(plane);
        }
      },
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 28, right: 8),
        color: isPlaneActive ? const Color(0xFF0284C7).withValues(alpha: 0.25) : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, size: 12, color: const Color(0xFF38BDF8)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name, style: TextStyle(fontSize: 9.5, color: isPlaneActive ? const Color(0xFF38BDF8) : theme.textSecondary)),
            ),
            if (plane != null)
              GestureDetector(
                onTap: () => vm.selectPlaneForSketch(plane),
                child: Tooltip(
                  message: 'Create 2D Sketch on $name',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(color: const Color(0xFF0284C7).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                    child: const Text(
                      'Sketch',
                      style: TextStyle(fontSize: 8, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConstructionItem(CADSketchPlane plane, AssemblyStudioViewModel vm) {
    if (_filterQuery.isNotEmpty && !plane.name.toLowerCase().contains(_filterQuery)) return const SizedBox.shrink();
    final isSelected = vm.activeSketchPlane?.id == plane.id;

    return InkWell(
      onTap: () {
        vm.selectPlaneForSketch(plane);
      },
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 28, right: 8),
        color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.2) : Colors.transparent,
        child: Row(
          children: [
            const Icon(Icons.layers_rounded, size: 12, color: Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                plane.name,
                style: TextStyle(fontSize: 9.5, color: isSelected ? const Color(0xFFF59E0B) : theme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => vm.togglePlaneVisibility(plane.id),
              child: Icon(
                plane.isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                size: 12,
                color: plane.isVisible ? const Color(0xFFF59E0B) : theme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSketchItem(CADSketchPlane plane, AssemblyStudioViewModel vm) {
    if (_filterQuery.isNotEmpty && !plane.name.toLowerCase().contains(_filterQuery)) return const SizedBox.shrink();
    final isSelected = vm.activeSketchPlane?.id == plane.id && vm.isSketchMode;
    final segments = AssemblySurfaceSketchEngine.compilePlaneSegments(plane);
    final validation = segments.isNotEmpty ? CADProfileValidator.validateProfile(segments) : null;
    final isClosed = validation?.isValidClosedLoop ?? false;

    return InkWell(
      onTap: () {
        if (isSelected) {
          vm.alignCameraToActivePlaneNormal();
        } else {
          vm.editSketch(plane);
        }
      },
      child: Container(
        height: 26,
        padding: const EdgeInsets.only(left: 28, right: 8),
        color: isSelected ? const Color(0xFFE0F2FE) : Colors.transparent,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/icons/onshape/tree_sketch.svg',
              width: 13,
              height: 13,
              colorFilter: ColorFilter.mode(isSelected ? AssemblyStudioTheme.onshapeBlue : theme.textSecondary, BlendMode.srcIn),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                plane.name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AssemblyStudioTheme.onshapeBlue : theme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (segments.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isClosed ? const Color(0x2210B981) : const Color(0x22F59E0B),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: isClosed ? const Color(0xFF10B981) : const Color(0xFFF59E0B), width: 0.6),
                ),
                child: Text(
                  isClosed ? 'Closed' : 'Open',
                  style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: isClosed ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                ),
              ),
            GestureDetector(
              onTap: () => vm.togglePlaneVisibility(plane.id),
              child: SvgPicture.asset(
                plane.isVisible ? 'assets/icons/onshape/eyeball_open.svg' : 'assets/icons/onshape/eyeball_closed.svg',
                width: 13,
                height: 13,
                colorFilter: ColorFilter.mode(plane.isVisible ? const Color(0xFF64748B) : const Color(0xFFCBD5E1), BlendMode.srcIn),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyItem(AssemblyPart part, AssemblyStudioViewModel vm) {
    if (_filterQuery.isNotEmpty && !part.name.toLowerCase().contains(_filterQuery)) return const SizedBox.shrink();
    final isSelected = vm.doc.selectedPartId == part.id;

    return InkWell(
      onTap: () => vm.selectPart(part.id),
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 28, right: 8),
        color: isSelected ? const Color(0xFF0284C7).withValues(alpha: 0.15) : Colors.transparent,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/icons/onshape/tree_part.svg',
              width: 12,
              height: 12,
              colorFilter: ColorFilter.mode(isSelected ? AssemblyStudioTheme.onshapeBlue : const Color(0xFF64748B), BlendMode.srcIn),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                part.name,
                style: TextStyle(fontSize: 9.5, color: isSelected ? AssemblyStudioTheme.onshapeBlue : theme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => vm.togglePartVisibility(part.id),
              child: SvgPicture.asset(
                part.isVisible ? 'assets/icons/onshape/eyeball_open.svg' : 'assets/icons/onshape/eyeball_closed.svg',
                width: 13,
                height: 13,
                colorFilter: ColorFilter.mode(part.isVisible ? theme.textSecondary : theme.textMuted, BlendMode.srcIn),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeldItem(dynamic weld, AssemblyStudioViewModel vm) {
    final desc = weld.jointDescription ?? 'Fillet Weld (${weld.weldLengthMm.toStringAsFixed(0)}mm)';
    if (_filterQuery.isNotEmpty && !desc.toLowerCase().contains(_filterQuery) && !weld.id.toLowerCase().contains(_filterQuery)) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 24,
      padding: const EdgeInsets.only(left: 28, right: 8),
      child: Row(
        children: [
          const Icon(Icons.flash_on_rounded, size: 12, color: Color(0xFFA855F7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              weld.jointDescription ?? 'Fillet Weld (${weld.weldLengthMm.toStringAsFixed(0)}mm)',
              style: TextStyle(fontSize: 9.5, color: theme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
