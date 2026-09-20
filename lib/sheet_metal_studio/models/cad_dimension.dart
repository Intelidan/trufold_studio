// =============================================================================
// cad_dimension.dart
//
// First-class persistent associative CAD Dimension entity.
// References specific geometry IDs and tracks measured values, offsets, and styles.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cad_primitives.dart';
import 'dsf_document.dart';

enum CadDimensionType {
  horizontal,
  vertical,
  aligned,
  angular,
  radius,
  diameter,
  arcLength,
  centerToCenter,
  edgeToEdge,
  holeToEdge,
  holeToHole,
  bendToEdge,
  bendToBend,
  overall,
}

enum CadAnchorType {
  center,
  midpoint,
  endpoint,
  startPoint,
  endPoint,
  arcMidpoint,
  quadrant,
  perpendicular;

  String get label {
    switch (this) {
      case CadAnchorType.center:
        return 'Center';
      case CadAnchorType.midpoint:
        return 'Midpoint';
      case CadAnchorType.endpoint:
      case CadAnchorType.startPoint:
      case CadAnchorType.endPoint:
        return 'Endpoint';
      case CadAnchorType.arcMidpoint:
        return 'Arc Midpoint';
      case CadAnchorType.quadrant:
        return 'Quadrant';
      case CadAnchorType.perpendicular:
        return 'Perpendicular';
    }
  }

  String get symbol {
    switch (this) {
      case CadAnchorType.center:
        return '⊙';
      case CadAnchorType.midpoint:
        return '⌖';
      case CadAnchorType.endpoint:
      case CadAnchorType.startPoint:
      case CadAnchorType.endPoint:
        return '•';
      case CadAnchorType.arcMidpoint:
        return '⊕';
      case CadAnchorType.quadrant:
        return '◇';
      case CadAnchorType.perpendicular:
        return '⊥';
    }
  }
}

enum CadAllowedMotion {
  edgeNormal,
  constraintVector,
  structuralParameter,
  free;
}

class CadDimension {
  final String id;
  final CadDimensionType type;
  final String? referenceAId; // Entity or vertex ID A
  final String? referenceBId; // Entity or vertex ID B
  final CadAnchorType? anchorTypeA; // Snap anchor type A
  final CadAnchorType? anchorTypeB; // Snap anchor type B
  final CadPoint2D? pointA; // Explicit geometric attachment point A
  final CadPoint2D? pointB; // Explicit geometric attachment point B
  final double dimensionLineOffset; // Perpendicular offset of dimension line from attachment
  final double extensionLineOvershoot; // Extension line overshoot beyond dimension line
  final double measuredValue;
  final Offset userOffset; // Drag displacement from default leader anchor
  final bool isDriven; // True if geometry drives dimension; False if dimension drives geometry
  final bool isDriving; // True if this dimension acts as an active driving constraint
  final CadAllowedMotion? allowedMotion; // Valid direction of motion when driving
  final String? referenceEntityId; // Reference entity that stays stationary
  final String? drivenEntityId; // Entity that moves to satisfy the constraint
  final String? parameterId; // Linked CadParameter ID if driving
  final String? prefix; // e.g. 'Ø', 'R', '2×'
  final String? suffix; // e.g. 'TYP', 'REF', 'MAX'
  final double? toleranceUpper;
  final double? toleranceLower;
  final String? overrideText;
  final String units;
  final bool isVisible;

  const CadDimension({
    required this.id,
    required this.type,
    this.referenceAId,
    this.referenceBId,
    this.anchorTypeA,
    this.anchorTypeB,
    this.pointA,
    this.pointB,
    this.dimensionLineOffset = 8.0,
    this.extensionLineOvershoot = 4.0,
    required this.measuredValue,
    this.userOffset = Offset.zero,
    this.isDriven = true,
    bool? isDriving,
    this.allowedMotion,
    this.referenceEntityId,
    this.drivenEntityId,
    this.parameterId,
    this.prefix,
    this.suffix,
    this.toleranceUpper,
    this.toleranceLower,
    this.overrideText,
    this.units = 'mm',
    this.isVisible = true,
  }) : isDriving = isDriving ?? !isDriven;

