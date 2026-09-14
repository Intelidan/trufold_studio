// =============================================================================
// magnetic_snap_engine.dart
//
// High-Precision Magnetic Snapping Engine for Danish Sheet Metal Studio.
// Automatically snaps cursor to corner vertices, bend junctions, edge midpoints,
// punch centers, quadrants, intersections, perpendicular drops, tangents,
// nearest points, and grid coordinates for seamless CAD authoring.
// Supports Ortho / Polar tracking (0°, 45°, 90°, etc.) and Box/Crossing selection.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/painting.dart';

import '../models/cad_primitives.dart';
import '../models/dsf_document.dart';
import '../models/cnc_punch_primitive.dart';

enum SnapType {
  endpoint, // Outer blank corner vertex, bend endpoint, cut endpoint
  midpoint, // Edge, bend, or cut line midpoint
  center, // Round punch, circle, or obround punch center
  intersection, // Intersection between any lines or edges
  perpendicular, // Perpendicular drop onto an edge/segment from anchor
  tangent, // Tangent point to circle/round punch from anchor
  nearest, // Continuous point along an edge or cut line
  quadrant, // 0°, 90°, 180°, 270° quadrant points on circles/punches
  grid, // Discrete drafting grid coordinates

  // Backward-compatibility aliases
  cornerVertex,
  bendEndpoint,
  junctionDot,
  edgeMidpoint,
  punchCenter,
  edgePoint,
  edgeIntersection;

  bool get isEndpoint =>
      this == SnapType.endpoint ||
      this == SnapType.cornerVertex ||
      this == SnapType.bendEndpoint;

  bool get isMidpoint =>
      this == SnapType.midpoint || this == SnapType.edgeMidpoint;

  bool get isCenter => this == SnapType.center || this == SnapType.punchCenter;

  bool get isIntersection =>
      this == SnapType.intersection ||
      this == SnapType.junctionDot ||
      this == SnapType.edgeIntersection;

  bool get isNearest =>
      this == SnapType.nearest || this == SnapType.edgePoint;
}

class SnapEngineSettings {
  final double snapRadiusMm;
  final bool enableEndpoint;
  final bool enableMidpoint;
  final bool enableCenter;
  final bool enableIntersection;
  final bool enablePerpendicular;
  final bool enableTangent;
  final bool enableNearest;
  final bool enableQuadrant;
  final bool enableGrid;
  final double gridSpacingMm;
  final bool enableOrthoTracking;
  final List<double> trackingAngles;
  final double orthoAngleToleranceDeg;

  const SnapEngineSettings({
    this.snapRadiusMm = 8.0,
    this.enableEndpoint = true,
    this.enableMidpoint = true,
    this.enableCenter = true,
    this.enableIntersection = true,
    this.enablePerpendicular = true,
    this.enableTangent = true,
    this.enableNearest = false, // Disabled by default to prevent hijacking cursor
    this.enableQuadrant = true,
    this.enableGrid = false,
    this.gridSpacingMm = 10.0,
    this.enableOrthoTracking = true,
    this.trackingAngles = const [
      0.0,
      45.0,
      90.0,
      135.0,
      180.0,
      225.0,
      270.0,
      315.0,
    ],
    this.orthoAngleToleranceDeg = 3.0,
  });

