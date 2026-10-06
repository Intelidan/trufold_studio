import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/vector_cad_entity.dart';

/// Result of a CAD point snap calculation.
class CadSnapResult {
  final Offset point;
  final bool isSnapped;
  final String snapType; // 'vertex', 'center', 'grid', 'none'
  final String? snapTargetName;

  const CadSnapResult({
    required this.point,
    required this.isSnapped,
    this.snapType = 'none',
    this.snapTargetName,
  });
}

/// CAD Snapping Engine: Performs geometric vertex, center, and grid snapping.
class CadSnapEngine {
  bool isGridSnapEnabled;
  double gridSizeMm;
  double vertexSnapRadiusMm;

  CadSnapEngine({
    this.isGridSnapEnabled = true,
    this.gridSizeMm = 20.0,
    this.vertexSnapRadiusMm = 8.0,
  });

  CadSnapResult snapPoint({
    required Offset rawPointMm,
    required List<VectorCadEntity> entities,
  }) {
    // 1. First priority: Vertex / Anchor Snapping to existing geometry
    for (final entity in entities) {
      if (entity is VectorCadLine) {
        if ((rawPointMm - entity.p1).distance <= vertexSnapRadiusMm) {
          return CadSnapResult(
            point: entity.p1,
            isSnapped: true,
            snapType: 'vertex',
            snapTargetName: '${entity.label} Start',
          );
        }
        if ((rawPointMm - entity.p2).distance <= vertexSnapRadiusMm) {
          return CadSnapResult(
            point: entity.p2,
            isSnapped: true,
            snapType: 'vertex',
            snapTargetName: '${entity.label} End',
          );
        }
        // Midpoint snap
        final mid = (entity.p1 + entity.p2) / 2.0;
        if ((rawPointMm - mid).distance <= vertexSnapRadiusMm) {
          return CadSnapResult(
            point: mid,
            isSnapped: true,
            snapType: 'center',
            snapTargetName: '${entity.label} Midpoint',
          );
        }
      } else if (entity is VectorCadRect) {
        final r = entity.rect;
        final corners = [
          r.topLeft,
          r.topRight,
          r.bottomRight,
          r.bottomLeft,
          r.center,
        ];
        for (int i = 0; i < 4; i++) {
          if ((rawPointMm - corners[i]).distance <= vertexSnapRadiusMm) {
            return CadSnapResult(
              point: corners[i],
              isSnapped: true,
              snapType: 'vertex',
              snapTargetName: '${entity.label} Corner',
            );
          }
        }
        if ((rawPointMm - corners[4]).distance <= vertexSnapRadiusMm) {
          return CadSnapResult(
            point: corners[4],
            isSnapped: true,
            snapType: 'center',
            snapTargetName: '${entity.label} Center',
          );
        }
      } else if (entity is VectorCadCircle) {
        if ((rawPointMm - entity.center).distance <= vertexSnapRadiusMm) {
          return CadSnapResult(
            point: entity.center,
            isSnapped: true,
            snapType: 'center',
            snapTargetName: '${entity.label} Center',
          );
        }
        // Cardinal points on circumference (0°, 90°, 180°, 270°)
        for (final angle in [0.0, math.pi / 2, math.pi, 3 * math.pi / 2]) {
          final cardinal = entity.center + Offset(math.cos(angle), math.sin(angle)) * entity.radius;
          if ((rawPointMm - cardinal).distance <= vertexSnapRadiusMm) {
            return CadSnapResult(
              point: cardinal,
              isSnapped: true,
              snapType: 'vertex',
              snapTargetName: '${entity.label} Quadrant',
            );
          }
        }
      } else if (entity is VectorCadPolyline) {
        for (final pt in entity.points) {
          if ((rawPointMm - pt).distance <= vertexSnapRadiusMm) {
            return CadSnapResult(
              point: pt,
              isSnapped: true,
              snapType: 'vertex',
              snapTargetName: '${entity.label} Vertex',
            );
          }
        }
      }
    }

    // 2. Second priority: Grid matrix snapping
    if (isGridSnapEnabled && gridSizeMm > 0.0) {
      final snappedX = (rawPointMm.dx / gridSizeMm).roundToDouble() * gridSizeMm;
      final snappedY = (rawPointMm.dy / gridSizeMm).roundToDouble() * gridSizeMm;
      return CadSnapResult(
        point: Offset(snappedX, snappedY),
        isSnapped: true,
        snapType: 'grid',
        snapTargetName: 'Grid (${gridSizeMm.toStringAsFixed(0)}mm)',
      );
    }

    // 3. Fallback: Raw point without snapping
    return CadSnapResult(
      point: rawPointMm,
      isSnapped: false,
      snapType: 'none',
    );
  }
}