  String get displayedText {
    if (overrideText != null && overrideText!.isNotEmpty) {
      return overrideText!;
    }
    String valStr;
    if (type == CadDimensionType.angular) {
      valStr = '${measuredValue.toStringAsFixed(1)}°';
    } else if (type == CadDimensionType.radius) {
      valStr = 'R${measuredValue.toStringAsFixed(1)}';
    } else if (type == CadDimensionType.diameter) {
      valStr = 'Ø${measuredValue.toStringAsFixed(1)}';
    } else {
      valStr = measuredValue.toStringAsFixed(2);
    }

    final pfx = prefix != null && prefix!.isNotEmpty ? '$prefix ' : '';
    final sfx = suffix != null && suffix!.isNotEmpty ? ' $suffix' : '';
    String tolStr = '';
    if (toleranceUpper != null || toleranceLower != null) {
      final u = toleranceUpper != null ? '+${toleranceUpper!.toStringAsFixed(2)}' : '+0.00';
      final l = toleranceLower != null ? '-${toleranceLower!.abs().toStringAsFixed(2)}' : '-0.00';
      tolStr = ' ($u / $l)';
    }

    return '$pfx$valStr$tolStr$sfx';
  }

  CadDimension copyWith({
    String? id,
    CadDimensionType? type,
    String? referenceAId,
    String? referenceBId,
    CadAnchorType? anchorTypeA,
    CadAnchorType? anchorTypeB,
    CadPoint2D? pointA,
    CadPoint2D? pointB,
    double? dimensionLineOffset,
    double? extensionLineOvershoot,
    double? measuredValue,
    Offset? userOffset,
    bool? isDriven,
    bool? isDriving,
    CadAllowedMotion? allowedMotion,
    String? referenceEntityId,
    String? drivenEntityId,
    String? parameterId,
    String? prefix,
    String? suffix,
    double? toleranceUpper,
    double? toleranceLower,
    String? overrideText,
    String? units,
    bool? isVisible,
  }) {
    return CadDimension(
      id: id ?? this.id,
      type: type ?? this.type,
      referenceAId: referenceAId ?? this.referenceAId,
      referenceBId: referenceBId ?? this.referenceBId,
      anchorTypeA: anchorTypeA ?? this.anchorTypeA,
      anchorTypeB: anchorTypeB ?? this.anchorTypeB,
      pointA: pointA ?? this.pointA,
      pointB: pointB ?? this.pointB,
      dimensionLineOffset: dimensionLineOffset ?? this.dimensionLineOffset,
      extensionLineOvershoot:
          extensionLineOvershoot ?? this.extensionLineOvershoot,
      measuredValue: measuredValue ?? this.measuredValue,
      userOffset: userOffset ?? this.userOffset,
      isDriven: isDriven ?? this.isDriven,
      isDriving: isDriving ?? this.isDriving,
      allowedMotion: allowedMotion ?? this.allowedMotion,
      referenceEntityId: referenceEntityId ?? this.referenceEntityId,
      drivenEntityId: drivenEntityId ?? this.drivenEntityId,
      parameterId: parameterId ?? this.parameterId,
      prefix: prefix ?? this.prefix,
      suffix: suffix ?? this.suffix,
      toleranceUpper: toleranceUpper ?? this.toleranceUpper,
      toleranceLower: toleranceLower ?? this.toleranceLower,
      overrideText: overrideText ?? this.overrideText,
      units: units ?? this.units,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        if (referenceAId != null) 'referenceAId': referenceAId,
        if (referenceBId != null) 'referenceBId': referenceBId,
        if (anchorTypeA != null) 'anchorTypeA': anchorTypeA!.name,
        if (anchorTypeB != null) 'anchorTypeB': anchorTypeB!.name,
        if (pointA != null) 'pointAX': pointA!.x,
        if (pointA != null) 'pointAY': pointA!.y,
        if (pointB != null) 'pointBX': pointB!.x,
        if (pointB != null) 'pointBY': pointB!.y,
        'dimensionLineOffset': dimensionLineOffset,
        'extensionLineOvershoot': extensionLineOvershoot,
        'measuredValue': measuredValue,
        'userOffsetX': userOffset.dx,
        'userOffsetY': userOffset.dy,
        'isDriven': isDriven,
        'isDriving': isDriving,
        if (allowedMotion != null) 'allowedMotion': allowedMotion!.name,
        if (referenceEntityId != null) 'referenceEntityId': referenceEntityId,
        if (drivenEntityId != null) 'drivenEntityId': drivenEntityId,
        if (parameterId != null) 'parameterId': parameterId,
        if (prefix != null) 'prefix': prefix,
        if (suffix != null) 'suffix': suffix,
        if (toleranceUpper != null) 'toleranceUpper': toleranceUpper,
        if (toleranceLower != null) 'toleranceLower': toleranceLower,
        if (overrideText != null) 'overrideText': overrideText,
        'units': units,
        'isVisible': isVisible,
      };

  factory CadDimension.fromJson(Map<String, dynamic> json) => CadDimension(
        id: json['id'] as String,
        type: CadDimensionType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CadDimensionType.horizontal,
        ),
        referenceAId: json['referenceAId'] as String?,
        referenceBId: json['referenceBId'] as String?,
        anchorTypeA: json['anchorTypeA'] != null
            ? CadAnchorType.values.firstWhere(
                (a) => a.name == json['anchorTypeA'],
                orElse: () => CadAnchorType.center,
              )
            : null,
        anchorTypeB: json['anchorTypeB'] != null
            ? CadAnchorType.values.firstWhere(
                (a) => a.name == json['anchorTypeB'],
                orElse: () => CadAnchorType.center,
              )
            : null,
        pointA: json['pointAX'] != null && json['pointAY'] != null
            ? CadPoint2D(
                (json['pointAX'] as num).toDouble(),
                (json['pointAY'] as num).toDouble(),
              )
            : null,
        pointB: json['pointBX'] != null && json['pointBY'] != null
            ? CadPoint2D(
                (json['pointBX'] as num).toDouble(),
                (json['pointBY'] as num).toDouble(),
              )
            : null,
        dimensionLineOffset:
            (json['dimensionLineOffset'] as num?)?.toDouble() ?? 8.0,
        extensionLineOvershoot:
            (json['extensionLineOvershoot'] as num?)?.toDouble() ?? 4.0,
        measuredValue: (json['measuredValue'] as num).toDouble(),
        userOffset: Offset(
          (json['userOffsetX'] as num?)?.toDouble() ?? 0.0,
          (json['userOffsetY'] as num?)?.toDouble() ?? 0.0,
        ),
        isDriven: json['isDriven'] as bool? ?? true,
        isDriving: json['isDriving'] as bool? ?? !(json['isDriven'] as bool? ?? true),
        allowedMotion: json['allowedMotion'] != null
            ? CadAllowedMotion.values.firstWhere(
                (m) => m.name == json['allowedMotion'],
                orElse: () => CadAllowedMotion.free,
              )
            : null,
        referenceEntityId: json['referenceEntityId'] as String?,
        drivenEntityId: json['drivenEntityId'] as String?,
        parameterId: json['parameterId'] as String?,
        prefix: json['prefix'] as String?,
        suffix: json['suffix'] as String?,
        toleranceUpper: (json['toleranceUpper'] as num?)?.toDouble(),
        toleranceLower: (json['toleranceLower'] as num?)?.toDouble(),
        overrideText: json['overrideText'] as String?,
        units: json['units'] as String? ?? 'mm',
        isVisible: json['isVisible'] as bool? ?? true,
      );

