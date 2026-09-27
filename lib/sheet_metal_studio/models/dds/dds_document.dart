// =============================================================================
// dds_document.dart
//
// Root Technical Data Sheet (.dds) Document Model.
// Complete, portable submittal package containing:
// 1. Header (Format, schema version, generator, timestamps)
// 2. Project Document Control (Client, Consultant, Contractor, Rev, Status)
// 3. Order Metadata (Order No, source info from Excel/Manual, Total Qty)
// 4. Product Instances (Engineering parameters, template refs, cover states)
// 5. Sheets (Cover schedule page, individual product sheets, annotations)
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dds_product_instance.dart';
import 'dds_sheet.dart';

/// Metadata header identifying the file format and schema version.
@immutable
class DdsHeader {
  final String format; // 'TruFold_DDS'
  final int version; // 1
  final String generator; // 'TruFold Studio 2.0'
  final String createdAt;
  final String modifiedAt;

  const DdsHeader({
    this.format = 'TruFold_DDS',
    this.version = 1,
    this.generator = 'TruFold Studio 2.0',
    required this.createdAt,
    required this.modifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'format': format,
        'version': version,
        'generator': generator,
        'createdAt': createdAt,
        'modifiedAt': modifiedAt,
      };

  factory DdsHeader.fresh() {
    final nowStr = DateTime.now().toIso8601String();
    return DdsHeader(createdAt: nowStr, modifiedAt: nowStr);
  }

  factory DdsHeader.fromJson(Map<String, dynamic> json) {
    return DdsHeader(
      format: json['format'] as String? ?? 'TruFold_DDS',
      version: (json['version'] as num?)?.toInt() ?? 1,
      generator: json['generator'] as String? ?? 'TruFold Studio 2.0',
      createdAt: json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      modifiedAt: json['modifiedAt'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}

/// Commercial order metadata imported from Excel or entered manually.
@immutable
class DdsOrderInfo {
  final String orderNumber;
  final String orderDate;
  final String sourceType; // 'excel' or 'manual'
  final String? sourceFileName;
  final int totalOrderQuantity;

  const DdsOrderInfo({
    this.orderNumber = '',
    this.orderDate = '',
    this.sourceType = 'manual',
    this.sourceFileName,
    this.totalOrderQuantity = 0,
  });

  Map<String, dynamic> toJson() => {
        'orderNumber': orderNumber,
        'orderDate': orderDate,
        'sourceType': sourceType,
        if (sourceFileName != null) 'sourceFileName': sourceFileName,
        'totalOrderQuantity': totalOrderQuantity,
      };

  factory DdsOrderInfo.fromJson(Map<String, dynamic> json) {
    return DdsOrderInfo(
      orderNumber: json['orderNumber'] as String? ?? '',
      orderDate: json['orderDate'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? 'manual',
      sourceFileName: json['sourceFileName'] as String?,
      totalOrderQuantity: (json['totalOrderQuantity'] as num?)?.toInt() ?? 0,
    );
  }

  DdsOrderInfo copyWith({
    String? orderNumber,
    String? orderDate,
    String? sourceType,
    String? sourceFileName,
    int? totalOrderQuantity,
  }) {
    return DdsOrderInfo(
      orderNumber: orderNumber ?? this.orderNumber,
      orderDate: orderDate ?? this.orderDate,
      sourceType: sourceType ?? this.sourceType,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      totalOrderQuantity: totalOrderQuantity ?? this.totalOrderQuantity,
    );
  }
}

/// Project identification and formal ISO 7200 document-control metadata.
@immutable
class DdsProjectInfo {
  final String documentTitle;
  final String documentNumber;
  final String revision;
  final String status; // 'For Approval', 'Approved', 'Preliminary', 'As Built'
  final String projectName;
  final String client;
  final String consultant;
  final String contractor;
  final String preparedBy;
  final String designedBy;
  final String drawnBy;
  final String checkedBy;
  final String approvedBy;
  final String issueDate;
  final String designedDate;
  final String drawnDate;
  final String checkedDate;
  final String approvedDate;
  final DdsOrderInfo? orderInfo;
  final List<String> generalNotes;

  const DdsProjectInfo({
    this.documentTitle = 'Technical Data Sheet Package',
    this.documentNumber = 'TFS-TDS-001',
    this.revision = '00',
    this.status = 'For Approval',
    this.projectName = '',
    this.client = '',
    this.consultant = '',
    this.contractor = '',
    this.preparedBy = '',
    this.designedBy = 'Amir Khan',
    this.drawnBy = 'Sandeep',
    this.checkedBy = 'Nasser Anani',
    this.approvedBy = 'Consultant QA/QC',
    this.issueDate = '',
    this.designedDate = '',
    this.drawnDate = '',
    this.checkedDate = '',
    this.approvedDate = '',
    this.orderInfo,
    this.generalNotes = const [
      'All trunking and fittings manufactured in strict accordance with BS EN 50085-1.',
      'Material: Pre-galvanized mild steel sheet to BS EN 10346 Grade DX51D + Z275.',
      'All dimensions are nominal internal duct dimensions in millimeters unless noted otherwise.',
      'Integral coupler flaps feature pre-punched holes/slots to accept standard M6 fasteners.',
    ],
  });

  /// Formats the current date as DD/MM/YYYY
  static String get formattedToday {
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    return '$day/$month/${now.year}';
  }

  String get effectiveIssueDate => issueDate.isNotEmpty ? issueDate : formattedToday;
  String get effectiveDesignedDate => designedDate.isNotEmpty ? designedDate : effectiveIssueDate;
  String get effectiveDrawnDate => drawnDate.isNotEmpty ? drawnDate : effectiveIssueDate;
  String get effectiveCheckedDate => checkedDate.isNotEmpty ? checkedDate : formattedToday;
  String get effectiveApprovedDate => approvedDate.isNotEmpty ? approvedDate : formattedToday;

  Map<String, dynamic> toJson() => {
        'documentTitle': documentTitle,
        'documentNumber': documentNumber,
        'revision': revision,
        'status': status,
        'projectName': projectName,
        'client': client,
        'consultant': consultant,
        'contractor': contractor,
        'preparedBy': preparedBy,
        'designedBy': designedBy,
        'drawnBy': drawnBy,
        'checkedBy': checkedBy,
        'approvedBy': approvedBy,
        'issueDate': issueDate,
        'designedDate': designedDate,
        'drawnDate': drawnDate,
        'checkedDate': checkedDate,
        'approvedDate': approvedDate,
        if (orderInfo != null) 'orderInfo': orderInfo!.toJson(),
        'generalNotes': generalNotes,
      };

  factory DdsProjectInfo.fromJson(Map<String, dynamic> json) {
    final rawNotes = json['generalNotes'] as List<dynamic>? ?? [];
    return DdsProjectInfo(
      documentTitle: json['documentTitle'] as String? ?? 'Technical Data Sheet Package',
      documentNumber: json['documentNumber'] as String? ?? 'TFS-TDS-001',
      revision: json['revision'] as String? ?? '00',
      status: json['status'] as String? ?? 'For Approval',
      projectName: json['projectName'] as String? ?? '',
      client: json['client'] as String? ?? '',
      consultant: json['consultant'] as String? ?? '',
      contractor: json['contractor'] as String? ?? '',
      preparedBy: json['preparedBy'] as String? ?? '',
      designedBy: json['designedBy'] as String? ?? (json['preparedBy'] as String? ?? 'Amir Khan'),
      drawnBy: json['drawnBy'] as String? ?? (json['preparedBy'] as String? ?? 'Sandeep'),
      checkedBy: json['checkedBy'] as String? ?? 'Nasser Anani',
      approvedBy: json['approvedBy'] as String? ?? 'Consultant QA/QC',
      issueDate: json['issueDate'] as String? ?? formattedToday,
      designedDate: json['designedDate'] as String? ?? (json['issueDate'] as String? ?? formattedToday),
      drawnDate: json['drawnDate'] as String? ?? (json['issueDate'] as String? ?? formattedToday),
      checkedDate: json['checkedDate'] as String? ?? formattedToday,
      approvedDate: json['approvedDate'] as String? ?? formattedToday,
      orderInfo: json['orderInfo'] != null
          ? DdsOrderInfo.fromJson(json['orderInfo'] as Map<String, dynamic>)
          : null,
      generalNotes: rawNotes.map((e) => e.toString()).toList(),
    );
  }

  DdsProjectInfo copyWith({
    String? documentTitle,
    String? documentNumber,
    String? revision,
    String? status,
    String? projectName,
    String? client,
    String? consultant,
    String? contractor,
    String? preparedBy,
    String? designedBy,
    String? drawnBy,
    String? checkedBy,
    String? approvedBy,
    String? issueDate,
    String? designedDate,
    String? drawnDate,
    String? checkedDate,
    String? approvedDate,
    DdsOrderInfo? orderInfo,
    List<String>? generalNotes,
  }) {
    return DdsProjectInfo(
      documentTitle: documentTitle ?? this.documentTitle,
      documentNumber: documentNumber ?? this.documentNumber,
      revision: revision ?? this.revision,
      status: status ?? this.status,
      projectName: projectName ?? this.projectName,
      client: client ?? this.client,
      consultant: consultant ?? this.consultant,
      contractor: contractor ?? this.contractor,
      preparedBy: preparedBy ?? this.preparedBy,
      designedBy: designedBy ?? this.designedBy,
      drawnBy: drawnBy ?? this.drawnBy,
      checkedBy: checkedBy ?? this.checkedBy,
      approvedBy: approvedBy ?? this.approvedBy,
      issueDate: issueDate ?? this.issueDate,
      designedDate: designedDate ?? this.designedDate,
      drawnDate: drawnDate ?? this.drawnDate,
      checkedDate: checkedDate ?? this.checkedDate,
      approvedDate: approvedDate ?? this.approvedDate,
      orderInfo: orderInfo ?? this.orderInfo,
      generalNotes: generalNotes ?? this.generalNotes,
    );
  }
}

/// The root Technical Data Sheet (.dds) document model.
@immutable
class DdsDocument {
  final DdsHeader ddsHeader;
  final DdsProjectInfo projectInfo;
  final List<DdsProductInstance> productInstances;
  final List<DdsSheet> sheets;

  const DdsDocument({
    required this.ddsHeader,
    required this.projectInfo,
    this.productInstances = const [],
    this.sheets = const [],
  });

  /// Factory creating an empty, fresh DDS document with a default cover page.
  factory DdsDocument.create({
    String documentTitle = 'Technical Data Sheet Submittal',
    String documentNumber = 'TFS-TDS-001',
    String projectName = '',
    String client = '',
    String consultant = '',
    String contractor = '',
    String preparedBy = '',
  }) {
    final nowStr = DateTime.now().toIso8601String();
    return DdsDocument(
      ddsHeader: DdsHeader(createdAt: nowStr, modifiedAt: nowStr),
      projectInfo: DdsProjectInfo(
        documentTitle: documentTitle,
        documentNumber: documentNumber,
        projectName: projectName,
        client: client,
        consultant: consultant,
        contractor: contractor,
        preparedBy: preparedBy.isNotEmpty ? preparedBy : 'Amir Khan',
        designedBy: 'Amir Khan',
        drawnBy: 'Sandeep',
        checkedBy: 'Nasser Anani',
        approvedBy: 'Consultant QA/QC',
        issueDate: DdsProjectInfo.formattedToday,
        designedDate: DdsProjectInfo.formattedToday,
        drawnDate: DdsProjectInfo.formattedToday,
        checkedDate: DdsProjectInfo.formattedToday,
        approvedDate: DdsProjectInfo.formattedToday,
      ),
      productInstances: const [],
      sheets: const [
        DdsSheet(
          sheetId: 'sheet_cover',
          sheetType: DdsSheetType.coverSchedule,
          sheetNumber: 1,
          title: 'Submittal Transmittal & Product Schedule',
        ),
      ],
    );
  }

  /// Total sheet count in the binder.
  int get totalSheets => sheets.length;

  /// The primary cover / schedule sheet in the document.
  DdsSheet get coverScheduleSheet =>
      sheets.firstWhere((s) => s.isCoverPage, orElse: () => sheets.first);

  /// Looks up a product instance by its unique [instanceId].
  DdsProductInstance? findInstance(String? instanceId) {
    if (instanceId == null) return null;
    for (final inst in productInstances) {
      if (inst.instanceId == instanceId) return inst;
    }
    return null;
  }

  /// Looks up a sheet by its unique [sheetId].
  DdsSheet? findSheet(String sheetId) {
    for (final sh in sheets) {
      if (sh.sheetId == sheetId) return sh;
    }
    return null;
  }

  /// Adds a new product instance and corresponding sheet.
  DdsDocument addProductInstance(
    DdsProductInstance instance, {
    String? sheetTitle,
  }) {
    final updatedInstances = [...productInstances, instance];
    final nextSheetNum = sheets.length + 1;
    final newSheet = DdsSheet(
      sheetId: 'sheet_${instance.instanceId}',
      sheetType: DdsSheetType.productSheet,
      sheetNumber: nextSheetNum,
      title: sheetTitle ?? instance.productName,
      productInstanceId: instance.instanceId,
    );
    final updatedSheets = [...sheets, newSheet];

    final doc = copyWith(
      productInstances: updatedInstances,
      sheets: updatedSheets,
    );
    return doc.updateToc();
  }

  /// Updates an existing product instance by ID.
  DdsDocument updateProductInstance(DdsProductInstance updatedInstance) {
    final updatedInstances = productInstances.map((inst) {
      return inst.instanceId == updatedInstance.instanceId ? updatedInstance : inst;
    }).toList();
    final doc = copyWith(productInstances: updatedInstances);
    return doc.updateToc();
  }

  /// Removes a sheet and its associated product instance if no longer used.
  DdsDocument removeSheet(String sheetId) {
    final targetSheet = findSheet(sheetId);
    if (targetSheet == null) return this;

    final updatedSheets = sheets.where((s) => s.sheetId != sheetId).toList();
    // Re-number sheets sequentially
    for (int i = 0; i < updatedSheets.length; i++) {
      updatedSheets[i] = updatedSheets[i].copyWith(sheetNumber: i + 1);
    }

    // Check if instance is still referenced by other sheets
    final instId = targetSheet.productInstanceId;
    List<DdsProductInstance> updatedInstances = productInstances;
    if (instId != null) {
      final isStillUsed = updatedSheets.any((s) => s.productInstanceId == instId);
      if (!isStillUsed) {
        updatedInstances = productInstances.where((i) => i.instanceId != instId).toList();
      }
    }

    final doc = copyWith(
      productInstances: updatedInstances,
      sheets: updatedSheets,
    );
    return doc.updateToc();
  }

  /// Automatically regenerates the Table of Contents / Product Schedule on the Cover Sheet.
  DdsDocument updateToc() {
    final coverIdx = sheets.indexWhere((s) => s.isCoverPage);
    if (coverIdx == -1) return this;

    final tocEntries = <DdsTocEntry>[];
    for (final sh in sheets) {
      if (sh.isCoverPage) continue;
      final inst = findInstance(sh.productInstanceId);
      if (inst != null) {
        final p = inst.instanceParameters;
        final w1 = p['port1_width'] ?? p['width'] ?? 100.0;
        final h1 = p['port1_height'] ?? p['height'] ?? 100.0;
        final w2 = p['port2_width'];
        final h2 = p['port2_height'];
        final configStr = (w2 != null && h2 != null)
            ? 'W1=${w1.toInt()} H1=${h1.toInt()} / W2=${w2.toInt()} H2=${h2.toInt()}'
            : '${w1.toInt()} × ${h1.toInt()} mm';

        tocEntries.add(DdsTocEntry(
          sheetNumber: sh.sheetNumber,
          orderLine: inst.orderLine?.lineNumber ?? '',
          customerRef: inst.orderLine?.customerItemReference.isNotEmpty == true
              ? inst.orderLine!.customerItemReference
              : inst.productCode,
          productName: inst.productName,
          configuration: configStr,
          quantity: inst.orderLine?.quantity ?? 1,
          status: 'Resolved',
        ));
      }
    }

    final updatedCover = sheets[coverIdx].copyWith(tableOfContents: tocEntries);
    final updatedSheets = List<DdsSheet>.from(sheets);
    updatedSheets[coverIdx] = updatedCover;

    return copyWith(sheets: updatedSheets);
  }

  DdsDocument copyWith({
    DdsHeader? ddsHeader,
    DdsProjectInfo? projectInfo,
    List<DdsProductInstance>? productInstances,
    List<DdsSheet>? sheets,
  }) {
    return DdsDocument(
      ddsHeader: ddsHeader ??
          this.ddsHeader.copyWith(modifiedAt: DateTime.now().toIso8601String()),
      projectInfo: projectInfo ?? this.projectInfo,
      productInstances: productInstances ?? this.productInstances,
      sheets: sheets ?? this.sheets,
    );
  }

  Map<String, dynamic> toJson() => {
        'ddsHeader': ddsHeader.toJson(),
        'projectInfo': projectInfo.toJson(),
        'productInstances': productInstances.map((i) => i.toJson()).toList(),
        'sheets': sheets.map((s) => s.toJson()).toList(),
      };

  factory DdsDocument.fromJson(Map<String, dynamic> json) {
    final rawHeader = json['ddsHeader'] as Map<String, dynamic>? ?? {};
    final rawProject = json['projectInfo'] as Map<String, dynamic>? ?? {};
    final rawInstances = json['productInstances'] as List<dynamic>? ?? [];
    final rawSheets = json['sheets'] as List<dynamic>? ?? [];

    return DdsDocument(
      ddsHeader: DdsHeader.fromJson(rawHeader),
      projectInfo: DdsProjectInfo.fromJson(rawProject),
      productInstances: rawInstances
          .map((i) => DdsProductInstance.fromJson(i as Map<String, dynamic>))
          .toList(),
      sheets: rawSheets
          .map((s) => DdsSheet.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  String toJsonString({bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }
}

extension DdsHeaderExt on DdsHeader {
  DdsHeader copyWith({
    String? format,
    int? version,
    String? generator,
    String? createdAt,
    String? modifiedAt,
  }) {
    return DdsHeader(
      format: format ?? this.format,
      version: version ?? this.version,
      generator: generator ?? this.generator,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }
}
