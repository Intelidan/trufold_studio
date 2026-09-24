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
import '../models/trunking_cover_data.dart';
import 'covers/trunking_cover_generator.dart';
import 'associative_dimension_engine.dart';

/// Scope selector for DXF file generation when an accessory has an attached cover.
enum DxfExportScope {
  /// Export only the base workpiece blank.
  baseOnly,

  /// Export only the cover workpiece blank.
  coverOnly,

  /// Export both the base and cover side-by-side in a single DXF file for nesting.
  bothSideBySide;

  String get label {
    switch (this) {
      case DxfExportScope.baseOnly:
        return 'Base Only';
      case DxfExportScope.coverOnly:
        return 'Cover Only';
      case DxfExportScope.bothSideBySide:
        return 'Base + Cover (Side-by-Side)';
    }
  }
}

class DxfExporter {
  /// Generates a complete standard AutoCAD ASCII DXF string from a [DsfDocument].
  static String exportDxf(DsfDocument doc) =>
      exportBaseAndCoverDxf(doc, scope: DxfExportScope.baseOnly);

  /// Generates an AutoCAD ASCII DXF string supporting Base only, Cover only,
  /// or both Base and Cover positioned side-by-side in a single drawing.
  static String exportBaseAndCoverDxf(
    DsfDocument doc, {
    DxfExportScope scope = DxfExportScope.bothSideBySide,
  }) {
    if (doc.cover == null || scope == DxfExportScope.baseOnly) {
      return _exportSingleDoc(doc, partLabel: doc.cover != null ? 'BASE' : null);
    }

    if (scope == DxfExportScope.coverOnly) {
      return _exportSingleDoc(doc.cover!.document, partLabel: 'COVER');
    }

    return _exportCombinedDxf(doc, doc.cover!);
  }

  static String _exportSingleDoc(DsfDocument doc, {String? partLabel}) {
    final sb = StringBuffer();
    final bounds = _computeDocBounds(doc);
    final extMinX = bounds.hasBounds ? bounds.minX : 0.0;
    final extMinY = bounds.hasBounds ? bounds.minY : 0.0;
    final extMaxX = bounds.hasBounds ? bounds.maxX : 100.0;
    final extMaxY = bounds.hasBounds ? bounds.maxY : 100.0;

    _writeHeaderSection(sb, extMinX, extMinY, extMaxX, extMaxY);
    _writeTablesSection(sb, doc.effectiveLayers);

    sb.writeln('0\nSECTION');
    sb.writeln('2\nENTITIES');

    _writeDocEntities(sb, doc, offset: const CadPoint2D(0, 0), partLabel: partLabel);

    sb.writeln('0\nENDSEC');
    sb.writeln('0\nEOF');

    return sb.toString();
  }

  static String _exportCombinedDxf(DsfDocument baseDoc, TrunkingCoverData coverData) {
    final sb = StringBuffer();
    final coverDoc = coverData.document;

    // Determine 2D offset for cover. If snapped or overlapping (0,0), compute default side-by-side offset
    var offset = coverData.offset2D;
    if (offset.x.abs() < 1.0 && offset.y.abs() < 1.0) {
      offset = TrunkingCoverGenerator.computeDefaultBesideOffset(baseDoc, coverDoc);
    }

    final baseBounds = _computeDocBounds(baseDoc);
    final coverBounds = _computeDocBounds(coverDoc);

    final extMinX = math.min(baseBounds.minX, coverBounds.minX + offset.x);
    final extMaxX = math.max(baseBounds.maxX, coverBounds.maxX + offset.x);
    final extMinY = math.min(baseBounds.minY, coverBounds.minY + offset.y);
    final extMaxY = math.max(baseBounds.maxY, coverBounds.maxY + offset.y);

    _writeHeaderSection(sb, extMinX, extMinY, extMaxX, extMaxY);

    // Merge layers from both documents
    final allLayers = <DsfLayer>[
      ...baseDoc.effectiveLayers,
      ...coverDoc.effectiveLayers,
    ];
    _writeTablesSection(sb, allLayers);

    sb.writeln('0\nSECTION');
    sb.writeln('2\nENTITIES');

    // 1. Export Base entities
    _writeDocEntities(sb, baseDoc, offset: const CadPoint2D(0, 0), partLabel: 'BASE');

    // 2. Export Cover entities (translated by offset)
    _writeDocEntities(sb, coverDoc, offset: offset, partLabel: 'COVER');

    sb.writeln('0\nENDSEC');
    sb.writeln('0\nEOF');

    return sb.toString();
  }

  static void _writeHeaderSection(
    StringBuffer sb,
    double extMinX,
    double extMinY,
    double extMaxX,
    double extMaxY,
  ) {
    sb.writeln('0\nSECTION');
    sb.writeln('2\nHEADER');
    sb.writeln('9\n\$ACADVER\n1\nAC1009'); // AutoCAD Release 12 for universal CAM compatibility
    sb.writeln('9\n\$MEASUREMENT\n70\n1'); // 1 = Metric (millimeters)
    sb.writeln('9\n\$INSUNITS\n70\n4'); // 4 = Millimeters
    sb.writeln('9\n\$EXTMIN\n10\n${_f(extMinX)}\n20\n${_f(extMinY)}\n30\n0.0');
    sb.writeln('9\n\$EXTMAX\n10\n${_f(extMaxX)}\n20\n${_f(extMaxY)}\n30\n0.0');
    sb.writeln('0\nENDSEC');
  }

