import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/assembly_studio/engine/assembly_docking_engine.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_document.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_docking_zone.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_3d_viewport.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/painters/assembly_gizmo_painters.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SketchUp 2-Click Move Workflow Tests', () {
    testWidgets('Complete workflow: Select -> Translucent BBox -> M Key -> Click 1 -> Hover Move -> Arrow Axis Lock -> Snap -> Click 2 Commit', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      // Break weld bonds for rung_2 so it can move freely
      vm.breakAllBondsForPart('rung_2');
      final rung2 = vm.doc.parts.firstWhere((p) => p.id == 'rung_2');
      final initialPos = CadPoint3D(rung2.position.x, rung2.position.y, rung2.position.z);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 1000, height: 800, child: Assembly3DViewport(viewModel: vm)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Select entity by clicking on it
      vm.selectPart('rung_2');
      await tester.pumpAndSettle();

      expect(vm.selectedPart?.id, equals('rung_2'));

      // Verify that AssemblySelectedPartBoundingBoxPainter is present in the tree
      final bboxFinder = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is AssemblySelectedPartBoundingBoxPainter);
      expect(bboxFinder, findsOneWidget, reason: 'Translucent bounding box overlay must be painted around selected entity');

      // Verify 27 Snap Points generated for rung_2 (8 corners, 12 edge midpoints, 6 face centers, 1 centroid)
      final snapPoints = AssemblyDockingEngine.getAllSnapPointsForPart(rung2);
      final corners = snapPoints.where((p) => p.type == AssemblySnapPointType.boundingBoxCorner).toList();
      final edgeMidpoints = snapPoints.where((p) => p.type == AssemblySnapPointType.boundingBoxEdgeCenter).toList();
      final faceCenters = snapPoints.where((p) => p.type == AssemblySnapPointType.boundingBoxFaceCenter).toList();
      final centroids = snapPoints.where((p) => p.type == AssemblySnapPointType.boundingBoxCentroid).toList();

      expect(corners.length, equals(8), reason: 'Must have 8 bounding box corners');
      expect(edgeMidpoints.length, equals(12), reason: 'Must have 12 bounding box edge midpoints');
      expect(faceCenters.length, equals(6), reason: 'Must have 6 bounding box face centers');
      expect(centroids.length, equals(1), reason: 'Must have 1 centroid');

      // Step 2: Choose move tool / press M key
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();

      expect(vm.activeToolMode, equals(SketchUpToolMode.move), reason: 'Pressing M key must activate Move tool mode');

      // Screen location of rung_2
      const rungPosOnScreen = Offset(366.9, 287.5);

      // Step 3 & 4: Click 1 (Base Grab) & release mouse button
      final gesture = await tester.startGesture(rungPosOnScreen, buttons: kPrimaryMouseButton);
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.up(); // Releasing mouse button must NOT commit the move
      await tester.pumpAndSettle();

      // VCB should indicate active Move distance
      expect(vm.vcbLabel.startsWith('Distance'), isTrue, reason: 'Click 1 locks base anchor and enters hover move state');

      // Step 5: Hover move without holding down mouse button
      await gesture.moveTo(const Offset(450.0, 320.0));
      await tester.pump(const Duration(milliseconds: 30));

      expect(
        rung2.position.x != initialPos.x || rung2.position.y != initialPos.y || rung2.position.z != initialPos.z,
        isTrue,
        reason: 'Hover move must translate part smoothly without mouse button held down',
      );

      // Step 6: Arrow-Key Axis Locking
      // Press Right Arrow -> Lock X (Red Axis)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(vm.lockedAxis, equals(GizmoAxis.x), reason: 'Right arrow must lock Red X axis');

      // Press Left Arrow -> Lock Y (Green Axis)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(vm.lockedAxis, equals(GizmoAxis.y), reason: 'Left arrow must lock Green Y axis');

      // Press Up Arrow -> Lock Z (Blue Axis)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(vm.lockedAxis, equals(GizmoAxis.z), reason: 'Up arrow must lock Blue Z axis');

      // Press Down Arrow -> Unlock (Free Movement)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(vm.lockedAxis, equals(GizmoAxis.none), reason: 'Down arrow must unlock axis');

      // Step 7 & 8: Click 2 (Release / Placement)
      // Second click anywhere on canvas commits the placement
      final click2Gesture = await tester.startGesture(const Offset(480.0, 350.0), buttons: kPrimaryMouseButton);
      await tester.pump(const Duration(milliseconds: 30));
      await click2Gesture.up();
      await tester.pumpAndSettle();

      expect(vm.vcbValue, equals('Placed'), reason: '2nd click must release and commit entity move');
      expect(
        rung2.position.x != initialPos.x || rung2.position.y != initialPos.y || rung2.position.z != initialPos.z,
        isTrue,
        reason: 'Part must remain at new committed location after 2nd click',
      );
    });
  });
}
