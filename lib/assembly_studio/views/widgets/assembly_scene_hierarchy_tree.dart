import 'package:flutter/material.dart';
import '../../models/assembly_part.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';
import '../theme/assembly_studio_theme.dart';

/// Dark GameStudio-style Scene Hierarchy / Outliner Tree.
/// Organizes connected and welded parts under unified parent assembly tree nodes,
/// using compact 10px–11px typography to maximize 3D viewport canvas space.
class AssemblySceneHierarchyTree extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;
  final double width;

  const AssemblySceneHierarchyTree({
    super.key,
    required this.viewModel,
    this.width = 245.0,
  });

  @override
  State<AssemblySceneHierarchyTree> createState() => _AssemblySceneHierarchyTreeState();
}

class _AssemblySceneHierarchyTreeState extends State<AssemblySceneHierarchyTree> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _collapsedGroupIds = {};
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

  void _toggleGroupCollapse(String groupId) {
    setState(() {
      if (_collapsedGroupIds.contains(groupId)) {
        _collapsedGroupIds.remove(groupId);
      } else {
        _collapsedGroupIds.add(groupId);
      }
    });
  }

  void _expandAll() {
    setState(() {
      _collapsedGroupIds.clear();
    });
  }

  void _collapseAll(List<AssemblyGroupNode> groups) {
    setState(() {
      _collapsedGroupIds.addAll(groups.map((g) => g.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final groups = vm.getAssemblyHierarchyGroups();
    final totalParts = vm.doc.parts.length;
    final totalWelds = vm.doc.welds.length;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: theme.panelBackground, // Dynamic Light / Dark Panel Background
        border: Border(
          right: BorderSide(color: theme.panelBorder, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Panel Header (Dense GameStudio Style)
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: theme.panelHeaderBackground,
              border: Border(bottom: BorderSide(color: theme.panelBorder, width: 1.0)),
            ),
            child: Row(
              children: [
                Icon(Icons.account_tree_rounded, color: theme.accentSky, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'SCENE OUTLINER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: theme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // Counter badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: theme.accentSky.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.accentSky.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Text(
                    '$totalParts pts • $totalWelds wlds',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: theme.accentSky,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Filter / Search Bar & Expand/Collapse Controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.panelBackground,
              border: Border(bottom: BorderSide(color: theme.panelBorder, width: 1.0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: theme.inputBackground,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: theme.inputBorder, width: 0.8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 12, color: theme.textTertiary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: TextStyle(fontSize: 10, color: theme.textPrimary),
                            cursorColor: theme.accentSky,
                            decoration: InputDecoration(
                              hintText: 'Filter hierarchy...',
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
                const SizedBox(width: 6),
                // Expand All
                Tooltip(
                  message: 'Expand all groups',
                  child: InkWell(
                    onTap: _expandAll,
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: theme.cardBackground,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: theme.cardBorder, width: 0.8),
                      ),
                      child: Icon(Icons.unfold_more_rounded, size: 12, color: theme.textTertiary),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Collapse All
                Tooltip(
                  message: 'Collapse all groups',
                  child: InkWell(
                    onTap: () => _collapseAll(groups),
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: theme.cardBackground,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: theme.cardBorder, width: 0.8),
                      ),
                      child: Icon(Icons.unfold_less_rounded, size: 12, color: theme.textTertiary),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Tree Hierarchy List (Single Unified Tree)
          Expanded(
            child: totalParts == 0
                ? _buildEmptyTree()
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      // Root Scene Node
                      _buildRootSceneNode(vm, groups),

                      // Tree Groups
                      ...groups.map((group) => _buildGroupTree(group, vm)),
                    ],
                  ),
          ),

          // 4. Bottom Quick Stats & Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.panelHeaderBackground,
              border: Border(top: BorderSide(color: theme.panelBorder, width: 1.0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => vm.setToolMode(SketchUpToolMode.weld),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.hardware_rounded, size: 11, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Manual Weld Torch (W)',
                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: const Color(0xFF38BDF8)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Clear entire assembly',
                  child: InkWell(
                    onTap: () {
                      _showClearConfirm(context, vm);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.delete_sweep_rounded, size: 13, color: theme.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTree() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_clear_rounded, size: 28, color: Color(0xFF475569)),
            const SizedBox(height: 8),
            const Text(
              'No Parts in Assembly',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Drag parts from the Asset Shelf or click a demo template below.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: widget.viewModel.loadStandardLadderDemo,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                side: const BorderSide(color: Color(0xFF0284C7), width: 0.8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text('Load Demo Ladder', style: TextStyle(fontSize: 9.5, color: Color(0xFF38BDF8))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRootSceneNode(AssemblyStudioViewModel vm, List<AssemblyGroupNode> groups) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.blur_on_rounded, size: 12, color: Color(0xFF38BDF8)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Assembly: ${vm.doc.title}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE2E8F0),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF272730),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${groups.length} Sets',
              style: const TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTree(AssemblyGroupNode group, AssemblyStudioViewModel vm) {
    // Filter parts if search query is active
    final filteredParts = _filterQuery.isEmpty
        ? group.parts
        : group.parts.where((p) => p.name.toLowerCase().contains(_filterQuery)).toList();

    if (_filterQuery.isNotEmpty && filteredParts.isEmpty) {
      return const SizedBox.shrink();
    }

    final isCollapsed = _collapsedGroupIds.contains(group.id);
    final isGroupSelected = group.parts.every((p) => vm.selectedPartIds.contains(p.id)) && group.parts.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Parent Tree Node Header
          InkWell(
            onTap: () => _toggleGroupCollapse(group.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isGroupSelected
                    ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                    : (group.isConnectedAssembly ? theme.cardHoverBackground : theme.cardBackground),
                border: Border(
                  left: BorderSide(
                    color: group.isConnectedAssembly ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                    width: 2.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Collapse / Expand arrow
                  Icon(
                    isCollapsed ? Icons.arrow_right_rounded : Icons.arrow_drop_down_rounded,
                    size: 14,
                    color: theme.textTertiary,
                  ),
                  const SizedBox(width: 3),
                  // Group Icon
                  Icon(
                    group.isConnectedAssembly ? Icons.link_rounded : Icons.folder_open_rounded,
                    size: 12,
                    color: group.isConnectedAssembly ? theme.accentSky : theme.textTertiary,
                  ),
                  const SizedBox(width: 5),
                  // Group Name
                  Expanded(
                    child: Text(
                      group.name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Multi-select entire group
                  Tooltip(
                    message: 'Select entire assembly group',
                    child: InkWell(
                      onTap: () {
                        vm.selectPartGroup(group.parts.map((p) => p.id).toList());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: theme.panelBackground,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Icon(Icons.select_all_rounded, size: 10, color: theme.accentSky),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Part count pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.panelBackground,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${group.parts.length}',
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: theme.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Indented Children (Parts and Welds)
          if (!isCollapsed) ...[
            // Children Parts
            ...filteredParts.map((part) => _buildPartTreeNode(part, vm, group.isConnectedAssembly)),

            // Children Welds (if connected assembly)
            if (group.isConnectedAssembly && group.welds.isNotEmpty && _filterQuery.isEmpty)
              ...group.welds.map((weld) => _buildWeldTreeNode(weld, vm)),
          ],
        ],
      ),
    );
  }

  Widget _buildPartTreeNode(AssemblyPart part, AssemblyStudioViewModel vm, bool isUnderConnectedGroup) {
    final isSelected = vm.selectedPartIds.contains(part.id);
    final isPrimarySelected = vm.selectedPart?.id == part.id;
    final isVisible = part.isVisible;

    // Part accent color
    Color typeColor;
    switch (part.type) {
      case AssemblyPartType.straightRail:
      case AssemblyPartType.bentRail:
      case AssemblyPartType.walkThroughStile:
      case AssemblyPartType.boxTubeStile:
        typeColor = const Color(0xFF38BDF8); // Sky blue
        break;
      case AssemblyPartType.rung:
      case AssemblyPartType.diamondGripRung:
      case AssemblyPartType.wideStepTread:
        typeColor = const Color(0xFF34D399); // Green
        break;
      case AssemblyPartType.cableTrayStraight:
      case AssemblyPartType.cableTrayBend90:
      case AssemblyPartType.cableTrayBend45:
      case AssemblyPartType.cableTrayInsideRiser:
      case AssemblyPartType.cableTrayOutsideRiser:
      case AssemblyPartType.cableTrayTee:
      case AssemblyPartType.cableTrayCross:
      case AssemblyPartType.cableTrayReducer:
      case AssemblyPartType.cableTrayCoupler:
        typeColor = const Color(0xFF38BDF8); // Tray Cyan
        break;
      case AssemblyPartType.cableTrunkingBody:
      case AssemblyPartType.cableTrunkingCover:
      case AssemblyPartType.cableTrunkingBend:
      case AssemblyPartType.cableTrunkingRiser:
      case AssemblyPartType.cableTrunkingTee:
      case AssemblyPartType.cableTrunkingCoupler:
        typeColor = const Color(0xFF34D399); // Trunking Green
        break;
      case AssemblyPartType.customSheetMetal:
        typeColor = const Color(0xFF06B6D4); // Cyan
        break;
      case AssemblyPartType.holdDownClamp:
      case AssemblyPartType.standoffBracket:
      case AssemblyPartType.baseFootPlate:
      case AssemblyPartType.splicePlate:
        typeColor = const Color(0xFF94A3B8); // Hardware
        break;
      case AssemblyPartType.safetyCageHoop:
      case AssemblyPartType.safetyCageBellHoop:
      case AssemblyPartType.cageStrap:
      case AssemblyPartType.swingGate:
        typeColor = const Color(0xFF64748B); // Legacy / Deprecated
        break;
      case AssemblyPartType.channel:
        typeColor = const Color(0xFFFBBF24); // Amber
        break;
      case AssemblyPartType.angle:
        typeColor = const Color(0xFFF472B6); // Pink
        break;
      case AssemblyPartType.rod:
      case AssemblyPartType.bar:
        typeColor = const Color(0xFFA78BFA); // Purple
        break;
      case AssemblyPartType.iBeam:
        typeColor = const Color(0xFFFB923C); // Orange
        break;
      case AssemblyPartType.customExtrusion:
        typeColor = const Color(0xFF818CF8); // Indigo
        break;
    }

    return Container(
      margin: const EdgeInsets.only(left: 14, right: 4, top: 1, bottom: 1),
      child: InkWell(
        onTap: () {
          vm.selectPart(part.id);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF0284C7).withValues(alpha: isPrimarySelected ? 0.35 : 0.20)
                : theme.cardBackground,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected ? const Color(0xFF0284C7) : theme.cardBorder,
              width: isSelected ? 1.0 : 0.6,
            ),
          ),
          child: Row(
            children: [
              // Tree branch indicator
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: isVisible ? typeColor : const Color(0xFF475569),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),

              // Part Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  part.type.name.substring(0, part.type.name.length > 3 ? 3 : part.type.name.length).toUpperCase(),
                  style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: typeColor),
                ),
              ),
              const SizedBox(width: 5),

              // Part Name
              Expanded(
                child: Text(
                  part.name,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isVisible ? (isSelected ? (theme.isLight ? const Color(0xFF0284C7) : Colors.white) : theme.textPrimary) : theme.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Length tag
              Text(
                '${part.length.toInt()}mm',
                style: const TextStyle(fontSize: 8.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 4),

              // Visibility Eye Toggle Button (Small & Dense)
              Tooltip(
                message: isVisible ? 'Hide part in 3D' : 'Show part in 3D',
                child: InkWell(
                  onTap: () {
                    vm.togglePartVisibility(part.id);
                  },
                  borderRadius: BorderRadius.circular(2),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      size: 11,
                      color: isVisible ? const Color(0xFF94A3B8) : const Color(0xFFEF4444),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeldTreeNode(AssemblyWeldJoint weld, AssemblyStudioViewModel vm) {
    final isSelected = vm.selectedWeldId == weld.id;
    final partA = vm.doc.parts.where((p) => p.id == weld.partAId).firstOrNull;
    final partB = vm.doc.parts.where((p) => p.id == weld.partBId).firstOrNull;

    final label = (partA != null && partB != null)
        ? '${partA.name} ↔ ${partB.name}'
        : 'Weld Joint (${weld.weldSizeMm.toInt()}mm)';

    return Container(
      margin: const EdgeInsets.only(left: 20, right: 4, top: 1, bottom: 1),
      child: InkWell(
        onTap: () {
          vm.selectWeld(weld.id);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                : theme.cardBackground,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected ? const Color(0xFFF59E0B) : theme.cardBorder,
              width: isSelected ? 1.0 : 0.6,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.flash_on_rounded, size: 10, color: Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFFFDE68A) : const Color(0xFF94A3B8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${weld.weldSizeMm.toInt()}mm',
                style: const TextStyle(fontSize: 8, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 4),
              // Break bond button
              Tooltip(
                message: 'Break weld bond',
                child: InkWell(
                  onTap: () {
                    vm.breakBond(weld.partAId, weld.partBId);
                  },
                  borderRadius: BorderRadius.circular(2),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.link_off_rounded, size: 10, color: Color(0xFFEF4444)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearConfirm(BuildContext context, AssemblyStudioViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text('Clear Assembly?', style: TextStyle(color: theme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
        content: Text(
          'This will remove all parts and welds from the current assembly workspace.',
          style: TextStyle(color: theme.textTertiary, fontSize: 11),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              vm.clearAll();
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
