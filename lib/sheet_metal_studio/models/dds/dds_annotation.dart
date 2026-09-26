// =============================================================================
// dds_annotation.dart
//
// Technical Data Sheet (TDS) Annotation & Drawing Markup Data Models.
// Supports both:
// 1. Model-space annotations: Anchored to CAD physical coordinates (in mm)
//    which track geometry scaling dynamically.
// 2. Sheet-space annotations: Anchored to paper layout coordinates (in mm/pt)
//    for notes, title blocks, revision clouds, and approval stamps.
// =============================================================================

import 'package:flutter/foundation.dart';
import '../cad_primitives.dart';

/// Coordinate space where the annotation lives.
enum DdsAnnotationSpace {
  /// Anchored to physical CAD model coordinates (in mm).
  model,

  /// Anchored to paper layout coordinates (in mm on A4/A3 sheet).
  sheet,
}

/// Category / type of annotation.
enum DdsAnnotationType {
  linearDimension,
  leaderNote,
  noteBox,
  revisionCloud,
  approvalStamp,
}

/// Active authoring / markup tool on the Technical Data Sheet paper canvas.
enum DdsMarkupTool {
  select,
  linearDimension,
  leaderNote,
  noteBox,
  revisionCloud,
  approvalStamp,
}

/// Abstract base class for all Technical Data Sheet annotations.
@immutable
abstract class DdsAnnotation {
  final String id;
  final DdsAnnotationType type;
  final DdsAnnotationSpace space;
  final bool isVisible;

  const DdsAnnotation({
    required this.id,
    required this.type,
    required this.space,
    this.isVisible = true,
  });

  Map<String, dynamic> toJson();

  static DdsAnnotation fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'linearDimension';
    final type = DdsAnnotationType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => DdsAnnotationType.linearDimension,
    );

    switch (type) {
      case DdsAnnotationType.linearDimension:
        return DdsLinearDimensionAnnotation.fromJson(json);
      case DdsAnnotationType.leaderNote:
        return DdsLeaderNoteAnnotation.fromJson(json);
      case DdsAnnotationType.noteBox:
        return DdsNoteBoxAnnotation.fromJson(json);
      case DdsAnnotationType.revisionCloud:
        return DdsRevisionCloudAnnotation.fromJson(json);
      case DdsAnnotationType.approvalStamp:
        return DdsApprovalStampAnnotation.fromJson(json);
    }
  }
}

/// Linear dimension annotation displaying a measurement with extension lines.
class DdsLinearDimensionAnnotation extends DdsAnnotation {
  final CadPoint2D p1;
  final CadPoint2D p2;
  final String? anchorEntity;
  final String? prefix;
  final String? suffix;
  final String? textOverride;
  final double offsetDistance;

  const DdsLinearDimensionAnnotation({
    required super.id,
    super.space = DdsAnnotationSpace.model,
    super.isVisible = true,
    required this.p1,
    required this.p2,
    this.anchorEntity,
    this.prefix,
    this.suffix = ' mm',
    this.textOverride,
    this.offsetDistance = 15.0,
  }) : super(type: DdsAnnotationType.linearDimension);

  double get measuredLength => (p2 - p1).length;

  String get displayText {
    if (textOverride != null && textOverride!.isNotEmpty) return textOverride!;
    final pre = prefix ?? '';
    final suf = suffix ?? '';
    return '$pre${measuredLength.toStringAsFixed(1)}$suf';
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        'p1': {'x': p1.x, 'y': p1.y},
        'p2': {'x': p2.x, 'y': p2.y},
        if (anchorEntity != null) 'anchorEntity': anchorEntity,
        if (prefix != null) 'prefix': prefix,
        if (suffix != null) 'suffix': suffix,
        if (textOverride != null) 'textOverride': textOverride,
        'offsetDistance': offsetDistance,
      };

  factory DdsLinearDimensionAnnotation.fromJson(Map<String, dynamic> json) {
    final p1Map = json['p1'] as Map<String, dynamic>? ?? {'x': 0.0, 'y': 0.0};
    final p2Map = json['p2'] as Map<String, dynamic>? ?? {'x': 0.0, 'y': 0.0};
    return DdsLinearDimensionAnnotation(
      id: json['id'] as String? ?? 'dim_${DateTime.now().millisecondsSinceEpoch}',
      space: DdsAnnotationSpace.values.firstWhere(
        (e) => e.name == json['space'],
        orElse: () => DdsAnnotationSpace.model,
      ),
      isVisible: json['isVisible'] as bool? ?? true,
      p1: CadPoint2D((p1Map['x'] as num).toDouble(), (p1Map['y'] as num).toDouble()),
      p2: CadPoint2D((p2Map['x'] as num).toDouble(), (p2Map['y'] as num).toDouble()),
      anchorEntity: json['anchorEntity'] as String?,
      prefix: json['prefix'] as String?,
      suffix: json['suffix'] as String? ?? ' mm',
      textOverride: json['textOverride'] as String?,
      offsetDistance: (json['offsetDistance'] as num?)?.toDouble() ?? 15.0,
    );
  }
}

/// Leader note annotation with arrow pointing to a feature and callout text.
class DdsLeaderNoteAnnotation extends DdsAnnotation {
  final CadPoint2D targetPoint;
  final CadPoint2D textPosition;
  final String text;
  final String? anchorEntity;

