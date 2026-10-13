// =============================================================================
// studio_view_cube.dart
//
// Onshape-style Interactive 3D Orientation ViewCube with Micro Camera Controls
// and Context Menu for TruFold Studio 3D Viewport.
// Matches Onshape CAD reference:
// - Seamless 3D orientation cube with TitleCase face plates (Top, Front, Right...)
// - Integrated 3D coordinate triad (Red X, Green Y, Blue Z) at cube corner
// - Sleek micro camera navigation chevrons (Up, Down, Left, Right)
// - Top curved roll arc with double arrowheads (Roll CCW & Roll CW)
// - Miniature cube dropdown button [ ◰ ▾ ] with Onshape view and edge options
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/cad_primitives.dart';

class StudioViewCube extends StatefulWidget {
  final double azimuthDeg;
  final double elevationDeg;
  final VoidCallback? onResetView;
  final void Function(double azimuth, double elevation)? onSetView;
  final void Function(double dAzimuth, double dElevation)? onOrbit;
  final VoidCallback? onZoomToFit;
  final bool isPerspective;
  final VoidCallback? onTogglePerspective;
  final OnshapeRenderMode renderMode;
  final ValueChanged<OnshapeRenderMode>? onRenderModeChanged;
  final bool hiddenEdgesVisible;
  final ValueChanged<bool>? onToggleHiddenEdges;
  final OnshapeTangentEdgeMode tangentEdgeMode;
  final ValueChanged<OnshapeTangentEdgeMode>? onTangentEdgeModeChanged;
  final VoidCallback? onOpenGraphicsPreferences;
  final VoidCallback? onRollCw;
  final VoidCallback? onRollCcw;
  final bool isHighQuality;
  final VoidCallback? onToggleHighQuality;
  final double size;

  // Onshape Model Visualization Additions:
  final bool is3dRotateLocked;
  final VoidCallback? onToggle3dRotateLock;
  final VoidCallback? onPreviousView;
  final bool hasPreviousView;
  final VoidCallback? onOrientNormal;
  final bool highlightBoundaryEdges;
  final VoidCallback? onToggleHighlightBoundaryEdges;
  final bool isSectionViewActive;
  final VoidCallback? onToggleSectionView;
  final VoidCallback? onNamedViews;
  final VoidCallback? onZoomToSelection;

  const StudioViewCube({
    super.key,
    required this.azimuthDeg,
    required this.elevationDeg,
    this.onResetView,
    this.onSetView,
    this.onOrbit,
    this.onZoomToFit,
    this.isPerspective = true,
    this.onTogglePerspective,
    this.renderMode = OnshapeRenderMode.shadedWithEdges,
    this.onRenderModeChanged,
    this.hiddenEdgesVisible = false,
    this.onToggleHiddenEdges,
    this.tangentEdgeMode = OnshapeTangentEdgeMode.phantom,
    this.onTangentEdgeModeChanged,
    this.onOpenGraphicsPreferences,
    this.onRollCw,
    this.onRollCcw,
    this.isHighQuality = false,
    this.onToggleHighQuality,
    this.size = 80.0,
    this.is3dRotateLocked = false,
    this.onToggle3dRotateLock,
    this.onPreviousView,
    this.hasPreviousView = false,
    this.onOrientNormal,
    this.highlightBoundaryEdges = false,
    this.onToggleHighlightBoundaryEdges,
    this.isSectionViewActive = false,
    this.onToggleSectionView,
    this.onNamedViews,
    this.onZoomToSelection,
  });

  @override
  State<StudioViewCube> createState() => _StudioViewCubeState();
}

class _StudioViewCubeState extends State<StudioViewCube> {
  Offset? _mousePos;
  String? _hoveredFace;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    const totalW = 126.0;
    const totalH = 132.0;

