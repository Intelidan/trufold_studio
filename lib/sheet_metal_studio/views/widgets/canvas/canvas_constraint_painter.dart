// =============================================================================
// canvas_constraint_painter.dart
//
// Modular Canvas Painter for Constraint Symbols & Associative Links
// per Phase 1 Master Guide Sections 16, 17, 18 & Set 05.
//
// Renders:
// - Geometric constraint glyphs: H, V, //, ⊥, ◎, ⇋, =, 🔒
// - Dimensional constraint leader lines & value tags
// - Visual selection halo when constraint is active in inspector
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/cad_primitives.dart';
import '../../../models/dsf_document.dart';
import '../../../models/constraints/constraint_definition.dart';
import '../../../models/constraints/reference_geometry.dart';
import '../../../engine/constraints/reference_geometry_engine.dart';

class CanvasConstraintPainter {
  /// Renders all active constraint glyphs and associative leader lines
  static void paint({
    required Canvas canvas,
    required Size size,
    required DsfDocument document,
    required List<ConstraintDefinition> constraints,
    required Offset Function(CadPoint2D) cadToScreen,
    String? selectedConstraintId,
    List<ReferenceGeometry>? customReferences,
  }) {
    if (constraints.isEmpty) return;

    for (final constraint in constraints) {
      if (!constraint.isActive || constraint.isSuppressed) continue;
      final isSelected = constraint.id == selectedConstraintId;

      if (constraint.references.isEmpty) continue;

      // Resolve positions of references
      final resolvedPoints = <Offset>[];
      for (final ref in constraint.references) {
        final pt = ReferenceGeometryEngine.resolvePoint(
          ref: ref,
          document: document,
          customReferences: customReferences,
        );
        if (pt != null) {
          resolvedPoints.add(cadToScreen(pt.point));
        } else {
          final edge = ReferenceGeometryEngine.resolveEdge(
            ref: ref,
            document: document,
            customReferences: customReferences,
          );
          if (edge != null) {
            resolvedPoints.add(cadToScreen(edge.midpoint));
          }
        }
      }

      if (resolvedPoints.isEmpty) continue;

      // Draw associative connecting line if constraint binds 2 entities
      if (resolvedPoints.length >= 2) {
        final p1 = resolvedPoints[0];
        final p2 = resolvedPoints[1];

        final linkPaint = Paint()
          ..color = isSelected
              ? const Color(0xFF0284C7)
              : const Color(0xFF0D9488).withValues(alpha: 0.5)
          ..strokeWidth = isSelected ? 1.5 : 1.0
          ..style = PaintingStyle.stroke;

        canvas.drawLine(p1, p2, linkPaint);
        canvas.drawCircle(p1, 2.5, Paint()..color = linkPaint.color);
        canvas.drawCircle(p2, 2.5, Paint()..color = linkPaint.color);

        // Center glyph between the two entities
        final mid = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);
        _drawGlyph(
          canvas,
          glyph: constraint.symbol,
          position: mid,
          isSelected: isSelected,
          valueText: constraint.targetValue != null
              ? '${constraint.targetValue!.toStringAsFixed(1)} mm'
              : null,
        );
      } else {
        // Single entity glyph
        final pos = resolvedPoints.first;
        _drawGlyph(
          canvas,
          glyph: constraint.symbol,
          position: Offset(pos.dx + 12, pos.dy - 12),
          isSelected: isSelected,
        );
      }
    }
  }

  static void _drawGlyph(
    Canvas canvas, {
    required String glyph,
    required Offset position,
    bool isSelected = false,
    String? valueText,
  }) {
    final displayText = valueText != null ? '$glyph $valueText' : glyph;
    final textSpan = TextSpan(
      text: displayText,
      style: TextStyle(
        color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
        fontSize: 9.0,
        fontWeight: FontWeight.bold,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: position,
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      ),
      const Radius.circular(3),
    );

    // Background
    canvas.drawRRect(
      badgeRect,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    // Border
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = isSelected ? const Color(0xFF0284C7) : const Color(0xFF94A3B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 1.5 : 0.8,
    );

    textPainter.paint(
      canvas,
      Offset(badgeRect.left + 4, badgeRect.top + 2),
    );
  }
}
