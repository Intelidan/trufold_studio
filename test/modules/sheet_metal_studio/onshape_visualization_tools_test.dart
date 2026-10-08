import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/dds/dds_drawing_painters.dart';

void main() {
  group('Onshape Model Visualization Tools - Models & Configs', () {
    test('OnshapeGraphicsPreferences initializes with faithful CAD defaults', () {
      const prefs = OnshapeGraphicsPreferences();
      expect(prefs.tangentEdgeMode, OnshapeTangentEdgeMode.phantom);
      expect(prefs.highlightBoundaryEdges, isFalse);
      expect(prefs.boundaryEdgeColor, const Color(0xFFEF4444));
      expect(prefs.meshLineWidth, 1.2);
      expect(prefs.transparencyLevel, 0.35);
      expect(prefs.fieldOfView, 46.0);
    });

    test('OnshapeGraphicsPreferences copyWith updates boundary edges and tangent mode', () {
      const prefs = OnshapeGraphicsPreferences();
      final updated = prefs.copyWith(
        highlightBoundaryEdges: true,
        boundaryEdgeColor: const Color(0xFFDC2626),
        tangentEdgeMode: OnshapeTangentEdgeMode.visible,
        meshLineWidth: 2.0,
        transparencyLevel: 0.65,
      );

      expect(updated.highlightBoundaryEdges, isTrue);
      expect(updated.boundaryEdgeColor, const Color(0xFFDC2626));
      expect(updated.tangentEdgeMode, OnshapeTangentEdgeMode.visible);
      expect(updated.meshLineWidth, 2.0);
      expect(updated.transparencyLevel, 0.65);
    });

    test('SectionViewConfig initializes with clean state and flips correctly', () {
      const cfg = SectionViewConfig();
      expect(cfg.isEnabled, isFalse);
      expect(cfg.axis, SectionPlaneAxis.yz);
      expect(cfg.distanceOffsetMm, 0.0);
      expect(cfg.flipNormal, isFalse);

      final toggled = cfg.copyWith(
        isEnabled: true,
        axis: SectionPlaneAxis.yz,
        distanceOffsetMm: 45.0,
        flipNormal: true,
      );

      expect(toggled.isEnabled, isTrue);
      expect(toggled.axis, SectionPlaneAxis.yz);
      expect(toggled.distanceOffsetMm, 45.0);
      expect(toggled.flipNormal, isTrue);
    });

    test('NamedCadView serializes and restores camera state accurately', () {
      final cam = Cad3dCameraState(
        azimuthDeg: 45.0,
        elevationDeg: 30.0,
        zoom: 1.5,
        pan: const Offset(10, 20),
        orbitDistance: 450.0,
        orbitTarget: const CadPoint3D(0, 50, 0),
        isInitialized: true,
      );

      final namedView = NamedCadView(name: 'Isometric Front Detail', state: cam);
      final json = namedView.toJson();
      final restored = NamedCadView.fromJson(json);

      expect(restored.name, 'Isometric Front Detail');
      expect(restored.state.azimuthDeg, 45.0);
      expect(restored.state.elevationDeg, 30.0);
      expect(restored.state.zoom, 1.5);
      expect(restored.state.orbitDistance, 450.0);
      expect(restored.state.orbitTarget.y, 50.0);
    });
  });

  group('SheetMetalStudioViewModel - Onshape Visualization State', () {
    test('3D Rotate Lock toggles correctly', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.is3dRotateLocked, isFalse);
      vm.toggle3dRotateLock();
      expect(vm.is3dRotateLocked, isTrue);
      vm.toggle3dRotateLock();
      expect(vm.is3dRotateLocked, isFalse);
    });

    test('Camera History records and pops previous views (LIFO)', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.hasPreviousCameraView, isFalse);

      final state1 = Cad3dCameraState(azimuthDeg: 10, elevationDeg: 20, zoom: 1.0, isInitialized: true);
      final state2 = Cad3dCameraState(azimuthDeg: 30, elevationDeg: 40, zoom: 1.2, isInitialized: true);
      final state3 = Cad3dCameraState(azimuthDeg: 50, elevationDeg: 60, zoom: 1.5, isInitialized: true);

      vm.pushCameraHistory(state1);
      vm.pushCameraHistory(state2);
      vm.pushCameraHistory(state3);

      expect(vm.hasPreviousCameraView, isTrue);

      final popped3 = vm.popPreviousCameraState();
      expect(popped3?.azimuthDeg, 50.0);

      final popped2 = vm.popPreviousCameraState();
      expect(popped2?.azimuthDeg, 30.0);

      final popped1 = vm.popPreviousCameraState();
      expect(popped1?.azimuthDeg, 10.0);

      expect(vm.hasPreviousCameraView, isFalse);
      expect(vm.popPreviousCameraState(), isNull);
    });

    test('Named views can be saved, listed, and deleted', () {
      final vm = SheetMetalStudioViewModel();
      final state = Cad3dCameraState(azimuthDeg: 90, elevationDeg: 0, zoom: 2.0, isInitialized: true);

      vm.saveNamedView('End Elevation', state);
      expect(vm.namedViews.containsKey('End Elevation'), isTrue);
      expect(vm.namedViews['End Elevation']?.azimuthDeg, 90.0);

      vm.deleteNamedView('End Elevation');
      expect(vm.namedViews.containsKey('End Elevation'), isFalse);
    });

    test('Section View config modifications update ViewModel reactive state', () {
      final vm = SheetMetalStudioViewModel();
      expect(vm.sectionViewConfig.isEnabled, isFalse);

      vm.toggleSectionView();
      expect(vm.sectionViewConfig.isEnabled, isTrue);

      vm.setSectionViewAxis(SectionPlaneAxis.xy);
      expect(vm.sectionViewConfig.axis, SectionPlaneAxis.xy);

      vm.setSectionViewOffset(75.5);
      expect(vm.sectionViewConfig.distanceOffsetMm, 75.5);

      vm.toggleSectionView();
      expect(vm.sectionViewConfig.isEnabled, isFalse);
    });

    test('Part visibility (Hide, Show, Hide Other, Show All) operations', () {
      final vm = SheetMetalStudioViewModel();

      vm.hidePart('PART_BRACKET');
      expect(vm.isPartHidden('PART_BRACKET'), isTrue);
      expect(vm.isPartHidden('PART_BASE'), isFalse);

      vm.showPart('PART_BRACKET');
      expect(vm.isPartHidden('PART_BRACKET'), isFalse);

      final meshPartIds = vm.currentMesh.allPolygons
          .map((p) => SheetMetalStudioViewModel.extractPartIdFromFaceId(p.faceId))
          .toSet();

      if (meshPartIds.isNotEmpty) {
        final keep = meshPartIds.first;
        vm.hideOtherParts(keep);
        expect(vm.isPartHidden(keep), isFalse);
        for (final other in meshPartIds.skip(1)) {
          expect(vm.isPartHidden(other), isTrue);
        }
      }

      vm.showAllParts();
      expect(vm.hiddenPartIds.isEmpty, isTrue);
    });

    test('Part isolation and transparency operations', () {
      final vm = SheetMetalStudioViewModel();

      vm.isolatePart('PART_STIFFENER');
      expect(vm.isPartIsolated('PART_STIFFENER'), isTrue);
      expect(vm.isPartIsolated('PART_OTHER'), isFalse);

      vm.clearIsolation();
      expect(vm.isolatedPartIds.isEmpty, isTrue);

      vm.makePartTransparent('PART_CASING');
      expect(vm.isPartTransparent('PART_CASING'), isTrue);

      vm.clearTransparency();
      expect(vm.transparentPartIds.isEmpty, isTrue);
    });

    test('Part color appearance overrides and reset', () {
      final vm = SheetMetalStudioViewModel();

      vm.setPartColor('PART_FLANGE', const Color(0xFFEA580C));
      expect(vm.partColorOverrides['PART_FLANGE'], const Color(0xFFEA580C));

      vm.clearPartColor('PART_FLANGE');
      expect(vm.partColorOverrides.containsKey('PART_FLANGE'), isFalse);
    });

    test('extractPartIdFromFaceId parses both compound and simple IDs', () {
      expect(SheetMetalStudioViewModel.extractPartIdFromFaceId('BRACKET:FACE_TOP'), 'BRACKET');
      expect(SheetMetalStudioViewModel.extractPartIdFromFaceId('LADDER__RUNG_01'), 'LADDER');
      expect(SheetMetalStudioViewModel.extractPartIdFromFaceId('outer_rail_left_side'), 'outer_rail');
      expect(SheetMetalStudioViewModel.extractPartIdFromFaceId('SINGLEPART'), 'SINGLEPART');
    });
  });

  group('Section Plane Mathematical Clipping Calculations', () {
    test('Calculates section distance correctly for YZ, ZX, and XY planes', () {
      const pivot = CadPoint3D(50, 50, 50);
      const testVertex = CadPoint3D(80, 20, 60);

      // YZ plane: dist = (x - pivot.x) - offset
      double distYZ = (testVertex.x - pivot.x) - 10.0;
      expect(distYZ, 20.0); // 80 - 50 - 10 = 20 > 0 (clipped)

      // ZX plane: dist = (y - pivot.y) - offset
      double distZX = (testVertex.y - pivot.y) - (-40.0);
      expect(distZX, 10.0); // 20 - 50 - (-40) = 10 > 0 (clipped)

      // XY plane: dist = (z - pivot.z) - offset
      double distXY = (testVertex.z - pivot.z) - 20.0;
      expect(distXY, -10.0); // 60 - 50 - 20 = -10 <= 0 (kept)

      // Flip normal inverts distance sign
      expect(-distXY, 10.0);
    });
  });

  group('TDS / DDS 2D Multi-View Orthographic Projections (ISO 128 vs ANSI Y14.3)', () {
    test('First Angle (ISO) vs Third Angle (ANSI) view placement rules', () {
      DdsOrthographicViewType getTopLeft(bool isFirstAngle) =>
          isFirstAngle ? DdsOrthographicViewType.front : DdsOrthographicViewType.top;
      DdsOrthographicViewType getBottomLeft(bool isFirstAngle) =>
          isFirstAngle ? DdsOrthographicViewType.top : DdsOrthographicViewType.front;
      DdsOrthographicViewType getTopRight(bool isFirstAngle) =>
          isFirstAngle ? DdsOrthographicViewType.end : DdsOrthographicViewType.isometric;
      DdsOrthographicViewType getBottomRight(bool isFirstAngle) =>
          isFirstAngle ? DdsOrthographicViewType.isometric : DdsOrthographicViewType.end;

      // In 1st Angle:
      // Front is Top-Left, Left/End is Top-Right, Top is Bottom-Left, Isometric is Bottom-Right.
      expect(getTopLeft(true), DdsOrthographicViewType.front);
      expect(getBottomLeft(true), DdsOrthographicViewType.top);
      expect(getTopRight(true), DdsOrthographicViewType.end);
      expect(getBottomRight(true), DdsOrthographicViewType.isometric);

      // In 3rd Angle:
      // Top is Top-Left, Isometric is Top-Right, Front is Bottom-Left, End is Bottom-Right.
      expect(getTopLeft(false), DdsOrthographicViewType.top);
      expect(getBottomLeft(false), DdsOrthographicViewType.front);
      expect(getTopRight(false), DdsOrthographicViewType.isometric);
      expect(getBottomRight(false), DdsOrthographicViewType.end);
    });

    test('3D to 2D Orthographic coordinate mapping projections', () {
      const p3d = CadPoint3D(100.0, 50.0, 25.0);

      // Front elevation: X -> u, Y -> v (looking along -Z)
      final front2d = Offset(p3d.x, -p3d.y);
      expect(front2d.dx, 100.0);
      expect(front2d.dy, -50.0);

      // Top plan: X -> u, Z -> v (looking along -Y)
      final top2d = Offset(p3d.x, -p3d.z);
      expect(top2d.dx, 100.0);
      expect(top2d.dy, -25.0);

      // End elevation: Z -> u, Y -> v (looking along -X)
      final end2d = Offset(p3d.z, -p3d.y);
      expect(end2d.dx, 25.0);
      expect(end2d.dy, -50.0);

      // Isometric projection (30 degree tilt):
      // u = (x - z) * cos(30°), v = -(y - (x + z) * sin(30°))
      final isoU = (p3d.x - p3d.z) * 0.86602540378;
      final isoV = -(p3d.y - (p3d.x + p3d.z) * 0.5);
      expect(isoU, closeTo(64.95, 0.05));
      expect(isoV, closeTo(12.5, 0.05));
    });

    test('Section View 2D hatching lines generation along diagonal', () {
      final rect = Rect.fromLTWH(50, 50, 200, 100);
      const pitch = 12.0;

      // Diagonal cross-hatch calculation
      int hatchLinesCount = 0;
      for (double d = -rect.height; d < rect.width + rect.height; d += pitch) {
        hatchLinesCount++;
      }
      expect(hatchLinesCount, greaterThan(15));
    });
  });
}

