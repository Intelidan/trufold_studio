// Onshape Toolbar Widgets & Dropdown Menus
// TruFold Assembly Studio - Phase 7 Onshape Transformation
// Implements exact Onshape tool buttons, split caret buttons,
// responsive unpacking (SS1/SS2 vs PDF sub-menus), and live search dropdowns.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../viewmodels/assembly_studio_viewmodel.dart';
import '../../theme/assembly_studio_theme.dart';
import '../../../models/onshape_toolbar_items.dart';

/// Helper widget to render an Onshape SVG icon with fallback and state coloring
class OnshapeIconWidget extends StatelessWidget {
  final String assetPath;
  final double size;
  final bool isEnabled;
  final bool isActive;

  const OnshapeIconWidget({
    super.key,
    required this.assetPath,
    this.size = 20.0,
    this.isEnabled = true,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOpacity = isEnabled ? 1.0 : 0.35;

    return Opacity(
      opacity: effectiveOpacity,
      child: SvgPicture.asset(
        assetPath,
        width: size,
        height: size,
        placeholderBuilder: (ctx) => SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standalone tool button without a dropdown caret (or an unpacked tool from a group)
class OnshapeToolButton extends StatefulWidget {
  final OnshapeToolItem item;
  final AssemblyStudioViewModel viewModel;
  final VoidCallback? onCustomTap;

  const OnshapeToolButton({
    super.key,
    required this.item,
    required this.viewModel,
    this.onCustomTap,
  });

  @override
  State<OnshapeToolButton> createState() => _OnshapeToolButtonState();
}

class _OnshapeToolButtonState extends State<OnshapeToolButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final vm = widget.viewModel;
    final isEnabled = item.isImplemented;
    final isActive = item.isActive?.call(vm) ?? false;

    final tooltipMsg = isEnabled
        ? (item.shortcut.isNotEmpty ? '${item.label} (${item.shortcut})' : item.label)
        : '${item.label} (Not yet implemented)';

    return Tooltip(
      message: tooltipMsg,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: isEnabled
              ? () {
                  if (widget.onCustomTap != null) {
                    widget.onCustomTap!();
                  } else {
                    item.onExecute?.call(vm, context);
                  }
                }
              : () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${item.label} is scheduled for an upcoming release'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      width: 280,
                    ),
                  );
                },
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFFE0EDFF)
                  : (_isHovered && isEnabled ? const Color(0xFFE4E7EC) : Colors.transparent),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF2F80ED)
                    : (_isHovered && isEnabled ? const Color(0xFFCBD5E1) : Colors.transparent),
                width: 1.0,
              ),
            ),
            child: Center(
              child: OnshapeIconWidget(
                assetPath: item.assetPath,
                size: 20,
                isEnabled: isEnabled,
                isActive: isActive,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Authentic Onshape Split Button: Tool Icon on the left + dropdown Caret on the right.
/// Selecting an item from the dropdown promotes it to the primary button.
class OnshapeToolbarSplitButton extends StatefulWidget {
  final OnshapeToolGroup group;
  final OnshapeToolItem primaryItem;
  final ValueChanged<OnshapeToolItem> onSelectTool;
  final AssemblyStudioViewModel viewModel;
  final bool hasDropdown;

  const OnshapeToolbarSplitButton({
    super.key,
    required this.group,
    required this.primaryItem,
    required this.onSelectTool,
    required this.viewModel,
    this.hasDropdown = true,
  });

  @override
  State<OnshapeToolbarSplitButton> createState() => _OnshapeToolbarSplitButtonState();
}

class _OnshapeToolbarSplitButtonState extends State<OnshapeToolbarSplitButton> {
  bool _isMainHovered = false;
  bool _isCaretHovered = false;
  bool _isMenuOpen = false;

  void _openDropdown(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    setState(() => _isMenuOpen = true);

    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return Stack(
          children: [
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 2,
              child: _OnshapeDropdownCard(
                group: widget.group,
                currentSelectedId: widget.primaryItem.id,
                onSelect: (selected) {
                  Navigator.of(ctx).pop();
                  widget.onSelectTool(selected);
                  if (selected.isImplemented) {
                    selected.onExecute?.call(widget.viewModel, context);
                  }
                },
              ),
            ),
          ],
        );
      },
    );

    if (mounted) {
      setState(() => _isMenuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.primaryItem;
    final vm = widget.viewModel;
    final isEnabled = item.isImplemented;
    final isActive = item.isActive?.call(vm) ?? false;

    final tooltipMsg = isEnabled
        ? (item.shortcut.isNotEmpty ? '${item.label} (${item.shortcut})' : item.label)
        : '${item.label} (Not yet implemented)';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Primary Tool Action Button
        Tooltip(
          message: tooltipMsg,
          waitDuration: const Duration(milliseconds: 300),
          child: MouseRegion(
            cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _isMainHovered = true),
            onExit: (_) => setState(() => _isMainHovered = false),
            child: GestureDetector(
              onTap: isEnabled
                  ? () => item.onExecute?.call(vm, context)
                  : () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${item.label} is scheduled for an upcoming release'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                          width: 280,
                        ),
                      );
                    },
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFE0EDFF)
                      : (_isMainHovered && isEnabled ? const Color(0xFFE4E7EC) : Colors.transparent),
                  borderRadius: BorderRadius.horizontal(
                    left: const Radius.circular(3),
                    right: widget.hasDropdown ? Radius.zero : const Radius.circular(3),
                  ),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF2F80ED)
                        : (_isMainHovered && isEnabled ? const Color(0xFFCBD5E1) : Colors.transparent),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: OnshapeIconWidget(
                    assetPath: item.assetPath,
                    size: 20,
                    isEnabled: isEnabled,
                    isActive: isActive,
                  ),
                ),
              ),
            ),
          ),
        ),

        // 2. Dropdown Caret Button
        if (widget.hasDropdown)
          Builder(
            builder: (caretContext) {
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _isCaretHovered = true),
                onExit: (_) => setState(() => _isCaretHovered = false),
                child: GestureDetector(
                  onTap: () => _openDropdown(caretContext),
                  child: Container(
                    height: 28,
                    width: 13,
                    decoration: BoxDecoration(
                      color: _isMenuOpen || _isCaretHovered ? const Color(0xFFE4E7EC) : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                      border: Border.all(
                        color: _isMenuOpen || _isCaretHovered ? const Color(0xFFCBD5E1) : Colors.transparent,
                        width: 1.0,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.arrow_drop_down,
                        size: 14,
                        color: _isMenuOpen || _isCaretHovered ? const Color(0xFF1D2939) : const Color(0xFF475467),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Authentic Onshape Dropdown Card matching preview_all_icons.html & Onshape CAD
class _OnshapeDropdownCard extends StatefulWidget {
  final OnshapeToolGroup group;
  final String currentSelectedId;
  final ValueChanged<OnshapeToolItem> onSelect;

  const _OnshapeDropdownCard({
    required this.group,
    required this.currentSelectedId,
    required this.onSelect,
  });

  @override
  State<_OnshapeDropdownCard> createState() => _OnshapeDropdownCardState();
}

class _OnshapeDropdownCardState extends State<_OnshapeDropdownCard> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _filter = _searchCtrl.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = widget.group.items.where((it) {
      if (_filter.isEmpty) return true;
      return it.label.toLowerCase().contains(_filter) || it.shortcut.toLowerCase().contains(_filter);
    }).toList();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 260,
        constraints: const BoxConstraints(maxHeight: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFB0B7C3), width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search Tools input box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEAECF0), width: 1.0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: Color(0xFF667085)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF1D2939)),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Search tools...',
                        hintStyle: TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Tools List
            Flexible(
              child: filteredItems.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No matching tools',
                          style: TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filteredItems.length,
                      itemBuilder: (ctx, idx) {
                        final item = filteredItems[idx];
                        final isSelected = item.id == widget.currentSelectedId;
                        return _OnshapeDropdownMenuItem(
                          item: item,
                          isSelected: isSelected,
                          onTap: () => widget.onSelect(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnshapeDropdownMenuItem extends StatefulWidget {
  final OnshapeToolItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _OnshapeDropdownMenuItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_OnshapeDropdownMenuItem> createState() => _OnshapeDropdownMenuItemState();
}

class _OnshapeDropdownMenuItemState extends State<_OnshapeDropdownMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isEnabled = item.isImplemented;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: _isHovered && isEnabled
              ? const Color(0xFFEEF4FF)
              : (widget.isSelected ? const Color(0xFFF1F5F9) : Colors.transparent),
          child: Row(
            children: [
              OnshapeIconWidget(
                assetPath: item.assetPath,
                size: 20,
                isEnabled: isEnabled,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isEnabled ? const Color(0xFF101828) : const Color(0xFF98A2B3),
                  ),
                ),
              ),
              if (item.shortcut.isNotEmpty)
                _buildShortcutBadge(item.shortcut, isEnabled),
              if (widget.isSelected) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check, size: 14, color: AssemblyStudioTheme.onshapeBlue),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutBadge(String shortcut, bool isEnabled) {
    final parts = shortcut.split('+');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: parts.map((p) {
        return Container(
          margin: const EdgeInsets.only(left: 3),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F4F7),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFFD0D5DD), width: 1.0),
          ),
          child: Text(
            p.toLowerCase(),
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: isEnabled ? const Color(0xFF344054) : const Color(0xFF98A2B3),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Standard Onshape Toolbar Vertical Divider
class OnshapeToolbarDivider extends StatelessWidget {
  const OnshapeToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1.0,
      height: 22.0,
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      color: const Color(0xFFD0D5DD),
    );
  }
}
