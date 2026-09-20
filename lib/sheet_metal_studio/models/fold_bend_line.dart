// =============================================================================
// fold_bend_line.dart
//
// Represents a press-brake bend line axis in the unfolded flat pattern.
// Connects two planar faces in the kinematic folding tree.
// =============================================================================

import 'dart:math' as math;
import 'cad_primitives.dart';
import 'sheet_metal_definition.dart';

/// Direction of press-brake fold relative to the top surface of the sheet
enum BendDirection {
  up,   // Positive rotation around bend axis (+Z in local frame)
  down, // Negative rotation around bend axis (-Z in local frame)
}

/// Functional role of the press-brake crease line:
/// - [bend]: Primary structural body crease forming main sidewalls (typically 50-200 mm, default R=1.5mm)
/// - [flange]: Edge return lip, hem, or mounting bracket tab (typically 10-15 mm, e.g. 13mm/14mm, default R=0.5mm)
enum BendLineRole {
  bend,
  flange;

  static BendLineRole fromString(String? val) {
    if (val?.toLowerCase() == 'flange') return BendLineRole.flange;
    return BendLineRole.bend;
  }
}

class FoldBendLine {
  final String id;
  final CadPoint2D p1;
  final CadPoint2D p2;
  final BendDirection direction;
  final double targetAngleDeg; // e.g. 90.0 or 45.0
  final double radiusMm;
  final BendLineRole role;
  final String layer;
  final String parentFaceId;
  final String childFaceId;
  final bool showLabel;
  final bool isVisible;

  // First-class properties per Master Guide #27 (Step 13) & #28 (Step 14)
  final double? kFactor;
  final BendReliefType reliefType;
  final double? reliefWidthMm;
  final double? reliefDepthMm;
  final double? allowanceOverride;
  final double? deductionOverride;

  const FoldBendLine({
    required this.id,
    required this.p1,
    required this.p2,
    this.direction = BendDirection.up,
    this.targetAngleDeg = 90.0,
    this.radiusMm = 1.5,
    this.role = BendLineRole.bend,
    this.layer = 'BEND_UP',
    this.parentFaceId = '',
    this.childFaceId = '',
    this.showLabel = true,
    this.isVisible = true,
    this.kFactor,
    this.reliefType = BendReliefType.rectangular,
    this.reliefWidthMm,
    this.reliefDepthMm,
    this.allowanceOverride,
    this.deductionOverride,
  });

  /// Whether this crease acts as an edge return flange
  bool get isFlange => role == BendLineRole.flange;

  /// Length of the bend line
  double get length => p1.distanceTo(p2);

  double get x1 => p1.x;
  double get y1 => p1.y;
  double get x2 => p2.x;
  double get y2 => p2.y;
  double get angleDeg => targetAngleDeg;

