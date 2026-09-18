import 'dart:math' as math;

import '../models/cad_primitives.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/fold_bend_line.dart';
import '../models/perforation_pattern.dart';
import '../models/sheet_metal_material.dart';
import '../models/dsf_document.dart';
import '../models/dsf_layer.dart';
import 'dxf_mini_parser.dart';
import 'planar_face_decomposer.dart';

class DxfRecognitionResult {
  final List<CadPoint2D> outerContour;
  final List<FoldBendLine> bendCandidates;
  final List<CncPunchPrimitive> roundHoles;
  final List<CncPunchPrimitive> slotHoles;
  final List<PerforationPattern> recognizedPatterns;
  final List<CadLineSegment> interiorCuts;
  final List<CadArc2D> recognizedArcs;
  final DsfDocument generatedDocument;
  final String summary;

  const DxfRecognitionResult({
    required this.outerContour,
    required this.bendCandidates,
    required this.roundHoles,
    required this.slotHoles,
    required this.recognizedPatterns,
    required this.interiorCuts,
    this.recognizedArcs = const [],
    required this.generatedDocument,
    required this.summary,
  });
}

class _CurveSegment {
  final CadPoint2D start;
  final CadPoint2D end;
  final List<CadPoint2D> points;
  final String layer;

  _CurveSegment({
    required this.start,
    required this.end,
    required this.points,
    this.layer = '',
  });
}

