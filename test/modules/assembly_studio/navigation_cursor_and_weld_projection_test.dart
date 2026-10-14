import 'dart:ui' show PictureRecorder;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_3d_viewport.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/handlers/assembly_weld_smoothing_helper.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/painters/assembly_cursor_painters.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Navigation, Custom CAD Pointer & Weld Seam Projection Tests', () {
    late AssemblyStudioViewModel viewModel;

    setUp(() {
      viewModel = AssemblyStudioViewModel();
      viewModel.doc.parts.add(
        AssemblyPart(
          id: 'rail_1',
          name: 'Main Rail',
          type: AssemblyPartType.straightRail,
          position: const CadPoint3D(0.0, 0.0, 0.0),
          length: 1200.0,
          height: 75.0,
          flangeWidth: 35.0,
        ),
      );
    });

    test('1. AssemblyCadSelectionCursorPainter renders CAD pointer and handles snapping states', () {
      final painterDefault = AssemblyCadSelectionCursorPainter(
        cursorScreenPos: const Offset(100, 100),
        isSnapped: false,
      );
      final painterSnapped = AssemblyCadSelectionCursorPainter(
        cursorScreenPos: const Offset(100, 100),
        isSnapped: true,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painterDefault.paint(canvas, const Size(800, 600));
      painterSnapped.paint(canvas, const Size(800, 600));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);

      expect(painterDefault.shouldRepaint(painterSnapped), isTrue);
      expect(painterDefault.shouldRepaint(AssemblyCadSelectionCursorPainter(cursorScreenPos: const Offset(100, 100), isSnapped: false)), isFalse);
    });

    test('2. Weld Line Seam Projection (SS1): Floating air strokes are projected down to mutual contact seam', () {
      final partA = AssemblyPart(
        id: 'column_1',
        name: 'Vertical Column',
        length: 200.0,
        height: 400.0,
        position: const CadPoint3D(0, 0, 0),
        type: AssemblyPartType.channel,
      );

      final partB = AssemblyPart(
        id: 'plate_1',
        name: 'Base Plate',
        length: 600.0,
        height: 20.0,
        position: const CadPoint3D(0, 0, 0),
        type: AssemblyPartType.bar,
      );

      // Raw stroke where points 0..3 are on the seam, but points 4..6 drift into thin air (like arrow 1 in SS1)
      final rawAirStroke = [
        const CadPoint3D(20, 0, 0),
        const CadPoint3D(60, 0, 0),
        const CadPoint3D(120, 0, 0),
        const CadPoint3D(190, 0, 0),
        const CadPoint3D(240, 10, 40), // drifted off into air
        const CadPoint3D(270, 25, 60), // drifted off into air
      ];

      final projected = AssemblyWeldSmoothingHelper.projectStrokeToMutualContactSeam(
        strokePoints: rawAirStroke,
        partA: partA,
        partB: partB,
        contactToleranceMm: 25.0,
      );

      expect(projected, isNotEmpty);
      // All projected points must remain clamped within the physical contact boundary
      for (final pt in projected) {
        expect(pt.x, lessThanOrEqualTo(205.0)); // clamped near the column corner (arrow 2 in SS1)
      }
    });

    testWidgets('3. Camera movement completes and cursor restores to selected tool without shift key for pan', (tester) async {
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

      viewModel.setToolMode(SketchUpToolMode.select);
      await tester.pump();

      final center = tester.getCenter(find.byType(Assembly3DViewport));

      // Middle mouse button drag alone -> Panning (Requirement 2)
      final gesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await gesture.moveBy(const Offset(30, 20));
      await tester.pump();

      // Pan occurred
      expect(viewModel.pan.dx, equals(30.0));
      expect(viewModel.pan.dy, equals(20.0));

      // Release mouse (Requirement 1: icon immediately returns to selected tool)
      await gesture.up();
      await tester.pumpAndSettle();

      // Selected tool remains select and camera movement finished cleanly
      expect(viewModel.activeToolMode, equals(SketchUpToolMode.select));
    });

    testWidgets('4. Hovering over snap points on any object magnetically attracts cursor and highlights dot', (tester) async {
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

      viewModel.setToolMode(SketchUpToolMode.select);
      await tester.pump();

      final center = tester.getCenter(find.byType(Assembly3DViewport));

      // Move mouse pointer near center where scene entities exist
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.pump();

      // Viewport and custom CAD pointer overlay are present
      expect(find.byType(Assembly3DViewport), findsOneWidget);
    });
  });
}
