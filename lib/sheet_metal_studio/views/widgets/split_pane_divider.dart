// =============================================================================
// split_pane_divider.dart
//
// Interactive Draggable Split-Pane Divider between 2D and 3D Viewports.
// Supports drag-to-resize, double-click reset to 50/50, and hover indicators.
// Light CAD theme with Sky Blue accent.
// =============================================================================

import 'package:flutter/material.dart';

class SplitPaneDivider extends StatefulWidget {
  final double splitRatio;
  final ValueChanged<double> onRatioChanged;
  final VoidCallback? onDoubleTapReset;

  const SplitPaneDivider({super.key, required this.splitRatio, required this.onRatioChanged, this.onDoubleTapReset});

  @override
  State<SplitPaneDivider> createState() => _SplitPaneDividerState();
}

class _SplitPaneDividerState extends State<SplitPaneDivider> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _isHovered || _isDragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTapReset,
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
        onHorizontalDragCancel: () => setState(() => _isDragging = false),
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          final parentBox = box?.parent as RenderBox?;
          if (parentBox != null && parentBox.size.width > 0) {
            final deltaRatio = details.delta.dx / parentBox.size.width;
            widget.onRatioChanged(widget.splitRatio + deltaRatio);
          }
        },
        child: Container(
          width: 14.0,
          color: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 4.0 : 2.0,
              height: double.infinity,
              color: active ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
              child: Center(
                child: Container(
                  width: active ? 8.0 : 6.0,
                  height: 48.0,
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4.0),
                    boxShadow: active ? [BoxShadow(color: const Color(0xFF0284C7).withValues(alpha: 0.4), blurRadius: 8.0, spreadRadius: 1.0)] : null,
                  ),
                  child: Center(child: Icon(Icons.drag_indicator, size: 14.0, color: active ? Colors.white : const Color(0xFF475569))),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