  /// Resolves the actual 2D attachment point of an anchor from the live DsfDocument.
  /// If the entity cannot be found or is null, returns fallbackPoint.
  static CadPoint2D? resolveAnchorPoint({
    required DsfDocument doc,
    required String? entityId,
    required CadAnchorType? anchorType,
    CadPoint2D? fallbackPoint,
  }) {
    if (entityId == null || entityId.isEmpty) return fallbackPoint;

    // 1. Punch / Hole
    final punch = doc.punches.where((p) => p.id == entityId).firstOrNull;
    if (punch != null) {
      return punch.center;
    }

    // 2. Arc
    final arc = doc.arcs.where((a) => a.id == entityId).firstOrNull;
    if (arc != null) {
      switch (anchorType) {
        case CadAnchorType.center:
          return arc.center;
        case CadAnchorType.startPoint:
          return arc.startPoint;
        case CadAnchorType.endPoint:
        case CadAnchorType.endpoint:
          return arc.endPoint;
        case CadAnchorType.arcMidpoint:
          final midAngle = (arc.startAngleRad + arc.sweepAngleRad / 2.0);
          return CadPoint2D(
            arc.center.x + arc.radius * math.cos(midAngle),
            arc.center.y + arc.radius * math.sin(midAngle),
          );
        default:
          return arc.center;
      }
    }

    // 3. Bend
    final bend = doc.bends.where((b) => b.id == entityId).firstOrNull;
    if (bend != null) {
      switch (anchorType) {
        case CadAnchorType.midpoint:
          return CadPoint2D(
            (bend.p1.x + bend.p2.x) / 2.0,
            (bend.p1.y + bend.p2.y) / 2.0,
          );
        case CadAnchorType.startPoint:
          return bend.p1;
        case CadAnchorType.endPoint:
        case CadAnchorType.endpoint:
          return bend.p2;
        default:
          return CadPoint2D(
            (bend.p1.x + bend.p2.x) / 2.0,
            (bend.p1.y + bend.p2.y) / 2.0,
          );
      }
    }

    // 4. Cut Line
    final cut = doc.cutLines.where((c) => c.id == entityId).firstOrNull;
    if (cut != null) {
      switch (anchorType) {
        case CadAnchorType.midpoint:
          return CadPoint2D(
            (cut.p1.x + cut.p2.x) / 2.0,
            (cut.p1.y + cut.p2.y) / 2.0,
          );
        case CadAnchorType.startPoint:
          return cut.p1;
        case CadAnchorType.endPoint:
        case CadAnchorType.endpoint:
          return cut.p2;
        default:
          return CadPoint2D(
            (cut.p1.x + cut.p2.x) / 2.0,
            (cut.p1.y + cut.p2.y) / 2.0,
          );
      }
    }

    // 5. Contour Edge / Vertex
    if (entityId.startsWith('CONTOUR_EDGE_')) {
      final idxStr = entityId.replaceFirst('CONTOUR_EDGE_', '');
      final idx = int.tryParse(idxStr);
      if (idx != null && doc.outerContour.length >= 2 && idx < doc.outerContour.length) {
        final c1 = doc.outerContour[idx];
        final c2 = doc.outerContour[(idx + 1) % doc.outerContour.length];
        switch (anchorType) {
          case CadAnchorType.midpoint:
            return CadPoint2D((c1.x + c2.x) / 2.0, (c1.y + c2.y) / 2.0);
          case CadAnchorType.startPoint:
            return c1;
          case CadAnchorType.endPoint:
          case CadAnchorType.endpoint:
            return c2;
          default:
            return CadPoint2D((c1.x + c2.x) / 2.0, (c1.y + c2.y) / 2.0);
        }
      }
    }
    if (entityId.startsWith('CONTOUR_VERTEX_')) {
      final idxStr = entityId.replaceFirst('CONTOUR_VERTEX_', '');
      final idx = int.tryParse(idxStr);
      if (idx != null && idx < doc.outerContour.length) {
        return doc.outerContour[idx];
      }
    }

    return fallbackPoint;
  }
}
