// =============================================================================
// dxf_mini_parser.dart
//
// Standalone, zero-dependency ASCII DXF entity parser for Sheet Metal Studio.
// Parses LINE, ARC, CIRCLE, LWPOLYLINE, and TEXT entities with layer and color.
// =============================================================================

import 'dart:convert';
import '../models/cad_primitives.dart';

/// Raw 2D entity parsed from a DXF file
abstract class DxfRawEntity {
  final String layer;
  final int colorIndex;

  const DxfRawEntity({this.layer = '0', this.colorIndex = 7});
}

class DxfRawLine extends DxfRawEntity {
  final CadPoint2D p1;
  final CadPoint2D p2;

  const DxfRawLine({
    required this.p1,
    required this.p2,
    super.layer,
    super.colorIndex,
  });

  double get length => p1.distanceTo(p2);
}

class DxfRawCircle extends DxfRawEntity {
  final CadPoint2D center;
  final double radius;

  const DxfRawCircle({
    required this.center,
    required this.radius,
    super.layer,
    super.colorIndex,
  });
}

class DxfRawArc extends DxfRawEntity {
  final CadPoint2D center;
  final double radius;
  final double startAngleDeg;
  final double endAngleDeg;

  const DxfRawArc({
    required this.center,
    required this.radius,
    required this.startAngleDeg,
    required this.endAngleDeg,
    super.layer,
    super.colorIndex,
  });
}

class DxfRawPolyline extends DxfRawEntity {
  final List<CadPoint2D> vertices;
  final bool isClosed;

  const DxfRawPolyline({
    required this.vertices,
    this.isClosed = false,
    super.layer,
    super.colorIndex,
  });
}

class DxfRawText extends DxfRawEntity {
  final String text;
  final CadPoint2D position;

  const DxfRawText({
    required this.text,
    required this.position,
    super.layer,
    super.colorIndex,
  });
}

/// Parsed container of raw DXF drawing primitives
class DxfParsedData {
  final List<DxfRawEntity> entities;
  final Set<String> layers;

  const DxfParsedData({required this.entities, required this.layers});

  List<T> getEntitiesOfType<T extends DxfRawEntity>() =>
      entities.whereType<T>().toList();

  List<DxfRawEntity> getLayerEntities(String layerName) {
    final lower = layerName.toLowerCase();
    return entities.where((e) => e.layer.toLowerCase() == lower).toList();
  }
}

class DxfMiniParser {
  /// Parses ASCII DXF string content into [DxfParsedData].
  static DxfParsedData parse(String dxfContent) {
    final lines = const LineSplitter().convert(dxfContent);
    final entities = <DxfRawEntity>[];
    final layers = <String>{'0'};

    int idx = 0;
    bool inEntities = false;

    while (idx < lines.length - 1) {
      final codeStr = lines[idx].trim();
      final valStr = lines[idx + 1].trim();
      idx += 2;

      final code = int.tryParse(codeStr);
      if (code == null) continue;

      if (code == 0 && valStr == 'SECTION') {
        if (idx < lines.length - 1 && lines[idx].trim() == '2') {
          final secName = lines[idx + 1].trim().toUpperCase();
          idx += 2;
          if (secName == 'ENTITIES') inEntities = true;
        }
      } else if (code == 0 && valStr == 'ENDSEC') {
        inEntities = false;
      }

      if (inEntities && code == 0) {
        final entType = valStr.toUpperCase();
        if (entType == 'LINE') {
          final (line, nextIdx) = _parseLine(lines, idx);
          if (line != null) {
            entities.add(line);
            layers.add(line.layer);
          }
          idx = nextIdx;
        } else if (entType == 'LWPOLYLINE') {
          final (poly, nextIdx) = _parseLwPolyline(lines, idx);
          if (poly != null) {
            entities.add(poly);
            layers.add(poly.layer);
          }
          idx = nextIdx;
        } else if (entType == 'CIRCLE') {
          final (circle, nextIdx) = _parseCircle(lines, idx);
          if (circle != null) {
            entities.add(circle);
            layers.add(circle.layer);
          }
          idx = nextIdx;
        } else if (entType == 'ARC') {
          final (arc, nextIdx) = _parseArc(lines, idx);
          if (arc != null) {
            entities.add(arc);
            layers.add(arc.layer);
          }
          idx = nextIdx;
        } else if (entType == 'TEXT' || entType == 'MTEXT') {
          final (text, nextIdx) = _parseText(lines, idx);
          if (text != null) {
            entities.add(text);
            layers.add(text.layer);
          }
          idx = nextIdx;
        }
      }
    }

    return DxfParsedData(entities: entities, layers: layers);
  }

