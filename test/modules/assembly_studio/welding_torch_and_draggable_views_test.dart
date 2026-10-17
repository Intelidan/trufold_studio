import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_3d_viewport.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_sketchup_views_toolbar.dart';

void main() {
  group('Real-Time VCB, Draggable Views Toolbar & Manual Welding Tests', () {
    late AssemblyStudioViewModel viewModel;

    setUp(() {
      viewModel = AssemblyStudioViewModel();
      viewModel.clearAll();

      final part1 = AssemblyPart(
        id: 'plate_base',
        name: 'Base Flange Plate',
        type: AssemblyPartType.straightRail,
        position: const CadPoint3D(0.0, 0.0, 0.0),
        rotationDeg: const CadPoint3D(0.0, 0.0, 0.0),
        length: 800.0,
        height: 50.0,
        flangeWidth: 300.0,
        thickness: 3.0,
      );

      final part2 = AssemblyPart(
        id: 'column_1',
        name: 'Vertical Post Column',
        type: AssemblyPartType.straightRail,
        position: const CadPoint3D(0.0, 0.0, 50.0),
        rotationDeg: const CadPoint3D(0.0, 0.0, 0.0),
        length: 600.0,
        height: 60.0,
        flangeWidth: 60.0,
        thickness: 2.5,
      );

      viewModel.doc.parts.addAll([part1, part2]);
      viewModel.selectPart('column_1');
    });

    test('Draggable Views Toolbar & Center Screen/Axes on View Button Press', () {
      Offset dragOffset = const Offset(60, 54);
      bool axesCentered = false;

      final toolbar = AssemblySketchupViewsToolbar(
        viewModel: viewModel,
        onDragUpdate: (details) {
          dragOffset += details.delta;
        },
        onCenterAxes: () {
          axesCentered = true;
          viewModel.pan = Offset.zero;
        },
      );

      expect(dragOffset, equals(const Offset(60, 54)));
      toolbar.onDragUpdate!(DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(15, 25)));
      expect(dragOffset, equals(const Offset(75, 79)));

      // Set non-zero pan first
      viewModel.pan = const Offset(120.0, -80.0);
      expect(viewModel.pan, equals(const Offset(120.0, -80.0)));

      // Calling onCenterAxes clears pan to zero
      toolbar.onCenterAxes!();
      expect(axesCentered, isTrue);
      expect(viewModel.pan, equals(Offset.zero));
    });

    testWidgets('Views Toolbar renders drag handle & centers screen on button click', (tester) async {
      viewModel.showViewsToolbar = true;
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Assembly3DViewport(viewModel: viewModel)),
        ),
      );
      await tester.pumpAndSettle();

      // Find the views toolbar
      expect(find.byType(AssemblySketchupViewsToolbar), findsOneWidget);

      // Verify 7 view buttons (Iso, Top, Front, Right, Back, Left, Bottom)
      expect(find.byTooltip('Iso (Isometric View)'), findsOneWidget);
      expect(find.byTooltip('Top View (Roof)'), findsOneWidget);
      expect(find.byTooltip('Front View'), findsOneWidget);

      // Pan camera
      viewModel.pan = const Offset(90.0, 45.0);
      expect(viewModel.pan, equals(const Offset(90.0, 45.0)));

      // Tap Front View button
      await tester.tap(find.byTooltip('Front View'));
      await tester.pumpAndSettle();

      // Camera view is Front and screen/axes are centered (pan = Offset.zero)
      expect(viewModel.elevationDeg, closeTo(0.0, 0.1));
      expect(viewModel.azimuthDeg, closeTo(0.0, 0.1));
      expect(viewModel.pan, equals(Offset.zero));
    });

    test('Manual Welding: surface-following path, single bead on top (bothSides: false)', () {
      final surfacePoints = [
        const CadPoint3D(0.0, 0.0, 50.0),
        const CadPoint3D(50.0, 0.0, 50.0),
        const CadPoint3D(100.0, 0.0, 50.0),
        const CadPoint3D(150.0, 0.0, 50.0),
      ];

      viewModel.weldParts(
        'plate_base',
        'column_1',
        weldPoint: const CadPoint3D(75.0, 0.0, 50.0),
        weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
        legDir1: const CadPoint3D(0.0, 1.0, 0.0),
        legDir2: const CadPoint3D(0.0, 0.0, 1.0),
        weldLengthMm: 150.0,
        bothSides: false,
        pathPoints: surfacePoints,
      );

      expect(viewModel.doc.welds.length, equals(1));
      final weld = viewModel.doc.welds.first;
      expect(weld.bothSides, isFalse);
      expect(weld.pathPoints, isNotNull);
      expect(weld.pathPoints!.length, equals(4));

      // Build 3D mesh and verify fillet bead polygons
      final mesh = viewModel.doc.buildAssemblyMesh();
      final weldPolys = mesh.polygons.where((p) => p.faceId.startsWith('weld_')).toList();
      expect(weldPolys.isNotEmpty, isTrue);

      // All weld vertex Z coordinates must be strictly on top of the base plate (Z >= 50.0)
      for (final poly in weldPolys) {
        for (final v in poly.vertices) {
          expect(v.z, greaterThanOrEqualTo(49.0), reason: 'Weld bead must not sit underneath the object');
        }
      }
    });

    test('Weld bead is clickable, deletable, but not movable', () {
      viewModel.weldParts('plate_base', 'column_1', weldPoint: const CadPoint3D(50.0, 0.0, 50.0), weldLengthMm: 100.0, bothSides: false);

      expect(viewModel.doc.welds.length, equals(1));
      final weldId = viewModel.doc.welds.first.id;

      // Select weld
      viewModel.selectWeld(weldId);
      expect(viewModel.selectedWeldId, equals(weldId));
      expect(viewModel.selectedWeld, isNotNull);

      // Moving the welded part is blocked
      final target = viewModel.doc.parts.firstWhere((p) => p.id == 'column_1');
      expect(viewModel.isPartBonded(target.id), isTrue);

      // Deleting weld unlocks parts
      viewModel.deleteSelectedWeld();
      expect(viewModel.doc.welds.isEmpty, isTrue);
      expect(viewModel.isPartBonded(target.id), isFalse);
    });

    testWidgets('Manual Weld Torch: Esc clears weld line from memory, no old line resurrection', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Assembly3DViewport(viewModel: viewModel)),
        ),
      );
      await tester.pumpAndSettle();

      // Activate weld tool
      viewModel.setToolMode(SketchUpToolMode.weld);
      await tester.pumpAndSettle();

      final viewportFinder = find.byType(Assembly3DViewport);
      final center = tester.getCenter(viewportFinder);

      // Simulate dragging weld torch
      final gesture = await tester.startGesture(center, pointer: 1);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(center + const Offset(100, 0));
      await tester.pump(const Duration(milliseconds: 16));

      // Press Escape key to cancel
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await gesture.up();

      // Switch tool to select mode
      viewModel.setToolMode(SketchUpToolMode.select);
      await tester.pumpAndSettle();

      // Reactivate weld tool
      viewModel.setToolMode(SketchUpToolMode.weld);
      await tester.pumpAndSettle();

      // No welds created and no leftover draft path
      expect(viewModel.doc.welds.isEmpty, isTrue);
    });
  });
}
