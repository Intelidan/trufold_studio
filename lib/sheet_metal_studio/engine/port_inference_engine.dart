// =============================================================================
// port_inference_engine.dart
//
// 1-Click Semantic Port Inference Engine for Sheet Metal Studio
// per Port Assignment & Intelligent Scaling UX Guide and Master Implementation Spec.
//
// Core Principle:
// The user clicks ONE opening edge as an input hint.
// The engine automatically derives the complete semantic port topology:
// 1. Opening edge span & Width (W)
// 2. Outward connection direction / port normal vector (generic sheet metal connection vector)
// 3. Sidewall heights H_A and H_B computed geometrically from bend/reference lines
//    to the outermost wall boundary (accounting for fillets, chamfers, and aesthetic relief cuts)
// 4. Rigid coupler punch clusters and fastener features in the port zone
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/fold_bend_line.dart';
import '../models/dsf_document.dart';
import 'fitting_port_annotation_engine.dart';
import '../models/dxf_fitting_metadata.dart';

/// Complete semantic inference result for a single port opening
class PortInferenceResult {
  final String portId;
  final CadLineSegment openingEdge;
  final double inferredWidth;
  final double inferredHeightA;
  final double inferredHeightB;
  final CadPoint2D normal;
  final double outwardNormalAngleRad;
  final PortSide inferredSide;
  final List<CadLineSegment> sidewallAEdges;
  final List<CadLineSegment> sidewallBEdges;
  final FoldBendLine? associatedBendLineA;
  final FoldBendLine? associatedBendLineB;
  final List<String> associatedFeatureIds;
  final double confidence;
  final String inferenceNotes;

  const PortInferenceResult({
    required this.portId,
    required this.openingEdge,
    required this.inferredWidth,
    required this.inferredHeightA,
    required this.inferredHeightB,
    required this.normal,
    required this.outwardNormalAngleRad,
    required this.inferredSide,
    this.sidewallAEdges = const [],
    this.sidewallBEdges = const [],
    this.associatedBendLineA,
    this.associatedBendLineB,
    this.associatedFeatureIds = const [],
    this.confidence = 1.0,
    this.inferenceNotes = '',
  });

  bool get isSymmetric => (inferredHeightA - inferredHeightB).abs() < 1e-3;

  String get summaryText => isSymmetric
      ? 'W=${inferredWidth.toStringAsFixed(1)} mm, H=${inferredHeightA.toStringAsFixed(1)} mm (${inferredSide.displayName})'
      : 'W=${inferredWidth.toStringAsFixed(1)} mm, H-A=${inferredHeightA.toStringAsFixed(1)} mm, H-B=${inferredHeightB.toStringAsFixed(1)} mm (${inferredSide.displayName})';
}

class PortInferenceEngine {
  /// Infers complete semantic port definition from a clicked point or candidate edge.
  static PortInferenceResult? inferFromOpeningEdge({
    required DsfDocument document,
    required CadPoint2D clickedPoint,
    String portId = 'port1',
    CadLineSegment? candidateEdge,
    double pickToleranceMm = 20.0,
  }) {
    final contour = document.outerContour;
    if (contour.length < 3) return null;

    // 1. Identify clicked boundary edge on outer contour
    final opening = candidateEdge ?? _findClosestContourEdge(contour, clickedPoint, pickToleranceMm);
    if (opening == null) return null;

    final p1 = opening.p1;
    final p2 = opening.p2;
    final widthMm = p1.distanceTo(p2);
    if (widthMm < 1e-3) return null;

    // 2. Determine Outward Connection Direction / Port Normal
    final normalResult = _calculateOutwardNormal(contour, p1, p2);
    final normal = normalResult.normal;
    final normalAngle = normalResult.angleRad;
    final side = _classifyPortSide(normalAngle);

    // 3. Find connected sidewall geometry and determine H_A & H_B
    final sidewallResult = _inferSidewallHeights(
      document: document,
      openingEdge: opening,
      normal: normal,
    );

    // 4. Discover associated coupler punch holes and fastener features
    final featureIds = _discoverAssociatedFeatures(
      document: document,
      openingEdge: opening,
      heightA: sidewallResult.heightA,
      heightB: sidewallResult.heightB,
      normal: normal,
    );

    return PortInferenceResult(
      portId: portId,
      openingEdge: opening,
      inferredWidth: widthMm,
      inferredHeightA: sidewallResult.heightA,
      inferredHeightB: sidewallResult.heightB,
      normal: normal,
      outwardNormalAngleRad: normalAngle,
      inferredSide: side,
      sidewallAEdges: sidewallResult.edgesA,
      sidewallBEdges: sidewallResult.edgesB,
      associatedBendLineA: sidewallResult.bendA,
      associatedBendLineB: sidewallResult.bendB,
      associatedFeatureIds: featureIds,
      confidence: sidewallResult.confidence,
      inferenceNotes: sidewallResult.notes,
    );
  }

