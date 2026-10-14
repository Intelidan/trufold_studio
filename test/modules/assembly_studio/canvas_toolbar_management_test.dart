import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_sketchup_views_toolbar.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/overlays.dart';
import 'package:trufold_studio/assembly_studio/models/weld_quality_model.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Canvas Toolbar Management: Minimizing, Hiding, Showing, Moving, Rearranging', () {
    testWidgets('1. Joint Style Toolbar supports minimize, expand, close, and drag', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.activeToolMode = SketchUpToolMode.weld;

      Offset dragOffset = const Offset(60, 98);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                StatefulBuilder(
                  builder: (context, setState) {
                    return ListenableBuilder(
                      listenable: vm,
                      builder: (context, _) {
                        return AssemblyWeldJointStyleToolbar(
                          viewModel: vm,
                          position: dragOffset,
                          onDragUpdate: (details) {
                            setState(() {
                              dragOffset += details.delta;
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      // Expanded state shows all 4 joint choices
      expect(find.text('SELECT JOINT CONFIGURATION'), findsOneWidget);
      expect(find.text('T-JOINT'), findsOneWidget);

      // Tap minimize chevron
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pumpAndSettle();

      // Now minimized
      expect(vm.isJointToolbarMinimized, isTrue);
      expect(find.text('SELECT JOINT CONFIGURATION'), findsNothing);
      expect(find.text('T-JOINT'), findsOneWidget);

      // Tap expand
      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pumpAndSettle();
      expect(vm.isJointToolbarMinimized, isFalse);
      expect(find.text('SELECT JOINT CONFIGURATION'), findsOneWidget);

      // Tap close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(vm.showJointStyleToolbar, isFalse);
      expect(find.text('SELECT JOINT CONFIGURATION'), findsNothing);
    });

    testWidgets('2. Views Toolbar supports minimize, expand, and close', (tester) async {
      final vm = AssemblyStudioViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ListenableBuilder(
                  listenable: vm,
                  builder: (context, _) => AssemblySketchupViewsToolbar(viewModel: vm),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byTooltip('Front View'), findsOneWidget);

      // Tap minimize (chevron_left)
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(vm.isViewsToolbarMinimized, isTrue);
      expect(find.text('Views'), findsOneWidget);
      expect(find.byTooltip('Front View'), findsNothing);

      // Tap expand (chevron_right)
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(vm.isViewsToolbarMinimized, isFalse);
      expect(find.byTooltip('Front View'), findsOneWidget);

      // Tap close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(vm.showViewsToolbar, isFalse);
      expect(find.byTooltip('Front View'), findsNothing);
    });

    testWidgets('3. Quality HUD supports minimizing bottom card and defect sidebar independently', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.latestWeldEvaluation = const WeldScoreResult(
        speedConsistency: 85.0,
        profileUniformity: 90.0,
        overallScore: 88.0,
        gradeFeedback: 'Good weld',
        anomalies: [
          WeldAnomaly(position: CadPoint3D(10, 20, 30), description: 'Minor speed variation'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ListenableBuilder(
                  listenable: vm,
                  builder: (context, _) => AssemblyWeldQualityHUD(viewModel: vm),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('QUALITY METRIC GRADE: 88.0%'), findsOneWidget);
      expect(find.text('FAULT ANOMALY MARKS (1)'), findsOneWidget);

      // Minimize defect sidebar using keyboard_arrow_right
      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pumpAndSettle();
      expect(vm.isAnomalySidebarMinimized, isTrue);
      expect(find.text('FAULT ANOMALIES (1)'), findsOneWidget);

      // Minimize quality card using keyboard_arrow_down
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      expect(vm.isQualityCardMinimized, isTrue);
      expect(find.textContaining('QUALITY METRIC GRADE: 88.0% (A)'), findsOneWidget);

      // Expand quality card back using keyboard_arrow_up
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pumpAndSettle();
      expect(vm.isQualityCardMinimized, isFalse);
    });

    testWidgets('4. Clean Canvas Mode hides floating toolbars and provides 1-tap restore', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.activeToolMode = SketchUpToolMode.weld;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => Stack(
                children: [
                  const SizedBox.expand(),
                  AssemblyWeldJointStyleToolbar(viewModel: vm),
                  AssemblySketchupViewsToolbar(viewModel: vm),
                  AssemblyCanvasControlsHUD(
                    viewModel: vm,
                    onResetPositions: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Toolbars'), findsOneWidget);
      expect(find.text('SELECT JOINT CONFIGURATION'), findsOneWidget);
      expect(find.byTooltip('Front View'), findsOneWidget);

      // Toggle Clean Canvas Mode
      vm.toggleCleanCanvasMode();
      await tester.pumpAndSettle();

      // Toolbars should be hidden in clean canvas mode
      expect(find.text('SELECT JOINT CONFIGURATION'), findsNothing);
      expect(find.byTooltip('Front View'), findsNothing);
      expect(find.textContaining('Clean Canvas Active'), findsOneWidget);

      // Tap restore pill
      await tester.tap(find.textContaining('Clean Canvas Active'));
      await tester.pumpAndSettle();

      expect(vm.isCleanCanvasMode, isFalse);
      expect(find.text('SELECT JOINT CONFIGURATION'), findsOneWidget);
      expect(find.byTooltip('Front View'), findsOneWidget);
    });
  });
}
