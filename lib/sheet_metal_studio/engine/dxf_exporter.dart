// =============================================================================
// dxf_exporter.dart
//
// Pure-Dart Industrial CAD/CAM DXF Exporter for truFold Studio by Danish.
// Generates standard AutoCAD Release 12 / 2000 compliant ASCII DXF files
// ready for CNC Laser, Plasma, Waterjet cutting and CNC Press Brake machines.
// Layers:
// - CUT (Color 7 - White): Outer blank boundary & contour
// - BEND_UP (Color 4 - Cyan): Positive press brake fold lines
// - BEND_DOWN (Color 2 - Yellow): Negative press brake fold lines
// - HOLES (Color 3 - Green): Tooling holes, obrounds, and slots
// - ANNOTATION (Color 5 - Blue): Bend angles, radii, and part metadata
// Designed with ZERO external dependencies for 100% standalone portability.
// =============================================================================

import '../models/cad_primitives.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/fold_bend_line.dart';
import '../models/dsf_document.dart';

class DxfExporter {
  /// Generates a complete standard AutoCAD ASCII DXF string from a [DsfDocument].
  static String exportDxf(DsfDocument doc) {
    final sb = StringBuffer();

    // 1. HEADER SECTION
    sb.writeln('0\nSECTION');
    sb.writeln('2\nHEADER');
    sb.writeln(
      '9\n\$ACADVER\n1\nAC1009',
    ); // AutoCAD Release 12 for universal CAM compatibility
    sb.writeln('9\n\$INSUNITS\n70\n4'); // 4 = Millimeters
    sb.writeln('0\nENDSEC');

    // 2. TABLES SECTION (Define all document layers with matching ACI colors)
    final layers = doc.effectiveLayers;
    sb.writeln('0\nSECTION');
    sb.writeln('2\nTABLES');
    sb.writeln('0\nTABLE');
    sb.writeln('2\nLAYER');
    sb.writeln('70\n${layers.length}');

    for (final layer in layers) {
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

    // 3D. Titleblock Metadata Text
    final infoY = -25.0;
    _writeText(
      sb,
      'PART: ${doc.partNumber} | ${doc.productTypeName} | THK: ${doc.material.thicknessMm}mm (${doc.material.name})',
      CadPoint2D(0.0, infoY),
      height: 4.5,
      layer: 'ANNOTATION',
    );
    _writeText(
      sb,
      'BLANK: ${doc.blankWidthMm.toStringAsFixed(1)}mm x ${doc.blankLengthMm.toStringAsFixed(1)}mm | truFold Studio by Danish',
      CadPoint2D(0.0, infoY - 8.0),
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
    sb.writeln('0\nPOLYLINE');
    sb.writeln('8\n$layer');
    sb.writeln('66\n1'); // Vertices follow
    sb.writeln('70\n${closed ? 1 : 0}'); // 1 = Closed polyline
    sb.writeln('10\n0.0\n20\n0.0\n30\n0.0');

    for (final pt in pts) {
      sb.writeln('0\nVERTEX');
      sb.writeln('8\n$layer');
      sb.writeln('10\n${_f(pt.x)}');
      sb.writeln('20\n${_f(pt.y)}');
      sb.writeln('30\n0.0');
    }

    sb.writeln('0\nSEQEND');
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
    sb.writeln('60\n${_f(arc.endAngleDeg)}');
  }

  static String _f(double val) {
    if (val.abs() < 1e-4) return '0.0';
    return val.toStringAsFixed(3);
  }
}
