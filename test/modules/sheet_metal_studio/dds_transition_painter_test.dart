import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dsf_library_service.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/dds/dds_drawing_painters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('2D to 3D Transition Wipe & Kinematic Fold Tests', () {
    final templates = DsfLibraryService.loadAllTemplatesSync(
      baseDirectory: 'assets/dxf_templates/trunking_accessories',
    );
    final bend90 = templates.firstWhere((t) => t.templateId == 'trunking_bend_90');

    test('1. Kinematic fold progressive meshes from 0.0 (flat) to 1.0 (90 deg)', () {
      final flatMesh = KinematicFoldEngine.foldDocument(bend90.document, foldProgress: 0.0);
      expect(flatMesh.polygons, isNotEmpty);
      expect(flatMesh.boundHeight, closeTo(0.0, 0.1)); // Flat pattern has ~0 Z height

      final midMesh = KinematicFoldEngine.foldDocument(bend90.document, foldProgress: 0.5);
      expect(midMesh.polygons, isNotEmpty);
      expect(midMesh.boundHeight, greaterThan(0.0));

      final foldedMesh = KinematicFoldEngine.foldDocument(bend90.document, foldProgress: 1.0);
      expect(foldedMesh.polygons, isNotEmpty);
      expect(foldedMesh.boundHeight, greaterThan(midMesh.boundHeight));
    });

    testWidgets('2. Dds2Dto3DTransitionPainter paints at 0%, 50%, and 100% transitions', (tester) async {
      final foldedMesh = KinematicFoldEngine.foldDocument(bend90.document, foldProgress: 1.0);

      for (final progress in [0.0, 0.5, 1.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 500,
                child: CustomPaint(
                  painter: Dds2Dto3DTransitionPainter(
                    document: bend90.document,
                    mesh: foldedMesh,
                    transitionProgress: progress,
                    showCrossHatching: true,
                    showDividerLine: true,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(CustomPaint), findsWidgets);
      }
    });

    testWidgets('3. Dds3DIsometricPainter renders dynamic folded meshes without throwing', (tester) async {
      for (final foldProg in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final dynamicMesh = KinematicFoldEngine.foldDocument(bend90.document, foldProgress: foldProg);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: CustomPaint(
                  painter: Dds3DIsometricPainter(
                    mesh: dynamicMesh,
                    backgroundColor: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(CustomPaint), findsWidgets);
      }
    });
  });
}
