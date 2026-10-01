import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('Alt Key 0.1mm Precision Drag Tests', () {
    late SheetMetalStudioViewModel vm;

    setUp(() {
      vm = SheetMetalStudioViewModel();
      vm.loadDocument(DsfDocument.sampleCableTray(width: 100, height: 50, length: 200, flange: 15));
    });

    test('1. snapEndpointAngle quantizes coordinates to 0.1mm precision when isAlt is true with precisionMm', () {
      final anchor = CadPoint2D(0.0, 0.0);
      final rawTarget = CadPoint2D(123.4567, 87.6543);

      final quantized = SheetMetalStudioViewModel.snapEndpointAngle(
        anchor: anchor,
        target: rawTarget,
        isAlt: true,
        precisionMm: 0.1,
      );

      expect(quantized.x, equals(123.5));
      expect(quantized.y, equals(87.7));
    });

    test('2. resolveEffectivePoint quantizes to 0.1mm precision when isAltPressed is true', () {
      vm.isAltPressed = true;
      final rawPt = CadPoint2D(45.6789, 98.1234);

      final effective = vm.resolveEffectivePoint(rawPt);
      expect(effective.x, equals(45.7));
      expect(effective.y, equals(98.1));
    });

    test('3. updateCursorMm quantizes cursor and clears active snap when Alt is pressed', () {
      final rawCursor = CadPoint2D(12.345, 67.891);
      vm.updateCursorMm(rawCursor, isAlt: true);

      expect(vm.currentCursorMm, isNotNull);
      expect(vm.currentCursorMm!.x, equals(12.3));
      expect(vm.currentCursorMm!.y, equals(67.9));
      expect(vm.activeSnap, isNull);
    });

    test('4. updateBendEndpoint applies 0.1mm precision when Alt is held for bend and flange lines', () {
      // Find a bend line and a flange line in the cable tray sample
      expect(vm.document.bends, isNotEmpty);
      final bend = vm.document.bends.first;

      // Update P1 with Alt held and high-precision floating point coordinate
      final rawTarget = CadPoint2D(15.2891, 49.9482);
      vm.updateBendEndpoint(bendId: bend.id, isP1: true, newPoint: rawTarget, isAlt: true);

      final updatedBend = vm.document.bends.firstWhere((b) => b.id == bend.id);
      expect(updatedBend.p1.x, equals(15.3));
      expect(updatedBend.p1.y, equals(49.9));

      // Update P2 with Alt held
      final rawTargetP2 = CadPoint2D(114.7183, 199.9821);
      vm.updateBendEndpoint(bendId: bend.id, isP1: false, newPoint: rawTargetP2, isAlt: true);

      final updatedBendP2 = vm.document.bends.firstWhere((b) => b.id == bend.id);
      expect(updatedBendP2.p2.x, equals(114.7));
      expect(updatedBendP2.p2.y, equals(200.0));
    });

    test('5. updateCutEndpoint applies 0.1mm precision when Alt is held', () {
      // Add a cut line
      vm.addCutLine(CadPoint2D(10.0, 10.0), CadPoint2D(50.0, 10.0));
      final cut = vm.document.cutLines.last;

      // Drag endpoint with Alt held
      final rawP2 = CadPoint2D(55.5555, 12.3456);
      vm.updateCutEndpoint(cutId: cut.id, isP1: false, newPoint: rawP2, isAlt: true);

      final updatedCut = vm.document.cutLines.firstWhere((c) => c.id == cut.id);
      expect(updatedCut.p2.x, equals(55.6));
      expect(updatedCut.p2.y, equals(12.3));
    });
  });
}
