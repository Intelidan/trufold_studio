// =============================================================================
// assembly_gpu_edge_antialias_painter.dart
//
// Screen-Space Topological Edge Anti-Aliasing Overlay for Flutter GPU Viewport.
// Projects outer contour edges and hole rims with crisp, anti-aliased 2D strokes,
// eliminating jagged stair-stepping at any display resolution.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';

class AssemblyGpuEdgeAntiAliasPainter extends CustomPainter {
  final FoldedMeshResult mesh;
  final Offset Function(CadPoint3D) projectPoint;
  final double lineWidth;
  final bool silhouetteBoost;

  AssemblyGpuEdgeAntiAliasPainter({
    required this.mesh,
    required this.projectPoint,
    required this.lineWidth,
    required this.silhouetteBoost,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.polygons.isEmpty) return;

    final baseWidth = lineWidth.clamp(0.8, 3.5);
    final edgePaint = Paint()
      ..color = const Color(0xE61B242D) // Onshape dark charcoal-slate
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final rimPaint = Paint()
      ..color = const Color(0xE61B242D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseWidth * (silhouetteBoost ? 1.35 : 1.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (final poly in mesh.polygons) {
      if (poly.vertices.length < 3) continue;

      // Draw perimeter wireframe edge
      final p0 = projectPoint(poly.vertices[0]);
      if (p0 != Offset.zero) {
        final path = Path()..moveTo(p0.dx, p0.dy);
        for (int i = 1; i < poly.vertices.length; i++) {
          final p = projectPoint(poly.vertices[i]);
          if (p != Offset.zero) path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path, edgePaint);
      }

      // Draw hole rims
      for (final hole in poly.holes) {
        if (hole.length < 3) continue;
        final h0 = projectPoint(hole[0]);
        if (h0 != Offset.zero) {
          final hPath = Path()..moveTo(h0.dx, h0.dy);
          for (int i = 1; i < hole.length; i++) {
            final hp = projectPoint(hole[i]);
            if (hp != Offset.zero) hPath.lineTo(hp.dx, hp.dy);
          }
          hPath.close();
          canvas.drawPath(hPath, rimPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant AssemblyGpuEdgeAntiAliasPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.silhouetteBoost != silhouetteBoost;
  }
}
