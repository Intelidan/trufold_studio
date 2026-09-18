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
    String? hoveredConstraintId,
    Map<String, Rect>? renderedConstraintBadges,
    List<ReferenceGeometry>? customReferences,
  }) {
    if (constraints.isEmpty) return;

    for (final constraint in constraints) {
      if (!constraint.isActive || constraint.isSuppressed) continue;
      final isSelected = constraint.id == selectedConstraintId;
      final isHovered = constraint.id == hoveredConstraintId;

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
          ..color = (isSelected || isHovered)
              ? const Color(0xFF0284C7)
              : const Color(0xFF0D9488).withValues(alpha: 0.5)
          ..strokeWidth = (isSelected || isHovered) ? 1.8 : 1.0
          ..style = PaintingStyle.stroke;

        canvas.drawLine(p1, p2, linkPaint);
        canvas.drawCircle(p1, 2.5, Paint()..color = linkPaint.color);
        canvas.drawCircle(p2, 2.5, Paint()..color = linkPaint.color);

        // Center glyph between the two entities
        final mid = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);
        final badgeRect = _drawGlyph(
          canvas,
          glyph: constraint.symbol,
          position: mid,
          isSelected: isSelected,
          isHovered: isHovered,
          valueText: constraint.targetValue != null
              ? '${constraint.targetValue!.toStringAsFixed(1)} mm'
              : null,
        );
        if (renderedConstraintBadges != null) {
          renderedConstraintBadges[constraint.id] = badgeRect;
        }
      } else {
        // Single entity glyph
        final pos = resolvedPoints.first;
        final badgeRect = _drawGlyph(
          canvas,
          glyph: constraint.symbol,
          position: Offset(pos.dx + 12, pos.dy - 12),
          isSelected: isSelected,
          isHovered: isHovered,
        );
        if (renderedConstraintBadges != null) {
          renderedConstraintBadges[constraint.id] = badgeRect;
        }
      }
    }
  }

  static Rect _drawGlyph(
    Canvas canvas, {
    required String glyph,
    required Offset position,
    bool isSelected = false,
    bool isHovered = false,
    String? valueText,
  }) {
    final hasDeleteIcon = isSelected || isHovered;
    final displayText = valueText != null ? '$glyph $valueText' : glyph;
    final fullText = hasDeleteIcon ? '$displayText ✕' : displayText;

    final textSpan = TextSpan(
      text: fullText,
      style: TextStyle(
        color: (isSelected || isHovered)
            ? const Color(0xFF0284C7)
            : const Color(0xFF0F172A),
        fontSize: 9.5,
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
        width: textPainter.width + 10,
        height: textPainter.height + 5,
      ),
      const Radius.circular(4),
    );

    // Subtle drop shadow if hovered/selected
    if (isSelected || isHovered) {
      canvas.drawRRect(
        badgeRect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // Background
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = (isSelected || isHovered)
            ? const Color(0xFFF0F9FF)
            : Colors.white.withValues(alpha: 0.95),
    );

    // Border
    final borderColor = isSelected
        ? const Color(0xFF0284C7)
        : (isHovered ? const Color(0xFF06B6D4) : const Color(0xFF94A3B8));

    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = (isSelected || isHovered) ? 1.6 : 0.9,
    );

    textPainter.paint(
      canvas,
      Offset(badgeRect.left + 5, badgeRect.top + 2.5),
    );

    return badgeRect.outerRect;
  }
}
