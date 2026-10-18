import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/engine/dam/dam_file_service.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';

void main() {
  group('TruFold DAM Format & Cable Management System Specification', () {
    test('Requirement 1: Start Assembly Studio with a clean blank sketch on Front datum plane', () {
      final vm = AssemblyStudioViewModel(startWithBlank: true);
      
      // Blank model: parts and welds are empty
      expect(vm.doc.parts, isEmpty);
      expect(vm.doc.welds, isEmpty);
      
      // Sketch mode is active on Front XZ datum plane
      expect(vm.isSketchModeActive, isTrue);
      expect(vm.activeSketchPlane, isNotNull);
      expect(vm.activeSketchPlane!.id, contains('XZ'));
    });

    test('Requirement 1.2: User can open standard ladder demo on demand when needed', () {
      final vm = AssemblyStudioViewModel(startWithBlank: true);
      expect(vm.doc.parts, isEmpty);

      vm.loadStandardLadderDemo();
      expect(vm.doc.parts, isNotEmpty);
      expect(vm.doc.welds, isNotEmpty);
      expect(vm.isSketchModeActive, isFalse);
    });

    test('Requirement 2 & 3: Cable Management Systems (Tray, Trunking, Ladder) available and climbing cage discarded', () {
      final vm = AssemblyStudioViewModel(startWithBlank: true);

      // Load Cable Tray Demo
      vm.loadCableTrayDemo();
      expect(vm.doc.parts.any((p) => p.type == AssemblyPartType.cableTrayStraight), isTrue);
      expect(vm.doc.parts.any((p) => p.type == AssemblyPartType.cableTrayBend90), isTrue);

      // Load Cable Trunking Demo
      vm.loadCableTrunkingDemo();
      expect(vm.doc.parts.any((p) => p.type == AssemblyPartType.cableTrunkingBody), isTrue);
      expect(vm.doc.parts.any((p) => p.type == AssemblyPartType.cableTrunkingCover), isTrue);

      // Compliance report verifies IEC 61537 / NEMA VE 1 standards, NOT OSHA climbing cage
      final report = vm.evaluateLadderCompliance();
      expect(report.items.any((item) => item.standardCode.contains('IEC 61537') || item.standardCode.contains('NEMA VE 1')), isTrue);
      expect(report.items.any((item) => item.id == 'cage_height'), isFalse);
    });

    test('Requirement 4: TruFold .dam file format serialization and roundtrip deserialization', () {
      final vm = AssemblyStudioViewModel(startWithBlank: false); // Has rails, rungs, welds
      
      // Export to .dam JSON string
      final damJson = DamFileService.exportToDamJson(vm);
      expect(damJson, isNotEmpty);

      final Map<String, dynamic> decoded = jsonDecode(damJson);
      expect(decoded['format'], equals('TRUFOLD_DAM'));
      expect(decoded['version'], equals('1.0'));
      expect(decoded['parts'], isNotEmpty);
      expect(decoded['welds'], isNotEmpty);

      // Reconstruct into a new blank ViewModel
      final targetVm = AssemblyStudioViewModel(startWithBlank: true);
      expect(targetVm.doc.parts, isEmpty);

      final success = DamFileService.importFromDamJson(damJson, targetVm);
      expect(success, isTrue);
      expect(targetVm.doc.parts.length, equals(vm.doc.parts.length));
      expect(targetVm.doc.welds.length, equals(vm.doc.welds.length));
    });

    test('Requirement 5: DSF part conversion and CAD anatomy data preservation', () {
      const dsf = DsfDocument(
        productType: 'Cable Tray Fitting',
        itemName: 'TRAY-300x50',
        outerContour: [CadPoint2D(0, 0), CadPoint2D(200, 0), CadPoint2D(200, 300), CadPoint2D(0, 300)],
        bends: [FoldBendLine(id: 'B1', p1: CadPoint2D(0, 100), p2: CadPoint2D(200, 100), targetAngleDeg: 90, radiusMm: 1.5)],
        punches: [CncPunchPrimitive(id: 'P1', type: PunchType.roundHole, center: CadPoint2D(40, 50), diameterMm: 10)],
      );
      final dsfJson = jsonEncode(dsf.toJson());

      final part = DamFileService.convertDsfToAssemblyPart(
        dsfDoc: dsf,
        rawJsonStr: dsfJson,
        position: const CadPoint3D(100.0, 200.0, 0.0),
      );

      expect(part.type, equals(AssemblyPartType.cableTrayStraight));
      expect(part.customPolygons, isNotNull);
      expect(part.customPolygons, isNotEmpty);
      expect(part.sourceDsfJson, equals(dsfJson));
      expect(part.getEffectiveDsfDocument(), isNotNull);
      expect(part.getEffectiveDsfDocument()!.itemName, equals(dsf.itemName));
    });
  });
}