class DxfGeometryRecognitionEngine {
  /// Recognizes high-level sheet metal features from raw parsed DXF data
  static DxfRecognitionResult recognize(
    DxfParsedData parsed, {
    String productType = 'Sheet Metal Component',
    String itemName = 'Recognized DXF Part',
    SheetMetalMaterial material = const SheetMetalMaterial(),
  }) {
    final lines = parsed.getEntitiesOfType<DxfRawLine>();
    final polylines = parsed.getEntitiesOfType<DxfRawPolyline>();
    final circles = parsed.getEntitiesOfType<DxfRawCircle>();
    final arcs = parsed.getEntitiesOfType<DxfRawArc>();

    // 1. Recognize Outer Boundary and Interior Closed Loops
    final loopsResult = _recognizeLoopsAndOuterBoundary(
      lines: lines,
      polylines: polylines,
      arcs: arcs,
    );
    final rawOuterContour = loopsResult.outerContour;
    final interiorLoops = loopsResult.interiorLoops;

    // Bounding box of raw outer contour
    double rawMinX = 0, rawMaxX = 0, rawMinY = 0, rawMaxY = 0;
    if (rawOuterContour.isNotEmpty) {
      rawMinX = rawOuterContour.map((p) => p.x).reduce(math.min);
      rawMaxX = rawOuterContour.map((p) => p.x).reduce(math.max);
      rawMinY = rawOuterContour.map((p) => p.y).reduce(math.min);
      rawMaxY = rawOuterContour.map((p) => p.y).reduce(math.max);
    }

    // 2. Recognize Round Holes
    final roundHoles = <CncPunchPrimitive>[];
    int punchCounter = 1;
    for (final circle in circles) {
      roundHoles.add(
        CncPunchPrimitive.round(
          id: 'PUNCH_CIRC_$punchCounter',
          center: circle.center,
          diameterMm: circle.radius * 2.0,
          layer: circle.layer.isNotEmpty ? circle.layer : 'HOLES',
        ),
      );
      punchCounter++;
    }

    // 3. Recognize Obround Slots from paired lines & arcs, closed polylines, or interior loops
    final slotRecognition = _recognizeSlots(
      lines: lines,
      arcs: arcs,
      polylines: polylines,
      interiorLoops: interiorLoops,
      startCounter: punchCounter,
    );
    final slotHoles = slotRecognition.slots;
    final consumedSlotArcs = slotRecognition.consumedArcs;

    // 3B. Recognize Standalone & Boundary Arcs as First-Class CAD Entities
    final recognizedArcs = <CadArc2D>[];
    int arcCounter = 1;
    for (final a in arcs) {
      if (consumedSlotArcs.contains(a) || _isArcPartOfSlot(a, slotHoles)) continue;

      final sp = CadPoint2D(
        a.center.x + a.radius * math.cos(a.startAngleDeg * math.pi / 180.0),
        a.center.y + a.radius * math.sin(a.startAngleDeg * math.pi / 180.0),
      );
      final ep = CadPoint2D(
        a.center.x + a.radius * math.cos(a.endAngleDeg * math.pi / 180.0),
        a.center.y + a.radius * math.sin(a.endAngleDeg * math.pi / 180.0),
      );

      final isBnd = rawOuterContour.any((p) => p.distanceTo(sp) < 2.5) &&
          rawOuterContour.any((p) => p.distanceTo(ep) < 2.5);

      recognizedArcs.add(
        CadArc2D(
          id: isBnd ? 'ARC_BND_$arcCounter' : 'CUT_ARC_$arcCounter',
          center: a.center,
          radius: a.radius,
          startAngleDeg: a.startAngleDeg,
          endAngleDeg: a.endAngleDeg,
          startPoint: sp,
          endPoint: ep,
          layer: a.layer.isNotEmpty ? a.layer : (isBnd ? 'OUTLINE' : 'CUT'),
          isBoundary: isBnd,
        ),
      );
      arcCounter++;
    }

    // 4. Recognize Bend Candidates vs Interior Cuts
    final bendCandidates = <FoldBendLine>[];
    final interiorCuts = <CadLineSegment>[];
    int bendCounter = 1;
    int cutCounter = 1;

    for (final line in lines) {
      if (_isPartBoundaryLine(line, rawOuterContour)) continue;
      if (_isLinePartOfPunch(line, [...roundHoles, ...slotHoles])) continue;

      if (_isBendCandidate(
        line,
        minX: rawMinX,
        maxX: rawMaxX,
        minY: rawMinY,
        maxY: rawMaxY,
      )) {
        final dir = _detectBendDirection(line.layer, line.colorIndex);
        bendCandidates.add(
          FoldBendLine(
            id: 'BEND_$bendCounter',
            p1: line.p1,
            p2: line.p2,
            direction: dir,
            targetAngleDeg: 90.0,
            radiusMm: material.thicknessMm,
            layer: dir == BendDirection.up ? 'BEND_UP' : 'BEND_DOWN',
          ),
        );
        bendCounter++;
      } else {
        interiorCuts.add(
          CadLineSegment(
            id: 'CUT_$cutCounter',
            p1: line.p1,
            p2: line.p2,
            layer: line.layer,
          ),
        );
        cutCounter++;
      }
    }


    // 5. Recognize Repeated Perforation Patterns (linear or staggered arrays)
    final allPunches = [...roundHoles, ...slotHoles];
    final recognizedPatterns = _recognizePatterns(allPunches);

    // Remove punches that were absorbed into patterns
    final absorbedPunchIds = <String>{};
    for (final pat in recognizedPatterns) {
      final expanded = pat.expandToPunches();
      for (final ep in expanded) {
        final match = allPunches
            .where((p) => p.center.distanceTo(ep.center) < 1.0)
            .firstOrNull;
        if (match != null) absorbedPunchIds.add(match.id);
      }
    }
    final remainingPunches = allPunches
        .where((p) => !absorbedPunchIds.contains(p.id))
        .toList();

    // 6. Coordinate Normalization
    // Translate geometry so outer contour's min bounds start at (0, 0)
    final originX = rawMinX;
    final originY = rawMinY;
    CadPoint2D norm(CadPoint2D p) => CadPoint2D(p.x - originX, p.y - originY);

    final normalizedOuter = rawOuterContour.map(norm).toList();
    final normalizedBends = bendCandidates
        .map((b) => b.copyWith(p1: norm(b.p1), p2: norm(b.p2)))
        .toList();
    final normalizedCuts = interiorCuts
        .map(
          (c) => CadLineSegment(
            id: c.id,
            p1: norm(c.p1),
            p2: norm(c.p2),
            layer: c.layer,
          ),
        )
        .toList();
    final normalizedArcs = recognizedArcs
        .map(
          (a) => a.copyWith(
            center: norm(a.center),
            startPoint: norm(a.startPoint),
            endPoint: norm(a.endPoint),
          ),
        )
        .toList();
    final normalizedPunches = remainingPunches
        .map((p) => p.copyWith(center: norm(p.center)))
        .toList();
    final normalizedPatterns = recognizedPatterns
        .map((p) => p.copyWith(anchor: norm(p.anchor)))
        .toList();

    // 7. Planar Face Decomposition
    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: normalizedOuter,
      bends: normalizedBends,
      cutLines: normalizedCuts,
    );

