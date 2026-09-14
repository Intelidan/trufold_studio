// =============================================================================
// reference_geometry_engine.dart
//
// Reference Geometry & Stable Entity Resolution Engine per Phase 1 Master Guide
// Sections 12, 13, 14 & Set 01, Set 02.
//
// Computes and resolves:
// - Part reference edges: EDGE_LEFT, EDGE_RIGHT, EDGE_TOP, EDGE_BOTTOM
// - Centerlines: CENTER_X, CENTER_Y
// - Origin: ORIGIN (0, 0)
// - Sub-element points: Line.start, Line.end, Punch.center, Arc.center
// =============================================================================

import '../../models/cad_primitives.dart';
import '../../models/dsf_document.dart';
import '../../models/constraints/stable_geometry_reference.dart';
import '../../models/constraints/reference_geometry.dart';

class ResolvedPointRef {
  final CadPoint2D point;
  final String description;
  final bool isMovable;

  const ResolvedPointRef({
    required this.point,
    required this.description,
    this.isMovable = true,
  });
}

class ResolvedEdgeRef {
  final CadPoint2D p1;
  final CadPoint2D p2;
  final String description;
  final bool isInfinite;
  final bool isMovable;

  const ResolvedEdgeRef({
    required this.p1,
    required this.p2,
    required this.description,
    this.isInfinite = false,
    this.isMovable = true,
  });

  CadPoint2D get midpoint => CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
  double get length => p1.distanceTo(p2);
  bool get isVertical => (p1.x - p2.x).abs() < 1e-4;
  bool get isHorizontal => (p1.y - p2.y).abs() < 1e-4;
}