  /// Finds closest segment on the outer contour polygon within [toleranceMm].
  static CadLineSegment? _findClosestContourEdge(
    List<CadPoint2D> contour,
    CadPoint2D pt,
    double toleranceMm,
  ) {
    final n = contour.length;
    double minDistance = double.infinity;
    CadLineSegment? closestEdge;

    for (int i = 0; i < n; i++) {
      final p1 = contour[i];
      final p2 = contour[(i + 1) % n];
      final dist = _pointToSegmentDistance(pt, p1, p2);
      if (dist < minDistance && dist <= toleranceMm) {
        minDistance = dist;
        closestEdge = CadLineSegment(
          id: 'CONTOUR_EDGE_$i',
          p1: p1,
          p2: p2,
        );
      }
    }
    return closestEdge;
  }

  /// Calculates outward connection normal vector pointing away from fitting interior.
  static ({CadPoint2D normal, double angleRad}) _calculateOutwardNormal(
    List<CadPoint2D> contour,
    CadPoint2D p1,
    CadPoint2D p2,
  ) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) {
      return (normal: const CadPoint2D(0, 1), angleRad: math.pi / 2.0);
    }

    final mid = CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);

    // Two possible perpendicular unit normals
    final n1 = CadPoint2D(-dy / len, dx / len);
    final n2 = CadPoint2D(dy / len, -dx / len);

    // Sample test points at offset 5mm along both candidates
    final t1 = CadPoint2D(mid.x + n1.x * 5.0, mid.y + n1.y * 5.0);
    final t2 = CadPoint2D(mid.x + n2.x * 5.0, mid.y + n2.y * 5.0);

    final inPoly1 = _isPointInPolygon(t1, contour);
    final inPoly2 = _isPointInPolygon(t2, contour);

    CadPoint2D outwardNormal;
    if (!inPoly1 && inPoly2) {
      outwardNormal = n1;
    } else if (inPoly1 && !inPoly2) {
      outwardNormal = n2;
    } else {
      // Fallback: test distance to polygon centroid
      final centroid = _computeContourCentroid(contour);
      final dist1 = (t1.x - centroid.x) * (t1.x - centroid.x) + (t1.y - centroid.y) * (t1.y - centroid.y);
      final dist2 = (t2.x - centroid.x) * (t2.x - centroid.x) + (t2.y - centroid.y) * (t2.y - centroid.y);
      outwardNormal = dist1 > dist2 ? n1 : n2;
    }

    final angle = math.atan2(outwardNormal.y, outwardNormal.x);
    return (normal: outwardNormal, angleRad: angle);
  }

  /// Classifies vector angle into cardinal PortSide
  static PortSide _classifyPortSide(double angleRad) {
    final normAngle = ((angleRad % (2 * math.pi)) + 2 * math.pi) % (2 * math.pi);
    // 0 = East, pi/2 = North, pi = West, 3pi/2 = South
    const pi = math.pi;
    const tol = pi / 4.0; // 45 deg cone

    if (normAngle < tol || normAngle >= (2 * pi - tol)) {
      return PortSide.east;
    } else if ((normAngle - pi / 2.0).abs() < tol) {
      return PortSide.north;
    } else if ((normAngle - pi).abs() < tol) {
      return PortSide.west;
    } else if ((normAngle - 3 * pi / 2.0).abs() < tol) {
      return PortSide.south;
    }
    return PortSide.custom;
  }

  /// Infers sidewall heights H_A and H_B with highest priority on bend/wall references,
  /// geometric distance to outermost boundary, and handling chamfers/fillets.
  static ({
    double heightA,
    double heightB,
    List<CadLineSegment> edgesA,
    List<CadLineSegment> edgesB,
    FoldBendLine? bendA,
    FoldBendLine? bendB,
    double confidence,
    String notes,
  }) _inferSidewallHeights({
    required DsfDocument document,
    required CadLineSegment openingEdge,
    required CadPoint2D normal,
  }) {
    final p1 = openingEdge.p1;
    final p2 = openingEdge.p2;
    final contour = document.outerContour;
    final bends = document.bends;

    // Unit tangent vector along the opening edge (from p1 to p2)
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final edgeLen = math.sqrt(dx * dx + dy * dy);
    final tangent = edgeLen > 1e-6
        ? CadPoint2D(dx / edgeLen, dy / edgeLen)
        : const CadPoint2D(1, 0);

    // Inward direction pointing into the sheet metal blank
    final inwardDir = CadPoint2D(-normal.x, -normal.y);

    // -------------------------------------------------------------------------
    // Priority 1: Search for longitudinal bend lines that define the sidewall root
    // -------------------------------------------------------------------------
    FoldBendLine? bestBendA;
    FoldBendLine? bestBendB;
    double? bendDistA;
    double? bendDistB;

    for (final bend in bends) {
      // Check if bend line runs roughly parallel to the inward direction (angle diff < 25 deg)
      final bdx = bend.p2.x - bend.p1.x;
      final bdy = bend.p2.y - bend.p1.y;
      final blen = math.sqrt(bdx * bdx + bdy * bdy);
      if (blen < 5.0) continue;

      final bendDir = CadPoint2D(bdx / blen, bdy / blen);
      final dot = (bendDir.x * inwardDir.x + bendDir.y * inwardDir.y).abs();
      if (dot > 0.85) {
        // Bend runs parallel to opening depth! Check proximity to p1 or p2
        final distP1 = _pointToLineDistance(p1, bend.p1, bend.p2);
        final distP2 = _pointToLineDistance(p2, bend.p1, bend.p2);

        // Does it pass near p1 (within 20mm)?
        if (distP1 < 25.0) {
          if (bendDistA == null || distP1 < bendDistA) {
            bendDistA = distP1;
            bestBendA = bend;
          }
        }
        // Does it pass near p2 (within 20mm)?
        if (distP2 < 25.0) {
          if (bendDistB == null || distP2 < bendDistB) {
            bendDistB = distP2;
            bestBendB = bend;
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // Priority 2 & 3: Contour Wing Geometry & Geometric Ceiling Height
    // Measure distance from bend line (or corner root) to outermost wall boundary
    // -------------------------------------------------------------------------
    final wingA = _traceFlangeWing(
      contour: contour,
      startCorner: p1,
      tangentOutward: CadPoint2D(-tangent.x, -tangent.y), // outward along side A
      inwardDir: inwardDir,
    );

    final wingB = _traceFlangeWing(
      contour: contour,
      startCorner: p2,
      tangentOutward: tangent, // outward along side B
      inwardDir: inwardDir,
    );

    double inferredHA = 50.0;
    double inferredHB = 50.0;
    double confidence = 0.9;
    final notes = <String>[];

    if (bestBendA != null && wingA.outermostVertex != null) {
      // Geometric distance from bend line to outermost wall ceiling vertex
      inferredHA = _pointToLineDistance(wingA.outermostVertex!, bestBendA.p1, bestBendA.p2);
      notes.add('Side A height derived from bend line to outer wall ceiling: ${inferredHA.toStringAsFixed(1)} mm');
    } else if (wingA.maxPerpDistance > 5.0) {
      inferredHA = wingA.maxPerpDistance;
      notes.add('Side A height derived from boundary wing depth: ${inferredHA.toStringAsFixed(1)} mm');
    }

    if (bestBendB != null && wingB.outermostVertex != null) {
      inferredHB = _pointToLineDistance(wingB.outermostVertex!, bestBendB.p1, bestBendB.p2);
      notes.add('Side B height derived from bend line to outer wall ceiling: ${inferredHB.toStringAsFixed(1)} mm');
    } else if (wingB.maxPerpDistance > 5.0) {
      inferredHB = wingB.maxPerpDistance;
      notes.add('Side B height derived from boundary wing depth: ${inferredHB.toStringAsFixed(1)} mm');
    }

    // If one side detected a strong bend-derived height and the other wing is symmetric within 2mm, align them
    if ((inferredHA - inferredHB).abs() <= 2.0) {
      final avg = (inferredHA + inferredHB) / 2.0;
      inferredHA = avg;
      inferredHB = avg;
      notes.add('Symmetric sidewalls detected (H_A == H_B)');
    }

    return (
      heightA: inferredHA,
      heightB: inferredHB,
      edgesA: wingA.edges,
      edgesB: wingB.edges,
      bendA: bestBendA,
      bendB: bestBendB,
      confidence: confidence,
      notes: notes.join('; '),
    );
  }

  /// Traces outer contour edges from opening corner outward along the sidewall wing,
  /// capturing the outermost boundary vertex and maximum perpendicular flange extension.
  static ({
    List<CadLineSegment> edges,
    CadPoint2D? outermostVertex,
    double maxPerpDistance,
  }) _traceFlangeWing({
    required List<CadPoint2D> contour,
    required CadPoint2D startCorner,
    required CadPoint2D tangentOutward,
    required CadPoint2D inwardDir,
  }) {
    final n = contour.length;
    final idx = _findVertexIndex(contour, startCorner);
    if (idx == -1) {
      return (edges: const [], outermostVertex: null, maxPerpDistance: 0.0);
    }

    // Try both search directions (forward and backward) to find the branch turning along tangentOutward
    final edges = <CadLineSegment>[];
    CadPoint2D? maxPt;
    double maxDist = 0.0;

    // We search up to 6 connected edges (to encompass chamfer, fillet, tab, relief cut)
    for (final dir in [1, -1]) {
      double currentMax = 0.0;
      CadPoint2D? currentMaxPt;
      final currentEdges = <CadLineSegment>[];

      for (int step = 1; step <= 6; step++) {
        final i1 = (idx + (step - 1) * dir + n) % n;
        final i2 = (idx + step * dir + n) % n;
        final pt1 = contour[i1];
        final pt2 = contour[i2];

        // Vector of this segment
        final segDx = pt2.x - pt1.x;
        final segDy = pt2.y - pt1.y;
        final segLen = math.sqrt(segDx * segDx + segDy * segDy);
        if (segLen < 1e-4) continue;

        // Project displacement from startCorner onto tangentOutward
        final dispX = pt2.x - startCorner.x;
        final dispY = pt2.y - startCorner.y;
        final perpProj = dispX * tangentOutward.x + dispY * tangentOutward.y;

        if (perpProj > currentMax) {
          currentMax = perpProj;
          currentMaxPt = pt2;
        }

        currentEdges.add(CadLineSegment(
          id: 'WING_${dir}_$step',
          p1: pt1,
          p2: pt2,
        ));

        // Stop if we hit a relief cut that returns back inward or exceeds 300mm
        if (perpProj > 350.0 || (step > 2 && perpProj < currentMax - 10.0)) {
          break;
        }
      }

      if (currentMax > maxDist) {
        maxDist = currentMax;
        maxPt = currentMaxPt;
        edges.clear();
        edges.addAll(currentEdges);
      }
    }

    return (
      edges: edges,
      outermostVertex: maxPt,
      maxPerpDistance: maxDist,
    );
  }

  /// Discovers coupler mounting punch holes and slot features near the port opening.
  static List<String> _discoverAssociatedFeatures({
    required DsfDocument document,
    required CadLineSegment openingEdge,
    required double heightA,
    required double heightB,
    required CadPoint2D normal,
  }) {
    final p1 = openingEdge.p1;
    final p2 = openingEdge.p2;
    final mid = CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
    final maxH = math.max(heightA, heightB);
    final searchDepth = maxH + 50.0;
    final searchSpan = p1.distanceTo(p2) + 40.0;

    final featureIds = <String>[];

    for (final punch in document.punches) {
      // Vector from opening midpoint to punch center
      final vx = punch.center.x - mid.x;
      final vy = punch.center.y - mid.y;

      // Project onto inward direction (-normal)
      final depthProj = vx * (-normal.x) + vy * (-normal.y);

      // Project onto tangent direction (along opening)
      final normX = -normal.y;
      final normY = normal.x;
      final spanProj = (vx * normX + vy * normY).abs();

      // If within port depth and span, it's a coupler feature!
      if (depthProj >= -15.0 && depthProj <= searchDepth && spanProj <= searchSpan / 2.0) {
        featureIds.add(punch.id);
      }
    }

    return featureIds;
  }

  // ---------------------------------------------------------------------------
  // Geometry Utility Helpers
  // ---------------------------------------------------------------------------

  static int _findVertexIndex(List<CadPoint2D> contour, CadPoint2D pt, {double tol = 1.0}) {
    for (int i = 0; i < contour.length; i++) {
      if (contour[i].distanceTo(pt) <= tol) return i;
    }
    return -1;
  }

  static double _pointToSegmentDistance(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-6) return p.distanceTo(a);

    final t = math.max(0.0, math.min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq));
    final proj = CadPoint2D(a.x + t * dx, a.y + t * dy);
    return p.distanceTo(proj);
  }

  static double _pointToLineDistance(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return p.distanceTo(a);
    return ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len;
  }

  static bool _isPointInPolygon(CadPoint2D pt, List<CadPoint2D> poly) {
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

  static CadPoint2D _computeContourCentroid(List<CadPoint2D> contour) {
    if (contour.isEmpty) return const CadPoint2D(0, 0);
    double sx = 0, sy = 0;
    for (final p in contour) {
      sx += p.x;
      sy += p.y;
    }
    return CadPoint2D(sx / contour.length, sy / contour.length);
  }

  // ===========================================================================
  // Set 9: Automated Batch Port Discovery Engine (1-Click)
  // ===========================================================================

  /// Discovers and infers all ports on [document] automatically in a single pass.
  /// Categorizes, canonically sorts (West -> East -> North -> South -> Custom), and generates
  /// complete semantic port definitions including dual sidewall heights and associated punch clusters.
  static List<PortInferenceResult> autoDetectAllPorts(DsfDocument document) {
    final contour = document.outerContour;
    if (contour.length < 3) return const [];

    // 1. First attempt: leverage FittingPortAnnotationEngine which has template/fitting classification
    final annotationOpenings = FittingPortAnnotationEngine.detectPortOpenings(document: document);
    if (annotationOpenings.isNotEmpty) {
      final results = <PortInferenceResult>[];
      for (final op in annotationOpenings) {
        final edge = CadLineSegment(id: op.id, p1: op.edgeP1, p2: op.edgeP2);
        final res = inferFromOpeningEdge(
          document: document,
          clickedPoint: op.center,
          portId: op.id,
          candidateEdge: edge,
        );
        if (res != null) {
          results.add(res);
        }
      }
      if (results.isNotEmpty) return results;
    }

    final n = contour.length;

    // Compute bounding box
    double minX = contour.first.x, maxX = contour.first.x;
    double minY = contour.first.y, maxY = contour.first.y;
    for (final p in contour) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    const margin = 12.0;
    final candidateEdges = <({CadLineSegment edge, PortSide side, CadPoint2D center})>[];

    for (int i = 0; i < n; i++) {
      final p1 = contour[i];
      final p2 = contour[(i + 1) % n];
      final len = p1.distanceTo(p2);

      // Must be at least 20mm wide to be a channel opening
      if (len < 20.0) continue;

      final midX = (p1.x + p2.x) / 2.0;
      final midY = (p1.y + p2.y) / 2.0;
      final center = CadPoint2D(midX, midY);

      final normalRes = _calculateOutwardNormal(contour, p1, p2);
      final normal = normalRes.normal;
      final side = _classifyPortSide(normalRes.angleRad);

      // Check if adjacent edges form a tab step (coupler tab relief)
      final pPrev = contour[(i - 1 + n) % n];
      final pNext = contour[(i + 2) % n];
      final lenPrev = pPrev.distanceTo(p1);
      final lenNext = p2.distanceTo(pNext);
      final isTab = (lenPrev >= 6.0 && lenPrev <= 35.0) && (lenNext >= 6.0 && lenNext <= 35.0);

      // Check if edge is near bounding box extremities
      final isNearWest = (midX - minX).abs() < margin && normal.x < -0.5;
      final isNearEast = (maxX - midX).abs() < margin && normal.x > 0.5;
      final isNearSouth = (midY - minY).abs() < margin && normal.y < -0.5;
      final isNearNorth = (maxY - midY).abs() < margin && normal.y > 0.5;
      final isExtremity = isNearWest || isNearEast || isNearSouth || isNearNorth;

      if (isTab || isExtremity) {
        candidateEdges.add((
          edge: CadLineSegment(id: 'OPENING_$i', p1: p1, p2: p2),
          side: side,
          center: center,
        ));
      }
    }

    if (candidateEdges.isEmpty) {
      // Fallback: take longest transverse boundary edges with outward normal
      for (int i = 0; i < n; i++) {
        final p1 = contour[i];
        final p2 = contour[(i + 1) % n];
        final len = p1.distanceTo(p2);
        if (len >= 45.0) {
          final normalRes = _calculateOutwardNormal(contour, p1, p2);
          candidateEdges.add((
            edge: CadLineSegment(id: 'OPENING_$i', p1: p1, p2: p2),
            side: _classifyPortSide(normalRes.angleRad),
            center: CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0),
          ));
        }
      }
    }

    // Canonical sorting: West -> East -> North -> South -> Custom
    int sideOrder(PortSide s) {
      switch (s) {
        case PortSide.west:
          return 1;
        case PortSide.east:
          return 2;
        case PortSide.north:
          return 3;
        case PortSide.south:
          return 4;
        case PortSide.custom:
          return 5;
      }
    }

    candidateEdges.sort((a, b) {
      final orderA = sideOrder(a.side);
      final orderB = sideOrder(b.side);
      if (orderA != orderB) return orderA.compareTo(orderB);
      if (a.side == PortSide.west || a.side == PortSide.east) {
        return a.center.y.compareTo(b.center.y);
      }
      return a.center.x.compareTo(b.center.x);
    });

    final results = <PortInferenceResult>[];
    for (int i = 0; i < candidateEdges.length; i++) {
      final item = candidateEdges[i];
      final portId = 'port${i + 1}';
      final res = inferFromOpeningEdge(
        document: document,
        clickedPoint: item.center,
        portId: portId,
        candidateEdge: item.edge,
      );
      if (res != null) {
        results.add(res);
      }
    }

    return results;
  }

  /// Updates or synthesizes [DxfFittingMetadata] with all auto-detected semantic ports.
  static DxfFittingMetadata updateMetadataWithAutoDetectedPorts(
    DsfDocument document, [
    DxfFittingMetadata? baseMetadata,
  ]) {
    final detectedPorts = autoDetectAllPorts(document);
    final meta = baseMetadata ??
        DxfFittingMetadata.fromDocument(document) ??
        DxfFittingMetadata.detectFromDocument(document);

    final semanticPorts = Map<String, Map<String, dynamic>>.from(meta.semanticPorts ?? {});
    final portAssignments = Map<String, String>.from(meta.portAssignments ?? {});

    for (final p in detectedPorts) {
      semanticPorts[p.portId] = {
        'portId': p.portId,
        'side': p.inferredSide.name,
        'width': p.inferredWidth,
        'height': p.inferredHeightA,
        'heightA': p.inferredHeightA,
        'heightB': p.inferredHeightB,
        'normalX': p.normal.x,
        'normalY': p.normal.y,
        'normalAngleRad': p.outwardNormalAngleRad,
        'associatedFeatureIds': p.associatedFeatureIds,
      };
      portAssignments[p.portId] = p.inferredSide.name;
    }

    return meta.copyWith(
      semanticPorts: semanticPorts,
      portAssignments: portAssignments,
    );
  }
}

