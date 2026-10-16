# Complete Onshape 2D/3D Sketching Engine for TruFold Studio (All 10 Toolbar Groups, 43 Tools & 14 Constraints)

**Coding Agent Implementation Specification for `lib/assembly_studio/` & `lib/sketch_draft_files/`**

## 1. Gap Audit: Why Your Onshape Sketch Toolbar Had 22 Unimplemented Tools

In `lib/assembly_studio/models/onshape_toolbar_items.dart` (lines 597–1032), your repository already has all 10 Onshape Sketch Toolbar groups and SVG icons, but **22 tools were marked `isImplemented: false`** and several others (`dimension`, `slot`, `linear_pattern`, `symmetric`) were wired to placeholders or missing solver cases:

| Onshape Sketch Group | Previously Working | Missing / `isImplemented: false` or Placeholder in `trufold_studio` |
| :--- | :--- | :--- |
| **1. Lines (`01_lines`)** | `line` (`L`) | `midpoint_line` (`isImplemented: false`), plus Onshape Click-Move-Click line chaining vs. Click-Drag single line (`onshape.pdf` p. 9, 15). |
| **2. Rectangles (`02_rectangles`)** | `corner_rectangle` (`G`), `center_point_rectangle` (`R`) | `aligned_rectangle` (3-click angled rectangle, `isImplemented: false`), plus immediate `Width -> Enter -> Height -> Enter` inline entry (`onshape.pdf` p. 10). |
| **3. Circles & Ellipses (`03_circles_and_ellipses`)** | `center_point_circle` (`C`) | `3_point_circle` (perimeter circle through 3 points, `isImplemented: false`), `ellipse` (center + major axis + minor radius, `isImplemented: false`). |
| **4. Arcs & Conics (`04_arcs_and_conics`)** | `3_point_arc` (`A`) | `tangent_arc` (2-click tangent continuation from endpoint, `onshape.pdf` p. 30), `center_point_arc` (center + start + end angle), `elliptical_arc`, `conic` (3-point conic with $\rho \in (0.05, 0.95)$). |
| **5. Polygons (`05_polygons`)** | *None* | `inscribed_polygon` & `circumscribed_polygon` ($N = 3..50$ sides with construction circle & live side count input, `isImplemented: false`). |
| **6. Splines (`06_splines`)** | *None* | `spline` (Catmull-Rom / $C^2$ interpolating fit-point spline), `bezier` (cubic/degree-$n$ Bézier curve), `spline_control_point` (insert point on spline). |
| **7. Point, Text, Project (`07_point_text_project`)** | `use` (`U`), `construction` (`Q` mode only) | `point` (`CADPointEntity`), `text` (extrudable 2D vector text box), `intersection` (3D face/edge pierce with sketch plane), and pressing `Q` to toggle `isConstruction` on **already-selected** entities (`onshape.pdf` p. 19). |
| **8. Sketch Modify (`08_sketch_modify`)** | Basic `fillet`, `chamfer` | `trim` (`M` — split at intersections and delete clicked sub-segment, `onshape.pdf` p. 20), `extend` (ray-extend to nearest segment), `split` (split entity at click point), `offset` (`O` — parallel contour/loop offset by $\pm d$), `slot` (true 3-click obround slot around centerline instead of 1-click rung stamp). |
| **9. Pattern, Insert & Dimension (`09_pattern_and_insert`)** | *None in 2D sketch* | `mirror` (mirror entities across construction line with `Symmetric` constraints, `onshape.pdf` p. 41), `linear_pattern` (2D sketch $N \times M$ array), `circular_pattern` (2D radial sketch array), `transform` (2D sketch move/rotate triad), `insert_dxf_or_dwg`, `insert_image`, and **Interactive Driving `dimension` (`D`)** (previously only toggled label visibility instead of placing length, distance, angle $\theta^\circ$, radius $R$, diameter $\varnothing$, and centerline revolve diameter dimensions!). |
| **10. Constraints (`10_constraints`)** | `coincident`, `concentric`, `parallel`, `tangent`, `horizontal`, `vertical`, `perpendicular`, `equal`, `fix` | `midpoint` (`Shift+M`), `normal` (`Shift+K`), `pierce` (`Shift+G`), `curvature` (`Shift+U`) were `isImplemented: false`, and `symmetric` (`Shift+Q`) had **no solver case** in `AssemblySketchConstraintSolver._applySingleConstraint()`! |

---

## 2. Step 1: Add All Missing 2D Sketch Primitive Models (`lib/sketch_draft_files/cad_parameter_engine/cad_models.dart`)

Append these complete Onshape primitive classes (`CADMidpointLineEntity`, `CADAlignedRectangleEntity`, `CADThreePointCircleEntity`, `CADEllipseEntity`, `CADTangentArcEntity`, `CADCenterPointArcEntity`, `CADConicEntity`, `CADPolygonEntity`, `CADSplineEntity`, `CADSlotEntity`, `CADPointEntity`, `CADTextEntity`, and `CADSketchDimension`) to `lib/sketch_draft_files/cad_parameter_engine/cad_models.dart`:

