import 'package:flutter/material.dart';

import '../../models/assembly_part.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';
import '../theme/assembly_studio_theme.dart';

/// Bottom collapsible "Asset view" drawer inspired by Xenko / Unreal / Unity GameStudio.
/// Displays modular Common Parts with miniature isometric previews, Draggable & Click-to-Place triggers,
/// active Welds, and Cut-List BOM. Can be collapsed to 26px to maximize 3D canvas space.
class AssemblyAssetDrawer extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;

  const AssemblyAssetDrawer({super.key, required this.viewModel, required this.isCollapsed, required this.onToggleCollapse});

  @override
  State<AssemblyAssetDrawer> createState() => _AssemblyAssetDrawerState();
}

class _AssemblyAssetDrawerState extends State<AssemblyAssetDrawer> {
  int _activeTabIndex = 0; // 0: Asset view, 1: Welds, 2: Cut-List, 3: Diagnostics
  String _selectedCategory = 'All';

  AssemblyStudioTheme get theme => AssemblyStudioTheme(isLight: widget.viewModel.isLightBackground);

  Color _getCategoryTagTextColor(Color accent, bool isLight) {
    if (!isLight) return accent;
    final hsl = HSLColor.fromColor(accent);
    return hsl.withLightness((hsl.lightness * 0.70).clamp(0.0, 0.45)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final isCollapsed = widget.isCollapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      height: isCollapsed ? 28.0 : 160.0,
      decoration: BoxDecoration(
        color: theme.panelBackground, // Dynamic Light / Dark Drawer
        border: Border(top: BorderSide(color: theme.panelBorder, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Drawer Header / Tab Bar (Height 28px)
          _buildHeader(context, vm, isCollapsed),

          // 2. Expanded Drawer Body (Only shown when not collapsed)
          if (!isCollapsed) Expanded(child: _buildActiveTabContent(vm)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AssemblyStudioViewModel vm, bool isCollapsed) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.panelHeaderBackground,
        border: Border(bottom: BorderSide(color: theme.panelBorder, width: 1.0)),
      ),
      child: Row(
        children: [
          // Tab 0: Common Parts Library
          _buildTabButton(index: 0, icon: Icons.grid_view_rounded, label: 'Asset view (Common Parts)', count: 19),
          const SizedBox(width: 4),

          // Tab 1: Welds & Joints
          _buildTabButton(index: 1, icon: Icons.flash_on_rounded, label: 'Welds & Joints', count: vm.doc.welds.length, accentColor: const Color(0xFFF59E0B)),
          const SizedBox(width: 4),

          // Tab 2: Cut-List BOM
          _buildTabButton(index: 2, icon: Icons.receipt_long_rounded, label: 'Cut-List BOM', count: vm.doc.parts.length, accentColor: const Color(0xFF10B981)),
          const SizedBox(width: 4),

          // Tab 3: Diagnostics
          _buildTabButton(index: 3, icon: Icons.memory_rounded, label: '3D Diagnostics', accentColor: const Color(0xFFA855F7)),

          const SizedBox(width: 6),

          // Phase 2 Quick Generators & Demos (Flexible horizontal scroll prevents overflow)
          if (!isCollapsed)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: vm.generateSafetyCageAssembly,
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.isLight ? const Color(0xFFFEF3C7) : const Color(0xFFD97706).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.flash_on_rounded, size: 10, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 3),
                              Text(
                                '+ Safety Cage',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: theme.isLight ? const Color(0xFFB45309) : const Color(0xFFFCD34D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: vm.addWalkThroughParapetStiles,
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0284C7).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                          ),
                          child: Text(
                            '+ Walk-Through',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: theme.isLight ? const Color(0xFF0369A1) : const Color(0xFFBAE6FD),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: vm.addWallStandoffBrackets,
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: theme.isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.8),
                          ),
                          child: Text(
                            '+ Standoffs',
                            style: TextStyle(fontSize: 8.5, color: theme.textSecondary, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: vm.addBaseFootPlates,
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: theme.isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.8),
                          ),
                          child: Text(
                            '+ Base Shoes',
                            style: TextStyle(fontSize: 8.5, color: theme.textSecondary, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: vm.addSafetySwingGate,
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.isLight ? const Color(0xFFFEF3C7) : const Color(0xFF78350F),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: const Color(0xFFD97706), width: 0.8),
                          ),
                          child: Text(
                            '+ Swing Gate',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: theme.isLight ? const Color(0xFF92400E) : const Color(0xFFFDE68A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: vm.loadStandardLadderDemo,
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.isLight ? const Color(0xFFF1F5F9) : const Color(0xFF22222C),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: theme.isLight ? const Color(0xFFCBD5E1) : const Color(0xFF333342), width: 0.8),
                          ),
                          child: Text('Ladder Demo', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: vm.loadTeeAssemblyDemo,
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.isLight ? const Color(0xFFF1F5F9) : const Color(0xFF22222C),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: theme.isLight ? const Color(0xFFCBD5E1) : const Color(0xFF333342), width: 0.8),
                          ),
                          child: Text('Tee Demo', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            const Spacer(),

          const SizedBox(width: 6),

          // Collapse / Expand Toggle Button (Maximizes Canvas)
          Tooltip(
            message: isCollapsed ? 'Expand Asset Shelf (Show Parts)' : 'Minimize Asset Shelf (Maximize 3D Canvas)',
            child: InkWell(
              onTap: widget.onToggleCollapse,
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isCollapsed
                      ? (theme.isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0284C7).withValues(alpha: 0.25))
                      : (theme.isLight ? const Color(0xFFF1F5F9) : const Color(0xFF22222C)),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isCollapsed ? const Color(0xFF0284C7) : (theme.isLight ? const Color(0xFFCBD5E1) : const Color(0xFF333342)),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCollapsed ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 13,
                      color: isCollapsed ? const Color(0xFF0284C7) : theme.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isCollapsed ? 'Expand Shelf' : 'Max Canvas',
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: isCollapsed ? const Color(0xFF0284C7) : theme.textSecondary),
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

  Widget _buildTabButton({required int index, required IconData icon, required String label, int? count, Color accentColor = const Color(0xFF38BDF8)}) {
    final isActive = _activeTabIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _activeTabIndex = index;
          if (widget.isCollapsed) {
            widget.onToggleCollapse(); // Auto expand when user clicks a tab
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? theme.cardBackground : Colors.transparent,
          border: Border(top: BorderSide(color: isActive ? accentColor : Colors.transparent, width: 2.0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: isActive ? accentColor : theme.textTertiary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? theme.textPrimary : theme.textSecondary,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                decoration: BoxDecoration(color: isActive ? accentColor.withValues(alpha: 0.2) : theme.cardBorder, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '$count',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isActive ? accentColor : theme.textTertiary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(AssemblyStudioViewModel vm) {
    switch (_activeTabIndex) {
      case 0:
        return _buildAssetViewTab(vm);
      case 1:
        return _buildWeldsTab(vm);
      case 2:
        return _buildCutListTab(vm);
      case 3:
        return _buildDiagnosticsTab(vm);
      default:
        return const SizedBox.shrink();
    }
  }

  // ===========================================================================
  // TAB 0: ASSET VIEW (COMMON PARTS SHELF)
  // ===========================================================================
  Widget _buildAssetViewTab(AssemblyStudioViewModel vm) {
    final allAssets = [
      // 1. Rails & Stiles
      _AssetTemplateDef(
        type: AssemblyPartType.straightRail,
        title: 'C-Channel Rail',
        specs: '100x30x2.0 • 2000mm',
        category: 'Rails & Stiles',
        accentColor: const Color(0xFF38BDF8),
        createPart: () => AssemblyPart(
          id: 'rail_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Straight Stile Rail',
          type: AssemblyPartType.straightRail,
          length: 2000,
          height: 100,
          flangeWidth: 30,
          thickness: 2.0,
          color: const Color(0xFF94A3B8),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.walkThroughStile,
        title: 'Walk-Through Stile',
        specs: 'OSHA 1060mm • Flared Arch',
        category: 'Rails & Stiles',
        accentColor: const Color(0xFF38BDF8),
        createPart: () => AssemblyPart(
          id: 'walkthrough_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Walk-Through Parapet Stile',
          type: AssemblyPartType.walkThroughStile,
          length: 1060,
          height: 100,
          flangeWidth: 30,
          thickness: 2.5,
          color: const Color(0xFF38BDF8),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.boxTubeStile,
        title: 'RHS Box Stile',
        specs: '60x40x2.5 • Box Tube',
        category: 'Rails & Stiles',
        accentColor: const Color(0xFF64748B),
        createPart: () => AssemblyPart(
          id: 'boxtube_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Box Tube Stile (60x40)',
          type: AssemblyPartType.boxTubeStile,
          length: 2000,
          height: 60,
          flangeWidth: 40,
          thickness: 2.5,
          color: const Color(0xFF64748B),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.bentRail,
        title: 'Bent 90° Rail',
        specs: '100x30 • R300mm Arc',
        category: 'Rails & Stiles',
        accentColor: const Color(0xFF60A5FA),
        createPart: () => AssemblyPart(
          id: 'bent_rail_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Bent Rail Fitting',
          type: AssemblyPartType.bentRail,
          length: 600,
          height: 100,
          flangeWidth: 30,
          thickness: 2.0,
          color: const Color(0xFF64748B),
        ),
      ),

      // 2. Rungs & Treads
      _AssetTemplateDef(
        type: AssemblyPartType.rung,
        title: 'Slotted C-Rung',
        specs: '40x20x1.5 • 400mm',
        category: 'Rungs & Treads',
        accentColor: const Color(0xFF34D399),
        createPart: () => AssemblyPart(
          id: 'rung_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Slotted Rung',
          type: AssemblyPartType.rung,
          length: 400,
          height: 40,
          flangeWidth: 20,
          thickness: 1.5,
          color: const Color(0xFFCBD5E1),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.diamondGripRung,
        title: 'Diamond Grip-Strut',
        specs: '40x20x2.0 • Perforated',
        category: 'Rungs & Treads',
        accentColor: const Color(0xFF10B981),
        createPart: () => AssemblyPart(
          id: 'diamond_rung_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Diamond Grip-Strut Rung',
          type: AssemblyPartType.diamondGripRung,
          length: 400,
          height: 40,
          flangeWidth: 20,
          thickness: 2.0,
          color: const Color(0xFF10B981),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.wideStepTread,
        title: 'Wide Safety Tread',
        specs: '80x25x2.5 • Ribbed Step',
        category: 'Rungs & Treads',
        accentColor: const Color(0xFF059669),
        createPart: () => AssemblyPart(
          id: 'step_tread_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Wide Flanged Step Tread',
          type: AssemblyPartType.wideStepTread,
          length: 500,
          height: 80,
          flangeWidth: 25,
          thickness: 2.5,
          color: const Color(0xFF94A3B8),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.rod,
        title: 'Solid Round Rod',
        specs: 'Ø16mm Stainless 304',
        category: 'Rungs & Treads',
        accentColor: const Color(0xFFA78BFA),
        createPart: () => AssemblyPart(
          id: 'rod_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Round Tie Rod',
          type: AssemblyPartType.rod,
          length: 500,
          height: 16,
          flangeWidth: 16,
          thickness: 16,
          color: const Color(0xFFA78BFA),
        ),
      ),

      // 3. Safety Cages
      _AssetTemplateDef(
        type: AssemblyPartType.safetyCageBellHoop,
        title: 'Bell Entry Hoop',
        specs: 'Flared Ø800mm • 30° Mouth',
        category: 'Safety Cage',
        accentColor: const Color(0xFFF59E0B),
        createPart: () => AssemblyPart(
          id: 'cage_bell_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Bell Entry Hoop (Flared)',
          type: AssemblyPartType.safetyCageBellHoop,
          length: 50,
          height: 700,
          flangeWidth: 700,
          thickness: 4.0,
          color: const Color(0xFFF59E0B),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.safetyCageHoop,
        title: 'Standard Cage Hoop',
        specs: 'Ø700mm Circular Hoop',
        category: 'Safety Cage',
        accentColor: const Color(0xFFD97706),
        createPart: () => AssemblyPart(
          id: 'cage_hoop_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Standard Cage Hoop',
          type: AssemblyPartType.safetyCageHoop,
          length: 50,
          height: 700,
          flangeWidth: 700,
          thickness: 4.0,
          color: const Color(0xFF64748B),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.cageStrap,
        title: 'Vertical Cage Strap',
        specs: '30x3.0mm • 2000mm Flat',
        category: 'Safety Cage',
        accentColor: const Color(0xFF94A3B8),
        createPart: () => AssemblyPart(
          id: 'cage_strap_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Vertical Flat Strap',
          type: AssemblyPartType.cageStrap,
          length: 2000,
          height: 30,
          flangeWidth: 30,
          thickness: 3.0,
          color: const Color(0xFF94A3B8),
        ),
      ),

      // 4. Mounting & Hardware
      _AssetTemplateDef(
        type: AssemblyPartType.standoffBracket,
        title: 'Wall Standoff',
        specs: '175mm Heavy Standoff',
        category: 'Mounting & Hardware',
        accentColor: const Color(0xFF64748B),
        createPart: () => AssemblyPart(
          id: 'standoff_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Wall Standoff Bracket',
          type: AssemblyPartType.standoffBracket,
          length: 175,
          height: 80,
          flangeWidth: 50,
          thickness: 4.0,
          color: const Color(0xFF64748B),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.baseFootPlate,
        title: 'Base Anchor Shoe',
        specs: '120x100x6mm • 4-Hole',
        category: 'Mounting & Hardware',
        accentColor: const Color(0xFF475569),
        createPart: () => AssemblyPart(
          id: 'foot_plate_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Base Anchor Foot Plate',
          type: AssemblyPartType.baseFootPlate,
          length: 120,
          height: 100,
          thickness: 6.0,
          color: const Color(0xFF475569),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.splicePlate,
        title: 'Stile Splice Plate',
        specs: '250x80x3.0mm Fishplate',
        category: 'Mounting & Hardware',
        accentColor: const Color(0xFF94A3B8),
        createPart: () => AssemblyPart(
          id: 'splice_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Stile Splice Fishplate',
          type: AssemblyPartType.splicePlate,
          length: 250,
          height: 80,
          thickness: 3.0,
          color: const Color(0xFF94A3B8),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.swingGate,
        title: 'Safety Swing Gate',
        specs: 'OSHA 600x420mm Yellow',
        category: 'Mounting & Hardware',
        accentColor: const Color(0xFFFBBF24),
        createPart: () => AssemblyPart(
          id: 'gate_${DateTime.now().millisecondsSinceEpoch}',
          name: 'OSHA Safety Swing Gate',
          type: AssemblyPartType.swingGate,
          length: 600,
          height: 420,
          color: const Color(0xFFFBBF24),
          jointType: AssemblyJointType.hinged,
        ),
      ),

      // 5. Structural Profiles
      _AssetTemplateDef(
        type: AssemblyPartType.channel,
        title: 'Structural Channel',
        specs: 'C-Section 80x40x2.5',
        category: 'Profiles',
        accentColor: const Color(0xFFFBBF24),
        createPart: () => AssemblyPart(
          id: 'channel_${DateTime.now().millisecondsSinceEpoch}',
          name: 'C-Channel Stiffener',
          type: AssemblyPartType.channel,
          length: 600,
          height: 80,
          flangeWidth: 40,
          thickness: 2.5,
          color: const Color(0xFFFBBF24),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.angle,
        title: 'L-Angle Stiffener',
        specs: '50x50x3.0mm Flange',
        category: 'Profiles',
        accentColor: const Color(0xFFF472B6),
        createPart: () => AssemblyPart(
          id: 'angle_${DateTime.now().millisecondsSinceEpoch}',
          name: 'L-Angle Bracket',
          type: AssemblyPartType.angle,
          length: 400,
          height: 50,
          flangeWidth: 50,
          thickness: 3.0,
          color: const Color(0xFFF472B6),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.bar,
        title: 'Solid Flat Bar',
        specs: '50x6.0mm Tie Plate',
        category: 'Profiles',
        accentColor: const Color(0xFFC084FC),
        createPart: () => AssemblyPart(
          id: 'bar_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Flat Splice Bar',
          type: AssemblyPartType.bar,
          length: 450,
          height: 50,
          flangeWidth: 0,
          thickness: 6.0,
          color: const Color(0xFFC084FC),
        ),
      ),
      _AssetTemplateDef(
        type: AssemblyPartType.iBeam,
        title: 'I-Beam Girder',
        specs: '120x60x4.0 Flange',
        category: 'Profiles',
        accentColor: const Color(0xFFFB923C),
        createPart: () => AssemblyPart(
          id: 'ibeam_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Heavy I-Beam Post',
          type: AssemblyPartType.iBeam,
          length: 800,
          height: 120,
          flangeWidth: 60,
          thickness: 4.0,
          color: const Color(0xFFFB923C),
        ),
      ),
    ];

    final filteredAssets = _selectedCategory == 'All' ? allAssets : allAssets.where((a) => a.category == _selectedCategory).toList();

    const categories = ['All', 'Rails & Stiles', 'Rungs & Treads', 'Safety Cage', 'Mounting & Hardware', 'Profiles'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category Filter Chips Row
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.panelHeaderBackground,
            border: Border(bottom: BorderSide(color: theme.panelBorder, width: 0.6)),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 4),
            itemBuilder: (context, idx) {
              final cat = categories[idx];
              final isSel = _selectedCategory == cat;
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategory = cat;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSel ? (theme.isLight ? const Color(0xFFE0F2FE) : theme.accentSky.withValues(alpha: 0.25)) : theme.cardBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSel ? (theme.isLight ? const Color(0xFF0284C7) : theme.accentSky) : (theme.isLight ? const Color(0xFFCBD5E1) : theme.cardBorder),
                      width: isSel ? 1.0 : 0.8,
                    ),
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                      color: isSel ? (theme.isLight ? const Color(0xFF0369A1) : theme.accentSky) : theme.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Horizontal Asset Cards Shelf
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            itemCount: filteredAssets.length,
            itemBuilder: (context, index) {
              final asset = filteredAssets[index];
              return _buildAssetCard(context, vm, asset);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAssetCard(BuildContext context, AssemblyStudioViewModel vm, _AssetTemplateDef asset) {
    final placementData = PendingPartPlacement(
      type: asset.type,
      name: asset.title,
      length: 400,
      height: 40,
      flangeWidth: 20,
      thickness: 1.5,
      color: asset.accentColor,
    );

    final String catTag;
    switch (asset.category) {
      case 'Rails & Stiles':
        catTag = 'STILE';
        break;
      case 'Rungs & Treads':
        catTag = 'RUNG';
        break;
      case 'Safety Cage':
        catTag = 'CAGE';
        break;
      case 'Mounting & Hardware':
        catTag = 'MOUNT';
        break;
      case 'Profiles':
        catTag = 'PROFILE';
        break;
      default:
        catTag = 'PART';
    }

    return Draggable<PendingPartPlacement>(
      data: placementData,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: asset.accentColor, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_box_rounded, size: 14, color: asset.accentColor),
              const SizedBox(width: 6),
              Text(
                'Place ${asset.title}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
      child: Container(
        width: 116,
        margin: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: () {
            // Click to add / place directly into the assembly scene
            final newPart = asset.createPart();
            vm.addPart(newPart);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: theme.isLight ? [Colors.white, const Color(0xFFF8FAFC)] : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.isLight ? const Color(0xFFCBD5E1) : theme.cardBorder, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: theme.isLight ? 0.04 : 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Micro Header: Category tag + tactile '+' button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: asset.accentColor.withValues(alpha: theme.isLight ? 0.15 : 0.2),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: asset.accentColor.withValues(alpha: theme.isLight ? 0.6 : 0.4), width: 0.6),
                      ),
                      child: Text(
                        catTag,
                        style: TextStyle(
                          fontSize: 7.0,
                          fontWeight: FontWeight.w800,
                          color: _getCategoryTagTextColor(asset.accentColor, theme.isLight),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155),
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.6),
                      ),
                      child: Icon(Icons.add_rounded, size: 10, color: theme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 3),

                // Card Miniature Preview
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: theme.isLight ? [const Color(0xFFF8FAFC), const Color(0xFFEEF2F6)] : [const Color(0xFF1E293B), const Color(0xFF151E2E)],
                      ),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: theme.isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
                    ),
                    alignment: Alignment.center,
                    child: CustomPaint(
                      size: const Size(48, 42),
                      painter: _MiniatureAssetPainter(partType: asset.type, accentColor: asset.accentColor, isLight: theme.isLight),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Title
                Text(
                  asset.title,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: theme.textPrimary, letterSpacing: -0.1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // Specs subtitle
                Text(
                  asset.specs,
                  style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w500, color: theme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: WELDS & JOINTS
  // ===========================================================================
  Widget _buildWeldsTab(AssemblyStudioViewModel vm) {
    if (vm.doc.welds.isEmpty) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flash_off_rounded, size: 16, color: Color(0xFF64748B)),
            const SizedBox(width: 8),
            const Text(
              'No active weld bonds in model. Select Weld Torch (W) and drag across seams.',
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () => vm.setToolMode(SketchUpToolMode.weld),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                side: const BorderSide(color: Color(0xFFF59E0B), width: 0.8),
              ),
              child: const Text('Weld Torch (W)', style: TextStyle(fontSize: 9.5, color: Color(0xFFF59E0B))),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: vm.doc.welds.length,
      itemBuilder: (context, index) {
        final weld = vm.doc.welds[index];
        final isSelected = vm.selectedWeldId == weld.id;
        final partA = vm.doc.parts.where((p) => p.id == weld.partAId).firstOrNull;
        final partB = vm.doc.parts.where((p) => p.id == weld.partBId).firstOrNull;

        return Container(
          width: 160,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF59E0B).withValues(alpha: 0.2) : theme.cardBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? const Color(0xFFF59E0B) : theme.cardBorder, width: isSelected ? 1.2 : 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flash_on_rounded, size: 12, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Weld #${index + 1}',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: theme.textPrimary),
                    ),
                  ),
                  InkWell(
                    onTap: () => vm.breakBond(weld.partAId, weld.partBId),
                    child: const Icon(Icons.link_off_rounded, size: 12, color: Color(0xFFEF4444)),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '${partA?.name ?? "Part A"} ↔ ${partB?.name ?? "Part B"}',
                style: const TextStyle(fontSize: 8.5, color: Color(0xFFCBD5E1)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Bead: ${weld.weldSizeMm.toInt()}mm • Weld XYZ: (${weld.weldPoint.x.toInt()}, ${weld.weldPoint.y.toInt()}, ${weld.weldPoint.z.toInt()})',
                style: const TextStyle(fontSize: 7.5, color: Color(0xFF94A3B8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // TAB 2: CUT-LIST BOM
  // ===========================================================================
  Widget _buildCutListTab(AssemblyStudioViewModel vm) {
    if (vm.doc.parts.isEmpty) {
      return const Center(
        child: Text('Cut-List is empty. Add parts to generate BOM.', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: vm.doc.parts.length,
      itemBuilder: (context, index) {
        final part = vm.doc.parts[index];
        final isSelected = vm.selectedPartIds.contains(part.id);

        return Container(
          width: 150,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0284C7).withValues(alpha: 0.2) : theme.cardBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? const Color(0xFF0284C7) : theme.cardBorder, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                part.name,
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: theme.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text('Cut Length: ${part.length.toInt()} mm', style: const TextStyle(fontSize: 8.5, color: Color(0xFF38BDF8))),
              Text('Flange Width: ${part.flangeWidth.toInt()} mm', style: const TextStyle(fontSize: 8, color: Color(0xFF94A3B8))),
              Text('Thk: ${part.thickness}mm • ${part.type.name.toUpperCase()}', style: const TextStyle(fontSize: 8, color: Color(0xFF64748B))),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // TAB 3: 3D DIAGNOSTICS & ENGINE STATS
  // ===========================================================================
  Widget _buildDiagnosticsTab(AssemblyStudioViewModel vm) {
    final mesh = vm.assemblyMesh;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildDiagMetric('Polygons', '${mesh.polygons.length}', Icons.polyline_rounded, const Color(0xFF38BDF8)),
          const SizedBox(width: 16),
          _buildDiagMetric('Vertices', '${mesh.polygons.length * 4}', Icons.grain_rounded, const Color(0xFF34D399)),
          const SizedBox(width: 16),
          _buildDiagMetric(
            'Bounding Box',
            '${mesh.boundWidth.toInt()} x ${mesh.boundLength.toInt()} x ${mesh.boundHeight.toInt()} mm',
            Icons.view_in_ar_rounded,
            const Color(0xFFFBBF24),
          ),
          const SizedBox(width: 16),
          _buildDiagMetric('GPU Engine', 'flutter_scene (Impeller)', Icons.speed_rounded, const Color(0xFFA855F7)),
        ],
      ),
    );
  }

  Widget _buildDiagMetric(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: theme.cardBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(fontSize: 7.5, color: theme.textTertiary)),
              Text(
                val,
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssetTemplateDef {
  final AssemblyPartType type;
  final String title;
  final String specs;
  final String category;
  final Color accentColor;
  final AssemblyPart Function() createPart;

  const _AssetTemplateDef({
    required this.type,
    required this.title,
    required this.specs,
    required this.category,
    required this.accentColor,
    required this.createPart,
  });
}

/// Miniature CAD isometric diagram painter for the bottom asset cards.
class _MiniatureAssetPainter extends CustomPainter {
  final AssemblyPartType partType;
  final Color accentColor;
  final bool isLight;

  const _MiniatureAssetPainter({required this.partType, required this.accentColor, this.isLight = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final hsl = HSLColor.fromColor(accentColor);
    final topColor = hsl.withLightness((hsl.lightness * (isLight ? 1.05 : 1.25)).clamp(0.0, 0.95)).toColor();
    final frontColor = hsl.withLightness((hsl.lightness * (isLight ? 0.85 : 0.95)).clamp(0.0, 0.90)).toColor();
    final sideColor = hsl.withLightness((hsl.lightness * (isLight ? 0.65 : 0.70)).clamp(0.0, 0.80)).toColor();
    final strokeColor = isLight
        ? hsl.withLightness((hsl.lightness * 0.55).clamp(0.0, 0.45)).toColor()
        : hsl.withLightness((hsl.lightness * 1.35).clamp(0.0, 0.95)).toColor();

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = strokeColor;

    // Ground shadow in perspective
    final shadowPaint = Paint()
      ..color = isLight ? Colors.black.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.88), width: w * 0.72, height: 5), shadowPaint);

    switch (partType) {
      case AssemblyPartType.rung:
        final top = Path()
          ..moveTo(w * 0.15, h * 0.38)
          ..lineTo(w * 0.65, h * 0.20)
          ..lineTo(w * 0.85, h * 0.30)
          ..lineTo(w * 0.35, h * 0.48)
          ..close();
        fillPaint.color = topColor;
        canvas.drawPath(top, fillPaint);
        canvas.drawPath(top, strokePaint);

        final front = Path()
          ..moveTo(w * 0.35, h * 0.48)
          ..lineTo(w * 0.85, h * 0.30)
          ..lineTo(w * 0.85, h * 0.55)
          ..lineTo(w * 0.35, h * 0.73)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(front, fillPaint);
        canvas.drawPath(front, strokePaint);

        final slotPaint = Paint()
          ..color = isLight ? const Color(0xFF334155) : const Color(0xFF0F172A)
          ..style = PaintingStyle.fill;
        for (int i = 0; i < 3; i++) {
          final t = 0.25 + i * 0.25;
          final sx = (w * 0.35) * (1 - t) + (w * 0.85) * t;
          final sy = (w * 0.48) * (1 - t) + (w * 0.30) * t + 4.5;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx, sy), width: 3.0, height: 6.0), const Radius.circular(1.5)), slotPaint);
        }
        break;

      case AssemblyPartType.straightRail:
      case AssemblyPartType.bentRail:
        final top = Path()
          ..moveTo(w * 0.22, h * 0.35)
          ..lineTo(w * 0.55, h * 0.20)
          ..lineTo(w * 0.72, h * 0.28)
          ..lineTo(w * 0.39, h * 0.43)
          ..close();
        fillPaint.color = topColor;
        canvas.drawPath(top, fillPaint);
        canvas.drawPath(top, strokePaint);

        final front = Path()
          ..moveTo(w * 0.39, h * 0.43)
          ..lineTo(w * 0.72, h * 0.28)
          ..lineTo(w * 0.72, h * 0.72)
          ..lineTo(w * 0.39, h * 0.87)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(front, fillPaint);
        canvas.drawPath(front, strokePaint);

        final leftSide = Path()
          ..moveTo(w * 0.22, h * 0.35)
          ..lineTo(w * 0.39, h * 0.43)
          ..lineTo(w * 0.39, h * 0.87)
          ..lineTo(w * 0.22, h * 0.79)
          ..close();
        fillPaint.color = sideColor;
        canvas.drawPath(leftSide, fillPaint);
        canvas.drawPath(leftSide, strokePaint);

        final holePaint = Paint()
          ..color = isLight ? const Color(0xFF1E293B) : const Color(0xFF0F172A)
          ..style = PaintingStyle.fill;
        for (int i = 0; i < 4; i++) {
          final hy = h * 0.38 + i * (h * 0.12);
          final hx = w * 0.55 + (hy - h * 0.38) * -0.05;
          canvas.drawCircle(Offset(hx, hy), 1.5, holePaint);
        }
        break;

      case AssemblyPartType.walkThroughStile:
        final stile = Path()
          ..moveTo(w * 0.28, h * 0.85)
          ..lineTo(w * 0.28, h * 0.42)
          ..cubicTo(w * 0.28, h * 0.15, w * 0.75, h * 0.15, w * 0.75, h * 0.42)
          ..lineTo(w * 0.75, h * 0.85)
          ..lineTo(w * 0.63, h * 0.85)
          ..lineTo(w * 0.63, h * 0.44)
          ..cubicTo(w * 0.63, h * 0.26, w * 0.40, h * 0.26, w * 0.40, h * 0.44)
          ..lineTo(w * 0.40, h * 0.85)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(stile, fillPaint);
        canvas.drawPath(stile, strokePaint);
        break;

      case AssemblyPartType.boxTubeStile:
        final top = Path()
          ..moveTo(w * 0.25, h * 0.35)
          ..lineTo(w * 0.60, h * 0.18)
          ..lineTo(w * 0.75, h * 0.25)
          ..lineTo(w * 0.40, h * 0.42)
          ..close();
        fillPaint.color = topColor;
        canvas.drawPath(top, fillPaint);
        canvas.drawPath(top, strokePaint);

        final front = Path()
          ..moveTo(w * 0.40, h * 0.42)
          ..lineTo(w * 0.75, h * 0.25)
          ..lineTo(w * 0.75, h * 0.72)
          ..lineTo(w * 0.40, h * 0.89)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(front, fillPaint);
        canvas.drawPath(front, strokePaint);

        final side = Path()
          ..moveTo(w * 0.25, h * 0.35)
          ..lineTo(w * 0.40, h * 0.42)
          ..lineTo(w * 0.40, h * 0.89)
          ..lineTo(w * 0.25, h * 0.82)
          ..close();
        fillPaint.color = sideColor;
        canvas.drawPath(side, fillPaint);
        canvas.drawPath(side, strokePaint);

        final hollow = Path()
          ..moveTo(w * 0.30, h * 0.35)
          ..lineTo(w * 0.58, h * 0.21)
          ..lineTo(w * 0.70, h * 0.26)
          ..lineTo(w * 0.42, h * 0.40)
          ..close();
        final hollowPaint = Paint()
          ..color = isLight ? const Color(0xFF1E293B) : const Color(0xFF0F172A)
          ..style = PaintingStyle.fill;
        canvas.drawPath(hollow, hollowPaint);
        break;

      case AssemblyPartType.diamondGripRung:
        final top = Path()
          ..moveTo(w * 0.15, h * 0.40)
          ..lineTo(w * 0.65, h * 0.22)
          ..lineTo(w * 0.85, h * 0.32)
          ..lineTo(w * 0.35, h * 0.50)
          ..close();
        fillPaint.color = topColor;
        canvas.drawPath(top, fillPaint);
        canvas.drawPath(top, strokePaint);

        final front = Path()
          ..moveTo(w * 0.35, h * 0.50)
          ..lineTo(w * 0.85, h * 0.32)
          ..lineTo(w * 0.85, h * 0.58)
          ..lineTo(w * 0.35, h * 0.76)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(front, fillPaint);
        canvas.drawPath(front, strokePaint);

        final gripPaint = Paint()
          ..color = isLight ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)
          ..style = PaintingStyle.fill;
        for (int i = 0; i < 4; i++) {
          final t = 0.20 + i * 0.20;
          final gx = (w * 0.25) * (1 - t) + (w * 0.75) * t;
          final gy = (h * 0.45) * (1 - t) + (h * 0.27) * t;
          final diamond = Path()
            ..moveTo(gx, gy - 2.5)
            ..lineTo(gx + 2.5, gy)
            ..lineTo(gx, gy + 2.5)
            ..lineTo(gx - 2.5, gy)
            ..close();
          canvas.drawPath(diamond, gripPaint);
        }
        break;

      case AssemblyPartType.wideStepTread:
        final top = Path()
          ..moveTo(w * 0.12, h * 0.42)
          ..lineTo(w * 0.65, h * 0.18)
          ..lineTo(w * 0.88, h * 0.30)
          ..lineTo(w * 0.35, h * 0.54)
          ..close();
        fillPaint.color = topColor;
        canvas.drawPath(top, fillPaint);
        canvas.drawPath(top, strokePaint);

        final front = Path()
          ..moveTo(w * 0.35, h * 0.54)
          ..lineTo(w * 0.88, h * 0.30)
          ..lineTo(w * 0.88, h * 0.50)
          ..lineTo(w * 0.35, h * 0.74)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(front, fillPaint);
        canvas.drawPath(front, strokePaint);
        break;

      case AssemblyPartType.safetyCageHoop:
      case AssemblyPartType.safetyCageBellHoop:
        final isBell = partType == AssemblyPartType.safetyCageBellHoop;
        final hoopPath = Path()
          ..moveTo(w * 0.18, h * 0.80)
          ..lineTo(w * 0.18, h * 0.52)
          ..cubicTo(isBell ? w * 0.10 : w * 0.18, h * 0.18, isBell ? w * 0.90 : w * 0.82, h * 0.18, w * 0.82, h * 0.52)
          ..lineTo(w * 0.82, h * 0.80);
        final hoopStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..color = frontColor;
        canvas.drawPath(hoopPath, hoopStroke);
        final innerStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = topColor;
        canvas.drawPath(hoopPath, innerStroke);
        break;

      case AssemblyPartType.cageStrap:
        final sRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.18, height: h * 0.75);
        fillPaint.color = frontColor;
        canvas.drawRect(sRect, fillPaint);
        canvas.drawRect(sRect, strokePaint);
        break;

      case AssemblyPartType.standoffBracket:
        final arm = Path()
          ..moveTo(w * 0.20, h * 0.68)
          ..lineTo(w * 0.65, h * 0.68)
          ..lineTo(w * 0.65, h * 0.28)
          ..lineTo(w * 0.78, h * 0.28)
          ..lineTo(w * 0.78, h * 0.78)
          ..lineTo(w * 0.20, h * 0.78)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(arm, fillPaint);
        canvas.drawPath(arm, strokePaint);
        break;

      case AssemblyPartType.baseFootPlate:
        final plate = Path()
          ..moveTo(w * 0.15, h * 0.68)
          ..lineTo(w * 0.65, h * 0.52)
          ..lineTo(w * 0.85, h * 0.62)
          ..lineTo(w * 0.35, h * 0.78)
          ..close();
        fillPaint.color = topColor;
        canvas.drawPath(plate, fillPaint);
        canvas.drawPath(plate, strokePaint);

        final plateFront = Path()
          ..moveTo(w * 0.35, h * 0.78)
          ..lineTo(w * 0.85, h * 0.62)
          ..lineTo(w * 0.85, h * 0.68)
          ..lineTo(w * 0.35, h * 0.84)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(plateFront, fillPaint);
        canvas.drawPath(plateFront, strokePaint);

        final cleat = Path()
          ..moveTo(w * 0.45, h * 0.65)
          ..lineTo(w * 0.55, h * 0.61)
          ..lineTo(w * 0.55, h * 0.30)
          ..lineTo(w * 0.45, h * 0.35)
          ..close();
        fillPaint.color = sideColor;
        canvas.drawPath(cleat, fillPaint);
        canvas.drawPath(cleat, strokePaint);

        final boltP = Paint()
          ..color = isLight ? const Color(0xFF1E293B) : const Color(0xFF0F172A)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(w * 0.32, h * 0.69), 1.8, boltP);
        canvas.drawCircle(Offset(w * 0.72, h * 0.60), 1.8, boltP);
        break;

      case AssemblyPartType.splicePlate:
        final fPlate = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.35, height: h * 0.75);
        fillPaint.color = frontColor;
        canvas.drawRect(fPlate, fillPaint);
        canvas.drawRect(fPlate, strokePaint);
        break;

      case AssemblyPartType.swingGate:
        final gBorder = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.65, height: h * 0.55);
        final gStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = frontColor;
        canvas.drawRect(gBorder, gStroke);
        canvas.drawLine(Offset(w * 0.18, h * 0.5), Offset(w * 0.82, h * 0.5), gStroke);
        break;

      case AssemblyPartType.channel:
        final cPath = Path()
          ..moveTo(w * 0.25, h * 0.22)
          ..lineTo(w * 0.75, h * 0.22)
          ..lineTo(w * 0.75, h * 0.36)
          ..lineTo(w * 0.45, h * 0.36)
          ..lineTo(w * 0.45, h * 0.64)
          ..lineTo(w * 0.75, h * 0.64)
          ..lineTo(w * 0.75, h * 0.78)
          ..lineTo(w * 0.25, h * 0.78)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(cPath, fillPaint);
        canvas.drawPath(cPath, strokePaint);
        break;

      case AssemblyPartType.angle:
        final lPath = Path()
          ..moveTo(w * 0.25, h * 0.18)
          ..lineTo(w * 0.45, h * 0.18)
          ..lineTo(w * 0.45, h * 0.65)
          ..lineTo(w * 0.80, h * 0.65)
          ..lineTo(w * 0.80, h * 0.82)
          ..lineTo(w * 0.25, h * 0.82)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(lPath, fillPaint);
        canvas.drawPath(lPath, strokePaint);
        break;

      case AssemblyPartType.rod:
        fillPaint.color = frontColor;
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.28, fillPaint);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.28, strokePaint);
        fillPaint.color = topColor;
        canvas.drawCircle(Offset(w * 0.44, h * 0.44), w * 0.12, fillPaint);
        break;

      case AssemblyPartType.bar:
        final rect = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.20, h * 0.34, w * 0.60, h * 0.32), const Radius.circular(3));
        fillPaint.color = frontColor;
        canvas.drawRRect(rect, fillPaint);
        canvas.drawRRect(rect, strokePaint);
        break;

      case AssemblyPartType.iBeam:
        final iPath = Path()
          ..moveTo(w * 0.22, h * 0.18)
          ..lineTo(w * 0.78, h * 0.18)
          ..lineTo(w * 0.78, h * 0.32)
          ..lineTo(w * 0.58, h * 0.32)
          ..lineTo(w * 0.58, h * 0.68)
          ..lineTo(w * 0.78, h * 0.68)
          ..lineTo(w * 0.78, h * 0.82)
          ..lineTo(w * 0.22, h * 0.82)
          ..lineTo(w * 0.22, h * 0.68)
          ..lineTo(w * 0.42, h * 0.68)
          ..lineTo(w * 0.42, h * 0.32)
          ..lineTo(w * 0.22, h * 0.32)
          ..close();
        fillPaint.color = frontColor;
        canvas.drawPath(iPath, fillPaint);
        canvas.drawPath(iPath, strokePaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _MiniatureAssetPainter oldDelegate) =>
      oldDelegate.partType != partType || oldDelegate.accentColor != accentColor || oldDelegate.isLight != isLight;
}
