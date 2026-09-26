// =============================================================================
// excel_order_importer.dart
//
// Technical Data Sheet (TDS) Excel Order Import Engine.
// Imports customer order workbooks (.xlsx) and generates structured, standalone
// .dds documents without maintaining a live dependency on the source spreadsheet.
//
// Features:
// 1. Workbook preview (sheets, headers, sample rows).
// 2. Flexible, heuristic column mapping (Order, Line, Item, Desc, W, H, Qty, etc.).
// 3. Intelligent template resolution with fallback dimension regex extraction.
// 4. Standalone DDS generation with populated Table of Contents and individual sheets.
// 5. Complete import summary and exception tracking (unresolved/skipped items).
// =============================================================================

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import '../../models/dds/dds_document.dart';
import '../../models/dds/dds_product_instance.dart';
import '../../models/dds/dds_sheet.dart';
import 'dds_template_resolver.dart';

/// Heuristic column mapping configuration for spreadsheet import.
@immutable
class ExcelColumnMapping {
  final int orderNumberCol;
  final int orderLineCol;
  final int customerItemRefCol;
  final int customerDescriptionCol;
  final int productTypeCol;
  final int widthCol;
  final int heightCol;
  final int branchWidthCol;
  final int branchHeightCol;
  final int lengthCol;
  final int quantityCol;
  final int remarksCol;
  final int headerRowIndex;

  const ExcelColumnMapping({
    this.orderNumberCol = -1,
    this.orderLineCol = -1,
    this.customerItemRefCol = -1,
    this.customerDescriptionCol = -1,
    this.productTypeCol = -1,
    this.widthCol = -1,
    this.heightCol = -1,
    this.branchWidthCol = -1,
    this.branchHeightCol = -1,
    this.lengthCol = -1,
    this.quantityCol = -1,
    this.remarksCol = -1,
    this.headerRowIndex = 0,
  });

  ExcelColumnMapping copyWith({
    int? orderNumberCol,
    int? orderLineCol,
    int? customerItemRefCol,
    int? customerDescriptionCol,
    int? productTypeCol,
    int? widthCol,
    int? heightCol,
    int? branchWidthCol,
    int? branchHeightCol,
    int? lengthCol,
    int? quantityCol,
    int? remarksCol,
    int? headerRowIndex,
  }) {
    return ExcelColumnMapping(
      orderNumberCol: orderNumberCol ?? this.orderNumberCol,
      orderLineCol: orderLineCol ?? this.orderLineCol,
      customerItemRefCol: customerItemRefCol ?? this.customerItemRefCol,
      customerDescriptionCol: customerDescriptionCol ?? this.customerDescriptionCol,
      productTypeCol: productTypeCol ?? this.productTypeCol,
      widthCol: widthCol ?? this.widthCol,
      heightCol: heightCol ?? this.heightCol,
      branchWidthCol: branchWidthCol ?? this.branchWidthCol,
      branchHeightCol: branchHeightCol ?? this.branchHeightCol,
      lengthCol: lengthCol ?? this.lengthCol,
      quantityCol: quantityCol ?? this.quantityCol,
      remarksCol: remarksCol ?? this.remarksCol,
      headerRowIndex: headerRowIndex ?? this.headerRowIndex,
    );
  }
}

/// Preview of a single worksheet inside an imported Excel workbook.
class ExcelSheetPreview {
  final String sheetName;
  final int totalRows;
  final int totalCols;
  final int detectedHeaderRow;
  final List<String> detectedHeaders;
  final List<List<String>> sampleRows;
  final ExcelColumnMapping suggestedMapping;

  const ExcelSheetPreview({
    required this.sheetName,
    required this.totalRows,
    required this.totalCols,
    required this.detectedHeaderRow,
    required this.detectedHeaders,
    required this.sampleRows,
    required this.suggestedMapping,
  });
}

/// Comprehensive preview of the entire Excel workbook.
class ExcelWorkbookPreview {
  final String? fileName;
  final List<String> sheetNames;
  final String defaultSheet;
  final Map<String, ExcelSheetPreview> sheets;

  const ExcelWorkbookPreview({
    this.fileName,
    required this.sheetNames,
    required this.defaultSheet,
    required this.sheets,
  });
}

