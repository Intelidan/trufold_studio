// Parametric Design History Timeline Item Model
// TruFold Assembly Studio - Phase 6 Parametric Timeline
// Modular MVVM Architecture

import 'package:flutter/material.dart';

/// Supported parametric feature types shown in the Fusion 360-style design history timeline.
enum AssemblyTimelineFeatureType {
  originPlane,
  constructionPlane,
  sketch,
  extrude,
  cut,
  weld;

  String get label {
    switch (this) {
      case AssemblyTimelineFeatureType.originPlane:
        return 'Origin Plane';
      case AssemblyTimelineFeatureType.constructionPlane:
        return 'Construction Plane';
      case AssemblyTimelineFeatureType.sketch:
        return '2D Sketch';
      case AssemblyTimelineFeatureType.extrude:
        return 'Extrude';
      case AssemblyTimelineFeatureType.cut:
        return 'Extruded Cut';
      case AssemblyTimelineFeatureType.weld:
        return 'Weld Joint';
    }
  }

  IconData get icon {
    switch (this) {
      case AssemblyTimelineFeatureType.originPlane:
        return Icons.grid_3x3_rounded;
      case AssemblyTimelineFeatureType.constructionPlane:
        return Icons.layers_outlined;
      case AssemblyTimelineFeatureType.sketch:
        return Icons.draw_rounded;
      case AssemblyTimelineFeatureType.extrude:
        return Icons.view_in_ar_rounded;
      case AssemblyTimelineFeatureType.cut:
        return Icons.content_cut_rounded;
      case AssemblyTimelineFeatureType.weld:
        return Icons.flash_on_rounded;
    }
  }

  Color get color {
    switch (this) {
      case AssemblyTimelineFeatureType.originPlane:
        return const Color(0xFF38BDF8); // Sky blue
      case AssemblyTimelineFeatureType.constructionPlane:
        return const Color(0xFFF59E0B); // Amber
      case AssemblyTimelineFeatureType.sketch:
        return const Color(0xFF06B6D4); // Cyan
      case AssemblyTimelineFeatureType.extrude:
        return const Color(0xFF10B981); // Emerald
      case AssemblyTimelineFeatureType.cut:
        return const Color(0xFFEF4444); // Red
      case AssemblyTimelineFeatureType.weld:
        return const Color(0xFFA855F7); // Purple
    }
  }
}

/// A single discrete parametric feature in the timeline history.
class AssemblyTimelineItem {
  final String id;
  final String name;
  final AssemblyTimelineFeatureType type;
  final DateTime timestamp;
  final String? entityId; // e.g. planeId, sketchPlaneId, partId, weldId
  final Map<String, dynamic> parameters;
  bool isSuppressed;

  AssemblyTimelineItem({
    required this.id,
    required this.name,
    required this.type,
    DateTime? timestamp,
    this.entityId,
    this.parameters = const {},
    this.isSuppressed = false,
  }) : timestamp = timestamp ?? DateTime.now();

  AssemblyTimelineItem copyWith({
    String? id,
    String? name,
    AssemblyTimelineFeatureType? type,
    DateTime? timestamp,
    String? entityId,
    Map<String, dynamic>? parameters,
    bool? isSuppressed,
  }) {
    return AssemblyTimelineItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      entityId: entityId ?? this.entityId,
      parameters: parameters ?? this.parameters,
      isSuppressed: isSuppressed ?? this.isSuppressed,
    );
  }
}
