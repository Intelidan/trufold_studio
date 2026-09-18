// =============================================================================
// dxf_exporter.dart
//
// Pure-Dart Industrial CAD/CAM DXF Exporter for truFold Studio by Danish.
// Generates standard AutoCAD Release 12 / 2000 compliant ASCII DXF files
// ready for CNC Laser, Plasma, Waterjet cutting and CNC Press Brake machines.
// Layers:
// - CUT / OUTLINE (Color 7 - White): Outer blank boundary & contour
// - BEND_UP (Color 4 - Cyan): Positive press brake fold lines
// - BEND_DOWN (Color 2 - Yellow): Negative press brake fold lines
// - HOLES (Color 3 - Green): Tooling holes, obrounds, and slots
// - ANNOTATION (Color 5 - Blue): Bend angles, radii, dimensions, and metadata
// Designed with ZERO external dependencies for 100% standalone portability.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/fold_bend_line.dart';
import '../models/dsf_document.dart';
import '../models/dsf_layer.dart';
import 'associative_dimension_engine.dart';

class DxfExporter {
  /// Generates a complete standard AutoCAD ASCII DXF string from a [DsfDocument].
  static String exportDxf(DsfDocument doc) {
    final sb = StringBuffer();

    // Compute true bounding box of the entire workpiece to avoid text/geometry collisions
    double minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
    bool hasBounds = false;

    void updateBounds(double x, double y) {
      if (!hasBounds) {
        minX = maxX = x;
        minY = maxY = y;
        hasBounds = true;
      } else {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    for (final p in doc.outerContour) {
      updateBounds(p.x, p.y);
    }
    for (final b in doc.bends) {
      updateBounds(b.p1.x, b.p1.y);
      updateBounds(b.p2.x, b.p2.y);
    }
    for (final c in doc.cutLines) {
      updateBounds(c.p1.x, c.p1.y);
      updateBounds(c.p2.x, c.p2.y);
    }
    for (final a in doc.arcs) {
      updateBounds(a.center.x - a.radius, a.center.y - a.radius);
      updateBounds(a.center.x + a.radius, a.center.y + a.radius);
    }
    for (final p in doc.allPunches) {
      updateBounds(p.center.x - 10.0, p.center.y - 10.0);
      updateBounds(p.center.x + 10.0, p.center.y + 10.0);
    }
    for (final f in doc.faces) {
      for (final v in f.vertices) {
        updateBounds(v.x, v.y);
      }
    }

    final extMinX = hasBounds ? minX : 0.0;
    final extMinY = hasBounds ? minY : 0.0;
    final extMaxX = hasBounds ? maxX : 100.0;
    final extMaxY = hasBounds ? maxY : 100.0;

    // 1. HEADER SECTION
    sb.writeln('0\nSECTION');
    sb.writeln('2\nHEADER');
    sb.writeln('9\n\$ACADVER\n1\nAC1009'); // AutoCAD Release 12 for universal CAM compatibility
    sb.writeln('9\n\$MEASUREMENT\n70\n1'); // 1 = Metric (millimeters)
    sb.writeln('9\n\$INSUNITS\n70\n4'); // 4 = Millimeters
    sb.writeln('9\n\$EXTMIN\n10\n${_f(extMinX)}\n20\n${_f(extMinY)}\n30\n0.0');
    sb.writeln('9\n\$EXTMAX\n10\n${_f(extMaxX)}\n20\n${_f(extMaxY)}\n30\n0.0');
    sb.writeln('0\nENDSEC');

    // 2. TABLES SECTION (Define all document layers with matching ACI colors)
    final registeredLayers = <String, DsfLayer>{};
    for (final layer in doc.effectiveLayers) {
      registeredLayers[layer.name.toUpperCase()] = layer;
    }

    void ensureLayer(String name, int colorHex, [String lineType = 'CONTINUOUS']) {
      final up = name.toUpperCase();
      if (!registeredLayers.containsKey(up)) {
        registeredLayers[up] = DsfLayer(name: name, colorHex: colorHex, lineType: lineType);
      }
    }

    ensureLayer('CUT', 0xFFFFFFFF);
    ensureLayer('OUTLINE', 0xFF0F172A);
    ensureLayer('BEND_UP', 0xFF00FFFF, 'DASHED');
    ensureLayer('BEND_DOWN', 0xFFFFFF00, 'DASHED');
    ensureLayer('HOLES', 0xFF00FF00);
    ensureLayer('ANNOTATION', 0xFF0000FF);

    sb.writeln('0\nSECTION');
    sb.writeln('2\nTABLES');
    sb.writeln('0\nTABLE');
    sb.writeln('2\nLAYER');
    sb.writeln('70\n${registeredLayers.length}');

    for (final layer in registeredLayers.values) {
      _writeLayerDef(
        sb,
        layer.name,
        _colorHexToAci(layer.colorHex),
        layer.lineType,
      );
    }

    sb.writeln('0\nENDTAB');
    sb.writeln('0\nENDSEC');

    // 3. ENTITIES SECTION
    sb.writeln('0\nSECTION');
    sb.writeln('2\nENTITIES');

    // 3A. Outer Contour
    final outerLayer = doc.outerContourLayer.isNotEmpty
        ? doc.outerContourLayer
        : 'CUT';
    if (doc.outerContour.length >= 3) {
      _writePolyline(sb, doc.outerContour, layer: outerLayer, closed: true);
    } else if (doc.faces.isNotEmpty) {
      // Fallback: Export face perimeter polygons if outerContour was omitted
      for (final face in doc.faces) {
        if (face.vertices.length >= 3) {
          _writePolyline(sb, face.vertices, layer: outerLayer, closed: true);
        }
      }
    }

    // 3B. Press Brake Bend Lines
    for (final bend in doc.bends) {
      final bendLayer = bend.layer.isNotEmpty
          ? bend.layer
          : (bend.direction == BendDirection.up ? 'BEND_UP' : 'BEND_DOWN');
      _writeLine(sb, bend.p1, bend.p2, layer: bendLayer);

      // Bend annotation text (e.g. "UP 90.0° R1.5")
      final midX = (bend.p1.x + bend.p2.x) / 2.0;
      final midY = (bend.p1.y + bend.p2.y) / 2.0;
      final dirLabel = bend.direction == BendDirection.up ? 'UP' : 'DN';
      final text =
          '$dirLabel ${bend.targetAngleDeg.toStringAsFixed(1)}° R${bend.radiusMm.toStringAsFixed(1)}';
      _writeText(
        sb,
        text,
        CadPoint2D(midX + 2.0, midY + 2.0),
        height: 3.5,
        layer: 'ANNOTATION',
      );
    }

    // 3C. Punches & Perforations
    for (final punch in doc.allPunches) {
      final punchLayer = punch.layer.isNotEmpty ? punch.layer : 'HOLES';
      if (punch.type == PunchType.roundHole) {
        _writeCircle(
          sb,
          punch.center,
          punch.diameterMm / 2.0,
          layer: punchLayer,
        );
      } else {
        final poly = punch.toPolygon();
        if (poly.isNotEmpty) {
          _writePolyline(sb, poly, layer: punchLayer, closed: true);
        }
      }
    }

    // 3C-2. Laser Cut Lines & Slits
    for (final cut in doc.cutLines) {
      _writeLine(
        sb,
        cut.p1,
        cut.p2,
        layer: cut.layer.isNotEmpty ? cut.layer : 'CUT',
      );
    }

    // 3C-3. Arcs
    for (final arc in doc.arcs) {
      final arcLayer = arc.layer.isNotEmpty ? arc.layer : outerLayer;
      _writeArc(sb, arc, layer: arcLayer);
    }

    // 3D. Persistent Dimensions
    for (final dim in doc.dimensions) {
      if (!dim.isVisible) continue;
      final assoc = AssociativeDimensionEngine.resolveAssociation(dim, doc);
      final pA = assoc.pA;
      final pB = assoc.pB;
      final offset = dim.dimensionLineOffset;

      final dx = pB.x - pA.x;
      final dy = pB.y - pA.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 0.1) continue;

      final nx = -dy / len * offset;
      final ny = dx / len * offset;

      final dimA = CadPoint2D(pA.x + nx, pA.y + ny);
      final dimB = CadPoint2D(pB.x + nx, pB.y + ny);

      // Extension witness lines
      _writeLine(sb, pA, CadPoint2D(dimA.x + nx * 0.15, dimA.y + ny * 0.15), layer: 'ANNOTATION');
      _writeLine(sb, pB, CadPoint2D(dimB.x + nx * 0.15, dimB.y + ny * 0.15), layer: 'ANNOTATION');

      // Main dimension line
      _writeLine(sb, dimA, dimB, layer: 'ANNOTATION');

      // Measurement tag
      final midX = (dimA.x + dimB.x) / 2.0;
      final midY = (dimA.y + dimB.y) / 2.0;
      _writeText(sb, dim.displayedText, CadPoint2D(midX + 2.0, midY + 2.0), height: 3.0, layer: 'ANNOTATION');
    }

    // 3E. Titleblock Metadata Text (Safely placed strictly below part boundary)
    final titleX = hasBounds ? minX : 0.0;
    final titleY = hasBounds ? (minY - 15.0) : -25.0;

    _writeText(
      sb,
      'PART: ${doc.partNumber} | ${doc.productTypeName} | THK: ${doc.material.thicknessMm}mm (${doc.material.name})',
      CadPoint2D(titleX, titleY),
      height: 4.5,
      layer: 'ANNOTATION',
    );
    _writeText(
      sb,
      'BLANK: ${doc.blankWidthMm.toStringAsFixed(1)}mm x ${doc.blankLengthMm.toStringAsFixed(1)}mm | truFold Studio by Danish',
      CadPoint2D(titleX, titleY - 8.0),
      height: 3.5,
      layer: 'ANNOTATION',
    );

    sb.writeln('0\nENDSEC');
    sb.writeln('0\nEOF');

    return sb.toString();
  }

  static int _colorHexToAci(int colorHex) {
    final r = (colorHex >> 16) & 0xFF;
    final g = (colorHex >> 8) & 0xFF;
    final b = colorHex & 0xFF;

    if (r > 180 && g < 100 && b < 100) return 1; // Red
    if (r > 180 && g > 180 && b < 100) return 2; // Yellow
    if (r < 100 && g > 150 && b < 100) return 3; // Green
    if (r < 100 && g > 120 && b > 180) return 4; // Cyan
    if (r < 100 && g < 100 && b > 180) return 5; // Blue
    if (r > 180 && g < 100 && b > 180) return 6; // Magenta
    return 7; // White / Black (Default)
  }

  static void _writeLayerDef(
    StringBuffer sb,
    String name,
    int colorIndex, [
    String lineType = 'CONTINUOUS',
  ]) {
    sb.writeln('0\nLAYER');
    sb.writeln('2\n$name');
    sb.writeln('70\n0');
    sb.writeln('62\n$colorIndex');
    sb.writeln('6\n$lineType');
  }

  static void _writeLine(
    StringBuffer sb,
    CadPoint2D p1,
    CadPoint2D p2, {
    required String layer,
  }) {
    sb.writeln('0\nLINE');
    sb.writeln('8\n$layer');
    sb.writeln('10\n${_f(p1.x)}');
    sb.writeln('20\n${_f(p1.y)}');
    sb.writeln('30\n0.0');
    sb.writeln('11\n${_f(p2.x)}');
    sb.writeln('21\n${_f(p2.y)}');
    sb.writeln('31\n0.0');
  }

  static void _writeCircle(
    StringBuffer sb,
    CadPoint2D center,
    double radius, {
    required String layer,
  }) {
    sb.writeln('0\nCIRCLE');
    sb.writeln('8\n$layer');
    sb.writeln('10\n${_f(center.x)}');
    sb.writeln('20\n${_f(center.y)}');
    sb.writeln('30\n0.0');
    sb.writeln('40\n${_f(radius)}');
  }

  static void _writePolyline(
    StringBuffer sb,
    List<CadPoint2D> pts, {
    required String layer,
    bool closed = true,
  }) {
    if (pts.isEmpty) return;

    // Sanitize points: remove duplicate consecutive points
    final cleanPts = <CadPoint2D>[pts.first];
    for (int i = 1; i < pts.length; i++) {
      if (pts[i].distanceTo(cleanPts.last) >= 1e-4) {
        cleanPts.add(pts[i]);
      }
    }

    // If closed and last point is identical to first, drop redundant last point to prevent 0-length seam edge
    if (closed && cleanPts.length >= 2 && cleanPts.first.distanceTo(cleanPts.last) < 1e-4) {
      cleanPts.removeLast();
    }

    if (cleanPts.length < 2) return;

    sb.writeln('0\nPOLYLINE');
    sb.writeln('8\n$layer');
    sb.writeln('66\n1'); // Vertices follow
    sb.writeln('70\n${closed ? 1 : 0}'); // 1 = Closed polyline
    sb.writeln('10\n0.0\n20\n0.0\n30\n0.0');

    for (final pt in cleanPts) {
      sb.writeln('0\nVERTEX');
      sb.writeln('8\n$layer');
      sb.writeln('10\n${_f(pt.x)}');
      sb.writeln('20\n${_f(pt.y)}');
      sb.writeln('30\n0.0');
    }

    sb.writeln('0\nSEQEND');
    sb.writeln('8\n$layer');
  }

  static void _writeText(
    StringBuffer sb,
    String text,
    CadPoint2D pos, {
    double height = 3.0,
    required String layer,
  }) {
    sb.writeln('0\nTEXT');
    sb.writeln('8\n$layer');
    sb.writeln('10\n${_f(pos.x)}');
    sb.writeln('20\n${_f(pos.y)}');
    sb.writeln('30\n0.0');
    sb.writeln('40\n${_f(height)}');
    sb.writeln('1\n$text');
  }

  static void _writeArc(
    StringBuffer sb,
    CadArc2D arc, {
    required String layer,
  }) {
    sb.writeln('0\nARC');
    sb.writeln('8\n$layer');
    sb.writeln('10\n${_f(arc.center.x)}');
    sb.writeln('20\n${_f(arc.center.y)}');
    sb.writeln('30\n0.0');
    sb.writeln('40\n${_f(arc.radius)}');
    sb.writeln('50\n${_f(arc.startAngleDeg)}');
    sb.writeln('51\n${_f(arc.endAngleDeg)}'); // Group 51 is End Angle in standard DXF spec! (Group 60 was entity visibility)
  }

  static String _f(double val) {
    if (val.abs() < 1e-4) return '0.0';
    return val.toStringAsFixed(3);
  }
}
