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

/// A pull-out arrow attached to a [DdsNoteBoxAnnotation].
/// The arrow originates from the note-box border and its tip can be
/// snapped to a product entity id or left free-floating.
@immutable
class DdsNoteArrow {
  final String id;
  /// Arrow tip in paper-space mm (A4 = 297×210 mm).
  final CadPoint2D tip;
  /// Arrow root attachment point on the note-box border in paper-space mm.
  /// If null, defaults dynamically to the closest border point to [tip].
  final CadPoint2D? root;
  /// Optional entity id this arrow is anchored to.
  final String? anchorEntity;

  const DdsNoteArrow({
    required this.id,
    required this.tip,
    this.root,
    this.anchorEntity,
  });

  DdsNoteArrow copyWith({
    CadPoint2D? tip,
    CadPoint2D? root,
    String? anchorEntity,
    bool clearAnchor = false,
    bool clearRoot = false,
  }) {
    return DdsNoteArrow(
      id: id,
      tip: tip ?? this.tip,
      root: clearRoot ? null : (root ?? this.root),
      anchorEntity: clearAnchor ? null : (anchorEntity ?? this.anchorEntity),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tip': {'x': tip.x, 'y': tip.y},
    if (root != null) 'root': {'x': root!.x, 'y': root!.y},
    if (anchorEntity != null) 'anchorEntity': anchorEntity,
  };

  factory DdsNoteArrow.fromJson(Map<String, dynamic> json) {
    final tMap = json['tip'] as Map<String, dynamic>? ?? {'x': 0.0, 'y': 0.0};
    final rMap = json['root'] as Map<String, dynamic>?;
    CadPoint2D? parsedRoot;
    if (rMap != null) {
      parsedRoot = CadPoint2D(
        (rMap['x'] as num).toDouble(),
        (rMap['y'] as num).toDouble(),
      );
    }
    return DdsNoteArrow(
      id: json['id'] as String? ?? 'arrow_${DateTime.now().millisecondsSinceEpoch}',
      tip: CadPoint2D((tMap['x'] as num).toDouble(), (tMap['y'] as num).toDouble()),
      root: parsedRoot,
      anchorEntity: json['anchorEntity'] as String?,
    );
  }
}

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
  final String? backgroundColor;
  final String? textColor;
  final String? lineColor;