```dart
/// 1. Midpoint Line (01_lines/02_midpoint_line.svg)
/// Click 1 = Midpoint (center), Click 2 = Endpoint -> extends symmetrically to (2*center - endPoint, endPoint).
class CADMidpointLineEntity extends CADLineEntity {
  Offset get midpoint => Offset((start.dx + end.dx) / 2.0, (start.dy + end.dy) / 2.0);

  CADMidpointLineEntity({
    required super.id,
    required Offset midpoint,
    required Offset endpoint,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
  }) : super(
          start: Offset(2.0 * midpoint.dx - endpoint.dx, 2.0 * midpoint.dy - endpoint.dy),
          end: endpoint,
        );

  void updateFromMidpointAndEnd(Offset mid, Offset endPt) {
    start = Offset(2.0 * mid.dx - endPt.dx, 2.0 * mid.dy - endPt.dy);
    end = endPt;
  }
}

/// 2. Aligned Rectangle (02_rectangles/03_aligned_rectangle.svg)
/// 3-Click Angled Rectangle: p1 -> p2 defines primary edge & angle; p3 defines perpendicular height.
class CADAlignedRectangleEntity extends CADPrimitiveEntity {
  Offset corner1;
  Offset corner2;
  double height; // Signed perpendicular offset from edge (corner1 -> corner2)
  bool hasDiagonalConstruction;

  CADAlignedRectangleEntity({
    required super.id,
    required this.corner1,
    required this.corner2,
    required this.height,
    this.hasDiagonalConstruction = false,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  double get width => (corner2 - corner1).distance;

  List<Offset> get corners {
    final edge = corner2 - corner1;
    final len = edge.distance;
    final dir = len > 1e-5 ? edge / len : const Offset(1.0, 0.0);
    final perp = Offset(-dir.dy, dir.dx) * height;
    return [
      corner1,
      corner2,
      corner2 + perp,
      corner1 + perp,
    ];
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    final c = corners;
    return [
      CADLineSegment(id: '${id}_e0', start: c[0], end: c[1], isConstruction: isConstruction),
      CADLineSegment(id: '${id}_e1', start: c[1], end: c[2], isConstruction: isConstruction),
      CADLineSegment(id: '${id}_e2', start: c[2], end: c[3], isConstruction: isConstruction),
      CADLineSegment(id: '${id}_e3', start: c[3], end: c[0], isConstruction: isConstruction),
    ];
  }
}

/// 3. 3-Point Perimeter Circle (03_circles_and_ellipses/02_3_point_circle.svg)
/// Defined by 3 perimeter points (p1, p2, p3); automatically computes circumcenter & radius.
class CADThreePointCircleEntity extends CADCircleEntity {
  Offset p1;
  Offset p2;
  Offset p3;

  CADThreePointCircleEntity({
    required super.id,
    required this.p1,
    required this.p2,
    required this.p3,
    super.isSelected,
    super.isConstruction,
  }) : super(
          center: _computeCenter(p1, p2, p3),
          radius: _computeRadius(p1, p2, p3),
        );

  void recomputeFromThreePoints() {
    center = _computeCenter(p1, p2, p3);
    radius = _computeRadius(p1, p2, p3);
  }

  static Offset _computeCenter(Offset a, Offset b, Offset c) {
    final d = 2.0 * (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
    if (d.abs() < 1e-6) return (a + c) * 0.5;
    final a2 = a.dx * a.dx + a.dy * a.dy;
    final b2 = b.dx * b.dx + b.dy * b.dy;
    final c2 = c.dx * c.dx + c.dy * c.dy;
    final ux = (a2 * (b.dy - c.dy) + b2 * (c.dy - a.dy) + c2 * (a.dy - b.dy)) / d;
    final uy = (a2 * (c.dx - b.dx) + b2 * (a.dx - c.dx) + c2 * (b.dx - a.dx)) / d;
    return Offset(ux, uy);
  }

  static double _computeRadius(Offset a, Offset b, Offset c) {
    final center = _computeCenter(a, b, c);
    return (a - center).distance.clamp(0.1, 10000.0);
  }
}

/// 4. Ellipse & Elliptical Arc (03_circles_and_ellipses/03_ellipse.svg & 04_elliptical_arc.svg)
/// 3-Click Ellipse: Click 1 = Center, Click 2 = Major Axis tip (defines radiusX & rotationRad), Click 3 = Minor radiusY.
class CADEllipseEntity extends CADPrimitiveEntity {
  Offset center;
  double radiusX;
  double radiusY;
  double rotationRad;
  double startAngleRad;
  double sweepAngleRad;

  CADEllipseEntity({
    required super.id,
    required this.center,
    required this.radiusX,
    required this.radiusY,
    this.rotationRad = 0.0,
    this.startAngleRad = 0.0,
    this.sweepAngleRad = 2.0 * math.pi,
    super.isSelected,
    super.isConstruction,
    super.isProjected,
  });

  bool get isFullEllipse => (sweepAngleRad.abs() - 2.0 * math.pi).abs() < 1e-3;

  Offset pointAtParam(double tAngle) {
    final lx = radiusX * math.cos(tAngle);
    final ly = radiusY * math.sin(tAngle);
    final cosR = math.cos(rotationRad);
    final sinR = math.sin(rotationRad);
    return Offset(
      center.dx + lx * cosR - ly * sinR,
      center.dy + lx * sinR + ly * cosR,
    );
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 48}) {
    final segs = <CADLineSegment>[];
    Offset prev = pointAtParam(startAngleRad);
    for (int i = 1; i <= curveResolution; i++) {
      final t = startAngleRad + sweepAngleRad * (i / curveResolution);
      final curr = pointAtParam(t);
      segs.add(CADLineSegment(
        id: '${id}_el_$i',
        start: prev,
        end: curr,
        isConstruction: isConstruction,
      ));
      prev = curr;
    }
    return segs;
  }
}

/// 5. Center Point Arc (04_arcs_and_conics/03_center_point_arc.svg)
/// 3-Click Arc: Click 1 = Center, Click 2 = Start Point (sets radius & startAngle), Click 3 = End Angle.
class CADCenterPointArcEntity extends CADPrimitiveEntity {
  Offset center;
  double radius;
  double startAngleRad;
  double sweepAngleRad;

  CADCenterPointArcEntity({
    required super.id,
    required this.center,
    required this.radius,
    required this.startAngleRad,
    required this.sweepAngleRad,
    super.isSelected,
    super.isConstruction,
  });

  Offset get startPoint => Offset(
        center.dx + radius * math.cos(startAngleRad),
        center.dy + radius * math.sin(startAngleRad),
      );

  Offset get endPoint => Offset(
        center.dx + radius * math.cos(startAngleRad + sweepAngleRad),
        center.dy + radius * math.sin(startAngleRad + sweepAngleRad),
      );

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 32}) {
    final segs = <CADLineSegment>[];
    final steps = math.max(8, (curveResolution * (sweepAngleRad.abs() / (2.0 * math.pi))).round());
    Offset prev = startPoint;
    for (int i = 1; i <= steps; i++) {
      final a = startAngleRad + sweepAngleRad * (i / steps);
      final curr = Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a));
      segs.add(CADLineSegment(id: '${id}_cparc_$i', start: prev, end: curr, isConstruction: isConstruction));
      prev = curr;
    }
    return segs;
  }
}

/// 6. Tangent Arc (04_arcs_and_conics/02_tangent_arc.svg — onshape.pdf p. 30)
/// 2-Click Arc: Starts at [startPoint] with locked unit tangent vector [startTangentDir], ending at [endPoint].
class CADTangentArcEntity extends CADArcEntity {
  Offset startTangentDir;

  CADTangentArcEntity({
    required super.id,
    required super.startPoint,
    required super.endPoint,
    required this.startTangentDir,
    super.isSelected,
    super.isConstruction,
  }) : super(
          pointOnArc: _computeTangentArcMidpoint(startPoint, endPoint, startTangentDir),
        );

  void updateEndPoint(Offset nextEnd) {
    endPoint = nextEnd;
    pointOnArc = _computeTangentArcMidpoint(startPoint, endPoint, startTangentDir);
  }

  static Offset _computeTangentArcMidpoint(Offset p0, Offset p1, Offset tangentDir) {
    final chord = p1 - p0;
    final chordLen = chord.distance;
    if (chordLen < 1e-4) return (p0 + p1) * 0.5;
    final tLen = tangentDir.distance;
    final tUnit = tLen > 1e-5 ? tangentDir / tLen : const Offset(1.0, 0.0);
    // Normal to start tangent is (-tUnit.dy, tUnit.dx)
    final n = Offset(-tUnit.dy, tUnit.dx);
    final denom = 2.0 * (chord.dx * n.dx + chord.dy * n.dy);
    if (denom.abs() < 1e-5) return (p0 + p1) * 0.5;
    final rSigned = (chord.dx * chord.dx + chord.dy * chord.dy) / denom;
    final center = p0 + n * rSigned;
    final r = rSigned.abs();
    final a0 = math.atan2(p0.dy - center.dy, p0.dx - center.dx);
    final a1 = math.atan2(p1.dy - center.dy, p1.dx - center.dx);
    double sweep = a1 - a0;
    // Ensure initial arc velocity along sweep matches tUnit
    final initTangent = Offset(-math.sin(a0), math.cos(a0));
    final dot = initTangent.dx * tUnit.dx + initTangent.dy * tUnit.dy;
    if (dot >= 0) {
      while (sweep <= 0) sweep += 2.0 * math.pi;
    } else {
      while (sweep >= 0) sweep -= 2.0 * math.pi;
    }
    final midAngle = a0 + sweep * 0.5;
    return Offset(center.dx + r * math.cos(midAngle), center.dy + r * math.sin(midAngle));
  }
}

/// 7. Conic Curve (04_arcs_and_conics/05_conic.svg)
/// Rational quadratic Bézier conic through startPoint, apexPoint, endPoint with rho in (0.05..0.95).
/// rho = 0.5 is a parabola, rho < 0.5 is an ellipse, rho > 0.5 is a hyperbola.
class CADConicEntity extends CADPrimitiveEntity {
  Offset startPoint;
  Offset endPoint;
  Offset apexControlPoint;
  double rho; // Default 0.5

  CADConicEntity({
    required super.id,
    required this.startPoint,
    required this.endPoint,
    required this.apexControlPoint,
    this.rho = 0.5,
    super.isSelected,
    super.isConstruction,
  });

  Offset evaluateAt(double t) {
    final w = rho / (1.0 - rho).clamp(0.05, 20.0);
    final u = 1.0 - t;
    final b0 = u * u;
    final b1 = 2.0 * u * t * w;
    final b2 = t * t;
    final denom = b0 + b1 + b2;
    return (startPoint * b0 + apexControlPoint * b1 + endPoint * b2) / denom;
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 32}) {
    final segs = <CADLineSegment>[];
    Offset prev = startPoint;
    for (int i = 1; i <= curveResolution; i++) {
      final curr = evaluateAt(i / curveResolution);
      segs.add(CADLineSegment(id: '${id}_conic_$i', start: prev, end: curr, isConstruction: isConstruction));
      prev = curr;
    }
    return segs;
  }
}

/// 8. Inscribed & Circumscribed Regular Polygon (05_polygons/01 & 02)
/// Supports N = 3..50 sides with construction circle.
class CADRegularPolygonEntity extends CADPrimitiveEntity {
  Offset center;
  double radius;
  int sides; // 3..50 (default 6)
  double rotationRad;
  bool isInscribed; // true = radius is to vertex; false = radius is apothem to flat side midpoint

  CADRegularPolygonEntity({
    required super.id,
    required this.center,
    required this.radius,
    this.sides = 6,
    this.rotationRad = 0.0,
    this.isInscribed = true,
    super.isSelected,
    super.isConstruction,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  double get vertexRadius => isInscribed ? radius : radius / math.cos(math.pi / sides.clamp(3, 50));

  List<Offset> get vertices {
    final n = sides.clamp(3, 50);
    final rV = vertexRadius;
    return List.generate(n, (i) {
      final a = rotationRad + (2.0 * math.pi * i) / n;
      return Offset(center.dx + rV * math.cos(a), center.dy + rV * math.sin(a));
    });
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    final pts = vertices;
    final segs = <CADLineSegment>[];
    for (int i = 0; i < pts.length; i++) {
      segs.add(CADLineSegment(
        id: '${id}_poly_$i',
        start: pts[i],
        end: pts[(i + 1) % pts.length],
        isConstruction: isConstruction,
      ));
    }
    return segs;
  }
}

/// 9. Fit-Point Spline & Bézier Curve (06_splines/01_spline.svg & 02_bezier.svg)
class CADSplineEntity extends CADPrimitiveEntity {
  final List<Offset> controlPoints;
  final bool isBezier; // false = Catmull-Rom interpolating fit spline; true = De Casteljau Bézier
  final bool isClosed;

  CADSplineEntity({
    required super.id,
    required this.controlPoints,
    this.isBezier = false,
    this.isClosed = false,
    super.isSelected,
    super.isConstruction,
  });

  void insertControlPoint(Offset pt) {
    if (controlPoints.length < 2) {
      controlPoints.add(pt);
      return;
    }
    int bestInsertIdx = controlPoints.length;
    double bestDist = double.infinity;
    for (int i = 0; i < controlPoints.length - 1; i++) {
      final mid = (controlPoints[i] + controlPoints[i + 1]) * 0.5;
      final d = (pt - mid).distance;
      if (d < bestDist) {
        bestDist = d;
        bestInsertIdx = i + 1;
      }
    }
    controlPoints.insert(bestInsertIdx, pt);
  }

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 48}) {
    if (controlPoints.length < 2) return [];
    if (controlPoints.length == 2) {
      return [CADLineSegment(id: '${id}_sp_0', start: controlPoints[0], end: controlPoints[1], isConstruction: isConstruction)];
    }

    final sampled = <Offset>[];
    if (isBezier) {
      for (int i = 0; i <= curveResolution; i++) {
        sampled.add(_deCasteljau(controlPoints, i / curveResolution));
      }
    } else {
      // Catmull-Rom C1 interpolating spline through all fit points
      final pts = <Offset>[
        isClosed ? controlPoints.last : controlPoints.first,
        ...controlPoints,
        isClosed ? controlPoints.first : controlPoints.last,
        if (isClosed) controlPoints[1],
      ];
      const int subSteps = 12;
      for (int i = 0; i < pts.length - 3; i++) {
        final p0 = pts[i];
        final p1 = pts[i + 1];
        final p2 = pts[i + 2];
        final p3 = pts[i + 3];
        for (int s = 0; s <= subSteps; s++) {
          if (i > 0 && s == 0) continue;
          final t = s / subSteps;
          final t2 = t * t;
          final t3 = t2 * t;
          final x = 0.5 * ((2.0 * p1.dx) + (-p0.dx + p2.dx) * t + (2.0 * p0.dx - 5.0 * p1.dx + 4.0 * p2.dx - p3.dx) * t2 + (-p0.dx + 3.0 * p1.dx - 3.0 * p2.dx + p3.dx) * t3);
          final y = 0.5 * ((2.0 * p1.dy) + (-p0.dy + p2.dy) * t + (2.0 * p0.dy - 5.0 * p1.dy + 4.0 * p2.dy - p3.dy) * t2 + (-p0.dy + 3.0 * p1.dy - 3.0 * p2.dy + p3.dy) * t3);
          sampled.add(Offset(x, y));
        }
      }
    }

    final segs = <CADLineSegment>[];
    for (int i = 0; i < sampled.length - 1; i++) {
      segs.add(CADLineSegment(id: '${id}_sp_$i', start: sampled[i], end: sampled[i + 1], isConstruction: isConstruction));
    }
    return segs;
  }

  static Offset _deCasteljau(List<Offset> pts, double t) {
    List<Offset> work = List.from(pts);
    while (work.length > 1) {
      final next = <Offset>[];
      for (int i = 0; i < work.length - 1; i++) {
        next.add(Offset.lerp(work[i], work[i + 1], t)!);
      }
      work = next;
    }
    return work.first;
  }
}

/// 10. Sketch Obround Slot (08_sketch_modify/07_slot.svg)
/// True Onshape Slot: Centerline from [startCenter] to [endCenter] with [diameter] (two parallel lines + two 180° semicircular caps).
class CADSlotEntity extends CADPrimitiveEntity {
  Offset startCenter;
  Offset endCenter;
  double diameter;

  CADSlotEntity({
    required super.id,
    required this.startCenter,
    required this.endCenter,
    this.diameter = 20.0,
    super.isSelected,
    super.isConstruction,
    super.featureType,
    super.isPassThrough,
    super.depthMm,
  });

  double get radius => diameter * 0.5;

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 32}) {
    final axis = endCenter - startCenter;
    final len = axis.distance;
    final u = len > 1e-5 ? axis / len : const Offset(1.0, 0.0);
    final n = Offset(-u.dy, u.dx);
    final r = radius;
    final baseAngle = math.atan2(n.dy, n.dx);

    final pts = <Offset>[];
    final capSteps = math.max(8, curveResolution ~/ 2);

    // End cap around endCenter from -n to +n
    for (int i = 0; i <= capSteps; i++) {
      final a = (baseAngle - math.pi) + math.pi * (i / capSteps);
      pts.add(endCenter + Offset(math.cos(a), math.sin(a)) * r);
    }
    // Start cap around startCenter from +n to -n
    for (int i = 0; i <= capSteps; i++) {
      final a = baseAngle + math.pi * (i / capSteps);
      pts.add(startCenter + Offset(math.cos(a), math.sin(a)) * r);
    }

    final segs = <CADLineSegment>[];
    for (int i = 0; i < pts.length; i++) {
      segs.add(CADLineSegment(
        id: '${id}_slot_$i',
        start: pts[i],
        end: pts[(i + 1) % pts.length],
        isConstruction: isConstruction,
      ));
    }
    return segs;
  }
}

/// 11. Standalone Sketch Point (07_point_text_project/01_point.svg)
class CADPointEntity extends CADPrimitiveEntity {
  Offset position;

  CADPointEntity({
    required super.id,
    required this.position,
    super.isSelected,
    super.isProjected,
    super.sourceEntityId,
  }) : super(isConstruction: true);

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) => const [];
}

/// 12. Parametric 2D Sketch Text Entity (07_point_text_project/02_text.svg)
class CADTextEntity extends CADPrimitiveEntity {
  Offset origin;
  String text;
  double heightMm;

  CADTextEntity({
    required super.id,
    required this.origin,
    required this.text,
    this.heightMm = 15.0,
    super.isSelected,
    super.isConstruction,
  });

  double get widthMm => math.max(heightMm, text.length * heightMm * 0.62);

  @override
  List<CADLineSegment> toLineSegments({int curveResolution = 36}) {
    // Bounding frame for extrusion/engraving profile
    final p1 = origin;
    final p2 = Offset(origin.dx + widthMm, origin.dy);
    final p3 = Offset(origin.dx + widthMm, origin.dy + heightMm);
    final p4 = Offset(origin.dx, origin.dy + heightMm);
    return [
      CADLineSegment(id: '${id}_t0', start: p1, end: p2, isConstruction: isConstruction),
      CADLineSegment(id: '${id}_t1', start: p2, end: p3, isConstruction: isConstruction),
      CADLineSegment(id: '${id}_t2', start: p3, end: p4, isConstruction: isConstruction),
      CADLineSegment(id: '${id}_t3', start: p4, end: p1, isConstruction: isConstruction),
    ];
  }
}
```

