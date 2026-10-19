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
  static double _requiredDouble(String value, int groupCode, String entityType) {
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) {
      throw FormatException(
        '$entityType has an invalid numeric value for DXF group code $groupCode: "$value".',
      );
    }
    return parsed;
  }

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
        } else if (entType == 'POLYLINE') {
          final (poly, nextIdx) = _parsePolyline(lines, idx);
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
    double? x1, y1, x2, y2;
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
          x1 = _requiredDouble(val, code, 'LINE');
          break;
        case 20:
          y1 = _requiredDouble(val, code, 'LINE');
          break;
        case 11:
          x2 = _requiredDouble(val, code, 'LINE');
          break;
        case 21:
          y2 = _requiredDouble(val, code, 'LINE');
          break;
      }
    }

    if (x1 == null || y1 == null || x2 == null || y2 == null) {
      throw FormatException('LINE is missing a required coordinate group (10, 20, 11, or 21).');
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
          if (curX != null) {
            throw FormatException('LWPOLYLINE has an x coordinate without a matching y coordinate.');
          }
          curX = _requiredDouble(val, code, 'LWPOLYLINE');
          break;
        case 20:
          if (curX == null) {
            throw FormatException('LWPOLYLINE has a y coordinate without a matching x coordinate.');
          }
          vertices.add(CadPoint2D(curX, _requiredDouble(val, code, 'LWPOLYLINE')));
          curX = null;
          break;
      }
    }

    if (curX != null) {
      throw FormatException('LWPOLYLINE is missing a y coordinate for its final vertex.');
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

  static (DxfRawPolyline?, int) _parsePolyline(List<String> lines, int startIdx) {
    int idx = startIdx;
    final vertices = <CadPoint2D>[];
    String layer = '0';
    int color = 7;
    bool isClosed = false;

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
      }
    }

    while (idx < lines.length - 1) {
      final code = int.tryParse(lines[idx].trim()) ?? -1;
      final val = lines[idx + 1].trim().toUpperCase();
      if (code == 0) {
        if (val == 'VERTEX') {
          idx += 2;
          double? vx, vy;
          while (idx < lines.length - 1) {
            final vCode = int.tryParse(lines[idx].trim()) ?? -1;
            final vVal = lines[idx + 1].trim();
            if (vCode == 0) break;
            idx += 2;
            if (vCode == 10) vx = _requiredDouble(vVal, vCode, 'POLYLINE VERTEX');
            if (vCode == 20) vy = _requiredDouble(vVal, vCode, 'POLYLINE VERTEX');
          }
          if (vx == null || vy == null) {
            throw FormatException('POLYLINE VERTEX is missing a required coordinate group (10 or 20).');
          }
          vertices.add(CadPoint2D(vx, vy));
        } else if (val == 'SEQEND') {
          idx += 2;
          while (idx < lines.length - 1) {
            final sCode = int.tryParse(lines[idx].trim()) ?? -1;
            if (sCode == 0) break;
            idx += 2;
          }
          break;
        } else {
          break;
        }
      } else {
        idx += 2;
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
    double? cx, cy, r;
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
          cx = _requiredDouble(val, code, 'CIRCLE');
          break;
        case 20:
          cy = _requiredDouble(val, code, 'CIRCLE');
          break;
        case 40:
          r = _requiredDouble(val, code, 'CIRCLE');
          break;
      }
    }

    if (cx == null || cy == null || r == null || r <= 0) {
      throw FormatException('CIRCLE has missing coordinates or a non-positive radius.');
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
    double? cx, cy, r, startA, endA;
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
          cx = _requiredDouble(val, code, 'ARC');
          break;
        case 20:
          cy = _requiredDouble(val, code, 'ARC');
          break;
        case 40:
          r = _requiredDouble(val, code, 'ARC');
          break;
        case 50:
          startA = _requiredDouble(val, code, 'ARC');
          break;
        case 51:
          endA = _requiredDouble(val, code, 'ARC');
          break;
      }
    }

    if (cx == null || cy == null || r == null || r <= 0 || startA == null || endA == null) {
      throw FormatException('ARC has missing coordinates/angles or a non-positive radius.');
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
    double? x, y;
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
          x = _requiredDouble(val, code, 'TEXT');
          break;
        case 20:
          y = _requiredDouble(val, code, 'TEXT');
          break;
      }
    }

    if (x == null || y == null) {
      throw FormatException('TEXT is missing a required insertion coordinate group (10 or 20).');
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