  SnapEngineSettings copyWith({
    double? snapRadiusMm,
    bool? enableEndpoint,
    bool? enableMidpoint,
    bool? enableCenter,
    bool? enableIntersection,
    bool? enablePerpendicular,
    bool? enableTangent,
    bool? enableNearest,
    bool? enableQuadrant,
    bool? enableGrid,
    double? gridSpacingMm,
    bool? enableOrthoTracking,
    List<double>? trackingAngles,
    double? orthoAngleToleranceDeg,
  }) {
    return SnapEngineSettings(
      snapRadiusMm: snapRadiusMm ?? this.snapRadiusMm,
      enableEndpoint: enableEndpoint ?? this.enableEndpoint,
      enableMidpoint: enableMidpoint ?? this.enableMidpoint,
      enableCenter: enableCenter ?? this.enableCenter,
      enableIntersection: enableIntersection ?? this.enableIntersection,
      enablePerpendicular: enablePerpendicular ?? this.enablePerpendicular,
      enableTangent: enableTangent ?? this.enableTangent,
      enableNearest: enableNearest ?? this.enableNearest,
      enableQuadrant: enableQuadrant ?? this.enableQuadrant,
      enableGrid: enableGrid ?? this.enableGrid,
      gridSpacingMm: gridSpacingMm ?? this.gridSpacingMm,
      enableOrthoTracking: enableOrthoTracking ?? this.enableOrthoTracking,
      trackingAngles: trackingAngles ?? this.trackingAngles,
      orthoAngleToleranceDeg:
          orthoAngleToleranceDeg ?? this.orthoAngleToleranceDeg,
    );
  }
}

class SnapTarget {
  final CadPoint2D point;
  final SnapType type;
  final String label;
  final CadPoint2D? segmentStart;
  final CadPoint2D? segmentEnd;
  final CadPoint2D? trackingAnchor;
  final double? trackingAngleDeg;

  const SnapTarget({
    required this.point,
    required this.type,
    required this.label,
    this.segmentStart,
    this.segmentEnd,
    this.trackingAnchor,
    this.trackingAngleDeg,
  });

  double distanceTo(CadPoint2D pt) => point.distanceTo(pt);
}