  const DdsLeaderNoteAnnotation({
    required super.id,
    super.space = DdsAnnotationSpace.model,
    super.isVisible = true,
    required this.targetPoint,
    required this.textPosition,
    required this.text,
    this.anchorEntity,
  }) : super(type: DdsAnnotationType.leaderNote);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        'targetPoint': {'x': targetPoint.x, 'y': targetPoint.y},
        'textPosition': {'x': textPosition.x, 'y': textPosition.y},
        'text': text,
        if (anchorEntity != null) 'anchorEntity': anchorEntity,
      };

  factory DdsLeaderNoteAnnotation.fromJson(Map<String, dynamic> json) {
    final tMap = json['targetPoint'] as Map<String, dynamic>? ?? {'x': 0.0, 'y': 0.0};
    final pMap = json['textPosition'] as Map<String, dynamic>? ?? {'x': 0.0, 'y': 0.0};
    return DdsLeaderNoteAnnotation(
      id: json['id'] as String? ?? 'leader_${DateTime.now().millisecondsSinceEpoch}',
      space: DdsAnnotationSpace.values.firstWhere(
        (e) => e.name == json['space'],
        orElse: () => DdsAnnotationSpace.model,
      ),
      isVisible: json['isVisible'] as bool? ?? true,
      targetPoint: CadPoint2D((tMap['x'] as num).toDouble(), (tMap['y'] as num).toDouble()),
      textPosition: CadPoint2D((pMap['x'] as num).toDouble(), (pMap['y'] as num).toDouble()),
      text: json['text'] as String? ?? '',
      anchorEntity: json['anchorEntity'] as String?,
    );
  }
}

/// Standalone text/note box placed on the sheet.
class DdsNoteBoxAnnotation extends DdsAnnotation {
  final double x;
  final double y;
  final double width;
  final double height;
  final String text;
  final double fontSize;
  final bool hasBorder;

  const DdsNoteBoxAnnotation({
    required super.id,
    super.space = DdsAnnotationSpace.sheet,
    super.isVisible = true,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.text,
    this.fontSize = 10.0,
    this.hasBorder = true,
  }) : super(type: DdsAnnotationType.noteBox);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'text': text,
        'fontSize': fontSize,
        'hasBorder': hasBorder,
      };

  factory DdsNoteBoxAnnotation.fromJson(Map<String, dynamic> json) {
    return DdsNoteBoxAnnotation(
      id: json['id'] as String? ?? 'notebox_${DateTime.now().millisecondsSinceEpoch}',
      space: DdsAnnotationSpace.values.firstWhere(
        (e) => e.name == json['space'],
        orElse: () => DdsAnnotationSpace.sheet,
      ),
      isVisible: json['isVisible'] as bool? ?? true,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 100.0,
      height: (json['height'] as num?)?.toDouble() ?? 30.0,
      text: json['text'] as String? ?? '',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 10.0,
      hasBorder: json['hasBorder'] as bool? ?? true,
    );
  }
}

/// Revision cloud drawn around site-specific or revised features.
class DdsRevisionCloudAnnotation extends DdsAnnotation {
  final List<CadPoint2D> points;
  final String revisionTag;
  final double arcRadius;

  const DdsRevisionCloudAnnotation({
    required super.id,
    super.space = DdsAnnotationSpace.model,
    super.isVisible = true,
    required this.points,
    this.revisionTag = 'Δ1',
    this.arcRadius = 8.0,
  }) : super(type: DdsAnnotationType.revisionCloud);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        'points': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
        'revisionTag': revisionTag,
        'arcRadius': arcRadius,
      };

  factory DdsRevisionCloudAnnotation.fromJson(Map<String, dynamic> json) {
    final rawPts = json['points'] as List<dynamic>? ?? [];
    final pts = rawPts
        .map((p) => CadPoint2D(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
            ))
        .toList();
    return DdsRevisionCloudAnnotation(
      id: json['id'] as String? ?? 'revcloud_${DateTime.now().millisecondsSinceEpoch}',
      space: DdsAnnotationSpace.values.firstWhere(
        (e) => e.name == json['space'],
        orElse: () => DdsAnnotationSpace.model,
      ),
      isVisible: json['isVisible'] as bool? ?? true,
      points: pts,
      revisionTag: json['revisionTag'] as String? ?? 'Δ1',
      arcRadius: (json['arcRadius'] as num?)?.toDouble() ?? 8.0,
    );
  }
}

/// Client / Consultant review stamp block with status selection.
class DdsApprovalStampAnnotation extends DdsAnnotation {
  final double x;
  final double y;
  final double width;
  final double height;
  final String status; // 'A - Approved', 'B - Approved as Noted', 'C - Revise and Resubmit'
  final String reviewedBy;
  final String reviewDate;
  final String comments;

  const DdsApprovalStampAnnotation({
    required super.id,
    super.space = DdsAnnotationSpace.sheet,
    super.isVisible = true,
    required this.x,
    required this.y,
    this.width = 180.0,
    this.height = 70.0,
    this.status = 'For Approval',
    this.reviewedBy = '',
    this.reviewDate = '',
    this.comments = '',
  }) : super(type: DdsAnnotationType.approvalStamp);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'status': status,
        'reviewedBy': reviewedBy,
        'reviewDate': reviewDate,
        'comments': comments,
      };

  factory DdsApprovalStampAnnotation.fromJson(Map<String, dynamic> json) {
    return DdsApprovalStampAnnotation(
      id: json['id'] as String? ?? 'stamp_${DateTime.now().millisecondsSinceEpoch}',
      space: DdsAnnotationSpace.values.firstWhere(
        (e) => e.name == json['space'],
        orElse: () => DdsAnnotationSpace.sheet,
      ),
      isVisible: json['isVisible'] as bool? ?? true,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 180.0,
      height: (json['height'] as num?)?.toDouble() ?? 70.0,
      status: json['status'] as String? ?? 'For Approval',
      reviewedBy: json['reviewedBy'] as String? ?? '',
      reviewDate: json['reviewDate'] as String? ?? '',
      comments: json['comments'] as String? ?? '',
    );
  }
}
