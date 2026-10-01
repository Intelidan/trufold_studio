// =============================================================================
// dds_sheet.dart
//
// Technical Data Sheet (TDS) Sheet Presentation Model.
// Decouples product engineering instances from presentation sheets.
// A sheet presents views (2D & 3D), annotations, and layout configuration
// for a single product instance or a submittal cover schedule page.
// =============================================================================

import 'package:flutter/foundation.dart';

import '../cad_primitives.dart';
import 'dds_annotation.dart';

/// The role/type of a sheet within a Technical Data Sheet document.
enum DdsSheetType {
  /// Submittal Cover Page containing the transmittal schedule and BoQ index.
  coverSchedule,

  /// Detailed Technical Data Sheet for a single engineering product instance.
  productSheet,

  /// Blank engineering drafting sheet for custom sketches, diagrams, and annotations.
  blankSheet,
}

/// An entry in the Cover Page's Transmittal / Product Schedule table.
@immutable
class DdsTocEntry {
  final int sheetNumber;
  final String orderLine;
  final String customerRef;
  final String productName;
  final String configuration;
  final int quantity;
  final String status; // 'Resolved', 'Review', 'Pending'

  const DdsTocEntry({
    required this.sheetNumber,
    this.orderLine = '',
    this.customerRef = '',
    required this.productName,
    this.configuration = '',
    this.quantity = 1,
    this.status = 'Resolved',
  });

  Map<String, dynamic> toJson() => {
    'sheetNumber': sheetNumber,
    'orderLine': orderLine,
    'customerRef': customerRef,
    'productName': productName,
    'configuration': configuration,
    'quantity': quantity,
    'status': status,
  };

