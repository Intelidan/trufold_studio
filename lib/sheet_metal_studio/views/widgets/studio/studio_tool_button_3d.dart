// =============================================================================
// studio_tool_button_3d.dart
//
// Static CAD Ribbon Toolbar Button with Frosty Glass 3D Animated Tooltip.
// Features:
// - Calm, static toolbar buttons on the ribbon (no distracting in-place animations)
// - Popup tooltip with a sleek frosted glass background (BackdropFilter blur)
// - Large continuously animated isometric 3D action simulation
// - Prominently displays the tool name and keyboard shortcut
// - Accurately positioned directly beneath the tool button
// - Immediately dismisses on click or mouse exit
// =============================================================================

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'studio_3d_tool_icons.dart';

class Studio3DToolButton extends StatefulWidget {
  final Tool3DType toolType;
  final IconData fallbackIcon;
  final String label;
  final String? shortcut;
  final String description;
  final bool isActive;
  final VoidCallback onTap;
  final Color? activeColor;
  final double size;
  final String? tip;

  const Studio3DToolButton({
    super.key,
    required this.toolType,
    required this.fallbackIcon,
    required this.label,
    this.shortcut,
    required this.description,
    required this.isActive,
    required this.onTap,
    this.activeColor,
    this.size = 42.0,
    this.tip,
  });

  @override
  State<Studio3DToolButton> createState() => _Studio3DToolButtonState();
}

class _Studio3DToolButtonState extends State<Studio3DToolButton> {
  final OverlayPortalController _tooltipController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();

  Timer? _hoverTimer;
  bool _isHovered = false;

  void _onEnter() {
    setState(() => _isHovered = true);
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted && _isHovered) {
        _tooltipController.show();
      }
    });
  }

  void _onExit() {
    setState(() => _isHovered = false);
    _hoverTimer?.cancel();
    if (_tooltipController.isShowing) {
      _tooltipController.hide();
    }
  }

  void _onTap() {
    _hoverTimer?.cancel();
    if (_tooltipController.isShowing) {
      _tooltipController.hide();
    }
    widget.onTap();
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actCol = widget.activeColor ?? const Color(0xFF0284C7);

    return OverlayPortal(
      controller: _tooltipController,
      overlayChildBuilder: _buildTooltipOverlay,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: MouseRegion(
          onEnter: (_) => _onEnter(),
          onExit: (_) => _onExit(),
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: _onTap,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.size,
              height: widget.size,
              margin: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 1.0),
              decoration: BoxDecoration(
                color: widget.isActive ? actCol.withValues(alpha: 0.16) : (_isHovered ? const Color(0xFFF1F5F9) : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isActive ? actCol : (_isHovered ? const Color(0xFF94A3B8) : const Color(0xFFE2E8F0)),
                  width: widget.isActive ? 1.5 : 0.8,
                ),
                boxShadow: widget.isActive
                    ? [BoxShadow(color: actCol.withValues(alpha: 0.22), blurRadius: 6, offset: const Offset(0, 1.5))]
                    : (_isHovered ? [const BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))] : null),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Static CAD Ribbon Icon (Peaceful & static on the ribbon toolbar)
                  Tool3DActionIcon(
                    toolType: widget.toolType,
                    isHovered: false, // STATIC on toolbar ribbon!
                    isActive: widget.isActive,
                    size: widget.size * 0.68,
                    primaryColor: widget.isActive ? actCol : const Color(0xFF334155),
                  ),

                  // Fallback / Semantic Icon widget for tests and screen readers
                  Positioned.fill(
                    child: Center(
                      child: Icon(widget.fallbackIcon, size: widget.size * 0.55, color: Colors.transparent),
                    ),
                  ),

                  // Active status indicator pill at bottom
                  if (widget.isActive)
                    Positioned(
                      bottom: 2,
                      child: Container(
                        width: 14,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: actCol,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [BoxShadow(color: actCol.withValues(alpha: 0.8), blurRadius: 3)],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the popup tooltip box with frosted glass background (BackdropFilter blur),
  /// displaying the large animated 3D action simulation and the tool's name directly beneath the button.
  Widget _buildTooltipOverlay(BuildContext context) {
    final actCol = widget.activeColor ?? const Color(0xFF0284C7);
    const double iconSize = 66.0;

    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _layerLink,
        targetAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.topCenter,
        offset: const Offset(0, 6),
        showWhenUnlinked: false,
        child: IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 1.2),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Large Animated 3D Action Simulation Icon
                    SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: Center(
                        child: Tool3DActionIcon(
                          toolType: widget.toolType,
                          isHovered: true, // Smoothly loops 3D mechanical animation!
                          isActive: true,
                          size: iconSize,
                          primaryColor: actCol,
                        ),
                      ),
                    ),

                    const SizedBox(height: 5),

                    // Name of the Tool with Optional Shortcut Pill
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.1),
                        ),
                        if (widget.shortcut != null && widget.shortcut!.isNotEmpty) ...[
                          const SizedBox(width: 4.5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3), width: 0.6),
                            ),
                            child: Text(
                              widget.shortcut!,
                              style: const TextStyle(color: Color(0xFF0284C7), fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
