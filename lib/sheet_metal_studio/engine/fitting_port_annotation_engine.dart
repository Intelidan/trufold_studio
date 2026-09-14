// =============================================================================
// fitting_port_annotation_engine.dart
//
// Geometric Port Opening Detection & Flat Pattern Annotation Engine.
// Analyzes flat developed sheet metal CAD contours to detect channel entry/exit
// openings, proportionately maps ports (e.g. W1xH1, W2xH2, W3xH3 for Unequal Tees,
// Entry/Exit for Reducers, and all ends for Equal Tees/Bends/Crosses),
// supports user manual side assignment, and generates visual CAD tag models.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/dsf_document.dart';
import '../models/dxf_fitting_metadata.dart';

enum PortSide {
  west,
  east,
  north,
  south,
  custom;

  String get displayName {
    switch (this) {
      case PortSide.west:
        return 'West (Left)';
      case PortSide.east:
        return 'East (Right)';
      case PortSide.north:
        return 'North (Top)';
      case PortSide.south:
        return 'South (Bottom)';
      case PortSide.custom:
        return 'Custom';
    }
  }

  static PortSide fromString(String? val) {
    if (val == null) return PortSide.custom;
    final lower = val.toLowerCase();
    if (lower.contains('west') || lower.contains('left')) return PortSide.west;
    if (lower.contains('east') || lower.contains('right')) return PortSide.east;
    if (lower.contains('north') || lower.contains('top')) return PortSide.north;
    if (lower.contains('south') || lower.contains('bottom')) return PortSide.south;
    return PortSide.custom;
  }
}

/// A detected opening / port on the flat pattern boundary
class ProductPortOpening {
  final String id; // e.g. 'port1', 'port2', 'port3', 'entry', 'exit'
  final String label; // e.g. 'PORT 1: MAIN IN', 'ENTRY', 'BRANCH'
  final double widthMm; // Nominal or entered width
  final double heightMm; // Nominal or entered height
  final CadPoint2D edgeP1; // Opening boundary edge start
  final CadPoint2D edgeP2; // Opening boundary edge end
  final CadPoint2D center; // Center point of opening edge
  final CadPoint2D normal; // Unit outward normal vector (pointing out from part)
  final double measuredLengthMm; // Actual physical length on CAD drawing
  final PortSide side; // Cardinal direction

  const ProductPortOpening({
    required this.id,
    required this.label,
    required this.widthMm,
    required this.heightMm,
    required this.edgeP1,
    required this.edgeP2,
    required this.center,
    required this.normal,
    required this.measuredLengthMm,
    required this.side,
  });

  String get dimensionText => '${widthMm.toStringAsFixed(0)} × ${heightMm.toStringAsFixed(0)} mm';
}

/// Candidate opening edge discovered on outer contour
class _CandidateOpeningEdge {
  final CadPoint2D p1;
  final CadPoint2D p2;
  final CadPoint2D center;
  final CadPoint2D normal;
  final double length;
  final PortSide side;
  final bool isTabEdge;

  const _CandidateOpeningEdge({
    required this.p1,
    required this.p2,
    required this.center,
    required this.normal,
    required this.length,
    required this.side,
    required this.isTabEdge,
  });
}

class FittingPortAnnotationEngine {
  /// Detects all channel port openings on the outer contour and maps dimensions
  static List<ProductPortOpening> detectPortOpenings({
    required DsfDocument document,
    DxfFittingMetadata? metadata,
  }) {
    final contour = document.outerContour;
    if (contour.length < 3) return const [];

    final meta = metadata ?? DxfFittingMetadata.fromDocument(document) ?? DxfFittingMetadata.detectFromDocument(document);
    final candidateEdges = _findCandidateOpeningEdges(contour);
    if (candidateEdges.isEmpty) return const [];

    final product = meta.product.toLowerCase();
    final params = meta.parameters;
    final userAssignments = meta.portAssignments ?? const {};

    if (meta.isUnequalTee || product.contains('unequal tee')) {
      return _mapUnequalTeeOpenings(candidateEdges, params, userAssignments);
    } else if (meta.isEqualTee || product.contains('equal tee') || product.contains('tee')) {
      return _mapEqualTeeOpenings(candidateEdges, params, userAssignments);
    } else if (product.contains('reducer')) {
      return _mapReducerOpenings(candidateEdges, params, userAssignments);
    } else if (product.contains('bend')) {
      return _mapBendOpenings(candidateEdges, params, userAssignments);
    } else if (product.contains('cross')) {
      return _mapCrossOpenings(candidateEdges, params, userAssignments);
    } else {
      return _mapGenericOpenings(candidateEdges, params, userAssignments);
    }
  }

