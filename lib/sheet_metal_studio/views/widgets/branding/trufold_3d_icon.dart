// =============================================================================
// trufold_3d_icon.dart
//
// True 3D Animated Branding Icon & Loading Indicator for truFold Studio.
// Implements "Concept 3: Hinged Planar 't-F'" using 3D perspective projection,
// dynamic sheet metal folding kinematics (θ = 0° → 90°), depth-sorted faces,
// realistic lighting, metallic laser-cut edge walls, and CAD blueprint styling.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive & Animated 3D Icon for truFold Studio.
class TruFold3DIcon extends StatefulWidget {
  /// Display size (width and height).
  final double size;

  /// Whether the folding animation runs continuously (e.g. as a loading indicator).
  final bool isAnimated;

  /// Fixed fold angle in degrees when not animated (e.g. 0° flat, 45°, 90°).
  final double? fixedFoldAngleDeg;

  /// Whether to render the blueprint grid in the background.
  final bool showGrid;

  /// Whether to render technical CAD annotations (crosshairs, extension lines, θ arc).
  final bool showAnnotations;

  /// Whether the user can drag to orbit the 3D model.
  final bool interactiveOrbit;

  /// Primary color for the 't' planar face.
  final Color tColor;

  /// Primary color for the folding 'F' planar face.
  final Color fColor;

  /// Color for the bend axis, dimension arrows, and annotations.
  final Color accentColor;

  /// Animation cycle duration.
  final Duration animationDuration;

  /// Sheet metal thickness in local units (gives real 3D solid depth).
  final double sheetThickness;

  const TruFold3DIcon({
    super.key,
    this.size = 64.0,
    this.isAnimated = true,
    this.fixedFoldAngleDeg,
    this.showGrid = false,
    this.showAnnotations = false,
    this.interactiveOrbit = false,
    this.tColor = const Color(0xFF38BDF8), // Radiant CAD Sky Blue
    this.fColor = const Color(0xFF334155), // Precision Slate Charcoal
    this.accentColor = const Color(0xFFF97316), // Technical Orange
    this.animationDuration = const Duration(milliseconds: 2600),
    this.sheetThickness = 2.2,
  });

  @override
  State<TruFold3DIcon> createState() => _TruFold3DIconState();
}

class _TruFold3DIconState extends State<TruFold3DIcon> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _foldProgressAnim;

  // Interactive orbit angles in degrees
  double _userAzimuthDeg = -18.0;
  double _userElevationDeg = 16.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    // Smooth forward fold, brief hold, reverse unfold, brief hold
    _foldProgressAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 90.0).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 42.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(90.0),
        weight: 12.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 90.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 36.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 10.0,
      ),
    ]).animate(_animController);

    if (widget.isAnimated && widget.fixedFoldAngleDeg == null) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(TruFold3DIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimated && widget.fixedFoldAngleDeg == null) {
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
    } else {
      _animController.stop();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final currentAngle = widget.fixedFoldAngleDeg ?? (widget.isAnimated ? _foldProgressAnim.value : 45.0);

        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _TruFold3DPainter(
            foldAngleDeg: currentAngle,
            azimuthDeg: _userAzimuthDeg,
            elevationDeg: _userElevationDeg,
            showGrid: widget.showGrid,
            showAnnotations: widget.showAnnotations,
            tColor: widget.tColor,
            fColor: widget.fColor,
            accentColor: widget.accentColor,
            sheetThickness: widget.sheetThickness,
          ),
        );
      },
    );

    if (widget.interactiveOrbit) {
      content = GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _userAzimuthDeg += details.delta.dx * 0.7;
            _userElevationDeg = (_userElevationDeg - details.delta.dy * 0.7).clamp(-65.0, 65.0);
          });
        },
        child: content,
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: content,
    );
  }
}

/// 3D Vector Math Helper Point
class _V3 {
  final double x, y, z;
  const _V3(this.x, this.y, this.z);

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 operator *(double s) => _V3(x * s, y * s, z * s);

  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) => _V3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(x * x + y * y + z * z);
  _V3 normalized() {
    final l = length;
    return l > 1e-6 ? _V3(x / l, y / l, z / l) : const _V3(0, 0, 1);
  }
}

