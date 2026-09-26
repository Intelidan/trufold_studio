// =============================================================================
// dds_drawing_painters.dart
//
// Reusable 2D Technical Vector & 3D Isometric Viewport Painters.
// Used across:
// 1. DdsPaperCanvas: High-resolution split viewports on A4/A3 submittal sheets.
// 2. DdsTemplateLibraryDialog: 2D & 3D preview thumbnails in the tabular library.
// 3. Submittal PDF Export Engine.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../models/cad_primitives.dart';
import '../../../models/dsf_document.dart';
import '../../../engine/kinematic_fold_engine.dart';

// =============================================================================
// 1. 2D Technical Vector Drawing Painter
// =============================================================================

class Dds2DDrawingPainter extends CustomPainter {
  final DsfDocument? document;
  final dynamic coverData;
  final Color backgroundColor;
  final Color faceColor;
  final Color outlineColor;
  final Color bendColor;
  final Color holeColor;
  final bool showBendLines;
  final bool showPunches;

  Dds2DDrawingPainter({
    this.document,
    this.coverData,
    this.backgroundColor = Colors.transparent,
    this.faceColor = const Color(0xFFE2E8F0),
    this.outlineColor = const Color(0xFF0284C7),
    this.bendColor = const Color(0xFFF59E0B),
    this.holeColor = const Color(0xFF0F172A),
    this.showBendLines = true,
    this.showPunches = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor != Colors.transparent) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    }

    if (document == null || document!.faces.isEmpty) {
      _paintEmptyPlaceholder(canvas, size, 'Awaiting 2D Geometry...');
      return;
    }

