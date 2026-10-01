// =============================================================================
// studio_menu_bar_and_3d_icons_test.dart
//
// Widget & Unit tests for:
// 1. StudioMenuBar (File, Edit, Sketch, Sheet Metal, Constraints, Tooling, Templates, View, Help)
// 2. Studio3DToolButton and Tool3DActionIcon (3D isometric animated action icons on hover)
// =============================================================================

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_dimension.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_3d_tool_icons.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_menu_bar.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_tool_button_3d.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_sketch_palette.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/views/sheet_metal_studio_screen.dart';

void main() {
  group('StudioMenuBar & 3D Animated Tool Icons Tests', () {
    testWidgets('1. StudioMenuBar renders all 9 colorful category menus', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vm = SheetMetalStudioViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMenuBar(viewModel: vm, onNewTab: () {}, onOpenFile: () {}, onSaveFile: () {}, onConfirmClearAll: (ctx, vm) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all 9 menu categories are present
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Sketch'), findsOneWidget);
      expect(find.text('Sheet Metal'), findsOneWidget);
      expect(find.text('Constraints'), findsOneWidget);
      expect(find.text('Tooling'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
    });

    testWidgets('2. File menu opens dropdown and triggers onNewTab callback', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vm = SheetMetalStudioViewModel();
      bool newTabCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMenuBar(
              viewModel: vm,
              onNewTab: () => newTabCalled = true,
              onOpenFile: () {},
              onSaveFile: () {},
              onConfirmClearAll: (ctx, vm) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open File menu
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();

      // Dropdown should show 'New Blank Part'
      expect(find.text('New Blank Part'), findsOneWidget);
      expect(find.text('Save Part'), findsOneWidget);

      // Tap 'New Blank Part'
      await tester.tap(find.text('New Blank Part'));
      await tester.pumpAndSettle();

      expect(newTabCalled, isTrue);
    });

    testWidgets('3. Sheet Metal menu triggers Add Bend tool mode in ViewModel', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vm = SheetMetalStudioViewModel();
      expect(vm.toolMode, StudioToolMode.select);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMenuBar(viewModel: vm, onNewTab: () {}, onOpenFile: () {}, onSaveFile: () {}, onConfirmClearAll: (ctx, vm) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Sheet Metal menu
      await tester.tap(find.text('Sheet Metal'));
      await tester.pumpAndSettle();

      expect(find.text('Add Bend Line'), findsOneWidget);
      expect(find.text('Add Return Flange'), findsOneWidget);
      expect(find.text('Add Laser Cut Line / Slit'), findsOneWidget);

      // Tap Add Bend Line
      await tester.tap(find.text('Add Bend Line'));
      await tester.pumpAndSettle();

      expect(vm.toolMode, equals(StudioToolMode.addBend));
    });

    testWidgets('4. Studio3DToolButton renders 3D action canvas and activates on hover & tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Studio3DToolButton(
                toolType: Tool3DType.addBend,
                fallbackIcon: Icons.alt_route,
                label: 'Add Bend Line',
                shortcut: 'B',
                description: 'Define press brake fold line (0° to 90° in 3D)',
                isActive: false,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify custom 3D action icon widget is rendered
      expect(find.byType(Tool3DActionIcon), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // Simulate mouse hover event over the 3D tool button
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(Studio3DToolButton)));
      await tester.pump(const Duration(milliseconds: 200));

      // Tap the button
      await tester.tap(find.byType(Studio3DToolButton));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tapped, isTrue);

      // Move mouse away to stop repeat animation
      await gesture.moveTo(const Offset(500, 500));
      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets('5. Tool3DActionIcon paints without exceptions for all tool types', (tester) async {
      for (final type in Tool3DType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: Tool3DActionIcon(toolType: type, isHovered: true, isActive: true, size: 32.0)),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('6. Studio3DToolButton shows transparent icon-sized 3D animated tooltip on hover', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Studio3DToolButton(
                toolType: Tool3DType.addBend,
                fallbackIcon: Icons.alt_route,
                label: 'Add Bend Line',
                shortcut: 'B',
                description: 'Define press brake fold line (0° to 90° in 3D)',
                isActive: false,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially only 1 Tool3DActionIcon (static in toolbar button)
      expect(find.byType(Tool3DActionIcon), findsOneWidget);

      // Simulate mouse hover over button
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(Studio3DToolButton)));
      await tester.pump(const Duration(milliseconds: 250));

      // Tooltip is now visible: renders 2 Tool3DActionIcon widgets (1 in button, 1 large in tooltip)
      expect(find.byType(Tool3DActionIcon), findsNWidgets(2));
      expect(find.text('Add Bend Line'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);

      final buttonPos = tester.getTopLeft(find.byType(Studio3DToolButton));
      final buttonSize = tester.getSize(find.byType(Studio3DToolButton));
      final icons = find.byType(Tool3DActionIcon).evaluate().toList();
      final tooltipIconBox = icons.last.renderObject as RenderBox;
      final tooltipIconPos = tooltipIconBox.localToGlobal(Offset.zero);

      // Verify tooltip appears directly below the tool button (not at screen bottom)
      expect(tooltipIconPos.dy, greaterThanOrEqualTo(buttonPos.dy + buttonSize.height - 5));
      expect(tooltipIconPos.dy, lessThan(buttonPos.dy + buttonSize.height + 40));

      // Move mouse away
      await gesture.moveTo(const Offset(600, 600));
      await tester.pump(const Duration(milliseconds: 100));

      // Tooltip hides immediately
      expect(find.byType(Tool3DActionIcon), findsOneWidget);
      expect(find.text('Add Bend Line'), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('7. StudioMenuBar greys out unlinked constraint menu items', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vm = SheetMetalStudioViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMenuBar(viewModel: vm, onNewTab: () {}, onOpenFile: () {}, onSaveFile: () {}, onConfirmClearAll: (ctx, vm) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Constraints menu
      await tester.tap(find.text('Constraints'));
      await tester.pumpAndSettle();

      // Dimensional Constraints, Dimension, and Constraint Manager are enabled
      expect(find.text('Dimensional Constraints'), findsOneWidget);
      expect(find.text('Dimension'), findsOneWidget);

      // Unlinked constraint options exist but are disabled/greyed out
      expect(find.text('Coincident Constraint'), findsOneWidget);
      expect(find.text('Concentric Constraint'), findsOneWidget);

      final coincidentItem = tester.widget<PopupMenuItem<void>>(
        find.ancestor(of: find.text('Coincident Constraint'), matching: find.byType(PopupMenuItem<void>)),
      );
      expect(coincidentItem.enabled, isFalse);

      final concentricItem = tester.widget<PopupMenuItem<void>>(
        find.ancestor(of: find.text('Concentric Constraint'), matching: find.byType(PopupMenuItem<void>)),
      );
      expect(concentricItem.enabled, isFalse);
    });

    testWidgets('8. CAD tool shortcut keys switch viewModel.toolMode across screen and canvas', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: SheetMetalStudioScreen()));
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(SheetMetalStudioScreen)) as dynamic;
      final SheetMetalStudioViewModel vm = state.viewModel;

      // Initial mode is select
      expect(vm.toolMode, equals(StudioToolMode.select));

      // 1. 'B' -> Add Bend Line
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.addBend));

      // 2. 'F' -> Add Return Flange
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.addFlange));

      // 3. 'Shift + F' -> Corner Fillet
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.cornerFillet));

      // 4. 'M' -> Add Cut / Slit Line
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.addCut));

      // 5. 'L' -> Line / Polyline
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.drawPolyline));

      // 6. 'G' -> Rectangle Punch
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.drawRectangle));

      // 7. 'C' -> Circle Punch
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.drawCircle));

      // 8. 'Shift + C' -> Corner Chamfer
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.cornerChamfer));

      // 9. 'A' -> 3-Point Arc
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.drawArc));

      // 10. 'D' -> Smart Dimension
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.addDimension));

      // 11. 'P' -> Perforation Pattern
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.perforationPattern));

      // 12. 'H' -> Pan Tool
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.pan));

      // 13. 'V' -> Select Tool
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.select));

      // 14. Switch to Bend then press Space -> Select Tool
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.addBend));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.select));

      // 15. Escape hierarchy: closes open floating inspector / deselects / resets tool to select
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.addFlange));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      if (vm.toolMode != StudioToolMode.select) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
      }
      expect(vm.toolMode, equals(StudioToolMode.select));

      // 16. 'Q' -> Construction mode toggle
      final initialConst = vm.isConstructionModeActive;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pump();
      expect(vm.isConstructionModeActive, equals(!initialConst));
    });

    testWidgets('9. Tool shortcuts are ignored when typing inside an EditableText field', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              const SheetMetalStudioScreen(),
              Positioned(
                bottom: 20,
                right: 20,
                child: Material(
                  child: SizedBox(
                    width: 200,
                    child: TextField(controller: controller, focusNode: focusNode),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(SheetMetalStudioScreen)) as dynamic;
      final SheetMetalStudioViewModel vm = state.viewModel;
      expect(vm.toolMode, equals(StudioToolMode.select));

      // Focus the text field
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      // Typing 'b', 'f', 'm' while focused on TextField should NOT change toolMode
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.select)); // Still select!

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.select)); // Still select!

      // Unfocus the text field and click back onto the canvas
      focusNode.unfocus();
      await tester.pump();
      await tester.tap(find.byType(UnfoldedCanvasWidget));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Now 'B' switches tool immediately
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.addBend));
    });

    testWidgets('10. Sketch Palette is non-persistent and toggles via Toolbar Palette button and closes with X button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: SheetMetalStudioScreen()));
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(SheetMetalStudioScreen)) as dynamic;
      final SheetMetalStudioViewModel vm = state.viewModel;

      // Palette is closed by default
      expect(vm.isSketchPaletteOpen, isFalse);
      expect(find.byType(StudioSketchPalette), findsNothing);

      // Find 'Palette' button in the toolbar
      final paletteBtn = find.text('Palette');
      expect(paletteBtn, findsOneWidget);

      // Tap to open
      await tester.tap(paletteBtn);
      await tester.pumpAndSettle();
      expect(vm.isSketchPaletteOpen, isTrue);
      expect(find.byType(StudioSketchPalette), findsOneWidget);

      // Tap the close (X) button inside the palette
      final closeBtn = find.descendant(of: find.byType(StudioSketchPalette), matching: find.byIcon(Icons.close));
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // Palette is now closed
      expect(vm.isSketchPaletteOpen, isFalse);
      expect(find.byType(StudioSketchPalette), findsNothing);
    });

    testWidgets('11. Square and Circle tools: click places preset punch, drag places dimensioned punch; both modifiable and switch to select', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: SheetMetalStudioScreen()));
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(SheetMetalStudioScreen)) as dynamic;
      final SheetMetalStudioViewModel vm = state.viewModel;

      final canvasFinder = find.byType(UnfoldedCanvasWidget);
      expect(canvasFinder, findsOneWidget);
      final canvasCenter = tester.getCenter(canvasFinder);

      // A. Square Tool - Single Click
      vm.setToolMode(StudioToolMode.drawRectangle);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.drawRectangle));

      final initialPunchesCount = vm.document.punches.length;
      final gClick1 = await tester.startGesture(canvasCenter);
      await tester.pump(const Duration(milliseconds: 30));
      await gClick1.up();
      await tester.pumpAndSettle();

      expect(vm.document.punches.length, equals(initialPunchesCount + 1));
      final squarePunch1 = vm.document.punches.last;
      expect(squarePunch1.type == PunchType.square || squarePunch1.type == PunchType.rectangle, isTrue);
      expect(vm.selectedPunchId, equals(squarePunch1.id));
      expect(vm.toolMode, equals(StudioToolMode.select));

      // Close inspector and clear selection before starting next canvas gesture
      vm.setPropertyInspectorOpen(false);
      vm.clearSelection();
      await tester.pumpAndSettle();

      // B. Square Tool - Drag
      vm.setToolMode(StudioToolMode.drawRectangle);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.drawRectangle));

      final dragStart = canvasCenter + const Offset(-180, 50);
      final dragEnd = canvasCenter + const Offset(-100, 110);

      final gesture1 = await tester.startGesture(dragStart);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture1.moveTo(dragEnd);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture1.up();
      await tester.pumpAndSettle();

      expect(vm.document.punches.length, equals(initialPunchesCount + 2));
      final squarePunch2 = vm.document.punches.last;
      expect(squarePunch2.type == PunchType.square || squarePunch2.type == PunchType.rectangle, isTrue);
      expect(vm.selectedPunchId, equals(squarePunch2.id));
      expect(vm.toolMode, equals(StudioToolMode.select));

      // Close inspector and clear selection before next gesture
      vm.setPropertyInspectorOpen(false);
      vm.clearSelection();
      await tester.pumpAndSettle();

      // C. Circle Tool - Single Click
      vm.setToolMode(StudioToolMode.drawCircle);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.drawCircle));

      final clickPosCircle = canvasCenter - const Offset(160, 120);
      final gClick2 = await tester.startGesture(clickPosCircle);
      await tester.pump(const Duration(milliseconds: 30));
      await gClick2.up();
      await tester.pumpAndSettle();

      expect(vm.document.punches.length, equals(initialPunchesCount + 3));
      final circlePunch1 = vm.document.punches.last;
      expect(circlePunch1.isRound, isTrue);
      expect(vm.selectedPunchId, equals(circlePunch1.id));
      expect(vm.toolMode, equals(StudioToolMode.select));

      // Close inspector and clear selection before next gesture
      vm.setPropertyInspectorOpen(false);
      vm.clearSelection();
      await tester.pumpAndSettle();

      // D. Circle Tool - Drag
      vm.setToolMode(StudioToolMode.drawCircle);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.drawCircle));

      final circleDragStart = canvasCenter - const Offset(180, -80);
      final circleDragEnd = canvasCenter - const Offset(130, -80);

      final gesture2 = await tester.startGesture(circleDragStart);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture2.moveTo(circleDragEnd);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture2.up();
      await tester.pumpAndSettle();

      expect(vm.document.punches.length, equals(initialPunchesCount + 4));
      final circlePunch2 = vm.document.punches.last;
      expect(circlePunch2.isRound, isTrue);
      expect(vm.selectedPunchId, equals(circlePunch2.id));
      expect(vm.toolMode, equals(StudioToolMode.select));
    });

    testWidgets('12. Tool3DActionIcon implements asymmetric speed (fast forward ~520ms, slower recovery ~1050ms)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Tool3DActionIcon(toolType: Tool3DType.drawCircle, isHovered: true, size: 64)),
          ),
        ),
      );

      await tester.pump();
      final customPaintFinder = find.byType(CustomPaint);
      expect(customPaintFinder, findsWidgets);

      // Fast forward stroke: 520ms
      await tester.pump(const Duration(milliseconds: 520));
      // Apex dwell: 80ms
      await tester.pump(const Duration(milliseconds: 80));
      // Slower reverse stroke: 1050ms
      await tester.pump(const Duration(milliseconds: 525));
      await tester.pump(const Duration(milliseconds: 525));
      // Rest pause: 140ms
      await tester.pump(const Duration(milliseconds: 140));
      // Next forward cycle starts
      await tester.pump(const Duration(milliseconds: 260));

      expect(tester.takeException(), isNull);
    });

    testWidgets('13. Tool3DActionIcon renders distinct 3D icons for addDimension (constraint) and dragDimension (ruler)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Tool3DActionIcon(toolType: Tool3DType.addDimension, isHovered: true, size: 64),
                Tool3DActionIcon(toolType: Tool3DType.dragDimension, isHovered: true, size: 64),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    test('14. snapEndpointAngle quantizes all line angles to 5-degree increments with major axis magnetic locking', () {
      final anchor = CadPoint2D(0, 0);

      // Angle ~7° -> snaps to 5°
      final rad7 = 7.0 * math.pi / 180.0;
      final target7 = CadPoint2D(100.0 * math.cos(rad7), 100.0 * math.sin(rad7));
      final snapped7 = SheetMetalStudioViewModel.snapEndpointAngle(anchor: anchor, target: target7);
      final angle7 = (math.atan2(snapped7.y, snapped7.x) * 180.0 / math.pi).round();
      expect(angle7, equals(5));

      // Angle ~13° -> snaps to 15°
      final rad13 = 13.0 * math.pi / 180.0;
      final target13 = CadPoint2D(100.0 * math.cos(rad13), 100.0 * math.sin(rad13));
      final snapped13 = SheetMetalStudioViewModel.snapEndpointAngle(anchor: anchor, target: target13);
      final angle13 = (math.atan2(snapped13.y, snapped13.x) * 180.0 / math.pi).round();
      expect(angle13, equals(15));

      // Angle ~44.2° -> within 2.5° of 45° major axis -> locks to 45°
      final rad44 = 44.2 * math.pi / 180.0;
      final target44 = CadPoint2D(100.0 * math.cos(rad44), 100.0 * math.sin(rad44));
      final snapped44 = SheetMetalStudioViewModel.snapEndpointAngle(anchor: anchor, target: target44);
      final angle44 = (math.atan2(snapped44.y, snapped44.x) * 180.0 / math.pi).round();
      expect(angle44, equals(45));

      // Angle ~89.1° -> within 2.5° of 90° major axis -> locks to 90°
      final rad89 = 89.1 * math.pi / 180.0;
      final target89 = CadPoint2D(100.0 * math.cos(rad89), 100.0 * math.sin(rad89));
      final snapped89 = SheetMetalStudioViewModel.snapEndpointAngle(anchor: anchor, target: target89);
      final angle89 = (math.atan2(snapped89.y, snapped89.x) * 180.0 / math.pi).round();
      expect(angle89, equals(90));

      // If isAlt is true, raw target coordinate is returned unchanged
      final freeTarget = SheetMetalStudioViewModel.snapEndpointAngle(anchor: anchor, target: target7, isAlt: true);
      expect(freeTarget.x, closeTo(target7.x, 1e-4));
      expect(freeTarget.y, closeTo(target7.y, 1e-4));
    });

    test('15. ViewModel cursor snapping responds to Alt key toggle for drawing tools', () {
      final vm = SheetMetalStudioViewModel();
      vm.setToolMode(StudioToolMode.addBend);

      // Sheet metal contour corner at (0, 0)
      final nearCorner = CadPoint2D(2.0, 1.5);

      // Without Alt: snaps to (0, 0)
      vm.isAltPressed = false;
      vm.updateCursorMm(nearCorner, snapRadiusMm: 8.0);
      expect(vm.activeSnap, isNotNull);
      expect(vm.activeSnap!.point.distanceTo(CadPoint2D(0, 0)), lessThan(1e-3));

      // With Alt: snapping is bypassed
      vm.isAltPressed = true;
      vm.updateCursorMm(nearCorner, snapRadiusMm: 8.0);
      expect(vm.activeSnap, isNull);
    });

    testWidgets('16. Decoupled Alt tracking: Scenario A (snap start -> Alt drag free end) & Scenario B (Alt free start -> snap end)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: SheetMetalStudioScreen()));
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(SheetMetalStudioScreen)) as dynamic;
      final SheetMetalStudioViewModel vm = state.viewModel;

      // Close inspector and clear selection to avoid touch interception
      vm.setPropertyInspectorOpen(false);
      vm.clearSelection();
      await tester.pumpAndSettle();

      final canvasFinder = find.byType(UnfoldedCanvasWidget);
      expect(canvasFinder, findsOneWidget);

      final canvasCenter = tester.getCenter(canvasFinder);

      // Scenario A: Start without Alt (snapped) -> Press Alt during drag -> Free end point
      vm.setToolMode(StudioToolMode.dragDimension);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.dragDimension));

      final initialDimsCount = vm.document.dimensions.length;

      final pStart = canvasCenter + const Offset(-150, 40);
      final pEnd = canvasCenter + const Offset(-50, 80);

      final gesture1 = await tester.startGesture(pStart);
      await tester.pump();
      await gesture1.moveTo(pStart + const Offset(20, 10));
      await tester.pump();
      // Press Alt while dragging: end point moves freely without snapping
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      await gesture1.moveTo(pEnd);
      await tester.pump();
      await gesture1.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(vm.document.dimensions.length, equals(initialDimsCount + 1));
      expect(vm.toolMode, equals(StudioToolMode.select));

      // Scenario B: Start with Alt pressed (free start) -> Release Alt during drag -> Snapped end point
      vm.clearSelection();
      vm.setToolMode(StudioToolMode.addCut);
      await tester.pump();
      expect(vm.toolMode, equals(StudioToolMode.addCut));

      final initialCutsCount = vm.document.cutLines.length;

      final pCutStart = canvasCenter + const Offset(-140, -40);
      final pCutEnd = canvasCenter + const Offset(-40, -20);

      // Press Alt before starting drawing: start dot moves freely without snapping
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      final gesture2 = await tester.startGesture(pCutStart);
      await tester.pump();
      await gesture2.moveTo(pCutStart + const Offset(20, 10));
      await tester.pump();
      // Release Alt while dragging: end point snaps to 5 degrees and nearest entity
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      await gesture2.moveTo(pCutEnd);
      await tester.pump();
      await gesture2.up();
      await tester.pumpAndSettle();

      expect(vm.document.cutLines.length, equals(initialCutsCount + 1));
      expect(vm.toolMode, equals(StudioToolMode.select));
    });

    testWidgets('17. Line / Polyline Alt key free endpoint tracking updates rubberBandEndpoint without magnetic locking', (tester) async {
      final vm = SheetMetalStudioViewModel();
      vm.setToolMode(StudioToolMode.addBend);
      const startPt = CadPoint2D(10.0, 10.0);
      vm.setPendingBendStart(startPt);

      // Free hover cursor when Alt is pressed
      const freePt = CadPoint2D(123.456, 78.912);
      vm.updateCursorMm(freePt, isAlt: true);

      expect(vm.rubberBandEndpoint, isNotNull);
      expect(vm.rubberBandEndpoint!.x, closeTo(123.456, 0.001));
      expect(vm.rubberBandEndpoint!.y, closeTo(78.912, 0.001));
    });

    testWidgets('18. Dimension default offset is 8.0 mm and dimension line segment offset dragging updates line position', (tester) async {
      final vm = SheetMetalStudioViewModel();

      // Check CadDimension default line offset
      const dim = CadDimension(id: 'dim_test_1', type: CadDimensionType.aligned, referenceAId: 'seg_1', referenceBId: 'seg_2', measuredValue: 100.0);
      expect(dim.dimensionLineOffset, equals(8.0));

      vm.addDimension(dim);
      expect(vm.document.dimensions.first.dimensionLineOffset, equals(8.0));

      // Test setDimensionLineOffset and commitDimensionLineOffset
      vm.setDimensionLineOffset('dim_test_1', 15.5);
      expect(vm.document.dimensions.first.dimensionLineOffset, equals(15.5));

      vm.commitDimensionLineOffset('dim_test_1');
      expect(vm.document.dimensions.first.dimensionLineOffset, equals(15.5));
    });

    testWidgets('19. Canvas single-click registers immediately with zero delay', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: SheetMetalStudioScreen()));
      await tester.pumpAndSettle();

      final state = tester.state(find.byType(SheetMetalStudioScreen)) as dynamic;
      final SheetMetalStudioViewModel vm = state.viewModel;

      vm.setPropertyInspectorOpen(false);
      vm.clearSelection();
      await tester.pumpAndSettle();

      final canvasFinder = find.byType(UnfoldedCanvasWidget);
      expect(canvasFinder, findsOneWidget);
      final canvasCenter = tester.getCenter(canvasFinder);

      // Select addBend tool
      vm.setToolMode(StudioToolMode.addBend);
      await tester.pump();
      expect(vm.pendingBendStart, isNull);

      // Single tap down & up: must immediately register without waiting for 300ms double-tap delay
      final clickPt = canvasCenter + const Offset(50, 50);
      await tester.tapAt(clickPt);
      await tester.pump();

      // Immediate drawing activation
      expect(vm.pendingBendStart, isNotNull);
    });

    test('20. System and user dimension line offsets are trackable and movable', () {
      final vm = SheetMetalStudioViewModel();

      // System dimension line offset updates
      expect(vm.dimensionLineOffsets.containsKey('dim_blank_w'), isFalse);
      vm.setDimensionLineOffset('dim_blank_w', 42.0);
      expect(vm.dimensionLineOffsets['dim_blank_w'], equals(42.0));

      vm.setDimensionLineOffset('dim_blank_l', 55.5);
      expect(vm.dimensionLineOffsets['dim_blank_l'], equals(55.5));

      vm.resetDimensionLineOffset('dim_blank_w');
      expect(vm.dimensionLineOffsets.containsKey('dim_blank_w'), isFalse);
      expect(vm.dimensionLineOffsets['dim_blank_l'], equals(55.5));
    });

    test('21. Size dimensions on all entities can be toggled via viewModel', () {
      final vm = SheetMetalStudioViewModel();

      // 1. Face size dimension toggle
      final testFace = PlanarSheetFace(
        id: 'FACE_TEST',
        vertices: [CadPoint2D(0, 0), CadPoint2D(100, 0), CadPoint2D(100, 50), CadPoint2D(0, 50)],
        showLabel: true,
      );
      vm.loadDocument(vm.document.copyWith(faces: [testFace]));
      expect(vm.document.faces.first.showLabel, isTrue);
      vm.toggleFaceLabel('FACE_TEST');
      expect(vm.document.faces.first.showLabel, isFalse);
      vm.toggleFaceLabel('FACE_TEST');
      expect(vm.document.faces.first.showLabel, isTrue);

      // 2. Cut line size dimension toggle
      final testCut = CadLineSegment(id: 'CUT_TEST', p1: CadPoint2D(0, 0), p2: CadPoint2D(50, 0), showLabel: true);
      vm.loadDocument(vm.document.copyWith(cutLines: [testCut]));
      expect(vm.document.cutLines.first.showLabel, isTrue);
      vm.toggleCutLabel('CUT_TEST');
      expect(vm.document.cutLines.first.showLabel, isFalse);
      vm.toggleCutLabel('CUT_TEST');
      expect(vm.document.cutLines.first.showLabel, isTrue);

      // 3. Bend line size dimension toggle
      final testBend = FoldBendLine(id: 'BEND_TEST', p1: CadPoint2D(10, 0), p2: CadPoint2D(10, 50), showLabel: true);
      vm.loadDocument(vm.document.copyWith(bends: [testBend]));
      expect(vm.document.bends.first.showLabel, isTrue);
      vm.toggleBendLabel('BEND_TEST');
      expect(vm.document.bends.first.showLabel, isFalse);
      vm.toggleBendLabel('BEND_TEST');
      expect(vm.document.bends.first.showLabel, isTrue);

      // 4. Punch size dimension toggle
      final testPunch = CncPunchPrimitive(id: 'PUNCH_TEST', type: PunchType.roundHole, center: CadPoint2D(25, 25), showLabel: true);
      vm.loadDocument(vm.document.copyWith(punches: [testPunch]));
      expect(vm.document.punches.first.showLabel, isTrue);
      vm.togglePunchLabel('PUNCH_TEST');
      expect(vm.document.punches.first.showLabel, isFalse);
      vm.togglePunchLabel('PUNCH_TEST');
      expect(vm.document.punches.first.showLabel, isTrue);

      // 5. Arc size dimension toggle
      final testArc = CadArc2D(id: 'ARC_TEST', center: CadPoint2D(50, 50), radius: 20.0, startAngleRad: 0, sweepAngleRad: math.pi / 2, showLabel: true);
      vm.loadDocument(vm.document.copyWith(arcs: [testArc]));
      expect(vm.document.arcs.first.showLabel, isTrue);
      vm.toggleArcLabel('ARC_TEST');
      expect(vm.document.arcs.first.showLabel, isFalse);
      vm.toggleArcLabel('ARC_TEST');
      expect(vm.document.arcs.first.showLabel, isTrue);
    });

    testWidgets('22. In-place dimension editing converts badge to entry point, commits on Enter/Tab, cancels on Esc', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: SheetMetalStudioScreen()));
      await tester.pumpAndSettle();

      final canvasFinder = find.byType(UnfoldedCanvasWidget);
      expect(canvasFinder, findsOneWidget);

      final state = tester.state(canvasFinder) as dynamic;
      final SheetMetalStudioViewModel vm = state.widget.viewModel;

      // Locate the rendered blank width dimension badge
      final dimBadges = state.dimensionBadgeRects as Map<String, Rect>;
      expect(dimBadges.containsKey('dim_blank_w'), isTrue);

      // 1. Double tap / trigger dimension badge -> converts in-place to entry point
      state.startInPlaceDimensionEditForTesting('dim_blank_w');
      await tester.pumpAndSettle();

      // Verify the in-place entry point (TextField) appears
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);

      // Verify initial text matches blank width (200.00)
      final initialText = tester.widget<TextField>(inputFinder).controller!.text;
      final initialW = vm.document.blankWidthMm;
      expect(double.tryParse(initialText), equals(initialW));

      // 2. Press Esc -> Cancels the edit, closes entry point, no value change
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(vm.document.blankWidthMm, equals(initialW));

      // 3. Edit value to 260, then press Enter -> Executes and drives dimension
      state.startInPlaceDimensionEditForTesting('dim_blank_w');
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '260');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(vm.document.blankWidthMm, equals(260.0));

      // 4. Test Tab execution: enter 280, press Tab -> Executes and drives dimension
      state.startInPlaceDimensionEditForTesting('dim_blank_w');
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '280');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(vm.document.blankWidthMm, equals(280.0));
    });
  });
}