  /// Identifies transverse boundary edges that form port openings
  static List<_CandidateOpeningEdge> _findCandidateOpeningEdges(List<CadPoint2D> contour) {
    final n = contour.length;
    final candidates = <_CandidateOpeningEdge>[];

    // Compute bounding box
    double minX = contour.first.x, maxX = contour.first.x;
    double minY = contour.first.y, maxY = contour.first.y;
    for (final p in contour) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final margin = 8.0;

    for (int i = 0; i < n; i++) {
      final p1 = contour[i];
      final p2 = contour[(i + 1) % n];
      final len = p1.distanceTo(p2);

      // Must be at least 20mm wide to be a channel opening
      if (len < 20.0) continue;

      // Tangent vector
      final tx = (p2.x - p1.x) / len;
      final ty = (p2.y - p1.y) / len;

      final midX = (p1.x + p2.x) / 2.0;
      final midY = (p1.y + p2.y) / 2.0;
      final center = CadPoint2D(midX, midY);

      // Determine true outward normal
      final n1x = -ty;
      final n1y = tx;
      final test1 = CadPoint2D(midX + n1x * 2.0, midY + n1y * 2.0);
      final normal = _isPointInPoly(test1, contour)
          ? CadPoint2D(-n1x, -n1y)
          : CadPoint2D(n1x, n1y);

      // Check if adjacent edges form a tab step (7–25mm)
      final pPrev = contour[(i - 1 + n) % n];
      final pNext = contour[(i + 2) % n];
      final lenPrev = pPrev.distanceTo(p1);
      final lenNext = p2.distanceTo(pNext);
      final isTab = (lenPrev >= 6.5 && lenPrev <= 26.0) && (lenNext >= 6.5 && lenNext <= 26.0);

      // Check if edge is near bounding box extremities
      final isNearWest = (midX - minX).abs() < margin && normal.x < -0.5;
      final isNearEast = (maxX - midX).abs() < margin && normal.x > 0.5;
      final isNearSouth = (midY - minY).abs() < margin && normal.y < -0.5;
      final isNearNorth = (maxY - midY).abs() < margin && normal.y > 0.5;
      final isExtremity = isNearWest || isNearEast || isNearSouth || isNearNorth;

      if (!isTab && !isExtremity) continue;

      // Determine cardinal side
      PortSide side = PortSide.custom;
      if (normal.x < -0.6) {
        side = PortSide.west;
      } else if (normal.x > 0.6) {
        side = PortSide.east;
      } else if (normal.y > 0.6) {
        side = PortSide.north;
      } else if (normal.y < -0.6) {
        side = PortSide.south;
      }

      candidates.add(_CandidateOpeningEdge(
        p1: p1,
        p2: p2,
        center: center,
        normal: normal,
        length: len,
        side: side,
        isTabEdge: isTab,
      ));
    }

    // Deduplicate candidate edges that are nearly identical
    final unique = <_CandidateOpeningEdge>[];
    for (final c in candidates) {
      final exists = unique.any((u) => u.center.distanceTo(c.center) < 5.0);
      if (!exists) {
        unique.add(c);
      }
    }

    return unique;
  }