    // 8. Build Retained DsfLayer List
    final discoveredLayerNames = <String>{
      'OUTLINE',
      ...bendCandidates.map((b) => b.layer),
      ...interiorCuts.map((c) => c.layer),
      ...allPunches.map((p) => p.layer),
      ...parsed.layers,
    };
    final dsfLayers = <DsfLayer>[];
    for (final name in discoveredLayerNames) {
      if (name.isEmpty) continue;
      final upper = name.toUpperCase();
      int colorHex = 0xFF64748B;
      String lineType = 'CONTINUOUS';

      if (upper.contains('BEND_UP') || upper.contains('UP')) {
        colorHex = 0xFF0284C7;
        lineType = 'DASHED';
      } else if (upper.contains('BEND_DOWN') || upper.contains('DOWN')) {
        colorHex = 0xFFD97706;
        lineType = 'DASHED';
      } else if (upper.contains('CUT') || upper.contains('EDGE')) {
        colorHex = 0xFFE11D48;
      } else if (upper.contains('HOLE') || upper.contains('PUNCH')) {
        colorHex = 0xFF059669;
      } else if (upper.contains('OUTLINE')) {
        colorHex = 0xFF0F172A;
      }

      dsfLayers.add(
        DsfLayer(
          name: name,
          colorHex: colorHex,
          lineType: lineType,
          strokeWidth: upper.contains('OUTLINE') ? 2.0 : 1.0,
        ),
      );
    }

    final generatedDoc = DsfDocument(
      productType: productType,
      itemName: itemName,
      material: material,
      outerContour: normalizedOuter,
      bends: decomp.connectedBends,
      faces: decomp.faces,
      punches: normalizedPunches,
      perforationPatterns: normalizedPatterns,
      cutLines: normalizedCuts,
      arcs: normalizedArcs,
      baseFaceId: decomp.baseFaceId,
      layers: dsfLayers,
    );

    final summary =
        'Recognized ${normalizedOuter.length} boundary points, '
        '${normalizedArcs.length} arcs, '
        '${normalizedBends.length} bend lines, ${roundHoles.length} round holes, '
        '${slotHoles.length} slots, and ${recognizedPatterns.length} pattern arrays.';

