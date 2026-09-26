// =============================================================================
// dds_product_instance.dart
//
// Technical Data Sheet (TDS) Engineering Product Instance Model.
// Represents a single configured product item in the document, capturing:
// - Template reference (ID, baseline filename, SHA-256 fingerprint)
// - Sizing parameter overrides (Widths, Heights, Lengths, Thickness, etc.)
// - Parametric cover configuration (Included, Flange depth, Placement mode)
// - Customer order metadata & line item traceability (Order No, Line, Qty)
// - Calculated physical takeoff (Flat surface area, mass in kg)
// =============================================================================

import 'package:flutter/foundation.dart';
import '../cad_primitives.dart';

/// Traceability and customer metadata for an imported order line item.
@immutable
class DdsOrderLine {
  final String orderNumber;
  final String lineNumber;
  final String customerItemReference;
  final int quantity;
  final String customerDescription;
  final String remarks;
  final String? sourceSheet;
  final int? sourceRow;

  const DdsOrderLine({
    this.orderNumber = '',
    this.lineNumber = '',
    this.customerItemReference = '',
    this.quantity = 1,
    this.customerDescription = '',
    this.remarks = '',
    this.sourceSheet,
    this.sourceRow,
  });

  Map<String, dynamic> toJson() => {
        'orderNumber': orderNumber,
        'lineNumber': lineNumber,
        'customerItemReference': customerItemReference,
        'quantity': quantity,
        'customerDescription': customerDescription,
        'remarks': remarks,
        if (sourceSheet != null) 'sourceSheet': sourceSheet,
        if (sourceRow != null) 'sourceRow': sourceRow,
      };

  factory DdsOrderLine.fromJson(Map<String, dynamic> json) {
    return DdsOrderLine(
      orderNumber: json['orderNumber'] as String? ?? '',
      lineNumber: json['lineNumber'] as String? ?? '',
      customerItemReference: json['customerItemReference'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      customerDescription: json['customerDescription'] as String? ?? '',
      remarks: json['remarks'] as String? ?? '',
      sourceSheet: json['sourceSheet'] as String?,
      sourceRow: (json['sourceRow'] as num?)?.toInt(),
    );
  }

  DdsOrderLine copyWith({
    String? orderNumber,
    String? lineNumber,
    String? customerItemReference,
    int? quantity,
    String? customerDescription,
    String? remarks,
    String? sourceSheet,
    int? sourceRow,
  }) {
    return DdsOrderLine(
      orderNumber: orderNumber ?? this.orderNumber,
      lineNumber: lineNumber ?? this.lineNumber,
      customerItemReference: customerItemReference ?? this.customerItemReference,
      quantity: quantity ?? this.quantity,
      customerDescription: customerDescription ?? this.customerDescription,
      remarks: remarks ?? this.remarks,
      sourceSheet: sourceSheet ?? this.sourceSheet,
      sourceRow: sourceRow ?? this.sourceRow,
    );
  }
}

/// Reference pointing to an immutable CMS DSF template in the application library.
@immutable
class DdsTemplateReference {
  final String templateId;
  final String templateCategory;
  final String baselineFileName;
  final String? templateFingerprint;

  const DdsTemplateReference({
    required this.templateId,
    this.templateCategory = 'trunking_accessories',
    required this.baselineFileName,
    this.templateFingerprint,
  });

  Map<String, dynamic> toJson() => {
        'templateId': templateId,
        'templateCategory': templateCategory,
        'baselineFileName': baselineFileName,
        if (templateFingerprint != null) 'templateFingerprint': templateFingerprint,
      };

  factory DdsTemplateReference.fromJson(Map<String, dynamic> json) {
    return DdsTemplateReference(
      templateId: json['templateId'] as String? ?? '',
      templateCategory: json['templateCategory'] as String? ?? 'trunking_accessories',
      baselineFileName: json['baselineFileName'] as String? ?? '',
      templateFingerprint: json['templateFingerprint'] as String?,
    );
  }