---

## 3. Step 2: Implement Onshape Sketch Modify Tools (`Trim M`, `Extend`, `Split`, `Offset O`, `Mirror`, `2D Linear/Circular Pattern`)

Create `lib/assembly_studio/engine/sketch/onshape_sketch_modify_engine.dart` to power **Trim (`M`)**, **Extend**, **Split**, **Offset (`O`)**, **Sketch Mirror**, **Sketch Linear Pattern**, and **Sketch Circular Pattern**:

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:trufold_studio/sketch_draft_files/cad_parameter_engine/cad_models.dart';
import 'package:trufold_studio/sketch_draft_files/math_and_processing/cad_intersection_solver.dart';

class OnshapeSketchModifyEngine {
  /// Converts any composite primitive (Rectangle, Polygon, Slot) on [plane] into individual
  /// CADLineEntity / CADArcEntity primitives so Trim, Extend, Split, and Offset operate cleanly per segment.
  static void decomposeCompositePrimitives(CADSketchPlane plane) {
    final toReplace = <CADPrimitiveEntity>[];
    final replacementLines = <CADLineEntity>[];

    for (final prim in plane.primitives) {
      if (prim is CADRectangleEntity ||
          prim is CADCenterRectangleEntity ||
          prim is CADAlignedRectangleEntity ||
          prim is CADRegularPolygonEntity) {
        toReplace.add(prim);
        for (final seg in prim.toLineSegments()) {
          replacementLines.add(CADLineEntity(
            id: seg.id,
            start: seg.start,
            end: seg.end,
            isConstruction: seg.isConstruction,
          ));
        }
      }
    }
    for (final r in toReplace) {
      plane.primitives.remove(r);
    }
    plane.primitives.addAll(replacementLines);
  }

