// =============================================================================
// studio_tab_bar.dart
//
// Multi-File Tab Bar for truFold Studio by Danish.
// Allows managing multiple open files (.dsf, .dxf, .dds), switching active
// workspaces, closing tabs, creating new blank parts, and saving project containers.
// =============================================================================

import 'package:flutter/material.dart';
import '../../models/cad_primitives.dart';
import '../../models/studio_tab_model.dart';
import '../../services/studio_clipboard_service.dart';

class StudioTabBar extends StatelessWidget {
  final List<StudioTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelectTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onNewTab;
  final VoidCallback onOpenFile;
  final VoidCallback? onSaveDsf;
  final VoidCallback onSaveDdsProject;
  final VoidCallback? onCopySelection;
  final VoidCallback? onPasteClipboard;
  final ViewportLayoutMode viewportLayoutMode;
  final ValueChanged<ViewportLayoutMode>? onViewportLayoutModeChanged;
  final bool isRibbonCollapsed;
  final VoidCallback? onToggleRibbon;
  final bool isCompactMode;
  final VoidCallback? onToggleCompactMode;
  final UiDensityMode uiDensityMode;
  final String? activeToolLabel;
  final IconData? activeToolIcon;

  const StudioTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
    required this.onOpenFile,
    this.onSaveDsf,
    required this.onSaveDdsProject,
    this.onCopySelection,
    this.onPasteClipboard,
    this.viewportLayoutMode = ViewportLayoutMode.split,
    this.onViewportLayoutModeChanged,
    this.isRibbonCollapsed = false,
    this.onToggleRibbon,
    this.isCompactMode = false,
    this.onToggleCompactMode,
    this.uiDensityMode = UiDensityMode.auto,
    this.activeToolLabel,
    this.activeToolIcon,
  });

  IconData _iconForFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dds')) return Icons.folder_special;
    if (lower.endsWith('.dxf')) return Icons.draw;
    return Icons.layers;
  }

  Color _colorForFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dds')) return const Color(0xFFD97706); // Amber for DDS assembly
    if (lower.endsWith('.dxf')) return const Color(0xFF059669); // Emerald for DXF
    return const Color(0xFF0284C7); // Sky Blue for DSF
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0),
        border: Border(
          bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Scrollable Tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isActive = index == activeIndex;
                final fileIcon = _iconForFileName(tab.displayTitle);
                final fileColor = _colorForFileName(tab.displayTitle);

                return InkWell(
                  onTap: () => onSelectTab(index),
                  child: Container(
                    margin: const EdgeInsets.only(top: 3, right: 2),
                    constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : const Color(0xFFF1F5F9),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        topRight: Radius.circular(6),
                      ),
                      border: Border.all(
                        color: const Color(0xFFCBD5E1),
                        width: 0.8,
                      ),
                      boxShadow: isActive
                          ? [
                              const BoxShadow(
                                color: Color(0x0A000000),
                                blurRadius: 3,
                                offset: Offset(0, -1),
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      children: [
                        if (isActive)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 2.5,
                            child: Container(
                              decoration: BoxDecoration(
                                color: fileColor,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(5),
                                  topRight: Radius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(fileIcon, size: 14, color: fileColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  tab.displayTitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                    color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (tab.isModified) ...[
                                const SizedBox(width: 4),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0284C7),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                              const SizedBox(width: 4),
                              // Close Tab Button
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => onCloseTab(index),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color: isActive ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Action Buttons on Right
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFFCBD5E1))),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // New Blank Tab (+)
                IconButton(
                  icon: const Icon(Icons.add, size: 16, color: Color(0xFF0284C7)),
                  tooltip: 'New Tab (Ctrl+T)',
                  onPressed: onNewTab,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                // Open File
                IconButton(
                  icon: const Icon(Icons.file_open_outlined, size: 16, color: Color(0xFF0F172A)),
                  tooltip: 'Open .dsf, .dxf, or .dds file (Ctrl+O)',
                  onPressed: onOpenFile,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                // Save Active Part (.dsf)
                if (onSaveDsf != null)
                  IconButton(
                    icon: const Icon(Icons.save_outlined, size: 16, color: Color(0xFF0284C7)),
                    tooltip: 'Save Part to .dsf (Ctrl+S)',
                    onPressed: onSaveDsf,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                // Save/Export DDS Project
                IconButton(
                  icon: const Icon(Icons.archive_outlined, size: 16, color: Color(0xFFD97706)),
                  tooltip: 'Save All Tabs to .dds (Danish Data Sheet Project)',
                  onPressed: onSaveDdsProject,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                if (onCopySelection != null)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 15, color: Color(0xFF475569)),
                    tooltip: 'Copy Feature across files (Ctrl+C)',
                    onPressed: onCopySelection,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                if (onPasteClipboard != null)
                  IconButton(
                    icon: Icon(
                      Icons.paste,
                      size: 15,
                      color: StudioClipboardService.hasContent
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF94A3B8),
                    ),
                    tooltip: StudioClipboardService.hasContent
                        ? 'Paste ${StudioClipboardService.currentLabel} (Ctrl+V)'
                        : 'Paste (Ctrl+V)',
                    onPressed: onPasteClipboard,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),

                // Active tool indicator when ribbon is collapsed
                if (isRibbonCollapsed && activeToolLabel != null) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (activeToolIcon != null) ...[
                          Icon(activeToolIcon, size: 12, color: const Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          activeToolLabel!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Vertical Divider
                Container(
                  height: 18,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: const Color(0xFFCBD5E1),
                ),

                // Viewport Layout Mode Selector Pill
                if (onViewportLayoutModeChanged != null) ...[
                  Container(
                    height: 25,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLayoutPill(
                          mode: ViewportLayoutMode.canvas2D,
                          icon: Icons.crop_square_rounded,
                          label: '2D',
                          tooltip: '2D Flat Pattern Only (F2)',
                        ),
                        _buildLayoutPill(
                          mode: ViewportLayoutMode.split,
                          icon: Icons.vertical_split_rounded,
                          label: 'Split',
                          tooltip: 'Dual Split Viewport (F3)',
                        ),
                        _buildLayoutPill(
                          mode: ViewportLayoutMode.viewport3D,
                          icon: Icons.view_in_ar_rounded,
                          label: '3D',
                          tooltip: '3D Folded Mesh Only (F4)',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                // UI Density / Scale Preset Button
                if (onToggleCompactMode != null)
                  Tooltip(
                    message: 'UI Density: ${uiDensityMode.label} (${(isCompactMode ? 85 : 100)}% scale) - Click to cycle',
                    child: IconButton(
                      icon: Icon(
                        uiDensityMode == UiDensityMode.compact
                            ? Icons.compress_rounded
                            : (uiDensityMode == UiDensityMode.auto ? Icons.laptop_chromebook_rounded : Icons.desktop_windows_rounded),
                        size: 15,
                        color: isCompactMode ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                      ),
                      onPressed: onToggleCompactMode,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    ),
                  ),

                // Minimize / Expand Ribbon Chevron Button
                if (onToggleRibbon != null)
                  IconButton(
                    icon: Icon(
                      isRibbonCollapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                      size: 18,
                      color: isRibbonCollapsed ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                    ),
                    tooltip: isRibbonCollapsed
                        ? 'Expand Ribbon Toolbar (F1 / Ctrl+Shift+R)'
                        : 'Minimize Ribbon Toolbar (F1 / Ctrl+Shift+R)',
                    onPressed: onToggleRibbon,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutPill({
    required ViewportLayoutMode mode,
    required IconData icon,
    required String label,
    required String tooltip,
  }) {
    final isSelected = viewportLayoutMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onViewportLayoutModeChanged?.call(mode),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0284C7) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
