// =============================================================================
// CanvasLegendMixin
//
// Provides the compact layer legend, micro-legend items, tool-button helper,
// and snap-menu-item helper for _UnfoldedCanvasWidgetState.
// Extracted from unfolded_canvas_widget.dart.
// =============================================================================

part of '../unfolded_canvas_widget.dart';

/// Mixin that contributes legend + toolbar-button helper widgets to
/// [_UnfoldedCanvasWidgetState].
mixin CanvasLegendMixin on State<UnfoldedCanvasWidget> {
  bool _isLegendCollapsed = false;
  bool _showProfileFill = true;
  bool _showPoints = true;
  bool _showGrid = true;

  // ---------------------------------------------------------------------------
  // Compact Layer Legend
  // ---------------------------------------------------------------------------

  Widget _buildCompactLegend() {
    if (_isLegendCollapsed) {
      return InkWell(
        onTap: () => setState(() => _isLegendCollapsed = false),
        borderRadius: BorderRadius.circular(4),
        child: Tooltip(
          message: 'Layer Legend (Click to expand)',
          child: Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2.5),
                Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0284C7),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2.5),
                Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD97706),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2.5),
                Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF059669),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _microLegendItem('Cut', const Color(0xFF0F172A)),
          const SizedBox(width: 4),
          _microLegendItem('Up', const Color(0xFF0284C7)),
          const SizedBox(width: 4),
          _microLegendItem('Dn', const Color(0xFFD97706)),
          const SizedBox(width: 4),
          _microLegendItem('Hole', const Color(0xFF059669)),
          const SizedBox(width: 4),
          _microLegendItem('Coupler', const Color(0xFF7C3AED)),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => _isLegendCollapsed = true),
            borderRadius: BorderRadius.circular(2),
            child: const Tooltip(
              message: 'Collapse legend',
              child: Icon(Icons.close, size: 9.5, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _microLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3.5,
          height: 3.5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 7.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tool-ribbon button helper
  // ---------------------------------------------------------------------------

  Widget _toolButton({
    IconData? icon,
    Widget? customIcon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            customIcon ??
                Icon(
                  icon,
                  size: 13,
                  color: active
                      ? const Color(0xFF0284C7)
                      : const Color(0xFF475569),
                ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? const Color(0xFF0284C7)
                    : const Color(0xFF475569),
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Snap-menu item helper
  // ---------------------------------------------------------------------------

  PopupMenuItem<SnapType> _snapMenuItem(
    SnapType type,
    String title,
    bool enabled,
  ) {
    return PopupMenuItem<SnapType>(
      value: type,
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: enabled ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
