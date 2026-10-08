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
import '../../../models/dds/dds_sheet.dart';
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

// =============================================================================
// 6. Onshape-style 2D Orthographic Multi-View Drawing Painters & Widgets
// =============================================================================

/// Engineering view orientations for Onshape-style 2D drawing projections.
enum DdsOrthographicViewType {
  front('FRONT ELEVATION', 0.0, 0.0),
  top('TOP PLAN', 0.0, 90.0),
  end('RIGHT ELEVATION', 90.0, 0.0),
  left('LEFT ELEVATION', -90.0, 0.0),
  bottom('BOTTOM PLAN', 0.0, -90.0),
  back('REAR ELEVATION', 180.0, 0.0),
  isometric('ISOMETRIC PROJECTION', 45.0, 35.264),
  dimetric('DIMETRIC PROJECTION', 26.57, 20.7),
  trimetric('TRIMETRIC PROJECTION', 60.0, 30.0);

  final String title;
  final double defaultAzimuth;
  final double defaultElevation;
  const DdsOrthographicViewType(this.title, this.defaultAzimuth, this.defaultElevation);
}

/// Standard 2D Orthographic & Axonometric Projection Painter for technical drawing sheets.
class DdsOrthographicViewPainter extends CustomPainter {
  final FoldedMeshResult? mesh;
  final DdsOrthographicViewType viewType;
  final bool showDimensions;
  final bool showCenterlines;
  final bool showHiddenLines;
  final bool isShaded;
  final OnshapeTangentEdgeMode tangentEdgeMode;
  final bool showHoleCenterMarks;
  final Color backgroundColor;
  final Color outlineColor;
  final Color faceColor;
  final Color dimensionColor;
  final Color hiddenLineColor;
  final String? customTitle;

  DdsOrthographicViewPainter({
    required this.mesh,
    required this.viewType,
    this.showDimensions = true,
    this.showCenterlines = true,
    this.showHiddenLines = false,
    this.isShaded = false,
    this.tangentEdgeMode = OnshapeTangentEdgeMode.phantom,
    this.showHoleCenterMarks = true,
    this.backgroundColor = Colors.white,
    this.outlineColor = const Color(0xFF0F172A),
    this.faceColor = const Color(0xFFF8FAFC),
    this.dimensionColor = const Color(0xFF0284C7),
    this.hiddenLineColor = const Color(0xFF94A3B8),
    this.customTitle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor != Colors.transparent) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    }

    if (mesh == null || mesh!.polygons.isEmpty) {
      _paintEmptyText(canvas, size, 'Awaiting 3D Model Geometry...');
      return;
    }

    final m = mesh!;
    final center = m.center;

    // View bounding dimension extents along screen X and screen Y
    double extentW = 0.0;
    double extentH = 0.0;
    String horizDimLabel = '';
    String vertDimLabel = '';

    switch (viewType) {
      case DdsOrthographicViewType.front:
        extentW = m.boundWidth > 0 ? m.boundWidth : 100.0;
        extentH = m.boundHeight > 0 ? m.boundHeight : 50.0;
        horizDimLabel = 'W: ${m.boundWidth.toStringAsFixed(1)} mm';
        vertDimLabel = 'H: ${m.boundHeight.toStringAsFixed(1)} mm';
        break;
      case DdsOrthographicViewType.top:
        extentW = m.boundWidth > 0 ? m.boundWidth : 100.0;
        extentH = m.boundLength > 0 ? m.boundLength : 100.0;
        horizDimLabel = 'W: ${m.boundWidth.toStringAsFixed(1)} mm';
        vertDimLabel = 'L: ${m.boundLength.toStringAsFixed(1)} mm';
        break;
      case DdsOrthographicViewType.end:
      case DdsOrthographicViewType.left:
        extentW = m.boundLength > 0 ? m.boundLength : 100.0;
        extentH = m.boundHeight > 0 ? m.boundHeight : 50.0;
        horizDimLabel = 'L: ${m.boundLength.toStringAsFixed(1)} mm';
        vertDimLabel = 'H: ${m.boundHeight.toStringAsFixed(1)} mm';
        break;
      case DdsOrthographicViewType.bottom:
        extentW = m.boundWidth > 0 ? m.boundWidth : 100.0;
        extentH = m.boundLength > 0 ? m.boundLength : 100.0;
        horizDimLabel = 'W: ${m.boundWidth.toStringAsFixed(1)} mm';
        vertDimLabel = 'L: ${m.boundLength.toStringAsFixed(1)} mm';
        break;
      case DdsOrthographicViewType.back:
        extentW = m.boundWidth > 0 ? m.boundWidth : 100.0;
        extentH = m.boundHeight > 0 ? m.boundHeight : 50.0;
        horizDimLabel = 'W: ${m.boundWidth.toStringAsFixed(1)} mm';
        vertDimLabel = 'H: ${m.boundHeight.toStringAsFixed(1)} mm';
        break;
      case DdsOrthographicViewType.isometric:
      case DdsOrthographicViewType.dimetric:
      case DdsOrthographicViewType.trimetric:
        final maxDim = math.max(m.boundWidth, math.max(m.boundLength, m.boundHeight));
        extentW = maxDim > 0 ? maxDim : 100.0;
        extentH = extentW;
        break;
    }