  static void _writeTablesSection(StringBuffer sb, Iterable<DsfLayer> layers) {
    final registeredLayers = <String, DsfLayer>{};
    for (final layer in layers) {
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
  }

  static void _writeDocEntities(
    StringBuffer sb,
    DsfDocument doc, {
    CadPoint2D offset = const CadPoint2D(0, 0),
    String? partLabel,
  }) {
    final ox = offset.x;
    final oy = offset.y;
    final hasOffset = ox.abs() > 1e-4 || oy.abs() > 1e-4;

    CadPoint2D tx(CadPoint2D p) => hasOffset ? CadPoint2D(p.x + ox, p.y + oy) : p;

    // 3A. Outer Contour
    final outerLayer = doc.outerContourLayer.isNotEmpty ? doc.outerContourLayer : 'CUT';
    if (doc.outerContour.length >= 3) {
      final contour = hasOffset ? doc.outerContour.map(tx).toList() : doc.outerContour;
      _writePolyline(sb, contour, layer: outerLayer, closed: true);
    } else if (doc.faces.isNotEmpty) {
      for (final face in doc.faces) {
        if (face.vertices.length >= 3) {
          final verts = hasOffset ? face.vertices.map(tx).toList() : face.vertices;
          _writePolyline(sb, verts, layer: outerLayer, closed: true);
        }
      }
    }

    // 3B. Press Brake Bend Lines
    for (final bend in doc.bends) {
      final bendLayer = bend.layer.isNotEmpty
          ? bend.layer
          : (bend.direction == BendDirection.up ? 'BEND_UP' : 'BEND_DOWN');
      final p1 = tx(bend.p1);
      final p2 = tx(bend.p2);
      _writeLine(sb, p1, p2, layer: bendLayer);

      // Bend annotation text (e.g. "UP 90.0° R1.5")
      final midX = (p1.x + p2.x) / 2.0;
      final midY = (p1.y + p2.y) / 2.0;
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
      final center = tx(punch.center);
      if (punch.type == PunchType.roundHole) {
        _writeCircle(
          sb,
          center,
          punch.diameterMm / 2.0,
          layer: punchLayer,
        );
      } else {
        final poly = punch.toPolygon();
        if (poly.isNotEmpty) {
          final translated = hasOffset ? poly.map(tx).toList() : poly;
          _writePolyline(sb, translated, layer: punchLayer, closed: true);
        }
      }
    }

    // 3C-2. Laser Cut Lines & Slits
    for (final cut in doc.cutLines) {
      _writeLine(
        sb,
        tx(cut.p1),
        tx(cut.p2),
        layer: cut.layer.isNotEmpty ? cut.layer : 'CUT',
      );
    }

    // 3C-3. Arcs
    for (final arc in doc.arcs) {
      final arcLayer = arc.layer.isNotEmpty ? arc.layer : outerLayer;
      _writeArc(sb, arc, layer: arcLayer, offset: offset);
    }

    // 3D. Persistent Dimensions
    for (final dim in doc.dimensions) {
      if (!dim.isVisible) continue;
      final assoc = AssociativeDimensionEngine.resolveAssociation(dim, doc);
      final pA = tx(assoc.pA);
      final pB = tx(assoc.pB);
      final offsetDist = dim.dimensionLineOffset;

      final dx = pB.x - pA.x;
      final dy = pB.y - pA.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 0.1) continue;

      final nx = -dy / len * offsetDist;
      final ny = dx / len * offsetDist;

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

    // 3E. Titleblock Metadata Text
    final bbox = _computeDocBounds(doc);
    final titleX = bbox.hasBounds ? (bbox.minX + ox) : ox;
    final titleY = bbox.hasBounds ? (bbox.minY + oy - 15.0) : (oy - 25.0);
    final partTag = partLabel != null ? ' ($partLabel)' : '';
    final partNum = doc.partNumber.isNotEmpty ? doc.partNumber : doc.itemName;

    _writeText(
      sb,
      'PART: $partNum$partTag | ${doc.productTypeName} | THK: ${doc.material.thicknessMm}mm (${doc.material.name})',
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
  }

  static ({bool hasBounds, double minX, double maxX, double minY, double maxY}) _computeDocBounds(
      DsfDocument doc) {
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

    return (
      hasBounds: hasBounds,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
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
    CadPoint2D offset = const CadPoint2D(0, 0),
  }) {
    final cx = arc.center.x + offset.x;
    final cy = arc.center.y + offset.y;
    sb.writeln('0\nARC');
    sb.writeln('8\n$layer');
    sb.writeln('10\n${_f(cx)}');
    sb.writeln('20\n${_f(cy)}');
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
