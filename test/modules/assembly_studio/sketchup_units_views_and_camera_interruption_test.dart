import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_3d_viewport.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_sketchup_views_toolbar.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_sketchup_toolbar.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_measurement_units_card.dart';

void main() {
  group('Assembly Studio - Requirements 1 to 4 Tests', () {
    late AssemblyStudioViewModel viewModel;

    setUp(() {
      viewModel = AssemblyStudioViewModel();
      viewModel.clearAll();

      final part1 = AssemblyPart(
        id: 'rail_1',
        name: 'Left Stile Rail',
        type: AssemblyPartType.straightRail,
        position: const CadPoint3D(0.0, 0.0, 0.0),
        rotationDeg: const CadPoint3D(0.0, 0.0, 0.0),
        length: 1200.0,
        height: 75.0,
        flangeWidth: 35.0,
        thickness: 2.0,
      );

      final part2 = AssemblyPart(
        id: 'rail_2',
        name: 'Right Stile Rail',
        type: AssemblyPartType.straightRail,
        position: const CadPoint3D(0.0, 450.0, 0.0),
        rotationDeg: const CadPoint3D(0.0, 0.0, 0.0),
        length: 1200.0,
        height: 75.0,
        flangeWidth: 35.0,
        thickness: 2.0,
      );

      viewModel.doc.parts.addAll([part1, part2]);
      viewModel.selectPart('rail_1');
    });

    test('Requirement 3 (SS2): Measurement Units preferences & precision step control', () {
      // Default: Millimeters, Decimal, 4 decimal places
      expect(viewModel.lengthUnit, equals(MeasurementLengthUnit.millimeters));
      expect(viewModel.lengthDisplayPrecision, equals(4));
      expect(viewModel.precisionMovementStepMm, closeTo(0.0001, 1e-6));
      expect(viewModel.formatLength(22.6), equals('22.6000 mm'));

      // Change precision to 1 decimal place (0.0 mm)
      viewModel.setMeasurementSettings(lengthPrecision: 1);
      expect(viewModel.lengthDisplayPrecision, equals(1));
      expect(viewModel.precisionMovementStepMm, closeTo(0.1, 1e-6));
      expect(viewModel.formatLength(22.6), equals('22.6 mm'));

      // Change precision to 0 decimal places (0 mm)
      viewModel.setMeasurementSettings(lengthPrecision: 0);
      expect(viewModel.precisionMovementStepMm, closeTo(1.0, 1e-6));
      expect(viewModel.formatLength(22.6), equals('23 mm'));

      // Change length unit to Centimeters
      viewModel.setMeasurementSettings(length: MeasurementLengthUnit.centimeters, lengthPrecision: 2);
      expect(viewModel.lengthUnit, equals(MeasurementLengthUnit.centimeters));
      // 0.01 cm = 0.1 mm step
      expect(viewModel.precisionMovementStepMm, closeTo(0.1, 1e-6));
      expect(viewModel.formatLength(226.0), equals('22.60 cm'));

      // Length snapping override
      viewModel.setMeasurementSettings(
        length: MeasurementLengthUnit.millimeters,
        lengthPrecision: 4,
        lengthSnapping: true,
        snapStep: 5.0,
      );
      expect(viewModel.enableLengthSnapping, isTrue);
      expect(viewModel.precisionMovementStepMm, closeTo(5.0, 1e-6));

      // Display units format toggle
      viewModel.setMeasurementSettings(showUnitsFormat: false);
      expect(viewModel.formatLength(25.0), equals('25.0000'));
    });

    test('Requirement 4 (SS3): SketchUp Standard Views camera angle presets', () {
      // 1. Iso
      viewModel.setStandardView(SketchUpStandardView.iso);
      expect(viewModel.azimuthDeg, closeTo(45.0, 0.1));
      expect(viewModel.elevationDeg, closeTo(35.264, 0.1));
      expect(viewModel.isOrthoProjection, isFalse);

      // 2. Top
      viewModel.setStandardView(SketchUpStandardView.top);
      expect(viewModel.azimuthDeg, closeTo(0.0, 0.1));
      expect(viewModel.elevationDeg, closeTo(89.9, 0.1));
      expect(viewModel.isOrthoProjection, isTrue);

      // 3. Front
      viewModel.setStandardView(SketchUpStandardView.front);
      expect(viewModel.azimuthDeg, closeTo(0.0, 0.1));
      expect(viewModel.elevationDeg, closeTo(0.0, 0.1));

      // 4. Right
      viewModel.setStandardView(SketchUpStandardView.right);
      expect(viewModel.azimuthDeg, closeTo(90.0, 0.1));
      expect(viewModel.elevationDeg, closeTo(0.0, 0.1));

      // 5. Back
      viewModel.setStandardView(SketchUpStandardView.back);
      expect(viewModel.azimuthDeg, closeTo(180.0, 0.1));
      expect(viewModel.elevationDeg, closeTo(0.0, 0.1));

      // 6. Left
      viewModel.setStandardView(SketchUpStandardView.left);
      expect(viewModel.azimuthDeg, closeTo(270.0, 0.1));
      expect(viewModel.elevationDeg, closeTo(0.0, 0.1));

      // 7. Bottom
      viewModel.setStandardView(SketchUpStandardView.bottom);
      expect(viewModel.azimuthDeg, closeTo(0.0, 0.1));
      expect(viewModel.elevationDeg, closeTo(-89.9, 0.1));
    });

    testWidgets('Requirement 4 (SS3): AssemblySketchupViewsToolbar renders 7 house icons & updates view', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssemblySketchupViewsToolbar(viewModel: viewModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify toolbar exists
      expect(find.byType(AssemblySketchupViewsToolbar), findsOneWidget);

      // Tap Top view button (second button)
      final buttons = find.byType(InkWell);
      expect(buttons, findsNWidgets(7));

      // Tap Top (index 1)
      await tester.tap(buttons.at(1));
      await tester.pumpAndSettle();
      expect(viewModel.elevationDeg, closeTo(89.9, 0.1));

      // Tap Front (index 2)
      await tester.tap(buttons.at(2));
      await tester.pumpAndSettle();
      expect(viewModel.elevationDeg, closeTo(0.0, 0.1));
      expect(viewModel.azimuthDeg, closeTo(0.0, 0.1));
    });

    testWidgets('Requirement 3 (SS2): AssemblyMeasurementUnitsCard renders all controls matching SS2', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssemblyMeasurementUnitsCard(viewModel: viewModel, isDialog: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Measurement units'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);
      expect(find.text('Length'), findsOneWidget);
      expect(find.text('Area'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('Enable length snapping'), findsOneWidget);
      expect(find.text('Display units format'), findsOneWidget);
      expect(find.text('Force display of 0"'), findsOneWidget);
      expect(find.text('Angle Units'), findsOneWidget);
      expect(find.text('Enable angle snapping'), findsOneWidget);
    });

    testWidgets('Requirement 1 & 2: Camera navigation does not drop held object & VCB text reverts on blank', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: Assembly3DViewport(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Activate Move Tool
      viewModel.setToolMode(SketchUpToolMode.move);
      await tester.pumpAndSettle();

      final viewportCenter = tester.getCenter(find.byType(Assembly3DViewport));

      // 2. Click 1: Pick entity (ready for movement)
      final gesture = await tester.startGesture(viewportCenter, buttons: kPrimaryMouseButton);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      // Entity is now in motion
      expect(viewModel.vcbLabel, equals('Distance'));

      // 3. Middle / Right mouse button down & drag to orbit camera
      // Requirement 1: Camera navigation must NOT release or commit held object!
      final camGesture = await tester.startGesture(viewportCenter, buttons: kMiddleMouseButton);
      await camGesture.moveBy(const Offset(40, -30));
      await tester.pump(const Duration(milliseconds: 50));
      await camGesture.up();
      await tester.pumpAndSettle();

      // Releasing camera button must NOT commit the move: Move is still active!
      expect(viewModel.activeToolMode, equals(SketchUpToolMode.move));

      // 4. Test VCB text input live replacement & blank/invalid reversion (Requirement 2)
      // Enter a valid number "100" in VCB
      final textField = find.byType(TextField);
      expect(textField, findsWidgets);

      await tester.enterText(textField.first, '100');
      await tester.pumpAndSettle();

      final movingPart = viewModel.doc.parts.firstWhere((p) => p.id == 'rail_1');
      // Part moved by 100mm
      expect(movingPart.position.x, closeTo(100.0, 1.0));

      // Now clear / enter invalid blank text in VCB
      await tester.enterText(textField.first, '');
      await tester.pumpAndSettle();

      // Requirement 2: "And is the value is invalid or blank then the object should assume the original position."
      expect(movingPart.position.x, closeTo(0.0, 0.01));
      expect(movingPart.position.y, closeTo(0.0, 0.01));
      expect(movingPart.position.z, closeTo(0.0, 0.01));
    });

    testWidgets('Ctrl+Z (Undo) and Ctrl+Y (Redo) restore and reapply part modifications', (tester) async {
      final initialPartCount = viewModel.doc.parts.length;
      expect(initialPartCount, equals(2));

      // 1. Add a rung (records undo)
      viewModel.addRung(length: 500.0);
      expect(viewModel.doc.parts.length, equals(3));
      expect(viewModel.canUndo, isTrue);

      // 2. Undo via Ctrl+Z
      viewModel.undo();
      expect(viewModel.doc.parts.length, equals(2));
      expect(viewModel.canRedo, isTrue);

      // 3. Redo via Ctrl+Y
      viewModel.redo();
      expect(viewModel.doc.parts.length, equals(3));

      // 4. Test within UI with Focus and Keyboard Shortcuts
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: Assembly3DViewport(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger Ctrl+Z
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(viewModel.doc.parts.length, equals(2));

      // Trigger Ctrl+Y
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(viewModel.doc.parts.length, equals(3));
    });

    testWidgets('Middle mouse rotation and Shift + Middle mouse panning in Assembly3DViewport', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: Assembly3DViewport(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(Assembly3DViewport));
      final initAz = viewModel.azimuthDeg;
      expect(viewModel.pan, equals(Offset.zero));

      // a. Middle mouse button drag -> Rotation (Orbit)
      final orbitGesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await orbitGesture.moveBy(const Offset(50, -30));
      await tester.pump();
      await orbitGesture.up();
      await tester.pumpAndSettle();

      expect(viewModel.azimuthDeg, isNot(equals(initAz)));

      // b. Shift + Middle mouse button drag -> Panning
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final panGesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await panGesture.moveBy(const Offset(40, 20));
      await tester.pump();
      await panGesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(viewModel.pan.dx, equals(40.0));
      expect(viewModel.pan.dy, equals(20.0));
    });

    testWidgets('Orbit & Pan camera tools exist in AssemblySketchupToolbar matching SS1', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssemblySketchupToolbar(
              viewModel: viewModel,
              onZoomExtents: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tooltips for Orbit and Pan tools
      final orbitBtn = find.byTooltip('Orbit Camera (O) • Middle Mouse Drag');
      final panBtn = find.byTooltip('Pan Camera (H) • Shift + Middle Mouse Drag');

      expect(orbitBtn, findsOneWidget);
      expect(panBtn, findsOneWidget);

      // Tap Orbit tool
      await tester.tap(orbitBtn);
      await tester.pumpAndSettle();
      expect(viewModel.activeToolMode, equals(SketchUpToolMode.orbit));

      // Tap Pan tool
      await tester.tap(panBtn);
      await tester.pumpAndSettle();
      expect(viewModel.activeToolMode, equals(SketchUpToolMode.pan));
    });
  });
}