    // Allocate margin for title and dimensions
    const marginL = 36.0;
    const marginR = 24.0;
    const marginT = 24.0;
    const marginB = 34.0;
    final drawAreaW = math.max(10.0, size.width - marginL - marginR);
    final drawAreaH = math.max(10.0, size.height - marginT - marginB);

    final scale = math.min(drawAreaW / extentW, drawAreaH / extentH) * 0.85;
    final cx = marginL + drawAreaW / 2.0;
    final cy = marginT + drawAreaH / 2.0;

    // Project 3D coordinate to view canvas coordinate
    Offset project(CadPoint3D p) {
      final dx = p.x - center.x;
      final dy = p.y - center.y;
      final dz = p.z - center.z;

      switch (viewType) {
        case DdsOrthographicViewType.front:
          return Offset(cx + dx * scale, cy - dz * scale);
        case DdsOrthographicViewType.top:
          return Offset(cx + dx * scale, cy - dy * scale);
        case DdsOrthographicViewType.end:
          return Offset(cx + dy * scale, cy - dz * scale);
        case DdsOrthographicViewType.left:
          return Offset(cx - dy * scale, cy - dz * scale);
        case DdsOrthographicViewType.bottom:
          return Offset(cx + dx * scale, cy + dy * scale);
        case DdsOrthographicViewType.back:
          return Offset(cx - dx * scale, cy - dz * scale);
        case DdsOrthographicViewType.isometric:
        case DdsOrthographicViewType.dimetric:
        case DdsOrthographicViewType.trimetric:
          final azRad = viewType.defaultAzimuth * math.pi / 180.0;
          final elRad = viewType.defaultElevation * math.pi / 180.0;
          final rx = dx * math.cos(azRad) - dy * math.sin(azRad);
          final ry = dx * math.sin(azRad) + dy * math.cos(azRad);
          final scrY = ry * math.cos(elRad) + dz * math.sin(elRad);
          return Offset(cx + rx * scale, cy - scrY * scale);
      }
    }

    // Line of sight direction for depth sorting and backface test
    CadPoint3D getViewDirection() {
      switch (viewType) {
        case DdsOrthographicViewType.front:
          return const CadPoint3D(0, 1, 0);
        case DdsOrthographicViewType.top:
          return const CadPoint3D(0, 0, -1);
        case DdsOrthographicViewType.end:
          return const CadPoint3D(-1, 0, 0);
        case DdsOrthographicViewType.left:
          return const CadPoint3D(1, 0, 0);
        case DdsOrthographicViewType.bottom:
          return const CadPoint3D(0, 0, 1);
        case DdsOrthographicViewType.back:
          return const CadPoint3D(0, -1, 0);
        case DdsOrthographicViewType.isometric:
        case DdsOrthographicViewType.dimetric:
        case DdsOrthographicViewType.trimetric:
          final azRad = viewType.defaultAzimuth * math.pi / 180.0;
          final elRad = viewType.defaultElevation * math.pi / 180.0;
          return CadPoint3D(
            -math.sin(azRad) * math.cos(elRad),
            -math.cos(azRad) * math.cos(elRad),
            math.sin(elRad),
          );
      }
    }

    final allPolys = [...m.polygons, ...m.filletPolygons, ...m.thicknessPolygons];
    final vDir = getViewDirection();

    // Sort polygons by view-space depth (Painter's algorithm)
    allPolys.sort((a, b) {
      double zA = 0.0, zB = 0.0;
      for (final v in a.vertices) {
        zA += (v.x - center.x) * vDir.x + (v.y - center.y) * vDir.y + (v.z - center.z) * vDir.z;
      }
      for (final v in b.vertices) {
        zB += (v.x - center.x) * vDir.x + (v.y - center.y) * vDir.y + (v.z - center.z) * vDir.z;
      }
      return (zA / a.vertices.length).compareTo(zB / b.vertices.length);
    });

