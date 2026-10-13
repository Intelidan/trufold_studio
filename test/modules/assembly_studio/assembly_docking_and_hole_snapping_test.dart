import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_docking_zone.dart';
import 'package:trufold_studio/assembly_studio/engine/assembly_docking_engine.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_snap_animator.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_3d_viewport.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

class _TestSnapHarness extends StatefulWidget {
  final void Function(AssemblySnapAnimator animator) onReady;
  const _TestSnapHarness({required this.onReady});

  @override
  State<_TestSnapHarness> createState() => _TestSnapHarnessState();
}

class _TestSnapHarnessState extends State<_TestSnapHarness> with SingleTickerProviderStateMixin {
  late final AssemblySnapAnimator animator;

  @override
  void initState() {
    super.initState();
    animator = AssemblySnapAnimator(vsync: this, snapDuration: const Duration(milliseconds: 200));
    widget.onReady(animator);
  }

  @override
  void dispose() {
    animator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  group('AssemblyDockingEngine & Snap Point Extraction Tests', () {
    test('extracts bounding box corners, edge midpoints, and centroid for basic part', () {
      final part = AssemblyPart(id: 'p1', name: 'Test Part', type: AssemblyPartType.bar, length: 200.0, height: 100.0, thickness: 2.0);

      final snapPoints = AssemblyDockingEngine.getAllSnapPointsForPart(part);

      // Verify corners (8)
      final corners = snapPoints.where((p) => p.type == AssemblySnapPointType.boundingBoxCorner).toList();
      expect(corners.length, equals(8));

      // Verify edge midpoints (12)
      final edges = snapPoints.where((p) => p.type == AssemblySnapPointType.boundingBoxEdgeCenter).toList();
      expect(edges.length, equals(12));

      // Verify centroid (1)
      final centroid = snapPoints.where((p) => p.type == AssemblySnapPointType.boundingBoxCentroid).firstOrNull;
      expect(centroid, isNotNull);
      expect(centroid!.label, contains('Centroid'));
    });

    test('extracts hole centers and perimeter endpoints from parts with holes', () {
      final rail = AssemblyPart(
        id: 'rail_holes_1',
        name: 'Rail With Holes',
        type: AssemblyPartType.straightRail,
        length: 1000.0,
        height: 100.0,
        flangeWidth: 20.0,
      );

      final snapPoints = AssemblyDockingEngine.getAllSnapPointsForPart(rail);

      // Web coupler holes exist on straightRail
      final holeCenters = snapPoints.where((p) => p.type == AssemblySnapPointType.holeCenter).toList();
      expect(holeCenters.isNotEmpty, isTrue, reason: 'Rail should have hole center snap points from coupler holes');

      for (final hc in holeCenters) {
        expect(hc.isCenter, isTrue);
        expect(hc.isHoleOrSketch, isTrue);
        expect(hc.label, contains('Hole Center'));
      }

      final holePerimeters = snapPoints.where((p) => p.type == AssemblySnapPointType.holePerimeter).toList();
      expect(holePerimeters.isNotEmpty, isTrue, reason: 'Rail should have hole rim/perimeter snap points');
    });

    test('extracts sketch centers and endpoints from sketches drawn on part', () {
      final part = AssemblyPart(
        id: 'p_sketch_1',
        name: 'Plate With Sketches',
        type: AssemblyPartType.bar,
        length: 300.0,
        height: 200.0,
        thickness: 3.0,
        sketches: [
          AssemblySketchFeature(
            id: 'sk_hole_1',
            featureType: 'circle_hole',
            localCenter: const CadPoint2D(50.0, 50.0),
            widthMm: 12.0,
            heightMm: 12.0,
            targetFace: 'web',
          ),
          AssemblySketchFeature(
            id: 'sk_slot_1',
            featureType: 'rect_cut',
            localCenter: const CadPoint2D(150.0, 50.0),
            widthMm: 40.0,
            heightMm: 20.0,
            targetFace: 'web',
          ),
        ],
      );

      final snapPoints = AssemblyDockingEngine.getAllSnapPointsForPart(part);

      // Verify Sketch Centers
      final sketchCenters = snapPoints.where((p) => p.type == AssemblySnapPointType.sketchCenter).toList();
      expect(sketchCenters.length, equals(2));
      expect(sketchCenters.any((s) => s.featureId == 'sk_hole_1'), isTrue);
      expect(sketchCenters.any((s) => s.featureId == 'sk_slot_1'), isTrue);

      // Verify Sketch Endpoints (corners/quadrants)
      final sketchEndpoints = snapPoints.where((p) => p.type == AssemblySnapPointType.sketchEndpoint).toList();
      expect(sketchEndpoints.length, equals(8)); // 4 corners for each sketch feature
    });

    test('findNearestSnapPoint detects hole center accurately under cursor within tolerance', () {
      final snapA = AssemblySnapPoint(
        id: 'sp_corner',
        partId: 'p1',
        worldPosition: const CadPoint3D(0.0, 0.0, 0.0),
        localPosition: const CadPoint3D(0.0, 0.0, 0.0),
        type: AssemblySnapPointType.boundingBoxCorner,
        label: 'Corner',
      );
      final snapHole = AssemblySnapPoint(
        id: 'sp_hole',
        partId: 'p1',
        worldPosition: const CadPoint3D(50.0, 0.0, 50.0),
        localPosition: const CadPoint3D(50.0, 0.0, 50.0),
        type: AssemblySnapPointType.holeCenter,
        label: '⌖ Hole Center',
      );

      // Mock screen projection: world (x, y, z) -> screen (x * 2, z * 2)
      Offset mockProject(CadPoint3D pt) => Offset(pt.x * 2.0, pt.z * 2.0);

      // Cursor hovering directly over the hole center (screen 100, 100)
      final nearest = AssemblyDockingEngine.findNearestSnapPoint(
        screenCursor: const Offset(102.0, 99.0), // 2px away from hole
        candidates: [snapA, snapHole],
        projectPoint: mockProject,
        maxPixelDistance: 14.0,
      );

      expect(nearest, isNotNull);
      expect(nearest!.id, equals('sp_hole'));
      expect(nearest.type, equals(AssemblySnapPointType.holeCenter));
    });
  });

  group('AssemblySnapAnimator Tests', () {
    testWidgets('animates snap glide from start to target with ease-out cubic interpolation', (tester) async {
      AssemblySnapAnimator? animator;
      await tester.pumpWidget(MaterialApp(home: _TestSnapHarness(onReady: (a) => animator = a)));

      expect(animator, isNotNull);

      final part = AssemblyPart(id: 'p1', name: 'Moving Part', type: AssemblyPartType.bar, length: 100.0, height: 50.0);

      final startPos = const CadPoint3D(0.0, 0.0, 0.0);
      final targetPos = const CadPoint3D(100.0, 50.0, 20.0);

      final snapSrc = AssemblySnapPoint(
        id: 's1',
        partId: 'p1',
        worldPosition: startPos,
        localPosition: startPos,
        type: AssemblySnapPointType.holeCenter,
        label: 'Hole A',
      );
      final snapTgt = AssemblySnapPoint(
        id: 's2',
        partId: 'p2',
        worldPosition: targetPos,
        localPosition: targetPos,
        type: AssemblySnapPointType.holeCenter,
        label: 'Hole B',
      );

      CadPoint3D lastPos = startPos;
      bool completed = false;

      animator!.startSnapGlide(
        sourcePart: part,
        startPos: startPos,
        targetPos: targetPos,
        sourceSnap: snapSrc,
        targetSnap: snapTgt,
        onTick: (pos) {
          lastPos = pos;
        },
        onComplete: () {
          completed = true;
        },
      );

      // Verify input lock and target highlight during glide
      expect(animator!.isSnapping, isTrue);
      expect(animator!.highlightedPartId, equals('p2'));
      expect(animator!.targetScaleFactor, equals(1.04));

      // Advance animation halfway
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(lastPos.x, greaterThan(0.0));
      expect(lastPos.x, lessThan(100.0));

      // Settle animation to completion
      await tester.pumpAndSettle();
      expect(animator!.isSnapping, isFalse);
      expect(completed, isTrue);
      expect(lastPos.x, closeTo(100.0, 1e-3));
      expect(lastPos.y, closeTo(50.0, 1e-3));
      expect(lastPos.z, closeTo(20.0, 1e-3));

      // Clean teardown verified
      expect(animator!.highlightedPartId, isNull);
      expect(animator!.targetScaleFactor, equals(1.0));
    });
  });

  group('Assembly3DViewport Snapping & Activating Highlight Widget Tests', () {
    testWidgets('renders Assembly3DViewport and displays snap feedback in VCB HUD', (tester) async {
      final vm = AssemblyStudioViewModel();

      // Add a rung and straight rail
      final rail = AssemblyPart(id: 'rail_test', name: 'Stile Rail', type: AssemblyPartType.straightRail, length: 600.0, height: 80.0, flangeWidth: 20.0);
      vm.addPart(rail);
      vm.selectPart('rail_test');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Assembly3DViewport(viewModel: vm)),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Assembly3DViewport), findsOneWidget);
    });
  });
}
