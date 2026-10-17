import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_timeline_item.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_browser_tree.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/overlays.dart';

void main() {
  group('3D Surface Sketching Engine & Math Subroutines', () {
    test('createDatumPlane generates valid XY, XZ, YZ planes with orthogonal coordinate frames', () {
      final xyPlane = AssemblySurfaceSketchEngine.createDatumPlane('XY');
      expect(xyPlane.id, 'datum_XY');
      expect(xyPlane.normal.z, closeTo(1.0, 1e-4));
      expect(xyPlane.xAxis.dot(xyPlane.yAxis), closeTo(0.0, 1e-4));
      expect(xyPlane.xAxis.dot(xyPlane.zAxis), closeTo(0.0, 1e-4));

      final xzPlane = AssemblySurfaceSketchEngine.createDatumPlane('XZ');
      expect(xzPlane.id, 'datum_XZ');
      expect(xzPlane.normal.y.abs(), closeTo(1.0, 1e-4));

      final yzPlane = AssemblySurfaceSketchEngine.createDatumPlane('YZ');
      expect(yzPlane.id, 'datum_YZ');
      expect(yzPlane.normal.x, closeTo(1.0, 1e-4));
    });

    test('createPlaneFromFacePolygon extracts origin, normal, and local projection frame', () {
      final poly = CadFoldedPolygon3D(
        faceId: 'test_face_top',
        vertices: [CadPoint3D(0, 50, 0), CadPoint3D(100, 50, 0), CadPoint3D(100, 50, 50), CadPoint3D(0, 50, 50)],
        normal: CadPoint3D(0, 1, 0),
      );

      final plane = AssemblySurfaceSketchEngine.createPlaneFromFacePolygon(polygon: poly, partId: 'part_1');
      expect(plane.targetFaceId, 'test_face_top');
      expect(plane.targetPartId, 'part_1');
      expect(plane.normal.y, closeTo(1.0, 1e-4));

      // Test local <-> world coordinate roundtrip
      final localPt = const Offset(25.0, 15.0);
      final worldPt = plane.toWorld(localPt);
      final backLocal = plane.toLocal(worldPt);
      expect(backLocal.dx, closeTo(localPt.dx, 1e-3));
      expect(backLocal.dy, closeTo(localPt.dy, 1e-3));
    });

    test('computeNormalViewCameraAngles computes perpendicular azimuth and elevation angles', () {
      // Top face facing +Z
      final topAngles = AssemblySurfaceSketchEngine.computeNormalViewCameraAngles(vm_math.Vector3(0, 0, 1));
      expect(topAngles.elevationDeg, closeTo(90.0, 1e-2));

      // Side face facing +X
      final rightAngles = AssemblySurfaceSketchEngine.computeNormalViewCameraAngles(vm_math.Vector3(1, 0, 0));
      expect(rightAngles.elevationDeg, closeTo(0.0, 1e-2));
      expect(rightAngles.azimuthDeg, closeTo(90.0, 1e-2));

      // Front face facing -Y
      final frontAngles = AssemblySurfaceSketchEngine.computeNormalViewCameraAngles(vm_math.Vector3(0, -1, 0));
      expect(frontAngles.elevationDeg, closeTo(0.0, 1e-2));
      expect(frontAngles.azimuthDeg, closeTo(0.0, 1e-2));
    });

    test('CADProfileValidator and CADTessellator evaluate closed loops and generate ear-clipped triangles', () {
      final rect = CADRectangleEntity(id: 'rect_test', startPoint: const Offset(10, 10), width: 40, height: 30);
      final segs = rect.toLineSegments();
      expect(segs.length, 4);

      final validation = CADProfileValidator.validateProfile(segs);
      expect(validation.isValidClosedLoop, isTrue);
      expect(validation.orderedPathVertices.length, 5); // 4 vertices closed with first point

      final indices = CADTessellator.tessellatePolygon(validation.orderedPathVertices);
      expect(indices.length, 6); // A quad decomposes into 2 triangles = 6 indices
    });
  });

  group('AssemblyStudioViewModel Parametric Surface Sketching Operations', () {
    late AssemblyStudioViewModel vm;

    setUp(() {
      vm = AssemblyStudioViewModel();
    });

    test('activateSketchOnDatum enters sketch mode, locks 3D movement and aligns camera', () {
      vm.activateSketchOnDatum('XY');
      expect(vm.isSketchMode, isTrue);
      expect(vm.is3DMovementLocked, isTrue);
      expect(vm.activeSketchPlane, isNotNull);
      expect(vm.isOrthoProjection, isTrue);
    });

    test('focusPartAndEnterSketch with shortcut "S" activates sketch on selected face', () {
      expect(vm.doc.parts, isNotEmpty);
      final part = vm.doc.parts.first;
      vm.focusPartAndEnterSketch(part.id);

      expect(vm.isSketchMode, isTrue);
      expect(vm.is3DMovementLocked, isTrue);
      expect(vm.sketchPartId, part.id);
      expect(vm.activeSketchPlane, isNotNull);
    });

    test('addPrimitiveEntityToActivePlane and updateSelectedPrimitiveDimensions', () {
      vm.activateSketchOnDatum('XY');

      final rect = CADRectangleEntity(id: 'rect_1', startPoint: const Offset(20, 20), width: 50, height: 30, isPassThrough: true);
      vm.addPrimitiveEntityToActivePlane(rect);

      expect(vm.activeSketchPlane!.primitives.length, 1);
      expect(vm.selectedSketchEntity, rect);
      expect(vm.selectedSketchFeatureId, 'rect_1');

      // Update dimensions parametrically
      vm.updateSelectedPrimitiveDimensions(width: 80.0, height: 45.0, depthMm: 8.0);

      final updated = vm.selectedSketchEntity as CADRectangleEntity;
      expect(updated.width, 80.0);
      expect(updated.height, 45.0);
      expect(updated.depthMm, 8.0);
    });

    test('executeFeatureCutOnActiveSurface punches 3D pass-through void and updates history', () {
      expect(vm.doc.parts, isNotEmpty);
      final part = vm.doc.parts.first;
      vm.focusPartAndEnterSketch(part.id);

      final rect = CADRectangleEntity(id: 'cut_square', startPoint: const Offset(10, 10), width: 25, height: 25, isPassThrough: true);
      vm.addPrimitiveEntityToActivePlane(rect);
      vm.executeFeatureCutOnActiveSurface(isPassThrough: true);

      // Verify feature registered on part
      expect(part.sketches.any((s) => s.featureType == 'custom_cut' && s.isPassThrough), isTrue);
      // Verify feature registered in history
      expect(vm.sketchFeatureHistory.any((h) => h.name.contains('Pass-Through')), isTrue);

      // Test JSON history serialization and restoration
      final jsonStr = vm.serializeSketchHistory();
      expect(jsonStr, isNotEmpty);
      expect(jsonStr.contains('Pass-Through'), isTrue);

      vm.loadSketchHistory(jsonStr);
      expect(vm.sketchFeatureHistory, isNotEmpty);
    });

    test('generateIndustrialSTLFilePayload generates standardized ASCII STL text', () async {
      final stl = await vm.generateIndustrialSTLFilePayload();
      expect(stl, isNotNull);
      expect(stl!.startsWith('solid'), isTrue);
      expect(stl.contains('facet normal'), isTrue);
      expect(stl.contains('outer loop'), isTrue);
      expect(stl.contains('endfacet'), isTrue);
      expect(stl.contains('endsolid'), isTrue);
    });
  });

  group('Interactive UI Widgets (HUD and Parameter Panel)', () {
    testWidgets('AssemblySketchHud displays tool chips, Normal View (S) and Export STL buttons', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AssemblySketchHud(viewModel: vm)),
        ),
      );

      expect(find.textContaining('Direct Sketch'), findsOneWidget);
      expect(find.text('2-Pt Rect (R)'), findsOneWidget);
      expect(find.text('Circle (C)'), findsOneWidget);
      expect(find.text('Line (L)'), findsOneWidget);
      expect(find.text('Polyline'), findsOneWidget);
      expect(find.text('Normal View (S)'), findsOneWidget);
      expect(find.text('Export STL'), findsOneWidget);
    });

    testWidgets('AssemblySketchParameterPanel displays parametric dimension fields and triggers cut', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final rect = CADRectangleEntity(id: 'rect_ui_test', startPoint: const Offset(15, 25), width: 60, height: 40, isPassThrough: true);
      vm.addPrimitiveEntityToActivePlane(rect);

      bool rebuildCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssemblySketchParameterPanel(
              viewModel: vm,
              onRebuildModel: () {
                rebuildCalled = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Construction (Q)'), findsOneWidget);
      expect(find.text('Dimension (D)'), findsOneWidget);
      expect(find.text('Extrude (E)'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      // Tap Delete Sketch Entity
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(rebuildCalled, isTrue);
    });
  });

  group('Phase 1: 3D Planes & Construction Geometry Subroutines', () {
    test('CADSketchPlane quad corners and ray intersection', () {
      final plane = AssemblySurfaceSketchEngine.createDatumPlane('XY', size: 100.0);
      final corners = plane.getQuadCorners();
      expect(corners.length, 4);

      // Ray hitting center of plane from +Z
      final hitRay = plane.intersectRay(vm_math.Vector3(0.0, 0.0, 50.0), vm_math.Vector3(0.0, 0.0, -1.0));
      expect(hitRay.hit, isTrue);
      expect(hitRay.t, closeTo(50.0, 1e-4));
      expect(hitRay.hitWorld!.z, closeTo(0.0, 1e-4));
      expect(hitRay.hitLocal!.dx, closeTo(0.0, 1e-4));
      expect(hitRay.hitLocal!.dy, closeTo(0.0, 1e-4));

      // Ray missing the 100x100 plane bounds (x=80)
      final missRay = plane.intersectRay(vm_math.Vector3(80.0, 0.0, 50.0), vm_math.Vector3(0.0, 0.0, -1.0));
      expect(missRay.hit, isFalse);

      // Ray pointing away from the plane
      final awayRay = plane.intersectRay(vm_math.Vector3(0.0, 0.0, 50.0), vm_math.Vector3(0.0, 0.0, 1.0));
      expect(awayRay.hit, isFalse);
    });

    test('AssemblySurfaceSketchEngine creates valid Offset, Angle, Midplane, and 3-Point planes', () {
      final basePlane = AssemblySurfaceSketchEngine.createDatumPlane('XY');

      // Offset Plane +50mm
      final offsetPlane = AssemblySurfaceSketchEngine.createOffsetPlane(parentPlane: basePlane, offsetMm: 50.0);
      expect(offsetPlane.planeType, CADPlaneType.offsetPlane);
      expect(offsetPlane.origin.z, closeTo(50.0, 1e-4));
      expect(offsetPlane.normal.z, closeTo(1.0, 1e-4));
      expect(offsetPlane.offsetDistance, 50.0);

      // Angle Plane rotated 90 deg around X-axis
      final anglePlane = AssemblySurfaceSketchEngine.createAnglePlane(
        referencePlane: basePlane,
        axisOrigin: vm_math.Vector3(0, 0, 0),
        axisDir: vm_math.Vector3(1, 0, 0),
        angleDeg: 90.0,
      );
      expect(anglePlane.planeType, CADPlaneType.anglePlane);
      expect(anglePlane.normal.y.abs(), closeTo(1.0, 1e-3));

      // Midplane between Z=0 and Z=100
      final planeA = AssemblySurfaceSketchEngine.createDatumPlane('XY');
      final planeB = AssemblySurfaceSketchEngine.createOffsetPlane(parentPlane: planeA, offsetMm: 100.0);
      final mid = AssemblySurfaceSketchEngine.createMidplane(plane1: planeA, plane2: planeB);
      expect(mid.planeType, CADPlaneType.midplane);
      expect(mid.origin.z, closeTo(50.0, 1e-4));

      // 3-Point Plane
      final p3 = AssemblySurfaceSketchEngine.createPlaneFrom3Points(p1: vm_math.Vector3(0, 0, 0), p2: vm_math.Vector3(10, 0, 0), p3: vm_math.Vector3(0, 10, 0));
      expect(p3.planeType, CADPlaneType.threePointPlane);
      expect(p3.normal.z, closeTo(1.0, 1e-4));
    });

    test('AssemblyStudioViewModel plane selection workflow and construction plane management', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.isPlaneSelectionMode, isFalse);

      // Enter plane selection mode
      vm.enterPlaneSelectionMode();
      expect(vm.isPlaneSelectionMode, isTrue);

      // Hover plane
      vm.setHoveredPlane('datum_XZ');
      expect(vm.hoveredPlaneId, 'datum_XZ');

      // Select plane for sketch
      vm.selectPlaneForSketch(vm.datumPlaneXZ);
      expect(vm.isPlaneSelectionMode, isFalse);
      expect(vm.isSketchMode, isTrue);
      expect(vm.activeSketchPlane?.id, 'datum_XZ');

      // Add Offset Construction Plane
      final offPlane = vm.addOffsetConstructionPlane(parentPlaneId: 'datum_XY', offsetMm: 75.0);
      expect(vm.constructionPlanes.contains(offPlane), isTrue);
      expect(vm.allAvailablePlanes.contains(offPlane), isTrue);

      // Remove Construction Plane
      vm.removeConstructionPlane(offPlane.id);
      expect(vm.constructionPlanes.contains(offPlane), isFalse);
    });

    testWidgets('AssemblyPlaneSelectionBanner displays title and quick-select datum buttons', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.enterPlaneSelectionMode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblyPlaneSelectionBanner(viewModel: vm)]),
          ),
        ),
      );

      expect(find.text('CREATE SKETCH'), findsOneWidget);
      expect(find.text('XY Top'), findsOneWidget);
      expect(find.text('XZ Front'), findsOneWidget);
      expect(find.text('YZ Right'), findsOneWidget);
      expect(find.text('+ Construction Plane'), findsOneWidget);

      // Click XY Top quick select button
      await tester.tap(find.text('XY Top'));
      await tester.pumpAndSettle();

      expect(vm.isSketchMode, isTrue);
      expect(vm.activeSketchPlane?.id, 'datum_XY');
      expect(vm.isPlaneSelectionMode, isFalse);
    });
  });

  group('Phase 2: Fusion 360 Sketch Palette & 3D-to-2D Geometry Projection Subroutines', () {
    test('Sketch Palette toggles update state and notify listeners', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.showSketchGrid, isTrue);
      expect(vm.showSketchSnap, isTrue);
      expect(vm.showSketchConstraints, isTrue);
      expect(vm.showSketchDimensions, isTrue);
      expect(vm.showSketchProfileShading, isTrue);
      expect(vm.isSketchSliceBody, isFalse);
      expect(vm.isSketchConstructionMode, isFalse);

      vm.toggleSketchGrid();
      expect(vm.showSketchGrid, isFalse);

      vm.toggleSketchSnap();
      expect(vm.showSketchSnap, isFalse);

      vm.toggleSketchConstraints();
      expect(vm.showSketchConstraints, isFalse);

      vm.toggleSketchDimensions();
      expect(vm.showSketchDimensions, isFalse);

      vm.toggleSketchProfileShading();
      expect(vm.showSketchProfileShading, isFalse);

      vm.toggleSketchSliceBody();
      expect(vm.isSketchSliceBody, isTrue);

      vm.toggleSketchConstructionMode();
      expect(vm.isSketchConstructionMode, isTrue);
    });

    test('toggleSketchConstructionMode toggles selected entity construction attribute', () {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final line = CADLineEntity(id: 'line_test', start: const Offset(0, 0), end: const Offset(50, 0), isConstruction: false);
      vm.addPrimitiveEntityToActivePlane(line);
      vm.selectSketchPrimitive(line);
      expect(vm.selectedSketchEntity?.isConstruction, isFalse);

      // Press 'X' / toggle
      vm.toggleSketchConstructionMode();
      expect(line.isConstruction, isTrue);
      expect(vm.isSketchConstructionMode, isTrue);

      // Toggle again
      vm.toggleSketchConstructionMode();
      expect(line.isConstruction, isFalse);
      expect(vm.isSketchConstructionMode, isFalse);
    });

    test('3D-to-2D Geometry Projection creates projected magenta entities with source traceability', () {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY'); // Plane at Z=0, normal +Z

      expect(vm.isProjectGeometryMode, isFalse);
      vm.enterProjectGeometryMode();
      expect(vm.isProjectGeometryMode, isTrue);

      // Project a 3D edge
      final p1 = CadPoint3D(10.0, 20.0, 0.0);
      final p2 = CadPoint3D(50.0, 20.0, 0.0);
      final projLine = vm.project3DEdgeToActivePlane(p1, p2, sourceId: 'edge_ref_1');

      expect(projLine, isNotNull);
      expect(projLine!.isProjected, isTrue);
      expect(projLine.sourceEntityId, 'edge_ref_1');
      expect(projLine.start.dx, closeTo(10.0, 1e-3));
      expect(projLine.start.dy, closeTo(20.0, 1e-3));
      expect(projLine.end.dx, closeTo(50.0, 1e-3));
      expect(projLine.end.dy, closeTo(20.0, 1e-3));
      expect(vm.activeSketchPlane!.primitives.contains(projLine), isTrue);

      // Project a 3D vertex
      final v1 = CadPoint3D(35.0, 40.0, 0.0);
      final projVertex = vm.project3DVertexToActivePlane(v1, sourceId: 'vert_ref_1');
      expect(projVertex, isNotNull);
      expect(projVertex!.isProjected, isTrue);
      expect(projVertex.isConstruction, isTrue);
      expect(projVertex.center.dx, closeTo(35.0, 1e-3));
      expect(projVertex.center.dy, closeTo(40.0, 1e-3));

      // Project a 3D face boundary polygon
      final poly = CadFoldedPolygon3D(
        faceId: 'face_ref_1',
        vertices: [CadPoint3D(0, 0, 0), CadPoint3D(40, 0, 0), CadPoint3D(40, 30, 0), CadPoint3D(0, 30, 0)],
        normal: CadPoint3D(0, 0, 1),
      );
      final projFaceEdges = vm.project3DFaceToActivePlane(poly);
      expect(projFaceEdges.length, 4);
      for (final e in projFaceEdges) {
        expect(e.isProjected, isTrue);
        expect(e.sourceEntityId?.contains('face_ref_1'), isTrue);
      }

      // Exit projection mode
      vm.exitProjectGeometryMode();
      expect(vm.isProjectGeometryMode, isFalse);
    });

    testWidgets('AssemblySketchPalette displays controls, toggles, and fires actions', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblySketchPalette(viewModel: vm)]),
          ),
        ),
      );

      expect(find.text('SKETCH PALETTE'), findsOneWidget);
      expect(find.text('XY Top Plane'), findsOneWidget);
      expect(find.text('Look At'), findsOneWidget);
      expect(find.text('Project Geometry'), findsOneWidget);
      expect(find.text('Construction: OFF'), findsOneWidget);
      expect(find.text('Sketch Grid'), findsOneWidget);
      expect(find.text('Snap to Grid'), findsOneWidget);
      expect(find.text('Show Constraints'), findsOneWidget);
      expect(find.text('Show Dimensions'), findsOneWidget);
      expect(find.text('Show Profile'), findsOneWidget);
      expect(find.text('Finish Sketch'), findsOneWidget);

      // Tap Project Geometry
      await tester.tap(find.text('Project Geometry'));
      await tester.pumpAndSettle();
      expect(vm.isProjectGeometryMode, isTrue);
      expect(find.text('Projecting (Active)'), findsOneWidget);

      // Tap Construction
      await tester.tap(find.text('Construction: OFF'));
      await tester.pumpAndSettle();
      expect(vm.isSketchConstructionMode, isTrue);
      expect(find.text('Construction: ON'), findsOneWidget);

      // Tap Finish Sketch
      await tester.tap(find.text('Finish Sketch'));
      await tester.pumpAndSettle();
      expect(vm.isSketchMode, isFalse);
    });

    testWidgets('AssemblySketchHud displays Project (P) and Construction (X) interactive chips', (tester) async {
      tester.view.physicalSize = const Size(2560, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblySketchHud(viewModel: vm)]),
          ),
        ),
      );

      expect(find.text('Project (P)'), findsOneWidget);
      expect(find.text('Construction (X)'), findsOneWidget);

      // Tap Project chip
      await tester.tap(find.text('Project (P)'));
      await tester.pumpAndSettle();
      expect(vm.isProjectGeometryMode, isTrue);

      // Tap Construction chip
      await tester.tap(find.text('Construction (X)'));
      await tester.pumpAndSettle();
      expect(vm.isSketchConstructionMode, isTrue);
    });
  });

  group('Phase 3: Parametric 2D Primitives & Interactive Drawing', () {
    test('CADCenterRectangleEntity generates 4 boundary segments and 2 diagonal construction lines', () {
      final rect = CADCenterRectangleEntity(id: 'cr_1', center: const Offset(50.0, 50.0), width: 40.0, height: 20.0, hasDiagonalConstruction: true);

      final segs = rect.toLineSegments();
      expect(segs.length, 6);

      // 4 boundary lines
      final boundarySegs = segs.where((s) => !s.isConstruction).toList();
      expect(boundarySegs.length, 4);

      // 2 diagonal construction lines
      final diagSegs = segs.where((s) => s.isConstruction).toList();
      expect(diagSegs.length, 2);

      // Verify corners: (30, 40), (70, 40), (70, 60), (30, 60)
      expect(boundarySegs[0].start, const Offset(30.0, 40.0));
      expect(boundarySegs[0].end, const Offset(70.0, 40.0));
      expect(boundarySegs[1].start, const Offset(70.0, 40.0));
      expect(boundarySegs[1].end, const Offset(70.0, 60.0));
      expect(boundarySegs[2].start, const Offset(70.0, 60.0));
      expect(boundarySegs[2].end, const Offset(30.0, 60.0));
      expect(boundarySegs[3].start, const Offset(30.0, 60.0));
      expect(boundarySegs[3].end, const Offset(30.0, 40.0));

      // Diagonals connect opposite corners through center
      expect(diagSegs[0].start, const Offset(30.0, 40.0));
      expect(diagSegs[0].end, const Offset(70.0, 60.0));
      expect(diagSegs[1].start, const Offset(30.0, 60.0));
      expect(diagSegs[1].end, const Offset(70.0, 40.0));
    });

    test('CADProfileValidator succeeds on CADCenterRectangleEntity ignoring diagonal construction cross', () {
      final rect = CADCenterRectangleEntity(id: 'cr_2', center: const Offset(0.0, 0.0), width: 60.0, height: 40.0, hasDiagonalConstruction: true);

      final segs = rect.toLineSegments();
      final result = CADProfileValidator.validateProfile(segs);

      expect(result.isValidClosedLoop, isTrue);
      expect(result.orderedPathVertices.length, greaterThanOrEqualTo(4));
    });

    test('CADArcEntity accurately computes circumcircle center, radius, and sweep', () {
      // Circle centered at (10, 0) with radius 10:
      // Start at (0, 0), apex at (10, 10), end at (20, 0)
      final arc = CADArcEntity(id: 'arc_1', startPoint: const Offset(0.0, 0.0), endPoint: const Offset(20.0, 0.0), pointOnArc: const Offset(10.0, 10.0));

      final geom = arc.computeCircumcircle();
      expect(geom, isNotNull);
      expect(geom!.center.dx, closeTo(10.0, 1e-4));
      expect(geom.center.dy, closeTo(0.0, 1e-4));
      expect(geom.radius, closeTo(10.0, 1e-4));

      // Discretized segments (semicircle sweep = pi => 12 steps)
      final segs = arc.toLineSegments();
      expect(segs.length, 12);
      expect(segs.first.start.dx, closeTo(0.0, 1e-3));
      expect(segs.first.start.dy, closeTo(0.0, 1e-3));
      expect(segs.last.end.dx, closeTo(20.0, 1e-3));
      expect(segs.last.end.dy, closeTo(0.0, 1e-3));
    });

    test('CADArcEntity gracefully handles collinear points fallback', () {
      final collinearArc = CADArcEntity(
        id: 'arc_collinear',
        startPoint: const Offset(0.0, 0.0),
        endPoint: const Offset(30.0, 0.0),
        pointOnArc: const Offset(15.0, 0.0),
      );

      final geom = collinearArc.computeCircumcircle();
      expect(geom, isNull);

      final segs = collinearArc.toLineSegments();
      expect(segs.length, 1);
      expect(segs.first.start, const Offset(0.0, 0.0));
      expect(segs.first.end, const Offset(30.0, 0.0));
    });

    test('AssemblyStudioViewModel multi-step interactive drawing and cancellation', () {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      expect(vm.sketchInteractiveStartPoint, isNull);
      expect(vm.sketchInteractiveMidPoint, isNull);
      expect(vm.sketchPolylinePoints, isEmpty);

      // 1. Interactive step 1
      vm.setInteractiveSketchStart(const Offset(10.0, 20.0));
      expect(vm.sketchInteractiveStartPoint, const Offset(10.0, 20.0));

      // 2. Interactive step 2
      vm.setInteractiveSketchMid(const Offset(30.0, 40.0));
      expect(vm.sketchInteractiveMidPoint, const Offset(30.0, 40.0));

      // 3. Polyline points
      vm.addSketchPolylinePoint(const Offset(5.0, 5.0));
      vm.addSketchPolylinePoint(const Offset(15.0, 5.0));
      expect(vm.sketchPolylinePoints.length, 2);

      // 4. Switching tools resets interactive drawing state
      vm.setActiveSketchTool('arc_3point');
      expect(vm.sketchInteractiveStartPoint, isNull);
      expect(vm.sketchInteractiveMidPoint, isNull);
      expect(vm.sketchPolylinePoints, isEmpty);
      expect(vm.activeSketchTool, 'arc_3point');

      // 5. Explicit clear
      vm.setInteractiveSketchStart(const Offset(100.0, 100.0));
      vm.clearSketchInteractiveState();
      expect(vm.sketchInteractiveStartPoint, isNull);
    });

    test('AssemblyStudioViewModel parametric dimension updating for Center Rect and 3-Pt Arc', () {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final centerRect = CADCenterRectangleEntity(id: 'cr_edit', center: const Offset(20.0, 20.0), width: 30.0, height: 20.0);
      vm.addPrimitiveEntityToActivePlane(centerRect);
      vm.selectSketchPrimitive(centerRect);

      // Edit center rect dimensions
      vm.updateSelectedPrimitiveDimensions(position: const Offset(25.0, 30.0), width: 50.0, height: 35.0);
      expect(centerRect.center, const Offset(25.0, 30.0));
      expect(centerRect.width, 50.0);
      expect(centerRect.height, 35.0);

      // Add and edit Arc
      final arc = CADArcEntity(id: 'arc_edit', startPoint: const Offset(0.0, 0.0), endPoint: const Offset(20.0, 0.0), pointOnArc: const Offset(10.0, 10.0));
      vm.addPrimitiveEntityToActivePlane(arc);
      vm.selectSketchPrimitive(arc);

      vm.updateSelectedPrimitiveDimensions(radius: 15.0);
      // New apex point adjusted to fit radius 15
      final newGeom = arc.computeCircumcircle();
      expect(newGeom, isNotNull);
      expect(newGeom!.radius, closeTo(15.0, 0.2));
    });

    testWidgets('AssemblySketchHud displays Center Rect and 3-Pt Arc tool chips and switches tools', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblySketchHud(viewModel: vm)]),
          ),
        ),
      );

      expect(find.text('Center Rect'), findsOneWidget);
      expect(find.text('3-Pt Arc (A)'), findsOneWidget);

      // Tap Center Rect chip
      await tester.tap(find.text('Center Rect'));
      await tester.pumpAndSettle();
      expect(vm.activeSketchTool, 'center_rect');

      // Tap 3-Pt Arc chip
      await tester.tap(find.text('3-Pt Arc (A)'));
      await tester.pumpAndSettle();
      expect(vm.activeSketchTool, 'arc_3point');
    });

    testWidgets('AssemblySketchParameterPanel renders center rectangle inputs when selected', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final centerRect = CADCenterRectangleEntity(id: 'cr_panel', center: const Offset(15.0, 25.0), width: 60.0, height: 40.0);
      vm.addPrimitiveEntityToActivePlane(centerRect);
      vm.selectSketchPrimitive(centerRect);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblySketchParameterPanel(viewModel: vm)]),
          ),
        ),
      );

      expect(find.text('Construction (Q)'), findsOneWidget);
      expect(find.text('Dimension (D)'), findsOneWidget);
      expect(find.text('Extrude (E)'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('AssemblySketchParameterPanel renders 3-point arc inputs when selected', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final arc = CADArcEntity(id: 'arc_panel', startPoint: const Offset(0.0, 0.0), endPoint: const Offset(20.0, 0.0), pointOnArc: const Offset(10.0, 10.0));
      vm.addPrimitiveEntityToActivePlane(arc);
      vm.selectSketchPrimitive(arc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblySketchParameterPanel(viewModel: vm)]),
          ),
        ),
      );

      expect(find.text('Construction (Q)'), findsOneWidget);
      expect(find.text('Dimension (D)'), findsOneWidget);
      expect(find.text('Extrude (E)'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });
  });

  group('Phase 4: Geometric Constraints & Degree of Freedom (DOF) Solver', () {
    test('AssemblySketchConstraintSolver calculates initial Degrees of Freedom correctly', () {
      final line = CADLineEntity(id: 'l1', start: const Offset(0, 0), end: const Offset(10, 10));
      final circle = CADCircleEntity(id: 'c1', center: const Offset(20, 20), radius: 15);
      final arc = CADArcEntity(id: 'a1', startPoint: const Offset(0, 0), endPoint: const Offset(20, 0), pointOnArc: const Offset(10, 10));
      final rect = CADRectangleEntity(id: 'r1', startPoint: const Offset(0, 0), width: 30, height: 20);
      final poly = CADPolylineEntity(id: 'p1', points: [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)]);
      final proj = CADLineEntity(id: 'proj1', start: const Offset(0, 0), end: const Offset(20, 0), isProjected: true);

      expect(AssemblySketchConstraintSolver.computeInitialDof(line), equals(4));
      expect(AssemblySketchConstraintSolver.computeInitialDof(circle), equals(3));
      expect(AssemblySketchConstraintSolver.computeInitialDof(arc), equals(5));
      expect(AssemblySketchConstraintSolver.computeInitialDof(rect), equals(4));
      expect(AssemblySketchConstraintSolver.computeInitialDof(poly), equals(6));
      expect(AssemblySketchConstraintSolver.computeInitialDof(proj), equals(0));
    });

    test('Horizontal constraint snaps line endpoints to average Y and reduces DOFs', () {
      final line = CADLineEntity(id: 'line_h', start: const Offset(10, 5), end: const Offset(50, 25));
      final plane = CADSketchPlane(id: 'plane_h', origin: vm_math.Vector3.zero(), normal: vm_math.Vector3(0, 0, 1), up: vm_math.Vector3(0, 1, 0));
      plane.primitives.add(line);
      plane.constraints.add(CadConstraint(id: 'c_h', type: CadConstraintType.horizontal, entityIds: [line.id]));

      final result = AssemblySketchConstraintSolver.solve(plane);

      expect(result.isSuccess, isTrue);
      expect(line.start.dy, closeTo(15.0, 1e-4));
      expect(line.end.dy, closeTo(15.0, 1e-4));
      expect(result.totalDegreesOfFreedom, equals(3));
      expect(line.isFullyConstrained, isFalse);
    });

    test('Vertical constraint snaps line endpoints to average X and reduces DOFs', () {
      final line = CADLineEntity(id: 'line_v', start: const Offset(10, 5), end: const Offset(20, 45));
      final plane = CADSketchPlane(id: 'plane_v', origin: vm_math.Vector3.zero(), normal: vm_math.Vector3(0, 0, 1), up: vm_math.Vector3(0, 1, 0));
      plane.primitives.add(line);
      plane.constraints.add(CadConstraint(id: 'c_v', type: CadConstraintType.vertical, entityIds: [line.id]));

      final result = AssemblySketchConstraintSolver.solve(plane);

      expect(result.isSuccess, isTrue);
      expect(line.start.dx, closeTo(15.0, 1e-4));
      expect(line.end.dx, closeTo(15.0, 1e-4));
      expect(result.totalDegreesOfFreedom, equals(3));
    });

    test('Parallel constraint aligns slope of target line to reference line', () {
      final refLine = CADLineEntity(id: 'ref', start: const Offset(0, 0), end: const Offset(100, 0));
      final targetLine = CADLineEntity(id: 'tgt', start: const Offset(10, 10), end: const Offset(30, 40));
      final plane = CADSketchPlane(id: 'plane_par', origin: vm_math.Vector3.zero(), normal: vm_math.Vector3(0, 0, 1), up: vm_math.Vector3(0, 1, 0));
      plane.primitives.addAll([refLine, targetLine]);
      plane.constraints.add(CadConstraint(id: 'c_par', type: CadConstraintType.parallel, entityIds: [refLine.id, targetLine.id]));

      final result = AssemblySketchConstraintSolver.solve(plane);

      expect(result.isSuccess, isTrue);
      expect(targetLine.start.dy, closeTo(targetLine.end.dy, 1e-4));
    });

    test('Perpendicular constraint aligns target line at 90 degrees to reference line', () {
      final refLine = CADLineEntity(id: 'ref_p', start: const Offset(0, 0), end: const Offset(100, 0));
      final targetLine = CADLineEntity(id: 'tgt_p', start: const Offset(20, 10), end: const Offset(50, 40));
      final plane = CADSketchPlane(id: 'plane_perp', origin: vm_math.Vector3.zero(), normal: vm_math.Vector3(0, 0, 1), up: vm_math.Vector3(0, 1, 0));
      plane.primitives.addAll([refLine, targetLine]);
      plane.constraints.add(CadConstraint(id: 'c_perp', type: CadConstraintType.perpendicular, entityIds: [refLine.id, targetLine.id]));

      final result = AssemblySketchConstraintSolver.solve(plane);

      expect(result.isSuccess, isTrue);
      expect(targetLine.start.dx, closeTo(targetLine.end.dx, 1e-4));
    });

    test('Concentric and Equal constraints align circle centers and match radii', () {
      final c1 = CADCircleEntity(id: 'c1', center: const Offset(10, 10), radius: 25);
      final c2 = CADCircleEntity(id: 'c2', center: const Offset(50, 50), radius: 40);
      final plane = CADSketchPlane(id: 'plane_circles', origin: vm_math.Vector3.zero(), normal: vm_math.Vector3(0, 0, 1), up: vm_math.Vector3(0, 1, 0));
      plane.primitives.addAll([c1, c2]);
      plane.constraints.addAll([
        CadConstraint(id: 'c_conc', type: CadConstraintType.concentric, entityIds: [c1.id, c2.id]),
        CadConstraint(id: 'c_eq', type: CadConstraintType.equal, entityIds: [c1.id, c2.id]),
      ]);

      final result = AssemblySketchConstraintSolver.solve(plane);

      expect(result.isSuccess, isTrue);
      expect(c2.center.dx, closeTo(10.0, 1e-4));
      expect(c2.center.dy, closeTo(10.0, 1e-4));
      expect(c2.radius, closeTo(25.0, 1e-4));
    });

    test('Coincident constraint snaps start point of target to closest endpoint of reference', () {
      final l1 = CADLineEntity(id: 'l1', start: const Offset(0, 0), end: const Offset(50, 0));
      final l2 = CADLineEntity(id: 'l2', start: const Offset(52, 2), end: const Offset(80, 40));
      final plane = CADSketchPlane(id: 'plane_coinc', origin: vm_math.Vector3.zero(), normal: vm_math.Vector3(0, 0, 1), up: vm_math.Vector3(0, 1, 0));
      plane.primitives.addAll([l1, l2]);
      plane.constraints.add(CadConstraint(id: 'c_coinc', type: CadConstraintType.coincident, entityIds: [l1.id, l2.id]));

      final result = AssemblySketchConstraintSolver.solve(plane);

      expect(result.isSuccess, isTrue);
      expect(l2.start.dx, closeTo(50.0, 1e-4));
      expect(l2.start.dy, closeTo(0.0, 1e-4));
    });

    test('Fixed constraint eliminates all DOFs and marks entity as fully constrained (Black)', () {
      final line = CADLineEntity(id: 'l_fix', start: const Offset(10, 10), end: const Offset(60, 10));
      final plane = CADSketchPlane(id: 'plane_fix', origin: vm_math.Vector3.zero(), normal: vm_math.Vector3(0, 0, 1), up: vm_math.Vector3(0, 1, 0));
      plane.primitives.add(line);
      plane.constraints.add(CadConstraint(id: 'c_fix', type: CadConstraintType.fixed, entityIds: [line.id]));

      final result = AssemblySketchConstraintSolver.solve(plane);

      expect(result.isSuccess, isTrue);
      expect(result.totalDegreesOfFreedom, equals(0));
      expect(result.isFullyConstrained, isTrue);
      expect(line.isFullyConstrained, isTrue);
    });

    test('ViewModel applySketchConstraint and removeSketchConstraint update state', () {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final line = CADLineEntity(id: 'vm_line', start: const Offset(0, 0), end: const Offset(50, 20));
      vm.addPrimitiveEntityToActivePlane(line);
      expect(vm.sketchDegreesOfFreedom, equals(4));
      expect(vm.isSketchFullyConstrained, isFalse);

      // Select and apply horizontal constraint
      vm.selectSketchPrimitive(line);
      vm.applySketchConstraint(CadConstraintType.horizontal, targetEntityIds: [line.id]);

      expect(vm.activeSketchPlane!.constraints.length, equals(1));
      expect(vm.sketchDegreesOfFreedom, equals(3));
      expect(line.start.dy, closeTo(line.end.dy, 1e-4));

      // Remove constraint
      final constraintId = vm.activeSketchPlane!.constraints.first.id;
      vm.removeSketchConstraint(constraintId);

      expect(vm.activeSketchPlane!.constraints.isEmpty, isTrue);
      expect(vm.sketchDegreesOfFreedom, equals(4));
    });

    testWidgets('AssemblySketchPalette renders DOF status banner and active constraints', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final line = CADLineEntity(id: 'p_line', start: const Offset(0, 0), end: const Offset(50, 0));
      vm.addPrimitiveEntityToActivePlane(line);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblySketchPalette(viewModel: vm)]),
          ),
        ),
      );

      expect(find.textContaining('Under-constrained: 4 DOFs (Blue)'), findsOneWidget);

      // Apply fixed constraint -> Fully Constrained
      vm.applySketchConstraint(CadConstraintType.fixed, targetEntityIds: [line.id]);
      await tester.pumpAndSettle();

      expect(find.text('Fully Constrained (Black)'), findsOneWidget);
      expect(find.text('ACTIVE CONSTRAINTS'), findsOneWidget);
      expect(find.text('Fixed'), findsOneWidget);
    });

    testWidgets('AssemblySketchHud renders geometric constraint chips and triggers action', (tester) async {
      tester.view.physicalSize = const Size(2800, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final line = CADLineEntity(id: 'hud_line', start: const Offset(10, 5), end: const Offset(60, 25));
      vm.addPrimitiveEntityToActivePlane(line);
      vm.selectSketchPrimitive(line);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblySketchHud(viewModel: vm)]),
          ),
        ),
      );

      expect(find.text('H'), findsOneWidget);
      expect(find.text('H/V'), findsOneWidget);
      expect(find.text('•'), findsOneWidget);
      expect(find.text('//'), findsOneWidget);
      expect(find.text('⊥'), findsOneWidget);
      expect(find.text('='), findsOneWidget);
      expect(find.text('◎'), findsOneWidget);
      expect(find.text('🔒'), findsOneWidget);

      // Tap H/V chip
      await tester.ensureVisible(find.text('H/V'));
      await tester.tap(find.text('H/V'));
      await tester.pumpAndSettle();

      expect(vm.activeSketchPlane!.constraints.length, equals(1));
      expect(line.start.dy, closeTo(line.end.dy, 1e-4));
    });
  });

  group('Phase 5: 3D Feature Extrusion & Boolean Operations', () {
    test('AssemblyExtrudeEngine.generateExtrudedSolid One-Side creates watertight solid with top, bottom and side quads', () {
      final plane = AssemblySurfaceSketchEngine.createDatumPlane('XY');
      final loop = [const Offset(0, 0), const Offset(50, 0), const Offset(50, 30), const Offset(0, 30)];

      final solid = AssemblyExtrudeEngine.generateExtrudedSolid(
        plane: plane,
        profilePoints: loop,
        params: const AssemblyExtrudeParams(distanceMm: 25.0, direction: AssemblyExtrudeDirection.oneSide),
      );

      expect(solid.isEmpty, isFalse);
      expect(solid.volumeMm3, closeTo(37500.0, 1e-3));
      expect(solid.boundWidth, closeTo(50.0, 1e-3));
      expect(solid.boundLength, closeTo(30.0, 1e-3));
      expect(solid.boundHeight, closeTo(25.0, 1e-3));
      expect(solid.centroid.x, closeTo(25.0, 1e-3));
      expect(solid.centroid.y, closeTo(15.0, 1e-3));
      expect(solid.centroid.z, closeTo(12.5, 1e-3));

      // 2 top triangles + 2 bottom triangles + 8 side wall triangles = 12
      expect(solid.polygons.length, equals(12));

      // Top cap face normal should align with plane normal +Z
      final topFaces = solid.polygons.where((p) => p.faceId.startsWith('extrude_top_cap')).toList();
      expect(topFaces.length, equals(2));
      expect(topFaces.first.normal.z, closeTo(1.0, 1e-4));

      // Bottom cap face normal should align with -Z
      final botFaces = solid.polygons.where((p) => p.faceId.startsWith('extrude_bot_cap')).toList();
      expect(botFaces.length, equals(2));
      expect(botFaces.first.normal.z, closeTo(-1.0, 1e-4));
    });

    test('AssemblyExtrudeEngine.generateExtrudedSolid Symmetric and Two-Side directions calculate correct extents', () {
      final plane = AssemblySurfaceSketchEngine.createDatumPlane('XY');
      final loop = [const Offset(0, 0), const Offset(20, 0), const Offset(20, 20), const Offset(0, 20)];

      // Symmetric 15mm => Total height = 30mm (-15 to +15)
      final symSolid = AssemblyExtrudeEngine.generateExtrudedSolid(
        plane: plane,
        profilePoints: loop,
        params: const AssemblyExtrudeParams(distanceMm: 15.0, direction: AssemblyExtrudeDirection.symmetric),
      );

      expect(symSolid.boundHeight, closeTo(30.0, 1e-3));
      expect(symSolid.volumeMm3, closeTo(12000.0, 1e-3));
      expect(symSolid.centroid.z, closeTo(0.0, 1e-3));

      // Two-Side 20mm and 10mm => Total height = 30mm (-10 to +20)
      final twoSolid = AssemblyExtrudeEngine.generateExtrudedSolid(
        plane: plane,
        profilePoints: loop,
        params: const AssemblyExtrudeParams(distanceMm: 20.0, distanceSide2Mm: 10.0, direction: AssemblyExtrudeDirection.twoSide),
      );

      expect(twoSolid.boundHeight, closeTo(30.0, 1e-3));
      expect(twoSolid.volumeMm3, closeTo(12000.0, 1e-3));
      expect(twoSolid.centroid.z, closeTo(5.0, 1e-3));
    });

    test('AssemblyExtrudeEngine.generateExtrudedSolid applies Taper Angle and handles degenerate loop gracefully', () {
      final plane = AssemblySurfaceSketchEngine.createDatumPlane('XY');
      final loop = [const Offset(0, 0), const Offset(40, 0), const Offset(40, 40), const Offset(0, 40)];

      // Taper angle +15 degrees
      final taperedSolid = AssemblyExtrudeEngine.generateExtrudedSolid(
        plane: plane,
        profilePoints: loop,
        params: const AssemblyExtrudeParams(distanceMm: 50.0, taperAngleDeg: 15.0),
      );

      expect(taperedSolid.boundWidth, greaterThan(40.0));
      expect(taperedSolid.polygons.length, equals(12));

      // Degenerate loop (< 3 points)
      final emptySolid = AssemblyExtrudeEngine.generateExtrudedSolid(
        plane: plane,
        profilePoints: [const Offset(0, 0), const Offset(10, 0)],
        params: const AssemblyExtrudeParams(),
      );

      expect(emptySolid.isEmpty, isTrue);
      expect(emptySolid.polygons, isEmpty);
      expect(emptySolid.volumeMm3, equals(0.0));
    });

    test('AssemblyExtrudeEngine.executeExtrusion executes New Body, Join, and Cut operations', () {
      final vm = AssemblyStudioViewModel();
      final plane = AssemblySurfaceSketchEngine.createDatumPlane('XY');
      final loop = [const Offset(0, 0), const Offset(50, 0), const Offset(50, 50), const Offset(0, 50)];

      // 1. New Body
      final newBodyResult = AssemblyExtrudeEngine.executeExtrusion(
        doc: vm.doc,
        plane: plane,
        profilePoints: loop,
        params: const AssemblyExtrudeParams(distanceMm: 20.0, operation: AssemblyExtrudeOperation.newBody),
      );

      expect(newBodyResult.isSuccess, isTrue);
      expect(newBodyResult.createdPart, isNotNull);
      expect(newBodyResult.createdPart!.type, equals(AssemblyPartType.customExtrusion));
      expect(newBodyResult.createdPart!.customPolygons, isNotNull);
      expect(newBodyResult.createdPart!.customPolygons!.length, equals(12));
      expect(vm.doc.parts.contains(newBodyResult.createdPart!), isTrue);

      // 2. Join
      final targetPart = newBodyResult.createdPart!;
      final initialPolyCount = targetPart.customPolygons!.length;
      final joinResult = AssemblyExtrudeEngine.executeExtrusion(
        doc: vm.doc,
        plane: plane,
        profilePoints: loop,
        params: const AssemblyExtrudeParams(distanceMm: 10.0, operation: AssemblyExtrudeOperation.join),
        targetPart: targetPart,
      );

      expect(joinResult.isSuccess, isTrue);
      expect(targetPart.customPolygons!.length, equals(initialPolyCount + 12));

      // 3. Cut
      final cutResult = AssemblyExtrudeEngine.executeExtrusion(
        doc: vm.doc,
        plane: plane,
        profilePoints: loop,
        params: const AssemblyExtrudeParams(distanceMm: 5.0, operation: AssemblyExtrudeOperation.cut),
        targetPart: targetPart,
      );

      expect(cutResult.isSuccess, isTrue);
      expect(cutResult.cutFeature, isNotNull);
      expect(cutResult.cutFeature!.featureType, equals('extruded_cut'));
      expect(cutResult.cutFeature!.cutDepthMm, equals(5.0));
      expect(targetPart.sketches.contains(cutResult.cutFeature!), isTrue);
    });

    test('AssemblyStudioViewModel extrusion interactive workflow, parameters, and undo', () {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final rect = CADCenterRectangleEntity(id: 'extrude_rect', center: const Offset(50, 50), width: 40, height: 30, hasDiagonalConstruction: false);
      vm.addPrimitiveEntityToActivePlane(rect);
      vm.selectSketchPrimitive(rect);

      // Open Extrude Dialog
      vm.openExtrudeDialog();
      expect(vm.isExtrudeMode, isTrue);
      expect(vm.extrudeParams.profileEntityIds, contains('extrude_rect'));

      // Update parameters
      vm.updateExtrudeDistance(35.0);
      expect(vm.extrudeParams.distanceMm, equals(35.0));

      vm.updateExtrudeParams(vm.extrudeParams.copyWith(operation: AssemblyExtrudeOperation.newBody, direction: AssemblyExtrudeDirection.oneSide));

      final initialPartsCount = vm.doc.parts.length;

      // Execute Extrusion
      vm.executeExtrudeFeature();
      expect(vm.isExtrudeMode, isFalse);
      expect(vm.doc.parts.length, equals(initialPartsCount + 1));
      expect(vm.doc.parts.last.type, equals(AssemblyPartType.customExtrusion));
      expect(vm.canUndo, isTrue);

      // Undo reverts the created body
      vm.undo();
      expect(vm.doc.parts.length, equals(initialPartsCount));
    });

    testWidgets('AssemblyExtrudeDialog renders operation chips, inputs, and triggers extrude', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');
      final rect = CADCenterRectangleEntity(id: 'dialog_rect', center: const Offset(40, 40), width: 30, height: 20, hasDiagonalConstruction: false);
      vm.addPrimitiveEntityToActivePlane(rect);
      vm.openExtrudeDialog();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(children: [AssemblyExtrudeDialog(viewModel: vm)]),
          ),
        ),
      );

      expect(find.text('EXTRUDE'), findsOneWidget);
      expect(find.text('New Body'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Intersect'), findsOneWidget);
      expect(find.text('One Side'), findsOneWidget);
      expect(find.text('Symmetric'), findsOneWidget);
      expect(find.text('Two Sides'), findsOneWidget);
      expect(find.text('Extrude (E)'), findsOneWidget);

      // Tap Cut chip
      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();
      expect(vm.extrudeParams.operation, equals(AssemblyExtrudeOperation.cut));

      // Tap Extrude (E) button
      await tester.tap(find.text('Extrude (E)'));
      await tester.pumpAndSettle();
      expect(vm.isExtrudeMode, isFalse);
    });

    testWidgets('AssemblySketchHud and AssemblySketchPalette toggle Extrude mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(top: 14, left: 14, right: 14, child: AssemblySketchHud(viewModel: vm)),
                AssemblySketchPalette(viewModel: vm),
              ],
            ),
          ),
        ),
      );

      // Verify buttons
      expect(find.text('Extrude (E)'), findsOneWidget);
      expect(find.text('Extrude Profile (E)'), findsOneWidget);

      // Tap Extrude in HUD
      await tester.ensureVisible(find.text('Extrude (E)'));
      await tester.tap(find.text('Extrude (E)'));
      await tester.pumpAndSettle();
      expect(vm.isExtrudeMode, isTrue);

      // Tap Extrude Profile (E) in Palette to toggle off
      await tester.ensureVisible(find.text('Extrude Profile (E)'));
      await tester.tap(find.text('Extrude Profile (E)'));
      await tester.pumpAndSettle();
      expect(vm.isExtrudeMode, isFalse);
    });
  });

  group('Phase 6: Assembly Browser Tree, Parametric Timeline & Settings', () {
    test('Parametric Timeline: Recording features and Rollback suppression', () {
      final vm = AssemblyStudioViewModel();
      vm.clearAll();
      expect(vm.timelineItems, isEmpty);
      expect(vm.timelineRollbackIndex, 0);

      // 1. Record Construction Plane
      final plane = vm.addOffsetConstructionPlane(
        parentPlaneId: 'datum_xy',
        offsetMm: 30.0,
        name: 'WorkPlane 1',
      );
      expect(vm.timelineItems.length, 1);
      expect(vm.timelineItems.first.type, AssemblyTimelineFeatureType.constructionPlane);
      expect(vm.timelineItems.first.name, 'WorkPlane 1');

      // 2. Record Sketch
      vm.activateSketchOnDatum('XY');
      vm.addPrimitiveEntityToActivePlane(
        CADCenterRectangleEntity(
          id: 'rect_p6',
          center: Offset.zero,
          width: 50.0,
          height: 30.0,
        ),
      );
      vm.finishSketch();
      expect(vm.timelineItems.length, 2);
      expect(vm.timelineItems[1].type, AssemblyTimelineFeatureType.sketch);

      // 3. Record Extrude
      vm.updateExtrudeParams(vm.extrudeParams.copyWith(operation: AssemblyExtrudeOperation.newBody, distanceMm: 20.0));
      vm.executeExtrudeFeature();
      expect(vm.timelineItems.length, 3);
      expect(vm.timelineItems[2].type, AssemblyTimelineFeatureType.extrude);

      // Verify no suppression initially
      expect(vm.timelineItems[0].isSuppressed, isFalse);
      expect(vm.timelineItems[1].isSuppressed, isFalse);
      expect(vm.timelineItems[2].isSuppressed, isFalse);
      expect(plane.isVisible, isTrue);
      expect(vm.doc.parts.isNotEmpty, isTrue);
      expect(vm.doc.parts.last.isVisible, isTrue);

      // 4. Rollback Stepping Back (2 active: 0 and 1, feature 2 suppressed)
      vm.rollbackStepBack();
      expect(vm.timelineRollbackIndex, 2);
      expect(vm.timelineItems[2].isSuppressed, isTrue);
      expect(vm.timelineItems[1].isSuppressed, isFalse);
      expect(vm.doc.parts.last.isVisible, isFalse);

      // 5. Rollback to Start (0 active: all suppressed)
      vm.rollbackToStart();
      expect(vm.timelineRollbackIndex, 0);
      expect(vm.timelineItems[0].isSuppressed, isTrue);
      expect(plane.isVisible, isFalse);
      expect(vm.doc.parts.last.isVisible, isFalse);

      // 6. Rollback Step Forward (1 feature active: plane active, sketch & extrude suppressed)
      vm.rollbackStepForward();
      expect(vm.timelineRollbackIndex, 1);
      expect(vm.timelineItems[0].isSuppressed, isFalse);
      expect(plane.isVisible, isTrue);
      expect(vm.timelineItems[1].isSuppressed, isTrue);
      expect(vm.doc.parts.last.isVisible, isFalse);

      // 7. Rollback to End (All restored)
      vm.rollbackToEnd();
      expect(vm.timelineRollbackIndex, 3);
      expect(vm.timelineItems[0].isSuppressed, isFalse);
      expect(vm.timelineItems[1].isSuppressed, isFalse);
      expect(vm.timelineItems[2].isSuppressed, isFalse);
      expect(plane.isVisible, isTrue);
      expect(vm.doc.parts.last.isVisible, isTrue);
    });

    test('CAD Settings: units, grid snapping, and dialog toggle updates', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.cadSettings.isImperial, isFalse);
      expect(vm.cadSettings.gridSnapMm, 5.0);

      // Update settings
      vm.updateCadSettings(
        vm.cadSettings.copyWith(
          isImperial: true,
          gridSnapMm: 10.0,
          defaultExtrudeDistanceMm: 45.0,
        ),
      );
      expect(vm.cadSettings.isImperial, isTrue);
      expect(vm.cadSettings.gridSnapMm, 10.0);
      expect(vm.cadSettings.defaultExtrudeDistanceMm, 45.0);

      // Modal Dialog state
      expect(vm.isCadSettingsOpen, isFalse);
      vm.openCadSettingsDialog();
      expect(vm.isCadSettingsOpen, isTrue);
      vm.toggleCadSettingsDialog();
      expect(vm.isCadSettingsOpen, isFalse);
      vm.toggleCadSettingsDialog();
      expect(vm.isCadSettingsOpen, isTrue);
      vm.closeCadSettingsDialog();
      expect(vm.isCadSettingsOpen, isFalse);
    });

    testWidgets('AssemblyParametricTimeline renders feature chips and playback controls', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.clearAll();
      vm.addOffsetConstructionPlane(parentPlaneId: 'datum_xy', offsetMm: 20.0, name: 'WorkPlane 1');
      vm.activateSketchOnDatum('XY');
      vm.addPrimitiveEntityToActivePlane(
        CADCenterRectangleEntity(id: 'rect_p6_tl', center: Offset.zero, width: 30, height: 20),
      );
      vm.finishSketch();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  bottom: 12,
                  left: 56,
                  right: 236,
                  child: AssemblyParametricTimeline(viewModel: vm),
                ),
              ],
            ),
          ),
        ),
      );

      // Verify features present
      expect(find.textContaining('WorkPlane 1'), findsOneWidget);
      expect(find.textContaining('Sketch on XY Top Plane'), findsOneWidget);

      // Verify playback buttons
      expect(find.byTooltip('Rollback to start'), findsOneWidget);
      expect(find.byTooltip('Rollback to end'), findsOneWidget);

      // Tap Rollback to start
      await tester.tap(find.byTooltip('Rollback to start'));
      await tester.pumpAndSettle();
      expect(vm.timelineRollbackIndex, 0);

      // Tap Rollback to end
      await tester.tap(find.byTooltip('Rollback to end'));
      await tester.pumpAndSettle();
      expect(vm.timelineRollbackIndex, 2);
    });

    testWidgets('AssemblyBrowserTree renders CAD hierarchy folders and filter search', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.addOffsetConstructionPlane(parentPlaneId: 'datum_xy', offsetMm: 15.0, name: 'MidPlane');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssemblyBrowserTree(viewModel: vm, width: 250.0),
          ),
        ),
      );

      // Folder titles and elements (Onshape Features & Parts tree)
      expect(find.textContaining('Features'), findsOneWidget);
      expect(find.text('Origin'), findsOneWidget);
      expect(find.text('Top'), findsOneWidget);
      expect(find.text('Construction'), findsOneWidget);
      expect(find.text('MidPlane'), findsOneWidget);
      expect(find.text('Sketches'), findsOneWidget);
      expect(find.text('Parts'), findsOneWidget);

      // Search filter
      await tester.enterText(find.byType(TextField), 'MidPlane');
      await tester.pumpAndSettle();
      expect(find.text('MidPlane'), findsNWidgets(2));
      expect(find.text('Top'), findsNothing);
    });

    testWidgets('AssemblyCadSettingsDialog allows changing grid snapping and unit systems', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = AssemblyStudioViewModel();
      vm.openCadSettingsDialog();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: AssemblyCadSettingsDialog(viewModel: vm),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('CAD & VIEWPORT SETTINGS'), findsOneWidget);
      expect(find.text('Metric (mm / kg)'), findsOneWidget);
      expect(find.text('Imperial (in / lb)'), findsOneWidget);

      // Tap Imperial chip
      await tester.tap(find.text('Imperial (in / lb)'));
      await tester.pumpAndSettle();
      expect(vm.cadSettings.isImperial, isTrue);

      // Tap 10mm grid snap chip
      await tester.tap(find.text('10 mm'));
      await tester.pumpAndSettle();
      expect(vm.cadSettings.gridSnapMm, 10.0);

      // Close dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(vm.isCadSettingsOpen, isFalse);
    });
  });
}