    // 1. Draw Planar Faces and Profiles
    final strokePaint = Paint()
      ..color = outlineColor
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    final hiddenPaint = Paint()
      ..color = hiddenLineColor
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    final defaultFillPaint = Paint()
      ..color = faceColor
      ..style = PaintingStyle.fill;

    // Directional light vector for shaded renders
    const lx = -0.577;
    const ly = -0.577;
    const lz = 0.577;

    for (final poly in allPolys) {
      if (poly.vertices.length < 3) continue;

      final pts = poly.vertices.map((v) => project(v)).toList();
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();

      final n = poly.normal;
      // Facing dot product
      final dotView = n.x * vDir.x + n.y * vDir.y + n.z * vDir.z;
      final isFrontFacing = dotView >= -0.05;

      if (isShaded) {
        final dotLight = (n.x * lx + n.y * ly + n.z * lz).clamp(0.0, 1.0);
        final intensity = 0.45 + 0.55 * dotLight;
        final baseColor = poly.color;
        final litColor = Color.from(
          alpha: baseColor.a,
          red: (baseColor.r * intensity).clamp(0.0, 1.0),
          green: (baseColor.g * intensity).clamp(0.0, 1.0),
          blue: (baseColor.b * intensity).clamp(0.0, 1.0),
        );
        canvas.drawPath(path, Paint()..color = litColor..style = PaintingStyle.fill);
        canvas.drawPath(path, strokePaint);
      } else {
        if (isFrontFacing) {
          canvas.drawPath(path, defaultFillPaint);
          canvas.drawPath(path, strokePaint);
        } else if (showHiddenLines) {
          // Draw dashed hidden outlines for backfacing features
          _drawDashedPolygon(canvas, pts, hiddenPaint);
        }
      }

      // Draw tangent edges (fillet transitions)
      if (tangentEdgeMode != OnshapeTangentEdgeMode.removed && poly.tangentLines.isNotEmpty) {
        final isPhantom = tangentEdgeMode == OnshapeTangentEdgeMode.phantom;
        final tanPaint = Paint()
          ..color = isPhantom ? const Color(0xFF64748B) : outlineColor.withValues(alpha: 0.6)
          ..strokeWidth = 0.7
          ..style = PaintingStyle.stroke;

        for (final seg in poly.tangentLines) {
          if (seg.length >= 2) {
            final p1 = project(seg[0]);
            final p2 = project(seg[1]);
            if (isPhantom) {
              _drawDashedCenterline(canvas, p1, p2, tanPaint);
            } else {
              canvas.drawLine(p1, p2, tanPaint);
            }
          }
        }
      }
    }

    // 2. Draw Hole & Slot Center Marks
    if (showHoleCenterMarks && m.punchCenters3D.isNotEmpty) {
      final crossPaint = Paint()
        ..color = const Color(0xFF0284C7)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

      for (final pt in m.punchCenters3D.values) {
        final scr = project(pt);
        const s = 5.0;
        canvas.drawLine(Offset(scr.dx - s, scr.dy), Offset(scr.dx + s, scr.dy), crossPaint);
        canvas.drawLine(Offset(scr.dx, scr.dy - s), Offset(scr.dx, scr.dy + s), crossPaint);
      }
    }

    // 3. Draw Centerlines
    final isAxonometric = viewType == DdsOrthographicViewType.isometric ||
        viewType == DdsOrthographicViewType.dimetric ||
        viewType == DdsOrthographicViewType.trimetric;

    if (showCenterlines && !isAxonometric) {
      final centerPaint = Paint()
        ..color = const Color(0xFF94A3B8)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

      _drawDashedCenterline(
        canvas,
        Offset(cx - (extentW * scale / 2) - 12, cy),
        Offset(cx + (extentW * scale / 2) + 12, cy),
        centerPaint,
      );
      _drawDashedCenterline(
        canvas,
        Offset(cx, cy - (extentH * scale / 2) - 12),
        Offset(cx, cy + (extentH * scale / 2) + 12),
        centerPaint,
      );
    }