  static (DxfRawLine?, int) _parseLine(List<String> lines, int startIdx) {
    int idx = startIdx;
    double x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    String layer = '0';
    int color = 7;

    while (idx < lines.length - 1) {
      final code = int.tryParse(lines[idx].trim()) ?? -1;
      final val = lines[idx + 1].trim();

      if (code == 0) break; // Next entity started
      idx += 2;

      switch (code) {
        case 8:
          layer = val;
          break;
        case 62:
          color = int.tryParse(val) ?? 7;
          break;
        case 10:
          x1 = double.tryParse(val) ?? 0;
          break;
        case 20:
          y1 = double.tryParse(val) ?? 0;
          break;
        case 11:
          x2 = double.tryParse(val) ?? 0;
          break;
        case 21:
          y2 = double.tryParse(val) ?? 0;
          break;
      }
    }

    return (
      DxfRawLine(
        p1: CadPoint2D(x1, y1),
        p2: CadPoint2D(x2, y2),
        layer: layer,
        colorIndex: color,
      ),
      idx
    );
  }

  static (DxfRawPolyline?, int) _parseLwPolyline(List<String> lines, int startIdx) {
    int idx = startIdx;
    final vertices = <CadPoint2D>[];
    String layer = '0';
    int color = 7;
    bool isClosed = false;
    double? curX;

    while (idx < lines.length - 1) {
      final code = int.tryParse(lines[idx].trim()) ?? -1;
      final val = lines[idx + 1].trim();

      if (code == 0) break;
      idx += 2;

      switch (code) {
        case 8:
          layer = val;
          break;
        case 62:
          color = int.tryParse(val) ?? 7;
          break;
        case 70:
          final flags = int.tryParse(val) ?? 0;
          isClosed = (flags & 1) == 1;
          break;
        case 10:
          curX = double.tryParse(val);
          break;
        case 20:
          if (curX != null) {
            final curY = double.tryParse(val) ?? 0;
            vertices.add(CadPoint2D(curX, curY));
            curX = null;
          }
          break;
      }
    }

    if (vertices.isEmpty) return (null, idx);
    return (
      DxfRawPolyline(
        vertices: vertices,
        isClosed: isClosed,
        layer: layer,
        colorIndex: color,
      ),
      idx
    );
  }

  static (DxfRawCircle?, int) _parseCircle(List<String> lines, int startIdx) {
    int idx = startIdx;
    double cx = 0, cy = 0, r = 0;
    String layer = '0';
    int color = 7;

    while (idx < lines.length - 1) {
      final code = int.tryParse(lines[idx].trim()) ?? -1;
      final val = lines[idx + 1].trim();

      if (code == 0) break;
      idx += 2;

      switch (code) {
        case 8:
          layer = val;
          break;
        case 62:
          color = int.tryParse(val) ?? 7;
          break;
        case 10:
          cx = double.tryParse(val) ?? 0;
          break;
        case 20:
          cy = double.tryParse(val) ?? 0;
          break;
        case 40:
          r = double.tryParse(val) ?? 0;
          break;
      }
    }

    return (
      DxfRawCircle(
        center: CadPoint2D(cx, cy),
        radius: r,
        layer: layer,
        colorIndex: color,
      ),
      idx
    );
  }

  static (DxfRawArc?, int) _parseArc(List<String> lines, int startIdx) {
    int idx = startIdx;
    double cx = 0, cy = 0, r = 0, startA = 0, endA = 0;
    String layer = '0';
    int color = 7;

    while (idx < lines.length - 1) {
      final code = int.tryParse(lines[idx].trim()) ?? -1;
      final val = lines[idx + 1].trim();

      if (code == 0) break;
      idx += 2;

      switch (code) {
        case 8:
          layer = val;
          break;
        case 62:
          color = int.tryParse(val) ?? 7;
          break;
        case 10:
          cx = double.tryParse(val) ?? 0;
          break;
        case 20:
          cy = double.tryParse(val) ?? 0;
          break;
        case 40:
          r = double.tryParse(val) ?? 0;
          break;
        case 50:
          startA = double.tryParse(val) ?? 0;
          break;
        case 51:
          endA = double.tryParse(val) ?? 0;
          break;
      }
    }

    return (
      DxfRawArc(
        center: CadPoint2D(cx, cy),
        radius: r,
        startAngleDeg: startA,
        endAngleDeg: endA,
        layer: layer,
        colorIndex: color,
      ),
      idx
    );
  }

  static (DxfRawText?, int) _parseText(List<String> lines, int startIdx) {
    int idx = startIdx;
    double x = 0, y = 0;
    String text = '';
    String layer = '0';
    int color = 7;

    while (idx < lines.length - 1) {
      final code = int.tryParse(lines[idx].trim()) ?? -1;
      final val = lines[idx + 1].trim();

      if (code == 0) break;
      idx += 2;

      switch (code) {
        case 1:
          text = val;
          break;
        case 8:
          layer = val;
          break;
        case 62:
          color = int.tryParse(val) ?? 7;
          break;
        case 10:
          x = double.tryParse(val) ?? 0;
          break;
        case 20:
          y = double.tryParse(val) ?? 0;
          break;
      }
    }

    return (
      DxfRawText(
        text: text,
        position: CadPoint2D(x, y),
        layer: layer,
        colorIndex: color,
      ),
      idx
    );
  }
}