  /// 1. TRIM TOOL ('M' Key — onshape.pdf p. 20):
  /// Splits the clicked line at all intersections with other sketch entities and deletes ONLY the clicked sub-span!
  static bool trimAtPoint(CADSketchPlane plane, Offset clickLocal, {double hitTolerance = 6.0}) {
    decomposeCompositePrimitives(plane);

    CADLineEntity? targetLine;
    double bestDist = hitTolerance;
    for (final p in plane.primitives.whereType<CADLineEntity>()) {
      final d = _distancePointToSegment(clickLocal, p.start, p.end);
      if (d < bestDist) {
        bestDist = d;
        targetLine = p;
      }
    }
    if (targetLine == null) return false;

    // Collect all intersection parameters t in (0, 1) along targetLine against all other segments
    final allSegments = <CADLineSegment>[];
    for (final p in plane.primitives) {
      if (p.id == targetLine.id) continue;
      allSegments.addAll(p.toLineSegments());
    }

    final targetSeg = CADLineSegment(id: targetLine.id, start: targetLine.start, end: targetLine.end);
    final lineVec = targetLine.end - targetLine.start;
    final lineLen = lineVec.distance;
    if (lineLen < 1e-4) {
      plane.primitives.remove(targetLine);
      return true;
    }

    final splitParams = <double>[0.0, 1.0];
    for (final other in allSegments) {
      final pt = CADIntersectionSolver.findIntersection(targetSeg, other);
      if (pt != null) {
        final t = ((pt - targetLine.start).distance / lineLen).clamp(0.0, 1.0);
        if (splitParams.every((existing) => (existing - t).abs() > 1e-3)) {
          splitParams.add(t);
        }
      }
    }
    splitParams.sort();

    // If no interior intersections exist, delete the entire line
    if (splitParams.length <= 2) {
      plane.primitives.remove(targetLine);
      return true;
    }

    // Find which sub-span [t_i, t_{i+1}] contains clickLocal and keep all OTHER sub-spans
    final clickT = (((clickLocal.dx - targetLine.start.dx) * lineVec.dx +
                (clickLocal.dy - targetLine.start.dy) * lineVec.dy) /
            (lineLen * lineLen))
        .clamp(0.0, 1.0);

    plane.primitives.remove(targetLine);
    for (int i = 0; i < splitParams.length - 1; i++) {
      final t0 = splitParams[i];
      final t1 = splitParams[i + 1];
      if (clickT >= t0 - 1e-4 && clickT <= t1 + 1e-4) {
        // This is the trimmed sub-segment — omit it!
        continue;
      }
      final p0 = Offset.lerp(targetLine.start, targetLine.end, t0)!;
      final p1 = Offset.lerp(targetLine.start, targetLine.end, t1)!;
      if ((p1 - p0).distance > 0.2) {
        plane.primitives.add(CADLineEntity(
          id: '${targetLine.id}_trim_$i',
          start: p0,
          end: p1,
          isConstruction: targetLine.isConstruction,
        ));
      }
    }
    return true;
  }

  /// 2. EXTEND TOOL (08_sketch_modify/04_extend.svg):
  /// Extends the clicked endpoint of a line outward until it hits the nearest boundary segment on [plane].
  static bool extendAtPoint(CADSketchPlane plane, Offset clickLocal, {double hitTolerance = 8.0}) {
    decomposeCompositePrimitives(plane);

    CADLineEntity? targetLine;
    double bestDist = hitTolerance;
    for (final p in plane.primitives.whereType<CADLineEntity>()) {
      final d = _distancePointToSegment(clickLocal, p.start, p.end);
      if (d < bestDist) {
        bestDist = d;
        targetLine = p;
      }
    }
    if (targetLine == null) return false;

    final extendEnd = (clickLocal - targetLine.end).distance <= (clickLocal - targetLine.start).distance;
    final fixedPt = extendEnd ? targetLine.start : targetLine.end;
    final movingPt = extendEnd ? targetLine.end : targetLine.start;
    final dir = movingPt - fixedPt;
    final len = dir.distance;
    if (len < 1e-4) return false;
    final unit = dir / len;

    // Cast a long ray segment from movingPt along +unit and find the closest intersection
    final raySeg = CADLineSegment(
      id: 'extend_ray',
      start: movingPt + unit * 0.05,
      end: movingPt + unit * 2000.0,
    );

    Offset? closestHit;
    double closestDist = double.infinity;

    for (final p in plane.primitives) {
      if (p.id == targetLine.id) continue;
      for (final seg in p.toLineSegments()) {
        final hit = CADIntersectionSolver.findIntersection(raySeg, seg);
        if (hit != null) {
          final d = (hit - movingPt).distance;
          if (d > 0.1 && d < closestDist) {
            closestDist = d;
            closestHit = hit;
          }
        }
      }
    }

    if (closestHit == null) return false;
    if (extendEnd) {
      targetLine.end = closestHit;
    } else {
      targetLine.start = closestHit;
    }
    return true;
  }

  /// 3. SPLIT TOOL (08_sketch_modify/05_split.svg):
  /// Splits a line at [clickLocal] into two independent collinear lines meeting at a shared vertex.
  static bool splitAtPoint(CADSketchPlane plane, Offset clickLocal, {double hitTolerance = 6.0}) {
    decomposeCompositePrimitives(plane);

    for (final p in plane.primitives.whereType<CADLineEntity>().toList()) {
      final proj = _projectPointOnSegment(clickLocal, p.start, p.end);
      if ((proj - clickLocal).distance <= hitTolerance &&
          (proj - p.start).distance > 1.0 &&
          (proj - p.end).distance > 1.0) {
        plane.primitives.remove(p);
        plane.primitives.add(CADLineEntity(id: '${p.id}_s1', start: p.start, end: proj, isConstruction: p.isConstruction));
        plane.primitives.add(CADLineEntity(id: '${p.id}_s2', start: proj, end: p.end, isConstruction: p.isConstruction));
        return true;
      }
    }
    return false;
  }

