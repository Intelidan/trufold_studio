// =============================================================================
// sheet_metal_studio_screen_test.dart
//
// Widget & Viewmodel tests for Dual-Viewport Sheet Metal Studio UI.
// Covers:
// 1. ViewModel state mutations
// 2. Dual viewports and controls rendering
// 3. Mouse wheel zoom in 2D & 3D
// 4. Click empty area to deselect objects
// 5. Immediate 3D punch hole rendering with face hole polygons
// 6. Undo and Redo operations
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/sheet_metal_studio_screen.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/viewport_3d/flutter_scene_viewport_widget.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/split_pane_divider.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/fold_progress_slider.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/obround_icon.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cnc_turret_engine.dart';

void main() {
  group('Sheet Metal Studio UI & Viewmodel Tests', () {
    test(
      '1. ViewModel state mutations (split ratio, orbit, fold progress)',
      () {
        final vm = SheetMetalStudioViewModel();

        // Initial state
        expect(vm.foldProgress, equals(1.0));
        expect(vm.splitRatio, equals(0.50));
        expect(vm.currentMesh.polygons.isNotEmpty, isTrue);

        // Mutate fold progress
        vm.setFoldProgress(0.45);
        expect(vm.foldProgress, closeTo(0.45, 1e-4));

        // Mutate split ratio
        vm.setSplitRatio(0.65);
        expect(vm.splitRatio, closeTo(0.65, 1e-4));

        // Camera orbit
        vm.orbit3D(15, -10);
        expect(vm.azimuthDeg, equals(60.0));
        expect(vm.elevationDeg, equals(20.0));

        // Preset view
        vm.setPresetView(azimuth: 0, elevation: 89);
        expect(vm.azimuthDeg, equals(0.0));
        expect(vm.elevationDeg, equals(89.0));
      },
    );

    test('2. Mouse wheel zoom in 2D and 3D viewports', () {
      final vm = SheetMetalStudioViewModel();

      // Initial zoom
      final init2D = vm.zoom2D;
      final init3D = vm.cameraZoom;

      // 2D Zoom in and out
      vm.zoom2DCanvas(1.2);
      expect(vm.zoom2D, closeTo(init2D * 1.2, 1e-4));
      vm.zoom2DCanvas(0.8);
      expect(vm.zoom2D, closeTo(init2D * 1.2 * 0.8, 1e-4));

      // 3D Zoom in and out
      vm.zoom3D(1.15);
      expect(vm.cameraZoom, closeTo(init3D * 1.15, 1e-4));
      vm.zoom3D(0.85);
      expect(vm.cameraZoom, closeTo(init3D * 1.15 * 0.85, 1e-4));
    });

    test('3. Clicking empty area deselects all objects', () {
      final vm = SheetMetalStudioViewModel();

      // Select a bend and punch
      vm.selectBend('B1');
      expect(vm.selectedBendId, equals('B1'));

      // Clear selection
      vm.clearSelection();
      expect(vm.selectedBendId, isNull);
      expect(vm.selectedPunchId, isNull);
      expect(vm.selectedFaceId, isNull);

      // Select punch and simulate canvas click on far empty space
      final p = CncPunchPrimitive(
        id: 'P_TEST',
        type: PunchType.roundHole,
        center: const CadPoint2D(50, 50),
        diameterMm: 10,
      );
      vm.addPunch(p);
      expect(vm.selectedPunchId, equals('P_TEST'));

      // Click on (9999, 9999) - empty space
      vm.setToolMode(StudioToolMode.select);
      vm.handleCanvasClick(const CadPoint2D(9999, 9999));
      expect(vm.selectedPunchId, isNull);
      expect(vm.selectedBendId, isNull);
    });

    test('4. Immediate 3D punch hole rendering with face hole polygons', () {
      final vm = SheetMetalStudioViewModel();

      // Check initial 3D mesh holes
      int totalHolesInitial = 0;
      for (final poly in vm.currentMesh.polygons) {
        totalHolesInitial += poly.holes.length;
      }

      // Add a round hole in the center of base face (at mm coords (50, 150))
      final p = CncPunchPrimitive(
        id: 'P_HOLE_3D',
        type: PunchType.roundHole,
        center: const CadPoint2D(50, 150),
        diameterMm: 12.0,
      );
      vm.addPunch(p);

      // Recomputed 3D mesh should immediately contain the hole loop!
      int totalHolesAfter = 0;
      for (final poly in vm.currentMesh.polygons) {
        totalHolesAfter += poly.holes.length;
      }

      expect(totalHolesAfter, greaterThan(totalHolesInitial));
    });

    test('5. Undo and Redo feature in ViewModel', () {
      final vm = SheetMetalStudioViewModel();

      expect(vm.canUndo, isFalse);
      expect(vm.canRedo, isFalse);
      final initialPunchCount = vm.document.punches.length;

      // 1. Add a punch
      final p1 = CncPunchPrimitive(
        id: 'P_UNDO_1',
        type: PunchType.roundHole,
        center: const CadPoint2D(60, 60),
        diameterMm: 8.0,
      );
      vm.addPunch(p1);

      expect(vm.document.punches.length, equals(initialPunchCount + 1));
      expect(vm.canUndo, isTrue);
      expect(vm.canRedo, isFalse);

      // 2. Undo
      vm.undo();
      expect(vm.document.punches.length, equals(initialPunchCount));
      expect(vm.canUndo, isFalse);
      expect(vm.canRedo, isTrue);

      // 3. Redo
      vm.redo();
      expect(vm.document.punches.length, equals(initialPunchCount + 1));
      expect(vm.canUndo, isTrue);
      expect(vm.canRedo, isFalse);
    });

    testWidgets(
      '6. SheetMetalStudioScreen renders dual viewports, toolbar and undo/redo',
      (tester) async {
        // Set test screen size
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(home: SheetMetalStudioScreen()),
        );
        await tester.pumpAndSettle();

        // Verify core widgets exist
        expect(find.byType(UnfoldedCanvasWidget), findsOneWidget);
        expect(find.byType(SplitPaneDivider), findsOneWidget);
        expect(find.byType(FlutterSceneViewportWidget), findsOneWidget);
        expect(find.byType(FoldProgressSlider), findsOneWidget);

        // Verify header texts and buttons
        expect(find.text('truFold Studio by Danish'), findsOneWidget);
        expect(find.byTooltip('Undo (Ctrl+Z)'), findsWidgets);
        expect(find.byTooltip('Redo (Ctrl+Y)'), findsWidgets);

        // Tap preset button in bottom slider
        await tester.tap(find.text('0% Flat'));
        await tester.pumpAndSettle();

        // Verify status changes to flat blank
        expect(find.text('FLAT BLANK (CNC Laser / Punching)'), findsOneWidget);

        // Tap 100% 3D
        await tester.tap(find.text('100% 3D'));
        await tester.pumpAndSettle();
        expect(
          find.text('3D FORMED PRODUCT (Press Brake Complete)'),
          findsOneWidget,
        );
      },
    );

    test('7. 3D Camera middle-mouse panning and reset', () {
      final vm = SheetMetalStudioViewModel();

      expect(vm.pan3D, equals(Offset.zero));

      // Pan by (25, -15)
      vm.pan3DCanvas(const Offset(25, -15));
      expect(vm.pan3D.dx, closeTo(25.0, 1e-4));
      expect(vm.pan3D.dy, closeTo(-15.0, 1e-4));

      // Reset camera clears pan
      vm.resetCamera();
      expect(vm.pan3D, equals(Offset.zero));
    });

    test('8. Single-step undo for continuous multi-frame object dragging', () {
      final vm = SheetMetalStudioViewModel();
      final p = CncPunchPrimitive(
        id: 'P_DRAG_TEST',
        type: PunchType.roundHole,
        center: const CadPoint2D(50, 50),
        diameterMm: 8.0,
      );
      vm.addPunch(p);
      expect(vm.selectedPunchId, equals('P_DRAG_TEST'));

      // Simulate multi-frame drag (e.g. 20 pointer moves)
      vm.beginObjectDrag();
      for (int i = 1; i <= 20; i++) {
        vm.moveSelectedPunch(CadPoint2D(50.0 + i, 50.0 + i));
      }
      vm.endObjectDrag();

      // Current position should be at (70, 70)
      final movedPunch = vm.document.punches.firstWhere(
        (item) => item.id == 'P_DRAG_TEST',
      );
      expect(movedPunch.center.x, closeTo(70.0, 1e-4));

      // A single undo should restore the position back to (50, 50) in 1 step!
      vm.undo();
      final restoredPunch = vm.document.punches.firstWhere(
        (item) => item.id == 'P_DRAG_TEST',
      );
      expect(restoredPunch.center.x, closeTo(50.0, 1e-4));
    });

    test('9. Bend line dragging and edge constraints', () {
      final vm = SheetMetalStudioViewModel();
      // Select existing bend line B1
      expect(vm.document.bends.isNotEmpty, isTrue);
      final firstBend = vm.document.bends.first;
      vm.selectBend(firstBend.id);

      // Inspect initial constraints
      final initialConstraints = vm.getSelectedBendConstraints();
      expect(initialConstraints, isNotNull);

      // Drag the bend line by +10mm in X
      final origP1X = firstBend.p1.x;
      vm.beginObjectDrag();
      vm.moveSelectedBend(const CadPoint2D(10.0, 0.0));
      vm.endObjectDrag();

      final draggedBend = vm.document.bends.firstWhere(
        (b) => b.id == firstBend.id,
      );
      expect(draggedBend.p1.x, closeTo(origP1X + 10.0, 1e-4));

      // Set exact constraint from Left edge to 75.0 mm
      vm.setBendConstraint(referenceEdge: 'Left', targetDistanceMm: 75.0);
      final constrainedBend = vm.document.bends.firstWhere(
        (b) => b.id == firstBend.id,
      );
      expect(constrainedBend.id, equals(firstBend.id));
      final updatedConstraints = vm.getSelectedBendConstraints();
      expect(updatedConstraints!.distFromLeftMm, closeTo(75.0, 1e-4));
    });

    test('10. Magnetic snapping toggle and continuous edge snapping', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.magneticSnapEnabled, isTrue);

      // Snap near corner (0, 0)
      vm.updateCursorMm(const CadPoint2D(2.0, 1.0));
      expect(vm.activeSnap, isNotNull);

      // Toggle snap off
      vm.toggleMagneticSnap();
      expect(vm.magneticSnapEnabled, isFalse);
      expect(vm.activeSnap, isNull);

      // When off, cursor updates do not snap
      vm.updateCursorMm(const CadPoint2D(0.5, 0.5));
      expect(vm.activeSnap, isNull);
    });

    test('11. Rubber-band 45° angle snapping and open bend detection', () {
      final vm = SheetMetalStudioViewModel();
      vm.setToolMode(StudioToolMode.addBend);

      // First click at (50, 500)
      vm.handleCanvasClick(const CadPoint2D(50.0, 500.0));
      expect(vm.pendingBendStart, equals(const CadPoint2D(50.0, 500.0)));

      // Simulate cursor at 44° angle (within 2.5° of 45° major axis)
      // 44° should automatically snap to 45°
      final snapped = vm.resolveEffectivePoint(
        CadPoint2D(50.0 + 100.0 * math.cos(44.0 * math.pi / 180.0), 500.0 + 100.0 * math.sin(44.0 * math.pi / 180.0)),
      );
      final dx = snapped.x - 50.0;
      final dy = snapped.y - 500.0;
      // Angle should be 45 degrees
      expect(dx, closeTo(dy, 1.0));

      // Click second point in the middle of sheet (incomplete bend)
      vm.handleCanvasClick(const CadPoint2D(100.0, 500.0));
      expect(vm.pendingBendStart, isNull);

      final openBend = vm.document.bends.last;
      expect(openBend.p1.x, equals(50.0));
      expect(openBend.p2.x, equals(100.0));

      // Check open/incomplete bend detection
      expect(vm.isBendIncomplete(openBend), isTrue);
    });

    test('12. Dragging bend line endpoints (P1 / P2) to snap onto edges', () {
      final vm = SheetMetalStudioViewModel();
      // Add an incomplete bend in the center
      vm.addBendLine(
        const CadPoint2D(50.0, 600.0),
        const CadPoint2D(150.0, 600.0),
      );
      final bend = vm.document.bends.last;
      expect(vm.isBendIncomplete(bend), isTrue);

      // Drag P1 endpoint to left edge at x = 0.0
      vm.updateBendEndpoint(
        bendId: bend.id,
        isP1: true,
        newPoint: const CadPoint2D(0.0, 600.0),
      );
      // Drag P2 endpoint to right edge at x = 230.0
      vm.updateBendEndpoint(
        bendId: bend.id,
        isP1: false,
        newPoint: const CadPoint2D(230.0, 600.0),
      );

      final updatedBend = vm.document.bends.firstWhere((b) => b.id == bend.id);
      expect(updatedBend.p1.x, equals(0.0));
      expect(updatedBend.p2.x, equals(230.0));

      // Since it now spans across the sheet from edge to edge, it successfully partitions faces!
      expect(vm.isBendIncomplete(updatedBend), isFalse);
    });

    test(
      '13. Laser Cut Line tool: creation, endpoint dragging, and undo/redo',
      () {
        final vm = SheetMetalStudioViewModel();
        final initialCutCount = vm.document.cutLines.length;

        // Disable magnetic snap for exact interior test coordinates
        vm.toggleMagneticSnap();

        vm.setToolMode(StudioToolMode.addCut);
        expect(vm.toolMode, equals(StudioToolMode.addCut));

        // Draw cut line from (30, 800) to (90, 800)
        vm.handleCanvasClick(const CadPoint2D(30.0, 800.0));
        expect(vm.pendingBendStart, isNotNull);

        vm.handleCanvasClick(const CadPoint2D(90.0, 800.0));
        expect(vm.pendingBendStart, isNull);
        expect(vm.document.cutLines.length, equals(initialCutCount + 1));

        final cut = vm.document.cutLines.last;
        expect(cut.p1.x, equals(30.0));
        expect(cut.p2.x, equals(90.0));
        expect(cut.layer, equals('CUT'));

        // Drag endpoint of cut line
        vm.updateCutEndpoint(
          cutId: cut.id,
          isP1: false,
          newPoint: const CadPoint2D(120.0, 800.0),
        );
        final updatedCut = vm.document.cutLines.firstWhere(
          (c) => c.id == cut.id,
        );
        expect(updatedCut.p2.x, equals(120.0));

        // Undo endpoint drag
        vm.undo();
        // Undo cut creation
        vm.undo();
        expect(vm.document.cutLines.any((c) => c.id == cut.id), isFalse);

        // Redo cut creation
        vm.redo();
        expect(vm.document.cutLines.any((c) => c.id == cut.id), isTrue);
      },
    );

    test('14. deselectAll() clears all selection state and pending rubber-band points', () {
      final vm = SheetMetalStudioViewModel();

      // Test bend selection cleared
      vm.selectBend('B1');
      expect(vm.selectedBendId, equals('B1'));
      vm.deselectAll();
      expect(vm.selectedBendId, isNull);

      // Test cut selection cleared
      vm.selectCut('CUT_1');
      expect(vm.selectedCutId, equals('CUT_1'));
      vm.deselectAll();
      expect(vm.selectedCutId, isNull);

      // Test punch selection cleared
      vm.selectPunch('P1');
      expect(vm.selectedPunchId, equals('P1'));
      vm.deselectAll();
      expect(vm.selectedPunchId, isNull);

      // Test pending rubber-band bend point cleared
      vm.setToolMode(StudioToolMode.addBend);
      vm.handleCanvasClick(const CadPoint2D(10.0, 10.0));
      expect(vm.pendingBendStart, isNotNull);
      vm.deselectAll();
      expect(vm.pendingBendStart, isNull);
      expect(vm.rubberBandEndpoint, isNull);

      // Space key switches tool mode to Select
      vm.setToolMode(StudioToolMode.addBend);
      expect(vm.toolMode, equals(StudioToolMode.addBend));
      vm.setToolMode(StudioToolMode.select);
      expect(vm.toolMode, equals(StudioToolMode.select));
    });

    test('15. Global sheet thickness setting updates material and recalculates 3D mesh', () {
      final vm = SheetMetalStudioViewModel();

      expect(vm.document.material.thicknessMm, equals(1.5));
      vm.setSheetThickness(2.5);

      expect(vm.document.material.thicknessMm, equals(2.5));
      expect(vm.currentMesh.polygons.isNotEmpty, isTrue);

      // Set preset thickness 3.0mm
      vm.setSheetThickness(3.0);
      expect(vm.document.material.thicknessMm, equals(3.0));
    });

    test(
      '16. Bend line radius setting and 3D cylindrical curved bend fillets',
      () {
        final vm = SheetMetalStudioViewModel();
        expect(vm.document.bends.isNotEmpty, isTrue);

        final firstBend = vm.document.bends.first;
        vm.setBendRadius(firstBend.id, 4.0);

        final updatedBend = vm.document.bends.firstWhere(
          (b) => b.id == firstBend.id,
        );
        expect(updatedBend.radiusMm, equals(4.0));

        // With foldProgress > 0, the mesh generates 3D curved bend arc fillet polygons
        vm.setFoldProgress(1.0);
        expect(
          vm.currentMesh.allPolygons.length,
          equals(
            vm.currentMesh.polygons.length +
                vm.currentMesh.filletPolygons.length +
                vm.currentMesh.thicknessPolygons.length,
          ),
        );
      },
    );

    testWidgets(
      '17. ObroundSlotIcon renders stadium pill geometry without error',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: ObroundSlotIcon(
                  width: 20,
                  height: 12,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(ObroundSlotIcon), findsOneWidget);
      },
    );

    test('18. 2D flat drawing remains unfolded while 3D mesh folds', () {
      final vm = SheetMetalStudioViewModel();

      // Flat 2D planar face coordinates
      final initialFaceVertices = vm.document.faces
          .map((f) => List.of(f.vertices))
          .toList();

      // Fold 3D model to 100%
      vm.setFoldProgress(1.0);

      // 3D mesh has folded non-planar geometry
      final hasFoldedZ = vm.currentMesh.polygons.any(
        (p) => p.vertices.any((v) => v.z.abs() > 1.0),
      );
      expect(hasFoldedZ, isTrue);

      // 2D document faces remain strictly planar and unfolded
      for (int i = 0; i < vm.document.faces.length; i++) {
        final face = vm.document.faces[i];
        final initVerts = initialFaceVertices[i];
        expect(face.vertices.length, equals(initVerts.length));
        for (int v = 0; v < face.vertices.length; v++) {
          expect(face.vertices[v].x, equals(initVerts[v].x));
          expect(face.vertices[v].y, equals(initVerts[v].y));
        }
      }
    });

    test(
      '19. Overlapping punch hole detection and merging into compound punch',
      () {
        final vm = SheetMetalStudioViewModel();

        final p1 = CncPunchPrimitive(
          id: 'PUNCH_A',
          type: PunchType.roundHole,
          center: const CadPoint2D(50.0, 50.0),
          diameterMm: 12.0,
        );
        final p2 = CncPunchPrimitive(
          id: 'PUNCH_B',
          type: PunchType.roundHole,
          center: const CadPoint2D(56.0, 50.0),
          diameterMm: 12.0,
        );

        vm.addPunch(p1);
        vm.addPunch(p2);

        final overlapping = vm.findOverlappingPunches('PUNCH_A');
        expect(overlapping.length, equals(1));
        expect(overlapping.first.id, equals('PUNCH_B'));

        vm.mergeOverlappingPunches('PUNCH_A');
        expect(vm.document.punches.any((p) => p.id == 'PUNCH_A'), isFalse);
        expect(vm.document.punches.any((p) => p.id == 'PUNCH_B'), isFalse);
        final compound = vm.document.punches.firstWhere(
          (p) => p.type == PunchType.compound,
        );
        expect(compound, isNotNull);
        expect(compound.customBoundary, isNotNull);
        expect(compound.customBoundary!.length, greaterThan(10));
      },
    );

    test('20. Edge hole notching associates punch overlapping outer boundary with adjacent face', () {
      final vm = SheetMetalStudioViewModel();

      final edgeHole = CncPunchPrimitive(
        id: 'EDGE_HOLE_1',
        type: PunchType.roundHole,
        center: const CadPoint2D(50.0, 0.0),
        diameterMm: 16.0,
      );
      vm.addPunch(edgeHole);

      final mesh = vm.currentMesh;
      final wallPoly = mesh.polygons.firstWhere(
        (p) => p.faceId == 'F_LEFT_WALL',
      );
      expect(wallPoly.holes.isNotEmpty, isTrue);
    });

    test('21. 3D fillet curvature and outward normal generation', () {
      final vm = SheetMetalStudioViewModel();
      final firstBend = vm.document.bends.first;
      vm.setBendRadius(firstBend.id, 5.0);
      vm.setFoldProgress(1.0);

      expect(vm.currentMesh.filletPolygons.isNotEmpty, isTrue);
      for (final poly in vm.currentMesh.filletPolygons) {
        expect(poly.vertices.length, equals(4));
        final norm = poly.normal;
        expect(norm.length, closeTo(1.0, 1e-2));
      }
    });

    test('22. Endpoint dragging 5° step anchoring with 45°/90°/180° priority and Alt bypass', () {
      const anchor = CadPoint2D(100.0, 100.0);

      // Vector at 24° from anchor with length 100
      final rad24 = 24.0 * math.pi / 180.0;
      final target24 = CadPoint2D(
        anchor.x + 100.0 * math.cos(rad24),
        anchor.y + 100.0 * math.sin(rad24),
      );
      final snapped25 = SheetMetalStudioViewModel.snapEndpointAngle(
        anchor: anchor,
        target: target24,
        isAlt: false,
      );
      final dx25 = snapped25.x - anchor.x;
      final dy25 = snapped25.y - anchor.y;
      final angle25 = math.atan2(dy25, dx25) * 180.0 / math.pi;
      expect(angle25, closeTo(25.0, 0.5), reason: '24° must snap to 25°');

      // Vector at 44° from anchor with length 100
      final target44 = CadPoint2D(
        anchor.x + 100.0 * 0.7193398,
        anchor.y + 100.0 * 0.694658,
      );
      final snapped45 = SheetMetalStudioViewModel.snapEndpointAngle(
        anchor: anchor,
        target: target44,
        isAlt: false,
      );
      expect(
        (snapped45.x - anchor.x).abs(),
        closeTo((snapped45.y - anchor.y).abs(), 1e-3),
        reason: '44° must anchor to 45° major axis (equal dx and dy)',
      );

      // Vector at 89° from anchor
      final target89 = CadPoint2D(
        anchor.x + 100.0 * 0.017452,
        anchor.y + 100.0 * 0.999847,
      );
      final snapped90 = SheetMetalStudioViewModel.snapEndpointAngle(
        anchor: anchor,
        target: target89,
        isAlt: false,
      );
      expect(
        snapped90.x,
        closeTo(anchor.x, 1e-3),
        reason: '89° must anchor to 90° major axis (vertical)',
      );

      // Free movement when Alt is held
      final freeTarget = SheetMetalStudioViewModel.snapEndpointAngle(
        anchor: anchor,
        target: target44,
        isAlt: true,
      );
      expect(freeTarget.x, closeTo(target44.x, 1e-6));
      expect(freeTarget.y, closeTo(target44.y, 1e-6));
    });

    test('23. Glass mode toggle and default state', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.isGlassMode, isFalse);

      vm.toggleGlassMode();
      expect(vm.isGlassMode, isTrue);

      vm.toggleGlassMode();
      expect(vm.isGlassMode, isFalse);
    });

    test(
      '24. setAllBendsRadius propagates radius across all bends with undo/redo',
      () {
        final vm = SheetMetalStudioViewModel();
        expect(vm.document.bends.length, greaterThan(1));

        // Initial radii
        final initialRadius = vm.document.bends.first.radiusMm;

        // Set all bends to 3.5mm
        vm.setAllBendsRadius(3.5);
        expect(vm.document.material.defaultBendRadius, equals(3.5));
        for (final bend in vm.document.bends) {
          expect(bend.radiusMm, equals(3.5));
        }

        // Test undo
        vm.undo();
        expect(vm.document.bends.first.radiusMm, equals(initialRadius));

        // Test redo
        vm.redo();
        for (final bend in vm.document.bends) {
          expect(bend.radiusMm, equals(3.5));
        }
      },
    );

    test(
      '25. 360° Free Roaming Orbit Viewport allows full spherical rotation',
      () {
        final vm = SheetMetalStudioViewModel();
        vm.resetCamera();
        expect(vm.elevationDeg, equals(30.0));

        // Orbit by large vertical delta -> should not clamp to 85° anymore
        vm.orbit3D(0.0, 300.0);
        expect(vm.elevationDeg, isNot(closeTo(85.0, 1.0)));

        // Orbit full 360°
        vm.resetCamera();
        vm.orbit3D(360.0, 0.0);
        expect(vm.azimuthDeg, closeTo(45.0, 1e-4));
      },
    );

    test(
      '26. Bidirectional Hover Highlighting for punches, bends and faces',
      () {
        final vm = SheetMetalStudioViewModel();
        expect(vm.hoveredPunchId, isNull);
        expect(vm.hoveredBendId, isNull);

        vm.setHoveredPunch('P1');
        expect(vm.hoveredPunchId, equals('P1'));

        vm.setHoveredBend('B1');
        expect(vm.hoveredBendId, equals('B1'));

        vm.setHoveredFace('F1');
        expect(vm.hoveredFaceId, equals('F1'));

        vm.setHoveredPunch(null);
        vm.setHoveredBend(null);
        vm.setHoveredFace(null);
        expect(vm.hoveredPunchId, isNull);
        expect(vm.hoveredBendId, isNull);
        expect(vm.hoveredFaceId, isNull);
      },
    );

    test('27. Double-Click Selection Cycling for Overlapping Parts', () {
      final vm = SheetMetalStudioViewModel();
      // Add two overlapping punches at center (100, 50)
      vm.addPunch(
        CncTurretEngine.createRoundHole(
          id: 'P_TEST_1',
          center: const CadPoint2D(100.0, 50.0),
          diameterMm: 10.0,
        ),
      );
      vm.addPunch(
        CncTurretEngine.createObroundSlot(
          id: 'P_TEST_2',
          center: const CadPoint2D(100.0, 50.0),
          widthMm: 7.0,
          lengthMm: 30.0,
        ),
      );

      expect(vm.document.punches.length, greaterThanOrEqualTo(2));

      // Cycle selection at (100, 50)
      vm.cycleSelectionAt(const CadPoint2D(100.0, 50.0));
      expect(vm.selectedPunchId, isNotNull);
      final firstSelected = vm.selectedPunchId;

      // Second cycle
      vm.cycleSelectionAt(const CadPoint2D(100.0, 50.0));
      expect(vm.selectedPunchId, isNotNull);
      expect(vm.selectedPunchId, isNot(equals(firstSelected)));
    });

    test('28. Cable Tray Staggered Perforation Pattern Generator', () {
      final vm = SheetMetalStudioViewModel();
      final initialCount = vm.document.punches.length;

      // Configure a 4x3 staggered perforation pattern
      vm.toolConfig.patternColsX = 4;
      vm.toolConfig.patternRowsY = 3;
      vm.toolConfig.patternPitchX = 25.0;
      vm.toolConfig.patternPitchY = 30.0;
      vm.toolConfig.patternStaggered = true;
      vm.toolConfig.patternSlotWidth = 30.0;
      vm.toolConfig.patternSlotHeight = 7.0;

      vm.applyPerforationPattern(
        center: const CadPoint2D(100.0, 50.0),
        countX: 4,
        countY: 3,
        pitchX: 25.0,
        pitchY: 30.0,
        slotWidth: 30.0,
        slotHeight: 7.0,
        staggered: true,
      );
      // Grouped perforation pattern remains unified (1 pattern entity, not 12 separate punches)
      expect(vm.document.perforationPatterns.length, equals(1));
      expect(vm.document.allPunches.length, equals(initialCount + 12));
      expect(vm.document.punches.length, equals(initialCount));

      // Test undoing the pattern
      vm.undo();
      expect(vm.document.perforationPatterns.length, equals(0));
      expect(vm.document.allPunches.length, equals(initialCount));
    });

    test(
      '29. Active Tool Dimension Stamping stamps with exact configured size',
      () {
        final vm = SheetMetalStudioViewModel();
        vm.setToolMode(StudioToolMode.addPunchRound);
        vm.toolConfig.roundHoleDiameter = 14.5;

        // Canvas click stamps configured diameter
        vm.handleCanvasClick(const CadPoint2D(120.0, 80.0));
        final stamped = vm.document.punches.last;
        expect(stamped.type, equals(PunchType.roundHole));
        expect(stamped.diameterMm, equals(14.5));
      },
    );

    test('30. 2D Zoom with focal-point precisely anchors canvas under cursor', () {
      final vm = SheetMetalStudioViewModel();
      const viewportSize = Size(800, 600);
      const mousePos = Offset(300, 200);

      // Compute drawing coordinate under mousePos before zoom:
      // screen = center + pan + cad * zoom * yFlip
      // cad.x = (mouse.dx - center.dx - pan.dx) / zoom
      // cad.y = (center.dy + pan.dy - mouse.dy) / zoom
      final center = viewportSize.center(Offset.zero);
      final cadXBefore = (mousePos.dx - center.dx - vm.pan2D.dx) / vm.zoom2D;
      final cadYBefore = (center.dy + vm.pan2D.dy - mousePos.dy) / vm.zoom2D;

      // Zoom in by factor 1.5 anchored at mousePos
      vm.zoom2DCanvas(1.5, focalPoint: mousePos, viewportSize: viewportSize);

      final cadXAfter = (mousePos.dx - center.dx - vm.pan2D.dx) / vm.zoom2D;
      final cadYAfter = (center.dy + vm.pan2D.dy - mousePos.dy) / vm.zoom2D;

      expect(cadXAfter, closeTo(cadXBefore, 1e-4), reason: 'CAD X under mouse cursor must remain stationary');
      expect(cadYAfter, closeTo(cadYBefore, 1e-4), reason: 'CAD Y under mouse cursor must remain stationary');

      // Zoom out by factor 0.75 anchored at mousePos
      vm.zoom2DCanvas(0.75, focalPoint: mousePos, viewportSize: viewportSize);

      final cadXAfterOut = (mousePos.dx - center.dx - vm.pan2D.dx) / vm.zoom2D;
      final cadYAfterOut = (center.dy + vm.pan2D.dy - mousePos.dy) / vm.zoom2D;

      expect(cadXAfterOut, closeTo(cadXBefore, 1e-4), reason: 'CAD X under mouse cursor must remain stationary on zoom-out');
      expect(cadYAfterOut, closeTo(cadYBefore, 1e-4), reason: 'CAD Y under mouse cursor must remain stationary on zoom-out');
    });

    test('31. Arc entity selection, updateArc with undo/redo, and deletion', () {
      final vm = SheetMetalStudioViewModel();

      // Add a test arc to document
      final arc = CadArc2D(
        id: 'ARC_TEST_1',
        center: const CadPoint2D(100, 100),
        radius: 25.0,
        startAngleDeg: 0,
        endAngleDeg: 90,
        isClockwise: false,
        layer: 'OUTLINE',
      );
      vm.setDocument(vm.document.copyWith(arcs: [...vm.document.arcs, arc]));

      // Select the arc
      vm.selectArc('ARC_TEST_1');
      expect(vm.selectedArcId, equals('ARC_TEST_1'));
      expect(vm.selectedArc, isNotNull);
      expect(vm.selectedArc!.radius, equals(25.0));

      // Modify arc properties
      final updatedArc = vm.selectedArc!.copyWith(radius: 35.0, endAngleDeg: 180.0);
      vm.updateArc(updatedArc);
      expect(vm.selectedArc!.radius, equals(35.0));
      expect(vm.selectedArc!.endAngleDeg, equals(180.0));

      // Undo arc update (undo clears selection)
      vm.undo();
      final arcAfterUndo = vm.document.arcs.firstWhere((a) => a.id == 'ARC_TEST_1');
      expect(arcAfterUndo.radius, equals(25.0));
      expect(arcAfterUndo.endAngleDeg, equals(90.0));

      // Redo arc update
      vm.redo();
      final arcAfterRedo = vm.document.arcs.firstWhere((a) => a.id == 'ARC_TEST_1');
      expect(arcAfterRedo.radius, equals(35.0));
      expect(arcAfterRedo.endAngleDeg, equals(180.0));

      // Delete arc
      vm.deleteArc('ARC_TEST_1');
      expect(vm.selectedArcId, isNull);
      expect(vm.document.arcs.any((a) => a.id == 'ARC_TEST_1'), isFalse);

      // Undo deletion
      vm.undo();
      expect(vm.document.arcs.any((a) => a.id == 'ARC_TEST_1'), isTrue);
    });

    test('32. Global Curve Resolution setting configuration and updates', () {
      final vm = SheetMetalStudioViewModel();

      // Default resolution is 64
      expect(vm.curveResolution, equals(64));

      // Set to standard 32
      vm.setCurveResolution(32);
      expect(vm.curveResolution, equals(32));

      // Set to ultra 128
      vm.setCurveResolution(128);
      expect(vm.curveResolution, equals(128));

      // Invalid values clamped to minimum 12
      vm.setCurveResolution(4);
      expect(vm.curveResolution, equals(12));
    });
  });
}