  /// Maps Unequal Tee: 2 main run ports + 1 branch port
  static List<ProductPortOpening> _mapUnequalTeeOpenings(
    List<_CandidateOpeningEdge> edges,
    Map<String, double> params,
    Map<String, String> userAssignments,
  ) {
    final w1 = params['port1Width'] ?? 150.0;
    final h1 = params['port1Height'] ?? 50.0;
    final w2 = params['port2Width'] ?? 150.0;
    final h2 = params['port2Height'] ?? 50.0;
    final w3 = params['port3Width'] ?? 100.0;
    final h3 = params['port3Height'] ?? 50.0;

    if (edges.isEmpty) return const [];

    // Sort edges by measured length
    final sortedByLen = List<_CandidateOpeningEdge>.from(edges)
      ..sort((a, b) => b.length.compareTo(a.length));

    _CandidateOpeningEdge? branchEdge;
    _CandidateOpeningEdge? mainInEdge;
    _CandidateOpeningEdge? mainOutEdge;

    // Check user manual side overrides first
    if (userAssignments.isNotEmpty) {
      final sideP1 = PortSide.fromString(userAssignments['port1']);
      final sideP2 = PortSide.fromString(userAssignments['port2']);
      final sideP3 = PortSide.fromString(userAssignments['port3']);

      mainInEdge = edges.where((e) => e.side == sideP1).firstOrNull;
      mainOutEdge = edges.where((e) => e.side == sideP2 && e != mainInEdge).firstOrNull;
      branchEdge = edges.where((e) => e.side == sideP3 && e != mainInEdge && e != mainOutEdge).firstOrNull;
    }

    // Automatic proportionate mapping
    if (branchEdge == null || mainInEdge == null || mainOutEdge == null) {
      // Branch edge is typically closest to w3 length, or perpendicular to main run
      if (edges.length >= 3) {
        // Find the edge whose normal is perpendicular to the other two
        for (int i = 0; i < edges.length; i++) {
          final e = edges[i];
          final others = edges.where((o) => o != e).toList();
          final dot1 = (e.normal.x * others[0].normal.x + e.normal.y * others[0].normal.y).abs();
          final dot2 = (e.normal.x * others[1].normal.x + e.normal.y * others[1].normal.y).abs();
          if (dot1 < 0.3 && dot2 < 0.3) {
            branchEdge ??= e;
            mainInEdge ??= others[0].center.x < others[1].center.x ? others[0] : others[1];
            mainOutEdge ??= others[0].center.x >= others[1].center.x ? others[0] : others[1];
            break;
          }
        }
      }

      // Fallback: pick edge closest to w3 as branch
      branchEdge ??= sortedByLen.reduce((curr, next) =>
          (curr.length - w3).abs() < (next.length - w3).abs() ? curr : next);

      final remaining = sortedByLen.where((e) => e != branchEdge).toList();
      if (remaining.isNotEmpty) {
        mainInEdge ??= remaining.first;
      }
      if (remaining.length > 1) {
        mainOutEdge ??= remaining[1];
      }
    }

    final result = <ProductPortOpening>[];
    if (mainInEdge != null) {
      result.add(ProductPortOpening(
        id: 'port1',
        label: 'PORT 1: MAIN IN',
        widthMm: w1,
        heightMm: h1,
        edgeP1: mainInEdge.p1,
        edgeP2: mainInEdge.p2,
        center: mainInEdge.center,
        normal: mainInEdge.normal,
        measuredLengthMm: mainInEdge.length,
        side: mainInEdge.side,
      ));
    }
    if (mainOutEdge != null) {
      result.add(ProductPortOpening(
        id: 'port2',
        label: 'PORT 2: MAIN OUT',
        widthMm: w2,
        heightMm: h2,
        edgeP1: mainOutEdge.p1,
        edgeP2: mainOutEdge.p2,
        center: mainOutEdge.center,
        normal: mainOutEdge.normal,
        measuredLengthMm: mainOutEdge.length,
        side: mainOutEdge.side,
      ));
    }
    result.add(ProductPortOpening(
      id: 'port3',
      label: 'PORT 3: BRANCH',
      widthMm: w3,
      heightMm: h3,
      edgeP1: branchEdge.p1,
      edgeP2: branchEdge.p2,
      center: branchEdge.center,
      normal: branchEdge.normal,
      measuredLengthMm: branchEdge.length,
      side: branchEdge.side,
    ));
    return result;
  }