/// A 3D polygon face ready for depth sorting and drawing
class _Poly3D {
  final List<_V3> vertices;
  final Color baseColor;
  final Color? edgeColor;
  final double edgeWidth;
  final double depth;
  final _V3 normal;

  _Poly3D({
    required this.vertices,
    required this.baseColor,
    this.edgeColor,
    this.edgeWidth = 1.0,
    required this.depth,
    required this.normal,
  });
}

class _TruFold3DPainter extends CustomPainter {
  final double foldAngleDeg;
  final double azimuthDeg;
  final double elevationDeg;
  final bool showGrid;
  final bool showAnnotations;
  final Color tColor;
  final Color fColor;
  final Color accentColor;
  final double sheetThickness;

  static final _V3 _lightDir = const _V3(-0.45, 0.75, 0.55).normalized();

  _TruFold3DPainter({
    required this.foldAngleDeg,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.showGrid,
    required this.showAnnotations,
    required this.tColor,
    required this.fColor,
    required this.accentColor,
    required this.sheetThickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (showGrid) {
      _drawBlueprintGrid(canvas, size);
    }

    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final baseScale = size.width / 112.0;

    // View rotation angles
    final azRad = azimuthDeg * math.pi / 180.0;
    final elRad = elevationDeg * math.pi / 180.0;
    final sinAz = math.sin(azRad);
    final cosAz = math.cos(azRad);
    final sinEl = math.sin(elRad);
    final cosEl = math.cos(elRad);

    // 3D Camera Transformation
    _V3 transform(_V3 p) {
      // 1. Azimuth rotation around Y
      final x1 = p.x * cosAz - p.z * sinAz;
      final y1 = p.y;
      final z1 = p.x * sinAz + p.z * cosAz;

      // 2. Elevation rotation around X
      final x2 = x1;
      final y2 = y1 * cosEl - z1 * sinEl;
      final z2 = y1 * sinEl + z1 * cosEl;

      return _V3(x2, y2, z2);
    }

    // Perspective Projection from camera space to screen (X right, Y down)
    Offset project(_V3 cp) {
      const cameraDistance = 300.0;
      final fov = cameraDistance / (cameraDistance - cp.z);
      return Offset(
        cx + cp.x * baseScale * fov,
        cy - cp.y * baseScale * fov, // Invert Y for screen coordinates
      );
    }

    // -------------------------------------------------------------------------
    // 1. Define Model Vertices (Concept 3 "Hinged Planar t-F")
    // -------------------------------------------------------------------------
    // The 't' vertices (fixed left piece on Z = 0)
    // Coords from Image 3:
    final tFrontVertices = <_V3>[
      const _V3(-42, 34, 0),   // Top-left outer
      const _V3(-7, 34, 0),    // Top-right of 't' bar
      const _V3(-7, 21, 0),    // Corner into central slot
      const _V3(-12, 21, 0),   // Left slot wall top
      const _V3(-12, -22, 0),  // Left slot wall bottom
      const _V3(-7, -22, 0),   // Bottom slot transition
      const _V3(-7, -35, 0),   // Bottom-right of 't' stem
      const _V3(-21, -35, 0),  // Bottom flat edge
      const _V3(-32, -24, 0),  // Bottom-left 45° chamfer
      const _V3(-32, 21, 0),   // Under-edge of left arm corner
      const _V3(-42, 21, 0),   // Left arm bottom
    ];

    // The 'F' vertices (hinged along axis X = 0)
    // At fold angle θ = 0°, it lies flat in the plane
    final foldRad = foldAngleDeg * math.pi / 180.0;
    final sinFold = math.sin(foldRad);
    final cosFold = math.cos(foldRad);

    // Function to rotate a point on 'F' around the hinge axis X = 0
    _V3 rotateF(double rawX, double rawY) {
      // Hinge axis is along X = 0 line: rawX folds forward into +Z
      final xF = rawX * cosFold;
      final zF = rawX * sinFold;
      return _V3(xF, rawY, zF);
    }

    // Outer contour of 'F'
    final rawFCoords = <(double, double)>[
      (0.0, 34.0),    // Hinge top junction
      (36.0, 34.0),   // Top arm end top
      (36.0, 21.0),   // Top arm end bottom
      (12.0, 21.0),   // Inside corner top arm
      (12.0, 8.0),    // Top of middle bar
      (28.0, 8.0),    // Middle bar end top
      (28.0, -3.0),   // Middle bar end bottom
      (12.0, -3.0),   // Inside corner middle bar
      (12.0, -24.0),  // Bottom stem right edge
      (2.0, -35.0),   // Bottom-right 45° chamfer
      (0.0, -35.0),   // Hinge bottom junction
      (0.0, -22.0),   // Inner slot wall bottom
      (5.0, -22.0),   // Slot inset
      (5.0, 21.0),    // Slot inset top
      (0.0, 21.0),    // Inner slot wall top
    ];

    final fFrontVertices = rawFCoords.map((c) => rotateF(c.$1, c.$2)).toList();

    // -------------------------------------------------------------------------
    // 2. Generate 3D Solid Faces (Front, Back, and Side Edge Walls)
    // -------------------------------------------------------------------------
    final halfThick = sheetThickness / 2.0;
    final polyList = <_Poly3D>[];

    void addSolidExtrusion(
      List<_V3> front2D,
      Color faceColor, {
      _V3 normal = const _V3(0, 0, 1),
    }) {
      // Front face (+Z offset)
      final front = front2D.map((v) => v + normal * halfThick).toList();
      // Back face (-Z offset)
      final back = front2D.map((v) => v - normal * halfThick).toList();

      // Front polygon
      final frontTransformed = front.map(transform).toList();
      final frontDepth = frontTransformed.map((p) => p.z).reduce((a, b) => a + b) / frontTransformed.length;
      final frontNormTrans = transform(normal) - transform(const _V3(0, 0, 0));
      polyList.add(_Poly3D(
        vertices: frontTransformed,
        baseColor: faceColor,
        edgeColor: faceColor.withValues(alpha: 0.9),
        edgeWidth: 1.2,
        depth: frontDepth,
        normal: frontNormTrans.normalized(),
      ));

      // Back polygon
      final backTransformed = back.map(transform).toList().reversed.toList();
      final backDepth = backTransformed.map((p) => p.z).reduce((a, b) => a + b) / backTransformed.length;
      final backNormTrans = (transform(normal * -1.0) - transform(const _V3(0, 0, 0))).normalized();
      polyList.add(_Poly3D(
        vertices: backTransformed,
        baseColor: Color.lerp(faceColor, Colors.black, 0.35)!,
        edgeColor: Colors.black.withValues(alpha: 0.4),
        edgeWidth: 0.8,
        depth: backDepth,
        normal: backNormTrans,
      ));

      // Side edge walls (laser cut thickness perimeter)
      final edgeColor = Color.lerp(faceColor, const Color(0xFF0F172A), 0.45)!;
      for (int i = 0; i < front.length; i++) {
        final next = (i + 1) % front.length;
        final p1 = front[i];
        final p2 = front[next];
        final p3 = back[next];
        final p4 = back[i];

        final wallTransformed = [p1, p2, p3, p4].map(transform).toList();
        final wallDepth = (wallTransformed[0].z + wallTransformed[1].z + wallTransformed[2].z + wallTransformed[3].z) / 4.0;

        // Compute wall normal
        final v1 = wallTransformed[1] - wallTransformed[0];
        final v2 = wallTransformed[3] - wallTransformed[0];
        final wallNorm = v1.cross(v2).normalized();

        polyList.add(_Poly3D(
          vertices: wallTransformed,
          baseColor: edgeColor,
          edgeColor: const Color(0xFF0F172A).withValues(alpha: 0.65),
          edgeWidth: 0.9,
          depth: wallDepth,
          normal: wallNorm,
        ));
      }
    }

    // Add 't' solid geometry (normal = +Z)
    addSolidExtrusion(tFrontVertices, tColor, normal: const _V3(0, 0, 1));

    // Add 'F' solid geometry (normal rotates with fold angle)
    final fNormal = _V3(
      -sinFold,
      0,
      cosFold,
    ).normalized();
    addSolidExtrusion(fFrontVertices, fColor, normal: fNormal);

    // -------------------------------------------------------------------------
    // 3. Depth Sorting (Painter's Algorithm for Perfect 3D Occlusion)
    // -------------------------------------------------------------------------
    polyList.sort((a, b) => a.depth.compareTo(b.depth));

    // Draw all polygons with dynamic diffuse lighting
    for (final poly in polyList) {
      // Shading calculation based on surface normal & light
      final diff = math.max(0.20, poly.normal.dot(_lightDir));
      final shadedColor = Color.lerp(
        Colors.black,
        poly.baseColor,
        0.35 + 0.65 * diff,
      )!;

      final path = Path();
      final screenPts = poly.vertices.map(project).toList();
      path.moveTo(screenPts.first.dx, screenPts.first.dy);
      for (int i = 1; i < screenPts.length; i++) {
        path.lineTo(screenPts[i].dx, screenPts[i].dy);
      }
      path.close();

      // Fill face
      final fillPaint = Paint()
        ..color = shadedColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      // Edge outline for crisp precision CAD lines
      if (poly.edgeColor != null) {
        final strokePaint = Paint()
          ..color = poly.edgeColor!
          ..strokeWidth = poly.edgeWidth
          ..style = PaintingStyle.stroke;
        canvas.drawPath(path, strokePaint);
      }
    }

    // -------------------------------------------------------------------------
    // 4. Hinge Bend Line & Technical Annotations
    // -------------------------------------------------------------------------
    final pTopHinge = project(transform(const _V3(0, 36, 0)));
    final pBotHinge = project(transform(const _V3(0, -37, 0)));

    // Dashed / solid bend line down the hinge
    final bendLinePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pTopHinge, pBotHinge, bendLinePaint);

    if (showAnnotations) {
      _drawTechnicalAnnotations(
        canvas,
        size,
        cx,
        cy,
        baseScale,
        transform,
        project,
      );
    }
  }

