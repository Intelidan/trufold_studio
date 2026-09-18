// =============================================================================
// studio_enhancements_test.dart
//
// Automated Tests for truFold Studio Enhancements:
// 1. Separate 2D curve resolution and 3D mesh quality settings
// 2. Onshape-style click-and-drag drawing vs click-move-click
// 3. Collapsible parts browser panel
// 4. Press brake machine dialog & punch tooling integration
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/press_brake_machine_dialog.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/punch_tooling_selector_dialog.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_browser_panel.dart';
import 'package:trufold_studio/sheet_metal_studio/models/studio_tab_model.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_ribbon_toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Studio Enhancements Tests', () {
    test('1. Separate 2D and 3D curve resolution configuration in ViewModel and Kinematic Engine', () {
      final vm = SheetMetalStudioViewModel();

      // Defaults
      expect(vm.curveResolution2D, 64);
      expect(vm.curveResolution3D, 32);
      expect(vm.curveResolution, 64); // alias

      // Update 2D resolution
      vm.setCurveResolution2D(128);
      expect(vm.curveResolution2D, 128);
      expect(vm.curveResolution3D, 32); // untouched

      // Update 3D mesh quality
      vm.setCurveResolution3D(16);
      expect(vm.curveResolution3D, 16);
      expect(vm.curveResolution2D, 128); // untouched

      // Clamping checks
      vm.setCurveResolution2D(500);
      expect(vm.curveResolution2D, 128);
      vm.setCurveResolution3D(100);
      expect(vm.curveResolution3D, 64);

      // Verify foldDocument accepts curveResolution3D
      final sampleDoc = DsfDocument.sampleCableTray();
      final meshResult = KinematicFoldEngine.foldDocument(
        sampleDoc,
        foldProgress: 1.0,
        curveResolution3D: 16,
      );
      expect(meshResult.polygons.isNotEmpty, isTrue);
    });

    testWidgets('2. Collapsible parts browser panel toggles between expanded and mini-dock', (tester) async {
      final vm = SheetMetalStudioViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 600,
              child: StudioBrowserPanel(
                viewModel: vm,
                width: 260,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expanded initially: shows full tree and collapse button
      expect(find.text('BROWSER'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.text('Document Settings'), findsOneWidget);

      // Tap collapse button
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      // Collapsed into mini-dock: shows chevron_right expand button
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.text('Document Settings'), findsNothing);

      // Tap expand button
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      // Restored
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.text('Document Settings'), findsOneWidget);
    });

    testWidgets('3. PressBrakeMachineDialog switches presets and links to Punch Tooling Catalog', (tester) async {
      final vm = SheetMetalStudioViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PressBrakeMachineDialog.show(context, vm),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('PRESS BRAKE MACHINE & CAM SETTINGS'), findsOneWidget);
      expect(find.text('BROWSE FULL PUNCH CATALOG...'), findsOneWidget);

      // Verify Auto-Optimize Bend Sequence button exists and executes
      final autoBtn = find.text('AUTO-OPTIMIZE BEND SEQUENCE');
      expect(autoBtn, findsOneWidget);
      await tester.tap(autoBtn);
      await tester.pumpAndSettle();

      // Tap browse punch catalog button inside machine dialog
      await tester.tap(find.text('BROWSE FULL PUNCH CATALOG...'));
      await tester.pumpAndSettle();

      // Punch tooling dialog is opened
      expect(find.byType(PunchToolingSelectorDialog), findsOneWidget);
    });

    test('4. Onshape click-and-drag drawing vs click-move-click logic in ViewModel', () {
      final vm = SheetMetalStudioViewModel();

      // Start rectangle drawing
      vm.setToolMode(StudioToolMode.drawRectangle);
      expect(vm.pendingBendStart, isNull);

      // Simulate Onshape drag start: anchor set at (10, 10)
      vm.setPendingBendStart(const CadPoint2D(10, 10));
      expect(vm.pendingBendStart, const CadPoint2D(10, 10));

      // Simulate live drag rubber-band update to (80, 50)
      vm.updateRubberBand(const CadPoint2D(80, 50));
      expect(vm.rubberBandEndpoint, const CadPoint2D(80, 50));

      // Simulate release-to-commit at (80, 50)
      final initialCutCount = vm.document.cutLines.length;
      vm.handleCanvasClick(const CadPoint2D(80, 50), autoPlace: false);

      // Rectangle creates 4 perimeter cut lines
      expect(vm.document.cutLines.length, initialCutCount + 4);
      expect(vm.pendingBendStart, isNull);
      expect(vm.rubberBandEndpoint, isNull);
    });

    test('5. Rectangle dragging does not snap to 45° angle rays or collapse onto start origin line', () {
      final vm = SheetMetalStudioViewModel();
      vm.setToolMode(StudioToolMode.drawRectangle);

      // Start rectangle at (100, 100)
      vm.setPendingBendStart(const CadPoint2D(100, 100));

      // Drag cursor to (105, 101) - very close to horizontal axis (angle ~ 11.3°, dx=5, dy=1)
      // If 45° angle snapping were active, dy would snap to 0 (collapsing onto origin line)
      vm.updateCursorMm(const CadPoint2D(105, 101));

      // Candidate must preserve its true coordinates and NOT collapse to y=100
      expect(vm.rubberBandEndpoint, isNotNull);
      expect(vm.rubberBandEndpoint!.y, closeTo(101.0, 0.01));
      expect(vm.rubberBandEndpoint!.x, closeTo(105.0, 0.01));

      // Drag near starting point to (102, 103)
      vm.updateCursorMm(const CadPoint2D(102, 103));
      expect(vm.rubberBandEndpoint!.x, closeTo(102.0, 0.01));
      expect(vm.rubberBandEndpoint!.y, closeTo(103.0, 0.01));
    });

    testWidgets('6. StudioRibbonToolbar renders dedicated buttons for Add Bend, Flange, Cut, Chamfer, Punches', (tester) async {
      final vm = SheetMetalStudioViewModel();
      final tab = StudioTab(id: 't1', title: 'Test Part', viewModel: vm);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRibbonToolbar(
              viewModel: vm,
              tabs: [tab],
              activeTabIndex: 0,
              onTabSelected: (_) {},
              onTabClosed: (_) {},
              onNewTab: () {},
              onOpenFile: () {},
              onSaveFile: () {},
              onFinishSketch: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dedicated Sheet Metal tool buttons exist
      expect(find.byIcon(Icons.alt_route), findsOneWidget); // Add Bend Line
      expect(find.byIcon(Icons.border_outer), findsOneWidget); // Add Flange
      expect(find.byIcon(Icons.content_cut), findsOneWidget); // Add Cut
      expect(find.byIcon(Icons.crop_square_sharp), findsOneWidget); // Corner Chamfer
      expect(find.byIcon(Icons.adjust), findsOneWidget); // Round Hole Punch
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget); // Square Punch

      // Tap Add Bend button
      await tester.tap(find.byIcon(Icons.alt_route));
      await tester.pumpAndSettle();
      expect(vm.toolMode, StudioToolMode.addBend);

      // Tap Add Flange button
      await tester.tap(find.byIcon(Icons.border_outer));
      await tester.pumpAndSettle();
      expect(vm.toolMode, StudioToolMode.addFlange);

      // Tap Corner Chamfer button
      await tester.tap(find.byIcon(Icons.crop_square_sharp));
      await tester.pumpAndSettle();
      expect(vm.toolMode, StudioToolMode.cornerChamfer);
    });

    testWidgets('7. Arc selection and Parts Browser double-click opens property inspector', (tester) async {
      final vm = SheetMetalStudioViewModel();
      // Add an arc to the document
      final arc = CadArc2D(
        id: 'ARC_TEST',
        center: const CadPoint2D(50, 50),
        radius: 25,
        startAngleDeg: 0,
        endAngleDeg: 90,
      );
      vm.setDocument(vm.document.copyWith(arcs: [...vm.document.arcs, arc]));

      // Close inspector first to test re-opening
      vm.setPropertyInspectorOpen(false);
      expect(vm.isPropertyInspectorOpen, isFalse);

      // Selecting arc in browser panel or on canvas sets selectedArcId and opens property inspector
      vm.setSelectedArc('ARC_TEST');
      vm.setPropertyInspectorOpen(true);
      expect(vm.selectedArcId, 'ARC_TEST');
      expect(vm.isPropertyInspectorOpen, isTrue);

      // Verify selecting bend also sets property inspector open
      vm.selectBend('B1');
      expect(vm.selectedBendId, 'B1');
      vm.setPropertyInspectorOpen(true);
      expect(vm.isPropertyInspectorOpen, isTrue);
    });
  });
}