class ReferenceGeometryEngine {
  /// Computes bounding box and standard reference edges (EDGE_LEFT, EDGE_RIGHT, EDGE_TOP, EDGE_BOTTOM,
  /// CENTER_X, CENTER_Y) from the document's outer contour or combined geometry.
  static List<ReferenceGeometry> deriveStandardReferences(DsfDocument document) {
    final contour = document.outerContour;
    if (contour.isEmpty) return const [];

    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final pt in contour) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }

    final midX = (minX + maxX) / 2.0;
    final midY = (minY + maxY) / 2.0;

    return [
      ReferenceGeometry.edge(
        id: 'EDGE_LEFT',
        name: 'Left Edge',
        p1: CadPoint2D(minX, minY),
        p2: CadPoint2D(minX, maxY),
      ),
      ReferenceGeometry.edge(
        id: 'EDGE_RIGHT',
        name: 'Right Edge',
        p1: CadPoint2D(maxX, minY),
        p2: CadPoint2D(maxX, maxY),
      ),
      ReferenceGeometry.edge(
        id: 'EDGE_BOTTOM',
        name: 'Bottom Edge',
        p1: CadPoint2D(minX, minY),
        p2: CadPoint2D(maxX, minY),
      ),
      ReferenceGeometry.edge(
        id: 'EDGE_TOP',
        name: 'Top Edge',
        p1: CadPoint2D(minX, maxY),
        p2: CadPoint2D(maxX, maxY),
      ),
      ReferenceGeometry.centerlineX(
        x: midX,
        minY: minY - 20.0,
        maxY: maxY + 20.0,
      ),
      ReferenceGeometry.centerlineY(
        y: midY,
        minX: minX - 20.0,
        maxX: maxX + 20.0,
      ),
    ];
  }

  /// Resolves an [EntityRef] to a concrete point in CAD space
  static ResolvedPointRef? resolvePoint({
    required EntityRef ref,
    required DsfDocument document,
    List<ReferenceGeometry>? customReferences,
  }) {
    final id = ref.entityId.toUpperCase();

    if (id == 'ORIGIN') {
      return const ResolvedPointRef(
        point: CadPoint2D(0, 0),
        description: 'Origin (0,0)',
        isMovable: false,
      );
    }

    // 1. Check Punches
    for (final p in document.punches) {
      if (p.id == ref.entityId) {
        return ResolvedPointRef(
          point: p.center,
          description: 'Punch ${p.id} Center',
          isMovable: true,
        );
      }
    }

    // 2. Check Cut Lines
    for (final c in document.cutLines) {
      if (c.id == ref.entityId) {
        if (ref.subRef == GeometrySubRefType.start) {
          return ResolvedPointRef(point: c.p1, description: 'Line ${c.id} Start');
        } else if (ref.subRef == GeometrySubRefType.end) {
          return ResolvedPointRef(point: c.p2, description: 'Line ${c.id} End');
        }
      }
    }

    // 3. Check Bend Lines
    for (final b in document.bends) {
      if (b.id == ref.entityId) {
        if (ref.subRef == GeometrySubRefType.start) {
          return ResolvedPointRef(point: b.p1, description: 'Bend ${b.id} Start');
        } else if (ref.subRef == GeometrySubRefType.end) {
          return ResolvedPointRef(point: b.p2, description: 'Bend ${b.id} End');
        }
      }
    }

    // 4. Check Standard or Custom Reference Edges
    final allRefs = [
      ...deriveStandardReferences(document),
      ...?customReferences,
    ];

    for (final r in allRefs) {
      if (r.id.toUpperCase() == id) {
        if (ref.subRef == GeometrySubRefType.start) {
          return ResolvedPointRef(point: r.p1, description: '${r.name} Start');
        } else if (ref.subRef == GeometrySubRefType.end) {
          return ResolvedPointRef(point: r.p2, description: '${r.name} End');
        } else if (r.type == ReferenceGeometryType.constructionPoint) {
          return ResolvedPointRef(point: r.p1, description: '${r.name} Point');
        }
      }
    }

    return null;
  }

  /// Resolves an [EntityRef] to a line segment or linear edge in CAD space
  static ResolvedEdgeRef? resolveEdge({
    required EntityRef ref,
    required DsfDocument document,
    List<ReferenceGeometry>? customReferences,
  }) {
    final id = ref.entityId.toUpperCase();

    // 1. Standard or Custom Reference Geometries
    final allRefs = [
      ...deriveStandardReferences(document),
      ...?customReferences,
    ];

    for (final r in allRefs) {
      if (r.id.toUpperCase() == id) {
        return ResolvedEdgeRef(
          p1: r.p1,
          p2: r.p2,
          description: r.name,
          isInfinite: r.isInfinite,
          isMovable: !r.isLocked,
        );
      }
    }

    // 2. Cut Lines
    for (final c in document.cutLines) {
      if (c.id == ref.entityId) {
        return ResolvedEdgeRef(
          p1: c.p1,
          p2: c.p2,
          description: 'Cut Line ${c.id}',
        );
      }
    }

    // 3. Bend Lines
    for (final b in document.bends) {
      if (b.id == ref.entityId) {
        return ResolvedEdgeRef(
          p1: b.p1,
          p2: b.p2,
          description: 'Bend Line ${b.id}',
        );
      }
    }

    // 4. Outer Contour Segment by Index or Named Segment
    final contour = document.outerContour;
    if (contour.length >= 2) {
      if (ref.entityId.startsWith('CONTOUR_') || ref.entityId.startsWith('EDGE_')) {
        final idxStr = ref.entityId.replaceAll(RegExp(r'[^\d]'), '');
        final idx = int.tryParse(idxStr);
        if (idx != null && idx >= 0 && idx < contour.length) {
          final p1 = contour[idx];
          final p2 = contour[(idx + 1) % contour.length];
          return ResolvedEdgeRef(
            p1: p1,
            p2: p2,
            description: 'Contour Edge $idx',
          );
        }
      }
    }

    return null;
  }

  /// Measures the physical distance between two entity references [refA] and [refB].
  /// Supports point-to-point, point-to-edge, and edge-to-edge measurements.
  static double? measureDistance({
    required EntityRef refA,
    required EntityRef refB,
    required DsfDocument document,
    List<ReferenceGeometry>? customReferences,
  }) {
    // 1. Resolve points
    final ptA = resolvePoint(
      ref: refA,
      document: document,
      customReferences: customReferences,
    );
    final ptB = resolvePoint(
      ref: refB,
      document: document,
      customReferences: customReferences,
    );

    if (ptA != null && ptB != null) {
      return ptA.point.distanceTo(ptB.point);
    }

    // 2. Resolve edges
    final edgeA = resolveEdge(
      ref: refA,
      document: document,
      customReferences: customReferences,
    );
    final edgeB = resolveEdge(
      ref: refB,
      document: document,
      customReferences: customReferences,
    );

    // Point A to Edge B
    if (ptA != null && edgeB != null) {
      if (edgeA == null && edgeB.isVertical) {
        return (ptA.point.x - edgeB.p1.x).abs();
      } else if (edgeA == null && edgeB.isHorizontal) {
        return (ptA.point.y - edgeB.p1.y).abs();
      }
      return ptA.point.distanceTo(edgeB.midpoint);
    }

    // Edge A to Point B
    if (edgeA != null && ptB != null) {
      if (edgeB == null && edgeA.isVertical) {
        return (ptB.point.x - edgeA.p1.x).abs();
      } else if (edgeB == null && edgeA.isHorizontal) {
        return (ptB.point.y - edgeA.p1.y).abs();
      }
      return ptB.point.distanceTo(edgeA.midpoint);
    }

    // Edge A to Edge B
    if (edgeA != null && edgeB != null) {
      if (edgeA.isVertical && edgeB.isVertical) {
        return (edgeA.p1.x - edgeB.p1.x).abs();
      } else if (edgeA.isHorizontal && edgeB.isHorizontal) {
        return (edgeA.p1.y - edgeB.p1.y).abs();
      }
      return edgeA.midpoint.distanceTo(edgeB.midpoint);
    }

    return null;
  }
}