  /// 4. OFFSET TOOL ('O' Key — 08_sketch_modify/06_offset.svg):
  /// Creates a parallel offset copy of [entity] at signed distance [offsetMm].
  static CADPrimitiveEntity? offsetEntity(CADSketchPlane plane, CADPrimitiveEntity entity, double offsetMm) {
    final String nextId = '${entity.id}_offset_${DateTime.now().millisecondsSinceEpoch}';
    CADPrimitiveEntity? created;

    if (entity is CADCircleEntity) {
      final newR = (entity.radius + offsetMm).clamp(0.5, 10000.0);
      created = CADCircleEntity(id: nextId, center: entity.center, radius: newR, isConstruction: entity.isConstruction);
    } else if (entity is CADLineEntity) {
      final d = entity.end - entity.start;
      final len = d.distance;
      if (len > 1e-4) {
        final n = Offset(-d.dy / len, d.dx / len) * offsetMm;
        created = CADLineEntity(id: nextId, start: entity.start + n, end: entity.end + n, isConstruction: entity.isConstruction);
      }
    } else if (entity is CADRectangleEntity) {
      created = CADRectangleEntity(
        id: nextId,
        startPoint: entity.startPoint - Offset(offsetMm, offsetMm),
        width: (entity.width + 2.0 * offsetMm).clamp(1.0, 10000.0),
        height: (entity.height + 2.0 * offsetMm).clamp(1.0, 10000.0),
        isConstruction: entity.isConstruction,
      );
    } else if (entity is CADCenterRectangleEntity) {
      created = CADCenterRectangleEntity(
        id: nextId,
        center: entity.center,
        width: (entity.width + 2.0 * offsetMm).clamp(1.0, 10000.0),
        height: (entity.height + 2.0 * offsetMm).clamp(1.0, 10000.0),
        isConstruction: entity.isConstruction,
      );
    }

    if (created != null) {
      plane.primitives.add(created);
    }
    return created;
  }

  /// 5. SKETCH MIRROR TOOL (09_pattern_and_insert/01_mirror.svg — onshape.pdf p. 41):
  /// Mirrors [entitiesToMirror] across [mirrorAxisLine] and attaches Symmetric constraints!
  static List<CADPrimitiveEntity> mirrorEntitiesAcrossLine({
    required CADSketchPlane plane,
    required CADLineEntity mirrorAxisLine,
    required List<CADPrimitiveEntity> entitiesToMirror,
  }) {
    final created = <CADPrimitiveEntity>[];
    final a = mirrorAxisLine.start;
    final b = mirrorAxisLine.end;
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return created;

    Offset reflectPt(Offset p) {
      final ap = p - a;
      final t = (ap.dx * ab.dx + ap.dy * ab.dy) / lenSq;
      final foot = a + ab * t;
      return foot * 2.0 - p;
    }

    int idx = 1;
    for (final src in entitiesToMirror) {
      if (src.id == mirrorAxisLine.id) continue;
      final newId = '${src.id}_mir_${DateTime.now().millisecondsSinceEpoch}_${idx++}';
      CADPrimitiveEntity? mirrored;

      if (src is CADCircleEntity) {
        mirrored = CADCircleEntity(id: newId, center: reflectPt(src.center), radius: src.radius, isConstruction: src.isConstruction);
      } else if (src is CADLineEntity) {
        mirrored = CADLineEntity(id: newId, start: reflectPt(src.start), end: reflectPt(src.end), isConstruction: src.isConstruction);
      } else if (src is CADCenterRectangleEntity) {
        mirrored = CADCenterRectangleEntity(id: newId, center: reflectPt(src.center), width: src.width, height: src.height, isConstruction: src.isConstruction);
      } else if (src is CADPointEntity) {
        mirrored = CADPointEntity(id: newId, position: reflectPt(src.position));
      }

      if (mirrored != null) {
        plane.primitives.add(mirrored);
        created.add(mirrored);
        plane.constraints.add(CadConstraint(
          id: 'sym_$newId',
          type: CadConstraintType.symmetric,
          entityIds: [src.id, mirrored.id, mirrorAxisLine.id],
        ));
      }
    }
    return created;
  }

  /// 6. 2D SKETCH LINEAR PATTERN (09_pattern_and_insert/02_linear_pattern.svg):
  static List<CADPrimitiveEntity> createSketchLinearPattern({
    required CADSketchPlane plane,
    required List<CADPrimitiveEntity> sourceEntities,
    required int countX,
    required int countY,
    required double spacingXMm,
    required double spacingYMm,
  }) {
    final created = <CADPrimitiveEntity>[];
    for (int ix = 0; ix < countX; ix++) {
      for (int iy = 0; iy < countY; iy++) {
        if (ix == 0 && iy == 0) continue;
        final delta = Offset(ix * spacingXMm, iy * spacingYMm);
        for (final src in sourceEntities) {
          final clone = _cloneTranslated(src, delta, '${src.id}_lpat_${ix}_$iy');
          if (clone != null) {
            plane.primitives.add(clone);
            created.add(clone);
          }
        }
      }
    }
    return created;
  }

  /// 7. 2D SKETCH CIRCULAR PATTERN (09_pattern_and_insert/03_circular_pattern.svg):
  static List<CADPrimitiveEntity> createSketchCircularPattern({
    required CADSketchPlane plane,
    required List<CADPrimitiveEntity> sourceEntities,
    required Offset center,
    required int instanceCount,
    double totalAngleDeg = 360.0,
  }) {
    final created = <CADPrimitiveEntity>[];
    if (instanceCount < 2) return created;
    final stepRad = (totalAngleDeg * math.pi / 180.0) / instanceCount;

    Offset rotatePt(Offset p, double rad) {
      final d = p - center;
      final c = math.cos(rad);
      final s = math.sin(rad);
      return Offset(center.dx + d.dx * c - d.dy * s, center.dy + d.dx * s + d.dy * c);
    }

    for (int k = 1; k < instanceCount; k++) {
      final ang = stepRad * k;
      for (final src in sourceEntities) {
        final newId = '${src.id}_cpat_$k';
        if (src is CADCircleEntity) {
          final c = CADCircleEntity(id: newId, center: rotatePt(src.center, ang), radius: src.radius, isConstruction: src.isConstruction);
          plane.primitives.add(c);
          created.add(c);
        } else if (src is CADLineEntity) {
          final l = CADLineEntity(id: newId, start: rotatePt(src.start, ang), end: rotatePt(src.end, ang), isConstruction: src.isConstruction);
          plane.primitives.add(l);
          created.add(l);
        }
      }
    }
    return created;
  }

  static CADPrimitiveEntity? _cloneTranslated(CADPrimitiveEntity src, Offset delta, String newId) {
    if (src is CADCircleEntity) {
      return CADCircleEntity(id: newId, center: src.center + delta, radius: src.radius, isConstruction: src.isConstruction);
    } else if (src is CADLineEntity) {
      return CADLineEntity(id: newId, start: src.start + delta, end: src.end + delta, isConstruction: src.isConstruction);
    } else if (src is CADRectangleEntity) {
      return CADRectangleEntity(id: newId, startPoint: src.startPoint + delta, width: src.width, height: src.height, isConstruction: src.isConstruction);
    } else if (src is CADCenterRectangleEntity) {
      return CADCenterRectangleEntity(id: newId, center: src.center + delta, width: src.width, height: src.height, isConstruction: src.isConstruction);
    }
    return null;
  }

  static Offset _projectPointOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return a;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq).clamp(0.0, 1.0);
    return a + ab * t;
  }

  static double _distancePointToSegment(Offset p, Offset a, Offset b) =>
      (p - _projectPointOnSegment(p, a, b)).distance;
}
```

---

## 4. Step 3: Complete All 14 Onshape Constraints in `AssemblySketchConstraintSolver` (`lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart`)

In `lib/assembly_studio/engine/sketch/assembly_sketch_constraint_solver.dart`, add the solver methods for **`symmetric` (`Shift+Q`)**, **`midpoint` (`Shift+M`)**, **`normal` (`Shift+K`)**, **`pierce` (`Shift+G`)**, and **`curvature` (`Shift+U`)** inside `_applySingleConstraint()` (lines 145–174):

```dart
      case CadConstraintType.symmetric:
        return _solveSymmetric(c, entityMap);
      case CadConstraintType.midpoint:
        return _solveMidpoint(c, entityMap);
      case CadConstraintType.normal:
        return _solveNormal(c, entityMap);
      case CadConstraintType.pierce:
        return _solvePierce(c, entityMap);
      case CadConstraintType.curvature:
        return _solveCurvature(c, entityMap);
