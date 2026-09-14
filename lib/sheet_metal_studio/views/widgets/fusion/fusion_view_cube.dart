// =============================================================================
// fusion_view_cube.dart
//
// Autodesk Fusion 360 ViewCube widget for TruFold Studio 3D Viewport.
// Displays the top-right 3D orientation cube with FRONT face, Z/X compass axes,
// Home isometric icon, and interactive camera perspective switching.
// =============================================================================

import 'package:flutter/material.dart';

class FusionViewCube extends StatefulWidget {
  final VoidCallback? onResetView;
  final void Function(double azimuth, double elevation)? onSetView;

  const FusionViewCube({
    super.key,
    this.onResetView,
    this.onSetView,
  });

  @override
  State<FusionViewCube> createState() => _FusionViewCubeState();
}

class _FusionViewCubeState extends State<FusionViewCube> {
  bool _isHovered = false;
  String? _hoveredRegion;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _hoveredRegion = null;
      }),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _isHovered ? 0.95 : 0.82),
          shape: BoxShape.circle,
          border: Border.all(
            color: _isHovered ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Home / ISO button (Top Left)
            Positioned(
              top: 4,
              left: 4,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hoveredRegion = 'home'),
                onExit: (_) => setState(() => _hoveredRegion = null),
                child: GestureDetector(
                  onTap: () {
                    if (widget.onSetView != null) {
                      widget.onSetView!(45, 30);
                    } else {
                      widget.onResetView?.call();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _hoveredRegion == 'home'
                          ? const Color(0xFFE0F2FE)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.home,
                      size: 11,
                      color: _hoveredRegion == 'home'
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),

            // Compass Axes
            // Z Axis (Blue up) - Click for TOP view
            Positioned(
              top: 3,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hoveredRegion = 'top'),
                onExit: (_) => setState(() => _hoveredRegion = null),
                child: GestureDetector(
                  onTap: () => widget.onSetView?.call(0, 89),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Z (TOP)',
                        style: TextStyle(
                          color: _hoveredRegion == 'top'
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFF3B82F6),
                          fontSize: 7.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_up,
                        size: 10,
                        color: _hoveredRegion == 'top'
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFF3B82F6),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // X Axis (Red right) - Click for RIGHT / SIDE view
            Positioned(
              right: 2,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hoveredRegion = 'right'),
                onExit: (_) => setState(() => _hoveredRegion = null),
                child: GestureDetector(
                  onTap: () => widget.onSetView?.call(90, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_right,
                        size: 10,
                        color: _hoveredRegion == 'right'
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFFEF4444),
                      ),
                      Text(
                        'X',
                        style: TextStyle(
                          color: _hoveredRegion == 'right'
                              ? const Color(0xFFB91C1C)
                              : const Color(0xFFEF4444),
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Isometric / Orthogonal Cube Box - Click for FRONT view
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hoveredRegion = 'front'),
              onExit: (_) => setState(() => _hoveredRegion = null),
              child: GestureDetector(
                onTap: () => widget.onSetView?.call(0, 0),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _hoveredRegion == 'front'
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: _hoveredRegion == 'front'
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF94A3B8),
                      width: 1.0,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'FRONT',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: _hoveredRegion == 'front'
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF334155),
                      letterSpacing: 0.4,
                    ),
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