/// Record of an exception or skipped row during import.
class ExcelImportRowError {
  final int rowIndex;
  final String lineIdentifier;
  final String description;
  final String reason;

  const ExcelImportRowError({
    required this.rowIndex,
    required this.lineIdentifier,
    required this.description,
    required this.reason,
  });
}

/// Summary report of the batch import operation.
class ExcelImportSummary {
  final int totalRowsDetected;
  final int templatesMatched;
  final int requireUserResolution;
  final int skippedRows;
  final List<ExcelImportRowError> errors;

  const ExcelImportSummary({
    required this.totalRowsDetected,
    required this.templatesMatched,
    required this.requireUserResolution,
    required this.skippedRows,
    this.errors = const [],
  });
}

/// The result returned when importing an Excel file into a new DDS document.
class ExcelImportResult {
  final DdsDocument document;
  final ExcelImportSummary summary;
  final List<DdsProductInstance> unresolvedInstances;

  const ExcelImportResult({
    required this.document,
    required this.summary,
    this.unresolvedInstances = const [],
  });
}

/// Engine that parses .xlsx workbooks, extracts customer order items,
/// and builds a ready-to-edit DdsDocument.
class ExcelOrderImporter {
  /// Generates a quick preview of an Excel workbook for user inspection and column mapping.
  static ExcelWorkbookPreview previewWorkbook(List<int> bytes, {String? fileName}) {
    final excel = Excel.decodeBytes(bytes);
    final sheetNames = excel.tables.keys.toList();
    final sheets = <String, ExcelSheetPreview>{};

    for (final sheetName in sheetNames) {
      final table = excel.tables[sheetName];
      if (table == null || table.rows.isEmpty) continue;

      int headerIdx = 0;
      List<String> headers = [];

      // Find the first row that looks like a header (contains non-empty string cells)
      for (int r = 0; r < table.rows.length && r < 10; r++) {
        final row = table.rows[r];
        final nonNullCells = row.where((c) => c != null && _cellToString(c.value).isNotEmpty).toList();
        if (nonNullCells.length >= 2) {
          headerIdx = r;
          headers = row.map((c) => _cellToString(c?.value)).toList();
          break;
        }
      }

      final mapping = autoDetectMapping(headers, headerRowIndex: headerIdx);

      // Collect up to 10 sample rows following the header
      final sampleRows = <List<String>>[];
      for (int r = headerIdx + 1; r < table.rows.length && sampleRows.length < 10; r++) {
        final row = table.rows[r];
        final rowStr = row.map((c) => _cellToString(c?.value)).toList();
        if (rowStr.any((s) => s.isNotEmpty)) {
          sampleRows.add(rowStr);
        }
      }

      sheets[sheetName] = ExcelSheetPreview(
        sheetName: sheetName,
        totalRows: table.maxRows,
        totalCols: table.maxColumns,
        detectedHeaderRow: headerIdx,
        detectedHeaders: headers,
        sampleRows: sampleRows,
        suggestedMapping: mapping,
      );
    }

    final defaultSheet = sheetNames.isNotEmpty ? sheetNames.first : '';
    return ExcelWorkbookPreview(
      fileName: fileName,
      sheetNames: sheetNames,
      defaultSheet: defaultSheet,
      sheets: sheets,
    );
  }