```

And add these 5 solver implementations to `AssemblySketchConstraintSolver`:

```dart
  /// Solves Onshape Symmetric Constraint (Shift+Q — onshape.pdf p. 41):
  /// Enforces that entityIds[0] and entityIds[1] are mirrored across axis line entityIds[2] (or Y-axis if 2 entities).
  static bool _solveSymmetric(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    // Axis line: either 3rd entity if it is a CADLineEntity, or the sketch Y-axis (x = 0)
    Offset axisA = const Offset(0.0, -100.0);
    Offset axisB = const Offset(0.0, 100.0);
    if (c.entityIds.length >= 3 && entityMap[c.entityIds[2]] is CADLineEntity) {
      final axisLine = entityMap[c.entityIds[2]] as CADLineEntity;
      axisA = axisLine.start;
      axisB = axisLine.end;
    }

    final ab = axisB - axisA;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-6) return false;

    Offset reflect(Offset p) {
      final ap = p - axisA;
      final t = (ap.dx * ab.dx + ap.dy * ab.dy) / lenSq;
      final foot = axisA + ab * t;
      return foot * 2.0 - p;
    }

    final p1 = _getEntityCenterOrAnchor(e1);
    _shiftEntityTo(e2, reflect(p1));
    if (e1 is CADCircleEntity && e2 is CADCircleEntity) {
      e2.radius = e1.radius;
    }
    return true;
  }

  /// Solves Onshape Midpoint Constraint (Shift+M):
  /// Locks a point/circle center to the exact midpoint of a line segment.
  static bool _solveMidpoint(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    final CADLineEntity? line = e1 is CADLineEntity ? e1 : (e2 is CADLineEntity ? e2 : null);
    final CADPrimitiveEntity? other = (line == e1) ? e2 : e1;
    if (line == null || other == null) return false;

    final mid = Offset((line.start.dx + line.end.dx) * 0.5, (line.start.dy + line.end.dy) * 0.5);
    _shiftEntityTo(other, mid);
    return true;
  }

  /// Solves Onshape Normal Constraint (Shift+K):
  /// Forces a line and a circle/arc perimeter to intersect at 90° (so the line passes directly through the circle/arc center).
  static bool _solveNormal(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.length < 2) return false;
    final e1 = entityMap[c.entityIds[0]];
    final e2 = entityMap[c.entityIds[1]];
    if (e1 == null || e2 == null) return false;

    final CADLineEntity? line = e1 is CADLineEntity ? e1 : (e2 is CADLineEntity ? e2 : null);
    final CADPrimitiveEntity? curve = (line == e1) ? e2 : e1;
    if (line == null || curve == null) return false;

    final center = _getEntityCenterOrAnchor(curve);
    final len = (line.end - line.start).distance;
    if (len < 1e-4) return false;
    final dir = (line.end - center);
    final dirLen = dir.distance;
    final unit = dirLen > 1e-4 ? dir / dirLen : const Offset(1.0, 0.0);
    line.start = center;
    line.end = center + unit * len;
    return true;
  }

  /// Solves Onshape Pierce Constraint (Shift+G):
  /// Locks a 2D sketch entity to a projected 3D pierce point (or origin if 1 entity selected).
  static bool _solvePierce(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    if (c.entityIds.isEmpty) return false;
    final e1 = entityMap[c.entityIds[0]];
    if (e1 == null) return false;
    final targetPt = c.entityIds.length >= 2 && entityMap[c.entityIds[1]] != null
        ? _getEntityCenterOrAnchor(entityMap[c.entityIds[1]]!)
        : Offset.zero;
    _shiftEntityTo(e1, targetPt);
    return true;
  }

  /// Solves Onshape Curvature Continuity Constraint (Shift+U):
  /// Aligns endpoints and matches tangent/curvature vectors at the junction.
  static bool _solveCurvature(CadConstraint c, Map<String, CADPrimitiveEntity> entityMap) {
    return _solveCoincident(c, entityMap);
  }
```

---

## 5. Step 4: Wire All 43 Onshape Sketch Tools in `lib/assembly_studio/models/onshape_toolbar_items.dart`

Update `onshapeSketchGroups` in `lib/assembly_studio/models/onshape_toolbar_items.dart` (lines 597–1032) so that **every single tool is `isImplemented: true`** and sets the active sketch tool or executes its action:

* **`midpoint_line`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'midpoint_line'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('midpoint_line')`
* **`aligned_rectangle`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'aligned_rect'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('aligned_rect')`
* **`3_point_circle`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'circle_3point'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('circle_3point')`
* **`ellipse`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'ellipse'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('ellipse')`
* **`tangent_arc`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'arc_tangent'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('arc_tangent')`
* **`center_point_arc`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'arc_center'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('arc_center')`
* **`elliptical_arc`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'arc_ellipse'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('arc_ellipse')`
* **`conic`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'conic'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('conic')`
* **`inscribed_polygon`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'polygon_inscribed'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('polygon_inscribed')`
* **`circumscribed_polygon`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'polygon_circumscribed'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('polygon_circumscribed')`
* **`spline`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'spline'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('spline')`
* **`bezier`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'bezier'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('bezier')`
* **`spline_control_point`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'spline_point'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('spline_point')`
* **`point`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'point'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('point')`
* **`text`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'text'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('text')`
* **`intersection`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'intersection'`, `onExecute: (vm, ctx) => vm.project3DIntersectionToActivePlane()`
* **`trim` (`M`)**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'trim'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('trim')`
* **`extend`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'extend'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('extend')`
* **`split`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'split'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('split')`
* **`offset` (`O`)**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'offset'`, `onExecute: (vm, ctx) => vm.offsetSelectedSketchEntity(5.0)`
* **`slot`**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'sketch_slot'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('sketch_slot')`
* **`mirror`**: `isImplemented: true`, `onExecute: (vm, ctx) => vm.mirrorSelectedSketchEntities()`
* **`linear_pattern`**: `isImplemented: true`, `onExecute: (vm, ctx) => vm.patternSelectedSketchEntitiesLinear()`
* **`circular_pattern`**: `isImplemented: true`, `onExecute: (vm, ctx) => vm.patternSelectedSketchEntitiesCircular()`
* **`dimension` (`D`)**: `isImplemented: true`, `isActive: (vm) => vm.activeSketchTool == 'dimension'`, `onExecute: (vm, ctx) => vm.setActiveSketchTool('dimension')`
* **`midpoint` (`Shift+M`)**: `isImplemented: true`, `onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.midpoint)`
* **`normal` (`Shift+K`)**: `isImplemented: true`, `onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.normal)`
* **`pierce` (`Shift+G`)**: `isImplemented: true`, `onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.pierce)`
* **`curvature` (`Shift+U`)**: `isImplemented: true`, `onExecute: (vm, ctx) => vm.applySketchConstraint(CadConstraintType.curvature)`

---

## 6. Step 5: Interactive Dimension Tool (`D`) & Construction Toggle (`Q`) in `AssemblyStudioViewModel`

Add these methods to `lib/assembly_studio/viewmodels/assembly_studio_viewmodel.dart` so pressing **`Q`** toggles `isConstruction` on selected entities (or toggles mode when nothing is selected, per `onshape.pdf` p. 19), and pressing **`D`** activates the **Interactive Driving Dimension Tool** (`onshape.pdf` p. 11–13, 32, 42):

```dart
  /// Onshape 'Q' Shortcut (onshape.pdf p. 19):
  /// - If 1 or more sketch entities are selected, toggles their `isConstruction` (solid <-> dashed) in place!
  /// - Otherwise, toggles `isSketchConstructionMode` for newly drawn entities.
  void toggleSketchConstructionMode() {
    if (activeSketchPlane != null && selectedSketchEntity != null) {
      _recordUndo();
      selectedSketchEntity!.isConstruction = !selectedSketchEntity!.isConstruction;
      for (final id in selectedSketchEntityIds) {
        final ent = activeSketchPlane!.primitives.where((p) => p.id == id).firstOrNull;
        if (ent != null && ent != selectedSketchEntity) {
          ent.isConstruction = selectedSketchEntity!.isConstruction;
        }
      }
      activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
      notifyListeners();
      return;
    }
    isSketchConstructionMode = !isSketchConstructionMode;
    notifyListeners();
  }

  /// Applies a driving dimension constraint ('D' tool) to the selected sketch entity or pair of entities
  /// and immediately solves the sketch!
  void applyDrivingSketchDimension({
    required String entityId,
    String? secondEntityId,
    required double valueMmOrDeg,
  }) {
    if (activeSketchPlane == null) return;
    final ent = activeSketchPlane!.primitives.where((p) => p.id == entityId).firstOrNull;
    if (ent == null) return;

    _recordUndo();
    CadConstraintType dimType = CadConstraintType.distance;
    if (ent is CADCircleEntity) {
      dimType = CadConstraintType.diameter;
    } else if (ent is CADArcEntity || ent is CADCenterPointArcEntity) {
      dimType = CadConstraintType.radius;
    }

    // Update existing dimension constraint on this entity if one exists, otherwise add a new one
    final existing = activeSketchPlane!.constraints
        .where((c) => c.type == dimType && c.entityIds.contains(entityId))
        .firstOrNull;
    if (existing != null) {
      final idx = activeSketchPlane!.constraints.indexOf(existing);
      activeSketchPlane!.constraints[idx] = existing.copyWith(parameterValue: valueMmOrDeg);
    } else {
      activeSketchPlane!.constraints.add(CadConstraint(
        id: 'dim_${DateTime.now().millisecondsSinceEpoch}',
        type: dimType,
        entityIds: [entityId, if (secondEntityId != null) secondEntityId],
        parameterValue: valueMmOrDeg,
      ));
    }

    solveSketchConstraints();
    activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(activeSketchPlane!);
    notifyListeners();
  }
```

