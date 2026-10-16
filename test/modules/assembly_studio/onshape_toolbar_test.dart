import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/assembly_studio/models/onshape_toolbar_items.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/toolbar/assembly_onshape_toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Onshape Toolbar Tests', () {
    test('Registry contains all 10 3D groups and 10 Sketch groups', () {
      expect(onshape3dModelingGroups.length, 10);
      expect(onshapeSketchGroups.length, 10);

      // Verify group IDs
      expect(onshape3dModelingGroups.map((g) => g.id).toList(), [
        'base_features',
        'edge_and_body_features',
        'pattern_and_mirror',
        'part_modification',
        'direct_editing',
        'surfaces',
        'curves',
        'reference_and_variables',
        'frames',
        'sheet_metal_and_pcb',
      ]);

      expect(onshapeSketchGroups.map((g) => g.id).toList(), [
        'lines',
        'rectangles',
        'circles_and_ellipses',
        'arcs_and_conics',
        'polygons',
        'splines',
        'point_text_project',
        'sketch_modify',
        'pattern_and_insert',
        'constraints',
      ]);
    });

    test('Implemented tools are marked correctly', () {
      final baseGroup = onshape3dModelingGroups.firstWhere((g) => g.id == 'base_features');
      final extrude = baseGroup.items.firstWhere((it) => it.id == 'extrude');
      final revolve = baseGroup.items.firstWhere((it) => it.id == 'revolve');

      expect(extrude.isImplemented, isTrue);
      expect(revolve.isImplemented, isFalse);

      final lineGroup = onshapeSketchGroups.firstWhere((g) => g.id == 'lines');
      final line = lineGroup.items.firstWhere((it) => it.id == 'line');
      final midpoint = lineGroup.items.firstWhere((it) => it.id == 'midpoint_line');

      expect(line.isImplemented, isTrue);
      expect(midpoint.isImplemented, isTrue);
    });

    testWidgets('AssemblyOnshapeToolbar switches between 3D and Sketch toolbars', (tester) async {
      final vm = AssemblyStudioViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 1600, height: 50, child: AssemblyOnshapeToolbar(viewModel: vm)),
          ),
        ),
      );

      // In 3D Modeling mode initially
      expect(vm.isSketchMode, isFalse);
      expect(find.byType(AssemblyOnshapeToolbar), findsOneWidget);
      expect(find.text('Sketch'), findsOneWidget);

      // Enter Sketch Mode
      vm.enterSketchMode();
      await tester.pumpAndSettle();

      expect(vm.isSketchMode, isTrue);
      expect(find.byType(AssemblyOnshapeToolbar), findsOneWidget);

      // Finish Sketch Mode
      vm.finishSketch();
      await tester.pumpAndSettle();

      expect(vm.isSketchMode, isFalse);
    });
  });
}