    return DxfRecognitionResult(
      outerContour: normalizedOuter,
      bendCandidates: normalizedBends,
      roundHoles: roundHoles
          .map((h) => h.copyWith(center: norm(h.center)))
          .toList(),
      slotHoles: slotHoles
          .map((s) => s.copyWith(center: norm(s.center)))
          .toList(),
      recognizedPatterns: normalizedPatterns,
      interiorCuts: normalizedCuts,
      recognizedArcs: normalizedArcs,
      generatedDocument: generatedDoc,
      summary: summary,
    );
  }

  static bool _isArcPartOfSlot(DxfRawArc arc, List<CncPunchPrimitive> slots) {
    for (final s in slots) {
      if (s.type != PunchType.obroundSlot) continue;
      final slotW = s.widthMm > 0 ? s.widthMm : s.diameterMm;
      final halfW = slotW / 2.0;
      if ((arc.radius - halfW).abs() > 1.5) continue;
      final halfD = (s.lengthMm - slotW) / 2.0;
      final rad = s.rotationDeg * math.pi / 180.0;
      final c1 = CadPoint2D(s.center.x + halfD * math.cos(rad), s.center.y + halfD * math.sin(rad));
      final c2 = CadPoint2D(s.center.x - halfD * math.cos(rad), s.center.y - halfD * math.sin(rad));
      if (arc.center.distanceTo(c1) < 2.5 || arc.center.distanceTo(c2) < 2.5) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Recognition Helpers
  // ---------------------------------------------------------------------------

  static ({List<CadPoint2D> outerContour, List<List<CadPoint2D>> interiorLoops})
  _recognizeLoopsAndOuterBoundary({
    required List<DxfRawLine> lines,
    required List<DxfRawPolyline> polylines,
    required List<DxfRawArc> arcs,
  }) {
    final candidateLoops = <List<CadPoint2D>>[];

    // 1. Add closed polylines directly as candidates
    for (final poly in polylines) {
      if (poly.vertices.length >= 3) {
        candidateLoops.add(_deduplicatePoints(poly.vertices));
      }
    }

    // 2. Build segments from boundary lines, arcs, and open polylines
    final boundaryLines = lines.where((l) {
      final layer = l.layer.toUpperCase();
      return !layer.contains('BEND') &&
          !layer.contains('FOLD') &&
          !layer.contains('CENTER');
    }).toList();

    final segments = <_CurveSegment>[];
    for (final l in boundaryLines) {
      segments.add(
        _CurveSegment(
          start: l.p1,
          end: l.p2,
          points: [l.p1, l.p2],
          layer: l.layer,
        ),
      );
    }

    for (final a in arcs) {
      final sp = CadPoint2D(
        a.center.x + a.radius * math.cos(a.startAngleDeg * math.pi / 180.0),
        a.center.y + a.radius * math.sin(a.startAngleDeg * math.pi / 180.0),
      );
      final ep = CadPoint2D(
        a.center.x + a.radius * math.cos(a.endAngleDeg * math.pi / 180.0),
        a.center.y + a.radius * math.sin(a.endAngleDeg * math.pi / 180.0),
      );
      segments.add(
        _CurveSegment(
          start: sp,
          end: ep,
          points: [sp, ep],
          layer: a.layer,
        ),
      );
    }

    for (final p in polylines) {
      if (!p.isClosed && p.vertices.length >= 2) {
        segments.add(
          _CurveSegment(
            start: p.vertices.first,
            end: p.vertices.last,
            points: p.vertices,
            layer: p.layer,
          ),
        );
      }
    }

    // 3. Chain segments into closed loops
    final chainedLoops = _chainCurveSegments(segments);
    candidateLoops.addAll(chainedLoops);

    // 4. Select the candidate loop with the maximum bounding box area
    List<CadPoint2D> bestOuter = [];
    double maxArea = -1.0;
    int bestIdx = -1;

    for (int i = 0; i < candidateLoops.length; i++) {
      final loop = candidateLoops[i];
      final area = _calculateBoundingArea(loop);
      if (area > maxArea) {
        maxArea = area;
        bestOuter = loop;
        bestIdx = i;
      }
    }

    final interiorLoops = <List<CadPoint2D>>[];
    for (int i = 0; i < candidateLoops.length; i++) {
      if (i != bestIdx) {
        interiorLoops.add(candidateLoops[i]);
      }
    }

    // Fallback: If no closed loop has area > 50 mm², compute bounding box of lines
    if (maxArea < 50.0 && lines.isNotEmpty) {
      double minX = lines.first.p1.x, maxX = lines.first.p1.x;
      double minY = lines.first.p1.y, maxY = lines.first.p1.y;
      for (final l in lines) {
        minX = math.min(minX, math.min(l.p1.x, l.p2.x));
        maxX = math.max(maxX, math.max(l.p1.x, l.p2.x));
        minY = math.min(minY, math.min(l.p1.y, l.p2.y));
        maxY = math.max(maxY, math.max(l.p1.y, l.p2.y));
      }
      bestOuter = [
        CadPoint2D(minX, minY),
        CadPoint2D(maxX, minY),
        CadPoint2D(maxX, maxY),
        CadPoint2D(minX, maxY),
      ];
    }

    return (outerContour: bestOuter, interiorLoops: interiorLoops);
  }


  static List<List<CadPoint2D>> _chainCurveSegments(
    List<_CurveSegment> segments, {
    double tolerance = 1.5,
  }) {
    final loops = <List<CadPoint2D>>[];
    final pool = <_CurveSegment>[];

    // Remove exact duplicate segments and redundant collinear subsegments before chaining
    for (final s in segments) {
      bool isRedundant = false;
      for (int i = 0; i < pool.length; i++) {
        final existing = pool[i];
        if ((s.start.distanceTo(existing.start) < 0.1 &&
                s.end.distanceTo(existing.end) < 0.1) ||
            (s.start.distanceTo(existing.end) < 0.1 &&
                s.end.distanceTo(existing.start) < 0.1)) {
          isRedundant = true;
          break;
        }
        if (s.points.length == 2 && existing.points.length == 2) {
          if (_isCollinearSubsegment(s.start, s.end, existing.start, existing.end)) {
            isRedundant = true;
            break;
          } else if (_isCollinearSubsegment(existing.start, existing.end, s.start, s.end)) {
            pool[i] = s;
            isRedundant = true;
            break;
          }
        }
      }
      if (!isRedundant) pool.add(s);
    }

    while (pool.isNotEmpty) {
      final currentLoop = <CadPoint2D>[];
      var currentSeg = pool.removeAt(0);
      currentLoop.addAll(currentSeg.points);

      bool closed = false;
      while (pool.isNotEmpty) {
        final tail = currentLoop.last;
        if (currentLoop.length > 2 &&
            tail.distanceTo(currentLoop.first) <= tolerance) {
          closed = true;
          break;
        }

        int matchIdx = -1;
        bool reverse = false;
        for (int i = 0; i < pool.length; i++) {
          final seg = pool[i];
          if (seg.start.distanceTo(tail) <= tolerance) {
            matchIdx = i;
            reverse = false;
            break;
          } else if (seg.end.distanceTo(tail) <= tolerance) {
            matchIdx = i;
            reverse = true;
            break;
          }
        }

        if (matchIdx != -1) {
          final nextSeg = pool.removeAt(matchIdx);
          final ptsToAdd = reverse
              ? nextSeg.points.reversed.toList()
              : nextSeg.points;
          currentLoop.addAll(ptsToAdd.skip(1));
        } else {
          break;
        }
      }

      if (currentLoop.length > 2 &&
          currentLoop.last.distanceTo(currentLoop.first) <= tolerance) {
        closed = true;
      }

      if (closed && currentLoop.length >= 3) {
        loops.add(_deduplicatePoints(currentLoop));
      }
    }

    return loops;
  }

  static double _calculateBoundingArea(List<CadPoint2D> loop) {
    if (loop.isEmpty) return 0.0;
    double minX = loop.first.x, maxX = loop.first.x;
    double minY = loop.first.y, maxY = loop.first.y;
    for (final p in loop) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    return (maxX - minX) * (maxY - minY);
  }

  static List<CadPoint2D> _deduplicatePoints(List<CadPoint2D> pts) {
    final clean = <CadPoint2D>[];
    for (final p in pts) {
      if (clean.isEmpty || clean.last.distanceTo(p) > 0.05) {
        clean.add(p);
      }
    }
    return clean;
  }

  static bool _isPartBoundaryLine(
    DxfRawLine line,
    List<CadPoint2D> outerContour,
  ) {
    if (outerContour.length < 2) return false;
    const eps = 1.0;
    for (int i = 0; i < outerContour.length; i++) {
      final pA = outerContour[i];
      final pB = outerContour[(i + 1) % outerContour.length];
      final fwd = line.p1.distanceTo(pA) < eps && line.p2.distanceTo(pB) < eps;
      final rev = line.p1.distanceTo(pB) < eps && line.p2.distanceTo(pA) < eps;
      if (fwd || rev) return true;

      // Collinear subsegment check along boundary edge
      if (_isCollinearSubsegment(line.p1, line.p2, pA, pB, tolerance: 0.5)) {
        return true;
      }
    }
    return false;
  }

  static bool _isCollinearSubsegment(
    CadPoint2D b1,
    CadPoint2D b2,
    CadPoint2D a1,
    CadPoint2D a2, {
    double tolerance = 0.05,
  }) {
    final dxA = a2.x - a1.x;
    final dyA = a2.y - a1.y;
    final lenSqA = dxA * dxA + dyA * dyA;
    if (lenSqA < 1e-6) return false;
    final lenA = math.sqrt(lenSqA);
    final ux = dxA / lenA;
    final uy = dyA / lenA;
    final nx = -uy;
    final ny = ux;

    final dist1 = ((b1.x - a1.x) * nx + (b1.y - a1.y) * ny).abs();
    final dist2 = ((b2.x - a1.x) * nx + (b2.y - a1.y) * ny).abs();
    if (dist1 > tolerance || dist2 > tolerance) return false;

    final t1 = (b1.x - a1.x) * ux + (b1.y - a1.y) * uy;
    final t2 = (b2.x - a1.x) * ux + (b2.y - a1.y) * uy;
    final minT = math.min(t1, t2);
    final maxT = math.max(t1, t2);

    return minT >= -tolerance && maxT <= lenA + tolerance;
  }

  static bool _isBendCandidate(
    DxfRawLine line, {
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
  }) {
    final layer = line.layer.toUpperCase();
    if (layer.contains('BEND') ||
        layer.contains('FOLD') ||
        layer.contains('CREASE')) {
      return true;
    }
    if (line.colorIndex == 4 || line.colorIndex == 2) {
      return true;
    }

    // Geometric check: Straight line that spans from near one outer edge to an opposite edge
    final spansHoriz =
        (line.p1.x - minX).abs() < 1.0 && (line.p2.x - maxX).abs() < 1.0;
    final spansVert =
        (line.p1.y - minY).abs() < 1.0 && (line.p2.y - maxY).abs() < 1.0;
    return spansHoriz || spansVert;
  }

  static BendDirection _detectBendDirection(String layer, int colorIndex) {
    final upper = layer.toUpperCase();
    if (upper.contains('DOWN') || colorIndex == 2) {
      return BendDirection.down;
    }
    return BendDirection.up;
  }

  static bool _isLinePartOfPunch(DxfRawLine line, List<CncPunchPrimitive> punches) {
    final midX = (line.p1.x + line.p2.x) / 2.0;
    final midY = (line.p1.y + line.p2.y) / 2.0;
    final mid = CadPoint2D(midX, midY);

    for (final p in punches) {
      if (p.isSlot) {
        final dist = mid.distanceTo(p.center);
        if (dist > (p.lengthMm / 2.0 + 1.5)) continue;

        // Transform line midpoint into slot-local coordinate system
        final rad = p.rotationDeg * math.pi / 180.0;
        final cosR = math.cos(rad);
        final sinR = math.sin(rad);
        final dx = mid.x - p.center.x;
        final dy = mid.y - p.center.y;
        final localX = (dx * cosR + dy * sinR).abs();
        final localY = (-dx * sinR + dy * cosR).abs();

        if (localX <= (p.lengthMm / 2.0 + 1.0) &&
            localY <= (p.widthMm / 2.0 + 1.0)) {
          return true;
        }
      } else if (p.isRound) {
        if (mid.distanceTo(p.center) <= (p.diameterMm / 2.0 + 1.0)) {
          return true;
        }
      }
    }
    return false;
  }

  static CncPunchPrimitive? _recognizeSlotFromVertices(
    List<CadPoint2D> vertices,
    int slotIdNumber,
  ) {
    if (vertices.length < 3) return null;

    // Filter out trailing duplicate closing vertex if present
    final pts = <CadPoint2D>[];
    for (final p in vertices) {
      if (pts.isEmpty || pts.last.distanceTo(p) > 0.01) {
        pts.add(p);
      }
    }
    if (pts.length > 3 && pts.first.distanceTo(pts.last) < 0.05) {
      pts.removeLast();
    }
    if (pts.length < 3) return null;

    double minX = pts.first.x, maxX = pts.first.x;
    double minY = pts.first.y, maxY = pts.first.y;
    double sumX = 0, sumY = 0;
    for (final p in pts) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
      sumX += p.x;
      sumY += p.y;
    }
    final boxW = maxX - minX;
    final boxH = maxY - minY;
    if (boxW < 1.0 || boxH < 1.0 || boxW > 150.0 || boxH > 150.0) return null;

    final centroid = CadPoint2D(sumX / pts.length, sumY / pts.length);

    double length;
    double width;
    double theta;

    if (pts.length == 4) {
      // 4-vertex rectangle: side lengths are between adjacent vertices
      final side1 = pts[0].distanceTo(pts[1]);
      final side2 = pts[1].distanceTo(pts[2]);
      if (side1 >= side2) {
        length = side1;
        width = side2;
        theta = math.atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x);
      } else {
        length = side2;
        width = side1;
        theta = math.atan2(pts[2].y - pts[1].y, pts[2].x - pts[1].x);
      }
    } else {
      // Multi-vertex curved obround loop: maximum chord between any two vertices
      double maxDistSq = -1.0;
      CadPoint2D pA = pts.first;
      CadPoint2D pB = pts.first;
      for (int i = 0; i < pts.length; i++) {
        for (int j = i + 1; j < pts.length; j++) {
          final dx = pts[i].x - pts[j].x;
          final dy = pts[i].y - pts[j].y;
          final dSq = dx * dx + dy * dy;
          if (dSq > maxDistSq) {
            maxDistSq = dSq;
            pA = pts[i];
            pB = pts[j];
          }
        }
      }
      length = math.sqrt(maxDistSq);
      if (length < 1.0) return null;

      // Major axis direction
      theta = math.atan2(pB.y - pA.y, pB.x - pA.x);

      // Transverse width: project all vertices onto the normal vector (-sin(theta), cos(theta))
      final cosT = math.cos(theta);
      final sinT = math.sin(theta);
      double minV = double.infinity;
      double maxV = -double.infinity;
      for (final p in pts) {
        final v = -(p.x - centroid.x) * sinT + (p.y - centroid.y) * cosT;
        minV = math.min(minV, v);
        maxV = math.max(maxV, v);
      }
      width = maxV - minV;
    }

    if (width < 0.5) return null;

    final ratio = length / width;
    if (ratio < 1.15 || ratio > 15.0) return null;

    while (theta < 0) {
      theta += math.pi;
    }
    while (theta >= math.pi) {
      theta -= math.pi;
    }

    var rotDeg = theta * 180.0 / math.pi;
    for (final stdAngle in [0.0, 30.0, 45.0, 60.0, 90.0, 120.0, 135.0, 150.0, 180.0]) {
      if ((rotDeg - stdAngle).abs() < 1.0) {
        rotDeg = stdAngle == 180.0 ? 0.0 : stdAngle;
        break;
      }
    }

    return CncPunchPrimitive.obround(
      id: 'SLOT_$slotIdNumber',
      center: centroid,
      widthMm: width,
      lengthMm: length,
      rotationDeg: rotDeg,
    );
  }


  static ({List<CncPunchPrimitive> slots, Set<DxfRawArc> consumedArcs}) _recognizeSlots({
    required List<DxfRawLine> lines,
    required List<DxfRawArc> arcs,
    required List<DxfRawPolyline> polylines,
    required List<List<CadPoint2D>> interiorLoops,
    required int startCounter,
  }) {
    final slots = <CncPunchPrimitive>[];
    final consumedArcs = <DxfRawArc>{};
    int counter = startCounter;

    // 1. Complementary Arc-Pair Slot Recognition:
    // Pair semicircular arcs (~180° sweep) of equal radius facing each other.
    // This gives the exact width (2 * radius) and true total length (centerDist + 2 * radius).
    final semiArcs = <DxfRawArc>[];
    for (final a in arcs) {
      double start = a.startAngleDeg;
      double end = a.endAngleDeg;
      if (end < start) end += 360.0;
      final sweep = end - start;
      if ((sweep - 180.0).abs() < 6.0 && a.radius >= 0.5 && a.radius <= 50.0) {
        semiArcs.add(a);
      }
    }

    final matchedIndices = <int>{};
    for (int i = 0; i < semiArcs.length; i++) {
      if (matchedIndices.contains(i)) continue;
      final a1 = semiArcs[i];
      for (int j = i + 1; j < semiArcs.length; j++) {
        if (matchedIndices.contains(j)) continue;
        final a2 = semiArcs[j];
        if ((a1.radius - a2.radius).abs() < 0.2) {
          final centerDist = a1.center.distanceTo(a2.center);
          if (centerDist >= 0.5 && centerDist <= 150.0) {
            final slotCenter = CadPoint2D(
              (a1.center.x + a2.center.x) / 2.0,
              (a1.center.y + a2.center.y) / 2.0,
            );
            final width = a1.radius * 2.0;
            final length = centerDist + width;
            var angleRad = math.atan2(a2.center.y - a1.center.y, a2.center.x - a1.center.x);
            while (angleRad < 0) {
              angleRad += math.pi;
            }
            while (angleRad >= math.pi) {
              angleRad -= math.pi;
            }
            var rotDeg = angleRad * 180.0 / math.pi;
            for (final stdAngle in [0.0, 30.0, 45.0, 60.0, 90.0, 120.0, 135.0, 150.0, 180.0]) {
              if ((rotDeg - stdAngle).abs() < 1.0) {
                rotDeg = stdAngle == 180.0 ? 0.0 : stdAngle;
                break;
              }
            }

            final existingIdx = slots.indexWhere((s) => s.center.distanceTo(slotCenter) < 1.0);
            if (existingIdx != -1) {
              slots[existingIdx] = CncPunchPrimitive.obround(
                id: slots[existingIdx].id,
                center: slotCenter,
                widthMm: width,
                lengthMm: length,
                rotationDeg: rotDeg,
              );
            } else {
              slots.add(
                CncPunchPrimitive.obround(
                  id: 'SLOT_$counter',
                  center: slotCenter,
                  widthMm: width,
                  lengthMm: length,
                  rotationDeg: rotDeg,
                ),
              );
              counter++;
            }
            matchedIndices.add(i);
            matchedIndices.add(j);
            consumedArcs.add(a1);
            consumedArcs.add(a2);
            break;
          }
        }
      }
    }

    void addSlotIfUnique(CncPunchPrimitive? s) {
      if (s == null) return;
      if (!slots.any((existing) => existing.center.distanceTo(s.center) < 1.0)) {
        slots.add(s);
        counter++;
      }
    }

    // 2. Process closed polylines
    for (final poly in polylines) {
      addSlotIfUnique(_recognizeSlotFromVertices(poly.vertices, counter));
    }

    // 3. Process interior closed loops from curve chaining
    for (final loop in interiorLoops) {
      addSlotIfUnique(_recognizeSlotFromVertices(loop, counter));
    }

    return (slots: slots, consumedArcs: consumedArcs);
  }

  static List<PerforationPattern> _recognizePatterns(
    List<CncPunchPrimitive> punches,
  ) {
    final patterns = <PerforationPattern>[];
    if (punches.length < 4) return patterns;

    // Group punches by shape (round vs obround) and dimensions
    final groups = <String, List<CncPunchPrimitive>>{};
    for (final p in punches) {
      final key =
          '${p.shape.name}_${p.diameterMm.toStringAsFixed(1)}_${p.widthMm.toStringAsFixed(1)}_${p.lengthMm.toStringAsFixed(1)}';
      groups.putIfAbsent(key, () => []).add(p);
    }

    int patternCounter = 1;
    for (final group in groups.values) {
      if (group.length < 4) continue;

      // Extract unique X and Y coordinates (clustered with 1.0 mm tolerance)
      final xCoords = <double>[];
      final yCoords = <double>[];
      for (final p in group) {
        if (!xCoords.any((x) => (x - p.center.x).abs() < 1.0)) {
          xCoords.add(p.center.x);
        }
        if (!yCoords.any((y) => (y - p.center.y).abs() < 1.0)) {
          yCoords.add(p.center.y);
        }
      }
      xCoords.sort();
      yCoords.sort();

      // STRICT VALIDATION: A rectangular grid must have countX * countY == group.length
      if (xCoords.length >= 2 && yCoords.length >= 2) {
        if (group.length != xCoords.length * yCoords.length) {
          // Incomplete grid! Do NOT synthesize non-existent phantom holes.
          continue;
        }

        final pitchX = (xCoords.last - xCoords.first) / (xCoords.length - 1);
        final pitchY = (yCoords.last - yCoords.first) / (yCoords.length - 1);

        // Verify uniform column pitch
        bool uniformX = true;
        for (int i = 0; i < xCoords.length - 1; i++) {
          if (((xCoords[i + 1] - xCoords[i]) - pitchX).abs() > 0.5) {
            uniformX = false;
            break;
          }
        }
        if (!uniformX) continue;

        // Verify uniform row pitch
        bool uniformY = true;
        for (int j = 0; j < yCoords.length - 1; j++) {
          if (((yCoords[j + 1] - yCoords[j]) - pitchY).abs() > 0.5) {
            uniformY = false;
            break;
          }
        }
        if (!uniformY) continue;

        // Verify every grid intersection actually exists in group
        bool allExist = true;
        for (final x in xCoords) {
          for (final y in yCoords) {
            final exists = group.any(
              (p) => (p.center.x - x).abs() < 1.0 && (p.center.y - y).abs() < 1.0,
            );
            if (!exists) {
              allExist = false;
              break;
            }
          }
          if (!allExist) break;
        }
        if (!allExist) continue;

        final representative = group.first;
        patterns.add(
          PerforationPattern(
            id: 'PAT_$patternCounter',
            anchor: CadPoint2D(
              (xCoords.first + xCoords.last) / 2.0,
              (yCoords.first + yCoords.last) / 2.0,
            ),
            holeType: representative.type,
            diameterMm: representative.diameterMm,
            slotWidthMm: representative.widthMm,
            slotLengthMm: representative.lengthMm,
            rotationDeg: representative.angleDeg,
            countX: xCoords.length,
            countY: yCoords.length,
            pitchX: pitchX,
            pitchY: pitchY,
          ),
        );
        patternCounter++;
      }
    }

    return patterns;
  }
}