    final doc = document!;
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    for (final face in doc.faces) {
      for (final v in face.vertices) {
        if (v.x < minX) minX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.x > maxX) maxX = v.x;
        if (v.y > maxY) maxY = v.y;
      }
    }

    if (minX == double.infinity) {
      _paintEmptyPlaceholder(canvas, size, 'No 2D vertices.');
      return;
    }

    final modelW = maxX - minX;
    final modelH = maxY - minY;
    if (modelW <= 0 || modelH <= 0) return;

    final padding = size.width < 120 ? 8.0 : 30.0;
    final scale = math.min((size.width - padding) / modelW, (size.height - padding) / modelH);
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final modelCenterX = (minX + maxX) / 2.0;
    final modelCenterY = (minY + maxY) / 2.0;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale, -scale); // Invert Y for standard CAD coordinates
    canvas.translate(-modelCenterX, -modelCenterY);

    // 1. Draw Planar Faces & Outer Outline
    final facePaint = Paint()
      ..color = faceColor
      ..style = PaintingStyle.fill;
    final strokeWidth = (size.width < 120 ? 1.0 : 1.4) / scale;
    final outlinePaint = Paint()
      ..color = outlineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (final face in doc.faces) {
      if (face.vertices.length < 3) continue;
      final path = Path();
      path.moveTo(face.vertices.first.x, face.vertices.first.y);
      for (int i = 1; i < face.vertices.length; i++) {
        path.lineTo(face.vertices[i].x, face.vertices[i].y);
      }
      path.close();
      canvas.drawPath(path, facePaint);
      canvas.drawPath(path, outlinePaint);
    }

    // 2. Draw Bend Lines
    if (showBendLines && doc.bends.isNotEmpty) {
      final bendPaint = Paint()
        ..color = bendColor
        ..strokeWidth = (size.width < 120 ? 0.9 : 1.2) / scale
        ..style = PaintingStyle.stroke;

      for (final bend in doc.bends) {
        canvas.drawLine(Offset(bend.x1, bend.y1), Offset(bend.x2, bend.y2), bendPaint);
      }
    }

    // 3. Draw Punches / Holes
    if (showPunches && doc.punches.isNotEmpty) {
      final holePaint = Paint()
        ..color = holeColor
        ..style = PaintingStyle.fill;

      for (final punch in doc.punches) {
        final r = punch.diameterMm > 0
            ? punch.diameterMm / 2.0
            : (punch.widthMm > 0 ? punch.widthMm / 2.0 : 4.0);
        canvas.drawCircle(Offset(punch.center.x, punch.center.y), r, holePaint);
      }
    }

    canvas.restore();
  }

  void _paintEmptyPlaceholder(Canvas canvas, Size size, String message) {
    final tp = TextPainter(
      text: TextSpan(
        text: message,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant Dds2DDrawingPainter oldDelegate) =>
      oldDelegate.document != document || oldDelegate.coverData != coverData;
}

// =============================================================================
// 2. 3D Isometric Viewport Painter
// =============================================================================

class Dds3DIsometricPainter extends CustomPainter {
  final FoldedMeshResult? mesh;
  final Color backgroundColor;
  final double elevationDeg;
  final double azimuthDeg;

  Dds3DIsometricPainter({
    this.mesh,
    this.backgroundColor = Colors.transparent,
    this.elevationDeg = 35.264, // True isometric elevation angle
    this.azimuthDeg = 45.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor != Colors.transparent) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    }

    if (mesh == null || mesh!.polygons.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'No 3D Mesh',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 9.0),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }

    final azRad = azimuthDeg * math.pi / 180.0;
    final elRad = elevationDeg * math.pi / 180.0;
    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final m = mesh!;
    final center = m.center;
    final maxDim = math.max(m.boundWidth, math.max(m.boundLength, m.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final scale = (math.min(size.width, size.height) * 0.72) / fitDim;

    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    // Light direction (from top-left)
    final lx = -0.577;
    final ly = -0.577;
    final lz = 0.577;

    // Sort polygons by depth (Painter's algorithm)
    final sortedPolys = List<CadFoldedPolygon3D>.from(m.polygons);
    sortedPolys.sort((a, b) {
      double zA = 0.0, zB = 0.0;
      for (final v in a.vertices) {
        final ry = (v.x - center.x) * sinAz + (v.y - center.y) * cosAz;
        zA += -ry * sinEl + (v.z - center.z) * cosEl;
      }
      for (final v in b.vertices) {
        final ry = (v.x - center.x) * sinAz + (v.y - center.y) * cosAz;
        zB += -ry * sinEl + (v.z - center.z) * cosEl;
      }
      return (zA / a.vertices.length).compareTo(zB / b.vertices.length);
    });

    for (final poly in sortedPolys) {
      if (poly.vertices.length < 3) continue;

      final points = <Offset>[];
      for (final v in poly.vertices) {
        final dx = v.x - center.x;
        final dy = v.y - center.y;
        final dz = v.z - center.z;

        final rx = dx * cosAz - dy * sinAz;
        final ry = dx * sinAz + dy * cosAz;
        final scrY = ry * cosEl + dz * sinEl;

        points.add(Offset(cx + rx * scale, cy - scrY * scale));
      }

      // Directional shading
      final n = poly.normal;
      final dot = (n.x * lx + n.y * ly + n.z * lz).clamp(0.0, 1.0);
      final intensity = 0.45 + 0.55 * dot;

      final baseColor = poly.color;
      final litColor = Color.from(
        alpha: baseColor.a,
        red: (baseColor.r * intensity).clamp(0.0, 1.0),
        green: (baseColor.g * intensity).clamp(0.0, 1.0),
        blue: (baseColor.b * intensity).clamp(0.0, 1.0),
      );

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();

      canvas.drawPath(path, Paint()..color = litColor..style = PaintingStyle.fill);

      // Subtle edge line
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..strokeWidth = 0.7
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant Dds3DIsometricPainter oldDelegate) => oldDelegate.mesh != mesh;
}

// =============================================================================
// 3. Compact Thumbnail Widgets for Library Lister & Cards
// =============================================================================

class Dsf2DThumbnailWidget extends StatelessWidget {
  final DsfDocument? document;
  final double width;
  final double height;
  final Color backgroundColor;

  const Dsf2DThumbnailWidget({
    super.key,
    this.document,
    this.width = 84,
    this.height = 64,
    this.backgroundColor = const Color(0xFFF8FAFC),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: Dds2DDrawingPainter(
          document: document,
          backgroundColor: backgroundColor,
          faceColor: const Color(0xFFE2E8F0),
          outlineColor: const Color(0xFF0284C7),
          bendColor: const Color(0xFFF59E0B),
        ),
      ),
    );
  }
}

class Dsf3DIsometricThumbnailWidget extends StatelessWidget {
  final FoldedMeshResult? mesh;
  final double width;
  final double height;
  final Color backgroundColor;

  const Dsf3DIsometricThumbnailWidget({
    super.key,
    this.mesh,
    this.width = 84,
    this.height = 64,
    this.backgroundColor = const Color(0xFF0F172A),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(color: const Color(0xFF334155), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: Dds3DIsometricPainter(
          mesh: mesh,
          backgroundColor: backgroundColor,
        ),
      ),
    );
  }
}

// =============================================================================
// 4. 2D Blueprint to 3D Solid Transition Viewport Painter
// =============================================================================

class Dds2Dto3DTransitionPainter extends CustomPainter {
  final DsfDocument? document;
  final FoldedMeshResult? mesh;
  final double transitionProgress; // 0.0 (all 2D) to 1.0 (all 3D)
  final bool showDividerLine;
  final Color dividerColor;
  final bool showCrossHatching;
  final bool showBendLines;
  final bool showPunches;
  final double azimuthDeg;
  final double elevationDeg;

  Dds2Dto3DTransitionPainter({
    this.document,
    this.mesh,
    required this.transitionProgress,
    this.showDividerLine = true,
    this.dividerColor = const Color(0xFF38BDF8),
    this.showCrossHatching = true,
    this.showBendLines = true,
    this.showPunches = true,
    this.azimuthDeg = 45.0,
    this.elevationDeg = 35.264,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final wipeX = (size.width * transitionProgress.clamp(0.0, 1.0));

    // 1. LEFT REGION: 2D Technical Vector Blueprint
    if (wipeX > 0.0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, wipeX, size.height));

      // Engineering Blueprint Grid Background
      _paintBlueprintBackground(canvas, Size(wipeX, size.height));

      // 2D Technical CAD Drawing with Cross-Hatching
      _paint2DDrawing(canvas, size);

      // 2D View Label in top-left
      _paintLabel(
        canvas,
        const Offset(12, 10),
        '2D TECHNICAL BLUEPRINT (SECTION & FLAT)',
        const Color(0xFF0369A1),
      );

      canvas.restore();
    }

    // 2. RIGHT REGION: 3D Shaded Solid Model
    if (wipeX < size.width) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(wipeX, 0, size.width - wipeX, size.height));

      // Sleek Dark Viewport Background
      canvas.drawRect(
        Rect.fromLTWH(wipeX, 0, size.width - wipeX, size.height),
        Paint()..color = const Color(0xFF0F172A),
      );

      // Subtle isometric grid dots on 3D floor
      _paintIsoDots(canvas, Rect.fromLTWH(wipeX, 0, size.width - wipeX, size.height));

      // 3D Isometric Shaded Mesh
      _paint3DModel(canvas, size);

      // 3D View Label in top-right
      _paintLabel(
        canvas,
        Offset(size.width - 240, 10),
        '3D ASSEMBLED SOLID (METALLIC)',
        const Color(0xFF38BDF8),
      );

      canvas.restore();
    }

    // 3. TRANSITION LASER DIVIDER & GRAB HANDLE
    if (showDividerLine && wipeX > 4.0 && wipeX < size.width - 4.0) {
      _paintLaserDivider(canvas, size, wipeX);
    }
  }

  void _paintBlueprintBackground(Canvas canvas, Size size) {
    // Crisp off-white / technical paper background
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF8FAFC));

    // Subtle technical grid lines (spaced 20px)
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.6;

    for (double x = 0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _paintIsoDots(Canvas canvas, Rect bounds) {
    final dotPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    for (double x = bounds.left + 15; x < bounds.right; x += 30) {
      for (double y = bounds.top + 15; y < bounds.bottom; y += 30) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  void _paint2DDrawing(Canvas canvas, Size size) {
    if (document == null || document!.faces.isEmpty) return;

    final doc = document!;
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    for (final face in doc.faces) {
      for (final v in face.vertices) {
        if (v.x < minX) minX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.x > maxX) maxX = v.x;
        if (v.y > maxY) maxY = v.y;
      }
    }

    if (minX == double.infinity) return;
    final modelW = maxX - minX;
    final modelH = maxY - minY;
    if (modelW <= 0 || modelH <= 0) return;

    final scale = math.min((size.width - 60) / modelW, (size.height - 60) / modelH);
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final modelCenterX = (minX + maxX) / 2.0;
    final modelCenterY = (minY + maxY) / 2.0;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale, -scale); // Standard CAD Y-up
    canvas.translate(-modelCenterX, -modelCenterY);

    // 1. Draw Planar Faces with Mechanical Cross-Hatching (as in technical section drawings)
    final facePaint = Paint()..color = const Color(0xFFF1F5F9)..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 1.4 / scale
      ..style = PaintingStyle.stroke;
    final hatchPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.5)
      ..strokeWidth = 0.8 / scale
      ..style = PaintingStyle.stroke;

    for (final face in doc.faces) {
      if (face.vertices.length < 3) continue;
      final path = Path();
      path.moveTo(face.vertices.first.x, face.vertices.first.y);
      for (int i = 1; i < face.vertices.length; i++) {
        path.lineTo(face.vertices[i].x, face.vertices[i].y);
      }
      path.close();

      canvas.drawPath(path, facePaint);

      // 45° Mechanical Section Cross-Hatching
      if (showCrossHatching) {
        canvas.save();
        canvas.clipPath(path);
        final step = 8.0 / scale;
        final diag = (maxX - minX) + (maxY - minY);
        for (double d = -diag; d <= diag * 2; d += step) {
          canvas.drawLine(
            Offset(minX + d, minY),
            Offset(minX + d + diag, minY + diag),
            hatchPaint,
          );
        }
        canvas.restore();
      }

      canvas.drawPath(path, outlinePaint);
    }

    // 2. Draw Bend Lines
    if (showBendLines) {
      final bendPaint = Paint()
        ..color = const Color(0xFFD97706) // Amber
        ..strokeWidth = 1.2 / scale
        ..style = PaintingStyle.stroke;

      for (final bend in doc.bends) {
        canvas.drawLine(Offset(bend.x1, bend.y1), Offset(bend.x2, bend.y2), bendPaint);
      }
    }

    // 3. Draw Punches
    if (showPunches) {
      final holePaint = Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.fill;
      for (final punch in doc.punches) {
        final r = punch.diameterMm > 0 ? punch.diameterMm / 2.0 : 4.0;
        canvas.drawCircle(Offset(punch.center.x, punch.center.y), r, holePaint);
      }
    }

    canvas.restore();
  }

  void _paint3DModel(Canvas canvas, Size size) {
    if (mesh == null || mesh!.polygons.isEmpty) return;

    final azRad = azimuthDeg * math.pi / 180.0;
    final elRad = elevationDeg * math.pi / 180.0;
    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final m = mesh!;
    final center = m.center;
    final maxDim = math.max(m.boundWidth, math.max(m.boundLength, m.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final scale = (math.min(size.width, size.height) * 0.72) / fitDim;

    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    // Directional Lighting
    final lx = -0.577;
    final ly = -0.577;
    final lz = 0.577;

    final sortedPolys = List<CadFoldedPolygon3D>.from(m.polygons);
    sortedPolys.sort((a, b) {
      double zA = 0.0, zB = 0.0;
      for (final v in a.vertices) {
        final ry = (v.x - center.x) * sinAz + (v.y - center.y) * cosAz;
        zA += -ry * sinEl + (v.z - center.z) * cosEl;
      }
      for (final v in b.vertices) {
        final ry = (v.x - center.x) * sinAz + (v.y - center.y) * cosAz;
        zB += -ry * sinEl + (v.z - center.z) * cosEl;
      }
      return (zA / a.vertices.length).compareTo(zB / b.vertices.length);
    });

    for (final poly in sortedPolys) {
      if (poly.vertices.length < 3) continue;

      final points = <Offset>[];
      for (final v in poly.vertices) {
        final dx = v.x - center.x;
        final dy = v.y - center.y;
        final dz = v.z - center.z;

        final rx = dx * cosAz - dy * sinAz;
        final ry = dx * sinAz + dy * cosAz;
        final scrY = ry * cosEl + dz * sinEl;

        points.add(Offset(cx + rx * scale, cy - scrY * scale));
      }

      final n = poly.normal;
      final dot = (n.x * lx + n.y * ly + n.z * lz).clamp(0.0, 1.0);
      final intensity = 0.45 + 0.55 * dot;

      final baseColor = poly.color;
      final litColor = Color.from(
        alpha: baseColor.a,
        red: (baseColor.r * intensity).clamp(0.0, 1.0),
        green: (baseColor.g * intensity).clamp(0.0, 1.0),
        blue: (baseColor.b * intensity).clamp(0.0, 1.0),
      );

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();

      canvas.drawPath(path, Paint()..color = litColor..style = PaintingStyle.fill);

      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..strokeWidth = 0.7
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintLaserDivider(Canvas canvas, Size size, double wipeX) {
    // 1. Glowing Laser Band
    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          dividerColor.withValues(alpha: 0.3),
          dividerColor.withValues(alpha: 0.8),
          dividerColor.withValues(alpha: 0.3),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(wipeX - 6, 0, 12, size.height));

    canvas.drawRect(Rect.fromLTWH(wipeX - 6, 0, 12, size.height), glowPaint);

    // 2. Center Sharp Line
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8;
    canvas.drawLine(Offset(wipeX, 0), Offset(wipeX, size.height), linePaint);

    // 3. Central Draggable Badge Handle
    final handleCenter = Offset(wipeX, size.height / 2);
    const handleW = 76.0;
    const handleH = 26.0;
    final handleRect = Rect.fromCenter(center: handleCenter, width: handleW, height: handleH);
    final rrect = RRect.fromRectAndRadius(handleRect, const Radius.circular(13.0));

    // Handle Shadow & Background
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.95)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = dividerColor
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );

    // Handle Text: "2D ⬌ 3D"
    final tp = TextPainter(
      text: const TextSpan(
        children: [
          TextSpan(text: '2D ', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
          TextSpan(text: '⬌', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11.0, fontWeight: FontWeight.bold)),
          TextSpan(text: ' 3D', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, handleCenter - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintLabel(Canvas canvas, Offset pos, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3.0)),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant Dds2Dto3DTransitionPainter oldDelegate) => true;
}