  /// Automatically infers column roles based on header names.
  static ExcelColumnMapping autoDetectMapping(
    List<String> headers, {
    int headerRowIndex = 0,
  }) {
    int orderNumberCol = -1;
    int orderLineCol = -1;
    int customerItemRefCol = -1;
    int descriptionCol = -1;
    int productTypeCol = -1;
    int widthCol = -1;
    int heightCol = -1;
    int branchWidthCol = -1;
    int branchHeightCol = -1;
    int lengthCol = -1;
    int quantityCol = -1;
    int remarksCol = -1;

    for (int col = 0; col < headers.length; col++) {
      final h = headers[col].toLowerCase().trim();
      if (h.isEmpty) continue;

      if (_matches(h, ['order no', 'po no', 'order #', 'po #', 'order number', 'purchase order'])) {
        orderNumberCol = col;
      } else if (_matches(h, ['customer item', 'item code', 'ref no', 'part no', 'item ref', 'code', 'catalog no'])) {
        customerItemRefCol = col;
      } else if (_matches(h, ['line no', 'item no', 'order line', 'line #', 'item #', 'line', 'pos', 'sr no', 's.no'])) {
        orderLineCol = col;
      } else if (_matches(h, ['description', 'item description', 'product name', 'specification', 'title'])) {
        descriptionCol = col;
      } else if (_matches(h, ['product type', 'type', 'fitting', 'accessory', 'category'])) {
        productTypeCol = col;
      } else if (_matches(h, ['branch width', 'reduced width', 'w2', 'b_width'])) {
        branchWidthCol = col;
      } else if (_matches(h, ['branch height', 'reduced height', 'h2', 'b_height'])) {
        branchHeightCol = col;
      } else if (_matches(h, ['width', 'w1', 'w (mm)', 'width mm', 'w'])) {
        widthCol = col;
      } else if (_matches(h, ['height', 'h1', 'h (mm)', 'height mm', 'depth', 'h'])) {
        heightCol = col;
      } else if (_matches(h, ['length', 'len', 'l (mm)', 'length mm', 'l'])) {
        lengthCol = col;
      } else if (_matches(h, ['quantity', 'qty', 'count', 'pcs', 'nos', 'qnty'])) {
        quantityCol = col;
      } else if (_matches(h, ['remark', 'remarks', 'notes', 'comment', 'comments'])) {
        remarksCol = col;
      }
    }

    return ExcelColumnMapping(
      orderNumberCol: orderNumberCol,
      orderLineCol: orderLineCol,
      customerItemRefCol: customerItemRefCol,
      customerDescriptionCol: descriptionCol,
      productTypeCol: productTypeCol,
      widthCol: widthCol,
      heightCol: heightCol,
      branchWidthCol: branchWidthCol,
      branchHeightCol: branchHeightCol,
      lengthCol: lengthCol,
      quantityCol: quantityCol,
      remarksCol: remarksCol,
      headerRowIndex: headerRowIndex,
    );
  }