  /// Midpoint of the bend line
  CadPoint2D get midpoint => CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);

  /// Unit direction vector from p1 to p2
  CadPoint2D get unitDirection {
    final len = length;
    if (len < 1e-6) return const CadPoint2D(1, 0);
    return CadPoint2D((p2.x - p1.x) / len, (p2.y - p1.y) / len);
  }

  /// Unit normal vector perpendicular to the bend line (in-plane 2D)
  CadPoint2D get unitNormal {
    final u = unitDirection;
    return CadPoint2D(-u.y, u.x);
  }

  /// Angle in radians adjusted for UP (+) vs DOWN (-) direction
  double get effectiveSignedAngleRad {
    final sign = direction == BendDirection.up ? 1.0 : -1.0;
    return sign * (targetAngleDeg * math.pi / 180.0);
  }

  /// Calculates bend allowance BA = (π / 180) * angle * (R + K * T)
  double calculateBendAllowance({required double sheetThicknessMm, double kFactor = 0.40}) {
    if (allowanceOverride != null) return allowanceOverride!;
    final effectiveK = this.kFactor ?? kFactor;
    final r = radiusMm > 0 ? radiusMm : sheetThicknessMm;
    return (math.pi / 180.0) * targetAngleDeg.abs() * (r + effectiveK * sheetThicknessMm);
  }

  /// Calculates outside setback OSB = tan(θ / 2) * (R + T)
  double calculateOutsideSetback({required double sheetThicknessMm}) {
    final r = radiusMm > 0 ? radiusMm : sheetThicknessMm;
    final angleRad = (targetAngleDeg.abs() * math.pi / 180.0);
    return math.tan(angleRad / 2.0) * (r + sheetThicknessMm);
  }

  /// Calculates inside setback ISB = tan(θ / 2) * R
  double calculateInsideSetback({required double sheetThicknessMm}) {
    final r = radiusMm > 0 ? radiusMm : sheetThicknessMm;
    final angleRad = (targetAngleDeg.abs() * math.pi / 180.0);
    return math.tan(angleRad / 2.0) * r;
  }

  /// Calculates bend deduction BD = 2 * OSB - BA
  double calculateBendDeduction({required double sheetThicknessMm, double kFactor = 0.40}) {
    if (deductionOverride != null) return deductionOverride!;
    final osb = calculateOutsideSetback(sheetThicknessMm: sheetThicknessMm);
    final ba = calculateBendAllowance(sheetThicknessMm: sheetThicknessMm, kFactor: kFactor);
    return 2.0 * osb - ba;
  }

  FoldBendLine copyWith({
    String? id,
    CadPoint2D? p1,
    CadPoint2D? p2,
    BendDirection? direction,
    double? targetAngleDeg,
    double? radiusMm,
    BendLineRole? role,
    String? layer,
    String? parentFaceId,
    String? childFaceId,
    bool? showLabel,
    bool? isVisible,
    double? kFactor,
    BendReliefType? reliefType,
    double? reliefWidthMm,
    double? reliefDepthMm,
    double? allowanceOverride,
    double? deductionOverride,
  }) {
    return FoldBendLine(
      id: id ?? this.id,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      direction: direction ?? this.direction,
      targetAngleDeg: targetAngleDeg ?? this.targetAngleDeg,
      radiusMm: radiusMm ?? this.radiusMm,
      role: role ?? this.role,
      layer: layer ?? this.layer,
      parentFaceId: parentFaceId ?? this.parentFaceId,
      childFaceId: childFaceId ?? this.childFaceId,
      showLabel: showLabel ?? this.showLabel,
      isVisible: isVisible ?? this.isVisible,
      kFactor: kFactor ?? this.kFactor,
      reliefType: reliefType ?? this.reliefType,
      reliefWidthMm: reliefWidthMm ?? this.reliefWidthMm,
      reliefDepthMm: reliefDepthMm ?? this.reliefDepthMm,
      allowanceOverride: allowanceOverride ?? this.allowanceOverride,
      deductionOverride: deductionOverride ?? this.deductionOverride,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'p1': p1.toJson(),
        'p2': p2.toJson(),
        'direction': direction == BendDirection.up ? 'UP' : 'DOWN',
        'targetAngleDeg': targetAngleDeg,
        'radiusMm': radiusMm,
        'role': role.name,
        'layer': layer,
        'parentFaceId': parentFaceId,
        'childFaceId': childFaceId,
        'showLabel': showLabel,
        'isVisible': isVisible,
        if (kFactor != null) 'kFactor': kFactor,
        'reliefType': reliefType.name,
        if (reliefWidthMm != null) 'reliefWidthMm': reliefWidthMm,
        if (reliefDepthMm != null) 'reliefDepthMm': reliefDepthMm,
        if (allowanceOverride != null) 'allowanceOverride': allowanceOverride,
        if (deductionOverride != null) 'deductionOverride': deductionOverride,
      };

  factory FoldBendLine.fromJson(Map<String, dynamic> json) => FoldBendLine(
        id: json['id'] as String? ?? 'B1',
        p1: CadPoint2D.fromJson(json['p1'] as Map<String, dynamic>),
        p2: CadPoint2D.fromJson(json['p2'] as Map<String, dynamic>),
        direction: (json['direction'] as String?) == 'DOWN'
            ? BendDirection.down
            : BendDirection.up,
        targetAngleDeg: (json['targetAngleDeg'] as num?)?.toDouble() ?? 90.0,
        radiusMm: (json['radiusMm'] as num?)?.toDouble() ?? 1.5,
        role: BendLineRole.fromString(json['role'] as String?),
        layer: json['layer'] as String? ?? 'BEND_UP',
        parentFaceId: json['parentFaceId'] as String? ?? '',
        childFaceId: json['childFaceId'] as String? ?? '',
        showLabel: json['showLabel'] as bool? ?? true,
        isVisible: json['isVisible'] as bool? ?? true,
        kFactor: (json['kFactor'] as num?)?.toDouble(),
        reliefType: json['reliefType'] != null
            ? BendReliefType.fromString(json['reliefType'] as String)
            : BendReliefType.rectangular,
        reliefWidthMm: (json['reliefWidthMm'] as num?)?.toDouble(),
        reliefDepthMm: (json['reliefDepthMm'] as num?)?.toDouble(),
        allowanceOverride: (json['allowanceOverride'] as num?)?.toDouble(),
        deductionOverride: (json['deductionOverride'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldBendLine &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          p1 == other.p1 &&
          p2 == other.p2 &&
          direction == other.direction &&
          (targetAngleDeg - other.targetAngleDeg).abs() < 1e-6 &&
          (radiusMm - other.radiusMm).abs() < 1e-6 &&
          role == other.role &&
          layer == other.layer &&
          parentFaceId == other.parentFaceId &&
          childFaceId == other.childFaceId &&
          showLabel == other.showLabel &&
          isVisible == other.isVisible &&
          kFactor == other.kFactor &&
          reliefType == other.reliefType &&
          reliefWidthMm == other.reliefWidthMm &&
          reliefDepthMm == other.reliefDepthMm &&
          allowanceOverride == other.allowanceOverride &&
          deductionOverride == other.deductionOverride;

  @override
  int get hashCode => Object.hash(
        id,
        p1,
        p2,
        direction,
        targetAngleDeg,
        radiusMm,
        role,
        layer,
        parentFaceId,
        childFaceId,
        showLabel,
        isVisible,
        kFactor,
        reliefType,
        reliefWidthMm,
        reliefDepthMm,
      );
}

typedef FoldDirection = BendDirection;