  factory DdsTocEntry.fromJson(Map<String, dynamic> json) {
    return DdsTocEntry(
      sheetNumber: (json['sheetNumber'] as num?)?.toInt() ?? 1,
      orderLine: json['orderLine'] as String? ?? '',
      customerRef: json['customerRef'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      configuration: json['configuration'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      status: json['status'] as String? ?? 'Resolved',
    );
  }
}

/// 3D isometric camera orientation and view controls for the sheet.
@immutable
class DdsCamera3DSettings {
  final double elevationDeg;
  final double azimuthDeg;
  final double zoom;
  final CadPoint2D panOffset;

  const DdsCamera3DSettings({this.elevationDeg = 30.0, this.azimuthDeg = 45.0, this.zoom = 1.0, this.panOffset = const CadPoint2D(0.0, 0.0)});

  Map<String, dynamic> toJson() => {
    'elevationDeg': elevationDeg,
    'azimuthDeg': azimuthDeg,
    'zoom': zoom,
    'panOffset': {'x': panOffset.x, 'y': panOffset.y},
  };

  factory DdsCamera3DSettings.fromJson(Map<String, dynamic> json) {
    final pan = json['panOffset'] as Map<String, dynamic>?;
    return DdsCamera3DSettings(
      elevationDeg: (json['elevationDeg'] as num?)?.toDouble() ?? 30.0,
      azimuthDeg: (json['azimuthDeg'] as num?)?.toDouble() ?? 45.0,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      panOffset: pan != null ? CadPoint2D((pan['x'] as num).toDouble(), (pan['y'] as num).toDouble()) : const CadPoint2D(0.0, 0.0),
    );
  }
}

/// 2D technical drawing view settings for the sheet.
@immutable
class DdsDrawing2DSettings {
  final String viewMode; // 'dimensionedOutline', 'flatPattern', 'sideBySide'
  final bool showBendLines;
  final bool showPunches;
  final double zoom;
  final CadPoint2D panOffset;

  const DdsDrawing2DSettings({
    this.viewMode = 'dimensionedOutline',
    this.showBendLines = true,
    this.showPunches = true,
    this.zoom = 1.0,
    this.panOffset = const CadPoint2D(0.0, 0.0),
  });

  Map<String, dynamic> toJson() => {
    'viewMode': viewMode,
    'showBendLines': showBendLines,
    'showPunches': showPunches,
    'zoom': zoom,
    'panOffset': {'x': panOffset.x, 'y': panOffset.y},
  };

  factory DdsDrawing2DSettings.fromJson(Map<String, dynamic> json) {
    final pan = json['panOffset'] as Map<String, dynamic>?;
    return DdsDrawing2DSettings(
      viewMode: json['viewMode'] as String? ?? 'dimensionedOutline',
      showBendLines: json['showBendLines'] as bool? ?? true,
      showPunches: json['showPunches'] as bool? ?? true,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      panOffset: pan != null ? CadPoint2D((pan['x'] as num).toDouble(), (pan['y'] as num).toDouble()) : const CadPoint2D(0.0, 0.0),
    );
  }
}

/// Sheet layout and paper presentation settings.
@immutable
class DdsViewSettings {
  final String paperSize; // 'A4_Landscape', 'A3_Landscape'
  final double splitRatio2D3D; // 0.50 means 50% 2D on left, 50% 3D on right
  final DdsCamera3DSettings camera3D;
  final DdsDrawing2DSettings drawing2D;
  final bool showCover3D;
  final bool showFasteners3D;
  final bool showDimWidth;
  final bool showDimHeight;
  final bool showDimPorts;
  final bool showDimSlots;
  final bool showDimFlange;
  final bool showDimThickness;
  final bool showCadDimensionLines;
  final bool showDimensionTags;

  const DdsViewSettings({
    this.paperSize = 'A4_Landscape',
    this.splitRatio2D3D = 0.50,
    this.camera3D = const DdsCamera3DSettings(),
    this.drawing2D = const DdsDrawing2DSettings(),
    this.showCover3D = true,
    this.showFasteners3D = false,
    this.showDimWidth = true,
    this.showDimHeight = true,
    this.showDimPorts = true,
    this.showDimSlots = true,
    this.showDimFlange = true,
    this.showDimThickness = true,
    this.showCadDimensionLines = true,
    this.showDimensionTags = false,
    this.combinePortDimensions = true,
    this.is3DModelLocked = false,
  });

  final bool combinePortDimensions;
  final bool is3DModelLocked;

  DdsViewSettings copyWith({
    String? paperSize,
    double? splitRatio2D3D,
    DdsCamera3DSettings? camera3D,
    DdsDrawing2DSettings? drawing2D,
    bool? showCover3D,
    bool? showFasteners3D,
    bool? showDimWidth,
    bool? showDimHeight,
    bool? showDimPorts,
    bool? showDimSlots,
    bool? showDimFlange,
    bool? showDimThickness,
    bool? showCadDimensionLines,
    bool? showDimensionTags,
    bool? combinePortDimensions,
    bool? is3DModelLocked,
  }) {
    return DdsViewSettings(
      paperSize: paperSize ?? this.paperSize,
      splitRatio2D3D: splitRatio2D3D ?? this.splitRatio2D3D,
      camera3D: camera3D ?? this.camera3D,
      drawing2D: drawing2D ?? this.drawing2D,
      showCover3D: showCover3D ?? this.showCover3D,
      showFasteners3D: showFasteners3D ?? this.showFasteners3D,
      showDimWidth: showDimWidth ?? this.showDimWidth,
      showDimHeight: showDimHeight ?? this.showDimHeight,
      showDimPorts: showDimPorts ?? this.showDimPorts,
      showDimSlots: showDimSlots ?? this.showDimSlots,
      showDimFlange: showDimFlange ?? this.showDimFlange,
      showDimThickness: showDimThickness ?? this.showDimThickness,
      showCadDimensionLines: showCadDimensionLines ?? this.showCadDimensionLines,
      showDimensionTags: showDimensionTags ?? this.showDimensionTags,
      combinePortDimensions: combinePortDimensions ?? this.combinePortDimensions,
      is3DModelLocked: is3DModelLocked ?? this.is3DModelLocked,
    );
  }

  Map<String, dynamic> toJson() => {
    'paperSize': paperSize,
    'splitRatio2D3D': splitRatio2D3D,
    'camera3D': camera3D.toJson(),
    'drawing2D': drawing2D.toJson(),
    'showCover3D': showCover3D,
    'showFasteners3D': showFasteners3D,
    'showDimWidth': showDimWidth,
    'showDimHeight': showDimHeight,
    'showDimPorts': showDimPorts,
    'showDimSlots': showDimSlots,
    'showDimFlange': showDimFlange,
    'showDimThickness': showDimThickness,
    'showCadDimensionLines': showCadDimensionLines,
    'showDimensionTags': showDimensionTags,
    'combinePortDimensions': combinePortDimensions,
    'is3DModelLocked': is3DModelLocked,
  };

  factory DdsViewSettings.fromJson(Map<String, dynamic> json) {
    return DdsViewSettings(
      paperSize: json['paperSize'] as String? ?? 'A4_Landscape',
      splitRatio2D3D: (json['splitRatio2D3D'] as num?)?.toDouble() ?? 0.50,
      camera3D: json['camera3D'] != null ? DdsCamera3DSettings.fromJson(json['camera3D'] as Map<String, dynamic>) : const DdsCamera3DSettings(),
      drawing2D: json['drawing2D'] != null ? DdsDrawing2DSettings.fromJson(json['drawing2D'] as Map<String, dynamic>) : const DdsDrawing2DSettings(),
      showCover3D: json['showCover3D'] as bool? ?? true,
      showFasteners3D: json['showFasteners3D'] as bool? ?? false,
      showDimWidth: json['showDimWidth'] as bool? ?? true,
      showDimHeight: json['showDimHeight'] as bool? ?? true,
      showDimPorts: json['showDimPorts'] as bool? ?? true,
      showDimSlots: json['showDimSlots'] as bool? ?? true,
      showDimFlange: json['showDimFlange'] as bool? ?? true,
      showDimThickness: json['showDimThickness'] as bool? ?? true,
      showCadDimensionLines: json['showCadDimensionLines'] as bool? ?? true,
      showDimensionTags: json['showDimensionTags'] as bool? ?? false,
      combinePortDimensions: json['combinePortDimensions'] as bool? ?? true,
      is3DModelLocked: json['is3DModelLocked'] as bool? ?? false,
    );
  }
}

/// A presentation sheet within a Technical Data Sheet document.
@immutable
class DdsSheet {
  final String sheetId;
  final DdsSheetType sheetType;
  final int sheetNumber;
  final String title;
  final String? productInstanceId;
  final List<DdsTocEntry> tableOfContents;
  final List<DdsAnnotation> annotations;
  final DdsViewSettings viewSettings;

  const DdsSheet({
    required this.sheetId,
    required this.sheetType,
    required this.sheetNumber,
    required this.title,
    this.productInstanceId,
    this.tableOfContents = const [],
    this.annotations = const [],
    this.viewSettings = const DdsViewSettings(),
  });

  bool get isCoverPage => sheetType == DdsSheetType.coverSchedule;
  bool get isBlankSheet => sheetType == DdsSheetType.blankSheet;

  Map<String, dynamic> toJson() => {
    'sheetId': sheetId,
    'sheetType': sheetType.name,
    'sheetNumber': sheetNumber,
    'title': title,
    if (productInstanceId != null) 'productInstanceId': productInstanceId,
    if (tableOfContents.isNotEmpty) 'tableOfContents': tableOfContents.map((e) => e.toJson()).toList(),
    'annotations': annotations.map((a) => a.toJson()).toList(),
    'viewSettings': viewSettings.toJson(),
  };

  factory DdsSheet.fromJson(Map<String, dynamic> json) {
    final typeStr = json['sheetType'] as String? ?? 'productSheet';
    final sheetType = DdsSheetType.values.firstWhere((e) => e.name == typeStr, orElse: () => DdsSheetType.productSheet);

    final rawToc = json['tableOfContents'] as List<dynamic>? ?? [];
    final toc = rawToc.map((e) => DdsTocEntry.fromJson(e as Map<String, dynamic>)).toList();

    final rawAnn = json['annotations'] as List<dynamic>? ?? [];
    final annotations = rawAnn.map((e) => DdsAnnotation.fromJson(e as Map<String, dynamic>)).toList();

    return DdsSheet(
      sheetId: json['sheetId'] as String? ?? 'sheet_${DateTime.now().millisecondsSinceEpoch}',
      sheetType: sheetType,
      sheetNumber: (json['sheetNumber'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? '',
      productInstanceId: json['productInstanceId'] as String?,
      tableOfContents: toc,
      annotations: annotations,
      viewSettings: json['viewSettings'] != null ? DdsViewSettings.fromJson(json['viewSettings'] as Map<String, dynamic>) : const DdsViewSettings(),
    );
  }

  DdsSheet copyWith({
    String? sheetId,
    DdsSheetType? sheetType,
    int? sheetNumber,
    String? title,
    String? productInstanceId,
    List<DdsTocEntry>? tableOfContents,
    List<DdsAnnotation>? annotations,
    DdsViewSettings? viewSettings,
  }) {
    return DdsSheet(
      sheetId: sheetId ?? this.sheetId,
      sheetType: sheetType ?? this.sheetType,
      sheetNumber: sheetNumber ?? this.sheetNumber,
      title: title ?? this.title,
      productInstanceId: productInstanceId ?? this.productInstanceId,
      tableOfContents: tableOfContents ?? this.tableOfContents,
      annotations: annotations ?? this.annotations,
      viewSettings: viewSettings ?? this.viewSettings,
    );
  }
}