    // 4. Draw Dimension Lines and Extents
    if (showDimensions && !isAxonometric) {
      final halfW = (extentW * scale) / 2.0;
      final halfH = (extentH * scale) / 2.0;

      // Bottom Horizontal Dimension
      final dimY = cy + halfH + 14.0;
      _drawDimensionArrow(
        canvas,
        Offset(cx - halfW, dimY),
        Offset(cx + halfW, dimY),
        horizDimLabel,
        dimensionColor,
        isVertical: false,
      );

      // Left Vertical Dimension
      final dimX = cx - halfW - 14.0;
      _drawDimensionArrow(
        canvas,
        Offset(dimX, cy + halfH),
        Offset(dimX, cy - halfH),
        vertDimLabel,
        dimensionColor,
        isVertical: true,
      );
    }

    // 5. View Title & Scale Badge
    final titleText = customTitle ?? viewType.title;
    final scaleRatio = (scale < 0.5) ? '1:2' : (scale > 1.5 ? '2:1' : '1:1');
    _paintViewTitleBlock(canvas, size, titleText, scaleRatio);
  }

  void _drawDashedPolygon(Canvas canvas, List<Offset> pts, Paint paint) {
    if (pts.length < 2) return;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      _drawDashedCenterline(canvas, p1, p2, paint);
    }
  }

  void _drawDashedCenterline(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0) return;

    final ux = dx / dist;
    final uy = dy / dist;

    const pattern = [8.0, 2.5, 2.5, 2.5];
    double current = 0.0;
    int patIdx = 0;

    while (current < dist) {
      final segLen = pattern[patIdx % pattern.length];
      final end = math.min(current + segLen, dist);
      if (patIdx % 2 == 0) {
        canvas.drawLine(
          Offset(p1.dx + ux * current, p1.dy + uy * current),
          Offset(p1.dx + ux * end, p1.dy + uy * end),
          paint,
        );
      }
      current += segLen;
      patIdx++;
    }
  }

  void _drawDimensionArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    String label,
    Color color, {
    required bool isVertical,
  }) {
    final dimPaint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    canvas.drawLine(start, end, dimPaint);

    // Arrow heads
    const arrowSize = 4.0;
    if (isVertical) {
      canvas.drawLine(start, Offset(start.dx - arrowSize, start.dy - arrowSize), dimPaint);
      canvas.drawLine(start, Offset(start.dx + arrowSize, start.dy - arrowSize), dimPaint);
      canvas.drawLine(end, Offset(end.dx - arrowSize, end.dy + arrowSize), dimPaint);
      canvas.drawLine(end, Offset(end.dx + arrowSize, end.dy + arrowSize), dimPaint);
    } else {
      canvas.drawLine(start, Offset(start.dx + arrowSize, start.dy - arrowSize), dimPaint);
      canvas.drawLine(start, Offset(start.dx + arrowSize, start.dy + arrowSize), dimPaint);
      canvas.drawLine(end, Offset(end.dx - arrowSize, end.dy - arrowSize), dimPaint);
      canvas.drawLine(end, Offset(end.dx - arrowSize, end.dy + arrowSize), dimPaint);
    }

    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.white.withValues(alpha: 0.9),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final mid = Offset((start.dx + end.dx) / 2.0, (start.dy + end.dy) / 2.0);
    tp.paint(canvas, Offset(mid.dx - tp.width / 2.0, mid.dy - tp.height / 2.0));
  }

  void _paintViewTitleBlock(Canvas canvas, Size size, String title, String scaleRatio) {
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$title\n',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          TextSpan(
            text: 'SCALE $scaleRatio',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 8.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset((size.width - tp.width) / 2.0, size.height - tp.height - 4.0));
  }

  void _paintEmptyText(Canvas canvas, Size size, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2.0, (size.height - tp.height) / 2.0));
  }

  @override
  bool shouldRepaint(covariant DdsOrthographicViewPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.viewType != viewType ||
      oldDelegate.showDimensions != showDimensions ||
      oldDelegate.showCenterlines != showCenterlines ||
      oldDelegate.showHiddenLines != showHiddenLines ||
      oldDelegate.isShaded != isShaded ||
      oldDelegate.tangentEdgeMode != tangentEdgeMode ||
      oldDelegate.showHoleCenterMarks != showHoleCenterMarks;
}

/// Standard ISO 128 / ASME Y14.3 First-Angle and Third-Angle Projection Cone Symbol Painter.
class DdsProjectionSymbolPainter extends CustomPainter {
  final DdsProjectionAngle angle;
  final Color color;

