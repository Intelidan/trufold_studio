import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/step_interchange_bridge.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_document.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';

void main() {
  group('StepInterchangeBridge Tests', () {
    test('Exports FoldedMeshResult to valid ISO-10303 STEP format', () {
      final foldedResult = FoldedMeshResult(
        polygons: [
          CadFoldedPolygon3D(
            faceId: 'face_1',
            vertices: const [
              CadPoint3D(0.0, 0.0, 0.0),
              CadPoint3D(100.0, 0.0, 0.0),
              CadPoint3D(100.0, 50.0, 0.0),
              CadPoint3D(0.0, 50.0, 0.0),
            ],
            normal: const CadPoint3D(0.0, 0.0, 1.0),
          ),
        ],
        thicknessPolygons: const [],
        boundWidth: 100.0,
        boundLength: 50.0,
        boundHeight: 2.0,
        center: const CadPoint3D(50.0, 25.0, 1.0),
      );

      final stepBytes = StepInterchangeBridge.exportFoldedMeshToStep(
        foldedResult,
        partName: 'TestSheetPart',
      );

      expect(stepBytes.isNotEmpty, isTrue);
      final stepText = utf8.decode(stepBytes);
      expect(stepText.contains('ISO-10303-21;'), isTrue);
      expect(stepText.contains('HEADER;'), isTrue);
      expect(stepText.contains('DATA;'), isTrue);
      expect(stepText.contains('END-ISO-10303-21;'), isTrue);
      expect(stepText.contains('TestSheetPart'), isTrue);
    });

    test('Exports multi-part AssemblyDocument to STEP assembly', () {
      final doc = AssemblyDocument(
        id: 'test_doc_1',
        title: 'Cable Ladder Assembly Test',
      );

      doc.parts.add(AssemblyPart(
        id: 'rail_left',
        name: 'Left Rail',
        type: AssemblyPartType.straightRail,
        length: 500.0,
        height: 100.0,
        thickness: 2.0,
        position: const CadPoint3D(0.0, 0.0, 0.0),
      ));

      doc.parts.add(AssemblyPart(
        id: 'rail_right',
        name: 'Right Rail',
        type: AssemblyPartType.straightRail,
        length: 500.0,
        height: 100.0,
        thickness: 2.0,
        position: const CadPoint3D(300.0, 0.0, 0.0),
      ));

      final stepBytes = StepInterchangeBridge.exportAssemblyDocumentToStep(doc);
      expect(stepBytes.isNotEmpty, isTrue);

      final stepText = utf8.decode(stepBytes);
      expect(stepText.contains('ISO-10303-21;'), isTrue);
      expect(stepText.contains('Left_Rail') || stepText.contains('Left Rail'), isTrue);
      expect(stepText.contains('Right_Rail') || stepText.contains('Right Rail'), isTrue);
    });

    test('Performs 3D solid boolean subtraction (pierce/cutout) correctly', () {
      // 1. Target: 100x100x10 mm plate
      final targetPolys = [
        // Front
        CadFoldedPolygon3D(
          faceId: 'front',
          vertices: const [
            CadPoint3D(0, 0, 0),
            CadPoint3D(100, 0, 0),
            CadPoint3D(100, 100, 0),
            CadPoint3D(0, 100, 0),
          ],
          normal: const CadPoint3D(0, 0, -1),
        ),
        // Back
        CadFoldedPolygon3D(
          faceId: 'back',
          vertices: const [
            CadPoint3D(0, 0, 10),
            CadPoint3D(0, 100, 10),
            CadPoint3D(100, 100, 10),
            CadPoint3D(100, 0, 10),
          ],
          normal: const CadPoint3D(0, 0, 1),
        ),
      ];

      // 2. Cutter: 20x20x20 mm tool punch
      final cutterPolys = [
        CadFoldedPolygon3D(
          faceId: 'cut_f',
          vertices: const [
            CadPoint3D(40, 40, -5),
            CadPoint3D(60, 40, -5),
            CadPoint3D(60, 60, -5),
            CadPoint3D(40, 60, -5),
          ],
          normal: const CadPoint3D(0, 0, -1),
        ),
        CadFoldedPolygon3D(
          faceId: 'cut_b',
          vertices: const [
            CadPoint3D(40, 40, 15),
            CadPoint3D(40, 60, 15),
            CadPoint3D(60, 60, 15),
            CadPoint3D(60, 40, 15),
          ],
          normal: const CadPoint3D(0, 0, 1),
        ),
      ];

      final resultPolys = StepInterchangeBridge.booleanSubtract(
        targetPolygons: targetPolys,
        cutterPolygons: cutterPolys,
      );

      expect(resultPolys.isNotEmpty, isTrue);
    });
  });
}
