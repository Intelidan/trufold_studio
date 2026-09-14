// =============================================================================
// cnc_turret_engine.dart
//
// CNC Turret Punch & Sheet Metal Modification Engine for DSF Studio.
// Handles punch generation (Round, Obround, Square), edge/bend distance
// constraints, and corner contour treatments (fillets and chamfers).
// =============================================================================

import 'dart:math' as math;

import '../models/cad_primitives.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/dsf_document.dart';
import '../models/perforation_pattern.dart';
import '../models/planar_sheet_face.dart';

class PunchConstraints {
  final double distFromLeftMm;
  final double distFromRightMm;
  final double distFromBottomMm;
  final double distFromTopMm;
  final double? distToNearestBendMm;
  final String? nearestBendId;

  const PunchConstraints({
    required this.distFromLeftMm,
    required this.distFromRightMm,
    required this.distFromBottomMm,
    required this.distFromTopMm,
    this.distToNearestBendMm,
    this.nearestBendId,
  });
}

class CncTurretEngine {
  /// Computes exact edge and bend line distance constraints for a punch
  static PunchConstraints computeConstraints({
    required CncPunchPrimitive punch,
    required DsfDocument doc,
  }) {
    final cx = punch.center.x;
    final cy = punch.center.y;
    final bw = doc.blankWidthMm;
    final bl = doc.blankLengthMm;

    final distLeft = cx;
    final distRight = math.max(0.0, bw - cx);
    final distBottom = cy;
    final distTop = math.max(0.0, bl - cy);

    double? minBendDist;
    String? nearestBend;

    for (final bend in doc.bends) {
      final d = _distToSegment(punch.center, bend.p1, bend.p2);
      if (minBendDist == null || d < minBendDist) {
        minBendDist = d;
        nearestBend = bend.id;
      }
    }

    return PunchConstraints(
      distFromLeftMm: distLeft,
      distFromRightMm: distRight,
      distFromBottomMm: distBottom,
      distFromTopMm: distTop,
      distToNearestBendMm: minBendDist,
      nearestBendId: nearestBend,
    );
  }

  /// Creates a standard round bolt clearance hole (M6, M8, M10, etc.)
  static CncPunchPrimitive createRoundHole({
    required String id,
    required CadPoint2D center,
    double diameterMm = 8.0,
  }) {
    return CncPunchPrimitive.round(
      id: id,
      center: center,
      diameterMm: diameterMm,
    );
  }

  /// Creates an industrial Cable Tray Obround Slot (e.g. 7x25mm or 9x25mm)
  static CncPunchPrimitive createObroundSlot({
    required String id,
    required CadPoint2D center,
    double widthMm = 7.0,
    double lengthMm = 25.0,
    double rotationDeg = 0.0,
  }) {
    return CncPunchPrimitive.obround(
      id: id,
      center: center,
      widthMm: widthMm,
      lengthMm: lengthMm,
      rotationDeg: rotationDeg,
    );
  }

  /// Creates a rectangular coupler connection slot or knockout
  static CncPunchPrimitive createRectangularPunch({
    required String id,
    required CadPoint2D center,
    double widthMm = 20.0,
    double heightMm = 8.0,
    double rotationDeg = 0.0,
  }) {
    return CncPunchPrimitive(
      id: id,
      type: PunchType.rectangle,
      center: center,
      widthMm: widthMm,
      lengthMm: heightMm,
      rotationDeg: rotationDeg,
    );
  }

