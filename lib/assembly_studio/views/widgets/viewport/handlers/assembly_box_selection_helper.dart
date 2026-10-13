// Two-Way (Window & Crossing) Box Selection Helper
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

class AssemblyBoxSelectionHelper {
  /// Extracts projected 2D screen vertices / bounding corners for a part
  static List<Offset> getPartScreenCorners({
    required AssemblyPart part,
    required Size size,
    required FoldedMeshResult mesh,
    required Offset Function(CadPoint3D pt) projectPoint,
  }) {
    // 1. If mesh has polygons corresponding to this part, extract projected vertices
    final matchingPolys = mesh.allPolygons.where(
      (poly) => poly.faceId == part.id || poly.faceId.startsWith('${part.id}_'),
    );
    if (matchingPolys.isNotEmpty) {
      final pts = <Offset>[];
      for (final poly in matchingPolys) {
        for (final v in poly.vertices) {
          final scr = projectPoint(v);
          if (scr != Offset.zero) pts.add(scr);
        }
      }
      if (pts.isNotEmpty) return pts;
    }

    // 2. Fallback: 8 bounding box corners around part position and dimensions
    final l = part.length > 0 ? part.length : 100.0;
    final h = part.height > 0 ? part.height : 40.0;
    final w = part.flangeWidth > 0 ? part.flangeWidth * 2 : 40.0;

    final corners = <CadPoint3D>[
      part.toWorld(const CadPoint3D(0, 0, 0)),
      part.toWorld(CadPoint3D(l, 0, 0)),
      part.toWorld(CadPoint3D(0, w, 0)),
      part.toWorld(CadPoint3D(l, w, 0)),
      part.toWorld(CadPoint3D(0, 0, h)),
      part.toWorld(CadPoint3D(l, 0, h)),
      part.toWorld(CadPoint3D(0, w, h)),
      part.toWorld(CadPoint3D(l, w, h)),
    ];

    return corners.map(projectPoint).where((p) => p != Offset.zero).toList();
  }

  /// Determines if a part is selected according to SketchUp selection rules:
  /// - Window Selection (Left-to-Right, solid blue): All corners must be completely inside the box.
  /// - Crossing Selection (Right-to-Left, dashed green): Any corner inside OR part bounds overlap box.
  static bool isPartSelected({
    required Rect boxRect,
    required List<Offset> corners,
    required bool isCrossingSelect,
  }) {
    if (corners.isEmpty) return false;

    if (isCrossingSelect) {
      // Any corner inside the rectangle
      if (corners.any(boxRect.contains)) return true;

      // Or bounding rectangle intersection
      double minX = corners.first.dx, maxX = corners.first.dx;
      double minY = corners.first.dy, maxY = corners.first.dy;
      for (final c in corners) {
        if (c.dx < minX) minX = c.dx;
        if (c.dx > maxX) maxX = c.dx;
        if (c.dy < minY) minY = c.dy;
        if (c.dy > maxY) maxY = c.dy;
      }
      final partRect = Rect.fromLTRB(minX, minY, maxX, maxY);
      return boxRect.overlaps(partRect);
    } else {
      // Window selection: every single corner must be inside the box
      return corners.every(boxRect.contains);
    }
  }
}
