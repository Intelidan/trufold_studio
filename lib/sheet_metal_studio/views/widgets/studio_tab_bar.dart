// =============================================================================
// studio_tab_bar.dart
//
// Multi-File Tab Bar for Danish FormMatrix Studio.
// Allows managing multiple open files (.dsf, .dxf, .dds), switching active
// workspaces, closing tabs, creating new blank parts, and saving project containers.
// =============================================================================

import 'package:flutter/material.dart';
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
                final fileIcon = _iconForFileName(tab.title);
                final fileColor = _colorForFileName(tab.title);

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
                                  tab.title,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
