// =============================================================================
// contour_topology_classifier.dart
//
// Topology Classification Engine for Sheet Metal Studio (SET 17 & 19).
// Analyzes flat 2D outer contours and bend arrangements to identify fitting
// topologies (Rectangular trays, Equal/Unequal Tees, Reducers, Crosses, Bends)
// allowing the GeometricConstraintSolver to apply branch-zone solving.
// =============================================================================

import 'dart:math' as math;
import '../../models/cad_primitives.dart';
import '../../models/fold_bend_line.dart';
import '../../models/dsf_document.dart';

enum ContourTopologyType {
  rectangular, // Straight cable tray, covers, flat plates
  tBranch, // Equal & Unequal Tee (3 ports, 12-16 vertices)
  crossBranch, // Equal & Unequal Cross (4 ports, 16-20 vertices)
  taperedReducer, // Concentric / Eccentric Reducer (2 ports with angled transition)
  lBend, // 90° and 45° flat bends
  arbitraryPoly, // General irregular sheet metal polygon
}

class ContourTopologyClassifier {
  /// Classifies the topology of a blank contour.
  /// Accepts optional bends and document for fast-path template/metadata verification.
  static ContourTopologyType classify(
    List<CadPoint2D> contour, [
    List<FoldBendLine>? bends,
    DsfDocument? document,
  ]) {
    // 1. Fast-path check from document metadata or product naming
    if (document != null) {
      final appliedTemplate = document.metadata['appliedTemplate']?.toString().toLowerCase() ?? '';
      if (appliedTemplate == 'tray_tee' || appliedTemplate.contains('tee')) {
        return ContourTopologyType.tBranch;
      }
      if (appliedTemplate == 'tray_reducer' || appliedTemplate.contains('reducer')) {
        return ContourTopologyType.taperedReducer;
      }
      if (appliedTemplate == 'tray_cross' || appliedTemplate.contains('cross')) {
        return ContourTopologyType.crossBranch;
      }
      if (appliedTemplate.contains('bend')) {
        return ContourTopologyType.lBend;
      }
      if (appliedTemplate == 'tray_straight' || appliedTemplate.contains('straight')) {
        return ContourTopologyType.rectangular;
      }

      final name = '${document.productType} ${document.itemName}'.toLowerCase();
      if (name.contains('tee')) return ContourTopologyType.tBranch;
      if (name.contains('reducer')) return ContourTopologyType.taperedReducer;
      if (name.contains('cross')) return ContourTopologyType.crossBranch;
      if (name.contains('bend') && !name.contains('line')) return ContourTopologyType.lBend;
    }

    // 2. Geometric analysis on outer contour vertices
    if (contour.length < 3) {
      return ContourTopologyType.arbitraryPoly;
    }

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final p in contour) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    if (width <= 1e-3 || height <= 1e-3) {
      return ContourTopologyType.arbitraryPoly;
    }

    // Shoelace polygon area
    double doubleArea = 0.0;
    final n = contour.length;
    for (int i = 0; i < n; i++) {
      final p1 = contour[i];
      final p2 = contour[(i + 1) % n];
      doubleArea += (p1.x * p2.y) - (p2.x * p1.y);
    }
    final actualArea = (doubleArea / 2.0).abs();
    final bboxArea = width * height;
    final fillRatio = actualArea / bboxArea;

