import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/vector_cad_entity.dart';
import 'cad_snap_engine.dart';

/// High-performance 2D CAD vector custom painter.
/// Directly paints the technical drafting grid, CAD primitives, selection handles,
/// and live construction geometry at 120 FPS.
class CadVectorPainter extends CustomPainter {
  final List<VectorCadEntity> entities;
  final VectorCadEntity? selectedEntity;
  final VectorCadEntity? tempEntity;
  final CadSnapResult? snapResult;
  final Offset panOffset;
  final double scale; // px per mm
  final double gridSizeMm;
  final bool showGrid;

  CadVectorPainter({
    required this.entities,
    this.selectedEntity,
    this.tempEntity,
    this.snapResult,
    this.panOffset = Offset.zero,
    this.scale = 1.0,
    this.gridSizeMm = 20.0,
    this.showGrid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Technical Dark Grid Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0D0D0D),
    );

    canvas.save();
    // Apply pan & zoom coordinate transformation (mm space -> screen px space)
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);

    // Visible viewport bounds in CAD mm coordinates
    final visibleLeft = -panOffset.dx / scale;
    final visibleTop = -panOffset.dy / scale;
    final visibleRight = visibleLeft + size.width / scale;
    final visibleBottom = visibleTop + size.height / scale;

    if (showGrid && gridSizeMm > 0.0) {
      _drawGrid(canvas, visibleLeft, visibleTop, visibleRight, visibleBottom);
    }

    // 2. Draw Vector Entities
    for (final entity in entities) {
      if (entity == selectedEntity) continue; // Draw selected entity on top with handles
      _drawEntity(canvas, entity, isSelected: false);
    }

    // 3. Draw Selected Entity & Selection Bounding Box with Anchor Handles
    if (selectedEntity != null) {
      _drawEntity(canvas, selectedEntity!, isSelected: true);
      _drawSelectionBox(canvas, selectedEntity!);
    }

    // 4. Draw Active In-Progress Construction Entity (Yellow)
    if (tempEntity != null) {
      _drawEntity(canvas, tempEntity!, isConstruction: true);
    }

    // 5. Draw Snap Indicator Marker
    if (snapResult != null && snapResult!.isSnapped) {
      _drawSnapIndicator(canvas, snapResult!);
    }

    canvas.restore();
  }

  void _drawGrid(Canvas canvas, double left, double top, double right, double bottom) {
    final minorPaint = Paint()
      ..color = const Color(0xFF1E2638)
      ..strokeWidth = 1.0 / scale;

    final majorPaint = Paint()
      ..color = const Color(0xFF2C3E50)
      ..strokeWidth = 1.2 / scale;

    final axisPaint = Paint()
      ..color = const Color(0xFF0284C7).withValues(alpha: 0.65)
      ..strokeWidth = 1.5 / scale;

    final startX = (left / gridSizeMm).floor() * gridSizeMm;
    final endX = (right / gridSizeMm).ceil() * gridSizeMm;
    final startY = (top / gridSizeMm).floor() * gridSizeMm;
    final endY = (bottom / gridSizeMm).ceil() * gridSizeMm;

    // Vertical grid lines
    for (double x = startX; x <= endX; x += gridSizeMm) {
      final isMajor = (x / (gridSizeMm * 5)).roundToDouble() == (x / (gridSizeMm * 5));
      final p = (x.abs() < 1e-4) ? axisPaint : (isMajor ? majorPaint : minorPaint);
      canvas.drawLine(Offset(x, top), Offset(x, bottom), p);
    }

    // Horizontal grid lines
    for (double y = startY; y <= endY; y += gridSizeMm) {
      final isMajor = (y / (gridSizeMm * 5)).roundToDouble() == (y / (gridSizeMm * 5));
      final p = (y.abs() < 1e-4) ? axisPaint : (isMajor ? majorPaint : minorPaint);
      canvas.drawLine(Offset(left, y), Offset(right, y), p);
    }
  }

  void _drawEntity(Canvas canvas, VectorCadEntity entity, {bool isSelected = false, bool isConstruction = false}) {
    final strokeColor = isConstruction
        ? const Color(0xFFFFCC00) // Active construction yellow (matching HTML demo)
        : (isSelected ? const Color(0xFFEF4444) : entity.color);

    final strokePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = (isConstruction ? 2.2 : entity.strokeWidth) / scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = isConstruction
          ? const Color(0x22FFCC00)
          : (isSelected ? const Color(0x22EF4444) : strokeColor.withValues(alpha: 0.12))
      ..style = PaintingStyle.fill;

    if (entity is VectorCadLine) {
      if (entity.isDashed || entity.role == 'bend') {
        _drawDashedLine(canvas, entity.p1, entity.p2, strokePaint);
      } else {
        canvas.drawLine(entity.p1, entity.p2, strokePaint);
      }
    } else if (entity is VectorCadRect) {
      final r = entity.rect;
      if (entity.isFilled || isConstruction) {
        canvas.drawRect(r, fillPaint);
      }
      canvas.drawRect(r, strokePaint);
    } else if (entity is VectorCadCircle) {
      if (entity.isFilled || isConstruction) {
        canvas.drawCircle(entity.center, entity.radius, fillPaint);
      }
      canvas.drawCircle(entity.center, entity.radius, strokePaint);

      // Punch hole center crosshair
      final crossLen = math.min(entity.radius * 0.45, 6.0 / scale);
      if (crossLen > 1.0) {
        final crossPaint = Paint()
          ..color = strokeColor.withValues(alpha: 0.70)
          ..strokeWidth = 1.0 / scale;
        canvas.drawLine(entity.center - Offset(crossLen, 0), entity.center + Offset(crossLen, 0), crossPaint);
        canvas.drawLine(entity.center - Offset(0, crossLen), entity.center + Offset(0, crossLen), crossPaint);
      }
    } else if (entity is VectorCadPolyline) {
      if (entity.points.length >= 2) {
        final path = Path()..moveTo(entity.points.first.dx, entity.points.first.dy);
        for (int i = 1; i < entity.points.length; i++) {
          path.lineTo(entity.points[i].dx, entity.points[i].dy);
        }
        if (entity.isClosed) {
          path.close();
          if (entity.isFilled) canvas.drawPath(path, fillPaint);
        }
        canvas.drawPath(path, strokePaint);
      }
    }
  }

  void _drawSelectionBox(Canvas canvas, VectorCadEntity entity) {
    // Exact match to user screenshot: Red bounding box with corner anchor handles
    final b = entity.bounds;
    final boxPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 1.5 / scale
      ..style = PaintingStyle.stroke;

    canvas.drawRect(b, boxPaint);

    // Anchor handles at 4 corners
    final handleRadius = 4.5 / scale;
    final handleFill = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    final handleStroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2 / scale
      ..style = PaintingStyle.stroke;

    final corners = [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
    for (final c in corners) {
      canvas.drawCircle(c, handleRadius, handleFill);
      canvas.drawCircle(c, handleRadius, handleStroke);
    }

    // Dimension callouts
    if (entity is VectorCadRect) {
      _drawDimensionText(canvas, '${entity.width.toStringAsFixed(1)} mm', Offset(b.center.dx, b.top - 10.0 / scale));
      _drawDimensionText(canvas, '${entity.height.toStringAsFixed(1)} mm', Offset(b.right + 16.0 / scale, b.center.dy));
    } else if (entity is VectorCadLine) {
      final mid = (entity.p1 + entity.p2) / 2.0;
      final label = (entity.role == 'bend' || entity.isDashed)
          ? '${entity.length.toStringAsFixed(1)} mm  [${entity.bendAngleDeg.toStringAsFixed(0)}° ${entity.bendDirection}]'
          : '${entity.length.toStringAsFixed(1)} mm';
      _drawDimensionText(canvas, label, mid - Offset(0, 10.0 / scale));
    } else if (entity is VectorCadCircle) {
      _drawDimensionText(canvas, 'Ø ${entity.diameter.toStringAsFixed(1)} mm', Offset(entity.center.dx, entity.center.dy - entity.radius - 10.0 / scale));
    }
  }

  void _drawDimensionText(Canvas canvas, String text, Offset center) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFFEF4444),
          fontSize: math.max(10.0 / scale, 7.5),
          fontWeight: FontWeight.bold,
          backgroundColor: const Color(0xDD0D0D0D),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawSnapIndicator(Canvas canvas, CadSnapResult snap) {
    final pt = snap.point;
    final snapPaint = Paint()
      ..color = const Color(0xFFFFCC00)
      ..strokeWidth = 1.4 / scale
      ..style = PaintingStyle.stroke;

    final radius = 5.0 / scale;
    if (snap.snapType == 'vertex') {
      // Square box snap marker
      canvas.drawRect(Rect.fromCircle(center: pt, radius: radius), snapPaint);
    } else if (snap.snapType == 'center') {
      // Circle snap marker
      canvas.drawCircle(pt, radius, snapPaint);
    } else {
      // Diamond grid snap marker
      final path = Path()
        ..moveTo(pt.dx, pt.dy - radius)
        ..lineTo(pt.dx + radius, pt.dy)
        ..lineTo(pt.dx, pt.dy + radius)
        ..lineTo(pt.dx - radius, pt.dy)
        ..close();
      canvas.drawPath(path, snapPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final diff = p2 - p1;
    final dist = diff.distance;
    if (dist < 1e-4) return;
    final dir = diff / dist;
    final dashLen = 6.0 / scale;
    final gapLen = 4.0 / scale;
    double cur = 0.0;
    while (cur < dist) {
      final end = math.min(cur + dashLen, dist);
      canvas.drawLine(p1 + dir * cur, p1 + dir * end, paint);
      cur += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant CadVectorPainter oldDelegate) {
    return oldDelegate.entities != entities ||
        oldDelegate.selectedEntity != selectedEntity ||
        oldDelegate.tempEntity != tempEntity ||
        oldDelegate.snapResult != snapResult ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.scale != scale ||
        oldDelegate.gridSizeMm != gridSizeMm ||
        oldDelegate.showGrid != showGrid;
  }
}