class MagneticSnapEngine {
  /// Extracts discrete snap targets (endpoints, midpoints, centers, quadrants, intersections)
  /// according to active [settings].
  static List<SnapTarget> extractTargets(
    DsfDocument doc, {
    SnapEngineSettings settings = const SnapEngineSettings(),
    CadPoint2D? anchorPoint,
  }) {
    final targets = <SnapTarget>[];

    // Collect all linear segments for intersections and snaps
    final segments = <({CadPoint2D p1, CadPoint2D p2, String label})>[];

    // 1. Outer contour corner vertices and midpoints
    for (int i = 0; i < doc.outerContour.length; i++) {
      final pt = doc.outerContour[i];
      final next = doc.outerContour[(i + 1) % doc.outerContour.length];
      segments.add((p1: pt, p2: next, label: 'Contour'));

      if (settings.enableEndpoint) {
        targets.add(
          SnapTarget(
            point: pt,
            type: SnapType.cornerVertex,
            label:
                'Corner (${pt.x.toStringAsFixed(1)}, ${pt.y.toStringAsFixed(1)})',
          ),
        );
      }

      if (settings.enableMidpoint) {
        final mid = CadPoint2D((pt.x + next.x) / 2.0, (pt.y + next.y) / 2.0);
        targets.add(
          SnapTarget(
            point: mid,
            type: SnapType.edgeMidpoint,
            label:
                'Midpoint (${mid.x.toStringAsFixed(1)}, ${mid.y.toStringAsFixed(1)})',
            segmentStart: pt,
            segmentEnd: next,
          ),
        );
      }
    }

    // 2. Bend line endpoints, midpoints & segments
    for (final bend in doc.bends) {
      segments.add((p1: bend.p1, p2: bend.p2, label: bend.id));

      if (settings.enableEndpoint) {
        targets.add(
          SnapTarget(
            point: bend.p1,
            type: SnapType.bendEndpoint,
            label: '${bend.id} Endpoint',
          ),
        );
        targets.add(
          SnapTarget(
            point: bend.p2,
            type: SnapType.bendEndpoint,
            label: '${bend.id} Endpoint',
          ),
        );
      }

      if (settings.enableMidpoint) {
        targets.add(
          SnapTarget(
            point: bend.midpoint,
            type: SnapType.edgeMidpoint,
            label: '${bend.id} Midpoint',
            segmentStart: bend.p1,
            segmentEnd: bend.p2,
          ),
        );
      }
    }

    // 3. Punch centers & quadrants
    for (final punch in doc.punches) {
      if (settings.enableCenter) {
        targets.add(
          SnapTarget(
            point: punch.center,
            type: SnapType.punchCenter,
            label: '${punch.id} Center',
          ),
        );
      }

      if (settings.enableQuadrant) {
        final r = punch.widthMm / 2.0;
        if (punch.type == PunchType.roundHole) {
          targets.add(
            SnapTarget(
              point: CadPoint2D(punch.center.x + r, punch.center.y),
              type: SnapType.quadrant,
              label: '${punch.id} 0° Quadrant',
            ),
          );
          targets.add(
            SnapTarget(
              point: CadPoint2D(punch.center.x, punch.center.y + r),
              type: SnapType.quadrant,
              label: '${punch.id} 90° Quadrant',
            ),
          );
          targets.add(
            SnapTarget(
              point: CadPoint2D(punch.center.x - r, punch.center.y),
              type: SnapType.quadrant,
              label: '${punch.id} 180° Quadrant',
            ),
          );
          targets.add(
            SnapTarget(
              point: CadPoint2D(punch.center.x, punch.center.y - r),
              type: SnapType.quadrant,
              label: '${punch.id} 270° Quadrant',
            ),
          );
        }
      }
    }

    // 4. Cut line endpoints, midpoints & segments
    for (final cut in doc.cutLines) {
      segments.add((p1: cut.p1, p2: cut.p2, label: cut.id));

      if (settings.enableEndpoint) {
        targets.add(
          SnapTarget(
            point: cut.p1,
            type: SnapType.endpoint,
            label: '${cut.id} Cut Endpoint',
          ),
        );
        targets.add(
          SnapTarget(
            point: cut.p2,
            type: SnapType.endpoint,
            label: '${cut.id} Cut Endpoint',
          ),
        );
      }

      if (settings.enableMidpoint) {
        targets.add(
          SnapTarget(
            point: cut.midpoint,
            type: SnapType.midpoint,
            label: '${cut.id} Cut Midpoint',
            segmentStart: cut.p1,
            segmentEnd: cut.p2,
          ),
        );
      }
    }

    // 5. Intersections between segments
    if (settings.enableIntersection && segments.length >= 2) {
      for (int i = 0; i < segments.length; i++) {
        for (int j = i + 1; j < segments.length; j++) {
          final inter = intersectSegments(
            segments[i].p1,
            segments[i].p2,
            segments[j].p1,
            segments[j].p2,
          );
          if (inter != null) {
            targets.add(
              SnapTarget(
                point: inter,
                type: SnapType.intersection,
                label: 'Intersection (${segments[i].label} × ${segments[j].label})',
              ),
            );
          }
        }
      }
    }

    // 6. Perpendicular and Tangent snaps relative to active anchor
    if (anchorPoint != null) {
      if (settings.enablePerpendicular) {
        for (final seg in segments) {
          final foot = projectPerpendicularFoot(anchorPoint, seg.p1, seg.p2);
          if (foot != null) {
            targets.add(
              SnapTarget(
                point: foot,
                type: SnapType.perpendicular,
                label: 'Perpendicular to ${seg.label}',
                segmentStart: seg.p1,
                segmentEnd: seg.p2,
              ),
            );
          }
        }
      }

      if (settings.enableTangent) {
        for (final punch in doc.punches) {
          if (punch.type == PunchType.roundHole) {
            final tangents = computeCircleTangents(
              anchor: anchorPoint,
              center: punch.center,
              radius: punch.widthMm / 2.0,
            );
            for (final tanPt in tangents) {
              targets.add(
                SnapTarget(
                  point: tanPt,
                  type: SnapType.tangent,
                  label: 'Tangent to ${punch.id}',
                ),
              );
            }
          }
        }
      }
    }

    return targets;
  }

