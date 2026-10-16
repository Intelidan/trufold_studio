// Onshape-style Top Header & Dynamic Contextual Ribbon
// TruFold Assembly Studio - Phase 7 Onshape Transformation
// Features exact Onshape top bar, document info, version pill,
// and single-row contextual toolbar that morphs between 3D Modeling and 2D Sketching.

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/theme/assembly_studio_theme.dart';
import 'toolbar/assembly_desktop_menu_bar.dart';
import 'toolbar/assembly_onshape_toolbar.dart';

class AssemblyOnshapeTopBar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback? onToggleLeftPanel;
  final VoidCallback? onToggleRightPanel;
  final VoidCallback? onToggleBottomDrawer;
  final bool isLeftPanelOpen;
  final bool isRightPanelOpen;
  final bool isBottomDrawerOpen;
  final VoidCallback? onResetPositions;

  const AssemblyOnshapeTopBar({
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

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Top Header Row (Height 32px): Logo, Document Name, Versioning/Branch, Quick Action icons
            _buildOnshapeDocumentHeader(context, vm),

            // 2. Single-Row Dynamic Contextual Toolbar (Height 38px)
            // Displays 3D Modelling Toolbar or Sketch Toolbar based on vm.isSketchMode
            AssemblyOnshapeToolbar(viewModel: vm),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Top Header Row (Logo, Document Name, Versioning/Branch, User Options)
  // ---------------------------------------------------------------------------
  Widget _buildOnshapeDocumentHeader(BuildContext context, AssemblyStudioViewModel vm) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Onshape / TruFold Studio Logo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: AssemblyStudioTheme.onshapeBlueDark, borderRadius: BorderRadius.circular(4)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 5),
                  Text(
                    'trufold',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.white),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Document Hamburger Menu Icon
            InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(3),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.menu_rounded, size: 16, color: Color(0xFF475569)),
              ),
            ),

            const SizedBox(width: 6),

            // Document Title
            const Text(
              'Sheet Metal Enclosure',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),

            const SizedBox(width: 8),

            // Versioning / Branch Pill ('Main')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alt_route_rounded, size: 11, color: Color(0xFF64748B)),
                  SizedBox(width: 4),
                  Text(
                    'Main',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 14),

            // SS2: Desktop CAD Menu Bar (File, Edit, View, Panels, Windows, Settings, Help)
            AssemblyDesktopMenuBar(
              viewModel: vm,
              onToggleLeftPanel: onToggleLeftPanel,
              onToggleRightPanel: onToggleRightPanel,
              onToggleBottomDrawer: onToggleBottomDrawer,
              isLeftPanelOpen: isLeftPanelOpen,
              isRightPanelOpen: isRightPanelOpen,
              isBottomDrawerOpen: isBottomDrawerOpen,
              onResetPositions: onResetPositions,
            ),

            const SizedBox(width: 16),

            // Search Tools Input Box (Matches Onshape Screenshot 4)
            Container(
              height: 22,
              width: 140,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, size: 12, color: Color(0xFF94A3B8)),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Search tools... Alt+/',
                      style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Left Panel Toggle
            Tooltip(
              message: 'Toggle Features & Parts Tree',
              child: InkWell(
                onTap: onToggleLeftPanel,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(Icons.dock_rounded, size: 15, color: Color(0xFF475569)),
                ),
              ),
            ),

            const SizedBox(width: 4),

            // Right Inspector Toggle
            Tooltip(
              message: 'Toggle Property Inspector',
              child: InkWell(
                onTap: onToggleRightPanel,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(Icons.vertical_split_rounded, size: 15, color: Color(0xFF475569)),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Share Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AssemblyStudioTheme.onshapeBlue, borderRadius: BorderRadius.circular(4)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.share_rounded, size: 11, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Share',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // Help Button
            const Icon(Icons.help_outline_rounded, size: 15, color: Color(0xFF64748B)),

            const SizedBox(width: 6),

            // Canvas Background Theme Toggle (Sun / Moon)
            Tooltip(
              message: vm.isLightBackground ? 'Switch to Dark Studio Canvas (Alt+T)' : 'Switch to Light Studio Canvas (Alt+T)',
              child: InkWell(
                onTap: vm.toggleTheme,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    vm.isLightBackground ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    size: 15,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