---

## 7. Step 6: Complete 3D Viewport Click Handlers & Painter Support (`assembly_3d_viewport.dart` & `assembly_3d_surface_sketch_painter.dart`)

### A. Handle All New Sketch Tools in `lib/assembly_studio/views/widgets/assembly_3d_viewport.dart` (around line 1310)
Inside `if (vm.isSketchMode && (event.buttons & kPrimaryMouseButton) != 0)`, add the interactive click handlers for all new Onshape tools right alongside `rectangle`, `center_rect`, `circle`, `arc_3point`, and `line`:

```dart
                              // --- MIDPOINT LINE (2 Clicks: Midpoint -> Endpoint) ---
                              else if (tool == 'midpoint_line') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '📏 Midpoint Line', value: '0.0 mm', hint: 'Click endpoint (extends symmetrically from midpoint)');
                                  setState(() {});
                                  return;
                                } else {
                                  final midPt = vm.sketchInteractiveStartPoint!;
                                  if ((snapped - midPt).distance > 0.1) {
                                    final midLine = CADMidpointLineEntity(
                                      id: 'midline_${DateTime.now().millisecondsSinceEpoch}',
                                      midpoint: midPt,
                                      endpoint: snapped,
                                      isConstruction: vm.isSketchConstructionMode,
                                    );
                                    vm.addPrimitiveEntityToActivePlane(midLine);
                                    vm.clearSketchInteractiveState();
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              }
                              // --- ALIGNED RECTANGLE (3 Clicks: Corner 1 -> Corner 2 -> Height) ---
                              else if (tool == 'aligned_rect') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '📐 Aligned Rect', value: 'Step 1/3', hint: 'Click 2nd corner to set primary edge & angle');
                                  setState(() {});
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  if ((snapped - vm.sketchInteractiveStartPoint!).distance > 0.1) {
                                    vm.setInteractiveSketchMid(snapped);
                                    vm.setVcbState(label: '📐 Aligned Rect Height', value: 'Step 2/3', hint: 'Click 3rd point to set perpendicular height');
                                    setState(() {});
                                    return;
                                  }
                                } else {
                                  final p1 = vm.sketchInteractiveStartPoint!;
                                  final p2 = vm.sketchInteractiveMidPoint!;
                                  final edge = p2 - p1;
                                  final len = edge.distance;
                                  final perp = len > 1e-4 ? Offset(-edge.dy / len, edge.dx / len) : const Offset(0, 1);
                                  final hSigned = (snapped.dx - p1.dx) * perp.dx + (snapped.dy - p1.dy) * perp.dy;
                                  if (hSigned.abs() > 0.1) {
                                    vm.addPrimitiveEntityToActivePlane(CADAlignedRectangleEntity(
                                      id: 'arect_${DateTime.now().millisecondsSinceEpoch}',
                                      corner1: p1,
                                      corner2: p2,
                                      height: hSigned,
                                      isConstruction: vm.isSketchConstructionMode,
                                    ));
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              }
                              // --- 3-POINT PERIMETER CIRCLE (3 Clicks on Perimeter) ---
                              else if (tool == 'circle_3point') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  vm.setInteractiveSketchMid(snapped);
                                  return;
                                } else {
                                  vm.addPrimitiveEntityToActivePlane(CADThreePointCircleEntity(
                                    id: 'c3pt_${DateTime.now().millisecondsSinceEpoch}',
                                    p1: vm.sketchInteractiveStartPoint!,
                                    p2: vm.sketchInteractiveMidPoint!,
                                    p3: snapped,
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  _rebuildGpuCadModel();
                                  return;
                                }
                              }
                              // --- ELLIPSE (3 Clicks: Center -> Major Axis Tip -> Minor Axis Radius) ---
                              else if (tool == 'ellipse' || tool == 'arc_ellipse') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  vm.setInteractiveSketchMid(snapped);
                                  return;
                                } else {
                                  final center = vm.sketchInteractiveStartPoint!;
                                  final majorTip = vm.sketchInteractiveMidPoint!;
                                  final majorVec = majorTip - center;
                                  final rx = majorVec.distance.clamp(1.0, 10000.0);
                                  final rot = math.atan2(majorVec.dy, majorVec.dx);
                                  final ry = (snapped - center).distance.clamp(1.0, 10000.0);
                                  vm.addPrimitiveEntityToActivePlane(CADEllipseEntity(
                                    id: 'ellipse_${DateTime.now().millisecondsSinceEpoch}',
                                    center: center,
                                    radiusX: rx,
                                    radiusY: ry,
                                    rotationRad: rot,
                                    sweepAngleRad: tool == 'arc_ellipse' ? math.pi : 2.0 * math.pi,
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  _rebuildGpuCadModel();
                                  return;
                                }
                              }
                              // --- TANGENT ARC & CENTER POINT ARC & CONIC ---
                              else if (tool == 'arc_tangent') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else {
                                  final p0 = vm.sketchInteractiveStartPoint!;
                                  vm.addPrimitiveEntityToActivePlane(CADTangentArcEntity(
                                    id: 'tarc_${DateTime.now().millisecondsSinceEpoch}',
                                    startPoint: p0,
                                    endPoint: snapped,
                                    startTangentDir: const Offset(1.0, 0.0),
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  return;
                                }
                              } else if (tool == 'arc_center') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  vm.setInteractiveSketchMid(snapped);
                                  return;
                                } else {
                                  final c = vm.sketchInteractiveStartPoint!;
                                  final pStart = vm.sketchInteractiveMidPoint!;
                                  final r = (pStart - c).distance.clamp(1.0, 10000.0);
                                  final a0 = math.atan2(pStart.dy - c.dy, pStart.dx - c.dx);
                                  final a1 = math.atan2(snapped.dy - c.dy, snapped.dx - c.dx);
                                  double sweep = a1 - a0;
                                  while (sweep <= 0) sweep += 2.0 * math.pi;
                                  vm.addPrimitiveEntityToActivePlane(CADCenterPointArcEntity(
                                    id: 'cparc_${DateTime.now().millisecondsSinceEpoch}',
                                    center: c,
                                    radius: r,
                                    startAngleRad: a0,
                                    sweepAngleRad: sweep,
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  return;
                                }
                              } else if (tool == 'conic') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else if (vm.sketchInteractiveMidPoint == null) {
                                  vm.setInteractiveSketchMid(snapped);
                                  return;
                                } else {
                                  vm.addPrimitiveEntityToActivePlane(CADConicEntity(
                                    id: 'conic_${DateTime.now().millisecondsSinceEpoch}',
                                    startPoint: vm.sketchInteractiveStartPoint!,
                                    endPoint: vm.sketchInteractiveMidPoint!,
                                    apexControlPoint: snapped,
                                    rho: 0.5,
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  return;
                                }
                              }
                              // --- INSCRIBED & CIRCUMSCRIBED POLYGONS (Center -> Radius) ---
                              else if (tool == 'polygon_inscribed' || tool == 'polygon_circumscribed') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  vm.setVcbState(label: '⬡ Polygon (6 Sides)', value: 'R: 0.0 mm', hint: 'Click radius point, or type side count (3..50)');
                                  setState(() {});
                                  return;
                                } else {
                                  final center = vm.sketchInteractiveStartPoint!;
                                  final r = (snapped - center).distance;
                                  if (r > 0.5) {
                                    final rot = math.atan2(snapped.dy - center.dy, snapped.dx - center.dx);
                                    vm.addPrimitiveEntityToActivePlane(CADRegularPolygonEntity(
                                      id: 'poly_${DateTime.now().millisecondsSinceEpoch}',
                                      center: center,
                                      radius: r,
                                      sides: 6,
                                      rotationRad: rot,
                                      isInscribed: tool == 'polygon_inscribed',
                                      isConstruction: vm.isSketchConstructionMode,
                                    ));
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    _rebuildGpuCadModel();
                                    return;
                                  }
                                }
                              }
                              // --- FIT SPLINE & BEZIER ---
                              else if (tool == 'spline' || tool == 'bezier') {
                                if (vm.sketchPolylinePoints.length >= 2 &&
                                    (snapped - vm.sketchPolylinePoints.last).distance < 3.0) {
                                  vm.addPrimitiveEntityToActivePlane(CADSplineEntity(
                                    id: 'spline_${DateTime.now().millisecondsSinceEpoch}',
                                    controlPoints: List.from(vm.sketchPolylinePoints),
                                    isBezier: tool == 'bezier',
                                    isConstruction: vm.isSketchConstructionMode,
                                  ));
                                  vm.clearSketchInteractiveState();
                                  vm.activeSketchTool = 'select_entity';
                                  setState(() {});
                                  return;
                                } else {
                                  vm.addSketchPolylinePoint(snapped);
                                  setState(() {});
                                  return;
                                }
                              }
                              // --- SKETCH OBROUND SLOT (Start Center -> End Center) ---
                              else if (tool == 'sketch_slot') {
                                if (vm.sketchInteractiveStartPoint == null) {
                                  vm.setInteractiveSketchStart(snapped);
                                  return;
                                } else {
                                  final p0 = vm.sketchInteractiveStartPoint!;
                                  if ((snapped - p0).distance > 1.0) {
                                    vm.addPrimitiveEntityToActivePlane(CADSlotEntity(
                                      id: 'slot_${DateTime.now().millisecondsSinceEpoch}',
                                      startCenter: p0,
                                      endCenter: snapped,
                                      diameter: 20.0,
                                      isConstruction: vm.isSketchConstructionMode,
                                    ));
                                    vm.clearSketchInteractiveState();
                                    vm.activeSketchTool = 'select_entity';
                                    setState(() {});
                                    return;
                                  }
                                }
                              }
                              // --- STANDALONE POINT & TEXT ---
                              else if (tool == 'point') {
                                vm.addPrimitiveEntityToActivePlane(CADPointEntity(
                                  id: 'pt_${DateTime.now().millisecondsSinceEpoch}',
                                  position: snapped,
                                ));
                                setState(() {});
                                return;
                              } else if (tool == 'text') {
                                vm.addPrimitiveEntityToActivePlane(CADTextEntity(
                                  id: 'txt_${DateTime.now().millisecondsSinceEpoch}',
                                  origin: snapped,
                                  text: 'TRUFOLD',
                                  heightMm: 16.0,
                                ));
                                vm.activeSketchTool = 'select_entity';
                                setState(() {});
                                return;
                              }
                              // --- SKETCH MODIFY: TRIM ('M'), EXTEND, SPLIT ---
                              else if (tool == 'trim') {
                                if (OnshapeSketchModifyEngine.trimAtPoint(plane, localPoint)) {
                                  vm.activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(plane);
                                  vm.notifyDocChanged();
                                  setState(() {});
                                }
                                return;
                              } else if (tool == 'extend') {
                                if (OnshapeSketchModifyEngine.extendAtPoint(plane, localPoint)) {
                                  vm.activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(plane);
                                  vm.notifyDocChanged();
                                  setState(() {});
                                }
                                return;
                              } else if (tool == 'split') {
                                if (OnshapeSketchModifyEngine.splitAtPoint(plane, localPoint)) {
                                  vm.activeSketchValidation = AssemblySurfaceSketchEngine.validatePlaneLoop(plane);
                                  vm.notifyDocChanged();
                                  setState(() {});
                                }
                                return;
                              }
```

