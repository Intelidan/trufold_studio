// =============================================================================
// dynamic_dimension_input_state.dart
//
// Dynamic Direct Numeric / Dimension Input (AutoCAD / SolidWorks style HUD & Footer)
// Allows user to type exact dimensions while drawing lines, rectangles, circles,
// dimensions, bends, flanges, and punches.
// =============================================================================

import 'dart:math' as math;
import 'cad_primitives.dart';
import '../viewmodels/sheet_metal_studio_viewmodel.dart';

class DynamicDimensionInputState {
  String primaryBuffer = '';
  String secondaryBuffer = '';
  bool isEditingSecondary = false;

  CadPoint2D? anchorPoint;
  CadPoint2D? cursorPoint;

  bool get hasValue => primaryBuffer.trim().isNotEmpty || secondaryBuffer.trim().isNotEmpty;
  bool get hasPrimary => primaryBuffer.trim().isNotEmpty;
  bool get hasSecondary => secondaryBuffer.trim().isNotEmpty;
  bool get hasTypedPrimary => primaryBuffer.trim().isNotEmpty;
  bool get hasTypedSecondary => secondaryBuffer.trim().isNotEmpty;
  String get unit => 'mm';
  double get angleDeg => currentAngleDeg;

  double? get primaryValue => double.tryParse(primaryBuffer.trim());
  double? get secondaryValue => double.tryParse(secondaryBuffer.trim());

  String formatPrimary(StudioToolMode mode) {
    if (primaryBuffer.isNotEmpty) return primaryBuffer;
    if (mode == StudioToolMode.drawRectangle || mode == StudioToolMode.addPunchSquare) {
      return currentDeltaX > 0 ? currentDeltaX.toStringAsFixed(1) : '0.0';
    }
    return currentDistance > 0 ? currentDistance.toStringAsFixed(1) : '0.0';
  }

  String formatSecondary(StudioToolMode mode) {
    if (secondaryBuffer.isNotEmpty) return secondaryBuffer;
    return currentDeltaY > 0 ? currentDeltaY.toStringAsFixed(1) : (currentDeltaX > 0 ? currentDeltaX.toStringAsFixed(1) : '0.0');
  }

  void setAnchorPoint(CadPoint2D? pt) {
    anchorPoint = pt;
  }

  void setCursorPoint(CadPoint2D? pt) {
    cursorPoint = pt;
  }

  double get currentDistance {
    if (anchorPoint == null || cursorPoint == null) return 0.0;
    return anchorPoint!.distanceTo(cursorPoint!);
  }

  double get currentAngleDeg {
    if (anchorPoint == null || cursorPoint == null) return 0.0;
    final dx = cursorPoint!.x - anchorPoint!.x;
    final dy = cursorPoint!.y - anchorPoint!.y;
    double deg = math.atan2(dy, dx) * 180.0 / math.pi;
    if (deg < 0) deg += 360.0;
    return deg;
  }

  double get currentDeltaX {
    if (anchorPoint == null || cursorPoint == null) return 0.0;
    return (cursorPoint!.x - anchorPoint!.x).abs();
  }

  double get currentDeltaY {
    if (anchorPoint == null || cursorPoint == null) return 0.0;
    return (cursorPoint!.y - anchorPoint!.y).abs();
  }

  void appendChar(String char) {
    if (char == ',' || char == 'x' || char == 'X') {
      isEditingSecondary = true;
      return;
    }
    final target = isEditingSecondary ? secondaryBuffer : primaryBuffer;
    if (char == '.' && target.contains('.')) return;
    if (char == '-' && target.isNotEmpty) return;
    if (!RegExp(r'^[0-9.\-]$').hasMatch(char)) return;

    if (isEditingSecondary) {
      secondaryBuffer += char;
    } else {
      primaryBuffer += char;
    }
  }

  void backspace() {
    if (isEditingSecondary) {
      if (secondaryBuffer.isNotEmpty) {
        secondaryBuffer = secondaryBuffer.substring(0, secondaryBuffer.length - 1);
      } else {
        isEditingSecondary = false;
      }
    } else {
      if (primaryBuffer.isNotEmpty) {
        primaryBuffer = primaryBuffer.substring(0, primaryBuffer.length - 1);
      }
    }
  }

  void toggleSecondary() {
    isEditingSecondary = !isEditingSecondary;
  }

  void reset() {
    primaryBuffer = '';
    secondaryBuffer = '';
    isEditingSecondary = false;
    anchorPoint = null;
    cursorPoint = null;
  }