  const DdsAnnotation({
    required this.id,
    required this.type,
    required this.space,
    this.isVisible = true,
    this.backgroundColor,
    this.textColor,
    this.lineColor,
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

  /// Clones this annotation with an offset (dx, dy) and an optional new id.
  DdsAnnotation withOffset(double dx, double dy, {String? newId}) {
    final effectiveId = newId ?? '${id}_cpy_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final ann = this;
    if (ann is DdsNoteBoxAnnotation) {
      return ann.copyWith(id: effectiveId, x: ann.x + dx, y: ann.y + dy);
    } else if (ann is DdsApprovalStampAnnotation) {
      return ann.copyWith(id: effectiveId, x: ann.x + dx, y: ann.y + dy);
    } else if (ann is DdsLeaderNoteAnnotation) {
      return ann.copyWith(
        id: effectiveId,
        targetPoint: CadPoint2D(ann.targetPoint.x + dx, ann.targetPoint.y + dy),
        textPosition: CadPoint2D(ann.textPosition.x + dx, ann.textPosition.y + dy),
      );
    } else if (ann is DdsLinearDimensionAnnotation) {
      return ann.copyWith(
        id: effectiveId,
        p1: CadPoint2D(ann.p1.x + dx, ann.p1.y + dy),
        p2: CadPoint2D(ann.p2.x + dx, ann.p2.y + dy),
      );
    } else if (ann is DdsRevisionCloudAnnotation) {
      return ann.copyWith(
        id: effectiveId,
        points: ann.points.map((p) => CadPoint2D(p.x + dx, p.y + dy)).toList(),
      );
    }
    return ann;
  }

  static const String unset = '__UNSET__';

  /// Clones this annotation with updated color styling.
  DdsAnnotation withColors({
    String? backgroundColor = unset,
    String? textColor = unset,
    String? lineColor = unset,
  }) {
    final effectiveBg = identical(backgroundColor, unset) ? this.backgroundColor : backgroundColor;
    final effectiveText = identical(textColor, unset) ? this.textColor : textColor;
    final effectiveLine = identical(lineColor, unset) ? this.lineColor : lineColor;

    final ann = this;
    if (ann is DdsNoteBoxAnnotation) {
      return DdsNoteBoxAnnotation(
        id: ann.id,
        space: ann.space,
        isVisible: ann.isVisible,
        backgroundColor: effectiveBg,
        textColor: effectiveText,
        lineColor: effectiveLine,
        x: ann.x,
        y: ann.y,
        width: ann.width,
        height: ann.height,
        text: ann.text,
        fontSize: ann.fontSize,
        hasBorder: ann.hasBorder,
        arrows: ann.arrows,
      );
    } else if (ann is DdsApprovalStampAnnotation) {
      return DdsApprovalStampAnnotation(
        id: ann.id,
        space: ann.space,
        isVisible: ann.isVisible,
        backgroundColor: effectiveBg,
        textColor: effectiveText,
        lineColor: effectiveLine,
        x: ann.x,
        y: ann.y,
        width: ann.width,
        height: ann.height,
        status: ann.status,
        reviewedBy: ann.reviewedBy,
        reviewDate: ann.reviewDate,
      );
    } else if (ann is DdsLeaderNoteAnnotation) {
      return DdsLeaderNoteAnnotation(
        id: ann.id,
        space: ann.space,
        isVisible: ann.isVisible,
        backgroundColor: effectiveBg,
        textColor: effectiveText,
        lineColor: effectiveLine,
        targetPoint: ann.targetPoint,
        textPosition: ann.textPosition,
        text: ann.text,
      );
    } else if (ann is DdsLinearDimensionAnnotation) {
      return DdsLinearDimensionAnnotation(
        id: ann.id,
        space: ann.space,
        isVisible: ann.isVisible,
        backgroundColor: effectiveBg,
        textColor: effectiveText,
        lineColor: effectiveLine,
        p1: ann.p1,
        p2: ann.p2,
        anchorEntity: ann.anchorEntity,
        prefix: ann.prefix,
        suffix: ann.suffix,
        textOverride: ann.textOverride,
        offsetDistance: ann.offsetDistance,
      );
    } else if (ann is DdsRevisionCloudAnnotation) {
      return DdsRevisionCloudAnnotation(
        id: ann.id,
        space: ann.space,
        isVisible: ann.isVisible,
        backgroundColor: effectiveBg,
        textColor: effectiveText,
        lineColor: effectiveLine,
        points: ann.points,
        revisionTag: ann.revisionTag,
      );
    }
    return ann;
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
    super.backgroundColor,
    super.textColor,
    super.lineColor,
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

  DdsLinearDimensionAnnotation copyWith({
    String? id,
    CadPoint2D? p1,
    CadPoint2D? p2,
    String? anchorEntity,
    String? prefix,
    String? suffix,
    String? textOverride,
    double? offsetDistance,
    bool? isVisible,
    String? backgroundColor,
    String? textColor,
    String? lineColor,
  }) {
    return DdsLinearDimensionAnnotation(
      id: id ?? this.id,
      space: space,
      isVisible: isVisible ?? this.isVisible,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      lineColor: lineColor ?? this.lineColor,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      anchorEntity: anchorEntity ?? this.anchorEntity,
      prefix: prefix ?? this.prefix,
      suffix: suffix ?? this.suffix,
      textOverride: textOverride ?? this.textOverride,
      offsetDistance: offsetDistance ?? this.offsetDistance,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        if (textColor != null) 'textColor': textColor,
        if (lineColor != null) 'lineColor': lineColor,
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
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      lineColor: json['lineColor'] as String?,
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
    super.backgroundColor,
    super.textColor,
    super.lineColor,
    required this.targetPoint,
    required this.textPosition,
    required this.text,
    this.anchorEntity,
  }) : super(type: DdsAnnotationType.leaderNote);

  DdsLeaderNoteAnnotation copyWith({
    String? id,
    CadPoint2D? targetPoint,
    CadPoint2D? textPosition,
    String? text,
    String? anchorEntity,
    bool? isVisible,
    String? backgroundColor,
    String? textColor,
    String? lineColor,
  }) {
    return DdsLeaderNoteAnnotation(
      id: id ?? this.id,
      space: space,
      isVisible: isVisible ?? this.isVisible,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      lineColor: lineColor ?? this.lineColor,
      targetPoint: targetPoint ?? this.targetPoint,
      textPosition: textPosition ?? this.textPosition,
      text: text ?? this.text,
      anchorEntity: anchorEntity ?? this.anchorEntity,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        if (textColor != null) 'textColor': textColor,
        if (lineColor != null) 'lineColor': lineColor,
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
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      lineColor: json['lineColor'] as String?,
      targetPoint: CadPoint2D((tMap['x'] as num).toDouble(), (tMap['y'] as num).toDouble()),
      textPosition: CadPoint2D((pMap['x'] as num).toDouble(), (pMap['y'] as num).toDouble()),
      text: json['text'] as String? ?? '',
      anchorEntity: json['anchorEntity'] as String?,
    );
  }
}

/// Standalone text/note box placed on the sheet.
/// Each note box can own zero-or-more pull-out [DdsNoteArrow]s.
class DdsNoteBoxAnnotation extends DdsAnnotation {
  final double x;
  final double y;
  final double width;
  final double height;
  final String text;
  final double fontSize;
  final bool hasBorder;
  /// Pull-out arrows originating from this note box.
  final List<DdsNoteArrow> arrows;

  const DdsNoteBoxAnnotation({
    required super.id,
    super.space = DdsAnnotationSpace.sheet,
    super.isVisible = true,
    super.backgroundColor,
    super.textColor,
    super.lineColor,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.text,
    this.fontSize = 10.0,
    this.hasBorder = true,
    this.arrows = const [],
  }) : super(type: DdsAnnotationType.noteBox);

  DdsNoteBoxAnnotation copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    String? text,
    double? fontSize,
    bool? hasBorder,
    bool? isVisible,
    String? backgroundColor,
    String? textColor,
    String? lineColor,
    List<DdsNoteArrow>? arrows,
  }) {
    return DdsNoteBoxAnnotation(
      id: id ?? this.id,
      space: space,
      isVisible: isVisible ?? this.isVisible,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      lineColor: lineColor ?? this.lineColor,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      hasBorder: hasBorder ?? this.hasBorder,
      arrows: arrows ?? this.arrows,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        if (textColor != null) 'textColor': textColor,
        if (lineColor != null) 'lineColor': lineColor,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'text': text,
        'fontSize': fontSize,
        'hasBorder': hasBorder,
        if (arrows.isNotEmpty) 'arrows': arrows.map((a) => a.toJson()).toList(),
      };

  factory DdsNoteBoxAnnotation.fromJson(Map<String, dynamic> json) {
    final rawArrows = json['arrows'] as List<dynamic>? ?? [];
    return DdsNoteBoxAnnotation(
      id: json['id'] as String? ?? 'notebox_${DateTime.now().millisecondsSinceEpoch}',
      space: DdsAnnotationSpace.values.firstWhere(
        (e) => e.name == json['space'],
        orElse: () => DdsAnnotationSpace.sheet,
      ),
      isVisible: json['isVisible'] as bool? ?? true,
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      lineColor: json['lineColor'] as String?,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 100.0,
      height: (json['height'] as num?)?.toDouble() ?? 30.0,
      text: json['text'] as String? ?? '',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 10.0,
      hasBorder: json['hasBorder'] as bool? ?? true,
      arrows: rawArrows.map((a) => DdsNoteArrow.fromJson(a as Map<String, dynamic>)).toList(),
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
    super.backgroundColor,
    super.textColor,
    super.lineColor,
    required this.points,
    this.revisionTag = 'Δ1',
    this.arcRadius = 8.0,
  }) : super(type: DdsAnnotationType.revisionCloud);

  DdsRevisionCloudAnnotation copyWith({
    String? id,
    List<CadPoint2D>? points,
    String? revisionTag,
    double? arcRadius,
    bool? isVisible,
    String? backgroundColor,
    String? textColor,
    String? lineColor,
  }) {
    return DdsRevisionCloudAnnotation(
      id: id ?? this.id,
      space: space,
      isVisible: isVisible ?? this.isVisible,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      lineColor: lineColor ?? this.lineColor,
      points: points ?? this.points,
      revisionTag: revisionTag ?? this.revisionTag,
      arcRadius: arcRadius ?? this.arcRadius,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        if (textColor != null) 'textColor': textColor,
        if (lineColor != null) 'lineColor': lineColor,
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
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      lineColor: json['lineColor'] as String?,
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
    super.backgroundColor,
    super.textColor,
    super.lineColor,
    required this.x,
    required this.y,
    this.width = 180.0,
    this.height = 70.0,
    this.status = 'For Approval',
    this.reviewedBy = '',
    this.reviewDate = '',
    this.comments = '',
  }) : super(type: DdsAnnotationType.approvalStamp);

  DdsApprovalStampAnnotation copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    String? status,
    String? reviewedBy,
    String? reviewDate,
    String? comments,
    bool? isVisible,
    String? backgroundColor,
    String? textColor,
    String? lineColor,
  }) {
    return DdsApprovalStampAnnotation(
      id: id ?? this.id,
      space: space,
      isVisible: isVisible ?? this.isVisible,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      lineColor: lineColor ?? this.lineColor,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      status: status ?? this.status,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewDate: reviewDate ?? this.reviewDate,
      comments: comments ?? this.comments,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'space': space.name,
        'isVisible': isVisible,
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        if (textColor != null) 'textColor': textColor,
        if (lineColor != null) 'lineColor': lineColor,
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
      backgroundColor: json['backgroundColor'] as String?,
      textColor: json['textColor'] as String?,
      lineColor: json['lineColor'] as String?,
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
