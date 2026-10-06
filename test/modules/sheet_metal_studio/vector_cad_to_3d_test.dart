import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/canvas_2d/controllers/vector_cad_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/canvas_2d/models/vector_cad_entity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Vector CAD 2D Canvas to 3D Kinematic Folding Tests', () {
    test('Preset Reducer translates into valid 3D folded sheet metal model', () {
      final controller = VectorCadController();
      controller.loadBlueprintPreset('reducer');

      expect(controller.entities, isNotEmpty);
      expect(controller.entities.any((e) => e is VectorCadRect), isTrue);
      expect(controller.entities.any((e) => e is VectorCadLine && (e.role == 'bend' || e.isDashed)), isTrue);
      expect(controller.entities.any((e) => e is VectorCadCircle), isTrue);

      final dsfDoc = controller.toDsfDocument();
      expect(dsfDoc.faces, isNotEmpty);
      expect(dsfDoc.bends, isNotEmpty);
      expect(dsfDoc.punches.length, greaterThanOrEqualTo(4));
      expect(dsfDoc.baseFaceId, isNotEmpty);

      // Verify that KinematicFoldEngine folds this synthesized DsfDocument cleanly
      final foldedMesh = KinematicFoldEngine.foldDocument(dsfDoc, foldProgress: 1.0);
      expect(foldedMesh.polygons, isNotEmpty);
      expect(foldedMesh.boundWidth, greaterThan(0.0));
      expect(foldedMesh.boundLength, greaterThan(0.0));
      expect(foldedMesh.boundHeight, greaterThan(0.0)); // 90-degree bend produces non-zero 3D height!
    });

    test('Adding a new flange rectangle and 90-degree bend line folds into 3D correctly', () {
      final controller = VectorCadController();
      controller.clearWorkspace();

      // Create base floor plate
      controller.addEntity(
        const VectorCadRect(
          id: 'base_floor',
          label: 'Base Floor',
          p1: Offset(100.0, 100.0),
          p2: Offset(300.0, 200.0), // 200mm wide x 100mm long
        ),
      );

      // Create attached vertical flange
      controller.addEntity(
        const VectorCadRect(
          id: 'side_flange',
          label: 'Side Flange',
          p1: Offset(100.0, 200.0),
          p2: Offset(300.0, 250.0), // 200mm wide x 50mm high
        ),
      );

      // Create 90-degree UP fold bend line between them
      controller.addEntity(
        const VectorCadLine(
          id: 'bend_1',
          label: 'Bend 90 UP',
          p1: Offset(100.0, 200.0),
          p2: Offset(300.0, 200.0),
          role: 'bend',
          bendAngleDeg: 90.0,
          bendDirection: 'UP',
        ),
      );

      // Add a punch hole in the flange
      controller.addEntity(
        const VectorCadCircle(
          id: 'punch_flange',
          label: 'Flange Hole',
          center: Offset(200.0, 225.0),
          radius: 10.0, // Ø20mm
          isPunch: true,
        ),
      );

      final dsfDoc = controller.toDsfDocument();
      expect(dsfDoc.faces.length, equals(2));
      expect(dsfDoc.bends.length, equals(1));
      expect(dsfDoc.punches.length, equals(1));
      expect(dsfDoc.baseFaceId, equals('base_floor'));

      final foldedMesh = KinematicFoldEngine.foldDocument(dsfDoc, foldProgress: 1.0);
      expect(foldedMesh.polygons, isNotEmpty);
      expect(foldedMesh.boundHeight, closeTo(50.0, 2.0)); // 50mm flange folded 90 degrees yields ~50mm 3D height
    });

    test('Moving an entity dynamically updates the 3D folded geometry', () {
      final controller = VectorCadController();
      controller.clearWorkspace();

      controller.addEntity(
        const VectorCadRect(
          id: 'plate',
          label: 'Plate',
          p1: Offset(0.0, 0.0),
          p2: Offset(200.0, 100.0),
        ),
      );

      final docBefore = controller.toDsfDocument();
      expect(docBefore.outerContour.any((p) => p.x == 0.0 && p.y == 0.0), isTrue);

      // Move entity by +50mm X and +30mm Y
      controller.selectEntity('plate');
      controller.moveSelected(const Offset(50.0, 30.0));
      controller.commitMove();

      final docAfter = controller.toDsfDocument();
      expect(docAfter.outerContour.any((p) => p.x == 50.0 && p.y == 30.0), isTrue);
    });

    test('Undo and Redo stack works correctly for 2D entity manipulation', () {
      final controller = VectorCadController();
      controller.clearWorkspace();

      expect(controller.entities, isEmpty);
      expect(controller.canUndo, isTrue); // clearWorkspace recorded history

      controller.addEntity(
        const VectorCadCircle(
          id: 'c1',
          label: 'Circle 1',
          center: Offset(50.0, 50.0),
          radius: 15.0,
        ),
      );
      expect(controller.entities.length, equals(1));

      controller.undo();
      expect(controller.entities, isEmpty);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.entities.length, equals(1));
      expect(controller.entities.first.id, equals('c1'));
    });
  });
}