    return SizedBox(
      width: totalW,
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 0. Onshape 3D Rotate Lock Toggle Button
          Positioned(
            top: 2,
            left: 2,
            child: Tooltip(
              message: widget.is3dRotateLocked ? 'Unlock 3D rotation' : 'Lock 3D rotation',
              child: InkWell(
                onTap: widget.onToggle3dRotateLock,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: widget.is3dRotateLocked
                        ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: widget.is3dRotateLocked ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                      width: 1.0,
                    ),
                  ),
                  child: Icon(
                    widget.is3dRotateLocked ? Icons.lock : Icons.lock_open_outlined,
                    size: 12,
                    color: widget.is3dRotateLocked ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),

          // 1. Top Curved Double-Arrow Roll Arc
          Positioned(
            top: 2,
            left: 24,
            right: 20,
            height: 26,
            child: _RollArcWidget(
              onRollCcw: () {
                if (widget.onRollCcw != null) {
                  widget.onRollCcw!();
                } else {
                  widget.onOrbit?.call(-15, 0);
                }
              },
              onRollCw: () {
                if (widget.onRollCw != null) {
                  widget.onRollCw!();
                } else {
                  widget.onOrbit?.call(15, 0);
                }
              },
            ),
          ),

          // 2. Micro Navigation Chevrons (Up, Down, Left, Right)
          // Top Chevron (Tilt Up)
          Positioned(
            top: 2,
            left: (totalW - 20) / 2.0,
            width: 20,
            height: 18,
            child: _NavChevron(direction: AxisDirection.up, tooltip: 'Tilt Up (15°)', onTap: () => widget.onOrbit?.call(0, 15)),
          ),

          // Bottom Chevron (Tilt Down)
          Positioned(
            bottom: 24,
            left: (totalW - 20) / 2.0,
            width: 20,
            height: 18,
            child: _NavChevron(direction: AxisDirection.down, tooltip: 'Tilt Down (15°)', onTap: () => widget.onOrbit?.call(0, -15)),
          ),

          // Left Chevron (Rotate Left)
          Positioned(
            top: (totalH - 40) / 2.0,
            left: 2,
            width: 18,
            height: 20,
            child: _NavChevron(direction: AxisDirection.left, tooltip: 'Rotate Left (15°)', onTap: () => widget.onOrbit?.call(-15, 0)),
          ),

          // Right Chevron (Rotate Right)
          Positioned(
            top: (totalH - 40) / 2.0,
            right: 2,
            width: 18,
            height: 20,
            child: _NavChevron(direction: AxisDirection.right, tooltip: 'Rotate Right (15°)', onTap: () => widget.onOrbit?.call(15, 0)),
          ),

          // 3. Center: Interactive 3D View Cube
          Positioned(
            top: 22,
            left: (totalW - widget.size) / 2.0,
            width: widget.size,
            height: widget.size,
            child: MouseRegion(
              onHover: (event) {
                setState(() {
                  _mousePos = event.localPosition;
                });
              },
              onExit: (_) {
                setState(() {
                  _mousePos = null;
                  _hoveredFace = null;
                });
              },
              cursor: _isDragging ? SystemMouseCursors.grabbing : (_hoveredFace != null ? SystemMouseCursors.click : SystemMouseCursors.grab),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => setState(() => _isDragging = true),
                onPanUpdate: (details) {
                  widget.onOrbit?.call(-details.delta.dx * 0.75, details.delta.dy * 0.75);
                },
                onPanEnd: (_) => setState(() => _isDragging = false),
                onTap: () {
                  if (_hoveredFace != null && widget.onSetView != null) {
                    _snapToFace(_hoveredFace!);
                  }
                },
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _ViewCubePainter(
                    azimuthDeg: widget.azimuthDeg,
                    elevationDeg: widget.elevationDeg,
                    mousePos: _mousePos,
                    onHoverFaceChanged: (face) {
                      if (_hoveredFace != face) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _hoveredFace = face);
                        });
                      }
                    },
                  ),
                ),
              ),
            ),
          ),

          // 4. Miniature Context Menu Cube Button [ ◰ ▾ ] Underneath Right
          Positioned(bottom: 0, right: 8, child: _buildContextMenuButton(context)),
        ],
      ),
    );
  }

  Widget _buildContextMenuButton(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Camera & Display Preferences',
      offset: const Offset(-180, 24),
      padding: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar_rounded, size: 14, color: Color(0xFF334155)),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 13, color: Color(0xFF64748B)),
          ],
        ),
      ),
      onSelected: (value) => _handleMenuAction(value),
      itemBuilder: (context) => [
        // Standard views
        _buildMenuItem('iso', 'Isometric'),
        _buildMenuItem('dimetric', 'Dimetric'),
        _buildMenuItem('trimetric', 'Trimetric'),
        const PopupMenuDivider(height: 8),

        // Graphics preferences & fit
        _buildMenuItemWithIcon('graphics', 'Graphics preferences...', Icons.settings_outlined),
        _buildMenuItem('named_views', 'Named views...'),
        _buildMenuItem('previous_view', 'Previous view', isEnabled: widget.hasPreviousView),
        _buildMenuItem('fit', 'Zoom to fit (F)'),
        _buildMenuItem('zoom_selection', 'Zoom to selection'),
        _buildMenuItem('orient_normal', 'Orient normal to face (N)'),
        const PopupMenuDivider(height: 8),

        // Projection
        _buildCheckMenuItem('perspective', 'Perspective view', widget.isPerspective),
        const PopupMenuDivider(height: 8),

        // Render modes
        _buildCheckMenuItem('shaded_edges', 'Shaded with edges', widget.renderMode == OnshapeRenderMode.shadedWithEdges),
        _buildCheckMenuItem('shaded_no_edges', 'Shaded without edges', widget.renderMode == OnshapeRenderMode.shadedWithoutEdges),
        _buildCheckMenuItem('unshaded', 'Unshaded', widget.renderMode == OnshapeRenderMode.unshaded),
        _buildCheckMenuItem('translucent', 'Translucent', widget.renderMode == OnshapeRenderMode.translucent),
        const PopupMenuDivider(height: 8),

        // Hidden edges (SS5)
        _buildCheckMenuItem('hidden_edges_removed', 'Hidden edges removed', !widget.hiddenEdgesVisible),
        _buildCheckMenuItem('hidden_edges_visible', 'Hidden edges visible', widget.hiddenEdgesVisible),
        const PopupMenuDivider(height: 8),

        // Tangent edges (SS5)
        _buildCheckMenuItem('tangent_edges_visible', 'Tangent edges visible', widget.tangentEdgeMode == OnshapeTangentEdgeMode.visible),
        _buildCheckMenuItem('tangent_edges_phantom', 'Tangent edges phantom', widget.tangentEdgeMode == OnshapeTangentEdgeMode.phantom),
        _buildCheckMenuItem('tangent_edges_removed', 'Tangent edges removed', widget.tangentEdgeMode == OnshapeTangentEdgeMode.removed),
        const PopupMenuDivider(height: 8),

        // Quality, Boundary & Section View
        _buildCheckMenuItem('high_quality', 'View in high quality', widget.isHighQuality),
        _buildCheckMenuItem('highlight_boundary', 'Highlight boundary edges', widget.highlightBoundaryEdges),
        _buildCheckMenuItem('section_view', 'Section view...', widget.isSectionViewActive),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(String value, String text, {bool isEnabled = true}) {
    return PopupMenuItem<String>(
      value: value,
      height: 30,
      enabled: isEnabled,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isEnabled ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
          fontWeight: isEnabled ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItemWithIcon(String value, String text, IconData icon) {
    return PopupMenuItem<String>(
      value: value,
      height: 30,
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF0F172A)),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildCheckMenuItem(String value, String text, bool isChecked) {
    return PopupMenuItem<String>(
      value: value,
      height: 30,
      child: Row(
        children: [
          SizedBox(width: 18, child: isChecked ? const Icon(Icons.check, size: 14, color: Color(0xFF0284C7)) : null),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isChecked ? FontWeight.w600 : FontWeight.w500,
              color: isChecked ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String value) {
    switch (value) {
      case 'iso':
        widget.onSetView?.call(45, 35.26);
        break;
      case 'dimetric':
        widget.onSetView?.call(30, 20);
        break;
      case 'trimetric':
        widget.onSetView?.call(60, 25);
        break;
      case 'graphics':
        widget.onOpenGraphicsPreferences?.call();
        break;
      case 'named_views':
        widget.onNamedViews?.call();
        break;
      case 'previous_view':
        widget.onPreviousView?.call();
        break;
      case 'fit':
        widget.onZoomToFit?.call();
        break;
      case 'zoom_selection':
        widget.onZoomToSelection?.call();
        break;
      case 'orient_normal':
        widget.onOrientNormal?.call();
        break;
      case 'perspective':
        widget.onTogglePerspective?.call();
        break;
      case 'shaded_edges':
        widget.onRenderModeChanged?.call(OnshapeRenderMode.shadedWithEdges);
        break;
      case 'shaded_no_edges':
        widget.onRenderModeChanged?.call(OnshapeRenderMode.shadedWithoutEdges);
        break;
      case 'unshaded':
        widget.onRenderModeChanged?.call(OnshapeRenderMode.unshaded);
        break;
      case 'translucent':
        widget.onRenderModeChanged?.call(OnshapeRenderMode.translucent);
        break;
      case 'hidden_edges_removed':
        widget.onToggleHiddenEdges?.call(false);
        break;
      case 'hidden_edges_visible':
        widget.onToggleHiddenEdges?.call(true);
        break;
      case 'tangent_edges_visible':
        widget.onTangentEdgeModeChanged?.call(OnshapeTangentEdgeMode.visible);
        break;
      case 'tangent_edges_phantom':
        widget.onTangentEdgeModeChanged?.call(OnshapeTangentEdgeMode.phantom);
        break;
      case 'tangent_edges_removed':
        widget.onTangentEdgeModeChanged?.call(OnshapeTangentEdgeMode.removed);
        break;
      case 'high_quality':
        widget.onToggleHighQuality?.call();
        break;
      case 'highlight_boundary':
        widget.onToggleHighlightBoundaryEdges?.call();
        break;
      case 'section_view':
        widget.onToggleSectionView?.call();
        break;
    }
  }

  void _snapToFace(String face) {
    switch (face) {
      case 'Top':
        widget.onSetView?.call(0, 89.9);
        break;
      case 'Bottom':
        widget.onSetView?.call(0, -89.9);
        break;
      case 'Front':
        widget.onSetView?.call(0, 0);
        break;
      case 'Back':
        widget.onSetView?.call(180, 0);
        break;
      case 'Right':
        widget.onSetView?.call(90, 0);
        break;
      case 'Left':
        widget.onSetView?.call(-90, 0);
        break;
    }
  }
}

/// Triangular Navigation Chevron Arrow (matching Onshape SS3)
class _NavChevron extends StatefulWidget {
  final AxisDirection direction;
  final String tooltip;
  final VoidCallback onTap;

  const _NavChevron({required this.direction, required this.tooltip, required this.onTap});

  @override
  State<_NavChevron> createState() => _NavChevronState();
}

class _NavChevronState extends State<_NavChevron> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            painter: _ChevronPainter(direction: widget.direction, isHovered: _hovered),
          ),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  final AxisDirection direction;
  final bool isHovered;

  _ChevronPainter({required this.direction, required this.isHovered});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    final paint = Paint()
      ..color = isHovered ? const Color(0xFF0284C7) : const Color(0xFFD3E0EA)
      ..style = PaintingStyle.fill;

    final path = Path();
    switch (direction) {
      case AxisDirection.up:
        path.moveTo(cx, 1);
        path.lineTo(size.width - 2, size.height - 3);
        path.lineTo(2, size.height - 3);
        break;
      case AxisDirection.down:
        path.moveTo(cx, size.height - 1);
        path.lineTo(size.width - 2, 3);
        path.lineTo(2, 3);
        break;
      case AxisDirection.left:
        path.moveTo(1, cy);
        path.lineTo(size.width - 3, 2);
        path.lineTo(size.width - 3, size.height - 2);
        break;
      case AxisDirection.right:
        path.moveTo(size.width - 1, cy);
        path.lineTo(3, 2);
        path.lineTo(3, size.height - 2);
        break;
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) => old.isHovered != isHovered || old.direction != direction;
}

/// Double-headed Roll Arc Widget spanning across top of cube (matching Onshape SS3)
class _RollArcWidget extends StatefulWidget {
  final VoidCallback onRollCcw;
  final VoidCallback onRollCw;

  const _RollArcWidget({required this.onRollCcw, required this.onRollCw});

  @override
  State<_RollArcWidget> createState() => _RollArcWidgetState();
}

class _RollArcWidgetState extends State<_RollArcWidget> {
  int _hoverSide = 0; // -1 = left (CCW), 1 = right (CW), 0 = none

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return MouseRegion(
          onHover: (e) {
            final side = e.localPosition.dx < w / 2.0 ? -1 : 1;
            if (_hoverSide != side) setState(() => _hoverSide = side);
          },
          onExit: (_) => setState(() => _hoverSide = 0),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) {
              if (e.localPosition.dx < w / 2.0) {
                widget.onRollCcw();
              } else {
                widget.onRollCw();
              }
            },
            child: Tooltip(
              message: _hoverSide == -1 ? 'Roll CCW (15°)' : 'Roll CW (15°)',
              waitDuration: const Duration(milliseconds: 300),
              child: CustomPaint(
                size: Size(w, constraints.maxHeight),
                painter: _RollArcPainter(hoverSide: _hoverSide),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RollArcPainter extends CustomPainter {
  final int hoverSide; // -1, 0, 1

  _RollArcPainter({required this.hoverSide});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final defaultColor = const Color(0xFFD3E0EA);
    final hoverColor = const Color(0xFF0284C7);

    final leftPaint = Paint()
      ..color = (hoverSide == -1) ? hoverColor : defaultColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final rightPaint = Paint()
      ..color = (hoverSide == 1) ? hoverColor : defaultColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Draw curved arch
    final arcRect = Rect.fromLTWH(4, 4, w - 8, h * 2.2);
    canvas.drawArc(arcRect, math.pi * 1.15, math.pi * 0.35, false, leftPaint);
    canvas.drawArc(arcRect, math.pi * 1.50, math.pi * 0.35, false, rightPaint);

    // Left arrowhead (pointing down-left)
    final arrowLeft = Path()
      ..moveTo(4, 18)
      ..lineTo(0, 12)
      ..lineTo(8, 11)
      ..close();
    final arrowLeftPaint = Paint()
      ..color = (hoverSide == -1) ? hoverColor : defaultColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowLeft, arrowLeftPaint);

    // Right arrowhead (pointing down-right)
    final arrowRight = Path()
      ..moveTo(w - 4, 18)
      ..lineTo(w, 12)
      ..lineTo(w - 8, 11)
      ..close();
    final arrowRightPaint = Paint()
      ..color = (hoverSide == 1) ? hoverColor : defaultColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowRight, arrowRightPaint);
  }

  @override
  bool shouldRepaint(covariant _RollArcPainter old) => old.hoverSide != hoverSide;
}

class _CubeFaceData {
  final String label;
  final List<int> vertexIndices;
  final List<double> normal;

  const _CubeFaceData({required this.label, required this.vertexIndices, required this.normal});
}

class _ViewCubePainter extends CustomPainter {
  final double azimuthDeg;
  final double elevationDeg;
  final Offset? mousePos;
  final ValueChanged<String?> onHoverFaceChanged;

  _ViewCubePainter({required this.azimuthDeg, required this.elevationDeg, required this.mousePos, required this.onHoverFaceChanged});

  static const List<_CubeFaceData> _faces = [
    _CubeFaceData(label: 'Top', vertexIndices: [4, 5, 6, 7], normal: [0, 0, 1]),
    _CubeFaceData(label: 'Bottom', vertexIndices: [0, 3, 2, 1], normal: [0, 0, -1]),
    _CubeFaceData(label: 'Front', vertexIndices: [0, 1, 5, 4], normal: [0, -1, 0]),
    _CubeFaceData(label: 'Back', vertexIndices: [2, 6, 7, 3], normal: [0, 1, 0]),
    _CubeFaceData(label: 'Right', vertexIndices: [1, 2, 6, 5], normal: [1, 0, 0]),
    _CubeFaceData(label: 'Left', vertexIndices: [0, 4, 7, 3], normal: [-1, 0, 0]),
  ];

  static const List<List<double>> _cubeVertices = [
    [-1, -1, -1], // 0: -X, -Y, -Z
    [1, -1, -1], // 1: +X, -Y, -Z
    [1, 1, -1], // 2: +X, +Y, -Z
    [-1, 1, -1], // 3: -X, +Y, -Z
    [-1, -1, 1], // 4: -X, -Y, +Z
    [1, -1, 1], // 5: +X, -Y, +Z
    [1, 1, 1], // 6: +X, +Y, +Z
    [-1, 1, 1], // 7: -X, +Y, +Z
  ];

  static (double x, double y, double z) _projectPoint(double x, double y, double z, double cosAz, double sinAz, double cosEl, double sinEl) {
    // Camera basis vectors for Z-up turntable:
    // Right u: (cosAz, sinAz, 0)
    // Up v: (-sinEl * sinAz, sinEl * cosAz, cosEl)
    // View w (depth towards camera): (cosEl * sinAz, -cosEl * cosAz, sinEl)
    final x2 = x * cosAz + y * sinAz;
    final y2 = -x * sinEl * sinAz + y * sinEl * cosAz + z * cosEl;
    final z2 = x * cosEl * sinAz - y * cosEl * cosAz + z * sinEl;

    return (x2, y2, z2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final scale = size.width * 0.28;

    final azRad = azimuthDeg * math.pi / 180.0;
    final elRad = elevationDeg * math.pi / 180.0;

    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final projVertices = <Offset>[];
    final projDepths = <double>[];
    for (final v in _cubeVertices) {
      final (x2, y2, z2) = _projectPoint(v[0], v[1], v[2], cosAz, sinAz, cosEl, sinEl);
      projVertices.add(Offset(cx + x2 * scale, cy - y2 * scale));
      projDepths.add(z2);
    }

    final visibleFaces = <({_CubeFaceData face, Path path, double zDepth, Offset center, List<Offset> poly})>[];
    String? hitFace;

    for (final face in _faces) {
      final norm = _projectPoint(face.normal[0], face.normal[1], face.normal[2], cosAz, sinAz, cosEl, sinEl);

      // Face is visible if outward normal faces toward camera (z > 0.001)
      if (norm.$3 > 0.001) {
        final path = Path();
        final p0 = projVertices[face.vertexIndices[0]];
        path.moveTo(p0.dx, p0.dy);
        double avgX = p0.dx;
        double avgY = p0.dy;
        double sumDepth = projDepths[face.vertexIndices[0]];
        final polyPts = <Offset>[p0];

        for (int i = 1; i < face.vertexIndices.length; i++) {
          final idx = face.vertexIndices[i];
          final p = projVertices[idx];
          path.lineTo(p.dx, p.dy);
          avgX += p.dx;
          avgY += p.dy;
          sumDepth += projDepths[idx];
          polyPts.add(p);
        }
        path.close();

        final center = Offset(avgX / face.vertexIndices.length, avgY / face.vertexIndices.length);
        final avgZ = sumDepth / face.vertexIndices.length;
        visibleFaces.add((face: face, path: path, zDepth: avgZ, center: center, poly: polyPts));

        if (mousePos != null && path.contains(mousePos!)) {
          hitFace = face.label;
        }
      }
    }

    onHoverFaceChanged(hitFace);

    // Painter's algorithm: draw furthest faces first, nearest faces last
    visibleFaces.sort((a, b) => a.zDepth.compareTo(b.zDepth));

    for (final f in visibleFaces) {
      final isHovered = (hitFace == f.face.label);
      final normalZ = f.zDepth.clamp(0.0, 1.0);

      // Shaded cube bevel background
      final baseBgColor = Color.lerp(const Color(0xFFD8E3EB), const Color(0xFFCBD5E1), 1.0 - normalZ)!;

      final bgPaint = Paint()
        ..color = baseBgColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(f.path, bgPaint);

      // Inset Face Plate (White rounded plate matching Onshape SS3)
      final insetPath = Path();
      const insetFactor = 0.84;
      final insetPts = f.poly.map((p) => f.center + (p - f.center) * insetFactor).toList();

      if (insetPts.length >= 3) {
        insetPath.moveTo(insetPts[0].dx, insetPts[0].dy);
        for (int i = 1; i < insetPts.length; i++) {
          insetPath.lineTo(insetPts[i].dx, insetPts[i].dy);
        }
        insetPath.close();

        final platePaint = Paint()
          ..color = isHovered ? const Color(0xFFE0F2FE) : Colors.white
          ..style = PaintingStyle.fill;

        final plateBorder = Paint()
          ..color = isHovered ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)
          ..strokeWidth = isHovered ? 1.5 : 1.0
          ..style = PaintingStyle.stroke;

        canvas.drawPath(insetPath, platePaint);
        canvas.drawPath(insetPath, plateBorder);
      }

      // TitleCase Label: Top, Front, Right (matching Onshape SS3)
      final textSpan = TextSpan(
        text: f.face.label,
        style: TextStyle(
          color: isHovered ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          fontSize: 9.0,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.2,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();

      tp.paint(canvas, Offset(f.center.dx - tp.width / 2.0, f.center.dy - tp.height / 2.0));
    }

    // 3D Coordinate Triad (Red X, Green Y, Blue Z)
    _drawCornerTriad(canvas, size: size, cosAz: cosAz, sinAz: sinAz, cosEl: cosEl, sinEl: sinEl, scale: scale);
  }

  void _drawCornerTriad(
    Canvas canvas, {
    required Size size,
    required double cosAz,
    required double sinAz,
    required double cosEl,
    required double sinEl,
    required double scale,
  }) {
    final axisLen = scale * 0.55;
    // Lower left corner of cube container
    final origin = Offset(14.0, size.height - 12.0);

    void drawAxis(double rx, double ry, double rz, Color color, String name) {
      final (x2, y2, _) = _projectPoint(rx, ry, rz, cosAz, sinAz, cosEl, sinEl);
      final ep = Offset(origin.dx + x2 * axisLen, origin.dy - y2 * axisLen);
      final p = Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(origin, ep, p);

      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ep.dx - 1, ep.dy - 3));
    }

    // Red X (Right), Green Y (Up), Blue Z (Depth)
    drawAxis(1, 0, 0, const Color(0xFFEF4444), 'X');
    drawAxis(0, 1, 0, const Color(0xFF22C55E), 'Y');
    drawAxis(0, 0, 1, const Color(0xFF3B82F6), 'Z');
  }

  @override
  bool shouldRepaint(covariant _ViewCubePainter oldDelegate) {
    return oldDelegate.azimuthDeg != azimuthDeg || oldDelegate.elevationDeg != elevationDeg || oldDelegate.mousePos != mousePos;
  }
}