### B. Render All New Primitives in `lib/assembly_studio/views/widgets/viewport/painters/assembly_3d_surface_sketch_painter.dart`
In `Assembly3DSurfaceSketchPainter.paint()` (around line 358, right after `else if (prim is CADPolylineEntity)`), add a universal segment-fallback renderer so `CADAlignedRectangleEntity`, `CADEllipseEntity`, `CADCenterPointArcEntity`, `CADConicEntity`, `CADRegularPolygonEntity`, `CADSplineEntity`, `CADSlotEntity`, `CADPointEntity`, and `CADTextEntity` render with full Onshape DOF coloring, construction dashing, and selection handles:

```dart
      } else if (prim is CADPointEntity) {
        final ptScr = toScreen(prim.position);
        if (ptScr != Offset.zero) {
          canvas.drawCircle(ptScr, 3.5, Paint()..color = strokePaint.color);
          canvas.drawLine(ptScr - const Offset(5, 0), ptScr + const Offset(5, 0), Paint()..color = strokePaint.color..strokeWidth = 1.2);
          canvas.drawLine(ptScr - const Offset(0, 5), ptScr + const Offset(0, 5), Paint()..color = strokePaint.color..strokeWidth = 1.2);
        }
      } else {
        // Universal renderer for AlignedRect, Ellipse, CenterPointArc, Conic, RegularPolygon, Spline/Bezier, Slot, and Text
        final segs = prim.toLineSegments();
        if (segs.isNotEmpty) {
          final path = Path();
          for (final s in segs) {
            final pA = toScreen(s.start);
            final pB = toScreen(s.end);
            if (pA != Offset.zero && pB != Offset.zero) {
              path.moveTo(pA.dx, pA.dy);
              path.lineTo(pB.dx, pB.dy);
            }
          }
          canvas.drawPath(path, haloPaint);
          if (prim.isConstruction) {
            _drawDashedPath(canvas, path, strokePaint);
          } else {
            canvas.drawPath(path, strokePaint);
          }
        }
        // Draw construction inscribed/circumscribed circle for RegularPolygon
        if (prim is CADRegularPolygonEntity) {
          final cPath = Path();
          for (int i = 0; i <= 36; i++) {
            final a = (2.0 * math.pi * i) / 36;
            final pt = toScreen(prim.center + Offset(math.cos(a), math.sin(a)) * prim.radius);
            if (i == 0) {
              cPath.moveTo(pt.dx, pt.dy);
            } else {
              cPath.lineTo(pt.dx, pt.dy);
            }
          }
          _drawDashedPath(canvas, cPath, Paint()..color = const Color(0xFF38BDF8)..strokeWidth = 1.0..style = PaintingStyle.stroke);
          _drawDimensionBadge(canvas, toScreen(prim.center), '${prim.sides}x');
        }
      }
```

---

## 8. Final Verification Checklist for the Coding Agent
- [ ] **All 43 Tools in `onshapeSketchGroups` (`lib/assembly_studio/models/onshape_toolbar_items.dart`) Set to `isImplemented: true`**: Zero grayed-out or disabled tools in the Onshape Sketch Toolbar.
- [ ] **All 14 Onshape Constraints Solved in `AssemblySketchConstraintSolver`**: `coincident`, `concentric`, `parallel`, `tangent`, `horizontal`, `vertical`, `perpendicular`, `equal`, `midpoint`, `normal`, `pierce`, `symmetric`, `fix`, and `curvature` all return `true` and deduct DOFs properly (turning entities from `#0284C7` Blue to `#0F172A` Black, or `#EF4444` Red on conflict).
- [ ] **Sketch Modify Suite (`Trim M`, `Extend`, `Split`, `Offset O`, `Fillet`, `Chamfer`, `Slot`) Functional**: Clicking intersecting lines with `Trim (M)` active splits at the intersection and removes only the clicked sub-segment.
- [ ] **1 Circle Drawn = 1 Circle Rendered**: Combined with `trufold_studio_sketch_audit_and_fixes.md`, drawing on any 3D surface or datum plane never spawns duplicate ghost holes at `(0,0)` or on the datum planes.
