// =============================================================================
// studio_view_cube.dart
//
// Interactive 3D Orientation ViewCube for truFold Studio 3D Viewport.
// Features:
// - Real-time 3D rendered orientation cube synced with camera azimuth and elevation
// - 6 interactive faces (TOP, FRONT, RIGHT, BACK, LEFT, BOTTOM) with hover highlight
// - Face click to snap camera directly to that orthogonal or isometric view
// - Drag-to-orbit gesture support directly on the ViewCube
// - 3D RGB coordinate axes triad (X red, Y green, Z blue)
// - Isometric Home icon button to reset view
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

class StudioViewCube extends StatefulWidget {
  final double azimuthDeg;
  final double elevationDeg;
  final VoidCallback? onResetView;
  final void Function(double azimuth, double elevation)? onSetView;
  final void Function(double dAzimuth, double dElevation)? onOrbit;
  final double size;

  const StudioViewCube({
    super.key,
    required this.azimuthDeg,
    required this.elevationDeg,
    this.onResetView,
    this.onSetView,
    this.onOrbit,
    this.size = 88.0,
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
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 1. 3D ViewCube Painter + Drag / Click gestures
          MouseRegion(
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
            cursor: _isDragging
                ? SystemMouseCursors.grabbing
                : (_hoveredFace != null ? SystemMouseCursors.click : SystemMouseCursors.grab),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => setState(() => _isDragging = true),
              onPanUpdate: (details) {
                widget.onOrbit?.call(details.delta.dx * 0.7, -details.delta.dy * 0.7);
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

          // 2. Home / ISO button in top-left
          Positioned(
            top: 3,
            left: 3,
            child: Tooltip(
              message: 'Home / Isometric View',
              child: InkWell(
                onTap: () {
                  if (widget.onSetView != null) {
                    widget.onSetView!(45, 30);
                  } else {
                    widget.onResetView?.call();
                  }
                },
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                  ),
                  child: const Icon(
                    Icons.home_outlined,
                    size: 11,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _snapToFace(String face) {
    switch (face) {
      case 'TOP':
        widget.onSetView?.call(0, 89);
        break;
      case 'BOTTOM':
        widget.onSetView?.call(0, -89);
        break;
      case 'FRONT':
        widget.onSetView?.call(0, 0);
        break;
      case 'BACK':
        widget.onSetView?.call(180, 0);
        break;
      case 'RIGHT':
        widget.onSetView?.call(90, 0);
        break;
      case 'LEFT':
        widget.onSetView?.call(-90, 0);
        break;
    }
  }
}

class _CubeFaceData {
  final String label;
  final List<int> vertexIndices;
  final List<double> normal;

  const _CubeFaceData({
    required this.label,
    required this.vertexIndices,
    required this.normal,
  });
}

class _ViewCubePainter extends CustomPainter {
  final double azimuthDeg;
  final double elevationDeg;
  final Offset? mousePos;
  final ValueChanged<String?> onHoverFaceChanged;

  _ViewCubePainter({
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.mousePos,
    required this.onHoverFaceChanged,
  });

  static const List<_CubeFaceData> _faces = [
    _CubeFaceData(label: 'TOP', vertexIndices: [4, 5, 6, 7], normal: [0, 0, 1]),
    _CubeFaceData(label: 'BOTTOM', vertexIndices: [3, 2, 1, 0], normal: [0, 0, -1]),
    _CubeFaceData(label: 'FRONT', vertexIndices: [7, 6, 2, 3], normal: [0, 1, 0]),
    _CubeFaceData(label: 'BACK', vertexIndices: [4, 0, 1, 5], normal: [0, -1, 0]),
    _CubeFaceData(label: 'RIGHT', vertexIndices: [5, 1, 2, 6], normal: [1, 0, 0]),
    _CubeFaceData(label: 'LEFT', vertexIndices: [4, 7, 3, 0], normal: [-1, 0, 0]),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final cubeRadius = size.width * 0.28;

    final azRad = azimuthDeg * math.pi / 180.0;
    final elRad = elevationDeg * math.pi / 180.0;

    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    // 8 cube vertices in local 3D coordinates (-1 to 1)
    const rawVerts = [
      [-1.0, -1.0, -1.0], // 0
      [ 1.0, -1.0, -1.0], // 1
      [ 1.0,  1.0, -1.0], // 2
      [-1.0,  1.0, -1.0], // 3
      [-1.0, -1.0,  1.0], // 4
      [ 1.0, -1.0,  1.0], // 5
      [ 1.0,  1.0,  1.0], // 6
      [-1.0,  1.0,  1.0], // 7
    ];

    // Project function matching viewport 3D camera
    ({Offset pt, double depth}) project(double rx, double ry, double rz) {
      final x1 = rx * cosAz - ry * sinAz;
      final y1 = rx * sinAz + ry * cosAz;
      final z1 = rz;

      final x2 = x1;
      final y2 = y1 * cosEl - z1 * sinEl;
      final z2 = y1 * sinEl + z1 * cosEl;

      return (
        pt: Offset(cx + x2 * cubeRadius, cy - y2 * cubeRadius),
        depth: z2,
      );
    }

    final projectedVerts = rawVerts.map((v) => project(v[0], v[1], v[2])).toList();

    // Transform face normals to camera space
    final visibleFaces = <({
      _CubeFaceData face,
      Path path,
      double depth,
      double normalZ,
      Offset center,
    })>[];

    for (final face in _faces) {
      final nx = face.normal[0];
      final ny = face.normal[1];
      final nz = face.normal[2];

      final ny1 = nx * sinAz + ny * cosAz;
      final nz2 = ny1 * sinEl + nz * cosEl;

      // Face visible if facing camera
      if (nz2 > 0.05) {
        final path = Path();
        double sumDepth = 0.0;
        double sumX = 0.0;
        double sumY = 0.0;

        for (int i = 0; i < face.vertexIndices.length; i++) {
          final vi = face.vertexIndices[i];
          final p = projectedVerts[vi];
          sumDepth += p.depth;
          sumX += p.pt.dx;
          sumY += p.pt.dy;
          if (i == 0) {
            path.moveTo(p.pt.dx, p.pt.dy);
          } else {
            path.lineTo(p.pt.dx, p.pt.dy);
          }
        }
        path.close();

        visibleFaces.add((
          face: face,
          path: path,
          depth: sumDepth / 4.0,
          normalZ: nz2,
          center: Offset(sumX / 4.0, sumY / 4.0),
        ));
      }
    }

    // Sort visible faces by depth (painter's algorithm)
    visibleFaces.sort((a, b) => a.depth.compareTo(b.depth));

    // Determine hovered face (from frontmost to back)
    String? foundHover;
    if (mousePos != null) {
      for (int i = visibleFaces.length - 1; i >= 0; i--) {
        if (visibleFaces[i].path.contains(mousePos!)) {
          foundHover = visibleFaces[i].face.label;
          break;
        }
      }
    }
    onHoverFaceChanged(foundHover);

    // Draw visible faces
    for (final f in visibleFaces) {
      final isHovered = f.face.label == foundHover;

      // Base shading based on orientation to virtual top-light
      final shade = (0.75 + f.normalZ * 0.25).clamp(0.0, 1.0);
      final baseColor = Color.lerp(
        const Color(0xFFE2E8F0),
        const Color(0xFFF8FAFC),
        shade,
      )!;

      final facePaint = Paint()
        ..color = isHovered
            ? const Color(0xFF0284C7).withValues(alpha: 0.28)
            : baseColor
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = isHovered ? const Color(0xFF0284C7) : const Color(0xFF94A3B8)
        ..strokeWidth = isHovered ? 1.5 : 1.0
        ..style = PaintingStyle.stroke;

      canvas.drawPath(f.path, facePaint);
      canvas.drawPath(f.path, borderPaint);

      // Label on face
      final textSpan = TextSpan(
        text: f.face.label,
        style: TextStyle(
          color: isHovered ? const Color(0xFF0284C7) : const Color(0xFF334155),
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(f.center.dx - tp.width / 2.0, f.center.dy - tp.height / 2.0),
      );
    }

    // Draw 3D Coordinate triad (X Red, Y Green, Z Blue) in bottom-left corner
    _drawCoordinateTriad(canvas, cx: 16.0, cy: size.height - 16.0, cosAz: cosAz, sinAz: sinAz, cosEl: cosEl, sinEl: sinEl);
  }

  void _drawCoordinateTriad(
    Canvas canvas, {
    required double cx,
    required double cy,
    required double cosAz,
    required double sinAz,
    required double cosEl,
    required double sinEl,
  }) {
    const axisLen = 11.0;

    void drawAxis(double rx, double ry, double rz, Color color, String name) {
      final x1 = rx * cosAz - ry * sinAz;
      final y1 = rx * sinAz + ry * cosAz;
      final z1 = rz;

      final x2 = x1;
      final y2 = y1 * cosEl - z1 * sinEl;

      final ep = Offset(cx + x2 * axisLen, cy - y2 * axisLen);
      final p = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(cx, cy), ep, p);

      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(color: color, fontSize: 6.5, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ep.dx - 2, ep.dy - 3));
    }

    drawAxis(1, 0, 0, const Color(0xFFEF4444), 'X');
    drawAxis(0, 1, 0, const Color(0xFF22C55E), 'Y');
    drawAxis(0, 0, 1, const Color(0xFF3B82F6), 'Z');
  }

  @override
  bool shouldRepaint(covariant _ViewCubePainter oldDelegate) {
    return oldDelegate.azimuthDeg != azimuthDeg ||
        oldDelegate.elevationDeg != elevationDeg ||
        oldDelegate.mousePos != mousePos;
  }
}