  /// Maps Reducer: Entry (larger width) and Exit (smaller width)
  static List<ProductPortOpening> _mapReducerOpenings(
    List<_CandidateOpeningEdge> edges,
    Map<String, double> params,
    Map<String, String> userAssignments,
  ) {
    final win = params['widthIn'] ?? (params['width'] ?? 100.0);
    final wout = params['widthOut'] ?? (params['branchWidth'] ?? 50.0);
    final h = params['height'] ?? 50.0;

    if (edges.isEmpty) return const [];

    final sorted = List<_CandidateOpeningEdge>.from(edges)
      ..sort((a, b) => b.length.compareTo(a.length));

    _CandidateOpeningEdge? entryEdge;
    _CandidateOpeningEdge? exitEdge;

    if (userAssignments.isNotEmpty) {
      final sideIn = PortSide.fromString(userAssignments['entry'] ?? userAssignments['port1']);
      final sideOut = PortSide.fromString(userAssignments['exit'] ?? userAssignments['port2']);
      entryEdge = edges.where((e) => e.side == sideIn).firstOrNull;
      exitEdge = edges.where((e) => e.side == sideOut && e != entryEdge).firstOrNull;
    }

    entryEdge ??= sorted.first;
    exitEdge ??= sorted.length > 1
        ? (sorted.firstWhere((e) => e != entryEdge, orElse: () => sorted.last))
        : sorted.first;

    final result = <ProductPortOpening>[
      ProductPortOpening(
        id: 'entry',
        label: 'ENTRY (IN)',
        widthMm: math.max(win, wout),
        heightMm: h,
        edgeP1: entryEdge.p1,
        edgeP2: entryEdge.p2,
        center: entryEdge.center,
        normal: entryEdge.normal,
        measuredLengthMm: entryEdge.length,
        side: entryEdge.side,
      ),
    ];

    if (sorted.length > 1) {
      result.add(ProductPortOpening(
        id: 'exit',
        label: 'EXIT (OUT)',
        widthMm: math.min(win, wout),
        heightMm: h,
        edgeP1: exitEdge.p1,
        edgeP2: exitEdge.p2,
        center: exitEdge.center,
        normal: exitEdge.normal,
        measuredLengthMm: exitEdge.length,
        side: exitEdge.side,
      ));
    }

    return result;
  }

  /// Maps Equal Tee: 3 ports with equal width
  static List<ProductPortOpening> _mapEqualTeeOpenings(
    List<_CandidateOpeningEdge> edges,
    Map<String, double> params,
    Map<String, String> userAssignments,
  ) {
    final w = params['width'] ?? 100.0;
    final h = params['height'] ?? 50.0;
    final result = <ProductPortOpening>[];

    final edgesToUse = <_CandidateOpeningEdge>[];
    if (userAssignments.isNotEmpty) {
      for (int i = 1; i <= 3; i++) {
        final assignedSide = PortSide.fromString(userAssignments['port$i']);
        final match = edges.where((e) => e.side == assignedSide && !edgesToUse.contains(e)).firstOrNull;
        if (match != null) edgesToUse.add(match);
      }
    }
    for (final e in edges) {
      if (edgesToUse.length >= 3) break;
      if (!edgesToUse.contains(e)) edgesToUse.add(e);
    }

    int idx = 1;
    for (final e in edgesToUse.take(3)) {
      final isBranch = idx == 3;
      result.add(ProductPortOpening(
        id: 'port$idx',
        label: isBranch ? 'PORT $idx: BRANCH' : 'PORT $idx: MAIN',
        widthMm: w,
        heightMm: h,
        edgeP1: e.p1,
        edgeP2: e.p2,
        center: e.center,
        normal: e.normal,
        measuredLengthMm: e.length,
        side: e.side,
      ));
      idx++;
    }
    return result;
  }