  /// Imports an Excel workbook and produces a complete, populated DdsDocument.
  static ExcelImportResult importWorkbook({
    required List<int> bytes,
    String? sheetName,
    ExcelColumnMapping? customMapping,
    String? fileName,
    DdsProjectInfo? projectInfoOverrides,
  }) {
    final excel = Excel.decodeBytes(bytes);
    final targetSheet = sheetName ?? (excel.tables.keys.isNotEmpty ? excel.tables.keys.first : '');
    final table = excel.tables[targetSheet];

    if (table == null || table.rows.isEmpty) {
      final doc = DdsDocument.create(
        documentTitle: 'Empty Import',
        documentNumber: 'TDS-IMP-EMPTY',
      );
      return ExcelImportResult(
        document: doc,
        summary: const ExcelImportSummary(
          totalRowsDetected: 0,
          templatesMatched: 0,
          requireUserResolution: 0,
          skippedRows: 0,
        ),
      );
    }

    // Determine mapping
    final headerRowIdx = customMapping?.headerRowIndex ?? 0;
    final headers = table.rows.length > headerRowIdx
        ? table.rows[headerRowIdx].map((c) => _cellToString(c?.value)).toList()
        : <String>[];
    final mapping = customMapping ?? autoDetectMapping(headers, headerRowIndex: headerRowIdx);

    final productInstances = <DdsProductInstance>[];
    final sheets = <DdsSheet>[];
    final errors = <ExcelImportRowError>[];
    final unresolved = <DdsProductInstance>[];

    String detectedOrderNo = '';
    int totalQty = 0;
    int templatesMatched = 0;
    int requireResolution = 0;
    int skippedCount = 0;

    int itemSequence = 1;

    for (int r = mapping.headerRowIndex + 1; r < table.rows.length; r++) {
      final row = table.rows[r];
      if (row.isEmpty || row.every((c) => c == null || _cellToString(c.value).isEmpty)) {
        continue; // skip empty rows
      }

      final orderNo = _getColString(row, mapping.orderNumberCol);
      if (detectedOrderNo.isEmpty && orderNo.isNotEmpty) {
        detectedOrderNo = orderNo;
      }

      final lineNo = _getColString(row, mapping.orderLineCol, fallback: '$itemSequence');
      final custRef = _getColString(row, mapping.customerItemRefCol, fallback: 'ITEM-$itemSequence');
      final desc = _getColString(row, mapping.customerDescriptionCol);
      final pType = _getColString(row, mapping.productTypeCol);
      final remarks = _getColString(row, mapping.remarksCol);
      final qty = _getColInt(row, mapping.quantityCol, fallback: 1);

      // If description and ref are completely blank, skip row
      if (desc.isEmpty && custRef.isEmpty && pType.isEmpty) {
        skippedCount++;
        continue;
      }

      totalQty += qty;

      // Sizing overrides from columns
      final width = _getColDouble(row, mapping.widthCol);
      final height = _getColDouble(row, mapping.heightCol);
      final branchWidth = _getColDouble(row, mapping.branchWidthCol);
      final branchHeight = _getColDouble(row, mapping.branchHeightCol);
      final length = _getColDouble(row, mapping.lengthCol);

      // Match template
      final searchText = '$pType $desc $custRef'.trim();
      var templateRef = DdsTemplateResolver.matchByDescription(searchText);

      bool isResolved = templateRef != null;
      if (!isResolved) {
        // Fallback to straight reducer or 90 bend if unknown
        templateRef = DdsTemplateResolver.createReference('trunking_bend_90');
        requireResolution++;
      } else {
        templatesMatched++;
      }

      // Extract parameter dictionary
      final params = <String, double>{};
      if (width != null) params['width'] = width;
      if (height != null) params['height'] = height;
      if (branchWidth != null) params['branch_width'] = branchWidth;
      if (branchHeight != null) params['branch_height'] = branchHeight;
      if (length != null) params['length'] = length;

      // Extract regex dimensions from description if columns were missing
      _extractDimensionsFromText(searchText, params);

      final instanceId = 'inst_${itemSequence.toString().padLeft(3, '0')}';
      final orderLine = DdsOrderLine(
        orderNumber: orderNo.isNotEmpty ? orderNo : detectedOrderNo,
        lineNumber: lineNo,
        customerItemReference: custRef,
        quantity: qty,
        customerDescription: desc.isNotEmpty ? desc : custRef,
        remarks: remarks,
        sourceSheet: targetSheet,
        sourceRow: r + 1,
      );

      final productName = desc.isNotEmpty
          ? desc
          : (DdsTemplateResolver.templateDisplayNames[templateRef.templateId] ?? custRef);

      final instance = DdsProductInstance(
        instanceId: instanceId,
        productName: productName,
        productCode: custRef,
        orderLine: orderLine,
        templateReference: templateRef,
        instanceParameters: params,
        coverConfiguration: const DdsCoverConfig(
          included: true,
          placementMode3D: 'exploded',
        ),
      );

      productInstances.add(instance);
      if (!isResolved) {
        unresolved.add(instance);
        errors.add(ExcelImportRowError(
          rowIndex: r + 1,
          lineIdentifier: lineNo,
          description: desc,
          reason: 'Could not automatically match description to a built-in CMS template.',
        ));
      }

      // Create corresponding product sheet (Sheet 1 is reserved for Cover)
      final sheetNumber = itemSequence + 1;
      sheets.add(DdsSheet(
        sheetId: 'sheet_$instanceId',
        sheetType: DdsSheetType.productSheet,
        sheetNumber: sheetNumber,
        title: '$custRef — $productName',
        productInstanceId: instanceId,
      ));

      itemSequence++;
    }

    // Build project info & order info
    final orderInfo = DdsOrderInfo(
      orderNumber: detectedOrderNo.isNotEmpty ? detectedOrderNo : 'ORD-AUTO',
      orderDate: DateTime.now().toIso8601String().substring(0, 10),
      sourceType: 'excel',
      sourceFileName: fileName,
      totalOrderQuantity: totalQty,
    );

    final projectInfo = (projectInfoOverrides ?? const DdsProjectInfo()).copyWith(
      orderInfo: orderInfo,
      documentTitle: projectInfoOverrides?.documentTitle ?? 'Technical Data Sheet Submittal',
      documentNumber: projectInfoOverrides?.documentNumber ?? 'TDS-${detectedOrderNo.isNotEmpty ? detectedOrderNo : "SUBMITTAL"}',
    );

    // Initial Cover Sheet
    final coverSheet = DdsSheet(
      sheetId: 'sheet_cover',
      sheetType: DdsSheetType.coverSchedule,
      sheetNumber: 1,
      title: 'Transmittal & Product Schedule',
      viewSettings: const DdsViewSettings(paperSize: 'A4_Landscape'),
    );

    var ddsDoc = DdsDocument(
      ddsHeader: DdsHeader.fresh(),
      projectInfo: projectInfo,
      productInstances: productInstances,
      sheets: [coverSheet, ...sheets],
    );

    // Populate Table of Contents / Product Schedule
    ddsDoc = ddsDoc.updateToc();

    final summary = ExcelImportSummary(
      totalRowsDetected: productInstances.length + skippedCount,
      templatesMatched: templatesMatched,
      requireUserResolution: requireResolution,
      skippedRows: skippedCount,
      errors: errors,
    );

    return ExcelImportResult(
      document: ddsDoc,
      summary: summary,
      unresolvedInstances: unresolved,
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Methods
  // ---------------------------------------------------------------------------

  static bool _matches(String text, List<String> patterns) {
    for (final p in patterns) {
      if (text == p || text.contains(p)) return true;
    }
    return false;
  }

  static String _cellToString(CellValue? cell) {
    if (cell == null) return '';
    if (cell is TextCellValue) return cell.value.text?.trim() ?? cell.value.toString().trim();
    if (cell is IntCellValue) return cell.value.toString();
    if (cell is DoubleCellValue) return cell.value.toString();
    if (cell is DateCellValue) {
      return cell.asDateTimeLocal().toIso8601String().substring(0, 10);
    }
    if (cell is BoolCellValue) return cell.value ? 'true' : 'false';
    if (cell is FormulaCellValue) return cell.formula;
    return cell.toString().trim();
  }

  static String _getColString(List<Data?> row, int colIndex, {String fallback = ''}) {
    if (colIndex < 0 || colIndex >= row.length) return fallback;
    final cell = row[colIndex];
    if (cell == null) return fallback;
    final s = _cellToString(cell.value);
    return s.isNotEmpty ? s : fallback;
  }

  static int _getColInt(List<Data?> row, int colIndex, {int fallback = 1}) {
    final d = _getColDouble(row, colIndex);
    return d != null ? d.round() : fallback;
  }

  static double? _getColDouble(List<Data?> row, int colIndex) {
    if (colIndex < 0 || colIndex >= row.length) return null;
    final cell = row[colIndex];
    if (cell == null) return null;
    final val = cell.value;
    if (val is IntCellValue) return val.value.toDouble();
    if (val is DoubleCellValue) return val.value;
    final str = _cellToString(val);
    final clean = str.replaceAll(RegExp(r'[^\d.-]'), '');
    return double.tryParse(clean);
  }

  /// Parses dimensions like "150x100 to 75x50" or "100x50" from free text.
  static void _extractDimensionsFromText(String text, Map<String, double> targetParams) {
    // 4-part dimension: e.g. "150x100 to 75x50" or "150x100x75x50"
    final fourPart = RegExp(r'(\d+)\s*[xX*×/]\s*(\d+)\s*(?:to|-|x|X|\/)\s*(\d+)\s*[xX*×/]\s*(\d+)');
    final match4 = fourPart.firstMatch(text);
    if (match4 != null) {
      targetParams['port1_width'] ??= double.tryParse(match4.group(1)!) ?? 100.0;
      targetParams['port1_height'] ??= double.tryParse(match4.group(2)!) ?? 100.0;
      targetParams['port2_width'] ??= double.tryParse(match4.group(3)!) ?? 50.0;
      targetParams['port2_height'] ??= double.tryParse(match4.group(4)!) ?? 50.0;
      return;
    }

    // 2-part dimension: e.g. "150x100" or "150 × 100"
    final twoPart = RegExp(r'(\d+)\s*[xX*×/]\s*(\d+)');
    final match2 = twoPart.firstMatch(text);
    if (match2 != null) {
      final w = double.tryParse(match2.group(1)!) ?? 100.0;
      final h = double.tryParse(match2.group(2)!) ?? 100.0;
      targetParams['width'] ??= w;
      targetParams['height'] ??= h;
      targetParams['port1_width'] ??= w;
      targetParams['port1_height'] ??= h;
    }
  }
}