  CadPoint2D computeEffectiveEndpoint({
    required StudioToolMode toolMode,
    required ActiveToolConfig toolConfig,
  }) {
    final anchor = anchorPoint;
    final cur = cursorPoint ?? anchor ?? const CadPoint2D(0, 0);
    if (anchor == null) return cur;

    final pVal = primaryValue;
    final sVal = secondaryValue;

    if (toolMode == StudioToolMode.addCut ||
        toolMode == StudioToolMode.addBend ||
        toolMode == StudioToolMode.addFlange ||
        toolMode == StudioToolMode.drawPolyline ||
        toolMode == StudioToolMode.addDimension ||
        toolMode == StudioToolMode.dragDimension) {
      final dx = cur.x - anchor.x;
      final dy = cur.y - anchor.y;
      final len = math.sqrt(dx * dx + dy * dy);
      final angle = len > 1e-4 ? math.atan2(dy, dx) : 0.0;
      final targetLength = pVal ?? (len > 1e-3 ? len : 50.0);
      return CadPoint2D(
        anchor.x + targetLength * math.cos(angle),
        anchor.y + targetLength * math.sin(angle),
      );
    } else if (toolMode == StudioToolMode.drawRectangle ||
        toolMode == StudioToolMode.addPunchSquare) {
      final sx = cur.x >= anchor.x ? 1.0 : -1.0;
      final sy = cur.y >= anchor.y ? 1.0 : -1.0;
      final rawW = (cur.x - anchor.x).abs();
      final rawH = (cur.y - anchor.y).abs();

      final double w;
      final double h;

      if (sVal != null) {
        w = pVal ?? (rawW > 1e-3 ? rawW : (toolConfig.rectWidth > 0 ? toolConfig.rectWidth : 20.0));
        h = sVal;
      } else if (toolConfig.squareAspectLocked && toolMode == StudioToolMode.addPunchSquare) {
        final side = pVal ?? (math.max(rawW, rawH) > 1e-3 ? math.max(rawW, rawH) : (toolConfig.squareSize > 0 ? toolConfig.squareSize : 20.0));
        w = side;
        h = side;
      } else {
        w = pVal ?? (rawW > 1e-3 ? rawW : (toolConfig.rectWidth > 0 ? toolConfig.rectWidth : 20.0));
        h = sVal ?? pVal ?? (rawH > 1e-3 ? rawH : (toolConfig.rectHeight > 0 ? toolConfig.rectHeight : 20.0));
      }
      return CadPoint2D(anchor.x + sx * w, anchor.y + sy * h);
    } else if (toolMode == StudioToolMode.drawCircle ||
        toolMode == StudioToolMode.addPunchRound) {
      final dx = cur.x - anchor.x;
      final dy = cur.y - anchor.y;
      final len = math.sqrt(dx * dx + dy * dy);
      final angle = len > 1e-4 ? math.atan2(dy, dx) : 0.0;
      final targetR = pVal ?? (len > 1e-3 ? len : (toolConfig.roundHoleDiameter > 0 ? toolConfig.roundHoleDiameter / 2.0 : 10.0));
      return CadPoint2D(
        anchor.x + targetR * math.cos(angle),
        anchor.y + targetR * math.sin(angle),
      );
    } else if (toolMode == StudioToolMode.addPunchObround) {
      final w = pVal ?? (toolConfig.obroundLength > 0 ? toolConfig.obroundLength : 25.0);
      final l = sVal ?? (toolConfig.obroundWidth > 0 ? toolConfig.obroundWidth : 10.0);
      return CadPoint2D(anchor.x + w / 2.0, anchor.y + l / 2.0);
    }

    return cur;
  }

  String getPromptTitle(StudioToolMode mode) {
    switch (mode) {
      case StudioToolMode.addCut:
        return 'Specify Cut Line Length';
      case StudioToolMode.addBend:
        return 'Specify Bend Line Length';
      case StudioToolMode.addFlange:
        return 'Specify Flange Length';
      case StudioToolMode.drawPolyline:
        return 'Specify Polyline Segment Length';
      case StudioToolMode.drawCircle:
      case StudioToolMode.addPunchRound:
        return 'Specify Circle Radius';
      case StudioToolMode.drawRectangle:
      case StudioToolMode.addPunchSquare:
        return 'Specify Rectangle Dimensions';
      case StudioToolMode.addPunchObround:
        return 'Specify Obround Length & Width';
      case StudioToolMode.addDimension:
      case StudioToolMode.dragDimension:
        return 'Specify Dimension Distance';
      default:
        return 'Specify Distance';
    }
  }

  String getPrimaryLabel(StudioToolMode mode) {
    switch (mode) {
      case StudioToolMode.addCut:
      case StudioToolMode.addBend:
      case StudioToolMode.addFlange:
      case StudioToolMode.drawPolyline:
        return 'Length';
      case StudioToolMode.drawCircle:
      case StudioToolMode.addPunchRound:
        return 'Radius';
      case StudioToolMode.drawRectangle:
      case StudioToolMode.addPunchSquare:
        return 'Width';
      case StudioToolMode.addPunchObround:
        return 'Length';
      case StudioToolMode.addDimension:
      case StudioToolMode.dragDimension:
        return 'Dim';
      default:
        return 'Dist';
    }
  }

  String? getSecondaryLabel(StudioToolMode mode) {
    switch (mode) {
      case StudioToolMode.drawRectangle:
      case StudioToolMode.addPunchSquare:
        return 'Height';
      case StudioToolMode.addPunchObround:
        return 'Width';
      default:
        return null;
    }
  }
}