  /// Calculates intersection point of segment S1(a, b) and S2(c, d), or null if none.
  static CadPoint2D? intersectSegments(
    CadPoint2D a,
    CadPoint2D b,
    CadPoint2D c,
    CadPoint2D d,
  ) {
    final dx1 = b.x - a.x;
    final dy1 = b.y - a.y;
    final dx2 = d.x - c.x;
    final dy2 = d.y - c.y;

    final denom = dx1 * dy2 - dy1 * dx2;
    if (denom.abs() < 1e-6) return null; // Parallel or collinear

    final t = ((c.x - a.x) * dy2 - (c.y - a.y) * dx2) / denom;
    final u = ((c.x - a.x) * dy1 - (c.y - a.y) * dx1) / denom;

    if (t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0) {
      return CadPoint2D(a.x + t * dx1, a.y + t * dy1);
    }
    return null;
  }

  /// Projects a perpendicular from [anchor] onto segment [a]-[b].
  /// Returns the foot point if it lies strictly within the segment, otherwise null.
  static CadPoint2D? projectPerpendicularFoot(
    CadPoint2D anchor,
    CadPoint2D a,
    CadPoint2D b,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 < 1e-6) return null;

    final t = ((anchor.x - a.x) * dx + (anchor.y - a.y) * dy) / l2;
    if (t > 0.01 && t < 0.99) {
      return CadPoint2D(a.x + t * dx, a.y + t * dy);
    }
    return null;
  }

  /// Computes the two tangent points on a circle with [center] and [radius] from [anchor].
  static List<CadPoint2D> computeCircleTangents({
    required CadPoint2D anchor,
    required CadPoint2D center,
    required double radius,
  }) {
    final d = anchor.distanceTo(center);
    if (d <= radius + 1e-4) return const []; // Inside or on circle boundary

    final baseAngle = math.atan2(center.y - anchor.y, center.x - anchor.x);
    final alpha = math.asin(radius / d);
    final tangentLength = math.sqrt(d * d - radius * radius);

    final t1Angle = baseAngle + alpha;
    final t2Angle = baseAngle - alpha;

    return [
      CadPoint2D(
        anchor.x + tangentLength * math.cos(t1Angle),
        anchor.y + tangentLength * math.sin(t1Angle),
      ),
      CadPoint2D(
        anchor.x + tangentLength * math.cos(t2Angle),
        anchor.y + tangentLength * math.sin(t2Angle),
      ),
    ];
  }

  /// Projects point [p] onto segment [a]-[b] clamped to endpoints.
  static CadPoint2D projectPointToSegment(
    CadPoint2D p,
    CadPoint2D a,
    CadPoint2D b,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 < 1e-6) return a;
    final t = math.max(
      0.0,
      math.min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2),
    );
    return CadPoint2D(a.x + t * dx, a.y + t * dy);
  }

  /// Finds closest snap target prioritizing discrete points, ortho tracking,
  /// continuous edges, and grid coords.
  static SnapTarget? findClosestSnap({
    required CadPoint2D cursorMm,
    required List<SnapTarget> targets,
    DsfDocument? doc,
    SnapEngineSettings settings = const SnapEngineSettings(),
    CadPoint2D? anchorPoint,
    double? snapRadiusMm,
  }) {
    // Prioritize passed screen-scaled radius if provided, otherwise settings radius
    final effRadius = snapRadiusMm ?? settings.snapRadiusMm;

    SnapTarget? bestTarget;
    double bestDistance = effRadius;

    // 1. Priority: Discrete targets (Endpoint, Midpoint, Center, Intersection, Quadrant, Perpendicular, Tangent)
    for (final target in targets) {
      final d = target.distanceTo(cursorMm);
      if (d < bestDistance) {
        bestDistance = d;
        bestTarget = target;
      }
    }

    if (bestTarget != null) return bestTarget;

    // 2. Ortho / Polar Tracking Ray Snap (0°, 45°, 90°, etc.)
    if (anchorPoint != null && settings.enableOrthoTracking) {
      final orthoSnap = checkOrthoTracking(
        anchor: anchorPoint,
        cursor: cursorMm,
        trackingAngles: settings.trackingAngles,
        toleranceDeg: settings.orthoAngleToleranceDeg,
      );
      if (orthoSnap != null) {
        return orthoSnap;
      }
    }

    // 3. Nearest continuous edge snapping (tight threshold 0.4x effRadius)
    final nearestThreshold = effRadius * 0.4;
    if (settings.enableNearest && doc != null) {
      if (doc.outerContour.length >= 2) {
        for (int i = 0; i < doc.outerContour.length; i++) {
          final a = doc.outerContour[i];
          final b = doc.outerContour[(i + 1) % doc.outerContour.length];
          final proj = projectPointToSegment(cursorMm, a, b);
          final d = proj.distanceTo(cursorMm);
          if (d < nearestThreshold && d < bestDistance) {
            bestDistance = d;
            bestTarget = SnapTarget(
              point: proj,
              type: SnapType.nearest,
              label:
                  'Edge (${proj.x.toStringAsFixed(1)}, ${proj.y.toStringAsFixed(1)})',
              segmentStart: a,
              segmentEnd: b,
            );
          }
        }
      }

      // Continuous cut lines
      for (final cut in doc.cutLines) {
        final proj = projectPointToSegment(cursorMm, cut.p1, cut.p2);
        final d = proj.distanceTo(cursorMm);
        if (d < nearestThreshold && d < bestDistance) {
          bestDistance = d;
          bestTarget = SnapTarget(
            point: proj,
            type: SnapType.nearest,
            label:
                'Cut (${proj.x.toStringAsFixed(1)}, ${proj.y.toStringAsFixed(1)})',
            segmentStart: cut.p1,
            segmentEnd: cut.p2,
          );
        }
      }
    }

    if (bestTarget != null) return bestTarget;

    // 4. Grid Snap (if enabled)
    if (settings.enableGrid && settings.gridSpacingMm > 0) {
      final gx =
          (cursorMm.x / settings.gridSpacingMm).round() * settings.gridSpacingMm;
      final gy =
          (cursorMm.y / settings.gridSpacingMm).round() * settings.gridSpacingMm;
      final gridPt = CadPoint2D(gx, gy);
      if (gridPt.distanceTo(cursorMm) < effRadius) {
        return SnapTarget(
          point: gridPt,
          type: SnapType.grid,
          label: 'Grid (${gx.toStringAsFixed(1)}, ${gy.toStringAsFixed(1)})',
        );
      }
    }

    return null;
  }

  /// Checks if [cursor] is close to any polar tracking ray originating at [anchor].
  static SnapTarget? checkOrthoTracking({
    required CadPoint2D anchor,
    required CadPoint2D cursor,
    required List<double> trackingAngles,
    double toleranceDeg = 3.5,
  }) {
    final dx = cursor.x - anchor.x;
    final dy = cursor.y - anchor.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 2.0) return null;

    double cursorAngleDeg = (math.atan2(dy, dx) * 180.0 / math.pi) % 360.0;
    if (cursorAngleDeg < 0) cursorAngleDeg += 360.0;

    for (final targetAngle in trackingAngles) {
      double diff = (cursorAngleDeg - targetAngle).abs();
      if (diff > 180.0) diff = 360.0 - diff;

      if (diff <= toleranceDeg) {
        final rad = targetAngle * math.pi / 180.0;
        final snappedPt = CadPoint2D(
          anchor.x + length * math.cos(rad),
          anchor.y + length * math.sin(rad),
        );
        return SnapTarget(
          point: snappedPt,
          type: SnapType.nearest,
          label: 'Ortho: ${targetAngle.toStringAsFixed(0)}° (L: ${length.toStringAsFixed(1)} mm)',
          trackingAnchor: anchor,
          trackingAngleDeg: targetAngle,
        );
      }
    }
    return null;
  }

  // ===========================================================================
  // CAD Selection Box Algorithms (Window vs Crossing Selection)
  // ===========================================================================

  /// Returns true if point [pt] lies within [box].
  static bool isPointInRect(CadPoint2D pt, Rect box) {
    return pt.x >= box.left &&
        pt.x <= box.right &&
        pt.y >= box.top &&
        pt.y <= box.bottom;
  }

  /// Returns true if line segment [p1]-[p2] is strictly and entirely inside [box].
  static bool isSegmentInsideRect(CadPoint2D p1, CadPoint2D p2, Rect box) {
    return isPointInRect(p1, box) && isPointInRect(p2, box);
  }

  /// Returns true if line segment [p1]-[p2] touches or intersects [box].
  static bool isSegmentIntersectingRect(
    CadPoint2D p1,
    CadPoint2D p2,
    Rect box,
  ) {
    // If either endpoint is inside, it touches/intersects
    if (isPointInRect(p1, box) || isPointInRect(p2, box)) return true;

    // Check intersection with all 4 bounding edges of the box
    final topLeft = CadPoint2D(box.left, box.top);
    final topRight = CadPoint2D(box.right, box.top);
    final bottomLeft = CadPoint2D(box.left, box.bottom);
    final bottomRight = CadPoint2D(box.right, box.bottom);

    if (intersectSegments(p1, p2, topLeft, topRight) != null) return true;
    if (intersectSegments(p1, p2, topRight, bottomRight) != null) return true;
    if (intersectSegments(p1, p2, bottomRight, bottomLeft) != null) return true;
    if (intersectSegments(p1, p2, bottomLeft, topLeft) != null) return true;

    return false;
  }

  /// Evaluates Window Selection (Left-to-Right drag):
  /// Selects elements that are STRICTLY and COMPLETELY contained within [cadBox].
  static Set<String> evaluateWindowSelection({
    required DsfDocument doc,
    required Rect cadBox,
  }) {
    final selectedIds = <String>{};

    for (final bend in doc.bends) {
      if (bend.isVisible && isSegmentInsideRect(bend.p1, bend.p2, cadBox)) {
        selectedIds.add(bend.id);
      }
    }

    for (final cut in doc.cutLines) {
      if (isSegmentInsideRect(cut.p1, cut.p2, cadBox)) {
        selectedIds.add(cut.id);
      }
    }

    for (final punch in doc.punches) {
      if (!punch.isVisible) continue;
      final punchBox = Rect.fromCenter(
        center: Offset(punch.center.x, punch.center.y),
        width: punch.widthMm,
        height: punch.lengthMm > 0 ? punch.lengthMm : punch.widthMm,
      );
      if (cadBox.contains(punchBox.topLeft) &&
          cadBox.contains(punchBox.bottomRight)) {
        selectedIds.add(punch.id);
      }
    }

    for (final pattern in doc.perforationPatterns) {
      if (!pattern.isVisible) continue;
      final b = pattern.calculateBounds();
      final patBox = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
      if (cadBox.contains(patBox.topLeft) &&
          cadBox.contains(patBox.bottomRight)) {
        selectedIds.add(pattern.id);
      }
    }

    return selectedIds;
  }

  /// Evaluates Crossing Selection (Right-to-Left drag):
  /// Selects elements that TOUCH or INTERSECT [cadBox].
  static Set<String> evaluateCrossingSelection({
    required DsfDocument doc,
    required Rect cadBox,
  }) {
    final selectedIds = <String>{};

    for (final bend in doc.bends) {
      if (bend.isVisible &&
          isSegmentIntersectingRect(bend.p1, bend.p2, cadBox)) {
        selectedIds.add(bend.id);
      }
    }

    for (final cut in doc.cutLines) {
      if (isSegmentIntersectingRect(cut.p1, cut.p2, cadBox)) {
        selectedIds.add(cut.id);
      }
    }

    for (final punch in doc.punches) {
      if (!punch.isVisible) continue;
      final punchBox = Rect.fromCenter(
        center: Offset(punch.center.x, punch.center.y),
        width: punch.widthMm,
        height: punch.lengthMm > 0 ? punch.lengthMm : punch.widthMm,
      );
      if (cadBox.overlaps(punchBox)) {
        selectedIds.add(punch.id);
      }
    }

    for (final pattern in doc.perforationPatterns) {
      if (!pattern.isVisible) continue;
      final b = pattern.calculateBounds();
      final patBox = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
      if (cadBox.overlaps(patBox)) {
        selectedIds.add(pattern.id);
      }
    }

    return selectedIds;
  }
}
