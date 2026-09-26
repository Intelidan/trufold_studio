import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/excel_order_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Excel Order Importer Tests', () {
    test('1. Previews workbook and auto-detects column headers', () {
      final excel = Excel.createExcel();
      final sheet = excel['Orders'];

      // Header row
      sheet.appendRow([
        TextCellValue('Order No'),
        TextCellValue('Line No'),
        TextCellValue('Item Code'),
        TextCellValue('Description'),
        TextCellValue('Width'),
        TextCellValue('Height'),
        TextCellValue('Quantity'),
        TextCellValue('Remarks'),
      ]);

      // Row 1: Equal Tee
      sheet.appendRow([
        TextCellValue('PO-9901'),
        TextCellValue('1'),
        TextCellValue('TEE-100'),
        TextCellValue('Cable Trunking Equal Tee 100x100'),
        IntCellValue(100),
        IntCellValue(100),
        IntCellValue(20),
        TextCellValue('Zone A'),
      ]);

      // Row 2: Reducer with regex dimension extraction in description
      sheet.appendRow([
        TextCellValue('PO-9901'),
        TextCellValue('2'),
        TextCellValue('RED-150-75'),
        TextCellValue('Straight Reducer 150x100 to 75x50'),
        TextCellValue(''),
        TextCellValue(''),
        IntCellValue(10),
        TextCellValue('Shaft B'),
      ]);

      // Row 3: 90 Inside Riser
      sheet.appendRow([
        TextCellValue('PO-9901'),
        TextCellValue('3'),
        TextCellValue('RISER-90'),
        TextCellValue('90 deg inside riser 100x100'),
        IntCellValue(100),
        IntCellValue(100),
        IntCellValue(5),
        TextCellValue('Vertical run'),
      ]);

      final bytes = excel.save()!;
      final preview = ExcelOrderImporter.previewWorkbook(bytes, fileName: 'Hospital_Order.xlsx');

      expect(preview.sheetNames.contains('Orders'), isTrue);
      final ordersPreview = preview.sheets['Orders'];
      expect(ordersPreview, isNotNull);
      expect(ordersPreview!.detectedHeaders.length, greaterThanOrEqualTo(8));
      expect(ordersPreview.suggestedMapping.orderNumberCol, equals(0));
      expect(ordersPreview.suggestedMapping.customerDescriptionCol, equals(3));
      expect(ordersPreview.suggestedMapping.quantityCol, equals(6));

      // 2. Perform full import into DdsDocument
      final importResult = ExcelOrderImporter.importWorkbook(
        bytes: bytes,
        sheetName: 'Orders',
        fileName: 'Hospital_Order.xlsx',
      );

      final doc = importResult.document;
      final summary = importResult.summary;

      expect(summary.totalRowsDetected, equals(3));
      expect(summary.templatesMatched, equals(3));
      expect(summary.requireUserResolution, equals(0));

      expect(doc.projectInfo.orderInfo?.orderNumber, equals('PO-9901'));
      expect(doc.projectInfo.orderInfo?.totalOrderQuantity, equals(35));
      expect(doc.productInstances.length, equals(3));

      // Verify Reducer 4-part dimension regex extraction
      final reducerInstance = doc.productInstances[1];
      expect(reducerInstance.templateReference.templateId, equals('trunking_reducer'));
      expect(reducerInstance.instanceParameters['port1_width'], equals(150.0));
      expect(reducerInstance.instanceParameters['port1_height'], equals(100.0));
      expect(reducerInstance.instanceParameters['port2_width'], equals(75.0));
      expect(reducerInstance.instanceParameters['port2_height'], equals(50.0));

      // Verify sheets: 1 cover + 3 products = 4 total sheets
      expect(doc.sheets.length, equals(4));
      expect(doc.coverScheduleSheet.tableOfContents.length, equals(3));
      expect(doc.coverScheduleSheet.tableOfContents[0].customerRef, equals('TEE-100'));
      expect(doc.coverScheduleSheet.tableOfContents[0].quantity, equals(20));
      expect(doc.coverScheduleSheet.tableOfContents[1].customerRef, equals('RED-150-75'));
      expect(doc.coverScheduleSheet.tableOfContents[1].quantity, equals(10));
    });
  });
}
