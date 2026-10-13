import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

void main() {
  group('SketchUp-Style 3-Click Rotation & Radial Arrays', () {
    late AssemblyStudioViewModel vm;
    late AssemblyPart testPart;

    setUp(() {
      vm = AssemblyStudioViewModel();
      vm.doc.parts.clear();
      testPart = AssemblyPart(
        id: 'test_rung_1',
        name: 'Test Rung',
        type: AssemblyPartType.rung,
        position: const CadPoint3D(100.0, 0.0, 0.0),
        rotationDeg: const CadPoint3D(0.0, 0.0, 0.0),
        length: 400.0,
        height: 30.0,
        flangeWidth: 30.0,
      );
      vm.doc.parts.add(testPart);
      vm.selectPart(testPart.id);
    });

    test('Oriented Bounding Box computes 8 tight world corners conforming to orientation', () {
      final corners = testPart.getOrientedBoundingBoxCorners();
      expect(corners.length, equals(8));
      // Base corner at position
      expect(corners[0].x, equals(100.0));
      expect(corners[0].y, equals(-20.0));
      expect(corners[0].z, equals(0.0));
      // End corner at position + length (400)
      expect(corners[1].x, equals(500.0));
      expect(corners[1].y, equals(-20.0));
      expect(corners[1].z, equals(0.0));
    });

    test('rotateAndCopyPart creates rotational copy around custom pivot point', () {
      final initialCount = vm.doc.parts.length;
      final copied = vm.rotateAndCopyPart(
        testPart.id,
        45.0,
        centerPoint: const CadPoint3D(0, 0, 0),
        axis: GizmoAxis.z,
      );

      expect(copied, isNotNull);
      expect(vm.doc.parts.length, equals(initialCount + 1));
      expect(copied.rotationDeg.z, equals(45.0));

      // Check position: (100, 0, 0) rotated 45 deg around (0,0,0) in Z -> (100*cos45, 100*sin45, 0)
      final expectedX = 100.0 * math.cos(math.pi / 4);
      final expectedY = 100.0 * math.sin(math.pi / 4);
      expect(copied.position.x, closeTo(expectedX, 0.01));
      expect(copied.position.y, closeTo(expectedY, 0.01));
    });

    test('radialArrayPart generates multiplied radial array (*N) around custom pivot', () {
      // Create radial array of 4 total parts at 30 deg steps around origin
      final copies = vm.radialArrayPart(
        testPart.id,
        4,
        30.0,
        centerPoint: const CadPoint3D(0, 0, 0),
        axis: GizmoAxis.z,
      );

      // radialArrayPart creates totalCount - 1 copies (i.e. 3 new parts)
      expect(copies.length, equals(3));
      expect(vm.doc.parts.length, equals(4)); // original + 3 copies

      // Verify each copy's rotation and radial distance
      for (int i = 0; i < copies.length; i++) {
        final copy = copies[i];
        final expectedDeg = (i + 1) * 30.0;
        expect(copy.rotationDeg.z, closeTo(expectedDeg, 0.01));
        // Radius should remain 100mm from origin
        final rad = math.sqrt(copy.position.x * copy.position.x + copy.position.y * copy.position.y);
        expect(rad, closeTo(100.0, 0.01));
      }
    });

    test('recordLastRotate stores pivot and axis for subsequent VCB radial array commands', () {
      const customPivot = CadPoint3D(50.0, 20.0, 0.0);
      vm.recordLastRotate(
        partId: testPart.id,
        deltaDeg: 45.0,
        centerPoint: customPivot,
        axis: GizmoAxis.z,
      );

      expect(vm.lastRotateCenterPoint, equals(customPivot));
      expect(vm.lastRotateAxis, equals(GizmoAxis.z));
      expect(vm.lastRotateDeltaDeg, equals(45.0));

      // Now enter '*3' in VCB
      vm.submitVcbInput('*3');
      // Should have generated 2 radial array copies (total 3 parts) around custom pivot
      expect(vm.doc.parts.length, equals(3));
    });

    test('divideRadialArray (/N) creates interpolated copies around custom pivot', () {
      const customPivot = CadPoint3D(0, 0, 0);
      vm.recordLastRotate(
        partId: testPart.id,
        deltaDeg: 90.0,
        centerPoint: customPivot,
        axis: GizmoAxis.z,
      );

      // Now enter '/3' in VCB -> divides 90 deg into 3 intervals (30 deg each)
      vm.submitVcbInput('/3');
      expect(vm.doc.parts.length, equals(3)); // 1 original + 2 copies at 30 and 60 deg
    });

    test('Onshape Graphics Preferences defaults and state toggles operate cleanly', () {
      expect(vm.graphicsPreferences.antiAliasingQuality, equals(AntiAliasingQuality.high));
      expect(vm.graphicsPreferences.hiddenEdgesVisible, isFalse);
      expect(vm.onshapeRenderMode, equals(OnshapeRenderMode.shadedWithEdges));

      // Toggle render mode
      vm.onshapeRenderMode = OnshapeRenderMode.shadedWithoutEdges;
      expect(vm.onshapeRenderMode, equals(OnshapeRenderMode.shadedWithoutEdges));

      // Toggle preferences
      vm.updateGraphicsPreferences((p) => p.copyWith(hiddenEdgesVisible: true));
      expect(vm.graphicsPreferences.hiddenEdgesVisible, isTrue);
    });
  });
}
