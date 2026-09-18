// =============================================================================
// cad_dimension.dart
//
// First-class persistent associative CAD Dimension entity.
// References specific geometry IDs and tracks measured values, offsets, and styles.
// =============================================================================

import 'package:flutter/material.dart';
import 'cad_primitives.dart';

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

class CadDimension {
  final String id;
  final CadDimensionType type;
  final String? referenceAId; // Entity or vertex ID A
  final String? referenceBId; // Entity or vertex ID B
  final CadPoint2D? pointA; // Explicit geometric attachment point A
  final CadPoint2D? pointB; // Explicit geometric attachment point B
  final double dimensionLineOffset; // Perpendicular offset of dimension line from attachment
  final double extensionLineOvershoot; // Extension line overshoot beyond dimension line
  final double measuredValue;
  final Offset userOffset; // Drag displacement from default leader anchor
  final bool isDriven; // True if geometry drives dimension; False if dimension drives geometry
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
    this.pointA,
    this.pointB,
    this.dimensionLineOffset = 8.0,
    this.extensionLineOvershoot = 4.0,
    required this.measuredValue,
    this.userOffset = Offset.zero,
    this.isDriven = true,
    this.parameterId,
    this.prefix,
    this.suffix,
    this.toleranceUpper,
    this.toleranceLower,
    this.overrideText,
    this.units = 'mm',
    this.isVisible = true,
  });

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
    CadPoint2D? pointA,
    CadPoint2D? pointB,
    double? dimensionLineOffset,
    double? extensionLineOvershoot,
    double? measuredValue,
    Offset? userOffset,
    bool? isDriven,
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
      pointA: pointA ?? this.pointA,
      pointB: pointB ?? this.pointB,
      dimensionLineOffset: dimensionLineOffset ?? this.dimensionLineOffset,
      extensionLineOvershoot:
          extensionLineOvershoot ?? this.extensionLineOvershoot,
      measuredValue: measuredValue ?? this.measuredValue,
      userOffset: userOffset ?? this.userOffset,
      isDriven: isDriven ?? this.isDriven,
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
        parameterId: json['parameterId'] as String?,
        prefix: json['prefix'] as String?,
        suffix: json['suffix'] as String?,
        toleranceUpper: (json['toleranceUpper'] as num?)?.toDouble(),
        toleranceLower: (json['toleranceLower'] as num?)?.toDouble(),
        overrideText: json['overrideText'] as String?,
        units: json['units'] as String? ?? 'mm',
        isVisible: json['isVisible'] as bool? ?? true,
      );
}