  DdsTemplateReference copyWith({
    String? templateId,
    String? templateCategory,
    String? baselineFileName,
    String? templateFingerprint,
  }) {
    return DdsTemplateReference(
      templateId: templateId ?? this.templateId,
      templateCategory: templateCategory ?? this.templateCategory,
      baselineFileName: baselineFileName ?? this.baselineFileName,
      templateFingerprint: templateFingerprint ?? this.templateFingerprint,
    );
  }
}

/// Parametric cover options and placement state for this product instance.
@immutable
class DdsCoverConfig {
  final bool included;
  final double flangeDepthMm;
  final String placementMode3D; // 'snappedToBase', 'exploded', 'besideBase'
  final double clearanceOffsetMm;
  final double snappedElevationZ;
  final CadPoint3D customOffset3D;

  const DdsCoverConfig({
    this.included = true,
    this.flangeDepthMm = 12.0,
    this.placementMode3D = 'snappedToBase',
    this.clearanceOffsetMm = 2.0,
    this.snappedElevationZ = 5.0,
    this.customOffset3D = const CadPoint3D(0.0, 0.0, 0.0),
  });

  Map<String, dynamic> toJson() => {
        'included': included,
        'flangeDepthMm': flangeDepthMm,
        'placementMode3D': placementMode3D,
        'clearanceOffsetMm': clearanceOffsetMm,
        'snappedElevationZ': snappedElevationZ,
        'customOffset3D': {
          'x': customOffset3D.x,
          'y': customOffset3D.y,
          'z': customOffset3D.z,
        },
      };

  factory DdsCoverConfig.fromJson(Map<String, dynamic> json) {
    final offMap = json['customOffset3D'] as Map<String, dynamic>?;
    return DdsCoverConfig(
      included: json['included'] as bool? ?? true,
      flangeDepthMm: (json['flangeDepthMm'] as num?)?.toDouble() ?? 12.0,
      placementMode3D: json['placementMode3D'] as String? ?? 'snappedToBase',
      clearanceOffsetMm: (json['clearanceOffsetMm'] as num?)?.toDouble() ?? 2.0,
      snappedElevationZ: (json['snappedElevationZ'] as num?)?.toDouble() ?? 5.0,
      customOffset3D: offMap != null
          ? CadPoint3D(
              (offMap['x'] as num).toDouble(),
              (offMap['y'] as num).toDouble(),
              (offMap['z'] as num).toDouble(),
            )
          : const CadPoint3D(0.0, 0.0, 0.0),
    );
  }

  DdsCoverConfig copyWith({
    bool? included,
    double? flangeDepthMm,
    String? placementMode3D,
    double? clearanceOffsetMm,
    double? snappedElevationZ,
    CadPoint3D? customOffset3D,
  }) {
    return DdsCoverConfig(
      included: included ?? this.included,
      flangeDepthMm: flangeDepthMm ?? this.flangeDepthMm,
      placementMode3D: placementMode3D ?? this.placementMode3D,
      clearanceOffsetMm: clearanceOffsetMm ?? this.clearanceOffsetMm,
      snappedElevationZ: snappedElevationZ ?? this.snappedElevationZ,
      customOffset3D: customOffset3D ?? this.customOffset3D,
    );
  }
}

/// Calculated physical sheet metal takeoff (surface area and estimated mass).
@immutable
class DdsCalculatedTakeoff {
  final double blankSurfaceAreaM2;
  final double estimatedNetWeightKg;

