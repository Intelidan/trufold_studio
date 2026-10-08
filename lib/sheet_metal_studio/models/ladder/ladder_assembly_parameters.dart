import '../paint_coat_specification.dart';

/// Manufacturing method for joining each rung to the side rails.
enum LadderRungJointMethod {
  directInsideWeld,
  passThroughOutsideWeld;

  String get label => switch (this) {
    LadderRungJointMethod.directInsideWeld => 'Direct Inside Weld',
    LadderRungJointMethod.passThroughOutsideWeld => 'Pass-Through + Outside Weld',
  };

  String get code => switch (this) {
    LadderRungJointMethod.directInsideWeld => 'directInsideWeld',
    LadderRungJointMethod.passThroughOutsideWeld => 'passThroughOutsideWeld',
  };

  static LadderRungJointMethod fromString(String? value) {
    if (value == null) return LadderRungJointMethod.passThroughOutsideWeld;
    final lower = value.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    if (lower.contains('inside') || lower.contains('direct')) {
      return LadderRungJointMethod.directInsideWeld;
    }
    return LadderRungJointMethod.passThroughOutsideWeld;
  }
}

/// Pitch calculation mode for straight ladder rungs.
enum RungPitchMode {
  equalizedPitch,
  fixedPitch;

  String get label => switch (this) {
    RungPitchMode.equalizedPitch => 'Equalized Pitch',
    RungPitchMode.fixedPitch => 'Fixed Pitch',
  };

  static RungPitchMode fromString(String? value) {
    if (value == null) return RungPitchMode.equalizedPitch;
    if (value.toLowerCase().contains('fixed')) return RungPitchMode.fixedPitch;
    return RungPitchMode.equalizedPitch;
  }
}

/// Flange direction on the side rail return bends.
enum LadderFlangeDirection {
  inside,
  outside;

  String get label => switch (this) {
    LadderFlangeDirection.inside => 'Inside Flange',
    LadderFlangeDirection.outside => 'Outside Flange',
  };

  static LadderFlangeDirection fromString(String? value) {
    if (value == null) return LadderFlangeDirection.inside;
    if (value.toLowerCase().contains('out')) return LadderFlangeDirection.outside;
    return LadderFlangeDirection.inside;
  }
}

/// Geometry style for ladder accessories (curved radius vs angular/segmented).
enum LadderAccessoryStyle {
  curved,
  segmented;

  String get label => switch (this) {
    LadderAccessoryStyle.curved => 'Curved (Smooth Radius)',
    LadderAccessoryStyle.segmented => 'Angular / Segmented',
  };

  static LadderAccessoryStyle fromString(String? value) {
    if (value == null) return LadderAccessoryStyle.segmented;
    final lower = value.toLowerCase();
    if (lower.contains('curve')) return LadderAccessoryStyle.curved;
    return LadderAccessoryStyle.segmented;
  }
}

/// Full engineering parameter set defining a cable ladder assembly.
class LadderAssemblyParameters {
  final double width;
  final double height;
  final double length;
  final double thickness;
  final double flangeWidth;
  final LadderFlangeDirection flangeDirection;
  final LadderAccessoryStyle accessoryStyle;
  final double endMarginPitch; // P_end: header / footer margin
  final double intermediateTargetPitch; // P_target: default 250.0mm
  final RungPitchMode pitchMode;
  final LadderRungJointMethod jointMethod;
  final double outsideWeldProjection; // default 3.5mm
  final double passThroughClearance; // default 1.0mm
  final bool includeCover;
  final double coverHeight; // default 12.0mm
  final bool includeSpliceHoles;
  final String materialName;
  final PaintCoatSpecification paintCoat;

  const LadderAssemblyParameters({
    this.width = 600.0,
    this.height = 100.0,
    this.length = 3000.0,
    this.thickness = 2.0,
    this.flangeWidth = 32.0,
    this.flangeDirection = LadderFlangeDirection.inside,
    this.accessoryStyle = LadderAccessoryStyle.segmented,
    this.endMarginPitch = 125.0,
    this.intermediateTargetPitch = 250.0,
    this.pitchMode = RungPitchMode.equalizedPitch,
    this.jointMethod = LadderRungJointMethod.passThroughOutsideWeld,
    this.outsideWeldProjection = 3.5,
    this.passThroughClearance = 1.0,
    this.includeCover = false,
    this.coverHeight = 12.0,
    this.includeSpliceHoles = true,
    this.materialName = 'HDG',
    this.paintCoat = const PaintCoatSpecification(),
  });

  /// Calculates the physical cut length of a straight C-channel rung blank.
  double get physicalRungCutLength {
    switch (jointMethod) {
      case LadderRungJointMethod.directInsideWeld:
        return width;
      case LadderRungJointMethod.passThroughOutsideWeld:
        return width + (2 * thickness) + (2 * outsideWeldProjection);
    }
  }