  const DdsProjectionSymbolPainter({
    required this.angle,
    this.color = const Color(0xFF0F172A),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final centerPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    final cy = size.height / 2.0;
    final h1 = size.height * 0.42;
    final h2 = size.height * 0.82;
    final r1 = h1 / 2.0;
    final r2 = h2 / 2.0;

    // Centerline
    canvas.drawLine(Offset(2, cy), Offset(size.width - 2, cy), centerPaint);

    if (angle == DdsProjectionAngle.firstAngle) {
      // 1st Angle: Frustum on left, concentric circles on right
      final frustumLeft = 4.0;
      final frustumRight = size.width * 0.44;
      final path = Path()
        ..moveTo(frustumLeft, cy - r1)
        ..lineTo(frustumRight, cy - r2)
        ..lineTo(frustumRight, cy + r2)
        ..lineTo(frustumLeft, cy + r1)
        ..close();
      canvas.drawPath(path, strokePaint);

      final circleCx = size.width * 0.74;
      canvas.drawLine(Offset(circleCx, cy - r2 - 3), Offset(circleCx, cy + r2 + 3), centerPaint);
      canvas.drawCircle(Offset(circleCx, cy), r1, strokePaint);
      canvas.drawCircle(Offset(circleCx, cy), r2, strokePaint);
    } else {
      // 3rd Angle: Concentric circles on left, frustum on right
      final circleCx = size.width * 0.26;
      canvas.drawLine(Offset(circleCx, cy - r2 - 3), Offset(circleCx, cy + r2 + 3), centerPaint);
      canvas.drawCircle(Offset(circleCx, cy), r1, strokePaint);
      canvas.drawCircle(Offset(circleCx, cy), r2, strokePaint);

      final frustumLeft = size.width * 0.56;
      final frustumRight = size.width - 4.0;
      final path = Path()
        ..moveTo(frustumLeft, cy - r1)
        ..lineTo(frustumRight, cy - r2)
        ..lineTo(frustumRight, cy + r2)
        ..lineTo(frustumLeft, cy + r1)
        ..close();
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant DdsProjectionSymbolPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.color != color;
}

/// 2D Section View Painter with standard ISO cross-hatching and cutting plane callout.
class DdsSectionDrawingPainter extends CustomPainter {
  final FoldedMeshResult? mesh;
  final SectionViewConfig sectionConfig;
  final double sheetThickness;
  final Color crossHatchColor;
  final Color cuttingLineColor;

  DdsSectionDrawingPainter({
    required this.mesh,
    this.sectionConfig = const SectionViewConfig(isEnabled: true),
    this.sheetThickness = 2.0,
    this.crossHatchColor = const Color(0xFF0284C7),
    this.cuttingLineColor = const Color(0xFFDC2626),
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    if (mesh == null || mesh!.polygons.isEmpty) {
      _paintEmptyText(canvas, size, 'Awaiting Geometry for Section Cut...');
      return;
    }

    final m = mesh!;
    final center = m.center;
    final maxDim = math.max(m.boundWidth, math.max(m.boundLength, m.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 150.0;
    final scale = (math.min(size.width, size.height) * 0.70) / fitDim;
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    // 1. Draw Sliced Cross Section Faces with 45° Diagonal Hatching
    final hatchPaint = Paint()
      ..color = crossHatchColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    final boundaryPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.fill;

    for (final poly in m.polygons) {
      if (poly.vertices.length < 3) continue;

      final pts = poly.vertices.map((v) {
        final dx = v.x - center.x;
        final dz = v.z - center.z;
        return Offset(cx + dx * scale, cy - dz * scale);
      }).toList();

      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, boundaryPaint);

      // Clip and paint diagonal cross-hatching inside cut faces
      canvas.save();
      canvas.clipPath(path);
      for (double x = -size.height; x < size.width + size.height; x += 6.0) {
        canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), hatchPaint);
      }
      canvas.restore();
    }

    // 2. Cutting Plane Indicators (A ◄────────────► A)
    final cutY = cy - 25.0;
    final cutLinePaint = Paint()
      ..color = cuttingLineColor
      ..strokeWidth = 1.6;

    canvas.drawLine(Offset(24.0, cutY), Offset(size.width - 24.0, cutY), cutLinePaint);
    _drawCutArrow(canvas, Offset(24.0, cutY), true, cuttingLineColor);
    _drawCutArrow(canvas, Offset(size.width - 24.0, cutY), false, cuttingLineColor);

    // Callout Letters
    _paintCalloutLetter(canvas, Offset(16.0, cutY - 6), 'A', cuttingLineColor);
    _paintCalloutLetter(canvas, Offset(size.width - 20.0, cutY - 6), 'A', cuttingLineColor);

    // 3. Section Title & Material Callout
    final titlePainter = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(
            text: 'SECTION A - A (CROSS SECTION)\n',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          TextSpan(
            text: 'SHEET THICKNESS: ${sheetThickness.toStringAsFixed(1)} mm  |  SCALE 1:1  |  HATCH: ISO STEEL 45°',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    titlePainter.paint(canvas, Offset((size.width - titlePainter.width) / 2.0, size.height - titlePainter.height - 8.0));
  }

  void _drawCutArrow(Canvas canvas, Offset pos, bool pointingRight, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    final dir = pointingRight ? 1.0 : -1.0;
    canvas.drawLine(pos, Offset(pos.dx + dir * 8, pos.dy - 6), p);
    canvas.drawLine(pos, Offset(pos.dx + dir * 8, pos.dy + 6), p);
  }

  void _paintCalloutLetter(Canvas canvas, Offset pos, String letter, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: letter, style: TextStyle(color: color, fontSize: 12.0, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  void _paintEmptyText(Canvas canvas, Size size, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2.0, (size.height - tp.height) / 2.0));
  }

  @override
  bool shouldRepaint(covariant DdsSectionDrawingPainter oldDelegate) =>
      oldDelegate.mesh != mesh || oldDelegate.sectionConfig != sectionConfig;
}

/// 2D Unfolded Flat Pattern Drawing Painter with bend line callouts and blank dimensions.
class DdsFlatPatternDrawingPainter extends CustomPainter {
  final DsfDocument? document;
  final Color outlineColor;
  final Color bendUpColor;
  final Color bendDownColor;
  final Color dimensionColor;

  DdsFlatPatternDrawingPainter({
    required this.document,
    this.outlineColor = const Color(0xFF0284C7),
    this.bendUpColor = const Color(0xFFD97706),
    this.bendDownColor = const Color(0xFF2563EB),
    this.dimensionColor = const Color(0xFF0F172A),
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    if (document == null || document!.faces.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(text: 'Awaiting Unfolded Flat Pattern...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2.0, (size.height - tp.height) / 2.0));
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

    if (minX == double.infinity) return;
    final modelW = maxX - minX;
    final modelH = maxY - minY;
    if (modelW <= 0 || modelH <= 0) return;

    const pad = 42.0;
    final scale = math.min((size.width - pad * 2) / modelW, (size.height - pad * 2) / modelH);
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final modelMidX = (minX + maxX) / 2.0;
    final modelMidY = (minY + maxY) / 2.0;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale, -scale);
    canvas.translate(-modelMidX, -modelMidY);

    // 1. Draw Flat Faces & Outer Cut Boundary
    final facePaint = Paint()..color = const Color(0xFFF8FAFC)..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..color = outlineColor
      ..strokeWidth = 1.4 / scale
      ..style = PaintingStyle.stroke;

    for (final face in doc.faces) {
      if (face.vertices.length < 3) continue;
      final path = Path()..moveTo(face.vertices.first.x, face.vertices.first.y);
      for (int i = 1; i < face.vertices.length; i++) {
        path.lineTo(face.vertices[i].x, face.vertices[i].y);
      }
      path.close();
      canvas.drawPath(path, facePaint);
      canvas.drawPath(path, outlinePaint);
    }

    // 2. Draw Bend Lines with UP/DOWN color coding
    for (final bend in doc.bends) {
      final isUp = bend.angleDeg >= 0;
      final bendPaint = Paint()
        ..color = isUp ? bendUpColor : bendDownColor
        ..strokeWidth = 1.2 / scale
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(bend.x1, bend.y1), Offset(bend.x2, bend.y2), bendPaint);
    }

    canvas.restore();

    // 3. Overall Blank Bounding Dimensions Callout
    final infoPainter = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(
            text: 'FLAT PATTERN BLANK (UNFOLDED)\n',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 10.0, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          TextSpan(
            text: 'BLANK SIZE: ${modelW.toStringAsFixed(1)} × ${modelH.toStringAsFixed(1)} mm  |  BENDS: ${doc.bends.length}  |  THICKNESS: ${doc.material.thicknessMm.toStringAsFixed(1)} mm',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    infoPainter.paint(canvas, Offset((size.width - infoPainter.width) / 2.0, size.height - infoPainter.height - 8.0));
  }

  @override
  bool shouldRepaint(covariant DdsFlatPatternDrawingPainter oldDelegate) => oldDelegate.document != document;
}

