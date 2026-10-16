// Parametric CAD Settings Model
// TruFold Assembly Studio - Phase 6 Settings
// Modular MVVM Architecture

import '../engine/sketch/assembly_extrude_engine.dart';

/// Viewport visual rendering style modes.
enum CadVisualStyle {
  shadedWithEdges,
  shaded,
  wireframe;

  String get label {
    switch (this) {
      case CadVisualStyle.shadedWithEdges:
        return 'Shaded with Edges';
      case CadVisualStyle.shaded:
        return 'Shaded Only';
      case CadVisualStyle.wireframe:
        return 'Wireframe';
    }
  }
}

/// Global parametric CAD modeling & viewport settings.
class AssemblyCadSettings {
  final double gridSnapMm;
  final double defaultExtrudeDistanceMm;
  final AssemblyExtrudeDirection defaultExtrudeDirection;
  final AssemblyExtrudeOperation defaultExtrudeOperation;
  final bool isImperial;
  final CadVisualStyle visualStyle;
  final bool showConstraintBadges;
  final bool showDofBadges;
  final bool showTimeline;
  final bool showOriginAxes;
  final bool autoConstraintInference;

  const AssemblyCadSettings({
    this.gridSnapMm = 5.0,
    this.defaultExtrudeDistanceMm = 25.0,
    this.defaultExtrudeDirection = AssemblyExtrudeDirection.oneSide,
    this.defaultExtrudeOperation = AssemblyExtrudeOperation.newBody,
    this.isImperial = false,
    this.visualStyle = CadVisualStyle.shadedWithEdges,
    this.showConstraintBadges = true,
    this.showDofBadges = true,
    this.showTimeline = true,
    this.showOriginAxes = true,
    this.autoConstraintInference = true,
  });

  AssemblyCadSettings copyWith({
    double? gridSnapMm,
    double? defaultExtrudeDistanceMm,
    AssemblyExtrudeDirection? defaultExtrudeDirection,
    AssemblyExtrudeOperation? defaultExtrudeOperation,
    bool? isImperial,
    CadVisualStyle? visualStyle,
    bool? showConstraintBadges,
    bool? showDofBadges,
    bool? showTimeline,
    bool? showOriginAxes,
    bool? autoConstraintInference,
  }) {
    return AssemblyCadSettings(
      gridSnapMm: gridSnapMm ?? this.gridSnapMm,
      defaultExtrudeDistanceMm: defaultExtrudeDistanceMm ?? this.defaultExtrudeDistanceMm,
      defaultExtrudeDirection: defaultExtrudeDirection ?? this.defaultExtrudeDirection,
      defaultExtrudeOperation: defaultExtrudeOperation ?? this.defaultExtrudeOperation,
      isImperial: isImperial ?? this.isImperial,
      visualStyle: visualStyle ?? this.visualStyle,
      showConstraintBadges: showConstraintBadges ?? this.showConstraintBadges,
      showDofBadges: showDofBadges ?? this.showDofBadges,
      showTimeline: showTimeline ?? this.showTimeline,
      showOriginAxes: showOriginAxes ?? this.showOriginAxes,
      autoConstraintInference: autoConstraintInference ?? this.autoConstraintInference,
    );
  }
}