  /// Calculates the rectangular slot dimensions on the side rail for pass-through joint.
  ({double width, double height}) get railSlotDimensions {
    const rungProfileW = 40.0;
    const rungProfileH = 20.0;
    return (
      width: rungProfileW + (2 * passThroughClearance),
      height: rungProfileH + (2 * passThroughClearance),
    );
  }

  LadderAssemblyParameters copyWith({
    double? width,
    double? height,
    double? length,
    double? thickness,
    double? flangeWidth,
    LadderFlangeDirection? flangeDirection,
    LadderAccessoryStyle? accessoryStyle,
    double? endMarginPitch,
    double? intermediateTargetPitch,
    RungPitchMode? pitchMode,
    LadderRungJointMethod? jointMethod,
    double? outsideWeldProjection,
    double? passThroughClearance,
    bool? includeCover,
    double? coverHeight,
    bool? includeSpliceHoles,
    String? materialName,
    PaintCoatSpecification? paintCoat,
  }) {
    return LadderAssemblyParameters(
      width: width ?? this.width,
      height: height ?? this.height,
      length: length ?? this.length,
      thickness: thickness ?? this.thickness,
      flangeWidth: flangeWidth ?? this.flangeWidth,
      flangeDirection: flangeDirection ?? this.flangeDirection,
      accessoryStyle: accessoryStyle ?? this.accessoryStyle,
      endMarginPitch: endMarginPitch ?? this.endMarginPitch,
      intermediateTargetPitch: intermediateTargetPitch ?? this.intermediateTargetPitch,
      pitchMode: pitchMode ?? this.pitchMode,
      jointMethod: jointMethod ?? this.jointMethod,
      outsideWeldProjection: outsideWeldProjection ?? this.outsideWeldProjection,
      passThroughClearance: passThroughClearance ?? this.passThroughClearance,
      includeCover: includeCover ?? this.includeCover,
      coverHeight: coverHeight ?? this.coverHeight,
      includeSpliceHoles: includeSpliceHoles ?? this.includeSpliceHoles,
      materialName: materialName ?? this.materialName,
      paintCoat: paintCoat ?? this.paintCoat,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'width': width,
      'height': height,
      'length': length,
      'thickness': thickness,
      'flangeWidth': flangeWidth,
      'flangeDirection': flangeDirection.name,
      'accessoryStyle': accessoryStyle.name,
      'endMarginPitch': endMarginPitch,
      'intermediateTargetPitch': intermediateTargetPitch,
      'pitchMode': pitchMode.name,
      'jointMethod': jointMethod.code,
      'outsideWeldProjection': outsideWeldProjection,
      'passThroughClearance': passThroughClearance,
      'includeCover': includeCover,
      'coverHeight': coverHeight,
      'includeSpliceHoles': includeSpliceHoles,
      'materialName': materialName,
      'paintCoat': paintCoat.toJson(),
    };
  }

  factory LadderAssemblyParameters.fromJson(Map<String, dynamic> json) {
    final targetPitch = (json['intermediateTargetPitch'] as num?)?.toDouble() ?? (json['rung_pitch'] as num?)?.toDouble() ?? 250.0;
    return LadderAssemblyParameters(
      width: (json['width'] as num?)?.toDouble() ?? 600.0,
      height: (json['height'] as num?)?.toDouble() ?? 100.0,
      length: (json['length'] as num?)?.toDouble() ?? 3000.0,
      thickness: (json['thickness'] as num?)?.toDouble() ?? 2.0,
      flangeWidth: (json['flangeWidth'] as num?)?.toDouble() ?? 32.0,
      flangeDirection: LadderFlangeDirection.fromString(json['flangeDirection'] as String?),
      accessoryStyle: LadderAccessoryStyle.fromString(json['accessoryStyle'] as String? ?? json['geometryStyle'] as String?),
      endMarginPitch: (json['endMarginPitch'] as num?)?.toDouble() ?? (json['end_margin_pitch'] as num?)?.toDouble() ?? (targetPitch / 2.0),
      intermediateTargetPitch: targetPitch,
      pitchMode: RungPitchMode.fromString(json['pitchMode'] as String?),
      jointMethod: LadderRungJointMethod.fromString(json['jointMethod'] as String?),
      outsideWeldProjection: (json['outsideWeldProjection'] as num?)?.toDouble() ?? (json['outside_weld_projection'] as num?)?.toDouble() ?? 3.5,
      passThroughClearance: (json['passThroughClearance'] as num?)?.toDouble() ?? 1.0,
      includeCover: json['includeCover'] as bool? ?? (json['include_cover'] != null ? (json['include_cover'] as num) > 0.5 : false),
      coverHeight: (json['coverHeight'] as num?)?.toDouble() ?? 12.0,
      includeSpliceHoles: json['includeSpliceHoles'] as bool? ?? true,
      materialName: json['materialName'] as String? ?? 'HDG',
      paintCoat: json['paintCoat'] != null
          ? PaintCoatSpecification.fromJson(json['paintCoat'] as Map<String, dynamic>)
          : const PaintCoatSpecification(),
    );
  }
}