  /// Generates a standard industrial Cable Management System (CMS) tray bed perforation array.
  /// Auto-nests a unified perforation pattern onto any selected planar sheet surface.
  /// Applies industrial Cable Management System (CMS) modular pitch rules:
  /// - Standard tray widths (50, 100, 150, 250, 300, 450, 600, 750, 900 mm):
  ///   Width-wise pitch: 50 mm, side margin: 25 mm.
  /// - Side walls (50 mm height): 2 rows of perforation (25 mm pitch, 12.5 mm margin).
  /// - Longitudinal pitch: 80 mm, center-to-center staggered punch distance: 25 mm.
  /// - End margins: 50 mm.
  /// - Slot dimensions: Obround 30x7 mm default.
  /// - Automatically clips/excludes any holes that violate face boundaries.
  static PerforationPattern autoNestPerforationOnFace({
    required PlanarSheetFace face,
    required DsfDocument doc,
    PunchType holeType = PunchType.obroundSlot,
    double slotWidth = 7.0,
    double slotLength = 30.0,
    double diameterMm = 8.0,
    double pitchY = 80.0,
    double staggerDistance = 25.0,
    double endMargin = 50.0,
    double? rotationDeg,
    bool staggered = true,
    int? overrideCols,
    double? overridePitchX,
    String? patternId,
    String layer = 'HOLES',
  }) {
    if (face.vertices.isEmpty) {
      return PerforationPattern(
        id: patternId ?? 'PAT_${face.id}',
        anchor: const CadPoint2D(0, 0),
        countX: 1,
        countY: 1,
        pitchX: 50.0,
        pitchY: pitchY,
      );
    }

    // 1. Compute bounding box of face
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final v in face.vertices) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
    }

    final dimX = maxX - minX;
    final dimY = maxY - minY;
    // In standard unfolding, Y is length and X is width
    final bool isLongitudinalY = dimY >= dimX;
    final faceWidth = isLongitudinalY ? dimX : dimY;
    final faceLength = isLongitudinalY ? dimY : dimX;

    // 2. Width-wise columns & pitch auto-selection
    int countX;
    double pitchX;
    final isSideWall = face.role == FaceRole.sideWall || (faceWidth >= 35.0 && faceWidth <= 65.0 && face.role != FaceRole.baseFloor);

    if (overrideCols != null && overrideCols > 0) {
      countX = overrideCols;
      pitchX = overridePitchX ?? ((countX > 1) ? (faceWidth - 50.0) / (countX - 1) : 0.0);
    } else if (overridePitchX != null && overridePitchX > 0) {
      pitchX = overridePitchX;
      countX = math.max(1, ((faceWidth - 50.0) / pitchX).round() + 1);
    } else if (isSideWall) {
      // Side wall rules: 50mm wall -> 2 rows (25mm pitch), 100mm -> 4 rows, 200mm -> 8 rows
      countX = math.max(1, (faceWidth / 25.0).round());
      pitchX = (countX > 1) ? (faceWidth - 25.0) / (countX - 1) : 0.0;
    } else {
      // Tray bed floor: 50, 100, 150, 250, 300, 450, 600, 750, 900 mm
      countX = math.max(1, (faceWidth / 50.0).round());
      pitchX = (countX > 1) ? (faceWidth - 50.0) / (countX - 1) : 0.0;
    }

    // 3. Longitudinal rows & pitch (80mm pitch, 25mm stagger, 50mm end margin)
    final usableL = faceLength - (2.0 * endMargin) - (staggered ? staggerDistance : 0.0);
    final countY = usableL > 0 ? math.max(1, (usableL / pitchY).floor() + 1) : 1;

    // 4. Default slot rotation:
    // Bed floor: 0° (transverse obround 30x7 across tray width)
    // Side wall: 90° (longitudinal along tray wall)
    final double effectiveRotation = rotationDeg ?? (isSideWall ? 90.0 : 0.0);

    // 5. Anchor at face centroid (adjusted along longitudinal axis so staggered pattern is centered)
    final anchor = isLongitudinalY
        ? CadPoint2D(face.centroid.x, face.centroid.y - (staggered ? staggerDistance / 2.0 : 0.0))
        : CadPoint2D(face.centroid.x - (staggered ? staggerDistance / 2.0 : 0.0), face.centroid.y);

    final pat = PerforationPattern(
      id: patternId ?? 'PAT_${face.id}',
      anchor: anchor,
      holeType: holeType,
      slotWidthMm: slotWidth,
      slotLengthMm: slotLength,
      diameterMm: diameterMm,
      countX: countX,
      countY: countY,
      pitchX: pitchX,
      pitchY: pitchY,
      staggered: staggered,
      staggerDistanceMm: staggerDistance,
      staggerAlongY: isLongitudinalY,
      rotationDeg: effectiveRotation,
      layer: layer,
      targetFaceId: face.id,
    );

    // 6. Boundary clipping: exclude any holes that lie outside the face boundary
    final excluded = <int>{};
    final minClearance = math.min(slotWidth, slotLength) / 2.0;

    for (int iy = 0; iy < countY; iy++) {
      for (int ix = 0; ix < countX; ix++) {
        final idx = iy * countX + ix;
        final center = pat.holeCenter(idx);

        if (!_pointInPolygon(center, face.vertices) ||
            _distanceToPolygonBoundary(center, face.vertices) < minClearance) {
          excluded.add(idx);
        }
      }
    }

    return pat.copyWith(deletedHoleIndices: excluded);
  }

  static bool _pointInPolygon(CadPoint2D pt, List<CadPoint2D> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].x, yi = polygon[i].y;
      final xj = polygon[j].x, yj = polygon[j].y;
      final intersect = ((yi > pt.y) != (yj > pt.y)) &&
          (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }


  static double _distanceToPolygonBoundary(CadPoint2D pt, List<CadPoint2D> polygon) {
    double minDist = double.infinity;
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      final d = _distToSegment(pt, polygon[i], polygon[j]);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  /// Generates a standard industrial Cable Management System (CMS) tray bed perforation array.
  /// Generates obround slots (e.g. 7x30mm or 7x25mm) distributed across the bottom bed floor.
  static List<CncPunchPrimitive> generateTrayPerforationArray({
    required DsfDocument doc,
    double slotWidth = 7.0,
    double slotLength = 25.0,
    int rows = 2,
    double pitchY = 100.0,
    double sideMargin = 20.0,
    double endMargin = 50.0,
    double rotationDeg = 90.0,
    String layer = 'HOLES',
  }) {
    // 1. Identify base floor face
    PlanarSheetFace? baseFace;
    for (final face in doc.faces) {
      if (face.id == doc.baseFaceId || face.role == FaceRole.baseFloor) {
        baseFace = face;
        break;
      }
    }
    baseFace ??= doc.faces.isNotEmpty ? doc.faces.first : null;
    if (baseFace == null || baseFace.vertices.isEmpty) return [];

    // 2. Compute bounding box of bed face
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final v in baseFace.vertices) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
    }

    final bedW = maxX - minX;
    final bedL = maxY - minY;
    if (bedW <= 0 || bedL <= 0) return [];

    // 3. Compute transverse column centers
    final xCoords = <double>[];
    if (rows <= 1) {
      xCoords.add(minX + bedW / 2.0);
    } else {
      final usableW = math.max(10.0, bedW - 2 * sideMargin);
      final spacing = usableW / (rows - 1);
      for (int i = 0; i < rows; i++) {
        xCoords.add(minX + sideMargin + i * spacing);
      }
    }

    // 4. Compute longitudinal row centers along length
    final yCoords = <double>[];
    final startY = minY + endMargin;
    final endY = maxY - endMargin;
    if (startY <= endY) {
      for (double y = startY; y <= endY + 1e-4; y += pitchY) {
        yCoords.add(y);
      }
    } else {
      yCoords.add(minY + bedL / 2.0);
    }

    // 5. Generate punches
    final punches = <CncPunchPrimitive>[];
    int counter = doc.punches.length + 1;
    for (final y in yCoords) {
      for (final x in xCoords) {
        punches.add(
          CncPunchPrimitive.obround(
            id: 'P_SLOT_$counter',
            center: CadPoint2D(x, y),
            widthMm: slotWidth,
            lengthMm: slotLength,
            rotationDeg: rotationDeg,
            layer: layer,
          ),
        );
        counter++;
      }
    }
    return punches;
  }

  /// Generates standard CMS side-rail coupler slot pairs at the ends of side walls.
  /// Allows technical datasheet generation and CAM press tooling for splice plates.
  static List<CncPunchPrimitive> generateSideRailCouplerSlots({
    required DsfDocument doc,
    double slotWidth = 7.0,
    double slotLength = 20.0,
    double endOffset = 25.0,
    double verticalSpacing = 25.0,
    String layer = 'HOLES',
  }) {
    final sideWalls = doc.faces
        .where((f) => f.role == FaceRole.sideWall)
        .toList();
    if (sideWalls.isEmpty) return [];

    final couplers = <CncPunchPrimitive>[];
    int counter = doc.punches.length + 1;

    for (final wall in sideWalls) {
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      for (final v in wall.vertices) {
        if (v.x < minX) minX = v.x;
        if (v.x > maxX) maxX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.y > maxY) maxY = v.y;
      }

      final wallHeight = maxX - minX;
      final wallLength = maxY - minY;
      if (wallLength < endOffset * 2) continue;

      final centerX = (minX + maxX) / 2.0;
      final yEnds = [minY + endOffset, maxY - endOffset];

      for (final y in yEnds) {
        if (wallHeight >= verticalSpacing + 20.0) {
          // Pair of slots (top and bottom)
          final xTop = centerX + verticalSpacing / 2.0;
          final xBot = centerX - verticalSpacing / 2.0;
          couplers.add(
            CncPunchPrimitive.obround(
              id: 'P_CPLR_$counter',
              center: CadPoint2D(xTop, y),
              widthMm: slotWidth,
              lengthMm: slotLength,
              rotationDeg: 0.0,
              layer: layer,
            ),
          );
          counter++;
          couplers.add(
            CncPunchPrimitive.obround(
              id: 'P_CPLR_$counter',
              center: CadPoint2D(xBot, y),
              widthMm: slotWidth,
              lengthMm: slotLength,
              rotationDeg: 0.0,
              layer: layer,
            ),
          );
          counter++;
        } else {
          // Single centered coupler slot
          couplers.add(
            CncPunchPrimitive.obround(
              id: 'P_CPLR_$counter',
              center: CadPoint2D(centerX, y),
              widthMm: slotWidth,
              lengthMm: slotLength,
              rotationDeg: 0.0,
              layer: layer,
            ),
          );
          counter++;
        }
      }
    }
    return couplers;
  }

  /// Applies a 45° corner chamfer (miter cut) to a specific vertex of the outer contour
  static List<CadPoint2D> applyCornerChamfer({
    required List<CadPoint2D> contour,
    required int vertexIndex,
    double chamferMm = 5.0,
  }) {
    if (contour.length < 3 ||
        vertexIndex < 0 ||
        vertexIndex >= contour.length) {
      return contour;
    }

    final n = contour.length;
    final prev = contour[(vertexIndex - 1 + n) % n];
    final curr = contour[vertexIndex];
    final next = contour[(vertexIndex + 1) % n];

    // Direction vectors pointing away from current vertex
    final dPrev = (prev - curr);
    final lenPrev = dPrev.length;
    final dNext = (next - curr);
    final lenNext = dNext.length;

    if (lenPrev < chamferMm || lenNext < chamferMm) return contour;

    final uPrev = CadPoint2D(dPrev.x / lenPrev, dPrev.y / lenPrev);
    final uNext = CadPoint2D(dNext.x / lenNext, dNext.y / lenNext);

    final cut1 = curr + (uPrev * chamferMm);
    final cut2 = curr + (uNext * chamferMm);

    final updated = <CadPoint2D>[];
    for (int i = 0; i < n; i++) {
      if (i == vertexIndex) {
        updated.add(cut1);
        updated.add(cut2);
      } else {
        updated.add(contour[i]);
      }
    }
    return updated;
  }

  /// Applies a rounded corner fillet with radius R to a specific vertex
  static List<CadPoint2D> applyCornerFillet({
    required List<CadPoint2D> contour,
    required int vertexIndex,
    double radiusMm = 5.0,
    int arcSegments = 6,
  }) {
    if (contour.length < 3 ||
        vertexIndex < 0 ||
        vertexIndex >= contour.length) {
      return contour;
    }

    final n = contour.length;
    final prev = contour[(vertexIndex - 1 + n) % n];
    final curr = contour[vertexIndex];
    final next = contour[(vertexIndex + 1) % n];

    final d1 = (prev - curr);
    final len1 = d1.length;
    final d2 = (next - curr);
    final len2 = d2.length;

    if (len1 < radiusMm || len2 < radiusMm) return contour;

    final u1 = CadPoint2D(d1.x / len1, d1.y / len1);
    final u2 = CadPoint2D(d2.x / len2, d2.y / len2);

    final pStart = curr + (u1 * radiusMm);
    final pEnd = curr + (u2 * radiusMm);

    // Generate smooth bezier arc points
    final arcPoints = <CadPoint2D>[];
    for (int i = 0; i <= arcSegments; i++) {
      final t = i / arcSegments;
      // Quadratic Bezier: (1-t)^2 * pStart + 2(1-t)t * curr + t^2 * pEnd
      final b0 = (1.0 - t) * (1.0 - t);
      final b1 = 2.0 * (1.0 - t) * t;
      final b2 = t * t;
      arcPoints.add(
        CadPoint2D(
          b0 * pStart.x + b1 * curr.x + b2 * pEnd.x,
          b0 * pStart.y + b1 * curr.y + b2 * pEnd.y,
        ),
      );
    }

    final updated = <CadPoint2D>[];
    for (int i = 0; i < n; i++) {
      if (i == vertexIndex) {
        updated.addAll(arcPoints);
      } else {
        updated.add(contour[i]);
      }
    }
    return updated;
  }

  static double _distToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y);
    if (l2 < 1e-4) return p.distanceTo(a);
    final t = math.max(
      0.0,
      math.min(
        1.0,
        ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2,
      ),
    );
    final proj = CadPoint2D(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
    return p.distanceTo(proj);
  }
}