  /// Maps 90° / 45° Bend: Inlet & Outlet
  static List<ProductPortOpening> _mapBendOpenings(
    List<_CandidateOpeningEdge> edges,
    Map<String, double> params,
    Map<String, String> userAssignments,
  ) {
    final w = params['width'] ?? 100.0;
    final h = params['height'] ?? 50.0;
    final result = <ProductPortOpening>[];

    _CandidateOpeningEdge? inEdge;
    _CandidateOpeningEdge? outEdge;
    if (userAssignments.isNotEmpty) {
      final sideIn = PortSide.fromString(userAssignments['port1'] ?? userAssignments['inlet']);
      final sideOut = PortSide.fromString(userAssignments['port2'] ?? userAssignments['outlet']);
      inEdge = edges.where((e) => e.side == sideIn).firstOrNull;
      outEdge = edges.where((e) => e.side == sideOut && e != inEdge).firstOrNull;
    }
    inEdge ??= edges.firstOrNull;
    outEdge ??= edges.length > 1
        ? (edges.firstWhere((e) => e != inEdge, orElse: () => edges.last))
        : inEdge;

    if (inEdge != null) {
      result.add(ProductPortOpening(
        id: 'port1',
        label: 'INLET',
        widthMm: w,
        heightMm: h,
        edgeP1: inEdge.p1,
        edgeP2: inEdge.p2,
        center: inEdge.center,
        normal: inEdge.normal,
        measuredLengthMm: inEdge.length,
        side: inEdge.side,
      ));
    }
    if (outEdge != null && outEdge != inEdge) {
      result.add(ProductPortOpening(
        id: 'port2',
        label: 'OUTLET',
        widthMm: w,
        heightMm: h,
        edgeP1: outEdge.p1,
        edgeP2: outEdge.p2,
        center: outEdge.center,
        normal: outEdge.normal,
        measuredLengthMm: outEdge.length,
        side: outEdge.side,
      ));
    }
    return result;
  }

  /// Maps Cross: 4 ports
  static List<ProductPortOpening> _mapCrossOpenings(
    List<_CandidateOpeningEdge> edges,
    Map<String, double> params,
    Map<String, String> userAssignments,
  ) {
    final w = params['width'] ?? 100.0;
    final h = params['height'] ?? 50.0;
    final result = <ProductPortOpening>[];

    final edgesToUse = <_CandidateOpeningEdge>[];
    if (userAssignments.isNotEmpty) {
      for (int i = 1; i <= 4; i++) {
        final assignedSide = PortSide.fromString(userAssignments['port$i']);
        final match = edges.where((e) => e.side == assignedSide && !edgesToUse.contains(e)).firstOrNull;
        if (match != null) edgesToUse.add(match);
      }
    }
    for (final e in edges) {
      if (edgesToUse.length >= 4) break;
      if (!edgesToUse.contains(e)) edgesToUse.add(e);
    }

    int idx = 1;
    for (final e in edgesToUse.take(4)) {
      result.add(ProductPortOpening(
        id: 'port$idx',
        label: 'PORT $idx',
        widthMm: params['port${idx}Width'] ?? w,
        heightMm: params['port${idx}Height'] ?? h,
        edgeP1: e.p1,
        edgeP2: e.p2,
        center: e.center,
        normal: e.normal,
        measuredLengthMm: e.length,
        side: e.side,
      ));
      idx++;
    }
    return result;
  }

  /// Generic fallback
  static List<ProductPortOpening> _mapGenericOpenings(
    List<_CandidateOpeningEdge> edges,
    Map<String, double> params,
    Map<String, String> userAssignments,
  ) {
    final w = params['width'] ?? 100.0;
    final h = params['height'] ?? 50.0;
    final result = <ProductPortOpening>[];

    int idx = 1;
    for (final e in edges.take(2)) {
      result.add(ProductPortOpening(
        id: 'port$idx',
        label: 'PORT $idx',
        widthMm: w,
        heightMm: h,
        edgeP1: e.p1,
        edgeP2: e.p2,
        center: e.center,
        normal: e.normal,
        measuredLengthMm: e.length,
        side: e.side,
      ));
      idx++;
    }
    return result;
  }

  /// Standard winding number / ray-casting test to determine if a point is inside a polygon
  static bool _isPointInPoly(CadPoint2D pt, List<CadPoint2D> poly) {
    bool inside = false;
    final n = poly.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final pi = poly[i];
      final pj = poly[j];
      if (((pi.y > pt.y) != (pj.y > pt.y)) &&
          (pt.x < (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x)) {
        inside = !inside;
      }
    }
    return inside;
  }
}
