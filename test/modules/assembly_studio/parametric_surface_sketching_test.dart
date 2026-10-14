import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/assembly_sketch_hud.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/assembly_sketch_parameter_panel.dart';

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
      expect(xzPlane.normal.y, closeTo(1.0, 1e-4));

      final yzPlane = AssemblySurfaceSketchEngine.createDatumPlane('YZ');
      expect(yzPlane.id, 'datum_YZ');
      expect(yzPlane.normal.x, closeTo(1.0, 1e-4));
    });

    test('createPlaneFromFacePolygon extracts origin, normal, and local projection frame', () {
      final poly = CadFoldedPolygon3D(
        faceId: 'test_face_top',
        vertices: [
          CadPoint3D(0, 50, 0),
          CadPoint3D(100, 50, 0),
          CadPoint3D(100, 50, 50),
          CadPoint3D(0, 50, 50),
        ],
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
      final rect = CADRectangleEntity(
        id: 'rect_test',
        startPoint: const Offset(10, 10),
        width: 40,
        height: 30,
      );
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

      final rect = CADRectangleEntity(
        id: 'rect_1',
        startPoint: const Offset(20, 20),
        width: 50,
        height: 30,
        isPassThrough: true,
      );
      vm.addPrimitiveEntityToActivePlane(rect);

      expect(vm.activeSketchPlane!.primitives.length, 1);
      expect(vm.selectedSketchEntity, rect);
      expect(vm.selectedSketchFeatureId, 'rect_1');

      // Update dimensions parametrically
      vm.updateSelectedPrimitiveDimensions(
        width: 80.0,
        height: 45.0,
        depthMm: 8.0,
      );

      final updated = vm.selectedSketchEntity as CADRectangleEntity;
      expect(updated.width, 80.0);
      expect(updated.height, 45.0);
      expect(updated.depthMm, 8.0);
    });

    test('executeFeatureCutOnActiveSurface punches 3D pass-through void and updates history', () {
      expect(vm.doc.parts, isNotEmpty);
      final part = vm.doc.parts.first;
      vm.focusPartAndEnterSketch(part.id);

      final rect = CADRectangleEntity(
        id: 'cut_square',
        startPoint: const Offset(10, 10),
        width: 25,
        height: 25,
        isPassThrough: true,
      );
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
          home: Scaffold(
            body: AssemblySketchHud(viewModel: vm),
          ),
        ),
      );

      expect(find.textContaining('Direct Sketch'), findsOneWidget);
      expect(find.text('Rectangle'), findsOneWidget);
      expect(find.text('Circle'), findsOneWidget);
      expect(find.text('Line'), findsOneWidget);
      expect(find.text('Polyline'), findsOneWidget);
      expect(find.text('Normal View (S)'), findsOneWidget);
      expect(find.text('Export STL'), findsOneWidget);
    });

    testWidgets('AssemblySketchParameterPanel displays parametric dimension fields and triggers cut', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.activateSketchOnDatum('XY');

      final rect = CADRectangleEntity(
        id: 'rect_ui_test',
        startPoint: const Offset(15, 25),
        width: 60,
        height: 40,
        isPassThrough: true,
      );
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

      expect(find.textContaining('PARAMETERS'), findsOneWidget);
      expect(find.text('Width (mm)'), findsOneWidget);
      expect(find.text('Height (mm)'), findsOneWidget);
      expect(find.text('PUNCH PASS-THROUGH CUT'), findsOneWidget);

      // Tap Punch Pass-Through Cut
      await tester.tap(find.text('PUNCH PASS-THROUGH CUT'));
      await tester.pumpAndSettle();

      expect(rebuildCalled, isTrue);
    });
  });
}