  void _drawBlueprintGrid(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.65;

    const spacing = 12.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawTechnicalAnnotations(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    double scale,
    _V3 Function(_V3) transform,
    Offset Function(_V3) project,
  ) {
    // 1. Crosshairs on 't' and 'F'
    final crossPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 0.8;

    void drawCrosshair(_V3 pt) {
      final sp = project(transform(pt));
      const s = 4.0;
      canvas.drawLine(Offset(sp.dx - s, sp.dy), Offset(sp.dx + s, sp.dy), crossPaint);
      canvas.drawLine(Offset(sp.dx, sp.dy - s), Offset(sp.dx, sp.dy + s), crossPaint);
    }

    drawCrosshair(const _V3(-26, 27.5, 0));
    drawCrosshair(const _V3(-22, -8, 0));
    drawCrosshair(const _V3(24, 27.5, 0));
    drawCrosshair(const _V3(20, 2.5, 0));
    drawCrosshair(const _V3(10, -18, 0));

    // 2. Angular dimension indicator arc at the bottom (θ = 0° → 90°)
    final pCenter = project(transform(const _V3(0, -38, 0)));
    final arcRadius = 14.0 * (size.width / 120.0);

    final arcPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCircle(center: pCenter, radius: arcRadius);
    final sweep = (foldAngleDeg * math.pi / 180.0).clamp(0.1, math.pi / 2);
    canvas.drawArc(rect, 0, sweep, false, arcPaint);

    // Arrow tip on arc
    final tipX = pCenter.dx + arcRadius * math.cos(sweep);
    final tipY = pCenter.dy + arcRadius * math.sin(sweep);
    final tipPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(tipX, tipY), 2.2, tipPaint);

    // Dimension label text "θ = 0° → 90°" or dynamic angle
    final labelSpan = TextSpan(
      text: 'θ = ${foldAngleDeg.toStringAsFixed(0)}°',
      style: TextStyle(
        color: accentColor,
        fontSize: math.max(8.0, size.width * 0.085),
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
    final tp = TextPainter(text: labelSpan, textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(pCenter.dx - tp.width / 2.0, pCenter.dy + 7));
  }

  @override
  bool shouldRepaint(covariant _TruFold3DPainter old) {
    return old.foldAngleDeg != foldAngleDeg ||
        old.azimuthDeg != azimuthDeg ||
        old.elevationDeg != elevationDeg ||
        old.showGrid != showGrid ||
        old.showAnnotations != showAnnotations ||
        old.tColor != tColor ||
        old.fColor != fColor ||
        old.accentColor != accentColor ||
        old.sheetThickness != sheetThickness;
  }
}