  const DdsCalculatedTakeoff({
    this.blankSurfaceAreaM2 = 0.0,
    this.estimatedNetWeightKg = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'blankSurfaceAreaM2': blankSurfaceAreaM2,
        'estimatedNetWeightKg': estimatedNetWeightKg,
      };

  factory DdsCalculatedTakeoff.fromJson(Map<String, dynamic> json) {
    return DdsCalculatedTakeoff(
      blankSurfaceAreaM2: (json['blankSurfaceAreaM2'] as num?)?.toDouble() ?? 0.0,
      estimatedNetWeightKg: (json['estimatedNetWeightKg'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Authoritative product instance storing parameters, template references, and order info.
@immutable
class DdsProductInstance {
  final String instanceId;
  final String productName;
  final String productCode;
  final DdsOrderLine? orderLine;
  final DdsTemplateReference templateReference;
  final Map<String, double> instanceParameters;
  final DdsCoverConfig coverConfiguration;
  final DdsCalculatedTakeoff? calculatedTakeoff;
  final String material;
  final String finish;
  final String notes;

  const DdsProductInstance({
    required this.instanceId,
    required this.productName,
    this.productCode = '',
    this.orderLine,
    required this.templateReference,
    this.instanceParameters = const {},
    this.coverConfiguration = const DdsCoverConfig(),
    this.calculatedTakeoff,
    this.material = 'Pre-Galvanized Steel DX51D+Z275',
    this.finish = 'Natural Mill Galvanized (Z275)',
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'productName': productName,
        'productCode': productCode,
        if (orderLine != null) 'orderLine': orderLine!.toJson(),
        'templateReference': templateReference.toJson(),
        'instanceParameters': instanceParameters,
        'coverConfiguration': coverConfiguration.toJson(),
        if (calculatedTakeoff != null) 'calculatedTakeoff': calculatedTakeoff!.toJson(),
        'material': material,
        'finish': finish,
        'notes': notes,
      };

  factory DdsProductInstance.fromJson(Map<String, dynamic> json) {
    final rawParams = json['instanceParameters'] as Map<String, dynamic>? ?? {};
    final params = rawParams.map((k, v) => MapEntry(k, (v as num).toDouble()));

    return DdsProductInstance(
      instanceId: json['instanceId'] as String? ?? 'inst_${DateTime.now().millisecondsSinceEpoch}',
      productName: json['productName'] as String? ?? '',
      productCode: json['productCode'] as String? ?? '',
      orderLine: json['orderLine'] != null
          ? DdsOrderLine.fromJson(json['orderLine'] as Map<String, dynamic>)
          : null,
      templateReference: DdsTemplateReference.fromJson(
        json['templateReference'] as Map<String, dynamic>? ?? {},
      ),
      instanceParameters: params,
      coverConfiguration: json['coverConfiguration'] != null
          ? DdsCoverConfig.fromJson(json['coverConfiguration'] as Map<String, dynamic>)
          : const DdsCoverConfig(),
      calculatedTakeoff: json['calculatedTakeoff'] != null
          ? DdsCalculatedTakeoff.fromJson(json['calculatedTakeoff'] as Map<String, dynamic>)
          : null,
      material: json['material'] as String? ?? 'Pre-Galvanized Steel DX51D+Z275',
      finish: json['finish'] as String? ?? 'Natural Mill Galvanized (Z275)',
      notes: json['notes'] as String? ?? '',
    );
  }

  DdsProductInstance copyWith({
    String? instanceId,
    String? productName,
    String? productCode,
    DdsOrderLine? orderLine,
    DdsTemplateReference? templateReference,
    Map<String, double>? instanceParameters,
    DdsCoverConfig? coverConfiguration,
    DdsCalculatedTakeoff? calculatedTakeoff,
    String? material,
    String? finish,
    String? notes,
  }) {
    return DdsProductInstance(
      instanceId: instanceId ?? this.instanceId,
      productName: productName ?? this.productName,
      productCode: productCode ?? this.productCode,
      orderLine: orderLine ?? this.orderLine,
      templateReference: templateReference ?? this.templateReference,
      instanceParameters: instanceParameters ?? this.instanceParameters,
      coverConfiguration: coverConfiguration ?? this.coverConfiguration,
      calculatedTakeoff: calculatedTakeoff ?? this.calculatedTakeoff,
      material: material ?? this.material,
      finish: finish ?? this.finish,
      notes: notes ?? this.notes,
    );
  }
}
