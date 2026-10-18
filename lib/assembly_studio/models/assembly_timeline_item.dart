// Parametric Design History Timeline Item Model
// TruFold Assembly Studio - Phase 6 Parametric Timeline
// Modular MVVM Architecture

import 'package:flutter/material.dart';

import '../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';

typedef ExtrudeOperationSpec = ExtrudeFeatureSpec;

/// Supported parametric feature types shown in the Onshape / Fusion 360-style design history timeline.
enum AssemblyFeatureKind {
  originPlane,
  constructionPlane,
  sketch,
  extrude,
  cut,
  revolve,
  sheetMetalModel,
  flange,
  tab,
  mirror,
  modifyJoint,
  hole,
  weld;

  String get label {
    switch (this) {
      case AssemblyFeatureKind.originPlane:
        return 'Origin Plane';
      case AssemblyFeatureKind.constructionPlane:
        return 'Construction Plane';
      case AssemblyFeatureKind.sketch:
        return 'Sketch';
      case AssemblyFeatureKind.extrude:
        return 'Extrude';
      case AssemblyFeatureKind.cut:
        return 'Extruded Cut';
      case AssemblyFeatureKind.revolve:
        return 'Revolve';
      case AssemblyFeatureKind.sheetMetalModel:
        return 'Sheet Metal Model';
      case AssemblyFeatureKind.flange:
        return 'Flange';
      case AssemblyFeatureKind.tab:
        return 'Tab';
      case AssemblyFeatureKind.mirror:
        return 'Mirror';
      case AssemblyFeatureKind.modifyJoint:
        return 'Modify Joint';
      case AssemblyFeatureKind.hole:
        return 'Hole';
      case AssemblyFeatureKind.weld:
        return 'Weld Joint';
    }
  }

  IconData get icon {
    switch (this) {
      case AssemblyFeatureKind.originPlane:
        return Icons.grid_3x3_rounded;
      case AssemblyFeatureKind.constructionPlane:
        return Icons.layers_outlined;
      case AssemblyFeatureKind.sketch:
        return Icons.draw_rounded;
      case AssemblyFeatureKind.extrude:
        return Icons.view_in_ar_rounded;
      case AssemblyFeatureKind.cut:
        return Icons.content_cut_rounded;
      case AssemblyFeatureKind.revolve:
        return Icons.refresh_rounded;
      case AssemblyFeatureKind.sheetMetalModel:
        return Icons.architecture_rounded;
      case AssemblyFeatureKind.flange:
        return Icons.crop_square_rounded;
      case AssemblyFeatureKind.tab:
        return Icons.tab_rounded;
      case AssemblyFeatureKind.mirror:
        return Icons.flip_rounded;
      case AssemblyFeatureKind.modifyJoint:
        return Icons.link_rounded;
      case AssemblyFeatureKind.hole:
        return Icons.radio_button_unchecked_rounded;
      case AssemblyFeatureKind.weld:
        return Icons.flash_on_rounded;
    }
  }

  Color get color {
    switch (this) {
      case AssemblyFeatureKind.originPlane:
        return const Color(0xFF38BDF8); // Sky blue
      case AssemblyFeatureKind.constructionPlane:
        return const Color(0xFFF59E0B); // Amber
      case AssemblyFeatureKind.sketch:
        return const Color(0xFF0284C7); // Cyan
      case AssemblyFeatureKind.extrude:
        return const Color(0xFF10B981); // Emerald
      case AssemblyFeatureKind.cut:
        return const Color(0xFFEF4444); // Red
      case AssemblyFeatureKind.weld:
        return const Color(0xFFA855F7); // Purple
      default:
        return const Color(0xFF64748B);
    }
  }
}

typedef AssemblyTimelineFeatureType = AssemblyFeatureKind;

/// A single discrete parametric feature in the timeline history.
class AssemblyTimelineItem {
  final String id;
  String name; // Editable in-place: "Sketch 1", "Extrude 1", "Tab 1", etc.
  final AssemblyFeatureKind kind;
  AssemblyFeatureKind get type => kind;
  final String? parentSketchId; // For Extrude/Tab referencing a Sketch
  final Set<String> targetProfileIds; // Specific closed loop IDs inside parentSketchId
  ExtrudeFeatureSpec? extrudeSpec;
  bool isVisible;
  bool isSuppressed;
  bool hasError;
  String? errorMessage;
  final DateTime timestamp;
  final String? entityId; // e.g. planeId, sketchPlaneId, partId, weldId
  final Map<String, dynamic> parameters;

  AssemblyTimelineItem({
    required this.id,
    required this.name,
    AssemblyFeatureKind? kind,
    AssemblyFeatureKind? type,
    this.parentSketchId,
    Set<String>? targetProfileIds,
    this.extrudeSpec,
    this.isVisible = true,
    this.isSuppressed = false,
    this.hasError = false,
    this.errorMessage,
    DateTime? timestamp,
    this.entityId,
    this.parameters = const {},
  })  : kind = kind ?? type ?? AssemblyFeatureKind.sketch,
        targetProfileIds = targetProfileIds ?? <String>{},
        timestamp = timestamp ?? DateTime.now();

  AssemblyTimelineItem copyWith({
    String? id,
    String? name,
    AssemblyFeatureKind? kind,
    AssemblyFeatureKind? type,
    String? parentSketchId,
    Set<String>? targetProfileIds,
    ExtrudeFeatureSpec? extrudeSpec,
    bool? isVisible,
    bool? isSuppressed,
    bool? hasError,
    String? errorMessage,
    DateTime? timestamp,
    String? entityId,
    Map<String, dynamic>? parameters,
  }) {
    return AssemblyTimelineItem(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? type ?? this.kind,
      parentSketchId: parentSketchId ?? this.parentSketchId,
      targetProfileIds: targetProfileIds ?? this.targetProfileIds,
      extrudeSpec: extrudeSpec ?? this.extrudeSpec,
      isVisible: isVisible ?? this.isVisible,
      isSuppressed: isSuppressed ?? this.isSuppressed,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp ?? this.timestamp,
      entityId: entityId ?? this.entityId,
      parameters: parameters ?? this.parameters,
    );
  }
}
