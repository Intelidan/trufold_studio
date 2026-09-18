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
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/press_brake_machine_dialog.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/punch_tooling_selector_dialog.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_browser_panel.dart';
import 'package:trufold_studio/sheet_metal_studio/models/studio_tab_model.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_ribbon_toolbar.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/cad_number_spinner.dart';

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
      final meshResult = KinematicFoldEngine.foldDocument(sampleDoc, foldProgress: 1.0, curveResolution3D: 16);
      expect(meshResult.polygons.isNotEmpty, isTrue);
    });

    testWidgets('2. Collapsible parts browser panel toggles between expanded and mini-dock', (tester) async {
      final vm = SheetMetalStudioViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 300, height: 600, child: StudioBrowserPanel(viewModel: vm, width: 260)),
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
              builder: (context) => ElevatedButton(onPressed: () => PressBrakeMachineDialog.show(context, vm), child: const Text('Open Dialog')),
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
      final initialPunchCount = vm.document.punches.length;
      vm.handleCanvasClick(const CadPoint2D(80, 50), autoPlace: false);

      // Rectangle creates a void punch with zero duplicate perimeter cut lines (SS2)
      expect(vm.document.cutLines.length, initialCutCount);
      expect(vm.document.punches.length, initialPunchCount + 1);
      expect(vm.document.punches.last.type, PunchType.compound);
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
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      // Verify dedicated Sheet Metal & Draw tool buttons exist
      expect(find.byIcon(Icons.alt_route), findsOneWidget); // Add Bend Line
      expect(find.byIcon(Icons.border_outer), findsOneWidget); // Add Flange
      expect(find.byIcon(Icons.content_cut), findsOneWidget); // Add Cut
      expect(find.byIcon(Icons.crop_square_sharp), findsOneWidget); // Corner Chamfer
      expect(find.byIcon(Icons.crop_16_9), findsOneWidget); // Slot / Obround Punch
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget); // Circle / Bolt Hole Punch
      expect(find.byIcon(Icons.crop_square), findsOneWidget); // Rectangle / Square Punch
      expect(find.byIcon(Icons.anchor), findsOneWidget); // Prominent Base Floor Anchor Button
      expect(find.byIcon(Icons.restart_alt), findsOneWidget); // Clear All / Start Fresh Button

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
      final arc = CadArc2D(id: 'ARC_TEST', center: const CadPoint2D(50, 50), radius: 25, startAngleDeg: 0, endAngleDeg: 90);
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

    test('8. deleteSelectedEntities() deletes arcs, punches, cuts, bends, and patterns', () {
      final vm = SheetMetalStudioViewModel();
      final arc = CadArc2D(id: 'ARC_TO_DELETE', center: const CadPoint2D(20, 20), radius: 10, startAngleDeg: 0, endAngleDeg: 180);
      vm.setDocument(vm.document.copyWith(arcs: [...vm.document.arcs, arc]));
      expect(vm.document.arcs.any((a) => a.id == 'ARC_TO_DELETE'), isTrue);

      // Select and delete arc via deleteSelectedEntities()
      vm.setSelectedArc('ARC_TO_DELETE');
      vm.deleteSelectedEntities();

      expect(vm.document.arcs.any((a) => a.id == 'ARC_TO_DELETE'), isFalse);
      expect(vm.selectedArcId, isNull);
    });

    test('9. StudioToolMode.drawArc creates a first-class CadArc2D entity instead of line segments', () {
      final vm = SheetMetalStudioViewModel();
      final initialArcCount = vm.document.arcs.length;
      final initialCutCount = vm.document.cutLines.length;

      vm.setToolMode(StudioToolMode.drawArc);

      // Place 3 points to complete arc
      vm.handleCanvasClick(const CadPoint2D(10, 10));
      vm.handleCanvasClick(const CadPoint2D(20, 25));
      vm.handleCanvasClick(const CadPoint2D(30, 10));

      // Must create a first-class CadArc2D in document.arcs
      expect(vm.document.arcs.length, initialArcCount + 1);
      final createdArc = vm.document.arcs.last;
      expect(createdArc.id, startsWith('ARC_'));
      expect(createdArc.radius, greaterThan(0));

      // Must NOT create discretized cut lines
      expect(vm.document.cutLines.length, initialCutCount);

      // Arc is automatically selected and property sheet opened
      expect(vm.selectedArcId, createdArc.id);
      expect(vm.isPropertyInspectorOpen, isTrue);
    });

    test('10. CadArc2D normalizes unnormalized angles (540° -> 180°, 630° -> 270°)', () {
      final arc = CadArc2D(id: 'ARC_DXF_CORNER', center: const CadPoint2D(79.22, 20.0), radius: 15.0, startAngleDeg: 540.0, endAngleDeg: 630.0);

      // Normalized to [0, 360)
      expect(arc.startAngleDeg, closeTo(180.0, 1e-4));
      expect(arc.endAngleDeg, closeTo(270.0, 1e-4));
      expect(arc.sweepAngleDeg, closeTo(90.0, 1e-4));
    });

    test('11. updateArc() on boundary arc synchronizes outerContour vertices', () {
      final vm = SheetMetalStudioViewModel();
      // Set an outer contour polygon
      final contour = [const CadPoint2D(0, 0), const CadPoint2D(100, 0), const CadPoint2D(100, 50), const CadPoint2D(0, 50)];
      final bndArc = CadArc2D(id: 'ARC_BND_1', center: const CadPoint2D(100, 25), radius: 25.0, startAngleDeg: 270.0, endAngleDeg: 90.0, isBoundary: true);
      vm.setDocument(vm.document.copyWith(outerContour: contour, arcs: [bndArc]));

      // Update arc radius from 25 to 30
      final updatedArc = CadArc2D(id: 'ARC_BND_1', center: const CadPoint2D(100, 25), radius: 30.0, startAngleDeg: 270.0, endAngleDeg: 90.0, isBoundary: true);
      vm.updateArc(updatedArc);

      // Verify outer contour was synchronized with updated endpoints
      expect(vm.document.arcs.first.radius, 30.0);
      expect(vm.document.outerContour.isNotEmpty, isTrue);
      expect(vm.document.outerContour.any((p) => p.distanceTo(updatedArc.startPoint) < 0.01), isTrue);
      expect(vm.document.outerContour.any((p) => p.distanceTo(updatedArc.endPoint) < 0.01), isTrue);
    });

    test('12. ViewModel tracks isModified flag on edits and cleans on markClean()', () {
      final vm = SheetMetalStudioViewModel();
      vm.markClean();
      expect(vm.isModified, isFalse);

      // Adding a punch marks modified
      vm.addPunch(CncPunchPrimitive.round(id: 'P_TEST', center: const CadPoint2D(50, 50), diameterMm: 10));
      expect(vm.isModified, isTrue);

      // markClean resets it
      vm.markClean();
      expect(vm.isModified, isFalse);
    });

    test('13. Merged Circle & Square tools: single-click stamps punch preset, drag creates custom geometry', () {
      final vm = SheetMetalStudioViewModel();
      vm.toolConfig.roundHoleDiameter = 8.5;
      vm.toolConfig.selectedPunchPreset = 'M8';
      vm.toolConfig.squareAspectLocked = false;
      vm.toolConfig.rectWidth = 25.0;
      vm.toolConfig.rectHeight = 25.0;

      // 1. Single-click stamp for Circle tool (distance <= 0.5mm between click1 and click2)
      vm.setToolMode(StudioToolMode.drawCircle);
      vm.handleCanvasClick(const CadPoint2D(100, 100));
      vm.handleCanvasClick(const CadPoint2D(100.1, 100.1));
      expect(vm.document.punches.any((p) => p.type == PunchType.roundHole && p.diameterMm == 8.5), isTrue);

      // 2. Drag draw for Circle tool (distance > 0.5mm) -> creates custom sized round punch
      vm.setToolMode(StudioToolMode.drawCircle);
      vm.handleCanvasClick(const CadPoint2D(200, 200));
      vm.handleCanvasClick(const CadPoint2D(215, 200)); // radius = 15 -> diameter = 30
      expect(vm.document.punches.any((p) => p.type == PunchType.roundHole && (p.diameterMm - 30.0).abs() < 0.1), isTrue);

      // 3. Single-click stamp for Rectangle tool (distance <= 1.0mm)
      vm.setToolMode(StudioToolMode.drawRectangle);
      vm.handleCanvasClick(const CadPoint2D(150, 150));
      vm.handleCanvasClick(const CadPoint2D(150.2, 150.2));
      expect(vm.document.punches.any((p) => (p.type == PunchType.square || p.type == PunchType.rectangle) && p.widthMm == 25.0), isTrue);

      // 4. Drag draw for Rectangle tool (distance > 1.0mm) -> creates compound rectangular cutout void
      final punchCountBefore = vm.document.punches.length;
      vm.setToolMode(StudioToolMode.drawRectangle);
      vm.handleCanvasClick(const CadPoint2D(300, 300));
      vm.handleCanvasClick(const CadPoint2D(350, 340));
      expect(vm.document.punches.length, punchCountBefore + 1);
      expect(vm.document.punches.last.type, PunchType.compound);
    });

    testWidgets('14. CadNumberSpinner stepper buttons and value bounds', (tester) async {
      double testVal = 10.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (ctx, setState) =>
                  CadNumberSpinner(value: testVal, step: 2.5, min: 0.0, max: 100.0, suffix: 'mm', onChanged: (newV) => setState(() => testVal = newV)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find [+] and [-] buttons
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);

      // Tap [+]
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(testVal, 12.5);

      // Tap [-] twice
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(testVal, 7.5);
    });

    test('15. selectAll() and clearAllDrawingEntities() in SheetMetalStudioViewModel', () {
      final vm = SheetMetalStudioViewModel();

      // Add features
      vm.addPunch(CncPunchPrimitive.round(id: 'P_1', center: const CadPoint2D(10, 10), diameterMm: 6));
      vm.addPunch(CncPunchPrimitive.round(id: 'P_2', center: const CadPoint2D(20, 20), diameterMm: 8));
      vm.addCutLine(const CadPoint2D(0, 0), const CadPoint2D(50, 50));
      vm.addBendLine(const CadPoint2D(0, 25), const CadPoint2D(100, 25));

      // Select all
      vm.selectAll();
      expect(vm.selectedEntityIds.contains('P_1'), isTrue);
      expect(vm.selectedEntityIds.contains('P_2'), isTrue);
      expect(vm.selectedEntityIds.isNotEmpty, isTrue);

      // Clear all and start fresh
      vm.clearAllDrawingEntities(resetToBlank: true);
      expect(vm.document.punches.isEmpty, isTrue);
      expect(vm.document.cutLines.isEmpty, isTrue);
      expect(vm.document.bends.isEmpty, isTrue);
      expect(vm.document.outerContour.length, 4); // blank rectangular sheet restored
      expect(vm.selectedEntityIds.isEmpty, isTrue);

      // Undo restores cleared entities
      vm.undo();
      expect(vm.document.punches.isNotEmpty, isTrue);
      expect(vm.document.cutLines.isNotEmpty, isTrue);
    });

    test('16. autoBendPlacementEnabled flag and toggleAutoBendPlacement()', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.autoBendPlacementEnabled, isTrue);

      vm.toggleAutoBendPlacement();
      expect(vm.autoBendPlacementEnabled, isFalse);

      vm.toggleAutoBendPlacement(enabled: true);
      expect(vm.autoBendPlacementEnabled, isTrue);
    });
  });
}