    // Check for sloped/tapered transition edges (Reducer detection)
    int slopedEdgeCount = 0;
    for (int i = 0; i < n; i++) {
      final p1 = contour[i];
      final p2 = contour[(i + 1) % n];
      final dx = (p2.x - p1.x).abs();
      final dy = (p2.y - p1.y).abs();
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 15.0 && dx > 3.0 && dy > 3.0) {
        slopedEdgeCount++;
      }
    }

    if (slopedEdgeCount >= 2 && fillRatio < 0.88 && fillRatio > 0.45) {
      return ContourTopologyType.taperedReducer;
    }

    // Check 3x3 grid occupancy to distinguish T-shape, Cross, L-bend, and Rectangle
    final occupiedGrid = List.generate(3, (_) => List.generate(3, (_) => false));
    const sampleSteps = 6;
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final cellMinX = minX + col * (width / 3.0);
        final cellMaxX = minX + (col + 1) * (width / 3.0);
        final cellMinY = minY + row * (height / 3.0);
        final cellMaxY = minY + (row + 1) * (height / 3.0);

        bool cellInside = false;
        for (int sx = 1; sx < sampleSteps; sx++) {
          for (int sy = 1; sy < sampleSteps; sy++) {
            final testX = cellMinX + (cellMaxX - cellMinX) * (sx / sampleSteps);
            final testY = cellMinY + (cellMaxY - cellMinY) * (sy / sampleSteps);
            if (_pointInPolygon(CadPoint2D(testX, testY), contour)) {
              cellInside = true;
              break;
            }
          }
          if (cellInside) break;
        }
        occupiedGrid[row][col] = cellInside;
      }
    }

    // Corner occupancies:
    final bl = occupiedGrid[0][0];
    final br = occupiedGrid[0][2];
    final tl = occupiedGrid[2][0];
    final tr = occupiedGrid[2][2];

    int emptyCorners = 0;
    if (!bl) emptyCorners++;
    if (!br) emptyCorners++;
    if (!tl) emptyCorners++;
    if (!tr) emptyCorners++;

    if (emptyCorners == 4) {
      return ContourTopologyType.crossBranch;
    } else if (emptyCorners == 2) {
      if ((!tl && !tr) || (!bl && !br) || (!tl && !bl) || (!tr && !br)) {
        return ContourTopologyType.tBranch;
      }
    } else if (emptyCorners == 1) {
      return ContourTopologyType.lBend;
    }

    // Check reflex / concave corners in polygon
    int concaveCorners = _countConcaveCorners(contour);
    if (concaveCorners == 2) {
      return ContourTopologyType.tBranch;
    } else if (concaveCorners == 4) {
      return ContourTopologyType.crossBranch;
    } else if (concaveCorners == 1) {
      return ContourTopologyType.lBend;
    }

    if (fillRatio >= 0.82) {
      return ContourTopologyType.rectangular;
    }

    return ContourTopologyType.arbitraryPoly;
  }

  /// Ray-casting point-in-polygon test
  static bool _pointInPolygon(CadPoint2D point, List<CadPoint2D> polygon) {
    bool inside = false;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].x, yi = polygon[i].y;
      final xj = polygon[j].x, yj = polygon[j].y;

      final intersect = ((yi > point.y) != (yj > point.y)) &&
          (point.x < (xj - xi) * (point.y - yi) / (yj - yi + 1e-12) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Counts prominent internal reflex (concave) corners where cross product is negative
  static int _countConcaveCorners(List<CadPoint2D> contour) {
    if (contour.length < 4) return 0;
    final n = contour.length;

    double doubleArea = 0.0;
    for (int i = 0; i < n; i++) {
      final p1 = contour[i];
      final p2 = contour[(i + 1) % n];
      doubleArea += (p1.x * p2.y) - (p2.x * p1.y);
    }
    final isCcw = doubleArea > 0;

    int concaveCount = 0;
    for (int i = 0; i < n; i++) {
      final prev = contour[(i - 1 + n) % n];
      final curr = contour[i];
      final next = contour[(i + 1) % n];

      final v1x = curr.x - prev.x;
      final v1y = curr.y - prev.y;
      final v2x = next.x - curr.x;
      final v2y = next.y - curr.y;

      final cross = (v1x * v2y) - (v1y * v2x);
      final isReflex = isCcw ? cross < -1e-4 : cross > 1e-4;
      if (isReflex) {
        final len1 = math.sqrt(v1x * v1x + v1y * v1y);
        final len2 = math.sqrt(v2x * v2x + v2y * v2y);
        if (len1 > 10.0 && len2 > 10.0) {
          concaveCount++;
        }
      }
    }
    return concaveCount;
  }
}
